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
  # The env-file lookup is rendered to the resolved, absolute path at
  # configure time (B1/B2 fix): the installed file no longer depends on
  # XDG_CONFIG_HOME being set the same way at shell-start time as it was at
  # configure time.
  assert_contains "$(cat "$TEST_HOME/.zshenv")" "$TEST_HOME/.config/teeup/env" || return 1
  assert_not_contains "$(cat "$TEST_HOME/.zshenv")" 'XDG_CONFIG_HOME:-$HOME/.config}/teeup/env' || return 1
  cleanup_test_env
}

test_configure_bakes_the_absolute_env_path_for_a_custom_xdg_config_home() {
  setup
  require_zsh || return 1
  export XDG_CONFIG_HOME="$TEST_HOME/xdg"
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  assert_file_exists "$XDG_CONFIG_HOME/teeup/env" || return 1
  local out expected_state
  # The state dir formula follows XDG_STATE_HOME, not XDG_CONFIG_HOME; compare
  # against what teeup-runtime actually recorded rather than re-deriving it.
  # Values are %q-escaped rather than double-quoted, so a plain path with no
  # shell metacharacters comes out unquoted; strip only the "export NAME="
  # prefix.
  expected_state="$(grep '^export TEEUP_STATE_DIR=' "$XDG_CONFIG_HOME/teeup/env" | sed -e 's/^export TEEUP_STATE_DIR=//')"
  # Nothing macOS reads before ~/.zshenv sets XDG_CONFIG_HOME, so unsetting it
  # here is exactly the fresh-login-shell scenario B1 broke: the installed
  # .zshenv must still find the env file and set both TEEUP_PATH and
  # TEEUP_STATE_DIR from it.
  out="$(env -u XDG_CONFIG_HOME zsh -f -c "source '$TEST_HOME/.zshenv'; print -r -- \$TEEUP_PATH \$TEEUP_STATE_DIR")"
  assert_equals "$TEEUP_PATH $expected_state" "$out" || return 1
  cleanup_test_env
}

test_configure_bakes_the_absolute_local_zsh_path_for_a_custom_xdg_config_home() {
  setup
  require_zsh || return 1
  # A one-shot custom XDG_CONFIG_HOME at install time: configure puts local.zsh
  # under that root, but nothing sets XDG_CONFIG_HOME again before a fresh
  # login shell reads ~/.zshrc, so the shipped token would expand to
  # ~/.config/zsh/local.zsh and the file would never be sourced.
  export XDG_CONFIG_HOME="$TEST_HOME/xdg"
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  assert_file_exists "$XDG_CONFIG_HOME/zsh/local.zsh" || return 1
  printf 'TEEUP_LOCAL_MARKER=from-custom-xdg\n' >> "$XDG_CONFIG_HOME/zsh/local.zsh"
  assert_not_contains "$(cat "$TEST_HOME/.zshrc")" 'XDG_CONFIG_HOME:-$HOME/.config}/zsh/local.zsh' || return 1
  local out
  out="$(env -u XDG_CONFIG_HOME zsh -f -c "source '$TEST_HOME/.zshrc'; print -r -- \$TEEUP_LOCAL_MARKER" 2>/dev/null)"
  assert_equals "from-custom-xdg" "$out" || return 1
  cleanup_test_env
}

test_configure_quotes_a_path_with_shell_metacharacters() {
  setup
  require_zsh || return 1
  export XDG_CONFIG_HOME="$TEST_HOME/we\`ird \$dir \"q\" \\b"
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  local zshenv="$TEST_HOME/.zshenv"
  assert_file_exists "$zshenv" || return 1
  local out
  # Passed as an argv element ($1), not interpolated into the -c script text:
  # the point of the fix is that a backtick, dollar, double quote or
  # backslash baked into the rendered .zshenv must not be re-parsed as shell
  # syntax when that file is sourced.
  out="$(zsh -f -c 'source "$1"; print -r -- $TEEUP_PATH $TEEUP_CONFIG_DIR' _ "$zshenv")"
  assert_equals "$TEEUP_PATH $XDG_CONFIG_HOME/teeup" "$out" || return 1
  cleanup_test_env
}

