#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/helper.sh"

setup() {
  setup_test_env
}

test_suite_timeouts_kill_the_suite_and_carry_on() {
  setup

  local copy="$TEST_HOME/checkout"
  mkdir -p "$copy/tests/capabilities" "$copy/tests/lib"

  # Copy enough to make run.sh work
  cp -p "$TEEUP_PATH/tests/helper.sh" "$copy/tests/helper.sh"
  cp -p "$TEEUP_PATH/tests/run.sh" "$copy/tests/run.sh"

  # The runner will test these two files
  printf '#!/usr/bin/env bash\nsleep 10\n' > "$copy/tests/capabilities/sleeps.sh"
  chmod +x "$copy/tests/capabilities/sleeps.sh"

  printf '#!/usr/bin/env bash\necho "Other suite ran"\n' > "$copy/tests/capabilities/other.sh"
  chmod +x "$copy/tests/capabilities/other.sh"

  local rc=0 out=""
  out="$(cd "$copy" && TEEUP_TEST_SUITE_TIMEOUT=2 ./tests/run.sh 2>&1)" || rc=$?

  assert_failure "$rc" || return 1
  assert_contains "$out" "TIMEOUT: tests/capabilities/sleeps.sh after 2s" "timeout must print correctly: $out" || return 1
  assert_contains "$out" "Other suite ran" "other suites must still run: $out" || return 1
  assert_contains "$out" "1 of 2 suites failed." "summary must be correct: $out" || return 1

  cleanup_test_env
}

run_test "a hung test suite times out" test_suite_timeouts_kill_the_suite_and_carry_on

print_summary
