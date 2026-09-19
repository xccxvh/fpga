# riscv/ —— Sapphire RISC-V 程序开发

角色 A（系统平台与显示集成）的 RISC-V 侧工作目录。

> 本文记录 A 的 bring-up 环境和历史测试。涉及 DDR 布局、UDP APB、BitBlt/Display、
> framebuffer 所有权的内容，必须以
> [`../../../07_docs/interfaces/unified_fpga_interface_spec_v1.0.md`](../../../07_docs/interfaces/unified_fpga_interface_spec_v1.0.md)
> 为准。下文早期地址建议不能用于联合工程。

板子：Efinix Titanium Ti60F225，片上 Sapphire SoC（RV32IM，100 MHz，无 FPU/C 扩展）。

---

## 快速开始

```bash
cd riscv
./run.sh p1test              # 编译 projects/p1test 并上板运行，打印串口输出
./run.sh p1test --build-only # 只编译
UART=/dev/ttyUSB0 ./run.sh p1test   # 换串口（默认 ttyUSB2）
```

脚本会自己做完：激活工具链 → 准备编译树 → 同步源码 → 编译 → openocd 上板 → 抓串口。

---

## 目录结构

```
riscv/
├── run.sh                  一键 编译 + 上板
├── tools/
│   ├── openocd_ti60.cfg    openocd 配置（含三个坑的说明，改前必读）
│   └── cpu0.yaml           CPU 调试描述（iCache 配置），openocd 必需
└── projects/
    └── p1test/             P1：GPIO 寄存器读写验证
        ├── makefile
        └── src/
            ├── main.c
            └── userDef.h
```

---

## 怎么加一个新程序

```bash
cp -r projects/p1test projects/我的程序
# 改 projects/我的程序/src/main.c
# 改 makefile 第一行  PROJ_NAME=我的程序
./run.sh 我的程序
```

`makefile` 用 `${STANDALONE}/common/*.mk`，脚本会自动把工程放进
`/tmp/riscv_sw/soc/software/standalone/user/<名字>/`，那个相对路径正好对得上，
不用改任何东西。

---

## 硬件环境的关键事实

### 内存映射

| 地址 | 内容 |
|---|---|
| `0x00000000-0x00000FFF` | **空的**，地址译码里不存在，别往里写 |
| `0x00001000-0x10000000` | **DDR3，256MB，应用运行区**（`default.ld` ORIGIN=0x1000） |
| `0x10000000-0xE0000FFF` | ⚠️ 译码窗口内但**超出真实容量，会回卷**，别用 |
| `0xF9000000-0xF9000FFF` | RAM_A，**SPI flash bootloader 在这里** |
| `0xF8010000` | UART0（串口，对应 `/dev/ttyUSB2`） |
| `0xF8015000` | GPIO0 |
| `0xF8100000` | APB slave 0 —— **⚠️ 当前是哑模块，读永远返回 0**，见下 |

**DDR3 真实容量是 256MB**（`ddr3_parameter.vh`: `ADDR_WIDTH 28`）。SoC 的译码窗口
`SYSTEM_DDR_BMB_SIZE = 0xe0000000`（3.5GB）**只是地址译码范围，是虚的**，
超出 256MB 会回卷。已实测（见下）。

**应用本身就运行在 DDR 里** —— `0x1000` 是 DDR 窗口起点，不是片上 RAM。
所以能跑程序就说明 DDR3 控制器上电校准是成功的。

### 启动链（决定了调试流程）

CPU 复位向量是 **`0xF9000000`**（不是 0），那里是 SPI flash bootloader：

```
复位 → bootloader（RAM_A）→ 从 SPI flash 0x380000 拷 124KB 到 0x1000 → 跳转 0x1000
```

板上 SPI flash 是空的，所以 bootloader 每次都会用 **全 `0xFF` 把 0x1000 覆盖掉**。

**这就是 `run.sh` 里必须用 `reset halt` 的原因**——要抢在 bootloader 执行前接管 CPU：

