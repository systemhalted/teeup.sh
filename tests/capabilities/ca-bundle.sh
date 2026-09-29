#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  export MOCK_SECURITY_MODE=admin_roots
  export TEEUP_PLUTIL="$MOCK_BIN/plutil"
  export TEEUP_SYSTEM_ROOT_KEYCHAIN="$TEST_HOME/SystemRootCertificates.keychain"
  export TEEUP_SYSTEM_KEYCHAIN="$TEST_HOME/System.keychain"
  touch "$TEEUP_SYSTEM_ROOT_KEYCHAIN" "$TEEUP_SYSTEM_KEYCHAIN"

  mock_command_script security <<'EOF_SECURITY'
case "$1" in
  dump-trust-settings)
    case "$MOCK_SECURITY_MODE" in
      no_roots) echo "Number of trusted certs = 0" ;;
      # What macOS actually does with no admin trust settings: says so on
      # stderr and exits 1.
      no_trust_settings) echo "SecTrustSettingsCopyCertificates: No Trust Settings were found." >&2; exit 1 ;;
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
      mixed_trust)
        # AAAA: an entry with no result (trust root). CCCC: Deny (3).
        # DDDD: trusted but not in System.keychain. EEEE: Unspecified (4)
        # only. FFFF: TrustAsRoot (2). Spread over lines as plutil writes it.
        cat > "$3" <<'EOF_PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>trustList</key>
	<dict>
		<key>AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA</key>
		<dict>
			<key>issuerName</key>
			<data>AAAA</data>
			<key>trustSettings</key>
			<array>
				<dict/>
			</array>
		</dict>
		<key>CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC</key>
		<dict>
			<key>trustSettings</key>
			<array>
				<dict>
					<key>kSecTrustSettingsPolicyString</key>
					<string>example.com</string>
					<key>kSecTrustSettingsResult</key>
					<integer>1</integer>
				</dict>
				<dict>
					<key>kSecTrustSettingsResult</key>
					<integer>3</integer>
				</dict>
			</array>
		</dict>
		<key>DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD</key>
		<dict>
			<key>trustSettings</key>
			<array/>
		</dict>
		<key>EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE</key>
		<dict>
			<key>trustSettings</key>
			<array>
				<dict>
					<key>kSecTrustSettingsResult</key>
					<integer>4</integer>
				</dict>
			</array>
		</dict>
		<key>FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF</key>
		<dict>
			<key>trustSettings</key>
			<array>
				<dict>
					<key>kSecTrustSettingsResult</key>
					<integer>2</integer>
				</dict>
			</array>
		</dict>
	</dict>
</dict>
</plist>
EOF_PLIST
        ;;
      all_denied)
        printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
          '<plist version="1.0"><dict><key>trustList</key><dict>' \
          '<key>CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC</key><dict><key>trustSettings</key><array><dict><key>kSecTrustSettingsResult</key><integer>3</integer></dict></array></dict>' \
          '</dict></dict></plist>' > "$3"
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
          '-----BEGIN CERTIFICATE-----' 'UNTRUSTED_SYSTEM_CERT' '-----END CERTIFICATE-----' \
          'SHA-1 hash: CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC' \
          '-----BEGIN CERTIFICATE-----' 'DENIED_CERT' '-----END CERTIFICATE-----' \
          'SHA-1 hash: EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE' \
          '-----BEGIN CERTIFICATE-----' 'UNSPECIFIED_CERT' '-----END CERTIFICATE-----' \
          'SHA-1 hash: FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF' \
          '-----BEGIN CERTIFICATE-----' 'TRUST_AS_ROOT_CERT' '-----END CERTIFICATE-----'
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

test_doctor_reports_not_needed_without_admin_roots() {
  setup
  export MOCK_SECURITY_MODE=no_roots
  local rc=0 out
  out="$(cap_run ca-bundle doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "not needed" || return 1
  cleanup_test_env
}

test_no_trust_settings_exit_means_no_admin_roots() {
  setup
  export MOCK_SECURITY_MODE=no_trust_settings
  local rc=0 out
  ca_bundle_rebuild || { echo "rebuild failed on a Mac with no admin trust settings"; return 1; }
  [[ ! -e "$TEEUP_STATE_DIR/ca-bundle.pem" ]] || { echo "a bundle was built"; return 1; }
  out="$(cap_run ca-bundle doctor 2>&1)" || rc=$?
  assert_success "$rc" "$out" || return 1
  assert_contains "$out" "not needed" || return 1
  cleanup_test_env
}

test_configure_warns_but_does_not_fail_bootstrap() {
  setup
  # ca-bundle is core: a failing configure stops ./bootstrap. A Mac whose
  # trust settings cannot be read still needs the rest of teeup.
  export MOCK_SECURITY_MODE=dump_failure
  local rc=0 out
  out="$(cap_run ca-bundle configure 2>&1)" || rc=$?
  assert_success "$rc" "$out" || return 1
  assert_contains "$out" "teeup doctor ca-bundle" || return 1
  cleanup_test_env
}

