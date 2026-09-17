# teeup Redesign, Phase 3a: Daily Tier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the daily tier the user chose on 2026-09-13 (`emacs zed firefox-developer-edition obsidian`, installed at bootstrap) and the three editors and browsers that moved out of it (`neovim`, `vscode`, `chrome`, as `tier=lazy` capabilities), each following `teeup theme set` and `teeup install font`, plus the JSON settings helper they share and the `TEEUP_EMACS_FLAVOR` answer.

**Architecture:** Every capability follows the phase 2 contract (`capability` metadata, `install`, `configure`, optional `theme-apply`/`font-apply`, `themed/*.tpl`). Emacs runs as a login daemon from a LaunchAgent and puts one of four configurations in place (teeup's built-ins-only starter, Doom, Spacemacs, or the user's own). Neovim gets the LazyVim starter layout with teeup's Lua layer on `package.path`. Zed and VS Code keep their own `settings.json`; teeup edits only the keys it owns through `json_set_key`/`json_merge_key`, new in `lib/files.sh`. Editor theme names live in the palette next to the colours, so one theme renders a colorscheme name for every editor, and the editor hooks act only on editors teeup installed.

**Tech Stack:** bash 3.2 (macOS stock), BSD `sed`/`awk`, `jq`, Emacs Lisp (Emacs 28 or later), Lua (Neovim and LazyVim), JSON with comments (Zed, VS Code), LaunchAgent plists, Homebrew casks and formulae with MacPorts degradation, the phase 1 mock-binary test harness.

**Spec:** `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md`. This plan implements the daily half of the phase 3 row of "Migration path for the repo", the Editors, Browsers, Productivity and Essential set rows of the interview table as amended by the user on 2026-09-13, spec section 4a's `neovim` example, section 5 steps 4 and 6, and section 7's "Fonts" and "Themes" paragraphs for Neovim, Zed and VS Code. Its last task records the 2026-09-13 decision in the spec.

**Sibling plan and the seam:** plan 3b (`docs/superpowers/plans/2026-09-13-redesign-phase3b-lazy-runtime.md`) is written and executed in parallel. It owns every new `bin/teeup` verb (`lazy-run`, `launch`, `install dev-env`), the shims directory and its generation from `provides=`, `lib/lazy.sh`, `lib/mise.sh`, and the lazy capabilities `colima ai herdr tmux ollama cursor`. This plan owns the capabilities `emacs zed firefox-developer-edition obsidian` (daily) and `neovim vscode chrome` (lazy), their hooks and templates, `json_set_key`, `json_merge_key` and `json_quote`, the `TEEUP_EMACS_FLAVOR` answer, and the spec amendment. Neither plan depends on the other's tasks. The files both touch are `README.md` and `CONTRIBUTING.md`, and each only appends; the anchors below are text 3b does not change. 3b's shims for `nvim` and `code` and its `teeup launch` for `Google Chrome`, `Visual Studio Code`, `Zed`, `Obsidian`, `Emacs` and `Firefox Developer Edition` come from the metadata written here, whichever plan lands first. This plan does not touch `bin/teeup`, `lib/all.sh`, `lib/core.sh`, `lib/capability.sh` or `capabilities/core.list`.

---

## Global Constraints

- bash 3.2 compatible everywhere: no `mapfile`, `declare -A`, `${var,,}`/`${var^^}`, `readarray`, `readlink -f`; no same-line `local` back-references (`local a=1 b=$a`); `10#$n` for arithmetic on numbers that came from text. bash 3.2 mis-parses a quoted pattern containing `/` inside `${var//pat/repl}`: use `replace_literal` (`lib/files.sh`). Run `shopt -u patsub_replacement 2>/dev/null || true` before a `${var//}` replacement whose replacement text contains `&`. Nothing in this plan uses `${var//}`.
- BSD tools only: no GNU-only flags for `sed`, `grep`, `awk`, `date`, `mktemp`, `sort`, `readlink`, `stat`; no `\t` or `\n` inside a `sed` replacement; awk gets values through `ENVIRON`, never `-v`, when they may contain backslashes. The JSONC awk program in Task 1 was run under the one-true-awk that macOS ships as well as gawk.
- Capability scripts start with `#!/usr/bin/env bash`, run as `bash -eu` with `lib/all.sh` loaded and `answers_load` done, use no `local`, and call mocked commands by bare name. `set -e` fires on a failing command anywhere in a script, so a command that may fail harmlessly carries `|| warn ...` or sits in an `if`; never end a script with `[[ ]] && cmd`. Every mutation goes through `run_cmd`/`run_privileged` or a primitive with its own `DRY_RUN` guard (`write_managed_file`, `copy_config_once`, `backup_target`, `launchagent_install`, `theme_render`, and this plan's `json_set_key`/`json_merge_key`). `DRY_RUN=true` changes nothing.
- Paths: `user_config_dir` for `~/.config` wherever the tool itself honours `XDG_CONFIG_HOME` (Emacs, Doom, Neovim); `$HOME/.config/zed` for Zed, which does not on macOS; `$HOME/Library/Application Support/Code/User` for VS Code. `TEEUP_CONFIG_DIR` and `TEEUP_STATE_DIR` are honoured, and paths with spaces and metacharacters must work: Task 1 uses a settings directory named `Some App & $more`, Task 2 a state directory and a `TMPDIR` with a space, `&`, `<` and `>` plus a checkout named `José's $Café Dir`, Task 3 a `$HOME` named `Ada Lovelace & co`, Task 5 the same `José's $Café Dir` checkout, Task 6 the `Application Support` directory itself.
- Machine file precedence (answers, then `machines/<hostname>.conf`) for every consumer of an answer. The only new answer is `TEEUP_EMACS_FLAVOR`: `capabilities/emacs/configure` reads it after `answers_load`, and the wizard does not ask it when `machine_get TEEUP_EMACS_FLAVOR` finds a pin. Both are tested.
- `capability` metadata contract: `summary group tier requires provides packages casks apps interactive`. `provides` never names a command macOS ships. A daily capability must be in `daily.list` or `teeup commands --check` fails, so each task appends its own names to `capabilities/daily.list` in the same commit; `neovim`, `vscode` and `chrome` are `tier=lazy` and in no list. `apps` holds one application name each (3b reads the field as `;`-separated).
- Themed template basenames share one namespace per mode (`cap_check` rejects a duplicate): this plan adds `emacs.el.tpl`, `zed.json.tpl`, `neovim.lua.tpl` and `vscode.json.tpl`, none of which exist today. `theme_set` fails the whole switch when a rendered file keeps a `{{ key }}` token and `theme_palette_load` rejects any value outside `^[#A-Za-z0-9][A-Za-z0-9 ._()+-]*$`, so every palette key a template uses is added to both `themes/catppuccin/*.toml` files in the same task, and every value is a plain name.
- Tests: `tests/helper.sh` (temp `HOME`, `MOCK_BIN` first on the narrowed `PATH` `$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin`, `mock_command`, `mock_command_script`, `mock_macos_base`, `TEEUP_TEST_MISSING`, `TEEUP_PKG_PREFIX`, `TEEUP_APPS_DIR`). The narrowed `PATH` hides Homebrew but not `/usr/bin`: a Linux developer machine may have `emacs`, `emacsclient` and `nvim` there, and a running editor's socket in `XDG_RUNTIME_DIR`. Host tools a test needs (`jq`, `lua`, `luac`, `emacs`, `python3`) are resolved before `setup_test_env`; host editors are mocked or hidden with `TEEUP_TEST_MISSING`, and `XDG_RUNTIME_DIR` and `TMPDIR` point into the test home before any hook looks for sockets. CI runs `macos-14`, `macos-15-intel` and `ubuntu-latest`; a test that passes on only one of them, or only on a developer's machine, is a defect.
- Every task ends with `./tests/run.sh` green, `./bin/teeup commands --check` silent with exit 0, `shellcheck --severity=warning` clean on every new or edited script and test, `git diff --check` clean, and **one** commit with a plain imperative subject and no trailer of any kind (no `Co-Authored-By`, no `Claude-Session`, no "Generated with").
- Suite counts: `tests/run.sh` ends with `All N suites passed.` Never hard-code N. Each task states "the suite count printed before this task, plus K", so the plan stays right whether 3a or 3b lands first. Per-suite counts (`Summary: x/y passed`) are exact, because every suite named here is created or extended only by this plan.
- Nothing in this phase has run on a real Mac. Each task carries a **Real-Mac risk** note naming what only hardware proves.
- Verify, do not guess: every cask, formula, port, settings key, file location, CLI flag and install command below was checked against upstream on 2026-09-13; the sources are listed in the Self-review. A name that does not appear there is not to be introduced during execution without the same check.
- Plain prose in every comment, log line and doc: none of "No X, no Y" chains, "That's the whole ...", "Don't X it. Y it.", "Sit with that", "You already know", "is the entire", "The punchline", "Worth naming", "X is real, and ...".

---

## Contracts this plan publishes

1. **JSON settings edits** (`lib/files.sh`). `json_set_key <file> <key> <json-value>` sets one literal top-level key (dots are part of the key: VS Code's `workbench.colorTheme` is one key) to a JSON literal; `json_merge_key <file> <key> <json-object>` merges an object into the object already at `<key>`, keeping members it does not name; `json_quote <text>` prints `<text>` as a JSON string literal. A missing or empty file starts as `{}`. Comments (`//`, `/* */`) and trailing commas are read. The comment lines above the opening brace are kept; a file with a comment inside the object is copied to `<file>.teeup_backup_<timestamp>` before the first write, because jq's rewrite cannot keep it. The write goes through `write_managed_file`, so `DRY_RUN` prints `Would write <file> (<key>)` and an unchanged file logs `Already current`. Both return 1 with the file untouched when jq is missing, the file is a symlink, the value is not JSON, or the file is not a JSON object. Plan 3b defines no JSON helper of its own.
2. **`TEEUP_EMACS_FLAVOR`** is `starter` (default), `doom`, `spacemacs` or `none`. The wizard asks it right after a yes to the daily set, offering the current answer first, and skips it when the machine file pins it; any other value warns and means `starter`. `starter` owns `$(user_config_dir)/emacs/{init.el,local.el}` (copied once); `doom` clones Doom into `$(user_config_dir)/emacs` and runs `bin/doom install --no-env` until `${DOOMDIR:-$(user_config_dir)/doom}/init.el` exists; `spacemacs` clones into `~/.emacs.d`; `none` writes no configuration. A directory that is not the chosen flavor's checkout is moved aside with `backup_target`, never deleted.
3. **The Emacs daemon.** LaunchAgent label `sh.teeup.emacs`, plist `~/Library/LaunchAgents/sh.teeup.emacs.plist`, running `<command -v emacs> --fg-daemon` with `PATH`, `XDG_CONFIG_HOME`, `TEEUP_PATH`, `TEEUP_CONFIG_DIR`, `TEEUP_STATE_DIR` and (when set) `TMPDIR` in its environment, `RunAtLoad` true and `KeepAlive` `{SuccessfulExit: false}`. `configure` reinstalls it only when the plist changed or `launchctl print gui/<uid>/sh.teeup.emacs` fails, so a configure never kills a running daemon for nothing. `remove` calls `launchagent_remove sh.teeup.emacs`.
4. **The editor hook gate.** A `theme-apply` or `font-apply` in this plan does nothing unless `state_done check "cap-$TEEUP_CAP"` succeeds (the capability was installed through teeup) or `TEEUP_CONFIGURING` equals `$TEEUP_CAP` (its own `configure` is running it, before the done marker exists). `zed/configure` and `vscode/configure` export `TEEUP_CONFIGURING="$TEEUP_CAP"` and run both hooks through `cap_run_optional`.
5. **Palette name keys.** Both modes of every theme define `emacs_theme` (an Emacs theme symbol), `zed_theme` and `zed_extension` (a Zed theme name and the extension id that provides it), `neovim_colorscheme`, `vscode_theme` and `vscode_extension`. An extension of `none` installs nothing. Catppuccin ships `modus-vivendi`/`modus-operandi`, `Catppuccin Mocha`/`Catppuccin Latte` with `catppuccin`, `catppuccin-mocha`/`catppuccin-latte`, and `Catppuccin Mocha`/`Catppuccin Latte` with `Catppuccin.catppuccin-vsc`. `theme_set` renders them into `current/theme/<mode>/{emacs.el,zed.json,neovim.lua,vscode.json}`.
6. **Metadata 3b consumes.** `neovim`: `tier=lazy`, `provides="nvim"`, `apps=""`. `vscode`: `tier=lazy`, `provides="code"`, `apps="Visual Studio Code"`. `chrome`: `tier=lazy`, `provides=""`, `apps="Google Chrome"`. Daily: `emacs` (`apps="Emacs"`), `zed` (`apps="Zed"`), `firefox-developer-edition` (`apps="Firefox Developer Edition"`), `obsidian` (`apps="Obsidian"`), in that order in `capabilities/daily.list`. Every `apps` value is the cask's `app` artifact name without `.app`.

---

## Decisions made here

1. **The JSON helpers live in `lib/files.sh`, not a new `lib/json.sh`.** A new library would add a word to `lib/all.sh`'s source loop, the same line plan 3b edits to add `lazy` and `mise`; two plans rewriting one line conflict whichever lands second. The functions are file primitives next to `write_managed_file`, which they call. Their suite is `tests/lib/json.sh`, named for what it tests.
2. **Keys are literal, never dotted paths.** VS Code's settings file is flat (`"workbench.colorTheme"` is one key; a nested `{"workbench": {...}}` object is not a setting VS Code reads), and Zed needs only top-level keys (`theme`, `buffer_font_family`, `auto_install_extensions`). A path syntax would be wrong for one editor and unused by the other.
3. **JSONC is read, not rejected.** Zed's own first `settings.json` has a comment header and trailing commas, and both editors accept comments anywhere, so a helper that refused them would refuse the most common real file. The comment header survives; comments inside the object cannot survive a jq rewrite, so that file is backed up once before the write and the warning names the backup.
4. **A symlinked settings file is left alone.** `write_managed_file` renames a temporary file onto the path, which would replace a dotfile manager's link with an untracked copy.
5. **Editor hooks act only on editors teeup installed** (contract 4). `teeup theme set` runs every capability's hooks: without the gate, a core-only Mac would grow a `~/.config/zed/settings.json`, a `code --list-extensions` call and an `emacsclient` probe, and a developer running the suite on Linux would have `nvim --remote-send` delivered to the Neovim they are typing in.
6. **Zed's settings path is `$HOME/.config/zed/settings.json` whatever `XDG_CONFIG_HOME` says.** Zed's `paths::config_dir()` reads `XDG_CONFIG_HOME` only on Linux and FreeBSD; on macOS it is `home_dir().join(".config").join("zed")`. Writing to `$(user_config_dir)/zed` would write a file Zed never reads on a machine with a custom `XDG_CONFIG_HOME`.
7. **Zed and VS Code follow the system appearance themselves.** Zed's `theme` becomes `{"mode": "system", "light": ..., "dark": ...}`; VS Code gets `window.autoDetectColorScheme: true` with `workbench.preferredDarkColorTheme` and `workbench.preferredLightColorTheme`. Light/dark switches need no teeup run, and `workbench.colorTheme` stays the user's.
8. **MacPorts never installs `zed`.** The MacPorts port named `zed` is Brim's "Tooling for super-structured data", not the editor; `zed/install` warns with the download URL instead of calling `pkg_install`. Firefox Developer Edition, Obsidian, VS Code and Chrome have no ports either.
9. **Emacs comes from the `emacs-app` cask on Homebrew, the `emacs` port on MacPorts.** Homebrew's `emacs` formula is built `--without-ns` (terminal only); the `emacs-app` cask (formerly `emacs`) installs `Emacs.app` and links `emacs` and `emacsclient` into the Homebrew prefix, so one install serves the daemon, GUI frames and `emacsclient -t`. MacPorts' `emacs-app` port puts only `Emacs.app` under `/Applications/MacPorts`, with nothing on `PATH` for the LaunchAgent, so the terminal `emacs` port (which installs `emacsclient`) is the one the daemon can run.
10. **The starter is built-ins only, themed with Modus.** A fresh Mac gets a working Emacs before any package download: `fido-vertical-mode`, `savehist`, `recentf`, line numbers in `prog-mode`, MELPA configured but nothing fetched. Catppuccin for Emacs is a MELPA package, so the palette names the built-in `modus-vivendi`/`modus-operandi`; `teeup-apply-theme` catches a missing theme and keeps the current one, because a failing init in a daemon leaves nothing to connect to.
11. **The daemon restarts after a crash only.** `KeepAlive {SuccessfulExit: false}`: `kill-emacs` exits 0, so a daemon stopped on purpose stays down until the next login, `launchctl kickstart`, or an `emacsclient` from zsh (whose empty `ALTERNATE_EDITOR` starts one).
12. **The daemon gets the shell's `TMPDIR`.** Without `XDG_RUNTIME_DIR` (unset on macOS), Emacs puts its server socket in `$TMPDIR/emacs<uid>`, falling back to `/tmp` (`server-socket-dir` in Emacs 31.1's `server.el`), and `emacsclient` looks under its own `TMPDIR`. Writing the configuring shell's value into the plist makes the two agree by construction rather than by whatever environment launchd hands the agent.
13. **The Emacs hooks probe with `emacsclient -a false`.** The zsh layer exports `ALTERNATE_EDITOR=""`, which makes a bare `emacsclient -e t` start a daemon instead of answering whether one runs; `-a` on the command line takes precedence over the variable.
14. **`emacs configure` re-runs `git configure` once `emacsclient` exists.** `git` is core and runs before any daily capability, so on a first bootstrap it finds no `emacsclient` and writes `editor = vim`. The same re-run pattern `ssh/configure` uses fixes that in the same bootstrap; it is skipped when git is in `TEEUP_SKIP`, was never configured, or already says `emacsclient`.
15. **Doom is `doomemacs/core`, installed with `--no-env`.** `github.com/doomemacs/doomemacs` redirects to `github.com/doomemacs/core`, whose README clones that URL into `~/.config/emacs`. `bin/doom-install` declares `--env` after `&flags`, which `doom-cli.el` turns into an accepted `--no-env`; without it the install asks "Generate an envvar file?", a question nobody can answer with stdin on `/dev/null`.
16. **Neovim ships the LazyVim starter file by file.** `init.lua` keeps the starter's `require("config.lazy")` and adds the lines that find the checkout (environment, then `~/.config/teeup/env` decoded from bash's `%q`, then `~/.local/share/teeup`); `lua/config/lazy.lua` is the starter's bootstrap with teeup's specs inserted between LazyVim and `{ import = "plugins" }`. Every file is copied once and is the user's. The starter's `lua/plugins/example.lua` becomes an empty `lua/plugins/local.lua` with the examples as comments.
17. **Running Neovims are told over RPC.** Neovim 0.12 creates its socket as `nvim.<pid>.0` directly in `XDG_RUNTIME_DIR` when that is set, otherwise under `$TMPDIR/nvim.<user>/<random>/`; the hooks send `<Cmd>lua require("teeup.neovim").apply()<CR>` to each, which works in every mode. Both locations and the key string were run against a real Neovim 0.12.5.
18. **An old Neovim is reported.** `pkg_install neovim nvim` keeps whatever `nvim` is already on `PATH`, and LazyVim stops on anything older than 0.11.2, so `neovim/configure` warns with the version it found.
19. **Firefox Developer Edition, Obsidian and Chrome are one task.** All three are a cask with nothing to configure, the same three scripts and the same six tests; a reviewer approves or rejects the pattern once. Their `configure` records that decision and reports whether the app is in place.
20. **CONTRIBUTING items are appended, never numbered against a fixed baseline.** On `main` the list ends at item 13; Task 7 appends two items after whatever the last numbered item is when it runs.

---

## File structure

| Path | Responsibility |
|---|---|
| `lib/files.sh` | gains `json_quote`, `json_set_key`, `json_merge_key` and the JSONC reader they share. |
| `capabilities/emacs/` | `emacs-app` cask or `emacs` port; flavor-dependent configuration; the `sh.teeup.emacs` LaunchAgent; the git editor re-run; `remove`; `theme-apply`/`font-apply` through `emacsclient`; `themed/emacs.el.tpl`; the thin `config/emacs/{init.el,local.el}` and the thick `default/teeup/init.el`. |
| `capabilities/zed/` | `zed` cask; `theme-apply` writes `theme` and `auto_install_extensions`, `font-apply` writes `buffer_font_family`; `themed/zed.json.tpl`. |
| `capabilities/firefox-developer-edition/`, `capabilities/obsidian/`, `capabilities/chrome/` | one cask each, nothing to configure. |
| `capabilities/neovim/` | `neovim` formula or port; the LazyVim starter layout under `config/nvim/`; the `teeup.neovim` Lua layer under `default/teeup/`; RPC reload hooks; `themed/neovim.lua.tpl`. |
| `capabilities/vscode/` | `visual-studio-code` cask; `theme-apply` writes the preferred themes and installs the extension with `code`; `font-apply` writes `editor.fontFamily`; `themed/vscode.json.tpl`. |
| `capabilities/daily.list` | `emacs zed firefox-developer-edition obsidian`. |
| `themes/catppuccin/{dark,light}.toml` | the six editor name keys. |
| `bootstrap` | the wizard's daily-set prompt names the new set and asks the Emacs flavor. |
| `.github/workflows/ci.yml` | installs `emacs-nox` on the Linux runner for the Elisp checks. |
| `tests/lib/json.sh`, `tests/capabilities/{emacs,zed,firefox-developer-edition,obsidian,chrome,neovim,vscode}.sh` | one new suite per library change and capability. |
| `tests/bootstrap.sh` | the wizard's flavor question and the daily tier walk. |
| `README.md`, `CONTRIBUTING.md` | the daily tier, the Editors section, two contributor items. |
| `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md` | the 2026-09-13 amendment. |

**Reading this plan mechanically.** Every fenced block whose info string carries `file=<path>` is the complete content of that file after the step. Every edit to an existing file is a pair of blocks, `edit-old=<path>` (text that exists on `main` or was produced by an earlier step of this plan, quoted exactly and occurring exactly once in the file) followed by `edit-new=<path>` (what replaces it). Blocks without either marker are commands or illustrations and change nothing. Blocks that contain triple backticks are fenced with four.

---

### Task 1: `json_set_key`, `json_merge_key` and `json_quote` in `lib/files.sh`

**Files:**
- Modify: `lib/files.sh` (append after `replace_literal`, the last function)
- Test: `tests/lib/json.sh` (new suite)

**Interfaces:**
- Consumes: `have`, `warn` (`lib/core.sh`); `write_managed_file` (`lib/files.sh`); `DRY_RUN`; `jq` on `PATH` at call time (`cli-tools` and `teeup-runtime` install it).
- Produces (contract 1): `json_quote <text>` prints one JSON string literal; `json_set_key <file> <key> <json-value>` and `json_merge_key <file> <key> <json-object>` return 0 after writing (or finding the file already current) and 1 with the file untouched when jq is missing, `<file>` is a symlink, the value is not JSON, or the file is not a JSON object. Tasks 3 and 6 call all three.

**External facts (verified 2026-09-13):** Zed's `assets/settings/initial_user_settings.json` starts with `// Zed settings` comment lines and ends its `theme` object with `"dark": "One Dark",` followed by `},` and `}`; Zed parses user settings with `serde_json_lenient`, so comments and trailing commas are valid there. A hand-edited VS Code `settings.json` may carry comments and trailing commas too, which Task 6's test covers. The `jq` used locally is 1.8.2 (`--arg`, `--argjson`, `-n`, `-c`, `-r`, `error()`).

**Real-Mac risk:** low. The awk program was run under the one-true-awk macOS ships (built from source) as well as gawk; mawk on the Ubuntu runner is exercised by CI. Only a real Zed proves that a file rewritten by jq (2-space indentation, header comments kept, inner comments gone) reloads without a settings error.

- [ ] **Step 1: Write the failing test `tests/lib/json.sh`**

```bash file=tests/lib/json.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# jq is resolved before setup_test_env narrows PATH (Homebrew's copy is
# hidden from the macOS runners there) and linked into the mock bin, so the
# library finds it by name. Every CI runner image ships jq; a machine without
# it fails this suite rather than skipping it.
JQ_BIN="$(command -v jq || true)"

setup() {
  setup_test_env
  if [[ -z "$JQ_BIN" ]]; then
    echo "jq is not installed: this suite needs it"
    return 1
  fi
  ln -s "$JQ_BIN" "$MOCK_BIN/jq"
  source "$TEEUP_PATH/lib/all.sh"
  export DRY_RUN=false
  # A directory with a space and shell metacharacters on purpose.
  FILE="$TEST_HOME/Some App & \$more/settings.json"
}

# body_of <file>: the file without its comment header, for jq.
body_of() { sed '/^[[:space:]]*\/\//d' "$1"; }

test_set_key_creates_the_file() {
  setup || return 1
  json_set_key "$FILE" theme '"One Dark"' >/dev/null
  assert_file_exists "$FILE" || return 1
  assert_equals "One Dark" "$(jq -r .theme "$FILE")" || return 1
  cleanup_test_env
}

test_a_dotted_key_is_one_flat_key() {
  setup || return 1
  mkdir -p "$(dirname "$FILE")"
  printf '{"editor.fontSize": 14, "workbench.colorTheme": "Abyss"}\n' > "$FILE"
  json_set_key "$FILE" workbench.colorTheme '"Catppuccin Mocha"' >/dev/null
  assert_equals "14" "$(jq -r '.["editor.fontSize"]' "$FILE")" || return 1
  assert_equals "Catppuccin Mocha" "$(jq -r '.["workbench.colorTheme"]' "$FILE")" || return 1
  assert_equals "null" "$(jq -r '.workbench' "$FILE")" "no nested object was created" || return 1
  cleanup_test_env
}

test_set_key_accepts_objects_and_booleans() {
  setup || return 1
  json_set_key "$FILE" theme '{"mode":"system","light":"One Light","dark":"One Dark"}' >/dev/null
  json_set_key "$FILE" window.autoDetectColorScheme true >/dev/null
  json_set_key "$FILE" telemetry false >/dev/null
  assert_equals "system" "$(jq -r .theme.mode "$FILE")" || return 1
  assert_equals "true" "$(jq -r '.["window.autoDetectColorScheme"]' "$FILE")" || return 1
  assert_equals "false" "$(jq -r .telemetry "$FILE")" || return 1
  cleanup_test_env
}

# Zed's own first settings.json, verbatim from assets/settings/initial_user_settings.json:
# a comment header and trailing commas.
test_zeds_initial_file_is_edited_and_keeps_its_header() {
  setup || return 1
  mkdir -p "$(dirname "$FILE")"
  cat > "$FILE" <<'EOF2'
// Zed settings
//
// For information on how to configure Zed, see the Zed
// documentation: https://zed.dev/docs/configuring-zed
//
// To see all of Zed's default settings without changing your
// custom settings, run `zed: open default settings` from the
// command palette (cmd-shift-p / ctrl-shift-p)
{
  "ui_font_size": 16,
  "buffer_font_size": 15,
  "theme": {
    "mode": "system",
    "light": "One Light",
    "dark": "One Dark",
  },
}
EOF2
  local out
  out="$(json_set_key "$FILE" buffer_font_family '"Hack Nerd Font"' 2>&1)"
  assert_equals "// Zed settings" "$(head -1 "$FILE")" || return 1
  assert_contains "$(cat "$FILE")" "https://zed.dev/docs/configuring-zed" || return 1
  assert_equals "15" "$(body_of "$FILE" | jq -r .buffer_font_size)" || return 1
  assert_equals "One Dark" "$(body_of "$FILE" | jq -r .theme.dark)" || return 1
  assert_equals "Hack Nerd Font" "$(body_of "$FILE" | jq -r .buffer_font_family)" || return 1
  assert_not_contains "$out" "do not survive" "a header-only comment needs no backup" || return 1
  cleanup_test_env
}

test_comments_inside_the_object_are_backed_up() {
  setup || return 1
  mkdir -p "$(dirname "$FILE")"
  cat > "$FILE" <<'EOF2'
{
  // the size I like
  "editor.fontSize": 13, /* inline */
  "url": "https://example.com/a//b",
  "quote": "say \"hi\" // not a comment",
}
EOF2
  local out
  out="$(json_set_key "$FILE" editor.fontFamily '"Hack Nerd Font"' 2>&1)"
  assert_equals "13" "$(jq -r '.["editor.fontSize"]' "$FILE")" || return 1
  assert_equals "https://example.com/a//b" "$(jq -r .url "$FILE")" "// inside a string is kept" || return 1
  assert_equals 'say "hi" // not a comment' "$(jq -r .quote "$FILE")" || return 1
  assert_contains "$out" "Comments inside $FILE do not survive the edit" || return 1
  ls "$FILE".teeup_backup_* >/dev/null 2>&1 || { echo "no backup was made"; return 1; }
  assert_contains "$(cat "$FILE".teeup_backup_*)" "// the size I like" || return 1
  cleanup_test_env
}

test_set_key_is_idempotent() {
  setup || return 1
  json_set_key "$FILE" theme '"One Dark"' >/dev/null
  local out
  out="$(json_set_key "$FILE" theme '"One Dark"')"
  assert_contains "$out" "Already current: $FILE" || return 1
  cleanup_test_env
}

test_set_key_dry_run_writes_nothing() {
  setup || return 1
  local out
  out="$(DRY_RUN=true json_set_key "$FILE" theme '"One Dark"')"
  assert_contains "$out" "[DRY-RUN] Would write $FILE (theme)" || return 1
  [[ ! -e "$FILE" ]] || { echo "file written in dry run"; return 1; }
  cleanup_test_env
}

test_a_file_that_is_not_an_object_is_left_alone() {
  setup || return 1
  mkdir -p "$(dirname "$FILE")"
  printf '["a", "b"]\n' > "$FILE"
  local rc=0 out
  out="$(json_set_key "$FILE" theme '"One Dark"' 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" 'is not a JSON object jq can edit; set it by hand: "theme": "One Dark"' || return 1
  assert_equals '["a", "b"]' "$(cat "$FILE")" "the file is untouched" || return 1
  printf '{ "a": \n' > "$FILE"
  rc=0
  json_set_key "$FILE" theme '"One Dark"' >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "a truncated file is refused" || return 1
  assert_equals '{ "a": ' "$(cat "$FILE")" || return 1
  cleanup_test_env
}

test_a_symlinked_file_is_left_alone() {
  setup || return 1
  mkdir -p "$(dirname "$FILE")" "$TEST_HOME/dotfiles"
  printf '{"theme": "Mine"}\n' > "$TEST_HOME/dotfiles/settings.json"
  ln -s "$TEST_HOME/dotfiles/settings.json" "$FILE"
  local rc=0 out
  out="$(json_set_key "$FILE" theme '"One Dark"' 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$FILE is a symlink; teeup does not write through it" || return 1
  [[ -L "$FILE" ]] || { echo "the link was replaced"; return 1; }
  assert_equals "Mine" "$(jq -r .theme "$TEST_HOME/dotfiles/settings.json")" || return 1
  cleanup_test_env
}

test_set_key_rejects_a_non_json_value() {
  setup || return 1
  local rc=0 out
  out="$(json_set_key "$FILE" theme 'One Dark' 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "not a JSON value: 'One Dark'" || return 1
  [[ ! -e "$FILE" ]] || { echo "file written for a bad value"; return 1; }
  cleanup_test_env
}

test_set_key_without_jq_warns() {
  setup || return 1
  export TEEUP_TEST_MISSING="jq"
  local rc=0 out
  out="$(json_set_key "$FILE" theme '"One Dark"' 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "jq is not installed" || return 1
  unset TEEUP_TEST_MISSING
  cleanup_test_env
}

test_merge_key_keeps_the_users_entries() {
  setup || return 1
  mkdir -p "$(dirname "$FILE")"
  printf '{"auto_install_extensions": {"html": true, "toml": false}}\n' > "$FILE"
  json_merge_key "$FILE" auto_install_extensions '{"catppuccin": true}' >/dev/null
  assert_equals "true" "$(jq -r .auto_install_extensions.html "$FILE")" || return 1
  assert_equals "false" "$(jq -r .auto_install_extensions.toml "$FILE")" || return 1
  assert_equals "true" "$(jq -r .auto_install_extensions.catppuccin "$FILE")" || return 1
  json_merge_key "$TEST_HOME/new.json" auto_install_extensions '{"catppuccin": true}' >/dev/null
  assert_equals "true" "$(jq -r .auto_install_extensions.catppuccin "$TEST_HOME/new.json")" "a missing object is created" || return 1
  cleanup_test_env
}

test_json_quote_escapes() {
  setup || return 1
  assert_equals '"Ada \"Countess\" \\ Lovelace"' "$(json_quote 'Ada "Countess" \ Lovelace')" || return 1
  cleanup_test_env
}

echo "lib/json"
run_test "set_key creates the file" test_set_key_creates_the_file
run_test "a dotted key is one flat key" test_a_dotted_key_is_one_flat_key
run_test "set_key accepts objects and booleans" test_set_key_accepts_objects_and_booleans
run_test "Zed's initial file is edited and keeps its header" test_zeds_initial_file_is_edited_and_keeps_its_header
run_test "comments inside the object are backed up" test_comments_inside_the_object_are_backed_up
run_test "set_key is idempotent" test_set_key_is_idempotent
run_test "set_key dry run writes nothing" test_set_key_dry_run_writes_nothing
run_test "a file that is not an object is left alone" test_a_file_that_is_not_an_object_is_left_alone
run_test "a symlinked file is left alone" test_a_symlinked_file_is_left_alone
run_test "set_key rejects a non-JSON value" test_set_key_rejects_a_non_json_value
run_test "set_key without jq warns" test_set_key_without_jq_warns
run_test "merge_key keeps the user's entries" test_merge_key_keeps_the_users_entries
run_test "json_quote escapes" test_json_quote_escapes
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/lib/json.sh`
Expected: every test fails with `json_set_key: command not found` (or `json_merge_key`, `json_quote`); `Summary: 0/13 passed`.

