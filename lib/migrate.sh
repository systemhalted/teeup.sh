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

# migrate_rc_paths -> every rc file to visit, one absolute path per line
#
# zsh reads ${ZDOTDIR:-$HOME}/.zshenv, not always $HOME/.zshenv, and
# capabilities/zsh/configure installs teeup's stubs into that same directory.
# Visiting only $HOME on a ZDOTDIR machine means the migration reports success
# while changing nothing: the predecessor's lines go on running in the files
# zsh actually reads, and a doctor finding naming `teeup migrate legacy` as
# the fix can never go green.
#
# Both locations are visited when they differ, because a machine part-way
# through a migration can have leftovers in either. The bash files are not
# affected by ZDOTDIR and are only ever looked for in $HOME. One definition,
# used by every step that walks rc files, so they cannot disagree about which
# files exist.
migrate_rc_paths() {
  local zdot="${ZDOTDIR:-$HOME}" name
  for name in .zshenv .zprofile .zshrc; do
    printf '%s\n' "$zdot/$name"
    if [[ "$zdot" != "$HOME" ]]; then
      printf '%s\n' "$HOME/$name"
    fi
  done
  for name in .bashrc .bash_profile .profile; do
    printf '%s\n' "$HOME/$name"
  done
}

# Every rc line that wired a predecessor into a shell. Two patterns, because
# the reason printed on each neutralised line should say which predecessor it
# came from. teeup's own zsh stubs (phase 2a) contain none of these names, so
# neither pattern touches them and their stock checksums stay valid.
TEEUP_MIGRATE_LEGACY_RC_PATTERN='teeup\.common|teeupshrc|shellrc\.common|mac-setup'
# Oh My Zsh, Powerlevel10k and Antigen: the prompt and plugin frameworks that
# teeup's zsh layer and starship replace. legacy/teeup.sh disabled the antigen
# lines for the same reason. capabilities/zsh/doctor looks for exactly this
# union afterwards, so anything added here belongs there too.
TEEUP_MIGRATE_PROMPT_RC_PATTERN='powerlevel10k|p10k|POWERLEVEL9K_|oh-my-zsh|ohmyzsh|ZSH_THEME|antigen'

# migrate_legacy_paths
# What the old monolithic teeup.sh left behind: ~/.teeup.common (a file it
# generated with append_once), ~/.config/mac-setup (which held the generated
# zsh.zsh), and the ~/.teeupshrc and ~/.shellrc.common symlinks it created
# into whatever dotfiles directory it was pointed at. Removing the files
# without neutralising the lines that source them would make every new shell
# print an error, so both halves happen here.
# 0 when everything it tried succeeded, 1 when a removal was refused. A
# refusal never stops the rest: the point of the step is to get as much of the
# machine into a good state as it safely can, and say what it would not touch.
migrate_legacy_paths() {
  local key path rc=0
  log "Removing what older teeup versions left in your home directory"
  for key in teeup-common teeupshrc shellrc-common mac-setup; do
    if ! migrate_rm "$key"; then
      rc=1
    fi
  done
  log "Neutralising the shell lines that loaded them"
  while IFS= read -r path; do
    if [[ -n "$path" ]]; then
      disable_matching_lines "$path" "$TEEUP_MIGRATE_LEGACY_RC_PATTERN" "replaced by teeup's zsh layer"
      disable_matching_lines "$path" "$TEEUP_MIGRATE_PROMPT_RC_PATTERN" "replaced by teeup's starship prompt"
    fi
  done <<EOF_RC
$(migrate_rc_paths)
EOF_RC
  return $rc
}

# migrate_runtime_pattern <sdkman|rbenv|pyenv> -> that manager's awk ERE
# Deliberately narrow. The bare name would match a comment, an unrelated PATH
# entry or a variable that merely contains it, and a pattern that is too wide
# comments out lines the user still needs. These are the patterns
# legacy/teeup.sh used, plus the dot-directory each manager puts on PATH.
migrate_runtime_pattern() {
  case "$1" in
    sdkman) printf '%s\n' 'sdkman-init\.sh|SDKMAN_DIR|\.sdkman' ;;
    rbenv)  printf '%s\n' 'rbenv (init|shell)|RBENV_ROOT|\.rbenv' ;;
    pyenv)  printf '%s\n' 'pyenv (init|virtualenv-init)|PYENV_ROOT|\.pyenv' ;;
    *) return 1 ;;
  esac
}

