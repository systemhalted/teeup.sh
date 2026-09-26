#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  # `--version` answers for real: an exit-0, silent brew reads as "cannot
  # answer" (lib/doctor.sh's doctor_backend_can_answer), which used to switch
  # off every package check below in silence (NI2).
  mock_command_script brew <<'EOF2'
case "$1" in --version) echo "Homebrew 4.3.9" ;; esac
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

test_reset_renders_the_home_files_again() {
  setup
  # A config dir with a space and a dollar sign: the rendered env path is
  # %q-quoted, so a raw copy of home/.zshrc would differ from the reset file.
  export XDG_CONFIG_HOME="$TEST_HOME/con fig \$x"
  # The narrowed PATH still exposes a host gum, and a capability's configure
  # may ask a question; keep every prompt on the plain read path.
  export TEEUP_NO_GUM=1
  DRY_RUN=false "$TEEUP" install zsh >/dev/null
  cp "$TEST_HOME/.zshrc" "$TEST_HOME/zshrc.installed"
  printf 'alias gs="git status"\n' >> "$TEST_HOME/.zshrc"
  local out
  out="$(DRY_RUN=false "$TEEUP" reset zsh 2>&1)"
  cmp -s "$TEST_HOME/zshrc.installed" "$TEST_HOME/.zshrc" ||
    { echo "reset must restore what configure rendered:"; diff "$TEST_HOME/zshrc.installed" "$TEST_HOME/.zshrc"; return 1; }
  assert_not_contains "$(cat "$TEST_HOME/.zshrc")" '${XDG_CONFIG_HOME:-$HOME/.config}/teeup/env' "not the raw template" || return 1
  assert_contains "$out" "Reset $TEST_HOME/.zshrc (backup at" || return 1
  assert_contains "$out" 'alias gs="git status"' "the diff shows the line the backup keeps" || return 1
  assert_contains "$out" "Already at the shipped version: $TEST_HOME/.zshenv" || return 1
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

test_default_env_prefers_the_users_own_machine_file_over_the_repos() {
  setup
  require_zsh || return 1
  local root="$TEST_HOME/prefixroot"
  mkdir -p "$root/opt/local/bin" "$root/opt/local/sbin"
  mkdir -p "$root/opt/homebrew/bin" "$root/opt/homebrew/sbin"
  : > "$root/opt/homebrew/bin/brew"
  chmod +x "$root/opt/homebrew/bin/brew"
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_PACKAGE_MANAGER="homebrew"\n' > "$TEST_HOME/.config/teeup/answers"
  # Both a repo machine file, under the same throwaway TEEUP_PATH the test
  # above stubs, and a user one under $XDG_CONFIG_HOME/teeup/machines/ (which
  # setup_test_env already points at $TEST_HOME/.config). The user file names
  # MacPorts, the repo file Homebrew, so only the user file winning puts
  # MacPorts first on PATH.
  mkdir -p "$TEST_HOME/machines" "$TEST_HOME/.config/teeup/machines"
  printf 'TEEUP_PACKAGE_MANAGER="homebrew"\n' > "$TEST_HOME/machines/testmac.conf"
  printf 'TEEUP_PACKAGE_MANAGER="macports"\n' > "$TEST_HOME/.config/teeup/machines/testmac.conf"
  local out
  out="$(TEEUP_TEST_PREFIX_ROOT="$root" zsh -f -c "export TEEUP_PATH='$TEST_HOME'; . '$TEEUP_PATH/capabilities/zsh/default/env'; printf '%s\n' \"\$PATH\"")"
  local macports_pos brew_pos
  macports_pos="$(printf '%s' "$out" | tr ':' '\n' | grep -n "^$root/opt/local/bin\$" | head -1 | cut -d: -f1)"
  brew_pos="$(printf '%s' "$out" | tr ':' '\n' | grep -n "^$root/opt/homebrew/bin\$" | head -1 | cut -d: -f1)"
  [[ -n "$macports_pos" && -n "$brew_pos" ]] || { echo "expected both prefixes on PATH, got: $out"; return 1; }
  [[ "$macports_pos" -lt "$brew_pos" ]] ||
    { echo "expected MacPorts before Homebrew (the user's own machine file must win), got: $out"; return 1; }
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

test_default_env_moves_the_shims_last_under_a_macports_machine_file() {
  setup
  require_zsh || return 1
  local root="$TEST_HOME/prefixroot" shims="$TEST_HOME/.local/state/teeup/shims"
  mkdir -p "$root/opt/local/bin" "$root/opt/local/sbin" "$root/opt/homebrew/bin" "$root/opt/homebrew/sbin"
  : > "$root/opt/homebrew/bin/brew"
  chmod +x "$root/opt/homebrew/bin/brew"
  mkdir -p "$TEST_HOME/.local/bin" "$shims" "$TEST_HOME/machines"
  # machine_file() looks up $TEEUP_PATH/machines/<hostname -s>.conf, and
  # mock_macos_base answers "testmac"; TEEUP_PATH is pointed at TEST_HOME
  # inside the zsh process only, as in the machine-file test above.
  printf 'TEEUP_PACKAGE_MANAGER="macports"\n' > "$TEST_HOME/machines/testmac.conf"
  local out n macports_pos brew_pos
  out="$(PATH="$shims:$PATH:$TEST_HOME/appended" TEEUP_TEST_PREFIX_ROOT="$root" zsh -f -c "export TEEUP_PATH='$TEST_HOME'; . '$TEEUP_PATH/capabilities/zsh/default/env'; . '$TEEUP_PATH/capabilities/zsh/default/env'; printf '%s\n' \"\$PATH\"")"
  [[ "$out" == *":$shims" ]] || { echo "teeup shims must be the last PATH entry, got: $out"; return 1; }
  n="$(printf '%s' "$out" | tr ':' '\n' | grep -cxF "$shims" || true)"
  assert_equals "1" "$n" "the shims directory appears once" || return 1
  macports_pos="$(printf '%s' "$out" | tr ':' '\n' | grep -nxF "$root/opt/local/bin" | head -1 | cut -d: -f1)"
  brew_pos="$(printf '%s' "$out" | tr ':' '\n' | grep -nxF "$root/opt/homebrew/bin" | head -1 | cut -d: -f1)"
  [[ -n "$macports_pos" && -n "$brew_pos" && "$macports_pos" -lt "$brew_pos" ]] ||
    { echo "expected MacPorts before Homebrew (machine file must win), got: $out"; return 1; }
  cleanup_test_env
}

