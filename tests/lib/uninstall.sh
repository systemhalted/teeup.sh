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

# MacPorts's own line, run the same way: the printed export really does put
# the port prefix on PATH once the .zprofile it lands in is sourced.
test_path_hint_prints_a_macports_command_that_works() {
  setup
  export ZDOTDIR="$TEST_HOME/z dot"
  mkdir -p "$ZDOTDIR" "$TEEUP_PKG_PREFIX/bin"
  printf '#!/bin/sh\n' > "$TEEUP_PKG_PREFIX/bin/port"
  chmod +x "$TEEUP_PKG_PREFIX/bin/port"
  export TEEUP_PACKAGE_MANAGER=macports
  uninstall_path_hint
  run_fix "${_UNINSTALL_KEPT##*run: }" || { echo "the printed command failed"; return 1; }
  assert_contains "$(cat "$ZDOTDIR/.zprofile")" "export PATH=\"$TEEUP_PKG_PREFIX/bin:$TEEUP_PKG_PREFIX/sbin:\$PATH\"" || return 1
  run_fix ". $(printf '%q' "$ZDOTDIR/.zprofile"); command -v port" || { echo "the port prefix never lands on PATH"; return 1; }
  uninstall_report_reset
  uninstall_path_hint
  assert_equals "" "$_UNINSTALL_KEPT" "no hint once the line is there" || return 1
  cleanup_test_env
}

# Final review I3: mise's own tools (node, and anything the ai-* wrappers
# lazily install through it) stop resolving in a new shell once teeup's shell
# layer -- which ran `mise activate zsh` (capabilities/zsh/default/init) and
# put ~/.local/bin and mise's own shims on PATH (default/env) -- is gone.
# When packages are kept, mise stays installed too, so the hint restores it
# the same way it restores Homebrew's or MacPorts' own PATH line. mise is
# mocked so `activate zsh` prints a PATH export the way real mise's does,
# pointing at a directory holding a fake tool.
test_path_hint_restores_mise_tools_when_they_are_kept() {
  setup
  export ZDOTDIR="$TEST_HOME/z dot"
  mkdir -p "$ZDOTDIR" "$TEEUP_PKG_PREFIX/bin"
  printf '#!/bin/sh\n' > "$TEEUP_PKG_PREFIX/bin/brew"
  chmod +x "$TEEUP_PKG_PREFIX/bin/brew"
  local tools="$TEST_HOME/mise-tools"
  mkdir -p "$tools"
  printf '#!/bin/sh\necho ran\n' > "$tools/node"
  chmod +x "$tools/node"
  cat > "$TEEUP_PKG_PREFIX/bin/mise" <<MISE
#!/bin/sh
if [ "\$1" = "activate" ]; then
  printf 'export PATH="%s:\$PATH"\n' "$tools"
fi
MISE
  chmod +x "$TEEUP_PKG_PREFIX/bin/mise"
  export TEEUP_PACKAGE_MANAGER=homebrew
  _UNINSTALL_PACKAGES=false
  uninstall_path_hint
  local note fix
  note="$(printf '%s\n' "$_UNINSTALL_KEPT" | grep '^mise at')"
  [[ -n "$note" ]] || { echo "no mise PATH hint was printed"; return 1; }
  fix="${note##*run: }"
  run_fix "$fix" || { echo "the printed command failed"; return 1; }
  assert_contains "$(cat "$ZDOTDIR/.zshrc")" "mise activate zsh" || return 1
  run_fix ". $(printf '%q' "$ZDOTDIR/.zshrc"); command -v node" | grep -q "$tools/node" || { echo "the mise shim tool does not resolve once the fix is sourced"; return 1; }
  uninstall_report_reset
  uninstall_path_hint
  assert_not_contains "$_UNINSTALL_KEPT" "mise at" "no repeat once the line is there" || return 1
  cleanup_test_env
}

# --packages uninstalls mise itself along with everything else it installed,
# so there is nothing of it left to restore, and the hint must say nothing.
test_path_hint_skips_mise_when_packages_are_removed() {
  setup
  mkdir -p "$TEEUP_PKG_PREFIX/bin"
  printf '#!/bin/sh\n' > "$TEEUP_PKG_PREFIX/bin/brew"
  chmod +x "$TEEUP_PKG_PREFIX/bin/brew"
  printf '#!/bin/sh\n' > "$TEEUP_PKG_PREFIX/bin/mise"
  chmod +x "$TEEUP_PKG_PREFIX/bin/mise"
  export TEEUP_PACKAGE_MANAGER=homebrew
  _UNINSTALL_PACKAGES=true
  uninstall_path_hint
  assert_not_contains "$_UNINSTALL_KEPT" "mise at" "mise's own hint must not print when --packages removes it" || return 1
  cleanup_test_env
}

# A hint is suppressed only by a line that would actually work: a comment
# never runs, and a bare `brew shellenv` cannot find Homebrew once teeup's own
# PATH lines are gone -- only the absolute, active eval does.
test_path_hint_needs_an_active_working_line_to_stop() {
  setup
  export ZDOTDIR="$TEST_HOME/z dot"
  mkdir -p "$ZDOTDIR" "$TEEUP_PKG_PREFIX/bin"
  printf '#!/bin/sh\n' > "$TEEUP_PKG_PREFIX/bin/brew"
  chmod +x "$TEEUP_PKG_PREFIX/bin/brew"
  export TEEUP_PACKAGE_MANAGER=homebrew
  printf '# eval "$(%s/bin/brew shellenv)"\n' "$TEEUP_PKG_PREFIX" > "$ZDOTDIR/.zprofile"
  uninstall_path_hint
  assert_contains "$_UNINSTALL_KEPT" "run:" "a commented-out working line must not suppress the hint" || return 1
  uninstall_report_reset
  printf 'eval "$(brew shellenv)"\n' > "$ZDOTDIR/.zprofile"
  uninstall_path_hint
  assert_contains "$_UNINSTALL_KEPT" "run:" "a bare shellenv with no prefix cannot find this Homebrew and must not suppress the hint" || return 1
  uninstall_report_reset
  printf 'eval "$(%s/bin/brew shellenv)"\n' "$TEEUP_PKG_PREFIX" > "$ZDOTDIR/.zprofile"
  uninstall_path_hint
  assert_equals "" "$_UNINSTALL_KEPT" "the working absolute line must suppress the hint" || return 1
  cleanup_test_env
}

# An unreadable file cannot be told apart from a clean one by exit status
# alone; a caller that treats "could not check" as "nothing to remove" would
# leave a live hook in place while later steps remove the binary it hooks.
test_shell_notes_a_failure_instead_of_silence_when_it_cannot_read_the_zshrc() {
  setup
  zsh_home
  printf 'export MINE=1\n' >> "$ZH/.zshrc"
  chmod 000 "$ZH/.zshrc"
  uninstall_shell >/dev/null 2>&1
  chmod 644 "$ZH/.zshrc"
  assert_contains "$_UNINSTALL_FAILED" "$ZH/.zshrc" "an unreadable file must be a failure, not silence" || return 1
  assert_contains "$(cat "$ZH/.zshrc")" "export MINE=1" "nothing teeup could not read may have been rewritten" || return 1
  cleanup_test_env
}

# --- Doom's theme line (final review I5) --------------------------------------
# capabilities/emacs/configure adds one marked line to a Doom user's
# config.el (the `;; teeup: theme ...` marker and the `load!` line right
# after it); once teeup is gone that line points into a state directory
# uninstall_teardown is about to delete. `load!`'s own noerror keeps it
# harmless to Doom, but it is dead, so teeup uninstall takes exactly those
# two lines out and leaves the rest of the file untouched.
doom_config_el() {
  mkdir -p "$TEST_HOME/.config/doom"
  printf '%s\n' "$1" > "$TEST_HOME/.config/doom/config.el"
}

