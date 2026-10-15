// Keccak-f1600 KAT (issue #19): permutation of the all-zero state,
// migrated from tb/tb_keccak.v. The expected state is the same vector
// cross-checked by sw/golden.py against hashlib SHA3-256. Exits 0 on
// pass and 1 on the first mismatch or timeout.
#include "Vkeccak_f1600.h"
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

using State = std::array<uint64_t, 25>;

int HexValue(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

bool ParseHex(const char* hex, State* out) {
  constexpr size_t kDigits = 400;
  if (std::strlen(hex) != kDigits) return false;
  out->fill(0);
  for (size_t pos = 0; pos < kDigits; ++pos) {
    const int v = HexValue(hex[kDigits - 1 - pos]);
    if (v < 0) return false;
    (*out)[pos / 16] |= static_cast<uint64_t>(v) << (4 * (pos % 16));
  }
  return true;
}

std::string ToHex(const State& value) {
  static constexpr char kDigits[] = "0123456789abcdef";
  std::string out;
  out.reserve(400);
  for (size_t pos = 400; pos > 0; --pos) {
    const size_t nibble = pos - 1;
    out.push_back(kDigits[(value[nibble / 16] >> (4 * (nibble % 16))) & 0xf]);
  }
  return out;
}

template <typename Port>
void PutState(Port& port, const State& value) {
  for (size_t i = 0; i < 50; ++i) {
    port[i] = static_cast<uint32_t>(value[i / 2] >> (32 * (i % 2)));
  }
}

template <typename Port>
State FetchState(const Port& port) {
  State value{};
  for (size_t i = 0; i < 50; ++i) {
    value[i / 2] |= static_cast<uint64_t>(static_cast<uint32_t>(port[i]))
                    << (32 * (i % 2));
  }
  return value;
}

constexpr const char kExpectedZero[] =
    "eaf1ff7b5ceca24975f644e97f30a13b16f53526e70465c21841f924a2c509"
    "e4940c7922ae3a26148c3ee88a1ccf32c8b87c5a554fd00ecb613670957bc4"
    "661164befef28cc970f205e5635a21d9ae6101f22f1a11a5569f43b831cd03"
    "47c82681a57c16dbcf555fa9a6e6260d712103eb5aa93f2317d63530935ab7"
    "d08ffc64ad30a6f71b19059c8c5bda0cd6192e7690fee5a0a44647c4ff97a4"
    "2d7f8e6fd48b284e056253d057bd1547306f80494dd598261ea65aa9ee84d5"
    "ccf933c0478af1258f7940e1dde7";

}  // namespace

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vkeccak_f1600> dut{new Vkeccak_f1600{&context}};
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

  State want{};
  if (!ParseHex(kExpectedZero, &want)) {
    std::printf("FAIL internal Keccak constant\n");
    return 1;
  }

  dut->clk = 0;
  dut->rst_n = 0;
  dut->start = 0;
  PutState(dut->state_in, State{});
  tick();
  tick();
  dut->rst_n = 1;
  dut->eval();

  dut->start = 1;
  dut->eval();
  tick();
  dut->start = 0;
  dut->eval();

  ++checks;
  if (!dut->busy) {
    std::printf("FAIL keccak(0): busy not set after start\n");
    return 1;
  }

  int cycles = 0;
  while (!dut->done && cycles < 1000) {
    tick();
    ++cycles;
  }
  ++checks;
  if (!dut->done) {
    std::printf("FAIL keccak(0): timed out waiting for done\n");
    return 1;
  }

  const State got = FetchState(dut->state_out);
  ++checks;
  if (got != want) {
    std::printf("FAIL keccak(0)\n got=%s\n exp=%s\n", ToHex(got).c_str(),
                ToHex(want).c_str());
    return 1;
  }
  std::printf("PASS keccak-f1600(0)\n");

  tick();
  ++checks;
  if (dut->done || dut->busy) {
    std::printf("FAIL keccak(0): done/busy did not return idle\n");
    return 1;
  }

  dut->final();
  if (cov_path != nullptr) context.coveragep()->write(cov_path);
  std::printf("TB_KECCAK PASS (%llu checks)\n",
              static_cast<unsigned long long>(checks));
  return 0;
}
