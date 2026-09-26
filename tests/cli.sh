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
  # A cask that also links a command, and a lazy capability with neither.
  make_cap zapper lazy "" "zap" "Zap App"
  make_cap plain lazy
  out="$("$TEEUP" list --tier lazy)"
  assert_contains "$out" "lazyone" || return 1
  assert_not_contains "$out" "alpha" || return 1
  # Lazy rows say how they are reached; core rows have no such column.
  assert_contains "$out" "[on first: frob]" || return 1
  assert_contains "$out" "[launch: Sketch Pad]" || return 1
  assert_contains "$out" "[on first: zap; launch: Zap App]" || return 1
  assert_contains "$out" "[teeup install plain]" || return 1
  out="$("$TEEUP" list --tier core)"
  assert_not_contains "$out" "[" || return 1
  cleanup_test_env
}

test_status_reports_backend_and_installed() {
  setup
  "$TEEUP" install alpha >/dev/null
  local out
  out="$("$TEEUP" status)"
  assert_contains "$out" "Package manager: homebrew" || return 1
  assert_contains "$out" "alpha              installed (core)" || return 1
  assert_contains "$out" "Installed: 1 of 4" || return 1
  assert_contains "$out" "Answers: missing" || return 1
  assert_contains "$out" "Lazy shims: none (run: teeup configure teeup-runtime)" || return 1
  assert_contains "$out" "Dev envs: none" || return 1
  # With shims in place and a dev-env marked, both lines list them.
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false shims_generate >/dev/null
  DRY_RUN=false state_done mark dev-env-go
  out="$("$TEEUP" status)"
  assert_contains "$out" "Lazy shims: frob" || return 1
  assert_contains "$out" "Dev envs: go" || return 1
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
  assert_contains "$("$TEEUP" help)" "teeup install dev-env <lang>" || return 1
  assert_contains "$("$TEEUP" help)" "teeup launch <app|capability>" || return 1
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

# An install that genuinely fails (not one that is not applicable): the shim
# contract says 127 and a teeup-authored line saying the command is still not
# there. Without the guard in cmd_lazy_run this aborts on `set -e` at the
# install line, so the process exits 1 with only cap_run's generic text.
test_lazy_run_exits_127_when_the_install_fails() {
  setup
  cat > "$TEEUP_CAPS_DIR/lazyone/install" <<'EOF2'
#!/usr/bin/env bash
echo "install:lazyone"
exit 1
EOF2
  local rc=0 out
  out="$(printf 'y\n' | TEEUP_TEST_TTY=yes "$TEEUP" lazy-run lazyone frob 2>&1)" || rc=$?
  assert_equals "127" "$rc" || return 1
  assert_contains "$out" "lazyone could not be installed, so frob is still not available." || return 1
  "$TEEUP" has lazyone && { echo "a failed install must not be marked installed"; return 1; }
  cleanup_test_env
}

# A dependency that fails must stop the install, through lazy-run exactly as
# through `teeup install`. cmd_lazy_run calls cmd_install inside an `if`,
# which disables `set -e` for everything it runs, so without an explicit
# return the loop would carry on and mark the target installed (I3).
test_lazy_run_does_not_mark_installed_when_a_dependency_fails() {
  setup
  # lazyone's own fixture has no requires, so give it one that fails.
  make_cap lazyone lazy alpha frob ""
  make_frob_installable
  cat > "$TEEUP_CAPS_DIR/alpha/install" <<'EOF2'
#!/usr/bin/env bash
echo "install:alpha"
exit 1
EOF2
  chmod +x "$TEEUP_CAPS_DIR/alpha/install"
  local rc=0 out
  out="$(printf 'y\n' | TEEUP_TEST_TTY=yes "$TEEUP" lazy-run lazyone frob 2>&1)" || rc=$?
  assert_equals "127" "$rc" || return 1
  "$TEEUP" has lazyone && { echo "lazyone must not be marked installed when alpha failed"; return 1; }
  "$TEEUP" has alpha && { echo "alpha must not be marked installed"; return 1; }
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

test_launch_opens_an_installed_app_without_installing() {
  setup
  mock_command open 0 ""
  mkdir -p "$TEEUP_APPS_DIR/Sketch Pad.app"
  local out
  out="$("$TEEUP" launch "sketch pad")"
  assert_contains "$out" "Opening Sketch Pad" || return 1
  assert_not_contains "$out" "install:sketch" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "open -a Sketch Pad" || return 1
  # Unquoted, the way people type `teeup launch Google Chrome`.
  out="$("$TEEUP" launch Sketch Pad 2>&1)" || { echo "an unquoted app name must resolve: $out"; return 1; }
  assert_contains "$out" "Opening Sketch Pad" || return 1
  cleanup_test_env
}

test_launch_installs_the_capability_then_opens() {
  setup
  mock_command open 0 ""
  # The fixture's install "installs" the app by creating its bundle.
  printf '#!/usr/bin/env bash\necho "install:sketch"\nmkdir -p "$TEEUP_APPS_DIR/Sketch Pad.app"\n' > "$TEEUP_CAPS_DIR/sketch/install"
  local out
  out="$("$TEEUP" launch sketch)"
  assert_contains "$out" "Sketch Pad is not installed; installing sketch first." || return 1
  assert_contains "$out" "install:sketch" || return 1
  assert_contains "$out" "configure:sketch" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "open -a Sketch Pad" || return 1
  "$TEEUP" has sketch || { echo "sketch must be marked installed"; return 1; }
  cleanup_test_env
}

test_launch_fails_clearly_when_the_app_never_appears() {
  setup
  mock_command open 0 ""
  # What a MacPorts machine sees: cask_install warned and returned 0, so the
  # capability "succeeded" and the bundle is still missing.
  local rc=0 out
  out="$("$TEEUP" launch sketch 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Sketch Pad is still not in $TEEUP_APPS_DIR, $HOME/Applications after installing sketch" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "open -a" || return 1
  cleanup_test_env
}

# B1: a MacPorts machine's message must name the directory it actually looks
# in (macports_apps_dir), not just /Applications -- and the app that really
# is installed there must not be reinstalled by a second `teeup launch`.
test_launch_on_macports_consults_the_macports_apps_dir() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  mock_command open 0 ""
  local out
  out="$("$TEEUP" launch sketch 2>&1)" || true
  assert_contains "$out" "Sketch Pad is still not in $TEEUP_APPS_DIR, $HOME/Applications, /Applications/MacPorts after installing sketch" || return 1
  # Now the app really is there, the way a MacPorts aqua port would put it:
  # a second launch must open it, not reinstall the capability.
  local macports_dir="$TEST_HOME/pkgprefix/etc/macports"
  mkdir -p "$macports_dir"
  printf 'applications_dir\t%s/MacPortsApps\n' "$TEST_HOME" > "$macports_dir/macports.conf"
  mkdir -p "$TEST_HOME/MacPortsApps/Sketch Pad.app"
  out="$("$TEEUP" launch sketch 2>&1)"
  assert_contains "$out" "Opening Sketch Pad" || return 1
  assert_not_contains "$out" "install:sketch" || return 1
  cleanup_test_env
}

test_launch_dry_run_previews_the_open() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" launch sketch)"
  assert_contains "$out" "[DRY-RUN] Would execute: open -a Sketch Pad" || return 1
  cleanup_test_env
}

test_launch_unknown_app_and_skipped_capability() {
  setup
  local rc=0 out
  out="$("$TEEUP" launch "Nothing Here" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "No capability provides an app named 'Nothing Here'" || return 1
  rc=0
  out="$(TEEUP_SKIP=sketch "$TEEUP" launch sketch 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "sketch is skipped on this machine (TEEUP_SKIP); install Sketch Pad by hand." || return 1
  cleanup_test_env
}

# M6: a capability with more than one apps= entry must open the one the user
# actually named, not always the first.
test_launch_opens_the_named_app_not_just_the_first() {
  setup
  make_cap paint lazy "" "" "Paint Shop; Paint Viewer"
  mock_command open 0 ""
  mkdir -p "$TEEUP_APPS_DIR/Paint Viewer.app"
  local out
  out="$("$TEEUP" launch "Paint Viewer")"
  assert_contains "$out" "Opening Paint Viewer" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "open -a Paint Viewer" || return 1
  # Naming the capability itself (no specific app requested) still falls
  # back to the first app.
  out="$("$TEEUP" launch paint 2>&1)" || true
  assert_contains "$out" "Paint Shop is not installed; installing paint first." || return 1
  cleanup_test_env
}

# M9: a genuine install failure during `teeup launch` must reach a
# teeup-authored message, not abort under `set -e` on the bare `cmd_install`
# call with only cap_run's generic "Failed: X install" line.
test_launch_reports_a_real_install_failure_instead_of_aborting() {
  setup
  printf '#!/usr/bin/env bash\necho "install:sketch about to fail"\nfalse\n' > "$TEEUP_CAPS_DIR/sketch/install"
  local rc=0 out
  out="$("$TEEUP" launch sketch 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "sketch could not be installed, so Sketch Pad is still not available. The output above says why." || return 1
  cleanup_test_env
}

# M7: teeup list is a machine-independent catalogue; on a MacPorts machine it
# must say so rather than let a launch: route it cannot verify pass as fact.
test_list_notes_the_macports_launch_caveat() {
  setup
  local out
  out="$("$TEEUP" list --tier lazy)"
  assert_not_contains "$out" "MacPorts machine" || return 1
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  out="$("$TEEUP" list --tier lazy)"
  assert_contains "$out" "This is a MacPorts machine" || return 1
  cleanup_test_env
}

# M5: extra arguments must not be silently dropped -- `teeup install dev-env
# python node` must not look like it set both up when only python was.
test_install_dev_env_rejects_extra_arguments() {
  setup
  local rc=0 out
  out="$("$TEEUP" install dev-env python node 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Usage: teeup install dev-env <python|node|java|ruby|rust|go>" || return 1
  cleanup_test_env
}

test_install_dev_env_goes_through_mise() {
  setup
  mock_command_script mise <<'EOF2'
[ "$1" = "-C" ] && shift 2
case "$*" in
  "ls --global"*) : ;;
  "where "*) exit 1 ;;
  *) : ;;
esac
exit 0
EOF2
  local out
  out="$("$TEEUP" install dev-env go)"
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / use -g go@latest" || return 1
  assert_contains "$out" "go is ready" || return 1
  local rc=0
  out="$("$TEEUP" install dev-env cobol 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Usage: teeup install dev-env <python|node|java|ruby|rust|go>" || return 1
  cleanup_test_env
}

# A lazy capability with packages, a cask and a remove script of its own, the
# shape `teeup remove` has to handle: the script undoes machine state, the
# metadata names what to uninstall.
make_removable_cap() {
  make_cap tool lazy
  printf 'summary="Fixture tool"\ngroup=system\ntier=lazy\nrequires=""\nprovides=""\npackages="ripgrep"\ncasks="wezterm"\ninteractive=false\n' > "$TEEUP_CAPS_DIR/tool/capability"
  printf '#!/usr/bin/env bash\necho "remove:tool"\n' > "$TEEUP_CAPS_DIR/tool/remove"
  chmod +x "$TEEUP_CAPS_DIR/tool/remove"
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1 $2" in
  "list --formula"|"list --cask") exit 0 ;;
esac
exit 0
EOF2
  "$TEEUP" install tool >/dev/null
  : > "$MOCK_LOG"
}

