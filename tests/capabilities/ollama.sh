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
  # Nothing in this suite may reach the host's mise (Task 5, #112).
  mock_mise_tools
}

test_install_gets_the_cask_and_the_pinned_command() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install ollama 2>&1)"
  assert_contains "$out" "Would execute: brew install --cask ollama-app" || return 1
  assert_contains "$out" "Would execute: mise -C / install ollama@$(lock_version ollama)" || return 1
  assert_not_contains "$out" "brew install ollama" || return 1
  assert_not_contains "$out" "ollama pull llama3.2" || return 1
  cleanup_test_env
}

test_install_keeps_the_mise_command_when_the_cask_fails_on_an_old_mac() {
  setup
  # A real macOS 13 Mac: the cask refuses, and this time the floor really is
  # why (I6).
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
  assert_contains "$out" "The ollama-app cask did not install (it needs macOS 14 or newer; this Mac is on macOS 13)." || return 1
  assert_contains "$out" "start the server with: ollama serve" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install ollama@$(lock_version ollama)" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew install ollama" "the formula fallback is gone" || return 1
  "$TEEUP" has ollama || { echo "ollama must be marked installed"; return 1; }
  cleanup_test_env
}

# I6: on a Mac that already meets the floor, a cask failure has some other
# cause (network, tap, quarantine); the message must not blame a version it
# never checked failed.
test_install_does_not_blame_macos_when_this_mac_is_current() {
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
  assert_contains "$out" "The ollama-app cask did not install. The ollama command still comes from mise" || return 1
  assert_not_contains "$out" "macOS 14 or newer" || return 1
  "$TEEUP" has ollama || { echo "ollama must be marked installed"; return 1; }
  cleanup_test_env
}

test_install_on_macports_uses_mise_and_no_port() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install ollama 2>&1)"
  assert_contains "$out" "Would execute: mise -C / install ollama@$(lock_version ollama)" || return 1
  assert_not_contains "$out" "port install ollama" || return 1
  assert_not_contains "$out" "--cask" || return 1
  cleanup_test_env
}

# With mise skipped, the ollama command has no source, so a Mac that also
# cannot get the app has nothing of Ollama to install.
OLLAMA_NA_MESSAGE="Ollama needs either the Ollama app (a Homebrew cask) or mise for the ollama command; mise is skipped and the app could not be installed here."

test_install_on_macports_is_not_applicable_when_mise_is_skipped() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(TEEUP_SKIP=mise DRY_RUN=false "$TEEUP" install ollama 2>&1)" || true
  assert_contains "$out" "$OLLAMA_NA_MESSAGE" || return 1
  assert_not_contains "$out" "the ollama command comes from mise" "no promise of a command mise will not install" || return 1
  "$TEEUP" has ollama && { echo "ollama must not be marked installed"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "mise -C / install" || return 1
  cleanup_test_env
}

test_install_is_not_applicable_when_the_cask_fails_and_mise_is_skipped() {
  setup
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "list "*) exit 1 ;;
  "install --cask") exit 1 ;;
esac
exit 0
EOF2
  local out
  out="$(TEEUP_SKIP=mise DRY_RUN=false "$TEEUP" install ollama 2>&1)" || true
  assert_contains "$(cat "$MOCK_LOG")" "brew install --cask ollama-app" "the app is tried first" || return 1
  assert_contains "$out" "$OLLAMA_NA_MESSAGE" || return 1
  assert_not_contains "$out" "The ollama command still comes from mise" || return 1
  "$TEEUP" has ollama && { echo "ollama must not be marked installed"; return 1; }
  cleanup_test_env
}

# The app alone is still Ollama: install warns about the missing command and
# succeeds, as before.
test_install_keeps_the_app_when_mise_is_skipped() {
  setup
  local out
  out="$(TEEUP_SKIP=mise DRY_RUN=false "$TEEUP" install ollama 2>&1)" || { echo "install failed: $out"; return 1; }
  assert_contains "$out" "only the app was installed" || return 1
  assert_not_contains "$out" "$OLLAMA_NA_MESSAGE" || return 1
  "$TEEUP" has ollama || { echo "ollama must be marked installed"; return 1; }
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
run_test "install gets the cask and the pinned command" test_install_gets_the_cask_and_the_pinned_command
run_test "install keeps the mise command when the cask fails on an old Mac" test_install_keeps_the_mise_command_when_the_cask_fails_on_an_old_mac
run_test "install does not blame macOS when this Mac is current" test_install_does_not_blame_macos_when_this_mac_is_current
run_test "install on MacPorts uses mise and no port" test_install_on_macports_uses_mise_and_no_port
run_test "install on MacPorts is not applicable when mise is skipped" test_install_on_macports_is_not_applicable_when_mise_is_skipped
run_test "install is not applicable when the cask fails and mise is skipped" test_install_is_not_applicable_when_the_cask_fails_and_mise_is_skipped
run_test "install keeps the app when mise is skipped" test_install_keeps_the_app_when_mise_is_skipped
run_test "configure names the pull command only when it exists" test_configure_names_the_pull_command_only_when_it_exists
run_test "launch opens the app and the shim exists" test_launch_opens_the_app_and_the_shim_exists
print_summary
