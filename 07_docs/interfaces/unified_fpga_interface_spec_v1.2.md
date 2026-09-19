# FPGA 赛题二三方统一接口规范 V1.2

- 协议标识：`FPGA-IF-1.2`
- 冻结日期：2026-09-20
- 状态：**接口冻结；联合 RTL、驱动和位流尚未全部实现或板测**
- 适用角色：A（网络接收与平台接入）、B（BitBlt、显示与 SoC/DDR 集成）、C（RISC-V 软件与游戏）
- 唯一权威文档：本文件

本规范定义联合工程的数据格式、地址、寄存器、UDP 包、DDR 访问、缓冲区所有权、
错误恢复和验收门禁。任何独立 Demo、代码注释、个人进度文档或历史测试记录与本规范
冲突时，以本规范为准；但“规范已冻结”不代表相应实现已经完成。

文中的“必须”“禁止”是验收要求；“建议”是非强制实现建议。所有多字节网络字段使用
大端序，DDR 与 CPU 内存中的多字节像素使用小端序。

---

## 1. 系统目标与职责边界

联合系统的数据路径是：

```text
PC UDP → A: UDP 解析/完整性检查 → A: DDR 写主机 ┐
                                                    ├→ B: DDR 仲裁/DDR3
C: RISC-V → B: BitBlt 控制与数据主机 ─────────────┤
                                                    └→ B: Display DMA → HDMI

C: RISC-V → A: UDP Frame RX APB 状态/授权
C: RISC-V → B: BitBlt/Display SYSTEM_AXI_A 控制
```

职责严格划分如下：

| 角色 | 必须负责 | 禁止自行决定 |
|---|---|---|
| A | UDP 包解析、帧完整性、授权写门控、UDP DDR 写主机、帧快照 | 物理写地址、当前前台、自动换帧 |
| B | 唯一联合 SoC 顶层、DDR 控制器、AXI 仲裁、BitBlt、Display DMA、HDMI | 绕过 C 自动授权生产者 |
| C | 版本检查、后台所有权、生产者调度、状态消费、唯一换帧提交、超时恢复 | 让两个生产者并发写同一后台 |

联合工程中只有 C 软件可以写 Display 的 `NEXT_ADDR` 并提交 `SWAP_REQUEST`。
A 的旧 `slot/DBUF/AUTO_SWAP` 和按键直接切屏只能存在于独立 Demo，禁止进入联合顶层。

---

## 2. 固定系统参数

| 项目 | 冻结值 |
|---|---:|
| 有效分辨率 | `1280 × 720` |
| 刷新率 | `60 Hz` |
| 像素时钟 | `74.25 MHz` |
| 像素格式 | RGB565，`R[15:11] G[10:5] B[4:0]` |
| 内存字节序 | 小端；低地址保存像素低 8 位 |
| 每像素字节数 | `2` |
| stride | `2560 B` |
| 有效帧字节数 | `1,843,200 B`（`0x001C2000`） |
| DDR 物理容量 | `256 MiB`（`0x00000000–0x0FFFFFFF`） |
| DDR AXI 数据宽度 | `128 bit`，每 beat 16 B、8 个像素 |
| SoC/DDR/控制主时钟 | `100 MHz user_clk/sys_clk` |

HDMI 时序固定为：

| 参数 | 有效 | 前肩 | 同步 | 后肩 | 总计 |
|---|---:|---:|---:|---:|---:|
| 水平 | 1280 | 110 | 40 | 220 | 1650 |
| 垂直 | 720 | 5 | 5 | 20 | 750 |

RGB565 到 HDMI RGB888 的扩展必须为：

```text
R8 = {R5, R5[4:2]}
G8 = {G6, G6[5:4]}
B8 = {B5, B5[4:2]}
```

### 2.1 官方资料依据与适用边界

本规范的平台参数与赛题验收依据来自仓库 `resource/` 中保存的官方资料：

| 资料 | 本规范采用的事实 |
|---|---|
| [2026 易灵思创新设计赛道选题指南](<../../resource/易灵思FPGA 创新设计赛道选题指南(2).pdf>) | BitBlt 至少支持 Block Copy/Solid Fill、突发传输与 FIFO、双缓冲、最低 640×480@60，以及 CPU/硬件 FPS 实时对比 |
| [Ti60F225I3-V4 开发板说明](<../../resource/Ti60F225_DemoBoard_v4/TI60F225I3-V4 DEMO板软硬件设计说明-260813-1.pdf>) | 板载 DDR3 为 MT41J128M16JT-125、x16、2 Gb，即 256 MiB；板级 HDMI 能力高于本规范 720p60 目标 |
| [官方 Hard-JTAG BSP soc.h](../../resource/Ti60F225_DemoBoard_v4/08_ti60f225_soc_demo/09_Ti60F225_hardjtag_demo/par/ddr_demo_ti60/embedded_sw/soc/bsp/efinix/EfxSapphireSoc/include/soc.h) | CLINT 100 MHz、PLIC 源 30、APB/SYSTEM_AXI_A 窗口，以及 4 KiB 单路 D-cache/64 B cache line |
| [官方相机转 HDMI V6 DDR 参数](../../resource/Ti60f225_sc431hai2hdmi_v6/rtl/ddr3_controller/ddr3_parameter.vh) | DDR 用户 AXI 地址宽度 32 bit、数据宽度 128 bit；DDR core/AXI 时钟为 100 MHz |

资料的使用边界固定如下：

