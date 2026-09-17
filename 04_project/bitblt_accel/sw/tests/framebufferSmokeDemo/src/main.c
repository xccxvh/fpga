#include <stdint.h>
#include "bsp.h"
#include "bitblt_regs.h"
#include "display_regs.h"
#include "framebuffer_layout.h"

#define TIMEOUT_LOOPS 50000000u

static const uint32_t colors[8] = {
    XRGB8888(255, 255, 255), XRGB8888(255, 255, 0),
    XRGB8888(0, 255, 255),   XRGB8888(0, 255, 0),
    XRGB8888(255, 0, 255),   XRGB8888(255, 0, 0),
    XRGB8888(0, 0, 255),     XRGB8888(0, 0, 0)
};

static void fail(const char *message) {
    bsp_printf("FAILED: %s\r\n", message);
    while (1) {}
}

void crash(void) { fail("unexpected trap"); }
void trap(void) { crash(); }
void trap_entry(void);

static void fill(uint32_t dst, uint32_t width, uint32_t height,
                 uint32_t stride, uint32_t color) {
    uint32_t timeout = TIMEOUT_LOOPS;
    uint32_t status;
    bitblt_write(BITBLT_DST_ADDR, dst);
    bitblt_write(BITBLT_WIDTH, width);
    bitblt_write(BITBLT_HEIGHT, height);
    bitblt_write(BITBLT_DST_STRIDE, stride);
    bitblt_write(BITBLT_COLOR, color);
    bitblt_write(BITBLT_OPERATION, BITBLT_OP_FILL);
    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_CLEAR);
    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_START);
    do { status = bitblt_read(BITBLT_STATUS); }
    while (!(status & BITBLT_STATUS_DONE) && --timeout);
    if (!timeout) fail("BitBlt timeout");
    if (status & BITBLT_STATUS_ERROR) fail("BitBlt error");
}

static void draw_horizontal_bars(uint32_t base) {
    uint32_t i;
    for (i = 0; i < 8; ++i)
        fill(base + i * 60u * FB_STRIDE, FB_WIDTH, 60u,
             FB_STRIDE, colors[i]);
}

static void draw_vertical_bars(uint32_t base) {
    uint32_t i;
    for (i = 0; i < 8; ++i)
        fill(base + i * 80u * FB_BYTES_PER_PIXEL, 80u, FB_HEIGHT,
             FB_STRIDE, colors[i]);
}

void main(void) {
    uint32_t timeout, start_frame;
    bsp_init();
    bsp_printf("*** BitBlt Framebuffer Smoke Demo ***\r\n");
    if (bitblt_read(BITBLT_VERSION) != 0x00010003u)
        fail("BitBlt version");
    if (display_read(DISPLAY_VERSION) != DISPLAY_VERSION_V0_2)
        fail("display version/address decode");
    bsp_printf("Register decode: PASSED\r\n");

    draw_horizontal_bars(FB_A_BASE);
    bsp_printf("Framebuffer A horizontal bars: READY\r\n");
    display_write(DISPLAY_WIDTH, FB_WIDTH);
    display_write(DISPLAY_HEIGHT, FB_HEIGHT);
    display_write(DISPLAY_STRIDE, FB_STRIDE);
    display_write(DISPLAY_FORMAT, DISPLAY_FORMAT_XRGB8888);
    display_write(DISPLAY_IRQ_ENABLE, 0u);
    display_write(DISPLAY_CONTROL,
                  DISPLAY_CONTROL_ENABLE | DISPLAY_CONTROL_CLEAR);
    start_frame = display_read(DISPLAY_FRAME_COUNT);
    timeout = TIMEOUT_LOOPS;
    while ((display_read(DISPLAY_FRAME_COUNT) - start_frame) < 2u && --timeout) {}
    if (!timeout) fail("display frame timeout");
    if (display_read(DISPLAY_STATUS) & DISPLAY_STATUS_ERROR)
        fail("display initial status");
    bsp_printf("Framebuffer A scanout: PASSED\r\n");

    draw_vertical_bars(FB_B_BASE);
    bsp_printf("Framebuffer B vertical bars: READY\r\n");
    display_write(DISPLAY_NEXT_ADDR, FB_B_BASE);
    display_write(DISPLAY_CONTROL,
                  DISPLAY_CONTROL_ENABLE | DISPLAY_CONTROL_SWAP_REQUEST);
    timeout = TIMEOUT_LOOPS;
    while (!(display_read(DISPLAY_STATUS) & DISPLAY_STATUS_SWAP_DONE) && --timeout) {}
    if (!timeout) fail("VBlank swap timeout");
    if (display_read(DISPLAY_FRONT_ADDR) != FB_B_BASE)
        fail("front buffer did not switch");
    if (display_read(DISPLAY_STATUS) &
        (DISPLAY_STATUS_UNDERFLOW | DISPLAY_STATUS_ERROR))
        fail("display underflow/error");
    bsp_printf("VBlank A->B swap: PASSED\r\n");
    bsp_printf("*** FRAMEBUFFER SMOKE DEMO PASSED ***\r\n");
    while (1) {}
}
