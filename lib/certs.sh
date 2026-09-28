#!/usr/bin/env bash
# certs.sh - a CLI trust bundle for administrator-managed macOS roots.
# Safe to source from teeup's bash libraries and from the POSIX-shaped zsh
# environment layer. Rebuild functions require core.sh; applying an existing
# bundle uses only shell built-ins and uname.

ca_bundle_path() {
  printf '%s/ca-bundle.pem\n' "${TEEUP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/teeup}"
}

ca_bundle_curlrc_path() {
  printf '%s/ca-bundle.curlrc\n' "${TEEUP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/teeup}"
}

_ca_bundle_is_macos() {
  [ "$(uname -s 2>/dev/null)" = "Darwin" ]
}

# ca_bundle_apply_env
# The official mise release uses rustls-native-roots. That loader checks
# SSL_CERT_FILE before the platform store, so mise needs no separate setting.
# Homebrew documents that an absolute HOMEBREW_CURLRC is passed to curl with
# --config. Every assignment here is a default: an inherited value or a value
# written later in ~/.config/zsh/local.zsh wins, including an explicitly empty
# value.
ca_bundle_apply_env() {
  _ca_bundle_is_macos || return 0
  _teeup_ca_bundle="$(ca_bundle_path)"
  _teeup_ca_curlrc="$(ca_bundle_curlrc_path)"
  if [ -s "$_teeup_ca_bundle" ]; then
    if [ -z "${SSL_CERT_FILE+x}" ]; then SSL_CERT_FILE="$_teeup_ca_bundle"; export SSL_CERT_FILE; fi
    if [ -z "${GIT_SSL_CAINFO+x}" ]; then GIT_SSL_CAINFO="$_teeup_ca_bundle"; export GIT_SSL_CAINFO; fi
    if [ -z "${CURL_CA_BUNDLE+x}" ]; then CURL_CA_BUNDLE="$_teeup_ca_bundle"; export CURL_CA_BUNDLE; fi
    if [ -z "${REQUESTS_CA_BUNDLE+x}" ]; then REQUESTS_CA_BUNDLE="$_teeup_ca_bundle"; export REQUESTS_CA_BUNDLE; fi
    if [ -z "${NODE_EXTRA_CA_CERTS+x}" ]; then NODE_EXTRA_CA_CERTS="$_teeup_ca_bundle"; export NODE_EXTRA_CA_CERTS; fi
  fi
  if [ -s "$_teeup_ca_curlrc" ] && [ -z "${HOMEBREW_CURLRC+x}" ]; then
    HOMEBREW_CURLRC="$_teeup_ca_curlrc"
    export HOMEBREW_CURLRC
  fi
  unset _teeup_ca_bundle _teeup_ca_curlrc
}

_ca_bundle_clear_own_env() {
  local bundle curlrc
  bundle="$(ca_bundle_path)"
  curlrc="$(ca_bundle_curlrc_path)"
  [[ "${SSL_CERT_FILE:-}" == "$bundle" ]] && unset SSL_CERT_FILE
  [[ "${GIT_SSL_CAINFO:-}" == "$bundle" ]] && unset GIT_SSL_CAINFO
  [[ "${CURL_CA_BUNDLE:-}" == "$bundle" ]] && unset CURL_CA_BUNDLE
  [[ "${REQUESTS_CA_BUNDLE:-}" == "$bundle" ]] && unset REQUESTS_CA_BUNDLE
  [[ "${NODE_EXTRA_CA_CERTS:-}" == "$bundle" ]] && unset NODE_EXTRA_CA_CERTS
  [[ "${HOMEBREW_CURLRC:-}" == "$curlrc" ]] && unset HOMEBREW_CURLRC
  return 0
}

