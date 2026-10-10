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
  out="$(DRY_RUN=true "$TEEUP" install raycast)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask raycast" || return 1
  cleanup_test_env
}

test_install_warns_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  local rc=0 out
  out="$(DRY_RUN=true "$TEEUP" install raycast 2>&1)" || rc=$?
  assert_success "$rc" "a missing cask must not fail the install" || return 1
  assert_contains "$out" "Raycast is a cask and MacPorts has no port of it" || return 1
  assert_not_contains "$out" "brew install --cask" || return 1
  assert_not_contains "$out" "port install" || return 1
  cleanup_test_env
}

test_configure_reports_the_app() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure raycast)"
  assert_contains "$out" "Raycast.app is not in $TEST_HOME/Applications or ~/Applications; run: teeup install raycast" || return 1
  mkdir -p "$TEST_HOME/Applications/Raycast.app"
  out="$(DRY_RUN=false "$TEEUP" configure raycast)"
  assert_contains "$out" "Raycast is installed; open it with: open -a 'Raycast'" || return 1
  cleanup_test_env
}

# Casks can install into ~/Applications. A Raycast there is installed, also on
# a MacPorts Mac, where configure must not call the capability not applicable.
test_configure_finds_raycast_in_the_home_applications() {
  setup
  mkdir -p "$HOME/Applications/Raycast.app"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure raycast)"
  assert_contains "$out" "Raycast is installed; open it with: open -a 'Raycast'" "Homebrew" || return 1
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  out="$(DRY_RUN=false "$TEEUP" configure raycast 2>&1)"
  assert_contains "$out" "Raycast is installed; open it with: open -a 'Raycast'" "MacPorts" || return 1
  assert_not_contains "$out" "not applicable" "MacPorts" || return 1
  cleanup_test_env
}

test_configure_writes_nothing_in_a_dry_run() {
  setup
  local before after
  before="$(find "$TEST_HOME" -type f | sort)"
  DRY_RUN=true "$TEEUP" configure raycast >/dev/null 2>&1
  after="$(find "$TEST_HOME" -type f | sort)"
  assert_equals "$before" "$after" "a dry run must write nothing" || return 1
  cleanup_test_env
}

# raycast_provides -> the capability's provides= value.
raycast_provides() {
  (
    # shellcheck source=/dev/null
    . "$TEEUP_PATH/capabilities/raycast/capability"
    printf '%s' "${provides:-}"
  )
}

# Raycast ships an app and no command, so a `raycast` shim would install the
# app and then fail to find a command to run.
test_there_is_no_raycast_command_shim() {
  setup
  assert_equals "" "$(raycast_provides)" "provides must be empty" || return 1
  cleanup_test_env
}

test_the_tier_is_lazy() {
  setup
  assert_contains "$("$TEEUP" list --tier lazy)" "raycast" || return 1
  if grep -qx "raycast" "$TEEUP_PATH/capabilities/daily.list"; then
    echo "raycast must not be in daily.list"; return 1
  fi
  cleanup_test_env
}

test_the_menu_offers_raycast() {
  setup
  assert_contains "$(cat "$TEEUP_PATH/share/teeup/menu.json")" '"install.apps.raycast": {"label": "Raycast", "when": "! teeup has raycast", "action": "teeup install raycast"}' || return 1
  cleanup_test_env
}

echo "capabilities/raycast"
run_test "install dry run gets the cask" test_install_dry_run_gets_the_cask
run_test "install warns on MacPorts" test_install_warns_on_macports
run_test "configure reports the app" test_configure_reports_the_app
run_test "configure finds Raycast in ~/Applications" test_configure_finds_raycast_in_the_home_applications
run_test "configure writes nothing in a dry run" test_configure_writes_nothing_in_a_dry_run
run_test "there is no raycast command shim" test_there_is_no_raycast_command_shim
run_test "the tier is lazy" test_the_tier_is_lazy
run_test "the menu offers Raycast" test_the_menu_offers_raycast
print_summary
