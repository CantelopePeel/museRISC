#!/bin/bash
# Parallel equivalent of sim/run_act_core.sh (same per-ELF verdict:
# core_tb exit status, 5M-cycle budget). Usage:
#   sim/run_act_core_par.sh <core_tb> <out.csv> [elf-dir] [jobs]
TB=$(readlink -f "$1"); OUT=$(readlink -f "$2")
cd "$(dirname "$0")/.."
ELF_DIR=${3:-third_party/riscv-arch-test/work/muserisc-core/elfs}
JOBS=${4:-24}
start=$(date +%s)
one() {
  elf=$1; tb=$2
  name=$(basename "$elf" .elf)
  out=$("$tb" "$elf" 5000000 2>&1); rc=$?
  cycles=$(echo "$out" | sed -n 's/.* \([0-9][0-9]*\) cycles.*/\1/p' | tail -1)
  if [ $rc -eq 0 ]; then echo "$name,PASS,$cycles"; else echo "$name,FAIL,$cycles"; fi
}
export -f one
find "$ELF_DIR" -type f -name '*.elf' | sort | xargs -P "$JOBS" -I{} bash -c 'one "$@"' _ {} "$TB" > "$OUT.tmp"
{ echo "test,result,cycles"; sort "$OUT.tmp"; } > "$OUT"; rm -f "$OUT.tmp"
pass=$(grep -c ',PASS,' "$OUT"); total=$(( $(wc -l < "$OUT") - 1 ))
echo "ACT (muserisc-core): $pass/$total PASS, $((total-pass)) FAIL; wall $(( $(date +%s) - start ))s"
