#ifndef RENDERER_SW_EXT_H
#define RENDERER_SW_EXT_H

#include <stdint.h>

#include "renderer_sw.h"     /* pixel_t */

/*
 * CPU 参考实现【扩展】：Color Key 与 Alpha 混合。
 *
 * 为什么单独一个文件而不是塞进 renderer_sw.c：
 * renderer_sw.c 是已冻结、已板测的 M1 基线（fill_rect / blit），
 * 它的行为不许动。Color Key 和 Alpha 是 M4/M5 的新能力，
 * 硬件侧 B 组 RTL 对它们的支持状态也不一样，所以分开：
 *
 *   Color Key   B 组 RTL 有 OPERATION=2（BITBLT_OP_COLOR_KEY，V0.4 已板测
 *               20x5 像素），但 B 的 bitblt_api.h 还没有对应的 C 入口。
 *               硬件通路等 B 扩 API；本文件的实现先作为【比对基准】。
 *
 *   Alpha       B 组 RTL 尚未实现。本文件是唯一实现，将来用来核对硬件。
 *
 * 两个函数都按【当前像素格式】工作：
 *   RGB565   颜色键按 16-bit 精确比较；混合在 8-bit 通道上算完再量化回去
 *   XRGB8888 颜色键按 32-bit 精确比较；混合在 8-bit 通道上算完再量化回去
 *
 * 语义与冻结的 sw_* 保持一致：越界一律裁剪，不写出画布之外。
 */


/*
 * 带颜色键的块拷贝：源里等于 key 的像素视为透明，目标保持原值。
 *
 * 与 sw_blit 的差别只有这一条：命中的像素被跳过而不是写过去。
 * 参数含义、裁剪行为都与 sw_blit 完全一致。
 *
 * key 的比较是【精确相等】，不做容差、不做通道级近似——
 * 统一规范要求“Color Key 按 16-bit RGB565 精确比较”。
 */
void sw_color_key_blit(
    pixel_t *framebuffer,
    int fb_width,
    int fb_height,
    int fb_stride,

    const pixel_t *src,
    int src_width,
    int src_height,
    int src_stride,

    int dst_x,
    int dst_y,

    pixel_t key
);


/*
 * 半透明纯色填充：把 color 以 alpha 混合到目标上。
 *
 * alpha 取值 0..255，0 = 完全透明（目标不变），255 = 完全不透明（等于 fill）。
 * 这两个端点必须精确成立，不能被舍入误差动摇 —— 测试会钉住它们。
 *
 * 内部在 8-bit 通道上做乘加，再量化回当前像素格式。
 * 用 (src*a + dst*(255-a) + 127) / 255 的整数公式：+127 是四舍五入，
 * 保证 a=0 和 a=255 时结果精确等于 dst / src。
 */
void sw_alpha_blend_rect(
    pixel_t *framebuffer,
    int fb_width,
    int fb_height,
    int fb_stride,

    int x,
    int y,
    int width,
    int height,

    pixel_t color,
    uint8_t alpha
);

#endif
