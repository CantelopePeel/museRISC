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
