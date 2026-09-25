#!/usr/bin/env bash
# migrate.sh - `teeup migrate legacy`: retire this teeup's predecessors on a
# machine that already had one. Spec section 10.
#
# Two predecessors exist. The old monolithic teeup.sh wrote ~/.teeup.common,
# ~/.config/mac-setup and a handful of ~/.<name> symlinks, and appended blocks
# to the shell rc files that source them. The chezmoi repo at
# ~/Work/environment/dotfiles still owns $HOME on machines that ran it, and it
# still serves Linux, so it is never deleted, never purged, and never even
# written to: this file only ever reads from chezmoi.
#
# Everything this file deletes is named by a KEY, never by a path. migrate_rm
# takes a key and asks migrate_target for the path itself, so the set of
# deletable things is fixed by the case statement below and no caller can
# widen it. Three further gates run on the resolved path anyway, because an
# XDG_CONFIG_HOME override or a symlinked ~/.config can still make a key land
# somewhere it must not.
#
# Requires core.sh, files.sh, state.sh, ui.sh.

# The rc files every predecessor wrote into, relative to $HOME, in the order
# they are visited. Names only: each step joins them to $HOME itself. Exported
# like TEEUP_MIGRATIONS_DIR and the rest of teeup's module variables, so a
# capability script or a migration can read the same list.
TEEUP_MIGRATE_RC_FILES=".zshenv .zprofile .zshrc .bashrc .bash_profile .profile"
export TEEUP_MIGRATE_RC_FILES

# migrate_target <key> -> the absolute path that key names
# The closed list. Anything that is not one of these five keys has no path, so
# migrate_rm can never be pointed at it -- the sibling chezmoi checkout
# included. Returns 1 and prints nothing for an unknown key.
migrate_target() {
  case "$1" in
    teeup-common)   printf '%s\n' "$HOME/.teeup.common" ;;
    teeupshrc)      printf '%s\n' "$HOME/.teeupshrc" ;;
    shellrc-common) printf '%s\n' "$HOME/.shellrc.common" ;;
    mac-setup)      printf '%s\n' "$(user_config_dir)/mac-setup" ;;
    chezmoi-config) printf '%s\n' "$(user_config_dir)/chezmoi" ;;
    *) return 1 ;;
  esac
}

# chezmoi_ro <subcommand> [args...]
# The only place in teeup that runs chezmoi, and it runs only read-only
# subcommands. `chezmoi purge` "removes chezmoi's configuration, state, and
# source directory" (chezmoi reference, purge), which is the sibling repo, so
# it is not on the list and cannot be reached from anywhere -- including a
# capability's doctor script, which sources this file like everything else.
# tests/lib/migrate.sh greps bin/, lib/ and capabilities/ for a second call
# site, because this guarantee lasts exactly as long as this is the only one.
# An unlisted subcommand is a programming error, not a user mistake, so it
# dies rather than warning.
chezmoi_ro() {
  case "${1:-}" in
    managed|source-path|--version) ;;
    *) die "teeup only runs read-only chezmoi subcommands; '${1:-}' is not one of managed, source-path, --version." ;;
  esac
  command chezmoi "$@"
}

# migrate_chezmoi_source -> the physical chezmoi source directory, or nothing
# Two different answers share the empty output, and migrate_path_is_safe has
# to tell them apart, so the exit status carries the difference:
#   0 with output    -- this is the source directory
#   0 with no output -- chezmoi is not installed, so there is no repo to guard
#   1                -- chezmoi is here but teeup could not find out where its
#                       source is, which is NOT the same as there being none
# Physical form (pwd -P), so a symlinked path cannot slip past the string
# comparisons in migrate_path_is_safe.
migrate_chezmoi_source() {
  local src
  have chezmoi || return 0
  src="$(chezmoi_ro source-path 2>/dev/null)" || return 1
  [[ -n "$src" ]] || return 1
  src="$(cd "$src" 2>/dev/null && pwd -P)" || return 1
  printf '%s\n' "$src"
}

# migrate_resolve <path> -> the path with its parent resolved
# Every symlink ABOVE the last component is resolved; the last component is
# left exactly as it is, so a dangling or foreign symlink can be removed
# without following it to whatever it points at. Returns 1 when the parent
# directory does not exist (macOS has no readlink -f, hence cd + pwd -P).
migrate_resolve() {
  local path="$1" parent base
  parent="$(dirname "$path")"
  base="$(basename "$path")"
  parent="$(cd "$parent" 2>/dev/null && pwd -P)" || return 1
  [[ -n "$parent" ]] || return 1
  case "$parent" in
    /) printf '/%s\n' "$base" ;;
    *) printf '%s/%s\n' "$parent" "$base" ;;
  esac
}

