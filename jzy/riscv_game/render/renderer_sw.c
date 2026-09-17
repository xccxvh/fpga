#include "renderer_sw.h"


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
)
{
    if (framebuffer == 0)
        return;

    if (width <= 0 || height <= 0)
        return;

    /*
     * 裁剪：
     * 防止矩形跑出屏幕以后写坏别的内存。
     */
    int x0 = x;
    int y0 = y;
    int x1 = x + width;
    int y1 = y + height;

    if (x0 < 0)
        x0 = 0;

    if (y0 < 0)
        y0 = 0;

    if (x1 > fb_width)
        x1 = fb_width;

    if (y1 > fb_height)
        y1 = fb_height;

    if (x0 >= x1 || y0 >= y1)
        return;

    for (int py = y0; py < y1; py++)
    {
        pixel_t *row = framebuffer + py * fb_stride;

        for (int px = x0; px < x1; px++)
        {
            row[px] = color;
        }
    }
}


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
)
{
    if (framebuffer == 0 || src == 0)
        return;

    for (int sy = 0; sy < src_height; sy++)
    {
        int dy = dst_y + sy;

        if (dy < 0 || dy >= fb_height)
            continue;

        for (int sx = 0; sx < src_width; sx++)
        {
            int dx = dst_x + sx;

            if (dx < 0 || dx >= fb_width)
                continue;

            framebuffer[
                dy * fb_stride + dx
            ] =
            src[
                sy * src_stride + sx
            ];
        }
    }
}
