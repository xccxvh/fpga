# B 组（FPGA 2D 加速器）进展与计划

- 更新日期：2026-09-16
- 当前分支：`feature/bitblt-mvp`
- 当前接口版本：`0x00010003`

## 1. 已完成

### 平台摸底和参考 Demo

- 验证 Ti60F225 的 Efinity 编译、JTAG 下载、RISC-V Hard-JTAG、UART 和 DDR 链路。
- 定位厂家 `axi4Demo` 的 SYSTEM_AXI_A 无从设备问题，并用支持 AW/W 独立握手的
  2 KiB AXI RAM 修复，读写比较和中断通过。
- 确认厂家 `apb3Demo` 与当前 SoC 硬件不匹配：软件期待 LFSR 外设，位流没有实现。
- 协助定位 HDMI TX 厂家异常时序问题；1080p60 修正版已能输出彩条。

### BitBlt 控制面

- 实现 32-bit AXI 寄存器 Slave，基地址 `0xE1000000`。
- 实现 START、BUSY、DONE、ERROR和PLIC完成中断。
- 实现 Fill/Copy 参数寄存器和 VERSION 寄存器。
- 寄存器回读、状态转换和中断均已实板验证。

### BitBlt 数据面

- 实现 128-bit AXI Solid Fill，支持二维 stride 和最多16-beat Burst。
- 实现 128-bit AXI Block Copy，加入16×128-bit内部 Burst 缓冲。
- 实现 CPU/BitBlt 两主机 DDR 读、写仲裁器。
- Burst 自动按行和4 KiB边界拆分。
- 检查零尺寸、非法操作、对齐、stride以及AXI响应/ID/RLAST错误。
- Solid Fill 与 Block Copy 均已通过真实 DDR 写入和 CPU 逐像素回读。
- 已建立 Icarus Verilog 自检回归，覆盖 Fill/Copy、Burst、4 KiB 边界、
  backpressure、非法参数、AXI错误以及读写仲裁。
- 控制接口自检覆盖寄存器复位/读写、START/BUSY/DONE/ERROR、中断、CLEAR、
  WSTRB、非法地址、非单拍访问以及AW/W不同到达顺序，全部通过。

## 2. 当前阶段判断

| 阶段 | B 组状态 | 尚缺内容 |
|---|---|---|
| M1 接口和骨架 | B部分完成 | A/C确认像素格式、内存布局和驱动API |
| M2 Solid Fill | B 数据面完成 | 与 A 的Framebuffer/HDMI链路联调；补目标区外哨兵检查 |
| M3 Block Copy | 核心链路完成 | 命令FIFO、双缓冲、显示换帧、性能对比和并发压力测试 |
| M4 Color Key | 未开始 | 等M3接口稳定后实现 |
| M5 Alpha Blend | 未开始 | 等Color Key与带宽数据后设计流水线 |

当前不能宣称 M2/M3 整阶段完成，因为屏幕显示、Double Buffer 和 CPU/FPGA
性能对比属于三人联合验收项；但 B 负责的 Fill/Copy 核心功能已经达到板测 MVP。

## 3. 下一步优先级

### P0：冻结接口并建立回归基线

1. B已在V0.2冻结XRGB8888、640×480@60、Framebuffer A/B及素材/Scratch地址。
2. B已冻结显示控制寄存器、VBlank换帧、共享PLIC 30和错误处理语义。
3. B已提供`bitblt_api.h`、`display_api.h`及内存布局头文件。
4. A/C需签收V0.2；如有异议必须在开始显示RTL/驱动前提出。

验收：A/B/C在接口V0.2上确认；不兼容修改必须提升VERSION并更新版本表。

### P1：补齐 B 模块正确性测试

1. 目标区前后设置哨兵，验证区域外数据不变。
2. 测试 1/2/4/15/16/17 beat、跨行、跨4 KiB边界和不同stride。
3. 测试非法操作、零宽高、未对齐地址、过小stride和忙时再次START。
4. 注入读写backpressure及错误响应，确认不会死锁且ERROR正确。
5. 持续扩展现有RTL Testbench，使关键测试不依赖每次手工上板。

当前结果：引擎、控制Slave和读写仲裁器自动回归全部通过。下一轮补随机长时间
压力。板级保护区、跨4 KiB和640×480整帧Copy已实板通过。

### P2：完成M2/M3系统联调

1. 与 A 对接 BitBlt DDR 地址和显示 Framebuffer 地址。
2. 用 Fill 在后台 Buffer 画多个矩形并显示。
3. 用 Copy 将大图搬到后台 Buffer。
4. 与 A/C 完成VBlank换帧，连续切换检查撕裂。
5. 压测CPU、BitBlt和显示同时访问DDR的仲裁与带宽。

验收：屏幕图案正确、区域外不变、连续换帧无明显撕裂。

### P3：满足基础赛题性能项

1. 明确赛题“内部FIFO”的验收口径，加入命令FIFO或可流水的数据FIFO。
2. 增加周期/字节计数，测量Fill和Copy有效吞吐率。
3. 评估当前“先读完整Burst再写”的气泡，必要时改为双缓冲ping-pong流水。
4. 与C在相同图像任务下完成CPU Copy与FPGA Copy耗时/FPS对比。

验收：Copy、Fill、Burst、FIFO、C驱动、Double Buffer和性能对比均有可复现证据。

### P4/P5：竞赛增强功能

- M4：Color Key、边界裁剪、连续Sprite命令。
- M5：Alpha Blend、定点取整规范、DSP利用、Sprite 60 FPS压力曲线。

在 P0–P3 完成前只做预研，不让增强功能破坏 Fill/Copy 回归基线。

## 4. 需要队友提供的信息

### A（平台/显示）

- 签收V0.2中的Framebuffer地址、XRGB8888和640×480时序。
- 按V0.2实现或共同评审显示读DMA、异步FIFO和VBlank换帧。
- 确认HDMI引脚/PLL可以并入当前DDR+RISC-V顶层工程。

### C（软件/游戏）

- 签收`bitblt_api.h`、`display_api.h`的参数顺序和错误码。
- 按XRGB8888小端及16 B行对齐提供素材转换工具。
- CPU参考Fill/Copy及逐像素比对程序。
- 性能对比的统一图像尺寸、任务和计时范围。
