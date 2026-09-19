/*
 * 板端 smoke 在宿主机上的替身环境。
 *
 * 提供三样东西，让 tests/test_bitblt_board.c 能原样编译并运行：
 *   1. bsp.h 的替身实现（bsp_init / bsp_printf / bsp_uDelay / clint_getTime）
 *   2. 一片映射在真实地址上的假内存，让权威头文件里的绝对地址访问能工作
 *   3. 一个 BitBlt 行为模型，替掉 driver/bitblt_api.c 的真硬件分支
 *
 * 【它验证什么】板端测试自己的判定逻辑：T0 的 fail-fast 分支、
 * guard 的算术、回读比对、PASS/FAIL 计数。
 *
 * 【它不验证什么】真硬件行为。模型是照着约定写的，模型和 RTL 不一致时
 * 这里照样通过，真板上才暴露。所以它是"上板前的自查"，不是替代品。
 *
 * M2_STUB_FAULT 环境变量可以注入故障，用来确认测试真的能拦住错 ——
 * 一个从不失败的测试等于没有测试。
 */

#define _DEFAULT_SOURCE

#include <errno.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

#include "bsp.h"

#include "bitblt_api.h"
#include "bitblt_platform.h"
#include "framebuffer_format.h"
#include "protocol_frozen.h"

/*
 * 只为拿 BITBLT_BASE / BITBLT_VERSION / SCRATCH_BASE 来布置替身内存，
 * 以及从 protocol_frozen.h 取当前冻结的期望版本。
 * 用的就是板端那一份权威头文件，不另抄一份地址常量。
 */
#include "bitblt_regs.h"
#include "framebuffer_layout.h"


/* ------------------------------------------------------------------ */
/* 故障注入                                                            */
/* ------------------------------------------------------------------ */

enum stub_fault
{
    FAULT_NONE = 0,
    FAULT_NOHOOK,      /* bitblt_set_tick_source() 静默失效 -> T0 未注入分支 */
    FAULT_FREEZE,      /* CLINT 不走字                          -> T0 单调性 */
    FAULT_SLOWCLOCK,   /* uDelay 只推进一半                     -> T0 频率 */
    FAULT_VERSION,     /* VERSION 寄存器不是预期值              -> T1 门 */
    FAULT_PAD,         /* fill 铺满 stride，越写行尾 padding    -> T3 padding */
    FAULT_OVERRUN,     /* fill 多写一行，越写下方 guard        -> T3 下方 */
    FAULT_SHORT        /* fill 少写一行                        -> T2 回读 */
};

static const struct
{
    const char   *name;
    enum stub_fault value;
} FAULTS[] = {
    { "nohook",    FAULT_NOHOOK    },
    { "freeze",    FAULT_FREEZE    },
    { "slowclock", FAULT_SLOWCLOCK },
    { "version",   FAULT_VERSION   },
    { "pad",       FAULT_PAD       },
    { "overrun",   FAULT_OVERRUN   },
    { "short",     FAULT_SHORT     }
};

static enum stub_fault g_fault = FAULT_NONE;


/* ------------------------------------------------------------------ */
/* 状态                                                                */
/* ------------------------------------------------------------------ */

static uint64_t g_ticks = 0;
static uint64_t (*g_now_ticks)(void) = 0;
static uint32_t g_last_status = 0;


/*
 * 替身模型的像素宽度 —— 必须与当前位流的像素格式一致。
 * 模型按 32 位写、被测代码按 16 位读，会让"注错却抓不到"，
 * 那比没有模型更危险。
 */
#define TEST_MODEL_PIXEL_BYTES FMT_BYTES_PER_PIXEL

#if RENDER_PIXEL_FORMAT_RGB565
typedef uint16_t stub_pixel_t;
#else
typedef uint32_t stub_pixel_t;
#endif

typedef char assert_stub_pixel_type_matches[
    sizeof(stub_pixel_t) == TEST_MODEL_PIXEL_BYTES ? 1 : -1];


/* ------------------------------------------------------------------ */
/* 假内存                                                              */
/* ------------------------------------------------------------------ */

#ifndef MAP_FIXED_NOREPLACE
#define MAP_FIXED_NOREPLACE 0x100000
#endif

static void stub_map(uintptr_t addr, size_t len, const char *what)
{
    void *p = mmap((void *)addr, len, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);

    if (p != (void *)addr)
    {
        fprintf(stderr, "stub: mmap %s @ 0x%lX (%lu B) failed: %s\n",
                what, (unsigned long)addr, (unsigned long)len,
                strerror(errno));
        exit(2);
    }
}


/* ------------------------------------------------------------------ */
/* bsp.h 的替身                                                        */
/* ------------------------------------------------------------------ */

void bsp_init(void)
{
    const char *fault = getenv("M2_STUB_FAULT");
    size_t i;

    /* 不缓冲：板端程序跑完停在 while(1)，替身要靠闹钟收尾，
       输出必须先落到 pipe 里，不能留在 stdio 缓冲区。 */
    setvbuf(stdout, 0, _IONBF, 0);

    if (fault != 0 && *fault != '\0')
    {
        for (i = 0u; i < sizeof(FAULTS) / sizeof(FAULTS[0]); ++i)
        {
            if (strcmp(fault, FAULTS[i].name) == 0)
            {
                g_fault = FAULTS[i].value;
                break;
            }
        }
        if (i == sizeof(FAULTS) / sizeof(FAULTS[0]))
        {
            fprintf(stderr, "stub: unknown M2_STUB_FAULT=%s\n", fault);
            exit(2);
        }
    }

    stub_map((uintptr_t)SCRATCH_BASE, (size_t)SCRATCH_SIZE, "scratch");
    stub_map((uintptr_t)BITBLT_BASE, 0x1000u, "bitblt regs");

    /*
     * 正常路径回显当前联合工程冻结的 RGB565 版本；
     * 注错时回一个不同的值（用旧 XRGB8888 版本号，正好模拟
     * "板上烧的还是老位流"这个真实场景）。
     */
    *(volatile uint32_t *)(uintptr_t)(BITBLT_BASE + BITBLT_VERSION) =
        (g_fault == FAULT_VERSION)
            ? BITBLT_VERSION_V0_4
            : PROTO_BITBLT_VERSION_RGB565;
}


