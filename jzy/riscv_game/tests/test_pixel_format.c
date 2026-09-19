/*
 * 像素格式、几何参数与软件参考绘制（Color Key / Alpha）的测试。
 *
 * 覆盖 07_docs/interfaces/unified_fpga_interface_spec_v1.0.md 里 C 侧要落地的部分：
 *   - RGB888/XRGB8888 -> RGB565 打包，RGB565 -> 通道值解包
 *   - 几何：宽高、stride、整帧字节数、宽度粒度、16 B 对齐
 *   - Color Key 按 16-bit 精确比较
 *   - Alpha 混合在较宽位宽上算、量化回当前格式，且两个端点精确
 *
 * 本文件对两种像素格式都要成立：
 *   RGB565（默认）与 -DRENDER_PIXEL_FORMAT_RGB565=0 的 XRGB8888 回退。
 * 与格式有关的期望值按开关分支写，不写死其中一种。
 *
 * 构建要求：禁止定义 NDEBUG（assert 会被整体移除导致假通过）。
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>

#include "framebuffer_format.h"
#include "renderer_sw.h"
#include "renderer_sw_ext.h"


#ifdef NDEBUG
#error "测试依赖 assert 判定，禁止定义 NDEBUG：断言会被移除导致假通过"
#endif


/* ------------------------------------------------------------------ */
/* 画布与保护区                                                        */
/* ------------------------------------------------------------------ */

#define PAD_STRIDE 20   /* 有效宽度 16，多出的是行尾 padding */
#define PAD_ROWS    4   /* 底部保护行 */

#define GUARD 0xDEADu

static pixel_t canvas[PAD_STRIDE * (12 + PAD_ROWS)];


/*
 * 按通道值造一个软件像素。
 *
 * 不能直接写 0xFFFF 当白色 —— 同一个字面量在 RGB565 里是白，
 * 在 XRGB8888 里是青色。测试里的"白色/黑色"必须按格式构造，
 * 否则测试本身就成了"默认按 4 B/像素处理"的残留。
 */
