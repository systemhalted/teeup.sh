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
  # The ai-split migration's regenerated leaf refresh now runs a capability's
  # configure through cap_run, which calls answers_load; keep it off the
  # checkout's own machines/ (Global Constraints: any test that can load a
  # machine file exports this to a temp dir).
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
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

AI_SPLIT_MIGRATION=1790403216.sh

copy_ai_split_migration() {
  cp "$TEEUP_PATH/migrations/$AI_SPLIT_MIGRATION" "$TEEUP_MIGRATIONS_DIR/$AI_SPLIT_MIGRATION"
}

write_legacy_ai_path() {
  local command="$1"
  mkdir -p "$HOME/.local/bin"
  printf '#!/bin/bash\n%s\necho legacy-%s\n' "$TEEUP_MISE_WRAPPER_MARKER" "$command" > "$HOME/.local/bin/$command"
  chmod +x "$HOME/.local/bin/$command"
}

test_ai_split_migration_maps_complete_legacy_state_and_refreshes_shims() {
  setup
  copy_ai_split_migration
  state_done mark cap-ai
  state_done mark cap-teeup-runtime
  local command leaf
  for command in claude codex gemini copilot opencode; do write_legacy_ai_path "$command"; done
  mkdir -p "$(shims_dir)"
  shim_write ai claude >/dev/null
  assert_contains "$(cat "$(shims_dir)/claude")" "lazy-run ai claude" || return 1

  migration_run "$AI_SPLIT_MIGRATION" >/dev/null
  for leaf in ai-claude ai-codex ai-gemini ai-copilot ai-opencode; do
    state_done check "cap-$leaf" || { echo "$leaf was not migrated"; return 1; }
  done
  state_done check cap-ai || { echo "a complete aggregate must stay installed"; return 1; }
  assert_contains "$(cat "$(shims_dir)/claude")" 'lazy-run ai-claude claude "$@"' || return 1
  assert_file_exists "$MARKS/$AI_SPLIT_MIGRATION" || return 1
  cleanup_test_env
}

# I1 regression: a legacy managed wrapper (the aggregate `ai` capability's
# old configure wrote it) must be rewritten with the leaf's current
# implementation -- the progress line, retry and lazy log the old stub never
# had. A foreign file at the same path (no marker) is not teeup's, and must
# come through byte for byte.
test_ai_split_migration_refreshes_a_legacy_managed_wrapper() {
  setup
  copy_ai_split_migration
  state_done mark cap-ai
  write_legacy_ai_path claude
  local before
  before="$(cat "$HOME/.local/bin/claude")"
  printf '#!/bin/sh\necho native\n' > "$HOME/.local/bin/codex"
  chmod +x "$HOME/.local/bin/codex"

  migration_run "$AI_SPLIT_MIGRATION" >/dev/null

  state_done check cap-ai-claude || { echo "claude was not migrated"; return 1; }
  local after
  after="$(cat "$HOME/.local/bin/claude")"
  [[ "$before" != "$after" ]] || { echo "the legacy stub must be rewritten"; return 1; }
  assert_contains "$after" "Installing Claude Code through mise (first run, can take a minute)..." || return 1
  assert_not_contains "$after" "echo legacy-claude" || return 1

  state_done check cap-ai-codex || { echo "the foreign codex path was not mapped"; return 1; }
  assert_equals "$(printf '#!/bin/sh\necho native\n')" "$(cat "$HOME/.local/bin/codex")" "a foreign command file must stay untouched" || return 1
  cleanup_test_env
}

