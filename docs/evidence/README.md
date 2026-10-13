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
- Caveat: this run used Spike defaults (`RV64IMAFDC_zicntr_zihpm`,
  `PMP Regions 0`), **not** a config matched to
  `cv64a6_imafdc_sv39`. It validates the ELFs and the oracle only;
  matched-config solo and `SPIKE_TANDEM` lockstep comparison are
  B2 tasks in issue #2.
