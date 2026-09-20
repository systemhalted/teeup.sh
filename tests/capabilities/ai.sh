#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  # A mise that knows nothing is installed until `use -g` says so, and whose
  # `x` echoes the tools it would load and the command it would run.
  mock_command_script mise <<'EOF2'
[ "$1" = "-C" ] && shift 2
case "$*" in
  "ls --global"*) : ;;
  "where "*) grep -qx "$2" "$HOME/mise-installed" 2>/dev/null || exit 1 ;;
  "use "*)
    shift
    while [ $# -gt 0 ]; do case "$1" in -g|--quiet) shift ;; *) break ;; esac; done
    printf '%s\n' "${1%%@*}" >> "$HOME/mise-installed"
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
  # The last test drives the shim's install prompt through ui_confirm; keep
  # it away from gum (a host gum on the narrowed PATH would otherwise answer
  # for real and never print the line this test asserts on).
  export TEEUP_NO_GUM=1
  TEEUP="$TEEUP_PATH/bin/teeup"
  BIN="$TEST_HOME/.local/bin"
  SHIMS="$TEST_HOME/.local/state/teeup/shims"
}

test_install_downloads_nothing() {
  setup
  local out c
  out="$(DRY_RUN=true "$TEEUP" install ai 2>&1)"
  assert_contains "$out" "AI CLIs install on first call through mise; nothing to download now." || return 1
  # The requires= chain runs the mise capability (which asks mise about
  # pre-commit); none of the five CLIs is touched.
  for c in claude codex gemini copilot opencode; do
    assert_not_contains "$(cat "$MOCK_LOG")" "$c" || return 1
  done
  cleanup_test_env
}

test_configure_writes_the_five_wrappers() {
  setup
  DRY_RUN=false "$TEEUP" configure ai >/dev/null
  local c
  for c in claude codex copilot opencode; do
    assert_file_exists "$BIN/$c" || return 1
    [[ -x "$BIN/$c" ]] || { echo "$c wrapper must be executable"; return 1; }
    assert_contains "$(cat "$BIN/$c")" "for teeup_tool in $c; do" || return 1
    assert_contains "$(cat "$BIN/$c")" "exec mise x $c -- $c \"\$@\"" || return 1
  done
  # gemini is an npm package and runs on Node, so its wrapper brings node;
  # the mise tool is the registry's canonical gemini-cli.
  assert_contains "$(cat "$BIN/gemini")" "for teeup_tool in node gemini-cli; do" || return 1
  assert_contains "$(cat "$BIN/gemini")" "exec mise x node gemini-cli -- gemini \"\$@\"" || return 1
  cleanup_test_env
}

test_wrapper_installs_on_first_call_then_execs() {
  setup
  DRY_RUN=false "$TEEUP" configure ai >/dev/null
  local out
  out="$("$BIN/claude" --version)"
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / use -g --quiet claude" || return 1
  assert_equals "mise-x:claude:claude --version" "$out" || return 1
  : > "$MOCK_LOG"
  out="$("$BIN/claude" -p "say hi")"
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  assert_equals "mise-x:claude:claude -p say hi" "$out" || return 1
  cleanup_test_env
}

test_configure_keeps_a_native_claude() {
  setup
  mkdir -p "$BIN" "$TEST_HOME/.local/share/claude/versions"
  printf '#!/bin/sh\necho native\n' > "$TEST_HOME/.local/share/claude/versions/2.1.0"
  chmod +x "$TEST_HOME/.local/share/claude/versions/2.1.0"
  ln -s "$TEST_HOME/.local/share/claude/versions/2.1.0" "$BIN/claude"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ai 2>&1)"
  assert_contains "$out" "Keeping $BIN/claude: it was not written by teeup" || return 1
  assert_equals "native" "$("$BIN/claude")" || return 1
  assert_file_exists "$BIN/codex" || return 1
  # I4: the summary must name only the wrappers teeup actually wrote, not
  # claude, whose native installer symlink teeup left alone.
  assert_contains "$out" "The first call of codex, gemini, copilot or opencode installs it through mise." || return 1
  assert_not_contains "$out" "The first call of claude, codex" || return 1
  cleanup_test_env
}

