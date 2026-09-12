# teeup Redesign, Phase 2b: Desktop Group Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the desktop half of the core tier — the macOS system library (`defaults`, LaunchAgents, appearance), the cross-tool theme system with one theme, the font system, and the `wezterm`, `aerospace`, `keyboard` and `macos-defaults` capabilities — so that `./bootstrap --dry-run` walks the whole core list and `teeup theme set catppuccin` renders every app's colours for both light and dark.

**Architecture:** Two new libraries (`lib/macos.sh`, `lib/theme.sh`) plus a small `lib/font.sh` extend the phase 1 runtime. Themes are semantic `key = "value"` palettes under `themes/<name>/{dark,light}.toml`; every capability that has colours ships `themed/*.tpl` templates with `{{ token }}` placeholders; `theme_set` renders all of them for both modes into a staging directory, swaps it into `~/.local/state/teeup/current/theme/`, and then runs each capability's optional `theme-apply` script. Fonts work the same way: one state file, one `font-apply` hook.

**Tech Stack:** bash 3.2 (macOS stock), BSD `sed`/`awk`, shellcheck, Homebrew (casks) with MacPorts degradation, Lua 5.4 for the WezTerm layer, TOML for AeroSpace and the palettes, the phase 1 mock-binary test harness.

**Spec:** `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md`. This plan covers the desktop entries of the spec's core list (`wezterm fonts aerospace keyboard macos-defaults theme`), spec section 7's "macOS defaults", "Fonts" and "Themes" paragraphs, and the `lib/macos.sh` and `lib/theme.sh` rows of section 4.

**Sibling plan and dependency:** `docs/superpowers/plans/2026-09-11-redesign-phase2a-shell-and-git.md` (plan 2a: shell and git group) is written and executed in parallel. **Plan 2b depends on plan 2a and must be executed after it**, for two reasons: 2a's Task 1 makes the `lib/` and `bin/teeup` fixes from the phase 1 final review (notably the `answers_set` key guard and `_pkg_backend_resolve` ordering) that every task here sits on top of, and 2a's `zsh` capability is what exports `TEEUP_APPEARANCE` and sources the `env.sh` this plan generates. Plan 2a does **not** depend on plan 2b: it ships a starship palette block with the marker strings this plan writes into, and if 2b never ran, that block simply stays as 2a shipped it.

---

## Global Constraints

