#!/usr/bin/env bash
# uninstall.sh - `teeup uninstall`: take teeup off this Mac.
#
# The run is a fixed sequence of steps (bin/teeup's cmd_uninstall calls them
# in order) and every step reports into one ledger with four columns:
# removed, kept, refused and failed. "Kept" is a policy outcome -- the
# user's edited files, their identity, the package manager, the packages
# unless asked -- and is not a problem. "Refused" is teeup declining to touch
# something it would otherwise have removed (a symlink into a dotfiles repo,
# a path inside a git checkout or outside $HOME), and "failed" is a removal
# that did not happen. Either of the last two makes the verb exit non-zero
# and keeps teeup's own state, config and command in place, so the printed
# rerun command can finish the job once the cause is fixed.
#
# Every deletion goes through uninstall_rm, which reuses lib/migrate.sh's
# safety gates: never outside $HOME, never inside a git checkout, never the
# chezmoi source directory, and a symlink is removed as a link, never
# followed. Every success line is ok_unless_dry after a checked mutation, and
# a line in the "removed" column is only written after the removal was
# verified (or, in a dry run, under a "Would remove" heading).
#
# Requires core.sh, files.sh, state.sh, answers.sh, pkg.sh, ui.sh,
# capability.sh, macos.sh, lazy.sh, hooks.sh and migrate.sh.

# --- the ledger ---------------------------------------------------------------

uninstall_report_reset() {
  _UNINSTALL_REMOVED=""
  _UNINSTALL_KEPT=""
  _UNINSTALL_REFUSED=""
  _UNINSTALL_FAILED=""
}
uninstall_report_reset

# uninstall_note <removed|kept|refused|failed> <text>
uninstall_note() {
  local line="$2"$'\n'
  case "$1" in
    removed) _UNINSTALL_REMOVED="$_UNINSTALL_REMOVED$line" ;;
    kept) _UNINSTALL_KEPT="$_UNINSTALL_KEPT$line" ;;
    refused) _UNINSTALL_REFUSED="$_UNINSTALL_REFUSED$line" ;;
    failed) _UNINSTALL_FAILED="$_UNINSTALL_FAILED$line" ;;
    *) die "uninstall_note: unknown column '$1'" ;;
  esac
}

# uninstall_clean -> 0 when nothing so far was refused or failed.
uninstall_clean() {
  [[ -z "$_UNINSTALL_REFUSED" && -z "$_UNINSTALL_FAILED" ]]
}

_uninstall_section() {
  local title="$1" body="$2" line
  [[ -n "$body" ]] || return 0
  printf '%s\n' "$title"
  while IFS= read -r line; do
    if [[ -n "$line" ]]; then printf '  - %s\n' "$line"; fi
  done <<EOF
$body
EOF
  return 0
}

# uninstall_summary -> prints the ledger; 0 when clean, 1 otherwise.
uninstall_summary() {
  local removed_title="Removed:"
  if [[ "$DRY_RUN" == "true" ]]; then removed_title="Would remove (dry run; nothing was changed):"; fi
  echo ""
  echo "teeup uninstall summary"
  if [[ -z "$_UNINSTALL_REMOVED$_UNINSTALL_KEPT$_UNINSTALL_REFUSED$_UNINSTALL_FAILED" ]]; then
    echo "  Nothing of teeup's was left to remove."
  fi
  _uninstall_section "$removed_title" "$_UNINSTALL_REMOVED"
  _uninstall_section "Kept:" "$_UNINSTALL_KEPT"
  _uninstall_section "Refused (teeup would not touch these; each line says what to do):" "$_UNINSTALL_REFUSED"
  _uninstall_section "Failed:" "$_UNINSTALL_FAILED"
  uninstall_clean
}

# --- asking -------------------------------------------------------------------

# _UNINSTALL_ASK is "true" only on a real run with a terminal and no --yes;
# cmd_uninstall sets it. Everything else takes the default, which is always
# the answer that removes less.
_UNINSTALL_ASK="${_UNINSTALL_ASK:-false}"

# uninstall_ask <question> -> 0 for yes. Defaults to no.
uninstall_ask() {
  [[ "$_UNINSTALL_ASK" == "true" ]] || return 1
  ui_confirm "$1" no
}

# uninstall_q <path> -> <path> quoted for a command line the user can paste
# into bash or zsh (both read bash's %q forms).
uninstall_q() { printf '%q' "$1"; }

# uninstall_active_flags [yes] -> " --packages" and/or " --identity", for
# whichever of _UNINSTALL_PACKAGES and _UNINSTALL_IDENTITY is "true" right
# now, and " --yes" when the caller passes "true" for <yes>. cmd_uninstall
# calls this both before either is asked about (a no-terminal run's flags are
# exactly what was typed) and after (once an answer may have changed them),
# so every rerun or preview command it prints names the flags this run
# actually needs repeated, not just the ones typed on the command line. The
# optional <yes> argument exists because a run that reached this point with
# no terminal only did so because --yes was given (bin/teeup dies before
# here otherwise), so the rerun it names must carry --yes too, or pasting it
# back into that same no-terminal context dies all over again.
uninstall_active_flags() {
  local flags="" yes="${1:-false}"
  if [[ "$_UNINSTALL_PACKAGES" == "true" ]]; then flags="$flags --packages"; fi
  if [[ "$_UNINSTALL_IDENTITY" == "true" ]]; then flags="$flags --identity"; fi
  if [[ "$yes" == "true" ]]; then flags="$flags --yes"; fi
  printf '%s' "$flags"
}

# --- deleting -----------------------------------------------------------------

# uninstall_rm <path> [label]
# The one deletion in `teeup uninstall`. A path that is not there is nothing
# to do. Anything else is resolved (lib/migrate.sh's migrate_resolve, which
# leaves the last component alone so a symlink is removed as a link and never
# followed) and must pass migrate_path_is_safe -- strictly inside the
# physical $HOME, not inside any git checkout, not the chezmoi source -- or
# it is refused with the command that removes it by hand. A directory gets
# rm -rf, anything else rm -f, and the result is checked on disk before it
# is called removed. Notes its own outcome in the ledger.
# 0 removed or nothing there; 1 refused or failed. A caller that does not
# branch on the status writes `|| true`: the outcome is already in the
# ledger, and bin/teeup runs under `set -e`, where a bare call that returned 1
# would end the whole uninstall before its summary.
uninstall_rm() {
  local path="$1" label="${2:-$1}" resolved flag="-f"
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    return 0
  fi
  if [[ -d "$path" && ! -L "$path" ]]; then flag="-rf"; fi
  if ! resolved="$(migrate_resolve "$path")" || ! migrate_path_is_safe "$resolved"; then
    uninstall_note refused "$label: $path is outside your home directory, inside a git checkout or inside the chezmoi source, so teeup did not delete it. Remove it yourself if you mean to: rm $flag $(uninstall_q "$path")"
    return 1
  fi
  if ! run_cmd rm "$flag" "$resolved" 2>/dev/null; then
    uninstall_note failed "$label: could not delete $path. Remove it with: rm $flag $(uninstall_q "$path")"
    return 1
  fi
  if [[ "$DRY_RUN" != "true" ]] && [[ -e "$resolved" || -L "$resolved" ]]; then
    uninstall_note failed "$label: $path is still there after rm. Remove it with: rm $flag $(uninstall_q "$path")"
    return 1
  fi
  ok_unless_dry "Removed $path"
  uninstall_note removed "$label"
  return 0
}

# uninstall_newest_backup <path> -> the newest <path>.teeup_backup_* beside
# it, or nothing. backup names carry a sortable timestamp (lib/files.sh's
# _backup_name), and a glob expands sorted, so the last match is the newest.
uninstall_newest_backup() {
  local f newest=""
  for f in "$1".teeup_backup_*; do
    [[ -e "$f" || -L "$f" ]] || continue
    newest="$f"
  done
  [[ -n "$newest" ]] || return 1
  printf '%s\n' "$newest"
}

