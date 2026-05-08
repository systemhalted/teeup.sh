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
  export HOME="$TEST_HOME"
  export ZSHRC="$TEST_HOME/.zshrc"
  export ZPROFILE="$TEST_HOME/.zprofile"
  export ZSH_INTEGRATION="$TEST_HOME/.config/mac-setup/zsh.zsh"
  mkdir -p "$(dirname "$ZSH_INTEGRATION")"
  touch "$ZSHRC"
  touch "$ZPROFILE"
  export MOCK_BIN="$(mktemp -d)"
  export MOCK_LOG="$TEST_HOME/mock.log"
  touch "$MOCK_LOG"
  export PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
}

cleanup_test_env() {
  case "${TEST_HOME:-}" in
    /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) rm -rf "$TEST_HOME" ;;
  esac
  case "${MOCK_BIN:-}" in
    /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) rm -rf "$MOCK_BIN" ;;
  esac
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

mock_command_script() {
  local cmd="$1"
  shift
  {
    echo "#!/usr/bin/env bash"
    cat
  } > "$MOCK_BIN/$cmd"
  chmod +x "$MOCK_BIN/$cmd"
}

mock_macos_base_commands() {
  mock_command uname 0 "Darwin"
  mock_command sw_vers 0 "14.6.1"
  mock_command xcode-select 0 "/Library/Developer/CommandLineTools"
  mock_command pkgutil 1 ""
}

mock_package_manager_commands() {
  mock_command_script brew <<'EOF'
echo "brew $*" >> "$MOCK_LOG"
case "$1" in
  --prefix) echo "/opt/homebrew" ;;
  list) exit 1 ;;
  *) exit 0 ;;
esac
EOF
  mock_command_script port <<'EOF'
echo "port $*" >> "$MOCK_LOG"
case "$1" in
  installed) exit 1 ;;
  *) exit 0 ;;
esac
EOF
  mock_command sudo 0 ""
}

mock_python_commands() {
  mock_command_script uv <<'EOF'
echo "uv $*" >> "$MOCK_LOG"
case "$1 $2 $3" in
  "python list --only-installed") exit 0 ;;
  "tool list ") exit 0 ;;
  *) exit 0 ;;
esac
EOF
  mock_command_script pyenv <<'EOF'
echo "pyenv $*" >> "$MOCK_LOG"
case "$1" in
  versions) exit 0 ;;
  *) exit 0 ;;
esac
EOF
  mock_command_script pipx <<'EOF'
echo "pipx $*" >> "$MOCK_LOG"
case "$1" in
  list) exit 0 ;;
  *) exit 0 ;;
esac
EOF
}

mock_runtime_commands() {
  mock_command_script rbenv <<'EOF'
echo "rbenv $*" >> "$MOCK_LOG"
case "$1" in
  versions) exit 0 ;;
  init) echo "true" ;;
  *) exit 0 ;;
esac
EOF
  mock_command ruby-build 0 ""
  mock_command gem 0 ""
  mock_command rustup 0 ""
  mock_command cargo 0 ""
  mock_command_script colima <<'EOF'
echo "colima $*" >> "$MOCK_LOG"
case "$1" in
  status) exit 1 ;;
  *) exit 0 ;;
esac
EOF
  mock_command docker 0 ""
  mock_command docker-compose 0 ""
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
