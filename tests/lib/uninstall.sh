#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# Every test runs in the harness's throwaway HOME with a fixture capability
# tree, a machines directory of its own (TEEUP_MACHINES_DIR otherwise
# defaults to the checkout's machines/, which no test may write or read), and
# chezmoi hidden, so migrate_path_is_safe's chezmoi gate answers the same on
# every runner. HOME_P is $TEST_HOME's physical form: uninstall_rm resolves
# paths, and on macOS /var/folders is /private/var/folders.
setup() {
  setup_test_env
  mock_macos_base
  hide_host_commands chezmoi
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_CAPS_DIR" "$TEEUP_MACHINES_DIR"
  export TEEUP_NO_GUM=1
  source "$TEEUP_PATH/lib/all.sh"
  # shellcheck disable=SC2034
  DRY_RUN=false
  uninstall_report_reset
  _UNINSTALL_ASK=false
  _UNINSTALL_PACKAGES=false
  _UNINSTALL_IDENTITY=false
  _UNINSTALL_GONE=" "
  HOME_P="$(cd "$TEST_HOME" && pwd -P)"
}

# make_cap <name> <tier> [requires] [packages] [casks]
make_cap() {
  local name="$1" tier="$2" requires="${3:-}" pkgs="${4:-}" casks="${5:-}"
  local dir="$TEEUP_CAPS_DIR/$name"
  mkdir -p "$dir"
  printf 'summary="Fixture %s"\ngroup=system\ntier=%s\nrequires="%s"\nprovides=""\npackages="%s"\ncasks="%s"\ninteractive=false\n' \
    "$name" "$tier" "$requires" "$pkgs" "$casks" > "$dir/capability"
  printf '#!/usr/bin/env bash\necho "install:%s"\n' "$name" > "$dir/install"
  printf '#!/usr/bin/env bash\necho "configure:%s"\n' "$name" > "$dir/configure"
  chmod +x "$dir/install" "$dir/configure"
}

# run_fix <command>: what the user would do with a printed fix, in their
# shell: zsh when the machine has it (every CI runner does), else bash.
run_fix() {
  if have zsh; then zsh -c "$1"; else bash -c "$1"; fi
}

test_rm_removes_a_file_a_directory_and_a_link_without_following_it() {
  setup
  mkdir -p "$TEST_HOME/d/sub" "$TEST_HOME/keep"
  printf 'x\n' > "$TEST_HOME/f"
  printf 'x\n' > "$TEST_HOME/d/sub/g"
  printf 'precious\n' > "$TEST_HOME/keep/target"
  ln -s "$TEST_HOME/keep/target" "$TEST_HOME/link"
  uninstall_rm "$TEST_HOME/f" "a file" >/dev/null || return 1
  uninstall_rm "$TEST_HOME/d" "a directory" >/dev/null || return 1
  uninstall_rm "$TEST_HOME/link" "a link" >/dev/null || return 1
  [[ ! -e "$TEST_HOME/f" && ! -e "$TEST_HOME/d" && ! -L "$TEST_HOME/link" ]] || { echo "all three must be gone"; return 1; }
  assert_file_exists "$TEST_HOME/keep/target" "a link is removed, never what it points to" || return 1
  assert_contains "$_UNINSTALL_REMOVED" "a directory" || return 1
  uninstall_rm "$TEST_HOME/nothing-here" "absent" || { echo "nothing there is not a problem"; return 1; }
  uninstall_clean || { echo "nothing was refused"; return 1; }
  cleanup_test_env
}

# A path outside $HOME and one inside a git checkout are refused, and the
# command the note prints really does remove them.
test_rm_refuses_outside_home_and_in_a_git_checkout_with_a_fix_that_works() {
  setup
  local outside="$TEST_HOME/outside dir \$x" repo="$TEST_HOME/home/repo" fix
  mkdir -p "$outside" "$repo/.git" "$TEST_HOME/home"
  printf 'x\n' > "$repo/tracked"
  export HOME="$TEST_HOME/home"
  uninstall_rm "$outside" "outside" >/dev/null 2>&1 && { echo "outside HOME must be refused"; return 1; }
  uninstall_rm "$repo/tracked" "in a repo" >/dev/null 2>&1 && { echo "a git checkout must be refused"; return 1; }
  [[ -d "$outside" && -f "$repo/tracked" ]] || { echo "nothing may be deleted"; return 1; }
  assert_contains "$_UNINSTALL_REFUSED" "outside" || return 1
  while IFS= read -r fix; do
    [[ -n "$fix" ]] || continue
    run_fix "${fix##*: }" || { echo "the printed fix failed: $fix"; return 1; }
  done <<EOF2
$_UNINSTALL_REFUSED
EOF2
  [[ ! -e "$outside" && ! -e "$repo/tracked" ]] || { echo "the printed fixes must remove both"; return 1; }
  cleanup_test_env
}