- [ ] **Step 3: Append the helpers to `lib/files.sh`**

The block goes after the closing brace of `replace_literal`, the last function in the file.

```bash edit-old=lib/files.sh
  done
  printf '%s\n' "$out$rest"
}
```

```bash edit-new=lib/files.sh
  done
  printf '%s\n' "$out$rest"
}

# --- JSON settings files ------------------------------------------------------
# Zed and VS Code keep their settings in a JSON file the user also edits, so
# teeup never ships one: it sets the few keys the theme and the font need and
# leaves the rest alone. jq does the edit (cli-tools and teeup-runtime install
# it); write_managed_file does the write, so DRY_RUN previews it and an
# unchanged file is left alone.
#
# Both editors read JSON with comments and trailing commas ("JSONC"), and
# Zed's own first settings file has both. jq reads neither, so the file is
# converted first by the awk program below, which walks it character by
# character outside strings: `//` and `/* */` comments are dropped and a comma
# followed only by whitespace or comments before `}` or `]` is dropped. The
# comment lines above the opening brace (Zed's header) are put back on the way
# out; a comment inside the object cannot survive jq's rewrite, so a file that
# has one is copied to <file>.teeup_backup_<timestamp> before the first write.
#
# The program runs per line with its state carried across lines, so it never
# indexes into one long string. With ENVIRON["JSONC_DETECT"] set it prints
# nothing and exits 0 when the input holds a comment, 1 when it holds none.
_JSONC_AWK='
function out(s) { if (!detect) printf "%s", s }
BEGIN { detect = (ENVIRON["JSONC_DETECT"] != ""); found = 0 }
{
  line = $0 "\n"
  n = length(line)
  for (i = 1; i <= n; i++) {
    c = substr(line, i, 1)
    if (lc) { if (c == "\n") { lc = 0; if (pc) pw = pw c; else out(c) } ; continue }
    if (bc) { if (c == "*" && substr(line, i + 1, 1) == "/") { bc = 0; i++ } ; continue }
    if (ins) {
      out(c)
      if (esc) esc = 0
      else if (c == "\\") esc = 1
      else if (c == "\"") ins = 0
      continue
    }
    if (c == "/" && substr(line, i + 1, 1) == "/") { lc = 1; found = 1; i++; continue }
    if (c == "/" && substr(line, i + 1, 1) == "*") { bc = 1; found = 1; i++; continue }
    if (c == " " || c == "\t" || c == "\r" || c == "\n") { if (pc) pw = pw c; else out(c); continue }
    if (pc) { if (c != "}" && c != "]") out(","); out(pw); pc = 0; pw = "" }
    if (c == ",") { pc = 1; continue }
    if (c == "\"") ins = 1
    out(c)
  }
}
END {
  if (pc) { out(","); out(pw) }
  if (detect) exit(found ? 0 : 1)
}
'

# json_quote <text> -> <text> as one JSON string literal, escaped by jq.
json_quote() { jq -n --arg v "$1" '$v'; }

# _json_edit <set|merge> <file> <key> <json-value>
_json_edit() {
  local op="$1" file="$2" key="$3" value="$4" header="" body="" stripped result filter backup
  if ! have jq; then
    warn "jq is not installed; cannot set $key in $file. Run: teeup install cli-tools"
    return 1
  fi
  # A settings file that is a symlink belongs to a dotfile manager, and the
  # write below (a rename onto the path) would replace the link with a copy
  # the manager no longer tracks.
  if [[ -L "$file" ]]; then
    warn "$file is a symlink; teeup does not write through it. Set it by hand: \"$key\": $value"
    return 1
  fi
  if ! jq -n --argjson v "$value" 'true' >/dev/null 2>&1; then
    warn "json_${op}_key: not a JSON value: '$value' (a string needs its quotes: '\"text\"')"
    return 1
  fi
  if [[ -f "$file" ]]; then
    # The header is every blank or `//` line before the first other line.
    header="$(awk '!body && /^[[:space:]]*(\/\/.*)?$/ { print; next } { body = 1 }' "$file")"
    body="$(awk '!body && /^[[:space:]]*(\/\/.*)?$/ { next } { body = 1; print }' "$file")"
  fi
  stripped="$(printf '%s\n' "$body" | awk "$_JSONC_AWK")"
  case "$stripped" in
    *[![:space:]]*) ;;
    *) stripped="{}" ;;
  esac
  case "$op" in
    set) filter='if type == "object" then .[$k] = $v else error("not an object") end' ;;
    merge) filter='if type == "object" and ((.[$k] // {}) | type) == "object" then .[$k] = ((.[$k] // {}) + $v) else error("not an object") end' ;;
  esac
  if ! result="$(printf '%s\n' "$stripped" | jq --arg k "$key" --argjson v "$value" "$filter" 2>/dev/null)" || [[ -z "$result" ]]; then
    warn "$file is not a JSON object jq can edit; set it by hand: \"$key\": $value"
    return 1
  fi
  if [[ "$DRY_RUN" != "true" ]] && printf '%s\n' "$body" | JSONC_DETECT=1 awk "$_JSONC_AWK"; then
    backup="${file}.teeup_backup_$(date +%Y%m%d%H%M%S)"
    cp "$file" "$backup"
    warn "Comments inside $file do not survive the edit; your previous file is at $backup"
  fi
  {
    if [[ -n "$header" ]]; then printf '%s\n' "$header"; fi
    printf '%s\n' "$result"
  } | write_managed_file "$file" "$key"
}

# json_set_key <file> <dotted.key> <json-value>
# Sets <dotted.key> in the JSON object in <file> to <json-value>, a JSON
# literal ('"Catppuccin Mocha"', 'true', '{"mode":"system"}'; json_quote makes
# one from text). The key is one literal top-level key, dots included: VS
# Code's "workbench.colorTheme" is a single key, and a nested
# {"workbench": {...}} object is not a setting VS Code reads. A missing or
# empty file starts as {}. Returns 1, the file untouched, when jq is missing,
# the file is a symlink, the value is not JSON, or the file is not a JSON
# object.
json_set_key() { _json_edit set "$1" "$2" "$3"; }

# json_merge_key <file> <key> <json-object>
# Like json_set_key, but the object already at <key> keeps the members
# <json-object> does not name (Zed's auto_install_extensions gains one entry
# and keeps the user's).
json_merge_key() { _json_edit merge "$1" "$2" "$3"; }
```

- [ ] **Step 4: Run the new suite and the existing files suite**

Run: `bash tests/lib/json.sh && bash tests/lib/files.sh`
Expected: `Summary: 13/13 passed`, then `Summary: 12/12 passed`.

- [ ] **Step 5: Full checks and commit**

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning lib/files.sh tests/lib/json.sh
git diff --check
git add lib/files.sh tests/lib/json.sh
git commit -m "Add json_set_key and json_merge_key for editor settings files"
```

Expected: `commands --check`, shellcheck and `git diff --check` print nothing; `./tests/run.sh` ends with `All N suites passed.` where N is the suite count printed before this task, plus 1.

---

### Task 2: `emacs` capability and the `TEEUP_EMACS_FLAVOR` answer

**Files:**
- Create: `capabilities/emacs/{capability,install,configure,remove,theme-apply,font-apply}`, `capabilities/emacs/config/emacs/{init.el,local.el}`, `capabilities/emacs/default/teeup/init.el`, `capabilities/emacs/themed/emacs.el.tpl`
- Modify: `capabilities/daily.list`, `themes/catppuccin/dark.toml`, `themes/catppuccin/light.toml`, `bootstrap` (the wizard), `.github/workflows/ci.yml`
- Test: `tests/capabilities/emacs.sh` (new suite), `tests/bootstrap.sh` (four new tests, one `setup()` comment)

**Interfaces:**
- Consumes: `answers_get`, `machine_get`, `machine_file`, `answers_set` (`lib/answers.sh`); `cask_install`, `casks_supported`, `pkg_install`, `pkg_installed`, `pkg_prefix` (`lib/pkg.sh`); `copy_config_once`, `backup_target`, `replace_literal` (`lib/files.sh`); `launchagent_install`, `launchagent_remove` (`lib/macos.sh`); `state_done` (`lib/state.sh`); `cap_run`, `cap_skipped` (`lib/capability.sh`); `ui_choose` (`lib/ui.sh`); `user_config_dir`, `run_cmd`, `have`, `log`, `ok`, `warn` (`lib/core.sh`); `TEEUP_CAP`, `TEEUP_CAP_DIR`, `TEEUP_APPS_DIR` (the test hook aerospace already uses for `/Applications`); the theme contract (`TEEUP_STATE_DIR/current/theme/<mode>/`) and the font file (`TEEUP_STATE_DIR/current/font`); `capabilities/git/configure`'s `editor = emacsclient -t` line in `$(user_config_dir)/git/teeup-generated`.
- Produces: contracts 2, 3 and 5 (`emacs_theme`); the Emacs Lisp function `teeup-apply` (re-reads theme and font; bound to `C-c t`), called by the hooks; `emacs` as the first line of `daily.list`; `install`'s warning (I2) when Homebrew's `emacs` formula is already installed, since the `emacs-app` cask then does not link `emacs`/`emacsclient` over it; `configure`'s LaunchAgent program path, which prefers `Emacs.app/Contents/MacOS/Emacs` under `TEEUP_APPS_DIR` or `~/Applications` over a PATH `emacs` for the same reason.

**External facts (verified 2026-09-13):**
- Homebrew cask `emacs-app` 31.1: `app "Emacs.app"`, binaries `Emacs.app/Contents/MacOS/Emacs` as `emacs` and `Emacs.app/Contents/MacOS/bin-<arch>/emacsclient` (also `ebrowse`, `etags`), `old_tokens: ["emacs"]` (the cask `emacs` now 404s). Homebrew formula `emacs` 31.1 configures `--without-x --without-ns` (terminal only).
- MacPorts port `emacs` 31.1 is `--without-ns --without-x` and installs `bin/emacsclient` with the rest of `INSTALLABLES`; port `emacs-app` 31.1 copies only `Emacs.app` into `/Applications/MacPorts`.
- GNU Emacs manual, "Find Init": "~/.emacs.el, ~/.emacs, or ~/.emacs.d/init.el in that order", the XDG location `~/.config/emacs` overridable by `XDG_CONFIG_HOME`, and "~/.emacs.d, ~/.emacs, and ~/.emacs.el are always preferred if they exist". "Initial Options": `--fg-daemon[=name]`. "emacsclient Options": an empty `-a` command starts a daemon, `ALTERNATE_EDITOR` has the same effect, and when both are present `-a` takes precedence. `server-socket-dir` (Emacs 31.1 `lisp/server.el`): `$XDG_RUNTIME_DIR/emacs`, else `emacs<uid>` under `TMPDIR` or `/tmp`. `use-short-answers` and `fido-vertical-mode` are new in 28.1; `server-after-make-frame-hook` in 27.1.
- launchd.plist(5): `KeepAlive` `SuccessfulExit` "If false, the job will be restarted in the inverse condition" (restart on a non-zero exit); `RunAtLoad` launches the job once when it is loaded.
- Doom: `github.com/doomemacs/doomemacs` redirects to `github.com/doomemacs/core`; README: `git clone --depth 1 https://github.com/doomemacs/core ~/.config/emacs` then `~/.config/emacs/bin/doom install`. `bin/doom-install`: `(defcli! install ((aot? ("--aot")) &flags (config? ("--config" :yes)) (envfile? ("--env")) (install? ("--install" :yes))) ...)`, "This command is idempotent and safe to reuse"; `doom-cli.el`: an option declared after `&flags` "will implicitly include a --no-foo". `DOOMDIR` defaults to `~/.config/doom` when Doom lives under the XDG config dir.
- Spacemacs README: `git clone https://github.com/syl20bnr/spacemacs "${HOME}/.emacs.d"`; it writes `~/.spacemacs` on the first start.

