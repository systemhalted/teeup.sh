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
}

test_install_dry_run_renders_nothing() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install theme)"
  assert_contains "$out" "[DRY-RUN] Would render env.sh.tpl" || return 1
  assert_contains "$out" "[DRY-RUN] Would swap" || return 1
  [[ ! -e "$TEST_HOME/.local/state/teeup/current/theme" ]] || { echo "theme written in dry run"; return 1; }
  cleanup_test_env
}

test_configure_writes_env_for_both_modes() {
  setup
  DRY_RUN=false "$TEEUP" configure theme >/dev/null
  local state
  state="$TEST_HOME/.local/state/teeup"
  assert_file_exists "$state/current/theme/dark/env.sh" || return 1
  assert_file_exists "$state/current/theme/light/env.sh" || return 1
  assert_contains "$(cat "$state/current/theme/dark/env.sh")" 'export BAT_THEME="OneHalfDark"' || return 1
  assert_contains "$(cat "$state/current/theme/dark/env.sh")" 'export TEEUP_THEME_ACCENT="#89b4fa"' || return 1
  assert_contains "$(cat "$state/current/theme/light/env.sh")" 'export BAT_THEME="OneHalfLight"' || return 1
  assert_equals "catppuccin" "$(cat "$state/current/theme.name")" || return 1
  cleanup_test_env
}

test_configure_writes_both_starship_palettes() {
  setup
  DRY_RUN=false "$TEEUP" configure theme >/dev/null
  local state
  state="$TEST_HOME/.local/state/teeup"
  assert_contains "$(cat "$state/current/theme/dark/starship-palette.toml")" "[palettes.teeup-dark]" || return 1
  assert_contains "$(cat "$state/current/theme/light/starship-palette.toml")" "[palettes.teeup-light]" || return 1
  cleanup_test_env
}

test_theme_apply_patches_the_starship_block() {
  setup
  mkdir -p "$TEST_HOME/.config"
  # Plan 2a's layout: the palette key and the block above every [table].
  cat > "$TEST_HOME/.config/starship.toml" <<'EOF2'
palette = "teeup-dark"
# teeup:theme-palette:start
# teeup:theme-palette:end

[character]
success_symbol = "[>](bold green)"
EOF2
  DRY_RUN=false "$TEEUP" configure theme >/dev/null
  local written
  written="$(cat "$TEST_HOME/.config/starship.toml")"
  assert_contains "$written" "[palettes.teeup-dark]" || return 1
  assert_contains "$written" "[palettes.teeup-light]" || return 1
  assert_contains "$written" 'accent = "#89b4fa"' || return 1
  assert_contains "$written" 'success_symbol = "[>](bold green)"' "the user's own lines survive" || return 1
  # defaults read exits 1 in the mock, so appearance is light.
  assert_contains "$written" 'palette = "teeup-light"' || return 1
  cleanup_test_env
}

test_theme_apply_replaces_a_populated_block() {
  setup
  mkdir -p "$TEST_HOME/.config"
  # Main's shipped starship.toml already carries a populated marker block
  # (plan 2a's own dark/light palettes); theme-apply must replace its
  # content, not merely fail to find an empty block to fill.
  cat > "$TEST_HOME/.config/starship.toml" <<'EOF2'
palette = "teeup-dark"

# teeup:theme-palette:start
[palettes.teeup-dark]
black = "#51576d"
red = "#e78284"

[palettes.teeup-light]
black = "#5c5f77"
red = "#d20f39"
# teeup:theme-palette:end

[character]
success_symbol = "[>](bold green)"
EOF2
  DRY_RUN=false "$TEEUP" configure theme >/dev/null
  local written
  written="$(cat "$TEST_HOME/.config/starship.toml")"
  assert_contains "$written" 'accent = "#89b4fa"' "the old block content is gone, teeup's palette is in" || return 1
  assert_not_contains "$written" 'red = "#e78284"' "the stale populated block did not survive" || return 1
  assert_contains "$written" 'success_symbol = "[>](bold green)"' "the user's own lines survive" || return 1
  cleanup_test_env
}

