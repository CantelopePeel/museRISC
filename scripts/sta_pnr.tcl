# Timing report for a placed/routed muserisc_soc_top ORFS stage.
# Run inside the ORFS image through the flow environment, e.g.
#   ./scripts/openroad_docker.sh "FLOW_VARIANT=reg STA_STAGE=6_final \
#       RUN_SCRIPT=designs/muserisc_scripts/sta_pnr.tcl run"
# STA_STAGE: ORFS result stem (3_place, 4_cts, 5_route, 6_final, ...);
# the matching .odb/.sdc are loaded. Parasitics: the stage's SPEF if
# it exists (6_final.spef from the finish stage's RCX extraction),
# else placement estimates.
#
# Reports WNS/TNS at the SDC period, the critical paths, and fmax by
# bisecting the clock period with the design and parasitics fixed
# (no re-optimization), so a path launched by a falling-edge macro
# output (sky130 OpenRAM dout) is timed against its half period at
# every candidate. Also reports the worst path into a few blocks.
set stage $::env(STA_STAGE)
if {[info exists ::env(STA_LIBS)] && $::env(STA_LIBS) ne ""} {
  # Other corner: these liberty files replace the platform's
  # (e.g. sky130 ss_100C_1v60 std cells + the TT-only OpenRAM libs).
  foreach lib $::env(STA_LIBS) {
    read_liberty $lib
  }
  read_db $::env(RESULTS_DIR)/$stage.odb
  read_sdc $::env(RESULTS_DIR)/$stage.sdc
  if {[file exists $::env(PLATFORM_DIR)/setRC.tcl]} {
    source $::env(PLATFORM_DIR)/setRC.tcl
  }
  puts "liberty: $::env(STA_LIBS)"
} else {
  source $::env(SCRIPTS_DIR)/load.tcl
  load_design $stage.odb $stage.sdc
}

set spef $::env(RESULTS_DIR)/$stage.spef
if {[file exists $spef]} {
  puts "parasitics: $spef"
  read_spef $spef
} else {
  puts "parasitics: placement estimate"
  estimate_parasitics -placement
}

set clk [get_clocks core_clock]
set period0 [get_property $clk period]
set unc [expr {[info exists ::env(STA_SETUP_UNC)] ? $::env(STA_SETUP_UNC) : 0.5}]

puts "==== summary at the SDC period ($period0 ns)"
report_worst_slack -max -digits 3
report_worst_slack -min -digits 3
report_tns -digits 3
report_check_types -max_slew -max_capacitance -max_fanout -violators

puts "==== top critical paths at the SDC period"
report_checks -path_delay max -group_path_count 5 -endpoint_path_count 1 \
  -format end -digits 3
report_checks -path_delay max -fields {fanout cap slew} -digits 3

# Post-CTS stages time the propagated (real) clock tree.
set propagated [expr {[string index $stage 0] >= 4}]
proc wns_at {p} {
  global unc propagated
  create_clock -name core_clock -period $p [get_ports clk_i]
  set_clock_uncertainty -setup $unc [get_clocks core_clock]
  if {$propagated} { set_propagated_clock [get_clocks core_clock] }
  return [sta::worst_slack -max]
}
set lo 1.0
set hi 400.0
while {$hi - $lo > 0.02} {
  set mid [expr {($lo + $hi) / 2.0}]
  if {[wns_at $mid] >= 0} { set hi $mid } else { set lo $mid }
}
puts [format "min_period_bisect_ns %.2f  fmax_bisect_mhz %.2f" $hi [expr {1000.0 / $hi}]]
wns_at $hi
puts "==== critical paths at the bisected minimum period"
report_checks -path_delay max -group_path_count 10 -endpoint_path_count 1 \
  -format end -digits 3
report_checks -path_delay max -fields {fanout cap slew} -digits 3

# Worst path into each block at the bisected period.
set all_d [all_registers -data_pins]
foreach p {u_cpu/u_core/u_vec u_cpu/u_core/u_fpu u_cpu/u_core/u_csr
           u_cpu/u_core/u_mmu u_cpu/u_dcache u_cpu/u_icache
           u_cpu/u_core/u_vregfile u_crypto} {
  set eps {}
  foreach pin $all_d {
    set n [string map {. /} [get_full_name $pin]]
    if {[string match "$p/*" $n]} { lappend eps $pin }
  }
  if {[llength $eps] == 0} { continue }
  set path [lindex [find_timing_paths -to $eps -path_delay max \
    -group_path_count 1 -sort_by_slack] 0]
  puts [format "block %-26s endpoints %6d  worst_slack %8.3f  from %s" $p \
    [llength $eps] [get_property $path slack] \
    [get_full_name [get_property $path startpoint]]]
}
wns_at $period0
