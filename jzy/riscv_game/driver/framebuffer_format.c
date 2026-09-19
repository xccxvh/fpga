#include "framebuffer_format.h"


/*
 * RGB565 位域（统一规范：R[15:11] G[10:5] B[4:0]）
 *
 * 打包用高位截断：8-bit 通道丢掉最低几位。
 * 解包用位复制  ：把高位填回低位，保证满量程映射到满量程。
 *
 * 两侧刻意不对称——这是 24-bit 到 16-bit 转换的通行做法：
 * 截断保证 round-trip 的"高 5/6 位"语义可预测，位复制保证
 * 纯白(255,255,255)解出来还是纯白，不会变成 (248,252,248) 的灰白。
 */

#define RGB565_R_SHIFT 11u
#define RGB565_G_SHIFT 5u
#define RGB565_B_SHIFT 0u

#define RGB565_R_MASK  0x1Fu
#define RGB565_G_MASK  0x3Fu
#define RGB565_B_MASK  0x1Fu


uint16_t fmt_rgb565_pack(uint8_t r, uint8_t g, uint8_t b)
{
    uint16_t r5 = (uint16_t)((uint16_t)r >> 3);   /* 8 -> 5 bit */
    uint16_t g6 = (uint16_t)((uint16_t)g >> 2);   /* 8 -> 6 bit */
    uint16_t b5 = (uint16_t)((uint16_t)b >> 3);   /* 8 -> 5 bit */

    return (uint16_t)((uint16_t)(r5 << RGB565_R_SHIFT) |
                      (uint16_t)(g6 << RGB565_G_SHIFT) |
                      (uint16_t)(b5 << RGB565_B_SHIFT));
}


uint16_t fmt_xrgb8888_to_rgb565(uint32_t xrgb8888)
{
    uint8_t r = (uint8_t)((xrgb8888 >> 16) & 0xFFu);
    uint8_t g = (uint8_t)((xrgb8888 >> 8) & 0xFFu);
    uint8_t b = (uint8_t)(xrgb8888 & 0xFFu);

    return fmt_rgb565_pack(r, g, b);
}


void fmt_rgb565_unpack(uint16_t rgb565, uint8_t *r, uint8_t *g, uint8_t *b)
{
    uint8_t r5 = (uint8_t)((rgb565 >> RGB565_R_SHIFT) & RGB565_R_MASK);
    uint8_t g6 = (uint8_t)((rgb565 >> RGB565_G_SHIFT) & RGB565_G_MASK);
    uint8_t b5 = (uint8_t)((rgb565 >> RGB565_B_SHIFT) & RGB565_B_MASK);

    if (r != 0)
    {
        /* R8 = {R5, R5[4:2]}：满量程 31 -> 255 */
        *r = (uint8_t)((uint8_t)(r5 << 3) | (uint8_t)(r5 >> 2));
    }

    if (g != 0)
    {
        /* G8 = {G6, G6[5:4]}：满量程 63 -> 255 */
        *g = (uint8_t)((uint8_t)(g6 << 2) | (uint8_t)(g6 >> 4));
    }

    if (b != 0)
    {
        *b = (uint8_t)((uint8_t)(b5 << 3) | (uint8_t)(b5 >> 2));
    }
}


uint32_t fmt_rgb565_to_xrgb8888(uint16_t rgb565)
{
    uint8_t r = 0;
    uint8_t g = 0;
    uint8_t b = 0;

    fmt_rgb565_unpack(rgb565, &r, &g, &b);

    return ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
}


uint32_t fmt_color_to_hw(pixel_t c)
{
#if RENDER_PIXEL_FORMAT_RGB565
    /*
     * 统一规范要求 COLOR[31:16] 写 0，避免新旧驱动误配。
     * pixel_t 是 16 bit，提升到 32 bit 后高位天然是 0，
     * 这里再显式掩一次，防的是"将来 pixel_t 变宽却忘了改这里"。
     */
    return (uint32_t)c & FMT_COLOR_MASK;
#else
    (void)FMT_COLOR_MASK;
    return (uint32_t)c;
#endif
}


pixel_t fmt_color_from_hw(uint32_t hw)
{
#if RENDER_PIXEL_FORMAT_RGB565
    return (pixel_t)(hw & FMT_COLOR_MASK);
#else
    return (pixel_t)hw;
#endif
}
