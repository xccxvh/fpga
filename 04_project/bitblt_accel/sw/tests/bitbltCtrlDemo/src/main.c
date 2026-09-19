#include <stdint.h>
#include "bsp.h"
#include "riscv.h"
#include "plic.h"
#include "vexriscv.h"
#include "bitblt_regs.h"

static volatile uint32_t irq_seen;
static void fail(const char *message) { bsp_printf("FAILED: %s\r\n", message); while (1) {} }
void crash(void) { fail("unexpected trap"); }
void bitblt_interrupt(void) {
    uint32_t claim;
    while ((claim = plic_claim(BSP_PLIC, BSP_PLIC_CPU_0)) != 0) {
        if (claim == SYSTEM_PLIC_SYSTEM_AXI_A_INTERRUPT) irq_seen = 1;
        else crash();
        plic_release(BSP_PLIC, BSP_PLIC_CPU_0, claim);
    }
}
void trap(void) {
    int32_t value = csr_read(mcause);
    if ((value < 0) && ((value & 0xF) == CAUSE_MACHINE_EXTERNAL)) bitblt_interrupt();
    else crash();
}
void trap_entry(void);
static void interrupt_init(void) {
    plic_set_threshold(BSP_PLIC, BSP_PLIC_CPU_0, 0);
    plic_set_enable(BSP_PLIC, BSP_PLIC_CPU_0, SYSTEM_PLIC_SYSTEM_AXI_A_INTERRUPT, 1);
    plic_set_priority(BSP_PLIC, SYSTEM_PLIC_SYSTEM_AXI_A_INTERRUPT, 1);
    csr_write(mtvec, trap_entry);
    csr_set(mie, MIE_MEIE);
    csr_write(mstatus, csr_read(mstatus) | MSTATUS_MPP | MSTATUS_MIE);
}
void main(void) {
    const uint32_t src = 0x01100000u;
    const uint32_t dst = 0x01200000u;
    const uint32_t width = 80u;
    const uint32_t height = 3u;
    const uint32_t src_stride = 160u;
    const uint32_t dst_stride = 176u;
    volatile uint16_t *source = (volatile uint16_t *)src;
    volatile uint16_t *destination = (volatile uint16_t *)dst;
    uint32_t timeout, status, x, y;
    uint16_t expected;
    bsp_init();
    bsp_printf("*** BitBlt Block Copy MVP ***\r\n");
    if (bitblt_read(BITBLT_VERSION) != BITBLT_VERSION_V2_0) fail("version register");
    for (y = 0; y < height; ++y) {
        for (x = 0; x < width; ++x)
            source[y * (src_stride / 2u) + x] = (uint16_t)(0x5000u | (y << 8) | x);
    }
    bsp_printf("CPU DDR writes: ISSUED\r\n");
    __asm__ volatile ("fence rw,rw" ::: "memory");
    bsp_printf("Source pattern: PREPARED\r\n");
    bitblt_write(BITBLT_SRC_ADDR, src);
    bitblt_write(BITBLT_DST_ADDR, dst);
    bitblt_write(BITBLT_WIDTH, width);
    bitblt_write(BITBLT_HEIGHT, height);
    bitblt_write(BITBLT_SRC_STRIDE, src_stride);
    bitblt_write(BITBLT_DST_STRIDE, dst_stride);
    bitblt_write(BITBLT_COLOR, 0u);
    bitblt_write(BITBLT_OPERATION, BITBLT_OP_COPY);
    if (bitblt_read(BITBLT_SRC_ADDR) != src ||
        bitblt_read(BITBLT_DST_ADDR) != dst ||
        bitblt_read(BITBLT_WIDTH) != width || bitblt_read(BITBLT_HEIGHT) != height ||
        bitblt_read(BITBLT_SRC_STRIDE) != src_stride ||
        bitblt_read(BITBLT_DST_STRIDE) != dst_stride ||
        bitblt_read(BITBLT_OPERATION) != BITBLT_OP_COPY) fail("register readback");
    bsp_printf("Register readback: PASSED\r\n");
    irq_seen = 0; interrupt_init();
    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_CLEAR);
    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_START);
    timeout = 10000000u;
    do { status = bitblt_read(BITBLT_STATUS); }
    while (!(status & BITBLT_STATUS_DONE) && --timeout);
    if (!timeout) fail("completion timeout");
    if (status & BITBLT_STATUS_ERROR) fail("hardware status error");
    if (!irq_seen) fail("completion interrupt");
    bsp_printf("Status transition: PASSED\r\n");
    bsp_printf("Completion IRQ: PASSED\r\n");
    __asm__ volatile ("fence rw,rw" ::: "memory");
    for (y = 0; y < height; ++y) {
        for (x = 0; x < width; ++x) {
            data_cache_invalidate_address(&destination[y * (dst_stride / 2u) + x]);
            expected = (uint16_t)(0x5000u | (y << 8) | x);
            if (destination[y * (dst_stride / 2u) + x] != expected)
                fail("DDR copy mismatch");
        }
    }
    bsp_printf("DDR Copy burst readback: PASSED (240 pixels)\r\n");
    bsp_printf("*** BitBlt Block Copy MVP PASSED ***\r\n");
    while (1) {}
}
