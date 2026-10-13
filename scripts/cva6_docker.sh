#!/usr/bin/env bash
# Build the pinned CVA6 (third_party/cva6) Verilator model and run
# sample riscv-isa-tests, inside a native-arch Ubuntu container.
# (Native macOS is not a CVA6-supported build host: its Makefiles
# assume a Linux GNU toolchain and -m64 GNU flags.)
# Usage:
#   ./scripts/cva6_docker.sh [extra make targets...]
#   TEST_LISTS=asm,amo,mul ./scripts/cva6_docker.sh regression
#   SPIKE_TANDEM=1 TEST_LISTS=smoke ./scripts/cva6_docker.sh regression
# Regression CSV and per-test logs land in build/regression/<RUN_NAME>/.
# TESTS may override TEST_LISTS with a space-separated test list.
set -euo pipefail
cd "$(dirname "$0")/.."
docker info >/dev/null 2>&1 || { echo "docker daemon not running"; exit 1; }
[ -d third_party/cva6/core ] || { echo "clone CVA6 first (setup.sh)"; exit 1; }

mkdir -p build/regression
# Persist the container's /opt/riscv (Spike tandem fork + toolchain
# symlinks) on the host, per host architecture. Without this the
# --rm container rebuilds Spike from scratch on every invocation
# (~10 min under emulation); with it, line "if [ ! -x .../spike ]"
# below skips the build after the first install.
HOST_ARCH="$(uname -m)"
TOOLCHAIN_CACHE="$PWD/build/toolchain-cache/$HOST_ARCH/riscv"
mkdir -p "$TOOLCHAIN_CACHE"
docker run --rm \
  -e NUM_JOBS="${NUM_JOBS:-2}" \
  -e SPIKE_TANDEM="${SPIKE_TANDEM:-}" \
  -e VER_LIBRARY="${VER_LIBRARY:-}" \
  -e TEST_LISTS="${TEST_LISTS:-smoke}" \
  -e TESTS="${TESTS:-}" \
  -e TEST_TIMEOUT_SEC="${TEST_TIMEOUT_SEC:-120}" \
  -e RUN_NAME="${RUN_NAME:-}" \
  -e ELF_SUBDIR="${ELF_SUBDIR:-}" \
  -e TIME_OUT="${TIME_OUT:-}" \
  -v "$PWD/third_party/cva6:/cva6" \
  -v "$PWD/build/regression:/evidence" \
  -v "$TOOLCHAIN_CACHE:/opt/riscv" \
  -w /cva6 ubuntu:24.04 bash -exc '
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq build-essential git cmake autoconf automake libtool \
  pkg-config device-tree-compiler gcc-riscv64-unknown-elf \
  picolibc-riscv64-unknown-elf \
  libyaml-cpp-dev libboost-all-dev python3 flex bison libfl-dev zlib1g-dev curl help2man perl
# Cap parallelism by default: an 8 GB Docker VM gets cc1plus
# OOM-killed at -j$(nproc) while compiling Verilator/CVA6 C++.
# Larger CI runners may pass NUM_JOBS=4 (or more) explicitly.
export RISCV=/opt/riscv SPIKE_INSTALL_DIR=/opt/riscv
export NUM_JOBS="${NUM_JOBS:-2}"
if [ -z "${VER_LIBRARY}" ]; then
  if [ -n "${SPIKE_TANDEM}" ]; then VER_LIBRARY=work-ver-tandem; else VER_LIBRARY=work-ver; fi
fi
if [ -z "${RUN_NAME}" ]; then
  if [ -n "${SPIKE_TANDEM}" ]; then RUN_NAME=tandem; else RUN_NAME=solo; fi
