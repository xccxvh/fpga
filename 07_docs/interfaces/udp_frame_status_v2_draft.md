# UDP Frame Status V2 协议冻结草案

- 日期：2026-09-19
- 提出：C（RISC-V 软件）
- 状态：**协议冻结草案（A/B 第一轮评审完成，A/C 字段协议基本对齐；
  仍待 B 确认 block base / APB 时钟域 / VERSION / APB 未映射行为）**
- 待确认项一律标注 `待A确认` / `待B确认` / `待A/C确认`，C 侧在确认前不会写进代码。

依据：

- `rwj/udp_image_demo/fpga/rtl/top.v` 实测信号（A 组已提交的实现）
- `07_docs/interfaces/rgb565_720p_migration.md`（团队统一目标）
- `07_docs/interfaces/bitblt_interface_v0.2.md`（BitBlt/显示已冻结基线）
- UDP Frame Status 软件侧静态检查（第二阶段结论）
- **A 侧答复《UDP Frame Status V2 —— A侧答复》**
- B 侧第一轮评审回复

> 本文件已放在 `07_docs/interfaces/`，与其它接口文档同级。
> 但文件名里的 `_draft` **必须保留到 B 的 4 项平台确认完成、正式冻结为止**——
> 它是草案，不是基线。冻结后去掉 `_draft` 并补齐版本记录。

---

## 0. 已知前提

```text
APB Slave 0  base = 0xF8100000        （soc.h: IO_APB_SLAVE_0_INPUT，已在 BSP 中）
```

窗口划分：

| 范围 | 用途 | 状态 |
|---|---|---|
| `0xF8100000 - 0xF81000FF` | Reserved | 候选 |
| `0xF8100100 - 0xF81001FF` | RX Frame Status（本文件描述的范围） | **候选，待 B 最终确认** |
| `0xF8100200 - 0xF810FFFF` | 未映射 | **行为待 B 决定**（见 §Q） |

> ⚠️ `0xF8100100 - 0xF81001FF` 仍是候选，不是已冻结的团队地址分配。
> A/C 的字段协议已对齐，但**字段对齐 ≠ 地址分配冻结**。

MVP 采用：

```text
Polling，不使用 IRQ
通知机制 = Snapshot + 32-bit SEQ + matching ACK
```

---

## A. A/C 已对齐的候选寄存器表

**A/C 字段协议已基本对齐。** A 已明确撤回早期草案中的 `ID` / `SWAP_SEQ` /
`SWAP_FRAME` 三个字段，并接受 C 的寄存器顺序。

| 偏移 | 名称 | R/W | 复位值 | 分类 | 说明 |
|---:|---|---|---:|---|---|
| `+0x00` | `SEQ` | RO | `0` | **commit 标志** | 快照发布时 +1 |
| `+0x04` | `FRAME_STATUS` | RO | `0` | **snapshot** | 见 §E |
| `+0x08` | `FRAME_ID` | RO | `0` | **snapshot** | 高 16 位恒 0 |
| `+0x0C` | `SLOT` | RO | `0` | **snapshot** | 保留 3-bit，仅供诊断 |
| `+0x10` | `BASE_ADDR` | RO | `0` | **snapshot** | **权威地址** |
| `+0x14` | `RX_BYTES` | RO | `0` | **snapshot** | |
| `+0x18` | `EXPECT_BYTES` | RO | `0` | **snapshot** | |
| `+0x1C` | `ACK_SEQ` | WO | `0` | 控制 | 见 §F |
| `+0x20` | `LIVE_STATUS` | RO | — | **live** | 见 §L.1 |
| `+0x24` | `ERR_STICKY` | RO | `0` | **live** | 见 §H |
| `+0x28` | `VERSION` | RO | 待定 | **static** | 推荐 `0x00010000`，**待 B/C 最终分配** |
| `+0x2C` | `AUTH_BASE` | RW | `0` | 控制 | 见 §AUTH |
| `+0x30` | `AUTH_CTRL` | WO | `0` | 控制 | `bit0 = ARM`，其余 reserved |
| `+0x34–0xFC` | Reserved | RO | `0` | — | 读回 0，写入忽略 |

### A.0 文档与 RTL 的对齐状态

> 截至本文件更新时，`frame_status_apb.v` **尚未提交到本仓库**。
> 因此上表是**协议层面**的 A/C 对齐结果；等 A 提交 RTL 后，
> 仍需逐项核对源码与本表一致（这是验证动作，不是待定项）。

### A.1 `AUTH_CTRL`

```text
bit0      = ARM
bit1~31   = reserved，读 0，写忽略
```

