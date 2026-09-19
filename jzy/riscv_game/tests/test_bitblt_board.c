/*
 * M2 BitBlt 板端 smoke test —— Ti60F225 / Sapphire RISC-V (RV32)
 *
 * M2 第一阶段只验证真实硬件上的最小闭环，顺序固定：
 *
 *   T0  CLINT tick source   —— fail-fast 门，不通就绝不碰 BitBlt MMIO
 *   T1  BitBlt VERSION      —— MMIO 存活门，读回值不对就不下发 FILL
 *   T2  bitblt_fill 写 Scratch DDR，CPU 逐像素回读
 *   T3  矩形四周的 guard sentinel 未被改写
 *
 * 本版刻意【不包含】：display_api、HDMI、双缓冲、Copy、游戏逻辑与输入。
 * 这些等 T0~T3 在真板上稳定之后再逐步加。
 *
 * 板端与 host 的分工：
 *   tests/test_bitblt_api.c          host 侧驱动/适配层测试（注入假时钟）
 *   tests/test_render_board.c        M1 CPU 渲染层板端 smoke（本文件不动它）
 *   本文件                            M2 真硬件 smoke，只能用 bsp_printf 输出
 *
 * 刻意的取舍：
 *   - 不用 assert 判定。板上 assert 失败只会挂住，什么都看不到；
 *     这里全部显式打印并统计失败数。
 *   - 不开 ASan/UBSan，板上没有这些运行时。
 *   - BSP/CLINT 的接线只存在于本文件（board boundary）。
 *     driver/bitblt_api.c 仍然与 bsp.h 无关，host 测试继续注入假时钟。
 */

#include <stdint.h>

#include "bsp.h"

#include "bitblt_api.h"
#include "bitblt_platform.h"

/*
 * 板端测试【只读】引用 B 的权威寄存器定义，用来做 VERSION 这类硬件契约检查。
 *
 * 引用范围是刻意划分的：
 *   生产代码（render/ 与 driver/）  只允许 driver/bitblt_api.c 碰寄存器
 *   板级验证代码（本文件）          允许只读引用，用于验证硬件契约
 *
 * 这不是第二份真相源 —— 用的就是 driver/bitblt_api.c 用的那一份头文件，
 * 没有复制、没有另抄偏移。为读一个版本号去封装 bitblt_get_version() 反而
 * 不如直接读寄存器干净，但那只属于验证路径。
 * make check-hw-isolation 覆盖的是生产代码那一侧。
 */
#include "bitblt_regs.h"

#include "framebuffer_layout.h"


/* ------------------------------------------------------------------ */
/* 预期与区域参数                                                      */
/* ------------------------------------------------------------------ */

/* 与 hw/rtl/bitblt_ctrl_axi.v 的 localparam VERSION 一致 */
#define BITBLT_EXPECTED_VERSION 0x00010003u

/*
 * 首个区域：64x64 XRGB8888。
 *
 * 硬件约束（V0.1，见 04_project/bitblt_accel/README.md）：
 *   SRC / DST / STRIDE 必须 16 字节对齐；WIDTH 必须是 4 的倍数。
 * 下面三条静态断言把它们钉死，改错常量会直接编译失败。
 *
 *   row bytes = 64 × 4 = 256 B，16 的倍数
 *   stride    = 320 B（80 像素），16 的倍数且 > 256
 *   → 每行行尾自然留下 64 B 的 padding，正好拿来放 guard
 */
#define TEST_WIDTH        64u
#define TEST_HEIGHT       64u
#define TEST_PIXEL_BYTES  4u
#define TEST_ROW_BYTES    (TEST_WIDTH * TEST_PIXEL_BYTES)   /* 256 B */
#define TEST_STRIDE       320u                              /* 80 px */
#define TEST_STRIDE_PX    (TEST_STRIDE / TEST_PIXEL_BYTES)  /* 80 px */

