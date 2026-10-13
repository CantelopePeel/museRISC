export DESIGN_NAME = muse_crypto_top
export PLATFORM    = nangate45
export VERILOG_FILES = $(sort $(wildcard $(DESIGN_HOME)/src/muse_crypto/*.v))
export SDC_FILE      = $(DESIGN_HOME)/nangate45/muse_crypto/constraint.sdc
export CORE_UTILIZATION = 28
export PLACE_DENSITY_LB_ADDON = 0.05
export CLOCK_PERIOD = 10
# Baseline run (2026-10-12) finished route-clean and timing-MET but
# with 51 post-route max-capacitance violations (wire cap growth
# after the placement-stage repair). Size drivers to 80% of the
# liberty max-cap during early sizing to leave routing headroom.
export EARLY_SIZING_CAP_RATIO = 0.8