test_remove_runs_the_script_then_uninstalls_from_metadata() {
  setup
  make_removable_cap
  local out r u
  out="$("$TEEUP" remove tool 2>&1)"
  assert_contains "$out" "remove:tool" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall --cask wezterm" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall ripgrep" || return 1
  r="$(printf '%s\n' "$out" | grep -n 'remove:tool' | head -1 | cut -d: -f1)"
  u="$(printf '%s\n' "$out" | grep -n 'Uninstalled wezterm' | head -1 | cut -d: -f1)"
  [[ "$r" -lt "$u" ]] || { echo "the remove script runs while the tool is still installed"; return 1; }
  assert_contains "$out" "Removed tool." || return 1
  "$TEEUP" has tool && { echo "the done marker must be gone"; return 1; }
  cleanup_test_env
}

test_remove_without_a_script_uses_metadata_alone() {
  setup
  make_removable_cap
  rm -f "$TEEUP_CAPS_DIR/tool/remove"
  local out
  out="$("$TEEUP" remove tool 2>&1)"
  assert_not_contains "$out" "has no remove script" "a capability without one is the normal case" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall ripgrep" || return 1
  assert_contains "$out" "Removed tool." || return 1
  cleanup_test_env
}

test_remove_refuses_what_something_else_requires() {
  setup
  mock_command brew 0 ""
  "$TEEUP" install beta >/dev/null
  local rc=0 out
  out="$("$TEEUP" remove alpha 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "alpha is required by: beta" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew uninstall" || return 1
  "$TEEUP" has alpha || { echo "nothing was removed"; return 1; }
  rc=0
  out="$("$TEEUP" remove nope 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Unknown capability: nope" || return 1
  rc=0
  out="$("$TEEUP" remove lazyone 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "lazyone is not installed here." || return 1
  assert_contains "$("$TEEUP" help)" "teeup remove <capability>" || return 1
  cleanup_test_env
}

test_remove_keeps_config_files_and_previews_a_dry_run() {
  setup
  make_removable_cap
  mkdir -p "$TEEUP_CAPS_DIR/tool/config"
  printf 'shipped=1\n' > "$TEEUP_CAPS_DIR/tool/config/tool.conf"
  local out
  out="$(DRY_RUN=true "$TEEUP" remove tool 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew uninstall --cask wezterm" || return 1
  assert_contains "$out" "[DRY-RUN] Would clear state: done/cap-tool" || return 1
  assert_contains "$out" "Your configuration files for tool were left in place." || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew uninstall" "nothing was uninstalled" || return 1
  "$TEEUP" has tool || { echo "the marker must survive a dry run"; return 1; }
  cleanup_test_env
}

test_remove_keeps_the_marker_when_an_uninstall_fails() {
  setup
  make_removable_cap
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1 $2" in
  "uninstall --cask") exit 1 ;;
  "list --formula"|"list --cask") exit 0 ;;
esac
exit 0
EOF2
  local rc=0 out
  out="$("$TEEUP" remove tool 2>&1)" || rc=$?
  assert_failure "$rc" "a failed uninstall must reach the exit status" || return 1
  assert_contains "$out" "Could not uninstall the wezterm cask." || return 1
  assert_contains "$out" "Leaving tool marked installed" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall ripgrep" "the package uninstall still runs" || return 1
  "$TEEUP" has tool || { echo "the marker must survive a failed uninstall, so a retry can find the leftover cask"; return 1; }
  cleanup_test_env
}

# D-1's general rule: a capability with no remove script and empty
# packages=/casks= (xcode-clt, package-manager on `main`, ai before this
# task gave it a remove script) has nothing teeup can undo, so `teeup
# remove` must not claim it did.
test_remove_dies_when_nothing_can_be_undone() {
  setup
  make_cap widget lazy
  mock_command brew 0 ""
  "$TEEUP" install widget >/dev/null
  local rc=0 out
  out="$("$TEEUP" remove widget 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "widget ships no remove script and installs no packages or casks that teeup tracks" || return 1
  assert_not_contains "$out" "Removed widget." || return 1
  "$TEEUP" has widget || { echo "the marker must survive; nothing was actually removed"; return 1; }
  cleanup_test_env
}

# R-A2: a capability this machine can never have (state_na, not state_done)
# must not be told to install something impossible, in cmd_remove either.
test_remove_refuses_a_not_applicable_capability() {
  setup
  make_na_cap gamma core
  printf 'alpha\nbeta\ngamma\n' > "$TEEUP_CAPS_DIR/core.list"
  "$TEEUP" install gamma >/dev/null 2>&1
  local rc=0 out
  out="$("$TEEUP" remove gamma 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "gamma is not applicable on this machine." || return 1
  cleanup_test_env
}

# A capability can carry a stale not-applicable marker beside its done marker
# -- a machine that gained what it was missing, reinstalled, and had the NA
# marker left behind by an older teeup. Removing it must clear both, or
# `teeup status` goes on calling a removed capability "not applicable on this
# machine" forever (R-7.3).
# A `remove` script that answers not-applicable: cap_run turns that exit into
# a success for every verb, so the script undid nothing of its own and teeup
# must not report a clean "Removed".
test_remove_is_honest_when_the_remove_script_answers_not_applicable() {
  setup
  "$TEEUP" install alpha >/dev/null
  cat > "$TEEUP_CAPS_DIR/alpha/remove" <<'EOF2'
#!/usr/bin/env bash
not_applicable "nothing of alpha's own to undo here"
EOF2
  chmod +x "$TEEUP_CAPS_DIR/alpha/remove"
  local out
  out="$("$TEEUP" remove alpha 2>&1)"
  assert_contains "$out" "reported it is not applicable on this machine, so it undid nothing of its own" || return 1
  out="$("$TEEUP" status 2>&1)"
  if printf '%s\n' "$out" | grep -q 'not applicable'; then
    echo "status calls a removed capability not applicable"
    return 1
  fi
  cleanup_test_env
}

# Everything `teeup update` reaches out to, mocked: the checkout is clean, the
# package manager and mise do nothing, and the fixture core.list is alpha+beta.
mock_update_world() {
  mock_command_script git <<'EOF2'
echo "git $*" >> "$MOCK_LOG"
case "$*" in
  *status*) exit 0 ;;
esac
exit 0
EOF2
  mock_command brew 0 ""
  mock_command mise 0 ""
}

# A migration that adjusts a config for a NEW version of a tool has to run
# after that tool is upgraded, not before. Running migrations first deadlocks
# the update on a machine whose old binary rejects the new config: the
# migration's refresh validates against the binary that is still installed,
# fails, and `migrations_run_pending || exit 1` stops the update before the
# upgrade that would have fixed it -- every time, forever.
#
# This is not hypothetical: migrations/<epoch>.sh refreshes aerospace.toml to
# config-version 2, and capabilities/aerospace/configure asks the running
# AeroSpace to validate it before installing.
test_update_upgrades_packages_before_running_migrations() {
  setup
  mock_update_world
  "$TEEUP" install alpha >/dev/null
  export TEEUP_MIGRATIONS_DIR="$TEST_HOME/migrations"
  mkdir -p "$TEEUP_MIGRATIONS_DIR"
  # The migration records what the package manager had already done by the
  # time it ran.
  printf '#!/usr/bin/env bash\nif grep -q "brew upgrade" "$MOCK_LOG" 2>/dev/null; then echo "migration saw the upgrade"; else echo "migration ran before the upgrade"; fi\n' \
    > "$TEEUP_MIGRATIONS_DIR/1780000001.sh"
  local out
  out="$("$TEEUP" update 2>&1)"
  assert_contains "$out" "migration saw the upgrade" "a migration must run against the versions this update installed" || return 1
  assert_not_contains "$out" "migration ran before the upgrade" || return 1
  cleanup_test_env
}

# ...and still before the configure loop, so a configure never runs on top of
# a migration that has not been applied yet.
test_update_runs_migrations_before_configuring() {
  setup
  mock_update_world
  "$TEEUP" install alpha >/dev/null
  export TEEUP_MIGRATIONS_DIR="$TEST_HOME/migrations"
  mkdir -p "$TEEUP_MIGRATIONS_DIR"
  printf '#!/usr/bin/env bash\necho "migration ran"\n' > "$TEEUP_MIGRATIONS_DIR/1780000002.sh"
  local out mig_line cfg_line
  out="$("$TEEUP" update 2>&1)"
  mig_line="$(printf '%s\n' "$out" | grep -n 'migration ran' | head -1 | cut -d: -f1)"
  cfg_line="$(printf '%s\n' "$out" | grep -n 'configure:alpha' | head -1 | cut -d: -f1)"
  [[ -n "$mig_line" && -n "$cfg_line" ]] || { echo "fixture: both steps must appear"; return 1; }
  [[ "$mig_line" -lt "$cfg_line" ]] || { echo "migrations must still run before configure"; return 1; }
  cleanup_test_env
}

# `teeup migrate legacy` end to end. The fixture capability tree here has no
# real zsh capability, so cap-zsh is marked done by hand where the migration
# is expected to proceed -- see the shell-safety test below for why that
# marker gates the chezmoi half at all.
migrate_setup() {
  export XDG_CONFIG_HOME="$TEST_HOME/.config"
  export TEEUP_TEST_MISSING="chezmoi"
  export TEEUP_TEST_TTY=no
}

test_migrate_requires_a_known_target() {
  setup
  migrate_setup
  local rc=0 out
  out="$("$TEEUP" migrate 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Usage: teeup migrate legacy" || return 1
  rc=0
  out="$("$TEEUP" migrate nonsense 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Unknown migration target" || return 1
  cleanup_test_env
}

test_migrate_legacy_runs_every_step_and_closes_with_a_real_command() {
  setup
  migrate_setup
  source "$TEEUP_PATH/lib/all.sh"
  state_done mark cap-zsh
  printf 'x\n' > "$TEST_HOME/.teeup.common"
  printf 'source "$HOME/.teeup.common"\neval "$(rbenv init -)"\nexport KEEP=1\n' > "$TEST_HOME/.zshrc"
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" migrate legacy 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  [[ ! -e "$TEST_HOME/.teeup.common" ]] || { echo "the legacy file survived"; return 1; }
  local content
  content="$(cat "$TEST_HOME/.zshrc")"
  assert_contains "$content" "replaced by teeup" || return 1
  assert_contains "$content" "rbenv replaced by mise" || return 1
  assert_contains "$content" "export KEEP=1" || return 1
  assert_contains "$out" "nothing to take over" "no chezmoi here" || return 1
  # T6.1: the closing line must name verbs that exist. teeup doctor landed
  # after this test was written, and is how to see what is left over.
  assert_contains "$out" "teeup update" || return 1
  assert_contains "$out" "teeup doctor" || return 1
  assert_contains "$("$TEEUP" help)" "teeup doctor" "the verb the migration names must be one bin/teeup has" || return 1
  cleanup_test_env
}

# T6.2, Important. The migration moves the shell rc files aside so teeup's own
# can take over. If teeup's zsh layer was never configured on this machine,
# that leaves no .zshrc, .zshenv or .zprofile at all -- the user opens a new
# terminal and has nothing. The chezmoi half is what moves those files, so it
# is what has to be gated.
test_migrate_legacy_refuses_the_chezmoi_half_without_teeups_zsh_layer() {
  setup
  migrate_setup
  source "$TEEUP_PATH/lib/all.sh"
  # cap-zsh deliberately NOT marked: teeup's shell layer is not installed.
  unset TEEUP_TEST_MISSING
  export TEEUP_TEST_TTY=yes
  local sibling="$TEST_HOME/dotfiles"
  mkdir -p "$sibling"
  printf '%s\n' "$TEST_HOME/.zshrc" > "$TEST_HOME/managed.txt"
  export TEEUP_TEST_CHEZMOI_SRC="$sibling"
  export TEEUP_TEST_CHEZMOI_MANAGED="$TEST_HOME/managed.txt"
  mock_command_script chezmoi <<'EOF2'
case "$1" in
  source-path) printf '%s\n' "$TEEUP_TEST_CHEZMOI_SRC" ;;
  managed) cat "${TEEUP_TEST_CHEZMOI_MANAGED:-/dev/null}" ;;
  --version) echo "chezmoi version v2.66.0" ;;
  *) exit 1 ;;
