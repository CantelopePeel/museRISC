# Post-synthesis OpenSTA report for muserisc_soc_top (any platform).
# Run inside the ORFS image with the platform/design env loaded, e.g.
#   openroad -exit -no_init sta_synth.tcl
# Env: STA_LIBS (liberty files), STA_ODB (1_synth.odb), STA_SDC,
#      STA_PREFIXES (hierarchical instance prefixes to report the
#      worst path into, e.g. "u_core/u_vec u_core/u_fpu").
# No placement yet: delays use the liberty wire-load model (no
# parasitics), and no timing repair has been applied, so this is
# the raw synthesized logic depth, not a closure result.
foreach lib $::env(STA_LIBS) {
  read_liberty $lib
}
read_db $::env(STA_ODB)
read_sdc $::env(STA_SDC)

puts "==== summary"
report_wns -digits 3
report_tns -digits 3
set period [get_property [get_clocks core_clock] period]
set wns [sta::worst_slack -max]
set crit [expr {$period - $wns}]
puts [format "crit_path_ns %.3f (period %.3f, worst slack %.3f, setup uncertainty included)" \
  $crit $period $wns]
puts [format "fmax_mhz %.2f" [expr {1000.0 / $crit}]]

puts "==== critical path"
report_checks -path_delay max -format full -fields {fanout} -digits 3

# Setup endpoints (register data and enable pins, not async
# set/reset) whose
# instance path matches one of the include globs and none of the
# exclude globs. Kept modules use "/" in instance names, flattened
# submodules "."; both are normalized to "/" before matching.
set all_d [all_registers -data_pins]
proc endpoints {incl excl} {
  global all_d
  set eps {}
  foreach pin $all_d {
    set n [string map {. /} [get_full_name $pin]]
    if {[regexp {/(RN|SN|RESET_B|SET_B)$} $n]} {
      continue
    }
    set ok 0
    foreach g $incl {
      if {[string match $g $n]} { set ok 1 }
    }
    foreach g $excl {
      if {[string match $g $n]} { set ok 0 }
    }
    if {$ok} { lappend eps $pin }
  }
  return $eps
}
proc report_block {label eps} {
  global period
  if {[llength $eps] == 0} {
    puts "block $label: no register endpoints found"
    return
  }
  set path [lindex [find_timing_paths -to $eps -path_delay max \
    -group_path_count 1 -sort_by_slack] 0]
  set slack [get_property $path slack]
  puts [format "block %-20s endpoints %6d  worst_slack %9.3f  arrival_ns %8.3f  from %s  to %s" \
    $label [llength $eps] $slack [expr {$period - 0.5 - $slack}] \
    [get_full_name [get_property $path startpoint]] \
    [get_full_name [get_property $path endpoint]]]
}

puts "==== worst path per block (endpoints inside the prefix)"
foreach p $::env(STA_PREFIXES) {
  report_block $p [endpoints [list "$p/*"] {}]
}
# Next tier once the vector unit (combinational fp_eval element
# step) is set aside.
report_block "(all but vec)" \
  [endpoints {*} {u_cpu/u_core/u_vec/*}]

puts "==== worst path outside the vector unit"
report_checks -to [endpoints {*} {u_cpu/u_core/u_vec/*}] -path_delay max -digits 3

# Fmax by bisection on the clock period. `period - WNS` is only right
# when every critical path is a full-cycle path; macros with
# falling-edge outputs (sky130 OpenRAM dout) launch half-cycle paths
# whose budget scales with the period, so re-time at each candidate.
proc wns_at {p} {
  create_clock -name core_clock -period $p [get_ports clk_i]
  set_clock_uncertainty -setup 0.5 [get_clocks core_clock]
  return [sta::worst_slack -max]
}
set lo 1.0
set hi 2000.0
while {$hi - $lo > 0.05} {
  set mid [expr {($lo + $hi) / 2.0}]
  if {[wns_at $mid] >= 0} { set hi $mid } else { set lo $mid }
}
puts [format "min_period_bisect_ns %.2f  fmax_bisect_mhz %.2f" $hi [expr {1000.0 / $hi}]]
wns_at $hi
puts "==== critical path at the bisected minimum period"
report_checks -path_delay max -path_group core_clock -digits 3

# Same, restricted to paths launched on the rising edge (i.e. what
# fmax would be if the falling-edge macro outputs were registered).
proc wns_rise_at {p} {
  create_clock -name core_clock -period $p [get_ports clk_i]
  set_clock_uncertainty -setup 0.5 [get_clocks core_clock]
  set path [lindex [find_timing_paths -rise_from [get_clocks core_clock] \
    -path_delay max -group_path_count 1 -sort_by_slack] 0]
  return [get_property $path slack]
}
set lo 1.0
set hi 2000.0
while {$hi - $lo > 0.05} {
  set mid [expr {($lo + $hi) / 2.0}]
  if {[wns_rise_at $mid] >= 0} { set hi $mid } else { set lo $mid }
}
puts [format "min_period_rise_launch_ns %.2f  fmax_rise_launch_mhz %.2f" $hi [expr {1000.0 / $hi}]]
wns_rise_at $hi
puts "==== worst rising-edge-launched path at that period"
report_checks -rise_from [get_clocks core_clock] -path_delay max -digits 3
