# FPGA 赛题二：系统目标、分工与当前协议问题审计

- 审计日期：2026-09-19
- 审计范围：仓库主线现有 Markdown、赛题指南、A/B/C 三侧 RTL 与软件代码，以及尚未合入主线的 `origin/feature/rgb565-720p-integration` 文档
- 文档性质：**现状审计与收敛建议，不是新的冻结协议**
- 核心结论：**三个小系统分别已有成果，但当前不存在一套能够联合运行的端到端协议和联合位流。**

> 阅读本文时必须区分四种状态：目标已选择、协议已冻结、局部代码已实现、联合实板已验证。
> 当前仓库中这四种状态经常被混写，这是本次协议混乱的首要原因。

---

## 1. 项目的最终目标

### 1.1 赛题原始要求

赛题二要求在 Ti60F225 上实现一个 RISC-V + FPGA 异构 2D 图形系统：

1. RISC-V 运行游戏或 GUI 高层逻辑，下发渲染命令；
2. FPGA BitBlt 引擎直接访问 DDR，至少支持 Solid Fill 和 Block Copy；
3. DDR 访问使用 Burst 和内部 FIFO/缓存；
4. Framebuffer 经 VGA/HDMI 输出，最低要求 640×480@60 Hz；
5. 软件实现 Double Buffer，避免撕裂；
6. Demo 对比 CPU 渲染与 FPGA 加速的 FPS；
7. 高阶目标包括 Color Key、Alpha Blend 和高 Sprite 数量的互动游戏。

仓库额外形成了一个有展示价值的输入链：PC 将图片转换为 RGB565，经千兆以太网 UDP 送入 FPGA，再由统一显示/渲染系统使用。

### 1.2 团队已选的联合目标

目前团队意图统一为：

| 项目 | 联合目标 |
|---|---|
| 显示 | 1280×720@60 Hz，74.25 MHz 像素时钟 |
| 像素 | RGB565，`R[15:11] G[10:5] B[4:0]` |
| 内存字节序 | 小端；低地址存 RGB565 低 8 位 |
| stride | 2560 B/行，16 B 对齐 |
| 有效帧大小 | 1,843,200 B |
| DDR 数据总线 | 128-bit AXI4；每 beat 16 B，即 8 个 RGB565 像素 |
| Framebuffer | A=`0x01000000`，B=`0x01800000`，每槽保留 8 MiB |
| BitBlt 控制 | SYSTEM_AXI_A，`0xE1000000` |
| 显示控制 | SYSTEM_AXI_A，`0xE1100000` |
| 换帧 | C 侧软件是唯一提交者；显示仅在 VBlank 切换 |

理想的联合数据流应当是：

```text
PC RGB565 图片
      |
      v
A：UDP 接收/完整性检查 ----完成快照----> C：RISC-V 软件
      |                                      |
      | 仅写“软件授权的后台”                  | NEXT_ADDR + SWAP_REQUEST
      v                                      v
                         DDR A/B Framebuffer
                           ^              |
                           |              v
                   B：BitBlt          B：Display DMA/HDMI
                   写后台              只读当前前台
```

其中最重要的系统不变量是：

- 任一时刻只有一个生产者拥有后台 Buffer：UDP 或 BitBlt；
- UDP、BitBlt 都不能写当前前台；
- 只有 C 软件可以请求换帧；
- 收帧/渲染完成不等于已经上屏；只有 `SWAP_DONE` 且 `FRONT_ADDR` 回读正确后，旧前台才重新可写。

---

## 2. 三方分工：目标分工与实际代码边界

| 角色 | 目标职责 | 当前已有成果 | 尚未闭环的部分 |
|---|---|---|---|
| A：平台/网络接收 | UDP/RGMII、收帧完整性、UDP 写 DDR、CPU 可见完成通知、联合平台接入 | 独立 720p/RGB565 UDP+HDMI Demo；PC 转换/发送工具；Frame Status APB RTL 与 TB | APB 模块未接入 SoC；授权输出未接 UDP 写状态机；独立 Demo 仍使用低地址 slot 和硬件自动换帧 |
| B：2D 加速与显示数据面 | BitBlt Fill/Copy/Color Key、显示 DMA/控制器、DDR 仲裁、SYSTEM_AXI_A 控制面 | 1080p/XRGB8888 V0.4 已完成大量仿真、板测、性能和老化验证 | RGB565 BitBlt、720p 显示、三写主仲裁和 UDP 联合顶层尚未在主线实现 |
| C：RISC-V 软件/游戏 | CPU 参考渲染、统一渲染 API、BitBlt/显示驱动、Buffer 所有权与换帧状态机、游戏 | 软件默认已迁移到 RGB565；CPU 渲染、格式转换、状态机和主机测试较完整 | UDP MMIO 驱动、AUTH/ACK/seqlock 尚未实现；当前 UDP capability 默认不可用；尚无联合硬件可供板测 |