esac
EOF2
  printf 'mine\n' > "$TEST_HOME/.zshrc"
  local out rc=0
  out="$(printf 'y\ny\n' | DRY_RUN=false "$TEEUP" migrate legacy 2>&1)" || rc=$?
  assert_equals "mine" "$(cat "$TEST_HOME/.zshrc")" "without teeup's zsh layer the rc file must stay put" || return 1
  assert_contains "$out" "teeup install zsh" "it has to say how to make this safe" || return 1
  assert_equals "0" "$(find "$TEST_HOME" -name '*.teeup_backup_*' | wc -l | tr -d ' ')" || return 1
  cleanup_test_env
}

# And with the layer installed, the same run proceeds.
test_migrate_legacy_proceeds_with_teeups_zsh_layer_installed() {
  setup
  migrate_setup
  source "$TEEUP_PATH/lib/all.sh"
  state_done mark cap-zsh
  unset TEEUP_TEST_MISSING
  export TEEUP_TEST_TTY=yes
  local sibling="$TEST_HOME/dotfiles"
  mkdir -p "$sibling"
  printf '%s\n' "$TEST_HOME/.zshrc" > "$TEST_HOME/managed.txt"
  export TEEUP_TEST_CHEZMOI_SRC="$sibling"
  export TEEUP_TEST_CHEZMOI_MANAGED="$TEST_HOME/managed.txt"
  mock_command_script chezmoi <<'EOF2'
case "$1" in
  source-path) printf '%s\n' "$TEEUP_TEST_CHEZMOI_SRC" ;;
  managed) cat "${TEEUP_TEST_CHEZMOI_MANAGED:-/dev/null}" ;;
  --version) echo "chezmoi version v2.66.0" ;;
  *) exit 1 ;;
esac
EOF2
  printf 'mine\n' > "$TEST_HOME/.zshrc"
  printf 'n\n' > /dev/null
  local out
  out="$(printf 'y\nn\n' | DRY_RUN=false "$TEEUP" migrate legacy 2>&1)" || true
  assert_equals "1" "$(find "$TEST_HOME" -name '.zshrc.teeup_backup_*' | wc -l | tr -d ' ')" "with the layer installed the move proceeds" || return 1
  cleanup_test_env
}

test_migrate_legacy_dry_run_changes_nothing() {
  setup
  migrate_setup
  source "$TEEUP_PATH/lib/all.sh"
  state_done mark cap-zsh
  printf 'x\n' > "$TEST_HOME/.teeup.common"
  printf 'eval "$(rbenv init -)"\n' > "$TEST_HOME/.zshrc"
  local out
  out="$(DRY_RUN=true "$TEEUP" migrate legacy 2>&1)"
  assert_file_exists "$TEST_HOME/.teeup.common" "a dry run must delete nothing" || return 1
  assert_equals 'eval "$(rbenv init -)"' "$(cat "$TEST_HOME/.zshrc")" "a dry run must edit nothing" || return 1
  assert_not_contains "$out" "✅ Removed" "a dry run must not claim a removal" || return 1
  # Seen on a real Mac, 2026-09-25: the preview ended "Migration finished.
  # Open a new terminal, then run: teeup update", a migration that never
  # happened, with a next step that only makes sense after a real one.
  assert_not_contains "$out" "Migration finished" "a dry run must not claim the migration ran" || return 1
  assert_contains "$out" "Dry run finished: nothing was changed" || return 1
  cleanup_test_env
}

test_migrate_legacy_exits_non_zero_when_it_refused_something() {
  setup
  migrate_setup
  source "$TEEUP_PATH/lib/all.sh"
  state_done mark cap-zsh
  unset TEEUP_TEST_MISSING
  local sibling="$TEST_HOME/dotfiles"
  mkdir -p "$sibling/dot_config"
  export TEEUP_TEST_CHEZMOI_SRC="$sibling"
  export TEEUP_TEST_CHEZMOI_MANAGED=/dev/null
  mock_command_script chezmoi <<'EOF2'
case "$1" in
  source-path) printf '%s\n' "$TEEUP_TEST_CHEZMOI_SRC" ;;
  managed) cat "${TEEUP_TEST_CHEZMOI_MANAGED:-/dev/null}" ;;
  --version) echo "chezmoi version v2.66.0" ;;
  *) exit 1 ;;
esac
EOF2
  # ~/.config symlinked into the checkout, so mac-setup resolves inside it.
  rm -rf "$XDG_CONFIG_HOME"
  ln -s "$sibling/dot_config" "$XDG_CONFIG_HOME"
  mkdir -p "$sibling/dot_config/mac-setup"
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" migrate legacy 2>&1)" || rc=$?
  assert_failure "$rc" "a refusal must reach the exit status" || return 1
  assert_contains "$out" "refused to touch something" || return 1
  assert_contains "$out" "Nothing was lost" || return 1
  assert_dir_exists "$sibling/dot_config/mac-setup" "the refused path must be untouched" || return 1
  cleanup_test_env
}

test_migrate_appears_in_help() {
  setup
  assert_contains "$("$TEEUP" help)" "teeup migrate legacy" || return 1
  cleanup_test_env
}

test_update_walks_every_step_in_order() {
  setup
  mock_update_world
  "$TEEUP" install alpha >/dev/null
  "$TEEUP" install beta >/dev/null
  mkdir -p "$TEST_HOME/.config/teeup/hooks/post-update.d"
  printf '#!/usr/bin/env bash\necho "post-update hook:[$*]"\n' > "$TEST_HOME/.config/teeup/hooks/post-update.d/10-mark.sh"
  export TEEUP_MIGRATIONS_DIR="$TEST_HOME/migrations"
  mkdir -p "$TEEUP_MIGRATIONS_DIR"
  printf '#!/usr/bin/env bash\necho "migration ran"\n' > "$TEEUP_MIGRATIONS_DIR/1780000000.sh"
  local out
  out="$("$TEEUP" update 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "git -C $TEEUP_PATH pull --ff-only" || return 1
  assert_contains "$out" "migration ran" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew update" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew upgrade --cask" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / upgrade" || return 1
  assert_contains "$out" "configure:alpha" || return 1
  assert_contains "$out" "configure:beta" || return 1
  assert_not_contains "$out" "install:alpha" "update never installs" || return 1
  assert_contains "$out" "post-update hook:[]" || return 1
  assert_contains "$out" "teeup is up to date." || return 1
  assert_file_exists "$TEST_HOME/.local/state/teeup/migrations/1780000000.sh" || return 1
  cleanup_test_env
}

test_update_skips_core_capabilities_it_never_installed() {
  setup
  mock_update_world
  "$TEEUP" install alpha >/dev/null
  local out
  out="$(TEEUP_SKIP=alpha "$TEEUP" update 2>&1)"
  assert_contains "$out" "Skipping alpha (TEEUP_SKIP)" || return 1
  assert_contains "$out" "beta has never been installed here; run: teeup install beta" || return 1
  assert_not_contains "$out" "configure:beta" || return 1
  cleanup_test_env
}

test_update_refuses_a_dirty_checkout() {
  setup
  mock_command_script git <<'EOF2'
echo "git $*" >> "$MOCK_LOG"
case "$*" in
  *status*) echo " M lib/core.sh" ;;
esac
exit 0
EOF2
  mock_command brew 0 ""
  mock_command mise 0 ""
  local rc=0 out
  out="$("$TEEUP" update 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$TEEUP_PATH has uncommitted changes" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "git -C $TEEUP_PATH pull" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew update" "nothing after the checkout runs" || return 1
  cleanup_test_env
}

test_update_carries_on_when_the_pull_fails() {
  setup
  mock_command_script git <<'EOF2'
echo "git $*" >> "$MOCK_LOG"
case "$*" in
  *status*) exit 0 ;;
  *pull*) echo "fatal: unable to access github.com" >&2; exit 128 ;;
esac
exit 0
EOF2
  mock_command brew 0 ""
  mock_command mise 0 ""
  "$TEEUP" install alpha >/dev/null
  local rc=0 out
  out="$("$TEEUP" update 2>&1)" || rc=$?
  assert_failure "$rc" "an update with a failed step exits non-zero" || return 1
  assert_contains "$out" "git pull --ff-only failed" || return 1
  assert_contains "$out" "configure:alpha" "the rest of the update still ran" || return 1
  assert_contains "$out" "teeup update finished, with the problems above." || return 1
  cleanup_test_env
}

test_update_one_capability_upgrades_its_packages_and_configures() {
  setup
  mock_update_world
  printf 'summary="Fixture alpha"\ngroup=system\ntier=core\nrequires=""\nprovides=""\npackages="ripgrep"\ncasks="wezterm"\ninteractive=false\n' > "$TEEUP_CAPS_DIR/alpha/capability"
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1 $2" in
  "list --formula"|"list --cask") exit 0 ;;
esac
exit 0
EOF2
  "$TEEUP" install alpha >/dev/null
  : > "$MOCK_LOG"
  local out
  out="$("$TEEUP" update alpha 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "brew upgrade --cask wezterm" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew upgrade ripgrep" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew update" "one capability does not update the whole machine" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "git -C" || return 1
  assert_contains "$out" "configure:alpha" || return 1
  assert_contains "$out" "Updated alpha." || return 1
  cleanup_test_env
}

test_update_one_capability_refuses_what_it_cannot_update() {
  setup
  mock_update_world
  local rc=0 out
  out="$("$TEEUP" update nope 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Unknown capability: nope" || return 1
  rc=0
  out="$("$TEEUP" update alpha 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "alpha is not installed. Install it with: teeup install alpha" || return 1
  "$TEEUP" install alpha >/dev/null
  rc=0
  out="$(TEEUP_SKIP=alpha "$TEEUP" update alpha 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "alpha is skipped on this machine (TEEUP_SKIP)" || return 1
  assert_contains "$("$TEEUP" help)" "teeup update [<capability>]" || return 1
  cleanup_test_env
}

# Spec section 4's optional `update` script, and the metadata fallback for a
# capability that ships none (the test above this one). The script owns the
# upgrade: a capability that manages its own tool (a runtime installed from a
# tarball, an editor that updates itself) must not also have its metadata
# packages upgraded underneath it.
test_update_runs_a_capabilitys_own_update_script() {
  setup
  mock_update_world
  printf 'summary="Fixture alpha"\ngroup=system\ntier=core\nrequires=""\nprovides=""\npackages="ripgrep"\ncasks="wezterm"\ninteractive=false\n' > "$TEEUP_CAPS_DIR/alpha/capability"
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1 $2" in
  "list --formula"|"list --cask") exit 0 ;;
