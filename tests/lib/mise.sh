#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# A mise that keeps "requested" (the global config's tool list, in
# mise-tools) and "installed" (what is on disk, in mise-installed) apart, the
# way the real one does. `use -g` records both, stripping any @version; a
# tool listed in mise-local-tools stands for a project config in the cwd,
# which only an unpinned (no `-C /`) call can see.
mock_mise() {
  mock_command_script mise <<'EOF2'
pinned=0
[ "$1" = "-C" ] && { pinned=1; shift 2; }
shadowed() { [ "$pinned" = "0" ] && grep -qx "$1" "$HOME/mise-local-tools" 2>/dev/null; }
case "$*" in
  "ls --global --installed"*)
    tool="${4:-}"
    [ -f "$HOME/mise-tools" ] || exit 0
    while read -r name; do
      [ -z "$tool" ] || [ "$name" = "$tool" ] || continue
      shadowed "$name" && continue
      grep -qx "$name" "$HOME/mise-installed" 2>/dev/null && printf '%s latest ~/.config/mise/config.toml latest\n' "$name"
    done < "$HOME/mise-tools"
    ;;
  "ls --global"*)
    tool="${3:-}"
    [ -f "$HOME/mise-tools" ] || exit 0
    while read -r name; do
      [ -z "$tool" ] || [ "$name" = "$tool" ] || continue
      shadowed "$name" && continue
      if grep -qx "$name" "$HOME/mise-installed" 2>/dev/null; then
        printf '%s latest ~/.config/mise/config.toml latest\n' "$name"
      else
        printf '%s latest (missing) ~/.config/mise/config.toml latest\n' "$name"
      fi
    done < "$HOME/mise-tools"
    ;;
  "where "*)
    grep -qx "$2" "$HOME/mise-installed" 2>/dev/null || exit 1
    ;;
  "use "*)
    shift
    while [ $# -gt 0 ]; do
      case "$1" in -g|--global|--quiet|-q) shift ;; *) break ;; esac
    done
    name="${1%%@*}"
    printf '%s\n' "$name" >> "$HOME/mise-tools"
    printf '%s\n' "$name" >> "$HOME/mise-installed"
    ;;
  "install "*)
    printf '%s\n' "$2" >> "$HOME/mise-installed"
    ;;
  "x "*)
    shift
    tools=""
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do tools="$tools${tools:+,}$1"; shift; done
    shift
    echo "mise-x:$tools:$*"
    ;;
  *) : ;;
esac
exit 0
EOF2
}

setup() {
  setup_test_env
  mock_macos_base
  mock_mise
  source "$TEEUP_PATH/lib/all.sh"
  export DRY_RUN=false
}

# Real Mac, 2026-09-26: teeup remove ai deleted the wrappers but left each
# tool installed and still requested in the global mise config, so the next
# teeup update (mise upgrade) would bring it back. Removing a tool teeup
# requested takes the request out too.
test_tool_unuse_drops_a_requested_tool() {
  setup
  printf 'claude\n' > "$TEST_HOME/mise-tools"
  printf 'claude\n' > "$TEST_HOME/mise-installed"
  mise_tool_unuse claude >/dev/null 2>&1 || { echo "unuse failed"; return 1; }
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / unuse -g claude" || return 1
  cleanup_test_env
}

