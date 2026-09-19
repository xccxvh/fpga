# rendererM2Demo —— M2 BitBlt 板端 smoke test（第一阶段）

在真实 Ti60F225 / Sapphire RISC-V (RV32) 上验证 BitBlt 加速器的最小闭环。
板端时基来自 Sapphire BSP 官方 `clint_getTime(BSP_CLINT)`。

## 这个工程验证什么

| 用例 | 内容 | 不通时 |
|---|---|---|
| T0 | CLINT tick source：已注入、单调递增、`bsp_uDelay(10000)` 推进约 1,000,000 个 100 MHz tick | **fail-fast**，整个 smoke 立刻结束 |
| T1 | `BITBLT_VERSION` == `0x00010003` | **fail-fast**，不再下发 FILL |
| T2 | `bitblt_fill()` 写 Scratch DDR 的 64×64 XRGB8888 区域，CPU 逐像素回读 | 记录 FAIL，继续跑 T3 |
| T3 | 矩形四周的 guard sentinel 未被改写（上下各 8 行 + 每行行尾 padding） | 记录 FAIL |

本版刻意**不包含**：`display_api`、HDMI、双缓冲、`bitblt_copy`、游戏逻辑与输入。
这些等 T0~T3 在真板上稳定之后再逐步加。

## T0 为什么必须 fail-fast

`driver/bitblt_api.c` 在没有 tick 源时会让 `wait_done()` 直接返回 `BITBLT_ETIMEOUT`
（刻意不猜时钟）。如果时基本身是坏的却继续跑 FILL，串口上看到的会是
"硬件超时"，而真正的原因在时基 —— 排查方向会被整个带偏。

所以 T0 一旦不通，`main()` 立即打印 `[FATAL]` 与 `M2 BITBLT BOARD TEST FAILED`
并停机，**不读任何 BitBlt 寄存器、不下发任何命令**。

`bitblt_board_test_clint()` 是一个独立函数（非 `static`，返回 0/非 0），
不依赖本文件其它测试的状态，未来的自动回归可以只链接并调用这一个函数。

## 区域参数

```
region 64x64 XRGB8888, row 256 B, stride 320 B, scratch+0x00010000
```

- 地址取自 B 的 `framebuffer_layout.h` 的 `SCRATCH_BASE`，测试代码里不重复硬编码；
  只在 Scratch 内部取 `+0x10000` 的偏移。
- 注意区分两个基地址：`TEST_REGION_BASE` 是区域本体（fill 的 DST），
  `TEST_GUARD_BASE` 是缓冲起点（上 guard 的第一行），两者差 8 行 stride。
- 满足硬件约束：`row bytes = 256`、`stride = 320`、区域本体与缓冲起点
  都是 16 字节对齐；`WIDTH = 64` 是 4 的倍数。这些由编译期静态断言钉死。
- `stride (320) > row bytes (256)`，于是每行行尾自然留下 64 B padding 当 guard。

guard 断言覆盖三处，缺一不可：向上越界、向下越界/stride 算错整行偏移、
以及"按 stride 铺满"这一类误写。

## 编译

```bash
cd jzy/co_debug_2026/par/ddr_demo_ti60_2026/embedded_sw/soc/software/standalone/renderer/rendererM2Demo

export PATH=$HOME/efinity/efinity-riscv-ide-2026.1/toolchain/bin:$PATH
make BSP=efinix/EfxSapphireSoc
```

`BSP` 没有默认值，必须显式给定 `efinix/EfxSapphireSoc`（不是 `EfxSapphireSoc`）。
`make clean` 同样要带上 `BSP=…`，否则 makefile 顶层的 BSP 存在性检查会直接报错。
实测产物：`ram: 10064 B / 124 KB (7.93%)`。

本工程**不复制**驱动源码，直接编译 `jzy/riscv_game/` 下冻结的那一份
`driver/bitblt_api.c` 与板端测试 `tests/test_bitblt_board.c`，
所以板上跑的就是仓库里这一份。

## 前置条件：bitstream

必须下载 B 组 BitBlt overlay 工程产生的 bitstream。

原始 `jzy/co_debug_2026/.../outflow/ddr_demo_ti60.bit` **不能用**：它没有连入
BitBlt RTL，访问 `0xE1000000` 会让 CPU 卡在第一次 load 上 —— 那是一次总线
挂死，软件超时根本跑不起来，串口只会停在中途没有结论。

## 串口输出（预期）

115200 8N1，接 `BSP_UART_TERMINAL`。

全部通过时：

