# FPGA 开发使用手册

> 适用环境：Ubuntu 22.04、Efinix Ti60F225 开发板、Efinity 2026.1、Efinity RISC-V Embedded Software IDE 2026.1  
> 项目：易灵思 FPGA 创新设计赛题二  
> 文档版本：V1.0（2026-09-08）

> 三方联合接口以
> [`../interfaces/unified_fpga_interface_spec_v1.2.md`](../interfaces/unified_fpga_interface_spec_v1.2.md)
> 为唯一依据；官方资料索引见 [`../../resource/README.md`](../../resource/README.md)。本文只说明
> 开发工具和 bring-up 流程，不定义联合寄存器、DDR 布局或 framebuffer 所有权。

## 1. 这两个 IDE 分别做什么

### 1.1 Efinity

Efinity 用于 FPGA **硬件部分**的开发，主要工作包括：

- 编写和管理 Verilog/SystemVerilog 源码；
- 配置 PLL、DDR3、LVDS、GPIO 等 FPGA 接口；
- 分配器件引脚和设置 IO 电气标准；
- 设置时钟和时序约束；
- 综合（Synthesis）、布局布线（Place & Route）和时序分析；
- 生成 FPGA 配置文件 `.bit`；
- 通过 JTAG 将 `.bit` 临时下载到 FPGA。

只包含 LED、按键、HDMI、DDR3 等纯 RTL 逻辑的 Demo，通常只使用 Efinity。

### 1.2 Efinity RISC-V IDE

RISC-V IDE 是基于 Eclipse 的软件开发环境，用于 FPGA 内部 **Sapphire RISC-V 软核的软件部分**，主要工作包括：

- 编写 C/C++ 程序；
- 编译裸机或 FreeRTOS 工程；
- 生成 ELF/HEX/BIN 等软件映像；
- 通过调试器下载程序、设置断点、单步运行和查看寄存器。

RISC-V IDE 不能代替 Efinity。使用软核时通常先由 Efinity 生成并下载包含 RISC-V 处理器的 FPGA 硬件，再使用 RISC-V IDE 编译、下载和调试软件。

```text
Verilog / IP / 引脚 / 时序
            ↓
         Efinity
            ↓
 FPGA 硬件配置文件 .bit + BSP
            ↓
      RISC-V IDE（C/C++）
            ↓
       RISC-V 软件程序
```

## 2. 本机环境和目录

### 2.1 软件安装位置

```text
Efinity:
/home/user/efinity/2026.1

RISC-V IDE:
/home/user/efinity/efinity-riscv-ide-2026.1
```

### 2.2 项目资料位置

```text
比赛总目录:
/home/user/fpga_workspace/project

厂家原始 Demo（只作为母版保存）:
/home/user/fpga_workspace/local/vendor_original/Ti60F225_DemoBoard_v4

实际开发工作区（英文路径）:
/home/user/fpga_workspace/project
```

建议始终遵循以下规则：

1. 厂家原始 Demo 不直接修改；
2. 要测试的 Demo 先复制到 `/home/user/fpga_workspace/project/03_bringup/`；
3. 自己的比赛工程放在 `/home/user/fpga_workspace/project/04_project/`；
4. 工程路径和文件名尽量只使用英文、数字和下划线，不使用空格与中文；
5. `outflow/` 是构建输出，不要把它当作 RTL 源码目录。

## 3. 开发板连接和首次检查

### 3.1 连接

1. 将开发板放在绝缘、平整的桌面上；
2. 确认跳帽和供电方式与开发板手册一致；
3. 使用支持数据传输的 USB 线连接板卡和电脑；
4. 打开开发板电源；
5. 不要带电插拔排针、DDR3、扩展板或裸线。

### 3.2 Linux 检查命令

```bash
lsusb | grep -i '0403:6011'
```

当前竞赛板正常识别结果包含：

```text
0403:6011 FT4232H
```

USB 规则已经安装在：

```text
/etc/udev/rules.d/80-efx-pgm.rules
```

若 Efinity 找不到下载器，可依次尝试：

1. 关闭 Programmer；
2. 开发板断电；
3. 重新插拔 USB；
4. 开发板上电；
5. 再打开 Programmer 并刷新设备。

正常情况下不应使用 `sudo` 启动整个 Efinity。

## 4. Efinity 基本使用

### 4.1 启动 Efinity

在终端执行：

```bash
/home/user/efinity/2026.1/bin/efinity
```

如果从终端启动后需要使用 Efinity 命令行工具，可先加载环境：

```bash
source /home/user/efinity/2026.1/bin/setup.sh
```

该 `source` 只对当前终端有效，新开终端后需重新执行。

### 4.2 打开现有工程

Efinity 工程入口是工程目录中的主 `.xml` 文件，例如：

