`timescale 1ns/1ps

// Read-only framebuffer DMA. XRGB8888 pixels are emitted four per 128-bit beat.
// Bursts are limited to 64 beats and never cross a 4 KiB boundary.  The
// longer bursts are required to sustain 1080p60 scanout through the DDR
// controller without spending too much bandwidth on read-address latency.
module display_dma_axi #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 128,
    parameter [7:0] AXI_ID = 8'hD1
) (
    input clk, input resetn,
    input start_frame,
    input [31:0] cfg_base_addr,
    input [31:0] cfg_width,
    input [31:0] cfg_height,
    input [31:0] cfg_stride,
    output reg busy,
    output reg done_pulse,
    output reg error_pulse,

    output [7:0] m_axi_arid,
    output [ADDR_WIDTH-1:0] m_axi_araddr,
    output [7:0] m_axi_arlen,
    output [2:0] m_axi_arsize,
    output [1:0] m_axi_arburst,
    output m_axi_arlock,
    output [3:0] m_axi_arcache,
    output [2:0] m_axi_arprot,
    output m_axi_arvalid,
    input m_axi_arready,
    input [7:0] m_axi_rid,
    input [DATA_WIDTH-1:0] m_axi_rdata,
    input [1:0] m_axi_rresp,
    input m_axi_rlast,
    input m_axi_rvalid,
    output m_axi_rready,

    output [DATA_WIDTH-1:0] stream_data,
    output stream_valid,
    input stream_ready,
    output stream_frame_last
);
    localparam ST_IDLE = 2'd0, ST_AR = 2'd1, ST_DATA = 2'd2;
    reg [1:0] state;
    reg [31:0] current_addr, next_row_addr;
    reg [31:0] row_index, height_reg, stride_reg;
    reg [31:0] row_beats_remaining, beats_per_row;
    reg [8:0] burst_beats;
    reg [8:0] beat_index;
    reg frame_error;

    wire [8:0] beats_to_4k = (13'd4096 - {1'b0,current_addr[11:0]}) >> 4;
    wire [8:0] row_limit = (row_beats_remaining > 32'd64) ? 9'd64 :
                           row_beats_remaining[8:0];
    wire [8:0] selected_burst = (beats_to_4k < row_limit) ?
                                beats_to_4k : row_limit;
    wire accept_read_data = (state == ST_DATA) && m_axi_rvalid && stream_ready;
    wire expected_last = (beat_index == burst_beats - 1'b1);
    wire final_beat = expected_last && (row_beats_remaining == burst_beats) &&
                      (row_index == height_reg - 1'b1);

    assign m_axi_arid = AXI_ID;
    assign m_axi_araddr = current_addr;
    assign m_axi_arlen = selected_burst[7:0] - 1'b1;
    assign m_axi_arsize = 3'd4;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock = 1'b0;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arprot = 3'b000;
    assign m_axi_arvalid = (state == ST_AR);
    assign m_axi_rready = (state == ST_DATA) && stream_ready;
    assign stream_data = m_axi_rdata;
    assign stream_valid = (state == ST_DATA) && m_axi_rvalid;
    assign stream_frame_last = stream_valid && final_beat;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= ST_IDLE;
            busy <= 0;
            done_pulse <= 0;
            error_pulse <= 0;
            current_addr <= 0;
            next_row_addr <= 0;
            row_index <= 0;
            height_reg <= 0;
            stride_reg <= 0;
            row_beats_remaining <= 0;
            beats_per_row <= 0;
            burst_beats <= 0;
            beat_index <= 0;
            frame_error <= 0;
        end else begin
            done_pulse <= 0;
            error_pulse <= 0;
            case (state)
                ST_IDLE: begin
                    busy <= 0;
                    if (start_frame) begin
                        if ((cfg_base_addr[3:0] != 0) ||
                            (cfg_width == 0) || (cfg_width[1:0] != 0) ||
                            (cfg_height == 0) ||
                            (cfg_stride < (cfg_width << 2)) ||
                            (cfg_stride[3:0] != 0)) begin
                            error_pulse <= 1;
                        end else begin
                            busy <= 1;
                            frame_error <= 0;
                            current_addr <= cfg_base_addr;
                            next_row_addr <= cfg_base_addr + cfg_stride;
                            row_index <= 0;
                            height_reg <= cfg_height;
                            stride_reg <= cfg_stride;
                            beats_per_row <= cfg_width >> 2;
                            row_beats_remaining <= cfg_width >> 2;
                            state <= ST_AR;
                        end
                    end
                end
                ST_AR: begin
                    if (m_axi_arready) begin
                        burst_beats <= selected_burst;
                        beat_index <= 0;
                        state <= ST_DATA;
                    end
                end
                ST_DATA: begin
                    if (accept_read_data) begin
                        if ((m_axi_rid != AXI_ID) || (m_axi_rresp != 2'b00) ||
                            (m_axi_rlast != expected_last))
                            frame_error <= 1;
                        if (expected_last) begin
                            if (row_beats_remaining == burst_beats) begin
                                if (row_index == height_reg - 1'b1) begin
                                    busy <= 0;
                                    done_pulse <= 1;
                                    error_pulse <= frame_error ||
                                                   (m_axi_rid != AXI_ID) ||
                                                   (m_axi_rresp != 2'b00) ||
                                                   (m_axi_rlast != expected_last);
                                    state <= ST_IDLE;
                                end else begin
                                    row_index <= row_index + 1'b1;
                                    current_addr <= next_row_addr;
                                    next_row_addr <= next_row_addr + stride_reg;
                                    row_beats_remaining <= beats_per_row;
                                    state <= ST_AR;
                                end
                            end else begin
                                current_addr <= current_addr + (burst_beats << 4);
                                row_beats_remaining <= row_beats_remaining - burst_beats;
                                state <= ST_AR;
                            end
                        end else begin
                            beat_index <= beat_index + 1'b1;
                        end
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
