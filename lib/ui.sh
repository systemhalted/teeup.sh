#!/usr/bin/env bash
# ui.sh - prompts over gum with plain read fallbacks. Every function reads
# from stdin so tests can pipe answers; gum draws on /dev/tty by itself.
# Requires core.sh.

_ui_gum() { [[ -z "${TEEUP_NO_GUM:-}" ]] && have gum; }

# ui_input <prompt> [default] -> prints the answer
ui_input() {
  local prompt="$1" default="${2:-}" answer
  if _ui_gum; then
    answer="$(gum input --prompt "$prompt: " --value "$default" --placeholder "$default")" || answer=""
  else
    printf '%s' "$prompt" >&2
    [[ -n "$default" ]] && printf ' [%s]' "$default" >&2
    printf ': ' >&2
    IFS= read -r answer || answer=""
  fi
  [[ -z "$answer" ]] && answer="$default"
  printf '%s\n' "$answer"
}

# ui_confirm <prompt> [yes|no]  (default yes)
ui_confirm() {
  local prompt="$1" default="${2:-yes}" answer hint
  if _ui_gum; then
    if [[ "$default" == "yes" ]]; then
      gum confirm "$prompt"
    else
      gum confirm --default=false "$prompt"
    fi
    return $?
  fi
  if [[ "$default" == "yes" ]]; then hint="Y/n"; else hint="y/N"; fi
  printf '%s [%s]: ' "$prompt" "$hint" >&2
  IFS= read -r answer || answer=""
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
  local answer i opt n=$#
  if _ui_gum; then
    gum choose --header "$prompt" "$@"
    return $?
  fi
  printf '%s\n' "$prompt" >&2
  i=1
  for opt in "$@"; do
    printf '  %d) %s\n' "$i" "$opt" >&2
    i=$((i + 1))
  done
  printf 'Choice [1]: ' >&2
  IFS= read -r answer || answer=""
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
