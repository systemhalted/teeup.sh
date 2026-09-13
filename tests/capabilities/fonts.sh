#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_dry_run_gets_the_cask() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install fonts)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask font-jetbrains-mono-nerd-font" || return 1
  cleanup_test_env
}

test_configure_records_the_default_family() {
  setup
  DRY_RUN=false "$TEEUP" configure fonts >/dev/null
  assert_equals "JetBrainsMono Nerd Font" "$(cat "$TEST_HOME/.local/state/teeup/current/font")" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  DRY_RUN=false "$TEEUP" configure fonts >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure fonts)"
  assert_contains "$out" "Font already recorded: JetBrainsMono Nerd Font" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  DRY_RUN=true "$TEEUP" configure fonts >/dev/null
  [[ ! -e "$TEST_HOME/.local/state/teeup/current/font" ]] || { echo "state written in dry run"; return 1; }
  cleanup_test_env
}

test_configure_warns_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(DRY_RUN=false "$TEEUP" configure fonts 2>&1)"
  assert_contains "$out" "MacPorts has no Nerd Font ports" || return 1
  cleanup_test_env
}

test_install_font_switches_the_family() {
  setup
  DRY_RUN=false "$TEEUP" configure fonts >/dev/null
  DRY_RUN=false "$TEEUP" install font "Cascadia Mono" >/dev/null
  assert_equals "CaskaydiaMono Nerd Font" "$(cat "$TEST_HOME/.local/state/teeup/current/font")" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew install --cask font-caskaydia-mono-nerd-font" || return 1
  cleanup_test_env
}

test_install_font_list_prints_the_table() {
  setup
  assert_contains "$(DRY_RUN=false "$TEEUP" install font list)" "font-hack-nerd-font" || return 1
  cleanup_test_env
}

test_install_font_unknown_fails() {
  setup
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" install font 'Comic Sans' 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Unknown font: Comic Sans" || return 1
  cleanup_test_env
}

test_install_font_refuses_when_fonts_is_skipped() {
  setup
  # TEEUP_SKIP="fonts" is how a managed Mac says no casks; `teeup install font`
  # installs a cask, so it must honour the skip like `teeup install fonts`.
  local rc=0 out
  out="$(TEEUP_SKIP="fonts wezterm" DRY_RUN=false "$TEEUP" install font hack 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "fonts is skipped on this machine (TEEUP_SKIP)" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew install" || return 1
  [[ ! -e "$TEST_HOME/.local/state/teeup/current/font" ]] || { echo "font recorded despite the skip"; return 1; }
  assert_contains "$(TEEUP_SKIP=fonts DRY_RUN=false "$TEEUP" install font list)" "font-hack-nerd-font" "listing installs nothing, so it stays allowed" || return 1
  cleanup_test_env
}

echo "capabilities/fonts"
run_test "install dry run gets the cask" test_install_dry_run_gets_the_cask
run_test "configure records the default family" test_configure_records_the_default_family
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "configure warns on macports" test_configure_warns_on_macports
run_test "install font switches the family" test_install_font_switches_the_family
run_test "install font list prints the table" test_install_font_list_prints_the_table
run_test "install font unknown fails" test_install_font_unknown_fails
run_test "install font refuses when fonts is skipped" test_install_font_refuses_when_fonts_is_skipped
print_summary
