# BitBlt/显示软硬件接口约定 V0.2

- 日期：2026-09-17
- 主要维护：B（FPGA 2D渲染加速器）
- BitBlt版本寄存器：`0x00010003`
- 状态标记：`已验证`、`已冻结待实现`、`待联调`

本文是A（平台/显示）、B（BitBlt RTL）、C（RISC-V软件）的接口基线。“已验证”
表示已有Ti60F225实板结果；“已冻结待实现”表示地址、位定义和软件语义不再随意
修改，但对应RTL/驱动尚未完成。任何不兼容修改必须更新版本记录。

## 1. 接口总表

| 接口项目 | V0.2统一约定 | 状态/责任 |
|---|---|---|
| 显示分辨率与刷新率 | 首版固定`640×480@60 Hz`：25.2 MHz像素时钟，水平800总像素，垂直525总行；BitBlt仍使用参数化宽高 | 已冻结待实现 |
| 像素格式与字节序 | XRGB8888、小端；C值为`0x00RRGGBB`，低地址依次存B、G、R、X；显示输出`R=word[23:16]`、`G=word[15:8]`、`B=word[7:0]` | 已冻结待实现 |
| 图像宽高与stride | WIDTH/HEIGHT单位为像素/行；SRC_STRIDE、DST_STRIDE单位为字节；width必须为4的倍数，stride必须16 B对齐且不小于`width*4` | 已验证 |
| DDR/Framebuffer布局 | 256 MiB物理DDR；Framebuffer A=`0x01000000`、B=`0x01800000`，各8 MiB；素材区=`0x02000000`/32 MiB；Scratch=`0x04000000`/16 MiB | 地址已冻结；显示读取待实现 |
| RISC-V→BitBlt | `SYSTEM_AXI_A`，32-bit AXI4 Slave，基地址`0xE1000000`；仅支持单拍、完整4-byte strobe | 已验证 |
| RISC-V→显示控制 | `SYSTEM_AXI_A`，32-bit AXI4 Slave，基地址`0xE1100000`；仅支持单拍、完整4-byte strobe | 已冻结待实现 |
| BitBlt数据接口 | 128-bit AXI4 Master，INCR Burst，`ARSIZE/AWSIZE=4`；每beat 16 B | 已验证 |
| Burst/缓冲 | 单Burst最多16 beat（256 B），自动按行和4 KiB边界拆分；Copy内部缓冲为16×128 bit | 已验证 |
| Double Buffer | BitBlt只写后台Buffer；DONE且ERROR=0后软件提交NEXT_ADDR；显示只在VBlank切换；SWAP_DONE后旧前台才可复用 | 已冻结待实现 |
| 中断 | BitBlt与显示共享PLIC源30；顶层OR，ISR读取两组STATUS判源 | BitBlt已验证；显示待实现 |
| 时钟/复位 | DDR主机和控制接口位于100 MHz `user_clk`域，低有效`ddr_rstn`；显示数据通过异步FIFO跨到25.2 MHz像素域 | 前半已验证；CDC待实现 |
| 素材格式 | 与Framebuffer相同的XRGB8888小端像素；逐行连续，stride 16 B对齐；X字节当前忽略 | 已冻结；C提供工具 |
| C驱动 | 阻塞式`bitblt_fill/copy`和`display_queue/wait_swap`；返回OK、EINVAL、EBUSY、ETIMEOUT、EHW；超时单位为100 MHz CLINT tick | API已冻结待实现 |

当前BitBlt一次只执行一条命令，没有命令FIFO；内部Burst缓冲不能算命令FIFO。
命令FIFO属于后续性能增强，不改变V0.2单命令寄存器语义。

## 2. BitBlt寄存器映射（`0xE1000000`）

