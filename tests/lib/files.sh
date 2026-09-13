#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false
  SRC="$TEST_HOME/src.conf"
  DEST="$TEST_HOME/.config/tool/tool.conf"
  printf 'shipped=1\n' > "$SRC"
}

test_append_once_is_idempotent() {
  setup
  echo 'export FOO=1' | append_once "$TEST_HOME/.rc" "teeup:foo"
  echo 'export FOO=1' | append_once "$TEST_HOME/.rc" "teeup:foo"
  assert_equals "1" "$(grep -c 'export FOO=1' "$TEST_HOME/.rc")" || return 1
  assert_contains "$(cat "$TEST_HOME/.rc")" "# teeup:foo" || return 1
  cleanup_test_env
}

test_write_managed_file_noops_when_identical() {
  setup
  echo content | write_managed_file "$TEST_HOME/managed" "test"
  local out
  out="$(echo content | write_managed_file "$TEST_HOME/managed" "test")"
  assert_contains "$out" "Already current" || return 1
  cleanup_test_env
}

test_backup_target_moves_and_prints_path() {
  setup
  echo old > "$TEST_HOME/file"
  local backup
  backup="$(backup_target "$TEST_HOME/file")"
  [[ "$backup" == "$TEST_HOME/file.teeup_backup_"* ]] || { echo "bad backup name: $backup"; return 1; }
  assert_file_exists "$backup" || return 1
  [[ ! -e "$TEST_HOME/file" ]] || { echo "original still present"; return 1; }
  cleanup_test_env
}

test_copy_config_once_copies_and_records_sha() {
  setup
  copy_config_once "$SRC" "$DEST"
  assert_file_exists "$DEST" || return 1
  assert_equals "$(file_sha "$SRC")" "$(stock_sha "$DEST")" "recorded sha" || return 1
  cleanup_test_env
}

test_copy_config_once_skips_user_edited_file() {
  setup
  copy_config_once "$SRC" "$DEST"
  printf 'shipped=1\nmine=2\n' > "$DEST"
  printf 'shipped=2\n' > "$SRC"
  copy_config_once "$SRC" "$DEST"
  assert_contains "$(cat "$DEST")" "mine=2" "user edits survive" || return 1
  cleanup_test_env
}

test_copy_config_once_backs_up_foreign_file() {
  setup
  mkdir -p "$(dirname "$DEST")"
  printf 'foreign=1\n' > "$DEST"
  local out
  out="$(copy_config_once "$SRC" "$DEST")"
  assert_contains "$(cat "$DEST")" "shipped=1" || return 1
  ls "$(dirname "$DEST")"/tool.conf.teeup_backup_* >/dev/null || { echo "no backup"; return 1; }
  assert_contains "$out" "foreign=1" "diff of the backup is printed" || return 1
  cleanup_test_env
}

test_copy_config_once_backs_up_a_dangling_symlink() {
  setup
  mkdir -p "$(dirname "$DEST")"
  # What a dotfile manager leaves behind once its store is moved or removed:
  # the link is still there, its target is not. `[[ -e ]]` is false for it, so
  # copy_config_once used to treat it as absent and hand it to `cp`.
  ln -s "$TEST_HOME/store/tool.conf" "$DEST"
  [[ -L "$DEST" && ! -e "$DEST" ]] || { echo "the fixture is not a dangling symlink"; return 1; }
  local out
  out="$(copy_config_once "$SRC" "$DEST" 2>&1)"
  [[ ! -L "$DEST" ]] || { echo "dest is still a symlink"; return 1; }
  assert_equals "shipped=1" "$(cat "$DEST")" || return 1
  assert_equals "$(file_sha "$SRC")" "$(stock_sha "$DEST")" "recorded sha" || return 1
  local backup="" f
  for f in "$(dirname "$DEST")"/tool.conf.teeup_backup_*; do
    [[ -L "$f" ]] && backup="$f"
  done
  [[ -n "$backup" ]] || { echo "the dangling symlink was not backed up: $out"; return 1; }
  assert_equals "$TEST_HOME/store/tool.conf" "$(readlink "$backup")" || return 1
  cleanup_test_env
}

test_copy_config_once_dry_run_touches_nothing() {
  setup
  # shellcheck disable=SC2034
  DRY_RUN=true
  local out
  out="$(copy_config_once "$SRC" "$DEST")"
  [[ ! -e "$DEST" ]] || { echo "dest created in dry run"; return 1; }
  assert_contains "$out" "[DRY-RUN]" || return 1
  cleanup_test_env
}

test_refresh_config_backs_up_and_diffs() {
  setup
  copy_config_once "$SRC" "$DEST"
  printf 'shipped=1\nmine=2\n' > "$DEST"
  local out
  out="$(refresh_config "$SRC" "$DEST")"
  assert_equals "shipped=1" "$(cat "$DEST")" || return 1
  assert_contains "$out" "mine=2" "diff shows what was replaced" || return 1
  cleanup_test_env
}

test_refresh_config_removes_backup_when_unchanged() {
  setup
  copy_config_once "$SRC" "$DEST"
  refresh_config "$SRC" "$DEST" >/dev/null
  if ls "$(dirname "$DEST")"/tool.conf.teeup_backup_* >/dev/null 2>&1; then
    echo "backup left behind although nothing changed"; return 1
  fi
  cleanup_test_env
}

test_refresh_prints_the_backup_path() {
  setup
  printf 'shipped\n' > "$TEST_HOME/src"
  printf 'mine\n' > "$TEST_HOME/dest"
  local out
  out="$(refresh_config "$TEST_HOME/src" "$TEST_HOME/dest" 2>&1)"
  assert_contains "$out" "Backed up $TEST_HOME/dest to" || return 1
  cleanup_test_env
}

echo "lib/files.sh"
run_test "append_once is idempotent" test_append_once_is_idempotent
run_test "write_managed_file noops when identical" test_write_managed_file_noops_when_identical
run_test "backup_target moves and prints path" test_backup_target_moves_and_prints_path
run_test "copy_config_once copies and records sha" test_copy_config_once_copies_and_records_sha
run_test "copy_config_once skips user-edited file" test_copy_config_once_skips_user_edited_file
run_test "copy_config_once backs up foreign file" test_copy_config_once_backs_up_foreign_file
run_test "copy_config_once backs up a dangling symlink" test_copy_config_once_backs_up_a_dangling_symlink
run_test "copy_config_once dry run touches nothing" test_copy_config_once_dry_run_touches_nothing
run_test "refresh_config backs up and diffs" test_refresh_config_backs_up_and_diffs
run_test "refresh_config removes backup when unchanged" test_refresh_config_removes_backup_when_unchanged
run_test "refresh prints the backup path" test_refresh_prints_the_backup_path
print_summary
