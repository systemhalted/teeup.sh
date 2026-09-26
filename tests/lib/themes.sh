#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# Every shipped theme, checked against every shipped template. The tests walk
# themes/ instead of naming themes, so a theme added later is covered without
# touching this file. THEMES_UNDER_TEST points the walk at another directory,
# which is how a broken palette is shown to fail.
THEMES_UNDER_TEST="${THEMES_UNDER_TEST:-$TEEUP_PATH/themes}"

# jq and luac are found before setup_test_env narrows PATH (Homebrew's copies
# are hidden on the macOS runners). CI installs both; a machine without them
# fails the parse test rather than skipping it.
THEMES_JQ="$(command -v jq || true)"
THEMES_LUAC="$(command -v luac || command -v luac5.4 || true)"
# Resolved for the same reason, and to the same effect: if present, the
# rendered doom-theme.el files are parsed for real; if not (a developer
# machine, or a macOS CI runner, which never installs Emacs), the check below
# falls back to a paren-balance count instead of skipping outright.
THEMES_EMACS="$(command -v emacs || true)"

# bat 0.26.1's built-in themes, as `bat --list-themes` prints them. Homebrew
# and MacPorts both ship 0.26.1.
BAT_BUILTIN_THEMES='1337
Catppuccin Frappe
Catppuccin Latte
Catppuccin Macchiato
Catppuccin Mocha
Coldark-Cold
Coldark-Dark
DarkNeon
Dracula
GitHub
Monokai Extended
Monokai Extended Bright
Monokai Extended Light
Monokai Extended Origin
Nord
OneHalfDark
OneHalfLight
Solarized (dark)
Solarized (light)
Sublime Snazzy
TwoDark
Visual Studio Dark+
ansi
base16
base16-256
gruvbox-dark
gruvbox-light
zenburn'

# The colour themes in Emacs 30.1's etc/themes. The starter configuration
# installs no packages, so a palette's emacs_theme must be one of these.
EMACS_BUILTIN_THEMES='adwaita
deeper-blue
dichromacy
leuven
leuven-dark
light-blue
manoj-dark
misterioso
modus-operandi
modus-operandi-deuteranopia
modus-operandi-tinted
modus-operandi-tritanopia
modus-vivendi
modus-vivendi-deuteranopia
modus-vivendi-tinted
modus-vivendi-tritanopia
tango
tango-dark
tsdh-dark
tsdh-light
wheatgrass
whiteboard
wombat'

# The themes Zed ships in assets/themes. Only these need no extension.
ZED_BUILTIN_THEMES='One Dark
One Light
Ayu Dark
Ayu Light
Ayu Mirage
Gruvbox Dark
Gruvbox Dark Hard
Gruvbox Dark Soft
Gruvbox Light
Gruvbox Light Hard
Gruvbox Light Soft'

# Every theme in github.com/doomemacs/themes' themes/ directory, commit
# a59202912ad55014e53a685eee6cd94130bdd4fd (checked 2026-09-26, via
# api.github.com/repos/doomemacs/themes/contents/themes), as the `doom-theme'
# symbol each one defines (its filename without "-theme.el"). Doom has no
# Catppuccin port, so a palette's doom_theme names the closest one instead.
DOOM_BUILTIN_THEMES='doom-1337
doom-Iosvkem
doom-acario-dark
doom-acario-light
doom-ayu-dark
doom-ayu-light
doom-ayu-mirage
doom-badger
doom-bluloco-dark
doom-bluloco-light
doom-challenger-deep
doom-city-lights
doom-dark+
doom-dracula
doom-earl-grey
doom-ephemeral
doom-fairy-floss
doom-feather-dark
doom-feather-light
doom-flatwhite
doom-gruvbox-light
doom-gruvbox
doom-henna
doom-homage-black
doom-homage-white
doom-horizon
doom-ir-black
doom-lantern
doom-laserwave
doom-manegarm
doom-material-dark
doom-material
doom-meltbus
doom-miramare
doom-molokai
doom-monokai-classic
doom-monokai-machine
doom-monokai-octagon
doom-monokai-pro
doom-monokai-ristretto
doom-monokai-spectrum
doom-moonlight
doom-nord-aurora
doom-nord-light
doom-nord
doom-nova
doom-oceanic-next
doom-oksolar-dark
doom-oksolar-light
doom-old-hope
doom-one-light
doom-one
doom-opera-light
doom-opera
doom-outrun-electric
doom-palenight
doom-peacock
doom-pine
doom-plain-dark
doom-plain
doom-rouge
doom-shades-of-purple
doom-snazzy
doom-solarized-dark-high-contrast
doom-solarized-dark
doom-solarized-light
doom-sourcerer
doom-spacegrey
doom-tokyo-night
doom-tomorrow-day
doom-tomorrow-night
doom-vibrant
doom-wilmersdorf
doom-winter-is-coming-dark-blue
doom-winter-is-coming-light
doom-xcode
doom-zenburn'

