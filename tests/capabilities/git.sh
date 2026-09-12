#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  mock_command git 0 ""
  mock_command git-lfs 0 ""
  export TEEUP_TEST_MISSING="delta lazygit emacsclient"
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

test_install_gets_git_delta_lfs_and_lazygit() {
  setup
  # setup mocks git-lfs onto PATH for the configure tests, and pkg_install
  # short-circuits on a command that is already there. Hide it for this test
  # only, or the brew assertion below can never fire.
  export TEEUP_TEST_MISSING="delta lazygit emacsclient git-lfs"
  local out
  out="$(DRY_RUN=true "$TEEUP" install git 2>&1)"
  assert_contains "$out" "Would execute: brew install git" || return 1
  assert_contains "$out" "Would execute: brew install git-delta" || return 1
  assert_contains "$out" "Would execute: brew install git-lfs" || return 1
  assert_contains "$out" "Would execute: brew install lazygit" || return 1
  cleanup_test_env
}

test_configure_writes_both_identities() {
  setup
  seed_answers "ada@corp.example"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local personal work
  personal="$(cat "$TEST_HOME/.config/git/identity-personal")"
  work="$(cat "$TEST_HOME/.config/git/identity-work")"
  assert_contains "$personal" "email = ada@example.com" || return 1
  assert_contains "$personal" "name = Ada Lovelace" || return 1
  assert_contains "$personal" "signingkey = $TEST_HOME/.ssh/id_ed25519_personal.pub" || return 1
  assert_contains "$work" "email = ada@corp.example" || return 1
  assert_contains "$work" "signingkey = $TEST_HOME/.ssh/id_ed25519_work.pub" || return 1
  cleanup_test_env
}

test_work_identity_falls_back_to_the_personal_email() {
  setup
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  assert_contains "$(cat "$TEST_HOME/.config/git/identity-work")" "email = ada@example.com" || return 1
  cleanup_test_env
}

test_work_identity_falls_back_to_the_personal_signingkey() {
  setup
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local work
  work="$(cat "$TEST_HOME/.config/git/identity-work")"
  assert_contains "$work" "signingkey = $TEST_HOME/.ssh/id_ed25519_personal.pub" || return 1
  if [[ "$work" == *"id_ed25519_work"* ]]; then
    echo "identity-work should not reference the never-created work key"
    return 1
  fi
  cleanup_test_env
}

test_configure_without_answers_warns_and_writes_no_identity() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure git 2>&1)"
  assert_contains "$out" "skipping the git identities" || return 1
  [[ ! -e "$TEST_HOME/.config/git/identity-personal" ]] || { echo "identity written without answers"; return 1; }
  cleanup_test_env
}

test_configure_ships_the_config_and_the_editor() {
  setup
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local body
  body="$(cat "$TEST_HOME/.config/git/config")"
  assert_contains "$body" 'includeIf "gitdir:~/Work/"' || return 1
  assert_contains "$body" 'includeIf "gitdir:~/Personal/"' || return 1
  assert_contains "$body" "pager = delta" || return 1
  assert_contains "$body" "format = ssh" || return 1
  assert_contains "$body" "defaultBranch = main" || return 1
  local generated
  generated="$(cat "$TEST_HOME/.config/git/teeup-generated")"
  assert_contains "$generated" "editor = vim" || return 1
  # delta is hidden by TEEUP_TEST_MISSING and no key exists yet, so the
  # generated include has to switch both dangerous defaults back off.
  assert_contains "$generated" "pager = less" || return 1
  assert_contains "$generated" "diffFilter = cat" || return 1
  assert_contains "$generated" "gpgsign = false" || return 1
  cleanup_test_env
}

test_signing_and_delta_are_enabled_once_they_exist() {
  setup
  export TEEUP_TEST_MISSING="lazygit emacsclient"
  mock_command delta 0 ""
  seed_answers ""
  mkdir -p "$TEST_HOME/.ssh"
  printf 'ssh-ed25519 AAAAFAKE ada@example.com\n' > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local generated
  generated="$(cat "$TEST_HOME/.config/git/teeup-generated")"
  assert_contains "$generated" "gpgsign = true" || return 1
  assert_contains "$generated" "pager = delta" || return 1
  cleanup_test_env
}

test_signing_stays_off_with_a_work_email_and_no_work_key() {
  setup
  seed_answers "ada@corp.example"
  mkdir -p "$TEST_HOME/.ssh"
  printf 'ssh-ed25519 AAAAFAKE ada@example.com\n' > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  # No id_ed25519_work.pub: the work identity file still points at it (see
  # identity-work in the test above), so signing must stay off machine-wide
  # rather than fail every commit under ~/Work.
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local generated
  generated="$(cat "$TEST_HOME/.config/git/teeup-generated")"
  assert_contains "$generated" "gpgsign = false" || return 1
  cleanup_test_env
}

test_signing_turns_on_once_both_identity_keys_exist() {
  setup
  seed_answers "ada@corp.example"
  mkdir -p "$TEST_HOME/.ssh"
  printf 'ssh-ed25519 AAAAFAKE ada@example.com\n' > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  printf 'ssh-ed25519 AAAAWORK ada@corp.example\n' > "$TEST_HOME/.ssh/id_ed25519_work.pub"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local generated
  generated="$(cat "$TEST_HOME/.config/git/teeup-generated")"
  assert_contains "$generated" "gpgsign = true" || return 1
  cleanup_test_env
}

