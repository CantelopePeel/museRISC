// Directed RV64I tests for the stage-1 core (issue #18).
// Convention: t0 holds the current test number; failure jumps to
// `fail`, which stores t0 to the harness exit address; success
// stores 0. See tb/cpp/core_tb.cpp.
    .option norvc
    .text
    .globl _start
_start:
    // 1: ADDI + ADD
    li t0, 1
    li a0, 40
    addi a0, a0, 2
    li a1, 42
    bne a0, a1, fail
    add a0, a0, a1
    li a1, 84
    bne a0, a1, fail

    // 2: SUB with negative result, SLT vs SLTU sign handling
    li t0, 2
    li a0, 5
    li a1, 9
    sub a2, a0, a1
    li a3, -4
    bne a2, a3, fail
    slt a2, a2, x0
    li a3, 1
    bne a2, a3, fail
    sltu a2, a2, x0        // a2==1 unsigned < 0 is false
    bne a2, x0, fail
    slti a2, a3, -1        // 1 < -1 signed is false
    bne a2, x0, fail
    sltiu a2, a3, -1       // 1 < 0xfff... unsigned is true
    li a3, 1
    bne a2, a3, fail

    // 3: logic ops and immediate sign extension
    li t0, 3
    xori a0, x0, -1        // all ones
    li a1, -1
    bne a0, a1, fail
    andi a0, a0, 0x3c
    li a1, 0x3c
    bne a0, a1, fail
    ori a0, a0, 0x41
    li a1, 0x7d
    bne a0, a1, fail
    li a1, 0xff
    xor a0, a0, a1
    li a1, 0x82
    bne a0, a1, fail
    li a1, 0x0f
    and a0, a0, a1
    li a1, 0x02
    bne a0, a1, fail
    or a0, a0, a1
    li a1, 0x02
    bne a0, a1, fail

    // 4: shifts, including shift-amount masking and SRA sign fill
    li t0, 4
    li a0, 1
    slli a0, a0, 63        // 0x8000000000000000
    srai a1, a0, 63        // -1
    li a2, -1
    bne a1, a2, fail
    srli a1, a0, 63        // 1
    li a2, 1
    bne a1, a2, fail
    li a1, 65              // shift amount masks to 1
    sll a0, a2, a1         // 1 << 1 = 2
    li a2, 2
    bne a0, a2, fail
    li a0, -256
    li a1, 4
    sra a0, a0, a1         // -16
    li a2, -16
    bne a0, a2, fail
    srl a0, a0, a1         // logical: huge positive
    bgtz a0, 5f
    j fail
5:

    // 5: W variants truncate to 32 bits and sign-extend
    li t0, 5
    li a0, 0x7fffffff
    addiw a0, a0, 1        // wraps to 0x80000000 -> sign-extended
    li a1, -2147483648
    bne a0, a1, fail
    li a0, 0x100000001
    li a1, 0x1
    addw a0, a0, a1        // 0x00000001 + 1 = 2 (high bits dropped)
    li a1, 2
    bne a0, a1, fail
    li a0, -16
    sraiw a0, a0, 2        // -4
    li a1, -4
    bne a0, a1, fail
    li a0, 0x40000000
    slliw a0, a0, 1        // 0x80000000 -> negative when sign-extended
    li a1, -2147483648
    bne a0, a1, fail
    li a0, 5
    li a1, 9
    subw a0, a0, a1
    li a1, -4
    bne a0, a1, fail
    li a0, -1
    srliw a0, a0, 28       // 0xf
    li a1, 15
    bne a0, a1, fail

    // 6: LUI (with sign extension of the 32-bit result)
    li t0, 6
    lui a0, 0x80000
    li a1, 0xffffffff80000000
    bne a0, a1, fail
    lui a0, 0x7ffff
    li a1, 0x7ffff000
    bne a0, a1, fail

    // 7: AUIPC-semantics by loading a known data word pc-relative
    li t0, 7
    la a0, magic           // auipc+addi pair
    ld a0, 0(a0)
    li a1, 0x1122334455667788
    bne a0, a1, fail

    // 8: JAL skips, JALR call/return through ra
    li t0, 8
    li a0, 0
    jal x0, 1f
    li a0, 1               // skipped
