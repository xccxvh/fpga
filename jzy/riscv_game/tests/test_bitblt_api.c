/*
 * BitBlt 驱动与适配层的 host 测试。
 *
 * 与另外两套测试的分工：
 *   tests/test_renderer.c     冻结的 M1 CPU 基线（不修改）
 *   tests/test_render_api.c   统一渲染层、裁剪、后端分发
 *   本文件                    B 冻结的 bitblt_* 接口 + renderer_fpga.c 适配层
 *
 * 测的是"适配层有没有把正确的参数、正确的超时、正确的错误码对上"，
 * 不测真实寄存器行为——那是板上 M2 联调的事。
 *
 * 构建要求：
 *   禁止定义 NDEBUG（assert 语义的判定会被移除）
 *   禁止定义 BITBLT_ENABLE_HW_ACCESS（本机测试不得接触任何寄存器）
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include "renderer.h"
#include "renderer_fpga.h"
#include "bitblt_api.h"
#include "bitblt_platform.h"
#include "framebuffer_layout.h"


#ifdef NDEBUG
#error "测试依赖判定失败即中止，禁止定义 NDEBUG"
#endif

#ifdef BITBLT_ENABLE_HW_ACCESS
#error "本机测试不得开启硬件访问：驱动必须始终走纯软件路径"
#endif


#define MAX_DIAG 8


static int g_pass = 0;
static int g_fail = 0;
static int t_fail = 0;
static int t_printed = 0;


/* ------------------------------------------------------------------ */
/* 判定与输出                                                          */
/* ------------------------------------------------------------------ */

static void t_begin(void)
{
    t_fail = 0;
    t_printed = 0;
}


static void t_end(const char *name)
{
    if (t_fail == 0)
    {
        g_pass++;
        printf("[PASS] %s\n", name);
    }
    else
    {
        g_fail++;
    }
}


static void fail_u64(const char *name, const char *what, uint64_t want, uint64_t got)
{
    if (t_printed < MAX_DIAG)
    {
        printf("  [FAIL] %s field=%s expected=0x%016llX actual=0x%016llX\n",
               name, what, (unsigned long long)want, (unsigned long long)got);
        t_printed++;
    }

    t_fail++;
}


static void expect_u64(const char *name, const char *what, uint64_t want, uint64_t got)
{
    if (want != got)
    {
        fail_u64(name, what, want, got);
    }
}


