# sky130hd tapcell (platform tapcell.tcl) plus a row halo around the
# SRAM macros, so no standard cell is placed within
# MUSERISC_MACRO_ROW_HALO um (default 15) of a macro edge. That keeps
# room for the macro pin escape and the macro PDN connections.
set h 15
if {[info exists ::env(MUSERISC_MACRO_ROW_HALO)]} { set h $::env(MUSERISC_MACRO_ROW_HALO) }
cut_rows -halo_width_x $h -halo_width_y $h
tapcell \
  -distance 14 \
  -tapcell_master "$::env(TAP_CELL_NAME)"
