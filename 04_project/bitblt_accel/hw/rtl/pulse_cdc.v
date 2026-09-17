`timescale 1ns/1ps

// Transfers isolated pulses between asynchronous clock domains using a toggle.
module pulse_cdc (
    input src_clk, input src_resetn, input src_pulse,
    input dst_clk, input dst_resetn, output dst_pulse
);
    reg src_toggle;
    reg dst_sync1, dst_sync2, dst_sync2_d;
    assign dst_pulse = dst_sync2 ^ dst_sync2_d;
    always @(posedge src_clk or negedge src_resetn) begin
        if (!src_resetn) src_toggle <= 0;
        else if (src_pulse) src_toggle <= ~src_toggle;
    end
    always @(posedge dst_clk or negedge dst_resetn) begin
        if (!dst_resetn) begin
            dst_sync1 <= 0; dst_sync2 <= 0; dst_sync2_d <= 0;
        end else begin
            dst_sync1 <= src_toggle;
            dst_sync2 <= dst_sync1;
            dst_sync2_d <= dst_sync2;
        end
    end
endmodule
