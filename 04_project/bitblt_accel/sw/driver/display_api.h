#ifndef DISPLAY_API_H
#define DISPLAY_API_H

#include <stdint.h>

typedef enum {
    DISPLAY_OK = 0,
    DISPLAY_EINVAL = -1,
    DISPLAY_EBUSY = -2,
    DISPLAY_ETIMEOUT = -3,
    DISPLAY_EHW = -4
} display_result_t;

display_result_t display_init(uint32_t front_addr,
                              uint32_t width, uint32_t height,
                              uint32_t stride, uint32_t format);
display_result_t display_queue_swap(uint32_t next_addr);
display_result_t display_wait_swap(uint64_t timeout_ticks);
uint32_t display_get_front(void);
void display_irq_handler(void);

#endif
