# UDP Frame Status V2 协议冻结草案

- 日期：2026-09-19
- 提出：C（RISC-V 软件）
- 状态：**协议冻结草案（B 侧第一轮评审已完成，A/C 字段表及部分板级资源仍待确认）**
- 待确认项一律标注 `待A确认` / `待B确认` / `待A/B/C确认`，C 侧在确认前不会写进代码。

依据：

- `rwj/udp_image_demo/fpga/rtl/top.v` 实测信号（A 组已提交的实现）
- `07_docs/interfaces/rgb565_720p_migration.md`（团队统一目标）
- `07_docs/interfaces/bitblt_interface_v0.2.md`（BitBlt/显示已冻结基线）
- UDP Frame Status 软件侧静态检查（第二阶段结论）
- B 侧第一轮评审回复

> 本文件已放在 `07_docs/interfaces/`，与其它接口文档同级。
> 但文件名里的 `_draft` **必须保留到字段表与 block base 全部冻结为止**——
> 它是草案，不是基线。冻结后去掉 `_draft` 并补齐版本记录。

---

## 0. 已知前提

```text
APB Slave 0  base = 0xF8100000        （soc.h: IO_APB_SLAVE_0_INPUT，已在 BSP 中）
```

窗口划分：

| 范围                        | 用途                                | 状态                                |
| --------------------------- | ----------------------------------- | ----------------------------------- |
| `0xF8100000 - 0xF81000FF` | Reserved                            | 候选                                |
| `0xF8100100 - 0xF81001FF` | RX Frame Status（本文件描述的范围） | **候选，待 B 最终确认（P1）** |

> ⚠️ **`0xF8100100 - 0xF81001FF` 目前是候选，不是已冻结的团队地址分配。**
>
> B 给出的冻结顺序仍然是：**先冻结 A/C 字段表 → 再定新块基址和 VERSION**。
> A 侧已经实现 `frame_status_apb.v`，**不等于**团队地址分配已经正式冻结。
> P1 仍需 B 明确回复：UDP Frame Status 是否正式占用这一段。

MVP 采用：

```text
Polling，不使用 IRQ
通知机制 = Snapshot + 32-bit SEQ + matching ACK
```

---

## A. 候选寄存器地址表（未冻结）

> **本表是 C 侧冻结草案，不是当前唯一权威寄存器表。**
>
> A 最新 `frame_status_apb.v` 已出现 `SWAP_SEQ` / `SWAP_FRAME` / `ID`
> 等本草案没有的字段。
>
> 必须先取得 A 当前**完整的 offset / R/W / reset / semantic 表**，
> 与本表逐项对齐之后，才能形成最终字段表。
>
> 另注：截至本文件更新时，本仓库内**尚无** `frame_status_apb.v`，
> 全仓库也搜不到 `SWAP_SEQ` / `SWAP_FRAME` / `AUTH_BASE`——
> A 的实现目前只在其自己的工作副本中，需 A 提交后才能逐项对齐。

|            偏移 | 名称             | R/W | 复位值 | 分类                  | 更新时机                  | 状态 |
| --------------: | ---------------- | --- | -----: | --------------------- | ------------------------- | ---- |
|       `+0x00` | `SEQ`          | RO  |  `0` | **commit 标志** | 快照锁存完成后 +1         | 候选 |
|       `+0x04` | `FRAME_STATUS` | RO  |  `0` | **snapshot**    | 与 SEQ 同拍锁存           | 候选 |
|       `+0x08` | `FRAME_ID`     | RO  |  `0` | **snapshot**    | 同上                      | 候选 |
|       `+0x0C` | `SLOT`         | RO  |  `0` | **snapshot**    | 同上                      | 候选 |
|       `+0x10` | `BASE_ADDR`    | RO  |  `0` | **snapshot**    | 同上                      | 候选 |
|       `+0x14` | `RX_BYTES`     | RO  |  `0` | **snapshot**    | 同上                      | 候选 |
|       `+0x18` | `EXPECT_BYTES` | RO  |  `0` | **snapshot**    | 同上                      | 候选 |
|       `+0x1C` | `ACK_SEQ`      | WO  |  `0` | 控制                  | 软件写；硬件不回读        | 候选 |
|       `+0x20` | `LIVE_STATUS`  | RO  |     — | **live**        | 实时，不属于任何 SEQ      | 候选 |
|       `+0x24` | `ERR_STICKY`   | RO  |  `0` | **live**        | 跨帧粘滞，matching ACK 清 | 候选 |
|       `+0x28` | `VERSION`      | RO  |   待定 | **static**      | 常量                      | 候选 |
| `+0x2C–0xFC` | Reserved         | RO  |  `0` | —                    | 读回 0，写入忽略          | 候选 |

