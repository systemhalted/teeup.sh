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
print_summary