test_configure_installs_under_zdotdir() {
  setup
  export ZDOTDIR="$TEST_HOME/zdot"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null
  assert_file_exists "$ZDOTDIR/.zshenv" || return 1
  assert_file_exists "$ZDOTDIR/.zprofile" || return 1
  assert_file_exists "$ZDOTDIR/.zshrc" || return 1
  [[ ! -e "$TEST_HOME/.zshenv" ]] || { echo ".zshenv installed under HOME instead of ZDOTDIR"; return 1; }
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

# F4: configure renders each home file to a temp file before copying it into
# place, so the dry-run message used to name that temp file -- useless to the
# user, who cannot tell what is actually being installed.
test_configure_dry_run_names_the_shipped_source_not_a_temp_file() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" configure zsh)"
  assert_contains "$out" "Would install $TEST_HOME/.zshenv from $TEEUP_PATH/capabilities/zsh/home/.zshenv" || return 1
  cleanup_test_env
}

test_configure_dry_run_names_the_shipped_source_for_a_foreign_zshenv() {
  setup
  printf 'export PATH=/mine:$PATH\n' > "$TEST_HOME/.zshenv"
  local out
  out="$(DRY_RUN=true "$TEEUP" configure zsh)"
  assert_contains "$out" "Would back up foreign $TEST_HOME/.zshenv and install $TEEUP_PATH/capabilities/zsh/home/.zshenv" || return 1
  cleanup_test_env
}

test_zshenv_sources_teeup_env_from_xdg_config_home() {
  setup
  require_zsh || return 1
  local xdg="$TEST_HOME/xdg"
  mkdir -p "$xdg/teeup"
  printf 'export TEEUP_PATH="from-xdg"\n' > "$xdg/teeup/env"
  local out
  out="$(XDG_CONFIG_HOME="$xdg" zsh -f -c "source '$TEEUP_PATH/capabilities/zsh/home/.zshenv'; print -r -- \$TEEUP_PATH")"
  assert_equals "from-xdg" "$out" || return 1
  cleanup_test_env
}

test_zprofile_sources_teeup_env_from_xdg_config_home() {
  setup
  require_zsh || return 1
  local xdg="$TEST_HOME/xdg"
  mkdir -p "$xdg/teeup"
  printf 'export TEEUP_PATH="from-xdg"\n' > "$xdg/teeup/env"
  local out
  out="$(XDG_CONFIG_HOME="$xdg" zsh -f -c "source '$TEEUP_PATH/capabilities/zsh/home/.zprofile'; print -r -- \$TEEUP_PATH")"
  assert_equals "from-xdg" "$out" || return 1
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

test_default_env_honours_mise_data_dir_for_shims() {
  setup
  require_zsh || return 1
  local mise_data="$TEST_HOME/custom-mise-data"
  mkdir -p "$TEST_HOME/.local/bin" "$mise_data/shims"
  local out
  out="$(MISE_DATA_DIR="$mise_data" zsh -f -c ". '$TEEUP_PATH/capabilities/zsh/default/env'; printf '%s\n' \"\$PATH\"")"
  assert_contains "$out" "$mise_data/shims" || return 1
  assert_not_contains "$out" "$TEST_HOME/.local/share/mise/shims" || return 1
  cleanup_test_env
}

test_default_env_prefers_macports_when_recorded() {
  setup
  require_zsh || return 1
  local root="$TEST_HOME/prefixroot"
  mkdir -p "$root/opt/local/bin" "$root/opt/local/sbin"
  mkdir -p "$root/opt/homebrew/bin" "$root/opt/homebrew/sbin"
  : > "$root/opt/homebrew/bin/brew"
  chmod +x "$root/opt/homebrew/bin/brew"
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_PACKAGE_MANAGER="macports"\n' > "$TEST_HOME/.config/teeup/answers"
  local out
  out="$(TEEUP_TEST_PREFIX_ROOT="$root" zsh -f -c ". '$TEEUP_PATH/capabilities/zsh/default/env'; printf '%s\n' \"\$PATH\"")"
  local macports_pos brew_pos
  macports_pos="$(printf '%s' "$out" | tr ':' '\n' | grep -n "^$root/opt/local/bin\$" | head -1 | cut -d: -f1)"
  brew_pos="$(printf '%s' "$out" | tr ':' '\n' | grep -n "^$root/opt/homebrew/bin\$" | head -1 | cut -d: -f1)"
  [[ -n "$macports_pos" && -n "$brew_pos" ]] || { echo "expected both prefixes on PATH, got: $out"; return 1; }
  [[ "$macports_pos" -lt "$brew_pos" ]] || { echo "expected MacPorts before Homebrew, got: $out"; return 1; }
  cleanup_test_env
}

