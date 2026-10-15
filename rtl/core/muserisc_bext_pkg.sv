// museRISC in-house core: helpers for muserisc_bext
// (issue #27). Op encodings plus bit-manipulation and AES
// helper functions, extracted verbatim from
// muserisc_bext.sv; no behavior change.
`default_nettype none
package muserisc_bext_pkg;

  // Operation encoding (decoder assigns these).
  localparam logic [5:0] BOP_ADD_UW   = 6'd0;
  localparam logic [5:0] BOP_SH1ADD   = 6'd1;
  localparam logic [5:0] BOP_SH2ADD   = 6'd2;
  localparam logic [5:0] BOP_SH3ADD   = 6'd3;
  localparam logic [5:0] BOP_SH1ADDUW = 6'd4;
  localparam logic [5:0] BOP_SH2ADDUW = 6'd5;
  localparam logic [5:0] BOP_SH3ADDUW = 6'd6;
  localparam logic [5:0] BOP_SLLI_UW  = 6'd7;
  localparam logic [5:0] BOP_ANDN     = 6'd8;
  localparam logic [5:0] BOP_ORN      = 6'd9;
  localparam logic [5:0] BOP_XNOR     = 6'd10;
  localparam logic [5:0] BOP_CLZ      = 6'd11;
  localparam logic [5:0] BOP_CLZW     = 6'd12;
  localparam logic [5:0] BOP_CTZ      = 6'd13;
  localparam logic [5:0] BOP_CTZW     = 6'd14;
  localparam logic [5:0] BOP_CPOP     = 6'd15;
  localparam logic [5:0] BOP_CPOPW    = 6'd16;
  localparam logic [5:0] BOP_MAX      = 6'd17;
  localparam logic [5:0] BOP_MAXU     = 6'd18;
  localparam logic [5:0] BOP_MIN      = 6'd19;
  localparam logic [5:0] BOP_MINU     = 6'd20;
  localparam logic [5:0] BOP_SEXT_B   = 6'd21;
  localparam logic [5:0] BOP_SEXT_H   = 6'd22;
  localparam logic [5:0] BOP_ROL      = 6'd23;
  localparam logic [5:0] BOP_ROLW     = 6'd24;
  localparam logic [5:0] BOP_ROR      = 6'd25;   // incl. RORI
  localparam logic [5:0] BOP_RORW     = 6'd26;   // incl. RORIW
  localparam logic [5:0] BOP_ORC_B    = 6'd27;
  localparam logic [5:0] BOP_REV8     = 6'd28;
  localparam logic [5:0] BOP_CLMUL    = 6'd29;
  localparam logic [5:0] BOP_CLMULH   = 6'd30;
  localparam logic [5:0] BOP_CLMULR   = 6'd31;
  localparam logic [5:0] BOP_BCLR     = 6'd32;   // incl. I forms
  localparam logic [5:0] BOP_BEXT     = 6'd33;
  localparam logic [5:0] BOP_BINV     = 6'd34;
  localparam logic [5:0] BOP_BSET     = 6'd35;
  localparam logic [5:0] BOP_CZEQZ    = 6'd36;
  localparam logic [5:0] BOP_CZNEZ    = 6'd37;
  localparam logic [5:0] BOP_PACK     = 6'd38;
  localparam logic [5:0] BOP_PACKH    = 6'd39;
  localparam logic [5:0] BOP_PACKW    = 6'd40;
  localparam logic [5:0] BOP_BREV8    = 6'd41;
  localparam logic [5:0] BOP_XPERM4   = 6'd42;
  localparam logic [5:0] BOP_XPERM8   = 6'd43;
  localparam logic [5:0] BOP_AES_ES   = 6'd44;
  localparam logic [5:0] BOP_AES_ESM  = 6'd45;
  localparam logic [5:0] BOP_AES_DS   = 6'd46;
  localparam logic [5:0] BOP_AES_DSM  = 6'd47;
  localparam logic [5:0] BOP_AES_IM   = 6'd48;
  localparam logic [5:0] BOP_AES_KS1I = 6'd49;   // b_i[3:0] = rcon index
  localparam logic [5:0] BOP_AES_KS2  = 6'd50;
  localparam logic [5:0] BOP_SHA256SIG0 = 6'd51;
  localparam logic [5:0] BOP_SHA256SIG1 = 6'd52;
  localparam logic [5:0] BOP_SHA256SUM0 = 6'd53;
  localparam logic [5:0] BOP_SHA256SUM1 = 6'd54;
  localparam logic [5:0] BOP_SHA512SIG0 = 6'd55;
  localparam logic [5:0] BOP_SHA512SIG1 = 6'd56;
  localparam logic [5:0] BOP_SHA512SUM0 = 6'd57;
  localparam logic [5:0] BOP_SHA512SUM1 = 6'd58;

  // ---- helpers ------------------------------------------------
  function automatic logic [6:0] clz64(input logic [63:0] v);
    logic [6:0] n;
    n = 7'd64;
    for (int i = 63; i >= 0; i--) begin
      if (v[i] && (n == 7'd64)) n = 7'(63 - i);
    end
    return n;
  endfunction

  function automatic logic [6:0] ctz64(input logic [63:0] v);
    logic [6:0] n;
    n = 7'd64;
    for (int i = 0; i < 64; i++) begin
      if (v[i] && (n == 7'd64)) n = 7'(i);
    end
    return n;
  endfunction

  function automatic logic [127:0] clmul128(input logic [63:0] x,
                                            input logic [63:0] y);
    logic [127:0] r;
    r = 128'b0;
    for (int i = 0; i < 64; i++) begin
      if (y[i]) r = r ^ (128'(x) << i);
    end
    return r;
  endfunction

  function automatic logic [63:0] ror64(input logic [63:0] v,
                                        input logic [5:0] sh);
    if (sh == 6'd0) return v;
    return (v >> sh) | (v << (6'd0 - sh));
  endfunction

  function automatic logic [31:0] ror32(input logic [31:0] v,
                                        input logic [4:0] sh);
    if (sh == 5'd0) return v;
    return (v >> sh) | (v << (5'd0 - sh));
  endfunction

  // ---- AES tables from first principles -----------------------
  function automatic logic [7:0] gf_mul(input logic [7:0] x,
                                        input logic [7:0] y);
    logic [7:0] r;
    logic [7:0] a, b;
    r = 8'b0; a = x; b = y;
    for (int i = 0; i < 8; i++) begin
      if (b[0]) r = r ^ a;
      a = {a[6:0], 1'b0} ^ (a[7] ? 8'h1B : 8'h00);
      b = b >> 1;
    end
    return r;
  endfunction

  function automatic logic [7:0] gf_inv(input logic [7:0] x);
    // x^254 by repeated squaring (0 maps to 0).
    logic [7:0] r, base;
    int e;
    r = 8'h01; base = x; e = 254;
    if (x == 8'h00) return 8'h00;
    while (e > 0) begin
      if ((e & 1) != 0) r = gf_mul(r, base);
      base = gf_mul(base, base);
      e = e >> 1;
    end
    return r;
  endfunction

  function automatic logic [7:0] aes_sbox(input logic [7:0] x);
    logic [7:0] s;
    s = gf_inv(x);
    return s ^ {s[6:0], s[7]} ^ {s[5:0], s[7:6]} ^
           {s[4:0], s[7:5]} ^ {s[3:0], s[7:4]} ^ 8'h63;
  endfunction

  function automatic logic [7:0] aes_isbox(input logic [7:0] x);
    // inverse affine transform, then GF inverse
    logic [7:0] s;
    s = {x[6:0], x[7]} ^ {x[4:0], x[7:5]} ^ {x[1:0], x[7:2]} ^
        8'h05;
    return gf_inv(s);
  endfunction

  // MixColumns on one 32-bit column (little-endian bytes).
  function automatic logic [31:0] mixcol(input logic [31:0] w);
    logic [7:0] b0, b1, b2, b3;
    b0 = w[7:0]; b1 = w[15:8]; b2 = w[23:16]; b3 = w[31:24];
    return {
      gf_mul(b0, 8'h03) ^ b1 ^ b2 ^ gf_mul(b3, 8'h02),
      b0 ^ b1 ^ gf_mul(b2, 8'h02) ^ gf_mul(b3, 8'h03),
      b0 ^ gf_mul(b1, 8'h02) ^ gf_mul(b2, 8'h03) ^ b3,
      gf_mul(b0, 8'h02) ^ gf_mul(b1, 8'h03) ^ b2 ^ b3};
  endfunction

  function automatic logic [31:0] imixcol(input logic [31:0] w);
    logic [7:0] b0, b1, b2, b3;
    b0 = w[7:0]; b1 = w[15:8]; b2 = w[23:16]; b3 = w[31:24];
    return {
      gf_mul(b0, 8'h0B) ^ gf_mul(b1, 8'h0D) ^ gf_mul(b2, 8'h09) ^
          gf_mul(b3, 8'h0E),
      gf_mul(b0, 8'h0D) ^ gf_mul(b1, 8'h09) ^ gf_mul(b2, 8'h0E) ^
          gf_mul(b3, 8'h0B),
      gf_mul(b0, 8'h09) ^ gf_mul(b1, 8'h0E) ^ gf_mul(b2, 8'h0B) ^
          gf_mul(b3, 8'h0D),
      gf_mul(b0, 8'h0E) ^ gf_mul(b1, 8'h0B) ^ gf_mul(b2, 8'h0D) ^
          gf_mul(b3, 8'h09)};
  endfunction

  // One aes64 round half: rs1 (a) and rs2 (b) together hold
  // the 128-bit state (a = columns 0-1, b = columns 2-3,
  // column-major little-endian). Apply (Inv)ShiftRows and
  // (Inv)SubBytes, producing the low 64-bit half; swapping
  // the operands produces the high half. Byte selection
  // follows the K spec (cross-checked against CVA6 aes.sv).
  function automatic logic [63:0] aes_sub_shift(
      input logic [63:0] a, input logic [63:0] b, input logic inv);
    logic [7:0] s [16];
    logic [7:0] o [8];
    for (int i = 0; i < 8; i++) begin
      s[i]   = a[i*8 +: 8];
      s[i+8] = b[i*8 +: 8];
    end
    if (!inv) begin
      o[0] = s[0];  o[1] = s[5];  o[2] = s[10]; o[3] = s[15];
      o[4] = s[4];  o[5] = s[9];  o[6] = s[14]; o[7] = s[3];
    end else begin
      o[0] = s[0];  o[1] = s[13]; o[2] = s[10]; o[3] = s[7];
      o[4] = s[4];  o[5] = s[1];  o[6] = s[14]; o[7] = s[11];
    end
    for (int i = 0; i < 8; i++) begin
      o[i] = inv ? aes_isbox(o[i]) : aes_sbox(o[i]);
    end
    return {o[7], o[6], o[5], o[4], o[3], o[2], o[1], o[0]};
  endfunction

  function automatic logic [7:0] aes_rcon(input logic [3:0] i);
    unique case (i)
      4'h0:    return 8'h01;
      4'h1:    return 8'h02;
      4'h2:    return 8'h04;
      4'h3:    return 8'h08;
      4'h4:    return 8'h10;
      4'h5:    return 8'h20;
      4'h6:    return 8'h40;
      4'h7:    return 8'h80;
      4'h8:    return 8'h1B;
      4'h9:    return 8'h36;
      default: return 8'h00;   // 0xA unused by AES-128/192/256
    endcase
  endfunction

endpackage
`default_nettype wire
