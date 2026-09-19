/*
 * B/C 编译期接口契约。
 *
 * 这里只引用 04_project/bitblt_accel/sw/driver 中的权威头文件，
 * 不复制任何定义。如果 B 修改了寄存器、API 类型或显示布局，
 * 这个翻译单元会在 contract 回归的最前面给出精确的失配位置。
 *
 * 本翻译单元是【唯一允许出现真实地址字面量】的地方：它的职责就是
 * 核对数字。render/ 与 driver/ 受 make check-no-addresses 约束，
 * 那里只能引用宏，不能写死地址。
 *
 * 像素格式：软件侧由 RENDER_PIXEL_FORMAT_RGB565 决定（默认 RGB565）。
 * B 的 framebuffer_layout.h 目前仍是 XRGB8888/1080p 历史值，
 * 这一点由文件末尾那组 b_header_still_legacy_* 断言显式钉住。
 */

#include "bitblt_regs.h"
#include "bitblt_api.h"
#include "display_regs.h"
#include "framebuffer_layout.h"
#include "../render/renderer.h"
#include "../driver/framebuffer_format.h"
#include "../driver/protocol_frozen.h"

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

/* ---- DDR 地址布局：与团队统一目标一致，两种格式共用 ---- */
CONTRACT_ASSERT(ddr_base,               DDR_PHYSICAL_BASE == 0x00000000u);
CONTRACT_ASSERT(ddr_size,               DDR_PHYSICAL_SIZE == 0x10000000u);
CONTRACT_ASSERT(system_reserved_base,   SYSTEM_RESERVED_BASE == 0x00000000u);
CONTRACT_ASSERT(system_reserved_size,   SYSTEM_RESERVED_SIZE == 0x01000000u);
CONTRACT_ASSERT(frame_slot_size,        FB_SLOT_SIZE == 0x00800000u);
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

/* 系统保留区不得压到 Framebuffer A */
CONTRACT_ASSERT(reserved_below_fb,
                SYSTEM_RESERVED_BASE + SYSTEM_RESERVED_SIZE <= FB_A_BASE);

/* ---- 现行统一目标：几何数值必须与迁移文档一致 ---- */
/* 见 07_docs/interfaces/rgb565_720p_migration.md 的「已确认的跨组数据约定」 */
#if RENDER_PIXEL_FORMAT_RGB565
CONTRACT_ASSERT(fmt_width,              FMT_WIDTH == 1280u);
CONTRACT_ASSERT(fmt_height,             FMT_HEIGHT == 720u);
CONTRACT_ASSERT(fmt_bytes_per_pixel,    FMT_BYTES_PER_PIXEL == 2u);
CONTRACT_ASSERT(fmt_stride,             FMT_STRIDE == 2560u);
CONTRACT_ASSERT(fmt_frame_bytes,        FMT_FRAME_BYTES == 1843200u);
CONTRACT_ASSERT(fmt_pixels_per_beat,    FMT_PIXELS_PER_BEAT == 8u);
CONTRACT_ASSERT(fmt_width_granularity,  FMT_WIDTH_GRANULARITY == 8u);
CONTRACT_ASSERT(fmt_pixel_clock,        FMT_PIXEL_CLOCK_HZ == 74250000u);
CONTRACT_ASSERT(fmt_h_total,
                FMT_WIDTH + FMT_H_FRONT_PORCH + FMT_H_SYNC + FMT_H_BACK_PORCH == 1650u);
CONTRACT_ASSERT(fmt_v_total,
                FMT_HEIGHT + FMT_V_FRONT_PORCH + FMT_V_SYNC + FMT_V_BACK_PORCH == 750u);
#else
CONTRACT_ASSERT(fmt_width,              FMT_WIDTH == 1920u);
CONTRACT_ASSERT(fmt_height,             FMT_HEIGHT == 1080u);
CONTRACT_ASSERT(fmt_bytes_per_pixel,    FMT_BYTES_PER_PIXEL == 4u);
CONTRACT_ASSERT(fmt_stride,             FMT_STRIDE == 7680u);
CONTRACT_ASSERT(fmt_frame_bytes,        FMT_FRAME_BYTES == 8294400u);
CONTRACT_ASSERT(fmt_pixels_per_beat,    FMT_PIXELS_PER_BEAT == 4u);
CONTRACT_ASSERT(fmt_width_granularity,  FMT_WIDTH_GRANULARITY == 4u);
CONTRACT_ASSERT(fmt_pixel_clock,        FMT_PIXEL_CLOCK_HZ == 148750000u);
CONTRACT_ASSERT(fmt_h_total,
                FMT_WIDTH + FMT_H_FRONT_PORCH + FMT_H_SYNC + FMT_H_BACK_PORCH == 2200u);