**以上字段全部保留为候选，未删除任何一项，但都不得标记为 final。**

### A.1 布局评估

**对齐**：全部 32-bit 对齐，无问题。头部占用 `0x00–0x2B`，窗口还剩 212 B。

**地址冲突**：无。`0xF8100100` 落在 APB slave 0 的 64 KB 内；UART0 (`0xF8010000`)、
GPIO0 (`0xF8015000`) 在别的段。

> ⚠️ `0xF8100000` 当前挂的是厂商 `apb3_top` **哑模块**（读恒返 0，写只改 1 bit
> 到悬空内部线，见 `rwj/udp_image_demo/riscv/README.md`）。A 必须在**不破坏厂商
> 地址译码**的前提下替换或扩展它。

**与已提交 RTL 信号的不匹配（需要 A 决策）：**

| # | 问题                                                                        | 现状                                                                                     | 影响                                                                                                                                       |
| - | --------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| 1 | **`BASE_ADDR` 在已提交 RTL 里不存在**                               | 只有`frame_wslot`(3-bit) 和 `slot_base()` 函数                                       | 必须**新增锁存寄存器**。不能由软件从 SLOT 推导——迁移文档要求"硬件报回来的实际写入基址必须等于软件授权的那块"，推导值证明不了这件事 |
| 2 | **`SLOT` 语义冲突**                                                 | `frame_wslot` 是 3-bit（0–7 槽轮转），A 的 demo 是 4 槽                               | 联合工程只有**2 个 Framebuffer**（A/B 双缓冲），3-bit 槽号在新架构下无意义                                                           |
| 3 | **`FRAME_ID` 位宽**                                                 | `frame_id_cur` 是 **16-bit**                                                     | 寄存器是 32-bit，需明确高 16 位恒 0                                                                                                        |
| 4 | **`ERR_STICKY`/`ACK_SEQ`/`LIVE_STATUS`/`VERSION` 无现有信号** | 现有`bresp_err` 是**每帧清零**的；`arp_miss_sync`/`ovf_sync` 只是 2FF 同步位 | 全部是新增逻辑，不是接线                                                                                                                   |

**冗余但不删**：`SLOT` 与 `BASE_ADDR` 信息冗余（后者是前者的函数）。
两个都保留，但明确 **`BASE_ADDR` 是权威，`SLOT` 仅供诊断**，软件不得用 `SLOT` 算地址。

**缺失**：无。`SEQ == 0` 天然表示"reset 后尚无任何快照"，不需要额外的 valid 位。

---

## AUTH_BASE 授权通路（待 A/B/C 冻结）

> 本节是 A 提出的一个**当前草案没有覆盖的真实缺口**，单独成节。

### 缺口描述

```text
C 已经能决定后台 framebuffer          ✓（frame_swap_acquire_back）
A 完成后也能报告 BASE_ADDR            ✓（候选字段）
但 C → A 的「本帧只允许写哪个 framebuffer」授权通路【缺失】  ✗
```

没有这条通路，硬件就无从知道 C 把哪一块后台授权给了 UDP 生产者，
「生产者不得写正在扫描的前台」这条约束在硬件侧无法落地。

### C 建议方案（待冻结，不是最终决定）

```text
C  acquire_back(UDP)
   → 获得 fs->back
   → APB 写 AUTH_BASE
   → APB 写一次性 ARM / AUTH_VALID
A  在下一帧 START 时锁存 AUTH_BASE
   → 清除一次性 ARM
   → 本帧只能写该锁存地址
   → frame_done 时 snapshot.BASE_ADDR 回报硬件【实际使用】的地址
C  检查 snapshot.BASE_ADDR == fs->back
```

### 明确立场

- C **倾向** APB `AUTH_BASE` + 一次性 `ARM` / `AUTH_VALID` 的方案；
- C **不建议**让 UDP 网络包直接携带并决定 DDR 写地址
  ——迁移文档明确要求"网络包自带 slot 或旧 `active_slot^1` 不能覆盖软件授权"；
- `BASE_ADDR` **必须是硬件实际锁存并使用的地址**，不是软件写入期望值的回显；
- 软件仍保留 `snapshot.BASE_ADDR == fs->back` 的校验（双保险：硬件约束 + 软件校验）。

