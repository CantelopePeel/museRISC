#!/usr/bin/env bash
# ACT4 (riscv-arch-test) compliance harness. RISCOF is deprecated
# upstream; the current framework generates self-checking ELFs using
# the Sail reference model, then runs them on a DUT.
#
# Today this validates the harness end-to-end (DUT = Sail itself) for
# RV64I:  `RESULT: All 51 tests passed.`  That is NOT a hardware
# compliance claim. Running the same ELFs on the CVA6 Verilator model
# needs a museRISC DUT config (rvmodel_macros.h + link.ld for the
# Ariane testharness) -- see docs/COMPLIANCE.md.
set -euo pipefail
cd "$(dirname "$0")/.."
ACT=third_party/riscv-arch-test
[ -d "$ACT/framework" ] || { echo "clone riscv-arch-test first"; exit 1; }
command -v mise >/dev/null || { echo "install mise (brew install mise)"; exit 1; }
[ -x third_party/sail/bin/sail_riscv_sim ] || { echo "install Sail 0.15 into third_party/sail"; exit 1; }
command -v riscv64-elf-gcc >/dev/null || { echo "install riscv64-elf-gcc"; exit 1; }

# ACT configs expect riscv64-unknown-elf-* names; alias the brew tools.
mkdir -p build/riscv-alias/bin
for t in gcc g++ objdump objcopy nm ar as ld readelf size strip ranlib; do
  ln -sf "$(command -v riscv64-elf-$t)" "build/riscv-alias/bin/riscv64-unknown-elf-$t"
done
ln -sf "$PWD/third_party/sail/bin/sail_riscv_sim" build/riscv-alias/bin/sail_riscv_sim

# UDB's z3 cache may hold a Linux ELF libz3 on macOS; shim in the
# Homebrew Mach-O build under the names its FFI loader tries.
if [ -f /opt/homebrew/lib/libz3.dylib ]; then
  D="$HOME/.cache/udb/z3/z3-5.1.0/arm64"; mkdir -p "$D"
  for n in libz3.so libz3.so.4.8 libz3 z3 libz3.dylib; do
    cp /opt/homebrew/lib/libz3.dylib "$D/$n"
  done
fi

cd "$ACT"
mise trust >/dev/null 2>&1 || true
PATH="$PWD/../../build/riscv-alias/bin:$PATH" \
  mise exec -- make sail-RVI20U64 EXTENSIONS="${EXTENSIONS:-I}" FAST=1
echo "Summary: $ACT/work/sail-RVI20U64/summary.log"
