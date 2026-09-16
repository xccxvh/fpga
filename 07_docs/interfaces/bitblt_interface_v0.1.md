# BitBlt 软硬件接口约定 V0.1

- 日期：2026-09-16
- 主要维护：B（FPGA 2D 渲染加速器）
- 接口版本寄存器：`0x00010003`
- 状态标记：`已验证`、`暂定`、`待 A/B/C 联调`

本文是 A（平台/显示）、B（BitBlt RTL）、C（RISC-V 软件）共同开发的接口基线。
其中“已验证”表示已有 Ti60F225 实板结果；“暂定”表示可以据此并行开发，但在
Framebuffer 联调前仍允许通过版本记录修改。

## 1. 接口总表

| 接口项目 | V0.1 统一约定 | 状态/责任 |
|---|---|---|
| 显示分辨率与刷新率 | BitBlt 使用参数化宽高，不绑定显示分辨率；首个系统联调目标建议 `640×480@60 Hz`，已有独立 HDMI TX `1920×1080@60 Hz` 输出验证 | 待 A/B/C 联调，A 冻结 |
| 像素格式与字节序 | 每像素 32 bit；建议软件与 Framebuffer 统一采用 XRGB8888、小端存储；BitBlt 当前把像素作为不透明 32-bit 数据搬运 | 暂定，A/C 确认通道顺序 |
| 图像宽高与 stride | WIDTH/HEIGHT 单位分别为像素/行；SRC_STRIDE、DST_STRIDE 单位为字节；当前 width 必须为 4 的倍数，stride 必须 16 B 对齐且不小于 `width*4` | 已验证 |
| DDR/Framebuffer 内存布局 | 板测临时源区 `0x01100000`、目标区 `0x01200000`；这两个地址不作为最终 Framebuffer A/B 地址 | 测试地址已验证；最终布局由 A 冻结 |
| RISC-V ↔ FPGA 控制总线 | `SYSTEM_AXI_A`，32-bit AXI4 memory-mapped Slave，基地址 `0xE1000000`；寄存器访问只支持单拍、完整 4-byte strobe | 已验证 |
| 命令字段 | OPERATION、SRC_ADDR、DST_ADDR、WIDTH、HEIGHT、SRC_STRIDE、DST_STRIDE、COLOR | 已验证 |
| START/BUSY/DONE/ERROR | START 是写 1 触发脉冲；BUSY 表示引擎执行中；DONE/ERROR 在控制接口中保持，下一次有效 START 或 CLEAR 清除；忙时 START 被拒绝并置 ERROR | 已验证 |
| 完成中断 | 引擎完成或因参数/AXI错误终止时产生 PLIC 完成中断；软件仍须读取 STATUS 判断 ERROR | 已验证 |
| DDR 数据接口 | 128-bit AXI4 Master，INCR Burst，`ARSIZE/AWSIZE=4`；每 beat 16 B，即 4 个像素 | 已验证 |
| Burst/缓冲 | 单 Burst 最多 16 beat（256 B），自动按行和 4 KiB 边界拆分；Copy 内部缓冲为 16×128 bit | 已验证 |
| 命令 FIFO | 当前一次只执行一条命令，没有命令 FIFO；内部 Burst 缓冲不能等同于最终命令 FIFO | 待 B 实现/确认赛题口径 |
| Double Buffer/换帧 | BitBlt 只写后台 Framebuffer；等待 DONE 后由软件请求换帧；显示模块只能在帧边界切换；收到完成确认后才能复用旧前台缓冲 | 协议暂定，A/C 实现 |
| 时钟和复位 | 控制、引擎和 DDR 仲裁当前位于 `user_clk` 域，使用低有效 `ddr_rstn`；当前 B 模块内部没有 CDC | 已验证；新增显示域由 A 负责 CDC |
| 素材格式 | 建议离线转换为与 Framebuffer 相同的连续 32-bit 小端像素；每行按约定 stride 对齐 | 暂定，C 提供工具 |
| C 驱动 | 写参数 → 写 START → 等中断或轮询 DONE → 检查 ERROR；必须设置超时；DDR 数据准备后执行 `fence rw,rw` | 基本流程已验证；正式 API/错误码由 C 冻结 |

## 2. 寄存器映射

| 偏移 | 寄存器 | R/W | 位宽 | 复位值 | 定义 |
|---:|---|---|---:|---:|---|
| `0x00` | CONTROL | W | 32 | `0` | bit0 START；bit1 CLEAR；其余保留为 0 |
| `0x04` | STATUS | R | 32 | `0` | bit0 BUSY；bit1 DONE；bit2 ERROR |
| `0x08` | SRC_ADDR | R/W | 32 | `0` | Copy 源 DDR 字节地址；Fill 忽略 |
| `0x0C` | DST_ADDR | R/W | 32 | `0` | 目标 DDR 字节地址 |
| `0x10` | WIDTH | R/W | 32 | `0` | 每行像素数 |
| `0x14` | HEIGHT | R/W | 32 | `0` | 行数 |
| `0x18` | SRC_STRIDE | R/W | 32 | `0` | Copy 源每行字节数；Fill 忽略 |
| `0x1C` | DST_STRIDE | R/W | 32 | `0` | 目标每行字节数 |
| `0x20` | COLOR | R/W | 32 | `0` | Fill 的 32-bit 像素值；Copy 忽略 |
| `0x24` | OPERATION | R/W | 32 | `0` | `0=FILL`，`1=COPY`，其他值非法 |
| `0x28` | VERSION | R | 32 | `0x00010003` | 当前接口/RTL版本 |

