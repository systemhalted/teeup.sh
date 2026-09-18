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

# machine_get <KEY> -> prints the value machines/<hostname>.conf sets for KEY
# and exits 0; exits 1 (printing nothing) when the file does not set it. An
# empty value counts as set: `TEEUP_PACKAGE_MANAGER=""` in the machine file is
# a pin too (it means "detect", and answers_load will enforce it). Read in a
# subshell so the lookup neither changes this shell nor is fooled by a KEY
# already exported from the answers file.
machine_get() {
  local key="$1" f
  f="$(machine_file)"
  [[ -f "$f" ]] || return 1
  (
    unset "$key"
    # shellcheck source=/dev/null
    source "$f"
    [[ -n "${!key+x}" ]] || exit 1
    printf '%s\n' "${!key}"
  )
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
  # A newline would split across lines once written, and sort would then
  # interleave the halves with other keys, leaving the answers file unable to
  # be sourced at all.
  case "$value" in
    *$'\n'*) die "answers_set: value for $key cannot contain a newline" ;;
  esac
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

# answers_unset <KEY>
# Drop KEY from the answers file and from this shell, and say whether there was
# anything to drop (0 = removed, 1 = the key was not there). The wizard uses it
# to clear answers to questions it no longer asks: a value the tool can neither
# ask about nor change is one only a text editor could ever remove.
answers_unset() {
  local key="$1" f tmp line found=false
  f="$(answers_file)"
  if ! [[ "$key" =~ ^TEEUP_[A-Z0-9_]+$ ]]; then
    die "answers_unset: key must look like TEEUP_NAME, got '$key'"
  fi
  [[ -f "$f" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in "$key="*) found=true ;; esac
  done < "$f"
  [[ "$found" == "true" ]] || return 1
  # Also out of this process: answers_load sourced (and answers_set exported)
  # the value, so leaving it set would let the rest of this run read an answer
  # the file no longer holds.
  unset "$key"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would remove $key from $f"
    return 0
  fi
  tmp="$(mktemp)"
  # Matched with the shell, not grep, so the key is never read as a regex.
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in "$key="*) continue ;; esac
    printf '%s\n' "$line"
  done < "$f" > "$tmp"
  mv "$tmp" "$f"
  chmod 600 "$f"
  return 0
}

# Identity helpers. git, ssh and github all key off the same one-or-two
# identities, so the mapping from identity name to email, key path and
# GitHub host lives here once.
#
# work_get <KEY> [default] -> the work identity's settings, read from
# machines/<hostname>.conf and nowhere else. The wizard never asks about work,
# so an answers-file TEEUP_WORK_EMAIL can only be a leftover from the wizard
# that used to: reading it would hand an upgraded machine a second key, a
# second passphrase and a second upload from a question the tool no longer
# admits exists. answers_get cannot make that distinction -- it reads whatever
# is in scope, the sourced answers file included -- so work settings never go
# through it.
work_get() {
  local key="$1" default="${2:-}" value
  if value="$(machine_get "$key")" && [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default"
  fi
}

answers_has_work() { [[ -n "$(work_get TEEUP_WORK_EMAIL)" ]]; }

identity_list() {
  printf 'personal\n'
  answers_has_work && printf 'work\n'
  return 0
}

identity_email() {
  case "$1" in
    personal) answers_get TEEUP_EMAIL ;;
    work)
      if answers_has_work; then work_get TEEUP_WORK_EMAIL; else answers_get TEEUP_EMAIL; fi
      ;;
    *) die "identity_email: unknown identity '$1' (expected personal or work)" ;;
  esac
}

# identity_gh_host <identity> -> the GitHub host `gh` talks to for this
# identity. Personal is always github.com; work defaults to github.com too,
# but machines/<hostname>.conf can point it at a GitHub Enterprise host by
# naming it in TEEUP_WORK_GH_HOST.
identity_gh_host() {
  case "$1" in
    personal) printf 'github.com\n' ;;
    work) work_get TEEUP_WORK_GH_HOST github.com ;;
    *) die "identity_gh_host: unknown identity '$1' (expected personal or work)" ;;
  esac
}

# ssh_host_alias <identity> -> the Host name teeup's own shipped ssh config
# (capabilities/ssh/config/ssh/config) uses for this identity. Fixed, unlike
# identity_gh_host: it names a *local* alias, not the real GitHub host, so a
# work identity on a GitHub Enterprise host still clones through
# git@github.com-work:org/repo.git.
ssh_host_alias() {
  case "$1" in
    personal) printf 'github.com\n' ;;
    work) printf 'github.com-work\n' ;;
    *) die "ssh_host_alias: unknown identity '$1' (expected personal or work)" ;;
  esac
}

# ssh_config_identity_file <identity> -> prints the IdentityFile an existing
# ~/.ssh/config already names for this identity's Host alias, and fails
# (printing nothing) when there is no such config, no matching Host block, or
# no IdentityFile inside it. This is what makes an existing ~/.ssh/config
# authority: identity_key below prefers whatever key the user already has
# wired up over teeup's own naming convention. A leading ~ is expanded to
# $HOME the way ssh itself expands it, so callers get a plain, usable path.
# bash 3.2-safe: no associative arrays, no extended globs.
ssh_config_identity_file() {
  local identity="$1" alias config line trimmed rest word in_block=false found=""
  alias="$(ssh_host_alias "$identity")"
  config="$HOME/.ssh/config"
  [[ -f "$config" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in
      Host[[:space:]]*)
        in_block=false
        rest="${trimmed#Host}"
        for word in $rest; do
          [[ "$word" == "$alias" ]] && in_block=true
        done
        ;;
      IdentityFile[[:space:]]*)
        if [[ "$in_block" == "true" && -z "$found" ]]; then
          found="${trimmed#IdentityFile}"
          found="${found#"${found%%[![:space:]]*}"}"
          found="${found%\"}"
          found="${found#\"}"
          # shellcheck disable=SC2088  # the tilde is a literal token here, not a path
          case "$found" in
            "~/"*) found="$HOME/${found#\~/}" ;;
            "~") found="$HOME" ;;
          esac
        fi
        ;;
    esac
  done < "$config"
  [[ -n "$found" ]] || return 1
  printf '%s\n' "$found"
}

# identity_key <identity> -> the private-key path this identity signs and
# authenticates with. An existing ~/.ssh/config naming an IdentityFile for
# this identity's host alias wins (see ssh_config_identity_file); otherwise
# teeup's own convention, $HOME/.ssh/id_ed25519_<identity>, which is also
# what a fresh machine gets once the ssh capability has generated it.
identity_key() {
  local reused
  case "$1" in
    personal|work)
      if reused="$(ssh_config_identity_file "$1")"; then
        printf '%s\n' "$reused"
      else
        printf '%s/.ssh/id_ed25519_%s\n' "$HOME" "$1"
      fi
      ;;
    *) die "identity_key: unknown identity '$1' (expected personal or work)" ;;
  esac
}
