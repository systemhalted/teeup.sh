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
  assert_contains "$out" "$3" "$label: the warning names the problem" || return 1
}

test_a_palette_rewrite_leaves_starship_toml_unedited() {
  setup
  DRY_RUN=false "$TEEUP" configure starship >/dev/null
  DRY_RUN=false "$TEEUP" configure theme >/dev/null
  assert_contains "$(cat "$TEEUP_PATH/capabilities/starship/config/starship.toml")" 'palette = "teeup-dark"' || return 1
  assert_contains "$(cat "$TEST_HOME/.config/starship.toml")" 'palette = "teeup-light"' "the palette was rewritten" || return 1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure starship)"
  assert_contains "$out" "Already installed: $TEST_HOME/.config/starship.toml" || return 1
  assert_not_contains "$out" "Keeping your edited" || return 1
  # A line of the user's own makes it theirs, and the next rewrite keeps it so.
  printf '\n[directory]\ntruncation_length = 2\n' >> "$TEST_HOME/.config/starship.toml"
  sed -i.bak 's/^palette = .*/palette = "teeup-dark"/' "$TEST_HOME/.config/starship.toml" && rm "$TEST_HOME/.config/starship.toml.bak"
  DRY_RUN=false "$TEEUP" configure theme >/dev/null
  assert_contains "$(cat "$TEST_HOME/.config/starship.toml")" 'palette = "teeup-light"' "the edited file still gets its palette" || return 1
  out="$(DRY_RUN=false "$TEEUP" configure starship)"
  assert_contains "$out" "Keeping your edited $TEST_HOME/.config/starship.toml" || return 1
  cleanup_test_env
}

test_theme_apply_leaves_a_symlinked_starship_toml_alone() {
  setup
  mkdir -p "$TEST_HOME/dotfiles" "$TEST_HOME/.config"
  cp "$TEEUP_PATH/capabilities/starship/config/starship.toml" "$TEST_HOME/dotfiles/starship.toml"
  ln -s "$TEST_HOME/dotfiles/starship.toml" "$TEST_HOME/.config/starship.toml"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure theme 2>&1)"
  assert_contains "$out" "$TEST_HOME/.config/starship.toml is a symlink" || return 1
  [[ -L "$TEST_HOME/.config/starship.toml" ]] || { echo "the link was replaced by a file"; return 1; }
  cmp -s "$TEEUP_PATH/capabilities/starship/config/starship.toml" "$TEST_HOME/dotfiles/starship.toml" ||
    { echo "the linked file was written through"; return 1; }
  cleanup_test_env
}

