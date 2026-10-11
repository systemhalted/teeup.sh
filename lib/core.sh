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

log()  { printf "%b %s\n" "🔹" "$*"; }
ok()   { printf "%b %s\n" "✅" "$*"; }
warn() { printf "%b %s\n" "⚠️" "$*" >&2; }
err()  { printf "%b %s\n" "❌" "$*" >&2; }
die()  { err "$@"; exit 1; }

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

# _nearest_existing_ancestor <path> -> walks up dirname until something is
# there. That is the directory `mkdir -p <path>` would actually create under,
# so its permissions are what decide whether the create would work.
_nearest_existing_ancestor() {
  local p="$1"
  while [[ ! -e "$p" ]]; do
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

# _writable_check_one <path> -> prints one line naming <path> (or, when it
# does not exist yet, the nearest existing ancestor that mkdir -p would
# create it under) and what is wrong with it, with a command that fixes it.
# Prints nothing and returns 0 when <path> is fine. The last check actually
# creates and removes a directory there (unless DRY_RUN), because the owner
# and -w checks above only ask access(2), and an ACL or a privacy rule can
# pass that while a real mkdir still fails.
_writable_check_one() {
  local path="$1" target="$1" owner why=""
  if [[ ! -e "$path" ]]; then
    target="$(_nearest_existing_ancestor "$path")"
    why=", so teeup cannot create $path there"
  elif [[ ! -d "$path" ]]; then
    printf '%s exists and is not a directory. Move it aside, then try again.\n' "$path"
    return 1
  fi
  if ! _is_mine "$target"; then
    owner="$(_path_owner "$target")"
    printf '%s is owned by %s, not you%s. Run: sudo chown -R "$(id -un)":staff %s\n' \
      "$target" "${owner:-someone else}" "$why" "$target"
    return 1
  fi
  if [[ ! -w "$target" ]]; then
    if [[ "$target" == "$HOME" ]]; then
      printf 'Your home folder %s does not allow new folders%s. Run: ls -lde %s, then: chmod u+w %s\n' \
        "$target" "$why" "$target" "$target"
    else
      printf '%s is not writable%s. Run: ls -lde %s, then: chmod u+w %s\n' \
        "$target" "$why" "$target" "$target"
    fi
    return 1
  fi
  # -w only asks access(2), which a macOS ACL (deny add_subdirectory) or a
  # privacy rule can pass while the actual create still fails -- the MacBook
  # Air that prompted this check. Skipped under DRY_RUN: it only reads
  # everywhere else, and a probe directory is a write.
  if [[ "$DRY_RUN" != "true" ]]; then
    local probe
    probe="$(mktemp -d "$target/.teeup-write-probe.XXXXXX" 2>&1)" || {
      if [[ "$target" == "$HOME" ]]; then
        printf 'Your home folder %s does not allow new folders (%s)%s. Run: ls -lde %s to see its permissions and ACLs.\n' \
          "$target" "$probe" "$why" "$target"
      else
        printf '%s refuses new folders (%s)%s. Run: ls -lde %s to see its permissions and ACLs.\n' \
          "$target" "$probe" "$why" "$target"
      fi
      return 1
    }
    rmdir "$probe" 2>/dev/null || true
  fi
  return 0
}

# writable_dirs_check -> prints one line per directory teeup writes into
# that is not safely writable (wrong type, owned by someone else, not
# writable, or refusing an actual mkdir -- or, when it does not exist yet,
# whichever existing ancestor mkdir -p would create it under). Honours
# DRY_RUN: the mkdir probe, the only step that writes anything, is skipped
# then. bootstrap's preflight calls this before anything else runs.
# Returns 1 when any line was printed.
writable_dirs_check() {
  local rc=0 path
  for path in \
    "${XDG_CONFIG_HOME:-$HOME/.config}" \
    "${XDG_STATE_HOME:-$HOME/.local/state}" \
    "${XDG_DATA_HOME:-$HOME/.local/share}" \
    "$HOME/.local/bin"
  do
    _writable_check_one "$path" || rc=1
  done
  if [[ -e "$TEEUP_CONFIG_DIR" ]]; then
    _writable_check_one "$TEEUP_CONFIG_DIR" || rc=1
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