**Real-Mac risk:** the largest in this plan. Only a Mac proves that (a) the `emacs-app` cask's `emacs` link (a launcher inside `Emacs.app`) runs `--fg-daemon` under launchd and that `emacsclient -c` opens a GUI frame from that daemon; (b) `emacsclient -t` from a new WezTerm tab finds the daemon's socket (both sides use the `TMPDIR` in the plist and the login session); (c) `launchctl print gui/<uid>/sh.teeup.emacs` succeeds for a loaded agent, so a second `teeup configure emacs` leaves the daemon alone; (d) `doom install --no-env` finishes non-interactively (it takes minutes, and `doom sync` may still prompt for something else, in which case add Doom's global `--force` after checking `bin/doom --help`); (e) `defaults read -g AppleInterfaceStyle` from inside the daemon reports the appearance the shell sees. The first check on hardware: `launchctl print gui/$(id -u)/sh.teeup.emacs | grep state`, then `emacsclient -a false -e '(list teeup-theme-name teeup-font-family)'`.

- [ ] **Step 1: Write the failing test `tests/capabilities/emacs.sh`**

```bash file=tests/capabilities/emacs.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# A real Emacs for the Elisp checks, resolved before setup_test_env narrows
# PATH (and before mock_macos_base replaces uname). The Elisp is
# platform-independent, so one runner is the gate: CI installs emacs-nox on
# the Linux runner, where a missing emacs fails these checks. Anywhere else
# (the macOS runners, a laptop without Emacs) they print a note and pass.
EMACS_REAL="$(command -v emacs || true)"
# python3's plistlib parses the rendered LaunchAgent the way launchd would
# read its XML. Every CI runner image has python3; resolved here for the same
# PATH reason as emacs.
PYTHON3="$(command -v python3 || true)"
EMACS_REQUIRED=false
if [[ "${CI:-}" == "true" && "$(uname -s)" == "Linux" ]]; then EMACS_REQUIRED=true; fi

# no_real_emacs: true (after a note or a failure message) when the Elisp
# checks cannot run; its exit status is what the caller returns.
no_real_emacs() {
  if [[ -n "$EMACS_REAL" ]]; then return 1; fi
  if [[ "$EMACS_REQUIRED" == "true" ]]; then
    echo "emacs is not installed on the Linux CI runner; the workflow's emacs-nox step should have installed it"
    NO_EMACS_RC=1
  else
    echo "note: no emacs on this machine; skipping the Elisp check (CI's Linux runner runs it)."
    NO_EMACS_RC=0
  fi
  return 0
}

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  mock_command_script launchctl <<'EOF2'
case "$1" in print) [ -f "$HOME/agent-loaded" ] ;; *) exit 0 ;; esac
EOF2
  mock_command git 0 ""
  # The emacs on the fake Mac: what `command -v emacs` resolves in the plist.
  mock_command emacs 0 ""
  # `emacsclient -e t` answers only when a daemon marker exists.
  mock_command_script emacsclient <<'EOF2'
[ -f "$HOME/daemon-up" ] || exit 1
exit 0
EOF2
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  TEEUP="$TEEUP_PATH/bin/teeup"
  EMACS_DIR="$TEST_HOME/.config/emacs"
  PLIST="$TEST_HOME/Library/LaunchAgents/sh.teeup.emacs.plist"
}

set_flavor() {
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_EMACS_FLAVOR="%s"\n' "$1" > "$TEST_HOME/.config/teeup/answers"
}

test_install_dry_run_gets_the_cask() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install emacs)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask emacs-app" || return 1
  cleanup_test_env
}

test_install_falls_back_to_the_port_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  export TEEUP_TEST_MISSING="emacs"
  mock_command port 1 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install emacs 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: sudo port install emacs" || return 1
  assert_not_contains "$out" "brew install --cask" || return 1
  cleanup_test_env
}

test_install_warns_when_the_formula_is_already_installed() {
  setup
  # Homebrew reports the emacs formula installed; cask_installed (a
  # different `brew list` call) must stay false so cask_install still runs.
  mock_command_script brew <<'EOF2'
case "$1 $2 $3" in
  "list --formula emacs") exit 0 ;;
  list*) exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  local out
  out="$(DRY_RUN=true "$TEEUP" install emacs 2>&1)"
  assert_contains "$out" "Homebrew's emacs formula is installed" || return 1
  assert_contains "$out" "brew uninstall emacs" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask emacs-app" || return 1
  cleanup_test_env
}

test_configure_prefers_the_app_bundle_over_a_path_emacs() {
  setup
  # Simulates I2 on hardware: the emacs-app cask is installed (its bundle
  # exists) but Homebrew's emacs formula still owns the PATH `emacs`
  # (`mock_command emacs` in setup stands in for it). configure must use the
  # bundle's own binary for the daemon, not the formula's.
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  mkdir -p "$TEEUP_APPS_DIR/Emacs.app/Contents/MacOS"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEEUP_APPS_DIR/Emacs.app/Contents/MacOS/Emacs"
  chmod +x "$TEEUP_APPS_DIR/Emacs.app/Contents/MacOS/Emacs"
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  local plist_body
  plist_body="$(cat "$PLIST")"
  assert_contains "$plist_body" "<string>$TEEUP_APPS_DIR/Emacs.app/Contents/MacOS/Emacs</string>" || return 1
  assert_not_contains "$plist_body" "<string>$MOCK_BIN/emacs</string>" "the formula's PATH emacs must not win" || return 1
  cleanup_test_env
}

test_configure_starter_installs_the_config_and_the_daemon_agent() {
  setup
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  assert_file_exists "$EMACS_DIR/init.el" || return 1
  assert_file_exists "$EMACS_DIR/local.el" || return 1
  assert_contains "$(cat "$EMACS_DIR/init.el")" "capabilities/emacs/default/teeup/init.el" || return 1
  assert_file_exists "$PLIST" || return 1
  local plist_body
  plist_body="$(cat "$PLIST")"
  assert_contains "$plist_body" "<string>$MOCK_BIN/emacs</string>" || return 1
  assert_contains "$plist_body" "<string>--fg-daemon</string>" || return 1
  assert_contains "$plist_body" "<key>TEEUP_PATH</key>" || return 1
  assert_contains "$plist_body" "<string>$TEEUP_PATH</string>" || return 1
  assert_contains "$plist_body" "<key>XDG_CONFIG_HOME</key>" || return 1
  assert_contains "$plist_body" "<string>$TEST_HOME/.config</string>" || return 1
  assert_contains "$plist_body" "<key>SuccessfulExit</key>" "only a crash restarts the daemon" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "launchctl bootstrap gui/501 $PLIST" || return 1
  cleanup_test_env
}

test_configure_is_idempotent_and_leaves_a_loaded_daemon_alone() {
  setup
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  # launchd reports the agent loaded from now on.
  : > "$TEST_HOME/agent-loaded"
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs)"
  assert_contains "$out" "Already installed: $EMACS_DIR/init.el" || return 1
  assert_contains "$out" "Emacs daemon agent already loaded" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "launchctl bootout" "a loaded daemon is not restarted" || return 1
  cleanup_test_env
}

test_configure_reloads_when_the_plist_changed() {
  setup
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  : > "$TEST_HOME/agent-loaded"
  printf 'stale\n' > "$PLIST"
  : > "$MOCK_LOG"
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "launchctl bootstrap gui/501 $PLIST" || return 1
  assert_contains "$(cat "$PLIST")" "<string>--fg-daemon</string>" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" configure emacs)"
  assert_contains "$out" "[DRY-RUN] Would install $EMACS_DIR/init.el" || return 1
  assert_contains "$out" "[DRY-RUN] Would write $PLIST" || return 1
  [[ ! -e "$EMACS_DIR" ]] || { echo "config written in dry run"; return 1; }
  [[ ! -e "$PLIST" ]] || { echo "plist written in dry run"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "launchctl" || return 1
  cleanup_test_env
}

test_configure_without_emacs_skips_the_agent() {
  setup
  export TEEUP_TEST_MISSING="emacs"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs)"
  assert_contains "$out" "emacs is not on PATH yet" || return 1
  assert_file_exists "$EMACS_DIR/init.el" "the config is still installed" || return 1
  [[ ! -e "$PLIST" ]] || { echo "plist written without an emacs to run"; return 1; }
  cleanup_test_env
}

test_flavor_doom_clones_and_installs() {
  setup
  set_flavor doom
  local out
  out="$(DRY_RUN=true "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: git clone --depth 1 https://github.com/doomemacs/core $EMACS_DIR" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: $EMACS_DIR/bin/doom install --no-env" || return 1
  assert_not_contains "$out" "Would install $EMACS_DIR/init.el" "the starter is not installed for doom" || return 1
  cleanup_test_env
}

test_flavor_doom_skips_an_existing_checkout_and_config() {
  setup
  set_flavor doom
  mkdir -p "$EMACS_DIR/bin" "$TEST_HOME/.config/doom"
  printf '#!/bin/sh\n' > "$EMACS_DIR/bin/doom"
  chmod +x "$EMACS_DIR/bin/doom"
  printf ';; mine\n' > "$TEST_HOME/.config/doom/init.el"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "Already a Doom checkout: $EMACS_DIR" || return 1
  assert_contains "$out" "Doom is set up ($TEST_HOME/.config/doom)" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "git clone" || return 1
  cleanup_test_env
}

test_switching_starter_to_doom_backs_up_the_starter() {
  setup
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  set_flavor doom
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "$EMACS_DIR is not a Doom checkout; moving it aside." || return 1
  ls -d "$EMACS_DIR.teeup_backup_"* >/dev/null 2>&1 || { echo "no backup of the starter"; return 1; }
  assert_contains "$(cat "$MOCK_LOG")" "git clone --depth 1 https://github.com/doomemacs/core $EMACS_DIR" || return 1
  cleanup_test_env
}

test_flavor_spacemacs_clones_into_emacs_d() {
  setup
  set_flavor spacemacs
  local out
  out="$(DRY_RUN=true "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: git clone https://github.com/syl20bnr/spacemacs $TEST_HOME/.emacs.d" || return 1
  cleanup_test_env
}

test_flavor_none_touches_no_config() {
  setup
  set_flavor none
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "TEEUP_EMACS_FLAVOR=none: leaving your Emacs configuration alone." || return 1
  [[ ! -e "$EMACS_DIR" ]] || { echo "config written for flavor none"; return 1; }
  assert_file_exists "$PLIST" "the daemon agent is flavor-independent" || return 1
  cleanup_test_env
}

test_the_machine_file_wins_over_the_answer() {
  setup
  set_flavor doom
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR"
  printf 'TEEUP_EMACS_FLAVOR="none"\n' > "$TEEUP_MACHINES_DIR/testmac.conf"
  local out
  out="$(DRY_RUN=true "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "TEEUP_EMACS_FLAVOR=none: leaving your Emacs configuration alone." || return 1
  assert_not_contains "$out" "git clone" "the answers file's doom lost to the machine file" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_unknown_flavor_warns_and_uses_the_starter() {
  setup
  set_flavor vanilla
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "Unknown TEEUP_EMACS_FLAVOR 'vanilla'" || return 1
  assert_file_exists "$EMACS_DIR/init.el" || return 1
  cleanup_test_env
}

test_a_legacy_emacs_d_is_reported_not_moved() {
  setup
  mkdir -p "$TEST_HOME/.emacs.d"
  printf ';; old\n' > "$TEST_HOME/.emacs.d/init.el"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "$TEST_HOME/.emacs.d exists and Emacs reads it instead of $EMACS_DIR/init.el" || return 1
  assert_equals ";; old" "$(cat "$TEST_HOME/.emacs.d/init.el")" || return 1
  cleanup_test_env
}

test_plist_escapes_metacharacters_in_paths() {
  setup
  # A state dir and a TMPDIR with a space and an ampersand: the plist must
  # stay valid XML.
  export TEEUP_STATE_DIR="$TEST_HOME/st ate&more"
  export TMPDIR="$TEST_HOME/t mp&<T>"
  mkdir -p "$TMPDIR"
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  local plist_body
  plist_body="$(cat "$PLIST")"
  assert_contains "$plist_body" "<string>$TEST_HOME/st ate&amp;more</string>" || return 1
  assert_contains "$plist_body" "<key>TMPDIR</key>" || return 1
  assert_contains "$plist_body" "<string>$TEST_HOME/t mp&amp;&lt;T&gt;</string>" || return 1
  assert_not_contains "$plist_body" "ate&more" "a bare ampersand would be malformed XML" || return 1
  if [[ -z "$PYTHON3" ]]; then
    echo "python3 is not installed: this test parses the plist with plistlib"
    return 1
  fi
  local parsed
  parsed="$("$PYTHON3" -c 'import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
print(d["EnvironmentVariables"]["TEEUP_STATE_DIR"] + "|" + d["EnvironmentVariables"]["TMPDIR"])' "$PLIST" 2>&1)"
  assert_equals "$TEST_HOME/st ate&more|$TEST_HOME/t mp&<T>" "$parsed" "the plist parses and the values round-trip" || return 1
  unset TEEUP_STATE_DIR TMPDIR
  cleanup_test_env
}

test_the_daemon_probe_never_starts_a_daemon() {
  setup
  mkdir -p "$TEST_HOME/.local/state/teeup/done"
  : > "$TEST_HOME/.local/state/teeup/done/cap-emacs"
  local out
  out="$(ALTERNATE_EDITOR="" DRY_RUN=true "$TEEUP" theme set catppuccin 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "emacsclient -a false -e t" || return 1
  assert_not_contains "$(grep '^emacsclient' "$MOCK_LOG")" "emacsclient -e" "every call overrides ALTERNATE_EDITOR" || return 1
  assert_contains "$out" "No Emacs daemon is running" || return 1
  cleanup_test_env
}

test_theme_renders_the_emacs_palette() {
  setup
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  local dark light
  dark="$TEST_HOME/.local/state/teeup/current/theme/dark/emacs.el"
  light="$TEST_HOME/.local/state/teeup/current/theme/light/emacs.el"
  assert_file_exists "$dark" || return 1
  assert_contains "$(cat "$dark")" '(setq teeup-theme-name (intern "modus-vivendi"))' || return 1
  assert_contains "$(cat "$light")" '(setq teeup-theme-name (intern "modus-operandi"))' || return 1
  assert_contains "$(cat "$dark")" '(accent . "#89b4fa")' || return 1
  assert_not_contains "$(cat "$dark")" "{{" "every token was substituted" || return 1
  cleanup_test_env
}

test_hooks_wait_until_teeup_installed_emacs() {
  setup
  : > "$TEST_HOME/daemon-up"
  local out
  out="$(DRY_RUN=true "$TEEUP" theme set catppuccin 2>&1)"
  assert_not_contains "$out" "emacsclient -e" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "emacsclient" "not even the daemon probe runs" || return 1
  cleanup_test_env
}

test_theme_apply_reloads_a_running_daemon() {
  setup
  mkdir -p "$TEST_HOME/.local/state/teeup/done"
  : > "$TEST_HOME/.local/state/teeup/done/cap-emacs"
  : > "$TEST_HOME/daemon-up"
  local out
  out="$(DRY_RUN=true "$TEEUP" theme set catppuccin 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: emacsclient -a false -e (when (fboundp 'teeup-apply) (teeup-apply))" || return 1
  rm -f "$TEST_HOME/daemon-up"
  out="$(DRY_RUN=true "$TEEUP" install font Hack 2>&1)"
  assert_contains "$out" "No Emacs daemon is running; the font is read at the next start." || return 1
  cleanup_test_env
}

test_remove_unloads_the_agent_through_lib_macos() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  DRY_RUN=false cap_run emacs remove >/dev/null
  [[ ! -e "$PLIST" ]] || { echo "plist survived remove"; return 1; }
  assert_contains "$(cat "$MOCK_LOG")" "launchctl bootout gui/501 $PLIST" || return 1
  assert_file_exists "$EMACS_DIR/init.el" "remove keeps the configuration" || return 1
  cleanup_test_env
}

test_configure_points_git_at_emacsclient() {
  setup
  # git ran in the core tier before emacs existed and chose vim.
  mkdir -p "$TEST_HOME/.config/git"
  printf '[core]\n\teditor = vim\n' > "$TEST_HOME/.config/git/teeup-generated"
  mock_command delta 0 ""
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "Re-running the git configuration so git opens emacsclient." || return 1
  assert_contains "$(cat "$TEST_HOME/.config/git/teeup-generated")" "editor = emacsclient -t" || return 1
  out="$(DRY_RUN=false "$TEEUP" configure emacs 2>&1)"
  assert_not_contains "$out" "Re-running the git configuration" "an up-to-date git is left alone" || return 1
  printf '[core]\n\teditor = vim\n' > "$TEST_HOME/.config/git/teeup-generated"
  out="$(TEEUP_SKIP="git" DRY_RUN=false "$TEEUP" configure emacs 2>&1)"
  assert_not_contains "$out" "Re-running the git configuration" "a skipped git is left alone" || return 1
  cleanup_test_env
}

# The starter is loaded by a real Emacs in batch mode with HOME pointing at
# the test home, TEEUP_PATH at this checkout and the theme rendered: it must
# resolve the layer, apply the light Modus theme (the defaults mock exits 1)
# and read the font teeup recorded.
test_starter_loads_in_a_real_emacs() {
  setup
  local NO_EMACS_RC=0
  if no_real_emacs; then
    cleanup_test_env
    return "$NO_EMACS_RC"
  fi
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  mkdir -p "$TEST_HOME/.local/state/teeup/current"
  printf 'Hack Nerd Font\n' > "$TEST_HOME/.local/state/teeup/current/font"
  local out rc=0
  out="$(cd "$TEST_HOME" && env -u TEEUP_APPEARANCE TEEUP_PATH="$TEEUP_PATH" "$EMACS_REAL" -Q --batch \
    -l "$EMACS_DIR/init.el" \
    --eval '(princ (format "THEME=%s MODE=%s FONT=%s ACCENT=%s\n" teeup-theme-name teeup-theme-mode teeup-font-family (cdr (assq (quote accent) teeup-theme-colors))))' 2>&1)" || rc=$?
  assert_success "$rc" "emacs --batch exited non-zero: $out" || return 1
  assert_contains "$out" "THEME=modus-operandi MODE=light FONT=Hack Nerd Font ACCENT=#1e66f5" || return 1
  cleanup_test_env
}

# ~/.config/teeup/env holds %q-escaped values; the thin init.el must decode a
# path with a space, a quote, a dollar sign and non-ASCII bytes the way bash
# would, in both the backslash form and the $'...' form. bash 5 writes the
# first; bash 3.2 (macOS's /bin/bash) switches to the second for non-ASCII
# bytes. The macOS runners have no Emacs, so the $'...' form is also written
# by hand here, byte for byte what bash 3.2 prints for this path, and the
# check does not depend on which bash the runner has. /bin/bash and
# TEEUP_TEST_BASH32 (a developer's bash 3.2 build) are tried as well.
test_env_file_paths_survive_special_bytes() {
  setup
  local NO_EMACS_RC=0
  if no_real_emacs; then
    cleanup_test_env
    return "$NO_EMACS_RC"
  fi
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  local weird checkout
  weird="José's \$Café Dir"
  checkout="$TEST_HOME/$weird Checkout/teeup"
  mkdir -p "$TEST_HOME/.config/teeup"
  local bash_bin out quoted
  for bash_bin in literal bash /bin/bash "${TEEUP_TEST_BASH32:-}"; do
    if [[ "$bash_bin" == "literal" ]]; then
      # What bash 3.2's %q prints for this path: $'...' with the quote
      # backslash-escaped and each UTF-8 byte of é as an octal escape.
      quoted="\$'$TEST_HOME/Jos\\303\\251\\'s \$Caf\\303\\251 Dir Checkout/teeup'"
    else
      [[ -n "$bash_bin" && -x "$(command -v "$bash_bin")" ]] || continue
      quoted="$("$bash_bin" -c 'printf "%q" "$1"' _ "$checkout")"
    fi
    printf 'export TEEUP_PATH=%s\n' "$quoted" > "$TEST_HOME/.config/teeup/env"
    out="$(cd "$TEST_HOME" && env -u TEEUP_PATH "$EMACS_REAL" -Q --batch -l "$EMACS_DIR/init.el" \
      --eval '(princ (format "PATH=%s\n" teeup-path))' 2>/dev/null)"
    assert_contains "$out" "PATH=$checkout" "$bash_bin: TEEUP_PATH should decode byte-for-byte (got: $out)" || return 1
  done
  cleanup_test_env
}

echo "capabilities/emacs"
run_test "install dry run gets the cask" test_install_dry_run_gets_the_cask
run_test "install falls back to the port on macports" test_install_falls_back_to_the_port_on_macports
run_test "install warns when the formula is already installed" test_install_warns_when_the_formula_is_already_installed
run_test "configure prefers the app bundle over a PATH emacs" test_configure_prefers_the_app_bundle_over_a_path_emacs
run_test "configure starter installs the config and the daemon agent" test_configure_starter_installs_the_config_and_the_daemon_agent
run_test "configure is idempotent and leaves a loaded daemon alone" test_configure_is_idempotent_and_leaves_a_loaded_daemon_alone
run_test "configure reloads when the plist changed" test_configure_reloads_when_the_plist_changed
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "configure without emacs skips the agent" test_configure_without_emacs_skips_the_agent
run_test "flavor doom clones and installs" test_flavor_doom_clones_and_installs
run_test "flavor doom skips an existing checkout and config" test_flavor_doom_skips_an_existing_checkout_and_config
run_test "switching starter to doom backs up the starter" test_switching_starter_to_doom_backs_up_the_starter
run_test "flavor spacemacs clones into ~/.emacs.d" test_flavor_spacemacs_clones_into_emacs_d
run_test "flavor none touches no config" test_flavor_none_touches_no_config
run_test "the machine file wins over the answer" test_the_machine_file_wins_over_the_answer
run_test "unknown flavor warns and uses the starter" test_unknown_flavor_warns_and_uses_the_starter
run_test "a legacy ~/.emacs.d is reported, not moved" test_a_legacy_emacs_d_is_reported_not_moved
run_test "plist escapes metacharacters in paths" test_plist_escapes_metacharacters_in_paths
run_test "the daemon probe never starts a daemon" test_the_daemon_probe_never_starts_a_daemon
run_test "theme renders the emacs palette" test_theme_renders_the_emacs_palette
run_test "hooks wait until teeup installed emacs" test_hooks_wait_until_teeup_installed_emacs
run_test "theme-apply reloads a running daemon" test_theme_apply_reloads_a_running_daemon
run_test "remove unloads the agent through lib/macos" test_remove_unloads_the_agent_through_lib_macos
run_test "configure points git at emacsclient" test_configure_points_git_at_emacsclient
run_test "starter loads in a real emacs" test_starter_loads_in_a_real_emacs
run_test "env file paths survive special bytes" test_env_file_paths_survive_special_bytes
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/capabilities/emacs.sh`
Expected: `Unknown capability: emacs` in most failures; `Summary: 1/26 passed` (only `hooks wait until teeup installed emacs`, because nothing runs yet). On a machine with no `emacs` at all the two Elisp checks print their note and pass, giving `Summary: 3/26 passed`.

- [ ] **Step 3: Write the metadata and `install`**

```sh file=capabilities/emacs/capability
summary="Emacs as a login daemon with emacsclient, in the flavor you chose"
group=editors
tier=daily
requires="package-manager git"
provides=""
packages=""
casks="emacs-app"
apps="Emacs"
interactive=false
```

```bash file=capabilities/emacs/install
#!/usr/bin/env bash
# Homebrew's `emacs` formula is the terminal-only build; the emacs-app cask
# (emacsformacosx.com) is the GUI build and links `emacs` and `emacsclient`
# into the Homebrew bin dir, so one install serves the daemon, windows and the
# terminal client. MacPorts has no casks: its `emacs` port is the terminal
# build with the same daemon and client commands, and its `emacs-app` port is
# the GUI build without them on PATH, so the port is the one the daemon agent
# can run.
if casks_supported; then
  # brew's cask link step skips a binary that already belongs to a formula
  # ("It seems there is already a Binary at .../emacs from formula emacs;
  # skipping link.") and still exits 0, so the cask install "succeeds" while
  # emacs/emacsclient keep pointing at the formula's terminal-only build.
  if pkg_installed emacs; then
    warn "Homebrew's emacs formula is installed; the emacs-app cask will not link emacs or emacsclient over it, so the daemon and emacsclient -c would keep using the terminal-only build. Run: brew uninstall emacs, then: teeup configure emacs"
  fi
  cask_install emacs-app
else
  pkg_install emacs emacs || warn "No emacs port could be installed; download Emacs from https://emacsformacosx.com and re-run: teeup configure emacs"
fi
```

- [ ] **Step 4: Write the thin user files and teeup's layer**

`config/emacs/init.el` is copied once into `~/.config/emacs` and belongs to the user; it finds the checkout (environment, then `~/.config/teeup/env`, whose values went through bash's `%q`, then `~/.local/share/teeup`) and loads `default/teeup/init.el` from it. `local.el` is copied once with everything commented out.

```elisp file=capabilities/emacs/config/emacs/init.el
;;; init.el --- ~/.config/emacs/init.el, yours  -*- lexical-binding: t -*-

;; teeup installed this file once and will not overwrite it. The thick layer
;; is capabilities/emacs/default/teeup/init.el in the teeup checkout, upgraded
;; by `teeup update`. Put your own settings in ~/.config/emacs/local.el, which
;; loads last, or below the layer call at the bottom of this file.

;; --- where the checkout is ---------------------------------------------------
;; The daemon started by launchd gets TEEUP_PATH from its LaunchAgent, a
;; shell exports it, and ~/.config/teeup/env (written by teeup-runtime)
;; covers everything else. Each value in that file went through bash's
;; `printf %q`, so a path with a space, a quote or a non-ASCII byte comes back
;; as a backslash-escaped word or a $'...' ANSI-C literal; teeup--unquote
;; undoes both.
(defun teeup--unquote (word)
  "Return the plain text of one shell WORD as bash would expand it."
  (let ((i 0) (n (length word)) (out nil))
    (while (< i n)
      (let ((c (aref word i)))
        (cond
         ;; '...' keeps everything literal.
         ((eq c ?')
          (let ((j (or (string-search "'" word (1+ i)) n)))
            (push (substring word (1+ i) j) out)
            (setq i (1+ j))))
         ;; "...": backslash escapes only $ ` " \ and newline.
         ((eq c ?\")
          (let ((j (1+ i)) (buf nil))
            (while (and (< j n) (not (eq (aref word j) ?\")))
              (let ((cj (aref word j)))
                (if (and (eq cj ?\\) (< (1+ j) n)
                         (memq (aref word (1+ j)) '(?$ ?` ?\" ?\\ ?\n)))
                    (progn (push (aref word (1+ j)) buf) (setq j (+ j 2)))
                  (push cj buf) (setq j (1+ j)))))
            (push (concat (nreverse buf)) out)
            (setq i (1+ j))))
         ;; $'...': ANSI-C quoting with \NNN octal, \xHH and the usual escapes.
         ((and (eq c ?$) (< (1+ i) n) (eq (aref word (1+ i)) ?'))
          (let ((j (+ i 2)) (buf nil))
            (while (and (< j n) (not (eq (aref word j) ?')))
              (let ((cj (aref word j)))
                (if (and (eq cj ?\\) (< (1+ j) n))
                    (let ((nx (aref word (1+ j))))
                      (cond
                       ((and (>= nx ?0) (<= nx ?7))
                        (let ((k (1+ j)) (v 0))
                          (while (and (< k n) (< (- k j) 4)
                                      (>= (aref word k) ?0) (<= (aref word k) ?7))
                            (setq v (+ (* v 8) (- (aref word k) ?0)) k (1+ k)))
                          (push (logand v 255) buf)
                          (setq j k)))
                       ((and (eq nx ?x) (< (+ j 2) n)
                             (string-match-p "[0-9a-fA-F]" (string (aref word (+ j 2)))))
                        (let ((k (+ j 2)) (hex ""))
                          (while (and (< k n) (< (length hex) 2)
                                      (string-match-p "[0-9a-fA-F]" (string (aref word k))))
                            (setq hex (concat hex (string (aref word k))) k (1+ k)))
                          (push (string-to-number hex 16) buf)
                          (setq j k)))
                       ((eq nx ?n) (push ?\n buf) (setq j (+ j 2)))
                       ((eq nx ?t) (push ?\t buf) (setq j (+ j 2)))
                       ((eq nx ?r) (push ?\r buf) (setq j (+ j 2)))
                       ((eq nx ?a) (push 7 buf) (setq j (+ j 2)))
                       ((eq nx ?b) (push 8 buf) (setq j (+ j 2)))
                       ((memq nx '(?e ?E)) (push 27 buf) (setq j (+ j 2)))
                       ((eq nx ?f) (push 12 buf) (setq j (+ j 2)))
                       ((eq nx ?v) (push 11 buf) (setq j (+ j 2)))
                       (t (push nx buf) (setq j (+ j 2)))))
                  (push cj buf) (setq j (1+ j)))))
            ;; The bytes are raw UTF-8; decode them back into characters.
            (push (decode-coding-string (apply #'unibyte-string (nreverse buf)) 'utf-8) out)
            (setq i (1+ j))))
         ;; A bare backslash makes the next character literal.
         ((and (eq c ?\\) (< (1+ i) n))
          (push (string (aref word (1+ i))) out)
          (setq i (+ i 2)))
         (t (push (string c) out) (setq i (1+ i))))))
    (apply #'concat (nreverse out))))

(defun teeup--env-file-value (key)
  "Return KEY from ~/.config/teeup/env, or nil when the file lacks it."
  (let ((file (expand-file-name "teeup/env" (or (getenv "XDG_CONFIG_HOME") "~/.config")))
        (re (concat "^export " (regexp-quote key) "=\\(.+\\)$")))
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward re nil t)
          (teeup--unquote (match-string 1)))))))

(defvar teeup-path
  (or (getenv "TEEUP_PATH")
      (teeup--env-file-value "TEEUP_PATH")
      (expand-file-name "~/.local/share/teeup"))
  "The teeup checkout.")

(defvar teeup-state-dir
  (or (getenv "TEEUP_STATE_DIR")
      (teeup--env-file-value "TEEUP_STATE_DIR")
      (expand-file-name "teeup" (or (getenv "XDG_STATE_HOME") "~/.local/state")))
  "Where teeup keeps the rendered theme and the font name.")

;; --- the teeup layer ---------------------------------------------------------
(let ((layer (expand-file-name "capabilities/emacs/default/teeup/init.el" teeup-path)))
  (if (file-readable-p layer)
      (load layer nil t)
    (message "teeup: no layer at %s; set TEEUP_PATH or run: teeup configure teeup-runtime" layer)))

;; Your own settings go below this line, or in local.el.
(let ((local (expand-file-name "local.el" user-emacs-directory)))
  (when (file-readable-p local)
    (load local nil t)))

;;; init.el ends here
```

```elisp file=capabilities/emacs/config/emacs/local.el
;;; local.el --- ~/.config/emacs/local.el, yours  -*- lexical-binding: t -*-

;; Loaded last by init.el. teeup ships this file once, with everything
;; commented out, and never touches it again. Anything the teeup layer set can
;; be overridden here.

;; A bigger default face (1/10 pt units; the family comes from
;; `teeup install font <name>`, so only the size belongs here):
;; (setq teeup-font-height 160)
;; (teeup-apply)

;; Packages from MELPA install on demand with M-x package-install, or:
;; (use-package magit :ensure t)

;;; local.el ends here
```

```elisp file=capabilities/emacs/default/teeup/init.el
;;; teeup/init.el --- teeup's Emacs layer  -*- lexical-binding: t -*-

;; Loaded by the thin ~/.config/emacs/init.el. This file is teeup's: edit it
;; in the checkout, not in your home directory. It is a small, built-ins-only
;; starter, so a fresh Mac gets a working Emacs before any package downloads;
;; MELPA is configured for M-x package-install and use-package :ensure.

(defvar teeup-path (expand-file-name "~/.local/share/teeup"))
(defvar teeup-state-dir (expand-file-name "~/.local/state/teeup"))
(defvar teeup-font-height 140
  "Default face height in 1/10 pt. Set it in local.el, then (teeup-apply).")
(defvar teeup-font-family "JetBrainsMono Nerd Font"
  "The family `teeup install font` recorded; refreshed by `teeup-apply'.")
(defvar teeup-theme-mode nil "dark or light, as last applied.")
(defvar teeup-theme-name nil "The theme symbol the rendered palette named.")
(defvar teeup-theme-colors nil "The semantic palette, as an alist of strings.")

;; --- packages ----------------------------------------------------------------
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-readable-p custom-file)
  (load custom-file nil t))

;; --- defaults ----------------------------------------------------------------
(setq inhibit-startup-screen t
      initial-scratch-message nil
      ring-bell-function 'ignore
      make-backup-files nil
      create-lockfiles nil
      auto-save-default t
      use-short-answers t
      confirm-kill-emacs nil
      sentence-end-double-space nil
      require-final-newline t
      load-prefer-newer t)
(setq-default indent-tabs-mode nil
              tab-width 4
              fill-column 80)
(when (fboundp 'tool-bar-mode) (tool-bar-mode -1))
(when (fboundp 'scroll-bar-mode) (scroll-bar-mode -1))
(menu-bar-mode -1)
(column-number-mode 1)
(global-auto-revert-mode 1)
(savehist-mode 1)
(recentf-mode 1)
(save-place-mode 1)
(show-paren-mode 1)
(electric-pair-mode 1)
(delete-selection-mode 1)
(fido-vertical-mode 1)
(when (fboundp 'which-key-mode) (which-key-mode 1))
(when (fboundp 'global-display-line-numbers-mode)
  (add-hook 'prog-mode-hook #'display-line-numbers-mode))
(when (eq system-type 'darwin)
  ;; Option is Meta, Command is Super; Cmd-V/Cmd-C keep macOS meaning.
  (setq ns-option-modifier 'meta
        ns-command-modifier 'super
        ns-pop-up-frames nil))

;; --- appearance, theme and font ----------------------------------------------
(defun teeup--read-first-line (path)
  "Return the first non-blank line of PATH, or nil."
  (when (file-readable-p path)
    (with-temp-buffer
      (insert-file-contents path)
      (goto-char (point-min))
      (let ((line (string-trim (buffer-substring-no-properties
                                (point) (line-end-position)))))
        (unless (string-empty-p line) line)))))

(defun teeup-appearance ()
  "Return \"dark\" or \"light\": TEEUP_APPEARANCE from a shell, else macOS.
`defaults read -g AppleInterfaceStyle` prints Dark in dark mode and fails in
light mode, the same rule the zsh layer and lib/macos.sh use."
  (let ((env (getenv "TEEUP_APPEARANCE")))
    (cond
     ((member env '("dark" "light")) env)
     ((and (executable-find "defaults")
           (string= "Dark"
                    (string-trim
                     (with-output-to-string
                       (with-current-buffer standard-output
                         (call-process "defaults" nil t nil "read" "-g" "AppleInterfaceStyle"))))))
      "dark")
     (t "light"))))

(defun teeup-apply-font ()
  "Point the default face at the family in current/font."
  (setq teeup-font-family
        (or (teeup--read-first-line (expand-file-name "current/font" teeup-state-dir))
            teeup-font-family))
  (when (display-graphic-p)
    (set-face-attribute 'default nil :family teeup-font-family :height teeup-font-height)))

(defun teeup-apply-theme ()
  "Load the theme the rendered palette for the current appearance names."
  (setq teeup-theme-mode (teeup-appearance))
  (let ((rendered (expand-file-name (concat "current/theme/" teeup-theme-mode "/emacs.el")
                                    teeup-state-dir)))
    (if (file-readable-p rendered)
        (load rendered nil t)
      ;; Before the first `teeup theme set`, use the built-in Modus themes.
      (setq teeup-theme-name (if (string= teeup-theme-mode "dark") 'modus-vivendi 'modus-operandi))))
  ;; A palette may name a theme this Emacs does not have (a MELPA theme not
  ;; installed yet); say so and keep the current one rather than failing the
  ;; whole init, which in a daemon would leave nothing to connect to.
  (when teeup-theme-name
    (condition-case err
        (progn
          (mapc #'disable-theme custom-enabled-themes)
          (load-theme teeup-theme-name t))
      (error (message "teeup: could not load theme %s: %s"
                      teeup-theme-name (error-message-string err))))))

(defun teeup-apply ()
  "Re-read the theme and font teeup recorded and apply both.
`teeup theme set` and `teeup install font` call this through emacsclient."
  (interactive)
  (teeup-apply-theme)
  (teeup-apply-font))

(teeup-apply)
;; A daemon has no graphic display until the first frame, so the font is set
;; again when a frame appears; and emacs-plus builds signal appearance changes.
(add-hook 'server-after-make-frame-hook #'teeup-apply-font)
(when (boundp 'ns-system-appearance-change-functions)
  (add-hook 'ns-system-appearance-change-functions (lambda (_appearance) (teeup-apply))))

;; --- keys --------------------------------------------------------------------
(global-set-key (kbd "C-x C-b") #'ibuffer)
(global-set-key (kbd "M-/") #'hippie-expand)
(global-set-key (kbd "C-c t") #'teeup-apply)

(provide 'teeup-init)
;;; teeup/init.el ends here
```

- [ ] **Step 5: Write the themed template and add `emacs_theme` to both palettes**

The theme name is passed through `intern` from a string, so no palette value can close the form.

```elisp file=capabilities/emacs/themed/emacs.el.tpl
;;; emacs.el --- generated by `teeup theme set'; do not edit  -*- lexical-binding: t -*-
;; The next theme switch replaces this file. Loaded by
;; capabilities/emacs/default/teeup/init.el for the {{ mode }} appearance. The
;; theme name is a string passed to `intern' rather than a quoted symbol, so a
;; palette value can never close the form and run code of its own.
(setq teeup-theme-mode "{{ mode }}")
(setq teeup-theme-name (intern "{{ emacs_theme }}"))
(setq teeup-theme-colors
      '((accent . "{{ accent }}")
        (selection . "{{ selection }}")
        (muted . "{{ muted }}")
        (background . "{{ background }}")
        (dark-background . "{{ dark_background }}")
        (lighter-background . "{{ lighter_background }}")
        (foreground . "{{ foreground }}")
        (light-foreground . "{{ light_foreground }}")
        (bright-foreground . "{{ bright_foreground }}")
        (red . "{{ red }}")
        (orange . "{{ orange }}")
        (yellow . "{{ yellow }}")
        (green . "{{ green }}")
        (cyan . "{{ cyan }}")
        (blue . "{{ blue }}")
        (magenta . "{{ magenta }}")))
```

```toml edit-old=themes/catppuccin/dark.toml
# Not a colour: bat has no Catppuccin theme built in, so the palette names the
# closest built-in. Rendered into env.sh as BAT_THEME.
bat_theme = "OneHalfDark"

accent = "#89b4fa"
selection = "#45475a"
```

```toml edit-new=themes/catppuccin/dark.toml
# Not a colour: bat has no Catppuccin theme built in, so the palette names the
# closest built-in. Rendered into env.sh as BAT_THEME.
bat_theme = "OneHalfDark"

# Not colours either: the name each editor knows the closest theme by. Every
# key here must exist in both modes, and a user theme must define them too.
emacs_theme = "modus-vivendi"

accent = "#89b4fa"
selection = "#45475a"
```

```toml edit-old=themes/catppuccin/light.toml
mode = "light"

bat_theme = "OneHalfLight"

accent = "#1e66f5"
selection = "#ccd0da"
```

```toml edit-new=themes/catppuccin/light.toml
mode = "light"

bat_theme = "OneHalfLight"

# Not colours either: the name each editor knows the closest theme by. Every
# key here must exist in both modes, and a user theme must define them too.
emacs_theme = "modus-operandi"

accent = "#1e66f5"
selection = "#ccd0da"
```

- [ ] **Step 6: Write `configure` and `remove`**

```bash file=capabilities/emacs/configure
#!/usr/bin/env bash
# Two jobs: put the chosen flavor's configuration in place, and keep an Emacs
# daemon running through a LaunchAgent so `emacsclient -t` (the editor the
# git and zsh capabilities point at) always has something to talk to.
#
# The flavor is the answer TEEUP_EMACS_FLAVOR (starter, doom, spacemacs or
# none; the wizard asks it when the daily tier is on, and a machine file can
# pin it). Emacs reads ~/.emacs.el, ~/.emacs and ~/.emacs.d before
# ~/.config/emacs (Emacs manual, "Find Init"), which decides where each
# flavor lives: the starter and Doom use ~/.config/emacs, Spacemacs's own
# instructions use ~/.emacs.d, and a leftover legacy location silently wins
# over the starter, so it is reported rather than moved.
flavor="$(answers_get TEEUP_EMACS_FLAVOR starter)"
case "$flavor" in
  starter|doom|spacemacs|none) ;;
  *)
    warn "Unknown TEEUP_EMACS_FLAVOR '$flavor' (expected starter, doom, spacemacs or none); using starter."
    flavor=starter
    ;;
esac

EMACS_DIR="$(user_config_dir)/emacs"
DOOM_DIR="${DOOMDIR:-$(user_config_dir)/doom}"
SPACEMACS_DIR="$HOME/.emacs.d"

legacy_init=""
for candidate in "$HOME/.emacs.el" "$HOME/.emacs" "$HOME/.emacs.d"; do
  if [[ -e "$candidate" ]]; then
    legacy_init="$candidate"
    break
  fi
done

# is_doom_checkout <dir>: Doom's CLI lives at bin/doom in its own checkout.
is_doom_checkout() { [[ -x "$1/bin/doom" ]]; }
# is_spacemacs_checkout <dir>: every Spacemacs checkout has core/ and layers/.
is_spacemacs_checkout() { [[ -d "$1/core" && -d "$1/layers" && -f "$1/init.el" ]]; }

case "$flavor" in
  starter)
    if is_doom_checkout "$EMACS_DIR"; then
      log "$EMACS_DIR is a Doom checkout; moving it aside for the starter configuration."
      backup_target "$EMACS_DIR" >/dev/null
    fi
    copy_config_once "$TEEUP_CAP_DIR/config/emacs/init.el" "$EMACS_DIR/init.el"
    copy_config_once "$TEEUP_CAP_DIR/config/emacs/local.el" "$EMACS_DIR/local.el"
    if [[ -n "$legacy_init" ]]; then
      warn "$legacy_init exists and Emacs reads it instead of $EMACS_DIR/init.el. Move it aside to use the teeup starter."
    fi
    ;;
  doom)
    if is_doom_checkout "$EMACS_DIR"; then
      log "Already a Doom checkout: $EMACS_DIR"
    else
      if [[ -e "$EMACS_DIR" ]]; then
        log "$EMACS_DIR is not a Doom checkout; moving it aside."
        backup_target "$EMACS_DIR" >/dev/null
      fi
      run_cmd git clone --depth 1 https://github.com/doomemacs/core "$EMACS_DIR" ||
        warn "Could not clone Doom Emacs; check the network and re-run: teeup configure emacs"
    fi
    # `doom install` is idempotent by Doom's own description, but a sync takes
    # minutes, so it runs only until the private config exists. --no-env
    # skips the one interactive prompt (envvar file), which this non-TTY
    # process could not answer.
    if [[ -f "$DOOM_DIR/init.el" ]]; then
      log "Doom is set up ($DOOM_DIR); after editing it run: doom sync"
    elif ! have emacs; then
      warn "emacs is not on PATH; once it is, run: $EMACS_DIR/bin/doom install --no-env"
    else
      run_cmd "$EMACS_DIR/bin/doom" install --no-env ||
        warn "doom install did not finish; re-run it by hand: $EMACS_DIR/bin/doom install --no-env"
    fi
    if [[ -n "$legacy_init" ]]; then
      warn "$legacy_init exists and Emacs reads it instead of $EMACS_DIR. Move it aside to use Doom."
    fi
    ;;
  spacemacs)
    if is_spacemacs_checkout "$SPACEMACS_DIR"; then
      log "Already a Spacemacs checkout: $SPACEMACS_DIR"
    else
      if [[ -e "$SPACEMACS_DIR" ]]; then
        log "$SPACEMACS_DIR is not a Spacemacs checkout; moving it aside."
        backup_target "$SPACEMACS_DIR" >/dev/null
      fi
      run_cmd git clone https://github.com/syl20bnr/spacemacs "$SPACEMACS_DIR" ||
        warn "Could not clone Spacemacs; check the network and re-run: teeup configure emacs"
    fi
    for candidate in "$HOME/.emacs.el" "$HOME/.emacs"; do
      if [[ -e "$candidate" ]]; then
        warn "$candidate exists and Emacs reads it instead of $SPACEMACS_DIR. Move it aside to use Spacemacs."
      fi
    done
    log "Spacemacs finishes its own setup on the first start; ~/.spacemacs is written then."
    ;;
  none)
    log "TEEUP_EMACS_FLAVOR=none: leaving your Emacs configuration alone."
    ;;
esac

# --- the daemon --------------------------------------------------------------
# launchd starts the agent with no PATH and none of the shell's environment,
# so the plist carries the binary's full path and the variables the starter
# layer reads: TEEUP_PATH first (a config that cannot find the checkout falls
# back to a plain Emacs), and XDG_CONFIG_HOME, without which a daemon on a
# machine with a non-default one would look for ~/.config/emacs, find nothing
# and create ~/.emacs.d (Emacs manual, "Find Init"). The values are
# XML-escaped: a home directory with an ampersand in it would otherwise be a
# malformed plist.
#
# RunAtLoad starts the daemon at login and whenever the agent is (re)loaded.
# KeepAlive with SuccessfulExit false restarts it only after a crash
# (launchd.plist(5)): `kill-emacs` exits 0, so a daemon stopped on purpose
# stays down until the next login, `launchctl kickstart`, or an `emacsclient`
# from zsh (the shell layer exports an empty ALTERNATE_EDITOR, which starts
# one).
plist_escape() {
  printf '%s\n' "$(replace_literal "$(replace_literal "$(replace_literal "$1" '&' '&amp;')" '<' '&lt;')" '>' '&gt;')"
}

# Prefer the emacs-app cask's own binary inside the bundle over a PATH
# `emacs`: when Homebrew's terminal-only emacs formula is already installed
# (I2, install's warning above), the cask's link step skips linking
# emacs/emacsclient over the formula's binary, so `command -v emacs` still
# resolves the formula build and the daemon would never open a GUI frame.
# TEEUP_APPS_DIR is the test hook for /Applications; ~/Applications is where
# HOMEBREW_CASK_OPTS can land a cask instead.
emacs_bin=""
for app_dir in "${TEEUP_APPS_DIR:-/Applications}" "$HOME/Applications"; do
  if [[ -x "$app_dir/Emacs.app/Contents/MacOS/Emacs" ]]; then
    emacs_bin="$app_dir/Emacs.app/Contents/MacOS/Emacs"
    break
  fi
done
if [[ -z "$emacs_bin" ]] && have emacs; then
  emacs_bin="$(command -v emacs)"
fi
if [[ -z "$emacs_bin" ]]; then
  log "emacs is not on PATH yet; the daemon LaunchAgent is written the next time you run: teeup configure emacs"
else
  agent_path="$(dirname "$emacs_bin"):$(pkg_prefix)/bin:$(pkg_prefix)/sbin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  # The server socket lives under TMPDIR (emacs<uid>), and emacsclient looks
  # under its own TMPDIR, so the daemon gets the one this shell has: the
  # per-user temporary directory macOS gives every login session.
  tmpdir_entry=""
  if [[ -n "${TMPDIR:-}" ]]; then
    tmpdir_entry="
    <key>TMPDIR</key>
    <string>$(plist_escape "$TMPDIR")</string>"
  fi
  rendered_plist="$(mktemp)"
  cat > "$rendered_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>sh.teeup.emacs</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(plist_escape "$emacs_bin")</string>
    <string>--fg-daemon</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$(plist_escape "$agent_path")</string>
    <key>XDG_CONFIG_HOME</key>
    <string>$(plist_escape "$(user_config_dir)")</string>
    <key>TEEUP_PATH</key>
    <string>$(plist_escape "$TEEUP_PATH")</string>
    <key>TEEUP_CONFIG_DIR</key>
    <string>$(plist_escape "$TEEUP_CONFIG_DIR")</string>
    <key>TEEUP_STATE_DIR</key>
    <string>$(plist_escape "$TEEUP_STATE_DIR")</string>$tmpdir_entry
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>ProcessType</key>
  <string>Interactive</string>
</dict>
</plist>
PLIST

  # launchagent_install always reloads, which would kill a running daemon (and
  # its unsaved buffers) on every `teeup configure emacs`. So the agent is only
  # (re)installed when the plist changed or launchd does not have it loaded;
  # `launchctl print` is the read that answers the second half.
  plist_path="$HOME/Library/LaunchAgents/sh.teeup.emacs.plist"
  if [[ -f "$plist_path" ]] && cmp -s "$rendered_plist" "$plist_path" &&
     launchctl print "gui/$(id -u)/sh.teeup.emacs" >/dev/null 2>&1; then
    log "Emacs daemon agent already loaded: sh.teeup.emacs"
  else
    launchagent_install sh.teeup.emacs < "$rendered_plist"
    ok "Emacs runs as a daemon at login; emacsclient -t opens a terminal frame, emacsclient -c a window."
  fi
  rm -f "$rendered_plist"
  log "A running daemon keeps its old configuration until: launchctl kickstart -k gui/$(id -u)/sh.teeup.emacs"
fi

# --- git's editor -------------------------------------------------------------
# The git capability writes core.editor = emacsclient -t only when emacsclient
# is on PATH, and git runs in the core tier, before this daily capability has
# installed Emacs. Re-running it here (the way ssh re-runs it once the keys
# exist) makes a first bootstrap end with git opening emacsclient rather than
# vim. A machine where git was never configured, or skips it, has nothing to
# update.
git_generated="$(user_config_dir)/git/teeup-generated"
if have emacsclient && ! cap_skipped git && [[ -f "$git_generated" ]] &&
   ! grep -q 'editor = emacsclient' "$git_generated"; then
  log "Re-running the git configuration so git opens emacsclient."
  cap_run git configure || warn "Could not re-run the git configuration. Run: teeup configure git"
fi
```

```bash file=capabilities/emacs/remove
#!/usr/bin/env bash
# Unload the daemon agent and drop its plist. Your configuration under
# ~/.config/emacs, ~/.config/doom or ~/.emacs.d is yours and stays.
launchagent_remove sh.teeup.emacs
ok "The Emacs daemon no longer starts at login."
```

- [ ] **Step 7: Write the two hooks**

```bash file=capabilities/emacs/theme-apply
#!/usr/bin/env bash
# A running daemon keeps the theme it loaded at startup; teeup-apply (defined
# by the starter layer) re-reads current/theme and current/font. Doom and
# Spacemacs do not define it, so the form is guarded with fboundp and is a
# no-op there. Nothing happens until teeup installed emacs: `teeup theme set`
# runs every capability's hook, and an emacsclient on PATH that teeup did not
# set up is not this hook's to drive. `emacsclient -e t` is the cheapest "is a
# daemon up" probe; `-a false` keeps it a probe, because the zsh layer exports
# an empty ALTERNATE_EDITOR, which would otherwise start a daemon (emacsclient
# Options: -a on the command line takes precedence over the variable).
if ! state_done check "cap-$TEEUP_CAP"; then
  exit 0
fi
if have emacsclient && emacsclient -a false -e t >/dev/null 2>&1; then
  run_cmd emacsclient -a false -e "(when (fboundp 'teeup-apply) (teeup-apply))" ||
    warn "Could not tell the Emacs daemon to reload its theme; it picks the new one up at the next restart."
else
  log "No Emacs daemon is running; the theme is read at the next start."
fi
```

```bash file=capabilities/emacs/font-apply
#!/usr/bin/env bash
# The same reload as theme-apply: teeup-apply re-reads current/font as well as
# current/theme, the fboundp guard keeps Doom and Spacemacs quiet, and
# `-a false` keeps the probe from starting a daemon.
if ! state_done check "cap-$TEEUP_CAP"; then
  exit 0
fi
if have emacsclient && emacsclient -a false -e t >/dev/null 2>&1; then
  run_cmd emacsclient -a false -e "(when (fboundp 'teeup-apply) (teeup-apply))" ||
    warn "Could not tell the Emacs daemon to reload its font; it picks the new one up at the next restart."
else
  log "No Emacs daemon is running; the font is read at the next start."
fi
```

- [ ] **Step 8: Make the scripts executable and put `emacs` in the daily list**

Run: `chmod +x capabilities/emacs/install capabilities/emacs/configure capabilities/emacs/remove capabilities/emacs/theme-apply capabilities/emacs/font-apply`

```text edit-old=capabilities/daily.list
# Daily tier: installed at bootstrap when the answers say TEEUP_DAILY=yes.
# Later phases append: emacs neovim zed vscode chrome obsidian
```

```text edit-new=capabilities/daily.list
# Daily tier: installed at bootstrap when the answers say TEEUP_DAILY=yes.
# Ordered; each entry's requires= must already be satisfied by core.list or
# the entries above it.
emacs
```

- [ ] **Step 9: Run the capability suite**

Run: `bash tests/capabilities/emacs.sh`
Expected: `Summary: 26/26 passed`. On a machine without Emacs the last two tests print `note: no emacs on this machine; skipping the Elisp check (CI's Linux runner runs it).` and pass; with `CI=true` on Linux they fail instead, which is what the CI step in Step 12 prevents.

- [ ] **Step 10: Ask the flavor in the wizard**

```bash edit-old=bootstrap
# wizard runs after step 3. See ask_package_manager.
wizard() {
  local name email work_email theme daily themes pinned_theme ask_theme=true
  echo ""
  echo "A few questions. Answers are saved to $(answers_file) and can be changed later with: ./bootstrap --reconfigure"
  echo ""
```

```bash edit-new=bootstrap
# wizard runs after step 3. See ask_package_manager.
wizard() {
  local name email work_email theme daily themes pinned_theme ask_theme=true
  local flavor="" current_flavor other_flavor flavors pinned_flavor
  echo ""
  echo "A few questions. Answers are saved to $(answers_file) and can be changed later with: ./bootstrap --reconfigure"
  echo ""
```

```bash edit-old=bootstrap
    # shellcheck disable=SC2086  # one option per word is exactly what ui_choose wants
    theme="$(ui_choose "Theme" $themes)"
  fi
  if ui_confirm "Install the daily set too (Emacs, Neovim, Zed, VS Code, Chrome, Obsidian)?" yes; then
    daily=yes
  else
    daily=no
  fi
  answers_set TEEUP_NAME "$name"
  answers_set TEEUP_EMAIL "$email"
  answers_set TEEUP_WORK_EMAIL "$work_email"
  if [[ "$ask_theme" == "true" ]]; then answers_set TEEUP_THEME "$theme"; fi
  answers_set TEEUP_DAILY "$daily"
  answers_load
}

```

```bash edit-new=bootstrap
    # shellcheck disable=SC2086  # one option per word is exactly what ui_choose wants
    theme="$(ui_choose "Theme" $themes)"
  fi
  if ui_confirm "Install the daily set too (Emacs, Zed, Firefox Developer Edition, Obsidian)?" yes; then
    daily=yes
  else
    daily=no
  fi
  # The Emacs flavor only matters when the daily tier (where emacs lives) is
  # on. A pinned value is not asked, for the same reason as the theme. The
  # current answer is offered first, so an empty reply keeps it; on a first
  # run that is teeup's own starter configuration.
  if [[ "$daily" == "yes" ]]; then
    if pinned_flavor="$(machine_get TEEUP_EMACS_FLAVOR)"; then
      log "Emacs flavor is pinned to ${pinned_flavor:-starter} by $(machine_file); not asking."
    else
      current_flavor="$(answers_get TEEUP_EMACS_FLAVOR starter)"
      case "$current_flavor" in
        starter|doom|spacemacs|none) ;;
        *) current_flavor=starter ;;
      esac
      flavors="$current_flavor"
      for other_flavor in starter doom spacemacs none; do
        [[ "$other_flavor" == "$current_flavor" ]] || flavors="$flavors $other_flavor"
      done
      # shellcheck disable=SC2086  # one option per word is exactly what ui_choose wants
      flavor="$(ui_choose "Emacs flavor (starter is teeup's config; none leaves ~/.config/emacs alone)" $flavors)"
    fi
  fi
  answers_set TEEUP_NAME "$name"
  answers_set TEEUP_EMAIL "$email"
  answers_set TEEUP_WORK_EMAIL "$work_email"
  if [[ "$ask_theme" == "true" ]]; then answers_set TEEUP_THEME "$theme"; fi
  answers_set TEEUP_DAILY "$daily"
  if [[ -n "$flavor" ]]; then answers_set TEEUP_EMACS_FLAVOR "$flavor"; fi
  answers_load
}

```

- [ ] **Step 11: Extend `tests/bootstrap.sh`**

The existing `WIZARD_INPUT` stops after the daily confirm; the plain-read `ui_choose` takes end of input as the first option, the current answer (`starter` on a first run), so the existing tests need no new input line. `emacs` and `emacsclient` join `TEEUP_TEST_MISSING`, which keeps `emacs configure` away from `launchctl` and from a host's own Emacs.

```bash edit-old=tests/bootstrap.sh
# Answers piped to the plain-read prompts, one per prompt. The package manager
# is asked first and on its own, before step 2 installs one; the rest is the
# wizard in step 4:
# package manager choice, name, email, work email, theme choice, daily confirm.
# "1" is the detected backend (Homebrew on the mocked modern Mac), "2" the
# other one; for the theme choice, "1" is the first theme themes/ ships, i.e.
# catppuccin.
WIZARD_INPUT=$'1\nAda Lovelace\nada@example.com\n\n1\ny\n'

setup() {
```

```bash edit-new=tests/bootstrap.sh
# Answers piped to the plain-read prompts, one per prompt. The package manager
# is asked first and on its own, before step 2 installs one; the rest is the
# wizard in step 4:
# package manager choice, name, email, work email, theme choice, daily confirm,
# Emacs flavor. "1" is the detected backend (Homebrew on the mocked modern
# Mac), "2" the other one; for the theme choice, "1" is the first theme
# themes/ ships, i.e. catppuccin. The flavor question is asked only after a
# "y" to the daily set, and the plain-read fallback takes an empty answer
# (end of input here) as the first option, starter, so inputs that stop after
# the daily confirm still work.
WIZARD_INPUT=$'1\nAda Lovelace\nada@example.com\n\n1\ny\n'

setup() {
```

```bash edit-old=tests/bootstrap.sh
esac
exit 0
EOF2
  export TEEUP_TEST_MISSING="brew gum jq starship rg fd fzf bat eza zoxide yq btop tldr dust gpg delta git-lfs lazygit"
  export TEEUP_NO_GUM=1
  export DRY_RUN=true
}
```

```bash edit-new=tests/bootstrap.sh
esac
exit 0
EOF2
  # emacs and emacsclient are in the list below because a fresh Mac has
  # neither and a Linux developer machine may have both in /usr/bin: with them
  # hidden, emacs configure skips the daemon agent and never reaches launchctl.
  export TEEUP_TEST_MISSING="brew gum jq starship rg fd fzf bat eza zoxide yq btop tldr dust gpg delta git-lfs lazygit emacs emacsclient"
  export TEEUP_NO_GUM=1
  export DRY_RUN=true
}
```

```bash edit-old=tests/bootstrap.sh
  cleanup_test_env
}

echo "bootstrap"
run_test "refuses non-macOS" test_refuses_non_macos
run_test "refuses root" test_refuses_root
```

```bash edit-new=tests/bootstrap.sh
  cleanup_test_env
}

test_dry_run_walks_the_daily_tier() {
  setup
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")"
  assert_contains "$out" "Completed: emacs install" || return 1
  assert_contains "$out" "Completed: emacs configure" || return 1
  assert_contains "$out" "Would install $TEST_HOME/.config/emacs/init.el" "the default flavor is the starter" || return 1
  cleanup_test_env
}

test_wizard_records_the_emacs_flavor() {
  setup
  # Option 2 after "y" is doom (the current answer, starter, is offered first).
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<$'1\nAda Lovelace\nada@example.com\n\n1\ny\n2\n')"
  assert_contains "$out" "Would set TEEUP_EMACS_FLAVOR" || return 1
  assert_contains "$out" "git clone --depth 1 https://github.com/doomemacs/core $TEST_HOME/.config/emacs" "the answer reached emacs configure in the same run" || return 1
  cleanup_test_env
}

test_wizard_does_not_ask_the_flavor_without_the_daily_tier() {
  setup
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<$'1\nAda Lovelace\nada@example.com\n\n1\nn\n')"
  assert_equals "0" "$(printf '%s\n' "$out" | grep -c 'Emacs flavor')" "the flavor question was asked" || return 1
  assert_not_contains "$out" "Would set TEEUP_EMACS_FLAVOR" || return 1
  cleanup_test_env
}

test_wizard_does_not_ask_for_a_pinned_flavor() {
  setup
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEST_HOME/machines"
  printf 'TEEUP_EMACS_FLAVOR="none"\n' > "$TEST_HOME/machines/testmac.conf"
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")"
  assert_contains "$out" "Emacs flavor is pinned to none by $TEST_HOME/machines/testmac.conf; not asking." || return 1
  assert_not_contains "$out" "Would set TEEUP_EMACS_FLAVOR" || return 1
  assert_contains "$out" "TEEUP_EMACS_FLAVOR=none: leaving your Emacs configuration alone." || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

echo "bootstrap"
run_test "refuses non-macOS" test_refuses_non_macos
run_test "refuses root" test_refuses_root
```

```bash edit-old=tests/bootstrap.sh
run_test "TEEUP_SKIP skips a core capability" test_teeup_skip_skips_a_core_capability
run_test "core failure aborts" test_core_failure_aborts
run_test "dry run answers take effect" test_dry_run_answers_take_effect
print_summary
```

```bash edit-new=tests/bootstrap.sh
run_test "TEEUP_SKIP skips a core capability" test_teeup_skip_skips_a_core_capability
run_test "core failure aborts" test_core_failure_aborts
run_test "dry run answers take effect" test_dry_run_answers_take_effect
run_test "dry run walks the daily tier" test_dry_run_walks_the_daily_tier
run_test "the wizard records the Emacs flavor" test_wizard_records_the_emacs_flavor
run_test "the wizard does not ask the flavor without the daily tier" test_wizard_does_not_ask_the_flavor_without_the_daily_tier
run_test "the wizard does not ask for a pinned flavor" test_wizard_does_not_ask_for_a_pinned_flavor
print_summary
```

Run: `bash tests/bootstrap.sh`
Expected: `Summary: 23/23 passed` (19 before this task, plus 4).

- [ ] **Step 12: Install Emacs on the Linux CI runner**

The Elisp is platform independent and the macOS runners have no Emacs, so one runner is the gate for `starter loads in a real emacs` and `env file paths survive special bytes`.

```yaml edit-old=.github/workflows/ci.yml
          fi
          luac -v

      - name: Shellcheck legacy scripts
        run: shellcheck --severity=warning legacy/teeup.sh legacy/teeup-wizard.sh

```

```yaml edit-new=.github/workflows/ci.yml
          fi
          luac -v

      - name: Install emacs (the emacs suite loads the shipped Elisp; Linux only, the Elisp is platform-independent)
        shell: bash
        run: |
          if [[ "$RUNNER_OS" == "Linux" ]]; then
            sudo apt-get install -y emacs-nox
            emacs --version | head -1
          fi

      - name: Shellcheck legacy scripts
        run: shellcheck --severity=warning legacy/teeup.sh legacy/teeup-wizard.sh

```

- [ ] **Step 13: Full checks and commit**

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning bootstrap capabilities/emacs/install capabilities/emacs/configure capabilities/emacs/remove capabilities/emacs/theme-apply capabilities/emacs/font-apply tests/capabilities/emacs.sh tests/bootstrap.sh
git diff --check
git add bootstrap .github/workflows/ci.yml capabilities/daily.list capabilities/emacs themes/catppuccin tests/capabilities/emacs.sh tests/bootstrap.sh
git commit -m "Add the emacs capability and the Emacs flavor answer"
```

Expected: `commands --check`, shellcheck and `git diff --check` print nothing; `./tests/run.sh` ends with `All N suites passed.` where N is the suite count printed before this task, plus 1.

---

### Task 3: `zed` capability

**Files:**
- Create: `capabilities/zed/{capability,install,configure,theme-apply,font-apply}`, `capabilities/zed/themed/zed.json.tpl`
- Modify: `capabilities/daily.list`, `themes/catppuccin/dark.toml`, `themes/catppuccin/light.toml`
- Test: `tests/capabilities/zed.sh` (new suite)

**Interfaces:**
- Consumes: `json_set_key`, `json_merge_key`, `json_quote` (Task 1); `cask_install`, `casks_supported` (`lib/pkg.sh`); `cap_run_optional` (`lib/capability.sh`); `state_done`; `font_current` (`lib/font.sh`); `TEEUP_THEME_DIR`, `TEEUP_FONT_FAMILY`; the gate of contract 4.
- Produces: contract 5's `zed_theme` and `zed_extension`; `current/theme/<mode>/zed.json` (`{"mode", "theme", "extension"}`); the keys `theme`, `buffer_font_family` and `auto_install_extensions.<extension>` in `~/.config/zed/settings.json`; `zed` as the second line of `daily.list`.

**External facts (verified 2026-09-13):**
- Homebrew cask `zed` 1.19.2: `app "Zed.app"`, `binary "Zed.app/Contents/MacOS/cli"` as `zed`, `auto_updates true`. MacPorts port `zed` 1.18.0 is Brim's data tool (homepage `zed.brimdata.io`), not the editor.
- `crates/paths/src/paths.rs`: `config_dir()` reads `XDG_CONFIG_HOME` only under `target_os = "linux"`/`"freebsd"`; the macOS branch is `home_dir().join(".config").join("zed")`; `settings_file()` is `config_dir().join("settings.json")`.
- `assets/settings/default.json`: `"theme": {"mode": "system", "light": "One Light", "dark": "One Dark"}` with mode `system`, `light` or `dark`; `"buffer_font_family": ".ZedMono"`; terminal `font_family` commented "If this option is not included, the terminal will default to matching the buffer's font family"; `"auto_install_extensions": {"html": true}` ("The extensions that Zed should automatically install on startup"), a map of extension id to bool.
- `catppuccin/zed` `extension.toml`: `id = "catppuccin"`; its theme file names `Catppuccin Latte`, `Catppuccin Frappé`, `Catppuccin Macchiato` and `Catppuccin Mocha`.

**Real-Mac risk:** only a real Zed proves that it (a) installs the `catppuccin` extension on the next start from `auto_install_extensions` and then resolves `Catppuccin Mocha` without a "theme not found" notice, (b) reloads a `settings.json` jq rewrote while it is running, and (c) draws `JetBrainsMono Nerd Font` for `buffer_font_family` (the family name must match what Core Text reports for the cask's font).

- [ ] **Step 1: Write the failing test `tests/capabilities/zed.sh`**

```bash file=tests/capabilities/zed.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# jq is found before setup_test_env narrows PATH and linked into the mock
# bin: the hooks call it by name, and Homebrew's copy is hidden on the macOS
# runners. A machine without jq fails this suite rather than skipping it.
JQ_BIN="$(command -v jq || true)"

setup() {
  setup_test_env
  mock_macos_base
  if [[ -z "$JQ_BIN" ]]; then
    echo "jq is not installed: this suite needs it"
    return 1
  fi
  ln -s "$JQ_BIN" "$MOCK_BIN/jq"
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  TEEUP="$TEEUP_PATH/bin/teeup"
  SETTINGS="$TEST_HOME/.config/zed/settings.json"
}

# mark_installed: what `teeup install zed` records after configure.
mark_installed() {
  mkdir -p "$TEST_HOME/.local/state/teeup/done"
  : > "$TEST_HOME/.local/state/teeup/done/cap-zed"
}

# read_setting <jq filter>: the settings file minus Zed's header comments.
read_setting() { sed '/^[[:space:]]*\/\//d' "$SETTINGS" | jq -r "$1"; }

test_install_dry_run_gets_the_cask() {
  setup || return 1
  local out
  out="$(DRY_RUN=true "$TEEUP" install zed)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask zed" || return 1
  cleanup_test_env
}

test_install_never_takes_the_macports_zed() {
  setup || return 1
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install zed 2>&1)"
  assert_contains "$out" "Zed is a cask and MacPorts has no port of the editor" || return 1
  assert_not_contains "$out" "port install zed" "MacPorts' zed is a different program" || return 1
  cleanup_test_env
}

test_configure_writes_theme_font_and_extension() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  DRY_RUN=false "$TEEUP" configure zed >/dev/null
  assert_file_exists "$SETTINGS" || return 1
  assert_equals "system" "$(read_setting .theme.mode)" || return 1
  assert_equals "Catppuccin Mocha" "$(read_setting .theme.dark)" || return 1
  assert_equals "Catppuccin Latte" "$(read_setting .theme.light)" || return 1
  assert_equals "true" "$(read_setting .auto_install_extensions.catppuccin)" || return 1
  assert_equals "JetBrainsMono Nerd Font" "$(read_setting .buffer_font_family)" || return 1
  cleanup_test_env
}

test_configure_before_a_theme_still_sets_the_font() {
  setup || return 1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure zed 2>&1)"
  assert_contains "$out" "No rendered Zed theme" || return 1
  assert_equals "JetBrainsMono Nerd Font" "$(read_setting .buffer_font_family)" || return 1
  assert_equals "null" "$(read_setting .theme)" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  DRY_RUN=false "$TEEUP" configure zed >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure zed)"
  assert_contains "$out" "Already current: $SETTINGS" || return 1
  assert_not_contains "$out" "Wrote $SETTINGS" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  local out
  out="$(DRY_RUN=true "$TEEUP" configure zed)"
  assert_contains "$out" "[DRY-RUN] Would write $SETTINGS (theme)" || return 1
  assert_contains "$out" "[DRY-RUN] Would write $SETTINGS (buffer_font_family)" || return 1
  [[ ! -e "$SETTINGS" ]] || { echo "settings written in dry run"; return 1; }
  cleanup_test_env
}

# Zed does not read XDG_CONFIG_HOME on macOS, and the settings path has to
# survive a home directory with a space and an ampersand in it.
test_the_path_ignores_xdg_config_home_and_survives_a_space() {
  setup || return 1
  export XDG_CONFIG_HOME="$TEST_HOME/elsewhere"
  export HOME="$TEST_HOME/Ada Lovelace & co"
  mkdir -p "$HOME"
  SETTINGS="$HOME/.config/zed/settings.json"
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  DRY_RUN=false "$TEEUP" configure zed >/dev/null
  assert_equals "Catppuccin Mocha" "$(read_setting .theme.dark)" || return 1
  [[ ! -e "$XDG_CONFIG_HOME/zed" ]] || { echo "wrote under XDG_CONFIG_HOME, which Zed never reads"; return 1; }
  cleanup_test_env
}

test_the_users_settings_and_header_survive() {
  setup || return 1
  mkdir -p "$(dirname "$SETTINGS")"
  cat > "$SETTINGS" <<'EOF2'
// Zed settings
//
// For information on how to configure Zed, see the Zed
// documentation: https://zed.dev/docs/configuring-zed
{
  "ui_font_size": 16,
  "buffer_font_size": 15,
  "theme": "One Dark",
  "auto_install_extensions": {
    "html": true,
  },
}
EOF2
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  DRY_RUN=false "$TEEUP" configure zed >/dev/null
  assert_equals "// Zed settings" "$(head -1 "$SETTINGS")" || return 1
  assert_equals "16" "$(read_setting .ui_font_size)" || return 1
  assert_equals "Catppuccin Mocha" "$(read_setting .theme.dark)" "a string theme is replaced by the object" || return 1
  assert_equals "true" "$(read_setting .auto_install_extensions.html)" "the user's extension stays" || return 1
  assert_equals "true" "$(read_setting .auto_install_extensions.catppuccin)" || return 1
  cleanup_test_env
}

test_hooks_leave_an_uninstalled_zed_alone() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  DRY_RUN=false "$TEEUP" install font Hack >/dev/null
  [[ ! -e "$SETTINGS" ]] || { echo "theme set wrote settings for a Zed teeup never installed"; return 1; }
  cleanup_test_env
}

test_theme_set_and_install_font_update_an_installed_zed() {
  setup || return 1
  mark_installed
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  assert_equals "Catppuccin Latte" "$(read_setting .theme.light)" || return 1
  DRY_RUN=false "$TEEUP" install font Hack >/dev/null
  assert_equals "Hack Nerd Font" "$(read_setting .buffer_font_family)" || return 1
  cleanup_test_env
}

test_an_extension_named_none_is_not_installed() {
  setup || return 1
  local theme="$TEST_HOME/.config/teeup/themes/plain"
  mkdir -p "$theme"
  sed -e 's/^zed_theme = .*/zed_theme = "One Dark"/' -e 's/^zed_extension = .*/zed_extension = "none"/' \
    "$TEEUP_PATH/themes/catppuccin/dark.toml" > "$theme/dark.toml"
  sed -e 's/^zed_theme = .*/zed_theme = "One Light"/' -e 's/^zed_extension = .*/zed_extension = "none"/' \
    "$TEEUP_PATH/themes/catppuccin/light.toml" > "$theme/light.toml"
  DRY_RUN=false "$TEEUP" theme set plain >/dev/null
  DRY_RUN=false "$TEEUP" configure zed >/dev/null
  assert_equals "One Dark" "$(read_setting .theme.dark)" || return 1
  assert_equals "null" "$(read_setting .auto_install_extensions)" || return 1
  cleanup_test_env
}

test_hooks_without_jq_warn_and_continue() {
  setup || return 1
  export TEEUP_TEST_MISSING="jq"
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" configure zed 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "jq is not installed; cannot write $SETTINGS" || return 1
  [[ ! -e "$SETTINGS" ]] || { echo "settings written without jq"; return 1; }
  unset TEEUP_TEST_MISSING
  cleanup_test_env
}

test_theme_renders_the_zed_names() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  local dark light
  dark="$TEST_HOME/.local/state/teeup/current/theme/dark/zed.json"
  light="$TEST_HOME/.local/state/teeup/current/theme/light/zed.json"
  assert_equals "Catppuccin Mocha" "$(jq -r .theme "$dark")" || return 1
  assert_equals "Catppuccin Latte" "$(jq -r .theme "$light")" || return 1
  assert_equals "catppuccin" "$(jq -r .extension "$dark")" || return 1
  cleanup_test_env
}

echo "capabilities/zed"
run_test "install dry run gets the cask" test_install_dry_run_gets_the_cask
run_test "install never takes the MacPorts zed" test_install_never_takes_the_macports_zed
run_test "configure writes theme, font and extension" test_configure_writes_theme_font_and_extension
run_test "configure before a theme still sets the font" test_configure_before_a_theme_still_sets_the_font
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "the path ignores XDG_CONFIG_HOME and survives a space" test_the_path_ignores_xdg_config_home_and_survives_a_space
run_test "the user's settings and header survive" test_the_users_settings_and_header_survive
run_test "hooks leave an uninstalled Zed alone" test_hooks_leave_an_uninstalled_zed_alone
run_test "theme set and install font update an installed Zed" test_theme_set_and_install_font_update_an_installed_zed
run_test "an extension named none is not installed" test_an_extension_named_none_is_not_installed
run_test "hooks without jq warn and continue" test_hooks_without_jq_warn_and_continue
run_test "theme renders the zed names" test_theme_renders_the_zed_names
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/capabilities/zed.sh`
Expected: `Unknown capability: zed` in the failures; `Summary: 1/13 passed` (only `hooks leave an uninstalled Zed alone`, because nothing runs yet).

- [ ] **Step 3: Write the metadata, `install` and `configure`**

```sh file=capabilities/zed/capability
summary="Zed editor, following the teeup theme and font"
group=editors
tier=daily
requires="package-manager cli-tools"
provides=""
packages=""
casks="zed"
apps="Zed"
interactive=false
```

```bash file=capabilities/zed/install
#!/usr/bin/env bash
# Zed is a cask, which also links the `zed` command into the Homebrew bin dir.
# MacPorts has no casks, and its port named `zed` is an unrelated data tool
# (Brim's "super-structured data" CLI), so pkg_install must never be tried
# here: say where to get the editor and let configure carry on.
if casks_supported; then
  cask_install zed
else
  warn "Zed is a cask and MacPorts has no port of the editor; download it from https://zed.dev/download"
fi
```

```bash file=capabilities/zed/configure
#!/usr/bin/env bash
# Zed reads ~/.config/zed/settings.json and applies changes live, so there is
# no shipped file: teeup owns three keys in whatever settings you have (theme,
# buffer_font_family and one entry of auto_install_extensions) and leaves the
# rest alone. configure brings them up to date by running the two hooks
# `teeup theme set` and `teeup install font` run. The hooks do nothing until
# teeup has installed Zed; TEEUP_CONFIGURING tells them this is that install.
export TEEUP_CONFIGURING="$TEEUP_CAP"
cap_run_optional "$TEEUP_CAP" theme-apply
cap_run_optional "$TEEUP_CAP" font-apply
if [[ -d "${TEEUP_APPS_DIR:-/Applications}/Zed.app" ]]; then
  log "Zed is installed; open it with: open -a Zed"
else
  log "Zed.app is not in ${TEEUP_APPS_DIR:-/Applications} yet; the settings are ready for it."
fi
```

- [ ] **Step 4: Write the hooks**

```bash file=capabilities/zed/theme-apply
#!/usr/bin/env bash
# Zed picks a theme by name and follows the system appearance itself when
# `theme` is an object with mode "system", so the rendered files carry names,
# not colours: both modes are read here and written as one object. The theme
# comes from an extension (Catppuccin for the shipped palette), which Zed
# installs on its next start because of auto_install_extensions.
#
# Zed on macOS reads ~/.config/zed whatever XDG_CONFIG_HOME says (its
# paths::config_dir is home_dir/.config/zed on every platform but Linux,
# FreeBSD and Windows), so the path is built from $HOME, not user_config_dir.
#
# `teeup theme set` runs every capability's hook; a settings file for an
# editor teeup did not install is not this hook's to write.
if ! state_done check "cap-$TEEUP_CAP" && [[ "${TEEUP_CONFIGURING:-}" != "$TEEUP_CAP" ]]; then
  exit 0
fi
ZED_SETTINGS="$HOME/.config/zed/settings.json"
THEME_DIR="${TEEUP_THEME_DIR:-$TEEUP_STATE_DIR/current/theme}"
dark="$THEME_DIR/dark/zed.json"
light="$THEME_DIR/light/zed.json"
if [[ ! -f "$dark" || ! -f "$light" ]]; then
  log "No rendered Zed theme in $THEME_DIR yet; the next teeup theme set writes it."
  exit 0
fi
if ! have jq; then
  warn "jq is not installed; cannot write $ZED_SETTINGS. Run: teeup install cli-tools"
  exit 0
fi
dark_theme="$(jq -r .theme "$dark")"
light_theme="$(jq -r .theme "$light")"
json_set_key "$ZED_SETTINGS" theme "$(jq -cn --arg l "$light_theme" --arg d "$dark_theme" '{mode: "system", light: $l, dark: $d}')"
# A palette whose Zed theme is built in names the extension "none".
for ext in $(jq -r .extension "$dark" "$light" | sort -u); do
  if [[ "$ext" == "none" ]]; then
    continue
  fi
  json_merge_key "$ZED_SETTINGS" auto_install_extensions "$(jq -cn --arg e "$ext" '{($e): true}')"
done
```

```bash file=capabilities/zed/font-apply
#!/usr/bin/env bash
# buffer_font_family is the editor font; Zed's terminal uses it too while
# terminal.font_family is unset (Zed's default settings: "If this option is
# not included, the terminal will default to matching the buffer's font
# family"). Same install gate and same ~/.config/zed path as theme-apply.
if ! state_done check "cap-$TEEUP_CAP" && [[ "${TEEUP_CONFIGURING:-}" != "$TEEUP_CAP" ]]; then
  exit 0
fi
ZED_SETTINGS="$HOME/.config/zed/settings.json"
if ! have jq; then
  warn "jq is not installed; cannot write $ZED_SETTINGS. Run: teeup install cli-tools"
  exit 0
fi
json_set_key "$ZED_SETTINGS" buffer_font_family "$(json_quote "${TEEUP_FONT_FAMILY:-$(font_current)}")"
```

- [ ] **Step 5: Write the themed template and add the two name keys to both palettes**

```json file=capabilities/zed/themed/zed.json.tpl
{
  "generated_by": "teeup theme set; do not edit, the next theme switch replaces this file",
  "mode": "{{ mode }}",
  "theme": "{{ zed_theme }}",
  "extension": "{{ zed_extension }}"
}
```

```toml edit-old=themes/catppuccin/dark.toml
# Not colours either: the name each editor knows the closest theme by. Every
# key here must exist in both modes, and a user theme must define them too.
emacs_theme = "modus-vivendi"

accent = "#89b4fa"
selection = "#45475a"
```

```toml edit-new=themes/catppuccin/dark.toml
# Not colours either: the name each editor knows the closest theme by. Every
# key here must exist in both modes, and a user theme must define them too.
emacs_theme = "modus-vivendi"
zed_theme = "Catppuccin Mocha"
zed_extension = "catppuccin"

accent = "#89b4fa"
selection = "#45475a"
```

```toml edit-old=themes/catppuccin/light.toml
# Not colours either: the name each editor knows the closest theme by. Every
# key here must exist in both modes, and a user theme must define them too.
emacs_theme = "modus-operandi"

accent = "#1e66f5"
selection = "#ccd0da"
```

```toml edit-new=themes/catppuccin/light.toml
# Not colours either: the name each editor knows the closest theme by. Every
# key here must exist in both modes, and a user theme must define them too.
emacs_theme = "modus-operandi"
zed_theme = "Catppuccin Latte"
zed_extension = "catppuccin"

accent = "#1e66f5"
selection = "#ccd0da"
```

- [ ] **Step 6: Make the scripts executable and append `zed` to the daily list**

Run: `chmod +x capabilities/zed/install capabilities/zed/configure capabilities/zed/theme-apply capabilities/zed/font-apply`

```text edit-old=capabilities/daily.list
# Ordered; each entry's requires= must already be satisfied by core.list or
# the entries above it.
emacs
```

```text edit-new=capabilities/daily.list
# Ordered; each entry's requires= must already be satisfied by core.list or
# the entries above it.
emacs
zed
```

- [ ] **Step 7: Run the capability suite**

Run: `bash tests/capabilities/zed.sh`
Expected: `Summary: 13/13 passed`.

- [ ] **Step 8: Full checks and commit**

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning capabilities/zed/install capabilities/zed/configure capabilities/zed/theme-apply capabilities/zed/font-apply tests/capabilities/zed.sh
git diff --check
git add capabilities/daily.list capabilities/zed themes/catppuccin tests/capabilities/zed.sh
git commit -m "Add the zed capability"
```

Expected: `commands --check`, shellcheck and `git diff --check` print nothing; `./tests/run.sh` ends with `All N suites passed.` where N is the suite count printed before this task, plus 1. `tests/bootstrap.sh` stays at `Summary: 23/23 passed`: its dry run now also shows `Completed: zed configure`, with the jq warning because the harness hides jq.

---

### Task 4: `firefox-developer-edition`, `obsidian` and `chrome` casks

**Files:**
- Create: `capabilities/firefox-developer-edition/{capability,install,configure}`, `capabilities/obsidian/{capability,install,configure}`, `capabilities/chrome/{capability,install,configure}`
- Modify: `capabilities/daily.list`
- Test: `tests/capabilities/firefox-developer-edition.sh`, `tests/capabilities/obsidian.sh`, `tests/capabilities/chrome.sh` (three new suites), `tests/bootstrap.sh` (one new test)

**Interfaces:**
- Consumes: `cask_install`, `casks_supported`; `TEEUP_APPS_DIR`; `teeup list --tier`.
- Produces: the finished `daily.list` (`emacs zed firefox-developer-edition obsidian`); contract 6's `apps` values `Firefox Developer Edition`, `Obsidian` and `Google Chrome`; `chrome` as a `tier=lazy` capability with no `provides`.

**External facts (verified 2026-09-13):** Homebrew cask `firefox@developer-edition` 156.0b5, `app "Firefox Developer Edition.app"`, `auto_updates true`, no macOS minimum; cask `obsidian` 1.13.7, `app "Obsidian.app"` (and a `binary` `obsidian` link to the bundled `obsidian-cli`), `depends_on macos: >= 12`, `auto_updates true`; cask `google-chrome` 153.0.8010.37, `app "Google Chrome.app"`, `depends_on macos: >= 13`, `auto_updates true`. `ports.macports.org/api/v1/ports/<name>/` returns 404 for `obsidian`, `firefox-developer-edition`, `vscode` and `google-chrome`, and a name search finds no port of the three apps.

**Real-Mac risk:** small. Homebrew refuses `google-chrome` below macOS 13 and `obsidian` below 12; `cask_install` returns that failure, the daily tier warns and continues for Obsidian, and `teeup install chrome` fails with brew's message. Only hardware shows the Gatekeeper prompt on each app's first open.

- [ ] **Step 1: Write the three failing tests**

```bash file=tests/capabilities/firefox-developer-edition.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_dry_run_gets_the_cask() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install firefox-developer-edition)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask firefox@developer-edition" || return 1
  cleanup_test_env
}

test_install_skips_an_installed_cask() {
  setup
  mock_command_script brew <<'EOF2'
case "$1 ${2:-} ${3:-}" in "list --cask firefox@developer-edition") exit 0 ;; list*) exit 1 ;; *) exit 0 ;; esac
EOF2
  local out
  out="$(DRY_RUN=true "$TEEUP" install firefox-developer-edition)"
  assert_contains "$out" "Already installed: firefox@developer-edition (cask)" || return 1
  assert_not_contains "$out" "brew install --cask firefox@developer-edition" || return 1
  cleanup_test_env
}

test_install_warns_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  local rc=0 out
  out="$(DRY_RUN=true "$TEEUP" install firefox-developer-edition 2>&1)" || rc=$?
  assert_success "$rc" "a missing cask must not fail the install" || return 1
  assert_contains "$out" "Firefox Developer Edition is a cask and MacPorts has no port of it" || return 1
  assert_not_contains "$out" "brew install --cask" || return 1
  assert_not_contains "$out" "port install" || return 1
  cleanup_test_env
}

test_configure_reports_the_app() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure firefox-developer-edition)"
  assert_contains "$out" "Firefox Developer Edition.app is not in $TEST_HOME/Applications" || return 1
  mkdir -p "$TEST_HOME/Applications/Firefox Developer Edition.app"
  out="$(DRY_RUN=false "$TEEUP" configure firefox-developer-edition)"
  assert_contains "$out" "Firefox Developer Edition is installed; open it with: open -a 'Firefox Developer Edition'" || return 1
  cleanup_test_env
}

test_configure_runs_no_command() {
  setup
  DRY_RUN=false "$TEEUP" configure firefox-developer-edition >/dev/null || return 1
  # answers_load's hostname lookup is the harness's, not the capability's.
  assert_equals "" "$(grep -v '^hostname' "$MOCK_LOG" || true)" "configure ran a command" || return 1
  [[ ! -e "$TEST_HOME/.config/teeup/answers" ]] || { echo "configure wrote an answer"; return 1; }
  cleanup_test_env
}

test_the_tier_is_daily() {
  setup
  assert_contains "$("$TEEUP" list --tier daily)" "firefox-developer-edition" || return 1
  grep -qx "firefox-developer-edition" "$TEEUP_PATH/capabilities/daily.list" || { echo "firefox-developer-edition is not in daily.list"; return 1; }
  cleanup_test_env
}

echo "capabilities/firefox-developer-edition"
run_test "install dry run gets the cask" test_install_dry_run_gets_the_cask
run_test "install skips an installed cask" test_install_skips_an_installed_cask
run_test "install warns on macports" test_install_warns_on_macports
run_test "configure reports the app" test_configure_reports_the_app
run_test "configure runs no command" test_configure_runs_no_command
run_test "the tier is daily" test_the_tier_is_daily
print_summary
```

```bash file=tests/capabilities/obsidian.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_dry_run_gets_the_cask() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install obsidian)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask obsidian" || return 1
  cleanup_test_env
}

test_install_skips_an_installed_cask() {
  setup
  mock_command_script brew <<'EOF2'
case "$1 ${2:-} ${3:-}" in "list --cask obsidian") exit 0 ;; list*) exit 1 ;; *) exit 0 ;; esac
EOF2
  local out
  out="$(DRY_RUN=true "$TEEUP" install obsidian)"
  assert_contains "$out" "Already installed: obsidian (cask)" || return 1
  assert_not_contains "$out" "brew install --cask obsidian" || return 1
  cleanup_test_env
}

test_install_warns_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  local rc=0 out
  out="$(DRY_RUN=true "$TEEUP" install obsidian 2>&1)" || rc=$?
  assert_success "$rc" "a missing cask must not fail the install" || return 1
  assert_contains "$out" "Obsidian is a cask and MacPorts has no port of it" || return 1
  assert_not_contains "$out" "brew install --cask" || return 1
  assert_not_contains "$out" "port install" || return 1
  cleanup_test_env
}

test_configure_reports_the_app() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure obsidian)"
  assert_contains "$out" "Obsidian.app is not in $TEST_HOME/Applications" || return 1
  mkdir -p "$TEST_HOME/Applications/Obsidian.app"
  out="$(DRY_RUN=false "$TEEUP" configure obsidian)"
  assert_contains "$out" "Obsidian is installed; open it with: open -a 'Obsidian'" || return 1
  cleanup_test_env
}

test_configure_runs_no_command() {
  setup
  DRY_RUN=false "$TEEUP" configure obsidian >/dev/null || return 1
  # answers_load's hostname lookup is the harness's, not the capability's.
  assert_equals "" "$(grep -v '^hostname' "$MOCK_LOG" || true)" "configure ran a command" || return 1
  [[ ! -e "$TEST_HOME/.config/teeup/answers" ]] || { echo "configure wrote an answer"; return 1; }
  cleanup_test_env
}

test_the_tier_is_daily() {
  setup
  assert_contains "$("$TEEUP" list --tier daily)" "obsidian" || return 1
  grep -qx "obsidian" "$TEEUP_PATH/capabilities/daily.list" || { echo "obsidian is not in daily.list"; return 1; }
  cleanup_test_env
}

echo "capabilities/obsidian"
run_test "install dry run gets the cask" test_install_dry_run_gets_the_cask
run_test "install skips an installed cask" test_install_skips_an_installed_cask
run_test "install warns on macports" test_install_warns_on_macports
run_test "configure reports the app" test_configure_reports_the_app
run_test "configure runs no command" test_configure_runs_no_command
run_test "the tier is daily" test_the_tier_is_daily
print_summary
```

```bash file=tests/capabilities/chrome.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_dry_run_gets_the_cask() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install chrome)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask google-chrome" || return 1
  cleanup_test_env
}

test_install_skips_an_installed_cask() {
  setup
  mock_command_script brew <<'EOF2'
case "$1 ${2:-} ${3:-}" in "list --cask google-chrome") exit 0 ;; list*) exit 1 ;; *) exit 0 ;; esac
EOF2
  local out
  out="$(DRY_RUN=true "$TEEUP" install chrome)"
  assert_contains "$out" "Already installed: google-chrome (cask)" || return 1
  assert_not_contains "$out" "brew install --cask google-chrome" || return 1
  cleanup_test_env
}

test_install_warns_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  local rc=0 out
  out="$(DRY_RUN=true "$TEEUP" install chrome 2>&1)" || rc=$?
  assert_success "$rc" "a missing cask must not fail the install" || return 1
  assert_contains "$out" "Google Chrome is a cask and MacPorts has no port of it" || return 1
  assert_not_contains "$out" "brew install --cask" || return 1
  assert_not_contains "$out" "port install" || return 1
  cleanup_test_env
}

test_configure_reports_the_app() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure chrome)"
  assert_contains "$out" "Google Chrome.app is not in $TEST_HOME/Applications" || return 1
  mkdir -p "$TEST_HOME/Applications/Google Chrome.app"
  out="$(DRY_RUN=false "$TEEUP" configure chrome)"
  assert_contains "$out" "Google Chrome is installed; open it with: open -a 'Google Chrome'" || return 1
  cleanup_test_env
}

test_configure_runs_no_command() {
  setup
  DRY_RUN=false "$TEEUP" configure chrome >/dev/null || return 1
  # answers_load's hostname lookup is the harness's, not the capability's.
  assert_equals "" "$(grep -v '^hostname' "$MOCK_LOG" || true)" "configure ran a command" || return 1
  [[ ! -e "$TEST_HOME/.config/teeup/answers" ]] || { echo "configure wrote an answer"; return 1; }
  cleanup_test_env
}

test_the_tier_is_lazy() {
  setup
  assert_contains "$("$TEEUP" list --tier lazy)" "chrome" || return 1
  if grep -qx "chrome" "$TEEUP_PATH/capabilities/daily.list" "$TEEUP_PATH/capabilities/core.list"; then
    echo "chrome is lazy but sits in a tier list"
    return 1
  fi
  cleanup_test_env
}

echo "capabilities/chrome"
run_test "install dry run gets the cask" test_install_dry_run_gets_the_cask
run_test "install skips an installed cask" test_install_skips_an_installed_cask
run_test "install warns on macports" test_install_warns_on_macports
run_test "configure reports the app" test_configure_reports_the_app
run_test "configure runs no command" test_configure_runs_no_command
run_test "the tier is lazy" test_the_tier_is_lazy
print_summary
```

- [ ] **Step 2: Run them to see them fail**

Run: `for c in firefox-developer-edition obsidian chrome; do bash tests/capabilities/$c.sh; done`
Expected: `Unknown capability: <name>` in the failures; `Summary: 0/6 passed` three times.

- [ ] **Step 3: Write `firefox-developer-edition`**

```sh file=capabilities/firefox-developer-edition/capability
summary="Firefox Developer Edition, the daily browser"
group=apps
tier=daily
requires="package-manager"
provides=""
packages=""
casks="firefox@developer-edition"
apps="Firefox Developer Edition"
interactive=false
```

```bash file=capabilities/firefox-developer-edition/install
#!/usr/bin/env bash
# Homebrew's token is firefox@developer-edition (the versioned Firefox casks
# live in the main tap under @-suffixed names). The cask updates itself
# (auto_updates), so brew never fights the browser's own updater. MacPorts
# has no casks and no port of the browser.
if casks_supported; then
  cask_install firefox@developer-edition
else
  warn "Firefox Developer Edition is a cask and MacPorts has no port of it; download it from https://www.mozilla.org/firefox/developer/"
fi
```

```bash file=capabilities/firefox-developer-edition/configure
#!/usr/bin/env bash
# Firefox keeps its settings in a profile it creates on the first start and
# syncs them through a Mozilla account, so there is nothing to ship. The
# script records that decision, and says whether the app is in place.
app="Firefox Developer Edition"
if [[ -d "${TEEUP_APPS_DIR:-/Applications}/$app.app" ]]; then
  log "$app is installed; open it with: open -a '$app'"
else
  log "$app.app is not in ${TEEUP_APPS_DIR:-/Applications}; the install step above says why."
fi
```

- [ ] **Step 4: Write `obsidian`**

```sh file=capabilities/obsidian/capability
summary="Obsidian notes"
group=apps
tier=daily
requires="package-manager"
provides=""
packages=""
casks="obsidian"
apps="Obsidian"
interactive=false
```

```bash file=capabilities/obsidian/install
#!/usr/bin/env bash
# Obsidian is a cask (macOS 12 or later) that updates itself. MacPorts has no
# casks and no port of it.
if casks_supported; then
  cask_install obsidian
else
  warn "Obsidian is a cask and MacPorts has no port of it; download it from https://obsidian.md/download"
fi
```

```bash file=capabilities/obsidian/configure
#!/usr/bin/env bash
# Vaults are folders you pick, and Obsidian keeps its settings inside each
# vault, so there is nothing to ship. The script records that decision, and
# says whether the app is in place.
app="Obsidian"
if [[ -d "${TEEUP_APPS_DIR:-/Applications}/$app.app" ]]; then
  log "$app is installed; open it with: open -a '$app'"
else
  log "$app.app is not in ${TEEUP_APPS_DIR:-/Applications}; the install step above says why."
fi
```

- [ ] **Step 5: Write `chrome`**

```sh file=capabilities/chrome/capability
summary="Google Chrome, installed when you first ask for it"
group=apps
tier=lazy
requires="package-manager"
provides=""
packages=""
casks="google-chrome"
apps="Google Chrome"
interactive=false
```

```bash file=capabilities/chrome/install
#!/usr/bin/env bash
# Chrome is a cask (macOS 13 or later) that updates itself. It is lazy:
# nothing runs at bootstrap, and `teeup install chrome` brings it in. It has
# no command to shim, so apps= is how the launcher finds it. MacPorts has no
# casks and no port of it.
if casks_supported; then
  cask_install google-chrome
else
  warn "Google Chrome is a cask and MacPorts has no port of it; download it from https://www.google.com/chrome/"
fi
```

```bash file=capabilities/chrome/configure
#!/usr/bin/env bash
# Chrome syncs its settings through a Google account, so there is nothing to
# ship. The script records that decision, and says whether the app is in
# place.
app="Google Chrome"
if [[ -d "${TEEUP_APPS_DIR:-/Applications}/$app.app" ]]; then
  log "$app is installed; open it with: open -a '$app'"
else
  log "$app.app is not in ${TEEUP_APPS_DIR:-/Applications}; the install step above says why."
fi
```

- [ ] **Step 6: Make the scripts executable and finish the daily list**

Run: `chmod +x capabilities/firefox-developer-edition/install capabilities/firefox-developer-edition/configure capabilities/obsidian/install capabilities/obsidian/configure capabilities/chrome/install capabilities/chrome/configure`

```text edit-old=capabilities/daily.list
# the entries above it.
emacs
zed
```

```text edit-new=capabilities/daily.list
# the entries above it.
emacs
zed
firefox-developer-edition
obsidian
```

- [ ] **Step 7: Run the three suites**

Run: `for c in firefox-developer-edition obsidian chrome; do bash tests/capabilities/$c.sh; done`
Expected: `Summary: 6/6 passed` three times.

- [ ] **Step 8: Prove the bootstrap order**

The three lazy names are checked through their `install` lines: `neovim` and `vscode` do not exist until Tasks 5 and 6, and from then on their `theme-apply` runs during the core tier's theme step, so `Starting: neovim` alone would match that.

```bash edit-old=tests/bootstrap.sh
  cleanup_test_env
}

test_wizard_records_the_emacs_flavor() {
  setup
  # Option 2 after "y" is doom (the current answer, starter, is offered first).
```

```bash edit-new=tests/bootstrap.sh
  cleanup_test_env
}

test_dry_run_walks_the_daily_tier_in_order() {
  setup
  local out e z f o
  out="$("$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")"
  e="$(printf '%s\n' "$out" | grep -n 'Completed: emacs configure' | head -1 | cut -d: -f1)"
  z="$(printf '%s\n' "$out" | grep -n 'Completed: zed configure' | head -1 | cut -d: -f1)"
  f="$(printf '%s\n' "$out" | grep -n 'Completed: firefox-developer-edition configure' | head -1 | cut -d: -f1)"
  o="$(printf '%s\n' "$out" | grep -n 'Completed: obsidian configure' | head -1 | cut -d: -f1)"
  [[ -n "$e" && -n "$z" && -n "$f" && -n "$o" ]] || { echo "a daily capability did not complete:"; printf '%s\n' "$out"; return 1; }
  [[ "$e" -lt "$z" && "$z" -lt "$f" && "$f" -lt "$o" ]] || { echo "the daily tier ran out of order"; return 1; }
  assert_not_contains "$out" "Starting: chrome install" "chrome is lazy" || return 1
  assert_not_contains "$out" "Starting: neovim install" "neovim is lazy" || return 1
  assert_not_contains "$out" "Starting: vscode install" "vscode is lazy" || return 1
  cleanup_test_env
}

test_wizard_records_the_emacs_flavor() {
  setup
  # Option 2 after "y" is doom (the current answer, starter, is offered first).
```

```bash edit-old=tests/bootstrap.sh
run_test "core failure aborts" test_core_failure_aborts
run_test "dry run answers take effect" test_dry_run_answers_take_effect
run_test "dry run walks the daily tier" test_dry_run_walks_the_daily_tier
run_test "the wizard records the Emacs flavor" test_wizard_records_the_emacs_flavor
run_test "the wizard does not ask the flavor without the daily tier" test_wizard_does_not_ask_the_flavor_without_the_daily_tier
run_test "the wizard does not ask for a pinned flavor" test_wizard_does_not_ask_for_a_pinned_flavor
```

```bash edit-new=tests/bootstrap.sh
run_test "core failure aborts" test_core_failure_aborts
run_test "dry run answers take effect" test_dry_run_answers_take_effect
run_test "dry run walks the daily tier" test_dry_run_walks_the_daily_tier
run_test "dry run walks the daily tier in order" test_dry_run_walks_the_daily_tier_in_order
run_test "the wizard records the Emacs flavor" test_wizard_records_the_emacs_flavor
run_test "the wizard does not ask the flavor without the daily tier" test_wizard_does_not_ask_the_flavor_without_the_daily_tier
run_test "the wizard does not ask for a pinned flavor" test_wizard_does_not_ask_for_a_pinned_flavor
```

Run: `bash tests/bootstrap.sh`
Expected: `Summary: 24/24 passed`.

- [ ] **Step 9: Full checks and commit**

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning capabilities/firefox-developer-edition/install capabilities/firefox-developer-edition/configure capabilities/obsidian/install capabilities/obsidian/configure capabilities/chrome/install capabilities/chrome/configure tests/capabilities/firefox-developer-edition.sh tests/capabilities/obsidian.sh tests/capabilities/chrome.sh tests/bootstrap.sh
git diff --check
git add capabilities/daily.list capabilities/firefox-developer-edition capabilities/obsidian capabilities/chrome tests/capabilities/firefox-developer-edition.sh tests/capabilities/obsidian.sh tests/capabilities/chrome.sh tests/bootstrap.sh
git commit -m "Add the firefox-developer-edition, obsidian and chrome casks"
```

Expected: `commands --check`, shellcheck and `git diff --check` print nothing; `./tests/run.sh` ends with `All N suites passed.` where N is the suite count printed before this task, plus 3.

---

### Task 5: `neovim` capability with the LazyVim starter

**Files:**
- Create: `capabilities/neovim/{capability,install,configure,theme-apply,font-apply}`, `capabilities/neovim/config/nvim/{init.lua,stylua.toml}`, `capabilities/neovim/config/nvim/lua/config/{lazy.lua,options.lua,keymaps.lua,autocmds.lua}`, `capabilities/neovim/config/nvim/lua/plugins/local.lua`, `capabilities/neovim/default/teeup/neovim.lua`, `capabilities/neovim/themed/neovim.lua.tpl`
- Modify: `themes/catppuccin/dark.toml`, `themes/catppuccin/light.toml`
- Test: `tests/capabilities/neovim.sh` (new suite)

**Interfaces:**
- Consumes: `pkg_install` (`lib/pkg.sh`); `copy_config_once`; `state_done`; `user_config_dir`, `have`, `run_cmd`; the theme and font state files; `~/.config/teeup/env` as `teeup-runtime` writes it (`export KEY=<printf %q value>`).
- Produces: contract 5's `neovim_colorscheme`; contract 6's `neovim` metadata (`tier=lazy`, `provides="nvim"`); the Lua module `teeup.neovim` with `M.mode()`, `M.theme(mode)`, `M.font_family()`, `M.colorscheme()`, `M.plugin_for(name)`, `M.load()`, `M.apply_font()`, `M.apply()` and `M.specs()`; `current/theme/<mode>/neovim.lua` (a table with `mode`, `colorscheme` and `colors`).

**External facts (verified 2026-09-13):**
- Homebrew formula `neovim` 0.12.5 installs `nvim`; MacPorts port `neovim` 0.12.4.
- `LazyVim/starter` tree: `.gitignore`, `.neoconf.json`, `LICENSE`, `README.md`, `init.lua` (`require("config.lazy")`), `stylua.toml`, `lua/config/{autocmds,keymaps,lazy,options}.lua`, `lua/plugins/example.lua`; `lua/config/lazy.lua` clones `https://github.com/folke/lazy.nvim.git` with `--filter=blob:none --branch=stable` into `stdpath("data") .. "/lazy/lazy.nvim"` and sets up `{ "LazyVim/LazyVim", import = "lazyvim.plugins" }, { import = "plugins" }` with `install = { colorscheme = { "tokyonight", "habamax" } }`.
- `LazyVim/LazyVim` `lua/lazyvim/plugins/colorscheme.lua` includes `{ "catppuccin/nvim", lazy = true, name = "catppuccin" }`; `catppuccin/nvim` ships `colors/catppuccin-mocha.lua` and `colors/catppuccin-latte.lua`. LazyVim's README and `lua/lazyvim/plugins/init.lua` require Neovim 0.11.2 or later.
- Neovim v0.12.5 `src/nvim/msgpack_rpc/server.c` names the default socket `<dir>/nvim.<pid>.<n>` from `stdpaths_get_xdg_var(kXDGRuntimeDir)`, which is `$XDG_RUNTIME_DIR` when set and otherwise `vim_gettempdir()`, a private `nvim.<user>/<random>` directory under `$TMPDIR` or `/tmp`; `runtime/doc/remote.txt` documents `--server {addr}` and `--remote-send {keys}`. Run locally against Neovim 0.12.5: a headless instance with `XDG_RUNTIME_DIR` set listened on `$XDG_RUNTIME_DIR/nvim.<pid>.0`, one without it on `$TMPDIR/nvim.<user>/<random>/nvim.<pid>.0`, and `--remote-send '<Cmd>lua vim.g.teeup_probe = "ok"<CR>'` set the variable in both. With both `init.lua` and `init.vim` present, Neovim 0.12.5 printed `E5422: Conflicting configs` and loaded `init.lua`.

**Real-Mac risk:** only a Mac with network proves the first `nvim` start: lazy.nvim clones, LazyVim installs its plugins, `catppuccin-mocha` loads (or `catppuccin-latte` with `TEEUP_APPEARANCE=light`), and `:LazyHealth` is clean with the `ripgrep`, `fd` and `fzf` that `cli-tools` provides. `$TMPDIR` on macOS is the per-user `/var/folders/.../T/`, so the socket loop's second pattern is the one that matters there; a GUI such as Neovide is the only place `guifont` shows.

- [ ] **Step 1: Write the failing test `tests/capabilities/neovim.sh`**

```bash file=tests/capabilities/neovim.sh
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
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/capabilities/neovim.sh`
Expected: `Unknown capability: neovim` in most failures; `Summary: 1/14 passed` (only `hooks leave a Neovim teeup did not install alone`).

- [ ] **Step 3: Write the metadata and `install`**

```sh file=capabilities/neovim/capability
summary="Neovim with LazyVim, following the teeup theme"
group=editors
tier=lazy
requires="package-manager git cli-tools"
provides="nvim"
packages="neovim"
casks=""
apps=""
interactive=false
```

```bash file=capabilities/neovim/install
#!/usr/bin/env bash
# The formula and the port are both called neovim and both install `nvim`.
# LazyVim wants git (partial clones), ripgrep, fd and fzf, which the git and
# cli-tools capabilities this one requires already provide; lazy.nvim and the
# plugins are cloned by Neovim itself on the first start.
pkg_install neovim nvim || die "Neovim could not be installed."
```

- [ ] **Step 4: Write the starter layout**

```lua file=capabilities/neovim/config/nvim/init.lua
-- ~/.config/nvim/init.lua - yours. teeup installed it once and will not
-- overwrite it. It is the LazyVim starter's init.lua plus the lines that find
-- the teeup checkout and put its Neovim layer on package.path; the thick layer
-- itself (capabilities/neovim/default/teeup/neovim.lua) lives in the checkout
-- and is upgraded by `teeup update`. Your plugins go in lua/plugins/.

-- A shell exports TEEUP_PATH and TEEUP_STATE_DIR (the zsh layer sources
-- ~/.config/teeup/env), so Neovim started from a terminal has both. Started
-- any other way it reads that env file itself. teeup-runtime writes every
-- value through bash's `printf %q`, which produces a backslash-escaped word
-- for plain paths and ANSI-C `$'...'` quoting (octal byte escapes) for
-- non-ASCII ones; unescape_word undoes both, byte by byte, the way the shell
-- reassembles a word.
local home = os.getenv("HOME") or ""

local function unescape_word(s)
  local out, i, n = {}, 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c == "'" then
      local j = s:find("'", i + 1, true)
      if not j then return nil end
      out[#out + 1] = s:sub(i + 1, j - 1)
      i = j + 1
    elseif c == '"' then
      local j, buf, closed = i + 1, {}, false
      while j <= n do
        local cj = s:sub(j, j)
        if cj == '"' then closed = true; break end
        local nx = s:sub(j + 1, j + 1)
        if cj == "\\" and (nx == "$" or nx == "`" or nx == '"' or nx == "\\" or nx == "\n") then
          buf[#buf + 1] = nx; j = j + 2
        else
          buf[#buf + 1] = cj; j = j + 1
        end
      end
      if not closed then return nil end
      out[#out + 1] = table.concat(buf)
      i = j + 1
    elseif c == "$" and s:sub(i + 1, i + 1) == "'" then
      local j, buf, closed = i + 2, {}, false
      local simple = { a = "\a", b = "\b", e = "\27", E = "\27", f = "\f", n = "\n", r = "\r", t = "\t", v = "\v" }
      while j <= n do
        local cj = s:sub(j, j)
        if cj == "'" then closed = true; break end
        if cj == "\\" then
          local nx = s:sub(j + 1, j + 1)
          local oct = s:sub(j + 1, j + 3):match("^[0-7][0-7]?[0-7]?")
          local hex = nx == "x" and s:sub(j + 2, j + 3):match("^%x%x?")
          if oct then
            buf[#buf + 1] = string.char(tonumber(oct, 8) % 256); j = j + 1 + #oct
          elseif hex then
            buf[#buf + 1] = string.char(tonumber(hex, 16)); j = j + 2 + #hex
          elseif simple[nx] then
            buf[#buf + 1] = simple[nx]; j = j + 2
          elseif nx == "" then
            return nil
          else
            buf[#buf + 1] = nx; j = j + 2
          end
        else
          buf[#buf + 1] = cj; j = j + 1
        end
      end
      if not closed then return nil end
      out[#out + 1] = table.concat(buf)
      i = j + 1
    elseif c == "\\" then
      local nx = s:sub(i + 1, i + 1)
      if nx == "" then return nil end
      out[#out + 1] = nx
      i = i + 2
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

local config_home = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
local env_file = config_home .. "/teeup/env"

local function env_or_file(key, fallback)
  local from_env = os.getenv(key)
  if from_env and from_env ~= "" then
    return from_env
  end
  local f = io.open(env_file, "r")
  if f then
    local pattern = "^export " .. key .. "=(.+)$"
    for line in f:lines() do
      local value = line:match(pattern)
      if value and value ~= "" then
        f:close()
        return unescape_word(value) or fallback
      end
    end
    f:close()
  end
  return fallback
end

local state_home = os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")
local teeup_root = env_or_file("TEEUP_PATH", home .. "/.local/share/teeup")
local teeup_state = env_or_file("TEEUP_STATE_DIR", state_home .. "/teeup")

-- Three tiers, highest priority first: generated theme files, your own
-- lua/ directory, then teeup's default layer. The user tier is on the
-- runtimepath already; naming it here keeps the order explicit.
package.path = table.concat({
  teeup_state .. "/current/theme/?.lua",
  config_home .. "/nvim/lua/?.lua",
  teeup_root .. "/capabilities/neovim/default/?.lua",
}, ";") .. ";" .. package.path

-- vim is nil under a plain Lua interpreter (the test harness); Neovim's
-- globals only exist from here on.
if vim then
  vim.g.teeup_path = teeup_root
  vim.g.teeup_state_dir = teeup_state
  -- bootstrap lazy.nvim, LazyVim and your plugins
  require("config.lazy")
end
```

```toml file=capabilities/neovim/config/nvim/stylua.toml
indent_type = "Spaces"
indent_width = 2
column_width = 120
```

```lua file=capabilities/neovim/config/nvim/lua/config/lazy.lua
-- lua/config/lazy.lua - the LazyVim starter's bootstrap, plus teeup's specs.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- teeup's layer: the colorscheme `teeup theme set` chose (and the plugin that
-- provides it) and the GUI font from `teeup install font`. pcall, so Neovim
-- still starts when the checkout cannot be found; the notice says where to
-- look.
local teeup_specs = {}
local ok, teeup = pcall(require, "teeup.neovim")
if ok then
  teeup_specs = teeup.specs()
else
  vim.schedule(function()
    vim.notify(
      "teeup: could not load teeup.neovim (" .. tostring(teeup) .. "); set TEEUP_PATH or run: teeup configure teeup-runtime",
      vim.log.levels.WARN
    )
  end)
end

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- teeup: colorscheme and font (a nested list is a valid spec)
    teeup_specs,
    -- import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  install = { colorscheme = { "catppuccin", "tokyonight", "habamax" } },
  checker = {
    enabled = true, -- check for plugin updates periodically
    notify = false, -- notify on update
  }, -- automatically check for plugin updates
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
```

```lua file=capabilities/neovim/config/nvim/lua/config/options.lua
-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
```

```lua file=capabilities/neovim/config/nvim/lua/config/keymaps.lua
-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
```

```lua file=capabilities/neovim/config/nvim/lua/config/autocmds.lua
-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")
```

```lua file=capabilities/neovim/config/nvim/lua/plugins/local.lua
-- lua/plugins/local.lua - your plugin specs. Every file in this directory is
-- loaded by lazy.nvim; this one ships empty. Add plugins, disable LazyVim
-- ones, or override their options here, for example:
--
-- return {
--   { "tpope/vim-fugitive" },
--   { "folke/flash.nvim", enabled = false },
-- }
--
-- The colorscheme is chosen by `teeup theme set`; to pin your own, override
-- it here with { "LazyVim/LazyVim", opts = { colorscheme = "gruvbox" } }.
return {}
```

- [ ] **Step 5: Write teeup's layer and the themed template, and add `neovim_colorscheme` to both palettes**

```lua file=capabilities/neovim/default/teeup/neovim.lua
-- teeup's Neovim layer, required by the thin ~/.config/nvim/init.lua through
-- lua/config/lazy.lua. This file is teeup's: edit it in the checkout, not in
-- your home directory.
--
-- What it does: read the colorscheme name `teeup theme set` rendered for the
-- current appearance, hand lazy.nvim the plugin that provides it, and set the
-- GUI font from `teeup install font`. M.apply() redoes both at runtime; the
-- theme-apply and font-apply hooks call it in every running instance.

local M = {}

local DEFAULT_FONT = "JetBrainsMono Nerd Font"
local DEFAULT_COLORSCHEME = "tokyonight"

local function state_dir()
  if vim.g.teeup_state_dir and vim.g.teeup_state_dir ~= "" then
    return vim.g.teeup_state_dir
  end
  local state_home = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
  return state_home .. "/teeup"
end

local function read_first_line(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local line = f:read("*l")
  f:close()
  if not line then
    return nil
  end
  line = line:gsub("^%s+", ""):gsub("%s+$", "")
  if line == "" then
    return nil
  end
  return line
end

-- dark or light. A shell exports TEEUP_APPEARANCE (the zsh layer reads
-- AppleInterfaceStyle at shell start); without it, 'background', which
-- Neovim sets from the terminal's own colours.
function M.mode()
  local env = os.getenv("TEEUP_APPEARANCE")
  if env == "dark" or env == "light" then
    return env
  end
  if vim.o.background == "light" then
    return "light"
  end
  return "dark"
end

-- The rendered palette for one mode: { mode, colorscheme, colors }, or nil
-- before the first `teeup theme set`.
function M.theme(mode)
  local path = state_dir() .. "/current/theme/" .. (mode or M.mode()) .. "/neovim.lua"
  local ok, theme = pcall(dofile, path)
  if ok and type(theme) == "table" then
    return theme
  end
  return nil
end

function M.font_family()
  return read_first_line(state_dir() .. "/current/font") or DEFAULT_FONT
end

-- Which plugin provides a colorscheme, keyed on the name's first run of
-- %w characters (letters and digits; %w does not include "-"): teeup's
-- palettes name colorschemes ("catppuccin-mocha"), not repositories. LazyVim
-- already ships catppuccin and tokyonight; the rest are added on demand. A
-- name not listed here is still tried (a plugin you added yourself may
-- provide it), and LazyVim falls back to habamax with a message if not.
-- "rose-pine", "rose-pine-moon" and "rose-pine-dawn" all key on "rose" (I3:
-- a key of "rosepine" could never match, since the hyphen stops %w's run
-- before "pine").
M.colorscheme_plugins = {
  catppuccin = { "catppuccin/nvim", name = "catppuccin" },
  tokyonight = { "folke/tokyonight.nvim" },
  gruvbox = { "ellisonleao/gruvbox.nvim" },
  nord = { "shaunsingh/nord.nvim" },
  kanagawa = { "rebelot/kanagawa.nvim" },
  everforest = { "neanias/everforest-nvim" },
  rose = { "rose-pine/neovim", name = "rose-pine" },
}

function M.plugin_for(colorscheme)
  local key = (colorscheme or ""):match("^([%w]+)")
  if key then
    return M.colorscheme_plugins[key]
  end
  return nil
end

function M.colorscheme()
  local theme = M.theme()
  if theme and type(theme.colorscheme) == "string" and theme.colorscheme ~= "" then
    return theme.colorscheme
  end
  return DEFAULT_COLORSCHEME
end

-- Load the colorscheme for the current mode. Errors propagate on purpose:
-- LazyVim wraps its colorscheme call and falls back to habamax with a message.
function M.load()
  vim.o.background = M.mode()
  vim.cmd.colorscheme(M.colorscheme())
end

function M.apply_font()
  vim.o.guifont = M.font_family() .. ":h14"
end

-- Runtime reload, from the hooks: never raises.
function M.apply()
  local ok, err = pcall(M.load)
  if not ok then
    vim.notify("teeup: could not load colorscheme " .. M.colorscheme() .. ": " .. tostring(err), vim.log.levels.WARN)
  end
  M.apply_font()
end

-- lazy.nvim specs for lua/config/lazy.lua.
function M.specs()
  local specs = {}
  local plugin = M.plugin_for(M.colorscheme())
  if plugin then
    table.insert(specs, plugin)
  end
  table.insert(specs, {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        M.load()
        M.apply_font()
      end,
    },
  })
  return specs
end

return M
```

```lua file=capabilities/neovim/themed/neovim.lua.tpl
-- Generated by `teeup theme set`. Do not edit; the next theme switch replaces
-- it. Read by capabilities/neovim/default/teeup/neovim.lua for the {{ mode }}
-- appearance: the colorscheme to load, and the palette for your own
-- highlights (require("teeup.neovim").theme().colors.accent).
return {
  mode = "{{ mode }}",
  colorscheme = "{{ neovim_colorscheme }}",
  colors = {
    accent = "{{ accent }}",
    selection = "{{ selection }}",
    muted = "{{ muted }}",
    background = "{{ background }}",
    dark_background = "{{ dark_background }}",
    lighter_background = "{{ lighter_background }}",
    foreground = "{{ foreground }}",
    light_foreground = "{{ light_foreground }}",
    bright_foreground = "{{ bright_foreground }}",
    red = "{{ red }}",
    orange = "{{ orange }}",
    yellow = "{{ yellow }}",
    green = "{{ green }}",
    cyan = "{{ cyan }}",
    blue = "{{ blue }}",
    magenta = "{{ magenta }}",
  },
}
```

```toml edit-old=themes/catppuccin/dark.toml
emacs_theme = "modus-vivendi"
zed_theme = "Catppuccin Mocha"
zed_extension = "catppuccin"

accent = "#89b4fa"
selection = "#45475a"
```

```toml edit-new=themes/catppuccin/dark.toml
emacs_theme = "modus-vivendi"
zed_theme = "Catppuccin Mocha"
zed_extension = "catppuccin"
neovim_colorscheme = "catppuccin-mocha"

accent = "#89b4fa"
selection = "#45475a"
```

```toml edit-old=themes/catppuccin/light.toml
emacs_theme = "modus-operandi"
zed_theme = "Catppuccin Latte"
zed_extension = "catppuccin"

accent = "#1e66f5"
selection = "#ccd0da"
```

```toml edit-new=themes/catppuccin/light.toml
emacs_theme = "modus-operandi"
zed_theme = "Catppuccin Latte"
zed_extension = "catppuccin"
neovim_colorscheme = "catppuccin-latte"

accent = "#1e66f5"
selection = "#ccd0da"
```

- [ ] **Step 6: Write `configure` and the hooks**

```bash file=capabilities/neovim/configure
#!/usr/bin/env bash
# The LazyVim starter layout, shipped file by file and copied once: every file
# under ~/.config/nvim is the user's from then on. The thin init.lua adds the
# teeup layer (capabilities/neovim/default/teeup/neovim.lua) to package.path;
# that layer is teeup's and is upgraded by `teeup update`. Neovim reads
# $XDG_CONFIG_HOME/nvim, so user_config_dir is the right root here.
NVIM_DIR="$(user_config_dir)/nvim"
for rel in init.lua stylua.toml lua/config/lazy.lua lua/config/options.lua \
           lua/config/keymaps.lua lua/config/autocmds.lua lua/plugins/local.lua; do
  copy_config_once "$TEEUP_CAP_DIR/config/nvim/$rel" "$NVIM_DIR/$rel"
done

# With both init.vim and init.lua, Neovim reports E5422 ("Conflicting
# configs") and loads only init.lua; ~/.vimrc is Vim's and Neovim never reads
# it. Both are reported, neither is moved.
if [[ -f "$NVIM_DIR/init.vim" ]]; then
  warn "$NVIM_DIR/init.vim exists next to init.lua; Neovim reports E5422 and ignores it. Fold what you need into $NVIM_DIR/lua/config/options.lua."
fi
if [[ -f "$HOME/.vimrc" ]]; then
  log "$HOME/.vimrc is Vim's; Neovim reads $NVIM_DIR/init.lua instead."
fi

# LazyVim stops with an error on a Neovim older than 0.11.2, and pkg_install
# keeps whatever nvim is already on PATH, so an old one is reported here.
if have nvim; then
  nvim_version="$(nvim --version 2>/dev/null | head -1 | sed -n 's/^NVIM v\([0-9][0-9]*\)\.\([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2 \3/p')"
  if [[ -n "$nvim_version" ]]; then
    read -r major minor patch <<< "$nvim_version"
    if (( 10#$major * 10000 + 10#$minor * 100 + 10#$patch < 1102 )); then
      warn "$(command -v nvim) is Neovim $major.$minor.$patch; LazyVim needs 0.11.2 or later. Upgrade it, or put a newer nvim first on PATH."
    fi
  fi
fi
log "Plugins are cloned by Neovim on the first start: run nvim, then :LazyHealth."
```

```bash file=capabilities/neovim/theme-apply
#!/usr/bin/env bash
# New Neovim instances read current/theme when they start. Running ones are
# told through their RPC sockets, which Neovim creates as nvim.<pid>.0 in
# $XDG_RUNTIME_DIR when that is set, and otherwise in a private directory
# $TMPDIR/nvim.<user>/<random>/ (msgpack_rpc/server.c and os/stdpaths.c).
# <Cmd> keys work in every mode, so the reload lands wherever the cursor is.
#
# `teeup theme set` runs every capability's hook, and a Neovim teeup did not
# install (one on a developer's machine running this repo's tests) is not
# this hook's to drive, so nothing happens until `teeup install neovim` has.
if ! state_done check "cap-$TEEUP_CAP"; then
  exit 0
fi
if ! have nvim; then
  exit 0
fi
keys='<Cmd>lua require("teeup.neovim").apply()<CR>'
user="$(id -un)"
found=0
for sock in "${XDG_RUNTIME_DIR:-/nonexistent}"/nvim.*.0 "${TMPDIR:-/tmp}/nvim.$user"/*/nvim.*.0 "/tmp/nvim.$user"/*/nvim.*.0; do
  [[ -e "$sock" ]] || continue
  found=1
  run_cmd nvim --server "$sock" --remote-send "$keys" ||
    warn "Could not reach the Neovim at $sock; it picks the theme up at its next start."
done
if [[ $found -eq 0 ]]; then
  log "No running Neovim to tell; the theme is read at the next start."
fi
```

```bash file=capabilities/neovim/font-apply
#!/usr/bin/env bash
# For Neovim the font is a GUI matter (vim.o.guifont, read by Neovide and the
# like); in a terminal the font is WezTerm's. A running GUI instance is told
# the same way theme-apply tells it: teeup.neovim's apply() re-reads the
# theme and the font. Same install gate and socket locations as theme-apply.
if ! state_done check "cap-$TEEUP_CAP"; then
  exit 0
fi
if ! have nvim; then
  exit 0
fi
keys='<Cmd>lua require("teeup.neovim").apply()<CR>'
user="$(id -un)"
found=0
for sock in "${XDG_RUNTIME_DIR:-/nonexistent}"/nvim.*.0 "${TMPDIR:-/tmp}/nvim.$user"/*/nvim.*.0 "/tmp/nvim.$user"/*/nvim.*.0; do
  [[ -e "$sock" ]] || continue
  found=1
  run_cmd nvim --server "$sock" --remote-send "$keys" ||
    warn "Could not reach the Neovim at $sock; it picks the font up at its next start."
done
if [[ $found -eq 0 ]]; then
  log "No running Neovim to tell; the font is read at the next start."
fi
```

- [ ] **Step 7: Make the scripts executable and run the suite**

Run: `chmod +x capabilities/neovim/install capabilities/neovim/configure capabilities/neovim/theme-apply capabilities/neovim/font-apply && bash tests/capabilities/neovim.sh`
Expected: `Summary: 14/14 passed`. `luac` and `lua` are required (CI installs them): without them the three Lua tests fail with an install hint.

- [ ] **Step 8: Full checks and commit**

`neovim` is `tier=lazy`, so no tier list changes.

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning capabilities/neovim/install capabilities/neovim/configure capabilities/neovim/theme-apply capabilities/neovim/font-apply tests/capabilities/neovim.sh
luac -p capabilities/neovim/config/nvim/init.lua capabilities/neovim/config/nvim/lua/config/*.lua capabilities/neovim/config/nvim/lua/plugins/local.lua capabilities/neovim/default/teeup/neovim.lua
git diff --check
git add capabilities/neovim themes/catppuccin tests/capabilities/neovim.sh
git commit -m "Add the neovim capability with the LazyVim starter"
```

Expected: `commands --check`, shellcheck, `luac -p` and `git diff --check` print nothing; `./tests/run.sh` ends with `All N suites passed.` where N is the suite count printed before this task, plus 1.

---

### Task 6: `vscode` capability

**Files:**
- Create: `capabilities/vscode/{capability,install,configure,theme-apply,font-apply}`, `capabilities/vscode/themed/vscode.json.tpl`
- Modify: `themes/catppuccin/dark.toml`, `themes/catppuccin/light.toml`
- Test: `tests/capabilities/vscode.sh` (new suite)

**Interfaces:**
- Consumes: `json_set_key`, `json_quote` (Task 1); `cask_install`, `casks_supported`; `cap_run_optional`; `state_done`; `font_current`; `TEEUP_THEME_DIR`, `TEEUP_FONT_FAMILY`; the gate of contract 4.
- Produces: contract 5's `vscode_theme` and `vscode_extension`; contract 6's `vscode` metadata (`tier=lazy`, `provides="code"`, `apps="Visual Studio Code"`); `current/theme/<mode>/vscode.json`; the keys `window.autoDetectColorScheme`, `workbench.preferredDarkColorTheme`, `workbench.preferredLightColorTheme` and `editor.fontFamily` in `~/Library/Application Support/Code/User/settings.json`.

**External facts (verified 2026-09-13):**
- Homebrew cask `visual-studio-code` 1.137.0: `app "Visual Studio Code.app"`, `binary ".../Contents/Resources/app/bin/code"` linked to `$HOMEBREW_PREFIX/bin/code`, `auto_updates true`.
- `microsoft/vscode-docs` `docs/configure/settings.md`: user settings on macOS at `$HOME/Library/Application\ Support/Code/User/settings.json`; `command-line.md` lists `--install-extension <extension-id>` and `--list-extensions`.
- `src/vs/workbench/services/themes/common/workbenchThemeService.ts`: `COLOR_THEME = 'workbench.colorTheme'`, `PREFERRED_DARK_THEME = 'workbench.preferredDarkColorTheme'`, `PREFERRED_LIGHT_THEME = 'workbench.preferredLightColorTheme'`, `DETECT_COLOR_SCHEME = 'window.autoDetectColorScheme'` (default `false` in `themeConfiguration.ts`). `src/vs/editor/common/config/fontInfo.ts`: `DEFAULT_MAC_FONT_FAMILY = 'Menlo, Monaco, \'Courier New\', monospace'`. `terminalConfiguration.ts` describes `terminal.integrated.fontFamily` as defaulting to `#editor.fontFamily#`'s value.
- `catppuccin/vscode` `packages/catppuccin-vsc/package.json`: `"publisher": "Catppuccin"`, `"name": "catppuccin-vsc"`, themes labelled `Catppuccin Mocha`, `Catppuccin Macchiato`, `Catppuccin Frappé`, `Catppuccin Latte`.

**Real-Mac risk:** only a Mac proves that `code --install-extension Catppuccin.catppuccin-vsc` works from a process with no window server session of its own (the CLI starts a headless Electron), that VS Code switches between the two preferred themes when the system appearance changes, and that it reloads a `settings.json` rewritten while it runs. The extension install needs network; a failure warns and leaves the settings written.

- [ ] **Step 1: Write the failing test `tests/capabilities/vscode.sh`**

```bash file=tests/capabilities/vscode.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# jq is found before setup_test_env narrows PATH and linked into the mock
# bin: the hooks call it by name, and Homebrew's copy is hidden on the macOS
# runners. A machine without jq fails this suite rather than skipping it.
JQ_BIN="$(command -v jq || true)"

setup() {
  setup_test_env
  mock_macos_base
  if [[ -z "$JQ_BIN" ]]; then
    echo "jq is not installed: this suite needs it"
    return 1
  fi
  ln -s "$JQ_BIN" "$MOCK_BIN/jq"
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  # The code CLI: lists what $HOME/code-extensions holds, one id per line.
  mock_command_script code <<'EOF2'
case "$1" in
  --list-extensions) cat "$HOME/code-extensions" 2>/dev/null || true ;;
  *) : ;;
esac
exit 0
EOF2
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  TEEUP="$TEEUP_PATH/bin/teeup"
  # The real location, space included: ~/Library/Application Support/Code/User.
  SETTINGS="$TEST_HOME/Library/Application Support/Code/User/settings.json"
}

# mark_installed: what `teeup install vscode` records after configure.
mark_installed() {
  mkdir -p "$TEST_HOME/.local/state/teeup/done"
  : > "$TEST_HOME/.local/state/teeup/done/cap-vscode"
}

read_setting() { jq -r "$1" "$SETTINGS"; }

test_vscode_is_lazy_and_provides_code() {
  setup || return 1
  source "$TEEUP_PATH/lib/all.sh"
  assert_equals "lazy" "$(cap_meta_get vscode tier)" || return 1
  assert_equals "code" "$(cap_meta_get vscode provides)" || return 1
  assert_equals "Visual Studio Code" "$(cap_meta_get vscode apps)" || return 1
  if grep -qx vscode "$TEEUP_PATH/capabilities/daily.list" "$TEEUP_PATH/capabilities/core.list"; then
    echo "vscode is lazy but sits in a tier list"
    return 1
  fi
  cleanup_test_env
}

test_install_dry_run_gets_the_cask() {
  setup || return 1
  local out
  out="$(DRY_RUN=true "$TEEUP" install vscode)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask visual-studio-code" || return 1
  cleanup_test_env
}

test_install_warns_on_macports() {
  setup || return 1
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install vscode 2>&1)"
  assert_contains "$out" "Visual Studio Code is a cask and MacPorts has no port of it" || return 1
  assert_not_contains "$out" "brew install --cask" || return 1
  cleanup_test_env
}

test_configure_writes_themes_font_and_installs_the_extension() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  DRY_RUN=false "$TEEUP" configure vscode >/dev/null
  assert_file_exists "$SETTINGS" || return 1
  assert_equals "true" "$(read_setting '.["window.autoDetectColorScheme"]')" || return 1
  assert_equals "Catppuccin Mocha" "$(read_setting '.["workbench.preferredDarkColorTheme"]')" || return 1
  assert_equals "Catppuccin Latte" "$(read_setting '.["workbench.preferredLightColorTheme"]')" || return 1
  assert_equals "'JetBrainsMono Nerd Font', Menlo, Monaco, 'Courier New', monospace" "$(read_setting '.["editor.fontFamily"]')" || return 1
  assert_equals "null" "$(read_setting '.workbench')" "dotted keys stay flat" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "code --install-extension Catppuccin.catppuccin-vsc" || return 1
  cleanup_test_env
}

test_an_installed_extension_is_not_reinstalled() {
  setup || return 1
  printf 'ms-python.python\ncatppuccin.catppuccin-vsc\n' > "$TEST_HOME/code-extensions"
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure vscode)"
  assert_contains "$out" "Already installed: VS Code extension Catppuccin.catppuccin-vsc" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "code --install-extension" || return 1
  cleanup_test_env
}

test_without_the_code_command_the_extension_is_a_hint() {
  setup || return 1
  export TEEUP_TEST_MISSING="code"
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure vscode)"
  assert_contains "$out" "install the Catppuccin.catppuccin-vsc extension from the Extensions view" || return 1
  assert_equals "Catppuccin Mocha" "$(read_setting '.["workbench.preferredDarkColorTheme"]')" "the settings are still written" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  DRY_RUN=false "$TEEUP" configure vscode >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure vscode)"
  assert_contains "$out" "Already current: $SETTINGS" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=true "$TEEUP" configure vscode)"
  assert_contains "$out" "[DRY-RUN] Would write $SETTINGS (window.autoDetectColorScheme)" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: code --install-extension Catppuccin.catppuccin-vsc" || return 1
  [[ ! -e "$SETTINGS" ]] || { echo "settings written in dry run"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "code --install-extension" || return 1
  cleanup_test_env
}

test_the_users_settings_survive() {
  setup || return 1
  mkdir -p "$(dirname "$SETTINGS")"
  # A hand-edited file with a comment and a trailing comma, both of which VS
  # Code accepts: the keys survive and the original is backed up.
  cat > "$SETTINGS" <<'EOF2'
{
    // mine
    "editor.fontSize": 13,
    "workbench.colorTheme": "Abyss",
}
EOF2
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  DRY_RUN=false "$TEEUP" configure vscode >/dev/null
  assert_equals "13" "$(read_setting '.["editor.fontSize"]')" || return 1
  assert_equals "Abyss" "$(read_setting '.["workbench.colorTheme"]')" "the manual theme key is not teeup's to change" || return 1
  assert_equals "Catppuccin Mocha" "$(read_setting '.["workbench.preferredDarkColorTheme"]')" || return 1
  ls "$SETTINGS".teeup_backup_* >/dev/null 2>&1 || { echo "the commented original was not backed up"; return 1; }
  cleanup_test_env
}

test_hooks_leave_an_uninstalled_vscode_alone() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  DRY_RUN=false "$TEEUP" install font Hack >/dev/null
  [[ ! -e "$TEST_HOME/Library/Application Support/Code" ]] || { echo "a hook wrote settings for a VS Code teeup never installed"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "code --" "not even the extension list is read" || return 1
  cleanup_test_env
}

test_theme_set_and_install_font_update_an_installed_vscode() {
  setup || return 1
  mark_installed
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  assert_equals "Catppuccin Latte" "$(read_setting '.["workbench.preferredLightColorTheme"]')" || return 1
  DRY_RUN=false "$TEEUP" install font Hack >/dev/null
  assert_equals "'Hack Nerd Font', Menlo, Monaco, 'Courier New', monospace" "$(read_setting '.["editor.fontFamily"]')" || return 1
  cleanup_test_env
}

test_hooks_without_jq_warn_and_continue() {
  setup || return 1
  export TEEUP_TEST_MISSING="jq"
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" configure vscode 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "jq is not installed; cannot write $SETTINGS" || return 1
  [[ ! -e "$SETTINGS" ]] || { echo "settings written without jq"; return 1; }
  unset TEEUP_TEST_MISSING
  cleanup_test_env
}

test_theme_renders_the_vscode_names() {
  setup || return 1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  local light
  light="$TEST_HOME/.local/state/teeup/current/theme/light/vscode.json"
  assert_file_exists "$light" || return 1
  assert_equals "Catppuccin Latte" "$(jq -r .theme "$light")" || return 1
  assert_equals "Catppuccin.catppuccin-vsc" "$(jq -r .extension "$light")" || return 1
  cleanup_test_env
}

echo "capabilities/vscode"
run_test "vscode is lazy and provides code" test_vscode_is_lazy_and_provides_code
run_test "install dry run gets the cask" test_install_dry_run_gets_the_cask
run_test "install warns on macports" test_install_warns_on_macports
run_test "configure writes themes, font and installs the extension" test_configure_writes_themes_font_and_installs_the_extension
run_test "an installed extension is not reinstalled" test_an_installed_extension_is_not_reinstalled
run_test "without the code command the extension is a hint" test_without_the_code_command_the_extension_is_a_hint
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "the user's settings survive" test_the_users_settings_survive
run_test "hooks leave an uninstalled VS Code alone" test_hooks_leave_an_uninstalled_vscode_alone
run_test "theme set and install font update an installed VS Code" test_theme_set_and_install_font_update_an_installed_vscode
run_test "hooks without jq warn and continue" test_hooks_without_jq_warn_and_continue
run_test "theme renders the vscode names" test_theme_renders_the_vscode_names
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/capabilities/vscode.sh`
Expected: `Unknown capability: vscode` in the failures; `Summary: 1/13 passed` (only `hooks leave an uninstalled VS Code alone`).

- [ ] **Step 3: Write the metadata, `install` and `configure`**

```sh file=capabilities/vscode/capability
summary="Visual Studio Code, following the teeup theme and font"
group=editors
tier=lazy
requires="package-manager cli-tools"
provides="code"
packages=""
casks="visual-studio-code"
apps="Visual Studio Code"
interactive=false
```

```bash file=capabilities/vscode/install
#!/usr/bin/env bash
# The cask links `code` (the CLI inside the app bundle) into the Homebrew bin
# dir, which theme-apply uses to install the theme extension. MacPorts has no
# casks and no port of VS Code.
if casks_supported; then
  cask_install visual-studio-code
else
  warn "Visual Studio Code is a cask and MacPorts has no port of it; download it from https://code.visualstudio.com/download"
fi
```

```bash file=capabilities/vscode/configure
#!/usr/bin/env bash
# VS Code keeps user settings in ~/Library/Application Support/Code/User/
# settings.json on macOS, outside ~/.config, and applies edits to that file
# live. There is no shipped file: teeup owns four keys in whatever settings
# you have (window.autoDetectColorScheme, the two preferred colour themes and
# editor.fontFamily) and leaves the rest alone. configure brings them up to
# date by running the two hooks `teeup theme set` and `teeup install font`
# run. The hooks do nothing until teeup has installed VS Code;
# TEEUP_CONFIGURING tells them this is that install.
export TEEUP_CONFIGURING="$TEEUP_CAP"
cap_run_optional "$TEEUP_CAP" theme-apply
cap_run_optional "$TEEUP_CAP" font-apply
app="Visual Studio Code"
if [[ -d "${TEEUP_APPS_DIR:-/Applications}/$app.app" ]]; then
  log "$app is installed; open it with: open -a '$app'"
else
  log "$app.app is not in ${TEEUP_APPS_DIR:-/Applications} yet; the settings are ready for it."
fi
```

- [ ] **Step 4: Write the hooks**

```bash file=capabilities/vscode/theme-apply
#!/usr/bin/env bash
# With window.autoDetectColorScheme on, VS Code follows the system appearance
# itself and picks workbench.preferredDarkColorTheme or
# workbench.preferredLightColorTheme, so both rendered modes are written and
# workbench.colorTheme (the theme used while detection is off) is left to
# you. The theme comes from an extension (Catppuccin for the shipped
# palette), which the `code` CLI installs when it is on PATH.
#
# `teeup theme set` runs every capability's hook; a settings file for an
# editor teeup did not install is not this hook's to write.
if ! state_done check "cap-$TEEUP_CAP" && [[ "${TEEUP_CONFIGURING:-}" != "$TEEUP_CAP" ]]; then
  exit 0
fi
VSCODE_SETTINGS="$HOME/Library/Application Support/Code/User/settings.json"
THEME_DIR="${TEEUP_THEME_DIR:-$TEEUP_STATE_DIR/current/theme}"
dark="$THEME_DIR/dark/vscode.json"
light="$THEME_DIR/light/vscode.json"
if [[ ! -f "$dark" || ! -f "$light" ]]; then
  log "No rendered VS Code theme in $THEME_DIR yet; the next teeup theme set writes it."
  exit 0
fi
if ! have jq; then
  warn "jq is not installed; cannot write $VSCODE_SETTINGS. Run: teeup install cli-tools"
  exit 0
fi
json_set_key "$VSCODE_SETTINGS" window.autoDetectColorScheme true
json_set_key "$VSCODE_SETTINGS" workbench.preferredDarkColorTheme "$(json_quote "$(jq -r .theme "$dark")")"
json_set_key "$VSCODE_SETTINGS" workbench.preferredLightColorTheme "$(json_quote "$(jq -r .theme "$light")")"

# The extension, once per distinct id; a palette whose theme is built in names
# it "none". `code --list-extensions` is a read, so it stays outside run_cmd.
for ext in $(jq -r .extension "$dark" "$light" | sort -u); do
  if [[ "$ext" == "none" ]]; then
    continue
  fi
  if ! have code; then
    log "The code command is not on PATH; install the $ext extension from the Extensions view."
  elif code --list-extensions 2>/dev/null | grep -qixF "$ext"; then
    log "Already installed: VS Code extension $ext"
  else
    run_cmd code --install-extension "$ext" ||
      warn "Could not install the $ext extension; install it from the Extensions view."
  fi
done
```

```bash file=capabilities/vscode/font-apply
#!/usr/bin/env bash
# editor.fontFamily is a CSS font list; VS Code's own macOS default,
# "Menlo, Monaco, 'Courier New', monospace", stays behind the teeup family as
# the fallback. terminal.integrated.fontFamily follows editor.fontFamily while
# it is unset. Same install gate and settings path as theme-apply.
if ! state_done check "cap-$TEEUP_CAP" && [[ "${TEEUP_CONFIGURING:-}" != "$TEEUP_CAP" ]]; then
  exit 0
fi
VSCODE_SETTINGS="$HOME/Library/Application Support/Code/User/settings.json"
if ! have jq; then
  warn "jq is not installed; cannot write $VSCODE_SETTINGS. Run: teeup install cli-tools"
  exit 0
fi
family="${TEEUP_FONT_FAMILY:-$(font_current)}"
json_set_key "$VSCODE_SETTINGS" editor.fontFamily "$(json_quote "'$family', Menlo, Monaco, 'Courier New', monospace")"
```

- [ ] **Step 5: Write the themed template and add the two name keys to both palettes**

```json file=capabilities/vscode/themed/vscode.json.tpl
{
  "generated_by": "teeup theme set; do not edit, the next theme switch replaces this file",
  "mode": "{{ mode }}",
  "theme": "{{ vscode_theme }}",
  "extension": "{{ vscode_extension }}"
}
```

```toml edit-old=themes/catppuccin/dark.toml
zed_theme = "Catppuccin Mocha"
zed_extension = "catppuccin"
neovim_colorscheme = "catppuccin-mocha"

accent = "#89b4fa"
selection = "#45475a"
```

```toml edit-new=themes/catppuccin/dark.toml
zed_theme = "Catppuccin Mocha"
zed_extension = "catppuccin"
neovim_colorscheme = "catppuccin-mocha"
vscode_theme = "Catppuccin Mocha"
vscode_extension = "Catppuccin.catppuccin-vsc"

accent = "#89b4fa"
selection = "#45475a"
```

```toml edit-old=themes/catppuccin/light.toml
zed_theme = "Catppuccin Latte"
zed_extension = "catppuccin"
neovim_colorscheme = "catppuccin-latte"

accent = "#1e66f5"
selection = "#ccd0da"
```

```toml edit-new=themes/catppuccin/light.toml
zed_theme = "Catppuccin Latte"
zed_extension = "catppuccin"
neovim_colorscheme = "catppuccin-latte"
vscode_theme = "Catppuccin Latte"
vscode_extension = "Catppuccin.catppuccin-vsc"

accent = "#1e66f5"
selection = "#ccd0da"
```

- [ ] **Step 6: Make the scripts executable and run the suite**

Run: `chmod +x capabilities/vscode/install capabilities/vscode/configure capabilities/vscode/theme-apply capabilities/vscode/font-apply && bash tests/capabilities/vscode.sh`
Expected: `Summary: 13/13 passed`.

- [ ] **Step 7: Full checks and commit**

`vscode` is `tier=lazy`, so no tier list changes.

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning capabilities/vscode/install capabilities/vscode/configure capabilities/vscode/theme-apply capabilities/vscode/font-apply tests/capabilities/vscode.sh
git diff --check
git add capabilities/vscode themes/catppuccin tests/capabilities/vscode.sh
git commit -m "Add the vscode capability"
```

Expected: `commands --check`, shellcheck and `git diff --check` print nothing; `./tests/run.sh` ends with `All N suites passed.` where N is the suite count printed before this task, plus 1.

---

### Task 7: README, CONTRIBUTING and the spec amendment

**Files:**
- Modify: `README.md`, `CONTRIBUTING.md`, `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md`

**Interfaces:**
- Consumes: every name from Tasks 1 to 6 as defined there: `json_set_key`, `json_merge_key`, `json_quote`, `TEEUP_EMACS_FLAVOR`, `TEEUP_CONFIGURING`, `sh.teeup.emacs`, the six palette keys, the seven capability names.
- Produces: the README's daily-tier sentence and "Editors" section; CONTRIBUTING items for JSON settings and editor hooks; the spec recording the user decision of 2026-09-13.

**Real-Mac risk:** none of its own; the text describes behaviour whose risks are recorded in Tasks 2 to 6.

- [ ] **Step 1: Describe the daily tier and the editors in the README**

The anchor is the end of the paragraph that lists the core tier. Plan 3b adds its "Lazy capabilities" section after the per-machine overrides paragraph that follows, and does not change this text.

```markdown edit-old=README.md
`theme`. The daily tier and everything lazy arrive in phase 3; `teeup list` is
always the source of truth.
```

```markdown edit-new=README.md
`theme`. The daily tier (`emacs`, `zed`, `firefox-developer-edition`,
`obsidian`) installs at bootstrap when you say yes to it. `neovim`, `vscode`
and `chrome` are lazy: `teeup install <name>` brings one in when you want it.
`teeup list` is always the source of truth.

### Editors

- **Emacs** runs as a daemon from the `sh.teeup.emacs` LaunchAgent, so
  `emacsclient -t` (the editor git and the shell use) and `emacsclient -c`
  (a window) always have a server. The answer `TEEUP_EMACS_FLAVOR` picks the
  configuration: `starter` (the default: a thin `~/.config/emacs/init.el`
  over teeup's built-ins-only layer), `doom` (Doom cloned into
  `~/.config/emacs`, then `doom install --no-env`), `spacemacs` (cloned into
  `~/.emacs.d`) or `none` (your own configuration, untouched). The wizard asks
  it with the daily set; change it with `./bootstrap --reconfigure`, or pin it
  in the machine file, then run `teeup configure emacs`.
- **Zed** and **VS Code** keep their own `settings.json`
  (`~/.config/zed/settings.json`, which Zed reads whatever `XDG_CONFIG_HOME`
  says, and `~/Library/Application Support/Code/User/settings.json`). teeup
  sets only the theme, font and theme-extension keys in them through `jq`,
  and leaves the rest alone. Comments inside the object do not survive that
  edit, so a file that has them is backed up first; a settings file that is a
  symlink is never written.
- **Neovim** gets the LazyVim starter layout under `~/.config/nvim`, every
  file yours after the first copy, with teeup's layer on `package.path`.
  LazyVim needs Neovim 0.11.2 or later.

`teeup theme set` and `teeup install font` reach every editor teeup has
installed: each has a themed template that names the theme for the palette
(Modus for Emacs, `catppuccin-mocha`/`catppuccin-latte` for Neovim and the
Catppuccin extension for Zed and VS Code) and a hook that tells a running
editor to pick it up.
```

- [ ] **Step 2: Append two items to CONTRIBUTING's "Adding a capability (new runtime)" list**

Append them after the last numbered item of that list, continuing its numbering, and renumber nothing already there. On `main` the last item is 13 (the `lib/macos.sh` rule quoted below), so these are 14 and 15. If plan 3b's items are already present, put these after its last one with the same text and the next two numbers.

```markdown edit-old=CONTRIBUTING.md
    `launchagent_install <label>` with the plist on stdin, and
    `launchagent_remove <label>` in `remove`. Never call `defaults write` or
    `launchctl` directly.
```

```markdown edit-new=CONTRIBUTING.md
    `launchagent_install <label>` with the plist on stdin, and
    `launchagent_remove <label>` in `remove`. Never call `defaults write` or
    `launchctl` directly.
14. An editor whose settings are JSON (Zed, VS Code) never gets a shipped
    `settings.json`: its hooks set only the keys teeup owns, with
    `json_set_key <file> <key> <json-value>` or
    `json_merge_key <file> <key> <json-object>` from `lib/files.sh`. The key is
    one literal top-level key (VS Code's `workbench.colorTheme` stays flat),
    the value is a JSON literal (`json_quote` makes one from text), comments
    and trailing commas are read, the write goes through
    `write_managed_file` (so `DRY_RUN` previews it), and a symlink or a file
    jq cannot edit is left alone with a warning.
15. A `theme-apply` or `font-apply` that writes an app's settings or talks to
    a running app starts with
    `if ! state_done check "cap-$TEEUP_CAP" && [[ "${TEEUP_CONFIGURING:-}" != "$TEEUP_CAP" ]]; then exit 0; fi`:
    `teeup theme set` runs every capability's hooks, including on machines
    where that app was never installed through teeup. A `configure` that
    wants the hooks' work done runs `export TEEUP_CONFIGURING="$TEEUP_CAP"`
    and then `cap_run_optional "$TEEUP_CAP" theme-apply`. Theme names an
    editor needs live in the palette next to the colours (`emacs_theme`,
    `zed_theme`, `zed_extension`, `neovim_colorscheme`, `vscode_theme`,
    `vscode_extension`; an extension of `none` installs nothing), so every
    theme, a user theme included, must define each of them in both modes or
    `teeup theme set` refuses to render.
```

- [ ] **Step 3: Record the 2026-09-13 decision in the spec**

The edits cover the status line, the Editors, Browsers, Productivity and Essential set rows of the interview table (the Productivity row called Obsidian lazy while the essential set made it daily, and the new daily set settles that), the `tier=` line of section 4a's `neovim` example, bootstrap step 4's wizard questions, the daily list under section 5, section 6's shim list and lazy list, and the daily tier line of section 11's diagram. Each edited line says what it was before.

```markdown edit-old=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md

Date: 2026-09-11
Status: approved design, pre-implementation

## Context

```

```markdown edit-new=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md

Date: 2026-09-11
Status: approved design, pre-implementation
Amended: 2026-09-13, the daily tier (user decision; see the Editors, Browsers, Productivity and Essential set rows of the interview table)

## Context

```

```markdown edit-old=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md
| Herdr | Lazy optional; agent workspace manager; verify macOS support. |
| Shell | Plain zsh, Omarchy-style layered default (`default/zsh/*` sourced by thin `~/.zshrc`); Starship; autosuggestions/syntax-highlighting/completions sourced directly; mise, zoxide, fzf, eza, bat wired in. No Oh My Zsh. |
| Prompt | Starship (TOML). |
| Editors | Emacs (flavor=starter default; doom/spacemacs/none switchable), Neovim (LazyVim), Zed, VS Code. |
| Git | Ask name/email once + optional work email; `includeIf` for `~/Work` (work identity) and `~/Personal`; both identities used on work laptop. Aliases + modern defaults like Omarchy. |
| Git extras | gh CLI + `gh auth login` + credential helper; lazygit; delta; git-lfs; pre-commit. |
| SSH/signing | ed25519 keys, macOS Keychain via ssh-agent, upload via gh, SSH commit signing (`gpg.format=ssh`). Separate key per identity (work/personal); SSH config host aliases pick the key. |
```

```markdown edit-new=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md
| Herdr | Lazy optional; agent workspace manager; verify macOS support. |
| Shell | Plain zsh, Omarchy-style layered default (`default/zsh/*` sourced by thin `~/.zshrc`); Starship; autosuggestions/syntax-highlighting/completions sourced directly; mise, zoxide, fzf, eza, bat wired in. No Oh My Zsh. |
| Prompt | Starship (TOML). |
| Editors | Emacs (flavor=starter default; doom/spacemacs/none switchable) and Zed are the daily editors. Neovim (LazyVim) and VS Code are lazy: fully configured capabilities reached through their `nvim` and `code` shims, `teeup install` and `teeup launch`. *Decision of 2026-09-13; this row first listed all four as daily.* |
| Git | Ask name/email once + optional work email; `includeIf` for `~/Work` (work identity) and `~/Personal`; both identities used on work laptop. Aliases + modern defaults like Omarchy. |
| Git extras | gh CLI + `gh auth login` + credential helper; lazygit; delta; git-lfs; pre-commit. |
| SSH/signing | ed25519 keys, macOS Keychain via ssh-agent, upload via gh, SSH commit signing (`gpg.format=ssh`). Separate key per identity (work/personal); SSH config host aliases pick the key. |
```

```markdown edit-old=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md
| Databases | Omarchy `docker-dbs` pattern: lazy picker starting localhost containers on Colima. |
| CLI core | Omarchy modern set: ripgrep fd fzf bat eza zoxide jq yq btop tree wget curl gnupg tldr dust lazygit gh; Omarchy aliases (ls→eza, cd→zoxide). |
| Fonts | JetBrainsMono Nerd Font at bootstrap; `teeup install font <name>` lazy, also switches terminal/editor font. |
| Browsers | Chrome, Firefox, Brave/Arc/Zen: all lazy casks. |
| Comms | Slack, Zoom, Signal/WhatsApp/Telegram, Discord/Teams: all lazy. |
| Productivity | Obsidian, 1Password, Raycast, Bruno/Notion/Typora: all lazy. |
| macOS prefs | Opinionated dev set on by default, one unit each, revertable. |
| Keyboard | Native `hidutil` Caps Lock→Control at bootstrap (LaunchAgent); Karabiner optional lazy with hyper-key config. |
| Secrets | macOS Keychain + `gh auth`; shell helper reads Keychain via `security`. Nothing in repo. |
| Dev dirs | Bootstrap creates `~/Work` and `~/Personal`; identity + SSH key per root. |
| Work vs personal | Only git identity + SSH key differ. |
| Essential set | Core (Xcode CLT, PM, shell, git/gh/ssh, WezTerm, font, CLI set, mise, AeroSpace, macOS defaults, hidutil) **plus daily set** (Emacs, Neovim, Zed, VS Code, Chrome, Obsidian) at bootstrap. Everything else lazy. |
| Profiles | No named profiles. Answers file + per-hostname overrides. |
| Themes | Yes: cross-tool theme system, a few themes, light/dark following macOS appearance. |
| Discoverability | CLI + `teeup menu` TUI (gum/fzf) from the same declarative data as `teeup list`/help. |
```

```markdown edit-new=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md
| Databases | Omarchy `docker-dbs` pattern: lazy picker starting localhost containers on Colima. |
| CLI core | Omarchy modern set: ripgrep fd fzf bat eza zoxide jq yq btop tree wget curl gnupg tldr dust lazygit gh; Omarchy aliases (ls→eza, cd→zoxide). |
| Fonts | JetBrainsMono Nerd Font at bootstrap; `teeup install font <name>` lazy, also switches terminal/editor font. |
| Browsers | Firefox Developer Edition is the daily browser. Chrome, Firefox, Brave/Arc/Zen: lazy casks. *Decision of 2026-09-13; the daily set first carried Chrome.* |
| Comms | Slack, Zoom, Signal/WhatsApp/Telegram, Discord/Teams: all lazy. |
| Productivity | Obsidian is daily (it was already in the essential set). 1Password, Raycast, Bruno/Notion/Typora: lazy. *Wording fixed 2026-09-13; this row first called Obsidian lazy while the essential set made it daily.* |
| macOS prefs | Opinionated dev set on by default, one unit each, revertable. |
| Keyboard | Native `hidutil` Caps Lock→Control at bootstrap (LaunchAgent); Karabiner optional lazy with hyper-key config. |
| Secrets | macOS Keychain + `gh auth`; shell helper reads Keychain via `security`. Nothing in repo. |
| Dev dirs | Bootstrap creates `~/Work` and `~/Personal`; identity + SSH key per root. |
| Work vs personal | Only git identity + SSH key differ. |
| Essential set | Core (Xcode CLT, PM, shell, git/gh/ssh, WezTerm, font, CLI set, mise, AeroSpace, macOS defaults, hidutil) **plus daily set** (Emacs, Zed, Firefox Developer Edition, Obsidian) at bootstrap. Everything else lazy. *Decision of 2026-09-13: the daily set was Emacs, Neovim, Zed, VS Code, Chrome, Obsidian; Neovim, VS Code and Chrome are now lazy.* |
| Profiles | No named profiles. Answers file + per-hostname overrides. |
| Themes | Yes: cross-tool theme system, a few themes, light/dark following macOS appearance. |
| Discoverability | CLI + `teeup menu` TUI (gum/fzf) from the same declarative data as `teeup list`/help. |
```

```markdown edit-old=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md
# capabilities/neovim/capability
summary="Neovim with LazyVim"
group=editors                  # editors|shell|git|languages|containers|apps|ai|macos|system
tier=daily                     # core | daily | lazy
provides="nvim"                # commands that get lazy shims when tier=lazy (space separated)
requires="package-manager git" # capabilities run before this one
packages="neovim"              # pkg_install candidates; used by default update/remove
```

```markdown edit-new=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md
# capabilities/neovim/capability
summary="Neovim with LazyVim"
group=editors                  # editors|shell|git|languages|containers|apps|ai|macos|system
tier=lazy                      # core | daily | lazy (neovim was daily until the 2026-09-13 decision)
provides="nvim"                # commands that get lazy shims when tier=lazy (space separated)
requires="package-manager git" # capabilities run before this one
packages="neovim"              # pkg_install candidates; used by default update/remove
```

```markdown edit-old=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md
  3  minimal self-install, only what the CLI needs to exist: write ~/.config/teeup/env,
     link ~/.local/bin/teeup, install gum (state dirs and shims belong to teeup-runtime)
  4  wizard (skipped when answers exist unless --reconfigure): name, personal email,
     work email (optional), package manager confirm, theme, include daily set (default yes)
     -> writes ~/.config/teeup/answers
  5  for cap in capabilities/core.list:  run_logged install; run_logged configure
  6  for cap in capabilities/daily.list: same (unless --skip-daily or answers say no)
```

```markdown edit-new=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md
  3  minimal self-install, only what the CLI needs to exist: write ~/.config/teeup/env,
     link ~/.local/bin/teeup, install gum (state dirs and shims belong to teeup-runtime)
  4  wizard (skipped when answers exist unless --reconfigure): name, personal email,
     work email (optional), package manager confirm, theme, include daily set (default yes),
     Emacs flavor (starter|doom|spacemacs|none, default starter; asked only with the daily set)
     -> writes ~/.config/teeup/answers
  5  for cap in capabilities/core.list:  run_logged install; run_logged configure
  6  for cap in capabilities/daily.list: same (unless --skip-daily or answers say no)
```

```markdown edit-old=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md
`run_logged` redirects stdin from `/dev/null` like Omarchy unless the capability sets `interactive=true`; `github` (gh auth login with scopes `admin:public_key,admin:ssh_signing_key`), `ssh` (key passphrase) and `package-manager` (sudo) are interactive.

Core list (ordered): `xcode-clt package-manager teeup-runtime dev-dirs zsh starship cli-tools secrets git ssh github mise wezterm fonts aerospace keyboard macos-defaults theme`.
Daily list: `emacs neovim zed vscode chrome obsidian`.
Everything else is `tier=lazy`, including `xcode` (`mas install 497799835` after checking `mas account`; the user signs into the App Store by hand since `mas signin` no longer works).

Capabilities that need a permission no script can grant (AeroSpace needs Accessibility, Karabiner needs driver approval) print the System Settings step from `configure` and check it from `doctor`.
```

```markdown edit-new=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md
`run_logged` redirects stdin from `/dev/null` like Omarchy unless the capability sets `interactive=true`; `github` (gh auth login with scopes `admin:public_key,admin:ssh_signing_key`), `ssh` (key passphrase) and `package-manager` (sudo) are interactive.

Core list (ordered): `xcode-clt package-manager teeup-runtime dev-dirs zsh starship cli-tools secrets git ssh github mise wezterm fonts aerospace keyboard macos-defaults theme`.
Daily list: `emacs zed firefox-developer-edition obsidian` (decision of 2026-09-13; `neovim`, `vscode` and `chrome` are lazy capabilities).
Everything else is `tier=lazy`, including `xcode` (`mas install 497799835` after checking `mas account`; the user signs into the App Store by hand since `mas signin` no longer works).

Capabilities that need a permission no script can grant (AeroSpace needs Accessibility, Karabiner needs driver approval) print the System Settings step from `configure` and check it from `doctor`.
```

```markdown edit-old=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md

AI CLIs (Claude Code, Codex, Gemini, Copilot CLI, OpenCode) use mise wrappers instead of shims, exactly like Omarchy's `mise-install`: `~/.local/bin/claude` runs `mise use -g claude` on first call and `exec mise x claude -- claude "$@"` after, so `teeup update` upgrades them with `mise upgrade`. The `ai` capability writes the wrappers at configure time; nothing is downloaded until first call.

Language runtimes are `teeup install dev-env <python|node|java|ruby|rust|go>`; Python also installs uv, Rust uses rustup, the rest are `mise use --global`. Runtimes get no shims (see the `provides=` rule). Shims exist only for commands macOS lacks: `docker`, `colima`, `kubectl`, `helm`, `k9s`, `tmux`, `herdr`, `ollama`, `lazydocker`.

Bootstrap versus lazy: bootstrap installs what every terminal session needs (core) plus the daily set, which defaults to yes. Lazy covers languages, containers, Kubernetes, `docker-dbs`, AI CLIs, Ollama, Cursor, Herdr, tmux, Karabiner, Xcode, browsers beyond Chrome, communication and productivity apps (1Password, Raycast, Bruno, Notion, Typora).

Herdr is gated on a phase 3 check that it ships macOS builds; if it does not, the capability is dropped.

```

```markdown edit-new=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md

AI CLIs (Claude Code, Codex, Gemini, Copilot CLI, OpenCode) use mise wrappers instead of shims, exactly like Omarchy's `mise-install`: `~/.local/bin/claude` runs `mise use -g claude` on first call and `exec mise x claude -- claude "$@"` after, so `teeup update` upgrades them with `mise upgrade`. The `ai` capability writes the wrappers at configure time; nothing is downloaded until first call.

Language runtimes are `teeup install dev-env <python|node|java|ruby|rust|go>`; Python also installs uv, Rust uses rustup, the rest are `mise use --global`. Runtimes get no shims (see the `provides=` rule). Shims exist only for commands macOS lacks: `nvim`, `code`, `docker`, `colima`, `kubectl`, `helm`, `k9s`, `tmux`, `herdr`, `ollama`, `lazydocker`.

Bootstrap versus lazy: bootstrap installs what every terminal session needs (core) plus the daily set, which defaults to yes. Lazy covers languages, containers, Kubernetes, `docker-dbs`, AI CLIs, Ollama, Cursor, Herdr, tmux, Karabiner, Xcode, Neovim, VS Code, Chrome and every browser other than Firefox Developer Edition, communication and productivity apps (1Password, Raycast, Bruno, Notion, Typora). (Decision of 2026-09-13: Neovim, VS Code and Chrome were daily in the first version of this document.)

Herdr is gated on a phase 3 check that it ships macOS builds; if it does not, the capability is dropped.

```

```markdown edit-old=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md
   └── theme           default theme rendered for dark and light
   │
   ▼
daily tier (if chosen): emacs neovim zed vscode chrome obsidian
   │
   ▼
lazy capabilities: shims in place, nothing downloaded
```

```markdown edit-new=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md
   └── theme           default theme rendered for dark and light
   │
   ▼
daily tier (if chosen): emacs zed firefox-developer-edition obsidian
   │
   ▼
lazy capabilities: shims in place, nothing downloaded
```

- [ ] **Step 4: Check the text and commit**

```bash
grep -n "emacs neovim zed vscode chrome obsidian" docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md README.md capabilities/daily.list
grep -n "2026-09-13" docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md | wc -l
./bin/teeup commands --check
./tests/run.sh
git diff --check
git add README.md CONTRIBUTING.md docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md
git commit -m "Document the daily tier and record the 2026-09-13 tier decision in the spec"
```

Expected: the first `grep` prints nothing (the old daily list survives nowhere); the second prints `8`; `commands --check` and `git diff --check` print nothing; `./tests/run.sh` ends with `All N suites passed.` where N is the suite count printed before this task (no new suite).

---

## Verification

Run from the repository root after Task 7, on a machine with `shellcheck`, `jq`, `lua`/`luac`, `python3` and (for the two Elisp checks) `emacs` installed (`sudo apt-get install -y shellcheck jq lua5.4 python3 emacs-nox`, or `brew install shellcheck jq lua python emacs`):

```bash
./bin/teeup commands --check          # prints nothing
./tests/run.sh                        # All N suites passed: the count before Task 1, plus 8
shellcheck --severity=warning bootstrap bin/teeup lib/*.sh \
  $(find capabilities -type f \( -name install -o -name configure \
    -o -name remove -o -name doctor -o -name theme-apply -o -name font-apply \)) \
  tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh \
  tests/lib/*.sh tests/capabilities/*.sh
luac -p capabilities/neovim/config/nvim/init.lua capabilities/neovim/config/nvim/lua/config/*.lua \
        capabilities/neovim/config/nvim/lua/plugins/local.lua capabilities/neovim/default/teeup/neovim.lua
./bin/teeup list --tier daily         # emacs, firefox-developer-edition, obsidian, zed
./bin/teeup list --tier lazy          # includes chrome, neovim, vscode
```

Then, under a throwaway `$HOME`, render every editor's theme file and write Zed's settings the way `teeup install zed` would:

```bash
tmp="$(mktemp -d)"
env HOME="$tmp" XDG_CONFIG_HOME="$tmp/.config" XDG_STATE_HOME="$tmp/.local/state" ./bin/teeup theme set catppuccin
ls "$tmp/.local/state/teeup/current/theme/dark"     # colors.toml emacs.el env.sh neovim.lua starship-palette.toml vscode.json wezterm.lua zed.json
mkdir -p "$tmp/.local/state/teeup/done" && : > "$tmp/.local/state/teeup/done/cap-zed"
env HOME="$tmp" XDG_CONFIG_HOME="$tmp/.config" XDG_STATE_HOME="$tmp/.local/state" ./bin/teeup configure zed
jq . "$tmp/.config/zed/settings.json"
```

Expected: the `ls` shows the eight files named in the comment and no `{{` in any of them; the last command prints `theme` as `{"mode": "system", "light": "Catppuccin Latte", "dark": "Catppuccin Mocha"}`, `auto_install_extensions` as `{"catppuccin": true}` and `buffer_font_family` as `JetBrainsMono Nerd Font`.

**What the first real run on a Mac should show.** Nothing in this plan has executed on macOS. In order:

1. `./bootstrap --dry-run` asks the Emacs flavor right after the daily-set question, then walks `emacs zed firefox-developer-edition obsidian` after the core tier with `brew install --cask emacs-app`, `zed`, `firefox@developer-edition` and `obsidian` lines.
2. `./bootstrap` installs them. `launchctl print gui/$(id -u)/sh.teeup.emacs` shows the agent running; `git config --get core.editor` prints `emacsclient -t` (the emacs capability re-ran git's configuration); `git commit` in a new WezTerm tab opens a terminal frame of the daemon.
3. `emacsclient -c` opens a window in Modus Vivendi (dark) or Modus Operandi (light) in JetBrainsMono Nerd Font; `teeup install font Hack` changes the frame's font at once.
4. Zed opens with the Catppuccin extension installing itself, then Catppuccin Mocha or Latte following System Settings; its terminal uses the same font as the buffer.
5. Firefox Developer Edition and Obsidian are in `/Applications`.
6. `teeup install neovim`, then `nvim`: lazy.nvim and LazyVim install, `catppuccin-mocha` loads, `:LazyHealth` is clean. With that Neovim open, `teeup theme set catppuccin` in another tab makes it reload (visible when the appearance changed in between).
7. `teeup install vscode`: VS Code gets the Catppuccin extension and follows the system appearance between Catppuccin Mocha and Latte; `teeup install chrome` installs Google Chrome.
8. `TEEUP_EMACS_FLAVOR=doom` in `machines/<hostname>.conf`, then `teeup configure emacs`: the starter directory is moved to `~/.config/emacs.teeup_backup_<timestamp>`, Doom is cloned, `doom install --no-env` runs to completion, and `launchctl kickstart -k gui/$(id -u)/sh.teeup.emacs` brings the daemon back up with Doom.

---

## Self-review

### Spec coverage

| Requirement | Source | Task |
|---|---|---|
| Daily tier `emacs zed firefox-developer-edition obsidian`, in that order, installed at bootstrap unless `--skip-daily` or `TEEUP_DAILY=no` | user decision 2026-09-13; spec 5 step 6 | 2, 3, 4 (each appends its names; Task 4's bootstrap test checks the order) |
| `neovim` (`provides="nvim"`), `vscode` (`provides="code"`) and `chrome` (`apps="Google Chrome"`) are `tier=lazy` and in no tier list | user decision 2026-09-13 | 4, 5, 6 (each suite asserts it) |
| Emacs with flavor `starter` default and `doom`/`spacemacs`/`none` switchable | interview: Editors; brief: `TEEUP_EMACS_FLAVOR` | 2 |
| Emacs as daemon plus `emacsclient`, the editor git and the shell already expect | research findings (dotfiles repo); `capabilities/git/configure`, `capabilities/zsh/default/env` | 2 |
| Neovim with LazyVim; Lua three-tier `package.path` (state, user, teeup default) | interview: Editors; spec 2, 7 | 5 |
| Zed and VS Code get theme and font keys written by jq; no shipped `settings.json` | spec 7 "Fonts", "Themes" | 1, 3, 6 |
| `current/font` read by Neovim, Zed and VS Code, switched by `teeup install font` | spec 4b, 7 | 3, 5, 6 (`font-apply`), 2 (Emacs as well) |
| `themed/*.tpl` per capability with colours; light and dark follow macOS appearance | spec 4, 7 | 2, 3, 5, 6 |
| Casks skipped with a note on MacPorts | spec 4a, 7 | 2 (port fallback), 3, 4, 6 |
| `config/` copied once and user-owned, `default/` referenced at runtime | spec 4, 7 | 2, 5 |
| Wizard asks the daily set; answers file plus machine file, machine wins | spec 5 step 4, 7 | 2 |
| Every script DRY_RUN-faithful, bash 3.2, shellcheck clean, tested under the mock harness | spec "Verification"; brief | 1 to 6 |
| Spec amended to record the decision, dated 2026-09-13 | brief | 7 |

Spec section 6's shims, `teeup launch` and `teeup install dev-env` are plan 3b's; this plan supplies only the metadata they read (contract 6).

### External facts and their sources (all fetched or run on 2026-09-13)

- Homebrew casks, from `https://formulae.brew.sh/api/cask/<token>.json` and the `.rb` files in `Homebrew/homebrew-cask`: `emacs-app` 31.1 (app `Emacs.app`; binaries `emacs`, `emacsclient`, `ebrowse`, `etags`; `old_tokens: ["emacs"]`), `zed` 1.19.2 (app `Zed.app`, binary `zed`), `firefox@developer-edition` 156.0b5 (app `Firefox Developer Edition.app`), `obsidian` 1.13.7 (app `Obsidian.app`, macOS 12 or later), `visual-studio-code` 1.137.0 (app `Visual Studio Code.app`, binary `code`), `google-chrome` 153.0.8010.37 (app `Google Chrome.app`, macOS 13 or later).
- Homebrew formulae, from `https://formulae.brew.sh/api/formula/<name>.json` and `Homebrew/homebrew-core`: `emacs` 31.1 with `--without-x --without-ns`; `neovim` 0.12.5.
- MacPorts, from `https://ports.macports.org/api/v1/ports/<name>/` and `macports-ports/editors/emacs/Portfile`: `emacs` 31.1 (terminal build, installs `emacsclient`), `emacs-app` 31.1 (`Emacs.app` into `/Applications/MacPorts` only), `neovim` 0.12.4, `jq` 1.8.2, `zed` 1.18.0 (Brim's data tool, `zed.brimdata.io`); 404 for `obsidian`, `firefox-developer-edition`, `vscode`, `google-chrome`.
- GNU Emacs manual (`emacs-mirror/emacs` branch `emacs-30`, `doc/emacs/custom.texi`, `cmdargs.texi`, `misc.texi`; also the "Find Init" page on gnu.org): init file order and XDG rule, `--fg-daemon`, `-a ""` and `ALTERNATE_EDITOR` precedence. Emacs 31.1 `lisp/server.el` (installed copy): `server-socket-dir`. `etc/NEWS.28` and `cus-start.el`: `use-short-answers`, `fido-vertical-mode` in 28.1.
- launchd.plist(5) (`https://keith.github.io/xcode-man-pages/launchd.plist.5.html`): `KeepAlive`/`SuccessfulExit`, `RunAtLoad`, `ProcessType Interactive`.
- Doom Emacs (`doomemacs/core`, default branch `master`): `README.md` install commands; `bin/doom-install` `defcli! install` flags; `lisp/doom-cli.el` on `--no-` flags; `lisp/doom.el` on `DOOMDIR`. `github.com/doomemacs/doomemacs` returns a 301 to `github.com/doomemacs/core`.
- Spacemacs (`syl20bnr/spacemacs` branch `develop`): `README.md` clone command into `~/.emacs.d`; `core/core-dotspacemacs.el` on `~/.spacemacs`.
- Zed (`zed-industries/zed` branch `main`): `crates/paths/src/paths.rs` (`config_dir`, `settings_file`), `assets/settings/default.json` (`theme`, `buffer_font_family`, terminal `font_family`, `auto_install_extensions`), `assets/settings/initial_user_settings.json`, `crates/settings_content/src/theme.rs` (`ThemeSelection`), user settings parsed with `serde_json_lenient`. `catppuccin/zed` `extension.toml` (`id = "catppuccin"`) and `themes/catppuccin-mauve.json` (theme names).
- VS Code: `microsoft/vscode-docs` `docs/configure/settings.md` (macOS path) and `command-line.md` (`--install-extension`, `--list-extensions`); `microsoft/vscode` `workbenchThemeService.ts`, `themeConfiguration.ts`, `fontInfo.ts`, `terminalConfiguration.ts`. `catppuccin/vscode` `packages/catppuccin-vsc/package.json` (id `Catppuccin.catppuccin-vsc`, theme labels).
- LazyVim: `api.github.com/repos/LazyVim/starter/git/trees/main?recursive=1`, the starter's `init.lua` and `lua/config/lazy.lua`; `LazyVim/LazyVim` `README.md`, `lua/lazyvim/plugins/init.lua` (Neovim 0.11.2) and `lua/lazyvim/plugins/colorscheme.lua` (catppuccin); `catppuccin/nvim` `colors/`.
- Neovim v0.12.5: `src/nvim/msgpack_rpc/server.c`, `src/nvim/os/stdpaths.c`, `src/nvim/fileio.c`, `runtime/doc/remote.txt`, `runtime/doc/starting.txt` (E5422). Run locally with `nvim` 0.12.5: both socket locations, `--remote-send` of a `<Cmd>` key string, and E5422 loading `init.lua`.
- Run locally: the JSONC awk program under the one-true-awk built from source (the awk macOS ships) and gawk; `emacsclient -a false -e t` with `ALTERNATE_EDITOR=""` and no server returned 1 without starting a daemon (Emacs 31.1); the rendered LaunchAgent parsed by Python's `plistlib` with a space, `&`, `<` and `>` in two values.

Nothing this plan relies on is unverified except what the Real-Mac risk notes name: behaviour that needs macOS, launchd, a GUI session or the network.

### Placeholder scan

No `TBD`, `TODO`, `FIXME`, "implement later", "similar to Task N" or bare `...` standing in for code. Every shipped file and test appears in full in a `file=` block; the only partial blocks are `edit-old`/`edit-new` pairs, each quoting text that occurs exactly once in the file at that point. The "Run" lines and expected outputs name exact commands and exact per-suite counts.

### Name and type consistency across tasks

- `json_set_key <file> <key> <json-value>`, `json_merge_key <file> <key> <json-object>` and `json_quote <text>` (Task 1) are the only JSON helpers; Task 3 calls all three, Task 6 calls `json_set_key` and `json_quote`, CONTRIBUTING item 14 names all three with these signatures.
- The gate `state_done check "cap-$TEEUP_CAP" || TEEUP_CONFIGURING == $TEEUP_CAP` is spelled identically in `zed/theme-apply`, `zed/font-apply`, `vscode/theme-apply`, `vscode/font-apply` and CONTRIBUTING item 15; `emacs` and `neovim` hooks use the `state_done` half only (their `configure` never runs them); `TEEUP_CONFIGURING` is exported only by `zed/configure` and `vscode/configure`.
- Palette keys: `emacs_theme` (Task 2) is read only by `emacs.el.tpl`; `zed_theme`/`zed_extension` (Task 3) only by `zed.json.tpl`; `neovim_colorscheme` (Task 5) only by `neovim.lua.tpl`; `vscode_theme`/`vscode_extension` (Task 6) only by `vscode.json.tpl`. After Task 6 both palettes define all six, in the order `emacs_theme zed_theme zed_extension neovim_colorscheme vscode_theme vscode_extension`, and the README and CONTRIBUTING list the same six.
- Rendered files: `current/theme/<mode>/emacs.el` is loaded by `teeup-apply-theme` in `default/teeup/init.el`; `zed.json` and `vscode.json` are read with `jq -r .theme`/`.extension` by the matching `theme-apply`; `neovim.lua` is `dofile`d by `M.theme()` in `teeup.neovim`. Each path is built from `TEEUP_THEME_DIR` (hooks) or the state dir (Lisp and Lua) the same way `lib/theme.sh` writes it.
- `sh.teeup.emacs` appears identically in `emacs/configure` (plist `Label`, `plist_path`, `launchctl print`), `emacs/remove`, the emacs suite, the README and contract 3.
- `TEEUP_EMACS_FLAVOR` values `starter doom spacemacs none` are listed identically in `bootstrap`'s wizard loop, the `case` in `emacs/configure`, the README, the spec amendment and contract 2.
- Settings paths: `$HOME/.config/zed/settings.json` in both Zed hooks and the Zed suite; `$HOME/Library/Application Support/Code/User/settings.json` in both VS Code hooks and the VS Code suite; `$(user_config_dir)/emacs`, `$(user_config_dir)/doom` and `$(user_config_dir)/nvim` for the tools that honour `XDG_CONFIG_HOME`.
- Suite counts: 13 (`lib/json`), 26 (`capabilities/emacs`), 13 (`zed`), 6 each (`firefox-developer-edition`, `obsidian`, `chrome`), 14 (`neovim`), 13 (`vscode`); `tests/bootstrap.sh` 19 on `main`, 23 after Task 2, 24 after Task 4. The suite total rises by 1, 1, 1, 3, 1, 1 and 0 across Tasks 1 to 7.

### Seam with plan 3b, re-read against its text

- 3b's Real-Mac note lists this plan's `apps` values as the casks' `app` artifact names; contract 6 matches it (`Visual Studio Code`, `Google Chrome`, `Firefox Developer Edition`).
- 3b's `have` ignores shims, so `have nvim` and `have code` in the Neovim and VS Code hooks stay false when only a shim exists, which is the intent.
- 3b's `cap_check` additions (plain command names in `provides`, no duplicate providers, no paths in `apps`) accept every metadata file here: `nvim` and `code` are plain and unique (3b's `cursor` provides `cursor`).
- 3b's text names this plan `2026-09-13-redesign-phase3a-daily-editors.md` and its CONTRIBUTING note expects an item about "`lib/json.sh`"; the file is `2026-09-13-redesign-phase3a-daily-tier.md` and the helpers live in `lib/files.sh` (Decision 1). Neither affects execution: 3b's instruction is to append after whatever the last item is.
- Both plans append to `README.md` and `CONTRIBUTING.md` at different anchors (this plan: the core-tier paragraph and item 13; 3b: the command block, the per-machine paragraph and item 13). If 3b lands first, Task 7 Step 2's anchor still exists but its items must follow 3b's, as the step says.

### Deliberately deferred

- **Appearance changes do not re-run the hooks.** Zed and VS Code follow the system appearance themselves; the Emacs starter re-applies only on `ns-system-appearance-change-functions` (emacs-plus builds) or `C-c t`; Neovim picks the mode at start and on the next hook. An appearance-watching LaunchAgent belongs with phase 4's hooks work.
- **`teeup remove` and `teeup reset` for the editors.** `capabilities/emacs/remove` is written to the contract and tested through `cap_run`; the verbs, and resets of the Emacs and Neovim starter files through `refresh_config`, are phase 4.
- **Theme packages for Emacs.** The palette names built-in Modus themes. A `catppuccin-theme` MELPA install behind a toggle is a later, opt-in change.
- **Obsidian and Firefox theming.** Obsidian keeps themes per vault and Firefox per profile; neither has a file teeup can own without choosing a vault or a profile.
- **A `doctor` for the Emacs daemon** (`launchctl print` state, socket reachable with `emacsclient -a false -e t`) waits for phase 4's `teeup doctor`.
- **More themes.** Every new theme must define the six editor name keys (contract 5), which CONTRIBUTING item 15 now states.

### Mechanical verification of this text

Every code block in this plan was generated from, and then checked back against, a reviewed implementation built task by task in a scratch clone of `main` (`0adfb22`); nothing was typed into the plan by hand.

- **Transcription.** A script read this document, applied each task's `file=` blocks, `edit-old=`/`edit-new=` pairs (asserting each `edit-old` occurs exactly once) and `chmod +x` lines to a fresh clone of `main`, then ran that task's own shellcheck line, `./bin/teeup commands --check`, `git diff --check` and `./tests/run.sh`, and committed with the task's `git add` and `git commit` lines. After every commit the working tree was clean (the `git add` lines cover every file) and the tree was byte-identical to the reviewed commit. Results: `main` printed `All 30 suites passed.`; after Tasks 1 to 7, `All 31`, `32`, `33`, `36`, `37`, `38` and `38 suites passed.`; commands `--check`, shellcheck and `git diff --check` were silent after every task; Task 7's two `grep` checks printed nothing and `8`.
- **Failing first.** For each task, the test files alone were applied on top of the previous task and run: `lib/json` 0/13, `emacs` 1/26, `zed` 1/13, `firefox-developer-edition`, `obsidian` and `chrome` 0/6 each, `neovim` 1/14, `vscode` 1/13, matching each task's Step 2. The one test that passes early in four suites is the hook-gate test, which asserts that nothing happens.
- **bash 3.2.0.** The final state's full suite, run with a bash 3.2.0 build first on `PATH` (so `tests/run.sh` and every suite ran under 3.2): `All 38 suites passed.` Because the harness narrows `PATH` to `/usr/bin` inside each test, a second run also linked the same bash 3.2.0 into each test's `MOCK_BIN`, so `bin/teeup`, `bootstrap` and every capability script ran under 3.2 as they do on macOS: `All 38 suites passed.`
- **Whole-tree checks on the final state.** The CI shellcheck command (every `install`, `configure`, `remove`, `doctor`, `theme-apply` and `font-apply`, the libraries and every test) is clean; `luac -p` is clean on the seven shipped Lua files; Emacs 31.1 reads every form of the three shipped `.el` files; `teeup theme set catppuccin` under a throwaway `$HOME` renders the eight files the Verification section lists with no `{{` left.
- **Host independence.** The suites were run on a Linux machine that has `emacs`, `emacsclient`, `nvim`, `jq`, `lua` and a running Emacs server and Neovim in `XDG_RUNTIME_DIR`; they passed without touching any of them, which is what the `TEEUP_TEST_MISSING` entries, the `XDG_RUNTIME_DIR`/`TMPDIR` overrides and the hook gates are for. The two Elisp checks were also run against deliberately broken decoding (the `$'...'` branch of `teeup--unquote` disabled) and failed as they should.

### Review fixes (2026-09-14)

Applied against the `.superpowers/plan3/phase3-plans-review.md` findings (reviewed against `main` at `0adfb22`):

- **I2.** `emacs/install` now warns (naming `brew uninstall emacs` and a re-run) when Homebrew's terminal-only `emacs` formula is already installed, since the `emacs-app` cask's link step then skips `emacs`/`emacsclient`. `emacs/configure` prefers `Emacs.app/Contents/MacOS/Emacs` under `TEEUP_APPS_DIR` or `~/Applications` for the daemon's `ProgramArguments`, falling back to a PATH `emacs` only when no bundle is found. Two new tests (`install warns when the formula is already installed`, `configure prefers the app bundle over a PATH emacs`), both mock-only; suite count 24 -> 26.
- **I3.** `M.colorscheme_plugins`' `rosepine` key, which could never match (`plugin_for` keys on the colorscheme name's first run of `%w` characters, and `-` is not one), is renamed to `rose`. Added `plugin_for matches dashed colorscheme names`, a plain-`lua` assertion that `plugin_for("rose-pine-dawn")[1] == "rose-pine/neovim"` and `plugin_for("tokyonight-day")[1] == "folke/tokyonight.nvim"`; suite count for `capabilities/neovim` 13 -> 14.

All affected suite counts, "see it fail" and "passes" `Summary:` lines, and the Self-review's own tallies above are updated to match. Re-verified by transcription together with plan 3b's fixes; see plan 3b's Self-review for the combined run.