# uninstall_offer_restore <path> -> 0 when an earlier copy was put back.
# A pristine teeup file that is about to go may have replaced one of the
# user's own at install time; copy_config_once kept that as
# <path>.teeup_backup_<ts>. On a terminal the user is asked (default no);
# otherwise, and after a no, the command that puts it back is noted instead.
# The mv is checked, and a failed one leaves the teeup file for the caller.
uninstall_offer_restore() {
  local path="$1" backup
  backup="$(uninstall_newest_backup "$path")" || return 1
  if uninstall_ask "Put back your earlier $path from $backup?"; then
    if run_cmd mv "$backup" "$path" 2>/dev/null && [[ -e "$path" || -L "$path" ]]; then
      ok_unless_dry "Put back $path from $backup"
      uninstall_note removed "teeup's $path (your earlier copy is back in its place)"
      return 0
    fi
    uninstall_note failed "$path: could not put $backup back. Do it with: mv $(uninstall_q "$backup") $(uninstall_q "$path")"
    return 1
  fi
  uninstall_note kept "$backup, your copy from before teeup. Put it back with: mv $(uninstall_q "$backup") $(uninstall_q "$path")"
  return 1
}

# --- what is installed --------------------------------------------------------

# uninstall_caps -> every installed capability, dependents before what they
# require (the reverse of cap_order), one per line. TEEUP_SKIP is ignored on
# purpose: a capability the machine file now skips may still have been
# installed before, and it is teeup's all the same.
uninstall_caps() {
  local name installed="" ordered reversed=""
  for name in $(cap_list); do
    if state_done check "cap-$name"; then installed="$installed $name"; fi
  done
  [[ -n "$installed" ]] || return 0
  # shellcheck disable=SC2086  # a word list of capability names
  ordered="$(cap_order $installed)" || return 1
  for name in $ordered; do
    case " $installed " in
      *" $name "*) reversed="$name $reversed" ;;
    esac
  done
  for name in $reversed; do
    printf '%s\n' "$name"
  done
}

# --- the shell layer ----------------------------------------------------------

# uninstall_shell_pattern -> the ERE for a line of teeup's in a zsh home file.
# Three things mark one: the env file line as capabilities/zsh/configure
# renders it (the %q-quoted path of $TEEUP_CONFIG_DIR/env), the same line
# unrendered (a file installed before rendering existed), and TEEUP_PATH,
# which every line that sources the default layer names. A user line that
# names TEEUP_PATH is dead after the uninstall anyway: nothing sets it.
uninstall_shell_pattern() {
  printf '%s|%s|TEEUP_PATH\n' \
    "$(ere_quote "$(printf '%q' "$TEEUP_CONFIG_DIR/env")")" \
    "$(ere_quote '${XDG_CONFIG_HOME:-$HOME/.config}/teeup/env')"
}

# uninstall_shell_live <file> -> 0 when <file> still has a live teeup line:
# one matching uninstall_shell_pattern that is not a comment, not already
# neutralised (": # Disabled by teeup ..."), and not a block opener, which
# disable_matching_lines leaves in place on purpose and which does nothing
# once its body is disabled and TEEUP_PATH is unset. 1 when the file was
# actually read and none of its lines is live. 2 when it could not be
# inspected at all -- unreadable, most often -- which a caller must never
# treat the same as 1: that would leave a live hook in place, silently, while
# later steps remove the binary it hooks.
uninstall_shell_live() {
  local status=0
  if [[ ! -r "$1" ]]; then
    return 2
  fi
  if TEEUP_UNS_PATTERN="$(uninstall_shell_pattern)" TEEUP_UNS_OPENER="$(block_opener_ere)" awk '
    $0 ~ ENVIRON["TEEUP_UNS_PATTERN"] && $0 !~ /^[ \t]*[:#]/ && $0 !~ ENVIRON["TEEUP_UNS_OPENER"] { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$1" 2>/dev/null; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -gt 1 ]]; then
    return 2
  fi
  return "$status"
}

# _uninstall_zshrc_stub -> the ~/.zshrc left in place of a pristine teeup
# copy. A shell must always find one: removing it outright is how the old
# migration nearly left a Mac with no working shell setup at all. It sources
# local.zsh only when that file stays (the user edited it), rendered the
# way capabilities/zsh/configure renders it.
_uninstall_zshrc_stub() {
  local local_zsh
  local_zsh="$(user_config_dir)/zsh/local.zsh"
  echo "# ~/.zshrc - left by teeup uninstall on $(date '+%Y-%m-%d'). teeup's shell"
  echo "# setup is gone; this file is yours, and is here so zsh always has one."
  if [[ -e "$local_zsh" ]] && ! config_is_pristine "$local_zsh"; then
    echo "[ -r $(printf '%q' "$local_zsh") ] && . $(printf '%q' "$local_zsh")"
  fi
}

# _uninstall_shell_file <path>
_uninstall_shell_file() {
  local file="$1" name resolved target backup parsed_before=false live_status=0
  name="${file##*/}"
  [[ -e "$file" || -L "$file" ]] || return 0
  if [[ -L "$file" ]]; then
    target="$(readlink "$file" 2>/dev/null || true)"
    if [[ -f "$file" ]]; then
      if uninstall_shell_live "$file"; then
        uninstall_note refused "$file is a symlink (to $target), so teeup did not write through it. Delete the lines that mention TEEUP_PATH or teeup/env from the file it points to."
      else
        live_status=$?
        if [[ "$live_status" -eq 2 ]]; then
          uninstall_note failed "$file is a symlink (to $target) that teeup could not read, so it could not tell whether the file it points to still needs its lines removed. Check $target by hand for lines mentioning TEEUP_PATH or teeup/env."
        fi
      fi
    fi
    return 0
  fi
  if uninstall_shell_live "$file"; then
    live_status=0
  else
    live_status=$?
  fi
  if [[ "$live_status" -eq 1 ]]; then
    return 0
  fi
  if [[ "$live_status" -eq 2 ]]; then
    uninstall_note failed "$file: teeup could not read it, so it could not check it for lines to remove. Check it by hand for lines mentioning TEEUP_PATH or teeup/env."
    return 0
  fi
  resolved="$(migrate_resolve "$file")" || resolved="$file"
  if migrate_in_git_checkout "$resolved"; then
    uninstall_note refused "$file is inside a git checkout, so teeup did not edit it. Delete the lines that mention TEEUP_PATH or teeup/env yourself."
    return 0
  fi
  if config_is_pristine "$file"; then
    # teeup's own copy, never edited: it goes, and an earlier copy of the
    # user's comes back if they want it.
    if uninstall_offer_restore "$file"; then return 0; fi
    if [[ "$name" != ".zshrc" ]]; then
      uninstall_rm "$file" "teeup's $file" || true
      return 0
    fi
    if _uninstall_zshrc_stub | write_managed_file "$file" "a zshrc of your own"; then
      uninstall_note removed "teeup's $file (a short one of your own is in its place)"
    else
      uninstall_note failed "$file: could not replace teeup's copy; it still sources teeup's shell layer. Edit it by hand."
    fi
    return 0
  fi
  # Edited by the user: their lines stay, teeup's are neutralised in place
  # with a backup beside the file (disable_matching_lines). zsh itself is
  # asked whether the file still parses, when it did before. -f, because
  # without it zsh sources ~/.zshenv first -- teeup's shell layer, running
  # in the middle of its own removal.
  if have zsh && zsh -f -n "$file" 2>/dev/null; then parsed_before=true; fi
  disable_matching_lines "$file" "$(uninstall_shell_pattern)" "teeup uninstall"
  if [[ "$DRY_RUN" == "true" ]]; then
    uninstall_note removed "teeup's lines in $file (your own lines stay)"
    return 0
  fi
  backup="$(uninstall_newest_backup "$file" || true)"
  if uninstall_shell_live "$file"; then
    uninstall_note failed "$file: teeup's lines are still live (see the warnings above). Delete the lines that mention TEEUP_PATH or teeup/env by hand."
    return 0
  else
    live_status=$?
    if [[ "$live_status" -eq 2 ]]; then
      uninstall_note failed "$file: could not be read back after its lines were disabled, so teeup could not confirm none is still live. Check it by hand for lines mentioning TEEUP_PATH or teeup/env; your copy from before is ${backup:-missing}."
      return 0
    fi
  fi
  if [[ "$parsed_before" == "true" ]] && ! zsh -f -n "$file" 2>/dev/null; then
    if [[ -n "$backup" ]] && cat "$backup" > "$file"; then
      uninstall_note failed "$file: zsh could not parse it with teeup's lines disabled, so it was put back as it was. Delete the lines that mention TEEUP_PATH or teeup/env by hand."
    else
      uninstall_note failed "$file: zsh cannot parse it with teeup's lines disabled. Your copy from before is ${backup:-missing}."
    fi
    return 0
  fi
  uninstall_note removed "teeup's lines in $file (your own lines stay; the file as it was is at $backup)"
}

# uninstall_old_zdotdirs <current dir> -> every OTHER directory that holds a
# stock-recorded zsh home file, one per line, each printed once. ZDOTDIR can
# change after install; a stock record for .zshenv, .zprofile or .zshrc at
# the directory it pointed to then is still a zsh home file, wherever it is
# now (Task 5's re-review observation).
uninstall_old_zdotdirs() {
  local current="$1" path dir seen=""
  while IFS= read -r path; do
    case "$path" in
      */.zshenv|*/.zprofile|*/.zshrc) ;;
      *) continue ;;
    esac
    dir="${path%/*}"
    [[ "$dir" != "$current" ]] || continue
    case $'\n'"$seen"$'\n' in *$'\n'"$dir"$'\n'*) continue ;; esac
    seen="$seen$dir"$'\n'
    printf '%s\n' "$dir"
  done <<STOCK
