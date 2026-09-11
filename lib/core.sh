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
have() { command -v "$1" >/dev/null 2>&1; }

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
  if [[ -n "$TEEUP_LOG_FILE" ]]; then
    mkdir -p "$(dirname "$TEEUP_LOG_FILE")"
    printf '%s\n' "$line" >> "$TEEUP_LOG_FILE"
  fi
  printf '%s\n' "$line"
}

# run_logged <name> <interactive:true|false> <command...>
# Brackets a unit with Starting/Completed/Failed lines. stdin is redirected
# from /dev/null unless interactive=true, so a unit can never block on a
# prompt nobody will answer. Returns the command's exit code.
run_logged() {
  local name="$1" interactive="$2"
  shift 2
  local rc=0
  _teeup_log_line "Starting: $name"
  if [[ "$interactive" == "true" ]]; then
    "$@" || rc=$?
  else
    "$@" </dev/null || rc=$?
  fi
  if [[ $rc -eq 0 ]]; then
    _teeup_log_line "Completed: $name"
  else
    _teeup_log_line "Failed: $name (exit code: $rc)"
  fi
  return $rc
}

is_macos()    { [[ "$(uname -s)" == "Darwin" ]]; }
arch()        { uname -m; }
macos_major() { sw_vers -productVersion 2>/dev/null | awk -F. '{print $1}'; }

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
