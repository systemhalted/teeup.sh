#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command killall 0 ""
  mock_defaults_absent
  TEEUP="$TEEUP_PATH/bin/teeup"
  RECORDS="$TEST_HOME/.local/state/teeup/defaults"
}

mock_defaults_absent() {
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) exit 1 ;;
  *) exit 0 ;;
esac
EOF2
}

test_configure_writes_every_preference() {
  setup
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  local log_body
  log_body="$(cat "$MOCK_LOG")"
  assert_contains "$log_body" "defaults write NSGlobalDomain AppleShowAllExtensions -bool true" || return 1
  assert_contains "$log_body" "defaults write com.apple.finder FXPreferredViewStyle -string Nlsv" || return 1
  assert_contains "$log_body" "defaults write NSGlobalDomain KeyRepeat -int 2" || return 1
  assert_contains "$log_body" "defaults write NSGlobalDomain InitialKeyRepeat -int 15" || return 1
  assert_contains "$log_body" "defaults write com.apple.dock autohide -bool true" || return 1
  assert_contains "$log_body" "defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true" || return 1
  assert_contains "$log_body" "defaults write com.apple.screencapture location -string $TEST_HOME/Screenshots" || return 1
  assert_contains "$log_body" "killall Finder" || return 1
  assert_contains "$log_body" "killall Dock" || return 1
  cleanup_test_env
}

test_configure_records_every_key_and_creates_the_screenshots_dir() {
  setup
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  assert_dir_exists "$TEST_HOME/Screenshots" || return 1
  assert_equals "absent" "$(cat "$RECORDS/NSGlobalDomain.AppleShowAllExtensions")" || return 1
  assert_equals "absent" "$(cat "$RECORDS/com.apple.dock.autohide")" || return 1
  assert_equals "16" "$(find "$RECORDS" -type f | wc -l | tr -d ' ')" "one record per preference" || return 1
  cleanup_test_env
}

test_configure_records_a_prior_value() {
  setup
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) echo 1; exit 0 ;;
  *) exit 0 ;;
esac
EOF2
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  assert_equals "-bool:1" "$(cat "$RECORDS/com.apple.dock.autohide")" || return 1
  assert_equals "-int:1" "$(cat "$RECORDS/NSGlobalDomain.KeyRepeat")" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure macos-defaults)"
  assert_contains "$out" "Already present: $TEST_HOME/Screenshots" || return 1
  assert_equals "absent" "$(cat "$RECORDS/com.apple.dock.autohide")" "the record is never refreshed" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" configure macos-defaults)"
  assert_contains "$out" "[DRY-RUN] Would execute: defaults write com.apple.dock autohide -bool true" || return 1
  assert_contains "$out" "[DRY-RUN] Would record defaults/com.apple.dock.autohide as absent" || return 1
  [[ ! -d "$RECORDS" ]] || { echo "records written in dry run"; return 1; }
  [[ ! -d "$TEST_HOME/Screenshots" ]] || { echo "Screenshots created in dry run"; return 1; }
  cleanup_test_env
}

test_remove_restores_every_key() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  : > "$MOCK_LOG"
  DRY_RUN=false cap_run macos-defaults remove >/dev/null
  local log_body
  log_body="$(cat "$MOCK_LOG")"
  assert_contains "$log_body" "defaults delete com.apple.dock autohide" || return 1
  assert_contains "$log_body" "defaults delete com.apple.screencapture location" || return 1
  assert_equals "0" "$(find "$RECORDS" -type f | wc -l | tr -d ' ')" "every record is consumed" || return 1
  cleanup_test_env
}

test_remove_rewrites_a_recorded_value() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mkdir -p "$RECORDS"
  printf -- '-bool:1\n' > "$RECORDS/com.apple.dock.autohide"
  DRY_RUN=false cap_run macos-defaults remove >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "defaults write com.apple.dock autohide -bool 1" || return 1
  cleanup_test_env
}

echo "capabilities/macos-defaults"
run_test "configure writes every preference" test_configure_writes_every_preference
run_test "configure records every key and creates ~/Screenshots" test_configure_records_every_key_and_creates_the_screenshots_dir
run_test "configure records a prior value" test_configure_records_a_prior_value
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "remove restores every key" test_remove_restores_every_key
run_test "remove rewrites a recorded value" test_remove_rewrites_a_recorded_value
print_summary
