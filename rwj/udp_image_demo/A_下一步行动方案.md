# A 的下一步行动方案：从 UDP 图片 Demo 到 M1/M2

> 角色 A（系统平台与显示集成）· 2026-09-18
> 依据：《选题二 三人分工与 M1–M5 阶段目标》
> 路径均相对 `FPGA2026/`

---

## 0. 一句话结论

**M1 的活不是从零搭平台，是把两份已经各自跑通的工程合并。**

- 你刚做完的 `udp_image_demo/` = **DDR3 + HDMI + Framebuffer + 切屏 + 素材通路**（没有 CPU）
- 现成的 `demo/08_ti60f225_soc_demo/.../ddr_demo_ti60/` = **Sapphire SoC + DDR3 + BSP 软件工程**（没有 HDMI）

两份合起来，正好是 M1 要的"共同底座"。**"梳理现有参考工程"这一步我已经替你做了**，结果在下面第 2 节。

---

## 1. 现状盘点

| 能力 | `udp_image_demo/`（你做的） | `ddr_demo_ti60/`（现成参考） |
|---|---|---|
| Sapphire SoC / CPU | ✗ | ✓ RV32IM，100 MHz，I/D cache 各 4 KB |
| DDR3 控制器 | ✓ | ✓（**但配置不同，见第 3 节**） |
| DDR3 校准 + 上板验证 | ✓ 已验证 | ✓（DDR 测试工程） |
| HDMI 1280×720 输出 | ✓ | ✗ |
| Framebuffer / VSYNC 切屏 | ✓ 8 槽 × 2 MiB | ✗ |
| 图片素材通路 | ✓ UDP | ✗ |
| 软件工程 / BSP | ✗ | ✓ standalone + freeRTOS + 例程 |
| CPU 可写的自定义寄存器口 | ✗ | ✓ APB slave 0（含 `apb3Demo` 范例） |
| 时序收敛 | ✓ 0 条负 slack | 未知 |

**两份都缺的是**：AXI 多主仲裁。现在 SoC 的 AXI 主口是**直连** DDR3 控制器的（`ddr3_example_top.v:373` 起的 `u_sapphire_soc` 例化，`io_ddrA_*` 直接接 `s_axi_*`）。要让加速器也访问 DDR，必须插一层仲裁。

---

## 2. 参考工程考古结果（我读文件确认的）

### 2.1 路径

```
demo/08_ti60f225_soc_demo/09_Ti60F225_co_debug_demo/
├── rtl/ddr3_example_top.v        ← 顶层，第 373 行例化 soc u_sapphire_soc
├── rtl/ddr3_controller/          ← DDR3 控制器
├── rtl/memory_test/              ← DDR 测试逻辑（合并时可删）
└── par/ddr_demo_ti60/
    ├── ddr_demo_ti60.xml / .peri.xml / sdc/
    ├── src/Axi_Mux.v             ★ 多主 AXI 仲裁器（有源码，但本工程没接）
    ├── src/Interrupt.v
    ├── ip/soc/                   ← SoC IP（settings.json / soc.v / soc_define.vh）
    ├── embedded_sw/soc/
    │   ├── bsp/efinix/EfxSapphireSoc/include/soc.h   ★ 完整内存映射
    │   └── software/standalone/apb3/apb3Demo/        ★ 自定义寄存器驱动范例
    └── outflow/                  ← 已编译过
```

### 2.2 直接可用的东西

| 项 | 值 | 来源 |
|---|---|---|
| CPU | RV32IM，100 MHz，无 FPU/D/C 扩展 | `settings.json`、`soc.h` |
| 系统 RAM | 只有 **4 KB** | `SYSTEM_RAM_A_SIZE=4096` |
| **APB slave 0 基地址** | **`0xF8100000`，64 KB** | `soc.h:66` |
| SoC AXI 主口基地址 | `0xE1000000` | `settings.json: Base_M_AXIS` |
| SoC AXI 数据宽度 | 128 bit | `src/Axi_Mux.v: AXI_DATA_WIDTH=128` |
| 默认串口 | UART0 @115200（`bsp_printf` 走这里） | `soc.h` |

