// In-house RV64 core (issue #18). Five-stage in-order pipeline
// (IF/ID/EX/MEM/WB) over combinational-read Harvard memory ports
// with M/S/U privilege, precise traps, interrupts, PMP, and an
// Sv39+Svnapot MMU; see docs/CORE.md for the contract and
// staging plan.
//
// Pipeline policy:
// - Full forwarding to EX (EX/MEM and MEM/WB) plus a WB->ID
//   bypass so an instruction reading a register in the cycle its
//   producer is in WB latches the new value.
// - One bubble on load-use (consumer in ID against a load in EX).
// - All control transfers resolve in EX (predict not-taken):
//   taken branches, jumps, xRET, and SFENCE flush IF/ID + ID/EX.
// - CSR writes commit on the EX->MEM edge; CSR reads in EX see
//   all older writes. Privilege changes only via trap entry
//   (WB) and xRET (EX), both of which flush, so priv_o always
//   names the privilege of every instruction in flight.
// - Exceptions travel with their instruction to WB; the
//   trapping instruction and everything younger perform no
//   register, memory, or CSR write. At WB the trap is taken
//   (redirect to the handler) unless trap_halt_i requests the
//   stage-1/2 freeze-and-report behavior for directed TBs.
// - Interrupts are injected in ID as an exception on the next
//   unexecuted instruction, making epc precise by construction.
// - Virtual memory: fetch translates combinationally (TLB hit)
//   or stalls IF while the walker runs; a data miss stalls the
//   whole pipeline with the access parked in MEM. PMP is always
//   checked on physical addresses (port C covers PTE accesses).
`default_nettype none
module muserisc_core import muserisc_pkg::*; (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire [63:0] boot_pc_i,     // reset PC (0 for directed TBs)
    // Instruction memory (combinational read)
    output wire [63:0] imem_addr_o,
    input  wire [31:0] imem_rdata_i,
    // Data memory (combinational read, byte-enable write)
    output wire [63:0] dmem_addr_o,
    output logic [63:0] dmem_wdata_o,
    output logic [7:0]  dmem_be_o,
    output wire        dmem_re_o,
    input  wire [63:0] dmem_rdata_i,
    // Trap observability: pulses the cycle a trap is taken.
    output wire        trap_o,
    output wire [63:0] trap_cause_o,
    output wire [63:0] trap_pc_o,
    // 1 = freeze on first trap (directed-TB mode), 0 = take trap.
    input  wire        trap_halt_i,
    // Interrupt lines (CLINT/PLIC equivalents in a future SoC).
    input  wire        irq_m_timer_i,
    input  wire        irq_m_soft_i,
    input  wire        irq_m_ext_i,
    input  wire        irq_s_timer_i,
    input  wire        irq_s_ext_i
);

  // ------------------------------------------------------------
  // CSR / privileged state (declared first: ID/EX read it)
  // ------------------------------------------------------------
  logic [1:0]  priv;
  // The core consumes mstatus.MPRV/MPP today; satp feeds the MMU.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [63:0] csr_mstatus, csr_satp, csr_hgatp;
  logic        virt, dvirt, csr_virt_inst, csr_sum, csr_mxr, csr_hs_mxr;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [1:0]  eff_priv_data;  // MPRV-adjusted privilege for data
  assign eff_priv_data = (priv == 2'b11 && csr_mstatus[17])
                             ? csr_mstatus[12:11] : priv;

  logic [11:0] csr_addr;
  logic [63:0] csr_rdata, csr_wdata, csr_src;
  logic        csr_illegal, csr_we;
  logic        sys_illegal;
  logic [2:0]  sys_op;
  logic [63:0] xret_pc;
  logic        irq_valid;
  logic [63:0] irq_cause;
  logic        trap_fire, trap_take;
  logic [63:0] trap_target;
  logic [1:0]  trap_priv_unused;
  logic        pmp_allow_fetch, pmp_allow_data, pmp_allow_walk;

  // MMU (instantiated after MEM; signals declared here for IF)
  logic [63:0] mmu_if_pa, mmu_d_pa;
  logic        mmu_if_ok, mmu_if_fault, mmu_if_fault_page;
  logic        mmu_d_ok, mmu_d_fault, mmu_d_fault_page;
  logic        mmu_if_fault_guest, mmu_d_fault_guest;
  logic [63:0] mmu_if_fault_gpa, mmu_d_fault_gpa;
  logic        walk_req, walk_we, walk_grant;
  logic [63:0] walk_addr, walk_wdata;
  logic [1:0]  walk_acc;
  logic        mem_stall;     // data translation miss: hold all regs
  logic        sfence_fire;   // SFENCE.VMA commits this cycle

  // ------------------------------------------------------------
  // IF stage
  // ------------------------------------------------------------
  logic [63:0] pc_q, pc_d;
  logic        stall;
  logic        flush;
  logic [63:0] redirect_pc;
  logic        freeze;
  logic        fetch_fault, fetch_stall;
  logic [63:0] fetch_cause;

  // Fetch realignment for 16-bit parcels (stage 5 C):
  // the MMU translates one aligned 32-bit fetch word at a
  // time. A 32-bit instruction starting in the upper half
  // latches its low parcel (straddle_q) and completes from
  // the next aligned word next cycle; that second fetch is
  // translated (and may fault) independently, with tval
  // naming the second half's address.
  logic        straddle_q;
  logic [15:0] straddle_lo_q;
  logic [63:0] fetch_va;
  assign fetch_va = straddle_q ? (pc_q + 64'd2)
                               : {pc_q[63:2], 2'b00};
  assign imem_addr_o = mmu_if_pa;
  // Physical addresses are 56 bits: an untranslated (M-mode /
  // Bare) address at or above 2^56 access-faults. Translated
  // PAs from the MMU are 56-bit by construction. Gated on
  // mmu_if_ok: while a walk is in flight if_pa_o still carries
  // the raw VA, which may be a high canonical address.
  logic fetch_pa_illegal;
  assign fetch_pa_illegal = mmu_if_ok && |mmu_if_pa[63:56];
  // IALIGN=16 (C extension): only translation and PMP faults
  // remain at fetch.
  assign fetch_fault = mmu_if_fault || fetch_pa_illegal ||
                       (mmu_if_ok && !pmp_allow_fetch);
  assign fetch_cause = mmu_if_fault ?
      (mmu_if_fault_guest ? 64'd20 :
       mmu_if_fault_page ? 64'd12 : 64'd1) : 64'd1;
  assign fetch_stall = !fetch_pa_illegal && !mmu_if_ok &&
                       !mmu_if_fault;

  // Parcel assembly and decompression.
  logic [15:0] parcel16;
  logic        parcel_long, rvc_illegal, straddle_enter;
  logic [31:0] fetch_instr, rvc_expanded;
  logic        fetch_rvc;
  logic [63:0] fetch_tval;
  assign parcel16 = pc_q[1] ? imem_rdata_i[31:16]
                            : imem_rdata_i[15:0];
  assign parcel_long = (parcel16[1:0] == 2'b11);
  assign straddle_enter = !straddle_q && parcel_long && pc_q[1] &&
                          !fetch_fault && !fetch_stall;
  muserisc_rvc u_rvc (
      .in_i      (parcel16),
      .out_o     (rvc_expanded),
      .illegal_o (rvc_illegal)
  );
  always_comb begin
    if (straddle_q) begin
      fetch_instr = {imem_rdata_i[15:0], straddle_lo_q};
      fetch_rvc = 1'b0;
    end else if (!parcel_long) begin
      fetch_instr = rvc_illegal ? 32'b0 : rvc_expanded;
      fetch_rvc = 1'b1;
    end else begin
      fetch_instr = imem_rdata_i;
      fetch_rvc = 1'b0;
    end
  end
  assign fetch_tval = straddle_q ? (pc_q + 64'd2) : pc_q;

  // IF/ID register
  logic        ifid_valid_q;
  logic [63:0] ifid_pc_q;
  logic [31:0] ifid_instr_q;
  logic        ifid_exc_q;      // fetch fault (access or page)
  logic [63:0] ifid_cause_q;
  logic        ifid_rvc_q;      // instruction was a 16-bit parcel
  logic [15:0] ifid_parcel_q;   // raw parcel (illegal tval)
  logic [63:0] ifid_tval_q;     // fetch-fault address
  logic [63:0] ifid_gpa_q;      // faulting GPA (guest faults)

  // ------------------------------------------------------------
  // ID stage
  // ------------------------------------------------------------
  muserisc_pkg::ctrl_t id_ctrl;
  logic [63:0] id_imm;
  logic [4:0]  id_rs1, id_rs2, id_rd;
  logic [63:0] rf_rs1, rf_rs2;
  logic [63:0] id_rs1_val, id_rs2_val;
  logic        id_exc;
  logic [63:0] id_cause, id_tval, id_gpa;
  logic        irq_inject;

  muserisc_decoder u_decoder (
      .instr_i (ifid_instr_q),
      .ctrl_o  (id_ctrl),
      .imm_o   (id_imm),
      .rs1_o   (id_rs1),
      .rs2_o   (id_rs2),
      .rd_o    (id_rd)
  );

  always_comb begin
    id_gpa = 64'd0;
    if (ifid_exc_q) begin
      id_exc = ifid_valid_q;
      id_cause = ifid_cause_q;          // 1 access / 12 page / 20 guest
      id_tval = ifid_tval_q;
      id_gpa = ifid_gpa_q;
    end else if (id_ctrl.ecall) begin
      id_exc = ifid_valid_q;
      id_cause = (priv == 2'b11) ? 64'd11 :
                 (priv == 2'b01) ? (virt ? 64'd10 : 64'd9) : 64'd8;
      id_tval = 64'd0;
    end else if (id_ctrl.ebreak) begin
      id_exc = ifid_valid_q;
      id_cause = CAUSE_BREAKPOINT;
      id_tval = ifid_pc_q;
    end else if (!id_ctrl.valid) begin
      id_exc = ifid_valid_q;
      id_cause = CAUSE_ILLEGAL_INSTR;
      id_tval = ifid_rvc_q ? {48'd0, ifid_parcel_q}
                           : {32'd0, ifid_instr_q};
    end else begin
      id_exc = 1'b0;
      id_cause = 64'd0;
      id_tval = 64'd0;
    end
  end

  assign irq_inject = irq_valid && ifid_valid_q && !stall && !flush &&
                      !freeze && !mem_stall;

  // Which sources the ID instruction reads (load-use interlock).
  logic [6:0] id_opcode;
  logic       id_uses_rs1, id_uses_rs2;
  assign id_opcode = ifid_instr_q[6:0];
  assign id_uses_rs1 = (id_opcode != 7'b0110111) &&
                       (id_opcode != 7'b0010111) &&
                       (id_opcode != 7'b1101111);
  assign id_uses_rs2 = (id_opcode == 7'b0110011) ||
                       (id_opcode == 7'b0111011) ||
                       (id_opcode == 7'b0100011) ||
                       (id_opcode == 7'b1100011) ||
                       (id_opcode == 7'b0101111);  // AMO/SC source
                       // (LR's rs2 field is x0; the rd!=0 guard covers it)

  // ID/EX register
  logic        idex_valid_q;
  logic [63:0] idex_pc_q;
  muserisc_pkg::ctrl_t idex_ctrl_q;
  logic [63:0] idex_imm_q;
  logic [31:0] idex_instr_q;  // for illegal-instruction tval in EX
  logic [63:0] idex_rs1_q, idex_rs2_q;
  logic [63:0] idex_frs1_q, idex_frs2_q, idex_frs3_q;
  logic [4:0]  idex_rs1_addr_q, idex_rs2_addr_q, idex_rd_q;
  logic [4:0]  idex_rs3_addr_q;
  logic        idex_exc_q;
  logic [63:0] idex_cause_q, idex_tval_q, idex_gpa_q;
  logic        idex_rvc_q;

  // FP sources of the ID instruction (from the decoder ctrl).
  logic [4:0] id_rs3;
  assign id_rs3 = ifid_instr_q[31:27];
  assign stall = idex_valid_q && idex_ctrl_q.mem_read &&
                 !idex_exc_q && ifid_valid_q && !ifid_exc_q &&
                 ((!idex_ctrl_q.fp_rd && (idex_rd_q != 5'd0) &&
                   ((id_uses_rs1 && (idex_rd_q == id_rs1)) ||
                    (id_uses_rs2 && (idex_rd_q == id_rs2)))) ||
                  (idex_ctrl_q.fp_rd &&
                   ((id_ctrl.fp_rs1 && (idex_rd_q == id_rs1)) ||
                    (id_ctrl.fp_rs2 && (idex_rd_q == id_rs2)) ||
                    (id_ctrl.fp_op && id_ctrl.fpu_op >= 5'd12 &&
                     id_ctrl.fpu_op <= 5'd15 &&
                     (idex_rd_q == id_rs3)))));

  // ------------------------------------------------------------
  // EX stage
  // ------------------------------------------------------------
  logic [63:0] ex_rs1, ex_rs2;
  logic [63:0] alu_a, alu_b, alu_result, muldiv_result;
  logic [63:0] ex_result;
  logic        branch_taken;
  logic        ex_misalign, ex_illegal;
  logic        ex_exc;
  logic [63:0] ex_cause, ex_tval, ex_gpa;
  logic        ex_ret, ex_serialize;

  // EX/MEM register
  logic        exmem_valid_q;
  logic [63:0] exmem_pc_q;
  /* verilator lint_off UNUSEDSIGNAL */
  muserisc_pkg::ctrl_t exmem_ctrl_q;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [63:0] exmem_result_q;
  logic [63:0] exmem_addr_q;
  logic [63:0] exmem_store_data_q;
  logic [4:0]  exmem_rd_q;
  logic        exmem_exc_q;
  logic [63:0] exmem_cause_q, exmem_tval_q, exmem_gpa_q;

  // MEM/WB register
  logic        memwb_valid_q;
  logic [63:0] memwb_pc_q;
  logic [63:0] memwb_result_q;
  logic [4:0]  memwb_rd_q;
  logic        memwb_reg_write_q;
  logic        memwb_fp_write_q;
  logic        memwb_exc_q;
  logic [63:0] memwb_cause_q, memwb_tval_q, memwb_gpa_q;

  logic        wb_write;
  assign wb_write = memwb_valid_q && memwb_reg_write_q && !memwb_exc_q;
  logic        wb_fp_write;
  assign wb_fp_write = memwb_valid_q && memwb_fp_write_q &&
                       !memwb_exc_q;
  assign trap_fire = memwb_valid_q && memwb_exc_q;
  assign trap_take = trap_fire && !trap_halt_i;
  assign freeze = trap_fire && trap_halt_i;
  assign trap_o = trap_fire;
  assign trap_cause_o = memwb_cause_q;
  assign trap_pc_o = memwb_pc_q;

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

  logic [63:0] frf_rs1, frf_rs2, frf_rs3;
  logic [63:0] id_frs1_val, id_frs2_val, id_frs3_val;
  muserisc_fpregfile u_fpregfile (
      .clk_i     (clk_i),
      .we_i      (wb_fp_write && !freeze),
      .waddr_i   (memwb_rd_q),
      .wdata_i   (memwb_result_q),
      .raddr1_i  (id_rs1),
      .raddr2_i  (id_rs2),
      .raddr3_i  (id_rs3),
      .rdata1_o  (frf_rs1),
      .rdata2_o  (frf_rs2),
      .rdata3_o  (frf_rs3)
  );
  assign id_frs1_val = (wb_fp_write && (memwb_rd_q == id_rs1))
                       ? memwb_result_q : frf_rs1;
  assign id_frs2_val = (wb_fp_write && (memwb_rd_q == id_rs2))
                       ? memwb_result_q : frf_rs2;
  assign id_frs3_val = (wb_fp_write && (memwb_rd_q == id_rs3))
                       ? memwb_result_q : frf_rs3;

  logic [63:0] ex_frs1, ex_frs2, ex_frs3;
  always_comb begin
    if (exmem_valid_q && exmem_ctrl_q.fp_rd &&
        !exmem_ctrl_q.mem_read && !exmem_exc_q &&
        (exmem_rd_q == idex_rs1_addr_q))
      ex_frs1 = exmem_result_q;
    else if (wb_fp_write && (memwb_rd_q == idex_rs1_addr_q))
      ex_frs1 = memwb_result_q;
    else
      ex_frs1 = idex_frs1_q;
    if (exmem_valid_q && exmem_ctrl_q.fp_rd &&
        !exmem_ctrl_q.mem_read && !exmem_exc_q &&
        (exmem_rd_q == idex_rs2_addr_q))
      ex_frs2 = exmem_result_q;
    else if (wb_fp_write && (memwb_rd_q == idex_rs2_addr_q))
      ex_frs2 = memwb_result_q;
    else
      ex_frs2 = idex_frs2_q;
    if (exmem_valid_q && exmem_ctrl_q.fp_rd &&
        !exmem_ctrl_q.mem_read && !exmem_exc_q &&
        (exmem_rd_q == idex_rs3_addr_q))
      ex_frs3 = exmem_result_q;
    else if (wb_fp_write && (memwb_rd_q == idex_rs3_addr_q))
      ex_frs3 = memwb_result_q;
    else
      ex_frs3 = idex_frs3_q;
  end

  assign id_rs1_val = (wb_write && (memwb_rd_q != 5'd0) &&
                       (memwb_rd_q == id_rs1)) ? memwb_result_q : rf_rs1;
  assign id_rs2_val = (wb_write && (memwb_rd_q != 5'd0) &&
                       (memwb_rd_q == id_rs2)) ? memwb_result_q : rf_rs2;

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

  logic [2:0]  csr_frm;
  logic [1:0]  csr_fs;
  logic [63:0] fpu_result;
  logic [4:0]  fpu_flags;
  logic [2:0]  fpu_rm;
  assign fpu_rm = (idex_ctrl_q.funct3 == 3'b111) ? csr_frm
                                                 : idex_ctrl_q.funct3;
  muserisc_fpu u_fpu (
      .op_i      (idex_ctrl_q.fpu_op),
      .fmt_d_i   (idex_ctrl_q.fmt_d),
      .rm_i      (fpu_rm),
      .a_i       (idex_ctrl_q.fp_rs1 ? ex_frs1 : ex_rs1),
      .b_i       (ex_frs2),
      .c_i       (ex_frs3),
      .aux_i     (idex_ctrl_q.fpu_aux),
      .result_o  (fpu_result),
      .flags_o   (fpu_flags)
  );
  // FP instructions need FS != Off; dynamic rounding mode must
  // name a real mode (static bad rms are illegal at decode).
  logic fp_illegal;
  assign fp_illegal = (idex_ctrl_q.fp && (csr_fs == 2'b00)) ||
                      (idex_ctrl_q.fp_rm &&
                       (idex_ctrl_q.funct3 == 3'b111) &&
                       (csr_frm > 3'd4));
  logic csr_fflags_we, fp_dirty_ex, fp_dirty_mem, fp_dirty;
  // !mem_exc on every EX-committed side effect: an older
  // instruction already carrying an exception in MEM must take
  // its trap before this instruction writes architectural state
  // (OpenSBI's mtvec restore right after a trapping CSR probe
  // otherwise beats the in-flight trap to the vector).
  assign csr_fflags_we = idex_valid_q && idex_ctrl_q.fp_op &&
                         !idex_exc_q && !ex_illegal && !trap_fire &&
                         !mem_exc && !mem_stall;
  assign fp_dirty_ex = csr_fflags_we && idex_ctrl_q.fp_rd;
  assign fp_dirty_mem = exmem_valid_q && exmem_ctrl_q.fp_rd &&
                        exmem_ctrl_q.mem_read && !exmem_exc_q &&
                        !mem_exc && !mem_stall;
  assign fp_dirty = fp_dirty_ex || fp_dirty_mem;

  logic [63:0] bext_result;
  muserisc_bext u_bext (
      .op_i      (idex_ctrl_q.bext_op),
      .a_i       (ex_rs1),
      .b_i       (idex_ctrl_q.alu_src_imm ? idex_imm_q : ex_rs2),
      .result_o  (bext_result)
  );

  muserisc_muldiv u_muldiv (
      .funct3_i  (idex_ctrl_q.funct3),
      .word_op_i (idex_ctrl_q.word_op),
      .a_i       (ex_rs1),
      .b_i       (ex_rs2),
      .result_o  (muldiv_result)
  );

  // CSR execution in EX.
  assign csr_addr = idex_imm_q[11:0];
  assign csr_src = idex_ctrl_q.csr_imm ? {59'd0, idex_rs1_addr_q} : ex_rs1;
  always_comb begin
    unique case (idex_ctrl_q.funct3[1:0])
      2'b01:   csr_wdata = csr_src;                       // CSRRW(I)
      2'b10:   csr_wdata = csr_rdata | csr_src;           // CSRRS(I)
      default: csr_wdata = csr_rdata & ~csr_src;          // CSRRC(I)
    endcase
  end
  // !mem_stall: a CSR write must not commit while an older
  // instruction is parked in MEM (it could still page-fault).
  assign csr_we = idex_valid_q && idex_ctrl_q.csr && !idex_exc_q &&
                  !trap_fire && !mem_exc && !mem_stall &&
                  ((idex_ctrl_q.funct3[1:0] == 2'b01) ||
                   (idex_rs1_addr_q != 5'd0));
  assign sfence_fire = idex_valid_q && idex_ctrl_q.sfence && !idex_exc_q &&
                       !sys_illegal && !mem_stall;
  assign sys_op = idex_ctrl_q.mret   ? 3'd1 :
                  idex_ctrl_q.sret   ? 3'd2 :
                  idex_ctrl_q.wfi    ? 3'd3 :
                  idex_ctrl_q.sfence ? 3'd4 : 3'd0;
  assign ex_ret = idex_valid_q && (idex_ctrl_q.mret || idex_ctrl_q.sret) &&
                  !idex_exc_q && !sys_illegal;
  // SFENCE and xRET serialize: redirect and flush like a jump.
  assign ex_serialize = ex_ret ||
                        (idex_valid_q && idex_ctrl_q.sfence &&
                         !idex_exc_q && !sys_illegal);
  assign ex_illegal = (idex_ctrl_q.csr ? csr_illegal :
                      ((idex_ctrl_q.mret || idex_ctrl_q.sret ||
                        idex_ctrl_q.wfi || idex_ctrl_q.sfence) && sys_illegal)) ||
                      fp_illegal;

  always_comb begin
    if (idex_ctrl_q.jal || idex_ctrl_q.jalr) ex_result = idex_pc_q + (idex_rvc_q ? 64'd2 : 64'd4);
    else if (idex_ctrl_q.csr)                ex_result = csr_rdata;
    else if (idex_ctrl_q.muldiv)             ex_result = muldiv_result;
    else if (idex_ctrl_q.fp_op)              ex_result = fpu_result;
    else if (idex_ctrl_q.bext)               ex_result = bext_result;
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

  // With IALIGN=16 a control target is misaligned only if
  // bit 0 is set, which no encodable target can be (branch
  // and JAL immediates are even, JALR clears bit 0); the
  // check is retained in that form for completeness.
  logic jump_misalign;
  assign jump_misalign = idex_valid_q && !idex_exc_q && !ex_illegal &&
      (idex_ctrl_q.jal || idex_ctrl_q.jalr ||
       (idex_ctrl_q.branch && branch_taken)) && redirect_pc[0];

  assign flush = idex_valid_q && !idex_exc_q && !ex_illegal &&
                 !jump_misalign &&
                 (idex_ctrl_q.jal || idex_ctrl_q.jalr ||
                  (idex_ctrl_q.branch && branch_taken) || ex_serialize);
  always_comb begin
    if (ex_ret)                  redirect_pc = xret_pc;
    else if (idex_ctrl_q.sfence) redirect_pc = idex_pc_q + (idex_rvc_q ? 64'd2 : 64'd4);
    else if (idex_ctrl_q.jalr)   redirect_pc = (ex_rs1 + idex_imm_q) & ~64'd1;
    else                         redirect_pc = idex_pc_q + idex_imm_q;
  end

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

  always_comb begin
    ex_gpa = idex_gpa_q;
    if (idex_exc_q) begin
      ex_exc = idex_valid_q;
      ex_cause = idex_cause_q;
      ex_tval = idex_tval_q;
    end else if (ex_illegal) begin
      ex_gpa = 64'd0;
      ex_exc = idex_valid_q;
      ex_cause = csr_virt_inst ? 64'd22 : CAUSE_ILLEGAL_INSTR;
      ex_tval = {32'd0, idex_instr_q};
    end else if (jump_misalign) begin
      ex_exc = 1'b1;
      ex_cause = 64'd0;  // instruction address misaligned
      ex_tval = redirect_pc;
    end else if (ex_misalign) begin
      ex_exc = idex_valid_q;
      ex_cause = idex_ctrl_q.mem_write ? CAUSE_STORE_MISALIGN
                                       : CAUSE_LOAD_MISALIGN;
      ex_tval = alu_result;
    end else begin
      ex_exc = 1'b0;
      ex_cause = 64'd0;
      ex_tval = 64'd0;
    end
  end

  // ------------------------------------------------------------
  // MEM stage
  // ------------------------------------------------------------
  logic [63:0] load_data;
  logic [63:0] mem_result;
  logic        data_access, mem_uses_port;
  logic        mem_pmp_fault, mem_trans_fault;
  logic        mem_exc;
  logic [63:0] mem_cause, mem_tval, mem_gpa;

  // A translation miss parks the access in MEM (pipeline hold);
  // a translation fault or a PMP denial on the PA excepts it.
  assign data_access = exmem_valid_q && !exmem_exc_q &&
                       (exmem_ctrl_q.mem_read || exmem_ctrl_q.mem_write);
  assign mem_stall = data_access && !mmu_d_ok && !mmu_d_fault;
  assign mem_trans_fault = data_access && mmu_d_fault;
  // PMP denial, or a physical address outside the 56-bit map.
  assign mem_pmp_fault = data_access && mmu_d_ok &&
                         (!pmp_allow_data || |mmu_d_pa[63:56]);
  assign mem_uses_port = data_access && mmu_d_ok && !mem_pmp_fault;
  // The walker borrows the port whenever MEM is not using it.
  assign walk_grant = walk_req && !mem_uses_port;
  assign dmem_addr_o = walk_grant ? walk_addr : mmu_d_pa;
  assign dmem_re_o = mem_uses_port && exmem_ctrl_q.mem_read;

  logic [63:0] load_shifted;
  logic        res_valid_q;
  logic [63:0] res_pa_q;
  logic        res_is_d_q;  // reserved access size: 1 = 8B, 0 = 4B
  assign load_shifted = dmem_rdata_i >> {exmem_addr_q[2:0], 3'b000};

  // AMO read-modify-write, executed in MEM against the loaded
  // value (combinational memory: read and write are one cycle).
  logic [63:0] eff_store_data;
  logic        sc_success;
  always_comb begin
    logic [31:0] a32, b32, r32;
    logic [63:0] r64;
    a32 = load_shifted[31:0];
    b32 = exmem_store_data_q[31:0];
    unique case (exmem_ctrl_q.amo_op)
      5'b00000: begin  // AMOADD
        r32 = a32 + b32;
        r64 = load_shifted + exmem_store_data_q;
      end
      5'b00100: begin  // AMOXOR
        r32 = a32 ^ b32;
        r64 = load_shifted ^ exmem_store_data_q;
      end
      5'b01000: begin  // AMOOR
        r32 = a32 | b32;
        r64 = load_shifted | exmem_store_data_q;
      end
      5'b01100: begin  // AMOAND
        r32 = a32 & b32;
        r64 = load_shifted & exmem_store_data_q;
      end
      5'b10000: begin  // AMOMIN
        r32 = ($signed(a32) < $signed(b32)) ? a32 : b32;
        r64 = ($signed(load_shifted) < $signed(exmem_store_data_q))
              ? load_shifted : exmem_store_data_q;
      end
      5'b10100: begin  // AMOMAX
        r32 = ($signed(a32) > $signed(b32)) ? a32 : b32;
        r64 = ($signed(load_shifted) > $signed(exmem_store_data_q))
              ? load_shifted : exmem_store_data_q;
      end
      5'b11000: begin  // AMOMINU
        r32 = (a32 < b32) ? a32 : b32;
        r64 = (load_shifted < exmem_store_data_q)
              ? load_shifted : exmem_store_data_q;
      end
      5'b11100: begin  // AMOMAXU
        r32 = (a32 > b32) ? a32 : b32;
        r64 = (load_shifted > exmem_store_data_q)
              ? load_shifted : exmem_store_data_q;
      end
      default: begin  // AMOSWAP
        r32 = b32;
        r64 = exmem_store_data_q;
      end
    endcase
    eff_store_data = exmem_ctrl_q.amo
        ? ((exmem_ctrl_q.funct3 == 3'b010) ? {32'd0, r32} : r64)
        : exmem_store_data_q;
  end
  // "Reserve exactly enough to cover the access": an SC
  // succeeds iff its whole access lies within the LR's range.
  assign sc_success = res_valid_q && (res_pa_q == mmu_d_pa) &&
                      (res_is_d_q || (exmem_ctrl_q.funct3 == 3'b010));

  always_comb begin
    dmem_be_o = 8'd0;
    dmem_wdata_o = 64'd0;
    if (walk_grant && walk_we) begin
      // PTE A/D writeback (suppressed on PMP denial; the MMU
      // turns that into an access fault for the requester).
      dmem_be_o = pmp_allow_walk ? 8'hFF : 8'd0;
      dmem_wdata_o = walk_wdata;
    end else if (mem_uses_port && exmem_ctrl_q.mem_write && !trap_fire &&
                 (!exmem_ctrl_q.sc || sc_success)) begin
      unique case (exmem_ctrl_q.funct3[1:0])
        2'b00: begin
          dmem_be_o = 8'h01 << exmem_addr_q[2:0];
          dmem_wdata_o = {8{eff_store_data[7:0]}};
        end
        2'b01: begin
          dmem_be_o = 8'h03 << {exmem_addr_q[2:1], 1'b0};
          dmem_wdata_o = {4{eff_store_data[15:0]}};
        end
        2'b10: begin
          dmem_be_o = 8'h0F << {exmem_addr_q[2], 2'b00};
          dmem_wdata_o = {2{eff_store_data[31:0]}};
        end
        default: begin
          dmem_be_o = 8'hFF;
          dmem_wdata_o = eff_store_data;
        end
      endcase
    end
  end

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

  assign mem_result = exmem_ctrl_q.sc ? (sc_success ? 64'd0 : 64'd1)
                    : exmem_ctrl_q.mem_read ?
                        ((exmem_ctrl_q.fp_rd && !exmem_ctrl_q.fmt_d) ?
                            {32'hFFFF_FFFF, load_shifted[31:0]} :
                            load_data)
                    : exmem_result_q;

  // LR/SC reservation (physical address + access size). Set
  // by a completing LR; cleared by any SC attempt, by a
  // store/AMO overlapping the reserved bytes, and on traps.
  logic        mem_completes;
  logic [63:0] store_end, res_end;
  assign mem_completes = data_access && !mem_stall && !mem_exc && !freeze;
  assign store_end = mmu_d_pa + (64'd1 << exmem_ctrl_q.funct3[1:0]);
  assign res_end = res_pa_q + (res_is_d_q ? 64'd8 : 64'd4);
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      res_valid_q <= 1'b0;
      res_pa_q <= 64'd0;
      res_is_d_q <= 1'b0;
    end else if (trap_take) begin
      res_valid_q <= 1'b0;
    end else if (mem_completes) begin
      if (exmem_ctrl_q.lr) begin
        res_valid_q <= 1'b1;
        res_pa_q <= mmu_d_pa;
        res_is_d_q <= (exmem_ctrl_q.funct3 == 3'b011);
      end else if (exmem_ctrl_q.sc) begin
        res_valid_q <= 1'b0;
      end else if (exmem_ctrl_q.mem_write && res_valid_q &&
                   (mmu_d_pa < res_end) && (res_pa_q < store_end)) begin
        res_valid_q <= 1'b0;
      end
    end
  end
  always_comb begin
    if (exmem_exc_q) begin
      mem_exc = exmem_valid_q;
      mem_cause = exmem_cause_q;
      mem_tval = exmem_tval_q;
      mem_gpa = exmem_gpa_q;
    end else if (mem_trans_fault) begin
      mem_exc = 1'b1;
      mem_cause = exmem_ctrl_q.mem_write
          ? (mmu_d_fault_guest ? 64'd23 :
             mmu_d_fault_page ? 64'd15 : 64'd7)
          : (mmu_d_fault_guest ? 64'd21 :
             mmu_d_fault_page ? 64'd13 : 64'd5);
      mem_tval = exmem_addr_q;  // faulting VA
      mem_gpa = mmu_d_fault_gpa;
    end else if (mem_pmp_fault) begin
      mem_exc = 1'b1;
      mem_cause = exmem_ctrl_q.mem_write ? 64'd7 : 64'd5;
      mem_tval = exmem_addr_q;
      mem_gpa = 64'd0;
    end else begin
      mem_exc = 1'b0;
      mem_cause = 64'd0;
      mem_tval = 64'd0;
      mem_gpa = 64'd0;
    end
  end

  // ------------------------------------------------------------
  // CSR / privileged unit
  // ------------------------------------------------------------
  muserisc_csr u_csr (
      .clk_i         (clk_i),
      .rst_ni        (rst_ni),
      .addr_i        (csr_addr),
      .rdata_o       (csr_rdata),
      .illegal_o     (csr_illegal),
      .wr_en_i       (csr_we),  // module itself suppresses illegal writes
      .frm_o         (csr_frm),
      .fs_o          (csr_fs),
      .fflags_we_i   (csr_fflags_we),
      .fflags_i      (fpu_flags),
      .fp_dirty_i    (fp_dirty),
      .wdata_i       (csr_wdata),
      .sys_illegal_o (sys_illegal),
      .sys_op_i      (sys_op),
      .ret_en_i      (ex_ret && !trap_fire && !mem_exc && !mem_stall),
      .trap_take_i   (trap_take),
      .trap_cause_i  (memwb_cause_q),
      .trap_pc_i     (memwb_pc_q),
      .trap_tval_i   (memwb_tval_q),
      .trap_gpa_i    (memwb_gpa_q),
      .trap_tinst_i  (64'd0),  // zero is a legal htinst/mtinst value
      .trap_target_o (trap_target),
      .trap_priv_o   (trap_priv_unused),
      .irq_valid_o   (irq_valid),
      .irq_cause_o   (irq_cause),
      .irq_m_timer_i (irq_m_timer_i),
      .irq_m_soft_i  (irq_m_soft_i),
      .irq_m_ext_i   (irq_m_ext_i),
      .irq_s_timer_i (irq_s_timer_i),
      .irq_s_ext_i   (irq_s_ext_i),
      .priv_o        (priv),
      .virt_o        (virt),
      .dvirt_o       (dvirt),
      .virt_inst_o   (csr_virt_inst),
      .sum_o         (csr_sum),
      .mxr_o         (csr_mxr),
      .hs_mxr_o      (csr_hs_mxr),
      .satp_o        (csr_satp),
      .hgatp_o       (csr_hgatp),
      .mstatus_o     (csr_mstatus),
      .xret_pc_o     (xret_pc),
      .retire_i      (memwb_valid_q && !memwb_exc_q && !mem_stall),
      .pmp_addr_a_i  (mmu_if_pa),
      .pmp_acc_a_i   (2'd2),
      .pmp_priv_a_i  (priv),
      .pmp_allow_a_o (pmp_allow_fetch),
      .pmp_addr_b_i  (mmu_d_pa),
      .pmp_acc_b_i   (exmem_ctrl_q.mem_write ? 2'd1 : 2'd0),
      .pmp_priv_b_i  (eff_priv_data),
      .pmp_allow_b_o (pmp_allow_data),
      .pmp_addr_c_i  (walk_addr),
      .pmp_acc_c_i   (walk_acc),
      .pmp_priv_c_i  (2'b01),  // implicit PTE accesses check as S
      .pmp_allow_c_o (pmp_allow_walk)
  );

  // ------------------------------------------------------------
  // MMU (Sv39 + Svnapot TLB and walker)
  // ------------------------------------------------------------
  muserisc_mmu u_mmu (
      .clk_i            (clk_i),
      .rst_ni           (rst_ni),
      .satp_i           (csr_satp),
      .hgatp_i          (csr_hgatp),
      .sum_i            (csr_sum),
      .mxr_i            (csr_mxr),
      .hs_mxr_i         (csr_hs_mxr),
      .flush_i          (sfence_fire),
      .abort_i          (trap_take),
      .if_va_i          (fetch_va),
      .if_priv_i        (priv),
      .if_virt_i        (virt),
      .if_pa_o          (mmu_if_pa),
      .if_ok_o          (mmu_if_ok),
      .if_fault_o       (mmu_if_fault),
      .if_fault_page_o  (mmu_if_fault_page),
      .if_fault_guest_o (mmu_if_fault_guest),
      .if_fault_gpa_o   (mmu_if_fault_gpa),
      .d_va_i           (exmem_addr_q),
      .d_write_i        (exmem_ctrl_q.mem_write),
      .d_priv_i         (eff_priv_data),
      .d_virt_i         (dvirt),
      .d_valid_i        (data_access),
      .d_pa_o           (mmu_d_pa),
      .d_ok_o           (mmu_d_ok),
      .d_fault_o        (mmu_d_fault),
      .d_fault_page_o   (mmu_d_fault_page),
      .d_fault_guest_o  (mmu_d_fault_guest),
      .d_fault_gpa_o    (mmu_d_fault_gpa),
      .walk_req_o       (walk_req),
      .walk_addr_o      (walk_addr),
      .walk_we_o        (walk_we),
      .walk_wdata_o     (walk_wdata),
      .walk_acc_o       (walk_acc),
      .walk_grant_i     (walk_grant),
      .walk_rdata_i     (dmem_rdata_i),
      .walk_pmp_allow_i (pmp_allow_walk)
  );

  // ------------------------------------------------------------
  // PC and pipeline registers
  // ------------------------------------------------------------
  always_comb begin
    if (flush)                             pc_d = redirect_pc;
    else if (stall || freeze || fetch_stall || straddle_enter)
                                           pc_d = pc_q;
    else if (fetch_fault)                  pc_d = pc_q + 64'd4;
    else                                   pc_d = pc_q +
                                                 (fetch_rvc ? 64'd2
                                                            : 64'd4);
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pc_q <= boot_pc_i;
      ifid_valid_q <= 1'b0;
      idex_valid_q <= 1'b0;
      exmem_valid_q <= 1'b0;
      memwb_valid_q <= 1'b0;
      ifid_pc_q <= 64'd0;
      ifid_instr_q <= 32'd0;
      ifid_exc_q <= 1'b0;
      ifid_cause_q <= 64'd0;
      ifid_rvc_q <= 1'b0;
      ifid_parcel_q <= 16'd0;
      ifid_tval_q <= 64'd0;
      ifid_gpa_q <= 64'd0;
      straddle_q <= 1'b0;
      straddle_lo_q <= 16'd0;
      idex_rvc_q <= 1'b0;
      idex_pc_q <= 64'd0;
      idex_ctrl_q <= '0;
      idex_imm_q <= 64'd0;
      idex_instr_q <= 32'd0;
      idex_rs1_q <= 64'd0;
      idex_rs2_q <= 64'd0;
      idex_rs1_addr_q <= 5'd0;
      idex_rs2_addr_q <= 5'd0;
      idex_rd_q <= 5'd0;
      idex_exc_q <= 1'b0;
      idex_cause_q <= 64'd0;
      idex_tval_q <= 64'd0;
      idex_gpa_q <= 64'd0;
      exmem_pc_q <= 64'd0;
      exmem_ctrl_q <= '0;
      exmem_result_q <= 64'd0;
      exmem_addr_q <= 64'd0;
      exmem_store_data_q <= 64'd0;
      exmem_rd_q <= 5'd0;
      exmem_exc_q <= 1'b0;
      exmem_cause_q <= 64'd0;
      exmem_tval_q <= 64'd0;
      exmem_gpa_q <= 64'd0;
      memwb_pc_q <= 64'd0;
      memwb_result_q <= 64'd0;
      memwb_rd_q <= 5'd0;
      memwb_reg_write_q <= 1'b0;
      memwb_exc_q <= 1'b0;
      memwb_cause_q <= 64'd0;
      memwb_tval_q <= 64'd0;
      memwb_gpa_q <= 64'd0;
    end else if (trap_take) begin
      // Precise trap entry: redirect and empty the pipeline,
      // including any half-fetched straddled instruction.
      pc_q <= trap_target;
      straddle_q <= 1'b0;
      ifid_valid_q <= 1'b0;
      idex_valid_q <= 1'b0;
      exmem_valid_q <= 1'b0;
      memwb_valid_q <= 1'b0;
      ifid_exc_q <= 1'b0;
    end else if (!freeze && !mem_stall) begin
      // (mem_stall holds every pipeline register; the parked
      // MEM access retries once its translation resolves.)
      pc_q <= pc_d;

      memwb_valid_q <= exmem_valid_q;
      memwb_pc_q <= exmem_pc_q;
      memwb_result_q <= mem_result;
      memwb_rd_q <= exmem_rd_q;
      memwb_reg_write_q <= exmem_ctrl_q.reg_write;
      memwb_fp_write_q <= exmem_ctrl_q.fp_rd;
      memwb_exc_q <= mem_exc;
      memwb_cause_q <= mem_cause;
      memwb_tval_q <= mem_tval;
      memwb_gpa_q <= mem_gpa;

      exmem_valid_q <= idex_valid_q;
      exmem_pc_q <= idex_pc_q;
      exmem_ctrl_q <= idex_ctrl_q;
      exmem_result_q <= ex_result;
      exmem_addr_q <= alu_result;
      exmem_store_data_q <= idex_ctrl_q.fp_rs2 ? ex_frs2 : ex_rs2;
      exmem_rd_q <= idex_rd_q;
      exmem_exc_q <= ex_exc;
      exmem_cause_q <= ex_cause;
      exmem_tval_q <= ex_tval;
      exmem_gpa_q <= ex_gpa;

      if (stall || flush) begin
        idex_valid_q <= 1'b0;
      end else if (irq_inject) begin
        // The fetched instruction has not executed; epc will
        // point at it so it re-executes after the handler.
        idex_valid_q <= 1'b1;
        idex_pc_q <= ifid_pc_q;
        idex_ctrl_q <= '0;
        idex_imm_q <= 64'd0;
        idex_instr_q <= 32'd0;
        idex_rvc_q <= 1'b0;
        idex_rs1_q <= 64'd0;
        idex_rs2_q <= 64'd0;
        idex_rs1_addr_q <= 5'd0;
        idex_rs2_addr_q <= 5'd0;
        idex_rd_q <= 5'd0;
        idex_exc_q <= 1'b1;
        idex_cause_q <= irq_cause;
        idex_tval_q <= 64'd0;
        idex_gpa_q <= 64'd0;
      end else begin
        idex_valid_q <= ifid_valid_q;
        idex_pc_q <= ifid_pc_q;
        idex_ctrl_q <= ifid_exc_q ? '0 : id_ctrl;
        idex_imm_q <= id_imm;
        idex_instr_q <= ifid_rvc_q ? {16'b0, ifid_parcel_q}
                                   : ifid_instr_q;
        idex_rvc_q <= ifid_rvc_q;
        idex_rs1_q <= id_rs1_val;
        idex_rs2_q <= id_rs2_val;
        idex_frs1_q <= id_frs1_val;
        idex_frs2_q <= id_frs2_val;
        idex_frs3_q <= id_frs3_val;
        idex_rs3_addr_q <= id_rs3;
        idex_rs1_addr_q <= id_rs1;
        idex_rs2_addr_q <= id_rs2;
        idex_rd_q <= id_rd;
        idex_exc_q <= id_exc;
        idex_cause_q <= id_cause;
        idex_tval_q <= id_tval;
        idex_gpa_q <= id_gpa;
      end

      if (flush) begin
        ifid_valid_q <= 1'b0;
        ifid_exc_q <= 1'b0;
        straddle_q <= 1'b0;
      end else if (!stall && !fetch_stall) begin
        if (straddle_enter) begin
          // Hold the low parcel; complete it next cycle.
          ifid_valid_q <= 1'b0;
          ifid_exc_q <= 1'b0;
          straddle_q <= 1'b1;
          straddle_lo_q <= parcel16;
        end else begin
          ifid_valid_q <= 1'b1;
          ifid_pc_q <= pc_q;
          ifid_instr_q <= fetch_fault ? 32'd0 : fetch_instr;
          ifid_exc_q <= fetch_fault;
          ifid_cause_q <= fetch_cause;
          ifid_rvc_q <= fetch_rvc && !fetch_fault;
          ifid_parcel_q <= parcel16;
          ifid_tval_q <= fetch_tval;
          ifid_gpa_q <= mmu_if_fault_guest ? mmu_if_fault_gpa : 64'd0;
          straddle_q <= 1'b0;
        end
      end else if (fetch_stall && !stall) begin
        // Walker is resolving this PC: bubble ID until it lands.
        ifid_valid_q <= 1'b0;
        ifid_exc_q <= 1'b0;
      end
    end
  end
endmodule
`default_nettype wire
