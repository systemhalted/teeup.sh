#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

MAPPING='{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x7000000E0}]}'

setup() {
  setup_test_env
  mock_macos_base
  mock_command launchctl 0 ""
  mock_command hidutil 0 ""
  TEEUP="$TEEUP_PATH/bin/teeup"
  PLIST="$TEST_HOME/Library/LaunchAgents/sh.teeup.keyboard.plist"
}

test_configure_writes_the_agent_and_applies_the_mapping() {
  setup
  DRY_RUN=false "$TEEUP" configure keyboard >/dev/null
  assert_file_exists "$PLIST" || return 1
  local plist_body log_body
  plist_body="$(cat "$PLIST")"
  assert_contains "$plist_body" "<string>sh.teeup.keyboard</string>" || return 1
  assert_contains "$plist_body" "/usr/bin/hidutil" || return 1
  assert_contains "$plist_body" "HIDKeyboardModifierMappingSrc" || return 1
  log_body="$(cat "$MOCK_LOG")"
  assert_contains "$log_body" "launchctl bootstrap gui/501 $PLIST" || return 1
  assert_contains "$log_body" "hidutil property --set $MAPPING" || return 1
  cleanup_test_env
}

test_configure_is_idempotent_on_the_plist() {
  setup
  DRY_RUN=false "$TEEUP" configure keyboard >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure keyboard)"
  assert_contains "$out" "Already current: $PLIST" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" configure keyboard)"
  assert_contains "$out" "[DRY-RUN] Would write $PLIST" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: hidutil property --set $MAPPING" || return 1
  [[ ! -e "$PLIST" ]] || { echo "plist written in dry run"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "hidutil" "nothing ran in dry run" || return 1
  cleanup_test_env
}

test_remove_unloads_and_clears_the_mapping() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure keyboard >/dev/null
  DRY_RUN=false cap_run keyboard remove >/dev/null
  [[ ! -e "$PLIST" ]] || { echo "plist survived remove"; return 1; }
  local log_body
  log_body="$(cat "$MOCK_LOG")"
  assert_contains "$log_body" "launchctl bootout gui/501 $PLIST" || return 1
  assert_contains "$log_body" 'hidutil property --set {"UserKeyMapping":[]}' || return 1
  cleanup_test_env
}

test_remove_without_a_plist_is_quiet() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  local out
  out="$(DRY_RUN=false cap_run keyboard remove 2>&1)"
  assert_contains "$out" "nothing to unload" || return 1
  cleanup_test_env
}

echo "capabilities/keyboard"
run_test "configure writes the agent and applies the mapping" test_configure_writes_the_agent_and_applies_the_mapping
run_test "configure is idempotent on the plist" test_configure_is_idempotent_on_the_plist
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "remove unloads and clears the mapping" test_remove_unloads_and_clears_the_mapping
run_test "remove without a plist is quiet" test_remove_without_a_plist_is_quiet
print_summary