$(uninstall_stock_paths)
STOCK
}

# uninstall_shell
# The first mutation of every uninstall, before any tool the layer hooks
# (mise, starship, zoxide, fzf) is removed: a new shell must never start by
# sourcing a hook for a binary that is already gone. A shell that is running
# already registered those hooks at startup and cannot be unhooked from here,
# which is why cmd_uninstall ends by telling the user to open a new one.
# The files are the ones zsh reads (${ZDOTDIR:-$HOME}), in the order it
# reads them, plus any zsh home file still recorded at an OLD ZDOTDIR (Task
# 5's re-review observation): those must go through this same handling too,
# never uninstall_configs's plain stock-checksum removal. When any of them
# changed, uninstall_path_hint says how to keep the package manager on PATH
# without teeup.
uninstall_shell() {
  local dir f old before="$_UNINSTALL_REMOVED"
  dir="${ZDOTDIR:-$HOME}"
  for f in .zshenv .zprofile .zshrc; do
    _uninstall_shell_file "$dir/$f"
  done
  while IFS= read -r old; do
    [[ -n "$old" ]] || continue
    for f in .zshenv .zprofile .zshrc; do
      _uninstall_shell_file "$old/$f"
    done
  done <<OLD
$(uninstall_old_zdotdirs "$dir")
OLD
  if [[ "$_UNINSTALL_REMOVED" != "$before" ]]; then
    uninstall_path_hint
  fi
}

# uninstall_doom_theme_line
# Final review I5: capabilities/emacs/configure adds one marked line to a
# Doom user's config.el -- the `;; teeup: theme ...` marker and the `load!`
# line right after it (whichever form it takes: the current mode-independent
# loader path, or a per-mode path a teeup from before I3 wrote and never
# rewrote). `load!`'s own noerror argument keeps a leftover line harmless to
# Doom, but it points at a path under $TEEUP_STATE_DIR that uninstall_teardown
# is about to delete, so it is dead once teeup is gone. This takes out exactly
# those two lines and leaves the rest of the file untouched byte for byte,
# including a `-*- lexical-binding: t -*-` cookie the marked block may sit
# right after (configure never moves it, and neither does this).
#
# Emacs's own `remove` script leaves config.el alone on purpose (a plain
# `teeup remove emacs` keeps your configuration); this only runs as part of
# `teeup uninstall`, which is why it lives here rather than in that script,
# and runs before the capability loop, in the same phase as uninstall_shell:
# both edit a file that lives outside the state and stock trees, ahead of
# anything underneath it going away.
uninstall_doom_theme_line() {
  local doom_dir config_el marker disabled_line template_line
  doom_dir="${DOOMDIR:-$(user_config_dir)/doom}"
  config_el="$doom_dir/config.el"
  marker=";; teeup: theme (managed by teeup; remove this line to opt out)"
  disabled_line=";; (setq doom-theme 'doom-one)  ; teeup: disabled Doom's template default so the teeup theme applies"
  template_line="(setq doom-theme 'doom-one)"
  if [[ -L "$config_el" ]]; then
    log "Not editing the symlink $config_el; whatever manages it owns its contents."
    return 0
  fi
  if [[ ! -f "$config_el" ]]; then
    return 0
  fi
  if ! grep -qF "$marker" "$config_el" && ! grep -qF "$disabled_line" "$config_el"; then
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    if grep -qF "$marker" "$config_el"; then
      printf "%b %s\n" "🔍" "[DRY-RUN] Would remove the teeup theme line from $config_el"
    fi
    if grep -qF "$disabled_line" "$config_el"; then
      printf "%b %s\n" "🔍" "[DRY-RUN] Would restore Doom's template default doom-theme in $config_el"
    fi
    return 0
  fi
  if [[ ! -w "$config_el" || ! -w "$doom_dir" ]]; then
    uninstall_note failed "$config_el's teeup theme changes could not be reverted (not writable)."
    return 0
  fi
  local tmp after_marker=false ok=true removed_marker=false restored_template=false
  tmp="$(mktemp)" || { uninstall_note failed "Could not create a temp file, so $config_el was left alone."; return 0; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$after_marker" == true ]]; then
      after_marker=false
      continue
    fi
    if [[ "$line" == "$marker" ]]; then
      after_marker=true
      removed_marker=true
      continue
    fi
    if [[ "$line" == "$disabled_line" ]]; then
      printf '%s\n' "$template_line" >> "$tmp"
      restored_template=true
      continue
    fi
    printf '%s\n' "$line" >> "$tmp"
  done < "$config_el" || ok=false
  if [[ "$ok" == true ]] && mv "$tmp" "$config_el"; then
    if [[ "$removed_marker" == true ]]; then
      uninstall_note removed "The teeup theme line in $config_el"
    fi
    if [[ "$restored_template" == true ]]; then
      uninstall_note removed "Restored Doom's template default doom-theme in $config_el"
    fi
  else
    rm -f "$tmp"
    uninstall_note failed "Could not rewrite $config_el."
  fi
}

# _uninstall_active_match <file> <ere> -> 0 when some active line in <file>
# matches the ERE <ere>: one that has not been commented out, however it is
# indented. A comment is text a shell never runs, so it can never be the
# working line uninstall_path_hint is checking for; a missing or unreadable
# file has no active lines at all.
_uninstall_active_match() {
  local file="$1" pattern="$2"
  [[ -r "$file" ]] || return 1
  TEEUP_UAM_PATTERN="$pattern" awk '
    $0 !~ /^[ \t]*#/ && $0 ~ ENVIRON["TEEUP_UAM_PATTERN"] { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$file" 2>/dev/null
}

# uninstall_path_hint
# teeup's shell layer is what put the package manager on PATH (default/env
# and `brew shellenv` in default/profile). With the layer gone, a new shell
# on Apple Silicon or MacPorts no longer finds brew, port or anything they
# installed, although both stay. The line each package manager documents
# for this is noted, with the command that adds it, unless the user's own
# .zprofile already has an active line that would actually put it there --
# an absolute `<prefix>/bin/brew shellenv` eval for Homebrew, an active PATH
# export naming `<prefix>/bin` for MacPorts. A comment, or a bare
# `brew shellenv` with no prefix (which cannot find Homebrew once teeup's own
# PATH lines are gone), does not count. /usr/local/bin (Intel Homebrew) is on
# macOS's default PATH already.
uninstall_path_hint() {
  local prefix zprofile zshrc line
  zprofile="${ZDOTDIR:-$HOME}/.zprofile"
  zshrc="${ZDOTDIR:-$HOME}/.zshrc"
  prefix="$(pkg_prefix)"
  case "$(pkg_backend)" in
    homebrew)
      if [[ "$prefix" != "/usr/local" && -x "$prefix/bin/brew" ]] && ! _uninstall_active_match "$zprofile" "eval.*$(ere_quote "$prefix/bin/brew shellenv")"; then
        line="eval \"\$($prefix/bin/brew shellenv)\""
        uninstall_note kept "$(pkg_backend_label) at $prefix. teeup's shell layer put it on PATH; to keep it there in new shells run: echo $(uninstall_q "$line") >> $(uninstall_q "$zprofile")"
      fi
      ;;
    macports)
      if [[ -x "$prefix/bin/port" ]] && ! _uninstall_active_match "$zprofile" "PATH=.*$(ere_quote "$prefix/bin")"; then
        line="export PATH=\"$prefix/bin:$prefix/sbin:\$PATH\""
        uninstall_note kept "$(pkg_backend_label) at $prefix. teeup's shell layer put it on PATH; to keep it there in new shells run: echo $(uninstall_q "$line") >> $(uninstall_q "$zprofile")"
      fi
      ;;
  esac
  _uninstall_mise_path_hint "$prefix" "$zshrc"
}

