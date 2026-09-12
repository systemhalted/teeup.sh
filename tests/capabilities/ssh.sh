#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command ssh-add 0 ""
  # A keygen that actually leaves the two files behind, so the permission and
  # idempotency steps have something to act on.
  mock_command_script ssh-keygen <<'EOF2'
out=""
while [ $# -gt 0 ]; do
  [ "$1" = "-f" ] && { shift; out="$1"; }
  shift
done
[ -n "$out" ] || exit 1
mkdir -p "$(dirname "$out")"
printf 'PRIVATE\n' > "$out"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAKEKEY comment\n' > "$out.pub"
EOF2
  TEEUP="$TEEUP_PATH/bin/teeup"
}

seed_answers() {
  mkdir -p "$TEST_HOME/.config/teeup"
  {
    printf 'TEEUP_NAME="Ada Lovelace"\n'
    printf 'TEEUP_EMAIL="ada@example.com"\n'
    printf 'TEEUP_WORK_EMAIL="%s"\n' "${1:-}"
  } > "$TEST_HOME/.config/teeup/answers"
}

test_configure_generates_one_key_without_a_work_email() {
  setup
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  assert_file_exists "$TEST_HOME/.ssh/id_ed25519_personal" || return 1
  assert_file_exists "$TEST_HOME/.ssh/id_ed25519_personal.pub" || return 1
  [[ ! -e "$TEST_HOME/.ssh/id_ed25519_work" ]] || { echo "work key without a work email"; return 1; }
  cleanup_test_env
}

test_configure_generates_both_keys_with_a_work_email() {
  setup
  seed_answers "ada@corp.example"
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  assert_file_exists "$TEST_HOME/.ssh/id_ed25519_work" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "ssh-keygen -t ed25519 -C ada@corp.example" || return 1
  cleanup_test_env
}

test_configure_adds_the_keys_to_the_keychain() {
  setup
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  assert_contains "$(cat "$MOCK_LOG")" "ssh-add --apple-use-keychain $TEST_HOME/.ssh/id_ed25519_personal" || return 1
  cleanup_test_env
}

test_configure_uses_apple_use_keychain_on_macos_12_and_newer() {
  setup
  mock_command sw_vers 0 "12.0"
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  assert_contains "$(cat "$MOCK_LOG")" "ssh-add --apple-use-keychain $TEST_HOME/.ssh/id_ed25519_personal" || return 1
  cleanup_test_env
}

test_configure_uses_dash_k_before_macos_12() {
  setup
  mock_command sw_vers 0 "11.6"
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  assert_contains "$(cat "$MOCK_LOG")" "ssh-add -K $TEST_HOME/.ssh/id_ed25519_personal" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "--apple-use-keychain" || return 1
  cleanup_test_env
}

test_configure_installs_the_ssh_config_with_both_hosts() {
  setup
  seed_answers "ada@corp.example"
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  local body
  body="$(cat "$TEST_HOME/.ssh/config")"
  assert_contains "$body" "Host github.com-work" || return 1
  assert_contains "$body" "IdentityFile ~/.ssh/id_ed25519_work" || return 1
  assert_contains "$body" "UseKeychain yes" || return 1
  cleanup_test_env
}

# GNU stat first, BSD stat second. Trying BSD first would be wrong: GNU's
# `stat -f` means "filesystem status", so it prints something and fails, and
# the fallback's output would be appended to that garbage.
file_mode() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then
    stat -c '%a' "$1"
  else
    stat -f '%Lp' "$1"
  fi
}

test_permissions_are_tightened() {
  setup
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  assert_equals "700" "$(file_mode "$TEST_HOME/.ssh")" || return 1
  assert_equals "600" "$(file_mode "$TEST_HOME/.ssh/id_ed25519_personal")" || return 1
  assert_equals "600" "$(file_mode "$TEST_HOME/.ssh/config")" || return 1
  cleanup_test_env
}

test_existing_key_is_not_regenerated() {
  setup
  seed_answers ""
  mkdir -p "$TEST_HOME/.ssh"
  printf 'MINE\n' > "$TEST_HOME/.ssh/id_ed25519_personal"
  printf 'ssh-ed25519 MINE comment\n' > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  assert_contains "$out" "Already present: $TEST_HOME/.ssh/id_ed25519_personal" || return 1
  assert_equals "MINE" "$(cat "$TEST_HOME/.ssh/id_ed25519_personal")" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  seed_answers ""
  local out
  out="$(DRY_RUN=true "$TEEUP" configure ssh 2>&1)"
  assert_contains "$out" "Would execute: ssh-keygen -t ed25519 -C ada@example.com" || return 1
  [[ ! -e "$TEST_HOME/.ssh/id_ed25519_personal" ]] || { echo "key written in dry run"; return 1; }
  cleanup_test_env
}

test_configure_twice_changes_nothing() {
  setup
  seed_answers "ada@corp.example"
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  local marker="$TEST_HOME/.idempotency-marker"
  : > "$marker"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  assert_contains "$out" "Already present: $TEST_HOME/.ssh/id_ed25519_personal" || return 1
  assert_contains "$out" "Already installed: $TEST_HOME/.ssh/config" || return 1
  assert_not_contains "$out" "Generating the" || return 1
  # chmod_once keeps the second run silent, so nothing under $HOME may change.
  local changed
  changed="$(find "$TEST_HOME" -newer "$marker" -type f \
    ! -name 'mock.log' ! -name '.idempotency-marker' 2>/dev/null)"
  assert_equals "" "$changed" "second configure must write nothing" || return 1
  cleanup_test_env
}

echo "capabilities/ssh"
run_test "configure generates one key without a work email" test_configure_generates_one_key_without_a_work_email
run_test "configure generates both keys with a work email" test_configure_generates_both_keys_with_a_work_email
run_test "configure adds the keys to the keychain" test_configure_adds_the_keys_to_the_keychain
run_test "configure uses --apple-use-keychain on macOS 12 and newer" test_configure_uses_apple_use_keychain_on_macos_12_and_newer
run_test "configure uses -K before macOS 12" test_configure_uses_dash_k_before_macos_12
run_test "configure installs the ssh config with both hosts" test_configure_installs_the_ssh_config_with_both_hosts
run_test "permissions are tightened" test_permissions_are_tightened
run_test "existing key is not regenerated" test_existing_key_is_not_regenerated
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "configure twice changes nothing" test_configure_twice_changes_nothing
print_summary
