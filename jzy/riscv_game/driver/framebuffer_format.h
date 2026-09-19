#ifndef FRAMEBUFFER_FORMAT_H
#define FRAMEBUFFER_FORMAT_H

#include <stdint.h>

#include "renderer_sw.h"        /* 格式开关与 pixel_t —— 本工程唯一的开关点 */
#include "framebuffer_layout.h" /* B 组权威 DDR 布局：地址唯一来源 */


/*
 * 现行显示格式与几何参数。
 *
 * ┌─ UNFROZEN_PROTOCOL ───────────────────────────────────────────────┐
 * │ 本文件的【几何参数】来自团队 2026-09-18 的决定：                   │
 * │   07_docs/interfaces/unified_fpga_interface_spec_v1.0.md         │
 * │                                                                   │
 * │ 那份文档同时写明「B组尚未迁移」——B 的权威 framebuffer_layout.h    │
 * │ 里仍然是 XRGB8888/1080p 的几何。所以几何参数暂时只能由本文件持有， │
 * │ 等 B 迁移完 framebuffer_layout.h 之后，本文件的几何宏应改为直接    │
 * │ 引用 B 的头文件，并把这里删掉。                                    │
 * │                                                                   │
 * │ 【地址】不在这里定义。FB A/B、素材区、Scratch、系统保留区一律      │
 * │ include B 的 framebuffer_layout.h 获得，本工程不复制任何地址数字。 │
 * └───────────────────────────────────────────────────────────────────┘
 *
 * 对应的编译期核对（真实数值断言）在 tests/test_contract.c 里：
 * 那里允许出现字面量，因为它的职责就是核对数字；
 * 而本目录受 make check-no-addresses 约束，不得出现硬编码地址。
 */

#if RENDER_PIXEL_FORMAT_RGB565

/* 现行目标：RGB565 / 1280x720@60 */
#define FMT_WIDTH              1280u
#define FMT_HEIGHT             720u
#define FMT_BYTES_PER_PIXEL    2u
#define FMT_PIXELS_PER_WORD    2u   /* 32-bit 控制/软件 word */
#define FMT_PIXELS_PER_BEAT    8u   /* 128-bit DDR AXI beat */
#define FMT_PIXEL_CLOCK_HZ     74250000u
#define FMT_H_FRONT_PORCH      110u
#define FMT_H_SYNC             40u
#define FMT_H_BACK_PORCH       220u
#define FMT_V_FRONT_PORCH      5u
#define FMT_V_SYNC             5u
#define FMT_V_BACK_PORCH       20u

/* 宽度必须是 8 像素的倍数：128-bit beat 一次搬 8 个 16-bit 像素，
   半拍会把一行切在 beat 中间，硬件不支持。 */
#define FMT_WIDTH_GRANULARITY  8u

/* 一个像素在 COLOR 寄存器里的表示：低 16 位有效，高 16 位必须写 0。 */
#define FMT_COLOR_MASK         0x0000FFFFu
#define FMT_COLOR_VALID_BITS   16u

#else

/* 历史基线（可回退）：XRGB8888 / 1920x1080@60，已板测通过 */
#define FMT_WIDTH              1920u
#define FMT_HEIGHT             1080u
#define FMT_BYTES_PER_PIXEL    4u
#define FMT_PIXELS_PER_WORD    1u
#define FMT_PIXELS_PER_BEAT    4u
#define FMT_PIXEL_CLOCK_HZ     148750000u
#define FMT_H_FRONT_PORCH      88u
#define FMT_H_SYNC             44u
#define FMT_H_BACK_PORCH       148u
#define FMT_V_FRONT_PORCH      4u
#define FMT_V_SYNC             5u
#define FMT_V_BACK_PORCH       36u

#define FMT_WIDTH_GRANULARITY  4u

#define FMT_COLOR_MASK         0xFFFFFFFFu
#define FMT_COLOR_VALID_BITS   32u

#endif

/* 字节 stride 与整帧字节数 —— 由上面的基本参数派生，不另填数字 */
#define FMT_STRIDE             (FMT_WIDTH * FMT_BYTES_PER_PIXEL)
#define FMT_FRAME_BYTES        (FMT_STRIDE * FMT_HEIGHT)

/* 地址与 stride 的硬件对齐要求（两个格式相同，来自 BitBlt 接口约定 §4） */
#define FMT_ALIGN_BYTES        16u


/* ------------------------------------------------------------------ *
 * 编译期核对（全部用关系式，不出现字面量地址）
 *
 * 这些断言盯的是"布局意图"而不是具体数字：具体数字的核对在
 * tests/test_contract.c 里做。这里保证的是本工程对布局的理解自洽——
 * 比如 8 MiB 的 slot 装得下当前格式的一整帧。
 * ------------------------------------------------------------------ */

typedef char fmt_frame_16b_aligned[(FMT_FRAME_BYTES % FMT_ALIGN_BYTES) == 0u ? 1 : -1];
typedef char fmt_stride_16b_aligned[(FMT_STRIDE % FMT_ALIGN_BYTES) == 0u ? 1 : -1];
typedef char fmt_width_granularity_16b[
    (FMT_WIDTH_GRANULARITY * FMT_BYTES_PER_PIXEL) == FMT_ALIGN_BYTES ? 1 : -1];
typedef char fmt_beat_covers_word[
    (FMT_PIXELS_PER_WORD * FMT_BYTES_PER_PIXEL) <= 4u ? 1 : -1];

/* 帧缓冲 A/B 是相邻的两个 8 MiB slot，素材区在其后，Scratch 更后 */
typedef char fmt_fb_a_before_b[(FB_A_BASE < FB_B_BASE) ? 1 : -1];
typedef char fmt_fb_slots_adjacent[(FB_B_BASE == FB_A_BASE + FB_SLOT_SIZE) ? 1 : -1];
typedef char fmt_asset_after_fb[(ASSET_BASE >= FB_B_BASE + FB_SLOT_SIZE) ? 1 : -1];
typedef char fmt_asset_covers_slots[(ASSET_SIZE >= 2u * FB_SLOT_SIZE) ? 1 : -1];
typedef char fmt_scratch_after_asset[(SCRATCH_BASE >= ASSET_BASE + ASSET_SIZE) ? 1 : -1];
typedef char fmt_scratch_fits[(SCRATCH_BASE + SCRATCH_SIZE) <= DDR_PHYSICAL_SIZE ? 1 : -1];

/* 当前格式的一整帧必须装得进一个 slot，否则双缓冲根本放不下 */
typedef char fmt_frame_fits_slot[(FMT_FRAME_BYTES <= FB_SLOT_SIZE) ? 1 : -1];


/* ------------------------------------------------------------------ *
 * 像素打包 / 解包
 *
 * RGB565 是 16-bit 格式，从 24-bit 通道值转换时必须明确舍入方式。
 * 这里统一用【高位截断】（取通道的高 5/6 位），解包用【位复制】
 * （R8 = {R5, R5[4:2]}），与统一规范的显示侧扩展一致。
 *
 * 位复制的性质：0 → 0，满量程 → 满量程（R5=31 → 255），
 * 且不做浮点/除法，适合当前没有硬件乘法器的场景。
 * ------------------------------------------------------------------ */

/* 三个 8-bit 通道值 -> 1 个 RGB565 像素值（低 16 位有效） */
uint16_t fmt_rgb565_pack(uint8_t r, uint8_t g, uint8_t b);

/* XRGB8888（0x00RRGGBB）-> RGB565 */
uint16_t fmt_xrgb8888_to_rgb565(uint32_t xrgb8888);

/* RGB565 -> XRGB8888（0x00RRGGBB），用于和旧素材/旧基线比对 */
uint32_t fmt_rgb565_to_xrgb8888(uint16_t rgb565);

/* RGB565 -> 三个 8-bit 通道值。任一指针为 0 表示不取该通道 */
void fmt_rgb565_unpack(uint16_t rgb565, uint8_t *r, uint8_t *g, uint8_t *b);

/* 把 32 位软件颜色值折算成硬件 COLOR 寄存器值：
   RGB565 下取低 16 位，XRGB8888 下原样返回。
   高 16 位必须为 0，避免新旧驱动误配（统一规范 §7）。 */
uint32_t fmt_color_to_hw(pixel_t c);

/* 硬件 COLOR 寄存器值还原成软件像素值。与 fmt_color_to_hw 互逆。 */
pixel_t fmt_color_from_hw(uint32_t hw);

#endif