### 2.1 一个需要明确的职责重叠

A 的旧独立 Demo 自带显示读状态机、HDMI 时序、按键/自动轮播换帧；B 的正式工程也有 Display DMA、显示控制寄存器和 HDMI 输出。

联合系统不能同时保留两个显示控制面。按当前统一方向，应明确：

- B 的 `0xE1100000` Display Controller、Display DMA 和 VBlank swap 是联合工程唯一显示路径；
- A 向联合工程提供 UDP 接收与写入生产者，不再直接维护 `active_slot/target_slot`；
- A 独立 Demo 的显示逻辑只保留作独立回归，不进入联合顶层。

目前文档中“A 负责平台/显示”和“B 已实现显示控制/DMA”同时存在，但没有明确最终顶层、HDMI 和 DDR 配置由谁合并、谁签字。这是组织边界问题，也会直接变成接口问题。

---

## 3. 三套实现当前实际上并不兼容

### 3.1 A 侧当前真实协议

A 的独立 Demo 当前是：

- RGB565、1280×720@60；
- 16 B UDP 私有包头，大端字段；图片 payload 为 RGB565 小端字节流；
- DDR 从地址 0 开始，每槽 2 MiB，`slot_base = slot << 21`；
- 网络包的 `slot`、`DBUF`、`AUTO_SWAP` 可以决定写入和切屏；
- `active_slot/target_slot` 由硬件自行管理；
- Frame Status APB V2 模块已存在于源码和工程文件中，但**没有在 `top.v` 中例化，也没有接到写状态机**；
- 新增的 `evt_write_enable/evt_write_base` 只是模块输出，尚未成为真实 DDR 写门控；
- PC 方向 UDP ACK 路径已有明确的未修缺陷，不能作为可靠确认通道。

所以，A 的“UDP 图片可显示”已成立，但“A 的 UDP 可以安全写联合 Framebuffer 并由 C 控制换帧”尚未成立。

### 3.2 B 侧当前真实协议

B 的主线 RTL 当前仍是历史 V0.4：

- XRGB8888、1920×1080@60；
- BitBlt `VERSION=0x00010004`；
- Display `VERSION=0x00020000`，`FORMAT` 只接受 0；
- BitBlt 一个 128-bit beat 按 4 个 32-bit 像素处理；
- Fill 使用 `{4{color}}`；Color Key 比较每个像素低 24-bit RGB，并按 4-byte lane 屏蔽；
- Display DMA 使用 `width >> 2`，像素解包器每 beat 输出 4 个 XRGB8888 像素；
- 显示控制器硬编码校验 1920×1080、stride≥7680、format=0；
- 视频时序模块固定为 1080p；
- DDR 写仲裁只有 CPU/BitBlt 两个主机，没有 UDP 第三写主。

所以，B 的旧通路是当前最扎实的板测基线，但不能直接接收 A/C 的 RGB565 Framebuffer。

### 3.3 C 侧当前真实协议

C 软件当前默认：

- `pixel_t=uint16_t`，RGB565、1280×720；
- 期望 BitBlt RGB565 `VERSION=0x00020000`；
- 期望 Display RGB565 `VERSION=0x00030000`、`FORMAT=1`；
- 使用 B 的 Framebuffer A/B 地址；
- 实现了“软件唯一换帧者”的逻辑状态机；
- 但 B 的权威头文件仍是旧格式，因此 C 在 `protocol_frozen.h` 中临时代持新枚举和版本号；
- `protocol_unfrozen.h` 仍把 UDP 完成通知视为 UNKNOWN，默认地址为 0；
- 没有 `udp_frame_status_regs.h`、真实 MMIO 驱动、AUTH 写入、snapshot seqlock、matching ACK 或 acquire 时 resync。

所以，C 的新软件模型与团队目标一致，但当前只能做主机侧逻辑验证，不能驱动现有 B 位流，也不能消费 A 的 APB 快照。

### 3.4 当前可运行组合

| 组合 | 结果 |
|---|---|
| A 独立 UDP Demo | 可运行，但使用自己的 DDR slot 和换帧规则 |
| B V0.4 BitBlt+Display | 可运行，且 XRGB8888/1080p 板测证据充分 |
| C 默认 RGB565 软件 + B V0.4 位流 | 正确行为是因 VERSION 不匹配而 fail-fast；显示初始化和板测路径已有此检查，不能作为联合配置运行 |
| A UDP + B BitBlt/Display + C 软件 | **尚不存在联合顶层/联合位流** |

