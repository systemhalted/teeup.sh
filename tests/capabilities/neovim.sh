#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# lua and luac are found before setup_test_env narrows PATH (Homebrew's live
# outside it on macOS). CI installs lua5.4 / lua, so a missing one fails the
# Lua checks rather than skipping them.
NVIM_LUAC="$(command -v luac || command -v luac5.4 || true)"
NVIM_LUA="$(command -v lua || command -v lua5.4 || command -v lua5.3 || true)"

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
  mock_command nvim 0 ""
  # Sockets are looked up in XDG_RUNTIME_DIR and TMPDIR; the developer's own
  # values would point the hooks at real, running editors.
  export XDG_RUNTIME_DIR="$TEST_HOME/run"
  export TMPDIR="$TEST_HOME/tmp"
  mkdir -p "$XDG_RUNTIME_DIR" "$TMPDIR"
  TEEUP="$TEEUP_PATH/bin/teeup"
  NVIM="$TEST_HOME/.config/nvim"
}

# mark_installed: what `teeup install neovim` records after configure.
mark_installed() {
  mkdir -p "$TEST_HOME/.local/state/teeup/done"
  : > "$TEST_HOME/.local/state/teeup/done/cap-neovim"
}

test_neovim_is_lazy_and_provides_nvim() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  assert_equals "lazy" "$(cap_meta_get neovim tier)" || return 1
  assert_equals "nvim" "$(cap_meta_get neovim provides)" || return 1
  if grep -qx neovim "$TEEUP_PATH/capabilities/daily.list" "$TEEUP_PATH/capabilities/core.list"; then
    echo "neovim is lazy but sits in a tier list"
    return 1
  fi
  cleanup_test_env
}

test_install_dry_run_gets_the_formula() {
  setup
  export TEEUP_TEST_MISSING="nvim"
  local out
  out="$(DRY_RUN=true "$TEEUP" install neovim)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install neovim" || return 1
  cleanup_test_env
}

test_install_uses_the_port_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  export TEEUP_TEST_MISSING="nvim"
  mock_command port 1 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install neovim 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: sudo port install neovim" || return 1
  cleanup_test_env
}

test_configure_installs_the_starter_layout() {
  setup
  DRY_RUN=false "$TEEUP" configure neovim >/dev/null
  local rel
  for rel in init.lua stylua.toml lua/config/lazy.lua lua/config/options.lua \
             lua/config/keymaps.lua lua/config/autocmds.lua lua/plugins/local.lua; do
    assert_file_exists "$NVIM/$rel" || return 1
  done
  assert_contains "$(cat "$NVIM/init.lua")" "capabilities/neovim/default/?.lua" || return 1
  assert_contains "$(cat "$NVIM/lua/config/lazy.lua")" 'pcall(require, "teeup.neovim")' || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  DRY_RUN=false "$TEEUP" configure neovim >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure neovim)"
  assert_contains "$out" "Already installed: $NVIM/init.lua" || return 1
  assert_contains "$out" "Already installed: $NVIM/lua/plugins/local.lua" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" configure neovim)"
  assert_contains "$out" "[DRY-RUN] Would install $NVIM/init.lua" || return 1
  [[ ! -e "$NVIM" ]] || { echo "config written in dry run"; return 1; }
  cleanup_test_env
}

test_configure_reports_a_conflicting_init_vim() {
  setup
  mkdir -p "$NVIM"
  printf 'set nocompatible\n' > "$NVIM/init.vim"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure neovim 2>&1)"
  assert_contains "$out" "$NVIM/init.vim exists next to init.lua; Neovim reports E5422 and ignores it." || return 1
  assert_file_exists "$NVIM/init.vim" "not moved" || return 1
  cleanup_test_env
}

test_configure_warns_about_a_neovim_too_old_for_lazyvim() {
  setup
  mock_command nvim 0 "NVIM v0.10.4"
  local out
  out="$(DRY_RUN=true "$TEEUP" configure neovim 2>&1)"
  assert_contains "$out" "$MOCK_BIN/nvim is Neovim 0.10.4; LazyVim needs 0.11.2 or later." || return 1
  mock_command nvim 0 "NVIM v0.11.2"
  out="$(DRY_RUN=true "$TEEUP" configure neovim 2>&1)"
  assert_not_contains "$out" "LazyVim needs" || return 1
  cleanup_test_env
}

test_theme_renders_the_neovim_palette() {
  setup
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  local dark light
  dark="$TEST_HOME/.local/state/teeup/current/theme/dark/neovim.lua"
  light="$TEST_HOME/.local/state/teeup/current/theme/light/neovim.lua"
  assert_file_exists "$dark" || return 1
  assert_contains "$(cat "$dark")" 'colorscheme = "catppuccin-mocha"' || return 1
  assert_contains "$(cat "$light")" 'colorscheme = "catppuccin-latte"' || return 1
  assert_contains "$(cat "$dark")" 'accent = "#89b4fa"' || return 1
  assert_not_contains "$(cat "$dark")" "{{" "every token was substituted" || return 1
  cleanup_test_env
}

