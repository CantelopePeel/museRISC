#!/bin/bash
# Stage 3d gate (issue #18): run ACT4 self-checking ELFs
# generated for the museRISC in-house core (see
# scripts/build_act4_core.sh) on the core itself via the C++
# harness. Each ELF reports pass/fail by its HTIF tohost halt.
#
# Usage: [JOBS=n] run_act_core.sh [out.csv] [elf-dir]
# JOBS>1 runs that many ELFs in parallel (same per-ELF command
# and verdict; results are reported in sorted ELF order).
set -u
cd "$(dirname "$0")/.."

CORE_TB=build/sim/core_tb
ELF_DIR=${2:-third_party/riscv-arch-test/work/muserisc-core/elfs}
JOBS=${JOBS:-1}
[ -d "$ELF_DIR" ] || { echo "no ELFs in $ELF_DIR; run ./scripts/build_act4_core.sh first"; exit 1; }

# One ELF -> "RESULT<TAB>name<TAB>cycles", plus the harness output on failure.
run_one() {
  local elf=$1 name out rc cycles
  name=$(basename "$elf" .elf)
  out=$("$CORE_TB" "$elf" 5000000 2>&1)
  rc=$?
  cycles=$(echo "$out" | sed -n 's/.* \([0-9][0-9]*\) cycles.*/\1/p')
  if [ $rc -eq 0 ]; then
    printf 'PASS\t%s\t%s\n' "$name" "$cycles"
  else
    printf 'FAIL\t%s\t%s\n' "$name" "$cycles"
    echo "$out" | sed 's/^/    /' >&2
  fi
}
export -f run_one
export CORE_TB

pass=0 fail=0 total=0
[ $# -ge 1 ] && echo "test,result,cycles" > "$1"
while IFS= read -r line; do
  case "$line" in
    PASS$'\t'*|FAIL$'\t'*) ;;
    *) echo "$line"; continue ;;
  esac
  IFS=$'\t' read -r res name cycles <<< "$line"
  total=$((total + 1))
  if [ "$res" = PASS ]; then pass=$((pass + 1)); else fail=$((fail + 1)); fi
  echo "$res $name ($cycles cycles)"
  [ $# -ge 1 ] && echo "$name,$res,$cycles" >> "$1"
done < <(find "$ELF_DIR" -type f -name '*.elf' | sort |
         xargs -P "$JOBS" -I{} bash -c 'run_one "$1"' _ {} |
         { if [ "$JOBS" -gt 1 ]; then sort -t$'\t' -k2,2 -s; else cat; fi; })
echo "ACT (muserisc-core): $pass/$total PASS, $fail FAIL"
[ "$fail" -eq 0 ]
