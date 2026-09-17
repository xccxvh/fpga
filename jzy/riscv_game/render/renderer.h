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
 * 像素格式（2026-09-17 确认）：XRGB8888，1 pixel = 32 bit = 4 Byte。
 *
 * 硬件侧确认事实：
 *   Pixel format        XRGB8888
 *   Pixel size          32 bit
 *   RISC-V control AXI  32 bit
 *   DDR AXI data width  128 bit
 *   Pixels per DDR beat 4
 *   Stride              width × 4 Byte
 *   Solid Fill color    1 个 32-bit XRGB8888 像素
 *   Block Copy          按 32-bit 像素搬运
 *
 * RTL 里存在显示侧格式字段（约定名 DISPLAY_FORMAT），但当前 RTL 只实现了
 * XRGB8888，没有 RGB565 的打包/解包与显示适配。因此 M1/M2 阶段【不要】试图把
 * 两个 RGB565 像素塞进一个 32-bit word 去绕过格式限制——那需要 RTL 侧的打包/
 * 解包支持，现在并不存在。
 *
 *
 * ── 迁移状态：已完成 ──
 *
 * CPU 参考实现（renderer_sw.*）已从 16-bit 迁移到 32-bit，与硬件数据面一致，
 * 所以下面 RENDER_FPGA_USABLE 为 1，FPGA 后端不再被格式闸门拦住。
 * 迁移后全部冻结基线与统一层测试、交叉编译、HW 分支编译均已重跑通过。
 *
 * 格式闸门本身保留：它防的是"pixel_t 又被改成与硬件不一致的宽度却没人发现"。
 * 任何时候都不允许用强制转换、截断或 reinterpret cast 绕过它。
 *
 *
 * ── RGB565：后续性能优化方向，现在不实现 ──
 *
 * 若以后 DDR 带宽、Framebuffer 占用或 Sprite 吞吐成为瓶颈，再考虑：
 *   16-bit RGB565
 *   2 pixels / 32-bit word
 *   8 pixels / 128-bit DDR beat
 *   stride = width × 2 Byte
 *   显示侧 unpacker 按 DISPLAY_FORMAT 解包
 * 本文件的像素格式抽象与显示侧格式扩展位就是为这条路径预留的接口。
 */


/*
 * 必须与 pixel_t 同步。改了 pixel_t 却忘了改这里会直接编译失败，
 * 而不是等到运行期才发现像素被按错误的宽度搬运。
 */
#define RENDER_PIXEL_BYTES 4u

typedef char render_pixel_bytes_must_match[
    (RENDER_PIXEL_BYTES == sizeof(pixel_t)) ? 1 : -1];

/*
 * 软件像素宽度与已确认的硬件格式一致时，FPGA 后端才可用。
 * 不一致时下发一律返回 RENDER_ERR_FORMAT_MISMATCH。
 */
#if   (RENDER_PIXEL_BYTES == 4u)
#define RENDER_FPGA_USABLE 1
#elif (RENDER_PIXEL_BYTES == 2u)
#define RENDER_FPGA_USABLE 0
#else
#error "未知像素宽度：与已确认的 XRGB8888（32-bit）不符"
#endif


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
