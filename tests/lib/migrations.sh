#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  # A migrations directory with a space, a quote, a dollar sign and an
  # ampersand in its path: file names reach bash, run_logged and the markers.
  export TEEUP_MIGRATIONS_DIR="$TEST_HOME/mig rations 'q' \$x & co"
  mkdir -p "$TEEUP_MIGRATIONS_DIR"
  source "$TEEUP_PATH/lib/all.sh"
  # shellcheck disable=SC2034  # read by the library functions under test
  DRY_RUN=false
  MARKS="$TEST_HOME/.local/state/teeup/migrations"
}

# make_migration <name> <body>
make_migration() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$TEEUP_MIGRATIONS_DIR/$1"
}

test_list_is_oldest_first_and_ignores_other_files() {
  setup
  make_migration 1790000000.sh ':'
  make_migration 999999999.sh ':'
  make_migration 1780000000.sh ':'
  make_migration helper.sh ':'
  printf 'notes\n' > "$TEEUP_MIGRATIONS_DIR/README.md"
  assert_equals "999999999.sh 1780000000.sh 1790000000.sh" "$(migrations_list | tr '\n' ' ' | sed 's/ $//')" || return 1
  cleanup_test_env
}

test_pending_leaves_out_applied_migrations() {
  setup
  make_migration 1780000000.sh ':'
  make_migration 1790000000.sh ':'
  state_migration_mark 1780000000.sh
  assert_equals "1790000000.sh" "$(migrations_pending)" || return 1
  migrations_mark_all
  assert_equals "" "$(migrations_pending)" || return 1
  assert_file_exists "$MARKS/1790000000.sh" || return 1
  cleanup_test_env
}

test_run_pending_runs_each_once_in_order_with_the_library() {
  setup
  make_migration 1790000000.sh 'echo "second $TEEUP_MIGRATION" >> "$HOME/ran"'
  make_migration 1780000000.sh 'log "from lib"; echo "first $TEEUP_MIGRATION name=${TEEUP_NAME:-}" >> "$HOME/ran"'
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_NAME="Ada"\n' > "$TEST_HOME/.config/teeup/answers"
  local out
  out="$(migrations_run_pending 2>&1)"
  assert_equals "$(printf 'first 1780000000.sh name=Ada\nsecond 1790000000.sh')" "$(cat "$TEST_HOME/ran")" || return 1
  assert_contains "$out" "from lib" || return 1
  assert_contains "$out" "Completed: migration 1780000000.sh" || return 1
  assert_contains "$out" "Applied 2 migration(s)." || return 1
  assert_file_exists "$MARKS/1780000000.sh" || return 1
  assert_file_exists "$MARKS/1790000000.sh" || return 1
  out="$(migrations_run_pending 2>&1)"
  assert_contains "$out" "No pending migrations." || return 1
  assert_equals "2" "$(wc -l < "$TEST_HOME/ran" | tr -d ' ')" "nothing runs twice" || return 1
  cleanup_test_env
}

test_a_failed_migration_stops_the_run_and_stays_pending() {
  setup
  make_migration 1770000000.sh 'echo "one" >> "$HOME/ran"'
  make_migration 1780000000.sh 'false; echo "unreachable" >> "$HOME/ran"'
  make_migration 1790000000.sh 'echo "three" >> "$HOME/ran"'
  local out rc=0
  out="$(migrations_run_pending 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_equals "one" "$(cat "$TEST_HOME/ran")" "bash -eu stops the failing script, and nothing after it runs" || return 1
  assert_contains "$out" "Migration 1780000000.sh failed, so the migrations after it did not run" || return 1
  assert_equals "$(printf '1780000000.sh\n1790000000.sh')" "$(migrations_pending)" || return 1
  cleanup_test_env
}

test_dry_run_previews_and_marks_nothing() {
  setup
  make_migration 1780000000.sh 'run_cmd touch "$HOME/made"'
  local out
  out="$(DRY_RUN=true migrations_run_pending 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: touch $TEST_HOME/made" || return 1
  assert_contains "$out" "[DRY-RUN] Would record state: migrations/1780000000.sh" || return 1
  [[ ! -e "$TEST_HOME/made" ]] || { echo "a migration mutated in dry run"; return 1; }
  [[ ! -e "$MARKS/1780000000.sh" ]] || { echo "marker written in dry run"; return 1; }
  cleanup_test_env
}

# A capability whose configure renders its file (the way zsh renders its home
# stubs), so a refresh must go through configure rather than copy the raw file.
make_rendering_cap() {
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR/tool/config"
  printf 'summary="Fixture tool"\ngroup=system\ntier=lazy\nrequires=""\nprovides=""\ninteractive=false\n' > "$TEEUP_CAPS_DIR/tool/capability"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/tool/install"
  cat > "$TEEUP_CAPS_DIR/tool/configure" <<'EOF2'
#!/usr/bin/env bash
rendered="$(mktemp)"
sed "s|@HOME@|$HOME|" "$TEEUP_CAP_DIR/config/tool.conf" > "$rendered"
copy_config_once "$rendered" "$HOME/.config/tool.conf"
rm -f "$rendered"
copy_config_once "$TEEUP_CAP_DIR/config/other.conf" "$HOME/.config/other.conf"
EOF2
  chmod +x "$TEEUP_CAPS_DIR/tool/install" "$TEEUP_CAPS_DIR/tool/configure"
  printf 'home=@HOME@\nversion=1\n' > "$TEEUP_CAPS_DIR/tool/config/tool.conf"
  printf 'other=1\n' > "$TEEUP_CAPS_DIR/tool/config/other.conf"
}

