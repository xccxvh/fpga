#ifndef BITBLT_API_H
#define BITBLT_API_H

#include <stdint.h>

typedef enum {
    BITBLT_OK = 0,
    BITBLT_EINVAL = -1,
    BITBLT_EBUSY = -2,
    BITBLT_ETIMEOUT = -3,
    BITBLT_EHW = -4
} bitblt_result_t;

/* Blocking V0.2 software contract; timeout_ticks uses the 100 MHz CLINT. */
bitblt_result_t bitblt_fill(uint32_t dst_addr,
                            uint32_t width, uint32_t height,
                            uint32_t dst_stride, uint32_t color,
                            uint64_t timeout_ticks);

bitblt_result_t bitblt_copy(uint32_t src_addr, uint32_t dst_addr,
                            uint32_t width, uint32_t height,
                            uint32_t src_stride, uint32_t dst_stride,
                            uint64_t timeout_ticks);

/* PLIC source 30 is shared by SYSTEM_AXI_A clients. */
void bitblt_irq_handler(void);

#endif
