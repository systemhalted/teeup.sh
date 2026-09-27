#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# The real osascript and node are found before setup_test_env narrows PATH.
# osascript exists only on a Mac, and the one test that runs the JXA program
# itself points it at a plist under $TEST_HOME, never at com.apple.Terminal.
# node is only a parser here: it proves profile.js is valid JavaScript on a
# machine that cannot run it.
TERMINAL_REAL_OSASCRIPT="$(command -v osascript || true)"
TERMINAL_REAL_PLUTIL="$(command -v plutil || true)"
TERMINAL_NODE="$(command -v node || command -v nodejs || true)"

PROFILE_JS="$TEEUP_PATH/capabilities/terminal-app/profile.js"

setup() {
  setup_test_env
  mock_macos_base
  mock_defaults_db
  mock_osascript
  TEEUP="$TEEUP_PATH/bin/teeup"
  STATE="$TEST_HOME/.local/state/teeup"
  RECORDS="$STATE/defaults"
}

# A stateful defaults database, as in tests/capabilities/macos-defaults.sh.
# Each "<domain>.<key>" file holds the type on its first line and the value
# after it; key names may contain spaces ("Default Window Settings").
# `defaults read -g AppleInterfaceStyle` reads the file "-g.AppleInterfaceStyle".
mock_defaults_db() {
  export DDB="$TEST_HOME/defaults-db"
  mkdir -p "$DDB"
  mock_command_script defaults <<'EOF2'
op="$1"; shift
f="$DDB/$1.$2"
case "$op" in
  read) [ -f "$f" ] || exit 1; tail -n +2 "$f" ;;
  read-type) [ -f "$f" ] || exit 1; echo "Type is $(head -1 "$f")" ;;
  write)
    [ "$2" = "${DEFAULTS_FAIL_WRITE:-}" ] && exit 1
    case "$3" in
      -string) t=string ;;
      *) exit 1 ;;
    esac
    printf '%s\n%s\n' "$t" "$4" > "$f"
    ;;
  delete) [ -f "$f" ] || exit 1; rm -f "$f" ;;
esac
EOF2
}

# seed_default <domain> <key> <type> <value>
seed_default() { printf '%s\n%s\n' "$3" "$4" > "$DDB/$1.$2"; }

# default_value <key> -> the com.apple.Terminal value, or "<absent>".
default_value() {
  if [[ -f "$DDB/com.apple.Terminal.$1" ]]; then tail -n +2 "$DDB/com.apple.Terminal.$1"; else echo "<absent>"; fi
}

set_appearance() {
  if [[ "$1" == "dark" ]]; then
    seed_default -g AppleInterfaceStyle string Dark
  else
    rm -f "$DDB/-g.AppleInterfaceStyle"
  fi
}

# The osascript stand-in. Every call is one line in $MOCK_LOG; an `apply`
# also leaves its arguments one per line in $OSA_APPLY, so a profile name and
# each Key=#hex pair can be checked exactly. `has <name>` answers from
# $TERMINAL_PROFILES, one profile name per line.
mock_osascript() {
  export OSA_APPLY="$TEST_HOME/osascript-apply"
  export TERMINAL_PROFILES="$TEST_HOME/terminal-profiles"
  : > "$TERMINAL_PROFILES"
  mock_command_script osascript <<'EOF2'
case "${4:-}" in
  apply) shift 4; printf '%s\n' "$@" > "$OSA_APPLY" ;;
  has) if grep -qxF "$5" "$TERMINAL_PROFILES"; then echo present; else echo absent; fi ;;
esac
exit 0
EOF2
}

mark_installed() {
  mkdir -p "$STATE/done"
  : > "$STATE/done/cap-terminal-app"
}

# palette_value <file> <key>: the value exactly as theme_palette_load reads it.
palette_value() {
  sed -n "s/^$2[[:space:]]*=[[:space:]]*\"\(.*\)\".*\$/\1/p" "$1"
}