| 偏移 | 寄存器 | R/W | 复位值 | 定义 |
|---:|---|---|---:|---|
| `0x00` | CONTROL | W | `0` | bit0 START；bit1 CLEAR；其余为0 |
| `0x04` | STATUS | R | `0` | bit0 BUSY；bit1 DONE；bit2 ERROR |
| `0x08` | SRC_ADDR | R/W | `0` | Copy源DDR字节地址；Fill忽略 |
| `0x0C` | DST_ADDR | R/W | `0` | 目标DDR字节地址 |
| `0x10` | WIDTH | R/W | `0` | 每行像素数 |
| `0x14` | HEIGHT | R/W | `0` | 行数 |
| `0x18` | SRC_STRIDE | R/W | `0` | Copy源每行字节数；Fill忽略 |
| `0x1C` | DST_STRIDE | R/W | `0` | 目标每行字节数 |
| `0x20` | COLOR | R/W | `0` | Fill的XRGB8888像素值；Copy忽略 |
| `0x24` | OPERATION | R/W | `0` | `0=FILL`，`1=COPY`，其他非法 |
| `0x28` | VERSION | R | `0x00010003` | BitBlt RTL/接口版本 |

寄存器写必须使用`WSTRB=4'b1111`。`AWLEN/ARLEN`非零、写未定义地址或BUSY时
再次START均置ERROR。

## 3. 显示控制寄存器（`0xE1100000`，待实现）

| 偏移 | 寄存器 | R/W | 定义 |
|---:|---|---|---|
| `0x00` | CONTROL | W | bit0 ENABLE；bit1 SWAP_REQUEST（写1脉冲）；bit2 CLEAR（写1脉冲） |
| `0x04` | STATUS | R | bit0 ENABLED；bit1 SWAP_PENDING；bit2 SWAP_DONE；bit3 UNDERFLOW；bit4 ERROR |
| `0x08` | FRONT_ADDR | R | 当前正在扫描的Framebuffer地址 |
| `0x0C` | NEXT_ADDR | R/W | 下一帧待切换Framebuffer地址 |
| `0x10` | WIDTH | R/W | 有效区宽度，首版写640 |
| `0x14` | HEIGHT | R/W | 有效区高度，首版写480 |
| `0x18` | STRIDE | R/W | 每行字节数，首版写2560 |
| `0x1C` | FORMAT | R/W | `0=XRGB8888`，其他值非法 |
| `0x20` | FRAME_COUNT | R | 每完成一帧扫描加1 |
| `0x24` | UNDERFLOW_COUNT | R | FIFO欠载次数，CLEAR时清零 |
| `0x28` | VERSION | R | 首版显示控制器为`0x00010000` |
| `0x2C` | IRQ_ENABLE | R/W | bit0 SWAP_DONE中断；bit1 UNDERFLOW中断 |

`SYSTEM_AXI_A`增加地址译码：`0xE1000000–0xE100FFFF`路由至BitBlt，
`0xE1100000–0xE110FFFF`路由至显示控制器，其他地址返回DECERR。当前位流尚未
加入该1-to-2控制互连，因此实现前禁止软件访问`DISPLAY_BASE`。

## 4. BitBlt命令与数据约束

1. 软件在BUSY=0时写入全部参数；CPU写过源数据后执行`fence rw,rw`。
2. 写CONTROL.START；硬件锁存参数并置BUSY，BUSY期间软件不得覆盖参数。
3. 完成后BUSY清零、DONE置位并产生中断。
4. 软件读取STATUS；ERROR=1时命令失败，不得提交换帧。
5. 下一条有效START或CONTROL.CLEAR清除DONE/ERROR。

约束如下：

- FILL/COPY的DST和DST_STRIDE必须16 B对齐。
- COPY的SRC和SRC_STRIDE也必须16 B对齐。
- WIDTH、HEIGHT非零；WIDTH为4的倍数；stride不小于`WIDTH*4`。
- Copy源、目标不得重叠；不提供`memmove`语义。
- Burst不超过16 beat且不跨4 KiB边界。
- `RRESP/BRESP`非OKAY、RID/BID错误或RLAST长度错误时置ERROR。
- 当前CPU只有4 KiB指令缓存，没有数据缓存；当前位流使用`fence rw,rw`即可。
  未来若启用数据缓存，CPU→BitBlt前必须clean，BitBlt→CPU后必须invalidate。

## 5. DDR内存布局

