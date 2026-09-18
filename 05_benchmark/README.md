# Benchmark

记录 FPS、DDR 带宽、时序、资源利用率和可复现的测试结果。大型日志与原始构建输出不进入 Git。

## 2026-09-18 BitBlt Fill/Copy 实板性能

测试平台为 Ti60F225、100 MHz RISC-V/DDR 用户时钟及持续工作的
1920×1080@60 Hz HDMI 扫描。源位于 `ASSET_BASE`，目标位于
`SCRATCH_BASE`；每次操作后抽查首、中、末像素，并检查显示状态。
吞吐率只按目标有效载荷 `width * height * 4` 计算；Copy 不把 DDR 读写流量
重复计为两倍。每项执行一次，因此这些数据是当前板级基线，不是统计学均值。

| 尺寸 | CPU Fill | HW Fill | 加速比 | CPU Copy | HW Copy | 加速比 |
|---|---:|---:|---:|---:|---:|---:|
| 64×64 | 37.72 MiB/s | 472.48 MiB/s | 12.52× | 9.81 MiB/s | 118.15 MiB/s | 12.03× |
| 320×240 | 38.14 MiB/s | 654.86 MiB/s | 17.16× | 15.93 MiB/s | 131.23 MiB/s | 8.23× |
| 640×480 | 37.75 MiB/s | 649.57 MiB/s | 17.20× | 15.93 MiB/s | 131.43 MiB/s | 8.24× |
| 1920×1080 | 37.39 MiB/s | 657.99 MiB/s | 17.59× | 15.87 MiB/s | 127.62 MiB/s | 8.04× |

1080p单次耗时：CPU/HW Fill为211515/12021 us，CPU/HW Copy为
498336/61977 us。完整测试期间显示前台持续扫描74帧，
`UNDERFLOW_COUNT=0`，最终串口输出：

```text
Display frames=74, underflows=0
*** BITBLT PERFORMANCE DEMO PASSED ***
```

同一bitstream在第一次干净启动时的1080p结果为Fill 657.38 MiB/s、Copy
127.68 MiB/s，复跑偏差小于0.1%，均为74帧、零欠流。

### 仲裁问题与修复

最初第二级DDR读仲裁固定给予显示DMA最高优先级。显示持续发出64-beat Burst时，
CPU和BitBlt读请求会长时间饥饿；同一测试中640×480 CPU Copy曾达到
35.5 s，结果还会随显示帧相位明显变化。修复后，读仲裁器在每个Burst边界
round-robin，已接受的Burst仍保持所有权直到`RLAST`。上述性能测试证明CPU和
BitBlt读延迟恢复稳定，同时显示零欠流。

### 构建证据

- Efinity 2026.1 Map、Interface、PnR和bitstream生成通过。
- 最差setup slack：core `+2.958 ns`，DDR `+0.397 ns`，HDMI慢时钟
  `+2.344 ns`。
- 最差hold slack：`+0.026 ns`。
- JTAG SRAM下载器件ID：`0x10660A79`。
- bitstream SHA-256：
  `0278427468b6080a41b6fcf51a119fc0d8a809e346cb999a218464fb7fcbd659`。

可复现程序位于
`04_project/bitblt_accel/sw/tests/bitbltPerformanceDemo`。
