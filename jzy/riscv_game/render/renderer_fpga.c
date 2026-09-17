#include <string.h>

#include "renderer_fpga.h"
#include "bitblt_platform.h"
#include "framebuffer_layout.h"


static gpu_limits_t g_limits;
static int          g_limits_set = 0;


void render_fpga_set_limits(const gpu_limits_t *lim)
{
    if (lim == 0)
    {
        memset(&g_limits, 0, sizeof(g_limits));
        g_limits_set = 0;
        return;
    }

    g_limits = *lim;
    g_limits_set = 1;
}


gpu_limits_t render_limits_from_layout(void)
{
    gpu_limits_t lim;

    /*
     * 只取内存布局有关的四组宏，地址全部来自 B 的权威头文件
     * framebuffer_layout.h，本工程不重复硬编码。
     *
     * 刻意不碰 FB_WIDTH / FB_HEIGHT / FB_STRIDE：那是显示分辨率相关参数，
     * 通用 Renderer 不该绑定 640x480 或 1920x1080 中的任何一个。
     */
    lim.ddr_base    = DDR_PHYSICAL_BASE;
    lim.ddr_size    = DDR_PHYSICAL_SIZE;
    lim.reserved_lo = SYSTEM_RESERVED_BASE;
    lim.reserved_hi = SYSTEM_RESERVED_BASE + SYSTEM_RESERVED_SIZE;

    return lim;
}


uint64_t render_timeout_ms_to_ticks(uint32_t timeout_ms)
{
    /*
     * CLINT 是 100 MHz，1 ms = 100000 tick。
     *
     * 先转 uint64_t 再乘：timeout_ms 超过约 42949 时，32 位乘法会回绕，
     * 把长超时算成一个很短的值，等待会提前超时失败。
     */
    return (uint64_t)timeout_ms * 100000ULL;
}


render_status_t render_status_from_bitblt(bitblt_result_t r)
{
    switch (r)
    {
    case BITBLT_OK:       return RENDER_OK;
    case BITBLT_EINVAL:   return RENDER_ERR_INVALID_ARG;
    case BITBLT_EBUSY:    return RENDER_ERR_BUSY;
    case BITBLT_ETIMEOUT: return RENDER_ERR_TIMEOUT;
    case BITBLT_EHW:      return RENDER_ERR_HW_ERROR;
    }

    /* 冻结枚举之外的值按硬件错误上报，不要静默当成成功 */
    return RENDER_ERR_HW_ERROR;
}


uint32_t render_pixel_to_hw_color(pixel_t c)
{
    /*
     * 恒等映射。
     *
     * pixel_t 已迁移为 uint32_t，格式就是硬件用的 XRGB8888，
     * 所以软件像素值可以直接当硬件 COLOR 寄存器值用。
     *
     * 保留这个函数是为了给将来的 RGB565 优化留一个唯一的转换点：
     * 若以后真做 16-bit RGB565，打包/解包逻辑只需要改这里
     * （见 renderer.h 顶部的 RGB565 段落）。
     */
    return (uint32_t)c;
}


/* 硬件要的是 DDR 物理地址；phys_base 为 0 表示画布就在指针指向的地方 */
static uintptr_t surface_base(const render_surface_t *s)
{
    return (s->phys_base != 0) ? s->phys_base : (uintptr_t)s->pixels;
}


render_status_t render_fpga_build_request(const render_op_t *op,
                                          int is_copy,
                                          gpu_params_t *out)
{
    uint32_t dst_pitch;

    if (op == 0 || op->dst == 0 || out == 0)
        return RENDER_ERR_INVALID_ARG;

    if (is_copy && op->src == 0)
        return RENDER_ERR_INVALID_ARG;

    /*
     * 行距来自画布的 stride_px，乘以软件像素字节数折算成字节。
     * 硬件 stride 一律以字节计，而统一层以像素计，换算只在这里发生一次。
     */
    dst_pitch = (uint32_t)op->dst->stride_px * RENDER_PIXEL_BYTES;

    memset(out, 0, sizeof(*out));

    out->dst_stride_bytes = dst_pitch;
    out->dst_addr_bytes = (uint32_t)(surface_base(op->dst)
                                     + (uintptr_t)op->dst_rect.y * (uintptr_t)dst_pitch
                                     + (uintptr_t)op->dst_rect.x * RENDER_PIXEL_BYTES);

    out->width = (uint32_t)op->dst_rect.w;
    out->height = (uint32_t)op->dst_rect.h;
    out->color = render_pixel_to_hw_color(op->color);
    out->operation = is_copy ? GPU_OP_COPY : GPU_OP_FILL;

    if (is_copy)
    {
        uint32_t src_pitch = (uint32_t)op->src->stride_px * RENDER_PIXEL_BYTES;

        out->src_stride_bytes = src_pitch;
        out->src_addr_bytes = (uint32_t)(surface_base(op->src)
                                         + (uintptr_t)op->src_rect.y * (uintptr_t)src_pitch
                                         + (uintptr_t)op->src_rect.x * RENDER_PIXEL_BYTES);
    }

    return RENDER_OK;
}


/*
 * 格式闸门与就绪检查。
 *
 * 用运行期判断而不是 #if，是为了让下面整条下发路径【始终参与编译】——
 * 否则格式定案那天，这段代码将是有生以来第一次被编译。
 */
static render_status_t fpga_gate(void)
{
    if (!RENDER_FPGA_USABLE)
        return RENDER_ERR_FORMAT_MISMATCH;

    if (!g_limits_set)
        return RENDER_ERR_NOT_READY;

    return RENDER_OK;
}


static render_status_t fpga_fill(const render_op_t *op)
{
    gpu_params_t req;
    render_status_t st = fpga_gate();

    if (st != RENDER_OK)
    {
        /*
         * FORMAT_MISMATCH：pixel_t 宽度与已确认的 XRGB8888 不一致（见 renderer.h）。
         * NOT_READY：内存布局还没设置，本工程不内置任何默认地址。
         */
        return st;
    }

    st = render_fpga_build_request(op, 0, &req);
    if (st != RENDER_OK)
        return st;

    st = gpu_validate_fill(&g_limits, &req);
    if (st != RENDER_OK)
        return st;

    return render_status_from_bitblt(
        bitblt_fill(req.dst_addr_bytes,
                    req.width,
                    req.height,
                    req.dst_stride_bytes,
                    req.color,
                    render_timeout_ms_to_ticks(RENDER_FPGA_TIMEOUT_MS)));
}


static render_status_t fpga_copy(const render_op_t *op)
{
    gpu_params_t req;
    render_status_t st = fpga_gate();

    if (st != RENDER_OK)
        return st;

    st = render_fpga_build_request(op, 1, &req);
    if (st != RENDER_OK)
        return st;

    st = gpu_validate_copy(&g_limits, &req);
    if (st != RENDER_OK)
        return st;

    return render_status_from_bitblt(
        bitblt_copy(req.src_addr_bytes,
                    req.dst_addr_bytes,
                    req.width,
                    req.height,
                    req.src_stride_bytes,
                    req.dst_stride_bytes,
                    render_timeout_ms_to_ticks(RENDER_FPGA_TIMEOUT_MS)));
}


const renderer_ops_t renderer_ops_fpga =
{
    "fpga",
    fpga_fill,
    fpga_copy
};
