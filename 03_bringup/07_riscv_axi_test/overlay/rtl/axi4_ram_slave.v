`timescale 1ns/1ps

// Minimal single-beat AXI4 slave used by the Sapphire axi4Demo.
// AW and W are accepted independently to avoid the deadlock present in the
// older vendor example slave. The 2 KiB RAM covers the demo's 0x000..0x7ff
// test range. Only single-beat accesses (AxLEN == 0) are supported.
module axi4_ram_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    output                      axi_interrupt,
    input                       axi_aclk,
    input                       axi_resetn,
    input  [7:0]                axi_awid,
    input  [ADDR_WIDTH-1:0]     axi_awaddr,
    input  [7:0]                axi_awlen,
    input  [2:0]                axi_awsize,
    input  [1:0]                axi_awburst,
    input                       axi_awlock,
    input  [3:0]                axi_awcache,
    input  [2:0]                axi_awprot,
    input  [3:0]                axi_awqos,
    input  [3:0]                axi_awregion,
    input                       axi_awvalid,
    output                      axi_awready,
    input  [DATA_WIDTH-1:0]     axi_wdata,
    input  [(DATA_WIDTH/8)-1:0] axi_wstrb,
    input                       axi_wlast,
    input                       axi_wvalid,
    output                      axi_wready,
    output [7:0]                axi_bid,
    output [1:0]                axi_bresp,
    output                      axi_bvalid,
    input                       axi_bready,
    input  [7:0]                axi_arid,
    input  [ADDR_WIDTH-1:0]     axi_araddr,
    input  [7:0]                axi_arlen,
    input  [2:0]                axi_arsize,
    input  [1:0]                axi_arburst,
    input                       axi_arlock,
    input  [3:0]                axi_arcache,
    input  [2:0]                axi_arprot,
    input  [3:0]                axi_arqos,
    input  [3:0]                axi_arregion,
    input                       axi_arvalid,
    output                      axi_arready,
    output [7:0]                axi_rid,
    output [DATA_WIDTH-1:0]     axi_rdata,
    output [1:0]                axi_rresp,
    output                      axi_rlast,
    output                      axi_rvalid,
    input                       axi_rready
);

    reg [DATA_WIDTH-1:0] memory [0:511];
    reg                  aw_pending;
    reg [ADDR_WIDTH-1:0] awaddr_reg;
    reg [7:0]            awid_reg;
    reg                  bvalid_reg;
    reg [7:0]            bid_reg;
    reg                  rvalid_reg;
    reg [DATA_WIDTH-1:0] rdata_reg;
    reg [7:0]            rid_reg;
    reg                  interrupt_reg;
    integer              byte_index;

    assign axi_awready   = !aw_pending && !bvalid_reg;
    assign axi_wready    = aw_pending && !bvalid_reg;
    assign axi_bid       = bid_reg;
    assign axi_bresp     = 2'b00;
    assign axi_bvalid    = bvalid_reg;
    assign axi_arready   = !rvalid_reg;
    assign axi_rid       = rid_reg;
    assign axi_rdata     = rdata_reg;
    assign axi_rresp     = 2'b00;
    assign axi_rlast     = 1'b1;
    assign axi_rvalid    = rvalid_reg;
    assign axi_interrupt = interrupt_reg;

    always @(posedge axi_aclk or negedge axi_resetn) begin
        if (!axi_resetn) begin
            aw_pending    <= 1'b0;
            awaddr_reg    <= {ADDR_WIDTH{1'b0}};
            awid_reg      <= 8'h00;
            bvalid_reg    <= 1'b0;
            bid_reg       <= 8'h00;
            rvalid_reg    <= 1'b0;
            rdata_reg     <= {DATA_WIDTH{1'b0}};
            rid_reg       <= 8'h00;
            interrupt_reg <= 1'b0;
        end else begin
            interrupt_reg <= 1'b0;

            if (axi_awvalid && axi_awready) begin
                aw_pending <= 1'b1;
                awaddr_reg <= axi_awaddr;
                awid_reg   <= axi_awid;
            end

            if (axi_wvalid && axi_wready) begin
                for (byte_index = 0; byte_index < DATA_WIDTH/8;
                     byte_index = byte_index + 1) begin
                    if (axi_wstrb[byte_index])
                        memory[awaddr_reg[10:2]][byte_index*8 +: 8]
                            <= axi_wdata[byte_index*8 +: 8];
                end
                aw_pending    <= 1'b0;
                bvalid_reg    <= 1'b1;
                bid_reg       <= awid_reg;
                interrupt_reg <= (axi_wdata == 32'h0000_ABCD);
            end

            if (bvalid_reg && axi_bready)
                bvalid_reg <= 1'b0;

            if (axi_arvalid && axi_arready) begin
                rdata_reg  <= memory[axi_araddr[10:2]];
                rid_reg    <= axi_arid;
                rvalid_reg <= 1'b1;
            end else if (rvalid_reg && axi_rready) begin
                rvalid_reg <= 1'b0;
            end
        end
    end

endmodule
