/*
 * 显示控制器驱动 —— B 冻结的 display_api.h 的实现。
 *
 * 对外严格使用 display_init() / display_queue_swap() / display_wait_swap() /
 * display_get_front() / display_irq_handler() / display_result_t，
 * 不自造第二套命名或错误码。
 *
 * 寄存器定义来自 B 的 display_regs.h —— 本工程不复制、不重定义任何偏移
 * 或基地址。总线路径固定为 SYSTEM_AXI_A（统一规范已冻结），基地址由 B 的
 * display_regs.h 提供，本工程不复制。
 * 不提供 APB 0xF8100000 那条路的切换开关：那条路已被明确否掉。
 *
 * 换帧的【顺序】不在这里实现。本文件只做单条寄存器操作；
 * "授权后台 -> 生产者完成 -> 提交 -> 等 SWAP_DONE -> 确认 FRONT_ADDR"
 * 这套状态机在 render/frame_swap.c 里，由 C 组软件作为唯一提交者执行。
 */

#include <string.h>

#include "display_api.h"
#include "display_platform.h"


#ifdef DISPLAY_ENABLE_HW_ACCESS

#if !defined(__riscv)
#error "DISPLAY_ENABLE_HW_ACCESS 只允许在 RISC-V 目标构建中开启"
#endif

/* 寄存器定义的唯一来源。禁止复制或软链这个头文件到本工程 */
#include "display_regs.h"

#endif


static int               g_bus_is_axi = 0;
static display_tick_fn   g_now_ticks = 0;
static uint32_t          g_last_status = 0;


#ifndef DISPLAY_ENABLE_HW_ACCESS

static display_call_record_t g_last_call;
static uint32_t              g_model_front = 0;
static uint32_t              g_model_version = 0;
static int                   g_model_swap_ok = 1;
static int                   g_model_swap_updates_front = 1;

const display_call_record_t *display_last_call(void)
{
    return (g_last_call.queued || g_last_call.inited) ? &g_last_call : 0;
}

void display_test_set_swap_ok(int ok)
{
    g_model_swap_ok = ok ? 1 : 0;
}

void display_test_set_front(uint32_t front)
{
    g_model_front = front;
}

void display_test_set_version(uint32_t version)
{
    g_model_version = version;
}

void display_test_clear_call(void)
{
    memset(&g_last_call, 0, sizeof(g_last_call));
}

void display_test_set_swap_updates_front(int updates)
{
    g_model_swap_updates_front = updates ? 1 : 0;
}

#endif /* !DISPLAY_ENABLE_HW_ACCESS */


void display_set_bus_path_axi(void)
{
    g_bus_is_axi = 1;
}


int display_bus_path_is_axi(void)
{
    return g_bus_is_axi;
}


void display_set_tick_source(display_tick_fn now_ticks)
{
    g_now_ticks = now_ticks;
}


int display_tick_source_ready(void)
{
    return g_now_ticks != 0;
}


uint32_t display_last_status(void)
{
    return g_last_status;
}


uint32_t display_get_version(void)
{
#ifdef DISPLAY_ENABLE_HW_ACCESS

    if (!g_bus_is_axi)
        return 0u;

    return display_read(DISPLAY_VERSION);

#else

    return g_model_version;

#endif
}


