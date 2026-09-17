# rendererM1Demo —— M1 渲染层板端 smoke test

在真实 Ti60F225 / Sapphire RISC-V (RV32) 上验证 M1 冻结的 CPU 参考渲染器与统一渲染层。

结构基于官方 `uartEchoDemo` 新建，**不改动 `uartEchoDemo` 原件**。

## 这个工程验证什么

| 用例 | 内容 |
|---|---|
| T1 | `pixel_t` 是 4 字节，且与 `RENDER_PIXEL_BYTES` 一致 |
| T2 | 未选后端时绘制报错；`render_init()` 默认选中 CPU |
| T3 | `render_fill_rect` 正常矩形；XRGB8888 三原色通道位置正确 |
| T4a/T4b | fill 左上裁剪（负坐标）、右下裁剪、正好贴合、完全在屏外 |
| T5 | `render_blit` 正常拷贝 |
| T6a/b/c | blit 左上裁剪、右下裁剪、完全在屏外 |
| T7 | `stride != width`：逐行验证每一行落在自己的 stride 上 |
| T8 | 一串混合操作后，行尾 padding 与底部保护行仍完好 |
| T9 | FPGA 后端在当前构建下是惰性的：拒绝下发、不碰寄存器、不写画布 |
| T10 | 直接测 `render_clip_rect()` 的裁剪几何，含 RV32 的 32 位极值 |

## 约束（刻意为之）

- **完全不访问 FPGA BitBlt**：不填任何真实地址，不定义 `BITBLT_ENABLE_HW_ACCESS`，
  不调用 `gpu_fill()` / `gpu_copy()` 做硬件操作。
- **不使用 ASan/UBSan**：板上没有这些运行时。
- **不用 `assert` 判定**：板上 assert 挂住后什么都看不到。全部显式打印 + 统计失败数。
- **不依赖 HDMI**：只用 `bsp_printf()` 走串口。
- 用静态 RAM 数组模拟小型 framebuffer（16×12，stride 20，底部留 4 行保护区）。
- 主要走 `render_*` 统一层 API，不绕过它直接测 `sw_*`。

## 关于源码位置

本工程**不复制**渲染层源码，直接编译 `/home/jzy/code/fpga/jzy/riscv_game/` 下冻结的那一份：

- `tests/test_render_board.c`
- `render/*.c`、`driver/*.c`

这样板上跑的就是 host 测试验证过的同一份代码，不存在第二份需要同步的副本。

默认路径按仓库约定推导（`$(HOME)/code/fpga/jzy/riscv_game`），目录不同就覆盖：

```bash
make BSP=efinix/EfxSapphireSoc RENDER_ROOT=/path/to/riscv_game
```

## 编译

### 命令行

```bash
cd jzy/co_debug_2026/par/ddr_demo_ti60_2026/embedded_sw/soc/software/standalone/renderer/rendererM1Demo

export PATH=$HOME/efinity/efinity-riscv-ide-2026.1/toolchain/bin:$PATH
make BSP=efinix/EfxSapphireSoc
```

**`BSP` 没有默认值，必须显式给定**，且值要写成 `efinix/EfxSapphireSoc`
（不是 `EfxSapphireSoc`）——`bsp.mk` 里的路径是 `${STANDALONE}/../../bsp/${BSP}`，
而实际目录是 `soc/bsp/efinix/EfxSapphireSoc`。Efinity RISC-V IDE 会自动传这个值。

产物在 `build/`：`rendererM1Demo.elf` / `.hex` / `.bin` / `.asm` / `.map`。

已实测：`ram: 18688 B / 124 KB (14.72%)`，编译零错误。

### 在 Efinity RISC-V IDE 里

本目录**没有**提交 `.project` / `.cproject` / `.launch`。原因：官方 `uartEchoDemo` 的
`.project` 里 `linkedResources` 指向厂家资料包的下载目录绝对路径，在当前工作树下已经失效；
手工造或盲拷只会把过期路径传播开。正确做法是在 IDE 里新建：

1. `File > New > RISC-V Application`（或 `Import > Existing Projects` 指向本目录后修正链接资源）
2. 选择本 BSP：`EfxSapphireSoc`
3. 工程根目录指向本目录，构建会自动用这里的 `makefile`
4. Build 后确认 `build/rendererM1Demo.elf` 生成

## 串口输出（预期）

115200 8N1，接 `BSP_UART_TERMINAL`（与 `uartEchoDemo` 同一路串口）。复位后的完整输出：

```
=== M1 Renderer Board Smoke Test ===
pixel_t = 4 bytes (expect 4), RENDER_PIXEL_BYTES = 4
canvas 16x12 stride_px=20 (4 guard cols) rows=16 (4 guard rows)
backend = CPU only; no BitBlt register access in this build

[PASS] T1_pixel_t_is_4_bytes
[PASS] T2_default_backend_is_cpu
[PASS] T3_fill_rect_normal
[PASS] T4a_fill_clip_left_top
[PASS] T4b_fill_clip_right_bottom
[PASS] T5_blit_normal
[PASS] T6a_blit_clip_left_top
[PASS] T6b_blit_clip_right_bottom
[PASS] T6c_blit_fully_outside
[PASS] T7_stride_not_equal_width
[PASS] T8_padding_intact_after_mixed_ops
[PASS] T9_fpga_backend_inert
[PASS] T10_clip_rect_geometry

PASS = 13
FAIL = 0
M1 BOARD TEST PASSED
```

失败时每条不符打印一行，最多 8 行，其余汇总：

```
[FAIL] T3_fill_rect_normal x=4 y=3 expected=0x00FF0000 actual=0x00000000
[FAIL] T3_fill_rect_normal 另有 12 处不符未逐条列出
...
PASS = 12
FAIL = 1
M1 BOARD TEST FAILED
```

跑完后程序停在 `while(1)`，串口保留完整结论供查看。

> 上面的输出是同一份源码在宿主机上用替身 `bsp.h` 跑出来的实际结果，
> 已确认 13/13 全过、失败路径也验证过。**板上的真实输出仍以实测为准。**

## 已知覆盖边界

`sw_*` 自身的裁剪容错**在板端测不出来**，这是设计使然：统一层先裁剪，
`sw_fill_rect` / `sw_blit` 永远收不到越界矩形，它们内部的裁剪是空操作。
这部分由 host 侧冻结基线 `tests/test_renderer.c` 直接调用 `sw_*` 覆盖。

因此本工程**不能**替代 host 测试，两者是互补关系：

- host：`cd jzy/riscv_game && make test`（严格警告 + ASan/UBSan，覆盖 `sw_*` 全部裁剪分支）
- board：本工程（确认真实 RV32 上的行为、`pixel_t` 宽度、后端分发）
