/*
 * CPU 渲染器（renderer_sw）正确性基线测试。
 *
 * 本文件是项目 CPU 渲染结果的判定基准，后续 RTL 加速器（BitBlt）的
 * 回读结果，按这里覆盖的行为逐条对齐。
 *
 * 像素格式：XRGB8888，1 pixel = 32 bit = 4 Byte（2026-09-17 确认）。
 * 本文件随 CPU 参考实现一起从 16-bit 迁移到 32-bit；
 * 迁移后备忘：改 pixel_t 宽度必须同步改 render/renderer.h 的
 * RENDER_PIXEL_BYTES，那里的静态断言会强制两处一致。
 *
 * 覆盖范围：
 *   1. 基础绘制：完全落在屏幕内的填充与拷贝
 *   2. 裁剪：负坐标、右下越界、完全在屏幕外、宽高 <= 0
 *   3. stride != width：画布行尾 padding 与源图行尾 padding
 *   4. 越界保护：画布四周预留保护区，任何越界写都会被检出
 *   5. 空指针：不得崩溃，也不得写内存
 *
 * 构建要求：
 *   本测试用 assert 判定结果，构建时禁止定义 NDEBUG。
 *   定义了 NDEBUG 时 assert 会被整体移除，测试会假通过
 *   （什么都不检查，退出码仍然是 0）。下面的 #error 把这种误用
 *   变成编译错误，避免出现"测试全绿但实际是坏的"。
 */

#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <assert.h>

#include "../render/renderer_sw.h"


#ifdef NDEBUG
#error "测试依赖 assert 判定，禁止定义 NDEBUG：断言会被移除导致假通过"
#endif


#define FB_W 16
#define FB_H 12


/*
 * 带保护区的画布。
 *
 * 有效区域是 FB_W x FB_H，但 stride 故意取 20（比宽度大 4），
 * 底部再多留 4 行。于是 x >= 16 的列尾和 y >= 12 的行全部是保护区，
 * 只要被写入就说明越界。
 *
 * 注意两点互补关系：
 *   - 保护区只能发现"落在数组内部"的越界写；
 *   - 写到数组之外的越界由 ASan（make native-test）发现。
 */
#define GUARD_STRIDE 20
#define GUARD_ROWS   16

/* 保护区的哨兵值。它只是个"没被写过"的标记，不代表任何合法颜色，
   用例里也不会写入这个值。 */
#define GUARD_VALUE  0xDEADu


/* 基础用例用的画布：stride == width */
static pixel_t framebuffer[FB_W * FB_H];

/* 边界用例用的画布：stride != width，且四周有保护区 */
static pixel_t guarded[GUARD_STRIDE * GUARD_ROWS];


static void clear_fb(void)
{
    memset(framebuffer, 0, sizeof(framebuffer));
}


static void guarded_reset(void)
{
    for (int i = 0; i < GUARD_STRIDE * GUARD_ROWS; i++)
        guarded[i] = GUARD_VALUE;
}


/* 检查基础画布上的一个像素：不符就先打印坐标再 assert */
static void check_fb(const char *tag, int x, int y, pixel_t want)
{
    pixel_t got = framebuffer[y * FB_W + x];

    if (got != want)
    {
        /* 用 PRIX32 而不是硬写 %X：rv32 上 uint32_t 是 unsigned long，
           写 %X 会与 unsigned int 不匹配，-Werror=format 会直接编译失败 */
        printf("  [FAIL] %s: framebuffer(%d,%d) 期望 0x%08" PRIX32 "，实际 0x%08" PRIX32 "\n",
               tag, x, y, want, got);
    }

    assert(got == want);
}


/* 检查带保护区画布上的一个像素 */
static void check_guarded(const char *tag, int x, int y, pixel_t want)
{
    pixel_t got = guarded[y * GUARD_STRIDE + x];

    if (got != want)
    {
        printf("  [FAIL] %s: guarded(%d,%d) 期望 0x%08" PRIX32 "，实际 0x%08" PRIX32 "\n",
               tag, x, y, want, got);
    }

    assert(got == want);
}


/* 有效区域之外（行尾 padding 列 + 底部保护行）必须一个像素都没动过 */
static void check_padding_intact(const char *tag)
{
    for (int y = 0; y < GUARD_ROWS; y++)
    {
        for (int x = 0; x < GUARD_STRIDE; x++)
        {
            if (x >= FB_W || y >= FB_H)
                check_guarded(tag, x, y, GUARD_VALUE);
        }
    }
}


