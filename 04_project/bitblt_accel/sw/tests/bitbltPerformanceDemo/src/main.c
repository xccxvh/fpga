#include <stdint.h>
#include "bsp.h"
#include "riscv.h"
#include "bitblt_regs.h"
#include "display_regs.h"
#include "framebuffer_layout.h"

#define TIMEOUT_LOOPS 50000000u
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))

typedef struct {
    uint32_t width;
    uint32_t height;
    uint32_t repeats;
} benchmark_case_t;

typedef struct {
    uint64_t cpu_fill_ticks;
    uint64_t hw_fill_ticks;
    uint64_t cpu_copy_ticks;
    uint64_t hw_copy_ticks;
} benchmark_result_t;

static const benchmark_case_t cases[] = {
    {64u,   64u,    1u},
    {320u,  240u,   1u},
    {640u,  480u,   1u},
    {1280u, 720u,   1u}
};

static const uint32_t colors[8] = {
    RGB565(255, 255, 255), RGB565(255, 255, 0),
    RGB565(0, 255, 255),   RGB565(0, 255, 0),
    RGB565(255, 0, 255),   RGB565(255, 0, 0),
    RGB565(0, 0, 255),     RGB565(0, 0, 0)
};

static void fail(const char *message) {
    bsp_printf("FAILED: %s\r\n", message);
    while (1) {}
}

void crash(void) { fail("unexpected trap"); }
void trap(void) {
    bsp_printf("FAILED trap: mcause=0x%x mepc=0x%x mtval=0x%x\r\n",
               csr_read(mcause), csr_read(mepc), csr_read(mtval));
    while (1) {}
}
void trap_entry(void);

static void bitblt_wait(void) {
    uint32_t timeout = TIMEOUT_LOOPS;
    uint32_t status;
    do {
        status = bitblt_read(BITBLT_STATUS);
    } while (!(status & BITBLT_STATUS_DONE) && --timeout);
    if (!timeout)
        fail("BitBlt timeout");
    if (status & BITBLT_STATUS_ERROR)
        fail("BitBlt status error");
}

static void bitblt_fill_once(uint32_t dst, uint32_t width,
                             uint32_t height, uint32_t color) {
    uint32_t stride = width * FB_BYTES_PER_PIXEL;
    bitblt_write(BITBLT_DST_ADDR, dst);
    bitblt_write(BITBLT_WIDTH, width);
    bitblt_write(BITBLT_HEIGHT, height);
    bitblt_write(BITBLT_DST_STRIDE, stride);
    bitblt_write(BITBLT_COLOR, color);
    bitblt_write(BITBLT_OPERATION, BITBLT_OP_FILL);
    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_CLEAR);
    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_START);
    bitblt_wait();
}

static void bitblt_copy_once(uint32_t dst, uint32_t src,
                             uint32_t width, uint32_t height) {
    uint32_t stride = width * FB_BYTES_PER_PIXEL;
    bitblt_write(BITBLT_SRC_ADDR, src);
    bitblt_write(BITBLT_DST_ADDR, dst);
    bitblt_write(BITBLT_WIDTH, width);
    bitblt_write(BITBLT_HEIGHT, height);
    bitblt_write(BITBLT_SRC_STRIDE, stride);
    bitblt_write(BITBLT_DST_STRIDE, stride);
    bitblt_write(BITBLT_OPERATION, BITBLT_OP_COPY);
    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_CLEAR);
    bitblt_write(BITBLT_CONTROL, BITBLT_CONTROL_START);
    bitblt_wait();
}

static void draw_front_buffer(void) {
    uint32_t i;
    for (i = 0u; i < 8u; ++i)
        bitblt_fill_once(FB_A_BASE + i * 90u * FB_STRIDE,
                         FB_WIDTH, 90u, colors[i]);

    display_write(DISPLAY_IRQ_ENABLE, 0u);
    display_write(DISPLAY_WIDTH, FB_WIDTH);
    display_write(DISPLAY_HEIGHT, FB_HEIGHT);
    display_write(DISPLAY_STRIDE, FB_STRIDE);
    display_write(DISPLAY_FORMAT, DISPLAY_FORMAT_RGB565);
    display_write(DISPLAY_CONTROL,
                  DISPLAY_CONTROL_ENABLE | DISPLAY_CONTROL_CLEAR);
}

