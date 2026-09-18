#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_command hostname 0 "testmac"
  source "$TEEUP_PATH/lib/all.sh"
  # shellcheck disable=SC2034
  DRY_RUN=false
  # Point the machine file at a temp copy of the repo's machines/ dir.
  TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR"
}

test_set_then_get() {
  setup
  answers_set TEEUP_NAME "Ada Lovelace"
  answers_set TEEUP_EMAIL "ada@example.com"
  answers_load
  assert_equals "Ada Lovelace" "$(answers_get TEEUP_NAME)" || return 1
  assert_equals "ada@example.com" "$(answers_get TEEUP_EMAIL)" || return 1
  cleanup_test_env
}

test_set_replaces_existing_key() {
  setup
  answers_set TEEUP_THEME catppuccin
  answers_set TEEUP_THEME tokyo-night
  assert_equals "1" "$(grep -c '^TEEUP_THEME=' "$(answers_file)")" || return 1
  answers_load
  assert_equals "tokyo-night" "$(answers_get TEEUP_THEME)" || return 1
  cleanup_test_env
}

test_get_default_when_unset() {
  setup
  answers_load
  assert_equals "homebrew" "$(answers_get TEEUP_PACKAGE_MANAGER homebrew)" || return 1
  cleanup_test_env
}

test_machine_file_wins() {
  setup
  answers_set TEEUP_PACKAGE_MANAGER homebrew
  printf 'TEEUP_PACKAGE_MANAGER="macports"\n' > "$TEEUP_MACHINES_DIR/testmac.conf"
  answers_load
  assert_equals "macports" "$(answers_get TEEUP_PACKAGE_MANAGER)" || return 1
  cleanup_test_env
}

test_machine_get_reads_only_the_machine_file() {
  setup
  # No machine file: not set, even when the answers file has the key exported.
  answers_set TEEUP_PACKAGE_MANAGER homebrew
  answers_load
  ! machine_get TEEUP_PACKAGE_MANAGER >/dev/null || { echo "reported a pin with no machine file"; return 1; }
  printf 'TEEUP_PACKAGE_MANAGER="macports"\n' > "$TEEUP_MACHINES_DIR/testmac.conf"
  assert_equals "macports" "$(machine_get TEEUP_PACKAGE_MANAGER)" || return 1
  # A key the machine file does not mention is not set, even though it is
  # exported here from the answers file.
  answers_set TEEUP_THEME catppuccin
  ! machine_get TEEUP_THEME >/dev/null || { echo "reported a pin for an unmentioned key"; return 1; }
  # An empty value is a pin (set-ness, not non-emptiness).
  printf 'TEEUP_PACKAGE_MANAGER=""\n' > "$TEEUP_MACHINES_DIR/testmac.conf"
  machine_get TEEUP_PACKAGE_MANAGER >/dev/null || { echo "an empty pin was reported as unset"; return 1; }
  assert_equals "" "$(machine_get TEEUP_PACKAGE_MANAGER)" || return 1
  # The lookup leaves this shell's values alone.
  assert_equals "homebrew" "$TEEUP_PACKAGE_MANAGER" || return 1
  cleanup_test_env
}

test_values_with_spaces_and_quotes_survive() {
  setup
  answers_set TEEUP_NAME 'O'"'"'Brien "The" Dev'
  answers_load
  assert_equals 'O'"'"'Brien "The" Dev' "$(answers_get TEEUP_NAME)" || return 1
  cleanup_test_env
}

test_answers_exist() {
  setup
  answers_exist && { echo "should not exist yet"; return 1; }
  answers_set TEEUP_NAME x
  answers_exist || { echo "should exist"; return 1; }
  cleanup_test_env
}

test_answers_exist_needs_wizard_key() {
  setup
  answers_set TEEUP_PACKAGE_MANAGER homebrew
  answers_exist && { echo "should not exist without TEEUP_NAME"; return 1; }
  answers_set TEEUP_NAME x
  answers_exist || { echo "should exist once TEEUP_NAME is set"; return 1; }
  cleanup_test_env
}

