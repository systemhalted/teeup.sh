#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# jq is resolved before setup_test_env narrows PATH (mirrors tests/lib/json.sh
# and tests/capabilities/zed.sh): the hooks call it by bare name, and
# Homebrew's copy is hidden on the macOS runners once PATH is narrowed. A
# machine without jq skips this suite with a note instead of failing it
# ("All new suites" ruling).
JQ_BIN="$(command -v jq || true)"
if [[ -z "$JQ_BIN" ]]; then
  echo "capabilities/vscode"
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
  # The code CLI: lists what $HOME/code-extensions holds, one id per line.
  mock_command_script code <<'EOF2'
case "$1" in
  --list-extensions) cat "$HOME/code-extensions" 2>/dev/null || true ;;
  *) : ;;
esac
exit 0
EOF2
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  TEEUP="$TEEUP_PATH/bin/teeup"
  # The real location, space included: ~/Library/Application Support/Code/User.
  SETTINGS="$TEST_HOME/Library/Application Support/Code/User/settings.json"
}

# mark_installed: what `teeup install vscode` records after configure.
mark_installed() {
  mkdir -p "$TEST_HOME/.local/state/teeup/done"
  : > "$TEST_HOME/.local/state/teeup/done/cap-vscode"
}

read_setting() { jq -r "$1" "$SETTINGS"; }

test_vscode_is_lazy_and_provides_code() {
  setup || return 1
  source "$TEEUP_PATH/lib/all.sh"
  assert_equals "lazy" "$(cap_meta_get vscode tier)" || return 1
  assert_equals "code" "$(cap_meta_get vscode provides)" || return 1
  assert_equals "Visual Studio Code" "$(cap_meta_get vscode apps)" || return 1
  if grep -qx vscode "$TEEUP_PATH/capabilities/daily.list" "$TEEUP_PATH/capabilities/core.list"; then
    echo "vscode is lazy but sits in a tier list"
    return 1
  fi
  cleanup_test_env
}

test_install_dry_run_gets_the_cask() {
  setup || return 1
  local out
  out="$(DRY_RUN=true "$TEEUP" install vscode)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask visual-studio-code" || return 1
  cleanup_test_env
}

test_install_warns_on_macports() {
  setup || return 1
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install vscode 2>&1)"
  assert_contains "$out" "Visual Studio Code is a cask and MacPorts has no port of it" || return 1
  assert_not_contains "$out" "brew install --cask" || return 1
  cleanup_test_env
}

test_configure_writes_themes_font_and_installs_the_extension() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  DRY_RUN=false "$TEEUP" configure vscode >/dev/null
  assert_file_exists "$SETTINGS" || return 1
  assert_equals "true" "$(read_setting '.["window.autoDetectColorScheme"]')" || return 1
  assert_equals "Catppuccin Mocha" "$(read_setting '.["workbench.preferredDarkColorTheme"]')" || return 1
  assert_equals "Catppuccin Latte" "$(read_setting '.["workbench.preferredLightColorTheme"]')" || return 1
  assert_equals "'JetBrainsMono Nerd Font', Menlo, Monaco, 'Courier New', monospace" "$(read_setting '.["editor.fontFamily"]')" || return 1
  assert_equals "null" "$(read_setting '.workbench')" "dotted keys stay flat" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "code --install-extension Catppuccin.catppuccin-vsc" || return 1
  cleanup_test_env
}

test_an_installed_extension_is_not_reinstalled() {
  setup || return 1
  printf 'ms-python.python\ncatppuccin.catppuccin-vsc\n' > "$TEST_HOME/code-extensions"
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure vscode)"
  assert_contains "$out" "Already installed: VS Code extension Catppuccin.catppuccin-vsc" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "code --install-extension" || return 1
  cleanup_test_env
}

test_without_the_code_command_the_extension_is_a_hint() {
  setup || return 1
  export TEEUP_TEST_MISSING="code"
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure vscode)"
  assert_contains "$out" "install the Catppuccin.catppuccin-vsc extension from the Extensions view" || return 1
  assert_equals "Catppuccin Mocha" "$(read_setting '.["workbench.preferredDarkColorTheme"]')" "the settings are still written" || return 1
  cleanup_test_env
}

