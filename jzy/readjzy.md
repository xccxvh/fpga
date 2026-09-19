# jzy 工作区说明

本文件（`jzy/readjzy.md`）是 `jzy/` 目录的 README，负责记录**本目录内部**的工程结构、开发环境、版本基准、编译调试步骤与目录说明。

## 团队统一目标与本目录当前状态（2026-09-19）

### 已统一的图像与总线参数

| 项目 | 统一值 |
|---|---|
| 显示模式 | `1280×720 @60 Hz`，像素时钟74.25 MHz |
| 像素格式 | RGB565小端，`R[15:11] G[10:5] B[4:0]`，2 Byte/像素 |
| 行与帧大小 | stride=`2560 B`；有效帧=`1,843,200 B` |
| DDR数据面 | 128-bit AXI4 INCR；每beat 16 B，即8个RGB565像素 |
| 控制路径 | 沿用B组`SYSTEM_AXI_A`：BitBlt=`0xE1000000`，显示=`0xE1100000` |
| 换帧控制 | C组软件是唯一提交者；通过`NEXT_ADDR`和`SWAP_REQUEST`请求VBlank切换 |

### 已选择的统一DDR布局

板载DDR3物理容量按256 MiB，即`0x00000000–0x0FFFFFFF`。联合工程统一使用
B组布局，不再使用A组UDP独立Demo从地址0开始的2 MiB图片槽：

| 区域 | 起始地址 | 结束地址 | 预留大小 | 用途与约束 |
|---|---:|---:|---:|---|
| 系统/程序保留区 | `0x00000000` | `0x00FFFFFF` | 16 MiB | CPU程序、数据和堆栈；禁止存放图片 |
| Framebuffer A | `0x01000000` | `0x017FFFFF` | 8 MiB | 前台或后台；RGB565有效帧只占前1,843,200 B |
| Framebuffer B | `0x01800000` | `0x01FFFFFF` | 8 MiB | 前台或后台；RGB565有效帧只占前1,843,200 B |
| 图片素材区 | `0x02000000` | `0x03FFFFFF` | 32 MiB | 原始图片、Sprite等；不能直接作为正在扫描的前台 |
| Scratch | `0x04000000` | `0x04FFFFFF` | 16 MiB | 测试、临时数据和中间结果 |
| 后续保留区 | `0x05000000` | `0x0FFFFFFF` | 176 MiB | 当前不得自行分配 |

所有地址只能从B组权威`framebuffer_layout.h`取得，C组代码不得另复制一套
数字常量。UDP与BitBlt每次只能有一个生产者写获授权的后台；不得写当前
`FRONT_ADDR`。生产者成功后由C软件提交换帧，确认`SWAP_DONE`和新的
`FRONT_ADDR`之后，原前台才可重新作为后台使用。

- A组UDP集成时必须把低地址slot映射改为上述Framebuffer A/B，并补充完整帧
  通知；字节数、包序号、FIFO状态及所有DDR `BRESP`均正确才算可显示。
- C组需要读取UDP完成状态或BitBlt `DONE && !ERROR`，但UDP完成通知的具体
  寄存器/中断地址仍待A/C落实，不能假定旧Demo已经具备该软件接口。
- `FORMAT=RGB565`及新BitBlt/显示VERSION值仍需随联合RTL实现后冻结。

- **注意：下面的XRGB8888章节是C组既有实现和验证记录，不是新目标。**
  `jzy/riscv_game`的`pixel_t`、CPU参考渲染、FPGA适配层和测试目前仍按
  XRGB8888/32 bit工作；B组当前V0.4 RTL/位流也仍是XRGB8888/1080p。
  不能仅改宏、强制转换或复用旧位流就宣称RGB565已联调通过。
- 新格式的软件迁移需与B组RGB565 RTL及A组UDP/显示链路同步，完成
  16-bit像素、stride、Color Key、图案/素材、边界与板端回归。控制寄存器和
  新格式枚举仍需按联合接口文档实现。
