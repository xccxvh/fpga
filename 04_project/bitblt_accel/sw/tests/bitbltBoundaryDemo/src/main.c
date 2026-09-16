#include <stdint.h>
#include "bsp.h"
#include "clint.h"
#include "plic.h"
#include "riscv.h"
#include "vexriscv.h"
#include "bitblt_regs.h"

#define GUARD_VALUE       0xD15EA5E5u
#define TIMEOUT_POLLS     100000000u
#define FILL_BASE         0x01110000u
#define COPY_SRC          0x01120000u
#define COPY_DST_BASE     0x01220000u
#define BOUNDARY_SRC      0x01300FF0u
#define BOUNDARY_DST      0x01400FF0u
#define LARGE_SRC         0x01500000u
#define LARGE_DST         0x01700000u

static volatile uint32_t irq_seen;

static void fail(const char *message) {
    bsp_printf("FAILED: %s\r\n", message);
    while (1) {}
}

void crash(void) {
    fail("unexpected trap");
}

void bitblt_interrupt(void) {
    uint32_t claim;
    while ((claim = plic_claim(BSP_PLIC, BSP_PLIC_CPU_0)) != 0) {
        if (claim == SYSTEM_PLIC_SYSTEM_AXI_A_INTERRUPT)
            irq_seen = 1;
        else
            crash();
        plic_release(BSP_PLIC, BSP_PLIC_CPU_0, claim);
    }
}

void trap(void) {
    int32_t value = csr_read(mcause);
    if ((value < 0) && ((value & 0xF) == CAUSE_MACHINE_EXTERNAL))
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

static void write_word(uint32_t address, uint32_t value) {
    *(volatile uint32_t *)address = value;
}

static uint32_t read_word(uint32_t address) {
    volatile uint32_t *pointer = (volatile uint32_t *)address;
    data_cache_invalidate_address(pointer);
    return *pointer;
}

static uint32_t pattern(uint32_t index) {
    return 0xA5000000u | (index & 0x00FFFFFFu);
}

static void fill_words(uint32_t address, uint32_t words, uint32_t value) {
    uint32_t index;
    for (index = 0; index < words; ++index)
        write_word(address + index * 4u, value);
}

static void expect_word(uint32_t address, uint32_t expected,
                        const char *message) {
    if (read_word(address) != expected)
        fail(message);
}

static uint32_t run_command(uint32_t op, uint32_t src, uint32_t dst,
                            uint32_t width, uint32_t height,
                            uint32_t source_stride,
                            uint32_t destination_stride,
                            uint32_t fill_color) {
    uint32_t timeout = TIMEOUT_POLLS;
    uint32_t status;
    uint64_t start_time, end_time;

    bitblt_write(BITBLT_SRC_ADDR, src);
    bitblt_write(BITBLT_DST_ADDR, dst);
    bitblt_write(BITBLT_WIDTH, width);
    bitblt_write(BITBLT_HEIGHT, height);
    bitblt_write(BITBLT_SRC_STRIDE, source_stride);
    bitblt_write(BITBLT_DST_STRIDE, destination_stride);
    bitblt_write(BITBLT_COLOR, fill_color);
    bitblt_write(BITBLT_OPERATION, op);

    __asm__ volatile ("fence rw,rw" ::: "memory");
    irq_seen = 0;
    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_CLEAR);
    start_time = clint_getTime(BSP_CLINT);
    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_START);
    do {
        status = bitblt_read(BITBLT_STATUS);
    } while (!(status & BITBLT_STATUS_DONE) && --timeout);
    end_time = clint_getTime(BSP_CLINT);

    if (!timeout)
        fail("completion timeout");
    if (status & BITBLT_STATUS_ERROR)
        fail("hardware status error");
    if (!irq_seen)
        fail("completion interrupt missing");
    return (uint32_t)(end_time - start_time);
}

static void test_fill_guards(void) {
    const uint32_t dst = FILL_BASE + 64u;
    const uint32_t width = 20u;
    const uint32_t height = 3u;
    const uint32_t stride = 128u;
    const uint32_t fill_color = 0x18C3F05Au;
    uint32_t x, y;

    fill_words(FILL_BASE, 16u + height * (stride / 4u) + 16u, GUARD_VALUE);
    run_command(BITBLT_OP_FILL, 0, dst, width, height, 0, stride, fill_color);

    for (x = 0; x < 16u; ++x)
        expect_word(FILL_BASE + x * 4u, GUARD_VALUE, "Fill prefix guard");
    for (y = 0; y < height; ++y) {
        for (x = 0; x < width; ++x)
            expect_word(dst + y * stride + x * 4u, fill_color, "Fill pixel");
        for (x = width; x < stride / 4u; ++x)
            expect_word(dst + y * stride + x * 4u, GUARD_VALUE,
                        "Fill row padding guard");
    }
    for (x = 0; x < 16u; ++x)
        expect_word(dst + height * stride + x * 4u, GUARD_VALUE,
                    "Fill suffix guard");
    bsp_printf("Fill guard test: PASSED\r\n");
}

