`timescale 1ns/1ps
module tb_display_dma_axi;
    reg clk=0, resetn=0; always #5 clk=~clk;
    reg start=0; reg [31:0] base=0,width=0,height=0,stride=0;
    wire busy,done,error;
    wire [7:0] arid,arlen; wire [31:0] araddr;
    wire [2:0] arsize; wire [1:0] arburst; wire arlock;
    wire [3:0] arcache; wire [2:0] arprot; wire arvalid;
    reg arready=1;
    reg [7:0] rid=8'hd1; reg [127:0] rdata=0;
    reg [1:0] rresp=0; reg rlast=0,rvalid=0; wire rready;
    wire [127:0] stream_data; wire stream_valid,stream_last;
    reg stream_ready=1;
    integer burst_remaining=0, total_beats=0, bursts=0, cycles=0;

    display_dma_axi dut(.clk(clk),.resetn(resetn),.start_frame(start),
      .cfg_base_addr(base),.cfg_width(width),.cfg_height(height),.cfg_stride(stride),
      .busy(busy),.done_pulse(done),.error_pulse(error),
      .m_axi_arid(arid),.m_axi_araddr(araddr),.m_axi_arlen(arlen),
      .m_axi_arsize(arsize),.m_axi_arburst(arburst),.m_axi_arlock(arlock),
      .m_axi_arcache(arcache),.m_axi_arprot(arprot),.m_axi_arvalid(arvalid),
      .m_axi_arready(arready),.m_axi_rid(rid),.m_axi_rdata(rdata),
      .m_axi_rresp(rresp),.m_axi_rlast(rlast),.m_axi_rvalid(rvalid),
      .m_axi_rready(rready),.stream_data(stream_data),.stream_valid(stream_valid),
      .stream_ready(stream_ready),.stream_frame_last(stream_last));

    // Minimal AXI memory responder. Insert stream backpressure periodically.
    always @(posedge clk) begin
      if(!resetn) begin rvalid<=0; burst_remaining<=0; total_beats<=0; bursts<=0; cycles<=0; end
      else begin
        cycles <= cycles+1;
        stream_ready <= ((cycles % 3) != 1);
        if(arvalid && arready) begin
          if(({1'b0,araddr[11:0]} + ((arlen+1)<<4)) > 4096) $fatal(1,"burst crossed 4KiB");
          if(arsize!=4 || arburst!=1) $fatal(1,"bad AR attributes");
          burst_remaining <= arlen+1;
          bursts <= bursts+1;
          rvalid <= 1;
          rlast <= (arlen==0);
          rdata <= {96'h0,araddr};
        end else if(rvalid && rready) begin
          total_beats <= total_beats+1;
          if(burst_remaining==1) begin
            rvalid<=0; rlast<=0; burst_remaining<=0;
          end else begin
            burst_remaining<=burst_remaining-1;
            rlast <= (burst_remaining==2);
            rdata <= rdata+16;
          end
        end
      end
    end

    initial begin
      repeat(4) @(posedge clk); resetn<=1;
      // Row 0 begins one beat before 4 KiB boundary: bursts 1+4.
      // Row 1 starts at base+96: one burst of 5 beats.
      @(posedge clk); base<=32'h0001_0ff0; width<=20; height<=2; stride<=96; start<=1;
      @(posedge clk); start<=0;
      wait(done); @(posedge clk);
      if(error || total_beats!=10 || bursts!=3) $fatal(1,"DMA frame result beats=%0d bursts=%0d",total_beats,bursts);
      // Invalid unaligned input must fail without issuing AXI traffic.
      @(posedge clk); base<=32'h0100_0004; width<=640; height<=480; stride<=2560; start<=1;
      @(posedge clk); start<=0;
      @(posedge clk);
      if(!error || busy) $fatal(1,"invalid configuration accepted");
      $display("PASS: display DMA burst, stride, 4KiB split and backpressure");
      $finish;
    end
endmodule