test_dry_run_set_exports_without_writing() {
  setup
  # shellcheck disable=SC2034
  DRY_RUN=true
  answers_set TEEUP_DAILY no >/dev/null
  assert_equals "no" "$(answers_get TEEUP_DAILY yes)" "value visible in-process" || return 1
  [[ ! -e "$(answers_file)" ]] || { echo "answers file written in dry run"; return 1; }
  cleanup_test_env
}

test_set_rejects_a_key_with_regex_characters() {
  setup
  local rc=0 out
  out="$( (answers_set 'TEEUP_A.*' hi) 2>&1 )" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "key must look like TEEUP_NAME" || return 1
  cleanup_test_env
}

test_set_rejects_a_bare_prefix() {
  setup
  local rc=0
  ( answers_set 'TEEUP_' hi ) >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" || return 1
  cleanup_test_env
}

test_set_replaces_only_the_exact_key() {
  setup
  answers_set TEEUP_EMAIL "old@example.com"
  answers_set TEEUP_WORK_EMAIL "work@example.com"
  answers_set TEEUP_EMAIL "new@example.com"
  answers_load
  assert_equals "new@example.com" "$(answers_get TEEUP_EMAIL)" || return 1
  assert_equals "work@example.com" "$(answers_get TEEUP_WORK_EMAIL)" || return 1
  cleanup_test_env
}

test_set_preserves_a_final_line_with_no_trailing_newline() {
  setup
  answers_set TEEUP_EMAIL "ada@example.com"
  # Strip the trailing newline answers_set always writes, so the file's last
  # line has none, then rewrite via the key it belongs to.
  printf '%s' "$(cat "$(answers_file)")" > "$(answers_file)"
  [[ "$(tail -c 1 "$(answers_file)")" != "" ]] || { echo "test setup did not strip the trailing newline"; return 1; }
  answers_set TEEUP_NAME "Ada Lovelace"
  answers_load
  assert_equals "ada@example.com" "$(answers_get TEEUP_EMAIL)" || return 1
  assert_equals "Ada Lovelace" "$(answers_get TEEUP_NAME)" || return 1
  cleanup_test_env
}

test_set_rejects_a_value_with_a_newline() {
  setup
  local rc=0 out
  out="$( (answers_set TEEUP_NOTE "$(printf 'line1\nline2')") 2>&1 )" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "cannot contain a newline" || return 1
  [[ ! -e "$(answers_file)" ]] || { echo "answers file written for a rejected value"; return 1; }
  cleanup_test_env
}

test_identity_helpers_without_work_email() {
  setup
  answers_set TEEUP_EMAIL "ada@example.com"
  answers_set TEEUP_WORK_EMAIL ""
  answers_load
  assert_equals "personal" "$(identity_list)" || return 1
  assert_equals "ada@example.com" "$(identity_email personal)" || return 1
  assert_equals "ada@example.com" "$(identity_email work)" || return 1
  assert_equals "$HOME/.ssh/id_ed25519_personal" "$(identity_key personal)" || return 1
  cleanup_test_env
}

# The work identity lives in the machine file and nowhere else, so every test
# that needs one seeds it there. hostname is mocked to "testmac" by setup.
seed_machine_work() {
  printf '%s\n' "$@" > "$TEEUP_MACHINES_DIR/testmac.conf"
}

test_identity_helpers_with_a_work_machine_file() {
  setup
  answers_set TEEUP_EMAIL "ada@example.com"
  seed_machine_work 'TEEUP_WORK_EMAIL="ada@corp.example"'
  answers_load
  assert_equals "personal
work" "$(identity_list)" || return 1
  assert_equals "ada@corp.example" "$(identity_email work)" || return 1
  assert_equals "$HOME/.ssh/id_ed25519_work" "$(identity_key work)" || return 1
  cleanup_test_env
}

