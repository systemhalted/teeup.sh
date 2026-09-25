#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  # `--version` answers for real: an exit-0, silent brew reads as "cannot
  # answer" (lib/doctor.sh's doctor_backend_can_answer), which used to switch
  # off every package check below in silence (NI2).
  mock_command_script brew <<'EOF2'
case "$1" in --version) echo "Homebrew 4.3.9" ;; esac
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  # `git config` is forwarded to the real git; everything else stays mocked.
  # The doctor reads the config through git itself now -- a line-oriented
  # search is not section aware and does not follow [include] -- so checking
  # it against a mock that answers nothing would prove nothing. Same reasoning
  # as the ssh suite forwarding `ssh-keygen -l` to the real binary: a parser
  # check only means something against a real parser. HOME is $TEST_HOME, so
  # a write has nowhere to go but the throwaway tree.
  mock_command_script git <<'EOF_GIT'
case "${1:-}" in
  config) command -p git "$@"; exit $? ;;
esac
exit 0
EOF_GIT
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
    if [[ "$work_block" == "renamed" ]]; then
      # The user renamed the root but kept teeup's identity files: nothing here
      # is a block teeup shipped, so the repair has to leave the file alone.
      printf '[includeIf "gitdir:~/Job/"]\n'
      printf '\tpath = "%s/identity-work"\n' "$dir"
    else
      printf '[includeIf "gitdir:~/Personal/"]\n'
      printf '\tpath = "%s/identity-personal"\n' "$dir"
      printf '[includeIf "gitdir:~/Work/"]\n'
      if [[ "$work_block" == "edited" ]]; then
        printf '\tpath = "%s/identity-mine"\n' "$dir"
      else
        printf '\tpath = "%s/identity-work"\n' "$dir"
      fi
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

# N-b: the warning is what the user acts on, so it has to name what is actually
# in their file. It used to list from the transformed copy, which has already
# rewritten the top-level include, and to match only teeup's own two roots, so
# a renamed root was never shown at all.
test_the_leftover_warning_names_every_old_model_line() {
  setup
  seed_answers
  seed_old_model renamed
  local before out after dir="$TEST_HOME/.config/git"
  before="$(cat "$dir/config")"
  out="$(DRY_RUN=false "$TEEUP" configure git 2>&1)"
  after="$(cat "$dir/config")"
  assert_equals "$before" "$after" "a config teeup did not ship is not edited" || return 1
  assert_contains "$out" 'includeIf "gitdir:~/Job/"' "a renamed root is named" || return 1
  assert_contains "$out" "path = \"$dir/identity-work\"" || return 1
  assert_contains "$out" "path = \"$dir/identity-personal\"" "the top-level include is named too" || return 1
  assert_file_exists "$dir/identity-personal" || return 1
  cleanup_test_env
}

# N-c: a ~/.config/git/config symlinked into a dotfiles repo. A symlink is
# never a file teeup installed, so the repair treats it the way copy_config_once
# and the ssh key path treat one -- back up the link, write a real file -- and
# says so, naming the file the link pointed at, which still has the old blocks.
link_config_into_dotfiles() {
  mkdir -p "$TEST_HOME/dotfiles/git"
  mv "$TEST_HOME/.config/git/config" "$TEST_HOME/dotfiles/git/config"
  ln -s "$TEST_HOME/dotfiles/git/config" "$TEST_HOME/.config/git/config"
}

test_configure_replaces_a_symlinked_config_and_says_so() {
  setup
  seed_answers
  seed_old_model
  link_config_into_dotfiles
  local dotfiles="$TEST_HOME/dotfiles/git/config" before out
  before="$(cat "$dotfiles")"
  out="$(DRY_RUN=false "$TEEUP" configure git 2>&1)"
  [[ ! -L "$TEST_HOME/.config/git/config" ]] || { echo "the repaired config is still a symlink"; return 1; }
  assert_not_contains "$(cat "$TEST_HOME/.config/git/config")" "includeIf" || return 1
  assert_equals "$before" "$(cat "$dotfiles")" "the file the link pointed at is not rewritten" || return 1
  assert_contains "$out" "$dotfiles" "the message names what the link pointed at" || return 1
  assert_contains "$out" "symlink" || return 1
  local backups
  backups="$(find "$TEST_HOME/.config/git" -name 'config.teeup_backup_*' -type l | wc -l | tr -d ' ')"
  assert_equals "1" "$backups" "the link itself is backed up" || return 1
  cleanup_test_env
}

