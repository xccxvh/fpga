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

    // ---- 板载按键（低电平按下，内部做同步 + 消抖）----
    // 注意：板子上的 KEY2/KEY3 与 b_led[0]/b_led[1] 复用 GPIOR_21/GPIOR_22，
    //       所以这里只用不冲突的 GPIOL_07 / GPIOL_03 两个键。
    input  key_prev,          // GPIOL_07  KEY1  上一张
    input  key_next,          // GPIOL_03  KEY3  下一张

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

// ============================================================
// 图片槽位 / 双缓冲
//
// DDR3 布局（每个槽位 2 MiB，一帧 1280x720 RGB565 = 1.758 MiB 放得下）：
//     槽位 0 : 0x000000       槽位 4 : 0x800000
//     槽位 1 : 0x200000       槽位 5 : 0xA00000
//     槽位 2 : 0x400000       槽位 6 : 0xC00000
//     槽位 3 : 0x600000       槽位 7 : 0xE00000
//
// 显示永远从 active_slot 读；按键 / 整帧完成只改 target_slot，
// active_slot 只在 rbeat 回绕（一帧读完）的那一刻更新 ——
// 那一刻读 FIFO 里还压着上一帧的尾巴，切换正好落在消隐期，所以不撕裂。
// ============================================================
localparam SLOT_SHIFT = 21;                  // 2 MiB
localparam SLOT_COUNT = 4;                   // 按键在这几个槽位之间循环
localparam [2:0] SLOT_LAST = 3'd3;           // = SLOT_COUNT - 1，按键回绕用

function [31:0] slot_base;
    input [2:0] s;
    begin
        slot_base = {8'd0, s, 21'd0};
    end
endfunction

reg [2:0] active_slot = 3'd0;    // HDMI 当前正在读的槽位
reg [2:0] target_slot = 3'd0;    // 期望切过去的槽位

// 控制字里的 flags 位
localparam F_START = 0;
localparam F_END   = 1;
localparam F_SWAP  = 2;
localparam F_ACK   = 3;
localparam F_DBUF  = 4;   // 双缓冲：由 FPGA 挑"当前没在显示"的那块写

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

// ------------------------------------------------------------
// 跨时钟 FIFO 的复位用原始异步复位 nrst，而不是 sys_rst_n。
//
// 为什么：sys_rst_n 是在 sys_clk 域数出来的，直接接到 WrClk=rxc 的 FIFO
// 的 Reset 上，工具就会在 sys_clk -> rxc 之间建出一条路径去做
// recovery/removal 检查，报出 -1.4ns 的负裕量（共 20 条）。
//
// 那 20 条本身是假警报 —— DC_FIFO 内部的 WrClkRstGen/RdClkRstGen 是
// 标准的"异步复位、同步释放"，源码里标了 async_reg，异步复位本来就不需要
// 满足跨时钟 setup/hold。但与其在约束文件里打补丁（试过 set_false_path 和
// set_clock_groups 两种写法，这个工具都不认），不如把复位来源改对：
// 异步复位就该来自异步输入，而不是某个无关时钟域里数出来的信号。
//
// 功能上是安全的：FIFO 的数据输出只在有写操作之后才有效，
// 而写入分别由真实收到的包(img_data_valid)和 cal_done 之后的 DDR 读触发。
// ------------------------------------------------------------
wire fifo_rst_n = nrst;

