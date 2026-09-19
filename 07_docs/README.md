# Documentation Index

本目录只保存可维护的项目文档。厂家资料放在`01_board/`，可执行工程放在
`03_bringup/`或`04_project/`，构建日志和临时位流不进入Git。

## 当前权威文档

| 类别 | 文档 | 说明 |
|---|---|---|
| 联合接口 | [`interfaces/rgb565_720p_migration.md`](interfaces/rgb565_720p_migration.md) | 当前团队目标：RGB565、720p、B组DDR布局及统一换帧规则 |
| 历史接口 | [`interfaces/bitblt_interface_v0.2.md`](interfaces/bitblt_interface_v0.2.md) | 已板测的XRGB8888/1080p V0.4历史实现，不是联合目标 |
| B组进展 | [`progress/B_role_progress_and_plan.md`](progress/B_role_progress_and_plan.md) | BitBlt完成项、风险和后续计划 |
| 开发手册 | [`notes/FPGA开发使用手册.md`](notes/FPGA开发使用手册.md) | Efinity、Programmer和RISC-V IDE使用流程 |
| 环境 | [`environment.md`](environment.md) | 工具版本与开发环境 |

## 实板测试记录

- [`test_records/2026-09-16_bitblt_fill_copy_board_test.md`](test_records/2026-09-16_bitblt_fill_copy_board_test.md)：Fill/Copy早期板测。
- [`test_records/2026-09-18_bitblt_display_aging_test.md`](test_records/2026-09-18_bitblt_display_aging_test.md)：显示并发老化与零欠流记录。
- [`test_records/2026-09-18_bitblt_color_key_v0.4.md`](test_records/2026-09-18_bitblt_color_key_v0.4.md)：Color Key V0.4板测及待复测项。

## 目录规则

- `interfaces/`：跨组接口合同；实现变更必须同步版本和状态。
- `architecture/`：系统框图、模块边界和设计决策。
- `progress/`：个人负责模块的进展与计划。
- `test_records/`：可追溯的仿真、编译和上板证据。
- `notes/`：工具使用与排错记录。
- `references/`：外部参考资料索引，不复制大型厂家资料。
- `meeting/`：会议结论；最终决定需回写权威接口文档。

状态必须区分“目标已选定”“代码已实现”“联合编译通过”“实板验证通过”，
不得将独立Demo的结果写成联合工程已经完成。
