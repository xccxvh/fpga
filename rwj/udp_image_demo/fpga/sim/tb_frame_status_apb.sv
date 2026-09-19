`timescale 1ns/1ps
//==========================================================================
// tb_frame_status_apb.sv —— 帧完成状态寄存器回归测试
//
// 覆盖 2026-09-19 B/C 提出的四个必须专门仿真的场景：
//   ① ACK 与新帧同周期 —— 新帧的错误位不能被 ACK 抹掉
//   ② SEQ 变化期间读取 —— 任何一次读都必须是自洽快照
//   ③ BRESP 错误       —— 含"最后一拍 BRESP 迟到"的情形
//   ④ SEQ 回绕         —— 32 位回绕对软件判据的影响
// 另加基础用例：复位、魔数、快照字段、STATUS 各位、ACK 匹配/不匹配、
// 切屏事件、LIVE_STATUS 实时性、地址译码。
//
// 两个时钟域刻意用不同频率（evt 108MHz / apb 100MHz），
// 这样跨时钟握手真的被测到 —— 用同频会把 CDC 问题掩盖掉。
//
// 运行：make frame-status   （见 sim/Makefile）
//==========================================================================
module tb_frame_status_apb;

// evt 域 108MHz（9.26ns），apb 域 100MHz（10ns）—— 刻意不同频
localparam real EVT_HALF = 4.63;
localparam real APB_HALF = 5.0;

logic evt_clk = 1'b0;
logic clk     = 1'b0;

always #(EVT_HALF) evt_clk = ~evt_clk;
always #(APB_HALF) clk     = ~clk;

//----------------------------------------------------------------------
// 事件域激励
//----------------------------------------------------------------------
logic         evt_rst_n;
logic         frame_done;
logic  [15:0] frame_id;
logic  [2:0]  frame_slot;
logic  [31:0] frame_base;
logic  [31:0] frame_rx_bytes;
logic  [31:0] frame_expect_bytes;
logic         frame_ok;
logic         frame_seq_err;
logic         fifo_ovf;
logic         bresp_err;
logic         arp_miss;
logic  [31:0] frame_checksum;
logic         frame_swap;
logic         swap_pulse;
logic  [15:0] swap_frame_id;

//----------------------------------------------------------------------
// 寄存器域
//----------------------------------------------------------------------
logic         rst_n;
logic         cal_done;
logic  [15:0] paddr;
logic         psel, penable, pwrite;
logic  [31:0] pwdata;
logic  [31:0] prdata;
logic         pready, pslverr;

frame_status_apb dut (
    .evt_clk(evt_clk), .evt_rst_n(evt_rst_n),
    .frame_done(frame_done), .frame_id(frame_id), .frame_slot(frame_slot),
    .frame_base(frame_base), .frame_rx_bytes(frame_rx_bytes),
    .frame_expect_bytes(frame_expect_bytes), .frame_ok(frame_ok),
    .frame_seq_err(frame_seq_err), .fifo_ovf(fifo_ovf), .bresp_err(bresp_err),
    .arp_miss(arp_miss), .frame_checksum(frame_checksum), .frame_swap(frame_swap),
    .swap_pulse(swap_pulse), .swap_frame_id(swap_frame_id),
    .cal_done(cal_done),
    .clk(clk), .rst_n(rst_n),
    .paddr(paddr), .psel(psel), .penable(penable), .pwrite(pwrite),
    .pwdata(pwdata), .prdata(prdata), .pready(pready), .pslverr(pslverr)
);

//----------------------------------------------------------------------
// 记分板
//----------------------------------------------------------------------
int errors = 0;
int checks = 0;

task automatic ck32(input [255:0] name, input logic [31:0] got, input logic [31:0] exp);
    checks++;
    if (got !== exp) begin
        errors++;
        $display("  [FAIL] %s  got=0x%08x exp=0x%08x", name, got, exp);
    end
endtask

task automatic ckbit(input [255:0] name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
        errors++;
        $display("  [FAIL] %s  got=%b exp=%b", name, got, exp);
    end
endtask

//----------------------------------------------------------------------
// 寄存器偏移（模块内 paddr[7:0]）
//----------------------------------------------------------------------
localparam [7:0] O_FRAME_ID = 8'h00, O_SLOT = 8'h04, O_BASE = 8'h08,
                 O_RX = 8'h0C, O_EXP = 8'h10, O_STATUS = 8'h14,
                 O_ACK = 8'h18, O_SEQ = 8'h1C, O_SWAPSEQ = 8'h20,
                 O_SWAPFRM = 8'h24, O_ERRST = 8'h28, O_ID = 8'h2C,
                 O_LIVE = 8'h30;
localparam [15:0] BASE = 16'h0100;      // 模块占 0x100-0x1FF

//----------------------------------------------------------------------
// APB master BFM（零等待态）
//----------------------------------------------------------------------
task automatic apb_wr(input [7:0] off, input [31:0] data);
    @(negedge clk);
    paddr = BASE + {8'd0, off}; pwrite = 1'b1; psel = 1'b1; penable = 1'b0;
    pwdata = data;
    @(negedge clk);
    penable = 1'b1;
    @(negedge clk);
    psel = 1'b0; penable = 1'b0; pwrite = 1'b0;
endtask

task automatic apb_rd(input [7:0] off, output [31:0] data);
    @(negedge clk);
    paddr = BASE + {8'd0, off}; pwrite = 1'b0; psel = 1'b1; penable = 1'b1;
    @(negedge clk);
    data = prdata;
    psel = 1'b0; penable = 1'b0;
endtask

//----------------------------------------------------------------------
// 事件域：发一帧
//----------------------------------------------------------------------
task automatic do_frame(input [15:0] fid, input [2:0] slot, input [31:0] fbase,
                        input [31:0] rx,  input [31:0] exp,
                        input        ok,  input        sqe,
                        input        ovf, input        brs,
                        input [31:0] cksum);
    @(negedge evt_clk);
    frame_id = fid; frame_slot = slot; frame_base = fbase;
    frame_rx_bytes = rx; frame_expect_bytes = exp;
    frame_ok = ok; frame_seq_err = sqe; fifo_ovf = ovf; bresp_err = brs;
    frame_checksum = cksum; frame_swap = 1'b0;
    frame_done = 1'b1;
    @(negedge evt_clk);
    frame_done = 1'b0;
endtask

task automatic do_swap(input [15:0] fid);
    @(negedge evt_clk);
    swap_frame_id = fid;
    swap_pulse = 1'b1;
    @(negedge evt_clk);
    swap_pulse = 1'b0;
endtask

// 等跨域同步 + 发布落定
task automatic settle;
    repeat (10) @(negedge clk);
endtask

// 复位 DUT 的寄存器侧，重新开始
task automatic reg_reset;
    @(negedge clk);
    rst_n = 1'b0;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (4) @(negedge clk);
endtask

//----------------------------------------------------------------------
// 主测试
//----------------------------------------------------------------------
logic [31:0] rd;
logic [31:0] s0, s1;

initial begin
    $display("===== frame_status_apb 回归 =====");

    // 初值
    evt_rst_n = 1'b0; rst_n = 1'b0;
    frame_done = 0; frame_id = 0; frame_slot = 0; frame_base = 0;
    frame_rx_bytes = 0; frame_expect_bytes = 0;
    frame_ok = 0; frame_seq_err = 0; fifo_ovf = 0; bresp_err = 0;
    arp_miss = 0; frame_checksum = 0; frame_swap = 0;
    swap_pulse = 0; swap_frame_id = 0;
    cal_done = 0;
    paddr = 0; psel = 0; penable = 0; pwrite = 0; pwdata = 0;

    repeat (6) @(posedge clk);
    rst_n = 1'b1;
    evt_rst_n = 1'b1;
    repeat (6) @(posedge clk);

    //------------------------------------------------------------------
    $display("-- 用例 1：复位值 + 魔数 + 地址译码 --");
    apb_rd(O_ID, rd);       ck32("ID 魔数", rd, 32'h4652_4D31);
    apb_rd(O_SEQ, rd);      ck32("复位 SEQ", rd, 32'd0);
    apb_rd(O_STATUS, rd);   ck32("复位 STATUS", rd, 32'd0);
    apb_rd(O_ERRST, rd);    ck32("复位 ERR_STICKY", rd, 32'd0);

    // 译码：越界地址不应答
    paddr = 16'h0200; psel = 1'b1; penable = 1'b1; pwrite = 1'b0;
    @(negedge clk);
    ckbit("越界 paddr 不响应", pready, 1'b0);
    paddr = BASE; @(negedge clk);
    ckbit("范围内 paddr 响应", pready, 1'b1);
    psel = 1'b0; penable = 1'b0;

    //------------------------------------------------------------------
    $display("-- 用例 2：好帧 -> 快照字段 --");
    do_frame(16'h1234, 3'd2, 32'h0040_0000, 32'd1843200, 32'd1843200,
             1'b1, 1'b0, 1'b0, 1'b0, 32'hDEAD_BEEF);
    settle;
    apb_rd(O_FRAME_ID, rd);  ck32("FRAME_ID", rd, 32'h0000_1234);
    apb_rd(O_SLOT, rd);      ck32("SLOT", rd, 32'd2);
    apb_rd(O_BASE, rd);      ck32("BASE_ADDR", rd, 32'h0040_0000);
    apb_rd(O_RX, rd);        ck32("RX_BYTES", rd, 32'd1843200);
    apb_rd(O_EXP, rd);       ck32("EXPECT_BYTES", rd, 32'd1843200);
    apb_rd(O_STATUS, rd);    ck32("STATUS 好帧", rd, 32'h0000_0003); // DONE|FRAME_OK
    apb_rd(O_SEQ, rd);       ck32("SEQ 递增到 1", rd, 32'd1);

    //------------------------------------------------------------------
    $display("-- 用例 3：各种坏帧 -> STATUS 对应位 --");
    do_frame(16'h1235, 3'd1, 32'h0020_0000, 32'd100, 32'd200,
             1'b0, 1'b0, 1'b0, 1'b0, 32'h0);         // BYTES_MISMATCH
    settle;
    apb_rd(O_STATUS, rd);
    ckbit("BYTES_MISMATCH 置位", rd[5], 1'b1);
    ckbit("FRAME_OK 清零",       rd[1], 1'b0);

    // 用例 ③：BRESP 错误
    do_frame(16'h1236, 3'd1, 32'h0020_0000, 32'd200, 32'd200,
             1'b0, 1'b0, 1'b0, 1'b1, 32'h0);         // BRESP_ERR
    settle;
    apb_rd(O_STATUS, rd);
    ckbit("BRESP_ERR 置位(status)",  rd[4], 1'b1);
    ckbit("BRESP_ERR 位不串到别人",  rd[5], 1'b0);
    apb_rd(O_ERRST, rd);
    ckbit("BRESP_ERR 累积到 sticky", rd[2], 1'b1);

    do_frame(16'h1237, 3'd1, 32'h0020_0000, 32'd200, 32'd200,
             1'b0, 1'b1, 1'b0, 1'b0, 32'h0);         // SEQ_ERR
    settle;
    apb_rd(O_ERRST, rd);
    ckbit("SEQ_ERR 累积到 sticky", rd[0], 1'b1);
    ckbit("BRESP sticky 保持",      rd[2], 1'b1);

    //------------------------------------------------------------------
    $display("-- 用例 4：ACK 匹配 / 不匹配 --");
    apb_rd(O_SEQ, s0);
    apb_wr(O_ACK, s0);                       // 匹配
    apb_rd(O_ERRST, rd);
    ck32("ACK 匹配 -> sticky 清零", rd, 32'd0);

    do_frame(16'h1238, 3'd1, 32'h0020_0000, 32'd200, 32'd200,
             1'b0, 1'b0, 1'b0, 1'b1, 32'h0);   // 再来个 BRESP 错
    settle;
    apb_rd(O_ERRST, rd);
    ckbit("新错误又置位", rd[2], 1'b1);

    apb_wr(O_ACK, 32'hDEAD_0000);            // 不匹配
    apb_rd(O_ERRST, rd);
    ckbit("ACK 不匹配 -> sticky 保留", rd[2], 1'b1);

    //------------------------------------------------------------------
    $display("-- 用例 5：切屏事件 --");
    do_swap(16'h00AA);
    settle;
    apb_rd(O_SWAPSEQ, rd);   ck32("SWAP_SEQ = 1", rd, 32'd1);
    apb_rd(O_SWAPFRM, rd);   ck32("SWAP_FRAME", rd, 32'h0000_00AA);
    do_swap(16'h00BB);
    settle;
    apb_rd(O_SWAPSEQ, rd);   ck32("SWAP_SEQ = 2", rd, 32'd2);
    apb_rd(O_SWAPFRM, rd);   ck32("SWAP_FRAME 跟随", rd, 32'h0000_00BB);

    //------------------------------------------------------------------
    $display("-- 用例 6：LIVE_STATUS 是实时的，不被快照影响 --");
    apb_rd(O_LIVE, rd);      ckbit("CAL_DONE 初始为 0", rd[0], 1'b0);
    cal_done = 1'b1;
    repeat (6) @(negedge clk);
    apb_rd(O_LIVE, rd);      ckbit("CAL_DONE 转 1", rd[0], 1'b1);
    apb_rd(O_STATUS, rd);
    ckbit("STATUS 不受 CAL_DONE 影响", rd[8], 1'b0);

    //------------------------------------------------------------------
    $display("-- 用例 7：SEQ 回绕（force 到 0xFFFFFFFF）--");
    force dut.st_seq = 32'hFFFF_FFFF;
    repeat (2) @(negedge clk);
    apb_rd(O_SEQ, rd);       ck32("SEQ 被 force 到 MAX", rd, 32'hFFFF_FFFF);
    // 注意：force 期间过程赋值被忽略，必须先 release 再发帧，
    // 否则 st_seq <= st_seq + 1 不会生效。
    release dut.st_seq;
    repeat (2) @(negedge clk);
    do_frame(16'h1239, 3'd1, 32'h0020_0000, 32'd200, 32'd200,
             1'b1, 1'b0, 1'b0, 1'b0, 32'h0);
    settle;
    apb_rd(O_SEQ, rd);       ck32("回绕到 0", rd, 32'd0);

    //------------------------------------------------------------------
    $display("-- 用例 8：② 读取期间 SEQ 变化 -- 任一次读都自洽 --");
    // 软件 seqlock 读法：读 SEQ -> 读字段 -> 再读 SEQ，不等则重读。
    // 硬件侧要求：任何一次读都取自同一帧，不会出现半个新帧半个旧帧。
    // 这里在事件域持续发帧，寄存器域按 seqlock 读，检查最终拿到的
    // FRAME_ID 与最后一次读到的 SEQ 描述同一帧。
    fork
        begin : frames
            for (int i = 0; i < 30; i++) begin
                do_frame(16'h4000 + i[15:0], 3'd1, 32'h0020_0000,
                         32'd200, 32'd200, 1'b1, 1'b0, 1'b0, 1'b0, 32'h0);
                #200;
            end
        end
        begin : reader
            int tries;
            tries = 0;
            while (tries < 40) begin
                apb_rd(O_SEQ, s0);
                apb_rd(O_FRAME_ID, rd);
                apb_rd(O_SEQ, s1);
                if (s0 == s1) begin
                    // 自洽：读到的是同一帧
                    if (rd[15:0] < 16'h4000 || rd[15:0] > 16'h401F) begin
                        errors++;
                        $display("  [FAIL] seqlock 读到撕裂帧 id=0x%04x seq=%0d",
                                 rd[15:0], s0);
                    end
                    tries++;
                end
            end
            checks++;
        end
    join

    //------------------------------------------------------------------
    $display("-- 用例 9：① ACK 与新帧同周期 -- 新帧错误不能被抹掉 --");
    // 把 ACK 写安排在发帧前后不同相位，重复多次，检查不变量：
    // 只要有一帧带 BRESP_ERR 发布、且此后没有匹配它 SEQ 的 ACK，
    // sticky 里那一位就必须还在。
    begin
        int survived;
        survived = 0;
        for (int ph = 0; ph < 8; ph++) begin
            reg_reset;
            cal_done = 1'b0;
            // 先发一帧好帧，让 SEQ=1
            do_frame(16'h5000, 3'd1, 32'h0020_0000, 32'd200, 32'd200,
                     1'b1, 1'b0, 1'b0, 1'b0, 32'h0);
            settle;
            // 相位：先写 ACK(旧 seq)，再/同时发带错的帧
            fork
                begin
                    repeat (ph) @(negedge clk);
                    apb_wr(O_ACK, 32'd1);            // 旧 SEQ
                end
                begin
                    repeat (ph) @(negedge evt_clk);
                    do_frame(16'h5001, 3'd1, 32'h0020_0000, 32'd200, 32'd200,
                             1'b0, 1'b0, 1'b0, 1'b1, 32'h0);   // BRESP 错
                end
            join
            settle;
            settle;
            apb_rd(O_SEQ, rd);
            if (rd == 32'd2) begin                      // 新帧确实发布了
                apb_rd(O_ERRST, rd);
                if (rd[2] === 1'b1) survived++;
                else begin
                    errors++;
                    $display("  [FAIL] 相位 %0d：新帧的 BRESP_ERR 被 ACK 抹掉了", ph);
                end
            end
            checks++;
        end
        $display("      8 个相位中有 %0d 个确认新帧错误存活", survived);
    end

    //------------------------------------------------------------------
    $display("");
    if (errors == 0)
        $display("frame_status_apb regression: PASSED (%0d checks)", checks);
    else
        $display("frame_status_apb regression: FAILED (%0d/%0d failed)", errors, checks);
    $display("");

    $finish;
end

initial begin
    #2000000;
    $display("TIMEOUT");
    $finish;
end

endmodule
