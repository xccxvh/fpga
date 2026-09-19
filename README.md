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
| BitBlt 控制与 Solid Fill | 已验证 | 配置寄存器、状态转换、PLIC 中断及 DDR Burst 写入均通过板测 |
| BitBlt Block Copy | 已验证（核心链路） | 128-bit AXI Burst 读写、二维 stride 和 240 像素逐项回读通过；显示/双缓冲尚未集成 |

## 协作规则

1. 厂家原始 Demo 不直接修改，工作副本放入 `03_bringup/`。
2. `04_project/` 是比赛正式工程。
3. 不提交安装包、厂家完整资料、构建缓存、日志和临时位流。
4. Efinity 的 `.xml`、`.peri.xml` 修改容易冲突，同一时间由一名成员负责同一工程配置。
5. 每个功能使用独立分支，例如 `feature/uart`、`feature/bitblt-fill`。
6. 合并前必须记录编译结果、WNS/WHS 和板上测试现象。
7. 测试代码依赖 `assert` 判定，测试构建禁止定义 `NDEBUG`——断言会被整体移除，测试将假通过
   （打印 `[FAIL]` 但不中止，退出码仍为 0）。CPU 渲染器测试见 `jzy/riscv_game/tests/`。

## 目录导航

| 目录 | 用途 |
|---|---|
| `01_board/` | 开发板、原理图、数据手册及厂家资料索引 |
| `02_learning/` | 学习和独立实验，不作为比赛正式实现 |
| `03_bringup/` | 厂家Demo工作副本及板级功能验证 |
| `04_project/bitblt_accel/` | B组BitBlt/显示正式工程与测试 |
| `05_benchmark/` | 性能、时序、资源利用率和可复现结果 |
| `06_demo/` | 经过板测后进入的最终演示程序 |
| `07_docs/` | 接口、进展、手册和板测记录；入口见`07_docs/README.md` |
| `08_team/` | 分工、周计划和团队协作文档 |
| `09_release/` | 发布清单、版本说明与校验值 |

`jzy/`和`rwj/`是队友工作区，各自维护；整理公共/B组文件时不得移动或批量修改。
本地`outflow/`、`work_*`、仿真波形和临时位流属于可再生产物，不进入Git，
也不应因为整理目录而直接删除。

详细使用方法见 `07_docs/notes/FPGA开发使用手册.md`，文档总索引见
`07_docs/README.md`。

赛题二软硬件基线见 `07_docs/interfaces/bitblt_interface_v0.2.md`，B 组当前进度与计划见
`07_docs/progress/B_role_progress_and_plan.md`。

团队联合目标与已选DDR/寄存器/换帧规则见
`07_docs/interfaces/rgb565_720p_migration.md`。当前各独立Demo不等于联合位流已验证。
