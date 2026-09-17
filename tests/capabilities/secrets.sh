#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  export TEEUP_NO_GUM=1
  TEEUP="$TEEUP_PATH/bin/teeup"
}

# A Keychain that remembers one item, so get/set/rm can be checked end to end.
# `-i` mimics real security(1): the whole command arrives on stdin, one line,
# with fields quoted the same way (a double-quoted string, \ and " escaped
# with a backslash). Parsing it in bash rather than shelling out again keeps
# this mock from ever needing the value on an argv of its own.
mock_security_store() {
  mock_command_script security <<'EOF2'
store="$HOME/keychain"
case "$1" in
  -i)
    IFS= read -r cmdline
    rest="${cmdline#*-w \"}"
    val="${rest%\"}"
    # Reverse the escaping in the order it was applied: quotes first, then
    # backslashes (the caller escapes backslashes first, then quotes).
    val="${val//\\\"/\"}"
    val="${val//\\\\/\\}"
    printf '%s\n' "$val" > "$store"
    ;;
  find-generic-password)
    [ -f "$store" ] || exit 44
    cat "$store"
    ;;
  add-generic-password)
    shift
    while [ $# -gt 0 ]; do
      if [ "$1" = "-w" ]; then shift; printf '%s\n' "$1" > "$store"; fi
      shift
    done
    ;;
  delete-generic-password)
    [ -f "$store" ] || exit 44
    rm -f "$store"
    ;;
esac
EOF2
}

test_set_then_get_round_trips() {
  setup
  mock_security_store
  printf 's3cret\n' | "$TEEUP" secret set openai_api_key >/dev/null
  assert_equals "s3cret" "$("$TEEUP" secret get openai_api_key)" || return 1
  # The value must never be a command-line argument (ps can read any local
  # user's argv): MOCK_LOG only ever records "security -i", so a value there
  # would prove a regression back to passing -w on argv.
  assert_not_contains "$(cat "$MOCK_LOG")" "s3cret" || { echo "secret leaked into MOCK_LOG (argv)"; return 1; }
  assert_contains "$(cat "$MOCK_LOG")" "security -i" || return 1
  cleanup_test_env
}

test_set_round_trips_a_value_with_spaces_and_quotes() {
  setup
  mock_security_store
  local value='has "quotes" and \backslash\ and spaces'
  printf '%s\n' "$value" | "$TEEUP" secret set tricky_key >/dev/null
  assert_equals "$value" "$("$TEEUP" secret get tricky_key)" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "$value" || { echo "secret leaked into MOCK_LOG (argv)"; return 1; }
  cleanup_test_env
}

test_get_missing_secret_fails_with_a_hint() {
  setup
  mock_command security 44 ""
  local rc=0 out
  out="$("$TEEUP" secret get nope 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "teeup secret set nope" || return 1
  cleanup_test_env
}

test_rm_deletes_the_item() {
  setup
  mock_security_store
  printf 's3cret\n' | "$TEEUP" secret set gh_token >/dev/null
  "$TEEUP" secret rm gh_token >/dev/null
  local rc=0
  "$TEEUP" secret get gh_token >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" || return 1
  cleanup_test_env
}

test_set_never_prints_the_value_in_dry_run() {
  setup
  mock_security_store
  local out
  out="$(printf 's3cret\n' | DRY_RUN=true "$TEEUP" secret set gh_token 2>&1)"
  assert_contains "$out" "Would execute: security add-generic-password -U -s teeup -a gh_token -w <value>" || return 1
  assert_not_contains "$out" "s3cret" || return 1
  [[ ! -e "$TEST_HOME/keychain" ]] || { echo "dry run wrote to the keychain"; return 1; }
  cleanup_test_env
}

test_set_refuses_an_empty_value() {
  setup
  mock_security_store
  local rc=0 out
  out="$(printf '\n' | "$TEEUP" secret set empty 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Refusing to store an empty value" || return 1
  cleanup_test_env
}

test_usage_without_a_name() {
  setup
  local rc=0 out
  out="$("$TEEUP" secret get 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Usage: teeup secret get|set|rm <name>" || return 1
  cleanup_test_env
}

test_configure_reports_the_keychain_is_usable() {
  setup
  mock_security_store
  local out
  out="$(DRY_RUN=false "$TEEUP" configure secrets)"
  assert_contains "$out" "Keychain service 'teeup' is ready" || return 1
  cleanup_test_env
}

test_configure_dry_run_does_not_claim_the_keychain_is_ready() {
  setup
  mock_security_store
  local out
  out="$(DRY_RUN=true "$TEEUP" configure secrets)"
  # F1: the Keychain check is a read, not a mutation, but the "ready" message
  # implies a verification that a dry run has no business claiming.
  assert_not_contains "$out" "Keychain service 'teeup' is ready" || return 1
  cleanup_test_env
}