---

## 4. 协议真相源本身存在冲突

### 4.1 同一事项在不同文件中有不同状态

| 事项 | 主线文档/代码中的说法 | 另一处说法 | 审计判断 |
|---|---|---|---|
| RGB565 FORMAT 与新版 VERSION | 主线 `rgb565_720p_migration.md` 仍写“建议/待确定” | C 的 `protocol_frozen.h` 和未合入主线的集成分支写“已冻结” | 数值大概率已经形成共识，但主线权威文档未同步 |
| UDP block base | V2 draft 写“待 B 最终确认” | `udp_frame_status_interface_review_v0.1.md` 写 B 已同意 `0xF8100100–0xF81001FF`；未合入分支也写已冻结 | 团队历史记录互相矛盾，不能仅凭代码默认值认定正式分配 |
| UDP 字段表 | draft 说 A/C 基本对齐 | A response 与当前 RTL 已进一步加入 AUTH 和 `LIVE_STATUS.bit1` | 字段表接近完成，但主草案的状态段落没有完全更新 |
| A RTL 是否已提交 | draft §A.0 仍写“尚未提交” | 当前源码已存在，且 response 记录 82 项检查 | 文档明显过期 |
| AUTH_ERR 六点语义 | draft 后部仍写“待 A 确认” | 当前 HEAD 提交及 A response 已明确接受并实现 | 文档明显过期 |
| B 进度 | `B_role_progress_and_plan.md` 写 Color Key 未开始、接口版本 `0x00010003` | V0.4 代码与板测记录表明 Color Key 已完成 | 进展文档过期 |
| BitBlt 接口文档名 | 文件名是 `bitblt_interface_v0.2.md` | 文件标题和内容已是 V0.4 历史实现 | 容易被脚本和成员误判版本 |

### 4.2 建议的文档优先级

在正式收敛前，建议使用以下证据优先级：

1. 当前分支实际 RTL/C/Python 代码：说明“现在实现了什么”；
2. 主线明确标记“已冻结”的接口文档：说明“团队承诺什么”；
3. 板测/仿真记录：说明“什么被验证过”；
4. 个人工作区进度文档和旧草案：只提供背景；
5. 未合入主线的远端分支文档：只能作为待合并决定，不能覆盖主线合同。

目前缺少一个主线 `07_docs/README.md` 形式的权威索引。未合入的集成分支已经有较好的索引草案，建议合并或重建，并明确每份文件是“当前合同”“历史基线”“评审记录”还是“草案”。

---

## 5. 当前协议问题清单

### P0-1：像素格式和显示几何没有在硬件端统一

**现象**

- A 和 C 已按 RGB565/720p 工作；
- B 主线仍按 XRGB8888/1080p 工作；
- 只改软件宏、Framebuffer 内容或寄存器值不会改变 B 的数据解释。

**影响**

- 同一 128-bit DDR 数据，A/C 解释为 8 个像素，B 解释为 4 个像素；
- stride、宽度粒度、Fill color、Color Key、显示解包全部不同；
- 误配不会总线报错，通常只表现为花屏或错误写入，最难排查。

**必须完成**

1. BitBlt 的 Fill/Copy/Color Key 改为 8×RGB565/beat；
2. Fill 将 `COLOR[15:0]` 复制 8 次；Color Key 对 8 个 16-bit 像素精确比较，并成对控制两个 `WSTRB`；
3. 宽度必须为 8 像素倍数，stride≥width×2；
4. Display DMA 按 width/8 计算；新增 RGB565 解包和 RGB888 位扩展；
5. 显示控制校验 1280×720、2560、FORMAT=1；
6. 视频时序、PLL 和约束改为 74.25 MHz/720p；
7. 完成仿真、完整编译、时序和实板显示后，RTL 才能返回新版 VERSION。

### P0-2：DDR 地址协议仍有两套，且新授权门控没有接入真实写路径

**现象**

- 联合目标使用 `0x01000000`/`0x01800000` 两个 8 MiB Framebuffer；
- A `top.v` 仍使用 `slot << 21`，允许写 `0x00000000` 起的 2 MiB 槽；
- A 的 Frame Status 模块已能输出 `evt_write_enable/evt_write_base`，但 `top.v` 写地址仍来自 `slot_base(frame_wslot)+byte_offset`；
- Frame Status 模块当前没有在 `top.v` 例化。

**影响**

把 A 独立写状态机直接并入 SoC，最坏会覆盖低 16 MiB 的 RISC-V 程序、栈或数据。

**必须完成**

