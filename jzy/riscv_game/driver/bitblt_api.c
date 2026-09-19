/*
 * BitBlt 驱动 —— B 冻结的 bitblt_api.h 的实现。
 *
 * 对外严格使用 bitblt_fill() / bitblt_copy() / bitblt_result_t /
 * uint64_t timeout_ticks，不自造第二套命名或错误码。
 *
 * 寄存器定义来自 B 的 bitblt_regs.h —— 本工程不复制、不重定义任何偏移或基地址。
 * 内存布局（Framebuffer A/B、素材区、Scratch）来自 B 的 framebuffer_layout.h，
 * 由平台层喂给渲染层，本文件不碰。
 *
 * 当前不实现 display_api.h 那一套，只做 BitBlt。
 */

#include "bitblt_api.h"
#include "bitblt_platform.h"


#ifdef BITBLT_ENABLE_HW_ACCESS

#if !defined(__riscv)
#error "BITBLT_ENABLE_HW_ACCESS 只允许在 RISC-V 目标构建中开启"
#endif

/* 寄存器定义的唯一来源。禁止复制或软链这个头文件到本工程 */
#include "bitblt_regs.h"

#endif


static bitblt_tick_fn g_now_ticks = 0;
static uint32_t      g_last_status = 0;


#ifndef BITBLT_ENABLE_HW_ACCESS

/*
 * 本机测试用的调用记录。
 *
 * 只在没有硬件访问的构建里存在：那种构建不会真的下发，
 * 记一份参数让 host 测试能验证适配层传下来的值是对的。
 * 板端构建里这段代码不存在，不给每次下发增加开销。
 */
static bitblt_call_record_t g_last_call;
static int                 g_has_call = 0;

const bitblt_call_record_t *bitblt_last_call(void)
{
    return g_has_call ? &g_last_call : 0;
}

static void record_call(uint32_t src_addr, uint32_t dst_addr,
                        uint32_t width, uint32_t height,
                        uint32_t src_stride, uint32_t dst_stride,
                        uint32_t color, int is_copy,
                        uint64_t timeout_ticks)
{
    g_last_call.dst_addr_bytes  = dst_addr;
    g_last_call.dst_stride_bytes = dst_stride;
    g_last_call.src_addr_bytes  = src_addr;
    g_last_call.src_stride_bytes = src_stride;
    g_last_call.width           = width;
    g_last_call.height          = height;
    g_last_call.color           = color;
    g_last_call.is_copy         = is_copy;
    g_last_call.timeout_ticks   = timeout_ticks;
    g_has_call = 1;
}

#endif /* !BITBLT_ENABLE_HW_ACCESS */


void bitblt_set_tick_source(bitblt_tick_fn now_ticks)
{
    g_now_ticks = now_ticks;
}


int bitblt_tick_source_ready(void)
{
    return g_now_ticks != 0;
}


uint32_t bitblt_last_status(void)
{
    return g_last_status;
}


#ifdef BITBLT_ENABLE_HW_ACCESS

/*
 * 轮询等待完成。
 *
 * 必须带超时：接口约定明确禁止无期限死循环。
 * 用 uint64_t 做差值比较，天然处理 tick 计数回绕。
 */
static bitblt_result_t wait_done(uint64_t timeout_ticks)
{
    uint64_t start;
    uint32_t status;

    if (g_now_ticks == 0)
    {
        /* 没有时基就不猜时钟：直接按超时处理，绝不无限等下去 */
        return BITBLT_ETIMEOUT;
    }

    start = g_now_ticks();

    for (;;)
    {
        status = bitblt_read(BITBLT_STATUS);

        if (status & BITBLT_STATUS_DONE)
        {
            break;
        }

        if ((g_now_ticks() - start) >= timeout_ticks)
        {
            return BITBLT_ETIMEOUT;
        }
    }

    g_last_status = status;

    /* DONE 与 ERROR 可能同时置位：ERROR 优先，命令判定为失败 */
    return (status & BITBLT_STATUS_ERROR) ? BITBLT_EHW : BITBLT_OK;
}