- `SYSTEM_DDR_BMB_SIZE=0xE0000000` 是 SoC 地址译码窗口，不是物理容量；所有联合模块仍只允许访问本规范定义的 256 MiB 物理 DDR。
- DDR 芯片/PHY 的 800/1600 Mbps 数据速率与 100 MHz 用户 AXI 时钟是不同层级参数，不得混写。
- 官方 Demo 中名为 `frame_buffer_V3` 的模块不是本规范的 Display V3.0。它使用地址 0、三缓冲、自动切换和 128-beat burst，只能作为厂商实现参考，禁止据此改变联合地址布局、双缓冲所有权或 burst 上限。
- 官方 Demo 未形成联合系统的 `CAL_DONE` 事务门控证明；本规范更严格的 `CAL_DONE=0` 时禁止 DDR 事务要求保持不变。
- Alpha Blend 属于赛题高阶挑战，不属于本版冻结 ABI；若增加硬件 Alpha 操作，必须另行走协议升级流程。

---

## 3. DDR 地址布局

| 区域 | 起始地址 | 结束地址 | 大小 | 访问规则 |
|---|---:|---:|---:|---|
| 系统/程序保留区 | `0x00000000` | `0x00FFFFFF` | 16 MiB | CPU 程序、数据、栈；图像硬件禁止写 |
| Framebuffer A | `0x01000000` | `0x017FFFFF` | 8 MiB | 仅前 `0x001C2000` 字节是有效帧 |
| Framebuffer B | `0x01800000` | `0x01FFFFFF` | 8 MiB | 仅前 `0x001C2000` 字节是有效帧 |
| 图片素材区 | `0x02000000` | `0x03FFFFFF` | 32 MiB | CPU/BitBlt 素材；不得直接扫描显示 |
| Scratch | `0x04000000` | `0x04FFFFFF` | 16 MiB | 测试和中间结果 |
| 保留区 | `0x05000000` | `0x0FFFFFFF` | 176 MiB | 未分配，禁止自行使用 |

强制规则：

1. 联合工程不得使用 A 独立 Demo 从地址 0 开始的 2 MiB 槽位。
2. UDP 只能写本次由 C 授权的 FB_A 或 FB_B 有效帧范围。
3. Display ENABLED 时，BitBlt 不得写当前 `FRONT_ADDR`；唯一例外是启动阶段确认
   Display 已禁用、DMA 未运行后，由 C 初始化复位前台 FB_A。
4. `base + offset` 这类单次加法必须使用至少 33 bit 中间值；BitBlt 矩形尾后地址
   `end_exclusive = base + (height - 1) * stride + width * 2` 必须使用 65 bit 中间值，或使用带逐步
   溢出检查的 64 bit 运算。任何中间步骤溢出、结果超出 DDR 物理范围或跨越下述单一
   合法区域，都必须在发出 DDR 请求前拒绝：FB_A 有效帧、FB_B 有效帧、图片素材区、
   Scratch。系统/程序保留区和未分配保留区禁止 BitBlt 访问；UDP 仍只能写本次授权的
   FB 有效帧范围。
5. 帧缓冲基址、素材区和 Scratch 的数字常量只允许出现在权威共享头文件与契约测试中。

---

## 4. 总线、时钟与复位契约

### 4.1 控制面

- BitBlt 和 Display 使用 32-bit `SYSTEM_AXI_A`。
- UDP Frame RX 状态使用 SoC APB slave 0 的 64 KiB 窗口。
- MMIO 访问必须为 32-bit 对齐访问。
- AXI 控制访问必须是单 beat：`AxLEN=0`、`AxSIZE=2`、`AxBURST=INCR`；写入必须
  `WSTRB=4'b1111`、`WLAST=1`。
- 非法传输、写只读寄存器、访问未定义寄存器必须完成总线事务并返回错误，禁止挂死总线。

`SYSTEM_AXI_A` 地址窗口固定为：

| Block | 地址窗口 | 窗口内未定义偏移 | 窗口外未映射地址 |
|---|---:|---|---|
| BitBlt | `0xE1000000–0xE100FFFF` | `SLVERR` | 由顶层返回 `DECERR` |
| Display | `0xE1100000–0xE110FFFF` | `SLVERR` | 由顶层返回 `DECERR` |

窗口内写只读寄存器、错误访问宽度、错误 Burst 属性或非法 `WSTRB` 同样返回 `SLVERR`；
顶层不得把未映射访问静默路由到任一 block。

### 4.2 DDR 数据面

- 数据宽度 128 bit，`AxSIZE=4`，只允许 `INCR` Burst。
- UDP 和 BitBlt 单个 Burst 最多 16 beat；Display 读 Burst 最多 64 beat。
- Burst 禁止跨越 4 KiB 边界。
- 一个已接收的写 Burst 从 AW 到 B 必须保持同一仲裁所有者；W 通道禁止交错。
- 一个已接收的读 Burst必须保持所有者直到 `RLAST`。
- 仲裁必须保证 CPU、UDP、BitBlt 和 Display 不饿死；Display 连续扫描必须通过零欠流压力测试。
- 只有 `RRESP/BRESP == OKAY (2'b00)` 是成功；`EXOKAY` 也按错误处理。
- 返回的 `RID/BID` 必须等于发起事务的 ID；错误 ID、错误 `RLAST` 或响应错误都必须终止本命令/本帧并上报。

联合写仲裁至少覆盖 CPU、BitBlt、UDP 三个主机；联合读仲裁至少覆盖 CPU、BitBlt、
Display 三个主机。具体 ID 数值不是软件 ABI，但仲裁器必须原样返回并按事务路由响应。

### 4.3 时钟域

- SoC、APB、BitBlt、UDP 帧状态/DDR 写状态机和 DDR 用户接口统一在 100 MHz 域。
- RGMII RX 为独立 125 MHz 域，只能通过异步 FIFO/握手进入 100 MHz 域。
- HDMI 像素域为 74.25 MHz，只能通过异步 FIFO 从 Display DMA 接收数据。
- 多 bit 状态禁止逐位两级同步；必须使用异步 FIFO，或“稳定数据 + toggle/握手”原子跨域。
- 每个异步域的复位可以异步置位，但必须在各自时钟域同步释放。
- `CAL_DONE=0` 时，UDP、BitBlt 和 Display 禁止发起 DDR 事务。