# _uninstall_mise_path_hint <package prefix> <.zshrc path>
# mise's own tools stop resolving in a new shell the same way Homebrew's and
# MacPorts' packages do: capabilities/zsh/default/init ran `mise activate
# zsh`, and default/env put ~/.local/bin and mise's own shims directory on
# PATH. Only printed when mise itself is staying: with --packages, mise is
# uninstalled along with everything else and there is nothing left to
# restore. The activation line is what mise's own docs and
# capabilities/zsh/default/init both run, from mise's resolved absolute path
# rather than a bare `mise` so it works before anything else puts mise back
# on PATH.
_uninstall_mise_path_hint() {
  local prefix="$1" zshrc="$2" mise_bin line local_bin
  [[ "$_UNINSTALL_PACKAGES" != "true" ]] || return 0
  mise_bin="$prefix/bin/mise"
  [[ -x "$mise_bin" ]] || return 0
  if ! _uninstall_active_match "$zshrc" "activate zsh"; then
    line="eval \"\$($mise_bin activate zsh)\""
    uninstall_note kept "mise at $mise_bin. teeup's shell layer ran it for you; to reach its tools in new shells run: echo $(uninstall_q "$line") >> $(uninstall_q "$zshrc")"
  fi
  local_bin="$HOME/.local/bin"
  if ! _uninstall_active_match "$zshrc" "$(ere_quote "$local_bin")"; then
    line="export PATH=\"$local_bin:\$PATH\""
    uninstall_note kept "$local_bin, which teeup's shell layer also put on PATH; to keep it there in new shells run: echo $(uninstall_q "$line") >> $(uninstall_q "$zshrc")"
  fi
}

# --- capabilities ---------------------------------------------------------------

# Set by cmd_uninstall: "true" to uninstall the packages and casks each
# capability's metadata names, "true" to remove the identity as well.
_UNINSTALL_PACKAGES="${_UNINSTALL_PACKAGES:-false}"
_UNINSTALL_IDENTITY="${_UNINSTALL_IDENTITY:-false}"
# Capabilities handled this run (removed, or kept by policy), space-padded.
_UNINSTALL_GONE=" "
# Installed package and cask names left on the machine, for the one "kept"
# line that says how to remove them later.
_UNINSTALL_KEPT_PKGS=""
_UNINSTALL_KEPT_CASKS=""

# uninstall_is_installed -> 0 only when teeup has capability records. The
# directory alone is not enough: a partial or already-removed state directory
# cannot tell us which software teeup installed.
uninstall_is_installed() {
  local marker
  [[ -d "$TEEUP_STATE_DIR" ]] || return 1
  for marker in "$TEEUP_STATE_DIR/done"/cap-*; do
    [[ -e "$marker" ]] && return 0
  done
  return 1
}

# uninstall_login_shell -> the login shell macOS has on record for this user.
uninstall_login_shell() {
  dscl . -read "/Users/${USER:-$(id -un)}" UserShell 2>/dev/null | awk '{print $2}'
}

# uninstall_blockers <name> -> the installed capabilities that still require
# <name> and were not handled this run, space separated (empty when none).
uninstall_blockers() {
  local target="$1" name out=""
  for name in $(cap_list); do
    if [[ "$name" == "$target" ]]; then continue; fi
    case "$_UNINSTALL_GONE" in *" $name "*) continue ;; esac
    state_done check "cap-$name" || continue
    case " $(cap_meta_get "$name" requires) " in
      *" $target "*) out="$out $name" ;;
    esac
  done
  printf '%s\n' "${out# }"
}

# _uninstall_keep_packages <name>
# Adds whichever of <name>'s packages and casks are installed here to the
# kept lists, under the name the package manager knows them by.
_uninstall_keep_packages() {
  local name="$1" pkg candidate cask
  for pkg in $(cap_meta_get "$name" packages); do
    for candidate in $(package_candidates "$pkg"); do
      if pkg_installed "$candidate" >/dev/null 2>&1; then
        case " $_UNINSTALL_KEPT_PKGS " in
          *" $candidate "*) ;;
          *) _UNINSTALL_KEPT_PKGS="${_UNINSTALL_KEPT_PKGS:+$_UNINSTALL_KEPT_PKGS }$candidate" ;;
        esac
        break
      fi
    done
  done
  casks_supported || return 0
  for cask in $(cap_meta_get "$name" casks); do
    if cask_installed "$cask" >/dev/null 2>&1; then
      case " $_UNINSTALL_KEPT_CASKS " in
        *" $cask "*) ;;
        *) _UNINSTALL_KEPT_CASKS="${_UNINSTALL_KEPT_CASKS:+$_UNINSTALL_KEPT_CASKS }$cask" ;;
      esac
    fi
  done
}

# uninstall_collect_packages <marked|all>
# Builds the same package and app lists the kept summary uses. "marked" is
# for an installed teeup and trusts only its capability records. "all" is
# for a machine without those records: it checks every capability's metadata
# so the user can remove matching software by hand without teeup claiming it
# installed any of it.
uninstall_collect_packages() {
  local scope="$1" names name
  _UNINSTALL_KEPT_PKGS=""
  _UNINSTALL_KEPT_CASKS=""
  case "$scope" in
    marked) names="$(uninstall_caps)" ;;
    all) names="$(cap_list)" ;;
    *) die "uninstall_collect_packages: expected marked or all" ;;
  esac
  for name in $names; do
    _uninstall_keep_packages "$name"
  done
}

# uninstall_package_commands -> pasteable commands for the lists most
# recently built by uninstall_collect_packages or uninstall_capabilities.
uninstall_package_commands() {
  if [[ -n "$_UNINSTALL_KEPT_PKGS" ]]; then
    case "$(pkg_backend)" in
      homebrew) printf 'brew uninstall %s\n' "$_UNINSTALL_KEPT_PKGS" ;;
      macports) printf 'sudo port uninstall %s\n' "$_UNINSTALL_KEPT_PKGS" ;;
    esac
  fi
  if [[ -n "$_UNINSTALL_KEPT_CASKS" ]]; then
    printf 'brew uninstall --cask %s\n' "$_UNINSTALL_KEPT_CASKS"
  fi
}

# uninstall_print_package_lists
# Show both categories before the package question, including an explicit
# "none" when no installed metadata item belongs in one of them.
uninstall_print_package_lists() {
  printf 'Packages: %s\n' "${_UNINSTALL_KEPT_PKGS:-none}"
  printf 'Apps: %s\n' "${_UNINSTALL_KEPT_CASKS:-none}"
  # The lists come from capability metadata, not from a record of what teeup
  # itself installed, so software the user brew-installed first shows up too.
  if [[ -n "$_UNINSTALL_KEPT_PKGS$_UNINSTALL_KEPT_CASKS" ]]; then
    warn "teeup lists what its capabilities use, so a package you installed yourself before teeup can be here too. Answer no to keep them all; the summary then prints the commands to remove the rest by hand."
  fi
}