- 联合版 UDP `AWADDR` 只能来自“已锁存 AUTH_BASE + 已验证的帧内 offset”；
- AUTH_BASE 只能是 FB_A 或 FB_B；
- 无授权/非法授权必须硬件禁止任何 DDR 写；
- 网络包里的 slot、DBUF 或 AUTO_SWAP 不得参与联合版物理地址计算；
- A 独立 Demo 与联合版应通过明确的顶层/构建目标隔离，不能靠注释区分。

### P0-3：Buffer 所有权和换帧控制链只完成了两端，未形成闭环

**目标顺序**

```text
C acquire 后台
→ C 向 A 写 AUTH_BASE + ARM，或向 B 下发 BitBlt
→ 生产者完成
→ C 验证结果
→ C 写 NEXT_ADDR + SWAP_REQUEST
→ 等新的 SWAP_DONE
→ 回读 FRONT_ADDR
→ ACK 完成快照并释放旧前台
```

**实际缺口**

- A 独立 Demo 仍可通过 UDP flag、按键和自动轮播直接换帧；
- C 的 `frame_swap_acquire_back()` 只改软件状态，没有写 A 的 AUTH 寄存器；
- C 没有 UDP snapshot 驱动，`frame_swap_udp_frame_ready()` 默认直接返回 NOT_READY；
- acquire 后需要的 `udp_frame_status_resync()` 尚未实现；
- A 的授权输出未接真实写状态机；
- 没有联合测试证明 UDP 与 BitBlt 不会同时写同一后台。

**结论**

“C 是唯一换帧提交者”目前是正确设计原则，不是已经实现的系统事实。

### P0-4：UDP 收帧的“完整帧”判据仍不足以证明图像写对了

当前 A 写状态机主要检查：

- DATA 的 `packet_idx` 是否连续；
- 累计 `rx_bytes` 是否等于 START 声明的 `frame_expect`；
- FIFO 是否溢出；
- DDR BRESP 是否为成功。

但以下字段或约束没有被完整验证：

1. `frame_expect` 是否**恰好等于 1,843,200**；当前任意非零且自洽的短帧都可能成为 `FRAME_OK`；
2. DATA `byte_offset` 是否连续、无重复、无空洞；当前两个连续包可以写同一 offset，累计字节数仍正确；
3. `byte_offset + payload_len` 是否越过有效帧或 Framebuffer 槽边界；
4. `payload_len` 是否为 16 B 的倍数、是否与实际 UDP payload 长度一致；解析器保留了 `pkt_len` 输入但没有使用；
5. 所有包的 `total_pkts` 是否一致，END 声明的实发包数是否匹配；解析器没有把 `total_pkts` 送入写状态机；
6. START/DATA/END 的 slot/flags/total 是否属于同一帧配置；
7. 超长、重复 START、无 START 的 DATA、提前 END 的恢复语义。

这意味着“包数顺序和总字节数正确”还不等于“每个目标字节恰好写了一次”。对于会直接写 DDR 的网络输入，这是功能正确性问题，也是内存安全问题。

建议联合协议至少强制：

```text
EXPECT_BYTES == 1,843,200
payload_len > 0 且 payload_len % 16 == 0
UDP_payload_length == 16 + payload_len
byte_offset == expected_next_offset
byte_offset + payload_len <= EXPECT_BYTES
packet_idx == expected_packet_idx
每包 total_pkts == START.total_pkts
END.actual_pkts == received_pkts == total_pkts
最终 RX_BYTES == EXPECT_BYTES
最后一笔 BRESP 已返回且必须为 OKAY
```

### P0-5：联合 SoC 的 AXI/DDR 拓扑还没有定义完成

**现状**

- B 的写仲裁器只有 CPU/BitBlt 两主机；
- UDP 将成为第三个 DDR 写主；
- B 的读路径已有 CPU、BitBlt、Display；联合版通常不需要保留 A 的旧显示读主；
- A 独立工程使用 108 MHz `sys_clk`，B 使用 100 MHz `user_clk`；
- 两份 DDR3 配置不可逐参数混搭，A 已有“混搭后编译通过但板上花屏”的记录；
- AXI ID、仲裁公平性、最大 Burst、响应路由和 reset/clock domain 尚无统一表。

**必须由最终顶层负责人冻结**

- 整套沿用哪一份 DDR controller/IP 配置；
- UDP 写主接入方式：3-to-1 或级联仲裁；
- CPU、BitBlt、Display、UDP 的 AXI ID；
- 各主机时钟、复位和 CDC；
- Burst 边界公平性，确保显示不欠流且 CPU/BitBlt/UDP 不饿死；
- 所有 `RRESP/BRESP/RID/BID/RLAST` 错误的归属和上报方式。