### 4.4 前台安全侧带

B 的 Display 控制器必须在 100 MHz `sys_clk` 域输出以下内部侧带，并直接连接到 UDP
授权门控和 BitBlt 参数检查；它不是软件 ABI，但属于联合顶层的强制硬件契约：

| 信号 | 宽度 | 复位值 | 语义 |
|---|---:|---:|---|
| `display_front_addr` | 32 bit | `0x01000000` | 与 Display `FRONT_ADDR` 同源、同周期更新 |
| `display_enabled` | 1 bit | 0 | 与 Display `STATUS.ENABLED` 同源 |

UDP 在 ARM 时必须比较 `AUTH_BASE` 与 `display_front_addr`，并在合法 START 消费授权时再次
比较；任一次相等都不得产生 DDR AW/W。ARM 阶段返回 APB 错误；START 阶段消费该授权并
发布 `AUTH_ERR` snapshot。BitBlt 在接受 START 前必须检查整个目标矩形；Display enabled
时只要目标范围与当前前台有效帧范围相交，就按非法参数完成且不得发出 DDR 请求。

侧带与消费者处于同一时钟域，不得另行逐位 CDC。C 仍负责编排所有权；这组硬门控用于在
软件错误、陈旧状态或异常控制写入时保证当前前台不被覆盖。

---

## 5. UDP 图像线协议 V1

### 5.1 网络参数与包头

联合版沿用当前默认网络参数：板卡 IPv4 `192.168.0.2`、UDP 端口 `8080`。
IP/MAC 地址以后可以配置化，但不得改变本节 UDP payload ABI。

每个 UDP payload 由 16 字节包头和可选图像数据组成。包头全部大端序：

| offset | 字段 | 宽度 | 规则 |
|---:|---|---:|---|
| 0 | `magic` | 2 B | 固定 `0xA55A` |
| 2 | `frame_id` | 2 B | 16-bit，按模 `2^16` 回绕 |
| 4 | `packet_idx` | 2 B | DATA 为 `0..1439`；START 为 0；END 为 1440 |
| 6 | `total_packets` | 2 B | 固定 `1440` |
| 8 | `payload_len` | 2 B | DATA 固定 `1280`；START/END 为 0 |
| 10 | `protocol_version` | 1 B | 固定 `1`；旧 `slot` 语义作废 |
| 11 | `flags` | 1 B | 见下表 |
| 12 | `byte_offset` | 4 B | DATA=`packet_idx×1280`；START/END=`0x001C2000` |
| 16 | `data` | N B | 仅 DATA 存在，RGB565 小端 |

`flags`：

| bit | 名称 | 规则 |
|---:|---|---|
| 0 | `START` | 仅 START 包为 1 |
| 1 | `END` | 仅 END 包为 1 |
| 2 | Reserved | 必须为 0；旧 `AUTO_SWAP` 作废 |
| 3 | `ACK_REQ` | 可选；START 与 END 必须一致 |
| 4 | Reserved | 必须为 0；旧 `DBUF` 作废 |
| 5 | Reserved | 必须为 0；旧 `AUTO` 作废 |
| 6–7 | Reserved | 必须为 0 |

一帧必须严格为：

```text
1 个 START
1440 个 DATA（每包 1280 B，packet_idx 连续 0..1439）
1 个 END
```

UDP 实际 payload 长度必须等于 `16 + payload_len`。解析器必须使用 MAC 提供的
真实长度进行核对，禁止只信包头中的 `payload_len`。

### 5.2 接收与错误规则

1. 只有成功消费一次 CPU 授权的合法 START 才能进入接收态。
2. 地址只能按 `latched_auth_base + byte_offset` 计算；任何网络字段都不能选择物理地址。
3. 每个 DATA 必须同时满足帧号一致、总包数一致、序号连续、偏移连续、长度正确、
   16 B 对齐且不越过 `base + 0x001C2000`。
4. 第一次发现错误后，停止为该帧发起新的 DDR 写；继续安全排空输入，直到 END、ABORT 或超时。
5. 收到活动帧之外的 DATA/END 时不得写 DDR；记录诊断错误即可。
6. 活动帧期间收到另一个 START：当前帧以 `HEADER_ERR` 失败并发布；新 START 不被接受，
   必须由 C 重新授权并由 PC 重发。
7. START 后 2 秒内未完成整帧，或连续 100 ms 没有合法下一包，按 `TIMEOUT_ERR` 结束。
8. END 到来后必须等待全部 AXI B 响应返回，才能发布快照或发送 PC ACK。
9. `FRAME_OK` 只在所有校验通过、实际字节数为 `0x001C2000`、全部 BRESP 为 OKAY时置位。

### 5.3 可选 PC ACK

`ACK_REQ=1` 时，A 可以在快照发布后发送 24 字节 ACK；它只用于上位机诊断，
C 的换帧决策必须以 APB snapshot 为准。ACK 丢失不能改变板内状态。

由于 CPU 授权是一次性的，这个 ACK **不表示下一帧授权已经就绪**。联合 V1 禁止 PC
仅收到坏帧 ACK 就立即自动重传；C 必须先消费旧 snapshot、重新 ARM，并通过串口/上层
控制流程明确给出 `UDP_READY` 后，PC 才能重发。正式网络流控留到后续协议版本。

