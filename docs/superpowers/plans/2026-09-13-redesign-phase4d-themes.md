# teeup Redesign, Phase 4d: More Themes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship three themes beyond Catppuccin (`tokyo-night`, `gruvbox`, `everforest`), each a dark and a light palette whose colours come from the theme's upstream source and whose editor names load the matching theme in bat, Emacs, Zed, Neovim and VS Code, plus one table-driven suite that renders every shipped theme through every shipped template.

**Architecture:** A theme is data: `themes/<name>/{dark,light}.toml`, rendered by the existing `lib/theme.sh` through every `capabilities/*/themed/*.tpl`. No library, capability, hook or verb changes. Task 1 adds `tests/lib/themes.sh`, which walks `themes/` instead of naming themes, so every later theme (shipped or added after this plan) is validated, rendered and checked for leftover tokens without a test edit; it also pins the upstream-verified values in a small anchor table, adds a README "Themes" section, and replaces the bootstrap test that asserted `tokyo-night` is not offered with one that asserts every shipped theme is. Tasks 2 to 4 add one theme each, test first through that anchor table.

**Tech Stack:** bash 3.2 (macOS stock), BSD `sed`, TOML palettes, the phase 1 mock-binary test harness, `jq` and `luac` for parsing rendered files in tests.

**Spec:** `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md`. This plan covers "remaining themes" from the phase 4 row of "Migration path for the repo", the interview answer for Themes ("cross-tool theme system, a few themes, light/dark following macOS appearance"), the `theme mode` rule of section 3 ("every theme ships `dark.toml` and `light.toml`"), and section 7's "Themes" paragraph. The spec needs no amendment: it names no themes beyond the one phase 2 shipped.

---

## Global Constraints

