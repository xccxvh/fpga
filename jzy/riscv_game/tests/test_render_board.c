/*
 * M1 渲染层板端 smoke test —— Ti60F225 / Sapphire RISC-V (RV32)
 *
 * 目的：在真实 RV32 上确认冻结的 M1 CPU reference 与统一渲染层的行为，
 * 包括 pixel_t 宽度、CPU 后端分发、Solid Fill、Block Copy、stride 与裁剪。
 *
 * 与本仓库 host 测试的分工：
 *   tests/test_renderer.c        冻结的 host 基线（不修改）
 *   tests/test_render_api.c      host 统一层测试（不修改）
 *   本文件                        板端 smoke test，只能用 bsp_printf 输出
 *
 * 板端与 host 的差异（刻意的）：
 *   - 不用 assert 判定。板上一旦 assert 失败，除了挂住什么信息都没有；
 *     这里全部显式打印并统计失败数，跑完能看到完整结论。
 *   - 不开 ASan/UBSan，板上没有这些运行时。
 *   - 用静态 RAM 数组模拟 framebuffer，不涉及 DDR 与显示。
 *   - 完全不访问 FPGA BitBlt：不填任何真实地址，不开启 BITBLT_ENABLE_HW_ACCESS，
 *     不调用 gpu_fill()/gpu_copy() 做任何硬件操作。
 *   - 主要走 render_* 统一层 API，不绕过它直接测 sw_*。
 */

#include <limits.h>

#include "bsp.h"

#include "renderer.h"


/* ------------------------------------------------------------------ */
/* 画布：stride > width，底部多留保护行                                 */
/* ------------------------------------------------------------------ */

#define FB_W      16
#define FB_H      12
#define FB_STRIDE 20          /* > FB_W，专门验证行尾 padding 没被误写 */
#define FB_ROWS   16          /* > FB_H，底部保护行 */

/*
 * 颜色常量按【当前像素格式】构造，不能直接写字面量。
 * 0x00FF0000 在 XRGB8888 里是纯红，在 RGB565 里高 16 位会被丢掉变成 0。
 */
#if RENDER_PIXEL_FORMAT_RGB565
/* RGB565 小端：R[15:11] G[10:5] B[4:0] */
#define COLOR_BG    0x0000u   /* 黑 */
#define COLOR_RED   0xF800u
#define COLOR_GREEN 0x07E0u
#define COLOR_BLUE  0x001Fu

/* 保护区哨兵。任何合法绘制都不会写出这个值，
   所以它一旦被改写就说明越界。 */
#define COLOR_GUARD 0xDEADu

/* 源图：故意让 stride 既不等于宽度，也不等于目标 stride */
#define SPR_W      5
#define SPR_H      4
#define SPR_STRIDE 8
#define SPR_BASE   0x4000u   /* 每个像素 SPR_BASE + sy*STRIDE + sx，互不相同 */

/* 逐行唯一标记：只用于检验"每一行落在自己的 stride 上"，不表示真实颜色。
   基址刻意避开 COLOR_* 与 SPR_BASE。 */
#define ROW_MARK(y) ((pixel_t)(0x0100u + (uint32_t)(y)))

#else
/* XRGB8888 颜色 */
#define COLOR_BG    0x00000000u   /* 背景：黑，高 8 位恒为 0 */
#define COLOR_RED   0x00FF0000u
#define COLOR_GREEN 0x0000FF00u
#define COLOR_BLUE  0x000000FFu

#define COLOR_GUARD 0x00ABCDEFu

#define SPR_W      5
#define SPR_H      4
#define SPR_STRIDE 8
#define SPR_BASE   0x00010000u

#define ROW_MARK(y) ((pixel_t)(0x00010000u * (uint32_t)((y) + 1)))
#endif

#define MAX_DIAG_PER_TEST 8


static pixel_t canvas[FB_STRIDE * FB_ROWS];
static pixel_t sprite[SPR_STRIDE * SPR_H];

static int g_pass = 0;
static int g_fail = 0;

static int t_fail = 0;      /* 当前用例内的不符处数 */
static int t_printed = 0;   /* 当前用例已打印的诊断行数，用于限流 */
static int t_extra = 0;     /* 超出限流、未打印的不符处数 */


/* ------------------------------------------------------------------ */
/* 判定与输出                                                          */
/* ------------------------------------------------------------------ */

static int str_eq(const char *a, const char *b)
{
    while (*a != '\0' && *a == *b)
    {
        a++;
        b++;
    }

    return *a == *b;
}


