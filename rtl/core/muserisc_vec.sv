// Combinational vector execution unit (issue #23, stage 8a):
// integer ALU and move classes over full register groups,
// mirroring the FPU's combinational correctness-first style.
// The loop covers the maximum element count (VLEN*8/8 = 512);
// prestart elements keep the old destination, tail/inactive
// elements follow vta/vma (agnostic = all-ones). Memory,
// widening, reduction, mask-logical and FP classes arrive in
// later substages behind this same group interface.
`default_nettype none
module muserisc_vec
  import muserisc_pkg::*;
(
    input  wire [5:0]    op_i,       // VOP_*
    input  wire [1:0]    form_i,     // VFORM_* (VV/VX/VI)
    input  wire [2:0]    sew_i,      // vtype.vsew (SEW = 8<<sew)
    input  wire [63:0]   vl_i,
    input  wire [63:0]   vstart_i,
    input  wire          vta_i,
    input  wire          vma_i,
    input  wire          vm_i,       // 1 = unmasked
    input  wire [511:0]  mask_i,     // v0 (bit i = element i)
    input  wire [4095:0] vs2_i,      // group at instr[24:20]
    input  wire [4095:0] vs1_i,      // group at instr[19:15] (VV)
    input  wire [4095:0] old_vd_i,
    input  wire [63:0]   scalar_i,   // rs1 value (VX)
    input  wire [63:0]   imm_i,      // sign-extended imm5 (VI)

    output logic [4095:0] result_o,  // new vd group
    output logic [63:0]   scalar_o   // vmv.x.s result
);

  // Element extraction at the current SEW. Indices are
  // computed in bits; callers guarantee sew_i <= 3.
  function automatic logic [63:0] get_el(
      input logic [4095:0] grp, input int idx, input logic [2:0] sew);
    logic [11:0] base;
    base = 12'(idx << (sew + 3));
    unique case (sew)
      3'd0: get_el = {56'd0, grp[base +: 8]};
      3'd1: get_el = {48'd0, grp[base +: 16]};
      3'd2: get_el = {32'd0, grp[base +: 32]};
      default: get_el = grp[base +: 64];
    endcase
  endfunction

  always_comb begin
    logic [63:0] a, b, r, ones;
    logic [5:0] shamt;
    logic active;
    int shamt_bits;
    result_o = old_vd_i;
    ones = (sew_i == 3'd3) ? 64'hffff_ffff_ffff_ffff :
           (sew_i == 3'd2) ? 64'h0000_0000_ffff_ffff :
           (sew_i == 3'd1) ? 64'h0000_0000_0000_ffff :
                             64'h0000_0000_0000_00ff;
    shamt_bits = 3 + int'(sew_i);  // log2(SEW)
    // Elements beyond 4096/SEW do not exist in the group;
    // part-selects there would be out of range.
    for (int i = 0; i < (512 >> sew_i); i++) begin
      a = get_el(vs2_i, i, sew_i);
      b = (form_i == VFORM_VV) ? get_el(vs1_i, i, sew_i) :
          (form_i == VFORM_VX) ? scalar_i : imm_i;
      shamt = b[5:0] & (6'd1 << shamt_bits) - 6'd1;
      unique case (op_i)
        VOP_ADD:  r = a + b;
        VOP_SUB:  r = a - b;
        VOP_RSUB: r = b - a;
        VOP_AND:  r = a & b;
        VOP_OR:   r = a | b;
        VOP_XOR:  r = a ^ b;
        VOP_SLL:  r = a << shamt;
        VOP_SRL:  r = (a & ones) >> shamt;
        VOP_SRA: begin
          // Arithmetic shift at SEW: sign-extend first.
          unique case (sew_i)
            3'd0: r = 64'(signed'(a[7:0]) >>> b[2:0]);
            3'd1: r = 64'(signed'(a[15:0]) >>> b[3:0]);
            3'd2: r = 64'(signed'(a[31:0]) >>> b[4:0]);
            default: r = 64'(signed'(a) >>> b[5:0]);
          endcase
        end
        VOP_MV:   r = (form_i == VFORM_VV) ? b : b;
        VOP_MVSX: r = scalar_i;
        default:  r = a;
      endcase
      r &= ones;
      active = (64'(unsigned'(i)) >= vstart_i) &&
               (64'(unsigned'(i)) < vl_i) && (vm_i || mask_i[i]);
      if (op_i == VOP_MVXS) begin
        // Scalar destination only; the group result is unused.
      end else if (op_i == VOP_MVSX) begin
        active = (i == 0) && (vstart_i == 64'd0) && (vl_i != 64'd0) &&
                 (vm_i || mask_i[0]);
        if (active) begin
          unique case (sew_i)
            3'd0: result_o[7:0] = r[7:0];
            3'd1: result_o[15:0] = r[15:0];
            3'd2: result_o[31:0] = r[31:0];
            default: result_o[63:0] = r;
          endcase
        end
      end else begin
        // Destination element: result, agnostic ones, or old.
        if (64'(unsigned'(i)) >= vstart_i) begin
          if (active) begin
            unique case (sew_i)
              3'd0: result_o[i*8 +: 8] = r[7:0];
              3'd1: result_o[i*16 +: 16] = r[15:0];
              3'd2: result_o[i*32 +: 32] = r[31:0];
              default: result_o[i*64 +: 64] = r;
            endcase
          end else if (64'(unsigned'(i)) >= vl_i) begin
            if (vta_i) begin
              unique case (sew_i)
                3'd0: result_o[i*8 +: 8] = 8'hff;
                3'd1: result_o[i*16 +: 16] = 16'hffff;
                3'd2: result_o[i*32 +: 32] = 32'hffff_ffff;
                default: result_o[i*64 +: 64] = 64'hffff_ffff_ffff_ffff;
              endcase
            end
          end else if (vma_i) begin
            unique case (sew_i)
              3'd0: result_o[i*8 +: 8] = 8'hff;
              3'd1: result_o[i*16 +: 16] = 16'hffff;
              3'd2: result_o[i*32 +: 32] = 32'hffff_ffff;
              default: result_o[i*64 +: 64] = 64'hffff_ffff_ffff_ffff;
            endcase
          end
        end
      end
    end
  end

  // vmv.x.s: element 0 of vs2, sign-extended from SEW.
  always_comb begin
    unique case (sew_i)
      3'd0: scalar_o = {{56{vs2_i[7]}}, vs2_i[7:0]};
      3'd1: scalar_o = {{48{vs2_i[15]}}, vs2_i[15:0]};
      3'd2: scalar_o = {{32{vs2_i[31]}}, vs2_i[31:0]};
      default: scalar_o = vs2_i[63:0];
    endcase
  end

endmodule
`default_nettype wire
