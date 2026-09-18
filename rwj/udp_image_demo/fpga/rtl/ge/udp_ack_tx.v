`timescale 1ns/1ps
//==========================================================================
// udp_ack_tx.v —— 整帧收完后给 PC 回一条 24 字节 UDP 回执
//
// 为什么需要：
//   PC 的 sendto() 返回只说明“本地发出去了”，完全不代表 FPGA 收全了。
//   有了回执，PC 才能报“FPGA确认：收到 1843200/1843200 Byte”。
//
// 何时触发：
//   PC 在 START 包里置 ACK_REQ 标志，FPGA 在收到 END 且帧完整时请求一次。
//   不置这个标志时，本模块永远停在 IDLE，不驱动任何 MAC 发送信号。
//
// 发送前必须先解决 ARP：
//   mac 内部的 arp_cache 只在“收到 ARP 应答”时学习（见 arp_cache.v），
//   所以板子必须先主动问一次“who has 192.168.0.3”，拿到回执才能单播。
//   本模块在 mac_not_exist 时会先发 ARP 请求再等一会儿。
//
// 跨时钟域：
//   req_tgl / done_tgl 是“翻转”信号，用两级同步器 + 边沿检测。
//   req_payload 在 req_tgl 翻转期间由上层保持稳定（上层有 busy 保护，
//   必须等 done 回来才允许改），属于标准的 data+toggle 握手。
//
// 注意：这条路径没有在真实硬件上验证过，所以默认不启用。
//==========================================================================
module udp_ack_tx (
    input         clk,                 // gmii_tx_clk (125MHz)
    input         rst_n,

    // ---- 请求（来自 sys_clk 域）----
    input         req_tgl,
    input  [191:0] req_payload,   // 24 字节回执，byte0 在最高位
    output        done_tgl,            // 回送到 sys_clk 域

    // ---- MAC 状态 ----
    input         mac_not_exist,       // ARP 表没查到目标 MAC
    input         mac_send_end,        // 一次 MAC 发送结束

    // ---- 到 mac_top 的发送接口 ----
    input         udp_ram_data_req,    // mac 要数据了，一拍脉冲
    output        udp_tx_req,
    output [7:0]  ram_wr_data,
    output        ram_wr_en,
    output [15:0] udp_send_data_length,
    output        arp_request_req
);

// 回执固定 24 字节：
//   0..1 magic / 2..3 frame_id / 4..7 实收字节 / 8..11 声明字节
//   12 写入槽位 / 13 状态 / 14 显示槽位 / 15 保留
//   16..19 帧校验和(加) / 20..23 帧校验和(异或)
localparam ACK_LEN = 24;

// ARP 请求后等多久再发 UDP。125MHz 下约 8ms，足够对方应答 + mac 内部复位。
localparam ARP_WAIT_MAX = 20'd1_000_000;

// 等 mac_send_end 的超时。mac_send_end 会被 ARP/ICMP 的发送误触发，
// 所以给个兜底，避免状态机卡死。125MHz 下约 1ms。
localparam SEND_WAIT_MAX = 17'd125_000;

localparam A_IDLE     = 3'd0;
localparam A_ARP_REQ  = 3'd1;
localparam A_ARP_WAIT = 3'd2;
localparam A_GEN_REQ  = 3'd3;
localparam A_WRITE    = 3'd4;
localparam A_SEND     = 3'd5;
localparam A_DONE     = 3'd6;

reg [2:0]   state;
reg [19:0]  arp_cnt;
reg [16:0]  send_cnt;
reg [4:0]   byte_cnt;              // 0..23
reg [191:0] sh;              // 回执内容移位寄存器
reg         req_tgl_d0, req_tgl_d1, req_tgl_d2;
reg         done_tgl_r;
reg         udp_tx_req_r;
reg         arp_req_r;
reg [7:0]   ram_wr_data_r;
reg         ram_wr_en_r;

assign udp_tx_req          = udp_tx_req_r;
assign arp_request_req     = arp_req_r;
assign ram_wr_data         = ram_wr_data_r;
assign ram_wr_en           = ram_wr_en_r;
assign udp_send_data_length = 16'd24;
assign done_tgl            = done_tgl_r;

// req_tgl 两级同步 + 上升/下降都算沿（翻转信号）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        req_tgl_d0 <= 1'b0;
        req_tgl_d1 <= 1'b0;
        req_tgl_d2 <= 1'b0;
    end else begin
        req_tgl_d0 <= req_tgl;
        req_tgl_d1 <= req_tgl_d0;
        req_tgl_d2 <= req_tgl_d1;
    end
end

wire req_pulse = req_tgl_d1 ^ req_tgl_d2;   // 翻转沿

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state        <= A_IDLE;
        arp_cnt      <= 20'd0;
        send_cnt     <= 17'd0;
        byte_cnt     <= 5'd0;
        sh           <= 192'd0;
        done_tgl_r   <= 1'b0;
        udp_tx_req_r <= 1'b0;
        arp_req_r    <= 1'b0;
        ram_wr_data_r<= 8'd0;
        ram_wr_en_r  <= 1'b0;
    end else begin
        arp_req_r    <= 1'b0;
        ram_wr_en_r  <= 1'b0;

        case (state)
            //----------------------------------------------------------
            A_IDLE: begin
                udp_tx_req_r <= 1'b0;
                if (req_pulse) begin
                    sh    <= req_payload;
                    state <= A_ARP_REQ;
                end
            end

            //----------------------------------------------------------
            // ARP 表没命中就先问一次；命中了直接发。
            A_ARP_REQ: begin
                if (mac_not_exist) begin
                    arp_req_r <= 1'b1;
                    arp_cnt   <= 20'd0;
                    state     <= A_ARP_WAIT;
                end else begin
                    state <= A_GEN_REQ;
                end
            end

            //----------------------------------------------------------
            A_ARP_WAIT: begin
                if (arp_cnt == ARP_WAIT_MAX) state <= A_GEN_REQ;
                else                         arp_cnt <= arp_cnt + 1'b1;
            end

            //----------------------------------------------------------
            // 拉高请求，等 mac 反过来要数据。
            A_GEN_REQ: begin
                udp_tx_req_r <= 1'b1;
                byte_cnt     <= 5'd0;
                if (udp_ram_data_req) begin
                    // mac 的 ram_write_addr 只要 ram_wr_en=0 就会归零，
                    // 所以这 16 个字节必须一个周期不落地连续写。
                    udp_tx_req_r <= 1'b0;
                    state        <= A_WRITE;
                end
            end

            //----------------------------------------------------------
            A_WRITE: begin
                ram_wr_data_r <= sh[191:184];
                ram_wr_en_r   <= 1'b1;
                sh            <= {sh[183:0], 8'h00};

                if (byte_cnt == ACK_LEN - 1) begin
                    byte_cnt  <= 5'd0;
                    send_cnt  <= 17'd0;
                    state     <= A_SEND;
                end else begin
                    byte_cnt <= byte_cnt + 1'b1;
                end
            end

            //----------------------------------------------------------
            A_SEND: begin
                if (mac_send_end || (send_cnt == SEND_WAIT_MAX)) begin
                    state <= A_DONE;
                end else begin
                    send_cnt <= send_cnt + 1'b1;
                end
            end

            //----------------------------------------------------------
            A_DONE: begin
                done_tgl_r <= ~done_tgl_r;   // 通知 sys 域：可以发下一条了
                state      <= A_IDLE;
            end

            default: state <= A_IDLE;
        endcase
    end
end

endmodule
