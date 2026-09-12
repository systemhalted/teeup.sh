#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  source "$TEEUP_PATH/lib/all.sh"
  export TEEUP_NO_GUM=1
}

test_input_reads_piped_answer() {
  setup
  assert_equals "Ada" "$(echo Ada | ui_input "Name" "Nobody")" || return 1
  cleanup_test_env
}

test_input_uses_default_on_empty_line() {
  setup
  assert_equals "Nobody" "$(echo | ui_input "Name" "Nobody")" || return 1
  cleanup_test_env
}

test_confirm_yes_and_no() {
  setup
  echo y | ui_confirm "Continue?" || { echo "y should confirm"; return 1; }
  echo n | ui_confirm "Continue?" && { echo "n should refuse"; return 1; }
  echo | ui_confirm "Continue?" yes || { echo "empty uses default yes"; return 1; }
  echo | ui_confirm "Continue?" no && { echo "empty uses default no"; return 1; }
  cleanup_test_env
}

test_choose_by_number_and_by_name() {
  setup
  assert_equals "macports" "$(echo 2 | ui_choose "Package manager" homebrew macports)" || return 1
  assert_equals "homebrew" "$(echo homebrew | ui_choose "Package manager" homebrew macports)" || return 1
  cleanup_test_env
}

test_choose_defaults_to_first_on_empty() {
  setup
  assert_equals "homebrew" "$(echo | ui_choose "Package manager" homebrew macports)" || return 1
  cleanup_test_env
}

test_input_reads_a_value_with_no_trailing_newline() {
  setup
  assert_equals "Ada" "$(printf Ada | ui_input "Name" "Nobody")" || return 1
  cleanup_test_env
}

test_secret_reads_a_value_with_no_trailing_newline() {
  setup
  assert_equals "s3cret" "$(printf s3cret | ui_secret "Value" 2>/dev/null)" || return 1
  cleanup_test_env
}

test_secret_reads_a_piped_value_without_echoing_it() {
  setup
  local out err
  out="$(echo s3cret | ui_secret "Value" 2>"$TEST_HOME/stderr.log")"
  err="$(cat "$TEST_HOME/stderr.log")"
  assert_equals "s3cret" "$out" || return 1
  assert_not_contains "$err" "s3cret" "the secret must not appear on stderr" || return 1
  cleanup_test_env
}

test_secret_uses_gum_password_mode() {
  setup
  unset TEEUP_NO_GUM
  mock_command gum 0 "from-gum"
  assert_equals "from-gum" "$(ui_secret "Value" </dev/null)" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "--password" || return 1
  cleanup_test_env
}

test_gum_is_used_when_available() {
  setup
  unset TEEUP_NO_GUM
  mock_command gum 0 "from-gum"
  assert_equals "from-gum" "$(ui_input "Name" </dev/null)" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "gum input" || return 1
  cleanup_test_env
}

test_choose_accepts_leading_zero_number() {
  setup
  local err
  assert_equals "h" "$(echo 08 | ui_choose "Pick" a b c d e f g h i 2>/dev/null)" || return 1
  err="$(echo 08 | ui_choose "Pick" a b c d e f g h i 2>&1 >/dev/null)"
  assert_not_contains "$err" "value too great" "no bash diagnostic leaks" || return 1
  cleanup_test_env
}

echo "lib/ui.sh"
run_test "input reads piped answer" test_input_reads_piped_answer
run_test "input uses default on empty line" test_input_uses_default_on_empty_line
run_test "input reads a value with no trailing newline" test_input_reads_a_value_with_no_trailing_newline
run_test "secret reads a value with no trailing newline" test_secret_reads_a_value_with_no_trailing_newline
run_test "confirm yes and no" test_confirm_yes_and_no
run_test "choose by number and by name" test_choose_by_number_and_by_name
run_test "choose defaults to first on empty" test_choose_defaults_to_first_on_empty
run_test "secret reads a piped value without echoing it" test_secret_reads_a_piped_value_without_echoing_it
run_test "secret uses gum password mode" test_secret_uses_gum_password_mode
run_test "gum is used when available" test_gum_is_used_when_available
run_test "choose accepts leading zero number" test_choose_accepts_leading_zero_number
print_summary