# migrate_disable_runtime_inits
# mise owns every runtime from phase 3b on, and two managers each putting a
# java or a python on PATH is the failure this prevents. The toolchains stay:
# ~/.sdkman, ~/.rbenv and ~/.pyenv hold installed versions a user may still
# want, and it is the shell lines, not the directories, that make them win.
# Always 0: nothing here can be refused.
migrate_disable_runtime_inits() {
  local manager path dir leftover="" pattern
  log "Disabling the runtime managers mise replaces (SDKMAN, rbenv, pyenv)"
  for manager in sdkman rbenv pyenv; do
    pattern="$(migrate_runtime_pattern "$manager")"
    while IFS= read -r path; do
      if [[ -n "$path" ]]; then
        disable_matching_lines "$path" "$pattern" "$manager replaced by mise"
      fi
    done <<EOF_RC
$(migrate_rc_paths)
EOF_RC
  done
  for dir in .sdkman .rbenv .pyenv; do
    if [[ -d "$HOME/$dir" ]]; then
      leftover="$leftover ~/$dir"
    fi
  done
  if [[ -n "$leftover" ]]; then
    warn "Still on disk:$leftover. teeup does not delete an installed toolchain; remove them yourself once a new shell works."
  fi
  return 0
}

# migrate_teeup_ships <absolute-path>
# 0 when some capability ships a file that lands exactly at <absolute-path>.
# This is what separates "teeup will put this back on the next update" from
# "this is yours and nothing will restore it", and the two deserve very
# different warnings before a bulk rename of somebody's home directory.
#
# Two shipped layouts: capabilities/<cap>/config/<rel> lands at
# <user_config_dir>/<rel>, and capabilities/<cap>/home/<name> lands at
# ${ZDOTDIR:-$HOME}/<name> for the zsh stubs or $HOME/<name> otherwise --
# both are checked, since which one applies is the capability's business.
migrate_teeup_ships() {
  [[ -n "$(migrate_teeup_owner "$1")" ]]
}

# migrate_teeup_owner <absolute-path> -> the capability that ships <path>
# (its config/ or home/ copy), or nothing when no capability does.
migrate_teeup_owner() {
  local want="$1" cap_dir rel dest zdot="${ZDOTDIR:-$HOME}"
  for cap_dir in "$TEEUP_CAPS_DIR"/*; do
    [[ -d "$cap_dir" ]] || continue
    if [[ -d "$cap_dir/config" ]]; then
      while IFS= read -r dest; do
        [[ -n "$dest" ]] || continue
        rel="${dest#"$cap_dir/config/"}"
        if [[ "$(user_config_dir)/$rel" == "$want" ]]; then
          basename "$cap_dir"
          return 0
        fi
      done <<EOF_CFG
$(find "$cap_dir/config" -type f 2>/dev/null)
EOF_CFG
    fi
    if [[ -d "$cap_dir/home" ]]; then
      while IFS= read -r dest; do
        [[ -n "$dest" ]] || continue
        rel="${dest##*/}"
        if [[ "$HOME/$rel" == "$want" || "$zdot/$rel" == "$want" ]]; then
          basename "$cap_dir"
          return 0
        fi
      done <<EOF_HOME
$(find "$cap_dir/home" -type f 2>/dev/null)
EOF_HOME
    fi
  done
  return 0
}

# migrate_backup <absolute-path>
# backup_target behind the same gates migrate_rm uses. Every path reaching
# this comes from `chezmoi managed`, which lists entries in the destination
# directory, so the gates should never fire; they are here because a chezmoi
# config with an unusual destDir would otherwise let the migration rename a
# file outside $HOME. Prints the backup path when it moved something, prints
# nothing when there was nothing there.
#
# Three statuses, because the caller has to tell them apart: 0 moved it or
# there was nothing to move, 1 REFUSED, 2 backup_target FAILED. Collapsing
# the last two tells the user teeup protected something when in fact a file
# is still sitting there unmoved -- they go looking for a safety rule and
# never investigate the file.
migrate_backup() {
  local path="$1" resolved
  if ! resolved="$(migrate_resolve "$path")"; then
    return 0
  fi
  if ! migrate_path_is_safe "$resolved"; then
    warn "Refusing to back up $path: it resolves to $resolved, which teeup's migration must not touch."
    return 1
  fi
  if [[ ! -e "$resolved" && ! -L "$resolved" ]]; then
    return 0
  fi
  if [[ -d "$resolved" && ! -L "$resolved" ]]; then
    log "Leaving the directory $resolved in place; only files are moved aside."
    return 0
  fi
  backup_target "$resolved" || return 2
}