test_tool_unuse_leaves_an_unrequested_tool_alone() {
  setup
  mise_tool_unuse claude >/dev/null 2>&1 || { echo "nothing to drop is not a failure"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG" 2>/dev/null)" "unuse" || return 1
  cleanup_test_env
}

# Codex on #46: with mise off PATH a tool the config file still requests must
# fail the remove, or its marker clears while the request stays.
test_tool_unuse_fails_without_mise_while_the_config_requests_the_tool() {
  setup
  # TEEUP_TEST_MISSING hides mise from `have`; the failing mock stands in for
  # the host's own mise, which mise_global_state would otherwise run.
  export TEEUP_TEST_MISSING=mise
  printf '#!/bin/sh\nexit 127\n' > "$MOCK_BIN/mise"
  chmod +x "$MOCK_BIN/mise"
  export MISE_GLOBAL_CONFIG_FILE="$TEST_HOME/mise-config.toml"
  printf '[tools]\nclaude = "latest"\n' > "$MISE_GLOBAL_CONFIG_FILE"
  local out rc=0
  out="$(mise_tool_unuse claude 2>&1)" || rc=$?
  unset MISE_GLOBAL_CONFIG_FILE TEEUP_TEST_MISSING
  assert_equals "1" "$rc" "the remove must stay retryable" || return 1
  assert_contains "$out" "mise unuse -g claude" "names the recovery command" || return 1
  cleanup_test_env
}

test_tool_unuse_without_mise_still_previews_in_a_dry_run() {
  setup
  export TEEUP_TEST_MISSING=mise
  printf '#!/bin/sh\nexit 127\n' > "$MOCK_BIN/mise"
  chmod +x "$MOCK_BIN/mise"
  export MISE_GLOBAL_CONFIG_FILE="$TEST_HOME/mise-config.toml"
  printf '[tools]\nclaude = "latest"\n' > "$MISE_GLOBAL_CONFIG_FILE"
  local out rc=0
  out="$(DRY_RUN=true mise_tool_unuse claude 2>&1)" || rc=$?
  unset MISE_GLOBAL_CONFIG_FILE TEEUP_TEST_MISSING
  assert_equals "0" "$rc" "a dry run needs no mise" || return 1
  assert_contains "$out" "unuse -g claude" "the preview names the command" || return 1
  cleanup_test_env
}

test_tool_unuse_without_mise_passes_a_tool_nothing_requests() {
  setup
  # TEEUP_TEST_MISSING hides mise from `have`; the failing mock stands in for
  # the host's own mise, which mise_global_state would otherwise run.
  export TEEUP_TEST_MISSING=mise
  printf '#!/bin/sh\nexit 127\n' > "$MOCK_BIN/mise"
  chmod +x "$MOCK_BIN/mise"
  export MISE_GLOBAL_CONFIG_FILE="$TEST_HOME/mise-config.toml"
  printf '[tools]\nnode = "22"\n' > "$MISE_GLOBAL_CONFIG_FILE"
  local rc=0
  mise_tool_unuse claude >/dev/null 2>&1 || rc=$?
  unset MISE_GLOBAL_CONFIG_FILE TEEUP_TEST_MISSING
  assert_equals "0" "$rc" "nothing to drop is not a failure" || return 1
  cleanup_test_env
}

test_tool_unuse_changes_nothing_in_a_dry_run() {
  setup
  printf 'claude\n' > "$TEST_HOME/mise-tools"
  local out
  out="$(DRY_RUN=true mise_tool_unuse claude 2>&1)"
  assert_not_contains "$(cat "$MOCK_LOG" 2>/dev/null)" "unuse" || return 1
  assert_contains "$out" "unuse -g claude" "the preview names the command" || return 1
  cleanup_test_env
}

test_tool_unuse_reports_a_failed_unuse() {
  setup
  printf 'claude\n' > "$TEST_HOME/mise-tools"
  mock_command_script mise <<'EOF2'
case "$*" in
  "-C / ls --global"*) echo "claude latest ~/.config/mise/config.toml latest" ;;
  *unuse*) exit 1 ;;
esac
EOF2
  local rc=0 out
  out="$(mise_tool_unuse claude 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "mise unuse -g claude" "name the command to run by hand" || return 1
  cleanup_test_env
}

test_global_state_distinguishes_the_three_cases() {
  setup
  assert_equals "absent" "$(mise_global_state uv)" || return 1
  printf 'uv\n' > "$TEST_HOME/mise-tools"
  assert_equals "requested" "$(mise_global_state uv)" || return 1
  printf 'uv\n' > "$TEST_HOME/mise-installed"
  assert_equals "installed" "$(mise_global_state uv)" || return 1
  cleanup_test_env
}

test_global_state_is_not_fooled_by_a_project_config() {
  setup
  printf 'uv\n' > "$TEST_HOME/mise-tools"
  printf 'uv\n' > "$TEST_HOME/mise-installed"
  printf 'uv\n' > "$TEST_HOME/mise-local-tools"
  # From inside the project directory the real `mise ls --global` hides the
  # global row; `-C /` is what keeps the answer about the global file.
  assert_equals "installed" "$(cd "$TEST_HOME" && mise_global_state uv)" || return 1
  assert_equals "0" "$(grep -c '^mise [^-]' "$MOCK_LOG" || true)" "every mise call is pinned with -C /" || return 1
  cleanup_test_env
}

test_global_state_falls_back_to_the_config_file() {
  setup
  # A mise too old for --global exits non-zero on it.
  mock_command_script mise <<'EOF2'
[ "$1" = "-C" ] && shift 2
case "$*" in
  "ls --global"*) exit 1 ;;
  "where "*) grep -qx "$2" "$HOME/mise-installed" 2>/dev/null || exit 1 ;;
  *) : ;;
esac
exit 0
EOF2
  mkdir -p "$TEST_HOME/.config/mise"
  assert_equals "absent" "$(mise_global_state uv)" || return 1
  printf '[tools]\nuv = "latest"\n' > "$TEST_HOME/.config/mise/config.toml"
  assert_equals "requested" "$(mise_global_state uv)" || return 1
  printf 'uv\n' > "$TEST_HOME/mise-installed"
  assert_equals "installed" "$(mise_global_state uv)" || return 1
  cleanup_test_env
}

# MISE_GLOBAL_CONFIG_FILE names the global config outright and wins over
# MISE_CONFIG_DIR in mise itself, so mise_global_state's own fallback has to
# read that file: reading the wrong one answers "absent" for a tool that is
# requested, and mise_ensure_global then sends a pinned version through
# `use -g`, which rewrites it.
test_global_state_fallback_honours_mise_global_config_file() {
  setup
  mock_command_script mise <<'EOF2'
[ "$1" = "-C" ] && shift 2
case "$*" in
  "ls --global"*) exit 1 ;;
  "where "*) grep -qx "$2" "$HOME/mise-installed" 2>/dev/null || exit 1 ;;
  *) : ;;
