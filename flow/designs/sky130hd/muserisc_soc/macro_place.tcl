# Manual macro placement for muserisc_soc_top on sky130hd
# (MACRO_PLACEMENT_TCL). Coordinates are derived from the core area,
# so DIE_AREA/CORE_AREA can change without editing this file.
#
#   +------------------------------------------------+
#   | D$ way3 (R0)  | I$ way0 (R0)  | I$ way1 (R0)   |  pins face down
#   |                                                |
#   | VRF2                                    tag I1 |
#   |                std cells                tag I0 |
#   | VRF1                                    tag D3 |
#   |                                         ...    |
#   | VRF0                                    tag D0 |
#   |                                                |
#   | D$ way0 (MX)  | D$ way1 (MX)  | D$ way2 (MX)   |  pins face up
#   +------------------------------------------------+
#
# OpenRAM port-0 pins (din/addr/wmask/dout, the only port the L1
# arrays use) sit along the macro's bottom edge and its control pins
# on the left edge, so the bottom row is mirrored (MX) to face the
# core. The VRF macros use port 0 (write, bottom edge) and port 1
# (read, top and right edges), so they get wide vertical gaps.
# Whatever this file does not place (a configuration with fewer
# macros) is left to rtl_macro_placer.

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

# Snap to the placement site grid (unithd 0.46 x 2.72).
proc mp_snap {v step} {
  return [expr {round($v / $step) * $step}]
}

proc mp_place {name x y orient} {
  set x [mp_snap $x 0.46]
  set y [mp_snap $y 2.72]
  puts "muserisc macro: $name at ($x, $y) $orient"
  place_macro -macro_name $name -location [list $x $y] -orientation $orient
}

set dways [mp_find "*u_dcache*u_data*u_ram"]
set iways [mp_find "*u_icache*u_data*u_ram"]
set dtags [mp_find "*u_dcache*u_tag*u_ram"]
set itags [mp_find "*u_icache*u_tag*u_ram"]
set vrfs  [mp_find "*u_vregfile*u_ram"]

# Data ways: bottom row = first three D$ ways, top row = the rest
# (remaining D$ ways, then the I$ ways).
set data [concat $dways $iways]
set ndata [llength $data]
if {$ndata > 0} {
  lassign [mp_size [lindex $data 0]] dw dh
  set nbot [expr {($ndata + 1) / 2}]
  set ntop [expr {$ndata - $nbot}]
  foreach {row n y orient first} [list bot $nbot $cy0 MX 0 \
                                       top $ntop [expr {$cy1 - $dh}] R0 $nbot] {
    if {$n == 0} { continue }
    set gap [expr {$n > 1 ? ($cx1 - $cx0 - $n * $dw) / ($n - 1) : 0}]
    if {$gap > 60} { set gap 60 }
    set x [expr {$cx0 + ($cx1 - $cx0 - $n * $dw - ($n - 1) * $gap) / 2.0}]
    for {set i 0} {$i < $n} {incr i} {
      mp_place [lindex $data [expr {$first + $i}]] $x $y $orient
      set x [expr {$x + $dw + $gap}]
    }
  }
  set band_y0 [expr {$cy0 + $dh}]
  set band_y1 [expr {$cy1 - $dh}]
} else {
  set band_y0 $cy0
  set band_y1 $cy1
}
set band_mid [expr {($band_y0 + $band_y1) / 2.0}]

# VRF banks: left column, centered in the band between the rows.
if {[llength $vrfs] > 0} {
  lassign [mp_size [lindex $vrfs 0]] vw vh
  set n [llength $vrfs]
  set gap 100.0
  set y [expr {$band_mid - ($n * $vh + ($n - 1) * $gap) / 2.0}]
  foreach v $vrfs {
    mp_place $v $cx0 $y R0
    set y [expr {$y + $vh + $gap}]
  }
}

# Tag ways: right column, D$ tags at the bottom (next to the D$
# ways), I$ tags at the top. Control pins (left edge) face the core.
set tags [concat $dtags $itags]
if {[llength $tags] > 0} {
  lassign [mp_size [lindex $tags 0]] tw th
  set n [llength $tags]
  set gap 40.0
  set y [expr {$band_mid - ($n * $th + ($n - 1) * $gap) / 2.0}]
  foreach t $tags {
    mp_place $t [expr {$cx1 - $tw}] $y R0
    set y [expr {$y + $th + $gap}]
  }
}
