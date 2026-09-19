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
}

test_install_gets_tmux() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install tmux)"
  assert_contains "$out" "Would execute: brew install tmux" || return 1
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

echo "capabilities/tmux"
run_test "install gets tmux" test_install_gets_tmux
run_test "configure installs the config once" test_configure_installs_the_config_once
run_test "configure leaves an existing home config alone" test_configure_leaves_an_existing_home_config_alone
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "shim is generated for tmux" test_shim_is_generated_for_tmux
print_summary
