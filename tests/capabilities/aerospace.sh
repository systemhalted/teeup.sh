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
# it live would force a three-monitor layout onto every machine, including a
# single-monitor one. It ships commented out, so the owner of a machine that
# wants it uncomments it in place.
test_shipped_defaults_do_not_force_a_monitor_layout() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null
  # A real [table] header at the start of a line, not teeup's own commented
  # example, which the file does carry.
  assert_not_contains "$(cat "$AERO")" "
[workspace-to-monitor-force-assignment]
" "monitor layout must not be live in the shipped defaults" || return 1
  assert_contains "$(cat "$AERO")" "# [workspace-to-monitor-force-assignment]" "the commented example is what a machine uncomments" || return 1
  cleanup_test_env
}

# The installed file is teeup's shipped file, byte for byte: there is nothing
# generated or merged any more.
test_configure_installs_the_shipped_file_unchanged() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null
  assert_equals "$(cat "$TEEUP_PATH/capabilities/aerospace/config/aerospace/aerospace.toml")" "$(cat "$AERO")" || return 1
  cleanup_test_env
}

# aerospace.toml is the owner's file once it is installed. This is the whole
# safety model now that there is no merge: an edited file is never replaced,
# and the run says so and names the way to take teeup's new version.
test_hand_edited_aerospace_toml_is_not_replaced() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null
  printf '\n# my own tweak, not from teeup\n' >> "$AERO"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace)"
  assert_contains "$out" "$AERO" || return 1
  local content
  content="$(cat "$AERO")"
  assert_contains "$content" "# my own tweak, not from teeup" "the hand edit must survive a re-configure" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null
  printf '\n# my own tweak\n' >> "$AERO"
  local before_aero
  before_aero="$(cat "$AERO")"
  DRY_RUN=true "$TEEUP" configure aerospace >/dev/null
  assert_equals "$before_aero" "$(cat "$AERO")" "a dry run must not touch aerospace.toml" || return 1
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


# The backstop: where AeroSpace itself is available to ask
# (`aerospace reload-config --dry-run`), it gets the last word before anything
# is installed, so a config it rejects never reaches
# ~/.config/aerospace/aerospace.toml and AeroSpace is never left silently
# loading nothing. The file being checked is teeup's own now that there is no
# merge, so a rejection means teeup's shipped config is broken -- still worth
# refusing to install rather than discovering it on the machine.
test_backstop_leaves_the_config_untouched_when_aerospace_rejects_it() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null 2>&1
  local before
  before="$(cat "$AERO")"
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
  assert_contains "$out" "$AERO" "the message must name the config that was not changed" || return 1
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
  # A fresh install is what the backstop guards, so clear the installed file.
  rm -f "$AERO"
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
  assert_contains "$(cat "$AERO")" "persistent-workspaces" "the config must still be installed" || return 1
  assert_contains "$out" "not running yet" || return 1
  # And it must not claim the config was checked.
  assert_not_contains "$(cat "$MOCK_LOG")" "aerospace reload-config" "there is nobody to ask, so it must not ask" || return 1
  cleanup_test_env
}

# The commonest case of all, and the one the backstop was defeated in: a
# genuinely fresh machine where ~/.config/aerospace does not exist yet. The
# staging mktemp lands in that directory, so it failed, the function warned
# and returned 0 -- a skip reported as success -- and copy_config_once then
# created the directory and installed the config without AeroSpace ever
# being asked. The backstop existed and did nothing exactly where it was
# needed most.
# The upgrade path. copy_config_once sees a checksum recorded for the
# already-installed file and says "Already installed", even when that pristine
# file is the PREVIOUS shipped version -- so a machine that installed aerospace
# before this change would never receive any of the new defaults. Copy-once is
# the right model (wezterm and starship use it), but it only half works
# without a migration: the shipped migration is what calls migration_refresh,
# which replaces the copies nobody edited and leaves edited ones alone.
test_the_shipped_migration_refreshes_a_pristine_config() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null 2>&1
  state_done mark cap-aerospace
  # A machine that installed aerospace before this change: an older shipped
  # file whose stock record matches it, so it reads as pristine.
  printf 'config-version = 2\n# the previous shipped file\n' > "$AERO"
  stock_record "$AERO" "$(file_sha "$AERO")"
  local mig
  mig="$(cd "$TEEUP_PATH" && ls migrations/*.sh 2>/dev/null | head -1)"
  mig="$(basename "${mig:-none}")"
  [[ "$mig" != "none" ]] || { echo "fixture: no migration is shipped"; return 1; }
  DRY_RUN=false migration_run "$mig" >/dev/null 2>&1 || { echo "the migration failed"; return 1; }
  assert_contains "$(cat "$AERO")" "persistent-workspaces" "a pristine copy must be refreshed to the new shipped version" || return 1
  # And an edited copy is left exactly as it is: that is the stock-checksum
  # rule, and the reason the owner can edit this file at all.
  printf '# mine, do not touch\n' > "$AERO"
  rm -f "$TEEUP_STATE_DIR/migrations/$mig"
  DRY_RUN=false migration_run "$mig" >/dev/null 2>&1 || true
  assert_equals '# mine, do not touch' "$(cat "$AERO")" "an edited config must survive the migration" || return 1
  cleanup_test_env
}

# The staging swap puts the candidate at $dest to ask AeroSpace about it and
# then puts the original back. If that restore fails, the candidate is left
# sitting at $dest -- and the function warned and returned SUCCESS, so
# configure carried on. copy_config_once then compares that candidate against
# the stock record, sees a hash it does not recognise, concludes the user
# edited the file, and leaves it exactly where it is. The user's real config
# stays stranded in a .teeup_validate_old.XXXXXX beside it and configure
# reports success. A failed restore has to stop the capability.
test_backstop_fails_when_the_original_cannot_be_restored() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null 2>&1
  printf '# my own config\n' > "$AERO"
  local before
  before="$(cat "$AERO")"
  # A running AeroSpace that accepts the candidate, so the only thing that
  # can go wrong is the restore.
  mock_command_script aerospace <<'EOF2'