test_generated_include_is_read_after_the_defaults() {
  setup
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  # git keeps the last value it reads, so the teeup-generated include must sit
  # below the [core] pager default it exists to override.
  local file="$TEST_HOME/.config/git/config" pager_line include_line
  pager_line="$(grep -n 'pager = delta' "$file" | head -1 | cut -d: -f1)"
  include_line="$(grep -n "path = $TEST_HOME/.config/git/teeup-generated" "$file" | head -1 | cut -d: -f1)"
  [[ -n "$pager_line" && -n "$include_line" && "$include_line" -gt "$pager_line" ]] ||
    { echo "teeup-generated (line $include_line) must be included after pager (line $pager_line)"; return 1; }
  cleanup_test_env
}

test_configure_prefers_emacsclient_when_present() {
  setup
  export TEEUP_TEST_MISSING="delta lazygit"
  mock_command emacsclient 0 ""
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  assert_contains "$(cat "$TEST_HOME/.config/git/teeup-generated")" "editor = emacsclient -t" || return 1
  cleanup_test_env
}

test_configure_runs_git_lfs_install_and_warns_about_gitconfig() {
  setup
  seed_answers ""
  printf '[user]\n\tname = Old\n' > "$TEST_HOME/.gitconfig"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure git 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "git lfs install --skip-repo" || return 1
  assert_contains "$out" "$TEST_HOME/.gitconfig exists and its keys win" || return 1
  assert_file_exists "$TEST_HOME/.gitconfig" || return 1
  cleanup_test_env
}

test_configure_renders_include_paths_for_a_custom_xdg_config_home() {
  setup
  seed_answers ""
  export XDG_CONFIG_HOME="$TEST_HOME/xdg"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local cfg="$TEST_HOME/xdg/git/config"
  assert_file_exists "$cfg" || return 1
  local body
  body="$(cat "$cfg")"
  assert_contains "$body" "path = $TEST_HOME/xdg/git/identity-personal" || return 1
  assert_contains "$body" "path = $TEST_HOME/xdg/git/teeup-generated" || return 1
  assert_contains "$body" "path = $TEST_HOME/xdg/git/local" || return 1
  # command -p bypasses the mocked `git` on PATH and finds the real binary,
  # which is what actually has to parse the rendered includeIf path.
  local resolved
  resolved="$(command -p git config --file "$cfg" --get-all 'includeIf.gitdir:~/Work/.path')"
  assert_equals "$TEST_HOME/xdg/git/identity-work" "$resolved" || return 1
  cleanup_test_env
}

test_configure_renders_include_paths_with_xdg_config_home_metacharacters() {
  setup
  seed_answers ""
  # sed replacement metacharacters (&, |, \) in the directory name would
  # corrupt a `sed "s|~/.config/git|$git_dir|g"` render; the bash substitution
  # loop that replaced it has none of that.
  export XDG_CONFIG_HOME="$TEST_HOME/con&fig|x"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local cfg="$XDG_CONFIG_HOME/git/config"
  assert_file_exists "$cfg" || return 1
  local body
  body="$(cat "$cfg")"
  assert_contains "$body" "path = $XDG_CONFIG_HOME/git/identity-personal" || return 1
  assert_contains "$body" "path = $XDG_CONFIG_HOME/git/teeup-generated" || return 1
  assert_contains "$body" "path = $XDG_CONFIG_HOME/git/local" || return 1
  local resolved
  resolved="$(command -p git config --file "$cfg" --get-all 'includeIf.gitdir:~/Work/.path')"
  assert_equals "$XDG_CONFIG_HOME/git/identity-work" "$resolved" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure git 2>&1)"
  assert_contains "$out" "Already current: $TEST_HOME/.config/git/identity-personal" || return 1
  assert_contains "$out" "Already installed: $TEST_HOME/.config/git/config" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  seed_answers ""
  DRY_RUN=true "$TEEUP" configure git >/dev/null 2>&1
  [[ ! -e "$TEST_HOME/.config/git/config" ]] || { echo "written in dry run"; return 1; }
  cleanup_test_env
}

echo "capabilities/git"
run_test "install gets git, delta, lfs and lazygit" test_install_gets_git_delta_lfs_and_lazygit
run_test "configure writes both identities" test_configure_writes_both_identities
run_test "work identity falls back to the personal email" test_work_identity_falls_back_to_the_personal_email
run_test "work identity falls back to the personal signingkey" test_work_identity_falls_back_to_the_personal_signingkey
run_test "configure without answers warns and writes no identity" test_configure_without_answers_warns_and_writes_no_identity
run_test "configure ships the config and the editor" test_configure_ships_the_config_and_the_editor
run_test "signing and delta are enabled once they exist" test_signing_and_delta_are_enabled_once_they_exist
run_test "signing stays off with a work email and no work key" test_signing_stays_off_with_a_work_email_and_no_work_key
run_test "signing turns on once both identity keys exist" test_signing_turns_on_once_both_identity_keys_exist
run_test "generated include is read after the defaults" test_generated_include_is_read_after_the_defaults
run_test "configure renders include paths for a custom XDG_CONFIG_HOME" test_configure_renders_include_paths_for_a_custom_xdg_config_home
run_test "configure renders include paths with XDG_CONFIG_HOME metacharacters" test_configure_renders_include_paths_with_xdg_config_home_metacharacters
run_test "configure prefers emacsclient when present" test_configure_prefers_emacsclient_when_present
run_test "configure runs git lfs install and warns about gitconfig" test_configure_runs_git_lfs_install_and_warns_about_gitconfig
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
print_summary
