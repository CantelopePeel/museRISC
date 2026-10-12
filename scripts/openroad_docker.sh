#!/usr/bin/env bash
# Run OpenROAD-flow-scripts (ORFS) on the muse_crypto macro in the
# official openroad/orfs image (amd64; emulated on Apple Silicon).
# Usage: PLATFORM=nangate45 ./scripts/openroad_docker.sh [make-target]
# Results land in build/orfs-results/<PLATFORM>/muse_crypto_top/base/.
set -euo pipefail
cd "$(dirname "$0")/.."
PLATFORM="${PLATFORM:-nangate45}"
TARGET="${1:-}"
command -v docker >/dev/null || { echo "docker not found"; exit 1; }
docker info >/dev/null 2>&1 || { echo "docker daemon not running"; exit 1; }
mkdir -p build/orfs-results build/orfs-logs build/orfs-reports build/orfs-objects

docker run --rm --platform linux/amd64 \
  -v "$PWD/flow/designs/$PLATFORM/muse_crypto:/OpenROAD-flow-scripts/flow/designs/$PLATFORM/muse_crypto" \
  -v "$PWD/rtl/crypto:/OpenROAD-flow-scripts/flow/designs/src/muse_crypto" \
  -v "$PWD/build/orfs-results:/OpenROAD-flow-scripts/flow/results" \
  -v "$PWD/build/orfs-logs:/OpenROAD-flow-scripts/flow/logs" \
  -v "$PWD/build/orfs-reports:/OpenROAD-flow-scripts/flow/reports" \
  -v "$PWD/build/orfs-objects:/OpenROAD-flow-scripts/flow/objects" \
  openroad/orfs:latest \
  bash -lc "source ./env.sh && cd flow && \
    make DESIGN_CONFIG=designs/$PLATFORM/muse_crypto/config.mk $TARGET"
echo "Results: build/orfs-results/$PLATFORM/muse_crypto_top/base/"