esac
exit 0
EOF2
  # The config dir mise would use without the variable says nothing about uv.
  mkdir -p "$TEST_HOME/.config/mise" "$TEST_HOME/elsewhere"
  : > "$TEST_HOME/.config/mise/config.toml"
  printf '[tools]\nuv = "1.2.3"\n' > "$TEST_HOME/elsewhere/mise.toml"
  assert_equals "absent" "$(mise_global_state uv)" || return 1
  export MISE_GLOBAL_CONFIG_FILE="$TEST_HOME/elsewhere/mise.toml"
  assert_equals "requested" "$(mise_global_state uv)" || return 1
  # It also wins over MISE_CONFIG_DIR, as it does in mise.
  mkdir -p "$TEST_HOME/other-config"
  : > "$TEST_HOME/other-config/config.toml"
  export MISE_CONFIG_DIR="$TEST_HOME/other-config"
  assert_equals "requested" "$(mise_global_state uv)" || return 1
  printf 'uv\n' > "$TEST_HOME/mise-installed"
  assert_equals "installed" "$(mise_global_state uv)" || return 1
  unset MISE_GLOBAL_CONFIG_FILE MISE_CONFIG_DIR
  cleanup_test_env
}

test_ensure_global_installs_reinstalls_or_skips() {
  setup
  local out
  out="$(mise_ensure_global uv latest)"
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / use -g uv@latest" || return 1
  : > "$MOCK_LOG"
  out="$(mise_ensure_global uv latest)"
  assert_contains "$out" "Already installed through mise: uv" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  # Requested but gone from disk: `mise install` honours the pin, `use -g`
  # would rewrite it.
  rm -f "$TEST_HOME/mise-installed"
  : > "$MOCK_LOG"
  out="$(mise_ensure_global uv latest)"
  assert_contains "$out" "uv is requested by the global mise config but not installed" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install uv" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  cleanup_test_env
}

test_ensure_global_dry_run_only_prints() {
  setup
  local out
  out="$(DRY_RUN=true dev_env_install go)"
  assert_contains "$out" "[DRY-RUN] Would execute: mise -C / use -g go@latest" || return 1
  assert_not_contains "$out" "go is ready" || return 1
  [[ ! -e "$TEST_HOME/mise-tools" ]] || { echo "dry run must not call mise use"; return 1; }
  state_done check dev-env-go && { echo "dry run must not mark the dev env ready"; return 1; }
  cleanup_test_env
}

test_ensure_global_warns_and_fails_when_mise_cannot_install() {
  setup
  mock_command mise 1 ""
  local rc=0 out
  out="$(mise_ensure_global uv latest 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Could not install uv through mise." || return 1
  cleanup_test_env
}

test_wrapper_installs_on_first_call_and_execs_after() {
  setup
  mise_wrapper_write ai-claude "Claude Code" claude claude >/dev/null
  local w="$TEST_HOME/.local/bin/claude" out
  [[ -x "$w" ]] || { echo "wrapper must be executable"; return 1; }
  assert_equals "$TEEUP_MISE_WRAPPER_MARKER" "$(sed -n 2p "$w")" || return 1
  out="$("$w" --version)"
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / use -g --quiet claude" || return 1
  assert_equals "mise-x:claude:claude --version" "$out" || return 1
  : > "$MOCK_LOG"
  out="$("$w" chat "hello there")"
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  assert_equals "mise-x:claude:claude chat hello there" "$out" || return 1
  # `mise x` is the one unpinned call: the command must run in the caller's
  # directory, not in /.
  assert_contains "$(cat "$MOCK_LOG")" "mise x claude -- claude chat hello there" || return 1
  cleanup_test_env
}

# A tool the global config already requests, but that is not on disk (a wiped
# MISE_DATA_DIR, an interrupted install): the wrapper must install it with
# `mise install`, which honours the version pinned there, and must not call
# `use -g`, which would rewrite the request and drop the pin.
test_wrapper_installs_a_requested_tool_without_rewriting_the_pin() {
  setup
  printf 'claude\n' > "$TEST_HOME/mise-tools"
  : > "$TEST_HOME/mise-installed"
  mise_wrapper_write ai-claude "Claude Code" claude claude >/dev/null
  local out
  out="$("$TEST_HOME/.local/bin/claude" --version)"
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install claude" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  assert_equals "mise-x:claude:claude --version" "$out" || return 1
  # The request is still the single line it was: nothing rewrote it.
  assert_equals "claude" "$(cat "$TEST_HOME/mise-tools")" || return 1
  cleanup_test_env
}

