/*
 * 换帧状态机测试 —— C 组软件作为唯一 SWAP 提交者的强制顺序。
 *
 * 依据：07_docs/interfaces/unified_fpga_interface_spec_v1.0.md
 *       「单一换帧控制与缓冲区所有权」
 *
 * 本文件要钉住的不是"能不能换成功"，而是【顺序不许被绕过】：
 *
 *   1. 后台只能有一个生产者，且拿到的永远不是当前前台
 *   2. 坏帧绝不提交换帧，前台一个字节都不动
 *   3. 提交之后、回读确认 FRONT_ADDR 之前，旧前台不能被任何人拿到
 *   4. 只有回读 FRONT_ADDR 才算确认，SWAP_DONE 单独出现不算数
 *   5. 已冻结但尚未接入的 UDP V2.0 必须走能力检测，不能把旧原型当成可用
 *
 * 地址取 B 权威头文件里的 FB_A_BASE / FB_B_BASE，不另编数字。
 *
 * 构建要求：禁止定义 NDEBUG。
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>

#include "frame_swap.h"
#include "display_api.h"
#include "display_platform.h"
#include "framebuffer_format.h"
#include "protocol_frozen.h"
#include "protocol_unfrozen.h"
#include "framebuffer_layout.h"


#ifdef NDEBUG
#error "测试依赖 assert 判定，禁止定义 NDEBUG：断言会被移除导致假通过"
#endif

#ifdef DISPLAY_ENABLE_HW_ACCESS
#error "本机测试不得开启硬件访问"
#endif


#define TIMEOUT_TICKS 1000000ULL

#define FB_A ((uintptr_t)FB_A_BASE)
#define FB_B ((uintptr_t)FB_B_BASE)


static uint64_t g_fake_ticks = 0;

static uint64_t fake_now(void)
{
    return g_fake_ticks;
}


/* 每一条用例都从干净的平台状态开始 */
static void platform_reset(void)
{
    protocol_caps_reset(0);
    display_set_bus_path_axi();
    display_set_tick_source(fake_now);
    display_test_set_swap_ok(1);
    display_test_set_swap_updates_front(1);
    display_test_set_front((uint32_t)FB_A);

    /* 默认摆成"当前联合工程的显示控制器"：V3.0 */
    display_test_set_version(PROTO_DISPLAY_VERSION_RGB565);
}


/* ------------------------------------------------------------------ */
/* 1. 初始化与参数校验                                                 */
/* ------------------------------------------------------------------ */

static void test_init(void)
{
    frame_swap_t fs;

    assert(frame_swap_init(0, FB_A, FB_B, FB_A) == FRAME_SWAP_ERR_INVALID_ARG);

    /* 两个 buffer 不能是同一个地址 */
    assert(frame_swap_init(&fs, FB_A, FB_A, FB_A) == FRAME_SWAP_ERR_INVALID_ARG);

    /* 初始前台必须是其中之一 */
    assert(frame_swap_init(&fs, FB_A, FB_B, 0x1234u) == FRAME_SWAP_ERR_INVALID_ARG);

    assert(frame_swap_init(&fs, FB_A, FB_B, FB_A) == FRAME_SWAP_OK);
    assert(fs.state == FRAME_SWAP_IDLE);
    assert(fs.owner == FRAME_PRODUCER_NONE);
    assert(frame_swap_front(&fs) == FB_A);
    assert(fs.swap_count == 0u);
    assert(fs.dropped_count == 0u);

    /* 从 B 当前前台开始也合法 */
    assert(frame_swap_init(&fs, FB_A, FB_B, FB_B) == FRAME_SWAP_OK);
    assert(frame_swap_front(&fs) == FB_B);

    printf("[PASS] 换帧状态机初始化与参数校验\n");
}


/* ------------------------------------------------------------------ */
/* 2. 后台授权：永远不是当前前台，且同一时刻只有一个所有者             */
/* ------------------------------------------------------------------ */

