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
