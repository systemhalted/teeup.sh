#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_gets_gum_and_jq() {
  setup
  export TEEUP_TEST_MISSING="gum jq"
  local out
  out="$(DRY_RUN=true "$TEEUP" install teeup-runtime)"
  assert_contains "$out" "Would execute: brew install gum" || return 1
  assert_contains "$out" "Would execute: brew install jq" || return 1
  cleanup_test_env
  unset TEEUP_TEST_MISSING
}

test_configure_creates_state_env_and_link() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local d
  for d in "done" toggles migrations shims logs current stock; do
    assert_dir_exists "$TEST_HOME/.local/state/teeup/$d" || return 1
  done
  local env_body
  env_body="$(cat "$TEST_HOME/.config/teeup/env")"
  # Values are %q-escaped, not double-quoted. A path with no shell
  # metacharacters comes out of %q unchanged, but the checkout itself can sit
  # anywhere: from "/Users/ada/My Code/teeup" the env file holds
  # "My\ Code", so the expectation is escaped the same way the capability
  # escapes it. (test_configure_quotes_a_path_with_shell_metacharacters below
  # covers the harsher characters in the paths teeup generates.)
  assert_contains "$env_body" "export TEEUP_PATH=$(printf '%q' "$TEEUP_PATH")" || return 1
  # The shell layer's home files bake these two paths in as absolute strings
  # at configure time (see capabilities/zsh/configure), so the env file has
  # to carry them too, not just TEEUP_PATH.
  assert_contains "$env_body" "export TEEUP_CONFIG_DIR=$(printf '%q' "$TEST_HOME/.config/teeup")" || return 1
  assert_contains "$env_body" "export TEEUP_STATE_DIR=$(printf '%q' "$TEST_HOME/.local/state/teeup")" || return 1
  assert_equals "$TEEUP_PATH/bin/teeup" "$(readlink "$TEST_HOME/.local/bin/teeup")" || return 1
  assert_dir_exists "$TEST_HOME/.config/teeup/hooks" || return 1
  assert_dir_exists "$TEST_HOME/.config/teeup/machines" || return 1
  cleanup_test_env
}

test_configure_quotes_a_path_with_shell_metacharacters() {
  setup
  export XDG_CONFIG_HOME="$TEST_HOME/we\`ird \$dir \"q\" \\b"
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local env_file out
  env_file="$XDG_CONFIG_HOME/teeup/env"
  assert_file_exists "$env_file" || return 1
  # Passed as an argv element ($1), not interpolated into the script text: a
  # backtick, dollar, double quote or backslash in the path must not be
  # re-parsed as shell syntax here any more than it should be in the file
  # capabilities/teeup-runtime/configure writes.
  out="$(bash -c 'source "$1"; printf %s "$TEEUP_CONFIG_DIR"' _ "$env_file")"
  assert_equals "$XDG_CONFIG_HOME/teeup" "$out" || return 1
  out="$(bash -c 'source "$1"; printf %s "$TEEUP_PATH"' _ "$env_file")"
  assert_equals "$TEEUP_PATH" "$out" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure teeup-runtime)"
  assert_contains "$out" "Already current: $TEST_HOME/.config/teeup/env" || return 1
  assert_contains "$out" "Already linked" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" configure teeup-runtime)"
  [[ ! -e "$TEST_HOME/.config/teeup/env" ]] || { echo "env written in dry run"; return 1; }
  [[ ! -e "$TEST_HOME/.local/bin/teeup" ]] || { echo "link made in dry run"; return 1; }
  [[ ! -e "$TEST_HOME/.config/teeup/hooks" ]] || { echo "hook directories made in dry run"; return 1; }
  # F1: a dry run must never claim the link was made.
  assert_not_contains "$out" "Linked $TEST_HOME/.local/bin/teeup" || return 1
  cleanup_test_env
}

test_configure_installs_a_sample_for_every_hook_event() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local event hooks="$TEST_HOME/.config/teeup/hooks"
  for event in post-bootstrap post-update theme-set; do
    assert_file_exists "$hooks/$event.d/example.sample" || return 1
    assert_equals "$(cat "$TEEUP_PATH/capabilities/teeup-runtime/default/hooks/$event.sample")" "$(cat "$hooks/$event.d/example.sample")" || return 1
  done
  # The user's own hooks sit beside the samples and survive every configure.
  printf '#!/usr/bin/env bash\necho mine\n' > "$hooks/theme-set.d/10-mine.sh"
  printf 'stale\n' > "$hooks/theme-set.d/example.sample"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure teeup-runtime)"
  assert_equals "$(printf '#!/usr/bin/env bash\necho mine')" "$(cat "$hooks/theme-set.d/10-mine.sh")" || return 1
  assert_contains "$out" "Wrote $hooks/theme-set.d/example.sample" "a changed sample is rewritten" || return 1
  assert_contains "$out" "Already current: $hooks/post-update.d/example.sample" || return 1
  cleanup_test_env
}

