<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/muserisc-logo-dark.svg">
    <img src="docs/assets/muserisc-logo.svg" alt="museRISC — RV64GCV crypto accelerator SoC" width="760">
  </picture>
</p>

<p align="center">
  <a href="https://github.com/bubblebabyboi/museRISC/actions/workflows/regression.yml"><img alt="RTL regression" src="https://github.com/bubblebabyboi/museRISC/actions/workflows/regression.yml/badge.svg"></a>
  <a href="https://github.com/bubblebabyboi/museRISC/actions/workflows/compliance.yml"><img alt="ACT4 compliance harness" src="https://github.com/bubblebabyboi/museRISC/actions/workflows/compliance.yml/badge.svg"></a>
  <a href="https://github.com/bubblebabyboi/museRISC/actions/workflows/hardware-regression.yml"><img alt="Hardware regression B1 and B3" src="https://github.com/bubblebabyboi/museRISC/actions/workflows/hardware-regression.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="Licence: GPLv3" src="https://img.shields.io/badge/licence-GPLv3-57D0B8"></a>
</p>

# museRISC

An open RISC-V crypto-accelerator SoC project: a Linux-capable **RV64GCV**
host with a hardware accelerator for the elliptic-curve and hashing
primitives used by Bitcoin, Ethereum, and other blockchain systems —
built to be verified with the official RISC-V compliance tests and
hardened with OpenROAD.

