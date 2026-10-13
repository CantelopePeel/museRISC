// Directed RV64M tests (issue #18 stage 2a). Same harness
// convention as rv64i_directed.S: t0 = test number, exit store 0.
    .option norvc
    .text
    .globl _start
_start:
    // 1: MUL low half and MULH across sign quadrants
    li t0, 1
    li a0, -3
    li a1, 7
    mul a2, a0, a1         // -21
    li a3, -21
    bne a2, a3, fail
    mulh a2, a0, a1        // high of -21 = -1
    li a3, -1
    bne a2, a3, fail
    li a0, -1
    li a1, -1
    mulh a2, a0, a1        // (-1)*(-1) = 1 -> high 0
    bne a2, x0, fail
    mulhu a2, a0, a1       // (2^64-1)^2 high = 2^64-2
    li a3, -2
    bne a2, a3, fail
    mulhsu a2, a0, a1      // (-1) * (2^64-1) = -(2^64-1) -> high -1
    li a3, -1
    bne a2, a3, fail

    // 2: MULH with a product that carries into the high word
    li t0, 2
    li a0, 0x100000000     // 2^32
    li a1, 0x100000000
    mulh a2, a0, a1        // 1
    li a3, 1
    bne a2, a3, fail
    mul a2, a0, a1         // low = 0
    bne a2, x0, fail

    // 3: DIV/REM sign quadrants (truncate toward zero,
    //    remainder takes the dividend's sign)
    li t0, 3
    li a0, -7
    li a1, 2
    div a2, a0, a1         // -3
    li a3, -3
    bne a2, a3, fail
    rem a2, a0, a1         // -1
    li a3, -1
    bne a2, a3, fail
    li a0, 7
    li a1, -2
    div a2, a0, a1         // -3
    li a3, -3
    bne a2, a3, fail
    rem a2, a0, a1         // +1
    li a3, 1
    bne a2, a3, fail
    divu a2, a0, a1        // 7 / (2^64-2) = 0
    bne a2, x0, fail
    remu a2, a0, a1        // 7
    li a3, 7
    bne a2, a3, fail

    // 4: division by zero (quotient all-ones, remainder = dividend)
    li t0, 4
    li a0, 42
    li a1, 0
    div a2, a0, a1
    li a3, -1
    bne a2, a3, fail
    divu a2, a0, a1
    li a3, -1
    bne a2, a3, fail
    rem a2, a0, a1
    li a3, 42
    bne a2, a3, fail
    remu a2, a0, a1
    li a3, 42
    bne a2, a3, fail
    li a0, -5
    rem a2, a0, a1         // dividend verbatim, sign kept
    li a3, -5
    bne a2, a3, fail

    // 5: signed overflow INT64_MIN / -1
    li t0, 5
    li a0, 0x8000000000000000
    li a1, -1
    div a2, a0, a1         // = INT64_MIN
    bne a2, a0, fail
    rem a2, a0, a1         // = 0
    bne a2, x0, fail

    // 6: MULW truncates to 32 bits and sign-extends
    li t0, 6
    li a0, 0x100000001
    li a1, 0x100000003
    mulw a2, a0, a1        // 1*3 = 3
    li a3, 3
    bne a2, a3, fail
    li a0, 0x40000000
    li a1, 4
    mulw a2, a0, a1        // 0x00000000 (overflow dropped) -> 0
    bne a2, x0, fail
    li a0, 0x7fffffff
    li a1, 2
    mulw a2, a0, a1        // 0xfffffffe -> -2
    li a3, -2
    bne a2, a3, fail

    // 7: DIVW/REMW/DIVUW/REMUW operate on 32-bit operands
    li t0, 7
    li a0, -7
    li a1, 2
    divw a2, a0, a1        // -3
    li a3, -3
    bne a2, a3, fail
    remw a2, a0, a1        // -1
    li a3, -1
    bne a2, a3, fail
    li a0, -1              // 0xffffffff... low32 = 4294967295
    li a1, 2
    divuw a2, a0, a1       // 2147483647
    li a3, 2147483647
    bne a2, a3, fail
    remuw a2, a0, a1       // 1
    li a3, 1
    bne a2, a3, fail

    // 8: W divide by zero and W signed overflow (INT32_MIN / -1)
    li t0, 8
    li a0, 123
    li a1, 0
    divw a2, a0, a1        // -1 (all ones, sign-extended)
    li a3, -1
    bne a2, a3, fail
    remw a2, a0, a1        // 123
    li a3, 123
    bne a2, a3, fail
    divuw a2, a0, a1       // -1
    li a3, -1
    bne a2, a3, fail
    li a0, -2147483648
    li a1, -1
    divw a2, a0, a1        // INT32_MIN sign-extended
    li a3, -2147483648
    bne a2, a3, fail
    remw a2, a0, a1        // 0
    bne a2, x0, fail

    // 9: bigger round trip: (a / b) * b + a %% b == a, mixed signs
    li t0, 9
    li a0, -1234567890123
    li a1, 98765
    div a2, a0, a1
    rem a3, a0, a1
    mul a2, a2, a1
    add a2, a2, a3
    bne a2, a0, fail
    li a0, 0xfedcba9876543210
    li a1, 0x1234567
    divu a2, a0, a1
    remu a3, a0, a1
    mul a2, a2, a1
    add a2, a2, a3
    bne a2, a0, fail

pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b
