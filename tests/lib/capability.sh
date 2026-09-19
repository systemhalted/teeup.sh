#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# Builds a fixture capability tree under $TEST_HOME/caps.
make_cap() {
  local name="$1" tier="$2" requires="${3:-}" provides="${4:-}"
  local dir="$TEEUP_CAPS_DIR/$name"
  mkdir -p "$dir"
  cat > "$dir/capability" <<EOF2
summary="Fixture $name"
group=system
tier=$tier
requires="$requires"
provides="$provides"
interactive=false
EOF2
  printf '#!/usr/bin/env bash\necho "install:%s cap=$TEEUP_CAP dir=$TEEUP_CAP_DIR"\n' "$name" > "$dir/install"
  printf '#!/usr/bin/env bash\necho "configure:%s"\nlog "from lib"\n' "$name" > "$dir/configure"
  chmod +x "$dir/install" "$dir/configure"
}

setup() {
  setup_test_env
  mock_command hostname 0 "testmac"
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR"
  source "$TEEUP_PATH/lib/all.sh"
  # shellcheck disable=SC2034
  DRY_RUN=false
  make_cap alpha core "" ""
  make_cap beta core "alpha" ""
  make_cap gamma daily "beta alpha" "gam"
  make_cap lazyone lazy "" ""
  printf '# core\nalpha\nbeta\n' > "$TEEUP_CAPS_DIR/core.list"
  printf 'gamma\n' > "$TEEUP_CAPS_DIR/daily.list"
}

test_list_and_exists() {
  setup
  assert_equals "alpha beta gamma lazyone" "$(cap_list | tr '\n' ' ' | sed 's/ $//')" || return 1
  cap_exists alpha || { echo "alpha should exist"; return 1; }
  cap_exists nope && { echo "nope should not exist"; return 1; }
  cleanup_test_env
}

test_meta_get_with_default() {
  setup
  assert_equals "daily" "$(cap_meta_get gamma tier)" || return 1
  assert_equals "beta alpha" "$(cap_meta_get gamma requires)" || return 1
  assert_equals "fallback" "$(cap_meta_get gamma missingkey fallback)" || return 1
  cleanup_test_env
}

test_tier_list_skips_comments() {
  setup
  assert_equals "alpha beta" "$(cap_tier_list core | tr '\n' ' ' | sed 's/ $//')" || return 1
  cleanup_test_env
}

test_order_puts_requires_first_and_dedupes() {
  setup
  assert_equals "alpha beta gamma" "$(cap_order gamma | tr '\n' ' ' | sed 's/ $//')" || return 1
  assert_equals "alpha beta gamma" "$(cap_order beta gamma alpha | tr '\n' ' ' | sed 's/ $//')" || return 1
  cleanup_test_env
}

test_run_executes_script_with_lib_and_env() {
  setup
  local out
  out="$(cap_run alpha install)"
  assert_contains "$out" "install:alpha cap=alpha dir=$TEEUP_CAPS_DIR/alpha" || return 1
  out="$(cap_run alpha configure)"
  assert_contains "$out" "🔹 from lib" "lib functions are available inside the script" || return 1
  assert_contains "$out" "Completed: alpha configure" || return 1
  cleanup_test_env
}

test_run_propagates_failure() {
  setup
  printf '#!/usr/bin/env bash\nfalse\necho unreachable\n' > "$TEEUP_CAPS_DIR/alpha/install"
  local rc=0 out
  out="$(cap_run alpha install)" || rc=$?
  assert_failure "$rc" || return 1
  assert_not_contains "$out" "unreachable" "bash -e stops at the first failure" || return 1
  cleanup_test_env
}

test_run_missing_verb_fails_clearly() {
  setup
  local rc=0 out
  out="$(cap_run alpha doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "alpha has no doctor script" || return 1
  cleanup_test_env
}

test_skipped_reads_teeup_skip() {
  setup
  export TEEUP_SKIP="beta lazyone"
  cap_skipped beta || { echo "beta should be skipped"; return 1; }
  cap_skipped alpha && { echo "alpha should not be skipped"; return 1; }
  cleanup_test_env
}

test_check_passes_on_valid_fixture() {
  setup
  cap_check || { echo "valid fixture should pass"; return 1; }
  cleanup_test_env
}

test_check_reports_problems() {
  setup
  chmod -x "$TEEUP_CAPS_DIR/alpha/install"
  sed -i.bak 's/^tier=daily/tier=weekly/' "$TEEUP_CAPS_DIR/gamma/capability" && rm "$TEEUP_CAPS_DIR/gamma/capability.bak"
  sed -i.bak 's/^provides=""/provides="python3"/' "$TEEUP_CAPS_DIR/lazyone/capability" && rm "$TEEUP_CAPS_DIR/lazyone/capability.bak"
  printf 'alpha\nbeta\nlazyone\n' > "$TEEUP_CAPS_DIR/core.list"
  local rc=0 out
  out="$(cap_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "alpha: install is not executable" || return 1
  assert_contains "$out" "gamma: tier must be core, daily or lazy" || return 1
  assert_contains "$out" "lazyone: provides must not list python3" || return 1
  assert_contains "$out" "lazyone: tier is lazy but it is listed in core.list" || return 1
  cleanup_test_env
}