/* guard：区域上下各 8 行，加上每行的行尾 padding */
#define TEST_GUARD_ROWS 8u
#define TEST_TOTAL_ROWS (TEST_GUARD_ROWS * 2u + TEST_HEIGHT)

/*
 * 地址分层，别把"缓冲起点"和"区域本体"混为一谈 ——
 * fill 的目标是区域本体，不是缓冲起点，两者差着上面那 8 行 guard。
 *
 *   TEST_GUARD_BASE   缓冲起点 = 上方 guard 的第一行
 *   TEST_REGION_BASE  区域本体左上角 = fill 的 DST
 *
 * 基地址来自 B 的 framebuffer_layout.h，测试代码里不重复硬编码 Scratch 基地址。
 * 只在 Scratch 内部取一个偏移，避开偏移 0 处可能存在的历史残留。
 */
#define TEST_REGION_OFFSET 0x00010000u
#define TEST_REGION_BASE   ((uint32_t)SCRATCH_BASE + TEST_REGION_OFFSET)
#define TEST_GUARD_BASE    (TEST_REGION_BASE - TEST_GUARD_ROWS * TEST_STRIDE)

typedef char assert_test_stride_16b_aligned[(TEST_STRIDE % 16u == 0u) ? 1 : -1];
typedef char assert_test_row_bytes_16b_aligned[(TEST_ROW_BYTES % 16u == 0u) ? 1 : -1];
typedef char assert_test_width_multiple_of_4[(TEST_WIDTH % 4u == 0u) ? 1 : -1];
typedef char assert_test_region_16b_aligned[(TEST_REGION_BASE % 16u == 0u) ? 1 : -1];
typedef char assert_test_guard_base_16b_aligned[(TEST_GUARD_BASE % 16u == 0u) ? 1 : -1];

/* 三种互不相同的取值：guard 色、填充前的脏值、填充色 */
#define TEST_GUARD_COLOR 0x00ABCDEFu
#define TEST_DIRTY_COLOR 0x00000000u
#define TEST_FILL_COLOR  0x00A5C3F0u

/*
 * 超时：直接由 CLINT 频率推出来，不写魔数。
 * 100 ms 对 64x64 的 fill 是极宽松的上限；板测曾经出现过 AXI 卡死，
 * 有超时至少能把"卡死"变成"BITBLT_ETIMEOUT"。
 */
#define TEST_TIMEOUT_TICKS ((uint64_t)BSP_CLINT_HZ / 10u)

/* T0 采样次数：足够看出单调性，又不至于拖慢启动 */
#define CLINT_SAMPLES 8u

/* 每条用例最多逐条打印几条诊断，其余只计数 */
#define MAX_DIAG 8

/*
 * 输出格式约束：本 BSP 用的是 lite 版 bsp_printf
 * （bsp.h 里 ENABLE_BSP_PRINTF_FULL = 0），只认 c / s / d / x / X。
 *
 * 尤其【没有无符号的 u 转换符】：解析器在 % 之后找不到认识的字符会一直
 * 吃到字符串结尾，结果是整行剩余内容被吞掉、那个参数也不会被取走，
 * 后面所有参数整体错位。
 * 所以无符号量一律先 (int) 再按 d 打印（本文件的值都远小于 INT_MAX）。
 *
 * %X / %x 固定输出 8 位十六进制，写 %08X 只是为了让意图可读，宽度并不生效。
 * make check-board-printf 会机械地挡住不支持的格式符。
 */

/*
 * CPU 与 BitBlt 之间的内存屏障。
 *
 * 板上是 rv32 的 fence。宿主机上（tests/host_board/ 的替身跑法）没有这条
 * 指令，编译成空操作 —— 那边是同一个进程，不存在 CPU 与引擎两个观察者，
 * 语义上本来也不需要屏障。
 *
 * 不能无条件退化成空操作：真板上少了它就会读到引擎还没写完的 DDR，
 * 所以按 __riscv 分支，而不是交给编译器去无声地处理。
 */
