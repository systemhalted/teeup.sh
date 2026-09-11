# teeup Redesign, Phase 0 and 1: Legacy Freeze and Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Freeze the current scripts under `legacy/` and build the new teeup runtime (bootstrap, `bin/teeup`, `lib/`, capability contract, test harness, CI) with the four core capabilities needed for `./bootstrap --dry-run` to run end to end on a mocked macOS.

**Architecture:** A bash 3.2 `bootstrap` script and a `bin/teeup` dispatcher share sourced libraries under `lib/`. Each capability is a directory under `capabilities/` with a sourced `capability` metadata file and separate `install` and `configure` scripts that the dispatcher runs as `bash -eu` with the libraries preloaded. State is file existence under `~/.local/state/teeup`; answers are a sourceable `KEY="value"` file under `~/.config/teeup`.

**Tech Stack:** bash 3.2 (macOS stock), shellcheck, Homebrew or MacPorts, gum (optional, with plain `read` fallback), the existing mock-binary test harness.

**Spec:** `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md`. This plan covers the migration table rows "Phase 0" and "Phase 1" plus the first four entries of the core list (`xcode-clt package-manager teeup-runtime dev-dirs`). Phases 2 to 5 get their own plans.

## Global Constraints

- Bash 3.2 compatible everywhere: no `mapfile`, no `declare -A`, no `${var,,}`, no `${var^^}`, no `readarray`, no `readlink -f`. Empty arrays expand as `${arr[@]+"${arr[@]}"}`.
- `shellcheck --severity=warning` clean on `bootstrap`, `bin/teeup`, `lib/*.sh`, every `capabilities/*/install|configure|doctor|remove`, and `tests/**/*.sh`.
- Every mutation of the machine goes through `run_cmd` (or `run_privileged`), so `DRY_RUN=true` performs no changes and prints `[DRY-RUN] Would execute: ...`.
- Capability scripts never call `sudo` directly; they use `run_privileged`.
- No secrets, emails or hostnames in the repo except in `machines/<hostname>.conf`, which the user commits deliberately.
- Commit subjects are plain imperative sentences. No `Co-Authored-By` or "Generated with" trailers (user's global CLAUDE.md).
- `./tests/run.sh` and `./legacy/tests/run_tests.sh` must both be green before every commit.
- macOS is the only target. `bootstrap` refuses to run when `uname -s` is not `Darwin`; tests mock `uname`.

---

## File structure

| Path | Responsibility |
|---|---|
| `legacy/` | Frozen copy of `teeup.sh`, `teeup-wizard.sh`, `lib/`, `templates/`, `tests/`. Only touched by Task 1. Deleted in Phase 5. |
| `bootstrap` | Fresh-Mac entry point. Preflight, Xcode CLT, package manager, self-install, wizard, tiers, summary. |
| `bin/teeup` | Dispatcher. Resolves `TEEUP_PATH`, loads `lib/all.sh`, maps `<verb> <cap>` to capability scripts or built-in verbs. |
| `lib/all.sh` | Sources every library in dependency order. The only file capability scripts and tests source. |
| `lib/core.sh` | Paths (`TEEUP_PATH`, `TEEUP_CONFIG_DIR`, `TEEUP_STATE_DIR`), logging, `have`, `die`, `run_cmd`, `run_logged`, `macos_major`, `arch`. |
| `lib/files.sh` | `file_sha`, `append_once`, `write_managed_file`, `backup_target`, `copy_config_once`, `refresh_config`. |
| `lib/state.sh` | `state_done`, `state_toggle`, `state_toggle_enabled`, `state_migration_done`, `state_migration_mark`. |
| `lib/answers.sh` | `answers_load`, `answers_get`, `answers_set`, `answers_file`, `machine_file`. |
| `lib/pkg.sh` | Package backends (homebrew, macports), `run_privileged`, `pkg_backend`, `pkg_install`, `pkg_installed`, `cask_install`, `pkg_backend_prepare`, `pkg_backend_path`. |
| `lib/ui.sh` | `ui_input`, `ui_confirm`, `ui_choose` over gum with `read` fallbacks. |
| `lib/capability.sh` | `cap_dir`, `cap_exists`, `cap_list`, `cap_meta_get`, `cap_tier_list`, `cap_order`, `cap_run`, `cap_check`. |
| `capabilities/core.list`, `capabilities/daily.list` | Ordered tier manifests. |
| `capabilities/xcode-clt/` | Command Line Tools and Rosetta. |
| `capabilities/package-manager/` | Homebrew or MacPorts bootstrap and refresh. |
| `capabilities/teeup-runtime/` | State dirs, env file, `~/.local/bin/teeup` link, gum and jq. |
| `capabilities/dev-dirs/` | `~/Work` and `~/Personal`. |
| `tests/helper.sh` | Mock harness ported from `legacy/tests/test_helper.sh`, plus `setup_teeup_env`. |
| `tests/run.sh` | Runs `tests/lib/*.sh`, `tests/capabilities/*.sh`, `tests/cli.sh`, `tests/bootstrap.sh`. |
| `.github/workflows/ci.yml` | Shellcheck plus both test suites on macos-14, macos-15-intel, ubuntu-latest. |

---

### Task 1: Freeze the current scripts under `legacy/`

**Files:**
- Move: `teeup.sh`, `teeup-wizard.sh`, `lib/`, `templates/`, `tests/` into `legacy/`
- Modify: `.github/workflows/ci.yml`, `README.md`, `CONTRIBUTING.md`

**Interfaces:**
- Produces: `legacy/tests/run_tests.sh` still green from the repo root; CI still runs it.

- [ ] **Step 1: Move the files with git so history follows**

```bash
mkdir -p legacy
git mv teeup.sh teeup-wizard.sh lib templates tests legacy/
git status --short | head
```

Expected: every line starts with `R` (rename).

- [ ] **Step 2: Run the legacy suite from its new home**

Run: `./legacy/tests/run_tests.sh`
Expected: `All tests passed!` The tests compute `PROJECT_DIR` as the parent of their own directory, so they resolve to `legacy/teeup.sh` without edits.

- [ ] **Step 3: Point CI at the legacy paths**

Replace the two shellcheck steps and the test step in `.github/workflows/ci.yml`:

```yaml
      - name: Shellcheck legacy scripts
        run: shellcheck --severity=warning legacy/teeup.sh legacy/teeup-wizard.sh

      - name: Shellcheck legacy tests
        run: shellcheck --severity=warning -x legacy/tests/*.sh

      - name: Run legacy tests
        env:
          CI: "true"
        run: ./legacy/tests/run_tests.sh
```

- [ ] **Step 4: Add the README banner**

Insert directly under the `Get your new machine ready for the first drive.` paragraph in `README.md`:

```markdown
> **Redesign in progress.** teeup is being rebuilt as a modular, macOS-only
> environment distribution. The design is in
> `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md`.
> The previous installer still works and lives under `legacy/`:
> `./legacy/teeup.sh --help`.
```

Also replace every `./teeup.sh` and `./teeup-wizard.sh` invocation in `README.md` and `CONTRIBUTING.md` with `./legacy/teeup.sh` and `./legacy/teeup-wizard.sh`:

```bash
sed -i.bak -e 's#\./teeup\.sh#./legacy/teeup.sh#g' -e 's#\./teeup-wizard\.sh#./legacy/teeup-wizard.sh#g' README.md CONTRIBUTING.md && rm README.md.bak CONTRIBUTING.md.bak
```

- [ ] **Step 5: Verify shellcheck and tests**

Run: `shellcheck --severity=warning legacy/teeup.sh legacy/teeup-wizard.sh && shellcheck --severity=warning -x legacy/tests/*.sh && ./legacy/tests/run_tests.sh`
Expected: no shellcheck output, `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Freeze the current installer and wizard under legacy/"
```

---

### Task 2: New test harness and runner

**Files:**
- Create: `tests/helper.sh`, `tests/run.sh`, `tests/lib/.gitkeep`, `tests/capabilities/.gitkeep`

**Interfaces:**
- Produces: `setup_test_env`, `cleanup_test_env`, `mock_command`, `mock_command_script`, `mock_macos_base`, `assert_equals`, `assert_contains`, `assert_not_contains`, `assert_file_exists`, `assert_dir_exists`, `assert_success`, `assert_failure`, `run_test`, `print_summary`, and `TEEUP_PATH` exported to the repo root. Every later test file starts with `source "$(dirname "$0")/../helper.sh"` (or `/helper.sh` for top-level tests).

- [ ] **Step 1: Write `tests/helper.sh`**

```bash
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
```

Note: the nested heredoc terminators inside `mock_command` and `mock_macos_base` are `EOF2` so they do not collide with any outer heredoc when this file is created via a heredoc.

- [ ] **Step 2: Write `tests/run.sh`**

```bash
#!/usr/bin/env bash
# run.sh - run every test file under tests/ and aggregate results.
set -euo pipefail

if [[ "${LC_ALL:-}" == "C.UTF-8" || "${LANG:-}" == "C.UTF-8" ]]; then
  export LANG="en_US.UTF-8"
  export LC_ALL="en_US.UTF-8"
fi

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0
ran=0

for suite in "$TESTS_DIR"/lib/*.sh "$TESTS_DIR"/capabilities/*.sh "$TESTS_DIR"/cli.sh "$TESTS_DIR"/bootstrap.sh; do
  [[ -f "$suite" ]] || continue
  ran=$((ran + 1))
  echo ""
  echo "== ${suite#"$TESTS_DIR"/} =="
  if ! bash "$suite"; then
    failed=$((failed + 1))
  fi
done

echo ""
if [[ $ran -eq 0 ]]; then
  echo "No test suites found."
  exit 0
fi
if [[ $failed -eq 0 ]]; then
  echo "All $ran suites passed."
  exit 0
fi
echo "$failed of $ran suites failed."
exit 1
```

- [ ] **Step 3: Create the empty suite directories and make the runner executable**

```bash
mkdir -p tests/lib tests/capabilities
touch tests/lib/.gitkeep tests/capabilities/.gitkeep
chmod +x tests/run.sh
./tests/run.sh
```

Expected: `No test suites found.` and exit 0.

- [ ] **Step 4: Shellcheck the harness**

Run: `shellcheck --severity=warning tests/helper.sh tests/run.sh`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add tests/helper.sh tests/run.sh tests/lib/.gitkeep tests/capabilities/.gitkeep
git commit -m "Add the test harness and runner for the new runtime"
```

---

### Task 3: `lib/core.sh` and `lib/all.sh`

**Files:**
- Create: `lib/core.sh`, `lib/all.sh`
- Test: `tests/lib/core.sh`

**Interfaces:**
- Produces: variables `TEEUP_PATH`, `TEEUP_CONFIG_DIR`, `TEEUP_STATE_DIR`, `DRY_RUN`, `TEEUP_LOG_FILE`; functions `log`, `ok`, `warn`, `err`, `die`, `have`, `run_cmd`, `run_logged <name> <interactive:true|false> <cmd...>`, `macos_major`, `arch`, `is_macos`, `format_duration`.
- `lib/all.sh` sources `core.sh files.sh state.sh answers.sh pkg.sh ui.sh capability.sh` in that order; later tasks add their file to it as they create it.

- [ ] **Step 1: Write the failing test `tests/lib/core.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

test_paths_default_to_xdg() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  assert_equals "$TEST_HOME/.config/teeup" "$TEEUP_CONFIG_DIR" "config dir" || return 1
  assert_equals "$TEST_HOME/.local/state/teeup" "$TEEUP_STATE_DIR" "state dir" || return 1
  cleanup_test_env
}

test_run_cmd_dry_run_prints_and_skips() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  DRY_RUN=true
  local out
  out="$(run_cmd touch "$TEST_HOME/should-not-exist")"
  assert_contains "$out" "[DRY-RUN] Would execute: touch $TEST_HOME/should-not-exist" || return 1
  [[ ! -e "$TEST_HOME/should-not-exist" ]] || { echo "file was created in dry run"; return 1; }
  cleanup_test_env
}

test_run_cmd_executes_when_not_dry() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  DRY_RUN=false
  run_cmd touch "$TEST_HOME/exists"
  assert_file_exists "$TEST_HOME/exists" || return 1
  cleanup_test_env
}

test_run_logged_records_start_and_completion() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  TEEUP_LOG_FILE="$TEST_HOME/log"
  run_logged "say-hi" false echo hi
  local log
  log="$(cat "$TEEUP_LOG_FILE")"
  assert_contains "$log" "Starting: say-hi" || return 1
  assert_contains "$log" "Completed: say-hi" || return 1
  cleanup_test_env
}

test_run_logged_reports_failure_without_aborting() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  TEEUP_LOG_FILE="$TEST_HOME/log"
  local rc=0
  run_logged "boom" false false || rc=$?
  assert_failure "$rc" "run_logged returns the command's failure" || return 1
  assert_contains "$(cat "$TEEUP_LOG_FILE")" "Failed: boom (exit code: 1)" || return 1
  cleanup_test_env
}

test_run_logged_closes_stdin_unless_interactive() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  TEEUP_LOG_FILE="$TEST_HOME/log"
  local got
  got="$(echo typed | run_logged "read-test" false bash -c 'IFS= read -r x; echo "got:$x"')"
  assert_contains "$got" "got:" || return 1
  assert_not_contains "$got" "got:typed" "stdin must be /dev/null when not interactive" || return 1
  got="$(echo typed | run_logged "read-test" true bash -c 'IFS= read -r x; echo "got:$x"')"
  assert_contains "$got" "got:typed" "stdin kept when interactive" || return 1
  cleanup_test_env
}

test_macos_major_and_arch_use_mocks() {
  setup_test_env
  mock_macos_base
  source "$TEEUP_PATH/lib/core.sh"
  assert_equals "14" "$(macos_major)" || return 1
  assert_equals "arm64" "$(arch)" || return 1
  is_macos || { echo "is_macos should be true under Darwin mock"; return 1; }
  cleanup_test_env
}

test_format_duration() {
  source "$TEEUP_PATH/lib/core.sh"
  assert_equals "1h 1m 1s" "$(format_duration 3661)" || return 1
  assert_equals "2m 5s" "$(format_duration 125)" || return 1
  assert_equals "9s" "$(format_duration 9)" || return 1
}

