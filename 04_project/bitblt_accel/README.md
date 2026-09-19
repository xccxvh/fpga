# BitBlt Accelerator

赛题二正式 BitBlt 工程。RISC-V 通过 `SYSTEM_AXI_A` 配置寄存器，硬件引擎
作为第二个 AXI 主机访问 DDR，并通过状态寄存器和 PLIC 中断报告完成。

当前已板测版本 `0x00010004` 已实现 Solid Fill、带内部 16×128-bit 缓冲的 Block
Copy 及 XRGB8888 Color Key Copy。CPU 与引擎分别通过读、写两组 2-to-1 AXI
仲裁器共享 DDR 数据通路。

团队联合接口以
[`../../07_docs/interfaces/unified_fpga_interface_spec_v1.2.md`](../../07_docs/interfaces/unified_fpga_interface_spec_v1.2.md)
为唯一依据。本目录当前 RTL、位流和大部分测试仍是历史 XRGB8888/1080p V0.4 实现，
不能按规范中的 RGB565/720p BitBlt V2.0、Display V3.0 使用。

V1.2 没有修改 BitBlt/Display 的寄存器 ABI，但确认联合 SoC 已启用 D-cache。CPU 写源数据后
不能把普通 `fence rw,rw` 当作完整同步；正式驱动必须通过平台层
`dma_sync_for_device()`/`dma_sync_for_cpu()` 交接共享 DDR 范围。

迁移时必须保持旧回归可运行，但不得从旧 RTL/头文件反向修改统一协议。完成标志是共享头文件、
RTL、C 驱动、模块仿真、联合仿真和目标板结果同时符合规范，而不是只修改 VERSION 常量。

## 当前板测结果

- RISC-V 软件使用 GCC 13.4 编译通过，测试程序约 6480 B / 124 KiB。
- Efinity 2026.1 Map、Interface、PnR、PGM 全流程通过。
- 1080p60 联合工程最差 Setup 余量约 0.325 ns，最差 Hold 余量约 0.026 ns；
  HDMI 像素域 Setup/Hold 余量分别约 2.542 ns/0.042 ns。
- Solid Fill：寄存器、BUSY/DONE、PLIC 中断和 240 像素 DDR 回读通过。
- Block Copy：80×3 像素、源 stride 384 B、目标 stride 416 B，240 像素逐项回读通过。
- Color Key：20×5 像素 DDR 回读通过，RGB 键值忽略 X 字节；目标 padding、
  哨兵和完成中断均通过。
- V0.4 详细板测证据及旧功能待复测状态见
  `../../07_docs/test_records/2026-09-18_bitblt_color_key_v0.4.md`。
- 每次 AXI Burst 最多 16 个 128-bit beat，并自动避免跨越 4 KiB 边界。
- `hw/sim` 自检回归已覆盖 Fill/Copy、Burst边界、backpressure、非法参数、
  AXI错误响应和读写仲裁。

Block Copy 板测串口输出：

```text
*** BitBlt Block Copy MVP ***
CPU DDR writes: ISSUED
Source pattern: PREPARED
Register readback: PASSED
Status transition: PASSED
Completion IRQ: PASSED
DDR Copy burst readback: PASSED (240 pixels)
*** BitBlt Block Copy MVP PASSED ***
```

## Framebuffer 显示集成进度

显示 RTL、DDR/RISC-V 顶层和 HDMI TX 已完成第一次联合集成：

- `SYSTEM_AXI_A` 按 `0xE100_0000` / `0xE110_0000` 隔离 BitBlt 与显示控制；
  未映射访问返回 `DECERR`。
- 显示控制器实现双缓冲、VBlank 原子换帧、帧计数、欠载计数和中断。
- 历史显示控制器已补控制面保护：enabled 时拒绝几何/格式改写，PENDING 时拒绝关闭显示
  或改写 NEXT_ADDR，请求时锁存目标并自动清旧 `SWAP_DONE`；固定 stride 只接受 7680 B。
  这些修改不改变其 V0.2/1080p/XRGB8888 身份。
- 128-bit DDR 读 DMA 支持二维 stride、最多 64 beat Burst、4 KiB 边界拆包。
- 512×128-bit 异步 FIFO 可缓存 2048 像素，跨越 100 MHz DDR 与
  约148.75 MHz像素时钟域。
- 已改用测试屏确认兼容的CTA-861 1920×1080p60时序和little-endian
  XRGB8888像素拆包。
- `framebuffer_display.v` 已把控制、DMA、FIFO、时序和像素通路封装。
- `bitblt_display_subsystem.v` 统一完成 `SYSTEM_AXI_A` 地址分发以及 BitBlt、
  显示寄存器控制。
- 厂家 DDR/RISC-V 顶层已加入第三路 DDR 读仲裁；两级读仲裁均按Burst边界
  round-robin，已接受的Burst保持所有权直到`RLAST`，避免显示持续请求造成
  CPU/BitBlt饥饿。
- 已合并官方 HDMI TX 的 DVI Encoder、148.75/743.75 MHz PLL 和 LVDS 引脚定义。
- 隔离工作副本位于 `local/riscv_work/bitblt_display_mvp`，不修改稳定的
  `bitblt_mvp` 和厂家原始 Demo。
- 640×480版本曾通过Efinity全流程，但测试屏不接受该输入；1080p60版本已完成
  Efinity全流程、时序检查和板端自动测试。
- `framebufferSmokeDemo` 已编译通过，用于绘制两组彩条、启动扫描输出并验证
  VBlank 双缓冲切换。

