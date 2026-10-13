# Directed misaligned-access probe for the CVA6 model (issue #20).
#
# Verifies the DUT config declaration MISALIGNED_LDST=false on the
# scalar cv64a6_imafdc_sv39 build: every misaligned scalar load/store
# (lh/lhu/lw/lwu/ld/sh/sw/sd, offsets 1..7) must trap with
# LD/ST_ADDR_MISALIGNED and, for stores, must not modify memory.
# Aligned controls must not trap. Halts via HTIF tohost like
# riscv-tests: write 1 on pass; on fail write 2*(case+2)+1.
#
# Cases are enumerated in CASES order below; the trap handler records
# mcause in s3 and skips the faulting instruction (mepc += 4; all
# probe instructions are 4-byte, .option norvc).
    .section .text.init
    .globl _start
    .option push
    .option norvc
_start:
    la t0, trap_handler
    csrw mtvec, t0
    li s1, 0              # case index
    la s0, buffer         # 64-byte aligned buffer

    # Fill buffer with a known pattern: byte i = i.
    li t1, 0
1:  sb t1, 0(s0)
    addi s0, s0, 1
    addi t1, t1, 1
    li t2, 64
    blt t1, t2, 1b
    la s0, buffer

    # Macro: expect_trap PROBE_INSN, expected_cause
    # Advances case index; s3=-1 sentinel reads as "no trap".
    .macro EXPECT_TRAP insn, cause
    li s3, -1
    \insn
    li t3, \cause
    bne s3, t3, fail
    addi s1, s1, 1
    .endm
    .macro EXPECT_OK insn
    li s3, -1
    \insn
    li t3, -1
    bne s3, t3, fail
    addi s1, s1, 1
    .endm

    # Aligned controls (must not trap) — 8 cases
    EXPECT_OK "lh a0, 0(s0)"
    EXPECT_OK "lhu a0, 2(s0)"
    EXPECT_OK "lw a0, 4(s0)"
    EXPECT_OK "lwu a0, 8(s0)"
    EXPECT_OK "ld a0, 16(s0)"
    EXPECT_OK "sh a0, 24(s0)"
    EXPECT_OK "sw a0, 28(s0)"
    EXPECT_OK "sd a0, 32(s0)"

    # Misaligned loads (cause 4) — offsets 1..7 as applicable
    EXPECT_TRAP "lh a0, 1(s0)", 4
    EXPECT_TRAP "lh a0, 3(s0)", 4
    EXPECT_TRAP "lhu a0, 5(s0)", 4
    EXPECT_TRAP "lhu a0, 7(s0)", 4
    EXPECT_TRAP "lw a0, 1(s0)", 4
    EXPECT_TRAP "lw a0, 2(s0)", 4
    EXPECT_TRAP "lw a0, 3(s0)", 4
    EXPECT_TRAP "lw a0, 6(s0)", 4
    EXPECT_TRAP "lwu a0, 9(s0)", 4
    EXPECT_TRAP "lwu a0, 10(s0)", 4
    EXPECT_TRAP "lwu a0, 11(s0)", 4
    EXPECT_TRAP "ld a0, 1(s0)", 4
    EXPECT_TRAP "ld a0, 2(s0)", 4
    EXPECT_TRAP "ld a0, 3(s0)", 4
    EXPECT_TRAP "ld a0, 4(s0)", 4
    EXPECT_TRAP "ld a0, 5(s0)", 4
    EXPECT_TRAP "ld a0, 6(s0)", 4
    EXPECT_TRAP "ld a0, 7(s0)", 4
    EXPECT_TRAP "ld a0, 63(s0)", 4

    # Misaligned stores (cause 6); a1 holds poison 0xEE bytes
    li a1, -1
    EXPECT_TRAP "sh a1, 1(s0)", 6
    EXPECT_TRAP "sh a1, 3(s0)", 6
    EXPECT_TRAP "sw a1, 1(s0)", 6
    EXPECT_TRAP "sw a1, 2(s0)", 6
    EXPECT_TRAP "sw a1, 3(s0)", 6
    EXPECT_TRAP "sw a1, 6(s0)", 6
    EXPECT_TRAP "sd a1, 1(s0)", 6
    EXPECT_TRAP "sd a1, 2(s0)", 6
    EXPECT_TRAP "sd a1, 3(s0)", 6
    EXPECT_TRAP "sd a1, 4(s0)", 6
    EXPECT_TRAP "sd a1, 5(s0)", 6
    EXPECT_TRAP "sd a1, 6(s0)", 6
    EXPECT_TRAP "sd a1, 7(s0)", 6
    EXPECT_TRAP "sd a1, 63(s0)", 6

    # FP misaligned (F/D enabled; causes 4/6) — needs FS on
    li t0, 0x2000
    csrs mstatus, t0
    EXPECT_TRAP "flw f0, 1(s0)", 4
    EXPECT_TRAP "flw f0, 2(s0)", 4
    EXPECT_TRAP "fld f0, 4(s0)", 4
    EXPECT_TRAP "fld f0, 7(s0)", 4
    EXPECT_TRAP "fsw f0, 1(s0)", 6
    EXPECT_TRAP "fsw f0, 2(s0)", 6
    EXPECT_TRAP "fsd f0, 4(s0)", 6
    EXPECT_TRAP "fsd f0, 7(s0)", 6

    # Misaligned atomics (LR cause is store-class 6 on CVA6; AMO 6)
    li s3, -1
    addi t4, s0, 2
    lr.w a0, (t4)
    li t3, 6
    bne s3, t3, fail
    addi s1, s1, 1
    li s3, -1
    addi t4, s0, 4
    lr.d a0, (t4)
    li t3, 6
    bne s3, t3, fail
    addi s1, s1, 1
    li s3, -1
    addi t4, s0, 1
    amoadd.w a0, a1, (t4)
    li t3, 6
    bne s3, t3, fail
    addi s1, s1, 1
    li s3, -1
    addi t4, s0, 4
    amoadd.d a0, a1, (t4)
    li t3, 6
    bne s3, t3, fail
    addi s1, s1, 1

    # Case count sanity: 8 aligned + 19 loads + 14 stores + 8 FP + 4 atomics
    li t3, 53
    bne s1, t3, fail_count

    # Memory integrity: trapping stores must not have written.
    # Bytes 0..15 must still equal their index (aligned-control
    # stores only touched 24..39; poison was all-ones).
    la s0, buffer
    li t1, 0
2:  lbu t4, 0(s0)
    bne t4, t1, fail_mem
    addi s0, s0, 1
    addi t1, t1, 1
    li t2, 16
    blt t1, t2, 2b

    li a0, 1
    la t0, tohost
    sw a0, 0(t0)
1:  j 1b
fail:                      # a0 = case+2
    addi a0, s1, 2
    j fail_write
fail_mem:                  # a0 = 2002 + byte index
    li a0, 2002
    add a0, a0, t1
    j fail_write
fail_count:                # a0 = 3002
    li a0, 3002
fail_write:
    slli a0, a0, 1
    ori a0, a0, 1
    la t0, tohost
    sw a0, 0(t0)
1:  j 1b
    .align 2
trap_handler:
    csrr s3, mcause
    csrr t5, mepc
    addi t5, t5, 4
    csrw mepc, t5
    mret
    .option pop
    .data
    .globl tohost
    .align 6
tohost: .dword 0
    .globl fromhost
    .align 6
fromhost: .dword 0
    .align 6
buffer: .space 128