static pixel_t make_color(uint8_t r, uint8_t g, uint8_t b)
{
#if RENDER_PIXEL_FORMAT_RGB565
    return (pixel_t)fmt_rgb565_pack(r, g, b);
#else
    return (pixel_t)(((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b);
#endif
}


/* make_color 的逆运算，同样与格式无关 */
static void unpack_color(pixel_t px, uint8_t *r, uint8_t *g, uint8_t *b)
{
#if RENDER_PIXEL_FORMAT_RGB565
    fmt_rgb565_unpack((uint16_t)px, r, g, b);
#else
    *r = (uint8_t)(((uint32_t)px >> 16) & 0xFFu);
    *g = (uint8_t)(((uint32_t)px >> 8) & 0xFFu);
    *b = (uint8_t)((uint32_t)px & 0xFFu);
#endif
}

static void canvas_reset(void)
{
    for (size_t i = 0; i < sizeof(canvas) / sizeof(canvas[0]); i++)
        canvas[i] = (pixel_t)GUARD;
}


/*
 * 有效区之外的每一个像素都必须是 GUARD。
 * 这条能抓住"写到行尾 padding 或底部保护行"的越界写。
 */
static void check_guards(const char *tag)
{
    int bad = 0;

    for (int y = 0; y < 12 + PAD_ROWS; y++)
    {
        for (int x = 0; x < PAD_STRIDE; x++)
        {
            int inside = (x < 16) && (y < 12);

            if (!inside && canvas[y * PAD_STRIDE + x] != (pixel_t)GUARD)
                bad++;
        }
    }

    if (bad != 0)
        printf("  [FAIL] %s: 有效区外有 %d 个像素被改写\n", tag, bad);

    assert(bad == 0);
}


/* ------------------------------------------------------------------ */
/* 1. 打包 / 解包                                                      */
/* ------------------------------------------------------------------ */

static void test_rgb565_pack_channels(void)
{
    /* 位段：R[15:11] G[10:5] B[4:0] */
    assert(fmt_rgb565_pack(0, 0, 0) == 0x0000u);
    assert(fmt_rgb565_pack(0xFF, 0xFF, 0xFF) == 0xFFFFu);
    assert(fmt_rgb565_pack(0xFF, 0, 0) == 0xF800u);
    assert(fmt_rgb565_pack(0, 0xFF, 0) == 0x07E0u);
    assert(fmt_rgb565_pack(0, 0, 0xFF) == 0x001Fu);

    /* 打包取高位：0x08 的 R5 = 1，0x07 的 R5 = 0 */
    assert(fmt_rgb565_pack(0x08, 0, 0) == (1u << 11));
    assert(fmt_rgb565_pack(0x07, 0, 0) == 0x0000u);

    printf("[PASS] RGB565 打包位段\n");
}


static void test_rgb565_unpack_bit_replication(void)
{
    uint8_t r = 0, g = 0, b = 0;

    /* 满量程必须映射到满量程，否则纯白会变成灰白 */
    fmt_rgb565_unpack(0xFFFFu, &r, &g, &b);
    assert(r == 0xFF && g == 0xFF && b == 0xFF);

    fmt_rgb565_unpack(0x0000u, &r, &g, &b);
    assert(r == 0 && g == 0 && b == 0);

    fmt_rgb565_unpack(0xF800u, &r, &g, &b);
    assert(r == 0xFF && g == 0x00 && b == 0x00);

    fmt_rgb565_unpack(0x07E0u, &r, &g, &b);
    assert(r == 0x00 && g == 0xFF && b == 0x00);

    fmt_rgb565_unpack(0x001Fu, &r, &g, &b);
    assert(r == 0x00 && g == 0x00 && b == 0xFF);

    /* 位复制的性质：R5=1 -> {001, 00} = 0b00100 = 8 */
    fmt_rgb565_unpack((uint16_t)(1u << 11), &r, &g, &b);
    assert(r == 8);

    /* 允许只取部分通道 */
    fmt_rgb565_unpack(0xF800u, &r, 0, 0);
    assert(r == 0xFF);

    printf("[PASS] RGB565 解包位复制（满量程 -> 满量程）\n");
}


static void test_rgb565_round_trip(void)
{
    /*
     * 全部 65536 个取值都必须满足 pack(unpack(v)) == v。
     *
     * 这条保证了 Color Key 的精确比较和 Alpha 的端点精确性：
     * 只要往返不是恒等，透明色就会和源像素对不上。
     */
    for (uint32_t v = 0; v <= 0xFFFFu; v++)
    {
        uint8_t r = 0, g = 0, b = 0;
        uint16_t back;

        fmt_rgb565_unpack((uint16_t)v, &r, &g, &b);
        back = fmt_rgb565_pack(r, g, b);

        assert(back == (uint16_t)v);
    }

    printf("[PASS] RGB565 解包/打包往返恒等（全部 65536 个取值）\n");
}


static void test_xrgb8888_conversion(void)
{
    assert(fmt_xrgb8888_to_rgb565(0x00000000u) == 0x0000u);
    assert(fmt_xrgb8888_to_rgb565(0x00FFFFFFu) == 0xFFFFu);
    assert(fmt_xrgb8888_to_rgb565(0x00FF0000u) == 0xF800u);
    assert(fmt_xrgb8888_to_rgb565(0x0000FF00u) == 0x07E0u);
    assert(fmt_xrgb8888_to_rgb565(0x000000FFu) == 0x001Fu);

    /* 高 8 位的 X 被忽略：0xFFRRGGBB 与 0x00RRGGBB 结果相同 */
    assert(fmt_xrgb8888_to_rgb565(0xFF123456u) == fmt_xrgb8888_to_rgb565(0x00123456u));

    /* 反向转换只有 16 bit 信息量，但纯色必须还原成纯色 */
    assert(fmt_rgb565_to_xrgb8888(0xFFFFu) == 0x00FFFFFFu);
    assert(fmt_rgb565_to_xrgb8888(0xF800u) == 0x00FF0000u);

    printf("[PASS] XRGB8888 <-> RGB565 转换\n");
}


static void test_color_register_mapping(void)
{
    /* 硬件 COLOR 寄存器值 <-> 软件像素值必须互逆 */
    for (uint32_t i = 0; i < 256u; i++)
    {
        uint32_t raw = (i * 257u) & 0xFFFFu;
        pixel_t  px  = fmt_color_from_hw(raw);

        assert(fmt_color_to_hw(px) == raw);
    }

#if RENDER_PIXEL_FORMAT_RGB565
    /* RGB565：高 16 位必须清零（统一规范要求，避免新旧驱动误配） */
    assert(fmt_color_to_hw((pixel_t)0xFFFFu) == 0x0000FFFFu);
    assert((fmt_color_to_hw((pixel_t)0xFFFFu) & 0xFFFF0000u) == 0u);
#endif

    printf("[PASS] COLOR 寄存器映射互逆\n");
}


/* ------------------------------------------------------------------ */
/* 2. 几何参数                                                         */
/* ------------------------------------------------------------------ */

static void test_geometry(void)
{
#if RENDER_PIXEL_FORMAT_RGB565
    /* 统一目标：1280x720@60，RGB565 —— 数值直接来自统一规范 */
    assert(FMT_WIDTH == 1280u);
    assert(FMT_HEIGHT == 720u);
    assert(FMT_BYTES_PER_PIXEL == 2u);
    assert(FMT_STRIDE == 2560u);
    assert(FMT_FRAME_BYTES == 1843200u);
    assert(FMT_PIXEL_CLOCK_HZ == 74250000u);
    assert(FMT_PIXELS_PER_BEAT == 8u);

    /* 水平总像素 1280+110+40+220 = 1650；垂直 720+5+5+20 = 750 */
    assert(FMT_WIDTH + FMT_H_FRONT_PORCH + FMT_H_SYNC + FMT_H_BACK_PORCH == 1650u);
    assert(FMT_HEIGHT + FMT_V_FRONT_PORCH + FMT_V_SYNC + FMT_V_BACK_PORCH == 750u);
#else
    /* 历史基线：1920x1080@60，XRGB8888 */
    assert(FMT_WIDTH == 1920u);
    assert(FMT_HEIGHT == 1080u);
    assert(FMT_BYTES_PER_PIXEL == 4u);
    assert(FMT_STRIDE == 7680u);
    assert(FMT_FRAME_BYTES == 8294400u);
    assert(FMT_PIXEL_CLOCK_HZ == 148750000u);
    assert(FMT_PIXELS_PER_BEAT == 4u);

    assert(FMT_WIDTH + FMT_H_FRONT_PORCH + FMT_H_SYNC + FMT_H_BACK_PORCH == 2200u);
    assert(FMT_HEIGHT + FMT_V_FRONT_PORCH + FMT_V_SYNC + FMT_V_BACK_PORCH == 1125u);
#endif

    /* 派生关系：stride 与整帧字节数不得是另填的数字 */
    assert(FMT_STRIDE == FMT_WIDTH * FMT_BYTES_PER_PIXEL);
    assert(FMT_FRAME_BYTES == FMT_STRIDE * FMT_HEIGHT);

    /* 128-bit beat 恰好覆盖整数个像素 */
    assert((FMT_PIXELS_PER_BEAT * FMT_BYTES_PER_PIXEL) == 16u);

    /* 一整帧必须装得进一个 8 MiB slot */
    assert(FMT_FRAME_BYTES <= FB_SLOT_SIZE);

    printf("[PASS] 几何参数与统一规范一致\n");
}


static void test_alignment_rules(void)
{
    /* 16 B 对齐：stride 与整帧字节数都必须满足 */
    assert((FMT_STRIDE % FMT_ALIGN_BYTES) == 0u);
    assert((FMT_FRAME_BYTES % FMT_ALIGN_BYTES) == 0u);

    /* 宽度粒度 = 16 B / 每像素字节数：XRGB8888 -> 4，RGB565 -> 8 */
    assert(FMT_WIDTH_GRANULARITY == (FMT_ALIGN_BYTES / FMT_BYTES_PER_PIXEL));

#if RENDER_PIXEL_FORMAT_RGB565
    assert(FMT_WIDTH_GRANULARITY == 8u);
#else
    assert(FMT_WIDTH_GRANULARITY == 4u);
#endif

    /* 现行宽度本身满足自己的粒度 */
    assert((FMT_WIDTH % FMT_WIDTH_GRANULARITY) == 0u);

    /* 每行字节数必须 >= 宽度 × 每像素字节数（否则行会重叠） */
    assert(FMT_STRIDE >= FMT_WIDTH * FMT_BYTES_PER_PIXEL);

    printf("[PASS] 对齐与宽度粒度规则\n");
}


/*
 * 地址算术：矩形在 DDR 里的字节区间。
 *
 * 复用校验器的口径（末行占 width × 每像素字节数），但这里用
 * 独立算式算一遍，两边对不上就说明有一侧算错了。
 */
static void test_address_arithmetic(void)
{
    const uint32_t fb_base = (uint32_t)FB_A_BASE;
    const uint32_t stride  = FMT_STRIDE;
    const uint32_t x = 16u, y = 3u;
    const uint32_t w = 64u, h = 4u;

    uint64_t addr = (uint64_t)fb_base
                  + (uint64_t)y * stride
                  + (uint64_t)x * FMT_BYTES_PER_PIXEL;

    uint64_t end = addr + (uint64_t)(h - 1u) * stride
                        + (uint64_t)w * FMT_BYTES_PER_PIXEL;

    /* 起点必须落在 Framebuffer A 里 */
    assert(addr >= (uint64_t)FB_A_BASE);
    assert(addr < (uint64_t)FB_A_BASE + FB_SLOT_SIZE);

    /* 覆盖的行数：end 落在第 y+h-1 行内 */
    assert(end > (uint64_t)fb_base + (uint64_t)(y + h - 1u) * stride);
    assert(end <= (uint64_t)fb_base + (uint64_t)(y + h - 1u) * stride + stride);

    /* 16 B 对齐：x 为 16 时，每像素 2 或 4 Byte 都对齐 */
    assert((addr % FMT_ALIGN_BYTES) == 0u);

    /* 一整帧从 FB_A 起算，正好占 FMT_FRAME_BYTES */
    assert((uint64_t)FB_A_BASE + FMT_FRAME_BYTES
           <= (uint64_t)FB_A_BASE + FB_SLOT_SIZE);

    /* 后台 Buffer B 与 A 不重叠 */
    assert((uint64_t)FB_B_BASE >= (uint64_t)FB_A_BASE + FB_SLOT_SIZE);

    printf("[PASS] 地址与 stride 算术（含 16 B 对齐）\n");
}


/* ------------------------------------------------------------------ */
/* 3. Color Key                                                        */
/* ------------------------------------------------------------------ */

static void test_color_key(void)
{
    /*
     * 源里有一个"透明"像素（等于 key），目标对应位置必须保持原值。
     * key 用 16-bit 精确比较：差一位就不算命中。
     */
#if RENDER_PIXEL_FORMAT_RGB565
    const pixel_t key = 0xF800u;   /* 纯红 */
    const pixel_t near_key = 0xF801u;  /* 只差最低位 */
#else
    const pixel_t key = 0x00FF0000u;
    const pixel_t near_key = 0x00FF0001u;
#endif

    const pixel_t bg = (pixel_t)0x0011u;
    const pixel_t fg = (pixel_t)0x0022u;

    pixel_t src[4 * 2] =
    {
        fg,  key, fg,  near_key,
        key, fg,  fg,  key
    };

    canvas_reset();

    /* 先把整块有效区刷成背景色（复用冻结基线的 fill） */
    sw_fill_rect(canvas, 16, 12, PAD_STRIDE, 0, 0, 16, 12, bg);

    sw_color_key_blit(canvas, 16, 12, PAD_STRIDE,
                      src, 4, 2, 4,
                      2, 3,
                      key);

    for (int sy = 0; sy < 2; sy++)
    {
        for (int sx = 0; sx < 4; sx++)
        {
            int dx = 2 + sx;
            int dy = 3 + sy;
            pixel_t got = canvas[dy * PAD_STRIDE + dx];
            pixel_t sp  = src[sy * 4 + sx];

            if (sp == key)
            {
                /* 命中 key：目标保持背景色，源像素不被写过去 */
                assert(got == bg);
            }
            else
            {
                /* 未命中：源像素完整搬过去（near_key 也算未命中） */
                assert(got == sp);
            }
        }
    }

    check_guards("color key 不越界");

    /* 完全在画布外的目标位置：什么都不写，也不崩 */
    canvas_reset();
    sw_color_key_blit(canvas, 16, 12, PAD_STRIDE, src, 4, 2, 4, -100, -100, key);
    sw_color_key_blit(canvas, 16, 12, PAD_STRIDE, src, 4, 2, 4, 100, 100, key);
    check_guards("color key 画布外");

    /* 空指针不得崩溃 */
    sw_color_key_blit(0, 16, 12, PAD_STRIDE, src, 4, 2, 4, 0, 0, key);
    sw_color_key_blit(canvas, 16, 12, PAD_STRIDE, 0, 4, 2, 4, 0, 0, key);

    printf("[PASS] Color Key 精确比较与透明语义\n");
}


/* ------------------------------------------------------------------ */
/* 4. Alpha 混合                                                       */
/* ------------------------------------------------------------------ */

static void test_alpha_endpoints(void)
{
    const pixel_t color = (pixel_t)0x7BEFu;
    const pixel_t bg    = (pixel_t)0x0012u;

    /* alpha = 0：完全透明，目标一个像素都不许变 */
    canvas_reset();
    sw_alpha_blend_rect(canvas, 16, 12, PAD_STRIDE, 0, 0, 16, 12, color, 0u);

    for (int y = 0; y < 12; y++)
        for (int x = 0; x < 16; x++)
            assert(canvas[y * PAD_STRIDE + x] == (pixel_t)GUARD);

    /* alpha = 255：完全覆盖，结果精确等于源色（不经过混合公式） */
    canvas_reset();
    sw_alpha_blend_rect(canvas, 16, 12, PAD_STRIDE, 0, 0, 16, 12, color, 255u);

    for (int y = 0; y < 12; y++)
        for (int x = 0; x < 16; x++)
            assert(canvas[y * PAD_STRIDE + x] == color);

    /* 在已有底色上 alpha = 255，同样必须精确等于源色 */
    canvas_reset();
    sw_alpha_blend_rect(canvas, 16, 12, PAD_STRIDE, 0, 0, 16, 12, bg, 255u);
    sw_alpha_blend_rect(canvas, 16, 12, PAD_STRIDE, 0, 0, 16, 12, color, 255u);
    assert(canvas[5 * PAD_STRIDE + 5] == color);

    printf("[PASS] Alpha 两个端点精确（0 = 不变，255 = 精确源色）\n");
}


static void test_alpha_midpoint(void)
{
    /*
     * alpha = 128 的黑底白字：结果应当落在通道中点附近。
     *
     * 这里不追求"某个精确整数"，而是验证【单调且落在两端之间】：
     * 量化回 RGB565 会丢低位，写死精确值等于把实现细节焊进测试。
     */
    const pixel_t white = make_color(0xFF, 0xFF, 0xFF);
    const pixel_t black = make_color(0x00, 0x00, 0x00);
    uint8_t r0, g0, b0, r1, g1, b1;

    canvas_reset();
    sw_alpha_blend_rect(canvas, 16, 12, PAD_STRIDE, 0, 0, 16, 12, black, 255u);
    sw_alpha_blend_rect(canvas, 16, 12, PAD_STRIDE, 4, 4, 8, 4, white, 128u);

    unpack_color(canvas[5 * PAD_STRIDE + 5], &r0, &g0, &b0);
    unpack_color(black, &r1, &g1, &b1);

    /* 白底黑上 50%：每个通道都被抬起来了，但没有到满 */
    assert(r0 > r1 && r0 < 0xFF);
    assert(g0 > g1 && g0 < 0xFF);
    assert(b0 > b1 && b0 < 0xFF);

    /* 混合区之外仍然是黑色 */
    assert(canvas[0 * PAD_STRIDE + 0] == black);
    assert(canvas[11 * PAD_STRIDE + 15] == black);

    check_guards("alpha 不越界");

    printf("[PASS] Alpha 中间值单调落在两端之间\n");
}


static void test_alpha_clipping(void)
{
    const pixel_t color = (pixel_t)0x1234u;

    /* 越界矩形必须被裁剪，且不碰保护区 */
    canvas_reset();
    sw_alpha_blend_rect(canvas, 16, 12, PAD_STRIDE, -8, -8, 20, 20, color, 200u);
    sw_alpha_blend_rect(canvas, 16, 12, PAD_STRIDE, 12, 8, 100, 100, color, 200u);
    sw_alpha_blend_rect(canvas, 16, 12, PAD_STRIDE, 0, 0, 0, 0, color, 200u);
    check_guards("alpha 裁剪");

    /* 空指针不得崩溃 */
    sw_alpha_blend_rect(0, 16, 12, PAD_STRIDE, 0, 0, 4, 4, color, 128u);

    printf("[PASS] Alpha 裁剪与空指针安全\n");
}


/* ------------------------------------------------------------------ */

int main(void)
{
    setvbuf(stdout, 0, _IONBF, 0);

    printf("像素格式：%s（每像素 %u Byte）\n",
#if RENDER_PIXEL_FORMAT_RGB565
           "RGB565",
#else
           "XRGB8888",
#endif
           (unsigned)FMT_BYTES_PER_PIXEL);

    test_rgb565_pack_channels();
    test_rgb565_unpack_bit_replication();
    test_rgb565_round_trip();
    test_xrgb8888_conversion();
    test_color_register_mapping();

    test_geometry();
    test_alignment_rules();
    test_address_arithmetic();

    test_color_key();
    test_alpha_endpoints();
    test_alpha_midpoint();
    test_alpha_clipping();

    printf("\nAll pixel format tests passed.\n");

    return 0;
}