# B2: the wizard used to ask for a work email and wrote it into the answers
# file. It no longer asks, so a leftover answer on an upgraded machine would
# resurrect a work identity -- a second key, a second passphrase and a second
# upload -- from a question the tool no longer admits exists. The machine file
# is the only source there is.
test_a_work_email_in_the_answers_file_is_inert() {
  setup
  answers_set TEEUP_EMAIL "ada@example.com"
  answers_set TEEUP_WORK_EMAIL "ada@corp.example"
  answers_load
  assert_equals "personal" "$(identity_list)" || return 1
  answers_has_work && { echo "a stale answer still configures a work identity"; return 1; }
  assert_equals "ada@example.com" "$(identity_email work)" || return 1
  cleanup_test_env
}

test_a_work_gh_host_in_the_answers_file_is_inert() {
  setup
  answers_set TEEUP_WORK_GH_HOST "github.enterprise.example.com"
  answers_load
  assert_equals "github.com" "$(identity_gh_host work)" || return 1
  cleanup_test_env
}

test_answers_unset_removes_the_key() {
  setup
  answers_set TEEUP_EMAIL "ada@example.com"
  answers_set TEEUP_WORK_EMAIL "ada@corp.example"
  answers_unset TEEUP_WORK_EMAIL || { echo "answers_unset reported nothing to remove"; return 1; }
  assert_not_contains "$(cat "$(answers_file)")" "TEEUP_WORK_EMAIL" || return 1
  assert_contains "$(cat "$(answers_file)")" "TEEUP_EMAIL" "the other answers survive" || return 1
  assert_equals "" "${TEEUP_WORK_EMAIL:-}" "the value is dropped from this shell too" || return 1
  local rc=0
  answers_unset TEEUP_WORK_EMAIL || rc=$?
  assert_failure "$rc" "a second unset has nothing to remove" || return 1
  cleanup_test_env
}

test_answers_unset_writes_nothing_in_a_dry_run() {
  setup
  answers_set TEEUP_WORK_EMAIL "ada@corp.example"
  local out
  out="$(DRY_RUN=true answers_unset TEEUP_WORK_EMAIL)"
  assert_contains "$out" "[DRY-RUN] Would remove TEEUP_WORK_EMAIL" || return 1
  assert_contains "$(cat "$(answers_file)")" "TEEUP_WORK_EMAIL" "a dry run must not rewrite the answers file" || return 1
  cleanup_test_env
}

test_identity_gh_host_defaults_to_github_com() {
  setup
  answers_load
  assert_equals "github.com" "$(identity_gh_host personal)" || return 1
  assert_equals "github.com" "$(identity_gh_host work)" || return 1
  cleanup_test_env
}

test_identity_gh_host_honors_a_pinned_work_host() {
  setup
  seed_machine_work 'TEEUP_WORK_EMAIL="ada@corp.example"' 'TEEUP_WORK_GH_HOST="github.enterprise.example.com"'
  answers_load
  assert_equals "github.com" "$(identity_gh_host personal)" "personal never moves off github.com" || return 1
  assert_equals "github.enterprise.example.com" "$(identity_gh_host work)" || return 1
  cleanup_test_env
}

# An existing ~/.ssh/config is authority (2026-09-17 decision): a Host block
# already naming an IdentityFile wins over teeup's own id_ed25519_<identity>
# convention, so git, ssh and github all pick up the key the user already had
# instead of teeup generating (and uploading) a second one.
#
# What a config means is ssh's question, not teeup's: these tests write the
# shapes a real config actually takes -- trailing comments, relative paths,
# lowercase keywords, the `=` form, `Host *`, a global IdentityFile, a `Match`
# block, an `Include` -- and check teeup's answer against what `ssh -G` itself
# reports for the same file. $HOME is the throwaway one, and every ssh call is
# pinned to it with -F, so nothing here reads the developer's own config.

write_ssh_config() {
  mkdir -p "$TEST_HOME/.ssh"
  cat > "$TEST_HOME/.ssh/config"
}

