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
| 基准工程目录 | `~/code/fpga/jzy/co_debug_2026/par/ddr_demo_ti60_2026/` |
| RISC-V 软件目录 | `~/code/fpga/jzy/co_debug_2026/par/ddr_demo_ti60_2026/embedded_sw/soc/software/` |
| BSP 目录 | `~/code/fpga/jzy/co_debug_2026/par/ddr_demo_ti60_2026/embedded_sw/soc/bsp/` |

> **注意**：README 中所有后续编译、驱动开发和运行说明，统一按 **2026.1 工程结构**编写，**禁止继续引用旧版 2025 BSP 路径**。

---

## jzy/riscv_game — CPU 渲染器与统一渲染层（M1）

M1 阶段的 CPU 参考实现，作为后续 RTL 渲染加速器（BitBlt）的比对基准；
其上是统一渲染层，让上层游戏代码只调用一套接口，底层在 CPU 与 FPGA 之间切换。

### 目录结构

| 目录 | 内容 |
|---|---|
| `render/` | CPU 参考实现 `renderer_sw.*`（**冻结**）；统一层 `renderer.*`、`render_status.*`；后端 `renderer_cpu.c`、`renderer_fpga.*` |
| `driver/` | GPU 驱动接口骨架 `gpu.*`（**不含真实寄存器访问**）；硬件约束校验 `gpu_validate.*` |
| `tests/` | 冻结基线 `test_renderer.c` + 统一层测试 `test_render_api.c` |
| `input/` | 输入处理（待填） |
| `game/` | 游戏逻辑（待填） |
| `perf/` | 性能对比测试（待填） |

### 测试与构建

统一入口在项目根 `jzy/riscv_game/Makefile`：

```bash
cd jzy/riscv_game
make test              # 两套都跑（冻结基线 + 统一层），均带严格警告 + ASan/UBSan
make check             # 静态约束检查：寄存器引用隔离、库代码无硬编码地址
make riscv-build       # RISC-V 交叉编译验证（rv32im_zicsr_zifencei / ilp32）
make riscv-build-hw    # 额外开启 BITBLT_ENABLE_HW_ACCESS 做编译检查
make clean
```

- 两套测试都用 `-Wall -Wextra -Wpedantic -Werror`，并固定开启 ASan + UBSan
  （`-fno-sanitize-recover=all`，UBSan 命中直接终止而不是打完警告继续跑）。
- `make check` 机械保证：全树只有一个文件 include `bitblt_regs.h`（B 组的寄存器定义，
  不复制、不软链），且 `render/`、`driver/` 里没有任何硬编码的真实地址。
- `make riscv-build` 的 `-march/-mabi` 取自 2026.1 BSP 实际产物的
  `Tag_RISCV_arch`（`rv32i2p1_m2p0_zicsr2p0_zifencei2p0_zmmul1p0`，ABI `ilp32`）。
  换 BSP 时可用 `make riscv-build RV_ARCH=... RV_ABI=...` 覆盖。
  这些目标只证明能编能链，产物不在本机运行。
- `tests/Makefile` 是冻结基线自带的，工具链参数与根 Makefile 一致，可以单独用。

### 渲染层分层约定

- **`render_*` 是统一层，`gpu_*` 是驱动层**。名字差异本身是安全属性：从调用点就能
  看出有没有裁剪过、stride 是像素还是字节。
- **裁剪只在 `render/renderer.c` 里做一次**，两个后端收到的都是已裁剪、保证落在画布内的
  参数。CPU 后端因此是纯直通，后端不得再裁剪，也不得写出 `dst_rect` 之外。
- **stride 单位**：统一层是像素（`stride_px`），驱动层是字节（`*_stride_bytes`），
  全代码库不出现裸 `stride`。硬件那边 `WIDTH` 是矩形宽度而 `DST_STRIDE` 是画布行距，
  传错会把后面每一行写花。
- **真实寄存器访问只允许出现在 `driver/gpu.c`**，且被 `#ifdef BITBLT_ENABLE_HW_ACCESS`
  包住。当前该分支是骨架，一行寄存器读写都没有实现。

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

### 板端 smoke test

`tests/test_render_board.c` 是在真实 Ti60F225 / RV32 上跑的 smoke test，
覆盖 `pixel_t` 宽度、CPU 后端分发、Solid Fill、Block Copy、stride 与裁剪共 13 项。
**完全不访问 FPGA BitBlt**，不填任何真实地址，不用 `assert` 判定，只用 `bsp_printf`。

它**不替代** host 测试，两者互补：host 侧直接调 `sw_*`，覆盖其全部裁剪分支；
板端只走 `render_*`，因此 `sw_*` 自身的裁剪容错在板上测不出来（统一层已先裁剪，
那是空操作）。

BSP 工程位置与完整说明见：

