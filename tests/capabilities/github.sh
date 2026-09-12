#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  # A gh that is signed out until `auth login` runs, and whose key list and
  # token scopes live in files the test can seed. `gh-session` holds the
  # scopes string that `auth status` echoes back on its "Token scopes:" line
  # for github.com, so a test can simulate a pre-existing login that is
  # missing a scope. A second host's session (if seeded) lives in
  # `gh-session-<host>`; a bare `auth status` (no -h) prints every seeded
  # host, github.com first, the way the real multi-host CLI does, so a test
  # can prove that only `-h github.com`'s own scopes decide teeup's refresh.
  mock_command_script gh <<'EOF2'
host=""
prev=""
for a in "$@"; do
  [ "$prev" = "-h" ] && host="$a"
  prev="$a"
done
case "$1 ${2:-}" in
  "auth status")
    if [ -n "$host" ]; then
      session_file="$HOME/gh-session"
      [ "$host" = "github.com" ] || session_file="$HOME/gh-session-$host"
      [ -f "$session_file" ] || exit 1
      echo "$host"
      echo "  Logged in to $host account testuser (keyring)"
      echo "  Token scopes: $(cat "$session_file")"
    else
      found=1
      if [ -f "$HOME/gh-session" ]; then
        found=0
        echo "github.com"
        echo "  Logged in to github.com account testuser (keyring)"
        echo "  Token scopes: $(cat "$HOME/gh-session")"
      fi
      for f in "$HOME"/gh-session-*; do
        [ -e "$f" ] || continue
        found=0
        other_host="${f#"$HOME"/gh-session-}"
        echo "$other_host"
        echo "  Logged in to $other_host account testuser (keyring)"
        echo "  Token scopes: $(cat "$f")"
      done
      exit "$found"
    fi
    ;;
  "auth login")
    printf "'admin:public_key', 'admin:ssh_signing_key'" > "$HOME/gh-session"
    ;;
  "auth refresh")
    session_file="$HOME/gh-session"
    [ -z "$host" ] || [ "$host" = "github.com" ] || session_file="$HOME/gh-session-$host"
    printf "'admin:public_key', 'admin:ssh_signing_key'" > "$session_file"
    ;;
  "ssh-key list") cat "$HOME/gh-keys" 2>/dev/null || true ;;
  # An upload lands in the same list a later run reads back, so running
  # configure twice can be tested the way GitHub would actually behave. The
  # real `gh ssh-key list` prints a type column, so the mock records the
  # --type it was given, letting the per-type dedupe be tested.
  "ssh-key add")
    pubfile="$3"
    shift 3
    ssh_key_type=""
    while [ $# -gt 0 ]; do
      case "$1" in --type) ssh_key_type="$2" ;; esac
      shift
    done
    ssh_key_body="$(awk '{print $2}' < "$pubfile")"
    printf 'title  ssh-ed25519 %s  id  2026-09-11  %s\n' "$ssh_key_body" "$ssh_key_type" >> "$HOME/gh-keys"
    ;;
  *) : ;;
esac
exit 0
EOF2
  TEEUP="$TEEUP_PATH/bin/teeup"
}

seed_keys() {
  mkdir -p "$TEST_HOME/.ssh"
  printf 'ssh-ed25519 AAAAPERSONALKEY ada@example.com\n' > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  printf 'PRIVATE\n' > "$TEST_HOME/.ssh/id_ed25519_personal"
}

test_install_gets_gh() {
  setup
  export TEEUP_TEST_MISSING="gh"
  local out
  out="$(DRY_RUN=true "$TEEUP" install github 2>&1)"
  assert_contains "$out" "Would execute: brew install gh" || return 1
  cleanup_test_env
}

test_configure_logs_in_with_the_two_scopes() {
  setup
  seed_keys
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "auth login --web --git-protocol ssh --scopes admin:public_key,admin:ssh_signing_key" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "config set git_protocol ssh --host github.com" || return 1
  cleanup_test_env
}

test_configure_uploads_authentication_and_signing_keys() {
  setup
  seed_keys
  DRY_RUN=false "$TEEUP" configure github >/dev/null 2>&1
  local calls
  calls="$(cat "$MOCK_LOG")"
  assert_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub --type authentication --title testmac personal" || return 1
  assert_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub --type signing --title testmac personal (signing)" || return 1
  cleanup_test_env
}

test_configure_skips_a_key_github_already_has() {
  setup
  seed_keys
  printf 'laptop  ssh-ed25519 AAAAPERSONALKEY  12345  2026-09-11  authentication\n' > "$TEST_HOME/gh-keys"
  printf 'laptop (signing)  ssh-ed25519 AAAAPERSONALKEY  67890  2026-09-11  signing\n' >> "$TEST_HOME/gh-keys"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  assert_contains "$out" "Already uploaded" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "ssh-key add" || return 1
  cleanup_test_env
}

