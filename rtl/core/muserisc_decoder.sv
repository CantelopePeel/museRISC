// RV64I decoder (stage 1): full base integer set. FENCE* decode as
// NOPs; ECALL/EBREAK raise the corresponding trap in the core.
// Anything else (including all CSR instructions until stage 3) is
// marked illegal so the core traps instead of silently misexecuting.
`default_nettype none
module muserisc_decoder import muserisc_pkg::*; (
    input  wire [31:0]          instr_i,
    output muserisc_pkg::ctrl_t ctrl_o,
    output logic [63:0]         imm_o,
    output logic [4:0]          rs1_o,
    output logic [4:0]          rs2_o,
    output logic [4:0]          rd_o
);
  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;
  logic [63:0] imm_i, imm_s, imm_b, imm_u, imm_j;

  assign opcode = instr_i[6:0];
  assign funct3 = instr_i[14:12];
  assign funct7 = instr_i[31:25];
  assign rs1_o  = instr_i[19:15];
  assign rs2_o  = instr_i[24:20];
  assign rd_o   = instr_i[11:7];

  assign imm_i = {{52{instr_i[31]}}, instr_i[31:20]};
  assign imm_s = {{52{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
  assign imm_b = {{51{instr_i[31]}}, instr_i[31], instr_i[7],
                  instr_i[30:25], instr_i[11:8], 1'b0};
  assign imm_u = {{32{instr_i[31]}}, instr_i[31:12], 12'd0};
  assign imm_j = {{43{instr_i[31]}}, instr_i[31], instr_i[19:12],
                  instr_i[20], instr_i[30:21], 1'b0};

  // OP/OP-IMM ALU select from funct3 (+ funct7 for SUB/SRA).
  function automatic alu_op_e alu_decode(input logic [2:0] f3,
                                         input logic alt);
    unique case (f3)
      3'b000:  alu_decode = alt ? ALU_SUB : ALU_ADD;
      3'b001:  alu_decode = ALU_SLL;
      3'b010:  alu_decode = ALU_SLT;
      3'b011:  alu_decode = ALU_SLTU;
      3'b100:  alu_decode = ALU_XOR;
      3'b101:  alu_decode = alt ? ALU_SRA : ALU_SRL;
      3'b110:  alu_decode = ALU_OR;
      default: alu_decode = ALU_AND;
    endcase
  endfunction

  always_comb begin
    ctrl_o = '0;
    ctrl_o.alu_op = ALU_ADD;
    ctrl_o.funct3 = funct3;
    imm_o = imm_i;

    unique case (opcode)
      7'b0110111: begin  // LUI
        ctrl_o.valid = 1'b1;
        ctrl_o.reg_write = 1'b1;
        ctrl_o.alu_src_imm = 1'b1;
        ctrl_o.alu_op = ALU_COPY_B;
        imm_o = imm_u;
      end
      7'b0010111: begin  // AUIPC
        ctrl_o.valid = 1'b1;
        ctrl_o.reg_write = 1'b1;
        ctrl_o.alu_src_imm = 1'b1;
        ctrl_o.alu_a_pc = 1'b1;
        ctrl_o.alu_op = ALU_ADD;
        imm_o = imm_u;
      end
      7'b1101111: begin  // JAL
        ctrl_o.valid = 1'b1;
        ctrl_o.reg_write = 1'b1;
        ctrl_o.jal = 1'b1;
        imm_o = imm_j;
      end
      7'b1100111: begin  // JALR (funct3 must be 000)
        if (funct3 == 3'b000) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.reg_write = 1'b1;
          ctrl_o.jalr = 1'b1;
          imm_o = imm_i;
        end
      end
      7'b1100011: begin  // branches
        if ((funct3 != 3'b010) && (funct3 != 3'b011)) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.branch = 1'b1;
          imm_o = imm_b;
        end
      end
      7'b0000011: begin  // loads (funct3 000..110)
        if (funct3 != 3'b111) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.reg_write = 1'b1;
          ctrl_o.mem_read = 1'b1;
          ctrl_o.alu_src_imm = 1'b1;
          imm_o = imm_i;
        end
      end
      7'b0100011: begin  // stores (funct3 000..011)
        if (funct3[2] == 1'b0) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.mem_write = 1'b1;
          ctrl_o.alu_src_imm = 1'b1;
          imm_o = imm_s;
        end
      end
      7'b0010011: begin  // OP-IMM
        ctrl_o.valid = 1'b1;
        ctrl_o.reg_write = 1'b1;
        ctrl_o.alu_src_imm = 1'b1;
        // instr[30] is an immediate bit here, not a funct7 bit:
        // it selects SRAI vs SRLI only. In particular ADDI is
        // always ADD, even when the immediate is negative.
        ctrl_o.alu_op = alu_decode(funct3,
                                   (funct3 == 3'b101) ? instr_i[30] : 1'b0);
        imm_o = imm_i;
        // Shift encodings with reserved imm bits set are illegal.
        if ((funct3 == 3'b001) && (instr_i[31:26] != 6'b000000)) begin
          ctrl_o.valid = 1'b0;
        end
        if ((funct3 == 3'b101) && (instr_i[31:26] != 6'b000000) &&
            (instr_i[31:26] != 6'b010000)) begin
          ctrl_o.valid = 1'b0;
        end
      end
      7'b0110011: begin  // OP (register-register) and M (funct7=1)
        if ((funct7 == 7'b0000000) ||
            ((funct7 == 7'b0100000) &&
             ((funct3 == 3'b000) || (funct3 == 3'b101)))) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.reg_write = 1'b1;
          ctrl_o.alu_op = alu_decode(funct3, instr_i[30]);
        end else if (funct7 == 7'b0000001) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.reg_write = 1'b1;
          ctrl_o.muldiv = 1'b1;
        end
      end
      7'b0011011: begin  // OP-IMM-32
        ctrl_o.valid = 1'b1;
        ctrl_o.reg_write = 1'b1;
        ctrl_o.alu_src_imm = 1'b1;
        ctrl_o.word_op = 1'b1;
        // As OP-IMM: instr[30] is an immediate bit; ADDIW is ADD.
        ctrl_o.alu_op = alu_decode(funct3,
                                   (funct3 == 3'b101) ? instr_i[30] : 1'b0);
        imm_o = imm_i;
        if ((funct3 != 3'b000) && (funct3 != 3'b001) &&
            (funct3 != 3'b101)) begin
          ctrl_o.valid = 1'b0;
        end
        if ((funct3 == 3'b001) && (funct7 != 7'b0000000)) begin
          ctrl_o.valid = 1'b0;
        end
        if ((funct3 == 3'b101) && (funct7 != 7'b0000000) &&
            (funct7 != 7'b0100000)) begin
          ctrl_o.valid = 1'b0;
        end
      end
      7'b0111011: begin  // OP-32 and M W-variants (funct7=1)
        ctrl_o.word_op = 1'b1;
        ctrl_o.alu_op = alu_decode(funct3, instr_i[30]);
        if ((funct7 == 7'b0000000) &&
            ((funct3 == 3'b000) || (funct3 == 3'b001) ||
             (funct3 == 3'b101))) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.reg_write = 1'b1;
        end else if ((funct7 == 7'b0100000) &&
                     ((funct3 == 3'b000) || (funct3 == 3'b101))) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.reg_write = 1'b1;
        end else if ((funct7 == 7'b0000001) &&
                     ((funct3 == 3'b000) || (funct3[2] == 1'b1))) begin
          // MULW (000), DIVW (100), DIVUW (101), REMW (110), REMUW (111);
          // there are no MULHW-class encodings.
          ctrl_o.valid = 1'b1;
          ctrl_o.reg_write = 1'b1;
          ctrl_o.muldiv = 1'b1;
        end
      end
      7'b0001111: begin  // FENCE / FENCE.I: NOP in stage 1
        ctrl_o.valid = 1'b1;
      end
      7'b1110011: begin  // SYSTEM: only ECALL/EBREAK in stage 1
        if (funct3 == 3'b000) begin
          if (instr_i[31:20] == 12'd0) begin
            ctrl_o.valid = 1'b1;
            ctrl_o.ecall = 1'b1;
          end else if (instr_i[31:20] == 12'd1) begin
            ctrl_o.valid = 1'b1;
            ctrl_o.ebreak = 1'b1;
          end
        end
      end
      default: begin
        ctrl_o = '0;
        ctrl_o.funct3 = funct3;
      end
    endcase

    // Contract: an illegal encoding asserts no side-effecting
    // control at all, regardless of which guard rejected it. The
    // core also gates writes on the trap, but the decoder output
    // alone must be safe to consume (stage 2 registers it).
    if (!ctrl_o.valid) begin
      ctrl_o = '0;
      ctrl_o.funct3 = funct3;
    end
  end
endmodule
`default_nettype wire
