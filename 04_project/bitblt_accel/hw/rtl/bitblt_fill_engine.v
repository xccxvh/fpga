`timescale 1ns/1ps

// Minimal hardware Fill engine for the first BitBlt data-plane milestone.
// Up to 16 consecutive 128-bit beats are issued per AXI burst.
module bitblt_fill_engine (
    input clk, input resetn, input start,
    input [31:0] dst_addr, input [31:0] width, input [31:0] height,
    input [31:0] dst_stride, input [31:0] color, input [31:0] operation,
    output reg busy, output reg done, output reg error,
    output reg [7:0] m_awid, output reg [31:0] m_awaddr,
    output [7:0] m_awlen, output [2:0] m_awsize, output [1:0] m_awburst,
    output m_awlock, output [3:0] m_awcache, output [2:0] m_awprot,
    output reg m_awvalid, input m_awready,
    output [127:0] m_wdata, output [15:0] m_wstrb, output m_wlast,
    output reg m_wvalid, input m_wready,
    input [7:0] m_bid, input [1:0] m_bresp, input m_bvalid, output m_bready
);
    localparam OP_FILL = 32'd0;
    localparam ST_IDLE = 2'd0, ST_AW = 2'd1, ST_W = 2'd2, ST_B = 2'd3;
    reg [1:0] state;
    reg [31:0] row_base, row_index, beats_per_row, row_beats_remaining;
    reg [4:0] burst_beats, burst_beat_index;
    reg [31:0] height_latched, stride_latched, color_latched;

    assign m_awlen = {3'd0, burst_beats} - 1'b1;
    assign m_awsize = 3'd4;
    assign m_awburst = 2'b01;
    assign m_awlock = 1'b0;
    assign m_awcache = 4'b0011;
    assign m_awprot = 3'b000;
    assign m_wdata = {4{color_latched}};
    assign m_wstrb = 16'hffff;
    assign m_wlast = (burst_beat_index + 1'b1 == burst_beats);
    assign m_bready = (state == ST_B);

    function [4:0] burst_size;
        input [31:0] remaining;
        input [31:0] address;
        reg [8:0] boundary_beats;
        begin
            if (address[11:0] > 12'hf00)
                boundary_beats = (13'h1000 - {1'b0, address[11:0]}) >> 4;
            else
                boundary_beats = 9'd16;
            if (remaining < boundary_beats) burst_size = remaining[4:0];
            else if (boundary_beats < 16) burst_size = boundary_beats[4:0];
            else burst_size = 5'd16;
        end
    endfunction

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= ST_IDLE; busy <= 0; done <= 0; error <= 0;
            m_awid <= 8'h00; m_awaddr <= 0; m_awvalid <= 0; m_wvalid <= 0;
            row_base <= 0; row_index <= 0; beats_per_row <= 0;
            row_beats_remaining <= 0; burst_beats <= 1; burst_beat_index <= 0;
            height_latched <= 0; stride_latched <= 0; color_latched <= 0;
        end else begin
            done <= 0;
            error <= 0;
            case (state)
                ST_IDLE: begin
                    busy <= 0; m_awvalid <= 0; m_wvalid <= 0;
                    if (start) begin
                        if ((operation != OP_FILL) || (width == 0) || (height == 0) ||
                            (width[1:0] != 0) || (dst_addr[3:0] != 0) ||
                            (dst_stride[3:0] != 0) || (dst_stride < (width << 2))) begin
                            done <= 1; error <= 1;
                        end else begin
                            busy <= 1; row_base <= dst_addr; row_index <= 0;
                            beats_per_row <= width >> 2; height_latched <= height;
                            row_beats_remaining <= width >> 2;
                            burst_beats <= burst_size(width >> 2, dst_addr);
                            burst_beat_index <= 0;
                            stride_latched <= dst_stride; color_latched <= color;
                            m_awaddr <= dst_addr; m_awvalid <= 1; state <= ST_AW;
                        end
                    end
                end
                ST_AW: if (m_awvalid && m_awready) begin
                    m_awvalid <= 0; m_wvalid <= 1; state <= ST_W;
                end
                ST_W: if (m_wvalid && m_wready) begin
                    if (m_wlast) begin m_wvalid <= 0; state <= ST_B; end
                    else burst_beat_index <= burst_beat_index + 1'b1;
                end
                ST_B: if (m_bvalid) begin
                    if ((m_bresp != 2'b00) || (m_bid != 8'h00)) begin
                        busy <= 0; done <= 1; error <= 1; state <= ST_IDLE;
                    end else if (row_beats_remaining > burst_beats) begin
                        row_beats_remaining <= row_beats_remaining - burst_beats;
                        m_awaddr <= m_awaddr + ({27'd0, burst_beats} << 4);
                        burst_beats <= burst_size(row_beats_remaining - burst_beats,
                                                 m_awaddr + ({27'd0, burst_beats} << 4));
                        burst_beat_index <= 0;
                        m_awvalid <= 1; state <= ST_AW;
                    end else if (row_index + 1 < height_latched) begin
                        row_index <= row_index + 1'b1;
                        row_base <= row_base + stride_latched;
                        row_beats_remaining <= beats_per_row;
                        burst_beats <= burst_size(beats_per_row, row_base + stride_latched);
                        burst_beat_index <= 0;
                        m_awaddr <= row_base + stride_latched;
                        m_awvalid <= 1; state <= ST_AW;
                    end else begin
                        busy <= 0; done <= 1; state <= ST_IDLE;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
