// Regression (Linux/OpenSBI PMU, issue #21): the `time` CSR is
// a real-time counter and must keep advancing while
// mcountinhibit.CY stops `cycle`. OpenSBI's PMU stop-all sets
// CY, and Linux uses `time` as its clocksource; aliasing time
// to mcycle froze the kernel clock at pmu_sbi_devinit.
// Exit store 0 = pass, t0 = failing subtest number.
    .option norvc
    .text
    .globl _start
_start:
    li t0, 1
    li t1, 1                      // CY
    csrw mcountinhibit, t1
    csrr s0, cycle
    csrr s1, time
    li t2, 2000
1:  addi t2, t2, -1
    bnez t2, 1b
    csrr s2, cycle
    csrr s3, time

    li t0, 2                      // cycle stayed stopped
    bne s2, s0, fail
    li t0, 3                      // time advanced substantially
    sub t3, s3, s1
    li t4, 100
    bltu t3, t4, fail

    li t0, 4
    csrw mcountinhibit, x0        // cycle resumes when CY clears
    csrr s0, cycle
    li t2, 100
1:  addi t2, t2, -1
    bnez t2, 1b
    csrr s2, cycle
    bne s2, s0, pass
    j fail

pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b