# B1: on a MacPorts Mac with no app bundle anywhere, vscode is not
# applicable -- teeup status must not claim it installed once the install
# step already said the editor cannot be installed.
test_configure_is_not_applicable_on_macports_without_the_app() {
  setup || return 1
  source "$TEEUP_PATH/lib/all.sh"
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  DRY_RUN=false cap_install_verbs vscode >/dev/null 2>&1
  state_done check "cap-vscode" && { echo "must not be marked done"; return 1; }
  state_na check "cap-vscode" || { echo "must be marked not-applicable"; return 1; }
  DRY_RUN=false "$TEEUP" has vscode >/dev/null 2>&1 && { echo "has must report not-installed"; return 1; }
  local out
  out="$(DRY_RUN=false "$TEEUP" status)"
  assert_contains "$out" "not applicable on this machine" || return 1
  assert_not_contains "$out" "vscode             installed" || return 1
  cleanup_test_env
}

# B1's other half: the settings-file work is still worth keeping, so a
# hand-downloaded VS Code on the same MacPorts Mac is reported installed.
test_configure_reports_installed_with_a_hand_downloaded_app_on_macports() {
  setup || return 1
  source "$TEEUP_PATH/lib/all.sh"
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  mkdir -p "$TEEUP_APPS_DIR/Visual Studio Code.app"
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  DRY_RUN=false cap_install_verbs vscode >/dev/null 2>&1
  state_done check "cap-vscode" || { echo "must be marked done"; return 1; }
  state_na check "cap-vscode" && { echo "must not be marked not-applicable"; return 1; }
  DRY_RUN=false "$TEEUP" has vscode || { echo "has must report installed"; return 1; }
  assert_equals "true" "$(read_setting '.["window.autoDetectColorScheme"]')" "the settings are still written" || return 1
  cleanup_test_env
}

# I2: a user theme's extension id is allowed to contain a space
# (TEEUP_PALETTE_VALUE_RE), but it is never a real VS Code extension id, so
# it must be skipped with a warning instead of word-splitting into bogus
# extensions.
test_an_extension_id_with_a_space_is_skipped_not_split() {
  setup || return 1
  mark_installed
  local theme="$TEST_HOME/.config/teeup/themes/spacey"
  mkdir -p "$theme"
  sed -e 's/^vscode_extension = .*/vscode_extension = "Cat Puccin vsc"/' \
    "$TEEUP_PATH/themes/catppuccin/dark.toml" > "$theme/dark.toml"
  sed -e 's/^vscode_extension = .*/vscode_extension = "Cat Puccin vsc"/' \
    "$TEEUP_PATH/themes/catppuccin/light.toml" > "$theme/light.toml"
  local out
  out="$(DRY_RUN=false "$TEEUP" theme set spacey 2>&1)"
  assert_contains "$out" "Ignoring extension id with a space: 'Cat Puccin vsc'" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "code --install-extension" "no bogus extension was installed" || return 1
  cleanup_test_env
}

# M3: a settings file that is correctly declined (a symlink into a dotfiles
# repo) must not make cap_run_optional print a false "theme-apply failed",
# and the rest of the hook must still run rather than being cut off by set
# -e at the first refusal.
test_theme_apply_continues_past_a_symlinked_settings_file() {
  setup || return 1
  mark_installed
  mkdir -p "$(dirname "$SETTINGS")"
  printf '{}\n' > "$TEST_HOME/dotfiles-vscode-settings.json"
  ln -s "$TEST_HOME/dotfiles-vscode-settings.json" "$SETTINGS"
  local out warnings
  out="$(DRY_RUN=false "$TEEUP" theme set catppuccin 2>&1)"
  assert_not_contains "$out" "vscode theme-apply failed" "the hook's own warning already said why" || return 1
  warnings="$(printf '%s\n' "$out" | grep -c "is a symlink; teeup does not write through it" || true)"
  assert_equals "3" "$warnings" "the color-scheme flag and both theme keys must all be attempted" || return 1
  [[ -L "$SETTINGS" ]] || { echo "the symlink was replaced"; return 1; }
  assert_equals "{}" "$(cat "$TEST_HOME/dotfiles-vscode-settings.json")" "the link's target is untouched" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  DRY_RUN=false "$TEEUP" configure vscode >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure vscode)"
  assert_contains "$out" "Already current: $SETTINGS" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=true "$TEEUP" configure vscode)"
  assert_contains "$out" "[DRY-RUN] Would write $SETTINGS (window.autoDetectColorScheme)" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: code --install-extension Catppuccin.catppuccin-vsc" || return 1
  [[ ! -e "$SETTINGS" ]] || { echo "settings written in dry run"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "code --install-extension" || return 1
  cleanup_test_env
}