test_theme_apply_refuses_malformed_markers() {
  setup
  assert_starship_untouched "end before start" 'palette = "teeup-dark"
# teeup:theme-palette:end
# teeup:theme-palette:start
[character]
success_symbol = "x"

[directory]
truncation_length = 3' "the end marker comes before the start marker" || return 1
  assert_starship_untouched "duplicated start" 'palette = "teeup-dark"
# teeup:theme-palette:start
[palettes.teeup-dark]
red = "#e78284"
# teeup:theme-palette:start
[palettes.teeup-light]
red = "#d20f39"
# teeup:theme-palette:end

[character]
success_symbol = "x"' "2 start markers" || return 1
  assert_starship_untouched "missing end" 'palette = "teeup-dark"
# teeup:theme-palette:start
[palettes.teeup-dark]
red = "#e78284"

[character]
success_symbol = "x"' "no end marker" || return 1
  # The user's own tables inside the block would be deleted by the rewrite.
  assert_starship_untouched "user tables inside the block" 'palette = "teeup-dark"
# teeup:theme-palette:start
[palettes.teeup-dark]
red = "#e78284"

[character]
success_symbol = "x"

[directory]
truncation_length = 3
# teeup:theme-palette:end' "[character] at line 6 sits between the teeup palette markers" || return 1
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

test_theme_apply_inserts_a_missing_root_palette() {
  setup
  mkdir -p "$TEST_HOME/.config"
  # No root `palette = ` line at all: theme-apply must insert one rather than
  # silently leaving starship without a palette selector.
  cat > "$TEST_HOME/.config/starship.toml" <<'EOF2'
# teeup:theme-palette:start
# teeup:theme-palette:end

[character]
success_symbol = "[>](bold green)"
EOF2
  DRY_RUN=false "$TEEUP" configure theme >/dev/null
  local file="$TEST_HOME/.config/starship.toml" written p s
  written="$(cat "$file")"
  assert_contains "$written" "[palettes.teeup-dark]" || return 1
  assert_contains "$written" "[palettes.teeup-light]" || return 1
  p="$(grep -n '^palette = ' "$file" | head -1 | cut -d: -f1)"
  s="$(grep -n -xF '# teeup:theme-palette:start' "$file" | head -1 | cut -d: -f1)"
  [[ -n "$p" ]] || { echo "no root palette line was inserted"; return 1; }
  [[ -n "$s" && "$p" -lt "$s" ]] ||
    { echo "the inserted palette line (line $p) must come before the start marker (line $s)"; return 1; }
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import tomllib' >/dev/null 2>&1; then
    local parsed
    parsed="$(python3 -c 'import tomllib, sys
d = tomllib.load(open(sys.argv[1], "rb"))
print(d.get("palette"))' "$file")"
    [[ "$parsed" == "teeup-dark" || "$parsed" == "teeup-light" ]] ||
      { echo "tomllib read root palette [$parsed], want teeup-dark or teeup-light"; return 1; }
  fi
  cleanup_test_env
}

test_theme_apply_inserts_a_root_palette_beside_a_table_scoped_one() {
  setup
  mkdir -p "$TEST_HOME/.config"
  # No root palette line, but a later table has its own `palette` key: that
  # key belongs to [custom] and must survive untouched while a root selector
  # is still inserted before the marker block.
  cat > "$TEST_HOME/.config/starship.toml" <<'EOF2'
# teeup:theme-palette:start
# teeup:theme-palette:end

[custom]
palette = "mine"
EOF2
  DRY_RUN=false "$TEEUP" configure theme >/dev/null
  local file="$TEST_HOME/.config/starship.toml" written p s
  written="$(cat "$file")"
  assert_contains "$written" 'palette = "mine"' "the table-scoped key survives unchanged" || return 1
  assert_contains "$written" "[palettes.teeup-dark]" || return 1
  p="$(grep -n '^palette = ' "$file" | head -1 | cut -d: -f1)"
  s="$(grep -n -xF '# teeup:theme-palette:start' "$file" | head -1 | cut -d: -f1)"
  [[ -n "$p" ]] || { echo "no root palette line was inserted"; return 1; }
  [[ -n "$s" && "$p" -lt "$s" ]] ||
    { echo "the inserted palette line (line $p) must come before the start marker (line $s)"; return 1; }
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

test_doctor_passes_after_a_theme_switch() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  theme_set catppuccin >/dev/null 2>&1
  local rc=0 out
  out="$(DRY_RUN=false cap_run theme doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "Current theme: catppuccin" || return 1
  cleanup_test_env
}

# Without colors.toml doctor cannot tell which theme dark/env.sh actually
# came from -- not a confirmed mismatch (it might well be right), and not
# healthy either: something material could not be checked.
test_doctor_reports_unknown_when_colors_toml_is_missing() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  theme_set catppuccin >/dev/null 2>&1
  rm -f "$TEEUP_STATE_DIR/current/theme/dark/colors.toml"
  local rc=0 out
  out="$(DRY_RUN=false cap_run theme doctor 2>&1)" || rc=$?
  assert_unknown "$rc" "the dark render might still be right; teeup only could not check it against colors.toml" || return 1
  assert_contains "$out" "colors.toml is missing" || return 1
  cleanup_test_env
}