建议整套沿用 B 已板测 DDR 配置和 100 MHz user clock，再迁移 A 的 UDP 写前端，不要参数拼接。

### P1-1：UDP Frame Status 接近收敛，但还没有正式基线

当前 A RTL 对应的候选寄存器表为：

| 相对 `0xF8100100` 偏移 | 名称 | 属性 | 当前实现语义 |
|---:|---|---|---|
| `0x00` | SEQ | RO | 最新 snapshot 发布计数 |
| `0x04` | FRAME_STATUS | RO | 当前 SEQ 的帧状态 |
| `0x08` | FRAME_ID | RO | 低 16 位有效 |
| `0x0C` | SLOT | RO | 仅诊断，联合版合法值 0/1 |
| `0x10` | BASE_ADDR | RO | 硬件实际锁存并使用的地址 |
| `0x14` | RX_BYTES | RO | 当前快照实际字节数 |
| `0x18` | EXPECT_BYTES | RO | START 声明字节数 |
| `0x1C` | ACK_SEQ | WO | 匹配当前 SEQ 才清 ERR_STICKY |
| `0x20` | LIVE_STATUS | RO | bit0 CAL_DONE；当前 RTL 另有 bit1 AUTH_PENDING |
| `0x24` | ERR_STICKY | RO | 自 matching ACK 以来的累计诊断错误 |
| `0x28` | VERSION | RO | 当前 RTL 默认 `0x00010000`，尚缺主线最终确认 |
| `0x2C` | AUTH_BASE | RW | 下一帧授权地址 |
| `0x30` | AUTH_CTRL | WO | bit0 ARM，一次性授权 |

`FRAME_STATUS` 当前实现为：

| bit | 名称 |
|---:|---|
| 0 | FRAME_OK |
| 1 | SEQ_ERR |
| 2 | FIFO_OVF |
| 3 | BRESP_ERR |
| 4 | LEN_ERR |
| 5 | NO_DATA_ERR |
| 6 | AUTH_ERR |

尚需一次正式签收：

1. block base 是否正式为 `0xF8100100`；
2. `VERSION=0x00010000`；
3. APB 使用 100 MHz user/sys clock；
4. `LIVE_STATUS.bit1=AUTH_PENDING`；
5. Reserved/未映射地址是 `PSLVERR=1` 还是保持厂家 `PREADY=1/PRDATA=0/PSLVERR=0`；
6. 唯一权威 `udp_frame_status_regs.h` 的位置和维护者。

在这些项目签收前，当前 A localparam、C 草案和远端分支文档仍是多个真相源。

### P1-2：AUTH 跨域实现存在“恰好一次消费”风险

当前 A 实现把 APB 域 `auth_pending` 作为电平同步到事件域，事件域在 START 时消费并用 toggle 回传清除。

需要重点复核两个边界：

1. CPU 写 ARM 后，`auth_pending` 尚未跨过同步器，START 已到达，会被当成无授权帧；
2. 第一次 START 已消费授权，但“清 pending”尚未往返同步完成时，若又到一个 START，同一授权电平可能被再次消费。

网络包的正常间隔可能让问题很难触发，但协议不能依赖“应该来不及”。建议事件域持有一个本地的一次性 token，在第一次 START 当拍原子清除；或者使用 request/ack toggle 形成明确的 armed/consumed 状态。`AUTH_PENDING` 还应明确表示“APB 写入待消费”还是“事件域已经 armed”，两者不是同一状态。

### P1-3：Display API 与硬件状态位语义存在启动和重复换帧风险

当前 C `display_init()`：

1. 写几何/FORMAT；
2. 写 `NEXT_ADDR=front_addr`；
3. 立即发 SWAP_REQUEST；
4. 不等待 VBlank 就返回成功。

但 B 显示控制器复位后 `FRONT_ADDR=FB_A`，并要求 `NEXT_ADDR != FRONT_ADDR`。若 `display_init(FB_A, ...)`，硬件会置 ERROR。

另外，B 的 `SWAP_DONE` 是粘滞位，必须 CLEAR。C 的 `display_queue_swap()` 没有在新请求前清旧 `SWAP_DONE`，`display_wait_swap()` 可能立即读到上一次的 DONE，在新 VBlank 到来前错误返回。旧板测程序依赖共享 IRQ handler 清状态，而 C 的通用轮询 API 不能隐含依赖一个尚未安装的 ISR。

需要冻结以下语义：

- `display_init(front_addr)` 是否保证返回时该地址已经成为前台；
- 若硬件复位前台已经是期望地址，是否只配置并 ENABLE，不发 swap；
- 每次 queue 前由谁清 stale DONE/ERROR；
- CLEAR 是否保留 ENABLE；
- 轮询与中断两种模式是否共享同一状态消费规则。