写 `ARM = 1` 后，由硬件在**下一帧 START 时消费并自清**（一次性）。

### A.2 布局评估

**对齐**：全部 32-bit 对齐。头部占用 `0x00–0x33`，窗口还剩 204 B。

**地址冲突**：无。`0xF8100100` 落在 APB slave 0 的 64 KB 内；
UART0 (`0xF8010000`)、GPIO0 (`0xF8015000`) 在别的段。

---

## AUTH_BASE 授权通路（A/C 已原则一致）

> A/C 已原则同意使用 APB `AUTH_BASE` + 一次性 `ARM` 的授权方案。

### AUTH.1 缺口描述

```text
C 已经能决定后台 framebuffer                    ✓（frame_swap_acquire_back）
A 完成后也能报告 BASE_ADDR                      ✓（snapshot.BASE_ADDR）
C → A 的「本帧只允许写哪个 framebuffer」授权通路   ← 由本节补齐
```

没有这条通路，硬件无从知道 C 把哪一块后台授权给了 UDP 生产者，
「生产者不得写正在扫描的前台」这条约束在硬件侧无法落地。

### AUTH.2 流程

```text
C  acquire_back(UDP)
   ↓
   得到 fs->back
   ↓
   WR AUTH_BASE = fs->back
   ↓
   WR AUTH_CTRL.ARM = 1
   ↓
A  下一帧 START 消费授权
   ↓
   锁存 AUTH_BASE
   ↓
   ARM 自清
   ↓
   整帧只能使用该锁存地址
   ↓
   snapshot.BASE_ADDR 回报硬件【实际使用】的地址
   ↓
C  校验 snapshot.BASE_ADDR == fs->back
```

### AUTH.3 立场（已确认）

- 采用 APB `AUTH_BASE` + 一次性 `ARM`；
- **不**让 UDP 网络包直接携带并决定 DDR 写地址
  ——迁移文档明确要求"网络包自带 slot 或旧 `active_slot^1` 不能覆盖软件授权"；
- `BASE_ADDR` **必须是硬件实际锁存并使用的地址**，不是软件写入期望值的回显；
- 软件仍保留 `snapshot.BASE_ADDR == fs->back` 的校验（硬件约束 + 软件校验双保险）。

### AUTH.4 无授权 START 的行为

方向已定：**拒绝该帧 + `AUTH_ERR`**。

仍需 A/C 最后确认一个小项：

> **START 无授权产生 `AUTH_ERR` 后，硬件是否仍发布一份坏 snapshot 并推进 SEQ？**
>
> 如果**完全不发布** snapshot，C 将无法通过 Frame Status 接口观察到这个 `AUTH_ERR`
> ——错误只存在于硬件内部，软件侧表现为"这一帧凭空消失了"。

`待A/C确认`，**不擅自决定**。

---

## B. R/W 属性

见 §A 表。补充三条：

1. 全部寄存器 **32-bit 访问**；`SLOT` / `FRAME_ID` 高位置 0。
2. `ACK_SEQ` 与 `AUTH_CTRL` 是 **WO**，读回 `0`——不提供回读，避免软件误以为它们是状态。
3. Reserved 区**读回 0、写入忽略**，不要留未译码空洞。

---

## C. reset 值

全部 `0`，`VERSION` 除外。

`SEQ` reset 后为 `0`，**第一帧完成后发布 `SEQ = 1`**。
即 SEQ 表示"已发布快照的计数"，`0` = 一个都没有。

---

## D. snapshot / live 分类

| 分类 | 寄存器 | 语义 |
|---|---|---|
| **snapshot**（与 SEQ 同拍、该 SEQ 内不可变） | `FRAME_STATUS` `FRAME_ID` `SLOT` `BASE_ADDR` `RX_BYTES` `EXPECT_BYTES` | 属于**同一个 `frame_done`** 的一整帧 |
| **commit 标志** | `SEQ` | 快照的提交点（逻辑语义，见 §D.1） |
| **live** | `LIVE_STATUS` `ERR_STICKY` | 可随时变化，**不属于任何 SEQ** |
| **static** | `VERSION` | 常量 |
| **控制** | `ACK_SEQ` `AUTH_BASE` `AUTH_CTRL` | 写口 |

> ⚠️ **`ERR_STICKY` 不是 snapshot。**
> 它可能在软件读完 `SEQ` 之后、读 `ERR_STICKY` 之前被新的 publish 改变。
> 所以软件**不得**用两次读的组合去推断某一帧的状态——这正是 §H 规则的来源。

### D.1 snapshot commit 语义（已修正）

