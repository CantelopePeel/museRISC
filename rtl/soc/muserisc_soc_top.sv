// museRISC SoC top (Phase 0/1 boundary).
// The in-house RV64 core (rtl/core) and an AXI crossbar plug in
// here in Phase 1 (issue #4, deferred). Today this file fixes the
// SoC-level contract -- clock/reset and the crypto accelerator's
// AXI-Lite port at 0x2000_0000 (see docs/SPEC.md memory map) -- so the
// OpenROAD macro flow and drivers have a stable target.
`default_nettype none
module muserisc_soc_top (
    input  wire        clk_i,
    input  wire        rst_ni,
    // Crypto accelerator AXI-Lite (driven by host crossbar in Phase 1;
    // exposed here for macro-level test / FPGA bring-up).
    input  wire [7:0]  crypto_awaddr,
    input  wire        crypto_awvalid,
    output wire        crypto_awready,
    input  wire [31:0] crypto_wdata,
    input  wire        crypto_wvalid,
    output wire        crypto_wready,
    output wire [1:0]  crypto_bresp,
    output wire        crypto_bvalid,
    input  wire        crypto_bready,
    input  wire [7:0]  crypto_araddr,
    input  wire        crypto_arvalid,
    output wire        crypto_arready,
    output wire [31:0] crypto_rdata,
    output wire [1:0]  crypto_rresp,
    output wire        crypto_rvalid,
    input  wire        crypto_rready
);
  muse_crypto_top u_crypto (
      .clk(clk_i), .rst_n(rst_ni),
      .s_axi_awaddr(crypto_awaddr), .s_axi_awvalid(crypto_awvalid),
      .s_axi_awready(crypto_awready), .s_axi_wdata(crypto_wdata),
      .s_axi_wvalid(crypto_wvalid), .s_axi_wready(crypto_wready),
      .s_axi_bresp(crypto_bresp), .s_axi_bvalid(crypto_bvalid),
      .s_axi_bready(crypto_bready), .s_axi_araddr(crypto_araddr),
      .s_axi_arvalid(crypto_arvalid), .s_axi_arready(crypto_arready),
      .s_axi_rdata(crypto_rdata), .s_axi_rresp(crypto_rresp),
      .s_axi_rvalid(crypto_rvalid), .s_axi_rready(crypto_rready));
endmodule
`default_nettype wire
