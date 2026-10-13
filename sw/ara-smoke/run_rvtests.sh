#!/usr/bin/env bash
# Build Ara's patched riscv-tests vector binaries (rv64uv) with the
# packaged RISC-V GCC and simulate each on the verilated model.
# Run inside the Ara container:
#   ./scripts/ara_docker.sh /repo/sw/ara-smoke/run_rvtests.sh [range]
# Optional args: first and last index (1-based) into the Makefrag list.
# Emits one CSV line per test: name,PASS|FAIL|BUILD_FAIL|TIMEOUT,cycles
set -uo pipefail
cd "$(dirname "$0")/../../third_party/ara/apps"
TESTS=$(sed -n '/^rv64uv_sc_tests/,/^$/p' riscv-tests/isa/rv64uv/Makefrag \
  | sed 's/rv64uv_sc_tests =//; s/\\//g' | tr '\n' ' ')
FIRST="${1:-1}"; LAST="${2:-9999}"
i=0
OVR=(COMPILER=gcc RISCV_CC=riscv64-unknown-elf-gcc
  RISCV_CXX=riscv64-unknown-elf-g++ RISCV_OBJDUMP=riscv64-unknown-elf-objdump
  RISCV_STRIP=riscv64-unknown-elf-strip GCC_INSTALL_DIR=/usr
  LLVM_FLAGS="-march=rv64gcv_zfh -mabi=lp64d -mno-relax --specs=picolibc.specs"
  LLVM_V_FLAGS=)
for t in $TESTS; do
  i=$((i+1))
  [ "$i" -lt "$FIRST" ] && continue
  [ "$i" -gt "$LAST" ] && break
  bin="bin/rv64uv-ara-$t"
  if [ ! -f "$bin" ]; then
    if ! make config=2_lanes vlen=512 "$bin" "${OVR[@]}" \
        > "/tmp/rvt_${t}_build.log" 2>&1; then
      echo "$t,BUILD_FAIL,"; continue
    fi
  fi
  timeout 240 ../hardware/build/verilator/Vara_tb_verilator \
    -l "ram,/repo/third_party/ara/apps/$bin,elf" \
    > "/tmp/rvt_${t}_sim.log" 2>&1
  rc=$?
  cyc=$(grep -a "Executed cycles" "/tmp/rvt_${t}_sim.log" | awk '{print $3}')
  if [ "$rc" -eq 124 ]; then echo "$t,TIMEOUT,$cyc";
  elif [ "$rc" -eq 0 ]; then echo "$t,PASS,$cyc";
  else echo "$t,FAIL(rc=$rc),$cyc"; fi
done
