# UDP Frame Status V2 —— A 侧答复

- 日期：2026-09-19
- 提出：A（系统平台与显示集成）
- 收件：B、C
- 答复对象：`udp_frame_status_v2_draft.md`（C，2026-09-19，587 行）
  + C 对 P1/P2/P3 的回应 + B 的 11 个问题

---

## 0. 摘要

C 的草案质量很高，**A 大部分接受**。少数几处 A 有不同意见、或发现了需要补的缺口：

| 节 | A 的立场 |
|---|---|
| **A** 地址表 | **全盘接受 C 的顺序**。A 现有实现顺序不同，按 C 改。**但草案漏了 `AUTH_BASE`/`AUTH_CTRL`**（C 自己在 P3 提的） |
| **E** bit 表 | **选 E.3 紧凑重排**，不选"保留原编号"。理由见 §E |
| **G** 优先级 | A **确认 G.1/G.3**，但 **A 现有实现与 G.1 有一处不同，A 改成 C 的版本**（C 的更安全） |
| **K** CDC | **A 独立实测结论与 C 一致**：帧状态信号全在 `sys_clk`。A 建议 APB 也放 `sys_clk` → 零 CDC |
| **L** VERSION | 需要。A 提议 `0x00010000`，请 B/C 分配 |

---

## A. 寄存器地址表

**A 全盘接受 C 的顺序。** A 现有 `frame_status_apb.v` 的顺序不同（把 `FRAME_ID` 放 `+0x00`、
`SEQ` 放 `+0x1C`），**A 按 C 的表改** —— C 把 `SEQ` 放 `+0x00` 作 commit 标志更合理，
软件 seqlock 读法的第一读就是 `SEQ`，放首位也便于 MMIO 访问。

### A.1 草案遗漏：`AUTH_BASE` / `AUTH_CTRL`

**C 在 P3 回应里提议了 `AUTH_BASE + 一次性 ARM`，但草案的 A 节没有这两项。**
两者不一致，请 C 确认以哪个为准 —— A 认为 **P3 的方案是对的且必需的**（理由见 P3 那节）。

A 建议在保留区段补两行：

| 偏移 | 名称 | R/W | 复位 | 分类 | 说明 |
|---:|---|---|---:|---|---|
| `+0x2C` | `AUTH_BASE` | RW | `0` | 控制 | C 写入本次授权写入的后台 framebuffer 物理地址 |
| `+0x30` | `AUTH_CTRL` | WO | — | 控制 | 写 bit0=1 → `ARM`；硬件在下一帧 START 消费并自清。读回 0 |

并新增一个错误位 `AUTH_ERR` 进 `FRAME_STATUS`（见 §E）。

### A.1（草案原节）的四点不匹配 —— A 全部确认

| # | 草案的发现 | A 的确认 |
|---|---|---|
| 1 | `BASE_ADDR` 在 RTL 里不存在，必须新增锁存寄存器 | ✅ **确认**。这正是 P3 的核心：软硬件各自独立得到地址，才能互相对账。A 的实现里 `frame_base` 是硬件输入、被锁存，**不是软件推导** |
| 2 | `SLOT` 语义冲突（3-bit 轮转 vs 2 个 Framebuffer） | ✅ **确认** |
| 3 | `FRAME_ID` 16-bit，高 16 位需明确恒 0 | ✅ **确认恒 0** |
| 4 | `ERR_STICKY`/`ACK_SEQ`/`LIVE_STATUS`/`VERSION` 全是新增逻辑 | ✅ **确认**。A 的实现里这些确实是新写的，不是接线 |

**"`SLOT` 与 `BASE_ADDR` 冗余但不删，`BASE_ADDR` 权威"** —— ✅ **A 同意**。
A 会加注释说明 `SLOT` 仅供人读诊断，软件不得用它算地址。

---

## B / C / D.1

**B（R/W）、C（reset 值）**：全部接受。`SEQ` 复位 0、第一帧后为 1 ✅

**D.1「`SEQ` 最后发布」** —— A 的实现方式需要 C 确认是否满足意图：

A 的实现里**所有 snapshot 字段（含 `SEQ`）在同一个时钟沿并行更新**（同一个
always 块的 nonblocking 赋值）。所以**不存在"先改 `SEQ` 再逐个改字段"的中间窗口** ——
从任何一次读的角度看，要么全是旧帧、要么全是新帧，没有混合态。

D.1 禁止的是"先改 `SEQ` 再逐字段更新"。A 的实现比它更强的（原子）。**请 C 确认接受。**

