#!/usr/bin/env bash
# core.sh - paths, logging, the dry-run seam and the logged runner.
# Sourced by lib/all.sh. Safe to source more than once.

: "${TEEUP_PATH:?TEEUP_PATH must point at the teeup checkout}"
TEEUP_CONFIG_DIR="${TEEUP_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/teeup}"
TEEUP_STATE_DIR="${TEEUP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/teeup}"
DRY_RUN="${DRY_RUN:-false}"
# Empty means log lines go to stdout only.
TEEUP_LOG_FILE="${TEEUP_LOG_FILE:-}"
export TEEUP_PATH TEEUP_CONFIG_DIR TEEUP_STATE_DIR DRY_RUN TEEUP_LOG_FILE

# A signal can interrupt a terminal write. These lines only report progress,
# so retry once and never let the write status stop a run under `set -e`.
_informational_line() {
  local icon="$1"
  shift
  if ! printf "%b %s\n" "$icon" "$*"; then
    printf "%b %s\n" "$icon" "$*" || true
  fi
  return 0
}

log()  { _informational_line "🔹" "$*"; }
ok()   { _informational_line "✅" "$*"; }
warn() { _informational_line "⚠️" "$*" >&2; }
err()  { printf "%b %s\n" "❌" "$*" >&2; }
die()  { err "$@"; exit 1; }

# _teeup_interrupted: the SIGINT trap bin/teeup and bootstrap install
# (`trap _teeup_interrupted INT`). Ctrl-C signals the whole foreground
# process group, but Homebrew and many other tools catch SIGINT, clean up
# and exit 1, so bash would see an ordinary failure and go on to the next
# step. bash runs this trap once the current command returns, so that
# command still gets to clean up, and then teeup stops with status 130.
# Only those two entry points install it: a capability script is a fresh
# `bash -eu` and keeps the default, and an exec (teeup lazy-run) resets it.
_teeup_interrupted() {
  if [[ -n "${_TEEUP_RUN_LOG_TMP:-}" ]]; then
    rm -rf "$_TEEUP_RUN_LOG_TMP"
  fi
  printf '\n' >&2
  err "Stopped (Ctrl-C)."
  exit 130
}

# ok_unless_dry <message>
# The one mechanism every capability uses to report a mutation: silent under
# DRY_RUN=true (run_cmd's own "[DRY-RUN] Would execute: ..." line already told
# the user what would happen; claiming it happened too would be a lie) and
# identical to plain `ok` on a real run, so today's wording never changes.
ok_unless_dry() {
  [[ "$DRY_RUN" == "true" ]] && return 0
  ok "$@"
}
# have <command>
# TEEUP_TEST_MISSING is a test-only hook: a space-separated list of commands
# the harness pretends are absent, so a test can simulate a fresh Mac on a
# host that already has them. An entry is a bare name (hidden wherever it is
# found) or an absolute path (only that binary is hidden, so a copy the test
# installs somewhere else is still found; see hide_host_commands in
# tests/helper.sh).
have() {
  local found
  case " ${TEEUP_TEST_MISSING:-} " in
    *" $1 "*) return 1 ;;
  esac
  found="$(command -v "$1" 2>/dev/null)" || return 1
  case " ${TEEUP_TEST_MISSING:-} " in
    *" $found "*) return 1 ;;
  esac
  # A teeup lazy shim (lib/lazy.sh) stands in for a command nothing real
  # provides, and the shell puts the shims directory last on PATH, so when
  # `command -v` answers with a shim there is no real binary anywhere ahead of
  # it. Counting that as "installed" would make pkg_install skip the very
  # package the shim exists to install.
  case "$found" in
    "$TEEUP_STATE_DIR/shims/"*) return 1 ;;
  esac
  return 0
}

# Every mutation goes through here so DRY_RUN=true is a faithful preview.
run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would execute: $*"
    return 0
  fi
  "$@"
}

