#!/usr/bin/env bash
#
# mayhem/build.sh — build Zephyr's two in-tree libFuzzer harnesses (native_sim/native/64), their
# standalone reproducers, and the ztest suite that test.sh runs. Runs offline as `mayhem` in /mayhem.
#
#   fuzz_sample         samples/subsys/debug/fuzz      (kernel + libFuzzer IRQ plumbing)
#   fuzz_dhcpv4_server  tests/net/fuzz/dhcpv4/server   (DHCPv4 server message parser)
#
# A native_sim libFuzzer image is a host executable (zephyr.exe) whose main() is libFuzzer's, so each
# harness is a whole Zephyr application build. mayhem/zephyr-module is passed as an extra Zephyr module
# to reach the native_simulator runner (where the final link happens) without editing upstream.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

export ZEPHYR_BASE="$SRC"
export ZEPHYR_TOOLCHAIN_VARIANT=host
BOARD=native_sim/native/64
MODULE="$SRC/mayhem/zephyr-module"
LSAN_OFF_SRC="$MODULE/lsan_off.c"   # __lsan_is_turned_off() hook, linked into every fuzz binary
# An explicit version keeps the build off `git describe` (the checkout may belong to another uid).
VERSION_ARGS=(-DBUILD_VERSION=mayhem)
MODULE_ARGS=(-DZEPHYR_MODULES="$MODULE" -DMAYHEM_LSAN_OFF_SRC="$LSAN_OFF_SRC")

# Zephyr switches the sanitizers with Kconfig; map the build contract's flags onto it.
asan=n; ubsan=n
case "$SANITIZER_FLAGS" in *address*)   asan=y ;; esac
case "$SANITIZER_FLAGS" in *undefined*) ubsan=y ;; esac
KCONFIG_SAN=(-DCONFIG_ASAN=$asan -DCONFIG_UBSAN=$ubsan -DCONFIG_ASAN_RECOVER=n)

# zbuild <app dir> <build dir> [cmake args…]: configure + build quietly, dump the log only on failure.
zbuild() {
  local app="$1" bdir="$2" log; shift 2
  log="$(mktemp)"
  rm -rf "$bdir"
  { cmake -S "$app" -B "$bdir" -GNinja -DBOARD="$BOARD" -DTOOLCHAIN_VARIANT_COMPILER=llvm \
          "${VERSION_ARGS[@]}" "$@" && ninja -C "$bdir"; } > "$log" 2>&1 \
    || { tail -80 "$log" >&2; rm -f "$log"; return 1; }
  rm -f "$log"
}

# 1) Fuzz builds. EXTRA_CFLAGS reaches every Zephyr object; the module adds the same DWARF level and
#    the LSan-off hook to the runner objects.
FUZZ_CFLAGS="$DEBUG_FLAGS"
[ -z "$SANITIZER_FLAGS" ] || FUZZ_CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS"

# Standalone reproducers link LLVM's run-once main() instead of the libFuzzer engine.
mkdir -p "$SRC/build-standalone"
STANDALONE_OBJ="$SRC/build-standalone/main.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$STANDALONE_OBJ"

# <target>:<app dir>
TARGETS=(
  "fuzz_sample:samples/subsys/debug/fuzz"
  "fuzz_dhcpv4_server:tests/net/fuzz/dhcpv4/server"
)
for t in "${TARGETS[@]}"; do
  name="${t%%:*}"; app="$SRC/${t#*:}"
  bname="build-${name//_/-}"
  zbuild "$app" "$SRC/$bname" "${MODULE_ARGS[@]}" -DEXTRA_CFLAGS="$FUZZ_CFLAGS" "${KCONFIG_SAN[@]}"
  cp "$SRC/$bname/zephyr/zephyr.exe" "$SRC/$name"
  zbuild "$app" "$SRC/$bname-standalone" "${MODULE_ARGS[@]}" -DEXTRA_CFLAGS="$FUZZ_CFLAGS" \
         "${KCONFIG_SAN[@]}" -DMAYHEM_STANDALONE_MAIN_OBJ="$STANDALONE_OBJ"
  cp "$SRC/$bname-standalone/zephyr/zephyr.exe" "$SRC/$name-standalone"
done

# 2) The ztest suite test.sh runs: the DHCPv4 server's own unit tests, NORMAL flags (no sanitizers, no
#    DWARF override, no extra module), as a clean independent build.
zbuild "$SRC/tests/net/dhcpv4/server" "$SRC/build-test-dhcpv4-server" \
       -DEXTRA_CFLAGS="$COVERAGE_FLAGS" -DEXTRA_LDFLAGS="$COVERAGE_FLAGS"
