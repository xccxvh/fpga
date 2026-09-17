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
 * 约束来源：07_docs/interfaces/bitblt_interface_v0.1.md 第 2、4 节。
 */

/* OPERATION 编码，与接口约定第 2 节一致。
 * gpu.c 在启用硬件分支时用编译期断言核对它们与 BITBLT_OP_* 相等。 */
#define GPU_OP_FILL 0u
#define GPU_OP_COPY 1u

/* 像素格式已确认：XRGB8888，1 pixel = 32 bit = 4 Byte。
 * DDR AXI 数据宽度 128 bit，每 beat 4 个像素。stride = width × 4 Byte。 */
#define GPU_HW_PIXEL_BYTES 4u

/* ------------------------------------------------------------------ *
 * 以下两条是当前 BitBlt V0.1 的【硬件约束】，不是最终游戏规则。
 *
 * 16 Byte 对齐、WIDTH % 4 == 0 都还没有冻结：
 * 后续需要和 B 组单独确认是否要在硬件侧放宽（放宽可以解除对矩形起点
 * 必须是 4 的倍数这一限制，从而不再约束字体字宽、精灵宽度和 UI 面板位置）。
 *
 * 在 B 组确认之前，校验器继续按 V0.1 的严格口径拒绝，不要在这里放松。
 * ------------------------------------------------------------------ */

/* 地址与 stride 必须 16 字节对齐（V0.1 §4） */
#define GPU_ALIGN_BYTES 16u

/* RTL 要求 width[1:0] == 0，即宽度必须是 4 像素的倍数（V0.1 §4） */
#define GPU_WIDTH_GRANULARITY 4u


/*
 * DDR 可访问窗口与保留区。
 *
 * ddr_size == 0 表示平台尚未填写这套布局，校验一律返回 RENDER_ERR_NOT_READY。
 * reserved_lo == reserved_hi 表示没有保留区。
 * 保留区用来防止加速器踩到 CPU 正在运行的代码/数据（链接器 ram 窗口）。
 */
typedef struct
{
    uint32_t ddr_base;
    uint32_t ddr_size;
    uint32_t reserved_lo;
    uint32_t reserved_hi;
} gpu_limits_t;


/*
 * 一条 BitBlt 命令的完整参数。
 *
 * 地址和 stride 单位都是【字节】。width 是像素数（硬件 32-bit 像素）。
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