# ca_bundle_admin_roots_present -> 0 present, 1 confirmed empty, 2 unreadable.
# `security dump-trust-settings -d` is the gate because -d names the admin
# domain. Its count line is stable across supported macOS releases; accepting
# a `Cert N:` line as present also handles older output that omitted the count.
ca_bundle_admin_roots_present() {
  local output rc=0
  output="$(security dump-trust-settings -d 2>&1)" || rc=$?
  [[ $rc -eq 0 ]] || return 2
  if printf '%s\n' "$output" | grep -Eq '^Cert [0-9]+:|^Number of trusted certs = [1-9][0-9]*$'; then
    return 0
  fi
  if printf '%s\n' "$output" | grep -Eq '^Number of trusted certs = 0$|No Trust Settings were found'; then
    return 1
  fi
  return 2
}

ca_bundle_remove() {
  local bundle curlrc
  bundle="$(ca_bundle_path)"
  curlrc="$(ca_bundle_curlrc_path)"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    [[ ! -e "$bundle" && ! -e "$curlrc" ]] || run_cmd rm -f "$bundle" "$curlrc"
    return 0
  fi
  rm -f "$bundle" "$curlrc"
  _ca_bundle_clear_own_env
}

_ca_bundle_fail() {
  local work="$1"
  shift
  rm -rf "$work"
  warn "$*"
  return 1
}

