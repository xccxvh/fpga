`timescale 1ns/1ps
`include "ddr3_controller.vh"

module ddr3_hdmi_test (
    input nrst,
    input clk_25m,
    input sys_clk,
    input core_clk,
    input tac_clk,
    input twd_clk,
    input tdqss_clk,
    input DDR3_PLL_LOCK,
    input SYS_PLL_LOCK,
    input hdmi_rx_pll_LOCKED,
    input hdmi_rx_slow_clk,
    input jtag_inst1_TDI,
    output jtag_inst1_TDO,

    output DDR3_PLL_RSTN,
    output SYS_PLL_RSTN,
    output hdmi_rx_pll_RSTN,
    output hdmi_rx_d0_RX_RST,
    output hdmi_rx_d1_RX_RST,
    output hdmi_rx_d2_RX_RST,

    output reset, output cs, output ras, output cas, output we, output cke,
    output [15:0] addr, output [2:0] ba, output odt,
    output [1:0] o_dm_hi, output [1:0] o_dm_lo,
    input [15:0] i_dq_hi, input [15:0] i_dq_lo,
    output [15:0] o_dq_hi, output [15:0] o_dq_lo, output [15:0] o_dq_oe,
    input [1:0] i_dqs_hi, input [1:0] i_dqs_lo,
    output [1:0] o_dqs_hi, output [1:0] o_dqs_lo,
    output [1:0] o_dqs_oe, output [1:0] o_dqs_n_oe,
    output [2:0] shift, output [4:0] shift_sel, output shift_ena,

    output tmds_tx_clk_TX_OE, output [9:0] tmds_tx_clk_TX_DATA, output tmds_tx_clk_TX_RST,
    output tmds_tx_data0_TX_OE, output [9:0] tmds_tx_data0_TX_DATA, output tmds_tx_data0_TX_RST,
    output tmds_tx_data1_TX_OE, output [9:0] tmds_tx_data1_TX_DATA, output tmds_tx_data1_TX_RST,
    output tmds_tx_data2_TX_OE, output [9:0] tmds_tx_data2_TX_DATA, output tmds_tx_data2_TX_RST,
    output [1:0] b_led,

    // ---- GE 时钟 PLL（从 rxc 派生 TX 时钟）----
    input         ge_0_gclk_pll_LOCKED,
    output        ge_rx_pll_RSTN,

    // ---- 千兆以太网（RGMII，来自 PHY）----
    input         rxc,
    input         rx_dv,
    input         rx_dv_LO,
    input  [3:0]  rxd_hi_i,
    input  [3:0]  rxd_lo_i,
    output        phy_rst_n,
    output        mdc_o_HI,
    output        mdc_o_LO,
    input         mdio_i,
    output        mdio_o,
    output        mdio_oe,
    output        tx_en_o_HI,
    output        tx_en_o_LO,
    output        txc_hi_o,
    output        txc_lo_o,
    output [3:0]  txd_hi_o,
    output [3:0]  txd_lo_o
);

localparam H_ACTIVE = 1280, H_FP = 110, H_SYNC = 40, H_BP = 220, H_TOTAL = 1650;
localparam V_ACTIVE = 720,  V_FP = 5,   V_SYNC = 5,  V_BP = 20,  V_TOTAL = 750;
localparam BEATS_PER_LINE = H_ACTIVE/8;
localparam FRAME_BEATS = BEATS_PER_LINE*V_ACTIVE;

assign DDR3_PLL_RSTN = nrst;
assign SYS_PLL_RSTN = nrst;
assign hdmi_rx_pll_RSTN = nrst;
assign hdmi_rx_d0_RX_RST = 1'b0;
assign hdmi_rx_d1_RX_RST = 1'b0;
assign hdmi_rx_d2_RX_RST = 1'b0;
assign jtag_inst1_TDO = jtag_inst1_TDI;