```
reset halt  →  load_image  →  reg pc 0x1000  →  resume
```

顺序不能变，换成 `init` + `halt` 就会被 bootloader 冲掉。

### APB slave 0 是哑模块

`0xF8100000` 上挂的 RTL（`par/ddr_demo_ti60/src/Interrupt.v`，模块名 `apb3_top`）：

```verilog
assign apb_prdata = 32'h0;                                  // 读永远返回 0
32'h0 : if(factory_doWrite) _zz_sig <= apb_pwdata[0];       // 只写 1 bit
```

而且 `_zz_sig` 驱动的 `sig` 是**悬空内部线**，没接任何引脚。

厂商的 `apb3Demo` 期望的是个 LFSR 外设，和这份 RTL 完全不匹配，所以跑起来
必然读到 0 并打印 `Failed!`。**这不是 APB 没通**——`apb_pready=1`，总线周期
正常完成，只是上面没设备。

自己加 APB slave 时，照 `ddr3_example_top.v:471` 的例化写，但记住三条：
**读要返回真数据、地址要被正确译码、输出要接到真实引脚或可读回的地方**。

---

## 已完成

| 项目 | 状态 |
|---|---|
| 工具链（xPack GCC 10.2.0） | ✅ |
| 编译 / 链接 / 上板 | ✅ |
| UART 收发 | ✅ `/dev/ttyUSB2` @115200 |
| **P1：RISC-V 读写硬件寄存器** | ✅ `p1test` 全部通过 |
| **DDR 可用范围 + 可靠性** | ✅ `ddrtest` 全部通过 |

### ddrtest 结果

```
[1] 容量探测  0x00100000 - 0x10000000  步长 1MB
    255 个探针全部正确 → 0x10000000 以下都可用
[2] 位模式测试 @ 0x00200000
    连续1 坏 0/32   连续0 坏 0/32   交替 坏 0/4
[3] 地址写自身  16384 个字
    全部正确
*** DDR 全部通过 ***
```

**结论：1MB – 256MB 整段可放心用于素材区和 framebuffer。**

地址规划建议：程序占 `0x1000-0x26f0`，素材/帧缓冲从 `0x00200000`（2MB）往上排，
避开低 1MB。

### p1test 结果

```
GPIO0 base = 0xf8015000
  ENABLE   write=0x0000000e  read=0x0000000e   OK
  OUTPUT   write=0x00000000  read=0x00000000   OK
  OUTPUT   write=0x0000000e  read=0x0000000e   OK
  OUTPUT   write=0x00000002  read=0x00000002   OK
  OUTPUT   write=0x0000000c  read=0x0000000c   OK
  OUTPUT   write=0x0000000a  read=0x0000000a   OK
  INPUT  (pin state) = 0x0000000a
*** P1 PASSED ***
```

最后一行是额外证据：GPIO 是 inout 引脚，`gpio_getInput()` 读回的实际管脚电平
正好等于最后写入的值，说明数据真的到了管脚，不只是寄存器回环。

---

## 下一步

**P2：自定义 APB slave 渲染寄存器**——RISC-V 通过 APB 控制图形加速器。

需要改 RTL + 重编 bitstream。待定：加在 `demo/08` 参考工程里（安全）
还是直接加到 `udp_image_demo` 顶层（一步到位但要动封版工程）。

---

## 注意

- **`udp_image_demo/fpga/outflow/ddr3_hdmi_test.bit` 不得删除或覆盖**，
  那是封版的 UDP 图片 Demo，随时要能恢复。md5 `8799c9b13c056bae99014f52bd280dba`。
- 编译树在 `/tmp/riscv_sw/`，重启会丢，`run.sh` 会自动从厂商工程重建。
- 厂商参考工程在
  `/media/rwj/ZX1 2TB/FPGA2026/demo/08_ti60f225_soc_demo/09_Ti60F225_co_debug_demo/`
  （RTL、BSP、全部官方例程源码都在那）。
