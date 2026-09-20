#!/usr/bin/env bash
# hooks.sh - the user's own scripts, run when teeup finishes something.
# $TEEUP_CONFIG_DIR/hooks/<event>.d/ holds any number of scripts. Each one runs
# with bash, in file name order, with the event's arguments; a *.sample file is
# documentation and never runs. A hook that fails warns and never aborts what
# fired it (spec section 7; Omarchy's omarchy-hook does the same).
#
#   post-bootstrap   after ./bootstrap, before its summary        (no arguments)
#   post-update      at the end of teeup update                  ($1: the capability, or nothing)
#   theme-set        after a theme is rendered and applied        ($1: the theme name)
#
# Requires core.sh.

TEEUP_HOOK_EVENTS="post-bootstrap post-update theme-set"
export TEEUP_HOOK_EVENTS

hooks_dir() { printf '%s/hooks\n' "$TEEUP_CONFIG_DIR"; }

# hook_run <event> [args...]
# Always returns 0. stdin is /dev/null (run_logged with interactive=false), so
# a hook that prompts cannot stall an update. In a dry run the hooks are named
# and not run: they are the user's scripts, and nothing says they honour
# DRY_RUN.
hook_run() {
  local event="$1" dir f rc
  shift
  case " $TEEUP_HOOK_EVENTS " in
    *" $event "*) ;;
    *)
      warn "hook_run: unknown event '$event' (expected one of: $TEEUP_HOOK_EVENTS)"
      return 0
      ;;
  esac
  dir="$(hooks_dir)/$event.d"
  [[ -d "$dir" ]] || return 0
  for f in "$dir"/*; do
    [[ -f "$f" ]] || continue
    case "$f" in *.sample) continue ;; esac
    if [[ "$DRY_RUN" == "true" ]]; then
      printf "%b %s\n" "🔍" "[DRY-RUN] Would run hook: $f $*"
      continue
    fi
    rc=0
    run_logged "hook $event ${f##*/}" false env TEEUP_HOOK_EVENT="$event" bash "$f" "$@" || rc=$?
    if [[ $rc -ne 0 ]]; then
      warn "Hook $f failed (exit code $rc); continuing."
    fi
  done
  return 0
}