#if defined(__riscv)
#define M2_FENCE() __asm__ volatile ("fence rw,rw" ::: "memory")
#else
#define M2_FENCE() ((void)0)
#endif


static int g_pass = 0;
static int g_fail = 0;


/* ------------------------------------------------------------------ */
/* T0 的独立入口                                                       */
/* ------------------------------------------------------------------ */

/*
 * CLINT tick source 门 —— 独立测试函数，可被未来的自动回归单独调用。
 *
 * 返回 0 = 通过；非 0 = 失败，调用方【必须立刻结束整个 smoke】。
 *
 * 为什么必须 fail-fast：
 *   driver/bitblt_api.c 在没有 tick 源时会让 wait_done() 直接返回
 *   BITBLT_ETIMEOUT（刻意不猜时钟）。若时基本身是坏的却继续跑 FILL，
 *   串口上看到的会是"硬件超时"，而真正的原因在时基 —— 排查方向会被带偏。
 *
 * 本函数只依赖 bitblt_tick_source_ready() 与 board_bitblt_ticks()，
 * 不依赖本文件其它测试的任何状态。
 */
int bitblt_board_test_clint(void);


/* ------------------------------------------------------------------ */
/* 板端时基                                                            */
/* ------------------------------------------------------------------ */

/*
 * bitblt_api.c 需要的 100 MHz tick 源。
 *
 * 直接转发 Sapphire BSP 官方实现：clint_getTime(BSP_CLINT)。
 * 它内部用 high/low 回读处理 RV32 的 32 位回绕，这里不自己拼高低位 ——
 * 自造一份回绕处理只会引入和 BSP 不一致的第二种行为。
 */
static uint64_t board_bitblt_ticks(void)
{
    return clint_getTime(BSP_CLINT);
}


static void halt_forever(void)
{
    while (1)
    {
        /* 结果已打印完，停在这里等自动回归从串口读结论 */
    }
}


/* ------------------------------------------------------------------ */
/* 判定与输出                                                          */
/* ------------------------------------------------------------------ */

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


static void print_verdict(void)
{
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
}


/* ------------------------------------------------------------------ */
/* T0: CLINT tick source（fail-fast）                                  */
/* ------------------------------------------------------------------ */

int bitblt_board_test_clint(void)
{
    static const char *name = "T0_clint_tick_source";
    uint64_t sample[CLINT_SAMPLES];
    uint64_t expected;
    uint64_t lower;
    uint64_t upper;
    uint64_t t0;
    uint64_t t1;
    uint64_t delta;
    uint32_t i;

    /*
     * 1) 时基必须已经注入。
     *    正常路径上 main() 已经调用过 bitblt_set_tick_source()，
     *    所以这里失败意味着注入被删掉或重排了 —— 那正是最该立刻停下来的情况。
     */
    if (bitblt_tick_source_ready() != 1)
    {
        test_fail(name, "tick source not injected");
        return 1;
    }

    /* 2) tick 必须单调不减，且在一串连续读里确实往前走 */
    for (i = 0u; i < CLINT_SAMPLES; ++i)
    {
        sample[i] = board_bitblt_ticks();
    }

    for (i = 1u; i < CLINT_SAMPLES; ++i)
    {
        if (sample[i] < sample[i - 1u])
        {
            bsp_printf("[FAIL] %s: tick went backwards at sample %d\r\n",
                       name, (int)i);
            ++g_fail;
            return 1;
        }
    }

    if (sample[CLINT_SAMPLES - 1u] <= sample[0])
    {
        bsp_printf("[FAIL] %s: tick did not advance over %d reads\r\n",
                   name, (int)CLINT_SAMPLES);
        ++g_fail;
        return 1;
    }

    /*
     * 3) 频率：bsp_uDelay(10000) 即 10 ms，在 100 MHz CLINT 上应当推进
     *    约 1,000,000 个 tick。
     *
     *    容差取 ±20% 是刻意的：bsp_uDelay() 是忙等循环，本身有开销，
     *    实测只会略多于 1,000,000。这里要抓的是"明显异常"
     *    （时钟不是 100 MHz、CLINT 没在计数、拿错了定时器），
     *    而不是把循环开销当成故障。
     */
    expected = (uint64_t)BSP_CLINT_HZ / 100u;
    lower = expected * 8u / 10u;
    upper = expected * 12u / 10u;

    t0 = board_bitblt_ticks();
    bsp_uDelay(10000);
    t1 = board_bitblt_ticks();

    if (t1 <= t0)
    {
        test_fail(name, "CLINT did not advance during bsp_uDelay");
        return 1;
    }

    delta = t1 - t0;

    if (delta < lower || delta > upper)
    {
        /* delta 用十六进制打原始值：频率离谱时它会超出 int，%d 会变成负数 */
        bsp_printf("[FAIL] %s: 10ms delta=0x%X ticks, expected about %d\r\n",
                   name, (int)delta, (int)expected);
        ++g_fail;
        return 1;
    }

    bsp_printf("CLINT 10ms delta = %d ticks (expected about %d)\r\n",
               (int)delta, (int)expected);
    test_pass(name);

    return 0;
}