test_default_env_editor_ignores_a_lazy_shim() {
  setup
  require_zsh || return 1
  local shims="$TEST_HOME/.local/state/teeup/shims" zsh_bin out
  zsh_bin="$(command -v zsh)"
  mkdir -p "$shims"
  printf '#!/bin/bash\nexit 127\n' > "$shims/nvim"
  chmod +x "$shims/nvim"
  # Only MOCK_BIN and the shims are searched, so an nvim, emacsclient or vim
  # on the host cannot answer the probe.
  out="$(PATH="$MOCK_BIN:$shims" "$zsh_bin" -f -c "unset EDITOR VISUAL; . '$TEEUP_PATH/capabilities/zsh/default/env'; print -r -- \$EDITOR" 2>/dev/null)"
  assert_equals "vim" "$out" "a lazy shim is not an installed nvim" || return 1
  mock_command nvim 0 ""
  out="$(PATH="$MOCK_BIN:$shims" "$zsh_bin" -f -c "unset EDITOR VISUAL; . '$TEEUP_PATH/capabilities/zsh/default/env'; print -r -- \$EDITOR" 2>/dev/null)"
  assert_equals "nvim" "$out" "a real nvim ahead of the shims counts" || return 1
  cleanup_test_env
}

test_doctor_passes_after_configure() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/zsh"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  local rc=0 out
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "Login shell is /bin/zsh." || return 1
  assert_contains "$out" ".zshrc loads teeup's shell layer" || return 1
  cleanup_test_env
}

test_doctor_reports_a_login_shell_that_is_not_zsh() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/bash"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "not zsh" || return 1
  assert_contains "$(cat "$report")" "chsh -s /bin/zsh" || return 1
  cleanup_test_env
}

test_doctor_reports_a_home_file_that_lost_the_teeup_layer() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/zsh"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  printf '# somebody replaced this\n' > "$TEST_HOME/.zshrc"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "never loads" || return 1
  assert_contains "$(cat "$report")" "teeup reset zsh" || return 1
  cleanup_test_env
}

