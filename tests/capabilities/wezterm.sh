#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# Find lua and luac before the test harness narrows PATH. On macOS, homebrew
# installs these to /opt/homebrew/bin or /usr/local/bin, which won't be in
# the restricted PATH that setup_test_env() establishes.
WEZTERM_LUAC="$(command -v luac || command -v luac5.4 || true)"
WEZTERM_LUA="$(command -v lua || command -v lua5.4 || command -v lua5.3 || true)"

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

# Points MacPorts' applications_dir at a path under $TEST_HOME. Every
# MacPorts test below uses this rather than letting wezterm_macports_apps_dir
# fall through to its real default (/Applications/MacPorts): that path is a
# real, absolute location on whatever machine runs this suite, and a test
# that asserted a bundle there existed (or didn't) would either have to
# create files outside $TEST_HOME or gamble that the runner never has a real
# MacPorts WezTerm install to trip over.
wezterm_set_macports_apps_dir() {
  mkdir -p "$TEEUP_PKG_PREFIX/etc/macports"
  printf 'applications_dir\t%s\n' "$1" > "$TEEUP_PKG_PREFIX/etc/macports/macports.conf"
}

# MacPorts moves the built app bundle into applications_dir rather than
# /Applications, and Launchpad only indexes /Applications, so a MacPorts
# install of WezTerm is real but invisible there -- when the bundle is
# actually there to say that about. This must not fire on Homebrew, where
# the cask lands in /Applications.
test_configure_names_the_macports_app_location() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local apps_dir="$TEST_HOME/FakeApps"
  wezterm_set_macports_apps_dir "$apps_dir"
  mkdir -p "$apps_dir/WezTerm.app"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure wezterm 2>&1)"
  assert_contains "$out" "$apps_dir" || return 1
  assert_contains "$out" "WezTerm.app" || return 1
  assert_contains "$out" "open -a" "should say how to actually launch it" || return 1
  cleanup_test_env
}

test_configure_names_the_macports_app_location_in_dry_run_too() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local apps_dir="$TEST_HOME/FakeApps"
  wezterm_set_macports_apps_dir "$apps_dir"
  mkdir -p "$apps_dir/WezTerm.app"
  local out
  out="$(DRY_RUN=true "$TEEUP" configure wezterm 2>&1)"
  assert_contains "$out" "$apps_dir" || return 1
  cleanup_test_env
}

# Review finding on the first round: `install` turns a failed
# `port install wezterm` into a warning and carries on, and `configure` can
# run on its own without `install` ever having run, so the bundle may well
# not be there. Naming a path with `open -a` for a bundle that does not
# exist would directly contradict install's own warning, so say nothing
# instead once the bundle is confirmed missing.
test_configure_says_nothing_when_the_bundle_is_missing() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  wezterm_set_macports_apps_dir "$TEST_HOME/FakeApps"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure wezterm 2>&1)"
  assert_not_contains "$out" "open -a" "must not hand out an open command for a bundle that is not there" || return 1
  assert_not_contains "$out" "$TEST_HOME/FakeApps/WezTerm.app" || return 1
  cleanup_test_env
}

test_configure_says_nothing_when_the_bundle_is_missing_in_dry_run_too() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  wezterm_set_macports_apps_dir "$TEST_HOME/FakeApps"
  local out
  out="$(DRY_RUN=true "$TEEUP" configure wezterm 2>&1)"
  assert_not_contains "$out" "open -a" "must not hand out an open command for a bundle that is not there" || return 1
  cleanup_test_env
}

# The default of /Applications/MacPorts is only macports-base's fallback for
# when applications_dir is unset; a machine that has customised it in
# macports.conf should be told the truth, not the compiled-in default.
test_configure_reads_applications_dir_from_macports_conf() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local apps_dir="$TEST_HOME/CustomApps"
  wezterm_set_macports_apps_dir "$apps_dir"
  mkdir -p "$apps_dir/WezTerm.app"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure wezterm 2>&1)"
  assert_contains "$out" "$apps_dir" || return 1
  assert_not_contains "$out" "/Applications/MacPorts" "the custom applications_dir should win over the compiled-in default" || return 1
  cleanup_test_env
}

test_configure_says_nothing_about_macports_on_homebrew() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure wezterm 2>&1)"
  assert_not_contains "$out" "MacPorts" || return 1
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

