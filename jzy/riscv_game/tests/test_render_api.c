/*
 * 统一渲染层 + GPU 驱动骨架的测试。
 *
 * 与 test_renderer.c 的分工：
 *   test_renderer.c  冻结的 M1 正确性基线，只测 renderer_sw.{c,h} 本身
 *   本文件           测统一层、后端分发、硬件约束校验、驱动骨架
 *
 * 核心是三路等价扫描：同一组参数分别走
 *   ① 冻结的 sw_fill_rect / sw_blit
 *   ② 统一层 + CPU 后端
 *   ③ 统一层 + 假后端（故意模拟硬件的"不裁剪"语义）
 * 三条路径画出来的整块画布（含保护区）必须逐像素相同。
 * 一次同时证明两件事：统一层与冻结基线一致，且在不做边界检查的硬件语义下也安全。
 *
 * 构建要求：
 *   禁止定义 NDEBUG（assert 会被移除导致假通过）
 *   禁止定义 BITBLT_ENABLE_HW_ACCESS（本机测试不得接触任何寄存器）
 *
 * 像素格式：XRGB8888，32 bit（见 renderer.h 顶部）。
 * pixel_t 已完成 16-bit -> 32-bit 迁移，格式闸门放行，
 * test_dispatch_and_gate 里走的是"整条下发通路"那一侧。
 */

#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <limits.h>
#include <assert.h>

#include "renderer.h"
#include "renderer_fpga.h"
#include "gpu.h"
#include "gpu_validate.h"


#ifdef NDEBUG
#error "测试依赖 assert 判定，禁止定义 NDEBUG：断言会被移除导致假通过"
#endif

#ifdef BITBLT_ENABLE_HW_ACCESS
#error "本机测试不得开启硬件访问：假后端必须始终是纯软件路径"
#endif


/* ------------------------------------------------------------------ */
/* 画布：两种配置，一种 stride == width，一种带越界保护区              */
/* ------------------------------------------------------------------ */

#define FB_W 16
#define FB_H 12

/* 保护区画布：stride 20 > 有效宽度 16，底部再留 4 行 */
#define PAD_STRIDE 20
#define PAD_ROWS   16

#define MAX_PIXELS  (PAD_STRIDE * PAD_ROWS)
#define GUARD_VALUE 0xDEAD

/* 源图：故意让 src_stride 既不等于 src_width，也不等于目标 stride */
#define SRC_W      5
#define SRC_H      4
#define SRC_STRIDE 7

static pixel_t canvas_frozen[MAX_PIXELS];
static pixel_t canvas_cpu[MAX_PIXELS];
static pixel_t canvas_fake[MAX_PIXELS];
static pixel_t src_pixels[SRC_STRIDE * SRC_H];


static void fill_canvas(pixel_t *canvas, int n, pixel_t value)
{
    for (int i = 0; i < n; i++)
        canvas[i] = value;
}


static int config_stride(int cfg)
{
    return (cfg == 0) ? FB_W : PAD_STRIDE;
}


static int config_rows(int cfg)
{
    return (cfg == 0) ? FB_H : PAD_ROWS;
}


static render_surface_t make_surface(pixel_t *pixels, int stride_px)
{
    render_surface_t s;

    s.pixels = pixels;
    s.width = FB_W;
    s.height = FB_H;
    s.stride_px = stride_px;
    s.phys_base = 0;

    return s;
}


static render_surface_t make_src_surface(void)
{
    render_surface_t s;

    s.pixels = src_pixels;
    s.width = SRC_W;
    s.height = SRC_H;
    s.stride_px = SRC_STRIDE;
    s.phys_base = 0;

    return s;
}


static render_rect_t make_rect(int x, int y, int w, int h)
{
    render_rect_t r;

    r.x = x;
    r.y = y;
    r.w = w;
    r.h = h;

    return r;
}


/* ------------------------------------------------------------------ */
/* 假后端：模拟硬件的"笨"语义                                          */
/* ------------------------------------------------------------------ */

/*
 * 刻意【不裁剪、不做任何边界检查】，只照着 dst_rect 写。
 *
 * 这正是 BitBlt 硬件的行为：它不会替你做边界检查。
 * 所以它能验证统一层的裁剪是否可靠——裁剪一旦有缺陷，这里就会写到
 * 保护区的 0xDEAD 上或者数组之外，被保护区检查或 ASan 抓住。
 *
 * 它写在测试文件里并且是 static，不会进板级镜像。
 */
static render_op_t g_last_op;
static int         g_fake_calls = 0;

static render_status_t fake_fill(const render_op_t *op)
{
    g_last_op = *op;
    g_fake_calls++;

    for (int yy = 0; yy < op->dst_rect.h; yy++)
    {
        pixel_t *row = op->dst->pixels
                     + (size_t)(op->dst_rect.y + yy) * (size_t)op->dst->stride_px;

        for (int xx = 0; xx < op->dst_rect.w; xx++)
            row[op->dst_rect.x + xx] = op->color;
    }

    return RENDER_OK;
}


