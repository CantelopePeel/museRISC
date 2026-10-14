// Expect an illegal-instruction trap (cause 2) on the all-zero
// encoding. Run with --expect-trap 2. (Stage 1 used a CSR access
// here; CSRs exist since stage 3, so the encoding changed.)
    .option norvc
    .text
    .globl _start
_start:
    li a0, 1
    .word 0x00000000
    li t1, 0x10000000      // reached only if no trap: report failure 99
    li t0, 99
    sd t0, 0(t1)
1:  j 1b