### 待确认

```text
START 到来时若 AUTH_VALID = 0：
  A 应丢帧并产生 AUTH_ERR，还是采用其他行为？
```

**这一条暂时不擅自冻结**，`待A/B/C确认`。

---

## B. R/W 属性

见 A 表。补充三条（同样属于候选）：

1. 全部寄存器 **32-bit 访问**；`SLOT` / `FRAME_ID` 高位置 0。
2. `ACK_SEQ` 是 **WO**，读回 `0`——不提供回读，避免软件误以为它是状态。
3. Reserved 区**读回 0、写入忽略**，不要留未译码空洞。

---

## C. reset 值

全部 `0`，`VERSION` 除外。

`SEQ` reset 后为 `0`，**第一帧完成后发布 `SEQ = 1`**。
即 SEQ 表示"已发布快照的计数"，`0` = 一个都没有。

---

## D. snapshot / live 分类

| 分类                                               | 寄存器                                                                             | 语义                                         |
| -------------------------------------------------- | ---------------------------------------------------------------------------------- | -------------------------------------------- |
| **snapshot**（与 SEQ 同拍、该 SEQ 内不可变） | `FRAME_STATUS` `FRAME_ID` `SLOT` `BASE_ADDR` `RX_BYTES` `EXPECT_BYTES` | 属于**同一个 `frame_done`** 的一整帧 |
| **commit 标志**                              | `SEQ`                                                                            | 快照的提交点；**最后写**               |
| **live**                                     | `LIVE_STATUS` `ERR_STICKY`                                                     | 可随时变化，**不属于任何 SEQ**         |
| **static**                                   | `VERSION`                                                                        | 常量                                         |
| **控制**                                     | `ACK_SEQ`                                                                        | 写口                                         |
| **控制**                                     | `AUTH_BASE` + `ARM`/`AUTH_VALID`                                             | 见 AUTH_BASE 节，字段尚未定                  |

> ⚠️ **`ERR_STICKY` 不是 snapshot。**
> 它可能在软件读完 `SEQ` 之后、读 `ERR_STICKY` 之前被新的 publish 改变。
> 所以软件**不得**用两次读的组合去推断某一帧的状态——这正是 H 节规则的来源。

### D.1 snapshot 发布顺序（硬性）

```text
最终 DDR 写事务完成
    ↓
所有相关 BRESP 返回
    ↓
锁存全部 snapshot 字段
    ↓
最后发布新的 SEQ
```

**SEQ 是整个 snapshot 的 commit 标志。禁止先改 SEQ 再逐个更新字段。**

---

## E. FRAME_STATUS bit 待确认表

**没有发明 bit。** 依据是 A 侧**已提交** RTL 里已经存在的一版状态字节——`top.v:721`
组装 UDP 回执包时用了它：

```verilog
{2'd0, bresp_err, fifo_ovf, frame_seq_err, arp_miss, cal_done, frame_ok}
// RTL 注释原文：[87:80] 状态：bit0 帧完整  bit1 DDR校准完 bit2 ARP未命中
//                          bit3 断号/串帧 bit4 FIFO溢出
//                          bit5 DDR写响应错(BRESP)  bit6-7 保留
```

现有 `frame_ok` 判据（`top.v:643-644`）：

```verilog
frame_bytes_ok = (frame_expect != 0) && (frame_rx == frame_expect);
frame_ok       = frame_bytes_ok && !frame_seq_err && !fifo_ovf && !bresp_err;
```

**候选表**（保留原 bit 编号，便于与 ACK 包状态字节对拍）：

|   bit | 名称                  | 来源                         | 状态                                               |
| ----: | --------------------- | ---------------------------- | -------------------------------------------------- |
|     0 | `FRAME_OK`          | `frame_ok`                 | 判据 =`!(bit3\|bit4\|bit5\|bit6\|bit7)`，`待A确认` |
|     1 | *(原 `cal_done`)* | —                           | **移到 LIVE_STATUS**，位置保留               |
|     2 | *(原 `arp_miss`)* | —                           | **移到 ERR_STICKY**，位置保留，理由见 E.2    |
|     3 | `SEQ_ERR`           | `frame_seq_err`            | 已有                                               |
|     4 | `FIFO_OVF`          | `fifo_ovf`                 | 已有                                               |
|     5 | `BRESP_ERR`         | `bresp_err`                | 已有                                               |
|     6 | `LEN_ERR`           | `frame_rx != frame_expect` | **新增，`待A确认`是否单列**                |
|     7 | `NO_DATA_ERR`       | `frame_expect == 0`        | **新增，`待A确认`是否单列**                |
| 8–31 | 保留                  |                              | 读 0                                               |

