// museRISC in-house core: helpers for muserisc_fpu (issue #27).
// Op encodings, the unpacked-operand type, and the pure
// helper functions used by the FPU dispatch. Extracted
// verbatim from muserisc_fpu.sv; no behavior change.
`default_nettype none
package muserisc_fpu_pkg;

  // Op encoding (op_i) for muserisc_fpu.
  localparam logic [4:0] FPU_ADD   = 5'd0;
  localparam logic [4:0] FPU_SUB   = 5'd1;
  localparam logic [4:0] FPU_MUL   = 5'd2;
  localparam logic [4:0] FPU_DIV   = 5'd3;
  localparam logic [4:0] FPU_SQRT  = 5'd4;
  localparam logic [4:0] FPU_SGNJ  = 5'd5;   // aux: 0=sgnj 1=sgnjn 2=sgnjx
  localparam logic [4:0] FPU_MINMAX= 5'd6;   // aux: 0=min 1=max
  localparam logic [4:0] FPU_CMP   = 5'd7;   // aux: 0=le 1=lt 2=eq
  localparam logic [4:0] FPU_CLASS = 5'd8;
  localparam logic [4:0] FPU_F2I   = 5'd9;   // aux: 0=W 1=WU 2=L 3=LU
  localparam logic [4:0] FPU_I2F   = 5'd10;  // aux: 0=W 1=WU 2=L 3=LU
  localparam logic [4:0] FPU_F2F   = 5'd11;  // fp->fp (fmt_d_i = dest)
  localparam logic [4:0] FPU_FMA   = 5'd12;  // a*b+c
  localparam logic [4:0] FPU_FMS   = 5'd13;  // a*b-c
  localparam logic [4:0] FPU_FNMS  = 5'd14;  // -(a*b)+c
  localparam logic [4:0] FPU_FNMA  = 5'd15;  // -(a*b)-c
  localparam logic [4:0] FPU_MVXF  = 5'd16;  // int bits -> fp reg
  localparam logic [4:0] FPU_MVFX  = 5'd17;  // fp raw bits -> int reg

  // ---------------------------------------------------------
  // Unpack. Produces a normalized significand with the hidden
  // bit at position (p-1) held in sig[52:0], an unbiased
  // exponent, and class flags.
  // ---------------------------------------------------------
  typedef struct {
    logic        sign;
    logic signed [15:0] exp;
    logic [52:0] sig;        // value = sig * 2^(exp-(p-1))
    logic        is_zero, is_inf, is_nan, is_snan, is_sub;
    logic [63:0] raw;        // effective bits (post box check)
  } unpacked_t;

  function automatic unpacked_t unpack(input logic [63:0] v,
                                       input logic d);
    unpacked_t u;
    logic [63:0] eff;
    logic [10:0] efield;
    logic [51:0] frac;
    logic [6:0]  pp;
    logic signed [15:0] e;
    logic [52:0] s;
    int sh;
    begin
      pp = d ? 7'd53 : 7'd24;
      eff = v;
      if (!d && (v[63:32] != 32'hFFFF_FFFF)) begin
        eff = 64'hFFFF_FFFF_7FC0_0000;  // improperly boxed
      end
      u.raw = eff;
      if (d) begin
        u.sign = eff[63]; efield = eff[62:52]; frac = eff[51:0];
        e = $signed({5'b0, efield}) - 16'sd1023;
      end else begin
        u.sign = eff[31]; efield = {3'b0, eff[30:23]};
        frac = {eff[22:0], 29'b0};
        e = $signed({5'b0, efield}) - 16'sd127;
      end
      u.is_zero = (efield == 0) && (frac == 0);
      u.is_sub  = (efield == 0) && (frac != 0);
      u.is_inf  = (efield == (d ? 11'h7FF : 11'h0FF)) && (frac == 0);
      u.is_nan  = (efield == (d ? 11'h7FF : 11'h0FF)) && (frac != 0);
      u.is_snan = u.is_nan && (frac[51] == 1'b0);
      // significand: frac is aligned with its MSB at bit 51;
      // take the top pp-1 bits under the hidden bit at pp-1.
      s = {1'b0, frac} >> (53 - pp);
      if (efield != 0) begin
        s[pp-1] = 1'b1;
      end else begin
        // subnormal: exponent is emin, significand not yet
        // normalized; normalize into the hidden bit. True zero
        // gets a below-range exponent so it always ranks as
        // the smaller operand in magnitude comparisons.
        e = d ? -16'sd1022 : -16'sd126;
        if (s == 0) e = -16'sd3000;
        if (s != 0) begin
          sh = 0;
          while (s[pp-1] == 1'b0 && sh < 60) begin
            s = s << 1; e = e - 16'sd1; sh = sh + 1;
          end
        end
      end
      u.exp = e;
      u.sig = s;
      return u;
    end
  endfunction

  function automatic logic [255:0] to_window(
      input logic [52:0] sig, input logic [6:0] pp);
    return {203'b0, sig} << (8'd255 - {1'b0, pp} + 8'd1);
  endfunction

  function automatic logic [8:0] clz256(input logic [255:0] v);
    logic [8:0] n;
    n = 9'd256;
    for (int i = 255; i >= 0; i--) begin
      if (v[i] && (n == 9'd256)) n = 9'(255 - i);
    end
    return n;
  endfunction

  function automatic logic [127:0] isqrt(input logic [255:0] v);
    logic [255:0] rem_v;
    logic [127:0] root;
    logic [255:0] trial;
    root = 128'b0;
    rem_v = v;
    for (int i = 127; i >= 0; i--) begin
      // (root with bit i set)^2 - root^2 = root*2^(i+1) + 2^2i,
      // where root holds only the already-chosen higher bits.
      trial = (256'(root) << (i + 1)) + (256'b1 << (2*i));
      if (rem_v >= trial) begin
        root[i] = 1'b1;
        rem_v = rem_v - trial;
      end
    end
    return root;
  endfunction

endpackage
`default_nettype wire