- bash 3.2 compatible everywhere: no `mapfile`, `declare -A`, `${var,,}`/`${var^^}`, `readarray`, `readlink -f`; no same-line `local` back-references; `10#$n` for arithmetic on numbers that came from text. bash 3.2 mis-parses a quoted pattern containing `/` inside `${var//pat/repl}`: use `replace_literal` (`lib/files.sh`); run `shopt -u patsub_replacement 2>/dev/null || true` before a `${var//}` replacement containing `&`. Nothing in this plan uses `${var//}`. A regular expression used with `=~` is kept in a variable, never written inline.
- BSD tools only: no GNU-only flags for `sed`, `grep`, `find`, `sort`, `comm`, `paste`, `wc`; no `\t` or `\n` in a `sed` replacement; awk values through `ENVIRON`, never `-v`, when they may contain backslashes (this plan uses no awk).
- Capability scripts: `#!/usr/bin/env bash`, `bash -eu`, `lib/all.sh` loaded, no `local`, mocked commands by bare name, every mutation through `run_cmd`/`run_privileged` or a `DRY_RUN`-guarded primitive. This plan adds and edits no capability script; the rule is listed so an executor who is tempted to "fix" a hook in passing stops.
- Paths: `user_config_dir` for `~/.config`; `TEEUP_CONFIG_DIR`/`TEEUP_STATE_DIR` honoured; paths with spaces and metacharacters must work. `tests/lib/themes.sh` renders into `XDG_STATE_HOME="$TEST_HOME/state dir & \$more"` from a capabilities directory named `José's caps & co`.
- Machine file precedence (answers, then `machines/<hostname>.conf`) for every consumer of an answer. The only answer involved is `TEEUP_THEME`; the pinned-theme wizard test already on `main` stays as it is.
- `capability` metadata contract (`summary group tier requires provides packages casks apps interactive`) and the tier lists are untouched; `teeup commands --check` must stay silent.
- Palette rules enforced by `lib/theme.sh` on `main`: a theme name matches `^[a-z0-9][a-z0-9-]*$`; a theme is offered only with both `dark.toml` and `light.toml`; `mode` must equal the file's mode; every value matches `^[#A-Za-z0-9][A-Za-z0-9 ._()+-]*$` (so no `é`, quote, `$`, backtick, `;` or backslash); a template that fails to render or leaves a `{{ key }}` token aborts the whole switch. `theme_palette_load` reads a value as everything between the first and the last double quote on its line, so a trailing comment after a value must contain no double quote.
- Every palette defines exactly the keys `themes/catppuccin/dark.toml` defines after plan 3a (the 25 colour keys, `mode`, `bat_theme`, and 3a's `emacs_theme zed_theme zed_extension neovim_colorscheme vscode_theme vscode_extension`), each once. Every colour is a named colour from the theme's upstream source, and the upstream name is in a comment on the same line.
- Tests: `tests/helper.sh` (temp `HOME`, `MOCK_BIN` first on the narrowed `PATH` `$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin`, `mock_command`, `mock_command_script`, `mock_macos_base`, `TEEUP_TEST_MISSING`, `TEEUP_PKG_PREFIX`, `TEEUP_APPS_DIR`). The narrowed `PATH` hides Homebrew, so `jq` and `luac` are resolved before `setup_test_env`. CI runs `macos-14`, `macos-15-intel` and `ubuntu-latest`; every runner has `jq`, and `ci.yml` installs `lua`/`lua5.4`. A test that passes only on a developer's machine is a defect.
- Every task ends with `./tests/run.sh` green, `./bin/teeup commands --check` silent with exit 0, `shellcheck --severity=warning` clean on every new or edited script and test, `git diff --check` clean, and **one** commit with a plain imperative subject and no trailer of any kind (no `Co-Authored-By`, no `Claude-Session`, no "Generated with").
- Suite counts: `tests/run.sh` ends with `All N suites passed.` Never hard-code N: each task states "the suite count printed before this task, plus K". Per-suite counts are exact for `tests/lib/themes.sh`, which only this plan touches; for `tests/bootstrap.sh` they are stated relative to the count before the task, because plans 4a to 4c may add tests to it.
- Nothing in this phase has run on a real Mac. Each task carries a **Real-Mac risk** note naming what only hardware proves.
- Verify, do not guess: every palette value, theme name, extension id and built-in theme list below was checked against the upstream file and commit the task's "External facts" block names, on 2026-09-13. A value or name not listed there is not to be introduced during execution without the same check.
- Plain prose in every comment, log line and doc: none of "No X, no Y" chains, "That's the whole ...", "Don't X it. Y it.", "Sit with that", "You already know", "is the entire", "The punchline", "Worth naming", "X is real, and ...".

---

## Depends on

Phase 3 is planned, not implemented. For code on `main` the code is the ground truth; for code plan 3a adds, its plan text is. Pre-flight: confirm each item below exists in the tree before starting Task 1.

| Interface consumed | Defined by | Used by |
|---|---|---|
| `capabilities/emacs/themed/emacs.el.tpl` (tokens `mode`, `emacs_theme`, 16 colour keys); `teeup-apply-theme` in `capabilities/emacs/default/teeup/init.el` disabling the enabled themes, then catching a theme that fails to load with a message | 3a Task 2 | Tasks 1 to 4 (render), Tasks 2 to 4 (the Real-Mac notes on tinted Modus themes) |
| `capabilities/zed/themed/zed.json.tpl` (`zed_theme`, `zed_extension`); `capabilities/zed/theme-apply` skipping an extension named `none` | 3a Task 3 | Tasks 1, 3 (gruvbox's built-in Zed theme) |
| `capabilities/neovim/themed/neovim.lua.tpl` (`neovim_colorscheme`, 16 colour keys); `M.colorscheme_plugins` in `capabilities/neovim/default/teeup/neovim.lua`, keyed by the colorscheme's first word (`catppuccin tokyonight gruvbox nord kanagawa everforest rosepine`), and `M.load` setting `vim.o.background` from the mode before `colorscheme` | 3a Task 5 | Task 1 (the plugin-lookup test), Tasks 2 to 4 |
| `capabilities/vscode/themed/vscode.json.tpl` (`vscode_theme`, `vscode_extension`); `capabilities/vscode/theme-apply` skipping `none` | 3a Task 6 | Tasks 1 to 4 |
| Contract 5 of plan 3a: both modes of every theme define the six editor name keys; `themes/catppuccin/{dark,light}.toml` carry them (`modus-vivendi`/`modus-operandi`, `Catppuccin Mocha`/`Catppuccin Latte` with `catppuccin`, `catppuccin-mocha`/`catppuccin-latte`, `Catppuccin Mocha`/`Catppuccin Latte` with `Catppuccin.catppuccin-vsc`) | 3a Tasks 2, 3, 5, 6 | Task 1 (anchor rows, the key-set reference) |
| The wizard order in `bootstrap` (package manager, name, email, theme, daily confirm, then the Emacs flavor only after a yes, an empty answer meaning `starter`; work is never asked, it is per-machine) and `WIZARD_INPUT` in `tests/bootstrap.sh` | 3a Task 2 | Task 1 (the wizard test's input) |
| The README "Editors" section ending with "Catppuccin extension for Zed and VS Code) and a hook that tells a running editor to pick it up." | 3a Task 7 | Task 1 (the anchor for the "Themes" section) |
| `test_wizard_does_not_ask_for_a_pinned_theme` and the `tokyo-night` assertion in `test_the_package_manager_is_asked_before_it_is_installed` in `tests/bootstrap.sh` | `main` (phase 2b) | Task 1 |
| `theme_list`, `theme_set`, `theme_palette_load`, `TEEUP_THEME_NAME_RE`, `TEEUP_THEME_FALLBACK`, `TEEUP_THEMES_DIR` | `main` (`lib/theme.sh`) | Task 1 |

**Plan 3b:** this plan consumes nothing from it (no function, verb, file or state path). The one file both touch is `README.md`: 3b's "Lazy capabilities" section is anchored on the per-machine overrides paragraph, and this plan's section is anchored on 3a's Editors text above that paragraph, so they land in either order.

**Plans 4a to 4c** (executed before this one): nothing is consumed from them. Two ways they could meet this plan, both caught by Task 1's suite rather than silently: (1) if an earlier plan adds a themed template that uses a new palette key, it adds that key to `themes/catppuccin/*.toml`, and `every palette has the fallback theme's keys` names it for each new theme; add the key to each new palette, with a value named from that theme's upstream source, in the task that ships the theme. (2) If 4a wires a `theme-set` hook event into `theme_set`, the suite's temporary `HOME` has no hooks directory, so nothing changes. The `tests/bootstrap.sh` anchors below are phase 2b text that 4a to 4c have no reason to change; if one did, re-quote the anchor from the file and keep the replacement.

---

## Decisions made here

1. **Three themes: `tokyo-night`, `gruvbox`, `everforest`.** Each has an upstream dark and light variant, a Neovim plugin that plan 3a's layer already maps, a VS Code extension on the Marketplace, and a Zed theme (built in for Gruvbox, an extension for the other two). **Rosé Pine is left out:** its Zed and VS Code theme names are `Rosé Pine` and `Rosé Pine Dawn`, and `é` fails `lib/theme.sh`'s palette value check, so the theme could not name its own editor themes without loosening a check that exists to keep palette values out of shell, Lua and TOML quoting trouble. Plan 3a's `rosepine` plugin key would also never match (the lookup takes the first word of `rose-pine`, which is `rose`).
2. **Colours come from each theme's own upstream palette, not from Omarchy's.** Catppuccin's palette matches Omarchy on purpose, but Omarchy ships only a dark `tokyo-night`, `gruvbox` and `everforest`, its `gruvbox` is Gruvbox Material (`#d4be98` foreground), and its `tokyo-night` mixes folke's palette with enkia's VS Code colours. The editor names in these palettes load folke's Tokyo Night, morhetz's Gruvbox and sainnhe's Everforest, so the terminal and prompt take the same sources: `folke/tokyonight.nvim` `extras/lua/tokyonight_{night,day}.lua`, `morhetz/gruvbox` `colors/gruvbox.vim`, `sainnhe/everforest` `autoload/everforest.vim` (medium contrast, the default of both its Neovim and VS Code ports).
3. **Role mapping.** `background` is the editor background; `foreground` the editor foreground; `accent` the theme's blue (Everforest: `statusline1`, its own emphasis green); `selection` the Visual background; `muted` the terminal's bright black; the six hues and their `bright_` pairs are the upstream terminal colours (`terminal_color_0..15` or tokyonight's `terminal` table), because `wezterm.lua.tpl` builds its ANSI table from them. `dark_background`, `darker_background` and `lighter_background` take the theme's own darker and raised backgrounds; where an upstream palette has fewer steps than teeup's keys, the nearest named colour repeats (Gruvbox dark has one background darker than `bg0`). None of the three palettes has a brown: `brown`, which no shipped template reads and exists so a template written against Catppuccin's keys renders, repeats an orange from the same palette, named in the comment.
4. **Emacs gets built-in themes.** The starter installs no packages (3a decision 10), so each palette names a Modus theme: the blue-black `modus-vivendi-tinted` for Tokyo Night's night, the warm `modus-operandi-tinted` for Gruvbox's and Everforest's light variants, plain Modus otherwise. The tinted variants exist since Emacs 30.1 (`etc/themes` on `emacs-30.1`; absent on `emacs-29`). The `emacs-app` cask and the `emacs` port are 31.1. On an older Emacs, 3a's `teeup-apply-theme` has already disabled the enabled themes when `load-theme` fails, so its `condition-case` leaves the default colours and a message in `*Messages*`. Doom and Spacemacs do not read `emacs_theme` at all.
5. **bat gets `base16` where it ships no theme.** bat 0.26.1 has built-in `gruvbox-dark` and `gruvbox-light`, and nothing for Tokyo Night or Everforest. `base16` draws with the terminal's own sixteen colours, which WezTerm takes from this palette, so bat follows the theme without a guess at the "closest" truecolour theme.
6. **Light editor themes are the ones the same extension ships.** `enkia.tokyo-night` and the `tokyo-night` Zed extension ship `Tokyo Night Light`, which is enkia's light palette rather than folke's day style; the Neovim colorscheme is folke's `tokyonight-day`. The terminal follows folke's day palette. A closer light port would mean a second extension per editor for one mode, so the README table says which names are used.
7. **One table-driven suite, `tests/lib/themes.sh`, owned by this plan.** Validation, key set, rendering, parse checks and the name checks walk `themes/`, so a theme added later is covered without editing the suite. The anchor table is the only per-theme data: rows pin the upstream-checked background, foreground, accent and the seven tool names, which gives each theme task a test that fails first, and a shipped theme without rows is still fully checked. `THEMES_UNDER_TEST` lets a step prove the suite fails on a broken palette.
8. **The rendering test runs `theme_set` against a copy of the shipped `themed/` directories with no `capability` files.** That exercises the real staging, validation and leftover-token checks while running no `theme-apply` hook (a directory without a `capability` file is not in `cap_list`), so it needs no editor mocks and cannot touch a developer's running editors.
9. **No `teeup theme next`.** The spec's command list is `teeup theme set|list|current`, and the phase 4 seams give 4d no verbs. Omarchy's `theme-next` cycles a desktop background along with the theme, which has no counterpart here.
10. **The spec is not edited.** It asks for "a few themes" without naming them.

---

## File structure

| Path | Responsibility |
|---|---|
| `tests/lib/themes.sh` | New suite: every shipped theme is valid, has the fallback theme's keys, renders every template, produces parseable JSON and Lua, names themes bat, Emacs, Neovim's teeup layer and Zed actually have, is in the README table, and matches its upstream anchors. |
| `tests/bootstrap.sh` | The wizard offers every shipped theme (and not a half theme) and renders the one chosen by number; the old "`tokyo-night` is not offered" assertion goes. |
| `README.md` | A "Themes" section after 3a's "Editors": the per-tool name table (one row per theme), notes on bat, Emacs, Zed, VS Code and Neovim, and how to add a theme of your own. |
| `themes/tokyo-night/{dark,light}.toml` | folke's Tokyo Night, night and day styles. |
| `themes/gruvbox/{dark,light}.toml` | morhetz's Gruvbox, medium contrast. |
| `themes/everforest/{dark,light}.toml` | sainnhe's Everforest, medium contrast. |

**Reading this plan mechanically.** Every fenced block whose info string carries `file=<path>` is the complete content of that file after the step. Every edit to an existing file is a pair of blocks, `edit-old=<path>` (text that exists at that point, quoted exactly and occurring exactly once in the file) followed by `edit-new=<path>` (what replaces it). Blocks without either marker are commands or illustrations and change nothing.

---
### Task 1: The every-theme suite, the wizard test and the README section

**Files:**
- Create: `tests/lib/themes.sh` (new suite)
- Modify: `tests/bootstrap.sh`, `README.md`

**Interfaces:**
- Consumes: `theme_list`, `theme_set`, `theme_palette_load`, `TEEUP_THEME_NAME_RE`, `TEEUP_THEME_FALLBACK` and `TEEUP_THEMES_DIR` (`lib/theme.sh` on `main`); every `capabilities/*/themed/*.tpl` (three on `main`, four from plan 3a); `M.colorscheme_plugins` in `capabilities/neovim/default/teeup/neovim.lua` (3a Task 5); the wizard input order of 3a Task 2; 3a Task 7's README "Editors" text.
- Produces: `tests/lib/themes.sh` with nine tests and the `upstream_anchors` heredoc, whose closing lines `ANCHORS` and `}` are the anchor Tasks 2 to 4 insert rows above; `THEMES_UNDER_TEST` (defaults to `$TEEUP_PATH/themes`); the README "Themes" section whose table has the row `` | `catppuccin` | Mocha, Latte | ...`` that Tasks 2 to 4 insert their rows after; `test_the_wizard_offers_every_shipped_theme` in `tests/bootstrap.sh`.

**External facts (verified 2026-09-13):**
- bat 0.26.1 is current (`gh api repos/sharkdp/bat/releases/latest`: `v0.26.1`, tag commit `979ba226`); Homebrew's `bat` formula and MacPorts' `bat` port are both 0.26.1. `bat --list-themes` from a build of that commit prints the 28 names in `BAT_BUILTIN_THEMES`; its README ("8-bit themes") says `base16` "uses 4-bit colors (3-bit colors plus bright variants)" from the terminal. Catppuccin's four themes arrived in 0.26.0 (`CHANGELOG.md`: "Add Catppuccin, see #3317").
- Emacs `etc/themes` at tag `emacs-30.1`: the 23 colour themes in `EMACS_BUILTIN_THEMES` plus `modus-themes.el`; the `emacs-29` branch has only `modus-operandi` and `modus-vivendi` among the Modus themes. Emacs 31.1 (installed) loads `modus-vivendi-tinted` and `modus-operandi-tinted` with `load-theme`.
- Zed `assets/themes` at `zed-industries/zed` `7960b2a7`: `one/one.json` (`One Dark`, `One Light`), `ayu/ayu.json` (`Ayu Dark`, `Ayu Light`, `Ayu Mirage`), `gruvbox/gruvbox.json` (`Gruvbox Dark`, `Gruvbox Dark Hard`, `Gruvbox Dark Soft`, `Gruvbox Light`, `Gruvbox Light Hard`, `Gruvbox Light Soft`).
- `jq` is preinstalled on the three GitHub runner images; `ci.yml` on `main` installs `lua5.4` (with a `luac` link) or `lua`.

**Real-Mac risk:** none of its own: the suite runs under the harness, and the wizard test drives `ui_choose`'s plain fallback (`TEEUP_NO_GUM=1`). With `gum` installed the same list appears as a `gum choose` menu, which only an interactive run on a Mac shows.

- [ ] **Step 1: Write the suite `tests/lib/themes.sh`**

```bash file=tests/lib/themes.sh
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
run_test "every palette names themes the tools ship" test_every_palette_names_themes_the_tools_ship
run_test "every editor theme has its extension" test_every_editor_theme_has_its_extension
run_test "every theme is in the README" test_every_theme_is_in_the_readme
run_test "palettes match their upstream anchors" test_palettes_match_their_upstream_anchors
print_summary
```

- [ ] **Step 2: Run it: the README test fails, everything else passes against Catppuccin**

Run: `bash tests/lib/themes.sh`
Expected: `Summary: 8/9 passed`, with `every theme is in the README` failing on `README.md's theme table has no row for catppuccin`.

- [ ] **Step 3: Prove the walk catches a broken palette**

```bash
broken="$(mktemp -d)"
cp -R themes/catppuccin "$broken/"
sed -i.bak '/^zed_theme/d' "$broken/catppuccin/light.toml" && rm "$broken/catppuccin/light.toml.bak"
THEMES_UNDER_TEST="$broken" bash tests/lib/themes.sh
rm -rf "$broken"
```

Expected: `Summary: 4/9 passed` (the README test still fails, as in Step 2), with `every palette has the fallback theme's keys` naming `zed_theme`, `every theme renders every template` and `every rendered JSON and Lua file parses` printing `the catppuccin light palette has no value for: zed_theme`, and `palettes match their upstream anchors` expecting `Catppuccin Latte`. Nothing in the checkout changed.

- [ ] **Step 4: Add the "Themes" section to the README**

The anchor is the end of plan 3a's "Editors" section. Plan 3b's "Lazy capabilities" section goes after the per-machine overrides paragraph below it, so the two do not collide.

```markdown edit-old=README.md
Catppuccin extension for Zed and VS Code) and a hook that tells a running
editor to pick it up.
```

```markdown edit-new=README.md
Catppuccin extension for Zed and VS Code) and a hook that tells a running
editor to pick it up.

### Themes

Every theme is a dark and a light palette; apps follow the macOS appearance
between the two. `teeup theme list` shows what is available and
`teeup theme set <name>` switches every app at once. Each palette also names
the theme each tool should load:

| Theme | Palettes | bat | Emacs | Zed | Neovim | VS Code |
|---|---|---|---|---|---|---|
| `catppuccin` | Mocha, Latte | `OneHalfDark`, `OneHalfLight` | `modus-vivendi`, `modus-operandi` | Catppuccin Mocha, Latte (extension `catppuccin`) | `catppuccin-mocha`, `catppuccin-latte` | Catppuccin Mocha, Latte (`Catppuccin.catppuccin-vsc`) |

- **Emacs** gets a theme built into Emacs, because the starter configuration
  installs no packages; Doom and Spacemacs keep the theme their own
  configuration picks.
- **Zed** installs a theme's extension the next time it starts; **VS Code**
  gets its extension through the `code` command. A theme Zed ships needs no
  extension.
- **Neovim** fetches the colorscheme's plugin through lazy.nvim on its next
  start.

A theme of your own goes in `~/.config/teeup/themes/<name>/` as `dark.toml`
and `light.toml`, and wins over a shipped theme of the same name. Copy a
shipped theme and change the values: every key must stay, each value is a
colour (`#rrggbb`) or a plain name, and the name is lower-case letters, digits
and dashes. `tests/lib/themes.sh` renders every shipped theme through every
template; a theme added to `themes/` needs a row in the table above.
```

- [ ] **Step 5: Run the suite again**

Run: `bash tests/lib/themes.sh`
Expected: `Summary: 9/9 passed`.

- [ ] **Step 6: Replace the "unshipped theme" assertion in `tests/bootstrap.sh`**

The assertion names `tokyo-night`, which Task 2 ships. Its intent (the wizard offers only complete themes) moves into a test that walks `themes/`.

```bash edit-old=tests/bootstrap.sh
  assert_contains "$out" "Package manager already recorded: homebrew" || return 1
  # The wizard's theme question offers only what themes/ ships (catppuccin);
  # ui_choose prints its options on stderr, which this test already captures.
  assert_not_contains "$out" "tokyo-night" "the wizard must not offer an unshipped theme" || return 1
  cleanup_test_env
}
```

```bash edit-new=tests/bootstrap.sh
  assert_contains "$out" "Package manager already recorded: homebrew" || return 1
  cleanup_test_env
}
```

- [ ] **Step 7: Add the wizard test after the pinned-theme test**

```bash edit-old=tests/bootstrap.sh
  assert_not_contains "$out" "Skipping the daily tier (TEEUP_DAILY=no)" "the daily answer lined up with its question" || return 1
  assert_contains "$out" "Bootstrap finished" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}
```

```bash edit-new=tests/bootstrap.sh
  assert_not_contains "$out" "Skipping the daily tier (TEEUP_DAILY=no)" "the daily answer lined up with its question" || return 1
  assert_contains "$out" "Bootstrap finished" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_the_wizard_offers_every_shipped_theme() {
  setup
  # A user theme with only one mode is not a theme, so it is never offered.
  mkdir -p "$TEST_HOME/.config/teeup/themes/half"
  printf 'mode = "dark"\n' > "$TEST_HOME/.config/teeup/themes/half/dark.toml"
  local expected count last d name i=0 out
  # The wizard offers theme_list's sorted names; ui_choose's plain fallback
  # prints them as "  <n>) <name>" on stderr, which is captured here.
  expected="$(for d in "$TEEUP_PATH"/themes/*/; do basename "$d"; done | sort)"
  # Answer the theme question with the last number, so bootstrap renders the
  # theme listed last rather than the default.
  count="$(printf '%s\n' "$expected" | wc -l | tr -d ' ')"
  last="$(printf '%s\n' "$expected" | tail -n 1)"
  out="$("$BOOT" --dry-run 2>&1 <<<$'1\nAda Lovelace\nada@example.com\n\n'"$count"$'\ny\n')"
  while IFS= read -r name; do
    i=$((i + 1))
    assert_contains "$out" "  $i) $name" "the wizard offers $name as option $i" || return 1
  done <<<"$expected"
  assert_not_contains "$out" ") half" "a theme with one mode is not offered" || return 1
  assert_contains "$out" "Would set TEEUP_THEME" || return 1
  assert_contains "$out" "and record theme $last" "bootstrap renders the theme chosen by number" || return 1
  cleanup_test_env
}
```

```bash edit-old=tests/bootstrap.sh
run_test "the wizard does not ask for a pinned theme" test_wizard_does_not_ask_for_a_pinned_theme
```

```bash edit-new=tests/bootstrap.sh
run_test "the wizard does not ask for a pinned theme" test_wizard_does_not_ask_for_a_pinned_theme
run_test "the wizard offers every shipped theme" test_the_wizard_offers_every_shipped_theme
```

- [ ] **Step 8: Run the bootstrap suite**

Run: `bash tests/bootstrap.sh`
Expected: `Summary: N/N passed`, where N is one more than before this step (25 on a tree with plan 3a and nothing else). The new test passes at once with Catppuccin alone: it is coverage for Tasks 2 to 4, and it was checked to fail when its last assertion names a theme other than the last one listed.

- [ ] **Step 9: Full checks and commit**

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning tests/lib/themes.sh tests/bootstrap.sh
git diff --check
git add tests/lib/themes.sh tests/bootstrap.sh README.md
git commit -m "Check every shipped theme against every template"
```

Expected: `commands --check`, shellcheck and `git diff --check` print nothing; `./tests/run.sh` ends with `All N suites passed.` where N is the suite count printed before this task, plus 1.

---

### Task 2: `tokyo-night`

**Files:**
- Create: `themes/tokyo-night/dark.toml`, `themes/tokyo-night/light.toml`
- Modify: `tests/lib/themes.sh` (anchor rows), `README.md` (table row, bat and Emacs notes)

**Interfaces:**
- Consumes: Task 1's `upstream_anchors` heredoc and README table; 3a's `tokyonight` entry in `M.colorscheme_plugins` (`folke/tokyonight.nvim`, which LazyVim already installs).
- Produces: the theme name `tokyo-night` in `teeup theme list` and the wizard.

**External facts (verified 2026-09-13):**
- `folke/tokyonight.nvim` at `cdc07ac78467a233fd62c493de29a17e0cf2b2b6`: `extras/lua/tokyonight_night.lua` and `extras/lua/tokyonight_day.lua` hold the generated palettes (`bg`, `bg_dark`, `bg_dark1`, `bg_highlight`, `bg_visual`, `fg`, `fg_dark`, `comment`, `blue`, `orange`, `terminal_black` and the `terminal` table); every colour in both palette files was compared by script against these files by the name in its comment. `colors/tokyonight-night.lua` and `colors/tokyonight-day.lua` exist, so `tokyonight-night` and `tokyonight-day` are colorscheme names.
- Zed: `zed-industries/extensions` at `6a833fe7`, `extensions.toml` `[tokyo-night]` version 0.8.0, submodule `ssaunderss/zed-tokyo-night` at `6d731d07`, whose `extension.toml` has `id = "tokyo-night"` and `themes/tokyo-night.json` names `Tokyo Night` (dark, `editor.background` `#1a1b26`), `Tokyo Night Light` (light), `Tokyo Night Storm` and `Tokyo Night Moon`.
- VS Code: Marketplace `enkia.tokyo-night` 1.1.2; its manifest contributes the themes `Tokyo Night`, `Tokyo Night Storm` and `Tokyo Night Light` with no `id`, so the label is the settings name (`enkia/tokyo-night-vscode-theme` `package.json` at `7c0f11ea` agrees).
- bat 0.26.1 ships no Tokyo Night theme (Task 1's list).

**Real-Mac risk:** only a Mac with the apps proves that (a) Zed installs the `tokyo-night` extension on its next start and resolves `Tokyo Night` and `Tokyo Night Light` without a "theme not found" notice, (b) `code --install-extension enkia.tokyo-night` succeeds and `workbench.preferredLightColorTheme: "Tokyo Night Light"` is picked when System Settings switches to Light, (c) the Emacs daemon started by 3a's LaunchAgent loads `modus-vivendi-tinted` in a GUI frame, and (d) WezTerm and bat's `base16` look right on both appearances.

- [ ] **Step 1: Add the upstream anchor rows**

```bash edit-old=tests/lib/themes.sh
ANCHORS
}
```

```bash edit-new=tests/lib/themes.sh
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
ANCHORS
}
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `bash tests/lib/themes.sh`
Expected: `Summary: 8/9 passed`; `palettes match their upstream anchors` fails with `File not found: .../themes/tokyo-night/dark.toml`.

- [ ] **Step 3: Write `themes/tokyo-night/dark.toml`**

```toml file=themes/tokyo-night/dark.toml
# Tokyo Night, the "night" style, as a teeup semantic palette. Every colour is
# a named colour from folke/tokyonight.nvim's generated palette,
# extras/lua/tokyonight_night.lua at commit cdc07ac7 (the name is in the
# comment), so WezTerm, Starship and the editors below draw the same theme.
mode = "dark"

# Names, not colours. bat has no Tokyo Night theme built in; base16 draws with
# the terminal's own sixteen colours, which WezTerm takes from this palette.
bat_theme = "base16"

# Emacs: a built-in theme (the starter installs no packages); Modus Vivendi
# Tinted is Modus's night-blue variant, built in since Emacs 30.1.
emacs_theme = "modus-vivendi-tinted"
# Zed: the "tokyo-night" extension (ssaunderss/zed-tokyo-night).
zed_theme = "Tokyo Night"
zed_extension = "tokyo-night"
# Neovim: folke/tokyonight.nvim, which LazyVim already ships.
neovim_colorscheme = "tokyonight-night"
# VS Code: enkia.tokyo-night.
vscode_theme = "Tokyo Night"
vscode_extension = "enkia.tokyo-night"

accent = "#7aa2f7"                # blue
selection = "#283457"             # bg_visual
muted = "#414868"                 # terminal_black (bright black)

background = "#1a1b26"            # bg
dark_background = "#16161e"       # bg_dark
darker_background = "#0c0e14"     # bg_dark1
lighter_background = "#292e42"    # bg_highlight

foreground = "#c0caf5"            # fg
dark_foreground = "#565f89"       # comment
light_foreground = "#a9b1d6"      # fg_dark
bright_foreground = "#c0caf5"     # terminal.white_bright

red = "#f7768e"                   # terminal.red
yellow = "#e0af68"                # terminal.yellow
orange = "#ff9e64"                # orange
green = "#9ece6a"                 # terminal.green
cyan = "#7dcfff"                  # terminal.cyan
blue = "#7aa2f7"                  # terminal.blue
magenta = "#bb9af7"               # terminal.magenta
brown = "#ff9e64"                 # no brown upstream: orange

bright_red = "#ff899d"            # terminal.red_bright
bright_yellow = "#faba4a"         # terminal.yellow_bright
bright_green = "#9fe044"          # terminal.green_bright
bright_cyan = "#a4daff"           # terminal.cyan_bright
bright_blue = "#8db0ff"           # terminal.blue_bright
bright_magenta = "#c7a9ff"        # terminal.magenta_bright
```

- [ ] **Step 4: Write `themes/tokyo-night/light.toml`**

```toml file=themes/tokyo-night/light.toml
# Tokyo Night, the "day" style. Every colour is a named colour from
# folke/tokyonight.nvim's extras/lua/tokyonight_day.lua at commit cdc07ac7.
# Same keys as dark.toml, mapped from the same upstream names.
mode = "light"

bat_theme = "base16"

# Tokyo Night's light editor ports are Tokyo Night Light (enkia's palette,
# not folke's day style); they are the light themes the same extensions ship.
emacs_theme = "modus-operandi"
zed_theme = "Tokyo Night Light"
zed_extension = "tokyo-night"
neovim_colorscheme = "tokyonight-day"
vscode_theme = "Tokyo Night Light"
vscode_extension = "enkia.tokyo-night"

accent = "#2e7de9"                # blue
selection = "#b7c1e3"             # bg_visual
muted = "#a1a6c5"                 # terminal_black (bright black)

background = "#e1e2e7"            # bg
dark_background = "#d0d5e3"       # bg_dark
darker_background = "#c1c9df"     # bg_dark1
lighter_background = "#c4c8da"    # bg_highlight

foreground = "#3760bf"            # fg
dark_foreground = "#848cb5"       # comment
light_foreground = "#6172b0"      # fg_dark
bright_foreground = "#3760bf"     # terminal.white_bright

red = "#f52a65"                   # terminal.red
yellow = "#8c6c3e"                # terminal.yellow
orange = "#b15c00"                # orange
green = "#587539"                 # terminal.green
cyan = "#007197"                  # terminal.cyan
blue = "#2e7de9"                  # terminal.blue
magenta = "#9854f1"               # terminal.magenta
brown = "#b15c00"                 # no brown upstream: orange

bright_red = "#ff4774"            # terminal.red_bright
bright_yellow = "#a27629"         # terminal.yellow_bright
bright_green = "#5c8524"          # terminal.green_bright
bright_cyan = "#007ea8"           # terminal.cyan_bright
bright_blue = "#358aff"           # terminal.blue_bright
bright_magenta = "#a463ff"        # terminal.magenta_bright
```

- [ ] **Step 5: Run the suite: only the README row is missing**

Run: `bash tests/lib/themes.sh`
Expected: `Summary: 8/9 passed`; `every theme is in the README` fails with `README.md's theme table has no row for tokyo-night`.

- [ ] **Step 6: Add the README row and the bat and Emacs notes**

```markdown edit-old=README.md
| `catppuccin` | Mocha, Latte | `OneHalfDark`, `OneHalfLight` | `modus-vivendi`, `modus-operandi` | Catppuccin Mocha, Latte (extension `catppuccin`) | `catppuccin-mocha`, `catppuccin-latte` | Catppuccin Mocha, Latte (`Catppuccin.catppuccin-vsc`) |
```

```markdown edit-new=README.md
| `catppuccin` | Mocha, Latte | `OneHalfDark`, `OneHalfLight` | `modus-vivendi`, `modus-operandi` | Catppuccin Mocha, Latte (extension `catppuccin`) | `catppuccin-mocha`, `catppuccin-latte` | Catppuccin Mocha, Latte (`Catppuccin.catppuccin-vsc`) |
| `tokyo-night` | night, day | `base16` | `modus-vivendi-tinted`, `modus-operandi` | Tokyo Night, Tokyo Night Light (extension `tokyo-night`) | `tokyonight-night`, `tokyonight-day` | Tokyo Night, Tokyo Night Light (`enkia.tokyo-night`) |
```

```markdown edit-old=README.md
- **Emacs** gets a theme built into Emacs, because the starter configuration
  installs no packages; Doom and Spacemacs keep the theme their own
  configuration picks.
```

```markdown edit-new=README.md
- **bat** gets `base16` when it ships no theme for the palette: `base16`
  draws with the terminal's sixteen colours, which WezTerm takes from the
  same palette.
- **Emacs** gets a theme built into Emacs, because the starter configuration
  installs no packages; Doom and Spacemacs keep the theme their own
  configuration picks. The tinted Modus themes need Emacs 30.1 or later; an
  older Emacs falls back to its default colours and says why in
  `*Messages*`.
```

- [ ] **Step 7: Run the suites**

Run: `bash tests/lib/themes.sh && bash tests/bootstrap.sh`
Expected: `Summary: 9/9 passed`, then the bootstrap suite with the same count as after Task 1, all passing; its wizard test now expects `  2) tokyo-night` and answers `2`.

- [ ] **Step 8: Full checks and commit**

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning tests/lib/themes.sh
git diff --check
git add themes/tokyo-night/dark.toml themes/tokyo-night/light.toml tests/lib/themes.sh README.md
git commit -m "Add the tokyo-night theme"
```

Expected: `commands --check`, shellcheck and `git diff --check` print nothing; `./tests/run.sh` ends with `All N suites passed.` where N is the suite count printed before this task, plus 0.

---

### Task 3: `gruvbox`

**Files:**
- Create: `themes/gruvbox/dark.toml`, `themes/gruvbox/light.toml`
- Modify: `tests/lib/themes.sh` (anchor rows), `README.md` (table row)

**Interfaces:**
- Consumes: Task 1's `upstream_anchors` heredoc and README table; 3a's `gruvbox` entry in `M.colorscheme_plugins` (`ellisonleao/gruvbox.nvim`); 3a's Zed and VS Code hooks skipping an extension named `none`.
- Produces: the theme name `gruvbox`.

**External facts (verified 2026-09-13):**
- `morhetz/gruvbox` at `5d15b2765f59754d7ac263c88a0f6e3e58124951`, `colors/gruvbox.vim`: the `s:gb` palette (`dark0_hard #1d2021` ... `faded_orange #af3a03`); `Normal` is `fg1` on `bg0`, `Visual` is `bg3`, `LineNr` `bg4`, `Comment` `gray`; for a dark background `bg0..4` are `dark0..4` and `fg1..4` are `light1..4`, reversed for light; `terminal_color_0` is `bg0`, `1..6` the `neutral_*` colours, `7` `fg4`, `8` `gray`, `9..14` `s:red`...`s:aqua` (`bright_*` on dark, `faded_*` on light), `15` `fg1`. Every colour in both palette files was compared by script against the `s:gb` names in its comment.
- bat 0.26.1 ships `gruvbox-dark` and `gruvbox-light` (Task 1's list).
- Zed ships `Gruvbox Dark` (`editor.background` `#282828`) and `Gruvbox Light` (`#fbf1c7`) in `assets/themes/gruvbox/gruvbox.json` at `7960b2a7`, so there is no extension.
- VS Code: Marketplace `jdinhlife.gruvbox` 1.29.1, whose manifest contributes `Gruvbox Dark Medium`, `Gruvbox Dark Hard`, `Gruvbox Dark Soft`, `Gruvbox Light Medium`, `Gruvbox Light Hard` and `Gruvbox Light Soft`, none with an `id`.
- Neovim: `ellisonleao/gruvbox.nvim` at `154eb5ff` has `colors/gruvbox.lua`, and `lua/gruvbox.lua` reads `vim.o.background`, which 3a's `M.load` sets from the mode before loading the colorscheme.

**Real-Mac risk:** only real apps prove that (a) Zed picks its built-in `Gruvbox Light` when the appearance changes, with nothing added to `auto_install_extensions`, (b) `jdinhlife.gruvbox` installs through `code` and `Gruvbox Light Medium` resolves, (c) on the first `nvim` after `teeup theme set gruvbox`, lazy.nvim clones `ellisonleao/gruvbox.nvim` before LazyVim's colorscheme hook runs (lazy.nvim's default installs missing plugins at startup; without the network LazyVim falls back to `habamax` with a message), and (d) `modus-operandi-tinted` loads in the Emacs daemon.

- [ ] **Step 1: Add the upstream anchor rows**

```bash edit-old=tests/lib/themes.sh
ANCHORS
}
```

```bash edit-new=tests/lib/themes.sh
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
ANCHORS
}
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `bash tests/lib/themes.sh`
Expected: `Summary: 8/9 passed`; `palettes match their upstream anchors` fails with `File not found: .../themes/gruvbox/dark.toml`.

- [ ] **Step 3: Write `themes/gruvbox/dark.toml`**

```toml file=themes/gruvbox/dark.toml
# Gruvbox dark, medium contrast, as a teeup semantic palette. Every colour is
# a named colour from morhetz/gruvbox's colors/gruvbox.vim at commit 5d15b276
# (the name is in the comment); the ANSI roles follow that file's
# terminal_color_0..15 for a dark background.
mode = "dark"

# Names, not colours. bat ships gruvbox-dark; Zed ships Gruvbox built in, so
# there is no Zed extension to install.
bat_theme = "gruvbox-dark"
emacs_theme = "modus-vivendi"
zed_theme = "Gruvbox Dark"
zed_extension = "none"
# Neovim: ellisonleao/gruvbox.nvim, which follows 'background'.
neovim_colorscheme = "gruvbox"
# VS Code: jdinhlife.gruvbox.
vscode_theme = "Gruvbox Dark Medium"
vscode_extension = "jdinhlife.gruvbox"

accent = "#83a598"                # bright_blue
selection = "#665c54"             # dark3 (Visual)
muted = "#928374"                 # gray_245 (terminal_color_8)

background = "#282828"            # dark0
dark_background = "#1d2021"       # dark0_hard
darker_background = "#1d2021"     # dark0_hard, the darkest gruvbox has
lighter_background = "#3c3836"    # dark1

foreground = "#ebdbb2"            # light1 (fg1)
dark_foreground = "#7c6f64"       # dark4
light_foreground = "#a89984"      # light4 (terminal_color_7)
bright_foreground = "#ebdbb2"     # light1 (terminal_color_15)

red = "#cc241d"                   # neutral_red
yellow = "#d79921"                # neutral_yellow
orange = "#fe8019"                # bright_orange
green = "#98971a"                 # neutral_green
cyan = "#689d6a"                  # neutral_aqua
blue = "#458588"                  # neutral_blue
magenta = "#b16286"               # neutral_purple
brown = "#d65d0e"                 # no brown upstream: neutral_orange

bright_red = "#fb4934"            # bright_red
bright_yellow = "#fabd2f"         # bright_yellow
bright_green = "#b8bb26"          # bright_green
bright_cyan = "#8ec07c"           # bright_aqua
bright_blue = "#83a598"           # bright_blue
bright_magenta = "#d3869b"        # bright_purple
```

- [ ] **Step 4: Write `themes/gruvbox/light.toml`**

```toml file=themes/gruvbox/light.toml
# Gruvbox light, medium contrast. Every colour is a named colour from
# morhetz/gruvbox's colors/gruvbox.vim at commit 5d15b276; the ANSI roles
# follow that file's terminal_color_0..15 for a light background, where the
# bright colours are the faded_* set.
mode = "light"

bat_theme = "gruvbox-light"
emacs_theme = "modus-operandi-tinted"
zed_theme = "Gruvbox Light"
zed_extension = "none"
neovim_colorscheme = "gruvbox"
vscode_theme = "Gruvbox Light Medium"
vscode_extension = "jdinhlife.gruvbox"

accent = "#076678"                # faded_blue
selection = "#bdae93"             # light3 (Visual)
muted = "#928374"                 # gray_244 (terminal_color_8)

background = "#fbf1c7"            # light0
dark_background = "#ebdbb2"       # light1
darker_background = "#d5c4a1"     # light2
lighter_background = "#f2e5bc"    # light0_soft

foreground = "#3c3836"            # dark1 (fg1)
dark_foreground = "#a89984"       # light4
light_foreground = "#7c6f64"      # dark4 (terminal_color_7)
bright_foreground = "#3c3836"     # dark1 (terminal_color_15)

red = "#cc241d"                   # neutral_red
yellow = "#d79921"                # neutral_yellow
orange = "#af3a03"                # faded_orange
green = "#98971a"                 # neutral_green
cyan = "#689d6a"                  # neutral_aqua
blue = "#458588"                  # neutral_blue
magenta = "#b16286"               # neutral_purple
brown = "#af3a03"                 # no brown upstream: faded_orange

bright_red = "#9d0006"            # faded_red
bright_yellow = "#b57614"         # faded_yellow
bright_green = "#79740e"          # faded_green
bright_cyan = "#427b58"           # faded_aqua
bright_blue = "#076678"           # faded_blue
bright_magenta = "#8f3f71"        # faded_purple
```

- [ ] **Step 5: Run the suite: only the README row is missing**

Run: `bash tests/lib/themes.sh`
Expected: `Summary: 8/9 passed`; `every theme is in the README` fails with `README.md's theme table has no row for gruvbox`.

- [ ] **Step 6: Add the README row**

The row goes right after Catppuccin's, which keeps the table in the order `teeup theme list` prints.

```markdown edit-old=README.md
| `catppuccin` | Mocha, Latte | `OneHalfDark`, `OneHalfLight` | `modus-vivendi`, `modus-operandi` | Catppuccin Mocha, Latte (extension `catppuccin`) | `catppuccin-mocha`, `catppuccin-latte` | Catppuccin Mocha, Latte (`Catppuccin.catppuccin-vsc`) |
```

```markdown edit-new=README.md
| `catppuccin` | Mocha, Latte | `OneHalfDark`, `OneHalfLight` | `modus-vivendi`, `modus-operandi` | Catppuccin Mocha, Latte (extension `catppuccin`) | `catppuccin-mocha`, `catppuccin-latte` | Catppuccin Mocha, Latte (`Catppuccin.catppuccin-vsc`) |
| `gruvbox` | dark, light (medium contrast) | `gruvbox-dark`, `gruvbox-light` | `modus-vivendi`, `modus-operandi-tinted` | Gruvbox Dark, Gruvbox Light (built in) | `gruvbox` | Gruvbox Dark Medium, Gruvbox Light Medium (`jdinhlife.gruvbox`) |
```

- [ ] **Step 7: Run the suites**

Run: `bash tests/lib/themes.sh && bash tests/bootstrap.sh`
Expected: `Summary: 9/9 passed`, then the bootstrap suite with the same count as before this task, all passing; its wizard test now lists `  2) gruvbox` and `  3) tokyo-night` and answers `3`.

- [ ] **Step 8: Full checks and commit**

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning tests/lib/themes.sh
git diff --check
git add themes/gruvbox/dark.toml themes/gruvbox/light.toml tests/lib/themes.sh README.md
git commit -m "Add the gruvbox theme"
```

Expected: `commands --check`, shellcheck and `git diff --check` print nothing; `./tests/run.sh` ends with `All N suites passed.` where N is the suite count printed before this task, plus 0.

---

### Task 4: `everforest`

**Files:**
- Create: `themes/everforest/dark.toml`, `themes/everforest/light.toml`
- Modify: `tests/lib/themes.sh` (anchor rows), `README.md` (table row)

**Interfaces:**
- Consumes: Task 1's `upstream_anchors` heredoc and README table; 3a's `everforest` entry in `M.colorscheme_plugins` (`neanias/everforest-nvim`).
- Produces: the theme name `everforest`.

**External facts (verified 2026-09-13):**
- `sainnhe/everforest` at `85a86eb62409e3ec88713bff3d1b9d7374e112e4`: `autoload/everforest.vim` `everforest#get_palette` (for `medium`: dark `bg_dim #232a2e`, `bg0 #2d353b` ... `bg_visual #543a48`; light `bg_dim #efebd4`, `bg0 #fdf6e3` ... `bg5 #bdc3af`, `bg_visual #eaedc8`; for `hard` dark `bg_dim #1e2326`; `palette2` dark `fg #d3c6aa` ... `statusline1 #a7c080`, light `fg #5c6a72` ... `statusline1 #93b259`); `colors/everforest.vim`: `Normal` `fg` on `bg0`, `Visual` `bg_visual`, `Comment` `grey1`, and terminal colours `black` = `bg3` (dark) or `fg` (light), `white` = `fg` (dark) or `bg3` (light), `terminal_color_8..15` repeating `0..7`. Every colour in both palette files was compared by script against these names.
- Zed: `extensions.toml` at `6a833fe7`, `[everforest]` version 0.2.0, submodule `albertsko/zed-everforest` at `1f1c84e0`: `extension.toml` `id = "everforest"`, and `themes/everforest-regular.json` names `Everforest Dark Medium (regular)` (`editor.background` `#2d353b`) and `Everforest Light Medium (regular)` (`#fdf6e3`). Parentheses pass the palette value check.
- VS Code: Marketplace `sainnhe.everforest` 0.3.0, manifest themes `Everforest Dark` and `Everforest Light` (no `id`); `sainnhe/everforest-vscode` `package.json` at `b17f8aff` agrees.
- Neovim: `neanias/everforest-nvim` at `a0e9edc5` has `colors/everforest.lua`; `lua/everforest/init.lua` defaults `background = "medium"` and builds the palette from `vim.o.background`.
- bat 0.26.1 ships no Everforest theme.

**Real-Mac risk:** only real apps prove that (a) Zed installs the `everforest` extension and resolves both `(regular)` names, (b) `sainnhe.everforest` installs and its `Everforest Light` is picked on the light appearance, (c) lazy.nvim fetches `neanias/everforest-nvim` on the first start as in Task 3, and (d) the palette's `selection` (`bg_visual`, a muted plum on dark) is readable as WezTerm's selection background, which `wezterm.lua.tpl` pairs with the background colour as text.

- [ ] **Step 1: Add the upstream anchor rows**

```bash edit-old=tests/lib/themes.sh
ANCHORS
}
```

```bash edit-new=tests/lib/themes.sh
everforest dark background #2d353b
everforest dark foreground #d3c6aa
everforest dark accent #a7c080
everforest dark bat_theme base16
everforest dark emacs_theme modus-vivendi
everforest dark zed_theme Everforest Dark Medium (regular)
everforest dark zed_extension everforest
everforest dark neovim_colorscheme everforest
everforest dark vscode_theme Everforest Dark
everforest dark vscode_extension sainnhe.everforest
everforest light background #fdf6e3
everforest light foreground #5c6a72
everforest light accent #93b259
everforest light bat_theme base16
everforest light emacs_theme modus-operandi-tinted
everforest light zed_theme Everforest Light Medium (regular)
everforest light zed_extension everforest
everforest light neovim_colorscheme everforest
everforest light vscode_theme Everforest Light
everforest light vscode_extension sainnhe.everforest
ANCHORS
}
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `bash tests/lib/themes.sh`
Expected: `Summary: 8/9 passed`; `palettes match their upstream anchors` fails with `File not found: .../themes/everforest/dark.toml`.

- [ ] **Step 3: Write `themes/everforest/dark.toml`**

```toml file=themes/everforest/dark.toml
# Everforest dark, medium contrast, as a teeup semantic palette. Every colour
# is a named colour from sainnhe/everforest's autoload/everforest.vim at
# commit 85a86eb6 (the name is in the comment), and the ANSI roles follow
# colors/everforest.vim's terminal colours, whose bright set repeats the
# normal one.
mode = "dark"

# Names, not colours. bat has no Everforest theme built in; base16 draws with
# the terminal's own sixteen colours, which WezTerm takes from this palette.
bat_theme = "base16"
emacs_theme = "modus-vivendi"
# Zed: the "everforest" extension (albertsko/zed-everforest).
zed_theme = "Everforest Dark Medium (regular)"
zed_extension = "everforest"
# Neovim: neanias/everforest-nvim, which follows 'background'.
neovim_colorscheme = "everforest"
# VS Code: sainnhe.everforest, whose contrast setting defaults to medium.
vscode_theme = "Everforest Dark"
vscode_extension = "sainnhe.everforest"

accent = "#a7c080"                # statusline1
selection = "#543a48"             # bg_visual
muted = "#475258"                 # bg3 (terminal black)

background = "#2d353b"            # bg0
dark_background = "#232a2e"       # bg_dim
darker_background = "#1e2326"     # bg_dim of the hard palette
lighter_background = "#343f44"    # bg1

foreground = "#d3c6aa"            # fg
dark_foreground = "#859289"       # grey1 (Comment)
light_foreground = "#9da9a0"      # grey2
bright_foreground = "#d3c6aa"     # fg (terminal white)

red = "#e67e80"                   # red
yellow = "#dbbc7f"                # yellow
orange = "#e69875"                # orange
green = "#a7c080"                 # green
cyan = "#83c092"                  # aqua
blue = "#7fbbb3"                  # blue
magenta = "#d699b6"               # purple
brown = "#e69875"                 # no brown upstream: orange

bright_red = "#e67e80"            # red
bright_yellow = "#dbbc7f"         # yellow
bright_green = "#a7c080"          # green
bright_cyan = "#83c092"           # aqua
bright_blue = "#7fbbb3"           # blue
bright_magenta = "#d699b6"        # purple
```

- [ ] **Step 4: Write `themes/everforest/light.toml`**

```toml file=themes/everforest/light.toml
# Everforest light, medium contrast. Every colour is a named colour from
# sainnhe/everforest's autoload/everforest.vim at commit 85a86eb6; the
# upstream terminal palette for a light background uses fg as black, so
# muted takes bg5, the grey upstream draws line numbers in.
mode = "light"

bat_theme = "base16"
emacs_theme = "modus-operandi-tinted"
zed_theme = "Everforest Light Medium (regular)"
zed_extension = "everforest"
neovim_colorscheme = "everforest"
vscode_theme = "Everforest Light"
vscode_extension = "sainnhe.everforest"

accent = "#93b259"                # statusline1
selection = "#eaedc8"             # bg_visual
muted = "#bdc3af"                 # bg5

background = "#fdf6e3"            # bg0
dark_background = "#efebd4"       # bg_dim
darker_background = "#e0dcc7"     # bg4
lighter_background = "#f4f0d9"    # bg1

foreground = "#5c6a72"            # fg
dark_foreground = "#939f91"       # grey1 (Comment)
light_foreground = "#829181"      # grey2
bright_foreground = "#5c6a72"     # fg

red = "#f85552"                   # red
yellow = "#dfa000"                # yellow
orange = "#f57d26"                # orange
green = "#8da101"                 # green
cyan = "#35a77c"                  # aqua
blue = "#3a94c5"                  # blue
magenta = "#df69ba"               # purple
brown = "#f57d26"                 # no brown upstream: orange

bright_red = "#f85552"            # red
bright_yellow = "#dfa000"         # yellow
bright_green = "#8da101"          # green
bright_cyan = "#35a77c"           # aqua
bright_blue = "#3a94c5"           # blue
bright_magenta = "#df69ba"        # purple
```

- [ ] **Step 5: Run the suite: only the README row is missing**

Run: `bash tests/lib/themes.sh`
Expected: `Summary: 8/9 passed`; `every theme is in the README` fails with `README.md's theme table has no row for everforest`.

- [ ] **Step 6: Add the README row**

```markdown edit-old=README.md
| `catppuccin` | Mocha, Latte | `OneHalfDark`, `OneHalfLight` | `modus-vivendi`, `modus-operandi` | Catppuccin Mocha, Latte (extension `catppuccin`) | `catppuccin-mocha`, `catppuccin-latte` | Catppuccin Mocha, Latte (`Catppuccin.catppuccin-vsc`) |
```

```markdown edit-new=README.md
| `catppuccin` | Mocha, Latte | `OneHalfDark`, `OneHalfLight` | `modus-vivendi`, `modus-operandi` | Catppuccin Mocha, Latte (extension `catppuccin`) | `catppuccin-mocha`, `catppuccin-latte` | Catppuccin Mocha, Latte (`Catppuccin.catppuccin-vsc`) |
| `everforest` | dark, light (medium contrast) | `base16` | `modus-vivendi`, `modus-operandi-tinted` | Everforest Dark Medium (regular), Everforest Light Medium (regular) (extension `everforest`) | `everforest` | Everforest Dark, Everforest Light (`sainnhe.everforest`) |
```

- [ ] **Step 7: Run the suites**

Run: `bash tests/lib/themes.sh && bash tests/bootstrap.sh`
Expected: `Summary: 9/9 passed`, then the bootstrap suite with the same count as before this task, all passing; its wizard test now lists `  1) catppuccin`, `  2) everforest`, `  3) gruvbox`, `  4) tokyo-night` and answers `4`.

- [ ] **Step 8: Full checks and commit**

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning tests/lib/themes.sh
git diff --check
git add themes/everforest/dark.toml themes/everforest/light.toml tests/lib/themes.sh README.md
git commit -m "Add the everforest theme"
```

Expected: `commands --check`, shellcheck and `git diff --check` print nothing; `./tests/run.sh` ends with `All N suites passed.` where N is the suite count printed before this task, plus 0.

---
## Verification

Run from the repository root after Task 4, on a machine with `shellcheck`, `jq`, `lua`/`luac` and (for the last check) `emacs` 30.1 or later:

```bash
./bin/teeup commands --check          # prints nothing
./tests/run.sh                        # All N suites passed: the count before Task 1, plus 1
bash tests/lib/themes.sh              # Summary: 9/9 passed
shellcheck --severity=warning tests/lib/themes.sh tests/bootstrap.sh
./bin/teeup theme list                # catppuccin, everforest, gruvbox, tokyo-night
```

Then, under a throwaway `$HOME`, render each new theme with the real capabilities (their hooks find no installed editor and do nothing) and load each rendered Emacs theme:

```bash
for t in tokyo-night gruvbox everforest; do
  tmp="$(mktemp -d)"
  env HOME="$tmp" XDG_CONFIG_HOME="$tmp/.config" XDG_STATE_HOME="$tmp/.local/state" ./bin/teeup theme set "$t"
  ls "$tmp/.local/state/teeup/current/theme/dark"
  grep -rl '{{' "$tmp/.local/state/teeup/current/theme" || echo "no tokens left"
  for m in dark light; do
    emacs --batch -Q --eval "(progn (load \"$tmp/.local/state/teeup/current/theme/$m/emacs.el\") (load-theme teeup-theme-name t) (princ (format \"%s loaded\n\" teeup-theme-name)))"
  done
  rm -rf "$tmp"
done
```

Expected for each theme: `Theme set to <name>`, the eight files `colors.toml emacs.el env.sh neovim.lua starship-palette.toml vscode.json wezterm.lua zed.json`, `no tokens left`, and two `... loaded` lines (`modus-vivendi-tinted`/`modus-operandi`, `modus-vivendi`/`modus-operandi-tinted`, `modus-vivendi`/`modus-operandi-tinted`).

**What the first real run on a Mac should show.** Nothing in this plan has executed on macOS. In order:

1. `./bootstrap --reconfigure` offers `1) catppuccin 2) everforest 3) gruvbox 4) tokyo-night` (as a `gum` menu when gum is installed).
2. `teeup theme set tokyo-night`: WezTerm reloads in Tokyo Night; a new zsh has `BAT_THEME=base16` and `bat` highlights with the terminal's colours; switching System Settings to Light and opening a new tab gives the day palette.
3. With Zed installed through teeup: Zed installs the `tokyo-night` extension and follows the appearance between `Tokyo Night` and `Tokyo Night Light`. `teeup theme set gruvbox` switches it to the built-in Gruvbox with no extension added; `teeup theme set everforest` adds `everforest` to `auto_install_extensions`.
4. With VS Code installed through teeup: the three extensions install through `code` and VS Code follows the appearance between the two names in the README table.
5. With the Emacs starter: `emacsclient -c` shows `modus-vivendi-tinted` for Tokyo Night on a dark appearance.
6. `teeup install neovim`, `teeup theme set gruvbox`, then `nvim`: lazy.nvim installs `gruvbox.nvim` and the colorscheme loads with `background` following the appearance.

---

## Self-review

### Spec coverage

| Requirement | Source | Task |
|---|---|---|
| "A few themes" beyond the one phase 2 shipped | interview table, Themes row; migration path phase 4 "remaining themes" | 2, 3, 4 |
| Every theme ships `dark.toml` and `light.toml`; apps follow macOS appearance | spec section 3 (`theme mode`), section 7 "Themes" | 2, 3, 4 (both files each); 1 (`every theme has a valid name and both modes`, `every palette loads for its own mode`) |
| `teeup theme set <name>` renders every `capabilities/*/themed/*.tpl` for both modes | spec section 7 "Themes" | 1 (`every theme renders every template`, table-driven over themes and templates, including 3a's four editor templates) |
| Zed and VS Code get `theme` written by jq; bat via `BAT_THEME` | spec section 7 "Themes" | 2, 3, 4 (names and extensions verified upstream); 1 (JSON parses, `env.sh` exports the palette's bat theme, bat and Zed names checked against the tools' built-in lists) |
| Wizard theme question offers what `themes/` ships | spec section 5 step 4; phase 2b's wizard | 1 (`the wizard offers every shipped theme`) |
| Every theme is tested, and a future theme is covered automatically | brief | 1 |
| README theme section | brief | 1 (section and Catppuccin row), 2 to 4 (one row each) |
| Spec updated only if needed | brief | not needed (Decision 10) |
| `teeup theme next` only if the spec or Omarchy justifies it | brief | not added (Decision 9) |

### External facts and their sources (all fetched or run on 2026-09-13)

- Palettes, compared by a script that read each palette line's trailing comment, looked the upstream name up in the fetched file and compared the value (150 colour values, 25 per file, zero mismatches): `folke/tokyonight.nvim` `cdc07ac78467a233fd62c493de29a17e0cf2b2b6` `extras/lua/tokyonight_night.lua`, `extras/lua/tokyonight_day.lua` (also `extras/wezterm/tokyonight_{night,day}.toml` for the ANSI order); `morhetz/gruvbox` `5d15b2765f59754d7ac263c88a0f6e3e58124951` `colors/gruvbox.vim`; `sainnhe/everforest` `85a86eb62409e3ec88713bff3d1b9d7374e112e4` `autoload/everforest.vim` and `colors/everforest.vim`.
- Zed: `zed-industries/zed` `7960b2a7c9568e90fbe0727332149e5b2a5fd57a` `assets/themes/{one,ayu,gruvbox}/*.json`; `zed-industries/extensions` `6a833fe78b7c982e04724c892b532029043706e9` `extensions.toml` and `.gitmodules`; `ssaunderss/zed-tokyo-night` `6d731d0724a6fa487f9031cbb4f8db0b80769568` (`extension.toml`, `themes/tokyo-night.json`); `albertsko/zed-everforest` `1f1c84e081f6dcaaac7105812032086608ca7a44` (`extension.toml`, `themes/everforest-regular.json`).
- VS Code: the Marketplace gallery API (`extensionquery`, then each version's `Microsoft.VisualStudio.Code.Manifest`) for `enkia.tokyo-night` 1.1.2, `jdinhlife.gruvbox` 1.29.1, `sainnhe.everforest` 0.3.0 and `Catppuccin.catppuccin-vsc` 3.19.0; theme labels as listed in Tasks 2 to 4, none with an `id`, so each label is the name `workbench.preferred*ColorTheme` takes (as plan 3a verified in `workbenchThemeService.ts`).
- Neovim: `folke/tokyonight.nvim` `colors/`; `ellisonleao/gruvbox.nvim` `154eb5ff5b96d0641307113fa385eaf0d36d9796` `colors/gruvbox.lua`, `lua/gruvbox.lua`; `neanias/everforest-nvim` `a0e9edc57379e8feafc6ba207c26dbb12fc1b6d8` `colors/everforest.lua`, `lua/everforest/init.lua`, `lua/everforest/colours.lua`. Plan 3a's `M.plugin_for` run under `lua` with a stub `vim` table maps `tokyonight-night`, `tokyonight-day`, `gruvbox`, `everforest` and `catppuccin-latte` to the expected repositories.
- bat: `sharkdp/bat` release `v0.26.1` (commit `979ba226`), `README.md` "8-bit themes", `CHANGELOG.md`; `bat --list-themes` from a build of that commit; `formulae.brew.sh/api/formula/bat.json` and `ports.macports.org/api/v1/ports/bat/` (both 0.26.1).
- Emacs: `emacs-mirror/emacs` `etc/themes` listings at tag `emacs-30.1` and branches `emacs-29` (no tinted Modus) and `emacs-30`, `emacs-31`; Emacs 31.1 (installed) `load-theme` of both tinted variants; `formulae.brew.sh/api/cask/emacs-app.json` (31.1).
- Omarchy's shipped `themes/{tokyo-night,gruvbox,everforest,rose-pine}/colors.toml`, `neovim.lua` and `vscode.json` (Omarchy 4.0.0.alpha, installed locally) were read for comparison only; Decision 2 says why their values were not used.

### Placeholder scan

No `TBD`, `TODO`, "implement later", "similar to Task N" or bare `...` standing in for content. Every new file appears in full in a `file=` block; every edit is an `edit-old`/`edit-new` pair whose `edit-old` occurs exactly once at that point. The `...` inside two "Expected" lines abbreviates a temporary path in a failure message, not content to write.

### Name and type consistency across tasks

- Suite and helpers: `tests/lib/themes.sh`, `THEMES_UNDER_TEST`, `upstream_anchors` and its `ANCHORS` terminator (Task 1) are the names Tasks 2 to 4 edit; each inserts rows directly above `ANCHORS` and `}`, so the three tasks apply in any order.
- README: the Catppuccin row text in Tasks 2 to 4's `edit-old` is byte-identical to Task 1's; each later row is inserted directly after it, which yields the `teeup theme list` order after Task 4. The README test looks for `` | `<name>` | ``, which each row starts with.
- Theme names `tokyo-night`, `gruvbox`, `everforest` are the directory names, the anchor rows' first column, the README rows' first column and the names in the commit subjects.
- Anchor rows pin `background`, `foreground`, `accent`, `bat_theme`, `emacs_theme`, `zed_theme`, `zed_extension`, `neovim_colorscheme`, `vscode_theme`, `vscode_extension` for both modes (20 rows per theme), and each value is the one in that task's palette file and README row.
- Counts: `tests/lib/themes.sh` is `Summary: 9/9 passed` after every task (8/9 at each task's red steps); the suite total rises by 1, 0, 0, 0; `tests/bootstrap.sh` gains one test in Task 1 only.

### Deferred items

Taken from the deferred lists named in the phase 4/5 brief: none. The only theme-related item, `starship.toml` reading as user-edited after a theme switch (`.superpowers/plan3/pr11-deferred.md`), is 4a's stock-checksum refresh rule; this plan's themes go through the same `theme-apply` and change nothing about it. The phase 1 and 2a reviews' deferred lists hold nothing about themes (the 2a re-review's pinned-theme question was fixed on `main`).

Left, with reasons:

- **Rosé Pine** (Decision 1): it needs `é` in its Zed and VS Code theme names, which the palette value check rejects, and plan 3a's `rosepine` plugin key cannot match `rose-pine`. Both would have to change first.
- **Catppuccin's `bat_theme`**: bat 0.26.0 added `Catppuccin Mocha` and `Catppuccin Latte`, so `themes/catppuccin/*.toml`'s "bat has no Catppuccin theme built in" comment is out of date. Switching changes an assertion in `tests/capabilities/theme.sh` and would give a machine with an older bat an unknown theme; it belongs with the next Catppuccin change, not with new themes.
- **Appearance changes re-running hooks** stays where plan 3a deferred it (phase 4's hooks work).
- **Harder and softer contrast variants** (Gruvbox hard and soft, Everforest hard and soft, Tokyo Night storm and moon) would each be a theme of their own under the one-name-two-modes model; a user theme can make one by copying a palette.

### Mechanical verification of this text

Every code block in this plan was generated from, and then checked back against, a reviewed implementation built task by task in a scratch clone of plan 3a's transcription harness (`main` with plan 3a applied one commit per task, tip `a2abae4`); plan 3b was not applied, because nothing here consumes it.

- **Transcription.** A script read this document, applied each task's `file=` blocks and `edit-old=`/`edit-new=` pairs (asserting each `edit-old` occurs exactly once) to a fresh clone of that harness, ran `./bin/teeup commands --check`, the task's own shellcheck line, `git diff --check` and `./tests/run.sh`, and committed with the task's `git add` line. The base printed `All 38 suites passed.`; after Tasks 1 to 4, `All 39 suites passed.` each time, with `lib/themes.sh` at `Summary: 9/9 passed` and `tests/bootstrap.sh` at `Summary: 25/25 passed`. `commands --check`, shellcheck and `git diff --check` were silent after every task, the working tree was clean after every commit, and each commit's tree was byte-identical to the reviewed implementation's.
- **Failing first.** The same script applied each task only up to its red steps on top of the previous task: Task 1 through Step 1 gave `8/9` with the README test failing on `catppuccin`, Step 3's broken copy gave `4/9` and left the checkout unchanged apart from the new suite, and through Step 5 gave `9/9`; Tasks 2, 3 and 4 through Step 1 gave `8/9` with the anchor test's `File not found: .../themes/<name>/dark.toml`, and through Step 4 gave `8/9` with `README.md's theme table has no row for <name>`. The wizard test's final assertion was also run naming a theme other than the last one listed, and failed.
- **Palette values.** A script parsed every `key = "#rrggbb"   # <upstream name>` line of the six palette files and compared the value with that name in the upstream file named in the task (tokyonight's generated Lua tables, gruvbox's `s:gb` dictionary, everforest's `get_palette` dictionaries): 150 values, no mismatch and no line without a name.
- **bash 3.2.0.** The final state's full suite with a bash 3.2.0 build first on `PATH`: `All 39 suites passed.` A second run also linked that bash into each test's `MOCK_BIN`, so `bin/teeup`, `bootstrap` and every capability script ran under 3.2 as on macOS: `All 39 suites passed.`
- **End to end.** The Verification section's loop, run on the final state: `teeup theme list` prints `catppuccin everforest gruvbox tokyo-night`; each new theme renders the eight files with no token left; Emacs 31.1 loads all six rendered theme names. With a done marker for `zed`, switching to `gruvbox` wrote Zed's `theme` object with no `auto_install_extensions` entry and switching to `everforest` added `{"everforest": true}`. Plan 3a's `M.plugin_for`, run under `lua`, mapped all four themes' colorschemes to their repositories.
