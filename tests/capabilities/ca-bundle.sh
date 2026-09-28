#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

TRUSTED_HASH="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
UNTRUSTED_HASH="BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"

setup() {
  setup_test_env
  mock_macos_base
  export MOCK_SECURITY_MODE=admin_roots
  export TEEUP_PLUTIL="$MOCK_BIN/plutil"

  mock_command_script security <<'EOF_SECURITY'
case "$1" in
  dump-trust-settings)
    case "$MOCK_SECURITY_MODE" in
      no_roots) echo "Number of trusted certs = 0" ;;
      dump_failure) echo "could not read trust settings" >&2; exit 1 ;;
      *) echo "Number of trusted certs = 1"; echo "Cert 0: Company Root" ;;
    esac
    ;;
  trust-settings-export)
    case "$MOCK_SECURITY_MODE" in
      export_failure) exit 1 ;;
      empty_export) : > "$3" ;;
      empty_trust_list)
        printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
          '<plist version="1.0"><dict><key>trustList</key><dict></dict></dict></plist>' > "$3"
        ;;
      *)
        printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
          '<plist version="1.0"><dict><key>trustList</key><dict>' \
          '<key>AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA</key><dict><key>trustSettings</key><array><dict></dict></array></dict>' \
          '</dict></dict></plist>' > "$3"
        ;;
    esac
    ;;
  find-certificate)
    case "$*" in
      *SystemRootCertificates.keychain*)
        case "$MOCK_SECURITY_MODE" in roots_failure) exit 1 ;; esac
        printf '%s\n' '-----BEGIN CERTIFICATE-----' 'SYSTEM_ROOT' '-----END CERTIFICATE-----'
        ;;
      *System.keychain*)
        case "$MOCK_SECURITY_MODE" in admin_find_failure) exit 1 ;; esac
        printf '%s\n' \
          'SHA-1 hash: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' \
          '-----BEGIN CERTIFICATE-----' 'TRUSTED_ADMIN_ROOT' '-----END CERTIFICATE-----' \
          'SHA-1 hash: BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB' \
          '-----BEGIN CERTIFICATE-----' 'UNTRUSTED_SYSTEM_CERT' '-----END CERTIFICATE-----'
        ;;
    esac
    ;;
  *) exit 2 ;;
esac
EOF_SECURITY

  mock_command_script plutil <<'EOF_PLUTIL'
case "$*" in
  *-convert*xml1*-o*) cp "$5" "$4" ;;
  *) exit 2 ;;
esac
EOF_PLUTIL

  # shellcheck source=lib/all.sh
  source "$TEEUP_PATH/lib/all.sh"
}

file_mtime() {
  if stat -f '%m' "$1" >/dev/null 2>&1; then
    stat -f '%m' "$1"
  else
    stat -c '%Y' "$1"
  fi
}

test_no_admin_roots_leave_no_bundle_or_environment() {
  setup
  export MOCK_SECURITY_MODE=no_roots
  mkdir -p "$TEEUP_STATE_DIR"
  printf 'old bundle\n' > "$TEEUP_STATE_DIR/ca-bundle.pem"
  printf 'old curlrc\n' > "$TEEUP_STATE_DIR/ca-bundle.curlrc"
  SSL_CERT_FILE="$TEEUP_STATE_DIR/ca-bundle.pem"
  HOMEBREW_CURLRC="$TEEUP_STATE_DIR/ca-bundle.curlrc"
  export SSL_CERT_FILE HOMEBREW_CURLRC

  ca_bundle_rebuild || return 1

  [[ ! -e "$TEEUP_STATE_DIR/ca-bundle.pem" ]] || { echo "bundle kept without admin roots"; return 1; }
  [[ ! -e "$TEEUP_STATE_DIR/ca-bundle.curlrc" ]] || { echo "curlrc kept without admin roots"; return 1; }
  [[ -z "${SSL_CERT_FILE+x}" ]] || { echo "teeup's SSL_CERT_FILE stayed exported"; return 1; }
  [[ -z "${HOMEBREW_CURLRC+x}" ]] || { echo "teeup's HOMEBREW_CURLRC stayed exported"; return 1; }
  [[ -z "${GIT_SSL_CAINFO+x}${CURL_CA_BUNDLE+x}${REQUESTS_CA_BUNDLE+x}${NODE_EXTRA_CA_CERTS+x}" ]] || {
    echo "certificate environment was added without admin roots"
    return 1
  }
  cleanup_test_env
}