| 区域 | 起始地址 | 大小 | 格式/stride | 访问方 | 状态 |
|---|---:|---:|---|---|---|
| 系统/程序保留区 | `0x00000000` | 16 MiB | 程序、栈及未来堆 | CPU/JTAG | 已冻结 |
| Framebuffer A | `0x01000000` | 8 MiB slot | XRGB8888；首版stride 2560 B | 显示/CPU/BitBlt | 已冻结待联调 |
| Framebuffer B | `0x01800000` | 8 MiB slot | XRGB8888；首版stride 2560 B | 显示/CPU/BitBlt | 已冻结待联调 |
| 图片素材区 | `0x02000000` | 32 MiB | XRGB8888、16 B对齐 | CPU写、BitBlt读 | 已冻结待联调 |
| 测试/Scratch | `0x04000000` | 16 MiB | 非持久临时数据 | CPU/BitBlt | 已冻结 |
| 后续可分配区 | `0x05000000` | 176 MiB | 未定义 | TBD | 保留 |

板载`MT41J128M16JT-125`容量为256 MiB，对应`0x00000000–0x0FFFFFFF`。每个
8 MiB Framebuffer slot既可容纳640×480×4，也可容纳1920×1080×4，且基址
同时满足4 KiB和16 B对齐。

早期板测使用`0x01100000–0x0182C000`，会覆盖新Framebuffer布局，只能在显示
关闭时运行；新测试必须迁移到Scratch区。

## 6. 显示时序、DMA与换帧

首版扫描时序：水平有效640、前肩16、同步96、后肩48；垂直有效480、前肩10、
同步2、后肩33；HSync/VSync均低有效，像素时钟25.2 MHz。

显示读DMA在100 MHz `user_clk`域访问128-bit DDR AXI，单Burst不超过16 beat且
不得跨4 KiB；通过至少1024像素的异步FIFO跨到像素时钟域。FIFO低水位时显示
读通道优先，其他时间事务间轮询；仲裁器必须保持所有权到本次Burst响应结束。
欠载时当前像素输出黑色，并置UNDERFLOW和计数器，不能重复随机旧像素。

换帧顺序：

1. 软件读取FRONT_ADDR，只向另一个Framebuffer绘图。
2. 所有BitBlt命令DONE且ERROR=0后，写NEXT_ADDR。
3. 写CONTROL.SWAP_REQUEST；PENDING期间再次请求置ERROR。
4. 显示模块仅在VBlank起点更新FRONT_ADDR，随后清PENDING、置SWAP_DONE。
5. 软件确认SWAP_DONE且FRONT_ADDR正确后，旧前台才能成为新后台。

BitBlt与显示共用`SYSTEM_PLIC_SYSTEM_AXI_A_INTERRUPT=30`。顶层将两个IRQ做OR；
ISR分别读取BitBlt STATUS和显示STATUS判断来源，处理后再向PLIC完成应答。

## 7. C API和错误码

权威头文件：

- `04_project/bitblt_accel/sw/driver/bitblt_regs.h`
- `04_project/bitblt_accel/sw/driver/display_regs.h`
- `04_project/bitblt_accel/sw/driver/framebuffer_layout.h`
- `04_project/bitblt_accel/sw/driver/bitblt_api.h`
- `04_project/bitblt_accel/sw/driver/display_api.h`

API参数顺序和返回值以头文件为准。统一错误码：`0=OK`、`-1=EINVAL`、
`-2=EBUSY`、`-3=ETIMEOUT`、`-4=EHW`。任何等待都必须带CLINT tick超时；
不能用无期限死循环。中断只是唤醒机制，最终结果必须以STATUS为准。

## 8. 已验证证据与待办

已验证：BitBlt寄存器、BUSY/DONE/ERROR、PLIC中断、Fill/Copy DDR回读、保护区
哨兵、二维stride、实际跨4 KiB、不同Burst、AXI backpressure/错误、读写仲裁，
以及640×480整帧Copy约353.2 MiB/s实板吞吐率。

仍需实现/验证：SYSTEM_AXI_A 1-to-2译码、显示DDR读DMA、异步FIFO、640×480 HDMI
输出、VBlank双缓冲切换、共享中断、CPU/BitBlt/显示三方并发和长时间压力。

## 9. 版本记录

| 版本 | 日期 | 修改内容 | 提出/维护 | 确认 |
|---|---|---|---|---|
| V0.1 | 2026-09-16 | 根据Fill/Copy实板结果建立控制、状态和DDR数据面基线 | B | 历史版本 |
| V0.2 | 2026-09-17 | 冻结640×480时序、XRGB8888、DDR布局、显示寄存器、VBlank换帧、共享中断和C API | B | B已核对板卡/现有工程；A/C待签收 |
