# Host core integration (Phase 1+)

museRISC does not home-grow an RV64GCV core. Integration plan:

1. **CVA6** (`third_party/cva6`, openhwgroup/cva6) — RV64GC, 6-stage,
   MMU/Sv39, AXI. Config: `cv64a6_imafdc_sv39` as the starting point.
2. **Ara** (`third_party/ara`, pulp-platform/ara) — RVV 1.0 vector
   co-processor designed to attach to CVA6. Start VLEN=512, 2 lanes.
3. Glue in this directory will hold the AXI crossbar config, boot ROM,
   and the arch-test target (`link.ld`, trap handler) for RISCOF.

Fetch with `./scripts/setup.sh` (pinned commits recorded there).
Compliance procedure: `scripts/run_compliance.sh` + COMPLIANCE.md.