**最终协议语义：**

> snapshot 字段和 SEQ 必须以**软件不可观察到撕裂状态**的方式**原子发布**。

A 当前实现：

```text
同一个 always block
同一时钟沿
所有 snapshot 字段 + SEQ
使用 nonblocking assignment 并行更新
```

**C 接受这种实现。**

因此：

```text
"SEQ 是 commit 标志"
```

是**逻辑语义**，**不是**要求 RTL 必须把 SEQ 延后一拍更新。

> 早期草案里"锁存字段 →（下一拍）再更新 SEQ"的写法容易被误读成对 RTL 的时序要求，
> 那种理解**作废**。要求只有一条：**软件不能观察到撕裂**。

软件侧 seqlock 仍然保持：

```c
s0 = RD(SEQ);
/* read fields */
s1 = RD(SEQ);

if (s0 != s1)
    retry;
```

---

## E. FRAME_STATUS bit 定义（A/C 已确认）

**最终紧凑表：**

| bit | 名称 | 含义 |
|---:|---|---|
| 0 | `FRAME_OK` | 整帧完整、可显示 |
| 1 | `SEQ_ERR` | 断号 / 重复 / 帧号与 START 不一致 |
| 2 | `FIFO_OVF` | 接收 FIFO 溢出 |
| 3 | `BRESP_ERR` | DDR 写响应错误（BRESP） |
| 4 | `LEN_ERR` | `RX_BYTES != EXPECT_BYTES` |
| 5 | `NO_DATA_ERR` | `frame_expect == 0`（A 已确认） |
| 6 | `AUTH_ERR` | 无授权 START 被拒 |
| 7–31 | Reserved | 读 0 |

### E.1 `FRAME_OK` 判据

```text
FRAME_OK = (bit1 ~ bit6 全部为 0)
```

即**没有任何错误位**时 `FRAME_OK = 1`。

> 早期草案里按旧 bit 编号写的 `!(bit3|bit4|bit5|bit6|bit7)` 表达式**已作废**，
> 与最终紧凑表不一致。

### E.2 明确不属于 FRAME_STATUS 的两项

| 项 | 归属 | 理由 |
|---|---|---|
| `ARP_MISS` | **诊断信息**，不在 FRAME_STATUS | 它是 rxc 域 2FF 同步过来的**全局**条件，不是某一帧的字节内容；且已提交 RTL 的 `frame_ok` 表达式里根本没有它 |
| `CAL_DONE` | **`LIVE_STATUS`** | 实时状态，不属于帧快照；`SEQ == 0` 时也必须可读 |

### E.3 已删除 DONE 位

**不再有 `DONE` 位。** `SEQ` 已经承担 commit / 新快照检测语义
（`seq != last_seq` 即"有新帧"），重复的 DONE 位只会制造第二个真相源。

---

## F. ACK_SEQ 语义（A/C 已确认）

### F.1 命名

**叫 `ACK_SEQ`。** 已提交 RTL 里存在的 `frame_ack` 是 **UDP 网络层回执包**
（`udp_ack_tx` 发出的 24 字节载荷，见 `top.v:700-727`），与本寄存器无关。

### F.2 行为

```text
ACK_SEQ = 软件刚刚消费的 SEQ

matching ACK：只允许清 ERR_STICKY
```

### F.3 ACK 不改变任何东西（除 ERR_STICKY）

```text
✗ 不改 SEQ            ✗ 不改 FRAME_STATUS      ✗ 不改 FRAME_ID
✗ 不改 SLOT           ✗ 不改 BASE_ADDR         ✗ 不改 RX_BYTES
✗ 不改 EXPECT_BYTES   ✗ 不参与 framebuffer swap
✗ 不作为 producer flow control
```

### F.4 含义

> **"软件已经观察/消费过这个 SEQ 的快照"**

**不是** "这一帧已经成功显示"。

因此：**坏帧也允许 ACK**（软件消费了"这是一帧坏帧"这个事实）。

---

## G. ACK 与新 snapshot 同周期仲裁（A/C 已确认）

**已冻结。** 同周期仲裁正式采用：

```text
publish_new_snapshot 优先于 ACK
```

即使新帧是**好帧**，旧 ACK **也丢弃**，`ERR_STICKY` **保持原值**。

### G.1 实现优先级

```verilog
if (publish_new_snapshot) begin              // 优先级高
    seq        <= seq + 1;
    err_sticky <= err_sticky | new_frame_err;
end else if (ack_wr_valid && ack_wdata == seq) begin   // 优先级低
    err_sticky <= 1'b0;                      // 只清，不置
end
```

