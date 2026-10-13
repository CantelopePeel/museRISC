# Roadmap

## Phase 0 — Foundation (v0.1 baseline, 2026-10-12) ✅
- [x] Repo scaffold, spec, locked decisions (RV64GCV / dual-curve / sim+OpenROAD)
- [x] SHA-256 + SHA-512 block cores, Keccak-f1600, EC field unit + KATs
- [x] AXI-Lite `muse_crypto` top + SoC shell, Verilator lint clean
- [x] Ed25519 (RFC 8032) + secp256k1 (ECDSA) reference ops over field primitives
- [x] Toolchain up: riscv64-elf-gcc 16.2, Yosys, Sail 0.15, mise/UDB for ACT4
- [x] ACT4 harness validated: 51 RV64I tests pass on Sail (not hardware)
- [x] CVA6/Ara/arch-test fetched at pinned commits; Spike builds in Docker
- [~] OpenROAD: synth/place/CTS OK; detail route not clean (see B3)

## Baseline gates (next, in order)

Tracked as GitHub issues #1-#4 - see [docs/TASKS.md](TASKS.md).
- [x] **B1** CVA6 Verilator model built; `rv64ui-p-add` and
      `rv64ui-p-simple` report `*** SUCCESS ***`; evidence in
      `docs/evidence/b1-cva6-2026-10-12.log` (issue #1)
- [x] **B2** Full CVA6 `riscv-asm-tests` list with Spike as behavioral
      oracle — Spike solo + CVA6 solo 174/174, tandem lockstep 173/174
      (+1 waived config divergence, zero mismatches), ACT4 `I,M` 64/64
      on the model; evidence in `docs/evidence/` (issue #2, closed
      2026-10-12)
- [ ] **B3** OpenROAD `muse_crypto` clean at 28% util (40% run ended
      with 645 route violations): final metrics + GDS artifact
- [ ] **B4** SoC integration: crypto on CVA6 AXI @ 0x2000_0000,
      bare-metal driver, on-core signature-verify demo

## Phase 2 — Full G + hardened crypto
- [ ] ACT4 A/F/D green + TestFloat; riscv-dv random regression in CI
- [ ] Hardware scalar-mul sequencer (constant-time ladder), fault review
- [ ] SHA-512/Keccak streaming (DMA) into the accelerator top
- [ ] OpenROAD full-SoC closure (hierarchical, macro-hardened crypto)

## Phase 3 — Vector
- [ ] Integrate Ara (RVV 1.0), VLEN config, ACT4 vector tests green
- [ ] Vectorised SHA-256 chain benchmark vs scalar (Solana PoH-style)

## Phase 4 — MPW readiness
- [ ] Caravel wrapper (or equivalent harness), padring, DFT/scan decision
- [ ] DRC/LVS/antenna clean in target PDK, GDS review, shuttle checklist
- Realistic area check first: if RV64GCV+crypto exceeds the harness,
  ship the crypto macro + RV64GC host and keep vector as FPGA/ASIC-v2.

Effort honesty: Phases 2–4 are months of focused work with the
integrate-don't-rewrite strategy; a from-scratch RV64GCV would be
longer and is explicitly out of scope.