# A source line left behind commented out while debugging still contains the
# marker text, so a substring match calls the shell healthy while none of
# teeup's layer loads -- the exact silent failure this check exists for.
test_doctor_does_not_count_a_commented_out_source_line() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/zsh"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  # shellcheck disable=SC2016  # the marker is literal text, not an expansion
  printf '# DISABLED while debugging: . "$TEEUP_PATH/capabilities/zsh/default/rc"\n' > "$TEST_HOME/.zshrc"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_failure "$rc" "a commented-out source line is not a loaded layer" || return 1
  assert_contains "$out" "never loads" || return 1
  cleanup_test_env
}

# A login shell recorded as zsh but no longer on disk: login falls back to
# something else, and every teeup shell file goes unread.
test_doctor_checks_the_login_shell_exists() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: $TEST_HOME/removed/zsh"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "nothing executable is there" || return 1
  cleanup_test_env
}

# A missing home file is its own outcome, distinct from one whose content is
# wrong; nothing else in this suite deletes one, so a mutation that disabled
# this branch outright went unnoticed.
test_doctor_reports_a_missing_home_file() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/zsh"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  rm -f "$TEST_HOME/.zshrc"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "No $TEST_HOME/.zshrc." || return 1
  assert_contains "$(cat "$report")" "teeup configure zsh" || return 1
  cleanup_test_env
}

# I1: unreadable is not missing, and the fix is not the same. The file is
# plainly there; `teeup reset zsh` replaces it and would destroy a file whose
# only problem is permissions.
test_doctor_reports_an_unreadable_home_file_not_a_replaceable_one() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/zsh"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  chmod 0000 "$TEST_HOME/.zshrc"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  chmod 0644 "$TEST_HOME/.zshrc"
  assert_failure "$rc" || return 1
  assert_contains "$out" "$TEST_HOME/.zshrc cannot be read" || return 1
  assert_contains "$(cat "$report")" "chmod u+r $TEST_HOME/.zshrc" || return 1
  assert_not_contains "$(cat "$report")" "teeup reset zsh" || return 1
  assert_not_contains "$out" "Permission denied" "raw grep stderr must not leak" || return 1
  cleanup_test_env
}

# I2: dscl failing outright (offline DirectoryService, wrong account type) is
# a machine that cannot be checked, not one that is broken -- chsh will not
# fix either.
test_doctor_says_dscl_could_not_answer_when_it_fails() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/zsh"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  mock_command dscl 1 ""
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_unknown "$rc" "dscl not answering is could-not-verify, not healthy and not a confirmed problem" || return 1
  assert_contains "$out" "Could not ask dscl" || return 1
  assert_not_contains "$out" "not zsh" || return 1
  assert_not_contains "$(cat "$report")" "chsh -s /bin/zsh" || return 1
  cleanup_test_env
}

# I2: dscl exits 0 but answers nothing -- a network/AD account whose record
# is not under /Users/$USER. Same "could not check" outcome as an outright
# failure, not "not zsh".
test_doctor_says_dscl_could_not_answer_when_it_is_blank() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/zsh"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  mock_command dscl 0 ""
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_unknown "$rc" "dscl not answering is could-not-verify, not healthy and not a confirmed problem" || return 1
  assert_contains "$out" "Could not ask dscl" || return 1
  assert_not_contains "$out" "not zsh" || return 1
  assert_not_contains "$(cat "$report")" "chsh -s /bin/zsh" || return 1
  cleanup_test_env
}

# teeup's own stub spans two lines: a guard naming the path, then the dot
# command on the next. Comment out only the SECOND and the file still has an
# uncommented line containing capabilities/zsh/default/ -- so a check that
# looks for the path reports the layer loading while nothing sources it. The
# dangling `&&` attaches to whatever follows, so the shell stays valid and
# there is no error to notice either.
test_doctor_requires_an_active_source_not_just_the_path() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  seed_answers
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  local rc_file="${ZDOTDIR:-$TEST_HOME}/.zshrc"
  assert_file_exists "$rc_file" || return 1
  # Comment out the dot command, leave its guard alone.
  awk '/^[[:space:]]*\. "\$TEEUP_PATH\/capabilities\/zsh\/default\/rc"/ { print "#" $0; next } { print }' \
    "$rc_file" > "$rc_file.new" && mv "$rc_file.new" "$rc_file"
  grep -q '^#' "$rc_file" || { echo "fixture: nothing was commented out"; return 1; }
  local out rc=0
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_contains "$out" "does not source teeup's default layer" "the path is present but nothing sources it" || return 1
  assert_failure "$rc" || return 1
  cleanup_test_env
}

