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
