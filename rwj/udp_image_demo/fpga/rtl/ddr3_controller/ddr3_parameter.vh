
//Generic
`define CKE_WIDTH	1
`define CS_WIDTH	1
`define RANK_WIDTH	1
`define BANK_WIDTH	3
`define ROW_WIDTH	14
`define COL_WIDTH	10
`define DM_WIDTH	2
`define DQS_WIDTH	2
`define DQ_WIDTH	16
`define ODT_WIDTH	1
`define DQ_CNT_WIDTH	4
`define DQS_CNT_WIDTH	1
`define DRAM_WIDTH	8
`define CK_WIDTH	1
`define RANKS	1
//AXI
`define DATA_WIDTH	16
// [2026-09-19 上板实测回退] A0-2 曾按"芯片实际 256MB，故 ADDR_WIDTH 应为 28"
//   把这里从 30 改成 28，同时把 ASYN_AXI_CLK 从 1 改成 0（见文件末尾），
//   但保留了本工程自己的 PHY 时钟相位（TX_CLK_SEL=0 / TX_CLK_90EDGE_SEL=3）。
//   **实测结果是画面花屏**；两个参数退回原值（30 / 1）后重建，画面恢复干净。
//
//   在数值上"28 才是芯片的真实地址宽度"这个推算没错，但 DDR3 控制器是加密 IP：
//   这 6 个参数是**一整套互相绑定的配置**，两份工程各有一套完整可用的组合，
//   **不能逐参数互换**。demo/08 的 (28,0,3,0) 和本工程的 (30,1,0,3) 各自都板测正常，
//   混搭则坏。详见 A0-2_DDR3配置统一.md 顶部红框。
//
//   要改必须整份替换 + 上板重跑校准，不能逐条拍板。
`define ADDR_WIDTH	30
`define AXI_ID_WIDTH	4
`define AXI_ADDR_WIDTH	32
`define AXI_DATA_WIDTH	128

//Timing
`define tCKE	7500

`define tFAW	35000
// [A0-2] 从 demo/08 补齐。memory_bus_ctl.v 里本来就有同名默认值 1_000_000，
//   两边都没人去覆盖它，所以功能上无差异 —— 补上纯粹是让两份文件一致，以后 diff 干净。
`define tPRDI	1000000

`define tRAS	35000
`define tRCD	15000
`define tREFI	7800000
`define tRFC	350000
`define tRP	15000
`define tRRD	10000
`define tRTP	10000
`define tWTR	10000
`define tZQI	128000000
`define tZQCS	64
`define tCK	2500
`define CWL	5
`define CL	6
`define nAL	0

//Options
`define RTT_NOM	"40"
`define RTT_WR	"60"
`define BURST_MODE	"8"
`define MEM_ADDR_ORDER	"BANK_ROW_COLUMN"
`define RX_CLK_SEL	2
`define TX_CLK_SEL	0
`define TX_CLK_90EDGE_SEL	3
`define CK_RATIO	4
// [2026-09-19 上板实测回退] A0-2 曾把这里从 1 改成 0，理由是 top.v 里
//     .axi_clk(sys_clk), .core_clk(sys_clk)
//   两个时钟同源，"宣称异步与实际不符"。该推理只看了加密块**外面**的 wrapper，
//   但这个参数在加密块内部还控制着什么，静态分析看不到。
//   实测：与 ADDR_WIDTH=28 一起改动后画面花屏，退回 1 后恢复干净。
//   详见 A0-2_DDR3配置统一.md 顶部红框。
`define ASYN_AXI_CLK	1
