#ifndef FRAME_SWAP_H
#define FRAME_SWAP_H

#include <stdint.h>

/*
 * 换帧状态机 —— C 组软件是【唯一】的 SWAP 提交者。
 *
 * 依据：07_docs/interfaces/unified_fpga_interface_spec_v1.1.md
 *       「帧缓冲所有权状态机」
 *
 * 硬件（A 组的 UDP 接收、B 组的 BitBlt 引擎）都【不允许】直接改显示控制器的
 * 前台基址。它们只能：
 *   1. 向软件申请一个后台 buffer 的写所有权；
 *   2. 写完以后向软件报告"这一帧好了"或"这一帧坏了"。
 * 由本状态机决定什么时候写 NEXT_ADDR 和 SWAP_REQUEST。
 *
 * ── 强制顺序 ──
 *
 *   取得/确认后台 buffer -> 生产者完成 -> 提交 swap
 *   -> 等待 SWAP_DONE -> 读回并确认 FRONT_ADDR 已切换
 *   -> 才允许复用旧前台 buffer
 *
 * "才允许复用"是靠结构保证的，不是靠调用方自觉：
 * acquire_back() 只在 IDLE 状态下受理，而 IDLE 只在
 * 「SWAP_DONE 且 FRONT_ADDR 已确认切换」之后才会重新到达。
 * 因此【提交之后、确认之前，旧前台不可能被任何人拿到】。
 *
 * ── 状态迁移 ──
 *
 *   IDLE ──acquire_back(who)──> PRODUCING     后台已授权，独占给 who
 *   PRODUCING ──producer_done(who, ok=1)──> READY
 *   PRODUCING ──producer_done(who, ok=0)──> IDLE   坏帧：释放后台，前台不动
 *   READY ──submit()──> IDLE                  成功：前台换到后台，旧前台转为可写
 *   READY ──submit()──> FAILED                失败/超时：保留原前台与错误供诊断
 *   FAILED ──resolve_failure()──> IDLE        重新读 FRONT_ADDR 判定实际状态
 *
 * 坏帧【绝不】提交换帧：这是统一规范的硬要求
 * （字节数、包序号、FIFO 溢出、全部 BRESP 都对了才算"完整可显示"）。
 */

#include "render_status.h"


typedef enum
{
    FRAME_SWAP_IDLE = 0,   /* 没有进行中的换帧，可以授权下一个后台 */
    FRAME_SWAP_PRODUCING,  /* 后台已授权给某个生产者，等它写完 */
    FRAME_SWAP_READY,      /* 生产者已完成，等软件提交换帧 */
    FRAME_SWAP_REQUESTED,  /* 已提交，等 SWAP_DONE 与 FRONT_ADDR 确认 */
    FRAME_SWAP_FAILED      /* 提交失败：前台保持原值，错误状态待诊断 */
} frame_swap_state_t;


typedef enum
{
    FRAME_PRODUCER_NONE = 0,
    FRAME_PRODUCER_UDP,     /* A 组网络接收，写后台 */
    FRAME_PRODUCER_BITBLT   /* B 组加速器，写后台 */
} frame_producer_t;


typedef enum
{
    FRAME_SWAP_OK = 0,

    FRAME_SWAP_ERR_INVALID_ARG,

    /* 未初始化 / 显示总线未声明 / 已冻结硬件能力尚未探测可用 */
    FRAME_SWAP_ERR_NOT_READY,

    /* 已有进行中的换帧，或后台已被占用 */
    FRAME_SWAP_ERR_BUSY,

    /* 调用者不是当前后台的写所有者（含"根本没有所有者"） */
    FRAME_SWAP_ERR_WRONG_OWNER,

    /* 生产者报告这一帧不完整，按坏帧处理，未提交 */
    FRAME_SWAP_ERR_FRAME_BAD,

    /* 提交时硬件返回错误，或等待 SWAP_DONE 超时 */
    FRAME_SWAP_ERR_TIMEOUT,
    FRAME_SWAP_ERR_HW,

    /* SWAP_DONE 置位了，但读回的 FRONT_ADDR 不是刚提交的地址 */
    FRAME_SWAP_ERR_FRONT_UNCHANGED,

    /* 显示控制器 VERSION 与当前联合工程约定不符（期望 V3.0 = 0x00030000）。
       版本不匹配时不写任何配置寄存器、不提交任何换帧 —— fail-fast。 */
    FRAME_SWAP_ERR_VERSION_MISMATCH,

    /* 上一次失败还没 resolve */
    FRAME_SWAP_ERR_FAILED_STATE
} frame_swap_status_t;


typedef struct
{
    frame_swap_state_t state;
    frame_producer_t   owner;        /* PRODUCING/READY 时有效 */

    uintptr_t          fb_a;         /* 两个 Framebuffer 的物理基址 */
    uintptr_t          fb_b;
    uintptr_t          front;        /* 当前正在扫描的前台 */
    uintptr_t          back;         /* 已授权的后台；0 = 未授权 */
    uintptr_t          pending;      /* 已提交待确认的地址 */

    frame_swap_status_t last_error;  /* 最近一次失败原因，供诊断 */
    uint32_t           swap_count;   /* 成功换帧次数 */
    uint32_t           dropped_count;/* 因坏帧/失败而未换的帧数 */
} frame_swap_t;


