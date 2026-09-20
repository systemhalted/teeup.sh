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
  mise_wrapper_write claude claude >/dev/null
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
  mise_wrapper_write claude claude >/dev/null
  local out
  out="$("$TEST_HOME/.local/bin/claude" --version)"
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install claude" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  assert_equals "mise-x:claude:claude --version" "$out" || return 1
  # The request is still the single line it was: nothing rewrote it.
  assert_equals "claude" "$(cat "$TEST_HOME/mise-tools")" || return 1
  cleanup_test_env
}

# The wrapper is teeup's own "install on first call", so a dry run previews
# the install and downloads nothing -- the same contract teeup lazy-run has.
test_wrapper_run_under_dry_run_installs_nothing() {
  setup
  mise_wrapper_write claude claude >/dev/null
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
  mise_wrapper_write claude claude >/dev/null
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
  mise_wrapper_write claude claude >/dev/null
  "$TEST_HOME/.local/bin/claude" --version >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install claude" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  unset MISE_GLOBAL_CONFIG_FILE
  cleanup_test_env
}

# The wrapper's own dependency: mise itself. A missing mise is the shim
# contract's 127 with a command to run, not a raw "mise: command not found".
test_wrapper_without_mise_exits_127_with_a_hint() {
  setup
  mise_wrapper_write claude claude >/dev/null
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
  mise_wrapper_write codex codex >/dev/null
  "$TEST_HOME/.local/bin/codex" >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "AGE=0" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "AGE=unset" || return 1
  cleanup_test_env
}

test_wrapper_installs_a_runtime_first_and_loads_it() {
  setup
  mise_wrapper_write gemini gemini node >/dev/null
  local out
  out="$("$TEST_HOME/.local/bin/gemini" chat)"
  assert_equals "mise-x:node,gemini:gemini chat" "$out" || return 1
  # node is installed before gemini, both through the pinned `use -g`.
  assert_equals "node|gemini" "$(grep 'use -g' "$MOCK_LOG" | sed 's/.* //' | tr '\n' '|' | sed 's/|$//')" || return 1
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
  out="$(mise_wrapper_write claude claude 2>&1)"
  assert_contains "$out" "Keeping $TEST_HOME/.local/bin/claude: it was not written by teeup" || return 1
  [[ -L "$TEST_HOME/.local/bin/claude" ]] || { echo "the native symlink must survive"; return 1; }
  out="$(mise_wrapper_write codex codex 2>&1)"
  assert_contains "$out" "Keeping $TEST_HOME/.local/bin/codex" || return 1
  assert_contains "$(cat "$TEST_HOME/.local/bin/codex")" "echo mine" || return 1
  # A wrapper teeup wrote is teeup's to rewrite.
  mise_wrapper_write gemini gemini >/dev/null
  out="$(mise_wrapper_write gemini gemini node)"
  assert_contains "$out" "Wrote $TEST_HOME/.local/bin/gemini" || return 1
  assert_contains "$(cat "$TEST_HOME/.local/bin/gemini")" "exec mise x node gemini -- gemini" || return 1
  cleanup_test_env
}

test_wrapper_rejects_a_name_that_is_not_plain() {
  setup
  local rc=0 out
  out="$(mise_wrapper_write ../evil claude 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "'../evil' is not a plain command or tool name" || return 1
  rc=0
  out="$(mise_wrapper_write ok 'x;y' 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  [[ ! -e "$TEST_HOME/.local/bin/ok" ]] || { echo "nothing may be written"; return 1; }
  cleanup_test_env
}

test_wrapper_write_is_idempotent_and_dry_run_safe() {
  setup
  mise_wrapper_write gemini gemini >/dev/null
  local out
  out="$(mise_wrapper_write gemini gemini)"
  assert_contains "$out" "Already current: $TEST_HOME/.local/bin/gemini" || return 1
  out="$(DRY_RUN=true mise_wrapper_write opencode opencode)"
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

echo "lib/mise.sh"
run_test "global state distinguishes the three cases" test_global_state_distinguishes_the_three_cases
run_test "global state is not fooled by a project config" test_global_state_is_not_fooled_by_a_project_config
run_test "global state falls back to the config file" test_global_state_falls_back_to_the_config_file
run_test "ensure_global installs, reinstalls or skips" test_ensure_global_installs_reinstalls_or_skips
run_test "dev env dry run only previews" test_ensure_global_dry_run_only_prints
run_test "ensure_global warns and fails when mise cannot install" test_ensure_global_warns_and_fails_when_mise_cannot_install
run_test "wrapper installs on first call and execs after" test_wrapper_installs_on_first_call_and_execs_after
run_test "wrapper installs a requested tool without rewriting the pin" test_wrapper_installs_a_requested_tool_without_rewriting_the_pin
run_test "wrapper run under dry run installs nothing" test_wrapper_run_under_dry_run_installs_nothing
run_test "wrapper reads the config when ls --global fails" test_wrapper_reads_the_config_when_ls_global_fails
run_test "wrapper fallback honours MISE_GLOBAL_CONFIG_FILE" test_wrapper_fallback_honours_mise_global_config_file
run_test "wrapper without mise exits 127 with a hint" test_wrapper_without_mise_exits_127_with_a_hint
run_test "wrapper exports release age zero" test_wrapper_exports_release_age_zero
run_test "wrapper installs a runtime first and loads it" test_wrapper_installs_a_runtime_first_and_loads_it
run_test "wrapper leaves a foreign command alone" test_wrapper_leaves_a_foreign_command_alone
run_test "wrapper rejects a name that is not plain" test_wrapper_rejects_a_name_that_is_not_plain
run_test "wrapper write is idempotent and dry-run safe" test_wrapper_write_is_idempotent_and_dry_run_safe
run_test "dev-env python brings uv" test_dev_env_python_brings_uv
run_test "dev-env each language uses mise" test_dev_env_each_language_uses_mise
run_test "dev-env rejects an unknown language and needs mise" test_dev_env_rejects_an_unknown_language_and_needs_mise
run_test "dev-env leaves a pinned runtime alone" test_dev_env_leaves_a_pinned_runtime_alone
print_summary
