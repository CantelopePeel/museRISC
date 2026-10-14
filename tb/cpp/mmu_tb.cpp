// Unit test for muserisc_mmu: Sv39 walks, superpages, Svnapot,
// permission matrix (U/SUM/MXR), hardware A/D updates, TLB
// ASID/global/flush semantics, and the fault taxonomy — against
// a byte memory in the TB holding hand-built page tables.
#include "Vmuserisc_mmu.h"
#include "verilated.h"
#include "verilated_cov.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <vector>

static uint64_t g_checks = 0;
static bool g_fail = false;

#define CHECK(cond)                                                     \
  do {                                                                  \
    ++g_checks;                                                         \
    if (!(cond)) {                                                      \
      std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);       \
      g_fail = true;                                                    \
      return 1;                                                         \
    }                                                                   \
  } while (0)

namespace {
// PTE flag bits.
constexpr uint64_t kV = 1, kR = 2, kW = 4, kX = 8, kU = 16, kG = 32,
                   kA = 64, kD = 128;
constexpr uint64_t kRootPa = 0x10000;   // root table (ppn 0x10)
constexpr uint64_t kL1Pa = 0x11000;
constexpr uint64_t kL0Pa = 0x12000;
uint64_t Pte(uint64_t pa, uint64_t flags) { return (pa >> 2) | flags; }
uint64_t Satp(uint16_t asid) {
  return (8ull << 60) | (uint64_t(asid) << 44) | (kRootPa >> 12);
}
}  // namespace

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vmuserisc_mmu> d{new Vmuserisc_mmu{&context}};
  const char* cov_path = std::getenv("COV_FILE");

  std::vector<uint8_t> mem(1u << 20, 0);
  auto rd64 = [&](uint64_t pa) {
    uint64_t v = 0;
    for (int i = 7; i >= 0; --i)
      v = (v << 8) | (pa + uint64_t(i) < mem.size() ? mem[pa + uint64_t(i)] : 0);
    return v;
  };
  auto wr64 = [&](uint64_t pa, uint64_t v) {
    for (int i = 0; i < 8; ++i)
      if (pa + uint64_t(i) < mem.size())
        mem[pa + uint64_t(i)] = uint8_t(v >> (8 * i));
  };
  int pmp_mode = 0;  // 0 allow, 2 deny A/D writebacks only
  auto tick = [&]() {
    // Combinational port service, then the clock edge applies
    // an A/D writeback exactly once.
    d->clk_i = 0;
    d->walk_rdata_i = rd64(d->walk_addr_o & ~7ull);
    d->eval();
    if (pmp_mode == 2) {
      d->walk_pmp_allow_i = d->walk_we_o ? 0 : 1;
      d->eval();
    }
    // Model the core: byte enables are PMP-gated, so a denied
    // writeback never reaches memory.
    const bool we = d->walk_req_o && d->walk_we_o && d->walk_grant_i &&
                    d->walk_pmp_allow_i;
    const uint64_t wa = d->walk_addr_o, wd = d->walk_wdata_o;
    d->clk_i = 1;
    d->eval();
    if (we) wr64(wa & ~7ull, wd);
    d->clk_i = 0;
    d->eval();
  };
  // A delivered fault is held until the core takes the trap;
  // model that consumption with an abort pulse.
  auto consume_fault = [&]() {
    d->abort_i = 1;
    tick();
    d->abort_i = 0;
    d->eval();
  };
  // Translate on the fetch port. Returns 0 ok (*pa set), 1 page
  // fault, 2 access fault, 3 timeout.
  auto xlate_if = [&](uint64_t va, int priv, uint64_t* pa) {
    d->if_va_i = va;
    d->if_priv_i = uint8_t(priv);
    for (int i = 0; i < 40; ++i) {
      d->eval();
      if (d->if_ok_o) { *pa = d->if_pa_o; return 0; }
      if (d->if_fault_o) {
        const int rc = d->if_fault_page_o ? 1 : 2;
        consume_fault();
        return rc;
      }
      tick();
    }
    return 3;
  };
  auto xlate_d = [&](uint64_t va, bool write, int priv, uint64_t* pa) {
    d->d_va_i = va;
    d->d_write_i = write ? 1 : 0;
    d->d_priv_i = uint8_t(priv);
    d->d_valid_i = 1;
    int rc = 3;
    for (int i = 0; i < 40; ++i) {
      d->eval();
      if (d->d_ok_o) { *pa = d->d_pa_o; rc = 0; break; }
      if (d->d_fault_o) { rc = d->d_fault_page_o ? 1 : 2; break; }
      tick();
    }
    d->d_valid_i = 0;
    d->eval();
    if (rc == 1 || rc == 2) consume_fault();
    return rc;
  };
  auto flush_tlb = [&]() {
    d->flush_i = 1;
    tick();
    d->flush_i = 0;
    d->eval();
  };

  // Init + reset.
  d->clk_i = 0; d->rst_ni = 0; d->satp_i = 0; d->sum_i = 0; d->mxr_i = 0;
  d->flush_i = 0; d->abort_i = 0;
  d->if_va_i = 0; d->if_priv_i = 3;
  d->d_va_i = 0; d->d_write_i = 0; d->d_priv_i = 3; d->d_valid_i = 0;
  d->walk_grant_i = 1; d->walk_rdata_i = 0; d->walk_pmp_allow_i = 1;
  tick(); tick();
  d->rst_ni = 1;
  d->eval();

  uint64_t pa = 0;
  // Bare mode and M-mode pass through untouched.
  CHECK(xlate_if(0xdead0000ull, 1, &pa) == 0 && pa == 0xdead0000ull);
  CHECK(xlate_d(0x12345000ull, true, 0, &pa) == 0 && pa == 0x12345000ull);
  d->satp_i = Satp(0);
  CHECK(xlate_if(0x400000ull, 3, &pa) == 0 && pa == 0x400000ull);

  // Page tables: VA 0x400000 (idx 0/2/0) -> PA 0x20000, S RW page.
  wr64(kRootPa + 0 * 8, Pte(kL1Pa, kV));
  wr64(kL1Pa + 2 * 8, Pte(kL0Pa, kV));
  wr64(kL0Pa + 0 * 8, Pte(0x20000, kV | kR | kW | kA | kD));
  CHECK(xlate_d(0x400123ull, false, 1, &pa) == 0 && pa == 0x20123ull);
  CHECK(xlate_d(0x400123ull, true, 1, &pa) == 0 && pa == 0x20123ull);
  CHECK(xlate_d(0x400123ull, false, 0, &pa) == 1);  // U into S page
  CHECK(xlate_if(0x400000ull, 1, &pa) == 1);        // no X
  // Unmapped neighbors fault at L0 (!V) and L1 (missing pointer).
  CHECK(xlate_d(0x401000ull, false, 1, &pa) == 1);
  CHECK(xlate_d(0x600000ull, false, 1, &pa) == 1);
  // Non-canonical Sv39 VA faults without walking.
  CHECK(xlate_d(1ull << 39, false, 1, &pa) == 1);
  CHECK(xlate_if(0x8000000000000000ull, 1, &pa) == 1);

  // Hardware A/D: clear both, flush, read sets A only, then a
  // store re-walks (TLB D=0) and sets D in memory too.
  wr64(kL0Pa + 0 * 8, Pte(0x20000, kV | kR | kW));
  flush_tlb();
  CHECK(xlate_d(0x400000ull, false, 1, &pa) == 0);
  CHECK((rd64(kL0Pa) & (kA | kD)) == kA);
  CHECK(xlate_d(0x400000ull, true, 1, &pa) == 0);
  CHECK((rd64(kL0Pa) & (kA | kD)) == (kA | kD));

  // U page at L0[1] -> PA 0x21000: U ok, S needs SUM, S fetch never.
  wr64(kL0Pa + 1 * 8, Pte(0x21000, kV | kR | kW | kX | kU | kA | kD));
  CHECK(xlate_d(0x401000ull, false, 0, &pa) == 0 && pa == 0x21000ull);
  CHECK(xlate_if(0x401000ull, 0, &pa) == 0 && pa == 0x21000ull);
  CHECK(xlate_d(0x401000ull, false, 1, &pa) == 1);
  d->sum_i = 1;
  CHECK(xlate_d(0x401000ull, false, 1, &pa) == 0);
  CHECK(xlate_if(0x401000ull, 1, &pa) == 1);
  d->sum_i = 0;
  // MXR: X-only S page at L0[2] readable by loads only with MXR.
  wr64(kL0Pa + 2 * 8, Pte(0x22000, kV | kX | kA | kD));
  flush_tlb();
  CHECK(xlate_d(0x402000ull, false, 1, &pa) == 1);
  d->mxr_i = 1;
  CHECK(xlate_d(0x402000ull, false, 1, &pa) == 0 && pa == 0x22000ull);
  d->mxr_i = 0;
  CHECK(xlate_if(0x402000ull, 1, &pa) == 0);

  // Malformed PTEs: W without R, reserved bits, NAPOT misuse,
  // non-leaf at L0, non-leaf with A set.
  wr64(kL0Pa + 3 * 8, Pte(0x23000, kV | kW | kA | kD));
  CHECK(xlate_d(0x403000ull, false, 1, &pa) == 1);
  wr64(kL0Pa + 3 * 8, Pte(0x23000, kV | kR | kA | kD) | (1ull << 55));
  CHECK(xlate_d(0x403000ull, false, 1, &pa) == 1);
  wr64(kL0Pa + 3 * 8, Pte(0x23000, kV | kR | kA | kD) | (1ull << 63));
  CHECK(xlate_d(0x403000ull, false, 1, &pa) == 1);  // N with ppn[3:0]!=8
  wr64(kL0Pa + 3 * 8, Pte(kL1Pa, kV));              // pointer at leaf level
  CHECK(xlate_d(0x403000ull, false, 1, &pa) == 1);
  wr64(kL1Pa + 3 * 8, Pte(kL0Pa, kV | kA));         // non-leaf A set
  CHECK(xlate_d(0x600000ull, false, 1, &pa) == 1);
  wr64(kL1Pa + 3 * 8, 0);

  // 2M superpage: L1[1] leaf -> PA 0x200000 RWX; misaligned faults.
  wr64(kL1Pa + 1 * 8, Pte(0x200000, kV | kR | kW | kX | kA | kD));
  CHECK(xlate_if(0x201234ull, 1, &pa) == 0 && pa == 0x201234ull);
  CHECK(xlate_d(0x3ff000ull, true, 1, &pa) == 0 && pa == 0x3ff000ull);
  wr64(kL1Pa + 1 * 8, Pte(0x201000, kV | kR | kW | kX | kA | kD));
  flush_tlb();
  CHECK(xlate_if(0x201234ull, 1, &pa) == 1);
  wr64(kL1Pa + 1 * 8, Pte(0x200000, kV | kR | kW | kX | kA | kD));

  // 1G superpage: root[1] leaf -> PA 0x40000000 X-only.
  wr64(kRootPa + 1 * 8, Pte(0x40000000, kV | kX | kA | kD));
  CHECK(xlate_if(0x40012345ull, 1, &pa) == 0 && pa == 0x40012345ull);
  CHECK(xlate_d(0x40012345ull, false, 1, &pa) == 1);

  // Svnapot 64K: L1[4]->L0b, L0b[0] ppn[3:0]=8 base PA 0x80000.
  const uint64_t kL0b = 0x13000;
  wr64(kL1Pa + 4 * 8, Pte(kL0b, kV));
  wr64(kL0b + 0 * 8, Pte(0x88000, kV | kR | kW | kA | kD) | (1ull << 63));
  flush_tlb();
  CHECK(xlate_d(0x800000ull, false, 1, &pa) == 0 && pa == 0x80000ull);
  CHECK(xlate_d(0x80f234ull, true, 1, &pa) == 0 && pa == 0x8f234ull);
  CHECK(xlate_d(0x810000ull, false, 1, &pa) == 1);  // past 64K

  // ASID isolation: remap under asid 0, then asid 1 must re-walk.
  flush_tlb();
  CHECK(xlate_d(0x400000ull, false, 1, &pa) == 0 && pa == 0x20000ull);
  wr64(kL0Pa + 0 * 8, Pte(0x24000, kV | kR | kW | kA | kD));
  d->satp_i = Satp(1);
  CHECK(xlate_d(0x400000ull, false, 1, &pa) == 0 && pa == 0x24000ull);
  d->satp_i = Satp(0);
  CHECK(xlate_d(0x400000ull, false, 1, &pa) == 0 && pa == 0x20000ull);
  // Global page: fill under asid 0, remap in memory, hit under asid 1.
  wr64(kL0Pa + 4 * 8, Pte(0x25000, kV | kR | kG | kA | kD));
  CHECK(xlate_d(0x404000ull, false, 1, &pa) == 0 && pa == 0x25000ull);
  wr64(kL0Pa + 4 * 8, Pte(0x26000, kV | kR | kG | kA | kD));
  d->satp_i = Satp(7);
  CHECK(xlate_d(0x404000ull, false, 1, &pa) == 0 && pa == 0x25000ull);
  // SFENCE flush makes the new mapping visible.
  flush_tlb();
  CHECK(xlate_d(0x404000ull, false, 1, &pa) == 0 && pa == 0x26000ull);
  d->satp_i = Satp(0);
  wr64(kL0Pa + 0 * 8, Pte(0x20000, kV | kR | kW | kA | kD));

  // Walker port denial (PMP) is an access fault, and a stalled
  // grant simply stretches the walk.
  flush_tlb();
  d->walk_pmp_allow_i = 0;
  CHECK(xlate_d(0x400000ull, false, 1, &pa) == 2);
  d->walk_pmp_allow_i = 1;
  d->walk_grant_i = 0;
  d->d_va_i = 0x400000ull; d->d_write_i = 0; d->d_priv_i = 1; d->d_valid_i = 1;
  for (int i = 0; i < 3; ++i) tick();
  d->eval();
  CHECK(!d->d_ok_o && !d->d_fault_o);
  d->walk_grant_i = 1;
  d->d_valid_i = 0;
  CHECK(xlate_d(0x400000ull, false, 1, &pa) == 0 && pa == 0x20000ull);

  // PMP denial on the A/D writeback itself is an access fault
  // and must leave the PTE (and TLB) untouched.
  wr64(kL0Pa + 6 * 8, Pte(0x27000, kV | kR | kW));  // A/D clear
  pmp_mode = 2;
  CHECK(xlate_d(0x406000ull, false, 1, &pa) == 2);
  CHECK((rd64(kL0Pa + 6 * 8) & (kA | kD)) == 0);
  pmp_mode = 0;
  CHECK(xlate_d(0x406000ull, false, 1, &pa) == 0 && pa == 0x27000ull);
  CHECK((rd64(kL0Pa + 6 * 8) & (kA | kD)) == kA);

  // A fetch walk fault that the requester walks away from (PC
  // changes before any trap) must not negative-cache: after the
  // mapping appears, the same VA translates with no flush/abort.
  d->if_va_i = 0x407000ull;
  d->if_priv_i = 1;
  for (int i = 0; i < 20 && !d->if_fault_o; ++i) tick();
  d->eval();
  CHECK(d->if_fault_o && d->if_fault_page_o);
  wr64(kL0Pa + 7 * 8, Pte(0x28000, kV | kX | kA | kD));
  d->if_va_i = 0x400000ull;  // PC moves on: stale fault drops
  tick();
  CHECK(xlate_if(0x407000ull, 1, &pa) == 0 && pa == 0x28000ull);

  // A data miss preempts an in-flight fetch walk; both complete.
  wr64(kL0Pa + 8 * 8, Pte(0x29000, kV | kX | kA | kD));
  wr64(kL0Pa + 9 * 8, Pte(0x2a000, kV | kR | kA | kD));
  flush_tlb();
  d->if_va_i = 0x408000ull;
  d->if_priv_i = 1;
  d->walk_grant_i = 0;
  tick();  // walker latches the fetch request, holds in W_READ
  d->d_va_i = 0x409000ull;
  d->d_write_i = 0;
  d->d_priv_i = 1;
  d->d_valid_i = 1;
  tick();  // data preempts the fetch walk
  d->walk_grant_i = 1;
  pa = 0;
  for (int i = 0; i < 40 && !d->d_ok_o; ++i) tick();
  d->eval();
  CHECK(d->d_ok_o && d->d_pa_o == 0x2a000ull);
  d->d_valid_i = 0;
  CHECK(xlate_if(0x408000ull, 1, &pa) == 0 && pa == 0x29000ull);

  d->final();
  if (cov_path != nullptr) context.coveragep()->write(cov_path);
  if (g_fail) return 1;
  std::printf("MMU TB PASS (%llu checks)\n",
              static_cast<unsigned long long>(g_checks));
  return 0;
}
