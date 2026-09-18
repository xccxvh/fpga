# BitBlt Performance Demo

在1920×1080 HDMI持续扫描时，对CPU与BitBlt的Fill/Copy端到端耗时进行对比。
源数据使用`ASSET_BASE`，目标使用`SCRATCH_BASE`，不会覆盖前台Framebuffer。

测试尺寸为64×64、320×240、640×480和1920×1080。CLINT频率为100 MHz；
输出吞吐率按每次操作的目标像素字节数计算，Copy不把DDR读写流量重复计为两倍。
每项完成后抽样回读首、中、末像素，并在每组测试后检查显示错误及欠流状态。

构建命令：

```bash
make clean all BSP=efinix/EfxSapphireSoc \
  RISCV_BIN=/home/user/efinity/efinity-riscv-ide-2026.1/toolchain/bin/riscv-none-elf-
```

2026-09-18板测已通过。1080p下硬件Fill为657.99 MiB/s、硬件Copy为
127.62 MiB/s，相对CPU分别加速17.59×和8.04×；完整测试期间显示扫描74帧，
欠流计数为0。完整尺寸表和仲裁问题分析见仓库根目录
`05_benchmark/README.md`。
