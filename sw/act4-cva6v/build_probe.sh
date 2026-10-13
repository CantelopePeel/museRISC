#!/usr/bin/env bash
# Build the tail-behavior probe ELF (see probe_tail.c). Run inside the
# Ara container: ./scripts/ara_docker.sh /repo/sw/act4-cva6v/build_probe.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
ARA=third_party/ara
if [ -f "$ARA/apps/link.ld" ]; then
  LD="$ARA/apps/link.ld"
else
  LD=build/ara-smoke-link.ld
  mkdir -p build
  sed 's/ALIGNMENT/128/g' "$ARA/apps/common/arch.link.ld" > "$LD"
fi
riscv64-unknown-elf-gcc -march=rv64gcv -mabi=lp64d -mcmodel=medany -O2 -nostdlib \
  -I"$ARA/apps/common" \
  -T "$LD" \
  "$ARA/apps/common/crt0.S" sw/act4-cva6v/probe_tail.c \
  -o sw/act4-cva6v/probe_tail.elf
echo "built sw/act4-cva6v/probe_tail.elf"
