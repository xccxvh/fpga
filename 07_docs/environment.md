# 开发环境

## 统一路径

```text
工作区：/home/user/fpga_workspace
Git 仓库：/home/user/fpga_workspace/project
厂家原始资料：/home/user/fpga_workspace/local/vendor_original/Ti60F225_DemoBoard_v4
本机安装包：/home/user/fpga_workspace/local/installers
```

## 软件版本

```text
Ubuntu 22.04
Efinity 2026.1.132
Efinity RISC-V IDE 2026.1.0.7
```

软件实际安装位置保留为：

```text
/home/user/efinity/2026.1
/home/user/efinity/efinity-riscv-ide-2026.1
```

`/home/user/fpga_workspace/tools/` 中提供软链接，避免搬动已安装软件导致路径失效。

## USB/JTAG

```text
FTDI VID:PID = 0403:6011
UDEV rule = /etc/udev/rules.d/80-efx-pgm.rules
```

JTAG URL 中的 USB Bus/Device 编号会在重新插拔后变化，不能写死。
