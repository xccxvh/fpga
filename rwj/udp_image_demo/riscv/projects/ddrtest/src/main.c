/* ===========================================================================
 *  DDR 测试：确认 RISC-V 能可靠读写 DDR，并测出真实可用容量
 *
 *  背景：
 *    SoC 的 DDR 译码窗口是 0x1000 - 0xe0000fff（3.5GB），但那只是地址译码范围，
 *    DDR3 控制器实际是 ADDR_WIDTH=28 → 2^28 = 256MB。
 *    超出真实容量的地址会回卷，可能踩到低地址（包括程序自己）。
 *
 *  安全措施：
 *    所有写入都在 0x00100000 (1MB) 以上，程序自己占的是 0x1000-0x26f0。
 *    别名检测靠"先全部写、再全部读回"——如果高地址回卷覆盖了低地址，
 *    低地址的签名就对不上，能直接暴露出来。
 *
 *  三个测试：
 *    1. 容量/别名探测   1MB 步长扫到 256MB
 *    2. 位模式          连续 1 / 连续 0 / 交替，抓坏位和位间耦合
 *    3. 地址写自身      抓地址译码错误
 * ===========================================================================
 */
#include <stdint.h>
#include "bsp.h"

#define DDR_LO   0x00100000u          /* 1MB，安全起点 */
#define DDR_HI   0x10000000u          /* 256MB，控制器标称容量 */
#define STRIDE   0x00100000u          /* 1MB 步长 → 255 个探针 */

/* 每个地址写入和它自己相关的签名，这样地址译码错了也能看出来 */
#define SIG(a)   ((a) ^ 0xA5A5A5A5u)

#define PAT_BASE 0x00200000u          /* 位模式测试区 */
#define PAT_WORDS 0x4000u             /* 64KB / 4 */

static u32 g_fails = 0;

static void report(const char *name, u32 ok) {
    if (ok)
        bsp_printf("  [OK]   %s\r\n", name);
    else {
        bsp_printf("  [FAIL] %s\r\n", name);
        g_fails++;
    }
}

/* ------------------------------------------------------------------------
 * 测试 1：容量 / 别名探测
 * ------------------------------------------------------------------------ */
static u32 test_range(void) {
    u32 n = 0, fails = 0, first = 0;

    bsp_printf("\r\n[1] 容量探测  0x%x - 0x%x  步长 1MB\r\n", DDR_LO, DDR_HI);

    for (u32 a = DDR_LO; a < DDR_HI; a += STRIDE) {
        *(volatile u32 *)a = SIG(a);
        n++;
    }
    bsp_printf("    已写 %d 个探针，回读校验中...\r\n", n);

    for (u32 a = DDR_LO; a < DDR_HI; a += STRIDE) {
        if (*(volatile u32 *)a != SIG(a)) {
            if (fails == 0) first = a;
            fails++;
        }
    }

    if (fails == 0) {
        bsp_printf("    %d 个探针全部正确 → 0x%x 以下都可用\r\n", n, DDR_HI);
        return 1;
    }

    bsp_printf("    %d / %d 个探针错误，首个错误地址 0x%x\r\n", fails, n, first);
    bsp_printf("    → 说明该地址已回卷（超出真实容量）\r\n");
    return 0;
}

/* ------------------------------------------------------------------------
 * 测试 2：位模式
 * ------------------------------------------------------------------------ */
static u32 test_bit_patterns(void) {
    volatile u32 *p = (volatile u32 *)PAT_BASE;
    u32 bad_w1 = 0, bad_w0 = 0, bad_alt = 0;

    bsp_printf("\r\n[2] 位模式测试 @ 0x%x\r\n", PAT_BASE);

    /* 连续 1：每次只有一位是 1 */
    for (int b = 0; b < 32; b++) {
        p[b] = 1u << b;
    }
    for (int b = 0; b < 32; b++) {
        if (p[b] != (1u << b)) bad_w1++;
    }

    /* 连续 0：每次只有一位是 0 */
    for (int b = 0; b < 32; b++) {
        p[32 + b] = ~(1u << b);
    }
    for (int b = 0; b < 32; b++) {
        if (p[32 + b] != ~(1u << b)) bad_w0++;
    }

    /* 交替模式 */
    const u32 alt[4] = {0x55555555u, 0xAAAAAAAAu, 0x33333333u, 0xCCCCCCCCu};
    for (int i = 0; i < 4; i++) p[64 + i] = alt[i];
    for (int i = 0; i < 4; i++) {
        if (p[64 + i] != alt[i]) bad_alt++;
    }

    bsp_printf("    连续1 坏 %d/32   连续0 坏 %d/32   交替 坏 %d/4\r\n",
               bad_w1, bad_w0, bad_alt);
    return (bad_w1 == 0 && bad_w0 == 0 && bad_alt == 0);
}

/* ------------------------------------------------------------------------
 * 测试 3：每个地址写它自己的值，抓地址译码错误
 * ------------------------------------------------------------------------ */
static u32 test_addr_in_addr(void) {
    volatile u32 *base = (volatile u32 *)PAT_BASE;
    u32 bad = 0, first = 0;

    bsp_printf("\r\n[3] 地址写自身  %d 个字\r\n", PAT_WORDS);

    for (u32 i = 0; i < PAT_WORDS; i++) {
        base[i] = PAT_BASE + i * 4;
    }
    for (u32 i = 0; i < PAT_WORDS; i++) {
        u32 expect = PAT_BASE + i * 4;
        if (base[i] != expect) {
            if (bad == 0) first = PAT_BASE + i * 4;
            bad++;
        }
    }

    if (bad == 0) {
        bsp_printf("    全部正确\r\n");
        return 1;
    }
    bsp_printf("    错 %d 个，首个 0x%x\r\n", bad, first);
    return 0;
}

/* ------------------------------------------------------------------------ */
void main() {
    bsp_init();

    bsp_printf("\r\n");
    bsp_printf("=====================================\r\n");
    bsp_printf("*** DDR 测试 ***\r\n");
    bsp_printf("控制器标称 256MB (ADDR_WIDTH=28)\r\n");
    bsp_printf("=====================================\r\n");

    u32 ok1 = test_range();
    u32 ok2 = test_bit_patterns();
    u32 ok3 = test_addr_in_addr();

    bsp_printf("\r\n-------------------------------------\r\n");
    bsp_printf("容量探测 : %s\r\n", ok1 ? "通过" : "失败");
    bsp_printf("位模式   : %s\r\n", ok2 ? "通过" : "失败");
    bsp_printf("地址译码 : %s\r\n", ok3 ? "通过" : "失败");
    if (g_fails == 0)
        bsp_printf("*** DDR 全部通过 ***\r\n");
    else
        bsp_printf("*** 有 %d 项失败 ***\r\n", g_fails);
    bsp_printf("-------------------------------------\r\n");

    while (1) { bsp_uDelay(1000000); }
}

/* trap.S 需要这个符号 */
#include "riscv.h"
void trap() {
    int32_t mcause = csr_read(mcause);
    bsp_printf("\r\n*** TRAP! mcause=0x%x ***\r\n", mcause);
    bsp_printf("（如果测试中途崩了，多半是写到了不存在的 DDR 地址上）\r\n");
    while (1) {}
}
