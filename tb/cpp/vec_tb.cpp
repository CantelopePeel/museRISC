// Vector execution unit testbench (issue #23): independent
// C++ golden model for the RVV 1.0 integer classes over
// register groups, across SEW, vl/vstart, masking, and
// tail/mask-agnostic policies. The golden model is written
// from the spec's element semantics directly (per-element
// arrays), not by mirroring the RTL loop.
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <random>

#include "Vmuserisc_vec.h"
#include "verilated.h"
#include "verilated_cov.h"

static int checks = 0;
static int failures = 0;
#define CHECK(cond)                                       \
  do {                                                    \
    ++checks;                                             \
    if (!(cond)) {                                        \
      std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, \
                  #cond);                                 \
      ++failures;                                         \
    }                                                     \
  } while (0)

namespace {

// A register group as 512 SEW-sized element slots is handled
// as raw 64-bit words; helpers extract/replace elements.
struct Group {
  uint64_t w[64] = {};
};

uint64_t MaskFor(int sew) {
  return sew >= 64 ? ~0ull : ((1ull << sew) - 1);
}
uint64_t GetEl(const Group& g, int idx, int sew) {
  const int base = idx * sew;
  const uint64_t v = g.w[base / 64] >> (base % 64);
  return v & MaskFor(sew);
}
void SetEl(Group& g, int idx, int sew, uint64_t v) {
  const int base = idx * sew;
  const int word = base / 64;
  const int off = base % 64;
  g.w[word] = (g.w[word] & ~(MaskFor(sew) << off)) |
              ((v & MaskFor(sew)) << off);
}
int64_t SextEl(uint64_t v, int sew) {
  if (sew == 64) return static_cast<int64_t>(v);
  const uint64_t sign = 1ull << (sew - 1);
  return static_cast<int64_t>(((v & MaskFor(sew)) ^ sign) - sign);
}

template <typename Port>
void PutGroup(Port& port, const Group& g) {
  for (int i = 0; i < 128; ++i) {
    port[i] = static_cast<uint32_t>(g.w[i / 2] >> (32 * (i % 2)));
  }
}
template <typename Port>
Group FetchGroup(const Port& port) {
  Group g;
  for (int i = 0; i < 128; ++i) {
    g.w[i / 2] |= static_cast<uint64_t>(
                      static_cast<uint32_t>(port[i]))
                  << (32 * (i % 2));
  }
  return g;
}

// VOP_* numeric codes mirror rtl/core/muserisc_pkg.sv.
enum Op {
  kAdd = 0, kSub, kRsub, kAnd, kOr, kXor, kSll, kSrl, kSra, kMv,
  kMvSx, kMvXs, kMin = 12, kMinu, kMax, kMaxu, kMul, kMulh, kMulhu,
  kMulhsu, kMacc, kMadd, kNmsac, kNmsub, kDiv, kDivu, kRem, kRemu,
  kAdc = 28, kSbc = 30, kMerge = 32, kSadd = 44, kSaddu, kSsub,
  kSsubu
};

uint64_t GoldenEl(Op op, uint64_t a, uint64_t b, uint64_t old_el,
                  bool carry, int sew, bool* sat, bool vi = false) {
  const uint64_t m = MaskFor(sew);
  const uint64_t bm = b & m;
  const int64_t as = SextEl(a, sew), bs = SextEl(b, sew);
  // VI shift amounts are the zero-extended 5-bit immediate.
  const int sh = static_cast<int>(
      (vi ? (b & 31ull) : b) & static_cast<uint64_t>(sew - 1));
  *sat = false;
  auto sat_s = [&](__int128 v) -> uint64_t {
    const __int128 hi = (static_cast<__int128>(1) << (sew - 1)) - 1;
    const __int128 lo = -(static_cast<__int128>(1) << (sew - 1));
    if (v > hi) { *sat = true; return static_cast<uint64_t>(hi) & m; }
    if (v < lo) { *sat = true; return static_cast<uint64_t>(lo) & m; }
    return static_cast<uint64_t>(v) & m;
  };
  switch (op) {
    case kAdd: return (a + bm) & m;
    case kSub: return (a - bm) & m;
    case kRsub: return (bm - a) & m;
    case kAnd: return a & bm;
    case kOr: return a | bm;
    case kXor: return a ^ bm;
    case kSll: return (a << sh) & m;
    case kSrl: return (a & m) >> sh;
    case kSra: return static_cast<uint64_t>(as >> sh) & m;
    case kMin: return as < bs ? a : bm;
    case kMinu: return a < bm ? a : bm;
    case kMax: return as > bs ? a : bm;
    case kMaxu: return a > bm ? a : bm;
    case kMul: return (a * bm) & m;
    case kMulh: return static_cast<uint64_t>(
        (static_cast<__int128>(as) * bs) >> sew) & m;
    case kMulhu: return static_cast<uint64_t>(
        (static_cast<unsigned __int128>(a) * bm) >> sew) & m;
    case kMulhsu: return static_cast<uint64_t>(
        (static_cast<__int128>(as) *
         static_cast<__int128>(bm)) >> sew) & m;
    case kMacc: return (old_el + a * bm) & m;
    case kMadd: return (bm * old_el + a) & m;
    case kNmsac: return (old_el - a * bm) & m;
    case kNmsub: return (a - bm * old_el) & m;
    case kDiv:
      if (bm == 0) return m;
      if (sew == 64 && as == INT64_MIN && bs == -1) return a;
      return static_cast<uint64_t>(as / bs) & m;
    case kDivu: return bm == 0 ? m : a / bm;
    case kRem:
      if (bm == 0) return a;
      if (sew == 64 && as == INT64_MIN && bs == -1) return 0;
      return static_cast<uint64_t>(as % bs) & m;
    case kRemu: return bm == 0 ? a : a % bm;
    case kAdc: return (a + bm + (carry ? 1 : 0)) & m;
    case kSbc: return (a - bm - (carry ? 1 : 0)) & m;
    case kMerge: return carry ? bm : a;
    case kSadd: return sat_s(static_cast<__int128>(as) + bs);
    case kSaddu: {
      const unsigned __int128 v =
          static_cast<unsigned __int128>(a) + bm;
      if (v > m) { *sat = true; return m; }
      return static_cast<uint64_t>(v);
    }
    case kSsub: return sat_s(static_cast<__int128>(as) - bs);
    case kSsubu:
      if (a < bm) { *sat = true; return 0; }
      return a - bm;
    default: return bm;  // moves
  }
}

}  // namespace

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Verilated::mkdir("logs");
  auto* d = new Vmuserisc_vec;
  std::mt19937_64 rng(0x5eed8a);

  const Op kOps[] = {kAdd,  kSub,  kRsub, kAnd,  kOr,    kXor,  kSll,
                     kSrl,  kSra,  kMv,   kMvSx, kMvXs,  kMin,  kMinu,
                     kMax,  kMaxu, kMul,  kMulh, kMulhu, kMulhsu, kMacc,
                     kMadd, kNmsac, kNmsub, kDiv,  kDivu, kRem,  kRemu,
                     kAdc,  kSbc,  kMerge, kSadd, kSaddu, kSsub, kSsubu};
  for (int sew_code = 0; sew_code < 4; ++sew_code) {
    const int sew = 8 << sew_code;
    const int max_el = 4096 / sew;
    for (Op op : kOps) {
      for (int form = 0; form < 3; ++form) {
        if (op == kRsub && form == 0) continue;
        if ((op == kMacc || op == kMadd || op == kNmsac ||
             op == kNmsub || op == kDiv || op == kDivu ||
             op == kRem || op == kRemu || op == kMul ||
             op == kMulh || op == kMulhu || op == kMulhsu) &&
            form == 2) {
          continue;  // OPM classes have no .vi form (unit is form-agnostic, keep coverage sane)
        }
        if ((op == kMvSx || op == kMvXs) && form != 0) continue;
        for (int trial = 0; trial < 12; ++trial) {
          Group vs2, vs1, old_vd, maskg;
          for (int i = 0; i < 64; ++i) {
            vs2.w[i] = rng();
            vs1.w[i] = rng();
            old_vd.w[i] = rng();
            maskg.w[i] = rng();
          }
          const uint64_t vl = rng() % (max_el + 1);
          const uint64_t vstart = (trial % 3 == 0) ? (rng() % 5) : 0;
          const bool vm = (rng() & 1) != 0;
          const bool vta = (rng() & 1) != 0;
          const bool vma = (rng() & 1) != 0;
          const uint64_t scalar = rng();
          const int64_t imm =
              static_cast<int64_t>(static_cast<int>(rng() % 32) - 16);

          d->op_i = static_cast<int>(op);
          d->form_i = form;
          d->sew_i = sew_code;
          d->vlmax_i = max_el;
          d->vxrm_i = 0;
          d->frm_i = 0;
          d->vl_i = vl;
          d->vstart_i = vstart;
          d->vta_i = vta;
          d->vma_i = vma;
          d->vm_i = vm;
          for (int i = 0; i < 16; ++i) {
            d->mask_i[i] = static_cast<uint32_t>(maskg.w[i / 2] >> (32 * (i % 2)));
          }
          PutGroup(d->vs2_i, vs2);
          PutGroup(d->vs1_i, vs1);
          PutGroup(d->old_vd_i, old_vd);
          d->scalar_i = scalar;
          d->imm_i = static_cast<uint64_t>(imm);
          d->eval();

          Group want = old_vd;
          auto mask_bit = [&](int i) {
            return ((maskg.w[i / 64] >> (i % 64)) & 1) != 0;
          };
          const bool unmasked_op =
              (op == kAdc || op == kSbc || op == kMerge);
          bool want_sat = false;
          if (op == kMvSx) {
            if (vstart == 0 && vl > 0 && (vm || mask_bit(0))) {
              SetEl(want, 0, sew, scalar);
            }
          } else if (op != kMvXs) {
            for (int i = 0; i < max_el; ++i) {
              if (static_cast<uint64_t>(i) < vstart) continue;
              const bool active = static_cast<uint64_t>(i) < vl &&
                                  (unmasked_op || vm || mask_bit(i));
              if (active) {
                const uint64_t a = GetEl(vs2, i, sew);
                const uint64_t b = form == 0 ? GetEl(vs1, i, sew)
                                   : form == 1 ? scalar
                                               : static_cast<uint64_t>(imm);
                bool sat_i = false;
                SetEl(want, i, sew,
                      GoldenEl(op, a, b, GetEl(old_vd, i, sew),
                               mask_bit(i), sew, &sat_i, form == 2));
                want_sat = want_sat || sat_i;
              }
              // Tail/inactive: agnostic = undisturbed, so
              // want (initialised to old_vd) already holds.
            }
          }
          if (op == kSadd || op == kSaddu || op == kSsub ||
              op == kSsubu) {
            CHECK((d->sat_o != 0) == want_sat);
          }
          const Group got = FetchGroup(d->result_o);
          for (int i = 0; i < max_el; ++i) {
            if (GetEl(got, i, sew) != GetEl(want, i, sew) &&
                failures < 4) {
              std::printf(
                  "DBG sew=%d op=%d form=%d vl=%llu vstart=%llu vm=%d "
                  "i=%d got=0x%llx want=0x%llx a=0x%llx b1=0x%llx\n",
                  sew, static_cast<int>(op), form,
                  (unsigned long long)vl, (unsigned long long)vstart,
                  vm ? 1 : 0, i,
                  (unsigned long long)GetEl(got, i, sew),
                  (unsigned long long)GetEl(want, i, sew),
                  (unsigned long long)GetEl(vs2, i, sew),
                  (unsigned long long)GetEl(vs1, i, sew));
            }
            CHECK(GetEl(got, i, sew) == GetEl(want, i, sew));
          }
          if (op == kMvXs) {
            CHECK(d->scalar_o ==
                  static_cast<uint64_t>(SextEl(GetEl(vs2, 0, sew), sew)));
          }
        }
      }
    }
  }

  // ---- Phase 3: mask/compare, reduction, widening,
  // narrowing, permutation classes at e32 with a small
  // element window (vlmax = 8) for readable failures.
  {
    const int sew = 32, sew_code = 2, vlmax = 8;
    auto run = [&](int vop, int form, uint64_t vl, uint64_t vstart,
                   bool vm, uint64_t imm, uint64_t scalar,
                   const Group& vs2, const Group& vs1,
                   const Group& old_vd, const Group& maskg) {
      d->op_i = vop;
      d->form_i = form;
      d->sew_i = sew_code;
      d->vl_i = vl;
      d->vstart_i = vstart;
      d->vlmax_i = vlmax;
      d->vta_i = 1;
      d->vma_i = 1;
      d->vm_i = vm;
      d->vxrm_i = 0;
          d->frm_i = 0;
      for (int i = 0; i < 16; ++i) {
        d->mask_i[i] =
            static_cast<uint32_t>(maskg.w[i / 2] >> (32 * (i % 2)));
      }
      PutGroup(d->vs2_i, vs2);
      PutGroup(d->vs1_i, vs1);
      PutGroup(d->old_vd_i, old_vd);
      d->scalar_i = scalar;
      d->imm_i = imm;
      d->eval();
      return FetchGroup(d->result_o);
    };
    Group vs2, vs1, old_vd, maskg, got;
    for (int i = 0; i < vlmax; ++i) {
      SetEl(vs2, i, sew, static_cast<uint64_t>(i * 3 - 7));
      SetEl(vs1, i, sew, static_cast<uint64_t>(10 - i));
      SetEl(old_vd, i, sew, 0xdead0000u + i);
    }
    maskg.w[0] = 0b10110101;

    // Compare to mask (vmslt.vv): bit i = vs2[i] < vs1[i].
    got = run(36, 0, vlmax, 0, true, 0, 0, vs2, vs1, old_vd, maskg);
    for (int i = 0; i < vlmax; ++i) {
      const bool want = SextEl(GetEl(vs2, i, sew), sew) <
                        SextEl(GetEl(vs1, i, sew), sew);
      CHECK(((got.w[0] >> i) & 1) == (want ? 1ull : 0ull));
    }
    // Masked compare (vmseq.vx, scalar 2): only mask-set
    // elements compare; others keep the old bit (agnostic =
    // undisturbed).
    got = run(33, 1, vlmax, 0, false, 0, 2, vs2, vs1, old_vd, maskg);
    for (int i = 0; i < vlmax; ++i) {
      const bool mbit = ((maskg.w[0] >> i) & 1) != 0;
      const bool want = mbit ? (GetEl(vs2, i, sew) == 2)
                             : (((old_vd.w[0] >> i) & 1) != 0);
      CHECK(((got.w[0] >> i) & 1) == (want ? 1ull : 0ull));
    }
    // Mask logical vmxor.mm (sub=3) between vs2/vs1 low bits.
    Group mv2, mv1;
    mv2.w[0] = 0b11001010;
    mv1.w[0] = 0b10101100;
    got = run(41, 0, vlmax, 0, true, 3, 0, mv2, mv1, old_vd, maskg);
    CHECK((got.w[0] & 0xff) == (0b11001010 ^ 0b10101100));
    // vmsbf.m (sub=1): ones strictly before first set bit.
    got = run(81, 0, vlmax, 0, true, 1, 0, mv2, mv1, old_vd, maskg);
    CHECK((got.w[0] & 0xff) == 0b00000001);  // first set at 1
    // vmsof.m (sub=2): only the first set bit.
    got = run(81, 0, vlmax, 0, true, 2, 0, mv2, mv1, old_vd, maskg);
    CHECK((got.w[0] & 0xff) == 0b00000010);
    // Reduction sum (sub=0) seeded by vs1 element 0 (=10).
    got = run(42, 0, vlmax, 0, true, 0, 0, vs2, vs1, old_vd, maskg);
    uint64_t red = 10;
    for (int i = 0; i < vlmax; ++i) red += GetEl(vs2, i, sew);
    CHECK(GetEl(got, 0, sew) == (red & 0xffffffffull));
    // Reduction min (sub=5).
    got = run(42, 0, vlmax, 0, true, 5, 0, vs2, vs1, old_vd, maskg);
    int64_t rmin = SextEl(GetEl(vs1, 0, sew), sew);
    for (int i = 0; i < vlmax; ++i) {
      const int64_t v = SextEl(GetEl(vs2, i, sew), sew);
      if (v < rmin) rmin = v;
    }
    CHECK(GetEl(got, 0, sew) ==
          (static_cast<uint64_t>(rmin) & 0xffffffffull));
    // Widening add .vv at e32 -> e64 results.
    got = run(55, 0, 4, 0, true, 0, 0, vs2, vs1, old_vd, maskg);
    for (int i = 0; i < 4; ++i) {
      const int64_t want = SextEl(GetEl(vs2, i, sew), sew) +
                           SextEl(GetEl(vs1, i, sew), sew);
      CHECK(GetEl(got, i, 64) == static_cast<uint64_t>(want));
    }
    // Narrowing shift right logical .wv: e64 -> e32 by 4.
    Group wide2;
    for (int i = 0; i < 4; ++i) {
      SetEl(wide2, i, 64, 0x1234567800ull + 0x100ull * i);
    }
    got = run(70, 1, 4, 0, true, 0, 4, wide2, vs1, old_vd, maskg);
    for (int i = 0; i < 4; ++i) {
      CHECK(GetEl(got, i, sew) ==
            ((GetEl(wide2, i, 64) >> 4) & 0xffffffffull));
    }
    // Slideup by 2 (vx): low elements keep old vd.
    got = run(74, 1, vlmax, 0, true, 0, 2, vs2, vs1, old_vd, maskg);
    for (int i = 0; i < vlmax; ++i) {
      const uint64_t want =
          i < 2 ? GetEl(old_vd, i, sew) : GetEl(vs2, i - 2, sew);
      CHECK(GetEl(got, i, sew) == want);
    }
    // Slidedown by 9 (past vlmax): everything zero.
    got = run(75, 1, vlmax, 0, true, 0, 9, vs2, vs1, old_vd, maskg);
    for (int i = 0; i < vlmax; ++i) CHECK(GetEl(got, i, sew) == 0);
    // Gather .vv with indices from vs1 (10-i -> in-range<8).
    got = run(78, 0, vlmax, 0, true, 0, 0, vs2, vs1, old_vd, maskg);
    for (int i = 0; i < vlmax; ++i) {
      const uint64_t idx = GetEl(vs1, i, sew);
      const uint64_t want = idx < 8 ? GetEl(vs2, static_cast<int>(idx), sew) : 0;
      CHECK(GetEl(got, i, sew) == want);
    }
    // viota.m over vs2 mask bits 0b10110101 (as vs2 group).
    Group iot;
    iot.w[0] = 0b10110101;
    got = run(82, 0, vlmax, 0, true, 0, 0, iot, vs1, old_vd, maskg);
    int cnt = 0;
    for (int i = 0; i < vlmax; ++i) {
      CHECK(GetEl(got, i, sew) == static_cast<uint64_t>(cnt));
      if ((iot.w[0] >> i) & 1) ++cnt;
    }
    // vid.v
    got = run(83, 0, vlmax, 0, true, 0, 0, iot, vs1, old_vd, maskg);
    for (int i = 0; i < vlmax; ++i) {
      CHECK(GetEl(got, i, sew) == static_cast<uint64_t>(i));
    }
    // vcpop.m / vfirst.m over 0b10110101.
    run(84, 0, vlmax, 0, true, 0, 0, iot, vs1, old_vd, maskg);
    CHECK(d->scalar_o == 5);
    run(85, 0, vlmax, 2, true, 0, 0, iot, vs1, old_vd, maskg);
    CHECK(d->scalar_o == 2);
    // vcompress.vm with select mask in vs1 (bits 0b10110101
    // applied to vs2 data elements).
    Group sel;
    sel.w[0] = 0b10110101;
    got = run(80, 0, vlmax, 0, true, 0, 0, vs2, sel, old_vd, maskg);
    int wp = 0;
    for (int i = 0; i < vlmax; ++i) {
      if ((sel.w[0] >> i) & 1) {
        CHECK(GetEl(got, wp, sew) == GetEl(vs2, i, sew));
        ++wp;
      }
    }
    // Sign extend vf2 (e16 -> e32, sub=7) and zero (sub=6).
    Group ext2;
    for (int i = 0; i < vlmax; ++i) {
      SetEl(ext2, i, 16, static_cast<uint64_t>(0x8000 + i));
    }
    got = run(43, 0, vlmax, 0, true, 7, 0, ext2, vs1, old_vd, maskg);
    for (int i = 0; i < vlmax; ++i) {
      CHECK(GetEl(got, i, sew) ==
            (static_cast<uint64_t>(SextEl(GetEl(ext2, i, 16), 16)) &
             0xffffffffull));
    }
    got = run(43, 0, vlmax, 0, true, 6, 0, ext2, vs1, old_vd, maskg);
    for (int i = 0; i < vlmax; ++i) {
      CHECK(GetEl(got, i, sew) == GetEl(ext2, i, 16));
    }
  }

  // ---- FP vector directed checks (stage 9, issue #29) ----
  // Host IEEE float/double is the oracle at RNE for value
  // checks; special values use explicit expected constants.
  {
    auto fbits = [](float f) {
      uint32_t u; std::memcpy(&u, &f, 4); return u;
    };
    auto dbits = [](double f) {
      uint64_t u; std::memcpy(&u, &f, 8); return u;
    };
    auto asf = [](uint32_t u) {
      float f; std::memcpy(&f, &u, 4); return f;
    };
    auto asd = [](uint64_t u) {
      double f; std::memcpy(&f, &u, 8); return f;
    };
    int flast = 0;
    auto frun = [&](int vop, int form, int sew_code, uint64_t vl,
                    uint64_t vstart, bool vm, uint64_t imm,
                    uint64_t scalar, const Group& vs2,
                    const Group& vs1, const Group& old_vd,
                    const Group& maskg) {
      d->op_i = vop; d->form_i = form; d->sew_i = sew_code;
      d->vl_i = vl; d->vstart_i = vstart; d->vlmax_i = 8;
      d->vta_i = 0; d->vma_i = 0; d->vm_i = vm;
      d->vxrm_i = 0; d->frm_i = 0;
      for (int i = 0; i < 16; ++i) {
        d->mask_i[i] =
            static_cast<uint32_t>(maskg.w[i / 2] >> (32 * (i % 2)));
      }
      PutGroup(d->vs2_i, vs2); PutGroup(d->vs1_i, vs1);
      PutGroup(d->old_vd_i, old_vd);
      d->scalar_i = scalar; d->imm_i = imm;
      d->eval();
      flast = d->fflags_o;
      return FetchGroup(d->result_o);
    };
    const int S32 = 2, D64 = 3;  // sew codes
    // vfadd/sub/mul/div .vv single, masked with prestart.
    for (int fop = 0; fop <= 3; ++fop) {
      Group a, b, old, m;
      const float av[8] = {1.5f, -2.25f, 0.5f, 100.0f,
                           -0.0f, 3.25f, 1e10f, 7.0f};
      const float bv[8] = {0.25f, 2.0f, -4.0f, 0.5f,
                           1.0f, -3.25f, 3.0f, 0.0f};
      for (int i = 0; i < 8; ++i) {
        SetEl(a, i, 32, fbits(av[i])); SetEl(b, i, 32, fbits(bv[i]));
        SetEl(old, i, 32, 0xeeee0000u + i);
      }
      m.w[0] = 0b11010110;
      Group got = frun(88, 0, S32, 7, 1, false, fop, 0, a, b, old, m);
      for (int i = 0; i < 8; ++i) {
        const bool active = i >= 1 && i < 7 && ((m.w[0] >> i) & 1);
        float want = 0;
        if (fop == 0) want = av[i] + bv[i];
        if (fop == 1) want = av[i] - bv[i];
        if (fop == 2) want = av[i] * bv[i];
        if (fop == 3) want = av[i] / bv[i];
        CHECK(GetEl(got, i, 32) ==
              (active ? fbits(want) : 0xeeee0000u + i));
      }
    }
    // vfdiv.vv double incl. div-by-zero -> inf + DZ, 0/0 -> NV.
    {
      Group a, b, old, m;
      const double av[4] = {1.0, 0.0, -5.0, 2.5};
      const double bv[4] = {0.0, 0.0, 2.0, 0.5};
      for (int i = 0; i < 4; ++i) {
        SetEl(a, i, 64, dbits(av[i])); SetEl(b, i, 64, dbits(bv[i]));
      }
      m.w[0] = 0xf;
      Group got = frun(88, 0, D64, 4, 0, true, 3, 0, a, b, old, m);
      CHECK(GetEl(got, 0, 64) == 0x7ff0000000000000ull);
      CHECK(GetEl(got, 1, 64) == 0x7ff8000000000000ull);
      CHECK(GetEl(got, 2, 64) == dbits(-2.5));
      CHECK(GetEl(got, 3, 64) == dbits(5.0));
      CHECK((flast & 0x10) != 0);  // NV
      CHECK((flast & 0x08) != 0);  // DZ
    }
    // vfmul.vf: scalar from FP reg (NaN-boxed single).
    {
      Group a, b, old, m;
      for (int i = 0; i < 8; ++i) SetEl(a, i, 32, fbits(0.5f * i));
      m.w[0] = 0xff;
      Group got = frun(88, 1, S32, 8, 0, true, 2,
                       (0xffffffffull << 32) | fbits(4.0f), a, b, old, m);
      for (int i = 0; i < 8; ++i) {
        CHECK(GetEl(got, i, 32) == fbits(0.5f * i * 4.0f));
      }
    }
    // vfmacc.vv single and vfnmsac.vf double (host fma).
    {
      Group a, b, c, m;
      for (int i = 0; i < 8; ++i) {
        SetEl(a, i, 32, fbits(1.0f + 0.25f * i));
        SetEl(b, i, 32, fbits(2.0f - 0.5f * i));
        SetEl(c, i, 32, fbits(0.125f * i));
      }
      m.w[0] = 0xff;
      Group got = frun(90, 0, S32, 8, 0, true, 0, 0, a, b, c, m);
      for (int i = 0; i < 8; ++i) {
        CHECK(GetEl(got, i, 32) ==
              fbits(std::fma(asf(fbits(1.0f + 0.25f * i)),
                             asf(fbits(2.0f - 0.5f * i)),
                             asf(fbits(0.125f * i)))));
      }
      Group a2, c2;
      for (int i = 0; i < 4; ++i) {
        SetEl(a2, i, 64, dbits(1.5 + i));
        SetEl(c2, i, 64, dbits(10.0 - i));
      }
      // vfnmsac (funct6 low bits 11): vd = -(vs2*rs) + vd.
      got = frun(90, 1, D64, 4, 0, true, (3 << 5), dbits(0.5), a2, b,
                 c2, m);
      for (int i = 0; i < 4; ++i) {
        CHECK(GetEl(got, i, 64) ==
              dbits(std::fma(-asd(dbits(1.5 + i)), 0.5,
                             asd(dbits(10.0 - i)))));
      }
      // vfnmacc (funct6 low bits 01): vd = -(vs2*rs) - vd.
      got = frun(90, 1, D64, 4, 0, true, (1 << 5), dbits(0.5), a2, b,
                 c2, m);
      for (int i = 0; i < 4; ++i) {
        CHECK(GetEl(got, i, 64) ==
              dbits(std::fma(-asd(dbits(1.5 + i)), 0.5,
                             -asd(dbits(10.0 - i)))));
      }
    }
    // vmflt.vv + vmfeq.vf (mask dest; NaN: lt false + NV).
    {
      Group a, b, old, m;
      const float av[8] = {1, 2, 3, 4, 5, 6, 7, 8};
      for (int i = 0; i < 8; ++i) {
        SetEl(a, i, 32, fbits(av[i])); SetEl(b, i, 32, fbits(4.5f));
        SetEl(old, i, 32, 0);
      }
      SetEl(a, 6, 32, 0x7fc00000u);  // qNaN element
      m.w[0] = 0xff;
      Group got = frun(92, 0, S32, 8, 0, true, 2, 0, a, b, old, m);
      CHECK((got.w[0] & 0xff) == 0b00001111);
      CHECK((flast & 0x10) != 0);  // signaling compare NV
      got = frun(92, 1, S32, 8, 0, true, 0,
                 (0xffffffffull << 32) | fbits(4.0f), a, b, old, m);
      CHECK((got.w[0] & 0xff) == 0b00001000);
      CHECK((flast & 0x10) == 0);  // qNaN quiet for feq
    }
    // vfsqrt.v / vfclass.v.
    {
      Group a, b, old, m;
      const float av[8] = {4.0f, 2.0f, -1.0f, 0.0f,
                           1.0f / 0.0f, -0.0f, 1e-42f, 9.0f};
      for (int i = 0; i < 8; ++i) SetEl(a, i, 32, fbits(av[i]));
      m.w[0] = 0xff;
      Group got = frun(93, 0, S32, 8, 0, true, 0, 0, a, b, old, m);
      CHECK(GetEl(got, 0, 32) == fbits(2.0f));
      CHECK(GetEl(got, 1, 32) == fbits(std::sqrt(2.0f)));
      CHECK(GetEl(got, 2, 32) == 0x7fc00000u);
      CHECK((flast & 0x10) != 0);  // sqrt(-1) NV
      got = frun(93, 0, S32, 8, 0, true, 1, 0, a, b, old, m);
      const uint32_t cls[8] = {1u << 6, 1u << 6, 1u << 1, 1u << 4,
                               1u << 7, 1u << 3, 1u << 5, 1u << 6};
      for (int i = 0; i < 8; ++i) CHECK(GetEl(got, i, 32) == cls[i]);
    }
    // vfwadd.vv (S->D) and vfwadd.wv, vfwmacc.vf.
    {
      Group a, b, old, m;
      const float av[4] = {0.1f, 1.5f, -2.5f, 100.0f};
      const float bv[4] = {0.2f, 0.5f, 2.5f, 0.25f};
      for (int i = 0; i < 4; ++i) {
        SetEl(a, i, 32, fbits(av[i])); SetEl(b, i, 32, fbits(bv[i]));
      }
      m.w[0] = 0xf;
      Group got = frun(89, 0, S32, 4, 0, true, 0, 0, a, b, old, m);
      for (int i = 0; i < 4; ++i) {
        CHECK(GetEl(got, i, 64) ==
              dbits(static_cast<double>(av[i]) +
                    static_cast<double>(bv[i])));
      }
      Group aw_;
      const double ad[4] = {1.25, -0.5, 3.0, 7.5};
      for (int i = 0; i < 4; ++i) SetEl(aw_, i, 64, dbits(ad[i]));
      got = frun(89, 0, S32, 4, 0, true, (1 << 7) | 1, 0, aw_, b, old,
                 m);  // vfwsub.wv
      for (int i = 0; i < 4; ++i) {
        CHECK(GetEl(got, i, 64) ==
              dbits(ad[i] - static_cast<double>(bv[i])));
      }
      Group c;
      for (int i = 0; i < 4; ++i) SetEl(c, i, 64, dbits(1.0 * i));
      got = frun(91, 1, S32, 4, 0, true, 0,
                 (0xffffffffull << 32) | fbits(2.0f), a, b, c, m);
      for (int i = 0; i < 4; ++i) {
        CHECK(GetEl(got, i, 64) ==
              dbits(std::fma(static_cast<double>(av[i]), 2.0, 1.0 * i)));
      }
    }
    // Conversions: f.xu, x.f, rtz x.f, f.f narrow, x.f.w narrow.
    {
      Group a, b, old, m;
      const uint32_t iv[8] = {0, 1, 7, 100000, 0x80000000u,
                              3, 17, 0xfffffff0u};
      for (int i = 0; i < 8; ++i) SetEl(a, i, 32, iv[i]);
      m.w[0] = 0xff;
      Group got = frun(94, 0, S32, 8, 0, true, 2, 0, a, b, old, m);
      for (int i = 0; i < 8; ++i) {
        CHECK(GetEl(got, i, 32) ==
              fbits(static_cast<float>(iv[i])));
      }
      const float fv[8] = {1.5f, -1.5f, 2.5f, -2.5f,
                           0.5f, 100.75f, -0.25f, 3.5f};
      Group fa_;
      for (int i = 0; i < 8; ++i) SetEl(fa_, i, 32, fbits(fv[i]));
      got = frun(94, 0, S32, 8, 0, true, 1, 0, fa_, b, old, m);
      const int32_t xwant[8] = {2, -2, 2, -2, 0, 101, 0, 4};  // RNE
      for (int i = 0; i < 8; ++i) {
        CHECK(GetEl(got, i, 32) ==
              static_cast<uint32_t>(xwant[i]));
      }
      got = frun(94, 0, S32, 8, 0, true, 7, 0, fa_, b, old, m);
      const int32_t zwant[8] = {1, -1, 2, -2, 0, 100, 0, 3};  // RTZ
      for (int i = 0; i < 8; ++i) {
        CHECK(GetEl(got, i, 32) ==
              static_cast<uint32_t>(zwant[i]));
      }
      Group da;
      const double dv[4] = {0.1, -3.75, 1e300, 2.5};
      for (int i = 0; i < 4; ++i) SetEl(da, i, 64, dbits(dv[i]));
      got = frun(94, 0, S32, 4, 0, true, 20, 0, da, b, old, m);
      for (int i = 0; i < 4; ++i) {
        CHECK(GetEl(got, i, 32) ==
              fbits(static_cast<float>(dv[i])));
      }
      got = frun(94, 0, S32, 4, 0, true, 17, 0, da, b, old, m);
      const int32_t nwant[4] = {0, -4, INT32_MAX, 2};
      for (int i = 0; i < 4; ++i) {
        CHECK(GetEl(got, i, 32) ==
              static_cast<uint32_t>(nwant[i]));
      }
    }
    // vfredusum / vfredmax / vfwredusum (sequential fold).
    {
      Group a, seed, old, m;
      const float av[8] = {1, 2, 4, 8, 16, 32, 64, 128};
      for (int i = 0; i < 8; ++i) SetEl(a, i, 32, fbits(av[i]));
      SetEl(seed, 0, 32, fbits(0.5f));
      m.w[0] = 0b01111101;  // skip elements 1 and 7
      Group got = frun(95, 0, S32, 8, 0, false, 0, 0, a, seed, old,
                       m);
      CHECK(GetEl(got, 0, 32) == fbits(0.5f + 1 + 4 + 8 + 16 + 32 + 64));
      got = frun(95, 0, S32, 8, 0, false, 3, 0, a, seed, old, m);
      CHECK(GetEl(got, 0, 32) == fbits(64.0f));
      Group dseed;
      SetEl(dseed, 0, 64, dbits(0.25));
      got = frun(96, 0, S32, 8, 0, true, 0, 0, a, dseed, old, m);
      CHECK(GetEl(got, 0, 64) == dbits(255.25));
    }
    // vfrec7 / vfrsqrt7 spot values (incl. specials; the
    // full tables are Sail-verified by probe + ACT).
    {
      Group a, b, old, m;
      const uint32_t in[8] = {0x3f800000, 0x40000000, 0x00000001,
                              0x7f800000, 0x00000000, 0x80000000,
                              0x7fc00000, 0xbf800000};
      for (int i = 0; i < 8; ++i) SetEl(a, i, 32, in[i]);
      m.w[0] = 0xff;
      Group got = frun(93, 0, S32, 8, 0, true, 3, 0, a, b, old, m);
      const uint32_t recw[8] = {0x3f7f0000, 0x3eff0000, 0x7f800000,
                                0x00000000, 0x7f800000, 0xff800000,
                                0x7fc00000, 0xbf7f0000};
      for (int i = 0; i < 8; ++i) CHECK(GetEl(got, i, 32) == recw[i]);
      CHECK((flast & 0x0d) == 0x0d);  // DZ + OF + NX accrued
      got = frun(93, 0, S32, 8, 0, true, 2, 0, a, b, old, m);
      const uint32_t rsqw[8] = {0x3f7f0000, 0x3f340000, 0x64b40000,
                                0x00000000, 0x7f800000, 0xff800000,
                                0x7fc00000, 0x7fc00000};
      for (int i = 0; i < 8; ++i) CHECK(GetEl(got, i, 32) == rsqw[i]);
      CHECK((flast & 0x18) == 0x18);  // NV + DZ accrued
      // vfncvt.rod.f.f.w: inexact results get odd LSB, exact
      // results unchanged, overflow saturates to max finite.
      Group da;
      const double dv[4] = {1.0 + 0x1p-30, 1.5, 1e300, -1e300};
      for (int i = 0; i < 4; ++i) SetEl(da, i, 64, dbits(dv[i]));
      got = frun(94, 0, S32, 4, 0, true, 21, 0, da, b, old, m);
      CHECK(GetEl(got, 0, 32) == 0x3f800001u);  // 1.0 | 1 (odd)
      CHECK(GetEl(got, 1, 32) == fbits(1.5f));
      CHECK(GetEl(got, 2, 32) == 0x7f7fffffu);
      CHECK(GetEl(got, 3, 32) == 0xff7fffffu);
    }
    // vfmv.f.s scalar result is NaN-boxed element 0.
    {
      Group a, b, old, m;
      SetEl(a, 0, 32, 0x80000000u);
      (void)frun(97, 0, S32, 4, 0, true, 0, 0, a, b, old, m);
      CHECK(d->scalar_o == 0xffffffff80000000ull);
    }
  }

  d->final();
  VerilatedCov::write(getenv("COV_FILE") ? getenv("COV_FILE")
                                         : "cov_vec.dat");
  delete d;
  if (failures == 0) {
    std::printf("VEC TB PASS (%d checks)\n", checks);
    return 0;
  }
  std::printf("VEC TB FAIL (%d failures)\n", failures);
  return 1;
}
