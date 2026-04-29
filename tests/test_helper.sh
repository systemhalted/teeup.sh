#!/usr/bin/env bash
# test_helper.sh — Common test utilities

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
declare -a FAILED_TESTS=()

setup_test_env() {
  export TEST_MODE="true"
  export TEST_HOME="$(mktemp -d)"
  export ZSHRC="$TEST_HOME/.zshrc"
  touch "$ZSHRC"
  export MOCK_BIN="$(mktemp -d)"
  export PATH="$MOCK_BIN:$PATH"
}

cleanup_test_env() {
  [[ -n "$TEST_HOME" && "$TEST_HOME" == /tmp/* ]] && rm -rf "$TEST_HOME"
  [[ -n "$MOCK_BIN" && "$MOCK_BIN" == /tmp/* ]] && rm -rf "$MOCK_BIN"
}

mock_command() {
  local cmd="$1"
  local exit_code="${2:-0}"
  local output="${3:-}"
  cat > "$MOCK_BIN/$cmd" <<EOF
#!/usr/bin/env bash
echo "$output"
exit $exit_code
EOF
  chmod +x "$MOCK_BIN/$cmd"
}

assert_equals() {
  local expected="$1" actual="$2" message="${3:-Values should be equal}"
  if [[ "$expected" == "$actual" ]]; then
    return 0
  fi
  echo "FAIL: $message"
  echo "  Expected: '$expected'"
  echo "  Actual:   '$actual'"
  return 1
}

assert_contains() {
  local haystack="$1" needle="$2" message="${3:-Should contain substring}"
  [[ "$haystack" == *"$needle"* ]] && return 0
  echo -e "${RED}FAIL: $message${RESET}\n  String: $haystack\n  Missing: $needle"
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

  # Run test directly (not in subshell for better error capture)
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
  echo "========================================"
  echo "Test Summary: $TESTS_PASSED/$TESTS_RUN passed"
  if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}Failed: ${FAILED_TESTS[*]}${RESET}"
  fi
  echo "========================================"
  [[ $TESTS_FAILED -eq 0 ]]
}