test_wrapper_prints_progress_to_stderr_and_logs_the_install() {
  setup
  mise_wrapper_write ai-claude "Claude Code" claude claude >/dev/null
  local wrapper="$TEST_HOME/.local/bin/claude"
  local log="$TEST_HOME/.local/state/teeup/logs/lazy.log" out err
  out="$("$wrapper" --version 2>"$TEST_HOME/err")"
  err="$(cat "$TEST_HOME/err")"
  assert_contains "$err" "Installing Claude Code through mise (first run, can take a minute)..." || return 1
  assert_equals "mise-x:claude:claude --version" "$out" || return 1
  assert_file_exists "$log" || return 1
  assert_contains "$(cat "$log")" "Installing Claude Code through mise (first run, can take a minute)..." || return 1
  assert_contains "$(cat "$log")" "Installed Claude Code through mise." || return 1
  assert_equals "1" "$(grep -c 'Installing Claude Code through mise' "$log" || true)" || return 1

  : > "$TEST_HOME/err"
  "$wrapper" --version >/dev/null 2>"$TEST_HOME/err"
  assert_equals "" "$(cat "$TEST_HOME/err")" "an installed tool needs no first-run line" || return 1
  assert_equals "1" "$(grep -c 'Installing Claude Code through mise' "$log" || true)" || return 1
  cleanup_test_env
}

# I3: readiness must probe the log file itself, not just its directory. A
# pre-existing read-only lazy.log has a writable parent, so `mkdir -p` alone
# says "ready" and the later `tee -a`/`>>` then leaks bash's raw permission
# error instead of teeup's own warning -- and the install must still finish.
test_wrapper_warns_once_when_the_lazy_log_is_read_only() {
  setup
  mise_wrapper_write ai-claude "Claude Code" claude claude >/dev/null
  local wrapper="$TEST_HOME/.local/bin/claude"
  local log="$TEST_HOME/.local/state/teeup/logs/lazy.log" out err
  mkdir -p "$(dirname "$log")"
  : > "$log"
  chmod 0444 "$log"
  out="$("$wrapper" --version 2>"$TEST_HOME/err")"
  err="$(cat "$TEST_HOME/err")"
  chmod 0644 "$log"
  assert_equals "mise-x:claude:claude --version" "$out" "install must still succeed" || return 1
  assert_contains "$err" "Could not write the lazy install log: $log" || return 1
  assert_not_contains "$err" "Permission denied" "teeup's own warning must replace the raw error" || return 1
  assert_equals "" "$(cat "$log")" "the read-only log must stay untouched" || return 1
  cleanup_test_env
}

test_wrapper_dry_run_creates_no_lazy_log() {
  setup
  mise_wrapper_write ai-claude "Claude Code" claude claude >/dev/null
  local log="$TEST_HOME/.local/state/teeup/logs/lazy.log"
  DRY_RUN=true "$TEST_HOME/.local/bin/claude" --version >/dev/null 2>&1
  [[ ! -e "$log" ]] || { echo "wrapper dry run created $log"; return 1; }
  [[ ! -d "${log%/*}" ]] || { echo "wrapper dry run created the logs directory"; return 1; }
  cleanup_test_env
}

# When the wrapper runs as the command of an outer run_logged, TEEUP_RUN_LOG_CAPTURED=true
# is already inherited and that outer tee already captures this process's
# stdout and stderr. The wrapper must not also append or tee to
# TEEUP_LOG_FILE itself, matching the same rule Task 1 enforces for nested
# run_logged calls -- otherwise the transcript is duplicated.
test_wrapper_skips_its_own_log_under_an_outer_run_logged() {
  setup
  mise_wrapper_write ai-claude "Claude Code" claude claude >/dev/null
  mise_wrapper_write ai-codex "Codex" codex codex >/dev/null
  local captured_log="$TEST_HOME/captured.log"
  local default_log="$TEST_HOME/.local/state/teeup/logs/lazy.log"
  local out err
  out="$(TEEUP_RUN_LOG_CAPTURED=true TEEUP_LOG_FILE="$captured_log" "$TEST_HOME/.local/bin/claude" --version 2>"$TEST_HOME/err")"
  err="$(cat "$TEST_HOME/err")"
  assert_contains "$err" "Installing Claude Code through mise (first run, can take a minute)..." || return 1
  assert_equals "mise-x:claude:claude --version" "$out" || return 1
  [[ ! -e "$captured_log" ]] || { echo "a captured wrapper must not create its own log file"; return 1; }

  # Without TEEUP_RUN_LOG_CAPTURED (a direct call, or the outermost one) the
  # wrapper still owns its own transcript.
  out="$("$TEST_HOME/.local/bin/codex" --version)"
  assert_equals "mise-x:codex:codex --version" "$out" || return 1
  assert_file_exists "$default_log" || return 1
  assert_contains "$(cat "$default_log")" "Installing Codex through mise (first run, can take a minute)..." || return 1
  assert_contains "$(cat "$default_log")" "Installed Codex through mise." || return 1
  cleanup_test_env
}