# ...and the shipped file, whose source line is real, must still pass.
test_doctor_accepts_the_shipped_two_line_source() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  seed_answers
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  local out
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || true
  assert_contains "$out" "loads teeup's shell layer" "the guard-then-dot shape teeup ships is a real source" || return 1
  cleanup_test_env
}

# Leftovers from what teeup replaced (spec section 10; phase 5a task 7).
test_doctor_flags_oh_my_zsh_p10k_files_and_a_live_rc_line() {
  setup
  export TEEUP_TEST_MISSING="chezmoi"
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/zsh"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  mkdir -p "$TEST_HOME/.oh-my-zsh"
  printf '# p10k\n' > "$TEST_HOME/.p10k.zsh"
  printf 'source "$HOME/.p10k.zsh"\n' >> "$TEST_HOME/.zshrc"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$TEST_HOME/.oh-my-zsh is still on disk" || return 1
  assert_contains "$out" "Powerlevel10k files are still here" || return 1
  assert_contains "$out" "still load something teeup replaced" || return 1
  assert_contains "$(cat "$report")" "teeup migrate legacy" || return 1
  cleanup_test_env
}

# The printed fixes are pasted into a shell, so a home with a space in it
# must survive them: run the fix, and the finding is gone.
test_doctor_leftover_fixes_survive_a_home_with_a_space() {
  setup
  export TEEUP_TEST_MISSING="chezmoi"
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/zsh"
  local home="$TEST_HOME/my home"
  mkdir -p "$home"
  export HOME="$home"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  mkdir -p "$home/.oh-my-zsh"
  printf '# p10k\n' > "$home/.p10k.zsh"
  local report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  DRY_RUN=false cap_run zsh doctor >/dev/null 2>&1 || true
  local fix
  while IFS= read -r fix; do
    (cd "$TEST_HOME" && bash -c "$fix") || { echo "the printed fix failed: $fix"; return 1; }
  done < <(grep -E 'oh-my-zsh|p10k' "$report" | cut -f3)
  [[ ! -e "$home/.oh-my-zsh" && ! -e "$home/.p10k.zsh" ]] || { echo "the fixes did not remove the leftovers"; return 1; }
  cleanup_test_env
}

test_doctor_stops_flagging_leftovers_once_migrate_has_neutralised_them() {
  setup
  export TEEUP_NO_GUM=1
  # No chezmoi here: this test is about the shell leftovers, and a host
  # chezmoi on the runner would drag its own source directory in.
  export TEEUP_TEST_MISSING="chezmoi"
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/zsh"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  printf '%s\n' 'source "$HOME/.teeup.common"' 'source "$HOME/.p10k.zsh"' >> "$TEST_HOME/.zshrc"
  DRY_RUN=false "$TEEUP" migrate legacy >/dev/null 2>&1 || return 1
  local rc=0 out
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_success "$rc" "a migrated home must come up clean" || return 1
  assert_contains "$out" "No Oh My Zsh directory." || return 1
  assert_contains "$out" "No Powerlevel10k files." || return 1
  assert_contains "$out" "No shell file loads a predecessor of teeup." || return 1
  cleanup_test_env
}

# Review P1 on task 7: migrate keeps a line ending in && (it opens a
# block), so the doctor must count it as inert too, or a migrated home
# fails for ever with a fix that changes nothing.
test_doctor_is_clean_after_migrate_keeps_an_and_opener() {
  setup
  export TEEUP_NO_GUM=1
  export TEEUP_TEST_MISSING="chezmoi"
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/zsh"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  printf '%s\n' '[[ -f ~/.p10k.zsh ]] &&' '  source ~/.p10k.zsh' >> "$TEST_HOME/.zshrc"
  DRY_RUN=false "$TEEUP" migrate legacy >/dev/null 2>&1 || return 1
  local rc=0 out
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_not_contains "$out" "still load something teeup replaced" "the kept opener runs nothing on its own" || return 1
  assert_success "$rc" || return 1
  cleanup_test_env
}

test_doctor_flags_a_chezmoi_source_directory_that_still_points_here() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/zsh"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  local sibling="$TEST_HOME/Work/environment/dotfiles"
  mkdir -p "$sibling" "$TEST_HOME/.config/chezmoi"
  export TEEUP_TEST_CHEZMOI_SRC="$sibling"
  mock_command_script chezmoi <<'EOF2'