- 集成版已选用B组`SYSTEM_AXI_A` BitBlt/显示寄存器路径；**C组软件是唯一
  换帧提交者**。UDP或BitBlt只写获授权的后台，完成后由软件写`NEXT_ADDR`
  和`SWAP_REQUEST`，确认VBlank切换后再复用旧前台。UDP向CPU报告完整帧
  的具体寄存器/中断仍待A/C实现，当前旧Demo不能直接用于此流程。

统一接口与待确认项见[`../07_docs/interfaces/rgb565_720p_migration.md`](../07_docs/interfaces/rgb565_720p_migration.md)；
旧版XRGB8888已测合同见[`../07_docs/interfaces/bitblt_interface_v0.2.md`](../07_docs/interfaces/bitblt_interface_v0.2.md)。

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
| `render/` | CPU 参考实现 `renderer_sw.*`（**冻结**）；统一层 `renderer.*`、`render_status.*`；后端 `renderer_cpu.c`、`renderer_fpga.*`；扩展参考 `renderer_sw_ext.*`（Color Key / Alpha）；换帧状态机 `frame_swap.*` |
| `driver/` | BitBlt 驱动 `bitblt_api.c`（实现 B 冻结的 `bitblt_fill/copy`，**全工程唯一引用 `bitblt_regs.h` 的文件**）；显示驱动 `display_api.c`（实现 B 冻结的 `display_*`，**唯一引用 `display_regs.h` 的文件**）+ 平台钩子 `display_platform.h`；格式与几何 `framebuffer_format.*`；**已冻结协议 `protocol_frozen.*`**；仍未冻结项 `protocol_unfrozen.*`（只剩 UDP）；硬件约束校验 `gpu_validate.*`；`gpu.*` 已降级为兼容层 |
| `tests/` | 冻结基线 `test_renderer.c` + 统一层测试 `test_render_api.c` + 像素格式/几何/Color Key/Alpha 测试 `test_pixel_format.c` + 换帧状态机测试 `test_frame_swap.c` |
| `input/` | 输入处理（待填） |
| `game/` | 游戏逻辑（待填） |
| `perf/` | 性能对比测试（待填） |

### 测试与构建

统一入口在项目根 `jzy/riscv_game/Makefile`：

```bash
cd jzy/riscv_game
make test              # 三套都跑（冻结基线 + 统一层 + BitBlt 适配层），均带严格警告 + ASan/UBSan
make check             # 静态约束检查：寄存器引用隔离、库代码无硬编码地址
make riscv-build       # RISC-V 交叉编译验证（rv32im_zicsr_zifencei / ilp32）
make riscv-build-hw    # 额外开启 BITBLT_ENABLE_HW_ACCESS 做编译检查
make clean
```

三套 host 测试的分工：

| 文件 | 覆盖 |
|---|---|
| `tests/test_renderer.c` | 冻结的 M1 CPU 基线（14 组） |
| `tests/test_render_api.c` | 统一层、裁剪、后端分发、约束校验（10 组） |
| `tests/test_bitblt_api.c` | `bitblt_*` 接口、错误码映射、超时换算、limits、适配层转发（7 组） |

- 三套测试都用 `-Wall -Wextra -Wpedantic -Werror`，并固定开启 ASan + UBSan
  （`-fno-sanitize-recover=all`，UBSan 命中直接终止而不是打完警告继续跑）。
- `make check` 机械保证两件事：**全树只有一个文件 include `bitblt_regs.h`**
  （现在是 `driver/bitblt_api.c`；B 组的寄存器定义不复制、不软链），
  以及 `render/`、`driver/` 里没有任何硬编码的真实地址。
- `make riscv-build-hw` 会真的把 `bitblt_api.c` 的寄存器分支编进去
  （include B 的 `bitblt_regs.h`、用 `fence rw,rw`、用寄存器枚举值），
  确保那段代码不是死代码。
