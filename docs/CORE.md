# In-house core (issue #18)

Clean-slate SystemVerilog RV64 core replacing the integrated
third-party CVA6+Ara. Target ISA: **RV64GCV** (the configuration the
CVA6+Ara evidence was gathered against), built and verified in stages.
Each stage lands only with its own C++ Verilator testbenches green and
coverage reported; ACT (riscv-arch-test) and Spike tandem runs — which
take far longer — are stage gates, not per-commit checks.

## Verification strategy

- **Per-module C++ Verilator testbenches** (`tb/cpp/`) with C++ golden
  models and randomized stimulus are the fast inner loop. Every new
  module ships with one; `sim/Makefile` builds with
  `--coverage-line --coverage-toggle` and reports merged coverage
  under `build/sim/coverage/`. Line coverage of `rtl/core/` from the
  committed tests is reported in evidence, never asserted by eye.
- **Directed self-checking assembly** (`sw/core-tests/`, riscv-tests
  style: nonzero exit = failing test number) runs on the core harness
  for end-to-end ISA semantics per stage.
- **Upstream suites as stage gates**: riscv-tests and ACT4 with a
  museRISC DUT config (reusing the flow proven on CVA6), Spike tandem
  once the core retires instructions observably.

## Stages

| Stage | Scope | Gate | Status |
|---|---|---|---|
| 1 | RV64I base integer, single-cycle, Harvard SRAM ports | unit TBs (ALU, decoder via directed asm), directed RV64I asm, coverage report | done |
| 2 | M extension + 5-stage pipeline (hazards, forwarding) behind the stage-1 module boundaries | directed M asm (incl. div/rem edges), stage-1 directed suite still green on the pipelined core | done |
| 3 | Privileged M/S/U, CSRs, traps/interrupts, Sv39+Svnapot MMU, PMP | riscv-tests `rv64ui/um` (needs CSR/trap state), ACT I/M + priv suites, Linux boot attempt | 3a+3b done (CSRs, traps/interrupts, PMP, MMU; upstream gates next) |
| 4 | A, F/D (IEEE-754, all rounding modes), Zba/Zbb/Zbc/Zbs, Zcb, Zicond, Zkn | ACT suites per extension, TestFloat vectors (flow exists) |
| 5 | C (Zca/Zcb/Zcd) — fetch realignment | ACT C suites, misaligned-fetch probes |
| 6 | V (RVV 1.0), VLEN 512, lane-parallel unit | ACT vector with the `sw/act4-cva6v` flow retargeted |

Single-cycle in stage 1 was deliberate: ISA semantics (decoder,
ALU, load/store datapath) got verified with zero hazard noise, and
stage 2 reused the same modules inside a classic 5-stage pipeline
— full forwarding to EX (EX/MEM and MEM/WB) plus a WB→ID bypass,
one load-use bubble, all control transfers resolved in EX
(predict not-taken, two flushed slots), and exceptions carried to
WB so a trapping instruction and everything younger perform no
writes. The M-unit divider is combinational in stage 2 (a
correctness vehicle; an iterative divider with an EX stall
replaces it before any synthesis target). Pipeline performance
beyond correctness is not yet a goal at this stage.

## Requirements carried from the CVA6+Ara characterization

These are measured third-party deviations the in-house core must not
repeat; each needs a directed test before the corresponding stage is
called done:

1. `vfirst.m`/`vpopc.m` examine only active elements (index < `vl`),
   and mask-result tails follow `vma` (`mu` = undisturbed). Ara
   violates both at small `vl`
   (`docs/evidence/act-vector-vfirst-probe-2026-10-13.log`).
2. LR/SC and AMO fault causes use the load-side cause class the
   privileged spec requires; CVA6 reports store-side causes for LR
   (waived in the merged evidence, issue #20).
3. PMP `pmpcfg` readback does not silently set bits the software
   cleared (CVA6 G=1 readback waiver, issue #20).
4. Misaligned scalar accesses: decide trap-vs-emulate before stage 3
   and test the declared behavior (stage 1 traps; Zicclsm is not
   claimed).

## Stage-1 interface contract

`muserisc_core` presents one instruction port and one data port,
both combinational-read (the TB SRAM responds in the same cycle):

- `imem_addr_o[63:0]`, `imem_rdata_i[31:0]`
- `dmem_addr_o[63:0]`, `dmem_wdata_o[63:0]`, `dmem_be_o[7:0]`
  (byte enables, nonzero = write), `dmem_re_o`, `dmem_rdata_i[63:0]`

Reset PC is `0x0000_0000`. Traps assert `trap_o` with
`trap_cause_o` (RISC-V mcause encoding) and freeze the PC; full trap
handling state arrives in stage 3. The core harness
(`tb/cpp/core_tb.cpp`) maps RAM at 0 and treats a store to
`0x1000_0000` as test exit (value 0 = pass, nonzero = failing test
number), matching the `sw/core-tests/` convention.