esac
exit 0
EOF2
  printf '#!/usr/bin/env bash\necho "update:alpha"\nrun_cmd touch "$HOME/updated"\n' > "$TEEUP_CAPS_DIR/alpha/update"
  chmod +x "$TEEUP_CAPS_DIR/alpha/update"
  "$TEEUP" install alpha >/dev/null
  : > "$MOCK_LOG"
  local out
  out="$("$TEEUP" update alpha 2>&1)"
  assert_contains "$out" "update:alpha" || return 1
  assert_file_exists "$TEST_HOME/updated" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew upgrade" "the script replaces the metadata upgrade" || return 1
  assert_contains "$out" "configure:alpha" "configure still runs after the script" || return 1
  assert_contains "$out" "Updated alpha." || return 1
  # The same capability without the script takes the metadata path again.
  rm -f "$TEEUP_CAPS_DIR/alpha/update"
  : > "$MOCK_LOG"
  out="$("$TEEUP" update alpha 2>&1)"
  assert_not_contains "$out" "update:alpha" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew upgrade ripgrep" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew upgrade --cask wezterm" || return 1
  cleanup_test_env
}

test_an_update_script_is_dry_run_and_its_failure_is_reported() {
  setup
  mock_update_world
  "$TEEUP" install alpha >/dev/null
  printf '#!/usr/bin/env bash\nrun_cmd touch "$HOME/updated"\n' > "$TEEUP_CAPS_DIR/alpha/update"
  chmod +x "$TEEUP_CAPS_DIR/alpha/update"
  local out rc=0
  out="$(DRY_RUN=true "$TEEUP" update alpha 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: touch $TEST_HOME/updated" || return 1
  [[ ! -e "$TEST_HOME/updated" ]] || { echo "the update script mutated in dry run"; return 1; }
  printf '#!/usr/bin/env bash\necho "the tool refused to update" >&2\nexit 1\n' > "$TEEUP_CAPS_DIR/alpha/update"
  out="$("$TEEUP" update alpha 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "alpha's update script failed." || return 1
  assert_contains "$out" "teeup update alpha finished, with the problems above." || return 1
  cleanup_test_env
}

# A capability the machine cannot have: update must skip it and say so, in
# both paths, rather than telling the user to install something impossible or
# reporting it as updated.
test_update_skips_a_not_applicable_capability() {
  setup
  mock_update_world
  cat > "$TEEUP_CAPS_DIR/alpha/install" <<'EOF2'
#!/usr/bin/env bash
not_applicable "alpha cannot be installed on this machine"
EOF2
  chmod +x "$TEEUP_CAPS_DIR/alpha/install"
  "$TEEUP" install alpha >/dev/null 2>&1 || true
  "$TEEUP" has alpha && { echo "a not-applicable capability must not read as installed"; return 1; }
  local out rc=0
  out="$("$TEEUP" update alpha 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "alpha is not applicable on this machine; skipping." || return 1
  assert_not_contains "$out" "Updated alpha." || return 1
  assert_not_contains "$out" "teeup install alpha" "it is not a missing install" || return 1
  # The whole-machine path says the same thing and never configures it.
  out="$("$TEEUP" update 2>&1)"
  assert_contains "$out" "alpha is not applicable on this machine; skipping." || return 1
  assert_not_contains "$out" "configure:alpha" || return 1
  cleanup_test_env
}

# A configure that answers not-applicable returns 0 and sets TEEUP_CAP_NA, so
# "did it succeed" is not the same question as "is it applicable". The theme
# capability is the one that matters: when its configure answers
# not-applicable it has rendered nothing, so the theme_set fallback still has
# to run.
test_update_does_not_treat_a_not_applicable_configure_as_done() {
  setup
  mock_update_world
  "$TEEUP" install alpha >/dev/null
  cat > "$TEEUP_CAPS_DIR/alpha/configure" <<'EOF2'
#!/usr/bin/env bash
echo "configure:alpha"
not_applicable "alpha turned out not to apply here"
EOF2
  chmod +x "$TEEUP_CAPS_DIR/alpha/configure"
  local out rc=0
  out="$("$TEEUP" update alpha 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "alpha is not applicable on this machine; skipping." || return 1
  assert_not_contains "$out" "Updated alpha." "a not-applicable configure is not an update" || return 1
  cleanup_test_env
}

# One capability failing must not stop the others, and must not be reported as
# an overall success.
test_update_carries_on_after_a_failed_configure_and_still_fails() {
  setup
  mock_update_world
  "$TEEUP" install alpha >/dev/null
  "$TEEUP" install beta >/dev/null
  cat > "$TEEUP_CAPS_DIR/alpha/configure" <<'EOF2'
#!/usr/bin/env bash
echo "configure:alpha"
exit 1
EOF2
  chmod +x "$TEEUP_CAPS_DIR/alpha/configure"
  local out rc=0
  out="$("$TEEUP" update 2>&1)" || rc=$?
  assert_failure "$rc" "one failed capability fails the run" || return 1
  assert_contains "$out" "alpha configure failed; continuing." || return 1
  assert_contains "$out" "configure:beta" "the capabilities after it still run" || return 1
  if printf '%s\n' "$out" | grep -q 'teeup is up to date'; then
    echo "claimed success after a capability failed"
    return 1
  fi
  cleanup_test_env
}

# The theme capability's own configure renders every template, so update
# skips the theme_set fallback when it ran. But a configure that answers
# not-applicable rendered nothing while still returning 0, so the fallback has
# to run anyway -- otherwise `teeup update` quietly stops regenerating the
# theme on exactly the machines that cannot configure it.
# A capability that was installed and now answers not-applicable -- a Mac that
# moved from Homebrew to MacPorts, say. Update must make the same done-to-NA
# move cap_install_verbs makes, or `teeup has` and `teeup status` go on
# calling it installed and every later update runs its configure again.
test_update_moves_a_newly_inapplicable_capability_to_not_applicable() {
  setup
  mock_update_world
  "$TEEUP" install alpha >/dev/null
  "$TEEUP" has alpha || { echo "fixture: alpha should be installed"; return 1; }
  cat > "$TEEUP_CAPS_DIR/alpha/configure" <<'EOF2'
#!/usr/bin/env bash
not_applicable "alpha cannot work on this machine any more"
EOF2
  chmod +x "$TEEUP_CAPS_DIR/alpha/configure"
  local out
  out="$("$TEEUP" update alpha 2>&1)"
  assert_contains "$out" "alpha is not applicable on this machine" || return 1
  "$TEEUP" has alpha && { echo "it must no longer be marked installed"; return 1; }
  assert_contains "$("$TEEUP" status 2>&1)" "not applicable" || return 1
  # And the whole-machine path makes the same move.
  "$TEEUP" install beta >/dev/null
  cat > "$TEEUP_CAPS_DIR/beta/configure" <<'EOF2'
#!/usr/bin/env bash
not_applicable "beta cannot work on this machine any more"
EOF2
  chmod +x "$TEEUP_CAPS_DIR/beta/configure"
  out="$("$TEEUP" update 2>&1)"
  assert_contains "$out" "beta is not applicable on this machine any more" || return 1
  "$TEEUP" has beta && { echo "beta must no longer be marked installed"; return 1; }
  cleanup_test_env
}

test_update_runs_the_theme_fallback_when_theme_is_not_applicable() {
  setup
  mock_update_world
  make_cap theme core
  cat > "$TEEUP_CAPS_DIR/theme/configure" <<'EOF2'
#!/usr/bin/env bash
echo "configure:theme"
not_applicable "no theme support on this machine"
EOF2
  chmod +x "$TEEUP_CAPS_DIR/theme/configure"
  printf 'alpha\nbeta\ntheme\n' > "$TEEUP_CAPS_DIR/core.list"
  "$TEEUP" install alpha >/dev/null
  "$TEEUP" install beta >/dev/null
  # Marked installed by hand: its own install would answer not-applicable too,
  # and this test is about the configure that runs during an update.
  : > "$TEST_HOME/.local/state/teeup/done/cap-theme"
  local out
  out="$("$TEEUP" update 2>&1)"
  assert_contains "$out" "configure:theme" || return 1
  # The fallback speaks: with no theme recorded it says so, which only happens
  # when theme_done stayed false.
  assert_contains "$out" "No theme recorded yet" || return 1
  cleanup_test_env
}

test_update_dry_run_changes_nothing() {
  setup
  mock_update_world
  "$TEEUP" install alpha >/dev/null
  export TEEUP_MIGRATIONS_DIR="$TEST_HOME/migrations"
  mkdir -p "$TEEUP_MIGRATIONS_DIR"
  printf '#!/usr/bin/env bash\nrun_cmd touch "$HOME/made"\n' > "$TEEUP_MIGRATIONS_DIR/1780000000.sh"
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=true "$TEEUP" update 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: git -C $TEEUP_PATH pull --ff-only" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: touch $TEST_HOME/made" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: brew update" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: mise -C / upgrade" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "pull --ff-only" "nothing was pulled" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew update" "nothing was upgraded" || return 1
  [[ ! -e "$TEST_HOME/made" ]] || { echo "a migration mutated in dry run"; return 1; }
  [[ ! -e "$TEST_HOME/.local/state/teeup/migrations/1780000000.sh" ]] || { echo "marker written in dry run"; return 1; }
  cleanup_test_env
}

# A capability with two shipped files under config/, the second rendered by
# configure, installed the way `teeup install` leaves it.
make_config_cap() {
  make_cap tool lazy
  mkdir -p "$TEEUP_CAPS_DIR/tool/config"
  printf 'shipped=1\n' > "$TEEUP_CAPS_DIR/tool/config/plain.conf"
  printf 'home=@HOME@\n' > "$TEEUP_CAPS_DIR/tool/config/rendered.conf"
  cat > "$TEEUP_CAPS_DIR/tool/configure" <<'EOF2'
#!/usr/bin/env bash
copy_config_once "$TEEUP_CAP_DIR/config/plain.conf" "$(user_config_dir)/tool/plain.conf"
rendered="$(mktemp)"
sed "s|@HOME@|$HOME|" "$TEEUP_CAP_DIR/config/rendered.conf" > "$rendered"
copy_config_once "$rendered" "$(user_config_dir)/tool/rendered.conf"
rm -f "$rendered"
echo "configure:tool"
EOF2
  "$TEEUP" install tool >/dev/null
  TOOL="$TEST_HOME/.config/tool"
}

test_reset_replaces_edited_files_through_configure() {
  setup
  make_config_cap
  printf 'shipped=1\nmine=1\n' > "$TOOL/plain.conf"
  local out backups
  out="$("$TEEUP" reset tool 2>&1)"
  assert_equals "shipped=1" "$(cat "$TOOL/plain.conf")" || return 1
  assert_equals "home=$TEST_HOME" "$(cat "$TOOL/rendered.conf")" "the rendered file stays rendered" || return 1
  assert_contains "$out" "Reset $TOOL/plain.conf (backup at $TOOL/plain.conf.teeup_backup_" || return 1
  assert_contains "$out" "> mine=1" "the diff shows what the backup holds" || return 1
  assert_contains "$out" "Already at the shipped version: $TOOL/rendered.conf" || return 1
  assert_contains "$out" "Reset tool." || return 1
  backups="$(find "$TOOL" -name '*.teeup_backup_*' | wc -l | tr -d ' ')"
  assert_equals "1" "$backups" "a backup only where something changed" || return 1
  assert_contains "$("$TEEUP" configure tool)" "Already installed: $TOOL/plain.conf" "the reset file is pristine again" || return 1
  cleanup_test_env
}

test_reset_dry_run_changes_nothing() {
  setup
  make_config_cap
  printf 'mine\n' > "$TOOL/plain.conf"
  local out
  out="$(DRY_RUN=true "$TEEUP" reset tool 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would reset $TOOL/plain.conf" || return 1
  assert_equals "mine" "$(cat "$TOOL/plain.conf")" || return 1
  [[ -z "$(find "$TOOL" -name '*.teeup_backup_*')" ]] || { echo "backup made in dry run"; return 1; }
  cleanup_test_env
}

