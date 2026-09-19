# B 组进度与统一接口接入要求

- 角色：联合 SoC/DDR 平台、BitBlt、Display DMA 与 HDMI
- 更新日期：2026-09-19
- 唯一协议：[`../interfaces/unified_fpga_interface_spec_v1.1.md`](../interfaces/unified_fpga_interface_spec_v1.1.md)
- 当前结论：**XRGB8888/1080p V0.4 历史路径已板测；RGB565/720p 联合版本尚未完成**

本文件只记录 B 的实现进度和待办。寄存器、版本、像素、地址、仲裁和换帧语义只允许由
统一协议定义。

## 1. B 的正式责任边界

B 必须交付：

1. 唯一联合 SoC 顶层和唯一 DDR3 控制器；
2. CPU、UDP、BitBlt、Display 的 AXI 仲裁和响应路由；
3. RGB565 BitBlt V2.0；
4. RGB565/720p Display V3.0、74.25 MHz 视频时序和 HDMI 输出；
5. `SYSTEM_AXI_A` 控制地址译码与 PLIC 源 30；
6. BitBlt/Display/Framebuffer 的唯一共享头文件；
7. 模块仿真、联合仿真、Efinity 时序和目标板证据。

B 禁止：

- 继续让联合位流按 XRGB8888/1080p 运行却报告为 RGB565 版本；
- 在 B 文档中重新定义 UDP 状态寄存器；
- 只接 CPU+BitBlt 两路写仲裁后宣称 UDP 已集成；
- 让 Display 或 UDP 自行绕过 C 的所有权状态机换帧。

## 2. 已完成的历史资产

当前 V0.4 历史实现已经验证：

- BitBlt AXI 控制、Solid Fill、Block Copy、XRGB8888 Color Key；
- 128-bit Burst、二维 stride、4 KiB 拆分、backpressure 和错误注入；
- CPU/BitBlt 写仲裁以及 CPU/BitBlt/Display 读仲裁；
- 1920×1080 XRGB8888 Display DMA、异步 FIFO、VBlank 双缓冲；
- PLIC 30 共享判源、32 帧并发和 3600 帧零欠流老化；
- Efinity 编译、时序和目标板显示。

这些结果可以作为回归基线，但其像素格式、显示时序和 VERSION 均不符合联合 V1.1。

2026-09-19 已对历史 `display_ctrl_axi.v` 做控制语义加固并加入仿真回归：显示开启时拒绝
几何/格式写，PENDING 时拒绝关闭显示和改写 NEXT_ADDR，请求接受时锁存 PENDING_ADDR 并
自动清旧 `SWAP_DONE`，历史固定模式的 stride 校验由“至少 7680”收紧为“等于 7680”。
这只是 V0.2/1080p/XRGB8888 回归基线加固，不代表 Display V3.0 已完成。

## 3. 当前不符合统一协议的地方

1. `framebuffer_layout.h` 仍定义 1920×1080、4 B/pixel、148.75 MHz。
2. `bitblt_regs.h` 仍公开 `0x00010004`，引擎按每 beat 4 个 32-bit 像素运行。
3. `display_regs.h` 仍只有 XRGB8888 格式，旧 VERSION 命名与编码规则不一致。
4. Display 复位几何、合法性检查和像素拆包仍是 1080p/XRGB8888。
5. 写仲裁器只有 CPU 和 BitBlt，没有 UDP 第三写主机。
6. 旧 Display AXI 写响应仍固定为 OKAY，尚未按 V3.0 对拒绝的 PENDING 写返回 `SLVERR`。
7. 旧显示初始化若向复位 FRONT=FB_A 再请求 FB_A，会因 NEXT==FRONT 失败。

## 4. 必须按顺序完成的工作

### B-P0：共享定义和契约

- 更新 `framebuffer_layout.h` 为 RGB565/720p 固定几何，但保留 8 MiB A/B slot 地址。
- `bitblt_regs.h` 增加并只默认使用 V2.0；`display_regs.h` 增加 RGB565=1 和 V3.0。
- 删除 C 的临时代持需求，让 C 直接引用 B 的唯一宏。
- 新增编译期断言：stride、帧大小、slot 容量、地址边界和版本值。

### B-P1：BitBlt V2.0

- Fill/Copy/Color Key 改为每 beat 8 个 RGB565 像素。
- FILL/COLOR_KEY 的 COLOR 只接受低 16 位，高 16 位非 0 必须报参数错误；COPY 忽略 COLOR。
- WIDTH 粒度改为 8；地址/stride 16 B 对齐，stride `>= width×2`。
- 非法参数在发出任何 DDR 请求前以 `DONE|ERROR` 完成。
- 保持源目标不重叠、4 KiB 拆分、ID/RESP/RLAST 和哨兵回归。
- 使用 checked-64/65-bit 计算完整矩形范围，拒绝溢出、跨区域、系统区和保留区访问；
  Display enabled 时通过统一前台侧带拒绝与当前前台相交的目标矩形。

### B-P2：Display V3.0

- 固定 1280×720、2560 B、FORMAT=1、74.25 MHz。
- RGB565 按统一位复制规则扩展到 RGB888。
- 按规范修复初始化、旧 SWAP_DONE、PENDING 重复请求和 enabled 配置写入语义。
- 接受 SWAP_REQUEST 时锁存 PENDING_ADDR，PENDING 期间拒绝改写 NEXT_ADDR。
- Reset：FRONT=FB_A、NEXT=FB_B、几何为 720p、FORMAT=RGB565、ENABLE=0。
- UNDERFLOW 输出黑色，连续扫描必须零欠流。

### B-P3：联合顶层和仲裁

- 采用一个 256 MiB DDR 配置和 100 MHz user_clk。
- 写侧扩为 CPU+BitBlt+UDP，读侧覆盖 CPU+BitBlt+Display。
- 已接收 Burst 保持所有权到 B/RLAST，W 通道不交错，所有请求方无饥饿。
- 接入 A 的 APB block、UDP 写 master，以及 Display→UDP/BitBlt 的 active FRONT 安全侧带。
- 固定 BitBlt/Display 的 64 KiB `SYSTEM_AXI_A` 窗口和错误响应，并按电平语义实现
  `plic_irq30 = bitblt_irq | display_irq`。

### B-P4：验证

- RGB565 BitBlt 全套 RTL 回归和 DDR 数据回读；
- Display 时序、像素颜色、PENDING_ADDR 锁存、VBlank、陈旧完成位和欠流仿真；
- UDP 未授权/前台变化/越界绝不出现在 DDR AW 端；
- BitBlt 溢出/非法区域/当前前台拒绝，以及 PLIC 30 双源电平中断回归；
- 四类 DDR 访问并发压力、Efinity 时序和 3600 帧真板老化。

## 5. B 的完成判据

- 三个 block VERSION 与统一协议精确匹配；
- C 不再需要 `protocol_frozen` 中的临时代持常量；
- 联合顶层只含一个 DDR 控制器并真实接入 UDP 第三写主机；
- RGB565 Fill/Copy/Color Key、720p 显示和 C 唯一换帧全部通过；
- 独立模块、联合仿真和目标板结果分别记录，不混写为同一种“通过”。