# The Terminal key each palette role lands in: the same roles WezTerm's
# colour scheme uses (capabilities/wezterm/themed/wezterm.lua.tpl), written
# out here independently of the template so a changed template fails.
TERMINAL_MAP="BackgroundColor=background
TextColor=foreground
TextBoldColor=bright_foreground
CursorColor=bright_foreground
SelectionColor=selection
ANSIBlackColor=dark_background
ANSIRedColor=red
ANSIGreenColor=green
ANSIYellowColor=yellow
ANSIBlueColor=blue
ANSIMagentaColor=magenta
ANSICyanColor=cyan
ANSIWhiteColor=foreground
ANSIBrightBlackColor=muted
ANSIBrightRedColor=bright_red
ANSIBrightGreenColor=bright_green
ANSIBrightYellowColor=bright_yellow
ANSIBrightBlueColor=bright_blue
ANSIBrightMagentaColor=bright_magenta
ANSIBrightCyanColor=bright_cyan
ANSIBrightWhiteColor=bright_foreground"

# check_apply <theme> <mode> <profile name>
check_apply() {
  local theme="$1" mode="$2" profile="$3" palette line key role want pairs
  palette="$TEEUP_PATH/themes/$theme/$mode.toml"
  assert_file_exists "$OSA_APPLY" "$theme $mode reached osascript" || return 1
  assert_equals "$profile" "$(sed -n 1p "$OSA_APPLY")" "$theme $mode profile name" || return 1
  pairs="$(tail -n +5 "$OSA_APPLY")"
  assert_equals 21 "$(printf '%s\n' "$pairs" | grep -c '=')" "$theme $mode hands over 21 colours" || return 1
  while IFS= read -r line; do
    key="${line%%=*}"
    role="${line#*=}"
    want="$(palette_value "$palette" "$role")"
    [[ -n "$want" ]] || { echo "themes/$theme/$mode.toml has no $role"; return 1; }
    printf '%s\n' "$pairs" | grep -qxF "$key=$want" ||
      { echo "$theme $mode: expected $key=$want ($role), got: $(printf '%s\n' "$pairs" | grep "^$key=" || echo nothing)"; return 1; }
  done <<EOF_MAP
$TERMINAL_MAP
EOF_MAP
}

# display_name <theme> -> "Tokyo Night" for tokyo-night.
display_name() {
  local word out=""
  for word in $(printf '%s' "$1" | tr '-' ' '); do
    out="${out:+$out }$(printf '%s' "${word:0:1}" | tr '[:lower:]' '[:upper:]')${word:1}"
  done
  printf '%s\n' "$out"
}

test_metadata_passes_the_capability_check() {
  setup
  local out rc=0
  out="$("$TEEUP" commands --check 2>&1)" || rc=$?
  assert_equals 0 "$rc" "teeup commands --check exits 0" || { echo "$out"; return 1; }
  assert_equals "" "$out" "teeup commands --check is silent" || return 1
  grep -qx 'tier=core' "$TEEUP_PATH/capabilities/terminal-app/capability" || { echo "terminal-app must be core"; return 1; }
  grep -qx 'terminal-app' "$TEEUP_PATH/capabilities/core.list" || { echo "terminal-app is not in core.list"; return 1; }
  cleanup_test_env
}

