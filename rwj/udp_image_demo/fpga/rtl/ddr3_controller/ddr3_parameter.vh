
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
// [A0-2] 原为 30（=1GB），但板上芯片实际 256MB：
//   BANK 3 / ROW 14 / COL 10 → 128M 单元，x16 位宽 → 256MB，故 ADDR_WIDTH = 28。
//   原值 30 会让 256MB 以上的地址被芯片忽略而回卷 —— 不报错，但数据悄悄写错地方。
//   之前一直没暴露，是因为 4 个槽位只用 8MB。合并后要用高地址，必须修正。
`define ADDR_WIDTH	28
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
// [A0-2] 原为 1（异步）。但 top.v 里 ddr3_top 的例化是
//     .axi_clk(sys_clk), .core_clk(sys_clk)
//   两个时钟同源，宣称异步与实际不符。改 0 让配置与接线一致，
//   也和 demo/08 对齐。注意：若 A1-3 统一时钟时决定 AXI 与 core 分频，
//   这里要改回 1。
`define ASYN_AXI_CLK	0
