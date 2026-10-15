// Combinational vector execution unit (issue #23): integer
// classes over full register groups (VLEN=512, ELEN=64),
// mirroring the FPU's combinational correctness-first style.
// Covers ALU/shift/min/max, mul/div/MAC, carry-in/out, merge,
// mask-producing compares and mask logicals, fixed-point
// saturating/averaging/shift-rounding (vxrm/vxsat), widening
// and narrowing, extends, reductions, slides, gather,
// compress, viota/vid, vmsbf/vmsof/vmsif, vcpop/vfirst, and
// whole-register moves. Prestart elements keep the old
// destination; tail/inactive elements follow vta/vma
// (agnostic = all-ones). Memory forms live in the core MEM
// sequencer; FP vector classes are not implemented.
`default_nettype none
module muserisc_vec
  import muserisc_pkg::*;
(
    input  wire [6:0]    op_i,       // VOP_*
    input  wire [1:0]    form_i,     // VFORM_* (VV/VX/VI)
    input  wire [2:0]    sew_i,      // vtype.vsew (SEW = 8<<sew)
    input  wire [63:0]   vl_i,
    input  wire [63:0]   vstart_i,
    input  wire [63:0]   vlmax_i,    // elements in a full group
    input  wire          vta_i,
    input  wire          vma_i,
    input  wire          vm_i,       // 1 = unmasked
    input  wire [511:0]  mask_i,     // v0 (bit i = element i)
    input  wire [4095:0] vs2_i,      // group at instr[24:20]
    input  wire [4095:0] vs1_i,      // group at instr[19:15] (VV)
    input  wire [4095:0] old_vd_i,
    input  wire [63:0]   scalar_i,   // rs1 value (VX)
    input  wire [63:0]   imm_i,      // imm5 / sub-operation
    input  wire [1:0]    vxrm_i,

    output logic [4095:0] result_o,  // new vd group
    output logic [63:0]   scalar_o,  // vmv.x.s / vcpop / vfirst
    output logic          sat_o      // an active element saturated
);

  // Agnostic policies behave as undisturbed in this
  // implementation (a spec-legal choice, matching the Sail
  // reference configuration), so vta_i/vma_i do not change
  // any result.
  wire unused_agnostic = vta_i ^ vma_i;

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

  // ---- Classification ----
  logic is_wide, is_narrow, is_mask_dest, unmasked_op;
  logic [2:0] dw;  // destination width code
  assign is_wide = ((op_i >= VOP_WADD) && (op_i <= VOP_WMACCUS)) ||
                   (op_i == VOP_WRED);
  assign is_narrow = (op_i >= VOP_NSRL) && (op_i <= VOP_NCLIPU);
  assign is_mask_dest = (op_i == VOP_MADC) || (op_i == VOP_MSBC) ||
      ((op_i >= VOP_CMPEQ) && (op_i <= VOP_CMPGT)) ||
      (op_i == VOP_MLOG) || (op_i == VOP_MSBIT);
  // Carry/merge forms take v0 as data, not as an enable mask.
  assign unmasked_op = (op_i == VOP_ADC) || (op_i == VOP_SBC) ||
                       (op_i == VOP_MERGE);
  assign dw = is_wide ? ((sew_i >= 3'd3) ? 3'd3 : (sew_i + 3'd1))
                      : sew_i;
  logic [2:0] aw;  // vs2 element width code for this op
  always_comb begin
    if (is_narrow || (op_i == VOP_WADDW) || (op_i == VOP_WADDUW) ||
        (op_i == VOP_WSUBW) || (op_i == VOP_WSUBUW)) begin
      aw = (sew_i >= 3'd3) ? 3'd3 : (sew_i + 3'd1);
    end else if (op_i == VOP_EXT) begin
      // imm[2:1]: 01=/8, 10=/4, 11=/2 (legality in the core).
      aw = sew_i - (3'd4 - {1'b0, imm_i[2:1]});
    end else begin
      aw = sew_i;
    end
  end

  // ---- Main dispatch ----
  always_comb begin
    logic [63:0] a, b, a_s, b_s, old_el, r, ones_v, ones_s;
    logic signed [127:0] prod, acc;
    logic [127:0] wide_v;
    logic [63:0] idx64, off64;
    logic [5:0] shamt, shamt_w;
    logic sat_i, active, bit_v, seen_v, src_act;
    int shamt_bits, iota_cnt, wp, src_idx;
    result_o = old_vd_i;
    sat_o = 1'b0;
    ones_s = (sew_i == 3'd3) ? 64'hffff_ffff_ffff_ffff :
             (sew_i == 3'd2) ? 64'h0000_0000_ffff_ffff :
             (sew_i == 3'd1) ? 64'h0000_0000_0000_ffff :
                               64'h0000_0000_0000_00ff;
    ones_v = (dw == 3'd3) ? 64'hffff_ffff_ffff_ffff :
             (dw == 3'd2) ? 64'h0000_0000_ffff_ffff :
             (dw == 3'd1) ? 64'h0000_0000_0000_ffff :
                            64'h0000_0000_0000_00ff;
    shamt_bits = 3 + int'(sew_i);  // log2(SEW)

    if (op_i == VOP_MVR) begin
      result_o = vs2_i;  // whole-register move: no vtype/vl
    end else if (op_i == VOP_COMPRESS) begin
      wp = (vstart_i > 64'd511) ? 512 : int'(vstart_i[9:0]);
      for (int i = 0; i < (512 >> sew_i); i++) begin
        if ((64'(unsigned'(i)) >= vstart_i) &&
            (64'(unsigned'(i)) < vl_i) && vs1_i[i]) begin
          if (wp < (512 >> sew_i)) begin
            result_o = put_el(result_o, wp, sew_i,
                              get_el(vs2_i, i, sew_i));
          end
          wp++;
        end
      end
    end else if (is_mask_dest) begin
      // Destination is a mask register: one bit per element.
      seen_v = 1'b0;
      for (int i = 0; i < 512; i++) begin
        a = (i < (512 >> sew_i)) ? get_el(vs2_i, i, sew_i) : 64'd0;
        b = (form_i == VFORM_VV)
            ? ((i < (512 >> sew_i)) ? get_el(vs1_i, i, sew_i) : 64'd0)
            : (form_i == VFORM_VX) ? scalar_i : imm_i;
        a_s = sext_el(a, sew_i);
        b_s = sext_el(b, sew_i);
        bit_v = 1'b0;
        src_act = (64'(unsigned'(i)) >= vstart_i) &&
                  (64'(unsigned'(i)) < vl_i) && (vm_i || mask_i[i]);
        unique case (op_i)
          VOP_CMPEQ: bit_v = (a & ones_v) == (b & ones_v);
          VOP_CMPNE: bit_v = (a & ones_v) != (b & ones_v);
          VOP_CMPLTU: bit_v = (a & ones_v) < (b & ones_v);
          VOP_CMPLT: bit_v = signed'(a_s) < signed'(b_s);
          VOP_CMPLEU: bit_v = (a & ones_v) <= (b & ones_v);
          VOP_CMPLE: bit_v = signed'(a_s) <= signed'(b_s);
          VOP_CMPGTU: bit_v = (a & ones_v) > (b & ones_v);
          VOP_CMPGT: bit_v = signed'(a_s) > signed'(b_s);
          VOP_MADC: begin
            wide_v = {64'd0, a & ones_v} + {64'd0, b & ones_v} +
                     {127'd0, (vm_i ? 1'b0 : mask_i[i])};
            bit_v = wide_v[8 << sew_i];
          end
          VOP_MSBC: begin
            wide_v = {64'd0, a & ones_v} - {64'd0, b & ones_v} -
                     {127'd0, (vm_i ? 1'b0 : mask_i[i])};
            bit_v = wide_v[127];
          end
          VOP_MLOG: begin
            unique case (imm_i[2:0])
              3'd0: bit_v = vs2_i[i] & ~vs1_i[i];   // vmandn
              3'd1: bit_v = vs2_i[i] & vs1_i[i];    // vmand
              3'd2: bit_v = vs2_i[i] | vs1_i[i];    // vmor
              3'd3: bit_v = vs2_i[i] ^ vs1_i[i];    // vmxor
              3'd4: bit_v = vs2_i[i] | ~vs1_i[i];   // vmorn
              3'd5: bit_v = ~(vs2_i[i] & vs1_i[i]);// vmnand
              3'd6: bit_v = ~(vs2_i[i] | vs1_i[i]);// vmnor
              default: bit_v = ~(vs2_i[i] ^ vs1_i[i]); // vmxnor
            endcase
          end
          default: begin  // VOP_MSBIT
            unique case (imm_i[1:0])
              2'd1: bit_v = !seen_v && !(src_act && vs2_i[i]); // vmsbf
              2'd2: bit_v = src_act && vs2_i[i] && !seen_v;    // vmsof
              default: bit_v = !seen_v;                        // vmsif
            endcase
          end
        endcase
        if (op_i == VOP_MSBIT) begin
          if (src_act) result_o[i] = bit_v;
          if (src_act && vs2_i[i]) seen_v = 1'b1;
        end else if ((op_i == VOP_MADC) || (op_i == VOP_MSBC) ||
                     (op_i == VOP_MLOG)) begin
          // No element masking for carry-out / mask logicals.
          if ((64'(unsigned'(i)) >= vstart_i) &&
              (64'(unsigned'(i)) < vl_i)) result_o[i] = bit_v;
        end else begin  // compares respect the v0 mask
          if (src_act) result_o[i] = bit_v;
        end
      end
    end else if (op_i == VOP_WRED) begin
      // Widening reduction sum into element 0 at 2*SEW; the
      // vs1 element 0 (already 2*SEW wide) seeds it.
      acc = signed'({64'd0, get_el(vs1_i, 0, dw)});
      for (int i = 0; i < (512 >> sew_i); i++) begin
        a = get_el(vs2_i, i, sew_i) & ones_s;
        if ((64'(unsigned'(i)) >= vstart_i) &&
            (64'(unsigned'(i)) < vl_i) && (vm_i || mask_i[i])) begin
          a_s = sext_el(a, sew_i);
          acc = acc + (imm_i[0]
                       ? signed'({{64{a_s[63]}}, a_s})
                       : signed'({64'd0, a}));
        end
      end
      if (vl_i != 64'd0) begin
        result_o = put_el(result_o, 0, dw, acc[63:0]);
      end
    end else if (op_i == VOP_RED) begin
      // Reduction into element 0; vs1 element 0 seeds it.
      acc = signed'({64'd0, get_el(vs1_i, 0, sew_i) & ones_v});
      for (int i = 0; i < (512 >> sew_i); i++) begin
        a = get_el(vs2_i, i, sew_i) & ones_v;
        if ((64'(unsigned'(i)) >= vstart_i) &&
            (64'(unsigned'(i)) < vl_i) && (vm_i || mask_i[i])) begin
          unique case (imm_i[2:0])
            3'd0: acc = acc + signed'({64'd0, a});
            3'd1: acc = acc & signed'({64'd0, a});
            3'd2: acc = acc | signed'({64'd0, a});
            3'd3: acc = acc ^ signed'({64'd0, a});
            3'd4: acc = (acc[63:0] & ones_v) < a ? acc
                                                 : signed'({64'd0, a});
            3'd5: acc = signed'(sext_el(acc[63:0], sew_i)) <
                        signed'(sext_el(a, sew_i))
                        ? acc : signed'({64'd0, a});
            3'd6: acc = (acc[63:0] & ones_v) > a ? acc
                                                 : signed'({64'd0, a});
            default: acc = signed'(sext_el(acc[63:0], sew_i)) >
                           signed'(sext_el(a, sew_i))
                           ? acc : signed'({64'd0, a});
          endcase
        end
      end
      if (vl_i != 64'd0) begin
        result_o = put_el(result_o, 0, sew_i, acc[63:0] & ones_v);
      end
    end else begin
      // Element-wise classes (incl. slides/gather/extends).
      iota_cnt = 0;
      off64 = (form_i == VFORM_VX) ? scalar_i : {59'd0, imm_i[4:0]};
      for (int i = 0; i < (512 >> dw); i++) begin
        a = get_el(vs2_i, i, aw);
        b = (form_i == VFORM_VV) ? get_el(vs1_i, i, sew_i) :
            (form_i == VFORM_VX) ? scalar_i : imm_i;
        a_s = sext_el(a, aw);
        b_s = sext_el(b, sew_i);
        old_el = get_el(old_vd_i, i, dw);
        // The VI shift amount is the zero-extended 5-bit
        // immediate (the decoder sign-extends imm5 for the
        // arithmetic forms).
        shamt = ((form_i == VFORM_VI) ? {1'b0, b[4:0]} : b[5:0]) &
                ((6'd1 << shamt_bits) - 6'd1);
        shamt_w = ((form_i == VFORM_VI) ? {1'b0, b[4:0]} : b[5:0]) &
                  ((6'd1 << (shamt_bits + 1)) - 6'd1);
        r = a;
        sat_i = 1'b0;
        unique case (op_i)
          VOP_ADD: r = a + b;
          VOP_SUB: r = a - b;
          VOP_RSUB: r = b - a;
          VOP_AND: r = a & b;
          VOP_OR: r = a | b;
          VOP_XOR: r = a ^ b;
          VOP_SLL: r = a << shamt;
          VOP_SRL: r = (a & ones_v) >> shamt;
          VOP_SRA: r = 64'(signed'(a_s) >>> shamt);
          VOP_MV: r = b;
          VOP_MVSX: r = scalar_i;
          VOP_MIN: r = signed'(a_s) < signed'(b_s) ? a : b;
          VOP_MINU: r = (a & ones_v) < (b & ones_v) ? a : b;
          VOP_MAX: r = signed'(a_s) > signed'(b_s) ? a : b;
          VOP_MAXU: r = (a & ones_v) > (b & ones_v) ? a : b;
          VOP_MUL: r = a * b;
          VOP_MULH: begin
            prod = signed'(a_s) * signed'(b_s);
            r = 64'(prod >> (8 << sew_i));
          end
          VOP_MULHU: begin
            wide_v = {64'd0, a & ones_s} * {64'd0, b & ones_s};
            r = 64'(wide_v >> (8 << sew_i));
          end
          VOP_MULHSU: begin
            prod = signed'(a_s) * signed'({64'd0, b & ones_v});
            r = 64'(prod >> (8 << sew_i));
          end
          VOP_MACC: r = old_el + a * b;
          VOP_MADD: r = b * old_el + a;
          VOP_NMSAC: r = old_el - a * b;
          VOP_NMSUB: r = a - b * old_el;
          VOP_DIV: begin
            if ((b & ones_v) == 64'd0) r = ones_v;
            else if ((sew_i == 3'd3) &&
                     (a_s == 64'h8000_0000_0000_0000) &&
                     (b_s == 64'hffff_ffff_ffff_ffff)) r = a_s;
            else r = 64'(signed'(a_s) / signed'(b_s));
          end
          VOP_DIVU: r = ((b & ones_v) == 64'd0) ? ones_v
                        : (a & ones_v) / (b & ones_v);
          VOP_REM: begin
            if ((b & ones_v) == 64'd0) r = a;
            else if ((sew_i == 3'd3) &&
                     (a_s == 64'h8000_0000_0000_0000) &&
                     (b_s == 64'hffff_ffff_ffff_ffff)) r = 64'd0;
            else r = 64'(signed'(a_s) % signed'(b_s));
          end
          VOP_REMU: r = ((b & ones_v) == 64'd0) ? a
                        : (a & ones_v) % (b & ones_v);
          VOP_ADC: r = a + b + {63'd0, mask_i[i]};
          VOP_SBC: r = a - b - {63'd0, mask_i[i]};
          VOP_MERGE: r = mask_i[i] ? b : a;
          VOP_SADD: r = sat_s(signed'({{64{a_s[63]}}, a_s}) +
                              signed'({{64{b_s[63]}}, b_s}), sew_i, sat_i);
          VOP_SADDU: r = sat_u({64'd0, a & ones_v} +
                               {64'd0, b & ones_v}, sew_i, sat_i);
          VOP_SSUB: r = sat_s(signed'({{64{a_s[63]}}, a_s}) -
                              signed'({{64{b_s[63]}}, b_s}), sew_i, sat_i);
          VOP_SSUBU: begin
            wide_v = {64'd0, a & ones_v} - {64'd0, b & ones_v};
            sat_i = wide_v[127];
            r = sat_i ? 64'd0 : wide_v[63:0];
          end
          VOP_AADD: begin
            prod = signed'({{64{a_s[63]}}, a_s}) +
                   signed'({{64{b_s[63]}}, b_s});
            wide_v = rnd_shift(128'(prod), 1, 1'b1, vxrm_i);
            r = wide_v[63:0];
          end
          VOP_AADDU: begin
            wide_v = rnd_shift(
                {64'd0, a & ones_v} + {64'd0, b & ones_v}, 1, 1'b0,
                vxrm_i);
            r = wide_v[63:0];
          end
          VOP_ASUB: begin
            prod = signed'({{64{a_s[63]}}, a_s}) -
                   signed'({{64{b_s[63]}}, b_s});
            wide_v = rnd_shift(128'(prod), 1, 1'b1, vxrm_i);
            r = wide_v[63:0];
          end
          VOP_ASUBU: begin
            wide_v = rnd_shift(
                {64'd0, a & ones_v} - {64'd0, b & ones_v}, 1, 1'b0,
                vxrm_i);
            r = wide_v[63:0];
          end
          VOP_SMUL: begin
            prod = signed'(a_s) * signed'(b_s);
            r = sat_s(signed'(rnd_shift(128'(prod), (8 << sew_i) - 1,
                                        1'b1, vxrm_i)),
                      sew_i, sat_i);
          end
          VOP_SSRL: begin
            wide_v = rnd_shift({64'd0, a & ones_v}, int'(shamt),
                               1'b0, vxrm_i);
            r = wide_v[63:0];
          end
          VOP_SSRA: begin
            wide_v = rnd_shift(128'(signed'(a_s)), int'(shamt),
                               1'b1, vxrm_i);
            r = wide_v[63:0];
          end
          VOP_WADD: r = a_s + b_s;
          VOP_WADDW: r = a_s + b_s;
          VOP_WSUB: r = a_s - b_s;
          VOP_WSUBW: r = a_s - b_s;
          VOP_WMUL: r = 64'(signed'(a_s) * signed'(b_s));
          VOP_WMULSU: r = 64'(signed'(a_s) *
                              signed'(b & ones_s));
          VOP_WMACC: r = old_el + 64'(signed'(a_s) * signed'(b_s));
          // For the macc forms the su/us suffix refers to
          // the assembly operands (vs1 field = b first):
          // su: signed(b) * unsigned(a); us: conversely.
          VOP_WMACCSU: r = old_el + 64'(signed'(b_s) *
                                        signed'(a & ones_s));
          VOP_WMACCUS: r = old_el + 64'(signed'(a_s) *
                                        signed'(b & ones_s));
          VOP_NSRL: r = a >> shamt_w;
          VOP_NSRA: r = 64'(signed'(a_s) >>> shamt_w);
          VOP_NCLIP: r = sat_s(signed'(rnd_shift(128'(signed'(a_s)),
                               int'(shamt_w), 1'b1, vxrm_i)),
                               sew_i, sat_i);
          VOP_NCLIPU: r = sat_u(rnd_shift({64'd0, a},
                                int'(shamt_w), 1'b0, vxrm_i),
                                sew_i, sat_i);
          VOP_EXT: r = imm_i[0] ? a_s : a;
          VOP_ID: r = 64'(unsigned'(i));
          VOP_IOTA: r = 64'(unsigned'(iota_cnt));
          VOP_GATHER: begin
            idx64 = (form_i == VFORM_VV) ? (b & ones_v) :
                    (form_i == VFORM_VX) ? scalar_i
                                         : {59'd0, imm_i[4:0]};
            r = (idx64 < vlmax_i)
                ? get_el(vs2_i, int'(idx64[9:0]), sew_i) : 64'd0;
          end
          VOP_GATHEREI16: begin
            idx64 = get_el(vs1_i, i, 3'd1) & 64'hffff;
            r = (idx64 < vlmax_i)
                ? get_el(vs2_i, int'(idx64[9:0]), sew_i) : 64'd0;
          end
          VOP_SLIDEUP: begin
            src_idx = (64'(unsigned'(i)) >= off64)
                      ? (i - int'(off64[9:0])) : 0;
            r = (64'(unsigned'(i)) >= off64)
                ? get_el(vs2_i, src_idx, sew_i) : old_el;
          end
          VOP_SLIDEDOWN: begin
            idx64 = 64'(unsigned'(i)) + off64;
            r = (idx64 < vlmax_i)
                ? get_el(vs2_i, int'(idx64[9:0]), sew_i) : 64'd0;
          end
          VOP_SLIDE1UP: r = (i == 0) ? scalar_i
                                     : get_el(vs2_i, i - 1, sew_i);
          VOP_SLIDE1DOWN: r = (64'(unsigned'(i)) + 64'd1 >= vl_i)
                              ? scalar_i : get_el(vs2_i, i + 1, sew_i);
          default: r = a;
        endcase
        // Widening unsigned forms zero-extend both sources;
        // handled by width masking of a (aw) and b below for
        // the .wv case where a is already at dest width.
        if ((op_i == VOP_WADDU) || (op_i == VOP_WADDUW)) begin
          r = a + (b & ones_s);
        end
        if ((op_i == VOP_WSUBU) || (op_i == VOP_WSUBUW)) begin
          r = a - (b & ones_s);
        end
        if (op_i == VOP_WMULU) r = (a & ones_s) * (b & ones_s);
        if (op_i == VOP_WMACCU) r = old_el + (a & ones_s) * (b & ones_s);

        active = (64'(unsigned'(i)) >= vstart_i) &&
                 (64'(unsigned'(i)) < vl_i) &&
                 (unmasked_op || vm_i || mask_i[i]);
        if ((op_i == VOP_SLIDEUP) &&
            (64'(unsigned'(i)) < off64) &&
            (64'(unsigned'(i)) < vl_i)) begin
          active = 1'b0;  // shifted-in region keeps old vd
        end
        if (sat_i && active) sat_o = 1'b1;
        if (op_i == VOP_IOTA) begin
          if ((64'(unsigned'(i)) >= vstart_i) &&
              (64'(unsigned'(i)) < vl_i) && (vm_i || mask_i[i]) &&
              vs2_i[i]) iota_cnt++;
        end
        if (op_i == VOP_MVXS || op_i == VOP_CPOP ||
            op_i == VOP_FIRST) begin
          // Scalar destination only; group result unused.
        end else if (op_i == VOP_MVSX) begin
          if ((i == 0) && (vstart_i == 64'd0) && (vl_i != 64'd0) &&
              (vm_i || mask_i[0])) begin
            result_o = put_el(result_o, 0, sew_i, r & ones_v);
          end
        end else if (64'(unsigned'(i)) >= vstart_i) begin
          // Inactive/tail elements keep the old destination
          // value under both undisturbed and agnostic
          // policies (agnostic = undisturbed, matching the
          // Sail reference configuration).
          if (active) begin
            result_o = put_el(result_o, i, dw, r & ones_v);
          end
        end
      end
    end
  end

  // Scalar results: vmv.x.s sign-extends element 0; vcpop
  // counts and vfirst finds active set bits in vs2.
  always_comb begin
    int cnt;
    logic [63:0] first_v;
    cnt = 0;
    first_v = 64'hffff_ffff_ffff_ffff;
    for (int i = 0; i < 512; i++) begin
      if ((64'(unsigned'(i)) >= vstart_i) &&
          (64'(unsigned'(i)) < vl_i) && (vm_i || mask_i[i]) &&
          vs2_i[i]) begin
        cnt++;
        if (first_v == 64'hffff_ffff_ffff_ffff) begin
          first_v = 64'(unsigned'(i));
        end
      end
    end
    unique case (op_i)
      VOP_CPOP: scalar_o = 64'(unsigned'(cnt));
      VOP_FIRST: scalar_o = first_v;
      default: scalar_o = sext_el(vs2_i[63:0], sew_i);
    endcase
  end

endmodule
`default_nettype wire