test_hooks_reload_every_running_neovim() {
  setup
  mark_installed
  # Neovim's two socket locations: nvim.<pid>.0 directly in XDG_RUNTIME_DIR,
  # and $TMPDIR/nvim.<user>/<random>/nvim.<pid>.0 without one. The harness's
  # id mock answers 501 for `id -un` too, so that is the user here.
  mkdir -p "$TMPDIR/nvim.501/abc123"
  : > "$TMPDIR/nvim.501/abc123/nvim.4242.0"
  : > "$XDG_RUNTIME_DIR/nvim.777.0"
  local out
  out="$(DRY_RUN=true "$TEEUP" theme set catppuccin 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: nvim --server $TMPDIR/nvim.501/abc123/nvim.4242.0 --remote-send <Cmd>lua require(\"teeup.neovim\").apply()<CR>" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: nvim --server $XDG_RUNTIME_DIR/nvim.777.0 --remote-send" || return 1
  out="$(DRY_RUN=true "$TEEUP" install font Hack 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: nvim --server $TMPDIR/nvim.501/abc123/nvim.4242.0 --remote-send" || return 1
  rm -rf "$TMPDIR/nvim.501" "$XDG_RUNTIME_DIR/nvim.777.0"
  out="$(DRY_RUN=true "$TEEUP" theme set catppuccin 2>&1)"
  assert_contains "$out" "No running Neovim to tell; the theme is read at the next start." || return 1
  cleanup_test_env
}

test_hooks_leave_a_neovim_teeup_did_not_install_alone() {
  setup
  : > "$XDG_RUNTIME_DIR/nvim.777.0"
  local out
  out="$(DRY_RUN=true "$TEEUP" theme set catppuccin 2>&1)"
  assert_not_contains "$out" "nvim --server" || return 1
  assert_not_contains "$out" "No running Neovim" "the hook did not even look" || return 1
  cleanup_test_env
}

test_lua_files_parse() {
  setup
  if [[ -z "$NVIM_LUAC" ]]; then
    echo "luac is not installed: install lua5.4 (apt) or lua (brew) to run this suite"
    cleanup_test_env
    return 1
  fi
  DRY_RUN=false "$TEEUP" configure neovim >/dev/null
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  local f rc=0
  for f in "$NVIM/init.lua" "$NVIM/lua/config/lazy.lua" "$NVIM/lua/config/options.lua" \
           "$NVIM/lua/config/keymaps.lua" "$NVIM/lua/config/autocmds.lua" "$NVIM/lua/plugins/local.lua" \
           "$TEEUP_PATH/capabilities/neovim/default/teeup/neovim.lua" \
           "$TEST_HOME/.local/state/teeup/current/theme/dark/neovim.lua" \
           "$TEST_HOME/.local/state/teeup/current/theme/light/neovim.lua"; do
    "$NVIM_LUAC" -p "$f" || { echo "Lua syntax error in $f"; rc=1; }
  done
  cleanup_test_env
  return $rc
}

# I3: a colorscheme table key that can never match a real colorscheme name
# is a silent no-op (no error, just no plugin), so this loads the shipped
# module under a plain lua (no `vim` global needed: M.plugin_for and the
# table it reads never touch vim) and asserts the lookup a dashed name needs.
test_plugin_for_matches_dashed_colorscheme_names() {
  setup
  if [[ -z "$NVIM_LUA" ]]; then
    echo "lua is not installed: install lua5.4 (apt) or lua (brew) to run this suite"
    cleanup_test_env
    return 1
  fi
  local out
  out="$("$NVIM_LUA" -e "
    local M = dofile('$TEEUP_PATH/capabilities/neovim/default/teeup/neovim.lua')
    local rp = M.plugin_for('rose-pine-dawn')
    local tn = M.plugin_for('tokyonight-day')
    assert(rp and rp[1] == 'rose-pine/neovim', 'rose-pine-dawn should key on rose, got ' .. tostring(rp and rp[1]))
    assert(tn and tn[1] == 'folke/tokyonight.nvim', 'tokyonight-day should key on tokyonight, got ' .. tostring(tn and tn[1]))
    print('ok')
  " 2>&1)"
  assert_contains "$out" "ok" "plugin_for must resolve dashed colorscheme names (got: $out)" || return 1
  cleanup_test_env
}

