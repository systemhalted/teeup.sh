#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

AI_LEAVES="ai-claude ai-codex ai-gemini ai-copilot ai-opencode"
AI_COMMANDS="claude codex gemini copilot opencode"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
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
  export TEEUP_NO_GUM=1
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  TEEUP="$TEEUP_PATH/bin/teeup"
  BIN="$TEST_HOME/.local/bin"
  SHIMS="$TEST_HOME/.local/state/teeup/shims"
  mkdir -p "$TEST_HOME/.local/state/teeup/done"
  # The real-Mac case is a completed bootstrap. Marking mise done makes this
  # suite fail if lazy-run replays its requirement instead of trusting state.
  # xcode-clt and package-manager are mise's own requires= chain: a completed
  # bootstrap has them done too, or cmd_install's per-capability skip check
  # (bin/teeup) walks past mise straight into reinstalling them (brew update
  # included) on every lazy call this suite makes.
  : > "$TEST_HOME/.local/state/teeup/done/cap-mise"
  : > "$TEST_HOME/.local/state/teeup/done/cap-package-manager"
  : > "$TEST_HOME/.local/state/teeup/done/cap-xcode-clt"
}

test_each_command_has_one_leaf_provider() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  local pair leaf command
  for pair in ai-claude:claude ai-codex:codex ai-gemini:gemini ai-copilot:copilot ai-opencode:opencode; do
    leaf="${pair%%:*}"
    command="${pair#*:}"
    assert_equals "$leaf" "$(lazy_provider "$command")" || return 1
    assert_equals "$command" "$(cap_meta_get "$leaf" provides)" || return 1
    assert_equals "mise" "$(cap_meta_get "$leaf" requires)" || return 1
  done
  assert_equals "" "$(cap_meta_get ai provides)" || return 1
  assert_equals "$AI_LEAVES" "$(cap_meta_get ai requires)" || return 1
  cleanup_test_env
}

test_runtime_shims_route_to_individual_leaves() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local pair leaf command
  for pair in ai-claude:claude ai-codex:codex ai-gemini:gemini ai-copilot:copilot ai-opencode:opencode; do
    leaf="${pair%%:*}"
    command="${pair#*:}"
    assert_file_exists "$SHIMS/$command" || return 1
    assert_contains "$(cat "$SHIMS/$command")" "lazy-run $leaf $command \"\$@\"" || return 1
  done
  cleanup_test_env
}

test_claude_shim_sets_up_only_claude() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  export PATH="$MOCK_BIN:/usr/bin:/bin:$BIN:$SHIMS"
  local out command leaf
  out="$(printf 'y\n' | TEEUP_TEST_TTY=yes DRY_RUN=false "$SHIMS/claude" --version 2>&1)"
  assert_contains "$out" "claude is provided by capability ai-claude. Install now?" || return 1
  assert_contains "$out" "Installing Claude Code through mise (first run, can take a minute)..." || return 1
  assert_contains "$out" "mise-x:claude:claude --version" || return 1
  assert_file_exists "$BIN/claude" || return 1
  "$TEEUP" has ai-claude || { echo "ai-claude must be marked"; return 1; }
  "$TEEUP" has ai && { echo "calling claude must not mark the bundle"; return 1; }
  for command in codex gemini copilot opencode; do
    [[ ! -e "$BIN/$command" && ! -L "$BIN/$command" ]] || { echo "claude created $command"; return 1; }
  done
  for leaf in ai-codex ai-gemini ai-copilot ai-opencode; do
    "$TEEUP" has "$leaf" && { echo "claude marked $leaf"; return 1; }
  done
  assert_not_contains "$(cat "$MOCK_LOG")" "brew update" || return 1
  cleanup_test_env
}

test_explicit_ai_install_writes_all_five_wrappers() {
  setup
  local out command leaf
  out="$(DRY_RUN=false "$TEEUP" install ai 2>&1)"
  for command in $AI_COMMANDS; do assert_file_exists "$BIN/$command" || return 1; done
  for leaf in $AI_LEAVES; do "$TEEUP" has "$leaf" || { echo "$leaf must be marked"; return 1; }; done
  "$TEEUP" has ai || { echo "the aggregate must be marked"; return 1; }
  assert_contains "$out" "AI bundle ready: claude, codex, gemini, copilot and opencode." || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "mise -C / use -g --quiet claude" "bundle setup writes wrappers but downloads nothing" || return 1
  cleanup_test_env
}

test_explicit_ai_install_skips_an_already_done_leaf() {
  setup
  DRY_RUN=false "$TEEUP" install ai-claude >/dev/null
  local before out
  before="$(stat -c %Y "$BIN/claude" 2>/dev/null || stat -f %m "$BIN/claude")"
  out="$(DRY_RUN=false "$TEEUP" install ai 2>&1)"
  assert_contains "$out" "Already installed: ai-claude (required by ai)" || return 1
  assert_equals "$before" "$(stat -c %Y "$BIN/claude" 2>/dev/null || stat -f %m "$BIN/claude")" || return 1
  cleanup_test_env
}

