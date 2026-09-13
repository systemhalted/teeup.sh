#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command ssh-add 0 ""
  # A keygen that actually leaves the two files behind, so the permission and
  # idempotency steps have something to act on. `-y -f <key>` (the partial-pair
  # repair path) prints a fake public key to stdout instead, matching real
  # ssh-keygen -y, since the caller redirects that into place itself.
  mock_command_script ssh-keygen <<'EOF2'
if [ "$1" = "-y" ]; then
  shift
  [ "$1" = "-f" ] && shift
  [ -f "$1" ] || exit 1
  printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAKEKEY rebuilt\n'
  exit 0
fi
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

test_configure_rebuilds_a_missing_public_half() {
  setup
  seed_answers ""
  mkdir -p "$TEST_HOME/.ssh"
  printf 'MINE-PRIVATE\n' > "$TEST_HOME/.ssh/id_ed25519_personal"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  assert_contains "$out" "Rebuilding the missing public half" || return 1
  assert_file_exists "$TEST_HOME/.ssh/id_ed25519_personal.pub" || return 1
  # Exactly what the mocked `ssh-keygen -y` printed, moved into place whole.
  assert_equals "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAKEKEY rebuilt" \
    "$(cat "$TEST_HOME/.ssh/id_ed25519_personal.pub")" || return 1
  # The private half must be untouched: ssh-keygen was never asked to
  # regenerate it, only to derive the public half (-y).
  assert_equals "MINE-PRIVATE" "$(cat "$TEST_HOME/.ssh/id_ed25519_personal")" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "ssh-keygen -t ed25519" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "ssh-keygen -y -f $TEST_HOME/.ssh/id_ed25519_personal" || return 1
  cleanup_test_env
}

test_configure_rebuilds_a_zero_byte_public_half() {
  setup
  seed_answers ""
  mkdir -p "$TEST_HOME/.ssh"
  # The state the first version of the rebuild left behind after a mistyped
  # passphrase: a good private key next to an empty .pub. A -f guard called
  # that pair "Already present" forever; the empty file must go through the
  # rebuild like a missing one.
  printf 'MINE-PRIVATE\n' > "$TEST_HOME/.ssh/id_ed25519_personal"
  : > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  assert_not_contains "$out" "Already present" || return 1
  assert_contains "$out" "Rebuilding the missing public half" || return 1
  assert_equals "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAKEKEY rebuilt" \
    "$(cat "$TEST_HOME/.ssh/id_ed25519_personal.pub")" || return 1
  assert_equals "MINE-PRIVATE" "$(cat "$TEST_HOME/.ssh/id_ed25519_personal")" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "ssh-keygen -t ed25519" || return 1
  cleanup_test_env
}

test_configure_replaces_a_zero_byte_private_key() {
  setup
  seed_answers ""
  mkdir -p "$TEST_HOME/.ssh"
  # The mirror image: an empty private half beside a good .pub. With -f it
  # was "Already present" forever, ssh-add could only warn, and the github
  # capability uploaded an orphan .pub. Both files are moved aside (a fresh
  # ssh-keygen -f on an existing file would otherwise prompt "Overwrite?")
  # and a new pair is generated.
  : > "$TEST_HOME/.ssh/id_ed25519_personal"
  printf 'ssh-ed25519 ORPHAN comment\n' > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  local out
  out="$(DRY_RUN=true "$TEEUP" configure ssh 2>&1)"
  assert_contains "$out" "Would back up $TEST_HOME/.ssh/id_ed25519_personal to" || return 1
  assert_contains "$out" "Would execute: ssh-keygen -t ed25519" || return 1
  [[ ! -s "$TEST_HOME/.ssh/id_ed25519_personal" ]] || { echo "private key changed in dry run"; return 1; }
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  assert_not_contains "$out" "Already present" || return 1
  assert_contains "$out" "Empty private key at $TEST_HOME/.ssh/id_ed25519_personal" || return 1
  assert_contains "$out" "Backed up $TEST_HOME/.ssh/id_ed25519_personal to" || return 1
  assert_contains "$out" "Backed up $TEST_HOME/.ssh/id_ed25519_personal.pub to" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "ssh-keygen -t ed25519 -C ada@example.com -f $TEST_HOME/.ssh/id_ed25519_personal" || return 1
  [[ -s "$TEST_HOME/.ssh/id_ed25519_personal" ]] || { echo "no private key generated"; return 1; }
  assert_contains "$(cat "$TEST_HOME/.ssh/id_ed25519_personal.pub")" "AAAAC3NzaC1lZDI1NTE5AAAAIFAKEKEY comment" || return 1
  cleanup_test_env
}

test_configure_leaves_no_pub_behind_when_the_rebuild_fails() {
  setup
  seed_answers ""
  mkdir -p "$TEST_HOME/.ssh"
  printf 'MINE-PRIVATE\n' > "$TEST_HOME/.ssh/id_ed25519_personal"
  # A mistyped or cancelled passphrase: real ssh-keygen -y prints nothing and
  # exits 1. A plain `> "$key.pub"` redirect has already created and truncated
  # the target by then, and that zero-byte .pub made every later run see a
  # complete pair and skip the repair for good.
  mock_command_script ssh-keygen <<'EOF2'
[ "$1" = "-y" ] && exit 1
exit 0
EOF2
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  assert_contains "$out" "Rebuilding $TEST_HOME/.ssh/id_ed25519_personal.pub failed" || return 1
  [[ ! -e "$TEST_HOME/.ssh/id_ed25519_personal.pub" ]] ||
    { echo "a .pub survived a failed rebuild: $(wc -c < "$TEST_HOME/.ssh/id_ed25519_personal.pub") bytes"; return 1; }
  local leftovers
  leftovers="$(find "$TEST_HOME/.ssh" -name 'id_ed25519_personal.teeup_rebuild_*' 2>/dev/null)"
  assert_equals "" "$leftovers" "the temp file must not be left behind" || return 1
  assert_equals "MINE-PRIVATE" "$(cat "$TEST_HOME/.ssh/id_ed25519_personal")" || return 1
  cleanup_test_env
}

