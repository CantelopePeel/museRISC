// Directed virtual-memory tests (issue #18 stage 3b): Sv39
// translation through the running pipeline -- 4K pages, 2M
// superpages, Svnapot 64K, page faults (12/13/15), the U/SUM/MXR
// permission rules, hardware A/D updates, SFENCE staleness, and
// MPRV. M-mode builds the tables; most tests run in S with page
// faults delegated to the S handler (records cause/tval, skips
// or redirects). t0 = test number; exit store 0 = pass.
//
// Layout: identity 2M superpage VA 0..2M -> PA 0 (code, stacks,
// tables at 0x100000/0x101000/0x102000). Test pages live at PA
// 0x180000.. (inside the identity window, so S can always check
// the physical alias), reached through VA 0x200000+ 4K mappings.
    .option norvc
    .text
    .globl _start

.equ PGROOT, 0x100000
.equ PGL1,   0x101000
.equ PGL0,   0x102000
.equ VA_A,   0x200000          // -> PA 0x180000 RW
.equ VA_B,   0x201000          // -> PA 0x181000 R
.equ VA_C,   0x202000          // -> PA 0x182000 X
.equ VA_D,   0x203000          // -> PA 0x183000 RW U
.equ VA_AD,  0x204000          // -> PA 0x184000 RW, A/D clear
.equ VA_NAP, 0x210000          // -> PA 0x190000 64K NAPOT RW
.equ VA_ALS, 0x300000          // -> PA 0x200000 RW (superpage alias)
.equ VA_SUP, 0x400000          // -> PA 0x200000 2M superpage RW

.macro PTEW tbl, idx, pa, flags
    li t1, \pa
    srli t1, t1, 2
    ori t1, t1, \flags
    li t2, \tbl + \idx * 8
    sd t1, 0(t2)
.endm

_start:
    la sp, main_stack_top
    la t1, trap_stack_top
    addi t1, t1, -64
    csrw mscratch, t1
    csrw sscratch, t1
    la t1, handler_m
    csrw mtvec, t1
    la t1, handler_s
    csrw stvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    // Zero the three table pages.
    li t1, PGROOT
    li t2, PGROOT + 0x3000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    // Tables. Flags: V1 R2 W4 X8 U16 G32 A64 D128.
    PTEW PGROOT, 0, PGL1, 0x01            // root[0] -> L1
    PTEW PGL1, 0, 0x000000, 0xCF          // 2M identity RWX
    PTEW PGL1, 1, PGL0, 0x01              // L1[1] -> L0
    PTEW PGL1, 2, 0x200000, 0xC7          // 2M superpage RW
    PTEW PGL0, 0, 0x180000, 0xC7
    PTEW PGL0, 1, 0x181000, 0xC3
    PTEW PGL0, 2, 0x182000, 0xC9
    PTEW PGL0, 3, 0x183000, 0xDF          // RWX U: also hosts u_code
    PTEW PGL0, 4, 0x184000, 0x07          // A/D clear on purpose
    PTEW PGL0, 256, 0x200000, 0xC7
    // NAPOT: same PTE replicated across L0[16..31].
    li t1, 0x198
    slli t1, t1, 10
    ori t1, t1, 0xC7
    li t2, 1
    slli t2, t2, 63
    or t1, t1, t2
    li t2, PGL0 + 16 * 8
    li a0, PGL0 + 32 * 8
1:  sd t1, 0(t2)
    addi t2, t2, 8
    blt t2, a0, 1b
    // Payload: magic in B and D pages, mini-function in C page,
    // and the U-mode stub copied into the U page (U fetch needs
    // a U page; the stub is position-independent).
    li t1, 0x181000
    li t2, 0xB001
    sd t2, 0(t1)
    la t1, u_code
    li t2, 0x183000
    la a0, u_code_end
1:  lw a1, 0(t1)
    sw a1, 0(t2)
    addi t1, t1, 4
    addi t2, t2, 4
    blt t1, a0, 1b
    li t1, 0x183200
    li t2, 0xD001
    sd t2, 0(t1)
    li t1, 0x182000
    li t2, 0x77700693                     // addi a3, x0, 0x777
    sw t2, 0(t1)
    li t2, 0x00008067                     // ret
    sw t2, 4(t1)
    // Delegate page faults (and U ecalls) to S; turn on Sv39.
    li t1, 0xB100
    csrw medeleg, t1
    li t1, 8
    slli t1, t1, 60
    ori t1, t1, PGROOT >> 12
    csrw satp, t1
    sfence.vma
    la t1, s_main
    csrw mepc, t1
    li t1, (1 << 11)
    csrs mstatus, t1
    mret