test_bundle_contains_public_and_trusted_admin_roots_only() {
  setup

  ca_bundle_rebuild || return 1

  local bundle="$TEEUP_STATE_DIR/ca-bundle.pem" curlrc="$TEEUP_STATE_DIR/ca-bundle.curlrc"
  assert_file_exists "$bundle" || return 1
  assert_file_exists "$curlrc" || return 1
  assert_contains "$(cat "$bundle")" "SYSTEM_ROOT" || return 1
  assert_contains "$(cat "$bundle")" "TRUSTED_ADMIN_ROOT" || return 1
  assert_not_contains "$(cat "$bundle")" "UNTRUSTED_SYSTEM_CERT" || return 1
  assert_contains "$(cat "$curlrc")" "$bundle" || return 1
  assert_equals "$bundle" "$SSL_CERT_FILE" || return 1
  assert_equals "$bundle" "$GIT_SSL_CAINFO" || return 1
  assert_equals "$bundle" "$CURL_CA_BUNDLE" || return 1
  assert_equals "$bundle" "$REQUESTS_CA_BUNDLE" || return 1
  assert_equals "$bundle" "$NODE_EXTRA_CA_CERTS" || return 1
  assert_equals "$curlrc" "$HOMEBREW_CURLRC" || return 1
  cleanup_test_env
}

test_unchanged_content_keeps_bundle_and_curlrc_mtimes() {
  setup
  ca_bundle_rebuild || return 1
  local bundle="$TEEUP_STATE_DIR/ca-bundle.pem" curlrc="$TEEUP_STATE_DIR/ca-bundle.curlrc"
  local bundle_before curlrc_before
  bundle_before="$(file_mtime "$bundle")"
  curlrc_before="$(file_mtime "$curlrc")"
  sleep 1

  ca_bundle_rebuild || return 1

  assert_equals "$bundle_before" "$(file_mtime "$bundle")" "unchanged bundle was replaced" || return 1
  assert_equals "$curlrc_before" "$(file_mtime "$curlrc")" "unchanged curlrc was replaced" || return 1
  cleanup_test_env
}

test_failed_or_empty_export_keeps_a_good_bundle() {
  setup
  ca_bundle_rebuild || return 1
  local bundle="$TEEUP_STATE_DIR/ca-bundle.pem" before rc=0
  before="$(cat "$bundle")"

  export MOCK_SECURITY_MODE=export_failure
  ca_bundle_rebuild >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "a failed export must be reported" || return 1
  assert_equals "$before" "$(cat "$bundle")" "failed export replaced the bundle" || return 1

  export MOCK_SECURITY_MODE=empty_export
  rc=0
  ca_bundle_rebuild >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "an empty export must be reported" || return 1
  assert_equals "$before" "$(cat "$bundle")" "empty export replaced the bundle" || return 1

  export MOCK_SECURITY_MODE=empty_trust_list
  rc=0
  ca_bundle_rebuild >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "an empty trust list must be reported" || return 1
  assert_equals "$before" "$(cat "$bundle")" "empty trust list replaced the bundle" || return 1
  cleanup_test_env
}

test_environment_keeps_user_set_values_including_empty() {
  setup
  SSL_CERT_FILE="/private/custom-ca.pem"
  CURL_CA_BUNDLE=""
  export SSL_CERT_FILE CURL_CA_BUNDLE

  ca_bundle_rebuild || return 1

  assert_equals "/private/custom-ca.pem" "$SSL_CERT_FILE" || return 1
  [[ -n "${CURL_CA_BUNDLE+x}" ]] || { echo "an explicitly empty variable became unset"; return 1; }
  assert_equals "" "$CURL_CA_BUNDLE" "an explicitly empty variable was overwritten" || return 1
  assert_equals "$TEEUP_STATE_DIR/ca-bundle.pem" "$GIT_SSL_CAINFO" || return 1
  cleanup_test_env
}

echo "capabilities/ca-bundle"
run_test "no admin roots leave no bundle or environment" test_no_admin_roots_leave_no_bundle_or_environment
run_test "bundle includes public and trusted admin roots only" test_bundle_contains_public_and_trusted_admin_roots_only
run_test "unchanged content keeps mtimes" test_unchanged_content_keeps_bundle_and_curlrc_mtimes
run_test "failed or empty export keeps a good bundle" test_failed_or_empty_export_keeps_a_good_bundle
run_test "environment keeps user-set values including empty" test_environment_keeps_user_set_values_including_empty
print_summary