两点注意：

1. `ack_wdata == seq` 比的是**自增前**的值；
2. ACK 分支**只清不置**，publish 分支**只置不清**——两条路径不会互相吃掉效果。

### G.2 验收场景

```text
current SEQ = N，CPU 写 ACK_SEQ = N
同周期新帧 N+1 发布且带错误
→ 必须得到：SEQ = N+1，ERR_STICKY = 1
```

> **A 已接受该规则，并将修改 RTL 和 testbench。**

---

## H. ERR_STICKY 语义

```text
ERR_STICKY  ≠  当前 FRAME_STATUS
```

| | `FRAME_STATUS` | `ERR_STICKY` |
|---|---|---|
| 描述对象 | **当前 SEQ 那一帧** | **自上次 matching ACK 以来**出现过的错误 |
| 可变性 | 该 SEQ 内不可变 | 任何 publish 都可能置位；ACK 可清 |
| 用途 | **决定这一帧能不能渲染** | 诊断 / 告警 |

### H.1 必须成立的例子

```text
SEQ 20 = bad
SEQ 21 = good
软件只看到最新：SEQ=21, FRAME_STATUS=GOOD, ERR_STICKY=1
→ SEQ 21 仍然是【好帧】，必须渲染
```

### H.2 C 侧硬性规则

判断当前帧能否渲染，**只能**用 snapshot 字段：
`FRAME_STATUS` / `RX_BYTES` / `EXPECT_BYTES` / `BASE_ADDR`。

**绝不能因为 `ERR_STICKY=1` 就拒绝当前帧。**

---

## I. SEQ 发布与回绕语义

```text
32 bit，RO，reset = 0
每发布一个新快照：SEQ = SEQ + 1  (mod 2^32)
```

软件只允许两种比较：

```c
seq == last_seq
seq != last_seq
```

**禁止**：

```c
seq > last_seq        /* 回绕时会误判 */
```

**必须支持**：

```text
0xFFFFFFFF -> 0x00000000     仍识别为新帧
```

---

## J. latest-snapshot 语义

**这不是 FIFO。**

> 只保证最新完成帧的完整快照可见，**不保证软件观察到所有中间 SEQ**。

```text
SW 轮询间隔内发生 SEQ 20 → 21 → 22
SW 再次轮询只看到 SEQ 22        ← 允许，20/21 无需补处理
```

### J.1 现有 frame_swap 是否兼容

**兼容，但有一个必须补的洞。**

兼容的部分：`frame_swap_udp_frame_ready()` **完全不看 SEQ**——它只校验
`reported_base == fs->back` 和 `frame_ok`。SEQ 比较被刻意留在驱动层。

### J.2 必须补的洞（真实缺陷，不是理论问题）

```text
T0: 软件 acquire_back(UDP) → 授权后台 = B
T1: 软件 poll → 读到的是【上一帧】的快照，BASE_ADDR = A（旧前台）
    → reported_base(A) != back(B) → 当前实现返回 WRONG_OWNER
    → 并且 release_back()，把刚授权的后台【释放掉了】
```

**授权之后第一次 poll，几乎必然误报一次 WRONG_OWNER 并丢掉后台授权。**

根因：`last_seq` 基线与后台授权**不同步**。

### J.3 修法：`resync()` —— 纯软件（已明确）

`frame_swap` 在 `acquire_back(UDP)` 成功的那一刻调用
`udp_frame_status_resync()`。

```text
读取当前 SEQ
→ 保存为 ctx->last_seq
→ 明确丢弃此前已经存在的 snapshot
```

**完全由 C 软件实现。不需要：**

```text
✗ RESYNC 寄存器
✗ 硬件命令
✗ 硬件握手
```

---

## K. CDC 要求

### K.1 已提交 RTL 的时钟域分布（A 已确认）

| 信号 | 域 | 说明 |
|---|---|---|
| `frame_done` `frame_wslot` `frame_rx` `frame_expect` `frame_id_cur` `frame_seq_err` `bresp_err` `rx_bytes` | **`sys_clk`** | 整个帧状态机在 `always @(posedge sys_clk)`（`top.v:359`） |
| `cal_done` | **`sys_clk`** | 来自 DDR 控制器（`top.v:373`） |
| `arp_miss_raw` `img_fifo_ovf` | **rxc** | 已有 2FF 同步（`top.v:210-222`） |
| `frame_tgl` | **像素域** | 已有 2FF 同步（`top.v:539-546`） |

**A 已确认：帧状态链路信号属于 `sys_clk`。**

### K.2 目标方案

A 建议最终：

