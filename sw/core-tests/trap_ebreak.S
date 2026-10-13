// Expect a breakpoint trap (cause 3). Run with --expect-trap 3.
    .option norvc
    .text
    .globl _start
_start:
    li a0, 1
    ebreak
    li t1, 0x10000000
    li t0, 99
    sd t0, 0(t1)
1:  j 1b