wire cal_done;
reg [31:0] awaddr = 0, araddr = 0;
reg awvalid = 0, arvalid = 0;
reg [3:0]  awlen_r = 4'd15;      // 当前写突发长度-1（尾包可能不满 16 拍）
wire awready, arready;
wire [127:0] wdata;
wire [15:0] wstrb = 16'hffff;
wire wlast = (wburst_cnt == awlen_r);
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
    .s_axi_awid(4'h1), .s_axi_awaddr(awaddr), .s_axi_awlen({4'd0, awlen_r}), .s_axi_awsize(3'd4),
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
wire [7:0]   img_slot;
wire [7:0]   img_flags;
wire [31:0]  img_pkt_hdr;      // {frame_id, packet_idx}
wire         img_fifo_ovf;     // rxc 域粘滞标志
wire         img_sof;

// ACK 请求跨时钟域（sys_clk -> gmii_tx_clk），用翻转信号 + data 握手
// 回执 24 字节：byte0 在最高位 [191:184]
reg  [191:0] ack_payload = 192'd0;
reg          ack_req_tgl = 1'b0;
wire         ack_done_tgl;
wire         arp_miss_raw;
wire         ctrl_fifo_full;   // 控制字 FIFO 写满（rxc 域）
wire         fid_fifo_full;    // frame_id/packet_idx FIFO 写满（rxc 域）

// ARP 命中 / FIFO 溢出都是慢变状态信号，两级同步即可
reg  [1:0]   arp_miss_sync = 2'b00;
reg  [1:0]   ovf_sync      = 2'b00;
always @(posedge sys_clk or negedge sys_rst_n)
    if (!sys_rst_n) begin
        arp_miss_sync <= 2'b00;
        ovf_sync      <= 2'b00;
    end else begin
        arp_miss_sync <= {arp_miss_sync[0], arp_miss_raw};
        ovf_sync      <= {ovf_sync[0], img_fifo_ovf};
    end

wire arp_miss = arp_miss_sync[1];
wire fifo_ovf = ovf_sync[1];

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
    .img_slot       (img_slot),
    .img_flags      (img_flags),
    .img_pkt_hdr    (img_pkt_hdr),
    .fifo_ovf       (img_fifo_ovf),
    .arp_miss       (arp_miss_raw),
    .img_sof        (img_sof),
    .rx_fifo_full   (rx_fifo_full),
    .ctrl_fifo_full (ctrl_fifo_full),
    .fid_fifo_full  (fid_fifo_full),
    .ack_tgl        (ack_req_tgl),
    .ack_payload    (ack_payload),
    .ack_done_tgl   (ack_done_tgl)
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
    .Reset(!fifo_rst_n), .WrClk(rxc), .WrEn(img_data_valid),
    .WrDNum(rx_fifo_wr_count), .WrFull(rx_fifo_full), .WrData(img_data),
    .RdClk(sys_clk), .RdEn(rx_fifo_rd_en),
    .RdDNum(), .RdEmpty(rx_fifo_empty), .DataVal(rx_fifo_dataval), .RdData(rx_fifo_rdata)
);

// 控制字（每个包一个，与数据 FIFO 严格同序）：
//   [63:32] byte_offset / START 时是本帧总字节数 / END 时是实发包数
//   [31:16] payload_len（0 表示这是 START/END 控制包，没有数据）
//   [15:8]  slot
//   [7:0]   flags
DC_FIFO #(.FIFO_MODE("Normal"), .DATA_WIDTH(64), .FIFO_DEPTH(32)) u_ctrl_fifo (
    .Reset(!fifo_rst_n), .WrClk(rxc), .WrEn(img_sof),
    .WrDNum(), .WrFull(ctrl_fifo_full), .WrData({img_byte_offset, img_payload_len, img_slot, img_flags}),
    .RdClk(sys_clk), .RdEn(ctrl_fifo_rd_en),
    .RdDNum(), .RdEmpty(ctrl_fifo_empty), .DataVal(ctrl_fifo_dataval), .RdData(ctrl_fifo_rdata)
);

// {frame_id, packet_idx} 单开一路 FIFO：控制字 64 bit 已经排满，塞不下了。
// 写使能和读使能都与 u_ctrl_fifo 完全一致，所以两者永远同步。
// 有了 packet_idx，上层才能查断号/重复/串帧 —— 光比字节数是不够的：
// "丢一个包又重复另一个包"字节数照样对得上。
wire [31:0] fid_fifo_rdata;
wire        fid_fifo_dataval;
reg         fid_fifo_rd_en;

DC_FIFO #(.FIFO_MODE("Normal"), .DATA_WIDTH(32), .FIFO_DEPTH(32)) u_fid_fifo (
    .Reset(!fifo_rst_n), .WrClk(rxc), .WrEn(img_sof),
    .WrDNum(), .WrFull(fid_fifo_full), .WrData(img_pkt_hdr),
    .RdClk(sys_clk), .RdEn(fid_fifo_rd_en),
    .RdDNum(), .RdEmpty(), .DataVal(fid_fifo_dataval), .RdData(fid_fifo_rdata)
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
reg [3:0]  wburst_len;     // 当前 burst 的 awlen（支持末尾不满 16 拍的包）

