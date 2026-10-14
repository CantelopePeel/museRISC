# Linux/OpenSBI platform for the in-house core (#21)

This is a Verilator platform around `muserisc_core`; it is not
SoC integration. `soc_tb` models a boot ROM, CLINT, PLIC,
16550 UART and 128 MiB RAM, using the addresses in
`muserisc.dts`.

Build and reproduce the recorded boot from the repo root:

```bash
make -C sim soc
bash scripts/build_opensbi.sh
bash scripts/build_linux_kernel.sh
build/sim/soc_tb 1000000000 \
  --load 0x1000=build/linux/boot_stub.bin \
  --load 0x80000000=build/linux/fw_jump.bin \
  --load 0x83000000=build/linux/muserisc.dtb \
  --load 0x80200000=build/linux/Image \
  --uart-log build/linux/linux-boot-uart.log \
  --exit-string MUSERISC_LINUX_BOOT_OK
```

The OpenSBI-only smoke gate substitutes `s_hello.bin` for the
kernel `Image` and `--exit-string HELLO`. Kernel output takes
a long time to appear because the current simulator runs at
hundreds of thousands of guest cycles per second.

The checked-in DT kernel command line is part of the gate:
`console=ttyS0,115200 earlycon=sbi cryptomgr.notests
initcall_debug loglevel=8 rw`. The kernel build embeds the
static `/init` from `init.c`; it mounts proc, prints uname
and `/proc/version`, then `MUSERISC_LINUX_BOOT_OK`. This is a
single-hart embedded-initramfs boot, not a distro or shell.
Evidence and the precise claim boundary are in
`docs/evidence/README.md`.
