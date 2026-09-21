#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# A capability tree of fixtures, so the metadata check is tested against
# metadata this file controls rather than against whatever teeup ships.
make_cap() {
  local name="$1" packages="${2:-}" casks="${3:-}" apps="${4:-}" provides="${5:-}"
  local dir="$TEEUP_CAPS_DIR/$name"
  mkdir -p "$dir"
  printf 'summary="Fixture %s"\ngroup=system\ntier=lazy\nrequires=""\nprovides="%s"\npackages="%s"\ncasks="%s"\napps="%s"\ninteractive=false\n' \
    "$name" "$provides" "$packages" "$casks" "$apps" > "$dir/capability"
  printf '#!/usr/bin/env bash\n:\n' > "$dir/install"
  printf '#!/usr/bin/env bash\n:\n' > "$dir/configure"
  chmod +x "$dir/install" "$dir/configure"
}

setup() {
  setup_test_env
  mock_macos_base
  # A config dir whose name carries a space and three characters that are
  # special to sed, awk and the shell, so every path this library builds is
  # exercised against one.
  export TEEUP_CONFIG_DIR="$TEST_HOME/con fig \$x & 'q'/teeup"
  export TEEUP_STATE_DIR="$TEST_HOME/sta te \$x & 'q'/teeup"
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  mkdir -p "$TEEUP_CAPS_DIR" "$TEEUP_APPS_DIR"
  source "$TEEUP_PATH/lib/all.sh"
  REPORT="$TEST_HOME/report"
  : > "$REPORT"
  export TEEUP_DOCTOR_REPORT="$REPORT"
}

test_fail_prints_and_records_against_the_current_capability() {
  setup
  local out
  out="$(TEEUP_CAP=widget doctor_fail "the widget is bent" "teeup configure widget" 2>&1)"
  assert_contains "$out" "the widget is bent" || return 1
  assert_equals "widget	the widget is bent	teeup configure widget" "$(cat "$REPORT")" || return 1
  cleanup_test_env
}

test_fail_flattens_tabs_and_newlines_so_one_failure_is_one_record() {
  setup
  TEEUP_CAP=widget doctor_fail "$(printf 'two\tparts\nand a line')" "$(printf 'teeup\tconfigure widget')" >/dev/null 2>&1
  assert_equals "1" "$(wc -l < "$REPORT" | tr -d ' ')" "one failure must be one line" || return 1
  assert_contains "$(cat "$REPORT")" "two parts and a line" || return 1
  cleanup_test_env
}

test_record_without_a_report_is_a_no_op() {
  setup
  export TEEUP_DOCTOR_REPORT=""
  doctor_record widget "nothing collects this" "teeup help" || return 1
  assert_equals "" "$(cat "$REPORT")" || return 1
  cleanup_test_env
}

test_verdict_is_zero_until_something_fails() {
  setup
  doctor_verdict || { echo "a fresh process has no failures"; return 1; }
  TEEUP_CAP=widget doctor_fail "bent" "teeup configure widget" >/dev/null 2>&1
  doctor_verdict && { echo "verdict must fail after doctor_fail"; return 1; }
  cleanup_test_env
}

test_metadata_check_reports_a_missing_package_with_its_fix() {
  setup
  make_cap widget "ripgrep"
  hide_host_commands brew
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "package ripgrep is not installed" || return 1
  assert_contains "$(cat "$REPORT")" "teeup install widget" || return 1
  cleanup_test_env
}

test_metadata_check_passes_when_the_package_manager_lists_it() {
  setup
  make_cap widget "ripgrep"
  mock_command_script brew <<'EOF2'
case "$1 ${2:-} ${3:-}" in
  "list --formula ripgrep") exit 0 ;;
  *) exit 1 ;;
esac
EOF2
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "package ripgrep is installed" || return 1
  assert_equals "" "$(cat "$REPORT")" || return 1
  cleanup_test_env
}

test_metadata_check_reports_a_missing_app() {
  setup
  make_cap widget "" "" "Widget Studio"
  mock_command brew 1 ""
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "Widget Studio.app is not installed" || return 1
  assert_contains "$(cat "$REPORT")" "teeup install widget" || return 1
  mkdir -p "$TEEUP_APPS_DIR/Widget Studio.app"
  : > "$REPORT"
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "Widget Studio.app is installed" || return 1
  assert_equals "" "$(cat "$REPORT")" || return 1
  cleanup_test_env
}