static render_status_t fake_copy(const render_op_t *op)
{
    g_last_op = *op;
    g_fake_calls++;

    for (int yy = 0; yy < op->dst_rect.h; yy++)
    {
        pixel_t *drow = op->dst->pixels
                      + (size_t)(op->dst_rect.y + yy) * (size_t)op->dst->stride_px;
        const pixel_t *srow = op->src->pixels
                            + (size_t)(op->src_rect.y + yy) * (size_t)op->src->stride_px;

        for (int xx = 0; xx < op->dst_rect.w; xx++)
            drow[op->dst_rect.x + xx] = srow[op->src_rect.x + xx];
    }

    return RENDER_OK;
}


static const renderer_ops_t fake_ops =
{
    "fake",
    fake_fill,
    fake_copy
};


/* ------------------------------------------------------------------ */
/* 三路等价扫描                                                        */
/* ------------------------------------------------------------------ */

static void compare_three(const char *tag, int cfg, int a, int b, int c, int d, int n)
{
    for (int i = 0; i < n; i++)
    {
        if (canvas_frozen[i] != canvas_cpu[i] || canvas_frozen[i] != canvas_fake[i])
        {
            /* PRIX32 而不是硬写 %X：rv32 上 uint32_t 是 unsigned long */
            printf("  [FAIL] %s cfg=%d 参数=(%d,%d,%d,%d) 第 %d 个像素: "
                   "冻结层=0x%08" PRIX32 " 统一层CPU=0x%08" PRIX32
                   " 统一层假后端=0x%08" PRIX32 "\n",
                   tag, cfg, a, b, c, d, i,
                   canvas_frozen[i], canvas_cpu[i], canvas_fake[i]);
        }

        assert(canvas_frozen[i] == canvas_cpu[i]);
        assert(canvas_frozen[i] == canvas_fake[i]);
    }
}


static void equiv_fill(int cfg, int x, int y, int w, int h)
{
    const pixel_t COLOR = 0x1234;
    int stride = config_stride(cfg);
    int n = stride * config_rows(cfg);

    render_surface_t surf_cpu;
    render_surface_t surf_fake;
    render_rect_t rect = make_rect(x, y, w, h);

    /* ① 冻结层 */
    fill_canvas(canvas_frozen, n, GUARD_VALUE);
    sw_fill_rect(canvas_frozen, FB_W, FB_H, stride, x, y, w, h, COLOR);

    /* ② 统一层 + CPU 后端 */
    surf_cpu = make_surface(canvas_cpu, stride);
    fill_canvas(canvas_cpu, n, GUARD_VALUE);
    render_select(RENDER_BACKEND_CPU);
    (void)render_fill_rect(&surf_cpu, rect, COLOR);

    /* ③ 统一层 + 假后端 */
    surf_fake = make_surface(canvas_fake, stride);
    fill_canvas(canvas_fake, n, GUARD_VALUE);
    render_select_ops(&fake_ops);
    (void)render_fill_rect(&surf_fake, rect, COLOR);

    compare_three("fill", cfg, x, y, w, h, n);
}


static void equiv_blit(int cfg, int dst_x, int dst_y)
{
    int stride = config_stride(cfg);
    int n = stride * config_rows(cfg);

    render_surface_t src = make_src_surface();
    render_surface_t surf_cpu;
    render_surface_t surf_fake;

    /* ① 冻结层 */
    fill_canvas(canvas_frozen, n, GUARD_VALUE);
    sw_blit(canvas_frozen, FB_W, FB_H, stride,
            src_pixels, SRC_W, SRC_H, SRC_STRIDE, dst_x, dst_y);

    /* ② 统一层 + CPU 后端 */
    surf_cpu = make_surface(canvas_cpu, stride);
    fill_canvas(canvas_cpu, n, GUARD_VALUE);
    render_select(RENDER_BACKEND_CPU);
    (void)render_blit(&surf_cpu, &src, dst_x, dst_y);

    /* ③ 统一层 + 假后端 */
    surf_fake = make_surface(canvas_fake, stride);
    fill_canvas(canvas_fake, n, GUARD_VALUE);
    render_select_ops(&fake_ops);
    (void)render_blit(&surf_fake, &src, dst_x, dst_y);

    compare_three("blit", cfg, dst_x, dst_y, SRC_W, SRC_H, n);
}


