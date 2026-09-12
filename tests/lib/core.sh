#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

test_paths_default_to_xdg() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  assert_equals "$TEST_HOME/.config/teeup" "$TEEUP_CONFIG_DIR" "config dir" || return 1
  assert_equals "$TEST_HOME/.local/state/teeup" "$TEEUP_STATE_DIR" "state dir" || return 1
  cleanup_test_env
}

test_run_cmd_dry_run_prints_and_skips() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  DRY_RUN=true
  local out
  out="$(run_cmd touch "$TEST_HOME/should-not-exist")"
  assert_contains "$out" "[DRY-RUN] Would execute: touch $TEST_HOME/should-not-exist" || return 1
  [[ ! -e "$TEST_HOME/should-not-exist" ]] || { echo "file was created in dry run"; return 1; }
  cleanup_test_env
}

test_run_cmd_executes_when_not_dry() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  DRY_RUN=false
  run_cmd touch "$TEST_HOME/exists"
  assert_file_exists "$TEST_HOME/exists" || return 1
  cleanup_test_env
}

test_run_logged_records_start_and_completion() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  TEEUP_LOG_FILE="$TEST_HOME/log"
  run_logged "say-hi" false echo hi
  local log
  log="$(cat "$TEEUP_LOG_FILE")"
  assert_contains "$log" "Starting: say-hi" || return 1
  assert_contains "$log" "Completed: say-hi" || return 1
  cleanup_test_env
}

test_run_logged_reports_failure_without_aborting() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  TEEUP_LOG_FILE="$TEST_HOME/log"
  local rc=0
  run_logged "boom" false false || rc=$?
  assert_failure "$rc" "run_logged returns the command's failure" || return 1
  assert_contains "$(cat "$TEEUP_LOG_FILE")" "Failed: boom (exit code: 1)" || return 1
  cleanup_test_env
}

test_run_logged_closes_stdin_unless_interactive() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  TEEUP_LOG_FILE="$TEST_HOME/log"
  local got
  got="$(echo typed | run_logged "read-test" false bash -c 'IFS= read -r x; echo "got:$x"')"
  assert_contains "$got" "got:" || return 1
  assert_not_contains "$got" "got:typed" "stdin must be /dev/null when not interactive" || return 1
  got="$(echo typed | run_logged "read-test" true bash -c 'IFS= read -r x; echo "got:$x"')"
  assert_contains "$got" "got:typed" "stdin kept when interactive" || return 1
  cleanup_test_env
}

test_macos_major_and_arch_use_mocks() {
  setup_test_env
  mock_macos_base
  source "$TEEUP_PATH/lib/core.sh"
  assert_equals "14" "$(macos_major)" || return 1
  assert_equals "arm64" "$(arch)" || return 1
  is_macos || { echo "is_macos should be true under Darwin mock"; return 1; }
  cleanup_test_env
}

test_format_duration() {
  source "$TEEUP_PATH/lib/core.sh"
  assert_equals "1h 1m 1s" "$(format_duration 3661)" || return 1
  assert_equals "2m 5s" "$(format_duration 125)" || return 1
  assert_equals "9s" "$(format_duration 9)" || return 1
}

test_have_honours_test_missing_hook() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  have bash || { echo "bash should be found"; return 1; }
  TEEUP_TEST_MISSING="bash gum" have bash && { echo "hook should hide bash"; return 1; }
  cleanup_test_env
}

test_user_config_dir_follows_xdg() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  assert_equals "$TEST_HOME/.config" "$(user_config_dir)" || return 1
  # In a subshell, so XDG_CONFIG_HOME stays set for the rest of the file.
  assert_equals "$HOME/.config" "$(unset XDG_CONFIG_HOME; user_config_dir)" || return 1
  cleanup_test_env
}

echo "lib/core.sh"
run_test "paths default to XDG under HOME" test_paths_default_to_xdg
run_test "run_cmd dry run prints and skips" test_run_cmd_dry_run_prints_and_skips
run_test "run_cmd executes when not dry" test_run_cmd_executes_when_not_dry
run_test "run_logged records start and completion" test_run_logged_records_start_and_completion
run_test "run_logged reports failure" test_run_logged_reports_failure_without_aborting
run_test "run_logged closes stdin unless interactive" test_run_logged_closes_stdin_unless_interactive
run_test "macos_major and arch" test_macos_major_and_arch_use_mocks
run_test "format_duration" test_format_duration
run_test "have honours TEEUP_TEST_MISSING hook" test_have_honours_test_missing_hook
run_test "user_config_dir follows XDG" test_user_config_dir_follows_xdg
print_summary