```text
APB slave
+
frame status FSM
统一在平台 user_clk / sys_clk = 100 MHz
→ 从而实现零 CDC
```

> **但最终 APB slave 0 挂哪个时钟仍由 B 确认**（见「仍需 B 最终确认」第 2 项）。

### K.3 A 当前保留的两域握手机制

A 当前**保留** toggle + 整组锁存的两域握手机制。**即使最终同域也可以保留**
——成本很小，可防未来时钟方案变化。

### K.4 无论哪种方案都必须满足

1. rxc 域的 `arp_miss` / `fifo_ovf` **必须用已同步的版本**
   （`arp_miss_sync[1]` / `ovf_sync[1]`），不能用 raw；
2. **禁止**每个 snapshot 字段各自打两拍同步——那会让 SEQ 与字段来自不同帧；
3. 软件不可观察到撕裂（见 §D.1）。

---

## L. LIVE_STATUS 与 VERSION

### L.1 LIVE_STATUS（A 已实现）

`CAL_DONE` 必须从帧快照中拆出来。

目标：即使**没有任何 `frame_done`、`SEQ` 仍为 0**，RISC-V 也必须能读到 DDR 校准状态。

```text
LIVE_STATUS.bit0 = CAL_DONE
```

A 已实现。考虑一并纳入（可选）：`DDR3_PLL_LOCK` / `SYS_PLL_LOCK`。

`LIVE_STATUS` **不是 snapshot**，实时读，不随 SEQ 变化。

### L.2 与 PC 方向 UDP ACK 包的区别（不要混为一谈）

**这是两条不同的接口，不要合并成一个协议。**

| 消费者 | 接口 | 是否含 `CAL_DONE` |
|---|---|---|
| **CPU（RISC-V）** | `FRAME_STATUS` | **不含** |
| **CPU（RISC-V）** | `LIVE_STATUS` | **含** |
| **PC（上位机）** | 旧 UDP ACK 包 payload | 含（`top.v:721` 的状态字节 bit1） |

正式确认：

```text
CPU-visible FRAME_STATUS：不含 CAL_DONE     ← A 已实现
CPU-visible LIVE_STATUS ：包含 CAL_DONE     ← A 已实现
```

> **PC 方向旧 UDP ACK 包 payload 中原有的 `cal_done` bit，本轮暂时不修改。**
>
> 理由：那是另一条接口，而且目前 UDP ACK 回包通路本身不可用
> （A 组记录：ACK 回执曾经被位宽截断静默失效，且当前无板可测）。
>
> **不要把"CPU 的 LIVE_STATUS"与"PC UDP ACK payload"当成同一个协议。**

### L.3 VERSION

```text
UDP Frame Status 需要 VERSION
A 建议 0x00010000（V1.0）
C 原则上接受
等待 B 最终确认 / 分配
```

保持一致：

```text
VERSION 是 IP-local
识别依据 = block base + VERSION
```

即三者的 VERSION 数值**允许相同**，真正的身份判断是 `base + VERSION` 联合判断。

`VERSION` **不属于 snapshot**（常量，不随 SEQ 变）。

### L.4 非 UDP 协议问题：`DISPLAY_VERSION_V0_2` 的命名不一致（B 提出）

B 提醒：现有的

```text
DISPLAY_VERSION_V0_2 = 0x00020000
```

命名与团队"高 16 位主版本、低 16 位次版本"的规则**不一致**——按规则
`0x00020000` 实际是 **V2.0**。建议后续统一名称为 `DISPLAY_VERSION_V2_0`。

> **这不是 UDP Frame Status 协议冻结的阻塞项。**
> 本轮**不擅自修改 Display 代码**或已冻结的协议常量，仅登记。

---

## M. C 侧最终 API 草案