test_wrapper_retries_an_interrupted_global_request() {
  setup
  mock_command_script mise <<'EOF2'
[ "$1" = "-C" ] && shift 2
case "$*" in
  "ls --global"*)
    [ -f "$HOME/mise-requested" ] && printf 'claude latest (missing) ~/.config/mise/config.toml latest\n'
    ;;
  "where "*) [ -f "$HOME/mise-installed" ] || exit 1 ;;
  "use "*)
    : > "$HOME/mise-requested"
    echo "download started, then interrupted"
    exit 130
    ;;
  "install claude")
    : > "$HOME/mise-installed"
    echo "download resumed"
    ;;
  "x claude -- claude --version") echo "claude-ready" ;;
  *) : ;;
esac
exit 0
EOF2
  mise_wrapper_write ai-claude "Claude Code" claude claude >/dev/null
  local wrapper="$TEST_HOME/.local/bin/claude" log="$TEST_HOME/.local/state/teeup/logs/lazy.log"
  local rc=0 out
  out="$("$wrapper" --version 2>&1)" || rc=$?
  assert_equals "130" "$rc" "the interrupted mise status must survive tee" || return 1
  assert_contains "$out" "Installing Claude Code through mise" || return 1
  assert_contains "$out" "download started, then interrupted" || return 1
  [[ ! -e "$TEST_HOME/mise-installed" ]] || { echo "the failed attempt claimed an install"; return 1; }
  assert_file_exists "$TEST_HOME/mise-requested" || return 1

  : > "$MOCK_LOG"
  out="$("$wrapper" --version 2>&1)"
  assert_contains "$out" "download resumed" || return 1
  assert_contains "$out" "claude-ready" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install claude" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  assert_contains "$(cat "$log")" "Install failed for Claude Code through mise (exit 130)." || return 1
  assert_contains "$(cat "$log")" "Installed Claude Code through mise." || return 1
  cleanup_test_env
}

test_wrapper_remove_deletes_only_a_teeup_wrapper() {
  setup
  mise_wrapper_write ai-codex "Codex" codex codex >/dev/null
  local wrapper="$TEST_HOME/.local/bin/codex" out
  out="$(mise_wrapper_remove ai-codex codex)"
  assert_contains "$out" "Removed the mise wrapper: codex" || return 1
  [[ ! -e "$wrapper" ]] || { echo "teeup wrapper remains"; return 1; }

  printf '#!/bin/sh\necho mine\n' > "$wrapper"
  out="$(mise_wrapper_remove ai-codex codex 2>&1)"
  assert_contains "$out" "Keeping $wrapper: it was not written by teeup" || return 1
  assert_file_exists "$wrapper" || return 1
  cleanup_test_env
}

test_wrapper_remove_dry_run_claims_no_removal() {
  setup
  mise_wrapper_write ai-codex "Codex" codex codex >/dev/null
  local wrapper="$TEST_HOME/.local/bin/codex" out
  out="$(DRY_RUN=true mise_wrapper_remove ai-codex codex 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: rm -f $wrapper" || return 1
  assert_not_contains "$out" "Removed the mise wrapper" || return 1
  assert_file_exists "$wrapper" || return 1
  cleanup_test_env
}

# The wrapper is teeup's own "install on first call", so a dry run previews
# the install and downloads nothing -- the same contract teeup lazy-run has.
test_wrapper_run_under_dry_run_installs_nothing() {
  setup
  mise_wrapper_write ai-claude "Claude Code" claude claude >/dev/null
  : > "$MOCK_LOG"
  local rc=0 out
  out="$(DRY_RUN=true "$TEST_HOME/.local/bin/claude" --version 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "[DRY-RUN] Would install claude through mise" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "install claude" || return 1
  [[ ! -e "$TEST_HOME/mise-tools" ]] || { echo "dry run must not record a request"; return 1; }
  # Once the tool is really installed there is no mutation left to withhold,
  # so the command itself still runs under DRY_RUN.
  printf 'claude\n' > "$TEST_HOME/mise-installed"
  out="$(DRY_RUN=true "$TEST_HOME/.local/bin/claude" --version)"
  assert_equals "mise-x:claude:claude --version" "$out" || return 1
  cleanup_test_env
}

# A mise too old for `ls --global` (it exits non-zero) must not make the
# wrapper read "not requested": the global config file answers instead, so a
# version the user pinned by hand is installed with `install` and survives.
test_wrapper_reads_the_config_when_ls_global_fails() {
  setup
  mkdir -p "$TEST_HOME/.config/mise"
  printf 'claude = "1.2.3"\n' > "$TEST_HOME/.config/mise/config.toml"
  mock_command_script mise <<'EOF2'
[ "$1" = "-C" ] && shift 2
case "$*" in
  "ls --global"*) exit 2 ;;
  "where "*) exit 1 ;;
  "install "*) printf '%s\n' "$2" >> "$HOME/mise-installed" ;;
  "x "*)
    shift
    tools=""
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do tools="$tools${tools:+,}$1"; shift; done
    shift
    echo "mise-x:$tools:$*"
    ;;
  *) : ;;