test_rm_dry_run_deletes_nothing_and_claims_nothing() {
  setup
  printf 'x\n' > "$TEST_HOME/f"
  local out
  out="$(DRY_RUN=true uninstall_rm "$TEST_HOME/f" "a file" 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: rm -f $HOME_P/f" || return 1
  assert_not_contains "$out" "Removed" || return 1
  assert_file_exists "$TEST_HOME/f" || return 1
  DRY_RUN=true uninstall_rm "$TEST_HOME/f" "a file" >/dev/null
  out="$(DRY_RUN=true uninstall_summary)"
  assert_contains "$out" "Would remove (dry run; nothing was changed):" || return 1
  cleanup_test_env
}

test_summary_lists_each_column_and_fails_on_a_problem() {
  setup
  local out rc=0
  out="$(uninstall_summary)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "Nothing of teeup's was left to remove." || return 1
  uninstall_note removed "gone thing"
  uninstall_note kept "kept thing"
  out="$(uninstall_summary)" || rc=$?
  assert_success "$rc" "kept is not a problem" || return 1
  assert_contains "$out" "  - kept thing" || return 1
  uninstall_note refused "refused thing"
  rc=0
  out="$(uninstall_summary)" || rc=$?
  assert_failure "$rc" "a refusal makes the run fail" || return 1
  assert_contains "$out" "  - refused thing" || return 1
  cleanup_test_env
}

test_caps_lists_installed_capabilities_dependents_first() {
  setup
  make_cap base core
  make_cap mid core base
  make_cap top lazy mid
  make_cap never lazy
  state_done mark cap-base
  state_done mark cap-mid
  state_done mark cap-top
  assert_equals "top mid base" "$(uninstall_caps | tr '\n' ' ' | sed 's/ $//')" || return 1
  cleanup_test_env
}

test_offer_restore_asks_and_puts_the_earlier_copy_back() {
  setup
  printf 'teeup\n' > "$TEST_HOME/conf"
  printf 'mine\n' > "$TEST_HOME/conf.teeup_backup_20260101000000"
  _UNINSTALL_ASK=true
  uninstall_offer_restore "$TEST_HOME/conf" >/dev/null 2>&1 <<< "y" || { echo "a yes restores"; return 1; }
  assert_equals "mine" "$(cat "$TEST_HOME/conf")" || return 1
  [[ ! -e "$TEST_HOME/conf.teeup_backup_20260101000000" ]] || { echo "the backup was moved, not copied"; return 1; }
  cleanup_test_env
}

# Without a terminal nothing is asked; the note carries the mv that puts the
# backup back, and that command works.
test_offer_restore_without_a_terminal_notes_a_command_that_works() {
  setup
  local dir="$TEST_HOME/it's a \$dir" fix
  mkdir -p "$dir"
  printf 'teeup\n' > "$dir/conf"
  printf 'mine\n' > "$dir/conf.teeup_backup_20260101000000"
  uninstall_offer_restore "$dir/conf" >/dev/null 2>&1 && { echo "nothing was restored"; return 1; }
  assert_equals "teeup" "$(cat "$dir/conf")" || return 1
  fix="${_UNINSTALL_KEPT##*: }"
  rm -f "$dir/conf"
  run_fix "$fix" || { echo "the printed mv failed: $fix"; return 1; }
  assert_equals "mine" "$(cat "$dir/conf")" || return 1
  cleanup_test_env
}

echo "lib/uninstall.sh"
run_test "rm removes a file, a directory and a link without following it" test_rm_removes_a_file_a_directory_and_a_link_without_following_it
run_test "rm refuses outside HOME and in a git checkout, with a fix that works" test_rm_refuses_outside_home_and_in_a_git_checkout_with_a_fix_that_works
run_test "rm dry run deletes nothing and claims nothing" test_rm_dry_run_deletes_nothing_and_claims_nothing
run_test "summary lists each column and fails on a problem" test_summary_lists_each_column_and_fails_on_a_problem
run_test "caps lists installed capabilities dependents first" test_caps_lists_installed_capabilities_dependents_first
run_test "offer_restore asks and puts the earlier copy back" test_offer_restore_asks_and_puts_the_earlier_copy_back
run_test "offer_restore without a terminal notes a command that works" test_offer_restore_without_a_terminal_notes_a_command_that_works
print_summary
