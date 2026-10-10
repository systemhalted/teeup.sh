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

# tools_fixture: a lock of the test's own and a mise capability for the
# requires check to find.
tools_fixture() {
  TEEUP_TOOLS_LOCK="$TEST_HOME/tools.lock"
  printf 'ripgrep 15.2.0\nfd 10.5.0\n' > "$TEEUP_TOOLS_LOCK"
  make_cap mise lazy "" ""
}

# make_tool_cap <name> <mise_tools> [requires, default mise]
make_tool_cap() {
  make_cap "$1" lazy "${3-mise}" ""
  printf 'mise_tools="%s"\n' "$2" >> "$TEEUP_CAPS_DIR/$1/capability"
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

test_run_exit_130_stops_the_caller() {
  setup
  printf '#!/usr/bin/env bash\nexit 130\n' > "$TEEUP_CAPS_DIR/alpha/install"
  local rc=0 out
  out="$(cap_run alpha install || ui_rc_or_exit $?; echo carried-on)" || rc=$?
  assert_not_contains "$out" "carried-on" "caller went on after capability Ctrl-C" || return 1
  assert_equals 130 "$rc" "capability Ctrl-C exit status" || return 1
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

test_hook_eligible_needs_the_marker_or_a_running_configure() {
  setup
  cap_hook_eligible alpha && { echo "alpha was never installed"; return 1; }
  state_done mark cap-alpha
  cap_hook_eligible alpha || { echo "an installed capability is eligible"; return 1; }
  TEEUP_CONFIGURING=beta cap_hook_eligible beta || { echo "the capability being configured is eligible"; return 1; }
  TEEUP_CONFIGURING=alpha cap_hook_eligible beta && { echo "only the capability named by TEEUP_CONFIGURING"; return 1; }
  cleanup_test_env
}

test_run_hooks_skips_capabilities_that_were_never_installed() {
  setup
  local name
  for name in alpha beta lazyone; do
    printf '#!/usr/bin/env bash\necho "hook:%s"\n' "$name" > "$TEEUP_CAPS_DIR/$name/font-apply"
    chmod +x "$TEEUP_CAPS_DIR/$name/font-apply"
  done
  state_done mark cap-alpha
  state_done mark cap-lazyone
  local out rc=0
  out="$(TEEUP_SKIP=lazyone cap_run_hooks font-apply 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "hook:alpha" || return 1
  assert_not_contains "$out" "hook:beta" "beta was never installed" || return 1
  assert_not_contains "$out" "hook:lazyone" "a skipped capability stays skipped" || return 1
  cleanup_test_env
}

test_run_restores_the_outer_capability_after_a_nested_run() {
  setup
  printf '#!/usr/bin/env bash\ncap_run alpha install\necho "after nested: $TEEUP_CAP $TEEUP_CAP_DIR"\n' > "$TEEUP_CAPS_DIR/beta/configure"
  local out
  out="$(cap_run beta configure 2>&1)"
  assert_contains "$out" "install:alpha cap=alpha" || return 1
  assert_contains "$out" "after nested: beta $TEEUP_CAPS_DIR/beta" || return 1
  cleanup_test_env
}

# A capability with a remove script that reports what it was told, and a
# package and a cask for cap_remove's own loop. brew answers "installed" to
# every list query and logs every call.
make_removable() {
  cat >> "$TEEUP_CAPS_DIR/alpha/capability" <<'EOF2'
packages="ripgrep"
casks="wezterm"
EOF2
  printf '#!/usr/bin/env bash\necho "remove:alpha packages=${TEEUP_REMOVE_PACKAGES:-unset}"\n' > "$TEEUP_CAPS_DIR/alpha/remove"
  chmod +x "$TEEUP_CAPS_DIR/alpha/remove"
  mock_command brew 0 ""
  state_done mark cap-alpha
}

test_cap_remove_with_packages_runs_the_script_then_uninstalls() {
  setup
  make_removable
  # Not `out="$(cap_remove ... )"`: that runs cap_remove in a nested
  # subshell, so an export it forgets to unset dies with that subshell and
  # the check below would pass either way. Redirecting to a file instead
  # runs cap_remove in this function's own shell, where a leaked
  # TEEUP_REMOVE_PACKAGES would actually be seen.
  local out_file="$TEST_HOME/cap-remove.out" rc=0
  cap_remove alpha true >"$out_file" 2>&1 || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$(cat "$out_file")" "remove:alpha packages=true" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall --cask wezterm" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall ripgrep" || return 1
  state_done check cap-alpha && { echo "the marker must be cleared"; return 1; }
  [[ -z "${TEEUP_REMOVE_PACKAGES:-}" ]] || { echo "the variable must not outlive the script"; return 1; }
  cleanup_test_env
}

# `teeup uninstall` keeps packages unless asked: the remove script still runs
# (it owns machine state such as a LaunchAgent), nothing is uninstalled, and
# the capability is forgotten all the same.
test_cap_remove_without_packages_keeps_them_and_tells_the_script() {
  setup
  make_removable
  local out rc=0
  out="$(cap_remove alpha false 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "remove:alpha packages=false" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "uninstall" "packages were kept" || return 1
  state_done check cap-alpha && { echo "the marker must be cleared"; return 1; }
  cleanup_test_env
}

# The metadata keys are read by cap_meta_get in a subshell that can see the
# caller's locals, so a local named after a key would answer for a
# capability that does not set it. beta sets no packages= at all.
test_cap_remove_reads_packages_from_the_metadata_only() {
  setup
  mock_command brew 0 ""
  state_done mark cap-beta
  local rc=0
  cap_remove beta true >/dev/null 2>&1 || rc=$?
  assert_equals "2" "$rc" "beta has nothing to undo" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "uninstall" || return 1
  state_done check cap-beta || { echo "nothing was removed, so the marker stays"; return 1; }
  cleanup_test_env
}

test_cap_remove_reports_a_failed_script_and_a_failed_uninstall() {
  setup
  make_removable
  printf '#!/usr/bin/env bash\nexit 1\n' > "$TEEUP_CAPS_DIR/alpha/remove"
  local rc=0
  cap_remove alpha true >/dev/null 2>&1 || rc=$?
  assert_equals "3" "$rc" "a failed remove script" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "uninstall" "nothing is uninstalled after the script failed" || return 1
  state_done check cap-alpha || { echo "the marker stays"; return 1; }
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/alpha/remove"
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "uninstall --cask") exit 1 ;;
esac
exit 0
EOF2
  rc=0
  cap_remove alpha true >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "a failed uninstall" || return 1
  state_done check cap-alpha || { echo "the marker stays so a retry finds the cask"; return 1; }
  cleanup_test_env
}

test_cap_remove_takes_the_links_and_with_packages_the_pinned_installs() {
  setup
  tools_fixture
  mock_mise_tools
  make_tool_cap search "ripgrep:rg"
  state_done mark cap-search
  mise_tools_apply search >/dev/null 2>&1
  local link="$TEST_HOME/.local/bin/rg" conf="$TEST_HOME/.config/mise/conf.d/teeup.toml" rc=0
  [[ -L "$link" && -f "$conf" ]] || { echo "fixture: rg is linked and pinned"; return 1; }
  cap_remove search false >/dev/null 2>&1 || rc=$?
  assert_success "$rc" "a capability with only mise tools has something to undo" || return 1
  [[ ! -e "$link" && ! -L "$link" ]] || { echo "the link goes"; return 1; }
  [[ ! -e "$conf" ]] || { echo "nothing is pinned any more, so the conf.d file goes"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "uninstall" "without packages the install stays" || return 1
  state_done check cap-search && { echo "the marker is cleared"; return 1; }
  state_done mark cap-search
  mise_tools_apply search >/dev/null 2>&1
  cap_remove search true >/dev/null 2>&1 || { echo "remove with packages failed"; return 1; }
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / uninstall ripgrep@15.2.0" || return 1
  cleanup_test_env
}

test_cap_remove_keeps_the_marker_when_a_mise_uninstall_fails() {
  setup
  tools_fixture
  mock_mise_tools
  make_tool_cap search "ripgrep:rg"
  state_done mark cap-search
  mise_tools_apply search >/dev/null 2>&1
  local rc=0
  MOCK_MISE_FAIL_UNINSTALL=ripgrep cap_remove search true >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" || return 1
  state_done check cap-search || { echo "a retry must still find it"; return 1; }
  cleanup_test_env
}

test_check_accepts_well_formed_mise_tools() {
  setup
  tools_fixture
  make_tool_cap search "ripgrep:rg fd:fd"
  local out rc=0
  out="$(cap_check 2>&1)" || rc=$?
  assert_success "$rc" "a well-formed mise_tools must pass: $out" || return 1
  cleanup_test_env
}

test_check_rejects_a_bad_mise_tools_pair() {
  setup
  tools_fixture
  make_tool_cap search "ripgrep rg: :fd ripgrep:r/g"
  local out rc=0
  out="$(cap_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "search: mise_tools entry 'ripgrep' is not <tool>:<command>" || return 1
  assert_contains "$out" "search: mise_tools entry 'rg:' is not <tool>:<command>" || return 1
  assert_contains "$out" "search: mise_tools entry ':fd' is not <tool>:<command>" || return 1
  assert_contains "$out" "search: mise_tools entry 'ripgrep:r/g' is not <tool>:<command>" || return 1
  cleanup_test_env
}

test_check_rejects_a_mise_tool_without_a_lock_line() {
  setup
  tools_fixture
  make_tool_cap search "ripgrep:rg bat:bat"
  local out rc=0
  out="$(cap_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "search: mise_tools names bat, which has no line in $TEEUP_TOOLS_LOCK" || return 1
  assert_not_contains "$out" "names ripgrep" || return 1
  cleanup_test_env
}

test_check_rejects_a_mise_command_or_tool_in_two_capabilities() {
  setup
  tools_fixture
  make_tool_cap finder "fd:rg"
  make_tool_cap other "ripgrep:rga"
  make_tool_cap search "ripgrep:rg"
  local out rc=0
  out="$(cap_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "search: mise_tools command rg is also in finder" || return 1
  assert_contains "$out" "search: mise_tools tool ripgrep is also in other" || return 1
  cleanup_test_env
}

test_check_requires_mise_for_mise_tools() {
  setup
  tools_fixture
  make_tool_cap search "ripgrep:rg" ""
  local out rc=0
  out="$(cap_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "search: has mise_tools but does not require mise" || return 1
  cleanup_test_env
}

# What `./bin/teeup commands --check` runs in CI, against the shipped tree
# and the shipped lock, without running bin/teeup.
test_check_passes_on_the_shipped_tree() {
  setup
  TEEUP_CAPS_DIR="$TEEUP_PATH/capabilities"
  TEEUP_TOOLS_LOCK="$TEEUP_PATH/share/teeup/tools.lock"
  local out rc=0
  out="$(cap_check 2>&1)" || rc=$?
  assert_success "$rc" "the shipped capabilities must lint clean: $out" || return 1
  cleanup_test_env
}

# A first bootstrap installs core.list top to bottom, so mise must come before
# every capability that installs a tool through it, and every entry's
# requires must already be above it.
test_shipped_core_list_installs_mise_before_its_users() {
  setup
  TEEUP_CAPS_DIR="$TEEUP_PATH/capabilities"
  local seen=" " name r pos=0 mise_pos=""
  for name in $(cap_tier_list core); do
    pos=$((pos + 1))
    for r in $(cap_meta_get "$name" requires); do
      case "$seen" in
        *" $r "*) ;;
        *) echo "$name requires $r, which core.list puts later"; return 1 ;;
      esac
    done
    if [[ "$name" == "mise" ]]; then mise_pos="$pos"; fi
    # shellcheck disable=SC2194  # a membership check against a fixed roster, not a variable
    case " zsh starship cli-tools git " in
      *" $name "*)
        [[ -n "$mise_pos" ]] || { echo "$name comes before mise in core.list"; return 1; }
        ;;
    esac
    seen="$seen$name "
  done
  for name in cli-tools git starship neovim tmux herdr ollama; do
    case " $(cap_meta_get "$name" requires) " in
      *" mise "*) ;;
      *) echo "$name does not require mise"; return 1 ;;
    esac
  done
  cleanup_test_env
}

