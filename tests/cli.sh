#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/helper.sh"

make_cap() {
  local name="$1" tier="$2" requires="${3:-}"
  local dir="$TEEUP_CAPS_DIR/$name"
  mkdir -p "$dir"
  printf 'summary="Fixture %s"\ngroup=system\ntier=%s\nrequires="%s"\nprovides=""\ninteractive=false\n' "$name" "$tier" "$requires" > "$dir/capability"
  printf '#!/usr/bin/env bash\necho "install:%s"\n' "$name" > "$dir/install"
  printf '#!/usr/bin/env bash\necho "configure:%s"\n' "$name" > "$dir/configure"
  chmod +x "$dir/install" "$dir/configure"
}

setup() {
  setup_test_env
  mock_macos_base
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR"
  make_cap alpha core
  make_cap beta core alpha
  make_cap lazyone lazy
  printf 'alpha\nbeta\n' > "$TEEUP_CAPS_DIR/core.list"
  : > "$TEEUP_CAPS_DIR/daily.list"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_runs_requires_in_order_and_marks_done() {
  setup
  local out
  out="$("$TEEUP" install beta)"
  local a b
  a="$(printf '%s\n' "$out" | grep -n 'install:alpha' | cut -d: -f1)"
  b="$(printf '%s\n' "$out" | grep -n 'install:beta' | cut -d: -f1)"
  [[ "$a" -lt "$b" ]] || { echo "alpha must install before beta"; return 1; }
  assert_contains "$out" "configure:beta" || return 1
  "$TEEUP" has beta || { echo "beta should be marked installed"; return 1; }
  "$TEEUP" has alpha || { echo "alpha should be marked installed"; return 1; }
  "$TEEUP" has lazyone && { echo "lazyone must not be marked"; return 1; }
  cleanup_test_env
}

test_install_refuses_skipped_capability() {
  setup
  local rc=0 out
  out="$(TEEUP_SKIP=beta "$TEEUP" install beta 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "beta is skipped on this machine (TEEUP_SKIP)" || return 1
  cleanup_test_env
}

test_install_unknown_capability() {
  setup
  local rc=0 out
  out="$("$TEEUP" install nope 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Unknown capability: nope" || return 1
  cleanup_test_env
}

test_configure_only() {
  setup
  local out
  out="$("$TEEUP" configure alpha)"
  assert_contains "$out" "configure:alpha" || return 1
  assert_not_contains "$out" "install:alpha" || return 1
  cleanup_test_env
}

test_list_shows_tier_and_summary() {
  setup
  local out
  out="$("$TEEUP" list)"
  assert_contains "$out" "alpha" || return 1
  assert_contains "$out" "core" || return 1
  assert_contains "$out" "Fixture alpha" || return 1
  out="$("$TEEUP" list --tier lazy)"
  assert_contains "$out" "lazyone" || return 1
  assert_not_contains "$out" "alpha" || return 1
  cleanup_test_env
}

test_status_reports_backend_and_installed() {
  setup
  "$TEEUP" install alpha >/dev/null
  local out
  out="$("$TEEUP" status)"
  assert_contains "$out" "Package manager: homebrew" || return 1
  assert_contains "$out" "Installed: 1 of 3" || return 1
  assert_contains "$out" "Answers: missing" || return 1
  cleanup_test_env
}

test_commands_check_delegates_to_cap_check() {
  setup
  "$TEEUP" commands --check || { echo "valid fixture should pass"; return 1; }
  chmod -x "$TEEUP_CAPS_DIR/alpha/install"
  "$TEEUP" commands --check >/dev/null 2>&1 && { echo "should fail"; return 1; }
  cleanup_test_env
}

test_unknown_verb_exits_2() {
  setup
  local rc=0
  "$TEEUP" frobnicate >/dev/null 2>&1 || rc=$?
  assert_equals "2" "$rc" || return 1
  cleanup_test_env
}

test_help_lists_verbs() {
  setup
  assert_contains "$("$TEEUP" help)" "teeup install <capability>" || return 1
  cleanup_test_env
}

test_dry_run_env_reaches_scripts() {
  setup
  printf '#!/usr/bin/env bash\nrun_cmd touch "$HOME/made"\n' > "$TEEUP_CAPS_DIR/alpha/install"
  DRY_RUN=true "$TEEUP" install alpha >/dev/null
  [[ ! -e "$TEST_HOME/made" ]] || { echo "dry run must not touch files"; return 1; }
  cleanup_test_env
}

echo "bin/teeup"
run_test "install runs requires in order and marks done" test_install_runs_requires_in_order_and_marks_done
run_test "install refuses skipped capability" test_install_refuses_skipped_capability
run_test "install unknown capability" test_install_unknown_capability
run_test "configure only" test_configure_only
run_test "list shows tier and summary" test_list_shows_tier_and_summary
run_test "status reports backend and installed" test_status_reports_backend_and_installed
run_test "commands --check delegates" test_commands_check_delegates_to_cap_check
run_test "unknown verb exits 2" test_unknown_verb_exits_2
run_test "help lists verbs" test_help_lists_verbs
run_test "dry run env reaches scripts" test_dry_run_env_reaches_scripts
print_summary
