# BitBlt/显示并发老化板测记录

- 日期：2026-09-18
- 开发板：Ti60F225 Demo Board v4
- 位流：公平读仲裁版`ddr_demo_ti60.bit`
- 位流SHA-256：`0278427468b6080a41b6fcf51a119fc0d8a809e346cb999a218464fb7fcbd659`
- 显示：1920×1080@60 Hz，XRGB8888，双Framebuffer
- 测试程序：`framebufferSmokeDemo`
- 构建参数：`STRESS_FRAMES=3600`，`STRESS_REPORT_INTERVAL=600`

## 覆盖内容

每轮读取当前前台地址，BitBlt向后台执行一次1920×1080全屏Fill，同时CPU持续
读取Scratch哨兵；BitBlt完成后校验共享PLIC源30中断，再请求VBlank原子换帧。
连续执行3600轮，并持续检查BitBlt ERROR、未知中断、显示ERROR和UNDERFLOW。

## 板端结果

```text
  stress progress: 600/3600 swaps
  stress progress: 1200/3600 swaps
  stress progress: 1800/3600 swaps
  stress progress: 2400/3600 swaps
  stress progress: 3000/3600 swaps
  stress progress: 3600/3600 swaps
Concurrent DDR/display stress: PASSED (3600 swaps, 3600 display frames, 0 underflows)
Vertical color bars restored: PASSED
*** FRAMEBUFFER SMOKE DEMO PASSED ***
```

结论：3600次全屏BitBlt写、CPU读、显示读、共享IRQ和VBlank换页并发运行通过；
显示帧计数与换页次数一致，欠流计数为0。此结果作为分钟级老化基线，后续仍需
执行小时级持续运行测试。

## 复现构建

在BSP内的`framebufferSmokeDemo`目录执行：

```bash
make clean all BSP=efinix/EfxSapphireSoc \
  RISCV_BIN=/home/user/efinity/efinity-riscv-ide-2026.1/toolchain/bin/riscv-none-elf- \
  CFLAGS_ARGS='-march=rv32im_zicsr -DSTRESS_FRAMES=3600u -DSTRESS_REPORT_INTERVAL=600u'
```

运行前必须重新JTAG下载组合bitstream，保证SoC、PLIC和显示外设处于干净状态。