```
jzy/co_debug_2026/par/ddr_demo_ti60_2026/embedded_sw/soc/software/
    standalone/renderer/rendererM1Demo/README.md
```

基于官方 `uartEchoDemo` 新建，未改动原件。编译需要显式给定
`BSP=efinix/EfxSapphireSoc`（`BSP` 无默认值，且值含 `efinix/` 前缀）。

---

## 像素格式：XRGB8888（CPU 侧迁移已完成）

### 已确认的硬件格式事实（2026-09-17）

| 项 | 值 |
|---|---|
| Pixel format | XRGB8888 |
| Pixel size | 32 bit = 4 Byte |
| RISC-V control AXI | 32 bit |
| DDR AXI data width | 128 bit |
| Pixels per DDR beat | 4 |
| Stride | width × 4 Byte |
| Solid Fill color | 1 个 32-bit XRGB8888 像素 |
| Block Copy | 按 32-bit 像素搬运 |

RTL 里存在显示侧格式字段（约定名 `DISPLAY_FORMAT`），但当前 RTL **只实现了
XRGB8888**，没有 RGB565 的打包/解包与显示适配。因此 M1/M2 阶段**不要**试图把
两个 RGB565 像素塞进一个 32-bit word 去绕过格式限制。

### 迁移状态：已完成，32-bit 版本已重新冻结为 M1 CPU reference baseline

CPU 参考实现已从 16-bit 迁移到 XRGB8888 / 32-bit。当前 `pixel_t` 是 `uint32_t`、
`RENDER_PIXEL_BYTES == 4`、`RENDER_FPGA_USABLE == 1`，FPGA 后端不再被格式闸门拦住。
`renderer.h` 里的静态断言仍强制 `RENDER_PIXEL_BYTES` 与 `sizeof(pixel_t)` 一致。

**格式闸门保留**：它防的是"pixel_t 又被改成与硬件不一致的宽度却没人发现"。
任何时候都不允许用强制转换、截断或 `reinterpret_cast` 绕过它。

迁移中实际改动的文件：

| 文件 | 改动 |
|---|---|
| `render/renderer_sw.h` | `pixel_t`：`uint16_t` → `uint32_t`；注释改为确认后的格式说明 |
| `render/renderer.h` | `RENDER_PIXEL_BYTES`：2 → 4 |
| `render/renderer_fpga.c` | `render_pixel_to_hw_color()` 改为恒等映射 |
| `tests/test_renderer.c` | `RED` 改为 `0x00FF0000`；诊断输出改用 `PRIX32` |
| `tests/test_renderer_api.c` | 格式闸门分支翻转并重写为走完整条下发通路；像素映射测试改为恒等映射 |

`render/renderer_sw.c` **未改动**——它的实现完全由 `pixel_t` 参数化，没有硬编码宽度。

**迁移中被交叉编译抓到的坑（值得记住）**：诊断输出原本写 `printf("...0x%08X", value)`。
在 x86-64 宿主机上 `uint32_t` 就是 `unsigned int`，能编过；但 rv32 上 `uint32_t` 是
`unsigned long`，`-Werror=format` 直接编译失败。已统一改为 `<inttypes.h>` 的 `PRIX32`。
**这类问题只有交叉编译能发现，本机测试全绿不代表板上没问题。**

迁移后的验证结果：`make test` 全绿、`make check` 通过、`make riscv-build` 通过、
`make riscv-build-hw` 通过、冻结层变异测试 10/10 抓到、统一层变异测试 12/12 抓到。

`renderer_sw.h` 里原有一句"最终是否采用 RGB565，要等三人接口约定正式确定"的暂定注释，
已随这次迁移一并改为确认后的 XRGB8888 说明。

### RGB565：后续性能优化方向，现在不实现

若以后 DDR 带宽、Framebuffer 占用或 Sprite 吞吐成为瓶颈，再考虑：

- 16-bit RGB565
- 2 pixels / 32-bit word
- 8 pixels / 128-bit DDR beat
- stride = width × 2 Byte
- 显示侧 unpacker 按 `DISPLAY_FORMAT` 解包

`renderer.h` 的像素格式抽象与显示侧格式扩展位就是为这条路径预留的接口。

### 对齐约束：当前是硬件约束，尚未冻结为游戏规则

`16 Byte 对齐`、`WIDTH % 4 == 0`（以及由此推出的矩形起点 `x % 4 == 0`）**只是
BitBlt V0.1 的硬件约束**，还没有冻结成最终游戏规则。

后续要和 B 组单独确认是否需要在硬件侧放宽——放宽可以解除对矩形起点必须是 4 的
倍数这一限制，从而不再约束字体字宽、精灵宽度和 UI 面板位置。

在 B 组确认之前，`gpu_validate.c` 继续按 V0.1 的严格口径拒绝，不要放松。
