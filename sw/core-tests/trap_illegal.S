// Expect an illegal-instruction trap (cause 2) on a CSR access,
// which stage 1 does not implement. Run with --expect-trap 2.
    .option norvc
    .text
    .globl _start
_start:
    li a0, 1
    csrr a0, mstatus
    li t1, 0x10000000      // reached only if no trap: report failure 99
    li t0, 99
    sd t0, 0(t1)
1:  j 1b