组合 bitstream 已通过 JTAG SRAM 下载且能识别 RISC-V Debug TAP。
`framebufferSmokeDemo` 完成寄存器译码、BitBlt绘制Framebuffer A/B、A扫描及
VBlank A→B换帧验证，串口全部返回`PASSED`。最初16-beat显示读Burst在1080p
下发生欠流；改为64 beat后持续扫描1561帧，`UNDERFLOW_COUNT=0`。目标屏已
目视确认显示Framebuffer B的8条竖向彩条。
- BitBlt与显示控制共享PLIC源30的判源通过：16次BitBlt完成中断及VBlank换帧
  中断均由同一ISR正确识别和清除。
- 32帧并发压力通过：HDMI持续扫描前台、BitBlt整帧写后台、CPU读取Scratch
  DDR并逐帧中断换页；测试后`UNDERFLOW_COUNT=0`，最终恢复8条竖向彩条。
- 3600帧并发老化通过：连续3600次全屏Fill、共享中断及VBlank换页，显示计数
  增加3600帧且`UNDERFLOW_COUNT=0`，结束后竖向彩条恢复正确。
- CPU/BitBlt性能对比通过：1080p Fill为37.39/657.99 MiB/s（17.59×），
  Copy为15.87/127.62 MiB/s（8.04×）；测试期间显示扫描74帧且零欠流。

以上是历史带宽基线，不等同于赛题要求的实时 FPS 对比。V1.2 最终 Demo 仍需在同一
RGB565/720p 场景中并列上屏显示纯 CPU 与 BitBlt FPS，并记录平均值和最低值。

```text
*** BitBlt Framebuffer Smoke Demo ***
Register decode: PASSED
Framebuffer A horizontal bars: READY
Framebuffer A scanout: PASSED
Framebuffer B vertical bars: READY
Shared IRQ BitBlt source: PASSED (16 interrupts)
VBlank A->B swap: PASSED
Shared IRQ display source: PASSED
Concurrent DDR/display stress: PASSED (32 swaps, 32 display frames, 0 underflows)
Vertical color bars restored: PASSED
*** FRAMEBUFFER SMOKE DEMO PASSED ***
```

## 当前限制

- 一个像素固定为 32 bit；颜色通道顺序由显示集成接口另行冻结。
- SRC、DST、SRC_STRIDE、DST_STRIDE 必须 16 字节对齐。
- WIDTH 单位为像素且必须为 4 的整数倍；HEIGHT 必须非零。
- stride 单位为字节，且不得小于 `WIDTH * 4`。
- Copy 不提供重叠区域的 `memmove` 语义。
- 当前缓冲按“读完一个 Burst 后再写一个 Burst”工作，还没有命令 FIFO。
- HDMI TX 与 DDR/RISC-V 已完成联合编译、寄存器/DMA/VBlank 板测及目标屏
  8条竖向彩条目视确认。
- CPU 与 BitBlt 的Fill/Copy端到端性能基线及3600帧并发老化已完成；后续仍需
  进行小时级持续运行测试。

## 创建 FPGA 工作副本

```bash
cp -a local/vendor_original/Ti60F225_DemoBoard_v4/08_ti60f225_soc_demo/09_Ti60F225_hardjtag_demo \
      local/riscv_work/bitblt_mvp
cp -a project/04_project/bitblt_accel/hw/efinity/overlay/. \
      local/riscv_work/bitblt_mvp/
cp project/04_project/bitblt_accel/hw/rtl/*.v \
   local/riscv_work/bitblt_mvp/rtl/
```

进入 `local/riscv_work/bitblt_mvp/par/ddr_demo_ti60`，加载 Efinity
`setup.sh` 后执行：

```bash
efx_run --prj -f compile ddr_demo_ti60
```

软件测试需要把 `sw/driver` 和 `sw/tests/bitbltCtrlDemo` 放入 BSP 工程。
测试源区域为 `0x01100000`，目标区域为 `0x01200000`；这些仅是测试地址，
不是最终 Framebuffer 内存布局。

## 创建显示集成副本

显示集成在新的 `bitblt_display_mvp` 副本中进行，不覆盖已经板测通过的
`bitblt_mvp`：

```bash
cp -a local/riscv_work/bitblt_mvp \
      local/riscv_work/bitblt_display_mvp
cp -a project/04_project/bitblt_accel/hw/efinity/overlay/. \
      local/riscv_work/bitblt_display_mvp/
cp project/04_project/bitblt_accel/hw/rtl/*.v \
   local/riscv_work/bitblt_display_mvp/rtl/
```

然后复制官方 HDMI TX Demo 的 `dvi_encoder.v`、`encode.v` 及其依赖文件，
使用 `hw/efinity/merge_hdmi_peri.py` 把 HDMI PLL/LVDS 定义合入 DDR 工程的
`.peri.xml`，并把 `hw/efinity/display_constraints.sdc` 追加到工程 SDC 后执行：

```bash
efx_run --prj -f compile ddr_demo_ti60
```

本次公平读仲裁版本的 JTAG bitstream SHA-256 为
`0278427468b6080a41b6fcf51a119fc0d8a809e346cb999a218464fb7fcbd659`。

命令行通过 OpenOCD 装载软件时，必须先执行 `soft_reset_halt`；只使用
`halt` 会使 VexRiscv 停在 `PC=0x8`，程序不会进入 `main()`：

```text
soft_reset_halt
load_image build/framebufferSmokeDemo.bin 0x1000 bin
resume 0x1000
```

共享中断测试前应重新JTAG下载bitstream，使SoC和PLIC从干净状态启动；
`soft_reset_halt`只复位CPU，不会复位PLIC及显示外设的历史状态。
