# 赛题二统一目标：RGB565 / 1280×720@60 Hz

- 决定日期：2026-09-18
- 适用对象：A组UDP接收/显示、B组BitBlt、C组RISC-V软件与素材工具
- 状态：**RGB565/720p、B组DDR布局、B组BitBlt/显示寄存器路径、软件唯一换帧提交者及UDP完成通知协议已选定；联合实现/板测尚未完成**

## 已确认的跨组数据约定

| 项目 | 统一目标 | 当前验证状态 |
|---|---|---|
| 像素 | RGB565，每像素16 bit；位段`R[15:11] G[10:5] B[4:0]` | A组UDP Demo采用；B组尚未迁移 |
| 内存字节序 | 小端：低地址为像素低8位，高地址为像素高8位；扫描按从左到右、从上到下 | 联合链路待验证 |
| 有效图像 | 1280×720，60 Hz | A组Demo采用；B组尚未迁移 |
| 紧凑stride | `1280×2=2560 B/行`，16 B对齐 | 联合链路待验证 |
| 单帧有效数据 | `2560×720=1,843,200 B`；128-bit DDR beat含8个RGB565像素 | 联合链路待验证 |
| HDMI时序目标 | 像素时钟74.25 MHz；水平`1280+110+40+220=1650`；垂直`720+5+5+20=750`，即60 Hz | 目标屏与新组合位流待验证 |

此处只冻结两项用户确认的跨组选择及其直接推导出的像素/帧数据量。
不得把旧`1920×1080 XRGB8888`位流、素材或软件程序当作新协议运行。
旧实现和实测记录保留在`bitblt_interface_v0.2.md`及测试记录中，作为可回退基线。

## 联合DDR布局（已选择；A/C需同步实现）

选择**沿用B组已板测的地址隔离**，暂不为节省容量而重排槽位：

| 区域 | 物理地址范围 | 约定用途 |
|---|---|---|
| 系统保留 | `0x00000000–0x00FFFFFF` | CPU程序、数据和堆栈；不得当图片槽 |
| Framebuffer A | `0x01000000–0x017FFFFF` | 8 MiB槽；实际只使用前1,843,200 B |
| Framebuffer B | `0x01800000–0x01FFFFFF` | 8 MiB槽；实际只使用前1,843,200 B |
| 图片素材 | `0x02000000–0x03FFFFFF` | 32 MiB；独立于扫描/绘图帧缓冲 |
| Scratch | `0x04000000–0x04FFFFFF` | 16 MiB；测试及中间结果 |
| 后续空间 | `0x05000000–0x0FFFFFFF` | 当前不分配 |

依据：B组当前SoC的linker把程序放在低地址`0x00001000`起始区域，旧
Framebuffer A/B和显示控制器都使用上表地址；沿用它们减少已验证部分的变更。
A组独立`udp_image_demo/fpga/rtl/top.v`则用`slot_base={8'd0,slot,21'd0}`，
把`0x00000000–0x00FFFFFF`分成8个2 MiB图片槽。**这两种布局冲突**：
不能把A组位流中的slot 0/1地址直接交给B组SoC，也不能在合并SoC后继续
向地址0写入图片。A组应将UDP写地址映射到上述Framebuffer后台，显示读取
同一个实际物理基址；原四槽按键切换若要保留，应把额外图片存入素材区，
由软件/BitBlt复制到后台后再切帧。2 MiB紧凑槽位是可选优化，不作为本次MVP
集成前置条件。此地址布局已选定，但A/B/C仍需把同一地址落实到linker、RTL、
驱动与发送侧，并做联合板测；不能把“布局已选”写成“合并位流已验证”。

## 联合控制寄存器（枚举已冻结；联合RTL待实现）

**沿用B组已板测的SYSTEM_AXI_A路径和原寄存器偏移**，不同时另起一套APB
寄存器协议。BitBlt为`0xE1000000`，显示控制为`0xE1100000`；两者经
控制地址译码共享SoC的SYSTEM_AXI_A，完成中断共享PLIC源30。关键偏移：

| 偏移 | BitBlt `0xE1000000` | 显示 `0xE1100000` |
|---:|---|---|
| `0x00` | CONTROL：START/CLEAR | CONTROL：ENABLE/SWAP_REQUEST/CLEAR |
| `0x04` | STATUS：BUSY/DONE/ERROR | STATUS：ENABLED/PENDING/SWAP_DONE/UNDERFLOW/ERROR |
| `0x08` | SRC_ADDR | FRONT_ADDR（只读） |
| `0x0C` | DST_ADDR | NEXT_ADDR |
| `0x10` | WIDTH（像素） | WIDTH=`1280` |
| `0x14` | HEIGHT（行） | HEIGHT=`720` |
| `0x18` | SRC_STRIDE（字节） | STRIDE=`2560` |
| `0x1C` | DST_STRIDE（字节） | FORMAT：`0=XRGB8888`、`1=RGB565`；联合工程固定写`1` |
| `0x20` | COLOR：**建议**低16位为RGB565 | FRAME_COUNT |
| `0x24` | OPERATION：`0=FILL,1=COPY,2=COLOR_KEY` | UNDERFLOW_COUNT |
| `0x28` | VERSION：RGB565版固定`0x00020000` | VERSION：RGB565版固定`0x00030000` |
| `0x2C` | — | IRQ_ENABLE |