- Bash 3.2 compatible everywhere: no `mapfile`, no `declare -A`, no `${var,,}`/`${var^^}` (use `tr '[:lower:]' '[:upper:]'`), no `readarray`, no `readlink -f`. Never reference a variable assigned earlier on the same `local` line. Use `10#$n` for arithmetic on user-typed numbers.
- macOS BSD tools: no GNU-only flags for `sed`, `date`, `mktemp`, `diff`, `cmp`, `sort`, `grep`, `readlink`, `stat`. Never rely on `\t` or `\n` in a BSD `sed` replacement. Tests run on Linux; the product runs on macOS.
- Capability scripts run as `bash -eu` with `lib/all.sh` sourced and `answers_load` done. **`set -e` is on**, and it fires only on the *last* command of a function or script: `[[ cond ]] && cmd` is safe mid-body (the failing `[[ ]]` is not the final command of the `&&` list) but exits the shell when it is the last statement of a function. Prefer the `if`/`else` form for statements that can be last, and append `|| true` / `|| warn "..."` to commands that are allowed to fail.
- Commands the tests mock are called **by name**, never by absolute path: `$MOCK_BIN` is first on `PATH` in the harness, and `/usr/bin/hidutil` would walk straight past it and mutate the CI runner. `/usr/bin` and `/usr/sbin` are always on `PATH` on macOS, so the bare name costs nothing. The one exception is a path inside a LaunchAgent plist, which launchd resolves itself with no `PATH` at all.
- `user_config_dir` (`lib/core.sh`, added by plan 2a's Task 1) is the single idiom for `~/.config`; never hand-roll `${XDG_CONFIG_HOME:-$HOME/.config}`.
- Capability scripts use no `local` (they are not functions), start with `#!/usr/bin/env bash` for shellcheck, and never call `sudo` (use `run_privileged`).
- Every mutation of the machine goes through `run_cmd`/`run_privileged`, or through a primitive with its own `DRY_RUN` guard (`write_managed_file`, `copy_config_once`, `append_once`, `_state_touch`, and the two new guards this plan adds: `_defaults_record` and `theme_render`). `DRY_RUN=true` must change nothing and must print `🔍 [DRY-RUN] Would execute: ...`.
- `capability` metadata is a sourced `KEY=value` file, not executable, no shebang: `summary group tier requires provides packages casks apps interactive`. `provides` must not name a command macOS ships.
- A capability whose `tier` is `core` must appear in `capabilities/core.list` or `cap_check` fails, so **each task appends its own capability to `core.list` in the same commit**. The exact file content after every task is given in that task.
- `shellcheck --severity=warning` clean on every new or edited script, including tests. Add a scoped `# shellcheck disable=SC2034` only on the line where SC2034 actually fires (shellcheck flags the last unread assignment of a variable in a file).
- Every task ends with `./tests/run.sh` green, `./bin/teeup commands --check` silent and exit 0, shellcheck clean, then **one** commit with a plain imperative subject. No `Co-Authored-By` and no "Generated with" trailer (user's global CLAUDE.md).
- **Suite counts in "Expected" blocks.** `tests/run.sh` ends with `All N suites passed.` Phase 1 left 13 suite files; plan 2a's self-review table ends at **21** (it adds eight capability suites and extends seven existing ones without creating them), and its Task 10 confirms `All 21 suites passed.` This plan therefore starts at 21 and each task below states the number it expects on that basis. Per-suite `run_test` counts come from the same 2a table: the only file both plans extend is `tests/lib/capability.sh` (10 today → 11 after 2a → 14 after this plan's Task 1), and `tests/bootstrap.sh` stays at 12 tests in both plans — both only change its `setup()`.
- Nothing in this phase has been run on a real Mac. Each task's **Real-Mac risk** note says what can only be proven there.

---

## Contracts this plan publishes

These four contracts are the seams between plan 2a and plan 2b. They are stated once here and repeated at the task that implements them; nothing else crosses the plan boundary.

1. **The shell `env.sh`.** `theme_set` renders `capabilities/theme/themed/env.sh.tpl` once per mode to
   `~/.local/state/teeup/current/theme/dark/env.sh` and `~/.local/state/teeup/current/theme/light/env.sh`
   (i.e. `$TEEUP_STATE_DIR/current/theme/<mode>/env.sh`). Each file is POSIX-sourceable and exports
   `TEEUP_THEME_MODE`, `TEEUP_THEME_ACCENT` and `BAT_THEME`. **Plan 2a's zsh default layer sources
   `"${XDG_STATE_HOME:-$HOME/.local/state}/teeup/current/theme/$TEEUP_APPEARANCE/env.sh"` when that file exists**, after it has exported `TEEUP_APPEARANCE`, and guards the source so a shell still starts before the first `teeup theme set`.
2. **`TEEUP_APPEARANCE`.** Plan 2a's zsh layer is the only producer: it exports `dark` or `light` at shell start from `defaults read -g AppleInterfaceStyle` (exit 1 means light). This plan never sets it. For code that runs outside an interactive shell — `teeup theme set`, a `theme-apply` script, a LaunchAgent — `lib/macos.sh` provides the identical computation as the function `appearance`, printing `dark` or `light`. Two producers, one definition, so a script and a shell can never disagree.
3. **The starship palette block.** Plan 2a ships `~/.config/starship.toml` with a `palette = "teeup-dark"` line immediately followed by an empty managed region delimited by the exact lines `# teeup:theme-palette:start` and `# teeup:theme-palette:end`. **All three must sit at the very top of the file, before the first `[table]` header.** That placement is load-bearing and not cosmetic: in TOML a bare key after a table header belongs to that table, so a `palette =` line further down parses as `cmd_duration.palette` and starship never sees a root palette selection — the rendered `[palettes.*]` tables would be inert and no test could tell. Plan 2a is being changed to put the block at the top; this plan's `capabilities/theme/theme-apply` refuses to touch a file where the start marker appears after the first `[` line, and warns instead, so the two plans cannot silently disagree.
   `theme-apply` replaces everything between the markers with `[palettes.teeup-dark]` and `[palettes.teeup-light]` tables rendered from the current theme, and rewrites the first line matching `^palette *=` to the palette matching `$(appearance)`. The palette tables define exactly these colour names: `accent selection muted background dark_background lighter_background foreground light_foreground bright_foreground black white red orange yellow green cyan blue magenta`. Plan 2a's `starship.toml` may reference any of them (`style = "fg:accent"`), and `black`/`white` are included because 2a's shipped block defines them. When the file or the markers are missing, `theme-apply` logs one line and does nothing.
4. **The font state file.** `~/.local/state/teeup/current/font` (i.e. `$TEEUP_STATE_DIR/current/font`) holds one line: the font family name as an application would name it, e.g. `JetBrainsMono Nerd Font`. WezTerm reads it at startup with a built-in fallback; `teeup install font <name>` rewrites it and then runs every capability's `font-apply`.

Two further contracts are internal to this plan but are what phase 3's capabilities (Neovim, Zed, VS Code) will implement:

- **`capabilities/<cap>/theme-apply`** — optional, executable, same runtime as `install`/`configure` (`bash -eu`, `lib/all.sh` loaded, answers sourced, `TEEUP_CAP`/`TEEUP_CAP_DIR` exported). `theme_set` runs it after the swap with `TEEUP_THEME_DIR` (= `$TEEUP_STATE_DIR/current/theme`) and `TEEUP_THEME_NAME` exported. Its job is to push the already-rendered files into the app (touch a config so it reloads, patch a JSON key, send an IPC message). A failure warns and never aborts the theme switch.
- **`capabilities/<cap>/font-apply`** — same runtime and same failure policy, run by `font_set` after the state file is written, with `TEEUP_FONT_FAMILY` exported.

---

## File structure

| Path | Responsibility |
|---|---|
| `lib/macos.sh` | `defaults_write`, `defaults_restore`, `launchagent_install`, `appearance`. |
| `lib/theme.sh` | `theme_dir`, `theme_list`, `theme_current`, `theme_palette_load`, `theme_render`, `theme_templates`, `theme_set`. |
| `lib/font.sh` | `font_cask`, `font_family`, `font_table`, `font_current`, `font_set`. |
| `lib/capability.sh` | gains `cap_run_optional` (run a verb only when the capability ships it). |
| `lib/all.sh` | gains `macos`, `theme` and `font` to its source list. |
| `themes/catppuccin/dark.toml`, `themes/catppuccin/light.toml` | The one shipped theme: Catppuccin Mocha and Catppuccin Latte as semantic palettes. |
| `capabilities/theme/` | `theme_set` wrapper capability; owns `themed/env.sh.tpl`, `themed/starship-palette.toml.tpl` and the `theme-apply` that patches `~/.config/starship.toml`. |
| `capabilities/fonts/` | JetBrainsMono Nerd Font cask and the default entry in the font state file. |
| `capabilities/wezterm/` | WezTerm cask, thin `~/.config/wezterm/wezterm.lua`, the thick `default/teeup/wezterm.lua` layer, `themed/wezterm.lua.tpl`, `theme-apply`, `font-apply`. |
| `capabilities/aerospace/` | AeroSpace cask from `nikitabobko/tap` and the i3-style `aerospace.toml`; prints the Accessibility step, `doctor` re-checks it. |
| `capabilities/keyboard/` | Caps Lock → Control through `hidutil`, persisted as the `sh.teeup.keyboard` LaunchAgent. |
| `capabilities/macos-defaults/` | The opinionated `defaults write` set, each one recorded so `remove` can restore it. |
| `bin/teeup` | gains `teeup theme set|list|current` and `teeup install font <name>`. |
| `tests/lib/{macos,theme,font}.sh`, `tests/capabilities/{theme,fonts,wezterm,aerospace,keyboard,macos-defaults}.sh` | One suite per new library and capability. |

---

### Task 1: `lib/macos.sh` and the optional-verb runner

**Files:**
- Create: `lib/macos.sh`
- Modify: `lib/all.sh`, `lib/capability.sh`, `tests/lib/capability.sh`, `tests/bootstrap.sh`
- Test: `tests/lib/macos.sh`

**Interfaces:**
- Consumes: `run_cmd`, `log`, `ok`, `warn`, `die` (`lib/core.sh`); `write_managed_file` (`lib/files.sh`); `TEEUP_STATE_DIR` (`lib/core.sh`); `cap_dir`, `cap_run` (`lib/capability.sh`).
- Produces:
  - `defaults_write <domain> <key> <type> <value>` — records the prior state under `$TEEUP_STATE_DIR/defaults/<domain>.<key>` as `absent` or `<type>:<value>` (only the first time), then `run_cmd defaults write <domain> <key> <type> <value>`.
  - `defaults_restore <domain> <key>` — replays that record with `defaults delete` or a typed `defaults write`, then removes the record.
  - `launchagent_install <label>` — plist content on stdin, written to `~/Library/LaunchAgents/<label>.plist` with `write_managed_file`, then `launchctl bootout` (failure ignored) and `launchctl bootstrap`.
  - `appearance` — prints `dark` or `light`.
  - `cap_run_optional <name> <verb>` — runs `capabilities/<name>/<verb>` when the file exists, warns instead of failing, always returns 0.
- Every later task in this plan consumes at least one of these.

**Real-Mac risk:** `launchctl bootout gui/<uid> <plist>` exits non-zero when the agent is not loaded — expected and ignored — but on a real Mac it can also fail with `Operation not permitted` if the plist has group/other write permission. Verified only on hardware.

- [ ] **Step 1: Write the failing test `tests/lib/macos.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false
}

# defaults read exits 1 for every key: a fresh Mac that has never set them.
mock_defaults_absent() {
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) exit 1 ;;
  *) exit 0 ;;
esac
EOF2
}

test_defaults_write_records_absent_and_writes() {
  setup
  mock_defaults_absent
  defaults_write com.apple.finder ShowPathbar -bool true >/dev/null
  local record
  record="$TEST_HOME/.local/state/teeup/defaults/com.apple.finder.ShowPathbar"
  assert_file_exists "$record" || return 1
  assert_equals "absent" "$(cat "$record")" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "defaults write com.apple.finder ShowPathbar -bool true" || return 1
  cleanup_test_env
}

test_defaults_write_records_the_prior_value() {
  setup
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) echo 0; exit 0 ;;
  *) exit 0 ;;
esac
EOF2
  defaults_write com.apple.dock autohide -bool true >/dev/null
  assert_equals "-bool:0" "$(cat "$TEST_HOME/.local/state/teeup/defaults/com.apple.dock.autohide")" || return 1
  cleanup_test_env
}

test_defaults_write_never_overwrites_an_existing_record() {
  setup
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) echo 1; exit 0 ;;
  *) exit 0 ;;
esac
EOF2
  mkdir -p "$TEST_HOME/.local/state/teeup/defaults"
  printf 'absent\n' > "$TEST_HOME/.local/state/teeup/defaults/com.apple.dock.autohide"
  defaults_write com.apple.dock autohide -bool true >/dev/null
  assert_equals "absent" "$(cat "$TEST_HOME/.local/state/teeup/defaults/com.apple.dock.autohide")" || return 1
  cleanup_test_env
}

test_defaults_write_dry_run_records_nothing() {
  setup
  mock_defaults_absent
  DRY_RUN=true
  local out
  out="$(defaults_write com.apple.finder ShowPathbar -bool true)"
  assert_contains "$out" "[DRY-RUN] Would execute: defaults write com.apple.finder ShowPathbar -bool true" || return 1
  assert_contains "$out" "[DRY-RUN] Would record defaults/com.apple.finder.ShowPathbar" || return 1
  [[ ! -e "$TEST_HOME/.local/state/teeup/defaults/com.apple.finder.ShowPathbar" ]] || { echo "record written in dry run"; return 1; }
  cleanup_test_env
}

test_defaults_restore_deletes_when_absent() {
  setup
  mock_defaults_absent
  mkdir -p "$TEST_HOME/.local/state/teeup/defaults"
  printf 'absent\n' > "$TEST_HOME/.local/state/teeup/defaults/com.apple.finder.ShowPathbar"
  defaults_restore com.apple.finder ShowPathbar >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "defaults delete com.apple.finder ShowPathbar" || return 1
  [[ ! -e "$TEST_HOME/.local/state/teeup/defaults/com.apple.finder.ShowPathbar" ]] || { echo "record kept"; return 1; }
  cleanup_test_env
}

test_defaults_restore_rewrites_the_prior_value() {
  setup
  mock_defaults_absent
  mkdir -p "$TEST_HOME/.local/state/teeup/defaults"
  printf -- '-bool:0\n' > "$TEST_HOME/.local/state/teeup/defaults/com.apple.dock.autohide"
  defaults_restore com.apple.dock autohide >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "defaults write com.apple.dock autohide -bool 0" || return 1
  cleanup_test_env
}

test_defaults_restore_without_a_record_is_a_noop() {
  setup
  mock_defaults_absent
  local out
  out="$(defaults_restore com.apple.dock autohide)"
  assert_contains "$out" "No recorded value for com.apple.dock autohide" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "defaults delete" || return 1
  cleanup_test_env
}

test_launchagent_install_writes_and_reloads() {
  setup
  mock_command launchctl 0 ""
  launchagent_install sh.teeup.test >/dev/null <<'EOF2'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>Label</key><string>sh.teeup.test</string></dict></plist>
EOF2
  local plist
  plist="$TEST_HOME/Library/LaunchAgents/sh.teeup.test.plist"
  assert_file_exists "$plist" || return 1
  assert_contains "$(cat "$plist")" "sh.teeup.test" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "launchctl bootout gui/501 $plist" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "launchctl bootstrap gui/501 $plist" || return 1
  cleanup_test_env
}

test_launchagent_install_is_idempotent_on_the_file() {
  setup
  mock_command launchctl 0 ""
  local plist body out
  plist="$TEST_HOME/Library/LaunchAgents/sh.teeup.test.plist"
  body='<plist version="1.0"><dict/></plist>'
  printf '%s\n' "$body" | launchagent_install sh.teeup.test >/dev/null
  out="$(printf '%s\n' "$body" | launchagent_install sh.teeup.test)"
  assert_contains "$out" "Already current: $plist" || return 1
  cleanup_test_env
}

test_launchagent_install_dry_run_writes_nothing() {
  setup
  mock_command launchctl 0 ""
  # shellcheck disable=SC2034  # last assignment in the file; read by run_cmd
  DRY_RUN=true
  local out
  out="$(printf '<plist/>\n' | launchagent_install sh.teeup.test)"
  assert_contains "$out" "[DRY-RUN] Would write $TEST_HOME/Library/LaunchAgents/sh.teeup.test.plist" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: launchctl bootstrap gui/501" || return 1
  [[ ! -e "$TEST_HOME/Library/LaunchAgents/sh.teeup.test.plist" ]] || { echo "plist written in dry run"; return 1; }
  cleanup_test_env
}

test_appearance_reads_the_interface_style() {
  setup
  mock_command_script defaults <<'EOF2'
case "$2" in
  -g) echo Dark; exit 0 ;;
esac
exit 1
EOF2
  assert_equals "dark" "$(appearance)" || return 1
  mock_defaults_absent
  assert_equals "light" "$(appearance)" || return 1
  cleanup_test_env
}

echo "lib/macos.sh"
run_test "defaults_write records absent and writes" test_defaults_write_records_absent_and_writes
run_test "defaults_write records the prior value" test_defaults_write_records_the_prior_value
run_test "defaults_write never overwrites a record" test_defaults_write_never_overwrites_an_existing_record
run_test "defaults_write dry run records nothing" test_defaults_write_dry_run_records_nothing
run_test "defaults_restore deletes when absent" test_defaults_restore_deletes_when_absent
run_test "defaults_restore rewrites the prior value" test_defaults_restore_rewrites_the_prior_value
run_test "defaults_restore without a record is a no-op" test_defaults_restore_without_a_record_is_a_noop
run_test "launchagent_install writes and reloads" test_launchagent_install_writes_and_reloads
run_test "launchagent_install is idempotent" test_launchagent_install_is_idempotent_on_the_file
run_test "launchagent_install dry run writes nothing" test_launchagent_install_dry_run_writes_nothing
run_test "appearance reads the interface style" test_appearance_reads_the_interface_style
print_summary
```

Run: `bash tests/lib/macos.sh`
Expected: every test FAILs with `defaults_write: command not found` — the library does not exist yet.

- [ ] **Step 2: Write `lib/macos.sh`**

```bash
#!/usr/bin/env bash
# macos.sh - the three native macOS seams teeup needs: the defaults database,
# LaunchAgents, and the light/dark appearance.
# Requires core.sh and files.sh.

_defaults_record_path() { printf '%s/defaults/%s.%s\n' "$TEEUP_STATE_DIR" "$1" "$2"; }

# Writing the record is a mutation of the machine's state dir, so it gets the
# same dry-run guard as state.sh's markers rather than going through run_cmd
# (the content is data, not a command line).
_defaults_record() {
  local record="$1" content="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would record ${record#"$TEEUP_STATE_DIR"/} as $content"
    return 0
  fi
  mkdir -p "$(dirname "$record")"
  printf '%s\n' "$content" > "$record"
}

# defaults_write <domain> <key> <type> <value>
# Records what was there before the first time teeup touches a key, so
# `teeup remove macos-defaults` can put the machine back. The record is never
# refreshed: the value teeup itself wrote is not a prior value.
# Only the first line of a prior value is kept; every key teeup writes is a
# scalar (bool, int or string), never a dict or an array.
defaults_write() {
  local domain="$1" key="$2" type="$3" value="$4" record prior
  record="$(_defaults_record_path "$domain" "$key")"
  if [[ ! -f "$record" ]]; then
    if defaults read "$domain" "$key" >/dev/null 2>&1; then
      prior="$(defaults read "$domain" "$key" 2>/dev/null | head -1)"
      _defaults_record "$record" "$type:$prior"
    else
      _defaults_record "$record" "absent"
    fi
  fi
  run_cmd defaults write "$domain" "$key" "$type" "$value"
}

# defaults_restore <domain> <key>
defaults_restore() {
  local domain="$1" key="$2" record recorded type value
  record="$(_defaults_record_path "$domain" "$key")"
  if [[ ! -f "$record" ]]; then
    log "No recorded value for $domain $key; leaving it alone."
    return 0
  fi
  recorded="$(cat "$record")"
  if [[ "$recorded" == "absent" ]]; then
    run_cmd defaults delete "$domain" "$key" || warn "Could not delete $domain $key."
  else
    type="${recorded%%:*}"
    value="${recorded#*:}"
    run_cmd defaults write "$domain" "$key" "$type" "$value"
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would clear ${record#"$TEEUP_STATE_DIR"/}"
  else
    rm -f "$record"
  fi
}

# launchagent_install <label>   (plist content on stdin)
# Always reloads, even when the plist did not change: bootout is the cheap way
# to make the agent match the file, and it is how a manually unloaded agent
# repairs itself on the next `teeup configure`.
launchagent_install() {
  local label="$1" dir plist uid
  dir="$HOME/Library/LaunchAgents"
  plist="$dir/$label.plist"
  [[ -d "$dir" ]] || run_cmd mkdir -p "$dir"
  write_managed_file "$plist" "LaunchAgent $label"
  uid="$(id -u)"
  # bootout exits non-zero when the agent is not loaded. That is the normal
  # first-install case, so the failure is ignored. Do not redirect run_cmd:
  # its dry-run preview goes to stdout and a redirection would hide it.
  run_cmd launchctl bootout "gui/$uid" "$plist" || true
  run_cmd launchctl bootstrap "gui/$uid" "$plist" || warn "Could not load $label; run: launchctl bootstrap gui/$uid $plist"
}

# appearance -> dark | light
# `defaults read -g AppleInterfaceStyle` prints "Dark" in dark mode and exits 1
# in light mode, which is also what plan 2a's zsh layer uses for
# TEEUP_APPEARANCE. Same rule in both places, so a script and a shell agree.
appearance() {
  local style
  if style="$(defaults read -g AppleInterfaceStyle 2>/dev/null)"; then
    case "$style" in
      *Dark*) printf 'dark\n'; return 0 ;;
    esac
  fi
  printf 'light\n'
}
```

- [ ] **Step 3: Add `macos` to `lib/all.sh`**

Replace the loop line in `lib/all.sh`:

```bash
for _teeup_lib in files state answers pkg ui capability; do
```

with:

```bash
for _teeup_lib in files state answers pkg ui capability macos; do
```

`macos.sh` comes after `files.sh` because `launchagent_install` calls `write_managed_file`.

- [ ] **Step 4: Add `cap_run_optional` to `lib/capability.sh`**

Append to the end of `lib/capability.sh`:

```bash
# cap_run_optional <name> <verb>
# The hook runner behind theme-apply and font-apply: a capability that has no
# opinion about themes simply ships no theme-apply, and a broken hook warns
# instead of aborting the switch (Omarchy's hook rule). cap_run itself is the
# strict version and stays that way, because `teeup configure nope` must fail.
cap_run_optional() {
  local name="$1" verb="$2"
  if cap_skipped "$name"; then return 0; fi
  [[ -f "$(cap_dir "$name")/$verb" ]] || return 0
  cap_run "$name" "$verb" || warn "$name $verb failed; continuing."
  return 0
}
```

The `cap_skipped` guard matters because a machine that sets `TEEUP_SKIP="aerospace"` has no AeroSpace to re-theme; without it a theme switch would still run its hook.

- [ ] **Step 5: Cover `cap_run_optional` in `tests/lib/capability.sh`**

Insert these two functions immediately before the final `echo "lib/capability.sh"` line:

```bash
test_run_optional_skips_a_missing_verb() {
  setup
  local out rc=0
  out="$(cap_run_optional alpha theme-apply 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_equals "" "$out" || return 1
  cleanup_test_env
}

test_run_optional_respects_teeup_skip() {
  setup
  printf '#!/usr/bin/env bash\necho "hook:alpha"\n' > "$TEEUP_CAPS_DIR/alpha/theme-apply"
  chmod +x "$TEEUP_CAPS_DIR/alpha/theme-apply"
  export TEEUP_SKIP="alpha"
  local out
  out="$(cap_run_optional alpha theme-apply 2>&1)"
  assert_equals "" "$out" "a skipped capability gets no hook" || return 1
  unset TEEUP_SKIP
  cleanup_test_env
}

test_run_optional_warns_but_succeeds_on_failure() {
  setup
  printf '#!/usr/bin/env bash\necho "hook:alpha dir=$TEEUP_THEME_DIR"\nfalse\n' > "$TEEUP_CAPS_DIR/alpha/theme-apply"
  chmod +x "$TEEUP_CAPS_DIR/alpha/theme-apply"
  export TEEUP_THEME_DIR=/tmp/theme
  local out rc=0
  out="$(cap_run_optional alpha theme-apply 2>&1)" || rc=$?
  assert_success "$rc" "an optional hook must never fail its caller" || return 1
  assert_contains "$out" "hook:alpha dir=/tmp/theme" || return 1
  assert_contains "$out" "alpha theme-apply failed; continuing." || return 1
  unset TEEUP_THEME_DIR
  cleanup_test_env
}
```

and these two lines immediately before `print_summary`:

```bash
run_test "run_optional skips a missing verb" test_run_optional_skips_a_missing_verb
run_test "run_optional respects TEEUP_SKIP" test_run_optional_respects_teeup_skip
run_test "run_optional warns but succeeds on failure" test_run_optional_warns_but_succeeds_on_failure
```

- [ ] **Step 6: Settle what `tests/bootstrap.sh` still needs**

`bootstrap --dry-run` runs every capability in `core.list`, so each of this plan's capabilities executes inside the bootstrap suite under *that* suite's mocks. Plan 2a already grew `setup()` for its own eight capabilities; after 2a it reads (phase 1 lines plus 2a's blocks):

```bash
setup() {
  setup_test_env
  mock_macos_base
  mock_command softwareupdate 0 ""
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  mock_command security 44 ""
  mock_command dscl 0 "UserShell: /bin/zsh"
  mock_command chsh 0 ""
  mock_command defaults 1 ""
  mock_command ssh-keygen 0 ""
  mock_command ssh-add 0 ""
  mock_command_script gh <<'EOF2'
# (2a's gh mock body: "auth status" exits 1, "ssh-key list" is empty)
EOF2
  mock_command_script mise <<'EOF2'
# (2a's mise mock body: "which" exits 1, everything else exits 0)
EOF2
  export TEEUP_TEST_MISSING="brew gum jq starship rg fd fzf bat eza zoxide yq btop tldr dust gpg delta git-lfs lazygit"
  export TEEUP_NO_GUM=1
  export DRY_RUN=true
}
```

Walk this plan's six capabilities against it. **This task changes nothing in that file**, and exactly one line is added later, by Task 5, when `aerospace` joins the manifest. Here is the reasoning, once, so no later task has to repeat it:

- **`defaults`** — already mocked by 2a for the `zsh` capability's appearance read, and `mock_command defaults 1 ""` is exactly right for `defaults_write` too: the `defaults read` probe (the one call outside `run_cmd`) exits 1, taking the `absent` branch, and every `defaults write` goes through `run_cmd`, which never executes under `DRY_RUN=true`. Do **not** add a second `defaults` mock.
- **`launchctl`, `hidutil`, `killall`** — reached only through `run_cmd`, and this suite is `DRY_RUN=true` throughout, so they are never executed. Mocking them would be dead code that falsely suggests the keyboard capability is covered here; the suite that really runs them is `tests/capabilities/keyboard.sh` (Task 6), which mocks them itself.
- **`brew`** — 2a's mock answers `list` with exit 1 and everything else with 0, which is what `cask_install wezterm`, `cask_install font-jetbrains-mono-nerd-font` and `aerospace`'s `brew tap … | grep -qx` need: not installed, not tapped, both printed rather than run.
- **`TEEUP_TEST_MISSING`** — needs no new entries. Nothing in this plan's capabilities branches on `have <tool>`: the cask path never consults `have`, and `pkg_install wezterm wezterm` is only reachable on the MacPorts branch, which this suite does not take.
- **`pgrep`, `luac`** — used only by `capabilities/aerospace/doctor` and `tests/capabilities/wezterm.sh`, neither of which `bootstrap` runs.
- **`/Applications`** — the one real leak. `aerospace/configure` probes it outside `run_cmd`, so the dry-run walk differs between a Mac that has AeroSpace and one that does not. Task 5 closes it with one `export TEEUP_APPS_DIR=…` line, in the same commit that puts `aerospace` in `core.list`.

The suite keeps its twelve tests throughout; only `setup()` changes, in Task 5, and Task 8 adds two assertions to one existing test.

- [ ] **Step 7: Run everything**

```bash
bash tests/lib/macos.sh
bash tests/lib/capability.sh
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning lib/*.sh tests/lib/macos.sh tests/lib/capability.sh tests/bootstrap.sh
```

Expected: `lib/macos.sh` prints `Summary: 11/11 passed`; `lib/capability.sh` prints `Summary: 14/14 passed` (10 from phase 1, one added by plan 2a's Task 1, three added here); `commands --check` prints nothing; `./tests/run.sh` ends with `All 22 suites passed.`; shellcheck prints nothing.

- [ ] **Step 8: Commit**

```bash
git add lib/macos.sh lib/all.sh lib/capability.sh tests/lib/macos.sh tests/lib/capability.sh
git commit -m "Add the macOS defaults, LaunchAgent and appearance library"
```

(`tests/bootstrap.sh` is deliberately absent: Step 6 established that it needs no change until Task 5.)

---

### Task 2: `lib/theme.sh`, the Catppuccin palettes and the `theme` capability

**Files:**
- Create: `lib/theme.sh`, `themes/catppuccin/dark.toml`, `themes/catppuccin/light.toml`, `capabilities/theme/{capability,install,configure,theme-apply}`, `capabilities/theme/themed/{env.sh.tpl,starship-palette.toml.tpl}`
- Modify: `lib/all.sh`, `bin/teeup`, `capabilities/core.list`
- Test: `tests/lib/theme.sh`, `tests/capabilities/theme.sh`

**Interfaces:**
- Consumes: `run_cmd`, `log`, `ok`, `warn`, `err`, `die`, `TEEUP_STATE_DIR`, `TEEUP_CONFIG_DIR` (`lib/core.sh`); `write_managed_file` (`lib/files.sh`); `cap_list`, `cap_run_optional`, `TEEUP_CAPS_DIR` (`lib/capability.sh`, Task 1); `appearance` (`lib/macos.sh`, Task 1); `answers_get` (`lib/answers.sh`).
- Produces:
  - `theme_dir <name>` → the palette directory (`~/.config/teeup/themes/<name>` wins over `themes/<name>`); prints an error and returns 1 when unknown.
  - `theme_list` → one theme name per line, deduplicated.
  - `theme_current` → the applied theme name, or `none`.
  - `theme_palette_load <file>` → exports `TEEUP_COLOR_<KEY>` for every `key = "value"` line, sets `TEEUP_COLOR_KEYS` and builds `TEEUP_COLOR_SED`.
  - `theme_render <tpl> <out>` → applies `TEEUP_COLOR_SED` to one template; dry-run prints `[DRY-RUN] Would render <tpl> -> <out>` and writes nothing.
  - `theme_templates` → every template path, user templates from `~/.config/teeup/themed/*.tpl` first, then `capabilities/*/themed/*.tpl`.
  - `theme_set <name>` → renders both modes into `$TEEUP_STATE_DIR/current/next-theme/`, swaps it onto `current/theme/`, writes `current/theme.name`, exports `TEEUP_THEME_DIR` and `TEEUP_THEME_NAME`, and runs every `theme-apply` hook.
  - `bin/teeup theme set|list|current`.
  - **The `env.sh` contract for plan 2a:** `$TEEUP_STATE_DIR/current/theme/<dark|light>/env.sh`, exporting `TEEUP_THEME_MODE`, `TEEUP_THEME_ACCENT`, `BAT_THEME`.
  - **The starship contract for plan 2a:** the `# teeup:theme-palette:start` / `# teeup:theme-palette:end` markers and the `palette = "teeup-<mode>"` root key in `~/.config/starship.toml`.

**Decisions made here (carried through the rest of the plan):**

1. **The dark palette is Catppuccin Mocha and the light one is Catppuccin Latte**, with the exact hex values Omarchy uses in `/usr/share/omarchy/themes/catppuccin/colors.toml` and `catppuccin-latte/colors.toml`, so the user's Arch desktop and their Mac render the same colours from the same key names.
2. **A palette is a key/value table, not strictly colours.** `mode` and `bat_theme` are ordinary keys; only values that look like `#rrggbb` get a `_rgb` variant. That is what lets `env.sh.tpl` pull `BAT_THEME` out of the same file as the colours instead of hard-coding a second lookup table.
3. **`BAT_THEME` is `OneHalfDark` / `OneHalfLight`.** Both are built into `bat`, so the theme works on a fresh Mac with nothing extra installed, and both are muted-pastel enough to sit beside Catppuccin. A real Catppuccin `.tmTheme` would have to be downloaded into `bat`'s config dir, which is a phase 4 concern.
4. **The starship block is written by `capabilities/theme/theme-apply`, not by a `capabilities/starship/theme-apply`**, because plan 2a owns that directory and this plan must not edit it. The only coupling is the contract above (one path, two marker strings, one root key). Phase 4 can move the script into `capabilities/starship/` without changing a byte of what it renders.
5. **The swap is "move aside, move in, delete"**, not an `mv` over a live directory: `current/theme` → `current/theme.prev`, `current/next-theme` → `current/theme`, then `rm -rf current/theme.prev`. The window in which `current/theme` does not exist is one `mv`, and a reader that misses it falls back to its built-in defaults.
6. **Idempotency for the theme pipeline is content equality, not a skip.** `theme_set` always re-renders, because that is exactly what `teeup update` needs it to do after a template changes. The test asserts that two consecutive runs leave byte-identical files rather than looking for an "Already ..." line.
7. **An unknown theme warns and falls back to `catppuccin`; it never fails.** `theme` is a **core** capability, so a non-zero `configure` makes `bootstrap` call `die "Core capability theme failed"` and abort the whole first run. The phase 1 wizard offers four theme names and only `catppuccin` ships in this phase, so three of the four answers would brick a fresh Mac. Falling back turns that into one warning line and a themed machine. Task 8 closes the other half by driving the wizard's options from `theme_list`, so a user cannot pick a theme that does not exist in the first place. Only a missing `catppuccin` — a broken checkout — still fails.

**Real-Mac risk:** `appearance` depends on `defaults read -g AppleInterfaceStyle` exiting 1 in light mode, which is documented Apple behaviour but has never been exercised by this code on hardware. Switching macOS appearance at runtime does **not** re-run `theme-apply`; the starship palette follows on the next `teeup theme set`. An appearance-watching LaunchAgent is deferred to phase 4.

- [ ] **Step 1: Write the two palettes**

`themes/catppuccin/dark.toml`:

```toml
# Catppuccin Mocha, as a teeup semantic palette. The keys are roles, not
# colour names, so a template never has to know which theme is loaded.
# Values match Omarchy's themes/catppuccin/colors.toml on purpose: the same
# palette renders the Arch desktop and this Mac.
mode = "dark"

# Not a colour: bat has no Catppuccin theme built in, so the palette names the
# closest built-in. Rendered into env.sh as BAT_THEME.
bat_theme = "OneHalfDark"

accent = "#89b4fa"
selection = "#45475a"
muted = "#585b70"

background = "#1e1e2e"
dark_background = "#161622"
darker_background = "#101019"
lighter_background = "#313244"

foreground = "#cdd6f4"
dark_foreground = "#6c7086"
light_foreground = "#bac2de"
bright_foreground = "#cdd6f4"

red = "#f38ba8"
yellow = "#f9e2af"
orange = "#f6b6ab"
green = "#a6e3a1"
cyan = "#94e2d5"
blue = "#89b4fa"
magenta = "#f5c2e7"
brown = "#7b5b55"

bright_red = "#f38ba8"
bright_yellow = "#f9e2af"
bright_green = "#a6e3a1"
bright_cyan = "#94e2d5"
bright_blue = "#89b4fa"
bright_magenta = "#f5c2e7"
```

`themes/catppuccin/light.toml`:

```toml
# Catppuccin Latte. Same keys as dark.toml, so every template renders in both
# modes without a single conditional.
mode = "light"

bat_theme = "OneHalfLight"

accent = "#1e66f5"
selection = "#ccd0da"
muted = "#acb0be"

background = "#eff1f5"
dark_background = "#e3e4e8"
darker_background = "#d7d8dc"
lighter_background = "#dce0e8"

foreground = "#4c4f69"
dark_foreground = "#9ca0b0"
light_foreground = "#5c5f77"
bright_foreground = "#4c4f69"

red = "#d20f39"
yellow = "#df8e1d"
orange = "#d84e2b"
green = "#40a02b"
cyan = "#179299"
blue = "#1e66f5"
magenta = "#ea76cb"
brown = "#6c2715"

bright_red = "#d20f39"
bright_yellow = "#df8e1d"
bright_green = "#40a02b"
bright_cyan = "#179299"
bright_blue = "#1e66f5"
bright_magenta = "#ea76cb"
```

- [ ] **Step 2: Write the failing test `tests/lib/theme.sh`**

```bash
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
run_test "set renders both modes and runs hooks" test_set_renders_both_modes_and_runs_hooks
run_test "set is content idempotent" test_set_is_content_idempotent
run_test "user template wins over the capability one" test_user_template_wins_over_the_capability_one
run_test "set dry run writes nothing" test_set_dry_run_writes_nothing
run_test "set unknown theme falls back to catppuccin" test_set_unknown_theme_falls_back_to_catppuccin
run_test "set fails when the fallback itself is missing" test_set_fails_when_the_fallback_itself_is_missing
run_test "list and current" test_list_and_current
print_summary
```

Run: `bash tests/lib/theme.sh`
Expected: all nine FAIL with `theme_palette_load: command not found`.

- [ ] **Step 3: Write `lib/theme.sh`**

```bash
#!/usr/bin/env bash
# theme.sh - semantic palettes, {{ token }} templates, staged swap, hooks.
# A theme is two files (dark.toml, light.toml) of `key = "value"` lines. Every
# capability that has colours ships themed/*.tpl; theme_set renders all of them
# for both modes, swaps the result into place and tells each capability to
# pick it up. Requires core.sh, files.sh and capability.sh.

TEEUP_THEMES_DIR="${TEEUP_THEMES_DIR:-$TEEUP_PATH/themes}"
export TEEUP_THEMES_DIR

# theme_dir <name>
# A user theme overrides a shipped one of the same name, the same way a user
# config overrides a shipped config. `die` is not used: this runs inside $( ),
# where die would only kill the substitution subshell.
theme_dir() {
  local name="$1" d
  d="$TEEUP_CONFIG_DIR/themes/$name"
  if [[ -f "$d/dark.toml" ]]; then printf '%s\n' "$d"; return 0; fi
  d="$TEEUP_THEMES_DIR/$name"
  if [[ -f "$d/dark.toml" ]]; then printf '%s\n' "$d"; return 0; fi
  err "Unknown theme: $name (try: teeup theme list)"
  return 1
}

theme_list() {
  local d
  {
    for d in "$TEEUP_THEMES_DIR"/*/; do
      if [[ -f "$d/dark.toml" ]]; then basename "$d"; fi
    done
    for d in "$TEEUP_CONFIG_DIR"/themes/*/; do
      if [[ -f "$d/dark.toml" ]]; then basename "$d"; fi
    done
  } 2>/dev/null | sort -u
}

theme_current() {
  local f="$TEEUP_STATE_DIR/current/theme.name"
  if [[ -f "$f" ]]; then cat "$f"; else printf 'none\n'; fi
}

# One sed substitution triple per key, appended to the shared script.
_theme_sed_entry() {
  local key="$1" value="$2" hex rgb
  printf 's|{{ %s }}|%s|g\n' "$key" "$value" >> "$TEEUP_COLOR_SED"
  printf 's|{{ %s_strip }}|%s|g\n' "$key" "${value#\#}" >> "$TEEUP_COLOR_SED"
  # Only a real six-digit hex colour gets an _rgb variant: `printf '%d' 0xzz`
  # fails, and under `set -e` that would abort the whole theme switch.
  case "$value" in
    \#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])
      hex="${value#\#}"
      rgb="$(printf '%d,%d,%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}")"
      printf 's|{{ %s_rgb }}|%s|g\n' "$key" "$rgb" >> "$TEEUP_COLOR_SED"
      ;;
  esac
}

# theme_palette_load <file>
# bash 3.2 has no associative arrays, so the palette becomes one exported
# TEEUP_COLOR_<KEY> per key plus a space-separated key list, and the render
# table is a sed script built once here rather than once per template.
# The `sed` expression takes the value out of the double quotes, which is why
# a value may contain spaces (bat_theme) but never a double quote.
theme_palette_load() {
  local file="$1" key value upper old
  if [[ ! -f "$file" ]]; then
    err "Palette file not found: $file"
    return 1
  fi
  for old in ${TEEUP_COLOR_KEYS:-}; do
    upper="$(printf '%s' "$old" | tr '[:lower:]' '[:upper:]')"
    unset "TEEUP_COLOR_$upper"
  done
  TEEUP_COLOR_KEYS=""
  if [[ -n "${TEEUP_COLOR_SED:-}" ]]; then rm -f "$TEEUP_COLOR_SED"; fi
  TEEUP_COLOR_SED="$(mktemp)"
  export TEEUP_COLOR_SED
  while read -r key value; do
    if [[ -z "$key" ]]; then continue; fi
    upper="$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
    export "TEEUP_COLOR_$upper=$value"
    TEEUP_COLOR_KEYS="$TEEUP_COLOR_KEYS$key "
    _theme_sed_entry "$key" "$value"
  done < <(sed -n 's/^\([a-z][a-z0-9_]*\)[[:space:]]*=[[:space:]]*"\([^"]*\)".*$/\1 \2/p' "$file")
  export TEEUP_COLOR_KEYS
}

# theme_render <tpl> <out>
theme_render() {
  local tpl="$1" out="$2"
  if [[ -z "${TEEUP_COLOR_SED:-}" || ! -f "${TEEUP_COLOR_SED:-}" ]]; then
    err "theme_render: call theme_palette_load first"
    return 1
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would render $(basename "$tpl") -> $out"
    return 0
  fi
  mkdir -p "$(dirname "$out")"
  sed -f "$TEEUP_COLOR_SED" "$tpl" > "$out"
}

# theme_templates -> every template, user copies first.
# theme_set renders in this order and never overwrites an output that already
# exists, so a user template of the same basename wins.
theme_templates() {
  local d f
  for f in "$TEEUP_CONFIG_DIR"/themed/*.tpl; do
    if [[ -f "$f" ]]; then printf '%s\n' "$f"; fi
  done
  for d in "$TEEUP_CAPS_DIR"/*/themed; do
    if [[ -d "$d" ]]; then
      for f in "$d"/*.tpl; do
        if [[ -f "$f" ]]; then printf '%s\n' "$f"; fi
      done
    fi
  done
  return 0
}

# theme_set <name>
# Render both modes into a staging directory, swap it into place, record the
# name, then let every capability pick the new files up. Rendering into a
# staging dir means a failure half way through leaves the old theme intact.
#
# An unknown name warns and falls back to catppuccin rather than failing: the
# theme capability is core, so a non-zero exit here aborts the whole bootstrap.
TEEUP_THEME_FALLBACK="catppuccin"
export TEEUP_THEME_FALLBACK

theme_set() {
  local name="$1" dir mode tpl out current next cap
  if ! dir="$(theme_dir "$name")"; then
    if [[ "$name" == "$TEEUP_THEME_FALLBACK" ]]; then
      return 1
    fi
    warn "Falling back to the $TEEUP_THEME_FALLBACK theme. Pick another with: teeup theme list"
    name="$TEEUP_THEME_FALLBACK"
    dir="$(theme_dir "$name")" || return 1
  fi
  current="$TEEUP_STATE_DIR/current/theme"
  next="$TEEUP_STATE_DIR/current/next-theme"
  if [[ -d "$next" ]]; then run_cmd rm -rf "$next"; fi
  for mode in dark light; do
    if [[ ! -f "$dir/$mode.toml" ]]; then
      err "Theme $name has no $mode.toml"
      return 1
    fi
    theme_palette_load "$dir/$mode.toml" || return 1
    run_cmd mkdir -p "$next/$mode"
    while IFS= read -r tpl; do
      out="$next/$mode/$(basename "$tpl" .tpl)"
      if [[ -e "$out" ]]; then continue; fi
      theme_render "$tpl" "$out" || warn "Could not render $tpl"
    done < <(theme_templates)
    if [[ "$DRY_RUN" != "true" ]]; then
      cp "$dir/$mode.toml" "$next/$mode/colors.toml"
    fi
  done
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would swap $next into $current and record theme $name"
  else
    if [[ -d "$current" ]]; then
      rm -rf "$current.prev"
      mv "$current" "$current.prev"
    fi
    mv "$next" "$current"
    rm -rf "$current.prev"
    printf '%s\n' "$name" > "$TEEUP_STATE_DIR/current/theme.name"
    ok "Theme set to $name"
  fi
  if [[ -n "${TEEUP_COLOR_SED:-}" ]]; then
    rm -f "$TEEUP_COLOR_SED"
    TEEUP_COLOR_SED=""
  fi
  TEEUP_THEME_DIR="$current"
  TEEUP_THEME_NAME="$name"
  export TEEUP_THEME_DIR TEEUP_THEME_NAME
  while IFS= read -r cap; do
    cap_run_optional "$cap" theme-apply
  done < <(cap_list)
}
```

- [ ] **Step 4: Add `theme` to `lib/all.sh`**

Replace the loop line again:

```bash
for _teeup_lib in files state answers pkg ui capability macos theme; do
```

`theme.sh` comes after `capability.sh` because `theme_set` calls `cap_list` and `cap_run_optional`.

- [ ] **Step 5: Add the `theme` verb to `bin/teeup`**

In `usage()`, insert directly after the line `  teeup list [--tier core|daily|lazy]`:

```text
  teeup theme set|list|current   apply, list or print the cross-tool theme
```

Add this function after `cmd_configure`:

```bash
cmd_theme() {
  local op="${1:-current}"
  [[ $# -gt 0 ]] && shift
  case "$op" in
    set)
      [[ -n "${1:-}" ]] || die "Usage: teeup theme set <name>"
      theme_set "$1"
      ;;
    list) theme_list ;;
    current) theme_current ;;
    *) die "Usage: teeup theme set|list|current" ;;
  esac
}
```

and add this line to the verb `case`, directly after `configure) cmd_configure "$@" ;;`:

```bash
  theme) cmd_theme "$@" ;;
```

- [ ] **Step 6: Write the `theme` capability**

`capabilities/theme/capability`:

```sh
summary="Cross-tool theme system with light and dark palettes"
group=system
tier=core
requires="teeup-runtime"
provides=""
interactive=false
```

`capabilities/theme/install`:

```bash
#!/usr/bin/env bash
# Nothing to install: the theme system is shell, sed and the palettes in the
# checkout. The file exists so `teeup install theme` is a recorded no-op
# rather than an error.
:
```

`capabilities/theme/configure`:

```bash
#!/usr/bin/env bash
# The theme is an answer, so configure means "render what the wizard chose".
# Re-running it is also how `teeup update` picks up new or changed templates,
# which is why theme_set always re-renders instead of skipping.
theme_set "$(answers_get TEEUP_THEME catppuccin)"
```

`capabilities/theme/themed/env.sh.tpl`:

```sh
# Generated by `teeup theme set`. Do not edit; the next theme switch replaces
# it. The zsh default layer sources the file for the current appearance:
#   ~/.local/state/teeup/current/theme/$TEEUP_APPEARANCE/env.sh
export TEEUP_THEME_MODE="{{ mode }}"
export TEEUP_THEME_ACCENT="{{ accent }}"
export BAT_THEME="{{ bat_theme }}"
```

`capabilities/theme/themed/starship-palette.toml.tpl`:

`black` and `white` are here because plan 2a's shipped block defines them; leaving them out would break a user style written as `fg:black` the first time a theme is set.

```toml
[palettes.teeup-{{ mode }}]
accent = "{{ accent }}"
selection = "{{ selection }}"
muted = "{{ muted }}"
background = "{{ background }}"
dark_background = "{{ dark_background }}"
lighter_background = "{{ lighter_background }}"
foreground = "{{ foreground }}"
light_foreground = "{{ light_foreground }}"
bright_foreground = "{{ bright_foreground }}"
black = "{{ dark_background }}"
white = "{{ bright_foreground }}"
red = "{{ red }}"
orange = "{{ orange }}"
yellow = "{{ yellow }}"
green = "{{ green }}"
cyan = "{{ cyan }}"
blue = "{{ blue }}"
magenta = "{{ magenta }}"
```

`capabilities/theme/theme-apply`:

```bash
#!/usr/bin/env bash
# Push the rendered palettes into ~/.config/starship.toml, which plan 2a ships
# with a `palette = "teeup-dark"` root key and an empty marker block at the
# end. The file belongs to the user, so only the region between the markers
# and that one root key are rewritten; everything else is left alone.
STARSHIP="$(user_config_dir)/starship.toml"
START="# teeup:theme-palette:start"
END="# teeup:theme-palette:end"
THEME_DIR="${TEEUP_THEME_DIR:-$TEEUP_STATE_DIR/current/theme}"

if [[ ! -f "$STARSHIP" ]]; then
  log "No $STARSHIP yet; its palette will be written the next time you run teeup theme set."
  exit 0
fi
if ! grep -qxF "$START" "$STARSHIP" || ! grep -qxF "$END" "$STARSHIP"; then
  warn "$STARSHIP has no '$START' block; leaving it alone."
  exit 0
fi

# `palette = ` is a root key, and in TOML a bare key after a table header
# belongs to that table. Plan 2a puts the palette line and this block at the top
# of the file for exactly that reason; if something moved them below a [table],
# rewriting them in place would produce a palette starship never reads, so stop
# and say so instead of writing something that silently does nothing.
marker_line="$(grep -n -xF "$START" "$STARSHIP" | head -1 | cut -d: -f1)"
first_table_line="$(grep -n '^\[' "$STARSHIP" | head -1 | cut -d: -f1)"
if [[ -n "$first_table_line" && "$marker_line" -gt "$first_table_line" ]]; then
  warn "$STARSHIP has the teeup palette block below its first [table]; a root 'palette =' key there would belong to that table. Move the block and the 'palette =' line above line $first_table_line, then run: teeup theme set $(theme_current)"
  exit 0
fi

block="$(mktemp)"
for mode in dark light; do
  rendered="$THEME_DIR/$mode/starship-palette.toml"
  if [[ -f "$rendered" ]]; then
    cat "$rendered" >> "$block"
    echo "" >> "$block"
  fi
done

active="teeup-$(appearance)"
rewritten="$(mktemp)"
# Both the block and the `palette =` line are above the first [table] (checked
# above), so rewriting them where they sit keeps the palette key at the TOML
# root. The block itself holds only [palettes.*] table headers, which is valid
# anywhere, and the user's own tables all follow it.
awk -v blockfile="$block" -v pal="$active" -v start="$START" -v end="$END" '
  $0 == start { print; skip = 1; while ((getline line < blockfile) > 0) print line; close(blockfile); next }
  $0 == end   { skip = 0; print; next }
  skip        { next }
  /^palette *=/ { printf "palette = \"%s\"\n", pal; next }
  { print }
' "$STARSHIP" > "$rewritten"

write_managed_file "$STARSHIP" "starship palette ($active)" < "$rewritten"
rm -f "$block" "$rewritten"
```

Make them executable:

```bash
chmod +x capabilities/theme/install capabilities/theme/configure capabilities/theme/theme-apply
```

- [ ] **Step 7: Add `theme` to `capabilities/core.list`**

Plan 2a's Task 9 leaves the file exactly like this — quoted here as the "before", so the edit is unambiguous:

```text
# Core tier: what every terminal session needs. Ordered; each entry's
# requires= must already be satisfied by the entries above it.
# Plan 2b appends: wezterm fonts aerospace keyboard macos-defaults theme
xcode-clt
package-manager
teeup-runtime
dev-dirs
zsh
starship
cli-tools
secrets
git
ssh
github
mise
```

Append `theme` and reword the third comment line, giving:

```text
# Core tier: what every terminal session needs. Ordered; each entry's
# requires= must already be satisfied by the entries above it.
# This plan still inserts, above theme: wezterm fonts aerospace keyboard macos-defaults
xcode-clt
package-manager
teeup-runtime
dev-dirs
zsh
starship
cli-tools
secrets
git
ssh
github
mise
theme
```

(The eight names between `dev-dirs` and `theme` are plan 2a's and are already in the file when this plan runs. 2a's Decisions table settles the `git`/`mise` question in favour of the spec's order — `mise` is **not** moved before `git` — so the twelve lines above are exactly what 2a leaves behind. `theme` goes last and stays last: every other capability's templates must exist before it renders them.)

- [ ] **Step 8: Write `tests/capabilities/theme.sh`**

```bash
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

test_theme_apply_without_starship_is_quiet() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure theme 2>&1)"
  assert_contains "$out" "No $TEST_HOME/.config/starship.toml yet" || return 1
  assert_not_contains "$out" "theme-apply failed" || return 1
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
run_test "theme-apply refuses a block below a table" test_theme_apply_refuses_a_block_below_a_table
run_test "theme-apply without starship is quiet" test_theme_apply_without_starship_is_quiet
run_test "configure twice is content identical" test_configure_twice_is_content_identical
run_test "theme verbs" test_theme_verbs
print_summary
```

- [ ] **Step 9: Run everything**

```bash
bash tests/lib/theme.sh
bash tests/capabilities/theme.sh
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning lib/theme.sh bin/teeup capabilities/theme/install capabilities/theme/configure capabilities/theme/theme-apply tests/lib/theme.sh tests/capabilities/theme.sh
```

Expected: `lib/theme.sh` prints `Summary: 10/10 passed`; `capabilities/theme` prints `Summary: 8/8 passed`; `commands --check` prints nothing; `./tests/run.sh` ends with `All 24 suites passed.`; shellcheck prints nothing.

- [ ] **Step 10: Commit**

```bash
git add lib/theme.sh lib/all.sh bin/teeup themes capabilities/theme capabilities/core.list tests/lib/theme.sh tests/capabilities/theme.sh
git commit -m "Add the theme system with the Catppuccin light and dark palettes"
```

---

### Task 3: `lib/font.sh`, the `fonts` capability and `teeup install font`

**Files:**
- Create: `lib/font.sh`, `capabilities/fonts/{capability,install,configure}`
- Modify: `lib/all.sh`, `bin/teeup`, `capabilities/core.list`
- Test: `tests/lib/font.sh`, `tests/capabilities/fonts.sh`

**Interfaces:**
- Consumes: `cask_install`, `casks_supported` (`lib/pkg.sh`); `write_managed_file` (`lib/files.sh`); `cap_list`, `cap_run_optional` (`lib/capability.sh`); `log`, `ok`, `warn`, `err`, `TEEUP_STATE_DIR` (`lib/core.sh`).
- Produces:
  - `font_cask <name>` → the Homebrew cask for a display name; error and exit 1 when unknown.
  - `font_family <name>` → the family name applications use.
  - `font_table` → the supported list, for `teeup install font list`.
  - `font_current` → the recorded family, or `JetBrainsMono Nerd Font`.
  - `font_set <name>` → installs the cask, rewrites `$TEEUP_STATE_DIR/current/font`, runs every `font-apply` hook.
  - `bin/teeup install font <name>`.
  - **The font state contract:** `$TEEUP_STATE_DIR/current/font`, one line, the family name.

**Decisions made here:**

1. **The font logic is a library, not a script inside the capability.** Both `bin/teeup install font` and `capabilities/fonts/configure` need the name table, and `bin/teeup` may not source a capability directory. Note that `lib/font.sh` is an **addition** to the spec's section-4 `lib/` table, which lists only `core pkg files state answers capability macos ui theme`; the alternative was to bolt the table onto `lib/theme.sh`, which has nothing to do with fonts.
2. **The name table is a closed list of five families** (JetBrainsMono, CaskaydiaMono, FiraCode, Hack, Meslo), matched on a normalised key (lower-cased, spaces/underscores/hyphens removed, a trailing `nerdfont` dropped) so `teeup install font "Cascadia Mono"`, `cascadia-mono` and `CaskaydiaMono Nerd Font` all resolve to the same row. An unknown name fails loudly with `teeup install font list` in the message rather than guessing a cask that may not exist.
3. **MacPorts machines get a warning, not a failure.** `cask_install` already warns and returns 0 there; `configure` adds one line naming nerdfonts.com, and the state file is still written so every tool agrees on a family name even when the font has to be installed by hand.

**Real-Mac risk:** cask names are taken from the Homebrew cask index and have not been resolved against a live `brew search`. `teeup install font "Cascadia Mono"` on hardware is the first proof that `font-caskaydia-mono-nerd-font` exists.

- [ ] **Step 1: Write the failing test `tests/lib/font.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false
}

test_names_normalise_to_the_same_row() {
  setup
  assert_equals "font-caskaydia-mono-nerd-font" "$(font_cask 'Cascadia Mono')" || return 1
  assert_equals "font-caskaydia-mono-nerd-font" "$(font_cask 'cascadia-mono')" || return 1
  assert_equals "font-caskaydia-mono-nerd-font" "$(font_cask 'CaskaydiaMono Nerd Font')" || return 1
  assert_equals "CaskaydiaMono Nerd Font" "$(font_family 'Cascadia Mono')" || return 1
  cleanup_test_env
}

test_every_shipped_family_resolves() {
  setup
  assert_equals "JetBrainsMono Nerd Font" "$(font_family 'JetBrains Mono')" || return 1
  assert_equals "FiraCode Nerd Font" "$(font_family 'Fira Code')" || return 1
  assert_equals "Hack Nerd Font" "$(font_family 'hack')" || return 1
  assert_equals "MesloLGS Nerd Font" "$(font_family 'Meslo')" || return 1
  assert_equals "font-jetbrains-mono-nerd-font" "$(font_cask 'JetBrainsMono')" || return 1
  assert_equals "font-fira-code-nerd-font" "$(font_cask 'FiraCode')" || return 1
  assert_equals "font-hack-nerd-font" "$(font_cask 'Hack')" || return 1
  assert_equals "font-meslo-lg-nerd-font" "$(font_cask 'MesloLGS')" || return 1
  cleanup_test_env
}

test_unknown_font_fails_with_a_hint() {
  setup
  local rc=0 out
  out="$(font_cask 'Comic Sans' 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Unknown font: Comic Sans" || return 1
  assert_contains "$out" "teeup install font list" || return 1
  cleanup_test_env
}

test_current_defaults_to_jetbrains() {
  setup
  assert_equals "JetBrainsMono Nerd Font" "$(font_current)" || return 1
  cleanup_test_env
}

test_set_installs_the_cask_and_records_the_family() {
  setup
  local out
  out="$(font_set 'Cascadia Mono')"
  assert_contains "$(cat "$MOCK_LOG")" "brew install --cask font-caskaydia-mono-nerd-font" || return 1
  assert_equals "CaskaydiaMono Nerd Font" "$(cat "$TEST_HOME/.local/state/teeup/current/font")" || return 1
  assert_equals "CaskaydiaMono Nerd Font" "$(font_current)" || return 1
  assert_contains "$out" "Font set to CaskaydiaMono Nerd Font" || return 1
  cleanup_test_env
}

test_set_runs_font_apply_hooks() {
  setup
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR/demo"
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
  cat > "$TEEUP_CAPS_DIR/demo/font-apply" <<'EOF2'
#!/usr/bin/env bash
echo "font-applied:$TEEUP_FONT_FAMILY"
EOF2
  chmod +x "$TEEUP_CAPS_DIR/demo/install" "$TEEUP_CAPS_DIR/demo/configure" "$TEEUP_CAPS_DIR/demo/font-apply"
  local out
  out="$(font_set Hack)"
  assert_contains "$out" "font-applied:Hack Nerd Font" || return 1
  cleanup_test_env
}

test_set_dry_run_writes_nothing() {
  setup
  # shellcheck disable=SC2034  # last assignment in the file; read by run_cmd
  DRY_RUN=true
  local out
  out="$(font_set 'Fira Code')"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask font-fira-code-nerd-font" || return 1
  assert_contains "$out" "[DRY-RUN] Would write $TEST_HOME/.local/state/teeup/current/font" || return 1
  [[ ! -e "$TEST_HOME/.local/state/teeup/current/font" ]] || { echo "state written in dry run"; return 1; }
  cleanup_test_env
}

test_table_lists_every_family() {
  setup
  local out
  out="$(font_table)"
  assert_contains "$out" "JetBrainsMono" || return 1
  assert_contains "$out" "CaskaydiaMono" || return 1
  assert_contains "$out" "font-meslo-lg-nerd-font" || return 1
  cleanup_test_env
}

echo "lib/font.sh"
run_test "names normalise to the same row" test_names_normalise_to_the_same_row
run_test "every shipped family resolves" test_every_shipped_family_resolves
run_test "unknown font fails with a hint" test_unknown_font_fails_with_a_hint
run_test "current defaults to JetBrainsMono" test_current_defaults_to_jetbrains
run_test "set installs the cask and records the family" test_set_installs_the_cask_and_records_the_family
run_test "set runs font-apply hooks" test_set_runs_font_apply_hooks
run_test "set dry run writes nothing" test_set_dry_run_writes_nothing
run_test "table lists every family" test_table_lists_every_family
print_summary
```

- [ ] **Step 2: Write `lib/font.sh`**

```bash
#!/usr/bin/env bash
# font.sh - one family name for every tool, switchable with one command.
# The name lives in $TEEUP_STATE_DIR/current/font; WezTerm (and, from phase 3,
# Neovim, Zed and VS Code) read it and a font-apply hook tells them to reload.
# Requires core.sh, files.sh, pkg.sh and capability.sh.

TEEUP_FONT_DEFAULT="JetBrainsMono Nerd Font"
export TEEUP_FONT_DEFAULT

font_file() { printf '%s/current/font\n' "$TEEUP_STATE_DIR"; }

font_current() {
  local f
  f="$(font_file)"
  if [[ -s "$f" ]]; then head -1 "$f"; else printf '%s\n' "$TEEUP_FONT_DEFAULT"; fi
}

# Lower-case, drop spaces, underscores and hyphens, then drop a trailing
# "nerdfont", so "Cascadia Mono", "cascadia-mono" and "CaskaydiaMono Nerd Font"
# all normalise to the same key.
_font_key() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' _-' | sed 's/nerdfont$//'
}

# _font_row <name> -> "<cask> <family...>"; returns 1 when the name is unknown.
_font_row() {
  local key
  key="$(_font_key "$1")"
  case "$key" in
    jetbrainsmono|jetbrains) echo "font-jetbrains-mono-nerd-font JetBrainsMono Nerd Font" ;;
    cascadiamono|cascadiacode|cascadia|caskaydiamono|caskaydia) echo "font-caskaydia-mono-nerd-font CaskaydiaMono Nerd Font" ;;
    firacode|fira) echo "font-fira-code-nerd-font FiraCode Nerd Font" ;;
    hack) echo "font-hack-nerd-font Hack Nerd Font" ;;
    meslo|meslolg|meslolgs) echo "font-meslo-lg-nerd-font MesloLGS Nerd Font" ;;
    *) return 1 ;;
  esac
}

font_cask() {
  local row
  if ! row="$(_font_row "$1")"; then
    err "Unknown font: $1 (try: teeup install font list)"
    return 1
  fi
  printf '%s\n' "${row%% *}"
}

font_family() {
  local row
  if ! row="$(_font_row "$1")"; then
    err "Unknown font: $1 (try: teeup install font list)"
    return 1
  fi
  printf '%s\n' "${row#* }"
}

font_table() {
  printf '%-16s %-24s %s\n' "NAME" "FAMILY" "CASK"
  printf '%-16s %-24s %s\n' "JetBrainsMono" "JetBrainsMono Nerd Font" "font-jetbrains-mono-nerd-font"
  printf '%-16s %-24s %s\n' "Cascadia Mono" "CaskaydiaMono Nerd Font" "font-caskaydia-mono-nerd-font"
  printf '%-16s %-24s %s\n' "Fira Code" "FiraCode Nerd Font" "font-fira-code-nerd-font"
  printf '%-16s %-24s %s\n' "Hack" "Hack Nerd Font" "font-hack-nerd-font"
  printf '%-16s %-24s %s\n' "Meslo" "MesloLGS Nerd Font" "font-meslo-lg-nerd-font"
}

# font_set <name>
# The same three steps as a theme switch: install, record, tell everyone.
font_set() {
  local requested="${1:-}" family cask cap
  if [[ -z "$requested" ]]; then
    err "Usage: teeup install font <name>   (teeup install font list shows the names)"
    return 1
  fi
  if [[ "$requested" == "list" ]]; then
    font_table
    return 0
  fi
  family="$(font_family "$requested")" || return 1
  cask="$(font_cask "$requested")" || return 1
  cask_install "$cask" || return 1
  write_managed_file "$(font_file)" "font family" <<FONT_STATE
$family
FONT_STATE
  TEEUP_FONT_FAMILY="$family"
  export TEEUP_FONT_FAMILY
  while IFS= read -r cap; do
    cap_run_optional "$cap" font-apply
  done < <(cap_list)
  ok "Font set to $family"
}
```

- [ ] **Step 3: Add `font` to `lib/all.sh`**

Final form of the loop line:

```bash
for _teeup_lib in files state answers pkg ui capability macos theme font; do
```

- [ ] **Step 4: Add `install font` to `bin/teeup`**

In `usage()`, change the `teeup install` line and add one below it:

```text
  teeup install <capability>     install and configure it (and what it requires)
  teeup install font <name>      install a Nerd Font and point every tool at it
```

In `cmd_install`, insert immediately after its first line. Plan 2a's Task 1 rewrote that line to capture `cap_order`'s status, so after 2a it reads `  local target="${1:-}" order c` — anchor on whatever is there, or on the `[[ -n "$target" ]] || die "Usage: teeup install` line directly below it. The result:

```bash
cmd_install() {
  local target="${1:-}" order c
  # `font` is not a capability: it is a switch over an already-installed
  # capability's state, so it is handled before the capability lookup.
  if [[ "$target" == "font" ]]; then
    shift
    font_set "$*"
    return $?
  fi
  [[ -n "$target" ]] || die "Usage: teeup install <capability>"
```

i.e. the inserted block is:

```bash
  # `font` is not a capability: it is a switch over an already-installed
  # capability's state, so it is handled before the capability lookup.
  if [[ "$target" == "font" ]]; then
    shift
    font_set "$*"
    return $?
  fi
```

`"$*"` rather than `"$1"` so both `teeup install font "Cascadia Mono"` and `teeup install font Cascadia Mono` work.

- [ ] **Step 5: Write the `fonts` capability**

`capabilities/fonts/capability`:

```sh
summary="JetBrainsMono Nerd Font, and the font every tool follows"
group=system
tier=core
requires="package-manager"
provides=""
casks="font-jetbrains-mono-nerd-font"
interactive=false
```

`capabilities/fonts/install`:

```bash
#!/usr/bin/env bash
# One font at bootstrap. Any other family is `teeup install font <name>`,
# which installs its cask on demand.
cask_install font-jetbrains-mono-nerd-font
```

`capabilities/fonts/configure`:

```bash
#!/usr/bin/env bash
# Record the family every tool should ask for. Written once: a later
# `teeup install font <name>` is the only thing that changes it, so re-running
# configure never undoes the user's choice.
if [[ -s "$(font_file)" ]]; then
  log "Font already recorded: $(font_current)"
else
  write_managed_file "$(font_file)" "font family" <<FONT_STATE
$TEEUP_FONT_DEFAULT
FONT_STATE
fi

if ! casks_supported; then
  warn "MacPorts has no Nerd Font ports. Install $(font_current) by hand from https://www.nerdfonts.com; the family name above is what every teeup config asks for."
fi
```

```bash
chmod +x capabilities/fonts/install capabilities/fonts/configure
```

- [ ] **Step 6: Add `fonts` to `capabilities/core.list`**

Insert `fonts` directly above `theme`:

```text
# (unchanged lines above)
mise
fonts
theme
```

- [ ] **Step 7: Write `tests/capabilities/fonts.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_dry_run_gets_the_cask() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install fonts)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask font-jetbrains-mono-nerd-font" || return 1
  cleanup_test_env
}

test_configure_records_the_default_family() {
  setup
  DRY_RUN=false "$TEEUP" configure fonts >/dev/null
  assert_equals "JetBrainsMono Nerd Font" "$(cat "$TEST_HOME/.local/state/teeup/current/font")" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  DRY_RUN=false "$TEEUP" configure fonts >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure fonts)"
  assert_contains "$out" "Font already recorded: JetBrainsMono Nerd Font" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  DRY_RUN=true "$TEEUP" configure fonts >/dev/null
  [[ ! -e "$TEST_HOME/.local/state/teeup/current/font" ]] || { echo "state written in dry run"; return 1; }
  cleanup_test_env
}

test_configure_warns_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(DRY_RUN=false "$TEEUP" configure fonts 2>&1)"
  assert_contains "$out" "MacPorts has no Nerd Font ports" || return 1
  cleanup_test_env
}

test_install_font_switches_the_family() {
  setup
  DRY_RUN=false "$TEEUP" configure fonts >/dev/null
  DRY_RUN=false "$TEEUP" install font "Cascadia Mono" >/dev/null
  assert_equals "CaskaydiaMono Nerd Font" "$(cat "$TEST_HOME/.local/state/teeup/current/font")" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew install --cask font-caskaydia-mono-nerd-font" || return 1
  cleanup_test_env
}

test_install_font_list_prints_the_table() {
  setup
  assert_contains "$(DRY_RUN=false "$TEEUP" install font list)" "font-hack-nerd-font" || return 1
  cleanup_test_env
}

test_install_font_unknown_fails() {
  setup
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" install font 'Comic Sans' 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Unknown font: Comic Sans" || return 1
  cleanup_test_env
}

echo "capabilities/fonts"
run_test "install dry run gets the cask" test_install_dry_run_gets_the_cask
run_test "configure records the default family" test_configure_records_the_default_family
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "configure warns on macports" test_configure_warns_on_macports
run_test "install font switches the family" test_install_font_switches_the_family
run_test "install font list prints the table" test_install_font_list_prints_the_table
run_test "install font unknown fails" test_install_font_unknown_fails
print_summary
```

- [ ] **Step 8: Run everything**

```bash
bash tests/lib/font.sh
bash tests/capabilities/fonts.sh
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning lib/font.sh bin/teeup capabilities/fonts/install capabilities/fonts/configure tests/lib/font.sh tests/capabilities/fonts.sh
```

Expected: `lib/font.sh` prints `Summary: 8/8 passed`; `capabilities/fonts` prints `Summary: 8/8 passed`; `commands --check` prints nothing; `./tests/run.sh` ends with `All 26 suites passed.`; shellcheck prints nothing.

- [ ] **Step 9: Commit**

```bash
git add lib/font.sh lib/all.sh bin/teeup capabilities/fonts capabilities/core.list tests/lib/font.sh tests/capabilities/fonts.sh
git commit -m "Add the fonts capability and the teeup install font switch"
```

---

### Task 4: `wezterm` capability

**Files:**
- Create: `capabilities/wezterm/{capability,install,configure,theme-apply,font-apply}`, `capabilities/wezterm/config/wezterm/{wezterm.lua,local.lua}`, `capabilities/wezterm/default/teeup/wezterm.lua`, `capabilities/wezterm/themed/wezterm.lua.tpl`
- Modify: `capabilities/core.list`
- Test: `tests/capabilities/wezterm.sh`

**Interfaces:**
- Consumes: `cask_install`, `casks_supported`, `pkg_install` (`lib/pkg.sh`); `copy_config_once` (`lib/files.sh`); `run_cmd`, `log`, `warn` (`lib/core.sh`); `TEEUP_CAP_DIR` (set by `cap_run`); the font state contract from Task 3; the theme staging contract from Task 2.
- Produces: `~/.config/wezterm/wezterm.lua` (thin, user-owned), `~/.config/wezterm/local.lua` (user-owned overrides), the `teeup.wezterm` Lua module, and `current/theme/<mode>/wezterm.lua` (a WezTerm colour-scheme table) through `themed/wezterm.lua.tpl`.

**Decisions made here:**

1. **`TEEUP_PATH` in Lua comes from the environment first, then from `~/.config/teeup/env`, then from `~/.local/share/teeup`.** WezTerm launched from the Dock or Spotlight inherits `launchd`'s environment, not a login shell's, so `os.getenv("TEEUP_PATH")` is usually nil there. `~/.config/teeup/env` is a one-line file that `teeup-runtime configure` already writes (`export TEEUP_PATH="…"`), and parsing one line of it in Lua is cheaper and more honest than telling the user to run `launchctl setenv`. The final fallback is the canonical clone path from spec section 2.
2. **One user override file, `~/.config/wezterm/local.lua`, returning a table.** The dotfiles repo used `~/.wezterm_local.lua` with a `workspaces` table; that shape is kept (so the user's existing file still works — the thin config falls back to it) but the file moves next to the rest of the WezTerm config. `local.lua` may set `font_size`, `workspaces` and `hyperlink_rules`; everything else goes in the user section of `wezterm.lua`.
3. **The work Jira hyperlink rule is not shipped.** It is a commented example in `local.lua`, per spec section 10.
4. **The `fc-list` font probing from the dotfiles config is dropped.** It existed because Linux machines lacked the preferred font; on macOS `fc-list` is usually absent and the probe always returned the first candidate anyway. The family now comes from `current/font`, which teeup controls, with `JetBrainsMono Nerd Font` as the built-in fallback.
5. **Both rendered schemes are registered and the current one selected**, rather than one file per appearance. WezTerm re-evaluates the config when the system appearance changes, so registering `teeup-dark` and `teeup-light` together makes the light/dark switch instant with no file work.
6. **`theme-apply` and `font-apply` both `touch` the config file.** The default layer adds the theme and font state files to WezTerm's reload watch list, but an instance started before those files existed is watching nothing; touching the config it definitely watches is the one reload path that always works.

**Real-Mac risk:** nothing here has been loaded by a real WezTerm. `luac -p` proves the files parse, not that `wezterm.config_builder()` accepts every key. The first real run should be `wezterm --config-file ~/.config/wezterm/wezterm.lua start -- true` and a look at `wezterm show-config-error` if it complains.

- [ ] **Step 1: Write `capabilities/wezterm/capability`**

```sh
summary="WezTerm terminal with the teeup Lua layer"
group=apps
tier=core
requires="package-manager"
provides=""
casks="wezterm"
apps="WezTerm"
interactive=false
```

- [ ] **Step 2: Write `capabilities/wezterm/install`**

```bash
#!/usr/bin/env bash
# WezTerm is a cask on Homebrew. On MacPorts there is no cask machinery, so
# try the port of the same name and say what to do when it is missing.
if casks_supported; then
  cask_install wezterm
else
  pkg_install wezterm wezterm || warn "No WezTerm port available; download it from https://wezfurlong.org/wezterm/installation.html"
fi
```

- [ ] **Step 3: Write the thin user config `capabilities/wezterm/config/wezterm/wezterm.lua`**

```lua
-- ~/.config/wezterm/wezterm.lua - yours. teeup installed it once and will not
-- overwrite it. The thick layer lives in the teeup checkout and is upgraded by
-- `teeup update`; put your own settings in ~/.config/wezterm/local.lua, or
-- below the `local config = ...` line here.
local wezterm = require("wezterm")

-- WezTerm launched from the Dock or Spotlight has launchd's environment, not a
-- login shell's, so TEEUP_PATH is usually missing. ~/.config/teeup/env is the
-- one-line file teeup-runtime writes for exactly this case.
local function teeup_path()
  local from_env = os.getenv("TEEUP_PATH")
  if from_env and from_env ~= "" then
    return from_env
  end
  local config_home = os.getenv("XDG_CONFIG_HOME") or (wezterm.home_dir .. "/.config")
  local f = io.open(config_home .. "/teeup/env", "r")
  if f then
    for line in f:lines() do
      local value = line:match('^export TEEUP_PATH="(.*)"$') or line:match("^export TEEUP_PATH=(.+)$")
      if value and value ~= "" then
        f:close()
        return value
      end
    end
    f:close()
  end
  return wezterm.home_dir .. "/.local/share/teeup"
end

local teeup_root = teeup_path()
local state_home = os.getenv("XDG_STATE_HOME") or (wezterm.home_dir .. "/.local/state")

-- Three tiers, highest priority first: generated theme files, your own
-- ~/.config/wezterm, then teeup's default layer. The first tier is there so a
-- theme can ship a require-able Lua module later; today's rendered colour
-- scheme is loaded by path with dofile, from the default layer.
local teeup_search_path = table.concat({
  state_home .. "/teeup/current/theme/?.lua",
  wezterm.config_dir .. "/?.lua",
  teeup_root .. "/capabilities/wezterm/default/?.lua",
}, ";")
package.path = teeup_search_path .. ";" .. package.path

-- Machine-specific settings. local.lua may set font_size, workspaces and
-- hyperlink_rules; see the comments in that file.
local overrides = {}
local ok, loaded = pcall(dofile, wezterm.config_dir .. "/local.lua")
if ok and type(loaded) == "table" then
  overrides = loaded
else
  -- The pre-teeup dotfiles repo kept this table in ~/.wezterm_local.lua.
  local ok_legacy, legacy = pcall(dofile, wezterm.home_dir .. "/.wezterm_local.lua")
  if ok_legacy and type(legacy) == "table" then
    overrides = legacy
  end
end

-- If the default layer cannot be found (no TEEUP_PATH, no ~/.config/teeup/env,
-- and the checkout is not at ~/.local/share/teeup) fall back to a terminal that
-- still works, and say where we looked. An uncaught error here means WezTerm
-- silently drops to its own defaults with nothing pointing at the cause.
local ok_layer, layer = pcall(require, "teeup.wezterm")
local config
if ok_layer then
  config = layer.config(overrides)
else
  wezterm.log_error(
    "teeup: could not load teeup.wezterm (" .. tostring(layer) .. "). Searched: "
      .. teeup_search_path
      .. " -- set TEEUP_PATH or re-run: teeup configure teeup-runtime"
  )
  config = wezterm.config_builder()
  config.font = wezterm.font_with_fallback({ "JetBrainsMono Nerd Font" })
  config.font_size = overrides.font_size or 16.0
end

-- Your own settings go below this line.

return config
```

- [ ] **Step 4: Write `capabilities/wezterm/config/wezterm/local.lua`**

```lua
-- ~/.config/wezterm/local.lua - machine-specific WezTerm settings.
-- Return a table. Everything is optional. This file is yours; teeup ships it
-- once with every entry commented out and never touches it again.
return {
  -- Font size for this machine. The family itself comes from
  -- `teeup install font <name>`, so it is not set here.
  -- font_size = 13.0,

  -- Quick-switch workspaces, reached with the leader key (CTRL+Space) and the
  -- single letter in `key`.
  -- workspaces = {
  --   { key = "e", name = "work", cwd = "/Users/you/Work" },
  --   { key = "p", name = "personal", cwd = "/Users/you/Personal" },
  -- },

  -- Extra Cmd+Click patterns, appended to WezTerm's defaults and teeup's
  -- GitHub shorthand rule. Issue-tracker rules belong here, not in the repo.
  -- hyperlink_rules = {
  --   { regex = [[\b(PROJ-\d+)\b]], format = "https://example.atlassian.net/browse/$1" },
  -- },
}
```

- [ ] **Step 5: Write the default layer `capabilities/wezterm/default/teeup/wezterm.lua`**

```lua
-- teeup's WezTerm layer, required by the thin ~/.config/wezterm/wezterm.lua.
-- This file is teeup's: edit it in the checkout, not in your home directory.
-- Ported from the pre-teeup dotfiles config; every binding is the same, the
-- font and the colours now come from teeup state instead of being hard-coded.

local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

local state_home = os.getenv("XDG_STATE_HOME") or (wezterm.home_dir .. "/.local/state")
local STATE = state_home .. "/teeup"
local DEFAULT_FONT = "JetBrainsMono Nerd Font"

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

-- The family `teeup install font` recorded. Watching the file means the
-- font-apply hook's touch is belt and braces rather than the only reload path.
function M.font_family()
  local path = STATE .. "/current/font"
  wezterm.add_to_config_reload_watch_list(path)
  return read_first_line(path) or DEFAULT_FONT
end

-- wezterm.gui does not exist in the mux server, so assume dark there.
function M.get_appearance()
  if wezterm.gui then
    return wezterm.gui.get_appearance()
  end
  return "Dark"
end

function M.mode()
  if M.get_appearance():find("Dark") then
    return "dark"
  end
  return "light"
end

-- `teeup theme set` renders one colour-scheme table per mode. Both are
-- registered, so the system appearance switch (which makes WezTerm
-- re-evaluate this config) only has to pick the other name.
function M.color_schemes()
  local schemes = {}
  local found = false
  for _, mode in ipairs({ "dark", "light" }) do
    local path = STATE .. "/current/theme/" .. mode .. "/wezterm.lua"
    local ok, scheme = pcall(dofile, path)
    if ok and type(scheme) == "table" then
      schemes["teeup-" .. mode] = scheme
      wezterm.add_to_config_reload_watch_list(path)
      found = true
    end
  end
  if not found then
    return nil
  end
  return schemes
end

-- Tab title: the last component of the pane's cwd, with a dot on the active
-- tab. Falls back to the pane title when there is no cwd (ssh, a pager).
wezterm.on("format-tab-title", function(tab)
  local pane = tab.active_pane
  local title = pane.title
  local cwd = pane.current_working_dir
  if cwd then
    local path = cwd.file_path or ""
    local folder = path:match("([^/]+)/?$")
    if folder then
      title = folder
    end
  end
  if tab.is_active then
    return " ● " .. title .. " "
  end
  return " " .. title .. " "
end)

-- Right status: workspace name and the clock.
wezterm.on("update-right-status", function(window)
  local workspace = window:active_workspace()
  local time = wezterm.strftime("%H:%M")
  window:set_right_status(wezterm.format({
    { Text = "  " .. workspace .. "  │  " .. time .. "  " },
  }))
end)

-- Emacs-style bindings behind a CTRL+Space leader: C-x 2 / C-x 3 split,
-- C-x o cycles, C-x 0 closes, C-x 1 zooms, b/f/c/k move between tabs.
function M.keys(overrides)
  local keys = {
    { key = "p", mods = "CMD|SHIFT", action = act.ActivateCommandPalette },
    { key = "r", mods = "CMD|SHIFT", action = act.ReloadConfiguration },
    { key = "k", mods = "CMD", action = act.Multiple({
      act.ClearScrollback("ScrollbackAndViewport"),
      act.SendKey({ key = "L", mods = "CTRL" }),
    }) },
    { key = "k", mods = "CTRL|SHIFT", action = act.Multiple({
      act.ClearScrollback("ScrollbackAndViewport"),
      act.SendKey({ key = "L", mods = "CTRL" }),
    }) },

    -- Panes
    { key = "3", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
    { key = "2", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
    { key = "o", mods = "LEADER", action = act.ActivatePaneDirection("Next") },
    { key = "LeftArrow", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
    { key = "DownArrow", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
    { key = "UpArrow", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
    { key = "RightArrow", mods = "LEADER", action = act.ActivatePaneDirection("Right") },
    { key = "0", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
    { key = "1", mods = "LEADER", action = act.TogglePaneZoomState },

    -- Tabs, as Emacs buffers
    { key = "b", mods = "LEADER", action = act.ActivateTabRelative(-1) },
    { key = "f", mods = "LEADER", action = act.ActivateTabRelative(1) },
    { key = "c", mods = "LEADER", action = act.SpawnTab("CurrentPaneDomain") },
    { key = "k", mods = "LEADER", action = act.CloseCurrentTab({ confirm = true }) },

    -- Workspaces
    { key = "w", mods = "LEADER", action = act.PromptInputLine({
      description = "Enter new workspace name:",
      action = wezterm.action_callback(function(window, pane, line)
        if line then
          window:perform_action(act.SwitchToWorkspace({ name = line }), pane)
        end
      end),
    }) },
    { key = "s", mods = "LEADER", action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES" }) },
    { key = "d", mods = "LEADER", action = act.SwitchToWorkspace({
      name = "default",
      spawn = { cwd = wezterm.home_dir },
    }) },

    -- Modes
    { key = "r", mods = "LEADER", action = act.ActivateKeyTable({ name = "resize_pane", one_shot = false }) },
    { key = "v", mods = "LEADER", action = act.ActivateCopyMode },
    { key = "q", mods = "LEADER", action = act.QuickSelect },
  }

  for _, ws in ipairs(overrides.workspaces or {}) do
    table.insert(keys, {
      key = ws.key,
      mods = "LEADER",
      action = act.SwitchToWorkspace({ name = ws.name, spawn = { cwd = ws.cwd } }),
    })
  end

  return keys
end

function M.key_tables()
  return {
    resize_pane = {
      { key = "LeftArrow", action = act.AdjustPaneSize({ "Left", 2 }) },
      { key = "RightArrow", action = act.AdjustPaneSize({ "Right", 2 }) },
      { key = "UpArrow", action = act.AdjustPaneSize({ "Up", 2 }) },
      { key = "DownArrow", action = act.AdjustPaneSize({ "Down", 2 }) },
      { key = "Escape", action = "PopKeyTable" },
      { key = "Enter", action = "PopKeyTable" },
    },
  }
end

function M.hyperlink_rules(overrides)
  local rules = wezterm.default_hyperlink_rules()
  -- owner/repo#123 opens the issue or PR.
  table.insert(rules, {
    regex = [[\b([A-Za-z0-9_-]+/[A-Za-z0-9_.-]+)#(\d+)\b]],
    format = "https://github.com/$1/issues/$2",
  })
  for _, rule in ipairs(overrides.hyperlink_rules or {}) do
    table.insert(rules, rule)
  end
  return rules
end

function M.config(overrides)
  overrides = overrides or {}
  local config = wezterm.config_builder()

  -- Fonts. Ligatures on; Devanagari falls back to a system face.
  config.font = wezterm.font_with_fallback({
    { family = M.font_family(), weight = "Medium" },
    "Noto Sans Devanagari",
  })
  config.font_size = overrides.font_size or 16.0
  config.harfbuzz_features = { "calt=1", "clig=1", "liga=1" }

  -- Colours. The built-in Catppuccin schemes are the fallback for the window
  -- between installing WezTerm and the first `teeup theme set`.
  local schemes = M.color_schemes()
  if schemes then
    config.color_schemes = schemes
    config.color_scheme = "teeup-" .. M.mode()
  elseif M.mode() == "dark" then
    config.color_scheme = "Catppuccin Mocha"
  else
    config.color_scheme = "Catppuccin Latte"
  end

  -- Window
  config.window_decorations = "TITLE | RESIZE"
  config.window_background_opacity = 0.92
  config.macos_window_background_blur = 20
  config.window_padding = { left = 12, right = 12, top = 12, bottom = 12 }
  config.text_background_opacity = 1.0
  config.inactive_pane_hsb = { saturation = 0.9, brightness = 0.8 }

  -- Tab bar. Always visible, so the tab workflow stays in muscle memory.
  config.use_fancy_tab_bar = true
  config.hide_tab_bar_if_only_one_tab = false
  config.tab_max_width = 30
  config.show_new_tab_button_in_tab_bar = true

  -- Keys
  config.leader = { key = "Space", mods = "CTRL", timeout_milliseconds = 1000 }
  config.keys = M.keys(overrides)
  config.key_tables = M.key_tables()

  -- General
  config.scrollback_lines = 10000
  config.enable_scroll_bar = false
  config.hyperlink_rules = M.hyperlink_rules(overrides)

  return config
end

return M
```

- [ ] **Step 6: Write `capabilities/wezterm/themed/wezterm.lua.tpl`**

```lua
-- Generated by `teeup theme set`. Do not edit; the next theme switch replaces
-- it. Loaded by capabilities/wezterm/default/teeup/wezterm.lua as the
-- "teeup-{{ mode }}" colour scheme.
return {
  foreground = "{{ foreground }}",
  background = "{{ background }}",
  cursor_bg = "{{ bright_foreground }}",
  cursor_fg = "{{ background }}",
  cursor_border = "{{ bright_foreground }}",
  selection_fg = "{{ background }}",
  selection_bg = "{{ selection }}",
  scrollbar_thumb = "{{ muted }}",
  split = "{{ muted }}",
  ansi = {
    "{{ dark_background }}",
    "{{ red }}",
    "{{ green }}",
    "{{ yellow }}",
    "{{ blue }}",
    "{{ magenta }}",
    "{{ cyan }}",
    "{{ foreground }}",
  },
  brights = {
    "{{ muted }}",
    "{{ bright_red }}",
    "{{ bright_green }}",
    "{{ bright_yellow }}",
    "{{ bright_blue }}",
    "{{ bright_magenta }}",
    "{{ bright_cyan }}",
    "{{ bright_foreground }}",
  },
  tab_bar = {
    background = "{{ dark_background }}",
    active_tab = { bg_color = "{{ accent }}", fg_color = "{{ background }}" },
    inactive_tab = { bg_color = "{{ lighter_background }}", fg_color = "{{ light_foreground }}" },
    inactive_tab_hover = { bg_color = "{{ selection }}", fg_color = "{{ foreground }}" },
    new_tab = { bg_color = "{{ dark_background }}", fg_color = "{{ light_foreground }}" },
    new_tab_hover = { bg_color = "{{ selection }}", fg_color = "{{ foreground }}" },
  },
}
```

- [ ] **Step 7: Write `configure`, `theme-apply` and `font-apply`**

`capabilities/wezterm/configure`:

```bash
#!/usr/bin/env bash
# Two files, both the user's from the moment they land: the thin config that
# pulls in teeup's layer, and the machine-specific override table.
WEZTERM_DIR="$(user_config_dir)/wezterm"
copy_config_once "$TEEUP_CAP_DIR/config/wezterm/wezterm.lua" "$WEZTERM_DIR/wezterm.lua"
copy_config_once "$TEEUP_CAP_DIR/config/wezterm/local.lua" "$WEZTERM_DIR/local.lua"
```

`capabilities/wezterm/theme-apply`:

```bash
#!/usr/bin/env bash
# The default layer adds the rendered theme files to WezTerm's reload watch
# list, but an instance started before those files existed is watching nothing.
# Touching the config file it definitely watches always reloads.
WEZTERM_CONFIG="$(user_config_dir)/wezterm/wezterm.lua"
if [[ -f "$WEZTERM_CONFIG" ]]; then
  run_cmd touch "$WEZTERM_CONFIG"
else
  log "No $WEZTERM_CONFIG yet; nothing to reload."
fi
```

`capabilities/wezterm/font-apply` (same two-line body as `theme-apply`, different reason):

```bash
#!/usr/bin/env bash
# The family is read from current/font when the config loads, so a reload is
# all that is needed to pick up a new font.
WEZTERM_CONFIG="$(user_config_dir)/wezterm/wezterm.lua"
if [[ -f "$WEZTERM_CONFIG" ]]; then
  run_cmd touch "$WEZTERM_CONFIG"
else
  log "No $WEZTERM_CONFIG yet; nothing to reload."
fi
```

```bash
chmod +x capabilities/wezterm/install capabilities/wezterm/configure capabilities/wezterm/theme-apply capabilities/wezterm/font-apply
```

- [ ] **Step 8: Add `wezterm` to `capabilities/core.list`**

Insert `wezterm` directly above `fonts`:

```text
# (unchanged lines above)
mise
wezterm
fonts
theme
```

- [ ] **Step 9: Write `tests/capabilities/wezterm.sh`**

```bash
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
  assert_contains "$(cat "$WEZ/wezterm.lua")" 'require("teeup.wezterm")' || return 1
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

test_lua_files_parse() {
  setup
  # This is the only gate on three shipped Lua files and the rendered scheme,
  # so a missing luac is a failure, not a skip. CI installs lua5.4 / lua.
  if ! command -v luac >/dev/null 2>&1; then
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
    luac -p "$f" || { echo "Lua syntax error in $f"; rc=1; }
  done
  cleanup_test_env
  return $rc
}

echo "capabilities/wezterm"
run_test "install dry run gets the cask" test_install_dry_run_gets_the_cask
run_test "install falls back to a port on macports" test_install_falls_back_to_a_port_on_macports
run_test "configure installs both user files" test_configure_installs_both_user_files
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "theme-apply reloads the config" test_theme_apply_reloads_the_config
run_test "font-apply reloads the config" test_font_apply_reloads_the_config
run_test "theme renders a wezterm scheme" test_theme_renders_a_wezterm_scheme
run_test "shipped and rendered Lua parses" test_lua_files_parse
print_summary
```

- [ ] **Step 10: Run everything**

```bash
bash tests/capabilities/wezterm.sh
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning capabilities/wezterm/install capabilities/wezterm/configure capabilities/wezterm/theme-apply capabilities/wezterm/font-apply tests/capabilities/wezterm.sh
luac -p capabilities/wezterm/config/wezterm/wezterm.lua capabilities/wezterm/config/wezterm/local.lua capabilities/wezterm/default/teeup/wezterm.lua
```

Expected: `capabilities/wezterm` prints `Summary: 9/9 passed`; `commands --check` prints nothing; `./tests/run.sh` ends with `All 27 suites passed.`; shellcheck and `luac -p` print nothing. `luac` is required, not optional: install `lua5.4` (apt) or `lua` (brew) first, and Task 8 adds the same step to CI.

- [ ] **Step 11: Commit**

```bash
git add capabilities/wezterm capabilities/core.list tests/capabilities/wezterm.sh
git commit -m "Add the wezterm capability with the teeup Lua layer and theme template"
```

---

### Task 5: `aerospace` capability

**Files:**
- Create: `capabilities/aerospace/{capability,install,configure,doctor}`, `capabilities/aerospace/config/aerospace/aerospace.toml`
- Modify: `capabilities/core.list`, `tests/bootstrap.sh`
- Test: `tests/capabilities/aerospace.sh`

**Interfaces:**
- Consumes: `casks_supported`, `cask_install` (`lib/pkg.sh`); `copy_config_once` (`lib/files.sh`); `run_cmd`, `log`, `ok`, `warn`, `err` (`lib/core.sh`); `TEEUP_CAP_DIR`.
- Produces: `~/.config/aerospace/aerospace.toml`, and `capabilities/aerospace/doctor` — the first capability in the tree to ship a `doctor` script. The `teeup doctor` verb itself is phase 4; until then the script is reachable with `cap_run aerospace doctor`, which is what its test uses.

**Decisions made here:**

1. **The tap is a separate step, not part of the cask name's resolution.** `brew install --cask nikitabobko/tap/aerospace` does tap implicitly on recent Homebrew, but doing it explicitly keeps the failure legible when the tap is unreachable, and `brew tap | grep -qx` makes it idempotent.
2. **`doctor` checks what a script may check.** Accessibility grants live in the TCC database, which no unprivileged process can read or write; the spec says so. So `doctor` verifies the app, the process and the config, and then prints the System Settings path for the one thing it cannot verify.
3. **AeroSpace is skipped, not failed, on MacPorts**, consistent with every other cask in this plan.

**Real-Mac risk:** everything about Accessibility. The first real run must confirm that AeroSpace launches, asks for Accessibility, and that `alt-h` actually moves focus once granted — plus that `alt-enter` opens WezTerm rather than a second Finder window.

- [ ] **Step 1: Write `capabilities/aerospace/capability`**

```sh
summary="AeroSpace tiling window manager"
group=macos
tier=core
requires="package-manager"
provides=""
casks="nikitabobko/tap/aerospace"
apps="AeroSpace"
interactive=false
```

- [ ] **Step 2: Write `capabilities/aerospace/install`**

```bash
#!/usr/bin/env bash
# AeroSpace ships from its author's tap, so the tap has to exist first. Doing
# it explicitly (rather than relying on the implicit tap in the cask name)
# keeps the error legible when GitHub is unreachable.
if ! casks_supported; then
  warn "AeroSpace is a cask and MacPorts has none; download it from https://github.com/nikitabobko/AeroSpace/releases"
  exit 0
fi
if brew tap 2>/dev/null | grep -qx nikitabobko/tap; then
  log "Already tapped: nikitabobko/tap"
else
  run_cmd brew tap nikitabobko/tap || warn "Could not tap nikitabobko/tap."
fi
cask_install nikitabobko/tap/aerospace
```

- [ ] **Step 3: Write `capabilities/aerospace/config/aerospace/aerospace.toml`**

```toml
# ~/.config/aerospace/aerospace.toml - yours, copied once by teeup.
# Reference: https://nikitabobko.github.io/AeroSpace/guide
#
# i3 muscle memory on macOS: alt is the modifier, hjkl moves focus,
# alt+shift+hjkl moves the window, alt+<n> switches workspace, alt+f is
# fullscreen, alt+/ flips the split orientation, alt+shift+; enters a service
# mode for the things you do once a week.

after-login-command = []
after-startup-command = []
start-at-login = true

# Containers with one child collapse, and a nested container flips its
# orientation. Both make the tree behave the way i3 users expect.
enable-normalization-flatten-containers = true
enable-normalization-opposite-orientation-for-nested-containers = true

accordion-padding = 30
default-root-container-layout = 'tiles'
default-root-container-orientation = 'auto'

# Follow the mouse to the monitor that took focus, so the next keystroke lands
# where you are looking.
on-focused-monitor-changed = ['move-mouse monitor-lazy-center']
automatically-unhide-macos-hidden-apps = false

[key-mapping]
preset = 'qwerty'

[gaps]
inner.horizontal = 8
inner.vertical = 8
outer.left = 8
outer.bottom = 8
outer.top = 8
outer.right = 8

[mode.main.binding]
alt-enter = 'exec-and-forget open -na WezTerm'

alt-slash = 'layout tiles horizontal vertical'
alt-comma = 'layout accordion horizontal vertical'
alt-f = 'fullscreen'

alt-h = 'focus left'
alt-j = 'focus down'
alt-k = 'focus up'
alt-l = 'focus right'

alt-shift-h = 'move left'
alt-shift-j = 'move down'
alt-shift-k = 'move up'
alt-shift-l = 'move right'

alt-minus = 'resize smart -50'
alt-equal = 'resize smart +50'

alt-1 = 'workspace 1'
alt-2 = 'workspace 2'
alt-3 = 'workspace 3'
alt-4 = 'workspace 4'
alt-5 = 'workspace 5'
alt-6 = 'workspace 6'
alt-7 = 'workspace 7'
alt-8 = 'workspace 8'
alt-9 = 'workspace 9'

alt-shift-1 = 'move-node-to-workspace 1'
alt-shift-2 = 'move-node-to-workspace 2'
alt-shift-3 = 'move-node-to-workspace 3'
alt-shift-4 = 'move-node-to-workspace 4'
alt-shift-5 = 'move-node-to-workspace 5'
alt-shift-6 = 'move-node-to-workspace 6'
alt-shift-7 = 'move-node-to-workspace 7'
alt-shift-8 = 'move-node-to-workspace 8'
alt-shift-9 = 'move-node-to-workspace 9'

alt-tab = 'workspace-back-and-forth'
alt-shift-tab = 'move-workspace-to-monitor --wrap-around next'

alt-shift-semicolon = 'mode service'

# Service mode: one key, one job, then back to main.
[mode.service.binding]
esc = ['reload-config', 'mode main']
r = ['flatten-workspace-tree', 'mode main']
f = ['layout floating tiling', 'mode main']
backspace = ['close-all-windows-but-current', 'mode main']
alt-shift-h = ['join-with left', 'mode main']
alt-shift-j = ['join-with down', 'mode main']
alt-shift-k = ['join-with up', 'mode main']
alt-shift-l = ['join-with right', 'mode main']
```

- [ ] **Step 4: Write `capabilities/aerospace/configure`**

```bash
#!/usr/bin/env bash
# AeroSpace has no include mechanism, so the whole file is copied once and
# belongs to the user from then on.
copy_config_once "$TEEUP_CAP_DIR/config/aerospace/aerospace.toml" "$(user_config_dir)/aerospace/aerospace.toml"

if [[ -d "${TEEUP_APPS_DIR:-/Applications}/AeroSpace.app" ]]; then
  log "AeroSpace is installed."
else
  log "AeroSpace will appear in /Applications once its cask finishes installing."
fi

# No script can grant Accessibility: macOS requires a human in System Settings,
# and doctor re-checks the part of this that is checkable.
cat <<'STEP'
One manual step, once per machine:
  System Settings > Privacy & Security > Accessibility > turn AeroSpace on
Until you do, AeroSpace cannot move a single window. Then start it with:
  open -a AeroSpace
STEP
```

- [ ] **Step 5: Write `capabilities/aerospace/doctor`**

```bash
#!/usr/bin/env bash
# Accessibility grants live in the TCC database, which no unprivileged process
# may read. So doctor checks everything else and prints the one manual step.
# TEEUP_APPS_DIR is a test hook: without it this script reads the real
# /Applications and passes or fails depending on the developer's own machine.
APPS_DIR="${TEEUP_APPS_DIR:-/Applications}"
problems=0

if [[ -d "$APPS_DIR/AeroSpace.app" ]]; then
  ok "AeroSpace is installed."
else
  err "AeroSpace is not in /Applications. Run: teeup install aerospace"
  problems=$((problems + 1))
fi

if [[ -f "$(user_config_dir)/aerospace/aerospace.toml" ]]; then
  ok "AeroSpace config present."
else
  err "No aerospace.toml. Run: teeup configure aerospace"
  problems=$((problems + 1))
fi

if pgrep -x AeroSpace >/dev/null 2>&1; then
  ok "AeroSpace is running."
else
  warn "AeroSpace is not running. Start it with: open -a AeroSpace"
fi

echo "If windows still do not move, turn AeroSpace on under System Settings > Privacy & Security > Accessibility."
[[ $problems -eq 0 ]]
```

```bash
chmod +x capabilities/aerospace/install capabilities/aerospace/configure capabilities/aerospace/doctor
```

- [ ] **Step 6: Add `aerospace` to `capabilities/core.list`**

Insert `aerospace` directly above `theme`:

```text
# (unchanged lines above)
wezterm
fonts
aerospace
theme
```

- [ ] **Step 6b: Teach the bootstrap suite about `aerospace`**

`aerospace` is now in `core.list`, so `bootstrap --dry-run` runs its `configure`, which probes `/Applications` outside `run_cmd`. Without a hook the dry-run walk says "AeroSpace is installed." on a developer's Mac and "will appear in /Applications" on CI. In `tests/bootstrap.sh`, inside `setup()`, insert one line after plan 2a's `mock_command defaults 1 ""`:

```bash
  # aerospace/configure probes /Applications outside run_cmd; point it at an
  # empty tree so the walk is the same on a developer's Mac and on CI.
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
```

This is the only change any task in this plan makes to `tests/bootstrap.sh`'s mocks; its twelve tests are unaffected.

- [ ] **Step 7: Write `tests/capabilities/aerospace.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in
  list) exit 1 ;;
  tap) exit 0 ;;
  *) exit 0 ;;
esac
EOF2
  TEEUP="$TEEUP_PATH/bin/teeup"
  AERO="$TEST_HOME/.config/aerospace/aerospace.toml"
}

test_install_taps_then_installs_the_cask() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install aerospace)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew tap nikitabobko/tap" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask nikitabobko/tap/aerospace" || return 1
  cleanup_test_env
}

test_install_skips_the_tap_when_present() {
  setup
  mock_command_script brew <<'EOF2'
case "$1" in
  list) exit 1 ;;
  tap) echo "nikitabobko/tap"; exit 0 ;;
  *) exit 0 ;;
esac
EOF2
  local out
  out="$(DRY_RUN=true "$TEEUP" install aerospace)"
  assert_contains "$out" "Already tapped: nikitabobko/tap" || return 1
  assert_not_contains "$out" "Would execute: brew tap" || return 1
  cleanup_test_env
}

test_install_is_skipped_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install aerospace 2>&1)"
  assert_contains "$out" "AeroSpace is a cask and MacPorts has none" || return 1
  assert_not_contains "$out" "brew install" || return 1
  assert_not_contains "$out" "brew tap" || return 1
  cleanup_test_env
}

test_configure_copies_the_config_and_prints_the_manual_step() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace)"
  assert_file_exists "$AERO" || return 1
  assert_contains "$(cat "$AERO")" "alt-h = 'focus left'" || return 1
  assert_contains "$(cat "$AERO")" "start-at-login = true" || return 1
  assert_contains "$out" "Privacy & Security > Accessibility" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace)"
  assert_contains "$out" "Already installed: $AERO" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  DRY_RUN=true "$TEEUP" configure aerospace >/dev/null
  [[ ! -e "$AERO" ]] || { echo "config written in dry run"; return 1; }
  cleanup_test_env
}

test_doctor_reports_the_missing_app_and_config() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  # Point at an empty tree so the result does not depend on whether the
  # developer running the suite happens to have AeroSpace installed.
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  mock_command pgrep 1 ""
  local rc=0 out
  out="$(DRY_RUN=false cap_run aerospace doctor 2>&1)" || rc=$?
  assert_failure "$rc" "doctor must exit non-zero when something is wrong" || return 1
  assert_contains "$out" "AeroSpace is not in /Applications" || return 1
  assert_contains "$out" "No aerospace.toml" || return 1
  cleanup_test_env
}

echo "capabilities/aerospace"
run_test "install taps then installs the cask" test_install_taps_then_installs_the_cask
run_test "install skips the tap when present" test_install_skips_the_tap_when_present
run_test "install is skipped on macports" test_install_is_skipped_on_macports
run_test "configure copies the config and prints the manual step" test_configure_copies_the_config_and_prints_the_manual_step
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "doctor reports the missing app and config" test_doctor_reports_the_missing_app_and_config
print_summary
```

- [ ] **Step 8: Run everything**

```bash
bash tests/capabilities/aerospace.sh
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning capabilities/aerospace/install capabilities/aerospace/configure capabilities/aerospace/doctor tests/capabilities/aerospace.sh tests/bootstrap.sh
```

Expected: `capabilities/aerospace` prints `Summary: 7/7 passed`; `commands --check` prints nothing; `./tests/run.sh` ends with `All 28 suites passed.`; shellcheck prints nothing.

- [ ] **Step 9: Commit**

```bash
git add capabilities/aerospace capabilities/core.list tests/capabilities/aerospace.sh tests/bootstrap.sh
git commit -m "Add the aerospace capability with an i3-style tiling config"
```

---

### Task 6: `keyboard` capability

**Files:**
- Create: `capabilities/keyboard/{capability,install,configure,remove}`
- Modify: `capabilities/core.list`
- Test: `tests/capabilities/keyboard.sh`

**Interfaces:**
- Consumes: `launchagent_install` (`lib/macos.sh`, Task 1); `run_cmd`, `log`, `ok` (`lib/core.sh`).
- Produces: `~/Library/LaunchAgents/sh.teeup.keyboard.plist` and the live `hidutil` mapping.

**Decisions made here:**

1. **`hidutil`, not Karabiner.** The spec's interview answer is explicit: native at bootstrap, Karabiner stays a lazy option for the hyper-key setup. `hidutil` remaps below every application, needs no driver approval and no kernel extension.
2. **The label is `sh.teeup.keyboard`**, reverse-DNS from the project's own domain, so every teeup LaunchAgent shares the `sh.teeup.` prefix and `launchctl list | grep sh.teeup` shows the lot.
3. **`configure` both installs the agent and applies the mapping.** A LaunchAgent alone would leave the current session unremapped until the next login, which reads as "teeup did nothing".
4. **`hidutil` is called by name in the scripts and by absolute path only inside the plist.** `$MOCK_BIN` is first on `PATH` in the harness, so `run_cmd /usr/bin/hidutil` would bypass the mock: on Linux it exits 127 and fails the suite, and on the macOS runners it actually remaps the runner's Caps Lock. launchd, by contrast, runs `ProgramArguments` with no `PATH`, so there the full path is required.

**Real-Mac risk:** the two HID usage numbers are the documented Caps Lock (`0x700000039`) and Left Control (`0x7000000E0`) codes, but the `--set` JSON is parsed by `hidutil` itself and has never been handed to the real binary. The first real run should end with `hidutil property --get UserKeyMapping` showing the pair back.

- [ ] **Step 1: Write `capabilities/keyboard/capability`**

```sh
summary="Caps Lock as Control, natively through hidutil"
group=macos
tier=core
requires="teeup-runtime"
provides=""
interactive=false
```

- [ ] **Step 2: Write `capabilities/keyboard/install`**

```bash
#!/usr/bin/env bash
# Nothing to install: hidutil ships with macOS at /usr/bin/hidutil. The file
# exists so the capability has the full contract.
:
```

- [ ] **Step 3: Write `capabilities/keyboard/configure`**

```bash
#!/usr/bin/env bash
# hidutil remaps at the HID layer, below every application, with no driver and
# no kernel extension. The mapping does not survive a logout, so a LaunchAgent
# re-applies it at login; this script also applies it to the running session so
# the change is immediate.
# 0x700000039 is Caps Lock and 0x7000000E0 is Left Control on HID usage page 7.
#
# hidutil is called by name, not as /usr/bin/hidutil: /usr/bin is always on
# PATH on macOS, and an absolute path would walk straight past the test
# harness's mock bin directory and remap the CI runner's own keyboard. The
# absolute path inside the plist below is different — launchd runs with no
# PATH of its own, so ProgramArguments must name the binary in full.
KEYBOARD_MAPPING='{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x7000000E0}]}'

launchagent_install sh.teeup.keyboard <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>sh.teeup.keyboard</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/hidutil</string>
    <string>property</string>
    <string>--set</string>
    <string>$KEYBOARD_MAPPING</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
</dict>
</plist>
PLIST

run_cmd hidutil property --set "$KEYBOARD_MAPPING"
ok "Caps Lock sends Control, now and at every login."
```

The heredoc terminator is unquoted on purpose: `$KEYBOARD_MAPPING` must expand, and the plist contains no other `$`.

- [ ] **Step 4: Write `capabilities/keyboard/remove`**

```bash
#!/usr/bin/env bash
# Unload the agent, drop the plist, and clear the mapping in this session.
# An empty UserKeyMapping list is hidutil's "no remapping" value.
PLIST_PATH="$HOME/Library/LaunchAgents/sh.teeup.keyboard.plist"
# UID is read-only in bash, hence the name.
UID_NUM="$(id -u)"

if [[ -f "$PLIST_PATH" ]]; then
  run_cmd launchctl bootout "gui/$UID_NUM" "$PLIST_PATH" || true
  run_cmd rm -f "$PLIST_PATH"
else
  log "No $PLIST_PATH; nothing to unload."
fi

run_cmd hidutil property --set '{"UserKeyMapping":[]}'
ok "Caps Lock is Caps Lock again."
```

```bash
chmod +x capabilities/keyboard/install capabilities/keyboard/configure capabilities/keyboard/remove
```

- [ ] **Step 5: Add `keyboard` to `capabilities/core.list`**

Insert `keyboard` directly above `theme`:

```text
# (unchanged lines above)
fonts
aerospace
keyboard
theme
```

- [ ] **Step 6: Write `tests/capabilities/keyboard.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

MAPPING='{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x7000000E0}]}'

setup() {
  setup_test_env
  mock_macos_base
  mock_command launchctl 0 ""
  mock_command hidutil 0 ""
  TEEUP="$TEEUP_PATH/bin/teeup"
  PLIST="$TEST_HOME/Library/LaunchAgents/sh.teeup.keyboard.plist"
}

test_configure_writes_the_agent_and_applies_the_mapping() {
  setup
  DRY_RUN=false "$TEEUP" configure keyboard >/dev/null
  assert_file_exists "$PLIST" || return 1
  local plist_body log_body
  plist_body="$(cat "$PLIST")"
  assert_contains "$plist_body" "<string>sh.teeup.keyboard</string>" || return 1
  assert_contains "$plist_body" "/usr/bin/hidutil" || return 1
  assert_contains "$plist_body" "HIDKeyboardModifierMappingSrc" || return 1
  log_body="$(cat "$MOCK_LOG")"
  assert_contains "$log_body" "launchctl bootstrap gui/501 $PLIST" || return 1
  assert_contains "$log_body" "hidutil property --set $MAPPING" || return 1
  cleanup_test_env
}

test_configure_is_idempotent_on_the_plist() {
  setup
  DRY_RUN=false "$TEEUP" configure keyboard >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure keyboard)"
  assert_contains "$out" "Already current: $PLIST" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" configure keyboard)"
  assert_contains "$out" "[DRY-RUN] Would write $PLIST" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: hidutil property --set $MAPPING" || return 1
  [[ ! -e "$PLIST" ]] || { echo "plist written in dry run"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "hidutil" "nothing ran in dry run" || return 1
  cleanup_test_env
}

test_remove_unloads_and_clears_the_mapping() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure keyboard >/dev/null
  DRY_RUN=false cap_run keyboard remove >/dev/null
  [[ ! -e "$PLIST" ]] || { echo "plist survived remove"; return 1; }
  local log_body
  log_body="$(cat "$MOCK_LOG")"
  assert_contains "$log_body" "launchctl bootout gui/501 $PLIST" || return 1
  assert_contains "$log_body" 'hidutil property --set {"UserKeyMapping":[]}' || return 1
  cleanup_test_env
}

test_remove_without_a_plist_is_quiet() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  local out
  out="$(DRY_RUN=false cap_run keyboard remove 2>&1)"
  assert_contains "$out" "nothing to unload" || return 1
  cleanup_test_env
}

echo "capabilities/keyboard"
run_test "configure writes the agent and applies the mapping" test_configure_writes_the_agent_and_applies_the_mapping
run_test "configure is idempotent on the plist" test_configure_is_idempotent_on_the_plist
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "remove unloads and clears the mapping" test_remove_unloads_and_clears_the_mapping
run_test "remove without a plist is quiet" test_remove_without_a_plist_is_quiet
print_summary
```

- [ ] **Step 7: Run everything**

```bash
bash tests/capabilities/keyboard.sh
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning capabilities/keyboard/install capabilities/keyboard/configure capabilities/keyboard/remove tests/capabilities/keyboard.sh
```

Expected: `capabilities/keyboard` prints `Summary: 5/5 passed`; `commands --check` prints nothing; `./tests/run.sh` ends with `All 29 suites passed.`; shellcheck prints nothing.

- [ ] **Step 8: Commit**

```bash
git add capabilities/keyboard capabilities/core.list tests/capabilities/keyboard.sh
git commit -m "Add the keyboard capability remapping Caps Lock to Control"
```

---

### Task 7: `macos-defaults` capability

**Files:**
- Create: `capabilities/macos-defaults/{capability,install,configure,remove}`
- Modify: `capabilities/core.list`
- Test: `tests/capabilities/macos-defaults.sh`

**Interfaces:**
- Consumes: `defaults_write`, `defaults_restore` (`lib/macos.sh`, Task 1); `run_cmd`, `log`, `ok` (`lib/core.sh`).
- Produces: sixteen preference writes and one recording per key under `$TEEUP_STATE_DIR/defaults/<domain>.<key>`; `~/Screenshots`.

**Decisions made here:**

1. **One `defaults_write` per line, each with the reason on the same line.** The spec asks for "one unit each, revertable"; in a single capability the unit is the line, and the recording under `state/defaults/` is what makes it revertable.
2. **`killall Finder` and `killall Dock` are two calls with `|| true`.** `killall Finder Dock` fails as a whole when either process is not running, and a failing command aborts a `bash -eu` capability script.
3. **`~/Screenshots` is created before the preference points at it**, so the first screenshot after bootstrap does not land nowhere.

**Real-Mac risk:** `defaults read` returns `0`/`1` for booleans, so a restored boolean is written back as `-bool 0`, which is correct but does not look like what the user originally typed. `KeyRepeat` and `InitialKeyRepeat` only take effect after a logout. Neither has been observed on hardware.

- [ ] **Step 1: Write `capabilities/macos-defaults/capability`**

```sh
summary="Opinionated macOS preferences for development"
group=macos
tier=core
requires="teeup-runtime"
provides=""
interactive=false
```

- [ ] **Step 2: Write `capabilities/macos-defaults/install`**

```bash
#!/usr/bin/env bash
# Nothing to install; every preference is written by configure.
:
```

- [ ] **Step 3: Write `capabilities/macos-defaults/configure`**

```bash
#!/usr/bin/env bash
# One preference per line, each with its reason. Every write records the prior
# value under state/defaults/, so `teeup remove macos-defaults` restores the
# machine to exactly what it was before teeup touched it.

# Files: see what you are actually working with.
defaults_write NSGlobalDomain AppleShowAllExtensions -bool true              # never hide an extension
defaults_write com.apple.finder AppleShowAllFiles -bool true                 # dotfiles are files
defaults_write com.apple.finder ShowPathbar -bool true                       # know where you are
defaults_write com.apple.finder FXPreferredViewStyle -string Nlsv            # list view everywhere
defaults_write com.apple.finder FXEnableExtensionChangeWarning -bool false   # renaming .txt to .md is not an event

# Dialogs: expanded, always.
defaults_write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true  # full Save panel
defaults_write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true     # full Print panel

# Typing: fast repeat, and no "helpful" rewriting of code.
defaults_write NSGlobalDomain KeyRepeat -int 2                               # fastest repeat (needs a logout)
defaults_write NSGlobalDomain InitialKeyRepeat -int 15                       # shortest delay before repeat
defaults_write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false      # "smart" quotes break code
defaults_write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false       # -- must stay --
defaults_write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false         # git is not Git
defaults_write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false     # no autocorrect in a commit message

# Dock and trackpad.
defaults_write com.apple.dock autohide -bool true                            # screen space for windows
defaults_write com.apple.AppleMultitouchTrackpad Clicking -bool true         # tap to click

# Screenshots out of the way of the Desktop.
SHOTS="$HOME/Screenshots"
if [[ -d "$SHOTS" ]]; then
  log "Already present: $SHOTS"
else
  run_cmd mkdir -p "$SHOTS"
fi
defaults_write com.apple.screencapture location -string "$SHOTS"

# Finder and Dock read most of these only at start. killall fails when a
# process is not running, which must not abort the script.
run_cmd killall Finder || true
run_cmd killall Dock || true
ok "macOS preferences applied. KeyRepeat and InitialKeyRepeat take effect after the next login."
```

- [ ] **Step 4: Write `capabilities/macos-defaults/remove`**

```bash
#!/usr/bin/env bash
# Replay what defaults_write recorded: a key that was absent is deleted, a key
# that had a value is written back with its original type.
defaults_restore NSGlobalDomain AppleShowAllExtensions
defaults_restore com.apple.finder AppleShowAllFiles
defaults_restore com.apple.finder ShowPathbar
defaults_restore com.apple.finder FXPreferredViewStyle
defaults_restore com.apple.finder FXEnableExtensionChangeWarning
defaults_restore NSGlobalDomain NSNavPanelExpandedStateForSaveMode
defaults_restore NSGlobalDomain PMPrintingExpandedStateForPrint
defaults_restore NSGlobalDomain KeyRepeat
defaults_restore NSGlobalDomain InitialKeyRepeat
defaults_restore NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled
defaults_restore NSGlobalDomain NSAutomaticDashSubstitutionEnabled
defaults_restore NSGlobalDomain NSAutomaticCapitalizationEnabled
defaults_restore NSGlobalDomain NSAutomaticSpellingCorrectionEnabled
defaults_restore com.apple.dock autohide
defaults_restore com.apple.AppleMultitouchTrackpad Clicking
defaults_restore com.apple.screencapture location

run_cmd killall Finder || true
run_cmd killall Dock || true
ok "macOS preferences restored. ~/Screenshots was left alone; delete it yourself if you want it gone."
```

```bash
chmod +x capabilities/macos-defaults/install capabilities/macos-defaults/configure capabilities/macos-defaults/remove
```

- [ ] **Step 5: Add `macos-defaults` to `capabilities/core.list`**

Insert `macos-defaults` directly above `theme`:

```text
# (unchanged lines above)
aerospace
keyboard
macos-defaults
theme
```

- [ ] **Step 6: Write `tests/capabilities/macos-defaults.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command killall 0 ""
  mock_defaults_absent
  TEEUP="$TEEUP_PATH/bin/teeup"
  RECORDS="$TEST_HOME/.local/state/teeup/defaults"
}

mock_defaults_absent() {
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) exit 1 ;;
  *) exit 0 ;;
esac
EOF2
}

test_configure_writes_every_preference() {
  setup
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  local log_body
  log_body="$(cat "$MOCK_LOG")"
  assert_contains "$log_body" "defaults write NSGlobalDomain AppleShowAllExtensions -bool true" || return 1
  assert_contains "$log_body" "defaults write com.apple.finder FXPreferredViewStyle -string Nlsv" || return 1
  assert_contains "$log_body" "defaults write NSGlobalDomain KeyRepeat -int 2" || return 1
  assert_contains "$log_body" "defaults write NSGlobalDomain InitialKeyRepeat -int 15" || return 1
  assert_contains "$log_body" "defaults write com.apple.dock autohide -bool true" || return 1
  assert_contains "$log_body" "defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true" || return 1
  assert_contains "$log_body" "defaults write com.apple.screencapture location -string $TEST_HOME/Screenshots" || return 1
  assert_contains "$log_body" "killall Finder" || return 1
  assert_contains "$log_body" "killall Dock" || return 1
  cleanup_test_env
}

test_configure_records_every_key_and_creates_the_screenshots_dir() {
  setup
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  assert_dir_exists "$TEST_HOME/Screenshots" || return 1
  assert_equals "absent" "$(cat "$RECORDS/NSGlobalDomain.AppleShowAllExtensions")" || return 1
  assert_equals "absent" "$(cat "$RECORDS/com.apple.dock.autohide")" || return 1
  assert_equals "16" "$(find "$RECORDS" -type f | wc -l | tr -d ' ')" "one record per preference" || return 1
  cleanup_test_env
}

test_configure_records_a_prior_value() {
  setup
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) echo 1; exit 0 ;;
  *) exit 0 ;;
esac
EOF2
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  assert_equals "-bool:1" "$(cat "$RECORDS/com.apple.dock.autohide")" || return 1
  assert_equals "-int:1" "$(cat "$RECORDS/NSGlobalDomain.KeyRepeat")" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure macos-defaults)"
  assert_contains "$out" "Already present: $TEST_HOME/Screenshots" || return 1
  assert_equals "absent" "$(cat "$RECORDS/com.apple.dock.autohide")" "the record is never refreshed" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" configure macos-defaults)"
  assert_contains "$out" "[DRY-RUN] Would execute: defaults write com.apple.dock autohide -bool true" || return 1
  assert_contains "$out" "[DRY-RUN] Would record defaults/com.apple.dock.autohide as absent" || return 1
  [[ ! -d "$RECORDS" ]] || { echo "records written in dry run"; return 1; }
  [[ ! -d "$TEST_HOME/Screenshots" ]] || { echo "Screenshots created in dry run"; return 1; }
  cleanup_test_env
}

test_remove_restores_every_key() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  : > "$MOCK_LOG"
  DRY_RUN=false cap_run macos-defaults remove >/dev/null
  local log_body
  log_body="$(cat "$MOCK_LOG")"
  assert_contains "$log_body" "defaults delete com.apple.dock autohide" || return 1
  assert_contains "$log_body" "defaults delete com.apple.screencapture location" || return 1
  assert_equals "0" "$(find "$RECORDS" -type f | wc -l | tr -d ' ')" "every record is consumed" || return 1
  cleanup_test_env
}

test_remove_rewrites_a_recorded_value() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mkdir -p "$RECORDS"
  printf -- '-bool:1\n' > "$RECORDS/com.apple.dock.autohide"
  DRY_RUN=false cap_run macos-defaults remove >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "defaults write com.apple.dock autohide -bool 1" || return 1
  cleanup_test_env
}

echo "capabilities/macos-defaults"
run_test "configure writes every preference" test_configure_writes_every_preference
run_test "configure records every key and creates ~/Screenshots" test_configure_records_every_key_and_creates_the_screenshots_dir
run_test "configure records a prior value" test_configure_records_a_prior_value
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "remove restores every key" test_remove_restores_every_key
run_test "remove rewrites a recorded value" test_remove_rewrites_a_recorded_value
print_summary
```

- [ ] **Step 7: Run everything**

```bash
bash tests/capabilities/macos-defaults.sh
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning capabilities/macos-defaults/install capabilities/macos-defaults/configure capabilities/macos-defaults/remove tests/capabilities/macos-defaults.sh
```

Expected: `capabilities/macos-defaults` prints `Summary: 7/7 passed`; `commands --check` prints nothing; `./tests/run.sh` ends with `All 30 suites passed.`; shellcheck prints nothing.

- [ ] **Step 8: Commit**

```bash
git add capabilities/macos-defaults capabilities/core.list tests/capabilities/macos-defaults.sh
git commit -m "Add the macos-defaults capability with recorded, revertable writes"
```

---

### Task 8: Manifest, README and contributor docs

**Files:**
- Modify: `capabilities/core.list`, `bootstrap`, `tests/bootstrap.sh`, `.github/workflows/ci.yml`, `README.md`, `CONTRIBUTING.md`
- No new test files; this task runs every existing one.

**Interfaces:**
- Consumes: everything the previous seven tasks produced, plus `theme_list` (Task 2).
- Produces: the complete core manifest in spec order, a wizard that only offers themes that exist, CI that shellchecks the optional capability verbs and really runs the Lua check, a README that names the desktop capabilities and the two new verbs, and the `themed/*.tpl` / `theme-apply` / `font-apply` contract written down where a contributor will look for it.

- [ ] **Step 1: Check `capabilities/core.list` against the spec order**

After Tasks 2 to 7 the file has been edited six times. Read it and make it exactly this (the eight names between `dev-dirs` and `wezterm` come from plan 2a; if 2a swapped `git` and `mise` for the `pre-commit` ordering decision, keep 2a's order for those two and change nothing else):

```text
# Core tier: what every terminal session needs. Ordered; each entry's
# requires= must already be satisfied by the entries above it.
xcode-clt
package-manager
teeup-runtime
dev-dirs
zsh
starship
cli-tools
secrets
git
ssh
github
mise
wezterm
fonts
aerospace
keyboard
macos-defaults
theme
```

`theme` is last on purpose: `theme_set` renders `capabilities/*/themed/*.tpl`, so every capability that owns a template has to be configured before it runs. The third comment line — plan 2a left it as `# Plan 2b appends: wezterm fonts aerospace keyboard macos-defaults theme`, and Task 2 rewrote it to `# This plan still inserts, above theme: …` — is deleted here, because there is nothing left to insert.

(Plan 2a's header line says "2b appends its five names" while its own Task 10 says six; six is right — `wezterm fonts aerospace keyboard macos-defaults theme`. The eighteen-line list above is the authority, and it is the spec's section 5 core list verbatim.)

- [ ] **Step 1b: Offer only themes that exist in the bootstrap wizard**

The phase 1 wizard hard-codes four theme names and only `catppuccin` ships. `theme_set` now falls back rather than failing (Task 2, Decision 7), but the better fix is not to offer a theme that does not exist. In `bootstrap`, inside `wizard()`, replace:

```bash
  theme="$(ui_choose "Theme (applied once the theme capability lands)" catppuccin tokyo-night gruvbox nord)"
```

with:

```bash
  # Offer what themes/ actually ships, so an answer can never name a palette
  # that theme_set would have to fall back from.
  # shellcheck disable=SC2046  # one option per word is exactly what ui_choose wants
  theme="$(ui_choose "Theme" $(theme_list))"
```

The unquoted `$(theme_list)` is deliberate — `ui_choose` takes one option per argument and theme names never contain whitespace — hence the scoped `SC2046` suppression, without which the shellcheck gate would fail. `theme_list` lives in `lib/theme.sh`, which `bootstrap` already has through `lib/all.sh`.

Then in `tests/bootstrap.sh`, update the comment above `WIZARD_INPUT` so the piped answers still read correctly:

```bash
# Answers piped to the plain-read wizard, one per prompt:
# name, email, work email, package manager choice, theme choice (1 = the first
# theme themes/ ships, i.e. catppuccin), daily confirm.
```

The piped `1` picks the first option either way, so `WIZARD_INPUT` itself does not change. Add one assertion to `test_dry_run_walks_core_tier_in_order`, after the `Would set TEEUP_NAME` line:

```bash
  assert_contains "$out" "Would set TEEUP_THEME" || return 1
  assert_not_contains "$out" "tokyo-night" "the wizard must not offer an unshipped theme" || return 1
```

Verify the order matches the spec:

```bash
grep -v '^#' capabilities/core.list | grep -v '^[[:space:]]*$' | tr '\n' ' '
```

Expected: `xcode-clt package-manager teeup-runtime dev-dirs zsh starship cli-tools secrets git ssh github mise wezterm fonts aerospace keyboard macos-defaults theme ` — the spec's core list from section 5, in order.

- [ ] **Step 2: Update `README.md`**

Replace the sentence that starts `Capabilities implemented so far:` (whatever plan 2a left there) with:

```markdown
The core tier is complete: `xcode-clt`, `package-manager`, `teeup-runtime`,
`dev-dirs`, `zsh`, `starship`, `cli-tools`, `secrets`, `git`, `ssh`, `github`,
`mise`, `wezterm`, `fonts`, `aerospace`, `keyboard`, `macos-defaults`,
`theme`. The daily tier and everything lazy arrive in phase 3; `teeup list` is
always the source of truth.
```

and add these two lines to the command block directly above it, after `teeup install <name>      # install and configure one capability`:

```text
teeup theme set catppuccin        # re-render every app's colours, light and dark
teeup install font "Fira Code"    # switch every tool to another Nerd Font
```

- [ ] **Step 3: Check the help text**

`teeup theme` was added to `usage()` in Task 2 and `teeup install font` in Task 3. Confirm both are there rather than adding them twice:

```bash
./bin/teeup help | grep -E 'install font|theme set'
```

Expected (two lines; they are not adjacent in the help text — `install font` sits under `teeup install`, `theme` under `teeup list`, and plan 2a's `secret` line sits under `has`):

```text
  teeup install font <name>      install a Nerd Font and point every tool at it
  teeup theme set|list|current   apply, list or print the cross-tool theme
```

- [ ] **Step 3b: Make CI cover the new scripts and the Lua check**

Plan 2a's Task 10 added an `Install zsh` step to `.github/workflows/ci.yml` and deliberately left the shellcheck step alone, so after 2a the two relevant stanzas read:

```yaml
      - name: Install zsh (the shell layer's tests need it)
        shell: bash
        run: |
          if [[ "$RUNNER_OS" == "Linux" ]]; then
            sudo apt-get update
            sudo apt-get install -y zsh
          fi
          zsh --version
```

```yaml
      - name: Shellcheck new runtime
        run: |
          shellcheck --severity=warning bootstrap bin/teeup lib/*.sh \
            capabilities/*/install capabilities/*/configure \
            tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh \
            tests/lib/*.sh tests/capabilities/*.sh
```

Two problems for this plan: that glob never sees the `theme-apply`, `font-apply`, `remove` and `doctor` scripts added here, and `luac` is on none of the three runner images, so `test_lua_files_parse` would fail everywhere now that it no longer skips.

Insert an `Install lua` step **directly after** 2a's `Install zsh` step:

```yaml
      - name: Install lua (the wezterm suite parses the shipped Lua)
        shell: bash
        run: |
          if [[ "$RUNNER_OS" == "Linux" ]]; then
            sudo apt-get install -y lua5.4
          else
            brew install lua
          fi
          luac -v
```

The Linux branch needs no `apt-get update`: 2a's zsh step directly above already ran one on that runner. `luac -v` turns a missing interpreter into a failed step with an obvious message, the same way 2a's `zsh --version` does.

Then replace 2a's `Shellcheck new runtime` step with:

```yaml
      - name: Shellcheck new runtime
        run: |
          shellcheck --severity=warning bootstrap bin/teeup lib/*.sh \
            $(find capabilities -type f \( -name install -o -name configure \
              -o -name remove -o -name doctor -o -name theme-apply \
              -o -name font-apply \)) \
            tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh \
            tests/lib/*.sh tests/capabilities/*.sh
```

Only the second line changes: `capabilities/*/install capabilities/*/configure` becomes the `find`. The rest of the step, and every other step 2a left in the file, is untouched.

- [ ] **Step 4: Document the theme and font contracts in `CONTRIBUTING.md`**

Append to the "Adding a capability (new runtime)" section, after item 7:

```markdown
8. If the tool has colours, add `capabilities/<name>/themed/<file>.tpl`.
   `teeup theme set` renders every template once per mode with `{{ key }}`,
   `{{ key_strip }}` (no leading `#`) and `{{ key_rgb }}` (`r,g,b`) replaced
   from `themes/<theme>/{dark,light}.toml`, and stages the results in
   `~/.local/state/teeup/current/theme/<mode>/<file>`. A user template of the
   same basename in `~/.config/teeup/themed/` wins.
9. If the tool needs to be told about a new theme or font, add an executable
   `capabilities/<name>/theme-apply` or `capabilities/<name>/font-apply`. Both
   run exactly like `install` and `configure` (`bash -eu`, `lib/all.sh`
   loaded, answers sourced, `TEEUP_CAP` and `TEEUP_CAP_DIR` exported).
   `theme-apply` additionally gets `TEEUP_THEME_DIR`
   (`~/.local/state/teeup/current/theme`) and `TEEUP_THEME_NAME`;
   `font-apply` gets `TEEUP_FONT_FAMILY`. Both are optional, and a failure
   warns without aborting the switch, so keep them to "tell the app to
   reload" rather than real work.
10. Native macOS settings go through `lib/macos.sh`: `defaults_write` (which
    records the prior value so `remove` can call `defaults_restore`) and
    `launchagent_install <label>` with the plist on stdin. Never call
    `defaults write` or `launchctl` directly.
```

- [ ] **Step 5: Run everything, twice**

```bash
./bin/teeup commands --check
./tests/run.sh
./legacy/tests/run_tests.sh
shellcheck --severity=warning bootstrap bin/teeup lib/*.sh \
  $(find capabilities -type f \( -name install -o -name configure \
    -o -name remove -o -name doctor -o -name theme-apply -o -name font-apply \)) \
  tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh \
  tests/lib/*.sh tests/capabilities/*.sh
./tests/run.sh
```

Expected: `commands --check` prints nothing and exits 0; both `./tests/run.sh` runs end with `All 30 suites passed.`; `./legacy/tests/run_tests.sh` prints `All tests passed!`; shellcheck prints nothing. The `find` is the same expression Step 3b puts in CI — a glob like `capabilities/*/doctor` expands to a literal unmatched path when only one capability ships that verb, which shellcheck then reports as a missing file.

- [ ] **Step 6: Walk the whole core tier once, in dry run**

```bash
./bootstrap --dry-run --skip-daily </dev/null 2>&1 | grep -E 'Completed: (wezterm|fonts|aerospace|keyboard|macos-defaults|theme) '
```

Expected, in this order:

```text
[...] Completed: wezterm install
[...] Completed: wezterm configure
[...] Completed: fonts install
[...] Completed: fonts configure
[...] Completed: aerospace install
[...] Completed: aerospace configure
[...] Completed: keyboard install
[...] Completed: keyboard configure
[...] Completed: macos-defaults install
[...] Completed: macos-defaults configure
[...] Completed: theme install
[...] Completed: theme configure
[...] Completed: theme configure
```

`theme configure` appears **twice**: once from the core tier and once from `bootstrap`'s step 7, which has run `cap_run theme configure` since phase 1 (`bootstrap:145-147`) for the days when `theme` was not yet in the list. It is idempotent, so the second run is only a few hundred milliseconds of re-rendering; removing the step belongs with phase 4's `update` work, not here.

(Run this from a machine with no `~/.config/teeup/answers`, or pass `--reconfigure` and answer the wizard; on a Linux workstation the run stops at `xcode-clt` because `bootstrap` refuses a non-Darwin `uname`, which is why the mocked `tests/bootstrap.sh` is the real gate and this command is only meaningful on macOS.)

- [ ] **Step 7: Commit**

```bash
git add capabilities/core.list bootstrap tests/bootstrap.sh .github/workflows/ci.yml README.md CONTRIBUTING.md
git commit -m "Complete the core tier manifest and document themes and fonts"
```

---

## Verification

Run from the repository root, on a machine with `shellcheck` and `lua` installed (`sudo apt-get install -y shellcheck lua5.4`, or `brew install shellcheck lua`; `luac` is required, the Lua suite fails without it):

```bash
./bin/teeup commands --check          # capability metadata lint; prints nothing
./tests/run.sh                        # All 30 suites passed.
./legacy/tests/run_tests.sh           # All tests passed!
shellcheck --severity=warning bootstrap bin/teeup lib/*.sh \
  $(find capabilities -type f \( -name install -o -name configure \
    -o -name remove -o -name doctor -o -name theme-apply -o -name font-apply \)) \
  tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh \
  tests/lib/*.sh tests/capabilities/*.sh
luac -p capabilities/wezterm/config/wezterm/wezterm.lua \
        capabilities/wezterm/config/wezterm/local.lua \
        capabilities/wezterm/default/teeup/wezterm.lua
```

Then, under a throwaway `$HOME`, prove the pipeline end to end:

```bash
tmp="$(mktemp -d)"
HOME="$tmp" XDG_CONFIG_HOME="$tmp/.config" XDG_STATE_HOME="$tmp/.local/state" \
  ./bin/teeup configure theme
find "$tmp/.local/state/teeup/current" -type f | sort
```

Expected: `current/font` is absent (that is the `fonts` capability's file), and `current/theme.name` plus `current/theme/{dark,light}/{colors.toml,env.sh,starship-palette.toml,wezterm.lua}` all exist, with no `{{` left in any of them.

**What the first real run on a Mac should show.** Nothing in this plan has executed on macOS. In order:

1. `./bootstrap --dry-run` walks the full core list and prints a `brew install --cask` line for `wezterm`, `font-jetbrains-mono-nerd-font` and `nikitabobko/tap/aerospace`, plus sixteen `defaults write` lines and one `hidutil property --set`.
2. `./bootstrap` installs them for real. WezTerm appears in `/Applications`; `teeup theme current` prints `catppuccin`; a **new** WezTerm window is Catppuccin-coloured in JetBrainsMono Nerd Font, and `CTRL+Space 3` splits it.
3. Caps Lock sends Control immediately, and `hidutil property --get UserKeyMapping` lists the pair. After a logout and login it still does, which is the LaunchAgent's job.
4. Finder shows hidden files and a path bar; the Dock hides; screenshots land in `~/Screenshots`. Key repeat only speeds up after the next login.
5. AeroSpace prints its Accessibility instruction and does nothing until the toggle is flipped in System Settings; afterwards `alt-h` moves focus and `alt-enter` opens WezTerm.
6. Switching System Settings to Light mode re-colours WezTerm on the spot (it re-evaluates the config and finds `teeup-light` already registered). The starship prompt follows on the next `teeup theme set catppuccin`, which is the known gap recorded below. Check the prompt really changed: `head -3 ~/.config/starship.toml` must show `palette = "teeup-light"` as the **first** line, above every `[table]`. If instead `theme-apply` printed "below its first [table]", plan 2a's `starship.toml` moved and the palette block has to go back to the top of the file.
7. `teeup install font "Cascadia Mono"` installs the cask, rewrites `current/font` and reloads WezTerm into the new family.
8. `teeup remove macos-defaults` (via `cap_run`, until the `remove` verb lands in phase 4) puts every preference back to what `defaults read` reported before bootstrap.

---

## Self-review

### Spec coverage

| Spec requirement | Section | Task |
|---|---|---|
| `lib/macos.sh`: `defaults_write` records prior value, `launchagent_install`, `appearance` | 4, 7 | 1 |
| `state/defaults/<domain>.<key>` holds `absent` or `<type>:<value>`; `remove` replays it | 7 | 1, 7 |
| LaunchAgents replace systemd user units | 2 | 1, 6 |
| `lib/theme.sh`: palette parse, template render, stage and swap | 4 | 2 |
| `themes/<name>/{dark,light}.toml` semantic palette; every theme ships both modes | 2, 7 | 2 |
| `teeup theme set` renders every `capabilities/*/themed/*.tpl`, user templates from `~/.config/teeup/themed/` first, staged then swapped | 7 | 2 |
| Shell tools pick the variant from `TEEUP_APPEARANCE`, exported from `AppleInterfaceStyle` | 7 | 2 (contract), 1 (`appearance`) |
| `bat` themed via `BAT_THEME` | 7 | 2 |
| Starship gets "the whole file copied and a managed block for theme colours" | 7 | 2 (`theme-apply`) |
| `teeup theme set|list|current` | CLI surface | 2 |
| `teeup install font <name>` installs the Nerd Font cask, writes `state/current/font`, switches the terminal font | 7 | 3 |
| JetBrainsMono Nerd Font at bootstrap | interview: Fonts | 3 |
| Casks skipped with a note on MacPorts | 4a, 7 | 3, 4, 5 |
| WezTerm, Lua, three-tier `package.path`, thin user file requiring the thick default | 2, 7 | 4 |
| Port the ~300-line WezTerm config, minus the work Jira rule which moves to a local file | 10 | 4 |
| `current/font` read by WezTerm through the default Lua layer | 7 | 4 |
| AeroSpace (TOML), Accessibility printed by `configure` and checked by `doctor` | 5, interview: WM | 5 |
| Native `hidutil` Caps Lock → Control at bootstrap, as a LaunchAgent | 5, interview: Keyboard | 6 |
| Opinionated macOS dev preferences, one unit each, revertable | 7, interview: macOS prefs | 7 |
| Core list ordering `… wezterm fonts aerospace keyboard macos-defaults theme` | 5 | 2–8 (each task inserts its own name; Task 8 verifies the whole order) |
| `config/` copied once and user-owned; `default/` referenced at runtime; `themed/*.tpl` rendered | 4, 7 | 4, 5 |

### Review fixes folded in (report: `.superpowers/sdd/phase2b-plan-review.md`)

| Finding | Change |
|---|---|
| B1 `hidutil` absolute path bypassed the mock and would remap the CI runners | Task 6 calls `hidutil` by name through `run_cmd` in `configure` and `remove`; `/usr/bin/hidutil` stays only inside the plist's `ProgramArguments`, which launchd resolves with no `PATH`. Dry-run assertion and a new Decision 4 follow. Grepped: no `run_cmd /usr/...` remains anywhere. |
| B2 `theme` is core and died for three of the four wizard themes | `theme_set` warns and falls back to `catppuccin` (Task 2, Decision 7 and `TEEUP_THEME_FALLBACK`); only a missing `catppuccin` still fails. Task 8 Step 1b drives the wizard's options from `theme_list` and updates `tests/bootstrap.sh`. Two tests replace the old "unknown theme fails" test. |
| I1 the root `palette =` key bound to the wrong TOML table | Contract 3 now states that 2a places the `palette =` line and the marker block above the first `[table]`, and why. `theme-apply` compares the start-marker line number with the first `^\[` line and warns and exits rather than writing an inert palette; the Task 2 fixture uses the top-of-file layout and a new test covers the refusal. |
| I2 CI shellchecked neither the optional verbs nor ran the Lua check | Task 8 Step 3b replaces the CI shellcheck glob with a `find` over `install configure remove doctor theme-apply font-apply`, and adds an `Install lua` step. `test_lua_files_parse` now fails instead of skipping when `luac` is missing, and returns through `cleanup_test_env`. |
| I3 the `cmd_install` anchor did not survive 2a | Task 3 Step 4 quotes 2a's post-Task-1 line (`local target="${1:-}" order c`), shows the whole resulting function head, and names a second anchor. |
| I4 un-`pcall`'d `require` | The thin `wezterm.lua` wraps the require, falls back to a minimal config (JetBrainsMono Nerd Font, no bindings) and calls `wezterm.log_error` with the resolved `teeup_search_path`. |
| I5 dead `launchctl`/`hidutil` mocks in the bootstrap test | Task 1 Step 6 adds only the `defaults` mock, and says why it is load-bearing (`defaults read` runs outside `run_cmd`) and why the other two would be dead code. |
| Minor 1, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 17, 20 | capability suite count 14/14; `_theme_sed_entry`'s `_rgb` guard requires six hex digits; `user_config_dir` replaces all five hand-rolled `${XDG_CONFIG_HOME:-…}`; `TEEUP_APPS_DIR` makes the aerospace doctor test hermetic; a comment explains the state tier of `package.path`; `theme-apply` defaults `TEEUP_THEME_DIR`; `cap_run_optional` honours `TEEUP_SKIP` (with a test); the starship palette gains `black` and `white`; the `luac` loop cleans up on failure; `lib/font.sh` is flagged as an addition to the spec's `lib/` table; the `teeup help` expectation greps instead of claiming adjacency; the `set -e` constraint is corrected to "last command only"; Task 2's `core.list` comment no longer says "Later phases". |
| Minor 2, 3, 9, 16, 18, 19 | Not changed: each is a documented trade (regenerate-always, unconditional `killall`, two near-identical reload hooks, 2a's unanchored test append, the reprinted Accessibility notice, the one-`mv` swap window) and each already carries its justification in the task text or the deferred list. |
| Minor 4 | Task 8 Step 6's expected output now shows `Completed: theme configure` twice and explains the duplicate from `bootstrap:145-147`. |

### Re-anchoring on plan 2a's revised text

2a was revised after this plan's first review pass. Re-read and re-anchored against its final version:

- **`.github/workflows/ci.yml`** — 2a's Task 10 adds an `Install zsh` step after `Install shellcheck` and leaves `Shellcheck new runtime` untouched. Task 8 Step 3b now quotes both of those stanzas as the "before", inserts `Install lua` directly after the zsh step (no `apt-get update`, because 2a's step above it already ran one), and replaces exactly one line of the shellcheck step.
- **`tests/bootstrap.sh`** — 2a grows `setup()` in eight of its ten tasks. Task 1 Step 6 quotes 2a's final `setup()` and shows that this plan needs **no** `defaults` mock of its own (2a already adds `mock_command defaults 1 ""` for the zsh appearance read, and that mock is exactly right for `defaults_write` under `DRY_RUN=true`), no `launchctl`/`hidutil` mock (dead code in a dry-run-only suite) and no `TEEUP_TEST_MISSING` entries (nothing here branches on `have`). The single real addition, `export TEEUP_APPS_DIR="$TEST_HOME/Applications"`, moved into Task 5 alongside the `core.list` insertion that makes it necessary, following 2a's own discipline.
- **`capabilities/core.list`** — Task 2 Step 7 now quotes 2a's twelve-line final file, including its `# Plan 2b appends: …` comment, as the "before"; 2a's Decisions table keeps `git` before `mise`, so that order is fixed, not conditional. Task 8 names both earlier spellings of the comment line it deletes.
- **Counts** — 2a's per-suite table gives `tests/lib/capability.sh` 11 after 2a (Task 1 here makes it 14) and `tests/bootstrap.sh` 12 unchanged; the 21-suite baseline in Global Constraints is 2a's own Task 10 figure rather than an estimate.
- **Contract 3** — 2a's review fix B3 moved `palette` and the marker block above every table header, which is what this plan's `theme-apply` guard checks for. The two plans now agree; 2a's deferred list points the light/dark palette switch at 2b, which is Task 2.

### Placeholder scan

No `TBD`, `TODO`, `FIXME`, bare `...` standing in for code, or "same as Task N" anywhere. The five `core.list` excerpts in Tasks 3 to 7 elide the lines above the insertion point as `# (unchanged lines above)`, which is a comment in that file's own syntax and so is harmless even if it were pasted literally; Task 8 prints the file in full. Every shipped file appears in full: `lib/macos.sh`, `lib/theme.sh`, `lib/font.sh`, both palette TOMLs, all four `.tpl` templates, all three WezTerm Lua files, `aerospace.toml`, every `capability` metadata file, every `install`/`configure`/`remove`/`doctor`/`theme-apply`/`font-apply` script, and all nine test files. The only cross-references are the three "insert this line into an existing file" edits (`lib/all.sh`, `bin/teeup`, `capabilities/core.list`), each of which quotes the before and after text.

### Name and type consistency across tasks

- `defaults_write <domain> <key> <type> <value>` and `defaults_restore <domain> <key>` (Task 1) match all sixteen call pairs in Task 7, and the record path `$TEEUP_STATE_DIR/defaults/<domain>.<key>` is asserted in both `tests/lib/macos.sh` and `tests/capabilities/macos-defaults.sh`.
- `launchagent_install <label>` with content on stdin (Task 1) matches the single call in Task 6; the label `sh.teeup.keyboard` appears identically in `configure`, `remove` and both tests.
- `cap_run_optional <name> <verb>` (Task 1) is called by `theme_set` (Task 2) with `theme-apply` and by `font_set` (Task 3) with `font-apply`; the hook scripts it runs are Task 2's `capabilities/theme/theme-apply` and Task 4's `capabilities/wezterm/{theme-apply,font-apply}`.
- `TEEUP_THEME_DIR` is exported by `theme_set` and read by `capabilities/theme/theme-apply`; `TEEUP_FONT_FAMILY` is exported by `font_set` and read by the fixture hook in `tests/lib/font.sh`. Neither name appears anywhere else.
- `$TEEUP_STATE_DIR/current/theme/<mode>/` is written by `theme_set` (Task 2), read by `capabilities/theme/theme-apply` (starship, Task 2), by the WezTerm default layer (Task 4, as `STATE .. "/current/theme/" .. mode .. "/wezterm.lua"`), and by plan 2a's zsh layer (`env.sh`). One path, four readers, spelled the same in all four.
- `$TEEUP_STATE_DIR/current/font` is written by `font_set` and `capabilities/fonts/configure` (both through `font_file`), and read by `font_current` and by the WezTerm layer's `M.font_family`.
- `appearance` (Task 1) is called only by `capabilities/theme/theme-apply`; it returns `dark`/`light`, which is exactly what the palette `mode` key and the `teeup-<mode>` scheme and palette names use.
- Template token names are the palette keys and nothing else: every `{{ … }}` in `env.sh.tpl`, `starship-palette.toml.tpl` and `wezterm.lua.tpl` (`mode accent bat_theme selection muted background dark_background lighter_background foreground light_foreground bright_foreground red orange yellow green cyan blue magenta bright_red bright_yellow bright_green bright_cyan bright_blue bright_magenta`) is defined in both `themes/catppuccin/dark.toml` and `light.toml`. `darker_background`, `dark_foreground` and `brown` are defined but unused, which is deliberate: they exist for phase 3's Neovim and editor templates.
- `lib/all.sh`'s source list ends as `files state answers pkg ui capability macos theme font` — `macos` after `files` (it calls `write_managed_file`), `theme` and `font` after `capability` (they call `cap_list`/`cap_run_optional`) and after `pkg` (`font_set` calls `cask_install`).
- Suite counts rise 21 → 22 → 24 → 26 → 27 → 28 → 29 → 30 across Tasks 1 to 7 and stay at 30 for Task 8, matching the number of test files each task adds. Per-suite `run_test` counts, re-counted from the plan text after the review pass: `lib/macos.sh` 11, `lib/capability.sh` 14 (10 + 1 from 2a + 3 here), `lib/theme.sh` 10, `capabilities/theme` 8, `lib/font.sh` 8, `capabilities/fonts` 8, `capabilities/wezterm` 9, `capabilities/aerospace` 7, `capabilities/keyboard` 5, `capabilities/macos-defaults` 7.
- Every command the harness mocks is called by bare name. Grepped for `run_cmd /usr/`, `/usr/bin/` and `/usr/sbin/` across the plan: the only remaining absolute paths are the `<string>/usr/bin/hidutil</string>` inside the LaunchAgent plist and the prose explaining why it is the exception.
- `user_config_dir` is the only spelling of `~/.config` in shipped code (grepped: no `${XDG_CONFIG_HOME:-$HOME/.config}` outside the Global Constraints line that forbids it). The Lua files keep their own `os.getenv("XDG_CONFIG_HOME")` fallbacks, which is the same rule in a language that cannot call the shell function.

### Mechanical re-verification after the review pass

Re-run against the edited plan, not the original:

- All four `lua` blocks extracted and `luac -p` clean.
- All thirty `#!/usr/bin/env bash` blocks extracted; `shellcheck --severity=warning` silent on every one. The only blocks that fail `bash -n` are the six deliberate one-line fragments meant to be spliced into existing files (the `lib/all.sh` loop line, the `theme)` case arm, the `cmd_install` insert).
- `theme_palette_load` + `theme_render` run for real against the shipped Catppuccin palettes: `{{ accent_rgb }}` → `137,180,250`, `env.sh` renders `BAT_THEME="OneHalfDark"`, and a palette containing `accent = "#zzzzzz"` now renders instead of aborting under `set -e`.
- `theme_set nope` prints `Unknown theme: nope`, then `Falling back to the catppuccin theme`, exits 0 and leaves `theme.name` as `catppuccin`.
- `capabilities/theme/theme-apply` run against four fixtures: the top-of-file layout (Python's `tomllib` confirms `palette` parses at the **root** and both `[palettes.*]` tables are present, including `black`), a second identical run (`Already current: …`), the below-a-table layout (refuses, writes nothing), and a missing `starship.toml` (one log line, exit 0).

### Deliberately deferred to phases 3 to 5

- **Appearance changes do not re-run the hooks.** WezTerm follows light/dark on its own because both schemes are registered, and the shell picks its `env.sh` at shell start, but the starship palette line and any future jq-patched app settings only change on the next `teeup theme set`. An appearance-watching LaunchAgent belongs with the rest of the `update`/hooks work (phase 4).
- **The `theme-set` hook directory** (`~/.config/teeup/hooks/theme-set.d/`, spec section 7) is not wired. `theme_set` runs capability `theme-apply` scripts only. Hooks and their `.sample` files are a phase 4 unit, together with `post-bootstrap` and `post-update`.
- **`teeup doctor` and `teeup remove` verbs.** `capabilities/aerospace/doctor`, `capabilities/keyboard/remove` and `capabilities/macos-defaults/remove` are written to the contract and tested through `cap_run`, but `bin/teeup` gains the verbs in phase 4.
- **`teeup reset <cap>`** for the WezTerm and AeroSpace configs: `refresh_config` already exists in `lib/files.sh`; the verb is phase 4.
- **A capability's own `theme-apply` for starship.** Today the theme capability writes that file, for the plan-ownership reason given in Task 2. Moving it under `capabilities/starship/` is a no-op refactor whenever 2a's tree is free.
- **`theme-apply` marks its target as user-edited.** `copy_config_once` compares against the sha recorded when the file was installed, so after the first starship patch the file reports "Keeping your edited …". That is the safe direction (teeup never overwrites), but re-recording the stock sha after a managed-block write would be tidier; it needs a `files.sh` change and belongs with phase 4's migration work.
- **More themes.** Only `catppuccin` ships. Task 8 drives the wizard's options from `theme_list`, so the other three names are simply not offered any more, and `theme_set` falls back with a warning if one reaches it from a hand-edited answers file. `tokyo-night`, `gruvbox` and `nord` palettes are phase 4; adding one is two TOML files and nothing else.
- **Editor and app templates.** `themed/*.tpl` for Neovim, Zed, VS Code and btop, plus the jq-based `font_family`/`theme` writers those need, land with the daily tier in phase 3.
- **Karabiner** (hyper key) and **`teeup launch`** for GUI casks stay lazy, phase 3.
- **Theme backgrounds.** `themes/<name>/backgrounds/` from spec section 4 is not created; macOS desktop pictures are set through a scripting bridge that needs its own investigation.
