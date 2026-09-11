#!/usr/bin/env bash
# run.sh - run every test file under tests/ and aggregate results.
set -euo pipefail

if [[ "${LC_ALL:-}" == "C.UTF-8" || "${LANG:-}" == "C.UTF-8" ]]; then
  export LANG="en_US.UTF-8"
  export LC_ALL="en_US.UTF-8"
fi

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0
ran=0

for suite in "$TESTS_DIR"/lib/*.sh "$TESTS_DIR"/capabilities/*.sh "$TESTS_DIR"/cli.sh "$TESTS_DIR"/bootstrap.sh; do
  [[ -f "$suite" ]] || continue
  ran=$((ran + 1))
  echo ""
  echo "== ${suite#"$TESTS_DIR"/} =="
  if ! bash "$suite"; then
    failed=$((failed + 1))
  fi
done

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
