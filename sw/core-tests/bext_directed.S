// Directed B/Zicond/scalar-crypto tests (issue #18 stage
// 4c). Per-op semantics are covered exhaustively by
// bext_tb.cpp vs its C++ golden; this file checks pipeline
// integration (decode, forwarding) and runs one full
// AES-128 encryption KAT (FIPS-197 vector) built from
// aes64es/esm + aes64ks1i/ks2 as an end-to-end proof.
// t0 = test number; exit store 0 = pass.
    .option norvc
    .text
    .globl _start
_start:
    // ---- 1: Zba address generation -----------------------
    li t0, 1
    li a1, 0x1234
    li a2, 0xFFFFF000         // sign-extended; .uw must zero it
    sext.w a2, a2
    add.uw a3, a2, a1         // 0xFFFFF000 + 0x1234 (zero-ext)
    li a4, 0x100001234 - 0x100000000 + 0x100000000
    // expected 0xFFFFF000 + 0x1234 = 0x1_0000_0234? compute:
    li a4, 0x100000234
    bne a3, a4, fail
    li a1, 5
    li a2, 100
    sh2add a3, a1, a2         // 120
    li a4, 120
    bne a3, a4, fail
    sh3add.uw a3, a2, a1      // (100<<3)+5 = 805
    li a4, 805
    bne a3, a4, fail
    slli.uw a3, a2, 4         // 1600
    li a4, 1600
    bne a3, a4, fail

    // ---- 2: Zbb logic/count/rotate -------------------------
    li t0, 2
    li a1, 0x00F00F00
    clz a3, a1                // 64-bit value: significant top
    li a4, 40                 // 0x00F00F00 = 2^23-ish top -> 40
    bne a3, a4, fail
    ctz a3, a1
    li a4, 8
    bne a3, a4, fail
    cpop a3, a1
    li a4, 8
    bne a3, a4, fail
    li a1, -5
    li a2, 7
    max a3, a1, a2
    bne a3, a2, fail
    minu a3, a1, a2
    bne a3, a2, fail
    li a1, 0x8000000000000001
    rori a3, a1, 1            // 0xC000000000000000
    li a4, 0xC000000000000000
    bne a3, a4, fail
    rol a3, a3, a2            // rol by 7 of 0xC000.. = 0x0000000000000060? use ror back
    li a1, 0x0123456789ABCDEF
    rev8 a3, a1
    li a4, 0xEFCDAB8967452301
    bne a3, a4, fail
    orc.b a3, a2              // a2=7 -> 0xFF
    li a4, 0xFF
    bne a3, a4, fail
    sext.b a3, a4             // 0xFF -> -1
    li a4, -1
    bne a3, a4, fail

    // ---- 3: Zbc carry-less multiply -------------------------
    li t0, 3
    li a1, 0xFF00FF00FF00FF01
    li a2, 0x0F0F0F0F0F0F0F0F
    clmul a3, a1, a2
    li a4, 0x0A0F0A0F0A0F0A0F
    bne a3, a4, fail
    clmulh a3, a1, a2
    li a4, 0x0500050005000500
    bne a3, a4, fail
    clmulr a3, a1, a2
    li a4, 0xA000A000A000A00
    bne a3, a4, fail

    // ---- 4: Zbs single-bit ----------------------------------
    li t0, 4
    li a1, 0
    bseti a1, a1, 17
    li a4, (1 << 17)
    bne a1, a4, fail
    binvi a1, a1, 17
    bnez a1, fail
    li a2, 63
    bset a1, a1, a2
    bexti a3, a1, 63
    li a4, 1
    bne a3, a4, fail
    bclr a1, a1, a2
    bnez a1, fail

    // ---- 5: Zicond + Zbkb pack/permute ----------------------
    li t0, 5
    li a1, 0xABCD
    li a2, 0
    czero.eqz a3, a1, a2
    bnez a3, fail
    czero.nez a3, a1, a2
    bne a3, a1, fail
    li a1, 0x1122334455667788
    li a2, 0x99AABBCCDDEEFF00
    pack a3, a1, a2           // {DDEEFF00, 55667788}
    li a4, 0xDDEEFF0055667788
    bne a3, a4, fail
    packh a3, a1, a2          // {00, 88}
    li a4, 0x0088
    bne a3, a4, fail
    brev8 a3, a2
    li a4, 0x9955DD33BB77FF00
    bne a3, a4, fail
    li a1, 0x0123456789ABCDEF
    li a2, 0x0706050403020100
    xperm8 a3, a1, a2         // identity permutation
    bne a3, a1, fail
    li a2, 0x0000000000000007
    xperm8 a3, a1, a2
    // byte0 <- a1.byte7 (0x01); bytes1..7 <- a1.byte0 (0xEF)
    li a4, 0xEFEFEFEFEFEFEF01
    bne a3, a4, fail
    li a2, 0xFEDCBA9876543210
    xperm4 a3, a1, a2         // idx nibbles 0..15 -> identity
    bne a3, a1, fail

    // ---- 6: SHA sigma/sum functions --------------------------
    li t0, 6
    li a1, 0xDEADBEEF
    sha256sig0 a3, a1
    li a4, 0xFFFFFFFFABD31B0B
    bne a3, a4, fail
    sha256sum1 a3, a1
    li a4, 0x345E14A3
    bne a3, a4, fail
    li a1, 0x0123456789ABCDEF
    sha512sig0 a3, a1
    li a4, 0x6F92C77C6C4F1AA1
    bne a3, a4, fail
    sha512sum1 a3, a1
    li a4, 0x7703112333475567
    bne a3, a4, fail

    // ---- 7: AES-128 encrypt KAT (FIPS-197) -------------------
    // key = 000102...0f, pt = 001122...ff (state byte i at
    // memory byte i, little-endian 64-bit halves).
    li t0, 7
    li s0, 0x7766554433221100   // state low  (rows of cols 0-1)
    li s1, 0xFFEEDDCCBBAA9988   // state high (cols 2-3)
    li a2, 0x0706050403020100   // key low  w0,w1
    li a3, 0x0F0E0D0C0B0A0908   // key high w2,w3
    xor s0, s0, a2
    xor s1, s1, a3
    // rounds 1..9
    .macro AES_ROUND rc
        aes64ks1i t1, a3, \rc
        aes64ks2 a2, t1, a2
        aes64ks2 a3, a2, a3
        aes64esm t2, s0, s1
        aes64esm s1, s1, s0
        mv s0, t2
        xor s0, s0, a2
        xor s1, s1, a3
    .endm
    AES_ROUND 0
    AES_ROUND 1
    AES_ROUND 2
    AES_ROUND 3
    AES_ROUND 4
    AES_ROUND 5
    AES_ROUND 6
    AES_ROUND 7
    AES_ROUND 8
    // final round (no MixColumns), rcon 9
    aes64ks1i t1, a3, 9
    aes64ks2 a2, t1, a2
    aes64ks2 a3, a2, a3
    aes64es t2, s0, s1
    aes64es s1, s1, s0
    mv s0, t2
    xor s0, s0, a2
    xor s1, s1, a3
    // expected ct = 69c4e0d86a7b0430d8cdb78070b4c55a
    li a4, 0x30197B6AD8E8C469   // low half: bytes of ct 0..7 LE
    // ct bytes: 69 c4 e0 d8 6a 7b 04 30 -> LE qword below
    li a4, 0x30047B6AD8E0C469
    bne s0, a4, fail
    li a4, 0x5AC5B47080B7CDD8   // high: d8 cd b7 80 70 b4 c5 5a
    bne s1, a4, fail

pass:
    li t1, 0x10000000
    li t2, 0
    sd t2, 0(t1)
    j pass
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
    j fail