如果 C 要求严格按"字段先、`SEQ` 后"分两拍，A 也可以改 —— 但那会引入一个
"字段已新、`SEQ` 还旧"的窗口，反而更弱。**A 建议保持同沿更新。**

---

## E. `FRAME_STATUS` bit 表 —— A 选 **E.3 紧凑重排**

### 理由

草案给"保留原编号"的理由是「便于与 ACK 包状态字节对拍」。**但这个理由在
`cal_done`/`arp_miss` 移出之后就不成立了：**

- ACK 包状态字节（`top.v:721`）里 bit1 = `cal_done`、bit2 = `arp_miss`
- 而 `FRAME_STATUS` 把这两位**移走了**，留下空洞
- 所以两个向量**无论选哪个方案都已经不同**，"对拍"的收益已经不存在

另外两点：

- **空洞会让软件误判** —— bit1/bit2 空着，读回 0，软件会以为"这两位将来会有意义"，
  或者误以为"这一帧的 cal_done=0、arp_miss=0"。语义不成立
- **拿 ACK 包做兼容性论据不成立** —— 那条通路目前**完全不可用**：板子在整帧完成后
  根本不发回执（实测见 `udp_frame_status_interface_review_v0.1.md` 附二）。
  为一个坏掉、且迁移时注定要重写的通路保留永久空洞，不值得

### A 建议的最终表

```text
bit0 FRAME_OK | bit1 SEQ_ERR  | bit2 FIFO_OVF
bit3 BRESP_ERR | bit4 LEN_ERR | bit5 NO_DATA_ERR | bit6 AUTH_ERR
bit7–31 保留，读 0
```

**A 同时去掉自己实现里的 `DONE` 位（bit0）** —— 它恒为 1，是冗余的。
`SEQ` 才是 commit 标志，"有没有新快照"由 `SEQ` 判断，不需要 `DONE`。

### E.2 `ARP_MISS` 移出 —— A 完全同意

草案的三条证据 A 全部确认，其中第 2 条 A 可以直接对上 RTL：

```verilog
top.v:644  frame_ok = frame_bytes_ok && !frame_seq_err && !fifo_ovf && !bresp_err
```

**`arp_miss` 确实不在 `frame_ok` 表达式里** ✅ 归 `ERR_STICKY`（诊断）合适。

### `NO_DATA_ERR` 的定义

草案给的判据是 `frame_expect == 0` —— **A 确认接受**。
（A 原以为它指"无数据包到达"，但 `frame_expect == 0` 的定义更简洁且等价 ——
START 声明 0 字节的帧本来就不该被当作有效帧。）

---

## F. `ACK_SEQ` —— 全盘接受

- **命名接受**：A 的实现里叫 `ACK`，会改成 `ACK_SEQ`。草案 F.1 的理由成立 ——
  `top.v` 里已有的 `frame_ack` 是 UDP 网络层回执，两者混名会误导
- **F.2 行为接受**
- **F.3 接受**：`ACK_SEQ` 不改任何 snapshot 字段
- **F.4 接受**："软件已消费过这个 SEQ"，不是"这一帧已经成功显示"。**坏帧也允许 ACK** ✅

---

## G. ACK 与新 `frame_done` 同周期 —— **A 确认，并会改自己的实现**

### G.1 / G.3：A 确认，但 A 现有实现与 G.1 有一处不同

**A 的实现：**

```verilog
wire        ack_hit  = ack_wr && (pwdata == st_seq);
wire [31:0] err_base = ack_hit ? 32'd0 : err_sticky;   // ← 差别在这里
if (snap_pulse) err_sticky <= err_base | {新帧的错误位};
else if (ack_hit) err_sticky <= 32'd0;
```

**草案 G.1：**

```verilog
if (publish_new_snapshot) err_sticky <= err_sticky | new_frame_err;  // ← 用旧值
else if (ack_wr_valid && ack_wdata == seq) err_sticky <= 1'b0;
```

**差别在 G.3 场景**（`SEQ=N`，写 `ACK=N`，同周期发布 `N+1`，且 `N+1` 是**好帧**）：

| | 结果 |
|---|---|
| A 的实现 | `err_base = 0`（ACK 命中）→ `ERR_STICKY = 0`，**旧错误被清掉** |
| 草案 G.1/G.3 | ACK 被丢弃 → `ERR_STICKY` **保持原值** |

### A 采纳草案的规则

