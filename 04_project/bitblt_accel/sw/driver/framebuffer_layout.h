#ifndef FRAMEBUFFER_LAYOUT_H
#define FRAMEBUFFER_LAYOUT_H

#include <stdint.h>

/* Ti60F225 demo board: one MT41J128M16JT-125, 256 MiB DDR3. */
#define DDR_PHYSICAL_BASE          0x00000000u
#define DDR_PHYSICAL_SIZE          0x10000000u
#define SYSTEM_RESERVED_BASE       0x00000000u
#define SYSTEM_RESERVED_SIZE       0x01000000u

/* Frozen joint target: CTA-861 1280x720p60, little-endian RGB565. */
#define FB_WIDTH                   1280u
#define FB_HEIGHT                  720u
#define FB_PIXEL_CLOCK_HZ          74250000u
#define FB_H_FRONT_PORCH           110u
#define FB_H_SYNC                  40u
#define FB_H_BACK_PORCH            220u
#define FB_V_FRONT_PORCH           5u
#define FB_V_SYNC                  5u
#define FB_V_BACK_PORCH            20u
#define FB_BYTES_PER_PIXEL         2u
#define FB_STRIDE                  (FB_WIDTH * FB_BYTES_PER_PIXEL)
#define FB_ACTIVE_BYTES            (FB_STRIDE * FB_HEIGHT)
#define FB_SLOT_SIZE               0x00800000u

/* Each 8 MiB slot fits one 1280x720 RGB565 frame (1,843,200 B). */
#define FB_A_BASE                  0x01000000u
#define FB_B_BASE                  0x01800000u
#define ASSET_BASE                 0x02000000u
#define ASSET_SIZE                 0x02000000u
#define SCRATCH_BASE               0x04000000u
#define SCRATCH_SIZE               0x01000000u
#define DDR_FREE_BASE              0x05000000u
#define DDR_FREE_SIZE              0x0B000000u

#define PIXEL_FORMAT_XRGB8888      0u
#define PIXEL_FORMAT_RGB565        1u
#define RGB565(r, g, b) \
    ((uint16_t)((((uint16_t)(r) & 0xf8u) << 8) | \
                (((uint16_t)(g) & 0xfcu) << 3) | \
                (((uint16_t)(b) & 0xf8u) >> 3)))
#define XRGB8888(r, g, b) \
    ((((uint32_t)(r) & 0xffu) << 16) | \
     (((uint32_t)(g) & 0xffu) << 8)  | \
      ((uint32_t)(b) & 0xffu))

#endif
