#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# jq is resolved before setup_test_env narrows PATH (mirrors tests/lib/json.sh):
# the hooks call it by bare name, and Homebrew's copy is hidden on the macOS
# runners once PATH is narrowed. A machine without jq skips this suite with a
# note instead of failing it ("All new suites" ruling).
JQ_BIN="$(command -v jq || true)"
if [[ -z "$JQ_BIN" ]]; then
  echo "capabilities/zed"
  echo "jq is not installed: skipping this suite (install jq to run it)"
  exit 0
fi

setup() {
  setup_test_env
  mock_macos_base
  ln -s "$JQ_BIN" "$MOCK_BIN/jq"
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  TEEUP="$TEEUP_PATH/bin/teeup"
  SETTINGS="$TEST_HOME/.config/zed/settings.json"
}

# mark_installed: what `teeup install zed` records after configure.
mark_installed() {
  mkdir -p "$TEST_HOME/.local/state/teeup/done"
  : > "$TEST_HOME/.local/state/teeup/done/cap-zed"
}

# read_setting <jq filter>: the settings file minus Zed's header comments.
read_setting() { sed '/^[[:space:]]*\/\//d' "$SETTINGS" | jq -r "$1"; }

test_install_dry_run_gets_the_cask() {
  setup || return 1
  local out
  out="$(DRY_RUN=true "$TEEUP" install zed)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask zed" || return 1
  cleanup_test_env
}

test_install_never_takes_the_macports_zed() {
  setup || return 1
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install zed 2>&1)"
  assert_contains "$out" "Zed is a cask and MacPorts has no port of the editor" || return 1
  assert_not_contains "$out" "port install zed" "MacPorts' zed is a different program" || return 1
  cleanup_test_env
}

test_configure_writes_theme_font_and_extension() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  DRY_RUN=false "$TEEUP" configure zed >/dev/null
  assert_file_exists "$SETTINGS" || return 1
  assert_equals "system" "$(read_setting .theme.mode)" || return 1
  assert_equals "Catppuccin Mocha" "$(read_setting .theme.dark)" || return 1
  assert_equals "Catppuccin Latte" "$(read_setting .theme.light)" || return 1
  assert_equals "true" "$(read_setting .auto_install_extensions.catppuccin)" || return 1
  assert_equals "JetBrainsMono Nerd Font" "$(read_setting .buffer_font_family)" || return 1
  cleanup_test_env
}

test_configure_before_a_theme_still_sets_the_font() {
  setup || return 1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure zed 2>&1)"
  assert_contains "$out" "No rendered Zed theme" || return 1
  assert_equals "JetBrainsMono Nerd Font" "$(read_setting .buffer_font_family)" || return 1
  assert_equals "null" "$(read_setting .theme)" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  DRY_RUN=false "$TEEUP" configure zed >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure zed)"
  assert_contains "$out" "Already current: $SETTINGS" || return 1
  assert_not_contains "$out" "Wrote $SETTINGS" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  local out
  out="$(DRY_RUN=true "$TEEUP" configure zed)"
  assert_contains "$out" "[DRY-RUN] Would write $SETTINGS (theme)" || return 1
  assert_contains "$out" "[DRY-RUN] Would write $SETTINGS (buffer_font_family)" || return 1
  [[ ! -e "$SETTINGS" ]] || { echo "settings written in dry run"; return 1; }
  cleanup_test_env
}

# Zed does not read XDG_CONFIG_HOME on macOS, and the settings path has to
# survive a home directory with a space and an ampersand in it.
test_the_path_ignores_xdg_config_home_and_survives_a_space() {
  setup || return 1
  export XDG_CONFIG_HOME="$TEST_HOME/elsewhere"
  export HOME="$TEST_HOME/Ada Lovelace & co"
  mkdir -p "$HOME"
  SETTINGS="$HOME/.config/zed/settings.json"
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  DRY_RUN=false "$TEEUP" configure zed >/dev/null
  assert_equals "Catppuccin Mocha" "$(read_setting .theme.dark)" || return 1
  [[ ! -e "$XDG_CONFIG_HOME/zed" ]] || { echo "wrote under XDG_CONFIG_HOME, which Zed never reads"; return 1; }
  cleanup_test_env
}

