#ifndef GPU_H
#define GPU_H

#include <stdint.h>
#include "render_status.h"
#include "gpu_validate.h"

/*
 * BitBlt 加速器的 GPU 驱动接口 —— 【已废弃，仅作兼容层保留】。
 *
 * ┌──────────────────────────────────────────────────────────────────┐
 * │ 新代码请用 driver/bitblt_api.c 实现的冻结接口：                    │
 * │   bitblt_fill() / bitblt_copy() / bitblt_result_t                 │
 * │   uint64_t timeout_ticks（100 MHz CLINT tick）                    │
 * │ 权威头文件是 B 的 04_project/bitblt_accel/sw/driver/bitblt_api.h。 │
 * └──────────────────────────────────────────────────────────────────┘
 *
 * 本文件是 V0.1 时期"待 C 确认"那套命名的产物，V0.2/V0.3 冻结下来的接口是
 * bitblt_*，所以这里不再对外。保留它只为不打断既有引用与测试；
 * 所有下发路径都返回 RENDER_ERR_UNSUPPORTED，没有任何寄存器访问。
 *
 * 寄存器访问（含 fence 与 STATUS 轮询）在生产代码里只存在于
 * driver/bitblt_api.c，由 make check-hw-isolation 机械保证。
 * 板级验证代码（tests/test_bitblt_board.c）允许只读引用 bitblt_regs.h
 * 做硬件契约检查，那不是生产路径，也不在本检查范围内。
 *
 * 渲染层不再使用本文件：render/renderer_fpga.c 直接调 bitblt_*。
 *
 * 现有接口的语义（保留不变）：
 *   gpu_fill / gpu_copy   骨架，恒返回 RENDER_ERR_UNSUPPORTED
 *   gpu_init              骨架，恒返回 RENDER_ERR_UNSUPPORTED
 *   gpu_set_timebase      局部时基注入，与本文件外的代码无关
 *
 * 调用方约定（由真正的驱动 bitblt_api.c 承担）：
 *   当前 SoC 已启用 4 KiB D-cache；共享 DDR 范围必须按统一规范 V1.2
 *   通过 dma_sync_for_device()/dma_sync_for_cpu() 交接。当前生产驱动尚未
 *   完成该同步封装，不能把 fence rw,rw 当作 cache invalidate。
 *
 * 硬件格式事实（2026-09-18 更新）：
 *   统一目标            RGB565 / 1280x720@60，2 Byte/像素，8 像素/128-bit beat
 *   当前位流（V0.4）    XRGB8888 / 1920x1080@60，4 Byte/像素，4 像素/beat
 *   RISC-V control AXI  32 bit
 *   DDR AXI data width  128 bit
 *
 * 位流实际是哪个格式属于运行期事实，用 render_fpga_set_hw_format() 声明；
 * 本文件不假定其中任何一个。详见 render/renderer.h 顶部与
 * driver/framebuffer_format.h。
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