> ## Status — B1+B2 complete (2026-10-12)
>
> **The crypto RTL is KAT-verified and the stock CVA6 host model now
> passes the full B2 regression — this is still not an RV64GCV
> compliance claim and not a chip.** The SHA-256, SHA-512,
> Keccak-f1600, and EC-field RTL passes known-answer tests
> (`make test`), Verilator lint (`make lint`), and Yosys synthesis,
> and the reference curve operations reproduce the Ed25519 RFC 8032
> signatures byte-for-byte and verify a secp256k1 ECDSA vector. On
> the pinned CVA6 Verilator model, all 174 directed `riscv-tests`
> (`asm,amo,mul` lists) pass solo, tandem Spike lockstep agrees on
> 173/174 with zero mismatches (one explained Spike-config waiver),
> and ACT4 `I,M` passes 64/64 — see
> [Test & ISA coverage](#test--isa-coverage) and `docs/evidence/`.
>
> **Not done yet:** floating-point/vector/privileged compliance,
> finished OpenROAD closure (B3, next), SoC integration of the
> accelerator (B4), and MPW readiness. See
> [What's left](#whats-left--the-baseline-plan) below.
> A *fully compliant* RV64GCV core with vector and floating point is
> not a from-scratch deliverable; museRISC integrates the proven
> CVA6 (RV64GC) + Ara (RVV) cores and contributes novel verified RTL
> for the crypto accelerator and SoC.

## Verified in this baseline

| Item | Evidence (reproduce with) |
|---|---|
| SHA-256 block core | FIPS 180-4 "abc"/empty KATs — `make test` |
| SHA-512 block core | FIPS 180-4 / hashlib "abc"/empty KATs — `make test` |
| Keccak-f1600 | Golden model cross-checked vs `hashlib` SHA3-256 — `make test` |
| EC field add/sub/mul-mod | secp256k1 + Curve25519 edge vectors — `make test` |
| Ed25519 sign/verify (ref) | RFC 8032 TEST 1+2 exact signatures — `python3 sw/ec_ops.py` |
| secp256k1 ECDSA verify (ref) | `cryptography`-generated oracle vector — `python3 sw/ec_ops.py` |
| RTL lint / synthesis | Verilator `-Wall` clean; Yosys synth clean — `make lint` |
| ACT4 harness | 51 RV64I tests pass **on Sail** — `make compliance` |
| CVA6 host smoke (B1) | `rv64ui-p-add`, `rv64ui-p-simple`: `*** SUCCESS ***` — `docs/evidence/` |
| Spike solo baseline (B2.1) | All 174 directed-list ELFs pass on standalone Spike (`matched` config) — `scripts/spike_solo.sh` |
| CVA6 solo regression (B2.2) | All 174 `asm,amo,mul` tests pass on the CVA6 model — `scripts/cva6_docker.sh` |
| Spike tandem lockstep (B2.3) | 173/174 pass with 0 mismatches (+1 waived Spike-config divergence) — `docs/evidence/` |
| ACT4 I/M on CVA6 (B2.4) | 64/64 self-checking ACT ELFs (51 I + 13 M) pass on the model — `scripts/build_act4_cva6.sh` |
| OpenROAD (partial, B3 next) | Detailed route 0 violations, timing met, GDS written (nangate45); 51 max-cap electrical violations remain |

## Test & ISA coverage

"Covered" means a green report is stored under `docs/evidence/` (see
[docs/COMPLIANCE.md](docs/COMPLIANCE.md) for the full matrix and
scope limits). Anything unchecked is planned work, not a claim.

### Tests

- [x] Crypto RTL known-answer tests (SHA-256/512, Keccak, EC field) — `make test`
- [x] Ed25519 / secp256k1 reference-model vectors — `python3 sw/ec_ops.py`
- [x] Verilator lint + Yosys synthesis (CI on every push) — `make lint`
- [x] ACT4 harness validation on Sail, 51 RV64I tests (harness only) — `make compliance`
- [x] `riscv-tests` directed lists `asm,amo,mul` — 174 tests on Spike solo, CVA6 solo, and tandem lockstep
- [x] ACT4 `I,M` self-checking ELFs on the CVA6 model — 64 tests (51 I + 13 M)
- [x] Directed FP lists (46) + ACT4 `A,F,D` on the model (220/222, 2 waived `Zalrsc-sc` harness hangs) — sweep branch, see `docs/evidence/`
- [ ] Berkeley TestFloat against the FPU configuration (#7)
- [ ] `riscv-tests` floating-point lists and privileged ACT suites (#7)
- [ ] Random instruction regression with riscv-dv in CI (#8)
- [ ] ACT4 vector suite (#9)
- [ ] Linux boot on the model
- [ ] On-core crypto driver / end-to-end signature verify (B4, #4)
- [ ] OpenROAD signoff run with final metrics + GDS (B3, #3)

### ISA (target: RV64GCV)

The integrated host today is stock CVA6 `cv64a6_imafdc_sv39`
(RV64GC-class scalar core; Ara vector unit not yet integrated, and
the custom crypto accelerator not yet attached to it).

- [x] **RV64I** base integer — directed `rv64ui` + ACT `I`
- [x] **M** multiply/divide — directed `rv64um` + ACT `M`
- [x] **A** atomics — directed `rv64ua` lists (ACT `A` still to run, #7)
- [x] **Zicsr / Zifencei** basics — via directed `rv64mi`/`rv64si` and `fence.i` tests
- [x] **F / D** floating point — directed (46/46 solo+Spike, tandem F 22/22) + ACT F/D 200/200; TestFloat still pending (#7)
- [ ] **C** compressed (+ Zca/Zcb/Zcd) — only the `rv64uc-p-rvc` smoke so far
- [ ] **V** vector (RVV 1.0) — Ara integration pending (#9)
- [ ] **Privileged M/S/U + Sv39** — exercised by directed priv and virtual-memory (`-v-`) tests; privileged ACT suite and Linux boot pending
- [ ] **B** bitmanip (Zba/Zbb/Zbc/Zbs), **Zicond**, scalar crypto (Zbkb/Zbkc/Zkn) — implemented in the host config, no directed tests yet

## Locked decisions (2026-10-12)

| Decision | Choice |
|---|---|
| ISA target | **RV64GCV** — RV64I + M/A/F/D/C + Vector 1.0 (phased, see roadmap) |
| Host core strategy | Integrate **CVA6** (RV64GC) + **Ara** (RVV); do not rewrite them |
| Crypto scope | **Both curves + Keccak**: Ed25519/Curve25519 + secp256k1, SHA-256/512, SHA3/Keccak-256 |
| Tapeout (v1) | **Simulation + OpenROAD only**; Caravel/MPW harness is a later phase |
| PDK (v1 flow) | Nangate45 (default ORFS) + Sky130HD configs for the crypto macro |

Why not from-scratch RV64GCV? Vector alone (RVV 1.0) is larger than a
base core, F/D needs IEEE-754 verification (TestFloat), and "fully
compliant" means passing `riscv-arch-test` + random testing. Integrating
CVA6+Ara is the credible route to a real MPW chip; our engineering
effort goes into the accelerator, SoC, drivers, and physical closure.

## Architecture

```
            ┌─────────────────────────────────────────────┐
            │  CVA6  RV64GC (6-stage, MMU, AXI)           │
            │    + Ara RVV 1.0 vector co-processor        │
            └──────────────────┬──────────────────────────┘
                               │ AXI4 / AXI-Lite
        ┌──────────────────────┼───────────────────────┐
        │                      │                       │
   ┌────▼─────┐          ┌─────▼────────┐        ┌─────▼─────┐
   │ SRAM /   │          │ muse_crypto  │        │ UART/SPI/ │
   │ DRAM ctl │          │ accelerator  │        │ GPIO/TRNG │
   └──────────┘          │ ─ SHA-256 ✓  │        └───────────┘
                         │ ─ SHA-512 ✓  │  ✓ RTL+KAT in this repo
                         │ ─ Keccak ✓   │  ◌ algorithm verified in ref
                         │ ─ EC field ✓ │    model; HW sequencer next
                         │ ─ Ed25519 ◌  │
                         │ ─ secp256k1 ◌│
                         └──────────────┘
```

Ed25519 signatures use SHA-512 with Curve25519 arithmetic. Ethereum
mapping: secp256k1 ECDSA + Keccak-256. Bitcoin mapping: secp256k1 + SHA-256.

## Quick start

Host tools used for this baseline: Verilator, Icarus Verilog, Yosys,
`riscv64-elf-gcc`, Python 3, Docker. OpenROAD and the CVA6 build run
in Docker (the CVA6 flow is Linux-only).

```sh
git clone https://github.com/bubblebabyboi/museRISC.git && cd museRISC
./scripts/setup.sh   # tool check + fetch pinned third-party sources
make test            # crypto KATs: RTL + Python golden models
make lint            # Verilator lint on all RTL
make compliance      # ACT4 RV64I harness validation on Sail
make openroad        # Docker ORFS run on muse_crypto (long; Linux/CI best)
./scripts/cva6_docker.sh  # CVA6 Verilator build + ISA-test smoke (long)
TEST_LISTS=asm,amo,mul RUN_NAME=solo-full ./scripts/cva6_docker.sh regression  # B2 solo regression (long)
./scripts/build_act4_cva6.sh  # Generate ACT4 I,M ELFs for the CVA6 model (B2.4)
```

`third_party/` (CVA6, Ara, riscv-arch-test, Sail) is intentionally not
committed — `setup.sh` records the pinned commits and fetch commands.

## Automated regression on GitHub

Every push and pull request runs the fast RTL gate. Heavier compliance
and hardware flows run weekly or on demand from the repository's
**Actions** tab because they take much longer and build large tools.

| Workflow | When | What it proves |
|---|---|---|
| RTL regression | Every push/PR + daily | Crypto KATs, Verilator lint, Yosys synthesis, script/SVG checks |
| ACT4 compliance harness | Weekly + manual | ACT4 RV64 tests generated and run on Sail — harness only, not hardware |
| Hardware regression (B1/B3) | Weekly + manual | B1 CVA6 `rv64ui` smoke tests and/or B3 OpenROAD route, with uploaded logs |

Run a heavy gate manually with the GitHub CLI:

```sh
gh workflow run "Hardware regression (B1/B3)" -f target=b1
gh workflow run "Hardware regression (B1/B3)" -f target=openroad
gh workflow run "ACT4 compliance harness" -f extensions=I
gh run watch
```

The workflows upload logs and summaries as Actions artifacts. A green
ACT4 badge does **not** make the core compliant; hardware claims rest
only on the B1/B2 evidence committed under `docs/evidence/`.

## What's left — the baseline plan

In priority order; do not start later items until the earlier gate is
green and its log/report is committed under `docs/evidence/`.

1. **B1 — Host smoke. ✅ Done.** The CVA6 Verilator model passes
   `rv64ui-p-add` / `rv64ui-p-simple` with
   `*** SUCCESS *** (tohost = 0)`; evidence is in `docs/evidence/`.
2. **B2 — Host regression. ✅ Done (2026-10-12).** All 174 directed
   `asm,amo,mul` tests pass on Spike solo and CVA6 solo; tandem
   lockstep agrees on 173/174 with zero mismatches (one waived
   Spike-config divergence); ACT4 `I,M` passes 64/64 on the model.
   Combined matrix: `docs/evidence/b2-combined-matrix-2026-10-12.csv`.
3. **B3 — Macro closure (next).** Finish the OpenROAD run for
   `muse_crypto`: the local flow already reaches a clean detailed
   route with timing met and GDS written, with 51 max-cap electrical
   violations left to clear, then publish final timing/power metrics
   and the GDS as a release artifact (not to git history if large).
4. **B4 — SoC integration.** Put `muse_crypto` behind the CVA6 AXI
   crossbar at `0x2000_0000`, write the bare-metal driver, and run an
   end-to-end Ed25519/secp256k1 verify on the simulated core.
5. **Then:** hardware scalar-multiply sequencer (constant-time),
   SHA-512/Keccak streaming into the accelerator top, ACT4 `A,F,D`
   + TestFloat, Ara vector integration (RVV), full-SoC OpenROAD
   closure, and only then a Caravel/MPW decision.

Full detail: [docs/ROADMAP.md](docs/ROADMAP.md) ·
[docs/SPEC.md](docs/SPEC.md) · [docs/COMPLIANCE.md](docs/COMPLIANCE.md)

## Repo layout

```
.github/      GitHub Actions: RTL, ACT4 and heavy hardware regression
rtl/crypto/   Novel verified RTL: sha256, sha512, keccak_f1600, ec_field, top
rtl/core/     Core integration glue (CVA6/Ara live in third_party/)
rtl/soc/      SoC top, AXI-Lite accelerator port
tb/           Testbenches + known-answer vectors
sw/           Register map header + golden/reference models + ACT4 DUT config (act4-cva6/)
flow/         OpenROAD-flow-scripts designs (nangate45, sky130hd)
docs/         SPEC.md · ROADMAP.md · COMPLIANCE.md · SPIKE_CONFIG.md · TASKS.md · evidence/ · assets/
scripts/      setup, CVA6 Docker regression, Spike solo, ACT4 build/compliance, ORFS Docker
third_party/  (not committed) cva6, ara, riscv-arch-test, sail — pinned
```

## Licence

Original museRISC code and documentation are licensed under the
**GNU General Public License v3.0** — see [LICENSE](LICENSE). Integrated
cores keep their own licences (CVA6/Ara: Solderpad/Apache-2.0). Check
`third_party/` before any commercial tapeout. Phase-0 crypto is a
functional reference, not side-channel hardened — no production keys;
see `docs/SPEC.md`.

The museRISC logo is an original project mark, not an official Muse or
RISC-V logo. “RISC-V” is used descriptively for the instruction-set target.