**A 改成 G.1 的写法。** 理由：

1. **C 的更安全** —— 粘滞寄存器的意义就是不丢错误。同拍发布时 ACK 已过期，
   丢弃它最多让软件多看到一次旧错误；而清掉它则可能**永久丢失**一条软件还没读到的错误
2. **C 的更简单** —— 只有一条规则（"同拍发布 → 丢弃 ACK"），不需要 `err_base` 这种派生项
3. **这是 C 的接口**，语义由 C 定，A 没有理由坚持一个更弱的选择

**副作用**：A 的 `tb_frame_status_apb.sv` 用例 9 目前验证的是 A 的旧行为。
改成 G.1 后，**"新帧错误不被抹掉"这条断言仍然成立**（publish 优先），
但需要**新增一个 G.3 的变体用例**（新帧是好帧时旧错误应保持）。
A 会一并改 TB。

---

## H / I / J

**H `ERR_STICKY` 语义**：接受。`ERR_STICKY ≠ 当前 FRAME_STATUS`、用途是诊断 —— A 的实现一致。

**I `SEQ` 发布与回绕**：接受。

**J.2 —— 这是 C 侧发现的真实缺陷，A 不涉及，但有一处要确认：**

草案 J.3 的修法是 `frame_swap` 在 `acquire_back(UDP)` 时调用
`udp_frame_status_resync()`，把软件基线拉到当前 `SEQ`。

**请 C 确认 `resync()` 是纯软件实现** —— 只需读一次 `SEQ` 存为基线即可，
**不需要硬件提供额外的 resync 寄存器或命令**。若需要硬件配合，A 要提前知道。

---

## K. CDC —— A 独立实测结论与草案一致

**A 确认草案 K.1 的时钟域表，逐条对上：**

| 草案的发现 | A 的确认 |
|---|---|
| `frame_done`/`frame_wslot`/`frame_rx`/`frame_expect`/`frame_id_cur`/`frame_seq_err`/`bresp_err`/`rx_bytes` 全在 `sys_clk` | ✅ 整个帧状态机在 `always @(posedge sys_clk)`（`top.v:359`） |
| `cal_done` 在 `sys_clk` | ✅ |
| `arp_miss_raw`/`img_fifo_ovf` 在 rxc，已有 2FF 同步 | ✅ `top.v:210-222` |

### 回答 B 的 Q8：APB slave 落在哪个时钟域

**A 的建议：APB slave 与帧状态机同处 `sys_clk`，实现零 CDC。**

理由：迁移文档要求"确认 100 MHz SoC 时钟"，A1-3 本来就要把 `sys_clk` 统一到
平台的 `user_clk`（100 MHz）。统一之后 APB 与帧逻辑自然同域，CDC 整个消失。

**A 的实现在这一点上是超集**：它按两域设计（toggle 握手 + 整组锁存）。
若确认同域，握手电路**冗余但无害**（约 20 个触发器）。A 建议**保留握手结构**，
理由：它让"时钟方案再变"不会静默出错，而成本可以忽略。

**但这需要 B 明确回答**：合并后 APB slave 0 挂在哪个时钟上？

### K.3 的两条

1. **rxc 域信号必须用已同步版本** ✅ A 的实现用的就是 `arp_miss_sync[1]`，
   而 `ovf_sync[1]` 在 `top.v` 侧就已经同步好了
2. **`SEQ` 必须是最后一个被更新的字段** —— 见 §D.1 的说明：
   A 的实现是同沿并行更新（比"最后更新"更强），**请 C 确认接受**

---

## L. `LIVE_STATUS` 与 `VERSION`

**`CAL_DONE` 进 `LIVE_STATUS`** ✅ 接受，A 已实现。

**`VERSION` 需要** ✅ 理由：迁移文档要求"软件必须读取 VERSION 并拒绝不匹配的位流"，
B 的 BitBlt（`+0x28`）和 Display（`+0x28`）都已有，A 这块没有会让探测阶段失去一致性。

**数值**：A 提议 **`0x00010000`（V1.0）**，按团队约定"高 16 主版本 / 低 16 次版本"。
**A 不擅自定值，请 B/C 分配。**

---

## M / N

A 会完整读一遍 C 的 API 草案和测试清单，如有异议另提。本文件暂无。

---

## 需要对方回应的