static void test_equivalence(void)
{
    static const int XS[] = { -20, -3, -1, 0, 1, 3, 4, 7, 15, 16, 20 };
    static const int WS[] = { 0, 1, 2, 3, 4, 5, 16, 50 };

    const int nxs = (int)(sizeof(XS) / sizeof(XS[0]));
    const int nws = (int)(sizeof(WS) / sizeof(WS[0]));

    for (int i = 0; i < SRC_STRIDE * SRC_H; i++)
        src_pixels[i] = (pixel_t)(0x1000 + i);

    for (int cfg = 0; cfg < 2; cfg++)
    {
        for (int xi = 0; xi < nxs; xi++)
        {
            for (int yi = 0; yi < nxs; yi++)
            {
                for (int wi = 0; wi < nws; wi++)
                {
                    for (int hi = 0; hi < nws; hi++)
                        equiv_fill(cfg, XS[xi], XS[yi], WS[wi], WS[hi]);
                }

                equiv_blit(cfg, XS[xi], XS[yi]);
            }
        }
    }

    printf("[PASS] 三路等价扫描（冻结层 / 统一层+CPU / 统一层+假后端）\n");
}


/* ------------------------------------------------------------------ */
/* 裁剪预言机：极值输入                                                */
/* ------------------------------------------------------------------ */

/*
 * 只测统一层——冻结层的 int x1 = x + width 在这些输入上是符号溢出 UB，
 * 不能拿去喂它。统一层先裁剪，冻结函数就永远看不到接近 INT_MAX 的操作数。
 */
static void oracle_check(int x, int y, int w, int h)
{
    render_rect_t req = make_rect(x, y, w, h);
    render_rect_t out;
    render_surface_t surf;
    int visible;
    int64_t x0 = x, y0 = y, x1 = 0, y1 = 0;
    int clipped_visible;

    /* 独立算一遍期望结果，不用被测代码 */
    if (w <= 0 || h <= 0)
    {
        visible = 0;
    }
    else
    {
        x1 = (int64_t)x + (int64_t)w;
        y1 = (int64_t)y + (int64_t)h;

        if (x0 < 0)
            x0 = 0;

        if (y0 < 0)
            y0 = 0;

        if (x1 > FB_W)
            x1 = FB_W;

        if (y1 > FB_H)
            y1 = FB_H;

        visible = (x0 < x1 && y0 < y1);
    }

    /* 直接测裁剪函数 */
    clipped_visible = render_clip_rect(FB_W, FB_H, req, &out);

    if (clipped_visible != visible)
    {
        printf("  [FAIL] 裁剪可见性 (%d,%d,%d,%d): 期望 %d 实际 %d\n",
               x, y, w, h, visible, clipped_visible);
    }

    assert(clipped_visible == visible);

    if (visible)
    {
        assert(out.x == (int)x0);
        assert(out.y == (int)y0);
        assert(out.w == (int)(x1 - x0));
        assert(out.h == (int)(y1 - y0));

        /* 不变量一：结果必须完全落在画布内 */
        assert(out.x >= 0 && out.y >= 0);
        assert((int64_t)out.x + out.w <= FB_W);
        assert((int64_t)out.y + out.h <= FB_H);

        /* 不变量二：结果必须是请求的子集 */
        assert(out.x >= x && out.y >= y);
        assert((int64_t)out.x + out.w <= (int64_t)x + w);
        assert((int64_t)out.y + out.h <= (int64_t)y + h);
    }

    /* 通过统一层 + 假后端确认"画了还是没画" */
    surf = make_surface(canvas_fake, FB_W);
    fill_canvas(canvas_fake, FB_W * FB_H, GUARD_VALUE);
    g_fake_calls = 0;
    (void)render_select_ops(&fake_ops);

    {
        render_status_t st = render_fill_rect(&surf, req, 0x0777);

        assert(st == RENDER_OK);
    }

    if (!visible)
    {
        assert(g_fake_calls == 0);

        /* 完全不可见时整块画布都不许动 */
        for (int i = 0; i < FB_W * FB_H; i++)
            assert(canvas_fake[i] == GUARD_VALUE);
    }
    else
    {
        assert(g_fake_calls == 1);
        assert(g_last_op.dst_rect.x == out.x);
        assert(g_last_op.dst_rect.y == out.y);
        assert(g_last_op.dst_rect.w == out.w);
        assert(g_last_op.dst_rect.h == out.h);
    }
}


static void test_clip_oracle(void)
{
    static const int VALS[] = {
        INT_MIN, -1000000, -1000, -20, -1, 0, 1, 15, 16, 20, 1000, 1000000, INT_MAX
    };

    const int n = (int)(sizeof(VALS) / sizeof(VALS[0]));

    for (int a = 0; a < n; a++)
        for (int b = 0; b < n; b++)
            for (int c = 0; c < n; c++)
                for (int d = 0; d < n; d++)
                    oracle_check(VALS[a], VALS[b], VALS[c], VALS[d]);

    printf("[PASS] 裁剪预言机（含 INT_MIN / INT_MAX 极值）\n");
}


/* ------------------------------------------------------------------ */
/* 画布视图                                                            */
/* ------------------------------------------------------------------ */

