#!/usr/bin/env bash
# test_teeup_behavior.sh — Behavioral tests for teeup.sh
#
# Usage: ./tests/test_teeup_behavior.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/test_helper.sh"

echo "========================================"
echo "Testing teeup.sh behavior"
echo "========================================"

test_isolated_test_env() {
  setup_test_env
  trap cleanup_test_env RETURN

  assert_dir_exists "$HOME" "Should set HOME to a temp directory"
  assert_file_exists "$ZSHRC" "Should create isolated zshrc"
  assert_file_exists "$ZPROFILE" "Should create isolated zprofile"
  assert_dir_exists "$MOCK_BIN" "Should create mock command directory"
}

test_macos_command_mocks() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_macos_base_commands

  assert_equals "Darwin" "$(uname -s)" "Should mock macOS uname"
  assert_equals "14.6.1" "$(sw_vers -productVersion)" "Should mock macOS version"
}

echo ""
echo "Running tests..."
echo ""

run_test "Isolated test environment" test_isolated_test_env
run_test "macOS command mocks" test_macos_command_mocks

print_summary
