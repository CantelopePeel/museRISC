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