/* ------------------------------------------------------------------ */
/* T1: VERSION 寄存器（MMIO 存活门）                                   */
/* ------------------------------------------------------------------ */

/*
 * 返回 0 = 通过；非 0 = 版本不符，调用方不再下发 FILL。
 *
 * 读 VERSION 本身已经是一次 MMIO 访问：它能正常返回就说明
 * SYSTEM_AXI_A 上确实挂着 BitBlt 响应者（烧错 bitstream 时 CPU 会直接
 * 停在这条 load 上，连软件超时都跑不起来）。版本不符说明 RTL 不是本
 * 测试针对的那一版，继续下发 FILL 没有意义，只会把结论搅浑。
 */
static int test_bitblt_version(void)
{
    static const char *name = "T1_bitblt_version";
    uint32_t version = bitblt_read(BITBLT_VERSION);

    if (version != BITBLT_EXPECTED_VERSION)
    {
        bsp_printf("[FAIL] %s expected=0x%08X actual=0x%08X\r\n",
                   name,
                   (int)BITBLT_EXPECTED_VERSION,
                   (int)version);
        ++g_fail;
        return 1;
    }

    bsp_printf("[PASS] %s (0x%08X)\r\n", name, (int)version);
    ++g_pass;

    return 0;
}


/* ------------------------------------------------------------------ */
/* 区域准备与 guard 校验                                               */
/* ------------------------------------------------------------------ */

/* 区域内 (x, y) 的像素，y 以区域本体左上角为 0 */
static volatile uint32_t *region_pixel(uint32_t x, uint32_t y)
{
    volatile uint32_t *base = (volatile uint32_t *)TEST_REGION_BASE;

    return base + y * TEST_STRIDE_PX + x;
}

/* 整块可写范围（含上下 guard 行）的起始像素 */
static volatile uint32_t *guard_base(void)
{
    return (volatile uint32_t *)TEST_GUARD_BASE;
}

/*
 * CPU 侧把整块区域铺好：
 *   - 全部先涂 guard 色（含上下 8 行 guard 和每行行尾 padding）
 *   - 区域本体再涂脏值
 *
 * 区域本体涂脏值这一步不能省：否则"回读等于填充色"可能本来就成立，
 * fill 没生效也看不出来。
 */
static void prepare_region(void)
{
    volatile uint32_t *p = guard_base();
    uint32_t row;
    uint32_t x;

    for (row = 0u; row < TEST_TOTAL_ROWS; ++row)
    {
        for (x = 0u; x < TEST_STRIDE_PX; ++x)
        {
            p[row * TEST_STRIDE_PX + x] = TEST_GUARD_COLOR;
        }
    }

    for (row = 0u; row < TEST_HEIGHT; ++row)
    {
        for (x = 0u; x < TEST_WIDTH; ++x)
        {
            *region_pixel(x, row) = TEST_DIRTY_COLOR;
        }
    }

    M2_FENCE();
}

