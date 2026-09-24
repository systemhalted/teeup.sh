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
  assert_equals "$(printf 'widget\tthe widget is bent\tteeup configure widget\tfail')" "$(cat "$REPORT")" || return 1
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

# doctor_unknown <message> <fix-command>
# The third outcome (lib/doctor.sh header): distinct from both doctor_ok and
# doctor_fail, printed with its own symbol, and recorded with kind "unknown"
# rather than silently dropped the way doctor_warn is. It must never be
# recorded as a failure -- that would turn "I could not check this" into
# "I checked, and it is broken", the opposite lie from the one this status
# exists to prevent.
test_unknown_prints_and_records_as_its_own_kind() {
  setup
  local out
  out="$(TEEUP_CAP=widget doctor_unknown "could not tell" "teeup doctor widget" 2>&1)"
  assert_contains "$out" "could not tell" || return 1
  assert_equals "$(printf 'widget\tcould not tell\tteeup doctor widget\tunknown')" "$(cat "$REPORT")" || return 1
  cleanup_test_env
}

# doctor_verdict is tri-state (lib/doctor.sh header): 0 healthy, 1 a
# doctor_fail happened, 2 nothing failed but a doctor_unknown did. A fail in
# the same run as an unknown still returns 1 -- a confirmed problem takes
# priority over an unrelated unknown.
test_verdict_returns_two_for_unknown_alone_and_one_when_a_failure_is_also_present() {
  setup
  doctor_verdict || { echo "a fresh process has no findings"; return 1; }
  TEEUP_CAP=widget doctor_unknown "could not tell" "teeup doctor widget" >/dev/null 2>&1
  local rc=0
  doctor_verdict || rc=$?
  assert_equals "2" "$rc" "an unknown alone must not read as either healthy or a confirmed problem" || return 1
  TEEUP_CAP=widget doctor_fail "bent" "teeup configure widget" >/dev/null 2>&1
  rc=0
  doctor_verdict || rc=$?
  assert_equals "1" "$rc" "a confirmed failure outranks an unrelated unknown in the same run" || return 1
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
# missing -- and must not file it as a *failure* with a fix. It is still a
# doctor_unknown, though, not silence: a check that gives up has to say so
# somewhere the exit status can see, or `teeup doctor` claims a machine is
# healthy that it never actually looked at (the bug three rounds of review
# kept finding in a new place each time). One record, kind "unknown".
test_metadata_check_says_so_when_it_cannot_ask_the_backend() {
  setup
  make_cap widget "ripgrep"
  hide_host_commands brew
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "is not on PATH, so teeup could not check what widget installed" || return 1
  assert_not_contains "$out" "package ripgrep is not installed" || return 1
  assert_equals "1" "$(wc -l < "$REPORT" | tr -d ' ')" "an unanswerable check is still recorded, just not as a failure" || return 1
  assert_contains "$(cat "$REPORT")" "$(printf '\tunknown')" "recorded with kind unknown, not fail" || return 1
  assert_not_contains "$(cat "$REPORT")" "teeup install widget" "an unanswerable check is not a failure with an install fix" || return 1
  cleanup_test_env
}

# A brew that is on PATH but fails every call (a half-finished upgrade, a
# broken prefix, a shim that always exits non-zero) is not "on PATH" in any
# sense doctor can use. `have` alone would pass this gate and doctor would
# then report every package "not installed" -- a flood of confident, wrong
# findings that all point away from the real cause. And once it is on PATH,
# saying "is not on PATH" is simply false (NI3) -- the wording must say what
# was actually established: that it did not answer.
test_metadata_check_says_so_when_the_backend_is_on_path_but_broken() {
  setup
  make_cap widget "ripgrep"
  mock_command brew 1 ""
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "teeup could not get an answer out of brew, so it could not check what widget installed" || return 1
  assert_not_contains "$out" "is not on PATH" "brew is on PATH; that sentence is the one thing just disproved" || return 1
  assert_not_contains "$out" "package ripgrep is not installed" || return 1
  assert_equals "1" "$(wc -l < "$REPORT" | tr -d ' ')" "an unanswerable check is still recorded, just not as a failure" || return 1
  assert_contains "$(cat "$REPORT")" "$(printf '\tunknown')" "recorded with kind unknown, not fail" || return 1
  cleanup_test_env
}

# NI2/mutation gap: dropping the `-n "$out"` requirement (lib/doctor.sh:117,
# exit 0 AND non-empty output both required) was caught by no suite at all,
# and it is exactly the change that silently turned off package and cask
# checking in seven suites whose shared brew mock exits 0 with nothing on
# stdout for `--version`. This pins the contract directly: an exit-0, silent
# backend must read exactly like a non-zero one, never like a real answer.
test_metadata_check_says_so_when_the_backend_answers_nothing() {
  setup
  make_cap widget "ripgrep"
  mock_command_script brew <<'EOF2'
exit 0
EOF2
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "teeup could not get an answer out of brew, so it could not check what widget installed" || return 1
  assert_not_contains "$out" "package ripgrep is not installed" || return 1
  assert_equals "1" "$(wc -l < "$REPORT" | tr -d ' ')" "an unanswerable check is still recorded, just not as a failure" || return 1
  assert_contains "$(cat "$REPORT")" "$(printf '\tunknown')" "recorded with kind unknown, not fail" || return 1
  cleanup_test_env
}

# Minor 4: the backend probe folds stderr into the answer (lib/doctor.sh's
# doctor_backend_can_answer runs `"$cmd" --version 2>&1`), on purpose --
# package-manager/doctor's "did not answer" message wants the error text
# even when the backend only ever writes to stderr. Pinned directly: a brew
# that exits 0 and prints its version on stderr alone must still read as a
# real answer, the same as one that prints it on stdout.
test_backend_can_answer_reads_stdout_and_stderr_alike() {
  setup
  make_cap widget "ripgrep"
  mock_command_script brew <<'EOF2'
case "$1" in --version) echo "Homebrew 4.0.0" >&2; exit 0 ;; esac
case "$1 ${2:-} ${3:-}" in
  "list --formula ripgrep") exit 0 ;;
  *) exit 1 ;;