// 整帧统计：START 声明总长 -> 逐包累加 -> END 比对
reg [31:0] rx_bytes;       // 本帧已写进 DDR 的字节数
reg [31:0] frame_expect;   // START 声明的本帧总字节数
reg [31:0] frame_rx;       // END 到来时锁存的 rx_bytes
reg [15:0] frame_id_cur;
reg [2:0]  frame_wslot;    // 本帧实际写入的槽位（START 时锁定，后面不再变）
reg        frame_swap;
reg        frame_ack;
reg        frame_done;     // 单拍：整帧完成
reg        frame_seq_err;  // packet_idx 断号/重复，或 frame_id 与 START 不一致
reg [15:0] exp_idx;        // 本帧期望的下一个 packet_idx

// 帧校验和：对真正进 DDR 的每一个 128-bit 字累加。
// 目的不是抗信道误码（以太网 FCS 已经覆盖了，坏帧在 MAC 层就被丢了），
// 而是查 FPGA 这边的写入路径 —— 槽位基地址算错、AXI 写偏、FIFO 溢出后错位，
// 这类错误字节数照样对得上，只有校验和能看出来。
reg [63:0]  ck_sum;
reg [127:0] ck_xor;

wire [15:0] ctrl_len   = ctrl_fifo_rdata[31:16];
wire [15:0] ctrl_beats = ctrl_len >> 4;      // 本包一共多少拍

// 剩余不足 16 拍时收短 burst，避免尾包被丢掉
wire [3:0] burst_len_next  = (wbeats >= 16) ? 4'd15 : (wbeats[3:0] - 4'd1);
// 本包第一拍的长度必须直接用 ctrl_len 算：这一刻 wbeats 还是上一个包的值
wire [3:0] first_burst_len = (ctrl_beats >= 16) ? 4'd15 : (ctrl_beats[3:0] - 4'd1);

assign rx_fifo_rd_en = (wstate == W_WD) && (rx_fifo_dataval ? wready : 1'b1);
assign fid_fifo_rd_en = ctrl_fifo_rd_en;    // 与控制字同进同出

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        wstate <= W_IDLE; waddr <= 0; wbeats <= 0; wburst_cnt <= 0;
        wburst_len <= 4'd15; awlen_r <= 4'd15;
        awvalid <= 0; bready <= 0; ctrl_fifo_rd_en <= 0;
        rx_bytes <= 0; frame_expect <= 0; frame_rx <= 0; frame_id_cur <= 0;
        frame_wslot <= 0; frame_swap <= 0; frame_ack <= 0; frame_done <= 0;
        frame_seq_err <= 0; exp_idx <= 0; ck_sum <= 0; ck_xor <= 0;
    end else begin
        bready <= 0; ctrl_fifo_rd_en <= 0; frame_done <= 0;
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
                    if (ctrl_len < 16'd16) begin
                        // ---- 无数据：START / END 控制包 ----
                        // 长度 0<len<16 的畸形包也落在这里，因为 flags 匹配不上，
                        // 会被直接忽略 —— 好过拿垃圾去写 DDR。
                        if (ctrl_fifo_rdata[F_START]) begin
                            frame_expect <= ctrl_fifo_rdata[63:32];
                            frame_id_cur <= fid_fifo_rdata[31:16];

                            // DBUF：写到"当前没在显示"的那一块。
                            // 这个判断必须由 FPGA 做 —— PC 不知道板子现在显示
                            // 哪个槽位，本地记状态在重启/按过键之后就是错的。
                            // 槽位在 START 就锁死，本帧所有包都写同一块。
                            frame_wslot  <= ctrl_fifo_rdata[F_DBUF]
                                            ? (active_slot ^ 3'd1)
                                            : ctrl_fifo_rdata[10:8];
                            // DBUF 隐含"写完就切过去"，否则双缓冲没有意义
                            frame_swap   <= ctrl_fifo_rdata[F_SWAP]
                                            | ctrl_fifo_rdata[F_DBUF];
                            frame_ack    <= ctrl_fifo_rdata[F_ACK];

                            rx_bytes      <= 32'd0;
                            exp_idx       <= 16'd0;
                            frame_seq_err <= 1'b0;
                            ck_sum        <= 64'd0;
                            ck_xor        <= 128'd0;
                        end
                        else if (ctrl_fifo_rdata[F_END]) begin
                            // 能走到这里，说明本帧所有 DATA 包都已经写完 DDR
                            frame_rx   <= rx_bytes;
                            // END 的 frame_id 也必须和 START 一致，
                            // 否则是两个发送程序在往同一个槽位里交错写
                            if (fid_fifo_rdata[31:16] != frame_id_cur)
                                frame_seq_err <= 1'b1;
                            frame_done <= 1'b1;
                        end
                        wstate <= W_IDLE;
                    end
                    else begin
                        // ---- 普通数据包 ----
                        // 查断号/重复：字节数对得上不代表包收全了，
                        // "丢一个包又重复另一个"字节数照样相等。
                        if (fid_fifo_rdata[15:0] != exp_idx)
                            frame_seq_err <= 1'b1;
                        if (fid_fifo_rdata[31:16] != frame_id_cur)
                            frame_seq_err <= 1'b1;
                        exp_idx <= exp_idx + 16'd1;

                        waddr      <= slot_base(frame_wslot)
                                      + ctrl_fifo_rdata[63:32];
                        wbeats     <= ctrl_beats;
                        wburst_len <= first_burst_len;
                        rx_bytes   <= rx_bytes + {16'd0, ctrl_len};
                        wstate     <= W_WA;
                    end
                end
            end
            W_WA: begin
                // AXI VALID 必须保持到 VALID && READY 真正握手。
                if (!awvalid) begin
                    awaddr  <= waddr;
                    awlen_r <= wburst_len;
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

                    // 帧校验和：对真正进 DDR 的 128-bit 字累加。
                    // 加法在 64 位上自然溢出回绕，XOR 折叠全部 128 位 ——
                    // PC 端按同样口径算，两边必须一致。
                    ck_sum <= ck_sum + {32'd0, wdata[63:0]}
                                     + {32'd0, wdata[127:64]};
                    ck_xor <= ck_xor ^ wdata;

                    if (wburst_cnt == awlen_r) begin
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
                    else begin
                        wburst_len <= burst_len_next;
                        wstate <= W_WA;
                    end
                end
            end
            default: wstate <= W_IDLE;
        endcase
    end
end

// ============================================================
// 读状态机：循环读 framebuffer → 读回 FIFO → HDMI
// ============================================================
localparam R_IDLE=0, R_RA=1, R_RD=2, R_DRAIN=3;

reg [2:0]  rstate;
reg [16:0] rbeat;

wire        fifo_full;
wire [9:0]  fifo_wr_count;
wire fifo_write = (rstate == R_RD) && rvalid && rready;
assign rready = (rstate == R_RD) && !fifo_full;

// 显示基地址只在整帧读完后才更新。此刻读 FIFO 里还压着上一帧末尾的
// 几行数据，屏幕正在消隐区，所以切屏不会被看见。
wire [31:0] active_base = slot_base(active_slot);
wire        rwrap = (rbeat + 16 >= FRAME_BEATS);

// ------------------------------------------------------------
// 帧边界对齐（R_DRAIN 状态用）
//
// 问题：读状态机是自由跑的，显示端按固定 115200 字/帧消费，两者之间只有
// 读 FIFO 缓冲，没有任何对齐机制。读状态机回绕的那一刻，FIFO 里还压着 K 个
// 字没被取走 —— 这 K 个字就是画面错位量。因为一个字 = 8 像素、一行 = 160 字：
//     水平偏移 = (8K mod 1280) 像素，垂直偏移 = floor(K/160) 行
// 表现就是"画面往右下移，移出去的部分从左上绕回来"。
//
// 修法：回绕后不进 R_RA，先停在 R_DRAIN，等显示端走到**消隐期的开头**
// （hcnt==0 && vcnt==V_ACTIVE，也就是最后一个有效像素之后）。那一刻：
//   ① 上一帧的字正好被取空，错位量归零；
//   ② 后面还有 V_TOTAL-V_ACTIVE = 30 行消隐，够读状态机从 DDR 预取。
// 之后每帧都这样对齐一次，所以是自校正的，不会累积漂移。
//
// 为什么不能对齐到 vcnt==0（有效画面第一行）：那是显示端立刻要数据的时刻，
// 而 AXI 读延迟约 250ns ≈ 19 个像素。第 0 行开头会饿死变黑，这一行少消费的
// 像素会让整帧字相位错开 —— 上下能对上，左右仍然偏。
// ------------------------------------------------------------
reg        frame_tgl = 1'b0;      // 像素域：每个消隐期开头翻转一次
always @(posedge hdmi_rx_slow_clk or negedge hdmi_rx_pll_LOCKED)
    if (!hdmi_rx_pll_LOCKED) frame_tgl <= 1'b0;
    else if (hcnt == 0 && vcnt == V_ACTIVE) frame_tgl <= ~frame_tgl;

// 翻转信号跨到 sys_clk，用翻转而不是脉冲：脉冲只有 1 个像素时钟宽，
// 打两拍可能漏掉，翻转不会。
reg [1:0] ftgl_sync = 2'b00;
reg       ftgl_sync_d = 1'b0;
always @(posedge sys_clk or negedge sys_rst_n)
    if (!sys_rst_n) begin
        ftgl_sync   <= 2'b00;
        ftgl_sync_d <= 1'b0;
    end else begin
        ftgl_sync   <= {ftgl_sync[0], frame_tgl};
        ftgl_sync_d <= ftgl_sync[1];
    end

wire frame_tick_sys = ftgl_sync[1] ^ ftgl_sync_d;   // sys_clk 域单拍

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        rstate <= R_IDLE; rbeat <= 0; arvalid <= 0; active_slot <= 3'd0;
    end else begin
        case (rstate)
            R_IDLE: begin
                arvalid <= 0;
                if (cal_done) rstate <= R_RA;
            end
            R_RA: begin
                // 与写地址通道一样，保持 VALID 直到完整握手。
                if (!arvalid) begin
                    araddr  <= active_base + {7'd0, rbeat, 4'd0};
                    arvalid <= 1;
                end
                if (arvalid && arready) begin arvalid <= 0; rstate <= R_RD; end
            end
            R_RD: if (rvalid && rready && rlast) begin
                if (rwrap) begin
                    rbeat <= 0;
                    // 一帧读完 = 消隐期，在这里换槽位
                    if (active_slot != target_slot) active_slot <= target_slot;
                    rstate <= R_DRAIN;   // 先等对齐，别急着读下一帧
                end
                else begin
                    rbeat  <= rbeat + 16;
                    rstate <= R_RA;
                end
            end
            // 等显示端走到帧开头。这一刻 FIFO 里上一帧的数据正好被取空，
            // 从这里接着读，显示端拿到的第一个字就是新帧的第 0 个字。
            R_DRAIN: begin
                arvalid <= 0;
                if (frame_tick_sys) rstate <= R_RA;
            end
            default: rstate <= R_IDLE;
        endcase
    end
end

// ============================================================
// 板载按键：两级同步 + 消抖 + 按下单拍脉冲
//
// 按键低电平有效。sys_clk 周期 9.26ns，2^21 拍 ≈ 19ms 消抖窗口。
// ============================================================
localparam [20:0] DEBOUNCE_MAX = 21'h1F_FFFF;

reg [1:0]  kp_sync = 2'b11, kn_sync = 2'b11;
reg [20:0] kp_cnt = 21'd0, kn_cnt = 21'd0;
reg        kp_stable = 1'b1, kn_stable = 1'b1;
reg        kp_stable_d = 1'b1, kn_stable_d = 1'b1;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        kp_sync <= 2'b11; kn_sync <= 2'b11;
        kp_cnt <= 21'd0; kn_cnt <= 21'd0;
        kp_stable <= 1'b1; kn_stable <= 1'b1;
        kp_stable_d <= 1'b1; kn_stable_d <= 1'b1;
    end else begin
        kp_sync <= {kp_sync[0], key_prev};
        kn_sync <= {kn_sync[0], key_next};

        if (kp_sync[1] != kp_stable) begin
            if (kp_cnt == DEBOUNCE_MAX) begin
                kp_stable <= kp_sync[1];
                kp_cnt    <= 21'd0;
            end else kp_cnt <= kp_cnt + 1'b1;
        end else kp_cnt <= 21'd0;

        if (kn_sync[1] != kn_stable) begin
            if (kn_cnt == DEBOUNCE_MAX) begin
                kn_stable <= kn_sync[1];
                kn_cnt    <= 21'd0;
            end else kn_cnt <= kn_cnt + 1'b1;
        end else kn_cnt <= 21'd0;

        kp_stable_d <= kp_stable;
        kn_stable_d <= kn_stable;
    end
end

wire key_prev_press = kp_stable_d & ~kp_stable;   // 1 -> 0 跳变那一拍
wire key_next_press = kn_stable_d & ~kn_stable;

// ============================================================
// 槽位切换：按键优先，其次是整帧完成后的自动切屏
// ============================================================
// 字节数对上 != 收全了：还要没有断号/重复，也没有 FIFO 溢出丢拍。
// frame_ok 同时用来门控切屏 —— 宁可这一帧不显示，也不要显示半张残图。
wire frame_bytes_ok = (frame_expect != 32'd0) && (frame_rx == frame_expect);
wire frame_ok       = frame_bytes_ok && !frame_seq_err && !fifo_ovf;

// 校验和折叠到 32 位（PC 端按同样口径算）
wire [31:0] ck_sum32 = ck_sum[31:0] ^ ck_sum[63:32];
wire [31:0] ck_xor32 = ck_xor[31:0] ^ ck_xor[63:32]
                     ^ ck_xor[95:64] ^ ck_xor[127:96];

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) target_slot <= 3'd0;
    else if (key_prev_press)
        target_slot <= (target_slot == 3'd0) ? SLOT_LAST : target_slot - 3'd1;
    else if (key_next_press)
        target_slot <= (target_slot == SLOT_LAST) ? 3'd0 : target_slot + 3'd1;
    else if (frame_done && frame_swap && frame_ok)
        target_slot <= frame_wslot;
end

// ============================================================
// 回执：整帧完成后请求一次；必须等上一条发完才允许发下一条
// （ack_payload 在 ack_req_tgl 翻转期间保持稳定，这是 data+toggle 握手）
// ============================================================
reg [1:0] done_sync = 2'b00;
reg       done_sync_d = 1'b0;
reg       ack_busy = 1'b0;

wire ack_done_pulse = done_sync[1] ^ done_sync_d;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        done_sync <= 2'b00; done_sync_d <= 1'b0;
        ack_busy <= 1'b0; ack_req_tgl <= 1'b0;
    end else begin
        done_sync   <= {done_sync[0], ack_done_tgl};
        done_sync_d <= done_sync[1];

        if (ack_done_pulse) ack_busy <= 1'b0;

        if (frame_done && frame_ack && !ack_busy && !ack_done_pulse) begin
            // 24 字节：byte0 落在最高位，udp_ack_tx 从 [191:184] 开始往外移
            ack_payload <= {
                16'hA55B,                       // [191:176] magic
                frame_id_cur,                   // [175:160] 帧号
                frame_rx,                       // [159:128] 实际写入字节数
                frame_expect,                   // [127:96]  声明总字节数
                {5'd0, frame_wslot},            // [95:88]   本帧实际写入的槽位
                // [87:80] 状态：bit0 帧完整 bit1 DDR校准完 bit2 ARP未命中
                //                bit3 断号/串帧 bit4 FIFO溢出 bit5 保留
                {3'd0, fifo_ovf, frame_seq_err, arp_miss, cal_done, frame_ok},
                {5'd0, active_slot},            // [79:72]   回执这一刻的显示槽位
                8'd0,                           // [71:64]   保留
                ck_sum32,                       // [63:32]   帧校验和（加）
                ck_xor32                        // [31:0]    帧校验和（异或）
            };
            ack_req_tgl <= ~ack_req_tgl;
            ack_busy    <= 1'b1;
        end
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
    .Reset(!fifo_rst_n), .WrClk(sys_clk), .WrEn(fifo_write), .WrDNum(fifo_wr_count),
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
