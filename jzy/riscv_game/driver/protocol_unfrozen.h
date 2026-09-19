#ifndef PROTOCOL_UNFROZEN_H
#define PROTOCOL_UNFROZEN_H

#include <stdint.h>

/*
 * 尚未冻结的协议项。
 *
 * ┌─ 本文件现在只剩一项 ──────────────────────────────────────────────┐
 * │ 文件名保留 protocol_unfrozen，但里面【已经只剩 UDP 完成通知】。     │
 * │                                                                   │
 * │ 原先放在这里的另外两项已经正式冻结，搬去了 protocol_frozen.h：      │
 * │   DISPLAY_FORMAT 的 RGB565 枚举值  -> PROTO_DISPLAY_FORMAT_RGB565  │
 * │   BitBlt / Display 的新版 VERSION  -> PROTO_BITBLT_VERSION_RGB565  │
 * │                                      PROTO_DISPLAY_VERSION_RGB565  │
 * │                                                                   │
 * │ 之所以保留旧文件名，是为了不做一次纯改名的全树重构；              │
 * │ 但这个文件里【只应存在还没冻结的东西】—— 新增任何已冻结的常量      │
 * │ 都应该放进 protocol_frozen.h，不要塞回这里。                       │
 * └───────────────────────────────────────────────────────────────────┘
 *
 * 还没冻结的：UDP 帧完成通知的寄存器地址、中断号、ACK 方式。
 * 迁移文档写"尚未分配"，要 A/C 在接入 SoC 时确定；A 组草案提过的 APB
 * 那一套已被迁移文档明确否掉，那份草案的地址同样不能拿来用。
 *
 * 需要一个尚未冻结的值时，用下面的 protocol_caps_t 表达"还没确认"，
 * 让调用方走降级分支；【不要】在这里写死任何数字。
 */

/* 出现在本文件里的每个值都还没冻结。grep 这个宏即可找到全部未冻结点。 */
#define UNFROZEN_PROTOCOL 1


/* ------------------------------------------------------------------ *
 * 能力查询：三态，默认 UNKNOWN
 *
 * 刻意不用 int/bool：bool 只有两态，"还没问过"会被迫伪装成"不支持"或
 * "支持"，两种伪装都会在联合调试时给出错误结论。
 * ------------------------------------------------------------------ */

typedef enum
{
    /* 还没确认 —— 默认值。所有依赖它的功能必须走降级分支 */
    PROTOCOL_CAP_UNKNOWN = 0,

    /* 三方已确认，对应数值可用 */
    PROTOCOL_CAP_YES,

    /* 三方已确认不提供该能力 */
    PROTOCOL_CAP_NO
} protocol_cap_t;


/*
 * 平台在初始化时填写。
 *
 * 全 0（= UNKNOWN）是安全默认：任何"能不能用某个未冻结接口"的判断
 * 都会得到"不能"，而不是"假装能"。
 */
typedef struct
{
    /* UDP 帧完成通知接口是否已分配 */
    protocol_cap_t udp_completion;

    /* 仅当 udp_completion == PROTOCOL_CAP_YES 时有效。
       在此之前保持 0：0 不是"某个地址"，而是"没有地址"。
       换帧状态机会拒绝把 0 当成有效寄存器地址来读写。 */
    uint32_t udp_completion_reg_addr;
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