| offset | 字段 | 宽度 | 规则 |
|---:|---|---:|---|
| 0 | `magic` | 2 B | `0xA55B` |
| 2 | `protocol_version` | 1 B | `1` |
| 3 | `header_len` | 1 B | `24` |
| 4 | `frame_id` | 2 B | 对应接收帧 |
| 6 | `status` | 2 B | `FRAME_STATUS[15:0]` |
| 8 | `rx_bytes` | 4 B | 与快照一致 |
| 12 | `expect_bytes` | 4 B | 与快照一致 |
| 16 | `checksum_sum` | 4 B | A 当前折叠和算法；仅诊断 |
| 20 | `checksum_xor` | 4 B | A 当前折叠异或算法；仅诊断 |

校验和对每个按内存顺序排列的 16 B 数据块计算：前 8 B 和后 8 B 分别按小端 `uint64_t`
解释；所有 64-bit 半块求和并按 `2^64` 回绕，最终
`checksum_sum=sum[31:0]^sum[63:32]`。同时异或所有 128-bit 数据块，最终将四个
32-bit lane 异或得到 `checksum_xor`。固定帧长已经是 16 B 倍数，不允许 ACK 计算时补零。

旧 24 字节 ACK 的 `slot/disp_slot` 格式不属于联合协议。

---

## 6. UDP Frame RX APB 接口

### 6.1 地址与版本

| 项目 | 冻结值 |
|---|---:|
| APB slave 0 总窗口 | `0xF8100000–0xF810FFFF` |
| UDP Frame RX block | `0xF8100100–0xF81001FF` |
| `UDP_FRAME_RX_VERSION` | `0x00020000`（V2.0） |
| MVP 通知方式 | Polling，无 UDP IRQ |

V2.0 相比 A 当前 V1 RTL 增加严格包头/偏移/边界/超时/中止语义，因此必须提升主版本，
禁止让旧模块以同一个版本号冒充兼容实现。

`0xF8100000–0xF81000FF` 和 `0xF8100200–0xF810FFFF` 未映射访问必须
`PREADY=1` 且 `PSLVERR=1`、读数据为 0；禁止通过 `PREADY=0` 挂起 CPU。
UDP block 内 `+0x34–+0xFC` 保留寄存器读 0、写忽略且不报错。

### 6.2 寄存器表

| 偏移 | 名称 | 属性 | 复位值 | 语义 |
|---:|---|---|---:|---|
| `+0x00` | `SEQ` | RO | 0 | snapshot 提交序号，每次发布加 1 |
| `+0x04` | `FRAME_STATUS` | RO | 0 | 当前 snapshot 状态 |
| `+0x08` | `FRAME_ID` | RO | 0 | 高 16 位恒 0 |
| `+0x0C` | `SLOT` | RO | 0 | 由实际基址派生：A=0、B=1；仅诊断 |
| `+0x10` | `BASE_ADDR` | RO | 0 | 硬件实际锁存并用于写入的地址；权威字段 |
| `+0x14` | `RX_BYTES` | RO | 0 | 通过 W 通道接收的图像字节数 |
| `+0x18` | `EXPECT_BYTES` | RO | 0 | 合法帧必须为 `0x001C2000` |
| `+0x1C` | `ACK_SEQ` | WO | 0 | 写已消费的 SEQ；读回 0 |
| `+0x20` | `LIVE_STATUS` | RO | 0 | 实时状态，非 snapshot |
| `+0x24` | `ERR_STICKY` | RO | 0 | 跨帧错误位图 |
| `+0x28` | `VERSION` | RO | `0x00020000` | IP-local 版本 |
| `+0x2C` | `AUTH_BASE` | RW | 0 | C 准备授权的 FB_A/FB_B 基址 |
| `+0x30` | `AUTH_CTRL` | WO | 0 | bit0 ARM；bit1 ABORT；读回 0 |

### 6.3 `FRAME_STATUS`

| bit | 名称 | 含义 |
|---:|---|---|
| 0 | `FRAME_OK` | bit1–11 全 0，帧可提交显示 |
| 1 | `SEQ_ERR` | DATA 序号或 frame_id 不连续/不一致 |
| 2 | `FIFO_OVF` | 数据、控制或 ID FIFO 溢出 |
| 3 | `AXI_ERR` | BRESP 非 OKAY、BID 错误或写事务异常 |
| 4 | `LEN_ERR` | 实际长度不等于期望长度 |
| 5 | `NO_DATA_ERR` | 声明长度为 0 或没有 DATA |
| 6 | `AUTH_ERR` | 无授权、非法授权或试图写前台 |
| 7 | `OFFSET_ERR` | offset 不连续、重叠或不对齐 |
| 8 | `BOUNDS_ERR` | 访问超出授权帧有效范围 |
| 9 | `HEADER_ERR` | 版本、flags、total、实际 UDP 长度或 START/END 结构错误 |
| 10 | `TIMEOUT_ERR` | 帧总超时或包间超时 |
| 11 | `ABORT_ERR` | 软件主动中止活动帧 |
| 12–31 | Reserved | 读 0 |

`FRAME_OK` 必须由完整判据计算，禁止由软件仅根据 `RX_BYTES` 推导。

### 6.4 `LIVE_STATUS` 与 `ERR_STICKY`

`LIVE_STATUS`：

| bit | 名称 | 含义 |
|---:|---|---|
| 0 | `CAL_DONE` | DDR 校准完成 |
| 1 | `AUTH_PENDING` | 一次性授权已 ARM、尚未被 START 消费 |
| 2 | `RX_ACTIVE` | 已接受 START，正在接收/排空一帧 |
| 3 | `WRITE_DRAINING` | END/错误后仍在等待 B 响应 |
| 4–31 | Reserved | 读 0 |

`ERR_STICKY[11:1]` 与 `FRAME_STATUS[11:1]` 同位累计，bit16 为 `ARP_MISS`
诊断；其余读 0。`ERR_STICKY` 只用于日志，禁止用它判断当前 snapshot 是否可显示。

