// Expect a store-address-misaligned trap (cause 6).
// Run with --expect-trap 6.
    .option norvc
    .text
    .globl _start
_start:
    la a0, scratch
    li a1, -1
    sw a1, 2(a0)           // misaligned word store
    li t1, 0x10000000
    li t0, 99
    sd t0, 0(t1)
1:  j 1b
    .data
    .align 3
scratch: .dword 0
