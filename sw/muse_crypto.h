/* museRISC crypto accelerator register map (see docs/SPEC.md).
 * Base in SoC: 0x2000_0000. Registers are little-endian w.r.t. DIN:
 * DIN0 holds the first SHA-256 message word / the low field word,
 * DOUT0 holds the low word of the 256-bit result. */
#ifndef MUSE_CRYPTO_H
#define MUSE_CRYPTO_H
#define MUSE_CRYPTO_BASE   0x20000000UL
#define MUSE_CTRL          (MUSE_CRYPTO_BASE + 0x00) /* b0 start, b[5:4] engine, b[7:6] field op */
#define MUSE_STATUS        (MUSE_CRYPTO_BASE + 0x04) /* b0 busy, b1 done */
#define MUSE_DIN(i)        (MUSE_CRYPTO_BASE + 0x08 + 4*(i))  /* i=0..15 */
#define MUSE_DOUT(i)       (MUSE_CRYPTO_BASE + 0x48 + 4*(i))  /* i=0..7  */
#define MUSE_MODSEL        (MUSE_CRYPTO_BASE + 0x68) /* 0 secp256k1, 1 Curve25519, 2 custom */
#define MUSE_MOD(i)        (MUSE_CRYPTO_BASE + 0x6C + 4*(i))  /* i=0..7  */
#define MUSE_ENG_SHA256    0
#define MUSE_ENG_KECCAK_RSVD 1 /* Phase 1 (needs DMA); do not use */
#define MUSE_ENG_FIELD     2
#define MUSE_FLD_ADD 0
#define MUSE_FLD_SUB 1
#define MUSE_FLD_MUL 2
#endif
