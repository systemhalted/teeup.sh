#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  mock_command open 0 ""
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_gets_the_cask() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install iterm2)"
  assert_contains "$out" "Would execute: brew install --cask iterm2" || return 1
  cleanup_test_env
}

test_install_is_not_applicable_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  source "$TEEUP_PATH/lib/all.sh"
  local out
  out="$(DRY_RUN=false cap_install_verbs iterm2 2>&1)"
  assert_contains "$out" "iTerm2 is a Homebrew cask and MacPorts has no iTerm2 port" || return 1
  assert_not_contains "$out" "port install" || return 1
  state_done check "cap-iterm2" && { echo "must not be marked done"; return 1; }
  state_na check "cap-iterm2" || { echo "must be marked not-applicable"; return 1; }
  out="$(DRY_RUN=false "$TEEUP" status)"
  assert_contains "$out" "iterm2" || return 1
  assert_contains "$out" "not applicable on this machine" || return 1
  cleanup_test_env
}

test_install_is_not_applicable_below_macos_13() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command sw_vers 0 "12.6.8"
  local out
  out="$(DRY_RUN=false cap_install_verbs iterm2 2>&1)"
  assert_contains "$out" "iTerm2 requires macOS 13 or newer; this Mac is on macOS 12" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew install" || return 1
  state_done check "cap-iterm2" && { echo "must not be marked done"; return 1; }
  state_na check "cap-iterm2" || { echo "must be marked not-applicable"; return 1; }
  cleanup_test_env
}

test_configure_gives_guidance_only_for_an_installed_iterm2() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure iterm2 2>&1)"
  assert_not_contains "$out" "teeup launch iterm2" || return 1
  mkdir -p "$TEEUP_APPS_DIR/iTerm.app"
  out="$(DRY_RUN=false "$TEEUP" configure iterm2)"
  assert_contains "$out" "teeup launch iterm2" || return 1
  cleanup_test_env
}

test_launch_installs_then_opens() {
  setup
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "list "*) exit 1 ;;
  "install --cask") mkdir -p "$TEEUP_APPS_DIR/iTerm.app" ;;
esac
exit 0
EOF2
  local out
  out="$(DRY_RUN=false "$TEEUP" launch iTerm)"
  assert_contains "$out" "iTerm is not installed; installing iterm2 first." || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew install --cask iterm2" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "open -a iTerm" || return 1
  "$TEEUP" has iterm2 || { echo "iterm2 must be marked installed"; return 1; }
  cleanup_test_env
}

test_launch_reports_not_applicable_instead_of_installed() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" launch iterm2 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "iterm2 is not applicable on this machine; iTerm was not installed" || return 1
  assert_not_contains "$out" "after installing iterm2" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "open -a iTerm" || return 1
  cleanup_test_env
}

echo "capabilities/iterm2"
run_test "install gets the cask" test_install_gets_the_cask
run_test "install is not applicable on macports" test_install_is_not_applicable_on_macports
run_test "install is not applicable below macOS 13" test_install_is_not_applicable_below_macos_13
run_test "configure gives guidance only for an installed iterm2" test_configure_gives_guidance_only_for_an_installed_iterm2
run_test "launch installs then opens" test_launch_installs_then_opens
run_test "launch reports not-applicable instead of installed" test_launch_reports_not_applicable_instead_of_installed
print_summary
