#!/usr/bin/env bash
#
# mayhem/test.sh — run Zephyr's own DHCPv4-server ztest suite (tests/net/dhcpv4/server), built by
# mayhem/build.sh for native_sim/native/64 with the project's normal flags.
#
# ztest asserts the server's replies (offered address, lease, options, NAK/ACK state transitions) and
# prints a per-suite summary; the counts below are taken from it. A neutered binary prints no summary,
# which reports as one failure rather than zero tests.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

RUNNER="$SRC/build-test-dhcpv4-server/zephyr/zephyr.exe"
if [ ! -x "$RUNNER" ]; then
  echo "test.sh: $RUNNER missing — mayhem/build.sh did not build the ztest suite" >&2
  emit_ctrf ztest 0 1 0
  exit 1
fi

# The simulated board writes scratch files next to its cwd.
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
out="$work/ztest.out"
(cd "$work" && timeout 600 "$RUNNER" > "$out" 2>&1)
rc=$?
cat "$out"

passed=0; failed=0; skipped=0
while read -r p f s; do
  passed=$((passed + p)); failed=$((failed + f)); skipped=$((skipped + s))
done < <(sed -n 's/^SUITE [A-Z]* - *[0-9.]*% \[[^]]*\]: pass = \([0-9]*\), fail = \([0-9]*\), skip = \([0-9]*\),.*/\1 \2 \3/p' "$out")

# A real run prints the summary footer and at least one passed assertion-bearing case.
if [ "$rc" -ne 0 ] || ! grep -q '^PROJECT EXECUTION SUCCESSFUL' "$out" || [ "$passed" -eq 0 ]; then
  failed=$((failed + 1))
fi
emit_ctrf ztest "$passed" "$failed" "$skipped"
