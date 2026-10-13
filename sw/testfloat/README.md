# TestFloat checkers for the CVA6 model

Bare-metal checkers that execute Berkeley TestFloat level-1 vectors
(generated against SoftFloat with the RISCV specialization) on the
CVA6 FPU (cvfpu) via the Verilator testharness, comparing result
bits (NaN-canonicalized: any NaN matches any NaN) and accrued
exception flags exactly. Each ELF halts via HTIF `tohost` like
`riscv-tests`: pass writes 1; a result mismatch at case `i` writes
`2*(i+2)+1`, a flags mismatch writes `2*(i+1000002)+1`, and any
trap writes 3.

Files:

- `link.ld` — checker linker script (DRAM at `0x80000000`).
- `../../scripts/testfloat_cva6.py` — vector text to checker
  assembly (operations: `f32/f64` add/sub/mul/div/sqrt/mulAdd,
  rounding RNE, tininess-after as generated).
- `../../scripts/build_testfloat.sh` — builds `testfloat_gen`
  if needed, generates vectors and ELFs, stages them under
  `third_party/cva6/testfloat-elfs/`.

Run with the batch runner, for example:

```sh
./scripts/build_testfloat.sh
TIME_OUT=20000000 TEST_TIMEOUT_SEC=420 ELF_SUBDIR=testfloat-elfs \
  TEST_LISTS=testfloat RUN_NAME=tf-all ./scripts/cva6_docker.sh regression
```

Scope v1: single/double add, sub, mul, div, sqrt, and fused
multiply-add at RNE. Conversions, comparisons, `roundToInt`, and
non-RNE rounding modes are follow-up work under issue #7. The
upstream `berkeley-softfloat-3`/`berkeley-testfloat-3` trees live
uncommitted under `third_party/` (recorded commits in evidence).