/* 整块画布（含有效区域）都必须没动过，用于"完全在屏幕外"的用例 */
static void check_all_intact(const char *tag)
{
    for (int y = 0; y < GUARD_ROWS; y++)
    {
        for (int x = 0; x < GUARD_STRIDE; x++)
            check_guarded(tag, x, y, GUARD_VALUE);
    }
}


/* ------------------------------------------------------------------ */
/* 基础用例                                                            */
/* ------------------------------------------------------------------ */

static void test_fill_rect(void)
{
    clear_fb();

    /* XRGB8888 的纯红：高 8 位空，红 8 位全 1 */
    const pixel_t RED = 0x00FF0000u;

    sw_fill_rect(
        framebuffer,
        FB_W,
        FB_H,
        FB_W,
        4,
        3,
        5,
        4,
        RED
    );

    for (int y = 0; y < FB_H; y++)
    {
        for (int x = 0; x < FB_W; x++)
        {
            int inside =
                (x >= 4 && x < 9 &&
                 y >= 3 && y < 7);

            if (inside)
                check_fb("基础填充-矩形内", x, y, RED);
            else
                check_fb("基础填充-矩形外", x, y, 0);
        }
    }

    printf("[PASS] sw_fill_rect\n");
}


static void test_blit(void)
{
    clear_fb();

    /* 6 个互不相同的标记值，只用于检验"哪个像素搬到了哪里"，不表示真实颜色 */
    pixel_t sprite[3 * 2] =
    {
        1, 2, 3,
        4, 5, 6
    };

    sw_blit(
        framebuffer,
        FB_W,
        FB_H,
        FB_W,

        sprite,
        3,
        2,
        3,

        5,
        4
    );

    check_fb("基础拷贝", 5, 4, 1);
    check_fb("基础拷贝", 6, 4, 2);
    check_fb("基础拷贝", 7, 4, 3);

    check_fb("基础拷贝", 5, 5, 4);
    check_fb("基础拷贝", 6, 5, 5);
    check_fb("基础拷贝", 7, 5, 6);

    printf("[PASS] sw_blit\n");
}


/* ------------------------------------------------------------------ */
/* 填充裁剪                                                            */
/* ------------------------------------------------------------------ */

/* 负坐标：左上角在屏幕外，必须裁到 (0,0)，且不能写到画布外 */
static void test_fill_rect_clip_left_top(void)
{
    guarded_reset();

    /* 矩形覆盖 x = -3..2、y = -2..2，可见部分是 (0,0)-(2,2) */
    sw_fill_rect(guarded, FB_W, FB_H, GUARD_STRIDE, -3, -2, 6, 5, 0x5678);

    check_guarded("负坐标", 0, 0, 0x5678);
    check_guarded("负坐标", 2, 2, 0x5678);
    check_guarded("负坐标", 3, 0, GUARD_VALUE);
    check_guarded("负坐标", 0, 3, GUARD_VALUE);

    check_padding_intact("负坐标");
    printf("[PASS] sw_fill_rect 负坐标裁剪\n");
}


/* 右下越界：起点在屏幕内，但尺寸远超画布 */
static void test_fill_rect_clip_right_bottom(void)
{
    guarded_reset();

    /* 起点 (13,10)，尺寸 50x50，可见部分是 (13,10)-(15,11) */
    sw_fill_rect(guarded, FB_W, FB_H, GUARD_STRIDE,
                 FB_W - 3, FB_H - 2, 50, 50, 0xABCD);

    check_guarded("右下越界", 13, 10, 0xABCD);
    check_guarded("右下越界", 15, 11, 0xABCD);
    check_guarded("右下越界", 12, 10, GUARD_VALUE);
    check_guarded("右下越界", 15, 9, GUARD_VALUE);

    check_padding_intact("右下越界");
    printf("[PASS] sw_fill_rect 右下越界裁剪\n");
}


/* 完全在屏幕外：一个像素都不许写 */
static void test_fill_rect_fully_outside(void)
{
    guarded_reset();

    /* 左上方向完全在外 */
    sw_fill_rect(guarded, FB_W, FB_H, GUARD_STRIDE, -50, -50, 10, 10, 0xFFFF);

    /* 起点在左边很远，右边界仍然落在屏幕外：
       这里 x0 会被裁到 0，但 x1 仍是负数，不能因为 x0 合法就往下走 */
    sw_fill_rect(guarded, FB_W, FB_H, GUARD_STRIDE, -100, 0, 50, 10, 0xFFFF);

    /* 右下方向完全在外 */
    sw_fill_rect(guarded, FB_W, FB_H, GUARD_STRIDE,
                 FB_W + 10, FB_H + 10, 10, 10, 0xFFFF);

    check_all_intact("完全在外");
    printf("[PASS] sw_fill_rect 完全在屏幕外\n");
}


