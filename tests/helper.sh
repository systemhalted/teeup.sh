#!/usr/bin/env bash
# helper.sh - mock harness for the new teeup runtime.
# Sourced by every test file. Creates a throwaway $HOME and a mock bin dir
# that is first on PATH, so tests never touch the real machine.

RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEEUP_PATH="$(dirname "$TESTS_DIR")"
export TEEUP_PATH

setup_test_env() {
  TEST_HOME="$(mktemp -d)"
  export TEST_HOME
  export HOME="$TEST_HOME"
  export XDG_CONFIG_HOME="$TEST_HOME/.config"
  export XDG_STATE_HOME="$TEST_HOME/.local/state"
  MOCK_BIN="$(mktemp -d)"
  export MOCK_BIN
  export MOCK_LOG="$TEST_HOME/mock.log"
  : > "$MOCK_LOG"
  export PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
  export DRY_RUN="${DRY_RUN:-false}"
  # Keeps tests away from the real /opt/homebrew on macOS CI runners.
  export TEEUP_PKG_PREFIX="$TEST_HOME/pkgprefix"
  unset TEEUP_CONFIG_DIR TEEUP_STATE_DIR TEEUP_ANSWERS_FILE TEEUP_LOG_FILE
}

cleanup_test_env() {
  case "${TEST_HOME:-}" in
    /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) rm -rf "$TEST_HOME" ;;
  esac
  case "${MOCK_BIN:-}" in
    /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) rm -rf "$MOCK_BIN" ;;
  esac
}

# mock_command <name> [exit_code] [stdout]
# Every call is appended to $MOCK_LOG as "<name> <args>".
mock_command() {
  local cmd="$1" exit_code="${2:-0}" output="${3:-}"
  cat > "$MOCK_BIN/$cmd" <<EOF2
#!/usr/bin/env bash
echo "$cmd \$*" >> "\$MOCK_LOG"
[ -n "$output" ] && echo "$output"
exit $exit_code
EOF2
  chmod +x "$MOCK_BIN/$cmd"
}

# mock_command_script <name>  (body on stdin)
mock_command_script() {
  local cmd="$1"
  {
    echo "#!/usr/bin/env bash"
    echo "echo \"$cmd \$*\" >> \"\$MOCK_LOG\""
    cat
  } > "$MOCK_BIN/$cmd"
  chmod +x "$MOCK_BIN/$cmd"
}

# A modern Apple Silicon Mac with CLT present and Homebrew missing.
mock_macos_base() {
  mock_command_script uname <<'EOF2'
case "$1" in
  -s) echo Darwin ;;
  -m) echo arm64 ;;
  *) echo Darwin ;;
esac
EOF2
  mock_command sw_vers 0 "14.6.1"
  mock_command xcode-select 0 "/Library/Developer/CommandLineTools"
  mock_command pkgutil 0 ""
  mock_command hostname 0 "testmac"
  mock_command sudo 0 ""
  mock_command id 0 "501"
}

assert_equals() {
  local expected="$1" actual="$2" message="${3:-Values should be equal}"
  [[ "$expected" == "$actual" ]] && return 0
  echo -e "${RED}FAIL: $message${RESET}\n  Expected: '$expected'\n  Actual:   '$actual'"
  return 1
}

assert_contains() {
  local haystack="$1" needle="$2" message="${3:-Should contain substring}"
  [[ "$haystack" == *"$needle"* ]] && return 0
  echo -e "${RED}FAIL: $message${RESET}\n  String: $haystack\n  Missing: $needle"
  return 1
}

assert_not_contains() {
  local haystack="$1" needle="$2" message="${3:-Should not contain substring}"
  [[ "$haystack" != *"$needle"* ]] && return 0
  echo -e "${RED}FAIL: $message${RESET}\n  String: $haystack\n  Unexpected: $needle"
  return 1
}

assert_file_exists() {
  local file="$1" message="${2:-File should exist}"
  [[ -f "$file" ]] && return 0
  echo -e "${RED}FAIL: $message${RESET}\n  File not found: $file"
  return 1
}

assert_dir_exists() {
  local dir="$1" message="${2:-Directory should exist}"
  [[ -d "$dir" ]] && return 0
  echo -e "${RED}FAIL: $message${RESET}\n  Dir not found: $dir"
  return 1
}

assert_success() {
  local exit_code="$1" message="${2:-Command should succeed}"
  [[ "$exit_code" -eq 0 ]] && return 0
  echo -e "${RED}FAIL: $message${RESET}\n  Exit code: $exit_code"
  return 1
}

assert_failure() {
  local exit_code="$1" message="${2:-Command should fail}"
  [[ "$exit_code" -ne 0 ]] && return 0
  echo -e "${RED}FAIL: $message${RESET}\n  Expected non-zero exit"
  return 1
}

run_test() {
  local test_name="$1" test_func="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  echo -n "  $test_name... "
  set +e
  local output
  output=$($test_func 2>&1)
  local result=$?
  set -e
  if [[ $result -eq 0 ]]; then
    echo -e "${GREEN}PASS${RESET}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "${RED}FAIL${RESET}"
    [[ -n "$output" ]] && echo "$output"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$test_name")
  fi
}

print_summary() {
  echo ""
  echo "Summary: $TESTS_PASSED/$TESTS_RUN passed"
  if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}Failed: ${FAILED_TESTS[*]}${RESET}"
  fi
  [[ $TESTS_FAILED -eq 0 ]]
}
