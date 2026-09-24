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

# The settings adopted from the user's own tuned AeroSpace config (2026-09
# port): zero gaps, focus-follows-mouse off, workspaces 1-9 always present,
# and the Emacs-style aliases alongside the hjkl set.
test_configure_writes_the_tuned_defaults() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null
  local content
  content="$(cat "$AERO")"
  assert_contains "$content" "config-version = 2" || return 1
  assert_contains "$content" "inner.horizontal = 0" || return 1
  assert_contains "$content" "outer.right = 0" || return 1
  assert_contains "$content" "focus-follows-mouse.enabled = false" || return 1
  assert_contains "$content" "persistent-workspaces = ['1', '2', '3', '4', '5', '6', '7', '8', '9']" || return 1
  assert_contains "$content" "alt-backslash = 'layout tiling floating'" || return 1
  assert_contains "$content" "alt-ctrl-b = 'focus left'" || return 1
  assert_contains "$content" "alt-ctrl-shift-b = 'move left'" || return 1
  assert_contains "$content" "alt-ctrl-shift-b = ['join-with left', 'mode main']" || return 1
  cleanup_test_env
}

# A monitor layout is a fact about one desk, not a teeup default -- shipping
# it in the base would force a three-monitor layout onto every machine,
# including a single-monitor one. It belongs in local.toml instead (see the
# next two tests).
test_shipped_defaults_do_not_force_a_monitor_layout() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null
  # A real [table] header, not just teeup's own comment mentioning the name
  # (which the file does have, pointing at local.toml).
  assert_not_contains "$(cat "$AERO")" "
[workspace-to-monitor-force-assignment]
" "monitor layout is per-machine, not a teeup default" || return 1
  cleanup_test_env
}

# local.toml is copy_config_once'd (never touched again once installed), so
# a fresh machine gets it shipped with every entry commented out.
test_configure_installs_local_toml() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null
  local local_toml="$TEST_HOME/.config/aerospace/local.toml"
  assert_file_exists "$local_toml" || return 1
  assert_contains "$(cat "$local_toml")" "workspace-to-monitor-force-assignment" || return 1
  cleanup_test_env
}

# The merge rule's first two cases: a bare top-level key in local.toml
# replaces teeup's same key, and a [table] in local.toml replaces teeup's
# table of that name entirely rather than merging key by key.
test_local_toml_overrides_a_key_and_replaces_a_table() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null
  local local_toml="$TEST_HOME/.config/aerospace/local.toml"
  cat >> "$local_toml" <<'EOF'

start-at-login = false

[gaps]
inner.horizontal = 12
inner.vertical = 12
EOF
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null
  local content
  content="$(cat "$AERO")"
  assert_contains "$content" "start-at-login = false" || return 1
  assert_not_contains "$content" "start-at-login = true" || return 1
  assert_contains "$content" "inner.horizontal = 12" || return 1
  assert_not_contains "$content" "inner.horizontal = 0" "redefining [gaps] should replace the whole table, not merge into it" || return 1
  assert_not_contains "$content" "outer.right" "keys the local.toml [gaps] block did not repeat should be gone, not kept from the base table" || return 1
  cleanup_test_env
}

# The merge rule's third case: a [table] local.toml defines that teeup's
# base never mentions is appended, not dropped. workspace-to-monitor is the
# example teeup itself ships commented out in local.toml.
test_local_toml_monitor_assignment_lands_in_the_generated_file() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null
  local local_toml="$TEST_HOME/.config/aerospace/local.toml"
  cat >> "$local_toml" <<'EOF'

[workspace-to-monitor-force-assignment]
1 = 'main'
4 = '2'
7 = '3'
EOF
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null
  local content
  content="$(cat "$AERO")"
  assert_contains "$content" "[workspace-to-monitor-force-assignment]" || return 1
  assert_contains "$content" "4 = '2'" || return 1
  cleanup_test_env
}

# A machine with no overrides in local.toml (the shipped, all-commented
# stub) gets teeup's base back unchanged.
test_configure_with_no_local_overrides_gets_the_base_unchanged() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null
  assert_equals "$(cat "$TEEUP_PATH/capabilities/aerospace/config/aerospace/aerospace.toml")" "$(cat "$AERO")" || return 1
  cleanup_test_env
}

