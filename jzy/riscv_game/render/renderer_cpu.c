#include "renderer.h"

/*
 * CPU 后端：把统一层已裁剪好的操作直接交给冻结的 sw_* 实现。
 *
 * 这一层刻意保持"薄"——不做任何裁剪、不碰参数，只做类型搬运。
 * 越薄越好：后端越简单，renderer_sw.c 已被验证过的行为就越能原样保留，
 * 三路等价测试（冻结层 / 统一层+CPU / 统一层+假后端）才有意义。
 */


static render_status_t cpu_fill(const render_op_t *op)
{
    /*
     * 传进去的矩形已经裁剪过，sw_fill_rect 内部还会再裁一次。
     * 同样边界下裁剪是幂等的，所以第二次是空操作，行为不受影响。
     */
    sw_fill_rect(op->dst->pixels,
                 op->dst->width,
                 op->dst->height,
                 op->dst->stride_px,
                 op->dst_rect.x,
                 op->dst_rect.y,
                 op->dst_rect.w,
                 op->dst_rect.h,
                 op->color);

    return RENDER_OK;
}


static render_status_t cpu_copy(const render_op_t *op)
{
    /*
     * sw_blit 的签名是"整张源图放到目标位置"，没有源内偏移参数。
     * 一旦目标被裁剪，源也必须跟着偏移，所以这里用子视图把源里对应的
     * 那一块单独表达出来，再把它画到裁剪后的目标位置。
     *
     * 没有发生裁剪时 src_rect 就是整张源图，视图与 op->src 等价，是纯直通。
     */
    render_surface_t src_view = render_surface_view(op->src,
                                                    op->src_rect.x,
                                                    op->src_rect.y,
                                                    op->src_rect.w,
                                                    op->src_rect.h);

    if (src_view.pixels == 0)
        return RENDER_ERR_INVALID_ARG;

    sw_blit(op->dst->pixels,
            op->dst->width,
            op->dst->height,
            op->dst->stride_px,

            src_view.pixels,
            src_view.width,
            src_view.height,
            src_view.stride_px,

            op->dst_rect.x,
            op->dst_rect.y);

    return RENDER_OK;
}


const renderer_ops_t renderer_ops_cpu =
{
    "cpu",
    cpu_fill,
    cpu_copy
};