static void wait_for_scanout(void) {
    uint32_t timeout = TIMEOUT_LOOPS;
    uint32_t start = display_read(DISPLAY_FRAME_COUNT);
    while ((display_read(DISPLAY_FRAME_COUNT) - start) < 2u && --timeout) {}
    if (!timeout)
        fail("display frame timeout");
    if (display_read(DISPLAY_STATUS) &
        (DISPLAY_STATUS_UNDERFLOW | DISPLAY_STATUS_ERROR))
        fail("display startup error");
}

static void initialise_source(void) {
    volatile uint16_t *source = (volatile uint16_t *)ASSET_BASE;
    uint32_t pixels = FB_ACTIVE_BYTES / sizeof(uint16_t);
    uint32_t i;
    bsp_printf("Preparing 720p RGB565 source pattern ..\r\n");
    for (i = 0u; i < pixels; ++i)
        source[i] = (uint16_t)(0x5000u | (i & 0x0fffu));
    __asm__ volatile ("fence rw,rw" ::: "memory");
    bsp_printf("Source pattern: READY\r\n");
}

static void cpu_fill(volatile uint16_t *dst, uint32_t pixels,
                     uint32_t repeats, uint16_t color) {
    uint32_t repeat, i;
    for (repeat = 0u; repeat < repeats; ++repeat)
        for (i = 0u; i < pixels; ++i)
            dst[i] = color;
    __asm__ volatile ("fence rw,rw" ::: "memory");
}

static void cpu_copy(volatile uint16_t *dst, volatile const uint16_t *src,
                     uint32_t pixels, uint32_t repeats) {
    uint32_t repeat, i;
    for (repeat = 0u; repeat < repeats; ++repeat)
        for (i = 0u; i < pixels; ++i)
            dst[i] = src[i];
    __asm__ volatile ("fence rw,rw" ::: "memory");
}

static void verify_fill(volatile uint16_t *dst, uint32_t pixels,
                        uint16_t expected) {
    uint32_t indices[3] = {0u, pixels / 2u, pixels - 1u};
    uint32_t i;
    for (i = 0u; i < 3u; ++i) {
        data_cache_invalidate_address(&dst[indices[i]]);
        if (dst[indices[i]] != expected)
            fail("fill readback mismatch");
    }
}

static void verify_copy(volatile uint16_t *dst, uint32_t pixels) {
    volatile const uint16_t *src = (volatile const uint16_t *)ASSET_BASE;
    uint32_t indices[3] = {0u, pixels / 2u, pixels - 1u};
    uint32_t i;
    for (i = 0u; i < 3u; ++i) {
        data_cache_invalidate_address((void *)&dst[indices[i]]);
        data_cache_invalidate_address((void *)&src[indices[i]]);
        if (dst[indices[i]] != src[indices[i]])
            fail("copy readback mismatch");
    }
}

static uint64_t elapsed_ticks(uint64_t start, uint64_t end) {
    uint64_t delta = end - start;
    if (delta == 0u)
        fail("invalid benchmark duration");
    return delta;
}

static uint64_t run_cpu_fill(const benchmark_case_t *test) {
    volatile uint16_t *dst = (volatile uint16_t *)SCRATCH_BASE;
    uint32_t pixels = test->width * test->height;
    uint64_t start = clint_getTime(BSP_CLINT);
    cpu_fill(dst, pixels, test->repeats, 0x1234u);
    uint64_t end = clint_getTime(BSP_CLINT);
    verify_fill(dst, pixels, 0x1234u);
    return elapsed_ticks(start, end);
}

static uint64_t run_hw_fill(const benchmark_case_t *test) {
    uint32_t repeat;
    uint64_t start = clint_getTime(BSP_CLINT);
    for (repeat = 0u; repeat < test->repeats; ++repeat)
        bitblt_fill_once(SCRATCH_BASE, test->width, test->height,
                         0x4321u);
    uint64_t end = clint_getTime(BSP_CLINT);
    verify_fill((volatile uint16_t *)SCRATCH_BASE,
                test->width * test->height, 0x4321u);
    return elapsed_ticks(start, end);
}

static uint64_t run_cpu_copy(const benchmark_case_t *test) {
    volatile uint16_t *dst = (volatile uint16_t *)SCRATCH_BASE;
    volatile const uint16_t *src = (volatile const uint16_t *)ASSET_BASE;
    uint32_t pixels = test->width * test->height;
    uint64_t start = clint_getTime(BSP_CLINT);
    cpu_copy(dst, src, pixels, test->repeats);
    uint64_t end = clint_getTime(BSP_CLINT);
    verify_copy(dst, pixels);
    return elapsed_ticks(start, end);
}