display_result_t display_init(uint32_t front_addr,
                              uint32_t width, uint32_t height,
                              uint32_t stride, uint32_t format)
{
    if (width == 0u || height == 0u)
        return DISPLAY_EINVAL;

    /*
     * stride 必须 16 字节对齐（接口约定 §4 的数据面约束）。
     * "stride >= width * 每像素字节数"不在这里判：那需要知道像素格式，
     * 而格式由调用方按已冻结的枚举值给出，本层不假定。
     * 调用方（frame_swap）在选格式时已经核对过。
     */
    if ((stride % 16u) != 0u)
        return DISPLAY_EINVAL;

    if ((front_addr % 16u) != 0u)
        return DISPLAY_EINVAL;

    if (!g_bus_is_axi)
    {
        /*
         * 没有声明总线路径就不碰寄存器。默认拒绝而不是默认 AXI：
         * 显示控制器的地址空间与 BitBlt 相邻，猜错会写到别的设备上。
         */
        return DISPLAY_EINVAL;
    }

#ifdef DISPLAY_ENABLE_HW_ACCESS

    display_write(DISPLAY_WIDTH, width);
    display_write(DISPLAY_HEIGHT, height);
    display_write(DISPLAY_STRIDE, stride);
    display_write(DISPLAY_FORMAT, format);
    display_write(DISPLAY_IRQ_ENABLE,
                  DISPLAY_IRQ_SWAP_DONE | DISPLAY_IRQ_ERROR);

    /* 第一帧：把初始前台放进 NEXT_ADDR 再请求一次切换，
       显示控制器只在 VBlank 更新 FRONT_ADDR。 */
    display_write(DISPLAY_NEXT_ADDR, front_addr);
    display_write(DISPLAY_CONTROL, DISPLAY_CONTROL_ENABLE);
    display_write(DISPLAY_CONTROL,
                  DISPLAY_CONTROL_ENABLE | DISPLAY_CONTROL_SWAP_REQUEST);

    g_last_status = display_read(DISPLAY_STATUS);

#else

    memset(&g_last_call, 0, sizeof(g_last_call));

    g_model_front = front_addr;
    g_last_call.front_addr = front_addr;
    g_last_call.width  = width;
    g_last_call.height = height;
    g_last_call.stride = stride;
    g_last_call.format = format;
    g_last_call.next_addr = 0u;
    g_last_call.queued = 0;
    g_last_call.inited = 1;

#endif

    return DISPLAY_OK;
}


display_result_t display_queue_swap(uint32_t next_addr)
{
    if ((next_addr % 16u) != 0u)
        return DISPLAY_EINVAL;

    if (next_addr == 0u)
        return DISPLAY_EINVAL;

    if (!g_bus_is_axi)
        return DISPLAY_EINVAL;

#ifdef DISPLAY_ENABLE_HW_ACCESS

    display_write(DISPLAY_NEXT_ADDR, next_addr);
    display_write(DISPLAY_CONTROL,
                  DISPLAY_CONTROL_ENABLE | DISPLAY_CONTROL_SWAP_REQUEST);

    g_last_status = display_read(DISPLAY_STATUS);

#else

    memset(&g_last_call, 0, sizeof(g_last_call));

    g_last_call.next_addr = next_addr;
    g_last_call.queued = 1;

#endif

    return DISPLAY_OK;
}


display_result_t display_wait_swap(uint64_t timeout_ticks)
{
    if (!g_bus_is_axi)
        return DISPLAY_EINVAL;

    if (g_now_ticks == 0)
    {
        /* 没有时基就不猜时钟：按超时处理，绝不无限等 */
        return DISPLAY_ETIMEOUT;
    }

#ifdef DISPLAY_ENABLE_HW_ACCESS

    {
        uint64_t start = g_now_ticks();
        uint32_t status;

        for (;;)
        {
            status = display_read(DISPLAY_STATUS);
            g_last_status = status;

            if ((status & DISPLAY_STATUS_ERROR) != 0u)
                return DISPLAY_EHW;

            if ((status & DISPLAY_STATUS_SWAP_DONE) != 0u)
                break;

            if ((g_now_ticks() - start) >= timeout_ticks)
                return DISPLAY_ETIMEOUT;
        }
    }

#else

    (void)timeout_ticks;

    if (!g_model_swap_ok)
        return DISPLAY_ETIMEOUT;

    if (g_model_swap_updates_front)
        g_model_front = g_last_call.next_addr;

#endif

    return DISPLAY_OK;
}


uint32_t display_get_front(void)
{
#ifdef DISPLAY_ENABLE_HW_ACCESS

    uint32_t front;

    if (!g_bus_is_axi)
        return 0u;

    front = display_read(DISPLAY_FRONT_ADDR);
    g_last_status = display_read(DISPLAY_STATUS);

    return front;

#else

    return g_model_front;

#endif
}


void display_irq_handler(void)
{
    /*
     * PLIC 源 30 由 SYSTEM_AXI_A 上的设备共享（BitBlt 与显示）。
     * 分发属于应用层：本函数只把显示 STATUS 读回来留档，
     * SWAP_DONE 由换帧状态机在 wait_swap 里消费。
     */
#ifdef DISPLAY_ENABLE_HW_ACCESS

    if (g_bus_is_axi)
        g_last_status = display_read(DISPLAY_STATUS);

#endif
}
