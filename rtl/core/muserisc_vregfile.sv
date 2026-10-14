// Vector register file (issue #23, stage 8): 32 registers of
// VLEN=512 bits. Reads return whole register *groups* (up to
// LMUL=8 consecutive registers, 4096 bits) starting at the
// given register; element 0 is the lowest bits of the first
// register. Writes commit one group in EX under the core's
// precise-trap gating, mirroring how CSR state commits.
`default_nettype none
module muserisc_vregfile
  import muserisc_pkg::*;
(
    input  wire        clk_i,
    // rst is unnecessary: vector registers are uninitialized
    // architecturally (tests write before reading).

    input  wire [4:0]  raddr_a_i,   // vs2 group (instr[24:20])
    output logic [4095:0] rdata_a_o,
    input  wire [4:0]  raddr_b_i,   // vs1 group (instr[19:15])
    output logic [4095:0] rdata_b_o,
    input  wire [4:0]  raddr_c_i,   // vd group (old value)
    output logic [4095:0] rdata_c_o,
    output logic [511:0]  v0_o,     // mask register

    input  wire        we_i,
    input  wire [4:0]  waddr_i,     // vd group base
    input  wire [2:0]  wlmul_i,     // effective LMUL code (0..3 = 1..8)
    input  wire [4095:0] wdata_i
);

  logic [511:0] regs_q [32];

  function automatic logic [4095:0] read_group(input logic [4:0] base);
    read_group = '0;
    for (int i = 0; i < 8; i++) begin
      read_group[i*512 +: 512] = regs_q[(base + 5'(i)) & 5'd31];
    end
  endfunction

  assign rdata_a_o = read_group(raddr_a_i);
  assign rdata_b_o = read_group(raddr_b_i);
  assign rdata_c_o = read_group(raddr_c_i);
  assign v0_o = regs_q[0];

  // Only the registers in the effective group are written;
  // fractional LMUL writes the single destination register.
  logic [3:0] group_n;
  assign group_n = 4'd1 << wlmul_i;

  always_ff @(posedge clk_i) begin
    if (we_i) begin
      for (int i = 0; i < 8; i++) begin
        if (4'(i) < group_n) begin
          regs_q[(waddr_i + 5'(i)) & 5'd31] <= wdata_i[i*512 +: 512];
        end
      end
    end
  end

endmodule
`default_nettype wire
