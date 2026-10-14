// Sv39 + Svnapot MMU for the in-house core (issue #18 stage 3b).
//
// One unified 32-entry fully-associative TLB with two
// combinational lookup ports (fetch and data) and a single
// page-table walker that borrows the core's data-memory port.
// Data misses preempt fetch walks (the MEM instruction is older
// and stalls the whole pipeline); fetch walks yield the port
// to MEM accesses cycle by cycle via walk_grant_i.
//
// Policies:
// - Translation is on iff satp.MODE == Sv39 and the effective
//   privilege is S or U; otherwise VA passes through as PA.
// - Hardware A/D update (Svadu semantics): the walker writes
//   the leaf PTE back with A (and D for stores) set. A TLB hit
//   with A=0 — impossible after a fill — or a store hit with
//   D=0 re-enters the walker to perform the update.
// - SFENCE.VMA flushes the whole TLB (operands ignored; a full
//   flush is always a legal implementation of any SFENCE).
// - Faults are reported as page faults or access faults
//   (PTE-access PMP denial); the core picks the cause code
//   from the access type. The physical-address PMP check on
//   the translated address itself stays in the core.
`default_nettype none
module muserisc_mmu (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire [63:0] satp_i,
    input  wire        sum_i,
    input  wire        mxr_i,
    input  wire        flush_i,        // SFENCE commits: clear TLB + walk
    input  wire        abort_i,        // trap taken: kill walk + fault state
    // Fetch lookup (priv = current privilege, access = execute)
    input  wire [63:0] if_va_i,
    input  wire [1:0]  if_priv_i,
    output logic [63:0] if_pa_o,
    output logic       if_ok_o,        // PA usable this cycle
    output logic       if_fault_o,     // definitive fault this cycle
    output logic       if_fault_page_o,
    // Data lookup
    input  wire [63:0] d_va_i,
    input  wire        d_write_i,
    input  wire [1:0]  d_priv_i,
    input  wire        d_valid_i,
    output logic [63:0] d_pa_o,
    output logic       d_ok_o,
    output logic       d_fault_o,
    output logic       d_fault_page_o,
    // Walker memory port (muxed onto the core data port)
    output logic       walk_req_o,     // wants the port this cycle
    output logic [63:0] walk_addr_o,
    output logic       walk_we_o,      // A/D writeback (8-byte store)
    output logic [63:0] walk_wdata_o,
    output logic [1:0]  walk_acc_o,    // PMP access class: 0 read, 1 write
    input  wire        walk_grant_i,   // port granted: consume rdata
    input  wire [63:0] walk_rdata_i,
    input  wire        walk_pmp_allow_i
);
  // ------------------------------------------------------------
  // TLB (32 entries, fully associative, round-robin fill)
  // ------------------------------------------------------------
  typedef struct packed {
    logic        valid;
    logic [15:0] asid;
    logic [26:0] vpn;     // VA[38:12]
    logic [43:0] ppn;     // PA[55:12]
    logic [1:0]  level;   // leaf level: 0 = 4K, 1 = 2M, 2 = 1G
    logic        napot;   // 64K contiguous (level 0 only)
    logic        r, w, x, u, g, a, d;
  } tlb_entry_t;

  tlb_entry_t tlb_q [0:31];
  logic [4:0]  fill_ptr_q;

  logic        satp_sv39;
  logic [15:0] satp_asid;
  assign satp_sv39 = (satp_i[63:60] == 4'd8);
  assign satp_asid = satp_i[59:44];

  /* verilator lint_off UNUSEDSIGNAL */  // low VA bits pass through PA muxes
  // (Expression form, no early returns: Verilator attributes no
  // coverage to return statements in inlined functions.)
  function automatic logic entry_match(
      input tlb_entry_t e, input logic [63:0] va, input logic [15:0] asid);
    logic [26:0] vpn;
    vpn = va[38:12];
    entry_match = e.valid && (e.g || (e.asid == asid)) &&
        ((e.level == 2'd2) ? (vpn[26:18] == e.vpn[26:18]) :
         (e.level == 2'd1) ? (vpn[26:9] == e.vpn[26:9]) :
         e.napot           ? (vpn[26:4] == e.vpn[26:4]) :
                             (vpn == e.vpn));
  endfunction

  function automatic logic [63:0] entry_pa(
      input tlb_entry_t e, input logic [63:0] va);
    entry_pa = (e.level == 2'd2) ? {8'd0, e.ppn[43:18], va[29:0]} :
               (e.level == 2'd1) ? {8'd0, e.ppn[43:9], va[20:0]} :
               e.napot           ? {8'd0, e.ppn[43:4], va[15:0]} :
                                   {8'd0, e.ppn, va[11:0]};
  endfunction

  // Permission of an access against one leaf/TLB entry.
  // acc: 0 read, 1 write, 2 execute.
  function automatic logic perm_ok(
      input tlb_entry_t e, input logic [1:0] priv,
      input logic [1:0] acc, input logic sum, input logic mxr);
    logic u_ok, rwx_ok;
    if (priv == 2'b00)      u_ok = e.u;                 // U needs U=1
    else if (acc == 2'd2)   u_ok = !e.u;                // S fetch: U=0
    else                    u_ok = !e.u || sum;         // S data
    if (acc == 2'd2)        rwx_ok = e.x;
    else if (acc == 2'd1)   rwx_ok = e.w;
    else                    rwx_ok = e.r || (mxr && e.x);
    return u_ok && rwx_ok;
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  /* verilator lint_off UNUSEDSIGNAL */  // only the VPN slices are inputs
  function automatic logic canonical(input logic [63:0] va);
    return (va[63:39] == {25{va[38]}});
  endfunction

  // Find a matching entry; returns its index (valid bit = bit 5).
  function automatic logic [5:0] find_entry(
      input logic [63:0] va, input logic [15:0] asid);
    find_entry = 6'd0;
    for (int i = 0; i < 32; i++) begin
      if (entry_match(tlb_q[i], va, asid)) begin
        find_entry = {1'b1, 5'(i)};
      end
    end
  endfunction

  /* verilator lint_on UNUSEDSIGNAL */

  // ------------------------------------------------------------
  // Lookups
  // ------------------------------------------------------------
  // Recorded walk fault (held until the core consumes it; killed
  // by abort/flush, and only ever matched against the faulting VA).
  logic        wf_valid_q, wf_is_data_q, wf_page_q;
  logic [63:0] wf_va_q;

  logic        if_trans, d_trans;
  assign if_trans = satp_sv39 && (if_priv_i != 2'b11);
  assign d_trans  = satp_sv39 && (d_priv_i != 2'b11);

  always_comb begin
    logic [5:0] f;
    tlb_entry_t e;
    if_pa_o = if_va_i;
    if_ok_o = 1'b0;
    if_fault_o = 1'b0;
    if_fault_page_o = 1'b1;
    f = find_entry(if_va_i, satp_asid);
    e = tlb_q[f[4:0]];
    if (!if_trans) begin
      if_ok_o = 1'b1;
    end else if (!canonical(if_va_i)) begin
      if_fault_o = 1'b1;
    end else if (f[5]) begin
      if_pa_o = entry_pa(e, if_va_i);
      if (!perm_ok(e, if_priv_i, 2'd2, sum_i, mxr_i)) if_fault_o = 1'b1;
      else if (e.a) if_ok_o = 1'b1;  // A=0 re-walks (cannot happen post-fill)
    end else if (wf_valid_q && !wf_is_data_q && (wf_va_q == if_va_i)) begin
      if_fault_o = 1'b1;
      if_fault_page_o = wf_page_q;
    end
  end

  always_comb begin
    logic [5:0] f;
    tlb_entry_t e;
    d_pa_o = d_va_i;
    d_ok_o = 1'b0;
    d_fault_o = 1'b0;
    d_fault_page_o = 1'b1;
    f = find_entry(d_va_i, satp_asid);
    e = tlb_q[f[4:0]];
    if (!d_trans) begin
      d_ok_o = 1'b1;
    end else if (!canonical(d_va_i)) begin
      d_fault_o = d_valid_i;
    end else if (f[5]) begin
      d_pa_o = entry_pa(e, d_va_i);
      if (!perm_ok(e, d_priv_i, d_write_i ? 2'd1 : 2'd0, sum_i, mxr_i)) begin
        d_fault_o = d_valid_i;
      end else if (e.a && (!d_write_i || e.d)) begin
        d_ok_o = 1'b1;
      end
    end else if (wf_valid_q && wf_is_data_q && (wf_va_q == d_va_i)) begin
      d_fault_o = d_valid_i;
      d_fault_page_o = wf_page_q;
    end
  end

  logic miss_f, miss_d;
  assign miss_f = if_trans && !if_ok_o && !if_fault_o;
  assign miss_d = d_valid_i && d_trans && !d_ok_o && !d_fault_o;

  // ------------------------------------------------------------
  // Page-table walker
  // ------------------------------------------------------------
  typedef enum logic [1:0] {W_IDLE, W_READ, W_UPD} walk_state_e;
  walk_state_e state_q;
  logic        req_is_data_q;
  logic [63:0] req_va_q;
  logic [1:0]  req_acc_q, req_priv_q, level_q;
  logic [15:0] req_asid_q;
  logic [63:0] pte_addr_q, pte_q;

  assign walk_req_o = (state_q != W_IDLE);
  assign walk_addr_o = pte_addr_q;
  assign walk_we_o = (state_q == W_UPD);
  assign walk_acc_o = (state_q == W_UPD) ? 2'd1 : 2'd0;

  // Combinational leaf evaluation of the PTE on the port.
  // (PTE RSW bits [9:8] are software's; the walker ignores them.)
  /* verilator lint_off UNUSEDSIGNAL */
  logic        pte_leaf, pte_fault, pte_needs_upd;
  tlb_entry_t  fill_entry;
  always_comb begin
    logic [63:0] pte;
    pte = walk_rdata_i;
    pte_leaf = pte[1] || pte[3];                       // R or X
    pte_fault = 1'b0;
    if (!pte[0] || (!pte[1] && pte[2])) pte_fault = 1'b1;   // !V, W w/o R
    if (pte[62:54] != 9'd0) pte_fault = 1'b1;               // PBMT/reserved
    if (!pte_leaf && (pte[7] || pte[6] || pte[4])) begin
      pte_fault = 1'b1;                                     // non-leaf D/A/U
    end
    if (!pte_leaf && (level_q == 2'd0)) pte_fault = 1'b1;
    if (pte[63] && !(pte_leaf && (level_q == 2'd0) &&
                     (pte[13:10] == 4'b1000))) begin
      pte_fault = 1'b1;                                     // bad NAPOT use of N
    end
    if (pte_leaf && (level_q == 2'd2) && (pte[27:10] != 18'd0)) begin
      pte_fault = 1'b1;                                     // misaligned 1G
    end
    if (pte_leaf && (level_q == 2'd1) && (pte[18:10] != 9'd0)) begin
      pte_fault = 1'b1;                                     // misaligned 2M
    end
    // Candidate TLB entry (also used for the permission check).
    fill_entry = '0;
    fill_entry.valid = 1'b1;
    fill_entry.asid = req_asid_q;
    fill_entry.vpn = req_va_q[38:12];
    fill_entry.ppn = pte[53:10];
    fill_entry.level = level_q;
    fill_entry.napot = pte[63];
    fill_entry.r = pte[1];
    fill_entry.w = pte[2];
    fill_entry.x = pte[3];
    fill_entry.u = pte[4];
    fill_entry.g = pte[5];
    fill_entry.a = 1'b1;  // walker guarantees A/D before filling
    fill_entry.d = pte[7] || (req_acc_q == 2'd1);
    if (pte_leaf && !pte_fault &&
        !perm_ok(fill_entry, req_priv_q, req_acc_q, sum_i, mxr_i)) begin
      pte_fault = 1'b1;
    end
    pte_needs_upd = !pte[6] || ((req_acc_q == 2'd1) && !pte[7]);
  end
  assign walk_wdata_o = pte_q | (64'd1 << 6) |
                        ((req_acc_q == 2'd1) ? (64'd1 << 7) : 64'd0);

  // Fill target: reuse an existing (A/D-stale) entry for this VA
  // so a re-walk never leaves a duplicate for lookups to find.
  logic [5:0] exist_f;
  logic [4:0] fill_idx;
  assign exist_f = find_entry(req_va_q, req_asid_q);
  assign fill_idx = exist_f[5] ? exist_f[4:0] : fill_ptr_q;

  /* verilator lint_off UNUSEDSIGNAL */  // only the VPN slice is read
  function automatic logic [63:0] pte_addr(
      input logic [43:0] base_ppn, input logic [63:0] va,
      input logic [1:0] level);
    logic [8:0] vpn_i;
    if (level == 2'd2)      vpn_i = va[38:30];
    else if (level == 2'd1) vpn_i = va[29:21];
    else                    vpn_i = va[20:12];
    return {8'd0, base_ppn, 12'd0} + {52'd0, vpn_i, 3'd0};
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= W_IDLE;
      fill_ptr_q <= 5'd0;
      wf_valid_q <= 1'b0;
      req_is_data_q <= 1'b0;
      req_va_q <= 64'd0;
      req_acc_q <= 2'd0;
      req_priv_q <= 2'd0;
      req_asid_q <= 16'd0;
      level_q <= 2'd0;
      pte_addr_q <= 64'd0;
      pte_q <= 64'd0;
      wf_is_data_q <= 1'b0;
      wf_page_q <= 1'b1;
      wf_va_q <= 64'd0;
      for (int i = 0; i < 32; i++) tlb_q[i] <= '0;
    end else if (flush_i || abort_i) begin
      state_q <= W_IDLE;
      wf_valid_q <= 1'b0;
      if (flush_i) begin
        for (int i = 0; i < 32; i++) tlb_q[i].valid <= 1'b0;
      end
    end else begin
      // A recorded fault lives only while its port still presents
      // the faulting VA; anything else would negative-cache it.
      if (wf_valid_q &&
          ((wf_is_data_q && (d_va_i != wf_va_q)) ||
           (!wf_is_data_q && (if_va_i != wf_va_q)))) begin
        wf_valid_q <= 1'b0;
      end
      unique case (state_q)
        W_IDLE: begin
          if (miss_d) begin
            state_q <= W_READ;
            req_is_data_q <= 1'b1;
            req_va_q <= d_va_i;
            req_acc_q <= d_write_i ? 2'd1 : 2'd0;
            req_priv_q <= d_priv_i;
            req_asid_q <= satp_asid;
            level_q <= 2'd2;
            pte_addr_q <= pte_addr(satp_i[43:0], d_va_i, 2'd2);
            wf_valid_q <= 1'b0;
          end else if (miss_f) begin
            state_q <= W_READ;
            req_is_data_q <= 1'b0;
            req_va_q <= if_va_i;
            req_acc_q <= 2'd2;
            req_priv_q <= if_priv_i;
            req_asid_q <= satp_asid;
            level_q <= 2'd2;
            pte_addr_q <= pte_addr(satp_i[43:0], if_va_i, 2'd2);
            wf_valid_q <= 1'b0;
          end
        end
        W_READ: begin
          // An older data miss preempts a fetch walk.
          if (!req_is_data_q && miss_d) begin
            req_is_data_q <= 1'b1;
            req_va_q <= d_va_i;
            req_acc_q <= d_write_i ? 2'd1 : 2'd0;
            req_priv_q <= d_priv_i;
            req_asid_q <= satp_asid;
            level_q <= 2'd2;
            pte_addr_q <= pte_addr(satp_i[43:0], d_va_i, 2'd2);
          end else if (walk_grant_i) begin
            if (!walk_pmp_allow_i) begin
              state_q <= W_IDLE;      // implicit-access PMP denial
              wf_valid_q <= 1'b1;
              wf_is_data_q <= req_is_data_q;
              wf_page_q <= 1'b0;
              wf_va_q <= req_va_q;
            end else if (pte_fault) begin
              state_q <= W_IDLE;
              wf_valid_q <= 1'b1;
              wf_is_data_q <= req_is_data_q;
              wf_page_q <= 1'b1;
              wf_va_q <= req_va_q;
            end else if (!pte_leaf) begin
              level_q <= level_q - 2'd1;
              pte_addr_q <= pte_addr(walk_rdata_i[53:10], req_va_q,
                                     level_q - 2'd1);
            end else if (pte_needs_upd) begin
              state_q <= W_UPD;
              pte_q <= walk_rdata_i;
            end else begin
              state_q <= W_IDLE;
              tlb_q[fill_idx] <= fill_entry;
              if (!exist_f[5]) fill_ptr_q <= fill_ptr_q + 5'd1;
            end
          end
        end
        default: begin  // W_UPD (and the unused encoding: recover)
          if (walk_grant_i) begin
            state_q <= W_IDLE;
            if (!walk_pmp_allow_i) begin
              wf_valid_q <= 1'b1;
              wf_is_data_q <= req_is_data_q;
              wf_page_q <= 1'b0;
              wf_va_q <= req_va_q;
            end else begin
              // Rebuild the fill entry from the stored PTE.
              tlb_q[fill_idx].valid <= 1'b1;
              tlb_q[fill_idx].asid <= req_asid_q;
              tlb_q[fill_idx].vpn <= req_va_q[38:12];
              tlb_q[fill_idx].ppn <= pte_q[53:10];
              tlb_q[fill_idx].level <= level_q;
              tlb_q[fill_idx].napot <= pte_q[63];
              tlb_q[fill_idx].r <= pte_q[1];
              tlb_q[fill_idx].w <= pte_q[2];
              tlb_q[fill_idx].x <= pte_q[3];
              tlb_q[fill_idx].u <= pte_q[4];
              tlb_q[fill_idx].g <= pte_q[5];
              tlb_q[fill_idx].a <= 1'b1;
              tlb_q[fill_idx].d <= pte_q[7] || (req_acc_q == 2'd1);
              if (!exist_f[5]) fill_ptr_q <= fill_ptr_q + 5'd1;
            end
          end
        end
      endcase
    end
  end
endmodule
`default_nettype wire