- `make riscv-build` 的 `-march/-mabi` 取自 2026.1 BSP 实际产物的
  `Tag_RISCV_arch`（`rv32i2p1_m2p0_zicsr2p0_zifencei2p0_zmmul1p0`，ABI `ilp32`）。
  换 BSP 时可用 `make riscv-build RV_ARCH=... RV_ABI=...` 覆盖。
  这些目标只证明能编能链，产物不在本机运行。
- `tests/Makefile` 是冻结基线自带的，工具链参数与根 Makefile 一致，可以单独用。

### 渲染层分层约定

- **三层分工**：`render_*`（上层游戏调用的统一层）→ `renderer_fpga.c`（适配层）
  → `bitblt_*`（B 冻结的驱动）。名字差异本身是安全属性：从调用点就能看出
  有没有裁剪过、stride 是像素还是字节、以及是不是直接碰了硬件。
- **裁剪只在 `render/renderer.c` 里做一次**，两个后端收到的都是已裁剪、保证落在画布内的
  参数。CPU 后端因此是纯直通，后端不得再裁剪，也不得写出 `dst_rect` 之外。
- **stride 单位**：统一层是像素（`stride_px`），驱动层是字节（`*_stride_bytes`），
  全代码库不出现裸 `stride`。硬件那边 `WIDTH` 是矩形宽度而 `DST_STRIDE` 是画布行距，
  传错会把后面每一行写花。
- **真实寄存器访问只允许出现在 `driver/bitblt_api.c`**，且被
  `#ifdef BITBLT_ENABLE_HW_ACCESS` 包住。旧的 `gpu.*` 已降级为兼容层，不再含寄存器分支。
- **上层只调 `render_fill_rect()` / `render_blit()`**；`render/renderer_fpga.c` 是适配层，
  负责调用 `bitblt_fill()` / `bitblt_copy()`、做 `bitblt_result_t → render_status_t`
  的错误码映射、以及 `timeout_ms → 100 MHz CLINT tick` 的换算。
- **地址一律来自 B 的权威头文件**：`bitblt_regs.h`（寄存器）、`framebuffer_layout.h`
  （Framebuffer A/B、素材区、Scratch、系统保留区）。本工程不复制、不软链、不重复硬编码，
  由 `make check` 机械保证。

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

## 既有像素实现：XRGB8888（CPU 侧历史基线）

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

### RGB565：C 侧代码迁移已完成，硬件尚未联调

**2026-09-19：C 侧软件已迁移到 RGB565 / 1280x720@60**，作为默认格式。
团队统一目标与依据见 `../07_docs/interfaces/rgb565_720p_migration.md`。

改动的落点：

| 位置 | 内容 |
|---|---|
| `render/renderer_sw.h` | `pixel_t` 改成 `uint16_t`，并成为**全工程唯一的格式开关** `RENDER_PIXEL_FORMAT_RGB565` |
| `driver/framebuffer_format.*` | 现行几何（1280/720/2 B/2560 B/1843200 B）、宽度粒度、pack/unpack、COLOR 映射 |
| `render/renderer.h` | `RENDER_PIXEL_BYTES` 改为由 `sizeof(pixel_t)` 派生，不再有第二处真相源 |
| `driver/gpu_validate.*` | 每像素字节数与宽度粒度进 `gpu_limits_t`，校验器对两种格式都成立 |
| `render/renderer_fpga.*` | 格式闸门由编译期常量改为**运行期声明** `render_fpga_set_hw_format()`，默认就是 RGB565，正常路径不需要显式调用 |
| `render/renderer_sw_ext.*` | Color Key（16-bit 精确比较）与 Alpha（宽位宽计算 + 量化回 RGB565）的 CPU 参考实现 |
| `render/frame_swap.*` | 换帧状态机：C 软件是唯一 SWAP 提交者 |
| `driver/display_api.c` | B 冻结 `display_api.h` 的实现，只走 `SYSTEM_AXI_A` |

`renderer_sw.c` **一行未改** —— 它完全由 `pixel_t` 参数化，这正是当初把它设计成
"只依赖 pixel_t、不硬编码宽度"的回报。

