#ifndef RENDERER_FPGA_H
#define RENDERER_FPGA_H

#include <stdint.h>
#include "renderer.h"
#include "gpu.h"

/*
 * FPGA（BitBlt 加速器）后端。
 *
 * 统一层送进来的操作已经裁剪好、保证落在画布内，本后端的职责是：
 *   1. 检查格式闸门（16-bit 软件像素 vs 32-bit 硬件数据面）
 *   2. 把画布坐标翻译成硬件要的字节地址与字节 stride
 *   3. 过一遍硬件约束校验
 *   4. 交给 gpu_fill() / gpu_copy()
 *
 * 硬件不做任何边界检查，所以第 2 步的地址算术必须精确；
 * 裁剪已经在统一层完成，这里不再重复。
 */


/*
 * 设置 DDR 可访问窗口与保留区。
 *
 * 由平台代码在 A 冻结内存布局后填写。传 0 清除。
 * 未设置时后端返回 RENDER_ERR_NOT_READY —— 本工程不内置任何默认地址。
 */
void render_fpga_set_limits(const gpu_limits_t *lim);


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


/*
 * 软件像素到硬件 COLOR 寄存器值的映射。
 *
 * pixel_t 与硬件格式都是 XRGB8888，所以当前是恒等映射。
 * 保留它是为了给将来的 RGB565 优化留一个唯一的抖动/打包点。
 */
uint32_t render_pixel_to_hw_color(pixel_t c);


extern const renderer_ops_t renderer_ops_fpga;

#endif
