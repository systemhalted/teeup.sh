#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  # `--version` answers for real: an exit-0, silent brew reads as "cannot
  # answer" (lib/doctor.sh's doctor_backend_can_answer), which used to switch
  # off the cask check below in silence (NI2).
  mock_command_script brew <<'EOF2'
case "$1" in
  --version) echo "Homebrew 4.3.9" ;;
  list) exit 1 ;;
  tap) exit 0 ;;
  *) exit 0 ;;
esac
EOF2
  # configure and doctor probe /Applications outside run_cmd; an empty tree
  # keeps their output the same on a developer's Mac and on CI.
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  TEEUP="$TEEUP_PATH/bin/teeup"
  AERO="$TEST_HOME/.config/aerospace/aerospace.toml"
}

test_install_taps_then_installs_the_cask() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install aerospace)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew tap nikitabobko/tap" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask nikitabobko/tap/aerospace" || return 1
  cleanup_test_env
}

test_install_skips_the_tap_when_present() {
  setup
  mock_command_script brew <<'EOF2'
case "$1" in
  list) exit 1 ;;
  tap) echo "nikitabobko/tap"; exit 0 ;;
  *) exit 0 ;;
esac
EOF2
  local out
  out="$(DRY_RUN=true "$TEEUP" install aerospace)"
  assert_contains "$out" "Already tapped: nikitabobko/tap" || return 1
  assert_not_contains "$out" "Would execute: brew tap" || return 1
  cleanup_test_env
}

test_install_is_skipped_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install aerospace 2>&1)"
  assert_contains "$out" "AeroSpace is a cask and MacPorts has none" || return 1
  assert_not_contains "$out" "brew install" || return 1
  assert_not_contains "$out" "brew tap" || return 1
  cleanup_test_env
}

# AeroSpace's README states its floor as macOS 13+; below that the binary
# cannot launch, so install must say so and touch nothing rather than tap
# and fetch a cask that will never run.
# cap_run, not `teeup install aerospace`: going through the full command
# would also pull in package-manager, whose own macOS-12-or-older branch
# picks MacPorts and is a different capability's concern. This is aerospace's
# own install script in isolation, the way the doctor tests below exercise it.
test_install_skips_below_the_macos_minimum() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command sw_vers 0 "12.7.6"
  local rc=0 out
  out="$(DRY_RUN=false cap_run aerospace install 2>&1)" || rc=$?
  assert_success "$rc" "a machine below the minimum is unsupported, not an error" || return 1
  assert_contains "$out" "AeroSpace requires macOS 13 or newer; this Mac is on macOS 12, so there is nothing to install." || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew tap" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew install" || return 1
  cleanup_test_env
}

test_install_skips_below_the_macos_minimum_in_dry_run_too() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command sw_vers 0 "12.7.6"
  local rc=0 out
  out="$(DRY_RUN=true cap_run aerospace install 2>&1)" || rc=$?
  assert_success "$rc" "a machine below the minimum is unsupported, not an error" || return 1
  assert_contains "$out" "AeroSpace requires macOS 13 or newer; this Mac is on macOS 12, so there is nothing to install." || return 1
  assert_not_contains "$out" "Would execute: brew" || return 1
  cleanup_test_env
}

# cap_install_verbs (lib/capability.sh) is what `teeup install` and bootstrap
# actually call: it is the one place deciding state_done vs state_na, so this
# is the mechanism that fixed the real bug -- aerospace used to be marked
# done, and reported "installed" by `teeup status`, on a macOS 12 machine
# that never actually got it.
test_install_below_the_macos_minimum_leaves_no_done_marker() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command sw_vers 0 "12.7.6"
  DRY_RUN=false cap_install_verbs aerospace >/dev/null 2>&1
  state_done check "cap-aerospace" && { echo "must not be marked done"; return 1; }
  state_na check "cap-aerospace" || { echo "must be marked not-applicable"; return 1; }
  DRY_RUN=false "$TEEUP" has aerospace >/dev/null 2>&1 && { echo "has must report not-installed"; return 1; }
  local out
  out="$(DRY_RUN=false "$TEEUP" status)"
  assert_contains "$out" "not applicable on this machine" || return 1
  assert_not_contains "$out" "aerospace          installed" || return 1
  cleanup_test_env
}

test_install_at_the_macos_minimum_marks_done_as_before() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false cap_install_verbs aerospace >/dev/null 2>&1
  state_done check "cap-aerospace" || { echo "must be marked done"; return 1; }
  state_na check "cap-aerospace" && { echo "must not be marked not-applicable"; return 1; }
  DRY_RUN=false "$TEEUP" has aerospace || { echo "has must report installed"; return 1; }
  cleanup_test_env
}

test_install_runs_as_usual_at_the_macos_minimum() {
  setup
  mock_command sw_vers 0 "13.0"
  local out
  out="$(DRY_RUN=true "$TEEUP" install aerospace)"
  assert_not_contains "$out" "requires macOS 13 or newer" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: brew tap nikitabobko/tap" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask nikitabobko/tap/aerospace" || return 1
  cleanup_test_env
}

