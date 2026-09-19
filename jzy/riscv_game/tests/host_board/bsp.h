#ifndef HOST_BOARD_STUB_BSP_H
#define HOST_BOARD_STUB_BSP_H

/*
 * 在宿主机上跑板端测试时用的【替身 bsp.h】。
 *
 * 存在的理由：tests/test_bitblt_board.c 只能在有 BSP 的地方编译，
 * 而那需要真板。这份替身让同一份源码在宿主机上原样跑起来，
 * 于是 T0~T3 的判定逻辑、guard 算术、fail-fast 分支在拿到板子之前
 * 就能被验证。
 *
 * 【边界】它不能替代真板：
 *   - 它没有真的 BitBlt 硬件，stub.c 里是一个行为模型；
 *   - 它没有真实的 CLINT，clint_getTime() 走的是软件计数器；
 *   - 它复刻了 BSP lite bsp_printf 的格式符限制，但复刻品终究不是原件。
 * 真板的结论只能由真板给出。
 *
 * 只放 test_bitblt_board.c 真正用到的那些符号，不多不少。
 */

#include <stdint.h>

/* clint_getTime() 的 base 参数在替身里被忽略，取值本身没有意义 */
#define BSP_CLINT     0u
#define BSP_CLINT_HZ  100000000u

void bsp_init(void);
void bsp_printf(const char *format, ...);
void bsp_uDelay(uint32_t usec);
uint64_t clint_getTime(uint32_t base);

#endif