test_configure_dry_run_leaves_a_symlinked_config_alone() {
  setup
  seed_answers
  seed_old_model
  link_config_into_dotfiles
  local out
  out="$(DRY_RUN=true "$TEEUP" configure git 2>&1)"
  [[ -L "$TEST_HOME/.config/git/config" ]] || { echo "a dry run replaced the symlink"; return 1; }
  assert_contains "$out" "symlink" || return 1
  cleanup_test_env
}

# A configured git tree with its one key pair on disk, which is the state in
# which commit signing is supposed to be on. Git has one identity, full stop,
# so there is no work key to seed here -- that only ever exists when
# machines/<hostname>.conf configures one, and git never reads it.
configure_git_with_keys() {
  seed_answers
  mkdir -p "$TEST_HOME/.ssh"
  printf 'PRIVATE\n' > "$TEST_HOME/.ssh/id_ed25519_personal"
  printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAKEKEYpersonal personal\n' > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
}

test_doctor_passes_on_a_configured_tree() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  printf '%s\n' "ada@example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAKEKEYpersonal" \
    > "$TEST_HOME/.config/git/allowed_signers"
  printf '[gpg "ssh"]\n\tallowedSignersFile = "%s"\n' "$TEST_HOME/.config/git/allowed_signers" \
    > "$TEST_HOME/.config/git/local"
  local rc=0 out
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "ada@example.com" || return 1
  assert_contains "$out" "Identity: " "the identity line names the name as well, since git needs both" || return 1
  assert_contains "$out" "Commit signing is on" || return 1
  cleanup_test_env
}

test_doctor_reports_an_unconfigured_tree() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "git has never been configured here" || return 1
  assert_contains "$(cat "$report")" "teeup configure git" || return 1
  cleanup_test_env
}

test_doctor_reports_signing_left_off_although_the_keys_exist() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  seed_answers
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  # The keys arrive after git was configured, which is exactly the order a
  # first bootstrap runs in: git, then ssh.
  mkdir -p "$TEST_HOME/.ssh"
  printf 'PRIVATE\n' > "$TEST_HOME/.ssh/id_ed25519_personal"
  printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAKEKEY personal\n' > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "has every key it needs on disk but commit signing is off" || return 1
  assert_contains "$(cat "$report")" "teeup configure git" || return 1
  cleanup_test_env
}

# B2: nothing in teeup ever writes gpg.ssh.allowedSignersFile, so a standard
# post-bootstrap machine hits this every time. It must be a note, not a
# failure -- a clean bootstrap has to pass doctor -- and the note must never
# suggest `git config --global`, which writes ~/.gitconfig, the same file the
# leftover-gitconfig warning below says to delete.
test_doctor_warns_about_a_missing_allowed_signers_file() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_success "$rc" "nothing in teeup writes allowedSignersFile yet, so a clean bootstrap must still pass doctor" || return 1
  assert_contains "$out" "gpg.ssh.allowedSignersFile is not set" || return 1
  assert_equals "" "$(cat "$report")" "a note must not be recorded as a doctor failure" || return 1
  assert_not_contains "$out" "git config --global" "the note must never suggest git config --global (it writes ~/.gitconfig)" || return 1
  cleanup_test_env
}

