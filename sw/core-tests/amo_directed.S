// Directed A-extension tests (issue #18 stage 4a): every AMO
// operation in both widths (result register = original value,
// memory = computed value), LR/SC success and the failure
// modes (no reservation, wrong address, double SC, intervening
// store), and atomic read-modify-write under forwarding
// pressure. t0 = test number; exit store 0 = pass.
    .option norvc
    .text
    .globl _start

// CHECK_AMO_D nmem, init, src, want_mem: rd must equal init.
.macro CHECK_AMO_D nmem, init, src, want
    li a2, \init
    sd a2, 0(a1)
    li a3, \src
    \nmem a4, a3, (a1)
    bne a4, a2, fail
    ld a4, 0(a1)
    li a2, \want
    bne a4, a2, fail
.endm
.macro CHECK_AMO_W nmem, init, src, want
    li a2, \init
    sw a2, 0(a1)
    li a3, \src
    \nmem a4, a3, (a1)
    sext.w a2, a2
    bne a4, a2, fail
    lw a4, 0(a1)
    li a2, \want
    sext.w a2, a2
    bne a4, a2, fail
.endm

_start:
    la a1, cell
    // 1: AMOADD/AMOSWAP both widths
    li t0, 1
    CHECK_AMO_D amoadd.d, 100, 23, 123
    CHECK_AMO_D amoswap.d, -7, 55, 55
    CHECK_AMO_W amoadd.w, 0x7fffffff, 1, 0x80000000
    CHECK_AMO_W amoswap.w, 0x12345678, -1, -1
    // 2: logic AMOs
    li t0, 2
    CHECK_AMO_D amoxor.d, 0xff00ff, 0x0f0f0f, 0xf00ff0
    CHECK_AMO_D amoor.d,  0xf000,   0x0ff0,   0xfff0
    CHECK_AMO_D amoand.d, 0xfff0,   0xff00,   0xff00
    CHECK_AMO_W amoxor.w, -1, 0x55555555, 0xaaaaaaaa
    CHECK_AMO_W amoor.w,  0x1010, 0x0101, 0x1111
    CHECK_AMO_W amoand.w, 0x1111, 0x1010, 0x1010
    // 3: min/max signed and unsigned
    li t0, 3
    CHECK_AMO_D amomin.d,  -5, 3,  -5
    CHECK_AMO_D amomin.d,   5, -3, -3
    CHECK_AMO_D amomax.d,  -5, 3,   3
    CHECK_AMO_D amominu.d, -5, 3,   3
    CHECK_AMO_D amomaxu.d, -5, 3,  -5
    CHECK_AMO_W amomin.w,  0x80000000, 0x7fffffff, 0x80000000
    CHECK_AMO_W amominu.w, 0x80000000, 0x7fffffff, 0x7fffffff
    CHECK_AMO_W amomaxu.w, 0x80000000, 0x7fffffff, 0x80000000
    CHECK_AMO_W amomax.w,  0x80000000, 0x7fffffff, 0x7fffffff
    // 4: LR/SC success (D and W); read-after-SC forwarding
    li t0, 4
    li a2, 41
    sd a2, 0(a1)
    lr.d a4, (a1)
    bne a4, a2, fail
    addi a3, a4, 1
    sc.d a5, a3, (a1)
    bnez a5, fail
    ld a4, 0(a1)
    li a2, 42
    bne a4, a2, fail
    li a2, 0x1000
    sw a2, 8(a1)
    addi t2, a1, 8
    lr.w a4, (t2)
    bne a4, a2, fail
    li a3, 0x2000
    sc.w a5, a3, (t2)
    bnez a5, fail
    lw a4, 8(a1)
    li a2, 0x2000
    bne a4, a2, fail
    // 5: SC failure modes: no LR, wrong address, double SC,
    // intervening store to the reserved granule
    li t0, 5
    li a3, 77
    sc.d a5, a3, (a1)               // no reservation
    beqz a5, fail
    lr.d a4, (a1)
    addi t2, a1, 8
    sc.d a5, a3, (t2)               // different address
    beqz a5, fail
    sc.d a5, a3, (a1)               // reservation consumed by SC
    beqz a5, fail
    lr.d a4, (a1)
    sd a3, 0(a1)                    // intervening store
    li a3, 78
    sc.d a5, a3, (a1)
    beqz a5, fail
    ld a4, 0(a1)                    // the intervening store won
    li a2, 77
    bne a4, a2, fail
    // 6: LR/SC update loop (atomic increment x10) with the
    // SC result feeding the branch immediately (forwarding)
    li t0, 6
    sd x0, 0(a1)
    li a6, 10
1:  lr.d a4, (a1)
    addi a4, a4, 1
    sc.d a5, a4, (a1)
    bnez a5, 1b
    addi a6, a6, -1
    bnez a6, 1b
    ld a4, 0(a1)
    li a2, 10
    bne a4, a2, fail
    // 7: back-to-back AMOs to the same cell (MEM forwarding
    // through memory, no bubbles required)
    li t0, 7
    li a2, 5
    sd a2, 0(a1)
    li a3, 3
    amoadd.d a4, a3, (a1)
    amoadd.d a5, a3, (a1)
    amoadd.d a6, a3, (a1)
    li a2, 5
    bne a4, a2, fail
    li a2, 8
    bne a5, a2, fail
    li a2, 11
    bne a6, a2, fail
    ld a4, 0(a1)
    li a2, 14
    bne a4, a2, fail

    // 8: LR immediately feeding SC's data operand (load-use
    // interlock on the SC rs2 — ACT PMPZalrsc caught this)
    li t0, 8
    li a2, 0x1234
    sd a2, 0(a1)
    lr.d a4, (a1)
    sc.d a5, a4, (a1)
    bnez a5, fail
    ld a4, 0(a1)
    bne a4, a2, fail
    li a2, 0x5678
    sw a2, 8(a1)
    addi t2, a1, 8
    lr.w a4, (t2)
    sc.w a5, a4, (t2)
    bnez a5, fail
    lw a4, 8(a1)
    bne a4, a2, fail

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
cell: .dword 0, 0
