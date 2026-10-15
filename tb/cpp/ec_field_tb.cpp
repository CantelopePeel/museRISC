// EC field KATs (issue #19), migrated from tb/tb_ec_field.v.
// Expected values are the Python-generated vectors documented in
// docs/COMPLIANCE.md. Exits 0 on pass and 1 on first failure.
#include "Vec_field.h"
#include "verilated.h"
#include "verilated_cov.h"

#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>

namespace {

using Field = std::array<uint64_t, 4>;

int HexValue(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

bool ParseHex(const char* hex, Field* out) {
  constexpr size_t kDigits = 64;
  if (std::strlen(hex) != kDigits) return false;
  out->fill(0);
  for (size_t pos = 0; pos < kDigits; ++pos) {
    const int v = HexValue(hex[kDigits - 1 - pos]);
    if (v < 0) return false;
    (*out)[pos / 16] |= static_cast<uint64_t>(v) << (4 * (pos % 16));
  }
  return true;
}

std::string ToHex(const Field& value) {
  static constexpr char kDigits[] = "0123456789abcdef";
  std::string out;
  out.reserve(64);
  for (size_t pos = 64; pos > 0; --pos) {
    const size_t nibble = pos - 1;
    out.push_back(kDigits[(value[nibble / 16] >> (4 * (nibble % 16))) & 0xf]);
  }
  return out;
}

Field Small(uint64_t value) {
  Field out{};
  out[0] = value;
  return out;
}

Field SubSmall(Field value, uint64_t amount) {
  uint64_t borrow = amount;
  for (uint64_t& word : value) {
    const uint64_t before = word;
    word -= borrow;
    borrow = before < borrow ? 1 : 0;
    if (borrow == 0) break;
  }
  return value;
}

template <typename Port>
void PutField(Port& port, const Field& value) {
  for (size_t i = 0; i < 8; ++i) {
    port[i] = static_cast<uint32_t>(value[i / 2] >> (32 * (i % 2)));
  }
}

template <typename Port>
Field FetchField(const Port& port) {
  Field value{};
  for (size_t i = 0; i < 8; ++i) {
    value[i / 2] |= static_cast<uint64_t>(static_cast<uint32_t>(port[i]))
                    << (32 * (i % 2));
  }
  return value;
}

}  // namespace

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vec_field> dut{new Vec_field{&context}};
  const char* cov_path = std::getenv("COV_FILE");
  uint64_t checks = 0;

  Field secp{};
  Field c255{};
  Field mixed_a{};
  Field mixed_b{};
  Field mixed_want{};
  if (!ParseHex("ffffffffffffffffffffffffffffffff"
                "fffffffffffffffffffffffefffffc2f",
                &secp) ||
      !ParseHex("7fffffffffffffffffffffffffffffff"
                "ffffffffffffffffffffffffffffffed",
                &c255) ||
      !ParseHex("1234567890abcdef1234567890abcdef"
                "1234567890abcdef1234567890abcdef",
                &mixed_a) ||
      !ParseHex("fedcba0987654321fedcba0987654321"
                "fedcba0987654321fedcba0987654321",
                &mixed_b) ||
      !ParseHex("0dabcd892d293feb6a2a19b97d502825"
                "c6a865e9cd771060354652a4e4897181",
                &mixed_want)) {
    std::printf("FAIL internal EC field constant\n");
    return 1;
  }

  auto tick = [&]() {
    dut->clk = 0;
    dut->eval();
    dut->clk = 1;
    dut->eval();
    dut->clk = 0;
    dut->eval();
  };

  dut->clk = 0;
  dut->rst_n = 0;
  dut->start = 0;
  dut->op = 0;
  PutField(dut->a, Field{});
  PutField(dut->b, Field{});
  PutField(dut->mod, Field{});
  tick();
  tick();
  dut->rst_n = 1;
  dut->eval();

  auto run_op = [&](uint8_t op, const Field& x, const Field& y,
                    const Field& mod, const Field& want,
                    const char* name) -> bool {
    dut->op = op;
    PutField(dut->a, x);
    PutField(dut->b, y);
    PutField(dut->mod, mod);
    dut->start = 1;
    dut->eval();
    tick();
    dut->start = 0;
    dut->eval();

    ++checks;
    if (op == 2 && !dut->busy) {
      std::printf("FAIL %s: busy not set after start\n", name);
      return false;
    }
    if (op != 2 && !dut->done) {
      std::printf("FAIL %s: single-cycle op did not set done\n", name);
      return false;
    }

    int cycles = 0;
    while (!dut->done && cycles < 1000) {
      tick();
      ++cycles;
    }
    ++checks;
    if (!dut->done) {
      std::printf("FAIL %s: timed out waiting for done\n", name);
      return false;
    }

    const Field got = FetchField(dut->result);
    ++checks;
    if (got != want) {
      std::printf("FAIL %s got=%s exp=%s\n", name, ToHex(got).c_str(),
                  ToHex(want).c_str());
      return false;
    }
    std::printf("PASS %s\n", name);

    tick();
    ++checks;
    if (dut->done || dut->busy) {
      std::printf("FAIL %s: done/busy did not return idle\n", name);
      return false;
    }
    return true;
  };

  const Field secp_m1 = SubSmall(secp, 1);
  const Field secp_m2 = SubSmall(secp, 2);
  const Field c255_m2 = SubSmall(c255, 2);

  if (!run_op(2, Small(2), Small(3), secp, Small(6), "mul 2*3 secp")) {
    return 1;
  }
  if (!run_op(2, secp_m1, secp_m1, secp, Small(1), "mul (p-1)^2 secp")) {
    return 1;
  }
  if (!run_op(2, c255_m2, c255_m2, c255, Small(4),
              "mul (p-2)^2 c25519")) {
    return 1;
  }
  if (!run_op(2, mixed_a, mixed_b, secp, mixed_want, "mul mixed secp")) {
    return 1;
  }
  if (!run_op(0, secp_m1, secp_m1, secp, secp_m2, "add (p-1)+(p-1)")) {
    return 1;
  }
  if (!run_op(1, Small(2), Small(3), secp, secp_m1, "sub 2-3 secp")) {
    return 1;
  }

  dut->final();
  if (cov_path != nullptr) context.coveragep()->write(cov_path);
  std::printf("TB_EC_FIELD PASS (%llu checks)\n",
              static_cast<unsigned long long>(checks));
  return 0;
}