// ---- S-mode test body ------------------------------------------
s_main:
    // 1: basic 4K translation both directions.
    li t0, 1
    li a1, VA_A
    li a2, 0xA001
    sd a2, 0(a1)
    li a1, 0x180000
    ld a3, 0(a1)
    bne a3, a2, fail_s
    // 2: load page fault on unmapped VA (13, tval = VA).
    li t0, 2
    li a1, 0x40000000
    ld a3, 0(a1)
    la a1, s_cause
    ld a3, 0(a1)
    li a2, 13
    bne a3, a2, fail_s
    la a1, s_tval
    ld a3, 0(a1)
    li a2, 0x40000000
    bne a3, a2, fail_s
    // 3: store to R-only page faults (15); load is fine.
    li t0, 3
    li a1, VA_B
    ld a3, 0(a1)
    li a2, 0xB001
    bne a3, a2, fail_s
    sd a2, 8(a1)
    la a1, s_cause
    ld a3, 0(a1)
    li a2, 15
    bne a3, a2, fail_s
    // 4: load from X-only page faults (13) until MXR is set.
    li t0, 4
    li a1, VA_C
    lw a3, 0(a1)
    la a1, s_cause
    ld a3, 0(a1)
    li a2, 13
    bne a3, a2, fail_s
    li a1, (1 << 19)
    csrs sstatus, a1
    li a1, VA_C
    lw a3, 0(a1)
    li a2, 0x77700693
    bne a3, a2, fail_s
    li a1, (1 << 19)
    csrc sstatus, a1
    // 5: execute the translated X page.
    li t0, 5
    li a1, VA_C
    jalr ra, a1, 0
    li a2, 0x777
    bne a3, a2, fail_s
    // 6: fetch from an R-only page faults (12) at the target VA.
    li t0, 6
    la a1, after_fetch_fault
    la a2, s_resume
    sd a1, 0(a2)
    li a1, VA_B
    jalr ra, a1, 0
    j fail_s                              // reachable only if no fault
after_fetch_fault:
    la a1, s_cause
    ld a3, 0(a1)
    li a2, 12
    bne a3, a2, fail_s
    la a1, s_tval
    ld a3, 0(a1)
    li a2, VA_B
    bne a3, a2, fail_s
    // 7: S accessing a U page needs SUM.
    li t0, 7
    li a1, VA_D + 0x200
    ld a3, 0(a1)
    la a1, s_cause
    ld a3, 0(a1)
    li a2, 13
    bne a3, a2, fail_s
    li a1, (1 << 18)
    csrs sstatus, a1
    li a1, VA_D + 0x200
    ld a3, 0(a1)
    li a2, 0xD001
    bne a3, a2, fail_s
    li a1, (1 << 18)
    csrc sstatus, a1
    // 8: U-mode excursion (U page ok, S page faults to S).
    li t0, 8
    la a1, s_after_u
    la a2, s_resume
    sd a1, 0(a2)
    la sp, u_stack_top
    li a1, VA_D                           // u_code copy in the U page
    csrw sepc, a1
    li a1, (1 << 8)
    csrc sstatus, a1                      // SPP = U
    sret
s_after_u:
    la sp, main_stack_top                 // restore S stack pointer
    li a1, 0x183208
    ld a3, 0(a1)
    li a2, 0xD00D
    bne a3, a2, fail_s
    la a1, s_cause                        // last S trap: U's ecall (8)
    ld a3, 0(a1)
    li a2, 8
    bne a3, a2, fail_s
    // 9: hardware A/D update.
    li t0, 9
    li a1, VA_AD
    li a2, 0xAD001
    sd a2, 0(a1)                          // store first: sets A and D
    li a1, PGL0 + 4 * 8
    ld a3, 0(a1)
    andi a3, a3, 0xC0
    li a2, 0xC0
    bne a3, a2, fail_s
    // clear A/D again, then a plain load must set A only.
    li a1, PGL0 + 4 * 8
    ld a3, 0(a1)
    li a2, -193                           // ~(A|D) low bits
    and a3, a3, a2
    sd a3, 0(a1)
    sfence.vma
    li a1, VA_AD
    ld a3, 0(a1)
    li a2, 0xAD001
    bne a3, a2, fail_s
    li a1, PGL0 + 4 * 8
    ld a3, 0(a1)
    andi a3, a3, 0xC0
    li a2, 0x40
    bne a3, a2, fail_s
    // 10: SFENCE staleness: remap VA_A, stale until sfence.
    li t0, 10
    li a1, VA_A
    ld a3, 0(a1)                          // re-warm after test 9 sfence
    li a2, 0xA001
    bne a3, a2, fail_s
    li a1, 0x185000
    li a2, 0xB002
    sd a2, 0(a1)
    li a1, PGL0
    li a3, 0x185000
    srli a3, a3, 2
    ori a3, a3, 0xC7
    sd a3, 0(a1)
    li a1, VA_A
    ld a3, 0(a1)
    li a2, 0xA001
    bne a3, a2, fail_s                    // stale TLB entry
    sfence.vma
    li a1, VA_A
    ld a3, 0(a1)
    li a2, 0xB002
    bne a3, a2, fail_s
    // 11: Svnapot 64K page.
    li t0, 11
    li a1, VA_NAP + 0x3008
    li a2, 0x9A90
    sd a2, 0(a1)
    li a1, 0x193008
    ld a3, 0(a1)
    bne a3, a2, fail_s
    li a1, VA_NAP + 0x10000               // past the 64K: unmapped
    ld a3, 0(a1)
    la a1, s_cause
    ld a3, 0(a1)
    li a2, 13
    bne a3, a2, fail_s
    // 12: 2M superpage + its 4K alias see the same PA.
    li t0, 12
    li a1, VA_SUP + 4
    li a2, 0x5009
    sw a2, 0(a1)
    li a1, VA_ALS + 4
    lw a3, 0(a1)
    bne a3, a2, fail_s
    // 13: non-canonical VA faults (13).
    li t0, 13
    li a1, 1
    slli a1, a1, 39
    ld a3, 0(a1)
    la a1, s_cause
    ld a3, 0(a1)
    li a2, 13
    bne a3, a2, fail_s
    // Hand back to M for the MPRV checks.
    la a1, m_main
    la a2, resume_addr
    sd a1, 0(a2)
    ecall                                 // cause 9 -> M handler
    j fail_s

