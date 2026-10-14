// museRISC in-house core: FPU unit testbench (C++/Verilator).
//
// Golden model: Berkeley SoftFloat 3 (the RISC-V reference).
// Tininess is configured after-rounding; NaN results from
// SoftFloat already come out canonical under RISC-V build
// options — where they don't, the TB canonicalizes the
// expected value before comparing.

#include <cstdint>
#include <cstdio>
#include <random>
#include <map>
#include <string>

extern "C" {
#include "softfloat.h"
}

#include "verilated.h"
#include "verilated_cov.h"
#include <cstdlib>
#include "Vmuserisc_fpu.h"

static Vmuserisc_fpu* dut;
static long checks = 0, fails = 0;

enum { OP_ADD=0, OP_SUB, OP_MUL, OP_DIV, OP_SQRT, OP_SGNJ, OP_MINMAX,
       OP_CMP, OP_CLASS, OP_F2I, OP_I2F, OP_F2F, OP_FMA, OP_FMS,
       OP_FNMS, OP_FNMA };

static uint64_t run(uint8_t op, bool d, uint8_t rm, uint64_t a,
                    uint64_t b, uint64_t c, uint8_t aux, uint8_t* fl) {
  dut->op_i = op; dut->fmt_d_i = d; dut->rm_i = rm;
  dut->a_i = a; dut->b_i = b; dut->c_i = c; dut->aux_i = aux;
  dut->eval();
  *fl = dut->flags_o;
  return dut->result_o;
}

static uint32_t box32(uint32_t f) {
  return f;
}
static uint64_t to_reg(bool d, uint64_t bits) {
  return d ? bits : (0xFFFFFFFF00000000ULL | (uint32_t)bits);
}

static bool is_nan32(uint32_t x) {
  return ((x >> 23) & 0xFF) == 0xFF && (x & 0x7FFFFF) != 0;
}
static bool is_nan64(uint64_t x) {
  return ((x >> 52) & 0x7FF) == 0x7FF &&
         (x & 0xFFFFFFFFFFFFFULL) != 0;
}
static uint64_t canon(bool d, uint64_t bits) {
  if (d) return is_nan64(bits) ? 0x7FF8000000000000ULL : bits;
  uint32_t f = (uint32_t)bits;
  return is_nan32(f) ? 0x7FC00000U : f;
}

static void clear_flags() { softfloat_exceptionFlags = 0; }
static uint8_t read_flags() {
  uint_fast8_t f = softfloat_exceptionFlags;
  // softfloat: invalid=16? map: use constants from softfloat.h
  uint8_t o = 0;
  if (f & softfloat_flag_invalid)   o |= 16;
  if (f & softfloat_flag_infinite)  o |= 8;
  if (f & softfloat_flag_overflow)  o |= 4;
  if (f & softfloat_flag_underflow) o |= 2;
  if (f & softfloat_flag_inexact)   o |= 1;
  return o;
}

static void set_rm(uint8_t rm) {
  switch (rm) {
    case 0: softfloat_roundingMode = softfloat_round_near_even; break;
    case 1: softfloat_roundingMode = softfloat_round_minMag; break;
    case 2: softfloat_roundingMode = softfloat_round_min; break;
    case 3: softfloat_roundingMode = softfloat_round_max; break;
    case 4: softfloat_roundingMode = softfloat_round_near_maxMag; break;
  }
}

static std::map<std::string, long> cat_fails;
static void cmp(const char* what, uint64_t got, uint64_t want,
                uint8_t gf, uint8_t wf, uint64_t a, uint64_t b,
                uint64_t c) {
  checks++;
  if (got != want || gf != wf) {
    cat_fails[what]++;
    if (cat_fails[what] <= 3)
      std::printf("FAIL %s a=%016llx b=%016llx c=%016llx "
                  "got=%016llx f=%u want=%016llx f=%u\n", what,
                  (unsigned long long)a, (unsigned long long)b,
                  (unsigned long long)c, (unsigned long long)got,
                  gf, (unsigned long long)want, wf);
    fails++;
  }
}


