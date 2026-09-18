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
  # for the *active* github.com account, so a test can simulate a pre-existing
  # login that is missing a scope. `gh-inactive-scopes`, if seeded, is a
  # second account on github.com: the real `gh auth status -h github.com`
  # reports every account known on the host and only `--active` narrows it to
  # the one gh will actually use, so a test can prove which account decides.
  # A second host's session (if seeded) lives in `gh-session-<host>`; a bare
  # `auth status` (no -h) prints every seeded host, github.com first, the way
  # the real multi-host CLI does, so a test can prove that only
  # `-h github.com`'s own scopes decide teeup's refresh.
  mock_command_script gh <<'EOF2'
echo "GH_HOST=$GH_HOST" >> "$MOCK_LOG"
host=""
prev=""
active=0
for a in "$@"; do
  # auth status/refresh spell it -h; auth login spells the same thing
  # --hostname. Both must be captured so a login targeting a second host
  # (a GitHub Enterprise instance, or a second github.com account under a
  # different alias) records its session under that host, not github.com's.
  case "$prev" in -h|--hostname) host="$a" ;; esac
  case "$a" in -a|--active) active=1 ;; esac
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
      echo "  - Active account: true"
      echo "  Token scopes: $(cat "$session_file")"
      if [ "$active" = "0" ] && [ "$host" = "github.com" ] && [ -f "$HOME/gh-inactive-scopes" ]; then
        echo "  Logged in to $host account otheruser (keyring)"
        echo "  - Active account: false"
        echo "  Token scopes: $(cat "$HOME/gh-inactive-scopes")"
      fi
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
    session_file="$HOME/gh-session"
    [ -z "$host" ] || [ "$host" = "github.com" ] || session_file="$HOME/gh-session-$host"
    printf "'admin:public_key', 'admin:ssh_signing_key'" > "$session_file"
    ;;
  "auth refresh")
    session_file="$HOME/gh-session"
    [ -z "$host" ] || [ "$host" = "github.com" ] || session_file="$HOME/gh-session-$host"
    printf "'admin:public_key', 'admin:ssh_signing_key'" > "$session_file"
    ;;
  # SSH keys are account-scoped, so a second host (a second github.com
  # account, or a GitHub Enterprise instance) has its own key list, exactly
  # like the session/scopes files above; GH_HOST (not a -h flag, which
  # neither ssh-key subcommand takes) is what selects it.
  "ssh-key list")
    keys_file="$HOME/gh-keys"
    [ "$GH_HOST" = "github.com" ] || keys_file="$HOME/gh-keys-$GH_HOST"
    cat "$keys_file" 2>/dev/null || true
    ;;
  # An upload lands in the same list a later run reads back, so running
  # configure twice can be tested the way GitHub would actually behave. The
  # mock records the --type it was given, letting the per-type dedupe be
  # tested.
  "ssh-key add")
    pubfile="$3"
    shift 3
    ssh_key_type=""
    ssh_key_title=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --type) ssh_key_type="$2" ;;
        --title) ssh_key_title="$2" ;;
      esac
      shift
    done
    [ -n "$ssh_key_title" ] || ssh_key_title="title"
    ssh_key_body="$(awk '{print $2}' < "$pubfile")"
    keys_file="$HOME/gh-keys"
    [ "$GH_HOST" = "github.com" ] || keys_file="$HOME/gh-keys-$GH_HOST"
    # Tab-separated, matching the non-TTY output of the real `gh ssh-key list`
    # (gh 2.100.0): TITLE, KEY, ADDED, ID, TYPE. The type is the LAST column
    # and a numeric ID sits second to last. The title is free text (it may
    # itself contain the word "signing"), so it must never be what the dedupe
    # check parses either.
    ssh_key_id="$(( $(wc -l < "$keys_file" 2>/dev/null || echo 0) + 58095771 ))"
    printf '%s\tssh-ed25519 %s\t2026-09-11T09:12:33Z\t%s\t%s\n' \
      "$ssh_key_title" "$ssh_key_body" "$ssh_key_id" "$ssh_key_type" >> "$keys_file"
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

seed_work_key() {
  mkdir -p "$TEST_HOME/.ssh"
  printf 'ssh-ed25519 AAAAWORKKEY ada@corp.example\n' > "$TEST_HOME/.ssh/id_ed25519_work.pub"
  printf 'PRIVATE\n' > "$TEST_HOME/.ssh/id_ed25519_work"
}