test_the_users_settings_survive() {
  setup || return 1
  mkdir -p "$(dirname "$SETTINGS")"
  # A hand-edited file with a comment and a trailing comma, both of which VS
  # Code accepts: the keys survive and the original is backed up.
  cat > "$SETTINGS" <<'EOF2'
{
    // mine
    "editor.fontSize": 13,
    "workbench.colorTheme": "Abyss",
}
EOF2
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  DRY_RUN=false "$TEEUP" configure vscode >/dev/null
  assert_equals "13" "$(read_setting '.["editor.fontSize"]')" || return 1
  assert_equals "Abyss" "$(read_setting '.["workbench.colorTheme"]')" "the manual theme key is not teeup's to change" || return 1
  assert_equals "Catppuccin Mocha" "$(read_setting '.["workbench.preferredDarkColorTheme"]')" || return 1
  ls "$SETTINGS".teeup_backup_* >/dev/null 2>&1 || { echo "the commented original was not backed up"; return 1; }
  cleanup_test_env
}

test_hooks_leave_an_uninstalled_vscode_alone() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  DRY_RUN=false "$TEEUP" install font Hack >/dev/null
  [[ ! -e "$TEST_HOME/Library/Application Support/Code" ]] || { echo "a hook wrote settings for a VS Code teeup never installed"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "code --" "not even the extension list is read" || return 1
  cleanup_test_env
}

test_theme_set_and_install_font_update_an_installed_vscode() {
  setup || return 1
  mark_installed
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  assert_equals "Catppuccin Latte" "$(read_setting '.["workbench.preferredLightColorTheme"]')" || return 1
  DRY_RUN=false "$TEEUP" install font Hack >/dev/null
  assert_equals "'Hack Nerd Font', Menlo, Monaco, 'Courier New', monospace" "$(read_setting '.["editor.fontFamily"]')" || return 1
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
  out="$(DRY_RUN=false "$TEEUP" configure vscode 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  # Twice: theme-apply and font-apply each refuse on their own.
  warnings="$(printf '%s\n' "$out" | grep -c "jq is not installed; cannot write $SETTINGS" || true)"
  assert_equals "2" "$warnings" || return 1
  [[ ! -e "$SETTINGS" ]] || { echo "settings written without jq"; return 1; }
  unset TEEUP_TEST_MISSING
  cleanup_test_env
}

test_theme_renders_the_vscode_names() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  local light
  light="$TEST_HOME/.local/state/teeup/current/theme/light/vscode.json"
  assert_file_exists "$light" || return 1
  assert_equals "Catppuccin Latte" "$(jq -r .theme "$light")" || return 1
  assert_equals "Catppuccin.catppuccin-vsc" "$(jq -r .extension "$light")" || return 1
  cleanup_test_env
}

echo "capabilities/vscode"
run_test "vscode is lazy and provides code" test_vscode_is_lazy_and_provides_code
run_test "install dry run gets the cask" test_install_dry_run_gets_the_cask
run_test "install warns on macports" test_install_warns_on_macports
run_test "configure writes themes, font and installs the extension" test_configure_writes_themes_font_and_installs_the_extension
run_test "an installed extension is not reinstalled" test_an_installed_extension_is_not_reinstalled
run_test "without the code command the extension is a hint" test_without_the_code_command_the_extension_is_a_hint
run_test "configure is not applicable on MacPorts without the app" test_configure_is_not_applicable_on_macports_without_the_app
run_test "configure reports installed with a hand-downloaded app on MacPorts" test_configure_reports_installed_with_a_hand_downloaded_app_on_macports
run_test "an extension id with a space is skipped, not split" test_an_extension_id_with_a_space_is_skipped_not_split
run_test "theme-apply continues past a symlinked settings file" test_theme_apply_continues_past_a_symlinked_settings_file
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "the user's settings survive" test_the_users_settings_survive
run_test "hooks leave an uninstalled VS Code alone" test_hooks_leave_an_uninstalled_vscode_alone
run_test "theme set and install font update an installed VS Code" test_theme_set_and_install_font_update_an_installed_vscode
run_test "hooks without jq warn and continue" test_hooks_without_jq_warn_and_continue
run_test "theme renders the vscode names" test_theme_renders_the_vscode_names
print_summary
