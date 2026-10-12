# Compliance matrix

"Compliant" here means: passes the named public test suite with a
stored report. Anything else is marked **not yet claimed**.
Last updated: 2026-10-12 (v0.1 baseline).

| Block | Suite | Status |
|---|---|---|
| SHA-256 core | FIPS 180-4 "abc"/empty KATs (`tb/tb_sha256`) | PASS (`make test`) |
| SHA-512 core | FIPS 180-4 / hashlib KATs (`tb/tb_sha512`) | PASS (`make test`) |
| Keccak-f1600 | Golden model vs hashlib SHA3-256 (`tb/tb_keccak`) | PASS (`make test`) |
| EC field unit | Python mod-arith cross-check, edge cases | PASS (`make test`) |
| Ed25519 (ref model) | RFC 8032 TEST 1+2 sign/verify (`sw/ec_ops.py`) | PASS (algorithm only; HW sequencer pending) |
| secp256k1 (ref model) | `cryptography` ECDSA oracle vector | PASS (algorithm only) |
| ACT4 harness | riscv-arch-test ACT4, RV64I, DUT = Sail | 51/51 PASS on Sail — harness validation, **not** a hardware claim |
| RV64I/M/C on CVA6 | riscv-tests + ACT4 on Verilator model | Not yet claimed (model build in progress; B1/B2) |
| RV64 A/F/D | ACT4 + TestFloat | Phase 2, not yet claimed |
| RVV 1.0 | ACT4 vector suite (fixed VLEN) | Phase 3, not yet claimed |
| Privileged/Sv39 | ACT4 privileged + Linux boot | Phase 2, not yet claimed |
| OpenROAD macro | ORFS nangate45, `muse_crypto` | Synth/place/CTS OK (setup +5.3 ns @ 10 ns); route not clean yet (B3) |

Reproduce locally:

```sh
make test                 # crypto KATs (done today)
make lint                 # Verilator -Wall clean
make compliance           # ACT4 RV64I on Sail (harness only)
./scripts/cva6_docker.sh  # CVA6 model + ISA smoke tests (B1, long)
make openroad             # ORFS on muse_crypto (B3, long)
```

Pinned sources: CVA6 `81245a47`, Ara `34bd3bc1`,
riscv-arch-test `6af53584`, Sail 0.15. Notes: RISCOF is deprecated
upstream in favour of ACT4; Ubuntu Verilator 5.020 internal-faults on
CVA6 master (use its pinned v5.008); Docker builds here cap jobs at 2
(~8 GB RAM). Archive every future report under `docs/evidence/`.
