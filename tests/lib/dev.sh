#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  # A caps directory with a space and three characters that are special to
  # sed, awk and the shell, so the scaffold is exercised against one.
  export TEEUP_CAPS_DIR="$TEST_HOME/ca ps \$x & 'q'"
  export TEEUP_TESTS_DIR="$TEST_HOME/te sts \$x & 'q'"
  mkdir -p "$TEEUP_CAPS_DIR" "$TEEUP_TESTS_DIR/capabilities"
  export TEEUP_NO_GUM=1
  source "$TEEUP_PATH/lib/all.sh"
}

# _dev_test_mode <path> -> its octal permission bits. Same GNU-then-BSD stat
# fallback as lib/files.sh's own _file_mode, kept local to the test so it
# does not depend on that private helper staying exported.
_dev_test_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || true
}

test_new_capability_writes_the_four_files() {
  setup
  dev_new_capability widget >/dev/null
  assert_file_exists "$TEEUP_CAPS_DIR/widget/capability" || return 1
  assert_file_exists "$TEEUP_CAPS_DIR/widget/install" || return 1
  assert_file_exists "$TEEUP_CAPS_DIR/widget/configure" || return 1
  assert_file_exists "$TEEUP_TESTS_DIR/capabilities/widget.sh" || return 1
  [[ -x "$TEEUP_CAPS_DIR/widget/install" ]] || { echo "install must be executable"; return 1; }
  [[ -x "$TEEUP_CAPS_DIR/widget/configure" ]] || { echo "configure must be executable"; return 1; }
  cleanup_test_env
}

test_new_capability_sets_the_right_modes() {
  setup
  dev_new_capability widget >/dev/null
  assert_equals "644" "$(_dev_test_mode "$TEEUP_CAPS_DIR/widget/capability")" "capability metadata should be 644" || return 1
  assert_equals "644" "$(_dev_test_mode "$TEEUP_TESTS_DIR/capabilities/widget.sh")" "the generated test should be 644" || return 1
  assert_equals "755" "$(_dev_test_mode "$TEEUP_CAPS_DIR/widget/install")" "install should be 755" || return 1
  assert_equals "755" "$(_dev_test_mode "$TEEUP_CAPS_DIR/widget/configure")" "configure should be 755" || return 1
  cleanup_test_env
}

test_new_capability_replaces_every_token() {
  setup
  dev_new_capability widget >/dev/null
  local body
  body="$(cat "$TEEUP_CAPS_DIR"/widget/capability "$TEEUP_CAPS_DIR"/widget/install "$TEEUP_CAPS_DIR"/widget/configure "$TEEUP_TESTS_DIR"/capabilities/widget.sh)"
  assert_not_contains "$body" "@NAME@" "no token may survive the scaffold" || return 1
  assert_contains "$body" 'packages="widget"' || return 1
  assert_contains "$body" 'tier=lazy' "a scaffold must not break teeup commands --check" || return 1
  cleanup_test_env
}

test_the_scaffolded_files_are_valid_shell() {
  setup
  dev_new_capability widget >/dev/null
  local f
  for f in "$TEEUP_CAPS_DIR/widget/capability" "$TEEUP_CAPS_DIR/widget/install" \
           "$TEEUP_CAPS_DIR/widget/configure" "$TEEUP_TESTS_DIR/capabilities/widget.sh"; do
    bash -n "$f" || { echo "$f does not parse"; return 1; }
  done
  cleanup_test_env
}

test_the_scaffolded_metadata_passes_the_lint() {
  setup
  dev_new_capability widget >/dev/null
  # The scaffold's requires= names package-manager, which every capability
  # needs; a stub stands in for it inside this throwaway caps directory.
  mkdir -p "$TEEUP_CAPS_DIR/package-manager"
  printf 'summary="Stub"\ngroup=system\ntier=lazy\nrequires=""\nprovides=""\ninteractive=false\n' \
    > "$TEEUP_CAPS_DIR/package-manager/capability"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/package-manager/install"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/package-manager/configure"
  chmod +x "$TEEUP_CAPS_DIR/package-manager/install" "$TEEUP_CAPS_DIR/package-manager/configure"
  # cap_check also wants the tier lists to exist and to name nothing unknown.
  : > "$TEEUP_CAPS_DIR/core.list"
  : > "$TEEUP_CAPS_DIR/daily.list"
  cap_check || { echo "a fresh scaffold must lint clean"; return 1; }
  cleanup_test_env
}

test_new_capability_refuses_a_bad_or_taken_name() {
  setup
  local rc=0 out
  out="$(dev_new_capability "Widget" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "lower-case letters, digits and dashes" || return 1
  rc=0
  out="$(dev_new_capability "" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Usage: teeup dev new-capability" || return 1
  dev_new_capability widget >/dev/null
  rc=0
  out="$(dev_new_capability widget 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "already exists" || return 1
  cleanup_test_env
}