test_default_env_prefers_homebrew_when_recorded() {
  setup
  require_zsh || return 1
  local root="$TEST_HOME/prefixroot"
  mkdir -p "$root/opt/local/bin" "$root/opt/local/sbin"
  mkdir -p "$root/opt/homebrew/bin" "$root/opt/homebrew/sbin"
  : > "$root/opt/homebrew/bin/brew"
  chmod +x "$root/opt/homebrew/bin/brew"
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_PACKAGE_MANAGER="homebrew"\n' > "$TEST_HOME/.config/teeup/answers"
  local out
  out="$(TEEUP_TEST_PREFIX_ROOT="$root" zsh -f -c ". '$TEEUP_PATH/capabilities/zsh/default/env'; printf '%s\n' \"\$PATH\"")"
  local macports_pos brew_pos
  macports_pos="$(printf '%s' "$out" | tr ':' '\n' | grep -n "^$root/opt/local/bin\$" | head -1 | cut -d: -f1)"
  brew_pos="$(printf '%s' "$out" | tr ':' '\n' | grep -n "^$root/opt/homebrew/bin\$" | head -1 | cut -d: -f1)"
  [[ -n "$macports_pos" && -n "$brew_pos" ]] || { echo "expected both prefixes on PATH, got: $out"; return 1; }
  [[ "$brew_pos" -lt "$macports_pos" ]] || { echo "expected Homebrew before MacPorts, got: $out"; return 1; }
  cleanup_test_env
}

test_default_env_lets_the_machine_file_override_the_answers_file() {
  setup
  require_zsh || return 1
  local root="$TEST_HOME/prefixroot"
  mkdir -p "$root/opt/local/bin" "$root/opt/local/sbin"
  mkdir -p "$root/opt/homebrew/bin" "$root/opt/homebrew/sbin"
  : > "$root/opt/homebrew/bin/brew"
  chmod +x "$root/opt/homebrew/bin/brew"
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_PACKAGE_MANAGER="homebrew"\n' > "$TEST_HOME/.config/teeup/answers"
  # machine_file() in lib/answers.sh looks up $TEEUP_PATH/machines/<hostname
  # -s>.conf; hostname is mocked to "testmac" by mock_macos_base. Stub the
  # machines dir under a throwaway TEEUP_PATH (exported inside the zsh
  # subshell only) so the real repo's machines/ is never touched, the same
  # way TEEUP_TEST_PREFIX_ROOT stubs the brew/MacPorts prefixes above.
  mkdir -p "$TEST_HOME/machines"
  printf 'TEEUP_PACKAGE_MANAGER="macports"\n' > "$TEST_HOME/machines/testmac.conf"
  local out
  out="$(TEEUP_TEST_PREFIX_ROOT="$root" zsh -f -c "export TEEUP_PATH='$TEST_HOME'; . '$TEEUP_PATH/capabilities/zsh/default/env'; printf '%s\n' \"\$PATH\"")"
  local macports_pos brew_pos
  macports_pos="$(printf '%s' "$out" | tr ':' '\n' | grep -n "^$root/opt/local/bin\$" | head -1 | cut -d: -f1)"
  brew_pos="$(printf '%s' "$out" | tr ':' '\n' | grep -n "^$root/opt/homebrew/bin\$" | head -1 | cut -d: -f1)"
  [[ -n "$macports_pos" && -n "$brew_pos" ]] || { echo "expected both prefixes on PATH, got: $out"; return 1; }
  [[ "$macports_pos" -lt "$brew_pos" ]] ||
    { echo "expected MacPorts before Homebrew (machine file must win), got: $out"; return 1; }
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