> A 的 `frame_status_apb.v` 可能已有不同定义，**以 A 提交的完整 offset 表为准再对齐**。

### E.1 为什么建议单列 bit6 / bit7

现在 `frame_ok` 把**四个**独立原因（序号 / FIFO / BRESP / 长度）压成一个布尔。
出了坏帧时无法归因，只能靠猜。单列之后软件日志能直接指出是哪一类。

### E.2 为什么 `ARP_MISS` 必须移出 FRAME_STATUS（有 RTL 证据）

1. `arp_miss` 是 rxc 域 **2FF 同步**过来的（`top.v:210-221`），它描述的是 ARP 解析
   这一**全局**条件，不是某一帧的字节内容；
2. **它根本不参与 `frame_ok`**（`top.v:644` 的表达式里没有它）——语义上它已经不属于
   "当前帧错误"了；
3. 一个"可变、且与帧无关"的位混进"不可变的帧快照"，会让快照的语义不成立。

→ 归入 **`ERR_STICKY`（诊断）** 或 `LIVE_STATUS`，`待A确认`。

### E.3 备选方案

若不保留原 bit 编号，可紧凑重排：

```text
bit0 FRAME_OK | bit1 SEQ_ERR | bit2 FIFO_OVF
bit3 BRESP_ERR | bit4 LEN_ERR | bit5 NO_DATA_ERR
```

两个方案都可以，**请 A 选一个**。

---

## F. ACK_SEQ 精确语义

### F.1 命名

**必须叫 `ACK_SEQ`。**

已提交 RTL 里存在的 `frame_ack` 是 **UDP 网络层回执包**（`udp_ack_tx` 发出的
24 字节载荷，见 `top.v:700-727`），与本寄存器毫无关系。命名必须区分开。

### F.2 行为

```text
软件： WR(ACK_SEQ, consumed_seq)      // = 刚成功读取的那个 SEQ

硬件： if (ACK_SEQ_wdata == SEQ && 本拍无新快照发布)
           ERR_STICKY <= 0;
       else
           ignore;
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

## G. ACK 与新 frame_done 同周期

**必须冻结。**

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

给定场景：

```text
current SEQ = N，CPU 写 ACK_SEQ = N
同周期新帧 N+1 发布且带错误
```

必须得到：

```text
SEQ        = N+1
ERR_STICKY = 1        ✓（publish 优先，旧 ACK 被丢弃）
```

### G.3 推论（请 A 一并确认）

若 `N+1` 是**好帧**，同一场景下 `ACK(N)` **同样应被丢弃**（SEQ 已前进，ACK 已过期），
`ERR_STICKY` 保持原值不变。

---

## H. ERR_STICKY 语义

```text
ERR_STICKY  ≠  当前 FRAME_STATUS
```

|          | `FRAME_STATUS`               | `ERR_STICKY`                                 |
| -------- | ------------------------------ | ---------------------------------------------- |
| 描述对象 | **当前 SEQ 那一帧**      | **自上次 matching ACK 以来**出现过的错误 |
| 可变性   | 该 SEQ 内不可变                | 任何 publish 都可能置位；ACK 可清              |
| 用途     | **决定这一帧能不能渲染** | 诊断 / 告警                                    |

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

> 对现有 `frame_swap` 的影响：`frame_swap_udp_frame_ready(fs, base, frame_ok)`
> 目前只收一个布尔 `frame_ok`。第三阶段必须保证这个布尔**由 snapshot 算出**，
> 而不是由 `ERR_STICKY` 算出。本阶段不实现，仅登记。

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
所以"跳过中间 SEQ"对状态机透明。

### J.2 必须补的洞（真实缺陷，不是理论问题）

```text
T0: 软件 acquire_back(UDP) → 授权后台 = B
T1: 软件 poll → 读到的是【上一帧】的快照，BASE_ADDR = A（旧前台）
    → reported_base(A) != back(B) → 当前实现返回 WRONG_OWNER
    → 并且 release_back()，把刚授权的后台【释放掉了】
