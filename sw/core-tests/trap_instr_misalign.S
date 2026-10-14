// Expect an instruction-address-misaligned trap (cause 0):
// IALIGN is 32, so jumping to a 2-byte-aligned target faults
// at fetch. Run with --expect-trap 0.
    .option norvc
    .text
    .globl _start
_start:
    la a0, target
    ori a0, a0, 2
    jalr x0, a0, 0
target:
    li t1, 0x10000000      // reached only if no trap: report failure 99
    li t0, 99
    sd t0, 0(t1)
1:  j 1b
