#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_command hostname 0 "testmac"
  source "$TEEUP_PATH/lib/all.sh"
  # shellcheck disable=SC2034
  DRY_RUN=false
  # Point the machine file at a temp copy of the repo's machines/ dir.
  TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR"
}

test_set_then_get() {
  setup
  answers_set TEEUP_NAME "Ada Lovelace"
  answers_set TEEUP_EMAIL "ada@example.com"
  answers_load
  assert_equals "Ada Lovelace" "$(answers_get TEEUP_NAME)" || return 1
  assert_equals "ada@example.com" "$(answers_get TEEUP_EMAIL)" || return 1
  cleanup_test_env
}

test_set_replaces_existing_key() {
  setup
  answers_set TEEUP_THEME catppuccin
  answers_set TEEUP_THEME tokyo-night
  assert_equals "1" "$(grep -c '^TEEUP_THEME=' "$(answers_file)")" || return 1
  answers_load
  assert_equals "tokyo-night" "$(answers_get TEEUP_THEME)" || return 1
  cleanup_test_env
}

test_get_default_when_unset() {
  setup
  answers_load
  assert_equals "homebrew" "$(answers_get TEEUP_PACKAGE_MANAGER homebrew)" || return 1
  cleanup_test_env
}

test_machine_file_wins() {
  setup
  answers_set TEEUP_PACKAGE_MANAGER homebrew
  printf 'TEEUP_PACKAGE_MANAGER="macports"\n' > "$TEEUP_MACHINES_DIR/testmac.conf"
  answers_load
  assert_equals "macports" "$(answers_get TEEUP_PACKAGE_MANAGER)" || return 1
  cleanup_test_env
}

test_values_with_spaces_and_quotes_survive() {
  setup
  answers_set TEEUP_NAME 'O'"'"'Brien "The" Dev'
  answers_load
  assert_equals 'O'"'"'Brien "The" Dev' "$(answers_get TEEUP_NAME)" || return 1
  cleanup_test_env
}

test_answers_exist() {
  setup
  answers_exist && { echo "should not exist yet"; return 1; }
  answers_set TEEUP_NAME x
  answers_exist || { echo "should exist"; return 1; }
  cleanup_test_env
}

test_dry_run_set_exports_without_writing() {
  setup
  # shellcheck disable=SC2034
  DRY_RUN=true
  answers_set TEEUP_DAILY no >/dev/null
  assert_equals "no" "$(answers_get TEEUP_DAILY yes)" "value visible in-process" || return 1
  [[ ! -e "$(answers_file)" ]] || { echo "answers file written in dry run"; return 1; }
  cleanup_test_env
}

echo "lib/answers.sh"
run_test "set then get" test_set_then_get
run_test "set replaces existing key" test_set_replaces_existing_key
run_test "get default when unset" test_get_default_when_unset
run_test "machine file wins" test_machine_file_wins
run_test "values with spaces and quotes survive" test_values_with_spaces_and_quotes_survive
run_test "answers_exist" test_answers_exist
run_test "dry run set exports without writing" test_dry_run_set_exports_without_writing
print_summary