esac
exit 0
EOF2
  mise_wrapper_write ai-claude "Claude Code" claude claude >/dev/null
  local out
  out="$("$TEST_HOME/.local/bin/claude" --version)"
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install claude" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  assert_equals "mise-x:claude:claude --version" "$out" || return 1
  assert_equals 'claude = "1.2.3"' "$(cat "$TEST_HOME/.config/mise/config.toml")" || return 1
  cleanup_test_env
}

# MISE_GLOBAL_CONFIG_FILE names the global config outright and wins over
# MISE_CONFIG_DIR in mise itself, so the same fallback must read that file.
test_wrapper_fallback_honours_mise_global_config_file() {
  setup
  mkdir -p "$TEST_HOME/elsewhere"
  printf 'claude = "1.2.3"\n' > "$TEST_HOME/elsewhere/mise.toml"
  export MISE_GLOBAL_CONFIG_FILE="$TEST_HOME/elsewhere/mise.toml"
  mock_command_script mise <<'EOF2'
[ "$1" = "-C" ] && shift 2
case "$*" in
  "ls --global"*) exit 2 ;;
  "where "*) exit 1 ;;
  "x "*) echo "mise-x-ran" ;;
  *) : ;;
esac
exit 0
EOF2
  mise_wrapper_write ai-claude "Claude Code" claude claude >/dev/null
  "$TEST_HOME/.local/bin/claude" --version >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install claude" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  unset MISE_GLOBAL_CONFIG_FILE TEEUP_TEST_MISSING
  cleanup_test_env
}

# The wrapper's own dependency: mise itself. A missing mise is the shim
# contract's 127 with a command to run, not a raw "mise: command not found".
test_wrapper_without_mise_exits_127_with_a_hint() {
  setup
  mise_wrapper_write ai-claude "Claude Code" claude claude >/dev/null
  local rc=0 out
  # The wrapper is a standalone script, so it does not consult
  # TEEUP_TEST_MISSING the way teeup's own `have` does. An empty PATH is what
  # a machine without mise looks like to it -- and it has to be empty, not
  # just missing the mock: the host running these tests may well have a real
  # mise of its own, which is exactly what this wrapper would find.
  mkdir -p "$TEST_HOME/empty-bin"
  out="$(PATH="$TEST_HOME/empty-bin" "$TEST_HOME/.local/bin/claude" --version 2>&1)" || rc=$?
  assert_equals "127" "$rc" || return 1
  assert_contains "$out" "Run: teeup install mise" || return 1
  cleanup_test_env
}

test_wrapper_exports_release_age_zero() {
  setup
  mock_command_script mise <<'EOF2'
echo "AGE=${MISE_MINIMUM_RELEASE_AGE:-unset}" >> "$MOCK_LOG"
[ "$1" = "-C" ] && shift 2
case "$*" in
  "where "*) exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  mise_wrapper_write ai-codex "Codex" codex codex >/dev/null
  "$TEST_HOME/.local/bin/codex" >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "AGE=0" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "AGE=unset" || return 1
  cleanup_test_env
}

test_wrapper_installs_a_runtime_first_and_loads_it() {
  setup
  mise_wrapper_write ai-gemini "Gemini CLI" gemini gemini node >/dev/null
  local out
  out="$("$TEST_HOME/.local/bin/gemini" chat)"
  assert_equals "mise-x:node,gemini:gemini chat" "$out" || return 1
  # node is installed before gemini, both through the pinned `use -g`.
  assert_equals "node|gemini" "$(grep 'use -g' "$MOCK_LOG" | sed 's/.* //' | tr '\n' '|' | sed 's/|$//')" || return 1
  cleanup_test_env
}

# M3: a wrapper with more than one tool must preview every missing tool on
# one line, not just the first it happens to check.
test_wrapper_dry_run_previews_every_missing_tool() {
  setup
  mise_wrapper_write ai-gemini "Gemini CLI" gemini gemini node >/dev/null
  local out
  out="$(DRY_RUN=true "$TEST_HOME/.local/bin/gemini" chat 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would install node gemini through mise, then run gemini." || return 1
  [[ ! -e "$TEST_HOME/mise-tools" ]] || { echo "dry run must not install anything"; return 1; }
  cleanup_test_env
}

test_wrapper_leaves_a_foreign_command_alone() {
  setup
  mkdir -p "$TEST_HOME/.local/bin" "$TEST_HOME/.local/share/claude/versions"
  # Claude Code's native installer: ~/.local/bin/claude is its symlink.
  printf '#!/bin/sh\necho native\n' > "$TEST_HOME/.local/share/claude/versions/2.1.0"
  ln -s "$TEST_HOME/.local/share/claude/versions/2.1.0" "$TEST_HOME/.local/bin/claude"
  printf '#!/bin/sh\necho mine\n' > "$TEST_HOME/.local/bin/codex"
  local out
  out="$(mise_wrapper_write ai-claude "Claude Code" claude claude 2>&1)"
  assert_contains "$out" "Keeping $TEST_HOME/.local/bin/claude: it was not written by teeup" || return 1
  [[ -L "$TEST_HOME/.local/bin/claude" ]] || { echo "the native symlink must survive"; return 1; }
  out="$(mise_wrapper_write ai-codex "Codex" codex codex 2>&1)"
  assert_contains "$out" "Keeping $TEST_HOME/.local/bin/codex" || return 1
  assert_contains "$(cat "$TEST_HOME/.local/bin/codex")" "echo mine" || return 1
  # A wrapper teeup wrote is teeup's to rewrite.
  mise_wrapper_write ai-gemini "Gemini CLI" gemini gemini >/dev/null
  out="$(mise_wrapper_write ai-gemini "Gemini CLI" gemini gemini node)"
  assert_contains "$out" "Wrote $TEST_HOME/.local/bin/gemini" || return 1
  assert_contains "$(cat "$TEST_HOME/.local/bin/gemini")" "exec mise x node gemini -- gemini" || return 1
  cleanup_test_env
}

