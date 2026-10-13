#!/usr/bin/env bash
# Run already-built riscv-tests ELFs on the standalone tandem Spike
# fork as a behavioral second opinion. This validates the ELF on
# Spike; it is not a CVA6 result and not a compliance claim.
#
# Prerequisite: build Spike and the tests first, for example:
#   ./scripts/cva6_docker.sh rv64ui-p-add-verilator
# Usage:
#   ./scripts/spike_solo.sh [rv64ui-p-add rv64ui-p-simple ...]
#   SPIKE_PROFILE=matched ./scripts/spike_solo.sh
# Profiles: default (Spike defaults) or matched (see
# docs/SPIKE_CONFIG.md for provenance and remaining gaps).
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

docker run --rm \
  -e SPIKE_PROFILE="${SPIKE_PROFILE:-default}" \
  -e TIMEOUT="${TIMEOUT:-20}" \
  -v "$PWD/third_party/cva6:/cva6" -w /cva6 ubuntu:24.04 \
  bash -lc '
    export LD_LIBRARY_PATH=/cva6/verif/core-v-verif/vendor/riscv/riscv-isa-sim/build:${LD_LIBRARY_PATH:-}
    S=verif/core-v-verif/vendor/riscv/riscv-isa-sim/build/spike
    "$S" -v 2>&1 | head -n 2 || true
    echo "Spike profile: $SPIKE_PROFILE"
    spike_args=(--disable-dtb)
    if [ "$SPIKE_PROFILE" = matched ]; then
      spike_args+=(
        --isa=RV64IMAFDC_zba_zbb_zbc_zbs_zcb_zicsr_zicntr_zihpm_zicond_zkn_svnapot
        --priv=MSU
        --param /top/core/0/pmpregions_max:uint64_t=64
        --param /top/core/0/pmpregions_writable:uint64_t=8
        --param /top/core/0/pmp_granularity:uint64_t=8
      )
    elif [ "$SPIKE_PROFILE" != default ]; then
      echo "unknown SPIKE_PROFILE: $SPIKE_PROFILE" >&2; exit 2
    fi
    fail=0
    for t in "$@"; do
      log="/tmp/$t.spike.log"
      if timeout "${TIMEOUT}s" "$S" "${spike_args[@]}" "tmp/riscv-tests/build/isa/$t" >"$log" 2>&1; then
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
