// museRISC crypto accelerator: AXI4-Lite slave wrapping the SHA-256
// block core and the 256-bit EC field unit. Keccak-f1600 is verified
// standalone (rtl/crypto/keccak_f1600.sv); its 1600-bit state needs a
// DMA/streaming interface, scheduled for Phase 1 -- engine select 1 is
// reserved and must not be used yet. Register map: docs/SPEC.md.
`default_nettype none
module muse_crypto_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output logic [1:0] s_axi_bresp,
    output logic       s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [7:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0] s_axi_rresp,
    output logic       s_axi_rvalid,
    input  wire        s_axi_rready
);
  localparam logic [255:0] SECP_P =
      256'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFE_FFFFFC2F;
  localparam logic [255:0] C25519_P =
      256'h7FFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFED;

  logic [511:0] din;
  logic [255:0] mod_regs;
  logic [31:0]  ctrl;
  logic [1:0]   modsel;
  logic         sha_start, fld_start, done_sticky;

  logic [255:0] modulus;
  logic [255:0] sha_digest, fld_result;
  logic         sha_busy, sha_done, fld_busy, fld_done;
  logic         any_busy;
  logic [255:0] dout;
  assign modulus = (modsel == 2'd0) ? SECP_P :
                   (modsel == 2'd1) ? C25519_P : mod_regs;
  assign any_busy = sha_busy | fld_busy;

  // Registers are little-endian (DIN0 first); SHA-256 wants the first
  // message word in block_in[511:480], so present a word-reversed view.
  logic [511:0] sha_block;
  always_comb begin
    for (int wi = 0; wi < 16; wi++) begin
      sha_block[511 - 32 * wi -: 32] = din[32 * wi +: 32];
    end
  end

  sha256_block u_sha (
      .clk(clk), .rst_n(rst_n), .start(sha_start),
      .block_in(sha_block), .digest_out(sha_digest),
      .busy(sha_busy), .done(sha_done));
  ec_field u_fld (
      .clk(clk), .rst_n(rst_n), .start(fld_start),
      .op(ctrl[7:6]), .a(din[255:0]), .b(din[511:256]),
      .mod(modulus), .result(fld_result),
      .busy(fld_busy), .done(fld_done));

  assign s_axi_awready = s_axi_awvalid & s_axi_wvalid & ~s_axi_bvalid;
  assign s_axi_wready  = s_axi_awready;
  assign s_axi_arready = ~s_axi_rvalid;
  logic wr, rd;
  assign wr = s_axi_awready & s_axi_wvalid;
  assign rd = s_axi_arvalid & s_axi_arready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      din <= '0; mod_regs <= '0; ctrl <= '0; modsel <= '0;
      dout <= '0;
      sha_start <= 1'b0; fld_start <= 1'b0; done_sticky <= 1'b0;
      s_axi_bvalid <= 1'b0; s_axi_bresp <= '0;
      s_axi_rvalid <= 1'b0; s_axi_rresp <= '0; s_axi_rdata <= '0;
    end else begin
      sha_start <= 1'b0; fld_start <= 1'b0;
      if (sha_done) begin
        dout <= sha_digest; done_sticky <= 1'b1;
      end
      if (fld_done) begin
        dout <= fld_result; done_sticky <= 1'b1;
      end

      if (wr) begin
        s_axi_bvalid <= 1'b1; s_axi_bresp <= '0;
        case (s_axi_awaddr)
          8'h00: begin
            ctrl <= s_axi_wdata; done_sticky <= 1'b0;
            if (s_axi_wdata[0] && s_axi_wdata[5:4] == 2'd0) begin
              sha_start <= 1'b1;
            end
            if (s_axi_wdata[0] && s_axi_wdata[5:4] == 2'd2) begin
              fld_start <= 1'b1;
            end
          end
          8'h68: modsel <= s_axi_wdata[1:0];
          default: begin
            if (s_axi_awaddr >= 8'h08 && s_axi_awaddr < 8'h48) begin
              din[32 * ((s_axi_awaddr - 8'h08) >> 2) +: 32] <=
                  s_axi_wdata;
            end else if (s_axi_awaddr >= 8'h6c &&
                         s_axi_awaddr < 8'h8c) begin
              mod_regs[32 * ((s_axi_awaddr - 8'h6c) >> 2) +: 32] <=
                  s_axi_wdata;
            end
          end
        endcase
      end else if (s_axi_bvalid & s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end

      if (rd) begin
        s_axi_rvalid <= 1'b1; s_axi_rresp <= '0;
        case (s_axi_araddr)
          8'h00: s_axi_rdata <= ctrl;
          8'h04: s_axi_rdata <= {30'b0, done_sticky, any_busy};
          8'h68: s_axi_rdata <= {30'b0, modsel};
          default: begin
            s_axi_rdata <= '0;
            if (s_axi_araddr >= 8'h48 && s_axi_araddr < 8'h68) begin
              s_axi_rdata <=
                  dout[32 * ((s_axi_araddr - 8'h48) >> 2) +: 32];
            end
          end
        endcase
      end else if (s_axi_rvalid & s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
      end
    end
  end
endmodule
`default_nettype wire