```text
LED_8bit_Test.xml
DDR3_MC.xml
```

在 Efinity 中选择 **File → Open Project**，然后选择主 `.xml` 文件。不要误选：

- `<project>.peri.xml`：Interface Designer 生成的接口描述；
- `debug_profile.wizard.json`：调试器配置；
- `outflow/` 下的 XML：构建中间文件；
- `.bit`：已经生成的配置文件，不是工程入口。

工程打开后先检查：

- Device 是否为 `Ti60F225`；
- Top Module 是否为正确顶层模块；
- RTL Source 列表是否完整且没有红色缺失项；
- Timing Model 是否与原工程一致；
- 工程路径是否为工作副本，而不是厂家原始 Demo。

### 4.3 认识主要界面

- **Project**：查看 RTL、约束、IP 和工程文件；
- **Dashboard**：控制综合、布局布线、位流生成等流程；
- **Messages/Console**：查看错误、警告和运行日志；
- **Results**：查看构建报告和输出文件；
- **Interface Designer**：配置 PLL、GPIO、DDR、LVDS、引脚和接口连接；
- **Programmer**：通过 JTAG 或 SPI 对 FPGA/Flash 编程。

### 4.4 修改 RTL

在 Project 面板中打开 `.v` 或 `.sv` 文件进行编辑，保存后重新编译。常见文件类型：

```text
.v / .sv       Verilog/SystemVerilog 源码
.vh / .svh     头文件和宏定义
.sdc           时钟和时序约束
.xml           Efinity 主工程
.peri.xml      FPGA 接口配置
.bit           JTAG 配置文件
.hex           常用于 SPI Flash 编程
```

修改顶层端口后，还必须同步检查 Interface Designer 中的端口和引脚，否则可能出现端口缺失或未约束错误。

### 4.5 使用 Interface Designer

只有在确实需要改变引脚、PLL、DDR3、LVDS 或其他器件接口时才修改 Interface Designer。

基本原则：

- 不凭感觉更改供电 Bank、电压或 IO Standard；
- 引脚号必须以本开发板原理图和厂家约束为准；
- 差分信号的 P/N 端必须成对且方向正确；
- HDMI、DDR3 等高速接口不要从空工程手工重建，优先继承厂家已验证 Demo；
- 修改后先运行接口检查，再运行完整编译；
- 保存前记录修改内容，便于回退。

### 4.6 完整编译

在 Dashboard 中运行完整流程。其主要阶段为：

```text
Synthesis
   ↓
Interface Generation / Interface Check
   ↓
Place and Route
   ↓
Timing Analysis
   ↓
Generate Bitstream
```

初学阶段建议使用自动流程，从头运行到 **Generate Bitstream**。若前面的 RTL、IP、引脚或约束有变化，不要只单独点击最后一步。

成功时应看到综合、接口、布局布线和位流生成均为 PASS，并在以下位置得到：

```text
<工程目录>/outflow/<工程名>.bit
```

命令行完整编译方式：

```bash
source /home/user/efinity/2026.1/bin/setup.sh
cd /path/to/project
efx_run.py project.xml --flow compile
```

把 `/path/to/project` 和 `project.xml` 替换成实际工程。命令行和 GUI 使用同一套工程配置，适合以后写自动构建脚本。

### 4.7 判断编译是否真正通过

不要只看是否生成了 `.bit`，还应检查：

- `Errors = 0`；
- 没有关键端口未分配；
- 器件型号和封装正确；
- 时序报告中 WNS、WHS 不为负；
- 资源使用没有超过器件容量；
- 警告与预期一致，没有新增的时钟、锁存器或多驱动警告。

常用报告位于 `outflow/`：

```text
<project>.err.log          错误
<project>.warn.log         警告
<project>.map.rpt          综合映射与资源
<project>.pinout.rpt       引脚分配
<project>.timing.rpt       最终时序
<project>.pt_timing.rpt    时序分析摘要
```

时序的简化判断：

- `WNS >= 0`：建立时间满足约束；
- `WHS >= 0`：保持时间满足约束；
- 任意一项为负：存在时序违例，不能因为生成了 `.bit` 就忽略。

## 5. 通过 JTAG 安全下载 `.bit`

### 5.1 SRAM 下载和 Flash 烧写的区别

| 模式 | 文件 | 是否掉电丢失 | 当前建议 |
|---|---|---:|---|
| JTAG 配置 FPGA SRAM | `.bit` | 是 | 调试阶段优先使用 |
| SPI Flash 编程 | 通常为 `.hex` | 否 | 明确需要固化时再使用 |

JTAG 下载到 SRAM 是目前运行 Demo 的默认方式。断电后该配置消失，开发板下次上电会重新加载原有 Flash 内容。

