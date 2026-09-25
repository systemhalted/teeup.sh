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

# A checkout-shaped fixture: a caps directory with one valid capability, a
# tests directory with a stub run.sh, and a menu file. Nothing here touches
# the real suite, which takes minutes.
seed_check_fixture() {
  mkdir -p "$TEEUP_CAPS_DIR/widget" "$TEEUP_TESTS_DIR/capabilities" "$TEEUP_TESTS_DIR/lib"
  printf 'summary="Widget"\ngroup=system\ntier=lazy\nrequires=""\nprovides=""\ninteractive=false\n' \
    > "$TEEUP_CAPS_DIR/widget/capability"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/widget/install"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/widget/configure"
  chmod +x "$TEEUP_CAPS_DIR/widget/install" "$TEEUP_CAPS_DIR/widget/configure"
  : > "$TEEUP_CAPS_DIR/core.list"
  : > "$TEEUP_CAPS_DIR/daily.list"
  printf '#!/usr/bin/env bash\necho "All 1 suites passed."\n' > "$TEEUP_TESTS_DIR/run.sh"
  printf '#!/usr/bin/env bash\necho "Summary: 1/1 passed"\n' > "$TEEUP_TESTS_DIR/capabilities/widget.sh"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_TESTS_DIR/helper.sh"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_TESTS_DIR/cli.sh"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_TESTS_DIR/bootstrap.sh"
  chmod +x "$TEEUP_TESTS_DIR/run.sh"
  export TEEUP_MENU_FILE="$TEST_HOME/menu.json"
  printf '{"a": {"label": "A", "action": "true"}}\n' > "$TEEUP_MENU_FILE"
  # The real shellcheck would lint the whole checkout on every one of these
  # tests; what is being tested is how dev_check reacts to its exit status.
  mock_command shellcheck 0 ""
}

test_dev_check_passes_a_clean_checkout() {
  setup
  seed_check_fixture
  local rc=0 out
  out="$(dev_check 2>&1)" || rc=$?
  assert_success "$rc" "$out" || return 1
  assert_contains "$out" "Metadata is clean." || return 1
  assert_contains "$out" "is well formed" || return 1
  assert_contains "$out" "shellcheck is clean." || return 1
  assert_contains "$out" "everything passed" || return 1
  cleanup_test_env
}

test_dev_check_reports_a_metadata_problem() {
  setup
  seed_check_fixture
  chmod -x "$TEEUP_CAPS_DIR/widget/install"
  local rc=0 out
  out="$(dev_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "widget: install is not executable" || return 1
  assert_contains "$out" "check(s) failed" || return 1
  cleanup_test_env
}

test_dev_check_reports_a_malformed_menu() {
  setup
  seed_check_fixture
  printf '{"a": {"label": "A"}}\n' > "$TEEUP_MENU_FILE"
  local rc=0 out
  out="$(dev_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "a has neither an action nor child rows" || return 1
  cleanup_test_env
}

test_dev_check_reports_a_failing_shellcheck() {
  setup
  seed_check_fixture
  mock_command shellcheck 1 "SC9999"
  local rc=0 out
  out="$(dev_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "SC9999" || return 1
  cleanup_test_env
}

# R9.1: a check that could not run is not a pass. Missing shellcheck must end
# with exit 2 ("could not check"), never a plain success -- assert_unknown,
# not assert_success, is the whole point of this test.
test_dev_check_notes_a_missing_shellcheck_rather_than_failing() {
  setup
  seed_check_fixture
  hide_host_commands shellcheck
  local rc=0 out
  out="$(dev_check 2>&1)" || rc=$?
  assert_unknown "$rc" "a missing linter is not a broken checkout, but 0 would claim a check that never ran" || return 1
  assert_contains "$out" "shellcheck is not installed" || return 1
  assert_contains "$out" "could not check: shellcheck" || return 1
  assert_not_contains "$out" "everything passed" "a check that could not run is not a pass" || return 1
  cleanup_test_env
}

test_dev_check_with_a_name_runs_only_that_suite() {
  setup
  seed_check_fixture
  printf '#!/usr/bin/env bash\necho "the whole suite ran"\n' > "$TEEUP_TESTS_DIR/run.sh"
  chmod +x "$TEEUP_TESTS_DIR/run.sh"
  local rc=0 out
  out="$(dev_check widget 2>&1)" || rc=$?
  assert_success "$rc" "$out" || return 1
  assert_contains "$out" "Summary: 1/1 passed" || return 1
  assert_not_contains "$out" "the whole suite ran" || return 1
  cleanup_test_env
}

test_dev_check_insists_every_capability_has_a_suite() {
  setup
  seed_check_fixture
  rm -f "$TEEUP_TESTS_DIR/capabilities/widget.sh"
  local rc=0 out
  out="$(dev_check widget 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Every capability needs a dry-run test" || return 1
  cleanup_test_env
}