# I4, the exact scenario in the adversarial review's probe_localbin.sh: three
# of the five wrappers are refused (a foreign symlink, a foreign plain file
# and a dangling symlink), and the summary line must name only the two teeup
# actually wrote.
test_configure_summary_names_only_the_wrappers_it_wrote() {
  setup
  mkdir -p "$BIN" "$TEST_HOME/.local/share/claude/versions"
  printf '#!/bin/sh\necho native\n' > "$TEST_HOME/.local/share/claude/versions/2.1.0"
  chmod +x "$TEST_HOME/.local/share/claude/versions/2.1.0"
  ln -s "$TEST_HOME/.local/share/claude/versions/2.1.0" "$BIN/claude"
  printf '#!/bin/sh\necho mine\n' > "$BIN/codex"
  ln -s "$TEST_HOME/nowhere" "$BIN/gemini"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ai 2>&1)"
  assert_contains "$out" "Keeping $BIN/claude: it was not written by teeup" || return 1
  assert_contains "$out" "Keeping $BIN/codex: it was not written by teeup" || return 1
  assert_contains "$out" "Keeping $BIN/gemini: it was not written by teeup" || return 1
  assert_file_exists "$BIN/copilot" || return 1
  assert_file_exists "$BIN/opencode" || return 1
  assert_contains "$out" "The first call of copilot or opencode installs it through mise." || return 1
  assert_not_contains "$out" "claude, codex, gemini" || return 1
  cleanup_test_env
}

test_configure_is_idempotent_and_dry_run_safe() {
  setup
  DRY_RUN=false "$TEEUP" configure ai >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ai)"
  assert_contains "$out" "Already current: $BIN/opencode" || return 1
  cleanup_test_env
  setup
  out="$(DRY_RUN=true "$TEEUP" configure ai)"
  assert_contains "$out" "Would write $BIN/claude" || return 1
  [[ ! -e "$BIN/claude" ]] || { echo "dry run wrote a wrapper"; return 1; }
  cleanup_test_env
}

test_wrappers_survive_a_home_with_spaces() {
  setup
  export HOME="$TEST_HOME/home with spaces"
  mkdir -p "$HOME"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_STATE_HOME="$HOME/.local/state"
  DRY_RUN=false "$TEEUP" configure ai >/dev/null
  local out
  out="$("$HOME/.local/bin/gemini" chat)"
  assert_equals "mise-x:node,gemini-cli:gemini chat" "$out" || return 1
  cleanup_test_env
}

# The freshly-bootstrapped-Mac path: nobody has run `teeup install ai` or
# `teeup configure ai` yet, and `claude` still works, through the shim
# provides= now puts in place.
test_the_claude_shim_installs_ai_then_execs_through_mise() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  assert_file_exists "$SHIMS/claude" || return 1
  assert_contains "$(cat "$SHIMS/claude")" 'lazy-run ai claude "$@"' || return 1
  export PATH="$MOCK_BIN:/usr/bin:/bin:$BIN:$SHIMS"
  # A gum binary on PATH (MOCK_BIN, ahead of the shims, the way a real
  # /opt/homebrew/bin/gum would be) must not be touched: TEEUP_NO_GUM=1
  # (set in setup) short-circuits _ui_gum before it ever checks `have gum`,
  # so the plain read fallback below is what answers the prompt even on a
  # machine that has gum installed.
  mock_command_script gum <<'EOF2'