# B3: gpgsign on with no user.signingkey at all fails every commit outright
# ("fatal: either user.signingkey or gpg.ssh.defaultKeyCommand needs to be
# configured"), a different and worse failure than the key existing but not
# being on disk.
test_doctor_reports_signing_on_with_no_signing_key_configured() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  grep -v signingkey "$TEST_HOME/.config/git/identity" > "$TEST_HOME/.config/git/identity.new"
  mv "$TEST_HOME/.config/git/identity.new" "$TEST_HOME/.config/git/identity"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_failure "$rc" "gpgsign on with no signingkey must not report healthy" || return 1
  assert_contains "$out" "no user.signingkey is set" || return 1
  assert_contains "$(cat "$report")" "teeup configure git" || return 1
  cleanup_test_env
}

# Mutation gap: `_git_doctor_last_value signingkey "$identity_file"
# "$generated" "$git_dir/local"` mutated to read from $identity_file alone
# stayed green -- every other test's signingkey lives in identity (where
# `configure git` itself writes it), so no test ever put it anywhere else.
# B3's whole point is that a hand edit could put it in teeup-generated or
# $git_dir/local instead, with the same "last value wins" rule real git
# uses; the fixed key must still be found there.
test_doctor_reads_signingkey_from_local_not_only_identity() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  grep -v signingkey "$TEST_HOME/.config/git/identity" > "$TEST_HOME/.config/git/identity.new"
  mv "$TEST_HOME/.config/git/identity.new" "$TEST_HOME/.config/git/identity"
  printf '[user]\n\tsigningkey = "%s.pub"\n' "$TEST_HOME/.ssh/id_ed25519_personal" \
    > "$TEST_HOME/.config/git/local"
  local rc=0 out
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_success "$rc" "a signingkey set in \$git_dir/local, not identity, must still be found" || return 1
  assert_contains "$out" "Commit signing is on" || return 1
  assert_not_contains "$out" "no user.signingkey is set" || return 1
  cleanup_test_env
}

# I6: a claim about gpg.format that was never read. Once the format is
# something other than ssh, the whole SSH-signature verification check does
# not apply, and the message must say what format actually is.
test_doctor_skips_verification_when_gpg_format_is_not_ssh() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  printf '[gpg]\n\tformat = openpgp\n' > "$TEST_HOME/.config/git/local"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_success "$rc" "gpg.format = openpgp means the SSH allowed-signers check does not apply" || return 1
  assert_contains "$out" "gpg.format = openpgp" || return 1
  assert_not_contains "$out" "gpg.format = ssh" "a claim about gpg.format must be read, not assumed" || return 1
  cleanup_test_env
}

# The gitconfig input space, enumerated rather than assumed. _git_doctor_last_value
# greps for a bare `key =` line, and its own comment admits it "can be fooled
# by an identically-named key in an unrelated section". Two shapes make that
# a real false finding rather than a theoretical one, and git itself answers
# both correctly -- `git config -f <file> --includes --get <key>` is section
# aware, follows [include], handles quoting, case and continuation. git is
# present by definition in this capability's doctor.
test_doctor_reads_the_key_from_the_right_section() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  # A signingkey in a LATER, unrelated section. A line-oriented grep taking
  # the last match reports that one; git reports user.signingkey.
  printf '[user]\n\tsigningkey = %s\n[gpg "ssh"]\n\tsigningkey = /nowhere/wrong_key\n' \
    "$TEST_HOME/.ssh/id_ed25519_personal.pub" > "$TEST_HOME/.config/git/local"
  local out
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || true
  assert_not_contains "$out" "/nowhere/wrong_key" "the key from an unrelated section is not user.signingkey" || return 1
  cleanup_test_env
}

# [include] is how people keep a work identity in a separate file, and git
# follows it. A doctor that does not will report a perfectly configured
# machine as having no identity at all.
test_doctor_follows_a_git_include() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  printf '[user]\n\tname = "Ada Lovelace"\n\temail = "ada@example.com"\n' \
    > "$TEST_HOME/.config/git/work-identity"
  printf '[include]\n\tpath = work-identity\n' > "$TEST_HOME/.config/git/identity"
  local rc=0 out
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_not_contains "$out" "sets no name and no email" "git follows [include]; so must teeup" || return 1
  assert_contains "$out" "ada@example.com" || return 1
  cleanup_test_env
}