```c
typedef struct {
    uint32_t seq;
    uint32_t status;        /* FRAME_STATUS */
    uint32_t frame_id;
    uint32_t slot;
    uint32_t base_addr;     /* 权威：硬件实际写入基址 */
    uint32_t rx_bytes;
    uint32_t expect_bytes;
} udp_frame_snapshot_t;

typedef struct {
    uint32_t last_seq;      /* 驱动内部基线，不对外 */
    int      inited;
} udp_frame_status_t;

typedef enum {
    UDP_FRAME_OK = 0,
    UDP_FRAME_NO_NEW,        /* SEQ == last_seq */
    UDP_FRAME_ERR_INVALID_ARG,
    UDP_FRAME_ERR_NOT_READY, /* 未 init */
    UDP_FRAME_ERR_IO,        /* 窗口不可访问 */
    UDP_FRAME_ERR_RESYNC_REQUIRED
} udp_frame_status_result_t;

void udp_frame_status_init(udp_frame_status_t *ctx);      /* 以当前 SEQ 为基线 */
void udp_frame_status_resync(udp_frame_status_t *ctx);    /* 纯软件，见 J.3 */

udp_frame_status_result_t
     udp_frame_status_poll(udp_frame_status_t *ctx, udp_frame_snapshot_t *out);

void     udp_frame_status_ack(udp_frame_status_t *ctx, uint32_t consumed_seq);
uint32_t udp_frame_status_live(void);         /* LIVE_STATUS，与 SEQ 无关 */
uint32_t udp_frame_status_err_sticky(void);
uint32_t udp_frame_status_version(void);

/* 纯函数：只吃 snapshot 字段，绝不看 ERR_STICKY —— 可单独单测 */
int udp_frame_snapshot_is_renderable(const udp_frame_snapshot_t *s);
```

### M.1 设计判断

| 问题 | 结论 |
|---|---|
| `last_seq` 放哪 | **驱动 context**（非全局）。`init()` 以当前 SEQ 为基线；`resync()` 显式重设 |
| ACK 谁调用 | 驱动**暴露** `ack()`，由 **frame_swap 调用**——只有它知道"这一帧消费完了" |
| `frame_swap_udp_frame_ready()` | **保留不改**（纯逻辑，现有 5 个 host 测试继续覆盖），另加 `frame_swap_udp_poll()` 走"读快照 → 算 frame_ok → 调它 → ACK" |
| 怎么避免职责互串 | 驱动**只**读寄存器 + 写 ACK/AUTH；frame_swap **只**做状态机；中间靠 snapshot 结构体解耦。frame_swap 的 host 测试**不需要**真 MMIO |

### M.2 resync() 的语义边界

```text
resync() = 丢弃当前已有 snapshot，并把【当前 SEQ】当作新基线
         （调用后第一次 poll 必然返回 NO_NEW）
```

**绝不允许在普通 `poll()` 内部偷偷 resync。**
唯一合法的自动调用点：`frame_swap_acquire_back()` 成功的那一刻（见 J.3）。

### M.3 与 frame_swap 公共错误码的关系

`udp_frame_status_result_t` 是**新驱动内部的 result enum**，与 **frame_swap
公共错误码**不是一回事。

```text
驱动自己的错误类型：第三阶段可按需要设计
frame_swap 公共 ABI：已冻结，不得因为新驱动而擅自改变
```

**`FRAME_SWAP_ERR_NOT_READY` 暂不新增专用错误码**（B 已确认原则，见文末）。

---

## N. 第三阶段测试清单（设计，未实现）

| # | 场景 | 需要的注入接缝 |
|---:|---|---|
| 1 | 无新帧（SEQ == last_seq） | `udp_test_set_seq()` |
| 2 | 正常新帧，全字段正确 | 同上 + 字段设置 |
| 3 | **撕裂保护**：读到一半 SEQ 变 | `udp_test_set_seq_after_reads(n, seq)` |
| 4 | SEQ 回绕 `0xFFFFFFFF→0` | 直接设 SEQ |
| 5 | 错误帧完整快照可读 | `udp_test_set_status()` |
| 6 | ACK 写入值 == 刚消费的 SEQ | 记录式模型（仿 `display_last_call()`） |
| 7 | latest snapshot：跳过中间 SEQ | 连续多次 set_seq |
| 8 | LIVE_STATUS 不依赖新帧 | 独立于 SEQ 的字段 |
| 9 | **ACK_SEQ != current SEQ 时 ERR_STICKY 不得被清** | 模型必须建模该硬件语义 |
| 10 | **AUTH_BASE + ARM 流程**：写序、ARM 自清、`BASE_ADDR` 不匹配时拒绝 | 记录式模型 |
| 11 | **无授权 START**：`AUTH_ERR` 是否能从 snapshot 观察到（取决于 AUTH.4 的答复） | 依赖 A/C 确认结果 |

第 9 条是协议明文要求、但容易被漏掉的项。host 模型不建模它，
"ACK 写错就清错误"这个 bug 会一路溜到板上。

可复用设施：`tests/host_board/stub.c` 的 `mmap(MAP_FIXED_NOREPLACE)` 假内存手法、
`run_scenarios.sh` 的故障注入范式、`display_test_*` 的钩子命名风格。

---

## O. 唯一权威头文件归属（B 已确认原则）

### O.1 不放 `04_project/bitblt_accel/sw/driver/`

B 已明确：该目录语义已经属于 BitBlt / Display，**不往里加 UDP 的东西**。