# uninstall_policy <name> -> what uninstall does with a capability that
# `teeup remove` refuses (it ships no remove script and names no packages),
# or "remove" for every other one. Spec amendment 2026-09-25 gives the reason
# for each; the short form is in the kept line each one writes.
uninstall_policy() {
  case "$1" in
    xcode-clt|package-manager|dev-dirs|secrets) echo keep ;;
    ssh) echo identity ;;
    teeup-runtime|theme) echo state ;;
    *) echo remove ;;
  esac
}

# _uninstall_keep_note <name>
_uninstall_keep_note() {
  case "$1" in
    xcode-clt)
      # sudo rm -rf on a system directory is not a command a test runs, even
      # against mocks: no test exercises this printed line.
      uninstall_note kept "Xcode Command Line Tools: git, compilers and the package manager need them. They are macOS's to manage; remove them by hand with: sudo rm -rf /Library/Developer/CommandLineTools"
      ;;
    package-manager)
      case "$(pkg_backend)" in
        # curl | bash, and it uninstalls the package manager itself: not a
        # command a test runs, even against mocks. No test exercises this
        # printed line.
        homebrew) uninstall_note kept "Homebrew: teeup never uninstalls the package manager. Homebrew's own uninstaller is: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)\"" ;;
        macports) uninstall_note kept "MacPorts: teeup never uninstalls the package manager. MacPorts documents its removal at https://guide.macports.org/#installing.macports.uninstalling" ;;
      esac
      ;;
    dev-dirs)
      uninstall_note kept "$HOME/Work: your projects live there."
      ;;
    secrets)
      _uninstall_secrets_note
      ;;
  esac
}

# uninstall_secret_names -> the account name of every login-Keychain item
# stored under the service "teeup" (what `teeup secret set` writes), one per
# line. `security dump-keychain` without -d prints attributes only, never a
# secret, and asks for nothing.
uninstall_secret_names() {
  have security || return 0
  security dump-keychain 2>/dev/null | awk '
    /^keychain: / { if (svce == "teeup" && acct != "") print acct; svce = ""; acct = "" }
    /"svce"<blob>="/ { v = $0; sub(/^.*"svce"<blob>="/, "", v); sub(/"$/, "", v); svce = v }
    /"acct"<blob>="/ { v = $0; sub(/^.*"acct"<blob>="/, "", v); sub(/"$/, "", v); acct = v }
    END { if (svce == "teeup" && acct != "") print acct }
  '
}

# _uninstall_secrets_note -> one kept line naming each teeup secret and the
# command that deletes it. Secrets are the user's data, not teeup's
# configuration, so uninstall never deletes them itself.
_uninstall_secrets_note() {
  local secret names="" cmds=""
  while IFS= read -r secret; do
    [[ -n "$secret" ]] || continue
    names="${names:+$names, }$secret"
    cmds="${cmds:+$cmds; }security delete-generic-password -s teeup -a $(uninstall_q "$secret")"
  done <<EOF
$(uninstall_secret_names)
EOF
  [[ -n "$names" ]] || return 0
  uninstall_note kept "Secrets in your login Keychain ($names). Delete them with: $cmds"
}

# _uninstall_remove_one <name>
_uninstall_remove_one() {
  local name="$1" rc=0 with="$_UNINSTALL_PACKAGES" names login
  names="$(cap_meta_get "$name" packages) $(cap_meta_get "$name" casks)"
  names="$(printf '%s' "$names" | awk '{$1=$1; print}')"
  # The login shell must survive. zsh's packages include zsh itself; when
  # the login shell is the package manager's zsh, uninstalling it would
  # leave Terminal nothing to start. The capability stays marked installed,
  # so the rerun this note names can finish it.
  if [[ "$name" == "zsh" && "$with" == "true" ]]; then
    login="$(uninstall_login_shell)"
    case "$login" in
      "$(pkg_prefix)"/*)
        # chsh changes the account's login shell for real, even under a
        # mock: not a command a test runs. No test exercises this printed
        # line.
        uninstall_note refused "zsh's packages ($names): your login shell is $login, which they provide. Switch to macOS's own zsh first with: chsh -s /bin/zsh, then run: $(uninstall_q "$TEEUP_PATH/bin/teeup") uninstall --packages"
        return 0
        ;;
    esac
  fi
  cap_remove "$name" "$with" || rc=$?
  case "$rc" in
    0)
      _UNINSTALL_GONE="$_UNINSTALL_GONE$name "
      if [[ -f "$(cap_dir "$name")/remove" && "$TEEUP_CAP_NA" != "true" ]]; then
        uninstall_note removed "$name: what its remove script set up"
      fi
      if [[ -n "$names" ]]; then
        if [[ "$with" == "true" ]]; then
          uninstall_note removed "$name's packages: $names"
        else
          _uninstall_keep_packages "$name"
        fi
      fi
      ;;
    2)
      # Nothing teeup tracks for it beyond its own record, which goes with
      # the state directory.
      _UNINSTALL_GONE="$_UNINSTALL_GONE$name "
      ;;
    3)
      uninstall_note failed "$name: its remove script failed (the output above says why), so nothing of it was uninstalled. Fix that, then run: $(uninstall_q "$TEEUP_PATH/bin/teeup") uninstall"
      ;;
    *)
      uninstall_note failed "$name: a package or cask would not uninstall (the output above says which). Fix that, then run: $(uninstall_q "$TEEUP_PATH/bin/teeup") uninstall --packages"
      ;;
  esac
}

# uninstall_capabilities
# Every installed capability, dependents first. A capability another one
# still needs (because that one failed or was refused) is refused in turn:
# pulling the package manager out from under a half-removed capability is
# how a retry becomes impossible.
uninstall_capabilities() {
  local name blockers had
  # Reset here, not just at source time: the ledger globals below must not
  # accumulate if the caller (a test, most likely) runs this twice in one
  # process.
  _UNINSTALL_GONE=" "
  _UNINSTALL_KEPT_PKGS=""
  _UNINSTALL_KEPT_CASKS=""
  had=" $(uninstall_caps | tr '\n' ' ')"
  for name in $had; do
    blockers="$(uninstall_blockers "$name")"
    if [[ -n "$blockers" ]]; then
      uninstall_note refused "$name: still required by $blockers, which could not be removed. It goes on the rerun, once those do."
      continue
    fi
    case "$(uninstall_policy "$name")" in
      keep)
        _uninstall_keep_note "$name"
        _UNINSTALL_GONE="$_UNINSTALL_GONE$name "
        ;;
      identity)
        if [[ "$_UNINSTALL_IDENTITY" != "true" ]]; then
          # No "run teeup uninstall --identity" here: a clean run tears
          # teeup itself down (Decision 11), so that advice would name a
          # command that no longer exists by the time this line is read.
          # teeup never deletes an SSH key either way (2026-09-26 decision);
          # uninstall_identity names each one and how to remove it by hand.
          uninstall_note kept "Your SSH keys and ~/.ssh/config: they are your identity. teeup never deletes an SSH key, with or without --identity."
        fi
        _UNINSTALL_GONE="$_UNINSTALL_GONE$name "
        ;;
      state)
        _UNINSTALL_GONE="$_UNINSTALL_GONE$name "
        ;;
      remove)
        _uninstall_remove_one "$name"
        ;;
    esac
  done
  if [[ -n "$_UNINSTALL_KEPT_PKGS" ]]; then
    case "$(pkg_backend)" in
      homebrew) uninstall_note kept "Packages: $_UNINSTALL_KEPT_PKGS. Remove them later with: brew uninstall $_UNINSTALL_KEPT_PKGS" ;;
      macports) uninstall_note kept "Packages: $_UNINSTALL_KEPT_PKGS. Remove them later with: sudo port uninstall $_UNINSTALL_KEPT_PKGS" ;;
    esac
  fi
  if [[ -n "$_UNINSTALL_KEPT_CASKS" ]]; then
    uninstall_note kept "Apps: $_UNINSTALL_KEPT_CASKS. Remove them later with: brew uninstall --cask $_UNINSTALL_KEPT_CASKS"
  fi
  # What a tool made for itself was never teeup's to track, so it is named
  # rather than silently left behind.
  case "$had" in
    *" mise "*|*" emacs "*|*" zed "*|*" vscode "*)
      uninstall_note kept "What the tools made for themselves: runtimes mise installed (${MISE_DATA_DIR:-$HOME/.local/share/mise}), a Doom or Spacemacs checkout, and the theme and font keys teeup set inside Zed's and VS Code's own settings."
      ;;
  esac
  return 0
}

# uninstall_launchagents
# Every sh.teeup.* agent still in ~/Library/LaunchAgents: the capability
# loop's remove scripts took their own (emacs, keyboard), so anything here
# belongs to a capability no longer marked installed. Unloaded and deleted
# through launchagent_remove, then checked on disk.
uninstall_launchagents() {
  local plist label rc
  for plist in "$HOME/Library/LaunchAgents"/sh.teeup.*.plist; do
    [[ -e "$plist" || -L "$plist" ]] || continue
    label="${plist##*/}"
    label="${label%.plist}"
    if [[ -L "$plist" ]]; then
      uninstall_note refused "LaunchAgent $label: $plist is a symlink, so teeup left it. Unload and delete it with: launchctl bootout gui/$(id -u) $(uninstall_q "$plist"); rm $(uninstall_q "$plist")"
      continue
    fi
    rc=0
    launchagent_remove "$label" 2>/dev/null || rc=$?
    if [[ "$rc" -eq 2 ]]; then
      uninstall_note refused "LaunchAgent $label: $plist sits in a linked LaunchAgents directory, so teeup left it. Unload and delete it with: launchctl bootout gui/$(id -u) $(uninstall_q "$plist"); rm $(uninstall_q "$plist")"
      continue
    fi
    if [[ "$DRY_RUN" != "true" && -e "$plist" ]]; then
      uninstall_note failed "LaunchAgent $label: $plist is still there. Unload and delete it with: launchctl bootout gui/$(id -u) $(uninstall_q "$plist"); rm $(uninstall_q "$plist")"
      continue
    fi
    uninstall_note removed "LaunchAgent $label"
  done
}

