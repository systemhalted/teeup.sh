#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  # The host may ship tmux; the install tests only preview.
  export TEEUP_TEST_MISSING="tmux"
  TEEUP="$TEEUP_PATH/bin/teeup"
  CONF="$TEST_HOME/.config/tmux/tmux.conf"
  # Nothing in this suite may reach the host's mise (Task 5, #112).
  mock_mise_tools
}

test_install_gets_tmux() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install tmux 2>&1)"
  assert_contains "$out" "Would execute: mise -C / install tmux@$(lock_version tmux)" || return 1
  assert_not_contains "$out" "brew install tmux" || return 1
  cleanup_test_env
}

test_configure_installs_the_config_once() {
  setup
  DRY_RUN=false "$TEEUP" configure tmux >/dev/null
  assert_file_exists "$CONF" || return 1
  assert_contains "$(cat "$CONF")" "set-option -g prefix C-a" || return 1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure tmux)"
  assert_contains "$out" "Already installed: $CONF" || return 1
  cleanup_test_env
}

test_configure_leaves_an_existing_home_config_alone() {
  setup
  printf 'set -g mouse on\n' > "$TEST_HOME/.tmux.conf"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure tmux)"
  assert_contains "$out" "Keeping your $TEST_HOME/.tmux.conf" || return 1
  # tmux loads both files, the XDG one last, so a second copy would
  # override the user's own settings.
  [[ ! -e "$CONF" ]] || { echo "no second config next to ~/.tmux.conf"; return 1; }
  assert_equals "set -g mouse on" "$(cat "$TEST_HOME/.tmux.conf")" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" configure tmux)"
  assert_contains "$out" "Would install $CONF" || return 1
  [[ ! -e "$CONF" ]] || { echo "written in dry run"; return 1; }
  cleanup_test_env
}

test_shim_is_generated_for_tmux() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  assert_file_exists "$TEST_HOME/.local/state/teeup/shims/tmux" || return 1
  cleanup_test_env
}

# M8: mise_tool_install keeps a tmux the user put in ~/.local/bin, so a
# pre-existing 2.x tmux would get an XDG config it can never read while
# teeup's "Installed" message implies it took effect.
test_configure_warns_when_the_installed_tmux_predates_xdg_support() {
  setup
  unset TEEUP_TEST_MISSING
  mkdir -p "$TEST_HOME/.local/bin"
  printf '#!/usr/bin/env bash\n[ "$1" = "-V" ] && echo "tmux 2.8"\n' > "$TEST_HOME/.local/bin/tmux"
  chmod +x "$TEST_HOME/.local/bin/tmux"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure tmux 2>&1)"
  assert_contains "$out" "tmux 2.8 does not read $CONF on its own (tmux 3.1 or newer does)" || return 1
  assert_file_exists "$CONF" || return 1
  cleanup_test_env
}

test_configure_is_silent_about_the_version_when_tmux_is_current() {
  setup
  unset TEEUP_TEST_MISSING
  mkdir -p "$TEST_HOME/.local/bin"
  printf '#!/usr/bin/env bash\n[ "$1" = "-V" ] && echo "tmux 3.3a"\n' > "$TEST_HOME/.local/bin/tmux"
  chmod +x "$TEST_HOME/.local/bin/tmux"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure tmux 2>&1)"
  assert_not_contains "$out" "does not read" || return 1
  cleanup_test_env
}

test_configure_never_guesses_at_an_unparsable_version() {
  setup
  unset TEEUP_TEST_MISSING
  mkdir -p "$TEST_HOME/.local/bin"
  printf '#!/usr/bin/env bash\n[ "$1" = "-V" ] && echo "tmux next-3.4"\n' > "$TEST_HOME/.local/bin/tmux"
  chmod +x "$TEST_HOME/.local/bin/tmux"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure tmux 2>&1)"
  assert_not_contains "$out" "does not read" || return 1
  cleanup_test_env
}

test_install_is_not_applicable_when_mise_is_skipped() {
  setup
  local out
  out="$(TEEUP_SKIP=mise DRY_RUN=false "$TEEUP" install tmux 2>&1)" || true
  assert_contains "$out" "tmux comes from mise, which is skipped on this machine (TEEUP_SKIP)." || return 1
  "$TEEUP" has tmux && { echo "tmux must not be marked installed"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "brew install tmux" || return 1
  cleanup_test_env
}

# The lazy round trip through mise: the shim asks, the install links
# ~/.local/bin/tmux, the link runs, and the next call needs no teeup at all.
test_shim_round_trip_installs_tmux_through_mise_and_runs_it() {
  setup
  export TEEUP_NO_GUM=1
  local shims="$TEST_HOME/.local/state/teeup/shims" out
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null 2>&1
  assert_file_exists "$shims/tmux" || return 1
  export PATH="$MOCK_BIN:$TEST_HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$shims"
  export TEEUP_TEST_MISSING=""
  hide_host_commands tmux
  out="$(printf 'y\n' | TEEUP_TEST_TTY=yes DRY_RUN=false "$shims/tmux" new -s work 2>&1)"
  assert_contains "$out" "tmux is provided by capability tmux. Install now?" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install tmux@$(lock_version tmux)" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew install tmux" || return 1
  assert_contains "$out" "tmux ran: new -s work" || return 1
  [[ -L "$TEST_HOME/.local/bin/tmux" ]] || { echo "the link must be in ~/.local/bin"; return 1; }
  "$TEEUP" has tmux || { echo "tmux must be marked installed"; return 1; }
  assert_equals "$TEST_HOME/.local/bin/tmux" "$(command -v tmux)" "the link comes before the shim" || return 1
  cleanup_test_env
}

echo "capabilities/tmux"
# The reload key must point at the file tmux actually loaded. configure
# installs under $XDG_CONFIG_HOME when one is set, so a literal
# ~/.config/tmux/tmux.conf in the binding would reload the wrong file, or
# none. run-shell expands the variable in the user's environment at press
# time, which a source-file argument cannot do.
test_the_reload_key_follows_xdg_config_home() {
  setup
  local conf="$TEEUP_PATH/capabilities/tmux/config/tmux/tmux.conf"
  assert_file_exists "$conf" || return 1
  local reload
  reload="$(grep -n 'bind r' "$conf")"
  assert_contains "$reload" 'XDG_CONFIG_HOME' || return 1
  if grep -q 'source-file ~/.config' <<<"$reload"; then
    echo "the reload key still names a literal ~/.config path"
    return 1
  fi
  cleanup_test_env
}

run_test "install gets tmux" test_install_gets_tmux
run_test "the reload key follows XDG_CONFIG_HOME" test_the_reload_key_follows_xdg_config_home
run_test "configure installs the config once" test_configure_installs_the_config_once
run_test "configure leaves an existing home config alone" test_configure_leaves_an_existing_home_config_alone
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "shim is generated for tmux" test_shim_is_generated_for_tmux
run_test "configure warns when the installed tmux predates XDG support" test_configure_warns_when_the_installed_tmux_predates_xdg_support
run_test "configure is silent about the version when tmux is current" test_configure_is_silent_about_the_version_when_tmux_is_current
run_test "configure never guesses at an unparsable version" test_configure_never_guesses_at_an_unparsable_version
run_test "install is not applicable when mise is skipped" test_install_is_not_applicable_when_mise_is_skipped
run_test "shim round trip installs tmux through mise and runs it" test_shim_round_trip_installs_tmux_through_mise_and_runs_it
print_summary