test_configure_dry_run_rebuild_prints_the_command_and_writes_nothing() {
  setup
  seed_answers ""
  mkdir -p "$TEST_HOME/.ssh"
  printf 'MINE-PRIVATE\n' > "$TEST_HOME/.ssh/id_ed25519_personal"
  local out
  out="$(DRY_RUN=true "$TEEUP" configure ssh 2>&1)"
  assert_contains "$out" "Would execute:" || return 1
  assert_contains "$out" "ssh-keygen -y -f" || return 1
  [[ ! -e "$TEST_HOME/.ssh/id_ed25519_personal.pub" ]] || { echo "pub written in dry run"; return 1; }
  assert_equals "MINE-PRIVATE" "$(cat "$TEST_HOME/.ssh/id_ed25519_personal")" || return 1
  cleanup_test_env
}

test_configure_backs_up_a_pub_only_key_and_regenerates_the_pair() {
  setup
  seed_answers ""
  mkdir -p "$TEST_HOME/.ssh"
  printf 'ssh-ed25519 ORPHAN comment\n' > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  assert_contains "$out" "Backed up $TEST_HOME/.ssh/id_ed25519_personal.pub" || return 1
  assert_file_exists "$TEST_HOME/.ssh/id_ed25519_personal" || return 1
  assert_equals "PRIVATE" "$(cat "$TEST_HOME/.ssh/id_ed25519_personal")" || return 1
  assert_contains "$(cat "$TEST_HOME/.ssh/id_ed25519_personal.pub")" "AAAAC3NzaC1lZDI1NTE5AAAAIFAKEKEY comment" || return 1
  local backup="" f
  for f in "$TEST_HOME"/.ssh/id_ed25519_personal.pub.teeup_backup_*; do
    [[ -e "$f" ]] && backup="$f"
  done
  [[ -n "$backup" ]] || { echo "orphan pub key not backed up"; return 1; }
  assert_contains "$(cat "$backup")" "ORPHAN" || return 1
  cleanup_test_env
}

test_configure_dry_run_pub_only_backs_up_nothing_and_generates_nothing() {
  setup
  seed_answers ""
  mkdir -p "$TEST_HOME/.ssh"
  printf 'ssh-ed25519 ORPHAN comment\n' > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  local out
  out="$(DRY_RUN=true "$TEEUP" configure ssh 2>&1)"
  assert_contains "$out" "Would back up" || return 1
  assert_contains "$out" "Would execute: ssh-keygen -t ed25519" || return 1
  [[ ! -e "$TEST_HOME/.ssh/id_ed25519_personal" ]] || { echo "private key written in dry run"; return 1; }
  assert_equals "ssh-ed25519 ORPHAN comment" "$(cat "$TEST_HOME/.ssh/id_ed25519_personal.pub")" || return 1
  cleanup_test_env
}

test_configure_reruns_git_configure_once_the_keys_exist() {
  setup
  seed_answers ""
  # git runs before ssh in the core list, so this is exactly the state a first
  # bootstrap reaches: a git config generated while no key existed, therefore
  # with commit signing off.
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  assert_file_exists "$TEST_HOME/.config/git/config" || return 1
  assert_contains "$(cat "$TEST_HOME/.config/git/teeup-generated")" "gpgsign = false" || return 1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  assert_contains "$out" "Re-running the git configuration" || return 1
  assert_contains "$out" "Completed: git configure" || return 1
  assert_contains "$(cat "$TEST_HOME/.config/git/teeup-generated")" "gpgsign = true" || return 1
  cleanup_test_env
}

test_configure_does_not_rerun_git_when_git_was_never_configured() {
  setup
  seed_answers ""
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  assert_not_contains "$out" "Re-running the git configuration" || return 1
  assert_not_contains "$out" "Completed: git configure" || return 1
  assert_contains "$out" "commit signing turns on at: teeup configure git" || return 1
  [[ ! -e "$TEST_HOME/.config/git/config" ]] || { echo "ssh configure wrote a git config"; return 1; }
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
run_test "configure rebuilds a missing public half" test_configure_rebuilds_a_missing_public_half
run_test "configure rebuilds a zero-byte public half" test_configure_rebuilds_a_zero_byte_public_half
run_test "configure replaces a zero-byte private key" test_configure_replaces_a_zero_byte_private_key
run_test "configure leaves no pub behind when the rebuild fails" test_configure_leaves_no_pub_behind_when_the_rebuild_fails
run_test "configure dry run rebuild prints the command and writes nothing" test_configure_dry_run_rebuild_prints_the_command_and_writes_nothing
run_test "configure re-runs git configure once the keys exist" test_configure_reruns_git_configure_once_the_keys_exist
run_test "configure does not re-run git when git was never configured" test_configure_does_not_rerun_git_when_git_was_never_configured
run_test "configure backs up a pub-only key and regenerates the pair" test_configure_backs_up_a_pub_only_key_and_regenerates_the_pair
run_test "configure dry run pub-only backs up nothing and generates nothing" test_configure_dry_run_pub_only_backs_up_nothing_and_generates_nothing
run_test "configure twice changes nothing" test_configure_twice_changes_nothing
print_summary
