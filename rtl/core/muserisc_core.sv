// In-house RV64 core (issue #18). Five-stage in-order pipeline
// (IF/ID/EX/MEM/WB) over combinational-read Harvard memory ports;
// see docs/CORE.md for the contract and staging plan.
//
// Pipeline policy (stage 2):
// - Full forwarding to EX from EX/MEM and MEM/WB, plus a WB->ID
//   bypass so an instruction reading a register in the cycle its
//   producer is in WB latches the new value.
// - One bubble on load-use (consumer in ID against a load in EX).
// - All control transfers resolve in EX (predict not-taken):
//   taken branches and jumps flush IF/ID and ID/EX.
// - Exceptions (illegal/ECALL/EBREAK from ID, misaligned
//   load/store from EX) travel with their instruction; the
//   trapping instruction and everything younger perform no
//   register or memory write, and trap_o asserts as it reaches
//   WB, freezing the machine. Full trap state arrives in stage 3.
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
    // Trap observability (halt on trap)
    output wire        trap_o,
    output wire [63:0] trap_cause_o,
    output wire [63:0] trap_pc_o
);

  // ------------------------------------------------------------
  // IF stage
  // ------------------------------------------------------------
  logic [63:0] pc_q, pc_d;
  logic        stall;         // load-use: hold PC and IF/ID
  logic        flush;         // control transfer taken in EX
  logic [63:0] redirect_pc;
  logic        freeze;        // trapping instruction reached WB

  assign imem_addr_o = pc_q;

  // IF/ID register
  logic        ifid_valid_q;
  logic [63:0] ifid_pc_q;
  logic [31:0] ifid_instr_q;

  // ------------------------------------------------------------
  // ID stage
  // ------------------------------------------------------------
  muserisc_pkg::ctrl_t id_ctrl;
  logic [63:0] id_imm;
  logic [4:0]  id_rs1, id_rs2, id_rd;
  logic [63:0] rf_rs1, rf_rs2;
  logic [63:0] id_rs1_val, id_rs2_val;
  logic        id_exc;
  logic [63:0] id_cause;

  muserisc_decoder u_decoder (
      .instr_i (ifid_instr_q),
      .ctrl_o  (id_ctrl),
      .imm_o   (id_imm),
      .rs1_o   (id_rs1),
      .rs2_o   (id_rs2),
      .rd_o    (id_rd)
  );

  assign id_exc = ifid_valid_q &&
                  (!id_ctrl.valid || id_ctrl.ecall || id_ctrl.ebreak);
  always_comb begin
    if (id_ctrl.ecall)       id_cause = CAUSE_ECALL_M;
    else if (id_ctrl.ebreak) id_cause = CAUSE_BREAKPOINT;
    else                     id_cause = CAUSE_ILLEGAL_INSTR;
  end

  // Which source registers the ID instruction actually reads
  // (for the load-use interlock). Derived from the opcode so the
  // decoder contract stays as unit-tested.
  logic [6:0] id_opcode;
  logic       id_uses_rs1, id_uses_rs2;
  assign id_opcode = ifid_instr_q[6:0];
  assign id_uses_rs1 = (id_opcode != 7'b0110111) &&  // LUI
                       (id_opcode != 7'b0010111) &&  // AUIPC
                       (id_opcode != 7'b1101111);    // JAL
  assign id_uses_rs2 = (id_opcode == 7'b0110011) ||  // OP
                       (id_opcode == 7'b0111011) ||  // OP-32
                       (id_opcode == 7'b0100011) ||  // STORE
                       (id_opcode == 7'b1100011);    // BRANCH

  // ID/EX register
  logic        idex_valid_q;
  logic [63:0] idex_pc_q;
  muserisc_pkg::ctrl_t idex_ctrl_q;
  logic [63:0] idex_imm_q;
  logic [63:0] idex_rs1_q, idex_rs2_q;
  logic [4:0]  idex_rs1_addr_q, idex_rs2_addr_q, idex_rd_q;
  logic        idex_exc_q;
  logic [63:0] idex_cause_q;

  // Load-use interlock: a load in EX whose rd is read in ID.
  assign stall = idex_valid_q && idex_ctrl_q.mem_read &&
                 !idex_exc_q && (idex_rd_q != 5'd0) && ifid_valid_q &&
                 ((id_uses_rs1 && (idex_rd_q == id_rs1)) ||
                  (id_uses_rs2 && (idex_rd_q == id_rs2)));

  // ------------------------------------------------------------
  // EX stage
  // ------------------------------------------------------------
  logic [63:0] ex_rs1, ex_rs2;          // after forwarding
  logic [63:0] alu_a, alu_b, alu_result, muldiv_result;
  logic [63:0] ex_result;
  logic        branch_taken;
  logic        ex_misalign;
  logic        ex_exc;
  logic [63:0] ex_cause;

  // EX/MEM register (declared here: forwarding reads it). The full
  // control struct travels even though MEM consumes only part of
  // it; later stages (traps, stage 3) need the rest in flight.
  logic        exmem_valid_q;
  logic [63:0] exmem_pc_q;
  /* verilator lint_off UNUSEDSIGNAL */
  muserisc_pkg::ctrl_t exmem_ctrl_q;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [63:0] exmem_result_q;   // ALU/muldiv result or return addr
  logic [63:0] exmem_addr_q;     // load/store address
  logic [63:0] exmem_store_data_q;
  logic [4:0]  exmem_rd_q;
  logic        exmem_exc_q;
  logic [63:0] exmem_cause_q;

  // MEM/WB register (declared here: forwarding/bypass read it)
  logic        memwb_valid_q;
  logic [63:0] memwb_pc_q;
  logic [63:0] memwb_result_q;
  logic [4:0]  memwb_rd_q;
  logic        memwb_reg_write_q;
  logic        memwb_exc_q;
  logic [63:0] memwb_cause_q;

  // Register file: WB write, ID reads with WB bypass at the latch.
  logic        wb_write;
  assign wb_write = memwb_valid_q && memwb_reg_write_q && !memwb_exc_q;

  muserisc_regfile u_regfile (
      .clk_i     (clk_i),
      .we_i      (wb_write && !freeze),
      .waddr_i   (memwb_rd_q),
      .wdata_i   (memwb_result_q),
      .raddr_a_i (id_rs1),
      .rdata_a_o (rf_rs1),
      .raddr_b_i (id_rs2),
      .rdata_b_o (rf_rs2)
  );

  assign id_rs1_val = (wb_write && (memwb_rd_q != 5'd0) &&
                       (memwb_rd_q == id_rs1)) ? memwb_result_q : rf_rs1;
  assign id_rs2_val = (wb_write && (memwb_rd_q != 5'd0) &&
                       (memwb_rd_q == id_rs2)) ? memwb_result_q : rf_rs2;

  // Forwarding into EX: EX/MEM (non-load results only; a load's
  // data is not ready there) wins over MEM/WB, which wins over
  // the value latched in ID.
  always_comb begin
    if (exmem_valid_q && exmem_ctrl_q.reg_write && !exmem_ctrl_q.mem_read &&
        !exmem_exc_q && (exmem_rd_q != 5'd0) &&
        (exmem_rd_q == idex_rs1_addr_q)) begin
      ex_rs1 = exmem_result_q;
    end else if (wb_write && (memwb_rd_q != 5'd0) &&
                 (memwb_rd_q == idex_rs1_addr_q)) begin
      ex_rs1 = memwb_result_q;
    end else begin
      ex_rs1 = idex_rs1_q;
    end
    if (exmem_valid_q && exmem_ctrl_q.reg_write && !exmem_ctrl_q.mem_read &&
        !exmem_exc_q && (exmem_rd_q != 5'd0) &&
        (exmem_rd_q == idex_rs2_addr_q)) begin
      ex_rs2 = exmem_result_q;
    end else if (wb_write && (memwb_rd_q != 5'd0) &&
                 (memwb_rd_q == idex_rs2_addr_q)) begin
      ex_rs2 = memwb_result_q;
    end else begin
      ex_rs2 = idex_rs2_q;
    end
  end

  assign alu_a = idex_ctrl_q.alu_a_pc ? idex_pc_q : ex_rs1;
  assign alu_b = idex_ctrl_q.alu_src_imm ? idex_imm_q : ex_rs2;

  muserisc_alu u_alu (
      .op_i      (idex_ctrl_q.alu_op),
      .word_op_i (idex_ctrl_q.word_op),
      .a_i       (alu_a),
      .b_i       (alu_b),
      .result_o  (alu_result)
  );

  muserisc_muldiv u_muldiv (
      .funct3_i  (idex_ctrl_q.funct3),
      .word_op_i (idex_ctrl_q.word_op),
      .a_i       (ex_rs1),
      .b_i       (ex_rs2),
      .result_o  (muldiv_result)
  );

  always_comb begin
    if (idex_ctrl_q.jal || idex_ctrl_q.jalr) ex_result = idex_pc_q + 64'd4;
    else if (idex_ctrl_q.muldiv)             ex_result = muldiv_result;
    else                                     ex_result = alu_result;
  end

  always_comb begin
    unique case (idex_ctrl_q.funct3)
      3'b000:  branch_taken = (ex_rs1 == ex_rs2);
      3'b001:  branch_taken = (ex_rs1 != ex_rs2);
      3'b100:  branch_taken = ($signed(ex_rs1) < $signed(ex_rs2));
      3'b101:  branch_taken = ($signed(ex_rs1) >= $signed(ex_rs2));
      3'b110:  branch_taken = (ex_rs1 < ex_rs2);
      3'b111:  branch_taken = (ex_rs1 >= ex_rs2);
      default: branch_taken = 1'b0;
    endcase
  end

  assign flush = idex_valid_q && !idex_exc_q &&
                 (idex_ctrl_q.jal || idex_ctrl_q.jalr ||
                  (idex_ctrl_q.branch && branch_taken));
  assign redirect_pc = idex_ctrl_q.jalr ? ((ex_rs1 + idex_imm_q) & ~64'd1)
                                        : (idex_pc_q + idex_imm_q);

  // Misalignment is known once the address is (EX). BYTE (funct3
  // low bits 00) can never misalign.
  always_comb begin
    ex_misalign = 1'b0;
    if (idex_ctrl_q.mem_read || idex_ctrl_q.mem_write) begin
      unique case (idex_ctrl_q.funct3[1:0])
        2'b01:   ex_misalign = alu_result[0];
        2'b10:   ex_misalign = |alu_result[1:0];
        2'b11:   ex_misalign = |alu_result[2:0];
        default: ex_misalign = 1'b0;
      endcase
    end
  end

  assign ex_exc = idex_exc_q || (idex_valid_q && ex_misalign);
  always_comb begin
    if (idex_exc_q)   ex_cause = idex_cause_q;
    else if (idex_ctrl_q.mem_write) ex_cause = CAUSE_STORE_MISALIGN;
    else              ex_cause = CAUSE_LOAD_MISALIGN;
  end

  // ------------------------------------------------------------
  // MEM stage
  // ------------------------------------------------------------
  logic [63:0] load_data;
  logic [63:0] mem_result;

  assign freeze = memwb_valid_q && memwb_exc_q;
  assign trap_o = freeze;
  assign trap_cause_o = memwb_cause_q;
  assign trap_pc_o = memwb_pc_q;

  assign dmem_addr_o = exmem_addr_q;
  assign dmem_re_o = exmem_valid_q && exmem_ctrl_q.mem_read && !exmem_exc_q;

  always_comb begin
    dmem_be_o = 8'd0;
    dmem_wdata_o = 64'd0;
    if (exmem_valid_q && exmem_ctrl_q.mem_write && !exmem_exc_q && !freeze) begin
      unique case (exmem_ctrl_q.funct3[1:0])
        2'b00: begin
          dmem_be_o = 8'h01 << dmem_addr_o[2:0];
          dmem_wdata_o = {8{exmem_store_data_q[7:0]}};
        end
        2'b01: begin
          dmem_be_o = 8'h03 << {dmem_addr_o[2:1], 1'b0};
          dmem_wdata_o = {4{exmem_store_data_q[15:0]}};
        end
        2'b10: begin
          dmem_be_o = 8'h0F << {dmem_addr_o[2], 2'b00};
          dmem_wdata_o = {2{exmem_store_data_q[31:0]}};
        end
        default: begin
          dmem_be_o = 8'hFF;
          dmem_wdata_o = exmem_store_data_q;
        end
      endcase
    end
  end

  logic [63:0] load_shifted;
  assign load_shifted = dmem_rdata_i >> {dmem_addr_o[2:0], 3'b000};
  always_comb begin
    unique case (exmem_ctrl_q.funct3)
      3'b000:  load_data = {{56{load_shifted[7]}}, load_shifted[7:0]};
      3'b001:  load_data = {{48{load_shifted[15]}}, load_shifted[15:0]};
      3'b010:  load_data = {{32{load_shifted[31]}}, load_shifted[31:0]};
      3'b011:  load_data = load_shifted;
      3'b100:  load_data = {56'd0, load_shifted[7:0]};
      3'b101:  load_data = {48'd0, load_shifted[15:0]};
      3'b110:  load_data = {32'd0, load_shifted[31:0]};
      default: load_data = 64'd0;
    endcase
  end

  assign mem_result = exmem_ctrl_q.mem_read ? load_data : exmem_result_q;

  // ------------------------------------------------------------
  // PC and pipeline registers
  // ------------------------------------------------------------
  always_comb begin
    if (flush)                pc_d = redirect_pc;
    else if (stall || freeze) pc_d = pc_q;
    else                      pc_d = pc_q + 64'd4;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pc_q <= 64'd0;
      ifid_valid_q <= 1'b0;
      idex_valid_q <= 1'b0;
      exmem_valid_q <= 1'b0;
      memwb_valid_q <= 1'b0;
      ifid_pc_q <= 64'd0;
      ifid_instr_q <= 32'd0;
      idex_pc_q <= 64'd0;
      idex_ctrl_q <= '0;
      idex_imm_q <= 64'd0;
      idex_rs1_q <= 64'd0;
      idex_rs2_q <= 64'd0;
      idex_rs1_addr_q <= 5'd0;
      idex_rs2_addr_q <= 5'd0;
      idex_rd_q <= 5'd0;
      idex_exc_q <= 1'b0;
      idex_cause_q <= 64'd0;
      exmem_pc_q <= 64'd0;
      exmem_ctrl_q <= '0;
      exmem_result_q <= 64'd0;
      exmem_addr_q <= 64'd0;
      exmem_store_data_q <= 64'd0;
      exmem_rd_q <= 5'd0;
      exmem_exc_q <= 1'b0;
      exmem_cause_q <= 64'd0;
      memwb_pc_q <= 64'd0;
      memwb_result_q <= 64'd0;
      memwb_rd_q <= 5'd0;
      memwb_reg_write_q <= 1'b0;
      memwb_exc_q <= 1'b0;
      memwb_cause_q <= 64'd0;
    end else if (!freeze) begin
      pc_q <= pc_d;

      // MEM/WB always advances.
      memwb_valid_q <= exmem_valid_q;
      memwb_pc_q <= exmem_pc_q;
      memwb_result_q <= mem_result;
      memwb_rd_q <= exmem_rd_q;
      memwb_reg_write_q <= exmem_ctrl_q.reg_write;
      memwb_exc_q <= exmem_exc_q;
      memwb_cause_q <= exmem_cause_q;

      // EX/MEM always advances.
      exmem_valid_q <= idex_valid_q;
      exmem_pc_q <= idex_pc_q;
      exmem_ctrl_q <= idex_ctrl_q;
      exmem_result_q <= ex_result;
      exmem_addr_q <= alu_result;
      exmem_store_data_q <= ex_rs2;
      exmem_rd_q <= idex_rd_q;
      exmem_exc_q <= ex_exc;
      exmem_cause_q <= ex_cause;

      // ID/EX: bubble on stall or flush.
      if (stall || flush) begin
        idex_valid_q <= 1'b0;
      end else begin
        idex_valid_q <= ifid_valid_q;
        idex_pc_q <= ifid_pc_q;
        idex_ctrl_q <= id_ctrl;
        idex_imm_q <= id_imm;
        idex_rs1_q <= id_rs1_val;
        idex_rs2_q <= id_rs2_val;
        idex_rs1_addr_q <= id_rs1;
        idex_rs2_addr_q <= id_rs2;
        idex_rd_q <= id_rd;
        idex_exc_q <= id_exc;
        idex_cause_q <= id_cause;
      end

      // IF/ID: hold on stall, clear on flush.
      if (flush) begin
        ifid_valid_q <= 1'b0;
      end else if (!stall) begin
        ifid_valid_q <= 1'b1;
        ifid_pc_q <= pc_q;
        ifid_instr_q <= imem_rdata_i;
      end
    end
  end
endmodule
`default_nettype wire
