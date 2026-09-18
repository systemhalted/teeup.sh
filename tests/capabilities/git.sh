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

# One identity, full stop (2026-09-17 decision): git never asks about work,
# so there is nothing here to seed beyond name and personal email.
seed_answers() {
  mkdir -p "$TEST_HOME/.config/teeup"
  {
    printf 'TEEUP_NAME="Ada Lovelace"\n'
    printf 'TEEUP_EMAIL="ada@example.com"\n'
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

test_configure_writes_the_one_identity() {
  setup
  seed_answers
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local identity
  identity="$(cat "$TEST_HOME/.config/git/identity")"
  assert_contains "$identity" 'email = "ada@example.com"' || return 1
  assert_contains "$identity" 'name = "Ada Lovelace"' || return 1
  assert_contains "$identity" "signingkey = \"$TEST_HOME/.ssh/id_ed25519_personal.pub\"" || return 1
  # No second identity file: work is not a git concept any more.
  [[ ! -e "$TEST_HOME/.config/git/identity-work" ]] || { echo "identity-work written; git no longer has a work identity"; return 1; }
  [[ ! -e "$TEST_HOME/.config/git/identity-personal" ]] || { echo "identity-personal written; the file is now just 'identity'"; return 1; }
  cleanup_test_env
}

# A work identity elsewhere on the machine (ssh, github) must not change what
# git writes: git always signs with the personal key and the personal email.
test_a_configured_work_identity_does_not_change_the_git_identity() {
  setup
  seed_answers
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR"
  printf 'TEEUP_WORK_EMAIL="ada@corp.example"\n' > "$TEEUP_MACHINES_DIR/testmac.conf"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local identity
  identity="$(cat "$TEST_HOME/.config/git/identity")"
  assert_contains "$identity" 'email = "ada@example.com"' || return 1
  assert_not_contains "$identity" "ada@corp.example" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_configure_without_answers_warns_and_writes_no_identity() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure git 2>&1)"
  assert_contains "$out" "skipping the git identity" || return 1
  [[ ! -e "$TEST_HOME/.config/git/identity" ]] || { echo "identity written without answers"; return 1; }
  cleanup_test_env
}

test_configure_ships_the_config_and_the_editor() {
  setup
  seed_answers
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local body
  body="$(cat "$TEST_HOME/.config/git/config")"
  # Identity by directory is gone (2026-09-17 decision): no includeIf blocks.
  assert_not_contains "$body" "includeIf" || return 1
  assert_contains "$body" "path = \"$TEST_HOME/.config/git/identity\"" || return 1
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
  seed_answers
  mkdir -p "$TEST_HOME/.ssh"
  printf 'fake-private-key\n' > "$TEST_HOME/.ssh/id_ed25519_personal"
  printf 'ssh-ed25519 AAAAFAKE ada@example.com\n' > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local generated
  generated="$(cat "$TEST_HOME/.config/git/teeup-generated")"
  assert_contains "$generated" "gpgsign = true" || return 1
  assert_contains "$generated" "pager = delta" || return 1
  cleanup_test_env
}

test_signing_stays_off_when_a_private_key_is_missing() {
  setup
  seed_answers
  mkdir -p "$TEST_HOME/.ssh"
  # Only the .pub survives (e.g. the private half was deleted, or never
  # existed): the old check looked at .pub alone and would have turned
  # signing on here, making every commit fail.
  printf 'ssh-ed25519 AAAAFAKE ada@example.com\n' > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local generated
  generated="$(cat "$TEST_HOME/.config/git/teeup-generated")"
  assert_contains "$generated" "gpgsign = false" || return 1
  cleanup_test_env
}

test_signing_turns_on_once_the_key_exists() {
  setup
  seed_answers
  mkdir -p "$TEST_HOME/.ssh"
  printf 'fake-private-key\n' > "$TEST_HOME/.ssh/id_ed25519_personal"
  printf 'ssh-ed25519 AAAAFAKE ada@example.com\n' > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local generated
  generated="$(cat "$TEST_HOME/.config/git/teeup-generated")"
  assert_contains "$generated" "gpgsign = true" || return 1
  cleanup_test_env
}

test_generated_include_is_read_after_the_defaults() {
  setup
  seed_answers
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  # git keeps the last value it reads, so the teeup-generated include must sit
  # below the [core] pager default it exists to override.
  local file="$TEST_HOME/.config/git/config" pager_line include_line
  pager_line="$(grep -n 'pager = delta' "$file" | head -1 | cut -d: -f1)"
  include_line="$(grep -n "path = \"$TEST_HOME/.config/git/teeup-generated\"" "$file" | head -1 | cut -d: -f1)"
  [[ -n "$pager_line" && -n "$include_line" && "$include_line" -gt "$pager_line" ]] ||
    { echo "teeup-generated (line $include_line) must be included after pager (line $pager_line)"; return 1; }
  cleanup_test_env
}