# A work identity is per-machine, not a wizard answer (2026-09-17 decision):
# machines/<hostname>.conf is the only source of TEEUP_WORK_EMAIL and
# TEEUP_WORK_GH_HOST. hostname is mocked to "testmac" by mock_macos_base.
seed_machine_work() {
  local email="$1" gh_host="${2:-}"
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR"
  {
    printf 'TEEUP_WORK_EMAIL="%s"\n' "$email"
    [[ -n "$gh_host" ]] && printf 'TEEUP_WORK_GH_HOST="%s"\n' "$gh_host"
  } > "$TEEUP_MACHINES_DIR/testmac.conf"
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
  assert_contains "$(cat "$MOCK_LOG")" "auth login --hostname github.com --web --git-protocol ssh --scopes admin:public_key,admin:ssh_signing_key" || return 1
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
  printf 'laptop\tssh-ed25519 AAAAPERSONALKEY\t2026-09-11T09:12:33Z\t58095771\tauthentication\n' > "$TEST_HOME/gh-keys"
  printf 'laptop (signing)\tssh-ed25519 AAAAPERSONALKEY\t2026-09-11T09:12:34Z\t58095772\tsigning\n' >> "$TEST_HOME/gh-keys"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  assert_contains "$out" "Already uploaded" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "ssh-key add" || return 1
  cleanup_test_env
}

test_configure_recognises_the_real_five_column_row() {
  setup
  seed_keys
  # Exactly what the installed gh 2.100.0 prints on its non-TTY path:
  # TITLE, KEY, ADDED, ID, TYPE. A parser that reads the second-to-last column
  # as the type sees the numeric ID instead, never matches, and re-uploads a
  # key GitHub already has on every single run.
  printf 'testmac personal\tssh-ed25519 AAAAPERSONALKEY\t2021-10-16T21:11:41Z\t58095771\tauthentication\n' > "$TEST_HOME/gh-keys"
  printf 'testmac personal (signing)\tssh-ed25519 AAAAPERSONALKEY\t2021-10-16T21:11:42Z\t58095772\tsigning\n' >> "$TEST_HOME/gh-keys"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  assert_contains "$out" "Already uploaded (authentication)" || return 1
  assert_contains "$out" "Already uploaded (signing)" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "ssh-key add" || return 1
  cleanup_test_env
}

test_configure_lets_the_active_account_decide_the_scopes() {
  setup
  seed_keys
  # Two accounts on github.com. The active one (the account every `gh ssh-key
  # add` below will use) lacks the signing scope; the inactive one has it.
  # Without --active, `gh auth status -h github.com` prints both accounts'
  # "Token scopes:" lines and the substring check finds the signing scope on
  # the wrong account, skipping the refresh the uploads actually need.
  printf "'admin:public_key'" > "$TEST_HOME/gh-session"
  printf "'admin:public_key', 'admin:ssh_signing_key'" > "$TEST_HOME/gh-inactive-scopes"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  assert_contains "$out" "Already signed in to GitHub (github.com)." || return 1
  assert_contains "$(cat "$MOCK_LOG")" "auth status --active -h github.com" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "auth refresh -h github.com -s admin:public_key,admin:ssh_signing_key" || return 1
  cleanup_test_env
}

test_configure_ignores_an_inactive_accounts_missing_scopes() {
  setup
  seed_keys
  # The mirror image: the active account has both scopes, a second account on
  # the same host has only one. Nothing needs refreshing.
  printf "'admin:public_key', 'admin:ssh_signing_key'" > "$TEST_HOME/gh-session"
  printf "'admin:public_key'" > "$TEST_HOME/gh-inactive-scopes"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  assert_contains "$out" "Already signed in to GitHub (github.com)." || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "auth refresh" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "auth login" || return 1
  cleanup_test_env
}

test_configure_refreshes_scopes_when_the_signing_scope_is_missing() {
  setup
  seed_keys
  printf "'admin:public_key'" > "$TEST_HOME/gh-session"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  assert_contains "$out" "Already signed in to GitHub (github.com)." || return 1
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
  assert_contains "$out" "Already signed in to GitHub (github.com)." || return 1
  assert_contains "$(cat "$MOCK_LOG")" "auth refresh -h github.com -s admin:public_key,admin:ssh_signing_key" || return 1
  cleanup_test_env
}

