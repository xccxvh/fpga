`timescale 1ns/1ps

// Display control plane for the BitBlt framebuffer output.
// Single-beat, 32-bit AXI4 slave. Register offsets follow interface v0.2.
module display_ctrl_axi #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter FB_A_ADDR = 32'h0100_0000,
    parameter FB_B_ADDR = 32'h0180_0000
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

    input vblank_pulse,
    input underflow_pulse,
    output display_enable,
    output [31:0] active_front_addr,
    output [31:0] active_width,
    output [31:0] active_height,
    output [31:0] active_stride,
    output [31:0] active_format,
    output swap_pending
);
    localparam [31:0] VERSION = 32'h0002_0000;

    reg aw_pending_reg, bvalid_reg, rvalid_reg;
    reg [ADDR_WIDTH-1:0] awaddr_reg;
    reg [7:0] awid_reg, bid_reg, rid_reg;
    reg [31:0] rdata_reg;
    reg display_enable_reg, swap_pending_reg;
    reg swap_done_reg, underflow_reg, error_reg;
    reg [31:0] front_addr_reg, next_addr_reg;
    reg [31:0] width_reg, height_reg, stride_reg, format_reg;
    reg [31:0] frame_count_reg, underflow_count_reg, irq_enable_reg;

    assign axi_awready = !aw_pending_reg && !bvalid_reg;
    assign axi_wready = aw_pending_reg && !bvalid_reg;
    assign axi_bid = bid_reg;
    assign axi_bresp = 2'b00;
    assign axi_bvalid = bvalid_reg;
    assign axi_arready = !rvalid_reg;
    assign axi_rid = rid_reg;
    assign axi_rdata = rdata_reg;
    assign axi_rresp = 2'b00;
    assign axi_rlast = 1'b1;
    assign axi_rvalid = rvalid_reg;

    assign display_enable = display_enable_reg;
    assign active_front_addr = front_addr_reg;
    assign active_width = width_reg;
    assign active_height = height_reg;
    assign active_stride = stride_reg;
    assign active_format = format_reg;
    assign swap_pending = swap_pending_reg;
    assign axi_interrupt = (swap_done_reg && irq_enable_reg[0]) ||
                           (underflow_reg && irq_enable_reg[1]) ||
                           (error_reg && irq_enable_reg[2]);

    function config_valid;
        input [31:0] candidate_next;
        begin
            config_valid = ((candidate_next == FB_A_ADDR) ||
                            (candidate_next == FB_B_ADDR)) &&
                           (candidate_next != front_addr_reg) &&
                           (candidate_next[3:0] == 4'h0) &&
                           (width_reg == 32'd1920) &&
                           (height_reg == 32'd1080) &&
                           (stride_reg >= 32'd7680) &&
                           (stride_reg[3:0] == 4'h0) &&
                           (format_reg == 32'd0);
        end
    endfunction

    function [31:0] register_read;
        input [5:0] word_address;
        begin
            case (word_address)
                6'h00: register_read = {31'h0, display_enable_reg};
                6'h01: register_read = {27'h0, error_reg, underflow_reg,
                                        swap_done_reg, swap_pending_reg,
                                        display_enable_reg};
                6'h02: register_read = front_addr_reg;
                6'h03: register_read = next_addr_reg;
                6'h04: register_read = width_reg;
                6'h05: register_read = height_reg;
                6'h06: register_read = stride_reg;
                6'h07: register_read = format_reg;
                6'h08: register_read = frame_count_reg;
                6'h09: register_read = underflow_count_reg;
                6'h0A: register_read = VERSION;
                6'h0B: register_read = irq_enable_reg;
                default: register_read = 32'h0;
            endcase
        end
    endfunction

    always @(posedge axi_aclk or negedge axi_resetn) begin
        if (!axi_resetn) begin
            aw_pending_reg <= 0;
            bvalid_reg <= 0;
            rvalid_reg <= 0;
            awaddr_reg <= 0;
            awid_reg <= 0;
            bid_reg <= 0;
            rid_reg <= 0;
            rdata_reg <= 0;
            display_enable_reg <= 0;
            swap_pending_reg <= 0;
            swap_done_reg <= 0;
            underflow_reg <= 0;
            error_reg <= 0;
            front_addr_reg <= FB_A_ADDR;
            next_addr_reg <= FB_B_ADDR;
            width_reg <= 32'd1920;
            height_reg <= 32'd1080;
            stride_reg <= 32'd7680;
            format_reg <= 0;
            frame_count_reg <= 0;
            underflow_count_reg <= 0;
            irq_enable_reg <= 0;
        end else begin
            if (axi_awvalid && axi_awready) begin
                aw_pending_reg <= 1;
                awaddr_reg <= axi_awaddr;
                awid_reg <= axi_awid;
                if ((axi_awlen != 0) || (axi_awsize != 3'd2) ||
                    (axi_awburst != 2'b01))
                    error_reg <= 1;
            end

            if (axi_wvalid && axi_wready) begin
                if (&axi_wstrb && axi_wlast) begin
                    case (awaddr_reg[7:2])
                        6'h00: begin
                            display_enable_reg <= axi_wdata[0];
                            if (axi_wdata[2]) begin
                                swap_done_reg <= 0;
                                underflow_reg <= 0;
                                error_reg <= 0;
                                underflow_count_reg <= 0;
                            end
                            if (axi_wdata[1]) begin
                                if (!swap_pending_reg &&
                                    config_valid(next_addr_reg))
                                    swap_pending_reg <= 1;
                                else
                                    error_reg <= 1;
                            end
                        end
                        6'h03: next_addr_reg <= axi_wdata;
                        6'h04: width_reg <= axi_wdata;
                        6'h05: height_reg <= axi_wdata;
                        6'h06: stride_reg <= axi_wdata;
                        6'h07: format_reg <= axi_wdata;
                        6'h0B: irq_enable_reg <= axi_wdata & 32'h7;
                        default: error_reg <= 1;
                    endcase
                end else begin
                    error_reg <= 1;
                end
                aw_pending_reg <= 0;
                bvalid_reg <= 1;
                bid_reg <= awid_reg;
            end
            if (bvalid_reg && axi_bready)
                bvalid_reg <= 0;

            if (axi_arvalid && axi_arready) begin
                rdata_reg <= register_read(axi_araddr[7:2]);
                rid_reg <= axi_arid;
                rvalid_reg <= 1;
                if ((axi_arlen != 0) || (axi_arsize != 3'd2) ||
                    (axi_arburst != 2'b01))
                    error_reg <= 1;
            end else if (rvalid_reg && axi_rready) begin
                rvalid_reg <= 0;
            end

            if (vblank_pulse && display_enable_reg) begin
                frame_count_reg <= frame_count_reg + 1'b1;
                if (swap_pending_reg) begin
                    front_addr_reg <= next_addr_reg;
                    swap_pending_reg <= 0;
                    swap_done_reg <= 1;
                end
            end

            if (underflow_pulse && display_enable_reg) begin
                underflow_reg <= 1;
                underflow_count_reg <= underflow_count_reg + 1'b1;
            end
        end
    end
endmodule
