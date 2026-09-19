#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/helper.sh"

make_cap() {
  local name="$1" tier="$2" requires="${3:-}" provides="${4:-}" apps="${5:-}"
  local dir="$TEEUP_CAPS_DIR/$name"
  mkdir -p "$dir"
  printf 'summary="Fixture %s"\ngroup=system\ntier=%s\nrequires="%s"\nprovides="%s"\napps="%s"\ninteractive=false\n' "$name" "$tier" "$requires" "$provides" "$apps" > "$dir/capability"
  printf '#!/usr/bin/env bash\necho "install:%s"\n' "$name" > "$dir/install"
  printf '#!/usr/bin/env bash\necho "configure:%s"\n' "$name" > "$dir/configure"
  chmod +x "$dir/install" "$dir/configure"
}

# A fixture whose install says not_applicable instead of actually installing.
make_na_cap() {
  local name="$1" tier="$2" requires="${3:-}"
  local dir="$TEEUP_CAPS_DIR/$name"
  mkdir -p "$dir"
  printf 'summary="Fixture %s"\ngroup=system\ntier=%s\nrequires="%s"\nprovides=""\ninteractive=false\n' "$name" "$tier" "$requires" > "$dir/capability"
  printf '#!/usr/bin/env bash\nnot_applicable "install: %s cannot run on this machine"\n' "$name" > "$dir/install"
  printf '#!/usr/bin/env bash\necho "configure:%s"\n' "$name" > "$dir/configure"
  chmod +x "$dir/install" "$dir/configure"
}

# A fixture whose install genuinely fails.
make_failing_cap() {
  local name="$1" tier="$2" requires="${3:-}"
  local dir="$TEEUP_CAPS_DIR/$name"
  mkdir -p "$dir"
  printf 'summary="Fixture %s"\ngroup=system\ntier=%s\nrequires="%s"\nprovides=""\ninteractive=false\n' "$name" "$tier" "$requires" > "$dir/capability"
  printf '#!/usr/bin/env bash\necho "install:%s about to fail"\nfalse\n' "$name" > "$dir/install"
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
  make_cap lazyone lazy "" "frob" ""
  make_cap sketch lazy "" "" "Sketch Pad"
  printf 'alpha\nbeta\n' > "$TEEUP_CAPS_DIR/core.list"
  : > "$TEEUP_CAPS_DIR/daily.list"
  TEEUP="$TEEUP_PATH/bin/teeup"
  # lazy-run and launch ask through ui_confirm and probe /Applications; keep
  # both away from gum and from the real folder.
  export TEEUP_NO_GUM=1
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
}

# lazyone's install puts a real `frob` on PATH (in MOCK_BIN, ahead of the
# shims), the way a package install would; the binary echoes its arguments so
# the exec at the end of lazy-run can be checked.
make_frob_installable() {
  cat > "$TEEUP_CAPS_DIR/lazyone/install" <<EOF2
#!/usr/bin/env bash
echo "install:lazyone"
printf '#!/usr/bin/env bash\necho "frob ran: \$*"\n' > "$MOCK_BIN/frob"
chmod +x "$MOCK_BIN/frob"
EOF2
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
  assert_contains "$out" "Installed: 1 of 4" || return 1
  assert_contains "$out" "Answers: missing" || return 1
  cleanup_test_env
}

# A machine this capability cannot run on at all: bootstrap/`teeup install`
# still succeeds, nothing is marked done, `teeup has` still reports
# not-installed, and `status` says so as its own state.
test_install_records_not_applicable_and_has_reports_not_installed() {
  setup
  make_na_cap gamma core
  printf 'alpha\nbeta\ngamma\n' > "$TEEUP_CAPS_DIR/core.list"
  local out rc=0
  out="$("$TEEUP" install gamma 2>&1)" || rc=$?
  assert_success "$rc" "not-applicable must not fail teeup install" || return 1
  assert_contains "$out" "gamma cannot run on this machine" || return 1
  local has_rc=0
  "$TEEUP" has gamma >/dev/null 2>&1 || has_rc=$?
  assert_failure "$has_rc" "gamma must not report installed" || return 1
  cleanup_test_env
}

test_status_shows_not_applicable_as_its_own_state() {
  setup
  make_na_cap gamma core
  printf 'alpha\nbeta\ngamma\n' > "$TEEUP_CAPS_DIR/core.list"
  "$TEEUP" install gamma >/dev/null 2>&1
  local out
  out="$("$TEEUP" status)"
  assert_contains "$out" "not applicable on this machine" || return 1
  assert_not_contains "$out" "gamma              installed" || return 1
  assert_contains "$out" "Not applicable on this machine: 1" || return 1
  cleanup_test_env
}