test_configure_retries_the_signing_upload_when_only_authentication_is_present() {
  setup
  seed_keys
  printf "'admin:public_key', 'admin:ssh_signing_key'" > "$TEST_HOME/gh-session"
  printf 'laptop\tssh-ed25519 AAAAPERSONALKEY\t2026-09-11T09:12:33Z\t58095771\tauthentication\n' > "$TEST_HOME/gh-keys"
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
  assert_contains "$out" "Already signed in to GitHub (github.com)." || return 1
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

test_configure_pins_gh_host_to_github_com() {
  setup
  seed_keys
  export GH_HOST=enterprise.invalid
  DRY_RUN=false "$TEEUP" configure github >/dev/null 2>&1
  local calls
  calls="$(cat "$MOCK_LOG")"
  assert_contains "$calls" "GH_HOST=github.com" || return 1
  assert_not_contains "$calls" "GH_HOST=enterprise.invalid" || return 1
  assert_contains "$calls" "auth login --hostname github.com" || return 1
  cleanup_test_env
}

test_configure_does_not_let_a_signing_titled_authentication_key_suppress_signing() {
  setup
  seed_keys
  # An authentication key whose title happens to contain the word "signing"
  # must not be mistaken for an already-uploaded signing key: only the KEY
  # and TYPE columns count, never the title.
  printf 'laptop signing key\tssh-ed25519 AAAAPERSONALKEY\t2026-09-11T09:12:33Z\t58095771\tauthentication\n' > "$TEST_HOME/gh-keys"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  local calls
  calls="$(cat "$MOCK_LOG")"
  assert_contains "$out" "Already uploaded (authentication)" || return 1
  assert_not_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub --type authentication" || return 1
  assert_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub --type signing --title testmac personal (signing)" || return 1
  cleanup_test_env
}

test_configure_does_not_let_a_key_titled_exactly_signing_suppress_signing() {
  setup
  seed_keys
  printf "'admin:public_key', 'admin:ssh_signing_key'" > "$TEST_HOME/gh-session"
  # The title is the first column and free text. A forward scan for "the
  # field that equals a type" stopped on this title, called the row a signing
  # key, skipped the signing upload and retried the authentication one.
  printf 'signing\tssh-ed25519 AAAAPERSONALKEY\t2026-09-11T09:12:33Z\t58095771\tauthentication\n' > "$TEST_HOME/gh-keys"
  local out calls
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  calls="$(cat "$MOCK_LOG")"
  assert_contains "$out" "Already uploaded (authentication)" || return 1
  assert_not_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub --type authentication" || return 1
  assert_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub --type signing --title testmac personal (signing)" || return 1
  cleanup_test_env
}

test_configure_reads_the_type_from_the_last_column_whatever_the_title() {
  setup
  seed_keys
  printf "'admin:public_key', 'admin:ssh_signing_key'" > "$TEST_HOME/gh-session"
  # Our authentication key is up under the title "signing"; someone else's
  # signing key is up under the title "authentication". Only the last column
  # may decide: a title-driven reading swaps the two, re-uploads the
  # authentication key and skips the signing one.
  printf 'signing\tssh-ed25519 AAAAPERSONALKEY\t2026-09-11T09:12:33Z\t58095771\tauthentication\n' > "$TEST_HOME/gh-keys"
  printf 'authentication\tssh-ed25519 SOMEONEELSE\t2026-09-11T09:12:34Z\t58095772\tsigning\n' >> "$TEST_HOME/gh-keys"
  local out calls
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  calls="$(cat "$MOCK_LOG")"
  assert_contains "$out" "Already uploaded (authentication)" || return 1
  assert_not_contains "$out" "Already uploaded (signing)" || return 1
  assert_not_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub --type authentication" || return 1
  assert_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub --type signing" || return 1
  cleanup_test_env
}

test_configure_never_matches_the_key_body_against_the_title() {
  setup
  seed_keys
  printf "'admin:public_key', 'admin:ssh_signing_key'" > "$TEST_HOME/gh-session"
  # A foreign key whose *title* is our key body. The backward scan for the
  # KEY column must stop before field 1, or this row suppresses our upload.
  printf 'someone AAAAPERSONALKEY\tssh-ed25519 SOMEONEELSE\t2026-09-11T09:12:33Z\t58095771\tauthentication\n' > "$TEST_HOME/gh-keys"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  assert_not_contains "$out" "Already uploaded" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub --type authentication" || return 1
  cleanup_test_env
}

test_configure_compares_the_key_body_exactly() {
  setup
  seed_keys
  printf "'admin:public_key', 'admin:ssh_signing_key'" > "$TEST_HOME/gh-session"
  # Someone else's key whose body merely contains ours is not ours: a
  # substring match would have skipped both uploads.
  printf 'other laptop\tssh-ed25519 AAAAPERSONALKEYEXTRA\t2026-09-11T09:12:33Z\t58095771\tauthentication\n' > "$TEST_HOME/gh-keys"
  printf 'other laptop (signing)\tssh-ed25519 XAAAAPERSONALKEY\t2026-09-11T09:12:34Z\t58095772\tsigning\n' >> "$TEST_HOME/gh-keys"
  local out calls
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  calls="$(cat "$MOCK_LOG")"
  assert_not_contains "$out" "Already uploaded" || return 1
  assert_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub --type authentication" || return 1
  assert_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub --type signing" || return 1
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
  assert_contains "$out" "Already signed in to GitHub (github.com)." || return 1
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

test_configure_uploads_the_work_key_to_a_second_github_com_account() {
  setup
  seed_keys
  seed_work_key
  seed_machine_work "ada@corp.example"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  local calls
  calls="$(cat "$MOCK_LOG")"
  assert_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub --type authentication --title testmac personal" || return 1
  assert_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_work.pub --type authentication --title testmac work" || return 1
  assert_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_work.pub --type signing --title testmac work (signing)" || return 1
  # Both identities land on the same host and file, since TEEUP_WORK_GH_HOST
  # was not set: a second github.com account, not a separate service.
  [[ ! -e "$TEST_HOME/gh-keys-github.com" ]] || { echo "a separate github.com key file was created"; return 1; }
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_configure_uploads_the_work_key_to_a_github_enterprise_host() {
  setup
  seed_keys
  seed_work_key
  seed_machine_work "ada@corp.example" "github.enterprise.example.com"
  # Personal is already signed in on github.com; the Enterprise host is not,
  # so only it goes through `auth login`.
  printf "'admin:public_key', 'admin:ssh_signing_key'" > "$TEST_HOME/gh-session"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  assert_contains "$out" "Already signed in to GitHub (github.com)." || return 1
  local calls
  calls="$(cat "$MOCK_LOG")"
  assert_contains "$calls" "auth login --hostname github.enterprise.example.com --web --git-protocol ssh --scopes admin:public_key,admin:ssh_signing_key" || return 1
  assert_contains "$calls" "config set git_protocol ssh --host github.enterprise.example.com" || return 1
  # The personal key still goes to github.com...
  assert_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub --type authentication --title testmac personal" || return 1
  # ...and the work key to the Enterprise host, tracked separately.
  assert_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_work.pub --type authentication --title testmac work" || return 1
  assert_file_exists "$TEST_HOME/gh-keys-github.enterprise.example.com" || return 1
  # The personal upload belongs in the plain (github.com) key list, not the
  # Enterprise one.
  assert_not_contains "$(cat "$TEST_HOME/gh-keys-github.enterprise.example.com")" "AAAAPERSONALKEY" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_configure_signs_in_to_each_host_independently() {
  setup
  seed_keys
  seed_work_key
  seed_machine_work "ada@corp.example" "github.enterprise.example.com"
  # Personal is already signed in on github.com with both scopes; the
  # Enterprise host has never been logged into. Only the Enterprise host may
  # go through `auth login`.
  printf "'admin:public_key', 'admin:ssh_signing_key'" > "$TEST_HOME/gh-session"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  local calls
  calls="$(cat "$MOCK_LOG")"
  assert_contains "$out" "Already signed in to GitHub (github.com)." || return 1
  assert_not_contains "$calls" "auth login --hostname github.com" || return 1
  assert_contains "$calls" "auth login --hostname github.enterprise.example.com" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_configure_skips_a_key_already_uploaded_to_the_enterprise_host() {
  setup
  seed_keys
  seed_work_key
  seed_machine_work "ada@corp.example" "github.enterprise.example.com"
  mkdir -p "$TEST_HOME"
  printf 'testmac work\tssh-ed25519 AAAAWORKKEY\t2026-09-11T09:12:33Z\t58095771\tauthentication\n' > "$TEST_HOME/gh-keys-github.enterprise.example.com"
  printf 'testmac work (signing)\tssh-ed25519 AAAAWORKKEY\t2026-09-11T09:12:34Z\t58095772\tsigning\n' >> "$TEST_HOME/gh-keys-github.enterprise.example.com"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  local calls
  calls="$(cat "$MOCK_LOG")"
  assert_contains "$out" "Already uploaded (authentication)" || return 1
  assert_contains "$out" "Already uploaded (signing)" || return 1
  assert_not_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_work.pub" || return 1
  # The personal upload against github.com must still happen: an upload
  # already present on the Enterprise host must not suppress it.
  assert_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub --type authentication" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_configure_dry_run_uploads_nothing_for_either_identity() {
  setup
  seed_keys
  seed_work_key
  seed_machine_work "ada@corp.example" "github.enterprise.example.com"
  local out
  out="$(DRY_RUN=true "$TEEUP" configure github 2>&1)"
  assert_contains "$out" "Would execute: gh auth login --hostname github.enterprise.example.com" || return 1
  assert_contains "$out" "Would execute: gh ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub" || return 1
  assert_contains "$out" "Would execute: gh ssh-key add $TEST_HOME/.ssh/id_ed25519_work.pub" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "ssh-key add" || return 1
  [[ ! -e "$TEST_HOME/gh-keys" && ! -e "$TEST_HOME/gh-keys-github.enterprise.example.com" ]] ||
    { echo "a key list was written in dry run"; return 1; }
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_configure_twice_with_a_work_identity_uploads_nothing_new() {
  setup
  seed_keys
  seed_work_key
  seed_machine_work "ada@corp.example" "github.enterprise.example.com"
  DRY_RUN=false "$TEEUP" configure github >/dev/null 2>&1
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  local calls
  calls="$(cat "$MOCK_LOG")"
  assert_contains "$out" "Already signed in to GitHub (github.com)." || return 1
  assert_contains "$out" "Already signed in to GitHub (github.enterprise.example.com)." || return 1
  assert_not_contains "$calls" "ssh-key add" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

# B2: a TEEUP_WORK_EMAIL left behind in the answers file by the wizard that
# used to ask for one must not upload a second key to GitHub.
test_a_stale_work_email_answer_uploads_nothing_extra() {
  setup
  seed_keys
  seed_work_key
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_WORK_EMAIL="ada@corp.example"\n' > "$TEST_HOME/.config/teeup/answers"
  DRY_RUN=false "$TEEUP" configure github >/dev/null 2>&1
  local calls
  calls="$(cat "$MOCK_LOG")"
  assert_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub --type authentication" || return 1
  assert_not_contains "$calls" "id_ed25519_work.pub" "a stale answer must not upload a work key" || return 1
  cleanup_test_env
}

echo "capabilities/github"
run_test "install gets gh" test_install_gets_gh
run_test "configure logs in with the two scopes" test_configure_logs_in_with_the_two_scopes
run_test "configure uploads authentication and signing keys" test_configure_uploads_authentication_and_signing_keys
run_test "configure skips a key GitHub already has" test_configure_skips_a_key_github_already_has
run_test "configure recognises the real five-column ssh-key list row" test_configure_recognises_the_real_five_column_row
run_test "configure lets the active account decide the scopes" test_configure_lets_the_active_account_decide_the_scopes
run_test "configure ignores an inactive account's missing scopes" test_configure_ignores_an_inactive_accounts_missing_scopes
run_test "configure refreshes scopes when the signing scope is missing" test_configure_refreshes_scopes_when_the_signing_scope_is_missing
run_test "configure lets github.com scopes decide over another host" test_configure_lets_github_com_scopes_decide_over_another_host
run_test "configure retries the signing upload when only authentication is present" test_configure_retries_the_signing_upload_when_only_authentication_is_present
run_test "configure skips the login when already signed in" test_configure_skips_the_login_when_already_signed_in
run_test "configure warns when the key is missing" test_configure_warns_when_the_key_is_missing
run_test "configure pins GH_HOST to github.com" test_configure_pins_gh_host_to_github_com
run_test "configure does not let a signing-titled authentication key suppress signing" test_configure_does_not_let_a_signing_titled_authentication_key_suppress_signing
run_test "configure does not let a key titled exactly 'signing' suppress signing" test_configure_does_not_let_a_key_titled_exactly_signing_suppress_signing
run_test "configure reads the type from the last column whatever the title" test_configure_reads_the_type_from_the_last_column_whatever_the_title
run_test "configure compares the key body exactly" test_configure_compares_the_key_body_exactly
run_test "configure never matches the key body against the title" test_configure_never_matches_the_key_body_against_the_title
run_test "configure dry run uploads nothing" test_configure_dry_run_uploads_nothing
run_test "configure twice uploads nothing new" test_configure_twice_uploads_nothing_new
run_test "a stale work email answer uploads nothing extra" test_a_stale_work_email_answer_uploads_nothing_extra
run_test "configure uploads the work key to a second github.com account" test_configure_uploads_the_work_key_to_a_second_github_com_account
run_test "configure uploads the work key to a GitHub Enterprise host" test_configure_uploads_the_work_key_to_a_github_enterprise_host
run_test "configure signs in to each host independently" test_configure_signs_in_to_each_host_independently
run_test "configure skips a key already uploaded to the Enterprise host" test_configure_skips_a_key_already_uploaded_to_the_enterprise_host
run_test "configure dry run uploads nothing for either identity" test_configure_dry_run_uploads_nothing_for_either_identity
run_test "configure twice with a work identity uploads nothing new" test_configure_twice_with_a_work_identity_uploads_nothing_new
print_summary
