// Expect a load access fault (cause 5): physical addresses
// are 56 bits, so loading at 2^56 in M-mode faults.
// Run with --expect-trap 5.
    .option norvc
    .text
    .globl _start
_start:
    li a0, 1
    slli a0, a0, 56
    ld a1, 0(a0)
    li t1, 0x10000000      // reached only if no trap: report failure 99
    li t0, 99
    sd t0, 0(t1)
1:  j 1b
