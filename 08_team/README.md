# Team

本目录记录团队任务分工、进度和周计划。三方接口的唯一权威来源是
[`../07_docs/interfaces/unified_fpga_interface_spec_v1.2.md`](../07_docs/interfaces/unified_fpga_interface_spec_v1.2.md)。

## 固定职责

| 角色 | 责任边界 | 主进度文档 |
|---|---|---|
| A | UDP 线协议、帧完整性、授权写门控、UDP DDR 写主机、Frame RX APB | `../rwj/udp_image_demo/A_进度总览.md` |
| B | 联合 SoC 顶层、DDR/AXI 仲裁、RGB565 BitBlt、720p Display/HDMI | `../07_docs/progress/B_role_progress_and_plan.md` |
| C | RISC-V 驱动、版本检查、后台所有权、唯一换帧提交、游戏与 CPU 回退 | `../jzy/readjzy.md` |

任何跨过上表边界的信号、寄存器、地址、状态位或时序语义都属于三方接口，必须写入统一
规范并经三方审阅，不能只写在个人 MD、聊天记录或代码注释中。

## 合并门禁

1. PR/合并说明必须填写影响的规范章节和版本；无接口变化写“无”。
2. 接口变化必须同时更新规范、唯一共享头文件、RTL/驱动和契约测试。
3. 数字常量不得在三方目录各复制一份；C 通过 include path 引用模块所有者的头文件。
4. 独立 Demo 只能标记“独立验证”；联合完成必须有端到端仿真、联合位流和目标板记录。
5. 未通过 VERSION 探测的组合禁止继续运行或用肉眼画面宣称兼容。
6. 旧协议草案不得留在 `07_docs/interfaces/`；历史结果只保留在 `test_records/` 或 Git 历史。
7. CPU 与 UDP/BitBlt/Display 交接 DDR 缓冲区时，必须执行 V1.2 的 cache 同步契约；
   `fence rw,rw` 不能替代硬件写后 D-cache invalidate。
8. 最终 Demo 必须在同一场景实时显示纯 CPU 与 BitBlt 的 FPS，测试条件和最低/平均 FPS
   写入 `05_benchmark/` 或 `07_docs/test_records/`。