test_doom_theme_line_removes_the_marker_and_the_load_line() {
  setup
  doom_config_el ';;; config.el -*- lexical-binding: t; -*-
;; teeup: theme (managed by teeup; remove this line to opt out)
(load! "'"$TEST_HOME"'/.local/state/teeup/current/theme/doom-theme-loader.el" "" t)

(setq doom-theme (quote doom-one))'
  uninstall_doom_theme_line
  local body
  body="$(cat "$TEST_HOME/.config/doom/config.el")"
  assert_equals ";;; config.el -*- lexical-binding: t; -*-" "$(head -n1 "$TEST_HOME/.config/doom/config.el")" \
    "the lexical-binding cookie stays byte for byte" || return 1
  assert_not_contains "$body" "teeup: theme" "the marker is gone" || return 1
  assert_not_contains "$body" "doom-theme-loader.el" "the load! line after the marker is gone too" || return 1
  assert_contains "$body" "(setq doom-theme (quote doom-one))" "the user's own line is left alone" || return 1
  assert_contains "$_UNINSTALL_REMOVED" "config.el" || return 1
  cleanup_test_env
}

# An old-style marked line (I3: a per-mode path fixed at configure time,
# never rewritten) must go the same way; uninstall does not care which form
# the line takes, only that the marker is there.
test_doom_theme_line_removes_an_old_style_load_line_too() {
  setup
  doom_config_el ';;; config.el
;; teeup: theme (managed by teeup; remove this line to opt out)
(load! "'"$TEST_HOME"'/.local/state/teeup/current/theme/dark/doom-theme.el" "" t)

(setq doom-theme (quote doom-one))'
  uninstall_doom_theme_line
  local body
  body="$(cat "$TEST_HOME/.config/doom/config.el")"
  assert_not_contains "$body" "teeup: theme" || return 1
  assert_not_contains "$body" "doom-theme.el" || return 1
  assert_contains "$body" "(setq doom-theme (quote doom-one))" || return 1
  cleanup_test_env
}

test_doom_theme_line_dry_run_changes_nothing() {
  setup
  doom_config_el ';; teeup: theme (managed by teeup; remove this line to opt out)
(load! "x" "" t)
(setq doom-theme (quote doom-one))'
  local before out
  before="$(cat "$TEST_HOME/.config/doom/config.el")"
  out="$(DRY_RUN=true uninstall_doom_theme_line 2>&1)"
  assert_equals "$before" "$(cat "$TEST_HOME/.config/doom/config.el")" "a dry run writes nothing" || return 1
  assert_contains "$out" "[DRY-RUN]" || return 1
  cleanup_test_env
}

# Nothing to do: the starter and Spacemacs (and a Doom user who deleted the
# line themselves) have either no config.el at all, or one with no marker.
test_doom_theme_line_is_a_no_op_when_there_is_no_marker() {
  setup
  doom_config_el ';; mine
(setq doom-theme (quote doom-one))'
  local before
  before="$(cat "$TEST_HOME/.config/doom/config.el")"
  uninstall_doom_theme_line
  assert_equals "$before" "$(cat "$TEST_HOME/.config/doom/config.el")" || return 1
  assert_equals "" "$_UNINSTALL_REMOVED" || return 1
  cleanup_test_env
}

test_doom_theme_line_is_a_no_op_with_no_config_el() {
  setup
  uninstall_doom_theme_line || { echo "must not fail when there is no Doom config.el at all"; return 1; }
  [[ ! -e "$TEST_HOME/.config/doom" ]] || { echo "must not create a doom directory"; return 1; }
  cleanup_test_env
}

test_doom_theme_line_refuses_a_symlinked_config_el() {
  setup
  mkdir -p "$TEST_HOME/.config/doom" "$TEST_HOME/elsewhere"
  doom_config_el ';; teeup: theme (managed by teeup; remove this line to opt out)
(load! "x" "" t)'
  mv "$TEST_HOME/.config/doom/config.el" "$TEST_HOME/elsewhere/config.el"
  ln -s "$TEST_HOME/elsewhere/config.el" "$TEST_HOME/.config/doom/config.el"
  local before
  before="$(cat "$TEST_HOME/elsewhere/config.el")"
  uninstall_doom_theme_line
  assert_equals "$before" "$(cat "$TEST_HOME/elsewhere/config.el")" "a symlinked config.el is not written through" || return 1
  cleanup_test_env
}

test_doom_theme_line_honors_doomdir() {
  setup
  export DOOMDIR="$TEST_HOME/somewhere/doom"
  mkdir -p "$DOOMDIR"
  printf ';; teeup: theme (managed by teeup; remove this line to opt out)\n(load! "x" "" t)\n' > "$DOOMDIR/config.el"
  uninstall_doom_theme_line
  assert_not_contains "$(cat "$DOOMDIR/config.el")" "teeup: theme" || return 1
  unset DOOMDIR
  cleanup_test_env
}

# make_remove_script <name> [exit status]
make_remove_script() {
  printf '#!/usr/bin/env bash\necho "remove:%s" >> "$MOCK_LOG"\nexit %s\n' "$1" "${2:-0}" > "$TEEUP_CAPS_DIR/$1/remove"
  chmod +x "$TEEUP_CAPS_DIR/$1/remove"
}

# A brew that says every formula and cask is installed and logs each call.
mock_brew_all_installed() {
  mock_command brew 0 ""
}

test_capabilities_keep_packages_by_default_and_name_how_to_remove_them() {
  setup
  mock_brew_all_installed
  make_cap tool lazy "" "ripgrep" "wezterm"
  make_remove_script tool
  state_done mark cap-tool
  uninstall_capabilities >/dev/null 2>&1
  assert_contains "$(cat "$MOCK_LOG")" "remove:tool" "the remove script still runs" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew uninstall" "packages are kept by default" || return 1
  assert_contains "$_UNINSTALL_KEPT" "Remove them later with: brew uninstall ripgrep" || return 1
  assert_contains "$_UNINSTALL_KEPT" "Remove them later with: brew uninstall --cask wezterm" || return 1
  state_done check cap-tool && { echo "tool is forgotten"; return 1; }
  uninstall_clean || return 1
  # Both printed "remove them later" commands actually call brew the way
  # they are spelled.
  local fix
  while IFS= read -r fix; do
    case "$fix" in *"Remove them later with:"*) run_fix "${fix##*: }" || { echo "the printed fix failed: $fix"; return 1; } ;; esac
  done <<EOF2
$_UNINSTALL_KEPT
EOF2
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall ripgrep" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall --cask wezterm" || return 1
  cleanup_test_env
}

test_package_inventory_lists_metadata_software_and_prints_commands_that_work() {
  setup
  mock_brew_all_installed
  make_cap first core "" "ripgrep" "wezterm"
  make_cap second lazy "" "ripgrep jq" "zed"
  uninstall_collect_packages all
  assert_equals "ripgrep jq" "$TEEUP_COLLECTED_PKGS" || return 1
  assert_equals "wezterm zed" "$TEEUP_COLLECTED_CASKS" || return 1
  local out fix
  out="$(uninstall_package_commands)"
  assert_contains "$out" "brew uninstall ripgrep jq" || return 1
  assert_contains "$out" "brew uninstall --cask wezterm zed" || return 1
  while IFS= read -r fix; do
    [[ -n "$fix" ]] || continue
    run_fix "$fix" || { echo "the printed uninstall command failed: $fix"; return 1; }
  done <<EOF2
$out
EOF2
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall ripgrep jq" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall --cask wezterm zed" || return 1
  cleanup_test_env
}

test_package_inventory_uses_only_marked_capabilities_for_an_installed_teeup() {
  setup
  mock_brew_all_installed
  make_cap installed core "" "ripgrep" "wezterm"
  make_cap unmarked lazy "" "jq" "zed"
  state_done mark cap-installed
  uninstall_collect_packages marked
  assert_equals "ripgrep" "$TEEUP_COLLECTED_PKGS" || return 1
  assert_equals "wezterm" "$TEEUP_COLLECTED_CASKS" || return 1
  cleanup_test_env
}

test_capabilities_name_what_the_tools_made_for_themselves() {
  setup
  make_cap mise core
  make_cap other lazy
  state_done mark cap-other
  uninstall_capabilities >/dev/null 2>&1
  assert_not_contains "$_UNINSTALL_KEPT" "made for themselves" "nothing to say without those tools" || return 1
  state_done mark cap-mise
  uninstall_capabilities >/dev/null 2>&1
  assert_contains "$_UNINSTALL_KEPT" "runtimes mise installed ($HOME/.local/share/mise)" || return 1
  cleanup_test_env
}

