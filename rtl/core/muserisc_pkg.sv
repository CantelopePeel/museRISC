// Shared types for the in-house RV64 core (issue #18, stage 1).
`default_nettype none
package muserisc_pkg;

  // Package constants are consumed selectively per module (e.g. the
  // ALU needs none of the trap causes), so unused-parameter lint is
  // off for the whole package.
  /* verilator lint_off UNUSEDPARAM */
  localparam int unsigned XLEN = 64;

  // ALU operations. Word (W-variant) behavior is selected separately.
  typedef enum logic [3:0] {
    ALU_ADD,
    ALU_SUB,
    ALU_SLL,
    ALU_SLT,
    ALU_SLTU,
    ALU_XOR,
    ALU_SRL,
    ALU_SRA,
    ALU_OR,
    ALU_AND,
    ALU_COPY_B  // result = operand B (LUI)
  } alu_op_e;

  // Decoder output consumed by the datapath. One struct so stage 2
  // can register it verbatim between decode and execute.
  typedef struct packed {
    logic    vec;          // any vector instruction (incl. vset)
    logic    vec_rd;       // destination is a vector register group
    logic    vset;         // vsetvli/vsetivli/vsetvl (form in fpu_aux)
    logic [5:0] bext_op;   // B/crypto op; vector op (VOP_*) if vec
    logic    bext;         // result comes from the B/crypto unit
    logic [4:0] fpu_op;    // FPU operation (muserisc_fpu FPU_*)
    logic [1:0] fpu_aux;   // sgnj/min-max/cmp, cvt size; vec form if vec
    logic    fmt_d;        // FP format: 1=binary64, 0=binary32
    logic    fp_op;        // result comes from the FPU in EX
    logic    fp_rm;        // op consumes a rounding mode
    logic    fp_rd;        // destination is an FP register
    logic    fp_rs1;       // rs1 read from the FP regfile
    logic    fp_rs2;       // rs2 read from the FP regfile
    logic    fp;           // any FP instruction (FS must be > 0)
    logic [4:0] amo_op;    // AMO funct5 (instr[31:27])
    logic    sc;           // store-conditional (result = success flag)
    logic    lr;           // load-reserved (sets the reservation)
    logic    amo;          // atomic RMW (funct5 in amo_op)
    logic    hlv;          // HLV/HLVX/HSV guest-memory access
    logic    hlvx;         // HLVX (execute-permission load)
    logic    hfence;       // HFENCE.VVMA/GVMA (full TLB flush here)
    logic    hfence_gvma;  // GVMA variant (TVM legality differs)
    logic    sfence;       // SFENCE.VMA (serializing; flushes TLBs)
    logic    wfi;          // WFI (executes as NOP unless TW traps it)
    logic    sret;         // SRET
    logic    mret;         // MRET
    logic    csr_imm;      // CSR source is the 5-bit zero-extended rs1 field
    logic    csr;          // CSR read/write instruction (funct3 selects op)
    logic    muldiv;       // result comes from the M unit (funct3 selects)
    logic    valid;        // legal instruction in the implemented subset
    logic    reg_write;    // write rd at end of cycle
    logic    mem_read;     // load: rd takes loaded data
    logic    mem_write;    // store: byte enables from funct3
    logic    alu_src_imm;  // ALU operand B is the immediate
    logic    alu_a_pc;     // ALU operand A is the PC (AUIPC)
    logic    word_op;      // 32-bit W-variant semantics in the ALU
    alu_op_e alu_op;
    logic    branch;       // conditional branch, condition in funct3
    logic    jal;
    logic    jalr;
    logic    ecall;
    logic    ebreak;
    logic [2:0] funct3;    // branch condition / load-store size+sign
  } ctrl_t;

  // mcause values the stage-1 core can raise.
  localparam logic [63:0] CAUSE_ILLEGAL_INSTR = 64'd2;
  localparam logic [63:0] CAUSE_BREAKPOINT    = 64'd3;
  localparam logic [63:0] CAUSE_LOAD_MISALIGN = 64'd4;
  localparam logic [63:0] CAUSE_STORE_MISALIGN = 64'd6;
  localparam logic [63:0] CAUSE_ECALL_M       = 64'd11;

  // Vector unit operations (stage 8, carried in bext_op) and
  // operand forms (carried in fpu_aux). VLEN/ELEN are fixed
  // for the in-house core's first vector configuration.
  localparam int unsigned VLEN = 512;
  localparam int unsigned ELEN = 64;
  localparam logic [5:0] VOP_ADD  = 6'd0;
  localparam logic [5:0] VOP_SUB  = 6'd1;
  localparam logic [5:0] VOP_RSUB = 6'd2;
  localparam logic [5:0] VOP_AND  = 6'd3;
  localparam logic [5:0] VOP_OR   = 6'd4;
  localparam logic [5:0] VOP_XOR  = 6'd5;
  localparam logic [5:0] VOP_SLL  = 6'd6;
  localparam logic [5:0] VOP_SRL  = 6'd7;
  localparam logic [5:0] VOP_SRA  = 6'd8;
  localparam logic [5:0] VOP_MV   = 6'd9;   // vmv.v.v/.x/.i
  localparam logic [5:0] VOP_MVSX = 6'd10;  // vmv.s.x
  localparam logic [5:0] VOP_MVXS = 6'd11;  // vmv.x.s
  localparam logic [1:0] VFORM_VV = 2'd0;
  localparam logic [1:0] VFORM_VX = 2'd1;
  localparam logic [1:0] VFORM_VI = 2'd2;
  /* verilator lint_on UNUSEDPARAM */

endpackage
`default_nettype wire
