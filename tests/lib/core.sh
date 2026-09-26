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

test_run_logged_captures_output_to_log_and_terminal() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  TEEUP_LOG_FILE="$TEST_HOME/log"
  local out log
  out="$(run_logged "chatty" false bash -c 'echo out-line; echo err-line >&2' 2>&1)"
  log="$(cat "$TEEUP_LOG_FILE")"
  assert_contains "$out" "out-line" "stdout must still reach the terminal" || return 1
  assert_contains "$out" "err-line" "stderr must still reach the terminal" || return 1
  assert_contains "$log" "out-line" "stdout must also land in the log" || return 1
  assert_contains "$log" "err-line" "stderr must also land in the log" || return 1
  cleanup_test_env
}

# A run_logged command may call another capability, migration or hook, which
# starts another run_logged in the child shell. The inner runner's own append
# and the outer runner's tee used to put every inner line in the same log twice.
test_run_logged_nested_output_is_logged_once() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  TEEUP_LOG_FILE="$TEST_HOME/log"
  export TEEUP_LOG_FILE
  local out log needle count
  out="$(run_logged "outer" false bash -c '
    source "$TEEUP_PATH/lib/core.sh"
    run_logged "inner" false bash -c "echo nested-out; echo nested-err >&2"
  ' 2>&1)"
  log="$(cat "$TEEUP_LOG_FILE")"
  for needle in "Starting: inner" "nested-out" "nested-err" "Completed: inner"; do
    count="$(printf '%s\n' "$log" | grep -c "$needle" || true)"
    assert_equals "1" "$count" "$needle must be appended once" || return 1
    assert_contains "$out" "$needle" "$needle must still reach the terminal" || return 1
  done
  assert_equals "1" "$(printf '%s\n' "$log" | grep -c 'Starting: outer' || true)" || return 1
  assert_equals "1" "$(printf '%s\n' "$log" | grep -c 'Completed: outer' || true)" || return 1
  cleanup_test_env
}

# A capability's stderr (every warn(), every err()) must keep landing on fd 2
# on its own -- `./bootstrap >out.log` must still show warnings on the
# terminal, and a caller piping only stdout elsewhere must not lose stderr.
# Proved by redirecting the two fds to separate files (not by merging them
# with 2>&1, which is exactly the bug this guards against) and checking each
# file got only its own stream, while the log got both.
test_run_logged_keeps_stdout_and_stderr_on_separate_fds() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  TEEUP_LOG_FILE="$TEST_HOME/log"
  run_logged "chatty" false bash -c 'echo out-line; echo err-line >&2' \
    >"$TEST_HOME/stdout.txt" 2>"$TEST_HOME/stderr.txt"
  local stdout_content stderr_content log
  stdout_content="$(cat "$TEST_HOME/stdout.txt")"
  stderr_content="$(cat "$TEST_HOME/stderr.txt")"
  log="$(cat "$TEEUP_LOG_FILE")"
  assert_contains "$stdout_content" "out-line" "stdout redirection must still see stdout" || return 1
  assert_not_contains "$stdout_content" "err-line" "stderr must not be merged into stdout" || return 1
  assert_contains "$stderr_content" "err-line" "stderr redirection must still see stderr" || return 1
  assert_not_contains "$stderr_content" "out-line" "stdout must not be merged into stderr" || return 1
  assert_contains "$log" "out-line" "stdout must still land in the log" || return 1
  assert_contains "$log" "err-line" "stderr must still land in the log" || return 1
  cleanup_test_env
}

# The tee for each stream runs in the background (a plain pipe or process
# substitution does not otherwise guarantee it has drained before this
# function returns); run_logged must wait for it. Proved with enough output
# that a missing wait would show up as a short log, not just a slow one:
# every line of both streams must reach the log, none dropped by the race.
test_run_logged_waits_for_a_large_capture_to_drain() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  TEEUP_LOG_FILE="$TEST_HOME/log"
  run_logged "firehose" false bash -c '
    for i in $(seq 1 5000); do echo "out-$i"; done
    for i in $(seq 1 5000); do echo "err-$i" >&2; done
  ' >/dev/null 2>/dev/null
  local out_count err_count
  out_count="$(grep -c '^out-' "$TEEUP_LOG_FILE" || true)"
  err_count="$(grep -c '^err-' "$TEEUP_LOG_FILE" || true)"
  assert_equals "5000" "$out_count" "every stdout line must reach the log, none dropped by the race" || return 1
  assert_equals "5000" "$err_count" "every stderr line must reach the log, none dropped by the race" || return 1
  cleanup_test_env
}