test_doctor_reports_present_and_current() {
  setup
  ca_bundle_rebuild || return 1
  local rc=0 out
  out="$(cap_run ca-bundle doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "present and current" || return 1
  cleanup_test_env
}

test_doctor_reports_missing_bundle_with_fix() {
  setup
  local rc=0 out report="$TEST_HOME/doctor-report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(cap_run ca-bundle doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "missing" || return 1
  assert_contains "$(cat "$report")" "teeup configure ca-bundle" || return 1
  cleanup_test_env
}

test_doctor_reports_bundle_older_than_system_keychain() {
  setup
  ca_bundle_rebuild || return 1
  sleep 1
  touch "$TEEUP_SYSTEM_KEYCHAIN"
  local rc=0 out report="$TEST_HOME/doctor-report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(cap_run ca-bundle doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "older" || return 1
  assert_contains "$(cat "$report")" "teeup configure ca-bundle" || return 1
  cleanup_test_env
}

# Seen on a real Mac, 2026-09-28: the keychain's date moved, the rebuild found
# the same certificates and rightly left the bundle alone, and doctor kept
# calling it stale because it compared the bundle's own date.
test_doctor_is_satisfied_after_a_rebuild_that_changed_nothing() {
  setup
  ca_bundle_rebuild || return 1
  sleep 1
  touch "$TEEUP_SYSTEM_KEYCHAIN"
  ca_bundle_rebuild || return 1
  local rc=0 out
  out="$(cap_run ca-bundle doctor 2>&1)" || rc=$?
  assert_success "$rc" "$out" || return 1
  cleanup_test_env
}

test_remove_deletes_bundle_and_curlrc() {
  setup
  ca_bundle_rebuild || return 1

  cap_run ca-bundle remove >/dev/null

  [[ ! -e "$TEEUP_STATE_DIR/ca-bundle.pem" ]] || { echo "remove kept the bundle"; return 1; }
  [[ ! -e "$TEEUP_STATE_DIR/ca-bundle.curlrc" ]] || { echo "remove kept the curlrc"; return 1; }
  cleanup_test_env
}

echo "capabilities/ca-bundle"
test_bundle_follows_each_certificates_trust_result() {
  setup
  export MOCK_SECURITY_MODE=mixed_trust
  local out bundle="$TEEUP_STATE_DIR/ca-bundle.pem"
  out="$(ca_bundle_rebuild 2>&1)" || { echo "rebuild failed: $out"; return 1; }
  assert_contains "$(cat "$bundle")" "TRUSTED_ADMIN_ROOT" || return 1
  assert_contains "$(cat "$bundle")" "TRUST_AS_ROOT_CERT" || return 1
  assert_not_contains "$(cat "$bundle")" "DENIED_CERT" || return 1
  assert_not_contains "$(cat "$bundle")" "UNSPECIFIED_CERT" || return 1
  assert_not_contains "$(cat "$bundle")" "UNTRUSTED_SYSTEM_CERT" || return 1
  # A trusted certificate that is not in System.keychain is skipped, not fatal.
  assert_contains "$out" "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD" || return 1
  cleanup_test_env
}

test_only_denied_admin_certificates_leave_no_bundle() {
  setup
  export MOCK_SECURITY_MODE=all_denied
  mkdir -p "$TEEUP_STATE_DIR"
  printf 'old bundle\n' > "$TEEUP_STATE_DIR/ca-bundle.pem"
  ca_bundle_rebuild || return 1
  [[ ! -e "$TEEUP_STATE_DIR/ca-bundle.pem" ]] || { echo "a bundle was kept with no trusted admin roots"; return 1; }
  cleanup_test_env
}

run_test "no admin roots leave no bundle or environment" test_no_admin_roots_leave_no_bundle_or_environment
run_test "bundle includes public and trusted admin roots only" test_bundle_contains_public_and_trusted_admin_roots_only
run_test "unchanged content keeps mtimes" test_unchanged_content_keeps_bundle_and_curlrc_mtimes
run_test "doctor is satisfied after a rebuild that changed nothing" test_doctor_is_satisfied_after_a_rebuild_that_changed_nothing
run_test "failed or empty export keeps a good bundle" test_failed_or_empty_export_keeps_a_good_bundle
run_test "environment keeps user-set values including empty" test_environment_keeps_user_set_values_including_empty
run_test "doctor reports not needed without admin roots" test_doctor_reports_not_needed_without_admin_roots
run_test "no-trust-settings exit means no admin roots" test_no_trust_settings_exit_means_no_admin_roots
run_test "configure warns but does not fail bootstrap" test_configure_warns_but_does_not_fail_bootstrap
run_test "doctor reports present and current" test_doctor_reports_present_and_current
run_test "doctor reports missing bundle with fix" test_doctor_reports_missing_bundle_with_fix
run_test "doctor reports an older bundle" test_doctor_reports_bundle_older_than_system_keychain
run_test "remove deletes bundle and curlrc" test_remove_deletes_bundle_and_curlrc
run_test "bundle follows each certificate's trust result" test_bundle_follows_each_certificates_trust_result
run_test "only denied admin certificates leave no bundle" test_only_denied_admin_certificates_leave_no_bundle
print_summary