/*
 * 统计 guard 区被改写的地方。
 *
 * 覆盖三处，缺一不可：
 *   1. 区域上方 TEST_GUARD_ROWS 行 —— 抓向上越界
 *   2. 区域下方 TEST_GUARD_ROWS 行 —— 抓向下越界 / stride 算错整行偏移
 *   3. 每一行 [TEST_WIDTH, TEST_STRIDE_PX) 的 padding —— 抓"按 stride 铺满"
 *
 * 返回不符的像素个数；最多逐条打印 MAX_DIAG 行。
 */
static int guard_violations(const char *name)
{
    volatile uint32_t *p = guard_base();
    uint32_t row;
    uint32_t x;
    uint32_t got;
    int bad = 0;
    int printed = 0;

    /* 1) 上方 guard 行 */
    for (row = 0u; row < TEST_GUARD_ROWS; ++row)
    {
        for (x = 0u; x < TEST_STRIDE_PX; ++x)
        {
            got = p[row * TEST_STRIDE_PX + x];
            if (got != TEST_GUARD_COLOR)
            {
                if (printed < MAX_DIAG)
                {
                    bsp_printf("[FAIL] %s above y=-%d x=%d expected=0x%08X actual=0x%08X\r\n",
                               name, (int)(TEST_GUARD_ROWS - row), (int)x,
                               (int)TEST_GUARD_COLOR, (int)got);
                    ++printed;
                }
                ++bad;
            }
        }
    }

    /* 2) 下方 guard 行 */
    for (row = 0u; row < TEST_GUARD_ROWS; ++row)
    {
        uint32_t full = TEST_GUARD_ROWS + TEST_HEIGHT + row;

        for (x = 0u; x < TEST_STRIDE_PX; ++x)
        {
            got = p[full * TEST_STRIDE_PX + x];
            if (got != TEST_GUARD_COLOR)
            {
                if (printed < MAX_DIAG)
                {
                    bsp_printf("[FAIL] %s below y=%d x=%d expected=0x%08X actual=0x%08X\r\n",
                               name, (int)(TEST_HEIGHT + row), (int)x,
                               (int)TEST_GUARD_COLOR, (int)got);
                    ++printed;
                }
                ++bad;
            }
        }
    }

    /* 3) 每行行尾 padding */
    for (row = 0u; row < TEST_HEIGHT; ++row)
    {
        for (x = TEST_WIDTH; x < TEST_STRIDE_PX; ++x)
        {
            got = *region_pixel(x, row);
            if (got != TEST_GUARD_COLOR)
            {
                if (printed < MAX_DIAG)
                {
                    bsp_printf("[FAIL] %s pad y=%d x=%d expected=0x%08X actual=0x%08X\r\n",
                               name, (int)row, (int)x,
                               (int)TEST_GUARD_COLOR, (int)got);
                    ++printed;
                }
                ++bad;
            }
        }
    }

    if (printed == MAX_DIAG && bad > printed)
    {
        bsp_printf("[FAIL] %s 另有 %d 处 guard 不符未逐条列出\r\n",
                   name, bad - printed);
    }

    return bad;
}


/* ------------------------------------------------------------------ */
/* T2: bitblt_fill 写 Scratch DDR，CPU 回读                            */
/* ------------------------------------------------------------------ */

