`timescale 1ns/1ps

// Transaction selector for two single-beat AXI control slaves.
// Payload/address sidebands are broadcast by the parent; this block gates the
// channel valid/ready signals and multiplexes responses. Unmapped accesses
// complete locally with DECERR so software cannot hang.
module axi_ctrl_demux_1to2 #(
    parameter BASE0 = 32'hE100_0000,
    parameter BASE1 = 32'hE110_0000,
    parameter MASK  = 32'hFFFF_0000
) (
    input clk, input resetn,
    input [31:0] s_awaddr, input s_awvalid, output s_awready,
    input s_wvalid, output s_wready,
    output [7:0] s_bid, output [1:0] s_bresp,
    output s_bvalid, input s_bready,
    input [7:0] s_awid,
    input [31:0] s_araddr, input s_arvalid, output s_arready,
    output [7:0] s_rid, output [31:0] s_rdata,
    output [1:0] s_rresp, output s_rlast,
    output s_rvalid, input s_rready,
    input [7:0] s_arid,

    output m0_awvalid, input m0_awready,
    output m0_wvalid, input m0_wready,
    input [7:0] m0_bid, input [1:0] m0_bresp,
    input m0_bvalid, output m0_bready,
    output m0_arvalid, input m0_arready,
    input [7:0] m0_rid, input [31:0] m0_rdata,
    input [1:0] m0_rresp, input m0_rlast,
    input m0_rvalid, output m0_rready,

    output m1_awvalid, input m1_awready,
    output m1_wvalid, input m1_wready,
    input [7:0] m1_bid, input [1:0] m1_bresp,
    input m1_bvalid, output m1_bready,
    output m1_arvalid, input m1_arready,
    input [7:0] m1_rid, input [31:0] m1_rdata,
    input [1:0] m1_rresp, input m1_rlast,
    input m1_rvalid, output m1_rready
);
    localparam SEL0 = 2'd0, SEL1 = 2'd1, SEL_ERR = 2'd2;
    wire [1:0] aw_sel_now = ((s_awaddr & MASK) == BASE0) ? SEL0 :
                            ((s_awaddr & MASK) == BASE1) ? SEL1 : SEL_ERR;
    wire [1:0] ar_sel_now = ((s_araddr & MASK) == BASE0) ? SEL0 :
                            ((s_araddr & MASK) == BASE1) ? SEL1 : SEL_ERR;
    reg write_active, write_data_done;
    reg [1:0] write_sel;
    reg [7:0] error_bid;
    reg read_active;
    reg [1:0] read_sel;
    reg [7:0] error_rid;

    assign m0_awvalid = !write_active && s_awvalid && (aw_sel_now == SEL0);
    assign m1_awvalid = !write_active && s_awvalid && (aw_sel_now == SEL1);
    assign s_awready = !write_active &&
                       ((aw_sel_now == SEL0) ? m0_awready :
                        (aw_sel_now == SEL1) ? m1_awready : 1'b1);

    assign m0_wvalid = write_active && !write_data_done &&
                       (write_sel == SEL0) && s_wvalid;
    assign m1_wvalid = write_active && !write_data_done &&
                       (write_sel == SEL1) && s_wvalid;
    assign s_wready = write_active && !write_data_done &&
                      ((write_sel == SEL0) ? m0_wready :
                       (write_sel == SEL1) ? m1_wready : 1'b1);

    assign s_bid = (write_sel == SEL0) ? m0_bid :
                   (write_sel == SEL1) ? m1_bid : error_bid;
    assign s_bresp = (write_sel == SEL0) ? m0_bresp :
                     (write_sel == SEL1) ? m1_bresp : 2'b11;
    assign s_bvalid = write_data_done &&
                      ((write_sel == SEL0) ? m0_bvalid :
                       (write_sel == SEL1) ? m1_bvalid : 1'b1);
    assign m0_bready = write_data_done && (write_sel == SEL0) && s_bready;
    assign m1_bready = write_data_done && (write_sel == SEL1) && s_bready;

    assign m0_arvalid = !read_active && s_arvalid && (ar_sel_now == SEL0);
    assign m1_arvalid = !read_active && s_arvalid && (ar_sel_now == SEL1);
    assign s_arready = !read_active &&
                       ((ar_sel_now == SEL0) ? m0_arready :
                        (ar_sel_now == SEL1) ? m1_arready : 1'b1);
    assign s_rid = (read_sel == SEL0) ? m0_rid :
                   (read_sel == SEL1) ? m1_rid : error_rid;
    assign s_rdata = (read_sel == SEL0) ? m0_rdata :
                     (read_sel == SEL1) ? m1_rdata : 32'h0;
    assign s_rresp = (read_sel == SEL0) ? m0_rresp :
                     (read_sel == SEL1) ? m1_rresp : 2'b11;
    assign s_rlast = (read_sel == SEL0) ? m0_rlast :
                     (read_sel == SEL1) ? m1_rlast : 1'b1;
    assign s_rvalid = read_active &&
                      ((read_sel == SEL0) ? m0_rvalid :
                       (read_sel == SEL1) ? m1_rvalid : 1'b1);
    assign m0_rready = read_active && (read_sel == SEL0) && s_rready;
    assign m1_rready = read_active && (read_sel == SEL1) && s_rready;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            write_active <= 0;
            write_data_done <= 0;
            write_sel <= SEL_ERR;
            error_bid <= 0;
            read_active <= 0;
            read_sel <= SEL_ERR;
            error_rid <= 0;
        end else begin
            if (s_awvalid && s_awready) begin
                write_active <= 1;
                write_data_done <= 0;
                write_sel <= aw_sel_now;
                error_bid <= s_awid;
            end
            if (s_wvalid && s_wready)
                write_data_done <= 1;
            if (s_bvalid && s_bready) begin
                write_active <= 0;
                write_data_done <= 0;
            end

            if (s_arvalid && s_arready) begin
                read_active <= 1;
                read_sel <= ar_sel_now;
                error_rid <= s_arid;
            end
            if (s_rvalid && s_rready)
                read_active <= 0;
        end
    end
endmodule
