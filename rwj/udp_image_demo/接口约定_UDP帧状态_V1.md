# 接口约定：UDP 接收器 → C 组软件（帧完成状态）

> 角色 A · 2026-09-18 · 草案 V1，待 B/C 确认
> 对应《选题二 三人分工与 M1–M5 阶段目标》接口约定的第 3.2 节补充

---

## 0. 这个接口解决什么问题

换帧规则已经定了（写后台 → 整帧完成 → 等 VSYNC 切基址），但**软件目前无法可靠获知三件事**：

1. **哪一帧完成了** —— 现在 `frame_id_cur` 会被下一帧的 START 直接覆盖
2. **写到哪个后台槽位了** —— `frame_wslot` 同样会被覆盖
3. **DDR 写入是否全部成功** —— `frame_done` 是**单拍脉冲**，软件根本抓不到；而且 **AXI 写响应错误（BRESP）现在完全没检查**

后果：C 组的换帧驱动没法判断"这一帧到底该不该拿去做渲染"，只能靠猜或定时。

---

## 1. 现状（改之前）

`udp_image_demo/fpga/rtl/top.v`：

```verilog
332:  reg frame_done;     // 单拍：整帧完成            ← 脉冲，转瞬即逝
328:  reg [15:0] frame_id_cur;                        ← 下一帧 START 就覆盖
329:  reg [2:0]  frame_wslot;                         ← 同上
631:  wire frame_ok = frame_bytes_ok && !frame_seq_err && !fifo_ovf;
                          ↑ 没有 BRESP
155:  wire [1:0] bresp, rresp;                        ← 只声明和连线，从未使用
```

`bresp` 在全文件只出现 **2 次**（声明 + 连到 DDR 控制器），**没有任何逻辑读它**。

**DDR 写响应错误目前是被完全忽略的** —— 字节数对得上、序号不断、FIFO 不溢出，`frame_ok` 就是 1，哪怕这块数据根本没写进 DDR。

---

## 2. 内存映射

挂在 **APB slave 0**（`soc.h` 已确认）：

```
基地址  0xF8100000
大小    64 KB

  0x000 - 0x03F   BitBlt 引擎寄存器（B 组，见《A_下一步行动方案》6.2）
  0x100 - 0x11F   UDP 帧完成状态   ← 本文档定义
  其余             保留
```

**为什么用 0x100 而不是 0x00**：B 的 BitBlt 寄存器草案已经占了 0x00–0x38，
帧状态属于显示/素材通路（A 侧），物理上是另一个模块，用不同偏移段隔离，
以后要拆成两个 APB slave 也好拆。

---

## 3. 寄存器定义

| 偏移 | 名称 | R/W | 位宽 | 说明 |
|---|---|---|---|---|
| `0x100` | `FRAME_ID` | R | 16 | 最近**完成**帧的帧号 |
| `0x104` | `SLOT` | R | 3 | 该帧实际写入的槽位（0–3） |
| `0x108` | `BASE_ADDR` | R | 32 | 该帧实际写入的 DDR 基址（= SLOT × 2 MiB） |
| `0x10C` | `RX_BYTES` | R | 32 | 实际写进 DDR 的字节数 |
| `0x110` | `EXPECT_BYTES` | R | 32 | START 包声明的本帧总字节数 |
| `0x114` | `STATUS` | R | 32 | 状态位图，见 3.1 |
| `0x118` | `ACK` | W | 32 | **写任意值 = 软件确认，清除粘滞状态** |
| `0x11C` | `SEQ` | R | 32 | 完成帧计数器，每完成一帧 +1 |

> 全部按 32 位对齐访问。`FRAME_ID` / `SLOT` 高位置 0。

### 3.1 STATUS 位定义

| 位 | 名称 | 含义 |
|---|---|---|
| 0 | `DONE` | 最近一帧已完成（锁存，不是脉冲） |
| 1 | `FRAME_OK` | **整帧成功**，判据见第 4 节 —— 软件只用这一位就该能决策 |
| 2 | `SEQ_ERR` | `packet_idx` 断号/重复，或 END 的 `frame_id` 与 START 不一致 |
| 3 | `FIFO_OVF` | 接收 FIFO 或控制 FIFO 溢出丢拍 |
| 4 | **`BRESP_ERR`** | **AXI 写响应错误（SLVERR / DECERR）** ← 新增 |
| 5 | `ARP_MISS` | ACK 因 ARP 未命中未能发出 |
| 6 | `BYTES_MISMATCH` | `RX_BYTES != EXPECT_BYTES` |
| 7 | `SWAPPED` | 本帧触发了切屏（软件可据此确认显示已更新） |
| 8 | `CAL_DONE` | DDR 校准完成（只读回显，不参与判定） |
| 9–31 | — | 保留，读 0 |