### O.2 推荐归属

| 阶段 | 位置 |
|---|---|
| **bring-up 阶段** | 按项目已有规则放 `03_bringup/` 下对应的 UDP block 试验目录 |
| **正式工程阶段** | 在 `04_project/` 下建立一个与 `bitblt_accel/` **并列**的 UDP Frame Status block；其 `sw/` 目录保存唯一权威 `udp_frame_status_regs.h` |

> 最终目录名称属于**工程组织事项**，不再是协议语义冻结的核心阻塞项。

### O.3 C 侧引用纪律

```text
只通过 -I 引用
禁止复制
禁止软链
禁止维护第二份 offset 定义
```

> **字段表与 block base 都冻结之前，不创建这份正式头文件。**
> 否则"文档草案"与"头文件"会形成两个真相源。

### O.4 hw-isolation 检查扩展（原则已确认，实现由 C 负责）

原「待 B 确认是否增加第三个头文件」→ 现结论：**需要扩展**。

B 给出的实现要求：不要继续复制 `grep bitblt_regs.h` + `case ...` 这种
**单头硬编码**逻辑，改成**表驱动**检查：

```text
权威头文件                    → 唯一允许引用的实现文件
-----------------------------------------------------------------
bitblt_regs.h                 → driver/bitblt_api.c
display_regs.h                → driver/display_api.c
udp_frame_status_regs.h       → driver/udp_frame_status.c
```

具体实现第三阶段再做。

### O.5 `check-no-addresses` 白名单必须同步扩展

现有 `check-no-addresses` 用硬编码地址清单做白名单。
**UDP Frame Status block base 必须加入该清单**，否则新 APB 地址进入 C 工程后
可能形成**检查盲区**——地址被硬编码却检查不到。

---

## P. 当前冻结状态与流程

### P.1 A/C 侧状态

| 项 | 状态 |
|---|---|
| A/C 字段表 | **基本完成** |
| A/C Snapshot / SEQ / ACK | **完成** |
| A/C AUTH 方案 | **原则完成**，剩一个"无授权错误发布细节"（AUTH.4） |
| A/C FRAME_STATUS | **完成** |
| A/C BASE_ADDR / SLOT / FRAME_ID | **完成** |
| A/C LIVE_STATUS | **完成** |

### P.2 B 仍需确认（4 项）

```text
block base
APB clock
VERSION 最终值
未映射 APB 行为
```

### P.3 冻结流程（已缩短）

```text
C 回复 A 剩余确认项（AUTH.4）
   ↓
B 回复 4 个平台项
   ↓
UDP Frame Status V2 正式冻结
   ↓
去掉文件名里的 _draft
   ↓
建立唯一权威 udp_frame_status_regs.h
   ↓
C 开始第三阶段驱动 + host tests
   ↓
A 同步修改 RTL / TB
```

---

## Q. APB PREADY 风险（A 发现，已核实）

> **这是一条真实的 RTL 风险，不是理论担忧。** 已在本仓库核实。

### Q.1 厂家模块的实际行为

`apb3_top`（文件：`jzy/co_debug_2026/par/ddr_demo_ti60_2026/src/Interrupt.v`）：

```verilog
assign factory_readErrorFlag  = 1'b0;
assign factory_writeErrorFlag = 1'b0;
assign apb_pready = 1'b1;              // ← 恒为 1，组合逻辑
assign apb_prdata = 32'h0;             // ← 恒为 0
assign apb_pslverror = ((factory_doWrite && factory_writeErrorFlag)
                     || (factory_doRead  && factory_readErrorFlag));   // 恒 0
```

即厂家对 APB slave 0 的**整个 64 KB 窗口**都是：

```text
PREADY = 1（永远）
PRDATA = 0（永远）
PSLVERR = 0（永远，无错误报告）
```

只有 `apb_paddr == 0` 会写 `_zz_sig`，其余地址全部是 no-op。

### Q.2 A 当前实现的风险

```text
厂家 apb3_top  ：PREADY = 1

A frame_status_apb.v ：PREADY = sel
```

**不能直接整模块替换。** 否则访问未映射地址时：

```text
PREADY 永远不拉高
→ APB transaction 永久挂起
→ CPU 卡死（不是报错，是挂住）
```

这种故障在板上表现为"程序莫名其妙停在某个外设访问上"，极难归因。

### Q.3 要求

最终 wrapper **必须保证未命中 UDP 子窗口时也能够正常结束 transaction**。

### Q.4 未映射区域的行为 —— `待B确认`

