# Verilator C++ testbenches for the in-house core (issue #18).
# Everything builds and runs on the host: verilator, verilator_coverage,
# and a riscv64 bare-metal gcc (riscv64-unknown-elf- or riscv64-elf-).
#
#   make -C sim            # unit + core tests, prints coverage summary
#   make -C sim coverage   # (re)build the annotated coverage report
#
# Coverage .dat files from every run in this directory's build output
# are merged; the annotated report lands in build/sim/coverage/.

ROOT  := ..
RTL   := $(ROOT)/rtl/core
BUILD := $(ROOT)/build/sim
OBJ   := $(BUILD)/obj

VERILATOR ?= verilator
VFLAGS    := --cc --exe --build -j 0 -Wall -Wno-DECLFILENAME \
             --coverage-line --coverage-toggle --assert \
             -CFLAGS "-std=c++17 -O2" --Mdir
PKG       := $(RTL)/muserisc_pkg.sv

RISCV_PREFIX ?= $(shell command -v riscv64-unknown-elf-gcc >/dev/null 2>&1 \
                  && echo riscv64-unknown-elf- || echo riscv64-elf-)
RISCV_GCC     := $(RISCV_PREFIX)gcc
RISCV_OBJCOPY := $(RISCV_PREFIX)objcopy
SWFLAGS       := -march=rv64i_zicsr_zifencei -mabi=lp64 -nostdlib -T $(ROOT)/sw/core-tests/link.ld

CORE_RTL := $(PKG) $(RTL)/muserisc_regfile.sv $(RTL)/muserisc_alu.sv \
            $(RTL)/muserisc_decoder.sv $(RTL)/muserisc_core.sv
TESTS    := rv64i_directed trap_illegal trap_misalign trap_ecall \
            trap_ebreak trap_store_misalign

.PHONY: all alu decoder regfile core sw coverage clean
all: alu decoder regfile core coverage

$(BUILD) $(OBJ):
	mkdir -p $@

## ---- ALU unit test ----------------------------------------------------
$(BUILD)/alu_tb: $(ROOT)/tb/cpp/alu_tb.cpp $(PKG) $(RTL)/muserisc_alu.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/alu --top-module muserisc_alu \
	  -o $(abspath $(BUILD)/alu_tb) $(PKG) $(RTL)/muserisc_alu.sv \
	  $(abspath $(ROOT)/tb/cpp/alu_tb.cpp)

alu: $(BUILD)/alu_tb
	cd $(BUILD) && COV_FILE=cov_alu.dat ./alu_tb

## ---- Decoder unit test -------------------------------------------------
$(BUILD)/decoder_tb: $(ROOT)/tb/cpp/decoder_tb.cpp $(PKG) $(RTL)/muserisc_decoder.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/decoder --top-module muserisc_decoder \
	  -o $(abspath $(BUILD)/decoder_tb) $(PKG) $(RTL)/muserisc_decoder.sv \
	  $(abspath $(ROOT)/tb/cpp/decoder_tb.cpp)

decoder: $(BUILD)/decoder_tb
	cd $(BUILD) && COV_FILE=cov_decoder.dat ./decoder_tb

## ---- Register file unit test --------------------------------------------
$(BUILD)/regfile_tb: $(ROOT)/tb/cpp/regfile_tb.cpp $(RTL)/muserisc_regfile.sv | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/regfile --top-module muserisc_regfile \
	  -o $(abspath $(BUILD)/regfile_tb) $(RTL)/muserisc_regfile.sv \
	  $(abspath $(ROOT)/tb/cpp/regfile_tb.cpp)

regfile: $(BUILD)/regfile_tb
	cd $(BUILD) && COV_FILE=cov_regfile.dat ./regfile_tb

## ---- Core harness + directed software ---------------------------------
$(BUILD)/core_tb: $(ROOT)/tb/cpp/core_tb.cpp $(CORE_RTL) | $(BUILD) $(OBJ)
	$(VERILATOR) $(VFLAGS) $(OBJ)/core --top-module muserisc_core \
	  -o $(abspath $(BUILD)/core_tb) $(CORE_RTL) \
	  $(abspath $(ROOT)/tb/cpp/core_tb.cpp)

$(BUILD)/%.bin: $(ROOT)/sw/core-tests/%.S $(ROOT)/sw/core-tests/link.ld | $(BUILD)
	$(RISCV_GCC) $(SWFLAGS) $< -o $(BUILD)/$*.elf
	$(RISCV_OBJCOPY) -O binary $(BUILD)/$*.elf $@

core: $(BUILD)/core_tb $(addprefix $(BUILD)/,$(addsuffix .bin,$(TESTS)))
	cd $(BUILD) && COV_FILE=cov_rv64i.dat ./core_tb rv64i_directed.bin
	cd $(BUILD) && COV_FILE=cov_trap_illegal.dat ./core_tb trap_illegal.bin 100000 --expect-trap 2
	cd $(BUILD) && COV_FILE=cov_trap_misalign.dat ./core_tb trap_misalign.bin 100000 --expect-trap 4
	cd $(BUILD) && COV_FILE=cov_trap_ecall.dat ./core_tb trap_ecall.bin 100000 --expect-trap 11
	cd $(BUILD) && COV_FILE=cov_trap_ebreak.dat ./core_tb trap_ebreak.bin 100000 --expect-trap 3
	cd $(BUILD) && COV_FILE=cov_trap_smisalign.dat ./core_tb trap_store_misalign.bin 100000 --expect-trap 6

## ---- Coverage ----------------------------------------------------------
# Annotate from this directory: the .dat files record source paths
# relative to sim/, where verilator was invoked. Inputs are listed
# explicitly so a stale merged file can never feed back into a merge.
COV_INPUTS := $(BUILD)/cov_alu.dat $(BUILD)/cov_decoder.dat \
              $(BUILD)/cov_regfile.dat $(BUILD)/cov_rv64i.dat \
              $(BUILD)/cov_trap_illegal.dat $(BUILD)/cov_trap_misalign.dat \
              $(BUILD)/cov_trap_ecall.dat $(BUILD)/cov_trap_ebreak.dat \
              $(BUILD)/cov_trap_smisalign.dat
coverage:
	@rm -f $(BUILD)/cov_merged.dat
	@verilator_coverage --write $(BUILD)/cov_merged.dat $(COV_INPUTS)
	@verilator_coverage --annotate $(BUILD)/coverage $(BUILD)/cov_merged.dat | tail -5

clean:
	rm -rf $(BUILD)
