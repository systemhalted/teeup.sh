#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  # The host may ship herdr; the install tests only preview.
  export TEEUP_TEST_MISSING="herdr"
  TEEUP="$TEEUP_PATH/bin/teeup"
  # Nothing in this suite may reach the host's mise (Task 5, #112).
  mock_mise_tools
}

test_install_gets_the_pinned_herdr() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install herdr 2>&1)"
  assert_contains "$out" "Would execute: mise -C / install herdr@$(lock_version herdr)" || return 1
  assert_not_contains "$out" "brew install herdr" || return 1
  cleanup_test_env
}

test_install_on_macports_still_uses_mise() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install herdr 2>&1)"
  assert_contains "$out" "Would execute: mise -C / install herdr@$(lock_version herdr)" || return 1
  assert_not_contains "$out" "port install herdr" || return 1
  cleanup_test_env
}

test_shim_is_generated_for_herdr() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  assert_file_exists "$TEST_HOME/.local/state/teeup/shims/herdr" || return 1
  cleanup_test_env
}

echo "capabilities/herdr"
run_test "install gets the pinned herdr" test_install_gets_the_pinned_herdr
run_test "install on MacPorts still uses mise" test_install_on_macports_still_uses_mise
run_test "shim is generated for herdr" test_shim_is_generated_for_herdr
print_summary
