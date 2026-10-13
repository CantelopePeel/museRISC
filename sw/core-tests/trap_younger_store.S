// A trapping (misaligned) load must suppress the younger store
// behind it in the pipeline: run with --expect-trap 4. If the
// store executed, the harness would report test 99 instead.
    .option norvc
    .text
    .globl _start
_start:
    la a0, scratch
    ld a1, 1(a0)           // misaligned: traps (cause 4)
    li t1, 0x10000000      // younger store to the exit address:
    li t0, 99              // must never retire
    sd t0, 0(t1)
1:  j 1b
    .data
    .align 3
scratch: .dword 0x1122334455667788
