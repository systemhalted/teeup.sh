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

test_machine_get_reads_only_the_machine_file() {
  setup
  # No machine file: not set, even when the answers file has the key exported.
  answers_set TEEUP_PACKAGE_MANAGER homebrew
  answers_load
  ! machine_get TEEUP_PACKAGE_MANAGER >/dev/null || { echo "reported a pin with no machine file"; return 1; }
  printf 'TEEUP_PACKAGE_MANAGER="macports"\n' > "$TEEUP_MACHINES_DIR/testmac.conf"
  assert_equals "macports" "$(machine_get TEEUP_PACKAGE_MANAGER)" || return 1
  # A key the machine file does not mention is not set, even though it is
  # exported here from the answers file.
  answers_set TEEUP_THEME catppuccin
  ! machine_get TEEUP_THEME >/dev/null || { echo "reported a pin for an unmentioned key"; return 1; }
  # An empty value is a pin (set-ness, not non-emptiness).
  printf 'TEEUP_PACKAGE_MANAGER=""\n' > "$TEEUP_MACHINES_DIR/testmac.conf"
  machine_get TEEUP_PACKAGE_MANAGER >/dev/null || { echo "an empty pin was reported as unset"; return 1; }
  assert_equals "" "$(machine_get TEEUP_PACKAGE_MANAGER)" || return 1
  # The lookup leaves this shell's values alone.
  assert_equals "homebrew" "$TEEUP_PACKAGE_MANAGER" || return 1
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

test_answers_exist_needs_wizard_key() {
  setup
  answers_set TEEUP_PACKAGE_MANAGER homebrew
  answers_exist && { echo "should not exist without TEEUP_NAME"; return 1; }
  answers_set TEEUP_NAME x
  answers_exist || { echo "should exist once TEEUP_NAME is set"; return 1; }
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

test_set_rejects_a_key_with_regex_characters() {
  setup
  local rc=0 out
  out="$( (answers_set 'TEEUP_A.*' hi) 2>&1 )" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "key must look like TEEUP_NAME" || return 1
  cleanup_test_env
}

test_set_rejects_a_bare_prefix() {
  setup
  local rc=0
  ( answers_set 'TEEUP_' hi ) >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" || return 1
  cleanup_test_env
}

test_set_replaces_only_the_exact_key() {
  setup
  answers_set TEEUP_EMAIL "old@example.com"
  answers_set TEEUP_WORK_EMAIL "work@example.com"
  answers_set TEEUP_EMAIL "new@example.com"
  answers_load
  assert_equals "new@example.com" "$(answers_get TEEUP_EMAIL)" || return 1
  assert_equals "work@example.com" "$(answers_get TEEUP_WORK_EMAIL)" || return 1
  cleanup_test_env
}

test_set_preserves_a_final_line_with_no_trailing_newline() {
  setup
  answers_set TEEUP_EMAIL "ada@example.com"
  # Strip the trailing newline answers_set always writes, so the file's last
  # line has none, then rewrite via the key it belongs to.
  printf '%s' "$(cat "$(answers_file)")" > "$(answers_file)"
  [[ "$(tail -c 1 "$(answers_file)")" != "" ]] || { echo "test setup did not strip the trailing newline"; return 1; }
  answers_set TEEUP_NAME "Ada Lovelace"
  answers_load
  assert_equals "ada@example.com" "$(answers_get TEEUP_EMAIL)" || return 1
  assert_equals "Ada Lovelace" "$(answers_get TEEUP_NAME)" || return 1
  cleanup_test_env
}

test_set_rejects_a_value_with_a_newline() {
  setup
  local rc=0 out
  out="$( (answers_set TEEUP_NOTE "$(printf 'line1\nline2')") 2>&1 )" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "cannot contain a newline" || return 1
  [[ ! -e "$(answers_file)" ]] || { echo "answers file written for a rejected value"; return 1; }
  cleanup_test_env
}

test_identity_helpers_without_work_email() {
  setup
  answers_set TEEUP_EMAIL "ada@example.com"
  answers_set TEEUP_WORK_EMAIL ""
  answers_load
  assert_equals "personal" "$(identity_list)" || return 1
  assert_equals "ada@example.com" "$(identity_email personal)" || return 1
  assert_equals "ada@example.com" "$(identity_email work)" || return 1
  assert_equals "$HOME/.ssh/id_ed25519_personal" "$(identity_key personal)" || return 1
  cleanup_test_env
}

test_identity_helpers_with_work_email() {
  setup
  answers_set TEEUP_EMAIL "ada@example.com"
  answers_set TEEUP_WORK_EMAIL "ada@corp.example"
  answers_load
  assert_equals "personal
work" "$(identity_list)" || return 1
  assert_equals "ada@corp.example" "$(identity_email work)" || return 1
  assert_equals "$HOME/.ssh/id_ed25519_work" "$(identity_key work)" || return 1
  cleanup_test_env
}

echo "lib/answers.sh"
run_test "set then get" test_set_then_get
run_test "set replaces existing key" test_set_replaces_existing_key
run_test "get default when unset" test_get_default_when_unset
run_test "machine file wins" test_machine_file_wins
run_test "machine_get reads only the machine file" test_machine_get_reads_only_the_machine_file
run_test "values with spaces and quotes survive" test_values_with_spaces_and_quotes_survive
run_test "answers_exist" test_answers_exist
run_test "answers_exist needs wizard key" test_answers_exist_needs_wizard_key
run_test "dry run set exports without writing" test_dry_run_set_exports_without_writing
run_test "set rejects a key with regex characters" test_set_rejects_a_key_with_regex_characters
run_test "set rejects a bare prefix" test_set_rejects_a_bare_prefix
run_test "set replaces only the exact key" test_set_replaces_only_the_exact_key
run_test "set preserves a final line with no trailing newline" test_set_preserves_a_final_line_with_no_trailing_newline
run_test "identity helpers without work email" test_identity_helpers_without_work_email
run_test "identity helpers with work email" test_identity_helpers_with_work_email
print_summary
