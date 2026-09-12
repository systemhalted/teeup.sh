#!/usr/bin/env bash
# answers.sh - the profile: a sourceable KEY="value" file written once by the
# bootstrap wizard, plus a committed per-machine override file.
# Requires core.sh.

TEEUP_MACHINES_DIR="${TEEUP_MACHINES_DIR:-$TEEUP_PATH/machines}"
export TEEUP_MACHINES_DIR

answers_file() { printf '%s/answers\n' "$TEEUP_CONFIG_DIR"; }

machine_file() {
  local host
  host="$(hostname -s 2>/dev/null || hostname)"
  printf '%s/%s.conf\n' "$TEEUP_MACHINES_DIR" "$host"
}

answers_exist() { [[ -s "$(answers_file)" ]]; }

# Load answers, then the machine file. The machine file is sourced last on
# purpose: it encodes hard constraints (package manager, skipped capabilities).
answers_load() {
  local f
  f="$(answers_file)"
  # shellcheck source=/dev/null
  [[ -f "$f" ]] && source "$f"
  f="$(machine_file)"
  # shellcheck source=/dev/null
  [[ -f "$f" ]] && source "$f"
  return 0
}

# answers_get <KEY> [default]
answers_get() {
  local key="$1" default="${2:-}" value
  value="${!key:-}"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default"
  fi
}

# answers_set <KEY> <value>
# Rewrites the file: drop the old line for KEY, append the new one, keep the
# file sorted so diffs stay readable. Values are written with %q-free double
# quoting; backslashes, dollars and double quotes are escaped by hand because
# the file is sourced by bash.
answers_set() {
  local key="$1" value="$2" f tmp escaped
  f="$(answers_file)"
  case "$key" in
    TEEUP_[A-Z0-9_]*) ;;
    *) die "answers_set: key must look like TEEUP_NAME, got '$key'" ;;
  esac
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would set $key in $f"
    return 0
  fi
  mkdir -p "$(dirname "$f")"
  touch "$f"
  escaped="$(printf '%s' "$value" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\$/g' -e 's/`/\\`/g')"
  tmp="$(mktemp)"
  { grep -v "^${key}=" "$f" || true; printf '%s="%s"\n' "$key" "$escaped"; } | sort > "$tmp"
  mv "$tmp" "$f"
  chmod 600 "$f"
  export "$key=$value"
}
