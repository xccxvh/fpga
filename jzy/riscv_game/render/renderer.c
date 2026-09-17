#include <stddef.h>

#include "renderer.h"


static const renderer_ops_t *g_ops = 0;


/* ------------------------------------------------------------------ */
/* 后端选择                                                            */
/* ------------------------------------------------------------------ */

void render_init(void)
{
    (void)render_select(RENDER_BACKEND_CPU);
}


render_status_t render_select(render_backend_t which)
{
    switch (which)
    {
    case RENDER_BACKEND_CPU:
        g_ops = &renderer_ops_cpu;
        return RENDER_OK;

    case RENDER_BACKEND_FPGA:
        /*
         * 这里允许选中，即使当前像素格式下它画不了任何东西。
         * 理由是选 FPGA 之后仍然要能查名字、等待格式定案；
         * 真正下发时的失败由后端返回 FORMAT_MISMATCH，那样错误码才带得上原因。
         */
        g_ops = &renderer_ops_fpga;
        return RENDER_OK;
    }

    return RENDER_ERR_INVALID_ARG;
}


render_status_t render_select_ops(const renderer_ops_t *ops)
{
    g_ops = ops;
    return RENDER_OK;
}


const char *render_backend_name(void)
{
    return g_ops ? g_ops->name : "(none)";
}


/* ------------------------------------------------------------------ */
/* 工具函数                                                            */
/* ------------------------------------------------------------------ */

int render_surface_valid(const render_surface_t *s)
{
    if (s == 0 || s->pixels == 0)
        return 0;

    if (s->width <= 0 || s->height <= 0)
        return 0;

    /* stride 比宽度小意味着行与行重叠，读会串行、写会踩到别人 */
    if (s->stride_px < s->width)
        return 0;

    return 1;
}


int render_clip_rect(int fb_width, int fb_height, render_rect_t req, render_rect_t *out)
{
    int64_t x0, y0, x1, y1;

    if (out == 0 || fb_width <= 0 || fb_height <= 0)
        return 0;

    if (req.w <= 0 || req.h <= 0)
        return 0;

    /*
     * 全程 64 位。
     *
     * 冻结的 sw_fill_rect 内部是 int x1 = x + width，x 很大时会有符号溢出 UB。
     * 本层先裁剪，冻结函数就永远看不到接近 INT_MAX 的操作数；
     * 这里自己也不能溢出，否则裁剪本身就不可信。
     */
    x0 = req.x;
    y0 = req.y;
    x1 = (int64_t)req.x + (int64_t)req.w;
    y1 = (int64_t)req.y + (int64_t)req.h;

    if (x0 < 0)
        x0 = 0;

    if (y0 < 0)
        y0 = 0;

    if (x1 > fb_width)
        x1 = fb_width;

    if (y1 > fb_height)
        y1 = fb_height;

    if (x0 >= x1 || y0 >= y1)
        return 0;

    out->x = (int)x0;
    out->y = (int)y0;
    out->w = (int)(x1 - x0);
    out->h = (int)(y1 - y0);

    return 1;
}


render_surface_t render_surface_view(const render_surface_t *parent,
                                     int x, int y, int w, int h)
{
    render_surface_t view;

    view.pixels = 0;
    view.width = 0;
    view.height = 0;
    view.stride_px = 0;
    view.phys_base = 0;

    if (!render_surface_valid(parent))
        return view;

    if (w <= 0 || h <= 0 || x < 0 || y < 0)
        return view;

    if ((int64_t)x + w > parent->width)
        return view;

    if ((int64_t)y + h > parent->height)
        return view;

    view.pixels = parent->pixels
                + (size_t)y * (size_t)parent->stride_px
                + (size_t)x;
    view.width = w;
    view.height = h;
    view.stride_px = parent->stride_px;

    /* phys_base 为 0 表示"与 pixels 同址"，视图继承这个语义 */
    if (parent->phys_base != 0)
    {
        view.phys_base = parent->phys_base
                       + (uintptr_t)y * (uintptr_t)parent->stride_px * RENDER_PIXEL_BYTES
                       + (uintptr_t)x * RENDER_PIXEL_BYTES;
    }

    return view;
}


/* ------------------------------------------------------------------ */
/* 绘制                                                                */
/* ------------------------------------------------------------------ */

render_status_t render_fill_rect(const render_surface_t *dst,
                                 render_rect_t rect,
                                 pixel_t color)
{
    render_op_t op;
    render_rect_t clipped;

    if (g_ops == 0)
        return RENDER_ERR_NO_BACKEND;

    if (!render_surface_valid(dst))
        return RENDER_ERR_INVALID_ARG;

    /*
     * 裁没了返回 OK：与冻结层"空矩形合法、什么都不做"保持一致。
     * 若将来游戏代码需要区分"画了"和"什么都没画"，加出参而不是加错误码。
     */
    if (!render_clip_rect(dst->width, dst->height, rect, &clipped))
        return RENDER_OK;

    op.dst = dst;
    op.src = 0;
    op.dst_rect = clipped;
    op.src_rect.x = 0;
    op.src_rect.y = 0;
    op.src_rect.w = clipped.w;
    op.src_rect.h = clipped.h;
    op.color = color;

    return g_ops->fill(&op);
}


render_status_t render_blit(const render_surface_t *dst,
                            const render_surface_t *src,
                            int dst_x,
                            int dst_y)
{
    render_op_t op;
    render_rect_t req;
    render_rect_t clipped;

    if (g_ops == 0)
        return RENDER_ERR_NO_BACKEND;

    if (!render_surface_valid(dst) || !render_surface_valid(src))
        return RENDER_ERR_INVALID_ARG;

    req.x = dst_x;
    req.y = dst_y;
    req.w = src->width;
    req.h = src->height;

    if (!render_clip_rect(dst->width, dst->height, req, &clipped))
        return RENDER_OK;

    op.dst = dst;
    op.src = src;
    op.dst_rect = clipped;

    /*
     * 反推源矩形：裁剪后的目标位置相对原目标位置偏移了多少，
     * 源就要跟着偏移多少。
     *
     * 用 64 位相减：dst_x 为 INT_MIN 时，0 - INT_MIN 会溢出 int。
     * 结果必然落在 [0, src->width] 内，转回 int 是安全的。
     */
    op.src_rect.x = (int)((int64_t)clipped.x - (int64_t)dst_x);
    op.src_rect.y = (int)((int64_t)clipped.y - (int64_t)dst_y);
    op.src_rect.w = clipped.w;
    op.src_rect.h = clipped.h;
    op.color = 0;

    return g_ops->copy(&op);
}