_teeup_log_line() {
  local line
  line="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  # When an outer run_logged already owns the tee, printing this line feeds it
  # to that tee. Appending here as well would put the same line in the log twice.
  if [[ -n "$TEEUP_LOG_FILE" && "${TEEUP_RUN_LOG_CAPTURED:-false}" != "true" ]]; then
    mkdir -p "$(dirname "$TEEUP_LOG_FILE")"
    printf '%s\n' "$line" >> "$TEEUP_LOG_FILE"
  fi
  printf '%s\n' "$line"
}

# run_logged <name> <interactive:true|false> <command...>
# Brackets a unit with Starting/Completed/Failed lines and, when a log file is
# configured, tees the command's own stdout and stderr into it too -- a
# capability's warnings, its "[DRY-RUN] Would execute" preview lines and its
# instructions used to reach the terminal only, so a log sent after a
# successful run was pure timestamps and a log sent after a failure could not
# explain it. stdin is redirected from /dev/null unless interactive=true, so
# a unit can never block on a prompt nobody will answer.
#
# interactive=true is never teed: that would put a pipe between the command
# and the terminal, and ssh-keygen's passphrase prompt, sudo's password
# prompt and `gh auth login`'s browser flow all need a real tty to draw on.
# Nothing sensitive is lost by leaving it uncaptured -- a passphrase or a
# sudo password is read straight from the tty by the prompting program, never
# printed to stdout or stderr, so it was never going to be in the stream this
# tees in the first place. The log gets a line saying capture was skipped and
# why, instead of silently staying empty for that unit.
#
# stdout and stderr are teed through two separate named pipes, one `tee` each,
# rather than merged with `2>&1` first: a capability's stderr (every warn(),
# every err()) must keep landing on fd 2, or `./bootstrap >out.log` would
# silently swallow it, and a caller further up would lose the ability to
# handle the two streams differently. Named pipes rather than the more usual
# `> >(tee ...) 2> >(tee ...)` process substitution: process substitution
# backgrounds its reader with nothing forcing this function to wait for it,
# so the tee could still be draining the pipe (and the log missing the
# command's tail) by the time the "Completed"/"Failed" line below is written
# -- a real race, not a theoretical one, confirmed with a capability that
# prints thousands of lines before this fix and fixed by the explicit `wait`
# below. Each tee is started first, so its open(2) on the fifo is already
# blocked waiting for a writer when the command opens the other end; `wait`
# after the command exits blocks until both tees have seen EOF and finished
# writing, so nothing after this branch can run ahead of the log being
# complete.
#
# The command sits in a plain redirection, not a pipe, so its own $? is the
# real exit status right here in this shell -- no subshell, no PIPESTATUS,
# nothing bash 3.2 could handle differently. `"$@" ... || rc=$?` (not a bare
# `rc=$?` on the next line) keeps it on the losing side of `||`, which is
# exempt from `set -e`, so a failing command cannot abort this function
# before its exit code is saved.
#
# Nested runners inherit TEEUP_RUN_LOG_CAPTURED=true from the command owned by
# the outer tee. Their bracket lines and command output still flow through the
# inherited stdout/stderr, but they neither append directly nor start another
# tee pair. The variable is scoped to the child command, so later independent
# run_logged calls in this shell remain outermost and capture normally.
run_logged() {
  local name="$1" interactive="$2"
  shift 2
  local rc=0
  _teeup_log_line "Starting: $name"
  if [[ "$interactive" == "true" ]]; then
    [[ -n "$TEEUP_LOG_FILE" ]] &&
      _teeup_log_line "($name is interactive; its output was not captured -- it needs a real terminal.)"
    "$@" || rc=$?
  elif [[ -n "$TEEUP_LOG_FILE" && "${TEEUP_RUN_LOG_CAPTURED:-false}" != "true" ]]; then
    local fifo_dir out_fifo err_fifo out_tee_pid err_tee_pid
    fifo_dir="$(mktemp -d)"
    # For _teeup_interrupted, which exits before the rm below.
    _TEEUP_RUN_LOG_TMP="$fifo_dir"
    out_fifo="$fifo_dir/stdout"
    err_fifo="$fifo_dir/stderr"
    mkfifo "$out_fifo" "$err_fifo"
    tee -a "$TEEUP_LOG_FILE" < "$out_fifo" &
    out_tee_pid=$!
    tee -a "$TEEUP_LOG_FILE" < "$err_fifo" >&2 &
    err_tee_pid=$!
    TEEUP_RUN_LOG_CAPTURED=true "$@" </dev/null > "$out_fifo" 2> "$err_fifo" || rc=$?
    wait "$out_tee_pid" "$err_tee_pid" || true
    rm -rf "$fifo_dir"
    _TEEUP_RUN_LOG_TMP=""
  else
    "$@" </dev/null || rc=$?
  fi
  if [[ $rc -eq 0 ]]; then
    _teeup_log_line "Completed: $name"
  elif [[ -n "${TEEUP_RUN_NA_EXIT:-}" && $rc -eq "$TEEUP_RUN_NA_EXIT" ]]; then
    # Only when the caller says this exit code means "not applicable" for the
    # command it is running -- cap_run does, for a capability verb. Logging
    # "Failed ... (exit code: 42)" next to the capability's own "not
    # applicable on this machine" line reads like something broke. run_logged
    # itself stays generic: 42 is an ordinary failure to anything else.
    _teeup_log_line "Not applicable: $name"
  else
    _teeup_log_line "Failed: $name (exit code: $rc)"
  fi
  return "$rc"
}

