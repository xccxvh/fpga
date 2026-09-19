# RGB565/720p 联合接口 —— 待解决问题清单

- 日期：2026-09-19
- 提出：A（系统平台与显示集成）
- 收件：B、C
- 依据：`rgb565_720p_migration.md`（分支 `feature/rgb565-720p-integration` 版本）、
  `bitblt_interface_v0.2.md`、`jzy/riscv_game/driver/protocol_*.h`

---

## 0. 结论

**接口尚未统一。** 分三类：

- **P1–P3 阻塞项** —— 不解决就无法动手，A/C 各自按自己的理解写会撞车
- **P4–P5 待确认项** —— 迁移文档自己列的"尚需落实或确认"
- **P6 排期问题** —— 不是接口问题

---

## P1 🔴【矛盾】UDP 完成通知的地址，两份在库文档说法相反

| 出处 | 说法 |
|---|---|
| `rgb565_720p_migration.md`（**分支版，较新**） | "UDP接收器的完成通知使用SoC现有APB slave 0窗口中的 **`0xF8100100–0xF81001FF`**，与BitBlt/显示的SYSTEM_AXI_A寄存器物理隔离。**A组负责APB slave实现**" |
| `jzy/riscv_game/driver/protocol_unfrozen.h` | "A组草案提过的 APB 那一套**已被迁移文档明确否掉**，那份草案的地址同样不能拿来用" |

**补充事实**：`origin/main` 上那份迁移文档是**旧版**，原文是"该新增接口的总线/地址由A与C在接入SoC时确定"——
它只说"BitBlt和显示**不迁到**这套APB表"，**并没有否掉 UDP 通知用 APB**。
`protocol_unfrozen.h` 是针对旧版写的，但把"BitBlt/显示不迁"读成了对整个 APB 方案的否决。

**影响**：
- A 已按分支版实现（`rwj/udp_image_demo/fpga/rtl/frame_status_apb.v`，占 `0x100–0x1FF`）
- C 的 `protocol_udp_completion_available()` 当前恒返回 0，不会去读这个地址，
  所以**现在不会撞车，但一旦 C 按另一份文档"确认可用"就会撞**

**需要**：B/C 明确以哪份为准。若以分支版为准，`protocol_unfrozen.h` 那段注释需要更正
（它与分支版直接冲突）。

---

## P2 🔴【缺失】寄存器字段偏移表不存在

迁移文档写："A组负责APB slave实现，C组通过32-bit MMIO访问；**具体字段偏移以A/C对齐表为准**。"

**但这份"对齐表"全仓库不存在。**

C 侧 `protocol_unfrozen.h` 里只有：

```c
uint32_t udp_completion_reg_addr;   /* 只有一个基址 */
uint32_t udp_completion_irq_id;
```

**没有字段布局。** A 侧已有实现，需要 C 确认后才能写驱动：

| 偏移 | 名称 | R/W | 说明 |
|---|---|---|---|
| `0x100` | `FRAME_ID` | R | 快照：帧号 |
| `0x104` | `SLOT` | R | 快照：写入槽位 |
| `0x108` | `BASE_ADDR` | R | 快照：实际写入的 DDR 基址 ← P3 要靠它核对 |
| `0x10C` | `RX_BYTES` | R | 快照：实际写入字节数 |
| `0x110` | `EXPECT_BYTES` | R | 快照：START 声明字节数 |
| `0x114` | `FRAME_STATUS` | R | 快照位图（A 侧代码里叫 `STATUS`，可改） |
| `0x118` | `ACK` | **W** | 写已消费的 SEQ；匹配才清 `ERR_STICKY` |
| `0x11C` | `SEQ` | R | 完成帧序号，32-bit，复位 0，允许回绕 |
| `0x120` | `SWAP_SEQ` | R | 显示端实际切屏次数 |
| `0x124` | `SWAP_FRAME` | R | 切上屏的是哪一帧 |
| `0x128` | `ERR_STICKY` | R/W | 跨帧累积错误，写任意值清 |
| `0x12C` | `ID` | R | 魔数 `0x46524D31`（"FRM1"），用于探测位流 |
| `0x130` | `LIVE_STATUS` | R | bit0 `CAL_DONE`，实时读，不参与快照 |

`FRAME_STATUS` 位（纯快照）：bit0 `DONE`｜bit1 `FRAME_OK`｜bit2 `SEQ_ERR`｜
bit3 `FIFO_OVF`｜bit4 `BRESP_ERR`｜bit5 `BYTES_MISMATCH`｜bit6 `SWAPPED`｜bit7 保留。

**需要**：A/C 确认这张表，产出一份公共头文件（C 的 `protocol_frozen.h` 里提到的
"B 一同步就删掉代持"是同一个模式 —— A/C 这边也该有一份唯一的定义）。

---

## P3 🔴【缺失】软件如何把"授权的后台地址"传给 A 的硬件，机制未定义

