`timescale 1ns/1ps
//==========================================================================
// udp_img_rx.v —— UDP 图片接收模块
//
// 功能：
//   1. RGMII 物理层 -> GMII -> 以太网 MAC -> UDP 解析（复用 demo4 的 mac_top）
//   2. 解析 16 字节包头（magic/frame_id/packet_idx/total/payload_len/byte_offset）
//   3. 把图片数据按 128-bit（16 字节）组装输出，供上层写 DDR3
//
// 时钟域：内部工作在 gmii_rx_clk（125MHz，从 RGMII rxc 恢复）
//==========================================================================
module udp_img_rx (
    input         rst_n,

    // ---- RGMII 接收（来自 PHY）----
    input         rxc,           // 125MHz RX 时钟
    input  [3:0]  rxd_hi_i,      // RX 数据（DDR 高相位）
    input  [3:0]  rxd_lo_i,      // RX 数据（DDR 低相位）
    input         rx_dv_HI,      // RX 数据有效（DDR 高相位）
    input         rx_dv_LO,      // RX 数据有效（DDR 低相位）

    // ---- RGMII 发送（到 PHY）----
    output        tx_en_o_HI,
    output        tx_en_o_LO,
    output [3:0]  txd_hi_o,
    output [3:0]  txd_lo_o,

    // ---- MDIO（本版不主动配置 PHY，保持默认自协商）----
    output        mdc_o,
    output        mdio_o,
    output        mdio_oe,
    input         mdio_i,
    output        phy_rst_n,

    // ---- 图片数据输出（gmii_rx_clk 域）----
    output [127:0] img_data,          // 128-bit 图片数据
    output         img_data_valid,    // 数据有效
    output [31:0]  img_byte_offset,   // 本包数据在帧内的字节偏移
    output [15:0]  img_payload_len,   // 本包图片数据字节数
    output [7:0]   img_slot,          // 目标图片槽位
    output [7:0]   img_flags,         // START/END/SWAP/ACK/DBUF 标志
    output [31:0]  img_pkt_hdr,       // {frame_id, packet_idx}，上层用来查断号和串帧
    output         fifo_ovf,          // FIFO 溢出粘滞标志（rxc 域，上层自行同步）
    output         arp_miss,          // ARP 表未命中（gmii_tx_clk 域，上层自行同步）
    output         img_sof,           // 包首拍标记（同时也是控制 FIFO 的写使能）

    // ---- FIFO 满指示（来自上层三个跨时钟 FIFO 的写侧，都是 rxc 域）----
    input          rx_fifo_full,      // 数据 FIFO 满：这一拍的数据会丢
    input          ctrl_fifo_full,    // 控制字 FIFO 满
    input          fid_fifo_full,     // frame_id/packet_idx FIFO 满

    // ---- 回执（ACK）发送请求：sys_clk 域 <-> gmii_tx_clk 域 ----
    input          ack_tgl,           // sys 域请求翻转一次 = 请求发一条回执
    input  [127:0] ack_payload,       // 回执内容，在 tgl 翻转期间必须保持稳定
    output         ack_done_tgl       // 回执发完，翻转一次回到 sys 域
);

//==========================================================================
// 物理层 / MAC 互连信号
//==========================================================================

wire [7:0]  gmii_txd;
wire        gmii_tx_en;
wire        gmii_tx_clk;
wire [7:0]  gmii_rxd;
wire        gmii_rx_dv;
wire        gmii_rx_clk;

wire        e_rx_dv;
wire [7:0]  e_rxd;
wire        e_tx_en;
wire [7:0]  e_txd;
wire        e_rst_n;
wire [31:0] pack_total_len;

// MAC / UDP 接收接口
wire [7:0]  udp_rec_ram_rdata;
reg  [10:0] udp_rec_ram_read_addr;
wire [15:0] udp_rec_data_length;
wire        udp_rec_data_valid;
wire        arp_found;
wire        mac_not_exist;

// 发送侧（只给 ACK 模块用，本版不主动发图片）
wire        mac_send_end;
wire [7:0]  ack_ram_wr_data;
wire        ack_ram_wr_en;
wire        ack_udp_tx_req;
wire        ack_ram_data_req;
wire        ack_arp_request_req;
wire [15:0] ack_send_data_length;

// 本地网络参数（与 PC 端约定一致）
localparam [47:0] SRC_MAC  = 48'h00_0a_35_01_fe_c0;
localparam [31:0] SRC_IP   = 32'hc0a80002;   // 192.168.0.2
localparam [31:0] DST_IP   = 32'hc0a80003;   // 192.168.0.3
localparam [15:0] SRC_PORT = 16'h1f90;       // 8080
localparam [15:0] DST_PORT = 16'h1f90;       // 8080

assign phy_rst_n = 1'b1;    // 不复位 PHY
assign mdc_o     = 1'b0;    // 本版不做 MDIO 配置
assign mdio_o    = 1'b0;
assign mdio_oe   = 1'b0;

// RGMII <-> GMII 转换
reg [3:0] align_rxd_hi;
reg       align_rx_dv_hi;
wire [3:0] align_rxd_lo;
wire       align_rx_dv_lo;

always @(posedge rxc) begin
    align_rxd_hi   <= rxd_hi_i;
    align_rx_dv_hi <= rx_dv_HI;
end

assign align_rxd_lo   = rxd_lo_i;
assign align_rx_dv_lo = rx_dv_LO;

util_gmii_to_rgmii u_rgmii (
    .rst_n              (rst_n),
    .rgmii_rxc          (rxc),
    .rgmii_rx_hi        (align_rxd_lo),
    .rgmii_rx_lo        (align_rxd_hi),
    .rgmii_rx_dv        (align_rx_dv_lo),
    .rgmii_rx_er        (align_rx_dv_hi),
    .rgmii_tx_ctrl_hi   (tx_en_o_HI),
    .rgmii_tx_ctrl_lo   (tx_en_o_LO),
    .rgmii_txd_lo       (txd_lo_o),
    .rgmii_txd_hi       (txd_hi_o),
    .gmii_txd           (e_txd),
    .gmii_tx_en         (e_tx_en),
    .gmii_tx_er         (1'b0),
    .gmii_tx_clk        (gmii_tx_clk),
    .gmii_crs           (),
    .gmii_col           (),
    .gmii_rxd           (gmii_rxd),
    .gmii_rx_dv         (gmii_rx_dv),
    .gmii_rx_er         (),
    .gmii_rx_clk        (gmii_rx_clk),
    .duplex_mode        (1'b1)
);

// 时钟/复位仲裁 + 收发缓冲（1000M 固定）
gmii_arbi u_arbi (
    .clk            (gmii_tx_clk),
    .rst_n          (rst_n),
    .speed          (2'b10),        // 1000M
    .link           (1'b1),
    .pack_total_len (pack_total_len),
    .e_rst_n        (e_rst_n),
    .gmii_rx_dv     (gmii_rx_dv),
    .gmii_rxd       (gmii_rxd),
    .gmii_tx_en     (gmii_tx_en),
    .gmii_txd       (gmii_txd),
    .e_rx_dv        (e_rx_dv),
    .e_rxd          (e_rxd),
    .e_tx_en        (e_tx_en),
    .e_txd          (e_txd)
);

// MAC + UDP/ARP/ICMP（只接收，发送侧只做 ARP/ICMP 自动应答）
mac_top u_mac (
    .gmii_tx_clk                (gmii_tx_clk),
    .gmii_rx_clk                (gmii_rx_clk),
    .rst_n                      (e_rst_n),
    .source_mac_addr            (SRC_MAC),
    .TTL                        (8'h80),
    .source_ip_addr             (SRC_IP),
    .destination_ip_addr        (DST_IP),
    .udp_send_source_port       (SRC_PORT),
    .udp_send_destination_port  (DST_PORT),
    // 发送侧（只有 ACK 模块会用到；ACK 默认关闭时这几个信号恒为 0）
    .ram_wr_data                (ack_ram_wr_data),
    .ram_wr_en                  (ack_ram_wr_en),
    .udp_ram_data_req           (ack_ram_data_req),
    .udp_send_data_length       (ack_send_data_length),
    .udp_tx_req                 (ack_udp_tx_req),
    .arp_request_req            (ack_arp_request_req),
    .mac_data_valid             (gmii_tx_en),
    .mac_send_end               (mac_send_end),
    .mac_tx_data                (gmii_txd),
    // 接收侧
    .rx_dv                      (e_rx_dv),
    .mac_rx_datain              (e_rxd),
    .udp_rec_ram_rdata          (udp_rec_ram_rdata),
    .udp_rec_ram_read_addr      (udp_rec_ram_read_addr),
    .udp_rec_data_length        (udp_rec_data_length),
    .udp_rec_data_valid         (udp_rec_data_valid),
    .arp_found                  (arp_found),
    .mac_not_exist              (mac_not_exist)
);

//==========================================================================
// UDP 数据提取状态机（gmii_rx_clk 域）
//
// UDP 数据在 udp_rx 内部 RAM 的布局（重要：udp_rx 只把 UDP payload 写入 RAM，
// 不写 8 字节 UDP 头，所以 RAM[0] 就是 payload 的首字节）：
//   [0:16]   我们的 16 字节包头（magic/frame/pkt/total/plen/reserved/offset）
//   [16:..]  图片数据（payload_len 字节，16 字节对齐）
//==========================================================================

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

// udp_rec_data_valid 上升沿检测（它不是单周期脉冲，会保持一段时间）
reg  udp_valid_d;
wire udp_valid_pulse;

//--------------------------------------------------------------------------
// FIFO 溢出粘滞检测（rxc 域）
//
// 三个 FIFO 的写侧都在 rxc 域，写进去的那一刻如果 WrFull 是高的，这一拍
// 就永久丢了 —— 必须当场抓，事后再看已经晚了。
//
// 判据：数据/控制字写使能 与 对应的 WrFull 同拍为高。
// 清除：收到新的 START 包时清掉，所以每个 ACK 报的都是"这一帧"的溢出。
//--------------------------------------------------------------------------
localparam F_START_BIT = 32;         // 包头里 flags 字节的最低位 = START

reg ovf_sticky;

always @(posedge gmii_rx_clk or negedge e_rst_n) begin
    if (!e_rst_n) begin
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
assign arp_miss        = mac_not_exist;
assign img_sof         = sof;

// udp_rec_data_valid 上升沿检测（打一拍做边沿检测）
always @(posedge gmii_rx_clk or negedge e_rst_n) begin
    if (!e_rst_n)
        udp_valid_d <= 1'b0;
    else
        udp_valid_d <= udp_rec_data_valid;
end
assign udp_valid_pulse = udp_rec_data_valid && !udp_valid_d;

always @(posedge gmii_rx_clk or negedge e_rst_n) begin
    if (!e_rst_n) begin
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
        udp_rec_ram_read_addr <= 11'd0;
    end
    else begin
        case (state)
            //--------------------------------------------------------
            S_IDLE: begin
                sof         <= 1'b0;
                word_valid  <= 1'b0;
                word_cnt    <= 4'd0;

                if (udp_valid_pulse) begin
                    state    <= S_SET_ADDR;
                end
            end

            //--------------------------------------------------------
            // 设包头起始地址。udp_rec_ram_read_addr 本身是寄存器，
            // dpram 内部还有一级 raddr_reg，因此要用 S_PRIME_HDR 预取。
            S_SET_ADDR: begin
                udp_rec_ram_read_addr <= 11'd0;
                hdr_cnt  <= 5'd0;
                hdr_buf  <= 128'd0;
                state    <= S_PRIME_HDR;
            end

            //--------------------------------------------------------
            // 预取 RAM[0]，同时把外部地址提前到 RAM[1]。
            // 下一拍进入 S_READ_HDR 时，udp_rec_ram_rdata 才是 RAM[0]。
            S_PRIME_HDR: begin
                udp_rec_ram_read_addr <= 11'd1;
                state <= S_READ_HDR;
            end

            //--------------------------------------------------------
            // 读 16 字节包头（左移，保证字段按大端解释）
            S_READ_HDR: begin
                hdr_buf <= {hdr_buf[119:0], udp_rec_ram_rdata};

                if (hdr_cnt == 5'd15) begin
                    state   <= S_HDR_CHECK;   // 等第 16 字节进入 hdr_buf
                end
                else begin
                    // dpram 内部地址还会寄存一拍，所以地址提前一字节。
                    udp_rec_ram_read_addr <= hdr_cnt + 11'd2;
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
                        udp_rec_ram_read_addr <= 11'd17;
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
                word_reg <= {udp_rec_ram_rdata, word_reg[127:8]};

                if (word_cnt == 4'd15) begin
                    word_cnt  <= 4'd0;
                    word_valid <= 1'b1;   // 下一拍 word_reg 完整

                    // 读到最后一个字节则结束（图片数据在 RAM[16:16+payload_len]）
                    if (udp_rec_ram_read_addr >= 11'd15 + payload_len) begin
                        state <= S_DONE;
                    end
                    else begin
                        udp_rec_ram_read_addr <= udp_rec_ram_read_addr + 1'b1;
                    end
                end
                else begin
                    word_cnt  <= word_cnt + 1'b1;
                    word_valid <= 1'b0;
                    udp_rec_ram_read_addr <= udp_rec_ram_read_addr + 1'b1;
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

//==========================================================================
// 回执发送（UDP ACK）
//
// 只在 PC 端用 --ack 时才会被触发；没人请求时整个状态机停在 IDLE，
// udp_tx_req / ram_wr_en / arp_request_req 全部为 0，对原有收图链路零影响。
//==========================================================================

udp_ack_tx u_ack_tx (
    .clk                (gmii_tx_clk),
    .rst_n              (e_rst_n),

    .req_tgl            (ack_tgl),
    .req_payload        (ack_payload),
    .done_tgl           (ack_done_tgl),

    .mac_not_exist      (mac_not_exist),
    .mac_send_end       (mac_send_end),

    .udp_ram_data_req   (ack_ram_data_req),
    .udp_tx_req         (ack_udp_tx_req),
    .ram_wr_data        (ack_ram_wr_data),
    .ram_wr_en          (ack_ram_wr_en),
    .udp_send_data_length(ack_send_data_length),
    .arp_request_req    (ack_arp_request_req)
);

endmodule