/*
 * 下发的公共路径。
 *
 * use_src 为 0 时是 FILL：硬件忽略 SRC_ADDR / SRC_STRIDE，不写它们。
 */
static bitblt_result_t submit(uint32_t src_addr, uint32_t dst_addr,
                              uint32_t width, uint32_t height,
                              uint32_t src_stride, uint32_t dst_stride,
                              uint32_t color, uint32_t operation,
                              int use_src, uint64_t timeout_ticks)
{
    uint32_t status;

    if (timeout_ticks == 0)
    {
        /* 约定要求所有等待都带超时，0 不是一个可用的超时值 */
        return BITBLT_EINVAL;
    }

    if (width == 0 || height == 0)
    {
        return BITBLT_EINVAL;
    }

    /* 硬件没有命令 FIFO，一次只执行一条。忙时下发会被硬件置 ERROR，先挡下来 */
    status = bitblt_read(BITBLT_STATUS);
    g_last_status = status;

    if (status & BITBLT_STATUS_BUSY)
    {
        return BITBLT_EBUSY;
    }

    bitblt_write(BITBLT_DST_ADDR, dst_addr);
    bitblt_write(BITBLT_WIDTH, width);
    bitblt_write(BITBLT_HEIGHT, height);
    bitblt_write(BITBLT_DST_STRIDE, dst_stride);

    if (use_src)
    {
        bitblt_write(BITBLT_SRC_ADDR, src_addr);
        bitblt_write(BITBLT_SRC_STRIDE, src_stride);
    }

    bitblt_write(BITBLT_COLOR, color);
    bitblt_write(BITBLT_OPERATION, operation);

    /*
     * CPU 刚写过的 DDR 源数据必须在 BitBlt 读之前可见。
     * 当前 SoC 已启用 D-cache；这里的 fence 只有排序作用，尚不能满足
     * V1.2 的 dma_sync_for_device() 契约。cache 同步封装落地前，本路径
     * 仍属于待迁移实现，不能据此宣称联合协议通过。
     */
    __asm__ volatile ("fence rw,rw" ::: "memory");

    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_CLEAR);
    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_START);

    return wait_done(timeout_ticks);
}

#endif /* BITBLT_ENABLE_HW_ACCESS */


bitblt_result_t bitblt_fill(uint32_t dst_addr,
                            uint32_t width, uint32_t height,
                            uint32_t dst_stride, uint32_t color,
                            uint64_t timeout_ticks)
{
#ifdef BITBLT_ENABLE_HW_ACCESS
    return submit(0u, dst_addr, width, height, 0u, dst_stride,
                  color, BITBLT_OP_FILL, 0, timeout_ticks);
#else
    record_call(0u, dst_addr, width, height, 0u, dst_stride,
                color, 0, timeout_ticks);
    return BITBLT_EHW;
#endif
}


bitblt_result_t bitblt_copy(uint32_t src_addr, uint32_t dst_addr,
                            uint32_t width, uint32_t height,
                            uint32_t src_stride, uint32_t dst_stride,
                            uint64_t timeout_ticks)
{
#ifdef BITBLT_ENABLE_HW_ACCESS
    return submit(src_addr, dst_addr, width, height, src_stride, dst_stride,
                  0u, BITBLT_OP_COPY, 1, timeout_ticks);
#else
    record_call(src_addr, dst_addr, width, height, src_stride, dst_stride,
                0u, 1, timeout_ticks);
    return BITBLT_EHW;
#endif
}


void bitblt_irq_handler(void)
{
    /*
     * PLIC 源 30 由 SYSTEM_AXI_A 上的设备共享，分发逻辑（还要读显示 STATUS）
     * 属于应用层。这里只负责把 BitBlt 的 STATUS 读回来留档，
     * DONE/ERROR 由下一次有效 START 或 CONTROL.CLEAR 清除。
     */
#ifdef BITBLT_ENABLE_HW_ACCESS
    g_last_status = bitblt_read(BITBLT_STATUS);
#endif
}
