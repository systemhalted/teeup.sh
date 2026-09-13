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
  local out
  out="$(DRY_RUN=false "$TEEUP" theme set nope 2>&1)"
  assert_contains "$out" "Unknown theme: nope" || return 1
  assert_contains "$out" "Falling back to the catppuccin theme" || return 1
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
run_test "theme-apply without starship is quiet" test_theme_apply_without_starship_is_quiet
run_test "theme-apply warns when nothing rendered" test_theme_apply_warns_when_nothing_rendered
run_test "configure twice is content identical" test_configure_twice_is_content_identical
run_test "theme verbs" test_theme_verbs
print_summary