echo "lib/core.sh"
run_test "paths default to XDG under HOME" test_paths_default_to_xdg
run_test "run_cmd dry run prints and skips" test_run_cmd_dry_run_prints_and_skips
run_test "run_cmd executes when not dry" test_run_cmd_executes_when_not_dry
run_test "run_logged records start and completion" test_run_logged_records_start_and_completion
run_test "run_logged reports failure" test_run_logged_reports_failure_without_aborting
run_test "run_logged closes stdin unless interactive" test_run_logged_closes_stdin_unless_interactive
run_test "macos_major and arch" test_macos_major_and_arch_use_mocks
run_test "format_duration" test_format_duration
print_summary
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/lib/core.sh`
Expected: FAIL with `lib/core.sh: No such file or directory`.

- [ ] **Step 3: Write `lib/core.sh`**

```bash
#!/usr/bin/env bash
# core.sh - paths, logging, the dry-run seam and the logged runner.
# Sourced by lib/all.sh. Safe to source more than once.

: "${TEEUP_PATH:?TEEUP_PATH must point at the teeup checkout}"
TEEUP_CONFIG_DIR="${TEEUP_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/teeup}"
TEEUP_STATE_DIR="${TEEUP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/teeup}"
DRY_RUN="${DRY_RUN:-false}"
# Empty means log lines go to stdout only.
TEEUP_LOG_FILE="${TEEUP_LOG_FILE:-}"
export TEEUP_PATH TEEUP_CONFIG_DIR TEEUP_STATE_DIR DRY_RUN TEEUP_LOG_FILE

log()  { printf "%b %s\n" "🔹" "$*"; }
ok()   { printf "%b %s\n" "✅" "$*"; }
warn() { printf "%b %s\n" "⚠️" "$*" >&2; }
err()  { printf "%b %s\n" "❌" "$*" >&2; }
die()  { err "$@"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Every mutation goes through here so DRY_RUN=true is a faithful preview.
run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would execute: $*"
    return 0
  fi
  "$@"
}

_teeup_log_line() {
  local line
  line="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  if [[ -n "$TEEUP_LOG_FILE" ]]; then
    mkdir -p "$(dirname "$TEEUP_LOG_FILE")"
    printf '%s\n' "$line" >> "$TEEUP_LOG_FILE"
  fi
  printf '%s\n' "$line"
}

# run_logged <name> <interactive:true|false> <command...>
# Brackets a unit with Starting/Completed/Failed lines. stdin is redirected
# from /dev/null unless interactive=true, so a unit can never block on a
# prompt nobody will answer. Returns the command's exit code.
run_logged() {
  local name="$1" interactive="$2"
  shift 2
  local rc=0
  _teeup_log_line "Starting: $name"
  if [[ "$interactive" == "true" ]]; then
    "$@" || rc=$?
  else
    "$@" </dev/null || rc=$?
  fi
  if [[ $rc -eq 0 ]]; then
    _teeup_log_line "Completed: $name"
  else
    _teeup_log_line "Failed: $name (exit code: $rc)"
  fi
  return $rc
}

is_macos()    { [[ "$(uname -s)" == "Darwin" ]]; }
arch()        { uname -m; }
macos_major() { sw_vers -productVersion 2>/dev/null | awk -F. '{print $1}'; }

format_duration() {
  local total="$1" hours minutes seconds
  hours=$((total / 3600))
  minutes=$(((total % 3600) / 60))
  seconds=$((total % 60))
  if [[ "$hours" -gt 0 ]]; then
    printf "%dh %dm %ds" "$hours" "$minutes" "$seconds"
  elif [[ "$minutes" -gt 0 ]]; then
    printf "%dm %ds" "$minutes" "$seconds"
  else
    printf "%ds" "$seconds"
  fi
}
```

- [ ] **Step 4: Write `lib/all.sh`**

```bash
#!/usr/bin/env bash
# all.sh - source every teeup library in dependency order.
# Usage: TEEUP_PATH=/path/to/teeup; source "$TEEUP_PATH/lib/all.sh"
_teeup_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEEUP_PATH="${TEEUP_PATH:-$(dirname "$_teeup_lib_dir")}"
export TEEUP_PATH
# shellcheck source=lib/core.sh
source "$_teeup_lib_dir/core.sh"
for _teeup_lib in files state answers pkg ui capability; do
  if [[ -f "$_teeup_lib_dir/$_teeup_lib.sh" ]]; then
    # shellcheck source=/dev/null
    source "$_teeup_lib_dir/$_teeup_lib.sh"
  fi
done
unset _teeup_lib _teeup_lib_dir
```

The `[[ -f ]]` guard lets `all.sh` exist before every library does; the guard is removed in Task 9 once all seven files exist.

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/lib/core.sh`
Expected: `Summary: 8/8 passed`

- [ ] **Step 6: Shellcheck and commit**

```bash
shellcheck --severity=warning lib/core.sh lib/all.sh tests/lib/core.sh
git add lib/core.sh lib/all.sh tests/lib/core.sh
git commit -m "Add the core library with logging, run_cmd and run_logged"
```

---

### Task 4: `lib/files.sh`

**Files:**
- Create: `lib/files.sh`
- Modify: nothing (all.sh already guards)
- Test: `tests/lib/files.sh`

**Interfaces:**
- Produces: `file_sha <file>`, `append_once <file> <marker>` (block on stdin), `write_managed_file <file> <label>` (content on stdin), `backup_target <path>` (prints backup path), `copy_config_once <src> <dest>`, `refresh_config <src> <dest>`, `stock_record <dest> <sha>`, `stock_sha <dest>`.
- `copy_config_once` semantics (spec section 10): dest missing -> copy and record sha; dest exists and equals recorded stock -> skip; dest exists with no record (foreign) -> backup, copy, record, print diff; dest exists with record but differs -> user edited, skip.

- [ ] **Step 1: Write the failing test `tests/lib/files.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false
  SRC="$TEST_HOME/src.conf"
  DEST="$TEST_HOME/.config/tool/tool.conf"
  printf 'shipped=1\n' > "$SRC"
}

test_append_once_is_idempotent() {
  setup
  echo 'export FOO=1' | append_once "$TEST_HOME/.rc" "teeup:foo"
  echo 'export FOO=1' | append_once "$TEST_HOME/.rc" "teeup:foo"
  assert_equals "1" "$(grep -c 'export FOO=1' "$TEST_HOME/.rc")" || return 1
  assert_contains "$(cat "$TEST_HOME/.rc")" "# teeup:foo" || return 1
  cleanup_test_env
}

test_write_managed_file_noops_when_identical() {
  setup
  echo content | write_managed_file "$TEST_HOME/managed" "test"
  local out
  out="$(echo content | write_managed_file "$TEST_HOME/managed" "test")"
  assert_contains "$out" "Already current" || return 1
  cleanup_test_env
}

test_backup_target_moves_and_prints_path() {
  setup
  echo old > "$TEST_HOME/file"
  local backup
  backup="$(backup_target "$TEST_HOME/file")"
  [[ "$backup" == "$TEST_HOME/file.teeup_backup_"* ]] || { echo "bad backup name: $backup"; return 1; }
  assert_file_exists "$backup" || return 1
  [[ ! -e "$TEST_HOME/file" ]] || { echo "original still present"; return 1; }
  cleanup_test_env
}

test_copy_config_once_copies_and_records_sha() {
  setup
  copy_config_once "$SRC" "$DEST"
  assert_file_exists "$DEST" || return 1
  assert_equals "$(file_sha "$SRC")" "$(stock_sha "$DEST")" "recorded sha" || return 1
  cleanup_test_env
}

test_copy_config_once_skips_user_edited_file() {
  setup
  copy_config_once "$SRC" "$DEST"
  printf 'shipped=1\nmine=2\n' > "$DEST"
  printf 'shipped=2\n' > "$SRC"
  copy_config_once "$SRC" "$DEST"
  assert_contains "$(cat "$DEST")" "mine=2" "user edits survive" || return 1
  cleanup_test_env
}

test_copy_config_once_backs_up_foreign_file() {
  setup
  mkdir -p "$(dirname "$DEST")"
  printf 'foreign=1\n' > "$DEST"
  local out
  out="$(copy_config_once "$SRC" "$DEST")"
  assert_contains "$(cat "$DEST")" "shipped=1" || return 1
  ls "$(dirname "$DEST")"/tool.conf.teeup_backup_* >/dev/null || { echo "no backup"; return 1; }
  assert_contains "$out" "foreign=1" "diff of the backup is printed" || return 1
  cleanup_test_env
}

test_copy_config_once_dry_run_touches_nothing() {
  setup
  DRY_RUN=true
  local out
  out="$(copy_config_once "$SRC" "$DEST")"
  [[ ! -e "$DEST" ]] || { echo "dest created in dry run"; return 1; }
  assert_contains "$out" "[DRY-RUN]" || return 1
  cleanup_test_env
}

test_refresh_config_backs_up_and_diffs() {
  setup
  copy_config_once "$SRC" "$DEST"
  printf 'shipped=1\nmine=2\n' > "$DEST"
  local out
  out="$(refresh_config "$SRC" "$DEST")"
  assert_equals "shipped=1" "$(cat "$DEST")" || return 1
  assert_contains "$out" "mine=2" "diff shows what was replaced" || return 1
  cleanup_test_env
}

test_refresh_config_removes_backup_when_unchanged() {
  setup
  copy_config_once "$SRC" "$DEST"
  refresh_config "$SRC" "$DEST" >/dev/null
  if ls "$(dirname "$DEST")"/tool.conf.teeup_backup_* >/dev/null 2>&1; then
    echo "backup left behind although nothing changed"; return 1
  fi
  cleanup_test_env
}

echo "lib/files.sh"
run_test "append_once is idempotent" test_append_once_is_idempotent
run_test "write_managed_file noops when identical" test_write_managed_file_noops_when_identical
run_test "backup_target moves and prints path" test_backup_target_moves_and_prints_path
run_test "copy_config_once copies and records sha" test_copy_config_once_copies_and_records_sha
run_test "copy_config_once skips user-edited file" test_copy_config_once_skips_user_edited_file
run_test "copy_config_once backs up foreign file" test_copy_config_once_backs_up_foreign_file
run_test "copy_config_once dry run touches nothing" test_copy_config_once_dry_run_touches_nothing
run_test "refresh_config backs up and diffs" test_refresh_config_backs_up_and_diffs
run_test "refresh_config removes backup when unchanged" test_refresh_config_removes_backup_when_unchanged
print_summary
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/lib/files.sh`
Expected: FAIL, `append_once: command not found`.

- [ ] **Step 3: Write `lib/files.sh`**

```bash
#!/usr/bin/env bash
# files.sh - idempotent file primitives and the copy-once config model.
# Requires core.sh.

file_sha() {
  if have shasum; then
    shasum -a 256 "$1" | cut -d ' ' -f 1
  else
    sha256sum "$1" | cut -d ' ' -f 1
  fi
}

# The stock record remembers the sha of the shipped file at the moment it was
# copied into place. It is how copy_config_once tells "still pristine" from
# "the user edited this" without ever diffing against the current shipped file.
_stock_record_path() {
  local dest="$1"
  printf '%s/stock/%s\n' "$TEEUP_STATE_DIR" "$(printf '%s' "$dest" | sed -e "s#^$HOME/##" -e 's#/#__#g')"
}

stock_record() {
  local dest="$1" sha="$2" record
  record="$(_stock_record_path "$dest")"
  mkdir -p "$(dirname "$record")"
  printf '%s\n' "$sha" > "$record"
}

stock_sha() {
  local record
  record="$(_stock_record_path "$1")"
  [[ -f "$record" ]] && cat "$record"
}

# append_once <file> <marker>   (block on stdin)
append_once() {
  local file="$1" marker="$2" tmp
  if grep -qF "# $marker" "$file" 2>/dev/null; then
    log "Already present in $(basename "$file"): $marker"
    cat >/dev/null
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would append to $file: $marker"
    cat >/dev/null
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  touch "$file"
  tmp="$(mktemp)"
  { echo ""; echo "# $marker"; cat; } > "$tmp"
  cat "$tmp" >> "$file"
  rm -f "$tmp"
  ok "Updated $(basename "$file") with: $marker"
}

# write_managed_file <file> <label>   (content on stdin)
write_managed_file() {
  local file="$1" label="$2" tmp
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would write $file ($label)"
    cat >/dev/null
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"
  cat > "$tmp"
  if [[ -f "$file" ]] && cmp -s "$tmp" "$file"; then
    rm -f "$tmp"
    log "Already current: $file"
    return 0
  fi
  mv "$tmp" "$file"
  ok "Wrote $file ($label)"
}

# backup_target <path>  -> prints the backup path on stdout
backup_target() {
  local target="$1" backup
  backup="${target}.teeup_backup_$(date +%Y%m%d%H%M%S)"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would back up $target to $backup" >&2
  else
    mv "$target" "$backup"
    ok "Backed up $target to $backup" >&2
  fi
  printf '%s\n' "$backup"
}

# copy_config_once <src> <dest>
# Installs a shipped file into the user's home exactly once. Never overwrites
# a file the user has edited. A foreign file (one teeup did not install) is
# backed up first and its diff printed so the user can carry lines over.
copy_config_once() {
  local src="$1" dest="$2" recorded current backup
  if [[ ! -e "$dest" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      printf "%b %s\n" "🔍" "[DRY-RUN] Would install $dest from $src"
      return 0
    fi
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    stock_record "$dest" "$(file_sha "$src")"
    ok "Installed $dest"
    return 0
  fi
  recorded="$(stock_sha "$dest" || true)"
  current="$(file_sha "$dest")"
  if [[ -n "$recorded" ]]; then
    if [[ "$recorded" == "$current" ]]; then
      log "Already installed: $dest"
    else
      log "Keeping your edited $dest (run teeup reset to restore the shipped file)"
    fi
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would back up foreign $dest and install $src"
    return 0
  fi
  backup="$(backup_target "$dest")"
  cp "$src" "$dest"
  stock_record "$dest" "$(file_sha "$src")"
  ok "Installed $dest (your previous file is at $backup)"
  echo "Lines from your previous file that are not in the teeup version:"
  diff "$dest" "$backup" || true
}

# refresh_config <src> <dest>
# Backup, replace with the shipped file, print the diff, drop the backup if
# nothing changed. Omarchy's refresh-config.
refresh_config() {
  local src="$1" dest="$2" backup
  if [[ ! -e "$dest" ]]; then
    copy_config_once "$src" "$dest"
    return $?
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would reset $dest to $src"
    return 0
  fi
  backup="$(backup_target "$dest" 2>/dev/null)"
  cp "$src" "$dest"
  stock_record "$dest" "$(file_sha "$src")"
  if cmp -s "$dest" "$backup"; then
    rm -f "$backup"
    log "Already at the shipped version: $dest"
    return 0
  fi
  ok "Reset $dest (backup at $backup)"
  echo "Changes:"
  diff "$dest" "$backup" || true
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/lib/files.sh`
Expected: `Summary: 9/9 passed`