static void test_acquire_back(void)
{
    frame_swap_t fs;
    uintptr_t back = 0;

    platform_reset();
    (void)frame_swap_init(&fs, FB_A, FB_B, FB_A);

    assert(frame_swap_acquire_back(0, FRAME_PRODUCER_UDP, &back)
           == FRAME_SWAP_ERR_INVALID_ARG);
    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_NONE, &back)
           == FRAME_SWAP_ERR_INVALID_ARG);
    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_UDP, 0)
           == FRAME_SWAP_ERR_INVALID_ARG);

    /* 前台是 A，拿到的后台必须是 B —— 结构上不可能拿到正在扫描的那块 */
    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_UDP, &back) == FRAME_SWAP_OK);
    assert(back == FB_B);
    assert(fs.state == FRAME_SWAP_PRODUCING);
    assert(fs.owner == FRAME_PRODUCER_UDP);

    /* 已经有一个生产者持有后台：再来一个必须被拒，而且不能抢占 */
    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_BITBLT, &back)
           == FRAME_SWAP_ERR_BUSY);
    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_UDP, &back)
           == FRAME_SWAP_ERR_BUSY);

    printf("[PASS] 后台授权排他且不等于当前前台\n");
}


/* ------------------------------------------------------------------ */
/* 3. 坏帧绝不上屏                                                     */
/* ------------------------------------------------------------------ */

static void test_bad_frame_never_swaps(void)
{
    frame_swap_t fs;
    uintptr_t back = 0;

    platform_reset();
    (void)frame_swap_init(&fs, FB_A, FB_B, FB_A);

    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_UDP, &back) == FRAME_SWAP_OK);

    /* 生产者报告这一帧不完整（字节数不对 / 序号错 / FIFO 溢出 / BRESP 出错） */
    assert(frame_swap_producer_done(&fs, FRAME_PRODUCER_UDP, 0)
           == FRAME_SWAP_ERR_FRAME_BAD);

    /* 前台一个字节都没动，后台被释放，坏帧计入统计 */
    assert(frame_swap_front(&fs) == FB_A);
    assert(fs.state == FRAME_SWAP_IDLE);
    assert(fs.dropped_count == 1u);
    assert(fs.swap_count == 0u);

    /* 没有 READY 状态，提交必须被拒 */
    assert(frame_swap_submit(&fs, TIMEOUT_TICKS) == FRAME_SWAP_ERR_NOT_READY);

    /* 生产者报完成时不是当前所有者：同样是拒绝 */
    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_UDP, &back) == FRAME_SWAP_OK);
    assert(frame_swap_producer_done(&fs, FRAME_PRODUCER_BITBLT, 1)
           == FRAME_SWAP_ERR_WRONG_OWNER);
    assert(frame_swap_producer_done(&fs, FRAME_PRODUCER_NONE, 1)
           == FRAME_SWAP_ERR_WRONG_OWNER);

    printf("[PASS] 坏帧不提交、生产者身份必须匹配\n");
}


/* ------------------------------------------------------------------ */
/* 4. 提交顺序：确认 FRONT_ADDR 之前旧前台不可复用                     */
/* ------------------------------------------------------------------ */

static void test_old_front_not_reusable_before_confirm(void)
{
    frame_swap_t fs;
    uintptr_t back = 0;
    uintptr_t again = 0;

    platform_reset();
    (void)frame_swap_init(&fs, FB_A, FB_B, FB_A);

    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_BITBLT, &back) == FRAME_SWAP_OK);
    assert(back == FB_B);
    assert(frame_swap_producer_done(&fs, FRAME_PRODUCER_BITBLT, 1) == FRAME_SWAP_OK);

    /*
     * 关键断言：生产者已完成、但还没提交换帧。
     * 此刻 A 仍然是正在扫描的前台，所以任何人都不能拿到它 ——
     * 包括"再申请一次后台"这种看上去无害的调用。
     */
    assert(fs.state == FRAME_SWAP_READY);
    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_UDP, &again)
           == FRAME_SWAP_ERR_BUSY);

    /* 时间也不许推进状态：状态机不接受"等一会儿就好了" */
    g_fake_ticks += 10000000ULL;
    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_UDP, &again)
           == FRAME_SWAP_ERR_BUSY);

    /* 正常提交后才回到 IDLE，此时新前台是 B，可复用的是 A */
    assert(frame_swap_submit(&fs, TIMEOUT_TICKS) == FRAME_SWAP_OK);
    assert(frame_swap_front(&fs) == FB_B);
    assert(fs.swap_count == 1u);
    assert(fs.state == FRAME_SWAP_IDLE);

    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_UDP, &again) == FRAME_SWAP_OK);
    assert(again == FB_A);

    printf("[PASS] 确认 FRONT_ADDR 之前旧前台不可复用\n");
}


