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
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false
  unset TEEUP_COLOR_KEYS TEEUP_COLOR_SED
}

make_fixture_theme() {
  mkdir -p "$TEST_HOME/.config/teeup/themes/fixture"
  cat > "$TEST_HOME/.config/teeup/themes/fixture/dark.toml" <<'EOF2'
mode = "dark"
bat_theme = "OneHalfDark"
accent = "#89b4fa"
background = "#1e1e2e"
EOF2
  cat > "$TEST_HOME/.config/teeup/themes/fixture/light.toml" <<'EOF2'
mode = "light"
bat_theme = "OneHalfLight"
accent = "#1e66f5"
background = "#eff1f5"
EOF2
}

make_fixture_caps() {
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR/demo/themed"
  cat > "$TEEUP_CAPS_DIR/demo/capability" <<'EOF2'
summary="Fixture demo"
group=system
tier=lazy
requires=""
provides=""
interactive=false
EOF2
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/demo/install"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/demo/configure"
  cat > "$TEEUP_CAPS_DIR/demo/theme-apply" <<'EOF2'
#!/usr/bin/env bash
echo "applied:$TEEUP_THEME_NAME"
ls "$TEEUP_THEME_DIR" 2>/dev/null || true
EOF2
  chmod +x "$TEEUP_CAPS_DIR/demo/install" "$TEEUP_CAPS_DIR/demo/configure" "$TEEUP_CAPS_DIR/demo/theme-apply"
  printf 'accent=%s strip=%s rgb=%s mode=%s\n' '{{ accent }}' '{{ accent_strip }}' '{{ accent_rgb }}' '{{ mode }}' \
    > "$TEEUP_CAPS_DIR/demo/themed/demo.conf.tpl"
}

test_palette_load_exports_every_key() {
  setup
  make_fixture_theme
  theme_palette_load "$TEST_HOME/.config/teeup/themes/fixture/dark.toml"
  assert_equals "#89b4fa" "$TEEUP_COLOR_ACCENT" || return 1
  assert_equals "dark" "$TEEUP_COLOR_MODE" || return 1
  assert_equals "OneHalfDark" "$TEEUP_COLOR_BAT_THEME" || return 1
  assert_contains "$TEEUP_COLOR_KEYS" "background " || return 1
  cleanup_test_env
}

test_palette_load_forgets_the_previous_mode() {
  setup
  make_fixture_theme
  theme_palette_load "$TEST_HOME/.config/teeup/themes/fixture/dark.toml"
  theme_palette_load "$TEST_HOME/.config/teeup/themes/fixture/light.toml"
  assert_equals "#1e66f5" "$TEEUP_COLOR_ACCENT" || return 1
  assert_equals "light" "$TEEUP_COLOR_MODE" || return 1
  cleanup_test_env
}

test_render_replaces_plain_strip_and_rgb_tokens() {
  setup
  make_fixture_theme
  theme_palette_load "$TEST_HOME/.config/teeup/themes/fixture/dark.toml"
  printf 'a=%s b=%s c=%s d=%s\n' '{{ accent }}' '{{ accent_strip }}' '{{ accent_rgb }}' '{{ bat_theme }}' \
    > "$TEST_HOME/in.tpl"
  theme_render "$TEST_HOME/in.tpl" "$TEST_HOME/out/rendered.conf"
  assert_equals "a=#89b4fa b=89b4fa c=137,180,250 d=OneHalfDark" "$(cat "$TEST_HOME/out/rendered.conf")" || return 1
  cleanup_test_env
}

test_render_escapes_sed_special_characters_in_user_values() {
  setup
  # A user theme under ~/.config/teeup/themes/<name>/ is a documented,
  # supported override point, so its values must survive `&`, `|`, `\` and a
  # space intact rather than corrupting or breaking the sed script.
  mkdir -p "$TEST_HOME/.config/teeup/themes/tricky"
  cat > "$TEST_HOME/.config/teeup/themes/tricky/dark.toml" <<'EOF2'
mode = "dark"
bat_theme = "OneHalfDark"
accent = "#89b4fa"
tricky = "#a&b|c\d e"
EOF2
  theme_palette_load "$TEST_HOME/.config/teeup/themes/tricky/dark.toml"
  printf 'plain=%s strip=%s\n' '{{ tricky }}' '{{ tricky_strip }}' > "$TEST_HOME/in.tpl"
  theme_render "$TEST_HOME/in.tpl" "$TEST_HOME/out/rendered.conf"
  assert_equals 'plain=#a&b|c\d e strip=a&b|c\d e' "$(cat "$TEST_HOME/out/rendered.conf")" || return 1
  cleanup_test_env
}