test_refresh_replaces_pristine_rendered_files_and_keeps_edited_ones() {
  setup
  make_rendering_cap
  cap_run tool configure >/dev/null
  state_done mark cap-tool
  printf 'other=1\nmine=1\n' > "$TEST_HOME/.config/other.conf"
  # The shipped files change in the next teeup version.
  printf 'home=@HOME@\nversion=2\n' > "$TEEUP_CAPS_DIR/tool/config/tool.conf"
  printf 'other=2\n' > "$TEEUP_CAPS_DIR/tool/config/other.conf"
  local out
  out="$(migration_refresh tool 2>&1)"
  assert_equals "$(printf 'home=%s\nversion=2' "$TEST_HOME")" "$(cat "$TEST_HOME/.config/tool.conf")" "refreshed, and rendered by configure" || return 1
  assert_contains "$out" "Refreshed $TEST_HOME/.config/tool.conf" || return 1
  assert_equals "$(printf 'other=1\nmine=1')" "$(cat "$TEST_HOME/.config/other.conf")" || return 1
  assert_contains "$out" "Keeping your edited $TEST_HOME/.config/other.conf" || return 1
  # Outside a refresh, copy_config_once is back to copying once: a newer
  # shipped file does not reach even a pristine copy.
  printf 'home=@HOME@\nversion=3\n' > "$TEEUP_CAPS_DIR/tool/config/tool.conf"
  out="$(cap_run tool configure 2>&1)"
  assert_contains "$out" "Already installed: $TEST_HOME/.config/tool.conf" || return 1
  assert_contains "$(cat "$TEST_HOME/.config/tool.conf")" "version=2" || return 1
  cleanup_test_env
}

test_refresh_skips_a_capability_that_is_not_installed() {
  setup
  make_rendering_cap
  local out
  out="$(migration_refresh tool 2>&1)"
  assert_contains "$out" "tool is not installed here; nothing to refresh." || return 1
  [[ ! -e "$TEST_HOME/.config/tool.conf" ]] || { echo "configure ran for a capability that is not installed"; return 1; }
  cleanup_test_env
}

test_new_is_named_from_the_last_commit() {
  setup
  mock_command git 0 "1788000000"
  local file
  file="$(migration_new 2>/dev/null)"
  assert_equals "$TEEUP_MIGRATIONS_DIR/1788000000.sh" "$file" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "git -C $TEEUP_PATH log -1 --format=%ct" || return 1
  assert_contains "$(head -2 "$file")" "Migration 1788000000." || return 1
  bash -n "$file" || { echo "the scaffold must be valid bash"; return 1; }
  file="$(migration_new 2>/dev/null)"
  assert_equals "$TEEUP_MIGRATIONS_DIR/1788000001.sh" "$file" "a second migration on the same commit takes the next second" || return 1
  cleanup_test_env
}

test_new_without_git_history_uses_the_clock_and_dry_run_writes_nothing() {
  setup
  mock_command git 128 ""
  local file out before after stamp
  before="$(date +%s)"
  file="$(migration_new 2>"$TEST_HOME/err")"
  after="$(date +%s)"
  assert_contains "$(cat "$TEST_HOME/err")" "No git history" || return 1
  stamp="${file##*/}"
  stamp="${stamp%.sh}"
  [[ "$stamp" -ge "$before" && "$stamp" -le "$after" ]] || { echo "unexpected name $file"; return 1; }
  rm -f "$file"
  mock_command git 0 "1788000000"
  out="$(DRY_RUN=true migration_new 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would create $TEEUP_MIGRATIONS_DIR/1788000000.sh" || return 1
  [[ ! -e "$TEEUP_MIGRATIONS_DIR/1788000000.sh" ]] || { echo "created in dry run"; return 1; }
  cleanup_test_env
}

echo "lib/migrations.sh"
run_test "list is oldest first and ignores other files" test_list_is_oldest_first_and_ignores_other_files
run_test "pending leaves out applied migrations" test_pending_leaves_out_applied_migrations
run_test "run_pending runs each once, in order, with the library" test_run_pending_runs_each_once_in_order_with_the_library
run_test "a failed migration stops the run and stays pending" test_a_failed_migration_stops_the_run_and_stays_pending
run_test "dry run previews and marks nothing" test_dry_run_previews_and_marks_nothing
run_test "refresh replaces pristine rendered files and keeps edited ones" test_refresh_replaces_pristine_rendered_files_and_keeps_edited_ones
run_test "refresh skips a capability that is not installed" test_refresh_skips_a_capability_that_is_not_installed
run_test "new is named from the last commit" test_new_is_named_from_the_last_commit
run_test "new without git history uses the clock, and dry run writes nothing" test_new_without_git_history_uses_the_clock_and_dry_run_writes_nothing
print_summary