test_configure_refreshes_scopes_when_the_signing_scope_is_missing() {
  setup
  seed_keys
  printf "'admin:public_key'" > "$TEST_HOME/gh-session"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  assert_contains "$out" "Already signed in to GitHub." || return 1
  assert_contains "$(cat "$MOCK_LOG")" "auth refresh -h github.com -s admin:public_key,admin:ssh_signing_key" || return 1
  cleanup_test_env
}

test_configure_lets_github_com_scopes_decide_over_another_host() {
  setup
  seed_keys
  # github.com itself is missing the signing scope, but an enterprise host is
  # signed in with both. An unscoped `gh auth status` would print both hosts'
  # "Token scopes:" lines, and a plain substring match on that combined text
  # would find admin:ssh_signing_key from the *other* host and skip the
  # refresh github.com actually needs. `-h github.com` must not be fooled.
  printf "'admin:public_key'" > "$TEST_HOME/gh-session"
  printf "'admin:public_key', 'admin:ssh_signing_key'" > "$TEST_HOME/gh-session-github.enterprise.example.com"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  assert_contains "$out" "Already signed in to GitHub." || return 1
  assert_contains "$(cat "$MOCK_LOG")" "auth refresh -h github.com -s admin:public_key,admin:ssh_signing_key" || return 1
  cleanup_test_env
}

test_configure_retries_the_signing_upload_when_only_authentication_is_present() {
  setup
  seed_keys
  printf "'admin:public_key', 'admin:ssh_signing_key'" > "$TEST_HOME/gh-session"
  printf 'laptop  ssh-ed25519 AAAAPERSONALKEY  12345  2026-09-11  authentication\n' > "$TEST_HOME/gh-keys"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  local calls
  calls="$(cat "$MOCK_LOG")"
  assert_not_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub --type authentication" || return 1
  assert_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub --type signing --title testmac personal (signing)" || return 1
  cleanup_test_env
}

test_configure_skips_the_login_when_already_signed_in() {
  setup
  seed_keys
  printf "'admin:public_key', 'admin:ssh_signing_key'" > "$TEST_HOME/gh-session"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  assert_contains "$out" "Already signed in to GitHub." || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "auth login" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "auth refresh" || return 1
  cleanup_test_env
}

test_configure_warns_when_the_key_is_missing() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  assert_contains "$out" "teeup configure ssh" || return 1
  cleanup_test_env
}

test_configure_dry_run_uploads_nothing() {
  setup
  seed_keys
  local out
  out="$(DRY_RUN=true "$TEEUP" configure github 2>&1)"
  assert_contains "$out" "Would execute: gh ssh-key add" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "ssh-key add" || return 1
  cleanup_test_env
}

test_configure_twice_uploads_nothing_new() {
  setup
  seed_keys
  DRY_RUN=false "$TEEUP" configure github >/dev/null 2>&1
  local marker="$TEST_HOME/.idempotency-marker"
  : > "$marker"
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  assert_contains "$out" "Already signed in to GitHub." || return 1
  assert_contains "$out" "Already uploaded" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "ssh-key add" || return 1
  # gh config set is the only write the second run makes, and it goes to gh's
  # own state, not to a file teeup owns.
  local changed
  changed="$(find "$TEST_HOME" -newer "$marker" -type f \
    ! -name 'mock.log' ! -name '.idempotency-marker' 2>/dev/null)"
  assert_equals "" "$changed" "second configure must write nothing" || return 1
  cleanup_test_env
}

echo "capabilities/github"
run_test "install gets gh" test_install_gets_gh
run_test "configure logs in with the two scopes" test_configure_logs_in_with_the_two_scopes
run_test "configure uploads authentication and signing keys" test_configure_uploads_authentication_and_signing_keys
run_test "configure skips a key GitHub already has" test_configure_skips_a_key_github_already_has
run_test "configure refreshes scopes when the signing scope is missing" test_configure_refreshes_scopes_when_the_signing_scope_is_missing
run_test "configure lets github.com scopes decide over another host" test_configure_lets_github_com_scopes_decide_over_another_host
run_test "configure retries the signing upload when only authentication is present" test_configure_retries_the_signing_upload_when_only_authentication_is_present
run_test "configure skips the login when already signed in" test_configure_skips_the_login_when_already_signed_in
run_test "configure warns when the key is missing" test_configure_warns_when_the_key_is_missing
run_test "configure dry run uploads nothing" test_configure_dry_run_uploads_nothing
run_test "configure twice uploads nothing new" test_configure_twice_uploads_nothing_new
print_summary