test_every_palette_and_mode_reaches_the_script() {
  setup
  mark_installed
  local dir theme count=0
  for dir in "$TEEUP_PATH"/themes/*/; do
    theme="$(basename "$dir")"
    [[ -f "$dir/dark.toml" && -f "$dir/light.toml" ]] || continue
    set_appearance dark
    rm -f "$OSA_APPLY"
    DRY_RUN=false "$TEEUP" theme set "$theme" >/dev/null 2>&1 || { echo "theme set $theme failed"; return 1; }
    check_apply "$theme" dark "teeup $(display_name "$theme") Dark" || return 1
    set_appearance light
    rm -f "$OSA_APPLY"
    DRY_RUN=false "$TEEUP" configure terminal-app >/dev/null 2>&1 || { echo "configure under $theme light failed"; return 1; }
    check_apply "$theme" light "teeup $(display_name "$theme") Light" || return 1
    count=$((count + 1))
  done
  [[ "$count" -ge 4 ]] || { echo "only $count themes were checked"; return 1; }
  cleanup_test_env
}

test_the_script_is_the_shipped_program() {
  setup
  set_appearance dark
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" configure terminal-app >/dev/null 2>&1
  assert_contains "$(cat "$MOCK_LOG")" "osascript -l JavaScript $PROFILE_JS apply teeup Catppuccin Dark" || return 1
  cleanup_test_env
}

test_default_and_startup_settings_are_written_and_recorded() {
  setup
  set_appearance dark
  seed_default com.apple.Terminal "Default Window Settings" string Pro
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure terminal-app 2>&1)"
  assert_equals "teeup Catppuccin Dark" "$(default_value "Default Window Settings")" || return 1
  assert_equals "teeup Catppuccin Dark" "$(default_value "Startup Window Settings")" || return 1
  assert_equals "-string:Pro" "$(cat "$RECORDS/com.apple.Terminal.Default Window Settings")" || return 1
  assert_equals "absent" "$(cat "$RECORDS/com.apple.Terminal.Startup Window Settings")" || return 1
  assert_contains "$out" "windows already open keep their colours" || return 1
  cleanup_test_env
}

test_the_profile_is_written_before_it_becomes_the_default() {
  setup
  set_appearance dark
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" configure terminal-app >/dev/null 2>&1
  local apply_line default_line
  apply_line="$(grep -n 'osascript .* apply ' "$MOCK_LOG" | head -1 | cut -d: -f1)"
  default_line="$(grep -n 'defaults write com.apple.Terminal Default Window Settings' "$MOCK_LOG" | head -1 | cut -d: -f1)"
  [[ -n "$apply_line" && -n "$default_line" && "$apply_line" -lt "$default_line" ]] ||
    { echo "osascript apply (line $apply_line) must come before the default (line $default_line)"; return 1; }
  cleanup_test_env
}

test_a_failed_profile_write_leaves_the_defaults_alone() {
  setup
  set_appearance dark
  seed_default com.apple.Terminal "Default Window Settings" string Pro
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  mock_command osascript 1 ""
  DRY_RUN=false "$TEEUP" configure terminal-app >/dev/null 2>&1 || true
  assert_equals "Pro" "$(default_value "Default Window Settings")" "the default still names the user's profile" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "defaults write com.apple.Terminal" || return 1
  cleanup_test_env
}

test_a_failed_default_write_is_reported() {
  setup
  set_appearance dark
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  local out
  out="$(DEFAULTS_FAIL_WRITE="Default Window Settings" DRY_RUN=false "$TEEUP" configure terminal-app 2>&1)" || true
  assert_contains "$out" "Could not set Terminal.app's Default Window Settings to teeup Catppuccin Dark" || return 1
  assert_not_contains "$out" "new windows use" "no success claimed" || return 1
  cleanup_test_env
}

test_only_teeup_profiles_are_named() {
  setup
  set_appearance dark
  printf 'Pro\nteeup Catppuccin Dark\n' > "$TERMINAL_PROFILES"
  seed_default com.apple.Terminal "Default Window Settings" string Pro
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" configure terminal-app >/dev/null 2>&1
  mark_installed
  DRY_RUN=false "$TEEUP" remove terminal-app >/dev/null 2>&1
  local line
  # Every call that writes names a teeup profile or none at all: `apply`
  # takes the name as its first argument, and `remove` takes no name, since
  # the program itself deletes only names that start with "teeup ".
  while IFS= read -r line; do
    case "$line" in
      *" apply teeup "*|*" remove"|*" has "*) ;;
      *) echo "unexpected osascript call: $line"; return 1 ;;
    esac
  done < <(grep '^osascript ' "$MOCK_LOG")
  grep -q '^osascript .* remove$' "$MOCK_LOG" || { echo "remove never asked osascript to delete teeup's profiles"; return 1; }
  cleanup_test_env
}

test_remove_restores_the_previous_defaults() {
  setup
  set_appearance dark
  printf 'Pro\n' > "$TERMINAL_PROFILES"
  seed_default com.apple.Terminal "Default Window Settings" string Pro
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" configure terminal-app >/dev/null 2>&1
  mark_installed
  local out
  out="$(DRY_RUN=false "$TEEUP" remove terminal-app 2>&1)" || { echo "$out"; return 1; }
  assert_equals "Pro" "$(default_value "Default Window Settings")" || return 1
  assert_equals "<absent>" "$(default_value "Startup Window Settings")" "a key teeup added is deleted again" || return 1
  [[ ! -e "$RECORDS/com.apple.Terminal.Default Window Settings" ]] || { echo "record kept"; return 1; }
  [[ ! -e "$STATE/done/cap-terminal-app" ]] || { echo "still marked installed"; return 1; }
  [[ ! -e "$STATE/terminal-app" ]] || { echo "the saved .terminal copies were left behind"; return 1; }
  cleanup_test_env
}

test_remove_falls_back_to_basic_when_the_old_profile_is_gone() {
  setup
  set_appearance dark
  seed_default com.apple.Terminal "Default Window Settings" string "Gone Profile"
  seed_default com.apple.Terminal "Startup Window Settings" string "Gone Profile"
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" configure terminal-app >/dev/null 2>&1
  mark_installed
  local out
  out="$(DRY_RUN=false "$TEEUP" remove terminal-app 2>&1)" || { echo "$out"; return 1; }
  assert_equals "Basic" "$(default_value "Default Window Settings")" || return 1
  assert_equals "Basic" "$(default_value "Startup Window Settings")" || return 1
  assert_contains "$out" "Gone Profile" "says which profile is gone" || return 1
  [[ ! -e "$RECORDS/com.apple.Terminal.Default Window Settings" ]] || { echo "record kept"; return 1; }
  cleanup_test_env
}

test_remove_keeps_a_recorded_profile_it_cannot_check() {
  setup
  set_appearance dark
  seed_default com.apple.Terminal "Default Window Settings" string Pro
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" configure terminal-app >/dev/null 2>&1
  mark_installed
  # osascript answers nothing at all, so whether Pro exists is unknown: the
  # user's own choice is put back rather than replaced by Basic.
  mock_command osascript 0 ""
  DRY_RUN=false "$TEEUP" remove terminal-app >/dev/null 2>&1
  assert_equals "Pro" "$(default_value "Default Window Settings")" || return 1
  cleanup_test_env
}

test_a_failed_profile_delete_keeps_it_installed() {
  setup
  set_appearance dark
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" configure terminal-app >/dev/null 2>&1
  mark_installed
  mock_command osascript 1 ""
  local rc=0
  DRY_RUN=false "$TEEUP" remove terminal-app >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "remove reports the failure" || return 1
  assert_file_exists "$STATE/done/cap-terminal-app" "still marked installed, so remove can be run again" || return 1
  cleanup_test_env
}

# find_terminal_app_migration -> the basename of the shipped migration that
# installs terminal-app on an existing machine (final review I4), found by
# content rather than position: migrations/ already ships others, and a
# later one could sort before or after this one.
find_terminal_app_migration() {
  local mig
  mig="$(grep -l 'cap_install_verbs terminal-app' "$TEEUP_PATH"/migrations/*.sh 2>/dev/null | head -1)"
  [[ -n "$mig" ]] && basename "$mig"
}

# I4 (the owner's decision): terminal-app became core on this branch, but
# `teeup update` only re-configures a capability already marked installed
# (bin/teeup's _update_configure_tier); it never installs one core gained
# since a machine's last bootstrap. The shipped migration is the only thing
# that reaches an existing Mac that pulled this branch before its next
# fresh bootstrap.
test_the_shipped_migration_installs_terminal_app_on_an_existing_machine() {
  setup
  set_appearance dark
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  source "$TEEUP_PATH/lib/all.sh"
  state_done mark cap-theme
  local mig
  mig="$(find_terminal_app_migration)"
  [[ -n "$mig" ]] || { echo "fixture: no shipped migration installs terminal-app"; return 1; }
  [[ ! -e "$STATE/done/cap-terminal-app" ]] || { echo "fixture: terminal-app must start uninstalled"; return 1; }
  DRY_RUN=false migration_run "$mig" >/dev/null 2>&1 || { echo "the migration failed"; return 1; }
  assert_file_exists "$STATE/done/cap-terminal-app" "the migration must install terminal-app" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "osascript -l JavaScript $PROFILE_JS apply" \
    "the migration must actually theme Terminal.app (cap_install_verbs), not just mark it installed" || return 1
  assert_file_exists "$STATE/migrations/$mig" "the migration itself must be marked applied" || return 1
  cleanup_test_env
}

# TEEUP_SKIP must be honoured the same way `teeup install terminal-app` would
# honour it: nothing installed, and the migration still finishes.
test_the_shipped_migration_leaves_a_skipped_terminal_app_alone() {
  setup
  set_appearance dark
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  source "$TEEUP_PATH/lib/all.sh"
  state_done mark cap-theme
  local mig rc=0
  mig="$(find_terminal_app_migration)"
  [[ -n "$mig" ]] || { echo "fixture: no shipped migration installs terminal-app"; return 1; }
  TEEUP_SKIP=terminal-app DRY_RUN=false migration_run "$mig" >/dev/null 2>&1 || rc=$?
  assert_success "$rc" "a skipped capability must not fail the migration" || return 1
  [[ ! -e "$STATE/done/cap-terminal-app" ]] || { echo "a skipped capability must not be installed"; return 1; }
  cleanup_test_env
}

# A fresh ./bootstrap installs terminal-app as part of core in the same run;
# migrations_mark_all (lib/migrations.sh) is what marks every shipped
# migration applied without running it, so this one must not run a second
# time and reach cap_install_verbs there.
test_a_fresh_bootstrap_marks_the_shipped_migration_without_running_it() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  local mig
  mig="$(find_terminal_app_migration)"
  [[ -n "$mig" ]] || { echo "fixture: no shipped migration installs terminal-app"; return 1; }
  migrations_mark_all
  assert_file_exists "$STATE/migrations/$mig" "a fresh bootstrap must mark every shipped migration applied" || return 1
  [[ ! -e "$STATE/done/cap-terminal-app" ]] || { echo "marking a migration applied must not itself install anything"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "osascript" "marking a migration applied must not run its script" || return 1
  cleanup_test_env
}

# Final review I5 ("check that terminal-app's remove runs during uninstall's
# capability loop, before the state teardown"): `teeup uninstall` on a
# machine with terminal-app installed must reach this capability's own
# remove script -- which restores Terminal's previous defaults and deletes
# teeup's profiles through osascript -- rather than leaving that to
# _UNINSTALL_STATE_ENTRIES, which only ever deletes a directory.
test_uninstall_runs_terminal_apps_remove_before_the_state_teardown() {
  setup
  hide_host_commands chezmoi
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR"
  set_appearance dark
  printf 'Pro\n' > "$TERMINAL_PROFILES"
  seed_default com.apple.Terminal "Default Window Settings" string Pro
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" configure terminal-app >/dev/null 2>&1
  mark_installed
  [[ -d "$STATE/terminal-app" ]] || { echo "the exported .terminal directory must exist before uninstall"; return 1; }
  local out rc=0
  out="$(TEEUP_TEST_TTY=no "$TEEUP" uninstall --yes 2>&1)" || rc=$?
  assert_success "$rc" "$out" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "osascript -l JavaScript $PROFILE_JS remove" \
    "the capability's own remove script must run, not just a directory wipe" || return 1
  assert_equals "Pro" "$(default_value "Default Window Settings")" "remove's own restore must have run" || return 1
  [[ ! -e "$STATE" ]] || { echo "the whole state dir must be gone once every entry, including terminal-app, is teeup's own"; return 1; }
  cleanup_test_env
}

test_dry_run_configure_changes_nothing() {
  setup
  set_appearance dark
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  : > "$MOCK_LOG"
  local before out
  before="$(ls -R "$DDB" "$STATE")"
  out="$(DRY_RUN=true "$TEEUP" configure terminal-app 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: osascript -l JavaScript $PROFILE_JS apply teeup Catppuccin Dark" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: defaults write com.apple.Terminal Default Window Settings -string teeup Catppuccin Dark" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: defaults write com.apple.Terminal Startup Window Settings -string teeup Catppuccin Dark" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "osascript" "a dry run never runs the program" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "defaults write" || return 1
  assert_equals "$before" "$(ls -R "$DDB" "$STATE")" "nothing written" || return 1
  cleanup_test_env
}

test_dry_run_remove_changes_nothing() {
  setup
  set_appearance dark
  seed_default com.apple.Terminal "Default Window Settings" string "Gone Profile"
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" configure terminal-app >/dev/null 2>&1
  mark_installed
  : > "$MOCK_LOG"
  local before out
  before="$(ls -R "$DDB" "$STATE"; cat "$DDB"/*)"
  out="$(DRY_RUN=true "$TEEUP" remove terminal-app 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: osascript -l JavaScript $PROFILE_JS remove" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: defaults write com.apple.Terminal Default Window Settings -string Basic" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: defaults delete com.apple.Terminal Startup Window Settings" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "apply" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" " remove" "a dry run deletes no profile" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "defaults write" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "defaults delete" || return 1
  assert_equals "$before" "$(ls -R "$DDB" "$STATE"; cat "$DDB"/*)" "nothing written" || return 1
  cleanup_test_env
}

test_the_recorded_font_is_handed_over() {
  setup
  set_appearance dark
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  mkdir -p "$STATE/current"
  printf 'FiraCode Nerd Font\n' > "$STATE/current/font"
  DRY_RUN=false "$TEEUP" configure terminal-app >/dev/null 2>&1
  assert_equals "FiraCode Nerd Font" "$(sed -n 2p "$OSA_APPLY")" || return 1
  assert_equals "13" "$(sed -n 3p "$OSA_APPLY")" "the default size" || return 1
  cleanup_test_env
}

test_no_recorded_font_leaves_the_font_alone() {
  setup
  set_appearance dark
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" configure terminal-app >/dev/null 2>&1
  assert_equals "" "$(sed -n 2p "$OSA_APPLY")" "an empty font name means: keep Terminal's font" || return 1
  cleanup_test_env
}

test_a_machine_can_pick_the_font_size() {
  setup
  set_appearance dark
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  TEEUP_TERMINAL_FONT_SIZE=15 DRY_RUN=false "$TEEUP" configure terminal-app >/dev/null 2>&1
  assert_equals "15" "$(sed -n 3p "$OSA_APPLY")" || return 1
  rm -f "$OSA_APPLY"
  local out
  out="$(TEEUP_TERMINAL_FONT_SIZE='1; rm' DRY_RUN=false "$TEEUP" configure terminal-app 2>&1)" || true
  assert_equals "13" "$(sed -n 3p "$OSA_APPLY")" "a size that is not a number falls back" || return 1
  assert_contains "$out" "TEEUP_TERMINAL_FONT_SIZE" || return 1
  cleanup_test_env
}

test_a_font_change_rebuilds_the_profile() {
  setup
  set_appearance dark
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  mark_installed
  mock_command brew 0 ""
  DRY_RUN=false "$TEEUP" install font hack >/dev/null 2>&1 || true
  assert_file_exists "$OSA_APPLY" "font-apply rebuilt the profile" || return 1
  assert_equals "Hack Nerd Font" "$(sed -n 2p "$OSA_APPLY")" || return 1
  cleanup_test_env
}

test_the_hook_waits_until_the_capability_is_installed() {
  setup
  set_appearance dark
  DRY_RUN=false "$TEEUP" theme set tokyo-night >/dev/null 2>&1
  assert_not_contains "$(cat "$MOCK_LOG")" "osascript" || return 1
  cleanup_test_env
}

# Real Mac, 2026-09-26: a theme rendered before this capability existed has
# no terminal-app.colors, so install built nothing until a --reload.
test_install_renders_a_theme_that_predates_the_capability() {
  setup
  set_appearance dark
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  rm -f "$TEST_HOME"/.local/state/teeup/current/theme/*/terminal-app.colors
  : > "$MOCK_LOG"
  local out rc=0
  out="$(DRY_RUN=false "$TEEUP" configure terminal-app 2>&1)" || rc=$?
  assert_equals 0 "$rc" || { echo "$out"; return 1; }
  assert_contains "$(cat "$MOCK_LOG")" "osascript" "the profile must be built now" || { echo "$out"; return 1; }
  assert_not_contains "$out" "No rendered theme" || return 1
  cleanup_test_env
}