### 3.2 数据是怎么来的

| 寄存器 | 来源（现有信号） |
|---|---|
| `FRAME_ID` | `frame_id_cur`（在 `frame_done` 时锁存） |
| `SLOT` | `frame_wslot`（同上，START 时锁定，帧内不变） |
| `BASE_ADDR` | `slot_base(frame_wslot)`，与写 DDR 用的是同一份 |
| `RX_BYTES` | `frame_rx`（END 时锁存的 `rx_bytes`） |
| `EXPECT_BYTES` | `frame_expect` |
| `SEQ` | 新增计数器，`frame_done` 时 +1 |

---

## 4. 整帧成功判据（含 BRESP）

```verilog
// 新增：AXI 写响应错误检测
wire bresp_err_pulse = bvalid && bready && (bresp != 2'b00);
// 粘滞：START 时清零，一帧内出过任何一次写错误就置位
reg  bresp_err;

// 整帧成功
wire frame_ok = frame_bytes_ok      // RX_BYTES == EXPECT_BYTES 且非 0
             && !frame_seq_err      // 序号连续、帧号一致
             && !fifo_ovf           // 没有溢出丢拍
             && !bresp_err;         // ← 新增：DDR 真的写成功了
```

**BRESP 编码**：`2'b00` = OKAY，`2'b01` = EXOKAY，`2'b10` = SLVERR，`2'b11` = DECERR。
只有 `2'b00` / `2'b01` 算成功。

### ⚠️ 这条会改变行为，需要重新验证

现在 `frame_ok` 用来**门控切屏**：

```verilog
671:  else if (frame_done && frame_swap && frame_ok)
          target_slot <= frame_wslot;
```

加上 BRESP 之后，**DDR 写偶发出错时这一帧不会切屏**，屏幕保持上一帧。

- **好处**：不会显示半张残图或全黑帧
- **代价**：属于行为变更，封版后的 UDP Demo 需要重新上板验证

**建议**：PC 端本来就有 `--retry` 重传机制，配合这个改动，出错帧会被重传，屏上始终是最新一张**完整**的图。这是更正确的行为，但要实测确认。

---

## 5. 软件使用方式（C 组）

### 5.1 轮询模式

```c
#define FRM_BASE      0xF8100100u
#define FRM_ID        (FRM_BASE + 0x00)
#define FRM_SLOT      (FRM_BASE + 0x04)
#define FRM_BASEADDR  (FRM_BASE + 0x08)
#define FRM_RXBYTES   (FRM_BASE + 0x0C)
#define FRM_EXPBYTES  (FRM_BASE + 0x10)
#define FRM_STATUS    (FRM_BASE + 0x14)
#define FRM_ACK       (FRM_BASE + 0x18)
#define FRM_SEQ       (FRM_BASE + 0x1C)

#define ST_DONE       (1u << 0)
#define ST_FRAME_OK   (1u << 1)
#define ST_BRESP_ERR  (1u << 4)
#define ST_SWAPPED    (1u << 7)

static uint32_t last_seq = 0;

/* 有新帧吗？返回 1 表示拿到一帧完整数据 */
int frame_poll(uint16_t *fid, uint32_t *base, uint32_t *bytes) {
    uint32_t seq = read_u32(FRM_SEQ);
    if (seq == last_seq) return 0;          /* 没新帧 */
    last_seq = seq;

    uint32_t st = read_u32(FRM_STATUS);
    *fid   = read_u32(FRM_ID) & 0xFFFF;
    *base  = read_u32(FRM_BASEADDR);
    *bytes = read_u32(FRM_RXBYTES);

    write_u32(1, FRM_ACK);                  /* 确认，清粘滞状态 */

    if (!(st & ST_FRAME_OK)) {
        bsp_printf("frame %u bad: status=0x%x\r\n", *fid, st);
        return -1;                          /* 坏帧，丢弃 */
    }
    return 1;                               /* 好帧，可以用 */
}
```

### 5.2 用 `SEQ` 而不是 `DONE` 判断"有新帧"

**不要**用 `DONE` 轮询 —— 它在软件确认前一直是 1，无法区分"新帧"和"上次那帧还没确认"。

**用 `SEQ`**：每完成一帧自增，永远单调。软件记下上次的值，变了就是有新帧。
第一次读取时 `last_seq` 初始化成当前值，避免开机就误判。

---

## 6. 实施清单

### 6.1 RTL（A 组）

**2026-09-18 已完成**（`efx_run -f map` 综合通过，位宽警告消失）：

