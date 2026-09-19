#include "gpu_validate.h"


/*
 * 一个矩形区域实际覆盖的字节区间，返回【独占结束地址】。
 *
 * 末行起点是 addr + (height-1)*stride，末行占 width * bytes_per_pixel 字节。
 * 全程 64 位运算：32 位回绕会把越界算成合法，必须让它在 64 位下暴露出来。
 *
 * bytes_per_pixel 由调用方保证非 0（check_common 已挡过）。
 * 调用前 height 必须已确认 > 0。
 */
static uint64_t region_end(uint32_t addr, uint32_t stride,
                           uint32_t width, uint32_t height,
                           unsigned bytes_per_pixel)
{
    return (uint64_t)addr
         + (uint64_t)(height - 1u) * (uint64_t)stride
         + (uint64_t)width * (uint64_t)bytes_per_pixel;
}


/*
 * 区间是否落在 DDR 窗口内、且不与保留区相交。
 *
 * 这里只做区间合法性判断，不关心它是源还是目标。
 */
static render_status_t check_region(const gpu_limits_t *lim, uint64_t lo, uint64_t hi)
{
    uint64_t win_lo = (uint64_t)lim->ddr_base;
    uint64_t win_hi = (uint64_t)lim->ddr_base + (uint64_t)lim->ddr_size;

    /* 越过 32 位地址空间顶端：地址算术已经回绕，直接判非法 */
    if (hi > 0x100000000ull)
        return RENDER_ERR_RANGE;

    if (lo < win_lo || hi > win_hi)
        return RENDER_ERR_RANGE;

    /* 保留区判交：lo == hi 或逆序一律视为没有保留区 */
    if (lim->reserved_lo < lim->reserved_hi)
    {
        uint64_t r_lo = (uint64_t)lim->reserved_lo;
        uint64_t r_hi = (uint64_t)lim->reserved_hi;

        if (lo < r_hi && r_lo < hi)
            return RENDER_ERR_RANGE;
    }

    return RENDER_OK;
}


/*
 * FILL 与 COPY 共用的检查，按此顺序判定错误码优先级：
 *   空指针 -> 布局未填 -> 像素格式未声明 -> operation -> width -> height
 *   -> 目标对齐 -> 目标 stride
 *
 * "布局未填"和"像素格式未声明"都用 NOT_READY：两者都是"平台还没告诉
 * 校验器硬件长什么样"，不是调用方的参数错。
 */
static render_status_t check_common(const gpu_limits_t *lim,
                                    const gpu_params_t *p,
                                    uint32_t expected_operation)
{
    if (lim == 0 || p == 0)
        return RENDER_ERR_INVALID_ARG;

    if (lim->ddr_size == 0u)
        return RENDER_ERR_NOT_READY;

    if (lim->bytes_per_pixel == 0u || lim->width_granularity == 0u)
        return RENDER_ERR_NOT_READY;

    if (p->operation != expected_operation)
        return RENDER_ERR_BAD_OPERATION;

    if (p->width == 0u || (p->width % lim->width_granularity) != 0u)
        return RENDER_ERR_BAD_WIDTH;

    if (p->height == 0u)
        return RENDER_ERR_BAD_HEIGHT;

    if ((p->dst_addr_bytes % GPU_ALIGN_BYTES) != 0u)
        return RENDER_ERR_BAD_ALIGN;

    if ((p->dst_stride_bytes % GPU_ALIGN_BYTES) != 0u)
        return RENDER_ERR_BAD_ALIGN;

    if ((uint64_t)p->dst_stride_bytes < (uint64_t)p->width * lim->bytes_per_pixel)
        return RENDER_ERR_BAD_STRIDE;

    return RENDER_OK;
}


render_status_t gpu_validate_fill(const gpu_limits_t *lim, const gpu_params_t *p)
{
    render_status_t st = check_common(lim, p, GPU_OP_FILL);

    if (st != RENDER_OK)
        return st;

    /* FILL 忽略源侧参数，只用目标区间 */
    return check_region(lim,
                        p->dst_addr_bytes,
                        region_end(p->dst_addr_bytes, p->dst_stride_bytes,
                                   p->width, p->height,
                                   lim->bytes_per_pixel));
}


render_status_t gpu_validate_copy(const gpu_limits_t *lim, const gpu_params_t *p)
{
    uint64_t dst_lo, dst_hi, src_lo, src_hi;
    render_status_t st = check_common(lim, p, GPU_OP_COPY);

    if (st != RENDER_OK)
        return st;

    /* COPY 才有源侧的对齐与 stride 约束 */
    if ((p->src_addr_bytes % GPU_ALIGN_BYTES) != 0u)
        return RENDER_ERR_BAD_ALIGN;

    if ((p->src_stride_bytes % GPU_ALIGN_BYTES) != 0u)
        return RENDER_ERR_BAD_ALIGN;

    if ((uint64_t)p->src_stride_bytes < (uint64_t)p->width * lim->bytes_per_pixel)
        return RENDER_ERR_BAD_STRIDE;

    dst_lo = p->dst_addr_bytes;
    dst_hi = region_end(p->dst_addr_bytes, p->dst_stride_bytes,
                        p->width, p->height, lim->bytes_per_pixel);
    src_lo = p->src_addr_bytes;
    src_hi = region_end(p->src_addr_bytes, p->src_stride_bytes,
                        p->width, p->height, lim->bytes_per_pixel);

    st = check_region(lim, dst_lo, dst_hi);
    if (st != RENDER_OK)
        return st;

    st = check_region(lim, src_lo, src_hi);
    if (st != RENDER_OK)
        return st;

    /*
     * 保守的包围盒相交测试。
     *
     * 硬件不保证 memmove 语义，所以重叠必须拒绝。用包围盒而不是逐行区间，
     * 意味着可能误拒某些实际不重叠的交错布局——这是有意的取舍：
     * 误报只是让某个合法请求退回 CPU 画，漏报则是内存损坏。
     * 将来要收紧成逐行区间比较，不需要改接口。
     */
    if (src_lo < dst_hi && dst_lo < src_hi)
        return RENDER_ERR_OVERLAP;

    return RENDER_OK;
}
