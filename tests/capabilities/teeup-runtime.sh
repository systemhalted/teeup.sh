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

# A sample teeup cannot rewrite (the user made it read-only, or it is one of
# their own files) must not take bootstrap down with it: write_managed_file
# refuses and returns 1, and configure has to carry on under `bash -eu` and
# still do everything below the loop.
test_configure_survives_a_sample_it_cannot_write() {
  setup
  local samples="$TEST_HOME/.config/teeup/hooks/post-update.d/example.sample"
  mkdir -p "$(dirname "$samples")"
  printf 'mine\n' > "$samples"
  chmod 0444 "$samples"
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" configure teeup-runtime 2>&1)" || rc=$?
  chmod 0644 "$samples"
  assert_success "$rc" "a sample teeup cannot write must not abort configure" || return 1
  assert_contains "$out" "is not writable" || return 1
  assert_equals "mine" "$(cat "$samples")" || return 1
  # Everything after the sample loop still ran.
  [[ -d "$TEST_HOME/.config/teeup/machines" ]] || { echo "the machines dir was not created"; return 1; }
  assert_file_exists "$TEST_HOME/.config/teeup/env" || return 1
  assert_file_exists "$TEST_HOME/.local/state/teeup/shims/docker" || return 1
  cleanup_test_env
}


# A PATH shaped the way the shell layer shapes it: the package prefix and
# ~/.local/bin in front, the lazy shims directory last.
healthy_path() {
  export PATH="$TEEUP_PKG_PREFIX/bin:$TEST_HOME/.local/bin:$PATH:$TEST_HOME/.local/state/teeup/shims"
}

test_doctor_passes_after_configure() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  healthy_path
  local rc=0 out
  out="$(DRY_RUN=false cap_run teeup-runtime doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "points at this checkout" || return 1
  assert_contains "$out" "The lazy shims directory is last on PATH." || return 1
  cleanup_test_env
}

# B1: TEEUP_PATH (and the other two values) are already exported into this
# process by lib/all.sh, so the env file's check has to prove it read the
# *file*, not echo back what it already had. A different checkout recorded in
# the file is the one case that must fail.
test_doctor_fails_when_the_env_file_points_at_another_checkout() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  healthy_path
  sed -i.bak "s#export TEEUP_PATH=.*#export TEEUP_PATH=$(printf '%q' "$TEST_HOME/somewhere-else")#" "$TEST_HOME/.config/teeup/env"
  rm -f "$TEST_HOME/.config/teeup/env.bak"
  local rc=0 out
  out="$(DRY_RUN=false cap_run teeup-runtime doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "does not match this checkout" || return 1
  assert_contains "$out" "TEEUP_PATH=$TEST_HOME/somewhere-else" || return 1
  assert_not_contains "$out" "/env points at this checkout" || return 1
  cleanup_test_env
}

# The commented-out case is exactly the mutation the adversarial review found
# undetected: with TEEUP_PATH inherited rather than unset before sourcing, a
# file that never sets it at all still "matches" this process's own value.
test_doctor_fails_when_the_env_file_has_teeup_path_commented_out() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  healthy_path
  sed -i.bak 's/^export TEEUP_PATH=/# export TEEUP_PATH=/' "$TEST_HOME/.config/teeup/env"
  rm -f "$TEST_HOME/.config/teeup/env.bak"
  local rc=0 out
  out="$(DRY_RUN=false cap_run teeup-runtime doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "does not match this checkout" || return 1
  assert_contains "$out" "TEEUP_PATH=nothing" || return 1
  assert_not_contains "$out" "/env points at this checkout" || return 1
  cleanup_test_env
}

test_doctor_fails_when_the_env_file_is_empty() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  healthy_path
  : > "$TEST_HOME/.config/teeup/env"
  local rc=0 out
  out="$(DRY_RUN=false cap_run teeup-runtime doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "does not match this checkout" || return 1
  assert_not_contains "$out" "/env points at this checkout" || return 1
  cleanup_test_env
}

test_doctor_fails_when_the_env_file_has_a_syntax_error() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  healthy_path
  printf 'if [ then\n' >> "$TEST_HOME/.config/teeup/env"
  local rc=0 out
  out="$(DRY_RUN=false cap_run teeup-runtime doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "could not source it" || return 1
  assert_not_contains "$out" "/env points at this checkout" || return 1
  # bash's own syntax-error text is stderr noise, not a finding.
  assert_not_contains "$out" "unexpected token" || return 1
  cleanup_test_env
}