# git treats gpg.ssh.allowedSignersFile as a pathname: `~/allowed_signers`
# is expanded to $HOME/allowed_signers, and `git config --path --get` shows
# it. Testing the raw string with -f therefore reports a perfectly usable
# trust file as missing -- and the suggested fix appends to the EXPANDED path,
# so following it changes nothing that later runs can see and the finding
# never clears.
test_doctor_expands_a_tilde_in_the_allowed_signers_path() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  local signers="$TEST_HOME/allowed_signers"
  printf '%s ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAKEKEYpersonal\n' "ada@example.com" > "$signers"
  # Written the way a person would write it, not the way a script would.
  printf '[gpg "ssh"]\n\tallowedSignersFile = "~/allowed_signers"\n' > "$TEST_HOME/.config/git/local"
  local rc=0 out
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_not_contains "$out" "which does not exist" "the file is there; git expands the tilde and so must teeup" || return 1
  assert_contains "$out" "signatures can be verified" || return 1
  assert_success "$rc" || return 1
  cleanup_test_env
}

# A tilde path that really is missing is still a failure, so the expansion is
# not a way of skipping the check.
test_doctor_still_reports_a_missing_tilde_allowed_signers_file() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  printf '[gpg "ssh"]\n\tallowedSignersFile = "~/not_there"\n' > "$TEST_HOME/.config/git/local"
  local rc=0 out
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "which does not exist" || return 1
  # And the path it names must be the expanded one, so the suggested command
  # writes where git will look.
  assert_contains "$out" "$TEST_HOME/not_there" || return 1
  cleanup_test_env
}

# The shipped config sets `useConfigOnly = true` so git never guesses an
# identity from the hostname. That makes a missing user.name fatal, not
# cosmetic: git refuses every commit with "fatal: no name was given and
# auto-detection is disabled". Checking only the email reports that machine
# healthy, and `teeup doctor` is the gate people trust before they start work.
test_doctor_fails_when_the_identity_has_no_name() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  local identity="$TEST_HOME/.config/git/identity"
  printf '[user]\n\temail = "someone@example.com"\n' > "$identity"
  local rc=0 out
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_failure "$rc" "an identity git will not commit with is not healthy" || return 1
  assert_contains "$out" "no name" || return 1
  assert_contains "$out" "useConfigOnly" "the message has to say why a missing name is fatal, not just that it is absent" || return 1
  cleanup_test_env
}

# The mirror case, so the check cannot be satisfied by testing one field twice.
test_doctor_fails_when_the_identity_has_no_email() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  local identity="$TEST_HOME/.config/git/identity"
  printf '[user]\n\tname = "Someone"\n' > "$identity"
  local rc=0 out
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "no email" || return 1
  cleanup_test_env
}

# And both present is healthy, with the identity named.
test_doctor_names_a_complete_identity() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  local identity="$TEST_HOME/.config/git/identity"
  printf '[user]\n\tname = "Ada Lovelace"\n\temail = "ada@example.com"\n' > "$identity"
  local out
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || true
  assert_contains "$out" "ada@example.com" || return 1
  assert_not_contains "$out" "no name" || return 1
  assert_not_contains "$out" "no email" || return 1
  cleanup_test_env
}