```

**授权之后第一次 poll，几乎必然误报一次 WRONG_OWNER 并丢掉后台授权。**

根因：`last_seq` 基线与后台授权**不同步**。

### J.3 修法（第三阶段实现，本阶段只冻结语义）

`frame_swap` 在 `acquire_back(UDP)` 成功的那一刻调用
`udp_frame_status_resync()`，把驱动基线拉到当前 SEQ——此后**只有授权之后发布的
快照**才会被当成新帧。

这正是 `resync()` 存在的理由。

---

## K. CDC 要求

**结论：按已提交 RTL，快照链路大概率不需要 CDC。**

### K.1 实测时钟域分布（`top.v`）

| 信号                                                                                                                       | 域                    | 说明                                                         |
| -------------------------------------------------------------------------------------------------------------------------- | --------------------- | ------------------------------------------------------------ |
| `frame_done` `frame_wslot` `frame_rx` `frame_expect` `frame_id_cur` `frame_seq_err` `bresp_err` `rx_bytes` | **`sys_clk`** | 整个帧状态机在`always @(posedge sys_clk)`（`top.v:359`） |
| `cal_done`                                                                                                               | **`sys_clk`** | 来自 DDR 控制器，被 sys_clk 域 FSM 直接使用（`top.v:373`） |
| `arp_miss_raw` `img_fifo_ovf`                                                                                          | **rxc**         | 已有 2FF 同步（`top.v:210-222`）                           |
| `frame_tgl`                                                                                                              | **像素域**      | 已有 2FF 同步（`top.v:539-546`）                           |

### K.2 目标方案（推荐）

```text
若 APB slave 与帧状态机同处 sys_clk：
    快照锁存寄存器 与 APB 可见寄存器 = 同一域
    → 快照链路【零 CDC】，SEQ 发布就是一次普通寄存器更新

若 A 决定 APB 在别的时钟域：
    源域：锁存完整 snapshot（一个整体）
      ↓ req/toggle 握手（单比特）
    目的域：整体复制 snapshot
      ↓ 最后写 SEQ

    【禁止】每个 snapshot 字段各自打两拍同步
            —— 那会让 SEQ 与字段来自不同帧，快照语义直接破裂
    握手期间【禁止】重复发布（快照被覆盖会导致撕裂）
```

### K.3 无论哪种方案都必须满足

1. rxc 域的 `arp_miss` / `fifo_ovf` **必须用已同步的版本**
   （`arp_miss_sync[1]` / `ovf_sync[1]`），不能用 raw；
2. `SEQ` 必须是**最后一个**被更新的字段。

> `待A确认`：A 的 demo 里 `sys_clk` = 9.26 ns ≈ 108 MHz；合并工程的 SoC 控制域是
> 100 MHz（B 的接口约定）。**APB slave 在合并后落在哪个时钟，需要 A 明确。**

---

## L. LIVE_STATUS 与 VERSION

### L.1 LIVE_STATUS

`CAL_DONE` 必须从帧快照中拆出来。

目标：即使**没有任何 `frame_done`、`SEQ` 仍为 0**，RISC-V 也必须能读到 DDR 校准状态。

```text
建议：LIVE_STATUS.bit0 = CAL_DONE
```

bit number 最终由 A 确认。

考虑一并纳入（可选，`待A确认`）：`DDR3_PLL_LOCK` / `SYS_PLL_LOCK`。

`LIVE_STATUS` **不是 snapshot**，实时读，不随 SEQ 变化。

### L.2 VERSION

#### L.2.1 VERSION 是 IP-local，不是全局编号 —— 已由 B 确认

原先"不得与 `0x00020000`(BitBlt) / `0x00030000`(Display) 撞车"的约束**已删除**。

```text
BitBlt            base + VERSION
Display           base + VERSION
UDP Frame Status  base + VERSION
```

三者的 VERSION **数值允许相同**。真正的身份判断是：

```text
IP base + VERSION        ← 联合判断
```

而不是仅比较一个 VERSION 数字。

#### L.2.2 仍需保留这一项

**建议保留 `VERSION`**（虽然 MVP 可以不要）。理由：

1. 这个 block 的语义**不平凡**——snapshot/ACK/ERR_STICKY 三者有同周期仲裁规则，
   后续必然演进；
2. C 侧已有版本门控先例（`proto_display_version_compatible`）。Display VERSION 检查
   刚证明了它的价值：**烧旧位流 + 新软件**是最难归因的故障，没有版本号时它和
   "驱动有 bug"长得一模一样；
3. 成本是一个 32-bit RO 寄存器。

可以考虑的取值风格（**仅示意，不是冻结值**）：

```text
0x00000001    // V0.1 风格
0x00010000    // V1.0
```

**现在仍不冻结具体数值。** 顺序必须是：

```text
字段表冻结 → block base 冻结 → 再确定 VERSION
```

`VERSION` **不属于 snapshot**（常量，不随 SEQ 变）。

### L.3 非 UDP 协议问题：`DISPLAY_VERSION_V0_2` 的命名不一致（B 提出）

B 提醒：B 现有的

```text
DISPLAY_VERSION_V0_2 = 0x00020000
```

命名与团队"高 16 位主版本、低 16 位次版本"的规则**不一致**——按规则
`0x00020000` 实际是 **V2.0**。

建议后续统一名称为：

```text
DISPLAY_VERSION_V2_0
```

> **这不是 UDP Frame Status 协议冻结的阻塞项。**
> 本轮**不擅自修改 Display 代码**或已冻结的协议常量，仅登记。

---

## M. C 侧最终 API 草案

**不放隐藏全局变量，放 driver context。**

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
void udp_frame_status_resync(udp_frame_status_t *ctx);    /* 显式丢弃快照，重设基线 */

udp_frame_status_result_t
     udp_frame_status_poll(udp_frame_status_t *ctx, udp_frame_snapshot_t *out);

void     udp_frame_status_ack(udp_frame_status_t *ctx, uint32_t consumed_seq);
uint32_t udp_frame_status_live(void);         /* LIVE_STATUS，与 SEQ 无关 */
uint32_t udp_frame_status_err_sticky(void);
uint32_t udp_frame_status_version(void);

/* 纯函数：只吃 snapshot 字段，绝不看 ERR_STICKY —— 可单独单测 */
int udp_frame_snapshot_is_renderable(const udp_frame_snapshot_t *s);
```

