# 统一三方接口协议真板探测记录（未通过）

- 日期：2026-09-19
- 开发板：Ti60F225 Demo Board v4
- 目标规范：[`../interfaces/unified_fpga_interface_spec_v1.0.md`](../interfaces/unified_fpga_interface_spec_v1.0.md)
- 总结论：**当前不能宣称统一协议通过真板验证**

本记录区分三件事：板卡是否连接、现有独立 Demo 是否可运行、统一三方协议是否通过。
前两项即使成立，也不能替代第三项。

## 1. 验收目标

按统一规范，板端启动时必须能分别读回：

| Block | 基地址 | `VERSION` 地址 | 期望值 |
|---|---:|---:|---:|
| BitBlt | `0xE1000000` | `0xE1000028` | `0x00020000` |
| Display | `0xE1100000` | `0xE1100028` | `0x00030000` |
| UDP Frame RX | `0xF8100100` | `0xF8100128` | `0x00020000` |

只有三者精确匹配，且完成 UDP 写后台、BitBlt 写后台、VBlank 换页、错误帧不换页和
长时间并发测试后，才能标记“统一协议已板测”。

## 2. 板卡与调试链探测

### 2.1 USB 枚举：通过

板卡 FTDI 已枚举：

```text
0403:6011 FT4232H Quad HS USB-UART/FIFO
/dev/ttyUSB0 .. /dev/ttyUSB3
if02 -> /dev/ttyUSB2
```

### 2.2 JTAG TAP：通过；CPU 控制：失败

OpenOCD 能识别 FPGA TAP：

```text
JTAG tap: fpga_spinal.bridge tap/device found: 0x10660a79
[fpga_spinal.cpu0] Target successfully examined.
```

但随后无论普通 `halt` 还是 `reset halt` 都失败：

```text
Error: timed out while waiting for target halted
TARGET: fpga_spinal.cpu0 - Not halted
```

因此没有执行 MMIO 读取，三个 `VERSION` 均未获得真板读值。该现象与“当前板上是
A 独立 UDP/HDMI 位流、并非带可用 Sapphire 调试链的联合位流”一致。OpenOCD 的
`Target successfully examined` 不能单独作为 CPU 或三方 IP 可用证据。

## 3. 当前硬件产物检查

统一板测所需产物不完整：

| 产物 | 结果 |
|---|---|
| B 统一 overlay bitstream | 缺失：`04_project/bitblt_accel/hw/efinity/overlay/par/ddr_demo_ti60/outflow/ddr_demo_ti60.bit` |
| M2 板测 ELF | 缺失：`rendererM2Demo/build/rendererM2Demo.elf` |
| UDP Frame RX V2 权威头文件 | 缺失：`04_project/udp_frame_rx/sw/udp_frame_rx_regs.h` |
| A 独立 Demo bitstream | 存在，但不属于统一联合位流 |

A 独立位流：

```text
rwj/udp_image_demo/fpga/outflow/ddr3_hdmi_test.bit
SHA-256 75d34160cc28a35dbd455a3e42989109ff8d433b1f258cf9411a06dcd9360412
```

仓库当前 RTL/头文件也明确仍是旧版本：

| Block | 当前实现 | 统一要求 | 结论 |
|---|---:|---:|---|
| BitBlt | `0x00010004`，1920×1080 XRGB8888 | `0x00020000`，1280×720 RGB565 | 不兼容 |
| Display | `0x00020000`，旧显示协议 | `0x00030000` | 不兼容 |
| UDP Frame RX | `0x00010000` 原型 | `0x00020000` | 不兼容 |

所以即使找回旧 B 位流并成功运行，也只能复现旧 V0.4 结果，不能作为统一 V1.0 的验收。

## 4. 以太网探测

PC 有线口状态符合独立 Demo 的基本要求：

```text
enp3s0  UP
IP      192.168.0.3/24
carrier 1
speed   1000
duplex  full
```

