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

---

## jzy/riscv_game — CPU 渲染器（M1）

M1 阶段的 CPU 参考实现，作为后续 RTL 渲染加速器（BitBlt）的比对基准。

### 目录结构

| 目录 | 内容 |
|---|---|
| `render/` | CPU 参考实现：`renderer_sw.h`、`renderer_sw.c`（Solid Fill + Block Copy） |
| `tests/` | 正确性基线测试与 Makefile |
| `driver/` | AXI / BitBlt 寄存器驱动（待填） |
| `input/` | 输入处理（待填） |
| `game/` | 游戏逻辑（待填） |
| `perf/` | 性能对比测试（待填） |

### 测试与构建

```bash
cd jzy/riscv_game/tests
make native-test    # 本机编译（严格警告 + ASan/UBSan）并运行全部测试
make riscv-build    # RISC-V 交叉编译验证（rv32im_zicsr_zifencei / ilp32）
make clean          # 删除构建产物
```

- `make native-test` 用 `-Wall -Wextra -Wpedantic -Werror`，并固定开启
  ASan + UBSan（`-fno-sanitize-recover=all`，UBSan 命中直接终止而不是打完警告继续跑）。
- `make riscv-build` 的 `-march/-mabi` 取自 2026.1 BSP 实际产物的
  `Tag_RISCV_arch`（`rv32i2p1_m2p0_zicsr2p0_zifencei2p0_zmmul1p0`，ABI `ilp32`）。
  换 BSP 时可用 `make riscv-build RV_ARCH=... RV_ABI=...` 覆盖。
  这个目标只证明能编能链，产物不在本机运行。

### 测试覆盖范围

`test_renderer.c` 是本项目 CPU 渲染结果的判定基准，覆盖：

1. 基础绘制：完全落在屏幕内的填充与拷贝
2. 裁剪：负坐标、右下越界、完全在屏幕外、宽高 <= 0、正好贴合画布边界
3. `stride != width`：画布行尾 padding、源图行尾 padding、源与目标 stride 三方都不同
4. 越界保护：画布四周预留保护区，任何越界写都会被检出
5. 空指针：不得崩溃，也不得写内存

越界检测分两层，缺一不可：

- **保护区**：画布 stride 故意取 20（比有效宽度 16 大），底部多留 4 行，
  padding 区全部填 `0xDEAD`。它只能发现**落在数组内部**的越界写。
- **ASan**：负责发现写到**数组之外**的越界。保护区覆盖不到这部分。

### 构建约束：测试构建禁止定义 NDEBUG

**测试依赖 `assert` 判定结果，任何测试构建都不得定义 `NDEBUG`。**

定义了 `NDEBUG` 时，`assert` 会被展开成空语句，所有断言被整体移除。
此时测试一条都不检查，却仍然打印 `All renderer tests passed.` 并返回退出码 0
——属于**假通过**，比直接报错危险得多。

`test_renderer.c` 顶部已经加了兜底，把这种误用变成编译错误：

```c
#ifdef NDEBUG
#error "测试依赖 assert 判定，禁止定义 NDEBUG：断言会被移除导致假通过"
#endif
```

注意：断言被移除时，`check_fb()` / `check_guarded()` 里的 `printf("[FAIL] ...")`
**仍然会打印**，只是不再中止程序。所以看到 `[FAIL]` 和 `All renderer tests passed.`
同时出现，就是踩到了这个坑，而不是"有失败但无伤大雅"。

交叉编译到板上时同样适用：不要把 `NDEBUG` 加进 BSP 的 `CFLAGS`。
（已确认 2026.1 BSP 的 `software/` 目录内没有任何地方定义 `NDEBUG`。）
