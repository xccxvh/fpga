#ifndef RENDERER_FPGA_H
#define RENDERER_FPGA_H

#include <stdint.h>

#include "renderer.h"
#include "bitblt_api.h"      /* B 冻结的驱动接口，权威定义在 B 的 driver 目录 */
#include "gpu_validate.h"    /* gpu_limits_t / gpu_params_t，硬件约束校验 */

/*
 * FPGA（BitBlt 加速器）后端 —— 统一层与冻结驱动之间的适配层。
 *
 * 三层职责：
 *   render_*（上层游戏） → 本文件（翻译 + 校验 + 映射） → bitblt_*（B 的驱动）
 *
 * 统一层送进来的操作已经裁剪好、保证落在画布内，本后端负责：
 *   1. 检查格式闸门与内存布局是否就绪
 *   2. 把画布坐标翻译成硬件要的字节地址与字节 stride
 *   3. 过一遍硬件约束校验（gpu_validate）
 *   4. 转换成 CLINT tick 超时后调用 bitblt_fill() / bitblt_copy()
 *   5. 把 bitblt_result_t 映射回统一层的 render_status_t
 *
 * 硬件不做任何边界检查，所以第 2 步的地址算术必须精确；
 * 裁剪已经在统一层完成，这里不再重复。
 */


/* 默认超时（毫秒）。1920x1080 整帧 8,294,400 B，
   按接口文档实测约 353 MiB/s 估算约 22 ms，留约 4.5 倍余量。 */
#define RENDER_FPGA_TIMEOUT_MS 100u


/*
 * 设置 DDR 可访问窗口与保留区。
 *
 * 由平台代码填写。板端通常直接用 render_limits_from_layout() 的结果；
 * 传 0 清除。未设置时后端返回 RENDER_ERR_NOT_READY。
 */
void render_fpga_set_limits(const gpu_limits_t *lim);


/*
 * 从 B 的权威布局头 framebuffer_layout.h 生成校验器需要的 limits。
 *
 * 只取 DDR 物理窗口与系统保留区两组宏，让库代码不必重复硬编码任何地址。
 *
 * 刻意【不引用】FB_WIDTH / FB_HEIGHT / FB_STRIDE：那是显示参数，
 * 通用 Renderer 不绑定任何分辨率。
 */
gpu_limits_t render_limits_from_layout(void);


/*
 * 把统一层的一次操作翻译成硬件参数。导出是为了可单测。
 *
 * is_copy 非 0 表示拷贝，否则是纯色填充。
 *
 * 注意 dst_stride_bytes 来自【画布】的 stride_px，不是矩形宽度——
 * 硬件那边 WIDTH 是矩形宽度而 DST_STRIDE 是 framebuffer 行距，
 * 把宽度当 stride 传过去会把后面每一行都写花。
 */
render_status_t render_fpga_build_request(const render_op_t *op,
                                          int is_copy,
                                          gpu_params_t *out);


/* 毫秒 -> 100 MHz CLINT tick。导出以便单测。 */
uint64_t render_timeout_ms_to_ticks(uint32_t timeout_ms);


/* bitblt_result_t -> render_status_t。导出以便单测。 */
render_status_t render_status_from_bitblt(bitblt_result_t r);


/*
 * 软件像素到硬件 COLOR 寄存器值的映射。
 *
 * pixel_t 与硬件格式都是 XRGB8888，所以当前是恒等映射。
 * 保留它是为了给将来的 RGB565 优化留一个唯一的抖动/打包点。
 */
uint32_t render_pixel_to_hw_color(pixel_t c);


extern const renderer_ops_t renderer_ops_fpga;

#endif