u_code:
    li a1, VA_D
    ld a3, 0x200(a1)
    li a2, 0xD001
    bne a3, a2, 1f
    li a2, 0xD00D
    sd a2, 0x208(a1)
1:  li a1, VA_A                           // S page: faults, S skips it
    ld a3, 0(a1)
    ecall                                 // escapes to s_after_u
1:  j 1b
u_code_end:

// ---- M-mode MPRV checks -----------------------------------------
m_main:
    li t0, 14
    // MPP=S, MPRV=1: data accesses translate as S.
    csrr a1, mstatus
    li a2, (3 << 11)
    not a2, a2
    and a1, a1, a2
    li a2, (1 << 11) | (1 << 17)
    or a1, a1, a2
    csrw mstatus, a1
    li a1, VA_A
    ld a3, 0(a1)
    li a2, 0xB002
    bne a3, a2, fail
    li a2, 0xC003
    sd a2, 0(a1)
    // U page with SUM=0 faults to M (13), handler skips the load.
    li a1, VA_D
    ld a3, 0(a1)
    la a1, saved_cause
    ld a3, 0(a1)
    li a2, 13
    bne a3, a2, fail
    // MPRV off: the store above must be visible at the PA.
    li a1, (1 << 17)
    csrc mstatus, a1
    li a1, 0x185000
    ld a3, 0(a1)
    li a2, 0xC003
    bne a3, a2, fail

pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail_s:                                   // escape to M to report
    la a1, m_fail
    la a2, resume_addr
    sd a1, 0(a2)
    ecall
1:  j 1b
m_fail:
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

// ---- Handlers ----------------------------------------------------
handler_m:
    csrrw sp, mscratch, sp
    sd t0, 0(sp)
    sd t1, 8(sp)
    sd t2, 16(sp)
    sd a0, 24(sp)
    sd a1, 32(sp)
    csrr t1, mcause
    la t2, saved_cause
    sd t1, 0(t2)
    csrr t1, mtval
    la t2, saved_tval
    sd t1, 0(t2)
    la t2, resume_addr
    ld t1, 0(t2)
    beqz t1, 1f
    sd x0, 0(t2)
    csrw mepc, t1
    li t1, (3 << 11)                      // land back in M
    csrs mstatus, t1
    j 2f
1:  csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
2:  ld t0, 0(sp)
    ld t1, 8(sp)
    ld t2, 16(sp)
    ld a0, 24(sp)
    ld a1, 32(sp)
    csrrw sp, mscratch, sp
    mret

handler_s:
    csrrw sp, sscratch, sp
    sd t0, 0(sp)
    sd t1, 8(sp)
    sd t2, 16(sp)
    sd a1, 24(sp)
    csrr t1, scause
    la t2, s_cause
    sd t1, 0(t2)
    csrr t1, stval
    la t2, s_tval
    sd t1, 0(t2)
    csrr t1, scause
    li t2, 8
    beq t1, t2, 3f                        // ecall from U: escape to S
    csrr t2, sstatus                      // resume override is for
    andi t2, t2, 256                      // S-mode traps only (SPP=1);
    beqz t2, 1f                           // U faults just skip +4
    la t2, s_resume
    ld t1, 0(t2)
    beqz t1, 1f
    sd x0, 0(t2)
    csrw sepc, t1
    j 2f
1:  csrr t1, sepc
    addi t1, t1, 4
    csrw sepc, t1
    j 2f
3:  la t2, s_resume
    ld t1, 0(t2)
    sd x0, 0(t2)
    csrw sepc, t1
    li t1, (1 << 8)                       // SPP = S for the sret
    csrs sstatus, t1
2:  ld t0, 0(sp)
    ld t1, 8(sp)
    ld t2, 16(sp)
    ld a1, 24(sp)
    csrrw sp, sscratch, sp
    sret

    .data
    .align 3
saved_cause: .quad 0
saved_tval:  .quad 0
resume_addr: .quad 0
s_cause:     .quad 0
s_tval:      .quad 0
s_resume:    .quad 0
    .align 4
main_stack:  .skip 4096
main_stack_top:
trap_stack:  .skip 4096
trap_stack_top:
u_stack:     .skip 1024
u_stack_top:
