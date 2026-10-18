# Global-routing layer setup for muserisc_soc_top (FASTROUTE_TCL).
# The platform default derates every layer by 20 %; with that, the
# middle band of the full SoC and of the Caravel variant never
# converged in FastRoute (thousands of gcells over by one track after
# 90+ congestion iterations). 10 % leaves the residual overflow to
# the detailed router (GLOBAL_ROUTE_ARGS -allow_congestion).
set adj 0.1
if {[info exists ::env(MUSERISC_GRT_ADJ)]} { set adj $::env(MUSERISC_GRT_ADJ) }
set_global_routing_layer_adjustment $::env(MIN_ROUTING_LAYER)-$::env(MAX_ROUTING_LAYER) $adj
set_routing_layers -clock $::env(MIN_CLK_ROUTING_LAYER)-$::env(MAX_ROUTING_LAYER)
set_routing_layers -signal $::env(MIN_ROUTING_LAYER)-$::env(MAX_ROUTING_LAYER)
