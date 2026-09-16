//***************************************************************/
//
// Moudel Name    : ddr3_example_top.v
// Version        : 1.1
// Date Created   : 2023-02-23 10:37:59
// Last Modified  : 2023-02-24 15:27:41
// Abstract       : ---
//
//***************************************************************/
//Modification History
//1.initial
//***************************************************************/
`include "ddr3_controller/ddr3_parameter.vh"

`define Efinity_Debug
`timescale 1ps/1ps
// `define SOFT_JTAG

module ddr3_example_top #
(
parameter                       RANK_RATIO         = 1,       // # of unique CS outputs per rank
parameter                       CK_RATIO           = `CK_RATIO, 
parameter                       ASYN_AXI_CLK       = `ASYN_AXI_CLK, 
parameter                       RANKS              = `RANKS,
parameter                       CK_WIDTH           = `CK_WIDTH,       // # of CK/CK# outputs to memory   
parameter                       CKE_WIDTH          = `CKE_WIDTH,       // # of cke outputs
parameter                       CS_WIDTH           = `CS_WIDTH,       // # of unique CS outputs
parameter                       BANK_WIDTH         = `BANK_WIDTH,       // # of bank bits
parameter                       ROW_WIDTH          = `ROW_WIDTH,       // DRAM address bus width
parameter                       COL_WIDTH          = `COL_WIDTH,      // column address width
parameter                       DM_WIDTH           = `DM_WIDTH,       // # of DM (data mask)
parameter                       DQS_WIDTH          = `DQS_WIDTH,       // # of DQS (strobe)
parameter                       DQ_WIDTH           = `DQ_WIDTH,      // # of DQ (data)
parameter                       ODT_WIDTH          = `ODT_WIDTH,
parameter                       DQ_CNT_WIDTH       = `DQ_CNT_WIDTH,       // = ceil(log2(DQ_WIDTH))
parameter                       DQS_CNT_WIDTH      = `DQS_CNT_WIDTH,       // = ceil(log2(DQS_WIDTH))  
parameter                       DRAM_WIDTH         = `DRAM_WIDTH,       // # of DQ per DQS   
parameter                       DATA_WIDTH         = `DATA_WIDTH,
parameter                       ADDR_WIDTH         = `ADDR_WIDTH,    
parameter                       AXI_ID_WIDTH       = `AXI_ID_WIDTH,
parameter                       AXI_ADDR_WIDTH     = `AXI_ADDR_WIDTH,
parameter                       AXI_DATA_WIDTH     = `AXI_DATA_WIDTH
)
(

   // Clock and reset ports
   input                              axi_clk,      
   input                              core_clk,     // CORE CLK @ 100MHz
   input                              sdram_clk,    // SDRAM CK @ 400MHz
   input                              rx_cal_clk,   // SDRAM CK @ 400MHz
   input                              tx_cal_clk,   // SDRAM CK @ 400MHz
   input                              tx_cal_clk_90edge,   // SDRAM CK @ 400MHz
   input                              pll_locked,
   input                              user_pll_locked,
  //  input                              peripheralClk,
   //&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
   output  wire                       system_uart_0_io_txd,
   input                              system_uart_0_io_rxd,   
   input  [3:0]                       soc_gpio_IN,
   output [3:0]                       soc_gpio_OUT,
   output [3:0]                       soc_gpio_OE,
    // debug core ports
`ifdef  Efinity_Debug  //&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& 
`ifdef SOFT_JTAG
  input                               io_jtag_tms,
  input                               io_jtag_tdi,
  output  wire                        io_jtag_tdo,
  input                               io_jtag_tck,
`else
  input                               jtag_inst1_CAPTURE ,
  input                               jtag_inst1_DRCK    ,
  input                               jtag_inst1_RESET   ,
  input                               jtag_inst1_RUNTEST ,
  input                               jtag_inst1_SEL     ,
  input                               jtag_inst1_SHIFT   ,
  input                               jtag_inst1_TCK     ,
  input                               jtag_inst1_TDI     ,
  input                               jtag_inst1_TMS     ,
  input                               jtag_inst1_UPDATE  ,
  output                              jtag_inst1_TDO     ,
`endif 

`endif  //&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
   // PLL status flags  
   output [2:0]                       pll_shift,  
   output [4:0]                       pll_shift_sel,
   output                             pll_shift_ena,  
   // memory interface ports
   output                             ddr_ck_hi,
   output                             ddr_ck_lo,
   output                             ddr_reset_n,
   output [CKE_WIDTH-1:0]             ddr_cke,     
   output [ROW_WIDTH-1:0]             ddr_addr,
   output [BANK_WIDTH-1:0]            ddr_ba,
   output                             ddr_cas_n,

   output [CS_WIDTH*RANK_RATIO-1:0]   ddr_cs_n,
   output                             ddr_ras_n,
   output                             ddr_we_n,
   
   input  [DQS_WIDTH-1:0]             ddr_dqs_in_hi,
   input  [DQS_WIDTH-1:0]             ddr_dqs_in_lo,
   input  [DQ_WIDTH-1:0]              ddr_dq_in_hi,
   input  [DQ_WIDTH-1:0]              ddr_dq_in_lo,
   
   output [DQS_WIDTH-1:0]             ddr_dqs_oe,
   output [DQS_WIDTH-1:0]             ddr_dqs_oe_n,
   output [DQ_WIDTH-1:0]              ddr_dq_oe,  
   output [DQS_WIDTH-1:0]             ddr_dqs_out_hi,
   output [DQS_WIDTH-1:0]             ddr_dqs_out_lo,
   output [DQ_WIDTH-1:0]              ddr_dq_out_hi,
   output [DQ_WIDTH-1:0]              ddr_dq_out_lo,
   output [DM_WIDTH-1:0]              ddr_dm_hi,
   output [DM_WIDTH-1:0]              ddr_dm_lo,
   output [ODT_WIDTH-1:0]             ddr_odt,

   input                              system_spi_0_io_data_0_IN,
   input                              system_spi_0_io_data_1_IN,
   output                             system_spi_0_io_ss,
   output                             system_spi_0_io_sclk_write,
   output                             system_spi_0_io_data_0_OUT,
   output                             system_spi_0_io_data_0_OE,
   output                             system_spi_0_io_data_1_OUT,
   output                             system_spi_0_io_data_1_OE

   );


      