/* ------------------------------------------------------------------ */
/* 5. 只有回读 FRONT_ADDR 才算确认                                     */
/* ------------------------------------------------------------------ */

static void test_front_readback_is_authoritative(void)
{
    frame_swap_t fs;
    uintptr_t back = 0;

    platform_reset();
    (void)frame_swap_init(&fs, FB_A, FB_B, FB_A);

    /*
     * SWAP_DONE 置位（wait_swap 返回 OK），但 FRONT_ADDR 没跟着变。
     * 状态位和实际扫描基址是两个事实，后者才作数。
     */
    display_test_set_swap_updates_front(0);

    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_BITBLT, &back) == FRAME_SWAP_OK);
    assert(frame_swap_producer_done(&fs, FRAME_PRODUCER_BITBLT, 1) == FRAME_SWAP_OK);

    assert(frame_swap_submit(&fs, TIMEOUT_TICKS) == FRAME_SWAP_ERR_FRONT_UNCHANGED);
    assert(fs.state == FRAME_SWAP_FAILED);
    assert(fs.last_error == FRAME_SWAP_ERR_FRONT_UNCHANGED);

    /* 失败状态下不许再授权任何 buffer：硬件可能已经扫上了 pending 那块 */
    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_UDP, &back)
           == FRAME_SWAP_ERR_FAILED_STATE);
    assert(frame_swap_producer_done(&fs, FRAME_PRODUCER_BITBLT, 1)
           == FRAME_SWAP_ERR_FAILED_STATE);

    /* resolve：前台确实没换，保持原值，回到 IDLE 让上层能继续 */
    assert(frame_swap_resolve_failure(&fs) == FRAME_SWAP_ERR_FRONT_UNCHANGED);
    assert(frame_swap_front(&fs) == FB_A);
    assert(fs.state == FRAME_SWAP_IDLE);

    printf("[PASS] FRONT_ADDR 回读是唯一判据\n");
}


static void test_timeout_and_late_swap(void)
{
    frame_swap_t fs;
    uintptr_t back = 0;

    /* --- 超时，且硬件确实没换 --- */
    platform_reset();
    (void)frame_swap_init(&fs, FB_A, FB_B, FB_A);

    display_test_set_swap_ok(0);   /* wait_swap 返回 ETIMEOUT */

    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_UDP, &back) == FRAME_SWAP_OK);
    assert(frame_swap_producer_done(&fs, FRAME_PRODUCER_UDP, 1) == FRAME_SWAP_OK);

    assert(frame_swap_submit(&fs, TIMEOUT_TICKS) == FRAME_SWAP_ERR_TIMEOUT);
    assert(fs.state == FRAME_SWAP_FAILED);
    assert(frame_swap_front(&fs) == FB_A);   /* 保留原前台 */
    assert(fs.dropped_count == 1u);

    assert(frame_swap_resolve_failure(&fs) == FRAME_SWAP_ERR_FRONT_UNCHANGED);
    assert(frame_swap_front(&fs) == FB_A);

    /* --- 超时，但硬件其实换过去了 --- */
    platform_reset();
    (void)frame_swap_init(&fs, FB_A, FB_B, FB_A);

    display_test_set_swap_ok(0);
    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_UDP, &back) == FRAME_SWAP_OK);
    assert(frame_swap_producer_done(&fs, FRAME_PRODUCER_UDP, 1) == FRAME_SWAP_OK);
    assert(frame_swap_submit(&fs, TIMEOUT_TICKS) == FRAME_SWAP_ERR_TIMEOUT);

    /* 只是没读到确认：回读发现前台已经在 B 上了 */
    display_test_set_front((uint32_t)FB_B);
    assert(frame_swap_resolve_failure(&fs) == FRAME_SWAP_OK);
    assert(frame_swap_front(&fs) == FB_B);
    assert(fs.swap_count == 1u);
    assert(fs.state == FRAME_SWAP_IDLE);

    /* resolve 之后可复用的是 A */
    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_UDP, &back) == FRAME_SWAP_OK);
    assert(back == FB_A);

    printf("[PASS] 超时与「硬件已换但没读到确认」两种结局分别处理\n");
}


