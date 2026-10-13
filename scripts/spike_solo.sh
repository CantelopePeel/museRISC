#!/usr/bin/env bash
# Run already-built riscv-tests ELFs on the standalone tandem Spike
# fork as a behavioral second opinion. This validates the ELF on
# Spike; it is not a CVA6 result and not a compliance claim.
#
# Prerequisite: build Spike and the tests first, for example:
#   ./scripts/cva6_docker.sh rv64ui-p-add-verilator
# Usage:
#   ./scripts/spike_solo.sh [rv64ui-p-add rv64ui-p-simple ...]
set -euo pipefail
cd "$(dirname "$0")/.."

SPIKE_REL=verif/core-v-verif/vendor/riscv/riscv-isa-sim/build/spike
if [ ! -x "third_party/cva6/$SPIKE_REL" ]; then
  echo "Spike binary not found. Run ./scripts/cva6_docker.sh first." >&2
  exit 1
fi
if [ "$#" -eq 0 ]; then
  set -- rv64ui-p-add rv64ui-p-simple
fi
for t in "$@"; do
  if [ ! -x "third_party/cva6/tmp/riscv-tests/build/isa/$t" ]; then
    echo "test ELF not built: $t" >&2
    exit 1
  fi
done

docker run --rm -v "$PWD/third_party/cva6:/cva6" -w /cva6 ubuntu:24.04 \
  bash -lc '
    export LD_LIBRARY_PATH=/cva6/verif/core-v-verif/vendor/riscv/riscv-isa-sim/build:${LD_LIBRARY_PATH:-}
    S=verif/core-v-verif/vendor/riscv/riscv-isa-sim/build/spike
    "$S" -v 2>&1 | head -n 2 || true
    fail=0
    for t in "$@"; do
      log="/tmp/$t.spike.log"
      if timeout "${TIMEOUT:-20}s" "$S" --disable-dtb "tmp/riscv-tests/build/isa/$t" >"$log" 2>&1; then
        echo "$t: Spike solo PASS (exit 0)"
        grep -E "ISA:|PMP Regions" "$log" | head -n 2 || true
      else
        rc=$?
        echo "$t: Spike solo FAIL (exit $rc)" >&2
        tail -n 30 "$log" >&2
        fail=1
      fi
    done
    exit "$fail"
  ' bash "$@"
