#ifndef BITBLT_PLATFORM_H
#define BITBLT_PLATFORM_H

#include <stdint.h>

/*
 * bitblt_api.c 的平台钩子。
 *
 * B 的 bitblt_api.h 是冻结的对外接口，本文件放的是它没有、但实现必须依赖的
 * 平台侧注入点。刻意与 bitblt_api.h 分开：那张头文件由 B 维护，不要往里加东西。
 */


/*
 * CLINT tick 计数源，单位是 100 MHz tick（1 tick = 10 ns）。
 *
 * bitblt_fill()/bitblt_copy() 的 timeout_ticks 就是这个单位，所以驱动需要一个
 * 能读到当前 tick 的入口。板端由应用用 BSP 的 CLINT 实现，本机测试注入假时钟。
 *
 * 用 uint64_t 而不是 uint32_t：100 MHz 下 32 位 tick 约 43 秒就回绕，
 * 超时判断会被回绕干扰。
 *
 * 未注入时，任何带超时的等待都会直接返回 BITBLT_ETIMEOUT —— 不猜时钟。
 */
typedef uint64_t (*bitblt_tick_fn)(void);

void bitblt_set_tick_source(bitblt_tick_fn now_ticks);

/* 返回 1 表示已注入 tick 源 */
int bitblt_tick_source_ready(void);


/* 最近一次读取到的 BitBlt STATUS 原始值，供串口排查 */
uint32_t bitblt_last_status(void);


/*
 * 最近一次下发请求的记录 —— 【仅本机测试用】。
 *
 * 只在未开启 BITBLT_ENABLE_HW_ACCESS 的构建里有记录：那种构建不会真的下发，
 * 记录一份参数可以让 host 测试验证适配层（renderer_fpga.c）确实把
 * 地址、stride、矩形和【转换后的 tick 超时】原样传给了驱动。
 *
 * 板端构建不记录，避免给每次下发增加无谓开销。
 */
typedef struct
{
    uint32_t dst_addr_bytes;
    uint32_t dst_stride_bytes;
    uint32_t src_addr_bytes;
    uint32_t src_stride_bytes;
    uint32_t width;
    uint32_t height;
    uint32_t color;
    int      is_copy;          /* 0 = FILL，非 0 = COPY */
    uint64_t timeout_ticks;
} bitblt_call_record_t;

/* 未开启硬件访问时返回最近一次记录；开启时恒返回 0 */
const bitblt_call_record_t *bitblt_last_call(void);

#endif
