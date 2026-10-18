# nangate45 tapcell (platform tapcell.tcl) plus a row halo around the
# SRAM macros (MUSERISC_MACRO_ROW_HALO um, default 5) for the pin
# escape on the macros' left edge.
set h 5
if {[info exists ::env(MUSERISC_MACRO_ROW_HALO)]} { set h $::env(MUSERISC_MACRO_ROW_HALO) }
cut_rows -halo_width_x $h -halo_width_y $h
tapcell \
  -distance 120 \
  -tapcell_master "$::env(TAP_CELL_NAME)" \
  -endcap_master "$::env(TAP_CELL_NAME)"
