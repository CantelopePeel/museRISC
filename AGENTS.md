# AGENTS.md

Working rules for AI agents (and humans) on this repository. Project
background, ISA status and evidence live in `README.md`, `docs/CORE.md`
and `docs/evidence/`.

## Environment

- First-time setup in the main checkout: `./scripts/install_deps.sh --gcc15`
  (builds pinned Verilator into `deps/`, fetches SoftFloat and
  riscv-tests), plus `./scripts/setup.sh --fetch-act` for ACT/Sail.
- In every shell: `source deps/env.sh` (puts `deps/` Verilator and the
  GCC 15+ RISC-V toolchain first on `PATH`, sets `RISCV_TESTS_DIR`).
- Baseline gates: `make test`, `make lint`, `make core-test`,
  `make riscv-tests`; ACT on the core via `scripts/build_act4_core.sh`
  then `sim/run_act_core.sh`.

## Long-running commands

Run anything that takes more than a minute or two (Verilator builds,
`make core-test`, riscv-tests, ACT, TestFloat, synthesis, OpenROAD) in
the background, logging to a file under `build/`, and keep working
while it runs. Report wall-clock time with results.

## Subagents work in git worktrees

- Every subagent that changes files works in its own git worktree on
  its own branch, never in the main checkout or another agent's
  worktree, so parallel work cannot collide.
- Branch from the current `main`; name the branch after the feature
  (e.g. `fpu-multicycle`).
- Do not copy or re-fetch dependencies into a worktree. Run
  `scripts/worktree_setup.sh <main-checkout>` from inside the worktree:
  it symlinks `deps/` and the `third_party/` sources to the main
  checkout. `riscv-arch-test` is the one exception (the ACT flow writes
  into it), so it gets a `git clone --shared`, which borrows git
  objects instead of copying them.
- Never write into symlinked `deps/` or `third_party/` from a worktree.
  `build/` is per-worktree.

## Pull requests

When principal work on a feature is done and it is well tested at
every level that applies (unit testbenches, integration/core-harness
tests, end-to-end runs and simulations such as riscv-tests, ACT
compliance suites, TestFloat and Linux boot), open a pull request.

- Target `main` of the fork `CantelopePeel/museRISC`. Never open PRs on
  the upstream `bubblebabyboi/museRISC` unless explicitly asked.
- The PR description lists what changed, every gate that was run with
  its pass counts and wall-clock time, and anything not run or waived.
- Do not open a PR for work whose tests are failing or not yet run;
  push the branch and report status instead.
- Significant RTL changes (e.g. FPU, multiply/divide, caches) get an
  independent audit by a separate agent before the PR is merged.
