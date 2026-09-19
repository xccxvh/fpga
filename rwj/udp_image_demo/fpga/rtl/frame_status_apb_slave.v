`timescale 1ns/1ps
//==========================================================================
// frame_status_apb_slave.v —— APB slave 0 整窗口包装
//
// 厂家工程在 `0xF8100000` 挂的是 `apb3_top`
// （`jzy/co_debug_2026/par/ddr_demo_ti60_2026/src/Interrupt.v:6`），
// 那是个空壳：`pready` 恒 1、`prdata` 恒 0、`pslverr` 恒 0，
// 只实现 offset 0 的一个可写位。本模块**整份替换**它。
//
//--------------------------------------------------------------------------
// ⚠️ 为什么需要这一层包装，而不是直接把内核接上去
//
// 厂家模块的关键性质是 **`PREADY` 无条件为 1**。APB 协议里 PREADY 是
// 从设备的"我完成了"信号 —— 如果某个地址永远不拉高 PREADY，
// **那一笔访问会让 APB 总线永久挂起**，整个 SoC 卡死。
//
// 而 `frame_status_apb` 内核是 `pready = sel`（只在自己那 256 字节内拉高），
// 这是为了便于多个从设备共享总线时做 OR。**直接拿内核替换厂家模块，
// 访问任何未映射地址都会挂死。** 所以必须由本层补上"未选中也拉高"。
//
//--------------------------------------------------------------------------
// 地址划分（同迁移文档）
//
//   0xF8100100–0xF81001FF   A 的帧状态寄存器
//   0xF8100000–0xF81000FF   保留区（迁移文档：不映射第二套 BitBlt 寄存器）
//   0xF8100200–0xF810FFFF   未映射
//
// 保留区与未映射区**返回 prdata=0 且 pslverr=1**。
//
// ⚠️ `PSLVERR=1` 是**相对厂家哑模块的行为变更** —— 厂家对任何地址都返回 0
//    且从不报错。改成报错更有诊断价值（软件能立刻发现地址写错），
//    但这属于行为变更。**待 B 确认**；若不接受，把下面 `unmapped_pslverr`
//    参数改成 1'b0 即可回到厂家行为。
//==========================================================================
module frame_status_apb_slave #(
    parameter [31:0] VERSION_INIT     = 32'h0001_0000,
    parameter [31:0] FB_A_BASE        = 32'h0100_0000,
    parameter [31:0] FB_B_BASE        = 32'h0180_0000,
    parameter        UNMAPPED_PSLVERR = 1'b1    // 未映射区是否报错，见头注
)(
    //======================================================================
    // APB3 slave 0 —— 整个 64KB 窗口
    //======================================================================
    input         clk,               // APB 时钟域
    input         rst_n,
    input  [15:0] paddr,
    input         psel,
    input         penable,
    input         pwrite,
    input  [31:0] pwdata,
    output [31:0] prdata,
    output        pready,
    output        pslverr,

    //======================================================================
    // 事件域（收帧逻辑侧）
    //======================================================================
    input         evt_clk,
    input         evt_rst_n,
    input         frame_start,
    input         frame_done,
    input  [15:0] frame_id,
    input  [31:0] frame_rx_bytes,
    input  [31:0] frame_expect_bytes,
    input         frame_seq_err,
    input         fifo_ovf,
    input         bresp_err,
    input         arp_miss,
    input         cal_done,

    // 联合顶层接到 UDP AXI 写状态机。
    output        evt_write_enable,
    output [31:0] evt_write_base
);

// 本模块负责的段：paddr[15:8] == 0x01，即 0xF8100100–0xF81001FF
wire in_range = (paddr[15:8] == 8'h01);

wire [31:0] fs_prdata;

frame_status_apb #(
    .VERSION_INIT (VERSION_INIT),
    .FB_A_BASE    (FB_A_BASE),
    .FB_B_BASE    (FB_B_BASE)
) u_frame_status (
    .evt_clk            (evt_clk),
    .evt_rst_n          (evt_rst_n),
    .frame_start        (frame_start),
    .frame_done         (frame_done),
    .frame_id           (frame_id),
    .frame_rx_bytes     (frame_rx_bytes),
    .frame_expect_bytes (frame_expect_bytes),
    .frame_seq_err      (frame_seq_err),
    .fifo_ovf           (fifo_ovf),
    .bresp_err          (bresp_err),
    .arp_miss           (arp_miss),
    .evt_write_enable   (evt_write_enable),
    .evt_write_base     (evt_write_base),
    .cal_done           (cal_done),
    .clk                (clk),
    .rst_n              (rst_n),
    .paddr              (paddr),
    .psel               (psel),
    .penable            (penable),
    .pwrite             (pwrite),
    .pwdata             (pwdata),
    .prdata             (fs_prdata),
    // 内核的 pready/pslverr 在本层被覆盖 —— 见头注
    .pready             (),
    .pslverr            ()
);

//--------------------------------------------------------------------------
// ⚠️ PREADY 必须无条件为 1
//
// 内核的 pready 只在自己段内拉高。这里覆盖成恒 1 —— 否则未映射地址的
// 访问会让 APB 总线永久挂起（厂家模块原本是恒 1）。
//--------------------------------------------------------------------------
assign pready  = 1'b1;

assign prdata  = in_range ? fs_prdata : 32'd0;
assign pslverr = in_range ? 1'b0 : UNMAPPED_PSLVERR;

endmodule