test_gemini_leaf_brings_node_and_gemini_cli() {
  setup
  DRY_RUN=false "$TEEUP" install ai-gemini >/dev/null
  local out
  out="$("$BIN/gemini" chat 2>"$TEST_HOME/err")"
  assert_contains "$(cat "$TEST_HOME/err")" "Installing Gemini CLI through mise" || return 1
  assert_equals "mise-x:node,gemini-cli:gemini chat" "$out" || return 1
  assert_contains "$(cat "$BIN/gemini")" "for teeup_tool in node gemini-cli; do" || return 1
  cleanup_test_env
}

test_leaf_configure_preserves_a_foreign_command() {
  setup
  mkdir -p "$BIN" "$TEST_HOME/.local/share/claude/versions"
  printf '#!/bin/sh\necho native\n' > "$TEST_HOME/.local/share/claude/versions/2.1.0"
  chmod +x "$TEST_HOME/.local/share/claude/versions/2.1.0"
  ln -s "$TEST_HOME/.local/share/claude/versions/2.1.0" "$BIN/claude"
  local out
  out="$(DRY_RUN=false "$TEEUP" install ai-claude 2>&1)"
  assert_contains "$out" "Keeping $BIN/claude: it was not written by teeup" || return 1
  assert_contains "$out" "teeup configure ai-claude" || return 1
  assert_not_contains "$out" "The first call of claude installs" || return 1
  assert_equals "native" "$("$BIN/claude")" || return 1
  cleanup_test_env
}

test_leaf_remove_touches_only_its_wrapper() {
  setup
  DRY_RUN=false "$TEEUP" install ai-claude >/dev/null
  DRY_RUN=false "$TEEUP" install ai-codex >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" remove ai-claude 2>&1)"
  assert_contains "$out" "Removed the mise wrapper: claude" || return 1
  [[ ! -e "$BIN/claude" ]] || { echo "claude wrapper remains"; return 1; }
  assert_file_exists "$BIN/codex" || return 1
  "$TEEUP" has ai-claude && { echo "ai-claude marker remains"; return 1; }
  "$TEEUP" has ai-codex || { echo "ai-codex marker was cleared"; return 1; }
  cleanup_test_env
}

test_aggregate_remove_removes_all_leaf_wrappers_and_state() {
  setup
  DRY_RUN=false "$TEEUP" install ai >/dev/null
  local out command leaf
  out="$(DRY_RUN=false "$TEEUP" remove ai 2>&1)"
  assert_contains "$out" "Removed ai." || return 1
  for command in $AI_COMMANDS; do
    [[ ! -e "$BIN/$command" && ! -L "$BIN/$command" ]] || { echo "$command wrapper remains"; return 1; }
  done
  for leaf in $AI_LEAVES; do "$TEEUP" has "$leaf" && { echo "$leaf marker remains"; return 1; }; done
  "$TEEUP" has ai && { echo "aggregate marker remains"; return 1; }
  cleanup_test_env
}

# Real Mac, 2026-09-26: teeup remove ai left every tool installed and still
# requested in the global mise config, so teeup update would reinstall them.
# Removing the bundle drops each leaf's own tool -- never the shared node.
test_aggregate_remove_drops_each_tool_from_mise_but_not_node() {
  setup
  printf '%s\n' claude codex gemini-cli node copilot opencode > "$TEST_HOME/mise-installed"
  mock_command_script mise <<'EOF2'
[ "$1" = "-C" ] && shift 2
case "$*" in
  "ls --global"*) while read -r t; do printf '%s latest ~/.config/mise/config.toml latest\n' "$t"; done < "$HOME/mise-installed" ;;
  *) : ;;
esac
exit 0
EOF2
  DRY_RUN=false "$TEEUP" install ai >/dev/null
  DRY_RUN=false "$TEEUP" remove ai >/dev/null 2>&1 || { echo "remove failed"; return 1; }
  local tool log
  log="$(cat "$MOCK_LOG")"
  for tool in claude codex gemini-cli copilot opencode; do
    assert_contains "$log" "mise -C / unuse -g $tool" "remove must drop $tool from the global mise config" || return 1
  done
  assert_not_contains "$log" "unuse -g node" "node is a shared runtime, never removed with gemini" || return 1
  cleanup_test_env
}

test_ai_dry_run_writes_nothing_and_claims_nothing() {
  setup
  local out command leaf
  out="$(DRY_RUN=true "$TEEUP" install ai 2>&1)"
  assert_contains "$out" "Would write $BIN/claude" || return 1
  assert_not_contains "$out" "AI bundle ready" || return 1
  # No leaf records a done marker under DRY_RUN (mise_wrapper_write only
  # previews), so a naive incomplete check would call every leaf "missing"
  # and tell the user to run the very command they are previewing (I1). The
  # aggregate configure must claim neither success nor incompleteness here.
  assert_not_contains "$out" "bundle is incomplete" || return 1
  for command in $AI_COMMANDS; do [[ ! -e "$BIN/$command" ]] || { echo "dry run wrote $command"; return 1; }; done
  for leaf in $AI_LEAVES; do "$TEEUP" has "$leaf" && { echo "dry run marked $leaf"; return 1; }; done
  [[ ! -e "$TEST_HOME/.local/state/teeup/logs/lazy.log" ]] || { echo "dry run wrote the lazy log"; return 1; }
  cleanup_test_env
}

