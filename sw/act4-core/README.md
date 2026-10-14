# ACT4 DUT config: museRISC in-house core

DUT configuration for running riscv-arch-test (ACT4) against
the in-house RV64 core in `rtl/core/` (issue #18 stage 3d).
The canonical copies live here; `scripts/build_act4_core.sh`
syncs them into `third_party/riscv-arch-test/config/cores/
muserisc-core/` before generating ELFs, and
`sim/run_act_core.sh` executes them on the core through
`tb/cpp/core_tb.cpp` (ELF/HTIF mode).

- `muserisc-core.yaml` — UDB configuration. Every value was
  read out of the RTL (citations inline). Declared scope:
  RV64IM + Zicsr/Zifencei/Zicntr, M/S/U, Sv39+Svbare+Svnapot+
  Svadu, PMP16, IALIGN=32.
- `sail.json` — Sail reference configuration, derived from
  `sw/act4-cva6/sail.json` with only these overrides:
  mcountinhibit/mcounteren/scounteren writable-bit masks
  (0x5 / 0x7 / 0x7), no writable HPM counters, hpmevent
  width 64, mtvec/stvec vectored base alignment 2²,
  medeleg delegatable bits 0xB35D, mstatus FS legal = Off,
  PMP {grain 0, count 16, usable 16, NA4 on}, platform
  vendorid 0 / archid 0x4D555345 / impid 0x30000,
  `wfi_is_nop` and `wfi_available_to_user_mode` true, and
  extensions flipped off (A, F, D, B, Zaamo, Zalrsc,
  Zicond, Zihpm, Zca/Zcb/Zcd, Zba/Zbb/Zbs/Zbc, Zbkb/Zbkc,
  Zknd/Zkne/Zknh, Svade) with Svadu flipped on. Everything
  else (memory regions, misaligned policy, platform) is
  inherited unchanged.
- `link.ld`, `rvmodel_macros.h` — copied from
  `sw/act4-cva6/` with header notes rewritten; the HTIF
  tohost halt convention is identical in this harness.

Generation (as run for the evidence in
`docs/evidence/act-core-impriv-2026-10-13.csv`):

1. `./scripts/build_act4_core.sh` (EXTENSIONS=I,M)
2. `EXTENSIONS=ExceptionsSv,ExceptionsSvSm,PMPS,PMPSm,PMPU,
   PMPF,Sv,SvPMP,SvSm,SvbareSm,SvaduPMP ./scripts/build_act4_core.sh`
   (plus Sv39,Svbare,Svnapot,Svadu for the Sv* suites)
3. `bash sim/run_act_core.sh <out.csv>`