test_check_reports_duplicate_template_basenames() {
  setup
  # Rendered templates share one flat namespace per mode, so two capabilities
  # shipping the same basename would silently render only one of them.
  mkdir -p "$TEEUP_CAPS_DIR/alpha/themed" "$TEEUP_CAPS_DIR/beta/themed" "$TEEUP_CAPS_DIR/gamma/themed"
  printf 'x\n' > "$TEEUP_CAPS_DIR/alpha/themed/colors.conf.tpl"
  printf 'x\n' > "$TEEUP_CAPS_DIR/gamma/themed/other.conf.tpl"
  cap_check || { echo "distinct basenames should pass"; return 1; }
  printf 'x\n' > "$TEEUP_CAPS_DIR/beta/themed/colors.conf.tpl"
  local rc=0 out
  out="$(cap_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "beta: themed/colors.conf.tpl is also shipped by alpha" || return 1
  cleanup_test_env
}

test_check_rejects_a_bad_provides_token_and_a_duplicate() {
  setup
  # A token with a slash would write the shim somewhere else; a leading dash
  # reads as an option on the shim's exec line.
  make_cap lazytwo lazy "" "gam tools/x"
  sed -i.bak 's/^tier=daily/tier=lazy/' "$TEEUP_CAPS_DIR/gamma/capability" && rm "$TEEUP_CAPS_DIR/gamma/capability.bak"
  : > "$TEEUP_CAPS_DIR/daily.list"
  local rc=0 out
  out="$(cap_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "lazytwo: provides token 'tools/x' is not a plain command name" || return 1
  assert_contains "$out" "lazytwo: provides gam, which gamma already provides" || return 1
  cleanup_test_env
}

test_check_rejects_an_apps_path() {
  setup
  printf 'apps="/Applications/Thing.app"\n' >> "$TEEUP_CAPS_DIR/lazyone/capability"
  local rc=0 out
  out="$(cap_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "lazyone: apps must be application names, not paths" || return 1
  cleanup_test_env
}

test_cap_order_fails_on_unknown_requires() {
  setup
  make_cap orphan core "ghost"
  local rc=0 out
  out="$( (cap_order orphan) 2>&1 )" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Unknown capability: ghost" || return 1
  cleanup_test_env
}

test_run_optional_skips_a_missing_verb() {
  setup
  local out rc=0
  out="$(cap_run_optional alpha theme-apply 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_equals "" "$out" || return 1
  cleanup_test_env
}

test_run_optional_respects_teeup_skip() {
  setup
  printf '#!/usr/bin/env bash\necho "hook:alpha"\n' > "$TEEUP_CAPS_DIR/alpha/theme-apply"
  chmod +x "$TEEUP_CAPS_DIR/alpha/theme-apply"
  export TEEUP_SKIP="alpha"
  local out
  out="$(cap_run_optional alpha theme-apply 2>&1)"
  assert_equals "" "$out" "a skipped capability gets no hook" || return 1
  unset TEEUP_SKIP
  cleanup_test_env
}

# not_applicable is the sanctioned "this machine cannot have this capability"
# answer: cap_run must turn its reserved exit code into a plain success, but
# only report it through TEEUP_CAP_NA, not through the run's own text output.
test_run_returns_not_applicable_without_failing() {
  setup
  printf '#!/usr/bin/env bash\nnot_applicable "no thanks here"\n' > "$TEEUP_CAPS_DIR/alpha/install"
  # Not `out="$(cap_run ...)"`: a command substitution forks a subshell, and
  # TEEUP_CAP_NA is a variable cap_run sets in ITS caller's shell -- it would
  # never escape the subshell for this test to see.
  local rc=0 out_file="$TEST_HOME/out"
  cap_run alpha install >"$out_file" 2>&1 || rc=$?
  assert_success "$rc" "not-applicable is not a failure" || return 1
  assert_equals "true" "$TEEUP_CAP_NA" || return 1
  assert_contains "$(cat "$out_file")" "no thanks here" || return 1
  cleanup_test_env
}

# The reserved exit code alone must never be enough: some other command
# failing to happen to exit 42 is still a real failure, because it never
# wrote the marker file only not_applicable creates.
test_run_a_bare_matching_exit_code_is_still_a_failure() {
  setup
  printf '#!/usr/bin/env bash\nexit 42\n' > "$TEEUP_CAPS_DIR/alpha/install"
  local rc=0
  cap_run alpha install >/dev/null 2>&1 || rc=$?
  assert_equals "42" "$rc" "exit 42 with no marker must not be read as not-applicable" || return 1
  assert_equals "false" "$TEEUP_CAP_NA" || return 1
  cleanup_test_env
}

