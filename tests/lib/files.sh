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

# mode_of <path>: same GNU-then-BSD stat probe as _file_mode in lib/files.sh
# and file_mode in capabilities/ssh/configure.
mode_of() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || true
}

# Review of Task 1: write_managed_file writes through mktemp (0600) and mv's
# the result into place, which used to carry mktemp's mode onto the
# destination -- narrowing a 0644 editor settings file to 0600 on its very
# first rewrite, a permissions diff in whatever dotfiles repo tracks it. An
# existing file now keeps its own mode across a rewrite.
test_write_managed_file_keeps_an_existing_mode() {
  setup
  local f="$TEST_HOME/existing.conf"
  printf 'old\n' > "$f"
  chmod 644 "$f"
  echo new | write_managed_file "$f" "test" >/dev/null
  assert_equals "644" "$(mode_of "$f")" "a 644 file keeps 644 after a rewrite" || return 1
  chmod 600 "$f"
  echo newer | write_managed_file "$f" "test" >/dev/null
  assert_equals "600" "$(mode_of "$f")" "a 600 file keeps 600 after a rewrite" || return 1
  cleanup_test_env
}

test_write_managed_file_new_file_keeps_todays_behavior() {
  setup
  local f="$TEST_HOME/brand-new.conf"
  echo content | write_managed_file "$f" "test" >/dev/null
  # Nothing existed to preserve a mode from, so the file is left exactly as
  # mktemp -> mv always made it: today's behaviour, unmodified by this fix.
  assert_equals "600" "$(mode_of "$f")" "a new file's mode is unchanged from today" || return 1
  cleanup_test_env
}

test_write_managed_file_dry_run_changes_no_mode() {
  setup
  local f="$TEST_HOME/existing.conf"
  printf 'old\n' > "$f"
  chmod 644 "$f"
  DRY_RUN=true
  echo new | write_managed_file "$f" "test" >/dev/null
  assert_equals "644" "$(mode_of "$f")" "a dry run touches no mode" || return 1
  assert_equals "old" "$(cat "$f")" "a dry run writes nothing" || return 1
  cleanup_test_env
}

# M11: a non-writable existing file (mode 0444) is treated like a symlink --
# `mv` onto the path would still succeed (only the directory's permissions
# govern a rename), silently rewriting the file and then restoring 0444,
# which usually contradicts why it was made read-only in the first place.
test_write_managed_file_leaves_a_non_writable_file_alone() {
  setup
  local f="$TEST_HOME/readonly.conf"
  printf 'old\n' > "$f"
  chmod 444 "$f"
  local rc=0 out
  out="$(echo new | write_managed_file "$f" "test" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$f is not writable; teeup leaves it alone." || return 1
  assert_equals "old" "$(cat "$f")" "the file's content is untouched" || return 1
  assert_equals "444" "$(mode_of "$f")" "the file's mode is untouched" || return 1
  chmod 644 "$f"
  cleanup_test_env
}

