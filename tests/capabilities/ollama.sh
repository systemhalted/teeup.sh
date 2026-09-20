#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  mock_command open 0 ""
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  export TEEUP_TEST_MISSING="ollama"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_gets_the_cask() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install ollama)"
  assert_contains "$out" "Would execute: brew install --cask ollama-app" || return 1
  assert_not_contains "$out" "brew install ollama" || return 1
  assert_not_contains "$out" "ollama pull llama3.2" || return 1
  cleanup_test_env
}

test_install_falls_back_to_the_formula_when_the_cask_fails() {
  setup
  # A real macOS 13 Mac: the cask refuses, the formula installs, and this
  # time the floor really is why (I6).
  mock_command sw_vers 0 "13.6"
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "list "*) exit 1 ;;
  "install --cask") exit 1 ;;
esac
exit 0
EOF2
  local out
  out="$(DRY_RUN=false "$TEEUP" install ollama 2>&1)"
  assert_contains "$out" "The ollama-app cask did not install (it needs macOS 14 or newer; this Mac is on macOS 13)" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew install ollama" || return 1
  "$TEEUP" has ollama || { echo "ollama must be marked installed"; return 1; }
  cleanup_test_env
}

# I6: on a Mac that already meets the floor, a cask failure has some other
# cause (network, tap, quarantine); the message must not blame a version it
# never checked failed.
test_install_falls_back_without_blaming_macos_when_this_mac_is_current() {
  setup
  # mock_macos_base reports macOS 14.6.1, comfortably above the floor.
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "list "*) exit 1 ;;
  "install --cask") exit 1 ;;
esac
exit 0
EOF2
  local out
  out="$(DRY_RUN=false "$TEEUP" install ollama 2>&1)"
  assert_contains "$out" "The ollama-app cask did not install; installing the ollama formula instead." || return 1
  assert_not_contains "$out" "macOS 14 or newer" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew install ollama" || return 1
  "$TEEUP" has ollama || { echo "ollama must be marked installed"; return 1; }
  cleanup_test_env
}

test_install_uses_the_port_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install ollama)"
  assert_contains "$out" "Would execute: sudo port install ollama" || return 1
  assert_not_contains "$out" "--cask" || return 1
  cleanup_test_env
}

test_configure_names_the_pull_command_only_when_it_exists() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ollama 2>&1)"
  assert_not_contains "$out" "ollama pull" || return 1
  unset TEEUP_TEST_MISSING
  mock_command ollama 0 ""
  out="$(DRY_RUN=false "$TEEUP" configure ollama)"
  assert_contains "$out" "ollama pull llama3.2" || return 1
  cleanup_test_env
}

test_launch_opens_the_app_and_the_shim_exists() {
  setup
  mkdir -p "$TEEUP_APPS_DIR/Ollama.app"
  DRY_RUN=false "$TEEUP" launch ollama >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "open -a Ollama" || return 1
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  assert_file_exists "$TEST_HOME/.local/state/teeup/shims/ollama" || return 1
  cleanup_test_env
}

echo "capabilities/ollama"
run_test "install gets the cask" test_install_gets_the_cask
run_test "install falls back to the formula when the cask fails" test_install_falls_back_to_the_formula_when_the_cask_fails
run_test "install falls back without blaming macOS when this Mac is current" test_install_falls_back_without_blaming_macos_when_this_mac_is_current
run_test "install uses the port on macports" test_install_uses_the_port_on_macports
run_test "configure names the pull command only when it exists" test_configure_names_the_pull_command_only_when_it_exists
run_test "launch opens the app and the shim exists" test_launch_opens_the_app_and_the_shim_exists
print_summary