static void test_surface_view(void)
{
    render_surface_t base = make_surface(canvas_cpu, FB_W);
    render_surface_t v;
    render_surface_t clipped;

    v = render_surface_view(&base, 2, 3, 4, 5);
    assert(render_surface_valid(&v));
    assert(v.pixels == canvas_cpu + 3 * FB_W + 2);
    assert(v.width == 4 && v.height == 5 && v.stride_px == FB_W);

    /* 视图带上 phys_base 偏移 */
    base.phys_base = 0x1000;
    v = render_surface_view(&base, 2, 3, 4, 5);
    assert(v.phys_base == 0x1000 + (uintptr_t)3 * FB_W * RENDER_PIXEL_BYTES
                            + (uintptr_t)2 * RENDER_PIXEL_BYTES);

    /* 越界视图一律返回空画布 */
    v = render_surface_view(&base, FB_W - 2, 0, 4, 1);
    assert(!render_surface_valid(&v));

    v = render_surface_view(&base, 0, FB_H - 1, 1, 4);
    assert(!render_surface_valid(&v));

    v = render_surface_view(&base, -1, 0, 2, 2);
    assert(!render_surface_valid(&v));

    v = render_surface_view(&base, 0, 0, 0, 2);
    assert(!render_surface_valid(&v));

    v = render_surface_view(&base, 0, 0, FB_W + 1, 1);
    assert(!render_surface_valid(&v));

    /* 非法画布：stride 小于宽度会串行，必须拒绝 */
    clipped = base;
    clipped.stride_px = FB_W - 1;
    assert(!render_surface_valid(&clipped));
    assert(render_surface_valid(&base));

    printf("[PASS] 画布视图与合法性检查\n");
}


/* ------------------------------------------------------------------ */
/* FPGA 参数翻译：精确值                                               */
/* ------------------------------------------------------------------ */

/*
 * 任意基准地址，只为了让地址算术可以手算验算。
 * 它不代表任何真实内存布局——本工程不内置 Framebuffer 地址。
 */
#define TEST_DST_BASE 0x20000000u
#define TEST_SRC_BASE 0x24000000u

static void test_exact_translation(void)
{
    static pixel_t big_fb[640 * 4];

    render_surface_t dst;
    render_surface_t src;
    render_op_t op;
    gpu_params_t req;

    dst.pixels = big_fb;
    dst.width = 640;
    dst.height = 4;
    dst.stride_px = 640;
    dst.phys_base = TEST_DST_BASE;

    src.pixels = src_pixels;
    src.width = SRC_W;
    src.height = SRC_H;
    src.stride_px = SRC_STRIDE;
    src.phys_base = TEST_SRC_BASE;

    memset(&op, 0, sizeof(op));
    op.dst = &dst;
    op.src = &src;
    op.dst_rect = make_rect(4, 3, 8, 2);
    op.src_rect = make_rect(1, 2, 8, 2);
    op.color = 0xF800;

    /* ---- FILL ---- */
    assert(render_fpga_build_request(&op, 0, &req) == RENDER_OK);

    /*
     * 这两条是本测试的重点：WIDTH 是矩形宽度，DST_STRIDE 是画布行距。
     * 把宽度当 stride 传过去，硬件会把后面每一行都写花。
     */
    assert(req.width == 8u);
    assert(req.dst_stride_bytes == 640u * RENDER_PIXEL_BYTES);
    assert(req.width != req.dst_stride_bytes);

    assert(req.dst_addr_bytes == TEST_DST_BASE
                                 + 3u * 640u * RENDER_PIXEL_BYTES
                                 + 4u * RENDER_PIXEL_BYTES);
    assert(req.height == 2u);
    assert(req.operation == GPU_OP_FILL);

    /* FILL 不碰源侧参数 */
    assert(req.src_addr_bytes == 0u);
    assert(req.src_stride_bytes == 0u);

    /* 颜色映射只经过 render_pixel_to_hw_color 一次 */
    assert(req.color == render_pixel_to_hw_color(0xF800));

    /* ---- COPY ---- */
    assert(render_fpga_build_request(&op, 1, &req) == RENDER_OK);
    assert(req.operation == GPU_OP_COPY);
    assert(req.src_stride_bytes == SRC_STRIDE * RENDER_PIXEL_BYTES);
    assert(req.src_addr_bytes == TEST_SRC_BASE
                                 + 2u * SRC_STRIDE * RENDER_PIXEL_BYTES
                                 + 1u * RENDER_PIXEL_BYTES);

    /* phys_base 传 0 时改用指针本身，裸机下两者相同 */
    dst.phys_base = 0;
    assert(render_fpga_build_request(&op, 0, &req) == RENDER_OK);
    assert(req.dst_addr_bytes == (uint32_t)((uintptr_t)big_fb
                                            + 3u * 640u * RENDER_PIXEL_BYTES
                                            + 4u * RENDER_PIXEL_BYTES));

    /* 空指针 */
    assert(render_fpga_build_request(0, 0, &req) == RENDER_ERR_INVALID_ARG);
    assert(render_fpga_build_request(&op, 0, 0) == RENDER_ERR_INVALID_ARG);

    printf("[PASS] FPGA 参数翻译精确值（WIDTH 与 DST_STRIDE 不混淆）\n");
}


