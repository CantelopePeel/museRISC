#!/usr/bin/env bash
# Build Berkeley TestFloat checker ELFs for the CVA6 model (issue #7).
# Generates level-1 RNE vectors with testfloat_gen (Berkeley
# SoftFloat/TestFloat 3e, RISCV specialization, built host-side in
# Docker), emits bare-metal checker assembly via
# scripts/testfloat_cva6.py, compiles with the host RISC-V GCC, and
# stages ELFs under third_party/cva6/testfloat-elfs/ for the batch
# runner: ELF_SUBDIR=testfloat-elfs ./scripts/cva6_docker.sh regression
set -euo pipefail
cd "$(dirname "$0")/.."
TP=third_party
GEN=$TP/berkeley-testfloat-3/build/HostRISCV/testfloat_gen
OPS="${OPS:-f32_add f32_sub f32_mul f32_div f32_sqrt f32_mulAdd f64_add f64_sub f64_mul f64_div f64_sqrt f64_mulAdd f32_to_i32 f32_to_i64 f32_to_ui32 f32_to_ui64 f64_to_i32 f64_to_i64 f64_to_ui32 f64_to_ui64 i32_to_f32 i64_to_f32 ui32_to_f32 ui64_to_f32 i32_to_f64 i64_to_f64 ui32_to_f64 ui64_to_f64 f32_to_f64 f64_to_f32 f32_eq f32_le f32_lt f64_eq f64_le f64_lt}"
MAX_CASES="${MAX_CASES:-46464}"
SEED="${SEED:-42}"
command -v riscv64-elf-gcc >/dev/null || { echo "install riscv64-elf-gcc"; exit 1; }
[ -d $TP/berkeley-testfloat-3 ] || { echo "clone berkeley-softfloat-3 + berkeley-testfloat-3 into third_party/ first"; exit 1; }
if [ ! -x "$GEN" ]; then
  echo "Building SoftFloat/TestFloat (host, RISCV specialization) in Docker..."
  docker run --rm -v "$PWD/$TP:/tp" ubuntu:24.04 bash -lc '
    apt-get update -qq && apt-get install -y -qq gcc make >/dev/null 2>&1
    cd /tp/berkeley-softfloat-3/build && mkdir -p HostRISCV && cp template-FAST_INT64/Makefile HostRISCV/
    cd HostRISCV && sed -i "s/^==> *//" Makefile && sed -i "s/SPECIALIZE_TYPE ?= 8086/SPECIALIZE_TYPE ?= RISCV/" Makefile
    cp ../Linux-RISCV64-GCC/platform.h . && make -j4 >/dev/null
    cd /tp/berkeley-testfloat-3/build && mkdir -p HostRISCV && cp template/Makefile HostRISCV/
    cd HostRISCV && sed -i "s/^==> *//" Makefile && sed -i "s/PLATFORM ?= Win32-MinGW/PLATFORM ?= HostRISCV/" Makefile
    cp ../Linux-RISCV64-GCC/platform.h . && make -j4 testfloat_gen EXE= LINK="cc -o \$@" >/dev/null'
fi
[ -x "$GEN" ] || { echo "testfloat_gen build failed"; exit 1; }
mkdir -p build/testfloat third_party/cva6/testfloat-elfs
for op in $OPS; do
  echo "== $op"
  docker run --rm -v "$PWD/$TP:/tp" ubuntu:24.04 bash -lc \
    "cd /tp/berkeley-testfloat-3/build/HostRISCV && ./testfloat_gen -level 1 -seed $SEED $op" \
    > "build/testfloat/$op.txt"
  python3 scripts/testfloat_cva6.py "$op" --max-cases "$MAX_CASES" \
    < "build/testfloat/$op.txt" > "build/testfloat/tf-$op.S"
  riscv64-elf-gcc -nostdlib -nostartfiles -march=rv64imafdc -mabi=lp64d \
    -T sw/testfloat/link.ld "build/testfloat/tf-$op.S" -o "build/testfloat/tf-$op" 2>/dev/null
  cp "build/testfloat/tf-$op" third_party/cva6/testfloat-elfs/
done
echo "Staged ELFs: $(ls third_party/cva6/testfloat-elfs | wc -l | tr -d ' ') in third_party/cva6/testfloat-elfs/"