test_run_logged_exit_status_survives_capture() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  TEEUP_LOG_FILE="$TEST_HOME/log"
  local rc=0
  run_logged "picky" false bash -c 'echo about to fail; exit 42' >/dev/null || rc=$?
  assert_equals "42" "$rc" "a captured command's real exit code must survive the tee" || return 1
  assert_contains "$(cat "$TEEUP_LOG_FILE")" "Failed: picky (exit code: 42)" || return 1
  cleanup_test_env
}

test_run_logged_interactive_is_not_captured_and_says_why() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  TEEUP_LOG_FILE="$TEST_HOME/log"
  local out log
  out="$(run_logged "secret-prompt" true echo do-not-log-this)"
  log="$(cat "$TEEUP_LOG_FILE")"
  assert_contains "$out" "do-not-log-this" "an interactive unit still prints to the terminal" || return 1
  assert_not_contains "$log" "do-not-log-this" "an interactive unit's output must never reach the log" || return 1
  assert_contains "$log" "secret-prompt is interactive" "the log must say capture was skipped" || return 1
  cleanup_test_env
}

test_run_logged_captures_dry_run_preview_lines() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  TEEUP_LOG_FILE="$TEST_HOME/log"
  DRY_RUN=true
  run_logged "previewed" false run_cmd touch "$TEST_HOME/should-not-exist" >/dev/null
  assert_contains "$(cat "$TEEUP_LOG_FILE")" "[DRY-RUN] Would execute: touch $TEST_HOME/should-not-exist" || return 1
  [[ ! -e "$TEST_HOME/should-not-exist" ]] || { echo "file was created in dry run"; return 1; }
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

# F1: a dry run must never claim a mutation happened. ok_unless_dry is the one
# mechanism every affected capability uses; this is the ground-truth test for
# it, both halves: silent under DRY_RUN=true, and identical to plain `ok` on a
# real run (the wording a real run prints today must not change).
test_ok_unless_dry_is_silent_when_dry_and_unchanged_otherwise() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  local out
  out="$(DRY_RUN=true ok_unless_dry "Installed ripgrep (Homebrew)")"
  assert_equals "" "$out" "a dry run must print nothing, not a false claim" || return 1
  out="$(DRY_RUN=false ok_unless_dry "Installed ripgrep (Homebrew)")"
  assert_equals "$(ok "Installed ripgrep (Homebrew)")" "$out" "real-run wording must match plain ok exactly" || return 1
  cleanup_test_env
}

test_have_hides_a_binary_by_absolute_path() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  local other
  other="$(mktemp -d)"
  mock_command frob 0 ""
  # Hiding by path: the MOCK_BIN copy is invisible, a copy elsewhere is not.
  export TEEUP_TEST_MISSING="$MOCK_BIN/frob"
  have frob && { echo "the listed path must be hidden"; return 1; }
  cp "$MOCK_BIN/frob" "$other/frob"
  PATH="$other:$PATH" have frob || { echo "a copy at another path is found"; return 1; }
  unset TEEUP_TEST_MISSING
  rm -rf "$other"
  cleanup_test_env
}

echo "lib/core.sh"
run_test "paths default to XDG under HOME" test_paths_default_to_xdg
run_test "run_cmd dry run prints and skips" test_run_cmd_dry_run_prints_and_skips
run_test "run_cmd executes when not dry" test_run_cmd_executes_when_not_dry
run_test "run_logged records start and completion" test_run_logged_records_start_and_completion
run_test "run_logged reports failure" test_run_logged_reports_failure_without_aborting
run_test "run_logged closes stdin unless interactive" test_run_logged_closes_stdin_unless_interactive
run_test "run_logged captures output to log and terminal" test_run_logged_captures_output_to_log_and_terminal
run_test "nested run_logged output is logged once" test_run_logged_nested_output_is_logged_once
run_test "run_logged keeps stdout and stderr on separate fds" test_run_logged_keeps_stdout_and_stderr_on_separate_fds
run_test "run_logged waits for a large capture to drain" test_run_logged_waits_for_a_large_capture_to_drain
run_test "run_logged exit status survives capture" test_run_logged_exit_status_survives_capture
run_test "run_logged interactive is not captured and says why" test_run_logged_interactive_is_not_captured_and_says_why
run_test "run_logged captures dry run preview lines" test_run_logged_captures_dry_run_preview_lines
run_test "macos_major and arch" test_macos_major_and_arch_use_mocks
run_test "format_duration" test_format_duration
run_test "have honours TEEUP_TEST_MISSING hook" test_have_honours_test_missing_hook
run_test "have hides a binary by absolute path" test_have_hides_a_binary_by_absolute_path
run_test "user_config_dir follows XDG" test_user_config_dir_follows_xdg
run_test "ok_unless_dry is silent when dry and unchanged otherwise" test_ok_unless_dry_is_silent_when_dry_and_unchanged_otherwise
print_summary
