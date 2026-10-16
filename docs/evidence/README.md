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

## B2.3 — Spike tandem lockstep directed regression (2026-10-12, branch `b2-tandem-act4`)

- Artifacts: [`b2-cva6-tandem-2026-10-12.csv`](b2-cva6-tandem-2026-10-12.csv)
  (174-row merged matrix in directed-list order; smoke step:
  [`b2-tandem-smoke-2026-10-12.csv`](b2-tandem-smoke-2026-10-12.csv))
- Command (single-run reproduce):
  `SPIKE_TANDEM=1 TEST_LISTS=asm,amo,mul RUN_NAME=tandem ./scripts/cva6_docker.sh regression`
  (separate model library `work-ver-tandem`; solo evidence untouched)
- Result: **173/174 PASS, 0 lockstep mismatches, 0 timeouts**,
  plus 1 explained reference-configuration waiver below (counts
  by family as B2.1/B2.2: 96 `rv64ui`, 26 `rv64um`, 38 `rv64ua`,
  6 `rv64si`, 7 `rv64mi`, 1 `rv64uc`; 92 `-p-` + 82 `-v-`).
  Every passing log shows DUT `*** SUCCESS *** (tohost = 0)`
  with tandem banner ISA `RV64IMAFDC_zba_zbb_zbc_zbs_zcb_zicsr`
  (from `get_isa_str`, per the B2.0 waivers), boot `0x10000`,
  PMP regions/granularity 8/8, and no `UVM_ERROR`/`UVM_FATAL`.
- Runner fix: tandem setup reads `+elf_file`/`+core_name` via
  `$value$plusargs`, but `ariane_tb.cpp` allowlists only three
  leading Verilog plusargs, so the runner now passes them after
  the binary, where `Verilated::commandArgs` still exposes them.
  `core_name` is the Makefile default target
  `cv64a6_imafdc_sv39` (`riscv_dpi.cc` requires the `cv64a`
  prefix; the `spike.sv` default `cva6` aborts). No
  `third_party/` patch was needed.
- Assembly note: the matrix merges nine 20-test chunk runs
  (`tandem-chunk1`–`chunk9`, list order) plus one retest below.
  Chunking uses the same ELFs, tandem model, and verdict logic
  as the single-run command; it exists because longer Docker
  runs on this host have died mid-matrix (see B2.2 note).
- Triage (2 initial non-PASS rows, both resolved):
  `rv64ua-v-amoand_w` first recorded `TIMEOUT` under host
  slowdown (log stalled after Spike init); standalone re-run
  passes with 21,225 cycles in 26 s, in family with its sibling
  atomics, and the matrix carries the retest row.
  `rv64mi-p-csr` deterministically records `FAIL` (exit 0,
  1,203 cycles, 0 mismatches): its log contains both CVA6
  `*** SUCCESS ***` and Spike-side `*** FAILED ***`, because
  tandem Spike has no `cycle` CSR without Zicntr (frozen
  `ext_zicntr_supported=0`) and traps on `TEST_CASE 25` while
  CVA6 passes. Standalone-Spike bisection (tandem ISA string
  fails exit 18; adding `_zicntr` passes) confirms a
  reference-configuration divergence, waived with reasons in
  `docs/SPIKE_CONFIG.md` (waived item 5). The matrix keeps the
  `FAIL` row; B2.3 acceptance is zero *unexplained* mismatches.
- Verification: every merged row was cross-checked against its
  per-test log (tandem banner, SUCCESS/FAILED shape, zero
  mismatches, CSV cycles equal to log cycles, no hidden UVM
  errors in passing logs). Per-test logs remain under
  `build/regression/*/logs/` locally (`build/` is not committed).