test_wrapper_rejects_a_name_that_is_not_plain() {
  setup
  local rc=0 out
  out="$(mise_wrapper_write ai-claude "Claude Code" ../evil claude 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "'../evil' is not a plain capability, command or tool name" || return 1
  rc=0
  out="$(mise_wrapper_write ai-test "Test CLI" ok 'x;y' 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  [[ ! -e "$TEST_HOME/.local/bin/ok" ]] || { echo "nothing may be written"; return 1; }
  cleanup_test_env
}

test_wrapper_write_is_idempotent_and_dry_run_safe() {
  setup
  mise_wrapper_write ai-gemini "Gemini CLI" gemini gemini >/dev/null
  local out
  out="$(mise_wrapper_write ai-gemini "Gemini CLI" gemini gemini)"
  assert_contains "$out" "Already current: $TEST_HOME/.local/bin/gemini" || return 1
  out="$(DRY_RUN=true mise_wrapper_write ai-opencode "OpenCode" opencode opencode)"
  assert_contains "$out" "Would write $TEST_HOME/.local/bin/opencode" || return 1
  [[ ! -e "$TEST_HOME/.local/bin/opencode" ]] || { echo "dry run wrote a wrapper"; return 1; }
  cleanup_test_env
}

test_dev_env_python_brings_uv() {
  setup
  local out
  out="$(dev_env_install python)"
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / use -g python@latest" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / use -g uv@latest" || return 1
  assert_contains "$out" "python is ready" || return 1
  state_done check dev-env-python || { echo "dev-env-python must be marked"; return 1; }
  assert_equals "python" "$(dev_env_installed)" || return 1
  cleanup_test_env
}

test_dev_env_each_language_uses_mise() {
  setup
  local l
  for l in node java ruby rust go; do
    dev_env_install "$l" >/dev/null
    assert_contains "$(cat "$MOCK_LOG")" "mise -C / use -g $l@latest" || return 1
  done
  assert_equals "node java ruby rust go" "$(dev_env_installed | tr '\n' ' ' | sed 's/ $//')" || return 1
  cleanup_test_env
}

test_dev_env_rejects_an_unknown_language_and_needs_mise() {
  setup
  local rc=0 out
  out="$(dev_env_install perl 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Usage: teeup install dev-env <python|node|java|ruby|rust|go>" || return 1
  rc=0
  out="$(TEEUP_TEST_MISSING=mise dev_env_install go 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "mise is not installed; run: teeup install mise" || return 1
  cleanup_test_env
}

test_dev_env_leaves_a_pinned_runtime_alone() {
  setup
  # node = "22" already in the global config and installed: nothing to do,
  # and above all no `use -g node@latest` that would rewrite the pin.
  printf 'node\n' > "$TEST_HOME/mise-tools"
  printf 'node\n' > "$TEST_HOME/mise-installed"
  local out
  out="$(dev_env_install node)"
  assert_contains "$out" "Already installed through mise: node" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  cleanup_test_env
}

# M4: "the next prompt in this shell has it (mise activate)" is only true
# once the zsh capability has actually wired up `mise activate`; without it
# dev_env_install must not claim that, and the java-specific hint must not
# name `javav`, a zsh function that would not exist either.
test_dev_env_messages_do_not_claim_zsh_without_it() {
  setup
  local out
  out="$(dev_env_install go)"
  assert_contains "$out" "go is ready through mise." || return 1
  assert_not_contains "$out" "mise activate" || return 1
  out="$(dev_env_install java)"
  assert_contains "$out" "Switch Java per shell with: mise use java@<spec>" || return 1
  assert_not_contains "$out" "javav 21" || return 1
  cleanup_test_env
}

test_dev_env_messages_mention_javav_and_mise_activate_once_zsh_is_installed() {
  setup
  state_done mark "cap-zsh"
  local out
  out="$(dev_env_install go)"
  assert_contains "$out" "go is ready: the next prompt in this shell has it (mise activate)" || return 1
  out="$(dev_env_install java)"
  assert_contains "$out" "Switch Java per shell with: javav 21 (Corretto 21)" || return 1
  cleanup_test_env
}

