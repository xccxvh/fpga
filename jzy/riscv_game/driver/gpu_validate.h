#ifndef GPU_VALIDATE_H
#define GPU_VALIDATE_H

#include <stdint.h>
#include "render_status.h"

/*
 * BitBlt 硬件约束的纯函数校验。
 *
 * 本文件不 include bitblt_regs.h，不访问任何寄存器，也不引用任何真实地址——
 * 内存布局全部通过 gpu_limits_t 参数传入。这样校验器可以在本机完整单测，
 * 而"不能自行填写尚未确定的地址"这条约束在代码结构上就成立。
 *
 * 约束来源：07_docs/interfaces/bitblt_interface_v0.2.md §4（现行，V0.4）
 *
 * 像素宽度【不是】编译期常量：B 组当前位流是 XRGB8888（4 Byte/像素、
 * 宽度 4 像素倍数），统一目标 RGB565 是 （2 Byte/像素、宽度 8 像素倍数）。
 * 两者都由 gpu_limits_t 在运行期传入，校验器对两种格式同等成立。
 */

/* OPERATION 编码，与接口约定第 2 节一致。
 * gpu.c 在启用硬件分支时用编译期断言核对它们与 BITBLT_OP_* 相等。 */
#define GPU_OP_FILL 0u
#define GPU_OP_COPY 1u

/* ------------------------------------------------------------------ *
 * 对齐与宽度粒度是 BitBlt 的【硬件约束】，不是游戏规则。
 *
 * 16 Byte 对齐是两种像素格式共同的约定。
 * 宽度粒度随像素宽度变化：16 Byte / 每像素字节数。
 *   4 Byte/像素（XRGB8888）-> 4 像素
 *   2 Byte/像素（RGB565）  -> 8 像素
 * 因此不在这里写死，由 gpu_limits_t.width_granularity 传入。
 *
 * 目前没有出现任何"放宽"的接口记录；B 组若要放宽需改接口约定。
 * 在 B 组确认之前，校验器继续按严格口径拒绝，不要在这里放松。
 * ------------------------------------------------------------------ */

/* 地址与 stride 必须 16 字节对齐（接口约定 §4） */
#define GPU_ALIGN_BYTES 16u


/*
 * DDR 可访问窗口、保留区与硬件像素格式。
 *
 * ddr_size == 0 表示平台尚未填写这套布局，校验一律返回 RENDER_ERR_NOT_READY。
 * reserved_lo == reserved_hi 表示没有保留区。
 * 保留区用来防止加速器踩到 CPU 正在运行的代码/数据（链接器 ram 窗口）。
 *
 * bytes_per_pixel == 0 或 width_granularity == 0 表示当前位流的像素格式
 * 尚未声明，校验返回 RENDER_ERR_NOT_READY —— 不猜默认值。
 */
typedef struct
{
    uint32_t ddr_base;
    uint32_t ddr_size;
    uint32_t reserved_lo;
    uint32_t reserved_hi;

    /* 硬件位流实现的像素格式：2 = RGB565，4 = XRGB8888，0 = 未声明 */
    unsigned bytes_per_pixel;

    /* 矩形宽度必须是的倍数：4（XRGB8888）或 8（RGB565），0 = 未声明 */
    unsigned width_granularity;
} gpu_limits_t;


/*
 * 一条 BitBlt 命令的完整参数。
 *
 * 地址和 stride 单位都是【字节】。width 是像素数。
 * FILL 忽略 src_addr_bytes / src_stride_bytes，填 0 即可。
 */
typedef struct
{
    uint32_t dst_addr_bytes;
    uint32_t dst_stride_bytes;
    uint32_t src_addr_bytes;
    uint32_t src_stride_bytes;
    uint32_t width;
    uint32_t height;
    uint32_t color;
    uint32_t operation;
} gpu_params_t;


/*
 * 校验一条 FILL / COPY 命令能否安全下发。
 *
 * 返回 RENDER_OK 表示参数满足全部硬件约束。否则返回具体错误码，
 * 错误码的判定顺序见 .c 里的检查表。
 *
 * FILL 和 COPY 分成两个入口，而不是靠 operation 字段分派，
 * 这样"填充被拿源侧规则校验"这类错误在签名层面就不可能出现。
 */
render_status_t gpu_validate_fill(const gpu_limits_t *lim, const gpu_params_t *p);
render_status_t gpu_validate_copy(const gpu_limits_t *lim, const gpu_params_t *p);

#endif