# uninstall_agent_skills
# The reverse of agent_skill_link (lib/files.sh): removes the "teeup" symlink
# it created in every agent CLI's skill directory it found. Ownership is
# decided the same way agent_skill_link decides it -- by where the symlink
# resolves, physically on both sides, not by how its path looks -- so a fork
# or a user's own skills repository laid out the same way is left alone, and
# so is anything at that name that is not a symlink at all: somebody else's
# skill, or their own file. uninstall_rm gives the removal itself the same
# safety gate and dry-run behaviour every other deletion in this file gets.
uninstall_agent_skills() {
  local dir target current resolved_src resolved_current
  resolved_src="$(cd -P "$TEEUP_PATH/share/agents/skills/teeup" 2>/dev/null && pwd -P)" || resolved_src=""
  for dir in "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.gemini/skills"; do
    target="$dir/teeup"
    [[ -e "$target" || -L "$target" ]] || continue
    if [[ ! -L "$target" ]]; then
      uninstall_note kept "$target: it is not a symlink teeup wrote."
      continue
    fi
    current="$(readlink "$target" 2>/dev/null || true)"
    resolved_current="$(cd -P "$(dirname "$target")" 2>/dev/null && cd -P "$current" 2>/dev/null && pwd -P)" || resolved_current=""
    if [[ -z "$resolved_src" || -z "$resolved_current" || "$resolved_current" != "$resolved_src" ]]; then
      uninstall_note kept "$target: a symlink to $current, not this checkout's own skill; teeup left it."
      continue
    fi
    uninstall_rm "$target" "the agent skill link ($target)" || true
  done
}

# --- configuration files --------------------------------------------------------

# uninstall_stock_paths -> every file teeup holds a stock record for, one per
# line: the reverse of lib/files.sh's _stock_record_path, which names a record
# after the path relative to $HOME with "/" turned into "__" (an absolute
# path, outside $HOME, keeps its leading "/" and so starts with "__"). This is
# every file copy_config_once, refresh_config or refresh_if_pristine ever
# installed, whichever capability did it and wherever it went. Nearly every
# record name starts with a dot (.config__..., .zshrc), which a plain * does
# not match, hence the two extra globs.
uninstall_stock_paths() {
  local record rel
  for record in "$TEEUP_STATE_DIR/stock"/* "$TEEUP_STATE_DIR/stock"/.[!.]* "$TEEUP_STATE_DIR/stock"/..?*; do
    [[ -f "$record" ]] || continue
    rel="${record##*/}"
    case "$rel" in
      __*) replace_literal "$rel" "__" "/" ;;
      *) printf '%s/%s\n' "$HOME" "$(replace_literal "$rel" "__" "/")" ;;
    esac
  done
}

# _uninstall_prune_dirs <removed file>
# Directories the removal left empty go too, walking up, but never $HOME
# itself or the XDG config directory. rmdir removes only an empty directory,
# so anything of the user's stops the walk. The config directory's own
# trailing slash (a $XDG_CONFIG_HOME set with one) is stripped before the
# comparison, or it would never match $dir and the walk could reach into
# $HOME itself.
_uninstall_prune_dirs() {
  local dir config
  if [[ "$DRY_RUN" == "true" ]]; then return 0; fi
  dir="$(dirname "$1")"
  config="$(user_config_dir)"
  config="${config%/}"
  while [[ "$dir" == "$HOME"/* && "$dir" != "$config" ]]; do
    rmdir "$dir" 2>/dev/null || break
    dir="$(dirname "$dir")"
  done
}

# _uninstall_generated <file> <label>
# A file teeup generates in full (git's identity and teeup-generated) says so
# on its first line and is overwritten on every configure, so it is teeup's
# whatever it holds. Without that line it is not a file teeup wrote.
_uninstall_generated() {
  local file="$1" label="$2"
  [[ -e "$file" || -L "$file" ]] || return 0
  if [[ ! -L "$file" ]] && head -n 1 "$file" 2>/dev/null | grep -q '^# Generated by teeup'; then
    uninstall_rm "$file" "$label" || true
  else
    uninstall_note kept "$file: teeup did not write it."
  fi
}

# _uninstall_is_identity_config <path> -> 0 when <path> is one of the files
# that carry the user's identity (~/.ssh/config or <config dir>/git/config),
# decided from the recorded path's own tail rather than by comparing it
# against the CURRENT XDG_CONFIG_HOME: a stock record written under one
# XDG_CONFIG_HOME must still be recognised when uninstall later runs with
# another (or with none set at all).
_uninstall_is_identity_config() {
  case "$1" in
    */.ssh/config|*/git/config) return 0 ;;
    *) return 1 ;;
  esac
}

# _uninstall_git_config_removed_packages_note <path to git/config>
# --packages can uninstall git-delta, git-lfs and gh (capabilities/git and
# capabilities/github's own packages) while a kept git/config -- edited, or
# pristine and kept because --identity was not given -- still sets
# core.pager and interactive.diffFilter to delta, the lfs clean/smudge/
# process filter, and the GitHub and gist credential helpers to
# `gh auth git-credential` (capabilities/git/config/git/config). Read from
# the file itself rather than tracked per capability, so an edit that added
# the same settings by hand is caught the same way. Only fires when
# --packages actually removes something (without it nothing on the machine
# changed, so the settings still work).
_uninstall_git_config_removed_packages_note() {
  local file="$1" refs="" cmds="" val host
  [[ "$_UNINSTALL_PACKAGES" == "true" ]] || return 0
  [[ -f "$file" ]] || return 0
  val="$(git config --file "$file" --get core.pager 2>/dev/null || true)"
  if [[ "$val" == "delta" ]]; then
    refs="${refs:+$refs, }core.pager = $val"
    cmds="${cmds:+$cmds; }git config --file $(uninstall_q "$file") --unset core.pager"
  fi
  val="$(git config --file "$file" --get interactive.diffFilter 2>/dev/null || true)"
  case "$val" in
    delta*)
      refs="${refs:+$refs, }interactive.diffFilter = $val"
      cmds="${cmds:+$cmds; }git config --file $(uninstall_q "$file") --unset interactive.diffFilter"
      ;;
  esac
  if git config --file "$file" --get-regexp '^filter\.lfs\.' >/dev/null 2>&1; then
    refs="${refs:+$refs, }filter.lfs"
    cmds="${cmds:+$cmds; }git config --file $(uninstall_q "$file") --remove-section filter.lfs"
  fi
  for host in github.com gist.github.com; do
    val="$(git config --file "$file" --get "credential.https://$host.helper" 2>/dev/null || true)"
    if [[ "$val" == "!gh auth git-credential" ]]; then
      refs="${refs:+$refs, }credential.https://$host.helper = $val"
      cmds="${cmds:+$cmds; }git config --file $(uninstall_q "$file") --unset-all credential.https://$host.helper"
    fi
  done
  [[ -n "$refs" ]] || return 0
  uninstall_note kept "$file still sets $refs, which --packages just removed the tools for. Remove those settings with: $cmds"
}

