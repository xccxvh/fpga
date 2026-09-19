#ifndef RENDERER_H
#define RENDERER_H

#include <stdint.h>
#include "renderer_sw.h"     /* 冻结的 pixel_t */
#include "render_status.h"

/*
 * CPU / FPGA 统一渲染层。
 *
 * 上层游戏代码只调用 render_* 这一套接口，底层在 CPU 参考实现与
 * BitBlt 加速器之间通过 render_select() 切换。
 *
 * 语义承诺（两种后端完全一致）：
 *   - 越界安全：允许坐标为负、允许矩形超出画布，自动裁剪；
 *     完全不可见的矩形是合法输入，返回 RENDER_OK 且什么都不画。
 *   - 裁剪只在本层做一次，后端收到的参数保证已裁剪、已落在画布内。
 *   - 后端不得再裁剪，也不得写出 dst_rect 之外（硬件不会替你做）。
 */


/* ------------------------------------------------------------------ */
/* 像素格式：唯一的开关点                                              */
/* ------------------------------------------------------------------ */

/*
 * ── 像素格式：两个独立的事实，不要混为一谈 ──
 *
 * 【软件像素宽度】由 pixel_t 决定，编译期已知。
 *   切换开关在 render/renderer_sw.h 顶部的 RENDER_PIXEL_FORMAT_RGB565：
 *     1（默认）= RGB565 / 1280x720@60  —— 团队 2026-09-18 选定的统一目标
 *     0        = XRGB8888 / 1920x1080@60 —— 历史基线，可回退
 *   几何参数（宽高、stride、帧大小）在 driver/framebuffer_format.h。
 *
 * 【硬件像素宽度】由 FPGA 上烧的位流决定，是运行期事实。
 *   当前 B 组位流（V0.4，`0x00010004`）只有 XRGB8888；RGB565 版 RTL
 *   尚未完成、未板测。所以这里【不能】用编译期常量断言"硬件是 32-bit"
 *   ——那种写法在 B 组 RGB565 位流落地的那一刻就变成了谎话。
 *
 *   改用运行期能力声明：平台层用 render_fpga_set_hw_format() 告诉后端
 *   "我加载的位流是哪个格式"，两边不一致时下发返回 FORMAT_MISMATCH。
 *   未声明时一律不下发（NOT_READY），不猜、不默认。
 *
 * 任何时候都不允许用强制转换、截断或 reinterpret cast 绕过这个检查。
 */


/*
 * 软件像素字节数。由 pixel_t 直接派生 —— 单一真相源。
 *
 * 以前这里是个字面量 4，配一条静态断言盯着 pixel_t；现在反过来，
 * 宏从类型算出来，两者不可能再不一致。
 */
#define RENDER_PIXEL_BYTES ((unsigned)sizeof(pixel_t))

typedef char render_pixel_bytes_supported[
    (RENDER_PIXEL_BYTES == 2u || RENDER_PIXEL_BYTES == 4u) ? 1 : -1];


/* ------------------------------------------------------------------ */
/* 类型                                                                */
/* ------------------------------------------------------------------ */

/*
 * 一块画布。
 *
 * stride_px 的单位是【像素】，与冻结的 sw_* 接口一致，不是字节。
 * 命名刻意带上 _px：驱动层用的是字节（*_stride_bytes），
 * 全代码库不出现裸 stride，避免两套单位互相污染。
 *
 * 硬件那边 WIDTH 是矩形宽度而 DST_STRIDE 是 framebuffer 行距，
 * 传错会把后面每一行都写花，所以这个区分值得用命名钉死。
 */
typedef struct
{
    pixel_t  *pixels;
    int       width;
    int       height;
    int       stride_px;
    uintptr_t phys_base;   /* 0 表示与 pixels 相同；A 冻结地址后由平台填写 */
} render_surface_t;


typedef struct
{
    int x, y, w, h;
} render_rect_t;


typedef enum
{
    RENDER_BACKEND_CPU = 0,
    RENDER_BACKEND_FPGA
} render_backend_t;


/*
 * 一次绘制操作。
 *
 * dst_rect 已由统一层裁剪：保证 w > 0、h > 0，且完全落在 dst 之内。
 * src_rect 与 dst_rect 等宽高，且完全落在 src 之内。
 * 后端的职责只有"照着画"，边界正确性由本层保证。
 */
typedef struct
{
    const render_surface_t *dst;
    const render_surface_t *src;    /* 0 表示纯色填充 */
    render_rect_t           dst_rect;
    render_rect_t           src_rect;
    pixel_t                 color;
} render_op_t;


typedef struct
{
    const char     *name;
    render_status_t (*fill)(const render_op_t *op);
    render_status_t (*copy)(const render_op_t *op);
} renderer_ops_t;


/* 后端注册符号，实现分别在 renderer_cpu.c 与 renderer_fpga.c */
extern const renderer_ops_t renderer_ops_cpu;
extern const renderer_ops_t renderer_ops_fpga;


/* ------------------------------------------------------------------ */
/* 公开 API：游戏代码只用这些                                          */
/* ------------------------------------------------------------------ */

/* 选定默认后端（CPU）。没有调用过 select 就绘制会返回 NO_BACKEND，
   而不是悄悄用 CPU 跑——那会让人误以为加速器已经在工作。 */
void render_init(void);

/*
 * 切换后端。
 *
 * 选 FPGA 成功不代表能用：16-bit 阶段任何绘制都会返回
 * RENDER_ERR_FORMAT_MISMATCH。选择本身允许成功，是为了还能查询
 * render_backend_name() 做诊断。
 */
render_status_t render_select(render_backend_t which);

/* 注入自定义后端（测试用假后端）。传 0 表示取消选择。 */
render_status_t render_select_ops(const renderer_ops_t *ops);

const char *render_backend_name(void);

/* 在当前画布上填充一个矩形。矩形可越界，自动裁剪 */
render_status_t render_fill_rect(const render_surface_t *dst,
                                 render_rect_t rect,
                                 pixel_t color);

/* 把整张 src 画到 dst 的 (dst_x, dst_y)。可越界，自动裁剪。
   子矩形请先用 render_surface_view() 取视图。 */
render_status_t render_blit(const render_surface_t *dst,
                            const render_surface_t *src,
                            int dst_x,
                            int dst_y);


/* ------------------------------------------------------------------ */
/* 工具函数：导出是为了可单测                                          */
/* ------------------------------------------------------------------ */

/* 画布是否可用：非空指针、宽高 > 0、stride_px >= width（防止越界读写） */
int render_surface_valid(const render_surface_t *s);

/* 裁剪矩形到画布范围。返回 1 表示裁剪后仍可见，结果写入 out；
   返回 0 表示完全不可见，out 不被修改。 */
int render_clip_rect(int fb_width, int fb_height, render_rect_t req, render_rect_t *out);

/* 取父画布的一块子视图（雪碧图用）。子矩形越界时返回空画布。 */
render_surface_t render_surface_view(const render_surface_t *parent,
                                     int x, int y, int w, int h);

#endif