test_capabilities_uninstall_packages_when_asked() {
  setup
  mock_brew_all_installed
  make_cap tool lazy "" "ripgrep" "wezterm"
  state_done mark cap-tool
  _UNINSTALL_PACKAGES=true
  uninstall_capabilities >/dev/null 2>&1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall ripgrep" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall --cask wezterm" || return 1
  assert_contains "$_UNINSTALL_REMOVED" "tool's packages: ripgrep wezterm" || return 1
  cleanup_test_env
}

# The seven `teeup remove` refuses. Each is decided, none is run, and none
# counts as a problem.
test_capabilities_decide_each_of_the_seven_remove_refuses() {
  setup
  mock_brew_all_installed
  mock_command security 0 ""
  local name
  for name in xcode-clt package-manager teeup-runtime dev-dirs secrets ssh theme; do
    make_cap "$name" core
    state_done mark "cap-$name"
  done
  uninstall_capabilities >/dev/null 2>&1
  uninstall_clean || { echo "a policy decision is not a problem: $_UNINSTALL_REFUSED$_UNINSTALL_FAILED"; return 1; }
  assert_contains "$_UNINSTALL_KEPT" "Xcode Command Line Tools" || return 1
  assert_contains "$_UNINSTALL_KEPT" "teeup never uninstalls the package manager" || return 1
  assert_contains "$_UNINSTALL_KEPT" "$HOME/Work" || return 1
  assert_contains "$_UNINSTALL_KEPT" "Your SSH keys and ~/.ssh/config" || return 1
  for name in xcode-clt package-manager teeup-runtime dev-dirs secrets ssh theme; do
    case "$_UNINSTALL_GONE" in *" $name "*) ;; *) echo "$name was not handled"; return 1 ;; esac
  done
  assert_not_contains "$(cat "$MOCK_LOG")" "uninstall" || return 1
  cleanup_test_env
}

# A capability whose dependent failed stays, and is refused rather than
# pulled out from under it.
test_capabilities_refuse_what_a_failed_dependent_still_needs() {
  setup
  mock_brew_all_installed
  make_cap base core
  make_remove_script base
  make_cap top lazy base
  make_remove_script top 1
  state_done mark cap-base
  state_done mark cap-top
  uninstall_capabilities >/dev/null 2>&1
  assert_contains "$_UNINSTALL_FAILED" "top: its remove script failed" || return 1
  assert_contains "$_UNINSTALL_REFUSED" "base: still required by top" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "remove:base" "base's remove must not run" || return 1
  state_done check cap-base || { echo "base stays marked for the rerun"; return 1; }
  state_done check cap-top || { echo "top stays marked for the rerun"; return 1; }
  cleanup_test_env
}

# --packages must not take away the zsh the login shell runs.
test_capabilities_keep_the_zsh_the_login_shell_runs() {
  setup
  mock_brew_all_installed
  mock_command dscl 0 "UserShell: $TEEUP_PKG_PREFIX/bin/zsh"
  make_cap zsh core "" "zsh zsh-completions"
  state_done mark cap-zsh
  _UNINSTALL_PACKAGES=true
  uninstall_capabilities >/dev/null 2>&1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew uninstall" || return 1
  assert_contains "$_UNINSTALL_REFUSED" "chsh -s /bin/zsh" || return 1
  state_done check cap-zsh || { echo "zsh stays marked so the rerun can finish"; return 1; }
  cleanup_test_env
}

test_launchagents_are_unloaded_removed_and_checked() {
  setup
  mock_command launchctl 0 ""
  local dir="$TEST_HOME/Library/LaunchAgents"
  mkdir -p "$dir"
  printf '<plist/>\n' > "$dir/sh.teeup.keyboard.plist"
  printf '<plist/>\n' > "$dir/com.other.agent.plist"
  uninstall_launchagents >/dev/null 2>&1
  [[ ! -e "$dir/sh.teeup.keyboard.plist" ]] || { echo "teeup's agent must go"; return 1; }
  assert_file_exists "$dir/com.other.agent.plist" "someone else's agent stays" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "launchctl bootout gui/501 $dir/sh.teeup.keyboard.plist" || return 1
  assert_contains "$_UNINSTALL_REMOVED" "LaunchAgent sh.teeup.keyboard" || return 1
  cleanup_test_env
}

# A symlinked plist is left exactly as it is: teeup never writes through a
# link (the same rule uninstall_shell follows for a symlinked .zshrc).
test_launchagents_refuses_a_symlinked_plist_and_leaves_it() {
  setup
  mock_command launchctl 0 ""
  local dir="$TEST_HOME/Library/LaunchAgents" target="$TEST_HOME/elsewhere.plist"
  mkdir -p "$dir"
  printf '<plist/>\n' > "$target"
  ln -s "$target" "$dir/sh.teeup.keyboard.plist"
  uninstall_launchagents >/dev/null 2>&1
  [[ -L "$dir/sh.teeup.keyboard.plist" ]] || { echo "the symlink must stay a link"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "launchctl" "a symlinked agent must not be unloaded" || return 1
  assert_contains "$_UNINSTALL_REFUSED" "$dir/sh.teeup.keyboard.plist is a symlink" || return 1
  cleanup_test_env
}

# When the plist is still there after launchagent_remove ran, that is a
# failure, not a silent success. A directory with no write bit for its owner
# is what makes rm -f fail here: unlinking the plist needs write permission
# on the directory that holds it, and this test does not have it.
test_launchagents_notes_a_failure_when_one_is_still_there_after_removal() {
  setup
  mock_command launchctl 0 ""
  local dir="$TEST_HOME/Library/LaunchAgents"
  mkdir -p "$dir"
  printf '<plist/>\n' > "$dir/sh.teeup.keyboard.plist"
  chmod 500 "$dir"
  uninstall_launchagents >/dev/null 2>&1
  chmod 700 "$dir"
  assert_contains "$(cat "$MOCK_LOG")" "launchctl bootout gui/501 $dir/sh.teeup.keyboard.plist" || return 1
  assert_file_exists "$dir/sh.teeup.keyboard.plist" "the entry rm -f could not remove must still be there" || return 1
  assert_contains "$_UNINSTALL_FAILED" "LaunchAgent sh.teeup.keyboard: $dir/sh.teeup.keyboard.plist is still there" || return 1
  cleanup_test_env
}

test_secrets_are_named_with_commands_that_delete_them() {
  setup
  mock_command_script security <<'EOF2'
cat <<'DUMP'
keychain: "/Users/x/Library/Keychains/login.keychain-db"
class: "genp"
attributes:
    "acct"<blob>="gh token"
    "svce"<blob>="teeup"
keychain: "/Users/x/Library/Keychains/login.keychain-db"
class: "genp"
attributes:
    "acct"<blob>="someone"
    "svce"<blob>="other-app"
DUMP
EOF2
  make_cap secrets core
  state_done mark cap-secrets
  uninstall_capabilities >/dev/null 2>&1
  assert_contains "$_UNINSTALL_KEPT" "(gh token)" || return 1
  assert_contains "$_UNINSTALL_KEPT" "security delete-generic-password -s teeup -a gh\\ token" || return 1
  assert_not_contains "$_UNINSTALL_KEPT" "someone" || return 1
  # The printed delete command really does call security the way it is
  # spelled, with the account name as one argument.
  run_fix "${_UNINSTALL_KEPT##*: }" || { echo "the printed delete command failed"; return 1; }
  assert_contains "$(cat "$MOCK_LOG")" "delete-generic-password -s teeup -a gh token" || return 1
  cleanup_test_env
}

# The macports arm of the package-manager kept note (the homebrew arm is
# covered by test_capabilities_decide_each_of_the_seven_remove_refuses).
test_capabilities_name_the_macports_removal_steps() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  make_cap package-manager core
  state_done mark cap-package-manager
  uninstall_capabilities >/dev/null 2>&1
  assert_contains "$_UNINSTALL_KEPT" "MacPorts: teeup never uninstalls the package manager" || return 1
  assert_contains "$_UNINSTALL_KEPT" "https://guide.macports.org/#installing.macports.uninstalling" || return 1
  cleanup_test_env
}

