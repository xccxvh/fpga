# BitBlt Color Key V0.4 板测与回归记录

- 日期：2026-09-18
- 分支：`feature/bitblt-color-key`
- 位流：`local/riscv_work/bitblt_display_mvp/par/ddr_demo_ti60/outflow/ddr_demo_ti60.bit`
- 位流SHA-256：`079d1d1139ecba0d6dbc260b97c6aaa31eff5458d9fd6ed555a055b3998f1b6d`
- BitBlt版本：`0x00010004`

## 已完成

- Efinity 2026.1 Map、Interface、PnR、PGM全流程通过；最终时序所有setup/hold
  slack为正（core setup `+3.474 ns`、core hold `+0.026 ns`）。
- Icarus Verilog全套八组RTL回归通过，包括Color Key混合像素、Fill/Copy、控制面、
  仲裁、显示控制、DMA、视频时序和异步FIFO。
- `bitbltColorKeyDemo`实板通过：20×5像素，源/目标不同stride，透明源像素
  X字节变化但RGB匹配，目标背景保持；非透明像素完整复制，目标行尾padding和
  前后哨兵保持，完成IRQ/STATUS正确。

```text
*** BitBlt Color Key Demo ***
Source/background pattern: READY
Completion IRQ/status: PASSED
RGB key/X-byte ignore: PASSED
Stride/padding/guards: PASSED
*** BITBLT COLOR KEY DEMO PASSED ***
```

## 待完成

- 已将旧`framebufferSmokeDemo`和`bitbltPerformanceDemo`同步为V0.4版本并在
  本地BSP重新编译通过；但当前虚拟机`lsusb`未枚举开发板FT4232H
  (`0403:6011`)，因此尚未在V0.4位流上复测旧Fill/Copy、HDMI换帧及零欠流。
- Color Key尚未完成Framebuffer可视化验证。
- A组UDP Demo采用1280×720 RGB565，与本分支1920×1080 XRGB8888不是
  同一位流/帧缓冲协议；团队现已确定迁移目标，见
  [`../interfaces/unified_fpga_interface_spec_v1.2.md`](../interfaces/unified_fpga_interface_spec_v1.2.md)，
  但尚未联合板测。

在开发板USB恢复后，先重新JTAG下载上述V0.4位流，每运行一个程序前再次下载
以复位SoC/PLIC/显示外设，然后依次运行`framebufferSmokeDemo`与
`bitbltPerformanceDemo`并补录串口结果。
