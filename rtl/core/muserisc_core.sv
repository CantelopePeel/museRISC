// Stage-1 single-cycle RV64I core (issue #18). One instruction per
// cycle over combinational-read Harvard memory ports; see
// docs/CORE.md for the interface contract and staging plan. Traps
// (illegal instruction, ECALL/EBREAK, misaligned load/store) assert
// trap_o and freeze the PC; full trap state arrives in stage 3.
`default_nettype none
module muserisc_core import muserisc_pkg::*; (
    input  wire        clk_i,
    input  wire        rst_ni,
    // Instruction memory (combinational read)
    output wire [63:0] imem_addr_o,
    input  wire [31:0] imem_rdata_i,
    // Data memory (combinational read, byte-enable write)
    output wire [63:0] dmem_addr_o,
    output logic [63:0] dmem_wdata_o,
    output logic [7:0]  dmem_be_o,
    output wire        dmem_re_o,
    input  wire [63:0] dmem_rdata_i,
    // Trap observability (stage 1: halt on trap)
    output wire        trap_o,
    output logic [63:0] trap_cause_o,
    output wire [63:0] trap_pc_o
);
  logic [63:0] pc_q, pc_d;
  muserisc_pkg::ctrl_t ctrl;
  logic [63:0] imm;
  logic [4:0]  rs1, rs2, rd;
  logic [63:0] rs1_data, rs2_data, rd_data;
  logic [63:0] alu_a, alu_b, alu_result;
  logic [63:0] load_data;
  logic        branch_taken;
  logic        misaligned_load, misaligned_store;
  logic        trap;

  muserisc_decoder u_decoder (
      .instr_i (imem_rdata_i),
      .ctrl_o  (ctrl),
      .imm_o   (imm),
      .rs1_o   (rs1),
      .rs2_o   (rs2),
      .rd_o    (rd)
  );

  muserisc_regfile u_regfile (
      .clk_i     (clk_i),
      .we_i      (ctrl.reg_write && !trap),
      .waddr_i   (rd),
      .wdata_i   (rd_data),
      .raddr_a_i (rs1),
      .rdata_a_o (rs1_data),
      .raddr_b_i (rs2),
      .rdata_b_o (rs2_data)
  );

  assign alu_a = ctrl.alu_a_pc ? pc_q : rs1_data;
  assign alu_b = ctrl.alu_src_imm ? imm : rs2_data;

  muserisc_alu u_alu (
      .op_i      (ctrl.alu_op),
      .word_op_i (ctrl.word_op),
      .a_i       (alu_a),
      .b_i       (alu_b),
      .result_o  (alu_result)
  );

  logic [63:0] muldiv_result;
  muserisc_muldiv u_muldiv (
      .funct3_i  (ctrl.funct3),
      .word_op_i (ctrl.word_op),
      .a_i       (rs1_data),
      .b_i       (rs2_data),
      .result_o  (muldiv_result)
  );

  // Branch conditions from funct3.
  always_comb begin
    unique case (ctrl.funct3)
      3'b000:  branch_taken = (rs1_data == rs2_data);                 // BEQ
      3'b001:  branch_taken = (rs1_data != rs2_data);                 // BNE
      3'b100:  branch_taken = ($signed(rs1_data) < $signed(rs2_data)); // BLT
      3'b101:  branch_taken = ($signed(rs1_data) >= $signed(rs2_data)); // BGE
      3'b110:  branch_taken = (rs1_data < rs2_data);                  // BLTU
      3'b111:  branch_taken = (rs1_data >= rs2_data);                 // BGEU
      default: branch_taken = 1'b0;
    endcase
  end

  // Data memory interface. Size from funct3[1:0]: 00 byte, 01 half,
  // 10 word, 11 double. Byte enables and write data are shifted to
  // the addressed byte lane; loads are extracted and (sign-)extended
  // below. Misaligned accesses trap (no Zicclsm claim, stage 1).
  assign dmem_addr_o = alu_result;
  assign dmem_re_o = ctrl.mem_read && !trap;

  always_comb begin
    dmem_be_o = 8'd0;
    dmem_wdata_o = 64'd0;
    if (ctrl.mem_write && !trap) begin
      unique case (ctrl.funct3[1:0])
        2'b00: begin
          dmem_be_o = 8'h01 << dmem_addr_o[2:0];
          dmem_wdata_o = {8{rs2_data[7:0]}};
        end
        2'b01: begin
          dmem_be_o = 8'h03 << {dmem_addr_o[2:1], 1'b0};
          dmem_wdata_o = {4{rs2_data[15:0]}};
        end
        2'b10: begin
          dmem_be_o = 8'h0F << {dmem_addr_o[2], 2'b00};
          dmem_wdata_o = {2{rs2_data[31:0]}};
        end
        default: begin
          dmem_be_o = 8'hFF;
          dmem_wdata_o = rs2_data;
        end
      endcase
    end
  end

  // Load extraction: shift the addressed bytes to the bottom, then
  // extend. funct3[2] set = unsigned (zero-extend).
  logic [63:0] load_shifted;
  assign load_shifted = dmem_rdata_i >> {dmem_addr_o[2:0], 3'b000};
  always_comb begin
    unique case (ctrl.funct3)
      3'b000:  load_data = {{56{load_shifted[7]}}, load_shifted[7:0]};   // LB
      3'b001:  load_data = {{48{load_shifted[15]}}, load_shifted[15:0]}; // LH
      3'b010:  load_data = {{32{load_shifted[31]}}, load_shifted[31:0]}; // LW
      3'b011:  load_data = load_shifted;                                 // LD
      3'b100:  load_data = {56'd0, load_shifted[7:0]};                   // LBU
      3'b101:  load_data = {48'd0, load_shifted[15:0]};                  // LHU
      3'b110:  load_data = {32'd0, load_shifted[31:0]};                  // LWU
      default: load_data = 64'd0;
    endcase
  end

  always_comb begin
    misaligned_load = 1'b0;
    misaligned_store = 1'b0;
    if (ctrl.mem_read || ctrl.mem_write) begin
      unique case (ctrl.funct3[1:0])
        2'b01: begin
          misaligned_load = ctrl.mem_read && dmem_addr_o[0];
          misaligned_store = ctrl.mem_write && dmem_addr_o[0];
        end
        2'b10: begin
          misaligned_load = ctrl.mem_read && (|dmem_addr_o[1:0]);
          misaligned_store = ctrl.mem_write && (|dmem_addr_o[1:0]);
        end
        2'b11: begin
          misaligned_load = ctrl.mem_read && (|dmem_addr_o[2:0]);
          misaligned_store = ctrl.mem_write && (|dmem_addr_o[2:0]);
        end
        default: ;
      endcase
    end
  end

  assign trap = !ctrl.valid || ctrl.ecall || ctrl.ebreak ||
                misaligned_load || misaligned_store;

  always_comb begin
    if (ctrl.ecall)         trap_cause_o = CAUSE_ECALL_M;
    else if (ctrl.ebreak)   trap_cause_o = CAUSE_BREAKPOINT;
    else if (misaligned_load)  trap_cause_o = CAUSE_LOAD_MISALIGN;
    else if (misaligned_store) trap_cause_o = CAUSE_STORE_MISALIGN;
    else                    trap_cause_o = CAUSE_ILLEGAL_INSTR;
  end
  assign trap_o = trap;
  assign trap_pc_o = pc_q;

  // Writeback select: jumps write the return address, loads the
  // loaded data, M ops the muldiv result, everything else the ALU.
  always_comb begin
    if (ctrl.jal || ctrl.jalr)   rd_data = pc_q + 64'd4;
    else if (ctrl.mem_read)      rd_data = load_data;
    else if (ctrl.muldiv)        rd_data = muldiv_result;
    else                         rd_data = alu_result;
  end

  // Next PC. JALR clears bit 0 per spec. Traps freeze the PC.
  always_comb begin
    if (trap)                        pc_d = pc_q;
    else if (ctrl.jal)               pc_d = pc_q + imm;
    else if (ctrl.jalr)              pc_d = (rs1_data + imm) & ~64'd1;
    else if (ctrl.branch && branch_taken) pc_d = pc_q + imm;
    else                             pc_d = pc_q + 64'd4;
  end

  assign imem_addr_o = pc_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) pc_q <= 64'd0;
    else         pc_q <= pc_d;
  end
endmodule
`default_nettype wire