# cap_install_verbs is what `teeup install` and bootstrap both call: it is
# the one place that decides state_done vs state_na.
test_install_verbs_marks_na_not_done_when_not_applicable() {
  setup
  printf '#!/usr/bin/env bash\nnot_applicable "install: nope"\n' > "$TEEUP_CAPS_DIR/alpha/install"
  cap_install_verbs alpha || { echo "not-applicable must not fail the call"; return 1; }
  state_done check "cap-alpha" && { echo "must not be marked done"; return 1; }
  state_na check "cap-alpha" || { echo "must be marked not-applicable"; return 1; }
  assert_equals "true" "$TEEUP_CAP_NA" || return 1
  cleanup_test_env
}

test_install_verbs_marks_done_on_the_normal_path() {
  setup
  cap_install_verbs alpha || { echo "a normal install/configure must succeed"; return 1; }
  state_done check "cap-alpha" || { echo "must be marked done"; return 1; }
  state_na check "cap-alpha" && { echo "must not be marked not-applicable"; return 1; }
  assert_equals "false" "$TEEUP_CAP_NA" || return 1
  cleanup_test_env
}

# A machine that outgrows a not-applicable answer (macOS upgraded, say) must
# not be stuck showing that stale state once the capability really runs.
test_install_verbs_clears_a_stale_na_marker_once_applicable() {
  setup
  state_na mark "cap-alpha"
  cap_install_verbs alpha || { echo "a normal install/configure must succeed"; return 1; }
  state_na check "cap-alpha" && { echo "stale not-applicable marker must be cleared"; return 1; }
  state_done check "cap-alpha" || { echo "must be marked done"; return 1; }
  cleanup_test_env
}

# A genuine failure must still be a failure: neither marker is touched, and
# the caller (teeup install, bootstrap) sees the same non-zero it always did.
test_install_verbs_propagates_a_real_failure() {
  setup
  printf '#!/usr/bin/env bash\nfalse\n' > "$TEEUP_CAPS_DIR/alpha/install"
  local rc=0
  cap_install_verbs alpha >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" || return 1
  state_done check "cap-alpha" && { echo "must not be marked done on failure"; return 1; }
  state_na check "cap-alpha" && { echo "must not be marked not-applicable on failure"; return 1; }
  cleanup_test_env
}

test_run_optional_warns_but_succeeds_on_failure() {
  setup
  printf '#!/usr/bin/env bash\necho "hook:alpha dir=$TEEUP_THEME_DIR"\nfalse\n' > "$TEEUP_CAPS_DIR/alpha/theme-apply"
  chmod +x "$TEEUP_CAPS_DIR/alpha/theme-apply"
  export TEEUP_THEME_DIR=/tmp/theme
  local out rc=0
  out="$(cap_run_optional alpha theme-apply 2>&1)" || rc=$?
  assert_success "$rc" "an optional hook must never fail its caller" || return 1
  assert_contains "$out" "hook:alpha dir=/tmp/theme" || return 1
  assert_contains "$out" "alpha theme-apply failed; continuing." || return 1
  unset TEEUP_THEME_DIR
  cleanup_test_env
}

echo "lib/capability.sh"
run_test "list and exists" test_list_and_exists
run_test "meta get with default" test_meta_get_with_default
run_test "tier list skips comments" test_tier_list_skips_comments
run_test "order puts requires first and dedupes" test_order_puts_requires_first_and_dedupes
run_test "run executes script with lib and env" test_run_executes_script_with_lib_and_env
run_test "run propagates failure" test_run_propagates_failure
run_test "run missing verb fails clearly" test_run_missing_verb_fails_clearly
run_test "run returns not-applicable without failing" test_run_returns_not_applicable_without_failing
run_test "run treats a bare matching exit code as a real failure" test_run_a_bare_matching_exit_code_is_still_a_failure
run_test "install_verbs marks na not done when not applicable" test_install_verbs_marks_na_not_done_when_not_applicable
run_test "install_verbs marks done on the normal path" test_install_verbs_marks_done_on_the_normal_path
run_test "install_verbs clears a stale na marker once applicable" test_install_verbs_clears_a_stale_na_marker_once_applicable
run_test "install_verbs propagates a real failure" test_install_verbs_propagates_a_real_failure
run_test "skipped reads TEEUP_SKIP" test_skipped_reads_teeup_skip
run_test "check passes on valid fixture" test_check_passes_on_valid_fixture
run_test "check reports problems" test_check_reports_problems
run_test "check reports duplicate template basenames" test_check_reports_duplicate_template_basenames
run_test "check rejects a bad provides token and a duplicate" test_check_rejects_a_bad_provides_token_and_a_duplicate
run_test "check rejects an apps path" test_check_rejects_an_apps_path
run_test "cap_order fails on unknown requires" test_cap_order_fails_on_unknown_requires
run_test "run_optional skips a missing verb" test_run_optional_skips_a_missing_verb
run_test "run_optional respects TEEUP_SKIP" test_run_optional_respects_teeup_skip
run_test "run_optional warns but succeeds on failure" test_run_optional_warns_but_succeeds_on_failure
print_summary