test_configure_prefers_emacsclient_when_present() {
  setup
  export TEEUP_TEST_MISSING="delta lazygit"
  mock_command emacsclient 0 ""
  seed_answers
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  assert_contains "$(cat "$TEST_HOME/.config/git/teeup-generated")" "editor = emacsclient -t" || return 1
  cleanup_test_env
}

test_configure_ships_the_lfs_filter_and_warns_about_gitconfig() {
  setup
  seed_answers
  printf '[user]\n\tname = Old\n' > "$TEST_HOME/.gitconfig"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure git 2>&1)"
  # The [filter "lfs"] block ships inside the copied config itself now, rather
  # than being written by a `git lfs install` that would run against the file
  # copy_config_once just installed on every configure.
  assert_not_contains "$(cat "$MOCK_LOG")" "git lfs install" || return 1
  local body
  body="$(cat "$TEST_HOME/.config/git/config")"
  assert_contains "$body" '[filter "lfs"]' || return 1
  assert_contains "$body" "smudge = git-lfs smudge -- %f" || return 1
  assert_contains "$body" "required = true" || return 1
  assert_contains "$out" "$TEST_HOME/.gitconfig exists and its keys win" || return 1
  assert_file_exists "$TEST_HOME/.gitconfig" || return 1
  cleanup_test_env
}

test_configure_warns_when_git_config_global_is_set() {
  setup
  seed_answers
  export GIT_CONFIG_GLOBAL="$TEST_HOME/somewhere/global-config"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure git 2>&1)"
  assert_contains "$out" "GIT_CONFIG_GLOBAL=$TEST_HOME/somewhere/global-config overrides" || return 1
  cleanup_test_env
}

test_configure_renders_include_paths_for_a_custom_xdg_config_home() {
  setup
  seed_answers
  export XDG_CONFIG_HOME="$TEST_HOME/xdg"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local cfg="$TEST_HOME/xdg/git/config"
  assert_file_exists "$cfg" || return 1
  local body
  body="$(cat "$cfg")"
  assert_contains "$body" "path = \"$TEST_HOME/xdg/git/identity\"" || return 1
  assert_contains "$body" "path = \"$TEST_HOME/xdg/git/teeup-generated\"" || return 1
  assert_contains "$body" "path = \"$TEST_HOME/xdg/git/local\"" || return 1
  # command -p bypasses the mocked `git` on PATH and finds the real binary,
  # which is what actually has to parse the rendered include path.
  local resolved
  resolved="$(command -p git config --file "$cfg" --get-all include.path | head -1)"
  assert_equals "$TEST_HOME/xdg/git/identity" "$resolved" || return 1
  cleanup_test_env
}

test_configure_renders_include_paths_with_xdg_config_home_metacharacters() {
  setup
  seed_answers
  # sed replacement metacharacters (&, |, \) in the directory name would
  # corrupt a `sed "s|~/.config/git|$git_dir|g"` render; the bash substitution
  # loop that replaced it has none of that.
  export XDG_CONFIG_HOME="$TEST_HOME/con&fig|x"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local cfg="$XDG_CONFIG_HOME/git/config"
  assert_file_exists "$cfg" || return 1
  local body
  body="$(cat "$cfg")"
  assert_contains "$body" "path = \"$XDG_CONFIG_HOME/git/identity\"" || return 1
  assert_contains "$body" "path = \"$XDG_CONFIG_HOME/git/teeup-generated\"" || return 1
  assert_contains "$body" "path = \"$XDG_CONFIG_HOME/git/local\"" || return 1
  cleanup_test_env
}