# Values checked against each theme's upstream sources when it was added:
# "<theme> <mode> <key> <value>", the value running to the end of the line.
# A row for a theme that is not shipped fails; a shipped theme without rows
# is still covered by every other test.
upstream_anchors() {
  cat <<'ANCHORS'
catppuccin dark background #1e1e2e
catppuccin dark foreground #cdd6f4
catppuccin dark accent #89b4fa
catppuccin dark bat_theme OneHalfDark
catppuccin dark emacs_theme modus-vivendi
catppuccin dark zed_theme Catppuccin Mocha
catppuccin dark zed_extension catppuccin
catppuccin dark neovim_colorscheme catppuccin-mocha
catppuccin dark vscode_theme Catppuccin Mocha
catppuccin dark vscode_extension Catppuccin.catppuccin-vsc
catppuccin dark doom_theme doom-dracula
catppuccin light background #eff1f5
catppuccin light foreground #4c4f69
catppuccin light accent #1e66f5
catppuccin light bat_theme OneHalfLight
catppuccin light emacs_theme modus-operandi
catppuccin light zed_theme Catppuccin Latte
catppuccin light zed_extension catppuccin
catppuccin light neovim_colorscheme catppuccin-latte
catppuccin light vscode_theme Catppuccin Latte
catppuccin light vscode_extension Catppuccin.catppuccin-vsc
catppuccin light doom_theme doom-acario-light
tokyo-night dark background #1a1b26
tokyo-night dark foreground #c0caf5
tokyo-night dark accent #7aa2f7
tokyo-night dark bat_theme base16
tokyo-night dark emacs_theme modus-vivendi-tinted
tokyo-night dark zed_theme Tokyo Night
tokyo-night dark zed_extension tokyo-night
tokyo-night dark neovim_colorscheme tokyonight-night
tokyo-night dark vscode_theme Tokyo Night
tokyo-night dark vscode_extension enkia.tokyo-night
tokyo-night dark doom_theme doom-tokyo-night
tokyo-night light background #e1e2e7
tokyo-night light foreground #3760bf
tokyo-night light accent #2e7de9
tokyo-night light bat_theme base16
tokyo-night light emacs_theme modus-operandi
tokyo-night light zed_theme Tokyo Night Light
tokyo-night light zed_extension tokyo-night
tokyo-night light neovim_colorscheme tokyonight-day
tokyo-night light vscode_theme Tokyo Night Light
tokyo-night light vscode_extension enkia.tokyo-night
tokyo-night light doom_theme doom-nord-light
gruvbox dark background #282828
gruvbox dark foreground #ebdbb2
gruvbox dark accent #83a598
gruvbox dark bat_theme gruvbox-dark
gruvbox dark emacs_theme modus-vivendi
gruvbox dark zed_theme Gruvbox Dark
gruvbox dark zed_extension none
gruvbox dark neovim_colorscheme gruvbox
gruvbox dark vscode_theme Gruvbox Dark Medium
gruvbox dark vscode_extension jdinhlife.gruvbox
gruvbox dark doom_theme doom-gruvbox
gruvbox light background #fbf1c7
gruvbox light foreground #3c3836
gruvbox light accent #076678
gruvbox light bat_theme gruvbox-light
gruvbox light emacs_theme modus-operandi-tinted
gruvbox light zed_theme Gruvbox Light
gruvbox light zed_extension none
gruvbox light neovim_colorscheme gruvbox
gruvbox light vscode_theme Gruvbox Light Medium
gruvbox light vscode_extension jdinhlife.gruvbox
gruvbox light doom_theme doom-gruvbox-light
ANCHORS
}

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  # A state directory with a space and shell metacharacters: every rendered
  # path below goes through it.
  export XDG_STATE_HOME="$TEST_HOME/state dir & \$more"
  export TEEUP_THEMES_DIR="$THEMES_UNDER_TEST"
  source "$TEEUP_PATH/lib/all.sh"
  export DRY_RUN=false
  unset TEEUP_COLOR_KEYS TEEUP_COLOR_SED
}