test_configure_copies_the_config_and_prints_the_manual_step() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace)"
  assert_file_exists "$AERO" || return 1
  assert_contains "$(cat "$AERO")" "alt-h = 'focus left'" || return 1
  assert_contains "$(cat "$AERO")" "start-at-login = true" || return 1
  assert_contains "$out" "Privacy & Security > Accessibility" || return 1
  assert_contains "$out" "AeroSpace will appear in /Applications" "the suite does not read the host's /Applications" || return 1
  cleanup_test_env
}

# On MacPorts, install just warned that casks (and so AeroSpace) do not
# exist and told the user to download it by hand; configure must not then
# contradict that by promising the cask will finish installing.
test_configure_tells_the_truth_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace 2>&1)"
  assert_not_contains "$out" "AeroSpace will appear in /Applications once its cask finishes installing" "MacPorts has no cask to finish installing" || return 1
  assert_contains "$out" "MacPorts has no AeroSpace cask" || return 1
  assert_contains "$out" "https://github.com/nikitabobko/AeroSpace/releases" || return 1
  cleanup_test_env
}

test_configure_tells_the_truth_on_macports_in_dry_run_too() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" configure aerospace 2>&1)"
  assert_not_contains "$out" "AeroSpace will appear in /Applications once its cask finishes installing" "MacPorts has no cask to finish installing" || return 1
  assert_contains "$out" "MacPorts has no AeroSpace cask" || return 1
  cleanup_test_env
}

test_the_manual_step_is_printed_in_full_once() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace)"
  assert_not_contains "$out" "One manual step, once per machine" || return 1
  assert_contains "$out" "If AeroSpace cannot move windows, turn it on under System Settings > Privacy & Security > Accessibility." || return 1
  cleanup_test_env
}

test_configure_keeps_an_existing_home_config() {
  setup
  # AeroSpace reads ~/.aerospace.toml and ~/.config/aerospace/aerospace.toml
  # and reports two configs as ambiguous, so a second one must not appear.
  printf 'start-at-login = false\n' > "$TEST_HOME/.aerospace.toml"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace)"
  [[ ! -e "$AERO" ]] || { echo "installed a second config next to ~/.aerospace.toml"; return 1; }
  assert_equals "start-at-login = false" "$(cat "$TEST_HOME/.aerospace.toml")" || return 1
  assert_contains "$out" "Keeping your $TEST_HOME/.aerospace.toml" || return 1
  cleanup_test_env
}

# Same floor for configure: below macOS 13 there is no app to point a
# config at and no Accessibility toggle worth naming, so nothing runs.
test_configure_skips_below_the_macos_minimum() {
  setup
  mock_command sw_vers 0 "12.7.6"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace 2>&1)"
  assert_contains "$out" "AeroSpace requires macOS 13 or newer; this Mac is on macOS 12, so there is nothing to configure." || return 1
  [[ ! -e "$AERO" ]] || { echo "wrote a config on an unsupported macOS"; return 1; }
  assert_not_contains "$out" "Privacy & Security > Accessibility" || return 1
  cleanup_test_env
}

test_configure_skips_below_the_macos_minimum_in_dry_run_too() {
  setup
  mock_command sw_vers 0 "12.7.6"
  local out
  out="$(DRY_RUN=true "$TEEUP" configure aerospace 2>&1)"
  assert_contains "$out" "AeroSpace requires macOS 13 or newer; this Mac is on macOS 12, so there is nothing to configure." || return 1
  [[ ! -e "$AERO" ]] || { echo "wrote a config on an unsupported macOS"; return 1; }
  assert_not_contains "$out" "Privacy & Security > Accessibility" || return 1
  cleanup_test_env
}

test_configure_runs_as_usual_at_the_macos_minimum() {
  setup
  mock_command sw_vers 0 "13.0"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace)"
  assert_not_contains "$out" "requires macOS 13 or newer" || return 1
  assert_file_exists "$AERO" || return 1
  assert_contains "$out" "Privacy & Security > Accessibility" || return 1
  cleanup_test_env
}

test_doctor_fails_when_both_configs_exist() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mkdir -p "$TEEUP_APPS_DIR/AeroSpace.app" "$(dirname "$AERO")"
  mock_command pgrep 0 ""
  printf 'x = 1\n' > "$TEST_HOME/.aerospace.toml"
  printf 'x = 1\n' > "$AERO"
  local rc=0 out
  out="$(DRY_RUN=false cap_run aerospace doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Two AeroSpace configs" || return 1
  cleanup_test_env
}

test_doctor_accepts_the_home_config() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mkdir -p "$TEEUP_APPS_DIR/AeroSpace.app"
  mock_command pgrep 0 ""
  printf 'x = 1\n' > "$TEST_HOME/.aerospace.toml"
  local rc=0 out
  out="$(DRY_RUN=false cap_run aerospace doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "AeroSpace config present: $TEST_HOME/.aerospace.toml" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace)"
  assert_contains "$out" "Already installed: $AERO" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  DRY_RUN=true "$TEEUP" configure aerospace >/dev/null
  [[ ! -e "$AERO" ]] || { echo "config written in dry run"; return 1; }
  cleanup_test_env
}