# R9.6: the same rule applies to a whole-suite run, per capability, even when
# no name was given to say which one to look at.
test_dev_check_insists_every_capability_has_a_suite_even_with_no_name() {
  setup
  seed_check_fixture
  rm -f "$TEEUP_TESTS_DIR/capabilities/widget.sh"
  local rc=0 out
  out="$(dev_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Every capability needs a dry-run test" || return 1
  cleanup_test_env
}

# R9.6: the <capability> argument is validated with cap_exists, not handed
# straight to a path -- "../etc" must be refused, not silently miss the file.
test_dev_check_refuses_an_unknown_capability_argument() {
  setup
  seed_check_fixture
  local rc=0 out
  out="$(dev_check "../etc" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "not a known capability" || return 1
  cleanup_test_env
}

test_dev_check_fails_when_the_suite_fails() {
  setup
  seed_check_fixture
  printf '#!/usr/bin/env bash\necho "1 of 1 suites failed."\nexit 1\n' > "$TEEUP_TESTS_DIR/run.sh"
  chmod +x "$TEEUP_TESTS_DIR/run.sh"
  local rc=0 out
  out="$(dev_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "1 of 1 suites failed." || return 1
  cleanup_test_env
}

# R9.4: refuse under DRY_RUN=true rather than silently running every suite in
# dry-run mode, which would report every mutation as skipped and every test
# as passed for the wrong reason.
test_dev_check_refuses_under_dry_run() {
  setup
  seed_check_fixture
  local rc=0 out
  out="$(DRY_RUN=true dev_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "DRY_RUN=true" || return 1
  cleanup_test_env
}

# R9.4: an exported TEEUP_* variable left over from the caller's shell must
# not reach the suite dev_check runs -- the suite has to see the same clean
# environment CI does.
test_dev_check_runs_the_suite_with_a_clean_environment() {
  setup
  seed_check_fixture
  printf '#!/usr/bin/env bash\nif [[ -n "${TEEUP_LEAKY_FIXTURE:-}" ]]; then\n  echo "leaked TEEUP_LEAKY_FIXTURE=$TEEUP_LEAKY_FIXTURE"\n  exit 1\nfi\necho "All 1 suites passed."\n' \
    > "$TEEUP_TESTS_DIR/run.sh"
  chmod +x "$TEEUP_TESTS_DIR/run.sh"
  local rc=0 out
  out="$(TEEUP_LEAKY_FIXTURE=should-not-leak dev_check 2>&1)" || rc=$?
  assert_success "$rc" "$out" || return 1
  assert_not_contains "$out" "leaked TEEUP_LEAKY_FIXTURE" || return 1
  cleanup_test_env
}

# R9.3: the shipped menu is linted alone; the user's own menu.json (if any) is
# linted too, reported as theirs, but a problem in it never fails the repo
# check.
test_dev_check_lints_the_users_menu_file_separately_without_failing_the_repo_check() {
  setup
  seed_check_fixture
  local user_menu
  user_menu="$(menu_user_file)"
  mkdir -p "$(dirname "$user_menu")"
  printf '{"b": {"label": "B"}}\n' > "$user_menu"
  local rc=0 out
  out="$(dev_check 2>&1)" || rc=$?
  assert_success "$rc" "$out" || return 1
  assert_contains "$out" "b has neither an action nor child rows" || return 1
  assert_contains "$out" "$user_menu" || return 1
  cleanup_test_env
}

# R9.5: the first `teeup <word>` of a menu row has to be a real dispatch arm.
test_dev_check_reports_an_unknown_verb_in_a_menu_row() {
  setup
  seed_check_fixture
  printf '{"a": {"label": "A", "action": "teeup frobnicate widget"}}\n' > "$TEEUP_MENU_FILE"
  local rc=0 out
  out="$(dev_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "calls an unknown verb: teeup frobnicate" || return 1
  cleanup_test_env
}

# R9.5: teeup has|install|reset|remove <cap> must name a real capability.
test_dev_check_reports_an_unknown_capability_in_a_menu_row() {
  setup
  seed_check_fixture
  printf '{"a": {"label": "A", "action": "teeup has bogus-cap"}}\n' > "$TEEUP_MENU_FILE"
  local rc=0 out
  out="$(dev_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "names an unknown capability: bogus-cap" || return 1
  cleanup_test_env
}

# R9.5: install dev-env/font are switches, not capabilities, and are exempt.
test_dev_check_allows_install_dev_env_and_font_without_a_capability() {
  setup
  seed_check_fixture
  printf '{"a": {"label": "A", "action": "teeup install dev-env python"}, "b": {"label": "B", "action": "teeup install font list"}}\n' \
    > "$TEEUP_MENU_FILE"
  local rc=0 out
  out="$(dev_check 2>&1)" || rc=$?
  assert_success "$rc" "$out" || return 1
  cleanup_test_env
}

