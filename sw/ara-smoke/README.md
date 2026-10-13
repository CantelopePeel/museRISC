# Ara RVV smoke kernel

Minimal strip-mined `vadd`/`vfadd` check for the CVA6+Ara
verilated model (`ara_tb_verilator`, VLEN 512, 2 lanes),
using Ara's own `crt0.S`/`arch.link.ld` runtime and the
Ubuntu-packaged `riscv64-unknown-elf-gcc` (no LLVM build
required). Exit code: 0 pass, 1 integer-stage fail,
2 FP-stage fail (the harness shifts the EOC value right
by one).

Build the model once, then the smoke ELF, then simulate:

```sh
./scripts/ara_docker.sh make -C hardware checkout
./scripts/ara_docker.sh make -C hardware apply-patches
./scripts/ara_docker.sh make -C hardware verilate config=2_lanes vlen=512
./scripts/ara_docker.sh /repo/sw/ara-smoke/build.sh
./scripts/ara_docker.sh hardware/build/verilator/Vara_tb_verilator \
  -l ram,/repo/sw/ara-smoke/smoke.elf,elf
```

`build.sh` compiles `smoke.c` with `-march=rv64gcv` and
links it against Ara's crt0 at 0x80000000.