test_configure_dry_run_still_prints_the_cask_message() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" configure aerospace)"
  assert_contains "$out" "AeroSpace will appear in /Applications once its cask finishes installing" || return 1
  cleanup_test_env
}

test_doctor_reports_the_missing_config() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command pgrep 1 ""
  local rc=0 out
  out="$(DRY_RUN=false cap_run aerospace doctor 2>&1)" || rc=$?
  assert_failure "$rc" "doctor must exit non-zero when something is wrong" || return 1
  assert_contains "$out" "No aerospace.toml" || return 1
  cleanup_test_env
}

test_doctor_records_the_fix_for_the_finding() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command pgrep 1 ""
  local report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  DRY_RUN=false cap_run aerospace doctor >/dev/null 2>&1 || true
  assert_contains "$(cat "$report")" "teeup configure aerospace" || return 1
  assert_equals "1" "$(wc -l < "$report" | tr -d ' ')" "the running check is a warning, not a failure" || return 1
  cleanup_test_env
}

# I20: AeroSpace.app in ~/Applications (a real cask location app_installed
# already searches) must not fail this script's own, narrower /Applications
# check while doctor_metadata_check calls the same run healthy -- the two
# findings contradicting each other in one run, on a machine with nothing
# wrong.
test_doctor_does_not_contradict_the_metadata_check_on_home_applications() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command pgrep 0 ""
  mock_command_script brew <<'EOF2'
case "$1" in --version) echo "Homebrew 4.3.9" ;; esac
case "$1" in list) exit 0 ;; tap) exit 0 ;; *) exit 0 ;; esac
EOF2
  # TEEUP_APPS_DIR is this suite's stand-in for /Applications (setup, above);
  # point it somewhere empty so the app is found only through app_installed's
  # ~/Applications fallback, not through the same path this script checks.
  export TEEUP_APPS_DIR="$TEST_HOME/EmptyApplications"
  mkdir -p "$TEEUP_APPS_DIR"
  mkdir -p "$HOME/Applications/AeroSpace.app"
  printf 'x = 1\n' > "$TEST_HOME/.aerospace.toml"
  local report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  local out
  out="$(DRY_RUN=false doctor_run_one aerospace 2>&1)"
  assert_contains "$out" "AeroSpace.app is installed" || return 1
  assert_not_contains "$out" "not in /Applications" "app_installed found it; this script must not contradict that" || return 1
  assert_equals "" "$(cat "$report")" "a healthy machine is not a problem to fix" || return 1
  cleanup_test_env
}

echo "capabilities/aerospace"
run_test "install taps then installs the cask" test_install_taps_then_installs_the_cask
run_test "install skips the tap when present" test_install_skips_the_tap_when_present
run_test "install is skipped on macports" test_install_is_skipped_on_macports
run_test "install skips below the macOS minimum" test_install_skips_below_the_macos_minimum
run_test "install skips below the macOS minimum in dry run too" test_install_skips_below_the_macos_minimum_in_dry_run_too
run_test "install below the macOS minimum leaves no done marker" test_install_below_the_macos_minimum_leaves_no_done_marker
run_test "install at the macOS minimum marks done as before" test_install_at_the_macos_minimum_marks_done_as_before
run_test "install runs as usual at the macOS minimum" test_install_runs_as_usual_at_the_macos_minimum
run_test "configure copies the config and prints the manual step" test_configure_copies_the_config_and_prints_the_manual_step
run_test "configure skips below the macOS minimum" test_configure_skips_below_the_macos_minimum
run_test "configure skips below the macOS minimum in dry run too" test_configure_skips_below_the_macos_minimum_in_dry_run_too
run_test "configure runs as usual at the macOS minimum" test_configure_runs_as_usual_at_the_macos_minimum
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "configure dry run still prints the cask message" test_configure_dry_run_still_prints_the_cask_message
run_test "configure tells the truth on macports" test_configure_tells_the_truth_on_macports
run_test "configure tells the truth on macports in dry run too" test_configure_tells_the_truth_on_macports_in_dry_run_too
run_test "the manual step is printed in full once" test_the_manual_step_is_printed_in_full_once
run_test "configure keeps an existing ~/.aerospace.toml" test_configure_keeps_an_existing_home_config
run_test "doctor fails when both configs exist" test_doctor_fails_when_both_configs_exist
run_test "doctor accepts ~/.aerospace.toml" test_doctor_accepts_the_home_config
run_test "doctor reports the missing config" test_doctor_reports_the_missing_config
run_test "doctor records the fix for the finding" test_doctor_records_the_fix_for_the_finding
run_test "doctor does not contradict the metadata check on ~/Applications" test_doctor_does_not_contradict_the_metadata_check_on_home_applications
print_summary
