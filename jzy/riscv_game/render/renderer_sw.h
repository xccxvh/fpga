#ifndef RENDERER_SW_H
#define RENDERER_SW_H

#include <stdint.h>

/*
 * 像素格式开关 —— 全工程唯一的格式开关点。
 *
 *   1（默认）= RGB565 / 1280x720@60
 *              团队 2026-09-18 选定的统一目标，
 *              见 07_docs/interfaces/rgb565_720p_migration.md
 *   0        = XRGB8888 / 1920x1080@60
 *              2026-09-17 的历史基线，已板测通过。
 *              保留为回退路径：B 组 RGB565 RTL/位流落地前，
 *              只有这一条路能上板跑通。
 *
 * 用 -DRENDER_PIXEL_FORMAT_RGB565=0 切回历史基线，冻结的 M1 基线
 * （tests/test_renderer.c）在回退路径下必须原样通过。
 *
 * 注意：这个开关只决定【软件】像素宽度。硬件那边是 XRGB8888 还是
 * RGB565 由位流决定，属于运行期事实，用 render_fpga_set_hw_format()
 * 声明，不能靠这个宏假设（见 render/renderer_fpga.h）。
 */
#ifndef RENDER_PIXEL_FORMAT_RGB565
#define RENDER_PIXEL_FORMAT_RGB565 1
#endif

#if RENDER_PIXEL_FORMAT_RGB565

/*
 * 一个像素 16 bit，RGB565 小端：
 *   bit[15:11] R5, bit[10:5] G6, bit[4:0] B5
 *   - 2 Byte / 像素，2 个像素 / 32-bit word
 *   - DDR AXI 数据宽度 128 bit，每 beat 8 个像素
 *   - stride = width × 2 Byte（1280 时 = 2560 Byte）
 *   - Solid Fill 的 color 低 16 位是 1 个 RGB565 像素
 *   - 透明色按 16-bit RGB565 精确比较
 */
typedef uint16_t pixel_t;

#else

/*
 * 一个像素 32 bit，XRGB8888 小端（历史基线，可回退）：
 *   - DDR AXI 数据宽度 128 bit，每 beat 4 个像素
 *   - stride = width × 4 Byte（1920 时 = 7680 Byte）
 *   - Solid Fill 的 color 就是 1 个 32-bit XRGB8888 像素
 *   - Block Copy 按 32-bit 像素搬运
 */
typedef uint32_t pixel_t;

#endif

/*
 * 本文件刻意【不】include 任何 driver/ 下的头文件：
 * tests/Makefile 编译冻结基线时不带任何 -I 参数，本头文件必须自包含。
 * 几何参数（宽高、stride、帧大小）在 driver/framebuffer_format.h 里，
 * 它 include 本文件以共用上面这一个开关。
 */


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