static void test_ping_pong(void)
{
    frame_swap_t fs;
    uintptr_t back = 0;

    platform_reset();
    (void)frame_swap_init(&fs, FB_A, FB_B, FB_A);

    /*
     * 连续换 4 帧：起始前台是 A，所以第 0 帧画到 B、换完前台变 B；
     * 第 1 帧画到 A、换完前台变 A，如此往复。
     */
    for (int i = 0; i < 4; i++)
    {
        uintptr_t expect = ((i % 2) == 0) ? FB_B : FB_A;

        assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_BITBLT, &back) == FRAME_SWAP_OK);
        assert(back == expect);
        assert(frame_swap_producer_done(&fs, FRAME_PRODUCER_BITBLT, 1) == FRAME_SWAP_OK);
        assert(frame_swap_submit(&fs, TIMEOUT_TICKS) == FRAME_SWAP_OK);
        assert(frame_swap_front(&fs) == expect);
    }

    assert(fs.swap_count == 4u);
    assert(fs.dropped_count == 0u);
    assert(fs.state == FRAME_SWAP_IDLE);

    /* 提交参数校验 */
    assert(frame_swap_submit(&fs, 0u) == FRAME_SWAP_ERR_NOT_READY);
    assert(frame_swap_submit(0, TIMEOUT_TICKS) == FRAME_SWAP_ERR_INVALID_ARG);

    printf("[PASS] 连续换帧 A/B 交替\n");
}


/* ------------------------------------------------------------------ */
/* 6. 未冻结协议项必须走能力检测                                       */
/* ------------------------------------------------------------------ */

static void test_udp_completion_still_unfrozen(void)
{
    frame_swap_t fs;
    uintptr_t back = 0;
    protocol_caps_t caps;

    platform_reset();
    (void)frame_swap_init(&fs, FB_A, FB_B, FB_A);

    /*
     * 协议已冻结两项（FORMAT 枚举 + 两个 VERSION），但 UDP 完成通知
     * 的寄存器/中断/ACK 仍然【没有分配】—— 这一项还是 UNKNOWN。
     */
    assert(protocol_caps_get()->udp_completion == PROTOCOL_CAP_UNKNOWN);
    assert(protocol_caps_get()->udp_completion_reg_addr == 0u);
    assert(protocol_udp_completion_available() == 0);

    /* UDP 通路整个不存在：即使生产者已经就位也不接受它的完成通知 */
    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_UDP, &back) == FRAME_SWAP_OK);
    assert(frame_swap_udp_frame_ready(&fs, back, 1) == FRAME_SWAP_ERR_NOT_READY);
    assert(frame_swap_front(&fs) == FB_A);
    assert(fs.swap_count == 0u);

    /* 声称支持却给不出地址：仍然按不可用处理，绝不能去读 0 地址 */
    protocol_caps_reset(&caps);
    caps.udp_completion = PROTOCOL_CAP_YES;
    caps.udp_completion_reg_addr = 0u;
    protocol_caps_set(&caps);
    assert(protocol_udp_completion_available() == 0);

    protocol_caps_reset(0);

    printf("[PASS] UDP V2.0 尚未接入时一律走能力检测\n");
}


/* ------------------------------------------------------------------ */
/* 6b. 已冻结的 FORMAT 与 VERSION                                      */
/* ------------------------------------------------------------------ */

