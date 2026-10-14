// Regression (found by OpenSBI boot, issue #21): a CSR write
// younger than a trapping instruction must not commit before
// the trap is taken. OpenSBI's csr_read_allowed installs an
// expected-trap mtvec, probes a possibly-absent CSR, then
// restores mtvec with the very next instruction; if that
// restore commits while the illegal-instruction trap is still
// in flight, the trap vectors to the main handler instead.
//
// Here the expected handler additionally checks that a
// younger `csrw mscratch` has not executed yet when it runs.
// Handled mode (no --expect-trap); exit store 0 = pass, t0 =
// failing subtest number.
    .option norvc
    .text
    .globl _start
_start:
    li t0, 1
    la t1, main_handler
    csrw mtvec, t1
    li t1, 0x1111
    csrw mscratch, t1

    li t0, 2
    la a0, expected_handler
    csrrw a0, mtvec, a0      // install expected trap; a0 = main
    csrr a7, 0x3c0           // absent CSR (pmpaddr16): traps
    csrw mtvec, a0           // younger restore (OpenSBI shape):
                             // must not beat the in-flight trap
    li t1, 0x2222            // (re-executed after mret)
    csrw mscratch, t1

    li t0, 3                 // trap reached the expected handler
    la t1, seen_magic
    ld t2, 0(t1)
    li t3, 0x600D
    bne t2, t3, fail
    li t0, 4                 // cause was illegal-instruction (2)
    la t1, seen_cause
    ld t2, 0(t1)
    li t3, 2
    bne t2, t3, fail
    li t0, 5                 // younger csrw runs after mret
    csrr t2, mscratch
    li t3, 0x2222
    bne t2, t3, fail
    j pass

// Records mcause and whether mscratch still held the old
// value (younger csrw not yet committed), then skips the
// trapping csrr. Clobbers a3/a4 only (dead at the probe site).
    .align 3
expected_handler:
    csrr a4, mcause
    la a3, seen_cause
    sd a4, 0(a3)
    csrr a4, mscratch
    li a3, 0x1111
    bne a4, a3, 1f
    la a3, seen_magic
    li a4, 0x600D
    sd a4, 0(a3)
1:  csrr a4, mepc
    addi a4, a4, 4
    csrw mepc, a4
    mret

main_handler:                // must never run for the probe
    li t0, 99
    j fail

pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

    .data
    .align 3
seen_cause: .dword 0
seen_magic: .dword 0