> **APB slave 0 就是 B 的命令寄存器和 C 的驱动的接口。**
> `apb3Demo`（`software/standalone/apb3/apb3Demo/src/main.c`）是一个能跑通的
> 读寄存器范例，`#define APB0 IO_APB_SLAVE_0_INPUT` —— C 写 `gpu_fill()` 直接照它抄。

### 2.3 `Axi_Mux.v` 是什么

最多 8 路 slave → 1 路 master 的 AXI 仲裁器，128-bit 数据宽度，通道数由
`Axi_Mux_Param.vh` 里的 `X2`…`X8` 宏选择。参考工程里它的例化被注释掉了，
但注释里留着 `m0_axi_*` / `m1_axi_*` 两组信号名 —— 说明**原设计意图就是
"CPU 一路 + 用户逻辑一路"**，A 的合并方案可以直接沿用这个结构。

### 2.4 引脚比对结果（A0-4 已完成）

我逐 `gpio_def` 比了两份 `peri.xml`：SoC 参考 65 个引脚，你的工程 76 个，
**共用 52 个**。其中 48 个是 DDR3/时钟等本来就要共用的，正常。

**真正需要人工解决的冲突只有 2 处：**

| 物理引脚 | SoC 参考工程 | 你的工程 | 建议 |
|---|---|---|---|
| `GPIOL_07` | `i_arstn`（SoC 异步复位） | `key_prev`（按键） | **让 SoC 用板载复位，别占这个键** |
| `GPIOR_27` | `soc_gpio[0]`（备用 GPIO） | `nrst`（板载复位键） | **丢掉 `soc_gpio[0]`，保留 `nrst`** |

两处都能靠**放弃 SoC 侧的非必要引脚**解决，不用改板子：

- `GPIOL_07` 物理上就是板载 KEY1。SoC 参考工程把它当复位输入用（按键按下=复位），
  但这样你就少了"上一张"键。**正确做法是让 SoC 的复位接到和其余逻辑同一套
  复位网络**（`nrst` + PLL lock 同步），而不是单独占一个按键。
- `GPIOR_27` 物理上是板载复位键，你已经在用。SoC 参考把它配成一个用户 GPIO，
  这个 GPIO 没有任何东西依赖，直接不接。

> 注：`GPIOB_P_04` / `GPIOB_P_09` 在两边叫 `verf1`,`verf0` vs `vref1`,`verf0`
> —— 只是拼写不一致，不是冲突，合并时统一一下名字即可。

**SoC 需要新增的 13 个引脚**（你的工程里全空着，加进去不冲突）：

| 用途 | 引脚 |
|---|---|
| UART0（`bsp_printf` 走这里，调试必需） | `GPIOL_02` (rxd)、`GPIOR_28` (txd) |
| 自定义 GPIO（可不用，`soc_gpio[0]` 直接丢） | `soc_gpio[1]`=`GPIOR_24`、`[2]`=`GPIOL_P_12`、`[3]`=`GPIOL_P_02` |
| SPI0（用不到可不接） | `GPIOL_P_03`、`GPIOL_N_03`、`GPIOL_N_01`、`GPIOL_P_01` |
| **JTAG（烧程序/调试必需，别被占）** | `GPIOR_15` (tck)、`GPIOR_12` (tdi)、`GPIOR_16` (tdo)、`GPIOR_19` (tms) |

**优先级**：UART0 和 JTAG 一定要留出来 —— 没有它们你没法 load 程序、没法打印调试。

---

## 3. 最大的合并风险：两边 DDR3 控制器配置不同

我逐文件 diff 了两边的 `ddr3_controller/`，**几乎所有文件都不同**，其中
`ddr3_parameter.vh` 有实质性差异：

| 宏 | `ddr_demo_ti60` | `udp_image_demo` | 影响 |
|---|---|---|---|
| `ADDR_WIDTH` | 28 | 30 | 寻址范围不同 |
| `AXI_ADDR_WIDTH` | 28 | 32 | AXI 地址位宽不同 |
| `tPRDI` | 有 | 无 | 时序参数不同 |
| `TX_CLK_SEL` / `TX_CLK_90EDGE_SEL` | 3 / 0 | 0 / 3 | **PHY 发送时钟选择相反** |
| `ASYN_AXI_CLK` | 0（同步） | 1（异步） | **AXI 时钟域架构不同** |

