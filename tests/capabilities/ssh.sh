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
  } > "$TEST_HOME/.config/teeup/answers"
}

# A work identity is per-machine, not a wizard answer (2026-09-17 decision):
# machines/<hostname>.conf is the only source of TEEUP_WORK_EMAIL. hostname is
# mocked to "testmac" by mock_macos_base above.
seed_machine_work() {
  local email="$1" gh_host="${2:-}"
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR"
  {
    printf 'TEEUP_WORK_EMAIL="%s"\n' "$email"
    [[ -n "$gh_host" ]] && printf 'TEEUP_WORK_GH_HOST="%s"\n' "$gh_host"
  } > "$TEEUP_MACHINES_DIR/testmac.conf"
}

test_configure_generates_one_key_on_a_machine_with_no_work_identity() {
  setup
  seed_answers
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  assert_file_exists "$TEST_HOME/.ssh/id_ed25519_personal" || return 1
  assert_file_exists "$TEST_HOME/.ssh/id_ed25519_personal.pub" || return 1
  [[ ! -e "$TEST_HOME/.ssh/id_ed25519_work" ]] || { echo "work key on a machine with no work identity"; return 1; }
  cleanup_test_env
}

test_configure_generates_both_keys_when_the_machine_file_configures_work() {
  setup
  seed_answers
  seed_machine_work "ada@corp.example"
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  assert_file_exists "$TEST_HOME/.ssh/id_ed25519_work" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "ssh-keygen -t ed25519 -C ada@corp.example" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_configure_generates_the_work_key_on_a_github_enterprise_host_too() {
  setup
  seed_answers
  # The GitHub host the work identity uploads to (see the github suite) has
  # no bearing on ssh's own key-per-identity loop: a work identity still gets
  # exactly one key, named and commented the same way regardless of host.
  seed_machine_work "ada@corp.example" "github.enterprise.example.com"
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  assert_file_exists "$TEST_HOME/.ssh/id_ed25519_work" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "ssh-keygen -t ed25519 -C ada@corp.example" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_configure_adds_the_keys_to_the_keychain() {
  setup
  seed_answers
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  assert_contains "$(cat "$MOCK_LOG")" "ssh-add --apple-use-keychain $TEST_HOME/.ssh/id_ed25519_personal" || return 1
  cleanup_test_env
}

test_configure_uses_apple_use_keychain_on_macos_12_and_newer() {
  setup
  mock_command sw_vers 0 "12.0"
  seed_answers
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  assert_contains "$(cat "$MOCK_LOG")" "ssh-add --apple-use-keychain $TEST_HOME/.ssh/id_ed25519_personal" || return 1
  cleanup_test_env
}

test_configure_uses_dash_k_before_macos_12() {
  setup
  mock_command sw_vers 0 "11.6"
  seed_answers
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  assert_contains "$(cat "$MOCK_LOG")" "ssh-add -K $TEST_HOME/.ssh/id_ed25519_personal" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "--apple-use-keychain" || return 1
  cleanup_test_env
}

test_configure_installs_the_ssh_config_with_both_hosts() {
  setup
  seed_answers
  seed_machine_work "ada@corp.example"
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  local body
  body="$(cat "$TEST_HOME/.ssh/config")"
  assert_contains "$body" "Host github.com-work" || return 1
  assert_contains "$body" "IdentityFile ~/.ssh/id_ed25519_work" || return 1
  assert_contains "$body" "UseKeychain yes" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

# I2: the work alias used to be shipped unconditionally, so a machine with no
# work identity got a Host block pointing at a key that does not exist -- with
# IdentitiesOnly yes, so any accidental use of it fails with no usable
# identity -- and the spec amendment this branch wrote said otherwise.
test_the_shipped_config_has_no_work_alias_without_a_work_identity() {
  setup
  seed_answers
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  local body
  body="$(cat "$TEST_HOME/.ssh/config")"
  assert_not_contains "$body" "github.com-work" || return 1
  assert_not_contains "$body" "id_ed25519_work" || return 1
  assert_contains "$body" "Host github.com" || return 1
  assert_contains "$body" "IdentityFile ~/.ssh/id_ed25519_personal" || return 1
  cleanup_test_env
}

# The alias is local, but it has to point somewhere real: a work identity on a
# GitHub Enterprise host is not reachable through github.com.
test_the_work_alias_points_at_the_work_host() {
  setup
  seed_answers
  seed_machine_work "ada@corp.example" "github.enterprise.example.com"
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  local body
  body="$(cat "$TEST_HOME/.ssh/config")"
  assert_contains "$body" "Host github.com-work" || return 1
  assert_contains "$body" "HostName github.enterprise.example.com" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

# I1: an existing ~/.ssh/config is the user's and teeup never rewrites it --
# but then the alias the work key is meant to be used through does not exist,
# git@github.com-work:org/repo.git resolves to nothing, and teeup used to say
# nothing at all about it.
test_configure_prints_the_block_a_foreign_config_is_missing() {
  setup
  seed_answers
  seed_machine_work "ada@corp.example"
  mkdir -p "$TEST_HOME/.ssh"
  cat > "$TEST_HOME/.ssh/config" <<'CFG'
Host myserver
  User someone
CFG
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  assert_contains "$out" "$TEST_HOME/.ssh/config" || return 1
  assert_contains "$out" "Host github.com-work" || return 1
  assert_contains "$out" "IdentityFile $TEST_HOME/.ssh/id_ed25519_work" || return 1
  assert_contains "$out" "IdentitiesOnly yes" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_configure_says_nothing_when_the_foreign_config_already_names_the_key() {
  setup
  seed_answers
  mkdir -p "$TEST_HOME/.ssh"
  printf 'MINE\n' > "$TEST_HOME/.ssh/id_rsa_legacy"
  printf 'ssh-ed25519 LEGACY comment\n' > "$TEST_HOME/.ssh/id_rsa_legacy.pub"
  cat > "$TEST_HOME/.ssh/config" <<CFG
Host github.com
  IdentityFile $TEST_HOME/.ssh/id_rsa_legacy
CFG
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  assert_not_contains "$out" "has no Host block" || return 1
  cleanup_test_env
}

test_configure_says_nothing_about_a_config_teeup_installed() {
  setup
  seed_answers
  seed_machine_work "ada@corp.example"
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  assert_not_contains "$out" "has no Host block" || return 1
  unset TEEUP_MACHINES_DIR
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
  seed_answers
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  assert_equals "700" "$(file_mode "$TEST_HOME/.ssh")" || return 1
  assert_equals "600" "$(file_mode "$TEST_HOME/.ssh/id_ed25519_personal")" || return 1
  assert_equals "600" "$(file_mode "$TEST_HOME/.ssh/config")" || return 1
  cleanup_test_env
}

test_existing_key_is_not_regenerated() {
  setup
  seed_answers
  mkdir -p "$TEST_HOME/.ssh"
  printf 'MINE\n' > "$TEST_HOME/.ssh/id_ed25519_personal"
  printf 'ssh-ed25519 MINE comment\n' > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  assert_contains "$out" "Already present: $TEST_HOME/.ssh/id_ed25519_personal" || return 1
  assert_equals "MINE" "$(cat "$TEST_HOME/.ssh/id_ed25519_personal")" || return 1
  cleanup_test_env
}

# An existing ~/.ssh/config is authority (2026-09-17 decision): a Host block
# already naming an IdentityFile wins over teeup's own convention, so the key
# it names is used instead of generating id_ed25519_personal.
test_configure_reuses_the_key_an_existing_ssh_config_already_names() {
  setup
  seed_answers
  mkdir -p "$TEST_HOME/.ssh"
  printf 'MINE-LEGACY-PRIVATE\n' > "$TEST_HOME/.ssh/id_rsa_legacy"
  printf 'ssh-ed25519 LEGACY comment\n' > "$TEST_HOME/.ssh/id_rsa_legacy.pub"
  cat > "$TEST_HOME/.ssh/config" <<CFG
Host github.com
  HostName github.com
  User git
  IdentityFile $TEST_HOME/.ssh/id_rsa_legacy
  IdentitiesOnly yes
CFG
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  assert_contains "$out" "Using the personal key already named in $TEST_HOME/.ssh/config: $TEST_HOME/.ssh/id_rsa_legacy" || return 1
  assert_contains "$out" "Already present: $TEST_HOME/.ssh/id_rsa_legacy" || return 1
  [[ ! -e "$TEST_HOME/.ssh/id_ed25519_personal" ]] || { echo "teeup generated a second personal key"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "ssh-keygen -t ed25519" || return 1
  cleanup_test_env
}

test_configure_never_replaces_an_existing_ssh_config() {
  setup
  seed_answers
  mkdir -p "$TEST_HOME/.ssh"
  cat > "$TEST_HOME/.ssh/config" <<'CFG'
Host example.org
  User someone
CFG
  local before after
  before="$(cat "$TEST_HOME/.ssh/config")"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  after="$(cat "$TEST_HOME/.ssh/config")"
  assert_equals "$before" "$after" "an existing ~/.ssh/config must never be rewritten" || return 1
  assert_contains "$out" "Already present: $TEST_HOME/.ssh/config" || return 1
  assert_not_contains "$out" "Would install" "teeup config" || true
  cleanup_test_env
}

test_configure_dry_run_reuse_writes_nothing_and_generates_nothing() {
  setup
  seed_answers
  mkdir -p "$TEST_HOME/.ssh"
  printf 'MINE-LEGACY-PRIVATE\n' > "$TEST_HOME/.ssh/id_rsa_legacy"
  printf 'ssh-ed25519 LEGACY comment\n' > "$TEST_HOME/.ssh/id_rsa_legacy.pub"
  cat > "$TEST_HOME/.ssh/config" <<CFG
Host github.com
  IdentityFile $TEST_HOME/.ssh/id_rsa_legacy
CFG
  local out
  out="$(DRY_RUN=true "$TEEUP" configure ssh 2>&1)"
  assert_contains "$out" "Using the personal key already named in $TEST_HOME/.ssh/config" || return 1
  assert_not_contains "$out" "Would execute: ssh-keygen -t ed25519" || return 1
  [[ ! -e "$TEST_HOME/.ssh/id_ed25519_personal" ]] || { echo "key generated in dry run"; return 1; }
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  seed_answers
  local out
  out="$(DRY_RUN=true "$TEEUP" configure ssh 2>&1)"
  assert_contains "$out" "Would execute: ssh-keygen -t ed25519 -C ada@example.com" || return 1
  [[ ! -e "$TEST_HOME/.ssh/id_ed25519_personal" ]] || { echo "key written in dry run"; return 1; }
  cleanup_test_env
}

test_configure_rebuilds_a_missing_public_half() {
  setup
  seed_answers
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
  seed_answers
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
  seed_answers
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
  seed_answers
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
  seed_answers
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
  seed_answers
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
  seed_answers
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
  seed_answers
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
  seed_answers
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
  seed_answers
  seed_machine_work "ada@corp.example"
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  local marker="$TEST_HOME/.idempotency-marker"
  : > "$marker"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  assert_contains "$out" "Already present: $TEST_HOME/.ssh/id_ed25519_personal" || return 1
  assert_contains "$out" "Already present: $TEST_HOME/.ssh/config" || return 1
  assert_not_contains "$out" "Generating the" || return 1
  # chmod_once keeps the second run silent, so nothing under $HOME may change.
  local changed
  changed="$(find "$TEST_HOME" -newer "$marker" -type f \
    ! -name 'mock.log' ! -name '.idempotency-marker' 2>/dev/null)"
  assert_equals "" "$changed" "second configure must write nothing" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

# B2: the wizard that shipped before 2026-09-17 wrote TEEUP_WORK_EMAIL into
# the answers file. A machine upgrading from it must not get a second identity
# out of that leftover: a second passphrase prompt, a second key and a second
# upload, from a question the tool no longer asks. Only the machine file
# configures work.
test_a_stale_work_email_answer_generates_no_second_key() {
  setup
  mkdir -p "$TEST_HOME/.config/teeup"
  {
    printf 'TEEUP_NAME="Ada Lovelace"\n'
    printf 'TEEUP_EMAIL="ada@example.com"\n'
    printf 'TEEUP_WORK_EMAIL="ada@corp.example"\n'
  } > "$TEST_HOME/.config/teeup/answers"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  assert_file_exists "$TEST_HOME/.ssh/id_ed25519_personal" || return 1
  [[ ! -e "$TEST_HOME/.ssh/id_ed25519_work" ]] || { echo "a stale answer generated a work key"; return 1; }
  assert_not_contains "$out" "Generating the work" || return 1
  cleanup_test_env
}

# I4: -s and -e both follow a symlink, so a dangling one was neither "there"
# nor "missing": the backup guard never fired and ssh-keygen wrote the new
# PRIVATE key through the link, to wherever it pointed -- possibly outside
# ~/.ssh entirely, into a synced folder or a dotfiles repo.
test_configure_replaces_a_dangling_symlink_at_the_key_path() {
  setup
  seed_answers
  mkdir -p "$TEST_HOME/.ssh" "$TEST_HOME/elsewhere"
  ln -s "$TEST_HOME/elsewhere/gone" "$TEST_HOME/.ssh/id_ed25519_personal"
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  [[ ! -e "$TEST_HOME/elsewhere/gone" ]] || { echo "the private key was written through the symlink"; return 1; }
  [[ ! -L "$TEST_HOME/.ssh/id_ed25519_personal" ]] || { echo "the key path is still a symlink"; return 1; }
  assert_file_exists "$TEST_HOME/.ssh/id_ed25519_personal" || return 1
  local backups
  backups="$(find "$TEST_HOME/.ssh" -name 'id_ed25519_personal.teeup_backup_*' | wc -l | tr -d ' ')"
  assert_equals "1" "$backups" "the symlink is backed up, not discarded" || return 1
  cleanup_test_env
}

test_configure_replaces_a_symlink_at_the_public_key_path() {
  setup
  seed_answers
  mkdir -p "$TEST_HOME/.ssh" "$TEST_HOME/elsewhere"
  ln -s "$TEST_HOME/elsewhere/gone.pub" "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  [[ ! -e "$TEST_HOME/elsewhere/gone.pub" ]] || { echo "the public key was written through the symlink"; return 1; }
  [[ ! -L "$TEST_HOME/.ssh/id_ed25519_personal.pub" ]] || { echo "the .pub path is still a symlink"; return 1; }
  cleanup_test_env
}

# I5: chmod_once used -e and stat, both of which follow a symlink, so teeup
# silently tightened a ~/.ssh/config symlinked into a dotfiles repo (a diff
# there, from a file teeup says it does not own) and loosened a reused .pub
# from 600 to 644. Only files teeup created get their mode set.
test_configure_does_not_chmod_a_config_it_does_not_own() {
  setup
  seed_answers
  mkdir -p "$TEST_HOME/.ssh" "$TEST_HOME/dotfiles/ssh"
  printf 'MINE\n' > "$TEST_HOME/.ssh/dotkey"
  printf 'ssh-ed25519 DOTKEY comment\n' > "$TEST_HOME/.ssh/dotkey.pub"
  chmod 644 "$TEST_HOME/.ssh/dotkey"
  chmod 600 "$TEST_HOME/.ssh/dotkey.pub"
  cat > "$TEST_HOME/dotfiles/ssh/config" <<CFG
Host github.com
  IdentityFile $TEST_HOME/.ssh/dotkey
CFG
  chmod 644 "$TEST_HOME/dotfiles/ssh/config"
  ln -s "$TEST_HOME/dotfiles/ssh/config" "$TEST_HOME/.ssh/config"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  assert_equals "644" "$(file_mode "$TEST_HOME/dotfiles/ssh/config")" "a config teeup did not install keeps its mode" || return 1
  assert_equals "644" "$(file_mode "$TEST_HOME/.ssh/dotkey")" "a reused key keeps its mode" || return 1
  assert_equals "600" "$(file_mode "$TEST_HOME/.ssh/dotkey.pub")" "a reused .pub is never loosened" || return 1
  assert_contains "$out" "$TEST_HOME/.ssh/dotkey" "the loose private key is named" || return 1
  assert_contains "$out" "chmod 600" "and the command to fix it is given" || return 1
  cleanup_test_env
}

test_configure_still_tightens_the_files_it_created() {
  setup
  seed_answers
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  assert_equals "600" "$(file_mode "$TEST_HOME/.ssh/id_ed25519_personal")" || return 1
  assert_equals "644" "$(file_mode "$TEST_HOME/.ssh/id_ed25519_personal.pub")" || return 1
  assert_equals "600" "$(file_mode "$TEST_HOME/.ssh/config")" || return 1
  cleanup_test_env
}

# I6: the machine file is hand-edited and now carries the whole work model, so
# a malformed work email must stop the run rather than become an ssh key's
# comment and a GitHub upload.
test_a_malformed_work_email_stops_the_run() {
  setup
  seed_answers
  seed_machine_work "not-an-email"
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "TEEUP_WORK_EMAIL" || return 1
  assert_contains "$out" "$TEST_HOME/machines/testmac.conf" || return 1
  [[ ! -e "$TEST_HOME/.ssh/id_ed25519_work" ]] || { echo "a work key was generated from a malformed address"; return 1; }
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_doctor_passes_after_configure() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  seed_answers
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  local rc=0 out
  out="$(DRY_RUN=false cap_run ssh doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "personal key pair is present" || return 1
  assert_contains "$out" "Host github.com" || return 1
  cleanup_test_env
}

test_doctor_reports_a_missing_key_pair() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  seed_answers
  # The directory exists and is correctly locked down; what is missing is the
  # keys, which is the state a half-finished `teeup configure ssh` leaves.
  mkdir -p "$TEST_HOME/.ssh"
  chmod 700 "$TEST_HOME/.ssh"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run ssh doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "has no key pair" || return 1
  assert_contains "$(cat "$report")" "teeup configure ssh" || return 1
  cleanup_test_env
}

test_doctor_reports_a_world_readable_private_key() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  seed_answers
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  chmod 644 "$TEST_HOME/.ssh/id_ed25519_personal"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run ssh doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "is mode 644" || return 1
  assert_contains "$(cat "$report")" "chmod 600 $TEST_HOME/.ssh/id_ed25519_personal" || return 1
  cleanup_test_env
}

echo "capabilities/ssh"
run_test "configure generates one key on a machine with no work identity" test_configure_generates_one_key_on_a_machine_with_no_work_identity
run_test "configure generates both keys when the machine file configures work" test_configure_generates_both_keys_when_the_machine_file_configures_work
run_test "a stale work email answer generates no second key" test_a_stale_work_email_answer_generates_no_second_key
run_test "a malformed work email stops the run" test_a_malformed_work_email_stops_the_run
run_test "configure generates the work key on a GitHub Enterprise host too" test_configure_generates_the_work_key_on_a_github_enterprise_host_too
run_test "configure adds the keys to the keychain" test_configure_adds_the_keys_to_the_keychain
run_test "configure uses --apple-use-keychain on macOS 12 and newer" test_configure_uses_apple_use_keychain_on_macos_12_and_newer
run_test "configure uses -K before macOS 12" test_configure_uses_dash_k_before_macos_12
run_test "configure installs the ssh config with both hosts" test_configure_installs_the_ssh_config_with_both_hosts
run_test "the shipped config has no work alias without a work identity" test_the_shipped_config_has_no_work_alias_without_a_work_identity
run_test "the work alias points at the work host" test_the_work_alias_points_at_the_work_host
run_test "configure prints the block a foreign config is missing" test_configure_prints_the_block_a_foreign_config_is_missing
run_test "configure says nothing when the foreign config already names the key" test_configure_says_nothing_when_the_foreign_config_already_names_the_key
run_test "configure says nothing about a config teeup installed" test_configure_says_nothing_about_a_config_teeup_installed
run_test "permissions are tightened" test_permissions_are_tightened
run_test "configure replaces a dangling symlink at the key path" test_configure_replaces_a_dangling_symlink_at_the_key_path
run_test "configure replaces a symlink at the public key path" test_configure_replaces_a_symlink_at_the_public_key_path
run_test "configure does not chmod a config it does not own" test_configure_does_not_chmod_a_config_it_does_not_own
run_test "configure still tightens the files it created" test_configure_still_tightens_the_files_it_created
run_test "existing key is not regenerated" test_existing_key_is_not_regenerated
run_test "configure reuses the key an existing ssh config already names" test_configure_reuses_the_key_an_existing_ssh_config_already_names
run_test "configure never replaces an existing ssh config" test_configure_never_replaces_an_existing_ssh_config
run_test "configure dry run reuse writes nothing and generates nothing" test_configure_dry_run_reuse_writes_nothing_and_generates_nothing
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
run_test "doctor passes after configure" test_doctor_passes_after_configure
run_test "doctor reports a missing key pair" test_doctor_reports_a_missing_key_pair
run_test "doctor reports a world-readable private key" test_doctor_reports_a_world_readable_private_key
print_summary