**回退路径必须保持可用**：`-DRENDER_PIXEL_FORMAT_RGB565=0` 切回 XRGB8888/1080p，
`make test-legacy` 会在该格式下把整套 host 测试再跑一遍。
B 组 RGB565 位流落地前，那是唯一能上板的路径。

**未完成（等 B 组）**：B 的 `framebuffer_layout.h` 仍是 XRGB8888/1080p 几何，
RGB565 版 BitBlt/显示 RTL 与联合位流尚未完成、未板测。详见下面的待确认清单。

### 协议冻结状态

**2026-09-19 已正式冻结两项**，定义集中在 `driver/protocol_frozen.h`（全工程唯一定义点）：

| 项 | 冻结值 | 说明 |
|---|---|---|
| `DISPLAY_FORMAT_XRGB8888` | `0` | 历史兼容枚举，仍有效，但**不是**当前联合工程默认格式 |
| `DISPLAY_FORMAT_RGB565` | `1` | **当前默认** |
| `BITBLT_VERSION_RGB565` | `0x00020000` | V2.0 |
| `DISPLAY_VERSION_RGB565` | `0x00030000` | V3.0 |

版本编码：**高 16 位主版本、低 16 位次版本**。RGB565 属于不兼容升级，
所以 BitBlt 进 V2.0、Display 进 V3.0。比较时比的是**完整 32 位**，不是只比主版本
—— 主版本对、次版本不同的位流仍是未验证组合，宁可 fail-fast。

换帧初始化顺序（`frame_swap_display_init()`）：

1. 读显示控制器 VERSION，必须等于 `DISPLAY_VERSION_RGB565`
2. 不匹配就返回 `FRAME_SWAP_ERR_VERSION_MISMATCH`，**一个配置寄存器都不写**，
   后续也不允许提交任何换帧
3. 版本对了才写几何与 `FORMAT = DISPLAY_FORMAT_RGB565 (= 1)`

> 按 RGB565 去配置一个 XRGB8888 位流不会报错，只会画一屏乱码 —— 所以版本必须
> 在写配置之前拦住。**这不代表 RGB565 位流已经存在或已板测。**
> 注意数值巧合：B 现有的 `DISPLAY_VERSION_V0_2` 同样是 `0x00020000`，
> 但那是显示控制器 V0.2 的旧版本号，与 BitBlt V2.0 是两回事。

**代持说明**：B 的权威头文件（`bitblt_regs.h` / `display_regs.h`）目前**尚未同步**
这几个宏，所以 `protocol_frozen.h` 暂时持有它们。`tests/test_contract.c` 里有一段
检测：**B 一同步，那边会编译失败**并提示把代持改成直接引用 B 的宏。
不允许两套版本定义长期并存。

### 仍未冻结：只剩 UDP 完成通知

`driver/protocol_unfrozen.h` 现在只剩这一项 —— 文件名保留是为了不做纯改名的
全树重构，但里面**只应存在还没冻结的东西**：

| 项 | 状态 | C 侧做法 |
|---|---|---|
| UDP 完成通知的寄存器地址 / 中断号 / ACK 方式 | 迁移文档写"尚未分配"，A 组草案提过的 APB 那一套已被否掉 | `protocol_udp_completion_available()` 在未声明时返回 0；`frame_swap_udp_frame_ready()` 直接 `NOT_READY`，不去读猜出来的地址 |

### 待板测（不能用软件测试代替的项）

以下项目 C 侧代码已经就位并通过 host/交叉编译测试，但**必须等硬件才能给结论**：

1. RGB565 版 BitBlt / 显示 RTL 与联合位流（B 组尚未实现）。
2. `render_fpga_set_hw_format()` 声明为 RGB565 后的整条下发通路真实行为。
3. 换帧状态机在真实显示控制器上的 `SWAP_DONE` / `FRONT_ADDR` 时序。
4. `test_bitblt_board.c` 的 T1 期望版本现在是 **`BITBLT_VERSION_RGB565`
   （`0x00020000`）**，而板上现存位流是 XRGB8888 的 V0.4（`0x00010004`）。
   所以拿到 RGB565 位流之前，T1 一定会 fail-fast —— 那是**正确行为**，
   不要为了让测试"变绿"而把期望值改回旧版本。