`ASYN_AXI_CLK` 和 `TX_CLK_SEL` 这两条尤其要注意：前者决定 AXI 是否跨时钟域，
后者直接影响 PHY 校准。**不能直接把 SoC 接到你现在这份 DDR3 控制器上就完事**，
必须先确定用哪一份配置，然后重新跑校准验证。

**行动**：这件事优先做（见第 4 节 A0-2），它决定后面所有工作的基础。

---

## 4. 行动清单

> 原则：**不等板子也能做的一律先做**。文档里说"开发板未到"，那么阶段 0 和
> 阶段 1 的大部分都能推进。

### 阶段 0：把参考工程跑起来（1 周内，最高优先级）

| 编号 | 任务 | 产出 | 卡点 |
|---|---|---|---|
| A0-1 | 把 `par/ddr_demo_ti60/` 整个拷到你自己的工程目录，用 `efx_run` 编译一遍 | 能编译出 bit 的 SoC 工程 | Efinity 版本、license |
| A0-2 | **diff 两份 DDR3 配置，定用哪份**（见第 3 节） | 一份确定的 `ddr3_parameter.vh` | 需要板子才能验证校准 |
| A0-3 | 从 `embedded_sw/soc/` 编译一个 standalone 例程，跑通 ELF 生成流程 | 能生成 ELF | RISC-V 工具链是否装了 |
| A0-4 | ~~核对引脚冲突~~ **已完成，见 2.4** —— 只剩 2 处冲突要按建议处理 | 引脚分配表 | 已无未知项 |
| A0-5 | 装 RISC-V 工具链 + 确认烧录/调试流程（Sapphire 用 soft TAP / JTAG） | 能 load 程序 | 环境搭建 |

**A0-2 是全项目最关键的一步**，建议拉着 B 一起定。

### 阶段 1：合并 SoC + HDMI（M1 主体）

| 编号 | 任务 | 说明 |
|---|---|---|
| A1-1 | 以 `udp_image_demo/fpga/rtl/top.v` 为底，加进 SoC | 保留你已验证的 HDMI + DDR3 + 时序约束 |
| A1-2 | 插入 `Axi_Mux`，SoC 和"用户逻辑口"共享 DDR3 | 用户逻辑口先接你的读写状态机，之后换成 B 的加速器 |
| A1-3 | 统一时钟/复位 | SoC 要 100 MHz；你现在 `sys_clk` 是 9.26 ns(≈108 MHz)。见第 5 节决策 3 |
| A1-4 | 加 APB slave 0 的空壳寄存器（只读 ID 就行） | 让 C 能先写驱动 |
| A1-5 | **验收：CPU 写一块 DDR，HDMI 显示出来** | M1→M2 的门禁 |

### 阶段 2：填接口约定（M1 的正式交付物）

第 6 节我起了一版草案，你带去开会改。

### 阶段 3：M2 的 A 侧（Solid Fill 联调）

- 把 B 的加速器作为 Axi_Mux 的第二路接进去
- 确认加速器写的 Framebuffer 区域 = HDMI 读的区域
- 板子到了以后负责上板：时钟、复位、DDR 初始化、HDMI 输出

---

## 5. 需要你和 B/C 一起拍板的 4 个决策

**决策 1：内存布局怎么分？**
现在 `udp_image_demo` 把 DDR 前 16 MiB 划成 8 个 2 MiB 图片槽。加了 CPU 之后要重划：
CPU 代码/数据、堆栈、Framebuffer A、Framebuffer B、图片素材区、加速器临时区。
**注意 CPU 只有 4 KB 系统 RAM，其余全在 DDR**，所以 DDR 布局就是软件的内存布局。

**决策 2：显示内容谁来写？**
- 方案甲：CPU 直接写 Framebuffer（简单，但 CPU 慢）
- 方案乙：加速器写到后台 Framebuffer，VSYNC 切屏（就是你现在的机制，也是赛题要的）

建议乙 —— 现有实现已经验证过，而且 M3 要拿它做 CPU/FPGA 对比。

**决策 3：系统时钟怎么统一？**
SoC 参考是 100 MHz；你的 `sys_clk` 是 9.26 ns ≈ 108 MHz。要么把 SoC 配成 108，
要么统一到 100（要重算 HDMI 时序 PLL 和 DDR3）。**这个必须在 A1-1 之前定**，
否则返工。

