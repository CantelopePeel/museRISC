# muse_crypto @ 100 MHz (nangate45). I/O delays are budget placeholders
# until the block is hardened inside the SoC (Phase 2).
create_clock [get_ports clk] -period 10.0 -name core_clock
# Separate setup/hold uncertainty: a combined 0.5ns makes every short
# path a hold violation after CTS (10k+ hold buffers, RSZ-0060).
set_clock_uncertainty -setup 0.5 [get_clocks core_clock]
set_clock_uncertainty -hold 0.05 [get_clocks core_clock]
set_input_delay  2.0 -clock core_clock [all_inputs]
set_output_delay 2.0 -clock core_clock [all_outputs]