# migrate_chezmoi
# The chezmoi half of spec section 10. Managed files are MOVED ASIDE, not
# deleted: copy_config_once then installs teeup's own version into the gap,
# and the .teeup_backup_<ts> copy is right there to lift personal lines out
# of. The source directory is never deleted, never purged, never written to --
# it is ~/Work/environment/dotfiles on this user's machines and it still
# serves Linux. The one thing this can delete is ~/.config/chezmoi, the config
# that points chezmoi at that source, and only after asking; the default is
# no, so a non-interactive run keeps it.
#
# Nothing is renamed until somebody says so. This moves about twenty files in
# a real home directory, and the list is not all the same kind of thing: the
# ones teeup ships a config for come back on the next update, and the rest --
# a ~/.tmux.conf, somebody's own ~/.local/bin scripts -- have nothing to
# restore them but a hand search for *.teeup_backup_*. So the two groups are
# listed separately and one confirmation covers the move, defaulting to no.
# 0 when everything it tried succeeded, 1 when something was refused or failed.
migrate_chezmoi() {
  local src managed line backup count=0 rc=0 chezmoi_config
  local mine="" theirs="" refused=0 failed=0 migrate_backup_rc=0 owners="" owner
  if ! have chezmoi; then
    log "No chezmoi on this machine; nothing to take over."
    return 0
  fi
  src="$(migrate_chezmoi_source)" || {
    warn "chezmoi is installed but teeup could not determine its source directory, so nothing was taken over."
    return 1
  }
  if [[ -z "$src" ]]; then
    log "chezmoi is installed but reports no source directory here; nothing to take over."
    return 0
  fi
  # The rc files are the whole risk here. This step moves ~/.zshrc, ~/.zshenv
  # and ~/.zprofile aside so teeup's own stubs can take over -- but teeup
  # installs those in `configure zsh`, and if that never ran on this machine
  # the move leaves the user with no shell startup files at all. They find out
  # by opening a terminal. So the marker that says teeup's shell layer is
  # actually here gates this half, and the message names the one command that
  # makes it safe.
  if ! state_done check "cap-zsh"; then
    warn "teeup's zsh layer is not configured on this machine, so moving chezmoi's files aside would leave you with no ~/.zshrc at all. Run 'teeup install zsh' first, then re-run this."
    return 1
  fi
  log "chezmoi manages this home from $src"
  log "That checkout still serves Linux, so teeup never deletes it, never runs 'chezmoi purge', and never writes to it."
  managed="$(mktemp)"
  if ! chezmoi_ro managed --path-style=absolute --include=files,symlinks > "$managed" 2>/dev/null; then
    warn "Could not list what chezmoi manages, so nothing was moved. Run 'chezmoi managed' yourself to see why."
    rm -f "$managed"
    return 1
  fi
  # Split first, so the question can say which files are which.
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" ]]; then
      continue
    fi
    if [[ ! -e "$line" && ! -L "$line" ]]; then
      continue
    fi
    if migrate_teeup_ships "$line"; then
      theirs="$theirs  $line
"
    else
      mine="$mine  $line
"
    fi
  done < "$managed"
  if [[ -z "$theirs" && -z "$mine" ]]; then
    log "chezmoi manages nothing that is still in your home directory; nothing to move."
    rm -f "$managed"
  else
    if [[ -n "$theirs" ]]; then
      echo "teeup reinstalls its own version of these straight after moving them (for capabilities installed here):"
      printf '%s' "$theirs"
    fi
    if [[ -n "$mine" ]]; then
      echo "teeup does not ship these -- they are yours, and only the .teeup_backup_<ts> copy will hold them:"
      printf '%s' "$mine"
    fi
    if ! lazy_is_tty; then
      # A bulk rename of somebody's home directory is not something to do on
      # an unattended run. Say what a real one would do and stop.
      log "Not moving anything: there is nobody to ask. A run from a terminal would move the files above aside as <name>.teeup_backup_<ts>."
      rm -f "$managed"
      return 0
    fi
    if ! ui_confirm "Move the files above aside so teeup can take over this home directory?" no; then
      log "Nothing was moved. chezmoi still owns those files; re-run when you are ready."
      rm -f "$managed"
      return 0
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ -z "$line" ]]; then
        continue
      fi
      # A capability the machine opts out of with TEEUP_SKIP will not be
      # reinstalled below, so its file stays where it is: moving it would
      # leave nothing in its place (TEEUP_SKIP=zsh: no .zshrc at all).
      owner="$(migrate_teeup_owner "$line")"
      if [[ -n "$owner" ]] && cap_skipped "$owner"; then
        log "Leaving $line in place: $owner is in TEEUP_SKIP, so teeup would not put its own version back."
        continue
      fi
      backup=""
      migrate_backup_rc=0
      backup="$(migrate_backup "$line")" || migrate_backup_rc=$?
      case "$migrate_backup_rc" in
        0)
          # backup_target returns the prospective path and 0 under DRY_RUN
          # without moving anything, so counting its output there would make
          # the preview claim it moved the user's home aside. Only a real
          # move counts.
          if [[ -n "$backup" && "$DRY_RUN" != "true" ]]; then
            count=$((count + 1))
            owner="$(migrate_teeup_owner "$line")"
            if [[ -n "$owner" ]]; then
              case " $owners " in
                *" $owner "*) ;;
                *) owners="$owners $owner" ;;
              esac
            fi
          fi
          ;;
        1) refused=$((refused + 1)); rc=1 ;;
        *) failed=$((failed + 1)); rc=1 ;;
      esac
    done < "$managed"
    rm -f "$managed"
    ok_unless_dry "Moved $count chezmoi-managed file(s) aside."
    # Reinstall what was just displaced, now, rather than on a later
    # `teeup update`: moving ~/.zshenv, ~/.zprofile and ~/.zshrc aside left a
    # real Mac (2026-09-25) with no teeup layer, no Homebrew on PATH and no
    # teeup in the next shell. Only capabilities installed here are
    # configured -- anything else would lay down a capability nobody chose.
    # After any refusal or failure, nothing is reinstalled automatically:
    # configure scripts write more than the files they ship (LaunchAgents,
    # for one), so one could write through the path that was just refused.
    # The commands are named instead.
    if [[ "$refused" -gt 0 || "$failed" -gt 0 ]]; then
      for owner in $owners; do
        if state_done check "cap-$owner" && ! state_na check "cap-$owner"; then
          warn "Not reinstalling teeup's $owner configuration automatically, because something above was left alone. Deal with that, then run: teeup configure $owner"
        fi
      done
    else
      for owner in $owners; do
        if state_na check "cap-$owner" || ! state_done check "cap-$owner"; then
          log "$owner is not installed here, so its file stays moved aside; run 'teeup install $owner' to get teeup's version."
          continue
        fi
        if cap_run "$owner" configure; then
          ok "Reinstalled teeup's $owner configuration."
        else
          warn "Could not reinstall teeup's $owner configuration; run: teeup configure $owner"
          rc=1
        fi
      done
    fi
    # Which of the two happened, named separately: a refusal is teeup
    # protecting something, a failure is a file still sitting there that
    # nobody will look at if it reads as a refusal.
    if [[ "$refused" -gt 0 ]]; then
      warn "$refused file(s) were refused: they resolve somewhere teeup's migration must not touch. Nothing was lost; they are where they were."
    fi
    if [[ "$failed" -gt 0 ]]; then
      warn "$failed file(s) could not be backed up and are still in place. Read the warnings above: that is a write that failed, not a safety refusal."
    fi
  fi
  chezmoi_config="$(migrate_target chezmoi-config)"
  if [[ ! -e "$chezmoi_config" ]]; then
    log "No $chezmoi_config, so chezmoi already has nothing pointing it at this home."
    return $rc
  fi
  if ui_confirm "Delete $chezmoi_config, so chezmoi stops pointing at $src? The checkout itself stays." no; then
    if ! migrate_rm chezmoi-config; then
      rc=1
    fi
  else
    log "Keeping $chezmoi_config. Running 'chezmoi apply' again will put its files back over teeup's."
  fi
  return $rc
}
