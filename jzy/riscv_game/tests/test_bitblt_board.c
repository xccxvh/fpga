/*
 * M2 BitBlt board smoke test -- Ti60F225 / Sapphire RV32.
 *
 * BSP/CLINT integration belongs here at the board boundary.  The portable
 * driver remains independent of bsp.h, and host tests continue to inject
 * fake_ticks.
 */

#include <stdint.h>

#include "bsp.h"

#include "bitblt_api.h"
#include "framebuffer_layout.h"
#include "bitblt_platform.h"

#define TEST_WIDTH          80u
#define TEST_HEIGHT         3u
#define TEST_SRC_STRIDE     384u
#define TEST_DST_STRIDE     416u
#define TEST_SRC_ADDR       ((uint32_t)SCRATCH_BASE)
#define TEST_DST_ADDR       ((uint32_t)SCRATCH_BASE + 0x00010000u)
#define TEST_TIMEOUT_TICKS  10000000ULL
#define FILL_COLOR          0x00A5C3F0u

static int g_pass;
static int g_fail;

/* Thin board-only adapter.  clint_getTime() already handles RV32 rollover. */
static uint64_t board_bitblt_ticks(void)
{
    return clint_getTime(BSP_CLINT);
}

static void test_pass(const char *name)
{
    ++g_pass;
    bsp_printf("[PASS] %s\r\n", name);
}

static void test_fail(const char *name, const char *reason)
{
    ++g_fail;
    bsp_printf("[FAIL] %s: %s\r\n", name, reason);
}

static void test_clint_tick_source(void)
{
    const char *name = "T0_clint_tick_source";
    uint64_t t0;
    uint64_t t1;
    uint64_t delta;
    uint64_t expected = (uint64_t)BSP_CLINT_HZ / 100u; /* 10 ms */
    uint64_t lower = expected * 8u / 10u;
    uint64_t upper = expected * 12u / 10u;

    if (bitblt_tick_source_ready() != 1)
    {
        test_fail(name, "bitblt_tick_source_ready() != 1");
        return;
    }

    t0 = board_bitblt_ticks();
    bsp_uDelay(10000);
    t1 = board_bitblt_ticks();

    if (t1 <= t0)
    {
        test_fail(name, "CLINT did not advance");
        return;
    }

    delta = t1 - t0;
    if (delta < lower || delta > upper)
    {
        bsp_printf("[FAIL] %s: delta=%d expected_about=%d\r\n",
                   name, (int)delta, (int)expected);
        ++g_fail;
        return;
    }

    bsp_printf("CLINT 10ms delta = %d ticks (expected about %d)\r\n",
               (int)delta, (int)expected);
    test_pass(name);
}

static void test_bitblt_fill(void)
{
    const char *name = "T1_bitblt_fill";
    volatile uint32_t *dst = (volatile uint32_t *)TEST_DST_ADDR;
    bitblt_result_t result;
    uint32_t x;
    uint32_t y;

    for (y = 0u; y < TEST_HEIGHT; ++y)
    {
        for (x = 0u; x < TEST_WIDTH; ++x)
        {
            dst[y * (TEST_DST_STRIDE / 4u) + x] = 0u;
        }
    }
    __asm__ volatile ("fence rw,rw" ::: "memory");

    bsp_printf("Starting T1 bitblt_fill\r\n");
    result = bitblt_fill(TEST_DST_ADDR, TEST_WIDTH, TEST_HEIGHT,
                         TEST_DST_STRIDE, FILL_COLOR, TEST_TIMEOUT_TICKS);
    bsp_printf("T1 bitblt_fill returned %d status=0x%08X\r\n",
               (int)result, bitblt_last_status());
    if (result != BITBLT_OK)
    {
        bsp_printf("[FAIL] %s: result=%d status=0x%08X\r\n",
                   name, (int)result, bitblt_last_status());
        ++g_fail;
        return;
    }

    __asm__ volatile ("fence rw,rw" ::: "memory");
    for (y = 0u; y < TEST_HEIGHT; ++y)
    {
        for (x = 0u; x < TEST_WIDTH; ++x)
        {
            if (dst[y * (TEST_DST_STRIDE / 4u) + x] != FILL_COLOR)
            {
                test_fail(name, "DDR fill readback mismatch");
                return;
            }
        }
    }

    test_pass(name);
}

static void test_bitblt_copy(void)
{
    const char *name = "T2_bitblt_copy";
    volatile uint32_t *src = (volatile uint32_t *)TEST_SRC_ADDR;
    volatile uint32_t *dst = (volatile uint32_t *)TEST_DST_ADDR;
    bitblt_result_t result;
    uint32_t expected;
    uint32_t x;
    uint32_t y;

    for (y = 0u; y < TEST_HEIGHT; ++y)
    {
        for (x = 0u; x < TEST_WIDTH; ++x)
        {
            src[y * (TEST_SRC_STRIDE / 4u) + x] =
                0x5A000000u | (y << 16) | x;
            dst[y * (TEST_DST_STRIDE / 4u) + x] = 0u;
        }
    }
    __asm__ volatile ("fence rw,rw" ::: "memory");

    bsp_printf("Starting T2 bitblt_copy\r\n");
    result = bitblt_copy(TEST_SRC_ADDR, TEST_DST_ADDR,
                         TEST_WIDTH, TEST_HEIGHT,
                         TEST_SRC_STRIDE, TEST_DST_STRIDE,
                         TEST_TIMEOUT_TICKS);
    bsp_printf("T2 bitblt_copy returned %d status=0x%08X\r\n",
               (int)result, bitblt_last_status());
    if (result != BITBLT_OK)
    {
        bsp_printf("[FAIL] %s: result=%d status=0x%08X\r\n",
                   name, (int)result, bitblt_last_status());
        ++g_fail;
        return;
    }

    __asm__ volatile ("fence rw,rw" ::: "memory");
    for (y = 0u; y < TEST_HEIGHT; ++y)
    {
        for (x = 0u; x < TEST_WIDTH; ++x)
        {
            expected = 0x5A000000u | (y << 16) | x;
            if (dst[y * (TEST_DST_STRIDE / 4u) + x] != expected)
            {
                test_fail(name, "DDR copy readback mismatch");
                return;
            }
        }
    }

    test_pass(name);
}

void main(void)
{
    bsp_init();
    bsp_printf("\r\n=== M2 BitBlt Board Smoke Test ===\r\n");

    /* Must happen before every path that can call bitblt_fill/copy. */
    bitblt_set_tick_source(board_bitblt_ticks);

    test_clint_tick_source();
    test_bitblt_fill();
    test_bitblt_copy();

    bsp_printf("\r\nPASS = %d\r\n", g_pass);
    bsp_printf("FAIL = %d\r\n", g_fail);
    if (g_fail == 0)
    {
        bsp_printf("M2 BITBLT BOARD TEST PASSED\r\n");
    }
    else
    {
        bsp_printf("M2 BITBLT BOARD TEST FAILED\r\n");
    }

    while (1)
    {
        /* Keep the UART verdict available for the regression runner. */
    }
}
