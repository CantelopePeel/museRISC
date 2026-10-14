// Vector execution unit testbench (issue #23, stage 8a):
// independent C++ golden model for the integer ALU + move
// classes over register groups, across SEW, vl/vstart,
// masking, and tail/mask-agnostic policies. The golden model
// is written from the RVV 1.0 element semantics directly
// (per-element arrays), not by mirroring the RTL loop.
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

enum Op { kAdd, kSub, kRsub, kAnd, kOr, kXor, kSll, kSrl, kSra, kMv, kMvSx, kMvXs };

uint64_t GoldenEl(Op op, uint64_t a, uint64_t b, int sew) {
  const int sh = static_cast<int>(b & static_cast<uint64_t>(sew - 1));
  switch (op) {
    case kAdd: return (a + b) & MaskFor(sew);
    case kSub: return (a - b) & MaskFor(sew);
    case kRsub: return (b - a) & MaskFor(sew);
    case kAnd: return a & b;
    case kOr: return a | b;
    case kXor: return a ^ b;
    case kSll: return (a << sh) & MaskFor(sew);
    case kSrl: return (a & MaskFor(sew)) >> sh;
    case kSra: return static_cast<uint64_t>(SextEl(a, sew) >> sh) &
                       MaskFor(sew);
    default: return b & MaskFor(sew);  // moves
  }
}

}  // namespace

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Verilated::mkdir("logs");
  auto* d = new Vmuserisc_vec;
  std::mt19937_64 rng(0x5eed8a);

  const Op kOps[] = {kAdd, kSub, kRsub, kAnd, kOr,  kXor,
                     kSll, kSrl, kSra,  kMv,  kMvSx, kMvXs};
  for (int sew_code = 0; sew_code < 4; ++sew_code) {
    const int sew = 8 << sew_code;
    const int max_el = 4096 / sew;
    for (Op op : kOps) {
      for (int form = 0; form < 3; ++form) {
        if (op == kRsub && form == 0) continue;
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
          if (op == kMvSx) {
            if (vstart == 0 && vl > 0 && (vm || mask_bit(0))) {
              SetEl(want, 0, sew, scalar);
            }
          } else if (op != kMvXs) {
            for (int i = 0; i < max_el; ++i) {
              if (static_cast<uint64_t>(i) < vstart) continue;
              const bool active = static_cast<uint64_t>(i) < vl &&
                                  (vm || mask_bit(i));
              if (active) {
                const uint64_t a = GetEl(vs2, i, sew);
                const uint64_t b = form == 0 ? GetEl(vs1, i, sew)
                                   : form == 1 ? scalar
                                               : static_cast<uint64_t>(imm);
                SetEl(want, i, sew, GoldenEl(op, a, b, sew));
              } else if (static_cast<uint64_t>(i) >= vl) {
                if (vta) SetEl(want, i, sew, MaskFor(sew));
              } else if (vma) {
                SetEl(want, i, sew, MaskFor(sew));
              }
            }
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
