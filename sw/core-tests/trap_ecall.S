// Expect an environment-call trap (cause 11). Run with --expect-trap 11.
    .option norvc
    .text
    .globl _start
_start:
    li a0, 1
    ecall
    li t1, 0x10000000
    li t0, 99
    sd t0, 0(t1)
1:  j 1b
