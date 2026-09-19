#include "frame_swap.h"

#include "display_api.h"
#include "display_platform.h"
#include "framebuffer_format.h"
#include "protocol_frozen.h"
#include "protocol_unfrozen.h"


/* ------------------------------------------------------------------ */
/* 内部工具                                                            */
/* ------------------------------------------------------------------ */

static uint32_t g_last_display_version = 0;


static uintptr_t other_buffer(const frame_swap_t *fs, uintptr_t which)
{
    return (which == fs->fb_a) ? fs->fb_b : fs->fb_a;
}


static frame_swap_status_t map_display_result(display_result_t r)
{
    switch (r)
    {
    case DISPLAY_OK:       return FRAME_SWAP_OK;
    case DISPLAY_EINVAL:   return FRAME_SWAP_ERR_INVALID_ARG;
    case DISPLAY_EBUSY:    return FRAME_SWAP_ERR_BUSY;
    case DISPLAY_ETIMEOUT: return FRAME_SWAP_ERR_TIMEOUT;
    case DISPLAY_EHW:      return FRAME_SWAP_ERR_HW;
    }

    /* 冻结枚举之外的值按硬件错误上报，不要静默当成成功 */
    return FRAME_SWAP_ERR_HW;
}


/* 把状态机退回"没有后台、没有待确认换帧"的干净状态 */
static void release_back(frame_swap_t *fs)
{
    fs->back     = 0u;
    fs->pending  = 0u;
    fs->owner    = FRAME_PRODUCER_NONE;
    fs->state    = FRAME_SWAP_IDLE;
}


/* ------------------------------------------------------------------ */
/* 初始化                                                              */
/* ------------------------------------------------------------------ */

frame_swap_status_t frame_swap_init(frame_swap_t *fs,
                                    uintptr_t fb_a, uintptr_t fb_b,
                                    uintptr_t front)
{
    if (fs == 0)
        return FRAME_SWAP_ERR_INVALID_ARG;

    if (fb_a == 0u || fb_b == 0u || fb_a == fb_b)
        return FRAME_SWAP_ERR_INVALID_ARG;

    if (front != fb_a && front != fb_b)
        return FRAME_SWAP_ERR_INVALID_ARG;

    fs->state         = FRAME_SWAP_IDLE;
    fs->owner         = FRAME_PRODUCER_NONE;
    fs->fb_a          = fb_a;
    fs->fb_b          = fb_b;
    fs->front         = front;
    fs->back          = 0u;
    fs->pending       = 0u;
    fs->last_error    = FRAME_SWAP_OK;
    fs->swap_count    = 0u;
    fs->dropped_count = 0u;

    return FRAME_SWAP_OK;
}


/* ------------------------------------------------------------------ */
/* 后台 buffer 的授权                                                  */
/* ------------------------------------------------------------------ */

frame_swap_status_t frame_swap_acquire_back(frame_swap_t *fs,
                                            frame_producer_t who,
                                            uintptr_t *out_back)
{
    if (fs == 0 || out_back == 0)
        return FRAME_SWAP_ERR_INVALID_ARG;

    if (who == FRAME_PRODUCER_NONE)
        return FRAME_SWAP_ERR_INVALID_ARG;

    if (fs->state == FRAME_SWAP_FAILED)
    {
        /* 上一次换帧的结局还没查清楚，此时不能把任何 buffer 交出去：
           硬件可能已经把 pending 那个地址变成前台了。 */
        return FRAME_SWAP_ERR_FAILED_STATE;
    }

    /*
     * 只在 IDLE 受理。
     *
     * 这一条就是"确认 FRONT_ADDR 之前不得复用旧前台"的机械保证：
     * 提交之后状态会离开 IDLE，只有回读到 FRONT_ADDR 确实换了才回来。
     * 在此之前旧前台拿不到任何人手里。
     */
    if (fs->state != FRAME_SWAP_IDLE)
        return FRAME_SWAP_ERR_BUSY;

    /*
     * 后台永远是"不是当前前台"的那一块。
     * 结构上保证生产者拿不到正在扫描的前台。
     */
    fs->back  = other_buffer(fs, fs->front);
    fs->owner = who;
    fs->state = FRAME_SWAP_PRODUCING;

    *out_back = fs->back;

    return FRAME_SWAP_OK;
}


/* ------------------------------------------------------------------ */
/* 生产者完成                                                          */
/* ------------------------------------------------------------------ */

