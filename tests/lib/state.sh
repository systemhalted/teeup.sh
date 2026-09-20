#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false
}

test_done_check_mark_clear() {
  setup
  state_done check bootstrap && { echo "should not be done yet"; return 1; }
  state_done mark bootstrap
  state_done check bootstrap || { echo "should be done"; return 1; }
  assert_file_exists "$TEEUP_STATE_DIR/done/bootstrap" || return 1
  state_done clear bootstrap
  state_done check bootstrap && { echo "should be cleared"; return 1; }
  cleanup_test_env
}

test_done_ensure_succeeds_only_first_time() {
  setup
  state_done ensure invite || { echo "first ensure should succeed"; return 1; }
  state_done ensure invite && { echo "second ensure should fail"; return 1; }
  cleanup_test_env
}

# A dry run previews the answer the real run would give: 0 the first time,
# non-zero once the marker is there. Always answering "first time" would make
# a caller that prints a long one-off notice print it on every preview, on a
# machine that would really see the short line.
test_done_ensure_dry_run_previews_the_real_answer() {
  setup
  DRY_RUN=true state_done ensure invite >/dev/null || { echo "dry run on a fresh marker should succeed"; return 1; }
  [[ ! -e "$TEEUP_STATE_DIR/done/invite" ]] || { echo "a dry run must not write the marker"; return 1; }
  state_done ensure invite >/dev/null || { echo "fixture: the real ensure should succeed"; return 1; }
  DRY_RUN=true state_done ensure invite >/dev/null && { echo "dry run must report the marker that is already there"; return 1; }
  cleanup_test_env
}

test_na_check_mark_clear() {
  setup
  state_na check "cap-aerospace" && { echo "should not be na yet"; return 1; }
  state_na mark "cap-aerospace"
  state_na check "cap-aerospace" || { echo "should be na"; return 1; }
  assert_file_exists "$TEEUP_STATE_DIR/na/cap-aerospace" || return 1
  state_na clear "cap-aerospace"
  state_na check "cap-aerospace" && { echo "should be cleared"; return 1; }
  cleanup_test_env
}

test_toggle_round_trip() {
  setup
  state_toggle_enabled nightlight && { echo "off by default"; return 1; }
  state_toggle nightlight on
  state_toggle_enabled nightlight || { echo "should be on"; return 1; }
  state_toggle nightlight
  state_toggle_enabled nightlight && { echo "toggle should turn it off"; return 1; }
  cleanup_test_env
}

test_migration_markers() {
  setup
  state_migration_done 1700000000 && { echo "not applied yet"; return 1; }
  state_migration_mark 1700000000
  state_migration_done 1700000000 || { echo "should be applied"; return 1; }
  cleanup_test_env
}

test_dry_run_records_nothing() {
  setup
  # shellcheck disable=SC2034
  DRY_RUN=true
  state_done mark bootstrap >/dev/null
  [[ ! -e "$TEEUP_STATE_DIR/done/bootstrap" ]] || { echo "marker written in dry run"; return 1; }
  cleanup_test_env
}

echo "lib/state.sh"
run_test "done check/mark/clear" test_done_check_mark_clear
run_test "done ensure succeeds only once" test_done_ensure_succeeds_only_first_time
run_test "done ensure dry run previews the real answer" test_done_ensure_dry_run_previews_the_real_answer
run_test "na check/mark/clear" test_na_check_mark_clear
run_test "toggle round trip" test_toggle_round_trip
run_test "migration markers" test_migration_markers
run_test "dry run records nothing" test_dry_run_records_nothing
print_summary
