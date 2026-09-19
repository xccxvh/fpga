/*
 * 【已废弃，仅作兼容层保留】—— 见 gpu.h 顶部的说明。
 *
 * 真正的 BitBlt 驱动是 driver/bitblt_api.c，它实现 B 冻结的
 * bitblt_fill() / bitblt_copy() / bitblt_result_t，并且是【生产代码】里
 * 唯一引用 bitblt_regs.h 的文件（由 make check-hw-isolation 保证）。
 * 板级验证代码 tests/test_bitblt_board.c 也读寄存器（只读，查 VERSION），
 * 那是验证路径，不在生产代码之列。
 *
 * 本文件过去那段 BITBLT_ENABLE_HW_ACCESS 分支只是 TODO 占位，从未实现过，
 * 现在直接去掉：寄存器访问不该有两个地方。
 */

#include "gpu.h"


static gpu_timebase_fn g_timebase = 0;
static uint32_t        g_version = 0;
static uint32_t        g_last_status = 0;


void gpu_set_timebase(gpu_timebase_fn now_us)
{
    g_timebase = now_us;
}


int gpu_timebase_ready(void)
{
    return g_timebase != 0;
}


uint32_t gpu_version(void)
{
    return g_version;
}


uint32_t gpu_last_status(void)
{
    return g_last_status;
}


render_status_t gpu_init(uint32_t expected_version)
{
    (void)expected_version;

    /* 兼容层不做任何初始化；版本校验在 bitblt_api.c 的实现里 */
    return RENDER_ERR_UNSUPPORTED;
}


render_status_t gpu_fill(const gpu_params_t *p, uint32_t timeout_ms)
{
    if (p == 0)
        return RENDER_ERR_INVALID_ARG;

    (void)timeout_ms;

    /* 兼容层：恒返回 UNSUPPORTED，不触碰任何寄存器 */
    return RENDER_ERR_UNSUPPORTED;
}


render_status_t gpu_copy(const gpu_params_t *p, uint32_t timeout_ms)
{
    if (p == 0)
        return RENDER_ERR_INVALID_ARG;

    (void)timeout_ms;

    return RENDER_ERR_UNSUPPORTED;
}
