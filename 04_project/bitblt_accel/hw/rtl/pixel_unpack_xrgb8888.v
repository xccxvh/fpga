`timescale 1ns/1ps

// Converts a 128-bit FIFO stream into one little-endian XRGB8888 pixel/cycle.
// The FIFO can prefetch during blanking. A missing active pixel emits black and
// a one-cycle underflow indication.
module pixel_unpack_xrgb8888 (
    input pixel_clk,
    input resetn,
    input pixel_request,
    input [127:0] stream_data,
    input stream_valid,
    output stream_ready,
    output [7:0] red,
    output [7:0] green,
    output [7:0] blue,
    output pixel_valid,
    output reg underflow_pulse
);
    reg [127:0] word_reg;
    reg word_valid;
    reg [1:0] pixel_index;
    reg underflow_active;
    wire consume_last = pixel_request && word_valid && (pixel_index == 2'd3);
    wire load_word = stream_valid && stream_ready;
    wire [31:0] selected_pixel = (pixel_index == 0) ? word_reg[31:0] :
                                 (pixel_index == 1) ? word_reg[63:32] :
                                 (pixel_index == 2) ? word_reg[95:64] :
                                                      word_reg[127:96];
    assign stream_ready = !word_valid || consume_last;
    assign pixel_valid = word_valid;
    assign red   = word_valid ? selected_pixel[23:16] : 8'h00;
    assign green = word_valid ? selected_pixel[15:8]  : 8'h00;
    assign blue  = word_valid ? selected_pixel[7:0]   : 8'h00;

    always @(posedge pixel_clk or negedge resetn) begin
        if (!resetn) begin
            word_reg <= 0;
            word_valid <= 0;
            pixel_index <= 0;
            underflow_pulse <= 0;
            underflow_active <= 0;
        end else begin
            underflow_pulse <= pixel_request && !word_valid && !underflow_active;
            if (pixel_request && !word_valid)
                underflow_active <= 1;
            else if (word_valid || !pixel_request)
                underflow_active <= 0;
            if (load_word)
                word_reg <= stream_data;

            if (pixel_request && word_valid) begin
                if (pixel_index == 2'd3) begin
                    pixel_index <= 0;
                    word_valid <= load_word;
                end else begin
                    pixel_index <= pixel_index + 1'b1;
                end
            end else if (!word_valid && load_word) begin
                word_valid <= 1;
                pixel_index <= 0;
            end
        end
    end
endmodule