### 6.5 授权、快照与 ACK

授权顺序：

```text
C 确认 AUTH_PENDING=0 且 RX_ACTIVE=0
→ 写 AUTH_BASE（只能是当前非前台的 FB_A 或 FB_B）
→ 写 AUTH_CTRL.ARM
→ 确认 AUTH_PENDING=1
→ PC 才可以发送 START
→ A 在 START 时恰好消费一次授权并锁存 BASE_ADDR
```

- pending/active 时再次 ARM、非法地址、当前前台地址或 `ARM|ABORT` 同写必须返回 APB 错误，
  且不得覆盖现有授权。
- 无授权 START：不写 DDR，发布 `AUTH_ERR` 坏帧 snapshot，SEQ 仍加 1。
- `ABORT` 在仅 pending 时撤销授权、不发布 snapshot；活动帧时停止新写、排空已发事务，
  发布 `ABORT_ERR` snapshot。
- 授权在 START 消费后立即失效；下一帧必须重新 ARM。

Snapshot 字段必须原子发布；软件使用 seqlock：

```c
do {
    s0 = RD(SEQ);
    /* 读取 FRAME_STATUS..EXPECT_BYTES */
    s1 = RD(SEQ);
} while (s0 != s1);
```

`SEQ` 按模 `2^32` 回绕，软件只能比较相等/不等，禁止使用大小比较。接口是
latest-snapshot，不是 FIFO；软件可能跳过中间 SEQ。

`ACK_SEQ` 仅表示“软件已消费该快照”：

- 只有写入值等于当前 `SEQ` 才清 `ERR_STICKY`；
- 不修改 snapshot、授权、生产者状态或显示状态；
- 坏帧同样必须 ACK；
- ACK 与新 snapshot 同周期时，新 snapshot 优先，ACK 丢弃。

---

## 7. BitBlt V2.0 接口

### 7.1 地址、寄存器与复位

基地址 `0xE1000000`，版本 `0x00020000`。

| 偏移 | 名称 | 属性 | 复位值 | 定义 |
|---:|---|---|---:|---|
| `0x00` | `CONTROL` | WO | 0 | bit0 START；bit1 CLEAR |
| `0x04` | `STATUS` | RO | 0 | bit0 BUSY；bit1 DONE；bit2 ERROR |
| `0x08` | `SRC_ADDR` | RW | 0 | COPY/COLOR_KEY 源物理地址 |
| `0x0C` | `DST_ADDR` | RW | 0 | 目标物理地址 |
| `0x10` | `WIDTH` | RW | 0 | 像素数 |
| `0x14` | `HEIGHT` | RW | 0 | 行数 |
| `0x18` | `SRC_STRIDE` | RW | 0 | 字节；FILL 忽略 |
| `0x1C` | `DST_STRIDE` | RW | 0 | 字节 |
| `0x20` | `COLOR` | RW | 0 | FILL/COLOR_KEY 使用 `[15:0]` RGB565，且 `[31:16]` 必须为 0；COPY 忽略 |
| `0x24` | `OPERATION` | RW | 0 | 0 FILL；1 COPY；2 COLOR_KEY |
| `0x28` | `VERSION` | RO | `0x00020000` | V2.0 |

命令流程：配置全部参数；COPY/COLOR_KEY 在写 START 前必须按 §9.1 对源范围执行
`dma_sync_for_device()`；随后确认 BUSY=0 并写 START，硬件原子锁存参数。完成时
BUSY=0、DONE=1；任何失败同时 ERROR=1。新 START 或 CLEAR 清旧 DONE/ERROR。
START 在 BUSY=1 时被拒绝并置 ERROR，不得破坏正在运行的命令。

非法参数必须在任何 DDR 请求之前失败，并产生 `DONE=1, ERROR=1`，避免软件等到超时。
CLEAR 不取消正在运行的命令；软件不得依赖 CLEAR 实现 abort。

### 7.2 数据约束与操作语义

- WIDTH、HEIGHT 必须非 0；WIDTH 必须是 8 像素倍数。
- 所有使用的地址和 stride 必须 16 B 对齐；stride 必须 `>= WIDTH×2`。
- 源矩形与目标矩形的完整尾后地址必须按 §3 的 65 bit/checked-64 规则计算，并各自完整落在
  一个合法区域内；不得依赖 32 bit 回绕、跨区域或跨 DDR 末端的结果。
- COPY/COLOR_KEY 源目标区域禁止重叠，不提供 memmove 语义。
- FILL/COLOR_KEY 的 `COLOR[31:16]` 非 0 属于非法参数，硬件必须在任何 DDR 请求前以
  `DONE=1, ERROR=1` 拒绝；COPY 不读取也不校验 COLOR。
- FILL：向目标矩形写 `COLOR[15:0]`。
- COPY：逐像素复制 RGB565，行尾 padding 不得修改。
- COLOR_KEY：源像素等于 `COLOR[15:0]` 时保留目标像素；不等时复制。透明像素对应的
  两个 WSTRB 位必须同时为 0；全透明 beat 仍可完成 AXI 写事务但 WSTRB 全 0。
- 任何 RRESP/BRESP/ID/RLAST 错误都使命令 ERROR。

V2.0 不支持非对齐矩形。C 对任意精灵坐标必须选择“整项 CPU 回退”或先在软件中拆分；
禁止截断坐标、扩大矩形或静默跳过边缘。MVP 默认采用整项 CPU 回退。

### 7.3 BitBlt 中断

BitBlt V2.0 不设独立 IRQ_ENABLE。`bitblt_irq` 是 100 MHz 域的高电平有效电平中断：

```text
bitblt_irq = STATUS.DONE
```