fi
export VER_LIBRARY RUN_NAME
# Directory (relative to /cva6) holding test ELFs named by TESTS.
# Default is the riscv-tests build output; ACT4 runs pass
# ELF_SUBDIR=act-elfs (staged by scripts/build_act4_cva6.sh) and
# skip the riscv-tests build below.
ELF_SUBDIR="${ELF_SUBDIR:-tmp/riscv-tests/build/isa}"
export ELF_SUBDIR
echo "CVA6 mode: SPIKE_TANDEM=${SPIKE_TANDEM:-0} VER_LIBRARY=$VER_LIBRARY TEST_LISTS=$TEST_LISTS RUN_NAME=$RUN_NAME ELF_SUBDIR=$ELF_SUBDIR"
# CVA6 master needs its pinned Verilator v5.008 (+patch); Ubuntu 5.020
# hits a Verilator internal fault on this design. Same recipe as
# ci/install-verilator.sh minus the long self-test.
if [ ! -x tmp/verilator-v5.008/bin/verilator ]; then
  mkdir -p tmp/verilator-v5.008/verilator && cd tmp/verilator-v5.008/verilator
  [ -d .git ] || git clone https://github.com/verilator/verilator.git .
  git checkout v5.008
  git apply /cva6/verif/regress/verilator-v5.patch || true
  autoconf && ./configure --prefix=/cva6/tmp/verilator-v5.008
  make -j${NUM_JOBS} && make install
  cd /cva6
fi
export PATH=/cva6/tmp/verilator-v5.008/bin:$PATH
unset VERILATOR_ROOT; verilator --version
mkdir -p $RISCV/bin $RISCV/lib tmp
for t in gcc g++ ar as ld nm objcopy objdump ranlib strip readelf size; do
  ln -sf /usr/bin/riscv64-unknown-elf-$t $RISCV/bin/riscv64-unknown-elf-$t