# A colors.toml that is there but does not parse as a valid palette (a bad
# value, a missing mode key) means the truncation re-check below it cannot
# run either -- again a genuine "could not check", not a confirmed problem.
# The source theme's own dark.toml is made invalid the same way, and kept
# byte-identical to the state copy, so the "rendered from a different theme"
# diff still passes -- only the palette-validity question is exercised here.
test_doctor_reports_unknown_when_colors_toml_is_invalid() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  local themes_dir="$TEST_HOME/fixture-themes"
  mkdir -p "$themes_dir"
  cp -R "$TEEUP_PATH/themes/catppuccin" "$themes_dir/mytheme"
  export TEEUP_THEMES_DIR="$themes_dir"
  theme_set mytheme >/dev/null 2>&1
  printf 'mode = "dark"\naccent = "bad;value"\n' > "$themes_dir/mytheme/dark.toml"
  cp "$themes_dir/mytheme/dark.toml" "$TEEUP_STATE_DIR/current/theme/dark/colors.toml"
  local rc=0 out
  out="$(DRY_RUN=false cap_run theme doctor 2>&1)" || rc=$?
  assert_unknown "$rc" "an invalid colors.toml means the truncation re-check could not run, not that it failed" || return 1
  assert_contains "$out" "could not be re-checked for truncation" || return 1
  assert_not_contains "$out" "rendered from a different theme" "source and state agree; only validity is in question here" || return 1
  cleanup_test_env
}

test_doctor_reports_a_machine_with_no_theme() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run theme doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "No theme has been applied" || return 1
  assert_contains "$(cat "$report")" "teeup theme set" || return 1
  cleanup_test_env
}

test_doctor_reports_a_template_that_was_never_rendered() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  theme_set catppuccin >/dev/null 2>&1
  # A capability added a template after the last switch, which is exactly what
  # every later phase does. This is written under the user template directory
  # inside $TEST_HOME, not $TEEUP_CAPS_DIR (the real checkout), and uses a
  # real catppuccin key (accent) rather than a made-up one: theme_templates
  # reads $TEEUP_CONFIG_DIR/themed first, and a stray *.tpl under the real
  # capabilities tree would be picked up by a theme_set running concurrently
  # in another suite.
  mkdir -p "$TEEUP_CONFIG_DIR/themed"
  printf 'color = "{{ accent }}"\n' > "$TEEUP_CONFIG_DIR/themed/latecomer.conf.tpl"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run theme doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "latecomer.conf has never been rendered" || return 1
  assert_contains "$(cat "$report")" "teeup theme set catppuccin" || return 1
  cleanup_test_env
}

test_doctor_reports_an_unresolved_token_in_a_rendered_file() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  theme_set catppuccin >/dev/null 2>&1
  printf 'color = "{{ nope }}"\n' > "$TEEUP_STATE_DIR/current/theme/dark/env.sh"
  local rc=0 out
  out="$(DRY_RUN=false cap_run theme doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "still holds an unresolved" || return 1
  cleanup_test_env
}

# An empty rendered file is neither missing nor holding a {{ token }}, so it
# slips past both of the other checks while the tool it belongs to reads no
# colours at all. A truncating write or a full disk leaves exactly this.
test_doctor_reports_an_empty_rendered_file() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  theme_set catppuccin >/dev/null 2>&1
  : > "$TEEUP_STATE_DIR/current/theme/dark/env.sh"
  local rc=0 out
  out="$(DRY_RUN=false cap_run theme doctor 2>&1)" || rc=$?
  assert_failure "$rc" "an empty render is not a render" || return 1
  assert_contains "$out" "is empty, so env.sh has no colours" || return 1
  cleanup_test_env
}

# theme_templates skips a themed/ directory it cannot read, in silence, so
# every template behind it goes unchecked and the doctor reports a clean bill
# for a theme it never looked at.
#
# NI7: this used to chmod 0000 a REAL capability directory
# ($TEEUP_CAPS_DIR/emacs/themed) and chmod it back to a hardcoded 0755,
# writing into the checkout -- the standing "no test writes into the
# checkout" rule, broken. TEEUP_CAPS_DIR is swapped to a throwaway fixture
# tree under $TEST_HOME instead: a copy of theme's own capability (so
# cap_run can still find and run it) plus one throwaway capability whose
# themed/ is unreadable, reproducing the exact defect without touching a
# real capability directory.
test_doctor_reports_a_themed_directory_it_cannot_read() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  theme_set catppuccin >/dev/null 2>&1
  local fixture_caps="$TEST_HOME/fixture-caps"
  mkdir -p "$fixture_caps"
  cp -R "$TEEUP_PATH/capabilities/theme" "$fixture_caps/theme"
  mkdir -p "$fixture_caps/throwaway/themed"
  printf 'color = "{{ accent }}"\n' > "$fixture_caps/throwaway/themed/broken.conf.tpl"
  chmod 0000 "$fixture_caps/throwaway/themed"
  local rc=0 out
  out="$(TEEUP_CAPS_DIR="$fixture_caps" DRY_RUN=false cap_run theme doctor 2>&1)" || rc=$?
  chmod 0755 "$fixture_caps/throwaway/themed"
  assert_failure "$rc" || return 1
  assert_contains "$out" "cannot be read, so its templates were not checked at all" || return 1
  cleanup_test_env
}

