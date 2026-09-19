`timescale 1ns/1ps

// BitBlt data plane: Solid Fill, buffered Block Copy and RGB Color Key Copy.
// Transfers use up to 16 128-bit beats and never cross a 4 KiB boundary.
module bitblt_engine (
    input clk, input resetn, input start,
    input [31:0] src_addr, input [31:0] dst_addr,
    input [31:0] width, input [31:0] height,
    input [31:0] src_stride, input [31:0] dst_stride,
    input [31:0] color, input [31:0] operation,
    output reg busy, output reg done, output reg error,

    output [7:0] m_awid, output reg [31:0] m_awaddr,
    output [7:0] m_awlen, output [2:0] m_awsize,
    output [1:0] m_awburst, output m_awlock,
    output [3:0] m_awcache, output [2:0] m_awprot,
    output reg m_awvalid, input m_awready,
    output [127:0] m_wdata, output [15:0] m_wstrb,
    output m_wlast, output reg m_wvalid, input m_wready,
    input [7:0] m_bid, input [1:0] m_bresp,
    input m_bvalid, output m_bready,

    output [7:0] m_arid, output reg [31:0] m_araddr,
    output [7:0] m_arlen, output [2:0] m_arsize,
    output [1:0] m_arburst, output m_arlock,
    output [3:0] m_arcache, output [2:0] m_arprot,
    output reg m_arvalid, input m_arready,
    input [7:0] m_rid, input [127:0] m_rdata,
    input [1:0] m_rresp, input m_rlast,
    input m_rvalid, output m_rready
);
    localparam OP_FILL = 32'd0, OP_COPY = 32'd1, OP_COLOR_KEY = 32'd2;
    localparam ST_IDLE = 3'd0, ST_AR = 3'd1, ST_R = 3'd2,
               ST_AW = 3'd3, ST_W = 3'd4, ST_B = 3'd5;
    reg [2:0] state;
    reg [127:0] copy_buffer [0:15];
    reg [31:0] src_row_base, dst_row_base;
    reg [31:0] row_index, beats_per_row, row_beats_remaining;
    reg [31:0] height_latched, src_stride_latched, dst_stride_latched;
    reg [31:0] color_latched, operation_latched;
    reg [4:0] burst_beats, read_index, write_index;
    reg read_error;

    assign m_awid = 8'h00;
    assign m_awlen = {3'd0, burst_beats} - 1'b1;
    assign m_awsize = 3'd4;
    assign m_awburst = 2'b01;
    assign m_awlock = 1'b0;
    assign m_awcache = 4'b0011;
    assign m_awprot = 3'b000;
    assign m_wdata = (operation_latched != OP_FILL) ? copy_buffer[write_index[3:0]]
                                                    : {4{color_latched}};
    // XRGB8888 Color Key compares RGB only. Each matching pixel disables its
    // four byte lanes so the existing destination pixel remains unchanged.
    assign m_wstrb = (operation_latched == OP_COLOR_KEY) ? {
        (copy_buffer[write_index[3:0]][119:96] == color_latched[23:0]) ? 4'h0 : 4'hf,
        (copy_buffer[write_index[3:0]][87:64]  == color_latched[23:0]) ? 4'h0 : 4'hf,
        (copy_buffer[write_index[3:0]][55:32]  == color_latched[23:0]) ? 4'h0 : 4'hf,
        (copy_buffer[write_index[3:0]][23:0]   == color_latched[23:0]) ? 4'h0 : 4'hf
    } : 16'hffff;
    assign m_wlast = (write_index + 1'b1 == burst_beats);
    assign m_bready = (state == ST_B);

    assign m_arid = 8'h00;
    assign m_arlen = {3'd0, burst_beats} - 1'b1;
    assign m_arsize = 3'd4;
    assign m_arburst = 2'b01;
    assign m_arlock = 1'b0;
    assign m_arcache = 4'b0011;
    assign m_arprot = 3'b000;
    assign m_rready = (state == ST_R);

    function [8:0] boundary_beats;
        input [31:0] address;
        begin
            if (address[11:0] > 12'hf00)
                boundary_beats = (13'h1000 - {1'b0, address[11:0]}) >> 4;
            else
                boundary_beats = 9'd16;
        end
    endfunction

    function [4:0] transfer_size;
        input [31:0] remaining;
        input [31:0] source_address;
        input [31:0] destination_address;
        input do_read;
        reg [8:0] limit;
        begin
            limit = boundary_beats(destination_address);
            if (do_read && (boundary_beats(source_address) < limit))
                limit = boundary_beats(source_address);
            if (remaining < limit)
                transfer_size = remaining[4:0];
            else if (limit < 16)
                transfer_size = limit[4:0];
            else
                transfer_size = 5'd16;
        end
    endfunction

    task finish_with_error;
        begin
            busy <= 1'b0;
            done <= 1'b1;
            error <= 1'b1;
            m_awvalid <= 1'b0;
            m_wvalid <= 1'b0;
            m_arvalid <= 1'b0;
            state <= ST_IDLE;
        end
    endtask

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= ST_IDLE;
            busy <= 1'b0; done <= 1'b0; error <= 1'b0;
            m_awaddr <= 32'd0; m_awvalid <= 1'b0; m_wvalid <= 1'b0;
            m_araddr <= 32'd0; m_arvalid <= 1'b0;
            src_row_base <= 32'd0; dst_row_base <= 32'd0;
            row_index <= 32'd0; beats_per_row <= 32'd0;
            row_beats_remaining <= 32'd0;
            height_latched <= 32'd0;
            src_stride_latched <= 32'd0; dst_stride_latched <= 32'd0;
            color_latched <= 32'd0; operation_latched <= OP_FILL;
            burst_beats <= 5'd1; read_index <= 5'd0; write_index <= 5'd0;
            read_error <= 1'b0;
        end else begin
            done <= 1'b0;
            error <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    m_awvalid <= 1'b0; m_wvalid <= 1'b0; m_arvalid <= 1'b0;
                    if (start) begin
                        if ((operation > OP_COLOR_KEY) || (width == 0) || (height == 0) ||
                            (width[1:0] != 0) || (dst_addr[3:0] != 0) ||
                            (dst_stride[3:0] != 0) || (dst_stride < (width << 2)) ||
                            ((operation != OP_FILL) &&
                             ((src_addr[3:0] != 0) || (src_stride[3:0] != 0) ||
                              (src_stride < (width << 2))))) begin
                            done <= 1'b1;
                            error <= 1'b1;
                        end else begin
                            busy <= 1'b1;
                            src_row_base <= src_addr; dst_row_base <= dst_addr;
                            m_araddr <= src_addr; m_awaddr <= dst_addr;
                            row_index <= 32'd0;
                            beats_per_row <= width >> 2;
                            row_beats_remaining <= width >> 2;
                            height_latched <= height;
                            src_stride_latched <= src_stride;
                            dst_stride_latched <= dst_stride;
                            color_latched <= color;
                            operation_latched <= operation;
                            burst_beats <= transfer_size(width >> 2, src_addr, dst_addr,
                                                         operation != OP_FILL);
                            read_index <= 5'd0; write_index <= 5'd0; read_error <= 1'b0;
                            if (operation != OP_FILL) begin
                                m_arvalid <= 1'b1;
                                state <= ST_AR;
                            end else begin
                                m_awvalid <= 1'b1;
                                state <= ST_AW;
                            end
                        end
                    end
                end
                ST_AR: if (m_arvalid && m_arready) begin
                    m_arvalid <= 1'b0;
                    read_index <= 5'd0;
                    read_error <= 1'b0;
                    state <= ST_R;
                end
                ST_R: if (m_rvalid) begin
                    copy_buffer[read_index[3:0]] <= m_rdata;
                    if ((m_rresp != 2'b00) || (m_rid != 8'h00))
                        read_error <= 1'b1;
                    if (m_rlast) begin
                        if ((read_index + 1'b1 != burst_beats) || read_error ||
                            (m_rresp != 2'b00) || (m_rid != 8'h00)) begin
                            finish_with_error();
                        end else begin
                            write_index <= 5'd0;
                            m_awvalid <= 1'b1;
                            state <= ST_AW;
                        end
                    end else if (read_index + 1'b1 == burst_beats) begin
                        finish_with_error();
                    end else begin
                        read_index <= read_index + 1'b1;
                    end
                end
                ST_AW: if (m_awvalid && m_awready) begin
                    m_awvalid <= 1'b0;
                    write_index <= 5'd0;
                    m_wvalid <= 1'b1;
                    state <= ST_W;
                end
                ST_W: if (m_wvalid && m_wready) begin
                    if (m_wlast) begin
                        m_wvalid <= 1'b0;
                        state <= ST_B;
                    end else begin
                        write_index <= write_index + 1'b1;
                    end
                end
                ST_B: if (m_bvalid) begin
                    if ((m_bresp != 2'b00) || (m_bid != 8'h00)) begin
                        finish_with_error();
                    end else if (row_beats_remaining > burst_beats) begin
                        row_beats_remaining <= row_beats_remaining - burst_beats;
                        m_araddr <= m_araddr + ({27'd0, burst_beats} << 4);
                        m_awaddr <= m_awaddr + ({27'd0, burst_beats} << 4);
                        burst_beats <= transfer_size(row_beats_remaining - burst_beats,
                            m_araddr + ({27'd0, burst_beats} << 4),
                            m_awaddr + ({27'd0, burst_beats} << 4),
                            operation_latched != OP_FILL);
                        read_index <= 5'd0; write_index <= 5'd0;
                        if (operation_latched != OP_FILL) begin
                            m_arvalid <= 1'b1; state <= ST_AR;
                        end else begin
                            m_awvalid <= 1'b1; state <= ST_AW;
                        end
                    end else if (row_index + 1 < height_latched) begin
                        row_index <= row_index + 1'b1;
                        src_row_base <= src_row_base + src_stride_latched;
                        dst_row_base <= dst_row_base + dst_stride_latched;
                        m_araddr <= src_row_base + src_stride_latched;
                        m_awaddr <= dst_row_base + dst_stride_latched;
                        row_beats_remaining <= beats_per_row;
                        burst_beats <= transfer_size(beats_per_row,
                            src_row_base + src_stride_latched,
                            dst_row_base + dst_stride_latched,
                            operation_latched != OP_FILL);
                        read_index <= 5'd0; write_index <= 5'd0;
                        if (operation_latched != OP_FILL) begin
                            m_arvalid <= 1'b1; state <= ST_AR;
                        end else begin
                            m_awvalid <= 1'b1; state <= ST_AW;
                        end
                    end else begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end
                end
                default: finish_with_error();
            endcase
        end
    end
endmodule
