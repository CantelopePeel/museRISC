// Privileged state for the in-house core (issue #18 stage 3):
// M/S/U CSRs, precise trap entry/return, interrupt selection with
// delegation, cycle/instret counters, and 16 PMP entries.
//
// Contract with the pipeline (docs/CORE.md):
// - CSR reads are combinational in EX; writes commit on the
//   EX->MEM edge (wr_en_i), so a following instruction in EX reads
//   the new value next cycle. xRET side effects apply on the same
//   edge; trap entry applies on the WB edge (trap_take_i).
// - Current privilege changes only through trap entry / xRET,
//   both of which flush the pipeline, so priv_o always names the
//   privilege of every instruction currently in flight.
// - satp is stored here; translation itself lives in the MMU.
`default_nettype none
module muserisc_csr (
    input  wire        clk_i,
    input  wire        rst_ni,
    // CSR read/write port (EX)
    input  wire [11:0] addr_i,
    output logic [63:0] rdata_o,
    output logic       illegal_o,     // access faults as illegal-instr
    input  wire        wr_en_i,       // commit wdata_i at the next edge
    input  wire [63:0] wdata_i,
    // Privileged-instruction legality helpers (EX)
    output logic       sys_illegal_o, // mret/sret/wfi/sfence not allowed now
    input  wire [2:0]  sys_op_i,      // 0 none 1 mret 2 sret 3 wfi 4 sfence
    input  wire        ret_en_i,      // xRET takes effect at the next edge
    // Trap entry (WB)
    input  wire        trap_take_i,
    input  wire [63:0] trap_cause_i,  // full xcause value (bit63 = interrupt)
    input  wire [63:0] trap_pc_i,
    input  wire [63:0] trap_tval_i,
    output logic [63:0] trap_target_o,
    output logic [1:0] trap_priv_o,   // privilege the trap is taken to
    // Interrupt injection (sampled in ID)
    output logic       irq_valid_o,
    output logic [63:0] irq_cause_o,  // full xcause value (interrupt bit set)
    // External interrupt pins
    input  wire        irq_m_timer_i,
    input  wire        irq_m_soft_i,
    input  wire        irq_m_ext_i,
    input  wire        irq_s_timer_i,
    input  wire        irq_s_ext_i,
    // State outputs
    output logic [1:0] priv_o,
    output logic [63:0] satp_o,
    output logic [63:0] mstatus_o,
    output logic [63:0] xret_pc_o,    // mepc or sepc per sys_op_i
    input  wire        retire_i,      // an instruction retired in WB
    // PMP checks (physical addresses, combinational)
    input  wire [63:0] pmp_addr_a_i,
    input  wire [1:0]  pmp_acc_a_i,   // 0 read 1 write 2 exec
    input  wire [1:0]  pmp_priv_a_i,
    output logic       pmp_allow_a_o,
    input  wire [63:0] pmp_addr_b_i,
    input  wire [1:0]  pmp_acc_b_i,
    input  wire [1:0]  pmp_priv_b_i,
    output logic       pmp_allow_b_o,
    input  wire [63:0] pmp_addr_c_i,
    input  wire [1:0]  pmp_acc_c_i,
    input  wire [1:0]  pmp_priv_c_i,
    output logic       pmp_allow_c_o
);
  localparam logic [1:0] PRIV_U = 2'b00, PRIV_S = 2'b01, PRIV_M = 2'b11;

  // ------------------------------------------------------------
  // Architectural state
  // ------------------------------------------------------------
  logic [1:0]  priv_q;
  // mstatus fields actually stored
  logic mstatus_mie_q, mstatus_sie_q, mstatus_mpie_q, mstatus_spie_q;
  logic mstatus_spp_q;
  logic [1:0] mstatus_mpp_q;
  logic mstatus_mprv_q, mstatus_sum_q, mstatus_mxr_q;
  logic mstatus_tvm_q, mstatus_tw_q, mstatus_tsr_q;
  logic [63:0] medeleg_q, mideleg_q, mie_q, mtvec_q, mcounteren_q;
  logic [63:0] mscratch_q, mepc_q, mcause_q, mtval_q;
  logic        mip_ssip_q, mip_seip_q, mip_stip_q;
  logic [63:0] menvcfg_q, mcountinhibit_q;
  logic [63:0] stvec_q, scounteren_q, sscratch_q, sepc_q, scause_q;
  logic [63:0] stval_q, senvcfg_q, satp_q;
  logic [63:0] mcycle_q, minstret_q;
  logic [7:0]  pmpcfg_q [0:15];
  logic [63:0] pmpaddr_q [0:15];

  assign priv_o = priv_q;
  assign satp_o = satp_q;

  // mstatus assembly (unlisted fields read zero).
  always_comb begin
    mstatus_o = 64'd0;
    mstatus_o[1]     = mstatus_sie_q;
    mstatus_o[3]     = mstatus_mie_q;
    mstatus_o[5]     = mstatus_spie_q;
    mstatus_o[7]     = mstatus_mpie_q;
    mstatus_o[8]     = mstatus_spp_q;
    mstatus_o[12:11] = mstatus_mpp_q;
    mstatus_o[17]    = mstatus_mprv_q;
    mstatus_o[18]    = mstatus_sum_q;
    mstatus_o[19]    = mstatus_mxr_q;
    mstatus_o[20]    = mstatus_tvm_q;
    mstatus_o[21]    = mstatus_tw_q;
    mstatus_o[22]    = mstatus_tsr_q;
    mstatus_o[35:34] = 2'b10;  // SXL = 64-bit
    mstatus_o[33:32] = 2'b10;  // UXL = 64-bit
  end

  localparam logic [63:0] SSTATUS_MASK =
      (64'd1 << 1) | (64'd1 << 5) | (64'd1 << 8) |
      (64'd1 << 18) | (64'd1 << 19) | (64'd3 << 32);

  // mip assembly: pin-driven fields plus software SSIP/SEIP.
  logic [63:0] mip_val;
  always_comb begin
    mip_val = 64'd0;
    mip_val[1]  = mip_ssip_q;
    mip_val[3]  = irq_m_soft_i;
    mip_val[5]  = irq_s_timer_i | mip_stip_q;
    mip_val[7]  = irq_m_timer_i;
    mip_val[9]  = irq_s_ext_i | mip_seip_q;
    mip_val[11] = irq_m_ext_i;
  end

  // ------------------------------------------------------------
  // Read mux + legality
  // ------------------------------------------------------------
  logic        csr_exists;
  logic [63:0] csr_rdata;
  // Composed pmpcfg views (RV64: cfg0 holds entries 0-7, cfg2 8-15).
  logic [63:0] pmpcfg0_val, pmpcfg2_val;
  always_comb begin
    for (int i = 0; i < 8; i++) begin
      pmpcfg0_val[i*8 +: 8] = pmpcfg_q[i];
      pmpcfg2_val[i*8 +: 8] = pmpcfg_q[i+8];
    end
  end

  always_comb begin
    csr_exists = 1'b1;
    csr_rdata = 64'd0;
    unique case (addr_i)
      12'h100: csr_rdata = mstatus_o & SSTATUS_MASK;              // sstatus
      12'h104: csr_rdata = mie_q & mideleg_q;                     // sie
      12'h105: csr_rdata = stvec_q;                               // stvec
      12'h106: csr_rdata = scounteren_q;                          // scounteren
      12'h10A: csr_rdata = senvcfg_q;                             // senvcfg
      12'h140: csr_rdata = sscratch_q;                            // sscratch
      12'h141: csr_rdata = sepc_q;                                // sepc
      12'h142: csr_rdata = scause_q;                              // scause
      12'h143: csr_rdata = stval_q;                               // stval
      12'h144: csr_rdata = mip_val & mideleg_q;                   // sip
      12'h180: csr_rdata = satp_q;                                // satp
      12'h300: csr_rdata = mstatus_o;                             // mstatus
      12'h301: csr_rdata = 64'h8000_0000_0014_1101;               // misa: RV64 IMA SU
      12'h302: csr_rdata = medeleg_q;                             // medeleg
      12'h303: csr_rdata = mideleg_q;                             // mideleg
      12'h304: csr_rdata = mie_q;                                 // mie
      12'h305: csr_rdata = mtvec_q;                               // mtvec
      12'h306: csr_rdata = mcounteren_q;                          // mcounteren
      12'h30A: csr_rdata = menvcfg_q;                             // menvcfg
      12'h320: csr_rdata = mcountinhibit_q;                       // mcountinhibit
      12'h340: csr_rdata = mscratch_q;                            // mscratch
      12'h341: csr_rdata = mepc_q;                                // mepc
      12'h342: csr_rdata = mcause_q;                              // mcause
      12'h343: csr_rdata = mtval_q;                               // mtval
      12'h344: csr_rdata = mip_val;                               // mip
      12'h3A0: csr_rdata = pmpcfg0_val;                           // pmpcfg0
      12'h3A2: csr_rdata = pmpcfg2_val;                           // pmpcfg2
      12'hB00: csr_rdata = mcycle_q;                              // mcycle
      12'hB02: csr_rdata = minstret_q;                            // minstret
      12'hC00: csr_rdata = mcycle_q;                              // cycle
      12'hC01: csr_rdata = mcycle_q;                              // time
      12'hC02: csr_rdata = minstret_q;                            // instret
      12'hF11: csr_rdata = 64'd0;                                 // mvendorid
      12'hF12: csr_rdata = 64'h4D55_5345;                         // marchid "MUSE"
      12'hF13: csr_rdata = 64'h0003_0000;                         // mimpid
      12'hF14: csr_rdata = 64'd0;                                 // mhartid
      12'hF15: csr_rdata = 64'd0;                                 // mconfigptr
      default: begin
        if ((addr_i >= 12'h3B0) && (addr_i <= 12'h3BF)) begin
          csr_rdata = pmpaddr_q[addr_i[3:0]];
        end else if ((addr_i >= 12'hB03) && (addr_i <= 12'hB1F)) begin
          csr_rdata = 64'd0;                                      // mhpmcounter3-31
        end else if ((addr_i >= 12'h323) && (addr_i <= 12'h33F)) begin
          csr_rdata = 64'd0;                                      // mhpmevent3-31
        end else if (((addr_i >= 12'h7A0) && (addr_i <= 12'h7A5)) ||
                     (addr_i == 12'h7A8) || (addr_i == 12'h7AA) ||
                     (addr_i == 12'h5A8)) begin
          // Sdtrig trigger CSRs, zero triggers implemented:
          // tselect/tdata*/tinfo/tcontrol/context all read 0
          // (tinfo.type = none), writes are ignored.
          csr_rdata = 64'd0;
        end else begin
          csr_exists = 1'b0;
        end
      end
    endcase
  end

  logic csr_priv_ok, csr_write_attempt;
  assign csr_priv_ok = (priv_q >= addr_i[9:8]);
  // The core only asserts wr_en_i for actual writes; read-only
  // CSRs (addr[11:10]==2'b11) fault on any write attempt.
  assign csr_write_attempt = wr_en_i;
  // Counter access control: mcounteren gates S and U reads of
  // the unprivileged counters (0xC00-0xC1F), scounteren gates U.
  logic counter_blocked;
  always_comb begin
    counter_blocked = 1'b0;
    if ((addr_i[11:5] == 7'h60) && (priv_q != PRIV_M)) begin
      if (!mcounteren_q[{1'b0, addr_i[4:0]}]) counter_blocked = 1'b1;
      if ((priv_q == PRIV_U) && !scounteren_q[{1'b0, addr_i[4:0]}]) begin
        counter_blocked = 1'b1;
      end
    end
  end
  // TVM: satp access from S-mode is illegal while TVM=1.
  assign illegal_o = !csr_exists || !csr_priv_ok || counter_blocked ||
                     ((addr_i == 12'h180) && (priv_q == PRIV_S) &&
                      mstatus_tvm_q) ||
                     (csr_write_attempt && (addr_i[11:10] == 2'b11));
  assign rdata_o = csr_rdata;

  // xRET/WFI/SFENCE legality in the current privilege.
  always_comb begin
    unique case (sys_op_i)
      3'd1: sys_illegal_o = (priv_q != PRIV_M);                   // MRET
      3'd2: sys_illegal_o = (priv_q == PRIV_U) ||
                            ((priv_q == PRIV_S) && mstatus_tsr_q); // SRET
      3'd3: sys_illegal_o = (priv_q != PRIV_M) && mstatus_tw_q;   // WFI/TW
      3'd4: sys_illegal_o = (priv_q == PRIV_U) ||
                            ((priv_q == PRIV_S) && mstatus_tvm_q); // SFENCE/TVM
      default: sys_illegal_o = 1'b0;
    endcase
  end

  assign xret_pc_o = (sys_op_i == 3'd2) ? sepc_q : mepc_q;

  // ------------------------------------------------------------
  // Interrupt selection
  // ------------------------------------------------------------
  logic [63:0] pend_m, pend_s;
  logic [63:0] sel_cause_m, sel_cause_s;
  assign pend_m = mip_val & mie_q & ~mideleg_q;
  assign pend_s = mip_val & mie_q & mideleg_q;

  /* verilator lint_off UNUSEDSIGNAL */  // pend has only 6 live bits
  function automatic logic [63:0] pick_irq(input logic [63:0] pend);
    if (pend[11])      pick_irq = 64'd11;
    else if (pend[3])  pick_irq = 64'd3;
    else if (pend[7])  pick_irq = 64'd7;
    else if (pend[9])  pick_irq = 64'd9;
    else if (pend[1])  pick_irq = 64'd1;
    else if (pend[5])  pick_irq = 64'd5;
    else               pick_irq = 64'd0;
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  assign sel_cause_m = pick_irq(pend_m);
  assign sel_cause_s = pick_irq(pend_s);

  logic take_m, take_s;
  assign take_m = (pend_m != 64'd0) &&
                  ((priv_q < PRIV_M) || mstatus_mie_q);
  assign take_s = !take_m && (pend_s != 64'd0) &&
                  ((priv_q < PRIV_S) ||
                   ((priv_q == PRIV_S) && mstatus_sie_q));
  assign irq_valid_o = take_m || take_s;
  assign irq_cause_o = {1'b1, 63'd0} | (take_m ? sel_cause_m : sel_cause_s);

  // ------------------------------------------------------------
  // Trap target (delegated traps go to S when taken from S/U)
  // ------------------------------------------------------------
  logic        trap_is_irq;
  logic [5:0]  trap_code;
  logic        trap_to_s;
  assign trap_is_irq = trap_cause_i[63];
  assign trap_code = trap_cause_i[5:0];
  always_comb begin
    if (priv_q == PRIV_M) begin
      trap_to_s = 1'b0;
    end else if (trap_is_irq) begin
      trap_to_s = mideleg_q[trap_code];
    end else begin
      trap_to_s = medeleg_q[trap_code];
    end
  end
  assign trap_priv_o = trap_to_s ? PRIV_S : PRIV_M;
  always_comb begin
    if (trap_to_s) begin
      trap_target_o = {stvec_q[63:2], 2'b00} +
          ((stvec_q[1:0] == 2'b01) && trap_is_irq
               ? {56'd0, trap_code, 2'b00} : 64'd0);
    end else begin
      trap_target_o = {mtvec_q[63:2], 2'b00} +
          ((mtvec_q[1:0] == 2'b01) && trap_is_irq
               ? {56'd0, trap_code, 2'b00} : 64'd0);
    end
  end

  // ------------------------------------------------------------
  // PMP (16 entries, grain 4 bytes)
  // ------------------------------------------------------------
  // PMP compares in the pmpaddr domain (PA[55:2], 54 bits); the
  // unused input bits (byte offsets, cfg permission bits consumed
  // by the caller) are inherent to the interface.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic pmp_match(
      input logic [63:0] addr,
      input logic [7:0]  cfg,
      input logic [63:0] pmpaddr,
      input logic [63:0] prev_pmpaddr);
    logic [53:0] a54, enc, prev, napot_mask;
    a54 = addr[55:2];
    enc = pmpaddr[53:0];
    prev = prev_pmpaddr[53:0];
    napot_mask = enc ^ (enc + 54'd1);  // trailing-ones span, incl. the 0 above
    unique case (cfg[4:3])
      2'b00:   pmp_match = 1'b0;                                    // OFF
      2'b01:   pmp_match = (a54 >= prev) && (a54 < enc);            // TOR
      2'b10:   pmp_match = (a54 == enc);                            // NA4
      default: pmp_match = ((a54 ^ enc) & ~napot_mask) == 54'd0;    // NAPOT
    endcase
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  function automatic logic pmp_check(
      input logic [63:0] addr,
      input logic [1:0]  acc,
      input logic [1:0]  priv);
    logic allow;
    allow = (priv == PRIV_M);
    for (int i = 15; i >= 0; i--) begin
      if (pmp_match(addr, pmpcfg_q[i], pmpaddr_q[i],
                    (i == 0) ? 64'd0 : pmpaddr_q[i-1])) begin
        if ((priv == PRIV_M) && !pmpcfg_q[i][7]) begin
          allow = 1'b1;
        end else if (acc == 2'd0) begin
          allow = pmpcfg_q[i][0];
        end else if (acc == 2'd1) begin
          allow = pmpcfg_q[i][1];
        end else begin
          allow = pmpcfg_q[i][2];
        end
      end
    end
    return allow;
  endfunction

  assign pmp_allow_a_o = pmp_check(pmp_addr_a_i, pmp_acc_a_i, pmp_priv_a_i);
  assign pmp_allow_b_o = pmp_check(pmp_addr_b_i, pmp_acc_b_i, pmp_priv_b_i);
  assign pmp_allow_c_o = pmp_check(pmp_addr_c_i, pmp_acc_c_i, pmp_priv_c_i);

  // PMP write locking: an entry is locked by its own L bit, and
  // pmpaddr[i] is also locked when entry i+1 is a locked TOR entry
  // (pmpaddr[i] forms its lower bound).
  function automatic logic pmp_locked(input int idx);
    pmp_locked = pmpcfg_q[idx][7] ||
        ((idx < 15) && pmpcfg_q[idx+1][7] &&
         (pmpcfg_q[idx+1][4:3] == 2'b01));
  endfunction

  // ------------------------------------------------------------
  // Sequential updates: CSR writes, xRET, trap entry, counters
  // ------------------------------------------------------------
  logic [1:0] ret_priv;
  assign ret_priv = (sys_op_i == 3'd2) ? {1'b0, mstatus_spp_q} : mstatus_mpp_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      priv_q <= PRIV_M;
      mstatus_mie_q <= 1'b0;
      mstatus_sie_q <= 1'b0;
      mstatus_mpie_q <= 1'b0;
      mstatus_spie_q <= 1'b0;
      mstatus_spp_q <= 1'b0;
      mstatus_mpp_q <= 2'b00;
      mstatus_mprv_q <= 1'b0;
      mstatus_sum_q <= 1'b0;
      mstatus_mxr_q <= 1'b0;
      mstatus_tvm_q <= 1'b0;
      mstatus_tw_q <= 1'b0;
      mstatus_tsr_q <= 1'b0;
      medeleg_q <= 64'd0;
      mideleg_q <= 64'd0;
      mie_q <= 64'd0;
      mtvec_q <= 64'd0;
      mcounteren_q <= 64'd0;
      mscratch_q <= 64'd0;
      mepc_q <= 64'd0;
      mcause_q <= 64'd0;
      mtval_q <= 64'd0;
      mip_ssip_q <= 1'b0;
      mip_seip_q <= 1'b0;
      mip_stip_q <= 1'b0;
      menvcfg_q <= 64'd0;
      mcountinhibit_q <= 64'd0;
      stvec_q <= 64'd0;
      scounteren_q <= 64'd0;
      sscratch_q <= 64'd0;
      sepc_q <= 64'd0;
      scause_q <= 64'd0;
      stval_q <= 64'd0;
      senvcfg_q <= 64'd0;
      satp_q <= 64'd0;
      mcycle_q <= 64'd0;
      minstret_q <= 64'd0;
      for (int i = 0; i < 16; i++) begin
        pmpcfg_q[i] <= 8'd0;
        pmpaddr_q[i] <= 64'd0;
      end
    end else begin
      // Free-running counters (inhibit bits honored).
      if (!mcountinhibit_q[0]) mcycle_q <= mcycle_q + 64'd1;
      if (retire_i && !mcountinhibit_q[2]) begin
        minstret_q <= minstret_q + 64'd1;
      end

      if (trap_take_i) begin
        priv_q <= trap_priv_o;
        if (trap_to_s) begin
          sepc_q <= trap_pc_i;
          scause_q <= trap_cause_i;
          stval_q <= trap_tval_i;
          mstatus_spie_q <= mstatus_sie_q;
          mstatus_sie_q <= 1'b0;
          mstatus_spp_q <= priv_q[0];
        end else begin
          mepc_q <= trap_pc_i;
          mcause_q <= trap_cause_i;
          mtval_q <= trap_tval_i;
          mstatus_mpie_q <= mstatus_mie_q;
          mstatus_mie_q <= 1'b0;
          mstatus_mpp_q <= priv_q;
        end
        // MPRV is NOT cleared by trap entry (only by an xRET
        // returning to a non-M mode, below).
      end else if (ret_en_i) begin
        // xRET (sys_op 1 = MRET, 2 = SRET)
        priv_q <= ret_priv;
        if (sys_op_i == 3'd1) begin
          mstatus_mie_q <= mstatus_mpie_q;
          mstatus_mpie_q <= 1'b1;
          mstatus_mpp_q <= 2'b00;
          if (ret_priv != PRIV_M) mstatus_mprv_q <= 1'b0;
        end else begin
          mstatus_sie_q <= mstatus_spie_q;
          mstatus_spie_q <= 1'b1;
          mstatus_spp_q <= 1'b0;
        end
      end else if (wr_en_i && !illegal_o) begin
        unique case (addr_i)
          12'h100: begin  // sstatus: writable S-visible fields only
            mstatus_sie_q <= wdata_i[1];
            mstatus_spie_q <= wdata_i[5];
            mstatus_spp_q <= wdata_i[8];
            mstatus_sum_q <= wdata_i[18];
            mstatus_mxr_q <= wdata_i[19];
          end
          12'h104: mie_q <= (mie_q & ~mideleg_q) | (wdata_i & mideleg_q);
          12'h105: stvec_q <= {wdata_i[63:2], (wdata_i[1:0] < 2'd2) ? wdata_i[1:0] : 2'd0};
          12'h106: scounteren_q <= wdata_i & 64'h7;  // CY|TM|IR exist
          12'h10A: senvcfg_q <= wdata_i;
          12'h140: sscratch_q <= wdata_i;
          12'h141: sepc_q <= {wdata_i[63:2], 2'b00};
          12'h142: scause_q <= wdata_i;
          12'h143: stval_q <= wdata_i;
          12'h144: mip_ssip_q <= wdata_i[1];
          12'h180: begin  // satp MODE is WARL: only Bare/Sv39 stick
            if ((wdata_i[63:60] == 4'd0) || (wdata_i[63:60] == 4'd8)) begin
              satp_q <= wdata_i;
            end
          end
          12'h300: begin  // mstatus
            mstatus_sie_q <= wdata_i[1];
            mstatus_mie_q <= wdata_i[3];
            mstatus_spie_q <= wdata_i[5];
            mstatus_mpie_q <= wdata_i[7];
            mstatus_spp_q <= wdata_i[8];
            mstatus_mpp_q <= (wdata_i[12:11] == 2'b10) ? 2'b00 : wdata_i[12:11];
            mstatus_mprv_q <= wdata_i[17];
            mstatus_sum_q <= wdata_i[18];
            mstatus_mxr_q <= wdata_i[19];
            mstatus_tvm_q <= wdata_i[20];
            mstatus_tw_q <= wdata_i[21];
            mstatus_tsr_q <= wdata_i[22];
          end
          12'h302: medeleg_q <= wdata_i & 64'hB35D;
          12'h303: mideleg_q <= wdata_i & 64'h222;
          12'h304: mie_q <= wdata_i & 64'hAAA;
          12'h305: mtvec_q <= {wdata_i[63:2], (wdata_i[1:0] < 2'd2) ? wdata_i[1:0] : 2'd0};
          12'h306: mcounteren_q <= wdata_i & 64'h7;  // CY|TM|IR exist
          12'h30A: menvcfg_q <= wdata_i;
          12'h320: mcountinhibit_q <= wdata_i & 64'h5;  // CY|IR exist
          12'h340: mscratch_q <= wdata_i;
          12'h341: mepc_q <= {wdata_i[63:2], 2'b00};
          12'h342: mcause_q <= wdata_i;
          12'h343: mtval_q <= wdata_i;
          12'h344: begin
            mip_ssip_q <= wdata_i[1];
            mip_stip_q <= wdata_i[5];
            mip_seip_q <= wdata_i[9];
          end
          12'h3A0: begin
            for (int i = 0; i < 8; i++) begin
              if (!pmpcfg_q[i][7]) begin
                // Bits 6:5 are reserved (read zero); W without R
                // is reserved: clear W and X (WARL, matching
                // Sail's PMP_ClearPermissions).
                pmpcfg_q[i] <= wdata_i[i*8 +: 8] &
                               ((wdata_i[i*8+1] && (wdata_i[i*8] == 1'b0)) ? 8'h99 : 8'h9F);
              end
            end
          end
          12'h3A2: begin
            for (int i = 0; i < 8; i++) begin
              if (!pmpcfg_q[i+8][7]) begin
                pmpcfg_q[i+8] <= wdata_i[i*8 +: 8] &
                                 ((wdata_i[i*8+1] && (wdata_i[i*8] == 1'b0)) ? 8'h99 : 8'h9F);
              end
            end
          end
          12'hB00: mcycle_q <= wdata_i;
          12'hB02: minstret_q <= wdata_i;
          default: begin
            if ((addr_i >= 12'h3B0) && (addr_i <= 12'h3BF)) begin
              if (!pmp_locked(int'(addr_i[3:0]))) begin
                pmpaddr_q[addr_i[3:0]] <= {10'd0, wdata_i[53:0]};
              end
            end
            // mhpmcounter/mhpmevent and read-only CSRs: ignored or
            // already faulted via illegal_o.
          end
        endcase
      end
    end
  end
endmodule
`default_nettype wire
