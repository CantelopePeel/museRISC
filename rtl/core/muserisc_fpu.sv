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
// Op encoding (op_i): see FPU_* constants in
// muserisc_fpu_pkg, which also holds the unpack type and
// helper functions. fmt_d_i selects
// binary64 (1) vs binary32 (0). Operands are raw 64-bit
// register contents: binary32 values are read from the low
// 32 bits with the NaN-box check applied (improperly boxed =
// canonical NaN); results for binary32 are NaN-boxed.

module muserisc_fpu import muserisc_fpu_pkg::*; (
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

  fp_eval_result_t eval_r;
  always_comb begin
    eval_r = fp_eval(op_i, fmt_d_i, rm_i, a_i, b_i, c_i, aux_i);
  end
  assign result_o = eval_r.result;
  assign flags_o = eval_r.flags;

endmodule
