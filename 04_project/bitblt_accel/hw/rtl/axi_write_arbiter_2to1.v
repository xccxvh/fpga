`timescale 1ns/1ps

// Two-master, one-outstanding AXI4 write arbiter. Master 1 is the accelerator.
module axi_write_arbiter_2to1 (
    input clk, input resetn,
    input [7:0] s0_awid, input [31:0] s0_awaddr, input [7:0] s0_awlen,
    input [2:0] s0_awsize, input [1:0] s0_awburst, input s0_awlock,
    input [3:0] s0_awcache, input [2:0] s0_awprot, input s0_awvalid, output s0_awready,
    input [127:0] s0_wdata, input [15:0] s0_wstrb, input s0_wlast, input s0_wvalid, output s0_wready,
    output [7:0] s0_bid, output [1:0] s0_bresp, output s0_bvalid, input s0_bready,
    input [7:0] s1_awid, input [31:0] s1_awaddr, input [7:0] s1_awlen,
    input [2:0] s1_awsize, input [1:0] s1_awburst, input s1_awlock,
    input [3:0] s1_awcache, input [2:0] s1_awprot, input s1_awvalid, output s1_awready,
    input [127:0] s1_wdata, input [15:0] s1_wstrb, input s1_wlast, input s1_wvalid, output s1_wready,
    output [7:0] s1_bid, output [1:0] s1_bresp, output s1_bvalid, input s1_bready,
    output [7:0] m_awid, output [31:0] m_awaddr, output [7:0] m_awlen,
    output [2:0] m_awsize, output [1:0] m_awburst, output m_awlock,
    output [3:0] m_awcache, output [2:0] m_awprot, output m_awvalid, input m_awready,
    output [127:0] m_wdata, output [15:0] m_wstrb, output m_wlast, output m_wvalid, input m_wready,
    input [7:0] m_bid, input [1:0] m_bresp, input m_bvalid, output m_bready
);
    localparam IDLE = 2'd0, DATA = 2'd1, RESP = 2'd2;
    reg [1:0] state;
    reg owner;
    wire choose1 = s1_awvalid;
    assign m_awid = choose1 ? s1_awid : s0_awid;
    assign m_awaddr = choose1 ? s1_awaddr : s0_awaddr;
    assign m_awlen = choose1 ? s1_awlen : s0_awlen;
    assign m_awsize = choose1 ? s1_awsize : s0_awsize;
    assign m_awburst = choose1 ? s1_awburst : s0_awburst;
    assign m_awlock = choose1 ? s1_awlock : s0_awlock;
    assign m_awcache = choose1 ? s1_awcache : s0_awcache;
    assign m_awprot = choose1 ? s1_awprot : s0_awprot;
    assign m_awvalid = (state == IDLE) && (s1_awvalid || s0_awvalid);
    assign s0_awready = (state == IDLE) && !choose1 && m_awready;
    assign s1_awready = (state == IDLE) && choose1 && m_awready;
    assign m_wdata = owner ? s1_wdata : s0_wdata;
    assign m_wstrb = owner ? s1_wstrb : s0_wstrb;
    assign m_wlast = owner ? s1_wlast : s0_wlast;
    assign m_wvalid = (state == DATA) && (owner ? s1_wvalid : s0_wvalid);
    assign s0_wready = (state == DATA) && !owner && m_wready;
    assign s1_wready = (state == DATA) && owner && m_wready;
    assign s0_bid = m_bid; assign s1_bid = m_bid;
    assign s0_bresp = m_bresp; assign s1_bresp = m_bresp;
    assign s0_bvalid = (state == RESP) && !owner && m_bvalid;
    assign s1_bvalid = (state == RESP) && owner && m_bvalid;
    assign m_bready = (state == RESP) && (owner ? s1_bready : s0_bready);
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin state <= IDLE; owner <= 0; end
        else case (state)
            IDLE: if (m_awvalid && m_awready) begin owner <= choose1; state <= DATA; end
            DATA: if (m_wvalid && m_wready && m_wlast) state <= RESP;
            RESP: if (m_bvalid && m_bready) state <= IDLE;
            default: state <= IDLE;
        endcase
    end
endmodule
