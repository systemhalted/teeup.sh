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
  export TEEUP_TEST_MISSING="ghostty"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_gets_the_cask() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install ghostty)"
  assert_contains "$out" "Would execute: brew install --cask ghostty" || return 1
  cleanup_test_env
}

test_install_is_not_applicable_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  source "$TEEUP_PATH/lib/all.sh"
  local out
  out="$(DRY_RUN=false cap_install_verbs ghostty 2>&1)"
  assert_contains "$out" "Ghostty is a Homebrew cask and MacPorts has no Ghostty port" || return 1
  assert_not_contains "$out" "port install" || return 1
  state_done check "cap-ghostty" && { echo "must not be marked done"; return 1; }
  state_na check "cap-ghostty" || { echo "must be marked not-applicable"; return 1; }
  out="$(DRY_RUN=false "$TEEUP" status)"
  assert_contains "$out" "ghostty" || return 1
  assert_contains "$out" "not applicable on this machine" || return 1
  cleanup_test_env
}

test_install_is_not_applicable_below_macos_13() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command sw_vers 0 "12.6.8"
  local out
  out="$(DRY_RUN=false cap_install_verbs ghostty 2>&1)"
  assert_contains "$out" "Ghostty requires macOS 13 or newer; this Mac is on macOS 12" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew install" || return 1
  state_done check "cap-ghostty" && { echo "must not be marked done"; return 1; }
  state_na check "cap-ghostty" || { echo "must be marked not-applicable"; return 1; }
  cleanup_test_env
}

test_configure_gives_guidance_only_for_an_installed_ghostty() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ghostty 2>&1)"
  assert_not_contains "$out" "run ghostty" || return 1
  mkdir -p "$TEEUP_APPS_DIR/Ghostty.app"
  unset TEEUP_TEST_MISSING
  mock_command ghostty 0 ""
  out="$(DRY_RUN=false "$TEEUP" configure ghostty)"
  assert_contains "$out" "teeup launch ghostty" || return 1
  assert_contains "$out" "run ghostty in a project directory" || return 1
  cleanup_test_env
}

test_launch_installs_then_opens() {
  setup
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "list "*) exit 1 ;;
  "install --cask") mkdir -p "$TEEUP_APPS_DIR/Ghostty.app" ;;
esac
exit 0
EOF2
  local out
  out="$(DRY_RUN=false "$TEEUP" launch Ghostty)"
  assert_contains "$out" "Ghostty is not installed; installing ghostty first." || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew install --cask ghostty" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "open -a Ghostty" || return 1
  "$TEEUP" has ghostty || { echo "ghostty must be marked installed"; return 1; }
  cleanup_test_env
}

test_launch_reports_not_applicable_instead_of_installed() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" launch ghostty 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "ghostty is not applicable on this machine; Ghostty was not installed" || return 1
  assert_not_contains "$out" "after installing ghostty" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "open -a Ghostty" || return 1
  cleanup_test_env
}

echo "capabilities/ghostty"
run_test "install gets the cask" test_install_gets_the_cask
run_test "install is not applicable on macports" test_install_is_not_applicable_on_macports
run_test "install is not applicable below macOS 13" test_install_is_not_applicable_below_macos_13
run_test "configure gives guidance only for an installed ghostty" test_configure_gives_guidance_only_for_an_installed_ghostty
run_test "launch installs then opens" test_launch_installs_then_opens
run_test "launch reports not-applicable instead of installed" test_launch_reports_not_applicable_instead_of_installed
print_summary