```text
方案 A（厂家原行为）：PRDATA = 0 / PSLVERR = 0
方案 B（严格）      ：PSLVERR = 1
```

**等待 B 决定**（见「仍需 B 最终确认」第 4 项）。

---

# A 已确认结论（原 13 项中已关闭部分）

| # | 项 | 结论 |
|---:|---|---|
| 1 | 完整 offset 表 | A 撤回 `ID`/`SWAP_SEQ`/`SWAP_FRAME`，接受 C 的寄存器顺序；字段表见 §A |
| 2 | `SWAP_SEQ` / `SWAP_FRAME` / `ID` | **已撤回**，不进协议 |
| 3 | `SLOT` | 保留 3-bit 字段，联合工程合法值仅 0/1，仅供诊断 |
| 4 | `FRAME_ID` | 硬件内部 16-bit，寄存器读出时 `[31:16]` 恒 0 |
| 5 | `FRAME_STATUS` bit 表 | 最终紧凑表，见 §E |
| 6 | `LEN_ERR` / `NO_DATA_ERR` | 单列为 bit4 / bit5；`NO_DATA_ERR = (frame_expect == 0)`，A 已确认 |
| 7 | `ARP_MISS` | 不属于 FRAME_STATUS，作为诊断信息处理 |
| 8 | `CAL_DONE` | 不属于 FRAME_STATUS，放入 LIVE_STATUS；A 已实现 |
| 9 | ACK / publish 同周期优先级 | publish 优先；A 已接受并将修改 RTL 和 testbench |
| 10 | APB 时钟 | A 建议 APB slave + frame status FSM 统一在 100 MHz；**最终由 B 确认** |
| 11 | `BASE_ADDR` 锁存 | 必须是硬件实际锁存并使用的地址，是 snapshot 中的权威地址 |

# 仍需 A/C 最后确认（1 项）

```text
START 无授权 → AUTH_ERR 后，
硬件是否发布一份坏 snapshot 并推进 SEQ？
```

若不发布，C 无法通过 Frame Status 接口观察到该错误（见 AUTH.4）。

---

# 仍需 B 最终确认（4 项）

```text
1. 0xF8100100 – 0xF81001FF
   是否正式分配给 UDP Frame Status

2. APB slave 0 合并后最终使用哪个时钟
   （A 建议的目标是 user_clk / sys_clk 100 MHz）

3. UDP_FRAME_STATUS_VERSION
   是否采用 0x00010000（V1.0）

4. Reserved / 未映射 APB 地址：
   PSLVERR = 1，
   还是保持厂家行为（PREADY=1、PRDATA=0、不报错）
```

> 正式 UDP block 在 `04_project/` 下的**目录名称**仍可作为工程组织事项保留，
> 但**不应再作为协议语义冻结的核心阻塞项**。

---

# 跨分支联调提醒（非协议阻塞项）

> B 提出的 **merge / integration 风险**，**不属于 UDP 协议冻结内容**，记录在此以免丢失。

B 的 `feature/rgb565-720p-rtl` 工作区可能已经把 framebuffer 头文件改成：

```text
1280x720
2 B/pixel
```

而某个 C `test_contract.c` 版本仍可能存在旧断言：

```text
FB_BYTES_PER_PIXEL == 4
FB_WIDTH == 1920
```

**注意措辞：不能说成"C 当前工程已经坏了"。**
C 当前最新提交已执行过 `make contract-test` 与 `./scripts/regress.sh quick` 并 **PASS**。
这是**合并时才会暴露**的风险。

> 合并 B 的 feature 分支时，必须**重新检查**双方 `test_contract.c`
> 与权威 framebuffer 头文件是否一致。

---

# 冻结后 C 侧将新增/修改的文件（预告，未实现）

> **字段表与 block base 都冻结之前，一个都不会创建。**

| 文件 | 性质 |
|---|---|
| `<UDP block>/sw/udp_frame_status_regs.h` | 新增，offset 唯一定义点 |
| `driver/udp_frame_status_platform.h` | 新增，tick 源 / host 模型接缝 |
| `driver/udp_frame_status.c` | 新增，MMIO 唯一落点 |
| `driver/udp_frame_status.h` | 新增，对外 snapshot API |
| `driver/protocol_unfrozen.h/.c` | 修改，`udp_completion` 语义升级 |
| `render/frame_swap.c/.h` | 修改，新增 `frame_swap_udp_poll()` + `acquire_back()` 时 resync |
| `tests/test_udp_frame_status.c` | 新增 |
| `Makefile` | 修改，hw-isolation 改表驱动 + `check-no-addresses` 加 UDP base |