- [ ] **Step 5: Shellcheck and commit**

```bash
shellcheck --severity=warning lib/files.sh tests/lib/files.sh
git add lib/files.sh tests/lib/files.sh
git commit -m "Add file primitives and the copy-once config model"
```

---

### Task 5: `lib/state.sh`

**Files:**
- Create: `lib/state.sh`
- Test: `tests/lib/state.sh`

**Interfaces:**
- Produces: `state_done check|mark|ensure|clear <name>`, `state_toggle <flag> [on|off|toggle]`, `state_toggle_enabled <flag>`, `state_migration_done <id>`, `state_migration_mark <id>`. All markers live under `$TEEUP_STATE_DIR/{done,toggles,migrations}/`. These are real filesystem writes even in dry run? No: `mark`, `ensure`, `clear`, toggles and migration marks go through `run_cmd`-style gating so a dry run never records state.

- [ ] **Step 1: Write the failing test `tests/lib/state.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false
}

test_done_check_mark_clear() {
  setup
  state_done check bootstrap && { echo "should not be done yet"; return 1; }
  state_done mark bootstrap
  state_done check bootstrap || { echo "should be done"; return 1; }
  assert_file_exists "$TEEUP_STATE_DIR/done/bootstrap" || return 1
  state_done clear bootstrap
  state_done check bootstrap && { echo "should be cleared"; return 1; }
  cleanup_test_env
}

test_done_ensure_succeeds_only_first_time() {
  setup
  state_done ensure invite || { echo "first ensure should succeed"; return 1; }
  state_done ensure invite && { echo "second ensure should fail"; return 1; }
  cleanup_test_env
}

test_toggle_round_trip() {
  setup
  state_toggle_enabled nightlight && { echo "off by default"; return 1; }
  state_toggle nightlight on
  state_toggle_enabled nightlight || { echo "should be on"; return 1; }
  state_toggle nightlight
  state_toggle_enabled nightlight && { echo "toggle should turn it off"; return 1; }
  cleanup_test_env
}

test_migration_markers() {
  setup
  state_migration_done 1700000000 && { echo "not applied yet"; return 1; }
  state_migration_mark 1700000000
  state_migration_done 1700000000 || { echo "should be applied"; return 1; }
  cleanup_test_env
}

test_dry_run_records_nothing() {
  setup
  DRY_RUN=true
  state_done mark bootstrap >/dev/null
  [[ ! -e "$TEEUP_STATE_DIR/done/bootstrap" ]] || { echo "marker written in dry run"; return 1; }
  cleanup_test_env
}

echo "lib/state.sh"
run_test "done check/mark/clear" test_done_check_mark_clear
run_test "done ensure succeeds only once" test_done_ensure_succeeds_only_first_time
run_test "toggle round trip" test_toggle_round_trip
run_test "migration markers" test_migration_markers
run_test "dry run records nothing" test_dry_run_records_nothing
print_summary
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/lib/state.sh`
Expected: FAIL, `state_done: command not found`.

- [ ] **Step 3: Write `lib/state.sh`**

```bash
#!/usr/bin/env bash
# state.sh - state as file existence under ~/.local/state/teeup.
# done/<name>        one-shot completion markers
# toggles/<flag>     boolean feature flags (existence = on)
# migrations/<id>    applied migration markers
# Requires core.sh.

_state_touch() {
  local marker="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would record state: ${marker#"$TEEUP_STATE_DIR"/}"
    return 0
  fi
  mkdir -p "$(dirname "$marker")"
  : > "$marker"
}

_state_remove() {
  local marker="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would clear state: ${marker#"$TEEUP_STATE_DIR"/}"
    return 0
  fi
  rm -f "$marker"
}

# state_done check|mark|ensure|clear <name>
# ensure: succeeds only the first time (noclobber makes it atomic), so it
# doubles as a "show this once" primitive.
state_done() {
  local op="$1" name="$2" marker="$TEEUP_STATE_DIR/done/$name"
  case "$op" in
    check) [[ -f "$marker" ]] ;;
    mark) _state_touch "$marker" ;;
    clear) _state_remove "$marker" ;;
    ensure)
      [[ "$DRY_RUN" == "true" ]] && { _state_touch "$marker"; return 0; }
      mkdir -p "$(dirname "$marker")"
      (set -o noclobber; : > "$marker") 2>/dev/null
      ;;
    *) die "state_done: unknown op '$op'" ;;
  esac
}

# state_toggle <flag> [on|off|toggle]
state_toggle() {
  local flag="$1" op="${2:-toggle}" marker="$TEEUP_STATE_DIR/toggles/$flag"
  case "$op" in
    on) _state_touch "$marker" ;;
    off) _state_remove "$marker" ;;
    toggle) if [[ -f "$marker" ]]; then _state_remove "$marker"; else _state_touch "$marker"; fi ;;
    *) die "state_toggle: unknown op '$op'" ;;
  esac
}

state_toggle_enabled() { [[ -f "$TEEUP_STATE_DIR/toggles/$1" ]]; }

state_migration_done() { [[ -f "$TEEUP_STATE_DIR/migrations/$1" ]]; }
state_migration_mark() { _state_touch "$TEEUP_STATE_DIR/migrations/$1"; }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/lib/state.sh`
Expected: `Summary: 5/5 passed`

- [ ] **Step 5: Shellcheck and commit**

```bash
shellcheck --severity=warning lib/state.sh tests/lib/state.sh
git add lib/state.sh tests/lib/state.sh
git commit -m "Add file-existence state markers for done, toggles and migrations"
```

---

### Task 6: `lib/answers.sh`

**Files:**
- Create: `lib/answers.sh`
- Test: `tests/lib/answers.sh`

**Interfaces:**
- Produces: `answers_file` (prints `$TEEUP_CONFIG_DIR/answers`), `machine_file` (prints `$TEEUP_PATH/machines/$(hostname -s).conf`), `answers_load` (sources answers, then the machine file so machine wins), `answers_get <KEY> [default]`, `answers_set <KEY> <value>` (rewrites the answers file, one `KEY="value"` per line, sorted), `answers_exist`.
- Keys are upper-case, prefixed `TEEUP_`. Phase 1 keys: `TEEUP_NAME`, `TEEUP_EMAIL`, `TEEUP_WORK_EMAIL`, `TEEUP_PACKAGE_MANAGER` (`homebrew|macports`), `TEEUP_THEME`, `TEEUP_DAILY` (`yes|no`), `TEEUP_SKIP` (space-separated capability names).

- [ ] **Step 1: Write the failing test `tests/lib/answers.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_command hostname 0 "testmac"
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false
  # Point the machine file at a temp copy of the repo's machines/ dir.
  TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR"
}

test_set_then_get() {
  setup
  answers_set TEEUP_NAME "Ada Lovelace"
  answers_set TEEUP_EMAIL "ada@example.com"
  answers_load
  assert_equals "Ada Lovelace" "$(answers_get TEEUP_NAME)" || return 1
  assert_equals "ada@example.com" "$(answers_get TEEUP_EMAIL)" || return 1
  cleanup_test_env
}

test_set_replaces_existing_key() {
  setup
  answers_set TEEUP_THEME catppuccin
  answers_set TEEUP_THEME tokyo-night
  assert_equals "1" "$(grep -c '^TEEUP_THEME=' "$(answers_file)")" || return 1
  answers_load
  assert_equals "tokyo-night" "$(answers_get TEEUP_THEME)" || return 1
  cleanup_test_env
}

test_get_default_when_unset() {
  setup
  answers_load
  assert_equals "homebrew" "$(answers_get TEEUP_PACKAGE_MANAGER homebrew)" || return 1
  cleanup_test_env
}

test_machine_file_wins() {
  setup
  answers_set TEEUP_PACKAGE_MANAGER homebrew
  printf 'TEEUP_PACKAGE_MANAGER="macports"\n' > "$TEEUP_MACHINES_DIR/testmac.conf"
  answers_load
  assert_equals "macports" "$(answers_get TEEUP_PACKAGE_MANAGER)" || return 1
  cleanup_test_env
}

test_values_with_spaces_and_quotes_survive() {
  setup
  answers_set TEEUP_NAME 'O'"'"'Brien "The" Dev'
  answers_load
  assert_equals 'O'"'"'Brien "The" Dev' "$(answers_get TEEUP_NAME)" || return 1
  cleanup_test_env
}

test_answers_exist() {
  setup
  answers_exist && { echo "should not exist yet"; return 1; }
  answers_set TEEUP_NAME x
  answers_exist || { echo "should exist"; return 1; }
  cleanup_test_env
}

echo "lib/answers.sh"
run_test "set then get" test_set_then_get
run_test "set replaces existing key" test_set_replaces_existing_key
run_test "get default when unset" test_get_default_when_unset
run_test "machine file wins" test_machine_file_wins
run_test "values with spaces and quotes survive" test_values_with_spaces_and_quotes_survive
run_test "answers_exist" test_answers_exist
print_summary
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/lib/answers.sh`
Expected: FAIL, `answers_set: command not found`.

- [ ] **Step 3: Write `lib/answers.sh`**

```bash
#!/usr/bin/env bash
# answers.sh - the profile: a sourceable KEY="value" file written once by the
# bootstrap wizard, plus a committed per-machine override file.
# Requires core.sh.

TEEUP_MACHINES_DIR="${TEEUP_MACHINES_DIR:-$TEEUP_PATH/machines}"

answers_file() { printf '%s/answers\n' "$TEEUP_CONFIG_DIR"; }

machine_file() {
  local host
  host="$(hostname -s 2>/dev/null || hostname)"
  printf '%s/%s.conf\n' "$TEEUP_MACHINES_DIR" "$host"
}

answers_exist() { [[ -s "$(answers_file)" ]]; }

# Load answers, then the machine file. The machine file is sourced last on
# purpose: it encodes hard constraints (package manager, skipped capabilities).
answers_load() {
  local f
  f="$(answers_file)"
  # shellcheck source=/dev/null
  [[ -f "$f" ]] && source "$f"
  f="$(machine_file)"
  # shellcheck source=/dev/null
  [[ -f "$f" ]] && source "$f"
  return 0
}

# answers_get <KEY> [default]
answers_get() {
  local key="$1" default="${2:-}" value
  value="${!key:-}"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default"
  fi
}

# answers_set <KEY> <value>
# Rewrites the file: drop the old line for KEY, append the new one, keep the
# file sorted so diffs stay readable. Values are written with %q-free double
# quoting; backslashes, dollars and double quotes are escaped by hand because
# the file is sourced by bash.
answers_set() {
  local key="$1" value="$2" f tmp escaped
  f="$(answers_file)"
  case "$key" in
    TEEUP_[A-Z0-9_]*) ;;
    *) die "answers_set: key must look like TEEUP_NAME, got '$key'" ;;
  esac
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would set $key in $f"
    return 0
  fi
  mkdir -p "$(dirname "$f")"
  touch "$f"
  escaped="$(printf '%s' "$value" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\$/g' -e 's/`/\\`/g')"
  tmp="$(mktemp)"
  { grep -v "^${key}=" "$f" || true; printf '%s="%s"\n' "$key" "$escaped"; } | sort > "$tmp"
  mv "$tmp" "$f"
  chmod 600 "$f"
  export "$key=$value"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/lib/answers.sh`
Expected: `Summary: 6/6 passed`

- [ ] **Step 5: Shellcheck and commit**

```bash
shellcheck --severity=warning lib/answers.sh tests/lib/answers.sh
git add lib/answers.sh tests/lib/answers.sh
git commit -m "Add the answers file with per-machine overrides"
```

---

### Task 7: `lib/pkg.sh`

**Files:**
- Create: `lib/pkg.sh`
- Test: `tests/lib/pkg.sh`