test_ai_split_migration_clears_an_incomplete_aggregate() {
  setup
  copy_ai_split_migration
  state_done mark cap-ai
  write_legacy_ai_path claude
  mkdir -p "$HOME/.local/bin"
  printf '#!/bin/sh\necho native\n' > "$HOME/.local/bin/codex"
  local out
  out="$(migration_run "$AI_SPLIT_MIGRATION" 2>&1)"
  state_done check cap-ai-claude || { echo "claude path was not mapped"; return 1; }
  state_done check cap-ai-codex || { echo "foreign codex path was not mapped"; return 1; }
  state_done check cap-ai-gemini && { echo "missing gemini was marked"; return 1; }
  state_done check cap-ai && { echo "incomplete aggregate stayed marked"; return 1; }
  assert_contains "$out" "The legacy ai setup is incomplete" || return 1
  assert_contains "$out" "teeup install ai" || return 1
  assert_contains "$(cat "$HOME/.local/bin/codex")" "echo native" || return 1
  cleanup_test_env
}

test_ai_split_migration_dry_run_changes_no_state_or_shim() {
  setup
  copy_ai_split_migration
  state_done mark cap-ai
  state_done mark cap-teeup-runtime
  write_legacy_ai_path claude
  mkdir -p "$(shims_dir)"
  shim_write ai claude >/dev/null
  local before out
  before="$(cat "$(shims_dir)/claude")"
  out="$(DRY_RUN=true migration_run "$AI_SPLIT_MIGRATION" 2>&1)"
  assert_contains "$out" "Would record state: done/cap-ai-claude" || return 1
  assert_contains "$out" "Would clear state: done/cap-ai" || return 1
  state_done check cap-ai-claude && { echo "dry run marked a leaf"; return 1; }
  state_done check cap-ai || { echo "dry run cleared the aggregate"; return 1; }
  assert_equals "$before" "$(cat "$(shims_dir)/claude")" "dry run rewrote a shim" || return 1
  [[ ! -e "$MARKS/$AI_SPLIT_MIGRATION" ]] || { echo "dry run marked the migration"; return 1; }
  cleanup_test_env
}

test_ai_split_migration_tolerates_a_fixture_tree_without_ai() {
  setup
  copy_ai_split_migration
  export TEEUP_CAPS_DIR="$TEST_HOME/fixture-caps"
  mkdir -p "$TEEUP_CAPS_DIR"
  state_done mark cap-ai
  migration_run "$AI_SPLIT_MIGRATION" >/dev/null
  state_done check cap-ai || { echo "a migration for absent capabilities changed fixture state"; return 1; }
  state_done check cap-ai-claude && { echo "fixture gained a nonexistent capability"; return 1; }
  cleanup_test_env
}

# The migration's own leaf check is `-e || -L`, covering a symlink the -e
# alone would miss. A working symlink still resolves, so mise_wrapper_write's
# marker read succeeds and (finding correctly, no marker on line 2) leaves it
# alone; its target is not teeup's to inspect or change.
test_ai_split_migration_marks_a_working_symlink_leaf() {
  setup
  copy_ai_split_migration
  state_done mark cap-ai
  printf '#!/bin/sh\necho real-codex\n' > "$HOME/real-codex"
  chmod +x "$HOME/real-codex"
  mkdir -p "$HOME/.local/bin"
  ln -s "$HOME/real-codex" "$HOME/.local/bin/codex"
  for command in claude gemini copilot opencode; do write_legacy_ai_path "$command"; done

  migration_run "$AI_SPLIT_MIGRATION" >/dev/null

  state_done check cap-ai-codex || { echo "a working symlink leaf was not marked"; return 1; }
  [[ -L "$HOME/.local/bin/codex" ]] || { echo "the symlink was replaced with a regular file"; return 1; }
  assert_equals "$HOME/real-codex" "$(readlink "$HOME/.local/bin/codex")" "a foreign symlink target must stay as it was" || return 1
  cleanup_test_env
}

