`timescale 1ns/1ps
module tb_async_fifo;
  reg wc=0,rc=0,wrstn=0,rrstn=0; always #3 wc=~wc; always #7 rc=~rc;
  wire [31:0] wd=written; wire wv=wrstn && (written<100); wire wr,full;
  wire [31:0] rd; wire rv,empty,almost; reg rr=0;
  integer written=0,read=0,cycles=0;
  async_fifo #(.DATA_WIDTH(32),.ADDR_WIDTH(4),.ALMOST_EMPTY_LEVEL(3)) dut(
    .w_clk(wc),.w_resetn(wrstn),.w_data(wd),.w_valid(wv),.w_ready(wr),.w_full(full),
    .r_clk(rc),.r_resetn(rrstn),.r_data(rd),.r_valid(rv),.r_ready(rr),
    .r_empty(empty),.r_almost_empty(almost));
  always @(posedge wc) begin
    if(wv && wr) written<=written+1;
  end
  always @(posedge rc) begin
    if(rrstn) begin
      cycles<=cycles+1; rr<=((cycles%4)!=0);
      if(rv && rr) begin
        if(rd!==read) $fatal(1,"FIFO ordering expected=%0d got=%0d",read,rd);
        read<=read+1;
        if(read==99) begin $display("PASS: asynchronous FIFO ordering/backpressure"); $finish; end
      end
    end
  end
  initial begin
    repeat(4) @(posedge wc); wrstn<=1;
    repeat(3) @(posedge rc); rrstn<=1;
    #100000 $fatal(1,"FIFO timeout written=%0d read=%0d",written,read);
  end
endmodule
