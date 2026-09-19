# Release

Git 中只保存发布清单、版本说明和 SHA-256。`.bit`、`.hex` 等二进制产物通过远程 Release 或团队共享空间发布。

联合版本发布说明必须列出统一协议版本（当前为
[`FPGA-IF-1.2`](../07_docs/interfaces/unified_fpga_interface_spec_v1.2.md)）、三块 IP VERSION、
SoC D-cache 配置、cache 同步实现、FPS 对比记录及 3600 帧老化结果。缺少任一项不得标记
“联合完成”。