test_configure_quotes_include_paths_with_hash_and_semicolon_in_xdg_config_home() {
  setup
  # '#' and ';' both start a comment in git's config parser outside quotes;
  # an unquoted `path = ~/.config/git/...` render would silently truncate
  # everything from the '#' on, dropping the include path and leaving git
  # with no identity at all. XDG_CONFIG_HOME is set before seeding the
  # answers file (unlike seed_answers, which always writes under the default
  # $TEST_HOME/.config) so the identity file actually gets written under this
  # same custom directory, and can be proven to load.
  export XDG_CONFIG_HOME="$TEST_HOME/con#fig;x"
  mkdir -p "$XDG_CONFIG_HOME/teeup"
  {
    printf 'TEEUP_NAME="Ada Lovelace"\n'
    printf 'TEEUP_EMAIL="ada@example.com"\n'
  } > "$XDG_CONFIG_HOME/teeup/answers"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local cfg="$XDG_CONFIG_HOME/git/config"
  assert_file_exists "$cfg" || return 1
  local body
  body="$(cat "$cfg")"
  assert_contains "$body" "path = \"$XDG_CONFIG_HOME/git/identity\"" || return 1
  assert_contains "$body" "path = \"$XDG_CONFIG_HOME/git/teeup-generated\"" || return 1
  assert_contains "$body" "path = \"$XDG_CONFIG_HOME/git/local\"" || return 1
  # command -p bypasses the mocked `git` on PATH and finds the real binary,
  # which is what actually has to parse the quoted, hash-containing path.
  local includes
  includes="$(command -p git config --file "$cfg" --get-all include.path)"
  assert_contains "$includes" "$XDG_CONFIG_HOME/git/identity" || return 1
  assert_contains "$includes" "$XDG_CONFIG_HOME/git/teeup-generated" || return 1
  assert_contains "$includes" "$XDG_CONFIG_HOME/git/local" || return 1
  # Prove the identity actually loads, not just that the path string is
  # intact.
  local loaded_email
  loaded_email="$(GIT_CONFIG_GLOBAL="$cfg" command -p git config --get user.email)"
  assert_equals "ada@example.com" "$loaded_email" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  seed_answers
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure git 2>&1)"
  assert_contains "$out" "Already current: $TEST_HOME/.config/git/identity" || return 1
  assert_contains "$out" "Already installed: $TEST_HOME/.config/git/config" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  seed_answers
  DRY_RUN=true "$TEEUP" configure git >/dev/null 2>&1
  [[ ! -e "$TEST_HOME/.config/git/config" ]] || { echo "written in dry run"; return 1; }
  cleanup_test_env
}

# F4: configure renders the shipped config to a temp file before copying it
# into place, so the dry-run message used to name that temp file instead of
# the shipped source the user could actually make sense of.
test_configure_dry_run_names_the_shipped_source_not_a_temp_file() {
  setup
  seed_answers
  local out
  out="$(DRY_RUN=true "$TEEUP" configure git 2>&1)"
  assert_contains "$out" "Would install $TEST_HOME/.config/git/config from $TEEUP_PATH/capabilities/git/config/git/config" || return 1
  cleanup_test_env
}

test_configure_dry_run_names_the_shipped_source_for_a_foreign_config() {
  setup
  seed_answers
  mkdir -p "$TEST_HOME/.config/git"
  printf '[user]\n\tname = Foreign\n' > "$TEST_HOME/.config/git/config"
  local out
  out="$(DRY_RUN=true "$TEEUP" configure git 2>&1)"
  assert_contains "$out" "Would back up foreign $TEST_HOME/.config/git/config and install $TEEUP_PATH/capabilities/git/config/git/config" || return 1
  cleanup_test_env
}

