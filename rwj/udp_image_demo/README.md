# udp_image_demo —— 千兆以太网 UDP 传图到 FPGA 并显示

电脑把 JPG/PNG 转成 RGB565，通过千兆以太网 UDP 分包发送到 Ti60F225 开发板，
FPGA 端把图片数据写入 DDR3，再从 DDR3 读出经 HDMI（1280×720）显示。

从图片转换、屏幕自适应、FPGA 编译烧录到 UDP 发送和故障排查的完整步骤，
请阅读 [`使用说明.md`](./使用说明.md)。

## 数据链路

```
[PC] 图片 -> RGB565 -> UDP 分包 --千兆网线--> [FPGA] UDP接收 -> DDR3 -> HDMI 1280x720
```

## 目录结构

```
udp_image_demo/
├── README.md
├── pc/                        PC 端（发送侧）
│   ├── img_to_rgb565.py       图片 -> RGB565 raw
│   ├── resize_bin.py           RGB565 raw 自适应到 1280x720
│   ├── udp_send_image.py      RGB565 -> UDP 分包发送
│   └── convert.sh             一键转 RGB565
└── fpga/                      FPGA 工程（Efinity）
    ├── rtl/top.v              顶层（UDP 接收 + DDR3 读写 + HDMI）
    ├── rtl/ge/udp_img_rx.v    UDP 图片接收模块（新写）
    ├── rtl/ge/mac/...         MAC/UDP/ARP/ICMP（来自 demo4）
    ├── rtl/ddr3_controller/   DDR3 控制器
    ├── rtl/hdmi/              HDMI 编码
    ├── ddr3_hdmi_test.xml     工程文件
    ├── ddr3_hdmi_test.peri.xml  引脚/时钟配置（含 GE 引脚 + clk_125m）
    ├── ddr3_hdmi_test.pt.sdc    时序约束（含 rxc 125MHz）
    └── build.sh               编译脚本
```

## UDP 分包协议（16 字节包头，大端）

| 偏移 | 字段 | 位宽 | 说明 |
|---|---|---|---|
| 0  | magic | 2B | 0xA55A |
| 2  | frame_id | 2B | 帧号 |
| 4  | packet_idx | 2B | 包号（从 0） |
| 6  | total_pkts | 2B | 总包数 |
| 8  | payload_len | 2B | 本包图片数据字节数 |
| 10 | reserved | 2B | 保留 |
| 12 | byte_offset | 4B | 本包数据在帧内字节偏移 |
| 16 | data | N B | RGB565 数据 |

- 每包 **1280 字节**数据（640 像素 = 半行，16 字节对齐，匹配 DDR3 128-bit AXI）
- 板子 IP 192.168.0.2，UDP 端口 8080

## 编译（fpga）

```bash
cd fpga
./build.sh
```

> 注意：不要自己设 EFINITY_HOME；脚本已清掉 ROS 污染的 PYTHONPATH。

生成 `fpga/outflow/ddr3_hdmi_test.bit`，用 Efinity Programmer 烧录。

## PC 端使用

```bash
# 1. 图片转 RGB565
cd pc
./convert.sh 图片.jpg 图片.bin

# 2. 发送到板子（电脑网卡 IP 需设为 192.168.0.3）
python3 udp_send_image.py 图片.bin --dry-run    # 先看分包
python3 udp_send_image.py 图片.bin              # 实际发送
```

已有 RGB565 `.bin` 可先自适应到屏幕大小。若旁边有转换时生成的
`.bin.json`，脚本会自动读取源分辨率：

```bash
# 默认 smart：最多拉伸 20%，其余区域补黑边
python3 resize_bin.py 输入.bin 输出_720p.bin

# 完全拉伸到全屏，不留黑边
python3 resize_bin.py 输入.bin 输出_720p.bin --mode stretch

# 没有 .bin.json 时手动指定源分辨率
python3 resize_bin.py 输入.bin 输出_720p.bin \
  --src-width 1920 --src-height 1080

python3 udp_send_image.py 输出_720p.bin
```

其他模式：`contain` 保持比例并补黑边，`cover` 保持比例并居中裁剪。

## 验证现象

- 烧录后 HDMI 先黑屏，DDR3 校准完成后显示黑场（framebuffer 全 0）
- 电脑发图后，屏幕实时显示收到的图片（1280×720）
- `b_led[0]` = DDR3 校准完成，`b_led[1]` = 显示启用
