#!/usr/bin/env bash
# Run Ara (third_party/ara) build/sim commands in the emulated
# amd64 Ubuntu container used for CVA6, reusing the CVA6-pinned
# Verilator v5.008 as Ara's verilator install. The ara tree is
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
[ -e third_party/ara/install/verilator ] || \
  ln -s ../../cva6/tmp/verilator-v5.008 third_party/ara/install/verilator
docker run --rm --platform linux/amd64 \
  -v "$PWD/third_party:/tp" \
  -v muserisc-apt-cache:/var/cache/apt \
  -w /tp/ara \
  ubuntu:24.04 bash -lc '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    mkdir -p /var/cache/apt/archives/partial
    apt-get update -o Dir::Cache::Archives=/var/cache/apt/archives
    apt-get install -y -o Dir::Cache::Archives=/var/cache/apt/archives \
      git curl make clang g++ libelf-dev python3 perl autoconf flex bison \
      help2man libfl-dev device-tree-compiler ca-certificates 2>/dev/null
    git config --global --add safe.directory "*"
    exec "$@"' -- "$@"
