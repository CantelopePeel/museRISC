#!/bin/bash
# Parallel variant of sim/run_act_core.sh: runs every ACT ELF on
# the core harness with N jobs and writes the same CSV format
# (test,result,cycles), sorted by test name. Extra harness
# arguments (e.g. memory-latency options) go in CORE_TB_ARGS.
#
# Usage: run_act_parallel.sh out.csv [elf-dir]
#   CORE_TB=build/sim/core_tb JOBS=$(nproc) CORE_TB_ARGS="--mem-lat 0:6"
set -u
cd "$(dirname "$0")/.."
OUT=${1:?usage: run_act_parallel.sh out.csv [elf-dir]}
ELF_DIR=${2:-third_party/riscv-arch-test/work/muserisc-core/elfs}
CORE_TB=${CORE_TB:-build/sim/core_tb}
JOBS=${JOBS:-$(nproc)}
export CORE_TB CORE_TB_ARGS="${CORE_TB_ARGS:-}"
[ -d "$ELF_DIR" ] || { echo "no ELFs in $ELF_DIR"; exit 1; }
tmp=$(mktemp -d)
find "$ELF_DIR" -type f -name '*.elf' | sort |
  xargs -P "$JOBS" -I{} sh -c '
    elf="$1"; name=$(basename "$elf" .elf)
    # shellcheck disable=SC2086
    out=$("$CORE_TB" "$elf" 5000000 $CORE_TB_ARGS 2>&1); rc=$?
    cycles=$(echo "$out" | sed -n "s/.* \([0-9][0-9]*\) cycles.*/\1/p")
    if [ $rc -eq 0 ]; then res=PASS; else res=FAIL; echo "$out" > "$0/$name.fail"; fi
    echo "$name,$res,$cycles" > "$0/$name.row"
  ' "$tmp" {}
echo "test,result,cycles" > "$OUT"
cat "$tmp"/*.row | sort >> "$OUT"
for f in "$tmp"/*.fail; do [ -e "$f" ] && { echo "== $(basename "$f" .fail)"; head -5 "$f"; }; done
total=$(($(wc -l < "$OUT") - 1))
pass=$(grep -c ',PASS,' "$OUT")
rm -rf "$tmp"
echo "ACT (muserisc-core): $pass/$total PASS, $((total - pass)) FAIL"
[ "$pass" -eq "$total" ]