static void test_display_init_format_and_version(void)
{
    platform_reset();

    /* 协议已冻结：默认格式不再有"未知"这个状态 */
    assert(PROTO_DISPLAY_FORMAT_XRGB8888 == 0u);
    assert(PROTO_DISPLAY_FORMAT_RGB565 == 1u);
    assert(proto_display_format_default() == 1u);
    assert(proto_display_format_default() == PROTO_DISPLAY_FORMAT_RGB565);

    /* XRGB8888 = 0 只是历史兼容枚举，不是当前默认 */
    assert(proto_display_format_default() != PROTO_DISPLAY_FORMAT_XRGB8888);

    /* 版本兼容判断：完整 32 位比较，不是只比主版本 */
    assert(proto_display_version_compatible(PROTO_DISPLAY_VERSION_RGB565) == 1);
    assert(proto_bitblt_version_compatible(PROTO_BITBLT_VERSION_RGB565) == 1);

    assert(proto_display_version_compatible(0x00030001u) == 0);  /* 次版本不同 */
    assert(proto_display_version_compatible(0x00020000u) == 0);  /* 主版本不同 */
    assert(proto_display_version_compatible(0u) == 0);
    /* B 当前 XRGB8888 位流的 BitBlt 版本（0x00010004），不是本工程要的 */
    assert(proto_bitblt_version_compatible(0x00010004u) == 0);

    printf("[PASS] FORMAT 与 VERSION 已冻结（默认 RGB565，版本比完整 32 位）\n");
}


static void test_display_init_writes_frozen_format(void)
{
    const display_call_record_t *rec;

    platform_reset();
    display_test_set_version(PROTO_DISPLAY_VERSION_RGB565);
    display_test_clear_call();

    assert(frame_swap_display_init(FB_A) == FRAME_SWAP_OK);
    assert(frame_swap_last_display_version() == PROTO_DISPLAY_VERSION_RGB565);

    rec = display_last_call();
    assert(rec != 0);

    /* 这就是本次冻结的核心：FORMAT 写的是 RGB565 = 1 */
    assert(rec->format == PROTO_DISPLAY_FORMAT_RGB565);
    assert(rec->format == 1u);

    /* 几何来自 framebuffer_format.h，不是另抄的数字 */
    assert(rec->width == FMT_WIDTH);
    assert(rec->height == FMT_HEIGHT);
    assert(rec->stride == FMT_STRIDE);
    assert(rec->front_addr == (uint32_t)FB_A);

    printf("[PASS] 显示初始化写 FORMAT=1(RGB565) 与现行几何\n");
}


static void test_display_init_rejects_wrong_version(void)
{
    static const uint32_t bad[] =
    {
        0x00010004u,   /* B 当前 XRGB8888 位流 V0.4 */
        0x00020000u,   /* 显示 V0.2 的旧版本号（数值上与 BitBlt V2.0 巧合） */
        0x00030001u,   /* 主版本对、次版本不对 */
        0x00040000u,   /* 主版本更高但未验证 */
        0u             /* 读不到（未声明总线路径时就是这个值） */
    };

    for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); i++)
    {
        platform_reset();
        display_test_set_version(bad[i]);
        display_test_clear_call();

        assert(frame_swap_display_init(FB_A) == FRAME_SWAP_ERR_VERSION_MISMATCH);
        assert(frame_swap_last_display_version() == bad[i]);

        /*
         * 关键：版本不对时【一个配置寄存器都不许写】。
         * 按 RGB565 去配置一个 XRGB8888 位流不会报错，只会画一屏乱码。
         */
        assert(display_last_call() == 0);
    }

    /* 未声明总线路径时读不到版本，同样按不匹配处理 */
    platform_reset();
    display_test_set_version(PROTO_DISPLAY_VERSION_RGB565);
    display_set_bus_path_axi();          /* 先声明回来，确认正常路径是通的 */
    assert(frame_swap_display_init(FB_A) == FRAME_SWAP_OK);

    printf("[PASS] 显示版本不匹配时 fail-fast 且不写任何寄存器\n");
}


