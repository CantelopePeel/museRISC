# Compliance matrix

"Compliant" here means: passes the named public test suite with a
stored report. Anything else is marked **not yet claimed**.
Last updated: 2026-10-12 (B2.0 config freeze + B2.1 Spike-solo baseline + B2.2 CVA6 solo directed regression complete).

| Block | Suite | Status |
|---|---|---|
| SHA-256 core | FIPS 180-4 "abc"/empty KATs (`tb/tb_sha256`) | PASS (`make test`) |
| SHA-512 core | FIPS 180-4 / hashlib KATs (`tb/tb_sha512`) | PASS (`make test`) |
| Keccak-f1600 | Golden model vs hashlib SHA3-256 (`tb/tb_keccak`) | PASS (`make test`) |
| EC field unit | Python mod-arith cross-check, edge cases | PASS (`make test`) |
| Ed25519 (ref model) | RFC 8032 TEST 1+2 sign/verify (`sw/ec_ops.py`) | PASS (algorithm only; HW sequencer pending) |
| secp256k1 (ref model) | `cryptography` ECDSA oracle vector | PASS (algorithm only) |
| ACT4 harness | riscv-arch-test ACT4, RV64I, DUT = Sail | 51/51 PASS on Sail — harness validation, **not** a hardware claim |
| CVA6 host smoke (B1) | riscv-tests `rv64ui-p-add`, `rv64ui-p-simple` on Verilator model | PASS — `*** SUCCESS *** (tohost = 0)`; see `docs/evidence/` (smoke only) |
| Spike solo (B2.1) | All 174 B2 directed-list ELFs on standalone tandem Spike, profile `matched` (config frozen in `docs/SPIKE_CONFIG.md`, B2.0) | 174/174 PASS exit 0 — validates ELFs + oracle only, **not** a CVA6 result; see `docs/evidence/` |
| Spike tandem (B2.3) | `SPIKE_TANDEM=1` RVFI lockstep vs CVA6 (`rvfi_compare`) | Not yet run |
| RV64I/M/A/C + priv subset on CVA6 (B2.2) | 174 riscv-tests (ui/um/ua/uc/si/mi, `-p-`+`-v-`) on Verilator model via batch runner | 174/174 PASS — `*** SUCCESS *** (tohost = 0)` each, 0 fail/timeout/mismatch; solo only, no lockstep compare (B2.3); see `docs/evidence/` |
| ACT4 I/M on CVA6 (B2.4) | riscv-arch-test ACT4 with CVA6 DUT config | Not yet run |
| RV64 A/F/D | ACT4 + TestFloat | Phase 2, not yet claimed |
| RVV 1.0 | ACT4 vector suite (fixed VLEN) | Phase 3, not yet claimed |
| Privileged/Sv39 | ACT4 privileged + Linux boot | Phase 2, not yet claimed |
| OpenROAD macro | ORFS nangate45, `muse_crypto` | Local run complete: detailed route 0 violations, antenna 0, setup/hold TNS 0 (setup WS +5.13 ns @ 10 ns), GDS written; 51 max-cap electrical violations remain — B3 not yet claimed |

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
