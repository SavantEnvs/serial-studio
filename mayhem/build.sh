#!/usr/bin/env bash
#
# mayhem/build.sh — builds, from upstream's own sources (mayhem/CMakeLists.txt selects them):
#   1) /mayhem/fuzz_<subject>             libFuzzer binaries, project code ASan+UBSan+SanCov instrumented
#   2) /mayhem/fuzz_<subject>-standalone  run-once reproducers (same harness, LLVM StandaloneFuzzTargetMain)
#   3) build-test/tst_*                   upstream's QTest suites for the same parsers, NORMAL flags
#
# Offline and re-runnable: every dependency (Qt, zlib, expat) is an apt package baked into the image;
# nothing is fetched and each build directory is reconfigured in place.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# Qt reads CXXFLAGS/LDFLAGS-style variables from nowhere; keep the environment from leaking in anyway.
unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS

# Fuzz + standalone: -fsanitize=fuzzer-no-link instruments the project code (not only the harness)
# unconditionally, so coverage is recorded even when SANITIZER_FLAGS is empty. vptr is relaxed because
# Qt's own (uninstrumented) shared libraries own the vtables of the QObject types the harnesses use.
common="$SANITIZER_FLAGS $DEBUG_FLAGS -O1 -fno-sanitize=vptr"

configure() { # <dir> <mode> <flags>
  cmake -S mayhem -B "$1" -G Ninja \
    -DMAYHEM_MODE="$2" -DMAYHEM_OUT="$SRC" -DSTANDALONE_FUZZ_MAIN="$STANDALONE_FUZZ_MAIN" "-DFUZZ_ENGINE=$LIB_FUZZING_ENGINE" "-DLSAN_OFF_SRC=$SRC/mayhem/lsan_off.cc" \
    -DCMAKE_BUILD_TYPE= \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    "-DCMAKE_C_FLAGS=$3" "-DCMAKE_CXX_FLAGS=$3"
}

# 1) libFuzzer binaries
configure build-fuzz FUZZ "$common -fsanitize=fuzzer-no-link"
cmake --build build-fuzz -j"$MAYHEM_JOBS"

# 2) standalone reproducers (no libFuzzer runtime)
configure build-standalone STANDALONE "$common"
cmake --build build-standalone -j"$MAYHEM_JOBS"

# 3) upstream's own test suites, normal flags, no sanitizers
cmake -S mayhem -B build-test -G Ninja \
  -DMAYHEM_MODE=TEST -DMAYHEM_OUT= \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  "-DCMAKE_C_FLAGS=$COVERAGE_FLAGS" "-DCMAKE_CXX_FLAGS=$COVERAGE_FLAGS"
cmake --build build-test -j"$MAYHEM_JOBS"