esac
EOF2
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "package ripgrep is installed" "a stderr-only --version must still count as an answer" || return 1
  assert_equals "" "$(cat "$REPORT")" || return 1
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

# NB3: permissions damage from `sudo ./bootstrap` or a bad umask lands on the
# state tree ROOT, not just done/. `[[ ! -e "$TEEUP_STATE_DIR/done" ]]` used
# to succeed for the wrong reason (a `stat` that failed with EACCES) and a
# fully installed, unreadable machine read as bare, exit 0.
test_state_readable_sees_an_unsearchable_parent_not_just_an_unsearchable_done() {
  setup
  mkdir -p "$TEEUP_STATE_DIR/done"
  doctor_state_readable || { echo "a fresh readable tree must pass"; return 1; }
  chmod 0000 "$TEEUP_STATE_DIR"
  doctor_state_readable && { echo "an unsearchable state root must not pass"; chmod 0755 "$TEEUP_STATE_DIR"; return 1; }
  chmod 0755 "$TEEUP_STATE_DIR"
  cleanup_test_env
}

# NI-C: NB3's own fix still trusted a bare `-e "$TEEUP_STATE_DIR"` once the
# root itself looked searchable -- but `-e` on the root is unsearchable for
# the wrong reason when the root's own PARENT cannot be searched (e.g.
# ~/.local/state left root-owned by a `sudo`-run tool, one directory above
# teeup's own tree), and a fully installed machine read as bare again, one
# level up from where NB3 fixed it.
test_state_readable_sees_an_unsearchable_grandparent_not_just_an_unsearchable_root() {
  setup
  mkdir -p "$TEEUP_STATE_DIR/done"
  doctor_state_readable || { echo "a fresh readable tree must pass"; return 1; }
  local parent
  parent="$(dirname "$TEEUP_STATE_DIR")"
  chmod 0000 "$parent"
  doctor_state_readable && { echo "an unsearchable parent of the state root must not pass"; chmod 0755 "$parent"; return 1; }
  chmod 0755 "$parent"
  cleanup_test_env
}

test_report_state_unreadable_records_a_chmod_fix_not_a_reset() {
  setup
  doctor_report_state_unreadable
  assert_contains "$(cat "$REPORT")" "could not be read" || return 1
  assert_contains "$(cat "$REPORT")" "chmod u+rx" || return 1
  cleanup_test_env
}