- Caveat: tandem comparison is architectural lockstep against
  Spike as configured in B2.0 (including its waivers), not a
  second normative compliance run. ACT4 `I,M` on the model is
  B2.4; the combined four-column matrix is B2.5 (issue #2).

## B2.4/B2.5 — ACT4 I/M on CVA6 and combined B2 matrix (2026-10-12, branch `b2-tandem-act4`)

- Artifacts: [`b2-act-cva6-2026-10-12.csv`](b2-act-cva6-2026-10-12.csv)
  (64-row ACT matrix), [`b2-combined-matrix-2026-10-12.csv`](b2-combined-matrix-2026-10-12.csv)
  (174-row Spike-solo / CVA6-solo / tandem matrix, B2.5);
  smoke step: [`b2-act-smoke-2026-10-12.csv`](b2-act-smoke-2026-10-12.csv)
- DUT config: `sw/act4-cva6/` (UDB yaml, `sail.json`, `link.ld`,
  `rvmodel_macros.h`, `test_config.yaml`), adapted from the
  upstream riscv-arch-test CVA6+Ara config to this scalar
  `cv64a6_imafdc_sv39` testharness build; see that directory's
  README for provenance and deliberate under-claims.
- Generation: `./scripts/build_act4_cva6.sh` produces 64
  self-checking ELFs (51 `I` + 13 `M`, riscv-arch-test
  `6af53584`, Sail-generated expected results) and stages them
  under `third_party/cva6/act-elfs/` for the batch runner
  (`ELF_SUBDIR=act-elfs TEST_LISTS=act-im` in
  `scripts/cva6_docker.sh`, four 16-ELF chunks `act-chunk1`–`4`).
- Result: **64/64 PASS** on the CVA6 solo model, 0
  fail/timeout; every log shows DUT `*** SUCCESS ***` and
  `RVCP-SUMMARY: TEST PASSED` with CSV cycles matching the log.
  ACT ELFs are self-checking against Sail, so a model PASS
  means CVA6 reproduced the reference result for every checked
  register/memory signature in that test. The optional
  standalone-Spike ACT cross-check was not run (generation
  already checks each ELF against Sail).
- Combined B2 outcome (B2.5): standalone Spike 174/174 PASS,
  CVA6 solo 174/174 PASS, tandem lockstep 173/174 PASS with
  zero mismatches plus the single waived `rv64mi-p-csr`
  reference-configuration divergence above, and ACT4 `I,M`
  64/64 PASS on the model. Within B2 scope the integrated
  CVA6 model (stock `cv64a6_imafdc_sv39` at `81245a47`, custom
  crypto not yet integrated) is therefore claimed as passing
  the directed `asm,amo,mul` lists plus ACT4 `I,M` — nothing
  wider (floating-point lists, privileged ACT suites, and RVV
  remain later-phase work, issues #7/#9).

## ISA verification sweep — F/D + A (2026-10-12, branch `isa-verify-sweep`, issue #7)

Pre-GDS sweep ordered ahead of B3. Directed float lists are
CVA6 `ci/riscv-fp-tests.list` ("fp"); ACT suites are generated
with the B2.4 DUT config (`sw/act4-cva6/`).

- Artifacts: [`fp-cva6-solo-2026-10-12.csv`](fp-cva6-solo-2026-10-12.csv)
  (46 directed float, CVA6 solo), [`spike-solo-fp-2026-10-12.log`](spike-solo-fp-2026-10-12.log)
  (46, standalone Spike `matched`), [`fp-tandem-f-2026-10-12.csv`](fp-tandem-f-2026-10-12.csv)
  (22 single-precision tandem), [`act-afd-cva6-2026-10-12.csv`](act-afd-cva6-2026-10-12.csv)
  (222 ACT rows: 84 F + 116 D + 18 Zaamo + 4 Zalrsc); smoke
  steps: [`fp-smoke-2026-10-12.csv`](fp-smoke-2026-10-12.csv),
  [`fp-tandem-smoke-2026-10-12.csv`](fp-tandem-smoke-2026-10-12.csv)
- Directed result: **CVA6 solo 46/46 PASS** (22 F + 24 D,
  `-p-`/`-v-`), **Spike solo 46/46 PASS**, **tandem F 22/22
  PASS** with 0 mismatches. Tandem D (24 tests) is waived as
  a harness limitation, not run to a matrix: every D test
  probed (`fadd`, `fdiv`, `move`, `ldst`) shows DUT SUCCESS
  with Spike-side FAILED and zero compare mismatches,
  including load/move-only tests, isolating tandem `fld`
  stepping at this pin (`docs/SPIKE_CONFIG.md` waived item 6).
  D arithmetic itself is evidenced by both solo oracles.
- ACT result: **220/222 PASS** on the CVA6 solo model (all F,
  D, Zaamo, and Zalrsc-`lr` rows PASS with
  `RVCP-SUMMARY: TEST PASSED`). The two `Zalrsc-sc` rows
  (`sc.d`, `sc.w`) hang to the cycle cap (still running at
  10M cycles, `tohost` untouched) in this testharness and are
  recorded `FAIL` as an explained waiver: directed
  `rv64ua-*-lrsc` passes solo and tandem (B2) and ACT
  `Zalrsc-lr` passes here, so core LR/SC logic is evidenced;
  the ACT `sc` case mix (hundreds of constrained-loop cases
  including `rs1=x0` forms) wedges the simulation memory
  path. Revisit with a directed case-level probe under #7;
  do not claim ACT Zalrsc-sc coverage.
- One transient harness crash (`F-fadd.s-00`, exit 139,
  banner-only log) passes cleanly on standalone re-run and in
  its chunk row, as with B2.2 `xor`.
- Berkeley TestFloat for this slice is stored separately
  below (2026-10-13).

## ISA verification sweep — B/C/Zicond/scalar-crypto (2026-10-12, branch `isa-verify-sweep`, issues #16/#17)

- Artifact: [`act-bc-cva6-2026-10-12.csv`](act-bc-cva6-2026-10-12.csv)
  (133-row ACT matrix in suite order)
- Config change: `Zcb`, `Zicond`, `Zkne`, `Zknd`, `Zknh`
  declared in `sw/act4-cva6/` after decoder audit at
  `81245a47` (compressed_decoder Zcb cases, `czero` under
  `RVZiCond`, AES/SHA ops under `ZKN`); Sail support enabled
  to match. Generation as B2.4 (`EXTENSIONS=` per suite),
  run solo on the CVA6 model in seven chunks
  (`act-b-chunk1`–`7`, `TIME_OUT` raised cycle cap supported
  by the runner for long ACT tests).
- Result: **133/133 PASS**, 0 fail/timeout (Zba 8, Zbb 24,
  Zbc 3, Zbs 8, Zbkb 14, Zbkc 2, Zca 32, Zcd 4, Zcb-family
  12, Zicsr 6, Zifencei 1, Zicond 2, Zkne 4, Zknd 5, Zknh 8);
  every log shows DUT `*** SUCCESS ***` and
  `RVCP-SUMMARY: TEST PASSED` with matching cycles.
- Scope notes: solo-model ACT evidence. Tandem lockstep for
  these suites was not run (B2.3 waivers already exclude
  Zicond/ZKN operands from comparison; bitmanip tandem is
  possible future work, not claimed). `Misalign` suite
  generated zero ELFs under this config and is handled with
  the privileged slice. Issues #16/#17 acceptance (stored
  green reports) is met by this artifact.

## ISA verification sweep — Berkeley TestFloat vs cvfpu (2026-10-13, branch `isa-verify-sweep`, issue #7)

- Artifact: [`testfloat-cva6-2026-10-13.csv`](testfloat-cva6-2026-10-13.csv)
  (12-row merged matrix in generator op order)
- Harness: `./scripts/build_testfloat.sh` builds host
  `testfloat_gen` (Berkeley SoftFloat/TestFloat 3e, RISCV
  specialization; berkeley-softfloat-3 `a0c6494c`,
  berkeley-testfloat-3 `a9c849f1`, uncommitted under
  `third_party/`), generates level-1 seed-42 vectors, and
  `scripts/testfloat_cva6.py` emits bare-metal checkers
  (`sw/testfloat/`) that execute each vector on the FPU and
  compare result bits (any NaN matches any NaN) and accrued
  `fflags` exactly, halting via HTIF `tohost` with the failing
  case index encoded. ELFs staged under
  `third_party/cva6/testfloat-elfs/`, run solo on the CVA6
  model in four 3-ELF chunks (`tf-chunk1`–`4`,
  `TIME_OUT=20000000 TEST_TIMEOUT_SEC=420`); the single-run
  reproduce (`TEST_LISTS=testfloat RUN_NAME=tf-all`, runner
  list added with this evidence) reproduces the identical
  12-row matrix.
- Result: **12/12 PASS**, 0 fail/timeout — f32/f64 add, sub,
  mul, div, sqrt, and fused mulAdd at RNE with
  tininess-after-rounding, 466,008 vector executions in
  total (46,464 per binary op; the two mulAdd ops are
  stride-sampled 46,464 of 6,133,248 level-1 cases; sqrt
  full at 600 f32 / 768 f64). Every log shows
  `*** SUCCESS ***` with CSV cycles matching the log.
- Scope notes: vectors are checked against SoftFloat with
  the RISCV specialization, so a PASS means the cvfpu
  configuration in this CVA6 build agrees with the
  IEEE-754/RISC-V reference arithmetic (including exception
  flags) for these operations at RNE. Conversions,
  comparisons/`roundToInt`, non-RNE rounding modes, and
  level-2 density remain follow-up work under issue #7;
  do not claim full TestFloat coverage. This completes the
  TestFloat task of #7; its privileged/Sv39 + Linux task
  is the next section.

## ISA verification sweep — privileged ACT (Sv39/PMP/exceptions) (2026-10-13, branch `isa-verify-sweep`, issue #7)

- Artifact: [`act-priv-cva6-2026-10-13.csv`](act-priv-cva6-2026-10-13.csv)
  (134-row merged matrix in generated-list order)
- Config changes: `include_priv_tests: True` in
  `sw/act4-cva6/test_config.yaml`, and Svnapot declared in
  the UDB yaml + `sail.json` after the discovery pass showed
  the hardware translating NAPOT PTEs the config claimed
  unsupported (`SvnapotEn: bit'(1)`,
  `cv64a6_imafdc_sv39_config_pkg.sv` @`81245a47`). The full
  matrix was regenerated and rerun under the corrected
  config (nine 16-ELF chunks `priv2-chunk1`–`9`,
  `TIME_OUT=10000000`), so every row below is from the
  corrected config; the three divergence classes reproduced
  identically across both passes.
- Result: **126/134 PASS**, 0 timeouts (ExceptionsSv 2,
  ExceptionsSvSm 4, ExceptionsSvZaamo 2,
  ExceptionsSvZaamoSm 3, ExceptionsSvZalrsc 0/2,
  ExceptionsSvZalrscSm 0/3, PMPF 1, PMPS 10, PMPSm 35/37,
  PMPU 10, PMPZaamo 1, PMPZalrsc 0/1, PMPZca 11, Sv 28,
  SvPMP 4, SvSm 6, Svade 2, Svbare 2, SvbareSm 1,
  Svnapot 4); every PASS log cross-checked (`SUCCESS` +
  `RVCP-SUMMARY: TEST PASSED` + matching cycles).
- Waived divergences (8 rows kept as FAIL/MISMATCH in the
  matrix; each log fingerprinted at merge time):
  1. **LR exception cause class** (6 tests: all
     ExceptionsSvZalrsc* + PMPZalrsc): CVA6 reports LR
     faults with store/AMO causes (misaligned 6 vs 4, page
     fault 15 vs 13, access fault 7 vs 5) because its LSU
     classifies LR on the store side; Sail/ACT classify LR
     as a load. Verified at the faulting `lr.w` (XEPC
     disassembly). Exception *behavior* otherwise matches.
  2. **PMP grain readback** (`PMPSm_grain-00`): for G=1,
     the spec gives NAPOT pmpaddr bit 0 its stored value,
     but `csr_regfile.sv` forces readback bit 0 to 1
     whenever A[1]=1 (the read-as-ones rule applies to
     bits [G-2:0], empty at G=1). Address matching itself
     (grain check suite) passes.
  3. **PA0 data value** (`PMPSm_cfg_A_tor_zero-00`): the
     test loads from physical address 0 and checks data;
     Sail's boot image and the harness debug ROM hold
     different words there (0x8067 vs 0x2). PMP permission
     behavior around the probe passes; the data word is
     platform content, not DUT logic.
- Not generated (0 ELFs, correctly deselected):
  `Misalign` (UDB declares misaligned ld/st unsupported —
  inherited measurement D13 says misaligned scalar accesses
  silently corrupt rather than fault; re-measure before
  claiming), Svadu/SvaduPMP (Svade implemented instead),
  Svinval/SvinvalSm and Svpbmt (no decode/PBMTE at this
  pin, checked in RTL), PMPZicbo/SvPMPZicbo/SvZicbo (no
  Zicbo). Sv48/Sv57 variants deselect against Sv39.
- Linux boot smoke: **not run, assessed out of scope for
  this harness tonight** — it needs cva6-sdk
  OpenSBI/Buildroot images and a linux-gnu toolchain (none
  present) plus ~10^9-cycle Verilator boots, a different
  flow from the tohost regression harness. Tracked as
  follow-up; privileged/Sv39 *spot checks* are the matrix
  above. Tandem lockstep for privileged suites not run.

## Sweep follow-ups — TestFloat conversions + comparisons (2026-10-13, branch `sweep-followups`, issue #20)

- Artifact: [`testfloat-cvt-cva6-2026-10-13.csv`](testfloat-cvt-cva6-2026-10-13.csv)
  (24-row merged matrix in `testfloat-cvt` list order)
- Harness: `scripts/testfloat_cva6.py` extended with
  conversion/comparison classes (float->int, int->float,
  f32<->f64, feq/fle/flt); arithmetic output verified
  byte-identical to the committed generator. Runner gains
  `TEST_LISTS=testfloat-cvt`; `scripts/build_testfloat.sh`
  default op set covers all 36 checkers. Run solo in four
  chunks (`tfcvt-chunk1`–`4`, `TIME_OUT=20000000
  TEST_TIMEOUT_SEC=420`).
- Result: **24/24 PASS**, 290,136 vector executions —
  f32/f64 to i32/i64/ui32/ui64, i32/i64/ui32/ui64 to
  f32/f64, f32->f64, f64->f32 (372–768 level-1 cases
  each), and f32/f64 eq/le/lt (46,464 each). Every log
  cross-checked against its row.
- Flag caveat (float->int only): TestFloat generates
  to-int vectors with SoftFloat `exact=false`, so its
  expected flags never include NX, while RISC-V `fcvt`
  raises NX on inexact conversions (flag distribution in
  the vectors is only {none, NV}). The checkers therefore
  mask NX for the 8 float->int ops and compare the other
  flags exactly; `fcvt` NX behavior itself is covered by
  ACT F/D against Sail (200/200 above). Everything else
  (result bits including saturation, NV) is exact.
- Remaining TestFloat depth under #20: non-RNE rounding
  modes, level-2 density. `roundToInt` has no instruction
  in this config (Zfa `fround` not implemented) and stays
  unclaimed.

## Sweep follow-ups — misaligned-access re-measure (2026-10-13, branch `misalign-probe`, issue #20)

- Artifact: [`misalign-probe-2026-10-13.csv`](misalign-probe-2026-10-13.csv)
  (1 row, PASS); probe source `sw/misalign/probe.S`
- Question: the inherited upstream CVA6+Ara config notes
  (discrepancy D13) claim misaligned scalar accesses
  silently corrupt data; our UDB declares
  `MISALIGNED_LDST: false` with an LSU-trap rationale.
  The probe (53 directed cases: lh/lhu/lw/lwu/ld,
  sh/sw/sd, flw/fld/fsw/fsd, lr.w/lr.d,
  amoadd.w/amoadd.d at every misaligning offset, aligned
  controls, and a no-write-on-trap memory check) runs on
  the scalar model and requires exact mcause per case.
- Result: **PASS** — every misaligned access traps
  (loads cause 4, stores/AMO/LR cause 6, LR store-class
  as in the privileged matrix), trapping stores modify
  nothing, aligned controls do not trap. D13 does not
  apply to this build; `docs/SPIKE_CONFIG.md`-era tandem
  `rv64mi-p-ma_addr` agreement is consistent with this.
- Consequence: `MISALIGNED_LDST: false` stands as
  measured truth, and the ACT `Misalign` suite — which
  requires `MISALIGNED_LDST: true` (hardware handles
  misaligned accesses without trapping) — correctly
  generates zero ELFs for this DUT. Misaligned handling
  by trap is the claim; non-trapping handling is not
  claimed. Config comments updated to cite this probe
  (behavior fields unchanged; no prior ELF changes).

## Sweep follow-ups — TestFloat non-RNE rounding modes (2026-10-13, branch `testfloat-rounding`, issue #20)

- Artifact: [`testfloat-rm-cva6-2026-10-13.csv`](testfloat-rm-cva6-2026-10-13.csv)
  (76-row merged matrix in `testfloat-rm` list order)
- Harness: generator `--rm` sets `frm` per ELF (RNE
  default output verified byte-identical); build script
  `RMODE=rtz|rdn|rup|rmm` generates vectors with the
  matching `testfloat_gen` flag (`-rminMag/-rmin/-rmax/
  -rnear_maxMag`, tininess-after) and stages
  `tf-<op>_<mode>`; runner list `testfloat-rm`
  enumerates all 76. Arithmetic ops are stride-sampled
  to 23,232 cases (half of level-1 binary density;
  mulAdd 23,232 of 6,133,248); conversions run full
  level-1 (372–768).
- Result: **76/76 PASS**, 771,936 vector executions —
  RTZ, RDN, RUP, and RMM each over f32/f64
  add/mul/div/sqrt/mulAdd plus nine conversions
  (f32_to_i32, f32_to_ui64, f64_to_i64, f64_to_ui32,
  i64_to_f32, ui64_to_f64, i32_to_f64, ui32_to_f32,
  f64_to_f32), run solo in eight chunks
  (`tfrm-<mode>-arith/cvt`). Every PASS log
  cross-checked. Single-run reproduce:
  `TEST_LISTS=testfloat-rm` (same selection; chunking is
  a host-stability measure, as in B2.2). Float->int NX
  masking applies as in the conversions evidence.
- TestFloat totals across the three matrices: 112
  checkers, 1,528,080 vectors, all PASS. Remaining
  under #20: level-2 mulAdd density. Sub-operations
  f32_sub/f64_sub rounding is covered at RNE and shares
  the adder rounding path; not separately run per mode.

## B3 — OpenROAD closure, muse_crypto nangate45 (2026-10-13, branch `b3-openroad`, issue #3)

- Artifact: [`b3-openroad-nangate45-2026-10-13.log`](b3-openroad-nangate45-2026-10-13.log)
  (metrics + liberty signoff extract); GDS published as
  the GitHub release asset `b3-nangate45-2026-10-13`
  (`6_final.gds`, 61 MB, not in git).
- Commands: `./scripts/openroad_docker.sh` then
  `./scripts/orfs_liberty_check.sh` (both Dockerized;
  config in `flow/designs/nangate45/muse_crypto/`).
- Baseline (pre-fix run): detail-route DRC 0, antenna 0,
  setup/hold TNS 0 (+5.13/+0.038 ns @ 10 ns), GDS
  written, but 51 post-route max-capacitance violations
  vs liberty (0 at every pre-route stage; final routed
  parasitics exceed estimates by up to 22%).
- Fix (three measured iterations): `EARLY_SIZING_CAP_RATIO
  = 0.8` alone changed nothing (buffering decisions key
  on the full limit); an SDC `set_max_capacitance` repair
  guardband is honored by the resizer at every stage —
  42 fF left 9 liberty violators, 21 fF (26.05/1.223,
  tightest violator class over worst observed growth)
  left 5, all weakest PMOS-stack gates; `DONT_USE_CELLS`
  (with `override` — the platform config is included
  after the design config and otherwise clobbers the
  list) bans NOR3_X1/NOR4_X1/NOR4_X2.
- Final result: **detail-route DRC 0, antenna 0, liberty
  max-cap/slew/fanout violations 0, setup WS +4.52 ns,
  hold WS +0.039 ns, TNS 0/0**; 61,590 stdcells,
  95,431 µm² stdcell area in a 296,867 µm² core (32.1%
  utilized), 20.16 mW total. The 21 fF SDC value is a
  repair target only; signoff is liberty limits via
  `scripts/orfs_liberty_check.sh` (the flow finish
  report counts 2,979 pins over the 21 fF guardband by
  design). Hold margin (+39 ps) is positive but thin —
  recorded, not waived. sky130hd deltas live in
  `flow/designs/sky130hd/muse_crypto/README.md`; no
  sky130hd run is claimed.

## Ara RVV integration — model build + vector smoke (2026-10-13, branch `9-ara-rvv`, issue #9)

- Artifact: [`ara-smoke-2026-10-13.log`](ara-smoke-2026-10-13.log);
  smoke source `sw/ara-smoke/`, runner
  `scripts/ara_docker.sh`.
- System: Ara `34bd3bc1` (2 lanes, VLEN 512) attached
  to its Bender-pinned CVA6 `99eac9a6`
  (`cv64a6_imafdcv_sv39`), verilated with Ara's pinned
  Verilator 5.047 in a native-arm64 container. The
  earlier "host RAM/toolchain" deferral turned out
  avoidable: only Verilator is built from source
  (~3 min), Bender deps come from the lockfile
  (`checkout`, not `update`), the SRAM DPI patch is
  applied, and the smoke kernel compiles with the
  packaged `riscv64-unknown-elf-gcc` — no LLVM build,
  no Docker memory increase (VM remains 7.65 GiB).
- Result: **smoke PASS** — strip-mined `vadd.vv` and
  `vfadd.vv` over 64 elements verified scalar-side,
  exit 0 in 3,751 cycles (~46 kHz); corrupted-expectation
  negative control exits 2; restored kernel re-passes
  deterministically.
- App kernels: [`ara-apps-2026-10-13.csv`](ara-apps-2026-10-13.csv)
  — 15/17 PASS on the model via the GCC substitute path
  (`sw/ara-smoke/run_apps.sh`, packaged
  `riscv64-unknown-elf-gcc` + picolibc specs): hello_world,
  dotproduct, fdotproduct, imatmul, fmatmul, iconv2d,
  fconv2d, jacobi2d, dropout, exp, softmax, pathfinder,
  roi_align, lavamd, fconv3d. `fft` and `dwt` fail with
  numerical errors at VLEN512, but both kernels carry
  single-register-group length assumptions that cannot
  hold at VLEN512 for the shipped problem sizes (`fft`:
  source documents "works if n_fft < VLMAX" and ignores
  the `vsetvl` return value, NFFT=64 vs VLMAX 16 for
  e32m1; `dwt`: vl-doubling accounting needs DWT_LEN=512
  to fit one e32m4 group, i.e. VLEN ≥ 2048). Both PASS
  on a VLEN2048 build of the same model with the same
  GCC toolchain
  ([`ara-apps-vlen2048-2026-10-13.csv`](ara-apps-vlen2048-2026-10-13.csv)),
  so they are classified as kernel VLEN assumptions, not
  hardware or compiler failures; the planned LLVM retest
  is descoped for these two kernels because the failure
  mode is compiler-independent by construction.
- Patched riscv-tests vector list (rv64uv, 177 tests,
  `sw/ara-smoke/run_rvtests.sh`, GCC builds):
  [`ara-rv64uv-2026-10-13.csv`](ara-rv64uv-2026-10-13.csv)
  records 49 PASS / 127 FAIL / 1 TIMEOUT (`vrgather`) at
  VLEN512. Every failing test's source assumes VLEN > 512
  by at least one concrete mechanism — hardcoded
  `VSET(avl, ...)` counts above VLMAX at VLEN512 while
  the `VLOAD`/`VCMP` macros check all `avl` elements;
  widening/narrowing cases that require the wide operand
  to fit one physical register; or `check_vtype_vl`
  requiring `vl == avl` for AVL up to 250 — and no test
  whose source fits VLEN512 fails (first failing element
  index is 8 in the widening cases, exactly one 512-bit
  register of e64). Rebuilt at VLEN2048 (Ara's upstream
  default for `2_lanes`) with the same GCC toolchain, the
  full list passes 177/177
  ([`ara-rv64uv-vlen2048-2026-10-13.csv`](ara-rv64uv-vlen2048-2026-10-13.csv)),
  which confirms the VLEN512 failures are test-source
  VLEN assumptions rather than Ara hardware bugs or GCC
  codegen faults. This suite therefore cannot serve as
  VLEN512 acceptance evidence; the VLEN512 claim rests on
  the smoke kernel, the 15 VLEN-agnostic app kernels, and
  the 49 rv64uv tests that fit VLEN512, pending ACT.
- ACT vector suites with a dedicated DUT config
  (`sw/act4-cva6v/`, derived byte-identically except
  `name:`/`description:` from upstream arch-test
  `6af53584`'s `cv64a6_imafdcv_sv39` config for these
  exact pins at VLEN512; `scripts/ara_docker.sh` applies
  upstream's two DUT-build patches — 16 MiB ELF loader
  window and CVA6 RVB/ZKN enable — so the model matches
  the config; note the model was re-verilated with those
  patches after the rv64uv/apps runs above, with smoke,
  rv64uv 1–10, and `dotproduct` re-verified
  cycle-identical). Generation
  (`scripts/build_act4_cva6v.sh`, Sail-checked) produced
  2,047 ELFs across Vf32/Vf64/Vls8–64/Vx8–64; 34 further
  Vls indexed/segment tests fail at generation time on
  the Sail side ("trap signature overflow", a test-side
  defect independent of the DUT;
  [`act-vector-genfail-2026-10-13.csv`](act-vector-genfail-2026-10-13.csv)).
  Running all 2,047 on the model
  ([`act-vector-cva6v-2026-10-13.csv`](act-vector-cva6v-2026-10-13.csv))
  gives 6 PASS / 2,005 FAIL / 36 TIMEOUT. The failures
  are **not** instruction-result mismatches: 2,032 fail
  at test case 1 inside ACT's self-check compare
  (`RVTEST_SIGUPD_V`: `vmsne.vv` + `vfirst.m` at small
  `vl`) with the reported bad byte equal to the expected
  byte, and the only passes are the scalar-result moves
  (`vmv.x.s`, `vfmv.f.s`) that use the scalar signature
  path. A directed probe
  ([`act-vector-vfirst-probe-2026-10-13.log`](act-vector-vfirst-probe-2026-10-13.log),
  source `sw/act4-cva6v/probe_tail.c`) root-causes this:
  data-path ops honor `vl` and tail-undisturbed exactly,
  but at `vl=1` the Ara mask compare writes NrLanes mask
  bits (2 here, 4 on a 4-lane build) instead of one, and
  `vfirst.m` scans past `vl`, returning NrLanes instead
  of -1 — contrary to RVV 1.0, where `vfirst`/`vpopc`
  examine only active elements (index < `vl`) and
  mask-result tails under `mu` are undisturbed. The 36
  TIMEOUTs (masked `vmadc`/`vmsbc`, `vrgather*`,
  `vcompress`) never halt; every terminating test
  finishes within 26,363 cycles, so these are hangs, not
  slow tests (budgets used: 20M cycles ×1, 5M ×7, 1M ×28,
  recorded per-row in the CSV). Net: ACT vector cannot
  pass on Ara at this pin — at either lane count —
  because of this Ara mask-op deviation, which also
  means full RVV 1.0 compliance **cannot be claimed**
  for the integrated CVA6+Ara system; `vfirst`/`vpopc`
  `vl` bounding and mask-tail behavior are requirements
  carried into the in-house core (#18).
- Open on #9: the synthesis area/timing snapshot, and
  the acceptance decision given the ACT blocker above
  (fix belongs upstream in Ara or in #18; it is not
  fixable in test code without invalidating the
  evidence). Vector compliance is not claimed.
  Resolution: #9 closed as merged with both items
  explicitly descoped; synthesis closure is tracked by
  #11, the ACT requirement by #18.

## In-house core stage 1 — RV64I (2026-10-13, issue #18 branch)

- Artifact: [`core-stage1-2026-10-13.log`](core-stage1-2026-10-13.log)
  (extract of a clean `make core-test` run); design and
  staging plan in [`docs/CORE.md`](../CORE.md), RTL in
  `rtl/core/`, C++ Verilator testbenches in `tb/cpp/`,
  directed software in `sw/core-tests/`.
- Result: ALU unit TB 205,642 checks, decoder unit TB
  10,258 checks (full opcode × funct3 × funct7-sample
  sweep vs an encoding-whitelist golden model), regfile
  unit TB 4,194 checks, directed RV64I assembly (14
  groups: arithmetic/logic/shifts incl. W variants, all
  branches, JAL/JALR, every load/store size and
  extension, `x0`, FENCE, AUIPC) and five expected-trap
  programs (illegal CSR access, misaligned load/store,
  ECALL, EBREAK) all PASS on the single-cycle core.
- Coverage: every annotated source line in `rtl/core/`
  executed (273/273, no `%000000` lines); combined
  line+toggle points 163/273 (59%), the residue being
  toggle/partial-expression points on wide datapaths.
- Bugs found by this loop and fixed before commit: ADDI
  with a negative immediate decoded as SUB, and illegal
  encodings leaking side-effecting control fields (both
  in `muserisc_decoder`); harness read-data settle and
  golden-model slips in two TBs.
- Caveat: this is stage 1 of the plan in
  `docs/CORE.md` — single-cycle RV64I only. No
  compliance claim attaches to it; riscv-tests/ACT
  gates start once CSR/trap state lands (stage 3).

## In-house core stage 2 — M extension + pipeline (2026-10-13, #18)

- Artifact: [`core-stage2-2026-10-13.log`](core-stage2-2026-10-13.log)
  (clean `make core-test` extract); plan in
  [`docs/CORE.md`](../CORE.md).
- Stage 2a (commit `1f280ec`): `muserisc_muldiv` (RV64M incl.
  divide-by-zero and signed-overflow rules, W variants) with a
  C++ unit TB (165,877 checks, `__int128` golden model,
  divisor-biased randoms) and `sw/core-tests/rv64m_directed.S`
  (sign quadrants, div-by-zero, `INT_MIN/-1` at both widths,
  div-mul-rem round trips), verified first on the single-cycle
  core.
- Stage 2b: the core is now a 5-stage in-order pipeline (full
  EX forwarding + WB→ID bypass, one load-use bubble, control
  transfers resolved in EX with two flushed slots, exceptions
  carried to WB so a trapping instruction and everything
  younger write nothing — the last point proven by
  `trap_younger_store.S`). The full stage-1/2a suite stays
  green unchanged, plus `pipeline_directed.S` (forwarding
  chains at distances 1–3, load-use into ALU/branch/JALR/store
  data and address, flush suppressing a fall-through store,
  `x0` never forwarding, dependent accumulate loop).
- Coverage: every annotated `rtl/core/` source line executed
  (456/456); combined line+toggle points 314/456 (68%),
  deterministic across reruns. `make test` and `make lint`
  also pass at this commit.
- Caveat: the divider is combinational (correctness vehicle,
  not timing-closable — an iterative divider replaces it
  before any synthesis target), and traps still halt the
  machine at WB; real trap state is stage 3. No compliance
  claim attaches yet.

## In-house core stage 3a — CSRs, privilege, traps, PMP (2026-10-13, #18)

- Artifact: [`core-stage3a-2026-10-13.log`](core-stage3a-2026-10-13.log)
  (`make core-test` extract); plan in
  [`docs/CORE.md`](../CORE.md).
- New `muserisc_csr` (505 lines): M/S/U CSR file with spec write
  masks, `sstatus`/`sie`/`sip` masked views, counters,
  trap entry/return with delegation (`medeleg`/`mideleg`),
  direct+vectored trap targets, interrupt priority
  (MEI > MSI > MTI > SEI > SSI > STI), and 16 PMP entries
  (OFF/TOR/NA4/NAPOT, W-without-R WARL, entry and
  adjacent-TOR locking). The pipeline takes precise traps at
  WB (trapping instruction and everything younger write
  nothing), injects interrupts in ID for a precise `epc`,
  executes CSR ops in EX committing on the EX→MEM edge, and
  checks PMP on fetch and data (with MPRV applied to data).
  `trap_halt_i` preserves the stage-1/2 freeze-and-report mode
  for the directed trap TBs.
- Verification: new C++ CSR unit TB (117 checks at the module
  ports), decoder TB grown to 12,311 checks for the SYSTEM
  space, and `sw/core-tests/priv_directed.S` (14 groups:
  CSR masks, MRET/SRET, delegation, PMP R/W/X denials
  including a NAPOT execute-deny instruction access fault,
  M timer IRQ and a delegated S timer IRQ with precise
  `epc`, counters, MPRV, privilege violations) — all PASS
  alongside the unchanged stage-1/2 suite.
- Coverage: every annotated `rtl/core/` source line executed
  (876/876); combined line+toggle points 475/926 (51%).
  `make test` and `make lint` also pass at this commit.
- One coverage-driven RTL cleanup: `pmp_locked` rewritten
  from early-`return` form to a single expression (identical
  semantics, proven by the same lock readback checks)
  because Verilator attributes no count to the nested
  return line even when the path provably executes.
- Caveat: `satp` is stored but no translation exists yet —
  Sv39+Svnapot MMU is stage 3b, followed by the riscv-tests
  and ACT stage gates (3c/3d). No compliance claim attaches
  yet.

## In-house core stage 3b — Sv39+Svnapot MMU (2026-10-13, #18)

- Artifact: [`core-stage3b-2026-10-13.log`](core-stage3b-2026-10-13.log)
  (`make core-test` extract); plan in
  [`docs/CORE.md`](../CORE.md).
- New `muserisc_mmu` (408 lines): unified 32-entry
  fully-associative TLB with fetch and data lookup ports,
  one walker sharing the core data port (data misses
  preempt fetch walks), Sv39 4K/2M/1G, Svnapot 64K,
  ASID+global, hardware A/D (Svadu), full-flush SFENCE,
  and recorded walk faults that die when the requester's
  VA moves on (no negative caching). Fetch translates in
  IF (stalling there on a miss); a data miss parks the
  access in MEM and holds the pipeline, with younger CSR
  writes and xRETs gated so nothing commits ahead of a
  possibly-faulting older access. PMP now checks physical
  addresses, with a new third port for implicit PTE
  accesses (S-mode); `satp` MODE is WARL-clamped.
- Verification: new C++ MMU unit TB (53 checks against
  hand-built page tables in TB memory: walks, superpages,
  NAPOT, canonicality, malformed PTEs, U/SUM/MXR, A/D
  writebacks incl. PMP-denied writeback, ASID/global,
  fault auto-clear, data-preempts-fetch) and
  `sw/core-tests/vm_directed.S` (14 groups on the running
  core, page faults 12/13/15 with `tval`, U excursion,
  SFENCE staleness, MPRV) — all PASS, stage-1..3a suite
  unchanged.
- Coverage: every annotated `rtl/core/` source line executed
  (1126/1126); combined line+toggle points 621/1210 (51%).
  `make test` and `make lint` also pass at this commit.
- Caveat: translation exists but no upstream suite has
  judged it yet — riscv-tests (3c) and ACT + a Linux boot
  attempt (3d) are next. No compliance claim attaches yet.

## In-house core stage 3c — riscv-tests gate (2026-10-13, #18)

- Artifact: [`riscv-tests-core-2026-10-13.csv`](riscv-tests-core-2026-10-13.csv)
  (per-test result and cycle count); reproduce with
  `make riscv-tests` (runner:
  [`sim/run_riscv_tests.sh`](../../sim/run_riscv_tests.sh)).
- Result: **64/64 PASS** at stage 3c — every `rv64ui-p-*` (51) and
  `rv64um-p-*` (13) test from the in-tree riscv-tests
  sources, compiled with the upstream recipe and run on
  the in-house core through the C++ harness's new ELF/HTIF
  mode (PT_LOAD placement, `boot_pc_i` = ELF entry,
  `tohost` exit). The gate has since been extended to
  the privileged `rv64mi-p-*`/`rv64si-p-*` suites
  (80/80; see stage 4.0 note in the 3d section).
  Cross-checks: three of the CVA6-built
  ELFs pass with identical cycle counts, and a hand-made
  HTIF failure probe is correctly reported as FAIL
  (the harness cannot pass vacuously).
- Core/harness changes: a `boot_pc_i` reset-PC input, and
  paged memory + ELF64/HTIF support in `tb/cpp/core_tb.cpp`
  (flat-binary directed mode unchanged). One toolchain
  shim: this riscv-tests vintage writes `satp` via its
  pre-1.10 alias `sptbr`, which modern binutils rejects;
  the runner shadows `env/p/riscv_test.h` with a renamed
  copy. No test logic is altered.
- Coverage: every annotated `rtl/core/` source line executed
  (1127/1127, one ELF run contributes to the merge);
  `make core-test`, `make test`, and `make lint` also pass
  at this commit.
- Caveat: riscv-tests are a smoke-grade suite, not
  architectural certification — ACT I/M (and a Linux boot
  attempt) in stage 3d is the stricter judge. No
  compliance claim attaches yet. Note this riscv-tests
  vintage has no `ma_data`/misaligned or virtual-memory
  (`-v-`) variants in the `rv64ui` directory; the `-p-`
  set above is complete for that tree.

## In-house core stage 3d — ACT I/M + privileged suites (2026-10-13, #18)

- Artifact: [`act-core-impriv-2026-10-13.csv`](act-core-impriv-2026-10-13.csv);
  DUT config in [`sw/act4-core/`](../../sw/act4-core/)
  (README there records the generation commands and the
  sail.json derivation), built by
  [`scripts/build_act4_core.sh`](../../scripts/build_act4_core.sh)
  and run by [`sim/run_act_core.sh`](../../sim/run_act_core.sh).
- Result: **ACT I + M 64/64 PASS**, and the privileged
  suites for the declared scope (ExceptionsSv/SvSm, PMP
  S/Sm/U/F, Sv, SvPMP, SvSm, Svbare/Sm, SvaduPMP) bring
  the total to **180/181 PASS**. Self-checking ELFs are
  judged by their HTIF halt on the same C++ harness as
  the directed tests.
- Sole waiver: `PMPSm_cfg_A_tor_zero-00`, the same
  platform divergence waived for the CVA6 host above —
  its probes store/load/execute at PA 0, which Sail's
  memory map access-faults (no region) while this
  harness has RAM there, so the expected traps never
  occur. Fixing it for real needs a bus-fault input on
  the core (SoC-stage work), not a core change.
- ACT earned its keep: triage of the first run (37 priv
  failures) found and fixed five real RTL bugs —
  `misa` had the wrong letter bits (A/Q instead of S),
  pmpcfg reserved bits [6:5] read back instead of
  reading zero, the R0W1→R0W0X0 WARL clearing also ate
  legal X-only entries, `mstatus.TVM` did not trap
  `satp` access from S, `MPRV` was incorrectly cleared
  on trap entry, and instruction-address-misaligned was
  attributed to the jump target's fetch instead of the
  jump instruction (plus counter-enable CSR masks and
  counter access gating added during config). The
  directed CSR TB and `vm_directed.S` were wrong in two
  places for the same old behaviors and were corrected
  (one vm-test fix is itself a lesson: after `mret`,
  MPP=U with MPRV retained makes M-mode loads translate
  as U).
- Coverage: every annotated `rtl/core/` source line executed
  (1143/1143) after the fixes; `make core-test`,
  `make riscv-tests` (64/64), `make test`, and
  `make lint` also pass at this commit.
- Still not a compliance claim: ACT coverage is bounded
  by the declared configuration (RV64IM + priv/Sv39
  scope) and this run is simulation only. A Linux boot
  attempt is the remaining stage-3d item.

- Stage 4.0 follow-up (same branch as stage 4): the
  `rv64mi`/`rv64si` probe failures are closed. `access`
  needed the architectural 56-bit physical-address limit
  enforced (fetch/load above 2^56 now access-fault; two
  directed trap tests added), gated on translation
  completion after ACT caught the first cut faulting
  high-canonical VAs mid-walk; `breakpoint` needed
  zero-trigger Sdtrig CSR stubs (read 0, writes ignored).
  The riscv-tests gate now includes mi/si (**80/80**,
  the CSV above is refreshed in place) and ACT is back
  at 180/181 with the same single waiver.

## In-house core stage 4a — A extension (2026-10-13, #18)

- Same artifacts, refreshed in place:
  [`riscv-tests-core-2026-10-13.csv`](riscv-tests-core-2026-10-13.csv)
  is now **99/99** (adds `rv64ua-p-*`, 19 tests) and
  [`act-core-impriv-2026-10-13.csv`](act-core-impriv-2026-10-13.csv)
  is now **214/215** (adds Zaamo/Zalrsc +
  ExceptionsSvZaamo/Zalrsc + PMPZaamo/PMPZalrsc; same
  single `tor_zero` waiver).
- Implementation: MEM-stage RMW against the loaded value
  (combinational memory makes AMOs single-cycle), physical
  LR/SC reservation with exact-access semantics (SC must
  lie inside the LR's range; cleared by SC, overlapping
  stores, and traps), `misa` gains A. Directed coverage:
  `sw/core-tests/amo_directed.S` (all 9 AMO ops × W/D where
  meaningful, LR/SC success and failure modes), decoder TB
  12,317 checks.
- One real bug found by ACT PMPZalrsc on first run: AMO/SC
  did not declare their rs2 source to the load-use
  interlock, so an SC immediately after its LR stored a
  stale register value. Fixed in `id_uses_rs2`; a directed
  back-to-back LR→SC regression is test 8 of
  `amo_directed.S`.

## In-house core stage 4b — F/D floating point (2026-10-13, #18)

- New `rtl/core/muserisc_fpu.sv`: combinational IEEE-754
  binary32/64 (add/sub/mul/div/sqrt/FMA×4, sign-inject,
  min/max, compares, class, all conversions, FMV), one
  shared round-and-pack stage, canonical-NaN results,
  NaN-boxing on S ops. Verified by
  [`tb/cpp/fpu_tb.cpp`](../../tb/cpp/fpu_tb.cpp) against
  Berkeley SoftFloat 3: 690,071 checks (random sweep over
  all ops × 5 rounding modes × both formats, plus directed
  specials and tininess-boundary regressions).
- Pipeline: separate 32×64 FP register file (3 read ports),
  full EX forwarding for FP sources incl. FMA rs3, load-use
  interlock for FLW/FLD, `mstatus.FS` with precise Dirty
  tracking, `fflags` accumulation from EX, dynamic-`frm`
  legality checked in EX, `misa` += F,D.
- Gates: `fp_directed.S` + decoder/CSR/FPU unit TBs green;
  [`riscv-tests-core-2026-10-13.csv`](riscv-tests-core-2026-10-13.csv)
  now **122/122** (adds `rv64uf`+`rv64ud`, 23 tests);
  [`act-core-impriv-2026-10-13.csv`](act-core-impriv-2026-10-13.csv)
  now **414/415** (adds full ACT F and D suites; same
  `tor_zero` waiver). Line coverage: everything except the
  FPU at 100%; `muserisc_fpu.sv` 482/493 merged with ACT
  runs (remainder: defensive default arms for op/rm codes
  the decoder never emits).
- Two real bugs found by ACT (both now regression-tested):
  (1) unpacked ±0 carried exponent `emin`, out-ranking
  tiny subnormals in add/FMA alignment and compares —
  fixed with a below-range exponent for zero; (2) underflow
  tininess must follow Berkeley's rule (jammed significand
  + rounding increment vs 2^emin), not simply "rounded
  result is subnormal".

## In-house core stage 4c — B, Zicond, scalar crypto (2026-10-13, #18)

- New `rtl/core/muserisc_bext.sv`: Zba/Zbb/Zbc/Zbs, Zicond,
  Zbkb/Zbkc(clmul)/Zbkx, Zkne/Zknd (aes64es/esm/ds/dsm/im/
  ks1i/ks2), Zknh (SHA-256/512 sigma/sum). AES S-boxes are
  derived at elaboration from the GF(2^8) inverse; the C++
  golden in [`tb/cpp/bext_tb.cpp`](../../tb/cpp/bext_tb.cpp)
  uses the literal FIPS-197 tables — 54,980 independent
  checks. `bext_directed.S` adds a full AES-128 encryption
  KAT (FIPS-197 vector) built from the scalar instructions
  inside the pipeline. `misa.B` set.
- ACT:
  [`act-core-impriv-2026-10-13.csv`](act-core-impriv-2026-10-13.csv)
  now **494/495** — adds Zba(8) Zbb(24) Zbc(3) Zbs(8)
  Zicond(2) Zbkb(14) Zbkc(2) Zbkx(2) Zkne(4) Zknd(5)
  Zknh(8), all green; same `tor_zero` waiver. riscv-tests
  unchanged at 122/122 (no B/K suites exist upstream there).

## In-house core stage 5 — C extension (Zca/Zcb/Zcd) (2026-10-13, #18)

- New `rtl/core/muserisc_rvc.sv`: combinational decompressor
  expanding every Zca/Zcb/Zcd 16-bit form (incl. RV64-only
  `c.addiw`/`c.addw`/`c.subw`/`c.ld`/`c.sd` and Zcb
  byte/halfword loads/stores) to its canonical 32-bit
  instruction; reserved/hint space outside the declared
  extensions raises illegal-instruction. Fetch gained a
  realigner: misaligned (2-byte) PCs fetch the aligned word
  and take the high parcel, and a 32-bit instruction
  straddling a page boundary buffers its first half while
  the second half is fetched (a fault on the second half
  reports `tval = pc+2`, `epc = pc`). IALIGN is now 16:
  jump/branch targets no longer raise address-misaligned
  (fetch faults surface at fetch), `xepc` writes keep bit 1,
  `misa` = `0x8000_0000_0014_112F` (RV64 IMABC FD SU).
  `sw/core-tests/trap_instr_misalign.S` deleted (the case
  no longer exists architecturally).
- Verification: [`tb/cpp/rvc_tb.cpp`](../../tb/cpp/rvc_tb.cpp)
  checks the decompressor against an independent golden
  expander over all directed forms plus randomized parcels
  (49,152 checks); `sw/core-tests/rvc_directed.S` covers
  mixed 16/32-bit streams, misaligned branches/jumps, and
  compressed loads/stores in the pipeline.
- Gates: `make core-test` green;
  [`riscv-tests-core-2026-10-13.csv`](riscv-tests-core-2026-10-13.csv)
  now **123/123** (adds `rv64uc-p-rvc`);
  [`act-core-impriv-2026-10-13.csv`](act-core-impriv-2026-10-13.csv)
  now **543/544** (adds Zca/Zcb/Zcd and the ZcbZba/ZcbZbb/
  ZcbZmmul combined suites, 49 tests; same single
  `PMPSm_cfg_A_tor_zero` platform waiver — PA0 is RAM in
  this harness but access-faults in the Sail memory map).
- Three encoding bugs were caught by the RVC TB / ACT
  before this gate and are regression-covered: D-form
  load/store immediate bit order, Zcb `c.lh`/`c.sh` select
  and offset mapping, and `c.mul` expanding to MULW
  (OP-32) instead of MUL (OP).
- Flow note: `ExceptionsSv` S/U initially "failed" against
  stale ACT artifacts generated under the pre-C config
  (Sail expectations assumed IALIGN=32; the ACT make does
  not track DUT config changes as dependencies). The core
  was correct; regenerating the priv suites from the
  current config restored 543/544 with no RTL change. The
  regeneration commands, including this caveat, are in
  [`sw/act4-core/README.md`](../../sw/act4-core/README.md).

## Crypto accelerator integration check (2026-10-13, #18)

Inventory of the repo's two distinct crypto layers after
stages 4c/5:

- **In-core scalar crypto** (Zbkb/Zbkc/Zbkx, Zkne/Zknd/Zknh
  in `muserisc_bext.sv`): integrated in the pipeline and
  covered by the ACT gate above plus `bext_directed.S`
  (full AES-128 FIPS-197 KAT from scalar instructions,
  SHA-256/512 sigma/sum ops).
- **Standalone accelerators** (`rtl/crypto/`):
  `sha256_block`, `sha512_block`, `keccak_f1600` and the
  256-bit `ec_field` unit behind the AXI4-Lite slave
  `muse_crypto_top` (SHA-256 block + EC field exposed;
  Keccak engine select reserved pending a streaming
  interface; SHA-512 verified standalone, not yet behind
  the AXI top). `muserisc_soc_top` exposes the AXI-Lite
  port at `0x2000_0000`, but no core/bus drives it yet —
  attaching the in-house core (Harvard SRAM ports today)
  needs a bus bridge + MMIO window + driver, which is B4
  SoC integration (#4), explicitly deferred. No core-side
  integration is claimed.
- Gap found and closed by this check: the leaf engines had
  KATs but the AXI4-Lite register layer had never been
  simulated. New `tb/tb_muse_crypto_top.v` (wired into
  `make test`) drives the documented register map end to
  end reusing leaf-KAT vectors: SHA-256("abc") and
  SHA-256("") digests, EC field mul/sub under secp256k1
  and Curve25519 MODSEL, custom-modulus regs, STATUS
  done-clearing on CTRL write, and reserved engine 1
  leaving STATUS idle. `TB_MUSE_CRYPTO_TOP PASS`; full
  `make test` remains `ALL PHASE-0 KATs PASS`.

### Linux/OpenSBI boot attempt — blocked on A (stage 4)

- Log: [`core-stage3d-linux-attempt-2026-10-13.log`](core-stage3d-linux-attempt-2026-10-13.log).
  OpenSBI generic builds cleanly under Docker with a
  Linux toolchain, but targets RV64GC (59% compressed
  instructions) and — decisively — refuses to configure
  without atomics: `riscv_locks.c: #error "need A or
  Zaamo or Zalrsc"` under `PLATFORM_RISCV_ISA=rv64im_*`.
  The boot is therefore gated on stage 4 (A) and, for
  stock binaries, stage 5 (C); harness CLINT/UART models
  are the remaining small pieces. No boot is claimed.
  This historical block was superseded by stage 6 below.

## In-house core stage 6 — OpenSBI and Linux boot (2026-10-14, #21)

- New platform harness
  [`tb/cpp/soc_tb.cpp`](../../tb/cpp/soc_tb.cpp) around the
  same core (the compliance `core_tb` remains the gate
  harness): boot ROM at `0x1000` presenting `a0=hartid` /
  `a1=DTB`, CLINT at `0x0200_0000`, PLIC at `0x0C00_0000`,
  byte-wide 16550 UART at `0x1000_0000`, and 128 MiB RAM at
  `0x8000_0000`. The machine is described by
  [`sw/linux/muserisc.dts`](../../sw/linux/muserisc.dts).
- [`scripts/build_opensbi.sh`](../../scripts/build_opensbi.sh)
  builds generic OpenSBI `fw_jump` (`0x8020_0000`) and the
  DTB in Docker. OpenSBI v1.9 boots and enters an S-mode
  payload: [`core-stage6a-opensbi-2026-10-14.log`](core-stage6a-opensbi-2026-10-14.log)
  ends with `HELLO FROM S-MODE`.
- [`scripts/build_linux_kernel.sh`](../../scripts/build_linux_kernel.sh)
  builds Linux 6.6 `defconfig` (modules and debug info off)
  with the static embedded-initramfs `/init` from
  [`sw/linux/init.c`](../../sw/linux/init.c). The recorded
  boot used this explicit kernel command line from the DT:
  `console=ttyS0,115200 earlycon=sbi cryptomgr.notests
  initcall_debug loglevel=8 rw`; in particular, crypto
  self-tests are disabled for this evidence run.
- Linux gate:
  [`core-stage6-linux-boot-2026-10-14.log`](core-stage6-linux-boot-2026-10-14.log).
  `SOC TB PASS` at **508,905,040 cycles**. The kernel
  reaches `Run /init as init process`, `/init` prints
  `muserisc init: userspace alive`, reports
  `uname: Linux 6.6.0 ... riscv64`, reads `/proc/version`,
  and prints `MUSERISC_LINUX_BOOT_OK`.
- Two real core bugs were found by this boot and are now
  regression-covered. (1) CSR writes commit in EX while
  traps commit at WB, so OpenSBI's younger `mtvec` restore
  beat its probing trap to the vector;
  `trap_younger_csr.S` failed before the `!mem_exc` gate and
  passes after it. (2) `time` was aliased to inhibited
  `mcycle`; OpenSBI PMU stop-all sets `mcountinhibit.CY`,
  which froze Linux's clocksource at `pmu_sbi_devinit`.
  `time` now has an independent real-time counter, covered
  by the CSR unit TB and `counter_time_directed.S`. A
  harness-only walker-starvation bug (page-table walks do
  not assert `dmem_re_o`) was also found and fixed in
  `soc_tb`; the page tables and core walker were correct.
- Final gates after both RTL fixes: `make core-test` and
  `make lint` green, `make test` = `ALL PHASE-0 KATs PASS`,
  [`riscv-tests-core-2026-10-14.csv`](riscv-tests-core-2026-10-14.csv)
  **123/123**, and
  [`act-core-impriv-2026-10-14.csv`](act-core-impriv-2026-10-14.csv)
  **543/544** (same `PMPSm_cfg_A_tor_zero` PA0 platform
  waiver).
- Claim boundary: this is a single-hart Verilator platform
  boot to a small embedded initramfs `/init`, not a distro,
  shell, block/network-device, SMP, H/KVM or V claim, and
  it does not integrate `muse_crypto_top` with the core
  (B4/#4 remains deferred).

## In-house core stage 7 — H hypervisor and KVM smoke (2026-10-14, #22)

- Stage 7a adds the virtualization mode bit, HS/VS CSR banks
  with S↔VS substitution, two-level trap delegation
  (M → HS → VS), virtual-instruction exceptions, and
  `misa.H`. Stage 7b adds two-stage Sv39 + Sv39x4 address
  translation in `muserisc_mmu.sv`, including G-stage
  translation of VS page-table accesses, combined 4 KiB TLB
  fills tagged by ASID/VMID, and guest-page faults
  (causes 20/21/23) with `htval`/`mtval2`. Stage 7c adds
  HLV/HSV/HLVX and HFENCE.VVMA/GVMA. Stage 7d completes VS
  interrupt selection and `hvip` injection. GEILEN is 0.
- First-party gates: CSR TB **196 checks**, MMU TB
  **74 checks**, decoder TB **12,332 checks**, and
  `hyp_directed.S` (M → HS → VS → VU entry, guest ecalls,
  virtual instructions, two-stage store, guest-page fault
  with `htval`, HLV/HSV/HLVX from HS, HFENCE remapping, an
  HLV guest fault reporting `hstatus.GVA`, and an injected
  VSSI handled and cleared in VS) — all inside
  `make core-test`, with `make lint` green.
- Upstream gates re-run on the Stage 7 core:
  [`riscv-tests-core-stage7-2026-10-14.csv`](riscv-tests-core-stage7-2026-10-14.csv)
  **123/123**, and
  [`act-core-stage7-2026-10-14.csv`](act-core-stage7-2026-10-14.csv)
  **543/544** (only the known `PMPSm_cfg_A_tor_zero-00`
  PA0 platform waiver). The pinned ACT tree contains no
  hypervisor suite (`tests/priv/` has no H tests), so there
  is no ACT H result to report; the ACT config now declares
  H for when a suite exists. `make test` still reports
  `ALL PHASE-0 KATs PASS`.
- KVM smoke:
  [`core-stage7-kvm-smoke-2026-10-14.log`](core-stage7-kvm-smoke-2026-10-14.log).
  With `riscv,isa = "rv64imafdcbh"` in the DT, Linux 6.6
  reports `kvm [1]: hypervisor extension available`,
  `using Sv39x4 G-stage page table format`, and `VMID 14
  bits available`. The embedded `/init`
  ([`sw/linux/kvm_smoke.c`](../../sw/linux/kvm_smoke.c),
  built with `MUSERISC_INIT_SRC=sw/linux/kvm_smoke.c
  MUSERISC_IMAGE_OUT=build/linux/Image-kvm
  scripts/build_linux_kernel.sh`) opens `/dev/kvm`,
  creates a VM and one vCPU with a 4 KiB RAM slot at GPA
  `0x1000`, and runs a four-instruction VS-mode guest. The
  guest's store of 42 to MMIO GPA `0x2000` exits with
  `KVM_EXIT_MMIO` (`addr=0x2000 len=4 write=1 data=42`),
  `/init` prints `MUSERISC_KVM_OK`, and the harness reports
  `SOC TB PASS` at **502,972,620 cycles**.
- Claim boundary: this is a one-vCPU KVM entry/exit smoke
  with a four-instruction bare-metal guest on the Verilator
  platform. It is not a guest-OS boot, not SMP, not an
  AIA/IMSIC or external-interrupt-virtualization claim
  (GEILEN=0, no PLIC guest context), and not a substitute
  for a future ACT hypervisor suite.

## In-house core stage 8 — integer V vector (2026-10-14, #23)

- Scope: integer RVV 1.0 (Zve32x/Zve64x, Zvl512b) with
  VLEN=512, ELEN=64 in `muserisc_vec.sv` /
  `muserisc_vregfile.sv` plus the MEM-stage element
  sequencer in `muserisc_core.sv`. Floating-point vector
  (Zve32f/Zve64f/Zve64d, i.e. full V) is **not**
  implemented; `misa.V` is set on the strength of the
  integer subset, so the claim for stage 8 is the integer
  vector subset only. Tail/mask-agnostic is implemented
  as undisturbed (matching the Sail reference
  configuration in `sw/act4-core/sail.json`).
- First-party gates: vector unit TB
  **1,014,476 checks** and `vec_directed.S` inside
  `make core-test`; `make lint` green.
- ACT vector result:
  [`act-core-stage8-2026-10-14.csv`](act-core-stage8-2026-10-14.csv)
  records all 1,936 generated self-checking ELFs run on
  the core (1,872 Vx/Vls vector + 51 I + 13 M):
  **1,936/1,936 PASS**. Generation used
  `scripts/build_act4_core.sh` with `sw/act4-core/`
  config; ELFs run via `build/sim/core_tb`.
- Tests not run (43), listed in
  [`act-vector-core-genfail-2026-10-14.csv`](act-vector-core-genfail-2026-10-14.csv):
  34 ordered-indexed load/store tests (`vlox*`/`vsoxseg*`
  in Vls8/16/32) fail Sail signature *generation* with
  `Trap signature overflow in sig mode` before any DUT
  is involved, so no self-checking ELF exists for them;
  9 Vx64 `vmulh`/`vsmul` tests are deselected by ACT's
  extension filter because their test config requires
  full `V`. Unordered indexed (`vlux*`/`vsux*`) and
  `vmulh` at SEW 8/16/32 are inside the passing set.
- Not re-run at this stage: the SoC Linux/KVM smokes
  (green at stages 6/7) and riscv-tests (123/123 at
  stage 7); scalar behavior is covered here by
  `make core-test` and the I/M ACT ELFs above.

## In-house core stage 9 — floating-point V vector (2026-10-14, #29)

- Scope: FP vector classes (Zve32f/Zve64f/Zve64d) in
  `muserisc_decoder.sv` (OP-V funct3 001/101 carve-out),
  `muserisc_vec.sv` (per-element execution through the
  shared scalar `fp_eval`/`fp_estimate` in
  `muserisc_fpu_pkg.sv`, extracted in stage 9a), and
  `muserisc_core.sv` (FP scalar operand from the FP
  regfile, accrued `fflags`, FS/SEW/frm legality).
  Covers binary/widening arithmetic, FMA (incl. the
  `vfwmacc` family), compares, sqrt/class,
  `vfrec7`/`vfrsqrt7` estimates, all conversions
  (incl. round-to-odd `vfncvt.rod`), ordered/unordered
  reductions, and FP moves/slides. Full `V` and FP16
  (the ACT Vf16 suite) are **not** claimed; `misa.V`
  remains set on the integer+FP subsets above.
- First-party gates: vector unit TB **1,014,624 checks**
  (HOST-oracle FP section incl. estimates and ROD),
  `fpvec_directed.S` + all suites inside
  `make core-test`, `make lint` green, FPU TB unchanged
  at **690,071 checks**. The `vfrec7`/`vfrsqrt7` tables
  were extracted from the Sail reference with an
  exponent/fraction/sign sweep probe and verified
  bit-exact (results and flags) over 10,792
  operand/result pairs, then re-verified on the DUT by
  signature diff of the same probe programs.
- ACT FP-vector result:
  [`act-fpvector-stage9-2026-10-14.csv`](act-fpvector-stage9-2026-10-14.csv)
  records all 162 generated self-checking ELFs run on
  the core (100 Vf32 + 62 Vf64): **162/162 PASS**.
  Generation: `EXTENSIONS=Vf32,Vf64
  ./scripts/build_act4_core.sh` after declaring
  Zve32f/Zve64f/Zve64d in `sw/act4-core/` and setting
  the Sail `support_level` to `Float_double`.
- Tests not run: the privileged `ExceptionsVf*` suites
  are deselected by the ACT framework for this DUT
  config because their test config requires `Zfhmin`
  and full `V`; FP-vector illegality (FS off, reserved
  `frm`, SEW<32) is covered by `fpvec_directed.S` and
  Sail probes instead. 4 of the 66 Vf64 sources
  (`vfmv.f.s`, `vfmv.s.f`, `vfslide1up.vf`,
  `vfslide1down.vf`) generated no ELF because their
  test config requires full `V`; the same instructions
  are covered in Vf32 above and in `fpvec_directed.S`.
  Integer ACT spot re-runs (Vx32, I) after the stage-9
  changes are recorded in the issue.

## Crypto/SoC RTL SystemVerilog port (2026-10-14, #19)

- `rtl/crypto/*.v` and `rtl/soc/muserisc_soc_top.v`
  ported to `.sv` (behavior-identical: `logic`,
  `always_ff`/`always_comb`, typed `automatic`
  functions). Function bodies keep assignment-to-name
  style because the Yosys classic frontend rejects
  `return` statements.
- Gates after the port: `make test` → `TB_SHA256 PASS`,
  `TB_KECCAK PASS`, `TB_SHA512 PASS`, `TB_EC_FIELD
  PASS`, `TB_MUSE_CRYPTO_TOP PASS`,
  `ALL PHASE-0 KATs PASS` (iverilog `-g2012` against
  the unchanged `tb/*.v` benches); `make lint` and
  `make core-test` green.
- Synthesis: local Yosys `read_verilog -sv` clean, and
  the ORFS synth stage re-ran on the `.sv` sources via
  `scripts/openroad_docker.sh
  results/nangate45/muse_crypto_top/base/1_2_yosys.v`
  (exit 0, no synth-log errors). The full P&R flow was
  **not** re-run for the `.sv` sources; the b3 GDS
  evidence above remains the P&R record for this
  (behavior-identical) design.
- Remainder of #19: migrating the `tb/*.v` benches to
  Verilator/cocotb is still open.

## Crypto testbench Verilator migration (2026-10-14, #19)

- The five Icarus benches (`tb/tb_sha256.v`,
  `tb/tb_sha512.v`, `tb/tb_keccak.v`, `tb/tb_ec_field.v`,
  `tb/tb_muse_crypto_top.v`) are replaced by C++
  Verilator benches in `tb/cpp/` with the same KAT
  vectors and pass markers: `sha256_tb.cpp`,
  `sha512_tb.cpp`, `keccak_tb.cpp`, `ec_field_tb.cpp`,
  and `crypto_top_tb.cpp`.
- Build/run wiring lives in `sim/Makefile` (`make -C sim
  crypto`); the top-level `make test` now runs the
  Python golden models plus those targets and still
  ends with `ALL PHASE-0 KATs PASS`. Icarus Verilog is
  no longer a host prerequisite for the fast gates.
- No RTL changed in this step.

## QEMU reference-boot oracle spike (2026-10-14, #30)

- QEMU cannot execute RTL; it is used only as a fast
  software oracle for the same Linux payload. The
  Verilated `soc_tb` log above remains the only
  "Linux on our RTL" evidence. Full note and decision:
  [`docs/QEMU.md`](../QEMU.md).
- System mode: `scripts/qemu_reference_boot.sh` boots
  the exact `build/linux/Image` from the stage-6 gate
  under `qemu-system-riscv64 -machine virt` (Docker,
  QEMU 8.2.2, bundled OpenSBI v1.3) and diffs the
  platform-independent markers (kernel banner,
  `muserisc init`, `uname`, `/proc/version`,
  `MUSERISC_LINUX_BOOT_OK`) against
  `core-stage6-linux-boot-2026-10-14.log`: **match**
  (`QEMU REFERENCE BOOT PASS`). Captured log:
  [`qemu-virt-reference-boot-2026-10-14.log`](qemu-virt-reference-boot-2026-10-14.log)
  (263 lines). All remaining deltas are platform/DT/
  firmware/harness (virt DT, OpenSBI version, 256 MiB
  vs 128 MiB RAM, PLIC interrupt count, baud reporting,
  no cycle count); none is a core-behavior difference.
- User mode: `scripts/qemu_user_oracle.sh` builds
  `sw/qemu/user_oracle.c` as a static RISC-V binary
  and runs it under `qemu-riscv64`, producing
  `MUSERISC_QEMU_USER_OK x=655d5f49 sum=325770522
  acc=17500.0`.
- Decision: boot-log marker diffing plus the user-mode
  smoke are sufficient. A lockstep trace-compare
  harness is not worth building now, because QEMU
  virt and `soc_tb` differ as platforms; ISA-level
  differential coverage already comes from
  riscv-tests, ACT vs Sail, and the unit TBs.

## OpenROAD P&R rerun on current .sv sources (2026-10-14, #31)

- Full ORFS rerun of the nangate45 `muse_crypto_top`
  macro on the current `.sv` sources. This supersedes
  the #19 note above ("full P&R was not re-run"): it
  has now been re-run. Scope is the crypto macro
  only — GDS generated / place-and-route complete,
  not a tapeout, not full-SoC closure (#11), and no
  core-timing claim. Full log with the b3 comparison
  table:
  [`openroad-nangate45-31-2026-10-14.log`](openroad-nangate45-31-2026-10-14.log).
- Rerun 1 (b3 cell ban) closed timing but liberty
  signoff (`scripts/orfs_liberty_check.sh`) found 3
  new max-capacitance violators, all AOI221_X1
  (13.81 fF limit) or OAI221_X1 (22.16 fF).
  `flow/designs/nangate45/muse_crypto/config.mk`
  now also bans those two cells.
- Rerun 2 (released): setup WS 4.34 ns, hold WS
  0.039 ns, setup/hold TNS 0 at the 10 ns
  (100 MHz) constraint; ORFS fmax estimate
  176.7 MHz; 63,474 stdcells, die 308,436 um2,
  utilization 0.321, total power 0.0211 W; route
  DRC 0, antenna 0, liberty max-cap/max-slew/
  max-fanout violators 0. `6_final.gds` (60 MB) is
  published as a GitHub release asset, not in git.

## Shallow AES S-box in muserisc_bext (2026-10-15, branch `aes-sbox-shallow`)

- The scalar-crypto S-box (aes64es/esm/ds/dsm/ks1i) computed
  the GF(2^8) inverse as x^254 — 8 chained variable GF(2^8)
  multiplies in a `while` loop: very deep, and rejected by
  Yosys (`Function gf_inv can only be called with constant
  arguments`). It is now a composite-field GF((2^4)^2)
  circuit (Satoh/Canright style, polynomial basis,
  GF(16) = GF(2)[w]/(w^4+w+1), z^2+z+0xA): forward and
  inverse share one tower inverter, with the AES<->tower
  isomorphism and the (inverse) affine transform folded into
  four 8x8 GF(2) matrices (λ and the isomorphism root chosen
  by exhaustive search for minimum matrix weight — unique
  minimum 110, next 112; reproduced and checked against the
  RTL by `scripts/gen_aes_tower.py --check`).
  `muserisc_bext` now has eight S-box lanes, each shared by
  SubBytes/InvSubBytes and also serving aes64ks1i (lanes
  0-3), instead of 16 (+4 ks1i) S-box instances. Still
  single-cycle, combinational.
- Why not a 256-entry table per direction: per lane, table
  pair 793 um2 / 8 levels / 0.52 ns vs tower 313 um2 / 17
  levels / 1.07 ns; at unit level the critical path differs
  by 0.04 ns (2.461 vs 2.497 ns, buffered) because
  MixColumns and the result mux share the path, while tables
  cost +3,800 um2 (+17%).
- Synthesis (Yosys 0.68 + OpenSTA from `openroad/orfs:latest`,
  Nangate45 typical, 10 ns virtual clock), full log with
  method and critical paths:
  [`bext-sbox-synth-2026-10-15.log`](bext-sbox-synth-2026-10-15.log).
  Baseline = original RTL with the while loop hand-unrolled
  (the original itself does not synthesize):

  | muserisc_bext | cells | area um2 | ltp levels | STA (buffered) | Yosys wall |
  |---|---|---|---|---|---|
  | original | — | — | — | Yosys error | — |
  | original, unrolled | 45,293 | 55,156 | 89 | 6.961 ns (87 cells) | 15:53 |
  | this change | 18,795 | 22,786 | 60 | 2.497 ns (32 cells) | 1:17 |

  The new ltp of 60 is the 64-bit ripple-carry `+` (Zba),
  not the AES path. Other loops in the unit (clmul, clz/ctz,
  cpop, MixColumns `gf_mul` by constants, SHA sigma) are
  constant-bound, synthesize, and are off the critical
  path — left alone.
- Unit TB ([`tb/cpp/bext_tb.cpp`](../../tb/cpp/bext_tb.cpp)):
  new exhaustive sweep of both S-boxes (all 256 inputs on
  all 8 lanes via aes64es/aes64ds, plus aes64ks1i lanes 0-3)
  against the literal FIPS-197 tables, which are themselves
  self-checked against the GF(2^8) inverse + affine
  definition; op loop extended to the unassigned encodings
  59-63 (must return 0). **60,866 checks PASS**; a single
  flipped matrix bit fails 128/256 sweep inputs (mutation
  check). Coverage of `muserisc_bext.sv` from the unit TB:
  **line 100% (70/70), toggle 100% (974/974)**. Verilator
  does not instrument inlined package-function bodies, so
  the S-box internals are covered by the exhaustive sweep
  rather than line counts. Two fixes made these numbers
  real: the TB wrote coverage *after* `delete dut` (reading
  freed counters — origin/main's TB reported garbage counts
  such as 2,444,302,752 hits on one line; fixed, the old RTL
  measures 98.6% line / 92.8% toggle), and `a32z` became a
  block-local variable (its constant-zero upper half was 64
  untoggleable points). `fpu_tb.cpp` and `rvc_tb.cpp` have
  the same write-after-delete pattern (out of scope here).
- Gates: `make lint` clean (17 s); `make test`
  `ALL PHASE-0 KATs PASS` (101 s); `make core-test` green —
  all unit TBs + 32 directed core binaries incl.
  `bext_directed` (AES-128 FIPS-197 KAT in the pipeline)
  (357 s cold / 152 s rebuild); `make riscv-tests` **123/123**
  (29 s).
- ACT on the core:
  [`act-core-bext-sbox-2026-10-15.csv`](act-core-bext-sbox-2026-10-15.csv)
  **92/92 PASS**, no waivers — Zba 8, Zbb 24, Zbc 3, Zbs 8,
  Zbkb 14, Zbkc 2, Zbkx 2, Zkne 4, Zknd 5, Zknh 8, Zicond 2,
  Zcb 7 + ZcbZba 1 + ZcbZbb 3 + ZcbZmmul 1: same test names
  and verdicts as `act-core-stage7-2026-10-14.csv`. Every
  test runs exactly +263 cycles vs that file, crypto and
  non-crypto alike. Confirmed not this RTL: the same ELFs on
  a `core_tb` built from origin/main give an identical CSV
  (review round 1); the cause is the vector-register prologue
  (`vsetvli` + `vmv.v.x v0..v31`) that ACT emits since
  Zve*/Zvl* entered `sw/act4-core/muserisc-core.yaml` in
  stages 8c/9. ELFs:
  `EXTENSIONS=Zba,Zbb,Zbc,Zbs,Zbkb,Zbkc,Zbkx,Zicond,Zkne,Zknd,Zknh`
  then `EXTENSIONS=Zcb` via `scripts/build_act4_core.sh`
  (17 s + cached), then `sim/run_act_core.sh` (48 s).

## Linux S-external interrupt livelock fix (2026-10-15, #3)

- Symptom: the soc_tb boot (OpenSBI v1.9 + Linux 6.6) reached
  `/init`'s `uname` line and then took S-external interrupts
  back to back until the 1e9-cycle limit
  ([`vecserial-linux-smoke-2026-10-15.log`](vecserial-linux-smoke-2026-10-15.log)
  on branch `vec-serial`).
- Root cause (core, not PLIC/UART/misa.V): CSRRS/CSRRC
  computed the new `mip` value from the read value, which ORs
  the `irq_s_ext_i` pin into SEIP (and `irq_s_timer_i` into
  STIP). OpenSBI does `csr_set/csr_clear(mip, MIP_STIP)` on
  every timer event; if the PLIC S-context line was high at
  that moment, the pin value was written into the software
  SEIP bit. With the UART interrupt-driven tty active after
  `/init` starts, this stuck `mip.SEIP` at 1: every PLIC
  claim returned 0 and Linux re-entered the handler forever.
  The privileged spec requires the RMW to use only the
  software SEIP bit.
- Fix: `muserisc_csr` exports `rmw_rdata_o` (= `rdata_o`
  except `mip` SEIP/STIP are the software bits) and the core
  uses it for CSRRS(I)/CSRRC(I). The rd value still reads
  pin | software bit.
- Regression: `sw/core-tests/irq_seip_rmw.S` in
  `make core-test`, using a new `core_tb` IRQ_CTL store
  (0x10000008) that drives the interrupt pins. It fails
  subtest 4 (SEIP latched after the pin drops) on the old
  RTL and passes with the fix. `irq_mip_rmw_variants.S` (from
  review) adds CSRRSI/CSRRCI and CSRRW on `mip` with the pins
  high and the `sip` alias from S-mode; `csr_tb` checks
  `rmw_rdata_o` directly.
- Gates: `make lint` clean (7 s); `make test`
  `ALL PHASE-0 KATs PASS` (35 s); `make core-test` all PASS (re-run after review: CSR TB 214 checks incl. `rmw_rdata_o`, 24 directed binaries incl. `irq_mip_rmw_variants`, 119 s; riscv-tests 123/123, 30 s); first run:
  23 directed binaries (244 s); `make riscv-tests`
  **123/123** (59 s); full ACT regenerated in this worktree
  (2,578 ELFs; same set as vec-serial)
  [`act-core-irqfix-2026-10-15.csv`](act-core-irqfix-2026-10-15.csv)
  **2,577/2,578**, the single `PMPSm_cfg_A_tor_zero-00` PA0
  waiver, verdicts identical to
  `act-core-vecserial-2026-10-15.csv` (869 s, 24 jobs).
- Linux: the same Image/fw_jump/dtb that livelocked reach
  `SOC TB PASS` at 508,685,709 cycles (`/proc/version` and
  `MUSERISC_LINUX_BOOT_OK` printed; 1,648 s wall) on
  vec-serial RTL + this fix, -O3 non-coverage soc_tb
  ([`irqfix-linux-boot-2026-10-15.log`](irqfix-linux-boot-2026-10-15.log)).
  The vector unit is idle for the whole boot. The same boot
  on this branch's own RTL was still running when this was
  written; its result will be posted on the PR.

## Element-serial vector unit + banked VRF (2026-10-15, #32)

- Change: `muserisc_vec.sv` rewritten from whole-group
  combinational evaluation to a 4-stage element-serial
  engine over a 64-bit datapath (iterative multiplier and
  divider, one shared `fp_eval`/`fp_estimate` call);
  `muserisc_vregfile.sv` from a 32x512 flop array with three
  4096-bit group read ports to three 1R1W 256x64 byte-write
  RAM replicas with synchronous read (SRAM/BRAM-mappable);
  the MEM vector load/store sequencer in `muserisc_core.sv`
  reads/writes VRF elements directly (no 4096-bit EX/MEM,
  MEM/WB or capture registers, no address multiplier). See
  [`docs/CORE.md`](../CORE.md) "Vector unit" for the design,
  the stall/trap/interrupt contract, and per-op cycle counts.
- Behavior changes (all spec-conformant): every completed
  vector instruction now resets `vstart` to 0 (previously
  only vset did); `vslidedown` offsets near 2^64 no longer
  wrap; segment loads never leave a partially written
  segment on a fault; a CSR access or vset right behind a
  vector load/store observes its `vstart`/`vl` update.
  Round-1 review fixes (pre-existing deviations on `main`):
  fault-only-first now traps only on an element-0 fault
  (trims `vl` for any later element, even with element 0
  masked off); `vmv<nr>r.v` and whole-register loads/stores
  now honor `vstart`.
- Unit TB (`tb/cpp/vec_tb.cpp` on
  `tb/sv/muserisc_vec_harness.sv` = unit + VRF): randomized
  against an independent C++ RVV golden model over all 88
  integer VOP classes x SEW x LMUL (1/8..8) x vl x vstart x
  v0 masking x vta/vma x vxrm, with whole-VRF before/after
  comparison and every allowed source/destination overlap;
  plus host-IEEE FP directed checks, a kill-mid-op check
  and cycle probes. `make core-test` default: **VEC TB PASS
  (61,672 checks, 22,880 random trials, seed 0x5eed8a)**; 300-per-op runs at seeds 0x5eed8a and 0xc0ffee passed (26,400 trials each); an earlier 600-per-op soak
  passed 52,800 trials (141,362 checks).
- Coverage (merged `make core-test`, Verilator line+toggle):
  `muserisc_vec.sv` every line hit and every toggle point
  hit except some bits of `fl_q` (flags of intermediate
  widening FP conversions, which are exact so OF/UF/DZ/NX
  can never be raised — structurally unreachable);
  `muserisc_vregfile.sv` 100% (no never-hit point).
- New directed test `sw/core-tests/vec_trap_directed.S`
  (in `make core-test`, `--irq-timer-after 2000`): M-timer
  interrupt during a long `vmacc` taken at the next
  instruction boundary with no replay; misaligned indexed
  load partial commit + `vstart`; PMP-faulting segment load
  with no partial segment, then handler-assisted resume from
  `vstart`; fault-only-first segment `vl` trim observed by a
  back-to-back `csrr vl` and `vsetvli x0,x0`; `vstart>0`
  arithmetic; strided store fault; FOF with element 0 masked
  off (trim, no trap); `vstart>0` on `vl1re32.v`, `vs1r.v`
  and `vmv1r.v`.
- Gates (all on the final RTL; wall-clock in parentheses):
  `make lint` clean (1 s); `make test` `ALL PHASE-0 KATs PASS`
  (22 s); `make core-test` all PASS (78 s);
  `make riscv-tests`
  [`riscv-tests-core-vecserial-2026-10-15.csv`](riscv-tests-core-vecserial-2026-10-15.csv)
  **123/123** (29 s).
- ACT, full core set regenerated in this worktree (I/M,
  priv, A/F/D/B/K/Zicond, C, Vx8-64, Vls8-64, Vf32/Vf64;
  2,578 ELFs, same 43 vector tests not generated as in
  stage 8): [`act-core-vecserial-2026-10-15.csv`](act-core-vecserial-2026-10-15.csv)
  **2,577/2,578** — Vx/Vls **1,872/1,872**, Vf32/Vf64
  **162/162**, scalar+priv **543/544** with the same single
  `PMPSm_cfg_A_tor_zero-00` PA0 waiver. The pre-rework RTL
  (origin/main) on the same ELFs gives the identical
  verdicts. Wall: 82 s on 32 parallel jobs with
  `sim/run_act_core_par.sh` (same per-ELF verdict as
  `sim/run_act_core.sh`; one result file per ELF, row count
  and uniqueness checked) vs 565 s on 24 jobs for the old RTL
  (the narrow datapath Verilates and simulates much faster).
  Simulated cycles: vector suites 2.4-5.9x the old
  single-cycle-per-instruction unit (element-serial by
  design), scalar suites +5% (ACT prologue vector init).
- Synthesis (`scripts/synth_vec.sh`; Yosys + OpenSTA from
  `openroad/orfs:latest`, Nangate45 typical, Kogge-Stone
  carry networks, ORFS `abc_speed` with buffering/sizing at
  10 ns, no wire load; `fp_eval`/`fp_estimate` black-boxed by
  `flow/vec-synth/fpu_stub_pkg.sv` in both designs, VRF RAM
  replicas black-boxed as SRAM macros; sv2v v0.0.13, now pinned in the script):

  | Block | Before (origin/main) | After (vec-serial) |
  |---|---|---|
  | `muserisc_vec` std-cell area | Yosys could not finish elaboration (killed by a host-memory guard at 141 GiB after ~4 h) | **52,735 um^2** (42,324 cells, 1,371 flops) |
  | `muserisc_vec` logic depth / STA | n/a (512-way unrolled element loops: 22 `*`/`/`/`%` and 15 `fp_eval`/`fp_estimate` sites per element) | **76** generic gates (ltp); worst path **3.29 ns** (inputs at 0 delay) at Nangate45 typical |
  | `muserisc_vregfile` | **603,640 um^2** (16,384 flops + 3x4096-bit group muxes), depth 18 | **5,254 um^2** logic (731 flops: v0 shadow + bypass) + 3x 256x64 1R1W SRAM (black-boxed; fakeram45_512x64 is 17,302 um^2 as an upper bound each), depth 6 |
  | Multipliers / dividers / `fp_eval` calls | per element (up to 512 lanes unrolled) | 1x 64x16 multiplier, 0 dividers (iterative), 1 `fp_eval` + 1 `fp_estimate` |

  Log: [`vec-serial-synth-2026-10-15.log`](vec-serial-synth-2026-10-15.log).
  The FP datapath is excluded on both sides (stub); its
  timing belongs to the multi-cycle FPU rework, which this
  unit will call per element. FPGA (Vivado, VU47P) numbers
  are not claimed (milestone F0 of #32).
- Linux: soc_tb boot of a freshly built OpenSBI v1.9 + Linux 6.6
  reaches `/init`'s `uname` line, then livelocks in
  S-external (PLIC/UART) interrupts until the 1e9-cycle limit
  ([`vecserial-linux-smoke-2026-10-15.log`](vecserial-linux-smoke-2026-10-15.log),
  7,163 s wall). An instrumented run shows **zero**
  vector-unit starts and zero vector load/store cycles
  through 550M cycles, so the reworked logic never activates
  and the scalar pipeline is unchanged; the trap trace is
  cycle-identical to origin/main for the first 12M cycles.
  Linux had not been re-run since `misa.V` landed (stage 8).
  This is treated as pre-existing and is not fixed here; the
  same boot on origin/main RTL (its unused vector unit and
  VRF stubbed only for simulation speed, with the testbench
  aborting if any vector instruction reaches EX — none did)
  livelocks identically: all 37 PC/data-address samples
  taken every 5M cycles from 450M to 630M match this
  branch's run exactly. Pre-existing (#3), since fixed on
  `main` by PR #6. With that fix (`af31588`) cherry-picked
  onto this branch's 26a2480 head, the boot passes:
  `MUSERISC_LINUX_BOOT_OK`, `SOC TB PASS` at 508,685,709
  cycles (8,033 s wall).

## Synthesizable RTL SoC: core + fabric + crypto (2026-10-15, #4)

- `rtl/soc/muserisc_soc_top.sv` now integrates the
  in-house core with a synthesizable fabric, boot ROM
  (0x1000), CLINT, PLIC (32 sources, UART=10), 16550
  UART, and the crypto accelerator at `0x2000_0000`
  behind a scalar-MMIO→AXI4-Lite bridge; the core
  gains `dmem_stall_i` to park MEM during AXI
  transactions. RAM is external at the `mem_*` ports
  (simulation model here; ASIC SRAM wrapper / FPGA
  BRAM-DDR later). Full log:
  [`soc-rtl-4-2026-10-15.log`](soc-rtl-4-2026-10-15.log).
- On-core crypto proof (`make -C sim socrtl`,
  `sw/soc-tests/crypto_soc_test.c` on `soc_rtl_tb`):
  `SOC CRYPTO PASS` at 11,097,819 cycles — SHA-256,
  field-mul KAT, Jacobian 2·G, and secp256k1 ECDSA
  verify of the `sw/ec_ops.py` frozen vector, all
  field ops (incl. scalar inverse via custom
  modulus n) on the accelerator. Ed25519 verify is
  not yet ported and remains open on #4.
- Platform proof: OpenSBI v1.9 boots on the RTL SoC
  (ACLINT + uart8250 reported from the RTL devices)
  and enters the S-mode payload: `HELLO FROM S-MODE`,
  `SOC RTL TB PASS` at 5,978,097 cycles. This is
  not a Linux boot on the RTL SoC — Linux evidence
  remains the `soc_tb` C++ platform above; ASIC
  timing is #11, FPGA hardware is #32.

## Multi-cycle synthesizable FPU + EX stall protocol (2026-10-15, branch `fpu-multicycle`, #32)

- `rtl/core/muserisc_fpu.sv` is now a multi-cycle F/D unit
  (FSM over registered stages; div/sqrt radix-2 restoring
  recurrence at 2 steps/cycle; log-depth leading-zero
  normalisers; separate round stage; no data-dependent
  loops). The arithmetic lives in
  `rtl/core/muserisc_fpu_ops.svh`, `include`d by the module
  and by `muserisc_fpu_pkg.sv`, whose `fp_eval` chains the
  same functions combinationally for the (still
  combinational) vector FP path. Latencies and the generic
  EX-stage req/done/ack/kill handshake are in
  [`docs/CORE.md`](../CORE.md) ("EX-stage multi-cycle
  units"). All numbers below:
  [`fpu-multicycle-2026-10-15.log`](fpu-multicycle-2026-10-15.log).
- FPU unit TB vs SoftFloat: **476,563 checks** (random sweep
  of every op × both formats × 5 IEEE modes, round-to-odd
  and rm 6/7, special/boundary pools, NaN-boxing, FMA
  cancellation, exact div/sqrt, undefined op codes) with
  randomized ack delays (HOLD), operand scrambling while
  busy, back-to-back issue, 2,000 mid-op kills/request drops,
  40 resets in flight, and every op's latency checked.
  TestFloat (`scripts/testfloat_fpu_vectors.sh`,
  berkeley-testfloat-3 a9c849f1, level 1, seed 42, all 36
  F/D operations × 5 rounding modes): **64,648,560/64,648,560
  vectors PASS** (1,148 s on the final RTL).
- Coverage (merged `make core-test`): `muserisc_fpu.sv` line
  39/39, branch 22/22, toggle 3,682/3,698 (the 16 untoggled
  points are flag bits that are constant by construction);
  `muserisc_fpu_ops.svh` line 123/123, branch 156/156. Note:
  Verilator collects no line coverage inside *package*
  functions, so the pre-existing package-based FPU logic had
  been invisible to coverage since stage 9a; the module-local
  `include` fixes that. The FPU/BEXT/RVC TBs also wrote
  coverage after freeing the model (garbage counts); fixed.
- Directed: `fp_directed.S` tests 11–16 (dependent chains
  through multi-cycle ops, back-to-back issue, int/store/branch
  consumers, FP load-use into long ops, fflags ordering vs
  CSR accesses, dynamic rm sampled at issue),
  `fp_stall_directed.S` (older trap/vector-load fault kills an
  in-flight fdiv which replays cleanly, FP ops completing
  during a 64-element vector-load mem_stall, branch/jump
  shadows, precise ecall/illegal after long ops, FS dirtying,
  held-EX operand refresh) and `fp_irq_directed.S` (machine
  timer IRQ at 48 consecutive offsets across in-flight
  fdiv/fsqrt/FMA; results identical to an IRQ-free run).
  `fp_stall_directed.S` test 4 **fails on the previous core**
  (stale scalar operand of an instruction held by
  `vec_wb_stall` after its producer retired) and passes with
  the held-EX operand refresh.
- Gates (final, rebased onto origin/main ef9a0cb with #4
  element-serial vector unit, #6 and the upstream RTL SoC;
  round-1 audit fixes included): `make core-test` green
  (138 s; now
  also builds and runs the `FPU_DS_BITS = 1` configuration:
  `fpu-ds1` unit TB 476,563 checks with its 30/59-cycle
  div/sqrt latencies, and `core-ds1` running `fp_directed`,
  `fp_stall_directed`, `fpvec_directed` and 25 IRQ offsets),
  `make lint` clean,
  `make test` `ALL PHASE-0 KATs PASS`,
  [`riscv-tests-core-fpu-multicycle-2026-10-15.csv`](riscv-tests-core-fpu-multicycle-2026-10-15.csv)
  **123/123**,
  [`act-core-fpu-multicycle-2026-10-15.csv`](act-core-fpu-multicycle-2026-10-15.csv)
  **2,577/2,578**: the stage-7 scalar set 543/544 (only the
  known `PMPSm_cfg_A_tor_zero-00` PA0 waiver; F 84/84, D
  116/116) plus the stage-8/9 vector sets 2,034/2,034 (1,872
  Vx/Vls + 162 Vf32/Vf64), regenerated in this tree with the
  same 34 Sail-side generation failures and 9 deselected
  tests as before.
- RTL SoC (upstream #4 sync): `make -C sim socrtl`
  `SOC CRYPTO PASS` (11,097,819 cycles) and OpenSBI v1.9 +
  S-mode payload on `soc_rtl_tb` (`HELLO FROM S-MODE`,
  6,059,345 cycles); yosys `read_slang` elaborates
  `muserisc_soc_top` with `-I rtl/core` (the include path is
  added to the SoC lint line and to
  `flow/designs/nangate45/muserisc_soc/config.mk`).
  `ex_hold = vec_ex_stall || ex_mc_busy`; simulation asserts
  the FPU and the vector unit are never in flight together,
  and `fp_stall_directed.S` test 13 interleaves vector ops
  with fdiv.d/fsqrt.d in both directions.
- Verilator 5.020 (the CI version): `make lint`, the unit
  TBs, `make -C sim core` and the riscv-tests smoke subset
  pass with Ubuntu 24.04's Verilator 5.020 (Docker), and the
  GitHub checks on the PR are green.
- Core-level coverage (unit TBs excluded) of
  `muserisc_fpu.sv` is also line 39/39 / branch 22/22: the
  HOLD state (FP op completing during an older vector load's
  `mem_stall`) is reached by `fp_stall_directed.S` test 3.
- Linux smoke: before #6, the `soc_tb` boot on origin/main
  itself livelocked in S-external interrupts after `/init`
  (#3), so this branch was held to "identical to main": the
  M-level trap trace and UART output of no-coverage `soc_tb`
  builds of origin/main and this branch are cycle-identical
  over the first 30M boot cycles (710 trap events each). On
  the final head (with #6): **`MUSERISC_LINUX_BOOT_OK`, `SOC
  TB PASS` at 502,782,909 cycles** (41 min wall,
  no-coverage build):
  [`fpu-multicycle-linux-boot-2026-10-15.log`](fpu-multicycle-linux-boot-2026-10-15.log).
- Synthesis (`scripts/synth_fpu.sh`, sv2v v0.0.13 → Yosys →
  OpenROAD repair_design/repair_timing + OpenSTA, Nangate45
  typical, no wire parasitics, Yosys ripple-carry adders):
  **44,416 µm²** cell area (35,546 cells, 1,388 flops = 14%
  of area); register-to-register min period **5.34 ns
  (187 MHz)**, critical path = the 2-step div/sqrt recurrence.
  Inputs and outputs are unconstrained, so the issue-cycle
  paths (forwarded operands → `unpack`/`i2f_sum`, and the
  fast-op `a_i` → `result_o` path behind the core's
  forwarding mux) are not in this figure. With `FPU_DS_BITS = 1`
  (div/sqrt 30/59 cycles instead of 17/32; simulated by
  `fpu-ds1`/`core-ds1`): 43,325 µm², 3.73 ns (268 MHz). A Kogge-Stone carry mapping was attempted but ABC
  did not finish within an hour and was abandoned. Full-core
  synthesis was not run here; per the round-2 audit, Yosys
  `read_slang` elaborates the whole SoC, and through sv2v +
  Yosys the core passes `proc`/coarse synthesis once the sv2v
  sensitivity lists over `muserisc_mmu`'s TLB array are
  relaxed to `@(*)`.

## Multi-cycle M unit (2026-10-15, branch `muldiv-multicycle`)

- `muserisc_muldiv_mc` (2-cycle-pipelined 65×65 multiplier, radix-4
  clz-normalised divider) replaces the combinational M unit in EX on
  the generic multi-cycle protocol (`docs/CORE.md`, "M unit"). Unit
  evidence (TB, 100% line/toggle, Nangate45 block synthesis 49.8k →
  28.6k µm², 115.8 ns comb → 4.7 ns reg→reg):
  [`muldiv-mc-nangate45-2026-10-15.log`](muldiv-mc-nangate45-2026-10-15.log).
- Integration gates:
  [`muldiv-multicycle-2026-10-15.log`](muldiv-multicycle-2026-10-15.log)
  — lint, test, core-test (new `md_directed`, `md_irq_directed` at 72
  timer-IRQ offsets plus exception kills of in-flight divides),
  riscv-tests 123/123, ACT 2,577/2,578
  ([`act-core-muldiv-multicycle-2026-10-15.csv`](act-core-muldiv-multicycle-2026-10-15.csv),
  only the known `PMPSm_cfg_A_tor_zero-00` waiver; I,M regenerated
  here 64/64), Verilator 5.020, `socrtl` + OpenSBI on `soc_rtl_tb`,
  Yosys `read_slang` of the SoC, and the `soc_tb` Linux boot
  (`MUSERISC_LINUX_BOOT_OK` at 510,301,199 cycles:
  [`muldiv-multicycle-linux-boot-2026-10-15.log`](muldiv-multicycle-linux-boot-2026-10-15.log)).
- `core_tb` now clears its `--irq-timer-after` line only on an
  interrupt trap (mcause bit 63), not on any trap: a synchronous
  exception taken while the IRQ is pending used to drop it silently
  (found by `md_irq_directed` at offset 168).

## In-house core L1 caches + latency-tolerant memory ports (2026-10-15, #32/#11/#4)

- Scope: the core's combinational Harvard ports are replaced
  by request/response ports; `muserisc_cpu` adds a blocking
  8 KiB 2-way L1 I$, a blocking 16 KiB 4-way write-back +
  write-allocate L1 D$ (single-port sync-read SRAM arrays),
  and a 2:1 arbiter onto one valid/ready burst memory bus.
  FENCE.I cleans the D$ and invalidates the I$; the PTW,
  AMO/LR/SC and the element-serial vector load/store
  sequencer go through the D$; the DRAM-only PMA keeps
  ROM/CLINT/PLIC/UART uncached. Design, protocol and
  parameters: [`docs/CORE.md`](../CORE.md#memory-interface-and-l1-caches).
  All results below are on the branch rebased onto `main`
  2789d95 (element-serial vector unit, mip RMW fix #6,
  synthesizable SoC #4, multi-cycle FPU #5, multi-cycle M unit
  #14, ORFS memory guard #16); the SoC now
  instantiates `muserisc_cpu` behind the new
  `muserisc_soc_fabric`, and IF consumes fetch words only when
  the generic `ex_hold` is low.
- `make core-test` (255 s wall):
  [`l1cache-core-test-2026-10-15.log`](l1cache-core-test-2026-10-15.log).
  All 36 directed tests (30 existing + 6 new:
  `smc_fencei_directed`, `amo_cache_directed`,
  `mmio_bypass_directed` incl. vector stride-0 loads/stores to
  the side-effect device, `vm_sfence_cache_directed`,
  `fp_hold_cache_directed`: fdiv.d/fsqrt.d and full-width
  div/rem/divuw on the multi-cycle units followed by
  straight-line code on cold I$ lines, `ptw_drop_directed`:
  a trap while a fetch walk's PTE read is in flight must drop
  the stale walker response) pass twice — caches on with seeded
  random bus latency 1–6, inter-beat gaps 0–2 and 70 %
  `req_ready` backpressure, and caches off — including
  `fp_stall_directed`, `md_directed`, `md_kill_directed`, the
  48-offset `fp_irq_directed` and the 72-offset
  `md_irq_directed` timer-IRQ sweeps in both configurations;
  `core-ds1` (FPU_DS_BITS=1) and `core-mdcomb` (combinational M
  unit) builds with random latency. 108 `CORE TB PASS` lines,
  no failures. New unit TBs:
  `icache_tb` 30,000 checked fetches (2,167 FENCE.I
  invalidations, 1,770 with a request outstanding), and
  `dcache_tb` 141,535 checks (16,565 loads, 17,951 stores,
  1,484 cleans, 6,250 I/O accesses), each over 10–12 bus
  timing profiles incl. a cache-disabled phase; both verify
  against a golden memory and check the bus protocol (I/O
  as exact in-order single beats, line bursts only for
  cacheable lines, no lost write-back after CLEAN).
  Mutation checks during development (dirty bit not set for
  byte stores; refill kill on invalidate removed; I$
  invalidate tied off; D$ clean skipped) were each caught by
  the unit TBs or `smc_fencei_directed`; removing the stale
  walker-response drop fails `ptw_drop_directed` (random
  latency); reverting the arbiter offer-hold fires both the
  new `a_req_stable` SVA and the `MbusModel` every-cycle
  request-stability check (`MBUS PROTOCOL ERROR`, exit 4) in
  `vm_directed` at `--mem-ready 50`.
- Coverage (Verilator line+toggle+branch; `scripts/cov_report.py`):
  cache unit TBs alone: `muserisc_dcache` line 41/41,
  branch 58/58, toggle 99.55 %; `muserisc_icache` line
  26/26, branch 44/44, toggle 98.48 %; `muserisc_sram_sp`
  line 2/2, toggle 99.85 %. Line coverage is 100 % with the
  two unreachable FSM `default:` recovery arms excluded via
  `coverage_off`. The uncovered toggles are structurally
  constant: `bus_req_len_o[7:2]` (fixed burst length),
  I$ fetch address bits [1:0] (always 0 by protocol), one
  SRAM data bit. `muserisc_bus_arb` (exercised only through
  `muserisc_cpu`): line 5/5, branch 16/16. Merged over all
  runs, the new core memory-port logic is fully line- and
  branch-covered; the remaining uncovered core lines/branches
  are pre-existing (vector LS corner cases, AMO min/max
  32-bit arms, guest-fault causes).
- riscv-tests: **123/123** with caches + random latency
  ([`riscv-tests-core-l1cache-2026-10-15.csv`](riscv-tests-core-l1cache-2026-10-15.csv),
  `make riscv-tests`, 22 s) and **123/123** uncached
  ([`riscv-tests-core-l1cache-nocache-2026-10-15.csv`](riscv-tests-core-l1cache-nocache-2026-10-15.csv),
  25 s).
- ACT (all 2,578 generated self-checking ELFs: 544 scalar/
  priv + 1,872 Vx/Vls + 162 Vf, generated in this worktree
  with the recorded `EXTENSIONS` lists) via
  `sim/run_act_core_par.sh` (now takes `CORE_TB_ARGS`), 20
  jobs: **2,577/2,578** with caches + random latency (seed 3,
  [`act-core-l1cache-2026-10-15.csv`](act-core-l1cache-2026-10-15.csv),
  282 s) and **2,577/2,578** uncached
  ([`act-core-l1cache-nocache-2026-10-15.csv`](act-core-l1cache-nocache-2026-10-15.csv),
  330 s). The only failure is the known
  `PMPSm_cfg_A_tor_zero-00` PA-0 waiver, as on `main`
  ([`act-core-muldiv-multicycle-2026-10-15.csv`](act-core-muldiv-multicycle-2026-10-15.csv)).
- Stress (not a make target; `core_tb` directly, with the
  every-cycle request-stability check): all 123 riscv-tests
  ELFs and 23 `*_directed` binaries (`fp_irq_directed`/
  `md_irq_directed` excluded: their IRQ must land inside a
  specific window, swept separately in core-test) under 6 new
  seeds (201-206) x 5 bus profiles — latency 1–20 + gaps 0–5 +
  30 % ready; latency 1–3 + 50 % ready; fixed latency 8;
  latency 1–6 + gaps 0–2 + 50 % ready; latency 2–30 + gaps 0–6
  + 20 % ready — with a timer IRQ asserted at cycle 2000:
  **4,380 runs, 0 failures, 0 protocol errors** (1,451 s).
- GitHub-CI toolchain reproduction (Docker `ubuntu:24.04`, apt
  Verilator 5.020 + `gcc-riscv64-unknown-elf` 13, clean export
  of the branch): `make lint` clean; unit TBs (`alu muldiv
  muldiv_mc decoder regfile csr mmu fpu bext rvc vec icache
  dcache crypto`) all PASS and `make -C sim core` all PASS (72
  `CORE TB PASS` lines); `soc_rtl_tb`/`soc_tb` build; riscv-tests smoke
  26/26. Verilator 5.020's intermittent internal "destroy
  locked Thread Pool" abort at the end of a `--build -j 0`
  (seen on unchanged unit TBs and on `core_tb`) needed a make
  retry; it is a tool flake, not an RTL error.
- RTL SoC ([`l1cache-soc-rtl-2026-10-15.log`](l1cache-soc-rtl-2026-10-15.log)):
  `soc_rtl_tb` with RAM behind the memory bus — on-core crypto
  driver + secp256k1 ECDSA verify **SOC CRYPTO PASS** with
  caches + random latency (18,851,904 cycles; upstream
  combinational-RAM SoC 11,097,819) and uncached (34,486,744);
  OpenSBI + `s_hello` from the RTL boot ROM **HELLO** at bus
  latency 1 (11,317,000 cycles; upstream 5,978,097) and with
  random latency (11,362,632). Slang elaboration of
  `muserisc_soc_top` with the ORFS Yosys `read_slang` (same
  flags and 34-file list as `flow/designs/nangate45/
  muserisc_soc/config.mk`): **0 errors**, 20 warnings, all
  pre-existing ("asynchronous load value missing" in core/
  crypto), none in the cache/CPU/fabric files.
- Cycle cost (blocking caches, two cycles per hit, correctness
  first) vs the combinational-memory core on `main`: riscv-tests
  2.74x total cycles with caches + random latency (median
  3.09x; vs the `fpu-multicycle` riscv-tests CSV), 3.64x uncached at latency 1 (every access a bus round
  trip plus the registered response); ACT 1.55x / 1.71x (the
  element-serial vector unit already dominates the vector
  suites); SoC crypto firmware 1.70x.
- Linux 6.6 (`soc_tb`, same OpenSBI v1.9 / Image / DTB as
  `muldiv-multicycle-linux-boot-2026-10-15.log`, which reaches
  the marker at 510,301,199 cycles on `main`), after the
  audit-round-1 arbiter fix: with caches on,
  `MUSERISC_LINUX_BOOT_OK` / `SOC TB PASS` at bus latency 1 in
  **1,614,840,462 cycles** (3.16x, 6,004 s;
  [`l1cache-linux-boot-lat1-2026-10-16.log`](l1cache-linux-boot-lat1-2026-10-16.log)),
  with random latency 1–6 + gaps 0–2 + 70 % ready (seed 7) in
  **2,115,195,513 cycles** (7,725 s;
  [`l1cache-linux-boot-rand-seed7-2026-10-16.log`](l1cache-linux-boot-rand-seed7-2026-10-16.log)),
  and with 50 % `req_ready` backpressure (seed 23) in
  **2,186,201,121 cycles** (8,131 s;
  [`l1cache-linux-boot-rand-bp50-2026-10-16.log`](l1cache-linux-boot-rand-bp50-2026-10-16.log));
  the random-latency runs exercise the arbiter's offer-hold and
  the every-cycle bus stability check throughout the boot.
  Uncached (`--no-cache`) Linux: a run with a phase-spread sampler (`--sample-pc
  0:50024721`) **passes**: `MUSERISC_LINUX_BOOT_OK` at
  6,303,080,388 cycles (29,301 s wall), 3.9x the cached boot at
  latency 1 and somewhat above the audit's 4.5–6G projection
  ([log](l1cache-linux-boot-nocache-2026-10-16.log)). The uncached mode is a bring-up strap, also
  gated by the directed tests, riscv-tests, ACT and the RTL-SoC
  runs above.
  An earlier note in this PR claimed the uncached boot was stuck
  in the scheduler's PELT update; that was a sampling artefact
  (the `--sample-pc` periods, 20M and 100M cycles, are multiples
  of the 40,000-cycle timer tick, so every sample hit the same
  point of the tick handler; `soc_tb` now documents that the
  period must not be a tick multiple). The audit measured a
  constant 24,656-cycle tick cost (62 % of the period, every
  tick taken) and progress through initramfs unpack and the
  jitterentropy SHA-3 self-test. (Before the #6 mip fix reached
  `main`, seed 7 hit the #3 SEI livelock right after `/init`'s
  first line; the fix, not this branch, resolved it.)
- Synthesis check (Yosys 0.68 in `openroad/orfs:latest`, sv2v
  v0.0.13, Nangate45 typical, arrays black-boxed):
  [`synth-caches-nangate45-2026-10-15.log`](synth-caches-nangate45-2026-10-15.log).
  Logic area excluding SRAM arrays: I$ 2,928 um2 (1,508
  cells, 270 flops), D$ 13,796 um2 (7,086 cells, 1,299
  flops, 47 % sequential — valid/dirty bits, the 64 B
  write-back line buffer and the registered uncached
  response), arbiter 191 um2 (103 cells, 4 flops incl. the
  offer-hold selection). Arrays: I$
  2 x (512 x 64 b data + 64 x 44 b tag); D$ 4 x (512 x
  64 b data with byte write mask + 64 x 44 b tag).

### Follow-ups from the PR #15 round-2 audit (2026-10-16)

- N1: `muserisc_bus_arb` drives `req_wdata_o = 0` on I$ beats, so
  the whole request payload (wdata included) is stable on every
  offered beat; `a_req_stable` and `MbusModel::CheckStable()` now
  check wdata on read beats too (the error message prints wdata).
  Mutant check (ungated wdata, `--mem-ready 20`, 3 seeds x
  `vm_directed`/`smc_fencei_directed`): the SVA fires in 6/6 runs;
  with the SVA also removed, the C++ check aborts 6/6 (exit 4,
  e.g. `addr 0x80->0x80 inst 1->1 ... wdata 0x0->0x4511451145114511`).
  Arbiter synthesis (Yosys/Nangate45): 259 um2, 167 cells, 4
  flops (was 191 um2; the 64 AND gates are the gating).
- N3: `priv_directed` test 3 brackets an `mcycle` read between two
  `cycle` reads instead of bounding the skew by 8 cycles;
  `vec_trap_directed` test 1 accepts an IRQ taken at any loop
  instruction (at the `vmacc` itself only with vstart = 0; the
  exact-20 accumulation check is unchanged). Before: 8/24 failures
  in 4 seeds of uncached / 20 %-ready profiles (priv test 3 in
  7, vec_trap test 1 in 1). After: 20 seeds x 5 profiles
  (`--no-cache` lat 1-4 / 20 %, `--no-cache` lat 2-30 gap 6 /
  20 %, cached lat 2-30 gap 6 / 20 %, default random, lat 1):
  all 100 `vec_trap` runs pass, and 80/100 `priv` runs; the 20
  others are all in the slowest profile (`--no-cache` lat 2-30
  gap 6 / 20 %) and are cycle-budget timeouts at 12M cycles, not
  failures: with a 60M budget they pass at 13.83M cycles (3/3
  seeds checked).
- Gates on `l1-followup` (main 910c023 + fixes), heavily loaded
  host: `make lint` clean (17 s); `make test` PASS (4 s);
  `make core-test` 108 `CORE TB PASS`, 0 fail (897 s);
  riscv-tests 123/123 (`make riscv-tests` 88 s; random latency
  91 s; uncached 91 s); ACT 2,577/2,578 with caches + random
  latency (only `PMPSm_cfg_A_tor_zero-00`, 550 s, 20 jobs);
  stress at seeds 301-303 x 6 profiles (adds `--no-cache` lat 1-4
  / 20 % ready to the five earlier ones): 2,628 runs, 0 failures,
  0 protocol errors (1,725 s); `soc_rtl_tb` crypto PASS cached +
  random latency (18,851,904 cycles) and uncached (34,486,744),
  OpenSBI `s_hello` HELLO at latency 1 (11,317,000) and random
  latency (11,362,632); Docker ubuntu:24.04 Verilator 5.020: lint
  clean, unit TBs incl. `icache`/`dcache` PASS, `make -C sim core`
  72 PASS lines, `soc_tb`/`soc_rtl_tb` build, riscv-tests smoke
  26/26.

## CSR vsetvl VLMAX and PLIC arbitration timing (2026-10-16, branch `timing-fixes`)

- Artifact: [`timing-csr-plic-2026-10-16.log`](timing-csr-plic-2026-10-16.log).
- Fixes the 2nd and 3rd worst paths of the first SoC synthesis
  (`docs/SOC_AREA.md` on `soc-sram-synth`): the CSR computed
  VLMAX as `512 / sew_bits` etc. (a 64-bit divider, 40.3 ns
  there) and now shifts (`group_bits >> (vsew + 3)`); the PLIC's
  31-step sequential claim scan (~460 levels) is now a 5-level
  tournament tree with the same lowest-id tie rule, still
  combinational, so a claim read returns the best source at the
  time of the read.
- Per-block synthesis with the SoC's ORFS Yosys flow
  (`scripts/synth_block_orfs.sh`, new; Nangate45, unrepaired,
  wire-load model): `muserisc_csr` **43.1 ns → 0.91 ns**,
  74,032 → 56,320 µm²; `muserisc_plic` **19.2 ns → 3.3 ns**
  (reg→reg; reg→`rdata_o` 19.1 → 3.2 ns), 37,288 → 32,860 µm².
- Gates on the rebased tree (main 910c023): lint, test,
  core-test (cached + uncached), vec TB at two seeds,
  riscv-tests 123/123 cached and uncached, ACT 2,577/2,578
  cached (random latency) and uncached (only the known
  `PMPSm_cfg_A_tor_zero-00` waiver; all 1,872 Vx/Vls + 162 Vf
  pass), `socrtl` and OpenSBI on `soc_rtl_tb`, Verilator 5.020
  and the `soc_tb` Linux boot (details in the log).

## Vector FP on the shared multi-cycle FPU (2026-10-16, branch `timing-vecfp`)

- Artifact: [`vecfp-shared-fpu-2026-10-16.log`](vecfp-shared-fpu-2026-10-16.log).
- Removes the worst path of the first SoC synthesis (128 ns,
  `docs/SOC_AREA.md` on `soc-sram-synth`): the vector unit no
  longer evaluates FP elements through one combinational
  `fp_eval`. Each FP sub-step is one operation on the core's
  scalar `muserisc_fpu`, which the vector unit drives while it is
  busy (the two only ever serve the instruction in EX); the
  `vfrec7`/`vfrsqrt7` estimate is split into two registered
  stages in the vector unit. Results are registered before use.
  Simulation asserts every sub-step result against
  `fp_eval`/`fp_estimate`.
- Shared rather than a second FPU instance: ~51k µm² saved for a
  2:1 port mux in the core and a few registers in the vector unit.
- Per-block synthesis (`scripts/synth_block_orfs.sh`, the SoC's
  ORFS Yosys flow, Nangate45, unrepaired): `muserisc_vec`
  **125.9 ns → 3.25 ns**, 148,418 → 59,283 µm²; vector unit +
  shared FPU + mux (`flow/vec-synth/muserisc_vec_fpu_synth.sv`)
  **4.16 ns**, 110,925 µm² vs 199,551 µm² for the old vec + FPU.
- Gates on the rebased tree (main 910c023): lint, test,
  core-test (cached + uncached), vec TB at two seeds,
  riscv-tests 123/123 cached and uncached, ACT 2,577/2,578
  cached (random latency) and uncached (only the known
  `PMPSm_cfg_A_tor_zero-00` waiver; all 1,872 Vx/Vls + 162 Vf
  pass; Vf cycles 1.02x), `socrtl` and OpenSBI on `soc_rtl_tb`,
  Verilator 5.020 and the `soc_tb` Linux boot (details in the
  log).

## PLIC spec claim/complete semantics, 3-bit priorities (2026-10-16, branch `plic-spec`, #21)

- Artifact: [`plic-spec-2026-10-16.log`](plic-spec-2026-10-16.log),
  Linux boot [`plic-spec-linux-boot-2026-10-16.log`](plic-spec-linux-boot-2026-10-16.log).
- RTL PLIC and the `soc_tb` C++ model now follow the RISC-V PLIC
  spec: a claim returns the best pending enabled source with
  priority > 0 regardless of the threshold (which gates only the
  EIP notification); a completion for a source not enabled for
  the context is ignored; priorities and thresholds are WARL with
  3 implemented bits. `plic_tb` checks each (the previous RTL
  fails it). `muserisc_plic` 32,860 → 4,940 µm², 3.32 → 1.76 ns.
- Gates: lint, test, core-test (incl. `plic_tb`, second seed),
  `socrtl`, OpenSBI on `soc_rtl_tb`, Verilator 5.020, and the
  `soc_tb` Linux boot (`MUSERISC_LINUX_BOOT_OK`, 1,612,954,759
  cycles).
