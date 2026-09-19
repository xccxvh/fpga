#ifndef DISPLAY_REGS_H
#define DISPLAY_REGS_H

#include <stdint.h>

/* V0.2 frozen contract, implemented by display_ctrl_axi.v. */
#define DISPLAY_BASE               0xE1100000u

#define DISPLAY_CONTROL            0x00u
#define DISPLAY_STATUS             0x04u
#define DISPLAY_FRONT_ADDR         0x08u
#define DISPLAY_NEXT_ADDR          0x0Cu
#define DISPLAY_WIDTH              0x10u
#define DISPLAY_HEIGHT             0x14u
#define DISPLAY_STRIDE             0x18u
#define DISPLAY_FORMAT             0x1Cu
#define DISPLAY_FRAME_COUNT        0x20u
#define DISPLAY_UNDERFLOW_COUNT    0x24u
#define DISPLAY_VERSION            0x28u
#define DISPLAY_IRQ_ENABLE         0x2Cu

#define DISPLAY_CONTROL_ENABLE       (1u << 0)
#define DISPLAY_CONTROL_SWAP_REQUEST (1u << 1)
#define DISPLAY_CONTROL_CLEAR        (1u << 2)

#define DISPLAY_STATUS_ENABLED       (1u << 0)
#define DISPLAY_STATUS_SWAP_PENDING  (1u << 1)
#define DISPLAY_STATUS_SWAP_DONE     (1u << 2)
#define DISPLAY_STATUS_UNDERFLOW     (1u << 3)
#define DISPLAY_STATUS_ERROR         (1u << 4)

#define DISPLAY_IRQ_SWAP_DONE        (1u << 0)
#define DISPLAY_IRQ_UNDERFLOW        (1u << 1)
#define DISPLAY_IRQ_ERROR            (1u << 2)

#define DISPLAY_FORMAT_XRGB8888      0u
#define DISPLAY_FORMAT_RGB565        1u
#define DISPLAY_VERSION_V0_2         0x00020000u
#define DISPLAY_VERSION_V3_0         0x00030000u

static inline void display_write(uint32_t offset, uint32_t value) {
    *(volatile uint32_t *)(DISPLAY_BASE + offset) = value;
}

static inline uint32_t display_read(uint32_t offset) {
    return *(volatile uint32_t *)(DISPLAY_BASE + offset);
}

#endif