shipped_themes() {
  local d
  for d in "$THEMES_UNDER_TEST"/*/; do
    if [[ -d "$d" ]]; then basename "$d"; fi
  done
}

# palette_value <file> <key>: the value exactly as theme_palette_load reads it.
palette_value() {
  sed -n "s/^$2[[:space:]]*=[[:space:]]*\"\(.*\)\".*\$/\1/p" "$1"
}

# palette_keys <file>: every key, sorted, duplicates kept.
palette_keys() {
  sed -n 's/^\([a-z][a-z0-9_]*\)[[:space:]]*=.*$/\1/p' "$1" | LC_ALL=C sort
}

# template_caps: a capabilities directory holding only the shipped themed/
# templates, so theme_set renders all of them and runs no hooks (a directory
# without a capability file is not a capability). Its name has a space, an
# apostrophe and an ampersand.
template_caps() {
  local d cap
  export TEEUP_CAPS_DIR="$TEST_HOME/José's caps & co"
  for d in "$TEEUP_PATH"/capabilities/*/themed; do
    if [[ -d "$d" ]]; then
      cap="$(basename "$(dirname "$d")")"
      mkdir -p "$TEEUP_CAPS_DIR/$cap"
      cp -R "$d" "$TEEUP_CAPS_DIR/$cap/themed"
    fi
  done
}

# render_theme <name>: theme_set into the test state dir; prints its log on failure.
render_theme() {
  local name="$1"
  if ! theme_set "$name" > "$TEST_HOME/set.log" 2>&1; then
    echo "teeup theme set $name failed:"
    cat "$TEST_HOME/set.log"
    return 1
  fi
  if grep -q "Falling back" "$TEST_HOME/set.log"; then
    echo "theme_set did not find $name:"
    cat "$TEST_HOME/set.log"
    return 1
  fi
}

test_every_theme_has_a_valid_name_and_both_modes() {
  setup
  local name listed found=0
  listed="$(theme_list | tr '\n' ' ')"
  for name in $(shipped_themes); do
    found=1
    [[ $name =~ $TEEUP_THEME_NAME_RE ]] || { echo "themes/$name is not a valid theme name"; return 1; }
    assert_file_exists "$THEMES_UNDER_TEST/$name/dark.toml" || return 1
    assert_file_exists "$THEMES_UNDER_TEST/$name/light.toml" || return 1
    assert_contains " $listed" " $name " "teeup theme list offers $name" || return 1
  done
  [[ $found -eq 1 ]] || { echo "no themes under $THEMES_UNDER_TEST"; return 1; }
  cleanup_test_env
}

test_every_palette_loads_for_its_own_mode() {
  setup
  local name mode
  for name in $(shipped_themes); do
    for mode in dark light; do
      theme_palette_load "$THEMES_UNDER_TEST/$name/$mode.toml" "$mode" ||
        { echo "themes/$name/$mode.toml was rejected"; return 1; }
    done
  done
  cleanup_test_env
}

test_every_palette_has_the_fallback_themes_keys() {
  setup
  local reference name mode file dupes diff_out
  # A template written against the fallback theme's keys must render with
  # any theme, so every palette defines exactly those keys, each once.
  reference="$THEMES_UNDER_TEST/$TEEUP_THEME_FALLBACK/dark.toml"
  assert_file_exists "$reference" "the fallback theme is shipped" || return 1
  for name in $(shipped_themes); do
    for mode in dark light; do
      file="$THEMES_UNDER_TEST/$name/$mode.toml"
      dupes="$(palette_keys "$file" | uniq -d | paste -s -d ' ' -)"
      [[ -z "$dupes" ]] || { echo "themes/$name/$mode.toml repeats: $dupes"; return 1; }
      diff_out="$(LC_ALL=C comm -3 <(palette_keys "$reference") <(palette_keys "$file") | tr -d '\t' | paste -s -d ' ' -)"
      [[ -z "$diff_out" ]] ||
        { echo "themes/$name/$mode.toml and themes/$TEEUP_THEME_FALLBACK/dark.toml differ in: $diff_out"; return 1; }
    done
  done
  cleanup_test_env
}

