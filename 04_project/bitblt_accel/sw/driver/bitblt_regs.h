#ifndef BITBLT_REGS_H
#define BITBLT_REGS_H
#include <stdint.h>
#define BITBLT_BASE 0xE1000000u
#define BITBLT_CONTROL 0x00u
#define BITBLT_STATUS 0x04u
#define BITBLT_SRC_ADDR 0x08u
#define BITBLT_DST_ADDR 0x0Cu
#define BITBLT_WIDTH 0x10u
#define BITBLT_HEIGHT 0x14u
#define BITBLT_SRC_STRIDE 0x18u
#define BITBLT_DST_STRIDE 0x1Cu
#define BITBLT_COLOR 0x20u
#define BITBLT_OPERATION 0x24u
#define BITBLT_VERSION 0x28u
#define BITBLT_CONTROL_START (1u << 0)
#define BITBLT_CONTROL_CLEAR (1u << 1)
#define BITBLT_STATUS_BUSY (1u << 0)
#define BITBLT_STATUS_DONE (1u << 1)
#define BITBLT_STATUS_ERROR (1u << 2)
#define BITBLT_OP_FILL 0u
#define BITBLT_OP_COPY 1u
#define BITBLT_OP_COLOR_KEY 2u
#define BITBLT_VERSION_V0_4 0x00010004u
static inline void bitblt_write(uint32_t offset, uint32_t value) {
    *(volatile uint32_t *)(BITBLT_BASE + offset) = value;
}
static inline uint32_t bitblt_read(uint32_t offset) {
    return *(volatile uint32_t *)(BITBLT_BASE + offset);
}
#endif