CONTRACT_ASSERT(fmt_v_total,
                FMT_HEIGHT + FMT_V_FRONT_PORCH + FMT_V_SYNC + FMT_V_BACK_PORCH == 1125u);
#endif

/* 软件像素宽度由 pixel_t 派生 */
CONTRACT_ASSERT(render_pixel_bytes,     RENDER_PIXEL_BYTES == FMT_BYTES_PER_PIXEL);
CONTRACT_ASSERT(render_pixel_bytes_ok,  RENDER_PIXEL_BYTES == 2u || RENDER_PIXEL_BYTES == 4u);

/* 每像素字节数一致：软件几何与 BitBlt 硬件按同一宽度算 stride */
CONTRACT_ASSERT(fmt_matches_sw,         FMT_BYTES_PER_PIXEL == RENDER_PIXEL_BYTES);

/* 一整帧必须装得进一个 8 MiB slot */
CONTRACT_ASSERT(fmt_frame_fits_slot,    FMT_FRAME_BYTES <= FB_SLOT_SIZE);

/*
 * B 的 framebuffer_layout.h 目前【仍是 XRGB8888/1080p 历史值】——
 * 迁移文档明写「B组尚未迁移」。下面这组断言把这个事实钉住：
 *
 *   - B 一旦迁移完，这些断言会失败，提醒把 FMT_* 的几何改为直接引用 B 的
 *     头文件（driver/framebuffer_format.h 顶部的 UNFROZEN_PROTOCOL 注记）。
 *   - 在此之前，C 侧的 RGB565 几何由 framebuffer_format.h 持有，
 *     地址仍然全部来自 B 的 framebuffer_layout.h。
 */
CONTRACT_ASSERT(b_header_still_legacy_pixel_bytes, FB_BYTES_PER_PIXEL == 4u);
CONTRACT_ASSERT(b_header_still_legacy_width,       FB_WIDTH == 1920u);
CONTRACT_ASSERT(b_header_still_legacy_height,      FB_HEIGHT == 1080u);
CONTRACT_ASSERT(b_header_still_legacy_stride,      FB_STRIDE == FB_WIDTH * FB_BYTES_PER_PIXEL);
CONTRACT_ASSERT(b_header_still_legacy_frame,       FB_ACTIVE_BYTES == 8294400u);

CONTRACT_ASSERT(xrgb8888_format,        PIXEL_FORMAT_XRGB8888 == 0u);
CONTRACT_ASSERT(xrgb8888_channels,      XRGB8888(0x12u, 0x34u, 0x56u) == 0x00123456u);

/* ================================================================== */
/* 已冻结的联合协议（2026-09-19）                                      */
/* ================================================================== */

/* ---- DISPLAY_FORMAT 枚举 ---- */
CONTRACT_ASSERT(display_format_xrgb8888, PROTO_DISPLAY_FORMAT_XRGB8888 == 0u);
CONTRACT_ASSERT(display_format_rgb565,   PROTO_DISPLAY_FORMAT_RGB565 == 1u);

/* 两个枚举必须不同：同值会让"按格式分支"静默退化成一条路 */
CONTRACT_ASSERT(format_enums_distinct,
                PROTO_DISPLAY_FORMAT_XRGB8888 != PROTO_DISPLAY_FORMAT_RGB565);

/* ---- 新版本号 ---- */
CONTRACT_ASSERT(bitblt_version_rgb565,   PROTO_BITBLT_VERSION_RGB565 == 0x00020000u);
CONTRACT_ASSERT(display_version_rgb565,  PROTO_DISPLAY_VERSION_RGB565 == 0x00030000u);