echo "lib/capability.sh"
run_test "list and exists" test_list_and_exists
run_test "meta get with default" test_meta_get_with_default
run_test "tier list skips comments" test_tier_list_skips_comments
run_test "order puts requires first and dedupes" test_order_puts_requires_first_and_dedupes
run_test "run executes script with lib and env" test_run_executes_script_with_lib_and_env
run_test "run propagates failure" test_run_propagates_failure
run_test "run exit 130 stops the caller" test_run_exit_130_stops_the_caller
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
run_test "hook eligible needs the marker or a running configure" test_hook_eligible_needs_the_marker_or_a_running_configure
run_test "run restores the outer capability after a nested run" test_run_restores_the_outer_capability_after_a_nested_run
run_test "run_hooks skips capabilities that were never installed" test_run_hooks_skips_capabilities_that_were_never_installed
run_test "cap_remove with packages runs the script then uninstalls" test_cap_remove_with_packages_runs_the_script_then_uninstalls
run_test "cap_remove without packages keeps them and tells the script" test_cap_remove_without_packages_keeps_them_and_tells_the_script
run_test "cap_remove reads packages from the metadata only" test_cap_remove_reads_packages_from_the_metadata_only
run_test "cap_remove reports a failed script and a failed uninstall" test_cap_remove_reports_a_failed_script_and_a_failed_uninstall
run_test "cap_remove takes the links and, with packages, the pinned installs" test_cap_remove_takes_the_links_and_with_packages_the_pinned_installs
run_test "cap_remove keeps the marker when a mise uninstall fails" test_cap_remove_keeps_the_marker_when_a_mise_uninstall_fails
run_test "check accepts well-formed mise_tools" test_check_accepts_well_formed_mise_tools
run_test "check rejects a bad mise_tools pair" test_check_rejects_a_bad_mise_tools_pair
run_test "check rejects a mise tool without a lock line" test_check_rejects_a_mise_tool_without_a_lock_line
run_test "check rejects a mise command or tool in two capabilities" test_check_rejects_a_mise_command_or_tool_in_two_capabilities
run_test "check requires mise for mise_tools" test_check_requires_mise_for_mise_tools
run_test "check passes on the shipped tree" test_check_passes_on_the_shipped_tree
run_test "shipped core.list installs mise before its users" test_shipped_core_list_installs_mise_before_its_users
print_summary
