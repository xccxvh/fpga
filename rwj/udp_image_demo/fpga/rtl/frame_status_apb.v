`timescale 1ns/1ps
//==========================================================================
// frame_status_apb.v —— UDP 帧完成状态寄存器（APB3 slave）
//
// 接口约定见 07_docs/interfaces/udp_frame_status_interface_review_v0.1.md
// 地址：0xF8100100 - 0xF81001FF（APB slave 0，低 256 字节为保留区）
//
// 2026-09-19 决议：③ 语义冻结，含三点补充 ——
//   (a) 最终 BRESP 后发布   (b) 跨时钟握手   (c) 只保留最新快照
//
//--------------------------------------------------------------------------
// (a) 最终 BRESP 后发布 —— 一条必须保持的不变量
//
// 本模块在 frame_done 那一刻发布快照，**前提是 frame_done 置起时本帧所有
// AXI 写响应都已经回来**。当前 top.v 的写状态机满足这条：
//
//     W_WB: if (bvalid) begin
//               if (bresp != 2'b00 && bresp != 2'b01) bresp_err <= 1'b1;
//               if (wbeats == 0) wstate <= W_IDLE;
//               else             wstate <= W_WA;
//           end
//
// 每个 burst 都在 W_WB 等 bvalid 才继续，全程最多一笔未完成写；
// 而 frame_done 在 W_CTRL 处理 END 时产生，进入 W_CTRL 前必经上一个
// DATA 包的 W_WB。所以发布时写流水线必然已排空。
//
// ⚠️ **一旦写通路改成流水线式（允许多笔未完成写），这个前提就不成立了** ——
//    届时必须把发布条件从 frame_done 改成"frame_done 且未完成写计数归零"，
//    否则会在最后一次 BRESP 到达前发布，把坏帧报成好帧。
//    合并到 B 的工程时 A 的写通路要挂到它的 AXI 写仲裁器上，那里要重新确认。
//
//--------------------------------------------------------------------------
// (b) 跨时钟握手
//
//   事件域 evt_clk：A 的收帧逻辑（top.v 的 sys_clk 域）
//   寄存器域 clk  ：APB 接口（合并后为 SoC 的 user_clk）
//
// 两域目前可能同源（A1-3 之前 sys_clk 是 108MHz、user_clk 是 100MHz），
// 也可能在 A1-3 统一。**按可能异步来设计**，这样两种情况下都对。
//
// 快照约 140 bit，**不能用多 bit 打两拍** —— 各 bit 到达时间不同会撕裂。
// 用 toggle 握手 + 双缓冲：事件域填好影子寄存器再翻 toggle，寄存器域
// 两级同步后整体锁存。
//
//--------------------------------------------------------------------------
// (c) 只保留最新快照
//
// 不排队、不累积。st_* 被每一帧覆盖；软件靠 SEQ + seqlock 读法判断有没有
// 新帧、读到的整组是否属于同一帧。
//==========================================================================
module frame_status_apb #(
    parameter [31:0] ID_MAGIC = 32'h4652_4D31   // "FRM1"
)(
    //======================================================================
    // 事件域：来自收帧逻辑的观测点
    //======================================================================
    input         evt_clk,
    input         evt_rst_n,

    input         frame_done,        // 单拍：整帧完成（且写流水线已排空，见 (a)）
    input  [15:0] frame_id,
    input  [2:0]  frame_slot,
    input  [31:0] frame_base,
    input  [31:0] frame_rx_bytes,
    input  [31:0] frame_expect_bytes,
    input         frame_ok,          // 整帧成功（含 !bresp_err）
    input         frame_seq_err,
    input         fifo_ovf,
    input         bresp_err,
    input         arp_miss,
    input  [31:0] frame_checksum,
    input         frame_swap,        // 本帧是否请求切屏
    input         swap_pulse,        // 单拍：显示端真的切屏了
    input  [15:0] swap_frame_id,

    //======================================================================
    // 寄存器域：APB3 slave
    //======================================================================
    input         cal_done,          // 实时回显，不属于快照

    input         clk,
    input         rst_n,
    input  [15:0] paddr,
    input         psel,
    input         penable,
    input         pwrite,
    input  [31:0] pwdata,
    output reg [31:0] prdata,
    output        pready,
    output        pslverr
);

//==========================================================================
// 寄存器偏移（模块内用 paddr[7:0]）
//==========================================================================
localparam OFF_FRAME_ID   = 8'h00;   // 0x100
localparam OFF_SLOT       = 8'h04;   // 0x104
localparam OFF_BASE_ADDR  = 8'h08;   // 0x108
localparam OFF_RX_BYTES   = 8'h0C;   // 0x10C
localparam OFF_EXPECT     = 8'h10;   // 0x110
localparam OFF_STATUS     = 8'h14;   // 0x114
localparam OFF_ACK        = 8'h18;   // 0x118
localparam OFF_SEQ        = 8'h1C;   // 0x11C
localparam OFF_SWAP_SEQ   = 8'h20;   // 0x120
localparam OFF_SWAP_FRAME = 8'h24;   // 0x124
localparam OFF_ERR_STICKY = 8'h28;   // 0x128
localparam OFF_ID         = 8'h2C;   // 0x12C
localparam OFF_LIVE       = 8'h30;   // 0x130

// STATUS 位 —— **纯快照**，不含任何实时位
localparam ST_DONE            = 0;
localparam ST_FRAME_OK        = 1;
localparam ST_SEQ_ERR         = 2;
localparam ST_FIFO_OVF        = 3;
localparam ST_BRESP_ERR       = 4;
localparam ST_BYTES_MISMATCH  = 5;
localparam ST_SWAPPED         = 6;

// LIVE_STATUS 位 —— 实时读，不参与快照
localparam LS_CAL_DONE        = 0;

// ERR_STICKY 位
localparam ES_SEQ_ERR         = 0;
localparam ES_FIFO_OVF        = 1;
localparam ES_BRESP_ERR       = 2;
localparam ES_ARP_MISS        = 3;
localparam ES_BYTES_MISMATCH  = 4;

//==========================================================================
// 事件域：组装快照 + toggle 握手
//==========================================================================
localparam SNAP_W = 16+3+32+32+32+16+32;   // = 163 bit

wire frame_bytes_mismatch = (frame_expect_bytes != 32'd0)
                         && (frame_rx_bytes != frame_expect_bytes);

// 快照里的 STATUS（bit0-7，不含实时的 CAL_DONE）
wire [15:0] evt_status = {
    9'd0,
    frame_swap,              // bit6 SWAPPED（切屏请求；实际完成由 swap_pulse 记录）
    frame_bytes_mismatch,    // bit5
    bresp_err,               // bit4
    fifo_ovf,                // bit3
    frame_seq_err,           // bit2
    frame_ok,                // bit1
    1'b1                     // bit0 DONE（快照必然已完成）
};

// 快照内容：{frame_id, slot, base, rx_bytes, expect_bytes, status, checksum}
wire [SNAP_W-1:0] evt_snapshot = {
    frame_id, frame_slot, frame_base, frame_rx_bytes,
    frame_expect_bytes, evt_status, frame_checksum
};

reg [SNAP_W-1:0] evt_shadow;
reg              evt_tgl;

always @(posedge evt_clk or negedge evt_rst_n) begin
    if (!evt_rst_n) begin
        evt_shadow <= {SNAP_W{1'b0}};
        evt_tgl    <= 1'b0;
    end
    else if (frame_done) begin
        evt_shadow <= evt_snapshot;
        evt_tgl    <= ~evt_tgl;      // 填好再翻，保证影子寄存器稳定
    end
end

// 切换事件单独一路（显示端在另一处，与帧完成不同步）
reg [15:0] evt_swap_frame;
reg        evt_swap_tgl;

always @(posedge evt_clk or negedge evt_rst_n) begin
    if (!evt_rst_n) begin
        evt_swap_frame <= 16'd0;
        evt_swap_tgl   <= 1'b0;
    end
    else if (swap_pulse) begin
        evt_swap_frame <= swap_frame_id;
        evt_swap_tgl   <= ~evt_swap_tgl;
    end
end

//==========================================================================
// 寄存器域：同步 toggle、整体锁存快照
//==========================================================================
reg [2:0] tgl_sync;
reg [2:0] swap_tgl_sync;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tgl_sync      <= 3'b000;
        swap_tgl_sync <= 3'b000;
    end
    else begin
        tgl_sync      <= {tgl_sync[1:0],      evt_tgl};
        swap_tgl_sync <= {swap_tgl_sync[1:0], evt_swap_tgl};
    end
end

wire snap_pulse = tgl_sync[2] ^ tgl_sync[1];        // 翻转沿 = 新快照
wire swap_evt   = swap_tgl_sync[2] ^ swap_tgl_sync[1];

// 锁存寄存器（发布）
reg [15:0] st_frame_id;
reg [2:0]  st_slot;
reg [31:0] st_base;
reg [31:0] st_rx_bytes;
reg [31:0] st_expect;
reg [15:0] st_status;
reg [31:0] st_checksum;
reg [31:0] st_seq;
reg [31:0] st_swap_seq;
reg [15:0] st_swap_frame;
reg [31:0] err_sticky;

// 跨域来的影子寄存器也要先同步（多 bit 不能直接用）。
// evt_shadow 在 evt_tgl 翻转前已稳定至少一拍，翻转沿同步到寄存器域后
// 还要再经两级，实际有 ≥3 拍余量，直接采样是安全的。
reg [SNAP_W-1:0] snap_buf;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) snap_buf <= {SNAP_W{1'b0}};
    else        snap_buf <= evt_shadow;
end

// ARP 未命中是异步事件（来自 MAC），跨到寄存器域累积
reg [1:0] arp_miss_sync;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) arp_miss_sync <= 2'b00;
    else        arp_miss_sync <= {arp_miss_sync[0], arp_miss};
end

// CAL_DONE 来自 DDR 控制器，是电平信号、校准后不再变化。
// 不进快照（软件在没有任何帧完成时也要能查），归 LIVE_STATUS。
reg [1:0] cal_done_sync;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) cal_done_sync <= 2'b00;
    else        cal_done_sync <= {cal_done_sync[0], cal_done};
end
wire cal_done_live = cal_done_sync[1];

// 本次发布的快照里的 status（注意：不能用 st_status，它在同一拍才被更新）
wire [15:0] new_status = snap_buf[SNAP_W-116 : SNAP_W-131];

wire        ack_hit    = ack_wr && (pwdata == st_seq);
// ACK 命中时本次发布的旧错误应被清掉，但新帧的错误必须留下
wire [31:0] err_base   = ack_hit ? 32'd0 : err_sticky;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        st_frame_id   <= 16'd0;
        st_slot       <= 3'd0;
        st_base       <= 32'd0;
        st_rx_bytes   <= 32'd0;
        st_expect     <= 32'd0;
        st_status     <= 16'd0;
        st_checksum   <= 32'd0;
        st_seq        <= 32'd0;
        st_swap_seq   <= 32'd0;
        st_swap_frame <= 16'd0;
        err_sticky    <= 32'd0;
    end
    else begin
        // ---- 新快照发布 ----
        if (snap_pulse) begin
            st_frame_id <= snap_buf[SNAP_W-1     : SNAP_W-16];
            st_slot     <= snap_buf[SNAP_W-17    : SNAP_W-19];
            st_base     <= snap_buf[SNAP_W-20    : SNAP_W-51];
            st_rx_bytes <= snap_buf[SNAP_W-52    : SNAP_W-83];
            st_expect   <= snap_buf[SNAP_W-84    : SNAP_W-115];
            st_status   <= new_status;
            st_checksum <= snap_buf[SNAP_W-132   : SNAP_W-163];
            st_seq      <= st_seq + 32'd1;
        end

        // ---- 切屏事件 ----
        if (swap_evt) begin
            st_swap_seq   <= st_swap_seq + 32'd1;
            st_swap_frame <= evt_swap_frame;
        end

        // ---- ERR_STICKY ----
        // ⚠️ 帧内错误必须取**快照里的** status，不能取事件域的原始信号
        //    （frame_ok / bresp_err / fifo_ovf / frame_seq_err）——
        //    那些是另一个时钟域的信号，在这里采样会撕裂。
        //    快照已经通过 toggle 握手整体跨过来了。
        //
        // 优先级：新快照发布 > ARP 累积 > ACK 清除。
        // 同拍发布新帧时，新帧的错误必须留下，不能被 ACK 抹掉。
        if (snap_pulse)
            err_sticky <= err_base
                        | {27'd0, new_status[ST_BYTES_MISMATCH],  // bit4
                           1'b0,                                  // bit3 ARP（单独累积）
                           new_status[ST_BRESP_ERR],              // bit2
                           new_status[ST_FIFO_OVF],               // bit1
                           new_status[ST_SEQ_ERR]};               // bit0
        else if (arp_miss_sync[1])
            err_sticky[ES_ARP_MISS] <= 1'b1;
        else if (ack_hit)
            err_sticky <= 32'd0;
    end
end

//==========================================================================
// APB3 slave —— 只响应 0x100-0x1FF（paddr[15:8] == 8'h01）
//==========================================================================
wire in_range = (paddr[15:8] == 8'h01);
wire sel      = psel && in_range;

assign pready  = sel;        // 零等待态；未选中时拉低，便于与其他模块 OR
assign pslverr = 1'b0;

wire wr_en = sel && penable && pwrite;

wire ack_wr = wr_en && (paddr[7:0] == OFF_ACK);

always @(*) begin
    case (paddr[7:0])
        OFF_FRAME_ID   : prdata = {16'd0, st_frame_id};
        OFF_SLOT       : prdata = {29'd0, st_slot};
        OFF_BASE_ADDR  : prdata = st_base;
        OFF_RX_BYTES   : prdata = st_rx_bytes;
        OFF_EXPECT     : prdata = st_expect;
        OFF_STATUS     : prdata = {16'd0, st_status[7:0]};   // 纯快照
        OFF_ACK        : prdata = 32'd0;          // 只写：清 ERR_STICKY
        OFF_SEQ        : prdata = st_seq;
        OFF_SWAP_SEQ   : prdata = st_swap_seq;
        OFF_SWAP_FRAME : prdata = {16'd0, st_swap_frame};
        OFF_ERR_STICKY : prdata = err_sticky;
        OFF_ID         : prdata = ID_MAGIC;
        OFF_LIVE       : prdata = {31'd0, cal_done_live};
        default        : prdata = 32'd0;
    endcase
end

endmodule
