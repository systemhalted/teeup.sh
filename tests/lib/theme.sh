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

test_palette_load_rejects_values_unsafe_for_the_rendered_files() {
  setup
  # A user theme under ~/.config/teeup/themes/<name>/ is a documented override
  # point, and its values land inside a shell export, Lua strings and TOML
  # strings. A value that is not a colour or a plain name (bat theme names have
  # spaces) is refused at load, naming the file, the key and the value.
  mkdir -p "$TEST_HOME/.config/teeup/themes/tricky"
  local file value rc out
  file="$TEST_HOME/.config/teeup/themes/tricky/dark.toml"
  for value in '#a&b|c\d e' 'Monokai $(touch PWNED)' 'Monokai `id`' '#89b4fa\q' 'Solarized "dark"' 'Nord; id' ''; do
    printf 'mode = "dark"\nbat_theme = "%s"\naccent = "#89b4fa"\n' "$value" > "$file"
    rc=0
    out="$(theme_palette_load "$file" 2>&1)" || rc=$?
    assert_failure "$rc" "value [$value] must be rejected" || return 1
    assert_contains "$out" "$file" || return 1
    assert_contains "$out" "bat_theme" || return 1
    assert_contains "$out" "\"$value\"" || return 1
  done
  # bat's own built-in theme names, which every template quotes.
  for value in 'Solarized (dark)' 'Solarized (light)' 'Visual Studio Dark+' 'Monokai Extended Light'; do
    printf 'mode = "dark"\nbat_theme = "%s"\naccent = "#89b4fa"\n' "$value" > "$file"
    theme_palette_load "$file" 2>/dev/null || { echo "value [$value] must be accepted"; return 1; }
    assert_equals "$value" "$TEEUP_COLOR_BAT_THEME" || return 1
  done
  # mode is the one value rendered outside quotes ([palettes.teeup-<mode>]).
  printf 'mode = "dark (x)"\naccent = "#89b4fa"\n' > "$file"
  rc=0
  out="$(theme_palette_load "$file" 2>&1)" || rc=$?
  assert_failure "$rc" "mode must be dark or light" || return 1
  assert_contains "$out" 'mode = "dark (x)"' || return 1
  cleanup_test_env
}

test_shipped_palettes_pass_validation() {
  setup
  local f
  for f in "$TEEUP_PATH"/themes/*/dark.toml "$TEEUP_PATH"/themes/*/light.toml; do
    theme_palette_load "$f" || { echo "shipped palette $f was rejected"; return 1; }
  done
  cleanup_test_env
}

test_render_still_escapes_sed_special_characters() {
  setup
  # Load-time validation keeps these characters out of palettes; the sed
  # escaping stays as a second line of defence for the render table itself.
  make_fixture_theme
  theme_palette_load "$TEST_HOME/.config/teeup/themes/fixture/dark.toml"
  _theme_sed_entry tricky '#a&b|c\d e'
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
  local out
  out="$(theme_set fixture 2>&1)"
  assert_equals "mine #89b4fa" "$(cat "$TEST_HOME/.local/state/teeup/current/theme/dark/demo.conf")" || return 1
  assert_not_contains "$out" "shadowed" "a user template overriding a shipped one is the feature, not a problem" || return 1
  cleanup_test_env
}

# make_hook_cap <name> <interactive> <verb> <body>
make_hook_cap() {
  local name="$1" interactive="$2" verb="$3" body="$4"
  mkdir -p "$TEEUP_CAPS_DIR/$name"
  printf 'summary="Fixture %s"\ngroup=system\ntier=lazy\nrequires=""\nprovides=""\ninteractive=%s\n' "$name" "$interactive" > "$TEEUP_CAPS_DIR/$name/capability"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/$name/install"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/$name/configure"
  printf '#!/usr/bin/env bash\n%s\n' "$body" > "$TEEUP_CAPS_DIR/$name/$verb"
  chmod +x "$TEEUP_CAPS_DIR/$name/install" "$TEEUP_CAPS_DIR/$name/configure" "$TEEUP_CAPS_DIR/$name/$verb"
}