| # | 事项 | 谁 |
|---|---|---|
| 1 | **确认 `0xF8100100–0xF81001FF` 的地址所有权**（APB/SoC 顶层归 B） | **B** |
| 2 | 草案 A 节**补 `AUTH_BASE` / `AUTH_CTRL`**（C 自己在 P3 提的，草案里没有） | C |
| 3 | 确认 **E.3 紧凑重排**（含新增 `AUTH_ERR` bit6） | C |
| 4 | 确认 **D.1 的"同沿并行更新"**满足意图（A 认为比"SEQ 最后"更强） | C |
| 5 | 确认 **`resync()` 是纯软件**，不需要硬件配合 | C |
| 6 | **APB slave 的时钟域**（决定零 CDC 是否成立） | **B** |
| 7 | **分配 `VERSION` 数值**（A 提议 `0x00010000`） | B/C |
| 8 | 未映射地址报 `PSLVERR` 还是返回 0（A 见 §Q10） | B |
| 9 | 确认 **START 无授权时"丢帧 + `AUTH_ERR`"**的处理 | C |

---

## 附：对 B 的 11 个问题的直接回答速查

| B 的问 | A 的答 | 详见 |
|---|---|---|
| Q1 `BASE_ADDR` 是否硬件锁存？ | **是，必须**，不能软件推导 | §A.1 |
| Q2 `SLOT` 定义？ | 保留 3-bit，恒 0/1，**`BASE_ADDR` 权威** | §A.1 |
| Q3 `FRAME_ID` 高 16 位？ | **恒 0** | §A.1 |
| Q4 bit 表保留原编号还是紧凑？ | **紧凑（E.3）** | §E |
| Q5 `LEN_ERR`/`NO_DATA_ERR` 单列？ | **是**，且新增 `AUTH_ERR` | §E |
| Q6 `ARP_MISS` 移出？ | **同意**，RTL 证据确认 | §E.2 |
| Q7 `CAL_DONE` 移出？ | **同意**；但建议 **UDP 回执包不动**（坏通路，动它没收益） | 下方注 |
| Q8 APB 时钟域？ | **建议与帧逻辑同处 `sys_clk`**，需 B 确认 | §K |
| Q9 优先级是否如 G.1？ | **是**，且 A 会把实现改成严格 G.1 | §G |
| Q10 `0xF8100000` 哑模块替换？ | 整份替换 + 薄包装；**`PREADY` 必须恒高** | 下方注 |
| Q11 `VERSION` 需要？数值？ | **需要**，提议 `0x00010000`，请 B/C 分配 | §L |

> **Q7 补充**：`CAL_DONE` 从 CPU 可见的 `FRAME_STATUS` 移出 ✅。
> 但 `top.v:721` 的 **UDP 回执包状态字节**里也有 `cal_done`（bit1）——
> 那份面向 PC、且通路完全不可用。**A 建议那份不动**，避免扩大改动面。
> 请 B/C 确认。
>
> **Q10 补充**：厂家 `apb3_top`（`jzy/co_debug_2026/par/ddr_demo_ti60_2026/src/Interrupt.v:6`）
> 是 `assign apb_pready = 1'b1` —— **无条件就绪**。
> ⚠️ **A 当前的 `frame_status_apb.v` 是 `pready = sel`（只在自己地址段内拉高），
> 直接替换会让未映射地址的 APB 访问永久挂起。** 必须由包装模块补上"未选中也拉高"。
> 这是 A 要改的第一处。
>
> `PSLVERR` 是行为变更（厂家原来对任何地址都返回 0 且不报错）。
> A 建议保留区/未映射区报 `pslverr=1`（更有诊断价值），**请 B 确认**。

---

## A 侧待办（不阻塞上述确认）

1. 按 C 的表重排寄存器顺序（`SEQ` 移到 `+0x00`）
2. 撤回 `ID` / `SWAP_SEQ` / `SWAP_FRAME`；`STATUS` 改名 `FRAME_STATUS`；`ACK` 改名 `ACK_SEQ`
3. 去掉 `DONE` 位；bit 表改紧凑；新增 `LEN_ERR` / `NO_DATA_ERR` / `AUTH_ERR`
4. 新增 `AUTH_BASE` / `AUTH_CTRL` 与授权锁存逻辑
5. **把 `ERR_STICKY` 的优先级实现改成严格 G.1**
6. 补 64 KB 窗口包装模块（含 `PREADY` 恒高的修正）
7. 扩展 `tb_frame_status_apb.sv`：新增 G.3 变体用例、授权通路用例

**确认后即可冻结 UDP Frame Status V2，C 不必等 A 的最终位流。**
