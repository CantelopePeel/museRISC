// Core-level harness for muserisc_core (stage 1). Models the
// combinational-read Harvard SRAM the core expects (see
// docs/CORE.md): RAM at 0, program binary loaded at 0, a store to
// EXIT_ADDR ends the test (0 = pass, nonzero = failing test number),
// and trap_o ends it with the cause reported.
//
// Usage: core_tb <program.bin> [max_cycles] [--expect-trap CAUSE]
// Exit status: 0 pass, 1 test failure, 2 timeout, 3 unexpected trap.
#include "Vmuserisc_core.h"
#include "verilated.h"
#include "verilated_cov.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <vector>

namespace {
constexpr uint64_t kRamSize = 16ull << 20;  // 16 MiB
constexpr uint64_t kExitAddr = 0x10000000ULL;

uint64_t Read64(const std::vector<uint8_t>& mem, uint64_t addr) {
  uint64_t v = 0;
  for (int i = 7; i >= 0; --i) {
    v = (v << 8) | (addr + static_cast<uint64_t>(i) < mem.size()
                        ? mem[addr + static_cast<uint64_t>(i)]
                        : 0);
  }
  return v;
}
}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    std::fprintf(stderr, "usage: %s <program.bin> [max_cycles] [--expect-trap CAUSE]\n", argv[0]);
    return 2;
  }
  const char* prog_path = argv[1];
  uint64_t max_cycles = 1000000;
  long expect_trap = -1;
  long irq_timer_after = -1;
  bool trace = std::getenv("CORE_TB_TRACE") != nullptr;
  for (int i = 2; i < argc; ++i) {
    if (std::strcmp(argv[i], "--expect-trap") == 0 && i + 1 < argc) {
      expect_trap = std::atol(argv[++i]);
    } else if (std::strcmp(argv[i], "--irq-timer-after") == 0 && i + 1 < argc) {
      irq_timer_after = std::atol(argv[++i]);
    } else if (std::strcmp(argv[i], "--trace") == 0) {
      trace = true;
    } else {
      max_cycles = std::strtoull(argv[i], nullptr, 0);
    }
  }

  std::vector<uint8_t> mem(kRamSize, 0);
  FILE* f = std::fopen(prog_path, "rb");
  if (f == nullptr) {
    std::fprintf(stderr, "cannot open %s\n", prog_path);
    return 2;
  }
  const size_t loaded = std::fread(mem.data(), 1, mem.size(), f);
  std::fclose(f);
  if (loaded == 0) {
    std::fprintf(stderr, "empty program %s\n", prog_path);
    return 2;
  }

  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vmuserisc_core> dut{new Vmuserisc_core{&context}};
  const char* cov_path = std::getenv("COV_FILE");

  auto finish = [&](int rc) {
    dut->final();
    if (cov_path != nullptr) context.coveragep()->write(cov_path);
    return rc;
  };

  dut->clk_i = 0;
  dut->rst_ni = 0;
  dut->imem_rdata_i = 0;
  dut->dmem_rdata_i = 0;
  // Legacy --expect-trap runs freeze at the first trap; normal
  // runs let the core take traps to its handlers.
  dut->trap_halt_i = (expect_trap >= 0) ? 1 : 0;
  dut->irq_m_timer_i = 0;
  dut->irq_m_soft_i = 0;
  dut->irq_m_ext_i = 0;
  dut->irq_s_timer_i = 0;
  dut->irq_s_ext_i = 0;
  bool irq_active = false;
  // Pulse every IRQ pin once while still in reset (mie = 0, so no
  // trap can be taken) so the level inputs exercised only by the
  // unit testbench still toggle through the core pins.
  dut->irq_m_soft_i = 1;
  dut->irq_m_ext_i = 1;
  dut->irq_s_timer_i = 1;
  dut->irq_s_ext_i = 1;
  for (int i = 0; i < 4; ++i) {
    dut->clk_i = static_cast<uint8_t>(i & 1);
    dut->eval();
  }
  dut->irq_m_soft_i = 0;
  dut->irq_m_ext_i = 0;
  dut->irq_s_timer_i = 0;
  dut->irq_s_ext_i = 0;
  dut->eval();
  dut->rst_ni = 1;

  for (uint64_t cycle = 0; cycle < max_cycles; ++cycle) {
    if (irq_timer_after >= 0 &&
        cycle >= static_cast<uint64_t>(irq_timer_after) && !irq_active) {
      dut->irq_m_timer_i = 1;
      irq_active = true;
    }
    if (irq_active && dut->trap_o) {
      dut->irq_m_timer_i = 0;  // level interrupt: clear once taken
      irq_active = false;
      irq_timer_after = -1;
    }
    // Combinational memory phase (clock low). Two settles: first
    // present the instruction so the core drives this cycle's data
    // address, then present the data for that address. Presenting
    // both before a single eval would serve the previous address.
    dut->clk_i = 0;
    dut->imem_rdata_i = static_cast<uint32_t>(Read64(mem, dut->imem_addr_o & ~7ull) >>
                                              ((dut->imem_addr_o & 7ull) * 8));
    dut->eval();
    dut->dmem_rdata_i = Read64(mem, dut->dmem_addr_o & ~7ull);
    dut->eval();
    if (trace) {
      std::printf("cy %4llu pc 0x%04lx insn 0x%08x daddr 0x%lx be 0x%02x wdata 0x%016lx re %d\n",
                  static_cast<unsigned long long>(cycle),
                  static_cast<unsigned long>(dut->imem_addr_o), dut->imem_rdata_i,
                  static_cast<unsigned long>(dut->dmem_addr_o), dut->dmem_be_o,
                  static_cast<unsigned long>(dut->dmem_wdata_o),
                  dut->dmem_re_o ? 1 : 0);
    }

    if (dut->trap_o && expect_trap >= 0) {
      const uint64_t cause = dut->trap_cause_o;
      if (cause == static_cast<uint64_t>(expect_trap)) {
        std::printf("CORE TB PASS %s (expected trap cause %llu at pc 0x%lx, %llu cycles)\n",
                    prog_path, static_cast<unsigned long long>(cause),
                    static_cast<unsigned long>(dut->trap_pc_o),
                    static_cast<unsigned long long>(cycle));
        return finish(0);
      }
      std::printf("CORE TB TRAP %s cause=%llu pc=0x%lx cycle=%llu\n", prog_path,
                  static_cast<unsigned long long>(cause),
                  static_cast<unsigned long>(dut->trap_pc_o),
                  static_cast<unsigned long long>(cycle));
      return finish(3);
    }

    // Clock rising edge: register write and PC update happen now;
    // apply the (combinationally decoded) store exactly once.
    const uint64_t daddr = dut->dmem_addr_o;
    const uint8_t be = dut->dmem_be_o;
    const uint64_t wdata = dut->dmem_wdata_o;
    dut->clk_i = 1;
    dut->eval();
    if (be != 0) {
      if (daddr == kExitAddr) {
        const long code = static_cast<long>(wdata & 0xffffffffULL);
        if (code == 0) {
          std::printf("CORE TB PASS %s (%llu cycles)\n", prog_path,
                      static_cast<unsigned long long>(cycle + 1));
          return finish(0);
        }
        std::printf("CORE TB FAIL %s test %ld (%llu cycles)\n", prog_path, code,
                    static_cast<unsigned long long>(cycle + 1));
        return finish(1);
      }
      const uint64_t base = daddr & ~7ull;
      for (int i = 0; i < 8; ++i) {
        if ((be & (1u << i)) != 0 && base + static_cast<uint64_t>(i) < mem.size()) {
          mem[base + static_cast<uint64_t>(i)] =
              static_cast<uint8_t>(wdata >> (8 * i));
        }
      }
    }
  }
  std::printf("CORE TB TIMEOUT %s after %llu cycles (pc 0x%lx)\n", prog_path,
              static_cast<unsigned long long>(max_cycles),
              static_cast<unsigned long>(dut->imem_addr_o));
  return finish(2);
}