frame_swap_status_t frame_swap_producer_done(frame_swap_t *fs,
                                             frame_producer_t who,
                                             int frame_ok)
{
    if (fs == 0)
        return FRAME_SWAP_ERR_INVALID_ARG;

    if (fs->state == FRAME_SWAP_FAILED)
        return FRAME_SWAP_ERR_FAILED_STATE;

    if (fs->state != FRAME_SWAP_PRODUCING)
        return FRAME_SWAP_ERR_BUSY;

    /* 只有当前后台的所有者能报告完成，别人说了不算 */
    if (who != fs->owner)
        return FRAME_SWAP_ERR_WRONG_OWNER;

    if (!frame_ok)
    {
        /*
         * 坏帧：释放后台，前台一个字节都不动，也【不】提交换帧。
         * 迁移文档第 3 条：字节数、包序号、FIFO、BRESP 全对才算完整可显示，
         * 失败帧不得提交换帧。
         */
        fs->dropped_count++;
        release_back(fs);
        return FRAME_SWAP_ERR_FRAME_BAD;
    }

    fs->state = FRAME_SWAP_READY;

    return FRAME_SWAP_OK;
}


/* ------------------------------------------------------------------ */
/* 提交换帧                                                            */
/* ------------------------------------------------------------------ */

frame_swap_status_t frame_swap_submit(frame_swap_t *fs, uint64_t timeout_ticks)
{
    display_result_t r;
    uint32_t         front_readback;

    if (fs == 0)
        return FRAME_SWAP_ERR_INVALID_ARG;

    if (fs->state == FRAME_SWAP_FAILED)
        return FRAME_SWAP_ERR_FAILED_STATE;

    if (fs->state == FRAME_SWAP_REQUESTED)
        return FRAME_SWAP_ERR_BUSY;

    if (fs->state != FRAME_SWAP_READY)
        return FRAME_SWAP_ERR_NOT_READY;

    if (timeout_ticks == 0u)
    {
        /* 接口约定禁止无期限等待，0 不是一个可用的超时值 */
        return FRAME_SWAP_ERR_INVALID_ARG;
    }

    if (!display_bus_path_is_axi())
    {
        /*
         * 显示控制一定走 SYSTEM_AXI_A（迁移文档已选定）。
         * 没声明就说明平台没初始化，不要猜路径。
         */
        return FRAME_SWAP_ERR_NOT_READY;
    }

    fs->pending = fs->back;
    fs->state   = FRAME_SWAP_REQUESTED;

    r = display_queue_swap((uint32_t)fs->pending);
    if (r != DISPLAY_OK)
    {
        fs->state      = FRAME_SWAP_FAILED;
        fs->last_error = map_display_result(r);
        fs->dropped_count++;
        return fs->last_error;
    }

    r = display_wait_swap(timeout_ticks);
    if (r != DISPLAY_OK)
    {
        fs->state      = FRAME_SWAP_FAILED;
        fs->last_error = map_display_result(r);
        fs->dropped_count++;
        return fs->last_error;
    }

    /*
     * 关键一步：不能凭 SWAP_DONE 就算成功，必须回读 FRONT_ADDR
     * 确认它真的换到了刚提交的地址。状态位和实际扫描基址是两个事实。
     */
    front_readback = display_get_front();

    if (front_readback != (uint32_t)fs->pending)
    {
        fs->state      = FRAME_SWAP_FAILED;
        fs->last_error = FRAME_SWAP_ERR_FRONT_UNCHANGED;
        fs->dropped_count++;
        return fs->last_error;
    }

    fs->front = fs->pending;
    release_back(fs);
    fs->swap_count++;

    return FRAME_SWAP_OK;
}


frame_swap_status_t frame_swap_resolve_failure(frame_swap_t *fs)
{
    uint32_t front_now;

    if (fs == 0)
        return FRAME_SWAP_ERR_INVALID_ARG;

    if (fs->state != FRAME_SWAP_FAILED)
        return FRAME_SWAP_ERR_NOT_READY;

    front_now = display_get_front();

    if (front_now == (uint32_t)fs->pending && fs->pending != 0u)
    {
        /*
         * 硬件其实换过去了，只是刚才没读到确认。
         * 按成功记账：前台就在 pending，旧前台从此重新可写。
         */
        fs->front = fs->pending;
        release_back(fs);
        fs->swap_count++;
        fs->last_error = FRAME_SWAP_OK;
        return FRAME_SWAP_OK;
    }

    /*
     * 前台没换。此时 pending 那块 buffer 的处境是"不确定"：
     * 硬件可能已经在扫它，也可能一辈子都不会扫。保守起见把前台
     * 保持在原来的地址上，并让调用方看到错误码去查板子。
     */
    release_back(fs);
    fs->last_error = FRAME_SWAP_ERR_FRONT_UNCHANGED;

    return FRAME_SWAP_ERR_FRONT_UNCHANGED;
}


uintptr_t frame_swap_front(const frame_swap_t *fs)
{
    return (fs != 0) ? fs->front : 0u;
}


/* ------------------------------------------------------------------ */
/* 显示控制器初始化                                                    */
/* ------------------------------------------------------------------ */

uint32_t frame_swap_last_display_version(void)
{
    return g_last_display_version;
}


