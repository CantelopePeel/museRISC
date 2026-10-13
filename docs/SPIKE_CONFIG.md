# Spike configuration for `cv64a6_imafdc_sv39` (B2.0 frozen)

This document records what the Spike behavioral oracle is configured
to represent during B2. B2.0 froze this on 2026-10-12 after a source
audit of the pinned CVA6 checkout: every configuration question is
either resolved below or explicitly waived with its scope limit.
Sail/ACT4 remains the normative compliance reference; Spike is a
second behavioral opinion.

Sources (pinned CVA6 checkout `81245a47`):
`core/include/cv64a6_imafdc_sv39_config_pkg.sv`,
`corev_apu/tb/ariane_soc_pkg.sv`, `corev_apu/tb/common/spike.sv`,
`verif/tb/core/uvma_cva6pkg_utils.sv` (`cva6pkg_to_core_cntrl_cfg`),
`verif/core-v-verif/lib/uvm_agents/uvma_core_cntrl/uvma_core_cntrl_utils.sv`
(`get_isa_str`), and the tandem Spike fork ISA parser
(`vendor/riscv/riscv-isa-sim/disasm/isa_parser.cc`).

## Frozen today

| Property | CVA6 target | Spike treatment |
|---|---|---|
| XLEN | 64 | `--isa=RV64...` |
| Base ISA | I, M, A, F, D, C | `RV64IMAFDC` |
| Bitmanip | `BExtEn=1` | `_zba_zbb_zbc_zbs` (as tandem `get_isa_str` emits) |
| Compressed extras | Zcb enabled, Zcmp disabled | `_zcb` |
| Counter/CSR exts | Zicntr/Zihpm enabled | Solo: `_zicsr_zicntr_zihpm`. Tandem conversion sets `ext_zicsr_supported=1` but `ext_zicntr_supported=0` (`uvma_cva6pkg_utils.sv:38-39`) — deliberate, so free-running counters are excluded from lockstep comparison |
| Conditional zero | `RVZiCond=1` | Solo: `_zicond`. Tandem: waived, see below |
| Scalar crypto | `ZKN=1` | Solo: `_zkn`. Tandem: waived, see below |
| Privilege modes | M, S, U (`HExtEn=0`) | `--priv=MSU` |
| MMU | Present; target named Sv39; Svnapot enabled | Solo: `_svnapot` accepted by the fork parser. Tandem fork `mmu_mode` defaults to `sv39`; `-v-` riscv-tests exercise translation but not NAPOT encodings |
| PMP entries | `NrPMPEntries=8`, NAPOT enabled | `pmpregions_max=64`, `pmpregions_writable=8`, granularity 8 bytes |
| Boot / memory | ROM base `0x0001_0000` (64 KiB), DRAM base `0x8000_0000` (1 GiB), hart 0 | Spike top defaults match (`bootrom_base=0x10000`, `dram_base=0x80000000`, `dram_size=0x40000000`) |
| Misaligned LD/ST | Traps (`LD/ST_ADDR_MISALIGNED` in the LSU) | Do **not** pass `--misaligned` |
| Perf counters | Enabled | Compare only where RVFI exposes them; count values may diverge by design |

Solo invocation that encodes the above (see `scripts/spike_solo.sh`,
profile `matched`):

```sh
SPIKE_PROFILE=matched ./scripts/spike_solo.sh
# expands to: spike --disable-dtb \
#   --isa=RV64IMAFDC_zba_zbb_zbc_zbs_zcb_zicsr_zicntr_zihpm_zicond_zkn_svnapot \
#   --priv=MSU \
#   --param /top/core/0/pmpregions_max:uint64_t=64 \
#   --param /top/core/0/pmpregions_writable:uint64_t=8 \
#   --param /top/core/0/pmp_granularity:uint64_t=8 <elf>
```

Note: Spike prints `PMP Regions 40` for a max of 64 because
`Proc.cc` streams the value with `std::hex` still active (`0x40`).

Verified (B2.1, 2026-10-12): all 174 B2 directed-list ELFs
(96 `rv64ui`, 26 `rv64um`, 38 `rv64ua`, 6 `rv64si`, 7 `rv64mi`,
1 `rv64uc`; 92 `-p-` + 82 `-v-`) exit 0 under profile `matched` —
see `docs/evidence/spike-solo-matched-full-2026-10-12.log`. The two
B1 ELFs also pass under profile `default`. This validates the ELFs
and the oracle; it says nothing about CVA6 (that is B2.2/B2.3).

## Resolved by source audit (B2.0)

