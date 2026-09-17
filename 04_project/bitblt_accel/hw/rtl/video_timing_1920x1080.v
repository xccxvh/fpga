`timescale 1ns/1ps

// CTA-861 1920x1080p60 timing used by the board-tested HDMI color-bar demo.
// The board PLL produces approximately 148.75 MHz from its 25 MHz reference.
module video_timing_1920x1080 (
    input pixel_clk,
    input resetn,
    output hsync,
    output vsync,
    output data_enable,
    output reg vblank_pulse,
    output [11:0] pixel_x,
    output [10:0] pixel_y
);
    localparam H_ACTIVE=1920, H_FP=88, H_SYNC=44, H_BP=148, H_TOTAL=2200;
    localparam V_ACTIVE=1080, V_FP=4, V_SYNC=5, V_BP=36, V_TOTAL=1125;
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
