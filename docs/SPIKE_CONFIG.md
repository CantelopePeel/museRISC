# Spike configuration for `cv64a6_imafdc_sv39` (B2.0 draft)

This document records what the Spike behavioral oracle is configured
to represent during B2. It is a **draft freeze**: fields marked
*unresolved* must be settled or explicitly waived before B2.3 tandem
results count as evidence. Sail/ACT4 remains the normative
compliance reference; Spike is a second behavioral opinion.

Sources (pinned CVA6 checkout `81245a47`):
`core/include/cv64a6_imafdc_sv39_config_pkg.sv`,
`corev_apu/tb/ariane_soc_pkg.sv`, `corev_apu/tb/common/spike.sv`,
`verif/core-v-verif/lib/uvm_agents/uvma_core_cntrl/uvma_core_cntrl_utils.sv`.

## Frozen today

| Property | CVA6 target | Spike treatment |
|---|---|---|
| XLEN | 64 | `--isa=RV64...` |
| Base ISA | I, M, A, F, D, C | `RV64IMAFDC` |
| Bitmanip | `BExtEn=1` | `_zba_zbb_zbc_zbs` (as tandem `get_isa_str` emits) |
| Compressed extras | Zcb enabled, Zcmp disabled | `_zcb` |
| Counter/CSR exts | Zicntr/Zihpm enabled | `_zicsr_zicntr` in solo profile; see gap below |
| Privilege modes | M, S, U (`HExtEn=0`) | `--priv=MSU` |
| MMU | Present; target named Sv39; Svnapot enabled | Tandem fork `mmu_mode` defaults to `sv39`; Svnapot behavior **unresolved** |
| PMP entries | `NrPMPEntries=8`, NAPOT enabled | `pmpregions_max=64`, `pmpregions_writable=8`, granularity 8 bytes |
| Boot / memory | ROM base `0x0001_0000` (64 KiB), DRAM base `0x8000_0000` (1 GiB), hart 0 | Spike top defaults match (`bootrom_base=0x10000`, `dram_base=0x80000000`, `dram_size=0x40000000`) |
| Misaligned LD/ST | Traps (`LD/ST_ADDR_MISALIGNED` in the LSU) | Do **not** pass `--misaligned` |
| Perf counters | Enabled | Compare only where RVFI exposes them; count values may diverge by design |

Solo invocation that encodes the above (see `scripts/spike_solo.sh`,
profile `matched`):

```sh
SPIKE_PROFILE=matched ./scripts/spike_solo.sh
# expands to: spike --disable-dtb \
#   --isa=RV64IMAFDC_zba_zbb_zbc_zbs_zcb_zicsr_zicntr --priv=MSU \
#   --param /top/core/0/pmpregions_max:uint64_t=64 \
#   --param /top/core/0/pmpregions_writable:uint64_t=8 \
#   --param /top/core/0/pmp_granularity:uint64_t=8 <elf>
```

Note: Spike prints `PMP Regions 40` for a max of 64 because
`Proc.cc` streams the value with `std::hex` still active (`0x40`).

Verified so far: both B1 ELFs exit 0 under profiles `default` and
`matched` — see `docs/evidence/spike-solo-*.log`.

## Unresolved before B2.3 acceptance

1. **ISA-string gaps.** The CVA6 config also sets `ZKN=1`,
   `RVZiCond=1`, and `RVZihpm=1`, which tandem `get_isa_str` does not
   emit. Decide per extension whether Spike models it, the test list
   avoids it, or a waiver is recorded.
2. **Tandem struct defaults.** `corev_apu/tb/common/spike.sv` sets
   only a subset of `st_core_cntrl_cfg` (extensions, modes, hart id,
   boot address). Fields it leaves at zero — including
   `pmp_regions`, `pmp_granularity`, `ext_zicsr_supported`,
   `ext_zicntr_supported`, and `unaligned_access_supported` — must be
   audited against the table above and patched or waived with reasons.
3. **Boot-address literal.** The same file writes
   `boot_addr = 'h0x10000`; verify what value actually reaches Spike
   before trusting tandem boot behavior.
4. **Debug/triggers.** `DebugEn=1` with `Sdtrig=0` but
   `SdtrigNrTriggers=4`; document which debug CSRs the reference is
   allowed to model differently.
5. **`--print-params` segfault.** The tandem Spike binary segfaults
   after printing top-level params (before core params) on this pin.
   Until fixed, parameter provenance comes from source inspection
   (`riscv/Proc.cc`) plus the `[SPIKE]` boot banner, not from
   `--print-params` output.

## Out of scope for Spike matching

Caches, branch prediction, commit-port timing, and all other
microarchitecture are intentionally unmodeled; tandem comparison is
architectural (instruction, PC, rd, privilege, trap, CSR values),
not cycle-accurate.
