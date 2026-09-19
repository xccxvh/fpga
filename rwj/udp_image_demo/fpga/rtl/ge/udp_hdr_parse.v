`timescale 1ns/1ps
//==========================================================================
// udp_hdr_parse.v —— UDP 图片负载解析与 128-bit 组装
//
// 2026-09-19 从 udp_img_rx.v 提取。**纯代码搬移，逻辑一行未改。**
//
// 为什么提取：
//   解析逻辑原本埋在 udp_img_rx 内部，和厂家 MAC + RGMII 层缠在一起，
//   而 RGMII 层用的是 Altera ALTDDIO_IN 原语，无法仿真
//   （ge/rgmii2gmii_altera/ 那 5 个文件）。结果是这部分逻辑
//   既没法独立验证，也没法在迁移时单独搬走。
//
//   提取后的边界是 mac_top 的 UDP 负载 RAM 接口，这是可以精确建模的：
//   上游只要给一个"来了 N 字节负载、负载在 RAM 里"的握手即可，
//   不需要建模以太网帧、IP 校验和、CRC32。
//
// 时钟域：gmii_rx_clk（125MHz，从 RGMII rxc 恢复）
//
// 负载在 RAM 里的布局（udp_rx 只写 UDP payload，不写 UDP 头）：
//   [0:16]    16 字节包头 magic/frame/pkt_idx/total/plen/slot/flags/offset
//   [16:..]   图片数据
//
//   注意 RAM 读有**两级延迟**：ram_addr 是寄存器，dpram 内部还有一级
//   raddr_reg。所以状态机用 S_PRIME_HDR 预取，S_READ_HDR 里收到的
//   ram_data 才正好是 ram_addr 指向的那一字节。
//==========================================================================
module udp_hdr_parse (
    input         clk,              // gmii_rx_clk
    input         rst_n,            // e_rst_n

    // ---- 来自 MAC 的 UDP 负载接口 ----
    input         pkt_valid,        // udp_rec_data_valid（非单拍，会保持）
    input  [15:0] pkt_len,          // udp_rec_data_length（本模块未使用，保留接口一致性）
    output reg [10:0] ram_addr,         // udp_rec_ram_read_addr
    input  [7:0]  ram_data,         // udp_rec_ram_rdata

    // ---- 三个下游 FIFO 的满指示（与写侧同域）----
    input         rx_fifo_full,     // 数据 FIFO 满：这一拍的数据会丢
    input         ctrl_fifo_full,   // 控制字 FIFO 满
    input         fid_fifo_full,    // frame_id/packet_idx FIFO 满

    // ---- 解析结果 ----
    output [127:0] img_data,        // 128-bit 图片数据
    output         img_data_valid,
    output         img_sof,         // 包首拍标记（控制字的 FIFO 写使能）
    output [31:0]  img_byte_offset,
    output [15:0]  img_payload_len,
    output [7:0]   img_slot,
    output [7:0]   img_flags,
    output [31:0]  img_pkt_hdr,     // {frame_id, packet_idx}
    output         fifo_ovf         // 溢出粘滞标志
);

localparam S_IDLE      = 3'd0;
localparam S_SET_ADDR  = 3'd1;
localparam S_PRIME_HDR = 3'd2;
localparam S_READ_HDR  = 3'd3;
localparam S_HDR_CHECK = 3'd4;
localparam S_READ_DATA = 3'd5;
localparam S_DONE      = 3'd6;

reg [2:0]   state;
reg [4:0]   hdr_cnt;          // 0..15，读 16 字节包头
reg [3:0]   word_cnt;         // 0..15，组装 128-bit
reg [127:0] hdr_buf;          // 包头移位寄存器（左移）
reg [127:0] word_reg;         // 数据 word（右移，保证低地址像素在低位）
reg         word_valid;
reg [15:0]  payload_len;
reg [7:0]   slot;
reg [7:0]   flags;
reg [15:0]  frame_id;
reg [15:0]  packet_idx;
reg [31:0]  byte_offset;
reg         sof;

// pkt_valid 上升沿检测（它不是单周期脉冲，会保持一段时间）
reg  pkt_valid_d;
wire pkt_valid_pulse;

//--------------------------------------------------------------------------
// FIFO 溢出粘滞检测
//
// 三个 FIFO 的写侧都在本时钟域，写进去的那一刻如果 WrFull 是高的，这一拍
// 就永久丢了 —— 必须当场抓，事后再看已经晚了。
//
// 判据：数据/控制字写使能 与 对应的 WrFull 同拍为高。
// 清除：收到新的 START 包时清掉，所以每个 ACK 报的都是"这一帧"的溢出。
//--------------------------------------------------------------------------
localparam F_START_BIT = 32;         // 包头里 flags 字节的最低位 = START

reg ovf_sticky;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ovf_sticky <= 1'b0;
    end
    else if (state == S_HDR_CHECK && hdr_buf[127:112] == 16'hA55A &&
             hdr_buf[63:48] == 16'd0 && hdr_buf[F_START_BIT]) begin
        ovf_sticky <= 1'b0;                      // 新帧开始，清上一帧的记录
    end
    else if ((word_valid && rx_fifo_full) ||
             (sof        && ctrl_fifo_full) ||
             (sof        && fid_fifo_full)) begin
        ovf_sticky <= 1'b1;
    end
end

assign img_data        = word_reg;
assign img_data_valid  = word_valid;
assign img_byte_offset = byte_offset;
assign img_payload_len = payload_len;
assign img_slot        = slot;
assign img_flags       = flags;
assign img_pkt_hdr     = {frame_id, packet_idx};
assign fifo_ovf        = ovf_sticky;
assign img_sof         = sof;

// pkt_valid 上升沿检测（打一拍做边沿检测）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        pkt_valid_d <= 1'b0;
    else
        pkt_valid_d <= pkt_valid;
end
assign pkt_valid_pulse = pkt_valid && !pkt_valid_d;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state        <= S_IDLE;
        hdr_cnt      <= 5'd0;
        word_cnt     <= 4'd0;
        hdr_buf      <= 128'd0;
        word_reg     <= 128'd0;
        word_valid   <= 1'b0;
        payload_len  <= 16'd0;
        slot         <= 8'd0;
        flags        <= 8'd0;
        frame_id     <= 16'd0;
        packet_idx   <= 16'd0;
        byte_offset  <= 32'd0;
        sof          <= 1'b0;
        ram_addr     <= 11'd0;
    end
    else begin
        case (state)
            //--------------------------------------------------------
            S_IDLE: begin
                sof         <= 1'b0;
                word_valid  <= 1'b0;

                if (pkt_valid_pulse) begin
                    state    <= S_SET_ADDR;
                end
            end

            //--------------------------------------------------------
            // 设包头起始地址。ram_addr 本身是寄存器，
            // dpram 内部还有一级 raddr_reg，因此要用 S_PRIME_HDR 预取。
            S_SET_ADDR: begin
                ram_addr <= 11'd0;
                hdr_cnt  <= 5'd0;
                hdr_buf  <= 128'd0;
                state    <= S_PRIME_HDR;
            end

            //--------------------------------------------------------
            // 预取 RAM[0]，同时把外部地址提前到 RAM[1]。
            // 下一拍进入 S_READ_HDR 时，ram_data 才是 RAM[0]。
            S_PRIME_HDR: begin
                ram_addr <= 11'd1;
                state <= S_READ_HDR;
            end

            //--------------------------------------------------------
            // 读 16 字节包头（左移，保证字段按大端解释）
            S_READ_HDR: begin
                hdr_buf <= {hdr_buf[119:0], ram_data};

                if (hdr_cnt == 5'd15) begin
                    state   <= S_HDR_CHECK;   // 等第 16 字节进入 hdr_buf
                end
                else begin
                    // dpram 内部地址还会寄存一拍，所以地址提前一字节。
                    ram_addr <= hdr_cnt + 11'd2;
                    hdr_cnt <= hdr_cnt + 1'b1;
                end
            end

            //--------------------------------------------------------
            // 包头解析（此时 hdr_buf 已含完整 16 字节）
            // 左移累积：最早读的 RAM[0] 在最高位 [127:120]
            //   [127:112]=magic [111:96]=frame [95:80]=pkt_idx
            //   [79:64]=total  [63:48]=payload_len
            //   [47:40]=slot   [39:32]=flags
            //   [31:0]=byte_offset
            S_HDR_CHECK: begin
                if (hdr_buf[127:112] == 16'hA55A) begin   // magic
                    payload_len <= hdr_buf[63:48];        // RAM[8:10]
                    slot        <= hdr_buf[47:40];        // RAM[10]
                    flags       <= hdr_buf[39:32];        // RAM[11]
                    frame_id    <= hdr_buf[111:96];       // RAM[2:4]
                    packet_idx  <= hdr_buf[95:80];        // RAM[4:6]
                    byte_offset <= hdr_buf[31:0];         // RAM[12:16]
                    word_cnt    <= 4'd0;
                    word_reg    <= 128'd0;
                    word_valid  <= 1'b0;
                    sof         <= 1'b1;                  // 控制字在这一拍写进 ctrl FIFO

                    if (hdr_buf[63:48] == 16'd0) begin
                        // START / END 控制包：没有数据，直接结束。
                        // 绝不能走 S_READ_DATA —— 那会读进 16 个垃圾字节
                        // 并把 word_valid 拉高，凭空写坏 DDR。
                        state <= S_DONE;
                    end
                    else begin
                        // RAM[16] 已在读数据端，提前给出下一个地址。
                        ram_addr <= 11'd17;
                        state <= S_READ_DATA;
                    end
                end
                else begin
                    state <= S_IDLE;   // magic 不对，丢弃
                end
            end

            //--------------------------------------------------------
            // 读 payload，每 16 字节组装一个 128-bit（右移）
            S_READ_DATA: begin
                sof <= 1'b0;
                word_reg <= {ram_data, word_reg[127:8]};

                if (word_cnt == 4'd15) begin
                    word_cnt  <= 4'd0;
                    word_valid <= 1'b1;   // 下一拍 word_reg 完整

                    // 读到最后一个字节则结束（图片数据在 RAM[16:16+payload_len]）
                    if (ram_addr >= 11'd15 + payload_len) begin
                        state <= S_DONE;
                    end
                    else begin
                        ram_addr <= ram_addr + 1'b1;
                    end
                end
                else begin
                    word_cnt  <= word_cnt + 1'b1;
                    word_valid <= 1'b0;
                    ram_addr <= ram_addr + 1'b1;
                end
            end

            //--------------------------------------------------------
            S_DONE: begin
                sof <= 1'b0;
                word_valid <= 1'b0;   // 拉低，防止最后一个 128-bit 重复写 FIFO
                state <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