# migrate_in_git_checkout <resolved-path>
# 0 when some directory between <resolved-path> and $HOME holds a .git entry.
# A user's repositories live under $HOME, the sibling chezmoi checkout among
# them, and a key that resolves inside one must be refused whatever chezmoi
# says about it -- an `rm -rf` inside a git repository is the outcome this
# whole file exists to make impossible. Walks upwards and stops at $HOME, so a
# .git above $HOME (a dotfiles-managed home directory) is not treated as one
# of the user's project checkouts.
migrate_in_git_checkout() {
  local path="$1" home dir
  home="$(cd "$HOME" 2>/dev/null && pwd -P)" || return 1
  dir="$(dirname "$path")"
  while [[ "$dir" != "$home" && "$dir" != "/" && -n "$dir" ]]; do
    if [[ -e "$dir/.git" ]]; then
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# migrate_path_is_safe <resolved-path>
# 0 when teeup's migration may delete it. Four refusals:
#   - not strictly inside the physical $HOME (so never /, never $HOME itself,
#     never anything in /etc or another user's home);
#   - a ".." component survived resolution;
#   - chezmoi is installed but teeup could not determine its source
#     directory. Failing open there is what would let a later run delete
#     inside the repo: "I could not find out" is not "there is nothing to
#     protect", so nothing is removed until it can be established;
#   - it is the chezmoi source directory, something inside it, a directory
#     that contains it, or anything inside any other git checkout under
#     $HOME. That is what keeps ~/Work/environment/dotfiles -- still serving
#     Linux -- out of reach even when a key resolves into it through a
#     symlinked ~/.config.
migrate_path_is_safe() {
  local path="$1" home src src_rc=0
  home="$(cd "$HOME" 2>/dev/null && pwd -P)" || return 1
  case "$path" in
    "$home") return 1 ;;
    "$home"/*) ;;
    *) return 1 ;;
  esac
  case "$path" in
    */..|*/../*) return 1 ;;
  esac
  src="$(migrate_chezmoi_source)" || src_rc=$?
  if [[ "$src_rc" -ne 0 ]]; then
    warn "chezmoi is installed but teeup could not determine its source directory, so it cannot tell whether a path is inside it. Nothing will be removed until that is established."
    return 1
  fi
  if [[ -n "$src" ]]; then
    case "$path" in
      "$src"|"$src"/*) return 1 ;;
    esac
    case "$src" in
      "$path"/*) return 1 ;;
    esac
  fi
  if migrate_in_git_checkout "$path"; then
    return 1
  fi
  return 0
}

# migrate_rm <key>
# The only deletion in the migration. Takes a key, never a path. Order is
# deliberate: the safety gate runs before the existence check, so a key that
# resolves somewhere forbidden is refused out loud whether or not anything is
# there. A symlink is removed with rm -f on the link itself and what it points
# at is never touched; only a real directory gets rm -rf.
#
# Every success line is ok_unless_dry after a checked rm, never ok after an
# unchecked one: a preview that reports deletions which never happened is
# worthless exactly where the user is told to rely on it, and a real run that
# reports a failed rm as a success sends them off believing a file is gone.
# 0 when it removed something or there was nothing to remove, 1 when it
# refused or the removal failed.
migrate_rm() {
  local key="$1" path resolved
  if ! path="$(migrate_target "$key")"; then
    err "teeup migrate has no target named '$key'; nothing was removed."
    return 1
  fi
  if ! resolved="$(migrate_resolve "$path")"; then
    log "Nothing at $path."
    return 0
  fi
  if ! migrate_path_is_safe "$resolved"; then
    warn "Refusing to remove $path: it resolves to $resolved, which teeup's migration must not touch."
    return 1
  fi
  if [[ ! -e "$resolved" && ! -L "$resolved" ]]; then
    log "Nothing at $path."
    return 0
  fi
  if [[ -L "$resolved" ]]; then
    if ! run_cmd rm -f "$resolved"; then
      warn "Could not remove the legacy symlink $path; it is still there."
      return 1
    fi
    ok_unless_dry "Removed the legacy symlink $path"
    return 0
  fi
  if [[ -d "$resolved" ]]; then
    if ! run_cmd rm -rf "$resolved"; then
      warn "Could not remove the legacy directory $path; it is still there."
      return 1
    fi
    ok_unless_dry "Removed the legacy directory $path"
    return 0
  fi
  if ! run_cmd rm -f "$resolved"; then
    warn "Could not remove the legacy file $path; it is still there."
    return 1
  fi
  ok_unless_dry "Removed the legacy file $path"
}
