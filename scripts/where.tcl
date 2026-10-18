# debug helper: print location of a few instances in a stage odb, and rows near a point
source $::env(SCRIPTS_DIR)/load.tcl
read_db $::env(RESULTS_DIR)/$::env(STA_STAGE).odb
set b [ord::get_db_block]
foreach n $::env(WHERE_INSTS) {
  set i [$b findInst $n]
  if {$i eq "NULL"} { puts "$n: not found"; continue }
  set bb [$i getBBox]
  puts [format "%s %s %.1f %.1f %s" $n [[$i getMaster] getName] [ord::dbu_to_microns [$bb xMin]] [ord::dbu_to_microns [$bb yMin]] [$i getPlacementStatus]]
}
if {[info exists ::env(WHERE_XY)]} {
  lassign $::env(WHERE_XY) px py
  set px [ord::microns_to_dbu $px]; set py [ord::microns_to_dbu $py]
  set n 0
  foreach r [$b getRows] {
    set bb [$r getBBox]
    if {[$bb yMin] <= $py + 20000 && [$bb yMax] >= $py - 20000} {
      puts [format "row %s x %.1f..%.1f y %.2f" [$r getName] [ord::dbu_to_microns [$bb xMin]] [ord::dbu_to_microns [$bb xMax]] [ord::dbu_to_microns [$bb yMin]]]
      incr n
    }
  }
  puts "rows near: $n"
  # std-cell area density in 100x100 um tiles over the whole core
  array set A {}
  foreach i [$b getInsts] {
    if {[[$i getMaster] isBlock]} { continue }
    set bb [$i getBBox]
    set k "[expr {[$bb xMin]/100000}],[expr {[$bb yMin]/100000}]"
    if {![info exists A($k)]} { set A($k) 0 }
    set A($k) [expr {$A($k) + [$bb getDX]*[$bb getDY]/1e6}]
  }
  set l {}
  foreach k [array names A] { lappend l [list $k $A($k)] }
  foreach e [lrange [lsort -real -decreasing -index 1 $l] 0 15] { puts "tile [lindex $e 0] area [format %.0f [lindex $e 1]] um2 of 10000" }
}