test_configure_quotes_special_characters_in_the_name() {
  setup
  local name='Jane "J" Smith #3 \ x' escaped
  # Mirror answers_set's own escaping (lib/answers.sh) so the answers file
  # sources cleanly under bash: without it, this value's quote/backslash
  # would break the source of the answers file itself, before configure even
  # runs.
  escaped="$(printf '%s' "$name" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\$/g' -e 's/`/\\`/g')"
  mkdir -p "$TEST_HOME/.config/teeup"
  {
    printf 'TEEUP_NAME="%s"\n' "$escaped"
    printf 'TEEUP_EMAIL="ada@example.com"\n'
  } > "$TEST_HOME/.config/teeup/answers"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  # command -p bypasses the mocked `git` on PATH (see setup) and finds the
  # real binary, which is what actually has to parse the quoted value.
  local resolved
  resolved="$(command -p git config --file "$TEST_HOME/.config/git/identity" user.name)"
  assert_equals "$name" "$resolved" || return 1
  cleanup_test_env
}

# B1: a machine that ran the old two-identity model keeps its ~/.config/git/config
# until something repairs it. copy_config_once sees the file matching the sha it
# recorded at install time and reports "Already installed", so the shipped
# includeIf blocks and the identity-personal/identity-work files survive every
# upgrade and ~/Work still commits as the work address. `teeup configure git`
# repairs that shape in place.

# seed_old_model: the tree an upgraded machine actually has -- the OLD shipped
# config (rendered, i.e. the include paths already quoted and absolute), both
# per-identity files, and a stock record holding the installed file's own sha so
# copy_config_once still calls it pristine.
seed_old_model() {
  local dir="$TEST_HOME/.config/git" work_block="${1:-shipped}"
  mkdir -p "$dir"
  {
    printf '# ~/.config/git/config - installed once by teeup; this copy is yours to edit.\n'
    printf '# Generated pieces (editor, pager, signing, the two identities) live in\n'
    printf '# separate included files so teeup can regenerate them without touching your\n'
    printf '# edits here. Include order is load-bearing: git keeps the LAST value it\n'
    printf '# reads, so teeup-generated is included below the defaults it has to be able\n'
    printf '# to override, and ~/.config/git/local last of all.\n'
    printf '\n'
    printf '[include]\n'
    printf '\t# Default identity; the includeIf blocks at the bottom override it per root.\n'
    printf '\tpath = "%s/identity-personal"\n' "$dir"
    printf '\n'
    printf '[user]\n'
    printf '\tuseConfigOnly = true     # never guess an identity from the hostname\n'
    printf '\n'
    printf '[include]\n'
    printf '\tpath = "%s/teeup-generated"\n' "$dir"
    printf '\n'
    printf '# Identity by directory (spec section 8). Both identities live on every\n'
    printf '# machine; where the repository sits decides which one applies.\n'
    printf '[includeIf "gitdir:~/Personal/"]\n'
    printf '\tpath = "%s/identity-personal"\n' "$dir"
    printf '[includeIf "gitdir:~/Work/"]\n'
    if [[ "$work_block" == "edited" ]]; then
      printf '\tpath = "%s/identity-mine"\n' "$dir"
    else
      printf '\tpath = "%s/identity-work"\n' "$dir"
    fi
    printf '\n'
    printf '# Untracked machine-local overrides, included last so they win over everything\n'
    printf '# above. Create it yourself; teeup never writes it.\n'
    printf '[include]\n'
    printf '\tpath = "%s/local"\n' "$dir"
  } > "$dir/config"
  printf '[user]\n\tname = "Ada Lovelace"\n\temail = "ada@example.com"\n' > "$dir/identity-personal"
  printf '[user]\n\tname = "Ada Lovelace"\n\temail = "ada@corp.example"\n' > "$dir/identity-work"
  mkdir -p "$TEST_HOME/.local/state/teeup/stock"
  { shasum -a 256 < "$dir/config" 2>/dev/null || sha256sum < "$dir/config"; } |
    cut -d ' ' -f 1 > "$TEST_HOME/.local/state/teeup/stock/.config__git__config"
}

