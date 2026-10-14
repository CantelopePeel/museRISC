// Expect an instruction access fault (cause 1): physical
// addresses are 56 bits, so fetching at 2^56 in M-mode (no
// translation) faults. The jalr commits first. Run with
// --expect-trap 1.
    .option norvc
    .text
    .globl _start
_start:
    li a0, 1
    slli a0, a0, 56
    jalr x0, a0, 0
    li t1, 0x10000000      // reached only if no trap: report failure 99
    li t0, 99
    sd t0, 0(t1)
1:  j 1b