case "$1" in
  source-path) printf '%s\n' "$TEEUP_TEST_CHEZMOI_SRC" ;;
  *) echo "mock chezmoi: unexpected subcommand $1" >&2; exit 1 ;;
esac
EOF2
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "chezmoi still points at $sibling" || return 1
  assert_contains "$(cat "$report")" "teeup migrate legacy" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "chezmoi purge" || return 1
  assert_dir_exists "$sibling" "a doctor script never changes anything" || return 1
  cleanup_test_env
}

# A chezmoi that fails is not a chezmoi with no source directory.
test_doctor_reports_unknown_when_chezmoi_fails() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/zsh"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  mkdir -p "$TEST_HOME/.config/chezmoi"
  mock_command_script chezmoi <<'EOF2'
echo "chezmoi: invalid config: yaml: line 1" >&2
exit 1
EOF2
  local rc=0 out
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_not_contains "$out" "has no source directory" || return 1
  assert_unknown "$rc" "nothing confirmed broken, but chezmoi could not be asked" || return 1
  cleanup_test_env
}

echo "capabilities/zsh"
test_env_survives_errexit_without_nvim() {
  setup
  require_zsh || return 1
  local zsh_bin out rc=0
  zsh_bin="$(command -v zsh)"
  # An assignment whose command substitution exits non-zero ends the shell
  # under errexit, and this file is read by every zsh that starts, including
  # `zsh -e -c ...`. With no nvim, no hostname and no uname reachable, every
  # substitution in the file fails at once: the file must still finish.
  out="$(PATH="$MOCK_BIN" "$zsh_bin" -f -e -c "unset EDITOR VISUAL; . '$TEEUP_PATH/capabilities/zsh/default/env'; print -r -- reached-the-end" 2>/dev/null)" || rc=$?
  assert_success "$rc" "errexit must not abort the shell layer" || return 1
  assert_contains "$out" "reached-the-end" || return 1
  cleanup_test_env
}

# The last of the chezmoi repo's ~/.config/shell/envs. Sourced rather than
# grepped, because what matters is the value a shell ends up with, and the
# PATH helpers only add a directory that exists.
test_env_layer_carries_the_cargo_and_go_paths() {
  setup
  local env_file="$TEEUP_PATH/capabilities/zsh/default/env"
  mkdir -p "$TEST_HOME/.cargo/bin" "$TEST_HOME/Development/GoWorkspace/bin"
  local out
  out="$(HOME="$TEST_HOME" PATH="/usr/bin:/bin" bash -c 'set -eu; . "$1"; printf "%s\n%s\n" "$PATH" "${GOPATH:-unset}"' _ "$env_file")"
  assert_contains "$out" "$TEST_HOME/.cargo/bin" "cargo install puts binaries there and no shim covers them" || return 1
  assert_contains "$out" "$TEST_HOME/Development/GoWorkspace" "GOPATH pins a location rather than taking Go's ~/go default" || return 1
  cleanup_test_env
}

# Doom's CLI is not on PATH otherwise: `doom sync` said "command not found"
# right after teeup installed Doom on a real Mac (2026-09-26).
test_env_layer_puts_the_doom_cli_on_path() {
  setup
  local env_file="$TEEUP_PATH/capabilities/zsh/default/env"
  mkdir -p "$TEST_HOME/.config/emacs/bin"
  local out
  out="$(HOME="$TEST_HOME" PATH="/usr/bin:/bin" bash -c 'set -eu; unset XDG_CONFIG_HOME; . "$1"; printf "%s\n" "$PATH"' _ "$env_file")"
  assert_contains "$out" "$TEST_HOME/.config/emacs/bin" "doom sync and doom doctor must resolve" || return 1
  cleanup_test_env
}