# aerospace.toml used to be the user's own copy-once file, so some machines
# have hand edits in it; those must survive a re-configure even when
# local.toml changed too, and the run should say why and point the way out.
test_hand_edited_aerospace_toml_is_not_regenerated() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null
  printf '\n# my own tweak, not from teeup\n' >> "$AERO"
  local local_toml="$TEST_HOME/.config/aerospace/local.toml"
  printf '\nstart-at-login = false\n' >> "$local_toml"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace)"
  assert_contains "$out" "Keeping your edited $AERO" || return 1
  assert_contains "$out" "$local_toml" "should point at local.toml for machine tweaks" || return 1
  assert_contains "$out" "teeup reset aerospace" || return 1
  local content
  content="$(cat "$AERO")"
  assert_contains "$content" "# my own tweak, not from teeup" "the hand edit must survive" || return 1
  assert_not_contains "$content" "start-at-login = false" "must not have regenerated over the hand-edited file" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing_even_with_local_overrides() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null
  local local_toml="$TEST_HOME/.config/aerospace/local.toml"
  printf '\nstart-at-login = false\n' >> "$local_toml"
  local before_aero before_local
  before_aero="$(cat "$AERO")"
  before_local="$(cat "$local_toml")"
  DRY_RUN=true "$TEEUP" configure aerospace >/dev/null
  assert_equals "$before_aero" "$(cat "$AERO")" "a dry run must not regenerate aerospace.toml" || return 1
  assert_equals "$before_local" "$(cat "$local_toml")" "a dry run must not touch local.toml either" || return 1
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
  # aerospace.toml is generated (base + local.toml), not copied, so a second
  # run says it is still at the version teeup generated rather than
  # "Already installed" (that wording is local.toml's own, still copy-once).
  assert_contains "$out" "Already at the shipped version: $AERO" || return 1
  assert_contains "$out" "Already installed: $TEST_HOME/.config/aerospace/local.toml" || return 1
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
# local.toml holds this machine's own settings -- the monitor assignment, for
# one. Someone runs `teeup reset aerospace` because the managed config is
# broken, not to lose the overrides they wrote by hand.
test_reset_leaves_the_local_override_alone() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null 2>&1
  local local_toml
  local_toml="$(user_config_dir)/aerospace/local.toml"
  assert_file_exists "$local_toml" || return 1
  printf "[workspace-to-monitor-force-assignment]\n1 = 'main'\n" > "$local_toml"
  local out
  out="$(DRY_RUN=false TEEUP_RESET=aerospace cap_run aerospace configure 2>&1)"
  assert_contains "$out" "leaves the local override file alone" || return 1
  assert_contains "$(cat "$local_toml")" "workspace-to-monitor-force-assignment" || return 1
  cleanup_test_env
}

# refresh_if_pristine returns 2 when teeup could not write the file at all (a
# read-only aerospace.toml, a full disk). The old file is then still in place
# and does not carry the local.toml settings this run merged, so finishing
# quietly would mark aerospace configured over a config that is not what teeup
# says it is.
test_configure_fails_when_the_generated_config_cannot_be_written() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null 2>&1
  local dest
  dest="$(user_config_dir)/aerospace/aerospace.toml"
  assert_file_exists "$dest" || return 1
  # Change local.toml so the next run has something new to write, then make
  # the destination unwritable.
  printf "[gaps]\ninner.horizontal = 42\n" >> "$(user_config_dir)/aerospace/local.toml"
  chmod 0444 "$dest"
  local rc=0 out
  out="$(DRY_RUN=false cap_run aerospace configure 2>&1)" || rc=$?
  chmod 0644 "$dest"
  assert_failure "$rc" "a config teeup could not write is not a configured capability" || return 1
  assert_contains "$out" "still on its previous configuration" || return 1
  if printf '%s\n' "$out" | grep -q 'inner.horizontal = 42'; then
    echo "claimed to have written settings it could not write"
    return 1
  fi
  cleanup_test_env
}