正常完成和错误完成都置 `DONE=1`，因此都产生中断；`ERROR` 只说明完成结果，不能单独产生
一个没有 DONE 的中断。软件写 CLEAR 或硬件接受下一条合法 START 时清 DONE，并在同周期
撤销 `bitblt_irq`。BUSY 时被拒绝的 START 只置 ERROR，不得制造伪完成中断或改变正在运行
命令的 DONE/BUSY 进程。

---

## 8. Display V3.0 接口

### 8.1 地址、寄存器与复位

基地址 `0xE1100000`，版本 `0x00030000`。

| 偏移 | 名称 | 属性 | 复位值 | 定义 |
|---:|---|---|---:|---|
| `0x00` | `CONTROL` | RW/命令 | 0 | bit0 ENABLE；bit1 SWAP_REQUEST；bit2 CLEAR |
| `0x04` | `STATUS` | RO | 0 | bit0 ENABLED；bit1 PENDING；bit2 SWAP_DONE；bit3 UNDERFLOW；bit4 ERROR |
| `0x08` | `FRONT_ADDR` | RO | `0x01000000` | 当前扫描地址 |
| `0x0C` | `NEXT_ADDR` | RW | `0x01800000` | 下一前台 |
| `0x10` | `WIDTH` | RW | 1280 | 只接受 1280 |
| `0x14` | `HEIGHT` | RW | 720 | 只接受 720 |
| `0x18` | `STRIDE` | RW | 2560 | 只接受 2560 |
| `0x1C` | `FORMAT` | RW | 1 | 0=XRGB8888 历史枚举；1=RGB565 当前格式 |
| `0x20` | `FRAME_COUNT` | RO | 0 | enabled 时每个 VBlank 加 1 |
| `0x24` | `UNDERFLOW_COUNT` | RO | 0 | 欠流次数 |
| `0x28` | `VERSION` | RO | `0x00030000` | V3.0 |
| `0x2C` | `IRQ_ENABLE` | RW | 0 | bit0 SWAP_DONE；bit1 UNDERFLOW；bit2 ERROR |

`CONTROL.bit0` 是电平值：每次写 CONTROL 都会更新 ENABLE，因此保持显示开启时的命令必须
同时带 `ENABLE=1`。CLEAR 清 SWAP_DONE、UNDERFLOW、ERROR 和 UNDERFLOW_COUNT，
但不取消 PENDING。

`display_irq` 同样是高电平有效电平中断：

```text
display_irq = (SWAP_DONE & IRQ_ENABLE[0]) |
              (UNDERFLOW & IRQ_ENABLE[1]) |
              (ERROR & IRQ_ENABLE[2])
```

清除相应粘滞状态或清除对应 IRQ_ENABLE 位后，中断必须在同一控制时钟域撤销。

### 8.2 初始化与换帧

初始化必须按以下顺序：

1. 读取 VERSION，必须精确等于 V3.0；不匹配时不得写任何配置。
2. Display 禁用时写 WIDTH、HEIGHT、STRIDE、FORMAT。
3. 读取复位 `FRONT_ADDR=FB_A`；初始化 FB_A 内容后写 `CONTROL.ENABLE`。
4. 禁止通过向当前 FRONT 提交 SWAP 来“初始化显示”。

换帧必须按以下顺序：

1. 确认 PENDING=0；写 `CONTROL=ENABLE|CLEAR` 清除旧完成状态。
2. 写 NEXT_ADDR，必须是 FB_A/FB_B 且不等于 FRONT_ADDR。
3. 写 `CONTROL=ENABLE|SWAP_REQUEST`。
4. 硬件接受请求时必须把 NEXT_ADDR 原子锁存到内部 `PENDING_ADDR`，自动清旧
   SWAP_DONE，并置 PENDING。
5. 只在 VBlank 起点令 FRONT_ADDR=PENDING_ADDR，然后清 PENDING、置 SWAP_DONE。
6. C 等到 SWAP_DONE 后必须再读 FRONT_ADDR；只有等于提交地址才算成功。

PENDING 时重复请求、配置非法、请求当前前台、enabled 时修改几何/格式，都必须置 ERROR
且不改变有效配置。PENDING 时禁止关闭显示；硬件应拒绝并保持 ENABLE。
PENDING 时写 NEXT_ADDR 也必须返回 `SLVERR`、置 ERROR，并保持 NEXT_ADDR/PENDING_ADDR
不变；已经接受的换帧目标在完成或复位前不可被重新定向。

UNDERFLOW 时输出黑色并累计计数，禁止重复随机旧像素。SWAP_DONE、UNDERFLOW、ERROR
都是粘滞状态，直到 CLEAR。

BitBlt 与 Display 完成中断共享 PLIC 源 30；顶层固定实现
`plic_irq30 = bitblt_irq | display_irq`，并按电平源接入 PLIC。ISR 必须读取两个 STATUS
判源、分别清除已处理状态，并在退出前确认两个内部 IRQ 均已撤销；禁止把任一内部 IRQ
转换为可能丢失的单周期脉冲。
UDP V1 MVP 使用轮询，不接入该中断。

---

## 9. 帧缓冲所有权状态机

C 是唯一所有权管理者。软件状态至少包含：

```text
IDLE → PRODUCING → READY → SWAP_PENDING → IDLE
                     └────────失败────────→ FAILED → RECOVER → IDLE
```

| 状态 | 所有权规则 |
|---|---|
| IDLE | FRONT 只读扫描；另一个 buffer 可分配 |
| PRODUCING | 后台独占给 UDP 或 BitBlt，一个时刻只能有一个生产者 |
| READY | 写入已完成，后台冻结，等待 C 提交换帧 |
| SWAP_PENDING | 两块 buffer 都禁止重新授权，等待 VBlank 和 FRONT 回读 |
| FAILED | 不猜测实际前台；重新读取 Display 状态和 FRONT 后恢复 |

