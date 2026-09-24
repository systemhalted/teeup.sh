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
  # A brew that answers --version (so doctor_backend_can_answer trusts it),
  # and answers no on the package itself. Hiding brew entirely is a
  # different state -- teeup cannot check at all -- and has its own test
  # below; so is one that is on PATH but cannot even answer --version.
  mock_command_script brew <<'EOF2'
case "$1" in --version) echo "Homebrew 4.0.0" ;; *) exit 1 ;; esac
EOF2
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "package ripgrep is not installed" || return 1
  assert_contains "$(cat "$REPORT")" "teeup install widget" || return 1
  cleanup_test_env
}

# "not installed" and "teeup could not find out" are different answers, and
# only one of them is a problem the user can fix. Without the backend's own
# command there is nothing to ask, so doctor must not assert the package is
# missing -- and must not file it as a failure with a fix.
test_metadata_check_says_so_when_it_cannot_ask_the_backend() {
  setup
  make_cap widget "ripgrep"
  hide_host_commands brew
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "is not on PATH, so teeup could not check what widget installed" || return 1
  assert_not_contains "$out" "package ripgrep is not installed" || return 1
  assert_equals "" "$(cat "$REPORT")" "an unanswerable check is not a failure with a fix" || return 1
  cleanup_test_env
}

# A brew that is on PATH but fails every call (a half-finished upgrade, a
# broken prefix, a shim that always exits non-zero) is not "on PATH" in any
# sense doctor can use. `have` alone would pass this gate and doctor would
# then report every package "not installed" -- a flood of confident, wrong
# findings that all point away from the real cause.
test_metadata_check_says_so_when_the_backend_is_on_path_but_broken() {
  setup
  make_cap widget "ripgrep"
  mock_command brew 1 ""
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "is not on PATH, so teeup could not check what widget installed" || return 1
  assert_not_contains "$out" "package ripgrep is not installed" || return 1
  assert_equals "" "$(cat "$REPORT")" "an unanswerable check is not a failure with a fix" || return 1
  cleanup_test_env
}

test_metadata_check_passes_when_the_package_manager_lists_it() {
  setup
  make_cap widget "ripgrep"
  mock_command_script brew <<'EOF2'
case "$1" in --version) echo "Homebrew 4.0.0"; exit 0 ;; esac
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

# An empty report with checked=false means nothing was looked at, not that
# everything looked at passed. Silence, not a false "healthy" (B4).
test_summary_says_nothing_when_nothing_was_checked() {
  setup
  local out rc=0
  out="$(doctor_summary "$REPORT" false 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_not_contains "$out" "everything checked is healthy" || return 1
  cleanup_test_env
}

test_state_readable_sees_a_done_dir_it_cannot_search() {
  setup
  mkdir -p "$TEEUP_STATE_DIR/done"
  doctor_state_readable || { echo "a fresh readable done/ must pass"; return 1; }
  chmod 0000 "$TEEUP_STATE_DIR/done"
  doctor_state_readable && { echo "an unreadable done/ must not pass"; chmod 0755 "$TEEUP_STATE_DIR/done"; return 1; }
  chmod 0755 "$TEEUP_STATE_DIR/done"
  cleanup_test_env
}

test_state_readable_treats_a_missing_done_dir_as_a_bare_machine() {
  setup
  rm -rf "$TEEUP_STATE_DIR/done"
  doctor_state_readable || { echo "a machine that never wrote done/ is not unreadable"; return 1; }
  cleanup_test_env
}

test_report_state_unreadable_records_a_chmod_fix_not_a_reset() {
  setup
  doctor_report_state_unreadable
  assert_contains "$(cat "$REPORT")" "could not be read" || return 1
  assert_contains "$(cat "$REPORT")" "chmod u+rx" || return 1
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
# A capability this machine cannot have is healthy, not broken. Checking its
# metadata would call every package it names missing, file a failure with a
# `teeup install` fix that answers not-applicable and changes nothing, and
# make `teeup doctor` exit 1 on a machine that is exactly as it should be.
test_run_one_leaves_a_not_applicable_capability_alone() {
  setup
  make_cap widget "ripgrep" "widget-app"
  mock_command brew 1 ""
  state_na mark "cap-widget"
  local out
  out="$(doctor_run_one widget 2>&1)"
  assert_contains "$out" "not applicable on this machine, so there is nothing to check" || return 1
  assert_not_contains "$out" "package ripgrep is not installed" || return 1
  assert_equals "" "$(cat "$REPORT")" "a not-applicable capability is not a problem to fix" || return 1
  cleanup_test_env
}

# "Nothing is installed" and "everything installed is skipped here" are
# different facts. Saying the first sends the user to ./bootstrap over a
# machine that is set up exactly as its machine file asks.
test_installed_any_sees_past_teeup_skip() {
  setup
  make_cap widget "" ""
  doctor_installed_any && { echo "nothing is installed yet"; return 1; }
  state_done mark "cap-widget"
  doctor_installed_any || { echo "an installed capability must be seen"; return 1; }
  TEEUP_SKIP=widget
  export TEEUP_SKIP
  assert_equals "" "$(doctor_targets)" "a skipped capability is not a target" || return 1
  doctor_installed_any || { echo "a skipped capability is still installed"; return 1; }
  unset TEEUP_SKIP
  cleanup_test_env
}

run_test "fail prints and records against the current capability" test_fail_prints_and_records_against_the_current_capability
run_test "fail flattens tabs and newlines" test_fail_flattens_tabs_and_newlines_so_one_failure_is_one_record
run_test "record without a report is a no-op" test_record_without_a_report_is_a_no_op
run_test "verdict is zero until something fails" test_verdict_is_zero_until_something_fails
run_test "metadata check reports a missing package" test_metadata_check_reports_a_missing_package_with_its_fix
run_test "metadata check says so when it cannot ask the backend" test_metadata_check_says_so_when_it_cannot_ask_the_backend
run_test "metadata check says so when the backend is on PATH but broken" test_metadata_check_says_so_when_the_backend_is_on_path_but_broken
run_test "metadata check passes when listed" test_metadata_check_passes_when_the_package_manager_lists_it
run_test "metadata check reports a missing app" test_metadata_check_reports_a_missing_app
run_test "metadata check skips casks on macports" test_metadata_check_skips_casks_on_macports
run_test "metadata check rejects a shim-only command" test_metadata_check_rejects_a_command_that_is_only_a_shim
run_test "run one leaves a not-applicable capability alone" test_run_one_leaves_a_not_applicable_capability_alone
run_test "installed_any sees past TEEUP_SKIP" test_installed_any_sees_past_teeup_skip
run_test "targets are the installed capabilities" test_targets_are_the_installed_capabilities_in_order
run_test "summary says nothing when nothing was checked" test_summary_says_nothing_when_nothing_was_checked
run_test "state readable sees a done dir it cannot search" test_state_readable_sees_a_done_dir_it_cannot_search
run_test "state readable treats a missing done dir as a bare machine" test_state_readable_treats_a_missing_done_dir_as_a_bare_machine
run_test "report state unreadable records a chmod fix, not a reset" test_report_state_unreadable_records_a_chmod_fix_not_a_reset
run_test "summary is quiet on an empty report" test_summary_is_quiet_and_zero_when_the_report_is_empty
run_test "summary names every failure and its fix" test_summary_names_every_failure_and_its_fix
run_test "run one records a silent non-zero doctor" test_run_one_records_a_doctor_that_exits_without_saying_why
run_test "run one does not double count" test_run_one_does_not_double_count_a_doctor_that_explained_itself
print_summary
