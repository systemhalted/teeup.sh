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
  # /usr/bin/security is macOS-only; 44 is its "no such item" exit code.
  mock_command security 44 ""
  # zsh capability: the login-shell probe, the change itself, and the
  # appearance read the shell layer performs (never reached from bootstrap,
  # mocked so a stray call cannot touch the host).
  mock_command dscl 0 "UserShell: /bin/zsh"
  mock_command chsh 0 ""
  mock_command defaults 1 ""
  export TEEUP_TEST_MISSING="brew gum jq starship rg fd fzf bat eza zoxide yq btop tldr dust gpg"
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

test_wizard_runs_when_only_backend_recorded() {
  setup
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_PACKAGE_MANAGER="homebrew"\n' > "$TEST_HOME/.config/teeup/answers"
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")"
  assert_contains "$out" "Your full name" || return 1
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

test_dry_run_answers_take_effect() {
  setup
  local out wizard_no_daily
  wizard_no_daily=$'Ada Lovelace\nada@example.com\n\n1\n1\nn\n'
  out="$("$BOOT" --dry-run <<<"$wizard_no_daily")"
  assert_contains "$out" "Skipping the daily tier (TEEUP_DAILY=no)" || return 1
  cleanup_test_env
}

echo "bootstrap"
run_test "refuses non-macOS" test_refuses_non_macos
run_test "refuses root" test_refuses_root
run_test "unknown flag exits 2" test_unknown_flag_exits_2
run_test "dry run walks core tier in order" test_dry_run_walks_core_tier_in_order
run_test "dry run touches nothing" test_dry_run_touches_nothing
run_test "existing answers skip wizard" test_existing_answers_skip_wizard
run_test "wizard runs when only backend recorded" test_wizard_runs_when_only_backend_recorded
run_test "--reconfigure reruns wizard" test_reconfigure_reruns_wizard
run_test "--skip-daily skips the tier" test_skip_daily_and_daily_no_skip_the_tier
run_test "TEEUP_SKIP skips a core capability" test_teeup_skip_skips_a_core_capability
run_test "core failure aborts" test_core_failure_aborts
run_test "dry run answers take effect" test_dry_run_answers_take_effect
print_summary
