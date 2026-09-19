# 厂家资料基线

完整厂家资料默认不进入主 Git 仓库。当前工作区另有 `resource/` 本地资料镜像，其索引、
SHA-256 和协议适用边界见 [`../../resource/README.md`](../../resource/README.md)。每名队员也可独立解压到自己的：

```text
fpga_workspace/local/vendor_original/Ti60F225_DemoBoard_v4
```

原始压缩包：

```text
Ti60F225_DemoBoard_v4完整资料包.zip
SHA-256: 31aec6aca350d819fcbf441ad152a0adcd8ae5ac8e3020115241ccab1ca35f22
```

工作时从厂家目录复制所需 Demo 到 `project/03_bringup/`，不得直接修改厂家基线。
官方 Demo 是平台事实和实现方式的参考，不是联合接口规范；发生冲突时以
[`../../07_docs/interfaces/unified_fpga_interface_spec_v1.2.md`](../../07_docs/interfaces/unified_fpga_interface_spec_v1.2.md)
为准。
