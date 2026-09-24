#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_bootstraps_homebrew_in_dry_run() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install package-manager)"
  assert_contains "$out" "Homebrew/install/HEAD/install.sh" || return 1
  assert_contains "$out" "Would execute: brew update" || return 1
  cleanup_test_env
}

test_install_refuses_missing_macports() {
  setup
  mock_command sw_vers 0 "12.7.1"
  local rc=0 out
  out="$(DRY_RUN=true "$TEEUP" install package-manager 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "MacPorts is not installed" || return 1
  cleanup_test_env
}

test_configure_records_backend_in_answers() {
  setup
  mock_command brew 0 ""
  DRY_RUN=false "$TEEUP" configure package-manager >/dev/null
  assert_contains "$(cat "$TEST_HOME/.config/teeup/answers")" 'TEEUP_PACKAGE_MANAGER="homebrew"' || return 1
  cleanup_test_env
}

test_configure_keeps_existing_answer() {
  setup
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_PACKAGE_MANAGER="macports"\n' > "$TEST_HOME/.config/teeup/answers"
  mock_command port 0 ""
  DRY_RUN=false "$TEEUP" configure package-manager >/dev/null
  assert_contains "$(cat "$TEST_HOME/.config/teeup/answers")" 'TEEUP_PACKAGE_MANAGER="macports"' || return 1
  cleanup_test_env
}

# F1 review sweep: "Recorded package manager: ..." followed answers_set
# unconditionally, so a dry run (which answers_set only previews) claimed the
# backend had been written to the answers file when it had not been.
test_configure_dry_run_does_not_claim_the_backend_was_recorded() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" configure package-manager)"
  assert_contains "$out" "Would set TEEUP_PACKAGE_MANAGER" || return 1
  assert_not_contains "$out" "Recorded package manager" || return 1
  [[ ! -e "$TEST_HOME/.config/teeup/answers" ]] || { echo "answers file written in dry run"; return 1; }
  cleanup_test_env
}

test_configure_real_run_wording_is_unchanged() {
  setup
  mock_command brew 0 ""
  local out
  out="$(DRY_RUN=false "$TEEUP" configure package-manager)"
  assert_contains "$out" "✅ Recorded package manager: homebrew" || return 1
  cleanup_test_env
}

test_doctor_passes_on_a_healthy_machine() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mkdir -p "$TEEUP_PKG_PREFIX/bin"
  export PATH="$TEEUP_PKG_PREFIX/bin:$PATH"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEEUP_PKG_PREFIX/bin/brew"
  chmod +x "$TEEUP_PKG_PREFIX/bin/brew"
  DRY_RUN=false "$TEEUP" configure package-manager >/dev/null
  local rc=0 out
  out="$(DRY_RUN=false cap_run package-manager doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "Homebrew is installed" || return 1
  assert_contains "$out" "recorded in the answers file: homebrew" || return 1
  cleanup_test_env
}

test_doctor_reports_a_backend_that_is_not_on_path() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  hide_host_commands brew
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run package-manager doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  # One true statement per state: with no brew anywhere, "not installed" is
  # the fact. Saying its prefix is also missing from PATH adds nothing and
  # points at a directory that does not exist.
  assert_contains "$out" "Homebrew is not installed" || return 1
  assert_contains "$(cat "$report")" "./bootstrap" || return 1
  cleanup_test_env
}

# Installed, but not where this architecture would put it -- a Homebrew at
# /usr/local on Apple Silicon, or one whose HOMEBREW_PREFIX is exported only
# in an interactive shell. teeup will look in the wrong place, and saying
# "not installed" (or naming the guessed prefix as though it were real) sends
# the user to reinstall something that is already there.
test_doctor_names_the_prefix_the_backend_is_really_at() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  local elsewhere="$TEST_HOME/opt/other brew"
  mkdir -p "$elsewhere/bin"
  printf '#!/usr/bin/env bash