### P1-4：AXI BRESP 成功判据不一致

A 独立写状态机把 `OKAY(00)` 和 `EXOKAY(01)` 都视为成功；B BitBlt 和联合迁移文档要求 `BRESP==OKAY`。

普通非独占 DDR 写不应返回 EXOKAY。建议统一为：**只有 2'b00 是成功，其余全部置错**。否则 A/B 对同一 DDR controller 异常的判断不同。

### P1-5：网络包协议仍带有独立 Demo 专用语义

当前 16 B UDP 包头没有显式协议版本，并复用了字段：

- START 的 `byte_offset` 表示总帧长；END 的同一字段表示实发包数；
- START 的 `packet_idx` 可被 AUTO 模式借作轮播间隔；
- `slot`、AUTO_SWAP、DBUF、AUTO 都会影响 A 独立 Demo 的地址或显示；
- PC ACK 的 status bit 表与 CPU Frame Status 的 bit 表不同；两者是不同协议。

联合版必须定义一个明确 profile：

- 建议保留现有 16 B 头以减少改动；
- 联合模式下 `slot` 仅诊断或必须为 0/1，但**不决定地址**；
- AUTO_SWAP、DBUF、AUTO 必须拒绝或忽略，不能绕过 C 软件；
- START/DATA/END 每种包允许使用哪些字段必须形成表格；
- PC ACK 与 CPU Frame Status 分开命名、分开版本；PC ACK 当前不可用，不作为联合 MVP 门禁。

### P1-6：BitBlt 对齐约束尚未转化为游戏层规则

RGB565 目标若保持 16 B 地址对齐，则矩形起始 x 和宽度通常都需要 8 像素对齐。游戏中的 Sprite、字体和裁剪结果很容易落在任意 x 坐标。

当前尚未决定：

- 硬件是否支持首尾 partial beat/WSTRB；
- 还是软件将不对齐边缘交给 CPU；
- 或把“坐标必须 8 像素对齐”变成游戏素材与布局规则。

这不是小优化，而是渲染 API 能否满足真实游戏的接口语义。建议在游戏 Demo 开始堆内容前冻结。

### P1-7：中断所有权和轮询模式需要明确

- BitBlt 与 Display 已共享 PLIC 源 30，应用必须读取两套 STATUS 判源；
- UDP Frame Status MVP 已倾向纯轮询，不并入源 30；
- 文档曾建议将来优先使用 PLIC 源 16；
- C 的 capability 结构仍保留 `udp_completion_irq_id`，容易让人误以为 MVP 有中断；
- C 尚无联合应用层共享 IRQ dispatcher。

建议 MVP 明确写死“UDP polling、IRQ_ID 不存在/必须为 0”，后续增加中断时升 UDP 协议小版本，并单独验证 PLIC 路由。

### P2-1：版本号规则与命名不统一

- 团队新规则是高 16 位 major、低 16 位 minor；
- `DISPLAY_VERSION_V0_2=0x00020000` 按该规则实际是 V2.0；
- 新 BitBlt V2.0 也使用 `0x00020000`，数值相同但寄存器基址不同，协议上允许，日志上容易误读；
- `bitblt_interface_v0.2.md` 实际记录的是 V0.4 历史实现；
- B 进展文档仍写 `0x00010003`。

建议所有日志统一打印“设备名 + base + version”，不要只打印 version 数字；历史宏可保留兼容别名，但新文档统一按编码规则命名。

### P2-2：构建与回归目前不能从本仓库路径直接复现

本次审计尝试运行现有回归：

- A、B RTL 仿真均因当前环境没有 `iverilog` 而未执行；不能把历史 PASS 当成本次运行结果；
- C 的聚合 Makefile 在仓库路径包含空格（`ZX1 2TB`）时没有正确引用 `$(TOP)` 等路径，Make 将路径拆成多个目标，`make test/check` 无法启动；
- 将相同的 C 与 B driver 源码复制到无空格临时路径，并以 `ASAN_OPTIONS=detect_leaks=0` 适配当前受监控执行环境后，`make test`、`make check` 和 `make test-legacy` 全部通过：RGB565 与 XRGB8888 两种软件格式、换帧状态机、静态隔离检查及板测逻辑模型 10/10 均通过；这些结果证明 C 的局部软件模型自洽，**不证明真实 MMIO、UDP 或联合位流可用**；
- 当前工作树中的 A Frame Status 文档/RTL/TB已有未提交修改，本审计按当前文件内容分析，并未改写这些文件。