# The font entry used to force weight="Medium" on the family table, which
# makes WezTerm warn "Unable to load a font ... An alternative variant of the
# font was requested" on every window whenever the family lacks that exact
# weight file -- true both when the Nerd Font family is entirely missing
# (MacPorts has no cask for it) and when it is present but ships only
# Regular/Bold. WezTerm has no way to prefer a weight without warning when
# that weight is absent, so the fix drops the weight and asks for the plain
# family name, the same style the very next entry in this fallback list
# ("Kohinoor Devanagari") already uses.
test_font_entry_does_not_force_a_weight() {
  local src out
  src="$TEEUP_PATH/capabilities/wezterm/default/teeup/wezterm.lua"
  out="$(cat "$src")"
  assert_not_contains "$out" "weight =" "no font entry should request a specific weight that can be absent" || return 1
  assert_contains "$out" "M.font_family(state_dir)," "the plain family name should still be the first fallback entry" || return 1
}

test_lua_files_parse() {
  setup
  # This is the only gate on three shipped Lua files and the rendered scheme,
  # so a missing luac is a failure, not a skip. CI installs lua5.4 / lua.
  if [[ -z "$WEZTERM_LUAC" ]]; then
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
    "$WEZTERM_LUAC" -p "$f" || { echo "Lua syntax error in $f"; rc=1; }
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

  if [[ -z "$WEZTERM_LUA" ]]; then
    echo "no lua interpreter installed: install lua5.4 (apt) or lua (brew) to run this test"
    cleanup_test_env
    return 1
  fi
  local lua_bin="$WEZTERM_LUA"

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

# capabilities/teeup-runtime/configure writes TEEUP_PATH/TEEUP_STATE_DIR
# through `printf '%q'`, and %q's output shape depends on the bash that ran
# it: a plain backslash-escaped word for ASCII specials (space, ', $), but
# bash 3.2 switches to ANSI-C `$'...'` quoting with octal byte escapes for
# any non-ASCII byte, while bash 5.x keeps raw UTF-8 with backslash escapes
# only on the ASCII specials. An override lets a developer point this at a
# real bash 3.2 binary (there is one already built in this project's CI
# scratchpad); with no override, it uses /bin/bash only if that happens to
# already be bash 3.2, which is exactly what macOS (and so this project's
# macOS CI runners) ships as its system bash. Neither being available skips
# the bash-3.2 variant with a note rather than failing the suite over it.
_wezterm_find_bash32() {
  local candidate
  for candidate in "${TEEUP_TEST_BASH32:-}" /bin/bash; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    if "$candidate" --version 2>/dev/null | head -1 | grep -q 'version 3\.2'; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# Run the real, installed ~/.config/wezterm/wezterm.lua's TEEUP_PATH/
# TEEUP_STATE_DIR resolution (not a reimplementation of it) up to the point
# both are resolved, then hand them back instead of building a whole config:
# the shipped file is one long chunk with no exported functions, so this
# extracts everything through `local teeup_state = teeup_state_dir()`
# (a unique, present-verbatim line in the shipped file) and appends a
# `return`. Requires only a minimal `wezterm` stub (home_dir/config_dir),
# since nothing before that line touches any other part of the WezTerm API.
_wezterm_assert_env_paths_survive() {
  local lua_bin="$1" bash_bin="$2" label="$3" checkout="$4" state="$5"
  local env_file="$TEST_HOME/.config/teeup/env" path_q state_q
  mkdir -p "$TEST_HOME/.config/teeup"
  path_q="$("$bash_bin" -c 'printf "%q" "$1"' _ "$checkout")"
  state_q="$("$bash_bin" -c 'printf "%q" "$1"' _ "$state")"
  {
    printf 'export TEEUP_PATH=%s\n' "$path_q"
    printf 'export TEEUP_STATE_DIR=%s\n' "$state_q"
  } > "$env_file"

  local fake_dir extractor out
  fake_dir="$(mktemp -d)"
  cat > "$fake_dir/wezterm.lua" <<'FAKE'
local M = {}
M.home_dir = os.getenv("WEZTERM_TEST_HOME") or "/tmp"
M.config_dir = os.getenv("WEZTERM_TEST_CONFIG_DIR") or "/tmp"
return M
FAKE

  extractor="$(mktemp)"
  cat > "$extractor" <<'LUAEOF'
local wezterm_file, fake_dir = arg[1], arg[2]
package.path = fake_dir .. "/?.lua;" .. package.path
local f = io.open(wezterm_file, "r")
local src = f:read("*a")
f:close()
local marker = "local teeup_state = teeup_state_dir()"
local idx = src:find(marker, 1, true)
if not idx then
  print("EXTRACT_ERROR=marker not found in " .. wezterm_file)
  os.exit(1)
end
local chunk, err = load(src:sub(1, idx + #marker - 1) .. "\nreturn teeup_root, teeup_state\n")
if not chunk then
  print("LOAD_ERROR=" .. tostring(err))
  os.exit(1)
end
local root, state = chunk()
print("TEEUP_ROOT=" .. tostring(root))
print("TEEUP_STATE=" .. tostring(state))
LUAEOF

  out="$(
    unset TEEUP_PATH TEEUP_STATE_DIR
    WEZTERM_TEST_HOME="$TEST_HOME" WEZTERM_TEST_CONFIG_DIR="$WEZ" \
      XDG_CONFIG_HOME="$TEST_HOME/.config" "$lua_bin" "$extractor" "$WEZ/wezterm.lua" "$fake_dir" 2>&1
  )"
  rm -rf "$fake_dir"
  rm -f "$extractor"

  local resolved_root resolved_state
  resolved_root="$(printf '%s\n' "$out" | grep '^TEEUP_ROOT=')"
  resolved_root="${resolved_root#TEEUP_ROOT=}"
  resolved_state="$(printf '%s\n' "$out" | grep '^TEEUP_STATE=')"
  resolved_state="${resolved_state#TEEUP_STATE=}"

  assert_equals "$checkout" "$resolved_root" "$label: TEEUP_PATH should decode byte-for-byte (full output: $out)" || return 1
  assert_equals "$state" "$resolved_state" "$label: TEEUP_STATE_DIR should decode byte-for-byte (full output: $out)" || return 1
}

# The Important review finding on round 1: value:gsub("\\(.)", "%1") only
# undoes plain backslash escapes. A checkout or state dir with a non-ASCII
# byte makes bash 3.2's %q switch to `$'...'` ANSI-C quoting with octal byte
# escapes (`$'/Users/caf\303\251/teeup'`), which that gsub does not touch at
# all: `José` came back as `Jos303251`, require() failed to find the module,
# and the whole teeup Lua layer silently fell back to WezTerm's own
# defaults. One path here carries every character class the review named:
# a space, a single quote, a dollar sign, a non-ASCII (José/Café) byte
# sequence, and a tab.
test_teeup_path_and_state_dir_survive_special_bytes() {
  setup
  DRY_RUN=false "$TEEUP" configure wezterm >/dev/null

  if [[ -z "$WEZTERM_LUA" ]]; then
    echo "no lua interpreter installed: install lua5.4 (apt) or lua (brew) to run this test"
    cleanup_test_env
    return 1
  fi
  local lua_bin="$WEZTERM_LUA"

  local weird checkout state
  weird="José's \$Café Dir$(printf '\t')End"
  checkout="$TEST_HOME/$weird Checkout/teeup"
  state="$TEST_HOME/$weird State/teeup"

  _wezterm_assert_env_paths_survive "$lua_bin" bash "bash5 ($(bash --version | head -1))" "$checkout" "$state" || return 1

  local bash32
  if bash32="$(_wezterm_find_bash32)"; then
    _wezterm_assert_env_paths_survive "$lua_bin" "$bash32" "bash 3.2.0 ($bash32)" "$checkout" "$state" || return 1
  else
    echo "note: no bash 3.2 binary found (checked \$TEEUP_TEST_BASH32 and /bin/bash); skipping that variant. CI's macOS runners ship /bin/bash 3.2 natively."
  fi

  cleanup_test_env
}

echo "capabilities/wezterm"
run_test "install dry run gets the cask" test_install_dry_run_gets_the_cask
run_test "install falls back to a port on macports" test_install_falls_back_to_a_port_on_macports
run_test "configure installs both user files" test_configure_installs_both_user_files
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "font entry does not force a weight" test_font_entry_does_not_force_a_weight
run_test "configure names the MacPorts app location" test_configure_names_the_macports_app_location
run_test "configure names the MacPorts app location in dry run too" test_configure_names_the_macports_app_location_in_dry_run_too
run_test "configure says nothing when the bundle is missing" test_configure_says_nothing_when_the_bundle_is_missing
run_test "configure says nothing when the bundle is missing in dry run too" test_configure_says_nothing_when_the_bundle_is_missing_in_dry_run_too
run_test "configure reads applications_dir from macports.conf" test_configure_reads_applications_dir_from_macports_conf
run_test "configure says nothing about MacPorts on Homebrew" test_configure_says_nothing_about_macports_on_homebrew
run_test "theme-apply reloads the config" test_theme_apply_reloads_the_config
run_test "font-apply reloads the config" test_font_apply_reloads_the_config
run_test "theme renders a wezterm scheme" test_theme_renders_a_wezterm_scheme
run_test "shipped and rendered Lua parses" test_lua_files_parse
run_test "TEEUP_PATH and TEEUP_STATE_DIR survive a space" test_teeup_path_and_state_dir_survive_a_space
run_test "TEEUP_PATH and TEEUP_STATE_DIR survive special bytes" test_teeup_path_and_state_dir_survive_special_bytes
print_summary