# A capability that genuinely fails must still abort teeup install -- the
# not-applicable path must never be a way to mask a real failure.
test_install_still_aborts_on_a_real_failure() {
  setup
  make_failing_cap gamma core
  printf 'alpha\nbeta\ngamma\n' > "$TEEUP_CAPS_DIR/core.list"
  local rc=0
  "$TEEUP" install gamma >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "a genuinely failing capability must still abort" || return 1
  local has_rc=0
  "$TEEUP" has gamma >/dev/null 2>&1 || has_rc=$?
  assert_failure "$has_rc" "gamma must not report installed on failure" || return 1
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
  assert_contains "$("$TEEUP" help)" "teeup install font list" || return 1
  assert_contains "$("$TEEUP" help)" "teeup lazy-run <cap> <cmd> [args]" || return 1
  cleanup_test_env
}

test_teeup_path_derives_from_location() {
  setup
  assert_equals "0.1.0-dev" "$(TEEUP_PATH=/nonexistent "$TEEUP" version)" || return 1
  cleanup_test_env
}

test_dry_run_env_reaches_scripts() {
  setup
  printf '#!/usr/bin/env bash\nrun_cmd touch "$HOME/made"\n' > "$TEEUP_CAPS_DIR/alpha/install"
  DRY_RUN=true "$TEEUP" install alpha >/dev/null
  [[ ! -e "$TEST_HOME/made" ]] || { echo "dry run must not touch files"; return 1; }
  cleanup_test_env
}

test_configure_refuses_skipped_capability() {
  setup
  local rc=0 out
  out="$(TEEUP_SKIP=alpha "$TEEUP" configure alpha 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "alpha is skipped on this machine (TEEUP_SKIP)" || return 1
  cleanup_test_env
}

# seed_shadowed_machine_files -> both the user's own machine file and the
# checkout's exist for "testmac" (mock_macos_base's hostname), so
# answers_load has something to announce. TEEUP_CONFIG_DIR is left at its
# default (derived from XDG_CONFIG_HOME, set by setup_test_env) so it need
# not be threaded through by hand.
seed_shadowed_machine_files() {
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR"
  printf 'TEEUP_PACKAGE_MANAGER="homebrew"\n' > "$TEEUP_MACHINES_DIR/testmac.conf"
  mkdir -p "$XDG_CONFIG_HOME/teeup/machines"
  printf 'TEEUP_PACKAGE_MANAGER="homebrew"\n' > "$XDG_CONFIG_HOME/teeup/machines/testmac.conf"
}

