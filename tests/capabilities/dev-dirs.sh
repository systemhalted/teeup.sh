#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_creates_work_only() {
  setup
  DRY_RUN=false "$TEEUP" install dev-dirs >/dev/null
  assert_dir_exists "$TEST_HOME/Work" || return 1
  # One identity, one root (2026-09-17 decision): ~/Personal is no longer
  # created.
  [[ ! -e "$TEST_HOME/Personal" ]] || { echo "Personal directory created; the two-root model is gone"; return 1; }
  cleanup_test_env
}

test_existing_dir_is_reported_not_recreated() {
  setup
  mkdir -p "$TEST_HOME/Work"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure dev-dirs)"
  assert_contains "$out" "Already present: $TEST_HOME/Work" || return 1
  cleanup_test_env
}

test_dry_run_does_not_claim_the_dir_was_created() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" configure dev-dirs)"
  assert_contains "$out" "[DRY-RUN] Would execute: mkdir -p" || return 1
  # F1: a dry run must never claim the directory was created.
  assert_not_contains "$out" "Created $TEST_HOME/Work" || return 1
  [[ ! -e "$TEST_HOME/Work" ]] || { echo "Work created in dry run"; return 1; }
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  DRY_RUN=false "$TEEUP" configure dev-dirs >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure dev-dirs)"
  assert_contains "$out" "Already present: $TEST_HOME/Work" || return 1
  cleanup_test_env
}

echo "capabilities/dev-dirs"
run_test "creates Work only" test_creates_work_only
run_test "existing dir reported not recreated" test_existing_dir_is_reported_not_recreated
run_test "dry run does not claim the dir was created" test_dry_run_does_not_claim_the_dir_was_created
run_test "configure is idempotent" test_configure_is_idempotent
print_summary