# I1 regression: a real (non-dry) configure of the aggregate must tell the
# truth about a leaf whose done marker is gone (an interrupted install, or
# one undone by hand), and the repair line it prints must actually repair it.
test_ai_configure_warns_when_a_leaf_is_incomplete_then_repairs() {
  setup
  DRY_RUN=false "$TEEUP" install ai >/dev/null
  rm -f "$TEST_HOME/.local/state/teeup/done/cap-ai-claude"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ai 2>&1)"
  assert_contains "$out" "The ai bundle is incomplete (ai-claude). Repair it with: teeup install ai" || return 1
  DRY_RUN=false "$TEEUP" install ai >/dev/null
  out="$(DRY_RUN=false "$TEEUP" configure ai 2>&1)"
  assert_not_contains "$out" "bundle is incomplete" || return 1
  assert_contains "$out" "AI bundle ready: claude, codex, gemini, copilot and opencode." || return 1
  cleanup_test_env
}

# I2 regression: a wrapper that cannot be deleted (its directory made
# read-only here, standing in for a permissions problem on a real machine)
# must fail teeup remove ai outright, name itself in the failure, and leave
# the aggregate marked installed -- a retry has to see "ai" as still there to
# remove, not silently already gone.
test_aggregate_remove_fails_when_a_wrapper_will_not_delete() {
  setup
  DRY_RUN=false "$TEEUP" install ai >/dev/null
  chmod 0555 "$BIN"
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" remove ai 2>&1)" || rc=$?
  chmod 0755 "$BIN"
  assert_failure "$rc" "a wrapper left behind must fail the removal" || return 1
  assert_contains "$out" "Could not finish removing:" || return 1
  "$TEEUP" has ai || { echo "the ai marker must remain after a failed removal"; return 1; }
  cleanup_test_env
}

# I2 regression: the only retry the failure names must actually work. Before
# the fix, the leaf's own mise_wrapper_remove named itself ("teeup remove
# ai-claude"), which cmd_remove refuses outright while the still-installed
# `ai` bundle requires ai-claude -- an unusable retry. Fix its cause (make
# the bin directory writable again) and run the printed "teeup remove ai";
# it must succeed.
test_aggregate_remove_retry_succeeds_once_the_cause_is_fixed() {
  setup
  DRY_RUN=false "$TEEUP" install ai >/dev/null
  chmod 0555 "$BIN"
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" remove ai 2>&1)" || rc=$?
  chmod 0755 "$BIN"
  assert_failure "$rc" || return 1
  assert_contains "$out" "then run: teeup remove ai" || return 1
  assert_not_contains "$out" "teeup remove ai-claude" "a leaf-only retry cannot succeed while ai still requires it" || return 1
  local rc2=0 out2
  out2="$(DRY_RUN=false "$TEEUP" remove ai 2>&1)" || rc2=$?
  assert_success "$rc2" "the printed retry command must actually succeed" || return 1
  assert_contains "$out2" "Removed ai." || return 1
  "$TEEUP" has ai && { echo "ai should be gone once the retry succeeds"; return 1; }
  for command in $AI_COMMANDS; do [[ ! -e "$BIN/$command" ]] || { echo "$command wrapper survived the retry"; return 1; }; done
  cleanup_test_env
}

echo "capabilities/ai"
run_test "each command has one leaf provider" test_each_command_has_one_leaf_provider
run_test "runtime shims route to individual leaves" test_runtime_shims_route_to_individual_leaves
run_test "claude shim sets up only claude" test_claude_shim_sets_up_only_claude
run_test "explicit ai install writes all five wrappers" test_explicit_ai_install_writes_all_five_wrappers
run_test "explicit ai install skips an already-done leaf" test_explicit_ai_install_skips_an_already_done_leaf
run_test "gemini leaf brings node and gemini-cli" test_gemini_leaf_brings_node_and_gemini_cli
run_test "leaf configure preserves a foreign command" test_leaf_configure_preserves_a_foreign_command
run_test "leaf remove touches only its wrapper" test_leaf_remove_touches_only_its_wrapper
run_test "aggregate remove removes all leaf wrappers and state" test_aggregate_remove_removes_all_leaf_wrappers_and_state
run_test "aggregate remove drops each tool from mise but not node" test_aggregate_remove_drops_each_tool_from_mise_but_not_node
run_test "ai dry run writes nothing and claims nothing" test_ai_dry_run_writes_nothing_and_claims_nothing
run_test "ai configure warns when a leaf is incomplete then repairs" test_ai_configure_warns_when_a_leaf_is_incomplete_then_repairs
run_test "aggregate remove fails when a wrapper will not delete" test_aggregate_remove_fails_when_a_wrapper_will_not_delete
run_test "aggregate remove retry succeeds once the cause is fixed" test_aggregate_remove_retry_succeeds_once_the_cause_is_fixed
print_summary
