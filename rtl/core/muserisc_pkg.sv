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
  /* verilator lint_on UNUSEDPARAM */

endpackage
`default_nettype wire