# uninstall_configs
# The stock-checksum rule (spec section 9) decides every file teeup copied:
# pristine, it is teeup's and goes (after offering back whatever it replaced);
# edited, it is the user's and stays. Every zsh home file is skipped here by
# name, wherever it is recorded -- at the current ZDOTDIR or an old one -- as
# uninstall_shell already handled it (or, for an old ZDOTDIR, handles it
# itself; Task 5's re-review observation, and this is where the plain
# stock-checksum removal below would otherwise have caught it). ~/.ssh/config
# waits for --identity; ~/.config/git/config does not -- the user's decision
# is that git/config is kept only WITHOUT --identity (Decision 8), so a
# pristine one goes here, like any other file, once --identity is given.
uninstall_configs() {
  local path gdir key edited="" id_files=""
  gdir="$(user_config_dir)/git"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    case "$path" in
      */.zshenv|*/.zprofile|*/.zshrc) continue ;;
    esac
    if [[ "$_UNINSTALL_IDENTITY" != "true" ]] && _uninstall_is_identity_config "$path"; then
      continue
    fi
    if [[ -L "$path" ]]; then
      uninstall_note kept "$path is a symlink; teeup does not touch it."
      continue
    fi
    if [[ -d "$path" ]]; then
      uninstall_note kept "$path is a directory where teeup installed a file; it is left alone."
      continue
    fi
    [[ -e "$path" ]] || continue
    if config_is_pristine "$path"; then
      if uninstall_offer_restore "$path"; then continue; fi
      if uninstall_rm "$path" "teeup's $path"; then _uninstall_prune_dirs "$path"; fi
    else
      edited="${edited:+$edited, }$path"
    fi
  done <<STOCK
$(uninstall_stock_paths)
STOCK
  if [[ -n "$edited" ]]; then
    uninstall_note kept "Config files you edited: $edited"
  fi
  _uninstall_generated "$gdir/teeup-generated" "teeup's generated git settings ($gdir/teeup-generated)"
  if [[ "$_UNINSTALL_IDENTITY" != "true" ]]; then
    # Not "run teeup uninstall --identity": a clean run tears teeup itself
    # down (Decision 11), so naming that command here would point at
    # something already gone by the time this line is read. Named only when
    # at least one is actually there: nothing was ever configured on a
    # machine that never ran `teeup configure git`, and a rerun after a
    # clean uninstall must not keep repeating a note about files that do
    # not exist.
    if [[ -e "$gdir/config" ]]; then id_files="$gdir/config"; fi
    if [[ -e "$gdir/identity" ]]; then id_files="${id_files:+$id_files and }$gdir/identity"; fi
    if [[ -n "$id_files" ]]; then
      uninstall_note kept "$id_files: git reads your name and email through them, so teeup leaves them in place without --identity."
    fi
  fi
  if [[ -f "$gdir/config" ]]; then
    # teeup-generated turned signing off until a key existed; if the key is
    # missing for any reason the shipped config's gpgsign = true is back in
    # charge, and signing with no key fails every commit -- with or without
    # --identity, since teeup never deletes a key either way.
    key="$(identity_key personal)"
    if [[ "$(git config --file "$gdir/config" --type=bool --get commit.gpgsign 2>/dev/null)" == "true" ]] && [[ ! -f "$key" || ! -f "$key.pub" ]]; then
      uninstall_note kept "Commit signing is on in $gdir/config but $key is missing, so git commit would fail. Turn signing off with: git config --file $(uninstall_q "$gdir/config") commit.gpgsign false"
    fi
  fi
  _uninstall_git_config_removed_packages_note "$gdir/config"
}

# uninstall_identity
# Only with --identity. teeup never deletes an SSH key, with or without this
# flag (2026-09-26 decision): a key at teeup's own naming convention
# (~/.ssh/id_ed25519_<identity>) may be one teeup generated, one it adopted
# because the user already had it there (capabilities/ssh/configure logs
# "Already present" and changes nothing about it), or one restored from a
# backup since -- teeup keeps no record telling those cases apart, and
# guessing wrong destroys a private key nothing else may hold a copy of.
# Every key found is named in the ledger instead, with the exact commands
# that drop its Keychain passphrase and move it aside by hand; a symlink is
# only named, never followed or touched. git's identity file is generated and
# goes; ~/.config/git/local is the user's own and is moved aside, never
# deleted -- and left alone entirely when it is itself a symlink.
uninstall_identity() {
  local id key flag="--apple-use-keychain" major gdir backup local_backup
  local key_backup pub_backup cmd
  major="$(macos_major)"
  if [[ "$major" =~ ^[0-9]+$ && "$major" -lt 12 ]]; then flag="-K"; fi
  for id in personal work; do
    key="$HOME/.ssh/id_ed25519_$id"
    if [[ -L "$key" ]]; then
      uninstall_note kept "$key is a symlink; teeup does not touch it. Remove it yourself if you mean to."
      continue
    fi
    [[ -e "$key" || -e "$key.pub" ]] || continue
    cmd="ssh-add -d $flag $(uninstall_q "$key") 2>/dev/null"
    if [[ -e "$key" ]]; then
      key_backup="$(_backup_name "$key")"
      cmd="$cmd; mv $(uninstall_q "$key") $(uninstall_q "$key_backup")"
    fi
    if [[ -e "$key.pub" ]]; then
      pub_backup="$(_backup_name "$key.pub")"
      cmd="$cmd; mv $(uninstall_q "$key.pub") $(uninstall_q "$pub_backup")"
    fi
    uninstall_note kept "$key: teeup never deletes an SSH key. Remove it yourself: $cmd"
  done
  gdir="$(user_config_dir)/git"
  _uninstall_generated "$gdir/identity" "your git identity ($gdir/identity)"
  if [[ -L "$gdir/local" ]]; then
    uninstall_note kept "$gdir/local is a symlink; teeup does not move it."
  elif [[ -e "$gdir/local" ]]; then
    if backup="$(backup_target "$gdir/local")"; then
      uninstall_note removed "$gdir/local (moved to $backup, since teeup never wrote it)"
    else
      # A fixed ".old" name would silently clobber (or be swallowed into) an
      # earlier failed attempt's leftovers; _backup_name (lib/files.sh) is
      # the same collision-checked naming backup_target itself would have
      # used had it succeeded.
      local_backup="$(_backup_name "$gdir/local")"
      uninstall_note failed "$gdir/local: could not move it aside. Move it yourself with: mv $(uninstall_q "$gdir/local") $(uninstall_q "$local_backup")"
    fi
  fi
  uninstall_note kept "Public keys teeup uploaded to GitHub: they stay on your account. Delete them at https://github.com/settings/keys"
}

# --- teeup itself -----------------------------------------------------------------

# _uninstall_config_dir
# $TEEUP_CONFIG_DIR holds teeup's env file, the answers and the hook samples,
# and may hold the user's own: a personal machine file, hooks, themes,
# template overrides. teeup's go; the directory goes only when nothing of
# the user's is left in it.
_uninstall_config_dir() {
  local dir="$TEEUP_CONFIG_DIR" teeup_files event f mine="" left=""
  [[ -e "$dir" || -L "$dir" ]] || return 0
  if [[ -L "$dir" ]]; then
    uninstall_note refused "$dir is a symlink, so teeup did not touch it or what it points to. Remove it yourself if you mean to: rm $(uninstall_q "$dir")"
    return 0
  fi
  teeup_files="$dir/env"$'\n'"$dir/answers"
  for event in $TEEUP_HOOK_EVENTS; do
    teeup_files="$teeup_files"$'\n'"$dir/hooks/$event.d/example.sample"
  done
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    case $'\n'"$teeup_files"$'\n' in
      *$'\n'"$f"$'\n'*) mine="${mine:+$mine$'\n'}$f" ;;
      *) left="${left:+$left, }${f#"$dir"/}" ;;
    esac
  done <<FILES
