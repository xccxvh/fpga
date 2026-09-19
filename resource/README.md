# 官方资料与参考 Demo 索引

本目录保存赛题、开发板和 Efinix 参考工程的本地副本。它们用于核对平台事实和赛题要求，
不是联合接口的第二份定义；联合工程唯一权威规范是
[`../07_docs/interfaces/unified_fpga_interface_spec_v1.2.md`](../07_docs/interfaces/unified_fpga_interface_spec_v1.2.md)。

## 直接用于 V1.2 的资料

| 资料 | SHA-256 | 用途 |
|---|---|---|
| `2026 FPGA竞赛赛题指南 -8.22(更正版).pdf` | `8a1417ebb30a2c7b67e2593c658e62d8bb5ed04a4b23ad7c9013bdaa79a04a0f` | 赛题二基础任务与高阶挑战 |
| `易灵思FPGA 创新设计赛道选题指南(2).pdf` | `c1d3c0b63a697650c047d524095ba02b1716d2219d33f8766c28a70b8cde7bd8` | Block Copy/Solid Fill、burst/FIFO、双缓冲和 CPU/硬件 FPS 对比要求 |
| `Ti60F225_DemoBoard_v4/TI60F225I3-V4 DEMO板软硬件设计说明-260813-1.pdf` | `62b97e2c3bb29c0f0b4e3e6b538ffa591836cb11e7b280aa7ac21b13063d5251` | MT41J128M16JT-125、x16、2 Gb/256 MiB、板级时钟和 YT8531SC |
| `Ti60F225_DemoBoard_v4/08_ti60f225_soc_demo/09_Ti60F225_hardjtag_demo/` | 目录，不以单一哈希标识 | SoC 地址窗口、PLIC 30、CLINT 100 MHz、4 KiB D-cache 与 BSP cache 操作 |
| `Ti60f225_sc431hai2hdmi_v6/` | 目录，不以单一哈希标识 | 32-bit AXI 地址、128-bit AXI 数据、100 MHz core/AXI 时钟和 `cal_done` 接口参考 |

## 使用边界

- 板载 DDR 物理容量是 256 MiB；BSP 的 `SYSTEM_DDR_BMB_SIZE=0xE0000000` 只是地址译码范围。
- 官方相机 HDMI Demo 的 `frame_buffer_V3` 与联合 Display V3.0 没有版本继承关系。其
  `START_ADDR=0`、`FB_NUM=3`、自动换帧和 `BURST_LEN=127` 不得带入联合工程。
- 官方 Demo 中“能运行”的复位或 `cal_done` 处理不能替代联合协议门禁；联合系统仍要求
  `CAL_DONE=0` 时 UDP、BitBlt、Display 均不得发起 DDR 事务。
- TinyML、Custom Instruction 和 DSP PDF 是扩展阅读，不定义赛题二的寄存器、地址、像素格式
  或 framebuffer 所有权。
- Alpha Blend 是高阶挑战。V1.2 只冻结 Fill、Copy 和 Color Key；硬件 Alpha 必须另行升级协议。

## 仓库管理

`Ti60F225_DemoBoard_v4` 约 3.1 GiB，不应在未确认托管策略前直接加入普通 Git 历史。团队需要
共享完整资料时使用 Git LFS、制品库或共享盘；普通 Git 至少保留本索引、来源说明和校验值。
