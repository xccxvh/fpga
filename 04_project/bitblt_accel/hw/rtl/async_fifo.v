`timescale 1ns/1ps

// Dual-clock FIFO with Gray-coded pointer synchronization.
// Default capacity is 512 x 128-bit words (4096 RGB565 pixels).
module async_fifo #(
    parameter DATA_WIDTH = 128,
    parameter ADDR_WIDTH = 9,
    parameter ALMOST_EMPTY_LEVEL = 32
) (
    input w_clk, input w_resetn,
    input [DATA_WIDTH-1:0] w_data,
    input w_valid, output w_ready,
    output w_full,
    input r_clk, input r_resetn,
    output [DATA_WIDTH-1:0] r_data,
    output r_valid, input r_ready,
    output r_empty,
    output r_almost_empty
);
    localparam DEPTH = (1 << ADDR_WIDTH);
    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    reg [ADDR_WIDTH:0] w_bin, w_gray, r_bin, r_gray;
    reg [ADDR_WIDTH:0] r_gray_wsync1, r_gray_wsync2;
    reg [ADDR_WIDTH:0] w_gray_rsync1, w_gray_rsync2;
    wire w_push = w_valid && w_ready;
    wire r_pop = r_valid && r_ready;
    wire [ADDR_WIDTH:0] w_bin_next = w_bin + w_push;
    wire [ADDR_WIDTH:0] r_bin_next = r_bin + r_pop;
    wire [ADDR_WIDTH:0] w_gray_next = (w_bin_next >> 1) ^ w_bin_next;
    wire [ADDR_WIDTH:0] r_gray_next = (r_bin_next >> 1) ^ r_bin_next;
    wire full_next = (w_gray_next ==
                     {~r_gray_wsync2[ADDR_WIDTH:ADDR_WIDTH-1],
                       r_gray_wsync2[ADDR_WIDTH-2:0]});
    wire empty_now = (r_gray == w_gray_rsync2);
    wire [ADDR_WIDTH:0] r_used = gray_to_bin(w_gray_rsync2) - r_bin;
    reg full_reg;

    function [ADDR_WIDTH:0] gray_to_bin;
        input [ADDR_WIDTH:0] gray;
        integer i;
        begin
            gray_to_bin[ADDR_WIDTH] = gray[ADDR_WIDTH];
            for (i=ADDR_WIDTH-1; i>=0; i=i-1)
                gray_to_bin[i] = gray_to_bin[i+1] ^ gray[i];
        end
    endfunction

    assign w_full = full_reg;
    assign w_ready = !full_reg;
    assign r_empty = empty_now;
    assign r_valid = !empty_now;
    assign r_data = memory[r_bin[ADDR_WIDTH-1:0]];
    assign r_almost_empty = (r_used <= ALMOST_EMPTY_LEVEL);

    always @(posedge w_clk or negedge w_resetn) begin
        if (!w_resetn) begin
            w_bin <= 0; w_gray <= 0; full_reg <= 0;
            r_gray_wsync1 <= 0; r_gray_wsync2 <= 0;
        end else begin
            r_gray_wsync1 <= r_gray;
            r_gray_wsync2 <= r_gray_wsync1;
            if (w_push) memory[w_bin[ADDR_WIDTH-1:0]] <= w_data;
            w_bin <= w_bin_next;
            w_gray <= w_gray_next;
            full_reg <= full_next;
        end
    end

    always @(posedge r_clk or negedge r_resetn) begin
        if (!r_resetn) begin
            r_bin <= 0; r_gray <= 0;
            w_gray_rsync1 <= 0; w_gray_rsync2 <= 0;
        end else begin
            w_gray_rsync1 <= w_gray;
            w_gray_rsync2 <= w_gray_rsync1;
            r_bin <= r_bin_next;
            r_gray <= r_gray_next;
        end
    end
endmodule
