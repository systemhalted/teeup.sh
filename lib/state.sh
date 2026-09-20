#!/usr/bin/env bash
# state.sh - state as file existence under ~/.local/state/teeup.
# done/<name>        one-shot completion markers
# toggles/<flag>     boolean feature flags (existence = on)
# migrations/<id>    applied migration markers
# Requires core.sh.

_state_touch() {
  local marker="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would record state: ${marker#"$TEEUP_STATE_DIR"/}"
    return 0
  fi
  mkdir -p "$(dirname "$marker")"
  : > "$marker"
}

_state_remove() {
  local marker="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would clear state: ${marker#"$TEEUP_STATE_DIR"/}"
    return 0
  fi
  # A state directory the user (or a bad umask) made unwritable would leak a
  # raw "rm: cannot remove ...: Permission denied" and, under `bash -eu`,
  # abort the caller mid-way -- for `teeup remove` that is after the packages
  # are already gone, with no teeup message at all (I4). Say what happened and
  # let the caller decide, the way stock_record does.
  if ! rm -f "$marker" 2>/dev/null; then
    warn "Could not clear ${marker#"$TEEUP_STATE_DIR"/}; teeup still has it on record."
    return 1
  fi
}

# state_done check|mark|ensure|clear <name>
# ensure: succeeds only the first time (noclobber makes it atomic), so it
# doubles as a "show this once" primitive.
state_done() {
  local op="$1" name="$2"
  local marker="$TEEUP_STATE_DIR/done/$name"
  case "$op" in
    check) [[ -f "$marker" ]] ;;
    mark) _state_touch "$marker" ;;
    clear) _state_remove "$marker" ;;
    ensure)
      # A dry run must preview the answer the real run would give, not always
      # say "first time": a caller that prints a long one-off notice on 0 and
      # a short line otherwise would otherwise show the long one on every
      # preview, including on a machine that has already seen it.
      if [[ "$DRY_RUN" == "true" ]]; then
        [[ -f "$marker" ]] && return 1
        _state_touch "$marker"
        return 0
      fi
      mkdir -p "$(dirname "$marker")"
      (set -o noclobber; : > "$marker") 2>/dev/null
      ;;
    *) die "state_done: unknown op '$op'" ;;
  esac
}

# state_na check|mark|clear <name>
# A capability a machine cannot have at all: cap_install_verbs marks this
# instead of state_done when install or configure answered not_applicable,
# so `teeup status` can tell "not applicable here" apart from both
# "installed" and plain absence. Never set by hand -- see not_applicable in
# lib/capability.sh.
state_na() {
  local op="$1" name="$2"
  local marker="$TEEUP_STATE_DIR/na/$name"
  case "$op" in
    check) [[ -f "$marker" ]] ;;
    mark) _state_touch "$marker" ;;
    clear) _state_remove "$marker" ;;
    *) die "state_na: unknown op '$op'" ;;
  esac
}

# state_toggle <flag> [on|off|toggle]
state_toggle() {
  local flag="$1" op="${2:-toggle}"
  local marker="$TEEUP_STATE_DIR/toggles/$flag"
  case "$op" in
    on) _state_touch "$marker" ;;
    off) _state_remove "$marker" ;;
    toggle) if [[ -f "$marker" ]]; then _state_remove "$marker"; else _state_touch "$marker"; fi ;;
    *) die "state_toggle: unknown op '$op'" ;;
  esac
}

state_toggle_enabled() { [[ -f "$TEEUP_STATE_DIR/toggles/$1" ]]; }

state_migration_done() { [[ -f "$TEEUP_STATE_DIR/migrations/$1" ]]; }
state_migration_mark() { _state_touch "$TEEUP_STATE_DIR/migrations/$1"; }
