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
| BitBlt/Display 历史路径 | 已验证 | XRGB8888/1080p V0.4 的 Fill/Copy/Color Key、双缓冲和 3600 帧老化已板测 |
| 三方统一接口 V1.1 | 已冻结 | RGB565/720p、UDP/BitBlt/Display、所有权及错误恢复已统一 |
| 联合 RGB565 位流 | 未完成 | A/B/C 仍需按统一规范迁移、联合仿真并完成目标板验收 |

## 协作规则

1. 厂家原始 Demo 不直接修改，工作副本放入 `03_bringup/`。
2. `04_project/` 是比赛正式工程。
3. 不提交安装包、厂家完整资料、构建缓存、日志和临时位流。
4. Efinity 的 `.xml`、`.peri.xml` 修改容易冲突，同一时间由一名成员负责同一工程配置。
5. 每个功能使用独立分支，例如 `feature/uart`、`feature/bitblt-fill`。
6. 合并前必须记录编译结果、WNS/WHS 和板上测试现象。
7. 测试代码依赖 `assert` 判定，测试构建禁止定义 `NDEBUG`——断言会被整体移除，测试将假通过
   （打印 `[FAIL]` 但不中止，退出码仍为 0）。CPU 渲染器测试见 `jzy/riscv_game/tests/`。
8. 三方跨模块接口只能由
   [`unified_fpga_interface_spec_v1.1.md`](07_docs/interfaces/unified_fpga_interface_spec_v1.1.md)
   定义；个人进度文档不得另建寄存器表、地址表或协议草案。
9. 跨角色协议修改必须先更新统一规范并提升版本，经 A/B/C 三方审阅后，再同步修改
   共享头文件、RTL、驱动和契约测试。单方代码先行不视为接口已变更。
10. “协议冻结”“模块仿真通过”“联合仿真通过”“目标板通过”是四种不同状态，
    进度记录必须明确写出，禁止用其中一种替代另一种。

详细使用方法见 `07_docs/notes/FPGA开发使用手册.md`。

赛题二三方唯一接口基线见
[`07_docs/interfaces/unified_fpga_interface_spec_v1.1.md`](07_docs/interfaces/unified_fpga_interface_spec_v1.1.md)。
该规范已经冻结 RGB565/720p、DDR、UDP、BitBlt、Display、所有权和验收规则；
当前联合实现仍未完成，独立 Demo 或旧位流通过不等于联合协议通过。

角色进度入口：

- A：`rwj/udp_image_demo/A_进度总览.md`
- B：`07_docs/progress/B_role_progress_and_plan.md`
- C：`jzy/readjzy.md`
- 团队职责与协议治理：`08_team/README.md`
