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

test_dryrun_legacy_python_does_not_write_config() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_macos_base_commands
  mock_package_manager_commands
  mock_python_commands

  local output
  output=$(DRY_RUN=true USE_UV=false PACKAGE_MANAGER=homebrew INSTALL_DOTFILES=true "$PROJECT_DIR/teeup.sh" --only python 2>&1)

  assert_contains "$output" "[DRY-RUN] Would execute: pipx ensurepath" "Should preview pipx ensurepath"
  assert_contains "$output" "[DRY-RUN] Would execute: pipx install poetry" "Should preview pipx installs"
  assert_equals "" "$(cat "$ZSHRC")" "Dry-run should not write zshrc"
  assert_equals "" "$(cat "$ZPROFILE")" "Dry-run should not write zprofile"
}

test_uv_python_only_skips_package_manager() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_macos_base_commands
  mock_python_commands

  local output
  output=$(DRY_RUN=true USE_UV=true "$PROJECT_DIR/teeup.sh" --only python 2>&1)

  assert_contains "$output" "Skipping package manager setup (RUN_HOMEBREW=false)" "UV-only Python should not require package manager"
}

test_legacy_python_only_enables_package_manager() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_macos_base_commands
  mock_package_manager_commands
  mock_python_commands

  local output
  output=$(DRY_RUN=true USE_UV=false PACKAGE_MANAGER=homebrew "$PROJECT_DIR/teeup.sh" --only python 2>&1)

  assert_contains "$output" "Preparing Homebrew" "Legacy Python should prepare package manager"
}

test_package_backed_modules_enable_package_manager() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_macos_base_commands
  mock_package_manager_commands

  local output
  output=$(DRY_RUN=true PACKAGE_MANAGER=homebrew "$PROJECT_DIR/teeup.sh" --only cli 2>&1)

  assert_contains "$output" "Preparing Homebrew" "CLI module should prepare package manager"
  assert_contains "$output" "[DRY-RUN] Would execute: brew update" "Should preview package-manager update"
}

test_macports_dryrun_warns_when_port_missing() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_macos_base_commands

  local output
  output=$(DRY_RUN=true PACKAGE_MANAGER=macports MACPORTS_PREFIX="$TEST_HOME/no-macports" "$PROJECT_DIR/teeup.sh" --only cli 2>&1)

  assert_contains "$output" "MacPorts is selected but the 'port' command is not available" "Should explain missing MacPorts"
  assert_contains "$output" "Continuing dry-run without MacPorts installed" "Should continue dry-run"
}

test_macports_apps_skip_casks_without_fallback() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_macos_base_commands

  local output
  output=$(DRY_RUN=true PACKAGE_MANAGER=macports MACPORTS_PREFIX="$TEST_HOME/no-macports" "$PROJECT_DIR/teeup.sh" --only apps 2>&1)

  assert_contains "$output" "Skipping GUI app casks in MacPorts mode" "Should skip casks without fallback"
  assert_contains "$output" "bruno (cask; MacPorts mode)" "Should record Bruno as skipped"
  assert_contains "$output" "obsidian (cask; MacPorts mode)" "Should record Obsidian as skipped"
}

echo ""
echo "Running tests..."
echo ""

run_test "Isolated test environment" test_isolated_test_env
run_test "macOS command mocks" test_macos_command_mocks
run_test "Dry-run legacy Python config isolation" test_dryrun_legacy_python_does_not_write_config
run_test "UV Python skips package manager" test_uv_python_only_skips_package_manager
run_test "Legacy Python enables package manager" test_legacy_python_only_enables_package_manager
run_test "Package-backed modules enable package manager" test_package_backed_modules_enable_package_manager
run_test "MacPorts dry-run missing port" test_macports_dryrun_warns_when_port_missing
run_test "MacPorts apps skip casks" test_macports_apps_skip_casks_without_fallback

print_summary
