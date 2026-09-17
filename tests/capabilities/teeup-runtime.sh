#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_gets_gum_and_jq() {
  setup
  export TEEUP_TEST_MISSING="gum jq"
  local out
  out="$(DRY_RUN=true "$TEEUP" install teeup-runtime)"
  assert_contains "$out" "Would execute: brew install gum" || return 1
  assert_contains "$out" "Would execute: brew install jq" || return 1
  cleanup_test_env
  unset TEEUP_TEST_MISSING
}

test_configure_creates_state_env_and_link() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local d
  for d in "done" toggles migrations shims logs current stock; do
    assert_dir_exists "$TEST_HOME/.local/state/teeup/$d" || return 1
  done
  local env_body
  env_body="$(cat "$TEST_HOME/.config/teeup/env")"
  # Values are %q-escaped, not double-quoted. A path with no shell
  # metacharacters comes out of %q unchanged, but the checkout itself can sit
  # anywhere: from "/Users/ada/My Code/teeup" the env file holds
  # "My\ Code", so the expectation is escaped the same way the capability
  # escapes it. (test_configure_quotes_a_path_with_shell_metacharacters below
  # covers the harsher characters in the paths teeup generates.)
  assert_contains "$env_body" "export TEEUP_PATH=$(printf '%q' "$TEEUP_PATH")" || return 1
  # The shell layer's home files bake these two paths in as absolute strings
  # at configure time (see capabilities/zsh/configure), so the env file has
  # to carry them too, not just TEEUP_PATH.
  assert_contains "$env_body" "export TEEUP_CONFIG_DIR=$(printf '%q' "$TEST_HOME/.config/teeup")" || return 1
  assert_contains "$env_body" "export TEEUP_STATE_DIR=$(printf '%q' "$TEST_HOME/.local/state/teeup")" || return 1
  assert_equals "$TEEUP_PATH/bin/teeup" "$(readlink "$TEST_HOME/.local/bin/teeup")" || return 1
  cleanup_test_env
}

test_configure_quotes_a_path_with_shell_metacharacters() {
  setup
  export XDG_CONFIG_HOME="$TEST_HOME/we\`ird \$dir \"q\" \\b"
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local env_file out
  env_file="$XDG_CONFIG_HOME/teeup/env"
  assert_file_exists "$env_file" || return 1
  # Passed as an argv element ($1), not interpolated into the script text: a
  # backtick, dollar, double quote or backslash in the path must not be
  # re-parsed as shell syntax here any more than it should be in the file
  # capabilities/teeup-runtime/configure writes.
  out="$(bash -c 'source "$1"; printf %s "$TEEUP_CONFIG_DIR"' _ "$env_file")"
  assert_equals "$XDG_CONFIG_HOME/teeup" "$out" || return 1
  out="$(bash -c 'source "$1"; printf %s "$TEEUP_PATH"' _ "$env_file")"
  assert_equals "$TEEUP_PATH" "$out" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure teeup-runtime)"
  assert_contains "$out" "Already current: $TEST_HOME/.config/teeup/env" || return 1
  assert_contains "$out" "Already linked" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" configure teeup-runtime)"
  [[ ! -e "$TEST_HOME/.config/teeup/env" ]] || { echo "env written in dry run"; return 1; }
  [[ ! -e "$TEST_HOME/.local/bin/teeup" ]] || { echo "link made in dry run"; return 1; }
  # F1: a dry run must never claim the link was made.
  assert_not_contains "$out" "Linked $TEST_HOME/.local/bin/teeup" || return 1
  cleanup_test_env
}

test_configure_backs_up_a_regular_file_at_the_link() {
  setup
  mkdir -p "$TEST_HOME/.local/bin"
  printf 'mine\n' > "$TEST_HOME/.local/bin/teeup"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure teeup-runtime 2>&1)"
  assert_contains "$out" "Replacing a regular file" || return 1
  assert_equals "$TEEUP_PATH/bin/teeup" "$(readlink "$TEST_HOME/.local/bin/teeup")" || return 1
  # A glob loop, not `ls | grep`: shellcheck rejects the latter (SC2010).
  local backup="" f
  for f in "$TEST_HOME"/.local/bin/teeup.teeup_backup_*; do
    [[ -e "$f" ]] && backup="$f"
  done
  [[ -n "$backup" ]] || { echo "no backup kept"; return 1; }
  cleanup_test_env
}

echo "capabilities/teeup-runtime"
run_test "install gets gum and jq" test_install_gets_gum_and_jq
run_test "configure creates state, env and link" test_configure_creates_state_env_and_link
run_test "configure quotes a path with shell metacharacters" test_configure_quotes_a_path_with_shell_metacharacters
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "configure backs up a regular file at the link" test_configure_backs_up_a_regular_file_at_the_link
print_summary
