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

# The wizard is the only writer of TEEUP_NAME, so its presence means the
# questions were answered; capabilities may record other keys earlier.
answers_exist() {
  local f
  f="$(answers_file)"
  [[ -s "$f" ]] && grep -q '^TEEUP_NAME=' "$f"
}

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
  local key="$1" value="$2" f tmp escaped line
  f="$(answers_file)"
  if ! [[ "$key" =~ ^TEEUP_[A-Z0-9_]+$ ]]; then
    die "answers_set: key must look like TEEUP_NAME, got '$key'"
  fi
  export "$key=$value"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would set $key in $f"
    return 0
  fi
  mkdir -p "$(dirname "$f")"
  touch "$f"
  escaped="$(printf '%s' "$value" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\$/g' -e 's/`/\\`/g')"
  tmp="$(mktemp)"
  # Drop the old line for KEY with the shell rather than grep, so the key is
  # never interpreted as a regular expression.
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in "$key="*) continue ;; esac
    printf '%s\n' "$line"
  done < "$f" > "$tmp"
  printf '%s="%s"\n' "$key" "$escaped" >> "$tmp"
  sort -o "$tmp" "$tmp"
  mv "$tmp" "$f"
  chmod 600 "$f"
}

# Identity helpers. git, ssh and github all key off the same two identities,
# so the mapping from identity name to email and key path lives here once.
# Work exists only when the wizard was given a work email; otherwise both
# directory roots use the personal identity.
answers_has_work() { [[ -n "$(answers_get TEEUP_WORK_EMAIL)" ]]; }

identity_list() {
  printf 'personal\n'
  answers_has_work && printf 'work\n'
  return 0
}

identity_email() {
  case "$1" in
    personal) answers_get TEEUP_EMAIL ;;
    work)
      if answers_has_work; then answers_get TEEUP_WORK_EMAIL; else answers_get TEEUP_EMAIL; fi
      ;;
    *) die "identity_email: unknown identity '$1' (expected personal or work)" ;;
  esac
}

identity_key() {
  case "$1" in
    personal|work) printf '%s/.ssh/id_ed25519_%s\n' "$HOME" "$1" ;;
    *) die "identity_key: unknown identity '$1' (expected personal or work)" ;;
  esac
}
