// Hypervisor stage 7a directed test (issue #22): M -> HS ->
// VS -> VU transitions with Bare vsatp/hgatp, guest ecalls,
// virtual-instruction exceptions, and HS/VS trap delegation.
// Two-stage translation is stage 7b and is not exercised here.
// Convention: t0 = test number, exit store 0 = pass.
    .option norvc
    .text
    .globl _start
_start:
    la sp, main_stack_top
    la t1, trap_stack_top
    addi t1, t1, -64
    csrw mscratch, t1
    la t1, handler_m
    csrw mtvec, t1
    // PMP catch-all RWX so HS/VS/VU can use all of RAM.
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1

    li t0, 1
    csrr a1, misa
    li a2, (1 << 7)
    and a1, a1, a2
    beqz a1, fail                  // misa.H

    // Delegate U/VS ecalls and virtual-instruction to HS.
    li t1, (1 << 8) | (1 << 10) | (1 << 22)
    csrw medeleg, t1
    csrw mideleg, x0
    // Drop to HS.
    la t1, hs_code
    csrw mepc, t1
    li t1, (1 << 11) | (1 << 7)    // MPP=S, MPIE=1
    csrs mstatus, t1
    mret

hs_code:
    li t0, 2
    la t1, trap_stack_top
    addi t1, t1, -128
    csrw sscratch, t1
    la t1, handler_hs
    csrw stvec, t1
    // Guest CSRs are directly accessible from HS.
    la t1, handler_vs
    csrw 0x205, t1                 // vstvec
    la t1, guest_trap_stack_top
    addi t1, t1, -64
    csrw 0x240, t1                 // vsscratch
    csrw 0x200, x0                 // vsstatus (SPP VU by default)
    csrw 0x280, x0                 // vsatp Bare
    csrw 0x680, x0                 // hgatp Bare
    li t1, (1 << 8)
    csrw 0x602, t1                 // hedeleg: VU ecall -> VS
    csrw hcounteren, 0x7
    // Enter VS.
    li t1, (1 << 7)
    csrw 0x600, t1                 // hstatus.SPV = 1
    li t1, (1 << 8)
    csrs sstatus, t1               // SPP = VS
    la t1, guest_vs
    csrw sepc, t1
    sret

hs_finish:
    li t0, 20
    la a1, hs_count
    ld a1, 0(a1)
    li a2, 3
    bne a1, a2, fail
    la a1, hs_causes
    ld a2, 0(a1)
    li a3, 10
    bne a2, a3, fail               // ecall from VS
    ld a2, 8(a1)
    li a3, 22
    bne a2, a3, fail               // direct H CSR in VS
    ld a2, 16(a1)
    bne a2, a3, fail               // S CSR in VU
    li t0, 21
    csrr a1, 0x240                 // vsscratch written via sscratch
    li a2, 0x00c0ffee
    bne a1, a2, fail
    li t0, 22
    la a1, guest_vs_flag
    ld a1, 0(a1)
    li a2, 0x115
    bne a1, a2, fail
    la a1, guest_vu_flag
    ld a1, 0(a1)
    li a2, 0x116
    bne a1, a2, fail
    la a1, guest_handled
    ld a1, 0(a1)
    li a2, 1
    bne a1, a2, fail
    j pass

guest_vs:
    li a0, 0x115
    la a1, guest_vs_flag
    sd a0, 0(a1)
    li a0, 0x00c0ffee
    csrw sscratch, a0              // substituted vsscratch
    ecall                          // cause 10 -> HS
    csrr a0, 0x600                 // hstatus in VS: virtual instr
    csrw sstatus, x0               // vsstatus.SPP = VU
    la a0, guest_vu
    csrw sepc, a0                  // substituted vsepc
    sret

guest_vu:
    li a0, 0x116
    la a1, guest_vu_flag
    sd a0, 0(a1)
    ecall                          // cause 8 -> VS handler
    csrr a0, sstatus               // virtual instr -> HS (final)
1:  j 1b

// HS trap handler: records scause per visit; resumes guest
// after calls 1-2 and exits the VM on the third.
handler_hs:
    csrrw sp, sscratch, sp
    sd t0, 0(sp)
    sd t1, 8(sp)
    sd t2, 16(sp)
    sd a0, 24(sp)
    la t2, hs_count
    ld t1, 0(t2)
    la a0, hs_causes
    slli t1, t1, 3
    add a0, a0, t1
    csrr t1, scause
    sd t1, 0(a0)
    la t2, hs_count
    ld t1, 0(t2)
    addi t1, t1, 1
    sd t1, 0(t2)
    li a0, 3
    beq t1, a0, 1f
    csrr t1, sepc
    addi t1, t1, 4
    csrw sepc, t1
    j 2f
1:  la t1, hs_finish
    csrw sepc, t1
    li t1, (1 << 7)
    csrc 0x600, t1                 // hstatus.SPV = 0 (return to HS)
    li t1, (1 << 8)
    csrs sstatus, t1               // SPP = S
2:  ld t0, 0(sp)
    ld t1, 8(sp)
    ld t2, 16(sp)
    ld a0, 24(sp)
    csrrw sp, sscratch, sp
    sret

// VS trap handler for the VU ecall. Uses the inherited guest
// stack (vsscratch holds the substitution marker checked by HS).
handler_vs:
    addi sp, sp, -32
    sd t0, 0(sp)
    sd t1, 8(sp)
    sd t2, 16(sp)
    la t2, guest_handled
    li t1, 1
    sd t1, 0(t2)
    csrr t1, sepc
    addi t1, t1, 4
    csrw sepc, t1
    ld t0, 0(sp)
    ld t1, 8(sp)
    ld t2, 16(sp)
    addi sp, sp, 32
    sret

handler_m:                         // no trap should land in M
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
hs_count:     .dword 0
hs_causes:    .dword 0, 0, 0
guest_vs_flag: .dword 0
guest_vu_flag: .dword 0
guest_handled: .dword 0
    .skip 512
main_stack_top:
    .skip 512
trap_stack_top:
    .skip 512
guest_trap_stack_top:
