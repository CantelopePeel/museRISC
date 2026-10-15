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

  // 7-bit estimate tables for vfrec7/vfrsqrt7 (the RVV
  // spec tables; values extracted exhaustively from the
  // Sail reference with an exponent/fraction sweep probe
  // and checked over ~10.8k operand/result pairs).
  function automatic logic [6:0] rec7_tab(input logic [6:0] i);
    unique case (i)
      7'd0: rec7_tab = 7'h7f; 7'd1: rec7_tab = 7'h7d; 7'd2: rec7_tab = 7'h7b; 7'd3: rec7_tab = 7'h79; 7'd4: rec7_tab = 7'h77; 7'd5: rec7_tab = 7'h75; 7'd6: rec7_tab = 7'h74; 7'd7: rec7_tab = 7'h72;
      7'd8: rec7_tab = 7'h70; 7'd9: rec7_tab = 7'h6e; 7'd10: rec7_tab = 7'h6d; 7'd11: rec7_tab = 7'h6b; 7'd12: rec7_tab = 7'h69; 7'd13: rec7_tab = 7'h68; 7'd14: rec7_tab = 7'h66; 7'd15: rec7_tab = 7'h64;
      7'd16: rec7_tab = 7'h63; 7'd17: rec7_tab = 7'h61; 7'd18: rec7_tab = 7'h60; 7'd19: rec7_tab = 7'h5e; 7'd20: rec7_tab = 7'h5d; 7'd21: rec7_tab = 7'h5b; 7'd22: rec7_tab = 7'h5a; 7'd23: rec7_tab = 7'h58;
      7'd24: rec7_tab = 7'h57; 7'd25: rec7_tab = 7'h55; 7'd26: rec7_tab = 7'h54; 7'd27: rec7_tab = 7'h53; 7'd28: rec7_tab = 7'h51; 7'd29: rec7_tab = 7'h50; 7'd30: rec7_tab = 7'h4f; 7'd31: rec7_tab = 7'h4d;
      7'd32: rec7_tab = 7'h4c; 7'd33: rec7_tab = 7'h4b; 7'd34: rec7_tab = 7'h4a; 7'd35: rec7_tab = 7'h48; 7'd36: rec7_tab = 7'h47; 7'd37: rec7_tab = 7'h46; 7'd38: rec7_tab = 7'h45; 7'd39: rec7_tab = 7'h44;
      7'd40: rec7_tab = 7'h42; 7'd41: rec7_tab = 7'h41; 7'd42: rec7_tab = 7'h40; 7'd43: rec7_tab = 7'h3f; 7'd44: rec7_tab = 7'h3e; 7'd45: rec7_tab = 7'h3d; 7'd46: rec7_tab = 7'h3c; 7'd47: rec7_tab = 7'h3b;
      7'd48: rec7_tab = 7'h3a; 7'd49: rec7_tab = 7'h39; 7'd50: rec7_tab = 7'h38; 7'd51: rec7_tab = 7'h37; 7'd52: rec7_tab = 7'h36; 7'd53: rec7_tab = 7'h35; 7'd54: rec7_tab = 7'h34; 7'd55: rec7_tab = 7'h33;
      7'd56: rec7_tab = 7'h32; 7'd57: rec7_tab = 7'h31; 7'd58: rec7_tab = 7'h30; 7'd59: rec7_tab = 7'h2f; 7'd60: rec7_tab = 7'h2e; 7'd61: rec7_tab = 7'h2d; 7'd62: rec7_tab = 7'h2c; 7'd63: rec7_tab = 7'h2b;
      7'd64: rec7_tab = 7'h2a; 7'd65: rec7_tab = 7'h29; 7'd66: rec7_tab = 7'h28; 7'd67: rec7_tab = 7'h28; 7'd68: rec7_tab = 7'h27; 7'd69: rec7_tab = 7'h26; 7'd70: rec7_tab = 7'h25; 7'd71: rec7_tab = 7'h24;
      7'd72: rec7_tab = 7'h23; 7'd73: rec7_tab = 7'h23; 7'd74: rec7_tab = 7'h22; 7'd75: rec7_tab = 7'h21; 7'd76: rec7_tab = 7'h20; 7'd77: rec7_tab = 7'h1f; 7'd78: rec7_tab = 7'h1f; 7'd79: rec7_tab = 7'h1e;
      7'd80: rec7_tab = 7'h1d; 7'd81: rec7_tab = 7'h1c; 7'd82: rec7_tab = 7'h1c; 7'd83: rec7_tab = 7'h1b; 7'd84: rec7_tab = 7'h1a; 7'd85: rec7_tab = 7'h19; 7'd86: rec7_tab = 7'h19; 7'd87: rec7_tab = 7'h18;
      7'd88: rec7_tab = 7'h17; 7'd89: rec7_tab = 7'h17; 7'd90: rec7_tab = 7'h16; 7'd91: rec7_tab = 7'h15; 7'd92: rec7_tab = 7'h15; 7'd93: rec7_tab = 7'h14; 7'd94: rec7_tab = 7'h13; 7'd95: rec7_tab = 7'h13;
      7'd96: rec7_tab = 7'h12; 7'd97: rec7_tab = 7'h11; 7'd98: rec7_tab = 7'h11; 7'd99: rec7_tab = 7'h10; 7'd100: rec7_tab = 7'h0f; 7'd101: rec7_tab = 7'h0f; 7'd102: rec7_tab = 7'h0e; 7'd103: rec7_tab = 7'h0e;
      7'd104: rec7_tab = 7'h0d; 7'd105: rec7_tab = 7'h0c; 7'd106: rec7_tab = 7'h0c; 7'd107: rec7_tab = 7'h0b; 7'd108: rec7_tab = 7'h0b; 7'd109: rec7_tab = 7'h0a; 7'd110: rec7_tab = 7'h09; 7'd111: rec7_tab = 7'h09;
      7'd112: rec7_tab = 7'h08; 7'd113: rec7_tab = 7'h08; 7'd114: rec7_tab = 7'h07; 7'd115: rec7_tab = 7'h07; 7'd116: rec7_tab = 7'h06; 7'd117: rec7_tab = 7'h05; 7'd118: rec7_tab = 7'h05; 7'd119: rec7_tab = 7'h04;
      7'd120: rec7_tab = 7'h04; 7'd121: rec7_tab = 7'h03; 7'd122: rec7_tab = 7'h03; 7'd123: rec7_tab = 7'h02; 7'd124: rec7_tab = 7'h02; 7'd125: rec7_tab = 7'h01; 7'd126: rec7_tab = 7'h01; 7'd127: rec7_tab = 7'h00;
    endcase
  endfunction

  function automatic logic [6:0] rsqrt7_tab(
      input logic e_odd, input logic [6:0] i);
    unique case ({e_odd, i})
      8'd0: rsqrt7_tab = 7'h7f; 8'd1: rsqrt7_tab = 7'h7f; 8'd2: rsqrt7_tab = 7'h7d; 8'd3: rsqrt7_tab = 7'h7d;
      8'd4: rsqrt7_tab = 7'h7b; 8'd5: rsqrt7_tab = 7'h7b; 8'd6: rsqrt7_tab = 7'h79; 8'd7: rsqrt7_tab = 7'h79;
      8'd8: rsqrt7_tab = 7'h77; 8'd9: rsqrt7_tab = 7'h77; 8'd10: rsqrt7_tab = 7'h76; 8'd11: rsqrt7_tab = 7'h76;
      8'd12: rsqrt7_tab = 7'h74; 8'd13: rsqrt7_tab = 7'h74; 8'd14: rsqrt7_tab = 7'h72; 8'd15: rsqrt7_tab = 7'h72;
      8'd16: rsqrt7_tab = 7'h71; 8'd17: rsqrt7_tab = 7'h71; 8'd18: rsqrt7_tab = 7'h6f; 8'd19: rsqrt7_tab = 7'h6f;
      8'd20: rsqrt7_tab = 7'h6d; 8'd21: rsqrt7_tab = 7'h6d; 8'd22: rsqrt7_tab = 7'h6c; 8'd23: rsqrt7_tab = 7'h6c;
      8'd24: rsqrt7_tab = 7'h6a; 8'd25: rsqrt7_tab = 7'h6a; 8'd26: rsqrt7_tab = 7'h69; 8'd27: rsqrt7_tab = 7'h69;
      8'd28: rsqrt7_tab = 7'h67; 8'd29: rsqrt7_tab = 7'h67; 8'd30: rsqrt7_tab = 7'h66; 8'd31: rsqrt7_tab = 7'h66;
      8'd32: rsqrt7_tab = 7'h64; 8'd33: rsqrt7_tab = 7'h64; 8'd34: rsqrt7_tab = 7'h63; 8'd35: rsqrt7_tab = 7'h63;
      8'd36: rsqrt7_tab = 7'h61; 8'd37: rsqrt7_tab = 7'h61; 8'd38: rsqrt7_tab = 7'h60; 8'd39: rsqrt7_tab = 7'h60;
      8'd40: rsqrt7_tab = 7'h5f; 8'd41: rsqrt7_tab = 7'h5f; 8'd42: rsqrt7_tab = 7'h5d; 8'd43: rsqrt7_tab = 7'h5d;
      8'd44: rsqrt7_tab = 7'h5c; 8'd45: rsqrt7_tab = 7'h5c; 8'd46: rsqrt7_tab = 7'h5b; 8'd47: rsqrt7_tab = 7'h5b;
      8'd48: rsqrt7_tab = 7'h5a; 8'd49: rsqrt7_tab = 7'h5a; 8'd50: rsqrt7_tab = 7'h58; 8'd51: rsqrt7_tab = 7'h58;
      8'd52: rsqrt7_tab = 7'h57; 8'd53: rsqrt7_tab = 7'h57; 8'd54: rsqrt7_tab = 7'h56; 8'd55: rsqrt7_tab = 7'h56;
      8'd56: rsqrt7_tab = 7'h55; 8'd57: rsqrt7_tab = 7'h55; 8'd58: rsqrt7_tab = 7'h54; 8'd59: rsqrt7_tab = 7'h54;
      8'd60: rsqrt7_tab = 7'h53; 8'd61: rsqrt7_tab = 7'h53; 8'd62: rsqrt7_tab = 7'h52; 8'd63: rsqrt7_tab = 7'h52;
      8'd64: rsqrt7_tab = 7'h50; 8'd65: rsqrt7_tab = 7'h50; 8'd66: rsqrt7_tab = 7'h4f; 8'd67: rsqrt7_tab = 7'h4f;
      8'd68: rsqrt7_tab = 7'h4e; 8'd69: rsqrt7_tab = 7'h4e; 8'd70: rsqrt7_tab = 7'h4d; 8'd71: rsqrt7_tab = 7'h4d;
      8'd72: rsqrt7_tab = 7'h4c; 8'd73: rsqrt7_tab = 7'h4c; 8'd74: rsqrt7_tab = 7'h4b; 8'd75: rsqrt7_tab = 7'h4b;
      8'd76: rsqrt7_tab = 7'h4a; 8'd77: rsqrt7_tab = 7'h4a; 8'd78: rsqrt7_tab = 7'h49; 8'd79: rsqrt7_tab = 7'h49;
      8'd80: rsqrt7_tab = 7'h48; 8'd81: rsqrt7_tab = 7'h48; 8'd82: rsqrt7_tab = 7'h47; 8'd83: rsqrt7_tab = 7'h47;
      8'd84: rsqrt7_tab = 7'h46; 8'd85: rsqrt7_tab = 7'h46; 8'd86: rsqrt7_tab = 7'h46; 8'd87: rsqrt7_tab = 7'h46;
      8'd88: rsqrt7_tab = 7'h45; 8'd89: rsqrt7_tab = 7'h45; 8'd90: rsqrt7_tab = 7'h44; 8'd91: rsqrt7_tab = 7'h44;
      8'd92: rsqrt7_tab = 7'h43; 8'd93: rsqrt7_tab = 7'h43; 8'd94: rsqrt7_tab = 7'h42; 8'd95: rsqrt7_tab = 7'h42;
      8'd96: rsqrt7_tab = 7'h41; 8'd97: rsqrt7_tab = 7'h41; 8'd98: rsqrt7_tab = 7'h40; 8'd99: rsqrt7_tab = 7'h40;
      8'd100: rsqrt7_tab = 7'h3f; 8'd101: rsqrt7_tab = 7'h3f; 8'd102: rsqrt7_tab = 7'h3f; 8'd103: rsqrt7_tab = 7'h3f;
      8'd104: rsqrt7_tab = 7'h3e; 8'd105: rsqrt7_tab = 7'h3e; 8'd106: rsqrt7_tab = 7'h3d; 8'd107: rsqrt7_tab = 7'h3d;
      8'd108: rsqrt7_tab = 7'h3c; 8'd109: rsqrt7_tab = 7'h3c; 8'd110: rsqrt7_tab = 7'h3b; 8'd111: rsqrt7_tab = 7'h3b;
      8'd112: rsqrt7_tab = 7'h3b; 8'd113: rsqrt7_tab = 7'h3b; 8'd114: rsqrt7_tab = 7'h3a; 8'd115: rsqrt7_tab = 7'h3a;
      8'd116: rsqrt7_tab = 7'h39; 8'd117: rsqrt7_tab = 7'h39; 8'd118: rsqrt7_tab = 7'h38; 8'd119: rsqrt7_tab = 7'h38;
      8'd120: rsqrt7_tab = 7'h38; 8'd121: rsqrt7_tab = 7'h38; 8'd122: rsqrt7_tab = 7'h37; 8'd123: rsqrt7_tab = 7'h37;
      8'd124: rsqrt7_tab = 7'h36; 8'd125: rsqrt7_tab = 7'h36; 8'd126: rsqrt7_tab = 7'h35; 8'd127: rsqrt7_tab = 7'h35;
      8'd128: rsqrt7_tab = 7'h34; 8'd129: rsqrt7_tab = 7'h34; 8'd130: rsqrt7_tab = 7'h33; 8'd131: rsqrt7_tab = 7'h33;
      8'd132: rsqrt7_tab = 7'h32; 8'd133: rsqrt7_tab = 7'h32; 8'd134: rsqrt7_tab = 7'h30; 8'd135: rsqrt7_tab = 7'h30;
      8'd136: rsqrt7_tab = 7'h2f; 8'd137: rsqrt7_tab = 7'h2f; 8'd138: rsqrt7_tab = 7'h2e; 8'd139: rsqrt7_tab = 7'h2e;
      8'd140: rsqrt7_tab = 7'h2c; 8'd141: rsqrt7_tab = 7'h2c; 8'd142: rsqrt7_tab = 7'h2b; 8'd143: rsqrt7_tab = 7'h2b;
      8'd144: rsqrt7_tab = 7'h2a; 8'd145: rsqrt7_tab = 7'h2a; 8'd146: rsqrt7_tab = 7'h29; 8'd147: rsqrt7_tab = 7'h29;
      8'd148: rsqrt7_tab = 7'h28; 8'd149: rsqrt7_tab = 7'h28; 8'd150: rsqrt7_tab = 7'h27; 8'd151: rsqrt7_tab = 7'h27;
      8'd152: rsqrt7_tab = 7'h26; 8'd153: rsqrt7_tab = 7'h26; 8'd154: rsqrt7_tab = 7'h24; 8'd155: rsqrt7_tab = 7'h24;
      8'd156: rsqrt7_tab = 7'h23; 8'd157: rsqrt7_tab = 7'h23; 8'd158: rsqrt7_tab = 7'h22; 8'd159: rsqrt7_tab = 7'h22;
      8'd160: rsqrt7_tab = 7'h21; 8'd161: rsqrt7_tab = 7'h21; 8'd162: rsqrt7_tab = 7'h20; 8'd163: rsqrt7_tab = 7'h20;
      8'd164: rsqrt7_tab = 7'h1f; 8'd165: rsqrt7_tab = 7'h1f; 8'd166: rsqrt7_tab = 7'h1e; 8'd167: rsqrt7_tab = 7'h1e;
      8'd168: rsqrt7_tab = 7'h1e; 8'd169: rsqrt7_tab = 7'h1e; 8'd170: rsqrt7_tab = 7'h1d; 8'd171: rsqrt7_tab = 7'h1d;
      8'd172: rsqrt7_tab = 7'h1c; 8'd173: rsqrt7_tab = 7'h1c; 8'd174: rsqrt7_tab = 7'h1b; 8'd175: rsqrt7_tab = 7'h1b;
      8'd176: rsqrt7_tab = 7'h1a; 8'd177: rsqrt7_tab = 7'h1a; 8'd178: rsqrt7_tab = 7'h19; 8'd179: rsqrt7_tab = 7'h19;
      8'd180: rsqrt7_tab = 7'h18; 8'd181: rsqrt7_tab = 7'h18; 8'd182: rsqrt7_tab = 7'h17; 8'd183: rsqrt7_tab = 7'h17;
      8'd184: rsqrt7_tab = 7'h17; 8'd185: rsqrt7_tab = 7'h17; 8'd186: rsqrt7_tab = 7'h16; 8'd187: rsqrt7_tab = 7'h16;
      8'd188: rsqrt7_tab = 7'h15; 8'd189: rsqrt7_tab = 7'h15; 8'd190: rsqrt7_tab = 7'h14; 8'd191: rsqrt7_tab = 7'h14;
      8'd192: rsqrt7_tab = 7'h13; 8'd193: rsqrt7_tab = 7'h13; 8'd194: rsqrt7_tab = 7'h13; 8'd195: rsqrt7_tab = 7'h13;
      8'd196: rsqrt7_tab = 7'h12; 8'd197: rsqrt7_tab = 7'h12; 8'd198: rsqrt7_tab = 7'h11; 8'd199: rsqrt7_tab = 7'h11;
      8'd200: rsqrt7_tab = 7'h10; 8'd201: rsqrt7_tab = 7'h10; 8'd202: rsqrt7_tab = 7'h10; 8'd203: rsqrt7_tab = 7'h10;
      8'd204: rsqrt7_tab = 7'h0f; 8'd205: rsqrt7_tab = 7'h0f; 8'd206: rsqrt7_tab = 7'h0e; 8'd207: rsqrt7_tab = 7'h0e;
      8'd208: rsqrt7_tab = 7'h0e; 8'd209: rsqrt7_tab = 7'h0e; 8'd210: rsqrt7_tab = 7'h0d; 8'd211: rsqrt7_tab = 7'h0d;
      8'd212: rsqrt7_tab = 7'h0c; 8'd213: rsqrt7_tab = 7'h0c; 8'd214: rsqrt7_tab = 7'h0c; 8'd215: rsqrt7_tab = 7'h0c;
      8'd216: rsqrt7_tab = 7'h0b; 8'd217: rsqrt7_tab = 7'h0b; 8'd218: rsqrt7_tab = 7'h0a; 8'd219: rsqrt7_tab = 7'h0a;
      8'd220: rsqrt7_tab = 7'h0a; 8'd221: rsqrt7_tab = 7'h0a; 8'd222: rsqrt7_tab = 7'h09; 8'd223: rsqrt7_tab = 7'h09;
      8'd224: rsqrt7_tab = 7'h09; 8'd225: rsqrt7_tab = 7'h09; 8'd226: rsqrt7_tab = 7'h08; 8'd227: rsqrt7_tab = 7'h08;
      8'd228: rsqrt7_tab = 7'h07; 8'd229: rsqrt7_tab = 7'h07; 8'd230: rsqrt7_tab = 7'h07; 8'd231: rsqrt7_tab = 7'h07;
      8'd232: rsqrt7_tab = 7'h06; 8'd233: rsqrt7_tab = 7'h06; 8'd234: rsqrt7_tab = 7'h06; 8'd235: rsqrt7_tab = 7'h06;
      8'd236: rsqrt7_tab = 7'h05; 8'd237: rsqrt7_tab = 7'h05; 8'd238: rsqrt7_tab = 7'h04; 8'd239: rsqrt7_tab = 7'h04;
      8'd240: rsqrt7_tab = 7'h04; 8'd241: rsqrt7_tab = 7'h04; 8'd242: rsqrt7_tab = 7'h03; 8'd243: rsqrt7_tab = 7'h03;
      8'd244: rsqrt7_tab = 7'h03; 8'd245: rsqrt7_tab = 7'h03; 8'd246: rsqrt7_tab = 7'h02; 8'd247: rsqrt7_tab = 7'h02;
      8'd248: rsqrt7_tab = 7'h02; 8'd249: rsqrt7_tab = 7'h02; 8'd250: rsqrt7_tab = 7'h01; 8'd251: rsqrt7_tab = 7'h01;
      8'd252: rsqrt7_tab = 7'h01; 8'd253: rsqrt7_tab = 7'h01; 8'd254: rsqrt7_tab = 7'h00; 8'd255: rsqrt7_tab = 7'h00;
    endcase
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

  // ---------------------------------------------------------
  // Whole scalar-FP evaluation: one operation in, boxed
  // result + accrued flags out. Shared verbatim by
  // muserisc_fpu (scalar) and the vector unit (per
  // element), so both agree bit-for-bit.
  // ---------------------------------------------------------
  typedef struct {
    logic [63:0] result;  // fp result (boxed) or int result
    logic [4:0]  flags;   // NV DZ OF UF NX
  } fp_eval_result_t;

  // vfrec7 (rsqrt=0) / vfrsqrt7 (rsqrt=1) element estimate.
  // The operand is normalized through unpack(); the result
  // is assembled from the table fraction with no rounding
  // (and no UF/NX except reciprocal overflow, per Sail).
  function automatic fp_eval_result_t fp_estimate(
      input logic rsqrt, input logic d, input logic [2:0] rm,
      input logic [63:0] v);
    unpacked_t u;
    fp_eval_result_t r;
    logic signed [15:0] eo, emax, emin;
    logic [6:0] idx, f7;
    logic [63:0] canon, infv, zerov, maxv;
    logic [62:0] field;
    logic [7:0] sig8;
    begin
      u = unpack(v, d);
      emax = d ? 16'sd1023 : 16'sd127;
      emin = d ? -16'sd1022 : -16'sd126;
      canon = d ? 64'h7FF8_0000_0000_0000
                : 64'hFFFF_FFFF_7FC0_0000;
      infv = d ? {u.sign, 11'h7FF, 52'b0}
               : {32'hFFFF_FFFF, u.sign, 8'hFF, 23'b0};
      zerov = d ? {u.sign, 63'b0}
                : {32'hFFFF_FFFF, u.sign, 31'b0};
      maxv = d ? {u.sign, 11'h7FE, 52'hF_FFFF_FFFF_FFFF}
               : {32'hFFFF_FFFF, u.sign, 8'hFE, 23'h7F_FFFF};
      idx = d ? u.sig[51:45] : u.sig[22:16];
      r.flags = 5'b0;
      r.result = canon;
      if (u.is_nan) begin
        r.flags[4] = u.is_snan;  // NV
      end else if (rsqrt && u.sign && !u.is_zero) begin
        r.flags[4] = 1'b1;       // NV: rsqrt of negative
      end else if (u.is_inf) begin
        r.result = zerov;
      end else if (u.is_zero) begin
        r.result = infv;
        r.flags[3] = 1'b1;       // DZ
      end else begin
        if (rsqrt) begin
          f7 = rsqrt7_tab(u.exp[0], idx);
          eo = -(u.exp >>> 1) - 16'sd1;
        end else begin
          f7 = rec7_tab(idx);
          eo = -u.exp - 16'sd1;
        end
        sig8 = {1'b1, f7};
        if (eo > emax) begin
          // Reciprocal overflow follows the standard
          // rounding-mode overflow rule (inf vs max finite).
          r.result = ((rm == 3'b001) ||
                      ((rm == 3'b010) && !u.sign) ||
                      ((rm == 3'b011) && u.sign)) ? maxv : infv;
          r.flags[2] = 1'b1;     // OF
          r.flags[0] = 1'b1;     // NX
        end else if (eo >= emin) begin
          r.result = d ? {(rsqrt ? 1'b0 : u.sign),
                          11'(eo + 16'sd1023), f7, 45'b0}
                       : {32'hFFFF_FFFF, (rsqrt ? 1'b0 : u.sign),
                          8'(eo + 16'sd127), f7, 16'b0};
        end else begin
          // Subnormal result (reciprocal of large values):
          // 8 significand bits shifted right by emin - eo.
          field = {55'b0, sig8} <<
                  ((d ? 6'd45 : 6'd16) - 6'(emin - eo));
          r.result = d ? {(rsqrt ? 1'b0 : u.sign), field}
                       : {32'hFFFF_FFFF, (rsqrt ? 1'b0 : u.sign),
                          field[30:0]};
        end
      end
      return r;
    end
  endfunction


  function automatic fp_eval_result_t fp_eval(
      input logic [4:0]  op,
      input logic        fmt_d,
      input logic [2:0]  rm,
      input logic [63:0] a,
      input logic [63:0] b,
      input logic [63:0] c,
      input logic [1:0]  aux);
    logic [6:0]  p;
    logic signed [15:0] emax, emin, bias;
    logic [63:0] canon_nan, pos_inf;
    unpacked_t ua, ub, uc, uas;
    logic        rp_sign, rp_sticky, rp_zero;
    logic signed [15:0] rp_exp;
    logic [255:0] rp_sig;
    logic [63:0] rp_result;
    logic [4:0]  rp_flags;
    logic        use_rp;
    logic [63:0] direct_result;
    logic [4:0]  op_flags;
    fp_eval_result_t r;

    if (fmt_d) begin
      p = 7'd53; emax = 16'sd1023; emin = -16'sd1022; bias = 16'sd1023;
      canon_nan = 64'h7FF8_0000_0000_0000;
      pos_inf   = 64'h7FF0_0000_0000_0000;
    end else begin
      p = 7'd24; emax = 16'sd127; emin = -16'sd126; bias = 16'sd127;
      canon_nan = 64'hFFFF_FFFF_7FC0_0000;
      pos_inf   = 64'hFFFF_FFFF_7F80_0000;
    end
    ua = unpack(a, fmt_d);
    ub = unpack(b, fmt_d);
    uc = unpack(c, fmt_d);
    uas = unpack(a, ~fmt_d);  // other format (F2F)

    // Operation dispatch (sets rp_* or a direct result).
  begin
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

    unique case (op)
      FPU_ADD, FPU_SUB: begin
        sb_sign = ub.sign ^ (op == FPU_SUB);
        if (ua.is_nan || ub.is_nan) begin
          use_rp = 1'b0; direct_result = canon_nan;
          op_flags[4] = ua.is_snan | ub.is_snan;
        end else if (ua.is_inf || ub.is_inf) begin
          use_rp = 1'b0;
          if (ua.is_inf && ub.is_inf && (ua.sign != sb_sign)) begin
            direct_result = canon_nan; op_flags[4] = 1'b1;
          end else begin
            rp_sign = ua.is_inf ? ua.sign : sb_sign;
            direct_result = fmt_d ? {rp_sign, pos_inf[62:0]}
                                    : {32'hFFFF_FFFF, rp_sign, 8'hFF, 23'b0};
          end
        end else if (ua.is_zero && ub.is_zero) begin
          use_rp = 1'b0;
          rp_sign = (ua.sign == sb_sign) ? ua.sign : (rm == 3'b010);
          direct_result = fmt_d ? {rp_sign, 63'b0}
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
              rp_sign = (rm == 3'b010);
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
          direct_result = fmt_d ? {rp_sign, pos_inf[62:0]}
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
          direct_result = fmt_d ? {rp_sign, pos_inf[62:0]}
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
                  (op == FPU_FNMS || op == FPU_FNMA);
        sc_sign = uc.sign ^ (op == FPU_FMS || op == FPU_FNMA);
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
          direct_result = fmt_d ? {sp_sign, pos_inf[62:0]}
                                  : {32'hFFFF_FFFF, sp_sign, 8'hFF, 23'b0};
        end else if (uc.is_inf) begin
          use_rp = 1'b0;
          direct_result = fmt_d ? {sc_sign, pos_inf[62:0]}
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
              rp_sign = (rm == 3'b010);
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
        if (fmt_d) begin
          direct_result = ua.raw;
          direct_result[63] = (aux == 2'd0) ? ub.sign :
                              (aux == 2'd1) ? ~ub.sign :
                                                (ua.sign ^ ub.sign);
        end else begin
          direct_result = {32'hFFFF_FFFF, ua.raw[31:0]};
          direct_result[31] = (aux == 2'd0) ? ub.sign :
                              (aux == 2'd1) ? ~ub.sign :
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
          rp_sign = (aux == 2'd0) ? (ua.sign | ub.sign)
                                    : (ua.sign & ub.sign);
          direct_result = fmt_d ? {rp_sign, 63'b0}
                                  : {32'hFFFF_FFFF, rp_sign, 31'b0};
        end else begin
          if (ua.sign != ub.sign) blt = ua.sign;
          else if (ua.exp != ub.exp)
            blt = ua.sign ? (ua.exp > ub.exp) : (ua.exp < ub.exp);
          else
            blt = ua.sign ? (ua.sig > ub.sig) : (ua.sig < ub.sig);
          direct_result = ((aux == 2'd0) == blt) ? ua.raw : ub.raw;
        end
      end

      FPU_CMP: begin
        use_rp = 1'b0;
        direct_result = 64'b0;
        if (ua.is_nan || ub.is_nan) begin
          op_flags[4] = (aux == 2'd2) ? (ua.is_snan | ub.is_snan)
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
          direct_result[0] = (aux == 2'd2) ? beq :
                             (aux == 2'd1) ? blt : (blt | beq);
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
          unique case (aux)
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
          end
          f2i_inexact = f2i_guard | f2i_sticky;
          unique case (rm)
            3'b000: f2i_round = f2i_guard & (f2i_sticky | f2i_ipart[0]);
            3'b001: f2i_round = 1'b0;
            3'b010: f2i_round = ua.sign & f2i_inexact;
            3'b011: f2i_round = ~ua.sign & f2i_inexact;
            3'b100: f2i_round = f2i_guard;
            default: f2i_round = 1'b0;
          endcase
          f2i_ipart = f2i_ipart + {127'b0, f2i_round};
          unique case (aux)
            2'd0: begin f2i_lim_pos = 128'h7FFF_FFFF; f2i_lim_neg = 128'h8000_0000; end
            2'd1: begin f2i_lim_pos = 128'hFFFF_FFFF; f2i_lim_neg = 128'd0; end
            2'd2: begin f2i_lim_pos = 128'h7FFF_FFFF_FFFF_FFFF; f2i_lim_neg = 128'h8000_0000_0000_0000; end
            2'd3: begin f2i_lim_pos = 128'hFFFF_FFFF_FFFF_FFFF; f2i_lim_neg = 128'd0; end
          endcase
          if (ua.sign) f2i_ovf = (f2i_ipart > f2i_lim_neg);
          else         f2i_ovf = (f2i_ipart > f2i_lim_pos);
          if (aux[0] && ua.sign && f2i_ipart != 0) f2i_ovf = 1'b1;
          if (f2i_ovf) begin
            op_flags[4] = 1'b1;
            unique case (aux)
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
            if (aux == 2'd0 || aux == 2'd1)
              direct_result = {{32{imag[31]}}, imag[31:0]};
            else
              direct_result = imag;
          end
        end
      end

      FPU_I2F: begin
        unique case (aux)
          2'd0: i2f_iv = {{32{a[31]}}, a[31:0]};
          2'd1: i2f_iv = {32'b0, a[31:0]};
          2'd2: i2f_iv = a;
          2'd3: i2f_iv = a;
        endcase
        rp_sign = ((aux == 2'd0) || (aux == 2'd2)) && i2f_iv[63];
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
          direct_result = fmt_d ? {uas.sign, pos_inf[62:0]}
                                  : {32'hFFFF_FFFF, uas.sign, 8'hFF, 23'b0};
        end else if (uas.is_zero) begin
          rp_zero = 1'b1;
        end else begin
          rp_sig = to_window(uas.sig, fmt_d ? 7'd24 : 7'd53);
          rp_exp = uas.exp;
        end
      end

      FPU_MVXF: begin
        use_rp = 1'b0;
        direct_result = fmt_d ? a
                                : {32'hFFFF_FFFF, a[31:0]};
      end

      FPU_MVFX: begin
        use_rp = 1'b0;
        direct_result = fmt_d ? a
                                : {{32{a[31]}}, a[31:0]};
      end

      default: begin
        use_rp = 1'b0;
        direct_result = 64'b0;
      end
    endcase
  end

    // Shared round-and-pack.
    /* verilator lint_off UNUSEDSIGNAL */
  begin
    logic signed [15:0] e;
    logic [15:0] shift, total_shift;
    logic [255:0] kept_wide, dropped_mask;
    logic [63:0] kept;
    logic guard, sticky, inexact, round_up;
    logic [63:0] fracbits;
    logic signed [15:0] efield;

    rp_flags = 5'b0;
    if (rp_zero) begin
      rp_result = fmt_d ? {rp_sign, 63'b0}
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
      unique case (rm)
        3'b000:  round_up = guard & (sticky | kept[0]);   // RNE
        3'b001:  round_up = 1'b0;                          // RTZ
        3'b010:  round_up = rp_sign & inexact;             // RDN
        3'b011:  round_up = ~rp_sign & inexact;            // RUP
        3'b100:  round_up = guard;                         // RMM
        3'b101:  round_up = inexact & ~kept[0];            // ROD (vfncvt.rod)
        default: round_up = 1'b0;
      endcase
      // Tininess, Berkeley-style "after rounding" (matches
      // Sail): only values headed subnormal can be tiny. With
      // the significand kept to p+X bits (X=10 for D, 7 for
      // S, jammed), the value is tiny iff its exponent is at
      // least two binades down, or one binade down and adding
      // the rounding increment does not carry it to 2^emin.
      begin
        logic [6:0] xb;
        logic [63:0] sig_b, inc_b;
        xb = fmt_d ? 7'd10 : 7'd7;
        sig_b = 64'(rp_sig >> (8'd255 - (8'(p) + 8'(xb) - 8'd1)));
        if (rp_sticky ||
            ((rp_sig << (8'(p) + 8'(xb))) != 0))
          sig_b[0] = 1'b1;
        unique case (rm)
          3'b000, 3'b100: inc_b = 64'b1 << (xb - 7'd1);
          3'b010: inc_b = rp_sign ? ((64'b1 << xb) - 64'b1) : 64'b0;
          3'b011: inc_b = rp_sign ? 64'b0 : ((64'b1 << xb) - 64'b1);
          3'b101: inc_b = (64'b1 << xb) - 64'b1;  // ROD magnitude
          default: inc_b = 64'b0;
        endcase
        if (inexact && (e < emin) &&
            ((e < emin - 16'sd1) ||
             ((sig_b + inc_b) < (64'b1 << (p[5:0] + xb[5:0])))))
          rp_flags[1] = 1'b1;                              // UF
      end
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
      if (e > emax) begin
        rp_flags[2] = 1'b1;                                // OF
        rp_flags[0] = 1'b1;                                // NX
        // overflow result per rm
        unique case (rm)
          3'b001, 3'b101: rp_result = fmt_d ? {rp_sign, 11'h7FE, 52'hF_FFFF_FFFF_FFFF}
                                      : {32'hFFFF_FFFF, rp_sign, 8'hFE, 23'h7F_FFFF};
          3'b010: rp_result = rp_sign ? (fmt_d ? {1'b1, pos_inf[62:0]} : {32'hFFFF_FFFF, 1'b1, 31'h7F80_0000})
                                      : (fmt_d ? {1'b0, 11'h7FE, 52'hF_FFFF_FFFF_FFFF} : {32'hFFFF_FFFF, 1'b0, 8'hFE, 23'h7F_FFFF});
          3'b011: rp_result = rp_sign ? (fmt_d ? {1'b1, 11'h7FE, 52'hF_FFFF_FFFF_FFFF} : {32'hFFFF_FFFF, 1'b1, 8'hFE, 23'h7F_FFFF})
                                      : (fmt_d ? pos_inf : {32'hFFFF_FFFF, 1'b0, 31'h7F80_0000});
          default: rp_result = fmt_d ? {rp_sign, pos_inf[62:0]}
                                       : {32'hFFFF_FFFF, rp_sign, 8'hFF, 23'b0};
        endcase
      end else if (kept < (64'b1 << (p[5:0]-6'd1))) begin
        // subnormal or zero: exponent field 0, frac = kept
        fracbits = kept;
        rp_result = fmt_d ? {rp_sign, 11'b0, fracbits[51:0]}
                            : {32'hFFFF_FFFF, rp_sign, 8'b0, fracbits[22:0]};
      end else begin
        efield = e + bias;
        fracbits = kept - (64'b1 << (p[5:0]-6'd1));
        rp_result = fmt_d ? {rp_sign, efield[10:0], fracbits[51:0]}
                            : {32'hFFFF_FFFF, rp_sign, efield[7:0],
                               fracbits[22:0]};
      end
    end
  end
    /* verilator lint_on UNUSEDSIGNAL */

    r.result = use_rp ? rp_result : direct_result;
    r.flags = op_flags | (use_rp ? rp_flags : 5'b0);
    return r;
  endfunction

endpackage
`default_nettype wire