is_macos()    { [[ "$(uname -s)" == "Darwin" ]]; }
arch()        { uname -m; }
macos_major() { sw_vers -productVersion 2>/dev/null | awk -F. '{print $1}'; }

# The directory capabilities/<cap>/config/ maps onto. TEEUP_CONFIG_DIR is
# teeup's own subdirectory of this one.
user_config_dir() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}"; }

# _strip_trailing_slashes <path> -> <path> with every trailing "/" removed,
# except a lone "/" stays "/". A trailing slash makes both -e and -L report
# false for a path that is actually a file or a dangling symlink (the
# kernel requires a directory before a trailing slash resolves at all), so
# without this, a check on ".../blocker/" would silently walk past a real
# blocker instead of catching it.
_strip_trailing_slashes() {
  local p="$1"
  while [[ "$p" == */ && "$p" != "/" ]]; do
    p="${p%/}"
  done
  printf '%s\n' "$p"
}

# _nearest_existing_ancestor_or_symlink <path> -> walks up dirname until
# something is there, prints that path, and returns 0; that is the
# directory `mkdir -p <path>` would actually create under, so its
# permissions are what decide whether the create would work. A symlink
# anywhere along the way (the checked path itself, or an ancestor the walk
# passes through) that does not resolve -- a missing target, or a loop --
# is reported instead of walked past -- `-e` is false for one too, so
# without this it would read as "does not exist" and the walk would
# continue straight past it into whatever the link used to point at:
# prints the problem line instead and returns 1.
_nearest_existing_ancestor_or_symlink() {
  local p linktarget
  p="$(_strip_trailing_slashes "$1")"
  while [[ ! -e "$p" ]]; do
    if [[ -L "$p" ]]; then
      linktarget="$(readlink "$p")"
      printf '%s is a symlink that cannot be resolved (its target %s is missing, or the links form a loop). Fix or remove the link.\n' \
        "$p" "$linktarget"
      return 1
    fi
    p="$(dirname "$p")"
  done
  printf '%s\n' "$p"
}

