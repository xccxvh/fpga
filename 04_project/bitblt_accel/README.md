# BitBlt Accelerator

赛题二正式工程。当前 MVP 验证 RISC-V 通过 `SYSTEM_AXI_A` 配置寄存器、
读取状态并接收完成中断，尚未连接 DDR 数据搬运核心。

基地址为 `0xE1000000`。寄存器依次为 CONTROL `0x00`、STATUS `0x04`、
SRC_ADDR `0x08`、DST_ADDR `0x0C`、WIDTH `0x10`、HEIGHT `0x14`、
SRC_STRIDE `0x18`、DST_STRIDE `0x1C`、COLOR `0x20`、OPERATION `0x24`
和 VERSION `0x28`。CONTROL bit0 为 START、bit1 为 CLEAR；STATUS bit0~2
依次为 BUSY、DONE、ERROR；OPERATION 目前定义 0 为 Fill、1 为 Copy。

## 当前验证结果

- RISC-V 软件编译：通过，使用 RAM 约 6.2 KiB。
- Efinity 2026.1 Map、Interface、PnR、位流生成：通过。
- 最差 Setup 余量：约 0.268 ns。
- 最差 Hold 余量：约 0.026 ns。
- 寄存器读回、BUSY 到 DONE 状态变化及完成中断：板测通过。

串口预期输出：

```text
*** BitBlt Control MVP ***
Register readback: PASSED
Status transition: PASSED
Completion IRQ: PASSED
*** BitBlt Control MVP PASSED ***
```

## 创建 FPGA 工作副本

```bash
cp -a local/vendor_original/Ti60F225_DemoBoard_v4/08_ti60f225_soc_demo/09_Ti60F225_hardjtag_demo \
      local/riscv_work/bitblt_mvp
cp -a project/04_project/bitblt_accel/hw/efinity/overlay/. \
      local/riscv_work/bitblt_mvp/
cp project/04_project/bitblt_accel/hw/rtl/bitblt_ctrl_axi.v \
   local/riscv_work/bitblt_mvp/rtl/
```

进入 `local/riscv_work/bitblt_mvp/par/ddr_demo_ti60`，加载 Efinity
`setup.sh` 后执行：

```bash
efx_run --prj -f compile ddr_demo_ti60
```

下一版本用真正的 DDR Fill 引擎替代八周期 Stub。
