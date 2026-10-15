// museRISC in-house core: element helpers for muserisc_vec
// (issue #27). Extracted verbatim from muserisc_vec.sv;
// no behavior change.
`default_nettype none
package muserisc_vec_pkg;

  // Element extraction at width code w (width = 8<<w, w<=3).
  function automatic logic [63:0] get_el(
      input logic [4095:0] grp, input int idx, input logic [2:0] w);
    logic [11:0] base;
    base = 12'(idx << (w + 3));
    unique case (w)
      3'd0: get_el = {56'd0, grp[base +: 8]};
      3'd1: get_el = {48'd0, grp[base +: 16]};
      3'd2: get_el = {32'd0, grp[base +: 32]};
      default: get_el = grp[base +: 64];
    endcase
  endfunction

  function automatic logic [63:0] sext_el(
      input logic [63:0] v, input logic [2:0] w);
    unique case (w)
      3'd0: sext_el = {{56{v[7]}}, v[7:0]};
      3'd1: sext_el = {{48{v[15]}}, v[15:0]};
      3'd2: sext_el = {{32{v[31]}}, v[31:0]};
      default: sext_el = v;
    endcase
  endfunction

  function automatic logic [4095:0] put_el(
      input logic [4095:0] grp, input int idx, input logic [2:0] w,
      input logic [63:0] v);
    put_el = grp;
    unique case (w)
      3'd0: put_el[idx*8 +: 8] = v[7:0];
      3'd1: put_el[idx*16 +: 16] = v[15:0];
      3'd2: put_el[idx*32 +: 32] = v[31:0];
      default: put_el[idx*64 +: 64] = v;
    endcase
  endfunction

  // Rounding shift-right of a 128-bit value by s (fixed-point
  // vxrm rules): 00 rnu, 01 rne, 10 rdn (truncate), 11 rod.
  function automatic logic [127:0] rnd_shift(
      input logic [127:0] v, input int s, input logic arith,
      input logic [1:0] rm);
    logic [127:0] q, disc, half_v;
    logic inc;
    if (s == 0) begin
      rnd_shift = v;
    end else begin
      q = arith ? 128'(signed'(v) >>> s) : (v >> s);
      disc = v & ((128'd1 << s) - 128'd1);
      half_v = 128'd1 << (s - 1);
      inc = 1'b0;
      unique case (rm)
        2'b00: inc = disc >= half_v;
        2'b01: inc = (disc > half_v) || ((disc == half_v) && q[0]);
        2'b11: q = q | {127'd0, (disc != 128'd0)};
        default: ;
      endcase
      rnd_shift = q + {127'd0, inc};
    end
  endfunction

  // Saturating clamp to a signed width-2^w range.
  function automatic logic [63:0] sat_s(
      input logic signed [127:0] v, input logic [2:0] w,
      output logic sat);
    logic signed [127:0] hi, lo;
    int bits;
    bits = 8 << w;
    hi = (128'sd1 << (bits - 1)) - 128'sd1;
    lo = -(128'sd1 << (bits - 1));
    sat = (v > hi) || (v < lo);
    sat_s = (v > hi) ? hi[63:0] : (v < lo) ? lo[63:0] : v[63:0];
  endfunction

  function automatic logic [63:0] sat_u(
      input logic [127:0] v, input logic [2:0] w,
      output logic sat);
    logic [127:0] hi;
    int bits;
    bits = 8 << w;
    hi = (128'd1 << bits) - 128'd1;
    sat = v > hi;
    sat_u = sat ? hi[63:0] : v[63:0];
  endfunction

endpackage
`default_nettype wire