static void expect_str(const char *name, const char *what,
                       const char *want, const char *got)
{
    if (want == 0 || got == 0 || strcmp(want, got) != 0)
    {
        if (t_printed < MAX_DIAG)
        {
            printf("  [FAIL] %s field=%s expected=%s actual=%s\n",
                   name, what, want ? want : "(null)", got ? got : "(null)");
            t_printed++;
        }

        t_fail++;
    }
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


static uint64_t fake_ticks(void)
{
    return 12345ULL;
}


/* ------------------------------------------------------------------ */
/* T1 超时换算                                                         */
/* ------------------------------------------------------------------ */

static void test_timeout_conversion(void)
{
    const char *name = "T1_timeout_ms_to_ticks";

    t_begin();

    expect_u64(name, "0ms", 0ULL, render_timeout_ms_to_ticks(0u));
    expect_u64(name, "1ms", 100000ULL, render_timeout_ms_to_ticks(1u));
    expect_u64(name, "100ms", 10000000ULL, render_timeout_ms_to_ticks(100u));

    /*
     * 32 位乘法会在 42950 ms 附近回绕：
     *   42950 * 100000 = 4,295,000,000 > 2^32 = 4,294,967,296
     * 这几条就是专门盯着"先转 uint64_t 再乘"的。
     */
    expect_u64(name, "42949ms", 4294900000ULL, render_timeout_ms_to_ticks(42949u));
    expect_u64(name, "42950ms", 4295000000ULL, render_timeout_ms_to_ticks(42950u));
    expect_u64(name, "UINT32_MAX ms", 429496729500000ULL,
               render_timeout_ms_to_ticks(0xFFFFFFFFu));

    t_end(name);
}


/* ------------------------------------------------------------------ */
/* T2 错误码映射                                                       */
/* ------------------------------------------------------------------ */

static void test_result_mapping(void)
{
    const char *name = "T2_bitblt_result_mapping";

    t_begin();

    expect_u64(name, "OK", (uint64_t)RENDER_OK,
               (uint64_t)render_status_from_bitblt(BITBLT_OK));
    expect_u64(name, "EINVAL", (uint64_t)RENDER_ERR_INVALID_ARG,
               (uint64_t)render_status_from_bitblt(BITBLT_EINVAL));
    expect_u64(name, "EBUSY", (uint64_t)RENDER_ERR_BUSY,
               (uint64_t)render_status_from_bitblt(BITBLT_EBUSY));
    expect_u64(name, "ETIMEOUT", (uint64_t)RENDER_ERR_TIMEOUT,
               (uint64_t)render_status_from_bitblt(BITBLT_ETIMEOUT));
    expect_u64(name, "EHW", (uint64_t)RENDER_ERR_HW_ERROR,
               (uint64_t)render_status_from_bitblt(BITBLT_EHW));

    /* 枚举之外的值绝不能静默当成成功 */
    expect_u64(name, "未定义 1", (uint64_t)RENDER_ERR_HW_ERROR,
               (uint64_t)render_status_from_bitblt((bitblt_result_t)1));
    expect_u64(name, "未定义 -99", (uint64_t)RENDER_ERR_HW_ERROR,
               (uint64_t)render_status_from_bitblt((bitblt_result_t)-99));

    /* 映射结果要能被统一层的字符串表认出来 */
    expect_str(name, "字符串", "HW_ERROR",
               render_strstatus(render_status_from_bitblt(BITBLT_EHW)));

    t_end(name);
}


/* ------------------------------------------------------------------ */
/* T3 limits 来自权威布局头                                            */
/* ------------------------------------------------------------------ */

static void test_limits_from_layout(void)
{
    const char *name = "T3_limits_from_layout";
    gpu_limits_t lim;

    t_begin();

    lim = render_limits_from_layout();

    /* 四个字段必须就是 B 的 framebuffer_layout.h 里的值，不是本工程编的 */
    expect_u64(name, "ddr_base", (uint64_t)DDR_PHYSICAL_BASE, (uint64_t)lim.ddr_base);
    expect_u64(name, "ddr_size", (uint64_t)DDR_PHYSICAL_SIZE, (uint64_t)lim.ddr_size);
    expect_u64(name, "reserved_lo", (uint64_t)SYSTEM_RESERVED_BASE,
               (uint64_t)lim.reserved_lo);
    expect_u64(name, "reserved_hi",
               (uint64_t)SYSTEM_RESERVED_BASE + (uint64_t)SYSTEM_RESERVED_SIZE,
               (uint64_t)lim.reserved_hi);

    /* 交叉核对：系统保留区不得与 Framebuffer A 重叠 */
    if ((uint64_t)lim.reserved_hi > (uint64_t)FB_A_BASE)
    {
        fail_u64(name, "保留区压到 Framebuffer A", (uint64_t)FB_A_BASE,
                 (uint64_t)lim.reserved_hi);
    }

    /* 交叉核对：窗口必须覆盖到最后一块可分配区 */
    if ((uint64_t)lim.ddr_base + (uint64_t)lim.ddr_size
        < (uint64_t)DDR_FREE_BASE + (uint64_t)DDR_FREE_SIZE)
    {
        fail_u64(name, "窗口没盖住可分配区",
                 (uint64_t)DDR_FREE_BASE + (uint64_t)DDR_FREE_SIZE,
                 (uint64_t)lim.ddr_base + (uint64_t)lim.ddr_size);
    }

    t_end(name);
}


/* ------------------------------------------------------------------ */
/* T4 校验器在真实布局下的接受 / 拒绝                                  */
/* ------------------------------------------------------------------ */

static void test_validator_with_real_layout(void)
{
    const char *name = "T4_validator_with_real_layout";
    gpu_limits_t lim = render_limits_from_layout();
    gpu_params_t p;

    t_begin();

    memset(&p, 0, sizeof(p));
    p.operation = GPU_OP_FILL;
    p.dst_stride_bytes = (uint32_t)FB_STRIDE;
    p.width = 4u;
    p.height = 1u;

    /* Scratch 区：合法目标 */
    p.dst_addr_bytes = (uint32_t)SCRATCH_BASE;
    expect_u64(name, "SCRATCH fill", (uint64_t)RENDER_OK,
               (uint64_t)gpu_validate_fill(&lim, &p));

    /* Framebuffer A：合法目标，且不与保留区相交 */
    p.dst_addr_bytes = (uint32_t)FB_A_BASE;
    expect_u64(name, "Framebuffer A fill", (uint64_t)RENDER_OK,
               (uint64_t)gpu_validate_fill(&lim, &p));

    /* 系统保留区：必须拒绝 */
    p.dst_addr_bytes = (uint32_t)SYSTEM_RESERVED_BASE + 0x1000u;
    expect_u64(name, "保留区 fill", (uint64_t)RENDER_ERR_RANGE,
               (uint64_t)gpu_validate_fill(&lim, &p));

    /* 跨过 DDR 顶端：必须拒绝 */
    p.dst_addr_bytes = (uint32_t)DDR_PHYSICAL_BASE + (uint32_t)DDR_PHYSICAL_SIZE - 16u;
    p.dst_stride_bytes = 16u;
    p.height = 2u;
    expect_u64(name, "越过 DDR 顶端", (uint64_t)RENDER_ERR_RANGE,
               (uint64_t)gpu_validate_fill(&lim, &p));

    t_end(name);
}


/* ------------------------------------------------------------------ */
/* T5 适配层确实按正确参数调了驱动                                     */
/* ------------------------------------------------------------------ */

static pixel_t g_fb[16 * 4];

static void test_adapter_calls_driver(void)
{
    const char *name = "T5_adapter_calls_bitblt_translated";
    render_surface_t dst;
    render_surface_t src;
    gpu_limits_t lim;
    const bitblt_call_record_t *rec;
    render_status_t st;

    t_begin();

    lim = render_limits_from_layout();
    render_fpga_set_limits(&lim);

    dst.pixels = g_fb;
    dst.width = 16;
    dst.height = 4;
    dst.stride_px = 16;
    dst.phys_base = (uintptr_t)SCRATCH_BASE;

    render_init();
    (void)render_select(RENDER_BACKEND_FPGA);

    /* ---- FILL ---- */
    st = render_fill_rect(&dst, make_rect(0, 0, 4, 4), 0x00123456u);

    /* 本机构建没有硬件访问，驱动返回 BITBLT_EHW，映射成 HW_ERROR */
    expect_u64(name, "fill status", (uint64_t)RENDER_ERR_HW_ERROR, (uint64_t)st);

    rec = bitblt_last_call();

    if (rec == 0)
    {
        fail_u64(name, "有调用记录", 1u, 0u);
    }
    else
    {
        expect_u64(name, "dst_addr", (uint64_t)SCRATCH_BASE,
                   (uint64_t)rec->dst_addr_bytes);
        /* 字节 stride = 像素 stride × 每像素字节数 */
        expect_u64(name, "dst_stride", 16u * (uint64_t)RENDER_PIXEL_BYTES,
                   (uint64_t)rec->dst_stride_bytes);
        expect_u64(name, "width", 4u, (uint64_t)rec->width);
        expect_u64(name, "height", 4u, (uint64_t)rec->height);
        expect_u64(name, "color", 0x00123456u, (uint64_t)rec->color);
        expect_u64(name, "is_copy", 0u, (uint64_t)rec->is_copy);
        /* 超时必须已经换算成 tick，而不是原样传毫秒 */
        expect_u64(name, "timeout_ticks",
                   render_timeout_ms_to_ticks(RENDER_FPGA_TIMEOUT_MS),
                   rec->timeout_ticks);
        /* FILL 不该带源侧参数 */
        expect_u64(name, "src_addr", 0u, (uint64_t)rec->src_addr_bytes);
    }

    /* ---- COPY ---- */
    src.pixels = g_fb;
    src.width = 4;
    src.height = 4;
    src.stride_px = 16;
    src.phys_base = (uintptr_t)SCRATCH_BASE + 0x10000u;

    st = render_blit(&dst, &src, 0, 0);
    expect_u64(name, "copy status", (uint64_t)RENDER_ERR_HW_ERROR, (uint64_t)st);

    rec = bitblt_last_call();

    if (rec != 0)
    {
        expect_u64(name, "copy src_addr", (uint64_t)SCRATCH_BASE + 0x10000u,
                   (uint64_t)rec->src_addr_bytes);
        expect_u64(name, "copy src_stride", 16u * (uint64_t)RENDER_PIXEL_BYTES,
                   (uint64_t)rec->src_stride_bytes);
        expect_u64(name, "copy is_copy", 1u, (uint64_t)rec->is_copy);
        expect_u64(name, "copy width", 4u, (uint64_t)rec->width);
    }

    render_fpga_set_limits(0);
    render_init();

    t_end(name);
}


/* ------------------------------------------------------------------ */
/* T6 布局未设置时不得下发                                             */
/* ------------------------------------------------------------------ */

static void test_gate_not_ready(void)
{
    const char *name = "T6_not_ready_without_limits";
    render_surface_t dst;
    render_status_t st;

    t_begin();

    render_fpga_set_limits(0);
    render_init();
    (void)render_select(RENDER_BACKEND_FPGA);

    dst.pixels = g_fb;
    dst.width = 16;
    dst.height = 4;
    dst.stride_px = 16;
    dst.phys_base = (uintptr_t)SCRATCH_BASE;

    st = render_fill_rect(&dst, make_rect(0, 0, 4, 4), 0x00111111u);
    expect_u64(name, "未设布局", (uint64_t)RENDER_ERR_NOT_READY, (uint64_t)st);

    render_init();
    t_end(name);
}


/* ------------------------------------------------------------------ */
/* T7 未开启硬件访问时驱动不开火                                       */
/* ------------------------------------------------------------------ */

static void test_driver_stub(void)
{
    const char *name = "T7_driver_inert_without_hw_access";
    bitblt_result_t r;

    t_begin();

    expect_u64(name, "tick 未注入", 0u, (uint64_t)bitblt_tick_source_ready());

    r = bitblt_fill((uint32_t)SCRATCH_BASE, 4u, 1u, (uint32_t)FB_STRIDE, 0u, 1000ULL);
    expect_u64(name, "bitblt_fill", (uint64_t)BITBLT_EHW, (uint64_t)r);
    expect_u64(name, "fill 记录 is_copy", 0u, (uint64_t)bitblt_last_call()->is_copy);

    r = bitblt_copy((uint32_t)SCRATCH_BASE, (uint32_t)SCRATCH_BASE + 0x1000u,
                    4u, 1u, (uint32_t)FB_STRIDE, (uint32_t)FB_STRIDE, 1000ULL);
    expect_u64(name, "bitblt_copy", (uint64_t)BITBLT_EHW, (uint64_t)r);
    expect_u64(name, "copy 记录 is_copy", 1u, (uint64_t)bitblt_last_call()->is_copy);
    expect_u64(name, "copy 记录 src_addr", (uint64_t)SCRATCH_BASE,
               (uint64_t)bitblt_last_call()->src_addr_bytes);

    /* tick 注入接口可用 */
    bitblt_set_tick_source(fake_ticks);
    expect_u64(name, "tick 已注入", 1u, (uint64_t)bitblt_tick_source_ready());

    bitblt_set_tick_source(0);
    expect_u64(name, "tick 已清除", 0u, (uint64_t)bitblt_tick_source_ready());

    t_end(name);
}


/* ------------------------------------------------------------------ */

int main(void)
{
    /*
     * 关掉 stdout 缓冲：本文件判定失败后不会立即中止（要跑完全部用例统计），
     * 但保持与其它测试一致的无缓冲输出，便于逐个用例观察。
     */
    setvbuf(stdout, 0, _IONBF, 0);

    test_timeout_conversion();
    test_result_mapping();
    test_limits_from_layout();
    test_validator_with_real_layout();
    test_adapter_calls_driver();
    test_gate_not_ready();
    test_driver_stub();

    printf("\nPASS = %d\n", g_pass);
    printf("FAIL = %d\n", g_fail);

    if (g_fail == 0)
    {
        printf("All BitBlt API / adapter tests passed.\n");
    }
    else
    {
        printf("BitBlt API / adapter tests FAILED.\n");
    }

    return g_fail != 0;
}