test_metadata_check_skips_casks_on_macports() {
  setup
  make_cap widget "" "widget-app"
  export TEEUP_PACKAGE_MANAGER=macports
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "casks are not available with MacPorts" || return 1
  assert_equals "" "$(cat "$REPORT")" "a MacPorts machine must not be told to install a cask" || return 1
  cleanup_test_env
}

test_metadata_check_rejects_a_command_that_is_only_a_shim() {
  setup
  make_cap widget "" "" "" "frob"
  mock_command brew 1 ""
  mkdir -p "$(shims_dir)"
  printf '#!/usr/bin/env bash\n:\n' > "$(shims_dir)/frob"
  chmod +x "$(shims_dir)/frob"
  PATH="$PATH:$(shims_dir)"
  export PATH
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "frob is not on PATH" || return 1
  assert_contains "$(cat "$REPORT")" "teeup install widget" || return 1
  cleanup_test_env
}

test_targets_are_the_installed_capabilities_in_order() {
  setup
  make_cap alpha
  make_cap beta
  make_cap gamma
  state_done mark cap-gamma
  state_done mark cap-alpha
  assert_equals "alpha
gamma" "$(doctor_targets)" || return 1
  assert_equals "gamma" "$(TEEUP_SKIP=alpha doctor_targets)" || return 1
  cleanup_test_env
}

test_summary_is_quiet_and_zero_when_the_report_is_empty() {
  setup
  local out rc=0
  out="$(doctor_summary "$REPORT" 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "everything checked is healthy" || return 1
  cleanup_test_env
}

test_summary_names_every_failure_and_its_fix() {
  setup
  printf 'git\tno signing key\tteeup configure git\n' >> "$REPORT"
  printf 'zsh\tnot the login shell\tchsh -s /bin/zsh\n' >> "$REPORT"
  local out rc=0
  out="$(doctor_summary "$REPORT" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "found 2 problem" || return 1
  assert_contains "$out" "git: no signing key" || return 1
  assert_contains "$out" "fix: teeup configure git" || return 1
  assert_contains "$out" "fix: chsh -s /bin/zsh" || return 1
  cleanup_test_env
}

test_run_one_records_a_doctor_that_exits_without_saying_why() {
  setup
  make_cap widget
  printf '#!/usr/bin/env bash\nexit 3\n' > "$TEEUP_CAPS_DIR/widget/doctor"
  mock_command brew 1 ""
  doctor_run_one widget >/dev/null 2>&1
  assert_contains "$(cat "$REPORT")" "exited non-zero without saying why" || return 1
  cleanup_test_env
}

test_run_one_does_not_double_count_a_doctor_that_explained_itself() {
  setup
  make_cap widget
  printf '#!/usr/bin/env bash\ndoctor_fail "the widget is bent" "teeup configure widget"\ndoctor_verdict\n' > "$TEEUP_CAPS_DIR/widget/doctor"
  mock_command brew 1 ""
  doctor_run_one widget >/dev/null 2>&1
  assert_equals "1" "$(wc -l < "$REPORT" | tr -d ' ')" || return 1
  assert_contains "$(cat "$REPORT")" "the widget is bent" || return 1
  cleanup_test_env
}

echo "lib/doctor.sh"
run_test "fail prints and records against the current capability" test_fail_prints_and_records_against_the_current_capability
run_test "fail flattens tabs and newlines" test_fail_flattens_tabs_and_newlines_so_one_failure_is_one_record
run_test "record without a report is a no-op" test_record_without_a_report_is_a_no_op
run_test "verdict is zero until something fails" test_verdict_is_zero_until_something_fails
run_test "metadata check reports a missing package" test_metadata_check_reports_a_missing_package_with_its_fix
run_test "metadata check passes when listed" test_metadata_check_passes_when_the_package_manager_lists_it
run_test "metadata check reports a missing app" test_metadata_check_reports_a_missing_app
run_test "metadata check skips casks on macports" test_metadata_check_skips_casks_on_macports
run_test "metadata check rejects a shim-only command" test_metadata_check_rejects_a_command_that_is_only_a_shim
run_test "targets are the installed capabilities" test_targets_are_the_installed_capabilities_in_order
run_test "summary is quiet on an empty report" test_summary_is_quiet_and_zero_when_the_report_is_empty
run_test "summary names every failure and its fix" test_summary_names_every_failure_and_its_fix
run_test "run one records a silent non-zero doctor" test_run_one_records_a_doctor_that_exits_without_saying_why
run_test "run one does not double count" test_run_one_does_not_double_count_a_doctor_that_explained_itself
print_summary
