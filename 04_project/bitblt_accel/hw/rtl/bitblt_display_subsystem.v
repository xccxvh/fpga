`timescale 1ns/1ps

// SYSTEM_AXI_A control-plane integration for BitBlt and framebuffer display.
// The full CPU address is decoded before either register bank sees AXI valid.
module bitblt_display_subsystem (
    input user_clk, input pixel_clk, input resetn,
    output axi_interrupt,
    input [7:0] s_awid, input [31:0] s_awaddr,
    input [7:0] s_awlen, input [2:0] s_awsize,
    input [1:0] s_awburst, input s_awlock,
    input [3:0] s_awcache, input [2:0] s_awprot,
    input [3:0] s_awqos, input [3:0] s_awregion,
    input s_awvalid, output s_awready,
    input [31:0] s_wdata, input [3:0] s_wstrb,
    input s_wlast, input s_wvalid, output s_wready,
    output [7:0] s_bid, output [1:0] s_bresp,
    output s_bvalid, input s_bready,
    input [7:0] s_arid, input [31:0] s_araddr,
    input [7:0] s_arlen, input [2:0] s_arsize,
    input [1:0] s_arburst, input s_arlock,
    input [3:0] s_arcache, input [2:0] s_arprot,
    input [3:0] s_arqos, input [3:0] s_arregion,
    input s_arvalid, output s_arready,
    output [7:0] s_rid, output [31:0] s_rdata,
    output [1:0] s_rresp, output s_rlast,
    output s_rvalid, input s_rready,

    output bitblt_start,
    output [31:0] bitblt_src_addr, output [31:0] bitblt_dst_addr,
    output [31:0] bitblt_width, output [31:0] bitblt_height,
    output [31:0] bitblt_src_stride, output [31:0] bitblt_dst_stride,
    output [31:0] bitblt_color, output [31:0] bitblt_operation,
    input bitblt_busy, input bitblt_done, input bitblt_error,

    output [7:0] display_arid, output [31:0] display_araddr,
    output [7:0] display_arlen, output [2:0] display_arsize,
    output [1:0] display_arburst, output display_arlock,
    output [3:0] display_arcache, output [2:0] display_arprot,
    output display_arvalid, input display_arready,
    input [7:0] display_rid, input [127:0] display_rdata,
    input [1:0] display_rresp, input display_rlast,
    input display_rvalid, output display_rready,
    output video_hsync, output video_vsync, output video_de,
    output [7:0] video_red, output [7:0] video_green,
    output [7:0] video_blue
);
    wire b_irq, d_irq;
    wire b_awvalid, b_awready, b_wvalid, b_wready;
    wire [7:0] b_bid; wire [1:0] b_bresp; wire b_bvalid, b_bready;
    wire b_arvalid, b_arready; wire [7:0] b_rid;
    wire [31:0] b_rdata; wire [1:0] b_rresp;
    wire b_rlast, b_rvalid, b_rready;
    wire d_awvalid, d_awready, d_wvalid, d_wready;
    wire [7:0] d_bid; wire [1:0] d_bresp; wire d_bvalid, d_bready;
    wire d_arvalid, d_arready; wire [7:0] d_rid;
    wire [31:0] d_rdata; wire [1:0] d_rresp;
    wire d_rlast, d_rvalid, d_rready;
    assign axi_interrupt = b_irq | d_irq;

    axi_ctrl_demux_1to2 u_ctrl_demux (
        .clk(user_clk), .resetn(resetn),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wvalid(s_wvalid), .s_wready(s_wready), .s_bid(s_bid),
        .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_awid(s_awid), .s_araddr(s_araddr), .s_arvalid(s_arvalid),
        .s_arready(s_arready), .s_rid(s_rid), .s_rdata(s_rdata),
        .s_rresp(s_rresp), .s_rlast(s_rlast), .s_rvalid(s_rvalid),
        .s_rready(s_rready), .s_arid(s_arid),
        .m0_awvalid(b_awvalid), .m0_awready(b_awready),
        .m0_wvalid(b_wvalid), .m0_wready(b_wready),
        .m0_bid(b_bid), .m0_bresp(b_bresp), .m0_bvalid(b_bvalid), .m0_bready(b_bready),
        .m0_arvalid(b_arvalid), .m0_arready(b_arready),
        .m0_rid(b_rid), .m0_rdata(b_rdata), .m0_rresp(b_rresp),
        .m0_rlast(b_rlast), .m0_rvalid(b_rvalid), .m0_rready(b_rready),
        .m1_awvalid(d_awvalid), .m1_awready(d_awready),
        .m1_wvalid(d_wvalid), .m1_wready(d_wready),
        .m1_bid(d_bid), .m1_bresp(d_bresp), .m1_bvalid(d_bvalid), .m1_bready(d_bready),
        .m1_arvalid(d_arvalid), .m1_arready(d_arready),
        .m1_rid(d_rid), .m1_rdata(d_rdata), .m1_rresp(d_rresp),
        .m1_rlast(d_rlast), .m1_rvalid(d_rvalid), .m1_rready(d_rready));

    bitblt_ctrl_axi u_bitblt_ctrl (
        .axi_interrupt(b_irq), .axi_aclk(user_clk), .axi_resetn(resetn),
        .axi_awid(s_awid), .axi_awaddr(s_awaddr), .axi_awlen(s_awlen),
        .axi_awsize(s_awsize), .axi_awburst(s_awburst), .axi_awlock(s_awlock),
        .axi_awcache(s_awcache), .axi_awprot(s_awprot), .axi_awqos(s_awqos),
        .axi_awregion(s_awregion), .axi_awvalid(b_awvalid), .axi_awready(b_awready),
        .axi_wdata(s_wdata), .axi_wstrb(s_wstrb), .axi_wlast(s_wlast),
        .axi_wvalid(b_wvalid), .axi_wready(b_wready), .axi_bid(b_bid),
        .axi_bresp(b_bresp), .axi_bvalid(b_bvalid), .axi_bready(b_bready),
        .axi_arid(s_arid), .axi_araddr(s_araddr), .axi_arlen(s_arlen),
        .axi_arsize(s_arsize), .axi_arburst(s_arburst), .axi_arlock(s_arlock),
        .axi_arcache(s_arcache), .axi_arprot(s_arprot), .axi_arqos(s_arqos),
        .axi_arregion(s_arregion), .axi_arvalid(b_arvalid), .axi_arready(b_arready),
        .axi_rid(b_rid), .axi_rdata(b_rdata), .axi_rresp(b_rresp),
        .axi_rlast(b_rlast), .axi_rvalid(b_rvalid), .axi_rready(b_rready),
        .start_pulse(bitblt_start), .cfg_src_addr(bitblt_src_addr),
        .cfg_dst_addr(bitblt_dst_addr), .cfg_width(bitblt_width),
        .cfg_height(bitblt_height), .cfg_src_stride(bitblt_src_stride),
        .cfg_dst_stride(bitblt_dst_stride), .cfg_color(bitblt_color),
        .cfg_operation(bitblt_operation), .engine_busy(bitblt_busy),
        .engine_done(bitblt_done), .engine_error(bitblt_error));

    framebuffer_display u_display (
        .user_clk(user_clk), .pixel_clk(pixel_clk), .resetn(resetn),
        .ctrl_interrupt(d_irq), .s_awid(s_awid), .s_awaddr(s_awaddr),
        .s_awlen(s_awlen), .s_awsize(s_awsize), .s_awburst(s_awburst),
        .s_awlock(s_awlock), .s_awcache(s_awcache), .s_awprot(s_awprot),
        .s_awqos(s_awqos), .s_awregion(s_awregion),
        .s_awvalid(d_awvalid), .s_awready(d_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wlast(s_wlast),
        .s_wvalid(d_wvalid), .s_wready(d_wready), .s_bid(d_bid),
        .s_bresp(d_bresp), .s_bvalid(d_bvalid), .s_bready(d_bready),
        .s_arid(s_arid), .s_araddr(s_araddr), .s_arlen(s_arlen),
        .s_arsize(s_arsize), .s_arburst(s_arburst), .s_arlock(s_arlock),
        .s_arcache(s_arcache), .s_arprot(s_arprot), .s_arqos(s_arqos),
        .s_arregion(s_arregion), .s_arvalid(d_arvalid), .s_arready(d_arready),
        .s_rid(d_rid), .s_rdata(d_rdata), .s_rresp(d_rresp),
        .s_rlast(d_rlast), .s_rvalid(d_rvalid), .s_rready(d_rready),
        .m_arid(display_arid), .m_araddr(display_araddr),
        .m_arlen(display_arlen), .m_arsize(display_arsize),
        .m_arburst(display_arburst), .m_arlock(display_arlock),
        .m_arcache(display_arcache), .m_arprot(display_arprot),
        .m_arvalid(display_arvalid), .m_arready(display_arready),
        .m_rid(display_rid), .m_rdata(display_rdata),
        .m_rresp(display_rresp), .m_rlast(display_rlast),
        .m_rvalid(display_rvalid), .m_rready(display_rready),
        .video_hsync(video_hsync), .video_vsync(video_vsync),
        .video_de(video_de), .video_red(video_red),
        .video_green(video_green), .video_blue(video_blue));
endmodule