UDP 流程：

```text
读取并确认 FRONT → 选择另一个 buffer → snapshot resync
→ AUTH_BASE + ARM → PC 发送 → 读取稳定 snapshot
→ 校验 FRAME_OK/BASE_ADDR/RX_BYTES/EXPECT_BYTES → ACK_SEQ
→ READY → Display swap → 校验 FRONT_ADDR → 旧前台变为可写后台
```

BitBlt 流程：

```text
读取并确认 FRONT → 选择另一个 buffer → START BitBlt
→ DONE && !ERROR → READY → Display swap
→ 校验 FRONT_ADDR → 旧前台变为可写后台
```

本版本一帧只允许一个生产者。UDP 背景后再由 BitBlt 叠加属于后续扩展；在所有权状态机
增加显式 handoff 并补测试之前，禁止通过绕过状态机实现。

失败帧绝不换屏。换帧超时后也不得立即复用任一 buffer，必须读取 `FRONT_ADDR` 判断硬件
实际停在哪里。

### 9.1 CPU cache 与硬件一致性

当前联合 SoC 已启用 4 KiB、单路、64 B cache line 的 D-cache。`fence rw,rw` 只保证
访问顺序，不能令 DMA/BitBlt 写入后留在 D-cache 中的旧副本自动失效。所有权移交必须通过
平台层的两个统一接口完成，业务层禁止直接散落 cache 指令：

- `dma_sync_for_device(addr, len)`：CPU 把自己写过的范围交给 UDP/BitBlt/Display 前调用；
  返回前必须保证 CPU 写缓冲内容已到达 DDR，再执行 `fence rw,rw`。厂商 BSP 的
  `soc_write_buffer_flush()` 是候选底层机制，但历史板测出现过不返回，必须先修复并以超时和
  DDR 可见性测试验证，禁止未经验证直接调用。若未来换成 write-back cache，实现还必须增加
  cache clean，但接口语义不变。
- `dma_sync_for_cpu(addr, len)`：UDP/BitBlt 写完且完成状态已经确认后、CPU 首次读取该范围前
  调用；实现必须向下/向上按 64 B cache line 对齐并执行逐行 invalidate，或使用全 D-cache
  invalidate，随后执行 `fence rw,rw`。

共享缓冲区在硬件持有期间 CPU 不得读写；CPU 重新获得所有权后才能执行
`dma_sync_for_cpu()` 并访问。共享范围应按 64 B 对齐；若调用者传入非整 cache line 范围，
平台同步实现必须避免破坏同一 cache line 中不属于共享范围的数据。不得把普通 `fence`、
MMIO 完成位或 `volatile` 当作 cache clean/invalidate 的替代品。

---

## 10. C 软件驱动约束

1. 启动时按 block base 读取三个 VERSION，必须分别精确匹配：
   - BitBlt `0x00020000`
   - Display `0x00030000`
   - UDP Frame RX `0x00020000`
2. 任一不匹配必须 fail-fast，打印读到值和期望值，不得“尽量运行”。
3. MMIO 只允许在对应驱动 `.c` 文件中出现；游戏和渲染层禁止直接访问寄存器。
4. 所有等待必须使用 100 MHz CLINT tick 的有限超时；禁止无限轮询。
5. UDP 驱动初始化和每次把后台授权给 UDP 时都要以当前 SEQ 重新建立基线，防止消费旧快照。
6. 判断 UDP 帧能否显示只能使用 snapshot；`ERR_STICKY` 只写日志。
7. `BASE_ADDR` 必须等于本次所有权状态机分配的后台，SLOT 不能用于计算地址。
8. 无论好帧坏帧，在完成处理后都写 matching ACK_SEQ；ACK 不等于换帧完成。
9. Display 请求前清旧 SWAP_DONE，请求后同时检查 SWAP_DONE 和 FRONT_ADDR。
10. BitBlt 参数不满足 16 B/8 像素约束时，V1 默认整项回退 CPU。
11. cache 一致性只能通过平台层 `dma_sync_for_device()`/`dma_sync_for_cpu()` 执行；
    CPU→硬件和硬件→CPU 两个方向都必须加入所有权状态机与板测。

---

## 11. 唯一定义、变更与文档纪律

### 11.1 权威代码定义

必须维护三组唯一寄存器头文件：

| Block | 唯一 C 头文件 | 唯一 RTL 定义文件/package |
|---|---|---|
| BitBlt | `04_project/bitblt_accel/sw/driver/bitblt_regs.h` | B 指定 |
| Display | `04_project/bitblt_accel/sw/driver/display_regs.h` | B 指定 |
| UDP Frame RX | `04_project/udp_frame_rx/sw/udp_frame_rx_regs.h` | A 指定 |
| DDR/Framebuffer | `04_project/bitblt_accel/sw/driver/framebuffer_layout.h` | B 指定 |

C 只能通过 include path 引用，禁止复制、软链或在调用点重写数字。当前尚不存在的 UDP
正式目录/头文件由 A 创建；创建后必须加入 C 的“唯一引用点”和“禁止硬编码地址”检查。

### 11.2 修改流程

协议变更必须同时完成：

1. 提交一份变更说明，列出旧值、新值、兼容性和迁移方法；
2. A/B/C 三方审阅；跨角色接口不得由单方直接修改；
3. 先修改本规范并提升版本，再修改共享头文件、RTL、驱动和测试；
4. 同一提交或同一合并序列中更新三方主 MD 的实现状态；
5. 通过契约测试和联合回归后才允许标记“已实现”；通过真板后才允许标记“已板测”。