# R9.5: teeup launch <App Name> is checked against apps=, not cap_exists.
test_dev_check_checks_launch_rows_against_apps() {
  setup
  seed_check_fixture
  printf 'summary="Widget"\ngroup=system\ntier=lazy\nrequires=""\nprovides=""\ninteractive=false\napps="Widget App"\n' \
    > "$TEEUP_CAPS_DIR/widget/capability"
  printf '{"a": {"label": "A", "action": "teeup launch Widget App"}}\n' > "$TEEUP_MENU_FILE"
  local rc=0 out
  out="$(dev_check 2>&1)" || rc=$?
  assert_success "$rc" "$out" || return 1
  cleanup_test_env
}

test_dev_check_reports_a_launch_row_that_cannot_be_resolved() {
  setup
  seed_check_fixture
  printf '{"a": {"label": "A", "action": "teeup launch Nonexistent App"}}\n' > "$TEEUP_MENU_FILE"
  local rc=0 out
  out="$(dev_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "names an app or capability launch cannot resolve: Nonexistent App" || return 1
  cleanup_test_env
}

# R9.2: dev_shell_files is the one source of truth for what CI lints, so it
# has to actually equal ci.yml's own "Shellcheck new runtime" step -- derived
# independently here, by expanding that step's globs and finds the way CI
# does, rather than by re-reading dev_shell_files' own source.
_ci_shellcheck_files() {
  local raw
  raw="$(awk '
    found && /^[[:space:]]*$/ { exit }
    found { sub(/^ */, ""); print }
    /- name: Shellcheck new runtime/ { getline; found = 1; next }
  ' "$TEEUP_PATH/.github/workflows/ci.yml")"
  (
    cd "$TEEUP_PATH" || exit 1
    shellcheck() {
      local a
      for a in "$@"; do
        case "$a" in
          --severity=*) ;;
          *) printf '%s\n' "$PWD/$a" ;;
        esac
      done
    }
    eval "$raw"
  )
}

test_dev_shell_files_matches_ci_yml() {
  setup_test_env
  mock_macos_base
  export TEEUP_NO_GUM=1
  source "$TEEUP_PATH/lib/all.sh"
  local dev_files ci_files diff_out
  dev_files="$(dev_shell_files | LC_ALL=C sort -u)"
  ci_files="$(_ci_shellcheck_files | LC_ALL=C sort -u)"
  diff_out="$(diff <(printf '%s\n' "$dev_files") <(printf '%s\n' "$ci_files") 2>&1)" || true
  if [[ -n "$diff_out" ]]; then
    echo "dev_shell_files and ci.yml's Shellcheck new runtime step disagree:"
    echo "$diff_out"
    cleanup_test_env
    return 1
  fi
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
run_test "dev check passes a clean checkout" test_dev_check_passes_a_clean_checkout
run_test "dev check reports a metadata problem" test_dev_check_reports_a_metadata_problem
run_test "dev check reports a malformed menu" test_dev_check_reports_a_malformed_menu
run_test "dev check reports a failing shellcheck" test_dev_check_reports_a_failing_shellcheck
run_test "dev check notes a missing shellcheck" test_dev_check_notes_a_missing_shellcheck_rather_than_failing
run_test "dev check with a name runs only that suite" test_dev_check_with_a_name_runs_only_that_suite
run_test "dev check insists on a suite per capability" test_dev_check_insists_every_capability_has_a_suite
run_test "dev check insists on a suite per capability, whole run" test_dev_check_insists_every_capability_has_a_suite_even_with_no_name
run_test "dev check refuses an unknown capability argument" test_dev_check_refuses_an_unknown_capability_argument
run_test "dev check fails when the suite fails" test_dev_check_fails_when_the_suite_fails
run_test "dev check refuses under dry run" test_dev_check_refuses_under_dry_run
run_test "dev check runs the suite with a clean environment" test_dev_check_runs_the_suite_with_a_clean_environment
run_test "dev check lints the user's menu file separately" test_dev_check_lints_the_users_menu_file_separately_without_failing_the_repo_check
run_test "dev check reports an unknown verb in a menu row" test_dev_check_reports_an_unknown_verb_in_a_menu_row
run_test "dev check reports an unknown capability in a menu row" test_dev_check_reports_an_unknown_capability_in_a_menu_row
run_test "dev check allows install dev-env and font" test_dev_check_allows_install_dev_env_and_font_without_a_capability
run_test "dev check checks launch rows against apps" test_dev_check_checks_launch_rows_against_apps
run_test "dev check reports an unresolved launch row" test_dev_check_reports_a_launch_row_that_cannot_be_resolved
run_test "dev_shell_files matches ci.yml" test_dev_shell_files_matches_ci_yml
print_summary