/* ------------------------------------------------------------------ */
/* 硬件约束校验：边界值表                                              */
/* ------------------------------------------------------------------ */

/*
 * 测试用的人造内存布局。数值本身没有意义——重点在于它们是【参数】
 * 而不是全局量，恰好证明校验器不依赖任何硬编码地址。
 *
 * 窗口 = [0x10000000, 0x18000000)，保留区 = [0x10000000, 0x10020000)
 */
#define T_DDR_BASE 0x10000000u
#define T_DDR_SIZE 0x08000000u
#define T_RSVD_LO  0x10000000u
#define T_RSVD_HI  0x10020000u
#define T_WIN_END  (T_DDR_BASE + T_DDR_SIZE)


static gpu_limits_t lim_normal(void)
{
    gpu_limits_t l;

    l.ddr_base = T_DDR_BASE;
    l.ddr_size = T_DDR_SIZE;
    l.reserved_lo = T_RSVD_LO;
    l.reserved_hi = T_RSVD_HI;

    return l;
}


static gpu_params_t params_normal(void)
{
    gpu_params_t p;

    memset(&p, 0, sizeof(p));
    p.dst_addr_bytes = 0x10100000u;
    p.dst_stride_bytes = 0x1000u;
    p.src_addr_bytes = 0x10500000u;
    p.src_stride_bytes = 0x1000u;
    p.width = 64u;
    p.height = 8u;
    p.color = 0x00FFFFFFu;
    p.operation = GPU_OP_FILL;

    return p;
}


static void expect_fill(const char *name, const gpu_limits_t *l,
                        const gpu_params_t *p, render_status_t want)
{
    render_status_t got = gpu_validate_fill(l, p);

    if (got != want)
    {
        printf("  [FAIL] fill 校验「%s」: 期望 %s，实际 %s\n",
               name, render_strstatus(want), render_strstatus(got));
    }

    assert(got == want);
}


static void expect_copy(const char *name, const gpu_limits_t *l,
                        const gpu_params_t *p, render_status_t want)
{
    render_status_t got = gpu_validate_copy(l, p);

    if (got != want)
    {
        printf("  [FAIL] copy 校验「%s」: 期望 %s，实际 %s\n",
               name, render_strstatus(want), render_strstatus(got));
    }

    assert(got == want);
}


static void test_validator_fill(void)
{
    gpu_limits_t l = lim_normal();
    gpu_limits_t l2;
    gpu_params_t p;

    /* 基准 */
    p = params_normal();
    expect_fill("基准", &l, &p, RENDER_OK);

    /* 空指针 */
    expect_fill("空 limits", 0, &p, RENDER_ERR_INVALID_ARG);
    expect_fill("空 params", &l, 0, RENDER_ERR_INVALID_ARG);

    /* 布局未填 */
    l2 = l;
    l2.ddr_size = 0u;
    expect_fill("ddr_size == 0", &l2, &p, RENDER_ERR_NOT_READY);

    /* operation */
    p = params_normal();
    p.operation = 99u;
    expect_fill("operation 非法", &l, &p, RENDER_ERR_BAD_OPERATION);

    /* width */
    p = params_normal();
    p.width = 0u;
    expect_fill("width == 0", &l, &p, RENDER_ERR_BAD_WIDTH);

    p = params_normal();
    p.width = 3u;
    expect_fill("width == 3（非 4 的倍数）", &l, &p, RENDER_ERR_BAD_WIDTH);

    p = params_normal();
    p.width = 4u;
    expect_fill("width == 4", &l, &p, RENDER_OK);

    p = params_normal();
    p.width = UINT32_MAX;
    expect_fill("width == UINT32_MAX", &l, &p, RENDER_ERR_BAD_WIDTH);

    /* height */
    p = params_normal();
    p.height = 0u;
    expect_fill("height == 0", &l, &p, RENDER_ERR_BAD_HEIGHT);

    /* 对齐：15 与 16 是分界 */
    p = params_normal();
    p.dst_addr_bytes = 0x10100008u;
    expect_fill("dst 地址未 16B 对齐", &l, &p, RENDER_ERR_BAD_ALIGN);

    p = params_normal();
    p.dst_addr_bytes = 0x10100010u;
    expect_fill("dst 地址 16B 对齐", &l, &p, RENDER_OK);

    p = params_normal();
    p.dst_stride_bytes = 0x1004u;
    expect_fill("dst_stride 未 16B 对齐", &l, &p, RENDER_ERR_BAD_ALIGN);

    /* stride 与 width*4 的分界 */
    p = params_normal();
    p.width = 64u;
    p.dst_stride_bytes = 240u;    /* 240 % 16 == 0，但 < 64*4 = 256 */
    expect_fill("dst_stride < width*4", &l, &p, RENDER_ERR_BAD_STRIDE);

    p = params_normal();
    p.width = 64u;
    p.dst_stride_bytes = 256u;    /* 正好等于 */
    expect_fill("dst_stride == width*4", &l, &p, RENDER_OK);

    /* 保留区 */
    p = params_normal();
    p.dst_addr_bytes = 0x10010000u;   /* 落在 [0x10000000, 0x10020000) 内 */
    expect_fill("dst 落在保留区", &l, &p, RENDER_ERR_RANGE);

    l2 = l;
    l2.reserved_lo = 0x10010000u;
    l2.reserved_hi = 0x10010000u;     /* lo == hi 表示没有保留区 */
    expect_fill("保留区为空", &l2, &p, RENDER_OK);

    /* 窗口边界：独占结束地址正好落在窗口末尾是通过，多一字节失败 */
    p = params_normal();
    p.dst_addr_bytes = T_WIN_END - 16u;
    p.dst_stride_bytes = 16u;
    p.width = 4u;
    p.height = 1u;
    expect_fill("范围正好结束在窗口末尾", &l, &p, RENDER_OK);

    /* 同一个起点，多一行就越过窗口末尾：结束于 T_WIN_END + 16 */
    p = params_normal();
    p.dst_addr_bytes = T_WIN_END - 16u;
    p.dst_stride_bytes = 16u;
    p.width = 4u;
    p.height = 2u;
    expect_fill("范围越过窗口末尾", &l, &p, RENDER_ERR_RANGE);

    /*
     * 32 位回绕。
     *
     * 窗口上界必须放到 32 位之外，否则越界区间会先被窗口检查拦下，
     * 这条断言就分辨不出回绕检查到底有没有生效。
     */
    l2.ddr_base = 0xFFFFFFF0u;
    l2.ddr_size = 0xFFFFFFFFu;        /* win_hi = 0x1FFFFFFEF，超过 32 位 */
    l2.reserved_lo = 0u;
    l2.reserved_hi = 0u;
    p = params_normal();
    p.dst_addr_bytes = 0xFFFFFFF0u;
    p.dst_stride_bytes = 16u;
    p.width = 4u;
    p.height = 2u;                    /* 结束于 0x100000010，越出 32 位 */
    expect_fill("地址回绕 32 位", &l2, &p, RENDER_ERR_RANGE);

    /* 错误优先级：width 与对齐同时非法时，width 先判 */
    p = params_normal();
    p.width = 3u;
    p.dst_addr_bytes = 0x10100008u;
    expect_fill("优先级 width 先于对齐", &l, &p, RENDER_ERR_BAD_WIDTH);

    printf("[PASS] FILL 约束校验边界值\n");
}


