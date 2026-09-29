#!/usr/bin/env bash
# certs.sh - a CLI trust bundle for administrator-managed macOS roots.
# Safe to source from teeup's bash libraries and from the POSIX-shaped zsh
# environment layer. Rebuild functions require core.sh; applying an existing
# bundle uses only shell built-ins and uname.

ca_bundle_path() {
  printf '%s/ca-bundle.pem\n' "${TEEUP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/teeup}"
}

ca_bundle_checked_path() {
  printf '%s/ca-bundle.checked\n' "${TEEUP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/teeup}"
}

ca_bundle_curlrc_path() {
  printf '%s/ca-bundle.curlrc\n' "${TEEUP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/teeup}"
}

_ca_bundle_is_macos() {
  [ "$(uname -s 2>/dev/null)" = "Darwin" ]
}

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

ca_bundle_admin_roots_present() {
  local output rc=0
  output="$(security dump-trust-settings -d 2>&1)" || rc=$?
  if printf '%s\n' "$output" | grep -Eq '^Number of trusted certs = 0$|No Trust Settings were found'; then
    return 1
  fi
  [[ $rc -eq 0 ]] || return 2
  if printf '%s\n' "$output" | grep -Eq '^Cert [0-9]+:|^Number of trusted certs = [1-9][0-9]*$'; then
    return 0
  fi
  return 2
}

ca_bundle_remove() {
  local bundle curlrc
  bundle="$(ca_bundle_path)"
  curlrc="$(ca_bundle_curlrc_path)"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    [[ ! -e "$bundle" && ! -e "$curlrc" ]] || run_cmd rm -f "$bundle" "$curlrc" "$(ca_bundle_checked_path)"
    return 0
  fi
  rm -f "$bundle" "$curlrc" "$(ca_bundle_checked_path)"
  _ca_bundle_clear_own_env
}

_ca_bundle_fail() {
  local work="$1"
  shift
  rm -rf "$work"
  warn "$*"
  return 1
}

_ca_bundle_trusted_hashes() {
  awk 'BEGIN { RS = "<" }
    NR == 1 { next }
    {
      tag = $0; sub(/>.*/, "", tag)
      text = $0; sub(/^[^>]*>/, "", text); gsub(/[ \t\r\n]/, "", text)
    }
    tag == "key" && cur == "" && length(text) == 40 && text !~ /[^0-9A-Fa-f]/ {
      cur = toupper(text); cdepth = depth; entries = 0; bare = 0; trust = 0; deny = 0
      next
    }
    tag == "dict" {
      depth++
      if (cur != "" && depth == cdepth + 2) { entries++; has_result = 0 }
      next
    }
    tag == "dict/" {
      if (cur != "" && depth == cdepth + 1) { entries++; bare++ }
      next
    }
    tag == "/dict" {
      if (cur != "" && depth == cdepth + 2 && !has_result) bare++
      depth--
      if (cur != "" && depth == cdepth) {
        if (!deny && (trust || bare > 0 || entries == 0)) print cur
        cur = ""
      }
      next
    }
    tag == "key" && cur != "" && text == "kSecTrustSettingsResult" { want_result = 1; next }
    tag == "integer" && want_result {
      want_result = 0; has_result = 1
      if (text == 3) deny = 1
      else if (text == 1 || text == 2) trust = 1
      next
    }
    tag !~ /^\// { want_result = 0 }
  ' "$1"
}