使用仓库测试图发送旧协议的一帧：

```text
尺寸          1280x720 RGB565
帧字节数      1843200
DATA 包数     1440
PC sendto     1442/1442
发送间隔      0.5 ms
FPGA ACK      5 s 超时，未收到
```

随后主机邻居表显示：

```text
192.168.0.2 dev enp3s0 FAILED
```

这意味着板端没有按预期响应 ARP，PC 的 `sendto` 成功只表示数据交给了主机协议栈，不能
证明 UDP 已到达 FPGA。当前 `udp_send_image.py` 在 ACK 超时时仍返回退出码 0，也不能
被 CI 当成板测通过条件。

由于运行环境没有 `CAP_NET_ADMIN`/`CAP_NET_RAW`，无法临时写入静态邻居项或抓取
`enp3s0` 原始报文。这个权限限制只影响进一步定位，不改变“没有 ACK、不能证明收帧”
的结论。

## 5. 软件契约验证

### 5.1 通过项

- `test_contract.c` 在 RV32 交叉编译下通过，冻结常量和权威头文件的编译期断言成立。
- 在无空格临时路径运行 host 回归通过：
  - renderer 基线测试全部通过；
  - render API、BitBlt adapter、RGB565 几何与像素格式全部通过；
  - 换帧所有权状态机全部通过；
  - 板端测试逻辑的正常与故障注入场景 `10/10` 符合预期。

这些结果证明 C 侧当前的协议判定逻辑能拒绝错误版本和错误状态，但不证明 FPGA RTL 已经
实现该协议。

### 5.2 回归基础设施问题

仓库实际路径包含空格：

```text
/media/rwj/ZX1 2TB/fpga
```

直接运行聚合 Makefile 时，未转义的绝对路径会被 make 拆成两个目标并失败。将源码复制到
无空格临时路径后同一组 host 测试通过。正式自动回归必须修复 Makefile 的路径处理，或把
构建工作目录固定为无空格路径。

本机可用的交叉编译器较旧，默认 `-march=rv32im_zicsr_zifencei` 语法不能识别；契约编译
使用 `RV_ARCH=rv32im` 后通过。正式 BSP 构建应固定经验证的工具链版本，不应由机器环境
隐式选择。

## 6. 最终判定

| 检查层级 | 判定 |
|---|---|
| USB/FTDI 连接 | PASS |
| FPGA JTAG TAP | PASS |
| RISC-V 可 halt/load | FAIL |
| 三块 `VERSION` 真板读回 | NOT RUN |
| A 旧 UDP 链路 ACK | FAIL/INCONCLUSIVE（ARP 未建立） |
| C 软件契约与状态机 host 测试 | PASS |
| 统一三方端到端协议 | **FAIL：实现与联合位流尚不存在** |

## 7. 下一次可执行的联合板测入口条件

必须先完成以下事项，再继续真板验收：

1. A 完成 UDP 线协议 V1、授权写门控、Frame RX V2.0 和唯一寄存器头文件；
2. B 完成 RGB565 BitBlt V2.0、Display V3.0、1280×720 时序和统一 framebuffer layout；
3. B 将 A 的 AXI master、三块 MMIO、单一 DDR 控制器和 Sapphire SoC 集成为一个位流；
4. C 生成启动即检查三块 `VERSION` 的板测 ELF，任一不匹配必须非零退出/打印 FAIL；
5. 产出 bitstream manifest，至少记录 git commit、Efinity 版本、三块 VERSION、像素格式、
   分辨率、帧缓冲地址和 SHA-256；
6. 再执行正常帧、丢包/乱序/越界/超时、BitBlt、VBlank 换页以及至少 3600 帧并发测试。

在上述入口条件满足前，不应继续尝试用 A 独立位流、B 的旧 V0.4 位流或厂家 DDR Demo
读取统一地址；未映射访问可能直接挂住 CPU，并产生无法解释的假结果。
