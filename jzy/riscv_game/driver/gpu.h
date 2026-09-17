#ifndef GPU_H
#define GPU_H

#include <stdint.h>
#include "render_status.h"
#include "gpu_validate.h"

/*
 * BitBlt 加速器的 GPU 驱动接口。
 *
 * 本文件就是 B 组接口计划里要求 C 冻结的那份 API：
 * gpu_fill()、gpu_copy()、超时和错误码。
 *
 * 已确认的硬件格式事实（2026-09-17）：
 *   Pixel format        XRGB8888
 *   Pixel size          32 bit
 *   RISC-V control AXI  32 bit
 *   DDR AXI data width  128 bit
 *   Pixels per DDR beat 4
 *   Stride              width × 4 Byte
 *   Solid Fill color    1 个 32-bit XRGB8888 像素
 *   Block Copy          按 32-bit 像素搬运
 *
 * RTL 里存在显示侧格式字段（约定名 DISPLAY_FORMAT），但当前只实现了 XRGB8888，
 * 没有 RGB565 的打包/解包与显示适配，所以本驱动只按 32-bit 像素处理。
 *
 * 当前是【骨架】：所有下发路径都返回 RENDER_ERR_UNSUPPORTED，
 * 真实的寄存器读写一行都没有实现。寄存器访问只可能出现在 gpu.c 里
 * 由 BITBLT_ENABLE_HW_ACCESS 包住的分支中。
 *
 * 驱动刻意不 include 任何 BSP 头（vexriscv.h / plic.h 等），
 * 否则本工程脱离 BSP 就编不过。代价是两件事成为调用方责任，
 * 写在下面的"调用方约定"里。
 *
 * 调用方约定：
 *   1. 读加速器写过的 DDR 之前，调用方必须执行 data_cache_invalidate_address()
 *      （D-cache 非一致，这一点 B 的 demo 本来就是这么做的）。
 *   2. 枚举换帧、PLIC 中断注册属于显示与 BSP 范畴，不在本驱动内。
 */


/* 超时单位是毫秒。默认值按 640x480x4B ≈ 1.2MB 估算，
   即使只有 100MB/s 也只需要约 12ms。 */
#define GPU_TIMEOUT_MS_DEFAULT 100u


/*
 * 时基：返回自任意起点的【微秒】数。
 *
 * 板上用 BSP 的 CLINT 实现，本机测试注入假时钟。
 * 未注入时驱动返回 RENDER_ERR_NOT_READY —— 不猜时钟频率，
 * 猜错会让超时静默失效，比报错危险得多。
 */
typedef uint32_t (*gpu_timebase_fn)(void);

void gpu_set_timebase(gpu_timebase_fn now_us);
int  gpu_timebase_ready(void);


/*
 * 初始化并可选地校验接口版本。
 *
 * expected_version 传 0 表示跳过版本检查。这里不硬编码 0x00010003：
 * 版本号属于 B 的寄存器定义，应该由调用方从 bitblt_regs.h 或接口约定取得。
 */
render_status_t gpu_init(uint32_t expected_version);

/* 设备 VERSION 寄存器最近一次读到的值；未读到过则为 0 */
uint32_t gpu_version(void);

/* 最近一次读到的 STATUS 原始值，供串口打印排查 */
uint32_t gpu_last_status(void);


/*
 * 下发一条命令并等待完成。
 *
 * 同步阻塞：硬件同时只执行一条命令且没有命令 FIFO，因此这里没有异步接口。
 * 上一条还没完成时返回 RENDER_ERR_BUSY。
 *
 * 参数合法性由 gpu_validate_* 负责，本函数不做二次校验也不做裁剪——
 * 调用方（renderer_fpga.c）必须先用校验器确认过。
 */
render_status_t gpu_fill(const gpu_params_t *p, uint32_t timeout_ms);
render_status_t gpu_copy(const gpu_params_t *p, uint32_t timeout_ms);

#endif
