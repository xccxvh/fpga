#include <string.h>

#include "renderer_fpga.h"
#include "bitblt_platform.h"
#include "framebuffer_format.h"
#include "framebuffer_layout.h"


static gpu_limits_t g_limits;
static int          g_limits_set = 0;

/*
 * 当前联合工程默认的硬件格式。
 *
 * 协议已冻结为 RGB565，所以默认就是 RGB565 —— "未知"不再挡在真实
 * 下发路径前面。平台仍然可以显式改（例如板上烧的是 XRGB8888 的
 * 旧位流时声明成 XRGB8888），但那是【主动声明一个例外】，
 * 不是必须完成的初始化步骤。
 *
 * 回退构建（软件是 XRGB8888）默认跟着软件格式走，否则两边必然不匹配。
 */
#if RENDER_PIXEL_FORMAT_RGB565
static render_hw_format_t g_hw_format = RENDER_HW_FORMAT_RGB565;
#else
static render_hw_format_t g_hw_format = RENDER_HW_FORMAT_XRGB8888;
#endif


void render_fpga_set_hw_format(render_hw_format_t fmt)
{
    g_hw_format = fmt;
}


render_hw_format_t render_fpga_hw_format(void)
{
    return g_hw_format;
}


unsigned render_hw_format_pixel_bytes(render_hw_format_t fmt)
{
    switch (fmt)
    {
    case RENDER_HW_FORMAT_XRGB8888: return 4u;
    case RENDER_HW_FORMAT_RGB565:   return 2u;
    case RENDER_HW_FORMAT_UNKNOWN:  break;
    }

    return 0u;
}


unsigned render_hw_format_width_granularity(render_hw_format_t fmt)
{
    switch (fmt)
    {
    case RENDER_HW_FORMAT_XRGB8888: return 4u;
    case RENDER_HW_FORMAT_RGB565:   return 8u;
    case RENDER_HW_FORMAT_UNKNOWN:  break;
    }

    return 0u;
}


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

    memset(&lim, 0, sizeof(lim));

    /*
     * 地址全部来自 B 的权威头文件 framebuffer_layout.h，本工程不重复硬编码。
     *
     * 刻意不碰 FB_WIDTH / FB_HEIGHT / FB_STRIDE：B 的那几个宏目前还是
     * XRGB8888/1080p 的历史值（B 尚未迁移），而通用 Renderer 也不该绑定
     * 任何分辨率。现行几何在 driver/framebuffer_format.h。
     */
    lim.ddr_base    = DDR_PHYSICAL_BASE;
    lim.ddr_size    = DDR_PHYSICAL_SIZE;
    lim.reserved_lo = SYSTEM_RESERVED_BASE;
    lim.reserved_hi = SYSTEM_RESERVED_BASE + SYSTEM_RESERVED_SIZE;

    /*
     * 像素宽度与宽度粒度来自【当前声明的硬件格式】，不是软件格式。
     * 校验器要回答的是"这条命令硬件能不能执行"，所以必须按硬件算。
     * 格式被显式清成 UNKNOWN 时留 0，check_common 会以 NOT_READY 拒绝。
     */
    lim.bytes_per_pixel  = render_hw_format_pixel_bytes(g_hw_format);
    lim.width_granularity = render_hw_format_width_granularity(g_hw_format);

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
     * 软件像素 -> 硬件 COLOR 寄存器值。全工程唯一的转换点。
     *
     * RGB565（默认）：取低 16 位，高位写 0 —— 统一规范要求 COLOR[31:16]
     * 写 0，避免新旧驱动误配。
     * XRGB8888（回退）：恒等映射。
     *
     * 两个分支都在 driver/framebuffer_format.c 里，本函数只做转发，
     * 免得打包规则出现第二份实现。
     */
    return fmt_color_to_hw(c);
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
 * 两个独立的失败原因，顺序不能颠倒：
 *   1. 布局没填 / 格式被显式清成 UNKNOWN -> NOT_READY（配置问题）
 *   2. 格式和软件像素宽度不符             -> FORMAT_MISMATCH（知道，但不兼容）
 *
 * 注意 UNKNOWN 现在【不是默认值】了：协议冻结为 RGB565 之后，默认格式
 * 就是 RGB565，正常路径不会因为它被拦住。UNKNOWN 只剩下一个用途 ——
 * 平台主动声明"我拒绝下发"，用来做实验或故障隔离。
 */
static render_status_t fpga_gate(void)
{
    unsigned hw_bytes;

    if (!g_limits_set || g_limits.ddr_size == 0u)
        return RENDER_ERR_NOT_READY;

    /* 声明的位流格式是权威事实，问它而不是问布局里的副本 */
    hw_bytes = render_hw_format_pixel_bytes(g_hw_format);

    if (hw_bytes == 0u)
        return RENDER_ERR_NOT_READY;

    if (hw_bytes != RENDER_PIXEL_BYTES)
        return RENDER_ERR_FORMAT_MISMATCH;

    /*
     * 布局里的像素参数必须与声明的位流格式一致。
     *
     * 不一致说明平台没走 render_limits_from_layout()，或者中途改了格式声明
     * 却没重建布局。两种情况下校验器都会按错误的每像素字节数算 stride 与
     * 区间末尾 —— 算错的后果是写到画布外面去，所以宁可拒绝下发。
     */
    if (g_limits.bytes_per_pixel != hw_bytes)
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
         * NOT_READY：内存布局没设置，或下发通道被显式关掉。
         * FORMAT_MISMATCH：软件像素宽度与当前位流格式不符（见 renderer.h）。
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