### M.1 四个设计判断

| 问题                                      | 结论                                                                                                                                           |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `last_seq` 放哪                         | **驱动 context**（非全局）。`init()` 以当前 SEQ 为基线；`resync()` 显式重设                                                          |
| ACK 谁调用                                | 驱动**暴露** `ack()`，由 **frame_swap 调用**——只有它知道"这一帧消费完了"                                                       |
| `frame_swap_udp_frame_ready()` 怎么处理 | **保留不改**（纯逻辑，现有 5 个 host 测试继续覆盖），另加 `frame_swap_udp_poll()` 走"读快照 → 算 frame_ok → 调它 → ACK"             |
| 怎么避免职责互串                          | 驱动**只**读寄存器 + 写 ACK；frame_swap **只**做状态机；中间靠 snapshot 结构体解耦。frame_swap 的 host 测试**不需要**真 MMIO |

### M.2 resync() 的语义边界

```text
resync() = 丢弃当前已有 snapshot，并把【当前 SEQ】当作新基线
         （调用后第一次 poll 必然返回 NO_NEW）
```

**绝不允许在普通 `poll()` 内部偷偷 resync。**

唯一合法的自动调用点：`frame_swap_acquire_back()` 成功的那一刻（见 J.3）。

### M.3 与 frame_swap 公共错误码的关系（B 已确认原则）

`udp_frame_status_result_t` 是**新驱动内部的 result enum**，
与 **frame_swap 公共错误码**不是一回事。

```text
驱动自己的错误类型：第三阶段可按需要设计
frame_swap 公共 ABI：已冻结，不得因为新驱动而擅自改变
```

**`FRAME_SWAP_ERR_NOT_READY` 暂不新增专用错误码。** 详见文末
「B 第一轮回复结论」。

---

## N. 第三阶段测试清单（设计，未实现）

| # | 场景                                                    | 需要的注入接缝                           |
| -: | ------------------------------------------------------- | ---------------------------------------- |
| 1 | 无新帧（SEQ == last_seq）                               | `udp_test_set_seq()`                   |
| 2 | 正常新帧，全字段正确                                    | 同上 + 字段设置                          |
| 3 | **撕裂保护**：读到一半 SEQ 变                     | `udp_test_set_seq_after_reads(n, seq)` |
| 4 | SEQ 回绕`0xFFFFFFFF→0`                               | 直接设 SEQ                               |
| 5 | 错误帧完整快照可读                                      | `udp_test_set_status()`                |
| 6 | ACK 写入值 == 刚消费的 SEQ                              | 记录式模型（仿`display_last_call()`）  |
| 7 | latest snapshot：跳过中间 SEQ                           | 连续多次 set_seq                         |
| 8 | LIVE_STATUS 不依赖新帧                                  | 独立于 SEQ 的字段                        |
| 9 | **ACK_SEQ != current SEQ 时 ERR_STICKY 不得被清** | 模型必须建模该硬件语义                   |

