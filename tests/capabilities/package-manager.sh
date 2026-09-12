#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_bootstraps_homebrew_in_dry_run() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install package-manager)"
  assert_contains "$out" "Homebrew/install/HEAD/install.sh" || return 1
  assert_contains "$out" "Would execute: brew update" || return 1
  cleanup_test_env
}

test_install_refuses_missing_macports() {
  setup
  mock_command sw_vers 0 "12.7.1"
  local rc=0 out
  out="$(DRY_RUN=true "$TEEUP" install package-manager 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "MacPorts is not installed" || return 1
  cleanup_test_env
}

test_configure_records_backend_in_answers() {
  setup
  mock_command brew 0 ""
  DRY_RUN=false "$TEEUP" configure package-manager >/dev/null
  assert_contains "$(cat "$TEST_HOME/.config/teeup/answers")" 'TEEUP_PACKAGE_MANAGER="homebrew"' || return 1
  cleanup_test_env
}

test_configure_keeps_existing_answer() {
  setup
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_PACKAGE_MANAGER="macports"\n' > "$TEST_HOME/.config/teeup/answers"
  mock_command port 0 ""
  DRY_RUN=false "$TEEUP" configure package-manager >/dev/null
  assert_contains "$(cat "$TEST_HOME/.config/teeup/answers")" 'TEEUP_PACKAGE_MANAGER="macports"' || return 1
  cleanup_test_env
}

echo "capabilities/package-manager"
run_test "install bootstraps Homebrew in dry run" test_install_bootstraps_homebrew_in_dry_run
run_test "install refuses missing MacPorts" test_install_refuses_missing_macports
run_test "configure records backend in answers" test_configure_records_backend_in_answers
run_test "configure keeps existing answer" test_configure_keeps_existing_answer
print_summary
