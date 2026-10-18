# muserisc_soc_top on sky130hd (area/timing estimate for the
# chip-size decision; same RTL as nangate45/muserisc_soc via the
# shared rtl/muserisc_soc_files.mk). SRAM macros
# (MUSERISC_SRAM_SKY130) are the OpenRAM macros shipped with ORFS:
#   VRF banks, 3x 256x64 1R1W byte-write: sky130_sram_1rw1r_64x256_8
#   L1 data ways, 6x 512x64: sky130_sram_1rw1r_128x256_8 as 256x128
#   L1 tag ways, 6x 64x44: sky130_sram_1rw1r_44x64_8
# The .v models (sram/gen_openram_models.py) give slang the ports;
# the .libs blackbox them.
export DESIGN_NAME = muserisc_soc_top
export PLATFORM    = sky130hd
export SYNTH_HDL_FRONTEND = slang
# -DSYNTHESIS: see nangate45/muserisc_soc/config.mk (ORFS also passes it).
export SYNTH_SLANG_ARGS = --unroll-limit=200000 -DSYNTHESIS -DMUSERISC_SRAM_SKY130
# L1 associativity (muserisc_soc_top IC_WAYS / DC_WAYS); the
# "caravel" variant below shrinks it to fit Caravel's user area.
MUSERISC_IC_WAYS ?= 2
MUSERISC_DC_WAYS ?= 4
ifneq ($(filter caravel%,$(FLOW_VARIANT)),)
  MUSERISC_IC_WAYS = 1
  MUSERISC_DC_WAYS = 2
endif
export SYNTH_SLANG_ARGS += -G IC_WAYS=$(MUSERISC_IC_WAYS) -G DC_WAYS=$(MUSERISC_DC_WAYS)
SKY130_RAM = $(FLOW_HOME)/platforms/sky130ram
SKY130_MACROS = sky130_sram_1rw1r_64x256_8 sky130_sram_1rw1r_128x256_8 \
                sky130_sram_1rw1r_44x64_8
export ADDITIONAL_LEFS = $(foreach m,$(SKY130_MACROS),$(SKY130_RAM)/$(m)/$(m).lef)
export ADDITIONAL_LIBS = $(foreach m,$(SKY130_MACROS),$(SKY130_RAM)/$(m)/$(m)_TT_1p8V_25C.lib)
export ADDITIONAL_GDS  = $(foreach m,$(SKY130_MACROS),$(SKY130_RAM)/$(m)/$(m).gds)
# SoC RTL list shared with the other platform's config (located
# relative to this file: DESIGN_HOME is not yet set while ORFS reads
# the design config).
include $(abspath $(dir $(lastword $(MAKEFILE_LIST)))../../src/muserisc_soc/muserisc_soc_files.mk)
export VERILOG_FILES = \
  $(foreach m,$(SKY130_MACROS),$(DESIGN_HOME)/$(PLATFORM)/muserisc_soc/sram/$(m).v) \
  $(addprefix $(DESIGN_HOME)/src/muserisc_soc/,$(MUSERISC_SOC_RTL))
# muserisc_fpu_ops.svh is `included by muserisc_fpu_pkg.sv and
# muserisc_fpu.sv.
export VERILOG_INCLUDE_DIRS = $(DESIGN_HOME)/src/muserisc_soc/core
export SDC_FILE      = $(DESIGN_HOME)/sky130hd/muserisc_soc/constraint.sdc

# ---- Place and route (docs/SOC_AREA.md, "Place and route") ----
MUSERISC_PNR_DIR = $(DESIGN_HOME)/$(PLATFORM)/muserisc_soc
# Explicit die/core: 15 macros (6.23 mm^2) along the edges, std cells
# in the middle band; see macro_place.tcl for the arrangement. 30 um
# core margin for the I/O pins.
# 3.56 x 3.36 mm left the global placer at 0.83-0.90 target density
# (it raised the 0.5 target itself: too little free area beside the
# 6.2 mm^2 of macros), and post-CTS legalization failed around the
# register files; 3.8 x 3.6 mm gives it ~0.5.
export DIE_AREA  ?= 0 0 3800 3600
export CORE_AREA ?= 30 30 3770 3570
# Caravel user project area (2.92 x 3.52 mm): 4 KiB I$ (1 way) +
# 8 KiB D$ (2 ways), so 9 macros.
ifneq ($(filter caravel%,$(FLOW_VARIANT)),)
  override DIE_AREA  = 0 0 2920 3520
  override CORE_AREA = 30 30 2890 3490
endif
export MACRO_PLACEMENT_TCL = $(MUSERISC_PNR_DIR)/macro_place.tcl
export TAPCELL_TCL = $(MUSERISC_PNR_DIR)/tapcell.tcl
export PDN_TCL = $(MUSERISC_PNR_DIR)/pdn.tcl
# 0.60 left the middle band congested in global routing (unreg trial);
# spread the std cells over more of the band.
export PLACE_DENSITY ?= 0.55
# GPL stops at 10 % overflow by default; on this design that left a
# band of ~90 %-dense 100 um tiles (the register files) above the VRF
# column that the legalizer could not resolve. Converge further.
export GLOBAL_PLACEMENT_ARGS ?= -overflow 0.05
export FASTROUTE_TCL = $(MUSERISC_PNR_DIR)/fastroute.tcl
# (-allow_congestion is not an option: the detailed router then stops
# on nets whose guides FastRoute left disconnected, DRT-0218.)
# caravel2: met4 power straps at 4x the platform pitch and no global
# routing derate, for the vertical (met2/met4) congestion.
ifneq ($(filter caravel2 caravel3,$(FLOW_VARIANT)),)
  export MUSERISC_PDN_M4_PITCH = 108.56
  export MUSERISC_GRT_ADJ = 0.0
endif
# caravel3: the 16 h runs of the full SoC (reg2) and caravel2 did not
# finish detailed routing. Global routing had no overflow (34-37 %
# average usage); the detailed-route violations were met1 shorts and
# spacing (> 97 %) in dense std-cell clusters (pin access), so spread
# the cells and pad them by one site on each side.
ifeq ($(FLOW_VARIANT),caravel3)
  override PLACE_DENSITY = 0.45
  export CELL_PAD_IN_SITES_GLOBAL_PLACEMENT = 1
  export CELL_PAD_IN_SITES_DETAIL_PLACEMENT = 1
  export DETAILED_ROUTE_END_ITERATION = 30
endif
# Timing repair budget. The floorplan-stage repair_timing ran for
# hours on the unrepaired netlist (one 145-fanout gate on many
# paths); buffer removal there is cheap, and placement repair_design
# plus the post-CTS / post-GRT repair_timing do the real work.
export REMOVE_ABC_BUFFERS ?= 1
export TNS_END_PERCENT ?= 20
export SKIP_LAST_GASP ?= 1
export SETUP_SLACK_MARGIN ?= 0
export HOLD_SLACK_MARGIN ?= 0
