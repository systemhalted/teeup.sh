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

# identity_gh_account <identity> -> the GitHub login `gh` must be switched to
# before this identity's key is uploaded, or nothing when there is nothing to
# switch. GH_HOST selects a host, and a host has exactly one active account,
# so two identities on github.com (a work account beside a personal one) can
# only be told apart by the account itself: machines/<hostname>.conf names it
# in TEEUP_WORK_GH_ACCOUNT and the github capability switches with
# `gh auth switch --hostname <host> --user <account>`. Personal is whatever
# account the user signed in with; teeup never switches away from it except to
# do the work upload, and switches back afterwards.
identity_gh_account() {
  case "$1" in
    personal) printf '\n' ;;
    work) work_get TEEUP_WORK_GH_ACCOUNT ;;
    *) die "identity_gh_account: unknown identity '$1' (expected personal or work)" ;;
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

# _ssh_identity_files <config file> <host> -> the IdentityFile lines ssh
# resolves for <host> from <config file>, one per line, verbatim (a leading ~
# and a relative path are still ssh's spellings here). Fails, printing
# nothing, when ssh cannot read the file.
#
# What a config means is ssh's question, not teeup's. Parsing it by hand got
# every real-world spelling wrong -- a trailing comment became part of the
# path, a relative path resolved against the current directory, lowercase
# keywords and the `=` form were missed, `Host *` and a pre-Host global
# IdentityFile were missed, a `Match` block donated its key to the Host block
# above it, and `Include` was not followed at all -- so ssh is asked instead.
# -F pins it to exactly this file, so teeup never reads a config it was not
# pointed at.
_ssh_identity_files() {
  local config="$1" host="$2" out line
  out="$(ssh -G -F "$config" -- "$host" 2>/dev/null)" || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "identityfile "*) printf '%s\n' "${line#identityfile }" ;;
    esac
  done <<EOF
$out
EOF
}

# _ssh_path_expand <ssh path> -> the path ssh would actually open: ~ and %d
# are the user's home, and a relative path is relative to ~/.ssh, not to the
# current directory.
_ssh_path_expand() {
  # shellcheck disable=SC2088  # the tilde is a literal token from ssh, not a path
  case "$1" in
    "~/"*) printf '%s/%s\n' "$HOME" "${1#\~/}" ;;
    "~") printf '%s\n' "$HOME" ;;
    "%d/"*) printf '%s/%s\n' "$HOME" "${1#%d/}" ;;
    "%d") printf '%s\n' "$HOME" ;;
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/.ssh/%s\n' "$HOME" "$1" ;;
  esac
}

# ssh_config_named_key <identity> -> the key the user's own ~/.ssh/config
# names for this identity's Host alias, expanded to a usable path; fails
# (printing nothing) when the config names none.
#
# "Names one" means: something other than the keys ssh falls back to on its
# own. ssh -G always reports an identityfile list -- its built-in candidates
# (~/.ssh/id_rsa, ~/.ssh/id_ed25519 and friends) when the config says nothing
# -- so the same question is put to ssh twice, once with the user's config and
# once with none, and the lines the two answers do not share are the user's
# deliberate choice. A config that names one of ssh's own default paths on
# purpose still counts: the two lists then differ in order or length, and its
# first entry is what ssh would offer first.
ssh_config_named_key() {
  local identity="$1" alias config user_keys default_keys key chosen="" first=""
  alias="$(ssh_host_alias "$identity")"
  config="$HOME/.ssh/config"
  [[ -f "$config" ]] || return 1
  if ! have ssh; then
    warn "ssh is not installed, so $config cannot be read; using teeup's own key path."
    return 1
  fi
  if ! user_keys="$(_ssh_identity_files "$config" "$alias")"; then
    warn "ssh could not read $config (run: ssh -G $alias); using teeup's own key path."
    return 1
  fi
  default_keys="$(_ssh_identity_files /dev/null "$alias")" || return 1
  [[ "$user_keys" == "$default_keys" ]] && return 1
  while IFS= read -r key || [[ -n "$key" ]]; do
    [[ -n "$key" ]] || continue
    [[ -n "$first" ]] || first="$key"
    _ssh_list_contains "$default_keys" "$key" && continue
    chosen="$key"
    break
  done <<EOF
$user_keys
EOF
  [[ -n "$chosen" ]] || chosen="$first"
  [[ -n "$chosen" ]] || return 1
  _ssh_path_expand "$chosen"
}

# _ssh_list_contains <newline-separated list> <value>: an exact, literal
# match. `case` would read a key path containing * or ? as a pattern.
_ssh_list_contains() {
  local item
  while IFS= read -r item || [[ -n "$item" ]]; do
    [[ "$item" == "$2" ]] && return 0
  done <<EOF
$1
EOF
  return 1
}

# ssh_config_identity_file <identity> -> the key an existing ~/.ssh/config
# names for this identity, but only when that key is really there and readable.
# This is what makes an existing ~/.ssh/config authority: identity_key below
# prefers whatever key the user already has wired up over teeup's own naming
# convention. A named key that does not exist is not a key to reuse -- teeup
# would have had to create it, at a path ssh may spell differently, and then
# claim it had reused it -- so it falls through to teeup's own convention. -f
# and -r, not -e: a dangling symlink and a directory are both "there" to -e.
ssh_config_identity_file() {
  local key
  key="$(ssh_config_named_key "$1")" || return 1
  [[ -f "$key" && -r "$key" ]] || return 1
  printf '%s\n' "$key"
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