# ~/.local/bin must still win over ~/.cargo/bin: teeup's own wrappers live
# there, and a cargo-installed binary of the same name must not shadow one.
test_env_layer_keeps_local_bin_ahead_of_cargo() {
  setup
  local env_file="$TEEUP_PATH/capabilities/zsh/default/env"
  mkdir -p "$TEST_HOME/.cargo/bin" "$TEST_HOME/.local/bin"
  local path_out local_pos cargo_pos
  path_out="$(HOME="$TEST_HOME" PATH="/usr/bin:/bin" bash -c 'set -eu; . "$1"; printf "%s" "$PATH"' _ "$env_file")"
  local_pos="$(printf '%s' "$path_out" | awk -v p="$TEST_HOME/.local/bin" '{print index($0, p)}')"
  cargo_pos="$(printf '%s' "$path_out" | awk -v p="$TEST_HOME/.cargo/bin" '{print index($0, p)}')"
  [[ "$local_pos" -gt 0 && "$cargo_pos" -gt 0 ]] || { echo "both directories must be on PATH"; return 1; }
  # The tildes are prose in a failure message, not paths to expand.
  # shellcheck disable=SC2088
  [[ "$local_pos" -lt "$cargo_pos" ]] || { echo "~/.local/bin must come before ~/.cargo/bin"; return 1; }
  cleanup_test_env
}

# The teeup shims stay last on PATH -- capabilities/teeup-runtime/doctor
# checks exactly that -- so anything added here has to go above them.
test_env_layer_keeps_the_shims_last() {
  setup
  local env_file="$TEEUP_PATH/capabilities/zsh/default/env"
  mkdir -p "$TEST_HOME/.cargo/bin" "$TEST_HOME/Development/GoWorkspace/bin" \
           "$TEST_HOME/.local/state/teeup/shims"
  local path_out
  path_out="$(HOME="$TEST_HOME" PATH="/usr/bin:/bin" bash -c 'set -eu; . "$1"; printf "%s" "$PATH"' _ "$env_file")"
  case "$path_out" in
    *"$TEST_HOME/.local/state/teeup/shims") ;;
    *) echo "the teeup shims must be the final PATH entry; got: $path_out"; return 1 ;;
  esac
  cleanup_test_env
}

# Self-maintained Emacs packages. The live chezmoi repo resolves each variable
# independently across the candidate roots and only stops once all three are
# found -- a machine with the checkouts split across two roots still gets all
# of them. Breaking at the first root that exists would silently lose the rest.
test_env_layer_finds_emacs_packages_across_two_roots() {
  setup
  local env_file="$TEEUP_PATH/capabilities/zsh/default/env"
  mkdir -p "$TEST_HOME/Work/environment/emacs/packages/sdkman.el"
  mkdir -p "$TEST_HOME/Work/products/emacs-packages/trustrail.el"
  mkdir -p "$TEST_HOME/Work/products/emacs-packages/wordwise.el"
  local out
  out="$(HOME="$TEST_HOME" PATH="/usr/bin:/bin" bash -c 'set -eu; . "$1"; printf "%s\n%s\n%s\n" "${SDKMAN_EL_DIR:-unset}" "${TRUSTRAIL_EL_DIR:-unset}" "${WORDWISE_EL_DIR:-unset}"' _ "$env_file")"
  assert_contains "$out" "$TEST_HOME/Work/environment/emacs/packages/sdkman.el" || return 1
  assert_contains "$out" "$TEST_HOME/Work/products/emacs-packages/trustrail.el" "a variable must keep looking past the first root that exists" || return 1
  assert_contains "$out" "$TEST_HOME/Work/products/emacs-packages/wordwise.el" || return 1
  cleanup_test_env
}

# With no checkout anywhere, every variable stays unset and the Emacs config
# installs the packages from GitHub instead.
test_env_layer_leaves_emacs_package_variables_unset_without_a_checkout() {
  setup
  local env_file="$TEEUP_PATH/capabilities/zsh/default/env"
  local out
  out="$(HOME="$TEST_HOME" PATH="/usr/bin:/bin" bash -c 'set -eu; . "$1"; printf "%s\n%s\n%s\n" "${SDKMAN_EL_DIR:-unset}" "${TRUSTRAIL_EL_DIR:-unset}" "${WORDWISE_EL_DIR:-unset}"' _ "$env_file")"
  assert_equals "unset
unset
unset" "$out" || return 1
  cleanup_test_env
}

test_alias_layer_carries_the_last_chezmoi_aliases() {
  setup
  local alias_file="$TEEUP_PATH/capabilities/zsh/default/aliases"
  assert_contains "$(cat "$alias_file")" "cd.." || return 1
  # The colima aliases are guarded on colima being there, so the guard is what
  # is asserted rather than the aliases being defined unconditionally.
  assert_contains "$(cat "$alias_file")" "colima-start" || return 1
  assert_contains "$(cat "$alias_file")" 'command -v colima' "they must not be defined on a machine with no colima" || return 1
  cleanup_test_env
}

