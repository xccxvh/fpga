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


/* 默认超时（毫秒）。RGB565/720p 整帧 1,843,200 B，
   按接口文档 XRGB8888/1080p 实测约 353 MiB/s 估算约 5 ms；
   回退到 XRGB8888/1080p 时整帧 8,294,400 B 约 22 ms。
   取 100 ms 对两种格式都留了充足余量。 */
#define RENDER_FPGA_TIMEOUT_MS 100u


/*
 * 硬件位流所实现的像素格式 —— 运行期事实，不是编译期常量。
 *
 * 默认值是当前联合工程约定（RGB565），所以正常路径不需要显式声明。
 * 板子上烧的是别的格式（例如 B 组现存的 XRGB8888 V0.4 位流）时，
 * 由平台层显式声明成那个格式 —— 声明错了会被闸门以 FORMAT_MISMATCH
 * 拦住，而不是画出一屏乱码。
 *
 * ⚠ RGB565 版 RTL/位流尚未完成验证：默认值表达的是"协议约定"，
 * 不是"板上已经跑通"。
 */
typedef enum
{
    /*
     * 显式声明"拒绝下发"，后端返回 RENDER_ERR_NOT_READY。
     *
     * 这【不再是默认值】：协议已冻结为 RGB565，默认格式就是 RGB565。
     * 保留这一项只是为了还能主动把下发通道关掉（实验、故障隔离），
     * 而不是因为协议没定。
     */
    RENDER_HW_FORMAT_UNKNOWN = 0,

    /* 32-bit XRGB8888，4 Byte/像素，宽度需 4 像素倍数 */
    RENDER_HW_FORMAT_XRGB8888,

    /* 16-bit RGB565，2 Byte/像素，宽度需 8 像素倍数。
       2026-09-18 选定的统一目标；联合 RTL/位流落地前不要声明它。 */
    RENDER_HW_FORMAT_RGB565
} render_hw_format_t;


/*
 * 声明当前位流的像素格式。
 *
 * 默认已是当前联合工程约定的 RGB565，所以【不需要】为了正常下发而调用它。
 * 只有两种情况要调：
 *   1. 板上烧的是别的格式（例如 XRGB8888 旧位流）—— 显式声明成那个
 *   2. 想把下发通道关掉 —— 传 UNKNOWN
 */
void render_fpga_set_hw_format(render_hw_format_t fmt);

/* 当前声明的硬件格式 */
render_hw_format_t render_fpga_hw_format(void);

/* 格式对应的每像素字节数 / 宽度像素粒度；UNKNOWN 返回 0 */
unsigned render_hw_format_pixel_bytes(render_hw_format_t fmt);
unsigned render_hw_format_width_granularity(render_hw_format_t fmt);


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
 * 地址（DDR 物理窗口与系统保留区）全部来自 B 的头文件，本工程不重复硬编码。
 * 像素宽度与宽度粒度来自当前声明的硬件格式 —— 校验器因此对两种格式都成立。
 *
 * 刻意【不引用】FB_WIDTH / FB_HEIGHT / FB_STRIDE：B 的那几个宏还是
 * XRGB8888/1080p 的历史值，且通用 Renderer 不该绑定任何分辨率。
 * 现行几何在 driver/framebuffer_format.h。
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
 * RGB565：取低 16 位、高位清零。XRGB8888（回退）：恒等映射。
 * 保留它是为了给将来的 RGB565 优化留一个唯一的抖动/打包点。
 */
uint32_t render_pixel_to_hw_color(pixel_t c);


extern const renderer_ops_t renderer_ops_fpga;

#endif
