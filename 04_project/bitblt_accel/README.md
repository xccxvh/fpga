# BitBlt Accelerator

赛题二正式 BitBlt 工程。RISC-V 通过 `SYSTEM_AXI_A` 配置寄存器，硬件引擎
作为第二个 AXI 主机访问 DDR，并通过状态寄存器和 PLIC 中断报告完成。

当前版本 `0x00010003` 已实现 Solid Fill 和带内部 16×128-bit 缓冲的 Block
Copy。CPU 与引擎分别通过读、写两组 2-to-1 AXI 仲裁器共享 DDR 数据通路。

完整软硬件约定见 `../../07_docs/interfaces/bitblt_interface_v0.1.md`。

## 当前板测结果

- RISC-V 软件使用 GCC 13.4 编译通过，测试程序约 6480 B / 124 KiB。
- Efinity 2026.1 Map、Interface、PnR、PGM 全流程通过。
- 最差 Setup 余量约 0.306 ns，最差 Hold 余量约 0.026 ns。
- Solid Fill：寄存器、BUSY/DONE、PLIC 中断和 240 像素 DDR 回读通过。
- Block Copy：80×3 像素、源 stride 384 B、目标 stride 416 B，240 像素逐项回读通过。
- 板级边界回归：Fill/Copy 护栏、不同 stride、实际跨 4 KiB 地址以及
  640×480 整帧 Copy 全部通过；整帧 Copy 实测约 353.2 MiB/s。
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

## 当前限制

- 一个像素固定为 32 bit；颜色通道顺序由显示集成接口另行冻结。
- SRC、DST、SRC_STRIDE、DST_STRIDE 必须 16 字节对齐。
- WIDTH 单位为像素且必须为 4 的整数倍；HEIGHT 必须非零。
- stride 单位为字节，且不得小于 `WIDTH * 4`。
- Copy 不提供重叠区域的 `memmove` 语义。
- 当前缓冲按“读完一个 Burst 后再写一个 Burst”工作，还没有命令 FIFO。
- Framebuffer、双缓冲、VSync 换帧和 CPU/FPGA 性能对比尚未集成。

## 创建 FPGA 工作副本

```bash
cp -a local/vendor_original/Ti60F225_DemoBoard_v4/08_ti60f225_soc_demo/09_Ti60F225_hardjtag_demo \
      local/riscv_work/bitblt_mvp
cp -a project/04_project/bitblt_accel/hw/efinity/overlay/. \
      local/riscv_work/bitblt_mvp/
cp project/04_project/bitblt_accel/hw/rtl/bitblt_ctrl_axi.v \
   project/04_project/bitblt_accel/hw/rtl/bitblt_engine.v \
   project/04_project/bitblt_accel/hw/rtl/axi_write_arbiter_2to1.v \
   project/04_project/bitblt_accel/hw/rtl/axi_read_arbiter_2to1.v \
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

更完整的板级保护区、跨 4 KiB 和 640×480 吞吐回归位于
`sw/tests/bitbltBoundaryDemo`。该程序已于 2026-09-17 实板通过；运行方法、
实测数据和预期串口输出见其 `README.md`。
