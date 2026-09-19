`timescale 1ns/1ps

// CTA-861 1280x720p60 timing at 74.25 MHz, positive HSync and VSync.
module video_timing_1280x720 (
    input pixel_clk,
    input resetn,
    output hsync,
    output vsync,
    output data_enable,
    output reg vblank_pulse,
    output [11:0] pixel_x,
    output [10:0] pixel_y
);
    localparam H_ACTIVE=1280, H_FP=110, H_SYNC=40, H_BP=220, H_TOTAL=1650;
    localparam V_ACTIVE=720, V_FP=5, V_SYNC=5, V_BP=20, V_TOTAL=750;
    reg [11:0] h_count;
    reg [10:0] v_count;
    assign data_enable = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
    assign hsync = (h_count >= H_ACTIVE+H_FP) &&
                   (h_count < H_ACTIVE+H_FP+H_SYNC);
    assign vsync = (v_count >= V_ACTIVE+V_FP) &&
                   (v_count < V_ACTIVE+V_FP+V_SYNC);
    assign pixel_x = h_count;
    assign pixel_y = v_count;

    always @(posedge pixel_clk or negedge resetn) begin
        if (!resetn) begin
            h_count <= 0;
            v_count <= 0;
            vblank_pulse <= 0;
        end else begin
            vblank_pulse <= (h_count == 0) && (v_count == V_ACTIVE);
            if (h_count == H_TOTAL-1) begin
                h_count <= 0;
                if (v_count == V_TOTAL-1) v_count <= 0;
                else v_count <= v_count + 1'b1;
            end else begin
                h_count <= h_count + 1'b1;
            end
        end
    end
endmodule