test_every_theme_renders_every_template() {
  setup
  template_caps
  local name mode state templates rendered leftover
  state="$XDG_STATE_HOME/teeup"
  templates="$(find "$TEEUP_CAPS_DIR" -path '*/themed/*.tpl' -type f | wc -l | tr -d ' ')"
  [[ "$templates" -gt 0 ]] || { echo "no templates found"; return 1; }
  for name in $(shipped_themes); do
    render_theme "$name" || return 1
    assert_equals "$name" "$(cat "$state/current/theme.name")" || return 1
    for mode in dark light; do
      # Every template plus the palette copy (colors.toml).
      rendered="$(find "$state/current/theme/$mode" -type f ! -name colors.toml | wc -l | tr -d ' ')"
      assert_equals "$templates" "$rendered" "$name $mode renders every template" || return 1
      leftover="$(grep -rl '{{' "$state/current/theme/$mode" || true)"
      [[ -z "$leftover" ]] || { echo "$name $mode left a token in: $leftover"; return 1; }
    done
  done
  cleanup_test_env
}

test_every_rendered_json_and_lua_file_parses() {
  setup
  if [[ -z "$THEMES_JQ" || -z "$THEMES_LUAC" ]]; then
    echo "jq and luac are needed: install jq and lua5.4 (apt) or lua (brew)"
    return 1
  fi
  template_caps
  local name f state
  state="$XDG_STATE_HOME/teeup"
  for name in $(shipped_themes); do
    render_theme "$name" || return 1
    while IFS= read -r f; do
      "$THEMES_JQ" -e . "$f" >/dev/null || { echo "$name: $f is not valid JSON"; return 1; }
    done < <(find "$state/current/theme" -name '*.json' -type f)
    while IFS= read -r f; do
      "$THEMES_LUAC" -p "$f" || { echo "$name: $f is not valid Lua"; return 1; }
    done < <(find "$state/current/theme" -name '*.lua' -type f)
    # env.sh is sourced by zsh: it must run, and export the palette's bat theme.
    assert_equals "$(palette_value "$THEMES_UNDER_TEST/$name/dark.toml" bat_theme)" \
      "$(sh -c '. "$1" && printf "%s" "$BAT_THEME"' sh "$state/current/theme/dark/env.sh")" || return 1
  done
  cleanup_test_env
}

# doom-theme.el is not JSON or Lua: it is checked separately, by naming the
# palette's own doom_theme and, when a real Emacs is on PATH, actually reading
# it. Without one (a developer's machine, or a macOS CI runner, neither of
# which installs Emacs), a paren-balance count stands in, the same fallback
# the JSON/Lua check above has no need of because jq and luac are required on
# every CI runner.
test_every_rendered_doom_theme_file_names_the_palette_and_parses() {
  setup
  template_caps
  local name mode state file want open close
  state="$XDG_STATE_HOME/teeup"
  for name in $(shipped_themes); do
    render_theme "$name" || return 1
    for mode in dark light; do
      file="$state/current/theme/$mode/doom-theme.el"
      assert_file_exists "$file" "$name $mode ships a doom-theme.el" || return 1
      want="$(palette_value "$THEMES_UNDER_TEST/$name/$mode.toml" doom_theme)"
      assert_contains "$(cat "$file")" "(setq doom-theme (intern \"$want\"))" || return 1
      if [[ -n "$THEMES_EMACS" ]]; then
        "$THEMES_EMACS" -Q --batch -l "$file" >/dev/null 2>&1 ||
          { echo "$name $mode: $file did not load in emacs --batch"; return 1; }
      else
        open="$(tr -cd '(' < "$file" | wc -c | tr -d ' ')"
        close="$(tr -cd ')' < "$file" | wc -c | tr -d ' ')"
        [[ "$open" == "$close" ]] ||
          { echo "$name $mode: $file has unbalanced parentheses ($open open, $close close)"; return 1; }
      fi
    done
  done
  cleanup_test_env
}