# B-A: an unreadable teeup-owned git file is not "could not check", it is
# fatal -- verified against real git 2.55.0, every git command exits 128 the
# moment it tries to read an [include]d path it cannot open, and an
# unreadable config silently drops every include under it so `git commit`
# fails with "Author identity unknown". Three rounds of review found the same
# false-pass shape here: this used to be a warn and `teeup doctor` exited 0,
# "everything checked is healthy," on a machine where every git command was
# fatal. It has to be a doctor_fail with a chmod fix, the same pattern mise
# and starship already use for their own unreadable files.
#
# NI1: the identity file is also where `signingkey` lives, and
# _git_doctor_last_value's "could not read this file" flag used to be set
# inside the `$( )` that calls it, so it never reached the caller -- the
# branch that reads "could not check user.signingkey" was unreachable, and
# doctor instead asserted the key was unset (chmod 000 identity used to print
# "❌ commit.gpgsign is on but no user.signingkey is set", even though the
# key IS set, in the file doctor just said it could not read). Fixed, that
# secondary finding is a genuine "could not check" (a doctor_unknown, not a
# second doctor_fail): the key really might be fine, teeup only could not
# tell -- the primary fail is the unreadable file itself.
test_doctor_fails_when_identity_file_is_unreadable() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  chmod 000 "$TEST_HOME/.config/git/identity"
  local rc=0 out
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  chmod 600 "$TEST_HOME/.config/git/identity"
  assert_equals "1" "$rc" "an unreadable identity file must be a confirmed failure (rc=1), not merely unknown (rc=2) or healthy (B-A)" || return 1
  assert_not_contains "$out" "has no email" "an unreadable file's absent content must not be reported as its content" || return 1
  assert_not_contains "$out" "Permission denied" "a raw permission error must never reach the report" || return 1
  assert_not_contains "$out" "no user.signingkey is set" "the key is in the file doctor could not read, not actually unset (NI1)" || return 1
  assert_contains "$out" "cannot be read" || return 1
  assert_contains "$out" "chmod u+r" || return 1
  assert_contains "$out" "could not check user.signingkey" || return 1
  cleanup_test_env
}

# B-A: real git treats an unreadable config exactly like a missing one --
# every command it runs is fatal, or (per the file's own permissions) its
# includes are silently dropped and identity/signing vanish with them. The
# "is in place" line must never print for a file git cannot actually read,
# and nothing downstream (gpg.format, allowed-signers) can be trusted either,
# so the script stops here rather than reporting on values it never read.
test_doctor_fails_when_config_file_is_unreadable() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  chmod 000 "$TEST_HOME/.config/git/config"
  local rc=0 out
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  chmod 600 "$TEST_HOME/.config/git/config"
  assert_equals "1" "$rc" "an unreadable config file must be a confirmed failure (rc=1), not healthy (B-A)" || return 1
  assert_not_contains "$out" "Permission denied" || return 1
  assert_not_contains "$out" "is in place" "a file git cannot read is not 'in place' in any sense that matters" || return 1
  assert_not_contains "$out" "does not apply" "gpg.format was never actually read here" || return 1
  assert_contains "$out" "cannot be read" || return 1
  assert_contains "$out" "chmod u+r" || return 1
  cleanup_test_env
}

# B-A: teeup-generated is [include]d exactly like identity; unreadable, it is
# just as fatal, not merely unchecked.
test_doctor_fails_when_generated_file_is_unreadable() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  chmod 000 "$TEST_HOME/.config/git/teeup-generated"
  local rc=0 out
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  chmod 600 "$TEST_HOME/.config/git/teeup-generated"
  assert_equals "1" "$rc" "an unreadable generated file must be a confirmed failure (rc=1), not healthy (B-A)" || return 1
  assert_not_contains "$out" "commit signing is off in" "an unreadable file's absent content must not be reported as its content" || return 1
  assert_not_contains "$out" "Permission denied" || return 1
  assert_contains "$out" "cannot be read" || return 1
  assert_contains "$out" "chmod u+r" || return 1
  cleanup_test_env
}