echo "gum must not run when TEEUP_NO_GUM=1" >&2
exit 1
EOF2
  local out
  out="$(printf 'y\n' | TEEUP_TEST_TTY=yes DRY_RUN=false "$SHIMS/claude" --version 2>&1)"
  assert_contains "$out" "claude is provided by capability ai. Install now?" || return 1
  assert_contains "$out" "mise-x:claude:claude --version" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "gum " "gum ran even though TEEUP_NO_GUM=1" || return 1
  assert_file_exists "$BIN/claude" || return 1
  "$TEEUP" has ai || { echo "ai must be marked installed"; return 1; }
  cleanup_test_env
}

# D-1/R-7.1: `teeup remove ai` used to report success while deleting nothing
# -- packages= and casks= are both empty, so the generic uninstall loop had
# nothing to do. capabilities/ai/remove now deletes the wrappers configure
# wrote, and only those: a foreign claude symlink (Claude Code's own
# installer, say) is left exactly as test_configure_keeps_a_native_claude
# leaves it.
test_remove_deletes_only_the_wrappers_teeup_wrote() {
  setup
  mkdir -p "$BIN" "$TEST_HOME/.local/share/claude/versions"
  printf '#!/bin/sh\necho native\n' > "$TEST_HOME/.local/share/claude/versions/2.1.0"
  chmod +x "$TEST_HOME/.local/share/claude/versions/2.1.0"
  ln -s "$TEST_HOME/.local/share/claude/versions/2.1.0" "$BIN/claude"
  DRY_RUN=false "$TEEUP" configure ai >/dev/null
  source "$TEEUP_PATH/lib/all.sh"
  local out c
  out="$(DRY_RUN=false cap_run ai remove 2>&1)"
  assert_contains "$out" "Keeping $BIN/claude: it was not written by teeup" || return 1
  assert_contains "$out" "Removed the mise wrapper(s): codex gemini copilot opencode" || return 1
  assert_equals "native" "$("$BIN/claude")" "the foreign claude symlink must survive" || return 1
  for c in codex gemini copilot opencode; do
    [[ ! -e "$BIN/$c" ]] || { echo "$c wrapper must be gone"; return 1; }
  done
  cleanup_test_env
}

test_remove_dry_run_deletes_no_wrapper() {
  setup
  DRY_RUN=false "$TEEUP" configure ai >/dev/null
  source "$TEEUP_PATH/lib/all.sh"
  local out
  out="$(DRY_RUN=true cap_run ai remove 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: rm -f $BIN/claude" || return 1
  assert_not_contains "$out" "Removed the mise wrapper(s)" || return 1
  assert_file_exists "$BIN/claude" || return 1
  cleanup_test_env
}

test_remove_without_any_wrapper_is_quiet() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  local out
  out="$(DRY_RUN=false cap_run ai remove 2>&1)"
  assert_contains "$out" "No teeup-written wrappers were found in ~/.local/bin." || return 1
  cleanup_test_env
}

echo "capabilities/ai"
run_test "install downloads nothing" test_install_downloads_nothing
run_test "configure writes the five wrappers" test_configure_writes_the_five_wrappers
run_test "wrapper installs on first call then execs" test_wrapper_installs_on_first_call_then_execs
run_test "configure keeps a native claude" test_configure_keeps_a_native_claude
run_test "configure summary names only the wrappers it wrote" test_configure_summary_names_only_the_wrappers_it_wrote
run_test "configure is idempotent and dry-run safe" test_configure_is_idempotent_and_dry_run_safe
run_test "wrappers survive a home with spaces" test_wrappers_survive_a_home_with_spaces
run_test "the claude shim installs ai then execs through mise" test_the_claude_shim_installs_ai_then_execs_through_mise
run_test "remove deletes only the wrappers teeup wrote" test_remove_deletes_only_the_wrappers_teeup_wrote
run_test "remove dry run deletes no wrapper" test_remove_dry_run_deletes_no_wrapper
run_test "remove without any wrapper is quiet" test_remove_without_any_wrapper_is_quiet
print_summary