_ca_bundle_stage() {
  local work="$1"
  local for_doctor="${2:-false}"

  local bundle trust_plist trust_xml hashes
  local system_pem system_records admin_pem staged_bundle staged_curlrc plutil
  bundle="$(ca_bundle_path)"
  trust_plist="$work/admin-trust.plist"
  trust_xml="$work/admin-trust.xml"
  hashes="$work/admin-hashes"
  system_pem="$work/system-roots.pem"
  system_records="$work/system-records.pem"
  admin_pem="$work/admin-roots.pem"
  staged_bundle="$work/ca-bundle.pem"
  staged_curlrc="$work/ca-bundle.curlrc"
  plutil="${TEEUP_PLUTIL:-/usr/bin/plutil}"

  if ! security trust-settings-export -d "$trust_plist" >/dev/null 2>&1; then
    [[ "$for_doctor" == "true" ]] || warn "Could not export the administrator certificate trust settings; the existing CA bundle was kept."
    return 1
  fi
  if [[ ! -s "$trust_plist" ]]; then
    [[ "$for_doctor" == "true" ]] || warn "The administrator certificate trust export was empty; the existing CA bundle was kept."
    return 1
  fi
  if ! "$plutil" -convert xml1 -o "$trust_xml" "$trust_plist" >/dev/null 2>&1; then
    [[ "$for_doctor" == "true" ]] || warn "Could not read the administrator certificate trust export; the existing CA bundle was kept."
    return 1
  fi
  if ! grep -Eq '<key>[0-9A-Fa-f]{40}</key>' "$trust_xml"; then
    [[ "$for_doctor" == "true" ]] || warn "The administrator certificate trust export contained no certificate hashes; the existing CA bundle was kept."
    return 1
  fi
  if ! _ca_bundle_trusted_hashes "$trust_xml" > "$hashes"; then
    [[ "$for_doctor" == "true" ]] || warn "Could not read the administrator certificate trust export; the existing CA bundle was kept."
    return 1
  fi
  if [[ ! -s "$hashes" ]]; then
    return 2
  fi

  if ! security find-certificate -a -p "${TEEUP_SYSTEM_ROOT_KEYCHAIN:-/System/Library/Keychains/SystemRootCertificates.keychain}" > "$system_pem" 2>/dev/null; then
    [[ "$for_doctor" == "true" ]] || warn "Could not export the macOS public roots; the existing CA bundle was kept."
    return 1
  fi
  if ! grep -q '^-----BEGIN CERTIFICATE-----$' "$system_pem"; then
    [[ "$for_doctor" == "true" ]] || warn "The macOS public-root export was empty; the existing CA bundle was kept."
    return 1
  fi

  if ! security find-certificate -a -Z -p "${TEEUP_SYSTEM_KEYCHAIN:-/Library/Keychains/System.keychain}" > "$system_records" 2>/dev/null; then
    [[ "$for_doctor" == "true" ]] || warn "Could not export certificates from the System keychain; the existing CA bundle was kept."
    return 1
  fi
  if ! awk -v hashes="$hashes" '
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
      for (hash in wanted) if (!(hash in matched)) print hash > missing
    }
  ' missing="$work/missing" "$system_records" > "$admin_pem"; then
    [[ "$for_doctor" == "true" ]] || warn "Could not read the System keychain export; the existing CA bundle was kept."
    return 1
  fi

  if [[ -s "$work/missing" ]]; then
    if [[ "$for_doctor" != "true" ]]; then
      local missing_hash
      while IFS= read -r missing_hash; do
        warn "An administrator-trusted certificate (SHA-1 $missing_hash) is not in the System keychain, so it is not in the CA bundle."
      done < "$work/missing"
    fi
  fi
  if ! grep -q '^-----BEGIN CERTIFICATE-----$' "$admin_pem"; then
    [[ "$for_doctor" == "true" ]] || warn "None of the administrator-trusted certificates is in the System keychain; the existing CA bundle was kept."
    return 1
  fi

  if ! cat "$system_pem" "$admin_pem" > "$staged_bundle"; then
    [[ "$for_doctor" == "true" ]] || warn "Could not stage the command-line CA bundle; the existing bundle was kept."
    return 1
  fi

  local curl_bundle
  curl_bundle="$(printf '%s' "$bundle" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  if ! printf 'cacert = "%s"\n' "$curl_bundle" > "$staged_curlrc"; then
    [[ "$for_doctor" == "true" ]] || warn "Could not stage Homebrew's curl configuration; the existing CA bundle was kept."
    return 1
  fi

  return 0
}

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

  local state_dir bundle curlrc work staged_bundle staged_curlrc
  state_dir="${TEEUP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/teeup}"
  bundle="$(ca_bundle_path)"
  curlrc="$(ca_bundle_curlrc_path)"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log "[DRY-RUN] Would rebuild the command-line CA bundle at $bundle"
    return 0
  fi
  mkdir -p "$state_dir" || return 1
  work="$(mktemp -d "$state_dir/.ca-bundle.XXXXXX")" || return 1
  staged_bundle="$work/ca-bundle.pem"
  staged_curlrc="$work/ca-bundle.curlrc"

  local stage_rc=0
  _ca_bundle_stage "$work" "false" || stage_rc=$?
  if [[ $stage_rc -eq 2 ]]; then
    rm -rf "$work"
    ca_bundle_remove
    return 0
  elif [[ $stage_rc -ne 0 ]]; then
    rm -rf "$work"
    return 1
  fi

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

  local checked
  checked="$(ca_bundle_checked_path)"
  if ! { : > "$checked"; } 2>/dev/null; then
    rm -f "$checked" 2>/dev/null || true
    warn "Could not update $checked; teeup doctor will judge the bundle by its own date."
  fi
  ca_bundle_apply_env
}

ca_bundle_is_current() {
  local bundle curlrc roots keychain checked
  bundle="$(ca_bundle_path)"
  curlrc="$(ca_bundle_curlrc_path)"
  roots="${TEEUP_SYSTEM_ROOT_KEYCHAIN:-/System/Library/Keychains/SystemRootCertificates.keychain}"
  keychain="${TEEUP_SYSTEM_KEYCHAIN:-/Library/Keychains/System.keychain}"

  if [[ ! -s "$bundle" || ! -s "$curlrc" ]]; then
    echo "missing"
    return 1
  fi
  if ! grep -qF "$bundle" "$curlrc"; then
    echo "curlrc_stale"
    return 1
  fi

  checked="$(ca_bundle_checked_path)"
  [[ -e "$checked" ]] || checked="$bundle"

  local needs_check=false
  if [[ -e "$roots" && "$roots" -nt "$checked" ]]; then
    needs_check=true
  fi
  if [[ -e "$keychain" && "$keychain" -nt "$checked" ]]; then
    needs_check=true
  fi

  if [[ "$needs_check" == "false" ]]; then
    echo "current"
    return 0
  fi

  local state_dir work stage_rc=0
  state_dir="${TEEUP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/teeup}"
  mkdir -p "$state_dir" >/dev/null 2>&1 || { echo "could_not_check"; return 1; }
  work="$(mktemp -d "$state_dir/.ca-bundle.XXXXXX")" || { echo "could_not_check"; return 1; }

  _ca_bundle_stage "$work" "true" || stage_rc=$?

  if [[ $stage_rc -eq 2 ]]; then
    rm -rf "$work"
    echo "changed"
    return 1
  elif [[ $stage_rc -ne 0 ]]; then
    rm -rf "$work"
    echo "could_not_check"
    return 1
  fi

  if cmp -s "$work/ca-bundle.pem" "$bundle"; then
    local marker_path
    marker_path="$(ca_bundle_checked_path)"
    if [[ -w "$marker_path" || ( ! -e "$marker_path" && -w "$(dirname "$marker_path")" ) ]]; then
      : > "$marker_path" 2>/dev/null || true
    fi
    rm -rf "$work"
    echo "current"
    return 0
  else
    rm -rf "$work"
    echo "changed"
    return 1
  fi
}

ca_bundle_apply_env