# assert_starship_untouched <label> <starship.toml content>
# theme-apply must warn and leave a file with malformed markers byte-identical.
assert_starship_untouched() {
  local label="$1" content="$2" out
  mkdir -p "$TEST_HOME/.config"
  printf '%s\n' "$content" > "$TEST_HOME/.config/starship.toml"
  cp "$TEST_HOME/.config/starship.toml" "$TEST_HOME/starship.before"
  out="$(DRY_RUN=false "$TEEUP" configure theme 2>&1)"
  cmp -s "$TEST_HOME/starship.before" "$TEST_HOME/.config/starship.toml" ||
    { echo "$label: starship.toml was rewritten:"; cat "$TEST_HOME/.config/starship.toml"; return 1; }
  assert_contains "$out" "leaving it alone" "$label: theme-apply says why" || return 1
}

test_theme_apply_refuses_malformed_markers() {
  setup
  assert_starship_untouched "end before start" 'palette = "teeup-dark"
# teeup:theme-palette:end
# teeup:theme-palette:start
[character]
success_symbol = "x"

[directory]
truncation_length = 3' || return 1
  assert_starship_untouched "duplicated start" 'palette = "teeup-dark"
# teeup:theme-palette:start
[palettes.teeup-dark]
red = "#e78284"
# teeup:theme-palette:start
[palettes.teeup-light]
red = "#d20f39"
# teeup:theme-palette:end

[character]
success_symbol = "x"' || return 1
  assert_starship_untouched "missing end" 'palette = "teeup-dark"
# teeup:theme-palette:start
[palettes.teeup-dark]
red = "#e78284"

[character]
success_symbol = "x"' || return 1
  cleanup_test_env
}

test_theme_apply_rewrites_only_the_first_palette_line() {
  setup
  mkdir -p "$TEST_HOME/.config"
  cat > "$TEST_HOME/.config/starship.toml" <<'EOF2'
palette = "teeup-dark"
# teeup:theme-palette:start
# teeup:theme-palette:end

[custom.foo]
command = "echo hi"
palette = "should-stay"
EOF2
  DRY_RUN=false "$TEEUP" configure theme >/dev/null
  local written
  written="$(cat "$TEST_HOME/.config/starship.toml")"
  assert_contains "$written" 'palette = "teeup-light"' || return 1
  assert_contains "$written" 'palette = "should-stay"' "a later palette key belongs to its table" || return 1
  cleanup_test_env
}

test_theme_apply_survives_a_backslash_in_tmpdir() {
  setup
  mkdir -p "$TEST_HOME/.config" "$TEST_HOME/tmp\new dir"
  cp "$TEEUP_PATH/capabilities/starship/config/starship.toml" "$TEST_HOME/.config/starship.toml"
  # awk -v processes backslash escapes, so a temp path handed over that way
  # names a different file and the palette block comes out empty.
  TMPDIR="$TEST_HOME/tmp\new dir" DRY_RUN=false "$TEEUP" configure theme >/dev/null
  local written
  written="$(cat "$TEST_HOME/.config/starship.toml")"
  assert_contains "$written" "[palettes.teeup-dark]" || return 1
  assert_contains "$written" 'accent = "#89b4fa"' || return 1
  cleanup_test_env
}

test_theme_apply_without_starship_is_quiet() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure theme 2>&1)"
  assert_contains "$out" "No $TEST_HOME/.config/starship.toml yet" || return 1
  assert_not_contains "$out" "theme-apply failed" || return 1
  cleanup_test_env
}

