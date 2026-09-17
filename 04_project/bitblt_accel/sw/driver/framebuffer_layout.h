#ifndef FRAMEBUFFER_LAYOUT_H
#define FRAMEBUFFER_LAYOUT_H

#include <stdint.h>

/* Ti60F225 demo board: one MT41J128M16JT-125, 256 MiB DDR3. */
#define DDR_PHYSICAL_BASE          0x00000000u
#define DDR_PHYSICAL_SIZE          0x10000000u
#define SYSTEM_RESERVED_BASE       0x00000000u
#define SYSTEM_RESERVED_SIZE       0x01000000u

/* First integration target: 640x480p60, little-endian XRGB8888. */
#define FB_WIDTH                   640u
#define FB_HEIGHT                  480u
#define FB_PIXEL_CLOCK_HZ          25200000u
#define FB_H_FRONT_PORCH           16u
#define FB_H_SYNC                  96u
#define FB_H_BACK_PORCH            48u
#define FB_V_FRONT_PORCH           10u
#define FB_V_SYNC                  2u
#define FB_V_BACK_PORCH            33u
#define FB_BYTES_PER_PIXEL         4u
#define FB_STRIDE                  (FB_WIDTH * FB_BYTES_PER_PIXEL)
#define FB_ACTIVE_BYTES            (FB_STRIDE * FB_HEIGHT)
#define FB_SLOT_SIZE               0x00800000u

/* 8 MiB slots also fit one 1920x1080 XRGB8888 frame. */
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