# resolved_email <repo> -> the user.email real git resolves for a repository,
# reading the migrated config as the global one so its includes (and any
# surviving includeIf) apply exactly as they would on the user's machine.
resolved_email() {
  local repo="$1"
  mkdir -p "$repo"
  GIT_CONFIG_GLOBAL="$TEST_HOME/.config/git/config" \
    command -p git -C "$repo" --git-dir="$repo/.git" config --get user.email 2>/dev/null || true
}

test_configure_repairs_an_old_two_identity_config() {
  setup
  seed_answers
  seed_old_model
  command -p git init -q "$TEST_HOME/Work/repo" >/dev/null 2>&1
  assert_equals "ada@corp.example" "$(resolved_email "$TEST_HOME/Work/repo")" "test setup must reproduce the old model" || return 1
  local out cfg
  out="$(DRY_RUN=false "$TEEUP" configure git 2>&1)"
  cfg="$(cat "$TEST_HOME/.config/git/config")"
  assert_not_contains "$cfg" 'includeIf "gitdir:~/Work/"' || return 1
  assert_not_contains "$cfg" 'includeIf "gitdir:~/Personal/"' || return 1
  assert_not_contains "$cfg" "identity-personal" || return 1
  assert_not_contains "$cfg" "identity-work" || return 1
  assert_contains "$cfg" "path = \"$TEST_HOME/.config/git/identity\"" || return 1
  assert_contains "$cfg" 'path = "'"$TEST_HOME"'/.config/git/local"' "unrelated shipped lines survive" || return 1
  assert_contains "$out" "one identity" || return 1
  assert_not_contains "$cfg" "the two identities" "the header paragraph teeup shipped is updated too" || return 1
  assert_contains "$cfg" "signing, the identity) live in separate" || return 1
  [[ ! -e "$TEST_HOME/.config/git/identity-personal" ]] || { echo "identity-personal left in place"; return 1; }
  [[ ! -e "$TEST_HOME/.config/git/identity-work" ]] || { echo "identity-work left in place"; return 1; }
  assert_equals "ada@example.com" "$(resolved_email "$TEST_HOME/Work/repo")" "a repository under the Work root must resolve to the one identity" || return 1
  cleanup_test_env
}

test_configure_leaves_a_hand_edited_old_config_alone() {
  setup
  seed_answers
  seed_old_model edited
  local before out after
  before="$(cat "$TEST_HOME/.config/git/config")"
  out="$(DRY_RUN=false "$TEEUP" configure git 2>&1)"
  after="$(cat "$TEST_HOME/.config/git/config")"
  assert_equals "$before" "$after" "a config whose blocks teeup did not ship must not be edited" || return 1
  assert_contains "$out" 'includeIf "gitdir:~/Work/"' "the warning names the lines" || return 1
  assert_file_exists "$TEST_HOME/.config/git/identity-personal" || return 1
  cleanup_test_env
}

test_configure_repairs_nothing_on_a_fresh_machine() {
  setup
  seed_answers
  local out
  out="$(DRY_RUN=false "$TEEUP" configure git 2>&1)"
  assert_not_contains "$out" "two-identity" || return 1
  assert_not_contains "$out" "identity-personal" || return 1
  cleanup_test_env
}

test_configure_twice_after_the_repair_changes_nothing() {
  setup
  seed_answers
  seed_old_model
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local first out second
  first="$(cat "$TEST_HOME/.config/git/config")"
  out="$(DRY_RUN=false "$TEEUP" configure git 2>&1)"
  second="$(cat "$TEST_HOME/.config/git/config")"
  assert_equals "$first" "$second" "the second run must not touch the repaired config" || return 1
  assert_contains "$out" "Already installed: $TEST_HOME/.config/git/config" || return 1
  assert_not_contains "$out" "two-identity" || return 1
  cleanup_test_env
}