static void test_validator_copy(void)
{
    gpu_limits_t l = lim_normal();
    gpu_params_t p;

    /* 基准：源在 [0x10500000, 0x10507100)，目标在 [0x10100000, 0x10107100)，不相交 */
    p = params_normal();
    p.operation = GPU_OP_COPY;
    expect_copy("基准", &l, &p, RENDER_OK);

    /* FILL 的参数拿去走 COPY 校验应当被判 operation 非法 */
    p = params_normal();
    expect_copy("operation 是 FILL", &l, &p, RENDER_ERR_BAD_OPERATION);

    /* 源侧对齐 */
    p = params_normal();
    p.operation = GPU_OP_COPY;
    p.src_addr_bytes = 0x10500008u;
    expect_copy("源地址未 16B 对齐", &l, &p, RENDER_ERR_BAD_ALIGN);

    p = params_normal();
    p.operation = GPU_OP_COPY;
    p.src_stride_bytes = 0x1004u;
    expect_copy("源 stride 未 16B 对齐", &l, &p, RENDER_ERR_BAD_ALIGN);

    p = params_normal();
    p.operation = GPU_OP_COPY;
    p.src_stride_bytes = 240u;        /* < 64*4 */
    expect_copy("源 stride 太小", &l, &p, RENDER_ERR_BAD_STRIDE);

    /* 源侧越界 */
    p = params_normal();
    p.operation = GPU_OP_COPY;
    p.src_addr_bytes = 0x10010000u;   /* 保留区 */
    expect_copy("源落在保留区", &l, &p, RENDER_ERR_RANGE);

    /* 重叠：源与目标区间相交 */
    p = params_normal();
    p.operation = GPU_OP_COPY;
    p.src_addr_bytes = 0x10103000u;   /* 与目标区重叠 */
    expect_copy("源目标重叠", &l, &p, RENDER_ERR_OVERLAP);

    /* 相邻但不重叠：目标的独占结束地址正好是源的起点 */
    p = params_normal();
    p.operation = GPU_OP_COPY;
    p.dst_addr_bytes = 0x10100000u;
    p.dst_stride_bytes = 0x1000u;
    p.src_addr_bytes = 0x10100000u + 0x7000u + 0x100u;
    expect_copy("相邻但不重叠", &l, &p, RENDER_OK);

    /* 源在目标之前，同样相邻不重叠 */
    p = params_normal();
    p.operation = GPU_OP_COPY;
    p.src_addr_bytes = 0x10100000u - 0x7100u;
    p.dst_addr_bytes = 0x10100000u;
    expect_copy("源在目标之前且相邻", &l, &p, RENDER_OK);

    /* 按字节错开一个字节也算重叠（保守判定） */
    p = params_normal();
    p.operation = GPU_OP_COPY;
    p.dst_addr_bytes = 0x10100000u;
    p.src_addr_bytes = 0x10100000u - 0x7110u;   /* 结束于目标起点前 16 字节 */
    expect_copy("源结束于目标起点前 16 字节", &l, &p, RENDER_OK);

    printf("[PASS] COPY 约束校验边界值（含重叠判定）\n");
}