寄存器写必须使用完整 `WSTRB=4'b1111`。当前控制 Slave 只支持单拍访问；如果
AXI `AWLEN/ARLEN` 非零、写未定义地址或在 BUSY 时再次 START，接口置 ERROR。

## 3. 命令与状态时序

1. C 在引擎空闲时写入全部参数。
2. 如果 CPU 刚写过 DDR 源数据，C 在 START 前执行 `fence rw,rw`。
3. C 向 CONTROL.START 写 1。B 只在 `BUSY=0` 时接受命令。
4. B 拉高 BUSY并锁存参数；软件不得在 BUSY 期间覆盖本条命令参数。
5. 操作结束后 BUSY 清零，DONE 置位并产生中断。
6. C 读取 STATUS；ERROR=1 时本条命令失败，不得提交换帧。
7. 下一条有效 START 会清 DONE/ERROR；软件也可以写 CONTROL.CLEAR 主动清除。

当前 START/DONE 是控制模块内部脉冲，STATUS.DONE/ERROR 是软件可见的保持位。

## 4. 数据面约束

- FILL 和 COPY 都要求 DST、DST_STRIDE 16 B 对齐。
- COPY 额外要求 SRC、SRC_STRIDE 16 B 对齐。
- WIDTH、HEIGHT 均不得为 0；WIDTH 必须为 4 的倍数。
- stride 必须大于或等于 `WIDTH * 4`。
- COPY 的源、目标区域暂定不得重叠；当前不保证 `memmove` 语义。
- 每个读/写 Burst 不超过 16 beat，且不会跨越 4 KiB 地址边界。
- 当前一轮 COPY 先完成一个 Burst 的读取，再从内部缓冲写出该 Burst；读写未流水重叠。
- AXI `RRESP/BRESP` 非 OKAY、RID/BID 不符合预期或 RLAST 长度错误时置 ERROR。

## 5. 内存布局

| 区域 | 起始地址 | 大小 | 格式/stride | 访问方 | 状态 |
|---|---:|---:|---|---|---|
| Block Copy 板测源区 | `0x01100000` | 本次 1152 B 范围 | 80×3，stride 384 B | CPU写、BitBlt读 | 已验证，仅测试 |
| Block Copy 板测目标区 | `0x01200000` | 本次 1248 B 范围 | 80×3，stride 416 B | BitBlt写、CPU读 | 已验证，仅测试 |
| Framebuffer A | TBD | TBD | XRGB8888（暂定） | 显示/CPU/BitBlt | A 待分配 |
| Framebuffer B | TBD | TBD | XRGB8888（暂定） | 显示/CPU/BitBlt | A 待分配 |
| 图片素材区 | TBD | TBD | 32-bit像素 | CPU/BitBlt | A/C 待分配 |

## 6. 换帧规则

| 事项 | V0.1 约定 | 状态 |
|---|---|---|
| 后台 Buffer 选择 | 软件只能向当前非显示 Buffer 下发绘图命令 | 暂定 |
| 绘制完成 | 所有 BitBlt 命令 DONE 且 ERROR=0 | 暂定 |
| 换帧请求 | C 向 A 提供的显示控制寄存器提交后台 Buffer 地址/编号 | A 待定义寄存器 |
| 帧边界切换 | 显示模块只在 VBlank/约定帧边界改变扫描地址 | A 待实现 |
| 完成确认 | A 提供当前前台 Buffer 或 SWAP_DONE 状态 | A/C 待确认 |
| 旧 Buffer 重用 | 仅在收到换帧完成确认后作为新的后台 Buffer 使用 | 暂定 |

## 7. 已验证证据与待补测试

已验证：控制寄存器读回、BUSY→DONE、PLIC中断、Solid Fill DDR回读、Block
Copy 80×3/双 stride/240像素回读、16-beat Burst、Efinity全流程和板上运行。

仍需补测：保护区哨兵、实际跨4 KiB地址用例、不同Burst长度、AXI backpressure、
非法参数与ERROR、CPU/BitBlt并发访问、最大图像压力、吞吐率、Framebuffer显示和
双缓冲换帧。LED、UART、FreeRTOS等基础 Demo 不需要为本接口重复测试。

## 8. 版本记录

| 版本 | 日期 | 修改内容 | 提出/维护 | 确认 |
|---|---|---|---|---|
| V0.1 | 2026-09-16 | 根据 Fill/Copy 实板结果建立控制、状态和 DDR 数据面基线 | B | A/C 待确认显示格式、内存布局与驱动API |
