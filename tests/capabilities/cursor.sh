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
  export TEEUP_TEST_MISSING="cursor"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_gets_the_cask() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install cursor)"
  assert_contains "$out" "Would execute: brew install --cask cursor" || return 1
  cleanup_test_env
}

test_install_is_not_applicable_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  source "$TEEUP_PATH/lib/all.sh"
  local out
  out="$(DRY_RUN=false cap_install_verbs cursor 2>&1)"
  assert_contains "$out" "Cursor is a Homebrew cask and MacPorts has no Cursor port" || return 1
  assert_not_contains "$out" "port install" || return 1
  state_done check "cap-cursor" && { echo "must not be marked done"; return 1; }
  state_na check "cap-cursor" || { echo "must be marked not-applicable"; return 1; }
  out="$(DRY_RUN=false "$TEEUP" status)"
  assert_contains "$out" "cursor" || return 1
  assert_contains "$out" "not applicable on this machine" || return 1
  cleanup_test_env
}

test_install_is_not_applicable_below_macos_12() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command sw_vers 0 "11.7.10"
  local out
  out="$(DRY_RUN=false cap_install_verbs cursor 2>&1)"
  assert_contains "$out" "Cursor requires macOS 12 or newer; this Mac is on macOS 11" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew install" || return 1
  state_done check "cap-cursor" && { echo "must not be marked done"; return 1; }
  state_na check "cap-cursor" || { echo "must be marked not-applicable"; return 1; }
  cleanup_test_env
}

test_configure_gives_guidance_only_for_an_installed_cursor() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure cursor 2>&1)"
  assert_not_contains "$out" "run cursor" || return 1
  mkdir -p "$TEEUP_APPS_DIR/Cursor.app"
  unset TEEUP_TEST_MISSING
  mock_command cursor 0 ""
  out="$(DRY_RUN=false "$TEEUP" configure cursor)"
  assert_contains "$out" "teeup launch cursor" || return 1
  assert_contains "$out" "run cursor in a project directory" || return 1
  cleanup_test_env
}

test_launch_installs_then_opens() {
  setup
  # brew install --cask "installs" the bundle.
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "list "*) exit 1 ;;
  "install --cask") mkdir -p "$TEEUP_APPS_DIR/Cursor.app" ;;
esac
exit 0
EOF2
  local out
  out="$(DRY_RUN=false "$TEEUP" launch Cursor)"
  assert_contains "$out" "Cursor is not installed; installing cursor first." || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew install --cask cursor" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "open -a Cursor" || return 1
  "$TEEUP" has cursor || { echo "cursor must be marked installed"; return 1; }
  cleanup_test_env
}

test_the_cursor_command_gets_a_shim() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  assert_contains "$(cat "$TEST_HOME/.local/state/teeup/shims/cursor")" 'lazy-run cursor cursor "$@"' || return 1
  assert_contains "$("$TEEUP" list --tier lazy)" "[on first: cursor; launch: Cursor]" || return 1
  cleanup_test_env
}

test_lazy_run_reports_not_applicable_instead_of_installed() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  export TEEUP_NO_GUM=1
  mock_command port 0 ""
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local rc=0 out shim
  shim="$TEST_HOME/.local/state/teeup/shims/cursor"
  out="$(printf 'y\n' | TEEUP_TEST_TTY=yes DRY_RUN=false "$shim" . 2>&1)" || rc=$?
  assert_equals "127" "$rc" || return 1
  assert_contains "$out" "cursor is not applicable on this machine; cursor was not installed" || return 1
  assert_not_contains "$out" "cursor is installed" || return 1
  cleanup_test_env
}

test_launch_reports_not_applicable_instead_of_installed() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" launch cursor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "cursor is not applicable on this machine; Cursor was not installed" || return 1
  assert_not_contains "$out" "after installing cursor" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "open -a Cursor" || return 1
  cleanup_test_env
}

echo "capabilities/cursor"
run_test "install gets the cask" test_install_gets_the_cask
run_test "install is not applicable on macports" test_install_is_not_applicable_on_macports
run_test "install is not applicable below macOS 12" test_install_is_not_applicable_below_macos_12
run_test "configure gives guidance only for an installed cursor" test_configure_gives_guidance_only_for_an_installed_cursor
run_test "launch installs then opens" test_launch_installs_then_opens
run_test "the cursor command gets a shim" test_the_cursor_command_gets_a_shim
run_test "lazy-run reports not-applicable instead of installed" test_lazy_run_reports_not_applicable_instead_of_installed
run_test "launch reports not-applicable instead of installed" test_launch_reports_not_applicable_instead_of_installed
print_summary
