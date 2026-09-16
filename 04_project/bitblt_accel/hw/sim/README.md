# BitBlt RTL 回归测试

本目录提供不依赖开发板的自检测试：

- `tb_bitblt_engine.sv`：Solid Fill、Block Copy、Burst 长度、二维 stride、
  4 KiB 边界、随机式 backpressure、非法参数及 AXI 错误响应。
- `tb_axi_arbiters.sv`：读写仲裁优先级、事务所有权保持和响应路由。

Ubuntu 可安装 `iverilog` 后执行：

```bash
cd 04_project/bitblt_accel/hw/sim
make test
```

预期结尾：

```text
BitBlt engine regression: PASSED
AXI arbiter regression: PASSED
```

测试使用字节寻址内存模型，并对所有写入维护参考内存。任何非预期写入、Burst
超过16 beat、跨4 KiB边界、数据不一致或超时都会使仿真以失败结束。
