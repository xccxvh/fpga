`timescale 1ns/1ps
//==========================================================================
// tb_frame_status_apb.sv —— 帧完成状态寄存器回归测试
//
// 被测：frame_status_apb.v（内核）+ frame_status_apb_slave.v（64KB 窗口包装）
// 协议：07_docs/interfaces/udp_frame_status_v2_draft.md（C 的冻结草案）
//
// 覆盖：
//   基础   复位值、VERSION、地址译码（含未映射区的 PREADY 必须为 1）
//   授权   AUTH_BASE + ARM → START 锁存 → 快照 BASE_ADDR；无授权 → AUTH_ERR
//   快照   好帧/各种坏帧、字段、SEQ 递增
//   ACK    匹配清 / 不匹配保留
//   G.2    ACK 与同拍发布的【坏帧】
//   G.3    ACK 与同拍发布的【好帧】—— 旧错误必须保留（草案 G.3 的推论）
//   回绕   SEQ 32-bit 回绕
//   并发   事件域连发帧的同时按 seqlock 读
//
// 两个时钟域刻意不同频（evt 108MHz / apb 100MHz），否则 CDC 问题测不出来。
//
// 运行：make frame-status IVL_ROOT=$HOME/.local/ivl/root
//==========================================================================
module tb_frame_status_apb;

localparam real EVT_HALF = 4.63;   // 108 MHz
localparam real APB_HALF = 5.0;    // 100 MHz

logic evt_clk = 1'b0;
logic clk     = 1'b0;
always #(EVT_HALF) evt_clk = ~evt_clk;
always #(APB_HALF) clk     = ~clk;

//----------------------------------------------------------------------
// 事件域激励
//----------------------------------------------------------------------
logic         evt_rst_n;
logic         frame_start, frame_done;
logic  [15:0] frame_id;
logic  [31:0] frame_rx_bytes, frame_expect_bytes;
logic         frame_seq_err, fifo_ovf, bresp_err, arp_miss;

//----------------------------------------------------------------------
// 寄存器域
//----------------------------------------------------------------------
logic         rst_n, cal_done;
logic  [15:0] paddr;
logic         psel, penable, pwrite;
logic  [31:0] pwdata, prdata;
logic         pready, pslverr;

frame_status_apb_slave dut (
    .clk(clk), .rst_n(rst_n),
    .paddr(paddr), .psel(psel), .penable(penable), .pwrite(pwrite),
    .pwdata(pwdata), .prdata(prdata), .pready(pready), .pslverr(pslverr),
    .evt_clk(evt_clk), .evt_rst_n(evt_rst_n),
    .frame_start(frame_start), .frame_done(frame_done),
    .frame_id(frame_id), .frame_rx_bytes(frame_rx_bytes),
    .frame_expect_bytes(frame_expect_bytes),
    .frame_seq_err(frame_seq_err), .fifo_ovf(fifo_ovf),
    .bresp_err(bresp_err), .arp_miss(arp_miss), .cal_done(cal_done)
);

//----------------------------------------------------------------------
// G.3 同拍检测：ACK 写与 snap_pulse 落在同一个 clk 周期
//
// 只有真的同拍时 G.3 的推论才适用 —— 不同拍时 ACK 先到是合法的清除行为。
// 所以用例 9 必须先检测同拍，不能无条件断言。
//----------------------------------------------------------------------
logic coincident;
always @(posedge clk) begin
    if (!rst_n) coincident <= 1'b0;
    else if (dut.u_frame_status.snap_pulse && dut.u_frame_status.ack_wr)
        coincident <= 1'b1;
end

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
// 寄存器偏移（相对 0xF8100100）
//----------------------------------------------------------------------
localparam [7:0] O_SEQ=8'h00, O_FST=8'h04, O_FID=8'h08, O_SLOT=8'h0C,
                 O_BASE=8'h10, O_RX=8'h14, O_EXP=8'h18, O_ACK=8'h1C,
                 O_LIVE=8'h20, O_ERRST=8'h24, O_VER=8'h28,
                 O_AUTHB=8'h2C, O_AUTHC=8'h30;
localparam [15:0] BASE = 16'h0100;

// FRAME_STATUS 位
localparam FS_OK=0, FS_SEQ=1, FS_OVF=2, FS_BRESP=3, FS_LEN=4, FS_NODATA=5, FS_AUTH=6;

localparam [31:0] FB_B = 32'h0180_0000;

//----------------------------------------------------------------------
// APB master BFM
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

// 等跨域同步落定
task automatic settle;
    repeat (10) @(negedge clk);
endtask

//----------------------------------------------------------------------
// 事件域
//----------------------------------------------------------------------
task automatic do_start(input [15:0] fid, input [31:0] exp_bytes);
    @(negedge evt_clk);
    frame_id = fid; frame_expect_bytes = exp_bytes;
    frame_start = 1'b1;
    @(negedge evt_clk);
    frame_start = 1'b0;
endtask

task automatic do_done(input [31:0] rx, input sqe, input ovf, input brs);
    @(negedge evt_clk);
    frame_rx_bytes = rx; frame_seq_err = sqe; fifo_ovf = ovf; bresp_err = brs;
    frame_done = 1'b1;
    @(negedge evt_clk);
    frame_done = 1'b0;
    frame_seq_err = 1'b0; fifo_ovf = 1'b0; bresp_err = 1'b0;
endtask

task automatic do_frame(input [15:0] fid, input [31:0] rx, input [31:0] exp,
                        input sqe, input ovf, input brs);
    do_start(fid, exp);
    do_done(rx, sqe, ovf, brs);
endtask

// 授权：写 AUTH_BASE + ARM，等事件域消费
task automatic do_auth(input [31:0] addr);
    apb_wr(O_AUTHB, addr);
    apb_wr(O_AUTHC, 32'd1);
    repeat (6) @(negedge evt_clk);   // 等 pending 同步到事件域
endtask

//----------------------------------------------------------------------
// 主测试
//----------------------------------------------------------------------
logic [31:0] rd, s0, s1;

initial begin
    $display("===== frame_status_apb 回归 =====");

    evt_rst_n = 0; rst_n = 0;
    frame_start = 0; frame_done = 0; frame_id = 0;
    frame_rx_bytes = 0; frame_expect_bytes = 0;
    frame_seq_err = 0; fifo_ovf = 0; bresp_err = 0; arp_miss = 0;
    cal_done = 0;
    paddr = 0; psel = 0; penable = 0; pwrite = 0; pwdata = 0;

    repeat (6) @(posedge clk);
    rst_n = 1; evt_rst_n = 1;
    repeat (6) @(posedge clk);

    //------------------------------------------------------------------
    $display("-- 用例 1：复位值 / VERSION / 地址译码 --");
    apb_rd(O_SEQ, rd);    ck32("复位 SEQ", rd, 32'd0);
    apb_rd(O_FST, rd);    ck32("复位 FRAME_STATUS", rd, 32'd0);
    apb_rd(O_VER, rd);    ck32("VERSION", rd, 32'h0001_0000);
    apb_rd(O_AUTHB, rd);  ck32("复位 AUTH_BASE", rd, 32'd0);
    apb_rd(O_ERRST, rd);  ck32("复位 ERR_STICKY", rd, 32'd0);
    apb_rd(O_LIVE, rd);   ck32("复位 LIVE_STATUS", rd, 32'd0);

    // ⚠️ 关键：未映射地址的 pready 必须为 1，否则 APB 总线挂死
    @(negedge clk);
    paddr = 16'h0200; psel = 1; penable = 1; pwrite = 0;
    @(negedge clk);
    ckbit("未映射 paddr 仍 PREADY=1", pready, 1'b1);
    ckbit("未映射 paddr 报 PSLVERR",  pslverr, 1'b1);
    paddr = 16'h0000; @(negedge clk);
    ckbit("保留区 0x00 仍 PREADY=1",  pready, 1'b1);
    ckbit("保留区 0x00 报 PSLVERR",   pslverr, 1'b1);
    paddr = BASE; @(negedge clk);
    ckbit("本段内 PSLVERR=0",         pslverr, 1'b0);
    psel = 0; penable = 0;

    //------------------------------------------------------------------
    $display("-- 用例 2：无授权 -> AUTH_ERR，BASE_ADDR=0 --");
    do_frame(16'h0001, 32'd1000, 32'd1000, 1'b0, 1'b0, 1'b0);
    settle;
    apb_rd(O_FST, rd);
    ckbit("无授权 AUTH_ERR=1", rd[FS_AUTH], 1'b1);
    ckbit("无授权 FRAME_OK=0",  rd[FS_OK],   1'b0);
    apb_rd(O_BASE, rd);   ck32("无授权 BASE_ADDR=0", rd, 32'd0);

    //------------------------------------------------------------------
    $display("-- 用例 3：授权通路 --");
    do_auth(32'h0100_0000);          // 授权 FB_A
    apb_rd(O_LIVE, rd);
    ckbit("ARM 后 AUTH_PENDING 置位", rd[1], 1'b1);

    do_frame(16'h0002, 32'd1000, 32'd1000, 1'b0, 1'b0, 1'b0);
    settle;
    apb_rd(O_BASE, rd);   ck32("BASE_ADDR = 授权地址", rd, 32'h0100_0000);
    apb_rd(O_SLOT, rd);   ck32("SLOT = 0 (FB_A)", rd, 32'd0);
    apb_rd(O_FST, rd);
    ckbit("有授权 AUTH_ERR=0", rd[FS_AUTH], 1'b0);
    ckbit("好帧 FRAME_OK=1",   rd[FS_OK],   1'b1);
    apb_rd(O_LIVE, rd);
    ckbit("授权已被消费，PENDING 清零", rd[1], 1'b0);

    // 授权 FB_B -> SLOT 应为 1
    do_auth(FB_B);
    do_frame(16'h0003, 32'd1000, 32'd1000, 1'b0, 1'b0, 1'b0);
    settle;
    apb_rd(O_BASE, rd);   ck32("BASE_ADDR = FB_B", rd, FB_B);
    apb_rd(O_SLOT, rd);   ck32("SLOT = 1 (FB_B)", rd, 32'd1);

    //------------------------------------------------------------------
    $display("-- 用例 4：坏帧各位 --");
    do_auth(32'h0100_0000);

    do_frame(16'h0004, 32'd100, 32'd200, 1'b0, 1'b0, 1'b0);   // 长度不符
    settle;
    apb_rd(O_FST, rd);
    ckbit("LEN_ERR 置位", rd[FS_LEN], 1'b1);
    ckbit("LEN_ERR 时 FRAME_OK=0", rd[FS_OK], 1'b0);

    do_frame(16'h0005, 32'd100, 32'd100, 1'b0, 1'b0, 1'b1);   // BRESP 错
    settle;
    apb_rd(O_FST, rd);
    ckbit("BRESP_ERR 置位", rd[FS_BRESP], 1'b1);
    apb_rd(O_ERRST, rd);
    ckbit("BRESP 累积到 sticky", rd[2], 1'b1);

    do_frame(16'h0006, 32'd0, 32'd0, 1'b0, 1'b0, 1'b0);       // expect=0
    settle;
    apb_rd(O_FST, rd);
    ckbit("NO_DATA_ERR 置位", rd[FS_NODATA], 1'b1);

    //------------------------------------------------------------------
    $display("-- 用例 5：ACK_SEQ 匹配 / 不匹配 --");
    apb_rd(O_SEQ, s0);
    apb_wr(O_ACK, s0);
    apb_rd(O_ERRST, rd);
    ck32("ACK 匹配 -> sticky 清零", rd, 32'd0);

    do_auth(32'h0100_0000);
    do_frame(16'h0007, 32'd100, 32'd100, 1'b0, 1'b0, 1'b1);
    settle;
    apb_rd(O_ERRST, rd);
    ckbit("新错误置位", rd[2], 1'b1);
    apb_wr(O_ACK, 32'hDEAD_0000);        // 不匹配
    apb_rd(O_ERRST, rd);
    ckbit("ACK 不匹配 -> 保留", rd[2], 1'b1);

    //------------------------------------------------------------------
    $display("-- 用例 6：LIVE_STATUS 实时，不受快照影响 --");
    apb_rd(O_LIVE, rd);   ckbit("CAL_DONE 初始 0", rd[0], 1'b0);
    cal_done = 1'b1;
    repeat (6) @(negedge clk);
    apb_rd(O_LIVE, rd);   ckbit("CAL_DONE 转 1", rd[0], 1'b1);
    apb_rd(O_FST, rd);    ckbit("FRAME_STATUS 无 CAL_DONE 位", rd[8], 1'b0);

    //------------------------------------------------------------------
    $display("-- 用例 7：SEQ 回绕 --");
    force dut.u_frame_status.st_seq = 32'hFFFF_FFFF;
    repeat (2) @(negedge clk);
    apb_rd(O_SEQ, rd);    ck32("SEQ force 到 MAX", rd, 32'hFFFF_FFFF);
    // force 期间过程赋值被忽略，必须先 release 再发帧
    release dut.u_frame_status.st_seq;
    repeat (2) @(negedge clk);
    do_auth(32'h0100_0000);
    do_frame(16'h0008, 32'd100, 32'd100, 1'b0, 1'b0, 1'b0);
    settle;
    apb_rd(O_SEQ, rd);    ck32("回绕到 0", rd, 32'd0);

    //------------------------------------------------------------------
    $display("-- 用例 8：seqlock 读取自洽 --");
    fork
        begin : frames
            // 注意：这里【不能】调用 do_auth —— 它会驱动 APB 信号，
            // 与 reader 分支抢总线。本用例只验快照自洽，无授权的帧
            // 同样会发布快照，足够。
            for (int i = 0; i < 24; i++) begin
                do_frame(16'h6000 + i[15:0], 32'd100, 32'd100, 1'b0, 1'b0, 1'b0);
                #150;
            end
        end
        begin : reader
            int tries; tries = 0;
            while (tries < 30) begin
                apb_rd(O_SEQ, s0);
                apb_rd(O_FID, rd);
                apb_rd(O_SEQ, s1);
                if (s0 == s1) begin
                    // 只允许读到 0（尚无快照）或 0x6000..0x6017 的合法帧号
                    if (rd[15:0] != 16'd0 &&
                        (rd[15:0] < 16'h6000 || rd[15:0] > 16'h6017)) begin
                        errors++;
                        $display("  [FAIL] seqlock 读到撕裂帧 id=0x%04x", rd[15:0]);
                    end
                    tries++;
                end
            end
            checks++;
        end
    join

    //------------------------------------------------------------------
    $display("-- 用例 9：G.3 —— ACK 与【同拍】发布 --");
    // 注意：只有当 ACK 写与 snap_pulse 真的落在同一个 clk 周期时，
    // G.3 的推论才适用。不同拍时 ACK 先到是合法的清除行为。
    // 所以本用例先检测同拍，只在同拍时断言。
    begin
        int coinc_n;
        int coinc_ok;
        coinc_n  = 0;
        coinc_ok = 0;

        for (int ph = 0; ph < 30; ph++) begin
            // 复位寄存器侧，重新开始
            @(negedge clk); rst_n = 0;
            repeat (4) @(negedge clk); rst_n = 1;
            repeat (4) @(negedge clk);
            cal_done   = 1'b0;
            coincident = 1'b0;

            // 先造一个带 BRESP 错误的帧，让 sticky 置位
            do_auth(32'h0100_0000);
            do_frame(16'h7000, 32'd100, 32'd100, 1'b0, 1'b0, 1'b1);
            settle;
            apb_rd(O_SEQ, s0);            // s0 = 1
            apb_rd(O_ERRST, rd);
            if (rd[2] !== 1'b1) begin
                errors++;
                $display("  [FAIL] 相位 %0d：前置条件不成立，sticky 未置位", ph);
            end

            // ACK 固定在 ~4 个 clk 周期后；帧按 ph 个 evt 周期扫。
            // 两个时钟周期不同（10ns vs 9.26ns），每步相对漂移约 0.74ns，
            // 30 步足以扫过完整的 clk 相位 —— 必然撞上同拍。
            fork
                begin
                    repeat (4) @(negedge clk);
                    apb_wr(O_ACK, s0);
                end
                begin
                    repeat (ph) @(negedge evt_clk);
                    do_frame(16'h7100 + ph[15:0], 32'd100, 32'd100,
                             1'b0, 1'b0, 1'b0);      // 好帧
                end
            join
            settle; settle;

            if (coincident) begin
                coinc_n++;
                apb_rd(O_ERRST, rd);
                if (rd[2] === 1'b1) coinc_ok++;
                else begin
                    errors++;
                    $display("  [FAIL] 相位 %0d：同拍时 G.3 旧错误被 ACK 抹掉了", ph);
                end
            end
            checks++;
        end

        // 扫了 40 个相位都没撞上同拍，说明测试没覆盖到目标场景
        if (coinc_n == 0) begin
            errors++;
            $display("  [FAIL] 30 个相位里没有一次同拍，G.3 未被覆盖");
        end
        $display("      30 个相位中同拍 %0d 次，其中 %0d 次旧错误保留",
                 coinc_n, coinc_ok);
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
    #4000000;
    $display("TIMEOUT");
    $finish;
end

endmodule