# A template edited after the last render leaves the tool on colours teeup no
# longer ships, and `teeup update` does not re-render on its own.
#
# NI7: this used to `touch` a real capability's .tpl file in the checkout
# ($TEEUP_CAPS_DIR/*/themed/*.tpl). theme_templates lists a user template
# under $TEEUP_CONFIG_DIR/themed FIRST, ahead of any capability's own, so
# copying one real template's basename there (never editing the original)
# shadows it with a fresher file under $TEST_HOME instead.
test_doctor_warns_when_a_template_is_newer_than_its_render() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  theme_set catppuccin >/dev/null 2>&1
  local real_tpl base
  real_tpl="$(theme_templates | head -1)"
  [[ -n "$real_tpl" ]] || { echo "fixture: no templates"; return 1; }
  base="$(basename "$real_tpl")"
  mkdir -p "$TEEUP_CONFIG_DIR/themed"
  cp "$real_tpl" "$TEEUP_CONFIG_DIR/themed/$base"
  local rc=0 out
  out="$(DRY_RUN=false cap_run theme doctor 2>&1)" || rc=$?
  assert_success "$rc" "a stale render is a warning, not a failure" || return 1
  assert_contains "$out" "is rendered from an older template" || return 1
  cleanup_test_env
}

# I19: theme.name is only a claim. A `teeup theme set` that wrote the name
# and then failed to render (or a hand-edited theme.name) leaves a render
# that never followed it -- nothing before this compared the two.
test_doctor_reports_a_theme_name_that_does_not_match_the_render() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  theme_set catppuccin >/dev/null 2>&1
  # A second, real, complete theme this doctor can resolve but never rendered.
  mkdir -p "$TEEUP_CONFIG_DIR/themes/otherhue"
  printf 'mode = "dark"\naccent = "#000000"\n' > "$TEEUP_CONFIG_DIR/themes/otherhue/dark.toml"
  printf 'mode = "light"\naccent = "#ffffff"\n' > "$TEEUP_CONFIG_DIR/themes/otherhue/light.toml"
  theme_list | grep -qxF otherhue || { echo "fixture: otherhue must be a real theme"; return 1; }
  printf 'otherhue\n' > "$TEEUP_STATE_DIR/current/theme.name"
  local rc=0 out
  out="$(DRY_RUN=false cap_run theme doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Current theme: otherhue" || return 1
  assert_contains "$out" "rendered from a different theme than otherhue" || return 1
  cleanup_test_env
}

# I19: a name that is not a real theme at all. Every fix line elsewhere in
# this doctor offers `teeup theme set $name`, which cannot succeed against
# this value, so it must be caught on its own before any of them fire.
test_doctor_reports_a_theme_name_that_does_not_exist() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  theme_set catppuccin >/dev/null 2>&1
  printf 'not-a-real-theme\n' > "$TEEUP_STATE_DIR/current/theme.name"
  local rc=0 out
  out="$(DRY_RUN=false cap_run theme doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "not-a-real-theme" || return 1
  assert_contains "$out" "teeup has no theme by that name" || return 1
  assert_not_contains "$out" "teeup theme set not-a-real-theme" "the fix offered must be able to succeed" || return 1
  cleanup_test_env
}

