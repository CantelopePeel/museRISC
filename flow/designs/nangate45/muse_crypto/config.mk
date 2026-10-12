export DESIGN_NAME = muse_crypto_top
export PLATFORM    = nangate45
export VERILOG_FILES = $(sort $(wildcard $(DESIGN_HOME)/src/muse_crypto/*.v))
export SDC_FILE      = $(DESIGN_HOME)/nangate45/muse_crypto/constraint.sdc
export CORE_UTILIZATION = 28
export PLACE_DENSITY_LB_ADDON = 0.05
export CLOCK_PERIOD = 10