static uint64_t run_hw_copy(const benchmark_case_t *test) {
    uint32_t repeat;
    uint64_t start = clint_getTime(BSP_CLINT);
    for (repeat = 0u; repeat < test->repeats; ++repeat)
        bitblt_copy_once(SCRATCH_BASE, ASSET_BASE,
                         test->width, test->height);
    uint64_t end = clint_getTime(BSP_CLINT);
    verify_copy((volatile uint16_t *)SCRATCH_BASE,
                test->width * test->height);
    return elapsed_ticks(start, end);
}

static void print_metric(const char *name, uint64_t ticks,
                         uint32_t bytes, uint32_t repeats) {
    uint64_t total_bytes = (uint64_t)bytes * repeats;
    uint64_t rate100 = total_bytes * BSP_CLINT_HZ * 100u /
                       ((uint64_t)ticks * 1024u * 1024u);
    uint32_t average_us = (uint32_t)
        (ticks / (BSP_CLINT_HZ / 1000000u) / repeats);
    bsp_printf("  %s: %d us/op, %d.", name, average_us,
               (uint32_t)(rate100 / 100u));
    if ((rate100 % 100u) < 10u)
        bsp_printf("0");
    bsp_printf("%d MiB/s payload\r\n", (uint32_t)(rate100 % 100u));
}

static void print_speedup(const char *name, uint64_t cpu_ticks,
                          uint64_t hw_ticks) {
    uint64_t speedup100 = cpu_ticks * 100u / hw_ticks;
    bsp_printf("  %s speedup: %d.", name,
               (uint32_t)(speedup100 / 100u));
    if ((speedup100 % 100u) < 10u)
        bsp_printf("0");
    bsp_printf("%dx\r\n", (uint32_t)(speedup100 % 100u));
}

static void run_case(const benchmark_case_t *test) {
    benchmark_result_t result;
    uint32_t bytes = test->width * test->height * FB_BYTES_PER_PIXEL;

    bsp_printf("CASE %dx%d, repeats=%d\r\n",
               test->width, test->height, test->repeats);
    bsp_printf("  running CPU Fill ..\r\n");
    result.cpu_fill_ticks = run_cpu_fill(test);
    bsp_printf("  running HW Fill ..\r\n");
    result.hw_fill_ticks = run_hw_fill(test);
    bsp_printf("  running CPU Copy ..\r\n");
    result.cpu_copy_ticks = run_cpu_copy(test);
    bsp_printf("  running HW Copy ..\r\n");
    result.hw_copy_ticks = run_hw_copy(test);

    print_metric("CPU Fill", result.cpu_fill_ticks, bytes, test->repeats);
    print_metric("HW  Fill", result.hw_fill_ticks, bytes, test->repeats);
    print_speedup("Fill", result.cpu_fill_ticks, result.hw_fill_ticks);
    print_metric("CPU Copy", result.cpu_copy_ticks, bytes, test->repeats);
    print_metric("HW  Copy", result.hw_copy_ticks, bytes, test->repeats);
    print_speedup("Copy", result.cpu_copy_ticks, result.hw_copy_ticks);

    if (display_read(DISPLAY_STATUS) &
        (DISPLAY_STATUS_UNDERFLOW | DISPLAY_STATUS_ERROR))
        fail("display error during benchmark");
}

void main(void) {
    uint32_t i;
    bsp_init();
    csr_write(mtvec, trap_entry);
    bsp_printf("*** BitBlt Performance Demo ***\r\n");
    if (bitblt_read(BITBLT_VERSION) != BITBLT_VERSION_V2_0)
        fail("BitBlt version");
    if (display_read(DISPLAY_VERSION) != DISPLAY_VERSION_V3_0)
        fail("display version");

    display_write(DISPLAY_IRQ_ENABLE, 0u);
    display_write(DISPLAY_CONTROL, DISPLAY_CONTROL_CLEAR);
    draw_front_buffer();
    wait_for_scanout();
    initialise_source();

    bsp_printf("CLINT=%d Hz; throughput uses destination payload bytes\r\n",
               BSP_CLINT_HZ);
    for (i = 0u; i < ARRAY_SIZE(cases); ++i)
        run_case(&cases[i]);

    bsp_printf("Display frames=%d, underflows=%d\r\n",
               display_read(DISPLAY_FRAME_COUNT),
               display_read(DISPLAY_UNDERFLOW_COUNT));
    if (display_read(DISPLAY_UNDERFLOW_COUNT) != 0u)
        fail("display underflow count");
    bsp_printf("*** BITBLT PERFORMANCE DEMO PASSED ***\r\n");
    while (1) {}
}