test_theme_apply_warns_when_nothing_rendered() {
  setup
  mkdir -p "$TEST_HOME/.config"
  cat > "$TEST_HOME/.config/starship.toml" <<'EOF2'
palette = "teeup-dark"
# teeup:theme-palette:start
# teeup:theme-palette:end

[character]
success_symbol = "[>](bold green)"
EOF2
  mkdir -p "$TEST_HOME/empty-theme/dark" "$TEST_HOME/empty-theme/light"
  local out
  out="$(TEEUP_THEME_DIR="$TEST_HOME/empty-theme" DRY_RUN=false bash -c '
    source "$TEEUP_PATH/lib/all.sh"
    answers_load
    source "$TEEUP_PATH/capabilities/theme/theme-apply"
  ' 2>&1)"
  assert_contains "$out" "No rendered starship palettes in $TEST_HOME/empty-theme" || return 1
  assert_not_contains "$(cat "$TEST_HOME/.config/starship.toml")" "[palettes.teeup-dark]" || return 1
  cleanup_test_env
}

test_configure_twice_is_content_identical() {
  setup
  DRY_RUN=false "$TEEUP" configure theme >/dev/null
  cp "$TEST_HOME/.local/state/teeup/current/theme/dark/env.sh" "$TEST_HOME/first.sh"
  DRY_RUN=false "$TEEUP" configure theme >/dev/null
  cmp -s "$TEST_HOME/first.sh" "$TEST_HOME/.local/state/teeup/current/theme/dark/env.sh" \
    || { echo "second configure changed env.sh"; return 1; }
  cleanup_test_env
}

test_theme_verbs() {
  setup
  assert_equals "none" "$(DRY_RUN=false "$TEEUP" theme current)" || return 1
  assert_contains "$(DRY_RUN=false "$TEEUP" theme list | tr '\n' ' ')" "catppuccin" || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  assert_equals "catppuccin" "$(DRY_RUN=false "$TEEUP" theme current)" || return 1
  cleanup_test_env
}

test_theme_set_refuses_an_unknown_or_invalid_name() {
  setup
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  local rc=0 out
  # A typo on the command line must not replace a working theme: the
  # catppuccin fallback is only for configure reading a stale answer.
  out="$(DRY_RUN=false "$TEEUP" theme set nope 2>&1)" || rc=$?
  assert_equals "1" "$rc" || return 1
  assert_contains "$out" "Unknown theme: nope" || return 1
  assert_contains "$out" "Available themes:" || return 1
  assert_contains "$out" "catppuccin" || return 1
  assert_not_contains "$out" "Falling back" || return 1
  rc=0
  out="$(DRY_RUN=false "$TEEUP" theme set ../themes/catppuccin 2>&1)" || rc=$?
  assert_equals "1" "$rc" || return 1
  assert_contains "$out" "Invalid theme name" || return 1
  assert_equals "catppuccin" "$(DRY_RUN=false "$TEEUP" theme current)" || return 1
  cleanup_test_env
}

make_user_theme_nord() {
  mkdir -p "$TEST_HOME/.config/teeup/themes/nord"
  cp "$TEEUP_PATH/themes/catppuccin/dark.toml" "$TEEUP_PATH/themes/catppuccin/light.toml" "$TEST_HOME/.config/teeup/themes/nord/"
}

test_theme_set_is_remembered_by_configure() {
  setup
  make_user_theme_nord
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_NAME="Ada"\nTEEUP_THEME="catppuccin"\n' > "$TEST_HOME/.config/teeup/answers"
  DRY_RUN=false "$TEEUP" theme set nord >/dev/null
  assert_contains "$(cat "$TEST_HOME/.config/teeup/answers")" 'TEEUP_THEME="nord"' || return 1
  assert_contains "$(cat "$TEST_HOME/.config/teeup/answers")" 'TEEUP_NAME="Ada"' "other answers survive" || return 1
  DRY_RUN=false "$TEEUP" configure theme >/dev/null
  assert_equals "nord" "$(DRY_RUN=false "$TEEUP" theme current)" "configure keeps the theme set last" || return 1
  cleanup_test_env
}