# make_key <path...>: the key files a config names have to exist, or teeup
# falls back to its own convention rather than adopting a path that is not
# there.
make_key() {
  local f
  for f in "$@"; do
    mkdir -p "$(dirname "$f")"
    printf 'PRIVATE\n' > "$f"
  done
}

# ssh_says <host>: the first IdentityFile real ssh resolves from the test
# config, with a leading ~ expanded and a relative path resolved against
# ~/.ssh the way ssh does at connect time. The ground truth every assertion
# below is compared against.
ssh_says() { ssh_says_from "$TEST_HOME/.ssh/config" "$1"; }

# The same question with no config at all: ssh's built-in candidates.
ssh_says_without_a_config() { ssh_says_from /dev/null "$1"; }

ssh_says_from() {
  local raw
  raw="$(ssh -G -F "$1" "$2" 2>/dev/null |
    awk 'tolower($1) == "identityfile" { sub(/^[^ ]+ /, ""); print; exit }')"
  # shellcheck disable=SC2088  # the tilde is a literal token from ssh, not a path
  case "$raw" in
    "~/"*) printf '%s/%s\n' "$HOME" "${raw#\~/}" ;;
    /*) printf '%s\n' "$raw" ;;
    *) printf '%s/.ssh/%s\n' "$HOME" "$raw" ;;
  esac
}

test_identity_key_reuses_an_existing_ssh_config_entry() {
  setup
  make_key "$TEST_HOME/.ssh/id_rsa_legacy"
  write_ssh_config <<'SSHCONFIG'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_rsa_legacy
  IdentitiesOnly yes
SSHCONFIG
  assert_equals "$(ssh_says github.com)" "$(identity_key personal)" || return 1
  assert_equals "$TEST_HOME/.ssh/id_rsa_legacy" "$(identity_key personal)" || return 1
  cleanup_test_env
}

# B3, the damaging one: teeup used to take the comment as part of the path and
# generate, sign with and upload a key literally named "mykey # personal",
# while ssh went on looking for ~/.ssh/mykey.
test_identity_key_ignores_a_trailing_comment() {
  setup
  make_key "$TEST_HOME/.ssh/mykey"
  write_ssh_config <<'SSHCONFIG'
Host github.com
  IdentityFile ~/.ssh/mykey # personal
SSHCONFIG
  assert_equals "$(ssh_says github.com)" "$(identity_key personal)" || return 1
  assert_equals "$TEST_HOME/.ssh/mykey" "$(identity_key personal)" || return 1
  cleanup_test_env
}

# ssh resolves a relative IdentityFile against ~/.ssh, not the current
# directory.
test_identity_key_resolves_a_relative_path_against_dot_ssh() {
  setup
  make_key "$TEST_HOME/.ssh/mykey"
  write_ssh_config <<'SSHCONFIG'
Host github.com
  IdentityFile mykey
SSHCONFIG
  assert_equals "$(ssh_says github.com)" "$(identity_key personal)" || return 1
  assert_equals "$TEST_HOME/.ssh/mykey" "$(identity_key personal)" || return 1
  cleanup_test_env
}

test_identity_key_reads_lowercase_keywords() {
  setup
  make_key "$TEST_HOME/.ssh/mykey"
  write_ssh_config <<'SSHCONFIG'
host github.com
  identityfile ~/.ssh/mykey
SSHCONFIG
  assert_equals "$(ssh_says github.com)" "$(identity_key personal)" || return 1
  cleanup_test_env
}

test_identity_key_reads_the_equals_form() {
  setup
  make_key "$TEST_HOME/.ssh/mykey"
  write_ssh_config <<'SSHCONFIG'
Host=github.com
IdentityFile=~/.ssh/mykey
SSHCONFIG
  assert_equals "$(ssh_says github.com)" "$(identity_key personal)" || return 1
  cleanup_test_env
}

test_identity_key_honors_a_wildcard_host() {
  setup
  make_key "$TEST_HOME/.ssh/wildkey"
  write_ssh_config <<'SSHCONFIG'
Host *
  IdentityFile ~/.ssh/wildkey
SSHCONFIG
  assert_equals "$(ssh_says github.com)" "$(identity_key personal)" || return 1
  assert_equals "$TEST_HOME/.ssh/wildkey" "$(identity_key personal)" || return 1
  cleanup_test_env
}

# B4: the pattern used to be split unquoted and unprotected by `set -f`, so
# `Host *` globbed against the current directory and which key teeup adopted
# depended on where it was run from.
test_identity_key_does_not_depend_on_the_current_directory() {
  setup
  make_key "$TEST_HOME/.ssh/wildkey"
  write_ssh_config <<'SSHCONFIG'
Host *
  IdentityFile ~/.ssh/wildkey
SSHCONFIG
  mkdir -p "$TEST_HOME/globbait"
  : > "$TEST_HOME/globbait/github.com"
  local from_bait from_root
  from_bait="$(cd "$TEST_HOME/globbait" && identity_key personal)"
  from_root="$(cd / && identity_key personal)"
  assert_equals "$from_root" "$from_bait" "the adopted key must not depend on the cwd" || return 1
  assert_equals "$TEST_HOME/.ssh/wildkey" "$from_bait" || return 1
  cleanup_test_env
}

test_identity_key_honors_a_global_identityfile() {
  setup
  make_key "$TEST_HOME/.ssh/globalkey"
  write_ssh_config <<'SSHCONFIG'
IdentityFile ~/.ssh/globalkey

Host example.org
  User someone
SSHCONFIG
  assert_equals "$(ssh_says github.com)" "$(identity_key personal)" || return 1
  assert_equals "$TEST_HOME/.ssh/globalkey" "$(identity_key personal)" || return 1
  cleanup_test_env
}

# A Match block that follows the matching Host block used to donate its key:
# in_block was only ever reset by another Host line.
test_identity_key_ignores_a_match_block_for_another_host() {
  setup
  make_key "$TEST_HOME/.ssh/otherkey"
  write_ssh_config <<'SSHCONFIG'
Host github.com
  User git

Match host other
  IdentityFile ~/.ssh/otherkey
SSHCONFIG
  # ssh itself gives github.com nothing but its built-in candidates here, so
  # there is no key in this config to reuse.
  assert_equals "$(ssh_says_without_a_config github.com)" "$(ssh_says github.com)" || return 1
  assert_equals "$TEST_HOME/.ssh/id_ed25519_personal" "$(identity_key personal)" "a Match block for another host is not github.com's key" || return 1
  cleanup_test_env
}

test_identity_key_follows_an_include() {
  setup
  make_key "$TEST_HOME/.ssh/included_key"
  mkdir -p "$TEST_HOME/.ssh/conf.d"
  cat > "$TEST_HOME/.ssh/conf.d/github.conf" <<'INCLUDED'
Host github.com
  IdentityFile ~/.ssh/included_key
INCLUDED
  write_ssh_config <<'SSHCONFIG'
Include ~/.ssh/conf.d/*.conf

Host example.org
  User someone
SSHCONFIG
  assert_equals "$(ssh_says github.com)" "$(identity_key personal)" || return 1
  assert_equals "$TEST_HOME/.ssh/included_key" "$(identity_key personal)" || return 1
  cleanup_test_env
}

test_identity_key_falls_back_when_the_host_block_is_not_named() {
  setup
  make_key "$TEST_HOME/.ssh/id_ed25519_other"
  write_ssh_config <<'SSHCONFIG'
Host example.org
  IdentityFile ~/.ssh/id_ed25519_other
SSHCONFIG
  assert_equals "$TEST_HOME/.ssh/id_ed25519_personal" "$(identity_key personal)" || return 1
  cleanup_test_env
}

# ssh's own built-in candidates (~/.ssh/id_rsa, ~/.ssh/id_ed25519, ...) are not
# a choice the user made, so a config that names no key for the host leaves
# teeup on its own convention even when one of those files exists.
test_identity_key_does_not_adopt_ssh_s_built_in_defaults() {
  setup
  make_key "$TEST_HOME/.ssh/id_rsa" "$TEST_HOME/.ssh/id_ed25519"
  write_ssh_config <<'SSHCONFIG'
Host github.com
  User git
SSHCONFIG
  assert_equals "$TEST_HOME/.ssh/id_ed25519_personal" "$(identity_key personal)" || return 1
  cleanup_test_env
}

test_identity_key_falls_back_when_the_named_key_does_not_exist() {
  setup
  write_ssh_config <<'SSHCONFIG'
Host github.com
  IdentityFile ~/.ssh/not_there
SSHCONFIG
  assert_equals "$TEST_HOME/.ssh/id_ed25519_personal" "$(identity_key personal)" || return 1
  cleanup_test_env
}

# -e and -s both follow a symlink, so a dangling one is neither "there" nor
# "missing"; adopting it would hand ssh-keygen a path that writes through the
# link to wherever it points.
test_identity_key_falls_back_for_a_dangling_symlink() {
  setup
  mkdir -p "$TEST_HOME/.ssh"
  ln -s "$TEST_HOME/.ssh/gone" "$TEST_HOME/.ssh/dangling"
  write_ssh_config <<'SSHCONFIG'
Host github.com
  IdentityFile ~/.ssh/dangling
SSHCONFIG
  assert_equals "$TEST_HOME/.ssh/id_ed25519_personal" "$(identity_key personal)" || return 1
  cleanup_test_env
}

test_identity_key_falls_back_when_there_is_no_ssh_config() {
  setup
  [[ ! -e "$TEST_HOME/.ssh/config" ]] || { echo "test setup left a config behind"; return 1; }
  assert_equals "$TEST_HOME/.ssh/id_ed25519_personal" "$(identity_key personal)" || return 1
  cleanup_test_env
}

test_identity_key_reuses_the_work_alias_separately() {
  setup
  make_key "$TEST_HOME/.ssh/id_ed25519_personal" "$TEST_HOME/.ssh/id_ed25519_corp"
  write_ssh_config <<'SSHCONFIG'
Host github.com
  IdentityFile ~/.ssh/id_ed25519_personal

Host github.com-work
  IdentityFile ~/.ssh/id_ed25519_corp
SSHCONFIG
  assert_equals "$TEST_HOME/.ssh/id_ed25519_personal" "$(identity_key personal)" || return 1
  assert_equals "$(ssh_says github.com-work)" "$(identity_key work)" || return 1
  assert_equals "$TEST_HOME/.ssh/id_ed25519_corp" "$(identity_key work)" || return 1
  cleanup_test_env
}

# ssh is how a config is read, so without it teeup cannot know what the config
# means. It says so and stays on its own convention rather than guessing.
test_identity_key_warns_and_falls_back_without_ssh() {
  setup
  make_key "$TEST_HOME/.ssh/mykey"
  write_ssh_config <<'SSHCONFIG'
Host github.com
  IdentityFile ~/.ssh/mykey
SSHCONFIG
  export TEEUP_TEST_MISSING="ssh"
  local out key
  out="$( { key="$(identity_key personal)"; } 2>&1; printf '%s' "$key" )"
  assert_contains "$out" "ssh" || return 1
  assert_contains "$out" "$TEST_HOME/.ssh/id_ed25519_personal" || return 1
  unset TEEUP_TEST_MISSING
  cleanup_test_env
}

test_identity_key_warns_and_falls_back_when_ssh_cannot_read_the_config() {
  setup
  make_key "$TEST_HOME/.ssh/mykey"
  write_ssh_config <<'SSHCONFIG'
Host github.com
  ThisIsNotAnSshOption yes
  IdentityFile ~/.ssh/mykey
SSHCONFIG
  local out key
  out="$( { key="$(identity_key personal)"; } 2>&1; printf '%s' "$key" )"
  assert_contains "$out" "$TEST_HOME/.ssh/config" || return 1
  assert_contains "$out" "$TEST_HOME/.ssh/id_ed25519_personal" || return 1
  cleanup_test_env
}

echo "lib/answers.sh"
run_test "set then get" test_set_then_get
run_test "set replaces existing key" test_set_replaces_existing_key
run_test "get default when unset" test_get_default_when_unset
run_test "machine file wins" test_machine_file_wins
run_test "machine_get reads only the machine file" test_machine_get_reads_only_the_machine_file
run_test "values with spaces and quotes survive" test_values_with_spaces_and_quotes_survive
run_test "answers_exist" test_answers_exist
run_test "answers_exist needs wizard key" test_answers_exist_needs_wizard_key
run_test "dry run set exports without writing" test_dry_run_set_exports_without_writing
run_test "set rejects a key with regex characters" test_set_rejects_a_key_with_regex_characters
run_test "set rejects a bare prefix" test_set_rejects_a_bare_prefix
run_test "set replaces only the exact key" test_set_replaces_only_the_exact_key
run_test "set preserves a final line with no trailing newline" test_set_preserves_a_final_line_with_no_trailing_newline
run_test "identity helpers without work email" test_identity_helpers_without_work_email
run_test "identity helpers with a work machine file" test_identity_helpers_with_a_work_machine_file
run_test "a work email in the answers file is inert" test_a_work_email_in_the_answers_file_is_inert
run_test "a work gh host in the answers file is inert" test_a_work_gh_host_in_the_answers_file_is_inert
run_test "answers_unset removes the key" test_answers_unset_removes_the_key
run_test "answers_unset writes nothing in a dry run" test_answers_unset_writes_nothing_in_a_dry_run
run_test "identity_gh_host defaults to github.com" test_identity_gh_host_defaults_to_github_com
run_test "identity_gh_host honors a pinned work host" test_identity_gh_host_honors_a_pinned_work_host
run_test "identity_key reuses an existing ssh config entry" test_identity_key_reuses_an_existing_ssh_config_entry
run_test "identity_key ignores a trailing comment" test_identity_key_ignores_a_trailing_comment
run_test "identity_key resolves a relative path against ~/.ssh" test_identity_key_resolves_a_relative_path_against_dot_ssh
run_test "identity_key reads lowercase keywords" test_identity_key_reads_lowercase_keywords
run_test "identity_key reads the = form" test_identity_key_reads_the_equals_form
run_test "identity_key honors a wildcard host" test_identity_key_honors_a_wildcard_host
run_test "identity_key does not depend on the current directory" test_identity_key_does_not_depend_on_the_current_directory
run_test "identity_key honors a global IdentityFile" test_identity_key_honors_a_global_identityfile
run_test "identity_key ignores a Match block for another host" test_identity_key_ignores_a_match_block_for_another_host
run_test "identity_key follows an Include" test_identity_key_follows_an_include
run_test "identity_key falls back when the host block is not named" test_identity_key_falls_back_when_the_host_block_is_not_named
run_test "identity_key does not adopt ssh's built-in defaults" test_identity_key_does_not_adopt_ssh_s_built_in_defaults
run_test "identity_key falls back when the named key does not exist" test_identity_key_falls_back_when_the_named_key_does_not_exist
run_test "identity_key falls back for a dangling symlink" test_identity_key_falls_back_for_a_dangling_symlink
run_test "identity_key falls back when there is no ssh config" test_identity_key_falls_back_when_there_is_no_ssh_config
run_test "identity_key reuses the work alias separately" test_identity_key_reuses_the_work_alias_separately
run_test "identity_key warns and falls back without ssh" test_identity_key_warns_and_falls_back_without_ssh
run_test "identity_key warns and falls back when ssh cannot read the config" test_identity_key_warns_and_falls_back_when_ssh_cannot_read_the_config
print_summary
