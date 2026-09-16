# RISC-V AXI4 RAM 验证

## 结果

- 基础工程：厂家 `09_Ti60F225_hardjtag_demo`
- 厂家原工程：`SYSTEM_AXI_A` 未连接 Slave，官方 `axi4Demo` 停在第一次写访问
- 修正工程：接入 2 KiB、32 位、单拍 AXI4 RAM Slave
- Efinity 2026.1：Map、Interface、PnR、位流生成均通过
- 板上验证：RAM 写入/读回与 AXI 中断均通过

串口预期输出：

```text
axi4 master demo !
Passed!
axi4 master interrupt demo !
Entered AXI Interrupt Routine, Passed!
```

## 覆盖文件

`overlay/` 保留相对于厂家 Hard-JTAG Demo 根目录的路径。先把厂家 Demo
复制成个人工作副本，再用该目录覆盖工作副本：

```bash
cp -a local/vendor_original/Ti60F225_DemoBoard_v4/08_ti60f225_soc_demo/09_Ti60F225_hardjtag_demo \
      local/riscv_work/hardjtag_axi_demo
cp -a project/03_bringup/07_riscv_axi_test/overlay/. \
      local/riscv_work/hardjtag_axi_demo/
```

厂家原目录不要直接修改。若队友的目录布局不同，只需保持 `overlay/` 内部的
相对路径一致。

## 编译

```bash
cd local/riscv_work/hardjtag_axi_demo/par/ddr_demo_ti60
source /path/to/efinity/2026.1/bin/setup.sh
efx_run --prj -f compile ddr_demo_ti60
```

生成位流位于 `outflow/ddr_demo_ti60.bit`。构建产物由 `.gitignore` 排除，
不提交 Git。

## 当前边界

`axi4_ram_slave.v` 面向官方 `write_u32/read_u32` 验证，只支持 `AxLEN=0`
的单拍访问。它已经验证了赛题二需要的 RISC-V 到 FPGA 逻辑控制路径，后续
BitBlt 数据搬运不能直接受限于这块 2 KiB RAM，应使用控制寄存器启动硬件，
由加速器侧主接口访问 DDR 帧缓冲。
