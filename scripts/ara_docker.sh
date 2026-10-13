#!/usr/bin/env bash
# Run Ara (third_party/ara) build/sim commands in a native-arm64
# Ubuntu container. Ara builds its own pinned Verilator into
# install/verilator (`make verilator`); the CVA6 v5.008 is too old
# for Ara's waiver syntax. The ara tree is
# mounted read-write: Bender checkouts (hardware/deps), build
# products (hardware/build, install/) persist on the host.
#
# Usage:
#   ./scripts/ara_docker.sh make -C hardware bender
#   ./scripts/ara_docker.sh make -C hardware update
#   ./scripts/ara_docker.sh make -C hardware verilate config=2_lanes vlen=512
set -euo pipefail
cd "$(dirname "$0")/.."
docker info >/dev/null 2>&1 || { echo "docker daemon not running"; exit 1; }
mkdir -p third_party/ara/install
docker run --rm \
  -v "$PWD:/repo" \
  -v muserisc-apt-cache:/var/cache/apt \
  -w /repo/third_party/ara \
  ubuntu:24.04 bash -lc '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    mkdir -p /var/cache/apt/archives/partial
    apt-get update -o Dir::Cache::Archives=/var/cache/apt/archives
    apt-get install -y -o Dir::Cache::Archives=/var/cache/apt/archives \
      git curl make clang g++ libelf-dev python3 perl autoconf flex bison \
      help2man libfl-dev device-tree-compiler ca-certificates \
      gcc-riscv64-unknown-elf picolibc-riscv64-unknown-elf 2>/dev/null
    git config --global --add safe.directory "*"
    # Upstream quirk at Ara 34bd3bc1: waiver.vlt contains stray UTF-8
    # object-replacement bytes (EF BF BC) that Verilator rejects as
    # invalid tokens. Strip non-ASCII bytes (idempotent, comments only).
    LC_ALL=C sed -i "s/[^[:print:][:space:]]//g" hardware/tb/verilator/waiver.vlt
    exec "$@"' -- "$@"