# git_dir/local is the third [include]d file (never written by teeup, so it
# gets no upfront existence/readability gate of its own the way identity and
# teeup-generated do) -- unreadable, config, identity and teeup-generated are
# all still fine, so nothing here is a *confirmed* problem, but the
# signingkey, gpg.format and allowed-signers questions genuinely cannot be
# answered: a doctor_unknown for each, and rc=2 (could-not-verify), not
# rc=0 and not rc=1.
test_doctor_reports_unknown_when_local_file_is_unreadable() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  : > "$TEST_HOME/.config/git/local"
  chmod 000 "$TEST_HOME/.config/git/local"
  local rc=0 out
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  chmod 600 "$TEST_HOME/.config/git/local"
  assert_unknown "$rc" "nothing here is confirmed broken, but signingkey/gpg.format/allowed-signers could not be checked" || return 1
  assert_contains "$out" "could not check user.signingkey" || return 1
  assert_contains "$out" "could not check gpg.format" || return 1
  cleanup_test_env
}

# Mutation testing found `^[[:space:]]*pager = delta$` -> `grep -q 'delta'`
# stayed green: a stray mention of "delta" anywhere in teeup-generated (a
# comment, say) must not be mistaken for the pager actually being set to it.
test_doctor_requires_the_exact_pager_setting_not_a_stray_mention_of_delta() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  export TEEUP_TEST_MISSING="lazygit emacsclient"
  mock_command delta 0 ""
  seed_answers
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  printf '# used to use delta here\n[core]\n\tpager = less\n[commit]\n\tgpgsign = false\n' \
    > "$TEST_HOME/.config/git/teeup-generated"
  local rc=0 out
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_failure "$rc" "a stray mention of delta is not the pager setting" || return 1
  assert_contains "$out" "delta is installed but" || return 1
  cleanup_test_env
}

test_doctor_warns_about_a_leftover_gitconfig() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  printf '[user]\n\temail = someone@else\n' > "$TEST_HOME/.gitconfig"
  local out
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || true
  assert_contains "$out" "$TEST_HOME/.gitconfig exists and its keys win" || return 1
  cleanup_test_env
}

echo "capabilities/git"
# An unsearchable ~/.ssh makes every key test answer "no", which used to
# downgrade the real failure ("every key is here but signing is off") into a
# note that the key does not exist yet -- about a machine teeup could not
# look at.
test_doctor_separates_an_unreadable_ssh_dir_from_a_missing_key() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  # Signing off, keys unreachable rather than absent.
  grep -v 'gpgsign' "$TEST_HOME/.config/git/teeup-generated" > "$TEST_HOME/tg" && mv "$TEST_HOME/tg" "$TEST_HOME/.config/git/teeup-generated"
  chmod 0000 "$TEST_HOME/.ssh"
  local rc=0 out
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  chmod 0755 "$TEST_HOME/.ssh"
  assert_unknown "$rc" "a key teeup could not look for is not a key that is absent" || return 1
  assert_contains "$out" "cannot be read, so teeup could not tell whether the key" || return 1
  assert_not_contains "$out" "does not exist yet" || return 1
  cleanup_test_env
}

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
# A comment mentioning the setting is not the setting. A half-written TODO in
# any of git's files must not make doctor report signature verification as
# working -- but per B2, an unset allowedSignersFile is a note, not a
# failure, so this must still pass doctor.
test_doctor_does_not_count_a_commented_allowed_signers_line() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  printf '# TODO: set allowedSignersFile = somewhere\n' > "$TEST_HOME/.config/git/local"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_success "$rc" "a comment is not configuration, but it also must not fail a clean machine" || return 1
  assert_contains "$out" "allowedSignersFile is not set" || return 1
  cleanup_test_env
}

# Set, but pointing at a file that is not there: git reports that only when
# you read a signature, so doctor is where it should surface.
test_doctor_reports_an_allowed_signers_path_that_is_missing() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  printf '[gpg "ssh"]\n\tallowedSignersFile = "%s"\n' "$TEST_HOME/.config/git/gone_signers" \
    > "$TEST_HOME/.config/git/local"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "which does not exist, so git can verify no signature" || return 1
  cleanup_test_env
}

