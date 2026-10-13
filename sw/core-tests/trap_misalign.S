// Expect a load-address-misaligned trap (cause 4): stage 1 traps
// misaligned accesses instead of emulating them.
// Run with --expect-trap 4.
    .option norvc
    .text
    .globl _start
_start:
    la a0, scratch
    ld a1, 1(a0)           // misaligned doubleword load
    li t1, 0x10000000      // reached only if no trap: report failure 99
    li t0, 99
    sd t0, 0(t1)
1:  j 1b
    .data
    .align 3
scratch: .dword 0x1122334455667788
