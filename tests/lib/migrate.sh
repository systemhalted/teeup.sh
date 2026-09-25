#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# Every test in this file runs inside the harness's throwaway HOME. The
# stand-in for the sibling chezmoi repo (~/Work/environment/dotfiles on the
# real machine, which keeps serving Linux and must never be touched) is
# created under $TEST_HOME with the same shape, so nothing here can reach the
# real one even if a gate were broken.
SIBLING_REL="Work/environment/dotfiles"

setup() {
  setup_test_env
  mock_macos_base
  # A config root whose name carries a space and three characters that are
  # special to sed, awk and the shell.
  export XDG_CONFIG_HOME="$TEST_HOME/con fig \$x & 'q'"
  export TEEUP_CONFIG_DIR="$XDG_CONFIG_HOME/teeup"
  export TEEUP_STATE_DIR="$TEST_HOME/sta te \$x & 'q'/teeup"
  # Prompts must be pipe-driven: the narrowed PATH still exposes a host gum.
  export TEEUP_NO_GUM=1
  source "$TEEUP_PATH/lib/all.sh"
  export DRY_RUN=false
  SIBLING="$TEST_HOME/$SIBLING_REL"
  mkdir -p "$SIBLING/dot_config"
  printf 'sibling\n' > "$SIBLING/dot_zshrc"
}

# A chezmoi that says $SIBLING is its source directory and lists whatever
# $TEEUP_TEST_CHEZMOI_MANAGED holds. Every call lands in $MOCK_LOG, so a test
# can prove which subcommands ran.
mock_chezmoi() {
  export TEEUP_TEST_CHEZMOI_SRC="${1-$SIBLING}"
  mock_command_script chezmoi <<'EOF2'
case "$1" in
  source-path) printf '%s\n' "$TEEUP_TEST_CHEZMOI_SRC" ;;
  managed) cat "${TEEUP_TEST_CHEZMOI_MANAGED:-/dev/null}" ;;
  --version) echo "chezmoi version v2.66.0" ;;
  *) echo "mock chezmoi: unexpected subcommand $1" >&2; exit 1 ;;
esac
EOF2
}

no_chezmoi() { export TEEUP_TEST_MISSING="chezmoi"; }

# Comparisons against a path teeup printed must use the physical form: on
# macOS $TEST_HOME under /var/folders resolves to /private/var/folders, and
# migrate_rm reports the resolved path (ruling R2).
phys_home() { (cd "$TEST_HOME" && pwd -P); }

test_migrate_target_names_only_the_five_legacy_paths() {
  setup
  assert_equals "$TEST_HOME/.teeup.common" "$(migrate_target teeup-common)" || return 1
  assert_equals "$TEST_HOME/.teeupshrc" "$(migrate_target teeupshrc)" || return 1
  assert_equals "$TEST_HOME/.shellrc.common" "$(migrate_target shellrc-common)" || return 1
  assert_equals "$XDG_CONFIG_HOME/mac-setup" "$(migrate_target mac-setup)" || return 1
  assert_equals "$XDG_CONFIG_HOME/chezmoi" "$(migrate_target chezmoi-config)" || return 1
  local rc=0
  migrate_target "$SIBLING" >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "a path is not a key" || return 1
  rc=0
  migrate_target dotfiles >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "there is no key for the sibling repo" || return 1
  cleanup_test_env
}

test_chezmoi_ro_runs_the_read_only_subcommands() {
  setup
  mock_chezmoi
  assert_equals "$SIBLING" "$(chezmoi_ro source-path)" || return 1
  assert_contains "$(chezmoi_ro --version)" "chezmoi version" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "chezmoi source-path" || return 1
  cleanup_test_env
}

# `chezmoi purge` "removes chezmoi's configuration, state, and source
# directory" -- the sibling repo. It must be unreachable, and so must every
# other writing subcommand.
test_chezmoi_ro_refuses_purge_and_every_other_subcommand() {
  setup
  mock_chezmoi
  local sub rc out
  for sub in purge apply destroy add init remove forget edit update; do
    rc=0
    out="$(chezmoi_ro "$sub" 2>&1)" || rc=$?
    assert_failure "$rc" "chezmoi_ro must refuse $sub" || return 1
    assert_contains "$out" "read-only chezmoi subcommands" || return 1
  done
  assert_not_contains "$(cat "$MOCK_LOG")" "chezmoi purge" "it must not reach the binary at all" || return 1
  cleanup_test_env
}