test_configure_dry_run_repairs_nothing() {
  setup
  seed_answers
  seed_old_model
  local before out after
  before="$(cat "$TEST_HOME/.config/git/config")"
  out="$(DRY_RUN=true "$TEEUP" configure git 2>&1)"
  after="$(cat "$TEST_HOME/.config/git/config")"
  assert_equals "$before" "$after" "a dry run must not repair the config" || return 1
  assert_contains "$out" "[DRY-RUN]" || return 1
  assert_file_exists "$TEST_HOME/.config/git/identity-personal" || return 1
  cleanup_test_env
}

# M3: the identity line is a claim about a mutation, so it belongs to a run
# that made one. A second configure writes nothing and says "Already current",
# and used to print the success line under it anyway.
test_configure_twice_does_not_claim_the_identity_again() {
  setup
  seed_answers
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure git 2>&1)"
  assert_contains "$out" "Already current: $TEST_HOME/.config/git/identity" || return 1
  assert_not_contains "$out" "git identity: ada@example.com" || return 1
  cleanup_test_env
}

test_configure_still_reports_the_identity_it_wrote() {
  setup
  seed_answers
  local out
  out="$(DRY_RUN=false "$TEEUP" configure git 2>&1)"
  assert_contains "$out" "git identity: ada@example.com" || return 1
  cleanup_test_env
}

echo "capabilities/git"
run_test "install gets git, delta, lfs and lazygit" test_install_gets_git_delta_lfs_and_lazygit
run_test "configure writes the one identity" test_configure_writes_the_one_identity
run_test "a configured work identity does not change the git identity" test_a_configured_work_identity_does_not_change_the_git_identity
run_test "configure without answers warns and writes no identity" test_configure_without_answers_warns_and_writes_no_identity
run_test "configure ships the config and the editor" test_configure_ships_the_config_and_the_editor
run_test "signing and delta are enabled once they exist" test_signing_and_delta_are_enabled_once_they_exist
run_test "signing stays off when a private key is missing" test_signing_stays_off_when_a_private_key_is_missing
run_test "signing turns on once the key exists" test_signing_turns_on_once_the_key_exists
run_test "generated include is read after the defaults" test_generated_include_is_read_after_the_defaults
run_test "configure renders include paths for a custom XDG_CONFIG_HOME" test_configure_renders_include_paths_for_a_custom_xdg_config_home
run_test "configure renders include paths with XDG_CONFIG_HOME metacharacters" test_configure_renders_include_paths_with_xdg_config_home_metacharacters
run_test "configure quotes include paths with hash and semicolon in XDG_CONFIG_HOME" test_configure_quotes_include_paths_with_hash_and_semicolon_in_xdg_config_home
run_test "configure prefers emacsclient when present" test_configure_prefers_emacsclient_when_present
run_test "configure ships the lfs filter and warns about gitconfig" test_configure_ships_the_lfs_filter_and_warns_about_gitconfig
run_test "configure warns when GIT_CONFIG_GLOBAL is set" test_configure_warns_when_git_config_global_is_set
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure twice does not claim the identity again" test_configure_twice_does_not_claim_the_identity_again
run_test "configure still reports the identity it wrote" test_configure_still_reports_the_identity_it_wrote
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "configure dry run names the shipped source, not a temp file" test_configure_dry_run_names_the_shipped_source_not_a_temp_file
run_test "configure dry run names the shipped source for a foreign config" test_configure_dry_run_names_the_shipped_source_for_a_foreign_config
run_test "configure quotes special characters in the name" test_configure_quotes_special_characters_in_the_name
run_test "configure repairs an old two-identity config" test_configure_repairs_an_old_two_identity_config
run_test "configure leaves a hand-edited old config alone" test_configure_leaves_a_hand_edited_old_config_alone
run_test "configure repairs nothing on a fresh machine" test_configure_repairs_nothing_on_a_fresh_machine
run_test "configure twice after the repair changes nothing" test_configure_twice_after_the_repair_changes_nothing
run_test "configure dry run repairs nothing" test_configure_dry_run_repairs_nothing
print_summary