run_test "doctor requires an active source not just the path" test_doctor_requires_an_active_source_not_just_the_path
run_test "doctor accepts the shipped two-line source" test_doctor_accepts_the_shipped_two_line_source
run_test "install gets the plugins and switches the login shell" test_install_gets_the_plugins_and_switches_the_login_shell
run_test "install leaves an existing zsh login shell alone" test_install_leaves_an_existing_zsh_login_shell_alone
run_test "configure installs the thin home files" test_configure_installs_the_thin_home_files
run_test "configure bakes the absolute env path for a custom XDG_CONFIG_HOME" test_configure_bakes_the_absolute_env_path_for_a_custom_xdg_config_home
run_test "configure bakes the absolute local.zsh path for a custom XDG_CONFIG_HOME" test_configure_bakes_the_absolute_local_zsh_path_for_a_custom_xdg_config_home
run_test "configure quotes a path with shell metacharacters" test_configure_quotes_a_path_with_shell_metacharacters
run_test "reset renders the home files again" test_reset_renders_the_home_files_again
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
run_test "default env moves the shims last under a macports machine file" test_default_env_moves_the_shims_last_under_a_macports_machine_file
run_test "default env editor ignores a lazy shim" test_default_env_editor_ignores_a_lazy_shim
run_test "env survives errexit without nvim" test_env_survives_errexit_without_nvim
run_test "default env prefers the user's own machine file over the repo's" test_default_env_prefers_the_users_own_machine_file_over_the_repos
run_test "rc exports appearance and sources the theme env" test_rc_exports_appearance_and_sources_the_theme_env
run_test "rc reports light when defaults exits non-zero" test_rc_reports_light_when_defaults_exits_nonzero
run_test "rc does not grow fpath on a second source" test_rc_does_not_grow_fpath_on_a_second_source
run_test "rc leaves git revision syntax alone" test_rc_leaves_git_revision_syntax_alone
run_test "doctor passes after configure" test_doctor_passes_after_configure
run_test "doctor reports a login shell that is not zsh" test_doctor_reports_a_login_shell_that_is_not_zsh
run_test "doctor reports a home file that lost the layer" test_doctor_reports_a_home_file_that_lost_the_teeup_layer
run_test "doctor does not count a commented-out source line" test_doctor_does_not_count_a_commented_out_source_line
run_test "doctor checks the login shell exists" test_doctor_checks_the_login_shell_exists
run_test "doctor reports a missing home file" test_doctor_reports_a_missing_home_file
run_test "doctor reports an unreadable home file, not a replaceable one" test_doctor_reports_an_unreadable_home_file_not_a_replaceable_one
run_test "doctor says dscl could not answer when it fails" test_doctor_says_dscl_could_not_answer_when_it_fails
run_test "doctor says dscl could not answer when it is blank" test_doctor_says_dscl_could_not_answer_when_it_is_blank
run_test "env layer carries the cargo and go paths" test_env_layer_carries_the_cargo_and_go_paths
run_test "env layer puts the doom cli on path" test_env_layer_puts_the_doom_cli_on_path
run_test "env layer keeps local bin ahead of cargo" test_env_layer_keeps_local_bin_ahead_of_cargo
run_test "env layer keeps the shims last" test_env_layer_keeps_the_shims_last
run_test "env layer finds emacs packages across two roots" test_env_layer_finds_emacs_packages_across_two_roots
run_test "env layer leaves emacs package variables unset without a checkout" test_env_layer_leaves_emacs_package_variables_unset_without_a_checkout
run_test "alias layer carries the last chezmoi aliases" test_alias_layer_carries_the_last_chezmoi_aliases
run_test "doctor flags Oh My Zsh, p10k files and a live rc line" test_doctor_flags_oh_my_zsh_p10k_files_and_a_live_rc_line
run_test "doctor leftover fixes survive a home with a space" test_doctor_leftover_fixes_survive_a_home_with_a_space
run_test "doctor is clean once migrate has run" test_doctor_stops_flagging_leftovers_once_migrate_has_neutralised_them
run_test "doctor is clean after migrate keeps an && opener" test_doctor_is_clean_after_migrate_keeps_an_and_opener
run_test "doctor flags a chezmoi source directory" test_doctor_flags_a_chezmoi_source_directory_that_still_points_here
run_test "doctor reports unknown when chezmoi fails" test_doctor_reports_unknown_when_chezmoi_fails
print_summary