# The macports arm of the "kept packages, remove them later" note (the
# homebrew arm is covered by
# test_capabilities_keep_packages_by_default_and_name_how_to_remove_them).
test_capabilities_keep_macports_packages_by_default_and_name_how_to_remove_them() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command_script port <<'EOF2'
[[ "$1" == "installed" ]] && echo "$2 @1.0 (active)"
exit 0
EOF2
  make_cap tool lazy "" "ripgrep"
  state_done mark cap-tool
  uninstall_capabilities >/dev/null 2>&1
  assert_not_contains "$(cat "$MOCK_LOG")" "port uninstall" "packages are kept by default" || return 1
  assert_contains "$_UNINSTALL_KEPT" "Remove them later with: sudo port uninstall ripgrep" || return 1
  cleanup_test_env
}

# install_teeup_file <shipped content> <dest>: the file as copy_config_once
# leaves it, stock record included.
install_teeup_file() {
  local src
  src="$(mktemp "$TEST_HOME/src.XXXXXX")"
  printf '%s\n' "$1" > "$src"
  copy_config_once "$src" "$2" >/dev/null
  rm -f "$src"
}

test_configs_remove_pristine_files_keep_edited_ones_and_prune_empty_dirs() {
  setup
  local cfg
  cfg="$(user_config_dir)"
  install_teeup_file "shipped" "$cfg/tool/tool.conf"
  install_teeup_file "shipped" "$cfg/other/other.conf"
  install_teeup_file "shipped" "$cfg/weird dir \$x/w.conf"
  printf 'mine\n' >> "$cfg/other/other.conf"
  uninstall_configs >/dev/null 2>&1
  [[ ! -e "$cfg/tool" ]] || { echo "a pristine file goes, and its emptied directory with it"; return 1; }
  [[ ! -e "$cfg/weird dir \$x" ]] || { echo "an awkward path is decoded and removed too"; return 1; }
  assert_file_exists "$cfg/other/other.conf" "an edited file stays" || return 1
  assert_contains "$_UNINSTALL_KEPT" "Config files you edited: $cfg/other/other.conf" || return 1
  assert_dir_exists "$cfg" "the config directory itself is never pruned" || return 1
  cleanup_test_env
}

# Without --identity, ~/.ssh/config and ~/.config/git/config stay even when
# pristine: git reads the identity through them.
test_configs_keep_the_identity_files_without_identity() {
  setup
  local gdir
  gdir="$(user_config_dir)/git"
  install_teeup_file "Host github.com" "$HOME/.ssh/config"
  install_teeup_file "[include]" "$gdir/config"
  printf '# Generated by teeup (teeup configure git). Your edits here are overwritten.\n[core]\n' > "$gdir/teeup-generated"
  printf '# Generated by teeup (teeup configure git). Your edits here are overwritten.\n[user]\n' > "$gdir/identity"
  uninstall_configs >/dev/null 2>&1
  assert_file_exists "$HOME/.ssh/config" || return 1
  assert_file_exists "$gdir/config" || return 1
  assert_file_exists "$gdir/identity" || return 1
  [[ ! -e "$gdir/teeup-generated" ]] || { echo "teeup's generated settings go either way"; return 1; }
  cleanup_test_env
}

test_configs_leave_a_generated_file_teeup_did_not_write() {
  setup
  local gdir
  gdir="$(user_config_dir)/git"
  mkdir -p "$gdir"
  printf '[core]\n\teditor = nano\n' > "$gdir/teeup-generated"
  uninstall_configs >/dev/null 2>&1
  assert_file_exists "$gdir/teeup-generated" || return 1
  assert_contains "$_UNINSTALL_KEPT" "teeup did not write it" || return 1
  cleanup_test_env
}

# teeup-generated kept signing off while no key existed. With it gone, the
# kept config's gpgsign = true would fail every commit, so the printed fix
# must turn it off -- and it does.
test_configs_gpgsign_fix_works() {
  setup
  hide_host_commands ssh
  local gdir fix
  gdir="$(user_config_dir)/git"
  install_teeup_file "$(printf '[commit]\n\tgpgsign = true')" "$gdir/config"
  uninstall_configs >/dev/null 2>&1
  fix="$(printf '%s\n' "$_UNINSTALL_KEPT" | sed -n 's/^Commit signing.*Turn signing off with: //p')"
  [[ -n "$fix" ]] || { echo "no signing fix was printed"; return 1; }
  run_fix "$fix" || { echo "the fix failed: $fix"; return 1; }
  assert_equals "false" "$(git config --file "$gdir/config" commit.gpgsign)" || return 1
  cleanup_test_env
}

# Final review I2: --packages can uninstall git-delta, git-lfs and gh while a
# kept git/config (edited, or pristine and kept because --identity was not
# given) still sets core.pager, interactive.diffFilter, the lfs filter and
# the GitHub/gist credential helper to them. The kept note names each such
# line and the exact command that clears it; run_fix proves each one really
# works, and git stays usable (a real commit, then `git log`) with delta gone.
test_configs_names_git_config_lines_that_reference_removed_packages() {
  setup
  hide_host_commands ssh
  local gdir note fixes cmd
  gdir="$(user_config_dir)/git"
  install_teeup_file "$(cat "$TEEUP_PATH/capabilities/git/config/git/config")" "$gdir/config"
  _UNINSTALL_PACKAGES=true
  uninstall_configs >/dev/null 2>&1
  note="$(printf '%s\n' "$_UNINSTALL_KEPT" | grep "still sets")"
  [[ -n "$note" ]] || { echo "no kept note named the git config lines that reference removed packages"; return 1; }
  assert_contains "$note" "core.pager = delta" || return 1
  assert_contains "$note" "interactive.diffFilter = delta --color-only" || return 1
  assert_contains "$note" "filter.lfs" || return 1
  assert_contains "$note" "credential.https://github.com.helper" || return 1
  assert_contains "$note" "credential.https://gist.github.com.helper" || return 1
  fixes="$(printf '%s\n' "$note" | sed -n 's/^.*Remove those settings with: //p')"
  [[ -n "$fixes" ]] || { echo "no fix commands were printed"; return 1; }
  local old_ifs="$IFS"
  IFS=';'
  for cmd in $fixes; do
    cmd="$(printf '%s' "$cmd" | sed -e 's/^ *//' -e 's/ *$//')"
    run_fix "$cmd" || { IFS="$old_ifs"; echo "the fix failed: $cmd"; return 1; }
  done
  IFS="$old_ifs"
  [[ -z "$(git config --file "$gdir/config" --get core.pager 2>/dev/null)" ]] || { echo "core.pager should be unset"; return 1; }
  [[ -z "$(git config --file "$gdir/config" --get interactive.diffFilter 2>/dev/null)" ]] || { echo "interactive.diffFilter should be unset"; return 1; }
  ! git config --file "$gdir/config" --get-regexp '^filter\.lfs\.' >/dev/null 2>&1 || { echo "filter.lfs should be gone"; return 1; }
  [[ -z "$(git config --file "$gdir/config" --get credential.https://github.com.helper 2>/dev/null)" ]] || { echo "the github helper should be unset"; return 1; }
  [[ -z "$(git config --file "$gdir/config" --get credential.https://gist.github.com.helper 2>/dev/null)" ]] || { echo "the gist helper should be unset"; return 1; }
  # git must still work once delta is gone: build a real repo with this fixed
  # config as its only global config (HOME and XDG_CONFIG_HOME already point
  # here) and the harness's own narrowed PATH, which has no delta on it.
  local repo="$TEST_HOME/gitlogrepo" out
  mkdir -p "$repo"
  ( cd "$repo" && git init -q . &&
    git -c commit.gpgsign=false -c user.email=t@example.com -c user.name=t commit --allow-empty -q -m init
  ) >/dev/null 2>&1 || { echo "building the repo failed with the fixed config"; return 1; }
  out="$(cd "$repo" && git log 2>&1)" || { echo "git log failed with delta absent: $out"; return 1; }
  assert_contains "$out" "init" "git log still shows the commit" || return 1
  cleanup_test_env
}

# Plan Decision 8: git/config is kept only WITHOUT --identity; a pristine one
# goes under --identity like any other file.
test_configs_removes_a_pristine_git_config_with_identity() {
  setup
  local gdir
  gdir="$(user_config_dir)/git"
  install_teeup_file "[include]" "$gdir/config"
  _UNINSTALL_IDENTITY=true
  uninstall_configs >/dev/null 2>&1
  [[ ! -e "$gdir/config" ]] || { echo "a pristine git/config goes with --identity"; return 1; }
  cleanup_test_env
}

