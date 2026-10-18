#!/usr/bin/env bash
# Run OpenROAD-flow-scripts (ORFS) in the official openroad/orfs
# image (amd64; emulated on Apple Silicon).
# Usage: [PLATFORM=nangate45] [DESIGN=muse_crypto|muserisc_soc] \
#          ./scripts/openroad_docker.sh [make-target]
# Results land in build/orfs-results/<PLATFORM>/<DESIGN_NAME>/base/
# (muse_crypto_top for muse_crypto, muserisc_soc_top for the SoC).
# The make target may carry variable overrides, e.g.
#   "FLOW_VARIANT=reg CLOCK_PERIOD=30 do-place".
# Optional environment:
#   ORFS_NAME     container name (so a run can be stopped with
#                 `docker stop <name>`; default: anonymous)
#   ORFS_TIMEOUT  wall-clock limit for make inside the container,
#                 in timeout(1) syntax (e.g. 6h; default: none)
# The container runs as the calling user, so build/ stays removable.
set -euo pipefail
cd "$(dirname "$0")/.."
PLATFORM="${PLATFORM:-nangate45}"
DESIGN="${DESIGN:-muse_crypto}"
TARGET="${1:-}"
command -v docker >/dev/null || { echo "docker not found"; exit 1; }
docker info >/dev/null 2>&1 || { echo "docker daemon not running"; exit 1; }
mkdir -p build/orfs-results build/orfs-logs build/orfs-reports build/orfs-objects

NAME_ARGS=()
[ -n "${ORFS_NAME:-}" ] && NAME_ARGS=(--name "$ORFS_NAME")
TIMEOUT_CMD=""
[ -n "${ORFS_TIMEOUT:-}" ] && TIMEOUT_CMD="timeout --signal=TERM --kill-after=60 $ORFS_TIMEOUT"

docker run --rm --platform linux/amd64 "${NAME_ARGS[@]}" \
  --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD/flow/designs/$PLATFORM/$DESIGN:/OpenROAD-flow-scripts/flow/designs/$PLATFORM/$DESIGN" \
  -v "$PWD/rtl/crypto:/OpenROAD-flow-scripts/flow/designs/src/muse_crypto" \
  -v "$PWD/rtl:/OpenROAD-flow-scripts/flow/designs/src/muserisc_soc" \
  -v "$PWD/scripts:/OpenROAD-flow-scripts/flow/designs/muserisc_scripts:ro" \
  -v "$PWD/build/orfs-results:/OpenROAD-flow-scripts/flow/results" \
  -v "$PWD/build/orfs-logs:/OpenROAD-flow-scripts/flow/logs" \
  -v "$PWD/build/orfs-reports:/OpenROAD-flow-scripts/flow/reports" \
  -v "$PWD/build/orfs-objects:/OpenROAD-flow-scripts/flow/objects" \
  openroad/orfs:latest \
  bash -lc "source ./env.sh && cd flow && \
    $TIMEOUT_CMD make DESIGN_CONFIG=designs/$PLATFORM/$DESIGN/config.mk $TARGET"
echo "Results: build/orfs-results/$PLATFORM/ (per DESIGN_NAME in $DESIGN/config.mk)"
