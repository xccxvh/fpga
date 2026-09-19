`timescale 1ns/1ps

module tb_bitblt_ctrl_axi;
    localparam [31:0] BASE = 32'he100_0000;
    localparam [31:0] CONTROL = BASE + 32'h00;
    localparam [31:0] STATUS = BASE + 32'h04;
    localparam [31:0] SRC_ADDR = BASE + 32'h08;
    localparam [31:0] DST_ADDR = BASE + 32'h0c;
    localparam [31:0] WIDTH = BASE + 32'h10;
    localparam [31:0] HEIGHT = BASE + 32'h14;
    localparam [31:0] SRC_STRIDE = BASE + 32'h18;
    localparam [31:0] DST_STRIDE = BASE + 32'h1c;
    localparam [31:0] COLOR = BASE + 32'h20;
    localparam [31:0] OPERATION = BASE + 32'h24;
    localparam [31:0] VERSION = BASE + 32'h28;

    reg clk = 0;
    reg resetn = 0;
    integer failures = 0;
    integer start_count = 0;
    integer interrupt_count = 0;

    wire interrupt;
    reg [7:0] awid;
    reg [31:0] awaddr;
    reg [7:0] awlen;
    reg [2:0] awsize;
    reg [1:0] awburst;
    reg awlock;
    reg [3:0] awcache;
    reg [2:0] awprot;
    reg [3:0] awqos, awregion;
    reg awvalid;
    wire awready;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    reg wlast, wvalid;
    wire wready;
    wire [7:0] bid;
    wire [1:0] bresp;
    wire bvalid;
    reg bready;

    reg [7:0] arid;
    reg [31:0] araddr;
    reg [7:0] arlen;
    reg [2:0] arsize;
    reg [1:0] arburst;
    reg arlock;
    reg [3:0] arcache;
    reg [2:0] arprot;
    reg [3:0] arqos, arregion;
    reg arvalid;
    wire arready;
    wire [7:0] rid;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rlast, rvalid;
    reg rready;

    wire start_pulse;
    wire [31:0] cfg_src_addr, cfg_dst_addr, cfg_width, cfg_height;
    wire [31:0] cfg_src_stride, cfg_dst_stride, cfg_color, cfg_operation;
    reg engine_busy, engine_done, engine_error;

    always #5 clk = ~clk;

    bitblt_ctrl_axi dut (
        .axi_interrupt(interrupt), .axi_aclk(clk), .axi_resetn(resetn),
        .axi_awid(awid), .axi_awaddr(awaddr), .axi_awlen(awlen),
        .axi_awsize(awsize), .axi_awburst(awburst), .axi_awlock(awlock),
        .axi_awcache(awcache), .axi_awprot(awprot), .axi_awqos(awqos),
        .axi_awregion(awregion), .axi_awvalid(awvalid), .axi_awready(awready),
        .axi_wdata(wdata), .axi_wstrb(wstrb), .axi_wlast(wlast),
        .axi_wvalid(wvalid), .axi_wready(wready),
        .axi_bid(bid), .axi_bresp(bresp), .axi_bvalid(bvalid), .axi_bready(bready),
        .axi_arid(arid), .axi_araddr(araddr), .axi_arlen(arlen),
        .axi_arsize(arsize), .axi_arburst(arburst), .axi_arlock(arlock),
        .axi_arcache(arcache), .axi_arprot(arprot), .axi_arqos(arqos),
        .axi_arregion(arregion), .axi_arvalid(arvalid), .axi_arready(arready),
        .axi_rid(rid), .axi_rdata(rdata), .axi_rresp(rresp), .axi_rlast(rlast),
        .axi_rvalid(rvalid), .axi_rready(rready),
        .start_pulse(start_pulse), .cfg_src_addr(cfg_src_addr),
        .cfg_dst_addr(cfg_dst_addr), .cfg_width(cfg_width), .cfg_height(cfg_height),
        .cfg_src_stride(cfg_src_stride), .cfg_dst_stride(cfg_dst_stride),
        .cfg_color(cfg_color), .cfg_operation(cfg_operation),
        .engine_busy(engine_busy), .engine_done(engine_done), .engine_error(engine_error)
    );

    always @(posedge clk) begin
        if (start_pulse) start_count <= start_count + 1;
        if (interrupt) interrupt_count <= interrupt_count + 1;
    end

    task check;
        input condition;
        input [8*120-1:0] message;
        begin
            if (!condition) begin
                failures = failures + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    task write_register;
        input [31:0] address;
        input [31:0] value;
        input [3:0] strobes;
        input [7:0] burst_len;
        begin
            @(negedge clk);
            awid = 8'h35;
            awaddr = address;
            awlen = burst_len;
            awvalid = 1;
            while (!awready) @(negedge clk);
            @(posedge clk); #1;
            awvalid = 0;

            @(negedge clk);
            wdata = value;
            wstrb = strobes;
            wvalid = 1;
            while (!wready) @(negedge clk);
            @(posedge clk); #1;
            wvalid = 0;

            while (!bvalid) begin @(posedge clk); #1; end
            check(bid == 8'h35, "BID must match AWID");
            check(bresp == 2'b00, "BRESP must be OKAY");
            @(posedge clk); #1;
        end
    endtask

    task read_register;
        input [31:0] address;
        input [7:0] burst_len;
        output [31:0] value;
        begin
            @(negedge clk);
            arid = 8'h5a;
            araddr = address;
            arlen = burst_len;
            arvalid = 1;
            while (!arready) @(negedge clk);
            @(posedge clk); #1;
            arvalid = 0;
            while (!rvalid) begin @(posedge clk); #1; end
            value = rdata;
            check(rid == 8'h5a, "RID must match ARID");
            check(rresp == 2'b00, "RRESP must be OKAY");
            check(rlast, "single register read must assert RLAST");
            @(posedge clk); #1;
        end
    endtask

    task expect_read;
        input [31:0] address;
        input [31:0] expected_value;
        input [8*100-1:0] message;
        reg [31:0] value;
        begin
            read_register(address, 0, value);
            if (value !== expected_value) begin
                failures = failures + 1;
                $display("FAIL: %0s got=%08x expected=%08x", message, value, expected_value);
            end
        end
    endtask

    task clear_status;
        begin
            write_register(CONTROL, 32'h2, 4'hf, 0);
            expect_read(STATUS, engine_busy ? 32'h1 : 32'h0, "CLEAR must clear DONE/ERROR");
        end
    endtask

    task pulse_engine_completion;
        input completion_error;
        begin
            @(negedge clk);
            engine_error = completion_error;
            engine_done = 1;
            @(negedge clk);
            engine_done = 0;
            engine_error = 0;
            @(posedge clk); #1;
        end
    endtask

    task simultaneous_aw_w;
        input [31:0] address;
        input [31:0] value;
        begin
            @(negedge clk);
            awid = 8'h6c;
            awaddr = address;
            awlen = 0;
            wdata = value;
            wstrb = 4'hf;
            awvalid = 1;
            wvalid = 1;
            #1;
            check(awready && !wready, "AW accepted first when AW/W arrive together");
            @(posedge clk); #1;
            awvalid = 0;
            check(wready, "held WVALID must become ready after AW handshake");
            @(posedge clk); #1;
            wvalid = 0;
            while (!bvalid) begin @(posedge clk); #1; end
            check(bid == 8'h6c, "simultaneous AW/W BID must match");
            @(posedge clk); #1;
        end
    endtask

    task w_before_aw;
        input [31:0] address;
        input [31:0] value;
        begin
            @(negedge clk);
            wdata = value;
            wstrb = 4'hf;
            wvalid = 1;
            #1;
            check(!wready, "W arriving before AW must be held off");
            repeat (2) @(posedge clk);
            @(negedge clk);
            awid = 8'h7d;
            awaddr = address;
            awlen = 0;
            awvalid = 1;
            while (!awready) @(negedge clk);
            @(posedge clk); #1;
            awvalid = 0;
            check(wready, "early W must be accepted after AW");
            @(posedge clk); #1;
            wvalid = 0;
            while (!bvalid) begin @(posedge clk); #1; end
            check(bid == 8'h7d, "W-before-AW BID must match");
            @(posedge clk); #1;
        end
    endtask

    reg [31:0] value;
    integer previous_count;
    initial begin
        awid=0; awaddr=0; awlen=0; awsize=3'd2; awburst=2'b01;
        awlock=0; awcache=0; awprot=0; awqos=0; awregion=0; awvalid=0;
        wdata=0; wstrb=4'hf; wlast=1; wvalid=0; bready=1;
        arid=0; araddr=0; arlen=0; arsize=3'd2; arburst=2'b01;
        arlock=0; arcache=0; arprot=0; arqos=0; arregion=0; arvalid=0; rready=1;
        engine_busy=0; engine_done=0; engine_error=0;

        repeat (4) @(posedge clk);
        resetn = 1;
        repeat (2) @(posedge clk);

        expect_read(CONTROL, 0, "CONTROL reset/read value");
        expect_read(STATUS, 0, "STATUS reset value");
        expect_read(SRC_ADDR, 0, "SRC_ADDR reset value");
        expect_read(DST_ADDR, 0, "DST_ADDR reset value");
        expect_read(WIDTH, 0, "WIDTH reset value");
        expect_read(HEIGHT, 0, "HEIGHT reset value");
        expect_read(SRC_STRIDE, 0, "SRC_STRIDE reset value");
        expect_read(DST_STRIDE, 0, "DST_STRIDE reset value");
        expect_read(COLOR, 0, "COLOR reset value");
        expect_read(OPERATION, 0, "OPERATION reset value");
        expect_read(VERSION, 32'h0002_0000, "VERSION value");
        $display("Register reset tests: PASSED");

        write_register(SRC_ADDR, 32'h0110_0000, 4'hf, 0);
        write_register(DST_ADDR, 32'h0120_0000, 4'hf, 0);
        write_register(WIDTH, 32'd80, 4'hf, 0);
        write_register(HEIGHT, 32'd3, 4'hf, 0);
        write_register(SRC_STRIDE, 32'd384, 4'hf, 0);
        write_register(DST_STRIDE, 32'd416, 4'hf, 0);
        write_register(COLOR, 32'ha5c3_f00d, 4'hf, 0);
        write_register(OPERATION, 32'd1, 4'hf, 0);
        expect_read(SRC_ADDR, 32'h0110_0000, "SRC_ADDR readback");
        expect_read(DST_ADDR, 32'h0120_0000, "DST_ADDR readback");
        expect_read(WIDTH, 32'd80, "WIDTH readback");
        expect_read(HEIGHT, 32'd3, "HEIGHT readback");
        expect_read(SRC_STRIDE, 32'd384, "SRC_STRIDE readback");
        expect_read(DST_STRIDE, 32'd416, "DST_STRIDE readback");
        expect_read(COLOR, 32'ha5c3_f00d, "COLOR readback");
        expect_read(OPERATION, 32'd1, "OPERATION readback");
        check(cfg_src_addr == 32'h0110_0000 && cfg_dst_addr == 32'h0120_0000,
              "configuration outputs must mirror registers");
        $display("Register read/write tests: PASSED");

        previous_count = start_count;
        write_register(CONTROL, 1, 4'hf, 0);
        repeat (2) @(posedge clk);
        check(start_count == previous_count + 1, "START must produce exactly one pulse");
        expect_read(STATUS, 0, "valid START must clear prior status");

        engine_busy = 1;
        previous_count = start_count;
        write_register(CONTROL, 1, 4'hf, 0);
        repeat (2) @(posedge clk);
        check(start_count == previous_count, "START while BUSY must be rejected");
        expect_read(STATUS, 32'h5, "BUSY START must expose BUSY+ERROR");
        clear_status();
        engine_busy = 0;
        $display("START/BUSY tests: PASSED");

        previous_count = interrupt_count;
        pulse_engine_completion(0);
        check(interrupt_count == previous_count + 1, "completion must pulse interrupt once");
        expect_read(STATUS, 32'h2, "successful completion must set DONE");
        repeat (3) @(posedge clk);
        expect_read(STATUS, 32'h2, "DONE must remain sticky");
        clear_status();

        previous_count = interrupt_count;
        pulse_engine_completion(1);
        check(interrupt_count == previous_count + 1, "error completion must pulse interrupt once");
        expect_read(STATUS, 32'h6, "error completion must set DONE+ERROR");
        write_register(CONTROL, 1, 4'hf, 0);
        repeat (2) @(posedge clk);
        expect_read(STATUS, 0, "next valid START must clear sticky status");
        $display("DONE/ERROR/interrupt tests: PASSED");

        write_register(COLOR, 32'hffff_ffff, 4'b0011, 0);
        expect_read(STATUS, 32'h4, "partial WSTRB must set ERROR");
        expect_read(COLOR, 32'ha5c3_f00d, "partial WSTRB must not change register");
        clear_status();

        write_register(BASE + 32'h7c, 32'h1234_5678, 4'hf, 0);
        expect_read(STATUS, 32'h4, "undefined write must set ERROR");
        clear_status();

        write_register(WIDTH, 32'd96, 4'hf, 1);
        expect_read(STATUS, 32'h4, "burst write must set ERROR");
        expect_read(WIDTH, 32'd96, "burst-tagged write still completes current beat");
        clear_status();

        read_register(VERSION, 1, value);
        expect_read(STATUS, 32'h4, "burst read must set ERROR");
        clear_status();
        $display("Control error handling tests: PASSED");

        simultaneous_aw_w(HEIGHT, 32'd7);
        expect_read(HEIGHT, 32'd7, "simultaneous AW/W write");
        w_before_aw(HEIGHT, 32'd9);
        expect_read(HEIGHT, 32'd9, "W-before-AW write");
        $display("AXI channel ordering tests: PASSED");

        if (failures == 0) begin
            $display("BitBlt control regression: PASSED");
            $finish;
        end else begin
            $display("BitBlt control regression: FAILED (%0d failures)", failures);
            $fatal(1);
        end
    end
endmodule
