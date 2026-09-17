#ifndef RENDERER_SW_H
#define RENDERER_SW_H

#include <stdint.h>

/*
 * M1阶段暂定：
 * 一个像素用16bit表示。
 *
 * 注意：
 * 这里只是CPU参考实现的数据类型，
 * 最终是否采用RGB565，要等三人接口约定正式确定。
 */
typedef uint16_t pixel_t;


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