| # | 改动 | 状态 |
|---|---|---|
| 1 | `bresp_err` 检测 + 粘滞位，START 时清零 | ✅ 已实施 |
| 2 | `frame_ok` 加入 `!bresp_err` | ✅ 已实施 |
| 3 | ACK 状态字节 bit5 = `bresp_err` | ✅ 已实施 |
| 4 | **ACK 回执位宽 bug 修复**（见下） | ✅ 已实施 |
| 5 | PC 端 `report_ack()` 增加 DDR 写入检查 | ✅ 已实施 |
| 6 | 新增 `st_*` 锁存寄存器组，`frame_done` 时锁存 | ⬜ 待合并时做 |
| 7 | 新增 `frame_seq` 计数器 | ⬜ 待合并时做 |
| 8 | APB slave 0 寄存器模块，映射到 `0xF8100100` | ⬜ 待合并时做 |

**第 6/7/8 项推迟的理由**：现在没有 CPU，锁存寄存器没有读者，综合会把它优化掉，
做了也验证不了。等 A1-4 加 APB slave 时一起做。

### 6.2 顺带修掉的一个真 bug：ACK 回执一直被截断

编译时从 Efinity 的 WARNING 里发现的：

```
WARNING: udp_img_rx.v(425): 128 differs from formal 192 for port 'req_payload'
WARNING: top.v(254):        192 differs from formal 128 for port 'ack_payload'
```

`top.v` 组的是 192 位（24 字节）回执，但 `udp_img_rx.v` 把透传口声明成了 `[127:0]`。
Verilog 连接时高 64 位被丢掉 —— 也就是 **magic(`0xA55B`) 和 `frame_id`**，
再传给 `udp_ack_tx` 时高位补 0。

PC 端按 magic 校验，`magic != 0xA55B` 直接拒收。**所以 `--ack` 和 `--retry`
从实现至今一直是静默失效的** —— 代码注释写着"没等到回执不算失败"，所以从来没报错。

修复：`udp_img_rx.v` 的 `[127:0]` 改成 `[191:0]`（纯透传口，无逻辑依赖）。

> **对历史结论的影响**：2026-09-18 之前所有关于"回执正常"的判断都不可信。
> 但图片显示本身不受影响 —— 收图和显示走的是另一条路径，没经过这个口。

### 6.2 软件（C 组）

| # | 工作 |
|---|---|
| 1 | 写 `frame_poll()` 驱动（照第 5 节） |
| 2 | 换帧逻辑改为由 `SEQ` 驱动，不再靠定时 |
| 3 | 失败帧策略：丢弃 + 打日志；PC 端 `--retry` 负责重传 |

### 6.3 待确认（需 A/B/C 一起定）

| 问题 | 选项 |
|---|---|
| BRESP 错误是否门控切屏？ | 建议**门控**（本方案默认）。备选：只记录不门控，屏上可能显示残图 |
| 要不要中断？ | 现在用轮询够了；如果 C 组做游戏循环需要低延迟，M4 再加 `IRQ_EN`（BitBlt 那份草案里有） |
| 环状缓冲还是单缓冲？ | 现在 4 槽轮转够用；如果 C 组要"最新帧优先"，可以扩成 8 槽 |
| `BYTES_MISMATCH` 要不要单列？ | 现在 `frame_bytes_ok` 已经隐含了，单列出来是为了调试方便 |

---

## 7. 附：DDR3 容量确认（影响地址规划）

实测确认（2026-09-18）：

| | `udp_image_demo` | `demo/08` |
|---|---|---|
| BANK / ROW / COL | 3 / 14 / 10 | 3 / 14 / 10 |
| **`ADDR_WIDTH`** | **30** | **28** |
| `AXI_ADDR_WIDTH` | 32 | 28 |

**几何完全相同** → 8 banks × 16384 rows × 1024 cols = 128M 单元
→ 配 16-bit 位宽 DDR3 = **256 MB**。

**两个工程的 `ADDR_WIDTH` 不一致（30 vs 28），合并时必须统一。**
按芯片实际容量，**28 是对的**。

实测（`riscv/projects/ddrtest`，1MB 步长扫 0x00100000–0x10000000）：
255 个探针全部正确，位模式、地址译码全过 → **1MB–256MB 整段可用**。

帧状态接口的地址规划（4 槽 × 2 MiB）：

```
0x00200000  槽位 0   ← FRAME_WSLOT / BASE_ADDR 会落在这个范围
0x00400000  槽位 1
0x00600000  槽位 2
0x00800000  槽位 3
0x00A00000  以上：预留给 BitBlt 素材区 / 中间缓冲
0x10000000  256 MB 硬边界
```
