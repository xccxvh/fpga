`timescale 1ns/1ps

module tb_bitblt_engine;
    localparam [31:0] BASE = 32'h1000_0000;
    localparam integer MEM_BYTES = 16'h8000;
    localparam integer TIMEOUT = 20000;
    localparam OP_FILL = 0;
    localparam OP_COPY = 1;
    localparam OP_COLOR_KEY = 2;

    reg clk = 0;
    reg resetn = 0;
    reg start = 0;
    reg [31:0] src_addr, dst_addr, width, height;
    reg [31:0] src_stride, dst_stride, color, operation;
    wire busy, done, error;

    wire [7:0] awid, awlen, bid;
    wire [31:0] awaddr;
    wire [2:0] awsize;
    wire [1:0] awburst, bresp;
    wire awlock, awvalid, awready;
    wire [3:0] awcache;
    wire [2:0] awprot;
    wire [127:0] wdata;
    wire [15:0] wstrb;
    wire wlast, wvalid, wready, bvalid, bready;

    wire [7:0] arid, arlen, rid;
    wire [31:0] araddr;
    wire [2:0] arsize;
    wire [1:0] arburst, rresp;
    wire arlock, arvalid, arready;
    wire [3:0] arcache;
    wire [2:0] arprot;
    wire [127:0] rdata;
    wire rlast, rvalid, rready;

    reg [7:0] memory [0:MEM_BYTES-1];
    reg [7:0] expected [0:MEM_BYTES-1];
    integer cycle_count = 0;
    integer failures = 0;
    integer aw_count = 0;
    integer ar_count = 0;
    integer max_aw_beats = 0;
    integer max_ar_beats = 0;

    reg write_active = 0;
    reg [31:0] write_address = 0;
    reg [8:0] write_beats_left = 0;
    reg bvalid_reg = 0;
    reg [1:0] bresp_reg = 0;
    reg inject_bresp = 0;

    reg read_active = 0;
    reg [31:0] read_address = 0;
    reg [8:0] read_beats_left = 0;
    reg inject_rresp = 0;
    reg force_early_rlast = 0;

    always #5 clk = ~clk;
    always @(posedge clk) cycle_count <= cycle_count + 1;

    assign awready = !write_active && !bvalid_reg && ((cycle_count % 3) != 0);
    assign wready = write_active && ((cycle_count % 4) != 1);
    assign bvalid = bvalid_reg;
    assign bresp = bresp_reg;
    assign bid = 8'h00;

    assign arready = !read_active && ((cycle_count % 4) != 2);
    assign rvalid = read_active && ((cycle_count % 5) != 3);
    assign rdata = read_word(read_address);
    assign rresp = inject_rresp ? 2'b10 : 2'b00;
    assign rid = 8'h00;
    assign rlast = read_active && (force_early_rlast || (read_beats_left == 1));

    bitblt_engine dut (
        .clk(clk), .resetn(resetn), .start(start),
        .src_addr(src_addr), .dst_addr(dst_addr), .width(width), .height(height),
        .src_stride(src_stride), .dst_stride(dst_stride),
        .color(color), .operation(operation),
        .busy(busy), .done(done), .error(error),
        .m_awid(awid), .m_awaddr(awaddr), .m_awlen(awlen), .m_awsize(awsize),
        .m_awburst(awburst), .m_awlock(awlock), .m_awcache(awcache),
        .m_awprot(awprot), .m_awvalid(awvalid), .m_awready(awready),
        .m_wdata(wdata), .m_wstrb(wstrb), .m_wlast(wlast),
        .m_wvalid(wvalid), .m_wready(wready), .m_bid(bid), .m_bresp(bresp),
        .m_bvalid(bvalid), .m_bready(bready),
        .m_arid(arid), .m_araddr(araddr), .m_arlen(arlen), .m_arsize(arsize),
        .m_arburst(arburst), .m_arlock(arlock), .m_arcache(arcache),
        .m_arprot(arprot), .m_arvalid(arvalid), .m_arready(arready),
        .m_rid(rid), .m_rdata(rdata), .m_rresp(rresp), .m_rlast(rlast),
        .m_rvalid(rvalid), .m_rready(rready)
    );

    function [127:0] read_word;
        input [31:0] address;
        integer index, byte_index;
        begin
            index = address - BASE;
            read_word = 0;
            for (byte_index = 0; byte_index < 16; byte_index = byte_index + 1)
                if ((index + byte_index >= 0) && (index + byte_index < MEM_BYTES))
                    read_word[byte_index*8 +: 8] = memory[index + byte_index];
        end
    endfunction

    task fail;
        input [8*120-1:0] message;
        begin
            failures = failures + 1;
            $display("FAIL: %0s", message);
        end
    endtask

    task initialise_memory;
        integer index;
        begin
            for (index = 0; index < MEM_BYTES; index = index + 1) begin
                memory[index] = 8'hcd;
                expected[index] = 8'hcd;
            end
        end
    endtask

    task put_pixel;
        input [31:0] address;
        input [15:0] value;
        integer index, byte_index;
        begin
            index = address - BASE;
            for (byte_index = 0; byte_index < 2; byte_index = byte_index + 1) begin
                memory[index + byte_index] = value[byte_index*8 +: 8];
                expected[index + byte_index] = value[byte_index*8 +: 8];
            end
        end
    endtask

    task expect_pixel;
        input [31:0] address;
        input [15:0] value;
        integer index, byte_index;
        begin
            index = address - BASE;
            for (byte_index = 0; byte_index < 2; byte_index = byte_index + 1)
                expected[index + byte_index] = value[byte_index*8 +: 8];
        end
    endtask

    task compare_memory;
        input [8*80-1:0] test_name;
        integer index, mismatches;
        begin
            mismatches = 0;
            for (index = 0; index < MEM_BYTES; index = index + 1) begin
                if (memory[index] !== expected[index]) begin
                    if (mismatches < 4)
                        $display("Mismatch %0s at +0x%0h: got %02x expected %02x",
                                 test_name, index, memory[index], expected[index]);
                    mismatches = mismatches + 1;
                end
            end
            if (mismatches != 0) begin
                failures = failures + 1;
                $display("FAIL: %0s had %0d memory mismatches", test_name, mismatches);
            end
        end
    endtask

    task pulse_start;
        begin
            @(negedge clk);
            start = 1;
            @(negedge clk);
            start = 0;
        end
    endtask

    task wait_for_done;
        input expected_error;
        input [8*80-1:0] test_name;
        integer count;
        begin : wait_loop
            count = 0;
            while (!done && count < TIMEOUT) begin
                @(posedge clk);
                #1;
                count = count + 1;
            end
            if (!done) begin
                fail({test_name, " timed out"});
                disable wait_loop;
            end
            if (error !== expected_error) begin
                failures = failures + 1;
                $display("FAIL: %0s error=%b expected=%b", test_name, error, expected_error);
            end
            @(posedge clk);
            #1;
        end
    endtask

    task run_fill;
        input integer beats;
        input [31:0] address;
        integer pixel;
        reg [15:0] fill_color;
        begin
            initialise_memory();
            fill_color = 16'hc000 | beats;
            src_addr = BASE;
            dst_addr = address;
            width = beats * 8;
            height = 1;
            src_stride = beats * 16;
            dst_stride = beats * 16;
            color = fill_color;
            operation = OP_FILL;
            for (pixel = 0; pixel < beats * 8; pixel = pixel + 1)
                expect_pixel(address + pixel * 2, fill_color);
            pulse_start();
            wait_for_done(0, "fill burst length");
            compare_memory("fill burst length");
        end
    endtask

    task run_copy_stride;
        integer x, y;
        reg [15:0] value;
        begin
            initialise_memory();
            src_addr = BASE + 32'h1000;
            dst_addr = BASE + 32'h3000;
            /* 160 像素 = 20 拍，超过 16 拍上限，保证读突发也走到最大长度。
               stride 保留原来的 "比最小 stride 多留 padding" 意图：
               最小 160*2 = 320，实取 384/416。 */
            width = 160;
            height = 3;
            src_stride = 384;
            dst_stride = 416;
            color = 0;
            operation = OP_COPY;
            for (y = 0; y < height; y = y + 1)
                for (x = 0; x < width; x = x + 1) begin
                    value = 16'h5000 | (y << 8) | x;
                    put_pixel(src_addr + y * src_stride + x * 2, value);
                    expect_pixel(dst_addr + y * dst_stride + x * 2, value);
                end
            pulse_start();
            wait_for_done(0, "copy stride");
            compare_memory("copy stride");
        end
    endtask

    task run_copy_4k_boundary;
        integer pixel;
        reg [15:0] value;
        begin
            initialise_memory();
            src_addr = BASE + 32'h0ff0;
            dst_addr = BASE + 32'h4ff0;
            width = 40;
            height = 1;
            src_stride = 80;
            dst_stride = 80;
            color = 0;
            operation = OP_COPY;
            for (pixel = 0; pixel < 40; pixel = pixel + 1) begin
                value = 16'ha500 | pixel;
                put_pixel(src_addr + pixel * 2, value);
                expect_pixel(dst_addr + pixel * 2, value);
            end
            pulse_start();
            wait_for_done(0, "copy 4KiB boundary");
            compare_memory("copy 4KiB boundary");
        end
    endtask

    task run_color_key;
        integer pixel;
        reg [15:0] value;
        begin
            initialise_memory();
            src_addr = BASE + 32'h1000;
            dst_addr = BASE + 32'h3000;
            width = 40;
            height = 1;
            src_stride = 80;
            dst_stride = 80;
            color = 32'h0000_2233;
            operation = OP_COLOR_KEY;
            for (pixel = 0; pixel < 40; pixel = pixel + 1) begin
                if ((pixel % 3) == 0)
                    value = 16'h2233;
                else
                    value = 16'h5a00 | pixel;
                put_pixel(src_addr + pixel * 2, value);
                if ((pixel % 3) != 0)
                    expect_pixel(dst_addr + pixel * 2, value);
            end
            pulse_start();
            wait_for_done(0, "color key");
            compare_memory("color key");
        end
    endtask

    task run_invalid;
        input [31:0] test_operation;
        input [31:0] test_src;
        input [31:0] test_dst;
        input [31:0] test_width;
        input [31:0] test_height;
        input [31:0] test_src_stride;
        input [31:0] test_dst_stride;
        input [8*80-1:0] test_name;
        begin
            initialise_memory();
            operation = test_operation;
            src_addr = test_src;
            dst_addr = test_dst;
            width = test_width;
            height = test_height;
            src_stride = test_src_stride;
            dst_stride = test_dst_stride;
            color = 32'h12345678;
            pulse_start();
            wait_for_done(1, test_name);
            compare_memory(test_name);
        end
    endtask

    always @(posedge clk) begin : memory_model
        integer index, byte_index, beats;
        if (!resetn) begin
            write_active <= 0;
            bvalid_reg <= 0;
            bresp_reg <= 0;
            read_active <= 0;
        end else begin
            if (awvalid && awready) begin
                beats = awlen + 1;
                aw_count <= aw_count + 1;
                if (beats > max_aw_beats) max_aw_beats <= beats;
                if (beats > 16) fail("AW burst exceeds 16 beats");
                if ({1'b0, awaddr[11:0]} + beats * 16 > 4096)
                    fail("AW burst crosses 4KiB boundary");
                if ((awsize != 4) || (awburst != 2'b01))
                    fail("AW attributes incorrect");
                write_active <= 1;
                write_address <= awaddr;
                write_beats_left <= beats;
            end
            if (wvalid && wready) begin
                index = write_address - BASE;
                if ((index < 0) || (index + 15 >= MEM_BYTES)) begin
                    fail("write outside memory model");
                end else begin
                    for (byte_index = 0; byte_index < 16; byte_index = byte_index + 1)
                        if (wstrb[byte_index])
                            memory[index + byte_index] <= wdata[byte_index*8 +: 8];
                end
                if (wlast !== (write_beats_left == 1))
                    fail("WLAST at incorrect beat");
                if (write_beats_left == 1) begin
                    write_active <= 0;
                    bvalid_reg <= 1;
                    bresp_reg <= inject_bresp ? 2'b10 : 2'b00;
                    inject_bresp <= 0;
                end else begin
                    write_address <= write_address + 16;
                    write_beats_left <= write_beats_left - 1;
                end
            end
            if (bvalid_reg && bready) begin
                bvalid_reg <= 0;
                bresp_reg <= 0;
            end

            if (arvalid && arready) begin
                beats = arlen + 1;
                ar_count <= ar_count + 1;
                if (beats > max_ar_beats) max_ar_beats <= beats;
                if (beats > 16) fail("AR burst exceeds 16 beats");
                if ({1'b0, araddr[11:0]} + beats * 16 > 4096)
                    fail("AR burst crosses 4KiB boundary");
                if ((arsize != 4) || (arburst != 2'b01))
                    fail("AR attributes incorrect");
                read_active <= 1;
                read_address <= araddr;
                read_beats_left <= beats;
            end
            if (rvalid && rready) begin
                if (inject_rresp) inject_rresp <= 0;
                if (rlast) begin
                    read_active <= 0;
                    force_early_rlast <= 0;
                end else begin
                    read_address <= read_address + 16;
                    read_beats_left <= read_beats_left - 1;
                end
            end
        end
    end

    initial begin
        src_addr = 0; dst_addr = 0; width = 0; height = 0;
        src_stride = 0; dst_stride = 0; color = 0; operation = 0;
        initialise_memory();
        repeat (4) @(posedge clk);
        resetn = 1;
        repeat (2) @(posedge clk);

        run_fill(1,  BASE + 32'h0200);
        run_fill(2,  BASE + 32'h0400);
        run_fill(4,  BASE + 32'h0600);
        run_fill(15, BASE + 32'h0800);
        run_fill(16, BASE + 32'h0a00);
        run_fill(17, BASE + 32'h0c00);
        $display("Fill burst tests: PASSED");

        run_copy_stride();
        run_copy_4k_boundary();
        $display("Copy/stride/boundary tests: PASSED");

        run_color_key();
        $display("Color Key tests: PASSED");

        run_invalid(3, BASE, BASE + 32'h2000, 8, 1, 16, 16, "illegal operation");
        run_invalid(OP_FILL, BASE, BASE + 32'h2000, 0, 1, 16, 16, "zero width");
        run_invalid(OP_FILL, BASE, BASE + 32'h2000, 8, 0, 16, 16, "zero height");
        run_invalid(OP_FILL, BASE, BASE + 32'h2004, 8, 1, 16, 16, "unaligned destination");
        run_invalid(OP_FILL, BASE, BASE + 32'h2000, 10, 1, 32, 32, "width not multiple of eight");
        run_invalid(OP_FILL, BASE, BASE + 32'h2000, 16, 1, 32, 16, "small destination stride");
        run_invalid(OP_COPY, BASE + 4, BASE + 32'h2000, 8, 1, 16, 16, "unaligned source");
        $display("Invalid parameter tests: PASSED");

        initialise_memory();
        src_addr = BASE; dst_addr = BASE + 32'h2000;
        width = 8; height = 1; src_stride = 16; dst_stride = 16;
        color = 32'hdeadbeef; operation = OP_FILL; inject_bresp = 1;
        pulse_start(); wait_for_done(1, "BRESP error");

        initialise_memory();
        put_pixel(BASE + 32'h1000, 16'h3344);
        src_addr = BASE + 32'h1000; dst_addr = BASE + 32'h2000;
        width = 8; height = 1; src_stride = 16; dst_stride = 16;
        color = 0; operation = OP_COPY; inject_rresp = 1;
        pulse_start(); wait_for_done(1, "RRESP error");

        initialise_memory();
        put_pixel(BASE + 32'h1000, 16'h7788);
        src_addr = BASE + 32'h1000; dst_addr = BASE + 32'h2000;
        /* 16 像素 = 2 拍。RGB565 下一拍 8 像素，width=8 只有 1 拍，
           那时强制 RLAST 恰好是正确的收尾，测不出"提前"。 */
        width = 16; height = 1; src_stride = 32; dst_stride = 32;
        operation = OP_COPY; force_early_rlast = 1;
        pulse_start(); wait_for_done(1, "early RLAST");
        $display("AXI error tests: PASSED");

        if ((max_aw_beats != 16) || (max_ar_beats != 16))
            fail("regression did not exercise 16-beat read and write bursts");

        if (failures == 0) begin
            $display("BitBlt engine regression: PASSED (%0d AW, %0d AR)", aw_count, ar_count);
            $finish;
        end else begin
            $display("BitBlt engine regression: FAILED (%0d failures)", failures);
            $fatal(1);
        end
    end
endmodule
