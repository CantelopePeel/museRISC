// museRISC in-house core: IEEE-754 binary32/binary64 FPU (F+D).
//
// Correctness-first combinational unit: every arithmetic op
// produces a wide-window (256-bit) normalized significand plus
// a sticky summary of everything below the window, and a
// single shared round-and-pack stage applies the rounding
// mode, subnormal handling, and flag rules (tininess after
// rounding). NaN results are always the canonical quiet NaN,
// as RISC-V requires. Division and square root use wide
// integer operators — right for simulation and as a golden
// reference; a synthesis-friendly iterative unit can replace
// them behind the same interface later.
//
// Op encoding (op_i): see FPU_* constants. fmt_d_i selects
// binary64 (1) vs binary32 (0). Operands are raw 64-bit
// register contents: binary32 values are read from the low
// 32 bits with the NaN-box check applied (improperly boxed =
// canonical NaN); results for binary32 are NaN-boxed.

module muserisc_fpu (
    input  logic [4:0]  op_i,
    input  logic        fmt_d_i,
    input  logic [2:0]  rm_i,        // resolved rounding mode
    input  logic [63:0] a_i,         // rs1 (fp value or int bits)
    input  logic [63:0] b_i,         // rs2
    input  logic [63:0] c_i,         // rs3 (FMA addend)
    input  logic [1:0]  aux_i,       // sgnj/min-max/cmp select, cvt int size
    output logic [63:0] result_o,    // fp result (boxed) or int result
    output logic [4:0]  flags_o      // NV DZ OF UF NX
);

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

  // Per-format parameters
  logic [6:0]  p;            // precision incl. hidden bit
  logic signed [15:0] emax, emin, bias;
  logic [63:0] canon_nan, pos_inf;
  always_comb begin
    if (fmt_d_i) begin
      p = 7'd53; emax = 16'sd1023; emin = -16'sd1022; bias = 16'sd1023;
      canon_nan = 64'h7FF8_0000_0000_0000;
      pos_inf   = 64'h7FF0_0000_0000_0000;
    end else begin
      p = 7'd24; emax = 16'sd127; emin = -16'sd126; bias = 16'sd127;
      canon_nan = 64'hFFFF_FFFF_7FC0_0000;
      pos_inf   = 64'hFFFF_FFFF_7F80_0000;
    end
  end

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
        // normalized; normalize into the hidden bit.
        e = d ? -16'sd1022 : -16'sd126;
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

  unpacked_t ua, ub, uc;
  always_comb begin
    ua = unpack(a_i, fmt_d_i);
    ub = unpack(b_i, fmt_d_i);
    uc = unpack(c_i, fmt_d_i);
  end

  // ---------------------------------------------------------
  // Shared round-and-pack.
  // in: rp_sign, rp_exp (exponent of the 1.xxx form; value =
  // (rp_sig / 2^255) * 2^rp_exp with rp_sig[255]=1), rp_sticky
  // ---------------------------------------------------------
  logic        rp_sign, rp_sticky, rp_zero;
  logic signed [15:0] rp_exp;
  logic [255:0] rp_sig;
  logic [63:0] rp_result;
  logic [4:0]  rp_flags;

  /* verilator lint_off UNUSEDSIGNAL */
  always_comb begin
    logic signed [15:0] e;
    logic [15:0] shift, total_shift;
    logic [255:0] kept_wide, dropped_mask;
    logic [63:0] kept;
    logic guard, sticky, inexact, round_up;
    logic [63:0] fracbits;
    logic signed [15:0] efield;

    rp_flags = 5'b0;
    if (rp_zero) begin
      rp_result = fmt_d_i ? {rp_sign, 63'b0}
                          : {32'hFFFF_FFFF, rp_sign, 31'b0};
    end else begin
      e = rp_exp;
      // subnormal right-shift amount
      shift = 16'd0;
      if (e < emin) shift = 16'(emin - e);
      total_shift = (16'd256 - {9'b0, p}) + shift;
      if (total_shift > 16'd256) begin
        kept = 64'b0;
        guard = 1'b0;
        sticky = (rp_sig != 0) | rp_sticky;
      end else if (total_shift == 16'd256) begin
        // everything drops; the MSB is the guard (half-ulp) bit
        kept = 64'b0;
        guard = rp_sig[255];
        sticky = (rp_sig[254:0] != 0) | rp_sticky;
      end else begin
        kept_wide = rp_sig >> total_shift[7:0];
        kept = kept_wide[63:0];
        guard = rp_sig[total_shift[7:0] - 8'd1];
        // sticky = any dropped bit strictly below the guard
        dropped_mask = (total_shift >= 16'd2) ?
            ((256'b1 << (total_shift[7:0] - 8'd1)) - 256'b1) : 256'b0;
        sticky = (rp_sticky != 1'b0) |
                 ((rp_sig & dropped_mask) != 0);
      end
      inexact = guard | sticky;
      unique case (rm_i)
        3'b000:  round_up = guard & (sticky | kept[0]);   // RNE
        3'b001:  round_up = 1'b0;                          // RTZ
        3'b010:  round_up = rp_sign & inexact;             // RDN
        3'b011:  round_up = ~rp_sign & inexact;            // RUP
        3'b100:  round_up = guard;                         // RMM
        default: round_up = 1'b0;
      endcase
      kept = kept + {63'b0, round_up};
      // rounding promoted into the next binade
      if (kept >= (64'b1 << p[5:0])) begin
        kept = kept >> 1;
        e = e + 16'sd1;
      end else if (shift != 0 && kept >= (64'b1 << (p[5:0]-6'd1))) begin
        // promoted from subnormal to min normal: exp = emin
        e = emin;
      end
      if (inexact) rp_flags[0] = 1'b1;                     // NX
      // underflow: inexact and the (rounded) result is tiny
      if (inexact && (kept < (64'b1 << (p[5:0]-6'd1))))
        rp_flags[1] = 1'b1;                                // UF
      if (e > emax) begin
        rp_flags[2] = 1'b1;                                // OF
        rp_flags[0] = 1'b1;                                // NX
        // overflow result per rm
        unique case (rm_i)
          3'b001: rp_result = fmt_d_i ? {rp_sign, 11'h7FE, 52'hF_FFFF_FFFF_FFFF}
                                      : {32'hFFFF_FFFF, rp_sign, 8'hFE, 23'h7F_FFFF};
          3'b010: rp_result = rp_sign ? (fmt_d_i ? {1'b1, pos_inf[62:0]} : {32'hFFFF_FFFF, 1'b1, 31'h7F80_0000})
                                      : (fmt_d_i ? {1'b0, 11'h7FE, 52'hF_FFFF_FFFF_FFFF} : {32'hFFFF_FFFF, 1'b0, 8'hFE, 23'h7F_FFFF});
          3'b011: rp_result = rp_sign ? (fmt_d_i ? {1'b1, 11'h7FE, 52'hF_FFFF_FFFF_FFFF} : {32'hFFFF_FFFF, 1'b1, 8'hFE, 23'h7F_FFFF})
                                      : (fmt_d_i ? pos_inf : {32'hFFFF_FFFF, 1'b0, 31'h7F80_0000});
          default: rp_result = fmt_d_i ? {rp_sign, pos_inf[62:0]}
                                       : {32'hFFFF_FFFF, rp_sign, 8'hFF, 23'b0};
        endcase
      end else if (kept < (64'b1 << (p[5:0]-6'd1))) begin
        // subnormal or zero: exponent field 0, frac = kept
        fracbits = kept;
        rp_result = fmt_d_i ? {rp_sign, 11'b0, fracbits[51:0]}
                            : {32'hFFFF_FFFF, rp_sign, 8'b0, fracbits[22:0]};
      end else begin
        efield = e + bias;
        fracbits = kept - (64'b1 << (p[5:0]-6'd1));
        rp_result = fmt_d_i ? {rp_sign, efield[10:0], fracbits[51:0]}
                            : {32'hFFFF_FFFF, rp_sign, efield[7:0],
                               fracbits[22:0]};
      end
    end
  end

  // ---------------------------------------------------------
  // Operation dispatch
  // ---------------------------------------------------------
  unpacked_t uas;   // A unpacked as the *other* format (F2F)
  always_comb uas = unpack(a_i, ~fmt_d_i);

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

  logic        use_rp;        // result comes from round-pack
  logic [63:0] direct_result;
  logic [4:0]  op_flags;

  always_comb begin
    logic sb_sign, sp_sign, sc_sign;
    logic [255:0] wa, wb, wc, wbig, wsmall, mag;
    logic signed [15:0] frame_e, dsh;
    logic big_is_a, eff_sub;
    logic [105:0] prod;
    logic [255:0] wprod;
    logic signed [15:0] prod_e;
    logic [255:0] dvd, quot, rema;
    logic [255:0] radic, sq_rem;
    logic [127:0] sq_root;
    logic signed [15:0] t;
    logic [8:0]  lz;
    logic [63:0] imag;
    logic abig, blt, beq;
    logic [9:0]  class_bits;
    logic signed [15:0] shamt;
    logic [255:0] f2i_win;
    logic [127:0] f2i_ipart, f2i_lim_pos, f2i_lim_neg;
    logic f2i_guard, f2i_sticky, f2i_inexact, f2i_round, f2i_ovf;
    logic [63:0] i2f_iv, i2f_m;

    sb_sign = 1'b0; sp_sign = 1'b0; sc_sign = 1'b0;
    wa = 0; wb = 0; wc = 0; wbig = 0; wsmall = 0; mag = 0;
    frame_e = 0; dsh = 0; big_is_a = 0; eff_sub = 0;
    prod = 0; wprod = 0; prod_e = 0;
    dvd = 0; quot = 0; rema = 0; radic = 0; sq_rem = 0;
    sq_root = 0; t = 0; lz = 0; imag = 0;
    abig = 0; blt = 0; beq = 0; class_bits = 0; shamt = 0;
    f2i_win = 0; f2i_ipart = 0; f2i_lim_pos = 0; f2i_lim_neg = 0;
    f2i_guard = 0; f2i_sticky = 0; f2i_inexact = 0;
    f2i_round = 0; f2i_ovf = 0; i2f_iv = 0; i2f_m = 0;
    use_rp = 1'b1;
    direct_result = 64'b0;
    op_flags = 5'b0;
    rp_sign = 1'b0;
    rp_exp = 16'sd0;
    rp_sig = 256'b0;
    rp_sticky = 1'b0;
    rp_zero = 1'b0;

    unique case (op_i)
      FPU_ADD, FPU_SUB: begin
        sb_sign = ub.sign ^ (op_i == FPU_SUB);
        if (ua.is_nan || ub.is_nan) begin
          use_rp = 1'b0; direct_result = canon_nan;
          op_flags[4] = ua.is_snan | ub.is_snan;
        end else if (ua.is_inf || ub.is_inf) begin
          use_rp = 1'b0;
          if (ua.is_inf && ub.is_inf && (ua.sign != sb_sign)) begin
            direct_result = canon_nan; op_flags[4] = 1'b1;
          end else begin
            rp_sign = ua.is_inf ? ua.sign : sb_sign;
            direct_result = fmt_d_i ? {rp_sign, pos_inf[62:0]}
                                    : {32'hFFFF_FFFF, rp_sign, 8'hFF, 23'b0};
          end
        end else if (ua.is_zero && ub.is_zero) begin
          use_rp = 1'b0;
          rp_sign = (ua.sign == sb_sign) ? ua.sign : (rm_i == 3'b010);
          direct_result = fmt_d_i ? {rp_sign, 63'b0}
                                  : {32'hFFFF_FFFF, rp_sign, 31'b0};
        end else begin
          wa = to_window(ua.sig, p);
          wb = to_window(ub.sig, p);
          big_is_a = (ua.exp > ub.exp) ||
                     ((ua.exp == ub.exp) && (wa >= wb));
          eff_sub = (ua.sign != sb_sign);
          if (big_is_a) begin
            wbig = wa; frame_e = ua.exp; rp_sign = ua.sign;
            dsh = ua.exp - ub.exp;
            wsmall = (dsh >= 16'sd256) ? 256'b0 : (wb >> dsh[7:0]);
            if ((dsh >= 16'sd256 && wb != 0) ||
                (dsh < 16'sd256 && dsh > 0 &&
                 ((wb << (16'sd256 - dsh)) != 0)))
              wsmall[0] = 1'b1;   // jam
          end else begin
            wbig = wb; frame_e = ub.exp; rp_sign = sb_sign;
            dsh = ub.exp - ua.exp;
            wsmall = (dsh >= 16'sd256) ? 256'b0 : (wa >> dsh[7:0]);
            if ((dsh >= 16'sd256 && wa != 0) ||
                (dsh < 16'sd256 && dsh > 0 &&
                 ((wa << (16'sd256 - dsh)) != 0)))
              wsmall[0] = 1'b1;
          end
          if (!eff_sub) begin
            {lz[0], mag} = {1'b0, wbig} + {1'b0, wsmall};
            if (lz[0]) begin
              rp_sig = {1'b1, mag[255:1]}; rp_sig[0] |= mag[0];
              rp_exp = frame_e + 16'sd1;
            end else begin
              rp_sig = mag; rp_exp = frame_e;
            end
          end else begin
            mag = wbig - wsmall;
            if (mag == 0) begin
              rp_zero = 1'b1;
              rp_sign = (rm_i == 3'b010);
            end else begin
              lz = clz256(mag);
              rp_sig = mag << lz[7:0];
              rp_exp = frame_e - 16'(lz);
            end
          end
        end
      end

      FPU_MUL: begin
        rp_sign = ua.sign ^ ub.sign;
        if (ua.is_nan || ub.is_nan ||
            (ua.is_zero && ub.is_inf) || (ua.is_inf && ub.is_zero)) begin
          use_rp = 1'b0; direct_result = canon_nan;
          if (ua.is_nan || ub.is_nan)
            op_flags[4] = ua.is_snan | ub.is_snan;
          else
            op_flags[4] = 1'b1;
        end else if (ua.is_inf || ub.is_inf) begin
          use_rp = 1'b0;
          direct_result = fmt_d_i ? {rp_sign, pos_inf[62:0]}
                                  : {32'hFFFF_FFFF, rp_sign, 8'hFF, 23'b0};
        end else if (ua.is_zero || ub.is_zero) begin
          rp_zero = 1'b1;
        end else begin
          prod = 106'(ua.sig) * 106'(ub.sig);
          wprod = {prod, 150'b0};   // prod bit105 -> bit255
          prod_e = ua.exp + ub.exp -
                   16'(2 * {9'b0, p}) + 16'sd2 + 16'sd105;
          lz = clz256(wprod);
          rp_sig = wprod << lz[7:0];
          rp_exp = prod_e - 16'(lz);
        end
      end

      FPU_DIV: begin
        rp_sign = ua.sign ^ ub.sign;
        if (ua.is_nan || ub.is_nan ||
            (ua.is_zero && ub.is_zero) || (ua.is_inf && ub.is_inf)) begin
          use_rp = 1'b0; direct_result = canon_nan;
          if ((ua.is_zero && ub.is_zero) || (ua.is_inf && ub.is_inf))
            op_flags[4] = 1'b1;
          else
            op_flags[4] = ua.is_snan | ub.is_snan;
        end else if (ua.is_inf || ub.is_zero) begin
          use_rp = 1'b0;
          direct_result = fmt_d_i ? {rp_sign, pos_inf[62:0]}
                                  : {32'hFFFF_FFFF, rp_sign, 8'hFF, 23'b0};
          if (ub.is_zero && !ua.is_inf) op_flags[3] = 1'b1;  // DZ
        end else if (ub.is_inf || ua.is_zero) begin
          rp_zero = 1'b1;
        end else begin
          dvd = 256'(ua.sig) << (8'(p) + 8'd70);
          quot = dvd / 256'(ub.sig);
          rema = dvd % 256'(ub.sig);
          rp_sticky = (rema != 0);
          wprod = quot << (8'd185 - 8'(p));
          lz = clz256(wprod);
          rp_sig = wprod << lz[7:0];
          rp_exp = ua.exp - ub.exp - 16'(lz);
        end
      end

      FPU_SQRT: begin
        rp_sign = ua.sign;
        if (ua.is_nan || (ua.sign && !ua.is_zero)) begin
          use_rp = 1'b0; direct_result = canon_nan;
          if (ua.is_nan)
            op_flags[4] = ua.is_snan;
          else
            op_flags[4] = 1'b1;
        end else if (ua.is_inf) begin
          use_rp = 1'b0;
          direct_result = pos_inf;
        end else if (ua.is_zero) begin
          rp_zero = 1'b1;
        end else begin
          t = ua.exp - 16'({9'b0, p} - 16'd1);
          shamt = 16'd140 + (t[0] ? 16'd1 : 16'd0);
          radic = 256'(ua.sig) << shamt[7:0];
          sq_root = isqrt(radic);
          sq_rem = radic - 256'(sq_root) * 256'(sq_root);
          rp_sticky = (sq_rem != 0);
          wprod = 256'(sq_root) << 158;
          lz = clz256(wprod);
          rp_sig = wprod << lz[7:0];
          // (separate statement: keep the divide in a signed
          // context — one unsigned operand would poison it)
          frame_e = (t - shamt) / 16'sd2;
          rp_exp = frame_e + 16'sd97 - 16'(lz);
        end
      end

      FPU_FMA, FPU_FMS, FPU_FNMS, FPU_FNMA: begin
        sp_sign = ua.sign ^ ub.sign ^
                  (op_i == FPU_FNMS || op_i == FPU_FNMA);
        sc_sign = uc.sign ^ (op_i == FPU_FMS || op_i == FPU_FNMA);
        if (ua.is_nan || ub.is_nan || uc.is_nan ||
            (ua.is_zero && ub.is_inf) || (ua.is_inf && ub.is_zero)) begin
          use_rp = 1'b0; direct_result = canon_nan;
          op_flags[4] = ua.is_snan | ub.is_snan | uc.is_snan |
                        (ua.is_zero && ub.is_inf) |
                        (ua.is_inf && ub.is_zero);
        end else if ((ua.is_inf || ub.is_inf) && uc.is_inf &&
                     (sp_sign != sc_sign)) begin
          use_rp = 1'b0; direct_result = canon_nan; op_flags[4] = 1'b1;
        end else if (ua.is_inf || ub.is_inf) begin
          use_rp = 1'b0;
          direct_result = fmt_d_i ? {sp_sign, pos_inf[62:0]}
                                  : {32'hFFFF_FFFF, sp_sign, 8'hFF, 23'b0};
        end else if (uc.is_inf) begin
          use_rp = 1'b0;
          direct_result = fmt_d_i ? {sc_sign, pos_inf[62:0]}
                                  : {32'hFFFF_FFFF, sc_sign, 8'hFF, 23'b0};
        end else begin
          prod = 106'(ua.sig) * 106'(ub.sig);
          wprod = {prod, 150'b0};
          prod_e = ua.exp + ub.exp - 16'(2 * {9'b0, p}) +
                   16'sd2 + 16'sd105;
          wc = to_window(uc.sig, p);
          // frame = max(prod_e, uc.exp); shift other right w/ jam
          if (prod_e >= uc.exp) begin
            frame_e = prod_e;
            dsh = prod_e - uc.exp;
            wsmall = (dsh >= 16'sd256) ? 256'b0 : (wc >> dsh[7:0]);
            if ((dsh >= 16'sd256 && wc != 0) ||
                (dsh < 16'sd256 && dsh > 0 &&
                 ((wc << (16'sd256 - dsh)) != 0)))
              wsmall[0] = 1'b1;
            wbig = wprod;
            abig = 1'b1;   // big window is the product
          end else begin
            frame_e = uc.exp;
            dsh = uc.exp - prod_e;
            wsmall = (dsh >= 16'sd256) ? 256'b0 : (wprod >> dsh[7:0]);
            if ((dsh >= 16'sd256 && wprod != 0) ||
                (dsh < 16'sd256 && dsh > 0 &&
                 ((wprod << (16'sd256 - dsh)) != 0)))
              wsmall[0] = 1'b1;
            wbig = wc;
            abig = 1'b0;
          end
          eff_sub = (sp_sign != sc_sign);
          if (!eff_sub) begin
            rp_sign = sp_sign;
            {lz[0], mag} = {1'b0, wbig} + {1'b0, wsmall};
            if (lz[0]) begin
              rp_sig = {1'b1, mag[255:1]}; rp_sig[0] |= mag[0];
              rp_exp = frame_e + 16'sd1;
            end else if (mag == 0) begin
              rp_zero = 1'b1;
              rp_sign = sp_sign & sc_sign;
            end else begin
              lz = clz256(mag);
              rp_sig = mag << lz[7:0];
              rp_exp = frame_e - 16'(lz);
            end
          end else begin
            // magnitude order inside the frame
            if (wbig >= wsmall) begin
              mag = wbig - wsmall;
              rp_sign = abig ? sp_sign : sc_sign;
            end else begin
              mag = wsmall - wbig;
              rp_sign = abig ? sc_sign : sp_sign;
            end
            if (mag == 0) begin
              rp_zero = 1'b1;
              rp_sign = (rm_i == 3'b010);
            end else begin
              lz = clz256(mag);
              rp_sig = mag << lz[7:0];
              rp_exp = frame_e - 16'(lz);
            end
          end
        end
      end

      FPU_SGNJ: begin
        use_rp = 1'b0;
        if (fmt_d_i) begin
          direct_result = ua.raw;
          direct_result[63] = (aux_i == 2'd0) ? ub.sign :
                              (aux_i == 2'd1) ? ~ub.sign :
                                                (ua.sign ^ ub.sign);
        end else begin
          direct_result = {32'hFFFF_FFFF, ua.raw[31:0]};
          direct_result[31] = (aux_i == 2'd0) ? ub.sign :
                              (aux_i == 2'd1) ? ~ub.sign :
                                                (ua.sign ^ ub.sign);
        end
      end

      FPU_MINMAX: begin
        use_rp = 1'b0;
        op_flags[4] = ua.is_snan | ub.is_snan;
        if (ua.is_nan && ub.is_nan)      direct_result = canon_nan;
        else if (ua.is_nan)              direct_result = ub.raw;
        else if (ub.is_nan)              direct_result = ua.raw;
        else if (ua.is_zero && ub.is_zero) begin
          rp_sign = (aux_i == 2'd0) ? (ua.sign | ub.sign)
                                    : (ua.sign & ub.sign);
          direct_result = fmt_d_i ? {rp_sign, 63'b0}
                                  : {32'hFFFF_FFFF, rp_sign, 31'b0};
        end else begin
          if (ua.sign != ub.sign) blt = ua.sign;
          else if (ua.exp != ub.exp)
            blt = ua.sign ? (ua.exp > ub.exp) : (ua.exp < ub.exp);
          else
            blt = ua.sign ? (ua.sig > ub.sig) : (ua.sig < ub.sig);
          direct_result = ((aux_i == 2'd0) == blt) ? ua.raw : ub.raw;
        end
      end

      FPU_CMP: begin
        use_rp = 1'b0;
        direct_result = 64'b0;
        if (ua.is_nan || ub.is_nan) begin
          op_flags[4] = (aux_i == 2'd2) ? (ua.is_snan | ub.is_snan)
                                        : 1'b1;
        end else begin
          if (ua.is_zero && ub.is_zero) begin
            blt = 1'b0; beq = 1'b1;
          end else if (ua.sign != ub.sign) begin
            blt = ua.sign; beq = 1'b0;
          end else if (ua.exp != ub.exp) begin
            blt = ua.sign ? (ua.exp > ub.exp) : (ua.exp < ub.exp);
            beq = 1'b0;
          end else begin
            blt = ua.sign ? (ua.sig > ub.sig) : (ua.sig < ub.sig);
            beq = (ua.sig == ub.sig);
          end
          direct_result[0] = (aux_i == 2'd2) ? beq :
                             (aux_i == 2'd1) ? blt : (blt | beq);
        end
      end

      FPU_CLASS: begin
        use_rp = 1'b0;
        class_bits = 10'b0;
        if (ua.is_inf)            class_bits[ua.sign ? 0 : 7] = 1'b1;
        else if (ua.is_nan)       class_bits[ua.is_snan ? 8 : 9] = 1'b1;
        else if (ua.is_zero)      class_bits[ua.sign ? 3 : 4] = 1'b1;
        else if (ua.is_sub)       class_bits[ua.sign ? 2 : 5] = 1'b1;
        else                      class_bits[ua.sign ? 1 : 6] = 1'b1;
        direct_result = {54'b0, class_bits};
      end

      FPU_F2I: begin
        use_rp = 1'b0;
        if (ua.is_nan) begin
          op_flags[4] = 1'b1;
          unique case (aux_i)
            2'd0: direct_result = 64'h0000_0000_7FFF_FFFF;
            2'd1: direct_result = 64'hFFFF_FFFF_FFFF_FFFF;
            2'd2: direct_result = 64'h7FFF_FFFF_FFFF_FFFF;
            2'd3: direct_result = 64'hFFFF_FFFF_FFFF_FFFF;
          endcase
        end else begin
          f2i_win = to_window(ua.sig, p);
          if (ua.is_zero) begin
            f2i_ipart = 0; f2i_guard = 0; f2i_sticky = 0;
          end else if (ua.exp >= 16'sd64) begin
            f2i_ipart = {128{1'b1}}; f2i_guard = 0; f2i_sticky = 0;
          end else if (ua.exp >= 16'sd0) begin
            f2i_ipart = 128'(f2i_win >> (16'sd255 - ua.exp));
            f2i_guard = f2i_win[8'(16'sd254 - ua.exp)];
            f2i_sticky = (ua.exp < 16'sd254) &&
                ((f2i_win & ((256'b1 << (16'sd254 - ua.exp)) - 1)) != 0);
          end else if (ua.exp < 16'sd0) begin
            f2i_ipart = 0;
            f2i_guard = (ua.exp == -16'sd1) ? f2i_win[255] : 1'b0;
            f2i_sticky = ua.is_inf ? 1'b0 :
                      ((ua.exp == -16'sd1) ? (f2i_win[254:0] != 0)
                                           : (f2i_win != 0));
          end else begin
            f2i_ipart = {128{1'b1}}; f2i_guard = 0; f2i_sticky = 0;
          end
          f2i_inexact = f2i_guard | f2i_sticky;
          unique case (rm_i)
            3'b000: f2i_round = f2i_guard & (f2i_sticky | f2i_ipart[0]);
            3'b001: f2i_round = 1'b0;
            3'b010: f2i_round = ua.sign & f2i_inexact;
            3'b011: f2i_round = ~ua.sign & f2i_inexact;
            3'b100: f2i_round = f2i_guard;
            default: f2i_round = 1'b0;
          endcase
          f2i_ipart = f2i_ipart + {127'b0, f2i_round};
          unique case (aux_i)
            2'd0: begin f2i_lim_pos = 128'h7FFF_FFFF; f2i_lim_neg = 128'h8000_0000; end
            2'd1: begin f2i_lim_pos = 128'hFFFF_FFFF; f2i_lim_neg = 128'd0; end
            2'd2: begin f2i_lim_pos = 128'h7FFF_FFFF_FFFF_FFFF; f2i_lim_neg = 128'h8000_0000_0000_0000; end
            2'd3: begin f2i_lim_pos = 128'hFFFF_FFFF_FFFF_FFFF; f2i_lim_neg = 128'd0; end
          endcase
          if (ua.sign) f2i_ovf = (f2i_ipart > f2i_lim_neg);
          else         f2i_ovf = (f2i_ipart > f2i_lim_pos);
          if (aux_i[0] && ua.sign && f2i_ipart != 0) f2i_ovf = 1'b1;
          if (f2i_ovf) begin
            op_flags[4] = 1'b1;
            unique case (aux_i)
              2'd0: direct_result = ua.sign ? 64'hFFFF_FFFF_8000_0000
                                            : 64'h0000_0000_7FFF_FFFF;
              2'd1: direct_result = ua.sign ? 64'b0
                                            : 64'hFFFF_FFFF_FFFF_FFFF;
              2'd2: direct_result = ua.sign ? 64'h8000_0000_0000_0000
                                            : 64'h7FFF_FFFF_FFFF_FFFF;
              2'd3: direct_result = ua.sign ? 64'b0 : 64'hFFFF_FFFF_FFFF_FFFF;
            endcase
          end else begin
            if (f2i_inexact) op_flags[0] = 1'b1;
            imag = f2i_ipart[63:0];
            if (ua.sign) imag = -imag;
            if (aux_i == 2'd0 || aux_i == 2'd1)
              direct_result = {{32{imag[31]}}, imag[31:0]};
            else
              direct_result = imag;
          end
        end
      end

      FPU_I2F: begin
        unique case (aux_i)
          2'd0: i2f_iv = {{32{a_i[31]}}, a_i[31:0]};
          2'd1: i2f_iv = {32'b0, a_i[31:0]};
          2'd2: i2f_iv = a_i;
          2'd3: i2f_iv = a_i;
        endcase
        rp_sign = ((aux_i == 2'd0) || (aux_i == 2'd2)) && i2f_iv[63];
        i2f_m = rp_sign ? (64'b0 - i2f_iv) : i2f_iv;
        if (i2f_m == 0) begin
          rp_zero = 1'b1; rp_sign = 1'b0;
        end else begin
          lz = clz256({192'b0, i2f_m});
          rp_sig = {192'b0, i2f_m} << lz[7:0];
          rp_exp = 16'sd63 - (16'(lz) - 16'sd192);
        end
      end

      FPU_F2F: begin
        rp_sign = uas.sign;
        if (uas.is_nan) begin
          use_rp = 1'b0; direct_result = canon_nan;
          op_flags[4] = uas.is_snan;
        end else if (uas.is_inf) begin
          use_rp = 1'b0;
          direct_result = fmt_d_i ? {uas.sign, pos_inf[62:0]}
                                  : {32'hFFFF_FFFF, uas.sign, 8'hFF, 23'b0};
        end else if (uas.is_zero) begin
          rp_zero = 1'b1;
        end else begin
          rp_sig = to_window(uas.sig, fmt_d_i ? 7'd24 : 7'd53);
          rp_exp = uas.exp;
        end
      end

      FPU_MVXF: begin
        use_rp = 1'b0;
        direct_result = fmt_d_i ? a_i
                                : {32'hFFFF_FFFF, a_i[31:0]};
      end

      FPU_MVFX: begin
        use_rp = 1'b0;
        direct_result = fmt_d_i ? a_i
                                : {{32{a_i[31]}}, a_i[31:0]};
      end

      default: begin
        use_rp = 1'b0;
        direct_result = 64'b0;
      end
    endcase
  end

  assign result_o = use_rp ? rp_result : direct_result;
  assign flags_o = op_flags | (use_rp ? rp_flags : 5'b0);

endmodule
