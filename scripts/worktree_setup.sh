#!/usr/bin/env bash
# Prepare a git worktree to build without re-fetching dependencies.
# Run from inside the new worktree:
#   /path/to/main/checkout/scripts/worktree_setup.sh
# or pass the main checkout explicitly:
#   ./scripts/worktree_setup.sh /data/liam/museRISC
# deps/ and read-only third_party/ sources are symlinked to the main
# checkout. riscv-arch-test is the exception: the ACT flow writes ELFs
# into its work/ directory, so each worktree gets its own
# `git clone --shared` (objects are borrowed, nothing is copied).
set -euo pipefail
wt=$(git rev-parse --show-toplevel)
main=${1:-$(cd "$(dirname "$0")/.." && pwd)}
if [ "$main" = "$wt" ]; then
  main=$(git -C "$wt" worktree list --porcelain | sed -n '1s/^worktree //p')
fi
[ "$main" != "$wt" ] || { echo "run this inside a worktree, not the main checkout" >&2; exit 1; }
[ -d "$main/deps" ] || { echo "$main/deps missing: run scripts/install_deps.sh in the main checkout first" >&2; exit 1; }

link() { # target linkname
  if [ -L "$2" ] || [ ! -e "$2" ]; then ln -sfn "$1" "$2"; echo "linked  $2 -> $1"; else
    echo "kept    $2 (exists, not a symlink)"; fi
}

cd "$wt"
link "$main/deps" deps
mkdir -p third_party
for src in "$main"/third_party/*; do
  name=$(basename "$src")
  if [ "$name" = riscv-arch-test ]; then
    if [ ! -d third_party/riscv-arch-test/.git ]; then
      git clone -q --shared "$src" third_party/riscv-arch-test
      git -C third_party/riscv-arch-test -c advice.detachedHead=false \
        checkout -q "$(git -C "$src" rev-parse HEAD)"
      (cd third_party/riscv-arch-test && mise trust -q 2>/dev/null || true)
      echo "cloned  third_party/riscv-arch-test (shared objects)"
    fi
  else
    link "$src" "third_party/$name"
  fi
done
echo "Done. In each shell: source deps/env.sh"