# The thin init.lua resolves TEEUP_PATH and TEEUP_STATE_DIR before it touches
# anything Neovim-specific (`vim` is nil under plain Lua, and the file says
# so), so a plain interpreter can run it and read the result off package.path.
# One path carries a space, a quote, a dollar sign and non-ASCII bytes, and
# the env file is written by the bash at hand, by hand in the $'...' form
# bash 3.2 uses for non-ASCII bytes (so every runner checks that form), and,
# when available, by a real bash 3.2 (macOS's /bin/bash; TEEUP_TEST_BASH32
# points at another).
_neovim_assert_paths_survive() {
  local bash_bin="$1" label="$2" checkout="$3" state="$4" out
  mkdir -p "$TEST_HOME/.config/teeup"
  if [[ "$bash_bin" == "literal" ]]; then
    # Byte for byte what bash 3.2's %q prints for these two paths: $'...'
    # with the quote backslash-escaped and each UTF-8 byte of é in octal.
    {
      printf 'export TEEUP_PATH=%s\n' "\$'$TEST_HOME/Jos\\303\\251\\'s \$Caf\\303\\251 Dir Checkout/teeup'"
      printf 'export TEEUP_STATE_DIR=%s\n' "\$'$TEST_HOME/Jos\\303\\251\\'s \$Caf\\303\\251 Dir State/teeup'"
    } > "$TEST_HOME/.config/teeup/env"
  else
    {
      printf 'export TEEUP_PATH=%s\n' "$("$bash_bin" -c 'printf "%q" "$1"' _ "$checkout")"
      printf 'export TEEUP_STATE_DIR=%s\n' "$("$bash_bin" -c 'printf "%q" "$1"' _ "$state")"
    } > "$TEST_HOME/.config/teeup/env"
  fi
  out="$(
    unset TEEUP_PATH TEEUP_STATE_DIR
    HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/.config" "$NVIM_LUA" -e "dofile('$NVIM/init.lua'); print(package.path)" 2>&1
  )"
  assert_contains "$out" "$state/current/theme/?.lua;" "$label: TEEUP_STATE_DIR should decode byte-for-byte (got: $out)" || return 1
  assert_contains "$out" "$checkout/capabilities/neovim/default/?.lua;" "$label: TEEUP_PATH should decode byte-for-byte" || return 1
}

test_teeup_paths_survive_special_bytes() {
  setup
  if [[ -z "$NVIM_LUA" ]]; then
    echo "no lua interpreter installed: install lua5.4 (apt) or lua (brew) to run this test"
    cleanup_test_env
    return 1
  fi
  DRY_RUN=false "$TEEUP" configure neovim >/dev/null
  local weird checkout state
  weird="José's \$Café Dir"
  checkout="$TEST_HOME/$weird Checkout/teeup"
  state="$TEST_HOME/$weird State/teeup"
  _neovim_assert_paths_survive bash "bash5" "$checkout" "$state" || return 1
  _neovim_assert_paths_survive literal "bash 3.2 form, written by hand" "$checkout" "$state" || return 1
  local candidate bash32=""
  for candidate in "${TEEUP_TEST_BASH32:-}" /bin/bash; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    if "$candidate" --version 2>/dev/null | head -1 | grep -q 'version 3\.2'; then bash32="$candidate"; break; fi
  done
  if [[ -n "$bash32" ]]; then
    _neovim_assert_paths_survive "$bash32" "bash 3.2 ($bash32)" "$checkout" "$state" || return 1
  else
    echo "note: no bash 3.2 binary found (checked \$TEEUP_TEST_BASH32 and /bin/bash); skipping that variant. CI's macOS runners ship /bin/bash 3.2 natively."
  fi
  cleanup_test_env
}

echo "capabilities/neovim"
run_test "neovim is lazy and provides nvim" test_neovim_is_lazy_and_provides_nvim
run_test "install dry run gets the formula" test_install_dry_run_gets_the_formula
run_test "install uses the port on macports" test_install_uses_the_port_on_macports
run_test "configure installs the starter layout" test_configure_installs_the_starter_layout
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "configure reports a conflicting init.vim" test_configure_reports_a_conflicting_init_vim
run_test "configure warns about a Neovim too old for LazyVim" test_configure_warns_about_a_neovim_too_old_for_lazyvim
run_test "theme renders the neovim palette" test_theme_renders_the_neovim_palette
run_test "hooks reload every running neovim" test_hooks_reload_every_running_neovim
run_test "hooks leave a Neovim teeup did not install alone" test_hooks_leave_a_neovim_teeup_did_not_install_alone
run_test "shipped and rendered Lua parses" test_lua_files_parse
run_test "plugin_for matches dashed colorscheme names" test_plugin_for_matches_dashed_colorscheme_names
run_test "TEEUP_PATH and TEEUP_STATE_DIR survive special bytes" test_teeup_paths_survive_special_bytes
print_summary