**不要把 Programmer 中的 `Program FPGA` 和 `Program Flash` 混淆。** 未核对 Flash 型号、模式、起始地址和文件格式前，不执行 `Program Flash`、Erase 或安全位操作。

### 5.2 使用 Programmer GUI

1. 保持开发板上电并连接 USB；
2. 在 Efinity 中打开 Programmer；
3. Programming Mode 选择 **JTAG**；
4. 点击刷新/扫描，确认扫描到 Titanium Ti60；
5. 选择当前工程 `outflow/` 下的 `.bit`；
6. 确认位流目标器件为 Ti60，与板上器件一致；
7. 点击 **Program FPGA**；
8. 等待完成信息，不要在编程过程中断电或拔线；
9. 根据 LED、串口或显示器现象验证功能。

### 5.3 命令行下载示例

当前板卡曾成功使用如下 JTAG 地址：

```text
ftdi://0x0403:0x6011:3:7/2
```

其中总线号和设备号可能在重新插拔后变化，因此每次应先扫描或在 GUI 中刷新，不能永久照抄 `3:7`。

命令格式：

```bash
/home/user/efinity/2026.1/pgm/bin/ftdi_pgm.sh \
  -m jtag \
  -u 'ftdi://0x0403:0x6011:BUS:DEVICE/2' \
  /absolute/path/to/design.bit
```

看到设备 ID、目标器件和 bitstream 路径均正确后才执行下载。

## 6. 当前已经验证的工程

### 6.1 LED Demo

工程：

```text
/home/user/fpga_workspace/project/03_bringup/01_led/LED_8bit_Test
```

入口：

```text
LED_8bit_Test.xml
```

位流：

```text
outflow/LED_8bit_Test.bit
```

状态：Efinity 2026.1 完整编译通过，JTAG SRAM 下载通过，板上 LED 现象已确认正确。

### 6.2 HDMI RX→TX Demo

工程：

```text
/home/user/fpga_workspace/project/03_bringup/06_hdmi_test/hdmi_rx2tx_loop_v19
```

入口：

```text
DDR3_MC.xml
```

位流：

```text
outflow/DDR3_MC.bit
```

连接：

```text
电脑/播放器 HDMI 输出 → 开发板 HDMI_RX
开发板 HDMI_TX → 显示器 HDMI 输入
```

建议输入为 `1920×1080 @ 60 Hz`。正常情况下 D3 为系统运行指示，D4 为 HDMI 输入时钟指示，显示器显示输入画面。

此旧版 Demo 在 Efinity 2026.1 中做了两项兼容处理：关闭工程里失效且 RTL 未启用的旧 Debugger 自动实例化，并删除未使用的旧 BSCAN 调试接口。这些修改只存在于工作副本，不影响 HDMI、DDR3、板外 JTAG或厂家原始 Demo。

## 7. RISC-V IDE 基本使用

> 本节是后续 Sapphire RISC-V Demo 的操作入口。目前已验证的 LED 和 HDMI 环回均为 FPGA RTL Demo，不需要使用 RISC-V IDE。

### 7.1 启动

```bash
/home/user/efinity/efinity-riscv-ide-2026.1/efinity-riscv-ide
```

首次启动会要求选择 Eclipse Workspace。建议使用英文路径：

```text
/home/user/fpga_workspace/local/riscv_workspace
```

Workspace 主要保存 IDE 元数据和导入的工程信息，不等同于 FPGA 的 Efinity 工程。

### 7.2 导入已有 BSP 示例

1. 先确认 Efinity 工程已经生成对应 Sapphire BSP；
2. 打开 RISC-V IDE 的 C/C++ Perspective；
3. 在 Project Explorer 选择 **Import projects...**；
4. 选择 Efinix/Efinity Makefile Project 导入向导；
5. 指向实际 BSP 目录；
6. 如为 FreeRTOS 工程，再指定匹配的 FreeRTOS Kernel 路径；
7. 选择需要的 sample project；
8. 可勾选创建 launch configuration；
9. 点击 Finish。

不要拿任意 BSP 与任意 FPGA `.bit` 混用。BSP 中的内存地址、外设基址和中断配置必须与当前 FPGA 硬件设计一致。

### 7.3 编译软件

在 Project Explorer 中右键工程：

1. **Clean Project**；
2. **Build Project**；
3. 在 Console 中确认编译结束且无 error；
4. 检查生成的 ELF/HEX/BIN 文件。

若修改了 Efinity 中的 RISC-V 外设或地址映射，应重新生成 BSP，并重新 Clean/Build 软件工程。

### 7.4 下载和调试

开始调试前必须确认：

- FPGA 已加载与该 BSP 匹配的 RISC-V 硬件位流；
- JTAG/调试接口连接正确；
- 目标内存类型和下载地址正确；
- 如程序依赖 UART，串口设备与波特率设置正确；
- launch configuration 指向当前生成的 ELF。

