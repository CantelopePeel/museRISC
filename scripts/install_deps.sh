#!/usr/bin/env bash
# Install the host tools museRISC needs (see scripts/setup.sh for the
# list and `make test` / `make lint` / `make core-test` for users).
#   ./scripts/install_deps.sh              # distro packages + mise
#   ./scripts/install_deps.sh --gcc15      # also the pinned GCC 15+ RISC-V
#                                          # toolchain ACT4 needs (Linux x86_64)
# Supports Ubuntu/Debian (apt) and macOS (Homebrew). Docker is not
# installed here; install it from https://docs.docker.com/engine/install/
# if you want `make openroad` or the CVA6 flows.
set -euo pipefail
cd "$(dirname "$0")/.."

# Same pin as .github/workflows/compliance.yml.
RISCV_TOOLCHAIN_TAG="2026.08.27"
RISCV_TOOLCHAIN_DIR="${RISCV_TOOLCHAIN_DIR:-$HOME/riscv-toolchain}"

want_gcc15=0
case "${1:-}" in
  --gcc15) want_gcc15=1 ;;
  "") ;;
  -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
  *) echo "unknown option: $1 (use --gcc15)" >&2; exit 2 ;;
esac

sudo_cmd() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi; }

case "$(uname -s)" in
  Linux)
    if ! command -v apt-get >/dev/null; then
      echo "only apt-based distros are supported; install the tools listed by ./scripts/setup.sh manually" >&2
      exit 1
    fi
    echo "== Installing apt packages =="
    sudo_cmd apt-get update
    sudo_cmd apt-get install -y iverilog verilator yosys z3 \
      gcc-riscv64-unknown-elf curl git make python3 xz-utils
    ;;
  Darwin)
    if ! command -v brew >/dev/null; then
      echo "Homebrew is required: https://brew.sh" >&2
      exit 1
    fi
    echo "== Installing Homebrew packages =="
    brew install verilator icarus-verilog yosys riscv64-elf-gcc mise z3
    ;;
  *)
    echo "unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

if ! command -v mise >/dev/null && [ ! -x "$HOME/.local/bin/mise" ]; then
  echo "== Installing mise (ACT4 tool manager) =="
  curl -fsSL https://mise.run | sh
fi

if [ "$want_gcc15" = 1 ]; then
  if [ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]; then
    echo "--gcc15: no prebuilt toolchain for $(uname -s)-$(uname -m); Homebrew's riscv64-elf-gcc is already recent" >&2
    exit 1
  fi
  . /etc/os-release
  asset="riscv64-elf-ubuntu-${VERSION_ID:-24.04}-gcc.tar.xz"
  if find "$RISCV_TOOLCHAIN_DIR" -path '*/bin/riscv64-unknown-elf-gcc' -print -quit 2>/dev/null | grep -q .; then
    echo "== GCC 15+ toolchain already in $RISCV_TOOLCHAIN_DIR =="
  else
    echo "== Downloading RISC-V toolchain $RISCV_TOOLCHAIN_TAG ($asset) =="
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    curl -fL "https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/${RISCV_TOOLCHAIN_TAG}/${asset}" -o "$tmp"
    mkdir -p "$RISCV_TOOLCHAIN_DIR"
    tar -xJf "$tmp" -C "$RISCV_TOOLCHAIN_DIR"
  fi
  gcc_bin=$(dirname "$(find "$RISCV_TOOLCHAIN_DIR" -path '*/bin/riscv64-unknown-elf-gcc' -print -quit)")
  echo "Add the GCC 15+ toolchain to PATH (before the distro one) for ACT4:"
  echo "  export PATH=\"$gcc_bin:\$PATH\""
fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "Add mise to PATH:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

echo
./scripts/setup.sh | sed -n '/== Host tools ==/,/MISSING  riscv\|ok       riscv/p'
