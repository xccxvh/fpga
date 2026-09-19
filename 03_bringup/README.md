# Board Bring-up Status

本目录的厂家 Demo 和兼容性修改只用于板级 bring-up。联合接口以
[`../07_docs/interfaces/unified_fpga_interface_spec_v1.2.md`](../07_docs/interfaces/unified_fpga_interface_spec_v1.2.md)
为准；官方 Demo 的地址 0、三缓冲、自动换页和 cache 处理方式不能直接成为联合协议。

## 01_led/LED_8bit_Test

- 来源：厂家 `01_Ti60F225_Key_led_osc_demo`
- Efinity 2026.1 完整编译：通过
- JTAG SRAM 下载：通过
- 板上 LED/按键现象：通过

## 06_hdmi_test/hdmi_rx2tx_loop_v19

- 来源：厂家 `02_Ti60F225_hdmi_demo`
- Efinity 2026.1 完整编译：通过
- JTAG SRAM 下载：通过
- 功能状态：通过；电脑 HDMI 输入经开发板环回到显示器，画面正常
- 兼容修改：关闭旧 Debugger 自动实例化；移除未使用的旧 BSCAN 调试接口
- 注意：工程实际输出 `b_led[0:1]` 位于 GPIOR_21/GPIOR_22，厂家手册的 D3/D4 描述与 V4 原理图/工程存在不一致。

## 06_hdmi_test/hdmi_tx_colorbar_v2

- 来源：厂家 `03_Ti60F225_hdmi_tx_demo`
- 厂家原始位流：JTAG 下载通过，但输出约为 1920x1536@44.26 Hz，测试显示器不支持，因而黑屏
- 兼容修改：将视频时序改为 1920x1080@60 Hz，并重新编译
- 板上验证：通过；显示器能稳定显示彩条

## RISC-V Hard-JTAG SoC

测试基于厂家 `09_Ti60F225_hardjtag_demo` 位流，程序由本机 RISC-V GCC 13.4 工具链编译，经 OpenOCD 加载到 `0x1000`。

| 程序 | 结果 | 实测现象 |
|---|---|---|
| `gpioDemo` | 部分通过 | UART、GPIO 闪烁通过；厂家程序所称 SW4 中断不可用，因为当前工程把 `soc_gpio[0]` 接到 LED0/P13，而非按键 |
| `clintTimerInterruptDemo` | 通过 | 串口计数持续递增，定时中断正常 |
| `memTest` | 通过 | 测试 16 MiB DDR，输出 `Data matched .. Test PASSED` |
| `uartEchoDemo` | 通过 | 输入 `Az1` 后逐字符返回 A、z、1 |
| `freertosDemo` | 通过 | 输出 `Hello world, this is FreeRTOS`，并持续输出 `Blink` |
| `apb3Demo` | 厂家软硬件不配套 | 程序运行后读回 `0x00000000` 并报告 `Failed!`；当前 `apb3_top` 未实现示例所需的 LFSR 外设 |
| `axi4Demo` | 修正后通过 | 厂家原工程停在第一次 AXI 写；接入独立 AW/W 握手的 2 KiB AXI RAM 后，读写比较及 AXI 中断均输出 `Passed!` |
| `co_debug_demo` | 未运行（非关键） | 厂家调试配置硬编码 Windows Efinity 2025.2、`.bat` 守护进程及 Windows 路径，需先移植到 Linux 2026.1；不影响当前 Hard-JTAG 开发 |

### 工具链兼容性

厂家 makefile 默认工具前缀与 GCC 13 ISA 规则不兼容。本地工作副本使用 `riscv-none-elf-`，并在 `-march` 中显式加入 `_zicsr_zifencei`。厂家原始目录保持不变。

AXI 修正工程的覆盖文件和复现步骤见 `07_riscv_axi_test/README.md`。