// IEEE minNum/maxNum golden (this SoftFloat build lacks them):
// NaN handling + zero-sign rules per spec; comparisons via
// SoftFloat on non-NaN inputs raise no flags.
static bool snan_bits(bool d, uint64_t v) {
  if (d) return ((v >> 52) & 0x7FF) == 0x7FF &&
                (v & 0xFFFFFFFFFFFFFULL) != 0 &&
                ((v >> 51) & 1) == 0;
  uint32_t f = (uint32_t)v;
  return ((f >> 23) & 0xFF) == 0xFF && (f & 0x7FFFFF) != 0 &&
         ((f >> 22) & 1) == 0;
}
static uint64_t minmax_golden(bool d, int is_max, uint64_t av,
                              uint64_t bv) {
  bool na = d ? is_nan64(av) : is_nan32((uint32_t)av);
  bool nb = d ? is_nan64(bv) : is_nan32((uint32_t)bv);
  if (snan_bits(d, av) || snan_bits(d, bv))
    softfloat_exceptionFlags |= softfloat_flag_invalid;
  if (na && nb)
    return d ? 0x7FF8000000000000ULL : 0xFFFFFFFF7FC00000ULL;
  if (na) return to_reg(d, bv);
  if (nb) return to_reg(d, av);
  bool az = d ? ((av & 0x7FFFFFFFFFFFFFFFULL) == 0)
              : (((uint32_t)av & 0x7FFFFFFFU) == 0);
  bool bz = d ? ((bv & 0x7FFFFFFFFFFFFFFFULL) == 0)
              : (((uint32_t)bv & 0x7FFFFFFFU) == 0);
  if (az && bz) {
    bool sa = d ? (av >> 63) : ((uint32_t)av >> 31);
    bool sb = d ? (bv >> 63) : ((uint32_t)bv >> 31);
    bool sign = is_max ? (sa && sb) : (sa || sb);
    return to_reg(d, sign ? (d ? (1ULL << 63) : (1ULL << 31)) : 0);
  }
  bool lt;
  if (d) { float64_t x{av}, y{bv}; lt = f64_lt(x, y); }
  else { float32_t x{(uint32_t)av}, y{(uint32_t)bv};
         lt = f32_lt(x, y); }
  bool pick_a = is_max ? !lt : lt;
  // equal values: bit patterns identical (only +-0 differ,
  // handled above), so either is fine
  return to_reg(d, pick_a ? av : bv);
}

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  const char* cov_path = std::getenv("COV_FILE");
  dut = new Vmuserisc_fpu{&context};
  softfloat_detectTininess = softfloat_tininess_afterRounding;

  std::mt19937_64 rng(0xF00D);
  const int N = 3000;

  for (int d = 0; d <= 1; d++) {
    auto rnd = [&]() -> uint64_t {
      // bias toward interesting exponents but keep random bits
      uint64_t v = rng();
      if ((v & 3) == 0) {  // make exponent small-ish sometimes
        if (d) v = (v & ~(0x7FFULL << 52)) |
                   (((rng() % 80) + 970ULL) << 52);
        else   v = (v & ~(0xFFULL << 23)) |
                   (((rng() % 60) + 95ULL) << 23);
      }
      return to_reg(d, v);
    };
    for (uint8_t rm = 0; rm < 5; rm++) {
      set_rm(rm);
      for (int i = 0; i < N; i++) {
        uint64_t a = rnd(), b = rnd(), c = rnd();
        uint64_t ab = d ? a : (uint32_t)a;
        uint64_t bb = d ? b : (uint32_t)b;
        uint64_t cb = d ? c : (uint32_t)c;
        float64_t fa{ab}, fb{bb}, fc{cb};
        float32_t f32a{(uint32_t)ab}, f32b{(uint32_t)bb},
                  f32c{(uint32_t)cb};
        uint8_t fl;
        // ADD/SUB/MUL/DIV
        for (int op = OP_ADD; op <= OP_DIV; op++) {
          uint64_t got = run(op, d, rm, a, b, c, 0, &fl);
          clear_flags();
          uint64_t want;
          if (d) {
            float64_t r = (op == OP_ADD) ? f64_add(fa, fb) :
                          (op == OP_SUB) ? f64_sub(fa, fb) :
                          (op == OP_MUL) ? f64_mul(fa, fb) :
                                           f64_div(fa, fb);
            want = canon(1, r.v);
          } else {
            float32_t r = (op == OP_ADD) ? f32_add(f32a, f32b) :
                          (op == OP_SUB) ? f32_sub(f32a, f32b) :
                          (op == OP_MUL) ? f32_mul(f32a, f32b) :
                                           f32_div(f32a, f32b);
            want = to_reg(0, canon(0, r.v));
          }
          cmp("arith", got, want, fl, read_flags(), a, b, op);
        }
        // SQRT
        {
          uint64_t got = run(OP_SQRT, d, rm, a, b, c, 0, &fl);
          clear_flags();
          uint64_t want = d ? canon(1, f64_sqrt(fa).v)
                            : to_reg(0, canon(0, f32_sqrt(f32a).v));
          cmp("sqrt", got, want, fl, read_flags(), a, 0, 0);
        }
        // FMA group
        for (int op = OP_FMA; op <= OP_FNMA; op++) {
          uint64_t got = run(op, d, rm, a, b, c, 0, &fl);
          clear_flags();
          // express all FMA sign variants with flipped inputs
          float64_t nga{fa.v ^ (op == OP_FNMS || op == OP_FNMA ?
                                (1ULL << 63) : 0)};
          float64_t ngc{fc.v ^ (op == OP_FMS || op == OP_FNMA ?
                                (1ULL << 63) : 0)};
          float32_t n32a{(uint32_t)(f32a.v ^
                      ((op == OP_FNMS || op == OP_FNMA) ?
                       (1U << 31) : 0))};
          float32_t n32c{(uint32_t)(f32c.v ^
                      ((op == OP_FMS || op == OP_FNMA) ?
                       (1U << 31) : 0))};
          uint64_t want;
          if (d) want = canon(1, f64_mulAdd(nga, fb, ngc).v);
          else want = to_reg(0, canon(0, f32_mulAdd(
                                        n32a, f32b, n32c).v));
          cmp("fma", got, want, fl, read_flags(), a, b, c);
        }
        // MIN/MAX
        for (int aux = 0; aux <= 1; aux++) {
          uint64_t got = run(OP_MINMAX, d, rm, a, b, c, aux, &fl);
          clear_flags();
          uint64_t want = minmax_golden(d, aux, ab, bb);
          cmp("minmax", got, want, fl, read_flags(), a, b, aux);
        }
        // CMP: aux 0=le 1=lt 2=eq(quiet)
        for (int aux = 0; aux <= 2; aux++) {
          uint64_t got = run(OP_CMP, d, rm, a, b, c, aux, &fl);
          clear_flags();
          bool r;
          if (d) r = (aux == 2) ? f64_eq(fa, fb) :
                     (aux == 1) ? f64_lt(fa, fb) : f64_le(fa, fb);
          else r = (aux == 2) ? f32_eq(f32a, f32b) :
                   (aux == 1) ? f32_lt(f32a, f32b) : f32_le(f32a, f32b);
          cmp("cmp", got, r ? 1 : 0, fl, read_flags(), a, b, aux);
        }
        // F2I aux: 0=W 1=WU 2=L 3=LU
        for (int aux = 0; aux <= 3; aux++) {
          uint64_t got = run(OP_F2I, d, rm, a, b, c, aux, &fl);
          clear_flags();
          uint64_t want;
          if (d) {
            switch (aux) {
              case 0: want = (uint64_t)(int64_t)
                             f64_to_i32(fa, rm, true); break;
              case 1: want = (uint64_t)(int64_t)(int32_t)
                             f64_to_ui32(fa, rm, true); break;
              case 2: want = (uint64_t)
                             f64_to_i64(fa, rm, true); break;
              default: want = f64_to_ui64(fa, rm, true); break;
            }
          } else {
            switch (aux) {
              case 0: want = (uint64_t)(int64_t)
                             f32_to_i32(f32a, rm, true); break;
              case 1: want = (uint64_t)(int64_t)(int32_t)
                             f32_to_ui32(f32a, rm, true); break;
              case 2: want = (uint64_t)
                             f32_to_i64(f32a, rm, true); break;
              default: want = f32_to_ui64(f32a, rm, true); break;
            }
          }
          cmp("f2i", got, want, fl, read_flags(), a, 0, aux);
        }
        // I2F: integer source in a_i (raw)
        for (int aux = 0; aux <= 3; aux++) {
          uint64_t got = run(OP_I2F, d, rm, ab, b, c, aux, &fl);
          clear_flags();
          uint64_t want;
          if (d) {
            float64_t r = aux == 0 ? i32_to_f64((int32_t)ab) :
                          aux == 1 ? ui32_to_f64((uint32_t)ab) :
                          aux == 2 ? i64_to_f64((int64_t)ab) :
                                     ui64_to_f64(ab);
            want = r.v;
          } else {
            float32_t r = aux == 0 ? i32_to_f32((int32_t)ab) :
                          aux == 1 ? ui32_to_f32((uint32_t)ab) :
                          aux == 2 ? i64_to_f32((int64_t)ab) :
                                     ui64_to_f32(ab);
            want = to_reg(0, r.v);
          }
          cmp("i2f", got, want, fl, read_flags(), ab, 0, aux);
        }
        // F2F: dest fmt = d, source is the other format
        {
          uint64_t src = d ? to_reg(0, (uint32_t)rng())
                           : rng();
          uint64_t got = run(OP_F2F, d, rm, src, b, c, 0, &fl);
          clear_flags();
          uint64_t want;
          if (d) {
            float32_t s{(uint32_t)src};
            want = canon(1, f32_to_f64(s).v);
          } else {
            float64_t s{src};
            want = to_reg(0, canon(0, f64_to_f32(s).v));
          }
          cmp("f2f", got, want, fl, read_flags(), src, 0, d);
        }
        (void)box32;
      }
    }
  }

  // Tininess-boundary regressions (from ACT D-fmadd.d-06):
  // results just below 2^emin that round up to min-normal.
  // UF depends on whether the jammed significand plus the
  // rounding increment carries to 2^emin (Berkeley rule).
  {
    uint8_t fl;
    auto fma_case = [&](uint64_t a, uint64_t b, uint64_t c,
                        uint8_t rm, uint64_t want, uint8_t wf) {
      uint64_t got = run(OP_FMA, 1, rm, a, b, c, 0, &fl);
      cmp("tininess", got, want, fl, wf, a, b, c);
    };
    // largest subnormal + negligible -> min normal, UF|NX
    fma_case(0x8010000000000000ULL, 0x91CF4D7110BEE879ULL,
             0x000FFFFFFFFFFFFFULL, 3, 0x0010000000000000ULL, 3);
    // min normal - negligible -> min normal, NX only
    fma_case(0x0010000000000000ULL, 0x99A6BAAE71EB5A39ULL,
             0x0010000000000000ULL, 3, 0x0010000000000000ULL, 1);
    // and with RNE (stays min normal here), NX only
    fma_case(0x0010000000000000ULL, 0x99A6BAAE71EB5A39ULL,
             0x0010000000000000ULL, 0, 0x0010000000000000ULL, 1);
  }

  // Directed specials for branch coverage the random sweep
  // hits too rarely: inf propagation in every op class,
  // FMA inf-inf cancellation, min/max NaN and zero pairs,
  // F2I of zero and of huge magnitudes, F2F inf.
  {
    uint8_t fl;
    for (int d = 0; d <= 1; d++) {
      set_rm(0);
      uint64_t inf = d ? 0x7FF0000000000000ULL : 0x7F800000ULL;
      uint64_t ninf = inf | (d ? (1ULL << 63) : (1ULL << 31));
      uint64_t one = d ? 0x3FF0000000000000ULL : 0x3F800000ULL;
      uint64_t qnan = d ? 0x7FF8000000000000ULL : 0x7FC00000ULL;
      uint64_t big = d ? 0x7FEFFFFFFFFFFFFFULL : 0x7F7FFFFFULL;
      auto R = [&](uint64_t v) { return to_reg(d, v); };
      auto bin = [&](int op, uint64_t x, uint64_t y, uint64_t z,
                     int aux, const char* nm) {
        uint64_t got = run(op, d, 0, R(x), R(y), R(z), aux, &fl);
        clear_flags();
        float64_t fa{x}, fb{y}, fc{z};
        float32_t f32a{(uint32_t)x}, f32b{(uint32_t)y},
                  f32c{(uint32_t)z};
        uint64_t want;
        if (op >= OP_FMA) {
          uint64_t na = (op == OP_FNMS || op == OP_FNMA)
                        ? (x ^ (d ? (1ULL<<63) : (1ULL<<31))) : x;
          uint64_t nc = (op == OP_FMS || op == OP_FNMA)
                        ? (z ^ (d ? (1ULL<<63) : (1ULL<<31))) : z;
          float64_t ga{na}, gc{nc};
          float32_t g32a{(uint32_t)na}, g32c{(uint32_t)nc};
          want = d ? canon(1, f64_mulAdd(ga, fb, gc).v)
                   : to_reg(0, canon(0, f32_mulAdd(g32a, f32b, g32c).v));
        } else if (op == OP_MINMAX) {
          want = minmax_golden(d, aux, x, y);
        } else if (op == OP_CMP) {
          bool r = d ? (aux == 2 ? f64_eq(fa, fb) :
                        aux == 1 ? f64_lt(fa, fb) : f64_le(fa, fb))
                     : (aux == 2 ? f32_eq(f32a, f32b) :
                        aux == 1 ? f32_lt(f32a, f32b) : f32_le(f32a, f32b));
          want = r ? 1 : 0;
        } else if (op == OP_F2I) {
          if (d) want = aux == 0 ? (uint64_t)(int64_t)f64_to_i32(fa, 0, true)
                      : aux == 1 ? (uint64_t)(int64_t)(int32_t)f64_to_ui32(fa, 0, true)
                      : aux == 2 ? (uint64_t)f64_to_i64(fa, 0, true)
                                 : f64_to_ui64(fa, 0, true);
          else want = aux == 0 ? (uint64_t)(int64_t)f32_to_i32(f32a, 0, true)
                      : aux == 1 ? (uint64_t)(int64_t)(int32_t)f32_to_ui32(f32a, 0, true)
                      : aux == 2 ? (uint64_t)f32_to_i64(f32a, 0, true)
                                 : f32_to_ui64(f32a, 0, true);
        } else if (d) {
          float64_t rd = op == OP_ADD ? f64_add(fa, fb) :
                         op == OP_MUL ? f64_mul(fa, fb) :
                                        f64_div(fa, fb);
          want = canon(1, rd.v);
        } else {
          float32_t rs = op == OP_ADD ? f32_add(f32a, f32b) :
                         op == OP_MUL ? f32_mul(f32a, f32b) :
                                        f32_div(f32a, f32b);
          want = to_reg(0, canon(0, rs.v));
        }
        cmp(nm, got, want, fl, read_flags(), x, y, z);
      };
      bin(OP_ADD, inf, one, 0, 0, "spc");       // inf + 1
      bin(OP_ADD, inf, ninf, 0, 0, "spc");      // inf - inf
      bin(OP_MUL, inf, one, 0, 0, "spc");       // inf * 1
      bin(OP_MUL, inf, 0, 0, 0, "spc");         // inf * 0
      bin(OP_DIV, one, inf, 0, 0, "spc");       // 1 / inf
      bin(OP_FMA, inf, one, ninf, 0, "spc");    // inf*1 - inf
      bin(OP_FMA, one, one, inf, 0, "spc");     // finite + inf
      bin(OP_FMA, 0, 0, 0, 0, "spc");           // 0*0+0
      bin(OP_FMA, inf, one, 0, 0, "spc");       // inf*1+0
      bin(OP_MINMAX, qnan, qnan, 0, 0, "spc");
      bin(OP_MINMAX, 0, d ? (1ULL<<63) : (1ULL<<31), 0, 0, "spc");
      bin(OP_MINMAX, 0, d ? (1ULL<<63) : (1ULL<<31), 0, 1, "spc");
      bin(OP_CMP, 0, d ? (1ULL<<63) : (1ULL<<31), 0, 2, "spc");
      for (int aux = 0; aux <= 3; aux++) {
        bin(OP_F2I, 0, 0, 0, aux, "spc");       // +0 -> int
        bin(OP_F2I, big, 0, 0, aux, "spc");     // huge -> sat
      }
      // F2F of inf (source is the other format)
      {
        uint64_t src = d ? 0x7F800000ULL : 0x7FF0000000000000ULL;
        uint64_t got = run(OP_F2F, d, 0, to_reg(!d, src), 0, 0, 0, &fl);
        uint64_t want = d ? 0x7FF0000000000000ULL
                          : 0xFFFFFFFF7F800000ULL;
        cmp("spc-f2f", got, want, fl, 0, src, 0, 0);
      }
    }
  }

  // Exact FMA cancellation to zero: sign is +0 except RDN.
  {
    uint8_t fl;
    uint64_t got;
    got = run(OP_FMA, 1, 0, 0x3FF8000000000000ULL,
              0x4000000000000000ULL, 0xC008000000000000ULL, 0, &fl);
    cmp("fma-cancel", got, 0, fl, 0, 0, 0, 0);
    got = run(OP_FMA, 1, 2, 0x3FF8000000000000ULL,
              0x4000000000000000ULL, 0xC008000000000000ULL, 0, &fl);
    cmp("fma-cancel", got, 0x8000000000000000ULL, fl, 0, 0, 0, 0);
  }

  // SGNJ + CLASS directed
  for (int d = 0; d <= 1; d++) {
    uint8_t fl;
    uint64_t a = to_reg(d, d ? 0xC004000000000000ULL
                             : 0xC0200000ULL);
    uint64_t b = to_reg(d, d ? 0x3FF0000000000000ULL
                             : 0x3F800000ULL);
    uint64_t got = run(OP_SGNJ, d, 0, a, b, 0, 2, &fl);
    uint64_t want = run(OP_SGNJ, d, 0, a, b, 0, 0, &fl);
    checks++;
    // sgnjx(-x,+y) keeps -; sgnj(-x,+y) takes +y sign
    uint64_t expct = d ? 0x4004000000000000ULL
                       : 0xFFFFFFFF40200000ULL;
    uint64_t expx = d ? 0xC004000000000000ULL
                      : 0xFFFFFFFFC0200000ULL;
    if (got != expx || want != expct) { fails++;
      std::printf("FAIL sgnj d=%d got=%016llx want=%016llx\n",
                  d, (unsigned long long)got,
                  (unsigned long long)expct); }
    auto cls = [&](uint64_t v, int bit) {
      uint64_t g = run(OP_CLASS, d, 0, to_reg(d, v), 0, 0, 0, &fl);
      checks++;
      if (g != (1ULL << bit) || fl != 0) { fails++;
        std::printf("FAIL class d=%d v=%016llx got=%llu\n", d,
                    (unsigned long long)v,
                    (unsigned long long)g); }
    };
    if (d) {
      cls(0xFFF8000000000000ULL, 9); cls(0xFFF4000000000000ULL, 8);
      cls(0xFFF0000000000000ULL, 0); cls(0xBFF0000000000000ULL, 1);
      cls(0x8000000000000001ULL, 2); cls(0x8000000000000000ULL, 3);
      cls(0x0000000000000000ULL, 4); cls(0x0000000000000001ULL, 5);
      cls(0x3FF0000000000000ULL, 6); cls(0x7FF0000000000000ULL, 7);
    } else {
      cls(0xFFC00000ULL, 9); cls(0xFFA00000ULL, 8);
      cls(0xFF800000ULL, 0); cls(0xBF800000ULL, 1);
      cls(0x80000001ULL, 2); cls(0x80000000ULL, 3);
      cls(0x00000000ULL, 4); cls(0x00000001ULL, 5);
      cls(0x3F800000ULL, 6); cls(0x7F800000ULL, 7);
    }
  }

  for (auto& kv : cat_fails)
    std::printf("fails[%s] = %ld\n", kv.first.c_str(), kv.second);
  dut->final();
  delete dut;
  if (cov_path != nullptr) context.coveragep()->write(cov_path);
  if (fails) { std::printf("FPU TB FAIL (%ld/%ld)\n", fails, checks);
    return 1; }
  std::printf("FPU TB PASS (%ld checks)\n", checks);
  return 0;
}
