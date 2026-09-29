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
  export TEEUP_TEST_MISSING="alacritty"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_gets_the_cask() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install alacritty)"
  assert_contains "$out" "Would execute: brew install --cask alacritty" || return 1
  cleanup_test_env
}

test_install_is_not_applicable_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  source "$TEEUP_PATH/lib/all.sh"
  local out
  out="$(DRY_RUN=false cap_install_verbs alacritty 2>&1)"
  assert_contains "$out" "Alacritty is a Homebrew cask and MacPorts has no Alacritty port" || return 1
  assert_not_contains "$out" "port install" || return 1
  state_done check "cap-alacritty" && { echo "must not be marked done"; return 1; }
  state_na check "cap-alacritty" || { echo "must be marked not-applicable"; return 1; }
  out="$(DRY_RUN=false "$TEEUP" status)"
  assert_contains "$out" "alacritty" || return 1
  assert_contains "$out" "not applicable on this machine" || return 1
  cleanup_test_env
}

test_configure_gives_guidance_only_for_an_installed_alacritty() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure alacritty 2>&1)"
  assert_not_contains "$out" "run alacritty" || return 1
  mkdir -p "$TEEUP_APPS_DIR/Alacritty.app"
  unset TEEUP_TEST_MISSING
  mock_command alacritty 0 ""
  out="$(DRY_RUN=false "$TEEUP" configure alacritty)"
  assert_contains "$out" "teeup launch alacritty" || return 1
  assert_contains "$out" "run alacritty in a project directory" || return 1
  cleanup_test_env
}

test_launch_installs_then_opens() {
  setup
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "list "*) exit 1 ;;
  "install --cask") mkdir -p "$TEEUP_APPS_DIR/Alacritty.app" ;;
esac
exit 0
EOF2
  local out
  out="$(DRY_RUN=false "$TEEUP" launch Alacritty)"
  assert_contains "$out" "Alacritty is not installed; installing alacritty first." || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew install --cask alacritty" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "open -a Alacritty" || return 1
  "$TEEUP" has alacritty || { echo "alacritty must be marked installed"; return 1; }
  cleanup_test_env
}

test_the_alacritty_command_gets_a_shim() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  assert_contains "$(cat "$TEST_HOME/.local/state/teeup/shims/alacritty")" 'lazy-run alacritty alacritty "$@"' || return 1
  assert_contains "$("$TEEUP" list --tier lazy)" "[on first: alacritty; launch: Alacritty]" || return 1
  cleanup_test_env
}

test_lazy_run_reports_not_applicable_instead_of_installed() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  export TEEUP_NO_GUM=1
  mock_command port 0 ""
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local rc=0 out shim
  shim="$TEST_HOME/.local/state/teeup/shims/alacritty"
  out="$(printf 'y\n' | TEEUP_TEST_TTY=yes DRY_RUN=false "$shim" . 2>&1)" || rc=$?
  assert_equals "127" "$rc" || return 1
  assert_contains "$out" "alacritty is not applicable on this machine; alacritty was not installed" || return 1
  assert_not_contains "$out" "alacritty is installed" || return 1
  cleanup_test_env
}

test_launch_reports_not_applicable_instead_of_installed() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" launch alacritty 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "alacritty is not applicable on this machine; Alacritty was not installed" || return 1
  assert_not_contains "$out" "after installing alacritty" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "open -a Alacritty" || return 1
  cleanup_test_env
}

echo "capabilities/alacritty"
run_test "install gets the cask" test_install_gets_the_cask
run_test "install is not applicable on macports" test_install_is_not_applicable_on_macports
run_test "configure gives guidance only for an installed alacritty" test_configure_gives_guidance_only_for_an_installed_alacritty
run_test "launch installs then opens" test_launch_installs_then_opens
run_test "the alacritty command gets a shim" test_the_alacritty_command_gets_a_shim
run_test "lazy-run reports not-applicable instead of installed" test_lazy_run_reports_not_applicable_instead_of_installed
run_test "launch reports not-applicable instead of installed" test_launch_reports_not_applicable_instead_of_installed
print_summary