/* ------------------------------------------------------------------ */
/* 分发、闸门、骨架惰性                                                */
/* ------------------------------------------------------------------ */

static void test_dispatch_and_gate(void)
{
    render_surface_t dst;
    render_surface_t src = make_src_surface();
    render_surface_t bad;

    /* 没选后端时绘制必须报错，而不是悄悄用 CPU 跑 */
    (void)render_select_ops(0);
    assert(strcmp(render_backend_name(), "(none)") == 0);

    dst = make_surface(canvas_cpu, FB_W);
    assert(render_fill_rect(&dst, make_rect(0, 0, 4, 4), 0x1111)
           == RENDER_ERR_NO_BACKEND);
    assert(render_blit(&dst, &src, 0, 0) == RENDER_ERR_NO_BACKEND);

    /* render_init 默认选 CPU */
    render_init();
    assert(strcmp(render_backend_name(), "cpu") == 0);

    /* render_select 未知后端 */
    assert(render_select((render_backend_t)99) == RENDER_ERR_INVALID_ARG);

    /* 非法画布：stride < width */
    bad = make_surface(canvas_cpu, FB_W);
    bad.stride_px = FB_W - 1;
    assert(render_fill_rect(&bad, make_rect(0, 0, 4, 4), 0x1111)
           == RENDER_ERR_INVALID_ARG);
    assert(render_blit(&dst, &bad, 0, 0) == RENDER_ERR_INVALID_ARG);
    assert(render_fill_rect(0, make_rect(0, 0, 4, 4), 0x1111)
           == RENDER_ERR_INVALID_ARG);

    /* 裁没了的矩形是合法输入：返回 OK 且一个像素都不画 */
    (void)render_select_ops(&fake_ops);
    fill_canvas(canvas_fake, FB_W * FB_H, GUARD_VALUE);
    g_fake_calls = 0;

    {
        render_surface_t dst_fake = make_surface(canvas_fake, FB_W);

        assert(render_fill_rect(&dst_fake, make_rect(-100, 0, 10, 10), 0x1111)
               == RENDER_OK);
        assert(render_fill_rect(&dst_fake, make_rect(0, 0, 0, 4), 0x1111)
               == RENDER_OK);
        assert(render_blit(&dst_fake, &src, -100, -100) == RENDER_OK);
    }

    assert(g_fake_calls == 0);

    for (int i = 0; i < FB_W * FB_H; i++)
        assert(canvas_fake[i] == GUARD_VALUE);

    /* FPGA 后端 */
    (void)render_select(RENDER_BACKEND_FPGA);
    assert(strcmp(render_backend_name(), "fpga") == 0);

    {
        render_status_t st;

#if RENDER_FPGA_USABLE
        /*
         * pixel_t 宽度与已确认的 XRGB8888 一致，闸门放行，
         * 下面把整条下发通路从"未填布局"一路走到骨架为止。
         */

        /* 1) 内存布局未设置：必须 NOT_READY。
              本工程不内置任何默认地址，没填布局就不许下发。 */
        render_fpga_set_limits(0);
        st = render_fill_rect(&dst, make_rect(0, 0, 4, 4), 0x1111);
        assert(st == RENDER_ERR_NOT_READY);

        /* 2) 布局已填，但画布物理地址在窗口之外：必须 RANGE。
              故意用一个明确的窗口外地址，不依赖宿主机指针值。 */
        {
            gpu_limits_t l = lim_normal();

            render_fpga_set_limits(&l);
            dst.phys_base = 0x20000000u;
        }
        st = render_fill_rect(&dst, make_rect(0, 0, 4, 4), 0x1111);
        assert(st == RENDER_ERR_RANGE);

        /* 3) 画布物理地址落在布局内：闸门与硬件约束校验全部通过，
              最终落到骨架的 UNSUPPORTED（真实下发尚未实现）。 */
        dst.phys_base = 0x10100000u;   /* 在窗口内且 16B 对齐 */
        st = render_fill_rect(&dst, make_rect(0, 0, 4, 4), 0x1111);
        assert(st == RENDER_ERR_UNSUPPORTED);

        /* 4) 硬件约束确实在生效：x = 1 使目标地址不再 16B 对齐。
              这条也是"矩形起点必须是 4 的倍数"的来源——
              它属于 BitBlt V0.1 硬件约束，B 组确认放宽之前一直有效。 */
        st = render_fill_rect(&dst, make_rect(1, 0, 4, 4), 0x1111);
        assert(st == RENDER_ERR_BAD_ALIGN);

        /* 5) width 不是 4 的倍数同样被拒 */
        st = render_fill_rect(&dst, make_rect(0, 0, 3, 4), 0x1111);
        assert(st == RENDER_ERR_BAD_WIDTH);

        /* 6) 拷贝路径同样过校验：源宽 5 不是 4 的倍数，在此被拦下 */
        {
            render_surface_t fpga_src = make_src_surface();

            fpga_src.phys_base = 0x10500000u;
            st = render_blit(&dst, &fpga_src, 0, 0);
            assert(st == RENDER_ERR_BAD_WIDTH);
        }

        /* 收尾：清掉布局与物理地址，避免影响后续用例 */
        render_fpga_set_limits(0);
        dst.phys_base = 0;
#else
        /*
         * pixel_t 宽度与已确认的 XRGB8888 不一致：闸门必须拦住一切下发，
         * 不允许用强制转换或截断绕过。
         */
        {
            gpu_limits_t l = lim_normal();

            render_fpga_set_limits(&l);
        }

        assert(render_fill_rect(&dst, make_rect(0, 0, 4, 4), 0x1111)
               == RENDER_ERR_FORMAT_MISMATCH);
        assert(render_blit(&dst, &src, 0, 0) == RENDER_ERR_FORMAT_MISMATCH);

        render_fpga_set_limits(0);
#endif
    }

    render_init();
    printf("[PASS] 后端分发、格式闸门与下发通路\n");
}