test_reset_refuses_what_it_cannot_reset() {
  setup
  make_config_cap
  local out rc=0
  out="$("$TEEUP" reset nope 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Unknown capability: nope" || return 1
  rc=0
  out="$("$TEEUP" reset alpha 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "alpha ships no config files to reset." || return 1
  rc=0
  out="$(TEEUP_SKIP=tool "$TEEUP" reset tool 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "tool is skipped on this machine (TEEUP_SKIP)" || return 1
  rm -f "$TEST_HOME/.local/state/teeup/done/cap-tool"
  rc=0
  out="$("$TEEUP" reset tool 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "tool is not installed. Install it with: teeup install tool" || return 1
  assert_contains "$("$TEEUP" help)" "teeup reset <capability>" || return 1
  cleanup_test_env
}

# write_managed_file (through refresh_config) refuses a symlinked
# destination: the reset must say plainly that this one file did not happen
# and why, not claim success and not leave the link replaced.
test_reset_reports_a_refused_write_plainly() {
  setup
  make_config_cap
  mkdir -p "$TEST_HOME/dotfiles"
  printf 'managed elsewhere\n' > "$TEST_HOME/dotfiles/plain.conf"
  rm -f "$TOOL/plain.conf"
  ln -s "$TEST_HOME/dotfiles/plain.conf" "$TOOL/plain.conf"
  local out rc=0
  out="$("$TEEUP" reset tool 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$TOOL/plain.conf is a symlink; teeup does not write through it, so it was not reset." || return 1
  assert_contains "$out" "Resetting tool failed; the backups made so far are next to their files." || return 1
  assert_not_contains "$out" "Reset tool." "a refused write must not be reported as success" || return 1
  [[ -L "$TOOL/plain.conf" ]] || { echo "the symlink was replaced"; return 1; }
  assert_equals "managed elsewhere" "$(cat "$TEST_HOME/dotfiles/plain.conf")" || return 1
  cleanup_test_env
}

test_dev_add_migration_creates_a_named_scaffold() {
  setup
  export TEEUP_MIGRATIONS_DIR="$TEST_HOME/migrations"
  mock_command git 0 "1788000000"
  local out rc=0
  out="$("$TEEUP" dev add-migration 2>/dev/null)"
  assert_equals "$TEEUP_MIGRATIONS_DIR/1788000000.sh" "$out" || return 1
  assert_file_exists "$TEEUP_MIGRATIONS_DIR/1788000000.sh" || return 1
  out="$("$TEEUP" dev frobnicate 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Usage: teeup dev add-migration" || return 1
  assert_contains "$("$TEEUP" help)" "teeup dev add-migration" || return 1
  cleanup_test_env
}

test_doctor_is_quiet_and_zero_when_nothing_is_installed_is_wrong() {
  setup
  "$TEEUP" install alpha >/dev/null
  local out rc=0
  out="$("$TEEUP" doctor 2>&1)" || rc=$?
  assert_success "$rc" "a healthy machine must exit 0" || return 1
  assert_contains "$out" "everything checked is healthy" || return 1
  assert_not_contains "$out" "== beta:" "an uninstalled capability is not checked" || return 1
  cleanup_test_env
}

test_doctor_names_the_failure_and_the_command_that_fixes_it() {
  setup
  "$TEEUP" install alpha >/dev/null
  printf '#!/usr/bin/env bash\ndoctor_fail "alpha has no widget" "teeup configure alpha"\ndoctor_verdict\n' > "$TEEUP_CAPS_DIR/alpha/doctor"
  local out rc=0
  out="$("$TEEUP" doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "alpha has no widget" || return 1
  assert_contains "$out" "fix: teeup configure alpha" || return 1
  cleanup_test_env
}

# The third outcome, end to end through `teeup doctor` itself, not just
# lib/doctor.sh's own unit tests: a capability whose doctor script could not
# check something material (doctor_unknown) with nothing confirmed broken
# must exit 2, distinct from both 0 (healthy) and 1 (found problems) -- the
# whole point of giving "could not check" its own outcome.
test_doctor_exits_two_when_nothing_failed_but_something_could_not_be_checked() {
  setup
  "$TEEUP" install alpha >/dev/null
  printf '#!/usr/bin/env bash\ndoctor_unknown "could not tell about alpha" "teeup doctor alpha"\ndoctor_verdict\n' > "$TEEUP_CAPS_DIR/alpha/doctor"
  local out rc=0
  out="$("$TEEUP" doctor 2>&1)" || rc=$?
  assert_equals "2" "$rc" "could-not-verify must not read as either healthy (0) or a confirmed problem (1)" || return 1
  assert_contains "$out" "could not tell about alpha" || return 1
  assert_contains "$out" "could not verify 1 item" || return 1
  assert_not_contains "$out" "everything checked is healthy" || return 1
  assert_not_contains "$out" "found 1 problem" "an unknown is not a confirmed problem" || return 1
  cleanup_test_env
}

test_doctor_checks_one_capability_even_when_it_is_not_installed() {
  setup
  printf '#!/usr/bin/env bash\ndoctor_ok "beta looks fine"\ndoctor_verdict\n' > "$TEEUP_CAPS_DIR/beta/doctor"
  local out rc=0
  out="$("$TEEUP" doctor beta 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "beta looks fine" || return 1
  cleanup_test_env
}

# Every installed capability skipped on this machine is not an empty machine:
# telling the user to run ./bootstrap over a machine that is set up exactly as
# its machine file asks sends them to do work that is already done.
test_doctor_separates_an_empty_machine_from_a_fully_skipped_one() {
  setup
  local out
  out="$(TEEUP_SKIP='' "$TEEUP" doctor 2>&1)" || true
  assert_contains "$out" "No capability is marked installed here" || return 1
  # Nothing was checked, so this must not also claim health (B4): the two
  # facts are different and must not share wording.
  assert_not_contains "$out" "everything checked is healthy" || return 1
  "$TEEUP" install alpha >/dev/null
  out="$(TEEUP_SKIP="alpha beta" "$TEEUP" doctor 2>&1)" || true
  assert_contains "$out" "Every installed capability is skipped on this machine" || return 1
  assert_not_contains "$out" "No capability is marked installed here" || return 1
  assert_not_contains "$out" "everything checked is healthy" || return 1
  cleanup_test_env
}

# A done/ directory teeup cannot read (left root-owned by a `sudo
# ./bootstrap`, or a bad umask) must not be read as "nothing is installed":
# every state_done lookup would silently answer no, and a fully-installed,
# healthy machine would be told to run ./bootstrap and then be congratulated
# as healthy in the same breath (B4).
test_doctor_reports_an_unreadable_state_dir_instead_of_calling_it_empty() {
  setup
  "$TEEUP" install alpha >/dev/null
  local state_dir="$TEST_HOME/.local/state/teeup/done"
  [[ -d "$state_dir" ]] || { echo "state dir fixture assumption broke"; return 1; }
  chmod 0000 "$state_dir"
  local out rc=0
  out="$("$TEEUP" doctor 2>&1)" || rc=$?
  chmod 0755 "$state_dir"
  assert_failure "$rc" "an unreadable state tree must not exit 0" || return 1
  assert_contains "$out" "could not be read" || return 1
  assert_contains "$out" "chmod u+rx" || return 1
  assert_not_contains "$out" "No capability is marked installed here" || return 1
  assert_not_contains "$out" "everything checked is healthy" || return 1
  cleanup_test_env
}

# NB3: doctor_state_readable used to test only $TEEUP_STATE_DIR/done. When
# the PARENT $TEEUP_STATE_DIR itself is unsearchable (the shape a `sudo
# ./bootstrap` or a bad umask actually leaves -- permissions damage lands on
# the tree root), `[[ ! -e "$TEEUP_STATE_DIR/done" ]]` used to succeed for
# the wrong reason (a `stat` that failed with EACCES), the gate passed, and
# a fully installed, healthy machine was told "No capability is marked
# installed here. Run ./bootstrap."
test_doctor_reports_an_unreadable_state_dir_parent_instead_of_calling_it_empty() {
  setup
  "$TEEUP" install alpha >/dev/null
  local state_root="$TEST_HOME/.local/state/teeup"
  [[ -d "$state_root/done" ]] || { echo "state dir fixture assumption broke"; return 1; }
  chmod 0000 "$state_root"
  local out rc=0
  out="$("$TEEUP" doctor 2>&1)" || rc=$?
  chmod 0755 "$state_root"
  assert_failure "$rc" "an unsearchable state root must not exit 0 either (NB3)" || return 1
  assert_contains "$out" "could not be read" || return 1
  assert_not_contains "$out" "No capability is marked installed here" || return 1
  assert_not_contains "$out" "everything checked is healthy" || return 1
  cleanup_test_env
}

# NI-C: NB3's own fix still trusted `-e "$TEEUP_STATE_DIR"` once the root
# itself looked searchable, but that is unsearchable for the wrong reason
# when the root's own PARENT cannot be searched -- ~/.local/state left
# root-owned by a `sudo`-run tool is at least as common as the teeup
# directory under it, and permissions damage lands on whichever directory a
# privileged process created first. A fully installed, healthy machine must
# not read as bare one directory further up than NB3 already covers.
test_doctor_reports_an_unreadable_state_dir_grandparent_instead_of_calling_it_empty() {
  setup
  "$TEEUP" install alpha >/dev/null
  local state_root="$TEST_HOME/.local/state/teeup" state_parent="$TEST_HOME/.local/state"
  [[ -d "$state_root/done" ]] || { echo "state dir fixture assumption broke"; return 1; }
  chmod 0000 "$state_parent"
  local out rc=0
  out="$("$TEEUP" doctor 2>&1)" || rc=$?
  chmod 0755 "$state_parent"
  assert_failure "$rc" "an unsearchable parent of the state root must not exit 0 either (NI-C)" || return 1
  assert_contains "$out" "could not be read" || return 1
  assert_contains "$out" "$state_parent" "the failure must name the directory that is actually unsearchable" || return 1
  assert_not_contains "$out" "No capability is marked installed here" || return 1
  assert_not_contains "$out" "everything checked is healthy" || return 1
  cleanup_test_env
}

test_doctor_rejects_an_unknown_capability() {
  setup
  local out rc=0
  out="$("$TEEUP" doctor nope 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Unknown capability: nope" || return 1
  cleanup_test_env
}

seed_config_answers() {
  mkdir -p "$TEST_HOME/.config/teeup"
  {
    printf 'TEEUP_EMAIL="ada@example.com"\n'
    printf 'TEEUP_NAME="Ada Lovelace"\n'
    printf 'TEEUP_THEME="catppuccin"\n'
  } > "$TEST_HOME/.config/teeup/answers"
}

pin_machine() {
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR"
  printf '%s\n' "$1" > "$TEEUP_MACHINES_DIR/testmac.conf"
}

