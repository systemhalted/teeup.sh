#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# cli-tools has two halves (#112). The package manager installs what teeup
# needs (jq), what mise has no package for (tree, wget, curl, gnupg) and
# btop, which has no macOS build upstream. mise installs the rest at the
# versions in share/teeup/tools.lock.
PM_COMMANDS="jq btop tree wget curl gpg"
MISE_COMMANDS="rg fd fzf bat eza zoxide yq tldr dust"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  # A fresh Mac has none of these. The mise half is hidden by path, so the
  # links an install writes into ~/.local/bin still count.
  export TEEUP_TEST_MISSING="jq btop gpg"
  # shellcheck disable=SC2086  # a word list of command names
  hide_host_commands $MISE_COMMANDS
  TEEUP="$TEEUP_PATH/bin/teeup"
  # Nothing in this suite may reach the host's mise (Task 5, #112).
  mock_mise_tools
}

mock_answering_brew() {
  mock_command_script brew <<'EOF2'
case "$1" in --version) echo "Homebrew 4.3.9" ;; esac
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
}

test_doctor_accepts_a_healthy_machine() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_answering_brew
  export TEEUP_TEST_MISSING=""
  local cmd rc=0 out
  for cmd in $PM_COMMANDS; do
    mock_command "$cmd" 0 ""
  done
  DRY_RUN=false "$TEEUP" configure cli-tools >/dev/null 2>&1
  state_done mark cap-cli-tools
  out="$(DRY_RUN=false "$TEEUP" doctor cli-tools 2>&1)" || rc=$?
  assert_success "$rc" "every package command is on PATH and every mise tool is linked: $out" || return 1
  assert_not_contains "$out" "is not installed" || return 1
  assert_contains "$out" "rg is ripgrep $(lock_version ripgrep) through mise." || return 1
  assert_contains "$out" "tldr is tealdeer $(lock_version tealdeer) through mise." || return 1
  cleanup_test_env
}

test_doctor_still_reports_a_package_that_is_missing_everywhere() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_answering_brew
  local cmd rc=0 out
  for cmd in btop tree wget curl gpg; do
    mock_command "$cmd" 0 ""
  done
  export TEEUP_TEST_MISSING="jq"
  DRY_RUN=false "$TEEUP" configure cli-tools >/dev/null 2>&1
  state_done mark cap-cli-tools
  out="$(DRY_RUN=false "$TEEUP" doctor cli-tools 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "package jq is not installed" || return 1
  cleanup_test_env
}

# The printed fix for a missing link is `teeup configure cli-tools`, and
# running it clears the finding.
test_doctor_reports_a_missing_link_and_its_fix_works() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_answering_brew
  export TEEUP_TEST_MISSING=""
  local cmd rc=0 out
  for cmd in $PM_COMMANDS; do
    mock_command "$cmd" 0 ""
  done
  state_done mark cap-cli-tools
  out="$(DRY_RUN=false "$TEEUP" doctor cli-tools 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$TEST_HOME/.local/bin/rg is missing" || return 1
  assert_contains "$out" "fix: teeup configure cli-tools" || return 1
  DRY_RUN=false "$TEEUP" configure cli-tools >/dev/null 2>&1
  rc=0
  out="$(DRY_RUN=false "$TEEUP" doctor cli-tools 2>&1)" || rc=$?
  assert_success "$rc" "the printed fix repaired it: $out" || return 1
  cleanup_test_env
}

test_doctor_reports_one_broken_package_command_end_to_end() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_answering_brew
  export TEEUP_TEST_MISSING=""
  local cmd rc=0 out
  for cmd in btop tree wget curl gpg; do
    mock_command "$cmd" 0 ""
  done
  mock_command jq 1 "broken jq"
  DRY_RUN=false "$TEEUP" configure cli-tools >/dev/null 2>&1
  state_done mark cap-cli-tools
  out="$(DRY_RUN=false "$TEEUP" doctor cli-tools 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "jq resolves to $MOCK_BIN/jq but does not run" || return 1
  assert_contains "$out" "fix: teeup install cli-tools" || return 1
  assert_contains "$out" "gpg is on PATH, so gnupg is provided" || return 1
  cleanup_test_env
}

test_install_reads_its_pairs_from_the_metadata() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  local declared pkg tools pair
  declared="$(cap_meta_get cli-tools package_commands)"
  for pkg in $(cap_meta_get cli-tools packages); do
    case " $declared " in
      *" $pkg:"*) ;;
      *) echo "package $pkg has no command mapping, so doctor cannot ask what install asked"; return 1 ;;
    esac
  done
  assert_contains "$declared" "gnupg:gpg" || return 1
  tools="$(cap_meta_get cli-tools mise_tools)"
  assert_contains "$tools" "ripgrep:rg" || return 1
  assert_contains "$tools" "tealdeer:tldr" || return 1
  for pair in $tools; do
    case " $(cap_meta_get cli-tools packages) " in
      *" ${pair%%:*} "*) echo "${pair%%:*} is in both packages and mise_tools"; return 1 ;;
    esac
  done
  cleanup_test_env
}

