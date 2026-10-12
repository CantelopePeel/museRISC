#!/usr/bin/env bash
# Build the pinned CVA6 (third_party/cva6) Verilator model and run
# sample riscv-isa-tests, inside a native-arch Ubuntu container.
# (Native macOS is not a CVA6-supported build host: its Makefiles
# assume a Linux GNU toolchain and -m64 GNU flags.)
# Usage: ./scripts/cva6_docker.sh [extra make targets...]
# Log evidence is expected under third_party/cva6/tmp/.
set -euo pipefail
cd "$(dirname "$0")/.."
docker info >/dev/null 2>&1 || { echo "docker daemon not running"; exit 1; }
[ -d third_party/cva6/core ] || { echo "clone CVA6 first (setup.sh)"; exit 1; }

docker run --rm -e NUM_JOBS="${NUM_JOBS:-2}" \
  -v "$PWD/third_party/cva6:/cva6" -w /cva6 ubuntu:24.04 bash -exc '
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
# riscv-tests: build only the -p- (physical) tests we run. The -v-
# variants need a libc (env/v/*.c) that the Ubuntu cross package
# does not provide in default include paths; CVA6 CI uses -p- tests.
TVERSION=eeacd5507db7a0f50ca8c4f27aff220fcbb60bdf
cd tmp
[ -d riscv-tests ] || git clone https://github.com/riscv/riscv-tests.git
cd riscv-tests && git checkout $TVERSION
git submodule update --init --recursive
autoconf; mkdir -p build isa_out
cd build && ../configure --prefix=/cva6/tmp/riscv-tests/build
mkdir -p isa && cd isa
make -f ../../isa/Makefile src_dir=../../isa XLEN=64 \
  RISCV_PREFIX=riscv64-unknown-elf- -j${NUM_JOBS} \
  rv64ui-p-add rv64ui-p-simple rv64um-p-mul rv64ua-p-amoadd_d || true
ls -l rv64ui-p-add rv64ui-p-simple 2>/dev/null || ls | head
cd /cva6
make verilate
'"${1:+make $*}"
echo "CVA6 container build/test step finished (see log above)."
