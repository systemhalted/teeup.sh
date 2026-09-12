#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  mock_command dscl 0 "UserShell: /bin/bash"
  mock_command chsh 0 ""
  mock_command defaults 1 ""
  TEEUP="$TEEUP_PATH/bin/teeup"
}

# The two contracts plan 2b builds on (TEEUP_APPEARANCE and the generated theme
# environment) are only proved by actually running zsh, so a missing zsh is a
# failure, not a skip: run_test hides the output of a passing test, so a "skip"
# notice would be invisible and 2b would inherit an unverified contract.
# CI installs zsh on the Linux runner; macOS always has /bin/zsh.
require_zsh() {
  command -v zsh >/dev/null 2>&1 && return 0
  echo "zsh is not installed; this suite needs it (brew install zsh / sudo apt-get install -y zsh)"
  return 1
}

test_install_gets_the_plugins_and_switches_the_login_shell() {
  setup
  export TEEUP_TEST_MISSING="zsh"
  local out
  out="$(DRY_RUN=true "$TEEUP" install zsh 2>&1)"
  assert_contains "$out" "Would execute: brew install zsh-autosuggestions" || return 1
  assert_contains "$out" "Would execute: brew install zsh-syntax-highlighting" || return 1
  assert_contains "$out" "Would execute: brew install zsh-completions" || return 1
  assert_contains "$out" "Would execute: chsh -s /bin/zsh" || return 1
  cleanup_test_env
}

test_install_leaves_an_existing_zsh_login_shell_alone() {
  setup
  mock_command dscl 0 "UserShell: /bin/zsh"
  local out
  out="$(DRY_RUN=true "$TEEUP" install zsh 2>&1)"
  assert_contains "$out" "Login shell is already /bin/zsh." || return 1
  assert_not_contains "$out" "chsh" || return 1
  cleanup_test_env
}

test_configure_installs_the_thin_home_files() {
  setup
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null
  assert_file_exists "$TEST_HOME/.zshrc" || return 1
  assert_file_exists "$TEST_HOME/.zprofile" || return 1
  assert_file_exists "$TEST_HOME/.zshenv" || return 1
  assert_file_exists "$TEST_HOME/.config/zsh/local.zsh" || return 1
  assert_contains "$(cat "$TEST_HOME/.zshrc")" 'capabilities/zsh/default/rc' || return 1
  assert_contains "$(cat "$TEST_HOME/.zshenv")" '.config/teeup/env' || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure zsh)"
  assert_contains "$out" "Already installed: $TEST_HOME/.zshrc" || return 1
  cleanup_test_env
}

test_configure_backs_up_a_foreign_zshrc() {
  setup
  printf 'export PATH=/mine:$PATH\n' > "$TEST_HOME/.zshrc"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  # A glob loop, not `ls | grep` (shellcheck SC2010). The backup of a dotfile
  # is itself a dotfile, so the pattern carries the leading dot.
  local backup="" f
  for f in "$TEST_HOME"/.zshrc.teeup_backup_*; do
    [[ -e "$f" ]] && backup="$f"
  done
  [[ -n "$backup" ]] || { echo "foreign file not backed up"; return 1; }
  assert_contains "$(cat "$TEST_HOME/.zshrc")" 'capabilities/zsh/default/rc' || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  DRY_RUN=true "$TEEUP" configure zsh >/dev/null
  [[ ! -e "$TEST_HOME/.zshrc" ]] || { echo ".zshrc written in dry run"; return 1; }
  cleanup_test_env
}

test_default_env_appends_the_shims_last() {
  setup
  require_zsh || return 1
  mkdir -p "$TEST_HOME/.local/bin" "$TEST_HOME/.local/state/teeup/shims"
  local out
  out="$(zsh -f -c ". '$TEEUP_PATH/capabilities/zsh/default/env'; printf '%s\n' \"\$PATH\"")"
  assert_contains "$out" "$TEST_HOME/.local/bin" || return 1
  [[ "$out" == *"$TEST_HOME/.local/state/teeup/shims" ]] ||
    { echo "teeup shims must be the last PATH entry, got: $out"; return 1; }
  cleanup_test_env
}

test_rc_exports_appearance_and_sources_the_theme_env() {
  setup
  require_zsh || return 1
  mock_command defaults 0 "Dark"
  mkdir -p "$TEST_HOME/.local/state/teeup/current/theme/dark"
  printf 'export BAT_THEME=teeup-generated\n' \
    > "$TEST_HOME/.local/state/teeup/current/theme/dark/env.sh"
  local out
  out="$(zsh -f -c "export TEEUP_PATH='$TEEUP_PATH'; . '$TEEUP_PATH/capabilities/zsh/default/rc'; print \"\$TEEUP_APPEARANCE \$BAT_THEME\"" 2>&1)"
  assert_contains "$out" "dark teeup-generated" || return 1
  cleanup_test_env
}

test_rc_reports_light_when_defaults_exits_nonzero() {
  setup
  require_zsh || return 1
  local out
  out="$(zsh -f -c "export TEEUP_PATH='$TEEUP_PATH'; . '$TEEUP_PATH/capabilities/zsh/default/rc'; print \"\$TEEUP_APPEARANCE\"" 2>&1)"
  assert_contains "$out" "light" || return 1
  cleanup_test_env
}

echo "capabilities/zsh"
run_test "install gets the plugins and switches the login shell" test_install_gets_the_plugins_and_switches_the_login_shell
run_test "install leaves an existing zsh login shell alone" test_install_leaves_an_existing_zsh_login_shell_alone
run_test "configure installs the thin home files" test_configure_installs_the_thin_home_files
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure backs up a foreign zshrc" test_configure_backs_up_a_foreign_zshrc
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "default env appends the shims last" test_default_env_appends_the_shims_last
run_test "rc exports appearance and sources the theme env" test_rc_exports_appearance_and_sources_the_theme_env
run_test "rc reports light when defaults exits non-zero" test_rc_reports_light_when_defaults_exits_nonzero
print_summary
