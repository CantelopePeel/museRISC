// Vector stage 8a directed test (issue #23): vsetvl family
// and VLMAX/vill semantics, mstatus.VS gating, vmv moves,
// and the first integer ALU classes at several SEW/LMUL
// settings, including a masked-off element. Vector memory
// instructions are stage 8b and are not exercised here.
// Convention: t0 = test number, exit store 0 = pass.
    .option norvc
    .option arch, +v
    .text
    .globl _start
_start:
    la sp, stack_top
    la t1, handler_m
    csrw mtvec, t1
    la t1, trap_stack_top
    addi t1, t1, -64
    csrw mscratch, t1

    // 1: vector op with VS=Off traps as illegal (cause 2).
    li t0, 1
    vsetvli a0, a1, e64, m1, ta, ma
    la a1, trap_cause
    ld a1, 0(a1)
    li a2, 2
    bne a1, a2, fail

    // Enable vector state (VS=Initial).
    li t1, (1 << 9)
    csrs mstatus, t1

    // 2: vsetvli computes VLMAX-capped vl: e64/m8 -> 64.
    li t0, 2
    li a1, 100
    vsetvli a0, a1, e64, m8, ta, ma
    li a2, 64
    bne a0, a2, fail
    csrr a1, vl
    bne a1, a2, fail
    csrr a1, vtype
    li a2, 0xdb                    // vma|vta|e64|m8
    bne a1, a2, fail
    csrr a1, vlenb
    li a2, 64
    bne a1, a2, fail

    // 3: vmv.v.x broadcast and vmv.x.s readback (e64).
    li t0, 3
    li a1, 0x1122334455667788
    vmv.v.x v8, a1                 // LMUL=8 group base
    vmv.x.s a0, v8
    bne a0, a1, fail

    // 4: e32/m2 integer ALU: 5 + 7 = 12, 5 - 2 = 3, shifts.
    li t0, 4
    li a1, 10
    vsetvli a0, a1, e32, m2, ta, ma
    li a2, 10
    bne a0, a2, fail
    vmv.v.i v4, 5
    vmv.v.i v6, 7
    vadd.vv v8, v4, v6
    vmv.x.s a0, v8
    li a2, 12
    bne a0, a2, fail
    li a1, 2
    vsub.vx v8, v4, a1
    vmv.x.s a0, v8
    li a2, 3
    bne a0, a2, fail
    vrsub.vi v8, v4, 9             // 9 - 5
    vmv.x.s a0, v8
    li a2, 4
    bne a0, a2, fail
    vsll.vi v8, v4, 3              // 5 << 3
    vmv.x.s a0, v8
    li a2, 40
    bne a0, a2, fail
    vmv.v.i v4, -16
    vsra.vi v8, v4, 2              // -16 >> 2 (arithmetic)
    vmv.x.s a0, v8
    li a2, -4
    bne a0, a2, fail
    vsrl.vi v8, v4, 2              // logical: 0x3ffffffc
    vmv.x.s a0, v8
    li a2, 0x3ffffffc
    bne a0, a2, fail

    // 5: vmv.s.x writes element 0 only; vmv.v.v copies.
    li t0, 5
    li a1, 64
    vsetvli a0, a1, e64, m1, ta, ma
    vmv.v.i v2, 7
    li a1, 99
    vmv.s.x v2, a1
    vmv.x.s a0, v2
    bne a0, a1, fail
    vmv.v.v v4, v2
    vmv.x.s a0, v4
    bne a0, a1, fail

    // 6: masked-off element 0 (v0 = 0, mu) keeps old vd.
    li t0, 6
    li a1, 8
    vsetvli a0, a1, e8, m1, ta, ma
    vmv.v.i v0, 0                  // all mask bits clear
    li a1, 4
    vsetvli a0, a1, e64, m1, tu, mu
    vmv.v.i v2, 11
    vmv.v.i v4, 3
    vadd.vv v2, v2, v4, v0.t       // masked off: stays 11
    vmv.x.s a0, v2
    li a2, 11
    bne a0, a2, fail

    // 7: vsetivli and fractional LMUL VLMAX (e64/mf2 -> 4).
    li t0, 7
    vsetivli a0, 7, e16, m1, ta, ma
    li a2, 7
    bne a0, a2, fail
    li a1, 100
    vsetvli a0, a1, e64, mf2, ta, ma
    li a2, 4
    bne a0, a2, fail

    // 8: illegal vtype via vsetvl sets vill and vl=0; a
    // following vector op traps; a valid vsetvli recovers.
    li t0, 8
    li a1, 10
    li a2, (4 << 3)                // vsew=4 -> SEW 128 > ELEN
    vsetvl a0, a1, a2
    bnez a0, fail
    csrr a1, vtype
    bgez a1, fail                  // vill is bit 63
    la a1, trap_cause
    sd x0, 0(a1)
    vadd.vv v2, v2, v2             // traps: vill
    la a1, trap_cause
    ld a1, 0(a1)
    li a2, 2
    bne a1, a2, fail
    li a1, 4
    vsetvli a0, a1, e64, m1, ta, ma
    li a2, 4
    bne a0, a2, fail
    vmv.v.i v2, 6
    vmv.x.s a0, v2
    li a2, 6
    bne a0, a2, fail
    j pass

handler_m:
    csrrw sp, mscratch, sp
    sd t1, 0(sp)
    sd t2, 8(sp)
    la t2, trap_cause
    csrr t1, mcause
    sd t1, 0(t2)
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    ld t1, 0(sp)
    ld t2, 8(sp)
    csrrw sp, mscratch, sp
    mret

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
trap_cause: .dword 0
    .skip 512
stack_top:
    .skip 512
trap_stack_top:
