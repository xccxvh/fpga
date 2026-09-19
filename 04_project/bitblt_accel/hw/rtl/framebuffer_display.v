`timescale 1ns/1ps

// Framebuffer display subsystem excluding the board-specific DVI encoder/PHY.
// Control and DDR interfaces use user_clk; video uses pixel_clk.
module framebuffer_display (
    input user_clk, input pixel_clk, input resetn,
    output ctrl_interrupt,
    input [7:0] s_awid, input [31:0] s_awaddr, input [7:0] s_awlen,
    input [2:0] s_awsize, input [1:0] s_awburst, input s_awlock,
    input [3:0] s_awcache, input [2:0] s_awprot,
    input [3:0] s_awqos, input [3:0] s_awregion,
    input s_awvalid, output s_awready,
    input [31:0] s_wdata, input [3:0] s_wstrb,
    input s_wlast, input s_wvalid, output s_wready,
    output [7:0] s_bid, output [1:0] s_bresp,
    output s_bvalid, input s_bready,
    input [7:0] s_arid, input [31:0] s_araddr, input [7:0] s_arlen,
    input [2:0] s_arsize, input [1:0] s_arburst, input s_arlock,
    input [3:0] s_arcache, input [2:0] s_arprot,
    input [3:0] s_arqos, input [3:0] s_arregion,
    input s_arvalid, output s_arready,
    output [7:0] s_rid, output [31:0] s_rdata,
    output [1:0] s_rresp, output s_rlast,
    output s_rvalid, input s_rready,

    output [7:0] m_arid, output [31:0] m_araddr,
    output [7:0] m_arlen, output [2:0] m_arsize,
    output [1:0] m_arburst, output m_arlock,
    output [3:0] m_arcache, output [2:0] m_arprot,
    output m_arvalid, input m_arready,
    input [7:0] m_rid, input [127:0] m_rdata,
    input [1:0] m_rresp, input m_rlast,
    input m_rvalid, output m_rready,

    output video_hsync, output video_vsync, output video_de,
    output [7:0] video_red, output [7:0] video_green,
    output [7:0] video_blue
);
    wire display_enable_user, swap_pending;
    wire [31:0] front_addr, cfg_width, cfg_height, cfg_stride, cfg_format;
    wire vblank_pixel, vblank_user, underflow_pixel, underflow_user;
    wire [11:0] pixel_x;
    wire [10:0] pixel_y;
    wire dma_busy, dma_done, dma_error;
    reg dma_start, vblank_user_d, display_enable_d;
    wire [127:0] dma_data;
    wire dma_valid, dma_ready, dma_frame_last;
    wire [127:0] fifo_data;
    wire fifo_valid, fifo_ready, fifo_full, fifo_empty, fifo_almost_empty;
    reg enable_sync1, enable_sync2, video_run;
    wire pixel_valid;
    wire [7:0] unpack_red, unpack_green, unpack_blue;
    assign video_red = video_run ? unpack_red : 8'h00;
    assign video_green = video_run ? unpack_green : 8'h00;
    assign video_blue = video_run ? unpack_blue : 8'h00;

    display_ctrl_axi u_ctrl (
        .axi_interrupt(ctrl_interrupt), .axi_aclk(user_clk), .axi_resetn(resetn),
        .axi_awid(s_awid), .axi_awaddr(s_awaddr), .axi_awlen(s_awlen),
        .axi_awsize(s_awsize), .axi_awburst(s_awburst), .axi_awlock(s_awlock),
        .axi_awcache(s_awcache), .axi_awprot(s_awprot), .axi_awqos(s_awqos),
        .axi_awregion(s_awregion), .axi_awvalid(s_awvalid), .axi_awready(s_awready),
        .axi_wdata(s_wdata), .axi_wstrb(s_wstrb), .axi_wlast(s_wlast),
        .axi_wvalid(s_wvalid), .axi_wready(s_wready), .axi_bid(s_bid),
        .axi_bresp(s_bresp), .axi_bvalid(s_bvalid), .axi_bready(s_bready),
        .axi_arid(s_arid), .axi_araddr(s_araddr), .axi_arlen(s_arlen),
        .axi_arsize(s_arsize), .axi_arburst(s_arburst), .axi_arlock(s_arlock),
        .axi_arcache(s_arcache), .axi_arprot(s_arprot), .axi_arqos(s_arqos),
        .axi_arregion(s_arregion), .axi_arvalid(s_arvalid), .axi_arready(s_arready),
        .axi_rid(s_rid), .axi_rdata(s_rdata), .axi_rresp(s_rresp),
        .axi_rlast(s_rlast), .axi_rvalid(s_rvalid), .axi_rready(s_rready),
        .vblank_pulse(vblank_user), .underflow_pulse(underflow_user),
        .display_enable(display_enable_user), .active_front_addr(front_addr),
        .active_width(cfg_width), .active_height(cfg_height),
        .active_stride(cfg_stride), .active_format(cfg_format),
        .swap_pending(swap_pending));

    // Delay VBlank one user-clock cycle so a pending front-buffer swap is
    // visible to the DMA before it snapshots the next frame address.
    always @(posedge user_clk or negedge resetn) begin
        if (!resetn) begin
            dma_start <= 0; vblank_user_d <= 0; display_enable_d <= 0;
        end else begin
            dma_start <= 0;
            vblank_user_d <= vblank_user;
            display_enable_d <= display_enable_user;
            if (!dma_busy && display_enable_user &&
                ((!display_enable_d) || vblank_user_d))
                dma_start <= 1;
        end
    end

    display_dma_axi u_dma (
        .clk(user_clk), .resetn(resetn), .start_frame(dma_start),
        .cfg_base_addr(front_addr), .cfg_width(cfg_width),
        .cfg_height(cfg_height), .cfg_stride(cfg_stride),
        .busy(dma_busy), .done_pulse(dma_done), .error_pulse(dma_error),
        .m_axi_arid(m_arid), .m_axi_araddr(m_araddr), .m_axi_arlen(m_arlen),
        .m_axi_arsize(m_arsize), .m_axi_arburst(m_arburst),
        .m_axi_arlock(m_arlock), .m_axi_arcache(m_arcache),
        .m_axi_arprot(m_arprot), .m_axi_arvalid(m_arvalid),
        .m_axi_arready(m_arready), .m_axi_rid(m_rid), .m_axi_rdata(m_rdata),
        .m_axi_rresp(m_rresp), .m_axi_rlast(m_rlast),
        .m_axi_rvalid(m_rvalid), .m_axi_rready(m_rready),
        .stream_data(dma_data), .stream_valid(dma_valid),
        .stream_ready(dma_ready), .stream_frame_last(dma_frame_last));

    async_fifo #(.DATA_WIDTH(128), .ADDR_WIDTH(9), .ALMOST_EMPTY_LEVEL(32)) u_fifo (
        .w_clk(user_clk), .w_resetn(resetn), .w_data(dma_data),
        .w_valid(dma_valid), .w_ready(dma_ready), .w_full(fifo_full),
        .r_clk(pixel_clk), .r_resetn(resetn), .r_data(fifo_data),
        .r_valid(fifo_valid), .r_ready(fifo_ready), .r_empty(fifo_empty),
        .r_almost_empty(fifo_almost_empty));

    video_timing_1280x720 u_timing (
        .pixel_clk(pixel_clk), .resetn(resetn), .hsync(video_hsync),
        .vsync(video_vsync), .data_enable(video_de),
        .vblank_pulse(vblank_pixel), .pixel_x(pixel_x), .pixel_y(pixel_y));

    always @(posedge pixel_clk or negedge resetn) begin
        if (!resetn) begin
            enable_sync1 <= 0; enable_sync2 <= 0; video_run <= 0;
        end else begin
            enable_sync1 <= display_enable_user;
            enable_sync2 <= enable_sync1;
            if (!enable_sync2) video_run <= 0;
            else if (vblank_pixel && !fifo_almost_empty) video_run <= 1;
        end
    end

    pixel_unpack_rgb565 u_unpack (
        .pixel_clk(pixel_clk), .resetn(resetn),
        .pixel_request(video_de && video_run),
        .stream_data(fifo_data), .stream_valid(fifo_valid),
        .stream_ready(fifo_ready), .red(unpack_red), .green(unpack_green),
        .blue(unpack_blue), .pixel_valid(pixel_valid),
        .underflow_pulse(underflow_pixel));

    pulse_cdc u_vblank_cdc (
        .src_clk(pixel_clk), .src_resetn(resetn), .src_pulse(vblank_pixel),
        .dst_clk(user_clk), .dst_resetn(resetn), .dst_pulse(vblank_user));
    pulse_cdc u_underflow_cdc (
        .src_clk(pixel_clk), .src_resetn(resetn), .src_pulse(underflow_pixel),
        .dst_clk(user_clk), .dst_resetn(resetn), .dst_pulse(underflow_user));
endmodule