test_doctor_fails_without_leaking_raw_errors_when_the_env_file_is_unreadable() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  healthy_path
  chmod 000 "$TEST_HOME/.config/teeup/env"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run teeup-runtime doctor 2>&1)" || rc=$?
  chmod 644 "$TEST_HOME/.config/teeup/env"
  assert_failure "$rc" || return 1
  assert_contains "$out" "cannot be read" || return 1
  assert_contains "$(cat "$report")" "chmod u+r" || return 1
  assert_not_contains "$out" "/env points at this checkout" || return 1
  assert_not_contains "$out" "Permission denied" || return 1
  cleanup_test_env
}

# I3: -d succeeds on a directory that cannot be read or searched, which is
# the exact state that makes state_done's own -f lookups silently answer no.
test_doctor_fails_when_a_state_directory_cannot_be_searched() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  healthy_path
  chmod 000 "$TEST_HOME/.local/state/teeup/done"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run teeup-runtime doctor 2>&1)" || rc=$?
  chmod 755 "$TEST_HOME/.local/state/teeup/done"
  assert_failure "$rc" || return 1
  assert_contains "$out" "not readable/searchable" || return 1
  assert_contains "$(cat "$report")" "chmod u+rx" || return 1
  assert_not_contains "$out" "Every state directory is present" || return 1
  cleanup_test_env
}

test_doctor_reports_a_missing_env_file_link_and_state() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run teeup-runtime doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "shells and LaunchAgents cannot find the checkout" || return 1
  assert_contains "$out" "so the teeup command is not on PATH" || return 1
  assert_contains "$out" "Missing under" || return 1
  assert_contains "$(cat "$report")" "teeup configure teeup-runtime" || return 1
  cleanup_test_env
}

test_doctor_fails_when_the_shims_directory_is_off_path() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  export PATH="$TEEUP_PKG_PREFIX/bin:$TEST_HOME/.local/bin:$PATH"
  local rc=0 out
  out="$(DRY_RUN=false cap_run teeup-runtime doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "is not on PATH, so no lazy shim can fire" || return 1
  cleanup_test_env
}

test_doctor_warns_when_the_shims_directory_is_not_last() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  export PATH="$TEEUP_PKG_PREFIX/bin:$TEST_HOME/.local/bin:$TEST_HOME/.local/state/teeup/shims:$PATH"
  local rc=0 out
  out="$(DRY_RUN=false cap_run teeup-runtime doctor 2>&1)" || rc=$?
  assert_success "$rc" "being out of order is a warning, not a failure" || return 1
  assert_contains "$out" "on PATH but not last" || return 1
  cleanup_test_env
}

# The shims directory twice on PATH -- once early, once last. It ends with
# the shims dir, so an "ends with" test passes, while the early copy shadows
# every real binary behind a shim: the exact failure the check is for.
test_doctor_warns_when_the_shims_directory_appears_twice() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local shims="$TEST_HOME/.local/state/teeup/shims"
  export PATH="$shims:$TEEUP_PKG_PREFIX/bin:$TEST_HOME/.local/bin:$PATH:$shims"
  local rc=0 out
  out="$(DRY_RUN=false cap_run teeup-runtime doctor 2>&1)" || rc=$?
  assert_success "$rc" "a shadowing PATH is a warning, not a failure" || return 1
  assert_contains "$out" "on PATH 2 times" || return 1
  assert_not_contains "$out" "is last on PATH" || return 1
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
run_test "configure survives a sample it cannot write" test_configure_survives_a_sample_it_cannot_write
run_test "configure dry run writes no shims" test_configure_dry_run_writes_no_shims
run_test "doctor passes after configure" test_doctor_passes_after_configure
run_test "doctor reports a missing env file, link and state" test_doctor_reports_a_missing_env_file_link_and_state
run_test "doctor fails when the shims dir is off PATH" test_doctor_fails_when_the_shims_directory_is_off_path
run_test "doctor warns when the shims dir is not last" test_doctor_warns_when_the_shims_directory_is_not_last
run_test "doctor warns when the shims dir appears twice" test_doctor_warns_when_the_shims_directory_appears_twice
run_test "doctor fails when the env file points at another checkout" test_doctor_fails_when_the_env_file_points_at_another_checkout
run_test "doctor fails when the env file has TEEUP_PATH commented out" test_doctor_fails_when_the_env_file_has_teeup_path_commented_out
run_test "doctor fails when the env file is empty" test_doctor_fails_when_the_env_file_is_empty
run_test "doctor fails when the env file has a syntax error" test_doctor_fails_when_the_env_file_has_a_syntax_error
run_test "doctor fails without leaking raw errors when the env file is unreadable" test_doctor_fails_without_leaking_raw_errors_when_the_env_file_is_unreadable
run_test "doctor fails when a state directory cannot be searched" test_doctor_fails_when_a_state_directory_cannot_be_searched
print_summary
