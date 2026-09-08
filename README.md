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
| HDMI RX→TX | 排查中 | Efinity 2026.1 编译和 JTAG 下载通过，显示与 LED 指示仍需和厂家原始位流对照 |
| RISC-V | 未开始 | IDE 已安装，BSP Demo 尚未验证 |

## 协作规则

1. 厂家原始 Demo 不直接修改，工作副本放入 `03_bringup/`。
2. `04_project/` 是比赛正式工程。
3. 不提交安装包、厂家完整资料、构建缓存、日志和临时位流。
4. Efinity 的 `.xml`、`.peri.xml` 修改容易冲突，同一时间由一名成员负责同一工程配置。
5. 每个功能使用独立分支，例如 `feature/uart`、`feature/bitblt-fill`。
6. 合并前必须记录编译结果、WNS/WHS 和板上测试现象。

详细使用方法见 `07_docs/notes/FPGA开发使用手册.md`。