/* 宽高为 0 或负数：合法输入，应当什么都不做 */
static void test_fill_rect_empty(void)
{
    guarded_reset();

    sw_fill_rect(guarded, FB_W, FB_H, GUARD_STRIDE, 0, 0, 0, 5, 0xFFFF);
    sw_fill_rect(guarded, FB_W, FB_H, GUARD_STRIDE, 0, 0, 5, -3, 0xFFFF);
    sw_fill_rect(guarded, FB_W, FB_H, GUARD_STRIDE, 2, 2, -4, -4, 0xFFFF);

    check_all_intact("空矩形");
    printf("[PASS] sw_fill_rect 宽高 <= 0\n");
}


/* 正好贴合边界：宽高恰好等于画布尺寸，不能多写一个像素（防 off-by-one） */
static void test_fill_rect_exact_fit(void)
{
    guarded_reset();

    sw_fill_rect(guarded, FB_W, FB_H, GUARD_STRIDE, 0, 0, FB_W, FB_H, 0x0F0F);

    for (int y = 0; y < FB_H; y++)
    {
        for (int x = 0; x < FB_W; x++)
            check_guarded("正好贴合", x, y, 0x0F0F);
    }

    check_padding_intact("正好贴合");
    printf("[PASS] sw_fill_rect 正好贴合画布边界\n");
}


/* 超大矩形盖满全屏，起点为负、尺寸远超画布 */
static void test_fill_rect_oversized(void)
{
    guarded_reset();

    sw_fill_rect(guarded, FB_W, FB_H, GUARD_STRIDE, -100, -100, 1000, 1000, 0x0F0F);

    for (int y = 0; y < FB_H; y++)
    {
        for (int x = 0; x < FB_W; x++)
            check_guarded("盖满全屏", x, y, 0x0F0F);
    }

    check_padding_intact("盖满全屏");
    printf("[PASS] sw_fill_rect 超大矩形覆盖全屏\n");
}


/* ------------------------------------------------------------------ */
/* 拷贝裁剪                                                            */
/* ------------------------------------------------------------------ */

/* 源图带行尾 padding（src_stride != src_width），不能把 padding 当像素拷过去 */
static void test_blit_src_padding(void)
{
    /* 3x2 的图，但每行占 4 个像素，第 4 个是 padding */
    pixel_t src[4 * 2] =
    {
        0x0101, 0x0102, 0x0103, 0xFFFF,
        0x0201, 0x0202, 0x0203, 0xFFFF
    };

    guarded_reset();

    sw_blit(guarded, FB_W, FB_H, GUARD_STRIDE,
            src, 3, 2, 4,
            5, 4);

    check_guarded("源图padding", 5, 4, 0x0101);
    check_guarded("源图padding", 6, 4, 0x0102);
    check_guarded("源图padding", 7, 4, 0x0103);

    check_guarded("源图padding", 5, 5, 0x0201);
    check_guarded("源图padding", 6, 5, 0x0202);
    check_guarded("源图padding", 7, 5, 0x0203);

    /* 只写了 3 列，第 4 列必须是保护值 */
    check_guarded("源图padding", 8, 4, GUARD_VALUE);
    check_guarded("源图padding", 8, 5, GUARD_VALUE);

    /* 只写了 2 行，第 3 行必须是保护值 */
    check_guarded("源图padding", 5, 6, GUARD_VALUE);

    check_padding_intact("源图padding");
    printf("[PASS] sw_blit 源图带行尾 padding\n");
}


/*
 * 源图 stride 与源图宽度都要 != 目标 stride，三方都不同，
 * 确保实现是用 src_stride 行进位、用 fb_stride 存放、用 src_width 计数。
 */
static void test_blit_all_strides_differ(void)
{
    /* 2x2 的图，每行占 3 个像素 */
    pixel_t src[3 * 2] =
    {
        0x0A, 0x0B, 0xEE,
        0x0C, 0x0D, 0xEE
    };

    guarded_reset();

    sw_blit(guarded, FB_W, FB_H, GUARD_STRIDE,
            src, 2, 2, 3,
            9, 7);

    check_guarded("三方stride不同", 9, 7, 0x0A);
    check_guarded("三方stride不同", 10, 7, 0x0B);
    check_guarded("三方stride不同", 9, 8, 0x0C);
    check_guarded("三方stride不同", 10, 8, 0x0D);

    check_guarded("三方stride不同", 11, 7, GUARD_VALUE);
    check_guarded("三方stride不同", 9, 9, GUARD_VALUE);

    check_padding_intact("三方stride不同");
    printf("[PASS] sw_blit 源/目标 stride 互不相同\n");
}