路径问题不是硬件协议本身，但它会阻止合并后自动发现协议漂移。建议 CI 或固定无空格工作目录，并修复 Makefile 的路径处理；联合协议冻结后至少需要一条不依赖个人目录的回归入口。

---

## 6. 建议收敛成的一套 MVP 基线

以下是基于现有共识的建议，需三方签字后再改成正式合同。

### 6.1 数据与地址

- RGB565 小端，1280×720@60；
- stride=2560，frame bytes=1,843,200；
- FB_A=`0x01000000`，FB_B=`0x01800000`，slot size=8 MiB；
- 系统区、素材区、Scratch 保持 B 布局；
- 网络包、软件和 RTL 不允许再定义另一套 Framebuffer 基址。

### 6.2 控制面

- BitBlt：AXI `0xE1000000`，RGB565 VERSION=`0x00020000`；
- Display：AXI `0xE1100000`，FORMAT=1，RGB565 VERSION=`0x00030000`；
- UDP Frame Status：APB `0xF8100100`，VERSION=`0x00010000`，MVP polling；
- UDP 字段表采用本文 §P1-1；`LIVE_STATUS.bit1=AUTH_PENDING` 必须正式写入；
- APB 整个窗口 `PREADY=1`。未映射区建议先保持厂家兼容行为 `PRDATA=0/PSLVERR=0`，除非确认 Sapphire 对 PSLVERR 的异常处理并完成板测。

### 6.3 UDP 写入安全

- CPU 的一次性 AUTH token 是地址唯一来源；
- token 只能授权 FB_A 或 FB_B，且在事件域恰好消费一次；
- 无 token、非法地址、前台地址或越界包都不得发出 AXI AW/W；
- 写地址只能是 `latched_auth_base + validated_next_offset`；
- `FRAME_OK` 必须包含固定帧长、连续 offset/packet、FIFO、最后 BRESP 等全部检查；
- snapshot 只能在最后写响应完成后发布。

### 6.4 Snapshot/ACK

- snapshot 字段与 SEQ 对软件原子可见；软件用 SEQ-field-SEQ seqlock 读取；
- SEQ 允许 32-bit 回绕，只比较相等/不等；
- 只保留 latest snapshot，不承诺事件 FIFO；
- ACK_SEQ 只表示“软件消费过该快照”，matching 时仅清 ERR_STICKY；
- publish 与 ACK 同周期时 publish 优先；
- ERR_STICKY 只用于诊断，不能替代当前 FRAME_STATUS 判断；
- acquire UDP 后先 resync，再 ARM，防止旧 snapshot 被误判为新帧。

### 6.5 换帧

- C 是唯一提交者；A/B 不直接修改显示前台；
- 每次新请求前明确清除旧 SWAP_DONE/ERROR；
- `SWAP_DONE` 后必须回读 `FRONT_ADDR==pending`；
- 超时或不一致时不释放可能成为前台的 Buffer，进入可诊断失败态；
- 只有完成上述确认后，旧前台才成为下一次后台。

---

## 7. 建议的下一步分工

### A 侧

1. 把 UDP 写状态机抽成联合版模块，移除 `slot_base()` 对物理地址的控制；
2. 接入 AUTH token，并在事件域做到恰好一次消费；
3. 增加固定帧长、offset、payload 实长、total_pkts、边界和严格 BRESP 检查；
4. 将 Frame Status APB wrapper 真正接入 SoC，不再只是工程源文件；
5. 联合版禁用硬件直接 swap、按键切前台和自动轮播；
6. Frame Status TB 增加授权同步边界、连续 START、越界 offset、短帧伪成功和 EXOKAY 用例；
7. PC sender 增加“standalone/integrated”明确模式，避免发出联合版不允许的 flags。

### B 侧

1. 完成 BitBlt RGB565 数据面和新版 VERSION；
2. 完成 720p Display DMA、RGB565 unpack、时序/PLL和新版 VERSION；
3. 指定最终联合顶层负责人，并整套采用已板测 DDR 配置；
4. 将 UDP 写主接入 DDR 仲裁，冻结 AXI ID、Burst 和公平策略；
5. 最终确认 UDP APB base、clock、VERSION、未映射行为；
6. 将已冻结 RGB565 枚举/版本写入 B 权威头文件，结束 C 的临时代持。

### C 侧

1. 在正式 header 出现后实现唯一 UDP MMIO 驱动；
2. 实现 seqlock poll、matching ACK、VERSION/LIVE 检查和 snapshot renderable 判定；
3. acquire UDP 成功后执行 resync、写 AUTH_BASE、ARM，并处理 AUTH_PENDING；
4. 修正 Display init、stale SWAP_DONE 清理和轮询/IRQ一致语义；
5. 实现 PLIC 30 的 BitBlt/Display统一 dispatcher；UDP MVP 保持轮询；
6. 明确不对齐矩形的 CPU fallback 或拒绝策略；
7. 增加 UDP 驱动 host model 和状态机联合测试。

