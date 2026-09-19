/* P1 验证：RISC-V 读写 FPGA 硬件寄存器
 * 目标外设：GPIO0 @ 0xF8015000
 * 方法：写 -> 立刻读回 -> 比对 -> 经 UART 打印结果
 */
#include <stdint.h>
#include "bsp.h"
#include "userDef.h"
#include "gpio.h"

static u32 fails = 0;

static void check(const char *name, u32 wrote, u32 got) {
    if (wrote == got) {
        bsp_printf("  %s  write=0x%x  read=0x%x   OK\r\n", name, wrote, got);
    } else {
        bsp_printf("  %s  write=0x%x  read=0x%x   ** FAIL **\r\n", name, wrote, got);
        fails++;
    }
}

void main() {
    bsp_init();

    bsp_printf("\r\n");
    bsp_printf("*** P1: RISC-V to FPGA register test ***\r\n");
    bsp_printf("GPIO0 base = 0x%x\r\n", GPIO0);

    /* --- 1. 输出使能寄存器 读写 --- */
    gpio_setOutputEnable(GPIO0, 0xE);
    check("ENABLE ", 0xE, gpio_getOutputEnable(GPIO0));

    /* --- 2. 输出寄存器 读写，走几个图样 --- */
    u32 pats[5] = {0x0, 0xE, 0x2, 0xC, 0xA};
    for (int i = 0; i < 5; i++) {
        gpio_setOutput(GPIO0, pats[i]);
        check("OUTPUT ", pats[i], gpio_getOutput(GPIO0));
        bsp_uDelay(200000);          /* 让 LED 肉眼可见 */
    }

    /* --- 3. 输入寄存器（读引脚实际电平，不参与 pass/fail）--- */
    bsp_printf("  INPUT  (pin state) = 0x%x\r\n", gpio_getInput(GPIO0));

    bsp_printf("\r\n");
    if (fails == 0)
        bsp_printf("*** P1 PASSED ***\r\n");
    else
        bsp_printf("*** P1 FAILED: %d errors ***\r\n", fails);

    while (1) { bsp_uDelay(1000000); }
}

/* trap.S 会跳到这个符号；任何异常/中断都停在这里并报出 mcause */
#include "riscv.h"
void trap() {
    int32_t mcause = csr_read(mcause);
    bsp_printf("\r\n*** TRAP! mcause=0x%x ***\r\n", mcause);
    while (1) {}
}