test_theme_set_warns_about_a_machine_pin() {
  setup
  make_user_theme_nord
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR"
  printf 'TEEUP_THEME="catppuccin"\n' > "$TEEUP_MACHINES_DIR/testmac.conf"
  local out
  out="$(DRY_RUN=false "$TEEUP" theme set nord 2>&1)"
  assert_contains "$out" "Theme set to nord" || return 1
  assert_contains "$out" "$TEEUP_MACHINES_DIR/testmac.conf pins TEEUP_THEME=catppuccin" || return 1
  out="$(DRY_RUN=false "$TEEUP" theme set catppuccin 2>&1)"
  assert_not_contains "$out" "pins TEEUP_THEME" "no warning when the choice matches the pin" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_a_theme_that_cannot_render_fails_set_and_configure() {
  setup
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  mkdir -p "$TEST_HOME/.config/teeup/themes/mini"
  cp "$TEEUP_PATH/themes/catppuccin/dark.toml" "$TEST_HOME/.config/teeup/themes/mini/dark.toml"
  printf 'mode = "light"\naccent = "#ffffff"\n' > "$TEST_HOME/.config/teeup/themes/mini/light.toml"
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" theme set mini 2>&1)" || rc=$?
  assert_equals "1" "$rc" "teeup theme set exits 1" || return 1
  assert_contains "$out" "wezterm.lua.tpl: the mini light palette has no value for:" || return 1
  assert_equals "catppuccin" "$(DRY_RUN=false "$TEEUP" theme current)" || return 1
  printf 'TEEUP_THEME="mini"\n' > "$TEST_HOME/.config/teeup/answers"
  rc=0
  out="$(DRY_RUN=false "$TEEUP" configure theme 2>&1)" || rc=$?
  assert_failure "$rc" "a shipped or chosen theme that cannot render must stop configure" || return 1
  assert_contains "$out" "Theme mini was not applied" || return 1
  assert_equals "catppuccin" "$(DRY_RUN=false "$TEEUP" theme current)" || return 1
  cleanup_test_env
}

test_theme_apply_refuses_a_block_below_a_table() {
  setup
  mkdir -p "$TEST_HOME/.config"
  cat > "$TEST_HOME/.config/starship.toml" <<'EOF2'
[cmd_duration]
min_time = 500

palette = "teeup-dark"
# teeup:theme-palette:start
# teeup:theme-palette:end
EOF2
  local out
  out="$(DRY_RUN=false "$TEEUP" configure theme 2>&1)"
  assert_contains "$out" "below its first [table]" || return 1
  assert_not_contains "$(cat "$TEST_HOME/.config/starship.toml")" "[palettes.teeup-dark]" || return 1
  cleanup_test_env
}

echo "capabilities/theme"
run_test "install dry run renders nothing" test_install_dry_run_renders_nothing
run_test "configure writes env.sh for both modes" test_configure_writes_env_for_both_modes
run_test "configure writes both starship palettes" test_configure_writes_both_starship_palettes
run_test "theme-apply patches the starship block" test_theme_apply_patches_the_starship_block
run_test "theme-apply replaces a populated block" test_theme_apply_replaces_a_populated_block
run_test "theme-apply refuses a block below a table" test_theme_apply_refuses_a_block_below_a_table
run_test "theme-apply refuses malformed markers" test_theme_apply_refuses_malformed_markers
run_test "theme-apply rewrites only the first palette line" test_theme_apply_rewrites_only_the_first_palette_line
run_test "theme-apply survives a backslash in TMPDIR" test_theme_apply_survives_a_backslash_in_tmpdir
run_test "theme-apply without starship is quiet" test_theme_apply_without_starship_is_quiet
run_test "theme-apply warns when nothing rendered" test_theme_apply_warns_when_nothing_rendered
run_test "configure twice is content identical" test_configure_twice_is_content_identical
run_test "theme verbs" test_theme_verbs
run_test "theme set refuses an unknown or invalid name" test_theme_set_refuses_an_unknown_or_invalid_name
run_test "theme set is remembered by configure" test_theme_set_is_remembered_by_configure
run_test "theme set warns about a machine pin" test_theme_set_warns_about_a_machine_pin
run_test "a theme that cannot render fails set and configure" test_a_theme_that_cannot_render_fails_set_and_configure
print_summary
