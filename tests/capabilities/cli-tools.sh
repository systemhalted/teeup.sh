#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  # A fresh Mac has none of these.
  export TEEUP_TEST_MISSING="rg fd fzf bat eza zoxide jq yq btop tldr dust gpg"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_uses_package_and_command_pairs() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install cli-tools 2>&1)"
  assert_contains "$out" "Would execute: brew install ripgrep" || return 1
  assert_contains "$out" "Would execute: brew install fd" || return 1
  assert_contains "$out" "Would execute: brew install gnupg" || return 1
  assert_contains "$out" "Would execute: brew install dust" || return 1
  cleanup_test_env
}

test_install_skips_tools_already_on_path() {
  setup
  export TEEUP_TEST_MISSING="rg fd fzf bat eza zoxide yq btop tldr dust gpg"
  mock_command jq 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install cli-tools 2>&1)"
  assert_contains "$out" "Already available on PATH: jq" || return 1
  assert_not_contains "$out" "brew install jq" || return 1
  cleanup_test_env
}

test_install_warns_but_survives_a_missing_port() {
  setup
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "list"*) exit 1 ;;
  "install dust") exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" install cli-tools 2>&1)" || rc=$?
  assert_success "$rc" "one missing tool must not fail the capability" || return 1
  assert_contains "$out" "Could not install: dust" || return 1
  cleanup_test_env
}

test_configure_writes_the_bat_config() {
  setup
  DRY_RUN=false "$TEEUP" configure cli-tools >/dev/null
  assert_file_exists "$TEST_HOME/.config/bat/config" || return 1
  local body
  body="$(cat "$TEST_HOME/.config/bat/config")"
  assert_contains "$body" "--style=numbers,changes,header" || return 1
  assert_not_contains "$body" "--theme" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  DRY_RUN=false "$TEEUP" configure cli-tools >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure cli-tools)"
  assert_contains "$out" "Already installed: $TEST_HOME/.config/bat/config" || return 1
  cleanup_test_env
}

echo "capabilities/cli-tools"
run_test "install uses package and command pairs" test_install_uses_package_and_command_pairs
run_test "install skips tools already on PATH" test_install_skips_tools_already_on_path
run_test "install warns but survives a missing port" test_install_warns_but_survives_a_missing_port
run_test "configure writes the bat config" test_configure_writes_the_bat_config
run_test "configure is idempotent" test_configure_is_idempotent
print_summary
