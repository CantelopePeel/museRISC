// SHA-256 block KATs (issue #19): FIPS 180-4 "abc" and empty-message
// padded blocks, migrated from tb/tb_sha256.v. Exits 0 on pass and 1
// on the first mismatch or timeout.
#include "Vsha256_block.h"
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

using Block = std::array<uint64_t, 8>;
using Digest = std::array<uint64_t, 4>;

int HexValue(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

template <size_t Words>
bool ParseHex(const char* hex, std::array<uint64_t, Words>* out) {
  const size_t digits = Words * 16;
  if (std::strlen(hex) != digits) return false;
  out->fill(0);
  for (size_t pos = 0; pos < digits; ++pos) {
    const int v = HexValue(hex[digits - 1 - pos]);
    if (v < 0) return false;
    (*out)[pos / 16] |= static_cast<uint64_t>(v) << (4 * (pos % 16));
  }
  return true;
}

template <size_t Words>
std::string ToHex(const std::array<uint64_t, Words>& value) {
  static constexpr char kDigits[] = "0123456789abcdef";
  std::string out;
  out.reserve(Words * 16);
  for (size_t pos = Words * 16; pos > 0; --pos) {
    const size_t nibble = pos - 1;
    out.push_back(kDigits[(value[nibble / 16] >> (4 * (nibble % 16))) & 0xf]);
  }
  return out;
}

template <typename Port, size_t Words>
void PutWide(Port& port, const std::array<uint64_t, Words>& value) {
  for (size_t i = 0; i < Words * 2; ++i) {
    port[i] = static_cast<uint32_t>(value[i / 2] >> (32 * (i % 2)));
  }
}

template <typename Port, size_t Words>
std::array<uint64_t, Words> FetchWide(const Port& port) {
  std::array<uint64_t, Words> value{};
  for (size_t i = 0; i < Words * 2; ++i) {
    value[i / 2] |= static_cast<uint64_t>(static_cast<uint32_t>(port[i]))
                    << (32 * (i % 2));
  }
  return value;
}

Block PaddedBlock(uint32_t first_word, uint64_t bit_length) {
  Block block{};
  block[7] = static_cast<uint64_t>(first_word) << 32;
  block[0] = bit_length;
  return block;
}

}  // namespace

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vsha256_block> dut{new Vsha256_block{&context}};
  const char* cov_path = std::getenv("COV_FILE");
  uint64_t checks = 0;

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
  PutWide(dut->block_in, Block{});
  tick();
  tick();
  dut->rst_n = 1;
  dut->eval();

  auto run_block = [&](const Block& block, const Digest& want,
                       const char* name) -> bool {
    PutWide(dut->block_in, block);
    dut->start = 1;
    dut->eval();
    tick();
    dut->start = 0;
    dut->eval();

    ++checks;
    if (!dut->busy) {
      std::printf("FAIL %s: busy not set after start\n", name);
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

    const Digest got = FetchWide<decltype(dut->digest_out), 4>(dut->digest_out);
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

  Digest abc{};
  Digest empty{};
  if (!ParseHex("ba7816bf8f01cfea414140de5dae2223"
                "b00361a396177a9cb410ff61f20015ad",
                &abc) ||
      !ParseHex("e3b0c44298fc1c149afbf4c8996fb924"
                "27ae41e4649b934ca495991b7852b855",
                &empty)) {
    std::printf("FAIL internal digest constant\n");
    return 1;
  }

  if (!run_block(PaddedBlock(0x61626380u, 24), abc, "sha256(abc)")) return 1;
  if (!run_block(PaddedBlock(0x80000000u, 0), empty, "sha256(empty)")) {
    return 1;
  }

  dut->final();
  if (cov_path != nullptr) context.coveragep()->write(cov_path);
  std::printf("TB_SHA256 PASS (%llu checks)\n",
              static_cast<unsigned long long>(checks));
  return 0;
}