test_configure_twice_is_a_no_op() {
  setup
  mock_security_store
  DRY_RUN=false "$TEEUP" configure secrets >/dev/null
  local marker="$TEST_HOME/.idempotency-marker"
  : > "$marker"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure secrets)"
  assert_contains "$out" "Keychain service 'teeup' is ready" || return 1
  # Nothing under $HOME may change on the second run. mock.log and the marker
  # itself are the harness's own bookkeeping.
  local changed
  changed="$(find "$TEST_HOME" -newer "$marker" -type f \
    ! -name 'mock.log' ! -name '.idempotency-marker' 2>/dev/null)"
  assert_equals "" "$changed" "second configure must write nothing" || return 1
  cleanup_test_env
}

test_teeup_env_function_is_shipped_and_parses() {
  setup
  local f="$TEEUP_PATH/capabilities/secrets/default/functions.zsh"
  assert_file_exists "$f" || return 1
  assert_contains "$(cat "$f")" "teeup-env()" || return 1
  # A grep alone would pass on a syntactically broken function. zsh is
  # installed on every runner this suite targets (CI installs it on Linux).
  if ! command -v zsh >/dev/null 2>&1; then
    echo "zsh is required to syntax-check the shipped function"
    return 1
  fi
  zsh -n "$f" || { echo "functions.zsh does not parse"; return 1; }
  cleanup_test_env
}

test_teeup_env_sanitises_the_variable_name() {
  setup
  if ! command -v zsh >/dev/null 2>&1; then
    echo "zsh is required to run teeup-env"
    return 1
  fi
  mock_security_store
  printf 's3cret\n' | "$TEEUP" secret set my.api-key >/dev/null
  local out
  out="$(PATH="$TEEUP_PATH/bin:$PATH" zsh -f -c "source '$TEEUP_PATH/capabilities/secrets/default/functions.zsh'; teeup-env my.api-key >/dev/null; print -r -- \"\$MY_API_KEY\"" 2>&1)"
  assert_equals "s3cret" "$out" || return 1
  cleanup_test_env
}

test_rejects_invalid_secret_names() {
  setup
  mock_security_store
  local rc=0 out
  # Test name with leading dash
  out="$("$TEEUP" secret get -- -badname 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Secret names use letters, digits, dot, underscore and dash, and cannot start with a dash" || return 1
  # Test name with spaces
  rc=0
  out="$("$TEEUP" secret get "a b" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Secret names use letters, digits, dot, underscore and dash, and cannot start with a dash" || return 1
  cleanup_test_env
}

test_set_never_leaks_via_trace() {
  setup
  mock_security_store
  local out
  # Run with bash -x to enable trace mode, capture all output
  out="$(printf 's3cr3t\n' | bash -x "$TEEUP" secret set traced_key 2>&1)"
  # Verify the secret value does not appear anywhere in the trace
  assert_not_contains "$out" "s3cr3t" || { echo "secret leaked in bash -x trace"; return 1; }
  # Verify the command succeeded
  assert_contains "$out" "Stored traced_key" || return 1
  cleanup_test_env
}

test_teeup_env_hides_the_secret_from_zsh_xtrace() {
  setup
  if ! command -v zsh >/dev/null 2>&1; then
    echo "zsh is required to run teeup-env"
    return 1
  fi
  mock_command security 0 "s3cret"
  local out
  # `set +x` runs after teeup-env returns and before the plain `print` below,
  # so the trace covers exactly the call under test; the readback print is
  # the test's own assertion mechanism, not part of what teeup-env must hide.
  out="$(PATH="$TEEUP_PATH/bin:$PATH" zsh -f -c "source '$TEEUP_PATH/capabilities/secrets/default/functions.zsh'; set -x; teeup-env demo >/dev/null; set +x; print -r -- \"\$DEMO\"" 2>"$TEST_HOME/err.txt")"
  assert_equals "s3cret" "$out" || return 1
  assert_not_contains "$(cat "$TEST_HOME/err.txt")" "s3cret" || { echo "secret leaked into the zsh xtrace"; return 1; }
  cleanup_test_env
}

echo "capabilities/secrets"
run_test "set then get round trips" test_set_then_get_round_trips
run_test "set round trips a value with spaces and quotes" test_set_round_trips_a_value_with_spaces_and_quotes
run_test "get missing secret fails with a hint" test_get_missing_secret_fails_with_a_hint
run_test "rm deletes the item" test_rm_deletes_the_item
run_test "set never prints the value in dry run" test_set_never_prints_the_value_in_dry_run
run_test "set refuses an empty value" test_set_refuses_an_empty_value
run_test "usage without a name" test_usage_without_a_name
run_test "configure reports the keychain is usable" test_configure_reports_the_keychain_is_usable
run_test "configure dry run does not claim the keychain is ready" test_configure_dry_run_does_not_claim_the_keychain_is_ready
run_test "configure twice is a no-op" test_configure_twice_is_a_no_op
run_test "rejects invalid secret names" test_rejects_invalid_secret_names
run_test "set never leaks via trace" test_set_never_leaks_via_trace
run_test "teeup-env function is shipped and parses" test_teeup_env_function_is_shipped_and_parses
run_test "teeup-env sanitises the variable name" test_teeup_env_sanitises_the_variable_name
run_test "teeup-env hides the secret from zsh xtrace" test_teeup_env_hides_the_secret_from_zsh_xtrace
print_summary
