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
    // [修复] 原为 [127:0]。上层 top.v 组的是 192 位（24 字节）回执，
    //   这里只声明 128 位会把高 64 位丢掉 —— 也就是 magic(0xA55B) 和 frame_id，
    //   再透传给 udp_ack_tx 时高位补 0，PC 端按 magic 校验直接拒收，
    //   导致 --ack / --retry 一直静默失效。纯粹是透传口，加宽即可。
    input  [191:0] ack_payload,       // 24 字节回执，byte0 在最高位
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
wire [10:0] udp_rec_ram_read_addr;   // 由 udp_hdr_parse 驱动
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

//==========================================================================
// UDP 负载解析（2026-09-19 提取为独立模块 udp_hdr_parse.v）
//
// 这段 FSM 原本内联在这里，和厂家 MAC + RGMII 层缠在一起。提取的理由：
//   1. RGMII 层用的是 Altera ALTDDIO_IN 原语（ge/rgmii2gmii_altera/），
//      无法仿真 —— 导致这部分逻辑既没法独立验证，也没法单独搬走
//   2. 解析逻辑和最终 DDR 布局无关，迁移到 B 的工程时要整体带走
//
// **纯代码搬移，逻辑一行未改。** 负载 RAM 布局与两级读延迟的说明见
// udp_hdr_parse.v 头部。
//==========================================================================
udp_hdr_parse u_parse (
    .clk             (gmii_rx_clk),
    .rst_n           (e_rst_n),

    // ---- 来自 MAC 的 UDP 负载接口 ----
    .pkt_valid       (udp_rec_data_valid),
    .pkt_len         (udp_rec_data_length),
    .ram_addr        (udp_rec_ram_read_addr),
    .ram_data        (udp_rec_ram_rdata),

    // ---- 下游三个 FIFO 的满指示 ----
    .rx_fifo_full    (rx_fifo_full),
    .ctrl_fifo_full  (ctrl_fifo_full),
    .fid_fifo_full   (fid_fifo_full),

    // ---- 解析结果 ----
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

// ARP 表未命中：直接来自 MAC，不经过解析逻辑
assign arp_miss = mac_not_exist;

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
