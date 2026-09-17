# BitBlt Accelerator

赛题二正式 BitBlt 工程。RISC-V 通过 `SYSTEM_AXI_A` 配置寄存器，硬件引擎
作为第二个 AXI 主机访问 DDR，并通过状态寄存器和 PLIC 中断报告完成。

当前版本 `0x00010003` 已实现 Solid Fill 和带内部 16×128-bit 缓冲的 Block
Copy。CPU 与引擎分别通过读、写两组 2-to-1 AXI 仲裁器共享 DDR 数据通路。

完整软硬件约定见 `../../07_docs/interfaces/bitblt_interface_v0.2.md`。

## 当前板测结果

- RISC-V 软件使用 GCC 13.4 编译通过，测试程序约 6480 B / 124 KiB。
- Efinity 2026.1 Map、Interface、PnR、PGM 全流程通过。
- 最差 Setup 余量约 0.306 ns，最差 Hold 余量约 0.026 ns。
- Solid Fill：寄存器、BUSY/DONE、PLIC 中断和 240 像素 DDR 回读通过。
- Block Copy：80×3 像素、源 stride 384 B、目标 stride 416 B，240 像素逐项回读通过。
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

第一阶段 RTL 已完成并通过独立仿真：

- `SYSTEM_AXI_A` 按 `0xE100_0000` / `0xE110_0000` 隔离 BitBlt 与显示控制；
  未映射访问返回 `DECERR`。
- 显示控制器实现双缓冲、VBlank 原子换帧、帧计数、欠载计数和中断。
- 128-bit DDR 读 DMA 支持二维 stride、最多 16 beat Burst、4 KiB 边界拆包。
- 512×128-bit 异步 FIFO 可缓存 2048 像素，跨越 100 MHz DDR 与
  25.2 MHz 像素时钟域。
- 640×480p60 负极性同步时序和 little-endian XRGB8888 像素拆包已完成。
- `framebuffer_display.v` 已把控制、DMA、FIFO、时序和像素通路封装；下一阶段
  是并入厂家 DDR 顶层、增加第三路 DDR 读仲裁并合并 HDMI TX PLL/LVDS 外设。

以上目前是仿真通过状态，尚不能标记为 HDMI 板测通过。

## 当前限制

- 一个像素固定为 32 bit；颜色通道顺序由显示集成接口另行冻结。
- SRC、DST、SRC_STRIDE、DST_STRIDE 必须 16 字节对齐。
- WIDTH 单位为像素且必须为 4 的整数倍；HEIGHT 必须非零。
- stride 单位为字节，且不得小于 `WIDTH * 4`。
- Copy 不提供重叠区域的 `memmove` 语义。
- 当前缓冲按“读完一个 Burst 后再写一个 Burst”工作，还没有命令 FIFO。
- HDMI TX PLL/LVDS 引脚与 DDR/RISC-V 工程尚未完成联合编译和板测。
- 还没有完成 CPU 绘制与 BitBlt 绘制的端到端显示性能对比。

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
