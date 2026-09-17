#include "gpu.h"


#ifdef BITBLT_ENABLE_HW_ACCESS

/*
 * 寄存器定义的唯一来源：B 组的 bitblt_regs.h。
 *
 * 本工程禁止复制、重定义或软链这个头文件——复制会制造第二份寄存器真相源，
 * 正是接口约定禁止的事情。用裸名 include 靠 -I 解析：
 * 工程里它在 04_project/bitblt_accel/sw/driver/，
 * 拷进 BSP 后它在 standalone/driver/，standalone.mk 已经加了该路径。
 */
#include "bitblt_regs.h"

#if !defined(__riscv)
#error "BITBLT_ENABLE_HW_ACCESS 只允许在 RISC-V 目标构建中开启"
#endif

/*
 * OPERATION 编码必须与 B 的寄存器定义一致。
 * 哪天 B 改了编码，这里会编译失败而不是静默发错命令。
 */
typedef char gpu_op_fill_must_match[(GPU_OP_FILL == BITBLT_OP_FILL) ? 1 : -1];
typedef char gpu_op_copy_must_match[(GPU_OP_COPY == BITBLT_OP_COPY) ? 1 : -1];

#endif


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

#ifdef BITBLT_ENABLE_HW_ACCESS
    /*
     * TODO(B/C 联调)：接通实数前保持骨架状态。
     *
     * 实现步骤：
     *   1. 读 BITBLT_VERSION；expected_version 非 0 且不相等时返回错误
     *   2. 复位/清状态：写 CONTROL.CLEAR
     *   3. 把 A 冻结的 DDR 窗口与保留区交给 render_fpga_set_limits()
     *
     * 在内存布局和像素格式都没确认之前，这里不下发任何命令。
     */
    return RENDER_ERR_UNSUPPORTED;
#else
    /* 本构建里根本不存在寄存器访问代码，没有任何可初始化的设备 */
    return RENDER_ERR_UNSUPPORTED;
#endif
}


#ifdef BITBLT_ENABLE_HW_ACCESS

/*
 * 真实下发路径——当前留空。
 *
 * TODO(骨架)：按接口约定第 3 节的时序实现：
 *   1. 读 STATUS；BUSY 置位则返回 RENDER_ERR_BUSY（硬件无命令 FIFO）
 *   2. 依次写 SRC_ADDR / DST_ADDR / WIDTH / HEIGHT /
 *      SRC_STRIDE / DST_STRIDE / COLOR / OPERATION
 *   3. 若 CPU 刚写过 DDR 源数据，执行 fence rw,rw
 *   4. 写 CONTROL.START
 *   5. 轮询 STATUS.DONE，用 g_timebase() 计算毫秒超时
 *   6. 读 STATUS，ERROR 置位则返回 RENDER_ERR_HW_ERROR
 *
 * 注意：这里只写寄存器，不碰 DDR 数据；读回由调用方负责 cache 维护。
 */
static render_status_t gpu_submit(const gpu_params_t *p, uint32_t timeout_ms)
{
    (void)p;
    (void)timeout_ms;

    return RENDER_ERR_UNSUPPORTED;
}

#endif


render_status_t gpu_fill(const gpu_params_t *p, uint32_t timeout_ms)
{
    if (p == 0)
        return RENDER_ERR_INVALID_ARG;

#ifdef BITBLT_ENABLE_HW_ACCESS
    return gpu_submit(p, timeout_ms);
#else
    (void)timeout_ms;
    /* 骨架：本构建不含任何寄存器访问代码，连碰都碰不到设备 */
    return RENDER_ERR_UNSUPPORTED;
#endif
}


render_status_t gpu_copy(const gpu_params_t *p, uint32_t timeout_ms)
{
    if (p == 0)
        return RENDER_ERR_INVALID_ARG;

#ifdef BITBLT_ENABLE_HW_ACCESS
    return gpu_submit(p, timeout_ms);
#else
    (void)timeout_ms;
    return RENDER_ERR_UNSUPPORTED;
#endif
}
