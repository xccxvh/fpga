`timescale 1ns/1ps

module tb_axi_arbiters;
    reg clk = 0;
    reg resetn = 0;
    integer failures = 0;

    reg [7:0] s0_awid, s0_awlen, s1_awid, s1_awlen;
    reg [31:0] s0_awaddr, s1_awaddr;
    reg [2:0] s0_awsize, s1_awsize;
    reg [1:0] s0_awburst, s1_awburst;
    reg s0_awlock, s1_awlock;
    reg [3:0] s0_awcache, s1_awcache;
    reg [2:0] s0_awprot, s1_awprot;
    reg s0_awvalid, s1_awvalid;
    wire s0_awready, s1_awready;
    reg [127:0] s0_wdata, s1_wdata;
    reg [15:0] s0_wstrb, s1_wstrb;
    reg s0_wlast, s1_wlast, s0_wvalid, s1_wvalid;
    wire s0_wready, s1_wready;
    wire [7:0] s0_bid, s1_bid;
    wire [1:0] s0_bresp, s1_bresp;
    wire s0_bvalid, s1_bvalid;
    reg s0_bready, s1_bready;
    wire [7:0] m_awid, m_awlen;
    wire [31:0] m_awaddr;
    wire [2:0] m_awsize;
    wire [1:0] m_awburst;
    wire m_awlock;
    wire [3:0] m_awcache;
    wire [2:0] m_awprot;
    wire m_awvalid;
    reg m_awready;
    wire [127:0] m_wdata;
    wire [15:0] m_wstrb;
    wire m_wlast, m_wvalid;
    reg m_wready;
    reg [7:0] m_bid;
    reg [1:0] m_bresp;
    reg m_bvalid;
    wire m_bready;

    reg [7:0] s0_arid, s0_arlen, s1_arid, s1_arlen;
    reg [31:0] s0_araddr, s1_araddr;
    reg [2:0] s0_arsize, s1_arsize;
    reg [1:0] s0_arburst, s1_arburst;
    reg s0_arlock, s1_arlock;
    reg [3:0] s0_arcache, s1_arcache;
    reg [2:0] s0_arprot, s1_arprot;
    reg s0_arvalid, s1_arvalid;
    wire s0_arready, s1_arready;
    wire [7:0] s0_rid, s1_rid;
    wire [127:0] s0_rdata, s1_rdata;
    wire [1:0] s0_rresp, s1_rresp;
    wire s0_rlast, s1_rlast, s0_rvalid, s1_rvalid;
    reg s0_rready, s1_rready;
    wire [7:0] m_arid, m_arlen;
    wire [31:0] m_araddr;
    wire [2:0] m_arsize;
    wire [1:0] m_arburst;
    wire m_arlock;
    wire [3:0] m_arcache;
    wire [2:0] m_arprot;
    wire m_arvalid;
    reg m_arready;
    reg [7:0] m_rid;
    reg [127:0] m_rdata;
    reg [1:0] m_rresp;
    reg m_rlast, m_rvalid;
    wire m_rready;

    always #5 clk = ~clk;

    axi_write_arbiter_2to1 write_dut (
        .clk(clk), .resetn(resetn),
        .s0_awid(s0_awid), .s0_awaddr(s0_awaddr), .s0_awlen(s0_awlen),
        .s0_awsize(s0_awsize), .s0_awburst(s0_awburst), .s0_awlock(s0_awlock),
        .s0_awcache(s0_awcache), .s0_awprot(s0_awprot), .s0_awvalid(s0_awvalid), .s0_awready(s0_awready),
        .s0_wdata(s0_wdata), .s0_wstrb(s0_wstrb), .s0_wlast(s0_wlast), .s0_wvalid(s0_wvalid), .s0_wready(s0_wready),
        .s0_bid(s0_bid), .s0_bresp(s0_bresp), .s0_bvalid(s0_bvalid), .s0_bready(s0_bready),
        .s1_awid(s1_awid), .s1_awaddr(s1_awaddr), .s1_awlen(s1_awlen),
        .s1_awsize(s1_awsize), .s1_awburst(s1_awburst), .s1_awlock(s1_awlock),
        .s1_awcache(s1_awcache), .s1_awprot(s1_awprot), .s1_awvalid(s1_awvalid), .s1_awready(s1_awready),
        .s1_wdata(s1_wdata), .s1_wstrb(s1_wstrb), .s1_wlast(s1_wlast), .s1_wvalid(s1_wvalid), .s1_wready(s1_wready),
        .s1_bid(s1_bid), .s1_bresp(s1_bresp), .s1_bvalid(s1_bvalid), .s1_bready(s1_bready),
        .m_awid(m_awid), .m_awaddr(m_awaddr), .m_awlen(m_awlen), .m_awsize(m_awsize),
        .m_awburst(m_awburst), .m_awlock(m_awlock), .m_awcache(m_awcache), .m_awprot(m_awprot),
        .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast), .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bid(m_bid), .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready)
    );

    axi_read_arbiter_2to1 read_dut (
        .clk(clk), .resetn(resetn),
        .s0_arid(s0_arid), .s0_araddr(s0_araddr), .s0_arlen(s0_arlen),
        .s0_arsize(s0_arsize), .s0_arburst(s0_arburst), .s0_arlock(s0_arlock),
        .s0_arcache(s0_arcache), .s0_arprot(s0_arprot), .s0_arvalid(s0_arvalid), .s0_arready(s0_arready),
        .s0_rid(s0_rid), .s0_rdata(s0_rdata), .s0_rresp(s0_rresp), .s0_rlast(s0_rlast), .s0_rvalid(s0_rvalid), .s0_rready(s0_rready),
        .s1_arid(s1_arid), .s1_araddr(s1_araddr), .s1_arlen(s1_arlen),
        .s1_arsize(s1_arsize), .s1_arburst(s1_arburst), .s1_arlock(s1_arlock),
        .s1_arcache(s1_arcache), .s1_arprot(s1_arprot), .s1_arvalid(s1_arvalid), .s1_arready(s1_arready),
        .s1_rid(s1_rid), .s1_rdata(s1_rdata), .s1_rresp(s1_rresp), .s1_rlast(s1_rlast), .s1_rvalid(s1_rvalid), .s1_rready(s1_rready),
        .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen), .m_arsize(m_arsize),
        .m_arburst(m_arburst), .m_arlock(m_arlock), .m_arcache(m_arcache), .m_arprot(m_arprot),
        .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rid(m_rid), .m_rdata(m_rdata), .m_rresp(m_rresp), .m_rlast(m_rlast),
        .m_rvalid(m_rvalid), .m_rready(m_rready)
    );

    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            if (!condition) begin
                failures = failures + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    task defaults;
        begin
            s0_awid=8'h10; s0_awaddr=32'h1000; s0_awlen=0; s0_awsize=4;
            s0_awburst=1; s0_awlock=0; s0_awcache=0; s0_awprot=0; s0_awvalid=0;
            s1_awid=8'h20; s1_awaddr=32'h2000; s1_awlen=0; s1_awsize=4;
            s1_awburst=1; s1_awlock=0; s1_awcache=0; s1_awprot=0; s1_awvalid=0;
            s0_wdata=128'h1111; s0_wstrb='1; s0_wlast=1; s0_wvalid=0; s0_bready=1;
            s1_wdata=128'h2222; s1_wstrb='1; s1_wlast=1; s1_wvalid=0; s1_bready=1;
            m_awready=0; m_wready=0; m_bid=0; m_bresp=0; m_bvalid=0;

            s0_arid=8'h30; s0_araddr=32'h3000; s0_arlen=1; s0_arsize=4;
            s0_arburst=1; s0_arlock=0; s0_arcache=0; s0_arprot=0; s0_arvalid=0; s0_rready=1;
            s1_arid=8'h40; s1_araddr=32'h4000; s1_arlen=1; s1_arsize=4;
            s1_arburst=1; s1_arlock=0; s1_arcache=0; s1_arprot=0; s1_arvalid=0; s1_rready=1;
            m_arready=0; m_rid=0; m_rdata=0; m_rresp=0; m_rlast=0; m_rvalid=0;
        end
    endtask

    initial begin
        defaults();
        repeat (3) @(posedge clk);
        resetn = 1;
        @(negedge clk);

        // Both write masters request together: accelerator (s1) has priority.
        s0_awvalid = 1; s1_awvalid = 1; m_awready = 1;
        #1;
        check(m_awvalid && s1_awready && !s0_awready, "write priority must select s1");
        check((m_awid == s1_awid) && (m_awaddr == s1_awaddr), "write address must come from s1");
        @(posedge clk); #1;
        s1_awvalid = 0; m_awready = 0;
        s0_wvalid = 1; s1_wvalid = 1; m_wready = 1;
        #1;
        check(m_wvalid && s1_wready && !s0_wready, "write owner must remain s1");
        check(m_wdata == s1_wdata, "write data must come from s1");
        @(posedge clk); #1;
        s0_wvalid = 0; s1_wvalid = 0; m_wready = 0;
        m_bid = 8'h20; m_bresp = 0; m_bvalid = 1;
        #1;
        check(s1_bvalid && !s0_bvalid && m_bready, "write response must route to s1");
        @(posedge clk); #1;
        m_bvalid = 0;

        // The waiting CPU write (s0) is accepted next.
        m_awready = 1;
        #1;
        check(s0_awready && !s1_awready && (m_awaddr == s0_awaddr), "waiting s0 write must run next");
        @(posedge clk); #1;
        s0_awvalid = 0; m_awready = 0;
        s0_wvalid = 1; m_wready = 1;
        #1;
        check(s0_wready && (m_wdata == s0_wdata), "write owner must be s0");
        @(posedge clk); #1;
        s0_wvalid = 0; m_wready = 0; m_bid = 8'h10; m_bvalid = 1;
        #1;
        check(s0_bvalid && !s1_bvalid, "write response must route to s0");
        @(posedge clk); #1; m_bvalid = 0;
        $display("Write arbiter tests: PASSED");

        // Both read masters request together: accelerator (s1) has priority.
        @(negedge clk);
        s0_arvalid = 1; s1_arvalid = 1; m_arready = 1;
        #1;
        check(m_arvalid && s1_arready && !s0_arready, "read priority must select s1");
        check((m_arid == s1_arid) && (m_araddr == s1_araddr), "read address must come from s1");
        @(posedge clk); #1;
        s1_arvalid = 0; m_arready = 0;
        m_rid = 8'h40; m_rdata = 128'haaaa; m_rvalid = 1; m_rlast = 0;
        #1;
        check(s1_rvalid && !s0_rvalid && m_rready, "read data must route to s1");
        @(posedge clk); #1;
        m_rdata = 128'hbbbb; m_rlast = 1;
        #1;
        check(s1_rvalid && !s0_rvalid, "read ownership must remain s1 through RLAST");
        @(posedge clk); #1;
        m_rvalid = 0; m_rlast = 0;

        // The waiting CPU read (s0) is accepted next.
        m_arready = 1;
        #1;
        check(s0_arready && !s1_arready && (m_araddr == s0_araddr), "waiting s0 read must run next");
        @(posedge clk); #1;
        s0_arvalid = 0; m_arready = 0;
        m_rid = 8'h30; m_rdata = 128'hcccc; m_rvalid = 1; m_rlast = 1;
        #1;
        check(s0_rvalid && !s1_rvalid && m_rready, "read data must route to s0");
        @(posedge clk); #1;
        m_rvalid = 0; m_rlast = 0;
        $display("Read arbiter tests: PASSED");

        // With both requesters continuously valid, grants alternate by burst.
        @(negedge clk);
        s0_arvalid = 1; s1_arvalid = 1; m_arready = 1;
        #1;
        check(s1_arready && !s0_arready,
              "round-robin must grant s1 after the previous s0 grant");
        @(posedge clk); #1;
        m_arready = 0; m_rvalid = 1; m_rlast = 1;
        #1;
        check(s1_rvalid && !s0_rvalid, "round-robin s1 response routing");
        @(posedge clk); #1;
        m_rvalid = 0; m_rlast = 0; m_arready = 1;
        #1;
        check(s0_arready && !s1_arready,
              "round-robin must grant waiting s0 after s1");
        @(posedge clk); #1;
        s0_arvalid = 0; s1_arvalid = 0; m_arready = 0;
        m_rvalid = 1; m_rlast = 1;
        #1;
        check(s0_rvalid && !s1_rvalid, "round-robin s0 response routing");
        @(posedge clk); #1;
        m_rvalid = 0; m_rlast = 0;
        $display("Read arbiter fairness: PASSED");

        if (failures == 0) begin
            $display("AXI arbiter regression: PASSED");
            $finish;
        end else begin
            $display("AXI arbiter regression: FAILED (%0d failures)", failures);
            $fatal(1);
        end
    end
endmodule