# The backstop: toml_merge_local is hand-written awk, not a TOML parser, and
# review keeps finding ways it can get a real local.toml wrong. Where
# AeroSpace itself is available to ask (`aerospace reload-config --dry-run`),
# it gets the last word before anything is installed, so a config it rejects
# never reaches ~/.config/aerospace/aerospace.toml and AeroSpace is never
# left to silently load nothing.
test_backstop_leaves_the_config_untouched_when_aerospace_rejects_it() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null 2>&1
  local before local_toml
  before="$(cat "$AERO")"
  local_toml="$TEST_HOME/.config/aerospace/local.toml"
  printf '\nstart-at-login = false\n' >> "$local_toml"
  mock_command_script aerospace <<'EOF2'
case "$1" in
  reload-config) echo "aerospace: config error: unexpected key on line 12" >&2; exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace 2>&1)" || rc=$?
  assert_failure "$rc" "a config AeroSpace rejects must fail the capability" || return 1
  assert_equals "$before" "$(cat "$AERO")" "the file already there must be left exactly as it was" || return 1
  assert_contains "$out" "$local_toml" "the message must name the file that could not be merged" || return 1
  assert_contains "$out" "unexpected key on line 12" "AeroSpace's own error must reach the user" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "aerospace reload-config" "must actually have asked AeroSpace" || return 1
  cleanup_test_env
}

# The commonest state on the machine this feature is for: AeroSpace is
# installed but has never been launched, so its socket answers nothing.
# reload-config fails there for a reason that has nothing to do with the
# config, and reading that as a rejection would refuse to install a perfectly
# good file on every fresh Mac.
# Staging a candidate at the destination to ask AeroSpace about it must never
# be how a dotfile-manager symlink gets replaced: the swap would put a regular
# file where the link was, and restore a regular file after -- destroying the
# link before refresh_config, which refuses symlinks for exactly this reason,
# ever sees it.
test_backstop_never_writes_through_a_symlinked_config() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null 2>&1
  local store="$TEST_HOME/dotfiles/aerospace.toml"
  mkdir -p "$(dirname "$store")"
  printf 'config-version = 2\n# managed elsewhere\n' > "$store"
  rm -f "$AERO"
  ln -s "$store" "$AERO"
  printf '\nstart-at-login = false\n' >> "$TEST_HOME/.config/aerospace/local.toml"
  # A running AeroSpace, so the backstop would otherwise stage through it.
  mock_command_script aerospace <<'EOF2'
case "$1" in
  list-monitors) echo "monitor 1"; exit 0 ;;
  reload-config) exit 0 ;;
  *) exit 0 ;;
esac
EOF2
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null 2>&1 || true
  [[ -L "$AERO" ]] || { echo "the symlink was replaced by a regular file"; return 1; }
  assert_equals "$store" "$(readlink "$AERO")" "the link must still point where it did" || return 1
  assert_contains "$(cat "$store")" "managed elsewhere" "the link target must be untouched" || return 1
  cleanup_test_env
}

test_backstop_skips_when_aerospace_is_not_running() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null 2>&1
  local local_toml="$TEST_HOME/.config/aerospace/local.toml"
  printf '\nstart-at-login = false\n' >> "$local_toml"
  # An installed AeroSpace whose server is not up: every command that needs
  # it fails, reload-config included.
  mock_command_script aerospace <<'EOF2'
case "$1" in
  list-monitors) echo "aerospace: Can not establish connection with AeroSpace server" >&2; exit 1 ;;
  reload-config) echo "aerospace: Can not establish connection with AeroSpace server" >&2; exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace 2>&1)" || rc=$?
  assert_success "$rc" "an AeroSpace that is not running is not a rejected config" || return 1
  assert_contains "$(cat "$AERO")" "start-at-login = false" "the merged config must still be installed" || return 1
  assert_contains "$out" "not running yet" || return 1
  # And it must not claim the config was checked.
  assert_not_contains "$(cat "$MOCK_LOG")" "aerospace reload-config" "there is nobody to ask, so it must not ask" || return 1
  cleanup_test_env
}