# ca_bundle_rebuild
# security's admin trust export is a plist whose trustList dictionary is keyed
# by SHA-1 certificate hashes. Convert it to XML, read those keys, then match
# them against the `SHA-1 hash:` records paired with PEM blocks from
# `security find-certificate -a -Z -p /Library/Keychains/System.keychain`.
# This deliberately does not append the whole System keychain: applications
# store certificates there that have no administrator trust setting, and a PEM
# bundle would otherwise promote every one of them to a trust anchor.
ca_bundle_rebuild() {
  _ca_bundle_is_macos || return 0
  local roots_rc=0
  ca_bundle_admin_roots_present || roots_rc=$?
  case "$roots_rc" in
    0) ;;
    1)
      ca_bundle_remove
      return 0
      ;;
    *)
      warn "Could not read the administrator certificate trust settings; the existing CA bundle was kept."
      return 1
      ;;
  esac

  local state_dir bundle curlrc work trust_plist trust_xml hashes
  local system_pem system_records admin_pem staged_bundle staged_curlrc plutil
  state_dir="${TEEUP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/teeup}"
  bundle="$(ca_bundle_path)"
  curlrc="$(ca_bundle_curlrc_path)"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log "[DRY-RUN] Would rebuild the command-line CA bundle at $bundle"
    return 0
  fi
  mkdir -p "$state_dir" || return 1
  work="$(mktemp -d "$state_dir/.ca-bundle.XXXXXX")" || return 1
  trust_plist="$work/admin-trust.plist"
  trust_xml="$work/admin-trust.xml"
  hashes="$work/admin-hashes"
  system_pem="$work/system-roots.pem"
  system_records="$work/system-records.pem"
  admin_pem="$work/admin-roots.pem"
  staged_bundle="$work/ca-bundle.pem"
  staged_curlrc="$work/ca-bundle.curlrc"
  plutil="${TEEUP_PLUTIL:-/usr/bin/plutil}"

  security trust-settings-export -d "$trust_plist" >/dev/null 2>&1 ||
    _ca_bundle_fail "$work" "Could not export the administrator certificate trust settings; the existing CA bundle was kept." || return 1
  [[ -s "$trust_plist" ]] ||
    _ca_bundle_fail "$work" "The administrator certificate trust export was empty; the existing CA bundle was kept." || return 1
  "$plutil" -convert xml1 -o "$trust_xml" "$trust_plist" >/dev/null 2>&1 ||
    _ca_bundle_fail "$work" "Could not read the administrator certificate trust export; the existing CA bundle was kept." || return 1
  sed -n 's/.*<key>\([0-9A-Fa-f]\{40\}\)<\/key>.*/\1/p' "$trust_xml" |
    tr '[:lower:]' '[:upper:]' > "$hashes"
  [[ -s "$hashes" ]] ||
    _ca_bundle_fail "$work" "The administrator certificate trust export contained no certificate hashes; the existing CA bundle was kept." || return 1

  security find-certificate -a -p "${TEEUP_SYSTEM_ROOT_KEYCHAIN:-/System/Library/Keychains/SystemRootCertificates.keychain}" > "$system_pem" 2>/dev/null ||
    _ca_bundle_fail "$work" "Could not export the macOS public roots; the existing CA bundle was kept." || return 1
  grep -q '^-----BEGIN CERTIFICATE-----$' "$system_pem" ||
    _ca_bundle_fail "$work" "The macOS public-root export was empty; the existing CA bundle was kept." || return 1

  security find-certificate -a -Z -p "${TEEUP_SYSTEM_KEYCHAIN:-/Library/Keychains/System.keychain}" > "$system_records" 2>/dev/null ||
    _ca_bundle_fail "$work" "Could not export certificates from the System keychain; the existing CA bundle was kept." || return 1
  awk -v hashes="$hashes" '
    BEGIN {
      while ((getline hash < hashes) > 0) { wanted[toupper(hash)] = 1 }
      close(hashes)
    }
    /^SHA-1 hash: / {
      hash = toupper(substr($0, 13))
      selected = (hash in wanted)
      next
    }
    selected && /^-----BEGIN CERTIFICATE-----$/ { in_cert = 1 }
    selected && in_cert { print }
    selected && /^-----END CERTIFICATE-----$/ { matched[hash] = 1; in_cert = 0; selected = 0 }
    END {
      for (hash in wanted) if (!(hash in matched)) exit 3
    }
  ' "$system_records" > "$admin_pem" ||
    _ca_bundle_fail "$work" "An administrator-trusted certificate was not found in the System keychain; the existing CA bundle was kept." || return 1
  grep -q '^-----BEGIN CERTIFICATE-----$' "$admin_pem" ||
    _ca_bundle_fail "$work" "The administrator certificate export was empty; the existing CA bundle was kept." || return 1

  cat "$system_pem" "$admin_pem" > "$staged_bundle" ||
    _ca_bundle_fail "$work" "Could not stage the command-line CA bundle; the existing bundle was kept." || return 1
  local curl_bundle
  curl_bundle="$(printf '%s' "$bundle" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf 'cacert = "%s"\n' "$curl_bundle" > "$staged_curlrc" ||
    _ca_bundle_fail "$work" "Could not stage Homebrew's curl configuration; the existing CA bundle was kept." || return 1

  if [[ -f "$bundle" ]] && cmp -s "$staged_bundle" "$bundle"; then
    rm -f "$staged_bundle"
  else
    mv "$staged_bundle" "$bundle" ||
      _ca_bundle_fail "$work" "Could not install the command-line CA bundle; the existing bundle was kept." || return 1
  fi
  if [[ -f "$curlrc" ]] && cmp -s "$staged_curlrc" "$curlrc"; then
    rm -f "$staged_curlrc"
  else
    mv "$staged_curlrc" "$curlrc" ||
      _ca_bundle_fail "$work" "Could not install Homebrew's curl configuration." || return 1
  fi
  rm -rf "$work"
  ca_bundle_apply_env
}

ca_bundle_is_current() {
  local bundle curlrc roots keychain
  bundle="$(ca_bundle_path)"
  curlrc="$(ca_bundle_curlrc_path)"
  roots="${TEEUP_SYSTEM_ROOT_KEYCHAIN:-/System/Library/Keychains/SystemRootCertificates.keychain}"
  keychain="${TEEUP_SYSTEM_KEYCHAIN:-/Library/Keychains/System.keychain}"
  [[ -s "$bundle" && -s "$curlrc" ]] || return 1
  grep -qF "$bundle" "$curlrc" || return 1
  [[ ! -e "$roots" || ! "$roots" -nt "$bundle" ]] || return 1
  [[ ! -e "$keychain" || ! "$keychain" -nt "$bundle" ]] || return 1
  return 0
}

# Sourcing this file is the shared environment path for teeup, lazy shims and
# the user's shells. It does not rebuild or touch the filesystem.
ca_bundle_apply_env