# M1: a read-only directory with no file there yet used to reach `mv`
# directly (the file-not-writable guard above only fires when the file
# exists), producing a raw `mv: cannot move ... Permission denied` with no
# teeup message.
test_write_managed_file_leaves_a_non_writable_directory_alone() {
  setup
  local d="$TEST_HOME/readonly-dir" f
  mkdir -p "$d"
  f="$d/newfile"
  chmod 555 "$d"
  local rc=0 out
  out="$(echo new | write_managed_file "$f" "test" 2>&1)" || rc=$?
  chmod 755 "$d"
  assert_failure "$rc" || return 1
  assert_contains "$out" "$d is not writable; teeup leaves $f alone." || return 1
  assert_not_contains "$out" "mv:" "a raw mv error must not reach the user" || return 1
  [[ ! -e "$f" ]] || { echo "must not have written the file"; return 1; }
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

# F4: a capability that renders before copying (zsh, git) passes a temp file
# as <src>; the dry-run message must name the shipped source it stands in
# for, not the temp path the user cannot make sense of.
test_copy_config_once_dry_run_names_the_display_src_when_installing_fresh() {
  setup
  # shellcheck disable=SC2034
  DRY_RUN=true
  local out
  out="$(copy_config_once "$SRC" "$DEST" "$TEEUP_PATH/capabilities/zsh/home/.zshenv")"
  assert_contains "$out" "Would install $DEST from $TEEUP_PATH/capabilities/zsh/home/.zshenv" || return 1
  assert_not_contains "$out" "$SRC" "the temp source path must not appear" || return 1
  cleanup_test_env
}

test_copy_config_once_dry_run_names_the_display_src_for_a_foreign_file() {
  setup
  mkdir -p "$(dirname "$DEST")"
  printf 'foreign=1\n' > "$DEST"
  # shellcheck disable=SC2034
  DRY_RUN=true
  local out
  out="$(copy_config_once "$SRC" "$DEST" "$TEEUP_PATH/capabilities/zsh/home/.zshenv")"
  assert_contains "$out" "Would back up foreign $DEST and install $TEEUP_PATH/capabilities/zsh/home/.zshenv" || return 1
  assert_not_contains "$out" "$SRC" "the temp source path must not appear" || return 1
  cleanup_test_env
}

test_copy_config_once_display_src_defaults_to_src() {
  setup
  # shellcheck disable=SC2034
  DRY_RUN=true
  local out
  out="$(copy_config_once "$SRC" "$DEST")"
  assert_contains "$out" "Would install $DEST from $SRC" "omitting display_src keeps today's wording" || return 1
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

test_replace_literal_is_literal_and_repeats() {
  setup
  # shellcheck disable=SC2088  # the tilde is a literal token here, not a path
  assert_equals 'x /p&q|r\s/a /p&q|r\s/b' "$(replace_literal 'x ~/.config/git/a ~/.config/git/b' '~/.config/git' '/p&q|r\s')" || return 1
  assert_equals '[ -r /tmp/we\`ird\ \$d/env ] && . /tmp/we\`ird\ \$d/env' "$(replace_literal '[ -r ${XDG_CONFIG_HOME:-$HOME/.config}/teeup/env ] && . ${XDG_CONFIG_HOME:-$HOME/.config}/teeup/env' '${XDG_CONFIG_HOME:-$HOME/.config}/teeup/env' '/tmp/we\`ird\ \$d/env')" || return 1
  assert_equals 'untouched' "$(replace_literal 'untouched' 'missing' 'x')" || return 1
  assert_equals 'abc' "$(replace_literal 'abc' '' 'x')" "empty token leaves text alone" || return 1
  cleanup_test_env
}

test_config_is_pristine_follows_the_stock_record() {
  setup
  config_is_pristine "$DEST" && { echo "a missing file is not pristine"; return 1; }
  copy_config_once "$SRC" "$DEST" >/dev/null
  config_is_pristine "$DEST" || { echo "a fresh copy is pristine"; return 1; }
  printf 'shipped=1\nmine=2\n' > "$DEST"
  config_is_pristine "$DEST" && { echo "an edited file is not pristine"; return 1; }
  printf 'unrecorded\n' > "$TEST_HOME/other"
  config_is_pristine "$TEST_HOME/other" && { echo "a file with no record is not pristine"; return 1; }
  ln -s "$SRC" "$TEST_HOME/link"
  stock_record "$TEST_HOME/link" "$(file_sha "$SRC")"
  config_is_pristine "$TEST_HOME/link" && { echo "a symlink is never pristine"; return 1; }
  cleanup_test_env
}

test_write_config_region_keeps_a_pristine_file_pristine() {
  setup
  # A directory with a space, an ampersand, a quote and a dollar sign: the
  # stock record path is derived from it.
  DEST="$TEST_HOME/.config/it's a & \$dir/tool.conf"
  copy_config_once "$SRC" "$DEST" >/dev/null
  printf 'shipped=1\n# managed region rewritten\n' | write_config_region "$DEST" "palette" >/dev/null
  assert_equals "$(printf 'shipped=1\n# managed region rewritten')" "$(cat "$DEST")" || return 1
  config_is_pristine "$DEST" || { echo "teeup's own rewrite must not read as a user edit"; return 1; }
  assert_contains "$(copy_config_once "$SRC" "$DEST")" "Already installed: $DEST" || return 1
  cleanup_test_env
}

test_write_config_region_leaves_an_edited_file_edited() {
  setup
  copy_config_once "$SRC" "$DEST" >/dev/null
  printf 'shipped=1\nmine=2\n' > "$DEST"
  local before
  before="$(stock_sha "$DEST")"
  printf 'shipped=1\nmine=2\n# region\n' | write_config_region "$DEST" "palette" >/dev/null
  assert_equals "$(printf 'shipped=1\nmine=2\n# region')" "$(cat "$DEST")" || return 1
  assert_equals "$before" "$(stock_sha "$DEST")" "the record of an edited file is kept" || return 1
  assert_contains "$(copy_config_once "$SRC" "$DEST")" "Keeping your edited $DEST" || return 1
  cleanup_test_env
}

# A dest the user made read-only: write_managed_file refuses it, and the
# recorded checksum must NOT move. Re-recording there would hash the OLD
# contents as "what teeup shipped", so the next run would read a file the
# user edited as pristine and overwrite it.
test_write_config_region_keeps_the_record_when_the_write_is_refused() {
  setup
  copy_config_once "$SRC" "$DEST" >/dev/null
  local before rc=0 out
  before="$(stock_sha "$DEST")"
  chmod 0444 "$DEST"
  out="$(printf 'shipped=1\n# region\n' | write_config_region "$DEST" "palette" 2>&1)" || rc=$?
  chmod 0644 "$DEST"
  assert_failure "$rc" || return 1
  assert_contains "$out" "is not writable" || return 1
  assert_equals "$before" "$(stock_sha "$DEST")" "a refused write must not re-record" || return 1
  assert_equals "$(printf 'shipped=1')" "$(cat "$DEST")" || return 1
  cleanup_test_env
}

# The write succeeds but the state directory will not take the record: the
# user gets teeup's warning, not a raw shell error, and the file is still
# written. The record stays stale, so the file reads as edited from then on --
# the safe direction, and the warning says so.
test_write_config_region_warns_when_the_record_cannot_be_written() {
  setup
  copy_config_once "$SRC" "$DEST" >/dev/null
  local record rc=0 out
  # The record file itself, not its directory: truncating a file that already
  # exists needs the file's own permission, not the directory's.
  record="$(_stock_record_path "$DEST")"
  chmod 0444 "$record"
  out="$(printf 'shipped=1\n# region\n' | write_config_region "$DEST" "palette" 2>&1)" || rc=$?
  chmod 0644 "$record"
  assert_success "$rc" "the file was written, so the caller is told so" || return 1
  assert_contains "$out" "Could not record the shipped checksum" || return 1
  if printf '%s\n' "$out" | grep -qi 'permission denied'; then
    echo "a raw shell error reached the user"
    return 1
  fi
  assert_equals "$(printf 'shipped=1\n# region')" "$(cat "$DEST")" || return 1
  cleanup_test_env
}

test_write_config_region_refuses_a_symlink_and_dry_run() {
  setup
  mkdir -p "$TEST_HOME/store"
  printf 'managed elsewhere\n' > "$TEST_HOME/store/tool.conf"
  mkdir -p "$(dirname "$DEST")"
  ln -s "$TEST_HOME/store/tool.conf" "$DEST"
  local rc=0 out
  out="$(printf 'new\n' | write_config_region "$DEST" "palette" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$DEST is a symlink" || return 1
  [[ -L "$DEST" ]] || { echo "the link was replaced"; return 1; }
  assert_equals "managed elsewhere" "$(cat "$TEST_HOME/store/tool.conf")" || return 1
  rm -f "$DEST"
  copy_config_once "$SRC" "$DEST" >/dev/null
  out="$(printf 'new\n' | DRY_RUN=true write_config_region "$DEST" "palette")"
  assert_contains "$out" "[DRY-RUN] Would write $DEST (palette)" || return 1
  assert_equals "shipped=1" "$(cat "$DEST")" || return 1
  assert_equals "$(file_sha "$SRC")" "$(stock_sha "$DEST")" || return 1
  cleanup_test_env
}

test_refresh_if_pristine_replaces_only_an_unedited_file() {
  setup
  copy_config_once "$SRC" "$DEST" >/dev/null
  printf 'shipped=2\n' > "$TEST_HOME/src2"
  local out rc=0
  out="$(refresh_if_pristine "$TEST_HOME/src2" "$DEST")"
  assert_contains "$out" "Refreshed $DEST" || return 1
  assert_equals "shipped=2" "$(cat "$DEST")" || return 1
  config_is_pristine "$DEST" || { echo "the record follows the refresh"; return 1; }
  printf 'shipped=2\nmine=3\n' > "$DEST"
  printf 'shipped=3\n' > "$TEST_HOME/src3"
  out="$(refresh_if_pristine "$TEST_HOME/src3" "$DEST")" || rc=$?
  assert_failure "$rc" "an edited file is reported, so the migration can patch it" || return 1
  assert_contains "$out" "Keeping your edited $DEST" || return 1
  assert_equals "$(printf 'shipped=2\nmine=3')" "$(cat "$DEST")" || return 1
  rm -f "$DEST"
  refresh_if_pristine "$TEST_HOME/src3" "$DEST" >/dev/null
  assert_equals "shipped=3" "$(cat "$DEST")" "a missing file is installed" || return 1
  cleanup_test_env
}

test_refresh_if_pristine_dry_run_changes_nothing() {
  setup
  copy_config_once "$SRC" "$DEST" >/dev/null
  printf 'shipped=2\n' > "$TEST_HOME/src2"
  local out
  out="$(DRY_RUN=true refresh_if_pristine "$TEST_HOME/src2" "$DEST")"
  assert_contains "$out" "[DRY-RUN] Would refresh $DEST from $TEST_HOME/src2" || return 1
  assert_equals "shipped=1" "$(cat "$DEST")" || return 1
  cleanup_test_env
}

test_backup_copy_keeps_the_original_in_place() {
  setup
  printf 'mine\n' > "$TEST_HOME/file"
  local backup
  backup="$(backup_copy "$TEST_HOME/file" 2>/dev/null)"
  [[ "$backup" == "$TEST_HOME/file.teeup_backup_"* ]] || { echo "bad backup name: $backup"; return 1; }
  assert_equals "mine" "$(cat "$backup")" || return 1
  assert_equals "mine" "$(cat "$TEST_HOME/file")" || return 1
  cleanup_test_env
}

test_two_backups_of_the_same_file_within_one_second_both_survive() {
  setup
  printf 'first\n' > "$TEST_HOME/file"
  local first second
  first="$(backup_copy "$TEST_HOME/file" 2>/dev/null)"
  printf 'second\n' > "$TEST_HOME/file"
  second="$(backup_copy "$TEST_HOME/file" 2>/dev/null)"
  [[ "$first" != "$second" ]] || { echo "the second call reused the first's name: $first"; return 1; }
  assert_equals "first" "$(cat "$first")" "the first backup must not be overwritten by the second" || return 1
  assert_equals "second" "$(cat "$second")" || return 1
  cleanup_test_env
}

echo "lib/files.sh"
run_test "append_once is idempotent" test_append_once_is_idempotent
run_test "write_managed_file noops when identical" test_write_managed_file_noops_when_identical
run_test "write_managed_file keeps an existing mode" test_write_managed_file_keeps_an_existing_mode
run_test "write_managed_file new file keeps today's behavior" test_write_managed_file_new_file_keeps_todays_behavior
run_test "write_managed_file dry run changes no mode" test_write_managed_file_dry_run_changes_no_mode
run_test "write_managed_file leaves a non-writable file alone" test_write_managed_file_leaves_a_non_writable_file_alone
run_test "write_managed_file leaves a non-writable directory alone" test_write_managed_file_leaves_a_non_writable_directory_alone
run_test "backup_target moves and prints path" test_backup_target_moves_and_prints_path
run_test "copy_config_once copies and records sha" test_copy_config_once_copies_and_records_sha
run_test "copy_config_once skips user-edited file" test_copy_config_once_skips_user_edited_file
run_test "copy_config_once backs up foreign file" test_copy_config_once_backs_up_foreign_file
run_test "copy_config_once backs up a dangling symlink" test_copy_config_once_backs_up_a_dangling_symlink
run_test "copy_config_once dry run touches nothing" test_copy_config_once_dry_run_touches_nothing
run_test "copy_config_once dry run names display_src when installing fresh" test_copy_config_once_dry_run_names_the_display_src_when_installing_fresh
run_test "copy_config_once dry run names display_src for a foreign file" test_copy_config_once_dry_run_names_the_display_src_for_a_foreign_file
run_test "copy_config_once display_src defaults to src" test_copy_config_once_display_src_defaults_to_src
run_test "refresh_config backs up and diffs" test_refresh_config_backs_up_and_diffs
run_test "refresh_config removes backup when unchanged" test_refresh_config_removes_backup_when_unchanged
run_test "refresh prints the backup path" test_refresh_prints_the_backup_path
run_test "config_is_pristine follows the stock record" test_config_is_pristine_follows_the_stock_record
run_test "write_config_region keeps a pristine file pristine" test_write_config_region_keeps_a_pristine_file_pristine
run_test "write_config_region leaves an edited file edited" test_write_config_region_leaves_an_edited_file_edited
run_test "write_config_region keeps the record when the write is refused" test_write_config_region_keeps_the_record_when_the_write_is_refused
run_test "write_config_region warns when the record cannot be written" test_write_config_region_warns_when_the_record_cannot_be_written
run_test "write_config_region refuses a symlink, and dry run" test_write_config_region_refuses_a_symlink_and_dry_run
run_test "refresh_if_pristine replaces only an unedited file" test_refresh_if_pristine_replaces_only_an_unedited_file
run_test "refresh_if_pristine dry run changes nothing" test_refresh_if_pristine_dry_run_changes_nothing
run_test "backup_copy keeps the original in place" test_backup_copy_keeps_the_original_in_place
run_test "two backups of the same file within one second both survive" test_two_backups_of_the_same_file_within_one_second_both_survive
run_test "replace_literal is literal and repeats" test_replace_literal_is_literal_and_repeats
print_summary