/*
 * 用两个 Framebuffer 的物理基址初始化，front 必须是其中之一。
 *
 * 地址来自 B 的权威 framebuffer_layout.h（FB_A_BASE / FB_B_BASE），
 * 由平台层传入；本模块不重复硬编码任何地址。
 */
frame_swap_status_t frame_swap_init(frame_swap_t *fs,
                                    uintptr_t fb_a, uintptr_t fb_b,
                                    uintptr_t front);


/*
 * 申请后台 buffer 的写所有权。
 *
 * 成功时 *out_back 得到【另一个】buffer 的物理地址（永远不是当前前台）。
 * 同一时刻只允许一个生产者持有后台：持有期间再次调用返回 BUSY，
 * 换其他生产者调用返回 BUSY（不会抢占）。
 *
 * 仅在 IDLE 状态受理。
 */
frame_swap_status_t frame_swap_acquire_back(frame_swap_t *fs,
                                            frame_producer_t who,
                                            uintptr_t *out_back);

/*
 * 生产者报告完成。
 *
 * frame_ok 必须由【生产者自己】按完整可显示判据算出来：
 *   UDP    ：字节数 == 期望值、包序号/帧ID 正确、无 FIFO 溢出、
 *            全部 DDR 写响应 BRESP=OKAY
 *   BitBlt ：DONE=1 且 ERROR=0
 *
 * frame_ok 为 0 时释放后台、保持前台不变，并计入 dropped_count。
 * 坏帧不会被提交换帧。
 */
frame_swap_status_t frame_swap_producer_done(frame_swap_t *fs,
                                             frame_producer_t who,
                                             int frame_ok);

/*
 * 提交换帧：写 NEXT_ADDR -> SWAP_REQUEST -> 等 SWAP_DONE -> 读回 FRONT_ADDR。
 *
 * 只有回读的 FRONT_ADDR 等于刚提交的地址才算成功；成功后才回到 IDLE，
 * 旧前台在那一刻才重新可写。
 */
frame_swap_status_t frame_swap_submit(frame_swap_t *fs, uint64_t timeout_ticks);

/*
 * 处理一次失败：重新读 FRONT_ADDR 判断硬件实际停在哪里。
 *
 * 若前台其实已经换过去了（硬件换了但状态位读取失败），按成功记账；
 * 否则保持原前台。两种情况下都回到 IDLE，让上层可以继续。
 */
frame_swap_status_t frame_swap_resolve_failure(frame_swap_t *fs);

/* 当前前台物理地址 */
uintptr_t frame_swap_front(const frame_swap_t *fs);

/* 状态名，供串口日志 */
const char *frame_swap_strstate(frame_swap_state_t st);
const char *frame_swap_strstatus(frame_swap_status_t st);


/*
 * 用现行几何初始化显示控制器，初始前台由平台指定。
 *
 * 协议已冻结（见 driver/protocol_frozen.h），所以这里不再有"格式未知"
 * 这个分支。顺序是：
 *
 *   1. 先读显示控制器 VERSION，要求等于 DISPLAY_VERSION_RGB565
 *      （V3.0 = 0x00030000）。不匹配就 fail-fast 返回
 *      FRAME_SWAP_ERR_VERSION_MISMATCH，【不写任何配置寄存器】，
 *      后续也不允许提交任何换帧。
 *   2. 版本对了才写几何与 FORMAT = DISPLAY_FORMAT_RGB565 (= 1)。
 *
 * 版本不匹配通常意味着烧的是旧位流（例如 XRGB8888 的 V0.2/V0.4），
 * 那种位流按 RGB565 配置会画出乱码而不是报错，所以必须在写之前拦住。
 */
frame_swap_status_t frame_swap_display_init(uintptr_t initial_front);

/* 最近一次 frame_swap_display_init() 读到的显示版本，供串口排查 */
uint32_t frame_swap_last_display_version(void);


/*
 * A 组 UDP 通路报告"这一帧完整可显示"。
 *
 * UDP Frame RX V2.0 已由统一规范冻结，但本软件尚未实现正式 MMIO 驱动。
 * 在平台完成版本探测并声明硬件可用之前，本函数一律返回
 * FRAME_SWAP_ERR_NOT_READY，不能把旧 V1 原型当成兼容实现。
 *
 * 注意：这个函数只是把"UDP 说它写完了"翻译成一次 producer_done，
 * 前提是软件【已经】通过 frame_swap_acquire_back() 把这块后台授权给了
 * UDP；统一规范禁止网络字段覆盖软件授权。
 */
frame_swap_status_t frame_swap_udp_frame_ready(frame_swap_t *fs,
                                               uintptr_t reported_base,
                                               int frame_ok);

#endif