/* 负偏移：源图左上角在屏幕外 */
static void test_blit_clip_negative(void)
{
    pixel_t src[4 * 4];
    for (int i = 0; i < 16; i++)
        src[i] = (pixel_t)(0x200 + i);

    guarded_reset();

    /* 目标 (-2,-2)：只有源图的 (2,2)/(3,2)/(2,3)/(3,3) 四个像素可见 */
    sw_blit(guarded, FB_W, FB_H, GUARD_STRIDE,
            src, 4, 4, 4,
            -2, -2);

    check_guarded("blit负偏移", 0, 0, 0x200 + 2 * 4 + 2);
    check_guarded("blit负偏移", 1, 0, 0x200 + 2 * 4 + 3);
    check_guarded("blit负偏移", 0, 1, 0x200 + 3 * 4 + 2);
    check_guarded("blit负偏移", 1, 1, 0x200 + 3 * 4 + 3);

    check_guarded("blit负偏移", 2, 0, GUARD_VALUE);
    check_guarded("blit负偏移", 0, 2, GUARD_VALUE);

    check_padding_intact("blit负偏移");
    printf("[PASS] sw_blit 负偏移裁剪\n");
}


/* 右下越界：源图右下方超出画布 */
static void test_blit_clip_right_bottom(void)
{
    pixel_t src[4 * 4];
    for (int i = 0; i < 16; i++)
        src[i] = (pixel_t)(0x300 + i);

    guarded_reset();

    /* 目标 (14,10)：只有源图左上角 2x2 可见 */
    sw_blit(guarded, FB_W, FB_H, GUARD_STRIDE,
            src, 4, 4, 4,
            FB_W - 2, FB_H - 2);

    check_guarded("blit右下", 14, 10, 0x300);
    check_guarded("blit右下", 15, 10, 0x300 + 1);
    check_guarded("blit右下", 14, 11, 0x300 + 4);
    check_guarded("blit右下", 15, 11, 0x300 + 5);

    check_padding_intact("blit右下");
    printf("[PASS] sw_blit 右下越界裁剪\n");
}


/* 完全在屏幕外 */
static void test_blit_fully_outside(void)
{
    pixel_t src[4 * 4];
    for (int i = 0; i < 16; i++)
        src[i] = (pixel_t)(0x400 + i);

    guarded_reset();

    sw_blit(guarded, FB_W, FB_H, GUARD_STRIDE, src, 4, 4, 4, -100, -100);

    /* 纵向落在画布内，但横向整体在屏幕左边：
       行合法不代表列合法，不能漏掉列方向的判断 */
    sw_blit(guarded, FB_W, FB_H, GUARD_STRIDE, src, 4, 4, 4, -6, 0);

    /* 右下方向完全在外 */
    sw_blit(guarded, FB_W, FB_H, GUARD_STRIDE, src, 4, 4, 4,
            FB_W + 10, FB_H + 10);

    check_all_intact("blit完全在外");
    printf("[PASS] sw_blit 完全在屏幕外\n");
}


/* 空指针：不得崩溃，也不得写内存 */
static void test_null_pointers(void)
{
    guarded_reset();

    /* 目标为空指针：直接返回，不得解引用 */
    sw_fill_rect(0, FB_W, FB_H, GUARD_STRIDE, 1, 1, 4, 4, 0xFFFF);
    sw_blit(0, FB_W, FB_H, GUARD_STRIDE, guarded, 4, 4, 4, 1, 1);

    /* 源为空指针：不得读，也不得写 */
    sw_blit(guarded, FB_W, FB_H, GUARD_STRIDE, 0, 4, 4, 4, 1, 1);

    check_all_intact("空指针");
    printf("[PASS] 空指针安全\n");
}


int main(void)
{
    /* 基础用例 */
    test_fill_rect();
    test_blit();

    /* 填充裁剪 */
    test_fill_rect_clip_left_top();
    test_fill_rect_clip_right_bottom();
    test_fill_rect_fully_outside();
    test_fill_rect_empty();
    test_fill_rect_exact_fit();
    test_fill_rect_oversized();

    /* 拷贝裁剪 */
    test_blit_src_padding();
    test_blit_all_strides_differ();
    test_blit_clip_negative();
    test_blit_clip_right_bottom();
    test_blit_fully_outside();

    /* 空指针 */
    test_null_pointers();

    printf("\nAll renderer tests passed.\n");

    return 0;
}