done
for f in /usr/lib/*/libyaml-cpp.so*; do
  [ -e "$f" ] && ln -sf "$f" $RISCV/lib/
done
cp -r /usr/include/yaml-cpp $RISCV/include/ 2>/dev/null || mkdir -p $RISCV/include
if [ ! -x $RISCV/bin/spike ]; then
  # Build the tandem Spike fork bundled with core-v-verif (recipe in
  # verif/core-v-verif/mk/Common.mk). The testharness links its
  # libdisasm and the fesvr DPI symbols (read_elf, get_section, ...),
  # which upstream Spike does not provide. Verilator must already be
  # built above: fesvr_dpi.cc includes <svdpi.h>.
  SRC=verif/core-v-verif/vendor/riscv/riscv-isa-sim
  cp /usr/share/misc/config.guess /usr/share/misc/config.sub $SRC/scripts/
  mkdir -p $SRC/build && cd $SRC/build
  # Keep configure probes clean (forced -include breaks the
  # boost_regex exit() probe); apply compatibility flags at make time.
  export CXXFLAGS="-O2 -I/cva6/tmp/verilator-v5.008/share/verilator/include/vltstd -I/cva6/tmp/verilator-v5.008/share/verilator/include"
  export CFLAGS="-O2"
  [ -f config.status ] || ../configure --prefix="$RISCV/" --build="$(gcc -dumpmachine)"
  SPIKE_CXXFLAGS="-O2 -include cstdint -include cstring -include stdexcept -I/cva6/tmp/verilator-v5.008/share/verilator/include/vltstd -I/cva6/tmp/verilator-v5.008/share/verilator/include"
  make -j${NUM_JOBS} CXXFLAGS="$SPIKE_CXXFLAGS" yaml-cpp-static || true
  make -j${NUM_JOBS} CXXFLAGS="$SPIKE_CXXFLAGS" yaml-cpp || true
  make -j${NUM_JOBS} CXXFLAGS="$SPIKE_CXXFLAGS"; make install
  export CXXFLAGS="" CFLAGS=""
  cd /cva6
fi
test -e $RISCV/lib/libdisasm.so || test -f $RISCV/lib/libdisasm.a
ls $RISCV/lib/ | grep -E "fesvr|riscv|disasm|yaml"
# riscv-tests: build both physical (-p-) and virtual-memory (-v-)
# tests. The -v- variants compile env/v/*.c, which need libc headers;
# the Ubuntu cross GCC ships no libc, so expose picolibc headers
# (nothing is linked from libc: the tests use -nostdlib and env/v
# provides its own string.c).
export C_INCLUDE_PATH=/usr/lib/picolibc/riscv64-unknown-elf/include
TVERSION=eeacd5507db7a0f50ca8c4f27aff220fcbb60bdf
cd tmp
[ -d riscv-tests ] || git clone https://github.com/riscv/riscv-tests.git
cd riscv-tests && git checkout $TVERSION
git submodule update --init --recursive
autoconf; mkdir -p build isa_out
cd build && ../configure --prefix=/cva6/tmp/riscv-tests/build
mkdir -p isa && cd isa
selected_tests=()
add_test() {
  local candidate="$1" existing
  for existing in "${selected_tests[@]}"; do
    [ "$existing" = "$candidate" ] && return 0
  done
  selected_tests+=("$candidate")
}
add_list_file() {
  local t
  while IFS= read -r t || [ -n "$t" ]; do
    case "$t" in ""|\#*) continue ;; esac
    add_test "$t"
  done < "$1"
}
if [ -n "$TESTS" ]; then
  for t in $TESTS; do add_test "$t"; done
else
  IFS=, read -r -a requested_lists <<< "$TEST_LISTS"
  for list_name in "${requested_lists[@]}"; do
    case "$list_name" in
      smoke)
        add_test rv64ui-p-add
        add_test rv64ui-p-simple
        add_test rv64um-p-mul
        add_test rv64ua-p-amoadd_d
        ;;
      asm) add_list_file /cva6/ci/riscv-asm-tests.list ;;
      amo) add_list_file /cva6/ci/riscv-amo-tests.list ;;
      mul) add_list_file /cva6/ci/riscv-mul-tests.list ;;
      fp) add_list_file /cva6/ci/riscv-fp-tests.list ;;
      testfloat)
        for op in f32_add f32_sub f32_mul f32_div f32_sqrt f32_mulAdd \
                  f64_add f64_sub f64_mul f64_div f64_sqrt f64_mulAdd; do
          add_test "tf-$op"
        done
        ;;
      testfloat-rm)
        for rm in rtz rdn rup rmm; do
          for op in f32_add f32_mul f32_div f32_sqrt f32_mulAdd \
                    f64_add f64_mul f64_div f64_sqrt f64_mulAdd \
                    f32_to_i32 f32_to_ui64 f64_to_i64 f64_to_ui32 \
                    i64_to_f32 ui64_to_f64 i32_to_f64 ui32_to_f32 \
                    f64_to_f32; do
            add_test "tf-${op}_${rm}"
          done
        done
        ;;
      testfloat-cvt)
        for op in f32_to_i32 f32_to_i64 f32_to_ui32 f32_to_ui64 \
                  f64_to_i32 f64_to_i64 f64_to_ui32 f64_to_ui64 \
                  i32_to_f32 i64_to_f32 ui32_to_f32 ui64_to_f32 \
                  i32_to_f64 i64_to_f64 ui32_to_f64 ui64_to_f64 \
                  f32_to_f64 f64_to_f32 \
                  f32_eq f32_le f32_lt f64_eq f64_le f64_lt; do
          add_test "tf-$op"
        done
        ;;
      none) ;;
      *) echo "unknown TEST_LISTS entry: $list_name" >&2; exit 2 ;;
    esac
  done
fi
echo "Selected ${#selected_tests[@]} riscv-tests ELF(s)"
if [ "${1:-}" = regression ] && [ "${#selected_tests[@]}" -eq 0 ]; then
  echo "regression requested with no selected tests" >&2; exit 2
fi
if [ "$ELF_SUBDIR" = tmp/riscv-tests/build/isa ]; then
  if [ "${#selected_tests[@]}" -gt 0 ]; then
    make -f ../../isa/Makefile src_dir=../../isa XLEN=64 \
      RISCV_PREFIX=riscv64-unknown-elf- -j"${NUM_JOBS}" \
      "${selected_tests[@]}"
  fi
else
  for t in "${selected_tests[@]}"; do
    [ -f "/cva6/$ELF_SUBDIR/$t" ] || { echo "Missing test ELF: $ELF_SUBDIR/$t" >&2; exit 1; }
  done
fi
cd /cva6
make_args=(ver-library="$VER_LIBRARY")
if [ -n "${SPIKE_TANDEM}" ]; then make_args+=(SPIKE_TANDEM="$SPIKE_TANDEM"); fi
make "${make_args[@]}" verilate
if [ "${1:-}" = regression ]; then
  outdir="/evidence/$RUN_NAME"
  mkdir -p "$outdir/logs"
  csv="$outdir/results.csv"
  printf "test,mode,exit_code,status,cycles,mismatches,log\n" > "$csv"
  mode=solo
  [ -n "${SPIKE_TANDEM}" ] && mode=tandem
  passed=0; failed=0; timed_out=0; mismatched=0
  for t in "${selected_tests[@]}"; do
    elf="$ELF_SUBDIR/$t"
    log="$outdir/logs/$t.log"
    # Optional cycle cap for long tests (harness default 2M cycles
    # in rvfi_tracer); +time_out is allowlisted by ariane_tb.cpp.
    time_out_arg=()
    if [ -n "${TIME_OUT:-}" ]; then time_out_arg=("+time_out=$TIME_OUT"); fi
    # Tandem Spike setup reads +elf_file/+core_name via
    # $value$plusargs (rvfi_spike.sv, spike.sv). They go after the
    # binary: ariane_tb.cpp allowlists only three leading Verilog
    # plusargs, while Verilated::commandArgs still exposes
    # trailing args to $value$plusargs. core_name is the Makefile
    # default target; riscv_dpi.cc requires the cv64a prefix.
    if [ "$mode" = tandem ]; then
      if timeout "$TEST_TIMEOUT_SEC" "$VER_LIBRARY/Variane_testharness" "${time_out_arg[@]}" "$elf" "+elf_file=$elf" "+core_name=cv64a6_imafdc_sv39" >"$log" 2>&1; then rc=0; else rc=$?; fi
    else
      if timeout "$TEST_TIMEOUT_SEC" "$VER_LIBRARY/Variane_testharness" "${time_out_arg[@]}" "$elf" >"$log" 2>&1; then rc=0; else rc=$?; fi
    fi
    mismatch_count=$(grep -ci "Mismatch" "$log" || true)
    cycles=$(sed -nE "s/.*after ([0-9]+) cycles.*/\1/p" "$log" | tail -n 1)
    status=FAIL
    if [ "$rc" -eq 124 ]; then
      status=TIMEOUT; timed_out=$((timed_out + 1))
    elif [ "$mismatch_count" -gt 0 ]; then
      status=MISMATCH; mismatched=$((mismatched + 1))
    elif [ "$rc" -eq 0 ] && grep -q "\*\*\* SUCCESS \*\*\*" "$log" && ! grep -q "\*\*\* FAILED \*\*\*" "$log"; then
      status=PASS; passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
    if [ "$status" = TIMEOUT ] || [ "$status" = MISMATCH ]; then
      failed=$((failed + 1))
    fi
    printf "%s,%s,%s,%s,%s,%s,logs/%s.log\n" "$t" "$mode" "$rc" "$status" "${cycles:-}" "$mismatch_count" "$t" >> "$csv"
    echo "$t: $status (exit $rc, mismatches $mismatch_count)"
  done
  {
    echo "mode=$mode"
    echo "test_lists=$TEST_LISTS"
    echo "selected=${#selected_tests[@]}"
    echo "passed=$passed"
    echo "failed=$failed"
    echo "timeouts=$timed_out"
    echo "mismatched=$mismatched"
  } > "$outdir/summary.txt"
  cat "$outdir/summary.txt"
  [ "$failed" -eq 0 ]
elif [ "$#" -gt 0 ]; then
  make "${make_args[@]}" "$@"
fi
' bash "$@"
echo "CVA6 container build/test step finished (see log above)."