static void test_bitblt_fill_readback(void)
{
    static const char *name = "T2_bitblt_fill_readback";
    bitblt_result_t result;
    uint32_t x;
    uint32_t y;
    uint32_t got;
    int bad = 0;
    int printed = 0;

    /*
     * 下发前先确认 CPU 自己写的 guard 确实落到 DDR 了。
     * 这一步不过就说明 CPU 侧 DDR 访问有问题，后面的回读结论没有意义。
     */
    if (guard_violations(name) != 0)
    {
        test_fail(name, "guard already broken before fill (CPU DDR writes)");
        return;
    }

    result = bitblt_fill(TEST_REGION_BASE, TEST_WIDTH, TEST_HEIGHT,
                         TEST_STRIDE, TEST_FILL_COLOR, TEST_TIMEOUT_TICKS);

    if (result != BITBLT_OK)
    {
        bsp_printf("[FAIL] %s result=%d status=0x%08X\r\n",
                   name, (int)result, (int)bitblt_last_status());
        ++g_fail;
        return;
    }

    /* 引擎写完 DDR 后 CPU 再读，中间必须有一次 fence */
    M2_FENCE();

    for (y = 0u; y < TEST_HEIGHT; ++y)
    {
        for (x = 0u; x < TEST_WIDTH; ++x)
        {
            got = *region_pixel(x, y);
            if (got != TEST_FILL_COLOR)
            {
                if (printed < MAX_DIAG)
                {
                    bsp_printf("[FAIL] %s x=%d y=%d expected=0x%08X actual=0x%08X\r\n",
                               name, (int)x, (int)y,
                               (int)TEST_FILL_COLOR, (int)got);
                    ++printed;
                }
                ++bad;
            }
        }
    }

    if (bad != 0)
    {
        bsp_printf("[FAIL] %s %dx%d 中有 %d 个像素不符（status=0x%08X）\r\n",
                   name, (int)TEST_WIDTH, (int)TEST_HEIGHT, bad,
                   (int)bitblt_last_status());

        if (bad > printed)
        {
            bsp_printf("[FAIL] %s 另有 %d 处未逐条列出\r\n", name, bad - printed);
        }

        ++g_fail;
        return;
    }

    test_pass(name);
}


/* ------------------------------------------------------------------ */
/* T3: guard sentinel                                                  */
/* ------------------------------------------------------------------ */

static void test_guard_sentinel(void)
{
    static const char *name = "T3_guard_sentinel";
    int bad = guard_violations(name);

    if (bad != 0)
    {
        bsp_printf("[FAIL] %s %d 个 guard 像素被改写\r\n", name, bad);
        ++g_fail;
        return;
    }

    test_pass(name);
}


/* ------------------------------------------------------------------ */

void main(void)
{
    bsp_init();

    bsp_printf("\r\n=== M2 BitBlt Board Smoke Test ===\r\n");
    bsp_printf("region %dx%d XRGB8888, row %d B, stride %d B, scratch+0x%X\r\n",
               (int)TEST_WIDTH, (int)TEST_HEIGHT,
               (int)TEST_ROW_BYTES, (int)TEST_STRIDE,
               (int)TEST_REGION_OFFSET);
    bsp_printf("guard: %d rows above/below, %d B padding each row\r\n",
               (int)TEST_GUARD_ROWS,
               (int)(TEST_STRIDE - TEST_ROW_BYTES));
    bsp_printf("timeout %d ticks (100 ms @ %d Hz)\r\n\r\n",
               (int)TEST_TIMEOUT_TICKS, (int)BSP_CLINT_HZ);

    /*
     * 板端时基必须在任何 bitblt_* 调用之前接上。
     * driver/bitblt_api.c 不知道 BSP 的存在，注入点只有这里。
     */
    bitblt_set_tick_source(board_bitblt_ticks);

    /*
     * T0 fail-fast：时基不通就直接出结论并停机，
     * 不读任何 BitBlt 寄存器、不下发任何命令。
     */
    if (bitblt_board_test_clint() != 0)
    {
        bsp_printf("\r\n[FATAL] CLINT tick source unusable; "
                   "BitBlt MMIO was NOT touched\r\n");
        print_verdict();
        halt_forever();
    }

    /* T1 同样是门：版本不对就不下发 FILL */
    if (test_bitblt_version() != 0)
    {
        bsp_printf("\r\n[FATAL] unexpected BitBlt version; "
                   "fill tests were NOT run\r\n");
        print_verdict();
        halt_forever();
    }

    prepare_region();

    test_bitblt_fill_readback();
    test_guard_sentinel();

    print_verdict();
    halt_forever();
}