case "$1" in
  list-monitors) echo "monitor 1"; exit 0 ;;
  reload-config) exit 0 ;;
  *) exit 0 ;;
esac
EOF2
  # Make the restore fail, and only the restore. The staging step names the
  # same .teeup_validate_old. path as its DESTINATION (cp -p $dest $saved),
  # so matching anywhere in the arguments breaks staging instead and the
  # check is skipped entirely -- a different path that proves nothing. The
  # restore is the direction where that path is the SOURCE.
  mock_command_script mv <<'EOF2'
src="$1"
case "$src" in
  -*) src="$2" ;;
esac
case "$src" in
  *.teeup_validate_old.*) exit 1 ;;
esac
exec /bin/mv "$@"
EOF2
  mock_command_script cp <<'EOF2'
src="$1"
case "$src" in
  -*) src="$2" ;;
esac
case "$src" in
  *.teeup_validate_old.*) exit 1 ;;
esac
exec /bin/cp "$@"
EOF2
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace 2>&1)" || rc=$?
  assert_failure "$rc" "a config teeup could not put back is not a configured capability" || return 1
  assert_contains "$out" "restore" || return 1
  # And the candidate must not have been quietly adopted as the user's file.
  assert_not_contains "$out" "Already installed" || return 1
  cleanup_test_env
}

test_backstop_validates_on_a_fresh_machine_with_no_config_dir() {
  setup
  local cfg_dir
  cfg_dir="$(dirname "$AERO")"
  rm -rf "$cfg_dir"
  [[ ! -d "$cfg_dir" ]] || { echo "fixture: the config dir must not exist"; return 1; }
  mock_command_script aerospace <<'EOF2'
case "$1" in
  list-monitors) echo "monitor 1"; exit 0 ;;
  reload-config) exit 0 ;;
  *) exit 0 ;;
esac
EOF2
  local rc=0
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null 2>&1 || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "aerospace reload-config" "AeroSpace must be asked on a fresh machine, not skipped" || return 1
  assert_file_exists "$AERO" || return 1
  cleanup_test_env
}

# And the rejection has to bite there too: on a fresh machine a config
# AeroSpace refuses must leave nothing behind.
test_backstop_installs_nothing_on_a_fresh_machine_when_aerospace_rejects_it() {
  setup
  local cfg_dir
  cfg_dir="$(dirname "$AERO")"
  rm -rf "$cfg_dir"
  mock_command_script aerospace <<'EOF2'
case "$1" in
  list-monitors) echo "monitor 1"; exit 0 ;;
  reload-config) echo "aerospace: config error: unexpected key on line 12" >&2; exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace 2>&1)" || rc=$?
  assert_failure "$rc" "a config AeroSpace rejects must fail the capability" || return 1
  [[ ! -e "$AERO" ]] || { echo "a rejected config was installed anyway"; return 1; }
  assert_contains "$out" "unexpected key on line 12" || return 1
  cleanup_test_env
}

test_backstop_installs_normally_when_aerospace_accepts_it() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null 2>&1
  rm -f "$AERO"
  mock_command_script aerospace <<'EOF2'
case "$1" in
  reload-config) exit 0 ;;
  *) exit 0 ;;
esac
EOF2
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace 2>&1)" || rc=$?
  assert_success "$rc" "a config AeroSpace accepts must configure normally" || return 1
  assert_contains "$(cat "$AERO")" "persistent-workspaces" "the config AeroSpace accepted must actually be installed" || return 1
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
  rm -f "$AERO"
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace 2>&1)" || rc=$?
  assert_success "$rc" "no aerospace binary must not block the install" || return 1
  assert_contains "$(cat "$AERO")" "persistent-workspaces" "no aerospace binary must not block the install" || return 1
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
run_test "backstop leaves the config untouched when AeroSpace rejects it" test_backstop_leaves_the_config_untouched_when_aerospace_rejects_it
run_test "backstop never writes through a symlinked config" test_backstop_never_writes_through_a_symlinked_config
run_test "backstop skips when aerospace is not running" test_backstop_skips_when_aerospace_is_not_running
run_test "the shipped migration refreshes a pristine config" test_the_shipped_migration_refreshes_a_pristine_config
run_test "backstop fails when the original cannot be restored" test_backstop_fails_when_the_original_cannot_be_restored
run_test "backstop validates on a fresh machine with no config dir" test_backstop_validates_on_a_fresh_machine_with_no_config_dir
run_test "backstop installs nothing on a fresh machine when AeroSpace rejects it" test_backstop_installs_nothing_on_a_fresh_machine_when_aerospace_rejects_it
run_test "backstop installs normally when AeroSpace accepts it" test_backstop_installs_normally_when_aerospace_accepts_it
run_test "backstop skips without claiming success when there is no aerospace binary" test_backstop_skips_without_claiming_success_when_there_is_no_aerospace_binary
run_test "configure writes the tuned defaults" test_configure_writes_the_tuned_defaults
run_test "shipped defaults do not force a monitor layout" test_shipped_defaults_do_not_force_a_monitor_layout
run_test "configure installs the shipped file unchanged" test_configure_installs_the_shipped_file_unchanged
run_test "hand-edited aerospace.toml is not replaced" test_hand_edited_aerospace_toml_is_not_replaced
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
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