test_no_rendered_theme_is_a_quiet_no_op() {
  setup
  set_appearance dark
  local out rc=0
  out="$(DRY_RUN=false "$TEEUP" configure terminal-app 2>&1)" || rc=$?
  assert_equals 0 "$rc" || { echo "$out"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "osascript" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "defaults write" || return 1
  cleanup_test_env
}

test_a_bad_rendered_colour_is_refused() {
  setup
  set_appearance dark
  DRY_RUN=false "$TEEUP" configure theme >/dev/null 2>&1
  # A user template of the same basename wins over the shipped one.
  mkdir -p "$TEST_HOME/.config/teeup/themed"
  printf 'BackgroundColor red\n' > "$TEST_HOME/.config/teeup/themed/terminal-app.colors.tpl"
  DRY_RUN=false "$TEEUP" theme set tokyo-night >/dev/null 2>&1 || true
  local out
  out="$(DRY_RUN=false "$TEEUP" configure terminal-app 2>&1)" || true
  [[ ! -f "$OSA_APPLY" ]] || { echo "osascript ran with a bad colour"; return 1; }
  assert_contains "$out" "BackgroundColor" || return 1
  cleanup_test_env
}

test_profile_js_is_valid_javascript() {
  if [[ -z "$TERMINAL_NODE" ]]; then
    echo "node is not installed: profile.js was not parsed"
    return "$(missing_tool_status)"
  fi
  "$TERMINAL_NODE" --check "$PROFILE_JS" || return 1
}

# plist_value <file> <keypath> -> the value plutil extracts as raw text.
plist_raw() { "$TERMINAL_REAL_PLUTIL" -extract "$2" raw -o - "$1"; }

test_the_jxa_program_on_a_real_mac() {
  if [[ -z "$TERMINAL_REAL_OSASCRIPT" || -z "$TERMINAL_REAL_PLUTIL" ]]; then
    echo "osascript is not on this machine (not a Mac): the JXA program was not run"
    return "$TEST_SKIPPED"
  fi
  setup
  local plist="$TEST_HOME/Terminal Prefs & Co.plist" out red
  cat > "$plist" <<'EOF_PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Window Settings</key>
  <dict>
    <key>Pro</key>
    <dict><key>name</key><string>Pro</string><key>marker</key><string>user</string></dict>
    <key>teeupish</key>
    <dict><key>name</key><string>teeupish</string><key>marker</key><string>user</string></dict>
  </dict>
  <key>Other</key>
  <string>kept</string>
</dict>
</plist>
EOF_PLIST
  export TEEUP_TEST_TERMINAL_PLIST="$plist"
  "$TERMINAL_REAL_OSASCRIPT" -l JavaScript "$PROFILE_JS" apply "Pro" "" 13 "" BackgroundColor=#000000 >/dev/null 2>&1 &&
    { echo "a name without the teeup prefix was accepted"; return 1; }
  out="$("$TERMINAL_REAL_OSASCRIPT" -l JavaScript "$PROFILE_JS" apply "teeup Test Dark" "Menlo" 13 "$TEST_HOME/export.terminal" \
    BackgroundColor=#1e1e2e TextColor=#cdd6f4 TextBoldColor=#cdd6f4 CursorColor=#cdd6f4 SelectionColor=#45475a \
    ANSIBlackColor=#161622 ANSIRedColor=#f38ba8 ANSIGreenColor=#a6e3a1 ANSIYellowColor=#f9e2af ANSIBlueColor=#89b4fa \
    ANSIMagentaColor=#f5c2e7 ANSICyanColor=#94e2d5 ANSIWhiteColor=#cdd6f4 ANSIBrightBlackColor=#585b70 \
    ANSIBrightRedColor=#f38ba8 ANSIBrightGreenColor=#a6e3a1 ANSIBrightYellowColor=#f9e2af ANSIBrightBlueColor=#89b4fa \
    ANSIBrightMagentaColor=#f5c2e7 ANSIBrightCyanColor=#94e2d5 ANSIBrightWhiteColor=#cdd6f4 2>&1)" ||
    { echo "apply failed: $out"; return 1; }
  assert_equals "user" "$(plist_raw "$plist" "Window Settings.Pro.marker")" "Pro untouched" || return 1
  assert_equals "user" "$(plist_raw "$plist" "Window Settings.teeupish.marker")" "teeupish untouched" || return 1
  assert_equals "kept" "$(plist_raw "$plist" "Other")" "other keys untouched" || return 1
  assert_equals "Window Settings" "$(plist_raw "$plist" "Window Settings.teeup Test Dark.type")" || return 1
  assert_equals "teeup Test Dark" "$(plist_raw "$plist" "Window Settings.teeup Test Dark.name")" || return 1
  assert_file_exists "$TEST_HOME/export.terminal" "the importable copy" || return 1
  # The archived colour decodes back to the sRGB value it was built from.
  red="$("$TERMINAL_REAL_OSASCRIPT" -l JavaScript -e '
    ObjC.import("AppKit");
    function run(argv) {
      var d = $.NSDictionary.dictionaryWithContentsOfFile(argv[0]);
      var data = d.objectForKey("Window Settings").objectForKey("teeup Test Dark").objectForKey("ANSIRedColor");
      var c = $.NSKeyedUnarchiver.unarchiveObjectWithData(data).colorUsingColorSpace($.NSColorSpace.sRGBColorSpace);
      return Math.round(c.redComponent * 255) + "," + Math.round(c.greenComponent * 255) + "," + Math.round(c.blueComponent * 255);
    }' "$plist")"
  assert_equals "243,139,168" "$red" "ANSIRedColor #f38ba8 round-trips" || return 1
  out="$("$TERMINAL_REAL_OSASCRIPT" -l JavaScript "$PROFILE_JS" has "teeup Test Dark")"
  assert_equals "present" "$out" || return 1
  "$TERMINAL_REAL_OSASCRIPT" -l JavaScript "$PROFILE_JS" remove >/dev/null || { echo "remove failed"; return 1; }
  assert_equals "absent" "$("$TERMINAL_REAL_OSASCRIPT" -l JavaScript "$PROFILE_JS" has "teeup Test Dark")" || return 1
  assert_equals "user" "$(plist_raw "$plist" "Window Settings.Pro.marker")" "Pro survives remove" || return 1
  assert_equals "user" "$(plist_raw "$plist" "Window Settings.teeupish.marker")" "teeupish survives remove" || return 1
  cleanup_test_env
}

echo "capabilities/terminal-app"
run_test "metadata passes the capability check" test_metadata_passes_the_capability_check
run_test "every palette and mode reaches the script" test_every_palette_and_mode_reaches_the_script
run_test "the script is the shipped program" test_the_script_is_the_shipped_program
run_test "default and startup settings are written and recorded" test_default_and_startup_settings_are_written_and_recorded
run_test "the profile is written before it becomes the default" test_the_profile_is_written_before_it_becomes_the_default
run_test "a failed profile write leaves the defaults alone" test_a_failed_profile_write_leaves_the_defaults_alone
run_test "a failed default write is reported" test_a_failed_default_write_is_reported
run_test "only teeup profiles are named" test_only_teeup_profiles_are_named
run_test "remove restores the previous defaults" test_remove_restores_the_previous_defaults
run_test "remove falls back to Basic when the old profile is gone" test_remove_falls_back_to_basic_when_the_old_profile_is_gone
run_test "remove keeps a recorded profile it cannot check" test_remove_keeps_a_recorded_profile_it_cannot_check
run_test "a failed profile delete keeps it installed" test_a_failed_profile_delete_keeps_it_installed
run_test "uninstall runs terminal-app's remove before the state teardown" test_uninstall_runs_terminal_apps_remove_before_the_state_teardown
run_test "install renders a theme that predates the capability" test_install_renders_a_theme_that_predates_the_capability
run_test "the shipped migration installs terminal-app on an existing machine" test_the_shipped_migration_installs_terminal_app_on_an_existing_machine
run_test "the shipped migration leaves a skipped terminal-app alone" test_the_shipped_migration_leaves_a_skipped_terminal_app_alone
run_test "a fresh bootstrap marks the shipped migration without running it" test_a_fresh_bootstrap_marks_the_shipped_migration_without_running_it
run_test "dry-run configure changes nothing" test_dry_run_configure_changes_nothing
run_test "dry-run remove changes nothing" test_dry_run_remove_changes_nothing
run_test "the recorded font is handed over" test_the_recorded_font_is_handed_over
run_test "no recorded font leaves the font alone" test_no_recorded_font_leaves_the_font_alone
run_test "a machine can pick the font size" test_a_machine_can_pick_the_font_size
run_test "a font change rebuilds the profile" test_a_font_change_rebuilds_the_profile
run_test "the hook waits until the capability is installed" test_the_hook_waits_until_the_capability_is_installed
run_test "no rendered theme is a quiet no-op" test_no_rendered_theme_is_a_quiet_no_op
run_test "a bad rendered colour is refused" test_a_bad_rendered_colour_is_refused
run_test "profile.js is valid JavaScript" test_profile_js_is_valid_javascript
run_test "the JXA program on a real Mac" test_the_jxa_program_on_a_real_mac
print_summary