frame_swap_status_t frame_swap_display_init(uintptr_t initial_front)
{
    display_result_t r;
    uint32_t         version;

    if (initial_front == 0u)
        return FRAME_SWAP_ERR_INVALID_ARG;

    /*
     * 统一走 SYSTEM_AXI_A。迁移文档已明确否掉 A 组草案里的
     * APB 0xF8100000 那一套，本工程不提供那条路的开关。
     *
     * 必须先声明路径，否则下面读 VERSION 会返回 0（读不到寄存器），
     * 那会被当成"版本不匹配"而报出一个误导性的错误。
     */
    display_set_bus_path_axi();

    /*
     * 1) 版本先于一切。
     *
     * 烧的是旧位流（XRGB8888 的 V0.2/V0.4）时，按 RGB565 写几何与
     * FORMAT 不会报错，只会画出一屏乱码 —— 那种故障在现场很难归因。
     * 所以版本不对就在这里拦住，一个配置寄存器都不写。
     */
    version = display_get_version();
    g_last_display_version = version;

    if (!proto_display_version_compatible(version))
        return FRAME_SWAP_ERR_VERSION_MISMATCH;

    /*
     * 2) 版本对了才写配置。
     *
     * 几何全部来自 framebuffer_format.h；FORMAT 取已冻结的 RGB565 枚举值，
     * 这里【不】出现任何数字。
     */
    r = display_init((uint32_t)initial_front,
                     FMT_WIDTH, FMT_HEIGHT, FMT_STRIDE,
                     proto_display_format_default());

    return map_display_result(r);
}


/* ------------------------------------------------------------------ */
/* UDP 完成通知                                                        */
/* ------------------------------------------------------------------ */

frame_swap_status_t frame_swap_udp_frame_ready(frame_swap_t *fs,
                                               uintptr_t reported_base,
                                               int frame_ok)
{
    if (fs == 0)
        return FRAME_SWAP_ERR_INVALID_ARG;

    /*
     * UDP 完成通知的寄存器/中断地址尚未分配。
     * 能力表没声明"可用"之前，这条通路整个不存在 ——
     * 既不去读猜出来的地址，也不假装 Udp 帧已经就绪。
     */
    if (!protocol_udp_completion_available())
        return FRAME_SWAP_ERR_NOT_READY;

    if (fs->state == FRAME_SWAP_FAILED)
        return FRAME_SWAP_ERR_FAILED_STATE;

    if (fs->state != FRAME_SWAP_PRODUCING || fs->owner != FRAME_PRODUCER_UDP)
        return FRAME_SWAP_ERR_WRONG_OWNER;

    /*
     * 硬件报回来的实际写入基址必须等于软件授权的那一块。
     * 迁移文档：「网络包自带 slot 或旧 active_slot^1 不能覆盖软件授权」——
     * 对不上就说明有人在写没被授权的 buffer，直接按坏帧处理。
     */
    if (reported_base != fs->back)
    {
        fs->dropped_count++;
        release_back(fs);
        return FRAME_SWAP_ERR_WRONG_OWNER;
    }

    return frame_swap_producer_done(fs, FRAME_PRODUCER_UDP, frame_ok);
}


/* ------------------------------------------------------------------ */
/* 诊断字符串                                                          */
/* ------------------------------------------------------------------ */

const char *frame_swap_strstate(frame_swap_state_t st)
{
    switch (st)
    {
    case FRAME_SWAP_IDLE:      return "IDLE";
    case FRAME_SWAP_PRODUCING: return "PRODUCING";
    case FRAME_SWAP_READY:     return "READY";
    case FRAME_SWAP_REQUESTED: return "REQUESTED";
    case FRAME_SWAP_FAILED:    return "FAILED";
    }

    return "?";
}


const char *frame_swap_strstatus(frame_swap_status_t st)
{
    switch (st)
    {
    case FRAME_SWAP_OK:                   return "OK";
    case FRAME_SWAP_ERR_INVALID_ARG:      return "INVALID_ARG";
    case FRAME_SWAP_ERR_NOT_READY:        return "NOT_READY";
    case FRAME_SWAP_ERR_BUSY:             return "BUSY";
    case FRAME_SWAP_ERR_WRONG_OWNER:      return "WRONG_OWNER";
    case FRAME_SWAP_ERR_FRAME_BAD:        return "FRAME_BAD";
    case FRAME_SWAP_ERR_TIMEOUT:          return "TIMEOUT";
    case FRAME_SWAP_ERR_HW:               return "HW";
    case FRAME_SWAP_ERR_FRONT_UNCHANGED:  return "FRONT_UNCHANGED";
    case FRAME_SWAP_ERR_VERSION_MISMATCH: return "VERSION_MISMATCH";
    case FRAME_SWAP_ERR_FAILED_STATE:     return "FAILED_STATE";
    }

    return "?";
}
