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
}

test_install_gets_the_formula() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install herdr)"
  assert_contains "$out" "Would execute: brew install herdr" || return 1
  cleanup_test_env
}

test_install_uses_the_port_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install herdr)"
  assert_contains "$out" "Would execute: sudo port install herdr" || return 1
  cleanup_test_env
}

test_shim_is_generated_for_herdr() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  assert_file_exists "$TEST_HOME/.local/state/teeup/shims/herdr" || return 1
  cleanup_test_env
}

echo "capabilities/herdr"
run_test "install gets the formula" test_install_gets_the_formula
run_test "install uses the port on macports" test_install_uses_the_port_on_macports
run_test "shim is generated for herdr" test_shim_is_generated_for_herdr
print_summary