# A5: the guarantee that purge is unreachable holds only while chezmoi_ro is
# the single call site. A second one added later would silently reopen it, so
# the rule is enforced rather than documented.
test_nothing_outside_chezmoi_ro_runs_chezmoi() {
  setup
  local offenders
  offenders="$(grep -rnE '(^|[^_[:alnum:]])chezmoi[ \t]' \
    "$TEEUP_PATH/bin" "$TEEUP_PATH/lib" "$TEEUP_PATH/capabilities" 2>/dev/null \
    | grep -v 'lib/migrate.sh' \
    | grep -vE '^[^:]+:[0-9]+:[ \t]*#' \
    || true)"
  if [[ -n "$offenders" ]]; then
    echo "chezmoi is invoked outside chezmoi_ro, so purge is reachable again:"
    echo "$offenders"
    cleanup_test_env
    return 1
  fi
  cleanup_test_env
}

test_migrate_resolve_leaves_the_last_component_alone() {
  setup
  local home
  home="$(phys_home)"
  mkdir -p "$TEST_HOME/real"
  ln -s "$TEST_HOME/real" "$TEST_HOME/link"
  # The parent is resolved...
  assert_equals "$home/real/thing" "$(migrate_resolve "$TEST_HOME/link/thing")" || return 1
  # ...but a dangling last component is not followed, so it can be removed.
  ln -s "$TEST_HOME/gone" "$TEST_HOME/dangling"
  assert_equals "$home/dangling" "$(migrate_resolve "$TEST_HOME/dangling")" || return 1
  local rc=0
  migrate_resolve "$TEST_HOME/no/such/parent/x" >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "a missing parent cannot be resolved" || return 1
  cleanup_test_env
}

test_migrate_path_is_safe_refuses_home_itself_and_anything_outside_it() {
  setup
  no_chezmoi
  local home
  home="$(phys_home)"
  migrate_path_is_safe "$home/.teeup.common" || { echo "a plain file under HOME must be safe"; return 1; }
  if migrate_path_is_safe "$home"; then echo "HOME itself must be refused"; return 1; fi
  if migrate_path_is_safe "/etc/zshrc"; then echo "a path outside HOME must be refused"; return 1; fi
  if migrate_path_is_safe "/"; then echo "/ must be refused"; return 1; fi
  if migrate_path_is_safe "$home/../elsewhere"; then echo "a .. component must be refused"; return 1; fi
  cleanup_test_env
}

test_migrate_path_is_safe_refuses_the_chezmoi_source_directory() {
  setup
  mock_chezmoi
  local src
  src="$(cd "$SIBLING" && pwd -P)"
  if migrate_path_is_safe "$src"; then echo "the source directory itself must be refused"; return 1; fi
  if migrate_path_is_safe "$src/dot_zshrc"; then echo "a file inside it must be refused"; return 1; fi
  if migrate_path_is_safe "$(dirname "$src")"; then echo "a directory containing it must be refused"; return 1; fi
  cleanup_test_env
}

# T2.1(a), Blocking. `chezmoi source-path` failing, or answering nothing, is
# not the same as chezmoi being absent: it means teeup could not find out
# where the repo is. Treating that as "no repo to protect" is what lets a
# later run delete inside it. Fail closed.
test_migrate_path_is_safe_fails_closed_when_the_source_cannot_be_determined() {
  setup
  # chezmoi is present but answers nothing for source-path.
  mock_command_script chezmoi <<'EOF2'
case "$1" in
  source-path) exit 0 ;;
  --version) echo "chezmoi version v2.66.0" ;;
  *) exit 1 ;;
esac
EOF2
  local home
  home="$(phys_home)"
  if migrate_path_is_safe "$home/.teeup.common"; then
    echo "an undeterminable chezmoi source must refuse every path, not allow them"
    return 1
  fi
  # And when it fails outright.
  mock_command_script chezmoi <<'EOF2'
case "$1" in
  source-path) echo "chezmoi: no config file found" >&2; exit 1 ;;
  --version) echo "chezmoi version v2.66.0" ;;
  *) exit 1 ;;
