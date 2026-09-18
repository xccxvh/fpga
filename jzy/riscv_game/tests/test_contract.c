/*
 * B/C 编译期接口契约。
 *
 * 这里只引用 04_project/bitblt_accel/sw/driver 中的权威头文件，
 * 不复制任何定义。如果 B 修改了寄存器、API 类型或显示布局，
 * 这个翻译单元会在 contract 回归的最前面给出精确的失配位置。
 */

#include "bitblt_regs.h"
#include "bitblt_api.h"
#include "framebuffer_layout.h"
#include "../render/renderer.h"

#define CONTRACT_ASSERT(name, expression) \
    typedef char contract_##name[(expression) ? 1 : -1]

/* 寄存器表与命令编码。 */
CONTRACT_ASSERT(bitblt_base,          BITBLT_BASE == 0xE1000000u);
CONTRACT_ASSERT(control_offset,       BITBLT_CONTROL == 0x00u);
CONTRACT_ASSERT(status_offset,        BITBLT_STATUS == 0x04u);
CONTRACT_ASSERT(src_addr_offset,      BITBLT_SRC_ADDR == 0x08u);
CONTRACT_ASSERT(dst_addr_offset,      BITBLT_DST_ADDR == 0x0Cu);
CONTRACT_ASSERT(width_offset,         BITBLT_WIDTH == 0x10u);
CONTRACT_ASSERT(height_offset,        BITBLT_HEIGHT == 0x14u);
CONTRACT_ASSERT(src_stride_offset,    BITBLT_SRC_STRIDE == 0x18u);
CONTRACT_ASSERT(dst_stride_offset,    BITBLT_DST_STRIDE == 0x1Cu);
CONTRACT_ASSERT(color_offset,         BITBLT_COLOR == 0x20u);
CONTRACT_ASSERT(operation_offset,     BITBLT_OPERATION == 0x24u);
CONTRACT_ASSERT(version_offset,       BITBLT_VERSION == 0x28u);
CONTRACT_ASSERT(control_start_bit,    BITBLT_CONTROL_START == (1u << 0));
CONTRACT_ASSERT(control_clear_bit,    BITBLT_CONTROL_CLEAR == (1u << 1));
CONTRACT_ASSERT(status_busy_bit,      BITBLT_STATUS_BUSY == (1u << 0));
CONTRACT_ASSERT(status_done_bit,      BITBLT_STATUS_DONE == (1u << 1));
CONTRACT_ASSERT(status_error_bit,     BITBLT_STATUS_ERROR == (1u << 2));
CONTRACT_ASSERT(fill_operation,       BITBLT_OP_FILL == 0u);
CONTRACT_ASSERT(copy_operation,       BITBLT_OP_COPY == 1u);

/* 返回码数值是 ABI 的一部分。 */
CONTRACT_ASSERT(result_ok,             BITBLT_OK == 0);
CONTRACT_ASSERT(result_einval,         BITBLT_EINVAL == -1);
CONTRACT_ASSERT(result_ebusy,          BITBLT_EBUSY == -2);
CONTRACT_ASSERT(result_etimeout,       BITBLT_ETIMEOUT == -3);
CONTRACT_ASSERT(result_ehw,            BITBLT_EHW == -4);