# _is_mine <path> -> true when the current user owns <path>. Bash's -O test
# reads this straight from the filesystem, so it cannot be fooled by
# anything a test mocks on `id` or `stat` (several suites already rely on
# `id -un` answering a fixed test uid, see tests/helper.sh mock_macos_base).
# TEEUP_TEST_NOT_MINE is a test-only hook (same idea as TEEUP_TEST_MISSING in
# `have`, above): a space-separated list of paths a test wants to pretend
# belong to someone else, since a sandboxed test has no way to actually hand
# a directory to another user.
_is_mine() {
  case " ${TEEUP_TEST_NOT_MINE:-} " in
    *" $1 "*) return 1 ;;
  esac
  [[ -O "$1" ]]
}

# _path_owner <path> -> the name of whoever owns <path>, for the message a
# problem prints -- never the decision itself (_is_mine owns that). GNU stat
# is probed first on purpose, same idiom as _file_mode in lib/files.sh: GNU's
# -f means something else and fails only after printing to stderr, while
# BSD's -c fails cleanly. TEEUP_TEST_PATH_OWNER is the display-side partner
# of TEEUP_TEST_NOT_MINE: real stat would report the true (and, in a
# sandbox, always matching) owner, not the someone-else name a test wants
# the message to show.
_path_owner() {
  if [[ -n "${TEEUP_TEST_PATH_OWNER:-}" ]]; then
    printf '%s\n' "$TEEUP_TEST_PATH_OWNER"
    return
  fi
  stat -c '%U' "$1" 2>/dev/null || stat -f '%Su' "$1" 2>/dev/null || true
}