esac
EOF2
  if migrate_path_is_safe "$home/.teeup.common"; then
    echo "a failing chezmoi source-path must refuse every path"
    return 1
  fi
  # With no chezmoi at all there is nothing to determine, so paths are fine.
  no_chezmoi
  migrate_path_is_safe "$home/.teeup.common" || { echo "no chezmoi means no repo to protect"; return 1; }
  cleanup_test_env
}

# T2.1(b), Blocking. The sibling repo is a git checkout, and so is anything
# else a user keeps under $HOME. A key that resolves inside one -- through a
# symlinked ~/.config, say -- must be refused even when chezmoi says nothing
# about it. This is the gate that keeps rm -rf out of a repository.
test_migrate_path_is_safe_refuses_anything_inside_a_git_checkout() {
  setup
  no_chezmoi
  local home
  home="$(phys_home)"
  mkdir -p "$TEST_HOME/somerepo/.git" "$TEST_HOME/somerepo/nested/deep"
  if migrate_path_is_safe "$home/somerepo/nested/deep/thing"; then
    echo "a path inside a git checkout must be refused"
    return 1
  fi
  if migrate_path_is_safe "$home/somerepo/thing"; then
    echo "a path directly inside a git checkout must be refused"
    return 1
  fi
  # A sibling directory that is not in the checkout is still fine.
  mkdir -p "$TEST_HOME/notarepo"
  migrate_path_is_safe "$home/notarepo/thing" || { echo "a path outside any checkout must stay allowed"; return 1; }
  cleanup_test_env
}

test_migrate_rm_refuses_a_key_it_was_never_given() {
  setup
  no_chezmoi
  local rc=0 out
  out="$(migrate_rm "$SIBLING" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "no target named" || return 1
  assert_file_exists "$SIBLING/dot_zshrc" "the sibling repo must be untouched" || return 1
  cleanup_test_env
}

test_migrate_rm_removes_a_file_a_dir_and_a_symlink() {
  setup
  no_chezmoi
  printf 'x\n' > "$TEST_HOME/.teeup.common"
  mkdir -p "$XDG_CONFIG_HOME/mac-setup/sub"
  printf 'y\n' > "$XDG_CONFIG_HOME/mac-setup/sub/f"
  printf 'keep me\n' > "$TEST_HOME/target"
  ln -s "$TEST_HOME/target" "$TEST_HOME/.teeupshrc"
  migrate_rm teeup-common >/dev/null || return 1
  migrate_rm mac-setup >/dev/null || return 1
  migrate_rm teeupshrc >/dev/null || return 1
  [[ ! -e "$TEST_HOME/.teeup.common" ]] || { echo "the file survived"; return 1; }
  [[ ! -e "$XDG_CONFIG_HOME/mac-setup" ]] || { echo "the directory survived"; return 1; }
  [[ ! -L "$TEST_HOME/.teeupshrc" ]] || { echo "the symlink survived"; return 1; }
  assert_contains "$(cat "$TEST_HOME/target")" "keep me" "what the symlink pointed at must be untouched" || return 1
  cleanup_test_env
}

# R1/A2, Blocking. DRY_RUN=true is the step the README tells the user to take
# first. A preview that reports deletions which never happened is worthless
# exactly where it matters most.
test_migrate_rm_dry_run_previews_without_claiming_a_deletion() {
  setup
  no_chezmoi
  printf 'x\n' > "$TEST_HOME/.teeup.common"
  local out
  out="$(DRY_RUN=true migrate_rm teeup-common 2>&1)"
  assert_file_exists "$TEST_HOME/.teeup.common" "a dry run must not delete anything" || return 1
  assert_not_contains "$out" "✅" "a dry run must not claim it removed anything" || return 1
  assert_contains "$out" "DRY-RUN" || return 1
  cleanup_test_env
}