# A stock record is decided from the recorded path's own tail, not by
# comparing it against the CURRENT XDG_CONFIG_HOME: a git/config installed
# under one XDG_CONFIG_HOME must still be recognised as an identity file --
# and so stay, without --identity -- when uninstall later runs with another.
test_configs_identity_skip_survives_a_changed_xdg_config_home() {
  setup
  export XDG_CONFIG_HOME="$TEST_HOME/xdg-old"
  mkdir -p "$XDG_CONFIG_HOME/git"
  install_teeup_file "[include]" "$XDG_CONFIG_HOME/git/config"
  export XDG_CONFIG_HOME="$TEST_HOME/xdg-new"
  uninstall_configs >/dev/null 2>&1
  assert_file_exists "$TEST_HOME/xdg-old/git/config" "the identity file survives a changed XDG_CONFIG_HOME" || return 1
  cleanup_test_env
}

# teeup never deletes an SSH key, with or without --identity (2026-09-26
# decision): a key at this name may not be one teeup made. It is only named,
# with a manual removal command that actually works once the user runs it.
test_identity_never_deletes_a_regular_key_and_prints_a_working_removal_command() {
  setup
  mock_command ssh-add 0 ""
  mkdir -p "$HOME/.ssh"
  printf 'k\n' > "$HOME/.ssh/id_ed25519_personal"
  printf 'k\n' > "$HOME/.ssh/id_ed25519_personal.pub"
  uninstall_identity >/dev/null 2>&1
  assert_file_exists "$HOME/.ssh/id_ed25519_personal" "teeup never deletes the key itself" || return 1
  assert_file_exists "$HOME/.ssh/id_ed25519_personal.pub" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "ssh-add" "teeup itself never calls ssh-add" || return 1
  local fix
  fix="$(printf '%s\n' "$_UNINSTALL_KEPT" | sed -n 's/^.*Remove it yourself: //p')"
  [[ -n "$fix" ]] || { echo "no manual removal command was printed"; return 1; }
  run_fix "$fix" || { echo "the printed fix failed: $fix"; return 1; }
  [[ ! -e "$HOME/.ssh/id_ed25519_personal" && ! -e "$HOME/.ssh/id_ed25519_personal.pub" ]] || { echo "running the fix should move both halves aside"; return 1; }
  assert_contains "$(cat "$MOCK_LOG")" "ssh-add -d --apple-use-keychain $HOME/.ssh/id_ed25519_personal" "the fix drops it from the agent and Keychain first" || return 1
  cleanup_test_env
}

# A symlinked key is only named, never followed: ssh-add is never called for
# it and nothing is written through the link.
test_identity_names_a_symlinked_key_and_never_touches_it() {
  setup
  mkdir -p "$HOME/.ssh" "$HOME/elsewhere"
  printf 'k\n' > "$HOME/elsewhere/realkey"
  ln -s "$HOME/elsewhere/realkey" "$HOME/.ssh/id_ed25519_personal"
  uninstall_identity >/dev/null 2>&1
  [[ -L "$HOME/.ssh/id_ed25519_personal" ]] || { echo "the symlink must stay a link"; return 1; }
  assert_equals "k" "$(cat "$HOME/elsewhere/realkey")" "nothing is written through the link" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "ssh-add" "a symlinked key is never touched" || return 1
  assert_contains "$_UNINSTALL_KEPT" "$HOME/.ssh/id_ed25519_personal is a symlink" || return 1
  cleanup_test_env
}

test_identity_moves_local_aside_and_removes_the_generated_identity_file() {
  setup
  local gdir
  gdir="$(user_config_dir)/git"
  mkdir -p "$gdir"
  printf '# Generated by teeup (teeup configure git). Your edits here are overwritten.\n' > "$gdir/identity"
  printf '[user]\n\temail = me@example.com\n' > "$gdir/local"
  uninstall_identity >/dev/null 2>&1
  [[ ! -e "$gdir/identity" ]] || { echo "the generated identity goes"; return 1; }
  [[ ! -e "$gdir/local" ]] || { echo "local is moved aside"; return 1; }
  [[ -n "$(uninstall_newest_backup "$gdir/local")" ]] || { echo "local's content must survive in a backup"; return 1; }
  cleanup_test_env
}

# A symlinked git/local is only named, never moved: mv would replace the link
# with a plain file and never touch whatever it points at.
test_identity_names_a_symlinked_git_local_and_leaves_it() {
  setup
  local gdir
  gdir="$(user_config_dir)/git"
  mkdir -p "$gdir" "$HOME/elsewhere"
  printf 'mine\n' > "$HOME/elsewhere/local"
  ln -s "$HOME/elsewhere/local" "$gdir/local"
  uninstall_identity >/dev/null 2>&1
  [[ -L "$gdir/local" ]] || { echo "the symlink must stay a link"; return 1; }
  assert_contains "$_UNINSTALL_KEPT" "$gdir/local is a symlink" || return 1
  cleanup_test_env
}

