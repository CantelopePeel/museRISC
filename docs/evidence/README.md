# Evidence

Committed, reproducible evidence for completed gates. A claim in
`docs/COMPLIANCE.md` should point here (or to a GitHub Actions run).

## B1 — CVA6 host smoke (2026-10-12)

- Artifact: [`b1-cva6-2026-10-12.log`](b1-cva6-2026-10-12.log) (extract of the full local Docker log)
- Command: `./scripts/cva6_docker.sh rv64ui-p-add-verilator rv64ui-p-simple-verilator`
- Result: exit 0; both tests report `*** SUCCESS *** (tohost = 0)`
  (`rv64ui-p-add` after 35,837 cycles; `rv64ui-p-simple` after 35,909 cycles)
- Configuration: CVA6 `81245a47fad8fe1a5d562d953ef2662e099def76`,
  Makefile default target `cv64a6_imafdc_sv39`, Verilator 5.008 (CVA6 pin
  with its v5 patch), tandem Spike fork bundled in core-v-verif,
  riscv-tests `eeacd550` physical (`-p-`) tests only
- Caveat: this is a **smoke gate**, not RV64GCV compliance. Full
  regression and ACT4 on the model are tracked by issue #2.

## Spike solo smoke on the B1 ELFs (2026-10-12, B2.1 start)

- Artifact: [`spike-solo-b1-elfs-2026-10-12.log`](spike-solo-b1-elfs-2026-10-12.log)
- Command: `./scripts/spike_solo.sh`
- Result: both B1 ELFs exit 0 on the standalone tandem-Spike binary
  (Spike 1.1.1-dev `b3149ab`)
- Caveat: the first run used Spike defaults (`RV64IMAFDC_zicntr_zihpm`,
  `PMP Regions 0`), **not** a config matched to
  `cv64a6_imafdc_sv39`. It validates the ELFs and the oracle only;
  matched-config solo and `SPIKE_TANDEM` lockstep comparison are
  B2 tasks in issue #2.
- Matched-profile rerun: `spike-solo-matched-b1-elfs-2026-10-12.log`
  (`SPIKE_PROFILE=matched`) — both ELFs exit 0 with ISA
  `RV64IMAFDC_zba_zbb_zbc_zbs_zcb_zicsr_zicntr`, privilege `MSU`,
  and PMP max/writable 64/8. Remaining config gaps are tracked in
  `docs/SPIKE_CONFIG.md`; this is still a two-test smoke, not B2.

## B2 batch regression runner smoke (2026-10-12)

- Artifact: [`b2-batch-runner-smoke-2026-10-12.csv`](b2-batch-runner-smoke-2026-10-12.csv)
- Command: `TESTS="rv64ui-p-add rv64ui-p-simple" RUN_NAME=solo-smoke ./scripts/cva6_docker.sh regression`
- Result: exit 0; CSV records both tests `PASS` in solo mode with
  cycle counts 35,837 / 35,909 — identical to the B1 gate above,
  now produced by the batch matrix runner (`results.csv` +
  `summary.txt` under `build/regression/<RUN_NAME>/`, per-test logs
  alongside). Tandem mode (`SPIKE_TANDEM=1`) uses a separate
  Verilator library (`work-ver-tandem`) so solo evidence is never
  overwritten.
