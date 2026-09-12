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
  assert_equals "export TEEUP_PATH=\"$TEEUP_PATH\"" "$(cat "$TEST_HOME/.config/teeup/env")" || return 1
  assert_equals "$TEEUP_PATH/bin/teeup" "$(readlink "$TEST_HOME/.local/bin/teeup")" || return 1
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
  DRY_RUN=true "$TEEUP" configure teeup-runtime >/dev/null
  [[ ! -e "$TEST_HOME/.config/teeup/env" ]] || { echo "env written in dry run"; return 1; }
  [[ ! -e "$TEST_HOME/.local/bin/teeup" ]] || { echo "link made in dry run"; return 1; }
  cleanup_test_env
}

echo "capabilities/teeup-runtime"
run_test "install gets gum and jq" test_install_gets_gum_and_jq
run_test "configure creates state, env and link" test_configure_creates_state_env_and_link
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
print_summary