test_the_users_settings_and_header_survive() {
  setup || return 1
  mkdir -p "$(dirname "$SETTINGS")"
  cat > "$SETTINGS" <<'EOF2'
// Zed settings
//
// For information on how to configure Zed, see the Zed
// documentation: https://zed.dev/docs/configuring-zed
{
  "ui_font_size": 16,
  "buffer_font_size": 15,
  "theme": "One Dark",
  "auto_install_extensions": {
    "html": true,
  },
}
EOF2
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  DRY_RUN=false "$TEEUP" configure zed >/dev/null
  assert_equals "// Zed settings" "$(head -1 "$SETTINGS")" || return 1
  assert_equals "16" "$(read_setting .ui_font_size)" || return 1
  assert_equals "Catppuccin Mocha" "$(read_setting .theme.dark)" "a string theme is replaced by the object" || return 1
  assert_equals "true" "$(read_setting .auto_install_extensions.html)" "the user's extension stays" || return 1
  assert_equals "true" "$(read_setting .auto_install_extensions.catppuccin)" || return 1
  cleanup_test_env
}

test_hooks_leave_an_uninstalled_zed_alone() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  DRY_RUN=false "$TEEUP" install font Hack >/dev/null
  [[ ! -e "$SETTINGS" ]] || { echo "theme set wrote settings for a Zed teeup never installed"; return 1; }
  cleanup_test_env
}

test_theme_set_and_install_font_update_an_installed_zed() {
  setup || return 1
  mark_installed
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  assert_equals "Catppuccin Latte" "$(read_setting .theme.light)" || return 1
  DRY_RUN=false "$TEEUP" install font Hack >/dev/null
  assert_equals "Hack Nerd Font" "$(read_setting .buffer_font_family)" || return 1
  cleanup_test_env
}

test_an_extension_named_none_is_not_installed() {
  setup || return 1
  local theme="$TEST_HOME/.config/teeup/themes/plain"
  mkdir -p "$theme"
  sed -e 's/^zed_theme = .*/zed_theme = "One Dark"/' -e 's/^zed_extension = .*/zed_extension = "none"/' \
    "$TEEUP_PATH/themes/catppuccin/dark.toml" > "$theme/dark.toml"
  sed -e 's/^zed_theme = .*/zed_theme = "One Light"/' -e 's/^zed_extension = .*/zed_extension = "none"/' \
    "$TEEUP_PATH/themes/catppuccin/light.toml" > "$theme/light.toml"
  DRY_RUN=false "$TEEUP" theme set plain >/dev/null
  DRY_RUN=false "$TEEUP" configure zed >/dev/null
  assert_equals "One Dark" "$(read_setting .theme.dark)" || return 1
  assert_equals "null" "$(read_setting .auto_install_extensions)" || return 1
  cleanup_test_env
}

test_hooks_without_jq_warn_and_continue() {
  setup || return 1
  # Render the theme while jq is still here: without a rendered theme
  # theme-apply exits earlier, at "no rendered theme", and its own jq guard is
  # never reached -- the warning below would then come from font-apply alone
  # and the assertion would pass with theme-apply's guard deleted.
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  export TEEUP_TEST_MISSING="jq"
  local rc=0 out warnings
  out="$(DRY_RUN=false "$TEEUP" configure zed 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  # Twice: theme-apply and font-apply each refuse on their own.
  warnings="$(printf '%s\n' "$out" | grep -c "jq is not installed; cannot write $SETTINGS" || true)"
  assert_equals "2" "$warnings" || return 1
  [[ ! -e "$SETTINGS" ]] || { echo "settings written without jq"; return 1; }
  unset TEEUP_TEST_MISSING
  cleanup_test_env
}

test_theme_renders_the_zed_names() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  local dark light
  dark="$TEST_HOME/.local/state/teeup/current/theme/dark/zed.json"
  light="$TEST_HOME/.local/state/teeup/current/theme/light/zed.json"
  assert_equals "Catppuccin Mocha" "$(jq -r .theme "$dark")" || return 1
  assert_equals "Catppuccin Latte" "$(jq -r .theme "$light")" || return 1
  assert_equals "catppuccin" "$(jq -r .extension "$dark")" || return 1
  cleanup_test_env
}

echo "capabilities/zed"
run_test "install dry run gets the cask" test_install_dry_run_gets_the_cask
run_test "install never takes the MacPorts zed" test_install_never_takes_the_macports_zed
run_test "configure writes theme, font and extension" test_configure_writes_theme_font_and_extension
run_test "configure before a theme still sets the font" test_configure_before_a_theme_still_sets_the_font
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "the path ignores XDG_CONFIG_HOME and survives a space" test_the_path_ignores_xdg_config_home_and_survives_a_space
run_test "the user's settings and header survive" test_the_users_settings_and_header_survive
run_test "hooks leave an uninstalled Zed alone" test_hooks_leave_an_uninstalled_zed_alone
run_test "theme set and install font update an installed Zed" test_theme_set_and_install_font_update_an_installed_zed
run_test "an extension named none is not installed" test_an_extension_named_none_is_not_installed
run_test "hooks without jq warn and continue" test_hooks_without_jq_warn_and_continue
run_test "theme renders the zed names" test_theme_renders_the_zed_names
print_summary
