#ifndef RENDERER_SW_H
#define RENDERER_SW_H

#include <stdint.h>

/*
 * M1：一个像素用 32 bit 表示，格式为 XRGB8888。
 *
 * 该格式已于 2026-09-17 确认，与 BitBlt 硬件数据面一致：
 *   - DDR AXI 数据宽度 128 bit，每 beat 4 个像素
 *   - stride = width × 4 Byte
 *   - Solid Fill 的 color 就是 1 个 32-bit XRGB8888 像素
 *   - Block Copy 按 32-bit 像素搬运
 *
 * 统一渲染层据此认为 FPGA 后端可用（见 render/renderer.h 的 RENDER_PIXEL_BYTES）。
 * 改这里必须同步改 RENDER_PIXEL_BYTES，否则统一层编译不过——
 * renderer.h 里有一行静态断言专门盯这件事。
 */
typedef uint32_t pixel_t;


/*
 * 在 framebuffer 中填充一个矩形。
 *
 * framebuffer : 目标画布
 * fb_width     : 画布有效宽度
 * fb_height    : 画布有效高度
 * fb_stride    : 每行包含多少个 pixel_t
 *
 * x, y         : 矩形左上角
 * width,height : 矩形尺寸
 * color        : 填充颜色
 */
void sw_fill_rect(
    pixel_t *framebuffer,
    int fb_width,
    int fb_height,
    int fb_stride,
    int x,
    int y,
    int width,
    int height,
    pixel_t color
);


/*
 * 将一张图片复制到 framebuffer。
 *
 * src          : 源图片
 * src_width    : 源图片宽度
 * src_height   : 源图片高度
 * src_stride   : 源图片每行像素数
 *
 * dst_x,dst_y  : 在 framebuffer 中放置的位置
 */
void sw_blit(
    pixel_t *framebuffer,
    int fb_width,
    int fb_height,
    int fb_stride,

    const pixel_t *src,
    int src_width,
    int src_height,
    int src_stride,

    int dst_x,
    int dst_y
);

#endif
