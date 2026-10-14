// Directed F+D tests (issue #18 stage 4b): pipeline
// integration (FS-off illegal, forwarding incl. FMA rs3,
// load-use stalls, store-data path), conversions, flags,
// rounding modes, NaN-boxing. Bit-exactness of arithmetic
// itself is covered by the FPU unit TB vs SoftFloat.
// t0 = test number; exit store 0 = pass.
    .option norvc
    .text
    .globl _start
_start:
    // ---- 1: FS=Off at reset => FP op is illegal ----------
    li t0, 1
    la t1, handler
    csrw mtvec, t1
    li s0, 0                  // trap counter (handler bumps)
    fadd.d ft0, ft0, ft0      // must trap (cause 2)
    li t1, 1
    bne s0, t1, fail
    // enable FP: FS = Initial (01)
    li t1, (1 << 13)
    csrs mstatus, t1

    // ---- 2: D arithmetic chain (fwd pressure) -------------
    li t0, 2
    li a0, 0x3FF8000000000000 // 1.5
    fmv.d.x ft0, a0
    li a0, 0x4002000000000000 // 2.25
    fmv.d.x ft1, a0
    fadd.d ft2, ft0, ft1      // 3.75
    fmv.x.d a1, ft2
    li a2, 0x400E000000000000
    bne a1, a2, fail
    fmul.d ft3, ft0, ft1      // 3.375
    fmv.x.d a1, ft3
    li a2, 0x400B000000000000
    bne a1, a2, fail
    fdiv.d ft4, ft2, ft0      // 2.5 (ft2 via fwd)
    fmv.x.d a1, ft4
    li a2, 0x4004000000000000
    bne a1, a2, fail
    fsqrt.d ft5, ft1          // 1.5
    fmv.x.d a1, ft5
    li a2, 0x3FF8000000000000
    bne a1, a2, fail

    // ---- 3: FMA incl. rs3 forwarding -----------------------
    li t0, 3
    li a0, 0x3FE4000000000000 // 0.625
    fmv.d.x ft6, a0
    fmadd.d ft7, ft0, ft1, ft6   // 1.5*2.25+0.625 = 4.0
    fmv.x.d a1, ft7
    li a2, 0x4010000000000000
    bne a1, a2, fail
    fnmsub.d ft7, ft0, ft1, ft6  // -(1.5*2.25)+0.625 = -2.75
    fmv.x.d a1, ft7
    li a2, 0xC006000000000000
    bne a1, a2, fail

    // ---- 4: loads/stores + load-use stall ------------------
    li t0, 4
    la a3, fdata
    fld ft0, 0(a3)            // 1.5 (double)
    fadd.d ft0, ft0, ft0      // 3.0 immediately (stall path)
    fsd ft0, 16(a3)           // store via EX fwd
    ld a1, 16(a3)
    li a2, 0x4008000000000000
    bne a1, a2, fail
    flw ft1, 8(a3)            // 2.25f
    fadd.s ft1, ft1, ft1      // 4.5f
    fsw ft1, 24(a3)
    lw a1, 24(a3)
    li a2, 0x40900000
    bne a1, a2, fail

    // ---- 5: conversions + rounding modes -------------------
    li t0, 5
    li a0, 0xC006000000000000 // -2.75
    fmv.d.x ft0, a0
    fcvt.w.d a1, ft0          // RNE -> -3
    li a2, -3
    bne a1, a2, fail
    fcvt.w.d a1, ft0, rtz     // -> -2
    li a2, -2
    bne a1, a2, fail
    li a0, 42
    fcvt.d.l ft1, a0
    fmv.x.d a1, ft1
    li a2, 0x4045000000000000 // 42.0
    bne a1, a2, fail
    li a0, 0x3FF199999999999A // 1.1
    fmv.d.x ft2, a0
    fcvt.s.d ft3, ft2
    fmv.x.w a1, ft3
    li a2, 0x3F8CCCCD          // 1.1f
    bne a1, a2, fail
    fcvt.d.s ft4, ft3         // back to double(1.1f)
    fcvt.l.d a1, ft4          // 1

    // ---- 6: flags: NX set above, DZ here -------------------
    li t0, 6
    frflags a1
    andi a1, a1, 0x01         // NX from fcvt.s.d (1.1)
    beqz a1, fail
    fsflags zero
    li a0, 0x3FF0000000000000 // 1.0
    fmv.d.x ft0, a0
    fmv.d.x ft1, zero         // +0.0
    fdiv.d ft2, ft0, ft1      // +inf, DZ
    fmv.x.d a1, ft2
    li a2, 0x7FF0000000000000
    bne a1, a2, fail
    frflags a1
    li a2, 0x08               // DZ only
    bne a1, a2, fail

    // ---- 7: compares / class / min-max / sgnj --------------
    li t0, 7
    fclass.d a1, ft2          // +inf -> bit7
    li a2, 0x80
    bne a1, a2, fail
    li a0, 0xBFF8000000000000 // -1.5
    fmv.d.x ft3, a0
    flt.d a1, ft3, ft0        // -1.5 < 1.0 -> 1
    li a2, 1
    bne a1, a2, fail
    feq.d a1, ft3, ft0
    bnez a1, fail
    fmin.d ft4, ft3, ft0      // -1.5
    fmv.x.d a1, ft4
    li a2, 0xBFF8000000000000
    bne a1, a2, fail
    fsgnjn.d ft4, ft0, ft3    // |ft0| with sign ~sign(ft3) = +
    fmv.x.d a1, ft4
    li a2, 0x3FF0000000000000
    bne a1, a2, fail

    // ---- 8: NaN-boxing -------------------------------------
    li t0, 8
    li a0, 0xDEAD00003F800000 // improperly boxed 1.0f
    fmv.d.x ft0, a0           // raw write into the freg
    fadd.s ft1, ft0, ft0      // source unboxed -> canonical NaN
    fmv.x.w a1, ft1
    li a2, 0x7FC00000
    bne a1, a2, fail
    li a0, 0xBF800000         // -1.0f
    fmv.w.x ft2, a0
    fmv.x.w a1, ft2           // must sign-extend
    li a2, 0xFFFFFFFFBF800000
    bne a1, a2, fail

    // ---- 9: FS reads back Dirty, SD set --------------------
    li t0, 9
    csrr a1, mstatus
    li a2, (3 << 13)
    and a1, a1, a2
    bne a1, a2, fail
    csrr a1, mstatus
    bltz a1, 1f               // SD = bit63
    j fail
1:
    // ---- 10: frm dynamic rounding (RTZ) --------------------
    li t0, 10
    csrw frm, zero            // will overwrite below
    li a0, 1
    frrm a1
    bnez a1, fail             // old frm was 0 (RNE)
    li a0, 0xBFFF333333333333 // -1.95 approx
    // use exact -1.75:
    li a0, 0xBFFC000000000000
    fmv.d.x ft0, a0
    li a0, 1                  // RTZ
    fsrm a0
    fcvt.l.d a1, ft0, dyn     // -1 under RTZ
    li a2, -1
    bne a1, a2, fail
    fsrm zero                 // back to RNE
    fcvt.l.d a1, ft0, dyn     // -2 under RNE
    li a2, -2
    bne a1, a2, fail

pass:
    li t1, 0x10000000
    li t2, 0
    sd t2, 0(t1)
    j pass
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
    j fail

handler:
    csrr t3, mcause
    li t4, 2
    bne t3, t4, fail
    addi s0, s0, 1
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret

    .data
    .balign 8
fdata:
    .dword 0x3FF8000000000000  // 1.5
    .word  0x40100000          // 2.25f at offset 8
    .word  0
    .dword 0                   // store target (16)
    .word  0                   // store target (24)
