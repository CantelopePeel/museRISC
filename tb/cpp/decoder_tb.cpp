// Unit test for muserisc_decoder: sweeps opcode x funct3 x funct7
// space (plus immediate-pattern corners) against a golden model
// formulated directly as the RV64I encoding whitelist from the ISA
// manual, independent of the RTL's case structure. Checks the full
// control struct and the selected immediate. Exits 0 on pass.
#include "Vmuserisc_decoder.h"
#include "verilated.h"
#include "verilated_cov.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>

namespace {
enum AluOp { ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND, COPY_B };

struct Ctrl {
  bool valid = false, reg_write = false, mem_read = false, mem_write = false;
  bool alu_src_imm = false, alu_a_pc = false, word_op = false, muldiv = false;
  bool csr = false, csr_imm = false, mret = false, sret = false;
  bool wfi = false, sfence = false;
  int alu_op = ADD;
  bool branch = false, jal = false, jalr = false, ecall = false, ebreak = false;
  uint64_t imm = 0;
};

int AluFor(int funct3, bool alt) {
  switch (funct3) {
    case 0: return alt ? SUB : ADD;
    case 1: return SLL;
    case 2: return SLT;
    case 3: return SLTU;
    case 4: return XOR;
    case 5: return alt ? SRA : SRL;
    case 6: return OR;
    default: return AND;
  }
}

uint64_t Sext(uint64_t v, int bits) {
  const uint64_t m = 1ull << (bits - 1);
  return (v ^ m) - m;
}

Ctrl Golden(uint32_t insn) {
  Ctrl c;
  const uint32_t op = insn & 0x7f;
  const uint32_t f3 = (insn >> 12) & 7;
  const uint32_t f7 = (insn >> 25) & 0x7f;
  const uint64_t imm_i = Sext(insn >> 20, 12);
  const uint64_t imm_s = Sext(((insn >> 25) << 5) | ((insn >> 7) & 0x1f), 12);
  const uint64_t imm_b = Sext((((insn >> 31) & 1) << 12) | (((insn >> 7) & 1) << 11) |
                              (((insn >> 25) & 0x3f) << 5) | (((insn >> 8) & 0xf) << 1), 13);
  const uint64_t imm_u = Sext(insn >> 12, 20) << 12;
  const uint64_t imm_j = Sext((((insn >> 31) & 1) << 20) | (((insn >> 12) & 0xff) << 12) |
                              (((insn >> 20) & 1) << 11) | (((insn >> 21) & 0x3ff) << 1), 21);
  c.imm = imm_i;
  const bool alt = ((insn >> 30) & 1) != 0;
  switch (op) {
    case 0x37:  // LUI
      c.valid = c.reg_write = c.alu_src_imm = true;
      c.alu_op = COPY_B; c.imm = imm_u; break;
    case 0x17:  // AUIPC
      c.valid = c.reg_write = c.alu_src_imm = c.alu_a_pc = true;
      c.alu_op = ADD; c.imm = imm_u; break;
    case 0x6f:  // JAL
      c.valid = c.reg_write = c.jal = true; c.imm = imm_j; break;
    case 0x67:  // JALR
      if (f3 == 0) { c.valid = c.reg_write = c.jalr = true; c.imm = imm_i; }
      break;
    case 0x63:  // branches: funct3 2,3 reserved
      if (f3 != 2 && f3 != 3) { c.valid = c.branch = true; c.imm = imm_b; }
      break;
    case 0x03:  // loads: funct3 7 reserved
      if (f3 != 7) {
        c.valid = c.reg_write = c.mem_read = c.alu_src_imm = true; c.imm = imm_i;
      }
      break;
    case 0x23:  // stores: funct3 0..3
      if (f3 <= 3) { c.valid = c.mem_write = c.alu_src_imm = true; c.imm = imm_s; }
      break;
    case 0x13: {  // OP-IMM; ADDI never becomes SUB
      c.valid = c.reg_write = c.alu_src_imm = true;
      c.alu_op = AluFor(static_cast<int>(f3), f3 == 5 ? alt : false);
      c.imm = imm_i;
      const uint32_t top = insn >> 26;
      if (f3 == 1 && top != 0) c.valid = false;
      if (f3 == 5 && top != 0 && top != 0x10) c.valid = false;
      break;
    }
    case 0x33:  // OP, plus M under funct7=1 (all funct3 defined)
      if (f7 == 0 || (f7 == 0x20 && (f3 == 0 || f3 == 5))) {
        c.valid = c.reg_write = true;
        c.alu_op = AluFor(static_cast<int>(f3), alt);
      } else if (f7 == 1) {
        c.valid = c.reg_write = c.muldiv = true;
      }
      break;
    case 0x1b: {  // OP-IMM-32: ADDIW (0), SLLIW (1), SRLIW/SRAIW (5)
      c.word_op = true;
      c.alu_op = AluFor(static_cast<int>(f3), f3 == 5 ? alt : false);
      c.imm = imm_i;
      if (f3 == 0 || f3 == 1 || f3 == 5) {
        c.valid = c.reg_write = c.alu_src_imm = true;
        if (f3 == 1 && f7 != 0) c.valid = false;
        if (f3 == 5 && f7 != 0 && f7 != 0x20) c.valid = false;
      }
      break;
    }
    case 0x3b:  // OP-32 + M W-variants: MULW, DIV[U]W, REM[U]W only
      c.word_op = true;
      c.alu_op = AluFor(static_cast<int>(f3), alt);
      if ((f7 == 0 && (f3 == 0 || f3 == 1 || f3 == 5)) ||
          (f7 == 0x20 && (f3 == 0 || f3 == 5))) {
        c.valid = c.reg_write = true;
      } else if (f7 == 1 && (f3 == 0 || f3 >= 4)) {
        c.valid = c.reg_write = c.muldiv = true;
      }
      break;
    case 0x0f:  // FENCE / FENCE.I
      c.valid = true;
      break;
    case 0x73:  // SYSTEM
      if (f3 == 0) {
        const uint32_t imm12 = insn >> 20;
        if (imm12 == 0) { c.valid = c.ecall = true; }
        else if (imm12 == 1) { c.valid = c.ebreak = true; }
        else if (imm12 == 0x302) { c.valid = c.mret = true; }
        else if (imm12 == 0x102) { c.valid = c.sret = true; }
        else if (imm12 == 0x105) { c.valid = c.wfi = true; }
        else if (((insn >> 25) & 0x7f) == 0x09) { c.valid = c.sfence = true; }
      } else if (f3 != 4) {
        c.valid = c.reg_write = c.csr = true;
        c.csr_imm = ((f3 >> 2) & 1) != 0;
        c.imm = imm_i;
      }
      break;
    default:
      break;
  }
  return c;
}
}  // namespace

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vmuserisc_decoder> dut{new Vmuserisc_decoder{&context}};
  const char* cov_path = std::getenv("COV_FILE");
  uint64_t checks = 0;

  auto run_one = [&](uint32_t insn) -> bool {
    dut->instr_i = insn;
    dut->eval();
    ++checks;
    const Ctrl g = Golden(insn);
    // ctrl_t bit layout must match muserisc_pkg.sv declaration order.
    const uint32_t c = dut->ctrl_o;
    auto bit = [&](int i) { return ((c >> i) & 1u) != 0; };
    // funct3 occupies the low 3 bits (last struct member), then the
    // flags in reverse declaration order; check them structurally.
    struct Field { const char* name; bool got; bool want; };
    // Decode the packed struct per the SV declaration (MSB first):
    // valid, reg_write, mem_read, mem_write, alu_src_imm, alu_a_pc,
    // word_op, alu_op[3:0], branch, jal, jalr, ecall, ebreak, funct3
    const int kFunct3 = 0, kEbreak = 3, kEcall = 4, kJalr = 5, kJal = 6,
              kBranch = 7, kAluOp = 8, kWordOp = 12, kAluAPc = 13,
              kAluSrcImm = 14, kMemWrite = 15, kMemRead = 16,
              kRegWrite = 17, kValid = 18, kMuldiv = 19, kCsr = 20,
              kCsrImm = 21, kMret = 22, kSret = 23, kWfi = 24, kSfence = 25;
    const Field fields[] = {
        {"valid", bit(kValid), g.valid},
        {"reg_write", bit(kRegWrite), g.reg_write && g.valid},
        {"mem_read", bit(kMemRead), g.mem_read && g.valid},
        {"mem_write", bit(kMemWrite), g.mem_write && g.valid},
        {"branch", bit(kBranch), g.branch && g.valid},
        {"jal", bit(kJal), g.jal && g.valid},
        {"jalr", bit(kJalr), g.jalr && g.valid},
        {"muldiv", bit(kMuldiv), g.muldiv && g.valid},
        {"csr", bit(kCsr), g.csr && g.valid},
        {"csr_imm", bit(kCsrImm), g.csr_imm && g.valid},
        {"mret", bit(kMret), g.mret && g.valid},
        {"sret", bit(kSret), g.sret && g.valid},
        {"wfi", bit(kWfi), g.wfi && g.valid},
        {"sfence", bit(kSfence), g.sfence && g.valid},
        {"ecall", bit(kEcall), g.ecall && g.valid},
        {"ebreak", bit(kEbreak), g.ebreak && g.valid},
    };
    for (const Field& fd : fields) {
      if (fd.got != fd.want) {
        std::printf("FAIL insn=0x%08x field %s got=%d want=%d ctrl=0x%x\n", insn,
                    fd.name, fd.got ? 1 : 0, fd.want ? 1 : 0, c);
        return false;
      }
    }
    if (g.valid) {
      if (bit(kAluSrcImm) != g.alu_src_imm || bit(kAluAPc) != g.alu_a_pc ||
          bit(kWordOp) != g.word_op ||
          static_cast<int>((c >> kAluOp) & 0xf) != g.alu_op) {
        std::printf("FAIL insn=0x%08x alu fields ctrl=0x%x want op=%d src_imm=%d a_pc=%d word=%d\n",
                    insn, c, g.alu_op, g.alu_src_imm ? 1 : 0, g.alu_a_pc ? 1 : 0,
                    g.word_op ? 1 : 0);
        return false;
      }
      if (dut->imm_o != g.imm) {
        std::printf("FAIL insn=0x%08x imm got=0x%016lx want=0x%016lx\n", insn,
                    static_cast<unsigned long>(dut->imm_o),
                    static_cast<unsigned long>(g.imm));
        return false;
      }
    }
    if (dut->rs1_o != ((insn >> 15) & 31) || dut->rs2_o != ((insn >> 20) & 31) ||
        dut->rd_o != ((insn >> 7) & 31) || ((c >> kFunct3) & 7u) != ((insn >> 12) & 7)) {
      std::printf("FAIL insn=0x%08x register/funct3 extraction\n", insn);
      return false;
    }
    return true;
  };

  // Sweep: every opcode x funct3 x funct7 sample, two immediate
  // patterns (one with sign bits set, one clear).
  const uint32_t f7s[] = {0x00, 0x20, 0x01, 0x7f, 0x10, 0x09};
  for (uint32_t op = 0; op < 128; ++op) {
    for (uint32_t f3 = 0; f3 < 8; ++f3) {
      for (uint32_t f7 : f7s) {
        const uint32_t base = (f7 << 25) | (17u << 20) | (9u << 15) |
                              (f3 << 12) | (13u << 7) | op;
        if (!run_one(base)) return 1;
        if (!run_one(base | 0x80000000u)) return 1;  // sign-bit variant
      }
    }
  }
  // SYSTEM immediate sweep (ECALL=0, EBREAK=1, everything else illegal).
  for (uint32_t imm12 = 0; imm12 < 4096; imm12 += 257) {
    if (!run_one((imm12 << 20) | 0x73u)) return 1;
  }
  if (!run_one(0x00000073u)) return 1;  // ECALL
  if (!run_one(0x00100073u)) return 1;  // EBREAK
  if (!run_one(0x30200073u)) return 1;  // MRET
  if (!run_one(0x10200073u)) return 1;  // SRET
  if (!run_one(0x10500073u)) return 1;  // WFI
  if (!run_one(0x12000073u)) return 1;  // SFENCE.VMA x0, x0
  if (!run_one(0x300010f3u)) return 1;  // CSRRW x2, mstatus, x0-ish fields

  dut->final();
  if (cov_path != nullptr) context.coveragep()->write(cov_path);
  std::printf("DECODER TB PASS (%llu checks)\n", static_cast<unsigned long long>(checks));
  return 0;
}
