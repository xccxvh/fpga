#include <stdint.h>
#include "bsp.h"
#include "riscv.h"
#include "plic.h"
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
    const uint32_t dst = 0x01200000u, width = 64u, height = 4u;
    const uint32_t stride = width * 4u, color = 0xA5C3F00Du;
    volatile uint32_t *frame = (volatile uint32_t *)dst;
    uint32_t timeout, status, x, y;
    bsp_init();
    bsp_printf("*** BitBlt DDR Fill MVP ***\r\n");
    if (bitblt_read(BITBLT_VERSION) != 0x00010001u) fail("version register");
    bitblt_write(BITBLT_SRC_ADDR, 0x01000000u);
    bitblt_write(BITBLT_DST_ADDR, dst);
    bitblt_write(BITBLT_WIDTH, width);
    bitblt_write(BITBLT_HEIGHT, height);
    bitblt_write(BITBLT_SRC_STRIDE, stride);
    bitblt_write(BITBLT_DST_STRIDE, stride);
    bitblt_write(BITBLT_COLOR, color);
    bitblt_write(BITBLT_OPERATION, BITBLT_OP_FILL);
    if (bitblt_read(BITBLT_SRC_ADDR) != 0x01000000u ||
        bitblt_read(BITBLT_DST_ADDR) != dst ||
        bitblt_read(BITBLT_WIDTH) != width || bitblt_read(BITBLT_HEIGHT) != height ||
        bitblt_read(BITBLT_SRC_STRIDE) != stride ||
        bitblt_read(BITBLT_DST_STRIDE) != stride ||
        bitblt_read(BITBLT_COLOR) != color ||
        bitblt_read(BITBLT_OPERATION) != BITBLT_OP_FILL) fail("register readback");
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
    for (y = 0; y < height; ++y)
        for (x = 0; x < width; ++x)
            if (frame[y * (stride / 4u) + x] != color) fail("DDR pixel mismatch");
    bsp_printf("DDR Fill readback: PASSED (256 pixels)\r\n");
    bsp_printf("*** BitBlt DDR Fill MVP PASSED ***\r\n");
    while (1) {}
}