test_configure_backs_up_a_regular_file_at_the_link() {
  setup
  mkdir -p "$TEST_HOME/.local/bin"
  printf 'mine\n' > "$TEST_HOME/.local/bin/teeup"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure teeup-runtime 2>&1)"
  assert_contains "$out" "Replacing a regular file" || return 1
  assert_equals "$TEEUP_PATH/bin/teeup" "$(readlink "$TEST_HOME/.local/bin/teeup")" || return 1
  # A glob loop, not `ls | grep`: shellcheck rejects the latter (SC2010).
  local backup="" f
  for f in "$TEST_HOME"/.local/bin/teeup.teeup_backup_*; do
    [[ -e "$f" ]] && backup="$f"
  done
  [[ -n "$backup" ]] || { echo "no backup kept"; return 1; }
  cleanup_test_env
}

# A capability tree of our own: the real teeup-runtime plus one lazy fixture,
# so the shim assertions do not depend on which lazy capabilities the repo
# ships at any given moment.
setup_with_lazy_fixture() {
  setup
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR/boxes"
  cp -R "$TEEUP_PATH/capabilities/teeup-runtime" "$TEEUP_CAPS_DIR/teeup-runtime"
  printf 'summary="Fixture boxes"\ngroup=containers\ntier=lazy\nrequires=""\nprovides="boxctl boxd"\ninteractive=false\n' > "$TEEUP_CAPS_DIR/boxes/capability"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/boxes/install"
  cp "$TEEUP_CAPS_DIR/boxes/install" "$TEEUP_CAPS_DIR/boxes/configure"
  chmod +x "$TEEUP_CAPS_DIR/boxes/install" "$TEEUP_CAPS_DIR/boxes/configure"
  printf 'teeup-runtime\n' > "$TEEUP_CAPS_DIR/core.list"
  : > "$TEEUP_CAPS_DIR/daily.list"
  SHIMS="$TEST_HOME/.local/state/teeup/shims"
}

test_configure_writes_the_lazy_shims() {
  setup_with_lazy_fixture
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  assert_file_exists "$SHIMS/boxctl" || return 1
  assert_file_exists "$SHIMS/boxd" || return 1
  [[ -x "$SHIMS/boxd" ]] || { echo "shim must be executable"; return 1; }
  assert_contains "$(cat "$SHIMS/boxd")" 'lazy-run boxes boxd "$@"' || return 1
  [[ ! -e "$SHIMS/teeup-runtime" ]] || { echo "a core capability gets no shim"; return 1; }
  cleanup_test_env
}

test_configure_removes_a_shim_its_capability_dropped() {
  setup_with_lazy_fixture
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  sed -i.bak 's/^provides=.*/provides="boxd"/' "$TEEUP_CAPS_DIR/boxes/capability" && rm "$TEEUP_CAPS_DIR/boxes/capability.bak"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure teeup-runtime 2>&1)"
  assert_contains "$out" "Removed stale shim: boxctl" || return 1
  assert_contains "$out" "Already current: $SHIMS/boxd" || return 1
  [[ ! -e "$SHIMS/boxctl" ]] || { echo "dropped command must lose its shim"; return 1; }
  cleanup_test_env
}

test_configure_dry_run_writes_no_shims() {
  setup_with_lazy_fixture
  local out
  out="$(DRY_RUN=true "$TEEUP" configure teeup-runtime)"
  assert_contains "$out" "Would write $SHIMS/boxd" || return 1
  [[ ! -e "$SHIMS/boxd" ]] || { echo "shim written in dry run"; return 1; }
  cleanup_test_env
}

echo "capabilities/teeup-runtime"
run_test "install gets gum and jq" test_install_gets_gum_and_jq
run_test "configure creates state, env and link" test_configure_creates_state_env_and_link
run_test "configure quotes a path with shell metacharacters" test_configure_quotes_a_path_with_shell_metacharacters
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "configure installs a sample for every hook event" test_configure_installs_a_sample_for_every_hook_event
run_test "configure backs up a regular file at the link" test_configure_backs_up_a_regular_file_at_the_link
run_test "configure writes the lazy shims" test_configure_writes_the_lazy_shims
run_test "configure removes a shim its capability dropped" test_configure_removes_a_shim_its_capability_dropped
run_test "configure dry run writes no shims" test_configure_dry_run_writes_no_shims
print_summary
