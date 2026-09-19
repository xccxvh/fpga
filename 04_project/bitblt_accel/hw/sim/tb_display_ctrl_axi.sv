`timescale 1ns/1ps

module tb_display_ctrl_axi;
    reg clk = 0, resetn = 0;
    always #5 clk = ~clk;

    reg [7:0] awid = 0; reg [31:0] awaddr = 0;
    reg [7:0] awlen = 0; reg [2:0] awsize = 2;
    reg [1:0] awburst = 1; reg awvalid = 0;
    wire awready;
    reg [31:0] wdata = 0; reg [3:0] wstrb = 4'hf;
    reg wlast = 1, wvalid = 0; wire wready;
    wire [7:0] bid; wire [1:0] bresp; wire bvalid; reg bready = 1;
    reg [7:0] arid = 0; reg [31:0] araddr = 0;
    reg [7:0] arlen = 0; reg [2:0] arsize = 2;
    reg [1:0] arburst = 1; reg arvalid = 0; wire arready;
    wire [7:0] rid; wire [31:0] rdata; wire [1:0] rresp;
    wire rlast, rvalid; reg rready = 1;
    reg vblank = 0, underflow = 0;
    wire irq, enable, pending;
    wire [31:0] front, width, height, stride, format;

    display_ctrl_axi dut (
        .axi_interrupt(irq), .axi_aclk(clk), .axi_resetn(resetn),
        .axi_awid(awid), .axi_awaddr(awaddr), .axi_awlen(awlen),
        .axi_awsize(awsize), .axi_awburst(awburst), .axi_awlock(1'b0),
        .axi_awcache(4'h0), .axi_awprot(3'h0), .axi_awqos(4'h0),
        .axi_awregion(4'h0), .axi_awvalid(awvalid), .axi_awready(awready),
        .axi_wdata(wdata), .axi_wstrb(wstrb), .axi_wlast(wlast),
        .axi_wvalid(wvalid), .axi_wready(wready), .axi_bid(bid),
        .axi_bresp(bresp), .axi_bvalid(bvalid), .axi_bready(bready),
        .axi_arid(arid), .axi_araddr(araddr), .axi_arlen(arlen),
        .axi_arsize(arsize), .axi_arburst(arburst), .axi_arlock(1'b0),
        .axi_arcache(4'h0), .axi_arprot(3'h0), .axi_arqos(4'h0),
        .axi_arregion(4'h0), .axi_arvalid(arvalid), .axi_arready(arready),
        .axi_rid(rid), .axi_rdata(rdata), .axi_rresp(rresp),
        .axi_rlast(rlast), .axi_rvalid(rvalid), .axi_rready(rready),
        .vblank_pulse(vblank), .underflow_pulse(underflow),
        .display_enable(enable), .active_front_addr(front),
        .active_width(width), .active_height(height),
        .active_stride(stride), .active_format(format),
        .swap_pending(pending)
    );

    task automatic axi_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk); awaddr <= addr; awvalid <= 1;
            while (!awready) @(posedge clk);
            @(posedge clk); awvalid <= 0; wdata <= data; wvalid <= 1;
            while (!wready) @(posedge clk);
            @(posedge clk); wvalid <= 0;
            while (!bvalid) @(posedge clk);
            @(posedge clk);
        end
    endtask

    task automatic pulse_vblank;
        begin
            @(posedge clk); vblank <= 1;
            @(posedge clk); vblank <= 0;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        resetn <= 1;
        repeat (2) @(posedge clk);
        if (front !== 32'h0100_0000 || width !== 1920 || height !== 1080 ||
            stride !== 7680 || format !== 0)
            $fatal(1, "reset defaults incorrect");

        // Legacy V0.2 is fixed at 1080p: a larger aligned stride is invalid.
        axi_write(32'hE110_002C, 32'h7);
        axi_write(32'hE110_0018, 32'd7696);
        axi_write(32'hE110_000C, 32'h0180_0000);
        axi_write(32'hE110_0000, 32'h3);
        if (pending || !dut.error_reg)
            $fatal(1, "non-exact legacy stride was accepted");

        // Restore the fixed legacy geometry while disabled.
        axi_write(32'hE110_0000, 32'h0);
        axi_write(32'hE110_0018, 32'd7680);
        axi_write(32'hE110_0000, 32'h4);

        // Geometry/format writes while enabled must fail without changing state.
        axi_write(32'hE110_0000, 32'h1);
        axi_write(32'hE110_0010, 32'd1280);
        axi_write(32'hE110_0014, 32'd720);
        axi_write(32'hE110_0018, 32'd2560);
        axi_write(32'hE110_001C, 32'd1);
        if (width !== 1920 || height !== 1080 || stride !== 7680 ||
            format !== 0 || !dut.error_reg)
            $fatal(1, "enabled geometry write changed active configuration");
        axi_write(32'hE110_0000, 32'h5);

        // Enable and request FB_B. It must not switch before vertical blank.
        axi_write(32'hE110_000C, 32'h0180_0000);
        axi_write(32'hE110_0000, 32'h3);
        if (!enable || !pending || front !== 32'h0100_0000)
            $fatal(1, "swap request state incorrect");

        // PENDING forbids disabling display and retargeting NEXT_ADDR.
        axi_write(32'hE110_0000, 32'h0);
        if (!enable || !pending || !dut.error_reg)
            $fatal(1, "display disable was accepted while swap pending");
        axi_write(32'hE110_000C, 32'h0100_0000);
        if (dut.next_addr_reg !== 32'h0180_0000)
            $fatal(1, "NEXT_ADDR changed while swap pending");

        pulse_vblank;
        repeat (2) @(posedge clk);
        if (front !== 32'h0180_0000 || pending || !irq)
            $fatal(1, "vblank swap did not complete");

        // CLEAR removes prior sticky state while preserving ENABLE.
        axi_write(32'hE110_0000, 32'h5);
        if (irq || !enable)
            $fatal(1, "clear before stale-DONE test failed");

        // Complete one clean swap so SWAP_DONE is sticky.
        axi_write(32'hE110_000C, 32'h0100_0000);
        axi_write(32'hE110_0000, 32'h3);
        pulse_vblank;
        repeat (2) @(posedge clk);
        if (front !== 32'h0100_0000 || !dut.swap_done_reg || !irq)
            $fatal(1, "setup swap for stale-DONE test failed");

        // A newly accepted request must clear stale SWAP_DONE automatically.
        axi_write(32'hE110_000C, 32'h0180_0000);
        axi_write(32'hE110_0000, 32'h3);
        if (!pending || dut.swap_done_reg || irq)
            $fatal(1, "accepted swap request did not clear stale SWAP_DONE");
        pulse_vblank;
        repeat (2) @(posedge clk);
        if (front !== 32'h0180_0000 || pending || !irq)
            $fatal(1, "second vblank swap did not complete");

        // Underflow is sticky and counted; CLEAR resets sticky state/counter.
        @(posedge clk); underflow <= 1;
        @(posedge clk); underflow <= 0;
        repeat (1) @(posedge clk);
        if (!irq || dut.underflow_count_reg !== 1)
            $fatal(1, "underflow accounting failed");
        axi_write(32'hE110_0000, 32'h5);
        if (irq || dut.underflow_count_reg !== 0 || !enable)
            $fatal(1, "clear failed");

        // The current front buffer cannot be queued as next.
        axi_write(32'hE110_000C, 32'h0180_0000);
        axi_write(32'hE110_0000, 32'h3);
        if (!dut.error_reg || pending)
            $fatal(1, "invalid swap was accepted");

        $display("PASS: display control write guards, pending lock and vblank swap");
        $finish;
    end
endmodule
