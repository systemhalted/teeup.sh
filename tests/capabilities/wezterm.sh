#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  TEEUP="$TEEUP_PATH/bin/teeup"
  WEZ="$TEST_HOME/.config/wezterm"
}

test_install_dry_run_gets_the_cask() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install wezterm)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask wezterm" || return 1
  cleanup_test_env
}

test_install_falls_back_to_a_port_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install wezterm 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: sudo port install wezterm" || return 1
  assert_not_contains "$out" "brew install --cask" || return 1
  cleanup_test_env
}

test_configure_installs_both_user_files() {
  setup
  DRY_RUN=false "$TEEUP" configure wezterm >/dev/null
  assert_file_exists "$WEZ/wezterm.lua" || return 1
  assert_file_exists "$WEZ/local.lua" || return 1
  assert_contains "$(cat "$WEZ/wezterm.lua")" 'pcall(require, "teeup.wezterm")' || return 1
  assert_contains "$(cat "$WEZ/wezterm.lua")" "capabilities/wezterm/default/?.lua" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  DRY_RUN=false "$TEEUP" configure wezterm >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure wezterm)"
  assert_contains "$out" "Already installed: $WEZ/wezterm.lua" || return 1
  assert_contains "$out" "Already installed: $WEZ/local.lua" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  DRY_RUN=true "$TEEUP" configure wezterm >/dev/null
  [[ ! -e "$WEZ/wezterm.lua" ]] || { echo "config written in dry run"; return 1; }
  cleanup_test_env
}

test_theme_apply_reloads_the_config() {
  setup
  DRY_RUN=false "$TEEUP" configure wezterm >/dev/null
  local out
  out="$(DRY_RUN=true "$TEEUP" theme set catppuccin 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: touch $WEZ/wezterm.lua" || return 1
  cleanup_test_env
}

test_font_apply_reloads_the_config() {
  setup
  DRY_RUN=false "$TEEUP" configure wezterm >/dev/null
  local out
  out="$(DRY_RUN=true "$TEEUP" install font Hack 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: touch $WEZ/wezterm.lua" || return 1
  cleanup_test_env
}

test_theme_renders_a_wezterm_scheme() {
  setup
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  local scheme
  scheme="$TEST_HOME/.local/state/teeup/current/theme/dark/wezterm.lua"
  assert_file_exists "$scheme" || return 1
  assert_contains "$(cat "$scheme")" 'background = "#1e1e2e"' || return 1
  assert_not_contains "$(cat "$scheme")" "{{" "every token was substituted" || return 1
  cleanup_test_env
}

test_lua_files_parse() {
  setup
  # This is the only gate on three shipped Lua files and the rendered scheme,
  # so a missing luac is a failure, not a skip. CI installs lua5.4 / lua.
  if ! command -v luac >/dev/null 2>&1; then
    echo "luac is not installed: install lua5.4 (apt) or lua (brew) to run this suite"
    cleanup_test_env
    return 1
  fi
  DRY_RUN=false "$TEEUP" configure wezterm >/dev/null
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  local f rc=0
  for f in "$TEEUP_PATH/capabilities/wezterm/config/wezterm/wezterm.lua" \
           "$TEEUP_PATH/capabilities/wezterm/config/wezterm/local.lua" \
           "$TEEUP_PATH/capabilities/wezterm/default/teeup/wezterm.lua" \
           "$TEST_HOME/.local/state/teeup/current/theme/dark/wezterm.lua" \
           "$TEST_HOME/.local/state/teeup/current/theme/light/wezterm.lua"; do
    luac -p "$f" || { echo "Lua syntax error in $f"; rc=1; }
  done
  cleanup_test_env
  return $rc
}

