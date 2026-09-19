#ifndef PROTOCOL_UNFROZEN_H
#define PROTOCOL_UNFROZEN_H

#include <stdint.h>

/*
 * 统一协议之前留下的能力探测兼容层。
 *
 * UDP Frame RX 地址和 V2.0 语义已经由
 * 07_docs/interfaces/unified_fpga_interface_spec_v1.1.md 冻结；本文件名和
 * UNFROZEN_PROTOCOL 宏仅为避免在正式 UDP 驱动落地前破坏现有 host 测试，
 * 【不再表示协议仍待确认】。
 *
 * 当前默认 UNKNOWN 的含义是“本软件尚未接入符合 V2.0 的硬件/驱动”，不是
 * “团队没有决定地址”。A 创建 udp_frame_rx_regs.h 且 C 完成正式驱动后，
 * 必须删除本兼容层；禁止向这里加入任何新协议常量。
 */

/* 过渡期绊线；正式 UDP V2.0 驱动接入后连同本文件删除。 */
#define UNFROZEN_PROTOCOL 1


/* ------------------------------------------------------------------ *
 * 能力查询：三态，默认 UNKNOWN
 *
 * 刻意不用 int/bool：bool 只有两态，"还没问过"会被迫伪装成"不支持"或
 * "支持"，两种伪装都会在联合调试时给出错误结论。
 * ------------------------------------------------------------------ */

typedef enum
{
    /* 尚未接入/探测 —— 默认值。所有依赖它的功能必须走降级分支 */
    PROTOCOL_CAP_UNKNOWN = 0,

    /* 三方已确认，对应数值可用 */
    PROTOCOL_CAP_YES,

    /* 三方已确认不提供该能力 */
    PROTOCOL_CAP_NO
} protocol_cap_t;


/*
 * 平台在初始化时填写。
 *
 * 全 0（= UNKNOWN）是安全默认：任何“当前是否接入该硬件”的判断
 * 都会得到"不能"，而不是"假装能"。
 */
typedef struct
{
    /* UDP Frame RX V2.0 实现是否已接入并通过版本探测 */
    protocol_cap_t udp_completion;

    /* 仅当 udp_completion == PROTOCOL_CAP_YES 时有效。
       在此之前保持 0：0 不是"某个地址"，而是"没有地址"。
       换帧状态机会拒绝把 0 当成有效寄存器地址来读写。 */
    uint32_t udp_completion_reg_addr;
    /* 旧结构保留字段；统一 V1.1 的 UDP MVP 固定 polling，必须保持 0。 */
    uint32_t udp_completion_irq_id;
} protocol_caps_t;


/* 设置为安全默认（全 UNKNOWN，地址 0） */
void protocol_caps_reset(protocol_caps_t *caps);

/* 当前能力表。未调用过 protocol_caps_set() 时返回全 UNKNOWN 表。 */
const protocol_caps_t *protocol_caps_get(void);

/* 平台填写能力表。传 0 等同 reset。 */
void protocol_caps_set(const protocol_caps_t *caps);


/*
 * UDP 帧完成通知是否可用。
 *
 * 返回 1 时 protocol_caps_get()->udp_completion_reg_addr 才是一个可以
 * 读的寄存器地址。返回 0 时调用方必须走降级路径（例如只由 BitBlt
 * 完成事件驱动换帧），不能去读 0 地址。
 */
int protocol_udp_completion_available(void);

#endif