test_set_renders_both_modes_and_runs_hooks() {
  setup
  make_fixture_theme
  make_fixture_caps
  local out state
  state="$TEST_HOME/.local/state/teeup"
  out="$(theme_set fixture)"
  assert_file_exists "$state/current/theme/dark/demo.conf" || return 1
  assert_file_exists "$state/current/theme/light/demo.conf" || return 1
  assert_equals "accent=#89b4fa strip=89b4fa rgb=137,180,250 mode=dark" "$(cat "$state/current/theme/dark/demo.conf")" || return 1
  assert_equals "accent=#1e66f5 strip=1e66f5 rgb=30,102,245 mode=light" "$(cat "$state/current/theme/light/demo.conf")" || return 1
  assert_equals "fixture" "$(cat "$state/current/theme.name")" || return 1
  assert_file_exists "$state/current/theme/dark/colors.toml" || return 1
  assert_contains "$out" "applied:fixture" "the theme-apply hook ran" || return 1
  [[ ! -e "$state/current/next-theme" ]] || { echo "staging dir survived the swap"; return 1; }
  cleanup_test_env
}

test_set_is_content_idempotent() {
  setup
  make_fixture_theme
  make_fixture_caps
  local state
  state="$TEST_HOME/.local/state/teeup"
  theme_set fixture >/dev/null
  cp "$state/current/theme/dark/demo.conf" "$TEST_HOME/first.conf"
  theme_set fixture >/dev/null
  cmp -s "$TEST_HOME/first.conf" "$state/current/theme/dark/demo.conf" || { echo "second run produced different output"; return 1; }
  cleanup_test_env
}

test_user_template_wins_over_the_capability_one() {
  setup
  make_fixture_theme
  make_fixture_caps
  mkdir -p "$TEST_HOME/.config/teeup/themed"
  printf 'mine %s\n' '{{ accent }}' > "$TEST_HOME/.config/teeup/themed/demo.conf.tpl"
  theme_set fixture >/dev/null
  assert_equals "mine #89b4fa" "$(cat "$TEST_HOME/.local/state/teeup/current/theme/dark/demo.conf")" || return 1
  cleanup_test_env
}

test_set_dry_run_writes_nothing() {
  setup
  make_fixture_theme
  make_fixture_caps
  # shellcheck disable=SC2034  # last assignment in the file; read by run_cmd
  DRY_RUN=true
  local out
  out="$(theme_set fixture)"
  assert_contains "$out" "[DRY-RUN] Would render demo.conf.tpl" || return 1
  assert_contains "$out" "[DRY-RUN] Would swap" || return 1
  [[ ! -e "$TEST_HOME/.local/state/teeup/current/theme" ]] || { echo "theme dir written in dry run"; return 1; }
  [[ ! -e "$TEST_HOME/.local/state/teeup/current/theme.name" ]] || { echo "theme.name written in dry run"; return 1; }
  cleanup_test_env
}

test_set_unknown_theme_falls_back_to_catppuccin() {
  setup
  local rc=0 out
  out="$(theme_set nope 2>&1)" || rc=$?
  assert_success "$rc" "theme is core; a bad name must not abort bootstrap" || return 1
  assert_contains "$out" "Unknown theme: nope" || return 1
  assert_contains "$out" "Falling back to the catppuccin theme" || return 1
  assert_equals "catppuccin" "$(cat "$TEST_HOME/.local/state/teeup/current/theme.name")" || return 1
  cleanup_test_env
}

test_set_fails_when_the_fallback_itself_is_missing() {
  setup
  export TEEUP_THEMES_DIR="$TEST_HOME/no-themes"
  local rc=0 out
  out="$(theme_set catppuccin 2>&1)" || rc=$?
  assert_failure "$rc" "a broken checkout must still fail loudly" || return 1
  assert_contains "$out" "Unknown theme: catppuccin" || return 1
  cleanup_test_env
}

test_list_and_current() {
  setup
  make_fixture_theme
  assert_contains "$(theme_list | tr '\n' ' ')" "catppuccin" "the shipped theme is listed" || return 1
  assert_contains "$(theme_list | tr '\n' ' ')" "fixture" "a user theme is listed" || return 1
  assert_equals "none" "$(theme_current)" || return 1
  cleanup_test_env
}

echo "lib/theme.sh"
run_test "palette load exports every key" test_palette_load_exports_every_key
run_test "palette load forgets the previous mode" test_palette_load_forgets_the_previous_mode
run_test "render replaces plain, strip and rgb tokens" test_render_replaces_plain_strip_and_rgb_tokens
run_test "render escapes sed special characters in user values" test_render_escapes_sed_special_characters_in_user_values
run_test "set renders both modes and runs hooks" test_set_renders_both_modes_and_runs_hooks
run_test "set is content idempotent" test_set_is_content_idempotent
run_test "user template wins over the capability one" test_user_template_wins_over_the_capability_one
run_test "set dry run writes nothing" test_set_dry_run_writes_nothing
run_test "set unknown theme falls back to catppuccin" test_set_unknown_theme_falls_back_to_catppuccin
run_test "set fails when the fallback itself is missing" test_set_fails_when_the_fallback_itself_is_missing
run_test "list and current" test_list_and_current
print_summary
