#include "renderer_sw_ext.h"
#include "framebuffer_format.h"


/*
 * 一个像素拆成 8-bit RGB 通道。
 *
 * RGB565 走位复制解包（与显示侧扩展方式一致）；
 * XRGB8888 直接取位段。两种格式在这里被抹平，上面的混合代码就只有一份。
 */
static void pixel_to_rgb(pixel_t px, uint8_t *r, uint8_t *g, uint8_t *b)
{
#if RENDER_PIXEL_FORMAT_RGB565
    fmt_rgb565_unpack((uint16_t)px, r, g, b);
#else
    uint32_t v = (uint32_t)px;

    *r = (uint8_t)((v >> 16) & 0xFFu);
    *g = (uint8_t)((v >> 8) & 0xFFu);
    *b = (uint8_t)(v & 0xFFu);
#endif
}


/* 8-bit RGB 通道合成一个像素。与 pixel_to_rgb 互逆。 */
static pixel_t rgb_to_pixel(uint8_t r, uint8_t g, uint8_t b)
{
#if RENDER_PIXEL_FORMAT_RGB565
    return (pixel_t)fmt_rgb565_pack(r, g, b);
#else
    return (pixel_t)(((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b);
#endif
}


/* 单通道混合：(src*a + dst*(255-a) + 127) / 255 */
static uint8_t blend_channel(uint8_t src, uint8_t dst, uint8_t a)
{
    uint32_t inv = (uint32_t)(255u - (uint32_t)a);

    return (uint8_t)(((uint32_t)src * (uint32_t)a +
                      (uint32_t)dst * inv +
                      127u) / 255u);
}


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
)
{
    if (framebuffer == 0 || src == 0)
        return;

    if (src_width <= 0 || src_height <= 0)
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

            pixel_t sp = src[sy * src_stride + sx];

            /*
             * 精确相等比较，没有容差。
             * 用 pixel_t 而不是拆通道比：RGB565 下 key 值和源像素值
             * 都是 16 bit，逐位相等才是"同一个颜色"。
             */
            if (sp == key)
                continue;

            framebuffer[dy * fb_stride + dx] = sp;
        }
    }
}


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
)
{
    int x0, y0, x1, y1;
    uint8_t sr, sg, sb;

    if (framebuffer == 0)
        return;

    if (width <= 0 || height <= 0)
        return;

    /* 与冻结的 sw_fill_rect 相同的裁剪口径 */
    x0 = x;
    y0 = y;
    x1 = x + width;
    y1 = y + height;

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

    pixel_to_rgb(color, &sr, &sg, &sb);

    for (int py = y0; py < y1; py++)
    {
        pixel_t *row = framebuffer + py * fb_stride;

        for (int px = x0; px < x1; px++)
        {
            uint8_t dr, dg, db;

            if (alpha == 0u)
            {
                /* 端点：完全透明，目标一个字节都不动 */
                continue;
            }

            if (alpha == 255u)
            {
                /* 端点：完全不透明，直接写源色。
                   不经过混合公式，避免多一次 unpack/pack 往返。 */
                row[px] = color;
                continue;
            }

            pixel_to_rgb(row[px], &dr, &dg, &db);

            row[px] = rgb_to_pixel(blend_channel(sr, dr, alpha),
                                   blend_channel(sg, dg, alpha),
                                   blend_channel(sb, db, alpha));
        }
    }
}
