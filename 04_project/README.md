# Contest Project

比赛正式工程目录：`rtl/` 保存 FPGA 逻辑，`riscv/` 保存软件，`sim/` 保存 testbench，
`ip/` 和 `constraints/` 保存可复现的工程输入，`scripts/` 保存自动化工具。

所有正式模块必须遵守
[`../07_docs/interfaces/unified_fpga_interface_spec_v1.0.md`](../07_docs/interfaces/unified_fpga_interface_spec_v1.0.md)。
正式联合工程只能存在一个 SoC 顶层和一个 DDR 控制器；独立 Demo 不得直接复制进本目录后
同时保留自己的地址、像素格式、换帧或 DDR 配置。

新模块接入必须同时提供：唯一寄存器头文件、RTL 常量定义、模块自检、契约检查和联合测试
入口。未完成这些项目的代码可以作为 bring-up 实验，但不能标记为正式接口实现。
