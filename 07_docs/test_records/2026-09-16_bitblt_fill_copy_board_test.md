# BitBlt Fill/Copy 板测记录

- 日期：2026-09-16
- FPGA：Efinix Ti60F225
- Efinity：2026.1.132
- RISC-V IDE：2026.1.0.7
- 接口版本：`0x00010003`
- Git 分支：`feature/bitblt-mvp`

## Solid Fill

- 目标地址：`0x01200000`
- 大小：80×3 个 32-bit 像素
- 目标 stride：384 B
- 颜色：`0xA5C3F00D`
- 结果：寄存器读回、BUSY→DONE、PLIC中断、240像素DDR回读全部通过。

预期/实测串口结果：

```text
*** BitBlt DDR Fill MVP ***
Register readback: PASSED
Status transition: PASSED
Completion IRQ: PASSED
DDR Fill burst readback: PASSED (240 pixels)
*** BitBlt DDR Fill MVP PASSED ***
```

## Block Copy

- 源地址：`0x01100000`
- 目标地址：`0x01200000`
- 大小：80×3 个 32-bit 像素
- 源 stride：384 B
- 目标 stride：416 B
- 源模式：`0x5A000000 | (y << 16) | x`
- 结果：CPU准备源数据、寄存器读回、BUSY→DONE、PLIC中断以及240像素逐项回读全部通过。

实测串口输出：

```text
*** BitBlt Block Copy MVP ***
CPU DDR writes: ISSUED
Source pattern: PREPARED
Register readback: PASSED
Status transition: PASSED
Completion IRQ: PASSED
DDR Copy burst readback: PASSED (240 pixels)
*** BitBlt Block Copy MVP PASSED ***
```

## 构建结果

- Efinity Map：PASS
- Interface：PASS
- Place & Route：PASS
- Bitstream/PGM：PASS
- 最差 Setup 余量：约 0.306 ns（`tx_cal_clk`）
- 最差 Hold 余量：约 0.026 ns
- RISC-V 测试程序：约 6480 B / 124 KiB（5.10%）

## 已知问题和未覆盖项

- 厂家 `soc_write_buffer_flush()` 在当前 CPU 配置下不会返回；测试改用标准
  `fence rw,rw` 后正常。正式驱动必须保留内存顺序屏障。
- 当前只完成小矩形/小块实板回读，没有完成保护区哨兵、实际跨4 KiB地址、
  backpressure、CPU/BitBlt/显示并发和整帧吞吐测试。
- Framebuffer、HDMI扫描、Double Buffer和VSync换帧不属于本次板测范围。
