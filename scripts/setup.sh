#!/usr/bin/env bash
# museRISC environment setup. Reports missing host tools, then fetches
# the pinned third-party sources (not committed) with --fetch.
#   ./scripts/setup.sh           # report only
#   ./scripts/setup.sh --fetch   # also clone third_party/ at the pins
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Host tools =="
for t in verilator iverilog python3 docker make git yosys mise \
         riscv64-elf-gcc; do
  if command -v "$t" >/dev/null; then echo "  ok       $t"; else
    echo "  MISSING  $t"; fi
done
cat <<'EOF'
Install on macOS (Linux: use your distro equivalents):
  brew install verilator icarus-verilog yosys riscv64-elf-gcc mise z3 gh

Pinned third-party sources (Phase 1, not needed for `make test`):
  cva6            81245a47fad8fe1a5d562d953ef2662e099def76
  ara             34bd3bc152421b4601a7bf3d6e8e91ffb545c99e
  riscv-arch-test 6af53584adc8b944fdc34c361988674870146d91
  sail-riscv      0.15 release (sail-riscv-Mac-arm64 on macOS)
Host build/test: ./scripts/cva6_docker.sh
ACT4 harness:    ./scripts/run_compliance.sh
EOF

if [ "${1:-}" = "--fetch" ]; then
  clone_pin() { # dir url commit
    if [ ! -d "$1" ]; then git clone "$2" "$1"; fi
    git -C "$1" checkout "$3"
    echo "pinned $1 @ $3"
  }
  mkdir -p third_party
  clone_pin third_party/cva6 https://github.com/openhwgroup/cva6.git \
    81245a47fad8fe1a5d562d953ef2662e099def76
  git -C third_party/cva6 submodule update --init --recursive --jobs 4
  clone_pin third_party/ara https://github.com/pulp-platform/ara.git \
    34bd3bc152421b4601a7bf3d6e8e91ffb545c99e
  clone_pin third_party/riscv-arch-test \
    https://github.com/riscv-non-isa/riscv-arch-test.git \
    6af53584adc8b944fdc34c361988674870146d91
  if [ ! -x third_party/sail/bin/sail_riscv_sim ]; then
    mkdir -p third_party/sail
    curl -sL https://github.com/riscv/sail-riscv/releases/download/0.15/sail-riscv-Mac-arm64.tar.gz \
      | tar xz -C third_party/sail --strip-components=1
  fi
fi
echo "Baseline check: run 'make test && make lint'"