版本编码为高 16 位主版本、低 16 位次版本。不兼容的字段、语义、复位值、地址或格式修改
必须提升主版本；只增加向后兼容能力可以提升次版本。IP VERSION 是 block-local，数值相同
不表示同一 IP，必须使用“block base + VERSION”识别。

个人 MD 只能记录进度和本角色待办，必须链接本规范，禁止复制完整寄存器表或另立协议草案。

---

## 12. 联合验收门禁

### 12.1 静态契约检查

- 文档和全部共享头文件的地址、版本、格式、几何完全一致。
- 全树不存在旧的 2 MiB slot、联合自动换帧、未授权 UDP DDR 地址计算。
- C 驱动/渲染层不存在硬编码 MMIO/Framebuffer 地址。
- 顶层只有一个 DDR 控制器，参数为真实 256 MiB；不存在 28/30 bit 地址宽度混用。

### 12.2 模块仿真

- UDP：正常帧、丢包、重复、乱序、错 frame_id/total/version/flags、实际 UDP 长度错误、
  offset 间隙/重叠/越界、无授权、重复 ARM、ABORT、两个超时、FIFO 溢出、BRESP/BID 错误、
  ACK/publish 同周期、SEQ 回绕、APB 未映射不挂死，以及 ARM 后、START 前前台变化时
  `AUTH_ERR` 且无 DDR AW/W。
- BitBlt：RGB565 Fill/Copy/Color Key、padding/哨兵、8/16/17 beat、4 KiB 边界、backpressure、
  非对齐、重叠、非法 op、总线错误、忙时 START、32 bit 回绕诱导值、矩形乘加溢出、跨合法
  区域、系统/保留区、当前前台相交，以及 DONE/CLEAR 对电平 IRQ 的置位和撤销。
- Display：720p 时序、RGB565 展开、初始化不自换帧、旧 SWAP_DONE 清除、重复请求、当前前台
  拒绝、PENDING 期间 NEXT_ADDR 写入拒绝且目标不变、VBlank 使用锁存 PENDING_ADDR 原子切换、
  欠流黑屏，以及三个 IRQ_ENABLE 位对应的电平 IRQ。
- C：版本 fail-fast、snapshot 撕裂重试、SEQ 回绕、旧 snapshot resync、坏帧 ACK、不用
  ERR_STICKY 判当前帧、所有权状态机、换帧超时恢复、非对齐 CPU 回退、checked-64 地址预检、
  PENDING 期间不改 NEXT_ADDR、共享 PLIC 30 双源清除，以及 CPU→硬件写缓冲同步和
  硬件→CPU D-cache 失效。cache 测试必须先预热同一 cache line，证明不会误读旧数据。

### 12.3 联合仿真与板测

通过顺序固定为：

1. CPU/BitBlt 写 RGB565 framebuffer，Display 720p 扫描；
2. 连续 A/B VBlank 换帧，确认无撕裂、无 stale SWAP_DONE；
3. UDP 授权写后台，坏帧保持旧前台，好帧由 C 提交换屏；
4. CPU + UDP + BitBlt + Display DDR 并发压力，检查公平性、错误和零欠流；
5. 使用同一分辨率、场景和对象数量，在屏幕上实时并列显示“纯 CPU 渲染”和“BitBlt
   硬件加速渲染”的 FPS；记录测试条件、平均 FPS、最低 FPS 和持续时间；
6. 运行至少 3600 帧，并记录 Efinity 时序、VERSION、串口状态和屏幕现象。

只有三层结论都通过才能写“联合完成”：模块测试通过、联合仿真通过、目标板通过。

---

## 13. 当前实现差距与交付责任

| 责任人 | 冻结后的必须交付 | 当前关键差距 |
|---|---|---|
| A | 新 UDP V1 parser、严格完整性、V2 APB、授权/ABORT/超时、UDP AXI master | 当前独立 Demo 仍使用 slot/自动换帧；V1 状态 RTL 未接真实写 FSM |
| B | RGB565 BitBlt V2、Display V3/720p、三写三读仲裁、唯一联合顶层 | 当前主线 RTL 是 XRGB8888/1080p，写仲裁只有 CPU+BitBlt |
| C | UDP V2 驱动、版本探测、所有权闭环、cache 同步、显示 stale 状态修复、CPU 回退 | UDP 协议已冻结，但当前仍使用旧命名的能力探测兼容层；现有文档/驱动仍有“无 D-cache、只需 fence”的错误假设 |
| 三方 | 共享常量检查、端到端仿真、联合位流和板测记录 | 当前没有通过本规范的联合 bitstream |

旧 XRGB8888/1080p 位流和 A 的独立 UDP Demo 可以作为回归资产保留，但不得用于证明本规范
已经实现。实现状态只在各角色主进度 MD 和测试记录中更新，本规范的冻结数值不得随进度变化。

---

## 14. 版本记录

| 版本 | 日期 | 内容 |
|---|---|---|
| V1.2 | 2026-09-20 | 依据官方赛题、板卡和 Demo 资料补充平台来源边界；确认当前 SoC 已启用 4 KiB D-cache，冻结 `dma_sync_for_device/cpu` 所有权交接语义；加入 CPU/硬件 FPS 实时对比验收；寄存器布局、线协议和三块 IP VERSION 不变 |
| V1.1 | 2026-09-19 | 澄清 checked-64/65-bit 地址安全、合法 DDR 区域、Display→UDP/BitBlt 前台侧带、PENDING_ADDR 锁存、SYSTEM_AXI_A 窗口及 PLIC 30 电平中断语义；寄存器布局和三块 IP VERSION 不变 |
| V1.0 | 2026-09-19 | 合并 RGB565/720p、DDR 布局、BitBlt、Display、UDP wire/APB、所有权、错误恢复和验收规则；取代此前全部接口草案/迁移稿/问题清单 |
