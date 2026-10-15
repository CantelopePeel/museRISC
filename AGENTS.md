# AGENTS.md

Working rules for AI agents (and humans) on this repository. Project
background, ISA status and evidence live in `README.md`, `docs/CORE.md`
and `docs/evidence/`.

## Environment

- First-time setup in the main checkout: `./scripts/install_deps.sh --gcc15`
  (builds pinned Verilator into `deps/`, fetches SoftFloat and
  riscv-tests), plus `./scripts/setup.sh --fetch-act` for ACT/Sail.
- In every shell: `source deps/env.sh` (bash or zsh; puts `deps/`
  Verilator and the GCC 15+ RISC-V toolchain first on `PATH`, sets
  `RISCV_TESTS_DIR`). With `--gcc15` that toolchain also builds the
  core tests, unlike CI (Ubuntu's GCC 13); all gates pass with both.
- GitHub CI installs Ubuntu's apt Verilator 5.020, not the pinned
  `deps/` one, and 5.020 rejects some constructs 5.048 accepts (e.g.
  `%Error-IMPURE` on variable-index writes inside package functions).
  Before opening a PR that touches RTL or testbenches, also lint and
  build with 5.020 (e.g. in a `ubuntu:24.04` Docker container with
  `apt-get install verilator`; never install it system-wide).
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
  `scripts/worktree_setup.sh` from inside the worktree: it symlinks
  `deps/` and the `third_party/` sources to the main checkout.
  `riscv-arch-test` is the one exception (the ACT flow writes into it),
  so it gets its own detached `git worktree` of the main checkout's
  clone, which shares git objects instead of copying them.
- Never write into symlinked `deps/` or `third_party/` from a worktree.
  `build/` is per-worktree. Flows that write into `third_party/` other
  than ACT (e.g. `scripts/build_testfloat.sh` and the CVA6 scripts,
  which write under `third_party/cva6/`) must run in the main checkout,
  one at a time.

## Pull requests

When principal work on a feature is done and it is well tested at
every level that applies (unit testbenches, integration/core-harness
tests, end-to-end runs and simulations such as riscv-tests, ACT
compliance suites, TestFloat and Linux boot), open a pull request.

- Target `main` of the fork `CantelopePeel/museRISC` first.
- The PR description lists what changed, every gate that was run with
  its pass counts and wall-clock time, and anything not run or waived.
- Do not open a PR for work whose tests are failing or not yet run;
  push the branch and report status instead.
- A PR merges only when `gh pr checks` is green on its head commit,
  in addition to the local gates and review.

## Review

Every PR is reviewed by subagents before it is merged, in at most
three rounds. A round is one review followed by the author's fixes:

1. Review: a reviewer subagent that did not write the change reviews
   the PR (correctness, test coverage and evidence, docs, and for RTL:
   synthesizability, timing-relevant structure, interaction with
   traps/stalls/flushes). Significant RTL changes (e.g. FPU,
   multiply/divide, caches) get a full independent audit, including
   re-running the gates rather than trusting the PR description.
2. Fix: the author addresses the findings, re-runs the affected gates,
   and pushes.

The next round uses a fresh reviewer. Stop as soon as a review has no
blocking findings. If blocking findings remain after the third round,
stop and escalate to the user with the outstanding issues instead of
merging. Reviewers post their findings as PR comments so the history
stays with the PR.

## Upstreaming

Once a PR has passed review and is merged into the fork's `main`, send
it upstream to `bubblebabyboi/museRISC` without waiting for a separate
decision:

- Split it into well-scoped PRs, one coherent change each (e.g. a unit
  and its tests; tooling separate from RTL). Leave out fork-only
  material (references to the fork, fork workflow rules).
- Branch from the latest upstream `main`, re-apply the change, and
  re-run every affected gate there; the upstream PR description reports
  those results, not the fork's.
- Open it with `gh pr create -R bubblebabyboi/museRISC --base main
  --head CantelopePeel:<branch>`, link the related upstream issue, and
  link back to the fork PR and its review comments.
- If upstream has already changed the same area so the change no
  longer applies cleanly, rebase and re-test; if it is obsolete, skip
  it and note that on the fork PR.