test_set_warns_when_a_capability_template_is_shadowed() {
  setup
  make_fixture_theme
  make_fixture_caps
  make_hook_cap zeta false theme-apply ':'
  mkdir -p "$TEEUP_CAPS_DIR/zeta/themed"
  printf 'zeta %s\n' '{{ accent }}' > "$TEEUP_CAPS_DIR/zeta/themed/demo.conf.tpl"
  local out
  out="$(theme_set fixture 2>&1)"
  assert_contains "$out" "$TEEUP_CAPS_DIR/zeta/themed/demo.conf.tpl was not rendered: another capability ships demo.conf.tpl" || return 1
  assert_equals "1" "$(printf '%s\n' "$out" | grep -c 'was not rendered')" "warned once, not once per mode" || return 1
  assert_equals "accent=#89b4fa strip=89b4fa rgb=137,180,250 mode=dark" "$(cat "$TEST_HOME/.local/state/teeup/current/theme/dark/demo.conf")" || return 1
  cleanup_test_env
}

test_set_runs_every_hook_after_an_interactive_one() {
  setup
  make_fixture_theme
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  # An interactive capability keeps its stdin; a hook of one that reads stdin
  # must not eat the list of capabilities still waiting for their hooks.
  make_hook_cap aaa true theme-apply 'read -r line || true; echo "aaa read:[$line]"'
  make_hook_cap bbb false theme-apply 'echo "bbb applied"'
  local out
  out="$(theme_set fixture 2>&1 </dev/null)"
  assert_contains "$out" "aaa read:[]" || return 1
  assert_contains "$out" "bbb applied" || return 1
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

# The staged swap exists so a broken switch leaves the working theme alone.
# Each case below sets the fixture theme first, breaks something, sets again,
# and checks the rendered file, the recorded name and the staging directory.
assert_previous_theme_kept() {
  local state="$TEST_HOME/.local/state/teeup"
  cmp -s "$TEST_HOME/before.conf" "$state/current/theme/dark/demo.conf" || { echo "the current theme was replaced"; return 1; }
  assert_equals "fixture" "$(cat "$state/current/theme.name")" || return 1
  [[ ! -e "$state/current/next-theme" ]] || { echo "staging dir left behind"; return 1; }
}

test_set_aborts_when_a_template_cannot_be_rendered() {
  setup
  make_fixture_theme
  make_fixture_caps
  theme_set fixture >/dev/null
  cp "$TEST_HOME/.local/state/teeup/current/theme/dark/demo.conf" "$TEST_HOME/before.conf"
  mkdir -p "$TEST_HOME/.config/teeup/themed"
  printf 'mine %s\n' '{{ accent }}' > "$TEST_HOME/.config/teeup/themed/demo.conf.tpl"
  chmod 000 "$TEST_HOME/.config/teeup/themed/demo.conf.tpl"
  if [[ -r "$TEST_HOME/.config/teeup/themed/demo.conf.tpl" ]]; then
    echo "(running as root: an unreadable file cannot be simulated; skipped)"
    cleanup_test_env
    return 0
  fi
  local rc=0 out
  out="$(theme_set fixture 2>&1)" || rc=$?
  chmod 644 "$TEST_HOME/.config/teeup/themed/demo.conf.tpl"
  assert_failure "$rc" "a failed render must fail the switch" || return 1
  assert_contains "$out" "Could not render $TEST_HOME/.config/teeup/themed/demo.conf.tpl" || return 1
  assert_contains "$out" "Theme fixture was not applied" || return 1
  assert_not_contains "$out" "applied:fixture" "no hook runs after an aborted switch" || return 1
  assert_previous_theme_kept || return 1
  cleanup_test_env
}

test_set_aborts_when_the_palette_misses_a_key() {
  setup
  make_fixture_theme
  make_fixture_caps
  theme_set fixture >/dev/null
  cp "$TEST_HOME/.local/state/teeup/current/theme/dark/demo.conf" "$TEST_HOME/before.conf"
  printf 'red=%s\n' '{{ red }}' > "$TEEUP_CAPS_DIR/demo/themed/extra.conf.tpl"
  local rc=0 out
  out="$(theme_set fixture 2>&1)" || rc=$?
  assert_failure "$rc" "unresolved tokens must fail the switch" || return 1
  assert_contains "$out" "$TEEUP_CAPS_DIR/demo/themed/extra.conf.tpl" || return 1
  assert_contains "$out" "red" || return 1
  assert_contains "$out" "Theme fixture was not applied" || return 1
  assert_previous_theme_kept || return 1
  cleanup_test_env
}

test_set_aborts_on_an_unsafe_palette_value() {
  setup
  make_fixture_theme
  make_fixture_caps
  theme_set fixture >/dev/null
  cp "$TEST_HOME/.local/state/teeup/current/theme/dark/demo.conf" "$TEST_HOME/before.conf"
  sed 's/OneHalfLight/Monokai $(id)/' "$TEST_HOME/.config/teeup/themes/fixture/light.toml" > "$TEST_HOME/light.toml"
  mv "$TEST_HOME/light.toml" "$TEST_HOME/.config/teeup/themes/fixture/light.toml"
  local rc=0 out
  out="$(theme_set fixture 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" 'bat_theme = "Monokai $(id)"' || return 1
  assert_previous_theme_kept || return 1
  cleanup_test_env
}

test_list_offers_only_themes_with_both_modes() {
  setup
  mkdir -p "$TEST_HOME/.config/teeup/themes/half"
  printf 'mode = "dark"\naccent = "#89b4fa"\n' > "$TEST_HOME/.config/teeup/themes/half/dark.toml"
  assert_not_contains "$(theme_list | tr '\n' ' ')" "half" || return 1
  local rc=0 out
  out="$(theme_set half 2>&1)" || rc=$?
  assert_success "$rc" "a half theme is an unknown name, which falls back" || return 1
  assert_contains "$out" "Falling back to the catppuccin theme" || return 1
  [[ ! -e "$TEST_HOME/.local/state/teeup/current/next-theme" ]] || { echo "staging dir left behind"; return 1; }
  cleanup_test_env
}

test_theme_names_are_validated() {
  setup
  local d rc out
  for d in "My Theme" "Bad_Name"; do
    mkdir -p "$TEST_HOME/.config/teeup/themes/$d"
    cp "$TEEUP_PATH/themes/catppuccin/dark.toml" "$TEEUP_PATH/themes/catppuccin/light.toml" "$TEST_HOME/.config/teeup/themes/$d/"
  done
  out="$(theme_list 2>"$TEST_HOME/list.err")"
  assert_not_contains "$out" "My" "a name with a space is not offered" || return 1
  assert_not_contains "$out" "Bad_Name" || return 1
  assert_contains "$out" "catppuccin" || return 1
  assert_contains "$(cat "$TEST_HOME/list.err")" "Ignoring theme $TEST_HOME/.config/teeup/themes/My Theme" || return 1
  rc=0
  out="$(theme_dir ../../teeup/themes/catppuccin 2>&1)" || rc=$?
  assert_failure "$rc" "a path is not a theme name" || return 1
  assert_contains "$out" "Invalid theme name: ../../teeup/themes/catppuccin" || return 1
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
run_test "palette load rejects values unsafe for the rendered files" test_palette_load_rejects_values_unsafe_for_the_rendered_files
run_test "shipped palettes pass validation" test_shipped_palettes_pass_validation
run_test "render still escapes sed special characters" test_render_still_escapes_sed_special_characters
run_test "set renders both modes and runs hooks" test_set_renders_both_modes_and_runs_hooks
run_test "set is content idempotent" test_set_is_content_idempotent
run_test "user template wins over the capability one" test_user_template_wins_over_the_capability_one
run_test "set warns when a capability template is shadowed" test_set_warns_when_a_capability_template_is_shadowed
run_test "set runs every hook after an interactive one" test_set_runs_every_hook_after_an_interactive_one
run_test "set dry run writes nothing" test_set_dry_run_writes_nothing
run_test "set unknown theme falls back to catppuccin" test_set_unknown_theme_falls_back_to_catppuccin
run_test "set fails when the fallback itself is missing" test_set_fails_when_the_fallback_itself_is_missing
run_test "set aborts when a template cannot be rendered" test_set_aborts_when_a_template_cannot_be_rendered
run_test "set aborts when the palette misses a key" test_set_aborts_when_the_palette_misses_a_key
run_test "set aborts on an unsafe palette value" test_set_aborts_on_an_unsafe_palette_value
run_test "list offers only themes with both modes" test_list_offers_only_themes_with_both_modes
run_test "theme names are validated" test_theme_names_are_validated
run_test "list and current" test_list_and_current
print_summary