test_install_uses_the_package_manager_for_its_half_and_mise_for_the_rest() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install cli-tools 2>&1)"
  assert_contains "$out" "Would execute: brew install jq" || return 1
  assert_contains "$out" "Would execute: brew install gnupg" || return 1
  assert_not_contains "$out" "brew install ripgrep" || return 1
  assert_not_contains "$out" "brew install tldr" || return 1
  assert_contains "$out" "Would execute: mise -C / install ripgrep@$(lock_version ripgrep)" || return 1
  assert_contains "$out" "Would execute: mise -C / install tealdeer@$(lock_version tealdeer)" || return 1
  assert_contains "$out" "Would link $TEST_HOME/.local/bin/tldr to tealdeer $(lock_version tealdeer) (mise)" || return 1
  cleanup_test_env
}

test_install_skips_tools_already_on_path() {
  setup
  export TEEUP_TEST_MISSING="btop gpg"
  mock_command jq 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install cli-tools 2>&1)"
  assert_contains "$out" "Already available on PATH: jq" || return 1
  assert_not_contains "$out" "brew install jq" || return 1
  cleanup_test_env
}

test_install_links_every_mise_tool() {
  setup
  DRY_RUN=false "$TEEUP" install cli-tools >/dev/null 2>&1 || { echo "install failed"; return 1; }
  local cmd
  for cmd in $MISE_COMMANDS; do
    [[ -L "$TEST_HOME/.local/bin/$cmd" ]] || { echo "$cmd is not linked"; return 1; }
  done
  assert_contains "$(cat "$TEST_HOME/.config/mise/conf.d/teeup.toml")" "\"ripgrep\" = \"$(lock_version ripgrep)\"" || return 1
  cleanup_test_env
}

test_install_warns_but_survives_a_missing_port_or_tool() {
  setup
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "list"*) exit 1 ;;
  "install btop") exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  local rc=0 out
  out="$(MOCK_MISE_FAIL_INSTALL=dust DRY_RUN=false "$TEEUP" install cli-tools 2>&1)" || rc=$?
  assert_success "$rc" "one missing tool must not fail the capability" || return 1
  assert_contains "$out" "Could not install: btop" || return 1
  assert_contains "$out" "mise could not install dust $(lock_version dust)" || return 1
  assert_contains "$out" "Some of the tools that come from mise are missing" || return 1
  [[ -L "$TEST_HOME/.local/bin/rg" ]] || { echo "the other tools are still linked"; return 1; }
  cleanup_test_env
}

test_install_on_macports_gets_the_same_mise_tools() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install cli-tools 2>&1)"
  assert_contains "$out" "Would execute: sudo port install jq" || return 1
  assert_contains "$out" "Would execute: mise -C / install ripgrep@$(lock_version ripgrep)" || return 1
  assert_contains "$out" "Would execute: mise -C / install tealdeer@$(lock_version tealdeer)" || return 1
  assert_not_contains "$out" "port install ripgrep" || return 1
  assert_not_contains "$out" "port install tealdeer" || return 1
  cleanup_test_env
}

test_configure_writes_the_bat_config() {
  setup
  DRY_RUN=false "$TEEUP" configure cli-tools >/dev/null 2>&1
  assert_file_exists "$TEST_HOME/.config/bat/config" || return 1
  local body
  body="$(cat "$TEST_HOME/.config/bat/config")"
  assert_contains "$body" "--style=numbers,changes,header" || return 1
  assert_not_contains "$body" "--theme" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  DRY_RUN=false "$TEEUP" configure cli-tools >/dev/null 2>&1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure cli-tools 2>&1)"
  assert_contains "$out" "Already installed: $TEST_HOME/.config/bat/config" || return 1
  assert_contains "$out" "Already linked: rg (ripgrep $(lock_version ripgrep))" || return 1
  assert_contains "$out" "Already current: $TEST_HOME/.config/mise/conf.d/teeup.toml" || return 1
  cleanup_test_env
}

echo "capabilities/cli-tools"
run_test "doctor accepts a healthy machine" test_doctor_accepts_a_healthy_machine
run_test "doctor still reports a package that is missing everywhere" test_doctor_still_reports_a_package_that_is_missing_everywhere
run_test "doctor reports a missing link, and its fix works" test_doctor_reports_a_missing_link_and_its_fix_works
run_test "doctor reports one broken package command end to end" test_doctor_reports_one_broken_package_command_end_to_end
run_test "install reads its pairs from the metadata" test_install_reads_its_pairs_from_the_metadata
run_test "install uses the package manager for its half and mise for the rest" test_install_uses_the_package_manager_for_its_half_and_mise_for_the_rest
run_test "install skips tools already on PATH" test_install_skips_tools_already_on_path
run_test "install links every mise tool" test_install_links_every_mise_tool
run_test "install warns but survives a missing port or tool" test_install_warns_but_survives_a_missing_port_or_tool
run_test "install on MacPorts gets the same mise tools" test_install_on_macports_gets_the_same_mise_tools
run_test "configure writes the bat config" test_configure_writes_the_bat_config
run_test "configure is idempotent" test_configure_is_idempotent
print_summary
