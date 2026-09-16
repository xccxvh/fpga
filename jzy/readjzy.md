# jzy 工作区说明

本文件（`jzy/readjzy.md`）是 `jzy/` 目录的 README，负责记录**本目录内部**的工程结构、开发环境、版本基准、编译调试步骤与目录说明。

## 文档分工约定

- **本文 `jzy/readjzy.md`**：负责 `jzy/` 文件夹**内部**的内容。
- **外层仓库 README（`../README.md`）**：负责**对外接口**相关的内容，包括外部端口、管脚分配、接口协议、板级对接约定等。

即：内部实现与开发流程写在这里；凡是涉及**外部端口和协议**的部分，统一写在外层 README，本文件不重复维护。

---

## RISC-V 开发环境与 BSP 版本说明

### 版本基准

本项目后续统一以 **Efinity 2026.1 重新生成的 Sapphire SoC 工程和 BSP** 为开发基准，**不再使用**原始资料包中旧版 **2025.x BSP**。

### 旧版 BSP 的兼容性问题

原资料包中的 `uartEchoDemo` 使用旧工具链前缀 `riscv-none-embed-`，直接在 Efinity RISC-V IDE 2026.1 / GCC 13.4.0 环境下编译会出现兼容性问题，包括：

- 找不到旧编译器（`riscv-none-embed-*` 工具链已不再随 IDE 提供）
- `zicsr` 相关汇编报错

### 重新生成过程

为统一版本，已使用 **Efinity 2026.1.132** 打开并升级原 `ddr_demo_ti60` 工程中的 **Sapphire SoC IP**，在 IP Configuration 中重新 Generate，生成新的：

```
embedded_sw/soc/
├── bsp/
└── software/
```

新生成的软件工程已改用：

```makefile
RISCV_BIN ?= riscv-none-elf-
```

（定义位置：`embedded_sw/soc/software/standalone/common/riscv64-unknown-elf.mk`）

对应本机工具链：

```
/home/jzy/efinity/efinity-riscv-ide-2026.1/toolchain/bin/riscv-none-elf-gcc
```

GCC 版本为：

```
riscv-none-elf-gcc 13.4.0
```

### 编译验证

已在新生成的 2026.1 BSP 下成功编译 `uartEchoDemo`：

```
CC src/main.c
CC ../../common/start.S
CC syscalls.c
LD uartEchoDemo
Memory region         Used Size  Region Size  %age Used
             ram:        6000 B       124 KB      4.73%
```

软件工程位置：`embedded_sw/soc/software/standalone/uart/uartEchoDemo/`

### 后续开发约定

后续 **RISC-V 软件开发、AXI/BitBlt 驱动、游戏 Demo** 等内容，全部基于这套 **2026.1 重新生成的 Sapphire BSP 和 software 工程**继续开发，不要再混用下载资料包中的旧版 2025.x BSP，以避免工具链和启动代码不兼容问题。

### 当前路径基准

| 内容 | 路径 |
|---|---|
| 基准工程目录 | `~/code/fpga/jzy/ddr_demo_ti60_2026/` |
| RISC-V 软件目录 | `~/code/fpga/jzy/ddr_demo_ti60_2026/embedded_sw/soc/software/` |
| BSP 目录 | `~/code/fpga/jzy/ddr_demo_ti60_2026/embedded_sw/soc/bsp/` |

> **注意**：README 中所有后续编译、驱动开发和运行说明，统一按 **2026.1 工程结构**编写，**禁止继续引用旧版 2025 BSP 路径**。