test_new_capability_writes_nothing_in_a_dry_run() {
  setup
  local out
  out="$(DRY_RUN=true dev_new_capability widget 2>&1)"
  [[ ! -e "$TEEUP_CAPS_DIR/widget" ]] || { echo "a dry run must create nothing"; return 1; }
  [[ ! -e "$TEEUP_TESTS_DIR/capabilities/widget.sh" ]] || { echo "a dry run must create no test"; return 1; }
  assert_not_contains "$out" "Scaffolded" "a dry run must not claim a mutation" || return 1
  assert_not_contains "$out" "Next (spec section 12)" "a dry run must print no next-steps list" || return 1
  cleanup_test_env
}

test_new_capability_removes_a_partial_scaffold_when_a_render_fails() {
  setup
  mkdir -p "$TEEUP_CAPS_DIR/widget"
  : > "$TEEUP_CAPS_DIR/widget/install"
  chmod 400 "$TEEUP_CAPS_DIR/widget/install"
  local rc=0 out
  out="$(dev_new_capability widget 2>&1)" || rc=$?
  chmod 700 "$TEEUP_CAPS_DIR/widget/install" 2>/dev/null || true
  assert_failure "$rc" || return 1
  [[ ! -e "$TEEUP_CAPS_DIR/widget" ]] || { echo "a failed render must remove the partial scaffold"; return 1; }
  cleanup_test_env
}

test_the_scaffolded_capability_passes_its_own_generated_suite() {
  setup
  # R8.1: tests/run.sh treats the checkout as read-only and diffs its whole
  # tree before and after a run (its _mode_snapshot), because suites run in
  # parallel and an interrupted run must never leave a stray capability
  # behind. So this scaffolds into a COPY of the checkout under $TEST_HOME,
  # not the real one: a generated suite finds tests/helper.sh by walking up
  # from where it sits, so the copy needs its own bin, lib, share,
  # capabilities and tests/helper.sh to behave exactly like the real thing.
  unset TEEUP_CAPS_DIR TEEUP_TESTS_DIR
  local copy="$TEST_HOME/checkout"
  mkdir -p "$copy/tests"
  cp -Rp "$TEEUP_PATH/bin" "$copy/bin"
  cp -Rp "$TEEUP_PATH/lib" "$copy/lib"
  cp -Rp "$TEEUP_PATH/share" "$copy/share"
  cp -Rp "$TEEUP_PATH/capabilities" "$copy/capabilities"
  cp -p "$TEEUP_PATH/tests/helper.sh" "$copy/tests/helper.sh"
  cp -p "$TEEUP_PATH/version" "$copy/version"
  local name=teeup-scaffold-probe
  local before after out="" rc=0 lint_rc=0
  before="$(git -C "$TEEUP_PATH" status --porcelain)"
  "$copy/bin/teeup" dev new-capability "$name" >/dev/null 2>&1 || rc=$?
  if [[ $rc -eq 0 ]]; then
    "$copy/bin/teeup" commands --check >/dev/null 2>&1 || lint_rc=$?
    out="$(bash "$copy/tests/capabilities/$name.sh" 2>&1)" || rc=$?
  fi
  after="$(git -C "$TEEUP_PATH" status --porcelain)"
  assert_equals "$before" "$after" "the real checkout must stay clean" || return 1
  assert_success "$rc" "the generated suite must pass: $out" || return 1
  assert_success "$lint_rc" "a scaffold must keep teeup commands --check green" || return 1
  assert_contains "$out" "Summary: 2/2 passed" || return 1
  cleanup_test_env
}

echo "lib/dev.sh"
run_test "new-capability writes the four files" test_new_capability_writes_the_four_files
run_test "new-capability sets the right modes" test_new_capability_sets_the_right_modes
run_test "new-capability replaces every token" test_new_capability_replaces_every_token
run_test "the scaffolded files are valid shell" test_the_scaffolded_files_are_valid_shell
run_test "the scaffolded metadata passes the lint" test_the_scaffolded_metadata_passes_the_lint
run_test "new-capability refuses a bad or taken name" test_new_capability_refuses_a_bad_or_taken_name
run_test "new-capability writes nothing in a dry run" test_new_capability_writes_nothing_in_a_dry_run
run_test "new-capability removes a partial scaffold when a render fails" test_new_capability_removes_a_partial_scaffold_when_a_render_fails
run_test "the scaffold passes its own generated suite" test_the_scaffolded_capability_passes_its_own_generated_suite
print_summary