static void t_begin(void)
{
    t_fail = 0;
    t_printed = 0;
    t_extra = 0;
}


static void t_end(const char *name)
{
    if (t_extra > 0)
    {
        bsp_printf("[FAIL] %s 另有 %d 处不符未逐条列出\r\n", name, t_extra);
    }

    if (t_fail == 0)
    {
        g_pass++;
        bsp_printf("[PASS] %s\r\n", name);
    }
    else
    {
        g_fail++;
    }
}


/* 像素不符：按约定格式打印坐标与期望/实际值 */
static void expect_color(const char *name, int x, int y, uint32_t want)
{
    uint32_t got = (uint32_t)canvas[(uint32_t)y * FB_STRIDE + x];

    if (got == want)
    {
        return;
    }

    if (t_printed < MAX_DIAG_PER_TEST)
    {
        bsp_printf("[FAIL] %s x=%d y=%d expected=0x%08X actual=0x%08X\r\n",
                   name, x, y, want, got);
        t_printed++;
    }
    else
    {
        t_extra++;
    }

    t_fail++;
}


/* 非像素类判定（状态码、后端名等） */
static void fail_text(const char *name, const char *expected, const char *actual)
{
    if (t_printed < MAX_DIAG_PER_TEST)
    {
        bsp_printf("[FAIL] %s expected=%s actual=%s\r\n", name, expected, actual);
        t_printed++;
    }
    else
    {
        t_extra++;
    }

    t_fail++;
}


static void expect_status(const char *name, render_status_t got, render_status_t want)
{
    if (got != want)
    {
        fail_text(name, render_strstatus(want), render_strstatus(got));
    }
}


/* 数值型判定（裁剪矩形的 x/y/w/h 等） */
static void fail_num(const char *name, const char *what, int expected, int actual)
{
    if (t_printed < MAX_DIAG_PER_TEST)
    {
        bsp_printf("[FAIL] %s field=%s expected=%d actual=%d\r\n",
                   name, what, expected, actual);
        t_printed++;
    }
    else
    {
        t_extra++;
    }

    t_fail++;
}


static void expect_int(const char *name, const char *what, int expected, int actual)
{
    if (expected != actual)
    {
        fail_num(name, what, expected, actual);
    }
}


/* ------------------------------------------------------------------ */
/* 画布辅助                                                            */
/* ------------------------------------------------------------------ */

/*
 * 复位画布：有效区域填背景色，保护区填哨兵。
 *
 * 这两者必须分开 —— 判定函数一律假设"没被画过的地方是背景色"，
 * 而保护区从来不该被写。之前这里把整块都填成哨兵，导致所有
 * "矩形外应为背景色"的断言全部误报。
 */
static void reset_canvas(void)
{
    for (int y = 0; y < FB_ROWS; y++)
    {
        for (int x = 0; x < FB_STRIDE; x++)
        {
            int visible = (x < FB_W && y < FB_H);

            canvas[(uint32_t)y * FB_STRIDE + x] = visible ? COLOR_BG : COLOR_GUARD;
        }
    }
}


static void reset_sprite(void)
{
    for (int i = 0; i < SPR_STRIDE * SPR_H; i++)
    {
        sprite[i] = (pixel_t)(SPR_BASE + (uint32_t)i);
    }
}


static render_surface_t make_canvas_surface(void)
{
    render_surface_t s;

    s.pixels = canvas;
    s.width = FB_W;
    s.height = FB_H;
    s.stride_px = FB_STRIDE;
    s.phys_base = 0;

    return s;
}