reg [7:0] rst_count = 0;
always @(posedge sys_clk or negedge nrst)
    if (!nrst || !DDR3_PLL_LOCK || !SYS_PLL_LOCK) rst_count <= 0;
    else if (!(&rst_count)) rst_count <= rst_count + 1'b1;
wire sys_rst_n = &rst_count;

wire cal_done;
reg [31:0] awaddr = 0, araddr = 0;
reg awvalid = 0, arvalid = 0;
wire awready, arready;
wire [127:0] wdata;
wire [15:0] wstrb = 16'hffff;
wire wlast = (wburst_cnt == 15);
wire wvalid = rx_fifo_dataval && (wstate == W_WD);
wire wready;
wire [3:0] bid, rid;
wire [1:0] bresp, rresp;
wire bvalid;
reg bready = 0;
wire [127:0] rdata;
wire rlast, rvalid;
wire rready;

assign addr[15:14]=2'b0;
ddr3_top u_ddr3 (
    .axi_clk(sys_clk), .core_clk(sys_clk), .sdram_clk(tdqss_clk),
    .rx_cal_clk(tac_clk), .tx_cal_clk(tdqss_clk), .tx_cal_clk_90edge(twd_clk), .rstn(sys_rst_n),
    .pll_shift(shift), .pll_shift_sel(shift_sel), .pll_shift_ena(shift_ena),
    .ddr_ck_hi(), .ddr_ck_lo(), .ddr_reset_n(reset), .ddr_cke(cke), .ddr_addr(addr[13:0]),
    .ddr_ba(ba), .ddr_cas_n(cas), .ddr_cs_n(cs), .ddr_ras_n(ras), .ddr_we_n(we),
    .ddr_dqs_in_hi(i_dqs_hi), .ddr_dqs_in_lo(i_dqs_lo), .ddr_dq_in_hi(i_dq_hi), .ddr_dq_in_lo(i_dq_lo),
    .ddr_dqs_oe(o_dqs_oe), .ddr_dqs_oe_n(o_dqs_n_oe), .ddr_dq_oe(o_dq_oe),
    .ddr_dqs_out_hi(o_dqs_hi), .ddr_dqs_out_lo(o_dqs_lo),
    .ddr_dq_out_hi(o_dq_hi), .ddr_dq_out_lo(o_dq_lo), .ddr_dm_hi(o_dm_hi), .ddr_dm_lo(o_dm_lo), .ddr_odt(odt),
    .app_sr_req(1'b0), .app_ref_req(1'b0), .app_zq_req(1'b0), .app_sr_active(), .app_ref_ack(), .app_zq_ack(),
    .s_axi_awid(4'h1), .s_axi_awaddr(awaddr), .s_axi_awlen(8'd15), .s_axi_awsize(3'd4),
    .s_axi_awburst(2'b01), .s_axi_awlock(1'b0), .s_axi_awcache(4'b0), .s_axi_awprot(3'b0), .s_axi_awqos(4'b0),
    .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wlast(wlast), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
    .s_axi_bid(bid), .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
    .s_axi_arid(4'h2), .s_axi_araddr(araddr), .s_axi_arlen(8'd15), .s_axi_arsize(3'd4),
    .s_axi_arburst(2'b01), .s_axi_arlock(1'b0), .s_axi_arcache(4'b0), .s_axi_arprot(3'b0), .s_axi_arqos(4'b0),
    .s_axi_arvalid(arvalid), .s_axi_arready(arready),
    .s_axi_rid(rid), .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rlast(rlast), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
    .wrlvl_dq_check(), .rd_level_dqs_check(), .init_cur_state(), .idelay_ld(), .mpr_rdlvl_dly(), .cal_done(cal_done)
);

// ============================================================
// UDP 图片接收（RGMII -> GMII -> MAC -> UDP -> 128-bit 数据）
// ============================================================

wire [127:0] img_data;
wire         img_data_valid;
wire [31:0]  img_byte_offset;
wire [15:0]  img_payload_len;
wire         img_sof;

udp_img_rx u_udp_img_rx (
    .rst_n          (nrst),
    .rxc            (rxc),
    .rxd_hi_i       (rxd_hi_i),
    .rxd_lo_i       (rxd_lo_i),
    .rx_dv_HI       (rx_dv),
    .rx_dv_LO       (rx_dv_LO),
    .tx_en_o_HI     (tx_en_o_HI),
    .tx_en_o_LO     (tx_en_o_LO),
    .txd_hi_o       (txd_hi_o),
    .txd_lo_o       (txd_lo_o),
    .mdc_o          (),
    .mdio_o         (mdio_o),
    .mdio_oe        (mdio_oe),
    .mdio_i         (mdio_i),
    .phy_rst_n      (phy_rst_n),
    .img_data       (img_data),
    .img_data_valid (img_data_valid),
    .img_byte_offset(img_byte_offset),
    .img_payload_len(img_payload_len),
    .img_sof        (img_sof)
);

assign txc_hi_o = 1'b1;   // RGMII TX 时钟（固定电平，见 demo4）
assign txc_lo_o = 1'b0;
assign mdc_o_HI = 1'b0;   // 本版不配置 MDIO
assign mdc_o_LO = 1'b0;
assign ge_rx_pll_RSTN = 1'b1;   // 不复位 GE PLL

// 跨时钟域 FIFO（gmii_rx_clk = rxc -> sys_clk）
wire [127:0] rx_fifo_rdata;
wire         rx_fifo_dataval;
wire         rx_fifo_empty;
wire         rx_fifo_full;
wire [9:0]   rx_fifo_wr_count;
reg          rx_fifo_rd_en;

wire [63:0]  ctrl_fifo_rdata;
wire         ctrl_fifo_dataval;
wire         ctrl_fifo_empty;
reg          ctrl_fifo_rd_en;

DC_FIFO #(.FIFO_MODE("Normal"), .DATA_WIDTH(128), .FIFO_DEPTH(512)) u_rx_fifo (
    .Reset(!sys_rst_n), .WrClk(rxc), .WrEn(img_data_valid),
    .WrDNum(rx_fifo_wr_count), .WrFull(rx_fifo_full), .WrData(img_data),
    .RdClk(sys_clk), .RdEn(rx_fifo_rd_en),
    .RdDNum(), .RdEmpty(rx_fifo_empty), .DataVal(rx_fifo_dataval), .RdData(rx_fifo_rdata)
);

DC_FIFO #(.FIFO_MODE("Normal"), .DATA_WIDTH(64), .FIFO_DEPTH(32)) u_ctrl_fifo (
    .Reset(!sys_rst_n), .WrClk(rxc), .WrEn(img_sof),
    .WrDNum(), .WrFull(), .WrData({img_byte_offset, img_payload_len, 16'h0}),
    .RdClk(sys_clk), .RdEn(ctrl_fifo_rd_en),
    .RdDNum(), .RdEmpty(ctrl_fifo_empty), .DataVal(ctrl_fifo_dataval), .RdData(ctrl_fifo_rdata)
);

assign wdata = rx_fifo_rdata;

// ============================================================
// 写状态机：UDP 数据 → DDR3（按 byte_offset 写）
// ============================================================
localparam W_IDLE=0, W_CTRL=1, W_WA=2, W_WD=3, W_WB=4;

reg [2:0]  wstate;
reg [31:0] waddr;          // 字节地址（16 字节对齐）
reg [15:0] wbeats;         // 当前包剩余 beats
reg [4:0]  wburst_cnt;     // 当前 burst 内已写 beats

assign rx_fifo_rd_en = (wstate == W_WD) && (rx_fifo_dataval ? wready : 1'b1);

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        wstate <= W_IDLE; waddr <= 0; wbeats <= 0; wburst_cnt <= 0;
        awvalid <= 0; bready <= 0; ctrl_fifo_rd_en <= 0;
    end else begin
        bready <= 0; ctrl_fifo_rd_en <= 0;
        case (wstate)
            W_IDLE: begin
                awvalid <= 0;
                if (cal_done && !ctrl_fifo_empty) begin
                    ctrl_fifo_rd_en <= 1;
                    wstate <= W_CTRL;
                end
            end
            W_CTRL: begin
                if (ctrl_fifo_dataval) begin
                    waddr  <= ctrl_fifo_rdata[63:32];          // byte_offset
                    wbeats <= ctrl_fifo_rdata[31:16] >> 4;     // payload_len/16
                    wstate <= W_WA;
                end
            end
            W_WA: begin
                // AXI VALID 必须保持到 VALID && READY 真正握手。
                if (!awvalid) begin
                    awaddr <= waddr;
                    awvalid <= 1;
                end
                if (awvalid && awready) begin
                    awvalid <= 0;
                    wburst_cnt <= 0;
                    wstate <= W_WD;
                end
            end
            W_WD: begin
                if (wvalid && wready) begin
                    wburst_cnt <= wburst_cnt + 1;
                    wbeats <= wbeats - 1;
                    waddr <= waddr + 16;
                    if (wburst_cnt == 15) begin
                        bready <= 1;
                        wstate <= W_WB;
                    end
                end
            end
            W_WB: begin
                bready <= 1;
                if (bvalid) begin
                    bready <= 0;
                    if (wbeats == 0) wstate <= W_IDLE;
                    else wstate <= W_WA;
                end
            end
            default: wstate <= W_IDLE;
        endcase
    end
end

// ============================================================
// 读状态机：循环读 framebuffer → 读回 FIFO → HDMI
// ============================================================
localparam R_IDLE=0, R_RA=1, R_RD=2;

reg [1:0]  rstate;
reg [16:0] rbeat;

wire        fifo_full;
wire [9:0]  fifo_wr_count;
wire fifo_write = (rstate == R_RD) && rvalid && rready;
assign rready = (rstate == R_RD) && !fifo_full;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        rstate <= R_IDLE; rbeat <= 0; arvalid <= 0;
    end else begin
        case (rstate)
            R_IDLE: begin
                arvalid <= 0;
                if (cal_done) rstate <= R_RA;
            end
            R_RA: begin
                // 与写地址通道一样，保持 VALID 直到完整握手。
                if (!arvalid) begin
                    araddr <= rbeat << 4;
                    arvalid <= 1;
                end
                if (arvalid && arready) begin arvalid <= 0; rstate <= R_RD; end
            end
            R_RD: if (rvalid && rready && rlast) begin
                if (rbeat + 16 >= FRAME_BEATS) rbeat <= 0;
                else rbeat <= rbeat + 16;
                rstate <= R_RA;
            end
            default: rstate <= R_IDLE;
        endcase
    end
end

reg [11:0] hcnt=0;
reg [9:0] vcnt=0;
wire video_de = (hcnt < H_ACTIVE) && (vcnt < V_ACTIVE);
wire video_hs = (hcnt >= H_ACTIVE+H_FP) && (hcnt < H_ACTIVE+H_FP+H_SYNC);
wire video_vs = (vcnt >= V_ACTIVE+V_FP) && (vcnt < V_ACTIVE+V_FP+V_SYNC);
wire frame_tick = (hcnt==0 && vcnt==0);

always @(posedge hdmi_rx_slow_clk or negedge hdmi_rx_pll_LOCKED)
    if (!hdmi_rx_pll_LOCKED) begin hcnt<=0; vcnt<=0; end
    else if (hcnt==H_TOTAL-1) begin hcnt<=0; if (vcnt==V_TOTAL-1) vcnt<=0; else vcnt<=vcnt+1'b1; end
    else hcnt<=hcnt+1'b1;

reg display_active = 0;
wire [9:0] fifo_rd_count;
always @(posedge hdmi_rx_slow_clk or negedge hdmi_rx_pll_LOCKED) begin
    if (!hdmi_rx_pll_LOCKED) display_active <= 0;
    else if (fifo_rd_count > 64) display_active <= 1;
end

wire [127:0] fifo_rdata;
wire fifo_empty, fifo_dataval;
reg fifo_rd_en=0;
DC_FIFO #(.FIFO_MODE("Normal"),.DATA_WIDTH(128),.FIFO_DEPTH(512)) u_fifo (
    .Reset(!sys_rst_n), .WrClk(sys_clk), .WrEn(fifo_write), .WrDNum(fifo_wr_count),
    .WrFull(fifo_full), .WrData(rdata), .RdClk(hdmi_rx_slow_clk), .RdEn(fifo_rd_en),
    .RdDNum(fifo_rd_count), .RdEmpty(fifo_empty), .DataVal(fifo_dataval), .RdData(fifo_rdata)
);

reg [127:0] cur_word=0, next_word=0;
reg cur_valid=0, next_valid=0, fifo_pending=0;
reg [2:0] subpixel=0;
always @(posedge hdmi_rx_slow_clk or negedge hdmi_rx_pll_LOCKED) begin
    if (!hdmi_rx_pll_LOCKED) begin
        fifo_rd_en<=0; fifo_pending<=0; cur_valid<=0; next_valid<=0; subpixel<=0;
    end else begin
        fifo_rd_en<=0;
        if (display_active && !fifo_empty && !fifo_pending && (!cur_valid || !next_valid)) begin
            fifo_rd_en<=1; fifo_pending<=1;
        end
        if (fifo_dataval) begin
            fifo_pending<=0;
            if (!cur_valid) begin cur_word<=fifo_rdata; cur_valid<=1; subpixel<=0; end
            else begin next_word<=fifo_rdata; next_valid<=1; end
        end
        if (video_de && display_active && cur_valid) begin
            if (subpixel==7) begin
                subpixel<=0;
                if (next_valid) begin cur_word<=next_word; next_valid<=0; cur_valid<=1; end
                else cur_valid<=0;
            end else begin cur_word<=cur_word>>16; subpixel<=subpixel+1'b1; end
        end
    end
end

wire [15:0] rgb565 = (display_active && cur_valid) ? cur_word[15:0] : 16'h0000;
wire [7:0] red   = {rgb565[15:11],rgb565[15:13]};
wire [7:0] green = {rgb565[10:5],rgb565[10:9]};
wire [7:0] blue  = {rgb565[4:0],rgb565[4:2]};
wire [9:0] tmds0,tmds1,tmds2,tmdsc;
dvi_encoder u_tx (
    .pixelclk(hdmi_rx_slow_clk), .rstin(!hdmi_rx_pll_LOCKED),
    .blue_din(blue), .green_din(green), .red_din(red),
    .hsync(video_hs), .vsync(video_vs), .de(video_de),
    .tmds_data0(tmds0), .tmds_data1(tmds1), .tmds_data2(tmds2), .tmds_clk(tmdsc)
);
assign tmds_tx_clk_TX_DATA=~tmdsc; assign tmds_tx_data0_TX_DATA=~tmds0;
assign tmds_tx_data1_TX_DATA=~tmds1; assign tmds_tx_data2_TX_DATA=~tmds2;
assign tmds_tx_clk_TX_OE=1; assign tmds_tx_data0_TX_OE=1;
assign tmds_tx_data1_TX_OE=1; assign tmds_tx_data2_TX_OE=1;
assign tmds_tx_clk_TX_RST=0; assign tmds_tx_data0_TX_RST=0;
assign tmds_tx_data1_TX_RST=0; assign tmds_tx_data2_TX_RST=0;
assign b_led[0]=cal_done;
assign b_led[1]=display_active;

endmodule