static void test_udp_reported_base_must_match(void)
{
    frame_swap_t fs;
    uintptr_t back = 0;
    protocol_caps_t caps;

    platform_reset();
    (void)frame_swap_init(&fs, FB_A, FB_B, FB_A);

    /* 模拟"UDP 完成通知地址已分配"这一未来状态，验证授权校验逻辑 */
    protocol_caps_reset(&caps);
    caps.udp_completion = PROTOCOL_CAP_YES;
    caps.udp_completion_reg_addr = 0x04000100u;   /* 测试用假地址，非协议值 */
    protocol_caps_set(&caps);

    assert(protocol_udp_completion_available() == 1);

    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_UDP, &back) == FRAME_SWAP_OK);
    assert(back == FB_B);

    /*
     * 硬件报回来的实际写入基址不是软件授权的那一块：
     * 说明有人在写没被授权的 buffer（例如网络包自带的 slot），
     * 直接按坏帧处理，不能提交换帧。
     */
    assert(frame_swap_udp_frame_ready(&fs, FB_A, 1) == FRAME_SWAP_ERR_WRONG_OWNER);
    assert(frame_swap_front(&fs) == FB_A);
    assert(fs.dropped_count == 1u);
    assert(fs.state == FRAME_SWAP_IDLE);

    /* 基址对得上但帧不完整：按坏帧处理 */
    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_UDP, &back) == FRAME_SWAP_OK);
    assert(frame_swap_udp_frame_ready(&fs, back, 0) == FRAME_SWAP_ERR_FRAME_BAD);
    assert(frame_swap_front(&fs) == FB_A);

    /* 完整可显示：放行 */
    assert(frame_swap_acquire_back(&fs, FRAME_PRODUCER_UDP, &back) == FRAME_SWAP_OK);
    assert(frame_swap_udp_frame_ready(&fs, back, 1) == FRAME_SWAP_OK);
    assert(fs.state == FRAME_SWAP_READY);
    assert(frame_swap_submit(&fs, TIMEOUT_TICKS) == FRAME_SWAP_OK);
    assert(frame_swap_front(&fs) == FB_B);

    protocol_caps_reset(0);

    printf("[PASS] UDP 实际写入基址必须等于软件授权的后台\n");
}


/* ------------------------------------------------------------------ */
/* 7. 诊断字符串                                                       */
/* ------------------------------------------------------------------ */

static void test_strings(void)
{
    assert(strcmp(frame_swap_strstate(FRAME_SWAP_IDLE), "IDLE") == 0);
    assert(strcmp(frame_swap_strstate(FRAME_SWAP_REQUESTED), "REQUESTED") == 0);
    assert(strcmp(frame_swap_strstate(FRAME_SWAP_FAILED), "FAILED") == 0);
    assert(strcmp(frame_swap_strstatus(FRAME_SWAP_OK), "OK") == 0);
    assert(strcmp(frame_swap_strstatus(FRAME_SWAP_ERR_FRAME_BAD), "FRAME_BAD") == 0);
    assert(strcmp(frame_swap_strstatus(FRAME_SWAP_ERR_FRONT_UNCHANGED),
                  "FRONT_UNCHANGED") == 0);
    assert(strcmp(frame_swap_strstatus(FRAME_SWAP_ERR_VERSION_MISMATCH),
                  "VERSION_MISMATCH") == 0);

    printf("[PASS] 换帧状态与错误码字符串\n");
}


/* ------------------------------------------------------------------ */

int main(void)
{
    setvbuf(stdout, 0, _IONBF, 0);

    test_init();
    test_acquire_back();
    test_bad_frame_never_swaps();
    test_old_front_not_reusable_before_confirm();
    test_front_readback_is_authoritative();
    test_timeout_and_late_swap();
    test_ping_pong();
    test_udp_completion_still_unfrozen();
    test_display_init_format_and_version();
    test_display_init_writes_frozen_format();
    test_display_init_rejects_wrong_version();
    test_udp_reported_base_must_match();
    test_strings();

    printf("\nAll frame swap tests passed.\n");

    return 0;
}