static render_surface_t make_sprite_surface(void)
{
    render_surface_t s;

    s.pixels = sprite;
    s.width = SPR_W;
    s.height = SPR_H;
    s.stride_px = SPR_STRIDE;
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


static uint32_t sprite_at(int sx, int sy)
{
    return SPR_BASE + (uint32_t)(sy * SPR_STRIDE + sx);
}


/* 有效区域内所有像素都必须是 want */
static void expect_all_visible(const char *name, uint32_t want)
{
    for (int y = 0; y < FB_H; y++)
    {
        for (int x = 0; x < FB_W; x++)
        {
            expect_color(name, x, y, want);
        }
    }
}


/* 指定矩形内是 want，矩形外仍是背景色 */
static void expect_rect(const char *name, int rx, int ry, int rw, int rh, uint32_t want)
{
    for (int y = 0; y < FB_H; y++)
    {
        for (int x = 0; x < FB_W; x++)
        {
            int inside = (x >= rx && x < rx + rw && y >= ry && y < ry + rh);

            expect_color(name, x, y, inside ? want : COLOR_BG);
        }
    }
}


/* 整张源图放到 (dst_x, dst_y)，超出画布的部分自动裁剪 */
static void expect_blit(const char *name, int dst_x, int dst_y)
{
    for (int y = 0; y < FB_H; y++)
    {
        for (int x = 0; x < FB_W; x++)
        {
            int sx = x - dst_x;
            int sy = y - dst_y;

            if (sx >= 0 && sx < SPR_W && sy >= 0 && sy < SPR_H)
            {
                expect_color(name, x, y, sprite_at(sx, sy));
            }
            else
            {
                expect_color(name, x, y, COLOR_BG);
            }
        }
    }
}


/*
 * 行尾 padding 列与底部保护行必须一个像素都没被动过。
 *
 * 这是 stride 用错时最先暴露的地方：如果实现把 width 当成 stride，
 * 第二行就会从第 16 个像素开始写，正好落进 padding 列。
 */
static void expect_padding_intact(const char *name)
{
    for (int y = 0; y < FB_ROWS; y++)
    {
        for (int x = 0; x < FB_STRIDE; x++)
        {
            if (x >= FB_W || y >= FB_H)
            {
                expect_color(name, x, y, COLOR_GUARD);
            }
        }
    }
}


/* 什么都没被画：有效区域仍是背景色，保护区仍完好 */
static void expect_nothing_drawn(const char *name)
{
    expect_all_visible(name, COLOR_BG);
    expect_padding_intact(name);
}


/* ------------------------------------------------------------------ */
/* T1 ~ T9                                                             */
/* ------------------------------------------------------------------ */

static void test_t1_pixel_size(void)
{
    const char *name = "T1_pixel_t_is_4_bytes";

    t_begin();

    /*
     * pixel_t 宽度必须与当前格式一致。
     * 期望值是 RENDER_PIXEL_BYTES（由 pixel_t 派生），不是写死的 4 ——
     * RGB565 下 4 反而是错的。
     */
    if (sizeof(pixel_t) != RENDER_PIXEL_BYTES)
    {
        fail_text(name, "sizeof(pixel_t) == RENDER_PIXEL_BYTES", "mismatch");
    }

    if (RENDER_PIXEL_BYTES != 2u && RENDER_PIXEL_BYTES != 4u)
    {
        fail_text(name, "RENDER_PIXEL_BYTES is 2 or 4", "other");
    }

    if (RENDER_PIXEL_BYTES != sizeof(pixel_t))
    {
        fail_text(name, "RENDER_PIXEL_BYTES == sizeof(pixel_t)", "mismatch");
    }

    t_end(name);
}


static void test_t2_default_backend(void)
{
    const char *name = "T2_default_backend_is_cpu";
    const char *got;

    t_begin();

    /* 没有 select 过任何后端时，绘制必须失败而不是悄悄用 CPU 跑 */
    (void)render_select_ops(0);
    {
        render_surface_t s = make_canvas_surface();
        render_status_t st = render_fill_rect(&s, make_rect(0, 0, 4, 4), COLOR_RED);

        expect_status(name, st, RENDER_ERR_NO_BACKEND);
    }

    render_init();
    got = render_backend_name();

    if (got == 0 || !str_eq(got, "cpu"))
    {
        fail_text(name, "cpu", got ? got : "(null)");
    }

    t_end(name);
}


static void test_t3_fill_normal(void)
{
    const char *name = "T3_fill_rect_normal";
    render_surface_t s = make_canvas_surface();
    render_status_t st;

    t_begin();
    reset_canvas();

    st = render_fill_rect(&s, make_rect(4, 3, 5, 4), COLOR_RED);
    expect_status(name, st, RENDER_OK);
    expect_rect(name, 4, 3, 5, 4, COLOR_RED);
    expect_padding_intact(name);

    /* 三种 XRGB8888 基本色各画一条，确认通道位置没错 */
    reset_canvas();
    st = render_fill_rect(&s, make_rect(0, 0, 16, 4), COLOR_RED);
    expect_status(name, st, RENDER_OK);
    st = render_fill_rect(&s, make_rect(0, 4, 16, 4), COLOR_GREEN);
    expect_status(name, st, RENDER_OK);
    st = render_fill_rect(&s, make_rect(0, 8, 16, 4), COLOR_BLUE);
    expect_status(name, st, RENDER_OK);

    for (int y = 0; y < FB_H; y++)
    {
        uint32_t want = (y < 4) ? COLOR_RED : ((y < 8) ? COLOR_GREEN : COLOR_BLUE);

        for (int x = 0; x < FB_W; x++)
        {
            expect_color(name, x, y, want);
        }
    }

    expect_padding_intact(name);
    t_end(name);
}


static void test_t4a_fill_clip_left_top(void)
{
    const char *name = "T4a_fill_clip_left_top";
    render_surface_t s = make_canvas_surface();
    render_status_t st;

    t_begin();
    reset_canvas();

    /* 矩形覆盖 x=-3..2、y=-2..2，可见部分只有 (0,0)-(2,2) */
    st = render_fill_rect(&s, make_rect(-3, -2, 6, 5), COLOR_GREEN);
    expect_status(name, st, RENDER_OK);

    expect_rect(name, 0, 0, 3, 3, COLOR_GREEN);
    expect_padding_intact(name);

    /* 完全在左上方向之外：一个像素都不许画 */
    reset_canvas();
    st = render_fill_rect(&s, make_rect(-100, -100, 10, 10), COLOR_RED);
    expect_status(name, st, RENDER_OK);
    expect_nothing_drawn(name);

    t_end(name);
}


static void test_t4b_fill_clip_right_bottom(void)
{
    const char *name = "T4b_fill_clip_right_bottom";
    render_surface_t s = make_canvas_surface();
    render_status_t st;

    t_begin();
    reset_canvas();

    /* 起点 (13,10)，尺寸 50x50，可见部分只有 (13,10)-(15,11) */
    st = render_fill_rect(&s, make_rect(FB_W - 3, FB_H - 2, 50, 50), COLOR_BLUE);
    expect_status(name, st, RENDER_OK);

    expect_rect(name, FB_W - 3, FB_H - 2, 3, 2, COLOR_BLUE);
    expect_padding_intact(name);

    /* 正好贴合整个画布：不能多写一个像素 */
    reset_canvas();
    st = render_fill_rect(&s, make_rect(0, 0, FB_W, FB_H), COLOR_RED);
    expect_status(name, st, RENDER_OK);
    expect_all_visible(name, COLOR_RED);
    expect_padding_intact(name);

    /* 完全在右下方向之外 */
    reset_canvas();
    st = render_fill_rect(&s, make_rect(FB_W + 10, FB_H + 10, 10, 10), COLOR_GREEN);
    expect_status(name, st, RENDER_OK);
    expect_nothing_drawn(name);

    t_end(name);
}


static void test_t5_blit_normal(void)
{
    const char *name = "T5_blit_normal";
    render_surface_t dst = make_canvas_surface();
    render_surface_t src = make_sprite_surface();
    render_status_t st;

    t_begin();
    reset_canvas();
    reset_sprite();

    st = render_blit(&dst, &src, 6, 4);
    expect_status(name, st, RENDER_OK);

    expect_blit(name, 6, 4);
    expect_padding_intact(name);

    t_end(name);
}


static void test_t6_blit_clip(void)
{
    const char *name = "T6a_blit_clip_left_top";
    render_surface_t dst = make_canvas_surface();
    render_surface_t src = make_sprite_surface();

    t_begin();
    reset_canvas();
    reset_sprite();

    expect_status(name, render_blit(&dst, &src, -2, -3), RENDER_OK);
    expect_blit(name, -2, -3);
    expect_padding_intact(name);
    t_end(name);

    /* ---- 右下越界 ---- */
    name = "T6b_blit_clip_right_bottom";
    t_begin();
    reset_canvas();

    expect_status(name, render_blit(&dst, &src, FB_W - 2, FB_H - 2), RENDER_OK);
    expect_blit(name, FB_W - 2, FB_H - 2);
    expect_padding_intact(name);
    t_end(name);

    /* ---- 完全在画布外：一个像素都不许画 ---- */
    name = "T6c_blit_fully_outside";
    t_begin();
    reset_canvas();

    expect_status(name, render_blit(&dst, &src, -100, -100), RENDER_OK);
    expect_nothing_drawn(name);
    t_end(name);
}


static void test_t7_stride_not_equal_width(void)
{
    const char *name = "T7_stride_not_equal_width";
    render_surface_t s = make_canvas_surface();
    render_status_t st;

    t_begin();
    reset_canvas();

    /*
     * 填满整个可见宽度。
     *
     * 这是 stride 用错时最容易暴露的用例：如果实现拿 width(16) 当 stride，
     * 第二行会从第 16 个像素开始写，整块图会逐行偏移，右侧 padding 列
     * 也会被写脏。
     */
    st = render_fill_rect(&s, make_rect(0, 0, FB_W, FB_H), COLOR_BLUE);
    expect_status(name, st, RENDER_OK);
    expect_all_visible(name, COLOR_BLUE);
    expect_padding_intact(name);

    /*
     * 在最右侧一列逐行填不同颜色，确认每一行都落在自己的 stride 上。
     */
    reset_canvas();

    for (int y = 0; y < FB_H; y++)
    {
        pixel_t c = ROW_MARK(y);

        st = render_fill_rect(&s, make_rect(FB_W - 1, y, 1, 1), c);
        expect_status(name, st, RENDER_OK);
    }

    for (int y = 0; y < FB_H; y++)
    {
        expect_color(name, FB_W - 1, y, ROW_MARK(y));
    }

    for (int y = 0; y < FB_H; y++)
    {
        for (int x = 0; x < FB_W - 1; x++)
        {
            expect_color(name, x, y, COLOR_BG);
        }
    }

    expect_padding_intact(name);
    t_end(name);
}


static void test_t8_padding_intact(void)
{
    const char *name = "T8_padding_intact_after_mixed_ops";
    render_surface_t dst = make_canvas_surface();
    render_surface_t src = make_sprite_surface();

    t_begin();
    reset_canvas();
    reset_sprite();

    /* 一串混合操作之后，保护区必须仍然完好 */
    expect_status(name, render_fill_rect(&dst, make_rect(0, 0, FB_W, FB_H), COLOR_BG),
                  RENDER_OK);
    expect_status(name, render_fill_rect(&dst, make_rect(-5, -5, 20, 20), COLOR_RED),
                  RENDER_OK);
    expect_status(name, render_fill_rect(&dst, make_rect(FB_W - 1, FB_H - 1, 100, 100),
                                         COLOR_GREEN), RENDER_OK);
    expect_status(name, render_blit(&dst, &src, -3, 2), RENDER_OK);
    expect_status(name, render_blit(&dst, &src, FB_W - 3, FB_H - 3), RENDER_OK);
    expect_status(name, render_fill_rect(&dst, make_rect(0, 0, 0, 0), COLOR_BLUE),
                  RENDER_OK);
    expect_status(name, render_blit(&dst, &src, -100, -100), RENDER_OK);

    expect_padding_intact(name);
    t_end(name);
}


static void test_t9_fpga_backend_inert(void)
{
    const char *name = "T9_fpga_backend_inert";
    render_surface_t s = make_canvas_surface();
    render_status_t st;

    t_begin();
    reset_canvas();

    /*
     * 选中 FPGA 后端，但没有设置内存布局，本次构建也没有开启
     * BITBLT_ENABLE_HW_ACCESS：任何绘制都必须被安全拒绝，
     * 既不得触碰寄存器，也不得写画布。
     *
     * 这条用来证明"板端 smoke test 没有碰 BitBlt"。
     */
    (void)render_select(RENDER_BACKEND_FPGA);
    st = render_fill_rect(&s, make_rect(0, 0, 4, 4), COLOR_RED);

    if (st != RENDER_ERR_NOT_READY)
    {
        fail_text(name, render_strstatus(RENDER_ERR_NOT_READY),
                  render_strstatus(st));
    }

    /* 没有写任何像素，也没有碰保护区 */
    expect_nothing_drawn(name);

    /* 切回 CPU，不影响后续 */
    render_init();
    t_end(name);
}


/*
 * T10 直接测统一层的裁剪函数。
 *
 * 为什么单列一条：只走 CPU 后端时，统一层裁剪错了也看不出来 ——
 * 冻结的 sw_fill_rect 自己还会再裁一次，把错误兜住。
 * render_clip_rect() 是 renderer.h 导出的公开 API，直接测它才能让
 * 统一层的裁剪在板上可观测。
 */
static void test_t10_clip_rect_geometry(void)
{
    const char *name = "T10_clip_rect_geometry";
    render_rect_t out;
    int visible;

    t_begin();

    /* 负坐标：裁到 (0,0) 并缩小尺寸 */
    visible = render_clip_rect(FB_W, FB_H, make_rect(-3, -2, 6, 5), &out);
    if (!visible)
    {
        fail_text(name, "visible", "not visible");
    }
    else
    {
        expect_int(name, "x", 0, out.x);
        expect_int(name, "y", 0, out.y);
        expect_int(name, "w", 3, out.w);
        expect_int(name, "h", 3, out.h);
    }

    /* 右下越界 */
    visible = render_clip_rect(FB_W, FB_H, make_rect(FB_W - 3, FB_H - 2, 50, 50), &out);
    if (!visible)
    {
        fail_text(name, "visible", "not visible");
    }
    else
    {
        expect_int(name, "x", FB_W - 3, out.x);
        expect_int(name, "y", FB_H - 2, out.y);
        expect_int(name, "w", 3, out.w);
        expect_int(name, "h", 2, out.h);
    }

    /* 正好贴合：不能多切也不能少切 */
    visible = render_clip_rect(FB_W, FB_H, make_rect(0, 0, FB_W, FB_H), &out);
    if (!visible)
    {
        fail_text(name, "visible", "not visible");
    }
    else
    {
        expect_int(name, "x", 0, out.x);
        expect_int(name, "y", 0, out.y);
        expect_int(name, "w", FB_W, out.w);
        expect_int(name, "h", FB_H, out.h);
    }

    /* 完全在屏幕外：必须判定为不可见 */
    if (render_clip_rect(FB_W, FB_H, make_rect(-100, -100, 10, 10), &out))
    {
        fail_text(name, "not visible", "visible");
    }

    if (render_clip_rect(FB_W, FB_H, make_rect(FB_W + 10, FB_H + 10, 10, 10), &out))
    {
        fail_text(name, "not visible", "visible");
    }

    /* 空矩形与负尺寸 */
    if (render_clip_rect(FB_W, FB_H, make_rect(2, 2, 0, 4), &out))
    {
        fail_text(name, "not visible", "visible");
    }

    if (render_clip_rect(FB_W, FB_H, make_rect(2, 2, -4, -4), &out))
    {
        fail_text(name, "not visible", "visible");
    }

    /*
     * 32 位极值：RV32 上最容易出符号溢出的地方。
     * INT_MIN + INT_MAX == -1，所以这个矩形整体在左侧屏幕外。
     */
    if (render_clip_rect(FB_W, FB_H, make_rect(INT_MIN, INT_MIN, INT_MAX, INT_MAX), &out))
    {
        fail_text(name, "not visible", "visible");
    }

    /* 起点极负但宽度极大：应当裁成整块画布 */
    visible = render_clip_rect(FB_W, FB_H,
                               make_rect(INT_MIN / 2, INT_MIN / 2, INT_MAX, INT_MAX), &out);
    if (!visible)
    {
        fail_text(name, "visible", "not visible");
    }
    else
    {
        expect_int(name, "x", 0, out.x);
        expect_int(name, "y", 0, out.y);
        expect_int(name, "w", FB_W, out.w);
        expect_int(name, "h", FB_H, out.h);
    }

    t_end(name);
}


/* ------------------------------------------------------------------ */

void main(void)
{
    bsp_init();

    reset_canvas();

    bsp_printf("\r\n=== M1 Renderer Board Smoke Test ===\r\n");
    bsp_printf("pixel_t = %d bytes (expect %d), RENDER_PIXEL_BYTES = %d\r\n",
               (int)sizeof(pixel_t), (int)RENDER_PIXEL_BYTES, (int)RENDER_PIXEL_BYTES);
    bsp_printf("canvas %dx%d stride_px=%d (%d guard cols) rows=%d (%d guard rows)\r\n",
               FB_W, FB_H, FB_STRIDE, FB_STRIDE - FB_W, FB_ROWS, FB_ROWS - FB_H);
    bsp_printf("backend = CPU only; no BitBlt register access in this build\r\n\r\n");

    test_t1_pixel_size();
    test_t2_default_backend();
    test_t3_fill_normal();
    test_t4a_fill_clip_left_top();
    test_t4b_fill_clip_right_bottom();
    test_t5_blit_normal();
    test_t6_blit_clip();
    test_t7_stride_not_equal_width();
    test_t8_padding_intact();
    test_t9_fpga_backend_inert();
    test_t10_clip_rect_geometry();

    bsp_printf("\r\nPASS = %d\r\n", g_pass);
    bsp_printf("FAIL = %d\r\n", g_fail);

    if (g_fail == 0)
    {
        bsp_printf("M1 BOARD TEST PASSED\r\n");
    }
    else
    {
        bsp_printf("M1 BOARD TEST FAILED\r\n");
    }

    while (1)
    {
        /* 结果已打印完，停在这里等人工查看串口 */
    }
}
