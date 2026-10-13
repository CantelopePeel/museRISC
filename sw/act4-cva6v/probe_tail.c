// Directed probe for the ACT vector first-case failures (issue #9).
// Replicates Vx8-vadd.vv-00 test case 1 structure (VLMAX prefill with
// vmv.v.i, VL=1 vle8 loads, VL=1 vadd.vv, all e8/m1/tu/mu) with known
// scalar values and dumps the whole destination register after each
// stage over the mock UART (0xC0000000), so tail-element behavior is
// directly observable. Exit code: 0 if every stage matches the scalar
// expectation, otherwise 20 + stage number of the first mismatch.
#include <stdint.h>

#define UART ((volatile uint8_t *)0xC0000000u)
static void putc_(char c) { *UART = (uint8_t)c; }
static void puts_(const char *s) { while (*s) putc_(*s++); }
static void puthex8(uint8_t v) {
  const char *d = "0123456789abcdef";
  putc_(d[(v >> 4) & 0xF]); putc_(d[v & 0xF]);
}

static uint8_t in_vd[64], in_vs2[64], in_vs1[64], out[64];

#define VREGS "v0", "v8", "v13", "t0", "memory"

static void dump_v0(const char *tag) {
  asm volatile(
      "vsetvli t0, zero, e8, m1, tu, mu\n"
      "vse8.v v0, (%0)\n"
      "fence\n"
      ::"r"(out)
      : VREGS);
  puts_(tag);
  for (int i = 0; i < 64; i++) { puthex8(out[i]); putc_(' '); }
  putc_('\n');
}

static int check_tail(uint8_t first, uint8_t rest) {
  if (out[0] != first) return 0;
  for (int i = 1; i < 64; i++)
    if (out[i] != rest) return 0;
  return 1;
}

int main(void) {
  puts_("PROBE START\n");
  // volatile stores: keep GCC from idiom-replacing the fills with
  // memset calls (nostdlib has no memset).
  for (int i = 0; i < 64; i++) {
    *(volatile uint8_t *)&in_vd[i] = 0xAA;
    *(volatile uint8_t *)&in_vs2[i] = 0x01;
    *(volatile uint8_t *)&in_vs1[i] = 0x02;
  }

  // Stage 1: VLMAX prefill (rs1 = x0, rd != x0 form used by ACT).
  asm volatile(
      "vsetvli t0, zero, e8, m1, tu, mu\n"
      "vmv.v.i v0, 0xd\n"
      "vmv.v.i v8, 0xd\n"
      "vmv.v.i v13, 0xd\n"
      ::: VREGS);
  dump_v0("S1 fill      : ");
  if (!check_tail(0x0d, 0x0d)) return 21;

  // Stage 2: VL=1 loads over element 0 only (tail must stay 0x0d).
  asm volatile(
      "vsetivli t0, 1, e8, m1, tu, mu\n"
      "vle8.v v0, (%0)\n"
      "vle8.v v8, (%1)\n"
      "vle8.v v13, (%2)\n"
      "vsetivli t0, 1, e8, m1, tu, mu\n"
      ::"r"(in_vd), "r"(in_vs2), "r"(in_vs1)
      : VREGS);
  dump_v0("S2 vl1 load  : ");
  if (!check_tail(0xAA, 0x0d)) return 22;

  // Stage 3: VL=1 vadd.vv v0, v8, v13 (element 0: 1 + 2 = 3).
  asm volatile(
      "vsetivli t0, 1, e8, m1, tu, mu\n"
      "vadd.vv v0, v8, v13\n"
      ::: VREGS);
  dump_v0("S3 vl1 vadd  : ");
  if (!check_tail(0x03, 0x0d)) return 23;

  // Stage 4: replicate the RVTEST_SIGUPD_V compare path. Prefill the
  // mask temporary v19 with all-ones at VLMAX, load golden (= DUT
  // result) into v21, then at VL=1: vmsne.vv v19, v0, v21 (bit 0 must
  // clear: elements equal; bits >= 1 must remain 1 under mu), then
  // vfirst.m must return -1 if it is bounded by vl, or >= 1 if it
  // scans the mask tail beyond vl.
  {
    long first = 0;
    asm volatile(
        "vsetvli t0, zero, e8, m1, tu, mu\n"
        "vmv.v.i v19, -1\n"
        "vmv.v.v v21, v0\n"
        "vsetivli t0, 1, e8, m1, tu, mu\n"
        "vmsne.vv v19, v0, v21\n"
        "vfirst.m %0, v19\n"
        : "=r"(first)
        :
        : "v0", "v8", "v13", "v19", "v21", "t0", "memory");
    asm volatile(
        "vsetvli t0, zero, e8, m1, tu, mu\n"
        "vse8.v v19, (%0)\n"
        "fence\n"
        ::"r"(out)
        : "v19", "t0", "memory");
    puts_("S4 mask      : ");
    for (int i = 0; i < 8; i++) { puthex8(out[i]); putc_(' '); }
    puts_("\nS4 vfirst = ");
    if (first < 0) { puts_("-1\n"); }
    else { puthex8((uint8_t)first); putc_('\n'); }
    if (first != -1) return 24;
  }

  puts_("PROBE OK\n");
  return 0;
}
