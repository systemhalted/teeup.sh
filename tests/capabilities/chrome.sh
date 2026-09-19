#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_dry_run_gets_the_cask() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install chrome)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask google-chrome" || return 1
  cleanup_test_env
}

test_install_skips_an_installed_cask() {
  setup
  mock_command_script brew <<'EOF2'
case "$1 ${2:-} ${3:-}" in "list --cask google-chrome") exit 0 ;; list*) exit 1 ;; *) exit 0 ;; esac
EOF2
  local out
  out="$(DRY_RUN=true "$TEEUP" install chrome)"
  assert_contains "$out" "Already installed: google-chrome (cask)" || return 1
  assert_not_contains "$out" "brew install --cask google-chrome" || return 1
  cleanup_test_env
}

test_install_warns_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  local rc=0 out
  out="$(DRY_RUN=true "$TEEUP" install chrome 2>&1)" || rc=$?
  assert_success "$rc" "a missing cask must not fail the install" || return 1
  assert_contains "$out" "Google Chrome is a cask and MacPorts has no port of it" || return 1
  assert_not_contains "$out" "brew install --cask" || return 1
  assert_not_contains "$out" "port install" || return 1
  cleanup_test_env
}

test_configure_reports_the_app() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure chrome)"
  assert_contains "$out" "Google Chrome.app is not in $TEST_HOME/Applications" || return 1
  # M4: a standalone `teeup configure chrome` has no install step above it,
  # so it must say what is actually known, not point at a step that never ran.
  assert_contains "$out" "run: teeup install chrome" || return 1
  assert_not_contains "$out" "the install step above says why" || return 1
  mkdir -p "$TEST_HOME/Applications/Google Chrome.app"
  out="$(DRY_RUN=false "$TEEUP" configure chrome)"
  assert_contains "$out" "Google Chrome is installed; open it with: open -a 'Google Chrome'" || return 1
  cleanup_test_env
}

test_configure_runs_no_command() {
  setup
  DRY_RUN=false "$TEEUP" configure chrome >/dev/null || return 1
  # answers_load's hostname lookup is the harness's, not the capability's;
  # the not_applicable guard's own macos_major/casks_supported checks read
  # sw_vers the same read-only way, to tell whether this machine can ever
  # have Chrome.
  assert_equals "" "$(grep -Ev '^(hostname|sw_vers)' "$MOCK_LOG" || true)" "configure ran a command" || return 1
  [[ ! -e "$TEST_HOME/.config/teeup/answers" ]] || { echo "configure wrote an answer"; return 1; }
  cleanup_test_env
}

test_the_tier_is_lazy() {
  setup
  assert_contains "$("$TEEUP" list --tier lazy)" "chrome" || return 1
  if grep -qx "chrome" "$TEEUP_PATH/capabilities/daily.list" "$TEEUP_PATH/capabilities/core.list"; then
    echo "chrome is lazy but sits in a tier list"
    return 1
  fi
  cleanup_test_env
}

echo "capabilities/chrome"
run_test "install dry run gets the cask" test_install_dry_run_gets_the_cask
run_test "install skips an installed cask" test_install_skips_an_installed_cask
run_test "install warns on macports" test_install_warns_on_macports
run_test "configure reports the app" test_configure_reports_the_app
run_test "configure runs no command" test_configure_runs_no_command
run_test "the tier is lazy" test_the_tier_is_lazy
print_summary
