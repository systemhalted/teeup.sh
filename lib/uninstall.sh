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

# uninstall_shell
# The first mutation of every uninstall, before any tool the layer hooks
# (mise, starship, zoxide, fzf) is removed: a new shell must never start by
# sourcing a hook for a binary that is already gone. A shell that is running
# already registered those hooks at startup and cannot be unhooked from here,
# which is why cmd_uninstall ends by telling the user to open a new one.
# The files are the ones zsh reads (${ZDOTDIR:-$HOME}), in the order it
# reads them. When any of them changed, uninstall_path_hint says how to keep
# the package manager on PATH without teeup.
uninstall_shell() {
  local dir f before="$_UNINSTALL_REMOVED"
  dir="${ZDOTDIR:-$HOME}"
  for f in .zshenv .zprofile .zshrc; do
    _uninstall_shell_file "$dir/$f"
  done
  if [[ "$_UNINSTALL_REMOVED" != "$before" ]]; then
    uninstall_path_hint
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
  local prefix zprofile line
  zprofile="${ZDOTDIR:-$HOME}/.zprofile"
  prefix="$(pkg_prefix)"
  case "$(pkg_backend)" in
    homebrew)
      [[ "$prefix" != "/usr/local" && -x "$prefix/bin/brew" ]] || return 0
      if _uninstall_active_match "$zprofile" "eval.*$(ere_quote "$prefix/bin/brew shellenv")"; then
        return 0
      fi
      line="eval \"\$($prefix/bin/brew shellenv)\""
      ;;
    macports)
      [[ -x "$prefix/bin/port" ]] || return 0
      if _uninstall_active_match "$zprofile" "PATH=.*$(ere_quote "$prefix/bin")"; then
        return 0
      fi
      line="export PATH=\"$prefix/bin:$prefix/sbin:\$PATH\""
      ;;
  esac
  uninstall_note kept "$(pkg_backend_label) at $prefix. teeup's shell layer put it on PATH; to keep it there in new shells run: echo $(uninstall_q "$line") >> $(uninstall_q "$zprofile")"
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
      _UNINSTALL_KEPT_CASKS="${_UNINSTALL_KEPT_CASKS:+$_UNINSTALL_KEPT_CASKS }$cask"
    fi
  done
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
      uninstall_note kept "Xcode Command Line Tools: git, compilers and the package manager need them. They are macOS's to manage; remove them by hand with: sudo rm -rf /Library/Developer/CommandLineTools"
      ;;
    package-manager)
      case "$(pkg_backend)" in
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
          uninstall_note kept "Your SSH keys and ~/.ssh/config: they are your identity. teeup uninstall --identity removes the keys teeup generated."
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
  local plist label
  for plist in "$HOME/Library/LaunchAgents"/sh.teeup.*.plist; do
    [[ -e "$plist" || -L "$plist" ]] || continue
    label="${plist##*/}"
    label="${label%.plist}"
    if [[ -L "$plist" ]]; then
      uninstall_note refused "LaunchAgent $label: $plist is a symlink, so teeup left it. Unload and delete it with: launchctl bootout gui/$(id -u) $(uninstall_q "$plist"); rm $(uninstall_q "$plist")"
      continue
    fi
    launchagent_remove "$label" || true
    if [[ "$DRY_RUN" != "true" && -e "$plist" ]]; then
      uninstall_note failed "LaunchAgent $label: $plist is still there. Unload and delete it with: launchctl bootout gui/$(id -u) $(uninstall_q "$plist"); rm $(uninstall_q "$plist")"
      continue
    fi
    uninstall_note removed "LaunchAgent $label"
  done
}