1. **Tandem struct fields are set, not zero.** `spike.sv` builds its
   config through `cva6pkg_to_core_cntrl_cfg`
   (`verif/tb/core/uvma_cva6pkg_utils.sv`), which sets
   `ext_zicsr_supported=1`, `pmp_regions=NrPMPEntries` (8),
   `pmp_supported`, `debug_supported=DebugEn`, M/S/U mode flags,
   marchid/mvendorid, CSR-comparison masks, and the DPI
   `mstatus_write_mask` / `misa_override` params. Fields remaining
   zero are consistent with the target: `ext_zicntr_supported=0`
   (deliberate — free-running counters cannot lockstep) and
   `unaligned_access_supported=0` (matches the trapping LSU;
   `rv64mi-p-ma_addr` in the B2 lists checks exactly this).
2. **Boot-address literal is correct under Verilator.**
   `spike.sv:57` writes `boot_addr = 64'h0x10000`, where `x` is an
   unknown hex digit. A minimal Verilator probe of the same literal
   prints `BOOT_ADDR=0000000000010000` (2-state X→0), so tandem on
   our Verilator-only flow boots at `0x1_0000` as intended. A
   4-state simulator would propagate X — an upstream wart to
   remember if the UVM flow is ever used, not a B2 blocker.
3. **DRAM map covers the ELF load address.** The conversion carries
   a FIXME `dram_base='h40000000, dram_size='h80000000`
   (`uvma_cva6pkg_utils.sv:43-47`), i.e. 0x4000_0000–0xBFFF_FFFF,
   which includes the harness DRAM base 0x8000_0000; the `spike`
   module itself takes `DramBase='h8000_0000`, `Size=64 MiB`.

## Waived for the B2 lists (scope-limited)

1. **Zicond / ZKN in tandem.** The fork parser supports both
   (`disasm/isa_parser.cc:133,180-191,231`), and solo `matched`
   enables them. But `st_core_cntrl_cfg` has no fields for them, so
   tandem `get_isa_str` cannot emit them and tandem Spike would
   trap those instructions as illegal. The B2 lists contain only
   `rv64ui/um/ua/uc/si/mi` tests — no `czero` or scalar-crypto
   operands — so B2.2/B2.3 results are unaffected. **Revisit
   before adding any rv64uk/Zicond list**: that needs an in-repo
   patch to the conversion/`get_isa_str`, applied by the Docker
   script (third_party/ is not committed).
2. **PMP granularity in tandem.** The struct has no granularity
   field on this pin, so the DPI-side default is unverified. The
   B2 lists contain no PMP-programming test (no `pmpaddr` test; the
   privileged subset is csr/mcsr/illegal/ma_addr/ma_fetch/scall/
   sbreak/wfi/dirty). PMP evidence comes from ACT4 privileged
   tests in B2.4/#7, not from B2 tandem.
3. **Svnapot / debug triggers.** No B2 list test encodes NAPOT PTEs
   or drives the debug module (`SdtrigNrTriggers=4` but `Sdtrig=0`;
   the only breakpoint-adjacent tests are the `sbreak` trap tests).
   Waived for B2; revisit with ACT4 privileged/debug coverage.
4. **`--print-params` segfault.** The tandem Spike binary segfaults
   after printing top-level params (before core params) on this
   pin. Parameter provenance therefore comes from source
   inspection (`riscv/Proc.cc`) plus the `[SPIKE]` boot banner,
   not from `--print-params` output.
5. **`rv64mi-p-csr` cycle-CSR reads (B2.3 finding).** Tandem sets
   `ext_zicntr_supported=0` (resolved item 1 above), so tandem
   Spike has no `cycle` CSR and `TEST_CASE 25`
   (`csrrc zero, cycle, zero`) traps illegal on Spike only,
   printing `*** FAILED *** (tohost = 18)` (18 is the stale
   TESTNUM from the preceding case) while CVA6 completes with
   `*** SUCCESS ***`. Standalone-Spike bisection confirms the
   cause: the tandem ISA string fails with exit 18, adding
   `_zicntr` passes. Lockstep comparison itself reports zero
   mismatches and no UVM errors for this test. Waived for B2.3
   as an explained reference-configuration divergence, not a
   DUT result; the matrix keeps the runner's `FAIL` row.
   **Revisit** by enabling Zicntr in the tandem conversion via
   a Docker-script patch (third_party/ is not committed) and
   re-running the full tandem matrix under the new ISA string;
   do not change the frozen config for a single test mid-gate.

## Out of scope for Spike matching

Caches, branch prediction, commit-port timing, and all other
microarchitecture are intentionally unmodeled; tandem comparison is
architectural (instruction, PC, rd, privilege, trap, CSR values),
not cycle-accurate.