# teeup-runtime writes ~/.config/teeup/env with every value passed through
# bash's `printf '%q'` (capabilities/teeup-runtime/configure), which
# backslash-escapes a space rather than quoting the whole value:
# `export TEEUP_PATH=/Users/ada/My\ Code/teeup`. The thin config has to undo
# that escaping for both TEEUP_PATH and TEEUP_STATE_DIR, or a checkout/state
# dir with a space in it resolves to the wrong (truncated) path.
#
# WezTerm itself is not installed here, so this stands up a minimal fake
# `wezterm` Lua module (just enough of the API surface the two shipped files
# touch while building a config) and runs the real, configured
# ~/.config/wezterm/wezterm.lua under a plain Lua interpreter. Success is
# `config.font[1].family` reading back the font this test wrote under the
# space-containing state dir; teeup.wezterm failing to load falls back to a
# flat `{ "JetBrainsMono Nerd Font" }` list instead, which the assertions
# below rule out.
test_teeup_path_and_state_dir_survive_a_space() {
  setup
  DRY_RUN=false "$TEEUP" configure wezterm >/dev/null

  local lua_bin
  lua_bin="$(command -v lua || command -v lua5.4 || command -v lua5.3 || true)"
  if [[ -z "$lua_bin" ]]; then
    echo "no lua interpreter installed: install lua5.4 (apt) or lua (brew) to run this test"
    cleanup_test_env
    return 1
  fi

  local checkout="$TEST_HOME/My Checkout/teeup"
  local state="$TEST_HOME/My State/teeup"
  mkdir -p "$checkout/capabilities/wezterm/default/teeup"
  cp "$TEEUP_PATH/capabilities/wezterm/default/teeup/wezterm.lua" \
    "$checkout/capabilities/wezterm/default/teeup/wezterm.lua"
  mkdir -p "$state/current"
  echo "SpaceTestFont" > "$state/current/font"

  mkdir -p "$TEST_HOME/.config/teeup"
  {
    printf 'export TEEUP_PATH=%s\n' "$(printf '%q' "$checkout")"
    printf 'export TEEUP_STATE_DIR=%s\n' "$(printf '%q' "$state")"
  } > "$TEST_HOME/.config/teeup/env"

  local fake_dir driver out
  fake_dir="$(mktemp -d)"
  cat > "$fake_dir/wezterm.lua" <<'FAKE'
local M = {}
M.home_dir = os.getenv("WEZTERM_TEST_HOME") or "/tmp"
M.config_dir = os.getenv("WEZTERM_TEST_CONFIG_DIR") or "/tmp"
M.log_error = function(msg) io.stderr:write("LOG_ERROR: " .. tostring(msg) .. "\n") end
M.on = function() end
M.action_callback = function(fn) return fn end
M.config_builder = function() return {} end
M.font_with_fallback = function(specs) return specs end
M.add_to_config_reload_watch_list = function() end
M.default_hyperlink_rules = function() return {} end
M.action = setmetatable({}, { __index = function() return function(...) return {} end end })
return M
FAKE

  driver="$(mktemp)"
  cat > "$driver" <<DRIVER
package.path = "$fake_dir/?.lua;" .. package.path
local config = dofile("$WEZ/wezterm.lua")
if type(config.font) == "table" and type(config.font[1]) == "table" then
  print("FONT_FAMILY=" .. tostring(config.font[1].family))
else
  print("FONT_FAMILY=" .. tostring(config.font and config.font[1]))
end
DRIVER

  out="$(
    unset TEEUP_PATH TEEUP_STATE_DIR
    WEZTERM_TEST_HOME="$TEST_HOME" WEZTERM_TEST_CONFIG_DIR="$WEZ" \
      XDG_CONFIG_HOME="$TEST_HOME/.config" "$lua_bin" "$driver" 2>&1
  )"
  rm -rf "$fake_dir"
  rm -f "$driver"

  assert_contains "$out" "FONT_FAMILY=SpaceTestFont" "a TEEUP_PATH/TEEUP_STATE_DIR with a space should resolve" || return 1
  assert_not_contains "$out" "LOG_ERROR" "teeup.wezterm should have loaded from the space-containing checkout" || return 1
  cleanup_test_env
}

echo "capabilities/wezterm"
run_test "install dry run gets the cask" test_install_dry_run_gets_the_cask
run_test "install falls back to a port on macports" test_install_falls_back_to_a_port_on_macports
run_test "configure installs both user files" test_configure_installs_both_user_files
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "theme-apply reloads the config" test_theme_apply_reloads_the_config
run_test "font-apply reloads the config" test_font_apply_reloads_the_config
run_test "theme renders a wezterm scheme" test_theme_renders_a_wezterm_scheme
run_test "shipped and rendered Lua parses" test_lua_files_parse
run_test "TEEUP_PATH and TEEUP_STATE_DIR survive a space" test_teeup_path_and_state_dir_survive_a_space
print_summary