第 9 条是协议明文要求、但容易被漏掉的项。host 模型不建模它，
"ACK 写错就清错误"这个 bug 会一路溜到板上。

可复用设施：`tests/host_board/stub.c` 的 `mmap(MAP_FIXED_NOREPLACE)` 假内存手法、
`run_scenarios.sh` 的故障注入范式、`display_test_*` 的钩子命名风格。
**现有框架足够，不需要新建。**

---

## O. 唯一权威头文件归属（B 已确认原则）

### O.1 不放 `04_project/bitblt_accel/sw/driver/`

B 已明确：该目录语义已经属于 BitBlt / Display，**不往里加 UDP 的东西**。

### O.2 推荐归属

| 阶段                    | 位置                                                                                                                                              |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| **bring-up 阶段** | 按项目已有规则放`03_bringup/` 下对应的 UDP block 试验目录                                                                                       |
| **正式工程阶段**  | 在`04_project/` 下建立一个与 `bitblt_accel/` **并列**的 UDP Frame Status block；其 `sw/` 目录保存唯一权威 `udp_frame_status_regs.h` |

> 最终准确的目录名称仍**待团队确认**（见「仍需 B 最终确认」第 3 项）。

### O.3 C 侧引用纪律

```text
只通过 -I 引用
禁止复制
禁止软链
禁止维护第二份 offset 定义
```

> **字段表没有冻结之前，不创建这份正式头文件。**
>
> 现在的状态是：`07_docs/interfaces/udp_frame_status_v2_draft.md`（本文件）
> 是唯一记录字段的地方。**不得**提前生成 `udp_frame_status_regs.h`，
> 否则"文档草案"和"头文件"会形成两个真相源。

### O.4 hw-isolation 检查扩展（原则已确认，实现由 C 负责）

原「待 B 确认是否增加第三个头文件」→ 现结论：**需要扩展**。

B 给出的实现要求：不要继续复制 `grep bitblt_regs.h` + `case ...` 这种
**单头硬编码**逻辑，后续应改成**表驱动**检查。

语义目标：

```text
权威头文件                    → 唯一允许引用的实现文件
-----------------------------------------------------------------
bitblt_regs.h                 → driver/bitblt_api.c
display_regs.h                → driver/display_api.c
udp_frame_status_regs.h       → driver/udp_frame_status.c
```

具体实现第三阶段再做。

### O.5 `check-no-addresses` 白名单必须同步扩展

现有 `check-no-addresses` 用硬编码地址清单做白名单。**UDP Frame Status block base
必须加入该清单**，否则新 APB 地址进入 C 工程后可能形成**检查盲区**——
地址被硬编码却检查不到。

---

## P. 冻结顺序（最终）

```text
当前阶段
   ↓
A/C 对齐完整字段表
   ↓
B 正式确认 block base
   ↓
A/B/C 确认 AUTH_BASE / ARM
   ↓
冻结 udp_frame_status_v2.md（去掉文件名里的 _draft）
   ↓
确定 VERSION
   ↓
建立唯一 udp_frame_status_regs.h
   ↓
C 扩展 hw-isolation / check-no-addresses
   ↓
C 编写 snapshot / SEQ / ACK / AUTH 驱动和 host tests
   ↓
A 接顶层 RTL
   ↓
联合上板
```

> 顺序不得颠倒。特别是：**头文件必须在字段表与 base 都冻结之后才建立**，
> 否则会形成"文档草案"与"头文件"两个真相源。

---

# B 第一轮回复结论（4 项，已关闭）

### 1. 头文件归属 —— 已确认原则

```text
不放 bitblt_accel
bring-up  → 03_bringup 下的 UDP block 试验目录
正式工程  → 04_project 下独立 UDP block，sw/ 保存权威头文件
C 侧只 -I 引用，禁止复制 / 软链 / 维护第二份定义
```

**但正式 block 的最终目录名称待后续确定。**

### 2. VERSION —— 已确认原则

```text
IP-local version，不存在全局避撞要求
身份识别 = base + VERSION 联合判断
```

**具体 VERSION 数值待字段表冻结后确定。**

### 3. hw-isolation —— 已确认原则

```text
需要扩展，由 C 负责实现
建议改成表驱动，不要单头硬编码
```