test_every_palette_names_themes_the_tools_ship() {
  setup
  local name mode file value word
  for name in $(shipped_themes); do
    for mode in dark light; do
      file="$THEMES_UNDER_TEST/$name/$mode.toml"
      value="$(palette_value "$file" bat_theme)"
      printf '%s\n' "$BAT_BUILTIN_THEMES" | grep -qxF "$value" ||
        { echo "themes/$name/$mode.toml: bat has no built-in theme named '$value'"; return 1; }
      value="$(palette_value "$file" emacs_theme)"
      printf '%s\n' "$EMACS_BUILTIN_THEMES" | grep -qxF "$value" ||
        { echo "themes/$name/$mode.toml: '$value' is not a theme built into Emacs"; return 1; }
      value="$(palette_value "$file" doom_theme)"
      printf '%s\n' "$DOOM_BUILTIN_THEMES" | grep -qxF "$value" ||
        { echo "themes/$name/$mode.toml: '$value' is not a theme built into doom-themes"; return 1; }
      # teeup's Neovim layer picks the plugin by the colorscheme's first word.
      value="$(palette_value "$file" neovim_colorscheme)"
      word="${value%%[!A-Za-z0-9]*}"
      grep -qE "^  $word = \\{" "$TEEUP_PATH/capabilities/neovim/default/teeup/neovim.lua" ||
        { echo "themes/$name/$mode.toml: no plugin for '$value' in teeup.neovim's colorscheme_plugins"; return 1; }
    done
  done
  cleanup_test_env
}

test_every_editor_theme_has_its_extension() {
  setup
  local name mode file zed_theme zed_ext vscode_ext
  local zed_id_re='^[a-z0-9][a-z0-9-]*$'
  local vscode_id_re='^[A-Za-z0-9][A-Za-z0-9-]*[.][A-Za-z0-9][A-Za-z0-9-]*$'
  for name in $(shipped_themes); do
    for mode in dark light; do
      file="$THEMES_UNDER_TEST/$name/$mode.toml"
      zed_theme="$(palette_value "$file" zed_theme)"
      zed_ext="$(palette_value "$file" zed_extension)"
      vscode_ext="$(palette_value "$file" vscode_extension)"
      if printf '%s\n' "$ZED_BUILTIN_THEMES" | grep -qxF "$zed_theme"; then
        assert_equals "none" "$zed_ext" "themes/$name/$mode.toml: $zed_theme is built into Zed" || return 1
      else
        [[ "$zed_ext" =~ $zed_id_re ]] ||
          { echo "themes/$name/$mode.toml: $zed_theme needs a Zed extension id, got '$zed_ext'"; return 1; }
      fi
      [[ "$vscode_ext" == "none" || "$vscode_ext" =~ $vscode_id_re ]] ||
        { echo "themes/$name/$mode.toml: '$vscode_ext' is not a VS Code extension id (publisher.name)"; return 1; }
    done
  done
  cleanup_test_env
}

test_every_theme_is_in_the_readme() {
  setup
  local name
  for name in $(shipped_themes); do
    grep -qF "| \`$name\` |" "$TEEUP_PATH/README.md" ||
      { echo "README.md's theme table has no row for $name"; return 1; }
  done
  cleanup_test_env
}

test_palettes_match_their_upstream_anchors() {
  setup
  local theme mode key value file actual
  while read -r theme mode key value; do
    file="$THEMES_UNDER_TEST/$theme/$mode.toml"
    assert_file_exists "$file" "an anchored theme is shipped" || return 1
    actual="$(palette_value "$file" "$key")"
    assert_equals "$value" "$actual" "themes/$theme/$mode.toml: $key" || return 1
  done < <(upstream_anchors)
  cleanup_test_env
}

echo "lib/themes (every shipped theme)"
run_test "every theme has a valid name and both modes" test_every_theme_has_a_valid_name_and_both_modes
run_test "every palette loads for its own mode" test_every_palette_loads_for_its_own_mode
run_test "every palette has the fallback theme's keys" test_every_palette_has_the_fallback_themes_keys
run_test "every theme renders every template" test_every_theme_renders_every_template
run_test "every rendered JSON and Lua file parses" test_every_rendered_json_and_lua_file_parses
run_test "every rendered doom-theme.el names the palette and parses" test_every_rendered_doom_theme_file_names_the_palette_and_parses
run_test "every palette names themes the tools ship" test_every_palette_names_themes_the_tools_ship
run_test "every editor theme has its extension" test_every_editor_theme_has_its_extension
run_test "every theme is in the README" test_every_theme_is_in_the_readme
run_test "palettes match their upstream anchors" test_palettes_match_their_upstream_anchors
print_summary