test_rc_does_not_grow_fpath_on_a_second_source() {
  setup
  require_zsh || return 1
  local root="$TEST_HOME/fakebrew"
  mkdir -p "$root/share/zsh/site-functions" "$root/share/zsh-completions"
  local out
  out="$(HOMEBREW_PREFIX="$root" zsh -f -c "export TEEUP_PATH='$TEEUP_PATH'; . '$TEEUP_PATH/capabilities/zsh/default/rc' 2>/dev/null; n1=\$#fpath; . '$TEEUP_PATH/capabilities/zsh/default/rc' 2>/dev/null; n2=\$#fpath; print \"\$n1 \$n2\"")"
  local n1 n2
  n1="${out%% *}"
  n2="${out##* }"
  assert_equals "$n1" "$n2" "fpath must not grow on a second source, got: $out" || return 1
  cleanup_test_env
}

test_rc_leaves_git_revision_syntax_alone() {
  setup
  require_zsh || return 1
  # EXTENDED_GLOB alone turns "^" into a glob operator, so `git show HEAD^`
  # dies with "no matches found"; NO_NOMATCH must be set alongside it so an
  # unmatched pattern passes through unchanged instead.
  # stderr is not captured here: on a host where mise has not yet trusted a
  # parent directory's config, `mise activate` (sourced from init, last in
  # the rc chain) warns on stderr, which is noise unrelated to this test.
  local out
  out="$(zsh -f -c "export TEEUP_PATH='$TEEUP_PATH'; . '$TEEUP_PATH/capabilities/zsh/default/rc'; print -r -- HEAD^" 2>/dev/null)"
  assert_equals "HEAD^" "$out" || return 1
  cleanup_test_env
}

echo "capabilities/zsh"
run_test "install gets the plugins and switches the login shell" test_install_gets_the_plugins_and_switches_the_login_shell
run_test "install leaves an existing zsh login shell alone" test_install_leaves_an_existing_zsh_login_shell_alone
run_test "configure installs the thin home files" test_configure_installs_the_thin_home_files
run_test "configure bakes the absolute env path for a custom XDG_CONFIG_HOME" test_configure_bakes_the_absolute_env_path_for_a_custom_xdg_config_home
run_test "configure bakes the absolute local.zsh path for a custom XDG_CONFIG_HOME" test_configure_bakes_the_absolute_local_zsh_path_for_a_custom_xdg_config_home
run_test "configure quotes a path with shell metacharacters" test_configure_quotes_a_path_with_shell_metacharacters
run_test "configure installs under ZDOTDIR" test_configure_installs_under_zdotdir
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure backs up a foreign zshrc" test_configure_backs_up_a_foreign_zshrc
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "configure dry run names the shipped source, not a temp file" test_configure_dry_run_names_the_shipped_source_not_a_temp_file
run_test "configure dry run names the shipped source for a foreign .zshenv" test_configure_dry_run_names_the_shipped_source_for_a_foreign_zshenv
run_test "zshenv sources teeup env from XDG_CONFIG_HOME" test_zshenv_sources_teeup_env_from_xdg_config_home
run_test "zprofile sources teeup env from XDG_CONFIG_HOME" test_zprofile_sources_teeup_env_from_xdg_config_home
run_test "default env appends the shims last" test_default_env_appends_the_shims_last
run_test "default env honours MISE_DATA_DIR for shims" test_default_env_honours_mise_data_dir_for_shims
run_test "default env prefers macports when recorded" test_default_env_prefers_macports_when_recorded
run_test "default env prefers homebrew when recorded" test_default_env_prefers_homebrew_when_recorded
run_test "default env lets the machine file override the answers file" test_default_env_lets_the_machine_file_override_the_answers_file
run_test "rc exports appearance and sources the theme env" test_rc_exports_appearance_and_sources_the_theme_env
run_test "rc reports light when defaults exits non-zero" test_rc_reports_light_when_defaults_exits_nonzero
run_test "rc does not grow fpath on a second source" test_rc_does_not_grow_fpath_on_a_second_source
run_test "rc leaves git revision syntax alone" test_rc_leaves_git_revision_syntax_alone
print_summary
