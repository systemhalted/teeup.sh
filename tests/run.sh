#!/usr/bin/env bash
# run.sh - run every test file under tests/ and aggregate results.
# Suites are independent (each builds its own temp HOME and mock bin), so they
# run in parallel batches. Output is buffered per suite and printed in the
# fixed order below, so a parallel run reads exactly like a serial one.
# TEEUP_TEST_JOBS=1 forces the serial path; the default is the CPU count,
# capped at 8. bash 3.2 has no `wait -n`, so a batch waits for all of its jobs.
set -euo pipefail

if [[ "${LC_ALL:-}" == "C.UTF-8" || "${LANG:-}" == "C.UTF-8" ]]; then
  export LANG="en_US.UTF-8"
  export LC_ALL="en_US.UTF-8"
fi

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

detect_jobs() {
  local n=""
  if [[ -n "${TEEUP_TEST_JOBS:-}" ]]; then
    printf '%s\n' "$TEEUP_TEST_JOBS"
    return 0
  fi
  # sysctl on macOS, nproc on Linux; neither is guaranteed, so fall back to 1.
  n="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 1)"
  case "$n" in
    ''|*[!0-9]*) n=1 ;;
  esac
  [[ "$n" -lt 1 ]] && n=1
  [[ "$n" -gt 8 ]] && n=8
  printf '%s\n' "$n"
}

jobs_wanted="$(detect_jobs)"
# An indexed array, not a joined string: a checkout path containing a space
# (/Users/ada/My Code/teeup) would otherwise split into bogus entries when the
# loops below expand it. bash 3.2 has indexed arrays; only associative ones
# arrived in bash 4.
suites=()
for suite in "$TESTS_DIR"/lib/*.sh "$TESTS_DIR"/capabilities/*.sh "$TESTS_DIR"/cli.sh "$TESTS_DIR"/bootstrap.sh "$TESTS_DIR"/docs.sh; do
  [[ -f "$suite" ]] || continue
  suites[${#suites[@]}]="$suite"
done

failed=0
ran=0
out_dir=""
if [[ "$jobs_wanted" -gt 1 ]]; then
  out_dir="$(mktemp -d "${TMPDIR:-/tmp}/teeup-tests.XXXXXX")"
  trap 'rm -rf "$out_dir"' EXIT
fi

# suite_key <suite>: the suite's path under tests/ with "/" turned into "_",
# so lib/theme.sh and capabilities/theme.sh (same basename, different suites)
# get their own log instead of overwriting each other.
suite_key() {
  local rel="${1#"$TESTS_DIR"/}"
  printf '%s\n' "$(printf '%s' "$rel" | tr '/' '_')"
}

# report <suite> <log file> <status file>: print one suite's buffered output
# and count its result, in the order the suite list defines.
report() {
  local suite="$1" log="$2" status_file="$3" rc=1
  [[ -f "$status_file" ]] && rc="$(cat "$status_file")"
  echo ""
  echo "== ${suite#"$TESTS_DIR"/} =="
  [[ -f "$log" ]] && cat "$log"
  ran=$((ran + 1))
  [[ "$rc" == "0" ]] || failed=$((failed + 1))
}

if [[ "$jobs_wanted" -le 1 ]]; then
  for suite in ${suites+"${suites[@]}"}; do
    ran=$((ran + 1))
    echo ""
    echo "== ${suite#"$TESTS_DIR"/} =="
    if ! bash "$suite"; then
      failed=$((failed + 1))
    fi
  done
else
  # A worker pool, not fixed batches: suite durations are very uneven (the
  # bootstrap suite alone is longer than several capability suites together),
  # and a batch that waits for its slowest member wastes most of the cores.
  # bash 3.2 has no `wait -n`, so the pool polls the running job count.
  # Start the slow suites first: bootstrap and cli are the longest by far, so
  # launching them last leaves the pool draining on one job at the end. The
  # report loop below still prints in the list's order, so output is stable.
  start_order=()
  for suite in ${suites+"${suites[@]}"}; do
    case "$suite" in
      */bootstrap.sh|*/cli.sh)
        start_order=("$suite" ${start_order+"${start_order[@]}"}) ;;
      *)
        start_order[${#start_order[@]}]="$suite" ;;
    esac
  done
  for suite in ${start_order+"${start_order[@]}"}; do
    while [[ "$(jobs -pr | wc -l | tr -d ' ')" -ge "$jobs_wanted" ]]; do
      sleep 0.2
    done
    key="$(suite_key "$suite")"
    # Each job writes its own log and exit code; nothing is shared but $out_dir.
    ( bash "$suite" > "$out_dir/$key.log" 2>&1; printf '%s\n' "$?" > "$out_dir/$key.rc" ) &
  done
  wait
  for suite in ${suites+"${suites[@]}"}; do
    key="$(suite_key "$suite")"
    report "$suite" "$out_dir/$key.log" "$out_dir/$key.rc"
  done
fi

echo ""
if [[ $ran -eq 0 ]]; then
  echo "No test suites found."
  exit 0
fi
if [[ $failed -eq 0 ]]; then
  echo "All $ran suites passed."
  exit 0
fi
echo "$failed of $ran suites failed."
exit 1