test_backstop_installs_normally_when_aerospace_accepts_it() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null 2>&1
  local local_toml="$TEST_HOME/.config/aerospace/local.toml"
  printf '\nstart-at-login = false\n' >> "$local_toml"
  mock_command_script aerospace <<'EOF2'
case "$1" in
  reload-config) exit 0 ;;
  *) exit 0 ;;
esac
EOF2
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace 2>&1)" || rc=$?
  assert_success "$rc" "a config AeroSpace accepts must configure normally" || return 1
  assert_contains "$(cat "$AERO")" "start-at-login = false" "the merge AeroSpace accepted must actually be installed" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "aerospace reload-config" "must actually have asked AeroSpace" || return 1
  cleanup_test_env
}

# No `aerospace` binary at all (a fresh Mac before the cask lands, a
# MacPorts machine, this Linux test box) has to skip the check, not fail it
# -- every other test in this suite relies on exactly that -- and skipping
# must not be reported as if AeroSpace had actually looked at the config.
test_backstop_skips_without_claiming_success_when_there_is_no_aerospace_binary() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null 2>&1
  local local_toml="$TEST_HOME/.config/aerospace/local.toml"
  printf '\nstart-at-login = false\n' >> "$local_toml"
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace 2>&1)" || rc=$?
  assert_success "$rc" "no aerospace binary must not block the install" || return 1
  assert_contains "$(cat "$AERO")" "start-at-login = false" "no aerospace binary must not block the install" || return 1
  assert_not_contains "$out" "AeroSpace said" "skipping validation must not be reported as having validated" || return 1
  cleanup_test_env
}

run_test "install taps then installs the cask" test_install_taps_then_installs_the_cask
run_test "install skips the tap when present" test_install_skips_the_tap_when_present
run_test "install is skipped on macports" test_install_is_skipped_on_macports
run_test "install skips below the macOS minimum" test_install_skips_below_the_macos_minimum
run_test "install skips below the macOS minimum in dry run too" test_install_skips_below_the_macos_minimum_in_dry_run_too
run_test "install below the macOS minimum leaves no done marker" test_install_below_the_macos_minimum_leaves_no_done_marker
run_test "install at the macOS minimum marks done as before" test_install_at_the_macos_minimum_marks_done_as_before
run_test "install runs as usual at the macOS minimum" test_install_runs_as_usual_at_the_macos_minimum
run_test "configure copies the config and prints the manual step" test_configure_copies_the_config_and_prints_the_manual_step
run_test "configure fails when the generated config cannot be written" test_configure_fails_when_the_generated_config_cannot_be_written
run_test "backstop leaves the config untouched when AeroSpace rejects it" test_backstop_leaves_the_config_untouched_when_aerospace_rejects_it
run_test "backstop never writes through a symlinked config" test_backstop_never_writes_through_a_symlinked_config
run_test "backstop skips when aerospace is not running" test_backstop_skips_when_aerospace_is_not_running
run_test "backstop installs normally when AeroSpace accepts it" test_backstop_installs_normally_when_aerospace_accepts_it
run_test "backstop skips without claiming success when there is no aerospace binary" test_backstop_skips_without_claiming_success_when_there_is_no_aerospace_binary
run_test "reset leaves the local override alone" test_reset_leaves_the_local_override_alone
run_test "configure writes the tuned defaults" test_configure_writes_the_tuned_defaults
run_test "shipped defaults do not force a monitor layout" test_shipped_defaults_do_not_force_a_monitor_layout
run_test "configure installs local.toml" test_configure_installs_local_toml
run_test "local.toml overrides a key and replaces a table" test_local_toml_overrides_a_key_and_replaces_a_table
run_test "local.toml monitor assignment lands in the generated file" test_local_toml_monitor_assignment_lands_in_the_generated_file
run_test "configure with no local overrides gets the base unchanged" test_configure_with_no_local_overrides_gets_the_base_unchanged
run_test "hand-edited aerospace.toml is not regenerated" test_hand_edited_aerospace_toml_is_not_regenerated
run_test "configure dry run writes nothing even with local overrides" test_configure_dry_run_writes_nothing_even_with_local_overrides
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
