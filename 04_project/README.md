# Contest Project

比赛正式工程当前集中在[`bitblt_accel/`](bitblt_accel/)：

- `hw/rtl/`：BitBlt、AXI仲裁、显示控制和Framebuffer扫描RTL。
- `hw/sim/`：自检testbench与仿真入口。
- `hw/efinity/`：可复现的Efinity overlay、约束和合并脚本。
- `sw/driver/`：BitBlt/显示寄存器与C API权威头文件。
- `sw/tests/`：控制、Fill/Copy、Color Key、性能和显示smoke程序。

顶层其他目录是早期规划占位，不应再复制一份BitBlt源码。新代码优先放入
`bitblt_accel/`的对应层级；板级试验先在`03_bringup/`验证，确认后再迁入正式工程。
构建生成的`outflow/`、`build/`、`work_*`、日志和位流不提交Git。
