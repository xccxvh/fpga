`timescale 1ns/1ps
//==========================================================================
// tb_udp_hdr_parse.sv —— UDP 图片负载解析回归测试
//
// 测 udp_hdr_parse.v：16 字节包头解析、magic 校验、128-bit 组装、
// 字节偏移、FIFO 溢出粘滞。
//
// 这个 testbench 之所以存在：这段解析逻辑原本埋在 udp_img_rx 内部，
// 外面裹着厂家 MAC 和 Altera DDIO 原语（无法仿真），所以从未被验证过。
// 2026-09-19 提取成独立模块后，边界变成"给我 N 字节负载"这么简单，
// 终于可以脱离以太网帧、IP 校验和和 CRC32 来测。
//
// 负载 RAM 直接用真实的 dpram.v（1 拍读延迟），不手写模型 ——
// 状态机里的地址提前量（hdr_cnt + 2）正是按这个延迟算的，写错就测错了。
//
// 运行：make hdr-parse
//==========================================================================
module tb_udp_hdr_parse;

localparam CLK_HALF = 4;              // 125 MHz
localparam RAM_DEPTH = 2048;

logic clk = 1'b0;
logic rst_n;

always #CLK_HALF clk = ~clk;

//----------------------------------------------------------------------
// DUT
//----------------------------------------------------------------------
logic          pkt_valid;
logic [15:0]   pkt_len;
logic [10:0]   ram_addr;
logic [7:0]    ram_data;
logic          rx_fifo_full, ctrl_fifo_full, fid_fifo_full;
logic [127:0]  img_data;
logic          img_data_valid, img_sof, fifo_ovf;
logic [31:0]   img_byte_offset, img_pkt_hdr;
logic [15:0]   img_payload_len;
logic [7:0]    img_slot, img_flags;

udp_hdr_parse dut (
    .clk             (clk),
    .rst_n           (rst_n),
    .pkt_valid       (pkt_valid),
    .pkt_len         (pkt_len),
    .ram_addr        (ram_addr),
    .ram_data        (ram_data),
    .rx_fifo_full    (rx_fifo_full),
    .ctrl_fifo_full  (ctrl_fifo_full),
    .fid_fifo_full   (fid_fifo_full),
    .img_data        (img_data),
    .img_data_valid  (img_data_valid),
    .img_sof         (img_sof),
    .img_byte_offset (img_byte_offset),
    .img_payload_len (img_payload_len),
    .img_slot        (img_slot),
    .img_flags       (img_flags),
    .img_pkt_hdr     (img_pkt_hdr),
    .fifo_ovf        (fifo_ovf)
);

// 真实的负载 RAM，行为与板上完全一致（地址寄存 1 拍 + 组合读）
dpram #(.WIDTH(8), .DEPTH(11)) u_ram (
    .clock      (clk),
    .data       (8'd0),
    .wraddress  (11'd0),
    .rdaddress  (ram_addr),
    .wren       (1'b0),
    .q          (ram_data)
);

//----------------------------------------------------------------------
// 记分板
//----------------------------------------------------------------------
int errors = 0;
int checks = 0;

task automatic check_eq32(input string name, input logic [31:0] got, input logic [31:0] exp);
    checks++;
    if (got !== exp) begin
        errors++;
        $display("  [FAIL] %-28s got=0x%08x exp=0x%08x", name, got, exp);
    end
endtask

task automatic check_eq16(input string name, input logic [15:0] got, input logic [15:0] exp);
    checks++;
    if (got !== exp) begin
        errors++;
        $display("  [FAIL] %-28s got=0x%04x exp=0x%04x", name, got, exp);
    end
endtask

task automatic check_eq8(input string name, input logic [7:0] got, input logic [7:0] exp);
    checks++;
    if (got !== exp) begin
        errors++;
        $display("  [FAIL] %-28s got=0x%02x exp=0x%02x", name, got, exp);
    end
endtask

task automatic check_bit(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
        errors++;
        $display("  [FAIL] %-28s got=%b exp=%b", name, got, exp);
    end
endtask

//----------------------------------------------------------------------
// 采集：每次 img_data_valid 拉高，记一个 128-bit word
//----------------------------------------------------------------------
logic [127:0] words[$];
logic [127:0] w0;                       // iverilog 10.3 不支持 words[0][7:0] 两级索引
int           n_words = 0;
int           n_sofs  = 0;

always @(posedge clk) begin
    if (rst_n) begin
        if (img_data_valid) begin
            words.push_back(img_data);
            n_words++;
        end
        if (img_sof) begin
            n_sofs++;
        end
    end
end

//----------------------------------------------------------------------
// 负载注入
//----------------------------------------------------------------------
byte unsigned pkt [0:RAM_DEPTH-1];

task automatic clear_pkt;
    for (int i = 0; i < RAM_DEPTH; i++) pkt[i] = 8'h00;
endtask

// 16 字节包头：magic(2) frame(2) pkt_idx(2) total(2) plen(2) slot(1) flags(1) offset(4)
task automatic build_hdr(input logic [15:0] frame_id, input logic [15:0] pkt_idx,
                         input logic [15:0] total,    input logic [15:0] plen,
                         input logic [7:0]  slot,     input logic [7:0]  flags,
                         input logic [31:0] offset);
    pkt[0]  = 8'hA5;  pkt[1]  = 8'h5A;
    pkt[2]  = frame_id[15:8];  pkt[3]  = frame_id[7:0];
    pkt[4]  = pkt_idx[15:8];   pkt[5]  = pkt_idx[7:0];
    pkt[6]  = total[15:8];     pkt[7]  = total[7:0];
    pkt[8]  = plen[15:8];      pkt[9]  = plen[7:0];
    pkt[10] = slot;
    pkt[11] = flags;
    pkt[12] = offset[31:24];   pkt[13] = offset[23:16];
    pkt[14] = offset[15:8];    pkt[15] = offset[7:0];
endtask

// 把 pkt[] 装进 RAM
task automatic load_ram(input int nbytes);
    for (int i = 0; i < nbytes; i++) u_ram.ram[i] = pkt[i];
endtask

// 发一个包：拉高 pkt_valid 走完整个解析过程
task automatic send_pkt(input int nbytes);
    @(negedge clk);
    pkt_valid = 1'b1;
    pkt_len   = nbytes[15:0];
    // 解析最长约 16 + payload/16 拍，留足余量
    repeat (nbytes + 80) @(posedge clk);
    @(negedge clk);
    pkt_valid = 1'b0;
    repeat (8) @(posedge clk);
endtask

//----------------------------------------------------------------------
// 主测试
//----------------------------------------------------------------------
initial begin
    $display("===== udp_hdr_parse 回归 =====");

    rst_n = 1'b0;
    pkt_valid = 1'b0; pkt_len = 16'd0;
    rx_fifo_full = 1'b0; ctrl_fifo_full = 1'b0; fid_fifo_full = 1'b0;
    clear_pkt;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    //------------------------------------------------------------------
    $display("-- 用例 1：复位后输出全 0 --");
    check_eq32("复位 img_data",        img_data,        32'd0);
    check_bit ("复位 img_data_valid",  img_data_valid,  1'b0);
    check_bit ("复位 img_sof",         img_sof,         1'b0);
    check_bit ("复位 fifo_ovf",        fifo_ovf,        1'b0);

    //------------------------------------------------------------------
    $display("-- 用例 2：START 控制包（plen=0，无数据）--");
    clear_pkt;
    n_words = 0; n_sofs = 0; words.delete();
    // magic, frame_id=0x1234, pkt_idx=0, total=4, plen=0, slot=2,
    // flags=START|SWAP=0x05, offset=总字节数 0x00180000
    build_hdr(16'h1234, 16'd0, 16'd4, 16'd0, 8'd2, 8'h05, 32'h0018_0000);
    load_ram(16);
    send_pkt(16);

    check_eq16("START img_pkt_hdr[31:16]=frame", img_pkt_hdr[31:16], 16'h1234);
    check_eq16("START img_pkt_hdr[15:0]=pkt_idx", img_pkt_hdr[15:0], 16'd0);
    check_eq8 ("START img_slot",        img_slot,        8'd2);
    check_eq8 ("START img_flags",       img_flags,       8'h05);
    check_eq32("START img_byte_offset", img_byte_offset, 32'h0018_0000);
    check_eq16("START img_payload_len", img_payload_len, 16'd0);
    check_bit ("START 无数据 word",      n_words != 0,    1'b0);
    check_bit ("START 有 sof",           n_sofs  != 0,    1'b1);

    //------------------------------------------------------------------
    $display("-- 用例 3：DATA 包，16 字节 payload --");
    clear_pkt;
    n_words = 0; n_sofs = 0; words.delete();
    // plen=16, offset=0x00001000, slot=1, flags=0
    build_hdr(16'h1234, 16'd1, 16'd4, 16'd16, 8'd1, 8'h00, 32'h0000_1000);
    for (int i = 0; i < 16; i++) pkt[16+i] = 8'h10 + i;   // 0x10..0x1F
    load_ram(32);
    send_pkt(32);

    check_eq8 ("DATA img_slot",        img_slot,        8'd1);
    check_eq8 ("DATA img_flags",       img_flags,       8'h00);
    check_eq32("DATA img_byte_offset", img_byte_offset, 32'h0000_1000);
    check_eq16("DATA img_payload_len", img_payload_len, 16'd16);
    check_bit ("DATA 恰好 1 个 word",   n_words == 1,    1'b1);
    // word_reg 右移累积：最早读到的字节落在低 8 位
    if (n_words >= 1) begin
        w0 = words[0];
        check_eq8("DATA word[7:0]  = RAM[16]",  w0[7:0],     8'h10);
        check_eq8("DATA word[15:8] = RAM[17]",  w0[15:8],    8'h11);
        check_eq8("DATA word[127:120]=RAM[31]", w0[127:120], 8'h1F);
    end

    //------------------------------------------------------------------
    $display("-- 用例 4：magic 错误应被丢弃 --");
    clear_pkt;
    n_words = 0; n_sofs = 0; words.delete();
    build_hdr(16'h1234, 16'd1, 16'd4, 16'd16, 8'd1, 8'h00, 32'h0000_1000);
    pkt[0] = 8'hA5; pkt[1] = 8'h5B;      // magic 破坏
    for (int i = 0; i < 16; i++) pkt[16+i] = 8'h10 + i;
    load_ram(32);
    send_pkt(32);
    check_bit("magic 错：无 word",  n_words == 0, 1'b1);
    check_bit("magic 错：无 sof",   n_sofs  == 0, 1'b1);

    //------------------------------------------------------------------
    $display("-- 用例 5：FIFO 满 -> fifo_ovf 粘滞 --");
    clear_pkt;
    n_words = 0; n_sofs = 0; words.delete();
    build_hdr(16'h2222, 16'd1, 16'd4, 16'd16, 8'd1, 8'h00, 32'h0);
    for (int i = 0; i < 16; i++) pkt[16+i] = 8'h20 + i;
    load_ram(32);
    rx_fifo_full = 1'b1;                 // 数据 FIFO 满
    send_pkt(32);
    rx_fifo_full = 1'b0;
    check_bit("FIFO 满 -> ovf 置位", fifo_ovf, 1'b1);

    //------------------------------------------------------------------
    $display("-- 用例 6：新的 START 包清除 fifo_ovf --");
    clear_pkt;
    build_hdr(16'h2222, 16'd0, 16'd4, 16'd0, 8'd1, 8'h01, 32'h0);  // flags=START
    load_ram(16);
    send_pkt(16);
    check_bit("START 清 ovf", fifo_ovf, 1'b0);

    //------------------------------------------------------------------
    $display("-- 用例 7：END 包（flags=0x02）与 32 字节多 word --");
    clear_pkt;
    n_words = 0; n_sofs = 0; words.delete();
    build_hdr(16'h3333, 16'd9, 16'd4, 16'd32, 8'd3, 8'h00, 32'h0000_2000);
    for (int i = 0; i < 32; i++) pkt[16+i] = 8'h40 + i;
    load_ram(48);
    send_pkt(48);
    check_eq8 ("32B img_slot",        img_slot,        8'd3);
    check_eq16("32B img_payload_len", img_payload_len, 16'd32);
    check_eq32("32B img_byte_offset", img_byte_offset, 32'h0000_2000);
    check_bit ("32B 恰好 2 个 word",   n_words == 2,    1'b1);

    //------------------------------------------------------------------
    $display("");
    if (errors == 0)
        $display("udp_hdr_parse regression: PASSED (%0d checks)", checks);
    else
        $display("udp_hdr_parse regression: FAILED (%0d/%0d checks failed)", errors, checks);
    $display("");

    $finish;
end

// 超时保护
initial begin
    #500000;
    $display("TIMEOUT");
    $finish;
end

endmodule
