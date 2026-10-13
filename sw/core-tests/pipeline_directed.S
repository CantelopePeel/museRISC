// Pipeline hazard tests (issue #18 stage 2b). Each group targets a
// specific forwarding / stall / flush path of the 5-stage core.
// Convention as rv64i_directed.S: t0 = test number.
    .option norvc
    .text
    .globl _start
_start:
    // 1: back-to-back dependent ALU ops (EX/MEM forwarding chain)
    li t0, 1
    li a0, 1
    addi a0, a0, 1
    add a0, a0, a0
    add a0, a0, a0
    addi a0, a0, -8
    bne a0, x0, fail       // ((1+1)*2*2)-8 = 0

    // 2: distance-2 dependency (MEM/WB forwarding)
    li t0, 2
    li a0, 10
    li a1, 99
    addi a0, a0, 1         // consumer two behind the first addi
    li a1, 11
    bne a0, a1, fail

    // 3: distance-3 dependency (producer in WB while consumer in ID)
    li t0, 3
    li a0, 20
    nop
    nop
    addi a0, a0, 22
    li a1, 42
    bne a0, a1, fail

    // 4: load-use: dependent ALU, branch, and address chain
    li t0, 4
    la a0, magic
    ld a1, 0(a0)
    addi a1, a1, 1         // immediate use of load result (stall)
    li a2, 0x1122334455667789
    bne a1, a2, fail
    ld a1, 0(a0)
    beq a1, a2, fail       // not equal: magic vs magic+1
    addi a1, a1, 1
    bne a1, a2, fail
    la a0, ptrtab
    ld a0, 0(a0)           // load a pointer...
    ld a1, 0(a0)           // ...and dereference it immediately
    li a2, 0x1122334455667788
    bne a1, a2, fail

    // 5: store data and store address from just-produced values
    li t0, 5
    la a0, scratch
    la a1, magic
    ld a1, 0(a1)
    sd a1, 0(a0)           // store data is the load result (stall)
    ld a2, 0(a0)
    li a3, 0x1122334455667788
    bne a2, a3, fail
    la a1, scratch
    addi a1, a1, 8         // just-computed store address
    li a2, 555
    sd a2, 0(a1)
    ld a3, 8(a0)
    li a4, 555
    bne a3, a4, fail

    // 6: taken branch flushes the fall-through instructions:
    //    neither the register write nor the store may happen
    li t0, 6
    la a0, scratch
    sd x0, 16(a0)
    li a1, 1
    li a2, 777
    beq a1, a1, 1f
    li a2, 888             // flushed
    sd a2, 16(a0)          // flushed
1:  li a3, 777
    bne a2, a3, fail
    ld a3, 16(a0)
    bne a3, x0, fail

    // 7: JALR target from just-computed and just-loaded values
    li t0, 7
    la a0, jal_mid
    jalr x0, 0(a0)         // target produced by la (auipc+addi)
    j fail
jal_mid:
    la a0, ptrtab2
    ld a0, 0(a0)           // load the target address
    jalr x0, 0(a0)         // load-use on the jump target
    j fail
jal_cont:
    li a1, 1
    li a2, 1
    bne a1, a2, fail

    // 8: mul/div results feed dependent ops immediately
    li t0, 8
    li a0, 6
    li a1, 7
    mul a0, a0, a1         // 42
    addi a0, a0, -42
    bne a0, x0, fail
    li a0, 100
    li a1, 7
    div a0, a0, a1         // 14
    mul a0, a0, a1         // 98
    li a2, 98
    bne a0, a2, fail

    // 9: writes to x0 never forward (x0 stays zero)
    li t0, 9
    li a0, 5
    addi x0, a0, 100       // rd=x0: discarded, must not forward
    addi a1, x0, 1
    li a2, 1
    bne a1, a2, fail
    add x0, a0, a0
    add a1, x0, a2
    li a2, 1
    bne a1, a2, fail

    // 10: branch on a just-loaded value (load-use into EX compare)
    li t0, 10
    la a0, scratch
    li a1, 1
    sd a1, 24(a0)
    ld a2, 24(a0)
    bnez a2, 1f
    j fail
1:  li a1, 1
    bne a2, a1, fail

    // 11: tight loop with dependent accumulate (forward every iter)
    li t0, 11
    li a0, 0
    li a1, 100
1:  add a0, a0, a1
    addi a1, a1, -1
    bnez a1, 1b
    li a2, 5050
    bne a0, a2, fail

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
ptrtab:  .dword magic
ptrtab2: .dword target2
scratch: .dword 0, 0, 0, 0
    .text
target2:
    j jal_cont