# The failure branch's printed mv must never clobber a backup name that is
# already taken -- the same collision-checked naming backup_target itself
# uses (_backup_name), not a fixed ".old" that a second attempt would
# silently overwrite.
test_identity_local_backup_fix_avoids_a_name_already_taken() {
  setup
  mock_command date 0 "20260101000000"
  local gdir fix
  gdir="$(user_config_dir)/git"
  mkdir -p "$gdir"
  printf 'existing backup\n' > "$gdir/local.teeup_backup_20260101000000"
  printf 'first\n' > "$gdir/local"
  chmod 500 "$gdir"
  uninstall_identity >/dev/null 2>&1
  chmod 700 "$gdir"
  assert_contains "$_UNINSTALL_FAILED" "$gdir/local: could not move it aside" || return 1
  fix="$(printf '%s\n' "$_UNINSTALL_FAILED" | sed -n 's/^.*Move it yourself with: //p')"
  [[ -n "$fix" ]] || { echo "no manual move command was printed"; return 1; }
  run_fix "$fix" || { echo "the printed fix failed: $fix"; return 1; }
  [[ ! -e "$gdir/local" ]] || { echo "the fix should have moved local aside"; return 1; }
  local backups=("$gdir"/local.teeup_backup_*)
  [[ ${#backups[@]} -ge 2 ]] || { echo "the existing backup must survive alongside a new one"; return 1; }
  local all
  all="$(cat "${backups[@]}")"
  assert_contains "$all" "existing backup" "the pre-existing backup must not be overwritten" || return 1
  assert_contains "$all" "first" "local's content must survive in the new backup" || return 1
  cleanup_test_env
}

# teeup's own files as teeup-runtime/configure leaves them, the user's own
# machine file among them.
teeup_runtime_home() {
  mkdir -p "$TEEUP_CONFIG_DIR/hooks/post-update.d" "$TEEUP_STATE_DIR/done" "$HOME/.local/bin"
  : > "$TEEUP_STATE_DIR/done/cap-teeup-runtime"
  printf 'export TEEUP_PATH=x\n' > "$TEEUP_CONFIG_DIR/env"
  printf 'TEEUP_NAME="Ada"\n' > "$TEEUP_CONFIG_DIR/answers"
  printf '# sample\n' > "$TEEUP_CONFIG_DIR/hooks/post-update.d/example.sample"
  ln -s "$TEEUP_PATH/bin/teeup" "$HOME/.local/bin/teeup"
}

test_teardown_removes_teeups_command_config_and_state() {
  setup
  teeup_runtime_home
  uninstall_teardown >/dev/null 2>&1
  [[ ! -e "$TEEUP_CONFIG_DIR" ]] || { echo "the config dir goes when nothing of the user's is in it"; return 1; }
  [[ ! -e "$TEEUP_STATE_DIR" ]] || { echo "the state dir goes"; return 1; }
  [[ ! -L "$HOME/.local/bin/teeup" ]] || { echo "the command goes"; return 1; }
  assert_file_exists "$TEEUP_PATH/bin/teeup" "the checkout stays" || return 1
  cleanup_test_env
}

test_teardown_keeps_the_users_own_files_in_the_config_dir() {
  setup
  teeup_runtime_home
  mkdir -p "$TEEUP_CONFIG_DIR/machines" "$TEEUP_CONFIG_DIR/hooks/post-update.d"
  printf 'TEEUP_SKIP="aerospace"\n' > "$TEEUP_CONFIG_DIR/machines/testmac.conf"
  printf 'echo mine\n' > "$TEEUP_CONFIG_DIR/hooks/post-update.d/mine"
  uninstall_teardown >/dev/null 2>&1
  assert_file_exists "$TEEUP_CONFIG_DIR/machines/testmac.conf" || return 1
  assert_file_exists "$TEEUP_CONFIG_DIR/hooks/post-update.d/mine" || return 1
  [[ ! -e "$TEEUP_CONFIG_DIR/env" && ! -e "$TEEUP_CONFIG_DIR/answers" ]] || { echo "teeup's own files go"; return 1; }
  [[ ! -e "$TEEUP_CONFIG_DIR/hooks/post-update.d/example.sample" ]] || { echo "the sample goes"; return 1; }
  assert_contains "$_UNINSTALL_KEPT" "machines/testmac.conf" || return 1
  cleanup_test_env
}

# Review I2: the "Delete them with: rm -rf <config dir>" fix is a real
# command, run for real here (Global Constraint 15), against a config dir
# named with a space -- the suites' usual awkward-path check -- to prove
# uninstall_q's quoting round-trips through zsh/bash.
test_teardown_config_dir_leftover_fix_removes_it() {
  setup
  export TEEUP_CONFIG_DIR="$TEST_HOME/con fig \$x"
  teeup_runtime_home
  mkdir -p "$TEEUP_CONFIG_DIR/machines"
  printf 'TEEUP_SKIP="aerospace"\n' > "$TEEUP_CONFIG_DIR/machines/testmac.conf"
  uninstall_teardown >/dev/null 2>&1
  assert_dir_exists "$TEEUP_CONFIG_DIR" "the config dir stays while the user's own file is in it" || return 1
  run_fix "${_UNINSTALL_KEPT##*Delete them with: }" || { echo "the printed rm -rf failed"; return 1; }
  [[ ! -e "$TEEUP_CONFIG_DIR" ]] || { echo "the printed rm -rf must remove the whole config dir"; return 1; }
  cleanup_test_env
}

# After any refusal or failure the rerun needs teeup's state, config and
# command, so none of them is touched.
test_teardown_waits_for_a_clean_run() {
  setup
  teeup_runtime_home
  uninstall_note failed "something"
  uninstall_teardown >/dev/null 2>&1
  assert_dir_exists "$TEEUP_STATE_DIR" || return 1
  assert_file_exists "$TEEUP_CONFIG_DIR/env" || return 1
  [[ -L "$HOME/.local/bin/teeup" ]] || { echo "the command stays for the rerun"; return 1; }
  cleanup_test_env
}

test_teardown_leaves_a_command_that_is_not_teeups() {
  setup
  mkdir -p "$HOME/.local/bin"
  ln -s /somewhere/else "$HOME/.local/bin/teeup"
  uninstall_teardown >/dev/null 2>&1
  [[ -L "$HOME/.local/bin/teeup" ]] || { echo "a link to somewhere else is not teeup's"; return 1; }
  assert_contains "$_UNINSTALL_KEPT" "not at this checkout" || return 1
  cleanup_test_env
}

# A state directory outside $HOME is refused, and the printed rm removes it.
test_teardown_refuses_a_state_dir_outside_home_with_a_fix_that_works() {
  setup
  export HOME="$TEST_HOME/home"
  export TEEUP_STATE_DIR="$TEST_HOME/elsewhere/st ate \$x"
  export TEEUP_CONFIG_DIR="$HOME/.config/teeup"
  mkdir -p "$HOME" "$TEEUP_STATE_DIR/done"
  mkdir -p "$TEEUP_CONFIG_DIR" "$HOME/.local/bin"
  printf 'x\n' > "$TEEUP_CONFIG_DIR/answers"
  ln -s "$TEEUP_PATH/bin/teeup" "$HOME/.local/bin/teeup"
  uninstall_teardown >/dev/null 2>&1
  assert_dir_exists "$TEEUP_STATE_DIR" || return 1
  # Checked before anything was deleted: config and command stay too.
  assert_file_exists "$TEEUP_CONFIG_DIR/answers" "a refused state dir must stop the whole teardown" || return 1
  [[ -L "$HOME/.local/bin/teeup" ]] || { echo "the teeup command must stay for the rerun"; return 1; }
  run_fix "${_UNINSTALL_REFUSED##*mean to: }" || { echo "the printed rm failed"; return 1; }
  [[ ! -e "$TEEUP_STATE_DIR" ]] || { echo "the printed rm must remove it"; return 1; }
  cleanup_test_env
}

# Codex P1 on the plan: a symlinked config dir was refused only after the
# command was deleted, and the state was deleted after it anyway.
test_teardown_keeps_everything_when_the_config_dir_is_a_symlink() {
  setup
  export HOME="$TEST_HOME/home"
  export TEEUP_STATE_DIR="$HOME/.local/state/teeup"
  export TEEUP_CONFIG_DIR="$HOME/.config/teeup"
  mkdir -p "$TEST_HOME/dotfiles/teeup" "$HOME/.config" "$TEEUP_STATE_DIR/done" "$HOME/.local/bin"
  ln -s "$TEST_HOME/dotfiles/teeup" "$TEEUP_CONFIG_DIR"
  ln -s "$TEEUP_PATH/bin/teeup" "$HOME/.local/bin/teeup"
  uninstall_teardown >/dev/null 2>&1
  assert_dir_exists "$TEEUP_STATE_DIR/done" "the state must stay for the rerun" || return 1
  [[ -L "$HOME/.local/bin/teeup" ]] || { echo "the teeup command must stay for the rerun"; return 1; }
  [[ -L "$TEEUP_CONFIG_DIR" ]] || { echo "the symlinked config dir must be left as it was"; return 1; }
  assert_contains "$_UNINSTALL_REFUSED" "symlink" || return 1
  cleanup_test_env
}

# Review M4 (data loss): TEEUP_STATE_DIR is a user-settable override, and the
# state dir was `rm -rf`'d outright with no check that it is actually
# teeup's. A directory that merely happens to be named or pointed at that way
# -- holding none of teeup's own markers -- must be left alone entirely,
# config and command included, not silently `rm -rf`'d.
test_teardown_refuses_a_state_dir_with_no_teeup_markers() {
  setup
  teeup_runtime_home
  rm -rf "$TEEUP_STATE_DIR"
  mkdir -p "$TEEUP_STATE_DIR"
  printf 'unrelated\n' > "$TEEUP_STATE_DIR/some-other-file"
  uninstall_teardown >/dev/null 2>&1
  assert_dir_exists "$TEEUP_STATE_DIR" "an unrecognisable state dir must stay" || return 1
  assert_file_exists "$TEEUP_STATE_DIR/some-other-file" "nothing inside it is touched either" || return 1
  assert_file_exists "$TEEUP_CONFIG_DIR/env" "the config must stay too" || return 1
  [[ -L "$HOME/.local/bin/teeup" ]] || { echo "the command must stay too"; return 1; }
  assert_contains "$_UNINSTALL_KEPT" "$TEEUP_STATE_DIR" || return 1
  cleanup_test_env
}

# The re-review's case: mise's own data dir has shims/ and migrations/, so a
# TEEUP_STATE_DIR override pointed at it passed a check on generic names.
# Codex on #52: the uninstall loop names a linked LaunchAgents directory as
# refused and leaves the file in the checkout alone.
test_launchagents_refuses_a_linked_launchagents_directory() {
  setup
  mock_command launchctl 0 ""
  local repo="$TEST_HOME/dotfiles"
  mkdir -p "$repo/.git" "$repo/LaunchAgents" "$TEST_HOME/Library"
  printf '<plist/>\n' > "$repo/LaunchAgents/sh.teeup.old.plist"
  ln -s "$repo/LaunchAgents" "$TEST_HOME/Library/LaunchAgents"
  uninstall_launchagents >/dev/null 2>&1
  assert_file_exists "$repo/LaunchAgents/sh.teeup.old.plist" || return 1
  assert_contains "$_UNINSTALL_REFUSED" "sh.teeup.old" || return 1
  cleanup_test_env
}

test_teardown_refuses_a_state_dir_that_only_shares_generic_names() {
  setup
  teeup_runtime_home
  rm -rf "$TEEUP_STATE_DIR"
  mkdir -p "$TEEUP_STATE_DIR/shims" "$TEEUP_STATE_DIR/migrations" "$TEEUP_STATE_DIR/done"
  printf 'x\n' > "$TEEUP_STATE_DIR/shims/node"
  unset _UNINSTALL_STATE_OWNED
  uninstall_teardown >/dev/null 2>&1
  assert_file_exists "$TEEUP_STATE_DIR/shims/node" "a directory that is not teeup's must stay whole" || return 1
  assert_file_exists "$TEEUP_CONFIG_DIR/env" "the config must stay too" || return 1
  assert_contains "$_UNINSTALL_KEPT" "no cap-* install marker" || return 1
  cleanup_test_env
}

# Even teeup's own state dir keeps a file teeup did not write, and so stays.
test_teardown_keeps_a_file_it_did_not_write_in_the_state_dir() {
  setup
  teeup_runtime_home
  printf 'mine\n' > "$TEEUP_STATE_DIR/notes.txt"
  unset _UNINSTALL_STATE_OWNED
  uninstall_teardown >/dev/null 2>&1
  assert_file_exists "$TEEUP_STATE_DIR/notes.txt" || return 1
  [[ ! -e "$TEEUP_STATE_DIR/done" ]] || { echo "teeup's own records still go"; return 1; }
  assert_contains "$_UNINSTALL_KEPT" "notes.txt" || return 1
  cleanup_test_env
}

# The normal state dir (teeup_runtime_home's own "done" marker) is still
# removed -- the new guard must not make every real teardown refuse itself.
test_teardown_still_removes_a_real_state_dir() {
  setup
  teeup_runtime_home
  uninstall_teardown >/dev/null 2>&1
  [[ ! -e "$TEEUP_STATE_DIR" ]] || { echo "a state dir with teeup's own markers must still go"; return 1; }
  cleanup_test_env
}

# Final review I1: lib/macos.sh's _defaults_record_path writes under
# $TEEUP_STATE_DIR/defaults, which macos-defaults (core tier) leaves behind
# once defaults_restore has cleared every record file inside it. Missing from
# teeup's own list, that empty directory made every real Mac's state dir
# un-removable and every later run call it "not teeup's own".
test_teardown_removes_a_defaults_directory_macos_defaults_leaves_behind() {
  setup
  teeup_runtime_home
  mkdir -p "$TEEUP_STATE_DIR/defaults"
  printf 'string:1\n' > "$TEEUP_STATE_DIR/defaults/com.example.foo"
  uninstall_teardown >/dev/null 2>&1
  [[ ! -e "$TEEUP_STATE_DIR" ]] || { echo "the state dir must go once defaults/ is one of teeup's own entries"; return 1; }
  cleanup_test_env
}

# Final review I5: capabilities/terminal-app/theme-apply writes the exported
# .terminal files under $TEEUP_STATE_DIR/terminal-app, a top-level entry
# CONTRIBUTING item 33 requires in _UNINSTALL_STATE_ENTRIES. Missing from
# teeup's own list, a dry run left it behind and reported the state dir as
# holding files teeup did not write, and a real run left the directory (and
# the whole state dir) un-removable whenever it existed without an install
# marker (theme-apply ran under TEEUP_CONFIGURING and the configure then
# failed).
test_teardown_removes_the_terminal_app_directory_theme_apply_leaves_behind() {
  setup
  teeup_runtime_home
  mkdir -p "$TEEUP_STATE_DIR/terminal-app"
  printf 'Window Settings\n' > "$TEEUP_STATE_DIR/terminal-app/teeup Catppuccin Dark.terminal"
  uninstall_teardown >/dev/null 2>&1
  [[ ! -e "$TEEUP_STATE_DIR" ]] || { echo "the state dir must go once terminal-app/ is one of teeup's own entries"; return 1; }
  cleanup_test_env
}

# The same scenario, previewed: a dry run must not report terminal-app/ as a
# leftover teeup did not write (the final review's exact repro).
test_dry_run_teardown_does_not_call_the_terminal_app_directory_a_leftover() {
  setup
  teeup_runtime_home
  mkdir -p "$TEEUP_STATE_DIR/terminal-app"
  printf 'Window Settings\n' > "$TEEUP_STATE_DIR/terminal-app/teeup Catppuccin Dark.terminal"
  DRY_RUN=true uninstall_teardown >/dev/null 2>&1
  assert_not_contains "$_UNINSTALL_KEPT" "holds files teeup did not write" "a dry run must preview terminal-app as one of teeup's own entries, not a leftover" || return 1
  cleanup_test_env
}

# Task 6 carry (Task 5's re-review observation): a ZDOTDIR changed since
# install leaves the old zsh home files still recorded in stock, at a
# directory uninstall_shell no longer looks at by default. They must still
# go through uninstall_shell's own handling -- the live-line check, the
# symlink and git-checkout refusals, the .zshrc stub -- never uninstall_rm's
# plain pristine-file removal by way of uninstall_configs.
test_shell_handles_zsh_home_files_left_at_an_old_zdotdir() {
  setup
  local old="$TEST_HOME/old zdot" new="$TEST_HOME/newzdot"
  export ZDOTDIR="$old"
  zsh_home
  mkdir -p "$new"
  export ZDOTDIR="$new"
  uninstall_shell >/dev/null 2>&1
  [[ ! -e "$old/.zshenv" && ! -e "$old/.zprofile" ]] || { echo "pristine files at the old ZDOTDIR must go too"; return 1; }
  assert_file_exists "$old/.zshrc" "a stub replaces the old ZDOTDIR's pristine .zshrc" || return 1
  uninstall_shell_live "$old/.zshrc" && { echo "the old ZDOTDIR's .zshrc still has a live teeup line"; return 1; }
  cleanup_test_env
}

test_configs_leaves_zsh_home_files_at_an_old_zdotdir_for_uninstall_shell() {
  setup
  local old="$TEST_HOME/old zdot" new="$TEST_HOME/newzdot"
  export ZDOTDIR="$old"
  zsh_home
  mkdir -p "$new"
  export ZDOTDIR="$new"
  uninstall_configs >/dev/null 2>&1
  assert_file_exists "$old/.zshenv" "uninstall_configs must leave the old ZDOTDIR's zsh files for uninstall_shell" || return 1
  assert_file_exists "$old/.zprofile" || return 1
  assert_file_exists "$old/.zshrc" || return 1
  cleanup_test_env
}

# agent_skill_link (lib/files.sh) symlinks teeup's own share/agents/skills/
# teeup into every agent CLI's skill directory it finds. uninstall_agent_skills
# is the reverse of exactly that: it removes only a link whose target
# resolves, physically, to this checkout's own skill directory, and leaves
# anything else at that name -- a real file, or a symlink into somewhere
# else -- named as kept.
test_uninstall_agent_skills_removes_teeups_own_links() {
  setup
  mkdir -p "$TEST_HOME/.claude"
  agent_skill_link "$TEEUP_PATH/share/agents/skills/teeup" teeup >/dev/null
  assert_equals "$TEEUP_PATH/share/agents/skills/teeup" "$(readlink "$TEST_HOME/.agents/skills/teeup")" "fixture: the link exists before uninstall" || return 1
  uninstall_agent_skills
  [[ ! -e "$TEST_HOME/.agents/skills/teeup" && ! -L "$TEST_HOME/.agents/skills/teeup" ]] || { echo "the tool-neutral link must be removed"; return 1; }
  [[ ! -e "$TEST_HOME/.claude/skills/teeup" && ! -L "$TEST_HOME/.claude/skills/teeup" ]] || { echo "the claude link must be removed"; return 1; }
  assert_contains "$_UNINSTALL_REMOVED" "agent skill link" || return 1
  cleanup_test_env
}

test_uninstall_agent_skills_keeps_a_foreign_symlink() {
  setup
  mkdir -p "$TEST_HOME/.agents/skills" "$TEST_HOME/elsewhere"
  ln -s "$TEST_HOME/elsewhere" "$TEST_HOME/.agents/skills/teeup"
  uninstall_agent_skills
  assert_equals "$TEST_HOME/elsewhere" "$(readlink "$TEST_HOME/.agents/skills/teeup")" "a symlink teeup did not write must be left alone" || return 1
  assert_contains "$_UNINSTALL_KEPT" "$TEST_HOME/.agents/skills/teeup" "the kept line must name the link" || return 1
  cleanup_test_env
}

test_uninstall_agent_skills_keeps_a_file_it_did_not_write() {
  setup
  mkdir -p "$TEST_HOME/.agents/skills/teeup"
  printf 'mine\n' > "$TEST_HOME/.agents/skills/teeup/SKILL.md"
  uninstall_agent_skills
  assert_file_exists "$TEST_HOME/.agents/skills/teeup/SKILL.md" "a real directory teeup did not write must survive" || return 1
  assert_equals "mine" "$(cat "$TEST_HOME/.agents/skills/teeup/SKILL.md")" || return 1
  assert_contains "$_UNINSTALL_KEPT" "$TEST_HOME/.agents/skills/teeup" "the kept line must name it" || return 1
  cleanup_test_env
}

test_uninstall_agent_skills_dry_run_removes_nothing() {
  setup
  mkdir -p "$TEST_HOME/.codex"
  agent_skill_link "$TEEUP_PATH/share/agents/skills/teeup" teeup >/dev/null
  DRY_RUN=true uninstall_agent_skills
  assert_equals "$TEEUP_PATH/share/agents/skills/teeup" "$(readlink "$TEST_HOME/.agents/skills/teeup")" "a dry run must remove nothing" || return 1
  assert_equals "$TEEUP_PATH/share/agents/skills/teeup" "$(readlink "$TEST_HOME/.codex/skills/teeup")" || return 1
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
run_test "path hint prints a macports command that works" test_path_hint_prints_a_macports_command_that_works
run_test "path hint needs an active working line to stop" test_path_hint_needs_an_active_working_line_to_stop
run_test "path hint restores mise's tools when they are kept" test_path_hint_restores_mise_tools_when_they_are_kept
run_test "path hint skips mise when packages are removed" test_path_hint_skips_mise_when_packages_are_removed
run_test "shell notes a failure instead of silence when it cannot read the zshrc" test_shell_notes_a_failure_instead_of_silence_when_it_cannot_read_the_zshrc
run_test "doom theme line removes the marker and the load! line" test_doom_theme_line_removes_the_marker_and_the_load_line
run_test "doom theme line removes an old-style load! line too" test_doom_theme_line_removes_an_old_style_load_line_too
run_test "doom theme line dry run changes nothing" test_doom_theme_line_dry_run_changes_nothing
run_test "doom theme line is a no-op when there is no marker" test_doom_theme_line_is_a_no_op_when_there_is_no_marker
run_test "doom theme line is a no-op with no config.el" test_doom_theme_line_is_a_no_op_with_no_config_el
run_test "doom theme line refuses a symlinked config.el" test_doom_theme_line_refuses_a_symlinked_config_el
run_test "doom theme line honors DOOMDIR" test_doom_theme_line_honors_doomdir
run_test "capabilities keep packages by default and name how to remove them" test_capabilities_keep_packages_by_default_and_name_how_to_remove_them
run_test "package inventory lists metadata software and prints commands that work" test_package_inventory_lists_metadata_software_and_prints_commands_that_work
run_test "package inventory uses only marked capabilities for an installed teeup" test_package_inventory_uses_only_marked_capabilities_for_an_installed_teeup
run_test "capabilities name what the tools made for themselves" test_capabilities_name_what_the_tools_made_for_themselves
run_test "capabilities uninstall packages when asked" test_capabilities_uninstall_packages_when_asked
run_test "capabilities decide each of the seven remove refuses" test_capabilities_decide_each_of_the_seven_remove_refuses
run_test "capabilities refuse what a failed dependent still needs" test_capabilities_refuse_what_a_failed_dependent_still_needs
run_test "capabilities keep the zsh the login shell runs" test_capabilities_keep_the_zsh_the_login_shell_runs
run_test "launchagents are unloaded, removed and checked" test_launchagents_are_unloaded_removed_and_checked
run_test "launchagents refuses a symlinked plist and leaves it" test_launchagents_refuses_a_symlinked_plist_and_leaves_it
run_test "launchagents notes a failure when one is still there after removal" test_launchagents_notes_a_failure_when_one_is_still_there_after_removal
run_test "secrets are named with commands that delete them" test_secrets_are_named_with_commands_that_delete_them
run_test "capabilities name the macports removal steps" test_capabilities_name_the_macports_removal_steps
run_test "capabilities keep macports packages by default and name how to remove them" test_capabilities_keep_macports_packages_by_default_and_name_how_to_remove_them
run_test "configs remove pristine files, keep edited ones and prune empty dirs" test_configs_remove_pristine_files_keep_edited_ones_and_prune_empty_dirs
run_test "configs keep the identity files without --identity" test_configs_keep_the_identity_files_without_identity
run_test "configs leave a generated file teeup did not write" test_configs_leave_a_generated_file_teeup_did_not_write
run_test "configs gpgsign fix works" test_configs_gpgsign_fix_works
run_test "configs names git config lines that reference removed packages" test_configs_names_git_config_lines_that_reference_removed_packages
run_test "configs removes a pristine git config with --identity" test_configs_removes_a_pristine_git_config_with_identity
run_test "configs identity skip survives a changed XDG_CONFIG_HOME" test_configs_identity_skip_survives_a_changed_xdg_config_home
run_test "identity never deletes a regular key and prints a working removal command" test_identity_never_deletes_a_regular_key_and_prints_a_working_removal_command
run_test "identity names a symlinked key and never touches it" test_identity_names_a_symlinked_key_and_never_touches_it
run_test "identity moves local aside and removes the generated identity file" test_identity_moves_local_aside_and_removes_the_generated_identity_file
run_test "identity names a symlinked git/local and leaves it" test_identity_names_a_symlinked_git_local_and_leaves_it
run_test "identity local backup fix avoids a name already taken" test_identity_local_backup_fix_avoids_a_name_already_taken
run_test "teardown removes teeup's command, config and state" test_teardown_removes_teeups_command_config_and_state
run_test "teardown keeps the user's own files in the config dir" test_teardown_keeps_the_users_own_files_in_the_config_dir
run_test "teardown config dir leftover fix removes it" test_teardown_config_dir_leftover_fix_removes_it
run_test "teardown waits for a clean run" test_teardown_waits_for_a_clean_run
run_test "teardown leaves a command that is not teeup's" test_teardown_leaves_a_command_that_is_not_teeups
run_test "teardown refuses a state dir outside HOME, with a fix that works" test_teardown_refuses_a_state_dir_outside_home_with_a_fix_that_works
run_test "teardown keeps everything when the config dir is a symlink" test_teardown_keeps_everything_when_the_config_dir_is_a_symlink
run_test "teardown refuses a state dir with no teeup markers" test_teardown_refuses_a_state_dir_with_no_teeup_markers
run_test "teardown still removes a real state dir" test_teardown_still_removes_a_real_state_dir
run_test "teardown removes a defaults directory macos-defaults leaves behind" test_teardown_removes_a_defaults_directory_macos_defaults_leaves_behind
run_test "teardown removes the terminal-app directory theme-apply leaves behind" test_teardown_removes_the_terminal_app_directory_theme_apply_leaves_behind
run_test "a dry run does not call the terminal-app directory a leftover" test_dry_run_teardown_does_not_call_the_terminal_app_directory_a_leftover
run_test "teardown refuses a state dir that only shares generic names" test_teardown_refuses_a_state_dir_that_only_shares_generic_names
run_test "launchagents refuses a linked LaunchAgents directory" test_launchagents_refuses_a_linked_launchagents_directory
run_test "teardown keeps a file it did not write in the state dir" test_teardown_keeps_a_file_it_did_not_write_in_the_state_dir
run_test "shell handles zsh home files left at an old ZDOTDIR" test_shell_handles_zsh_home_files_left_at_an_old_zdotdir
run_test "configs leaves zsh home files at an old ZDOTDIR for uninstall_shell" test_configs_leaves_zsh_home_files_at_an_old_zdotdir_for_uninstall_shell
run_test "agent_skills removes teeup's own links" test_uninstall_agent_skills_removes_teeups_own_links
run_test "agent_skills keeps a foreign symlink" test_uninstall_agent_skills_keeps_a_foreign_symlink
run_test "agent_skills keeps a file it did not write" test_uninstall_agent_skills_keeps_a_file_it_did_not_write
run_test "agent_skills dry run removes nothing" test_uninstall_agent_skills_dry_run_removes_nothing
print_summary