`COLOR[15:0]`用于Fill和Color Key，`COLOR[31:16]`建议要求写0，避免新旧
驱动误配。BitBlt按16 B对齐、宽度8像素倍数、`stride>=width×2`检查；
128-bit AXI一次承载8像素。原START/BUSY/DONE/ERROR及VBlank换帧顺序不变。

格式与版本号最终约定如下；版本编码高16位为主版本、低16位为次版本：

```c
#define DISPLAY_FORMAT_XRGB8888  0u
#define DISPLAY_FORMAT_RGB565    1u
#define BITBLT_VERSION_RGB565    0x00020000u
#define DISPLAY_VERSION_RGB565   0x00030000u
```

RGB565改变像素宽度、stride、对齐和Color Key语义，属于不兼容升级，因此
BitBlt由V1.x升级为V2.0；显示控制器由现有V2.0升级为V3.0。未识别的FORMAT
必须拒绝并置ERROR。枚举和版本号已经冻结，但当前B组V0.4 RTL/位流仍返回
历史版本值，只有完成RGB565实现和验证后才允许返回上述新版VERSION。
A组文档提出的`0xF8100000` APB寄存器表是**另一份草案**；该地址虽见SoC
`soc.h`，当前B组BitBlt并未接到APB slave。BitBlt和显示不迁到这套APB表。
UDP接收器的完成通知使用SoC现有APB slave 0窗口中的
`0xF8100100–0xF81001FF`，与BitBlt/显示的SYSTEM_AXI_A寄存器物理隔离。
`0xF8100000–0xF81000FF`保留，当前不映射第二套BitBlt寄存器。A组负责APB
slave实现，C组通过32-bit MMIO访问；具体字段偏移以A/C对齐表为准。

## UDP完成通知与ACK协议（已冻结，联合RTL待实现）

- MVP采用**主循环轮询**，不接入PLIC源30。若后续确需中断，应优先评估
  独立`userInterruptA`/PLIC源16，不能直接并入BitBlt/显示共用的源30。
- `SEQ`为32-bit无符号完成序号，复位为0；每发布一份成功或失败的完整快照
  都递增，允许自然回绕。软件以`SEQ != last_seq`判断出现新快照；该接口只
  保证最新快照，不是事件FIFO，软件允许通过SEQ差值统计跳帧。
- `FRAME_ID`、`SLOT`、`BASE_ADDR`、`RX_BYTES`、`EXPECT_BYTES`及
  `FRAME_STATUS[7:0]`在`frame_done`发布时同拍锁存，必须始终属于同一SEQ，
  ACK不得修改这些快照字段。
- `LIVE_STATUS`独立于快照；其中`CAL_DONE`实时可读，即使尚未完成任何帧，
  软件也能查询DDR校准状态。实时位不得混入`FRAME_STATUS`。
- 快照只能在最后一个DDR写响应已经接收后发布；只有包序号/帧ID、字节数、
  FIFO状态正确且全部`BRESP=OKAY`时才能置成功。失败帧同样发布带错误信息
  的快照，但不得提交显示换帧。
- 软件向`ACK`写入已消费的SEQ。只有`ACK == 当前SEQ`时才清`ERR_STICKY`；
  不匹配写入必须忽略。ACK不改变SEQ、快照寄存器或LIVE_STATUS。这样旧ACK
  无法清除其后到达的新帧错误。
- 若帧接收域与APB时钟域不同，A组必须用稳定数据+握手完成整组快照跨域，
  不能逐字段独立同步。

C组使用seqlock读法：先读SEQ，再读取所有快照字段，最后重读SEQ；两次SEQ
不一致则整组重读。稳定后保存`last_seq`并写`ACK=SEQ`。渲染及换帧判断依赖
当前快照的成功/错误位，不依赖`ERR_STICKY`是否已清除。

## 单一换帧控制与缓冲区所有权（已选规则，联合RTL待实现）

