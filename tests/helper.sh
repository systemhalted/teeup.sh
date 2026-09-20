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
  # /bin is not decoration: macOS keeps cp, mv, ln, mkdir and friends there,
  # not in /usr/bin as a merged-/usr Linux does. A test that narrows PATH
  # further must keep /bin too, or it passes on Linux and fails on the macOS
  # runners with "cp: command not found".
  export PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
  export DRY_RUN="${DRY_RUN:-false}"
  # Keeps tests away from the real /opt/homebrew on macOS CI runners.
  export TEEUP_PKG_PREFIX="$TEST_HOME/pkgprefix"
  unset TEEUP_CONFIG_DIR TEEUP_STATE_DIR TEEUP_ANSWERS_FILE TEEUP_LOG_FILE TEEUP_MACHINES_DIR
  # The macOS CI runners export HOMEBREW_PREFIX, which pkg_prefix obeys: left
  # in place it sends a test that never mentions Homebrew at the runner's own
  # /opt/homebrew, past the TEEUP_PKG_PREFIX sandbox above. A test that wants
  # one sets it itself.
  unset HOMEBREW_PREFIX
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

# hide_host_commands <name...>
# Pretend the host does not have these commands *as it has them now*: every
# copy reachable through a PATH directory is added to TEEUP_TEST_MISSING by
# its absolute path (all of them, not just the first: on a merged-/usr Linux
# /bin/docker and /usr/bin/docker are the same file under two PATH entries),
# so a copy the test installs later (into MOCK_BIN or a bin directory of its
# own) is still found. Hiding by name (TEEUP_TEST_MISSING="gum jq") is the
# right tool when the test never installs the command. Call after
# setup_test_env, which narrows PATH, and before mocking any of the names.
hide_host_commands() {
  local name rest dir
  for name in "$@"; do
    rest="$PATH:"
    while [[ -n "$rest" ]]; do
      dir="${rest%%:*}"
      rest="${rest#*:}"
      [[ -n "$dir" && -f "$dir/$name" && -x "$dir/$name" ]] || continue
      TEEUP_TEST_MISSING="${TEEUP_TEST_MISSING:+$TEEUP_TEST_MISSING }${dir%/}/$name"
    done
  done
  export TEEUP_TEST_MISSING
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
  RUN_TEST_FUNCS="${RUN_TEST_FUNCS:-} $test_func"
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

# A test function that is defined but never passed to run_test is a test that
# does not exist: it goes green by never running, which is worse than a
# failing one because nothing says so. Comparing the test_* functions the file
# defines against the ones run_test was given catches the case where a new
# test is written and its run_test line is forgotten or misspelled.
_unregistered_tests() {
  local func
  for func in $(declare -F | awk '{print $3}' | grep '^test_' || true); do
    case " ${RUN_TEST_FUNCS:-} " in
      *" $func "*) ;;
      *) echo "$func" ;;
    esac
  done
}

print_summary() {
  local orphan orphans=""
  for orphan in $(_unregistered_tests); do
    orphans="${orphans:+$orphans }$orphan"
  done
  if [[ -n "$orphans" ]]; then
    echo ""
    echo -e "${RED}Defined but never run (add a run_test line): $orphans${RESET}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("unregistered: $orphans")
  fi
  echo ""
  echo "Summary: $TESTS_PASSED/$TESTS_RUN passed"
  if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}Failed: ${FAILED_TESTS[*]}${RESET}"
  fi
  [[ $TESTS_FAILED -eq 0 ]]
}
