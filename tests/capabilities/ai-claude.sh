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
  source "$TEEUP_PATH/lib/all.sh"
}

test_install_is_a_dry_run_noop() {
  setup
  local before after
  before="$(find "$TEST_HOME" -type f | sort)"
  DRY_RUN=true cap_run ai-claude install >/dev/null 2>&1
  after="$(find "$TEST_HOME" -type f | sort)"
  assert_equals "$before" "$after" "a dry run must write nothing" || return 1
  cleanup_test_env
}

test_configure_writes_nothing_in_a_dry_run() {
  setup
  local before after
  before="$(find "$TEST_HOME" -type f | sort)"
  DRY_RUN=true cap_run ai-claude configure >/dev/null 2>&1
  after="$(find "$TEST_HOME" -type f | sort)"
  assert_equals "$before" "$after" "a dry run must write nothing" || return 1
  cleanup_test_env
}

test_configure_writes_the_claude_wrapper() {
  setup
  DRY_RUN=false cap_run ai-claude configure >/dev/null
  assert_file_exists "$TEST_HOME/.local/bin/claude" || return 1
  cleanup_test_env
}

echo "capabilities/ai-claude"
run_test "install is a dry-run noop" test_install_is_a_dry_run_noop
run_test "configure writes nothing in a dry run" test_configure_writes_nothing_in_a_dry_run
run_test "configure writes the claude wrapper" test_configure_writes_the_claude_wrapper
print_summary
