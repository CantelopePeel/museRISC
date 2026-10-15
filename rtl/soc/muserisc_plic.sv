// RISC-V PLIC subset: 32 sources, 2 contexts (0=M, 1=S,
// hart 0), SiFive register layout as modelled in
// tb/cpp/soc_tb.cpp and sw/linux/muserisc.dts. Bus is the
// core's aligned-64-bit data word (see muserisc_clint).
// Registers are 32-bit word accesses (as the Linux PLIC
// driver issues); claim/complete is at ctx_base+4: a load
// completing with re_i claims (side effect at the clock
// edge), a store completes. Level sources re-pend after
// completion while still asserted.
`default_nettype none
module muserisc_plic (
    input  wire        clk_i,
    input  wire        rst_ni,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [25:0] addr_i,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire        re_i,
    input  wire [7:0]  be_i,
    input  wire [63:0] wdata_i,
    output wire [63:0] rdata_o,
    input  wire [31:0] irq_sources_i,
    output wire [1:0]  eip_o
);
  logic [31:0] prio_q [0:31];
  logic [31:0] enable_q [0:1];
  logic [31:0] threshold_q [0:1];
  logic [31:0] claimed_q;

  logic [31:0] pending;
  assign pending = irq_sources_i & ~claimed_q;

  function automatic logic ctx_eip(input logic ctx);
    logic r;
    r = 1'b0;
    for (int s = 1; s < 32; s++) begin
      if (pending[s] && enable_q[ctx][s] &&
          (prio_q[s] > threshold_q[ctx])) r = 1'b1;
    end
    return r;
  endfunction
  assign eip_o = {ctx_eip(1), ctx_eip(0)};

  // Highest-priority claimable source (ties: lowest id,
  // matching the C++ model). 0 = none.
  function automatic logic [31:0] best_source(input logic ctx);
    logic [31:0] best, best_prio;
    best = 32'd0;
    best_prio = 32'd0;
    for (int s = 1; s < 32; s++) begin
      if (pending[s] && enable_q[ctx][s] &&
          (prio_q[s] > threshold_q[ctx]) &&
          (best == 32'd0 || prio_q[s] > best_prio)) begin
        best = s[31:0];
        best_prio = prio_q[s];
      end
    end
    return best;
  endfunction

  // One 32-bit PLIC register by word-aligned byte offset.
  function automatic logic [31:0] plic_word(input logic [25:0] off);
    logic [31:0] r;
    r = 32'd0;
    if (off < 26'h80) r = prio_q[off[6:2]];
    else if (off == 26'h1000) r = pending;
    else if (off == 26'h2000) r = enable_q[0];
    else if (off == 26'h2080) r = enable_q[1];
    else if (off == 26'h20_0000) r = threshold_q[0];
    else if (off == 26'h20_1000) r = threshold_q[1];
    else if (off == 26'h20_0004) r = re_i ? best_source(0) : 32'd0;
    else if (off == 26'h20_1004) r = re_i ? best_source(1) : 32'd0;
    return r;
  endfunction

  logic [25:0] align_off, word_off;
  assign align_off = {addr_i[25:3], 3'b000};
  assign word_off = {addr_i[25:2], 2'b00};
  assign rdata_o = {plic_word(align_off + 26'd4),
                    plic_word(align_off)};

  logic        is_claim0, is_claim1, is_claim;
  logic [31:0] claim_val, store_word;
  assign is_claim0 = (word_off == 26'h20_0004);
  assign is_claim1 = (word_off == 26'h20_1004);
  assign is_claim = is_claim0 || is_claim1;
  assign claim_val = is_claim0 ? best_source(0) :
                     is_claim1 ? best_source(1) : 32'd0;
  assign store_word = addr_i[2] ? wdata_i[63:32] : wdata_i[31:0];

  function automatic logic [31:0] merge_word(
      input logic [31:0] cur, input logic [63:0] wdata,
      input logic [7:0] be, input logic hi);
    logic [31:0] r;
    r = cur;
    for (int i = 0; i < 4; i++) begin
      if (be[i + (hi ? 4 : 0)]) begin
        r[8*i +: 8] = wdata[8*(i + (hi ? 4 : 0)) +: 8];
      end
    end
    return r;
  endfunction

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int s = 0; s < 32; s++) prio_q[s] <= 32'd0;
      enable_q[0] <= 32'd0;
      enable_q[1] <= 32'd0;
      threshold_q[0] <= 32'd0;
      threshold_q[1] <= 32'd0;
      claimed_q <= 32'd0;
    end else begin
      if (re_i && is_claim && claim_val != 32'd0) begin
        claimed_q[claim_val[4:0]] <= 1'b1;
      end
      if (be_i != 8'd0) begin
        if (is_claim) begin
          if (store_word < 32'd32) claimed_q[store_word[4:0]] <= 1'b0;
        end else if (word_off < 26'h80) begin
          prio_q[word_off[6:2]] <=
              merge_word(prio_q[word_off[6:2]], wdata_i, be_i,
                         addr_i[2]);
        end else if (word_off == 26'h2000) begin
          enable_q[0] <= merge_word(enable_q[0], wdata_i, be_i,
                                     addr_i[2]);
        end else if (word_off == 26'h2080) begin
          enable_q[1] <= merge_word(enable_q[1], wdata_i, be_i,
                                     addr_i[2]);
        end else if (word_off == 26'h20_0000) begin
          threshold_q[0] <= merge_word(threshold_q[0], wdata_i,
                                        be_i, addr_i[2]);
        end else if (word_off == 26'h20_1000) begin
          threshold_q[1] <= merge_word(threshold_q[1], wdata_i,
                                        be_i, addr_i[2]);
        end
      end
    end
  end
endmodule
`default_nettype wire
