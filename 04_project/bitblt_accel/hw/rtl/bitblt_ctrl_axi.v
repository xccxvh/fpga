`timescale 1ns/1ps

// BitBlt MVP control plane. Single-beat, 32-bit AXI4 slave.
module bitblt_ctrl_axi #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    output axi_interrupt, input axi_aclk, input axi_resetn,
    input [7:0] axi_awid, input [ADDR_WIDTH-1:0] axi_awaddr,
    input [7:0] axi_awlen, input [2:0] axi_awsize,
    input [1:0] axi_awburst, input axi_awlock,
    input [3:0] axi_awcache, input [2:0] axi_awprot,
    input [3:0] axi_awqos, input [3:0] axi_awregion,
    input axi_awvalid, output axi_awready,
    input [DATA_WIDTH-1:0] axi_wdata,
    input [(DATA_WIDTH/8)-1:0] axi_wstrb,
    input axi_wlast, input axi_wvalid, output axi_wready,
    output [7:0] axi_bid, output [1:0] axi_bresp,
    output axi_bvalid, input axi_bready,
    input [7:0] axi_arid, input [ADDR_WIDTH-1:0] axi_araddr,
    input [7:0] axi_arlen, input [2:0] axi_arsize,
    input [1:0] axi_arburst, input axi_arlock,
    input [3:0] axi_arcache, input [2:0] axi_arprot,
    input [3:0] axi_arqos, input [3:0] axi_arregion,
    input axi_arvalid, output axi_arready,
    output [7:0] axi_rid, output [DATA_WIDTH-1:0] axi_rdata,
    output [1:0] axi_rresp, output axi_rlast,
    output axi_rvalid, input axi_rready,
    output reg start_pulse,
    output [31:0] cfg_src_addr,
    output [31:0] cfg_dst_addr,
    output [31:0] cfg_width,
    output [31:0] cfg_height,
    output [31:0] cfg_src_stride,
    output [31:0] cfg_dst_stride,
    output [31:0] cfg_color,
    output [31:0] cfg_operation,
    input engine_busy,
    input engine_done,
    input engine_error
);

    localparam [31:0] VERSION = 32'h0001_0003;
    reg aw_pending, bvalid_reg, rvalid_reg;
    reg [ADDR_WIDTH-1:0] awaddr_reg;
    reg [7:0] awid_reg, bid_reg, rid_reg;
    reg [31:0] rdata_reg;
    reg [31:0] src_addr_reg, dst_addr_reg, width_reg, height_reg;
    reg [31:0] src_stride_reg, dst_stride_reg, color_reg, operation_reg;
    reg done_reg, error_reg, interrupt_reg;

    assign axi_awready = !aw_pending && !bvalid_reg;
    assign axi_wready = aw_pending && !bvalid_reg;
    assign axi_bid = bid_reg;
    assign axi_bresp = 2'b00;
    assign axi_bvalid = bvalid_reg;
    assign axi_arready = !rvalid_reg;
    assign axi_rid = rid_reg;
    assign axi_rdata = rdata_reg;
    assign axi_rresp = 2'b00;
    assign axi_rlast = 1'b1;
    assign axi_rvalid = rvalid_reg;
    assign axi_interrupt = interrupt_reg;
    assign cfg_src_addr = src_addr_reg;
    assign cfg_dst_addr = dst_addr_reg;
    assign cfg_width = width_reg;
    assign cfg_height = height_reg;
    assign cfg_src_stride = src_stride_reg;
    assign cfg_dst_stride = dst_stride_reg;
    assign cfg_color = color_reg;
    assign cfg_operation = operation_reg;

    function [31:0] register_read;
        input [5:0] word_address;
        begin
            case (word_address)
                6'h00: register_read = 32'h0;
                6'h01: register_read = {29'h0, error_reg, done_reg, engine_busy};
                6'h02: register_read = src_addr_reg;
                6'h03: register_read = dst_addr_reg;
                6'h04: register_read = width_reg;
                6'h05: register_read = height_reg;
                6'h06: register_read = src_stride_reg;
                6'h07: register_read = dst_stride_reg;
                6'h08: register_read = color_reg;
                6'h09: register_read = operation_reg;
                6'h0A: register_read = VERSION;
                default: register_read = 32'h0;
            endcase
        end
    endfunction

    always @(posedge axi_aclk or negedge axi_resetn) begin
        if (!axi_resetn) begin
            aw_pending <= 0; awaddr_reg <= 0; awid_reg <= 0;
            bvalid_reg <= 0; bid_reg <= 0; rvalid_reg <= 0;
            rdata_reg <= 0; rid_reg <= 0;
            src_addr_reg <= 0; dst_addr_reg <= 0;
            width_reg <= 0; height_reg <= 0;
            src_stride_reg <= 0; dst_stride_reg <= 0;
            color_reg <= 0; operation_reg <= 0;
            done_reg <= 0; error_reg <= 0;
            interrupt_reg <= 0; start_pulse <= 0;
        end else begin
            interrupt_reg <= 0;
            start_pulse <= 0;
            if (axi_awvalid && axi_awready) begin
                aw_pending <= 1;
                awaddr_reg <= axi_awaddr;
                awid_reg <= axi_awid;
                if (axi_awlen != 0) error_reg <= 1;
            end
            if (axi_wvalid && axi_wready) begin
                if (&axi_wstrb) begin
                    case (awaddr_reg[7:2])
                        6'h00: begin
                            if (axi_wdata[1]) begin done_reg <= 0; error_reg <= 0; end
                            if (axi_wdata[0]) begin
                                if (!engine_busy) begin
                                    done_reg <= 0; error_reg <= 0; start_pulse <= 1;
                                end else error_reg <= 1;
                            end
                        end
                        6'h02: src_addr_reg <= axi_wdata;
                        6'h03: dst_addr_reg <= axi_wdata;
                        6'h04: width_reg <= axi_wdata;
                        6'h05: height_reg <= axi_wdata;
                        6'h06: src_stride_reg <= axi_wdata;
                        6'h07: dst_stride_reg <= axi_wdata;
                        6'h08: color_reg <= axi_wdata;
                        6'h09: operation_reg <= axi_wdata;
                        default: error_reg <= 1;
                    endcase
                end else error_reg <= 1;
                aw_pending <= 0; bvalid_reg <= 1; bid_reg <= awid_reg;
            end
            if (bvalid_reg && axi_bready) bvalid_reg <= 0;
            if (axi_arvalid && axi_arready) begin
                rdata_reg <= register_read(axi_araddr[7:2]);
                rid_reg <= axi_arid; rvalid_reg <= 1;
                if (axi_arlen != 0) error_reg <= 1;
            end else if (rvalid_reg && axi_rready) rvalid_reg <= 0;
            if (engine_done) begin
                done_reg <= 1;
                if (engine_error) error_reg <= 1;
                interrupt_reg <= 1;
            end
        end
    end
endmodule