右键工程或 `.launch` 文件，选择 **Debug As → Debug Configurations...**，核对配置后进入 Debug。进入调试界面后可运行、暂停、单步、查看变量、内存和寄存器。

在第一个 RISC-V Demo 跑通前，不建议自行修改 OpenOCD 参数、CPU 配置或内存初始化方式。

## 8. 常见问题

### 8.1 Efinity 打不开工程

- 确认选择的是主 `<project>.xml`；
- 确认工程没有直接放在压缩包内；
- 确认所有文件已完整解压；
- 将工程复制到英文、无空格路径；
- 检查工程版本是否早于 Efinity 2026.1，旧调试配置可能需要迁移。

### 8.2 编译出现找不到源文件

- 查看 Project 中标红的文件；
- 检查工程是否引用了原作者电脑上的绝对路径；
- 检查相对路径层级是否因移动目录而变化；
- 不要只复制主 XML，应复制完整工程目录。

### 8.3 综合通过但布局布线失败

重点检查：

- 顶层端口与 `.peri.xml` 是否一致；
- 是否有未分配或重复分配的引脚；
- IO Standard 与 Bank 电压是否匹配；
- 时钟是否正确定义；
- 是否启用了工程中不存在的 Debugger/JTAG 调试实例；
- 器件型号、封装和 Timing Model 是否正确。

### 8.4 Programmer 找不到板卡

```bash
lsusb | grep -i '0403:6011'
```

- 没有输出：检查数据线、USB 口、电源和开发板开关；
- 有输出但 Programmer 看不到：关闭可能占用 FTDI/JTAG 的程序，重新插拔并刷新；
- 不要同时启动两个 Programmer 或多个调试会话争用同一 JTAG；
- 检查 `/etc/udev/rules.d/80-efx-pgm.rules` 是否存在。

### 8.5 下载成功但现象不对

- 再次确认下载的是当前工程最新生成的 `.bit`；
- 查看 `.bit` 修改时间，避免下载旧文件；
- 检查板卡开关、按键和 HDMI RX/TX 是否接反；
- 确认输入分辨率、串口波特率等外部条件；
- 查看时序报告是否存在负裕量；
- 用 LED/串口逐级定位，不要一次修改多个模块。

### 8.6 断电后 Demo 消失

这是 JTAG SRAM 下载的正常现象。重新下载 `.bit` 即可。只有明确需要上电自动运行时，才在核对官方 Flash 流程后烧写 SPI Flash。

## 9. 推荐的日常开发流程

```text
从厂家 Demo 创建工作副本
        ↓
记录当前可运行基线
        ↓
一次只修改一个功能
        ↓
完整编译并检查 error/warning
        ↓
检查资源、引脚、WNS/WHS
        ↓
JTAG 下载到 SRAM
        ↓
观察 LED/串口/HDMI 并记录结果
        ↓
确认稳定后提交 Git
```

每次实验至少记录：

- 日期和操作者；
- 工程路径与 Git commit；
- Efinity 版本；
- 使用的 `.bit` 文件和生成时间；
- 接线方式；
- 测试输入与预期输出；
- 实际现象；
- WNS/WHS 与资源占用；
- 警告、问题和解决方法。

## 10. 下载前安全检查清单

- [ ] 工程来自厂家 Demo 或已验证工作副本；
- [ ] 目标器件为 Ti60F225；
- [ ] 引脚和 IO 电压没有未经核对的修改；
- [ ] 编译无错误，关键警告已检查；
- [ ] 时序没有负裕量；
- [ ] Programmer 模式为 JTAG；
- [ ] 选择的是 `.bit`，目标是 Program FPGA；
- [ ] 没有选择 Program Flash、Erase 或安全配置；
- [ ] 外设接线方向正确，板上没有短路风险；
- [ ] 下载过程中不拔 USB、不关电源。

## 11. 本机官方参考资料

Efinity 完整用户指南：

```text
/home/user/efinity/2026.1/doc/pdf/efinity-ug.pdf
```

Efinity Programmer 用户指南：

```text
/home/user/efinity/2026.1/doc/pdf/efinity-pgm.pdf
```

Efinity 时序收敛指南：

```text
/home/user/efinity/2026.1/doc/pdf/efinity-timing-closure.pdf
```

RISC-V IDE 用户指南：

```text
/home/user/efinity/efinity-riscv-ide-2026.1/APB225-Efinix-IDE.pdf
```

开发板的原理图、用户手册和厂家 Demo 应优先从以下目录查找：

```text
/home/user/fpga_workspace/project/01_board/docs
```

---

后续每跑通一个新 Demo，应在本手册“当前已经验证的工程”中补充工程路径、接线、正常现象、兼容性修改和已知问题。
