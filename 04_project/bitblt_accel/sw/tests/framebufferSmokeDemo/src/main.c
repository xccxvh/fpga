#include <stdint.h>
#include "bsp.h"
#include "riscv.h"
#include "plic.h"
#include "vexriscv.h"
#include "bitblt_regs.h"
#include "display_regs.h"
#include "framebuffer_layout.h"

#define TIMEOUT_LOOPS 50000000u

#ifndef STRESS_FRAMES
#define STRESS_FRAMES 32u
#endif

#ifndef STRESS_REPORT_INTERVAL
#define STRESS_REPORT_INTERVAL 8u
#endif

static const uint32_t colors[8] = {
    XRGB8888(255, 255, 255), XRGB8888(255, 255, 0),
    XRGB8888(0, 255, 255),   XRGB8888(0, 255, 0),
    XRGB8888(255, 0, 255),   XRGB8888(255, 0, 0),
    XRGB8888(0, 0, 255),     XRGB8888(0, 0, 0)
};

static volatile uint32_t bitblt_irq_count;
static volatile uint32_t swap_irq_seen;
static volatile uint32_t display_fault_status;
static volatile uint32_t unexpected_irq;

static void fail(const char *message) {
    bsp_printf("FAILED: %s\r\n", message);
    while (1) {}
}

void crash(void) { fail("unexpected trap"); }

static void shared_axi_interrupt(void) {
    uint32_t claim;
    while ((claim = plic_claim(BSP_PLIC, BSP_PLIC_CPU_0)) != 0u) {
        if (claim == SYSTEM_PLIC_SYSTEM_AXI_A_INTERRUPT) {
            uint32_t bitblt_status = bitblt_read(BITBLT_STATUS);
            uint32_t display_status = display_read(DISPLAY_STATUS);
            uint32_t handled = 0u;
            if (bitblt_status & BITBLT_STATUS_DONE) {
                ++bitblt_irq_count;
                handled = 1u;
            }
            if (display_status & DISPLAY_STATUS_SWAP_DONE) {
                swap_irq_seen = 1u;
                handled = 1u;
            }
            if (display_status &
                (DISPLAY_STATUS_UNDERFLOW | DISPLAY_STATUS_ERROR)) {
                display_fault_status = display_status;
                handled = 1u;
            }
            if (display_status &
                (DISPLAY_STATUS_SWAP_DONE | DISPLAY_STATUS_UNDERFLOW |
                 DISPLAY_STATUS_ERROR))
                display_write(DISPLAY_CONTROL,
                              DISPLAY_CONTROL_ENABLE |
                              DISPLAY_CONTROL_CLEAR);
            if (!handled)
                unexpected_irq = 1u;
        } else {
            unexpected_irq = claim;
        }
        plic_release(BSP_PLIC, BSP_PLIC_CPU_0, claim);
    }
}

void trap(void) {
    int32_t cause = csr_read(mcause);
    if ((cause < 0) && ((cause & 0xFu) == CAUSE_MACHINE_EXTERNAL))
        shared_axi_interrupt();
    else
        crash();
}
void trap_entry(void);

static void interrupt_init(void) {
    plic_set_threshold(BSP_PLIC, BSP_PLIC_CPU_0, 0);
    plic_set_enable(BSP_PLIC, BSP_PLIC_CPU_0,
                    SYSTEM_PLIC_SYSTEM_AXI_A_INTERRUPT, 1);
    plic_set_priority(BSP_PLIC, SYSTEM_PLIC_SYSTEM_AXI_A_INTERRUPT, 1);
    csr_write(mtvec, trap_entry);
    csr_set(mie, MIE_MEIE);
    csr_write(mstatus, csr_read(mstatus) | MSTATUS_MPP | MSTATUS_MIE);
}

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
        fill(base + i * 135u * FB_STRIDE, FB_WIDTH, 135u,
             FB_STRIDE, colors[i]);
}

static void draw_vertical_bars(uint32_t base) {
    uint32_t i;
    for (i = 0; i < 8; ++i)
        fill(base + i * 240u * FB_BYTES_PER_PIXEL, 240u, FB_HEIGHT,
             FB_STRIDE, colors[i]);
}

static void wait_for_bitblt_irqs(uint32_t expected) {
    uint32_t timeout = TIMEOUT_LOOPS;
    while ((bitblt_irq_count != expected) && --timeout) {}
    if (!timeout || unexpected_irq)
        fail("shared BitBlt interrupt");
}

static void swap_to(uint32_t address) {
    uint32_t timeout = TIMEOUT_LOOPS;
    swap_irq_seen = 0u;
    display_write(DISPLAY_NEXT_ADDR, address);
    display_write(DISPLAY_CONTROL,
                  DISPLAY_CONTROL_ENABLE | DISPLAY_CONTROL_SWAP_REQUEST);
    while (!swap_irq_seen && --timeout) {}
    if (!timeout)
        fail("VBlank swap timeout");
    if (display_read(DISPLAY_FRONT_ADDR) != address)
        fail("front buffer did not switch");
    if (display_fault_status || unexpected_irq)
        fail("display underflow/error");
}

