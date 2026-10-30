#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
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

# RUN the QTest suites mayhem/build.sh built into build-test/ and add up each one's `Totals:` line.
# These are upstream's own known-answer suites for the wire/file parsers the fuzz harnesses drive
# (S7, ISO-TSAP, IEC 104, Sparkplug, CSV rows, block codec, API reception, SSE). A suite that prints no
# `Totals:` line (missing binary, crash, or a program that exits 0 without running) counts as a failure.
export QT_QPA_PLATFORM=offscreen
passed=0 ; failed=0 ; skipped=0
suites=(tst_s7comm_pdu tst_s7comm_isotsap tst_s7_address tst_iec104_apci tst_iec104_asdu \
        tst_sparkplug_payload tst_stream_block_codec tst_csv_rows tst_client_reception tst_sse_event_reader)
for t in "${suites[@]}"; do
  bin="$SRC/build-test/$t"
  if [ ! -x "$bin" ]; then echo "MISSING test binary $bin (mayhem/build.sh did not build it)" >&2 ; failed=$((failed+1)); continue; fi
  out="$("$bin" 2>&1)" ; rc=$?
  printf '%s\n' "$out" | grep -E '^(FAIL!|XPASS|Totals:)' || true
  line="$(printf '%s\n' "$out" | grep -E '^Totals:' | tail -n1)"
  if [ -z "$line" ]; then echo "$t: no Totals line (rc=$rc)" >&2 ; failed=$((failed+1)); continue; fi
  p=$(sed -E 's/^Totals: ([0-9]+) passed, ([0-9]+) failed, ([0-9]+) skipped.*/\1/' <<<"$line")
  f=$(sed -E 's/^Totals: ([0-9]+) passed, ([0-9]+) failed, ([0-9]+) skipped.*/\2/' <<<"$line")
  s=$(sed -E 's/^Totals: ([0-9]+) passed, ([0-9]+) failed, ([0-9]+) skipped.*/\3/' <<<"$line")
  passed=$((passed+p)) ; failed=$((failed+f)) ; skipped=$((skipped+s))
  if [ "$rc" -ne 0 ] && [ "$f" -eq 0 ]; then failed=$((failed+1)); fi
done
emit_ctrf "qttest" "$passed" "$failed" "$skipped"