/*
 * 复刻 BSP lite 版 bsp_printf 的解析器（bsp.h 里 ENABLE_BSP_PRINTF_FULL = 0）。
 *
 * 只认 c / s / d / x / X；% 之后的其它字符一律忽略着往后找。
 * 找不到就吃掉整行剩余内容，并且【不取走对应参数】——
 * 这正是它在真板上的可观测行为，在这里复刻出来，
 * 好让格式符写错时在宿主机上就能看见，而不是等上板。
 */
void bsp_printf(const char *format, ...)
{
    va_list ap;
    size_t i;
    char c;

    va_start(ap, format);

    for (i = 0u; format[i] != '\0'; ++i)
    {
        if (format[i] != '%')
        {
            putchar((unsigned char)format[i]);
            continue;
        }

        for (;;)
        {
            c = format[++i];

            if (c == '\0')
            {
                goto done;
            }
            if (c == 'c') { putchar(va_arg(ap, int));          break; }
            if (c == 's') { fputs(va_arg(ap, char *), stdout); break; }
            if (c == 'd') { printf("%d", va_arg(ap, int));     break; }
            if (c == 'X') { printf("%08X", (uint32_t)va_arg(ap, int)); break; }
            if (c == 'x') { printf("%08x", (uint32_t)va_arg(ap, int)); break; }
            /* 其它字符继续往后找，与 BSP 一致 */
        }
    }

done:
    va_end(ap);
}


uint64_t clint_getTime(uint32_t base)
{
    (void)base;

    if (g_fault == FAULT_FREEZE)
    {
        return g_ticks;
    }

    /* 自由运行的计数器：一次读带走几十个 tick，与真板量级相当 */
    g_ticks += 40u;

    return g_ticks;
}


void bsp_uDelay(uint32_t usec)
{
    uint64_t ticks = (uint64_t)usec * (BSP_CLINT_HZ / 1000000u);

    if (g_fault == FAULT_FREEZE)
    {
        return;
    }

    if (g_fault == FAULT_SLOWCLOCK)
    {
        ticks /= 2u;
    }

    g_ticks += ticks;
}


/* ------------------------------------------------------------------ */
/* driver/bitblt_api.c 的行为模型                                      */
/* ------------------------------------------------------------------ */

void bitblt_set_tick_source(bitblt_tick_fn now_ticks)
{
    if (g_fault == FAULT_NOHOOK)
    {
        return;   /* 模拟"注入被删掉/没生效"，T0 应当立刻挡住 */
    }

    g_now_ticks = now_ticks;
}


int bitblt_tick_source_ready(void)
{
    return g_now_ticks != 0;
}


uint32_t bitblt_last_status(void)
{
    return g_last_status;
}


bitblt_result_t bitblt_fill(uint32_t dst_addr,
                            uint32_t width, uint32_t height,
                            uint32_t dst_stride, uint32_t color,
                            uint64_t timeout_ticks)
{
    uint32_t pixels = width;
    uint32_t rows = height;
    uint32_t x;
    uint32_t y;

    if (timeout_ticks == 0u || width == 0u || height == 0u)
    {
        return BITBLT_EINVAL;
    }

    if (g_now_ticks == 0)
    {
        return BITBLT_ETIMEOUT;
    }

    if (g_fault == FAULT_PAD)
    {
        /* 铺满 stride，越写行尾 padding。
           每像素字节数必须跟当前位流格式走 —— 以前写死 /4 等于假设
           XRGB8888，RGB565 下注错工况会失效（注了错却抓不到）。 */
        pixels = dst_stride / TEST_MODEL_PIXEL_BYTES;
    }
    if (g_fault == FAULT_OVERRUN)
    {
        rows = height + 1u;                /* 多写一行，越写下方 guard */
    }
    if (g_fault == FAULT_SHORT)
    {
        rows = height - 1u;                /* 少写一行，回读应当抓到 */
    }

    for (y = 0u; y < rows; ++y)
    {
        volatile stub_pixel_t *row =
            (volatile stub_pixel_t *)(uintptr_t)(dst_addr + y * dst_stride);

        for (x = 0u; x < pixels; ++x)
        {
            row[x] = (stub_pixel_t)color;
        }
    }

    g_last_status = 0x2u;   /* DONE */

    return BITBLT_OK;
}


/*
 * M2 第一阶段不测 Copy，模型也就不建模它。
 * 真被用到时给一条明确的信息，而不是让链接器报一个看不懂的符号缺失。
 */
bitblt_result_t bitblt_copy(uint32_t src_addr, uint32_t dst_addr,
                            uint32_t width, uint32_t height,
                            uint32_t src_stride, uint32_t dst_stride,
                            uint64_t timeout_ticks)
{
    (void)src_addr; (void)dst_addr;
    (void)width; (void)height;
    (void)src_stride; (void)dst_stride;
    (void)timeout_ticks;

    fprintf(stderr, "stub: bitblt_copy is not modeled; M2 phase 1 has no Copy\n");

    return BITBLT_EHW;
}