**决策 4：AXI 位宽和 ID 怎么分？**
`Axi_Mux` 是 128-bit。多个 master 共用时 AXI ID 必须唯一，否则响应会串。
你现在的读写状态机写死了 `awid=1` / `arid=2`，加进 mux 后要重新分配。

---

## 6. 接口约定 V1 草案（A 侧建议值）

> 原文档第 3 节的五张表（3.1 总表 / 3.2 寄存器 / 3.3 内存布局 / 3.4 换帧规则 /
> 3.5 版本记录）目前全是空的。下面是我按现有工程实测情况填的建议值，
> **加粗**的建议直接采用，其余待议。3.4 和 3.5 我给出了结构，内容需要 B/C 补。

### 6.1 接口约定总表（对应原文档 3.1）

| 项目 | 建议值 | 依据 |
|---|---|---|
| **显示分辨率与刷新率** | **1280×720 @60Hz**（赛题最低 640×480，已验证 720p，先不降） | 现有工程实测 |
| **像素格式与字节序** | **RGB565，小端，2 B/像素** | 现有工程实测，HDMI 编码已按此实现 |
| **宽高与 stride** | **stride = width × 2**（1280×2=2560，天然 16 字节对齐，暂不加行填充） | 现有实现 |
| DDR / Framebuffer 布局 | **待定（决策 1）** | 需重新规划 |
| **控制总线** | **APB slave 0 @ `0xF8100000`，64 KB** | `soc.h:66` |
| **数据总线** | **AXI4，128-bit，INCR，burst ≤16 beat** | `Axi_Mux.v` + 现有 DDR3 控制器 |
| 命令字段 | 见 6.2 草案 | 需 B 确认 |
| **START/BUSY/DONE 语义** | **START 单次触发；BUSY 期间忽略新 START；DONE 保持到下次 START；ERROR 粘滞到写清除** | 建议，需 B 确认 |
| Burst / FIFO 握手 | AXI4 标准握手，FIFO 深度由 B 定 | B 主 |
| **Double Buffer 换帧规则** | **写后台 → 整帧完成 → 等 VSYNC 切基地址 → 旧前台可重用** | 现有实现已验证 |
| 时钟复位 | **待定（决策 3）** | 两边不同 |
| 素材格式与加载 | PC 端转 RGB565 小端 raw + JSON 元数据；加载走 UDP 或直接烧进 DDR | 现有 `pc/` 工具可直接复用 |
| 驱动 API / 超时 | `gpu_fill()` / `gpu_copy()` / `gpu_wait_done(timeout)` | 照 `apb3Demo` |

### 6.2 寄存器映射草案（对应原文档 3.2，供 B 参考）

基地址 `0xF8100000`。**以下是我按 BitBlt 常见需求起的草案，B 有权改，但一改就要更新这张表。**

| 偏移 | 名称 | R/W | 位宽 | 说明 |
|---|---|---|---|---|
| 0x00 | ID | R | 32 | 固定魔数 + 版本，驱动用来探测 |
| 0x04 | CTRL | W | 32 | bit0 START（自清）；bit1 模式（0=Fill 1=Copy） |
| 0x08 | STATUS | R | 32 | bit0 BUSY；bit1 DONE；bit2 ERROR |
| 0x0C | IRQ_EN | RW | 32 | 中断使能（可留到 M4） |
| 0x10 | DST_ADDR | RW | 32 | 目标基地址 |
| 0x14 | DST_STRIDE | RW | 32 | 目标行字节数（暂 = width×2） |
| 0x18 | SRC_ADDR | RW | 32 | 源基地址（Fill 时忽略） |
| 0x1C | SRC_STRIDE | RW | 32 | 源行字节数 |
| 0x20 | WIDTH | RW | 32 | 像素宽 |
| 0x24 | HEIGHT | RW | 32 | 像素高 |
| 0x28 | COLOR | RW | 32 | Fill 颜色（RGB565 在低 16 位） |
| 0x2C | COLOR_KEY | RW | 32 | Color Key 值 + 使能（M4） |
| 0x30 | ALPHA | RW | 32 | 全局 Alpha + 使能（M5） |
| 0x34 | DONE_COUNT | R | 32 | 完成次数，调试用 |
| 0x38 | ERROR_CODE | R | 32 | 出错原因 |