### 4. `FRAME_SWAP_ERR_NOT_READY` —— 已确认原则

**暂不新增 frame_swap 公共错误码。**

先在第三阶段实现时明确区分这几类现有状态：

```text
· 软件未初始化 / 前置条件缺失
· Display SWAP_PENDING / EBUSY
· Display ETIMEOUT
· UDP producer 尚未交付快照
· UDP snapshot 自身错误
```

如果这些已有状态**仍无法表达**某个真实、且可恢复方式不同的第四类错误，
**再**提出新增错误码。即：

```text
先证明缺口 → 再新增错误码
```

不要为了"语义看起来更整齐"提前扩枚举。

若最终确实需要新增公共返回码，应**与本次 RGB565 / UDP 协议版本升级一起完成**，
而不是冻结后再零散修改。

---

# 仍需 B 最终确认（3 项）

```text
1. P1（优先级最高）：
   0xF8100100 - 0xF81001FF
   是否正式分配给 UDP Frame Status

2. 字段表冻结后：
   UDP Frame Status 最终 VERSION 值

3. 正式 UDP block 在 04_project 下的最终目录名称
```

---

# 仍需 A 最终确认

（原 11 条与 A 最新 P1/P2/P3 合并去重后）

**字段与位宽**

1. **A 当前 `frame_status_apb.v` 的完整 offset 表**——需 A 提交后逐项对齐
2. **`SWAP_SEQ` / `SWAP_FRAME` / `ID` 的定义**——本草案没有这些字段
3. `SLOT` 最终位宽和语义（3-bit 槽号 vs 联合工程双缓冲）
4. `FRAME_ID` 高 16 位是否恒 0（现状 16-bit）
5. **`FRAME_STATUS` bit 表**：保留原编号（bit1/bit2 留空）还是紧凑重排？
6. `LEN_ERR` / `NO_DATA_ERR` 是否单列为 bit6 / bit7？
7. `ARP_MISS` 移出 FRAME_STATUS、归入 ERR_STICKY——同意否？（RTL 证据：它不参与 `frame_ok`）
8. `CAL_DONE` 从 ACK 包状态字节移出、改放 LIVE_STATUS——同意否？这是行为迁移

**授权通路**

9. **`AUTH_BASE` / `ARM` / `AUTH_VALID` 方案是否采纳？**
10. **START 到来时若 `AUTH_VALID = 0` 的行为**（丢帧 + `AUTH_ERR`，还是其他）

**时序与资源**

11. **APB slave 在合并后落在哪个时钟域？**（决定 K 节是否真的零 CDC）
12. ACK 与 publish 同周期的优先级实现是否如 G.1，以及 G.3 的推论是否成立
13. `0xF8100000` 哑模块替换方案：如何扩展而不破坏厂商地址译码

---

# 跨分支联调提醒（非协议阻塞项）

> 这一条是 B 提出的 **merge / integration 风险**，**不属于 UDP 协议冻结内容**，
> 记录在此以免丢失。

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
C 当前自己的最新提交已经执行过 `make contract-test` 与 `./scripts/regress.sh quick`
并 **PASS**。这是一个**合并时才会暴露**的风险，不是当前缺陷。

正确表述：

> 合并 B 的 feature 分支时，必须**重新检查**双方 `test_contract.c`
> 与权威 framebuffer 头文件是否一致。

---

# 冻结后 C 侧将新增/修改的文件（预告，未实现）

> **字段表与 block base 冻结之前，一个都不会创建。**

| 文件                                       | 性质                                                               |
| ------------------------------------------ | ------------------------------------------------------------------ |
| `<UDP block>/sw/udp_frame_status_regs.h` | 新增，offset 唯一定义点（路径待 O.2 确定）                         |
| `driver/udp_frame_status_platform.h`     | 新增，tick 源 / host 模型接缝                                      |
| `driver/udp_frame_status.c`              | 新增，MMIO 唯一落点                                                |
| `driver/udp_frame_status.h`              | 新增，对外 snapshot API                                            |
| `driver/protocol_unfrozen.h/.c`          | 修改，`udp_completion` 语义升级                                  |
| `render/frame_swap.c/.h`                 | 修改，新增`frame_swap_udp_poll()` + `acquire_back()` 时 resync |
| `tests/test_udp_frame_status.c`          | 新增                                                               |
| `Makefile`                               | 修改，hw-isolation 改表驱动 +`check-no-addresses` 加 UDP base    |