# I19: theme_current does a plain `cat`, which would otherwise die under
# `bash -eu` on an unreadable theme.name before a single finding is recorded.
test_doctor_reports_an_unreadable_theme_name_instead_of_dying() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  theme_set catppuccin >/dev/null 2>&1
  chmod 0000 "$TEEUP_STATE_DIR/current/theme.name"
  local rc=0 out
  out="$(DRY_RUN=false cap_run theme doctor 2>&1)" || rc=$?
  chmod 0644 "$TEEUP_STATE_DIR/current/theme.name"
  assert_failure "$rc" || return 1
  assert_contains "$out" "theme.name cannot be read" || return 1
  assert_not_contains "$out" "Permission denied" "raw cat stderr must not leak" || return 1
  cleanup_test_env
}

# I18: truncated is not empty and holds no {{ token }}, so it passes both of
# the other checks while the tool it belongs to reads a cut-off file.
test_doctor_reports_a_truncated_rendered_file() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  theme_set catppuccin >/dev/null 2>&1
  local rendered="$TEEUP_STATE_DIR/current/theme/dark/env.sh"
  [[ -s "$rendered" ]] || { echo "fixture: expected a non-empty render"; return 1; }
  head -c 5 "$rendered" > "$rendered.trunc" && mv "$rendered.trunc" "$rendered"
  local rc=0 out
  out="$(DRY_RUN=false cap_run theme doctor 2>&1)" || rc=$?
  assert_failure "$rc" "a truncated render is not a healthy one" || return 1
  assert_contains "$out" "does not match a fresh render" || return 1
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
run_test "a palette rewrite leaves starship.toml unedited" test_a_palette_rewrite_leaves_starship_toml_unedited
run_test "theme-apply leaves a symlinked starship.toml alone" test_theme_apply_leaves_a_symlinked_starship_toml_alone
run_test "theme-apply rewrites only the first palette line" test_theme_apply_rewrites_only_the_first_palette_line
run_test "theme-apply inserts a missing root palette" test_theme_apply_inserts_a_missing_root_palette
run_test "theme-apply inserts a root palette beside a table-scoped one" test_theme_apply_inserts_a_root_palette_beside_a_table_scoped_one
run_test "theme-apply survives a backslash in TMPDIR" test_theme_apply_survives_a_backslash_in_tmpdir
run_test "theme-apply without starship is quiet" test_theme_apply_without_starship_is_quiet
run_test "theme-apply warns when nothing rendered" test_theme_apply_warns_when_nothing_rendered
run_test "configure twice is content identical" test_configure_twice_is_content_identical
run_test "theme verbs" test_theme_verbs
run_test "theme set refuses an unknown or invalid name" test_theme_set_refuses_an_unknown_or_invalid_name
run_test "theme set is remembered by configure" test_theme_set_is_remembered_by_configure
run_test "theme set warns about a machine pin" test_theme_set_warns_about_a_machine_pin
run_test "a theme that cannot render fails set and configure" test_a_theme_that_cannot_render_fails_set_and_configure
run_test "doctor passes after a theme switch" test_doctor_passes_after_a_theme_switch
run_test "doctor reports unknown when colors.toml is missing" test_doctor_reports_unknown_when_colors_toml_is_missing
run_test "doctor reports unknown when colors.toml is invalid" test_doctor_reports_unknown_when_colors_toml_is_invalid
run_test "doctor reports a machine with no theme" test_doctor_reports_a_machine_with_no_theme
run_test "doctor reports a template never rendered" test_doctor_reports_a_template_that_was_never_rendered
run_test "doctor reports an unresolved token" test_doctor_reports_an_unresolved_token_in_a_rendered_file
run_test "doctor reports an empty rendered file" test_doctor_reports_an_empty_rendered_file
run_test "doctor reports a themed dir it cannot read" test_doctor_reports_a_themed_directory_it_cannot_read
run_test "doctor warns when a template is newer than its render" test_doctor_warns_when_a_template_is_newer_than_its_render
run_test "doctor reports a theme name that does not match the render" test_doctor_reports_a_theme_name_that_does_not_match_the_render
run_test "doctor reports a theme name that does not exist" test_doctor_reports_a_theme_name_that_does_not_exist
run_test "doctor reports an unreadable theme name instead of dying" test_doctor_reports_an_unreadable_theme_name_instead_of_dying
run_test "doctor reports a truncated rendered file" test_doctor_reports_a_truncated_rendered_file
print_summary
