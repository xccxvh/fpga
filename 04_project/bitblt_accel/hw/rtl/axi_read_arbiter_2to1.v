`timescale 1ns/1ps

// Two-master AXI read arbiter. Ownership is retained until the RLAST handshake.
module axi_read_arbiter_2to1 (
    input clk, input resetn,
    input [7:0] s0_arid, input [31:0] s0_araddr, input [7:0] s0_arlen,
    input [2:0] s0_arsize, input [1:0] s0_arburst, input s0_arlock,
    input [3:0] s0_arcache, input [2:0] s0_arprot, input s0_arvalid, output s0_arready,
    output [7:0] s0_rid, output [127:0] s0_rdata, output [1:0] s0_rresp,
    output s0_rlast, output s0_rvalid, input s0_rready,
    input [7:0] s1_arid, input [31:0] s1_araddr, input [7:0] s1_arlen,
    input [2:0] s1_arsize, input [1:0] s1_arburst, input s1_arlock,
    input [3:0] s1_arcache, input [2:0] s1_arprot, input s1_arvalid, output s1_arready,
    output [7:0] s1_rid, output [127:0] s1_rdata, output [1:0] s1_rresp,
    output s1_rlast, output s1_rvalid, input s1_rready,
    output [7:0] m_arid, output [31:0] m_araddr, output [7:0] m_arlen,
    output [2:0] m_arsize, output [1:0] m_arburst, output m_arlock,
    output [3:0] m_arcache, output [2:0] m_arprot, output m_arvalid, input m_arready,
    input [7:0] m_rid, input [127:0] m_rdata, input [1:0] m_rresp,
    input m_rlast, input m_rvalid, output m_rready
);
    reg active, owner;
    wire choose1 = s1_arvalid;
    assign m_arid = choose1 ? s1_arid : s0_arid;
    assign m_araddr = choose1 ? s1_araddr : s0_araddr;
    assign m_arlen = choose1 ? s1_arlen : s0_arlen;
    assign m_arsize = choose1 ? s1_arsize : s0_arsize;
    assign m_arburst = choose1 ? s1_arburst : s0_arburst;
    assign m_arlock = choose1 ? s1_arlock : s0_arlock;
    assign m_arcache = choose1 ? s1_arcache : s0_arcache;
    assign m_arprot = choose1 ? s1_arprot : s0_arprot;
    assign m_arvalid = !active && (s1_arvalid || s0_arvalid);
    assign s0_arready = !active && !choose1 && m_arready;
    assign s1_arready = !active && choose1 && m_arready;
    assign s0_rid = m_rid; assign s1_rid = m_rid;
    assign s0_rdata = m_rdata; assign s1_rdata = m_rdata;
    assign s0_rresp = m_rresp; assign s1_rresp = m_rresp;
    assign s0_rlast = m_rlast; assign s1_rlast = m_rlast;
    assign s0_rvalid = active && !owner && m_rvalid;
    assign s1_rvalid = active && owner && m_rvalid;
    assign m_rready = active && (owner ? s1_rready : s0_rready);
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin active <= 1'b0; owner <= 1'b0; end
        else begin
            if (!active && m_arvalid && m_arready) begin active <= 1'b1; owner <= choose1; end
            else if (active && m_rvalid && m_rready && m_rlast) active <= 1'b0;
        end
    end
endmodule
