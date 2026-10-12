# museRISC

An open RISC-V crypto-accelerator SoC project: a Linux-capable **RV64GCV**
host with a hardware accelerator for the elliptic-curve and hashing
primitives used by Solana, Bitcoin, and Ethereum — built to be verified
with the official RISC-V compliance tests and hardened with OpenROAD.

> ## Baseline status — v0.1 (2026-10-12)
>
> **What is verified today is the crypto RTL, not the RISC-V core and
> not a chip.** The SHA-256, SHA-512, Keccak-f1600, and EC-field RTL in
> this repo passes known-answer tests (`make test`), Verilator lint
> (`make lint`), and Yosys synthesis. The reference curve operations
> reproduce the Ed25519 RFC 8032 signatures byte-for-byte and verify a
> secp256k1 ECDSA vector. The official ACT4 compliance harness runs and
> passes 51 RV64I tests **on the Sail reference model** — that proves
> the harness, not our hardware.
>
> **Not done yet:** no CVA6 simulation result on RISC-V tests, no
> RV64GCV compliance claim, no finished OpenROAD routing/GDS, no MPW
> readiness. See [What's left](#whats-left--the-baseline-plan) below.
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
| OpenROAD (partial) | Synthesis 52,933 cells, setup slack +5.3 ns @100 MHz (nangate45); routing not yet clean |

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

Solana mapping: Ed25519 signatures (SHA-512 + Curve25519 arithmetic) and
SHA-256 hashing (including Proof-of-History chains). Ethereum mapping:
secp256k1 ECDSA + Keccak-256. Bitcoin mapping: secp256k1 + SHA-256.

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
```

`third_party/` (CVA6, Ara, riscv-arch-test, Sail) is intentionally not
committed — `setup.sh` records the pinned commits and fetch commands.

## What's left — the baseline plan

In priority order; do not start later items until the earlier gate is
green and its log/report is committed under `docs/evidence/`.

1. **B1 — Host smoke.** Finish the CVA6 Verilator build (pinned
   Verilator v5.008; job count capped for 8 GB Docker RAM) and run
   `rv64ui-p-add` / `rv64ui-p-simple`. Pass = testharness PASSED logs.
2. **B2 — Host regression.** Run CVA6's full `riscv-asm-tests` list,
   then generate ACT4 `I,M` ELFs and run them on the CVA6 model with a
   museRISC DUT config. Only then update the compliance matrix.
3. **B3 — Macro closure.** Get a clean OpenROAD run for `muse_crypto`
   at 28% utilization (run at 40% ended with 645 routing violations):
   zero DRC violations, final timing/power metrics, GDS committed as a
   release artifact (not to git history if large).
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
rtl/crypto/   Novel verified RTL: sha256, sha512, keccak_f1600, ec_field, top
rtl/core/     Core integration glue (CVA6/Ara live in third_party/)
rtl/soc/      SoC top, AXI-Lite accelerator port
tb/           Testbenches + known-answer vectors
sw/           Register map header + golden/reference models
flow/         OpenROAD-flow-scripts designs (nangate45, sky130hd)
docs/         SPEC.md · ROADMAP.md · COMPLIANCE.md
scripts/      setup, CVA6 Docker build, ACT4 compliance, ORFS Docker
third_party/  (not committed) cva6, ara, riscv-arch-test, sail — pinned
```

## Licence

Original museRISC code and documentation are licensed under the
**GNU General Public License v3.0** — see [LICENSE](LICENSE). Integrated
cores keep their own licences (CVA6/Ara: Solderpad/Apache-2.0). Check
`third_party/` before any commercial tapeout. Phase-0 crypto is a functional reference, not
side-channel hardened — no production keys; see `docs/SPEC.md`.
