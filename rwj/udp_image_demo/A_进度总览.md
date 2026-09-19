# A 组进度与统一接口接入要求

- 角色：网络接收、UDP 帧完整性、授权写门控和联合平台接入
- 更新日期：2026-09-19
- 唯一协议：[`../../07_docs/interfaces/unified_fpga_interface_spec_v1.0.md`](../../07_docs/interfaces/unified_fpga_interface_spec_v1.0.md)
- 当前结论：**独立 UDP Demo 已验证；统一协议实现尚未完成，不能合入联合位流**

本文件只记录 A 的实现进度和待办，不再定义地址、寄存器或包格式。若本文与统一协议冲突，
必须修改本文或实现，禁止据此修改统一协议常量。

## 1. A 的正式责任边界

A 必须交付：

1. UDP 图像线协议 V1 的严格解析器；
2. 帧号、包号、实际 UDP 长度、偏移、边界、超时、FIFO 和 AXI 响应检查；
3. CPU 一次性授权到真实 DDR 写地址的硬门控；
4. UDP Frame RX V2.0 APB block 和稳定 snapshot；
5. 128-bit UDP AXI 写主机及与 B 顶层的明确接口；
6. 正常帧和全部异常场景的自检 testbench；
7. 与 B/C 联合完成端到端板测。

A 禁止在联合工程中：

- 根据网络 `slot`、`DBUF` 或 `active_slot^1` 计算物理地址；
- 直接修改显示前台或触发自动换帧；
- 把 UDP 收满字节但未检查偏移/边界/BRESP 的帧报告为成功；
- 维护另一份地址表、寄存器表或换帧协议。

## 2. 已完成且可保留的资产

| 项目 | 状态 | 可用于联合工程的范围 |
|---|---|---|
| RGMII/MAC/UDP 接收链路 | 独立 Demo 已运行 | 可迁移，必须替换包语义与完整性检查 |
| RGB565 1280×720 图片工具 | 已运行 | 像素转换可复用，发送包必须升级到统一 V1 |
| UDP→128-bit 数据组装 | 已实现 | 必须补实际 `pkt_len`、固定包长和异常排空 |
| DDR 写 Burst | 独立 Demo 已运行 | 必须接 B 的联合仲裁和授权基址 |
| BRESP 错误采集 | 已加入独立代码 | 联合版只有 OKAY 算成功，并补 BID/未完成响应检查 |
| Frame Status APB V1 原型 | RTL/TB 已提交 | 仅作迁移基础；统一要求为 V2.0，字段和错误覆盖更严格 |
| RISC-V/UART/DDR bring-up | 已验证 | 作为平台调试资产保留 |
| 封版独立 bitstream | 已备份 | 只能证明独立 Demo，不能证明联合协议 |

## 3. 当前不符合统一协议的地方

1. `top.v` 仍按旧 slot 计算地址，并包含 DBUF、自动换屏和按键切图语义。
2. `evt_write_enable/evt_write_base` 尚未接入真正的 UDP DDR 写状态机。
3. 当前包头 byte10 仍解释成 slot，没有检查统一协议的 `protocol_version=1`。
4. 解析器保留 `pkt_len` 但未使用，无法发现包头长度和真实 UDP 长度不一致。
5. 当前完整性没有覆盖固定 1440 包、连续 offset、重叠、越界、帧/包超时和主动 ABORT。
6. 当前 Frame Status 版本为 V1.0，缺少 V2.0 的 `OFFSET/BOUNDS/HEADER/TIMEOUT/ABORT`
   状态和 `RX_ACTIVE/WRITE_DRAINING` 实时位。
7. 当前授权 CDC 是 pending level + shadow，尚未证明 START 与消费在所有边界上恰好一次。
8. A 独立 DDR 控制器和 108 MHz 路径不得并入联合工程；联合数据面使用 B 的单一 DDR
   控制器和 100 MHz user_clk。

## 4. 必须按顺序完成的工作

### A-P0：线协议和 parser

- 把 header byte10 改为协议版本并强制为 1；旧 slot 字段停止参与任何逻辑。
- START/DATA/END 严格采用统一规范的固定字段和固定 1280 B DATA。
- 使用 MAC 的真实 UDP payload 长度校验 `16 + payload_len`。
- 错误后停止新 DDR 写并安全排空；实现 100 ms 包间和 2 s 整帧超时。
- 更新 PC 发送脚本；联合模式不得再暴露 `--slot/--dbuf/--auto-cycle/--no-swap`。
- 联合模式关闭旧 `--retry` 的立即重传；必须等待 C 重新 ARM 并给出 `UDP_READY`。

### A-P1：授权和 APB V2.0

- 正式 block 固定在 `0xF8100100–0xF81001FF`，时钟为 100 MHz。
- VERSION 改为 `0x00020000`，实现统一规范全部寄存器位。
- ARM 只接受非前台 FB_A/FB_B；pending/active 重复 ARM返回错误，不能静默丢弃。
- 实现 ABORT、无授权坏 snapshot、原子 snapshot、matching ACK 和 publish 优先。
- 64 KiB wrapper 对未映射访问必须完成并 `PSLVERR=1`，禁止 CPU 挂死。
- 创建唯一头文件 `04_project/udp_frame_rx/sw/udp_frame_rx_regs.h`。

### A-P2：联合 DDR 写通路

- `AWADDR` 只能由锁存授权基址加已校验 offset 产生。
- 每 Burst 最多 16 beat、不跨 4 KiB，WSTRB 固定全 1。
- 等全部 B 响应后才能 frame_done；非 OKAY、错误 BID 或 outstanding 非 0 都是 AXI_ERR。
- 向 B 提供清晰的 128-bit AXI master 端口和 100 MHz 同步接口，不携带独立 DDR IP。

### A-P3：验证

- parser 单测覆盖实际长度、版本、flags、序号、total、offset、边界。
- APB TB 覆盖授权、重复 ARM、ABORT、超时、SEQ 回绕、ACK/publish 和未映射访问。
- 联合仿真证明坏帧不换屏、无授权不产生 AW、前台永不被 UDP 写。
- 板测记录必须包含 VERSION、帧状态、实际前台、DDR 错误和至少 3600 帧结果。

## 5. A 的完成判据

只有以下项目全部成立，A 才能把“UDP 联合接入”标记完成：

- PC sender 与 parser 都通过统一线协议 V1 契约测试；
- UDP Frame RX 读回 V2.0，C 驱动通过全部错误注入；
- B 顶层中真实 AWADDR 受授权硬门控；
- 正常帧可由 C 换屏，任一坏帧保持旧前台；
- 联合压力测试无越界、无欠流、无总线挂死；
- 结果已写入 `07_docs/test_records/`。

## 6. 独立 Demo 说明

`udp_image_demo` 的旧 slot、按键、自动轮播和直接换屏功能可以继续保留用于独立演示，
但必须在代码/使用说明中标记 `STANDALONE_ONLY`。联合实现应放入正式工程或明确的迁移模块，
不得通过宏默认启用两套互斥语义。

封版位流不得删除或覆盖；它的作用是回退和比较，不是统一接口的实现证据。