迁移文档换帧规则：

> 2. UDP集成版由软件指定/授权实际物理后台地址，**硬件在START时锁存**；
>    网络包自带slot或旧`active_slot ^ 1`不能覆盖软件授权。
> 5. ……软件能够核对**实际写入基址与被授权的后台基址一致**。

C 侧已经有软件状态机（`jzy/riscv_game/render/frame_swap.h` 的
`frame_swap_acquire_back(who)`），也有 `frame_swap_udp_frame_ready(fs, reported_base, frame_ok)`
用来接收 A 上报的基址。

**但中间那一环没有定义：软件怎么把授权地址送到 A 的硬件？**

现状：
- 现有 UDP 16 字节包头里 `slot` 只有 **1 字节**（槽位号 0..7），**装不下 32 位物理地址**
- `frame_swap.h` 里没有任何"写硬件授权寄存器"的路径
- 迁移文档说"硬件在START时锁存"，但 START 包里没有这个字段

**需要三方定义**，两个候选方向（A 不预设）：

| 方案 | 说明 | 代价 |
|---|---|---|
| **甲：包头新增字段** | 复用 `packet_idx` 之类的备用字段，或扩包头 | 改 PC 发送工具 + A 的解析 + C 的发送侧；包头是三方共用契约 |
| **乙：APB 寄存器块加一个 C 可写的授权寄存器** | A 在 `0x1xx` 段加一个 RW 寄存器，C 写、UDP 硬件在 START 时读走 | 不动包头；但 A 的 UDP 逻辑要能读寄存器（跨域） |

---

## P4 🟡【待确认】A 组 UDP 输入的细节

迁移文档"尚需落实或确认"章节原文：

> 确认A组UDP输入的行填充、端序、丢包处理及硬件写后台的仲裁方式。

**A 侧现状（供确认）**：
- 端序：小端，`RGB565` 低字节在低地址，与迁移文档"低地址为像素低8位"一致 ✓
- 行填充：`stride = width × 2 = 2560`，**无行填充**，天然 16 B 对齐
- 丢包处理：`packet_idx` 断号/重复 → `SEQ_ERR`；FIFO 溢出 → `FIFO_OVF`；
  两者都令 `frame_ok=0`，失败帧**不切屏**但**仍发布带错误信息的快照**（符合迁移文档）
- 写后台仲裁：**当前 A 的写状态机是唯一的 AXI 写主**；合并后要挂到 B 的写仲裁器上，
  **AXI ID 分配待定（见 P5）**

---

## P5 🟡【待确认】时钟、DDR 控制器配置与 AXI ID

迁移文档原文：

> 确认A/B合并使用的DDR控制器配置、100 MHz SoC时钟与74.25 MHz像素时钟，
> 以及AXI master ID分配；这些尚未由统一位流实测。

**A 侧可提供的实测依据**（2026-09-19）：
- DDR3 配置**不可逐参数混搭**：两份工程各有一套完整可用的组合，混搭实测花屏
  （详见 `rwj/udp_image_demo/A0-2_DDR3配置统一.md` 顶部红框）
- 合并应整份沿用 B 的配置，A 不提出任何参数变更
- A 的 `sys_clk` 目前是 108 MHz，若统一到 100 MHz 需重跑时序

---

## P6 ⚪【排期】B 的 RGB565 实现尚未开始

迁移文档"B组迁移边界"列了 4 条，全是 B 的 RTL：

1. BitBlt Fill/Copy/Color Key 按 8×16-bit 像素/beat；`stride >= width×2`；宽度 8 像素倍数
2. 显示 DMA 提取 RGB565 并扩展到 RGB888 输出
3. 显示控制器校验 1280×720/2560 stride/新格式；时序与 PLL 改 74.25 MHz
4. C 侧帧缓冲/素材打包/网络写入全部改用 RGB565

**核实过 B 的现状**：BitBlt `VERSION = 0x00010004`、Display `VERSION = 0x00020000`、
`FORMAT` 只接受 `0`、`pixel_unpack_xrgb8888.v` 是唯一解包器。
**C 的 `protocol_frozen.h` 对此的描述是准确的。**

→ 这解释了为什么"匹配协议的联合位流"现在产不出来：**不是编译问题，是 RGB565 通路还不存在。**

---

## 附：A 侧已完成且与迁移文档逐条吻合的部分

`frame_status_apb.v` 已实现并通过仿真（41 项检查），与迁移文档
「UDP完成通知与ACK协议」章节逐条对应：轮询不接 PLIC 源30、SEQ 允许回绕、
快照同拍锁存、`LIVE_STATUS` 独立、失败帧也发布快照、ACK 匹配才清 `ERR_STICKY`、
跨域整组握手。**所以 P1/P2/P3 一解决，A 侧就能接进顶层。**

尚未上板：该模块还没有被例化（没有 SoC 就没有 APB master），要等 A1-1。