# Signing on with the key gone is worse than signing off: every commit fails,
# and a doctor reporting full health is why nobody looks here first.
test_doctor_reports_signing_on_with_the_key_gone() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  printf '%s\n' "ada@example.com ssh-ed25519 AAAA" > "$TEST_HOME/.config/git/allowed_signers"
  printf '[gpg "ssh"]\n\tallowedSignersFile = "%s"\n' "$TEST_HOME/.config/git/allowed_signers" \
    > "$TEST_HOME/.config/git/local"
  rm -f "$TEST_HOME/.ssh/id_ed25519_personal"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "but that key is not on this machine, so every git commit fails" || return 1
  cleanup_test_env
}

run_test "doctor passes on a configured tree" test_doctor_passes_on_a_configured_tree
run_test "doctor reports an unconfigured tree" test_doctor_reports_an_unconfigured_tree
run_test "doctor separates an unreadable ssh dir from a missing key" test_doctor_separates_an_unreadable_ssh_dir_from_a_missing_key
run_test "doctor reports signing left off" test_doctor_reports_signing_left_off_although_the_keys_exist
run_test "doctor warns about a missing allowed-signers file" test_doctor_warns_about_a_missing_allowed_signers_file
run_test "doctor reports signing on with no signing key configured" test_doctor_reports_signing_on_with_no_signing_key_configured
run_test "doctor reads signingkey from local, not only identity" test_doctor_reads_signingkey_from_local_not_only_identity
run_test "doctor skips verification when gpg.format is not ssh" test_doctor_skips_verification_when_gpg_format_is_not_ssh
run_test "doctor reads the key from the right section" test_doctor_reads_the_key_from_the_right_section
run_test "doctor follows a git include" test_doctor_follows_a_git_include
run_test "doctor expands a tilde in the allowed signers path" test_doctor_expands_a_tilde_in_the_allowed_signers_path
run_test "doctor still reports a missing tilde allowed signers file" test_doctor_still_reports_a_missing_tilde_allowed_signers_file
run_test "doctor fails when the identity has no name" test_doctor_fails_when_the_identity_has_no_name
run_test "doctor fails when the identity has no email" test_doctor_fails_when_the_identity_has_no_email
run_test "doctor names a complete identity" test_doctor_names_a_complete_identity
run_test "doctor fails when the identity file is unreadable" test_doctor_fails_when_identity_file_is_unreadable
run_test "doctor fails when the config file is unreadable" test_doctor_fails_when_config_file_is_unreadable
run_test "doctor fails when the generated file is unreadable" test_doctor_fails_when_generated_file_is_unreadable
run_test "doctor reports unknown when the local file is unreadable" test_doctor_reports_unknown_when_local_file_is_unreadable
run_test "doctor requires the exact pager setting, not a stray mention of delta" test_doctor_requires_the_exact_pager_setting_not_a_stray_mention_of_delta
run_test "doctor does not count a commented allowed-signers line" test_doctor_does_not_count_a_commented_allowed_signers_line
run_test "doctor reports an allowed-signers path that is missing" test_doctor_reports_an_allowed_signers_path_that_is_missing
run_test "doctor reports signing on with the key gone" test_doctor_reports_signing_on_with_the_key_gone
run_test "doctor warns about a leftover ~/.gitconfig" test_doctor_warns_about_a_leftover_gitconfig
run_test "configure repairs an old two-identity config" test_configure_repairs_an_old_two_identity_config
run_test "configure leaves a hand-edited old config alone" test_configure_leaves_a_hand_edited_old_config_alone
run_test "the leftover warning names every old-model line" test_the_leftover_warning_names_every_old_model_line
run_test "configure replaces a symlinked config and says so" test_configure_replaces_a_symlinked_config_and_says_so
run_test "configure dry run leaves a symlinked config alone" test_configure_dry_run_leaves_a_symlinked_config_alone
run_test "configure repairs nothing on a fresh machine" test_configure_repairs_nothing_on_a_fresh_machine
run_test "configure twice after the repair changes nothing" test_configure_twice_after_the_repair_changes_nothing
run_test "configure dry run repairs nothing" test_configure_dry_run_repairs_nothing
print_summary