# _writable_check_one <path> [override_var] -> prints one line naming
# <path> (or, when it does not exist yet, the nearest existing ancestor
# that mkdir -p would create it under) and what is wrong with it, with a
# command that fixes it. <override_var> is the env var (if any, e.g.
# XDG_DATA_HOME) a message can point someone at instead, when the fix is
# "put it somewhere else you already own." Prints nothing and returns 0
# when <path> is fine.
#
# Order, deliberately: (1) a symlink that cannot be resolved, at <path> or
# along the walk to an ancestor, or an existing thing that is not a
# directory -- <path> itself, or (just as fatal, since mkdir -p cannot
# create anything under a file) the ancestor the walk stopped at -- always
# fails outright, before any write test, dry run or not. (2) the write
# test decides whether anything else is wrong at all: outside DRY_RUN, a
# real mktemp -d probe (because -w only asks access(2), and a macOS ACL or
# a privacy rule can pass that while a real mkdir still fails -- the
# MacBook Air that prompted this check), then, only if that passed, a
# second real probe with a plain file (some ACLs and sandboxing rules
# allow one but not the other); under DRY_RUN, which must not write
# anything, -w and -x (a directory that is writable but not searchable
# cannot have anything created inside it either). Every probe this makes
# is removed before returning, and a cleanup that itself fails is reported
# rather than ignored -- a probe teeup created and could not remove is
# itself something to fix, not a false "all clear". (3) only once the
# write test fails does ownership matter, and only to choose the fix text:
# a folder someone else owns but that still took the probe (or passes
# -w/-x) is left alone entirely -- ownership must never fail a folder by
# itself, and teeup must never suggest a recursive chown of a folder above
# the user's own, or assume the user's group. A plain (non-recursive)
# `chown` naming the user's own group ($(id -gn)) is offered only for the
# exact path teeup asked for, not an ancestor it would merely create
# something under.
#
# Every path inside a "Run: ..." command is shell-quoted with printf %q
# and preceded by "--" (the prose naming the folder uses neither) so a
# folder with a space, a metacharacter, or a name that looks like an
# option can be pasted straight into a terminal.
_writable_check_one() {
  local path override_var="${2:-}" target owner why="" reason="" probe
  local target_q path_q probe_q
  path="$(_strip_trailing_slashes "$1")"

  target="$(_nearest_existing_ancestor_or_symlink "$path")" || {
    printf '%s\n' "$target"
    return 1
  }

  if [[ "$target" == "$path" ]]; then
    if [[ ! -d "$path" ]]; then
      printf '%s exists and is not a directory. Move it aside, then try again.\n' "$path"
      return 1
    fi
  else
    why=", so teeup cannot create $path there"
    if [[ ! -d "$target" ]]; then
      printf '%s is a file, not a folder, so teeup cannot create %s. Move it aside, then try again.\n' \
        "$target" "$path"
      return 1
    fi
  fi

  printf -v target_q '%q' "$target"
  printf -v path_q '%q' "$path"

  if [[ "$DRY_RUN" != "true" ]]; then
    if probe="$(mktemp -d "$target/.teeup-write-probe.XXXXXX" 2>&1)"; then
      if ! rmdir "$probe" 2>/dev/null; then
        printf -v probe_q '%q' "$probe"
        printf '%s: teeup created %s but could not remove it. Remove it by hand: rm -rf -- %s\n' \
          "$target" "$probe" "$probe_q"
        return 1
      fi
      # A directory probe passing does not prove a plain file can be
      # created there too -- some ACLs and sandboxing rules distinguish
      # the two.
      if probe="$(mktemp "$target/.teeup-write-probe.XXXXXX" 2>&1)"; then
        if ! rm -f "$probe" 2>/dev/null; then
          printf -v probe_q '%q' "$probe"
          printf '%s: teeup created %s but could not remove it. Remove it by hand: rm -rf -- %s\n' \
            "$target" "$probe" "$probe_q"
          return 1
        fi
      else
        reason="file"
      fi
    else
      reason="probe"
    fi
  else
    [[ -w "$target" && -x "$target" ]] || reason="perm"
  fi
  [[ -n "$reason" ]] || return 0

  if _is_mine "$target"; then
    if [[ "$target" == "$HOME" ]]; then
      case "$reason" in
        probe)
          printf 'Your home folder %s does not allow new folders (%s)%s. Run: ls -lde -- %s to see its permissions and ACLs.\n' \
            "$target" "$probe" "$why" "$target_q" ;;
        file)
          printf 'Your home folder %s does not allow new files (%s)%s. Run: ls -lde -- %s to see its permissions and ACLs.\n' \
            "$target" "$probe" "$why" "$target_q" ;;
        *)
          printf 'Your home folder %s does not allow new folders%s. Run: ls -lde -- %s, then: chmod u+wx -- %s\n' \
            "$target" "$why" "$target_q" "$target_q" ;;
      esac
    else
      case "$reason" in
        probe)
          printf '%s refuses new folders (%s)%s. Run: ls -lde -- %s to see its permissions and ACLs.\n' \
            "$target" "$probe" "$why" "$target_q" ;;
        file)
          printf '%s refuses new files (%s)%s. Run: ls -lde -- %s to see its permissions and ACLs.\n' \
            "$target" "$probe" "$why" "$target_q" ;;
        *)
          printf '%s is not writable%s. Run: ls -lde -- %s, then: chmod u+wx -- %s\n' \
            "$target" "$why" "$target_q" "$target_q" ;;
      esac
    fi
    return 1
  fi

  if [[ "$target" == "$path" ]]; then
    owner="$(_path_owner "$target")"
    printf '%s is owned by %s, not you%s. Run: sudo chown -- "$(id -un)":"$(id -gn)" %s\n' \
      "$target" "${owner:-someone else}" "$why" "$target_q"
    return 1
  fi

  # target is an ancestor, not the path itself, and not mine: never offer
  # a recursive chown of it -- that folder likely holds more than this one
  # user's things. Only the new folder teeup would create gets a chown,
  # and only a plain one, naming the user's own group rather than assuming
  # one.
  if [[ "$target" == "$HOME" ]]; then
    if [[ -n "$override_var" ]]; then
      printf 'Your home folder %s does not let you create %s. Run: ls -lde -- %s to see its permissions and ACLs. Create %s yourself with the right owner (for example: sudo mkdir -p -- %s && sudo chown -- "$(id -un)":"$(id -gn)" %s), or point %s elsewhere.\n' \
        "$target" "$path" "$target_q" "$path" "$path_q" "$path_q" "$override_var"
    else
      printf 'Your home folder %s does not let you create %s. Run: ls -lde -- %s to see its permissions and ACLs. Create %s yourself with the right owner (for example: sudo mkdir -p -- %s && sudo chown -- "$(id -un)":"$(id -gn)" %s).\n' \
        "$target" "$path" "$target_q" "$path" "$path_q" "$path_q"
    fi
  else
    if [[ -n "$override_var" ]]; then
      printf '%s does not let you create %s. Run: ls -lde -- %s to see its permissions and ACLs. Create %s yourself with the right owner (for example: sudo mkdir -p -- %s && sudo chown -- "$(id -un)":"$(id -gn)" %s), or point %s elsewhere.\n' \
        "$target" "$path" "$target_q" "$path" "$path_q" "$path_q" "$override_var"
    else
      printf '%s does not let you create %s. Run: ls -lde -- %s to see its permissions and ACLs. Create %s yourself with the right owner (for example: sudo mkdir -p -- %s && sudo chown -- "$(id -un)":"$(id -gn)" %s).\n' \
        "$target" "$path" "$target_q" "$path" "$path_q" "$path_q"
    fi
  fi
  return 1
}