$(find "$dir" \( -type f -o -type l \) -print 2>/dev/null)
FILES
  if [[ -z "$left" ]]; then
    uninstall_rm "$dir" "teeup's config ($dir)" || true
    return 0
  fi
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if uninstall_rm "$f" "teeup's $f"; then _uninstall_prune_dirs "$f"; fi
  done <<MINE
$mine
MINE
  uninstall_note kept "Your own files in $dir: $left. Delete them with: rm -rf $(uninstall_q "$dir")"
}

# uninstall_mark_state_dir
# Decides, once and before anything is removed, whether $TEEUP_STATE_DIR is
# recognisably teeup's: its done/ holds at least one cap-<name> install
# marker as a plain file. Generic names alone prove nothing -- mise's own
# ~/.local/share/mise has shims/ and migrations/ -- and TEEUP_STATE_DIR is a
# user-settable override, so a careless one must never lead to teeup
# deleting a directory it does not own. Called by cmd_uninstall before the
# capabilities are removed, since removing them clears those very markers;
# uninstall_teardown asks on its own when nothing asked earlier.
uninstall_mark_state_dir() {
  local marker
  _UNINSTALL_STATE_OWNED=false
  for marker in "$TEEUP_STATE_DIR"/done/cap-*; do
    if [[ -f "$marker" && ! -L "$marker" ]]; then
      _UNINSTALL_STATE_OWNED=true
      return 0
    fi
  done
  return 0
}

# _UNINSTALL_STATE_ENTRIES lists every top-level name teeup itself writes
# under $TEEUP_STATE_DIR, one place both loops in _uninstall_state_dir read
# from -- add a name here, and it is both removed and no longer counted as a
# leftover. Named after their writers: done/na/toggles/migrations
# (lib/state.sh), current (lib/theme.sh, lib/font.sh), shims (lib/lazy.sh),
# stock (lib/files.sh), logs (lib/core.sh's TEEUP_LOG_FILE default and
# bin/teeup), defaults (lib/macos.sh's _defaults_record_path), terminal-app
# (capabilities/terminal-app/theme-apply's exported .terminal files, final
# review I5). CONTRIBUTING.md item 33 says a new one belongs here too.
_UNINSTALL_STATE_ENTRIES="done na toggles migrations stock shims current logs defaults terminal-app ca-bundle.pem ca-bundle.curlrc"

# _uninstall_is_state_entry <name> -> 0 when <name> is one of
# _UNINSTALL_STATE_ENTRIES.
_uninstall_is_state_entry() {
  local name="$1" entry
  for entry in $_UNINSTALL_STATE_ENTRIES; do
    if [[ "$entry" == "$name" ]]; then
      return 0
    fi
  done
  return 1
}

# _uninstall_state_dir
# Removes only the entries teeup itself writes under $TEEUP_STATE_DIR, then
# the directory once it is empty. Anything else in there is not teeup's and
# stays, named, so the directory stays with it.
_uninstall_state_dir() {
  local name left=""
  for name in $_UNINSTALL_STATE_ENTRIES; do
    uninstall_rm "$TEEUP_STATE_DIR/$name" "teeup's $name records ($TEEUP_STATE_DIR/$name)" || true
  done
  for name in "$TEEUP_STATE_DIR"/* "$TEEUP_STATE_DIR"/.[!.]* "$TEEUP_STATE_DIR"/..?*; do
    if [[ -e "$name" || -L "$name" ]]; then
      # A dry run leaves teeup's own entries in place; they are not leftovers.
      if _uninstall_is_state_entry "${name##*/}"; then
        continue
      fi
      left="$left ${name##*/}"
    fi
  done
  if [[ -n "$left" ]]; then
    uninstall_note kept "$TEEUP_STATE_DIR holds files teeup did not write ($left ), so it stays. Delete it yourself if you mean to: rm -rf $(uninstall_q "$TEEUP_STATE_DIR")"
  elif [[ -d "$TEEUP_STATE_DIR" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      uninstall_note removed "$TEEUP_STATE_DIR"
    elif rmdir "$TEEUP_STATE_DIR" 2>/dev/null; then
      uninstall_note removed "$TEEUP_STATE_DIR"
    else
      uninstall_note failed "$TEEUP_STATE_DIR could not be removed. Run: rmdir $(uninstall_q "$TEEUP_STATE_DIR")"
    fi
  fi
}

# uninstall_teardown
# Last, and only after a clean run: the teeup command, $TEEUP_CONFIG_DIR and
# $TEEUP_STATE_DIR. They are what a rerun needs -- the stock records that
# tell a pristine file from an edited one, the install markers, the recorded
# `defaults` values -- so after any refusal or failure they stay.
uninstall_teardown() {
  local link="$HOME/.local/bin/teeup" target d resolved
  if ! uninstall_clean; then
    uninstall_note kept "teeup's own state ($TEEUP_STATE_DIR), config ($TEEUP_CONFIG_DIR) and command: something above was refused or failed, and the rerun needs them."
    return 0
  fi
  # Every target is checked before any is deleted. A clean run can still meet
  # a refusal here -- a symlinked config dir, a state dir outside $HOME --
  # and deleting the command first, then refusing the config, then deleting
  # the state anyway breaks the promise that all three stay after any
  # problem (Codex, on this plan). The same checks uninstall_rm makes, done
  # up front.
  for d in "$TEEUP_CONFIG_DIR" "$TEEUP_STATE_DIR"; do
    [[ -e "$d" || -L "$d" ]] || continue
    if [[ -L "$d" ]] || ! resolved="$(migrate_resolve "$d")" || ! migrate_path_is_safe "$resolved"; then
      uninstall_note refused "$d is a symlink, outside your home directory, inside a git checkout or inside the chezmoi source, so teeup did not delete it -- nor teeup's state ($TEEUP_STATE_DIR), config ($TEEUP_CONFIG_DIR) or command, which a rerun needs. Remove it yourself if you mean to: rm -rf $(uninstall_q "$d")"
      return 0
    fi
  done
  # Only a state dir that uninstall_mark_state_dir recognised is emptied
  # below; anything else is left alone whole, with the config and command.
  if [[ -z "${_UNINSTALL_STATE_OWNED:-}" ]]; then
    uninstall_mark_state_dir
  fi
  if [[ -e "$TEEUP_STATE_DIR" && "$_UNINSTALL_STATE_OWNED" != "true" ]]; then
    uninstall_note kept "$TEEUP_STATE_DIR does not look like teeup's own state (no cap-* install marker in its done/ directory), so teeup left it alone, along with its config ($TEEUP_CONFIG_DIR) and command. Delete it yourself if you mean to: rm -rf $(uninstall_q "$TEEUP_STATE_DIR")"
    return 0
  fi
  # Config and state first, each followed by a fresh check, so a failure
  # stops the teardown; the command last, since it is what a rerun calls.
  _uninstall_config_dir
  if ! uninstall_clean; then
    uninstall_note kept "teeup's state ($TEEUP_STATE_DIR) and command: removing the config did not finish cleanly, and the rerun needs them."
    return 0
  fi
  _uninstall_state_dir
  if ! uninstall_clean; then
    uninstall_note kept "the teeup command: removing the state did not finish cleanly, and the rerun needs it."
    return 0
  fi
  if [[ -L "$link" ]]; then
    target="$(readlink "$link" 2>/dev/null || true)"
    if [[ "$target" == "$TEEUP_PATH/bin/teeup" ]]; then
      uninstall_rm "$link" "the teeup command ($link)" || true
    else
      uninstall_note kept "$link: it points at $target, not at this checkout."
    fi
  elif [[ -e "$link" ]]; then
    uninstall_note kept "$link: it is a file, not teeup's link."
  fi
}
