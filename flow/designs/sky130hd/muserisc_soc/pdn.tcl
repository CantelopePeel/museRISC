# sky130hd PDN for muserisc_soc_top: the platform grid (met1 rails,
# met4/met5 straps) plus a grid over the OpenRAM macros. Their
# vdd/gnd pins are on met3 (the macros obstruct met1-met3 only), so
# the macro grid runs met4 straps over each macro and drops
# met3-met4 vias onto the pins; the core grid's met5 straps connect
# to those met4 straps.
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDD$} -power
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDDPE$}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDDCE$}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VPWR}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VPB}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^vccd1$}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^vdd$}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^VSS$} -ground
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^VSSE$}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {VGND}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {VNB}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^vssd1$}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^gnd$}
global_connect

set_voltage_domain -name {CORE} -power {VDD} -ground {VSS}

define_pdn_grid -name {grid} -voltage_domains {CORE} -pins {met5}
add_pdn_stripe -grid {grid} -layer {met1} -width {0.48} -pitch {5.44} -offset {0} -followpins
# met4 is also the upper vertical signal layer; MUSERISC_PDN_M4_PITCH
# (default 27.14, the platform value) thins the straps for routability.
set m4p 27.140
if {[info exists ::env(MUSERISC_PDN_M4_PITCH)]} { set m4p $::env(MUSERISC_PDN_M4_PITCH) }
add_pdn_stripe -grid {grid} -layer {met4} -width {1.600} -pitch $m4p -offset {13.570}
add_pdn_stripe -grid {grid} -layer {met5} -width {1.600} -pitch {27.200} -offset {13.600}
add_pdn_connect -grid {grid} -layers {met1 met4}
add_pdn_connect -grid {grid} -layers {met4 met5}

foreach {gname orients} {
  sram_grid_h {R0 R180 MX MY}
  sram_grid_v {R90 R270 MXR90 MYR90}
} {
  define_pdn_grid -name $gname -voltage_domains {CORE} -macro \
    -orient $orients -halo {2.0 2.0 2.0 2.0} -default -grid_over_boundary
  add_pdn_stripe -grid $gname -layer {met4} -width {1.600} -pitch $m4p -offset {13.570}
  add_pdn_connect -grid $gname -layers {met3 met4}
  add_pdn_connect -grid $gname -layers {met4 met5}
}
