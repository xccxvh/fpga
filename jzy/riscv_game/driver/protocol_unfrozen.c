#include <string.h>

#include "protocol_unfrozen.h"


/*
 * 旧命名的 UDP 实现能力配置点。
 *
 * UDP 协议已经由统一规范 V1.1 冻结；这里没有默认地址，是因为正式 V2.0
 * 驱动和硬件尚未接入。默认就是 UNKNOWN / 0，后续必须由 A 的权威头文件
 * 和正式驱动取代本兼容层。
 *
 * DISPLAY_FORMAT 与 VERSION 已经冻结，不在这个文件里 ——
 * 见 protocol_frozen.h。
 */


static protocol_caps_t g_caps;


void protocol_caps_reset(protocol_caps_t *caps)
{
    if (caps == 0)
        return;

    memset(caps, 0, sizeof(*caps));
    /* memset 出来的 0 恰好就是 PROTOCOL_CAP_UNKNOWN，但显式写一遍，
       免得将来有人改了枚举顺序却不知道这里依赖它。 */
    caps->udp_completion          = PROTOCOL_CAP_UNKNOWN;
    caps->udp_completion_reg_addr = 0u;
    caps->udp_completion_irq_id   = 0u;
}


void protocol_caps_set(const protocol_caps_t *caps)
{
    if (caps == 0)
    {
        protocol_caps_reset(&g_caps);
        return;
    }

    g_caps = *caps;
}


const protocol_caps_t *protocol_caps_get(void)
{
    return &g_caps;
}


int protocol_udp_completion_available(void)
{
    if (g_caps.udp_completion != PROTOCOL_CAP_YES)
        return 0;

    /*
     * 声称支持却给不出地址，属于配置错误。这里按"不可用"处理而不是
     * 断言崩溃：换帧是运行期路径，把故障降级成"这一帧不走 UDP 通路"
     * 比让整机挂掉合理。
     */
    if (g_caps.udp_completion_reg_addr == 0u)
        return 0;

    return 1;
}