test_upgrade_covers_the_global_config_and_tolerates_no_mise() {
  setup
  mock_command mise 0 ""
  mise_upgrade
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / upgrade" || return 1
  local out
  out="$(DRY_RUN=true mise_upgrade)"
  assert_contains "$out" "[DRY-RUN] Would execute: mise -C / upgrade" || return 1
  out="$(TEEUP_TEST_MISSING="mise" mise_upgrade)"
  assert_contains "$out" "mise is not installed here; skipping the mise upgrade." || return 1
  cleanup_test_env
}

echo "lib/mise.sh"
run_test "global state distinguishes the three cases" test_global_state_distinguishes_the_three_cases
run_test "tool unuse drops a requested tool" test_tool_unuse_drops_a_requested_tool
run_test "tool unuse leaves an unrequested tool alone" test_tool_unuse_leaves_an_unrequested_tool_alone
run_test "tool unuse changes nothing in a dry run" test_tool_unuse_changes_nothing_in_a_dry_run
run_test "tool unuse reports a failed unuse" test_tool_unuse_reports_a_failed_unuse
run_test "tool unuse fails without mise while the config requests the tool" test_tool_unuse_fails_without_mise_while_the_config_requests_the_tool
run_test "tool unuse without mise passes a tool nothing requests" test_tool_unuse_without_mise_passes_a_tool_nothing_requests
run_test "tool unuse without mise still previews in a dry run" test_tool_unuse_without_mise_still_previews_in_a_dry_run
run_test "global state is not fooled by a project config" test_global_state_is_not_fooled_by_a_project_config
run_test "global state falls back to the config file" test_global_state_falls_back_to_the_config_file
run_test "global state fallback honours MISE_GLOBAL_CONFIG_FILE" test_global_state_fallback_honours_mise_global_config_file
run_test "ensure_global installs, reinstalls or skips" test_ensure_global_installs_reinstalls_or_skips
run_test "dev env dry run only previews" test_ensure_global_dry_run_only_prints
run_test "ensure_global warns and fails when mise cannot install" test_ensure_global_warns_and_fails_when_mise_cannot_install
run_test "wrapper installs on first call and execs after" test_wrapper_installs_on_first_call_and_execs_after
run_test "wrapper installs a requested tool without rewriting the pin" test_wrapper_installs_a_requested_tool_without_rewriting_the_pin
run_test "wrapper prints progress and logs the install" test_wrapper_prints_progress_to_stderr_and_logs_the_install
run_test "wrapper warns once when the lazy log is read-only" test_wrapper_warns_once_when_the_lazy_log_is_read_only
run_test "wrapper dry run creates no lazy log" test_wrapper_dry_run_creates_no_lazy_log
run_test "wrapper skips its own log under an outer run_logged" test_wrapper_skips_its_own_log_under_an_outer_run_logged
run_test "wrapper retries an interrupted global request" test_wrapper_retries_an_interrupted_global_request
run_test "wrapper remove deletes only a teeup wrapper" test_wrapper_remove_deletes_only_a_teeup_wrapper
run_test "wrapper remove dry run claims no removal" test_wrapper_remove_dry_run_claims_no_removal
run_test "wrapper run under dry run installs nothing" test_wrapper_run_under_dry_run_installs_nothing
run_test "wrapper reads the config when ls --global fails" test_wrapper_reads_the_config_when_ls_global_fails
run_test "wrapper fallback honours MISE_GLOBAL_CONFIG_FILE" test_wrapper_fallback_honours_mise_global_config_file
run_test "wrapper without mise exits 127 with a hint" test_wrapper_without_mise_exits_127_with_a_hint
run_test "wrapper exports release age zero" test_wrapper_exports_release_age_zero
run_test "wrapper installs a runtime first and loads it" test_wrapper_installs_a_runtime_first_and_loads_it
run_test "wrapper dry run previews every missing tool" test_wrapper_dry_run_previews_every_missing_tool
run_test "wrapper leaves a foreign command alone" test_wrapper_leaves_a_foreign_command_alone
run_test "wrapper rejects a name that is not plain" test_wrapper_rejects_a_name_that_is_not_plain
run_test "wrapper write is idempotent and dry-run safe" test_wrapper_write_is_idempotent_and_dry_run_safe
run_test "dev-env python brings uv" test_dev_env_python_brings_uv
run_test "dev-env each language uses mise" test_dev_env_each_language_uses_mise
run_test "dev-env rejects an unknown language and needs mise" test_dev_env_rejects_an_unknown_language_and_needs_mise
run_test "dev-env leaves a pinned runtime alone" test_dev_env_leaves_a_pinned_runtime_alone
run_test "dev-env messages do not claim zsh without it" test_dev_env_messages_do_not_claim_zsh_without_it
run_test "dev-env messages mention javav and mise activate once zsh is installed" test_dev_env_messages_mention_javav_and_mise_activate_once_zsh_is_installed
run_test "upgrade covers the global config and tolerates no mise" test_upgrade_covers_the_global_config_and_tolerates_no_mise
print_summary
