#!/usr/bin/env bash
# Build Ara apps with the packaged RISC-V GCC (no LLVM build) and run
# each on the verilated CVA6+Ara model. Run inside the Ara container:
#   ./scripts/ara_docker.sh /repo/sw/ara-smoke/run_apps.sh [app ...]
set -uo pipefail
cd "$(dirname "$0")/../../third_party/ara/apps"
APPS="${@:-dotproduct fdotproduct imatmul fmatmul iconv2d fconv2d}"
run_one() {
  local app="$1"
  echo "=== $app: build"
  if ! make config=2_lanes vlen=512 "$app" COMPILER=gcc \
      RISCV_CC=riscv64-unknown-elf-gcc RISCV_CXX=riscv64-unknown-elf-g++ \
      RISCV_OBJDUMP=riscv64-unknown-elf-objdump RISCV_STRIP=riscv64-unknown-elf-strip \
      LLVM_FLAGS="-march=rv64gcv_zfh -mabi=lp64d -mno-relax --specs=picolibc.specs" \
      LLVM_V_FLAGS= > "/tmp/ara_app_${app}_build.log" 2>&1; then
    echo "$app,BUILD_FAIL"; return
  fi
  echo "=== $app: simulate"
  ../hardware/build/verilator/Vara_tb_verilator \
    -l "ram,/repo/third_party/ara/apps/bin/$app,elf" \
    > "/tmp/ara_app_${app}_sim.log" 2>&1
  local rc=$?
  local cyc
  cyc=$(grep -a "Executed cycles" "/tmp/ara_app_${app}_sim.log" | awk '{print $3}')
  if [ "$rc" -eq 0 ]; then echo "$app,PASS,cycles=$cyc"; else echo "$app,FAIL(exit=$rc),cycles=$cyc"; fi
}
for app in $APPS; do run_one "$app"; done
