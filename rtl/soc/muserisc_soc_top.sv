// museRISC synthesizable SoC top (issue #4): in-house
// RV64 core + memory fabric + boot ROM + CLINT + PLIC +
// 16550 UART + muse_crypto accelerator. Memory map matches
// docs/SPEC.md, sw/linux/muserisc.dts, and the C++ model
// in tb/cpp/soc_tb.cpp:
//
//   0x0000_1000  boot ROM (4 KiB, muserisc_bootrom)
//   0x0200_0000  CLINT
//   0x0C00_0000  PLIC (UART = source 10, ext_irq_i ORed in)
//   0x1000_0000  16550 UART
//   0x2000_0000  crypto accelerator (AXI-Lite via bridge)
//   0x8000_0000  external RAM window (mem_* ports)
//
// RAM is intentionally external at this block level: the
// simulation harness, an ASIC SRAM wrapper/chip top, and
// the FPGA BRAM/DDR wrapper each implement the same async-
// read ports. Instruction and data RAM ports are separate
// (Harvard), matching the core; a unified-memory wrapper
// arbitrates externally if it has a single port.
`default_nettype none
module muserisc_soc_top (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire [63:0] boot_pc_i,
    // External RAM, instruction side (async read).
    output wire [63:0] mem_imem_addr_o,
    input  wire [31:0] mem_imem_rdata_i,
    // External RAM, data side (async read, byte-write).
    output wire [63:0] mem_dmem_addr_o,
    output wire        mem_dmem_re_o,
    output wire [7:0]  mem_dmem_be_o,
    output wire [63:0] mem_dmem_wdata_o,
    input  wire [63:0] mem_dmem_rdata_i,
    // UART serial pins + parallel byte stream (host capture).
    output wire        uart_tx_o,
    input  wire        uart_rx_i,
    output wire [7:0]  uart_tx_data_o,
    output wire        uart_tx_valid_o,
    input  wire [7:0]  uart_rx_data_i,
    input  wire        uart_rx_valid_i,
    // Extra PLIC interrupt sources (source 10 is the UART).
    input  wire [31:0] ext_irq_i,
    // Trap observability (test/debug).
    output wire        trap_o,
    output wire [63:0] trap_cause_o,
    output wire [63:0] trap_pc_o
);
  localparam logic [63:0] ROM_BASE    = 64'h0000_1000;
  localparam logic [63:0] CLINT_BASE  = 64'h0200_0000;
  localparam logic [63:0] PLIC_BASE   = 64'h0C00_0000;
  localparam logic [63:0] UART_BASE   = 64'h1000_0000;
  localparam logic [63:0] CRYPTO_BASE = 64'h2000_0000;
  localparam logic [63:0] RAM_BASE    = 64'h8000_0000;

  function automatic logic in_range(
      input logic [63:0] a, input logic [63:0] base,
      input logic [63:0] size);
    return (a >= base) && ((a - base) < size);
  endfunction

  // Core buses.
  logic [63:0] core_imem_addr, core_dmem_addr;
  logic [31:0] core_imem_rdata;
  logic [63:0] core_dmem_rdata, core_dmem_wdata;
  logic [7:0]  core_dmem_be;
  logic        core_dmem_re;
  logic        irq_m_timer, irq_m_soft, irq_m_ext, irq_s_ext;
  logic        crypto_stall;

  // Decodes (data side; instruction side only ROM/RAM).
  logic sel_rom_i, sel_ram_i;
  assign sel_rom_i = in_range(core_imem_addr, ROM_BASE, 64'h1000);
  assign sel_ram_i = (core_imem_addr >= RAM_BASE);
  logic sel_rom_d, sel_clint_d, sel_plic_d, sel_uart_d;
  logic sel_crypto_d, sel_ram_d;
  assign sel_rom_d = in_range(core_dmem_addr, ROM_BASE, 64'h1000);
  assign sel_clint_d = in_range(core_dmem_addr, CLINT_BASE, 64'h1_0000);
  assign sel_plic_d = in_range(core_dmem_addr, PLIC_BASE, 64'h400_0000);
  assign sel_uart_d = in_range(core_dmem_addr, UART_BASE, 64'h100);
  assign sel_crypto_d = in_range(core_dmem_addr, CRYPTO_BASE, 64'h100);
  assign sel_ram_d = (core_dmem_addr >= RAM_BASE);

  assign mem_imem_addr_o = core_imem_addr;
  assign mem_dmem_addr_o = core_dmem_addr;
  assign mem_dmem_re_o = core_dmem_re && sel_ram_d;
  assign mem_dmem_be_o = sel_ram_d ? core_dmem_be : 8'd0;
  assign mem_dmem_wdata_o = core_dmem_wdata;

  logic [31:0] rom_data_i;
  logic [63:0] rom_data_d, clint_rdata, plic_rdata, uart_rdata;
  logic [63:0] crypto_rdata;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [63:0] rom64_unused;
  logic [31:0] rom32_unused;
  /* verilator lint_on UNUSEDSIGNAL */
  muserisc_bootrom u_rom_i (
      .addr_i(core_imem_addr[11:0]), .data_o(rom_data_i),
      .data64_o(rom64_unused));
  muserisc_bootrom u_rom_d (
      .addr_i(core_dmem_addr[11:0]), .data_o(rom32_unused),
      .data64_o(rom_data_d));

  assign core_imem_rdata = sel_rom_i ? rom_data_i :
                           sel_ram_i ? mem_imem_rdata_i : 32'd0;
  always_comb begin
    if (sel_ram_d) core_dmem_rdata = mem_dmem_rdata_i;
    else if (sel_rom_d) core_dmem_rdata = rom_data_d;
    else if (sel_clint_d) core_dmem_rdata = clint_rdata;
    else if (sel_plic_d) core_dmem_rdata = plic_rdata;
    else if (sel_uart_d) core_dmem_rdata = uart_rdata;
    else if (sel_crypto_d) core_dmem_rdata = crypto_rdata;
    else core_dmem_rdata = 64'd0;
  end

  logic uart_irq;
  logic [31:0] plic_sources;
  logic [1:0]  plic_eip;
  assign plic_sources = ext_irq_i | {21'd0, uart_irq, 10'd0};
  assign irq_m_ext = plic_eip[0];
  assign irq_s_ext = plic_eip[1];

  muserisc_clint u_clint (
      .clk_i(clk_i), .rst_ni(rst_ni),
      .addr_i(core_dmem_addr[15:0]),
      .be_i(sel_clint_d ? core_dmem_be : 8'd0),
      .wdata_i(core_dmem_wdata), .rdata_o(clint_rdata),
      .irq_m_timer_o(irq_m_timer), .irq_m_soft_o(irq_m_soft));
  muserisc_plic u_plic (
      .clk_i(clk_i), .rst_ni(rst_ni),
      .addr_i(core_dmem_addr[25:0]),
      .re_i(sel_plic_d && core_dmem_re),
      .be_i(sel_plic_d ? core_dmem_be : 8'd0),
      .wdata_i(core_dmem_wdata), .rdata_o(plic_rdata),
      .irq_sources_i(plic_sources), .eip_o(plic_eip));
  muserisc_uart16550 u_uart (
      .clk_i(clk_i), .rst_ni(rst_ni),
      .addr_i(core_dmem_addr[2:0]),
      .re_i(sel_uart_d && core_dmem_re),
      .be_i(sel_uart_d ? core_dmem_be : 8'd0),
      .wdata_i(core_dmem_wdata), .rdata_o(uart_rdata),
      .irq_o(uart_irq), .tx_o(uart_tx_o), .rx_i(uart_rx_i),
      .tx_data_o(uart_tx_data_o), .tx_valid_o(uart_tx_valid_o),
      .rx_data_i(uart_rx_data_i), .rx_valid_i(uart_rx_valid_i));
  muserisc_crypto_bridge u_crypto_bridge (
      .clk_i(clk_i), .rst_ni(rst_ni),
      .sel_i(sel_crypto_d), .re_i(core_dmem_re),
      .be_i(core_dmem_be), .addr_i(core_dmem_addr[7:0]),
      .wdata_i(core_dmem_wdata), .rdata_o(crypto_rdata),
      .stall_o(crypto_stall));

  muserisc_core u_core (
      .clk_i(clk_i), .rst_ni(rst_ni), .boot_pc_i(boot_pc_i),
      .imem_addr_o(core_imem_addr), .imem_rdata_i(core_imem_rdata),
      .dmem_addr_o(core_dmem_addr), .dmem_wdata_o(core_dmem_wdata),
      .dmem_be_o(core_dmem_be), .dmem_re_o(core_dmem_re),
      .dmem_rdata_i(core_dmem_rdata),
      .dmem_stall_i(crypto_stall),
      .trap_o(trap_o), .trap_cause_o(trap_cause_o),
      .trap_pc_o(trap_pc_o), .trap_halt_i(1'b0),
      .irq_m_timer_i(irq_m_timer), .irq_m_soft_i(irq_m_soft),
      .irq_m_ext_i(irq_m_ext), .irq_s_timer_i(1'b0),
      .irq_s_ext_i(irq_s_ext));
endmodule
`default_nettype wire