# NB3: the failure must name whichever of the two is actually unreadable,
# not always point at done/ -- an unsearchable root is a different problem
# from an unsearchable done/, with the same shaped fix at a different path.
test_report_state_unreadable_names_the_root_when_that_is_the_problem() {
  setup
  mkdir -p "$TEEUP_STATE_DIR/done"
  chmod 0000 "$TEEUP_STATE_DIR"
  doctor_report_state_unreadable
  chmod 0755 "$TEEUP_STATE_DIR"
  assert_contains "$(cat "$REPORT")" "$TEEUP_STATE_DIR could not be read" || return 1
  assert_not_contains "$(cat "$REPORT")" "$TEEUP_STATE_DIR/done could not be read" || return 1
  cleanup_test_env
}

# NI-C: the same naming discipline, one directory further up -- an
# unsearchable parent of the state root is a third distinct problem from
# either the root or done/, and the fix has to chmod the directory that is
# actually broken, not the tree underneath it.
test_report_state_unreadable_names_the_parent_when_that_is_the_problem() {
  setup
  mkdir -p "$TEEUP_STATE_DIR/done"
  local parent
  parent="$(dirname "$TEEUP_STATE_DIR")"
  chmod 0000 "$parent"
  doctor_report_state_unreadable
  chmod 0755 "$parent"
  assert_contains "$(cat "$REPORT")" "$parent could not be read" || return 1
  assert_not_contains "$(cat "$REPORT")" "$TEEUP_STATE_DIR could not be read" || return 1
  assert_not_contains "$(cat "$REPORT")" "$TEEUP_STATE_DIR/done could not be read" || return 1
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

# A report holding only doctor_unknown records is the case this whole status
# exists for: nothing confirmed broken, but something material could not be
# checked, so 0 would be a claim doctor never verified. rc=2, not 0 and not
# 1, and the summary must say "could not verify", never "found N problem(s)"
# (that sentence is reserved for confirmed failures).
test_summary_reports_unknown_only_as_could_not_verify_not_healthy_or_a_problem() {
  setup
  printf 'git\tcould not check signingkey\tchmod u+r foo\tunknown\n' >> "$REPORT"
  local out rc=0
  out="$(doctor_summary "$REPORT" 2>&1)" || rc=$?
  assert_unknown "$rc" || return 1
  assert_not_contains "$out" "everything checked is healthy" || return 1
  assert_not_contains "$out" "found 1 problem" "an unknown is not a confirmed problem" || return 1
  assert_contains "$out" "could not verify 1 item" || return 1
  assert_contains "$out" "git: could not check signingkey" || return 1
  assert_contains "$out" "fix: chmod u+r foo" || return 1
  cleanup_test_env
}

# A confirmed failure and an unrelated unknown in the same report: both are
# named in the summary, but the exit status is 1 -- a real problem outranks
# something merely unverified.
test_summary_reports_both_a_failure_and_an_unknown_but_exits_on_the_failure() {
  setup
  printf 'git\tno signing key\tteeup configure git\tfail\n' >> "$REPORT"
  printf 'github\tcould not check signed-in\tgh auth status\tunknown\n' >> "$REPORT"
  local out rc=0
  out="$(doctor_summary "$REPORT" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "found 1 problem" || return 1
  assert_contains "$out" "could not verify 1 item" || return 1
  assert_contains "$out" "git: no signing key" || return 1
  assert_contains "$out" "github: could not check signed-in" || return 1
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

# A doctor script that only hits doctor_unknown exits 2 (doctor_verdict),
# which is still non-zero -- doctor_run_one's own "exited non-zero without
# saying why" fallback must not fire on top of it: the script DID say why,
# it just was not a failure. Only the one unknown record belongs in the
# report.
test_run_one_does_not_add_a_generic_failure_on_top_of_an_unknown() {
  setup
  make_cap widget
  printf '#!/usr/bin/env bash\ndoctor_unknown "could not tell" "teeup doctor widget"\ndoctor_verdict\n' > "$TEEUP_CAPS_DIR/widget/doctor"
  mock_command brew 1 ""
  doctor_run_one widget >/dev/null 2>&1
  assert_equals "1" "$(wc -l < "$REPORT" | tr -d ' ')" "the unknown record, and nothing on top of it" || return 1
  assert_contains "$(cat "$REPORT")" "could not tell" || return 1
  assert_not_contains "$(cat "$REPORT")" "without saying why" || return 1
  cleanup_test_env
}

# Minor 6: doctor_metadata_check only ever runs through doctor_run_one, but
# every suite's own doctor tests call `cap_run <cap> doctor` directly, which
# runs only the capability's own script and never reaches it -- so the
# `--version` line added to the shared brew mock across seven suites was
# inert for doctor purposes, and package/cask checking rested on this file's
# synthetic `widget` fixture alone. This runs doctor_run_one against a real,
# shipped capability with real packages and no doctor script of its own
# (cli-tools: doctor_metadata_check is the whole of what runs), so the
# package-check path is exercised at the doctor_run_one level against actual
# capability metadata, not only a fixture.
test_run_one_checks_packages_for_a_real_capability_with_no_doctor_script() {
  setup
  TEEUP_CAPS_DIR="$TEEUP_PATH/capabilities"
  mock_command_script brew <<'EOF2'
case "$1" in --version) echo "Homebrew 4.0.0" ;; *) exit 1 ;; esac
EOF2
  local out
  out="$(doctor_run_one cli-tools 2>&1)"
  assert_contains "$out" "package ripgrep is not installed" || return 1
  assert_contains "$(cat "$REPORT")" "package ripgrep is not installed" || return 1
  assert_contains "$(cat "$REPORT")" "teeup install cli-tools" || return 1
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
run_test "unknown prints and records as its own kind" test_unknown_prints_and_records_as_its_own_kind
run_test "verdict returns 2 for unknown alone and 1 when a failure is also present" test_verdict_returns_two_for_unknown_alone_and_one_when_a_failure_is_also_present
run_test "metadata check reports a missing package" test_metadata_check_reports_a_missing_package_with_its_fix
run_test "metadata check says so when it cannot ask the backend" test_metadata_check_says_so_when_it_cannot_ask_the_backend
run_test "metadata check says so when the backend is on PATH but broken" test_metadata_check_says_so_when_the_backend_is_on_path_but_broken
run_test "metadata check says so when the backend answers nothing" test_metadata_check_says_so_when_the_backend_answers_nothing
run_test "backend can answer reads stdout and stderr alike" test_backend_can_answer_reads_stdout_and_stderr_alike
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
run_test "state readable sees an unsearchable parent, not just an unsearchable done" test_state_readable_sees_an_unsearchable_parent_not_just_an_unsearchable_done
run_test "state readable sees an unsearchable grandparent, not just an unsearchable root" test_state_readable_sees_an_unsearchable_grandparent_not_just_an_unsearchable_root
run_test "report state unreadable records a chmod fix, not a reset" test_report_state_unreadable_records_a_chmod_fix_not_a_reset
run_test "report state unreadable names the root when that is the problem" test_report_state_unreadable_names_the_root_when_that_is_the_problem
run_test "report state unreadable names the parent when that is the problem" test_report_state_unreadable_names_the_parent_when_that_is_the_problem
run_test "summary is quiet on an empty report" test_summary_is_quiet_and_zero_when_the_report_is_empty
run_test "summary names every failure and its fix" test_summary_names_every_failure_and_its_fix
run_test "summary reports unknown-only as could-not-verify, not healthy or a problem" test_summary_reports_unknown_only_as_could_not_verify_not_healthy_or_a_problem
run_test "summary reports both a failure and an unknown but exits on the failure" test_summary_reports_both_a_failure_and_an_unknown_but_exits_on_the_failure
run_test "run one records a silent non-zero doctor" test_run_one_records_a_doctor_that_exits_without_saying_why
run_test "run one does not double count" test_run_one_does_not_double_count_a_doctor_that_explained_itself
run_test "run one does not add a generic failure on top of an unknown" test_run_one_does_not_add_a_generic_failure_on_top_of_an_unknown
run_test "run one checks packages for a real capability with no doctor script" test_run_one_checks_packages_for_a_real_capability_with_no_doctor_script
print_summary