1:  bne a0, x0, fail
    jal ra, func8
    li a1, 77
    bne a0, a1, fail
    j 2f
func8:
    li a0, 77
    jalr x0, 0(ra)
2:

    // 9: branches, all six conditions, taken and not taken
    li t0, 9
    li a0, -1
    li a1, 1
    blt a0, a1, 1f
    j fail
1:  bltu a0, a1, fail      // 0xffff.. < 1 unsigned is false
    bge a1, a0, 1f
    j fail
1:  bgeu a1, a0, fail
    beq a0, a0, 1f
    j fail
1:  beq a0, a1, fail
    bne a0, a1, 1f
    j fail
1:  bne a0, a0, fail
    // loop: sum 1..10 = 55 via backward branch
    li a0, 0
    li a1, 10
1:  add a0, a0, a1
    addi a1, a1, -1
    bnez a1, 1b
    li a1, 55
    bne a0, a1, fail

    // 10: stores then loads of every size, sign/zero extension
    li t0, 10
    la a0, scratch
    li a1, 0x1122334455667788
    sd a1, 0(a0)
    lb a2, 0(a0)
    li a3, -120            // 0x88 sign-extended
    bne a2, a3, fail
    lbu a2, 0(a0)
    li a3, 0x88
    bne a2, a3, fail
    lh a2, 0(a0)
    li a3, 0x7788
    bne a2, a3, fail
    lh a2, 6(a0)
    li a3, 0x1122
    bne a2, a3, fail
    lw a2, 4(a0)
    li a3, 0x11223344
    bne a2, a3, fail
    lwu a2, 0(a0)
    li a3, 0x55667788
    bne a2, a3, fail
    ld a2, 0(a0)
    bne a2, a1, fail
    sb x0, 1(a0)           // clear byte 1 (was 0x77)
    lbu a2, 1(a0)
    bne a2, x0, fail
    li a2, -1
    sh a2, 2(a0)           // bytes 2..3 = 0xffff
    lhu a2, 2(a0)
    li a3, 0xffff
    bne a2, a3, fail
    sw x0, 4(a0)           // clear high word
    lw a2, 4(a0)
    bne a2, x0, fail
    lh a2, 0(a0)           // low half now: byte0=0x88 byte1=0 -> 0x0088
    li a3, 0x88
    bne a2, a3, fail

    // 11: x0 is hardwired to zero
    li t0, 11
    addi x0, x0, 5
    addi a0, x0, 0
    bne a0, x0, fail
    li x0, 123
    bne x0, zero, fail

    // 12: FENCE executes as a NOP
    li t0, 12
    fence
    fence.i
    li a0, 3
    li a1, 3
    bne a0, a1, fail

    // 13: AUIPC is PC-relative (explicit auipc, not the la pseudo-op;
    // each check re-anchors with jal so no PC arithmetic is hand-counted)
    li t0, 13
    jal a1, 1f             // a1 = address of the auipc below
1:  auipc a0, 0            // a0 = its own PC == a1
    bne a0, a1, fail
    jal a1, 1f
1:  auipc a0, 1            // a0 = a1 + 0x1000
    li a2, 4096
    add a2, a1, a2
    bne a0, a2, fail
    jal a1, 1f
1:  auipc a0, 0xfffff      // imm_u sign-extends: a0 = a1 - 0x1000
    li a2, -4096
    add a2, a1, a2
    bne a0, a2, fail

    // 14: load/store at a high RAM address (upper address bits)
    li t0, 14
    li a0, 0x800000
    li a1, 0xfedcba9876543210
    sd a1, 0(a0)
    ld a2, 0(a0)
    bne a2, a1, fail
    li a4, 0x801000
    sw a1, 0(a4)
    lwu a2, 0(a4)
    li a3, 0x76543210
    bne a2, a3, fail

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
magic:   .dword 0x1122334455667788
scratch: .dword 0
