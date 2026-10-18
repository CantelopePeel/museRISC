# Manual macro placement for muserisc_soc_top on nangate45
# (MACRO_PLACEMENT_TCL). fakeram45 macros have every signal pin on
# their left edge, so the left column (L1 data ways) is mirrored (MY)
# to face the core and the right column (VRF banks, then the L1 tag
# ways) is placed R0. Columns are centred vertically in the core area,
# so DIE_AREA/CORE_AREA can change without editing this file.
set block [ord::get_db_block]
set core [$block getCoreArea]
set cx0 [ord::dbu_to_microns [$core xMin]]
set cy0 [ord::dbu_to_microns [$core yMin]]
set cx1 [ord::dbu_to_microns [$core xMax]]
set cy1 [ord::dbu_to_microns [$core yMax]]

proc mp_find {pattern} {
  set r {}
  foreach inst [[ord::get_db_block] getInsts] {
    if {[[$inst getMaster] isBlock] && [string match $pattern [$inst getName]]} {
      lappend r [$inst getName]
    }
  }
  return [lsort -dictionary $r]
}
proc mp_size {name} {
  set m [[[ord::get_db_block] findInst $name] getMaster]
  return [list [ord::dbu_to_microns [$m getWidth]] [ord::dbu_to_microns [$m getHeight]]]
}
# Snap to the placement site grid (FreePDK45 0.19 x 1.4).
proc mp_place {name x y orient} {
  set x [expr {round($x / 0.19) * 0.19}]
  set y [expr {round($y / 1.4) * 1.4}]
  puts "muserisc macro: $name at ($x, $y) $orient"
  place_macro -macro_name $name -location [list $x $y] -orientation $orient
}
# Stack a list of macros in a column at x, centred on the core.
proc mp_column {names x orient gap} {
  global cy0 cy1
  set h 0.0
  foreach n $names { set h [expr {$h + [lindex [mp_size $n] 1]}] }
  set h [expr {$h + $gap * ([llength $names] - 1)}]
  set y [expr {($cy0 + $cy1 - $h) / 2.0}]
  foreach n $names {
    mp_place $n $x $y $orient
    set y [expr {$y + [lindex [mp_size $n] 1] + $gap}]
  }
}

set data [concat [mp_find "*u_dcache*u_data*u_ram"] [mp_find "*u_icache*u_data*u_ram"]]
set right [concat [mp_find "*u_vregfile*u_ram"] \
                  [mp_find "*u_dcache*u_tag*u_ram"] [mp_find "*u_icache*u_tag*u_ram"]]
if {[llength $data] > 0} {
  mp_column $data $cx0 MY 20.0
}
if {[llength $right] > 0} {
  set w 0.0
  foreach n $right { set w [expr {max($w, [lindex [mp_size $n] 0])}] }
  # Right-align every macro of the column with the core edge.
  set h 0.0
  foreach n $right { set h [expr {$h + [lindex [mp_size $n] 1]}] }
  set gap 20.0
  set h [expr {$h + $gap * ([llength $right] - 1)}]
  set y [expr {($cy0 + $cy1 - $h) / 2.0}]
  foreach n $right {
    lassign [mp_size $n] mw mh
    mp_place $n [expr {$cx1 - $mw}] $y R0
    set y [expr {$y + $mh + $gap}]
  }
}