- Caveat: runner validation on two tests only. Full directed lists
  are B2.2; tandem lockstep is B2.3 (issue #2).

## B2.0 config freeze + B2.1 Spike-solo directed baseline (2026-10-12)

- Artifact: [`spike-solo-matched-full-2026-10-12.log`](spike-solo-matched-full-2026-10-12.log)
- Command: `SPIKE_PROFILE=matched ./scripts/spike_solo.sh <174 tests from ci/riscv-{asm,amo,mul}-tests.list>`
  (ELFs built by `TEST_LISTS=asm,amo,mul ./scripts/cva6_docker.sh`;
  the `-v-` virtual-memory variants build via picolibc headers —
  see `C_INCLUDE_PATH` in `scripts/cva6_docker.sh`)
- Result: exit 0, **174/174 PASS** (96 `rv64ui`, 26 `rv64um`,
  38 `rv64ua`, 6 `rv64si`, 7 `rv64mi`, 1 `rv64uc`; 92 `-p-` + 82 `-v-`)
  under ISA `RV64IMAFDC_zba_zbb_zbc_zbs_zcb_zicsr_zicntr_zihpm_zicond_zkn_svnapot`,
  `--priv=MSU`, PMP max/writable 64/8.
- B2.0 freeze: `docs/SPIKE_CONFIG.md` records the source audit —
  tandem struct fields (Zicsr/PMP/modes) are set by
  `cva6pkg_to_core_cntrl_cfg`, `ext_zicntr_supported=0` is
  deliberate, the `64'h0x10000` boot literal resolves to `0x10000`
  under Verilator, and Zicond/ZKN-in-tandem, PMP granularity,
  Svnapot and debug triggers are waived **for these lists only**
  with reasons.
- Caveat: Spike passing says the ELFs and oracle agree with the
  RISC-V spec as Spike models it. It is **not** evidence about
  CVA6. The same lists on the CVA6 model are B2.2 (solo) and
  B2.3 (tandem lockstep), issue #2.

## B2.2 — CVA6 solo directed regression (2026-10-12)

- Artifact: [`b2-cva6-solo-2026-10-12.csv`](b2-cva6-solo-2026-10-12.csv)
  (174-row merged matrix in directed-list order)
- Command (single-run reproduce):
  `TEST_LISTS=asm,amo,mul RUN_NAME=solo-full ./scripts/cva6_docker.sh regression`
- Result: **174/174 PASS** (96 `rv64ui`, 26 `rv64um`, 38 `rv64ua`,
  6 `rv64si`, 7 `rv64mi`, 1 `rv64uc`; 92 `-p-` + 82 `-v-`), each
  `*** SUCCESS *** (tohost = 0)`, 0 fail/timeout/mismatch, on
  CVA6 `81245a47` target `cv64a6_imafdc_sv39`, Verilator 5.008,
  riscv-tests `eeacd550`, solo mode (no tandem compare).
- Assembly note: host/Docker crashes interrupted the first two
  attempts, so the matrix merges the preserved partial runs in
  list order — `solo-full` 32 rows, `solo-full-resume` 21 rows,
  `solo-full-chunk1`–`chunk6` 121 rows — plus one retest row
  below. No completed row was re-run or overwritten; the two
  tests in flight at each crash (`rv64ui-p-sraiw`,
  `rv64si-p-csr`; empty/truncated logs, no CSV row) were run in
  the successor chunk. The chunked `TESTS=` runs use the same
  ELFs, model library (`work-ver`), and verdict logic as the
  single-run command above.
- Triage: `rv64ui-p-xor` first recorded `FAIL` exit 139 with a
  115-byte log (JTAG banner only, no SUCCESS/FAILED) — a
  testharness crash, not a tohost failure. Standalone re-run
  (`RUN_NAME=xor-retest`) passes with exit 0, `*** SUCCESS ***`
  after 35,837 cycles; the merged matrix carries the retest row.
- Verification: every merged `PASS` row was cross-checked
  against its per-test log (SUCCESS present, FAILED absent, CSV
  cycles equal to log cycles). Per-test logs remain under
  `build/regression/*/logs/` locally (`build/` is not committed).
- Caveat: solo tohost verdict only — no Spike lockstep
  comparison (B2.3) and no ACT4 (B2.4), issue #2. Scope is the
  three directed lists (`asm,amo,mul`) only; floating-point
  lists, random instruction testing, and RVV are later phases.
  This is directed-test evidence on the integrated CVA6 model,
  not a standalone RV64GCV compliance claim.

## B2.3 tandem smoke (2026-10-12, branch `b2-tandem-act4`)

- Artifact: [`b2-tandem-smoke-2026-10-12.csv`](b2-tandem-smoke-2026-10-12.csv)
- Command: `SPIKE_TANDEM=1 TEST_LISTS=smoke RUN_NAME=tandem-smoke ./scripts/cva6_docker.sh regression`
  (separate model library `work-ver-tandem`; solo evidence untouched)
- Result: exit 0, **4/4 PASS with 0 mismatches** (`rv64ui-p-add`,
  `rv64ui-p-simple`, `rv64um-p-mul`, `rv64ua-p-amoadd_d`); Spike
  tandem banner shows ISA `RV64IMAFDC_zba_zbb_zbc_zbs_zcb_zicsr`
  (from `get_isa_str`, per the B2.0 waivers), boot `0x10000`,
  PMP regions/granularity 8/8.
- Runner fix: tandem setup reads `+elf_file`/`+core_name` via
  `$value$plusargs`, but `ariane_tb.cpp` allowlists only three
  leading Verilog plusargs, so the runner now passes them after
  the binary, where `Verilated::commandArgs` still exposes them.
  `core_name` is the Makefile default target
  `cv64a6_imafdc_sv39` (`riscv_dpi.cc` requires the `cv64a`
  prefix; the `spike.sv` default `cva6` aborts). No
  `third_party/` patch was needed.
- Caveat: smoke only. The full 174-test tandem matrix runs next
  on this branch; B2.3 is claimed only when it completes with
  zero unexplained mismatches (issue #2).
