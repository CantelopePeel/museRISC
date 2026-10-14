# museRISC Phase-0 make targets. See docs/ROADMAP.md for phased goals.
RTL := rtl/crypto/sha256_block.v rtl/crypto/keccak_f1600.v \
       rtl/crypto/ec_field.v rtl/crypto/muse_crypto_top.v \
       rtl/soc/muserisc_soc_top.v
BUILD := build

CORE_RTL := rtl/core/muserisc_pkg.sv rtl/core/muserisc_regfile.sv \
            rtl/core/muserisc_fpregfile.sv rtl/core/muserisc_alu.sv \
            rtl/core/muserisc_muldiv.sv rtl/core/muserisc_fpu.sv \
            rtl/core/muserisc_bext.sv \
            rtl/core/muserisc_decoder.sv rtl/core/muserisc_csr.sv \
            rtl/core/muserisc_mmu.sv rtl/core/muserisc_core.sv

.PHONY: test lint core-test riscv-tests openroad compliance clean
test: ## Python golden self-check + iverilog KATs (needs python3, iverilog)
	python3 sw/golden.py
	python3 sw/ec_ops.py
	mkdir -p $(BUILD)
	iverilog -g2012 -o $(BUILD)/tb_sha256 rtl/crypto/sha256_block.v tb/tb_sha256.v
	vvp $(BUILD)/tb_sha256 | tee $(BUILD)/sha256.log
	grep -q "TB_SHA256 PASS" $(BUILD)/sha256.log
	iverilog -g2012 -o $(BUILD)/tb_keccak rtl/crypto/keccak_f1600.v tb/tb_keccak.v
	vvp $(BUILD)/tb_keccak | tee $(BUILD)/keccak.log
	grep -q "TB_KECCAK PASS" $(BUILD)/keccak.log
	iverilog -g2012 -o $(BUILD)/tb_sha512 rtl/crypto/sha512_block.v tb/tb_sha512.v
	vvp $(BUILD)/tb_sha512 | tee $(BUILD)/sha512.log
	grep -q "TB_SHA512 PASS" $(BUILD)/sha512.log
	iverilog -g2012 -o $(BUILD)/tb_ec rtl/crypto/ec_field.v tb/tb_ec_field.v
	vvp $(BUILD)/tb_ec | tee $(BUILD)/ec.log
	grep -q "TB_EC_FIELD PASS" $(BUILD)/ec.log
	@echo "ALL PHASE-0 KATs PASS"

lint: ## Verilator lint on all synthesizable RTL
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module muserisc_soc_top $(RTL)
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module keccak_f1600 rtl/crypto/keccak_f1600.v
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module sha512_block rtl/crypto/sha512_block.v
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module muserisc_core $(CORE_RTL)

core-test: ## In-house core C++ Verilator TBs + directed asm + coverage (issue #18)
	$(MAKE) -C sim

riscv-tests: ## Stage gate: upstream riscv-tests rv64ui/um on the in-house core (#18)
	$(MAKE) -C sim riscv-tests

openroad: ## Dockerized OpenROAD-flow-scripts run on the crypto macro
	./scripts/openroad_docker.sh

compliance: ## ACT4 riscv-arch-test RV64I on Sail (harness validation)
	./scripts/run_compliance.sh

clean:
	rm -rf $(BUILD)
