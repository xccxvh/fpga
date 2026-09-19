# BitBlt RTL 回归测试

本目录提供不依赖开发板的自检测试：

- `tb_bitblt_engine.sv`：Solid Fill、Block Copy、Burst 长度、二维 stride、
  4 KiB 边界、随机式 backpressure、非法参数及 AXI 错误响应。
- `tb_bitblt_ctrl_axi.sv`：寄存器复位/读写、START/BUSY/DONE/ERROR、完成中断、
  CLEAR、WSTRB、非法地址、非单拍访问及AW/W独立握手。
- `tb_axi_arbiters.sv`：写仲裁优先级、读仲裁Burst边界round-robin、持续双请求
  公平性、事务所有权保持和响应路由。
- `tb_axi_ctrl_demux_1to2.sv`：BitBlt/显示寄存器地址译码及未映射地址
  `DECERR` 响应。
- `tb_display_ctrl_axi.sv`：显示寄存器、VBlank 原子换帧、欠载计数和中断。
- `tb_display_dma_axi.sv`：Framebuffer DDR 读取、行步长、4 KiB 拆包和背压。
- `tb_async_fifo.sv`：DDR/像素异步时钟域 FIFO 的顺序和背压。
- `tb_video_pipeline.sv`：1280×720p60 时序及 RGB565 像素拆包。

Ubuntu 可安装 `iverilog` 后执行：

```bash
cd 04_project/bitblt_accel/hw/sim
make test
```

预期结尾：

```text
BitBlt engine regression: PASSED
BitBlt control regression: PASSED
AXI arbiter regression: PASSED
PASS: display control registers and vblank swap
PASS: AXI control address demultiplexer
PASS: display DMA burst, stride, 4KiB split and backpressure
PASS: 1280x720 timing and RGB565 pixel unpack
PASS: asynchronous FIFO ordering/backpressure
```

测试使用字节寻址内存模型，并对所有写入维护参考内存。任何非预期写入、Burst
超过16 beat、跨4 KiB边界、数据不一致或超时都会使仿真以失败结束。
