#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false
}

# defaults read exits 1 for every key: a fresh Mac that has never set them.
mock_defaults_absent() {
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) exit 1 ;;
  *) exit 0 ;;
esac
EOF2
}

test_defaults_write_records_absent_and_writes() {
  setup
  mock_defaults_absent
  defaults_write com.apple.finder ShowPathbar -bool true >/dev/null
  local record
  record="$TEST_HOME/.local/state/teeup/defaults/com.apple.finder.ShowPathbar"
  assert_file_exists "$record" || return 1
  assert_equals "absent" "$(cat "$record")" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "defaults write com.apple.finder ShowPathbar -bool true" || return 1
  cleanup_test_env
}

test_defaults_write_records_the_prior_value() {
  setup
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) echo 0; exit 0 ;;
  *) exit 0 ;;
esac
EOF2
  defaults_write com.apple.dock autohide -bool true >/dev/null
  assert_equals "-bool:0" "$(cat "$TEST_HOME/.local/state/teeup/defaults/com.apple.dock.autohide")" || return 1
  cleanup_test_env
}

test_defaults_write_never_overwrites_an_existing_record() {
  setup
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) echo 1; exit 0 ;;
  *) exit 0 ;;
esac
EOF2
  mkdir -p "$TEST_HOME/.local/state/teeup/defaults"
  printf 'absent\n' > "$TEST_HOME/.local/state/teeup/defaults/com.apple.dock.autohide"
  defaults_write com.apple.dock autohide -bool true >/dev/null
  assert_equals "absent" "$(cat "$TEST_HOME/.local/state/teeup/defaults/com.apple.dock.autohide")" || return 1
  cleanup_test_env
}

test_defaults_write_dry_run_records_nothing() {
  setup
  mock_defaults_absent
  DRY_RUN=true
  local out
  out="$(defaults_write com.apple.finder ShowPathbar -bool true)"
  assert_contains "$out" "[DRY-RUN] Would execute: defaults write com.apple.finder ShowPathbar -bool true" || return 1
  assert_contains "$out" "[DRY-RUN] Would record defaults/com.apple.finder.ShowPathbar" || return 1
  [[ ! -e "$TEST_HOME/.local/state/teeup/defaults/com.apple.finder.ShowPathbar" ]] || { echo "record written in dry run"; return 1; }
  cleanup_test_env
}

test_defaults_restore_deletes_when_absent() {
  setup
  mock_defaults_absent
  mkdir -p "$TEST_HOME/.local/state/teeup/defaults"
  printf 'absent\n' > "$TEST_HOME/.local/state/teeup/defaults/com.apple.finder.ShowPathbar"
  defaults_restore com.apple.finder ShowPathbar >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "defaults delete com.apple.finder ShowPathbar" || return 1
  [[ ! -e "$TEST_HOME/.local/state/teeup/defaults/com.apple.finder.ShowPathbar" ]] || { echo "record kept"; return 1; }
  cleanup_test_env
}

test_defaults_restore_rewrites_the_prior_value() {
  setup
  mock_defaults_absent
  mkdir -p "$TEST_HOME/.local/state/teeup/defaults"
  printf -- '-bool:0\n' > "$TEST_HOME/.local/state/teeup/defaults/com.apple.dock.autohide"
  defaults_restore com.apple.dock autohide >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "defaults write com.apple.dock autohide -bool 0" || return 1
  cleanup_test_env
}

test_defaults_restore_without_a_record_is_a_noop() {
  setup
  mock_defaults_absent
  local out
  out="$(defaults_restore com.apple.dock autohide)"
  assert_contains "$out" "No recorded value for com.apple.dock autohide" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "defaults delete" || return 1
  cleanup_test_env
}

test_launchagent_install_writes_and_reloads() {
  setup
  mock_command launchctl 0 ""
  launchagent_install sh.teeup.test >/dev/null <<'EOF2'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>Label</key><string>sh.teeup.test</string></dict></plist>
EOF2
  local plist
  plist="$TEST_HOME/Library/LaunchAgents/sh.teeup.test.plist"
  assert_file_exists "$plist" || return 1
  assert_contains "$(cat "$plist")" "sh.teeup.test" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "launchctl bootout gui/501 $plist" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "launchctl bootstrap gui/501 $plist" || return 1
  cleanup_test_env
}

test_launchagent_install_is_idempotent_on_the_file() {
  setup
  mock_command launchctl 0 ""
  local plist body out
  plist="$TEST_HOME/Library/LaunchAgents/sh.teeup.test.plist"
  body='<plist version="1.0"><dict/></plist>'
  printf '%s\n' "$body" | launchagent_install sh.teeup.test >/dev/null
  out="$(printf '%s\n' "$body" | launchagent_install sh.teeup.test)"
  assert_contains "$out" "Already current: $plist" || return 1
  cleanup_test_env
}

test_launchagent_install_dry_run_writes_nothing() {
  setup
  mock_command launchctl 0 ""
  # shellcheck disable=SC2034  # last assignment in the file; read by run_cmd
  DRY_RUN=true
  local out
  out="$(printf '<plist/>\n' | launchagent_install sh.teeup.test)"
  assert_contains "$out" "[DRY-RUN] Would write $TEST_HOME/Library/LaunchAgents/sh.teeup.test.plist" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: launchctl bootstrap gui/501" || return 1
  [[ ! -e "$TEST_HOME/Library/LaunchAgents/sh.teeup.test.plist" ]] || { echo "plist written in dry run"; return 1; }
  cleanup_test_env
}

test_appearance_reads_the_interface_style() {
  setup
  mock_command_script defaults <<'EOF2'
case "$2" in
  -g) echo Dark; exit 0 ;;
esac
exit 1
EOF2
  assert_equals "dark" "$(appearance)" || return 1
  mock_defaults_absent
  assert_equals "light" "$(appearance)" || return 1
  cleanup_test_env
}

echo "lib/macos.sh"
run_test "defaults_write records absent and writes" test_defaults_write_records_absent_and_writes
run_test "defaults_write records the prior value" test_defaults_write_records_the_prior_value
run_test "defaults_write never overwrites a record" test_defaults_write_never_overwrites_an_existing_record
run_test "defaults_write dry run records nothing" test_defaults_write_dry_run_records_nothing
run_test "defaults_restore deletes when absent" test_defaults_restore_deletes_when_absent
run_test "defaults_restore rewrites the prior value" test_defaults_restore_rewrites_the_prior_value
run_test "defaults_restore without a record is a no-op" test_defaults_restore_without_a_record_is_a_noop
run_test "launchagent_install writes and reloads" test_launchagent_install_writes_and_reloads
run_test "launchagent_install is idempotent" test_launchagent_install_is_idempotent_on_the_file
run_test "launchagent_install dry run writes nothing" test_launchagent_install_dry_run_writes_nothing
run_test "appearance reads the interface style" test_appearance_reads_the_interface_style
print_summary
