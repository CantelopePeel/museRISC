#!/usr/bin/env bash
# Build the Ara RVV smoke ELF. Run inside the Ara container:
#   ./scripts/ara_docker.sh /repo/sw/ara-smoke/build.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
ARA=third_party/ara
# arch.link.ld needs ALIGNMENT substituted (Ara generates link.ld per
# config; AxiWideBeWidth for 2 lanes = 16 bytes -> 2**7 for VLEN512
# vregs is overkill; apps use their generated linker script).
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
  "$ARA/apps/common/crt0.S" sw/ara-smoke/smoke.c \
  -o sw/ara-smoke/smoke.elf
echo "built sw/ara-smoke/smoke.elf"