static void test_copy_guards(void) {
    const uint32_t dst = COPY_DST_BASE + 64u;
    const uint32_t width = 20u;
    const uint32_t height = 3u;
    const uint32_t source_stride = 128u;
    const uint32_t destination_stride = 160u;
    uint32_t x, y, value;

    fill_words(COPY_DST_BASE,
               16u + height * (destination_stride / 4u) + 16u, GUARD_VALUE);
    for (y = 0; y < height; ++y)
        for (x = 0; x < width; ++x)
            write_word(COPY_SRC + y * source_stride + x * 4u,
                       pattern(y * width + x));

    run_command(BITBLT_OP_COPY, COPY_SRC, dst, width, height,
                source_stride, destination_stride, 0);

    for (x = 0; x < 16u; ++x)
        expect_word(COPY_DST_BASE + x * 4u, GUARD_VALUE, "Copy prefix guard");
    for (y = 0; y < height; ++y) {
        for (x = 0; x < width; ++x) {
            value = pattern(y * width + x);
            expect_word(dst + y * destination_stride + x * 4u,
                        value, "Copy pixel");
        }
        for (x = width; x < destination_stride / 4u; ++x)
            expect_word(dst + y * destination_stride + x * 4u,
                        GUARD_VALUE, "Copy row padding guard");
    }
    for (x = 0; x < 16u; ++x)
        expect_word(dst + height * destination_stride + x * 4u,
                    GUARD_VALUE, "Copy suffix guard");
    bsp_printf("Copy guard/stride test: PASSED\r\n");
}

static void test_4k_boundary(void) {
    const uint32_t width = 20u;
    const uint32_t height = 2u;
    const uint32_t stride = 128u;
    uint32_t x, y, value;

    fill_words(BOUNDARY_DST - 64u, 16u + height * (stride / 4u) + 16u,
               GUARD_VALUE);
    for (y = 0; y < height; ++y)
        for (x = 0; x < width; ++x)
            write_word(BOUNDARY_SRC + y * stride + x * 4u,
                       pattern(0x1000u + y * width + x));

    run_command(BITBLT_OP_COPY, BOUNDARY_SRC, BOUNDARY_DST,
                width, height, stride, stride, 0);

    for (x = 0; x < 16u; ++x)
        expect_word(BOUNDARY_DST - 64u + x * 4u, GUARD_VALUE,
                    "4KiB prefix guard");
    for (y = 0; y < height; ++y) {
        for (x = 0; x < width; ++x) {
            value = pattern(0x1000u + y * width + x);
            expect_word(BOUNDARY_DST + y * stride + x * 4u,
                        value, "4KiB copy pixel");
        }
        for (x = width; x < stride / 4u; ++x)
            expect_word(BOUNDARY_DST + y * stride + x * 4u,
                        GUARD_VALUE, "4KiB row padding guard");
    }
    for (x = 0; x < 16u; ++x)
        expect_word(BOUNDARY_DST + height * stride + x * 4u,
                    GUARD_VALUE, "4KiB suffix guard");
    bsp_printf("4KiB boundary test: PASSED\r\n");
}

static void test_large_copy(void) {
    const uint32_t width = 640u;
    const uint32_t height = 480u;
    const uint32_t stride = width * 4u;
    const uint32_t pixels = width * height;
    const uint32_t bytes = pixels * 4u;
    uint32_t index, ticks, kib_per_second;

    fill_words(LARGE_DST - 64u, 16u, GUARD_VALUE);
    fill_words(LARGE_DST + bytes, 16u, GUARD_VALUE);
    for (index = 0; index < pixels; ++index)
        write_word(LARGE_SRC + index * 4u, pattern(index));

    ticks = run_command(BITBLT_OP_COPY, LARGE_SRC, LARGE_DST,
                        width, height, stride, stride, 0);

    for (index = 0; index < pixels; ++index)
        expect_word(LARGE_DST + index * 4u, pattern(index),
                    "Large Copy pixel");
    for (index = 0; index < 16u; ++index) {
        expect_word(LARGE_DST - 64u + index * 4u, GUARD_VALUE,
                    "Large Copy prefix guard");
        expect_word(LARGE_DST + bytes + index * 4u, GUARD_VALUE,
                    "Large Copy suffix guard");
    }

    if (ticks == 0)
        fail("Large Copy zero timing");
    kib_per_second = (uint32_t)(((uint64_t)(bytes / 1024u) * BSP_CLINT_HZ) /
                                ticks);
    bsp_printf("Large Copy 640x480: PASSED\r\n");
    bsp_printf("Large Copy bytes=%d ticks=%d throughput=%d KiB/s\r\n",
               bytes, ticks, kib_per_second);
}

void main(void) {
    bsp_init();
    bsp_printf("*** BitBlt Board Boundary Regression ***\r\n");
    if (bitblt_read(BITBLT_VERSION) != 0x00010003u)
        fail("version register");
    interrupt_init();

    test_fill_guards();
    test_copy_guards();
    test_4k_boundary();
    test_large_copy();

    bsp_printf("*** BitBlt Board Boundary Regression PASSED ***\r\n");
    while (1) {}
}