/* 板端已验证的 XRGB8888 / 1080p 布局。 */
CONTRACT_ASSERT(ddr_base,               DDR_PHYSICAL_BASE == 0x00000000u);
CONTRACT_ASSERT(ddr_size,               DDR_PHYSICAL_SIZE == 0x10000000u);
CONTRACT_ASSERT(system_reserved_base,   SYSTEM_RESERVED_BASE == 0x00000000u);
CONTRACT_ASSERT(system_reserved_size,   SYSTEM_RESERVED_SIZE == 0x01000000u);
CONTRACT_ASSERT(pixel_bytes,            FB_BYTES_PER_PIXEL == 4u);
CONTRACT_ASSERT(render_pixel_bytes,     RENDER_PIXEL_BYTES == FB_BYTES_PER_PIXEL);
CONTRACT_ASSERT(frame_width,            FB_WIDTH == 1920u);
CONTRACT_ASSERT(frame_height,           FB_HEIGHT == 1080u);
CONTRACT_ASSERT(pixel_clock,            FB_PIXEL_CLOCK_HZ == 148750000u);
CONTRACT_ASSERT(h_front_porch,          FB_H_FRONT_PORCH == 88u);
CONTRACT_ASSERT(h_sync,                 FB_H_SYNC == 44u);
CONTRACT_ASSERT(h_back_porch,           FB_H_BACK_PORCH == 148u);
CONTRACT_ASSERT(v_front_porch,          FB_V_FRONT_PORCH == 4u);
CONTRACT_ASSERT(v_sync,                 FB_V_SYNC == 5u);
CONTRACT_ASSERT(v_back_porch,           FB_V_BACK_PORCH == 36u);
CONTRACT_ASSERT(frame_stride,           FB_STRIDE == FB_WIDTH * FB_BYTES_PER_PIXEL);
CONTRACT_ASSERT(frame_active_bytes,     FB_ACTIVE_BYTES == 8294400u);
CONTRACT_ASSERT(frame_slot_size,        FB_SLOT_SIZE == 0x00800000u);
CONTRACT_ASSERT(frame_fits_slot,        FB_ACTIVE_BYTES <= FB_SLOT_SIZE);
CONTRACT_ASSERT(frame_a_base,           FB_A_BASE == 0x01000000u);
CONTRACT_ASSERT(frame_b_base,           FB_B_BASE == 0x01800000u);
CONTRACT_ASSERT(frame_slots_adjacent,   FB_B_BASE == FB_A_BASE + FB_SLOT_SIZE);
CONTRACT_ASSERT(asset_base,             ASSET_BASE == 0x02000000u);
CONTRACT_ASSERT(asset_size,             ASSET_SIZE == 0x02000000u);
CONTRACT_ASSERT(assets_after_frames,    ASSET_BASE == FB_B_BASE + FB_SLOT_SIZE);
CONTRACT_ASSERT(scratch_base,           SCRATCH_BASE == 0x04000000u);
CONTRACT_ASSERT(scratch_size,           SCRATCH_SIZE == 0x01000000u);
CONTRACT_ASSERT(ddr_free_base,          DDR_FREE_BASE == 0x05000000u);
CONTRACT_ASSERT(ddr_free_size,          DDR_FREE_SIZE == 0x0B000000u);
CONTRACT_ASSERT(xrgb8888_format,        PIXEL_FORMAT_XRGB8888 == 0u);
CONTRACT_ASSERT(xrgb8888_channels,      XRGB8888(0x12u, 0x34u, 0x56u) == 0x00123456u);

/*
 * 赋值给精确的函数指针类型：参数数量、顺序、宽度或返回类型
 * 任意一项变化都会在 -Werror 下直接编译失败。
 */
typedef bitblt_result_t (*fill_signature_t)(uint32_t, uint32_t, uint32_t,
                                             uint32_t, uint32_t, uint64_t);
typedef bitblt_result_t (*copy_signature_t)(uint32_t, uint32_t, uint32_t,
                                             uint32_t, uint32_t, uint32_t,
                                             uint64_t);
typedef void (*irq_signature_t)(void);
typedef void (*register_write_signature_t)(uint32_t, uint32_t);
typedef uint32_t (*register_read_signature_t)(uint32_t);

static fill_signature_t contract_fill = bitblt_fill;
static copy_signature_t contract_copy = bitblt_copy;
static irq_signature_t contract_irq = bitblt_irq_handler;
static register_write_signature_t contract_register_write = bitblt_write;
static register_read_signature_t contract_register_read = bitblt_read;

void bitblt_contract_compile_probe(void)
{
    (void)contract_fill;
    (void)contract_copy;
    (void)contract_irq;
    (void)contract_register_write;
    (void)contract_register_read;
}
