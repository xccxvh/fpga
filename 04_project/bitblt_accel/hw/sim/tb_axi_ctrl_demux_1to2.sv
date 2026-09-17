`timescale 1ns/1ps
module tb_axi_ctrl_demux_1to2;
    reg clk=0, resetn=0; always #5 clk=~clk;
    reg [31:0] awaddr=0, araddr=0; reg awvalid=0,wvalid=0,arvalid=0;
    reg [7:0] awid=0,arid=0; wire awready,wready,arready;
    wire [7:0] bid,rid; wire [1:0] bresp,rresp;
    wire bvalid,rvalid,rlast; reg bready=1,rready=1;
    wire [31:0] rdata;
    wire m0awv,m1awv,m0wv,m1wv,m0arv,m1arv,m0br,m1br,m0rr,m1rr;
    reg m0awr=1,m1awr=1,m0wr=1,m1wr=1,m0bv=0,m1bv=0;
    reg m0arr=1,m1arr=1,m0rv=0,m1rv=0;

    axi_ctrl_demux_1to2 dut(
      .clk(clk),.resetn(resetn),.s_awaddr(awaddr),.s_awvalid(awvalid),.s_awready(awready),
      .s_wvalid(wvalid),.s_wready(wready),.s_bid(bid),.s_bresp(bresp),.s_bvalid(bvalid),
      .s_bready(bready),.s_awid(awid),.s_araddr(araddr),.s_arvalid(arvalid),.s_arready(arready),
      .s_rid(rid),.s_rdata(rdata),.s_rresp(rresp),.s_rlast(rlast),.s_rvalid(rvalid),
      .s_rready(rready),.s_arid(arid),
      .m0_awvalid(m0awv),.m0_awready(m0awr),.m0_wvalid(m0wv),.m0_wready(m0wr),
      .m0_bid(8'h10),.m0_bresp(2'b00),.m0_bvalid(m0bv),.m0_bready(m0br),
      .m0_arvalid(m0arv),.m0_arready(m0arr),.m0_rid(8'h20),.m0_rdata(32'h1111),
      .m0_rresp(2'b00),.m0_rlast(1'b1),.m0_rvalid(m0rv),.m0_rready(m0rr),
      .m1_awvalid(m1awv),.m1_awready(m1awr),.m1_wvalid(m1wv),.m1_wready(m1wr),
      .m1_bid(8'h11),.m1_bresp(2'b00),.m1_bvalid(m1bv),.m1_bready(m1br),
      .m1_arvalid(m1arv),.m1_arready(m1arr),.m1_rid(8'h21),.m1_rdata(32'h2222),
      .m1_rresp(2'b00),.m1_rlast(1'b1),.m1_rvalid(m1rv),.m1_rready(m1rr));

    task automatic write_target(input [31:0] addr, input integer target);
      begin
        @(posedge clk); awaddr<=addr; awvalid<=1;
        @(posedge clk);
        if (!awready || (target==0 && !m0awv) || (target==1 && !m1awv)) $fatal(1,"AW route");
        awvalid<=0; wvalid<=1;
        @(posedge clk);
        if (!wready || (target==0 && !m0wv) || (target==1 && !m1wv)) $fatal(1,"W route");
        wvalid<=0;
        if(target==0) m0bv<=1; else if(target==1) m1bv<=1;
        @(posedge clk);
        if(!bvalid || (target<2 && bresp!=0) || (target==2 && bresp!=3)) $fatal(1,"B route");
        m0bv<=0; m1bv<=0;
        @(posedge clk);
      end
    endtask

    task automatic read_target(input [31:0] addr, input integer target);
      begin
        @(posedge clk); araddr<=addr; arvalid<=1;
        @(posedge clk);
        if (!arready || (target==0 && !m0arv) || (target==1 && !m1arv)) $fatal(1,"AR route");
        arvalid<=0;
        if(target==0) m0rv<=1; else if(target==1) m1rv<=1;
        @(posedge clk);
        if(!rvalid || (target==0 && rdata!=32'h1111) ||
           (target==1 && rdata!=32'h2222) || (target==2 && rresp!=3)) $fatal(1,"R route");
        m0rv<=0; m1rv<=0;
        @(posedge clk);
      end
    endtask

    initial begin
      repeat(3) @(posedge clk); resetn<=1;
      write_target(32'hE100_0010,0);
      write_target(32'hE110_0000,1);
      write_target(32'hE120_0000,2);
      read_target(32'hE100_0028,0);
      read_target(32'hE110_0028,1);
      read_target(32'hE120_0000,2);
      $display("PASS: AXI control address demultiplexer"); $finish;
    end
endmodule