# A dangling symlink: -e is false (the target is gone) but -L is true, so the
# migration must still count the leaf as set up, and mise_wrapper_write's own
# marker read (which cannot follow the broken link) must leave it alone
# rather than crash the migration.
test_ai_split_migration_marks_a_dangling_symlink_leaf() {
  setup
  copy_ai_split_migration
  state_done mark cap-ai
  mkdir -p "$HOME/.local/bin"
  ln -s "$HOME/.local/bin/no-such-target" "$HOME/.local/bin/gemini"
  for command in claude codex copilot opencode; do write_legacy_ai_path "$command"; done

  migration_run "$AI_SPLIT_MIGRATION" >/dev/null

  state_done check cap-ai-gemini || { echo "a dangling symlink leaf was not marked"; return 1; }
  [[ -L "$HOME/.local/bin/gemini" ]] || { echo "the dangling symlink was replaced"; return 1; }
  [[ ! -e "$HOME/.local/bin/gemini" ]] || { echo "the symlink target must stay missing"; return 1; }
  assert_file_exists "$MARKS/$AI_SPLIT_MIGRATION" "the migration must finish, not crash on the broken link" || return 1
  cleanup_test_env
}

echo "lib/migrations.sh"
# A file whose name is not <epoch>.sh: the glob accepts it, everything else
# must not. It is announced rather than silently ignored, it never appears in
# the list, marking everything applied never writes a marker for it, and
# run_pending never tries to run it. A name with a space is the dangerous
# shape -- it used to word-split into bogus tokens in every one of those
# loops.
test_a_file_that_is_not_a_migration_name_is_skipped_loudly() {
  setup
  make_migration "1700000000.sh" 'echo real'
  make_migration "1700000001 copy.sh" 'echo "should never run"'
  local out
  out="$(migrations_list 2>&1)"
  assert_contains "$out" "1700000000.sh" || return 1
  assert_contains "$out" "Not a migration name" || return 1
  # The list itself, without the warning: the warning names the file on
  # purpose, so it has to be kept out of this check.
  if migrations_list 2>/dev/null | grep -q 'copy'; then
    echo "a file that is not a migration was listed"
    return 1
  fi
  assert_equals "1700000000.sh" "$(migrations_list 2>/dev/null)" || return 1
  assert_equals "1700000000.sh" "$(migrations_pending 2>/dev/null)" || return 1
  migrations_mark_all >/dev/null 2>&1
  assert_file_exists "$MARKS/1700000000.sh" || return 1
  local marks
  marks="$(ls "$MARKS" | tr '\n' ' ')"
  assert_equals "1700000000.sh " "$marks" "only the real migration is marked" || return 1
  cleanup_test_env
}

# run_pending counts what it ran, so its loop has to run in this shell.
test_run_pending_counts_correctly_with_an_odd_name_present() {
  setup
  make_migration "1700000000.sh" 'echo one'
  make_migration "1700000002 two.sh" 'echo two'
  local out
  # stderr carries the "not a migration name" warning, which names the file;
  # stdout is what run_pending itself reports.
  out="$(migrations_run_pending 2>/dev/null)"
  assert_contains "$out" "Applied 1 migration(s)." || return 1
  assert_not_contains "$out" "two" || return 1
  cleanup_test_env
}

run_test "ai split migration maps complete legacy state and refreshes shims" test_ai_split_migration_maps_complete_legacy_state_and_refreshes_shims
run_test "ai split migration refreshes a legacy managed wrapper" test_ai_split_migration_refreshes_a_legacy_managed_wrapper
run_test "ai split migration clears an incomplete aggregate" test_ai_split_migration_clears_an_incomplete_aggregate
run_test "ai split migration dry run changes no state or shim" test_ai_split_migration_dry_run_changes_no_state_or_shim
run_test "ai split migration tolerates a fixture tree without ai" test_ai_split_migration_tolerates_a_fixture_tree_without_ai
run_test "ai split migration marks a working symlink leaf" test_ai_split_migration_marks_a_working_symlink_leaf
run_test "ai split migration marks a dangling symlink leaf" test_ai_split_migration_marks_a_dangling_symlink_leaf
run_test "a file that is not a migration name is skipped loudly" test_a_file_that_is_not_a_migration_name_is_skipped_loudly
run_test "run_pending counts correctly with an odd name present" test_run_pending_counts_correctly_with_an_odd_name_present
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
