#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  mock_command_script mise <<'EOF2'
exit 0
EOF2
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  source "$TEEUP_PATH/lib/all.sh"
}

test_install_is_a_dry_run_noop() {
  setup
  local before after
  before="$(find "$TEST_HOME" -type f | sort)"
  DRY_RUN=true cap_run ai-gemini install >/dev/null 2>&1
  after="$(find "$TEST_HOME" -type f | sort)"
  assert_equals "$before" "$after" "a dry run must write nothing" || return 1
  cleanup_test_env
}

test_configure_writes_nothing_in_a_dry_run() {
  setup
  local before after
  before="$(find "$TEST_HOME" -type f | sort)"
  DRY_RUN=true cap_run ai-gemini configure >/dev/null 2>&1
  after="$(find "$TEST_HOME" -type f | sort)"
  assert_equals "$before" "$after" "a dry run must write nothing" || return 1
  cleanup_test_env
}

test_configure_writes_the_gemini_wrapper_with_node() {
  setup
  DRY_RUN=false cap_run ai-gemini configure >/dev/null
  assert_file_exists "$TEST_HOME/.local/bin/gemini" || return 1
  assert_contains "$(cat "$TEST_HOME/.local/bin/gemini")" "for teeup_tool in node gemini-cli; do" || return 1
  cleanup_test_env
}

echo "capabilities/ai-gemini"
run_test "install is a dry-run noop" test_install_is_a_dry_run_noop
run_test "configure writes nothing in a dry run" test_configure_writes_nothing_in_a_dry_run
run_test "configure writes the gemini wrapper with node" test_configure_writes_the_gemini_wrapper_with_node
print_summary