# _writable_check_log <log_file> [override_var] -> like _writable_check_one,
# but for a log file specifically: when <log_file> already exists, that
# exact file is what run_logged appends to, so it is checked directly (its
# type, and -w) rather than its directory -- a mode-0444 existing log file
# in an otherwise writable directory must fail here, and a writable
# existing file (or /dev/null) in a directory that would otherwise look
# unwritable to a plain ancestor-and-probe check must not. Only when
# <log_file> does not exist yet does the directory it would be created in
# matter, and that reduces to the ordinary check.
_writable_check_log() {
  local log_file="$1" override_var="${2:-}" log_q
  if [[ -e "$log_file" ]]; then
    if [[ -f "$log_file" || "$log_file" == /dev/null ]]; then
      if [[ ! -w "$log_file" ]]; then
        printf -v log_q '%q' "$log_file"
        printf '%s is not writable. Run: chmod u+w -- %s\n' "$log_file" "$log_q"
        return 1
      fi
      return 0
    fi
    printf '%s exists and is not a regular file. Move it aside, then try again.\n' "$log_file"
    return 1
  fi
  _writable_check_one "$(dirname "$log_file")" "$override_var"
}

# writable_dirs_check -> prints one line per directory (or, for the log
# target, file) teeup writes into that is not safely writable (a symlink
# that cannot be resolved, wrong type, not writable, or refusing an actual
# mkdir -- or, when it does not exist yet, whichever existing ancestor
# mkdir -p would create it under; see _writable_check_one for why
# ownership alone never fails one). Honours DRY_RUN: the mkdir probe, the
# only step that writes anything, is skipped then. bootstrap's preflight
# calls this before anything else runs.
# Also checks the effective TEEUP_STATE_DIR and TEEUP_CONFIG_DIR (as
# lib/core.sh, above, initialised them), whether or not they exist: a
# machine with either overridden away from its XDG default would otherwise
# never have its real write target checked; $HOME itself (dev-dirs creates
# ~/Work there, and zsh writes dotfiles directly into it); $MISE_CONFIG_DIR,
# when it is set and non-empty (capabilities/mise/configure writes there);
# and the log file itself -- "$TEEUP_LOG_FILE" when bootstrap has set one
# (it does, before this runs), else the same default run_logged falls back
# to, "$TEEUP_STATE_DIR/logs/bootstrap.log" -- checked directly if it
# already exists (_writable_check_log), otherwise its directory, so a
# `mkdir -p` failure (or an unwritable existing log file) deep inside
# run_logged's own log write, much later and far from any preflight
# message, cannot happen either. This deliberately does not try to
# enumerate every write target of every capability -- just the handful
# outside a capability's own config/state/data tree. Returns 1 when any
# line was printed.
#
# Paths and their override var, as two parallel arrays rather than one
# "path:var" string: a path is free to contain a colon (a theme name, a
# machine's own choice of XDG_CONFIG_HOME), and splitting on ":" would cut
# it off. Checked paths are tracked in an indexed array too, and compared
# element by element, rather than with a space-delimited string: a path
# containing a space (as its own entry, or as a substring of a different,
# longer path already recorded) must never cause a real duplicate to be
# skipped, or a distinct path to be wrongly treated as a duplicate.
writable_dirs_check() {
  local rc=0 i j n p seen_it
  local -a _wdc_paths=(
    "$HOME"
    "${XDG_CONFIG_HOME:-$HOME/.config}"
    "${XDG_STATE_HOME:-$HOME/.local/state}"
    "${XDG_DATA_HOME:-$HOME/.local/share}"
    "$HOME/.local/bin"
    "$TEEUP_STATE_DIR"
    "$TEEUP_CONFIG_DIR"
  )
  local -a _wdc_vars=(
    ""
    "XDG_CONFIG_HOME"
    "XDG_STATE_HOME"
    "XDG_DATA_HOME"
    ""
    "TEEUP_STATE_DIR"
    "TEEUP_CONFIG_DIR"
  )
  local -a _wdc_seen=()

  n=${#_wdc_paths[@]}
  for ((i = 0; i < n; i++)); do
    p="${_wdc_paths[i]}"
    seen_it=false
    for ((j = 0; j < ${#_wdc_seen[@]}; j++)); do
      if [[ "${_wdc_seen[j]}" == "$p" ]]; then
        seen_it=true
        break
      fi
    done
    [[ "$seen_it" == true ]] && continue
    _wdc_seen[${#_wdc_seen[@]}]="$p"
    _writable_check_one "$p" "${_wdc_vars[i]}" || rc=1
  done

  if [[ -n "${MISE_CONFIG_DIR:-}" ]]; then
    seen_it=false
    for ((j = 0; j < ${#_wdc_seen[@]}; j++)); do
      if [[ "${_wdc_seen[j]}" == "$MISE_CONFIG_DIR" ]]; then
        seen_it=true
        break
      fi
    done
    if [[ "$seen_it" != true ]]; then
      _wdc_seen[${#_wdc_seen[@]}]="$MISE_CONFIG_DIR"
      _writable_check_one "$MISE_CONFIG_DIR" "MISE_CONFIG_DIR" || rc=1
    fi
  fi

  local log_file log_parent
  if [[ -n "${TEEUP_LOG_FILE:-}" ]]; then
    log_file="$TEEUP_LOG_FILE"
  else
    log_file="$TEEUP_STATE_DIR/logs/bootstrap.log"
  fi
  if [[ -e "$log_file" ]]; then
    _writable_check_log "$log_file" "TEEUP_LOG_FILE" || rc=1
  else
    log_parent="$(dirname "$log_file")"
    seen_it=false
    for ((j = 0; j < ${#_wdc_seen[@]}; j++)); do
      if [[ "${_wdc_seen[j]}" == "$log_parent" ]]; then
        seen_it=true
        break
      fi
    done
    if [[ "$seen_it" != true ]]; then
      _writable_check_one "$log_parent" "TEEUP_LOG_FILE" || rc=1
    fi
  fi
  return "$rc"
}

format_duration() {
  local total="$1" hours minutes seconds
  hours=$((total / 3600))
  minutes=$(((total % 3600) / 60))
  seconds=$((total % 60))
  if [[ "$hours" -gt 0 ]]; then
    printf "%dh %dm %ds" "$hours" "$minutes" "$seconds"
  elif [[ "$minutes" -gt 0 ]]; then
    printf "%dm %ds" "$minutes" "$seconds"
  else
    printf "%ds" "$seconds"
  fi
}
