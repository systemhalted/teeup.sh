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

test_gum_is_used_when_available() {
  setup
  unset TEEUP_NO_GUM
  mock_command gum 0 "from-gum"
  assert_equals "from-gum" "$(ui_input "Name" </dev/null)" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "gum input" || return 1
  cleanup_test_env
}

echo "lib/ui.sh"
run_test "input reads piped answer" test_input_reads_piped_answer
run_test "input uses default on empty line" test_input_uses_default_on_empty_line
run_test "confirm yes and no" test_confirm_yes_and_no
run_test "choose by number and by name" test_choose_by_number_and_by_name
run_test "choose defaults to first on empty" test_choose_defaults_to_first_on_empty
run_test "gum is used when available" test_gum_is_used_when_available
print_summary
