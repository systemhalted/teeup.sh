#!/usr/bin/env bash
# ui.sh - prompts over gum with plain read fallbacks. Every function reads
# from stdin so tests can pipe answers; gum draws on /dev/tty by itself.
# Requires core.sh.

_ui_gum() { [[ -z "${TEEUP_NO_GUM:-}" ]] && have gum; }

# _ui_gum_rc <status> -> <status>, except that 130 exits the current shell.
# gum puts the terminal in raw mode, so Ctrl-C reaches gum as a key: gum exits
# 130 and teeup gets no SIGINT. Taking that as an empty answer or a no kept the
# wizard going. Exiting here stops teeup without signalling unrelated members
# of its process group, and still works when the caller inherited SIGINT as
# ignored (for example, a background test process).
_ui_gum_rc() {
  if [[ "$1" -eq 130 ]]; then
    exit 130
  fi
  return "$1"
}

ui_rc_or_exit() {
  local rc="$1"
  if [[ "$rc" -eq 130 ]]; then
    exit 130
  fi
  return "$rc"
}

# ui_input <prompt> [default] -> prints the answer
ui_input() {
  local prompt="$1" default="${2:-}" answer rc=0
  if _ui_gum; then
    answer="$(gum input --prompt "$prompt: " --value "$default" --placeholder "$default")" || { rc=$?; _ui_gum_rc $rc; answer=""; }
  else
    printf '%s' "$prompt" >&2
    [[ -n "$default" ]] && printf ' [%s]' "$default" >&2
    printf ': ' >&2
    IFS= read -r answer || {
      rc=$?
      if [[ $rc -eq 130 ]]; then exit 130; fi
    }
  fi
  [[ -z "$answer" ]] && answer="$default"
  printf '%s\n' "$answer"
  return $rc
}

# ui_secret <prompt> -> prints the answer, without echoing it to the terminal
ui_secret() {
  local prompt="$1" answer rc=0
  if _ui_gum; then
    answer="$(gum input --password --prompt "$prompt: ")" || { rc=$?; _ui_gum_rc $rc; answer=""; }
  else
    printf '%s: ' "$prompt" >&2
    IFS= read -rs answer || {
      rc=$?
      if [[ $rc -eq 130 ]]; then printf '\n' >&2; exit 130; fi
    }
    printf '\n' >&2
  fi
  printf '%s\n' "$answer"
  return $rc
}

# ui_confirm <prompt> [yes|no]  (default yes)
ui_confirm() {
  local prompt="$1" default="${2:-yes}" answer hint rc=0
  if _ui_gum; then
    if [[ "$default" == "yes" ]]; then
      gum confirm "$prompt" || _ui_gum_rc $?
    else
      gum confirm --default=false "$prompt" || _ui_gum_rc $?
    fi
    return $?
  fi
  if [[ "$default" == "yes" ]]; then hint="Y/n"; else hint="y/N"; fi
  printf '%s [%s]: ' "$prompt" "$hint" >&2
  IFS= read -r answer || {
    rc=$?
    if [[ $rc -eq 130 ]]; then exit 130; fi
    answer=""
  }
  case "$answer" in
    [Yy]*) return 0 ;;
    [Nn]*) return 1 ;;
    "") [[ "$default" == "yes" ]] ;;
    *) return 1 ;;
  esac
}

# ui_choose <prompt> <option...> -> prints the chosen option
# Plain mode accepts a number or the option's name; empty picks the first.
ui_choose() {
  local prompt="$1"
  shift
  local answer i opt n=$# rc=0
  if _ui_gum; then
    gum choose --header "$prompt" "$@" || _ui_gum_rc $?
    return $?
  fi
  printf '%s\n' "$prompt" >&2
  i=1
  for opt in "$@"; do
    printf '  %d) %s\n' "$i" "$opt" >&2
    i=$((i + 1))
  done
  printf 'Choice [1]: ' >&2
  IFS= read -r answer || {
    rc=$?
    if [[ $rc -eq 130 ]]; then exit 130; fi
    answer=""
  }
  if [[ -z "$answer" ]]; then
    printf '%s\n' "$1"
    return 0
  fi
  if [[ "$answer" =~ ^[0-9]+$ ]] && (( 10#$answer >= 1 && 10#$answer <= n )); then
    i=1
    for opt in "$@"; do
      if (( i == 10#$answer )); then printf '%s\n' "$opt"; return 0; fi
      i=$((i + 1))
    done
  fi
  for opt in "$@"; do
    if [[ "$opt" == "$answer" ]]; then printf '%s\n' "$opt"; return 0; fi
  done
  warn "Unknown choice '$answer'; using $1"
  printf '%s\n' "$1"
}