**Interfaces:**
- Consumes: `answers_get TEEUP_PACKAGE_MANAGER`, `macos_major`, `arch`, `run_cmd`, `have`.
- Produces: `run_privileged <cmd...>`, `pkg_backend` (prints `homebrew` or `macports`, resolving once and caching in `TEEUP_PKG_BACKEND`), `pkg_backend_label`, `pkg_prefix` (`/opt/homebrew`, `/usr/local`, or `/opt/local`), `pkg_backend_path` (prepends the backend's bin dirs to `PATH` for the current process), `pkg_backend_installed`, `pkg_backend_prepare` (installs Homebrew or runs `port selfupdate`), `package_candidates <pkg>`, `pkg_installed <pkg>`, `pkg_install <pkg> [command]`, `cask_installed <cask>`, `cask_install <cask>`, `casks_supported`.
- Ported from `legacy/lib/package_manager.sh` with the Linux backends removed and the `remember_*` bookkeeping dropped.
- `TEEUP_PKG_PREFIX`, set by the test helper, overrides `pkg_prefix` so tests never see the CI runner's real Homebrew.

- [ ] **Step 1: Write the failing test `tests/lib/pkg.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false
  unset TEEUP_PKG_BACKEND TEEUP_PACKAGE_MANAGER
}

test_backend_defaults_to_homebrew_on_modern_macos() {
  setup
  unset TEEUP_PKG_PREFIX
  assert_equals "homebrew" "$(pkg_backend)" || return 1
  assert_equals "/opt/homebrew" "$(pkg_prefix)" || return 1
  cleanup_test_env
}

test_backend_is_macports_on_macos_12() {
  setup
  unset TEEUP_PKG_PREFIX
  mock_command sw_vers 0 "12.7.1"
  assert_equals "macports" "$(pkg_backend)" || return 1
  assert_equals "/opt/local" "$(pkg_prefix)" || return 1
  cleanup_test_env
}

test_backend_honours_answer() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  assert_equals "macports" "$(pkg_backend)" || return 1
  cleanup_test_env
}

test_intel_homebrew_prefix() {
  setup
  unset TEEUP_PKG_PREFIX
  mock_command_script uname <<'EOF2'
case "$1" in -m) echo x86_64 ;; *) echo Darwin ;; esac
EOF2
  assert_equals "/usr/local" "$(pkg_prefix)" || return 1
  cleanup_test_env
}

test_pkg_install_skips_when_command_on_path() {
  setup
  mock_command jq 0 ""
  mock_command brew 0 ""
  local out
  out="$(pkg_install jq jq)"
  assert_contains "$out" "Already available on PATH: jq" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew install" || return 1
  cleanup_test_env
}

test_pkg_install_calls_brew_when_missing() {
  setup
  mock_command_script brew <<'EOF2'
case "$1" in
  list) exit 1 ;;
  install) exit 0 ;;
esac
EOF2
  DRY_RUN=true
  local out
  out="$(pkg_install ripgrep)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install ripgrep" || return 1
  cleanup_test_env
}

test_pkg_install_uses_sudo_port_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  DRY_RUN=true
  local out
  out="$(pkg_install ripgrep)"
  assert_contains "$out" "[DRY-RUN] Would execute: sudo port install ripgrep" || return 1
  cleanup_test_env
}

test_candidates_map_bash_completion_on_homebrew() {
  setup
  assert_equals "bash-completion@2 bash-completion" "$(package_candidates bash-completion)" || return 1
  cleanup_test_env
}

test_cask_install_skipped_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  local out
  out="$(cask_install wezterm)"
  assert_contains "$out" "Casks are not available with MacPorts" || return 1
  cleanup_test_env
}

test_cask_install_dry_run() {
  setup
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; esac
EOF2
  DRY_RUN=true
  local out
  out="$(cask_install wezterm)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask wezterm" || return 1
  cleanup_test_env
}

test_backend_prepare_installs_homebrew_when_missing() {
  setup
  DRY_RUN=true
  local out
  out="$(pkg_backend_prepare)"
  assert_contains "$out" "Homebrew/install/HEAD/install.sh" || return 1
  cleanup_test_env
}

test_run_privileged_prefixes_sudo() {
  setup
  DRY_RUN=true
  assert_contains "$(run_privileged port selfupdate)" "sudo port selfupdate" || return 1
  cleanup_test_env
}

echo "lib/pkg.sh"
run_test "backend defaults to homebrew on modern macOS" test_backend_defaults_to_homebrew_on_modern_macos
run_test "backend is macports on macOS 12" test_backend_is_macports_on_macos_12
run_test "backend honours answer" test_backend_honours_answer
run_test "intel homebrew prefix" test_intel_homebrew_prefix
run_test "pkg_install skips when command on PATH" test_pkg_install_skips_when_command_on_path
run_test "pkg_install calls brew when missing" test_pkg_install_calls_brew_when_missing
run_test "pkg_install uses sudo port on macports" test_pkg_install_uses_sudo_port_on_macports
run_test "candidates map bash-completion" test_candidates_map_bash_completion_on_homebrew
run_test "cask_install skipped on macports" test_cask_install_skipped_on_macports
run_test "cask_install dry run" test_cask_install_dry_run
run_test "backend prepare installs homebrew" test_backend_prepare_installs_homebrew_when_missing
run_test "run_privileged prefixes sudo" test_run_privileged_prefixes_sudo
print_summary
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/lib/pkg.sh`
Expected: FAIL, `pkg_backend: command not found`.

- [ ] **Step 3: Write `lib/pkg.sh`**

```bash
#!/usr/bin/env bash
# pkg.sh - Homebrew and MacPorts backends behind one candidate-list install
# primitive. Ported from legacy/lib/package_manager.sh, macOS only.
# Requires core.sh and answers.sh.

run_privileged() {
  if [[ "$(id -u)" -eq 0 ]]; then
    run_cmd "$@"
    return $?
  fi
  if have sudo; then
    run_cmd sudo "$@"
    return $?
  fi
  warn "sudo is unavailable; cannot run privileged command: $*"
  return 1
}

# pkg_backend -> homebrew | macports
# Resolution order: TEEUP_PACKAGE_MANAGER (answers or machine file), then
# macOS 12 or older means MacPorts (Homebrew no longer supports them), else
# Homebrew. Cached in TEEUP_PKG_BACKEND for the process.
pkg_backend() {
  if [[ -n "${TEEUP_PKG_BACKEND:-}" ]]; then
    printf '%s\n' "$TEEUP_PKG_BACKEND"
    return 0
  fi
  local answer major
  answer="$(answers_get TEEUP_PACKAGE_MANAGER)"
  case "$answer" in
    homebrew|macports) TEEUP_PKG_BACKEND="$answer" ;;
    "")
      major="$(macos_major)"
      if [[ "$major" =~ ^[0-9]+$ && "$major" -le 12 ]]; then
        TEEUP_PKG_BACKEND=macports
      else
        TEEUP_PKG_BACKEND=homebrew
      fi
      ;;
    *) die "Unknown TEEUP_PACKAGE_MANAGER '$answer' (expected homebrew or macports)" ;;
  esac
  export TEEUP_PKG_BACKEND
  printf '%s\n' "$TEEUP_PKG_BACKEND"
}

pkg_backend_label() {
  case "$(pkg_backend)" in
    homebrew) echo "Homebrew" ;;
    macports) echo "MacPorts" ;;
  esac
}

pkg_prefix() {
  # TEEUP_PKG_PREFIX lets tests point at an empty directory instead of the
  # real /opt/homebrew on the CI runner.
  if [[ -n "${TEEUP_PKG_PREFIX:-}" ]]; then
    printf '%s\n' "$TEEUP_PKG_PREFIX"
    return 0
  fi
  case "$(pkg_backend)" in
    macports) echo "/opt/local" ;;
    homebrew)
      if [[ "$(arch)" == "arm64" ]]; then echo "/opt/homebrew"; else echo "/usr/local"; fi
      ;;
  esac
}

# Put the backend's bin dirs first on PATH for this process. The shell
# capability handles the persistent version later.
pkg_backend_path() {
  local prefix
  prefix="$(pkg_prefix)"
  case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *) PATH="$prefix/bin:$prefix/sbin:$PATH"; export PATH ;;
  esac
}

pkg_backend_installed() {
  case "$(pkg_backend)" in
    homebrew) have brew || [[ -x "$(pkg_prefix)/bin/brew" ]] ;;
    macports) have port || [[ -x "$(pkg_prefix)/bin/port" ]] ;;
  esac
}

# Install Homebrew if missing, or refresh MacPorts. MacPorts itself is never
# auto-installed: its installer is a signed pkg tied to the macOS version.
pkg_backend_prepare() {
  case "$(pkg_backend)" in
    homebrew)
      if pkg_backend_installed; then
        ok "Homebrew already installed."
      else
        log "Installing Homebrew..."
        run_cmd bash -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
      fi
      pkg_backend_path
      run_cmd brew update || warn "brew update returned non-zero."
      ;;
    macports)
      if ! pkg_backend_installed; then
        err "MacPorts is not installed. Download the installer for your macOS version from https://www.macports.org/install.php, run it, then re-run bootstrap."
        return 1
      fi
      pkg_backend_path
      run_privileged port selfupdate || warn "port selfupdate returned non-zero."
      ;;
  esac
}

# package_candidates <pkg> -> space-separated names to try in order
package_candidates() {
  local pkg="$1"
  case "$(pkg_backend):$pkg" in
    homebrew:bash-completion) echo "bash-completion@2 bash-completion" ;;
    macports:gnupg) echo "gnupg2 gnupg" ;;
    macports:gh) echo "gh github-cli" ;;
    *) echo "$pkg" ;;
  esac
}

pkg_installed() {
  local pkg="$1"
  case "$(pkg_backend)" in
    homebrew) have brew && brew list --formula "$pkg" >/dev/null 2>&1 ;;
    macports) have port && port installed "$pkg" 2>/dev/null | grep -q '(active)' ;;
  esac
}

_pkg_install_candidate() {
  case "$(pkg_backend)" in
    homebrew) run_cmd brew install "$1" ;;
    macports) run_privileged port install "$1" ;;
  esac
}

# pkg_install <pkg> [command]
# Skips when <command> is already on PATH or any candidate is installed.
# Tries each candidate in order; warns and returns 1 when none installs.
pkg_install() {
  local pkg="$1" command_name="${2:-}" candidate
  if [[ -n "$command_name" ]] && have "$command_name"; then
    log "Already available on PATH: $command_name (skipping install for $pkg)"
    return 0
  fi
  for candidate in $(package_candidates "$pkg"); do
    if pkg_installed "$candidate"; then
      log "Already installed: $candidate"
      return 0
    fi
    if _pkg_install_candidate "$candidate"; then
      ok "Installed $candidate ($(pkg_backend_label))"
      return 0
    fi
    warn "Failed to install '$candidate' with $(pkg_backend_label); trying the next candidate."
  done
  warn "Unable to install '$pkg' with $(pkg_backend_label)."
  return 1
}

casks_supported() { [[ "$(pkg_backend)" == "homebrew" ]]; }

cask_installed() { have brew && brew list --cask "$1" >/dev/null 2>&1; }

# cask_install <cask>
# On MacPorts machines GUI apps are skipped with a note rather than failing,
# so a capability that is mostly CLI still installs its CLI half.
cask_install() {
  local cask="$1"
  if ! casks_supported; then
    warn "Casks are not available with MacPorts; install $cask by hand."
    return 0
  fi
  if cask_installed "$cask"; then
    log "Already installed: $cask (cask)"
    return 0
  fi
  run_cmd brew install --cask "$cask" && ok "Installed $cask (cask)"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/lib/pkg.sh`
Expected: `Summary: 12/12 passed`

- [ ] **Step 5: Shellcheck and commit**

```bash
shellcheck --severity=warning lib/pkg.sh tests/lib/pkg.sh
git add lib/pkg.sh tests/lib/pkg.sh
git commit -m "Add the Homebrew and MacPorts package backend library"
```

---

### Task 8: `lib/ui.sh`

**Files:**
- Create: `lib/ui.sh`
- Test: `tests/lib/ui.sh`

**Interfaces:**
- Produces: `ui_input <prompt> [default]` (prints the answer), `ui_confirm <prompt> [yes|no default]` (exit code), `ui_choose <prompt> <option...>` (prints the chosen option). Each uses `gum` when it is on PATH and `TEEUP_NO_GUM` is unset, else plain `read -r` from the terminal. Non-interactive (no TTY on stdin and no piped input) returns the default.

- [ ] **Step 1: Write the failing test `tests/lib/ui.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  source "$TEEUP_PATH/lib/all.sh"
  export TEEUP_NO_GUM=1
}

test_input_reads_piped_answer() {
  setup
  assert_equals "Ada" "$(echo Ada | ui_input "Name" "Nobody")" || return 1
  cleanup_test_env
}

test_input_uses_default_on_empty_line() {
  setup
  assert_equals "Nobody" "$(echo | ui_input "Name" "Nobody")" || return 1
  cleanup_test_env
}

test_confirm_yes_and_no() {
  setup
  echo y | ui_confirm "Continue?" || { echo "y should confirm"; return 1; }
  echo n | ui_confirm "Continue?" && { echo "n should refuse"; return 1; }
  echo | ui_confirm "Continue?" yes || { echo "empty uses default yes"; return 1; }
  echo | ui_confirm "Continue?" no && { echo "empty uses default no"; return 1; }
  cleanup_test_env
}

test_choose_by_number_and_by_name() {
  setup
  assert_equals "macports" "$(echo 2 | ui_choose "Package manager" homebrew macports)" || return 1
  assert_equals "homebrew" "$(echo homebrew | ui_choose "Package manager" homebrew macports)" || return 1
  cleanup_test_env
}

test_choose_defaults_to_first_on_empty() {
  setup
  assert_equals "homebrew" "$(echo | ui_choose "Package manager" homebrew macports)" || return 1
  cleanup_test_env
}

test_gum_is_used_when_available() {
  setup
  unset TEEUP_NO_GUM
  mock_command gum 0 "from-gum"
  assert_equals "from-gum" "$(ui_input "Name" </dev/null)" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "gum input" || return 1
  cleanup_test_env
}

echo "lib/ui.sh"
run_test "input reads piped answer" test_input_reads_piped_answer
run_test "input uses default on empty line" test_input_uses_default_on_empty_line
run_test "confirm yes and no" test_confirm_yes_and_no
run_test "choose by number and by name" test_choose_by_number_and_by_name
run_test "choose defaults to first on empty" test_choose_defaults_to_first_on_empty
run_test "gum is used when available" test_gum_is_used_when_available
print_summary
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/lib/ui.sh`
Expected: FAIL, `ui_input: command not found`.

- [ ] **Step 3: Write `lib/ui.sh`**

```bash
#!/usr/bin/env bash
# ui.sh - prompts over gum with plain read fallbacks. Every function reads
# from stdin so tests can pipe answers; gum draws on /dev/tty by itself.
# Requires core.sh.

_ui_gum() { [[ -z "${TEEUP_NO_GUM:-}" ]] && have gum; }

# ui_input <prompt> [default] -> prints the answer
ui_input() {
  local prompt="$1" default="${2:-}" answer
  if _ui_gum; then
    answer="$(gum input --prompt "$prompt: " --value "$default" --placeholder "$default")" || answer=""
  else
    printf '%s' "$prompt" >&2
    [[ -n "$default" ]] && printf ' [%s]' "$default" >&2
    printf ': ' >&2
    IFS= read -r answer || answer=""
  fi
  [[ -z "$answer" ]] && answer="$default"
  printf '%s\n' "$answer"
}

# ui_confirm <prompt> [yes|no]  (default yes)
ui_confirm() {
  local prompt="$1" default="${2:-yes}" answer hint
  if _ui_gum; then
    if [[ "$default" == "yes" ]]; then
      gum confirm "$prompt"
    else
      gum confirm --default=false "$prompt"
    fi
    return $?
  fi
  if [[ "$default" == "yes" ]]; then hint="Y/n"; else hint="y/N"; fi
  printf '%s [%s]: ' "$prompt" "$hint" >&2
  IFS= read -r answer || answer=""
  case "$answer" in
    [Yy]*) return 0 ;;
    [Nn]*) return 1 ;;
    "") [[ "$default" == "yes" ]] ;;
    *) return 1 ;;
  esac
}

# ui_choose <prompt> <option...> -> prints the chosen option
# Plain mode accepts a number or the option's name; empty picks the first.
ui_choose() {
  local prompt="$1"
  shift
  local answer i n=$#
  if _ui_gum; then
    gum choose --header "$prompt" "$@"
    return $?
  fi
  printf '%s\n' "$prompt" >&2
  i=1
  for opt in "$@"; do
    printf '  %d) %s\n' "$i" "$opt" >&2
    i=$((i + 1))
  done
  printf 'Choice [1]: ' >&2
  IFS= read -r answer || answer=""
  if [[ -z "$answer" ]]; then
    printf '%s\n' "$1"
    return 0
  fi
  if [[ "$answer" =~ ^[0-9]+$ ]] && [[ "$answer" -ge 1 && "$answer" -le "$n" ]]; then
    i=1
    for opt in "$@"; do
      if [[ "$i" -eq "$answer" ]]; then printf '%s\n' "$opt"; return 0; fi
      i=$((i + 1))
    done
  fi
  for opt in "$@"; do
    if [[ "$opt" == "$answer" ]]; then printf '%s\n' "$opt"; return 0; fi
  done
  warn "Unknown choice '$answer'; using $1"
  printf '%s\n' "$1"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/lib/ui.sh`
Expected: `Summary: 6/6 passed`

- [ ] **Step 5: Shellcheck and commit**

```bash
shellcheck --severity=warning lib/ui.sh tests/lib/ui.sh
git add lib/ui.sh tests/lib/ui.sh
git commit -m "Add prompt helpers over gum with plain read fallbacks"
```

---

### Task 9: `lib/capability.sh`

**Files:**
- Create: `lib/capability.sh`
- Modify: `lib/all.sh` (drop the `[[ -f ]]` guard), `lib/answers.sh` (export `TEEUP_MACHINES_DIR`)
- Test: `tests/lib/capability.sh`

**Interfaces:**
- Consumes: `run_logged`, `state_done`, `answers_get`, `die`.
- Produces: `TEEUP_CAPS_DIR` (default `$TEEUP_PATH/capabilities`, overridable for tests), `cap_dir <name>`, `cap_exists <name>`, `cap_list` (all names, sorted), `cap_meta_get <name> <key> [default]`, `cap_tier_list <core|daily>`, `cap_order <name...>` (dependency order, requires first, deduped), `cap_skipped <name>` (in `TEEUP_SKIP`), `cap_run <name> <verb>`, `cap_check` (metadata lint; prints problems, exit 1 if any).
- Capability scripts run as `bash -eu` in a child process with `lib/all.sh` sourced and `answers_load` called, and with `TEEUP_CAP`, `TEEUP_CAP_DIR` exported.

- [ ] **Step 1: Write the failing test `tests/lib/capability.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# Builds a fixture capability tree under $TEST_HOME/caps.
make_cap() {
  local name="$1" tier="$2" requires="${3:-}" provides="${4:-}"
  local dir="$TEEUP_CAPS_DIR/$name"
  mkdir -p "$dir"
  cat > "$dir/capability" <<EOF2
summary="Fixture $name"
group=system
tier=$tier
requires="$requires"
provides="$provides"
interactive=false
EOF2
  printf '#!/usr/bin/env bash\necho "install:%s cap=$TEEUP_CAP dir=$TEEUP_CAP_DIR"\n' "$name" > "$dir/install"
  printf '#!/usr/bin/env bash\necho "configure:%s"\nlog "from lib"\n' "$name" > "$dir/configure"
  chmod +x "$dir/install" "$dir/configure"
}

setup() {
  setup_test_env
  mock_command hostname 0 "testmac"
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR"
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false
  make_cap alpha core "" ""
  make_cap beta core "alpha" ""
  make_cap gamma daily "beta alpha" "gam"
  make_cap lazyone lazy "" "lz"
  printf '# core\nalpha\nbeta\n' > "$TEEUP_CAPS_DIR/core.list"
  printf 'gamma\n' > "$TEEUP_CAPS_DIR/daily.list"
}

test_list_and_exists() {
  setup
  assert_equals "alpha beta gamma lazyone" "$(cap_list | tr '\n' ' ' | sed 's/ $//')" || return 1
  cap_exists alpha || { echo "alpha should exist"; return 1; }
  cap_exists nope && { echo "nope should not exist"; return 1; }
  cleanup_test_env
}

test_meta_get_with_default() {
  setup
  assert_equals "daily" "$(cap_meta_get gamma tier)" || return 1
  assert_equals "beta alpha" "$(cap_meta_get gamma requires)" || return 1
  assert_equals "fallback" "$(cap_meta_get gamma missingkey fallback)" || return 1
  cleanup_test_env
}

test_tier_list_skips_comments() {
  setup
  assert_equals "alpha beta" "$(cap_tier_list core | tr '\n' ' ' | sed 's/ $//')" || return 1
  cleanup_test_env
}

test_order_puts_requires_first_and_dedupes() {
  setup
  assert_equals "alpha beta gamma" "$(cap_order gamma | tr '\n' ' ' | sed 's/ $//')" || return 1
  assert_equals "alpha beta gamma" "$(cap_order beta gamma alpha | tr '\n' ' ' | sed 's/ $//')" || return 1
  cleanup_test_env
}

test_run_executes_script_with_lib_and_env() {
  setup
  local out
  out="$(cap_run alpha install)"
  assert_contains "$out" "install:alpha cap=alpha dir=$TEEUP_CAPS_DIR/alpha" || return 1
  out="$(cap_run alpha configure)"
  assert_contains "$out" "🔹 from lib" "lib functions are available inside the script" || return 1
  assert_contains "$out" "Completed: alpha configure" || return 1
  cleanup_test_env
}

test_run_propagates_failure() {
  setup
  printf '#!/usr/bin/env bash\nfalse\necho unreachable\n' > "$TEEUP_CAPS_DIR/alpha/install"
  local rc=0 out
  out="$(cap_run alpha install)" || rc=$?
  assert_failure "$rc" || return 1
  assert_not_contains "$out" "unreachable" "bash -e stops at the first failure" || return 1
  cleanup_test_env
}

test_run_missing_verb_fails_clearly() {
  setup
  local rc=0 out
  out="$(cap_run alpha doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "alpha has no doctor script" || return 1
  cleanup_test_env
}

test_skipped_reads_teeup_skip() {
  setup
  export TEEUP_SKIP="beta lazyone"
  cap_skipped beta || { echo "beta should be skipped"; return 1; }
  cap_skipped alpha && { echo "alpha should not be skipped"; return 1; }
  cleanup_test_env
}

test_check_passes_on_valid_fixture() {
  setup
  cap_check || { echo "valid fixture should pass"; return 1; }
  cleanup_test_env
}

test_check_reports_problems() {
  setup
  chmod -x "$TEEUP_CAPS_DIR/alpha/install"
  sed -i.bak 's/^tier=daily/tier=weekly/' "$TEEUP_CAPS_DIR/gamma/capability" && rm "$TEEUP_CAPS_DIR/gamma/capability.bak"
  sed -i.bak 's/^provides=""/provides="python3"/' "$TEEUP_CAPS_DIR/lazyone/capability" && rm "$TEEUP_CAPS_DIR/lazyone/capability.bak"
  printf 'alpha\nbeta\nlazyone\n' > "$TEEUP_CAPS_DIR/core.list"
  local rc=0 out
  out="$(cap_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "alpha: install is not executable" || return 1
  assert_contains "$out" "gamma: tier must be core, daily or lazy" || return 1
  assert_contains "$out" "lazyone: provides must not list python3" || return 1
  assert_contains "$out" "lazyone: tier is lazy but it is listed in core.list" || return 1
  cleanup_test_env
}

echo "lib/capability.sh"
run_test "list and exists" test_list_and_exists
run_test "meta get with default" test_meta_get_with_default
run_test "tier list skips comments" test_tier_list_skips_comments
run_test "order puts requires first and dedupes" test_order_puts_requires_first_and_dedupes
run_test "run executes script with lib and env" test_run_executes_script_with_lib_and_env
run_test "run propagates failure" test_run_propagates_failure
run_test "run missing verb fails clearly" test_run_missing_verb_fails_clearly
run_test "skipped reads TEEUP_SKIP" test_skipped_reads_teeup_skip
run_test "check passes on valid fixture" test_check_passes_on_valid_fixture
run_test "check reports problems" test_check_reports_problems
print_summary
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/lib/capability.sh`
Expected: FAIL, `cap_list: command not found`.

- [ ] **Step 3: Write `lib/capability.sh`**

```bash
#!/usr/bin/env bash
# capability.sh - the capability contract: metadata, ordering, execution, lint.
# A capability is a directory under capabilities/ holding a sourced
# `capability` metadata file and executable install/configure scripts.
# Requires core.sh, state.sh, answers.sh.

TEEUP_CAPS_DIR="${TEEUP_CAPS_DIR:-$TEEUP_PATH/capabilities}"
export TEEUP_CAPS_DIR

# Commands macOS ships; a PATH-last shim for these can never fire.
TEEUP_SHIM_FORBIDDEN="python3 ruby java git perl"

cap_dir() { printf '%s/%s\n' "$TEEUP_CAPS_DIR" "$1"; }

cap_exists() { [[ -f "$(cap_dir "$1")/capability" ]]; }

cap_list() {
  local d
  for d in "$TEEUP_CAPS_DIR"/*/; do
    [[ -f "$d/capability" ]] || continue
    basename "$d"
  done | sort
}

# cap_meta_get <name> <key> [default]
# The metadata file is sourced in a subshell so its assignments never leak.
cap_meta_get() {
  local name="$1" key="$2" default="${3:-}" file
  file="$(cap_dir "$name")/capability"
  [[ -f "$file" ]] || die "Unknown capability: $name"
  (
    set +eu
    # shellcheck source=/dev/null
    source "$file"
    value="${!key:-}"
    [[ -n "$value" ]] || value="$default"
    printf '%s\n' "$value"
  )
}

# cap_tier_list <core|daily> -> names in manifest order
cap_tier_list() {
  local file="$TEEUP_CAPS_DIR/$1.list"
  [[ -f "$file" ]] || return 0
  grep -v '^[[:space:]]*#' "$file" | grep -v '^[[:space:]]*$'
}

# cap_order <name...> -> names with their requires first, each once.
# Visited is marked before recursing so a cycle cannot loop forever.
cap_order() {
  _TEEUP_CAP_VISITED=" "
  local c
  for c in "$@"; do _cap_visit "$c"; done
}

_cap_visit() {
  local c="$1" r
  case "$_TEEUP_CAP_VISITED" in *" $c "*) return 0 ;; esac
  _TEEUP_CAP_VISITED="$_TEEUP_CAP_VISITED$c "
  for r in $(cap_meta_get "$c" requires); do _cap_visit "$r"; done
  printf '%s\n' "$c"
}

cap_skipped() {
  case " ${TEEUP_SKIP:-} " in *" $1 "*) return 0 ;; esac
  return 1
}

# cap_run <name> <verb>
# Runs capabilities/<name>/<verb> as a fresh `bash -eu` with the libraries
# loaded and the answers file sourced. Wrapped in run_logged, which closes
# stdin unless the capability declares interactive=true.
cap_run() {
  local name="$1" verb="$2" dir script interactive
  dir="$(cap_dir "$name")"
  script="$dir/$verb"
  if [[ ! -f "$script" ]]; then
    err "$name has no $verb script"
    return 1
  fi
  interactive="$(cap_meta_get "$name" interactive false)"
  TEEUP_CAP="$name" TEEUP_CAP_DIR="$dir" \
    run_logged "$name $verb" "$interactive" \
    bash -eu -c 'source "$TEEUP_PATH/lib/all.sh"; answers_load; source "$1"' bash "$script"
}

# cap_check -> lints every capability; prints one problem per line.
cap_check() {
  local problems=0 name dir tier provides p verb
  for name in $(cap_list); do
    dir="$(cap_dir "$name")"
    tier="$(cap_meta_get "$name" tier)"
    [[ -n "$(cap_meta_get "$name" summary)" ]] || { echo "$name: summary is empty"; problems=$((problems + 1)); }
    case "$tier" in
      core|daily|lazy) ;;
      *) echo "$name: tier must be core, daily or lazy (got '$tier')"; problems=$((problems + 1)) ;;
    esac
    for verb in install configure; do
      if [[ ! -f "$dir/$verb" ]]; then
        echo "$name: missing $verb script"; problems=$((problems + 1))
      elif [[ ! -x "$dir/$verb" ]]; then
        echo "$name: $verb is not executable"; problems=$((problems + 1))
      fi
    done
    provides="$(cap_meta_get "$name" provides)"
    for p in $provides; do
      case " $TEEUP_SHIM_FORBIDDEN " in
        *" $p "*) echo "$name: provides must not list $p (macOS ships it, a shim can never fire)"; problems=$((problems + 1)) ;;
      esac
    done
    case "$tier" in
      core|daily)
        cap_tier_list "$tier" | grep -qx "$name" || { echo "$name: tier is $tier but it is not listed in $tier.list"; problems=$((problems + 1)); }
        ;;
      lazy)
        for verb in core daily; do
          cap_tier_list "$verb" | grep -qx "$name" && { echo "$name: tier is lazy but it is listed in $verb.list"; problems=$((problems + 1)); }
        done
        ;;
    esac
    for p in $(cap_meta_get "$name" requires); do
      cap_exists "$p" || { echo "$name: requires unknown capability $p"; problems=$((problems + 1)); }
    done
  done
  for tier in core daily; do
    for name in $(cap_tier_list "$tier"); do
      cap_exists "$name" || { echo "$tier.list: unknown capability $name"; problems=$((problems + 1)); }
    done
  done
  [[ $problems -eq 0 ]]
}
```

- [ ] **Step 4: Export the machines dir and drop the guard in `all.sh`**

In `lib/answers.sh` change the first assignment to:

```bash
TEEUP_MACHINES_DIR="${TEEUP_MACHINES_DIR:-$TEEUP_PATH/machines}"
export TEEUP_MACHINES_DIR
```

In `lib/all.sh` replace the guarded loop with:

```bash
for _teeup_lib in files state answers pkg ui capability; do
  # shellcheck source=/dev/null
  source "$_teeup_lib_dir/$_teeup_lib.sh"
done
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/lib/capability.sh && ./tests/run.sh`
Expected: `Summary: 10/10 passed`, then `All 6 suites passed.`

- [ ] **Step 6: Shellcheck and commit**

```bash
shellcheck --severity=warning lib/*.sh tests/lib/*.sh
git add lib/capability.sh lib/all.sh lib/answers.sh tests/lib/capability.sh
git commit -m "Add the capability contract with ordering, execution and lint"
```

---

### Task 10: `bin/teeup` dispatcher

**Files:**
- Create: `bin/teeup`
- Test: `tests/cli.sh`

**Interfaces:**
- Consumes: everything in `lib/all.sh`.
- Produces: the CLI verbs for this phase: `install <cap>`, `configure <cap>`, `list [--tier core|daily|lazy]`, `has <cap>`, `status`, `commands --check`, `help`, `version`. Unknown verbs exit 2. `teeup install` runs `cap_order` over the target, then `install` and `configure` for each, then marks `done/cap-<name>`. Skipped capabilities (`TEEUP_SKIP`) are refused with a message.
- Later phases add `update remove reset doctor menu launch theme config secret migrate dev lazy-run`.

- [ ] **Step 1: Write the failing test `tests/cli.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/helper.sh"

make_cap() {
  local name="$1" tier="$2" requires="${3:-}"
  local dir="$TEEUP_CAPS_DIR/$name"
  mkdir -p "$dir"
  printf 'summary="Fixture %s"\ngroup=system\ntier=%s\nrequires="%s"\nprovides=""\ninteractive=false\n' "$name" "$tier" "$requires" > "$dir/capability"
  printf '#!/usr/bin/env bash\necho "install:%s"\n' "$name" > "$dir/install"
  printf '#!/usr/bin/env bash\necho "configure:%s"\n' "$name" > "$dir/configure"
  chmod +x "$dir/install" "$dir/configure"
}

setup() {
  setup_test_env
  mock_macos_base
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR"
  make_cap alpha core
  make_cap beta core alpha
  make_cap lazyone lazy
  printf 'alpha\nbeta\n' > "$TEEUP_CAPS_DIR/core.list"
  : > "$TEEUP_CAPS_DIR/daily.list"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_runs_requires_in_order_and_marks_done() {
  setup
  local out
  out="$("$TEEUP" install beta)"
  local a b
  a="$(printf '%s\n' "$out" | grep -n 'install:alpha' | cut -d: -f1)"
  b="$(printf '%s\n' "$out" | grep -n 'install:beta' | cut -d: -f1)"
  [[ "$a" -lt "$b" ]] || { echo "alpha must install before beta"; return 1; }
  assert_contains "$out" "configure:beta" || return 1
  "$TEEUP" has beta || { echo "beta should be marked installed"; return 1; }
  "$TEEUP" has alpha || { echo "alpha should be marked installed"; return 1; }
  "$TEEUP" has lazyone && { echo "lazyone must not be marked"; return 1; }
  cleanup_test_env
}

test_install_refuses_skipped_capability() {
  setup
  local rc=0 out
  out="$(TEEUP_SKIP=beta "$TEEUP" install beta 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "beta is skipped on this machine (TEEUP_SKIP)" || return 1
  cleanup_test_env
}

test_install_unknown_capability() {
  setup
  local rc=0 out
  out="$("$TEEUP" install nope 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Unknown capability: nope" || return 1
  cleanup_test_env
}

test_configure_only() {
  setup
  local out
  out="$("$TEEUP" configure alpha)"
  assert_contains "$out" "configure:alpha" || return 1
  assert_not_contains "$out" "install:alpha" || return 1
  cleanup_test_env
}

test_list_shows_tier_and_summary() {
  setup
  local out
  out="$("$TEEUP" list)"
  assert_contains "$out" "alpha" || return 1
  assert_contains "$out" "core" || return 1
  assert_contains "$out" "Fixture alpha" || return 1
  out="$("$TEEUP" list --tier lazy)"
  assert_contains "$out" "lazyone" || return 1
  assert_not_contains "$out" "alpha" || return 1
  cleanup_test_env
}

test_status_reports_backend_and_installed() {
  setup
  "$TEEUP" install alpha >/dev/null
  local out
  out="$("$TEEUP" status)"
  assert_contains "$out" "Package manager: homebrew" || return 1
  assert_contains "$out" "Installed: 1 of 3" || return 1
  assert_contains "$out" "Answers: missing" || return 1
  cleanup_test_env
}

test_commands_check_delegates_to_cap_check() {
  setup
  "$TEEUP" commands --check || { echo "valid fixture should pass"; return 1; }
  chmod -x "$TEEUP_CAPS_DIR/alpha/install"
  "$TEEUP" commands --check >/dev/null 2>&1 && { echo "should fail"; return 1; }
  cleanup_test_env
}

test_unknown_verb_exits_2() {
  setup
  local rc=0
  "$TEEUP" frobnicate >/dev/null 2>&1 || rc=$?
  assert_equals "2" "$rc" || return 1
  cleanup_test_env
}

test_help_lists_verbs() {
  setup
  assert_contains "$("$TEEUP" help)" "teeup install <capability>" || return 1
  cleanup_test_env
}

test_dry_run_env_reaches_scripts() {
  setup
  printf '#!/usr/bin/env bash\nrun_cmd touch "$HOME/made"\n' > "$TEEUP_CAPS_DIR/alpha/install"
  DRY_RUN=true "$TEEUP" install alpha >/dev/null
  [[ ! -e "$TEST_HOME/made" ]] || { echo "dry run must not touch files"; return 1; }
  cleanup_test_env
}

echo "bin/teeup"
run_test "install runs requires in order and marks done" test_install_runs_requires_in_order_and_marks_done
run_test "install refuses skipped capability" test_install_refuses_skipped_capability
run_test "install unknown capability" test_install_unknown_capability
run_test "configure only" test_configure_only
run_test "list shows tier and summary" test_list_shows_tier_and_summary
run_test "status reports backend and installed" test_status_reports_backend_and_installed
run_test "commands --check delegates" test_commands_check_delegates_to_cap_check
run_test "unknown verb exits 2" test_unknown_verb_exits_2
run_test "help lists verbs" test_help_lists_verbs
run_test "dry run env reaches scripts" test_dry_run_env_reaches_scripts
print_summary
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/cli.sh`
Expected: FAIL, `bin/teeup: No such file or directory`.

- [ ] **Step 3: Write `bin/teeup`**

```bash
#!/usr/bin/env bash
# teeup - dispatcher for the teeup macOS environment.
# Usage: teeup <verb> [capability] [args]
set -eu

# Resolve the checkout even when invoked through the ~/.local/bin symlink.
# macOS readlink has no -f, so follow links by hand.
_self="${BASH_SOURCE[0]}"
while [[ -L "$_self" ]]; do
  _dir="$(cd "$(dirname "$_self")" && pwd)"
  _self="$(readlink "$_self")"
  [[ "$_self" != /* ]] && _self="$_dir/$_self"
done
TEEUP_PATH="${TEEUP_PATH:-$(cd "$(dirname "$_self")/.." && pwd)}"
export TEEUP_PATH
unset _self _dir

# shellcheck source=lib/all.sh
source "$TEEUP_PATH/lib/all.sh"
answers_load

usage() {
  cat <<'USAGE'
teeup - your Mac, as a distribution

  teeup install <capability>     install and configure it (and what it requires)
  teeup configure <capability>   re-run only its configuration
  teeup list [--tier core|daily|lazy]
  teeup has <capability>         exit 0 when installed (for scripts and menus)
  teeup status                   package manager, answers, installed capabilities
  teeup commands --check         lint capability metadata
  teeup version
  teeup help
USAGE
}

cmd_install() {
  local target="${1:-}" c
  [[ -n "$target" ]] || die "Usage: teeup install <capability>"
  cap_exists "$target" || die "Unknown capability: $target"
  if cap_skipped "$target"; then
    die "$target is skipped on this machine (TEEUP_SKIP)"
  fi
  for c in $(cap_order "$target"); do
    if cap_skipped "$c"; then
      warn "Skipping $c (TEEUP_SKIP)"
      continue
    fi
    cap_run "$c" install
    cap_run "$c" configure
    state_done mark "cap-$c"
  done
}

cmd_configure() {
  local target="${1:-}"
  [[ -n "$target" ]] || die "Usage: teeup configure <capability>"
  cap_exists "$target" || die "Unknown capability: $target"
  cap_run "$target" configure
}

cmd_list() {
  local tier_filter="" name tier
  if [[ "${1:-}" == "--tier" ]]; then
    tier_filter="${2:-}"
  fi
  for name in $(cap_list); do
    tier="$(cap_meta_get "$name" tier)"
    [[ -z "$tier_filter" || "$tier" == "$tier_filter" ]] || continue
    printf '%-18s %-6s %s\n' "$name" "$tier" "$(cap_meta_get "$name" summary)"
  done
}

cmd_has() {
  [[ -n "${1:-}" ]] || die "Usage: teeup has <capability>"
  state_done check "cap-$1"
}

cmd_status() {
  local total=0 installed=0 name
  echo "teeup $(cat "$TEEUP_PATH/version" 2>/dev/null || echo dev) at $TEEUP_PATH"
  echo "Package manager: $(pkg_backend)"
  if answers_exist; then echo "Answers: $(answers_file)"; else echo "Answers: missing (run ./bootstrap)"; fi
  for name in $(cap_list); do
    total=$((total + 1))
    if state_done check "cap-$name"; then
      installed=$((installed + 1))
      printf '  %-18s installed\n' "$name"
    fi
  done
  echo "Installed: $installed of $total capabilities"
}

cmd_commands() {
  case "${1:-}" in
    --check) cap_check ;;
    *) cap_list ;;
  esac
}

verb="${1:-help}"
[[ $# -gt 0 ]] && shift
case "$verb" in
  install) cmd_install "$@" ;;
  configure) cmd_configure "$@" ;;
  list) cmd_list "$@" ;;
  has) cmd_has "$@" ;;
  status) cmd_status ;;
  commands) cmd_commands "$@" ;;
  version) cat "$TEEUP_PATH/version" 2>/dev/null || echo dev ;;
  help|-h|--help) usage ;;
  *)
    err "Unknown verb: $verb"
    usage >&2
    exit 2
    ;;
esac
```

- [ ] **Step 4: Make it executable, add the version file, run the test**

```bash
chmod +x bin/teeup
echo "0.1.0-dev" > version
bash tests/cli.sh
```

Expected: `Summary: 10/10 passed`

- [ ] **Step 5: Shellcheck and commit**

```bash
shellcheck --severity=warning bin/teeup tests/cli.sh
git add bin/teeup version tests/cli.sh
git commit -m "Add the teeup dispatcher with install, configure, list, has and status"
```

---


### Task 11: The first four core capabilities

**Files:**
- Create: `capabilities/core.list`, `capabilities/daily.list`
- Create: `capabilities/xcode-clt/{capability,install,configure}`
- Create: `capabilities/package-manager/{capability,install,configure}`
- Create: `capabilities/teeup-runtime/{capability,install,configure}`
- Create: `capabilities/dev-dirs/{capability,install,configure}`
- Test: `tests/capabilities/xcode-clt.sh`, `tests/capabilities/package-manager.sh`, `tests/capabilities/teeup-runtime.sh`, `tests/capabilities/dev-dirs.sh`

**Interfaces:**
- Consumes: `cap_run` via `bin/teeup`, `pkg_backend_prepare`, `pkg_install`, `write_managed_file`, `answers_set`, `run_cmd`, `arch`.
- Produces: the tier manifests that `bootstrap` (Task 12) iterates; `~/.config/teeup/env` containing `export TEEUP_PATH=...`; the `~/.local/bin/teeup` symlink; `~/.local/state/teeup/{done,toggles,migrations,shims,logs,current,stock}`; `~/Work` and `~/Personal`.
- Every script starts with `#!/usr/bin/env bash` for shellcheck; `cap_run` sources it, so the shebang is never executed.

- [ ] **Step 1: Write the tier manifests**

`capabilities/core.list`:

```text
# Core tier: what every terminal session needs. Ordered; each entry's
# requires= must already be satisfied by the entries above it.
# Later phases append: zsh starship cli-tools secrets git ssh github mise
# wezterm fonts aerospace keyboard macos-defaults theme
xcode-clt
package-manager
teeup-runtime
dev-dirs
```

`capabilities/daily.list`:

```text
# Daily tier: installed at bootstrap when the answers say TEEUP_DAILY=yes.
# Later phases append: emacs neovim zed vscode chrome obsidian
```

- [ ] **Step 2: Write the failing tests**

`tests/capabilities/xcode-clt.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  export DRY_RUN=true
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_present_clt_and_rosetta_are_noops() {
  setup
  mock_command pkgutil 0 "package-id: com.apple.pkg.RosettaUpdateAuto"
  local out
  out="$("$TEEUP" configure xcode-clt; "$TEEUP" install xcode-clt)"
  assert_contains "$out" "Xcode Command Line Tools present." || return 1
  assert_contains "$out" "Rosetta 2 already installed." || return 1
  assert_not_contains "$out" "softwareupdate" || return 1
  cleanup_test_env
}

test_missing_clt_uses_softwareupdate_label() {
  setup
  mock_command xcode-select 2 ""
  mock_command softwareupdate 0 "* Label: Command Line Tools for Xcode-16.2"
  local out
  out="$("$TEEUP" install xcode-clt)"
  assert_contains "$out" "Would execute: touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress" || return 1
  assert_contains "$out" "Would execute: softwareupdate -i Command Line Tools for Xcode-16.2" || return 1
  cleanup_test_env
}

test_missing_clt_falls_back_to_gui() {
  setup
  mock_command xcode-select 2 ""
  mock_command softwareupdate 0 "No new software available."
  local out
  out="$("$TEEUP" install xcode-clt 2>&1)"
  assert_contains "$out" "Would execute: xcode-select --install" || return 1
  cleanup_test_env
}

test_rosetta_installed_on_arm_when_missing() {
  setup
  mock_command pkgutil 1 ""
  local out
  out="$("$TEEUP" install xcode-clt)"
  assert_contains "$out" "Would execute: /usr/sbin/softwareupdate --install-rosetta --agree-to-license" || return 1
  cleanup_test_env
}

test_rosetta_skipped_on_intel() {
  setup
  mock_command_script uname <<'EOF2'
case "$1" in -m) echo x86_64 ;; *) echo Darwin ;; esac
EOF2
  mock_command pkgutil 1 ""
  assert_not_contains "$("$TEEUP" install xcode-clt)" "install-rosetta" || return 1
  cleanup_test_env
}

echo "capabilities/xcode-clt"
run_test "present CLT and Rosetta are no-ops" test_present_clt_and_rosetta_are_noops
run_test "missing CLT uses softwareupdate label" test_missing_clt_uses_softwareupdate_label
run_test "missing CLT falls back to GUI" test_missing_clt_falls_back_to_gui
run_test "Rosetta installed on arm when missing" test_rosetta_installed_on_arm_when_missing
run_test "Rosetta skipped on Intel" test_rosetta_skipped_on_intel
print_summary
```

`tests/capabilities/package-manager.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_bootstraps_homebrew_in_dry_run() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install package-manager)"
  assert_contains "$out" "Homebrew/install/HEAD/install.sh" || return 1
  assert_contains "$out" "Would execute: brew update" || return 1
  cleanup_test_env
}

test_install_refuses_missing_macports() {
  setup
  mock_command sw_vers 0 "12.7.1"
  local rc=0 out
  out="$(DRY_RUN=true "$TEEUP" install package-manager 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "MacPorts is not installed" || return 1
  cleanup_test_env
}

test_configure_records_backend_in_answers() {
  setup
  mock_command brew 0 ""
  DRY_RUN=false "$TEEUP" configure package-manager >/dev/null
  assert_contains "$(cat "$TEST_HOME/.config/teeup/answers")" 'TEEUP_PACKAGE_MANAGER="homebrew"' || return 1
  cleanup_test_env
}

test_configure_keeps_existing_answer() {
  setup
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_PACKAGE_MANAGER="macports"\n' > "$TEST_HOME/.config/teeup/answers"
  mock_command port 0 ""
  DRY_RUN=false "$TEEUP" configure package-manager >/dev/null
  assert_contains "$(cat "$TEST_HOME/.config/teeup/answers")" 'TEEUP_PACKAGE_MANAGER="macports"' || return 1
  cleanup_test_env
}

echo "capabilities/package-manager"
run_test "install bootstraps Homebrew in dry run" test_install_bootstraps_homebrew_in_dry_run
run_test "install refuses missing MacPorts" test_install_refuses_missing_macports
run_test "configure records backend in answers" test_configure_records_backend_in_answers
run_test "configure keeps existing answer" test_configure_keeps_existing_answer
print_summary
```

`tests/capabilities/teeup-runtime.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_gets_gum_and_jq() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install teeup-runtime)"
  assert_contains "$out" "Would execute: brew install gum" || return 1
  assert_contains "$out" "Would execute: brew install jq" || return 1
  cleanup_test_env
}

test_configure_creates_state_env_and_link() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local d
  for d in done toggles migrations shims logs current stock; do
    assert_dir_exists "$TEST_HOME/.local/state/teeup/$d" || return 1
  done
  assert_equals "export TEEUP_PATH=\"$TEEUP_PATH\"" "$(cat "$TEST_HOME/.config/teeup/env")" || return 1
  assert_equals "$TEEUP_PATH/bin/teeup" "$(readlink "$TEST_HOME/.local/bin/teeup")" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure teeup-runtime)"
  assert_contains "$out" "Already current: $TEST_HOME/.config/teeup/env" || return 1
  assert_contains "$out" "Already linked" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  DRY_RUN=true "$TEEUP" configure teeup-runtime >/dev/null
  [[ ! -e "$TEST_HOME/.config/teeup/env" ]] || { echo "env written in dry run"; return 1; }
  [[ ! -e "$TEST_HOME/.local/bin/teeup" ]] || { echo "link made in dry run"; return 1; }
  cleanup_test_env
}

echo "capabilities/teeup-runtime"
run_test "install gets gum and jq" test_install_gets_gum_and_jq
run_test "configure creates state, env and link" test_configure_creates_state_env_and_link
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
print_summary
```

`tests/capabilities/dev-dirs.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_creates_work_and_personal() {
  setup
  DRY_RUN=false "$TEEUP" install dev-dirs >/dev/null
  assert_dir_exists "$TEST_HOME/Work" || return 1
  assert_dir_exists "$TEST_HOME/Personal" || return 1
  cleanup_test_env
}

test_existing_dirs_are_reported_not_recreated() {
  setup
  mkdir -p "$TEST_HOME/Work"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure dev-dirs)"
  assert_contains "$out" "Already present: $TEST_HOME/Work" || return 1
  assert_dir_exists "$TEST_HOME/Personal" || return 1
  cleanup_test_env
}

echo "capabilities/dev-dirs"
run_test "creates Work and Personal" test_creates_work_and_personal
run_test "existing dirs reported not recreated" test_existing_dirs_are_reported_not_recreated
print_summary
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `./tests/run.sh`
Expected: the four capability suites FAIL with `Unknown capability`.

- [ ] **Step 4: Write `capabilities/xcode-clt/`**

`capability`:

```sh
summary="Xcode Command Line Tools and Rosetta 2"
group=system
tier=core
requires=""
provides=""
interactive=false
```

`install`:

```bash
#!/usr/bin/env bash
# Command Line Tools first, because Homebrew and every compiler need them.
# Unattended path: the on-demand marker makes softwareupdate list the CLT
# package; fall back to the GUI installer when it does not.
if xcode-select -p >/dev/null 2>&1; then
  ok "Xcode Command Line Tools present."
else
  log "Installing Xcode Command Line Tools..."
  marker="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
  run_cmd touch "$marker"
  label="$(softwareupdate -l 2>/dev/null | grep -o 'Command Line Tools for Xcode-[0-9.]*' | tail -1 || true)"
  if [[ -n "$label" ]]; then
    run_cmd softwareupdate -i "$label"
  else
    warn "softwareupdate lists no Command Line Tools package; opening the GUI installer."
    run_cmd xcode-select --install || true
    warn "Complete the dialog, then re-run ./bootstrap."
  fi
  run_cmd rm -f "$marker"
fi

# Rosetta 2 lets Intel-only casks and tools run on Apple Silicon.
if [[ "$(arch)" == "arm64" ]]; then
  if pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
    ok "Rosetta 2 already installed."
  else
    log "Installing Rosetta 2 (Apple Silicon)..."
    run_cmd /usr/sbin/softwareupdate --install-rosetta --agree-to-license || warn "Rosetta install may require approval."
  fi
fi
```

`configure`:

```bash
#!/usr/bin/env bash
# Nothing to configure. The file exists so `teeup configure xcode-clt` is a
# recorded no-op rather than an error.
:
```

- [ ] **Step 5: Write `capabilities/package-manager/`**

`capability`:

```sh
summary="Homebrew, or MacPorts on macOS 12 and older"
group=system
tier=core
requires="xcode-clt"
provides=""
interactive=true
```

`install`:

```bash
#!/usr/bin/env bash
# Installs Homebrew when missing (its installer asks for sudo, hence
# interactive=true) or refreshes MacPorts. MacPorts is never auto-installed.
pkg_backend_prepare
```

`configure`:

```bash
#!/usr/bin/env bash
# Record the resolved backend so every later run agrees with this one, even
# after a macOS upgrade moves the machine past the MacPorts cut-off.
if [[ -z "$(answers_get TEEUP_PACKAGE_MANAGER)" ]]; then
  answers_set TEEUP_PACKAGE_MANAGER "$(pkg_backend)"
  ok "Recorded package manager: $(pkg_backend)"
else
  log "Package manager already recorded: $(answers_get TEEUP_PACKAGE_MANAGER)"
fi
```

- [ ] **Step 6: Write `capabilities/teeup-runtime/`**

`capability`:

```sh
summary="teeup state directories, env file and the teeup command"
group=system
tier=core
requires="package-manager"
provides=""
interactive=false
```

`install`:

```bash
#!/usr/bin/env bash
# gum draws the wizard and menus; jq reads the menu definition and app settings.
pkg_backend_path
pkg_install gum gum
pkg_install jq jq
```

`configure` (the heredoc terminator is `TEEUP_ENV` on purpose so this file can be pasted through another heredoc):

```bash
#!/usr/bin/env bash
# State lives under ~/.local/state/teeup as plain files; the env file tells
# shells and LaunchAgents where the checkout is; ~/.local/bin/teeup is the
# command users type.
for d in done toggles migrations shims logs current stock; do
  [[ -d "$TEEUP_STATE_DIR/$d" ]] || run_cmd mkdir -p "$TEEUP_STATE_DIR/$d"
done
[[ -d "$TEEUP_CONFIG_DIR/hooks" ]] || run_cmd mkdir -p "$TEEUP_CONFIG_DIR/hooks"

write_managed_file "$TEEUP_CONFIG_DIR/env" "teeup env" <<TEEUP_ENV
export TEEUP_PATH="$TEEUP_PATH"
TEEUP_ENV

link="$HOME/.local/bin/teeup"
[[ -d "$HOME/.local/bin" ]] || run_cmd mkdir -p "$HOME/.local/bin"
if [[ "$(readlink "$link" 2>/dev/null)" == "$TEEUP_PATH/bin/teeup" ]]; then
  log "Already linked: $link"
else
  run_cmd ln -sfn "$TEEUP_PATH/bin/teeup" "$link"
  ok "Linked $link"
fi
```

- [ ] **Step 7: Write `capabilities/dev-dirs/`**

`capability`:

```sh
summary="~/Work and ~/Personal project roots"
group=system
tier=core
requires=""
provides=""
interactive=false
```

`install`:

```bash
#!/usr/bin/env bash
# Nothing to install; the directories are created by configure.
:
```

`configure`:

```bash
#!/usr/bin/env bash
# Two roots. The git capability keys identity off them (includeIf), so they
# must exist before git is configured.
for d in "$HOME/Work" "$HOME/Personal"; do
  if [[ -d "$d" ]]; then
    log "Already present: $d"
  else
    run_cmd mkdir -p "$d"
    ok "Created $d"
  fi
done
```

- [ ] **Step 8: Make the scripts executable and run everything**

```bash
chmod +x capabilities/*/install capabilities/*/configure
./bin/teeup commands --check
./tests/run.sh
```

Expected: `commands --check` prints nothing and exits 0; `All 11 suites passed.`

- [ ] **Step 9: Shellcheck and commit**

```bash
shellcheck --severity=warning capabilities/*/install capabilities/*/configure tests/capabilities/*.sh
git add capabilities tests/capabilities
git commit -m "Add the xcode-clt, package-manager, teeup-runtime and dev-dirs capabilities"
```

---

### Task 12: `bootstrap`

**Files:**
- Create: `bootstrap`
- Test: `tests/bootstrap.sh`

**Interfaces:**
- Consumes: `lib/all.sh`, `cap_run`, `cap_tier_list`, `cap_skipped`, `cap_exists`, `ui_input`, `ui_confirm`, `ui_choose`, `answers_*`, `state_done`, `state_migration_mark`, `pkg_backend`, `pkg_backend_path`, `format_duration`.
- Produces: the fresh-Mac entry point described in spec section 5. Flags: `--dry-run`, `--reconfigure`, `--skip-daily`, `--help`. Exit 1 on a non-macOS host, when run as root, or when a core capability fails; exit 2 on an unknown flag. Daily failures warn and continue.
- The wizard writes `TEEUP_NAME`, `TEEUP_EMAIL`, `TEEUP_WORK_EMAIL`, `TEEUP_PACKAGE_MANAGER`, `TEEUP_THEME`, `TEEUP_DAILY`.

- [ ] **Step 1: Write the failing test `tests/bootstrap.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/helper.sh"

BOOT="$TEEUP_PATH/bootstrap"

# Answers piped to the plain-read wizard, one per prompt:
# name, email, work email, package manager choice, theme choice, daily confirm.
WIZARD_INPUT=$'Ada Lovelace\nada@example.com\n\n1\n1\ny\n'

setup() {
  setup_test_env
  mock_macos_base
  mock_command softwareupdate 0 ""
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  export TEEUP_NO_GUM=1
  export DRY_RUN=true
}

test_refuses_non_macos() {
  setup
  mock_command uname 0 "Linux"
  local rc=0 out
  out="$("$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")" || rc=$?
  assert_equals "1" "$rc" || return 1
  assert_contains "$out" "teeup targets macOS only" || return 1
  cleanup_test_env
}

test_refuses_root() {
  setup
  mock_command id 0 "0"
  local rc=0 out
  out="$("$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")" || rc=$?
  assert_equals "1" "$rc" || return 1
  assert_contains "$out" "not root" || return 1
  cleanup_test_env
}

test_unknown_flag_exits_2() {
  setup
  local rc=0
  "$BOOT" --frobnicate >/dev/null 2>&1 || rc=$?
  assert_equals "2" "$rc" || return 1
  cleanup_test_env
}

test_dry_run_walks_core_tier_in_order() {
  setup
  local out
  out="$("$BOOT" --dry-run <<<"$WIZARD_INPUT")"
  local x p r d
  x="$(printf '%s\n' "$out" | grep -n 'Completed: xcode-clt install' | head -1 | cut -d: -f1)"
  p="$(printf '%s\n' "$out" | grep -n 'Completed: package-manager install' | head -1 | cut -d: -f1)"
  r="$(printf '%s\n' "$out" | grep -n 'Completed: teeup-runtime configure' | head -1 | cut -d: -f1)"
  d="$(printf '%s\n' "$out" | grep -n 'Completed: dev-dirs configure' | head -1 | cut -d: -f1)"
  [[ -n "$x" && -n "$p" && -n "$r" && -n "$d" ]] || { echo "a core step did not complete:"; printf '%s\n' "$out"; return 1; }
  [[ "$x" -lt "$p" && "$p" -lt "$r" && "$r" -lt "$d" ]] || { echo "core tier ran out of order"; return 1; }
  assert_contains "$out" "Homebrew/install/HEAD/install.sh" || return 1
  assert_contains "$out" "Would set TEEUP_NAME" || return 1
  assert_contains "$out" "Would record state: done/bootstrap" || return 1
  assert_contains "$out" "Bootstrap finished" || return 1
  cleanup_test_env
}

test_dry_run_touches_nothing() {
  setup
  "$BOOT" --dry-run <<<"$WIZARD_INPUT" >/dev/null
  [[ ! -e "$TEST_HOME/.config/teeup/answers" ]] || { echo "answers written in dry run"; return 1; }
  [[ ! -e "$TEST_HOME/Work" ]] || { echo "Work created in dry run"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "sudo" "no sudo in dry run" || return 1
  cleanup_test_env
}

test_existing_answers_skip_wizard() {
  setup
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_NAME="Ada"\nTEEUP_EMAIL="ada@example.com"\nTEEUP_PACKAGE_MANAGER="homebrew"\nTEEUP_THEME="catppuccin"\nTEEUP_DAILY="yes"\n' > "$TEST_HOME/.config/teeup/answers"
  local out
  out="$("$BOOT" --dry-run </dev/null)"
  assert_contains "$out" "Using existing answers" || return 1
  assert_not_contains "$out" "Your full name" || return 1
  cleanup_test_env
}

test_reconfigure_reruns_wizard() {
  setup
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_NAME="Ada"\n' > "$TEST_HOME/.config/teeup/answers"
  local out
  out="$("$BOOT" --dry-run --reconfigure 2>&1 <<<"$WIZARD_INPUT")"
  assert_contains "$out" "Your full name" || return 1
  cleanup_test_env
}

test_skip_daily_and_daily_no_skip_the_tier() {
  setup
  local out
  out="$("$BOOT" --dry-run --skip-daily <<<"$WIZARD_INPUT")"
  assert_contains "$out" "Skipping the daily tier" || return 1
  cleanup_test_env
}

test_teeup_skip_skips_a_core_capability() {
  setup
  local out
  out="$(TEEUP_SKIP=dev-dirs "$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")"
  assert_contains "$out" "Skipping dev-dirs (TEEUP_SKIP)" || return 1
  assert_not_contains "$out" "Completed: dev-dirs configure" || return 1
  cleanup_test_env
}

test_core_failure_aborts() {
  setup
  mock_command sw_vers 0 "12.7.1"   # MacPorts path, port missing -> package-manager fails
  local rc=0 out
  out="$("$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")" || rc=$?
  assert_equals "1" "$rc" || return 1
  assert_contains "$out" "Core capability package-manager failed" || return 1
  assert_not_contains "$out" "Completed: dev-dirs configure" || return 1
  cleanup_test_env
}

echo "bootstrap"
run_test "refuses non-macOS" test_refuses_non_macos
run_test "refuses root" test_refuses_root
run_test "unknown flag exits 2" test_unknown_flag_exits_2
run_test "dry run walks core tier in order" test_dry_run_walks_core_tier_in_order
run_test "dry run touches nothing" test_dry_run_touches_nothing
run_test "existing answers skip wizard" test_existing_answers_skip_wizard
run_test "--reconfigure reruns wizard" test_reconfigure_reruns_wizard
run_test "--skip-daily skips the tier" test_skip_daily_and_daily_no_skip_the_tier
run_test "TEEUP_SKIP skips a core capability" test_teeup_skip_skips_a_core_capability
run_test "core failure aborts" test_core_failure_aborts
print_summary
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/bootstrap.sh`
Expected: FAIL, `bootstrap: No such file or directory`.

- [ ] **Step 3: Write `bootstrap`**

```bash
#!/usr/bin/env bash
# bootstrap - set up a fresh Mac with teeup.
#
#   git clone <repo> ~/.local/share/teeup && cd ~/.local/share/teeup && ./bootstrap
#
# bash 3.2, no dependencies beyond a fresh macOS. Safe to re-run: every step
# is idempotent, so re-running is also the repair path.
set -eu

TEEUP_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TEEUP_PATH
# shellcheck source=lib/all.sh
source "$TEEUP_PATH/lib/all.sh"

RECONFIGURE=false
SKIP_DAILY=false

usage() {
  cat <<'USAGE'
Usage: ./bootstrap [--dry-run] [--reconfigure] [--skip-daily]

  --dry-run      print every command instead of running it
  --reconfigure  ask the setup questions again even if answers exist
  --skip-daily   install only the core tier this run
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --reconfigure) RECONFIGURE=true ;;
    --skip-daily) SKIP_DAILY=true ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1"; usage >&2; exit 2 ;;
  esac
  shift
done
export DRY_RUN

if [[ "$DRY_RUN" != "true" ]]; then
  TEEUP_LOG_FILE="${TEEUP_LOG_FILE:-$TEEUP_STATE_DIR/logs/bootstrap.log}"
fi
export TEEUP_LOG_FILE

started="$(date +%s)"

# --- 0. preflight -----------------------------------------------------------
is_macos || die "teeup targets macOS only (uname -s reports $(uname -s))."
[[ "$(id -u)" -ne 0 ]] || die "Run bootstrap as your user, not root."
if [[ "$DRY_RUN" == "true" ]]; then
  log "Dry run: nothing will be changed."
else
  sudo -v || die "sudo is required for the package manager and system settings."
  ( while true; do sudo -n true; sleep 60; done ) 2>/dev/null &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
fi
log "macOS $(sw_vers -productVersion 2>/dev/null || echo '?') on $(arch), teeup at $TEEUP_PATH"

# --- helpers ----------------------------------------------------------------
run_capability() {
  # run_capability <name> -> install then configure, then mark done.
  local name="$1"
  cap_run "$name" install || return 1
  cap_run "$name" configure || return 1
  state_done mark "cap-$name"
}

run_tier() {
  # run_tier <core|daily>. Core failures abort; daily failures warn.
  local tier="$1" name
  for name in $(cap_tier_list "$tier"); do
    if ! cap_exists "$name"; then
      warn "$name is listed in $tier.list but not implemented yet; skipping."
      continue
    fi
    if cap_skipped "$name"; then
      warn "Skipping $name (TEEUP_SKIP)"
      continue
    fi
    if ! run_capability "$name"; then
      if [[ "$tier" == "core" ]]; then
        die "Core capability $name failed. See ${TEEUP_LOG_FILE:-the output above}, fix the cause, and re-run ./bootstrap."
      fi
      warn "Daily capability $name failed; continuing. Re-run with: teeup install $name"
    fi
  done
}

wizard() {
  local name email work_email pm theme daily
  echo ""
  echo "A few questions. Answers are saved to $(answers_file) and can be changed later with: teeup config set"
  echo ""
  name="$(ui_input "Your full name" "$(answers_get TEEUP_NAME "$(id -F 2>/dev/null || true)")")"
  email="$(ui_input "Personal email (git identity under ~/Personal)" "$(answers_get TEEUP_EMAIL)")"
  work_email="$(ui_input "Work email (git identity under ~/Work, empty for none)" "$(answers_get TEEUP_WORK_EMAIL)")"
  pm="$(ui_choose "Package manager" "$(pkg_backend)" "$(if [[ "$(pkg_backend)" == homebrew ]]; then echo macports; else echo homebrew; fi)")"
  theme="$(ui_choose "Theme (applied once the theme capability lands)" catppuccin tokyo-night gruvbox nord)"
  if ui_confirm "Install the daily set too (Emacs, Neovim, Zed, VS Code, Chrome, Obsidian)?" yes; then
    daily=yes
  else
    daily=no
  fi
  answers_set TEEUP_NAME "$name"
  answers_set TEEUP_EMAIL "$email"
  answers_set TEEUP_WORK_EMAIL "$work_email"
  answers_set TEEUP_PACKAGE_MANAGER "$pm"
  answers_set TEEUP_THEME "$theme"
  answers_set TEEUP_DAILY "$daily"
  unset TEEUP_PKG_BACKEND
  answers_load
}

# --- 1. Xcode Command Line Tools, Rosetta ------------------------------------
cap_run xcode-clt install || die "Xcode Command Line Tools are required. Complete the installer and re-run ./bootstrap."

# --- 2. package manager -------------------------------------------------------
answers_load
run_capability package-manager || die "Core capability package-manager failed. Fix the cause and re-run ./bootstrap."
pkg_backend_path

# --- 3. teeup runtime (env file, command link, gum, jq) -----------------------
run_capability teeup-runtime || die "Core capability teeup-runtime failed. Fix the cause and re-run ./bootstrap."

# --- 4. answers ---------------------------------------------------------------
if answers_exist && [[ "$RECONFIGURE" != "true" ]]; then
  log "Using existing answers from $(answers_file) (pass --reconfigure to change them)."
else
  wizard
fi

# --- 5 and 6. tiers -----------------------------------------------------------
run_tier core
if [[ "$SKIP_DAILY" == "true" ]]; then
  log "Skipping the daily tier (--skip-daily)."
elif [[ "$(answers_get TEEUP_DAILY yes)" == "no" ]]; then
  log "Skipping the daily tier (TEEUP_DAILY=no)."
else
  run_tier daily
fi

# --- 7. theme and state -------------------------------------------------------
if cap_exists theme; then
  cap_run theme configure || warn "Theme configuration failed; run: teeup theme set $(answers_get TEEUP_THEME)"
fi
if ! state_done check bootstrap; then
  # A fresh install starts with every shipped migration already applied.
  for m in "$TEEUP_PATH"/migrations/*.sh; do
    [[ -f "$m" ]] || continue
    state_migration_mark "$(basename "$m")"
  done
fi
state_done mark bootstrap

# --- 8. summary ---------------------------------------------------------------
echo ""
ok "Bootstrap finished in $(format_duration $(( $(date +%s) - started )))."
echo "Open a new terminal (or run: exec zsh) and try: teeup status"
```

- [ ] **Step 4: Make it executable and run the test**

```bash
chmod +x bootstrap
bash tests/bootstrap.sh
```

Expected: `Summary: 10/10 passed`

- [ ] **Step 5: Run the whole suite and shellcheck**

Run: `./tests/run.sh && shellcheck --severity=warning bootstrap tests/bootstrap.sh`
Expected: `All 12 suites passed.` and no shellcheck output.

- [ ] **Step 6: Commit**

```bash
git add bootstrap tests/bootstrap.sh
git commit -m "Add the bootstrap entry point with preflight, wizard and tiers"
```

---

### Task 13: CI, README and contributor docs for the new runtime

**Files:**
- Modify: `.github/workflows/ci.yml`, `README.md`, `CONTRIBUTING.md`, `.gitignore`

**Interfaces:**
- Produces: CI runs shellcheck on every new script, `./bin/teeup commands --check`, `./tests/run.sh`, and the legacy suite, on macos-14, macos-15-intel and ubuntu-latest.

- [ ] **Step 1: Add the new steps to CI**

Insert after the legacy steps in `.github/workflows/ci.yml`:

```yaml
      - name: Shellcheck new runtime
        run: |
          shellcheck --severity=warning bootstrap bin/teeup lib/*.sh \
            capabilities/*/install capabilities/*/configure \
            tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh \
            tests/lib/*.sh tests/capabilities/*.sh

      - name: Lint capability metadata
        run: ./bin/teeup commands --check

      - name: Run new runtime tests
        env:
          CI: "true"
        run: ./tests/run.sh
```

- [ ] **Step 2: Document the new runtime in `README.md`**

Replace the banner from Task 1 with:

```markdown
> **Redesign in progress.** teeup is being rebuilt as a modular, macOS-only
> environment distribution (design:
> `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md`).
> The new runtime lives in `bootstrap`, `bin/teeup`, `lib/` and
> `capabilities/`. The previous installer still works from `legacy/`.

## New runtime (preview)

```bash
git clone https://github.com/systemhalted/teeup.sh ~/.local/share/teeup
cd ~/.local/share/teeup
./bootstrap --dry-run     # preview everything it would do
./bootstrap               # run it
teeup status              # what is installed
teeup list                # every capability and its tier
teeup install <name>      # install and configure one capability
```

Capabilities implemented so far: `xcode-clt`, `package-manager`,
`teeup-runtime`, `dev-dirs`. The rest arrive phase by phase; `teeup list`
is always the source of truth.
```

- [ ] **Step 3: Add the capability contract to `CONTRIBUTING.md`**

Append:

```markdown
## Adding a capability (new runtime)

1. Create `capabilities/<name>/` with `capability`, `install`, `configure`.
2. `capability` is a sourced `KEY=value` file: `summary`, `group`, `tier`
   (`core|daily|lazy`), `requires`, `provides`, `packages`, `casks`, `apps`,
   `interactive`.
3. `install` only installs packages (`pkg_install`, `cask_install`).
   `configure` only writes configuration (`copy_config_once`,
   `write_managed_file`, `append_once`, `run_cmd`). Both are idempotent and
   run as `bash -eu` with `lib/all.sh` loaded and the answers file sourced.
4. Never call `sudo`; use `run_privileged`. Never mutate outside `run_cmd`.
5. `provides` must not list a command macOS already ships (`python3`, `ruby`,
   `java`, `git`, `perl`).
6. Add the name to `capabilities/core.list` or `daily.list` if it is not lazy.
7. Add `tests/capabilities/<name>.sh` using the mock harness; run
   `./bin/teeup commands --check && ./tests/run.sh` before committing.
```

- [ ] **Step 4: Ignore machine files that are not meant to be committed yet**

Append to `.gitignore`:

```text
# Per-machine overrides are committed deliberately; keep drafts out.
machines/*.draft
```

- [ ] **Step 5: Verify and commit**

```bash
shellcheck --severity=warning bootstrap bin/teeup lib/*.sh capabilities/*/install capabilities/*/configure tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh tests/lib/*.sh tests/capabilities/*.sh
./bin/teeup commands --check
./tests/run.sh
./legacy/tests/run_tests.sh
git add .github/workflows/ci.yml README.md CONTRIBUTING.md .gitignore
git commit -m "Wire the new runtime into CI and document it"
```

---

## Self-review

**Spec coverage for Phase 0 and 1.** Legacy freeze (Task 1); test harness (Task 2); `lib/core.sh` with `run_logged` stdin rule (Task 3); `lib/files.sh` with `copy_config_once` semantics from spec section 10 and `refresh_config` from section 7 (Task 4); `lib/state.sh` with `done ensure` noclobber (Task 5); answers file and committed per-hostname override with machine-wins precedence (Task 6); Homebrew and MacPorts backends with the macOS 12 cut-off and cask skip on MacPorts (Task 7); gum with read fallback (Task 8); capability contract, `requires` ordering, `provides` forbidden list, `commands --check` (Task 9); dispatcher verbs `install configure list has status commands help version` (Task 10); the first four core entries and both tier manifests (Task 11); bootstrap steps 0 to 8 including the unattended CLT path, sudo keepalive, wizard with daily defaulting to yes, mark-all-migrations-done on first install (Task 12); CI on all three runners (Task 13).

**Deferred to later plans, by spec section:** remaining core and daily capabilities and themes (section 5, 7); shims, mise wrappers, `dev-env`, `launch`, `lazy-run` (section 6); `secrets`, `defaults_write` record and restore, fonts, git extras, hooks (section 7); `update`, migrations runner, `reset`, `doctor`, `menu`, `config`, `migrate legacy`, `dev` verbs (sections 9, 10, 12); the agent skill (section 2).

**Placeholder scan:** no TBD, TODO or "similar to Task N". Every code step shows the code.

**Type and name consistency checked:** `run_logged <name> <interactive> <cmd...>` (Task 3) matches its use in `cap_run` (Task 9). `state_done mark "cap-$name"` (Tasks 10, 12) matches `cmd_has` (Task 10). `answers_get KEY default` (Task 6) matches every call in Tasks 7, 11, 12. `pkg_backend_prepare`, `pkg_backend_path`, `pkg_install <pkg> [cmd]`, `cask_install` (Task 7) match Tasks 11 and 12. `TEEUP_CAPS_DIR` and `TEEUP_MACHINES_DIR` overrides used by tests are exported by Tasks 9 and 6. The helper's `mock_command` logs every call to `MOCK_LOG` as `<name> <args>`, which Tasks 7, 10 and 12 assert on.

**Known test-environment caveat:** `id -F` (full name) is macOS-only; the wizard tolerates its absence with `|| true`. `readlink` without `-f` is used everywhere so the code runs on macOS. `shasum` exists on both macOS and Ubuntu runners; `sha256sum` is the fallback.