### 三方共同

1. 只保留一份当前联合接口文档，并把其余文件明确标成历史或评审记录；
2. 共同签收寄存器表、网络包 profile、AXI 主机表和完整时序图；
3. 用同一个测试帧完成 PC→UDP→DDR后台→C确认→VBlank换帧→HDMI 的最小闭环；
4. 再加入 BitBlt 写后台，与 UDP 轮流取得所有权；
5. 最后做 CPU/BitBlt/UDP/Display 并发压力、零欠流和错误注入。

---

## 8. 联合验收门禁

建议按以下顺序验收，前一层未通过不要宣称后一层完成：

1. **协议静态检查**：唯一头文件、无重复地址/offset/version、A/B/C 编译期断言一致；
2. **模块仿真**：RGB565 BitBlt、Display、UDP parser/write/status、CDC、仲裁分别自检；
3. **软件主机测试**：UDP seqlock/ACK/AUTH/resync、Buffer ownership、Display sticky status；
4. **联合编译**：Efinity 全流程通过，WNS/WHS 非负，BSP 与 bitstream 地址一致；
5. **DDR 回读**：UDP 与 BitBlt 都只写授权后台，前后哨兵和整个未授权前台不变；
6. **显示闭环**：720p RGB565 颜色正确，连续 VBlank 换帧无撕裂；
7. **异常注入**：丢包、重复包、错 offset、短帧、FIFO overflow、BRESP error、无 AUTH 均不上屏且可诊断；
8. **并发压力**：Display 持续扫描时交替执行 UDP/BitBlt，CPU 同时访问 DDR，统计欠流、错误、吞吐和 FPS；
9. **赛题 Demo**：同一场景下 CPU 与 FPGA Fill/Copy FPS 对比，再加入 Color Key；Alpha 作为后续增强。

---

## 9. 建议下一次会议只拍板这 8 项

1. 主线唯一权威接口文档及维护者；
2. RGB565 FORMAT=1、BitBlt V2.0、Display V3.0 是否正式回写 B 权威头文件；
3. UDP base=`0xF8100100`、VERSION=`0x00010000`、`LIVE_STATUS.bit1=AUTH_PENDING`；
4. APB clock 和未映射地址的 PSLVERR 行为；
5. 最终 SoC 顶层、DDR IP、HDMI 和约束的负责人；
6. UDP 第三写主的 AXI ID、仲裁结构和响应错误规则；
7. 联合 UDP 包中 slot/DBUF/AUTO_SWAP/AUTO 的拒绝或忽略规则；
8. RGB565 非 8 像素对齐矩形由硬件支持、CPU fallback，还是游戏层禁止。

这 8 项拍板后，A/B/C 才能分别写 RTL、公共头文件和驱动而不再发生“各自都正确，合起来不工作”。

---

## 10. 主要证据文件

- 赛题要求：`01_board/docs/contest/易灵思FPGA 创新设计赛道选题指南.pdf`
- 联合目标：`07_docs/interfaces/rgb565_720p_migration.md`
- B 历史基线：`07_docs/interfaces/bitblt_interface_v0.2.md`
- UDP V2 草案：`07_docs/interfaces/udp_frame_status_v2_draft.md`
- A 对 UDP V2 的实现答复：`07_docs/interfaces/udp_frame_status_v2_a_response.md`
- 当前问题清单：`07_docs/interfaces/rgb565_720p_open_issues.md`
- A 独立顶层：`rwj/udp_image_demo/fpga/rtl/top.v`
- A UDP 包解析：`rwj/udp_image_demo/fpga/rtl/ge/udp_hdr_parse.v`
- A Frame Status：`rwj/udp_image_demo/fpga/rtl/frame_status_apb.v`
- A PC 协议实现：`rwj/udp_image_demo/pc/udp_send_image.py`
- B BitBlt：`04_project/bitblt_accel/hw/rtl/bitblt_engine.v`
- B 显示控制/DMA：`04_project/bitblt_accel/hw/rtl/display_ctrl_axi.v`、`display_dma_axi.v`
- B 权威软件头：`04_project/bitblt_accel/sw/driver/*.h`
- C 协议状态：`jzy/riscv_game/driver/protocol_frozen.h`、`protocol_unfrozen.h`
- C 换帧状态机：`jzy/riscv_game/render/frame_swap.c`
- C 显示驱动：`jzy/riscv_game/driver/display_api.c`
