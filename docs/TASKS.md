# Task tracking

Canonical tracking is GitHub Issues, in order. Do not start a baseline
gate until the previous gate's evidence is committed under
`docs/evidence/` and its issue can be closed with a link to that evidence.

## Baseline gates ([milestone: Baseline B1-B4](https://github.com/bubblebabyboi/museRISC/milestone/1))

- [x] [#1](https://github.com/bubblebabyboi/museRISC/issues/1) **[B1] Host smoke** — CVA6 Verilator model passes `rv64ui-p-add` / `rv64ui-p-simple`; evidence in `docs/evidence/`
- [x] [#2](https://github.com/bubblebabyboi/museRISC/issues/2) **[B2] Host regression** — full `riscv-asm-tests` with Spike solo + `SPIKE_TANDEM` lockstep, then ACT4 `I,M` ELFs on the CVA6 model *(done 2026-10-12: Spike solo + CVA6 solo 174/174, tandem 173/174 + 1 waived divergence, ACT4 I/M 64/64; see `docs/evidence/b2-combined-matrix-2026-10-12.csv`)*
- [ ] [#3](https://github.com/bubblebabyboi/museRISC/issues/3) **[B3] OpenROAD closure** — clean route for `muse_crypto` (nangate45), final metrics + GDS *(next)*
- [ ] [#4](https://github.com/bubblebabyboi/museRISC/issues/4) **[B4] SoC integration** — `muse_crypto` on the CVA6 AXI fabric + driver + on-core signature verify *(blocked by #3 evidence flow; host confidence from #1/#2 in place)*

## Features ([milestone: v1 features](https://github.com/bubblebabyboi/museRISC/milestone/2))

- [ ] [#5](https://github.com/bubblebabyboi/museRISC/issues/5) Hardware scalar-multiply sequencer (constant-time) for Ed25519 + secp256k1
- [ ] [#6](https://github.com/bubblebabyboi/museRISC/issues/6) Streaming SHA-512 and Keccak/SHA3 into the accelerator top (sponge + DMA)
- [ ] [#7](https://github.com/bubblebabyboi/museRISC/issues/7) ACT4 A/F/D compliance + TestFloat for the FPU *(in progress on `isa-verify-sweep`: ACT A/F/D + TestFloat stored; privileged/Sv39 + Linux boot remain)*
- [ ] [#8](https://github.com/bubblebabyboi/museRISC/issues/8) riscv-dv random regression + GitHub Actions CI
- [ ] [#9](https://github.com/bubblebabyboi/museRISC/issues/9) Ara RVV 1.0 vector integration + ACT4 vector tests *(blocked by #2)*
- [ ] [#10](https://github.com/bubblebabyboi/museRISC/issues/10) Vectorised SHA-256 chain benchmark (Solana PoH-style) vs scalar + accelerator *(blocked by #4, #9)*
- [ ] [#11](https://github.com/bubblebabyboi/museRISC/issues/11) Full-SoC hierarchical OpenROAD closure (sky130hd) *(blocked by #3, #4)*
- [ ] [#12](https://github.com/bubblebabyboi/museRISC/issues/12) Security review: side-channel and fault hardening before any key handling
- [ ] [#13](https://github.com/bubblebabyboi/museRISC/issues/13) MPW readiness: Caravel harness decision, DRC/LVS, shuttle checklist *(blocked by #11)*