exit 0
' > "$elsewhere/bin/brew"
  chmod +x "$elsewhere/bin/brew"
  rm -f "$MOCK_BIN/brew"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(PATH="$elsewhere/bin:$PATH" DRY_RUN=false cap_run package-manager doctor 2>&1)" || rc=$?
  assert_contains "$out" "Homebrew is installed under $elsewhere" || return 1
  assert_contains "$out" "teeup looks for it under" || return 1
  assert_not_contains "$out" "Homebrew is not installed" || return 1
  cleanup_test_env
}

# I5: `brew` on PATH but failing on every call must not be reported
# "installed" -- everything downstream (every other capability's package
# lines) reads doctor_backend_can_answer's "have brew" as proof the backend
# can be asked, and this doctor must not certify a backend that cannot.
test_doctor_reports_a_backend_that_is_on_path_but_unreachable() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mkdir -p "$TEEUP_PKG_PREFIX/bin"
  export PATH="$TEEUP_PKG_PREFIX/bin:$PATH"
  printf '#!/usr/bin/env bash\necho "brew: fatal error" >&2\nexit 1\n' > "$TEEUP_PKG_PREFIX/bin/brew"
  chmod +x "$TEEUP_PKG_PREFIX/bin/brew"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run package-manager doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "did not answer" || return 1
  assert_not_contains "$out" "Homebrew is installed under" || return 1
  cleanup_test_env
}

# I4: pkg_prefix hardcodes /opt/local for MacPorts and never reads
# HOMEBREW_PREFIX, so offering that fix on a MacPorts machine names a
# variable that changes nothing.
test_doctor_does_not_offer_the_homebrew_prefix_fix_on_macports() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  export TEEUP_PACKAGE_MANAGER=macports
  local elsewhere="$TEST_HOME/mp"
  mkdir -p "$elsewhere/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$elsewhere/bin/port"
  chmod +x "$elsewhere/bin/port"
  local rc=0 out
  out="$(PATH="$elsewhere/bin:$PATH" DRY_RUN=false cap_run package-manager doctor 2>&1)" || true
  assert_contains "$out" "MacPorts is installed under $elsewhere" || return 1
  assert_contains "$out" "teeup looks for it under" || return 1
  assert_not_contains "$out" "HOMEBREW_PREFIX" || return 1
  assert_contains "$out" "MacPorts prefix is fixed" || return 1
  cleanup_test_env
}

test_doctor_says_when_the_machine_file_pins_another_backend() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR"
  printf 'TEEUP_PACKAGE_MANAGER="macports"\n' > "$TEEUP_MACHINES_DIR/testmac.conf"
  answers_set TEEUP_PACKAGE_MANAGER homebrew
  local out
  out="$(DRY_RUN=false cap_run package-manager doctor 2>&1)" || true
  assert_contains "$out" "pins TEEUP_PACKAGE_MANAGER=macports" || return 1
  cleanup_test_env
}

echo "capabilities/package-manager"
run_test "install bootstraps Homebrew in dry run" test_install_bootstraps_homebrew_in_dry_run
run_test "install refuses missing MacPorts" test_install_refuses_missing_macports
run_test "configure records backend in answers" test_configure_records_backend_in_answers
run_test "configure keeps existing answer" test_configure_keeps_existing_answer
run_test "doctor passes on a healthy machine" test_doctor_passes_on_a_healthy_machine
run_test "doctor reports a backend not on PATH" test_doctor_reports_a_backend_that_is_not_on_path
run_test "doctor names the prefix the backend is really at" test_doctor_names_the_prefix_the_backend_is_really_at
run_test "doctor reports a backend that is on PATH but unreachable" test_doctor_reports_a_backend_that_is_on_path_but_unreachable
run_test "doctor does not offer the Homebrew prefix fix on MacPorts" test_doctor_does_not_offer_the_homebrew_prefix_fix_on_macports
run_test "doctor says when the machine file pins another backend" test_doctor_says_when_the_machine_file_pins_another_backend
run_test "configure dry run does not claim the backend was recorded" test_configure_dry_run_does_not_claim_the_backend_was_recorded
run_test "configure real-run wording is unchanged" test_configure_real_run_wording_is_unchanged
print_summary
