#ifndef FRAMEBUFFER_LAYOUT_H
#define FRAMEBUFFER_LAYOUT_H

#include <stdint.h>

/* Ti60F225 demo board: one MT41J128M16JT-125, 256 MiB DDR3. */
#define DDR_PHYSICAL_BASE          0x00000000u
#define DDR_PHYSICAL_SIZE          0x10000000u
#define SYSTEM_RESERVED_BASE       0x00000000u
#define SYSTEM_RESERVED_SIZE       0x01000000u

/* Board-tested display target: CTA-861 1920x1080p60, XRGB8888. */
#define FB_WIDTH                   1920u
#define FB_HEIGHT                  1080u
#define FB_PIXEL_CLOCK_HZ          148750000u
#define FB_H_FRONT_PORCH           88u
#define FB_H_SYNC                  44u
#define FB_H_BACK_PORCH            148u
#define FB_V_FRONT_PORCH           4u
#define FB_V_SYNC                  5u
#define FB_V_BACK_PORCH            36u
#define FB_BYTES_PER_PIXEL         4u
#define FB_STRIDE                  (FB_WIDTH * FB_BYTES_PER_PIXEL)
#define FB_ACTIVE_BYTES            (FB_STRIDE * FB_HEIGHT)
#define FB_SLOT_SIZE               0x00800000u

/* Each 8 MiB slot fits one 1920x1080 XRGB8888 frame (8,294,400 B). */
#define FB_A_BASE                  0x01000000u
#define FB_B_BASE                  0x01800000u
#define ASSET_BASE                 0x02000000u
#define ASSET_SIZE                 0x02000000u
#define SCRATCH_BASE               0x04000000u
#define SCRATCH_SIZE               0x01000000u
#define DDR_FREE_BASE              0x05000000u
#define DDR_FREE_SIZE              0x0B000000u

#define PIXEL_FORMAT_XRGB8888      0u
#define XRGB8888(r, g, b) \
    ((((uint32_t)(r) & 0xffu) << 16) | \
     (((uint32_t)(g) & 0xffu) << 8)  | \
      ((uint32_t)(b) & 0xffu))

#endif
