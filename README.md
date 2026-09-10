# FPGA Contest — Ti60F225

易灵思 FPGA 创新设计赛题二团队开发仓库。

## 环境

- FPGA：Efinix Ti60F225
- 操作系统：Ubuntu 22.04
- Efinity：2026.1.132
- Efinity RISC-V IDE：2026.1.0.7

## 当前状态

| 模块 | 状态 | 说明 |
|---|---|---|
| LED/按键 Demo | 已验证 | Efinity 2026.1 编译、JTAG SRAM 下载及板上现象通过 |
| HDMI RX→TX | 已验证 | Efinity 2026.1 编译、JTAG 下载及 HDMI 环回显示通过 |
| HDMI TX 彩条 | 已验证（兼容修改） | 厂家异常时序在测试屏黑屏；修改为 1080p60 后显示通过 |
| RISC-V 基础功能 | 已验证 | GPIO、CLINT、DDR 16 MiB、UART Echo、FreeRTOS 已运行 |
| RISC-V AXI4 | 已验证（补全硬件） | 接入 2 KiB AXI RAM 后，官方读写比较与中断测试均通过 |
| RISC-V APB3 | 待修正硬件设计 | 官方软件已运行，厂家 Hard-JTAG 位流缺少示例要求的 LFSR 外设 |
| BitBlt 控制 MVP | 已验证 | 配置寄存器、状态转换及 PLIC 完成中断均已通过板测 |

## 协作规则

1. 厂家原始 Demo 不直接修改，工作副本放入 `03_bringup/`。
2. `04_project/` 是比赛正式工程。
3. 不提交安装包、厂家完整资料、构建缓存、日志和临时位流。
4. Efinity 的 `.xml`、`.peri.xml` 修改容易冲突，同一时间由一名成员负责同一工程配置。
5. 每个功能使用独立分支，例如 `feature/uart`、`feature/bitblt-fill`。
6. 合并前必须记录编译结果、WNS/WHS 和板上测试现象。

详细使用方法见 `07_docs/notes/FPGA开发使用手册.md`。
