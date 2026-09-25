#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  source "$TEEUP_PATH/lib/all.sh"
}

test_install_asks_the_package_manager() {
  setup
  export TEEUP_TEST_MISSING="@NAME@"
  local out
  out="$(DRY_RUN=true cap_run @NAME@ install 2>&1)"
  assert_contains "$out" "Would execute: brew install @NAME@" || return 1
  cleanup_test_env
}

test_configure_writes_nothing_in_a_dry_run() {
  setup
  local before after
  before="$(find "$TEST_HOME" -type f | sort)"
  DRY_RUN=true cap_run @NAME@ configure >/dev/null 2>&1
  after="$(find "$TEST_HOME" -type f | sort)"
  assert_equals "$before" "$after" "a dry run must write nothing" || return 1
  cleanup_test_env
}

echo "capabilities/@NAME@"
run_test "install asks the package manager" test_install_asks_the_package_manager
run_test "configure writes nothing in a dry run" test_configure_writes_nothing_in_a_dry_run
print_summary
