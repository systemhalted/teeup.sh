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

echo "lib/capability.sh"
run_test "list and exists" test_list_and_exists
run_test "meta get with default" test_meta_get_with_default
run_test "tier list skips comments" test_tier_list_skips_comments
run_test "order puts requires first and dedupes" test_order_puts_requires_first_and_dedupes
run_test "run executes script with lib and env" test_run_executes_script_with_lib_and_env
run_test "run propagates failure" test_run_propagates_failure
run_test "run missing verb fails clearly" test_run_missing_verb_fails_clearly
run_test "skipped reads TEEUP_SKIP" test_skipped_reads_teeup_skip
run_test "check passes on valid fixture" test_check_passes_on_valid_fixture
run_test "check reports problems" test_check_reports_problems
print_summary