5. 板端 `rendererM1Demo` 在 RGB565 下的 smoke test（`test_render_board.c` 已按
   格式参数化并通过交叉编译，但未上板）。

### 对齐约束：当前是硬件约束，尚未冻结为游戏规则

`16 Byte 对齐`、`WIDTH % 4 == 0`（以及由此推出的矩形起点 `x % 4 == 0`）**只是
BitBlt V0.1 的硬件约束**，还没有冻结成最终游戏规则。

后续要和 B 组单独确认是否需要在硬件侧放宽——放宽可以解除对矩形起点必须是 4 的
倍数这一限制，从而不再约束字体字宽、精灵宽度和 UI 面板位置。

在 B 组确认之前，`gpu_validate.c` 继续按 V0.1 的严格口径拒绝，不要放松。

---

## M1 真板验证记录与环境踩坑

### M1 真板最终结果

| 项 | 值 |
|---|---|
| 日期 | 2026-09-17 |
| 平台 | Ti60F225 + Sapphire RV32 |
| 软件 | Efinity 2026.1 / Efinity RISC-V IDE 2026.1 |
| 板端原始串口输出 | `jzy/riscv_game/logs/m1_renderer_board_smoke_2026-09-17_uart.log` |

结果：

```
PASS = 13
FAIL = 0
M1 BOARD TEST PASSED
```

因此 **M1 CPU Renderer 已通过三层验证**：

1. Host 单元测试 + ASan/UBSan
2. RISC-V 交叉编译
3. Ti60F225 Sapphire 真实板端运行

### 版本基准

后续统一使用：

- **Efinity 2026.1**
- **riscv-none-elf-gcc 13.4.0**
- **2026.1 重新生成的 Sapphire BSP**

**禁止重新混用原资料包 2025.x BSP。** 旧 BSP 曾导致：

```
riscv-none-embed-gcc: not found
extension `zicsr' required
```

（背景与重新生成过程见本文开头「RISC-V 开发环境与 BSP 版本说明」一节。）

### 工程路径坑

`ddr_demo_ti60.xml` 里使用 `../../rtl/...` 这样的**相对路径**，
因此**不能只复制 `ddr_demo_ti60` 子目录**。必须保留完整的：

```
co_debug_2026/
├── rtl/
└── par/
    └── ddr_demo_ti60_2026/