test_config_get_lists_every_key_and_marks_the_pinned_ones() {
  setup
  seed_config_answers
  pin_machine 'TEEUP_THEME="nord"'
  local out
  out="$("$TEEUP" config get)"
  assert_contains "$out" "TEEUP_NAME" || return 1
  assert_contains "$out" "Ada Lovelace" || return 1
  assert_contains "$out" "[pinned by testmac.conf]" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_config_get_prints_the_effective_value() {
  setup
  seed_config_answers
  assert_equals "catppuccin" "$("$TEEUP" config get TEEUP_THEME)" || return 1
  pin_machine 'TEEUP_THEME="nord"'
  assert_equals "nord" "$("$TEEUP" config get TEEUP_THEME)" "the machine file wins" || return 1
  local rc=0 out
  out="$("$TEEUP" config get TEEUP_NOPE 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "No answer named TEEUP_NOPE" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

# R7.2: get must not present a runtime variable as though it were an answer,
# even though it is exported into this very shell by setup() / answers_load.
test_config_get_refuses_a_runtime_variable_that_is_not_an_answer() {
  setup
  seed_config_answers
  local rc=0 out
  out="$("$TEEUP" config get TEEUP_CAPS_DIR 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "No answer named TEEUP_CAPS_DIR" || return 1
  cleanup_test_env
}

test_config_set_writes_the_answers_file() {
  setup
  seed_config_answers
  "$TEEUP" config set TEEUP_NAME Grace Hopper >/dev/null
  assert_equals "Grace Hopper" "$("$TEEUP" config get TEEUP_NAME)" || return 1
  assert_contains "$(cat "$TEST_HOME/.config/teeup/answers")" 'TEEUP_NAME="Grace Hopper"' || return 1
  cleanup_test_env
}

test_config_set_says_when_the_machine_file_makes_the_write_pointless() {
  setup
  seed_config_answers
  pin_machine 'TEEUP_THEME="nord"'
  local out
  out="$("$TEEUP" config set TEEUP_THEME catppuccin 2>&1)"
  assert_contains "$out" "pins TEEUP_THEME=nord" || return 1
  assert_contains "$out" "will have no effect" || return 1
  assert_contains "$(cat "$TEST_HOME/.config/teeup/answers")" 'TEEUP_THEME="catppuccin"' "the answers file is still written" || return 1
  assert_equals "nord" "$("$TEEUP" config get TEEUP_THEME)" "and the pin still wins" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_config_set_rejects_a_key_that_is_not_an_answer() {
  setup
  seed_config_answers
  local rc=0 out
  out="$("$TEEUP" config set PATH /tmp 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "must look like TEEUP_NAME" || return 1
  cleanup_test_env
}

# R7.1: any TEEUP_WORK_* key is refused outright, and told which file to
# edit instead -- the personal overlay this host would use, never the
# answers file, since work_get never reads the answers file at all.
test_config_set_refuses_any_work_key() {
  setup
  seed_config_answers
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR"
  local rc=0 out
  out="$("$TEEUP" config set TEEUP_WORK_EMAIL boss@corp.example 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  # M1: with no machine file anywhere yet, the file to edit must be the
  # personal overlay under TEEUP_CONFIG_DIR -- never machine_file()'s own
  # fallback, which is the checkout's machines/ dir and contradicts R7.1's
  # own ruling that the user edits their own overlay, not the checkout.
  assert_contains "$out" "$TEST_HOME/.config/teeup/machines/testmac.conf" "names the personal overlay to edit" || return 1
  assert_not_contains "$out" "$TEST_HOME/machines/testmac.conf" "must not point at the checkout's machine file when neither exists yet" || return 1
  assert_not_contains "$out" "(R7.1)" "an internal ruling tag must not reach the user" || return 1
  assert_contains "$out" "example.conf.sample" || return 1

  rc=0
  out="$("$TEEUP" config set TEEUP_WORK_GH_HOST github.enterprise.example.com 2>&1)" || rc=$?
  assert_failure "$rc" || return 1

  rc=0
  out="$("$TEEUP" config set TEEUP_WORK_GH_ACCOUNT ada-work 2>&1)" || rc=$?
  assert_failure "$rc" || return 1

  assert_not_contains "$(cat "$TEST_HOME/.config/teeup/answers")" "TEEUP_WORK" "the answers file must never gain a work key" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

# M1, the case machine_file() already handles right: once a machine file
# actually exists (even only the checkout's), it must still be the one
# named -- the fallback change must not hide a real, existing file.
test_config_set_names_an_existing_machine_file_even_the_checkouts() {
  setup
  seed_config_answers
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR"
  printf 'TEEUP_THEME="nord"\n' > "$TEEUP_MACHINES_DIR/testmac.conf"
  local rc=0 out
  out="$("$TEEUP" config set TEEUP_WORK_EMAIL boss@corp.example 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$TEEUP_MACHINES_DIR/testmac.conf" "an existing machine file is still named" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_config_set_dry_run_does_not_claim_success_or_write() {
  setup
  seed_config_answers
  local out
  out="$(DRY_RUN=true "$TEEUP" config set TEEUP_NAME "Grace Hopper" 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would set TEEUP_NAME" || return 1
  assert_not_contains "$out" "✅" || return 1
  assert_equals "Ada Lovelace" "$("$TEEUP" config get TEEUP_NAME)" "a dry run must not write" || return 1
  cleanup_test_env
}

test_config_set_says_the_git_identity_needs_reconfiguring() {
  setup
  seed_config_answers
  local out
  out="$("$TEEUP" config set TEEUP_EMAIL grace@example.com 2>&1)"
  assert_contains "$out" "teeup configure git" || return 1
  cleanup_test_env
}

test_config_set_says_emacs_needs_reconfiguring() {
  setup
  seed_config_answers
  local out
  out="$("$TEEUP" config set TEEUP_EMACS_FLAVOR doom 2>&1)"
  assert_contains "$out" "teeup configure emacs" || return 1
  cleanup_test_env
}

test_config_set_says_daily_needs_a_fresh_bootstrap() {
  setup
  seed_config_answers
  local out
  out="$("$TEEUP" config set TEEUP_DAILY true 2>&1)"
  assert_contains "$out" "./bootstrap" || return 1
  cleanup_test_env
}

# R7.5: TEEUP_THEME is redirected to the verb that actually validates the
# name and re-renders every themed tool, rather than just noting that a
# raw write happened.
test_config_set_redirects_theme_to_theme_set() {
  setup
  seed_config_answers
  local out
  out="$("$TEEUP" config set TEEUP_THEME nord 2>&1)"
  assert_contains "$out" "teeup theme set nord" || return 1
  assert_equals "nord" "$("$TEEUP" config get TEEUP_THEME)" || return 1
  cleanup_test_env
}

test_config_set_warns_about_package_manager_before_it_is_installed() {
  setup
  seed_config_answers
  local out
  out="$("$TEEUP" config set TEEUP_PACKAGE_MANAGER macports 2>&1)"
  assert_contains "$out" "only takes effect" || return 1
  assert_equals "macports" "$("$TEEUP" config get TEEUP_PACKAGE_MANAGER)" || return 1
  cleanup_test_env
}

test_config_set_refuses_package_manager_once_it_is_installed() {
  setup
  seed_config_answers
  mkdir -p "$TEST_HOME/.local/state/teeup/done"
  : > "$TEST_HOME/.local/state/teeup/done/cap-package-manager"
  local rc=0 out
  out="$("$TEEUP" config set TEEUP_PACKAGE_MANAGER macports 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "package-manager is already installed" || return 1
  assert_not_contains "$(cat "$TEST_HOME/.config/teeup/answers")" "TEEUP_PACKAGE_MANAGER" "must refuse before writing" || return 1
  cleanup_test_env
}

test_config_set_warns_when_nothing_known_applies_the_change() {
  setup
  seed_config_answers
  local out
  out="$("$TEEUP" config set TEEUP_CUSTOM_FLAG yes 2>&1)"
  assert_contains "$out" "not one of the answers" || return 1
  assert_equals "yes" "$("$TEEUP" config get TEEUP_CUSTOM_FLAG)" "the write itself still happens" || return 1
  cleanup_test_env
}

# R7.6: _config_keys must see an `export KEY=value` line too, or a key that
# exists only that way in a hand-written machine file stays invisible.
test_config_keys_accepts_an_exported_machine_line() {
  setup
  seed_config_answers
  pin_machine 'export TEEUP_ONLY_IN_MACHINE="pinned"'
  assert_equals "pinned" "$("$TEEUP" config get TEEUP_ONLY_IN_MACHINE)" || return 1
  local out
  out="$("$TEEUP" config get)"
  assert_contains "$out" "TEEUP_ONLY_IN_MACHINE" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

# R7.6: when both the personal overlay and the checkout's machine file
# exist, the header names both and says which one wins, rather than
# leaving the shadowed one invisible.
test_config_get_header_lists_both_machine_files_when_both_exist() {
  setup
  seed_config_answers
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR" "$TEST_HOME/.config/teeup/machines"
  printf 'TEEUP_THEME="nord"\n' > "$TEEUP_MACHINES_DIR/testmac.conf"
  printf 'TEEUP_THEME="dracula"\n' > "$TEST_HOME/.config/teeup/machines/testmac.conf"
  local out
  out="$("$TEEUP" config get 2>/dev/null)"
  assert_contains "$out" "$TEST_HOME/.config/teeup/machines/testmac.conf" || return 1
  assert_contains "$out" "$TEEUP_MACHINES_DIR/testmac.conf" || return 1
  assert_contains "$out" "wins" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

# I3: work_get (lib/answers.sh) never reads the answers file, only
# machines/<hostname>.conf -- so a leftover TEEUP_WORK_* answer must not be
# shown as though teeup will actually use it. `get` promises "prints what
# the rest of teeup will actually see"; for a work key that is work_get's
# answer, marked as ignored when it is only sitting in the answers file.
test_config_get_shows_a_leftover_work_answer_as_ignored() {
  setup
  seed_config_answers
  printf 'TEEUP_WORK_EMAIL="old@corp.example"\n' >> "$TEST_HOME/.config/teeup/answers"
  local out
  out="$("$TEEUP" config get 2>&1)"
  assert_contains "$out" "TEEUP_WORK_EMAIL" || return 1
  assert_contains "$out" "ignored: work settings are read from the machine file only" || return 1
  assert_not_contains "$out" "old@corp.example   [pinned" "a leftover value must never read as pinned/live" || return 1
  assert_equals "" "$("$TEEUP" config get TEEUP_WORK_EMAIL)" "get TEEUP_WORK_EMAIL must match work_get, which ignores the answers file" || return 1
  cleanup_test_env
}

# I3, positive case: once the machine file actually pins the work key,
# both the listing and the single-key form must show that real value.
test_config_get_shows_the_machine_files_work_answer_as_pinned() {
  setup
  seed_config_answers
  printf 'TEEUP_WORK_EMAIL="old@corp.example"\n' >> "$TEST_HOME/.config/teeup/answers"
  pin_machine 'TEEUP_WORK_EMAIL="boss@work.example"'
  local out
  out="$("$TEEUP" config get 2>&1)"
  assert_contains "$out" "boss@work.example   [pinned by testmac.conf]" || return 1
  assert_not_contains "$out" "old@corp.example" "the answers-file leftover must not appear once the machine file pins it" || return 1
  assert_equals "boss@work.example" "$("$TEEUP" config get TEEUP_WORK_EMAIL)" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_config_edit_runs_the_editor_and_keeps_a_good_edit() {
  setup
  seed_config_answers
  mock_command_script fakeed <<'EOF2'
printf 'TEEUP_EMAIL="grace@example.com"\n' >> "$1"
EOF2
  VISUAL=fakeed "$TEEUP" config edit >/dev/null
  assert_equals "grace@example.com" "$("$TEEUP" config get TEEUP_EMAIL)" || return 1
  local mode
  mode="$(stat -c '%a' "$TEST_HOME/.config/teeup/answers" 2>/dev/null || stat -f '%Lp' "$TEST_HOME/.config/teeup/answers")"
  assert_equals "600" "$mode" || return 1
  cleanup_test_env
}

test_config_edit_rolls_back_an_edit_that_will_not_parse() {
  setup
  seed_config_answers
  mock_command_script fakeed <<'EOF2'
printf 'TEEUP_NAME="unterminated\n' >> "$1"
EOF2
  local rc=0 out
  # VISUAL is emptied, not merely unset: it is a real variable in a real
  # developer's environment and would otherwise win over EDITOR here.
  out="$(VISUAL="" EDITOR=fakeed "$TEEUP" config edit 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "rolled back" || return 1
  assert_equals "Ada Lovelace" "$("$TEEUP" config get TEEUP_NAME)" || return 1
  cleanup_test_env
}

# R7.4: a line that passes bash -n but is not the shape answers_set writes
# (an unquoted value with a space) must be rolled back too, because sourcing
# it does not fail -- it silently runs the second word as a command.
test_config_edit_rolls_back_a_line_that_would_run_as_a_command() {
  setup
  seed_config_answers
  mock_command_script fakeed <<'EOF2'
printf 'TEEUP_NAME=Alan Turing\n' >> "$1"
EOF2
  local rc=0 out
  out="$(VISUAL=fakeed "$TEEUP" config edit 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "rolled back" || return 1
  assert_equals "Ada Lovelace" "$("$TEEUP" config get TEEUP_NAME)" "the original answer must survive the rollback" || return 1
  local mode
  mode="$(stat -c '%a' "$TEST_HOME/.config/teeup/answers" 2>/dev/null || stat -f '%Lp' "$TEST_HOME/.config/teeup/answers")"
  assert_equals "600" "$mode" "the restored file keeps its mode" || return 1
  cleanup_test_env
}

# I1: a bare value with no spaces can still carry `;`, `|`, `&`, `$`, a
# backtick or parens, and answers_load sources the file under `set -e`, so
# `TEEUP_NAME=a;false` makes every other verb exit 1 with no message at all
# once it is saved. The bare form must accept only a safe character class.
test_config_edit_rolls_back_a_bare_value_with_a_semicolon() {
  setup
  seed_config_answers
  mock_command_script fakeed <<'EOF2'
printf 'TEEUP_NAME=a;false\n' >> "$1"
EOF2
  local rc=0 out
  out="$(VISUAL=fakeed "$TEEUP" config edit 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "rolled back" || return 1
  assert_equals "Ada Lovelace" "$("$TEEUP" config get TEEUP_NAME)" "the original answer must survive the rollback" || return 1
  rc=0
  "$TEEUP" version >/dev/null 2>&1 || rc=$?
  assert_success "$rc" "a rolled-back edit must not leave every other verb exiting 1" || return 1
  cleanup_test_env
}

# I2: an editor that writes a bad line and then exits non-zero (":w" then
# ":cq" in vim does exactly this) must not leave that line in place. The
# backup has to be restored before the die, or "$f is unchanged" is a lie
# and the bad line breaks every subsequent verb.
test_config_edit_restores_the_backup_when_the_editor_exits_non_zero() {
  setup
  seed_config_answers
  mock_command_script fakeed <<'EOF2'
printf 'TEEUP_NAME=Ada Lovelace\n' >> "$1"
exit 1
EOF2
  local rc=0 out
  out="$(VISUAL=fakeed "$TEEUP" config edit 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "is unchanged" || return 1
  assert_equals "Ada Lovelace" "$("$TEEUP" config get TEEUP_NAME)" "the original file must actually be restored, not just described as unchanged" || return 1
  rc=0
  "$TEEUP" version >/dev/null 2>&1 || rc=$?
  assert_success "$rc" "the bad line the editor half-wrote must not linger and break every other verb" || return 1
  local mode
  mode="$(stat -c '%a' "$TEST_HOME/.config/teeup/answers" 2>/dev/null || stat -f '%Lp' "$TEST_HOME/.config/teeup/answers")"
  assert_equals "600" "$mode" "the restored file keeps its mode" || return 1
  cleanup_test_env
}

# Fix round 1 (Important): the quoted-value gate must accept exactly what
# answers_set itself writes -- backslash-escaped ", \, $ and ` -- or any
# answer that has ever held one of those characters breaks `teeup config
# edit` for good. Round-trips a value through the real `teeup config set`
# escaping, then edits a different line, and the tricky value must survive
# untouched rather than being rolled back as unsafe.
test_config_edit_accepts_a_value_answers_set_itself_escaped() {
  setup
  seed_config_answers
  local tricky='Grace "Ace" \both$ways`here`'
  "$TEEUP" config set TEEUP_NAME "$tricky" >/dev/null
  assert_equals "$tricky" "$("$TEEUP" config get TEEUP_NAME)" "sanity: the value round-trips through set/get" || return 1
  mock_command_script fakeed <<'EOF2'
printf 'TEEUP_EMAIL="grace@example.com"\n' >> "$1"
EOF2
  local out
  out="$(VISUAL=fakeed "$TEEUP" config edit 2>&1)"
  assert_contains "$out" "Saved" || return 1
  assert_equals "$tricky" "$("$TEEUP" config get TEEUP_NAME)" "the tricky value must survive an edit to a different line" || return 1
  assert_equals "grace@example.com" "$("$TEEUP" config get TEEUP_EMAIL)" || return 1
  cleanup_test_env
}

# Fix round 1 (Important): an UNescaped $(...) inside quotes is exactly what
# would let the line run a command when answers_load sources it, so it must
# still be rejected even though it is syntactically valid shell (bash -n
# alone would accept it) -- and the die message must not call this a parse
# failure, since the file does parse.
test_config_edit_rejects_unescaped_command_substitution_in_a_quoted_value() {
  setup
  seed_config_answers
  mock_command_script fakeed <<'EOF2'
printf 'TEEUP_NAME="$(id)"\n' >> "$1"
EOF2
  local rc=0 out
  out="$(VISUAL=fakeed "$TEEUP" config edit 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "rolled back" || return 1
  assert_not_contains "$out" "would not parse as shell" "a shape failure must not be reported as a parse failure" || return 1
  assert_equals "Ada Lovelace" "$("$TEEUP" config get TEEUP_NAME)" || return 1
  cleanup_test_env
}

test_config_edit_passes_flags_in_the_editor_variable() {
  setup
  seed_config_answers
  mock_command_script fakeed <<'EOF2'
printf '%s\n' "$*" > "$HOME/editor-args"
EOF2
  VISUAL="fakeed --wait" "$TEEUP" config edit >/dev/null
  assert_equals "--wait $TEST_HOME/.config/teeup/answers" "$(cat "$TEST_HOME/editor-args")" || return 1
  cleanup_test_env
}

# R7.3: a dry run previews only. It must not create the answers file, and
# must not invoke the editor at all (nothing on PATH answers to "fakeed"
# here, so a regression that reaches run_cmd would fail loudly).
test_config_edit_dry_run_creates_and_touches_nothing() {
  setup
  local out rc=0
  out="$(DRY_RUN=true VISUAL=fakeed "$TEEUP" config edit 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "[DRY-RUN] Would open fakeed on $TEST_HOME/.config/teeup/answers" || return 1
  if [[ -f "$TEST_HOME/.config/teeup/answers" ]]; then
    echo "the answers file must not be created under a dry run"
    return 1
  fi
  cleanup_test_env
}


# A menu of the fixture capabilities, so these tests never depend on what
# share/teeup/menu.json happens to contain.
write_test_menu() {
  export TEEUP_MENU_FILE="$TEST_HOME/menu.json"
  cat > "$TEEUP_MENU_FILE" <<'EOF2'
{
  "install": {"icon": "+", "label": "Install", "title": "Install something"},
  "install.alpha": {"label": "Alpha", "when": "! teeup has alpha", "action": "teeup install alpha"},
  "install.beta": {"label": "Beta", "action": "teeup install beta"},
  "status": {"label": "Status", "action": "teeup status"}
}
EOF2
}

test_menu_walks_into_a_submenu_and_runs_the_action() {
  setup
  write_test_menu
  local out
  out="$(printf '1\n1\n' | "$TEEUP" menu 2>&1)"
  assert_contains "$out" "1) + Install" || return 1
  assert_contains "$out" "install:alpha" || return 1
  "$TEEUP" has alpha || { echo "the action should really have installed alpha"; return 1; }
  cleanup_test_env
}

test_menu_hides_a_row_whose_when_predicate_fails() {
  setup
  write_test_menu
  "$TEEUP" install alpha >/dev/null
  local out
  out="$(printf '1\n\n' | "$TEEUP" menu 2>&1)"
  assert_contains "$out" "Beta" || return 1
  assert_not_contains "$out" "Alpha" "an installed alpha drops off the list" || return 1
  cleanup_test_env
}

test_menu_takes_a_route_and_offers_a_way_back() {
  setup
  write_test_menu
  local out
  out="$(printf '3\n\n' | "$TEEUP" menu install 2>&1)"
  assert_contains "$out" "Install something" || return 1
  assert_contains "$out" "3) .." || return 1
  assert_contains "$out" "1) + Install" "going back lands at the top level" || return 1
  cleanup_test_env
}

test_menu_rejects_an_unknown_route() {
  setup
  write_test_menu
  local rc=0 out
  out="$("$TEEUP" menu nosuch 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "No menu row with the id 'nosuch'" || return 1
  cleanup_test_env
}

# M2: `teeup menu <leaf id>` must run that row's action outright, the way
# the cmd_menu comment's own `omarchy menu summon style.theme` example says
# it does, rather than trying to list children under a route that has none
# and falling back with "Nothing left to show".
test_menu_route_to_a_leaf_runs_its_action() {
  setup
  write_test_menu
  local out rc=0
  out="$("$TEEUP" menu install.beta 2>&1)" || rc=$?
  assert_success "$rc" "$out" || return 1
  assert_contains "$out" "install:beta" "the leaf's action must actually run" || return 1
  assert_not_contains "$out" "Nothing left to show" || return 1
  cleanup_test_env
}

test_menu_dry_run_prints_the_action_instead_of_running_it() {
  setup
  write_test_menu
  local out
  out="$(printf '1\n1\n' | DRY_RUN=true "$TEEUP" menu 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would run: teeup install alpha" || return 1
  "$TEEUP" has alpha && { echo "a dry run must install nothing"; return 1; }
  cleanup_test_env
}

# R6.4: an empty line inside Install backs out to the top level rather than
# leaving the whole menu; a second empty line, now at the top level, is what
# actually exits. Two renders of the top level prove the walk went back
# rather than straight out after the first cancel.
test_menu_cancel_inside_a_submenu_goes_back_a_level() {
  setup
  write_test_menu
  local out rc=0 top_renders
  out="$(printf '1\n\n\n' | "$TEEUP" menu 2>&1)" || rc=$?
  assert_success "$rc" "a cancel at the top level is not an error" || return 1
  assert_contains "$out" "Install something" "entering Install shows its title" || return 1
  top_renders="$(printf '%s\n' "$out" | grep -cF '1) + Install')"
  assert_equals "2" "$top_renders" "the top level renders again after backing out of Install" || return 1
  cleanup_test_env
}

test_theme_set_without_a_name_opens_the_picker() {
  setup
  # Two complete palettes, copied from the one theme the repo ships, so the
  # render really succeeds; theme_list sorts, so the second is choice 2.
  export TEEUP_THEMES_DIR="$TEST_HOME/themes"
  mkdir -p "$TEEUP_THEMES_DIR"
  cp -R "$TEEUP_PATH/themes/catppuccin" "$TEEUP_THEMES_DIR/aaa-first"
  cp -R "$TEEUP_PATH/themes/catppuccin" "$TEEUP_THEMES_DIR/zzz-second"
  local out
  out="$(printf '2\n' | "$TEEUP" theme set 2>&1)"
  assert_contains "$out" "2) zzz-second" || return 1
  assert_equals "zzz-second" "$("$TEEUP" theme current)" || return 1
  local rc=0
  out="$(printf '\n' | "$TEEUP" theme set 2>&1)" || rc=$?
  assert_success "$rc" "backing out of the picker is not an error" || return 1
  assert_contains "$out" "Keeping the current theme" || return 1
  assert_equals "zzz-second" "$("$TEEUP" theme current)" "backing out changes nothing" || return 1
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
run_test "lazy-run exits 127 when the install fails" test_lazy_run_exits_127_when_the_install_fails
run_test "lazy-run does not mark installed when a dependency fails" test_lazy_run_does_not_mark_installed_when_a_dependency_fails
run_test "lazy-run respects TEEUP_SKIP" test_lazy_run_respects_teeup_skip
run_test "lazy-run reinstalls a capability whose command went missing" test_lazy_run_reinstalls_a_capability_whose_command_went_missing
run_test "lazy-run finds a command under the package prefix" test_lazy_run_finds_a_command_under_the_package_prefix
run_test "lazy-run dry run previews and runs nothing" test_lazy_run_dry_run_previews_and_runs_nothing
run_test "lazy-run rejects a command the capability does not provide" test_lazy_run_rejects_a_command_the_capability_does_not_provide
run_test "launch opens an installed app without installing" test_launch_opens_an_installed_app_without_installing
run_test "launch installs the capability then opens" test_launch_installs_the_capability_then_opens
run_test "launch fails clearly when the app never appears" test_launch_fails_clearly_when_the_app_never_appears
run_test "launch on macports consults the macports apps dir" test_launch_on_macports_consults_the_macports_apps_dir
run_test "launch dry run previews the open" test_launch_dry_run_previews_the_open
run_test "launch unknown app and skipped capability" test_launch_unknown_app_and_skipped_capability
run_test "launch opens the named app, not just the first" test_launch_opens_the_named_app_not_just_the_first
run_test "launch reports a real install failure instead of aborting" test_launch_reports_a_real_install_failure_instead_of_aborting
run_test "list notes the macports launch caveat" test_list_notes_the_macports_launch_caveat
run_test "install dev-env rejects extra arguments" test_install_dev_env_rejects_extra_arguments
run_test "install dev-env goes through mise" test_install_dev_env_goes_through_mise
run_test "data verbs keep stdout clean with a shadowed machine file" test_data_verbs_keep_stdout_clean_with_a_shadowed_machine_file
run_test "has stdout stays empty with a shadowed machine file" test_has_stdout_stays_empty_with_a_shadowed_machine_file
run_test "reset replaces edited files through configure" test_reset_replaces_edited_files_through_configure
run_test "reset dry run changes nothing" test_reset_dry_run_changes_nothing
run_test "reset refuses what it cannot reset" test_reset_refuses_what_it_cannot_reset
run_test "reset reports a refused write plainly" test_reset_reports_a_refused_write_plainly
run_test "dev add-migration creates a named scaffold" test_dev_add_migration_creates_a_named_scaffold
run_test "update upgrades packages before running migrations" test_update_upgrades_packages_before_running_migrations
run_test "update runs migrations before configuring" test_update_runs_migrations_before_configuring
run_test "update walks every step in order" test_update_walks_every_step_in_order
run_test "update skips core capabilities it never installed" test_update_skips_core_capabilities_it_never_installed
run_test "update refuses a dirty checkout" test_update_refuses_a_dirty_checkout
run_test "update carries on when the pull fails" test_update_carries_on_when_the_pull_fails
run_test "update one capability upgrades its packages and configures" test_update_one_capability_upgrades_its_packages_and_configures
run_test "update one capability refuses what it cannot update" test_update_one_capability_refuses_what_it_cannot_update
run_test "update runs a capability's own update script" test_update_runs_a_capabilitys_own_update_script
run_test "an update script is dry run and its failure is reported" test_an_update_script_is_dry_run_and_its_failure_is_reported
run_test "update skips a not-applicable capability" test_update_skips_a_not_applicable_capability
run_test "update does not treat a not-applicable configure as done" test_update_does_not_treat_a_not_applicable_configure_as_done
run_test "update carries on after a failed configure and still fails" test_update_carries_on_after_a_failed_configure_and_still_fails
run_test "update moves a newly inapplicable capability to not applicable" test_update_moves_a_newly_inapplicable_capability_to_not_applicable
run_test "update runs the theme fallback when theme is not applicable" test_update_runs_the_theme_fallback_when_theme_is_not_applicable
run_test "update dry run changes nothing" test_update_dry_run_changes_nothing
run_test "remove runs the script then uninstalls from metadata" test_remove_runs_the_script_then_uninstalls_from_metadata
run_test "remove without a script uses metadata alone" test_remove_without_a_script_uses_metadata_alone
run_test "remove refuses what something else requires" test_remove_refuses_what_something_else_requires
run_test "remove keeps config files and previews a dry run" test_remove_keeps_config_files_and_previews_a_dry_run
run_test "remove keeps the marker when an uninstall fails" test_remove_keeps_the_marker_when_an_uninstall_fails
run_test "remove dies when nothing can be undone" test_remove_dies_when_nothing_can_be_undone
run_test "remove is honest when the remove script answers not-applicable" test_remove_is_honest_when_the_remove_script_answers_not_applicable
run_test "remove refuses a not-applicable capability" test_remove_refuses_a_not_applicable_capability
run_test "doctor is quiet and zero when healthy" test_doctor_is_quiet_and_zero_when_nothing_is_installed_is_wrong
run_test "doctor names the failure and its fix" test_doctor_names_the_failure_and_the_command_that_fixes_it
run_test "doctor exits 2 when nothing failed but something could not be checked" test_doctor_exits_two_when_nothing_failed_but_something_could_not_be_checked
run_test "doctor checks an uninstalled capability" test_doctor_checks_one_capability_even_when_it_is_not_installed
run_test "doctor separates an empty machine from a fully skipped one" test_doctor_separates_an_empty_machine_from_a_fully_skipped_one
run_test "doctor reports an unreadable state dir instead of calling it empty" test_doctor_reports_an_unreadable_state_dir_instead_of_calling_it_empty
run_test "doctor reports an unreadable state dir parent instead of calling it empty" test_doctor_reports_an_unreadable_state_dir_parent_instead_of_calling_it_empty
run_test "doctor reports an unreadable state dir grandparent instead of calling it empty" test_doctor_reports_an_unreadable_state_dir_grandparent_instead_of_calling_it_empty
run_test "doctor rejects an unknown capability" test_doctor_rejects_an_unknown_capability
run_test "menu walks into a submenu and runs the action" test_menu_walks_into_a_submenu_and_runs_the_action
run_test "menu hides a row whose when fails" test_menu_hides_a_row_whose_when_predicate_fails
run_test "menu takes a route and offers a way back" test_menu_takes_a_route_and_offers_a_way_back
run_test "menu rejects an unknown route" test_menu_rejects_an_unknown_route
run_test "menu route to a leaf runs its action" test_menu_route_to_a_leaf_runs_its_action
run_test "menu dry run prints the action" test_menu_dry_run_prints_the_action_instead_of_running_it
run_test "menu cancel inside a submenu goes back a level" test_menu_cancel_inside_a_submenu_goes_back_a_level
run_test "theme set without a name opens the picker" test_theme_set_without_a_name_opens_the_picker
run_test "migrate requires a known target" test_migrate_requires_a_known_target
run_test "migrate legacy runs every step and closes with a real command" test_migrate_legacy_runs_every_step_and_closes_with_a_real_command
run_test "migrate legacy refuses the chezmoi half without teeup's zsh layer" test_migrate_legacy_refuses_the_chezmoi_half_without_teeups_zsh_layer
run_test "migrate legacy proceeds with teeup's zsh layer installed" test_migrate_legacy_proceeds_with_teeups_zsh_layer_installed
run_test "migrate legacy dry run changes nothing" test_migrate_legacy_dry_run_changes_nothing
run_test "migrate legacy exits non-zero when it refused something" test_migrate_legacy_exits_non_zero_when_it_refused_something
run_test "migrate appears in help" test_migrate_appears_in_help
run_test "config get lists every key and marks pins" test_config_get_lists_every_key_and_marks_the_pinned_ones
run_test "config get prints the effective value" test_config_get_prints_the_effective_value
run_test "config get refuses a runtime variable" test_config_get_refuses_a_runtime_variable_that_is_not_an_answer
run_test "config set writes the answers file" test_config_set_writes_the_answers_file
run_test "config set says when a pin makes it pointless" test_config_set_says_when_the_machine_file_makes_the_write_pointless
run_test "config set rejects a non-answer key" test_config_set_rejects_a_key_that_is_not_an_answer
run_test "config set refuses any work key" test_config_set_refuses_any_work_key
run_test "config set names an existing machine file even the checkout's" test_config_set_names_an_existing_machine_file_even_the_checkouts
run_test "config set dry run changes and claims nothing" test_config_set_dry_run_does_not_claim_success_or_write
run_test "config set names teeup configure git for name/email" test_config_set_says_the_git_identity_needs_reconfiguring
run_test "config set names teeup configure emacs for emacs flavor" test_config_set_says_emacs_needs_reconfiguring
run_test "config set names ./bootstrap for daily" test_config_set_says_daily_needs_a_fresh_bootstrap
run_test "config set redirects theme to teeup theme set" test_config_set_redirects_theme_to_theme_set
run_test "config set warns about package manager before install" test_config_set_warns_about_package_manager_before_it_is_installed
run_test "config set refuses package manager once installed" test_config_set_refuses_package_manager_once_it_is_installed
run_test "config set warns when nothing known applies the change" test_config_set_warns_when_nothing_known_applies_the_change
run_test "config keys accepts an exported machine line" test_config_keys_accepts_an_exported_machine_line
run_test "config get header lists both machine files" test_config_get_header_lists_both_machine_files_when_both_exist
run_test "config get shows a leftover work answer as ignored" test_config_get_shows_a_leftover_work_answer_as_ignored
run_test "config get shows the machine file's work answer as pinned" test_config_get_shows_the_machine_files_work_answer_as_pinned
run_test "config edit keeps a good edit" test_config_edit_runs_the_editor_and_keeps_a_good_edit
run_test "config edit rolls back a broken edit" test_config_edit_rolls_back_an_edit_that_will_not_parse
run_test "config edit rolls back a line that would run as a command" test_config_edit_rolls_back_a_line_that_would_run_as_a_command
run_test "config edit rolls back a bare value with a semicolon" test_config_edit_rolls_back_a_bare_value_with_a_semicolon
run_test "config edit restores the backup when the editor exits non-zero" test_config_edit_restores_the_backup_when_the_editor_exits_non_zero
run_test "config edit accepts a value answers_set itself escaped" test_config_edit_accepts_a_value_answers_set_itself_escaped
run_test "config edit rejects unescaped command substitution" test_config_edit_rejects_unescaped_command_substitution_in_a_quoted_value
run_test "config edit passes flags in EDITOR" test_config_edit_passes_flags_in_the_editor_variable
run_test "config edit dry run creates and touches nothing" test_config_edit_dry_run_creates_and_touches_nothing
print_summary
