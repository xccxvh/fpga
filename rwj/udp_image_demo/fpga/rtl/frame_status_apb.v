`timescale 1ns/1ps
//==========================================================================
// frame_status_apb.v —— UDP 帧完成状态寄存器（APB3 slave 内核）
//
// 历史 V1 原型。联合目标依据：
// `07_docs/interfaces/unified_fpga_interface_spec_v1.2.md`。
// 本模块当前尚不满足该规范的 UDP Frame RX V2.0 全部要求。
//
// **本模块只是内核**，只响应 `paddr[15:8] == 8'h01`（即 0xF8100100–0xF81001FF）。
// 整个 64KB 窗口的译码与 PREADY 由包装模块 `frame_status_apb_slave.v` 负责 ——
// 厂家原来的 `apb3_top` 是无条件 PREADY=1，而本内核是 `pready = sel`，
// **直接拿内核替换厂家模块会让未映射地址的 APB 访问永久挂起**。
//
//--------------------------------------------------------------------------
// 寄存器表（相对 0xF8100100，即内核内的 paddr[7:0]）
//
//   +0x00  SEQ           RO   完成序号；snapshot 的 commit 标志
//   +0x04  FRAME_STATUS  RO   快照位图，见下
//   +0x08  FRAME_ID      RO   高 16 位恒 0
//   +0x0C  SLOT          RO   0=A 1=B；**仅诊断用，BASE_ADDR 才是权威**
//   +0x10  BASE_ADDR     RO   硬件实际使用的锁存基址
//   +0x14  RX_BYTES      RO
//   +0x18  EXPECT_BYTES  RO
//   +0x1C  ACK_SEQ       WO   写已消费的 SEQ；匹配才清 ERR_STICKY
//   +0x20  LIVE_STATUS   RO   bit0 CAL_DONE  bit1 AUTH_PENDING
//   +0x24  ERR_STICKY    RO   跨帧粘滞，matching ACK 清
//   +0x28  VERSION       RO
//   +0x2C  AUTH_BASE     RW   C 写本次授权的后台 framebuffer 物理地址
//   +0x30  AUTH_CTRL     WO   写 bit0=1 → ARM
//   +0x34+ Reserved      RO   读回 0，写忽略
//
// FRAME_STATUS（紧凑排列，见答复文档 §E）：
//   bit0 FRAME_OK  bit1 SEQ_ERR  bit2 FIFO_OVF  bit3 BRESP_ERR
//   bit4 LEN_ERR   bit5 NO_DATA_ERR  bit6 AUTH_ERR
//
// ERR_STICKY：bit0 SEQ_ERR bit1 FIFO_OVF bit2 BRESP_ERR bit3 ARP_MISS
//             bit4 LEN_ERR  bit5 NO_DATA_ERR bit6 AUTH_ERR
//
//--------------------------------------------------------------------------
// D.1「SEQ 是整个 snapshot 的 commit 标志」
//
// 本实现里**所有 snapshot 字段（含 SEQ）在同一个时钟沿并行更新**，不存在
// "先改 SEQ 再逐个改字段"的窗口 —— 任何一次 APB 读要么全是旧帧、要么全是
// 新帧。统一规范要求软件不可观察到撕裂，本实现的同沿发布满足该要求。
//
//--------------------------------------------------------------------------
// ACK 与 publish 同周期（publish 优先）
//
//   if (publish_new_snapshot)          err_sticky <= err_sticky | new_frame_err;
//   else if (ack_wr && wdata == seq)   err_sticky <= 0;
//
// publish 分支读的是**旧值**再 OR —— 同拍时 ACK 被整体丢弃，旧错误不会被清。
// 这比"先清旧再 OR 新"更安全：粘滞寄存器宁可多留一次
// 旧错误，也不能误清掉软件还没读到的错误。
//
//--------------------------------------------------------------------------
// 授权通路（AUTH_BASE / AUTH_CTRL，C 在 P3 提议）
//
// 跨域方向是**寄存器域 → 事件域**（与快照相反）：
//
//   1. C 写 AUTH_BASE
//   2. C 写 AUTH_CTRL bit0=1 → 本域把 AUTH_BASE 复制进 auth_shadow，置
//      auth_pending。**pending 期间再写 ARM 会被丢弃**，C 可读
//      LIVE_STATUS.AUTH_PENDING 判断
//   3. auth_pending 经 2FF 同步到事件域
//   4. 事件域在 frame_start 时：有效 → 锁存 auth_shadow 为本帧地址并回送
//      consume toggle；无效 → AUTH_ERR，本帧不写 DDR、BASE_ADDR 报 0
//   5. 本域同步 consume toggle → 清 auth_pending
//
// auth_shadow 在整个传输期间不变（第 2 步的门控保证），所以事件域采样多 bit
// 数据是安全的 —— 这是"稳定数据 + 同步限定信号"模式，不是裸的多 bit 打两拍。
//==========================================================================
module frame_status_apb #(
    parameter [31:0] VERSION_INIT = 32'h0001_0000,  // 历史 V1 原型；联合 V2.0 必须改版
    parameter [31:0] FB_A_BASE    = 32'h0100_0000,
    parameter [31:0] FB_B_BASE    = 32'h0180_0000   // 用于推导 SLOT（仅诊断）
)(
    //======================================================================
    // 事件域：来自收帧逻辑的观测点
    //======================================================================
    input         evt_clk,
    input         evt_rst_n,

    input         frame_start,       // 单拍：START 控制包被处理（授权在此锁存）
    input         frame_done,        // 单拍：整帧完成，且写流水线已排空
    input  [15:0] frame_id,
    input  [31:0] frame_rx_bytes,
    input  [31:0] frame_expect_bytes,
    input         frame_seq_err,
    input         fifo_ovf,
    input         bresp_err,
    input         arp_miss,          // 异步，来自 MAC

    // 给 UDP AXI 写状态机的强制授权门控。联合顶层必须用这两个
    // 信号决定是否发写请求及写基址，不得再使用网络包内的 slot。
    output        evt_write_enable,
    output [31:0] evt_write_base,

    //======================================================================
    // 寄存器域：APB3 slave 内核
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
// 偏移与位定义
//==========================================================================
localparam OFF_SEQ        = 8'h00;
localparam OFF_FRAME_ST   = 8'h04;
localparam OFF_FRAME_ID   = 8'h08;
localparam OFF_SLOT       = 8'h0C;
localparam OFF_BASE_ADDR  = 8'h10;
localparam OFF_RX_BYTES   = 8'h14;
localparam OFF_EXPECT     = 8'h18;
localparam OFF_ACK_SEQ    = 8'h1C;
localparam OFF_LIVE       = 8'h20;
localparam OFF_ERR_STICKY = 8'h24;
localparam OFF_VERSION    = 8'h28;
localparam OFF_AUTH_BASE  = 8'h2C;
localparam OFF_AUTH_CTRL  = 8'h30;

localparam FS_FRAME_OK    = 0;
localparam FS_SEQ_ERR     = 1;
localparam FS_FIFO_OVF    = 2;
localparam FS_BRESP_ERR   = 3;
localparam FS_LEN_ERR     = 4;
localparam FS_NO_DATA_ERR = 5;
localparam FS_AUTH_ERR    = 6;

localparam ES_ARP_MISS    = 3;

// 快照位段（避免用算式写切片写错）
localparam SNAP_W         = 122;   // 16+3+32+32+32+7
localparam SN_ID_MSB      = 121, SN_ID_LSB    = 106;
localparam SN_SLOT_MSB    = 105, SN_SLOT_LSB  = 103;
localparam SN_BASE_MSB    = 102, SN_BASE_LSB  = 71;
localparam SN_RX_MSB      = 70,  SN_RX_LSB    = 39;
localparam SN_EXP_MSB     = 38,  SN_EXP_LSB   = 7;
localparam SN_ST_MSB      = 6,   SN_ST_LSB    = 0;

//==========================================================================
// 事件域
//==========================================================================

// ---- 授权：同步 pending ----
reg [1:0] pend_sync;
always @(posedge evt_clk or negedge evt_rst_n) begin
    if (!evt_rst_n) pend_sync <= 2'b00;
    else            pend_sync <= {pend_sync[0], auth_pending};
end

// ---- 帧内寄存器（START 锁存 / 清零，帧内累加）----
reg [15:0] cur_frame_id;
reg [31:0] cur_expect;
reg [31:0] cur_base;
reg [2:0]  cur_slot;
reg        cur_auth_ok;
reg        cur_seq_err, cur_fifo_ovf, cur_bresp_err;
reg        cons_tgl;

wire auth_addr_ok = (auth_shadow == FB_A_BASE) ||
                    (auth_shadow == FB_B_BASE);

// START 后整帧保持不变。无授权或非法基址时 base 必须为 0，
// write_enable 必须为 0，从硬件上防止 UDP 覆盖系统区或前台外的地址。
assign evt_write_enable = cur_auth_ok;
assign evt_write_base   = cur_auth_ok ? cur_base : 32'd0;

always @(posedge evt_clk or negedge evt_rst_n) begin
    if (!evt_rst_n) begin
        cur_frame_id <= 16'd0;  cur_expect  <= 32'd0;
        cur_base     <= 32'd0;  cur_slot    <= 3'd0;
        cur_auth_ok  <= 1'b0;   cons_tgl    <= 1'b0;
        cur_seq_err  <= 1'b0;   cur_fifo_ovf<= 1'b0;  cur_bresp_err <= 1'b0;
    end
    else if (frame_start) begin
        cur_frame_id <= frame_id;
        cur_expect   <= frame_expect_bytes;
        cur_auth_ok  <= pend_sync[1] && auth_addr_ok;
        // 无授权时上报 0 —— 软件能据此判 AUTH_ERR，且不会误当成某个真实基址
        cur_base     <= (pend_sync[1] && auth_addr_ok) ? auth_shadow : 32'd0;
        cur_slot     <= (pend_sync[1] && auth_addr_ok &&
                         (auth_shadow == FB_B_BASE)) ? 3'd1 : 3'd0;
        cur_seq_err  <= 1'b0;
        cur_fifo_ovf <= 1'b0;
        cur_bresp_err<= 1'b0;
        if (pend_sync[1]) cons_tgl <= ~cons_tgl;   // 回送：本次授权已消费
    end
    else begin
        if (frame_seq_err) cur_seq_err   <= 1'b1;
        if (fifo_ovf)      cur_fifo_ovf  <= 1'b1;
        if (bresp_err)     cur_bresp_err <= 1'b1;
    end
end

// ---- frame_done 那一拍组合出最终值 ----
// rx 直接用输入，不能用 cur_* —— 那个寄存器要到下一拍才更新，会晚一帧。
wire [31:0] fin_rx      = frame_done ? frame_rx_bytes : 32'd0;
wire        fin_len_err = (cur_expect != 32'd0) && (fin_rx != cur_expect);
wire        fin_no_data = (cur_expect == 32'd0);
wire        fin_seq_err = cur_seq_err   | frame_seq_err;
wire        fin_fifo    = cur_fifo_ovf  | fifo_ovf;
wire        fin_bresp   = cur_bresp_err | bresp_err;
wire        fin_auth_e  = ~cur_auth_ok;

wire [6:0] fin_status = {
    fin_auth_e,      // bit6 AUTH_ERR
    fin_no_data,     // bit5 NO_DATA_ERR
    fin_len_err,     // bit4 LEN_ERR
    fin_bresp,       // bit3 BRESP_ERR
    fin_fifo,        // bit2 FIFO_OVF
    fin_seq_err,     // bit1 SEQ_ERR
    ~fin_auth_e & ~fin_no_data & ~fin_len_err & ~fin_bresp
        & ~fin_fifo & ~fin_seq_err            // bit0 FRAME_OK
};

wire [SNAP_W-1:0] fin_snapshot = {
    cur_frame_id, cur_slot, cur_base, fin_rx, cur_expect, fin_status
};

reg [SNAP_W-1:0] evt_shadow;
reg              evt_tgl;

always @(posedge evt_clk or negedge evt_rst_n) begin
    if (!evt_rst_n) begin
        evt_shadow <= {SNAP_W{1'b0}};
        evt_tgl    <= 1'b0;
    end
    else if (frame_done) begin
        evt_shadow <= fin_snapshot;
        evt_tgl    <= ~evt_tgl;
    end
end

//==========================================================================
// 寄存器域
//==========================================================================
reg [2:0] tgl_sync;
reg [2:0] cons_sync;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tgl_sync  <= 3'b000;
        cons_sync <= 3'b000;
    end
    else begin
        tgl_sync  <= {tgl_sync[1:0],  evt_tgl};
        cons_sync <= {cons_sync[1:0], cons_tgl};
    end
end

wire snap_pulse = tgl_sync[2]  ^ tgl_sync[1];
wire cons_evt   = cons_sync[2] ^ cons_sync[1];

// evt_shadow 在 evt_tgl 翻转前已稳定，同步到本域后还有 ≥3 拍余量
reg [SNAP_W-1:0] snap_buf;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) snap_buf <= {SNAP_W{1'b0}};
    else        snap_buf <= evt_shadow;
end

reg [1:0] arp_miss_sync;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) arp_miss_sync <= 2'b00;
    else        arp_miss_sync <= {arp_miss_sync[0], arp_miss};
end

reg [1:0] cal_done_sync;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) cal_done_sync <= 2'b00;
    else        cal_done_sync <= {cal_done_sync[0], cal_done};
end

// ---- 授权寄存器 ----
reg [31:0] auth_base_reg;
reg [31:0] auth_shadow;
reg        auth_pending;

// ---- 快照寄存器 ----
reg [31:0] st_seq;
reg [6:0]  st_status;
reg [15:0] st_frame_id;
reg [2:0]  st_slot;
reg [31:0] st_base, st_rx, st_expect;
reg [31:0] err_sticky;

// APB 译码
wire in_range = (paddr[15:8] == 8'h01);
wire sel      = psel && in_range;
assign pready  = sel;
assign pslverr = 1'b0;

wire wr_en   = sel && penable && pwrite;
wire ack_wr  = wr_en && (paddr[7:0] == OFF_ACK_SEQ);
wire arm_wr  = wr_en && (paddr[7:0] == OFF_AUTH_CTRL) && pwdata[0];
wire base_wr = wr_en && (paddr[7:0] == OFF_AUTH_BASE);

wire ack_hit = ack_wr && (pwdata == st_seq);
wire [6:0] new_status = snap_buf[SN_ST_MSB : SN_ST_LSB];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        st_seq        <= 32'd0;
        st_status     <= 7'd0;
        st_frame_id   <= 16'd0;
        st_slot       <= 3'd0;
        st_base       <= 32'd0;
        st_rx         <= 32'd0;
        st_expect     <= 32'd0;
        err_sticky    <= 32'd0;
        auth_base_reg <= 32'd0;
        auth_shadow   <= 32'd0;
        auth_pending  <= 1'b0;
    end
    else begin
        // ---- 授权 ----
        if (base_wr)
            auth_base_reg <= pwdata;

        if (arm_wr && !auth_pending) begin
            auth_shadow  <= auth_base_reg;   // pending 期间保持不变
            auth_pending <= 1'b1;
        end
        else if (cons_evt) begin
            auth_pending <= 1'b0;
        end

        // ---- 快照发布（全部字段同沿并行，见头注 D.1）----
        if (snap_pulse) begin
            st_seq      <= st_seq + 32'd1;
            st_status   <= new_status;
            st_frame_id <= snap_buf[SN_ID_MSB   : SN_ID_LSB];
            st_slot     <= snap_buf[SN_SLOT_MSB : SN_SLOT_LSB];
            st_base     <= snap_buf[SN_BASE_MSB : SN_BASE_LSB];
            st_rx       <= snap_buf[SN_RX_MSB   : SN_RX_LSB];
            st_expect   <= snap_buf[SN_EXP_MSB  : SN_EXP_LSB];
        end

        // ---- ERR_STICKY：严格 G.1（publish 优先，ACK 只清不置）----
        if (snap_pulse)
            err_sticky <= err_sticky | {
                25'd0,
                new_status[FS_AUTH_ERR],
                new_status[FS_NO_DATA_ERR],
                new_status[FS_LEN_ERR],
                1'b0,                        // bit3 ARP_MISS 单独累积
                new_status[FS_BRESP_ERR],
                new_status[FS_FIFO_OVF],
                new_status[FS_SEQ_ERR]};
        else if (arp_miss_sync[1])
            err_sticky[ES_ARP_MISS] <= 1'b1;
        else if (ack_hit)
            err_sticky <= 32'd0;
    end
end

//==========================================================================
// APB 读
//==========================================================================
always @(*) begin
    case (paddr[7:0])
        OFF_SEQ        : prdata = st_seq;
        OFF_FRAME_ST   : prdata = {25'd0, st_status};
        OFF_FRAME_ID   : prdata = {16'd0, st_frame_id};
        OFF_SLOT       : prdata = {29'd0, st_slot};
        OFF_BASE_ADDR  : prdata = st_base;
        OFF_RX_BYTES   : prdata = st_rx;
        OFF_EXPECT     : prdata = st_expect;
        OFF_ACK_SEQ    : prdata = 32'd0;            // 只写
        OFF_LIVE       : prdata = {30'd0, auth_pending, cal_done_sync[1]};
        OFF_ERR_STICKY : prdata = err_sticky;
        OFF_VERSION    : prdata = VERSION_INIT;
        OFF_AUTH_BASE  : prdata = auth_base_reg;
        OFF_AUTH_CTRL  : prdata = 32'd0;            // 只写
        default        : prdata = 32'd0;            // 保留区读回 0
    endcase
end

endmodule
