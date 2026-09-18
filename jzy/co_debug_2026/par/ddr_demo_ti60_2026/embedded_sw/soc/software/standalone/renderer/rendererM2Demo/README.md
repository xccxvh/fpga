# rendererM2Demo

M2 真板 smoke test，使用 Sapphire BSP 官方 `clint_getTime(BSP_CLINT)` 为
`bitblt_api.c` 注入 100 MHz tick source，然后验证：

- 10 ms CLINT delta 约为 1,000,000 tick；
- `bitblt_tick_source_ready() == 1`；
- 通过正式 `bitblt_fill()` 的 DDR 回读；
- 通过正式 `bitblt_copy()` 的 DDR 回读。

通过标记为 `M2 BITBLT BOARD TEST PASSED`。通用驱动不包含 BSP/CLINT 依赖。

真板运行必须下载 B 组 BitBlt overlay 工程产生的 bitstream。原始
`jzy/co_debug_2026/.../outflow/ddr_demo_ti60.bit` 没有连入 BitBlt RTL，
访问 `0xE1000000` 会让 CPU 等待不存在的 AXI 响应。

单独构建：

```bash
make BSP=efinix/EfxSapphireSoc \
  RENDER_ROOT=/path/to/jzy/riscv_game \
  BITBLT_INC_DIR=/path/to/04_project/bitblt_accel/sw/driver
```
