#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_creates_work_and_personal() {
  setup
  DRY_RUN=false "$TEEUP" install dev-dirs >/dev/null
  assert_dir_exists "$TEST_HOME/Work" || return 1
  assert_dir_exists "$TEST_HOME/Personal" || return 1
  cleanup_test_env
}

test_existing_dirs_are_reported_not_recreated() {
  setup
  mkdir -p "$TEST_HOME/Work"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure dev-dirs)"
  assert_contains "$out" "Already present: $TEST_HOME/Work" || return 1
  assert_dir_exists "$TEST_HOME/Personal" || return 1
  cleanup_test_env
}

test_dry_run_does_not_claim_the_dirs_were_created() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" configure dev-dirs)"
  assert_contains "$out" "[DRY-RUN] Would execute: mkdir -p" || return 1
  # F1: a dry run must never claim the directories were created.
  assert_not_contains "$out" "Created $TEST_HOME/Work" || return 1
  assert_not_contains "$out" "Created $TEST_HOME/Personal" || return 1
  [[ ! -e "$TEST_HOME/Work" ]] || { echo "Work created in dry run"; return 1; }
  cleanup_test_env
}

echo "capabilities/dev-dirs"
run_test "creates Work and Personal" test_creates_work_and_personal
run_test "existing dirs reported not recreated" test_existing_dirs_are_reported_not_recreated
run_test "dry run does not claim the dirs were created" test_dry_run_does_not_claim_the_dirs_were_created
print_summary
