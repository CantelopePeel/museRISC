# debug helper: print a net's pins and their locations
source $::env(SCRIPTS_DIR)/load.tcl
read_db $::env(RESULTS_DIR)/$::env(STA_STAGE).odb
set b [ord::get_db_block]
set n [$b findNet $::env(NET_NAME)]
puts "net [$n getName] sigtype [$n getSigType] iterms [llength [$n getITerms]] bterms [llength [$n getBTerms]]"
foreach it [$n getITerms] {
  set i [$it getInst]
  set bb [$i getBBox]
  puts [format "  %s/%s %s at %.1f %.1f %s" [$i getName] [[$it getMTerm] getName] [[$i getMaster] getName] \
    [ord::dbu_to_microns [$bb xMin]] [ord::dbu_to_microns [$bb yMin]] [$i getPlacementStatus]]
}
foreach bt [$n getBTerms] {
  puts "  port [$bt getName]"
  foreach bp [$bt getBPins] { set bb [$bp getBBox]; puts [format "    pin at %.1f %.1f" [ord::dbu_to_microns [$bb xMin]] [ord::dbu_to_microns [$bb yMin]]] }
}
