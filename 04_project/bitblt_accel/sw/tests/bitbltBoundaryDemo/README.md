# BitBlt 板级边界与吞吐回归

该程序在接口版本 `0x00010003` 的 BitBlt 位流上运行，补充小规模
Fill/Copy MVP 未覆盖的真实 DDR 边界测试：

- Fill 目标区前后哨兵、行尾 padding 和 20×3 像素回读；
- Copy 不同源/目标 stride、目标区哨兵和逐像素回读；
- 源、目标都从 4 KiB 边界前 16 B 开始的跨页 Copy；
- 640×480 XRGB8888 整帧 Copy、前后哨兵、逐像素回读和 CLINT 计时。

测试使用 DDR 地址 `0x01110000` 至约 `0x0182C000`。运行前必须确认这些地址
没有被显示 Framebuffer、程序代码或其他主机占用。

## 构建

把 `bitbltBoundaryDemo` 和同级 `driver` 复制到与现有
`bitbltCtrlDemo` 相同的 BSP 目录后执行：

```bash
export PATH=/home/user/efinity/efinity-riscv-ide-2026.1/toolchain/bin:$PATH
make clean all BSP=efinix/EfxSapphireSoc
```

本机 2026-09-16 构建通过，生成程序占用 10,864 B / 124 KiB（8.56%）。

## 上板验收

1. 先通过 Efinity Programmer 下载 BitBlt `0x00010003` 位流。
2. 打开串口：`picocom -b 115200 /dev/ttyUSB2`。
3. 通过 RISC-V IDE/OpenOCD 加载并运行 `build/bitbltBoundaryDemo.elf`。
4. 只有看到下列结尾，才能登记为板测通过：

```text
Fill guard test: PASSED
Copy guard/stride test: PASSED
4KiB boundary test: PASSED
Large Copy 640x480: PASSED
Large Copy bytes=1228800 ticks=<实测值> throughput=<实测值> KiB/s
*** BitBlt Board Boundary Regression PASSED ***
```

任一 `FAILED:`、程序停住或 OpenOCD 报错都不能记为通过。当前仓库只记录了
构建通过；实际开发板结果需要连接 USB 后补录。
