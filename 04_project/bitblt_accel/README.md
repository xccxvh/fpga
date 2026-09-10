# BitBlt Accelerator

赛题二正式工程。当前 MVP 已连接真实 DDR Fill 数据通路：RISC-V 通过
`SYSTEM_AXI_A` 配置寄存器，硬件引擎作为第二个 AXI 主机写 DDR，并通过
状态寄存器和 PLIC 中断报告完成。

基地址为 `0xE1000000`。寄存器依次为 CONTROL `0x00`、STATUS `0x04`、
SRC_ADDR `0x08`、DST_ADDR `0x0C`、WIDTH `0x10`、HEIGHT `0x14`、
SRC_STRIDE `0x18`、DST_STRIDE `0x1C`、COLOR `0x20`、OPERATION `0x24`
和 VERSION `0x28`。CONTROL bit0 为 START、bit1 为 CLEAR；STATUS bit0~2
依次为 BUSY、DONE、ERROR；OPERATION 目前定义 0 为 Fill、1 为 Copy。

## 当前验证结果

- RISC-V 软件编译：通过，使用片上 RAM 6336 B。
- Efinity 2026.1 Map、Interface、PnR、位流生成：通过。
- 最差 Setup 余量：约 0.323 ns。
- 最差 Hold 余量：约 0.026 ns。
- 寄存器读回、BUSY 到 DONE、完成中断，以及 DDR 中 256 个像素逐项读回：板测通过。

当前 Fill 引擎每次 AXI 事务写入 4 个 32 位像素，支持二维高度和目标行跨度。
第一版要求目标地址与行跨度按 16 字节对齐、宽度为 4 像素的整数倍；Copy
数据通路尚未实现。CPU 与加速器的 DDR 写通道由单事务仲裁器共享，DDR 读
通道仍由 CPU 直接使用。

串口预期输出：

```text
*** BitBlt DDR Fill MVP ***
Register readback: PASSED
Status transition: PASSED
Completion IRQ: PASSED
DDR Fill readback: PASSED (256 pixels)
*** BitBlt DDR Fill MVP PASSED ***
```

## 创建 FPGA 工作副本

```bash
cp -a local/vendor_original/Ti60F225_DemoBoard_v4/08_ti60f225_soc_demo/09_Ti60F225_hardjtag_demo \
      local/riscv_work/bitblt_mvp
cp -a project/04_project/bitblt_accel/hw/efinity/overlay/. \
      local/riscv_work/bitblt_mvp/
cp project/04_project/bitblt_accel/hw/rtl/bitblt_ctrl_axi.v \
   local/riscv_work/bitblt_mvp/rtl/
cp project/04_project/bitblt_accel/hw/rtl/bitblt_fill_engine.v \
   project/04_project/bitblt_accel/hw/rtl/axi_write_arbiter_2to1.v \
   local/riscv_work/bitblt_mvp/rtl/
```

进入 `local/riscv_work/bitblt_mvp/par/ddr_demo_ti60`，加载 Efinity
`setup.sh` 后执行：

```bash
efx_run --prj -f compile ddr_demo_ti60
```

软件测试需要把 `sw/driver` 和 `sw/tests/bitbltCtrlDemo` 放到 BSP 的同一
`bitblt/` 目录下，再使用 RISC-V IDE 工具链编译。板测使用的目标区域为
`0x01200000`，写入 64×4 个 32 位像素，颜色值为 `0xA5C3F00D`。

下一版本应把单拍写升级为 AXI burst，并加入 Copy 的 DDR 读通道。
