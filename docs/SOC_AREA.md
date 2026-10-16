# SoC area and timing estimate (synthesis, 2026-10-16)

This is ORFS synthesis of the whole `muserisc_soc_top` on fork main
035bb05. That covers the core, the L1 I$/D$ with bus arbiter (#15),
the SoC fabric, CLINT/PLIC/UART/boot ROM and crypto. The core
includes the element-serial vector unit, whose FP runs on the shared
multi-cycle FPU (#20), the multi-cycle M unit, and the CSR VLMAX shift
and PLIC tournament tree (#19).

Every large array is an SRAM macro, 15 per SoC:

| Array | Count | Nangate45 macro | sky130hd macro |
|---|---:|---|---|
| VRF bank (256×64 1R1W) | 3 | `fakeram45_256x64_1r1w` (generated) | `sky130_sram_1rw1r_64x256_8` |
| L1 data way (512×64 1RW) | 6 | `fakeram45_512x64` (stock) | `sky130_sram_1rw1r_128x256_8`, used as 256×128 |
| L1 tag way (64×44 1RW) | 6 | `fakeram45_64x44` (generated) | `sky130_sram_1rw1r_44x64_8` |

These are post-synthesis numbers: no placement, no timing repair,
and delays from the liberty wire-load model. They are meant for the
chip-size decision, not for signoff.

Evidence: [`evidence/soc-sram-synth-2026-10-16.log`](evidence/soc-sram-synth-2026-10-16.log).

## Results

Flat synthesis (the ORFS default) gives the totals. A second,
hierarchical run (`SYNTH_HIERARCHICAL=1`) gives the per-module split;
it keeps module boundaries, so it comes out 1–4 % larger.

Both flows read the RTL with `-D SYNTHESIS`, so simulation-only
checks are dropped. ORFS passes that define itself, and the configs
repeat it.

| | Nangate45 | sky130hd |
|---|---:|---:|
| Std-cell area | 0.533 mm² (533,214 µm²) | 2.496 mm² (2,496,057 µm²) |
| SRAM macros (15) | 0.158 mm² (158,051 µm²) | 6.225 mm² (6,225,284 µm²) |
|   VRF banks (3) | 38,473 µm² | 1,258,388 µm² |
|   L1 data ways (6) | 103,809 µm² | 4,332,656 µm² |
|   L1 tag ways (6) | 15,769 µm² | 634,240 µm² |
| Total synthesized area | 0.691 mm² | 8.721 mm² |
| Cells (incl. macros) | 313,021 | 274,034 |
| Flip-flops | 27,293 | 27,299 |
| **Fmax (unrepaired, wire-load)** | **166 MHz** (6.03 ns) | **12.1 MHz** (82.8 ns) |
| Limiting path | `vls_started_q` → D$ data macro `ce_in` (5.5 ns logic) | VRF OpenRAM `dout1` (falling edge) → FPU operand enable: 40.9 ns of logic in half a cycle |
| Fmax if the OpenRAM outputs were registered | (same) | **22.2 MHz** (44.95 ns): FPU `state_q` → `exmem_result_q` |
| Yosys wall time / peak RSS (whole make) | 1 h 04 min / 2.71 GB | 1 h 01 min / 2.77 GB |

Fmax is found by bisecting the clock period in OpenSTA, which is the
`min_period_bisect` line of `sta_synth.tcl`. A period-minus-WNS figure
is wrong once a path starts at a falling-edge macro output, whose
budget is half the period.

On sky130 the half-cycle VRF read paths therefore set fmax:
- the period must be at least 2 × (clk→q + logic + uncertainty)
  = 2 × 41.4 ns;
- with those outputs registered, the next limit is the full-cycle
  FPU result path at 45 ns.

Everything else is shorter:
- PLIC and fabric ~18 ns;
- the caches ~20 ns;
- crypto ~24 ns.

On Nangate45 every block closes with slack at 100 MHz; the worst
paths in each block are 4.6–5.5 ns. The hierarchical netlists agree:
6.03 ns on Nangate45; 66.5 ns (15.0 MHz) on sky130, or 34.8 ns
(28.7 MHz) rising-edge only.

The sky130 column comes from a direct sky130hd synthesis run (the
platform and the OpenRAM macros ship in `openroad/orfs:latest`), not
from scaling:
- Std-cell area scales 4.68× from Nangate45 to sky130hd (flat runs).
- The macros do not scale that way: sky130 OpenRAM is 33–42× the
  fakeram45 area for the same array.
- So on sky130 the macros are 71 % of the synthesized area.

Where the Yosys time went: mostly in `abc` (Nangate45 3,082 s, sky130
2,899 s), with `extract_fa` at ~280 s, on a host at load ~100–150.
With the combinational vector `fp_eval` gone, flat synthesis is about
3× faster than before #20. The hierarchical runs took 21 min each at
2.35 GB.

### Area by module (hierarchical runs)

"Own" is the module's area excluding kept children. The sky130 run
keeps more modules. On Nangate45 the regfiles, ALU, decoder and RVC
are flattened into `muserisc_core`, SHA-256 into `muse_crypto_top`,
the L1 tag wrappers into the caches, and CLINT, UART, fabric and
arbiter into the top.

| Module | Nangate45 own (µm²) | sky130hd own (µm²) | Own flops (sky130 run) | Notes |
|---|---:|---:|---:|---|
| L1 data ways (6 × `muserisc_sram_sp`) | 6 × 17,735 | 6 × 724,923 | 6 × 66 | macro + read capture + half select |
| L1 tag ways (6 × `muserisc_sram_sp`) | ² | 6 × 107,366 | 6 × 45 | macro + read capture |
| VRF banks (3 × `muserisc_vrf_bank`) | 3 × 13,252 | 3 × 421,852 | 3 × 65 | macro + read capture |
| `muserisc_vec` | 61,218 | 284,007 | 1,481 | element-serial vector unit; FP on the shared FPU |
| `muserisc_csr` | 57,498 | 273,381 | 3,063 | |
| `muserisc_mmu` | 65,873 | 302,419 | 4,557 | TLBs + walker |
| `muserisc_fpu` | 52,075 | 243,099 | 1,394 | multi-cycle FPU, shared by scalar and vector |
| `muserisc_core` pipeline | 96,571 ³ | 203,017 | 2,730 | |
| `muserisc_fpregfile` / `regfile` | ³ | 106,162 / 96,927 | 2,048 / 2,048 | 32×64 flops each |
| `muserisc_alu`, `decoder`, `rvc` | ³ | 31,109 | 0 | |
| `muserisc_muldiv_mc` | 38,953 | 183,989 | 276 | multi-cycle M unit |
| `muserisc_bext` | 28,537 | 141,361 | 0 | bit-manip / scalar crypto |
| `muserisc_vregfile` logic | 5,337 | 28,569 | 731 | v0 shadow + write bypass |
| `muserisc_dcache` logic | 26,712 ² | 68,910 | 1,299 | |
| `muserisc_icache` logic | 9,221 ² | 16,638 | 270 | |
| `ec_field` | 42,260 | 197,387 | 1,291 | crypto field unit |
| `sha256_block` | ⁴ | 158,568 | 2,569 | |
| `muse_crypto_top` + bridge | 45,888 ⁴ | 49,926 | 1,098 | |
| `muserisc_plic` | 33,472 | 160,669 | 1,184 | 32 sources, tournament tree |
| fabric, arbiter, CLINT, UART, boot ROM, top | 9,334 | 41,547 | 639 | |
| **Total** | **719,116** | **8,846,976** | **27,539** | |

² The Nangate45 D$ / I$ rows include their 4 / 2 tag ways
(macros 4 / 2 × 2,628 µm²). ³ The Nangate45 "pipeline" row includes
the regfiles, ALU, decoder and RVC. ⁴ The Nangate45
`muse_crypto_top` row includes SHA-256.

## SRAM mapping

`muserisc_vrf_bank` (one 256×64 replica per VRF read port, every write
to all three) and `muserisc_sram_sp` (L1 data and tag ways) keep their
behavioural models by default. Two defines, set only by the ORFS
configs, select macro instances: `MUSERISC_SRAM_FAKERAM45` for
nangate45 and `MUSERISC_SRAM_SKY130` for sky130hd. `muserisc_sram_sp`
maps only the two L1 geometries, 512×64 with 8 lanes and 64×44 with
1 lane; any other geometry, such as the small cache unit-test
configurations, stays behavioural. Both ORFS configs read the same
RTL list, `rtl/muserisc_soc_files.mk`.

**Nangate45.** ORFS ships only single-port (1RW) fakeram45 views.
- **VRF banks:** ORFS has no 1R1W view and no 256×64 size, so
  `flow/designs/nangate45/muserisc_soc/sram/gen_fakeram45_1r1w.py`
  generates LEF/Liberty/Verilog views of a 256×64 1R1W macro in the
  fakeram45 style.
  - Footprint 134.71 × 95.20 µm = 12,824 µm². A 256×64 1RW macro
    interpolated between fakeram45_256x48 and 256x96 is ~9,751 µm²;
    ×1.3 for the dual-port bit cell and second decoder gives
    12,677 µm²; that is rounded up 1.2 % to a site- and row-aligned
    footprint.
  - Clk→q 0.27 ns on the rising edge.
- **L1 data ways:** the stock `fakeram45_512x64` (1RW, per-bit mask).
- **L1 tags:** the same script (`--ports 1rw`) generates
  `fakeram45_64x44`. Its footprint, 46.93 × 56.0 µm = 2,628 µm²,
  interpolates the stock 64x32 and 64x62 by width.
- **Write masks:** the wrappers drive each byte or lane enable onto
  the per-bit mask.

**sky130hd.** The OpenRAM macros prebuilt in ORFS's `sky130ram`, all
1RW+1R with a byte write mask and active-low selects:
- **VRF banks:** `sky130_sram_1rw1r_64x256_8`. Port 0 writes, port 1
  reads.
- **L1 data ways:** ORFS has no 512×64 single-port macro. Each way
  uses `sky130_sram_1rw1r_128x256_8` as 256×128: address bit 0
  selects the 64-bit half through the upper or lower 8 mask lanes on
  writes and a registered half select on reads. Port 1 is unused.
- **L1 tags:** `sky130_sram_1rw1r_44x64_8` (port 0 only).

**Read hold.** Neither macro family holds its read data.
- OpenRAM sets `dout` to X on every rising edge and reloads it on the
  falling edge only when that port reads; the .lib `dout` arcs are
  `falling_edge`.
- fakeram returns X after a non-read edge.

The RTL contracts expect held data: the VRF holds while `re` is low,
and `muserisc_sram_sp` holds until the next read. So every macro
wrapper has a capture register: `rd_q` marks a read in the previous
cycle, `hold_q` takes the macro output in the cycle after a read, and
`rdata = rd_q ? macro_out : hold_q`. Latency is unchanged. The cost
is 15 × (44–64) flops plus muxes, ~1 % of std-cell area.

The vector unit depends on the hold: without it, both macro families
fail the vector TB. The caches pass the full directed suite even
without it, because they consume array data in the cycle after the
read. They keep the capture register anyway, since `muserisc_sram_sp`
documents the hold.

**Half-cycle paths on sky130.** OpenRAM read data arrives ~0.4 ns
after the falling edge. So everything from `dout` through the capture
mux (and, for the VRF, the write bypass) to the first flop gets half
a clock period, and the clock period must be at least twice that path.
In the run above that path, from VRF read data into the FPU operand
enables, is 40.9 ns, and it sets the sky130 fmax at 12.1 MHz. A full
cycle would need a read pipeline stage (one more cycle of latency) or
a macro with rising-edge output.

**Collisions.**
- The VRF bypass in `muserisc_vregfile` covers same-word read/write
  collisions for the bytes being written. Unwritten bytes of a
  colliding word still come from the macro, so this design assumes
  the macro returns them intact. That holds for both models and for a
  dual-port cell, whose unwritten columns are not driven. OpenRAM
  documents same-address read+write as unsupported, so this needs
  confirming for sky130, or a full-word bypass.
- The L1 arrays are single-port, so they cannot collide.

**Simulation.** `make -C sim srammacro` (part of `make core-test`)
builds each macro family's behavioural models and runs:
- the vector unit TB;
- every directed core test on `muserisc_cpu`, with the real cache
  geometry and random bus latency (36 runs);
- the RTL SoC crypto firmware.

The models are
`flow/designs/nangate45/muserisc_soc/sram/*.v` (generated) and
`flow/designs/sky130hd/muserisc_soc/sram/gen_openram_models.py`. They
follow the vendor read behaviour: undefined data after a non-read
edge (pseudo-random garbage, because 2-state Verilator would turn X
into 0), and on sky130 data only after the falling edge.

Results are bit-exact, with cycle counts identical to the behavioural
build in every directed test, the SoC crypto run and OpenSBI.
Separate checks:
- Removing the VRF capture register fails the vector TB on both
  families.
- Breaking the sky130 half select fails the cache tests.
- The vendor OpenRAM `.v` files themselves pass the vector TB (3
  X-randomization seeds) and the full directed suite under Verilator.
  Two edits were needed: `$display` stripped, and the posedge
  `dout = 'bx` made non-blocking. As a blocking assignment it races
  the same-edge capture flop in simulation, which is zero-delay; in
  silicon the macro's clk→q exceeds the flop's hold time.

`make lint` lints the SoC under both defines.

**Memory guard.** With all 15 arrays on macros, no inferred memory
exceeds ORFS's default 4096-bit guard. The largest are the 32×64
int/FP regfiles and SHA-256 `w`, at 2048 bits each. So
`SYNTH_MEMORY_MAX_BITS` is no longer overridden: #16 set 16384 and
#15 set 32768.

## RTL fix needed for synthesis

The core loaded its reset PC from the `boot_pc_i` port under the async
reset (`pc_q <= boot_pc_i`). That is an async-load flop
(`$_ALDFFE_`), and neither library can map it, so ORFS failed
`check -assert` with 64 unmapped `pc_q` bits.

Now `pc_r` resets to 0, and an async-set `boot_q` flag selects
`boot_pc_i` until the first PC update. The architectural behaviour
and cycle counts are unchanged, provided `boot_pc_i` is a static
strap: it is now read combinationally until the first PC update
rather than sampled at reset, so it must be stable through that cycle
(see the SoC SDCs).

Follow-up: like every async-reset flop in the SoC, `boot_q` needs a
synchronized reset release, and `muserisc_soc_top` has no reset
synchronizer yet.

## Timing findings

These are pure synthesis results, before any repair, with delays from
the liberty wire-load model and no placement. The sky130hd numbers in
particular are pessimistic, so read them as relative depth rather
than as an achievable fmax.

1. **Earlier limiters are fixed on main.**
   - The vector FP element step (128 ns combinational `fp_eval`) went
     multi-cycle on the shared FPU in #20.
   - The CSR VLMAX divider (39 ns) became a shift in #19.
   - PLIC arbitration became a log-depth tree in #19.
2. **Nangate45: 166 MHz unrepaired.** The worst paths run from
   `vls_started_q` (vector load/store sequencing) into the D$ data
   macro enable and the EX/MEM result, ~5.5 ns. Every block has ≥ 4 ns
   slack at 100 MHz.
3. **sky130hd: the OpenRAM half-cycle read limits fmax to 12.1 MHz.**
   - VRF read data is driven ~0.4 ns after the falling edge.
   - It passes through the capture mux, the vregfile bypass and the
     FPU operand muxes (40.9 ns) into `u_fpu.prod_op` enables.
   - The fix is a VRF read pipeline stage (one more cycle of read
     latency) or a rising-edge macro. Either gets the sky130 SoC to
     ~22 MHz.
   - Next is the FPU result → EX/MEM result path, 45 ns full cycle.
4. **sky130hd full-cycle paths ≥ 20 ns.** FPU result and status,
   vector FP result capture (`u_vec.fp_res`, 44 ns) and CSR `fflags`
   (39 ns): all FPU-adjacent wide muxing.

## sky130 chip-size estimate (rough)

- **Synthesized (flat):** 2.50 mm² std cells + 6.23 mm² SRAM macros.
- **Placed std-cell region:** 4.2–5.0 mm² at 50–60 % utilization.
  Timing repair and CTS typically add another 0–20 %, giving
  4.2–6.0 mm².
- **Macros with a 40 µm halo:** ≈ 7.85 mm² in total.
  - VRF: 3 × 0.541 mm² = 1.62 mm².
  - L1 data: 6 × 0.870 mm² = 5.22 mm².
  - L1 tags: 6 × 0.167 mm² = 1.00 mm².
- **Core with caches ≈ 12.0–13.8 mm².** That is above Caravel's
  ~10 mm². Without the L1 arrays (VRF only, caches' logic kept) the
  figure is ~5.8–7.6 mm².

Assumptions: typical-corner libraries (sky130 tt 1.8 V / 25 °C);
utilization as in typical ORFS sky130hd designs (50–60 %); no IO
ring.

The prebuilt OpenRAM macros cost 22–38 µm² per bit, and the 6 L1 data
ways alone take 4.3 mm² synthesized and 5.2 mm² placed. The levers
are:
- smaller caches, e.g. 4 KiB + 4 KiB, which saves ~4 mm² placed;
- denser or fewer, larger macros: a custom OpenRAM single-port config
  instead of the 1rw1r ones, or DFFRAM;
- fewer VRF replicas (each 256×64 is 0.54 mm² placed).

On Nangate45 (for comparison, not a target) the same SoC is 0.69 mm²
synthesized and reaches 166 MHz before repair.

## Reproduce

```sh
DESIGN=muserisc_soc ./scripts/openroad_docker.sh synth                    # nangate45, flat
DESIGN=muserisc_soc PLATFORM=sky130hd ./scripts/openroad_docker.sh synth  # sky130hd, flat
DESIGN=muserisc_soc ./scripts/openroad_docker.sh "FLOW_VARIANT=hier SYNTH_HIERARCHICAL=1 synth"
# post-synthesis STA (inside the image, ORFS env loaded):
#   STA_LIBS="<std-cell lib> <macro libs>" STA_ODB=results/<plat>/muserisc_soc_top/base/1_synth.odb \
#   STA_SDC=results/<plat>/muserisc_soc_top/base/1_synth.sdc STA_PREFIXES="u_cpu/u_core/u_vec ..." \
#   openroad -exit -no_init designs/nangate45/muserisc_soc/sta_synth.tcl
# regenerate the generated macro views / models:
python3 flow/designs/nangate45/muserisc_soc/sram/gen_fakeram45_1r1w.py flow/designs/nangate45/muserisc_soc/sram
python3 flow/designs/nangate45/muserisc_soc/sram/gen_fakeram45_1r1w.py --ports 1rw --depth 64 --width 44 \
  --w 46.93 --h 56.0 --tcq 0.21 flow/designs/nangate45/muserisc_soc/sram
python3 flow/designs/nangate45/muserisc_soc/sram/gen_fakeram45_1r1w.py --ports 1rw --model-only \
  --depth 512 --width 64 flow/designs/nangate45/muserisc_soc/sram
python3 flow/designs/sky130hd/muserisc_soc/sram/gen_openram_models.py flow/designs/sky130hd/muserisc_soc/sram
```

Each flat synthesis takes ~1 h on a loaded host, mostly in ABC.
Floorplan, placement and repair were not run; the numbers above stop
at synthesis.