# R1/A2. "Removed ..." is said only after a real rm returned 0. An unwritable
# parent directory makes rm fail, and a migration that reports the deletion
# anyway sends the user off believing a file is gone that is still there.
test_migrate_rm_reports_a_deletion_that_did_not_happen() {
  setup
  no_chezmoi
  mkdir -p "$TEST_HOME/ro"
  printf 'x\n' > "$TEST_HOME/ro/.teeup.common"
  # migrate_target builds the path from $HOME, so point HOME at the
  # unwritable directory rather than guessing at its internals.
  local out rc=0
  HOME="$TEST_HOME/ro" chmod 0500 "$TEST_HOME/ro"
  out="$(HOME="$TEST_HOME/ro" migrate_rm teeup-common 2>&1)" || rc=$?
  chmod 0700 "$TEST_HOME/ro"
  assert_file_exists "$TEST_HOME/ro/.teeup.common" "the fixture must still be there for this to mean anything" || return 1
  assert_not_contains "$out" "Removed the legacy file" "it must not claim a deletion that failed" || return 1
  assert_failure "$rc" "a failed deletion is not a success" || return 1
  cleanup_test_env
}

test_migrate_rm_says_nothing_is_there_without_failing() {
  setup
  no_chezmoi
  local out rc=0
  out="$(migrate_rm teeup-common 2>&1)" || rc=$?
  assert_success "$rc" "nothing to remove is not a failure" || return 1
  assert_contains "$out" "Nothing at" || return 1
  cleanup_test_env
}

# The gate runs before the existence check on purpose: a key that resolves
# somewhere forbidden is refused out loud whether or not anything is there.
test_migrate_rm_refuses_a_key_that_resolves_into_the_sibling_repo() {
  setup
  mock_chezmoi
  # ~/.config symlinked into the chezmoi checkout, which is how a key can
  # land inside the repo without anybody naming it.
  rm -rf "$XDG_CONFIG_HOME"
  ln -s "$SIBLING/dot_config" "$XDG_CONFIG_HOME"
  mkdir -p "$SIBLING/dot_config/mac-setup"
  printf 'inside the repo\n' > "$SIBLING/dot_config/mac-setup/f"
  local rc=0 out
  out="$(migrate_rm mac-setup 2>&1)" || rc=$?
  assert_failure "$rc" "a key resolving into the sibling repo must be refused" || return 1
  assert_contains "$out" "must not touch" || return 1
  assert_file_exists "$SIBLING/dot_config/mac-setup/f" "nothing inside the repo may be removed" || return 1
  cleanup_test_env
}

echo "lib/migrate"
run_test "migrate_target names only the five legacy paths" test_migrate_target_names_only_the_five_legacy_paths
run_test "chezmoi_ro runs the read-only subcommands" test_chezmoi_ro_runs_the_read_only_subcommands
run_test "chezmoi_ro refuses purge and every other subcommand" test_chezmoi_ro_refuses_purge_and_every_other_subcommand
run_test "nothing outside chezmoi_ro runs chezmoi" test_nothing_outside_chezmoi_ro_runs_chezmoi
run_test "migrate_resolve leaves the last component alone" test_migrate_resolve_leaves_the_last_component_alone
run_test "migrate_path_is_safe refuses HOME itself and anything outside it" test_migrate_path_is_safe_refuses_home_itself_and_anything_outside_it
run_test "migrate_path_is_safe refuses the chezmoi source directory" test_migrate_path_is_safe_refuses_the_chezmoi_source_directory
run_test "migrate_path_is_safe fails closed when the source cannot be determined" test_migrate_path_is_safe_fails_closed_when_the_source_cannot_be_determined
run_test "migrate_path_is_safe refuses anything inside a git checkout" test_migrate_path_is_safe_refuses_anything_inside_a_git_checkout
run_test "migrate_rm refuses a key it was never given" test_migrate_rm_refuses_a_key_it_was_never_given
run_test "migrate_rm removes a file, a dir and a symlink" test_migrate_rm_removes_a_file_a_dir_and_a_symlink
run_test "migrate_rm dry run previews without claiming a deletion" test_migrate_rm_dry_run_previews_without_claiming_a_deletion
run_test "migrate_rm reports a deletion that did not happen" test_migrate_rm_reports_a_deletion_that_did_not_happen
run_test "migrate_rm says nothing is there without failing" test_migrate_rm_says_nothing_is_there_without_failing
run_test "migrate_rm refuses a key that resolves into the sibling repo" test_migrate_rm_refuses_a_key_that_resolves_into_the_sibling_repo
print_summary
