#ifndef DISPLAY_PLATFORM_H
#define DISPLAY_PLATFORM_H

#include <stdint.h>

/*
 * display_api.c 的平台钩子。
 *
 * 与 bitblt_platform.h 同一个套路：B 的 display_api.h 是冻结的对外接口，
 * 本文件放它没有、但实现必须依赖的平台侧注入点。
 * 刻意分开：那张头文件由 B 维护，不要往里加东西。
 */

/*
 * 显示控制器使用哪个总线段，由调用方在初始化前声明。
 *
 * 现行统一路径是 SYSTEM_AXI_A（统一规范已冻结）：显示控制器的
 * 基地址由 B 的 display_regs.h 提供，本工程不复制、不另写一份。
 * 与 BitBlt 共享 PLIC 源 30。A 组早期草案里的 APB 0xF8100000 那一套
 * 不属于联合控制路径，本工程不实现、也不提供切换开关。
 *
 * 保留这个函数是为了让"当前走哪条路"在板上日志里可查，
 * 而不是散落在代码注释里。
 */
void display_set_bus_path_axi(void);

/* 当前是否声明走 SYSTEM_AXI_A。未声明时 display_api 拒绝访问寄存器。 */
int display_bus_path_is_axi(void);


/*
 * 100 MHz CLINT tick 计数源。单位与 bitblt_platform.h 相同。
 *
 * display_wait_swap(timeout_ticks) 用的就是这个单位。
 * 未注入时任何等待直接返回 DISPLAY_ETIMEOUT —— 不猜时钟。
 */
typedef uint64_t (*display_tick_fn)(void);

void display_set_tick_source(display_tick_fn now_ticks);
int  display_tick_source_ready(void);


/* 最近一次读取到的显示 STATUS 原始值，供串口排查 */
uint32_t display_last_status(void);


/*
 * 读取显示控制器的 VERSION 寄存器。
 *
 * 硬件构建：真的读 DISPLAY_VERSION（需要先声明总线路径）。
 * 本机构建：返回模型值，默认 0，由 display_test_set_version() 设置。
 *
 * 读不到（未声明总线路径）返回 0 —— 0 永远不是一个合法版本号，
 * 调用方按"不匹配"处理即可，不需要额外区分"读不到"和"版本是 0"。
 */
uint32_t display_get_version(void);


/*
 * 最近一次下发请求的记录 —— 【仅本机测试用】。
 *
 * 只在未开启 DISPLAY_ENABLE_HW_ACCESS 的构建里记录。
 */
typedef struct
{
    uint32_t front_addr;
    uint32_t next_addr;
    uint32_t width;
    uint32_t height;
    uint32_t stride;
    uint32_t format;
    int      queued;    /* 有过一次 display_queue_swap() */
    int      inited;    /* 有过一次 display_init() */
} display_call_record_t;

/* 返回最近一次记录的调用；什么调用都没发生过时返回 0。
   inited / queued 分别标明记录里哪些字段是有效的。 */
const display_call_record_t *display_last_call(void);

/*
 * 清空调用记录（仅本机构建）。
 *
 * 用来回答"这一次尝试到底写没写寄存器"：记录本身是粘滞的，
 * 不先清掉就分不清是本次写的还是上一次留下的。
 */
void display_test_clear_call(void);


#ifndef DISPLAY_ENABLE_HW_ACCESS

/*
 * 本机测试用的显示控制器行为模型 —— 仅在没有硬件访问的构建里存在。
 *
 * 有硬件时这些函数不存在，所以测试代码如果要无条件调用它们，
 * 必须自己用 #ifdef 包起来。板端应用不要调用。
 */

/* wait_swap 的返回值模型：非 0 表示下一次 wait_swap 返回 DISPLAY_OK */
void display_test_set_swap_ok(int ok);

/* 直接摆布显示控制器的"当前前台地址"模型 */
void display_test_set_front(uint32_t front);

/* 摆布本机构建的 VERSION 模型值 */
void display_test_set_version(uint32_t version);

/*
 * wait_swap 成功时是否真的把前台搬过去。
 *
 * 默认 1（正常硬件）。置 0 用来模拟一种真实存在的坏情况：
 * SWAP_DONE 已经置位，但 FRONT_ADDR 没有跟着变 ——
 * 换帧状态机必须靠回读 FRONT_ADDR 才能发现，不能只信状态位。
 */
void display_test_set_swap_updates_front(int updates);

#endif /* !DISPLAY_ENABLE_HW_ACCESS */

#endif