static void stress_fill(uint32_t dst, uint32_t color,
                        volatile uint32_t *scratch) {
    uint32_t timeout = TIMEOUT_LOOPS;
    uint32_t status, index = 0u, cpu_error = 0u;
    uint32_t expected_irq = bitblt_irq_count + 1u;

    bitblt_write(BITBLT_DST_ADDR, dst);
    bitblt_write(BITBLT_WIDTH, FB_WIDTH);
    bitblt_write(BITBLT_HEIGHT, FB_HEIGHT);
    bitblt_write(BITBLT_DST_STRIDE, FB_STRIDE);
    bitblt_write(BITBLT_COLOR, color);
    bitblt_write(BITBLT_OPERATION, BITBLT_OP_FILL);
    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_CLEAR);
    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_START);
    do {
        uint32_t slot = index++ & 255u;
        if (scratch[slot] != (0xA5000000u | slot))
            cpu_error = 1u;
        status = bitblt_read(BITBLT_STATUS);
    } while (!(status & BITBLT_STATUS_DONE) && --timeout);

    if (!timeout)
        fail("stress BitBlt timeout");
    if ((status & BITBLT_STATUS_ERROR) || cpu_error)
        fail("concurrent DDR traffic");
    wait_for_bitblt_irqs(expected_irq);
    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_CLEAR);
}

static void run_concurrent_stress(void) {
    volatile uint32_t *scratch = (volatile uint32_t *)SCRATCH_BASE;
    uint32_t i, front, back, start_frames, completed_frames, underflows;

    for (i = 0u; i < 256u; ++i)
        scratch[i] = 0xA5000000u | i;
    __asm__ volatile ("fence rw,rw" ::: "memory");

    start_frames = display_read(DISPLAY_FRAME_COUNT);
    for (i = 0u; i < STRESS_FRAMES; ++i) {
        front = display_read(DISPLAY_FRONT_ADDR);
        back = (front == FB_A_BASE) ? FB_B_BASE : FB_A_BASE;
        stress_fill(back, colors[i & 7u], scratch);
        swap_to(back);
#if STRESS_REPORT_INTERVAL > 0
        if (((i + 1u) % STRESS_REPORT_INTERVAL) == 0u)
            bsp_printf("  stress progress: %d/%d swaps\r\n",
                       i + 1u, STRESS_FRAMES);
#endif
    }
    completed_frames = display_read(DISPLAY_FRAME_COUNT) - start_frames;
    underflows = display_read(DISPLAY_UNDERFLOW_COUNT);
    if (underflows != 0u || display_fault_status || unexpected_irq)
        fail("stress display accounting");
    bsp_printf("Concurrent DDR/display stress: PASSED (%d swaps, "
               "%d display frames, %d underflows)\r\n",
               STRESS_FRAMES, completed_frames, underflows);

    front = display_read(DISPLAY_FRONT_ADDR);
    back = (front == FB_A_BASE) ? FB_B_BASE : FB_A_BASE;
    i = bitblt_irq_count + 8u;
    draw_vertical_bars(back);
    wait_for_bitblt_irqs(i);
    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_CLEAR);
    swap_to(back);
    bsp_printf("Vertical color bars restored: PASSED\r\n");
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

    display_write(DISPLAY_IRQ_ENABLE, 0u);
    display_write(DISPLAY_CONTROL, DISPLAY_CONTROL_CLEAR);
    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_CLEAR);
    bitblt_irq_count = 0u;
    swap_irq_seen = 0u;
    display_fault_status = 0u;
    unexpected_irq = 0u;
    interrupt_init();

    draw_horizontal_bars(FB_A_BASE);
    bsp_printf("Framebuffer A horizontal bars: READY\r\n");
    display_write(DISPLAY_WIDTH, FB_WIDTH);
    display_write(DISPLAY_HEIGHT, FB_HEIGHT);
    display_write(DISPLAY_STRIDE, FB_STRIDE);
    display_write(DISPLAY_FORMAT, DISPLAY_FORMAT_XRGB8888);
    display_write(DISPLAY_IRQ_ENABLE,
                  DISPLAY_IRQ_SWAP_DONE | DISPLAY_IRQ_UNDERFLOW |
                  DISPLAY_IRQ_ERROR);
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
    wait_for_bitblt_irqs(16u);
    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_CLEAR);
    bsp_printf("Shared IRQ BitBlt source: PASSED (16 interrupts)\r\n");

    swap_to(FB_B_BASE);
    bsp_printf("VBlank A->B swap: PASSED\r\n");
    bsp_printf("Shared IRQ display source: PASSED\r\n");
    run_concurrent_stress();
    bsp_printf("*** FRAMEBUFFER SMOKE DEMO PASSED ***\r\n");
    while (1) {}
}