//Parameter Define
parameter FREQ = 200;			// default is 100 MHz.  Redefine as needed.
`ifndef SIM
    localparam CNT_INIT = 1.5*FREQ*1000;
`else
    localparam CNT_INIT = 10;
`endif    
  localparam   AIW               = AXI_ID_WIDTH      ;
  localparam   ADW               = AXI_DATA_WIDTH    ;
  localparam   ABN               = AXI_DATA_WIDTH/8   ;
  /////////////////////////////////////////////////////////
  // Wire declarations
  reg  [19:0]                       cnt;    
  wire                              clk;
  wire                              rst;
  wire                              mmcm_locked;
  reg                               aresetn;
  wire                              app_sr_active;
  wire                              app_ref_ack;
  wire                              app_zq_ack;

  wire                              cal_done;

  // Slave Interface Write Address Ports
  wire [AXI_ID_WIDTH-1:0]           s_axi_awid;
  wire [AXI_ADDR_WIDTH-1:0]         s_axi_awaddr;
  wire [7:0]                        s_axi_awlen;
  wire [2:0]                        s_axi_awsize;
  wire [1:0]                        s_axi_awburst;
  wire [0:0]                        s_axi_awlock;
  wire [3:0]                        s_axi_awcache;
  wire [2:0]                        s_axi_awprot;
  wire                              s_axi_awvalid;
  wire                              s_axi_awready;
   // Slave Interface Write Data Ports
  wire [AXI_DATA_WIDTH-1:0]         s_axi_wdata;
  wire [(AXI_DATA_WIDTH/8)-1:0]     s_axi_wstrb;
  wire                              s_axi_wlast;
  wire                              s_axi_wvalid;
  wire                              s_axi_wready;
   // Slave Interface Write Response Ports
  wire                              s_axi_bready;
  wire [AXI_ID_WIDTH-1:0]           s_axi_bid;
  wire [1:0]                        s_axi_bresp;
  wire                              s_axi_bvalid;
   // Slave Interface Read Address Ports
  wire [AXI_ID_WIDTH-1:0]           s_axi_arid;
  wire [AXI_ADDR_WIDTH-1:0]         s_axi_araddr;
  wire [7:0]                        s_axi_arlen;
  wire [2:0]                        s_axi_arsize;
  wire [1:0]                        s_axi_arburst;
  wire [0:0]                        s_axi_arlock;
  wire [3:0]                        s_axi_arcache;
  wire [2:0]                        s_axi_arprot;
  wire                              s_axi_arvalid;
  wire                              s_axi_arready;
   // Slave Interface Read Data Ports
  wire                              s_axi_rready;
  wire [AXI_ID_WIDTH-1:0]           s_axi_rid;
  wire [AXI_DATA_WIDTH-1:0]         s_axi_rdata;
  wire [1:0]                        s_axi_rresp;
  wire                              s_axi_rlast;
  wire                              s_axi_rvalid;

  // Sapphire external-memory AXI master before write arbitration.
  wire [7:0]                        cpu_ddr_awid;
  wire [31:0]                       cpu_ddr_awaddr;
  wire [7:0]                        cpu_ddr_awlen;
  wire [2:0]                        cpu_ddr_awsize;
  wire [1:0]                        cpu_ddr_awburst;
  wire                              cpu_ddr_awlock;
  wire [3:0]                        cpu_ddr_awcache;
  wire [2:0]                        cpu_ddr_awprot;
  wire                              cpu_ddr_awvalid;
  wire                              cpu_ddr_awready;
  wire [127:0]                      cpu_ddr_wdata;
  wire [15:0]                       cpu_ddr_wstrb;
  wire                              cpu_ddr_wlast;
  wire                              cpu_ddr_wvalid;
  wire                              cpu_ddr_wready;
  wire [7:0]                        cpu_ddr_bid;
  wire [1:0]                        cpu_ddr_bresp;
  wire                              cpu_ddr_bvalid;
  wire                              cpu_ddr_bready;
  wire [7:0]                        cpu_ddr_arid;
  wire [31:0]                       cpu_ddr_araddr;
  wire [7:0]                        cpu_ddr_arlen;
  wire [2:0]                        cpu_ddr_arsize;
  wire [1:0]                        cpu_ddr_arburst;
  wire                              cpu_ddr_arlock;
  wire [3:0]                        cpu_ddr_arcache;
  wire [2:0]                        cpu_ddr_arprot;
  wire                              cpu_ddr_arvalid;
  wire                              cpu_ddr_arready;
  wire [7:0]                        cpu_ddr_rid;
  wire [127:0]                      cpu_ddr_rdata;
  wire [1:0]                        cpu_ddr_rresp;
  wire                              cpu_ddr_rlast;
  wire                              cpu_ddr_rvalid;
  wire                              cpu_ddr_rready;

  // BitBlt engine AXI read/write masters.
  wire                              bitblt_start;
  wire [31:0]                       bitblt_src_addr;
  wire [31:0]                       bitblt_dst_addr;
  wire [31:0]                       bitblt_width;
  wire [31:0]                       bitblt_height;
  wire [31:0]                       bitblt_src_stride;
  wire [31:0]                       bitblt_dst_stride;
  wire [31:0]                       bitblt_color;
  wire [31:0]                       bitblt_operation;
  wire                              bitblt_busy;
  wire                              bitblt_done;
  wire                              bitblt_error;
  wire [7:0]                        bitblt_awid;
  wire [31:0]                       bitblt_awaddr;
  wire [7:0]                        bitblt_awlen;
  wire [2:0]                        bitblt_awsize;
  wire [1:0]                        bitblt_awburst;
  wire                              bitblt_awlock;
  wire [3:0]                        bitblt_awcache;
  wire [2:0]                        bitblt_awprot;
  wire                              bitblt_awvalid;
  wire                              bitblt_awready;
  wire [127:0]                      bitblt_wdata;
  wire [15:0]                       bitblt_wstrb;
  wire                              bitblt_wlast;
  wire                              bitblt_wvalid;
  wire                              bitblt_wready;
  wire [7:0]                        bitblt_bid;
  wire [1:0]                        bitblt_bresp;
  wire                              bitblt_bvalid;
  wire                              bitblt_bready;
  wire [7:0]                        bitblt_arid;
  wire [31:0]                       bitblt_araddr;
  wire [7:0]                        bitblt_arlen;
  wire [2:0]                        bitblt_arsize;
  wire [1:0]                        bitblt_arburst;
  wire                              bitblt_arlock;
  wire [3:0]                        bitblt_arcache;
  wire [2:0]                        bitblt_arprot;
  wire                              bitblt_arvalid;
  wire                              bitblt_arready;
  wire [7:0]                        bitblt_rid;
  wire [127:0]                      bitblt_rdata;
  wire [1:0]                        bitblt_rresp;
  wire                              bitblt_rlast;
  wire                              bitblt_rvalid;
  wire                              bitblt_rready;

  // Sapphire AXI-A master -> local 4 KiB RAM slave
  wire [7:0]                        axiA_awid;
  wire [31:0]                       axiA_awaddr;
  wire [7:0]                        axiA_awlen;
  wire [2:0]                        axiA_awsize;
  wire [1:0]                        axiA_awburst;
  wire                              axiA_awlock;
  wire [3:0]                        axiA_awcache;
  wire [2:0]                        axiA_awprot;
  wire [3:0]                        axiA_awqos;
  wire [3:0]                        axiA_awregion;
  wire                              axiA_awvalid;
  wire                              axiA_awready;
  wire [31:0]                       axiA_wdata;
  wire [3:0]                        axiA_wstrb;
  wire                              axiA_wlast;
  wire                              axiA_wvalid;
  wire                              axiA_wready;
  wire [7:0]                        axiA_bid;
  wire [1:0]                        axiA_bresp;
  wire                              axiA_bvalid;
  wire                              axiA_bready;
  wire [7:0]                        axiA_arid;
  wire [31:0]                       axiA_araddr;
  wire [7:0]                        axiA_arlen;
  wire [2:0]                        axiA_arsize;
  wire [1:0]                        axiA_arburst;
  wire                              axiA_arlock;
  wire [3:0]                        axiA_arcache;
  wire [2:0]                        axiA_arprot;
  wire [3:0]                        axiA_arqos;
  wire [3:0]                        axiA_arregion;
  wire                              axiA_arvalid;
  wire                              axiA_arready;
  wire [7:0]                        axiA_rid;
  wire [31:0]                       axiA_rdata;
  wire [1:0]                        axiA_rresp;
  wire                              axiA_rlast;
  wire                              axiA_rvalid;
  wire                              axiA_rready;
  wire                              axiA_interrupt;


//***************************************************************************
  wire [2:0]                        vio_pll_shift;  
  wire [4:0]                        vio_pll_shift_sel;
  wire                              vio_pll_shift_ena; 
  wire                              pos_pll_shift_ena; 
  wire [2:0]                        phy_pll_shift;  
  wire [4:0]                        phy_pll_shift_sel;
  wire                              phy_pll_shift_ena; 
  wire                              ddr_reset; 
  wire                              sys_rst;
  wire  [2:0]                       phy_wr_pll_shift;
  wire                              idelay_ld       ;
  wire                              mpr_rdlvl_dly   ;
  wire  [7:0]                       wrlvl_dq_check  ;
  wire  [7:0]                       rd_level_dqs_check;  
  wire  [2:0]                       rdlvl_shift;  
  wire  [2:0]                       wrlvl_shift;  
  wire  [15:0]                      debug_fifo;  
  wire  [15:0]                      overflow_fifo;  
  wire  [6:0]                       init_cur_state;  
  wire  [35:0]                      ddr_debug_port;  
  wire                              app_rdy;  
  wire                              user_clk;  
  wire                              ddr_rstn;  
  wire                                phy_rddata_valid;
  wire [2*CK_RATIO*DQ_WIDTH-1:0]      phy_rd_data;
  wire [2*CK_RATIO*DATA_WIDTH-1:0]    app_rd_data_to_axi; 
  wire                                app_rd_data_end;
  wire                                app_rd_data_valid;
  wire [2*CK_RATIO*DQ_WIDTH-1:0]      rd_data;          
  wire                                rd_data_en;            
  wire                                rd_data_end;   
   
  
// Start of User Design top instance
//***************************************************************************
// The User design is instantiated below. The memory interface ports are
// connected to the top-level and the application interface ports are
// connected to the traffic generator module. This provides a reference
// for connecting the memory controller to system.
//***************************************************************************
always @(posedge user_clk or negedge sys_rst) begin
	if (!sys_rst)
		cnt <= 0;
    else if (cnt != CNT_INIT) 
        cnt <= cnt + 20'd1;
	else 
        cnt <= cnt;
end
assign ddr_rstn = (cnt == CNT_INIT);


generate
if (ASYN_AXI_CLK) begin
assign user_clk = axi_clk;

end else begin
assign user_clk = core_clk;
end
endgenerate
//***************************************************************************
// The traffic generation module instantiated below drives traffic (patterns)
// on the application interface of the memory controller
//***************************************************************************
//***************************************************************************

assign sys_rst       = pll_locked & user_pll_locked;

//***************************************************************************
ddr3_top                 u_ddr3_top
      (
      
    .axi_clk                (user_clk             ),
    .core_clk               (core_clk            ),
    .sdram_clk              (sdram_clk           ),  
    .rx_cal_clk             (rx_cal_clk          ),
    .tx_cal_clk             (tx_cal_clk          ),
    .tx_cal_clk_90edge      (tx_cal_clk_90edge   ),
    .rstn                   (ddr_rstn            ),      
    .pll_shift              (pll_shift           ),
    .pll_shift_sel          (pll_shift_sel       ),
    .pll_shift_ena          (pll_shift_ena       ), 
///////////////DDR BUS
    .ddr_ck_hi              (ddr_ck_hi           ),
    .ddr_ck_lo              (ddr_ck_lo           ),
    .ddr_cke                (ddr_cke             ),    
    .ddr_reset_n            (ddr_reset_n         ),
    .ddr_cs_n               (ddr_cs_n            ),
    .ddr_ras_n              (ddr_ras_n           ),
    .ddr_cas_n              (ddr_cas_n           ),
    .ddr_we_n               (ddr_we_n            ),     
    .ddr_addr               (ddr_addr            ),
    .ddr_ba                 (ddr_ba              ),

    .ddr_dqs_oe             (ddr_dqs_oe          ),
    .ddr_dqs_oe_n           (ddr_dqs_oe_n        ),
    .ddr_dq_oe              (ddr_dq_oe           ),
    .ddr_dqs_in_hi          (ddr_dqs_in_hi       ),
    .ddr_dqs_in_lo          (ddr_dqs_in_lo       ),
    .ddr_dq_in_hi           (ddr_dq_in_hi        ),
    .ddr_dq_in_lo           (ddr_dq_in_lo        ),

    .ddr_dqs_out_hi         (ddr_dqs_out_hi      ),
    .ddr_dqs_out_lo         (ddr_dqs_out_lo      ),
    .ddr_dq_out_hi          (ddr_dq_out_hi       ),
    .ddr_dq_out_lo          (ddr_dq_out_lo       ),
    
    .ddr_dm_hi              (ddr_dm_hi           ),
    .ddr_dm_lo              (ddr_dm_lo           ),
    .ddr_odt                (ddr_odt             ),

// Application interface ports
       .app_sr_req                     (1'b0),
       .app_ref_req                    (1'b0),
       .app_zq_req                     (1'b0),
       .app_sr_active                  (app_sr_active),
       .app_ref_ack                    (app_ref_ack),
       .app_zq_ack                     (app_zq_ack),

// Slave Interface Write Address Ports
       .s_axi_awid                     (s_axi_awid        ),
       .s_axi_awaddr                   (s_axi_awaddr      ),
       .s_axi_awlen                    (s_axi_awlen       ),
       .s_axi_awsize                   (s_axi_awsize      ),
       .s_axi_awburst                  (s_axi_awburst     ),
       .s_axi_awlock                   (s_axi_awlock      ),
       .s_axi_awcache                  (s_axi_awcache     ),
       .s_axi_awprot                   (s_axi_awprot      ),
       .s_axi_awqos                    (4'h0              ),
       .s_axi_awvalid                  (s_axi_awvalid     ),
       .s_axi_awready                  (s_axi_awready     ),
// Slave Interface Write Data Ports
       .s_axi_wdata                    (s_axi_wdata       ),
       .s_axi_wstrb                    (s_axi_wstrb       ),
       .s_axi_wlast                    (s_axi_wlast       ),
       .s_axi_wvalid                   (s_axi_wvalid      ),
       .s_axi_wready                   (s_axi_wready      ),
// Slave Interface Write Response Ports
       .s_axi_bid                      (s_axi_bid         ),
       .s_axi_bresp                    (s_axi_bresp       ),
       .s_axi_bvalid                   (s_axi_bvalid      ),
       .s_axi_bready                   (s_axi_bready      ),
// Slave Interface Read Address Ports
       .s_axi_arid                     (s_axi_arid        ),
       .s_axi_araddr                   (s_axi_araddr      ),
       .s_axi_arlen                    (s_axi_arlen       ),
       .s_axi_arsize                   (s_axi_arsize      ),
       .s_axi_arburst                  (s_axi_arburst     ),
       .s_axi_arlock                   (s_axi_arlock      ),
       .s_axi_arcache                  (s_axi_arcache     ),
       .s_axi_arprot                   (s_axi_arprot      ),
       .s_axi_arqos                    (4'h0              ),
       .s_axi_arvalid                  (s_axi_arvalid     ),
       .s_axi_arready                  (s_axi_arready     ),
// Slave Interface Read Data Ports
       .s_axi_rid                      (s_axi_rid         ),
       .s_axi_rdata                    (s_axi_rdata       ),
       .s_axi_rresp                    (s_axi_rresp       ),
       .s_axi_rlast                    (s_axi_rlast       ),
       .s_axi_rvalid                   (s_axi_rvalid      ),
       .s_axi_rready                   (s_axi_rready      ),
//DEBUG       
       .wrlvl_dq_check                 (wrlvl_dq_check    ) ,
       .rd_level_dqs_check             (rd_level_dqs_check) ,
       .rdlvl_shift                    (rdlvl_shift) ,
       .wrlvl_shift                    (wrlvl_shift) ,
       .init_cur_state                 (init_cur_state    ) ,
       .idelay_ld                      (idelay_ld         ) ,
       .mpr_rdlvl_dly                  (mpr_rdlvl_dly     ) ,
       .ddr_debug_port                 (ddr_debug_port    ) ,
       .cal_done                       (cal_done          ) 
       );
// End of User Design top instance

//***************************************************************************


//***************************************************************************
soc u_sapphire_soc(
    .io_asyncReset                      (!pll_locked                        ),
    .io_systemClk                       (user_clk                           ),

    //UART 0
    .system_uart_0_io_txd               (system_uart_0_io_txd               ),
    .system_uart_0_io_rxd               (system_uart_0_io_rxd               ),
    .io_memoryClk                       (user_clk                           ),
    .io_memoryReset                     (                                   ),
    .io_systemReset                     (                                   ),

    // AXI-A master connected to the local RAM slave below
    .axiA_awid                          (axiA_awid                          ),
    .axiA_awaddr                        (axiA_awaddr                        ),
    .axiA_awlen                         (axiA_awlen                         ),
    .axiA_awsize                        (axiA_awsize                        ),
    .axiA_awburst                       (axiA_awburst                       ),
    .axiA_awlock                        (axiA_awlock                        ),
    .axiA_awcache                       (axiA_awcache                       ),
    .axiA_awprot                        (axiA_awprot                        ),
    .axiA_awqos                         (axiA_awqos                         ),
    .axiA_awregion                      (axiA_awregion                      ),
    .axiA_awvalid                       (axiA_awvalid                       ),
    .axiA_awready                       (axiA_awready                       ),
    .axiA_wdata                         (axiA_wdata                         ),
    .axiA_wstrb                         (axiA_wstrb                         ),
    .axiA_wlast                         (axiA_wlast                         ),
    .axiA_wvalid                        (axiA_wvalid                        ),
    .axiA_wready                        (axiA_wready                        ),
    .axiA_bid                           (axiA_bid                           ),
    .axiA_bresp                         (axiA_bresp                         ),
    .axiA_bvalid                        (axiA_bvalid                        ),
    .axiA_bready                        (axiA_bready                        ),
    .axiA_arid                          (axiA_arid                          ),
    .axiA_araddr                        (axiA_araddr                        ),
    .axiA_arlen                         (axiA_arlen                         ),
    .axiA_arsize                        (axiA_arsize                        ),
    .axiA_arburst                       (axiA_arburst                       ),
    .axiA_arlock                        (axiA_arlock                        ),
    .axiA_arcache                       (axiA_arcache                       ),
    .axiA_arprot                        (axiA_arprot                        ),
    .axiA_arqos                         (axiA_arqos                         ),
    .axiA_arregion                      (axiA_arregion                      ),
    .axiA_arvalid                       (axiA_arvalid                       ),
    .axiA_arready                       (axiA_arready                       ),
    .axiA_rid                           (axiA_rid                           ),
    .axiA_rdata                         (axiA_rdata                         ),
    .axiA_rresp                         (axiA_rresp                         ),
    .axiA_rlast                         (axiA_rlast                         ),
    .axiA_rvalid                        (axiA_rvalid                        ),
    .axiA_rready                        (axiA_rready                        ),
    .axiAInterrupt                      (axiA_interrupt                     ),

    //External Memory AXI4 Interface
    .io_ddrA_aw_payload_prot            (cpu_ddr_awprot                    ),
    .io_ddrA_aw_payload_qos             (                                  ),//(                                  ),
    .io_ddrA_aw_payload_cache           (cpu_ddr_awcache                   ),
    .io_ddrA_aw_payload_lock            (cpu_ddr_awlock                    ),
    .io_ddrA_aw_payload_burst           (cpu_ddr_awburst                   ),
    .io_ddrA_aw_payload_size            (cpu_ddr_awsize                    ),
    .io_ddrA_aw_payload_len             (cpu_ddr_awlen                     ),
    .io_ddrA_aw_payload_region          (                                 ),//(                                  ),
    .io_ddrA_aw_payload_id              (cpu_ddr_awid                      ),
    .io_ddrA_aw_payload_addr            (cpu_ddr_awaddr                    ),
    .io_ddrA_aw_ready                   (cpu_ddr_awready                   ),
    .io_ddrA_aw_valid                   (cpu_ddr_awvalid                   ),
    .io_ddrA_w_payload_last             (cpu_ddr_wlast                     ),
    .io_ddrA_w_ready                    (cpu_ddr_wready                    ),
    .io_ddrA_w_valid                    (cpu_ddr_wvalid                    ),
    .io_ddrA_w_payload_strb             (cpu_ddr_wstrb                     ),
    .io_ddrA_w_payload_data             (cpu_ddr_wdata                     ),
    .io_ddrA_b_payload_resp             (cpu_ddr_bresp                     ),
    .io_ddrA_b_payload_id               (cpu_ddr_bid                       ),
    .io_ddrA_b_ready                    (cpu_ddr_bready                    ),
    .io_ddrA_b_valid                    (cpu_ddr_bvalid                    ),
    .io_ddrA_ar_payload_prot            (cpu_ddr_arprot                   ),
    .io_ddrA_ar_payload_qos             (                                 ),//(                                  ),
    .io_ddrA_ar_payload_cache           (cpu_ddr_arcache                  ),
    .io_ddrA_ar_payload_region          (                                 ),//(                                  ),
    .io_ddrA_ar_payload_lock            (cpu_ddr_arlock                   ),
    .io_ddrA_ar_payload_burst           (cpu_ddr_arburst                  ),
    .io_ddrA_ar_payload_size            (cpu_ddr_arsize                   ),
    .io_ddrA_ar_payload_len             (cpu_ddr_arlen                    ),
    .io_ddrA_ar_payload_id              (cpu_ddr_arid                     ),
    .io_ddrA_ar_payload_addr            (cpu_ddr_araddr                   ),
    .io_ddrA_ar_ready                   (cpu_ddr_arready                  ),
    .io_ddrA_ar_valid                   (cpu_ddr_arvalid                  ),
    .io_ddrA_r_payload_last             (cpu_ddr_rlast                    ),
    .io_ddrA_r_payload_resp             (cpu_ddr_rresp                    ),
    .io_ddrA_r_payload_id               (cpu_ddr_rid                      ),
    .io_ddrA_r_payload_data             (cpu_ddr_rdata                    ),
    .io_ddrA_r_ready                    (cpu_ddr_rready                   ),
    .io_ddrA_r_valid                    (cpu_ddr_rvalid                   ),
     //SPI 0
    .system_spi_0_io_sclk_write         (system_spi_0_io_sclk_write         ),
    .system_spi_0_io_data_0_writeEnable (system_spi_0_io_data_0_OE ),
    .system_spi_0_io_data_0_read        (system_spi_0_io_data_0_IN        ),
    .system_spi_0_io_data_0_write       (system_spi_0_io_data_0_OUT       ),
    .system_spi_0_io_data_1_writeEnable (system_spi_0_io_data_1_OE ),
    .system_spi_0_io_data_1_read        (system_spi_0_io_data_1_IN        ),
    .system_spi_0_io_data_1_write       (system_spi_0_io_data_1_OUT       ),
    .system_spi_0_io_data_2_writeEnable (                                   ),
    .system_spi_0_io_data_2_read        (                                   ),
    .system_spi_0_io_data_2_write       (                                   ),
    .system_spi_0_io_data_3_writeEnable (                                   ),
    .system_spi_0_io_data_3_read        (                                   ),
    .system_spi_0_io_data_3_write       (                                   ),
    .system_spi_0_io_ss                 (system_spi_0_io_ss                 ),
    //APB 0
    .io_apbSlave_0_PADDR                (apb_paddr                          ),
    .io_apbSlave_0_PSEL                 (apb_psel                           ),
    .io_apbSlave_0_PENABLE              (apb_penable                        ),
    .io_apbSlave_0_PREADY               (apb_pready                         ),
    .io_apbSlave_0_PWRITE               (apb_pwrite                         ),
    .io_apbSlave_0_PWDATA               (apb_pwdata                         ),
    .io_apbSlave_0_PRDATA               (apb_prdata                         ),
    .io_apbSlave_0_PSLVERROR            (apb_pslverror                      ),

    .system_gpio_0_io_write             ( soc_gpio_OUT                      ),//,
    .system_gpio_0_io_read              ( soc_gpio_IN                       ),//
    .system_gpio_0_io_writeEnable       ( soc_gpio_OE                       ),//, 


    //Hard Jtag Tap
    .jtagCtrl_tck                       (jtag_inst1_TCK                     ),
    .jtagCtrl_tdi                       (jtag_inst1_TDI                     ),
    .jtagCtrl_tdo                       (jtag_inst1_TDO                     ),
    .jtagCtrl_enable                    (jtag_inst1_SEL                     ),
    .jtagCtrl_capture                   (jtag_inst1_CAPTURE                 ),
    .jtagCtrl_shift                     (jtag_inst1_SHIFT                   ),
    .jtagCtrl_update                    (jtag_inst1_UPDATE                  ),
    .jtagCtrl_reset                     (jtag_inst1_RESET                   )

);


axi_write_arbiter_2to1 u_ddr_write_arbiter (
    .clk(user_clk), .resetn(ddr_rstn),
    .s0_awid(cpu_ddr_awid), .s0_awaddr(cpu_ddr_awaddr), .s0_awlen(cpu_ddr_awlen),
    .s0_awsize(cpu_ddr_awsize), .s0_awburst(cpu_ddr_awburst), .s0_awlock(cpu_ddr_awlock),
    .s0_awcache(cpu_ddr_awcache), .s0_awprot(cpu_ddr_awprot),
    .s0_awvalid(cpu_ddr_awvalid), .s0_awready(cpu_ddr_awready),
    .s0_wdata(cpu_ddr_wdata), .s0_wstrb(cpu_ddr_wstrb), .s0_wlast(cpu_ddr_wlast),
    .s0_wvalid(cpu_ddr_wvalid), .s0_wready(cpu_ddr_wready),
    .s0_bid(cpu_ddr_bid), .s0_bresp(cpu_ddr_bresp), .s0_bvalid(cpu_ddr_bvalid), .s0_bready(cpu_ddr_bready),
    .s1_awid(bitblt_awid), .s1_awaddr(bitblt_awaddr), .s1_awlen(bitblt_awlen),
    .s1_awsize(bitblt_awsize), .s1_awburst(bitblt_awburst), .s1_awlock(bitblt_awlock),
    .s1_awcache(bitblt_awcache), .s1_awprot(bitblt_awprot),
    .s1_awvalid(bitblt_awvalid), .s1_awready(bitblt_awready),
    .s1_wdata(bitblt_wdata), .s1_wstrb(bitblt_wstrb), .s1_wlast(bitblt_wlast),
    .s1_wvalid(bitblt_wvalid), .s1_wready(bitblt_wready),
    .s1_bid(bitblt_bid), .s1_bresp(bitblt_bresp), .s1_bvalid(bitblt_bvalid), .s1_bready(bitblt_bready),
    .m_awid(s_axi_awid), .m_awaddr(s_axi_awaddr), .m_awlen(s_axi_awlen),
    .m_awsize(s_axi_awsize), .m_awburst(s_axi_awburst), .m_awlock(s_axi_awlock),
    .m_awcache(s_axi_awcache), .m_awprot(s_axi_awprot),
    .m_awvalid(s_axi_awvalid), .m_awready(s_axi_awready),
    .m_wdata(s_axi_wdata), .m_wstrb(s_axi_wstrb), .m_wlast(s_axi_wlast),
    .m_wvalid(s_axi_wvalid), .m_wready(s_axi_wready),
    .m_bid(s_axi_bid), .m_bresp(s_axi_bresp), .m_bvalid(s_axi_bvalid), .m_bready(s_axi_bready)
);


axi_read_arbiter_2to1 u_ddr_read_arbiter (
    .clk(user_clk), .resetn(ddr_rstn),
    .s0_arid(cpu_ddr_arid), .s0_araddr(cpu_ddr_araddr), .s0_arlen(cpu_ddr_arlen),
    .s0_arsize(cpu_ddr_arsize), .s0_arburst(cpu_ddr_arburst), .s0_arlock(cpu_ddr_arlock),
    .s0_arcache(cpu_ddr_arcache), .s0_arprot(cpu_ddr_arprot),
    .s0_arvalid(cpu_ddr_arvalid), .s0_arready(cpu_ddr_arready),
    .s0_rid(cpu_ddr_rid), .s0_rdata(cpu_ddr_rdata), .s0_rresp(cpu_ddr_rresp),
    .s0_rlast(cpu_ddr_rlast), .s0_rvalid(cpu_ddr_rvalid), .s0_rready(cpu_ddr_rready),
    .s1_arid(bitblt_arid), .s1_araddr(bitblt_araddr), .s1_arlen(bitblt_arlen),
    .s1_arsize(bitblt_arsize), .s1_arburst(bitblt_arburst), .s1_arlock(bitblt_arlock),
    .s1_arcache(bitblt_arcache), .s1_arprot(bitblt_arprot),
    .s1_arvalid(bitblt_arvalid), .s1_arready(bitblt_arready),
    .s1_rid(bitblt_rid), .s1_rdata(bitblt_rdata), .s1_rresp(bitblt_rresp),
    .s1_rlast(bitblt_rlast), .s1_rvalid(bitblt_rvalid), .s1_rready(bitblt_rready),
    .m_arid(s_axi_arid), .m_araddr(s_axi_araddr), .m_arlen(s_axi_arlen),
    .m_arsize(s_axi_arsize), .m_arburst(s_axi_arburst), .m_arlock(s_axi_arlock),
    .m_arcache(s_axi_arcache), .m_arprot(s_axi_arprot),
    .m_arvalid(s_axi_arvalid), .m_arready(s_axi_arready),
    .m_rid(s_axi_rid), .m_rdata(s_axi_rdata), .m_rresp(s_axi_rresp),
    .m_rlast(s_axi_rlast), .m_rvalid(s_axi_rvalid), .m_rready(s_axi_rready)
);

bitblt_engine u_bitblt_engine (
    .clk(user_clk), .resetn(ddr_rstn), .start(bitblt_start),
    .src_addr(bitblt_src_addr), .dst_addr(bitblt_dst_addr),
    .width(bitblt_width), .height(bitblt_height),
    .src_stride(bitblt_src_stride), .dst_stride(bitblt_dst_stride),
    .color(bitblt_color), .operation(bitblt_operation),
    .busy(bitblt_busy), .done(bitblt_done), .error(bitblt_error),
    .m_awid(bitblt_awid), .m_awaddr(bitblt_awaddr), .m_awlen(bitblt_awlen),
    .m_awsize(bitblt_awsize), .m_awburst(bitblt_awburst), .m_awlock(bitblt_awlock),
    .m_awcache(bitblt_awcache), .m_awprot(bitblt_awprot),
    .m_awvalid(bitblt_awvalid), .m_awready(bitblt_awready),
    .m_wdata(bitblt_wdata), .m_wstrb(bitblt_wstrb), .m_wlast(bitblt_wlast),
    .m_wvalid(bitblt_wvalid), .m_wready(bitblt_wready),
    .m_bid(bitblt_bid), .m_bresp(bitblt_bresp), .m_bvalid(bitblt_bvalid), .m_bready(bitblt_bready),
    .m_arid(bitblt_arid), .m_araddr(bitblt_araddr), .m_arlen(bitblt_arlen),
    .m_arsize(bitblt_arsize), .m_arburst(bitblt_arburst), .m_arlock(bitblt_arlock),
    .m_arcache(bitblt_arcache), .m_arprot(bitblt_arprot),
    .m_arvalid(bitblt_arvalid), .m_arready(bitblt_arready),
    .m_rid(bitblt_rid), .m_rdata(bitblt_rdata), .m_rresp(bitblt_rresp),
    .m_rlast(bitblt_rlast), .m_rvalid(bitblt_rvalid), .m_rready(bitblt_rready)
);


bitblt_ctrl_axi #(
    .ADDR_WIDTH                         (32                                 ),
    .DATA_WIDTH                         (32                                 )
) u_axi4_slave (
    .axi_interrupt                      (axiA_interrupt                     ),
    .axi_aclk                           (user_clk                           ),
    .axi_resetn                         (ddr_rstn                           ),
    .axi_awid                           (axiA_awid                          ),
    .axi_awaddr                         (axiA_awaddr                        ),
    .axi_awlen                          (axiA_awlen                         ),
    .axi_awsize                         (axiA_awsize                        ),
    .axi_awburst                        (axiA_awburst                       ),
    .axi_awlock                         (axiA_awlock                        ),
    .axi_awcache                        (axiA_awcache                       ),
    .axi_awprot                         (axiA_awprot                        ),
    .axi_awqos                          (axiA_awqos                         ),
    .axi_awregion                       (axiA_awregion                      ),
    .axi_awvalid                        (axiA_awvalid                       ),
    .axi_awready                        (axiA_awready                       ),
    .axi_wdata                          (axiA_wdata                         ),
    .axi_wstrb                          (axiA_wstrb                         ),
    .axi_wlast                          (axiA_wlast                         ),
    .axi_wvalid                         (axiA_wvalid                        ),
    .axi_wready                         (axiA_wready                        ),
    .axi_bid                            (axiA_bid                           ),
    .axi_bresp                          (axiA_bresp                         ),
    .axi_bvalid                         (axiA_bvalid                        ),
    .axi_bready                         (axiA_bready                        ),
    .axi_arid                           (axiA_arid                          ),
    .axi_araddr                         (axiA_araddr                        ),
    .axi_arlen                          (axiA_arlen                         ),
    .axi_arsize                         (axiA_arsize                        ),
    .axi_arburst                        (axiA_arburst                       ),
    .axi_arlock                         (axiA_arlock                        ),
    .axi_arcache                        (axiA_arcache                       ),
    .axi_arprot                         (axiA_arprot                        ),
    .axi_arqos                          (axiA_arqos                         ),
    .axi_arregion                       (axiA_arregion                      ),
    .axi_arvalid                        (axiA_arvalid                       ),
    .axi_arready                        (axiA_arready                       ),
    .axi_rid                            (axiA_rid                           ),
    .axi_rdata                          (axiA_rdata                         ),
    .axi_rresp                          (axiA_rresp                         ),
    .axi_rlast                          (axiA_rlast                         ),
    .axi_rvalid                         (axiA_rvalid                        ),
    .axi_rready                         (axiA_rready                        ),
    .start_pulse                        (bitblt_start                       ),
    .cfg_src_addr                       (bitblt_src_addr                    ),
    .cfg_dst_addr                       (bitblt_dst_addr                    ),
    .cfg_width                          (bitblt_width                       ),
    .cfg_height                         (bitblt_height                      ),
    .cfg_src_stride                     (bitblt_src_stride                  ),
    .cfg_dst_stride                     (bitblt_dst_stride                  ),
    .cfg_color                          (bitblt_color                       ),
    .cfg_operation                      (bitblt_operation                   ),
    .engine_busy                        (bitblt_busy                        ),
    .engine_done                        (bitblt_done                        ),
    .engine_error                       (bitblt_error                       )
);


apb3_top u_apb3_top(
    .clk                                (user_clk                           ),
    .reset                              (!ddr_rstn                          ),
    .apb_paddr                          (apb_paddr                          ),
    .apb_psel                           (apb_psel                           ),
    .apb_penable                        (apb_penable                        ),
    .apb_pready                         (apb_pready                         ),
    .apb_pwrite                         (apb_pwrite                         ),
    .apb_pwdata                         (apb_pwdata                         ),
    .apb_prdata                         (apb_prdata                         ),
    .apb_pslverror                      (apb_pslverror                      ),
    .sig                                (sig                                )
    
);    

//***************************************************************************


//***************************************************************************

endmodule
