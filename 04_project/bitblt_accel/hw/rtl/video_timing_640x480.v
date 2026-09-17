`timescale 1ns/1ps

// 640x480p60 timing: 25.2 MHz pixel clock, negative HSYNC/VSYNC.
module video_timing_640x480 (
    input pixel_clk,
    input resetn,
    output hsync,
    output vsync,
    output data_enable,
    output reg vblank_pulse,
    output [9:0] pixel_x,
    output [9:0] pixel_y
);
    localparam H_ACTIVE=640, H_FP=16, H_SYNC=96, H_BP=48, H_TOTAL=800;
    localparam V_ACTIVE=480, V_FP=10, V_SYNC=2, V_BP=33, V_TOTAL=525;
    reg [9:0] h_count, v_count;
    assign data_enable = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
    assign hsync = ~((h_count >= H_ACTIVE+H_FP) &&
                     (h_count < H_ACTIVE+H_FP+H_SYNC));
    assign vsync = ~((v_count >= V_ACTIVE+V_FP) &&
                     (v_count < V_ACTIVE+V_FP+V_SYNC));
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