```

当前基准硬件工程：

```
~/code/fpga/jzy/co_debug_2026/par/ddr_demo_ti60_2026/
```

### FTDI / OpenOCD 坑

本机实际 USB Product 字符串是：

```
Quad RS232-HS
```

但生成 BSP 时 `ftdi_ti.cfg` 里写的是厂家默认值：

```
Titanium Ti60F225 Development Kit
```

导致 OpenOCD 报：

```
Error: no device found
```

需要修改的文件：

```
embedded_sw/soc/bsp/efinix/EfxSapphireSoc/openocd/ftdi_ti.cfg
```

**两处**设备描述都改成 `Quad RS232-HS` 之后，OpenOCD 成功识别：

```
Target successfully examined.
Listening on port 3333 for gdb connections
```

### FT4232H 通道记录

一根 USB 会枚举出四个串口：

| 接口 | 设备节点 |
|---|---|
| if00 | `/dev/ttyUSB0` |
| if01 | `/dev/ttyUSB1` |
| if02 | `/dev/ttyUSB2` |
| if03 | `/dev/ttyUSB3` |

本次实测 Sapphire UART 落在 `/dev/ttyUSB2`，对应稳定别名：

```
usb-FTDI_Quad_RS232-HS-if02-port0
```

**后续不要永久依赖 `ttyUSB2` 这个编号**（换 USB 口或插拔顺序变化都会变），
应优先使用 `/dev/serial/by-id/`。

### GDB 启动坑

只执行：

```
set $pc = _start
continue
```

曾导致 CPU 停在 `PC=0x4`。

正确顺序是先复位、加载、在 main 下临时断点：

```
monitor reset halt
load
tbreak main
set $pc = _start
continue
```

到 `main()` 之后再继续运行。

注意用 `tbreak main`（临时断点），避免重复执行 `break main` 后留下多个断点。

### 串口访问权限（dialout）

`/dev/ttyUSB*` 的属主是 `root:dialout`、权限 `crw-rw----`。
默认用户不在 `dialout` 组里，因此**不打 sudo 打不开串口**：

```
$ exec 3<>/dev/ttyUSB2
bash: /dev/ttyUSB2: 权限不够
$ stty -F /dev/ttyUSB2
stty: /dev/ttyUSB2: 权限不够
```

一次性修复（需要 root，执行后**必须重新登录或重启**才在会话里生效）：

```bash
sudo usermod -aG dialout $USER
```

不重启先验证（`sg` 会重新读取组数据库）：

```bash
sg dialout -c 'test -r /dev/ttyUSB2 && test -w /dev/ttyUSB2 && echo OK'
```

重启后确认：

```bash
id | grep -o dialout
exec 3<>/dev/ttyUSB2 && echo "无需 sudo 即可打开"
```

> 不要用 `MODE="0666"` 的 udev 规则来"修"这个问题——那等于把串口对全机开放。
> 加组是标准做法。

已核查：本机装了 `brltty`（Ubuntu 上常见的 FTDI 串口抢占者），但其 udev 规则
`85-brltty.rules` 里 vendor `0403` 匹配的 product ID 是 `fe70`–`fe77`、`de58`/`de59`、
`f208`，**不含 FT4232H 的 `6011`**，因此不会抢占本板串口。

### 验收日志目录与命名约定

`jzy/riscv_game/logs/` 是**验收证据目录**，整目录对 git 可见
（`.gitignore` 里有 `!jzy/riscv_game/logs/*.log` 例外，因为默认 `*.log` 被忽略）。

命名统一为：

```
<阶段>_<测试名>_<日期>_<类型>.log
```

例如：

```
m1_renderer_board_smoke_2026-09-17_uart.log
m2_solid_fill_2026-09-xx_uart.log
m2_solid_fill_2026-09-xx_openocd.log
```

M2/M3 继续沿用；答辩或严格复现时再补存 OpenOCD 连接、GDB load/continue、
UART 功能输出三份即可。

### Programmer CLI 环境

GUI 之外可以用命令行烧 FPGA。必要环境至少为：

```bash
unset PYTHONHOME
unset PYTHONPATH

export EFINITY_HOME=$HOME/efinity/2026.1
export EFXPGM_HOME=$EFINITY_HOME/pgm
export EFXDBG_HOME=$EFINITY_HOME/debugger
export EFINITY_USER_DIR_INI=$HOME/.local/share/efinity/user_dir.ini

export PATH=$EFINITY_HOME/bin:$EFINITY_HOME/scripts:$EFXPGM_HOME/bin:$EFXDBG_HOME/bin:$PATH
```

枚举设备：

```bash
bash $EFINITY_HOME/pgm/bin/ftdi_pgm.sh --list_usb
```

JTAG 下载：

```bash
bash $EFINITY_HOME/pgm/bin/ftdi_pgm.sh \
  ~/code/fpga/jzy/co_debug_2026/par/ddr_demo_ti60_2026/outflow/ddr_demo_ti60.bit \
  -m jtag
```

### 真实地址：V0.3 已冻结，但库代码仍禁止硬编码

M1 板测**完全没有访问真正的 BitBlt**（当时地址还是 TBD）。现在地址已经由接口
文档冻结（V0.2/V0.3 行），权威来源是 B 的两个头文件：

| 内容 | 权威头文件 | 值 |
|---|---|---|
| BitBlt 寄存器块 | `bitblt_regs.h` | `0xE1000000`，偏移 `0x00`–`0x28` |
| 显示控制寄存器块 | `display_regs.h` | `0xE1100000`（**本工程本次不实现**） |
| Framebuffer A | `framebuffer_layout.h` | `0x01000000`，8 MiB slot |
| Framebuffer B | `framebuffer_layout.h` | `0x01800000`，8 MiB slot |
| 图片素材区 | `framebuffer_layout.h` | `0x02000000`，32 MiB |
| 测试/Scratch | `framebuffer_layout.h` | `0x04000000`，16 MiB |
| 系统/程序保留区 | `framebuffer_layout.h` | `0x00000000`，16 MiB |

**但库代码仍然不得硬编码这些地址。** `make check-no-addresses` 会在
`render/` 与 `driver/` 里搜上面这些字面量，出现即失败。地址只能通过：

- `gpu_limits_t` 参数（由平台层用 `render_limits_from_layout()` 填充，
  该函数直接从 `framebuffer_layout.h` 取宏）
- `render_surface_t.phys_base`

传入。这条约束的意义已经从"地址还没定"变成"地址已定，但只有一个真相源"。

> 注意 V0.3 §5 的提醒：早期板测用的 `0x01100000–0x0182C000` 会覆盖新的
> Framebuffer 布局，只能在显示关闭时运行；**新测试必须用 Scratch 区**。
> M1 板端 smoke test 用的是静态 RAM，不受影响。

### C 驱动的对外接口

对外严格使用 B 冻结的接口（`04_project/bitblt_accel/sw/driver/bitblt_api.h`）：

```c
typedef enum {
    BITBLT_OK = 0, BITBLT_EINVAL = -1, BITBLT_EBUSY = -2,
    BITBLT_ETIMEOUT = -3, BITBLT_EHW = -4
} bitblt_result_t;

bitblt_result_t bitblt_fill(uint32_t dst_addr, uint32_t width, uint32_t height,
                            uint32_t dst_stride, uint32_t color,
                            uint64_t timeout_ticks);
bitblt_result_t bitblt_copy(uint32_t src_addr, uint32_t dst_addr,
                            uint32_t width, uint32_t height,
                            uint32_t src_stride, uint32_t dst_stride,
                            uint64_t timeout_ticks);
```

- 实现位于 `jzy/riscv_game/driver/bitblt_api.c`，是**全工程唯一**引用
  `bitblt_regs.h` 的文件（`make check-hw-isolation` 保证）。
- 超时单位是 **100 MHz CLINT tick**，不是毫秒。适配层用
  `render_timeout_ms_to_ticks()` 换算（先转 `uint64_t` 再乘 `100000ULL`，
  避免 32 位溢出）。
- 旧的 `gpu_fill()` / `gpu_copy()` 是 V0.1 时期命名的遗留，**已降级为兼容层**，
  恒返回 `RENDER_ERR_UNSUPPORTED`，不含任何寄存器访问。新代码不要用。
- **缓存**：当前 CPU 只有 4 KiB 指令缓存、**没有数据缓存**，CPU 写过源数据后
  执行 `fence rw,rw` 即可，不需要 `data_cache_invalidate_address()`。
  （B 的旧 demo 里仍有 invalidate 调用，那是防御性写法，本次未擅自删除。）
- 本次**不实现** `display_api.h`（显示初始化与换帧），只做 BitBlt。

### 当前代码格式（历史实现，非团队新目标）

截至本次记录，现有C组代码仍采用：

- XRGB8888
- 32 bit / pixel
- 4 Byte / pixel
- DDR AXI 128 bit
- 4 pixels / beat

当前 B 的对齐要求（16 Byte 对齐、`WIDTH % 4 == 0`）**仍属于 BitBlt V0.1 硬件限制，
不冻结成最终游戏规则**，后续要和 B 组单独确认是否需要在硬件侧放宽。