### 6.3 内存布局草案（对应原文档 3.3）

**需先确认 DDR 实际容量**（两份配置推算不同，见第 3 节）。假设够用，建议：

| 区域 | 大小 | 用途 |
|---|---|---|
| 0x0000_0000 | 视容量 | **不用**（避免和低位地址陷阱冲突，也方便调试） |
| 0x0100_0000 | 8 MiB | CPU 代码 + 数据 + 堆栈（软件 ELF 加载区） |
| 0x0200_0000 | 2 MiB | Framebuffer A |
| 0x0220_0000 | 2 MiB | Framebuffer B |
| 0x0240_0000 | 32 MiB | 图片素材区（可放 16 张 720p） |
| 0x0440_0000 | 2 MiB | 加速器临时/中间缓冲 |
| 「以上」 | 0x0100_0000 | 软件可用堆（最大的一块） |

> 这只是草案。**必须先确认 DDR 容量和软件 linker script 的约定**再定稿。

---

## 7. 我踩过的坑（别再踩一遍）

1. **Efinity SDC 约束必须写在 `create_clock` 之后。** 写在前面不报错、不警告，
   整条被静默丢弃。判断是否生效看 `outflow/*.timing.rpt` 里的
   **Clock Relationship Summary** —— 目标时钟对应当从表里消失。
   （我在这上面白跑了 3 次编译。）

2. **`build.sh` 会被旧 bit 骗。** `efx_run` 即使 map 失败也可能返回 0，
   而脚本只检查 `.bit` 是否存在。已在 `udp_image_demo/fpga/build.sh` 里加了
   `rm -f outflow/*.bit`，新工程记得照做。

3. **按键和 LED 引脚复用。** 板子上 `key_i[1]`/`key_i[2]` 就是 `b_led[0]`/`b_led[1]`
   用的 GPIOR_21/GPIOR_22。能同时用的只有 GPIOL_07 和 GPIOL_03。

4. **DC_FIFO 的跨时钟复位握手会报假负 slack。** 它在 DC_FIFO 内部，外面改不了，
   只能在 SDC 里对每对"FIFO 写时钟/读时钟"加 `set_false_path` 双向排除。
   另外 FIFO 的 `Reset` 别接另一个时钟域数出来的信号。

5. **引脚命名两套。** 参考工程用 `ddr_addr[15:0]`，你的工程用 `addr[15:0]` +
   `o_dq_hi/o_dq_lo`。合并时别被名字骗了以为引脚不同，**要按物理 `gpio_def` 核对**。

---

## 8. M1 验收门禁（文档原文 + 我的落地判据）

| 文档要求 | 怎么算过了 |
|---|---|
| 接口约定完成 | 第 3.1–3.5 五张表填满，A/B/C 三人签字（哪怕是聊天记录确认） |
| 官方工程可编译 | `ddr_demo_ti60` 合并 HDMI 后能编译出 bit |
| 软件工程可编译 | `embedded_sw` 能生成 ELF，能 load 进 SoC |
| 最小 RTL Testbench 可运行 | B 的侧 |
| HDMI 工程可复现 | 别人照文档能在自己电脑上编译出同样的 bit |

---

## 9. 建议的下一步顺序（最小闭环）

```
A0-2  定 DDR3 用哪份配置  ← 先做这个，它卡住后面一切
  ↓
A0-1  把参考工程编译通过
  ↓
A1-1  加 SoC 进 udp_image_demo 的 top.v
  ↓
A1-2  插 Axi_Mux（第二路先接你自己的读写状态机）
  ↓
A1-5  验收：CPU 写 DDR → HDMI 显示出来
  ↓
     这时把 B/C 拉进来，接口约定定稿 → 进 M2
```

**最省力的路径**：不要新建工程，直接在 `udp_image_demo` 上长。它已经有时序
收敛的 DDR3 + HDMI + 已验证的 Framebuffer 机制，是这三样里最难调的。
把 SoC 当成一个新模块加进去，比反过来从头配 HDMI 容易得多。