# A verb whose stdout is data, not a report, must stay machine-readable even
# when answers_load has a shadowed-machine-file notice to give: the notice
# has to land on stderr, never mixed into the value a caller is capturing
# (teeup-env, `x=$(teeup secret get ...)`, and friends).
test_data_verbs_keep_stdout_clean_with_a_shadowed_machine_file() {
  setup
  seed_shadowed_machine_files
  mock_command security 0 "s3cr3t"
  local out errfile
  errfile="$TEST_HOME/stderr.out"

  out="$("$TEEUP" version 2>"$errfile")"
  assert_equals "0.1.0-dev" "$out" "version stdout" || return 1
  assert_contains "$(cat "$errfile")" "also exists and is ignored" "version stderr" || return 1

  out="$("$TEEUP" theme current 2>"$errfile")"
  assert_equals "none" "$out" "theme current stdout" || return 1
  assert_contains "$(cat "$errfile")" "also exists and is ignored" "theme current stderr" || return 1

  out="$("$TEEUP" theme list 2>"$errfile")"
  assert_equals "catppuccin" "$out" "theme list stdout" || return 1
  assert_contains "$(cat "$errfile")" "also exists and is ignored" "theme list stderr" || return 1

  out="$("$TEEUP" secret get mysecret 2>"$errfile")"
  assert_equals "s3cr3t" "$out" "secret get stdout" || return 1
  assert_contains "$(cat "$errfile")" "also exists and is ignored" "secret get stderr" || return 1

  out="$("$TEEUP" list 2>"$errfile")"
  assert_contains "$out" "alpha" "list stdout still lists capabilities" || return 1
  assert_contains "$(cat "$errfile")" "also exists and is ignored" "list stderr" || return 1

  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

# `has` is checked for stdout exactly, not just "contains": its whole
# contract is an exit code, so any stray byte on stdout (the notice
# included) is itself the bug.
test_has_stdout_stays_empty_with_a_shadowed_machine_file() {
  setup
  seed_shadowed_machine_files
  "$TEEUP" install alpha >/dev/null 2>/dev/null
  local out errfile
  errfile="$TEST_HOME/stderr.out"
  out="$("$TEEUP" has alpha 2>"$errfile")"
  assert_equals "" "$out" "has must print nothing on stdout" || return 1
  assert_contains "$(cat "$errfile")" "also exists and is ignored" "has stderr" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_list_tier_without_a_value_errors() {
  setup
  local rc=0 out
  out="$("$TEEUP" list --tier 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Usage: teeup list [--tier core|daily|lazy]" || return 1
  out="$("$TEEUP" list --tier nope 2>&1)" || rc=$?
  assert_contains "$out" "Unknown tier 'nope'" || return 1
  cleanup_test_env
}

test_lazy_run_execs_a_real_binary_when_one_exists() {
  setup
  mock_command frob 0 "the real frob"
  local out
  out="$("$TEEUP" lazy-run lazyone frob --one "two words")"
  assert_equals "the real frob" "$out" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "frob --one two words" || return 1
  assert_not_contains "$out" "install:lazyone" || return 1
  cleanup_test_env
}

test_lazy_run_without_a_tty_hints_and_exits_127() {
  setup
  local rc=0 out
  out="$(TEEUP_TEST_TTY=no "$TEEUP" lazy-run lazyone frob 2>&1)" || rc=$?
  assert_equals "127" "$rc" || return 1
  assert_contains "$out" "frob is not installed. It is provided by capability lazyone; run: teeup install lazyone" || return 1
  assert_not_contains "$out" "install:lazyone" || return 1
  cleanup_test_env
}

test_lazy_run_on_a_tty_installs_configures_and_execs() {
  setup
  make_frob_installable
  local out
  out="$(printf 'y\n' | TEEUP_TEST_TTY=yes "$TEEUP" lazy-run lazyone frob --flag "two words" 2>&1)"
  assert_contains "$out" "frob is provided by capability lazyone. Install now?" || return 1
  assert_contains "$out" "install:lazyone" || return 1
  assert_contains "$out" "configure:lazyone" || return 1
  assert_contains "$out" "frob ran: --flag two words" || return 1
  "$TEEUP" has lazyone || { echo "lazyone must be marked installed"; return 1; }
  cleanup_test_env
}

test_lazy_run_declined_exits_127_without_installing() {
  setup
  make_frob_installable
  local rc=0 out
  out="$(printf 'n\n' | TEEUP_TEST_TTY=yes "$TEEUP" lazy-run lazyone frob 2>&1)" || rc=$?
  assert_equals "127" "$rc" || return 1
  assert_contains "$out" "Not installed. When you want it: teeup install lazyone" || return 1
  assert_not_contains "$out" "install:lazyone" || return 1
  cleanup_test_env
}

test_lazy_run_respects_teeup_skip() {
  setup
  local rc=0 out
  out="$(printf 'y\n' | TEEUP_SKIP=lazyone TEEUP_TEST_TTY=yes "$TEEUP" lazy-run lazyone frob 2>&1)" || rc=$?
  assert_equals "127" "$rc" || return 1
  assert_contains "$out" "frob is provided by capability lazyone, which is skipped on this machine (TEEUP_SKIP)." || return 1
  assert_not_contains "$out" "install:lazyone" || return 1
  cleanup_test_env
}

test_lazy_run_reinstalls_a_capability_whose_command_went_missing() {
  setup
  "$TEEUP" install lazyone >/dev/null
  # Marked installed, but frob is gone: the question comes back, and an
  # install that still produces no frob ends in a clear 127.
  local rc=0 out
  out="$(printf 'y\n' | TEEUP_TEST_TTY=yes "$TEEUP" lazy-run lazyone frob 2>&1)" || rc=$?
  assert_equals "127" "$rc" || return 1
  assert_contains "$out" "frob is provided by capability lazyone. Install now?" || return 1
  assert_contains "$out" "install:lazyone" || return 1
  assert_contains "$out" "lazyone is installed but frob is still not on PATH" || return 1
  # With an install that does put frob back, the command runs.
  make_frob_installable
  out="$(printf 'y\n' | TEEUP_TEST_TTY=yes "$TEEUP" lazy-run lazyone frob again 2>&1)"
  assert_contains "$out" "frob ran: again" || return 1
  cleanup_test_env
}

test_lazy_run_finds_a_command_under_the_package_prefix() {
  setup
  # Installed by the package manager, but the calling PATH lacks its bin
  # directory: lazy-run adds it and execs without asking.
  mkdir -p "$TEEUP_PKG_PREFIX/bin"
  printf '#!/usr/bin/env bash\necho "prefix frob: $*"\n' > "$TEEUP_PKG_PREFIX/bin/frob"
  chmod +x "$TEEUP_PKG_PREFIX/bin/frob"
  local out
  out="$(TEEUP_TEST_TTY=no "$TEEUP" lazy-run lazyone frob x 2>&1)"
  assert_equals "prefix frob: x" "$out" || return 1
  cleanup_test_env
}

test_lazy_run_dry_run_previews_and_runs_nothing() {
  setup
  make_frob_installable
  local out
  out="$(printf 'y\n' | DRY_RUN=true TEEUP_TEST_TTY=yes "$TEEUP" lazy-run lazyone frob 2>&1)"
  assert_contains "$out" "Would record state: done/cap-lazyone" || return 1
  assert_contains "$out" "Dry run: frob was not installed, so it was not run." || return 1
  assert_not_contains "$out" "frob ran" || return 1
  cleanup_test_env
}

test_lazy_run_rejects_a_command_the_capability_does_not_provide() {
  setup
  local rc=0 out
  out="$("$TEEUP" lazy-run lazyone nope 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "lazyone does not provide nope" || return 1
  out="$("$TEEUP" lazy-run 2>&1)" || rc=$?
  assert_contains "$out" "Usage: teeup lazy-run <capability> <command> [args...]" || return 1
  cleanup_test_env
}

echo "bin/teeup"
run_test "install runs requires in order and marks done" test_install_runs_requires_in_order_and_marks_done
run_test "install refuses skipped capability" test_install_refuses_skipped_capability
run_test "install unknown capability" test_install_unknown_capability
run_test "configure only" test_configure_only
run_test "list shows tier and summary" test_list_shows_tier_and_summary
run_test "status reports backend and installed" test_status_reports_backend_and_installed
run_test "install records not-applicable and has reports not-installed" test_install_records_not_applicable_and_has_reports_not_installed
run_test "status shows not-applicable as its own state" test_status_shows_not_applicable_as_its_own_state
run_test "install still aborts on a real failure" test_install_still_aborts_on_a_real_failure
run_test "commands --check delegates" test_commands_check_delegates_to_cap_check
run_test "unknown verb exits 2" test_unknown_verb_exits_2
run_test "help lists verbs" test_help_lists_verbs
run_test "TEEUP_PATH derives from location" test_teeup_path_derives_from_location
run_test "dry run env reaches scripts" test_dry_run_env_reaches_scripts
run_test "configure refuses skipped capability" test_configure_refuses_skipped_capability
run_test "list --tier without a value errors" test_list_tier_without_a_value_errors
run_test "lazy-run execs a real binary when one exists" test_lazy_run_execs_a_real_binary_when_one_exists
run_test "lazy-run without a tty hints and exits 127" test_lazy_run_without_a_tty_hints_and_exits_127
run_test "lazy-run on a tty installs, configures and execs" test_lazy_run_on_a_tty_installs_configures_and_execs
run_test "lazy-run declined exits 127 without installing" test_lazy_run_declined_exits_127_without_installing
run_test "lazy-run respects TEEUP_SKIP" test_lazy_run_respects_teeup_skip
run_test "lazy-run reinstalls a capability whose command went missing" test_lazy_run_reinstalls_a_capability_whose_command_went_missing
run_test "lazy-run finds a command under the package prefix" test_lazy_run_finds_a_command_under_the_package_prefix
run_test "lazy-run dry run previews and runs nothing" test_lazy_run_dry_run_previews_and_runs_nothing
run_test "lazy-run rejects a command the capability does not provide" test_lazy_run_rejects_a_command_the_capability_does_not_provide
run_test "data verbs keep stdout clean with a shadowed machine file" test_data_verbs_keep_stdout_clean_with_a_shadowed_machine_file
run_test "has stdout stays empty with a shadowed machine file" test_has_stdout_stays_empty_with_a_shadowed_machine_file
print_summary
