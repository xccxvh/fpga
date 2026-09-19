#include <stdint.h>
#include "bsp.h"
#include "riscv.h"
#include "plic.h"
#include "vexriscv.h"
#include "bitblt_regs.h"
#include "framebuffer_layout.h"

#define TEST_WIDTH 24u
#define TEST_HEIGHT 5u
#define SRC_STRIDE 48u
#define DST_STRIDE 64u
#define KEY_RGB 0x07e0u
#define BACKGROUND 0x3333u
#define GUARD_BEFORE 0x1357u
#define GUARD_AFTER 0x2468u

static volatile uint32_t irq_seen;

static void fail(const char *message) {
    bsp_printf("FAILED: %s\r\n", message);
    while (1) {}
}

void crash(void) { fail("unexpected trap"); }

static void bitblt_interrupt(void) {
    uint32_t claim;
    while ((claim = plic_claim(BSP_PLIC, BSP_PLIC_CPU_0)) != 0u) {
        if (claim == SYSTEM_PLIC_SYSTEM_AXI_A_INTERRUPT)
            irq_seen = 1u;
        else
            fail("unexpected interrupt");
        plic_release(BSP_PLIC, BSP_PLIC_CPU_0, claim);
    }
}

void trap(void) {
    int32_t cause = csr_read(mcause);
    if ((cause < 0) && ((cause & 0xFu) == CAUSE_MACHINE_EXTERNAL))
        bitblt_interrupt();
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

static uint16_t source_pixel(uint32_t x, uint32_t y) {
    if (((x + y) & 3u) == 0u)
        return KEY_RGB;
    return (uint16_t)(0x5000u | (y << 8) | x);
}

void main(void) {
    const uint32_t src_addr = ASSET_BASE + 0x1000u;
    const uint32_t dst_addr = SCRATCH_BASE + 0x1000u;
    volatile uint16_t *src = (volatile uint16_t *)src_addr;
    volatile uint16_t *dst = (volatile uint16_t *)dst_addr;
    uint32_t x, y, timeout, status;
    uint16_t expected;

    bsp_init();
    bsp_printf("*** BitBlt Color Key Demo ***\r\n");
    if (bitblt_read(BITBLT_VERSION) != BITBLT_VERSION_V2_0)
        fail("version register");

    for (y = 0u; y < TEST_HEIGHT; ++y) {
        for (x = 0u; x < SRC_STRIDE / 2u; ++x)
            src[y * (SRC_STRIDE / 2u) + x] =
                (x < TEST_WIDTH) ? source_pixel(x, y) : 0xee00u;
        for (x = 0u; x < DST_STRIDE / 2u; ++x)
            dst[y * (DST_STRIDE / 2u) + x] = BACKGROUND;
    }
    dst[-1] = GUARD_BEFORE;
    dst[TEST_HEIGHT * (DST_STRIDE / 2u)] = GUARD_AFTER;
    __asm__ volatile ("fence rw,rw" ::: "memory");
    bsp_printf("Source/background pattern: READY\r\n");

    bitblt_write(BITBLT_SRC_ADDR, src_addr);
    bitblt_write(BITBLT_DST_ADDR, dst_addr);
    bitblt_write(BITBLT_WIDTH, TEST_WIDTH);
    bitblt_write(BITBLT_HEIGHT, TEST_HEIGHT);
    bitblt_write(BITBLT_SRC_STRIDE, SRC_STRIDE);
    bitblt_write(BITBLT_DST_STRIDE, DST_STRIDE);
    bitblt_write(BITBLT_COLOR, KEY_RGB);
    bitblt_write(BITBLT_OPERATION, BITBLT_OP_COLOR_KEY);

    irq_seen = 0u;
    interrupt_init();
    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_CLEAR);
    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_START);
    timeout = 10000000u;
    do {
        status = bitblt_read(BITBLT_STATUS);
    } while (!(status & BITBLT_STATUS_DONE) && --timeout);
    if (!timeout)
        fail("completion timeout");
    if (status & BITBLT_STATUS_ERROR)
        fail("hardware status error");
    if (!irq_seen)
        fail("completion interrupt");
    bsp_printf("Completion IRQ/status: PASSED\r\n");

    __asm__ volatile ("fence rw,rw" ::: "memory");
    for (y = 0u; y < TEST_HEIGHT; ++y) {
        for (x = 0u; x < TEST_WIDTH; ++x) {
            data_cache_invalidate_address(&dst[y * (DST_STRIDE / 2u) + x]);
            expected = source_pixel(x, y);
            if (expected == KEY_RGB)
                expected = BACKGROUND;
            if (dst[y * (DST_STRIDE / 2u) + x] != expected)
                fail("Color Key pixel mismatch");
        }
        for (x = TEST_WIDTH; x < DST_STRIDE / 2u; ++x) {
            data_cache_invalidate_address(&dst[y * (DST_STRIDE / 2u) + x]);
            if (dst[y * (DST_STRIDE / 2u) + x] != BACKGROUND)
                fail("destination padding modified");
        }
    }
    data_cache_invalidate_address(&dst[-1]);
    data_cache_invalidate_address(&dst[TEST_HEIGHT * (DST_STRIDE / 2u)]);
    if (dst[-1] != GUARD_BEFORE ||
        dst[TEST_HEIGHT * (DST_STRIDE / 2u)] != GUARD_AFTER)
        fail("destination guard modified");

    bsp_printf("RGB565 key compare: PASSED\r\n");
    bsp_printf("Stride/padding/guards: PASSED\r\n");
    bsp_printf("*** BITBLT COLOR KEY DEMO PASSED ***\r\n");
    while (1) {}
}