/* ---- 版本拆分：高 16 位主版本、低 16 位次版本 ---- */
CONTRACT_ASSERT(bitblt_major, PROTO_VERSION_MAJOR(PROTO_BITBLT_VERSION_RGB565) == 2u);
CONTRACT_ASSERT(bitblt_minor, PROTO_VERSION_MINOR(PROTO_BITBLT_VERSION_RGB565) == 0u);
CONTRACT_ASSERT(display_major, PROTO_VERSION_MAJOR(PROTO_DISPLAY_VERSION_RGB565) == 3u);
CONTRACT_ASSERT(display_minor, PROTO_VERSION_MINOR(PROTO_DISPLAY_VERSION_RGB565) == 0u);

/* 拆分宏本身要自洽：拼回去必须等于原值 */
CONTRACT_ASSERT(bitblt_split_roundtrip,
                (PROTO_VERSION_MAJOR(PROTO_BITBLT_VERSION_RGB565) << 16 |
                 PROTO_VERSION_MINOR(PROTO_BITBLT_VERSION_RGB565)) == PROTO_BITBLT_VERSION_RGB565);
CONTRACT_ASSERT(display_split_roundtrip,
                (PROTO_VERSION_MAJOR(PROTO_DISPLAY_VERSION_RGB565) << 16 |
                 PROTO_VERSION_MINOR(PROTO_DISPLAY_VERSION_RGB565)) == PROTO_DISPLAY_VERSION_RGB565);

/*
 * RGB565 是【不兼容升级】，主版本必须比已板测的 XRGB8888 版本高。
 * 这一条防的是"改了像素格式却忘 了进主版本"——那种位流会被旧软件
 * 当成兼容版本接受，然后画出一屏乱码。
 */
CONTRACT_ASSERT(bitblt_version_upgraded,
                PROTO_VERSION_MAJOR(PROTO_BITBLT_VERSION_RGB565)
                    > PROTO_VERSION_MAJOR(BITBLT_VERSION_V0_4));
CONTRACT_ASSERT(display_version_upgraded,
                PROTO_VERSION_MAJOR(PROTO_DISPLAY_VERSION_RGB565)
                    > PROTO_VERSION_MAJOR(DISPLAY_VERSION_V0_2));

/* 两个新版本号必须互不相同：它们属于不同寄存器，同值会让日志无法区分 */
CONTRACT_ASSERT(versions_distinct,
                PROTO_BITBLT_VERSION_RGB565 != PROTO_DISPLAY_VERSION_RGB565);

/* ================================================================== */
/* B 的权威头文件是否已同步                                            */
/* ================================================================== */
/*
 * 上面那些 PROTO_* 常量目前由 driver/protocol_frozen.h【代持】，
 * 因为 B 的 bitblt_regs.h / display_regs.h 还没有这几个宏。
 *
 * 一旦 B 同步，下面的 COUNT 会变成 1，CONTRACT_ASSERT 失败 ——
 * 那不是缺陷，是提醒：
 *   1. 把 protocol_frozen.h 里代持的数字换成直接引用 B 的宏
 *   2. 删掉这段检测
 * 这个检测存在的意义就是不让两套版本定义长期并存。
 */
#ifdef BITBLT_VERSION_RGB565
#define PROTO_B_SYNC_BITBLT_VER 1
#else
#define PROTO_B_SYNC_BITBLT_VER 0
#endif

#ifdef DISPLAY_FORMAT_RGB565
#define PROTO_B_SYNC_DISPLAY_FMT 1
#else
#define PROTO_B_SYNC_DISPLAY_FMT 0
#endif

#ifdef DISPLAY_VERSION_RGB565
#define PROTO_B_SYNC_DISPLAY_VER 1
#else
#define PROTO_B_SYNC_DISPLAY_VER 0
#endif

CONTRACT_ASSERT(b_header_not_yet_synced,
                (PROTO_B_SYNC_BITBLT_VER + PROTO_B_SYNC_DISPLAY_FMT
                 + PROTO_B_SYNC_DISPLAY_VER) == 0);

/* XRGB8888 枚举值是历史兼容项，B 早就有了 —— 它必须一直存在 */
CONTRACT_ASSERT(xrgb8888_enum_still_present, DISPLAY_FORMAT_XRGB8888 == 0u);

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
