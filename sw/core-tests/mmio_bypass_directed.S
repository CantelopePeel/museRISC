// Directed uncached (I/O) access tests. core_tb maps a side-
// effect device at 0x2000_0000 outside the cacheable windows:
//   +0x00 R  returns how many times it has been read (post-inc)
//   +0x08 R  number of writes seen at +0x10
//   +0x10 W  write counter
// Every load/store to it must reach the bus exactly once, in
// program order, as a single beat (the harness fails the run on
// any burst or fetch into the device window). Also: code
// executed from uncached RAM (single-beat fetches), and a
// cacheable line next to I/O traffic stays coherent.
// t0 = test number; exit store 0 = pass.
    .option norvc
    .text
    .globl _start

.equ DEV, 0x20000000
.equ NC_CODE, 0x20010000     // uncached RAM in core_tb's map

_start:
    li s0, DEV
    // 1: two reads of the read counter see consecutive values
    //    (a cached copy would repeat the first).
    li t0, 1
    ld t1, 0(s0)
    ld t2, 0(s0)
    addi t1, t1, 1
    bne t1, t2, fail
    // Byte and word loads of the same register also count.
    lbu t3, 0(s0)
    lw t4, 0(s0)
    addi t2, t2, 1
    bne t3, t2, fail
    addi t2, t2, 1
    bne t4, t2, fail

    // 2: three stores of different widths all reach the device.
    li t0, 2
    ld t5, 8(s0)                 // writes so far (0)
    bnez t5, fail
    sd t1, 0x10(s0)
    sw t1, 0x10(s0)
    sb t1, 0x10(s0)
    ld t5, 8(s0)
    li t6, 3
    bne t5, t6, fail

    // 3: store then read-back ordering: a store followed by a
    //    dependent device read sees the store's effect.
    li t0, 3
    sd x0, 0x10(s0)
    ld t5, 8(s0)
    li t6, 4
    bne t5, t6, fail

    // 4: run code from uncached RAM (fetches bypass the I$).
    li t0, 4
    li t1, NC_CODE
    li t2, 0x06400513            // addi a0, x0, 100
    sw t2, 0(t1)
    li t2, 0x00150513            // addi a0, a0, 1
    sw t2, 4(t1)
    li t2, 0x00008067            // ret
    sw t2, 8(t1)
    fence.i
    jalr ra, 0(t1)
    li t3, 101
    bne a0, t3, fail
    // Uncached code changes are visible after FENCE.I too.
    li t2, 0x00250513            // addi a0, a0, 2
    sw t2, 4(t1)
    fence.i
    jalr ra, 0(t1)
    li t3, 102
    bne a0, t3, fail

    // 5: interleave cacheable stores/loads with device traffic.
    li t0, 5
    la s1, cached_buf
    li s2, 0
1:  ld t1, 0(s0)                 // device read (side effect)
    sd t1, 0(s1)
    sd x0, 0x10(s0)              // device write
    ld t2, 0(s1)
    bne t1, t2, fail
    addi s1, s1, 8
    addi s2, s2, 1
    li t3, 16
    blt s2, t3, 1b
    ld t5, 8(s0)
    li t6, 20                    // 4 + 16 writes
    bne t5, t6, fail

pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

    .data
    .balign 64
cached_buf: .skip 128
