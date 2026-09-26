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
# Locals are named away from the reserved capability metadata keys (summary
# group tier requires provides packages casks apps interactive
# package_commands): cap_meta_get sources the capability file in a subshell
# that still sees a caller's locals, so a fixture builder using those names
# is exactly the trap that bit the first cap_remove.
make_cap() {
  local name="$1" cap_tier="$2" cap_requires="${3:-}" pkgs="${4:-}" cap_casks="${5:-}"
  local dir="$TEEUP_CAPS_DIR/$name"
  mkdir -p "$dir"
  printf 'summary="Fixture %s"\ngroup=system\ntier=%s\nrequires="%s"\nprovides=""\npackages="%s"\ncasks="%s"\ninteractive=false\n' \
    "$name" "$cap_tier" "$cap_requires" "$pkgs" "$cap_casks" > "$dir/capability"
  printf '#!/usr/bin/env bash\necho "install:%s"\n' "$name" > "$dir/install"
  printf '#!/usr/bin/env bash\necho "configure:%s"\n' "$name" > "$dir/configure"
  chmod +x "$dir/install" "$dir/configure"
}

# run_fix <command>: what the user would do with a printed fix, in their
# shell: zsh when the machine has it (every CI runner does), else bash. -f:
# without it zsh sources ~/.zshenv first, teeup's own shell layer, in the
# middle of its removal.
run_fix() {
  if have zsh; then zsh -f -c "$1"; else bash -c "$1"; fi
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

# Mirrors the live ai bundle: one capability requiring five leaves that all
# require a shared base (ai requires ai-claude..ai-opencode, each of which
# requires mise). The bundle must come out before every leaf, and every leaf
# before the base each of them requires.
test_caps_orders_a_bundle_before_its_leaves_and_leaves_before_their_shared_base() {
  setup
  make_cap base core
  make_cap leaf1 lazy base
  make_cap leaf2 lazy base
  make_cap leaf3 lazy base
  make_cap leaf4 lazy base
  make_cap leaf5 lazy base
  make_cap bundle lazy "leaf1 leaf2 leaf3 leaf4 leaf5"
  state_done mark cap-base
  state_done mark cap-leaf1
  state_done mark cap-leaf2
  state_done mark cap-leaf3
  state_done mark cap-leaf4
  state_done mark cap-leaf5
  state_done mark cap-bundle
  local out leaf bundle_pos base_pos leaf_pos
  out="$(uninstall_caps)"
  bundle_pos="$(grep -n -x bundle <<<"$out" | cut -d: -f1)"
  base_pos="$(grep -n -x base <<<"$out" | cut -d: -f1)"
  [[ -n "$bundle_pos" ]] || { echo "the bundle must be listed"; return 1; }
  [[ -n "$base_pos" ]] || { echo "the base must be listed"; return 1; }
  for leaf in leaf1 leaf2 leaf3 leaf4 leaf5; do
    leaf_pos="$(grep -n -x "$leaf" <<<"$out" | cut -d: -f1)"
    [[ -n "$leaf_pos" ]] || { echo "$leaf must be listed"; return 1; }
    [[ "$bundle_pos" -lt "$leaf_pos" ]] || { echo "the bundle must come before $leaf"; return 1; }
    [[ "$leaf_pos" -lt "$base_pos" ]] || { echo "$leaf must come before the shared base"; return 1; }
  done
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

# zsh_home: the three home files exactly as `teeup configure zsh` leaves them,
# rendered and stock-recorded, from the real capability in the checkout.
# The checkout is only read; everything written lands under $TEST_HOME.
zsh_home() {
  TEEUP_CAPS_DIR="$TEEUP_PATH/capabilities" cap_run zsh configure >/dev/null 2>&1
  ZH="${ZDOTDIR:-$HOME}"
}

test_shell_strips_teeups_lines_from_an_edited_zshrc_and_keeps_the_users() {
  setup
  export TEEUP_CONFIG_DIR="$TEST_HOME/con fig \$x"
  zsh_home
  printf 'export MINE=1\n' >> "$ZH/.zshrc"
  uninstall_shell >/dev/null 2>&1
  assert_contains "$(cat "$ZH/.zshrc")" "export MINE=1" || return 1
  assert_contains "$(cat "$ZH/.zshrc")" ": # Disabled by teeup (teeup uninstall):" || return 1
  uninstall_shell_live "$ZH/.zshrc" && { echo "a live teeup line is left"; return 1; }
  if have zsh; then zsh -f -n "$ZH/.zshrc" || { echo "zsh cannot parse the result"; return 1; }; fi
  [[ -n "$(uninstall_newest_backup "$ZH/.zshrc")" ]] || { echo "a copy of the file as it was must be beside it"; return 1; }
  uninstall_clean || { echo "nothing was refused: $_UNINSTALL_REFUSED$_UNINSTALL_FAILED"; return 1; }
  cleanup_test_env
}

# Pristine: .zshenv and .zprofile go; .zshrc is replaced, never removed, and
# the replacement sources an edited local.zsh so the user's own lines load.
test_shell_replaces_a_pristine_zshrc_and_removes_the_other_two() {
  setup
  zsh_home
  printf 'export LOCAL=1\n' >> "$(user_config_dir)/zsh/local.zsh"
  uninstall_shell >/dev/null 2>&1
  [[ ! -e "$ZH/.zshenv" && ! -e "$ZH/.zprofile" ]] || { echo "pristine .zshenv and .zprofile go"; return 1; }
  assert_file_exists "$ZH/.zshrc" "a .zshrc must always be left" || return 1
  uninstall_shell_live "$ZH/.zshrc" && { echo "the new .zshrc has a teeup line"; return 1; }
  assert_contains "$(cat "$ZH/.zshrc")" "zsh/local.zsh" || return 1
  if have zsh; then
    assert_equals "1" "$(zsh -f -c ". $(printf '%q' "$ZH/.zshrc"); echo \$LOCAL")" "the new .zshrc loads local.zsh" || return 1
  fi
  cleanup_test_env
}

test_shell_refuses_a_symlinked_zshrc_and_writes_nothing() {
  setup
  zsh_home
  mkdir -p "$TEST_HOME/dotfiles/.git"
  cp "$ZH/.zshrc" "$TEST_HOME/dotfiles/zshrc"
  rm -f "$ZH/.zshrc"
  ln -s "$TEST_HOME/dotfiles/zshrc" "$ZH/.zshrc"
  local before
  before="$(cat "$TEST_HOME/dotfiles/zshrc")"
  uninstall_shell >/dev/null 2>&1
  [[ -L "$ZH/.zshrc" ]] || { echo "the link must stay a link"; return 1; }
  assert_equals "$before" "$(cat "$TEST_HOME/dotfiles/zshrc")" "nothing is written through the link" || return 1
  assert_contains "$_UNINSTALL_REFUSED" "$ZH/.zshrc is a symlink" || return 1
  cleanup_test_env
}

test_shell_honours_zdotdir_and_refuses_one_inside_a_git_checkout() {
  setup
  export ZDOTDIR="$TEST_HOME/.config/zsh"
  zsh_home
  printf 'export MINE=1\n' >> "$ZDOTDIR/.zshrc"
  uninstall_shell >/dev/null 2>&1
  uninstall_shell_live "$ZDOTDIR/.zshrc" && { echo "ZDOTDIR's .zshrc was not handled"; return 1; }
  cleanup_test_env
  setup
  export ZDOTDIR="$TEST_HOME/dots/zsh"
  mkdir -p "$TEST_HOME/dots/.git"
  zsh_home
  printf 'export MINE=1\n' >> "$ZDOTDIR/.zshrc"
  uninstall_shell >/dev/null 2>&1
  uninstall_shell_live "$ZDOTDIR/.zshrc" || { echo "a file in a git checkout must not be edited"; return 1; }
  assert_contains "$_UNINSTALL_REFUSED" "is inside a git checkout" || return 1
  cleanup_test_env
}

test_shell_dry_run_changes_nothing() {
  setup
  zsh_home
  printf 'export MINE=1\n' >> "$ZH/.zshrc"
  local before after out
  before="$(ls -l "$ZH/.zshenv" "$ZH/.zprofile" "$ZH/.zshrc"; ls -A "$ZH"; cat "$ZH/.zshrc")"
  out="$(DRY_RUN=true uninstall_shell 2>&1)"
  after="$(ls -l "$ZH/.zshenv" "$ZH/.zprofile" "$ZH/.zshrc"; ls -A "$ZH"; cat "$ZH/.zshrc")"
  assert_equals "$before" "$after" || return 1
  assert_contains "$out" "[DRY-RUN]" || return 1
  cleanup_test_env
}

# The package manager stays, but the shell layer that put it on PATH goes.
# The printed command must put it back, into the .zprofile zsh reads.
test_path_hint_prints_a_command_that_works() {
  setup
  export ZDOTDIR="$TEST_HOME/z dot"
  mkdir -p "$ZDOTDIR" "$TEEUP_PKG_PREFIX/bin"
  printf '#!/bin/sh\n' > "$TEEUP_PKG_PREFIX/bin/brew"
  chmod +x "$TEEUP_PKG_PREFIX/bin/brew"
  export TEEUP_PACKAGE_MANAGER=homebrew
  uninstall_path_hint
  run_fix "${_UNINSTALL_KEPT##*run: }" || { echo "the printed command failed"; return 1; }
  assert_contains "$(cat "$ZDOTDIR/.zprofile")" "eval \"\$($TEEUP_PKG_PREFIX/bin/brew shellenv)\"" || return 1
  uninstall_report_reset
  uninstall_path_hint
  assert_equals "" "$_UNINSTALL_KEPT" "no hint once the line is there" || return 1
  cleanup_test_env
}

echo "lib/uninstall.sh"
run_test "rm removes a file, a directory and a link without following it" test_rm_removes_a_file_a_directory_and_a_link_without_following_it
run_test "rm refuses outside HOME and in a git checkout, with a fix that works" test_rm_refuses_outside_home_and_in_a_git_checkout_with_a_fix_that_works
run_test "rm dry run deletes nothing and claims nothing" test_rm_dry_run_deletes_nothing_and_claims_nothing
run_test "summary lists each column and fails on a problem" test_summary_lists_each_column_and_fails_on_a_problem
run_test "caps lists installed capabilities dependents first" test_caps_lists_installed_capabilities_dependents_first
run_test "caps orders a bundle before its leaves and leaves before their shared base" test_caps_orders_a_bundle_before_its_leaves_and_leaves_before_their_shared_base
run_test "offer_restore asks and puts the earlier copy back" test_offer_restore_asks_and_puts_the_earlier_copy_back
run_test "offer_restore without a terminal notes a command that works" test_offer_restore_without_a_terminal_notes_a_command_that_works
run_test "shell strips teeup's lines from an edited zshrc and keeps the user's" test_shell_strips_teeups_lines_from_an_edited_zshrc_and_keeps_the_users
run_test "shell replaces a pristine zshrc and removes the other two" test_shell_replaces_a_pristine_zshrc_and_removes_the_other_two
run_test "shell refuses a symlinked zshrc and writes nothing" test_shell_refuses_a_symlinked_zshrc_and_writes_nothing
run_test "shell honours ZDOTDIR and refuses one inside a git checkout" test_shell_honours_zdotdir_and_refuses_one_inside_a_git_checkout
run_test "shell dry run changes nothing" test_shell_dry_run_changes_nothing
run_test "path hint prints a command that works" test_path_hint_prints_a_command_that_works
print_summary