```
=== M2 BitBlt Board Smoke Test ===
region 64x64 XRGB8888, row 256 B, stride 320 B, scratch+0x00010000
guard: 8 rows above/below, 64 B padding each row
timeout 10000000 ticks (100 ms @ 100000000 Hz)

CLINT 10ms delta = 1000040 ticks (expected about 1000000)
[PASS] T0_clint_tick_source
[PASS] T1_bitblt_version (0x00010003)
[PASS] T2_bitblt_fill_readback
[PASS] T3_guard_sentinel

PASS = 4
FAIL = 0
M2 BITBLT BOARD TEST PASSED
```

T0 不通时（fail-fast，后面三个用例根本不会跑）：

```
[FAIL] T0_clint_tick_source: tick source not injected

[FATAL] CLINT tick source unusable; BitBlt MMIO was NOT touched

PASS = 0
FAIL = 1
M2 BITBLT BOARD TEST FAILED
```

T1 不通时（同样停下，不下发 FILL）：

```
CLINT 10ms delta = 1000040 ticks (expected about 1000000)
[PASS] T0_clint_tick_source
[FAIL] T1_bitblt_version expected=0x00010003 actual=0x00010002

[FATAL] unexpected BitBlt version; fill tests were NOT run

PASS = 1
FAIL = 1
M2 BITBLT BOARD TEST FAILED
```

T2/T3 抓到不符时会逐条打印坐标与期望/实际值（每条用例最多 8 行，其余只计数），
最后给出 `PASS = n / FAIL = m`。跑完程序停在 `while(1)`，串口保留完整结论。

> 上面三段输出是**同一份源码**在宿主机上跑出来的实际结果（见下节的替身跑法），
> 10 个场景（正常路径 + 9 个故障注入）全部符合预期。
> **板上的真实输出仍以实测为准。**

### 无板时怎么验证这份测试

板端测试的判定逻辑可以在宿主机上验证，不需要板子：

```bash
cd jzy/riscv_game
make board-logic-test
```

它把本文件**原样**编到宿主机上（`-Dmain=board_main` 让位给驱动器），
用替身 `bsp.h` + 一片 mmap 在真实地址上的假内存 + 一个 BitBlt 行为模型跑起来，
然后逐个注入故障，确认每一条用例真的会拦：

| 注入 | 期望 |
|---|---|
| 无 | 4/4 通过 |
| `nohook` | T0 报"tick source not injected"，且不碰 MMIO |
| `freeze` | T0 报 tick 不前进 |
| `slowclock` | T0 报 10 ms delta 越界 |
| `version` | T1 门挡住，不下发 FILL |
| `short` | T2 回读抓到 |
| `pad` | T3 抓到行尾 padding 被写 |
| `overrun` | T3 抓到下方 guard 被写 |

**这只说明测试的判定逻辑是对的，不说明它在真板上会通过。** 真板结论只能由
`scripts/regress.sh full` 给出。

## 输出格式符约束（踩过的坑）

本 BSP 用的是 lite 版 `bsp_printf`（`bsp.h` 里 `ENABLE_BSP_PRINTF_FULL = 0`），
**只认 `c` / `s` / `d` / `x` / `X`**。

用了它不认识的转换符（比如无符号的那个）**不会编译报错**，但板上会出两种坏结果：
解析器在 `%` 之后找不到认识的字符会一直吃到字符串结尾，于是整行剩余内容被吞掉，
而且那个参数不会被取走 —— **后面所有参数整体错位**。

所以板端测试里的无符号量一律先转 `int` 再按 `%d` 打印。
`make check-board-printf` 会在编译期机械地挡住这类写法
（黑名单而非白名单：源文件里 `TEST_STRIDE % 16u == 0u` 这种取模表达式
长得也像格式符，白名单扫描会误报）。

顺带一提，`%X` 固定输出 8 位，所以偏移打印出来是 `0x00010000` 而不是 `0x10000`；
写 `%08X` 只是让意图可读，宽度本身并不生效。

`tests/host_board/stub.c` 里的替身 `bsp_printf` 复刻了同一个解析器，
所以格式符写错在宿主机上就能看见，不必等上板。

## 与其它测试的分工

| 入口 | 覆盖 |
|---|---|
| `tests/test_bitblt_api.c` | host 侧驱动/适配层，注入假时钟，不碰真硬件 |
| `tests/test_render_board.c`（rendererM1Demo） | M1 CPU 渲染层在真 RV32 上的行为 |
| 本工程 | 真硬件 BitBlt MMIO + CLINT 时基 |

三者互补，本工程**不能**替代 host 测试。

## 相关入口

```bash
# 无板也能跑：host 测试 + 静态检查 + 交叉编译两个板端 ELF
jzy/riscv_game/scripts/regress.sh build

# 接上板子之后：连 bitstream 下载与 M1/M2 串口判定一起跑
jzy/riscv_game/scripts/regress.sh full
```