**C组RISC-V软件是唯一提交者**：集成位流中，只有C软件通过显示控制器
`NEXT_ADDR`（偏移`0x0C`）和`CONTROL.SWAP_REQUEST`（`0x00` bit1）请求
切换。显示控制器只在VBlank更新`FRONT_ADDR`，软件必须检查`SWAP_DONE`
以及读回的`FRONT_ADDR`后，才可复用旧前台。A组旧`target_slot/active_slot`
按键/UDP自动切屏逻辑不得再直接改集成显示前台；按键切图应变成软件请求。

1. 软件先读取`FRONT_ADDR`，选另一个B组Framebuffer作为后台，并把该后台
   的写所有权**只授予一个生产者**：UDP或BitBlt。生产者开始前，确认该
   后台没有正在进行的接收、BitBlt命令或未完成的换帧。
2. UDP集成版由软件指定/授权实际物理后台地址，硬件在START时锁存；网络包
   自带slot或旧`active_slot ^ 1`不能覆盖软件授权。地址只允许B组A/B
   Framebuffer；正在扫描的前台不得被UDP写入。BitBlt同理只写后台，且
   不与UDP并发写同一后台。
3. A组向CPU提供**保持到软件确认的完成状态**，至少包含帧ID、实际写入基址、
   接收字节数、完成/错误标志。只有字节数等于1,843,200、包序号/帧ID正确、
   无FIFO溢出、全部DDR写响应已返回且`BRESP=OKAY`，才报告“完整可显示”。
   当前A组`frame_ok`没有检查`BRESP`，联合版必须补上；失败帧不得提交换帧。
4. 软件看到UDP完整可显示，或看到BitBlt `DONE=1 && ERROR=0`后，先确保
   CPU/DDR可见性，再写`NEXT_ADDR=后台基址`，随后写`SWAP_REQUEST`。软件
   在确认`SWAP_DONE`之前不得再次授权该后台写入；若切换失败或超时，
   保留原前台并保留错误状态供诊断。
5. 软件确认新前台地址后，原前台才转为可写后台；再通知生产者下一帧可开始。

UDP通知地址、轮询方式和ACK语义已冻结，但不能据此宣称现有RTL已经支持
软件协调。A/C仍需实现并验证CPU不会读到混合快照，且软件能够核对实际写入
基址与被授权的后台基址一致。

## B组迁移边界

当前BitBlt V0.4把一个128-bit beat解释为4个32-bit XRGB8888像素，
`COLOR`的Fill值和Color Key键值也按XRGB8888处理；当前显示DMA/像素拆包器
及控制器只接受1920×1080 XRGB8888。仅修改软件头文件中的宽高或像素宏
不会产生RGB565画面。新版本至少需要：

1. BitBlt Fill、Copy、Color Key按8个16-bit像素/beat处理，检查16 B对齐、
   `stride >= width×2`、宽度为8像素倍数；明确`COLOR[15:0]`为RGB565填充值/透明键，
   上16位保留。透明像素的两个`WSTRB`位必须同时为0。
2. 显示DMA按RGB565提取像素，并扩展到HDMI输出RGB888；建议逐通道位复制
   (`R8={R5,R5[4:2]}`、`G8={G6,G6[5:4]}`、`B8={B5,B5[4:2]}`)。
3. 显示控制器校验1280×720、2560 B stride及新格式值；视频时序、PLL与
   相关时钟约束改为74.25 MHz目标。新BitBlt/显示版本号应与V0.4区分。
4. C侧帧缓冲、素材打包、网络写入、测试图案和缓存同步全部使用同一RGB565
   小端布局；分别完成RTL仿真、Efinity时序和板端显示/DDR回读/UDP联合验证。

## 尚需A/B/C落实或确认

- 按已选DDR地址、SYSTEM_AXI_A寄存器及单一换帧规则同步A/B/C的RTL、
  linker、C头文件及PC发送脚本。
- A/C按已冻结的`0xF8100100–0xF81001FF`轮询快照协议实现RTL和C驱动，
  并将双方对齐表中的字段偏移同步到公共头文件。
- 确认A组UDP输入的行填充、端序、丢包处理及硬件写后台的仲裁方式。
- 确认A/B合并使用的DDR控制器配置、100 MHz SoC时钟与74.25 MHz像素时钟，
  以及AXI master ID分配；这些尚未由统一位流实测。
- FORMAT与VERSION枚举已经冻结；A/B/C需同步头文件和RTL。当前旧位流仍是
  历史版本，软件必须读取VERSION并拒绝不匹配的位流。

## 验收顺序

保留V0.4历史分支/位流不动；在独立迁移分支先做RGB565 Fill/Copy/Color Key
DDR回读及保护区检查，再做720p彩条和VBlank换帧，最后与UDP接收合并，
进行整帧、并发和零欠流板测。任何未执行的步骤不能标记为通过。
