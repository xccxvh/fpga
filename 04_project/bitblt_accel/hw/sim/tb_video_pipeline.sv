`timescale 1ns/1ps
module tb_video_pipeline;
  reg clk=0,resetn=0; always #5 clk=~clk;
  wire hs,vs,de,vblank; wire [11:0] x; wire [10:0] y;
  reg [127:0] data=128'h00AABBCC_00112233_00445566_00778899;
  reg valid=0; wire ready; wire [7:0] r,g,b; wire pvalid,underflow;
  integer de_count=0,vblank_count=0,hs_high=0,vs_high=0;
  video_timing_1920x1080 timing(.pixel_clk(clk),.resetn(resetn),.hsync(hs),.vsync(vs),
    .data_enable(de),.vblank_pulse(vblank),.pixel_x(x),.pixel_y(y));
  pixel_unpack_xrgb8888 unpack(.pixel_clk(clk),.resetn(resetn),.pixel_request(de),
    .stream_data(data),.stream_valid(valid),.stream_ready(ready),.red(r),.green(g),
    .blue(b),.pixel_valid(pvalid),.underflow_pulse(underflow));

  always @(posedge clk) if(resetn) begin
    if(de) de_count<=de_count+1;
    if(hs) hs_high<=hs_high+1;
    if(vs) vs_high<=vs_high+1;
    if(vblank) vblank_count<=vblank_count+1;
  end
  initial begin
    repeat(3) @(posedge clk); resetn<=1;
    // Prefetch and verify little-endian XRGB channel selection.
    valid<=1; @(posedge clk); valid<=0;
    @(posedge clk);
    if(!pvalid || {r,g,b}!==24'h778899) $fatal(1,"pixel0 unpack failed");
    // Let one whole timing frame elapse.
    @(negedge clk); de_count=0; hs_high=0; vs_high=0; vblank_count=0;
    repeat(2200*1125) @(posedge clk);
    #1;
    if(de_count!=1920*1080 || hs_high!=44*1125 || vs_high!=5*2200 || vblank_count!=1)
      $fatal(1,"timing counts de=%0d hs=%0d vs=%0d vb=%0d",de_count,hs_high,vs_high,vblank_count);
    $display("PASS: 1920x1080 timing and XRGB8888 pixel unpack"); $finish;
  end
endmodule