static void test_color_mapping(void)
{
    /*
     * pixel_t 与硬件格式都是 XRGB8888，所以这里是恒等映射。
     *
     * 保留这个测试是为了钉住"转换点只有一个、且不改变像素值"：
     * 哪天真做 RGB565 打包，它会第一个失败。
     */
    assert(render_pixel_to_hw_color(0x00000000u) == 0x00000000u);
    assert(render_pixel_to_hw_color(0x00FFFFFFu) == 0x00FFFFFFu);
    assert(render_pixel_to_hw_color(0x00FF0000u) == 0x00FF0000u);   /* 纯红 */
    assert(render_pixel_to_hw_color(0x0000FF00u) == 0x0000FF00u);   /* 纯绿 */
    assert(render_pixel_to_hw_color(0x000000FFu) == 0x000000FFu);   /* 纯蓝 */
    assert(render_pixel_to_hw_color(0x00123456u) == 0x00123456u);   /* 任意值不变 */

    printf("[PASS] 像素到硬件 COLOR 的恒等映射\n");
}


static void test_skeleton_inert(void)
{
    gpu_params_t p = params_normal();

    /*
     * 骨架状态断言：所有下发路径都必须明确返回 UNSUPPORTED，且不得崩溃。
     * 接通真实驱动后这些期望值要连同实现一起改——
     * 这是有意的绊线，避免"骨架悄悄变成了半成品"。
     */
    assert(gpu_fill(&p, GPU_TIMEOUT_MS_DEFAULT) == RENDER_ERR_UNSUPPORTED);
    assert(gpu_copy(&p, GPU_TIMEOUT_MS_DEFAULT) == RENDER_ERR_UNSUPPORTED);
    assert(gpu_init(0u) == RENDER_ERR_UNSUPPORTED);
    assert(gpu_fill(0, 100u) == RENDER_ERR_INVALID_ARG);
    assert(gpu_copy(0, 100u) == RENDER_ERR_INVALID_ARG);

    /* 时基未注入：驱动不猜时钟 */
    assert(gpu_timebase_ready() == 0);
    assert(gpu_version() == 0u);

    printf("[PASS] GPU 驱动骨架惰性（不触碰任何寄存器）\n");
}


static void test_status_strings(void)
{
    assert(strcmp(render_strstatus(RENDER_OK), "OK") == 0);
    assert(strcmp(render_strstatus(RENDER_ERR_BAD_ALIGN), "BAD_ALIGN") == 0);
    assert(strcmp(render_strstatus(RENDER_ERR_FORMAT_MISMATCH), "FORMAT_MISMATCH") == 0);
    assert(RENDER_OK == 0);

    printf("[PASS] 状态码字符串\n");
}


int main(void)
{
    /*
     * 关掉 stdout 缓冲：assert 失败会 abort，而 abort 不 flush 缓冲，
     * 否则断点前的 [FAIL] 诊断会全部丢失，只剩一句断言失败。
     */
    setvbuf(stdout, 0, _IONBF, 0);

    test_status_strings();

    test_equivalence();
    test_clip_oracle();
    test_surface_view();

    test_exact_translation();
    test_validator_fill();
    test_validator_copy();

    test_dispatch_and_gate();
    test_color_mapping();
    test_skeleton_inert();

    printf("\nAll render API tests passed.\n");

    return 0;
}
