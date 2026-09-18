# Phase 4b: discoverability — doctor, menu, config, dev

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a bootstrapped Mac explain itself: `teeup doctor` says what is broken and the one command that fixes it, `teeup menu` puts every teeup action behind a keyboard-driven list, `teeup config` edits the profile without opening a file by hand, and `teeup dev` scaffolds and checks a new capability.

**Architecture:** Four verbs over three new libraries. `lib/doctor.sh` runs a generic metadata health check for every installed capability plus that capability's own optional `doctor` script, collecting findings into one report file whose summary names each failure and its fix. `lib/menu.sh` reads `share/teeup/menu.json` (a flat object of dotted ids, merged with the user's `~/.config/teeup/menu.json`) with a small awk parser, hides rows whose `when` predicate fails, and drives the choice through gum, fzf or a plain numbered list. `lib/dev.sh` scaffolds a capability and runs the metadata lint, shellcheck, the menu lint and the capability's test suite. `teeup config get|set|edit` is a thin layer over `lib/answers.sh` that always surfaces what `machines/<hostname>.conf` pins.

**Tech Stack:** bash 3.2, BSD userland, awk (no jq: macOS does not ship it and the test harness's narrowed PATH hides Homebrew's), gum and fzf when present, the existing `tests/helper.sh` mock harness.

**Spec:** `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md` — sections 4 (`doctor` in the capability directory, `share/teeup/menu.json`), 4a (the metadata contract this plan checks against), 4b (the home layout `doctor` verifies), 7 (the configuration model and its precedence), 12 (adding a tool later: `teeup dev new-capability`, the menu row, `teeup dev check`), the CLI surface block, and sections 1 and 2 for Omarchy's two models: predicates as exit codes, and a declarative menu with dotted ids.

---

## Depends on

Phases 1, 2a and 2b are merged; for them `main` is the ground truth. Phases 3a, 3b and 4a are planned but not merged, so their plan text is the contract. Every interface this plan consumes:

| Interface | Kind | Defined by |
|---|---|---|
| `log ok warn err die have run_cmd run_logged user_config_dir is_macos` | functions, `lib/core.sh` | main |
| `state_done check\|mark\|clear <name>` | function, `lib/state.sh` | main |
| `answers_file answers_exist answers_load answers_get answers_set machine_get machine_file` | functions, `lib/answers.sh` | main |
| `cap_dir cap_exists cap_list cap_meta_get cap_tier_list cap_order cap_skipped cap_run cap_run_optional cap_check` | functions, `lib/capability.sh` | main |
| `pkg_backend pkg_backend_label pkg_backend_installed pkg_installed package_candidates casks_supported cask_installed` | functions, `lib/pkg.sh` | main |
| `_ui_gum ui_input ui_confirm ui_choose` | functions, `lib/ui.sh` | main |
| `file_sha stock_sha copy_config_once write_managed_file replace_literal` | functions, `lib/files.sh` | main |
| `theme_current theme_list` | functions, `lib/theme.sh` | main |
| `setup_test_env cleanup_test_env mock_command mock_command_script mock_macos_base` and the assertions | test harness, `tests/helper.sh` | main |
| `capabilities/aerospace/doctor` | the one existing doctor script | main |
| `shims_dir cap_apps app_installed lazy_provider lazy_real_command` | functions, `lib/lazy.sh` | phase 3b, Task 1 |
| `hide_host_commands <name...>` | test helper, `tests/helper.sh` | phase 3b, Task 1 |
| `have` returns 1 for a command that resolves inside the shims directory | changed behaviour, `lib/core.sh` | phase 3b, Task 1 |
| `dev_env_installed` | function, `lib/mise.sh` | phase 3b, Task 4 |
| `teeup launch`, `teeup lazy-run`, `teeup install dev-env <lang>` | verbs, `bin/teeup` | phase 3b, Tasks 3 and 4 |
| capabilities `emacs zed firefox-developer-edition obsidian` (daily), `neovim vscode chrome` (lazy) | capability dirs | phase 3a |
| capabilities `colima ai herdr tmux ollama cursor` (lazy) | capability dirs | phase 3b, Tasks 5–10 |
| `cmd_dev` in `bin/teeup` with an `add-migration) migration_new ;;` arm and a `dev) cmd_dev "$@" ;;` dispatch arm | verb group, `bin/teeup` | phase 4a, Task 4 |
| `teeup update`, `teeup reset`, `teeup remove` | verbs, `bin/teeup` | phase 4a, Tasks 5, 6, 7 |
| `hook_run <event> [args]` | function, `lib/hooks.sh` | phase 4a, Task 2 |

### What was verified, and what is assumed

This plan was transcribed against **main + phase 3a + phase 3b** (the scratch tree at `plan3-ab-fix/tree`, HEAD = 3b Task 11, `All 46 suites passed.`). Phase 4a's plan text was final when this was written but its own transcription was still running, so 4a's tasks were **not** applied to the transcription base. Two consequences the executor must act on:

1. **Verb separation holds by construction.** 4a owns `update`, `reset`, `remove` and `dev add-migration`. This plan owns `doctor`, `menu`, `config`, `dev new-capability` and `dev check`. There is no overlap, and every `bin/teeup` anchor this plan edits (`teeup has` in `usage()`, `cmd_has() {`, `  has) cmd_has "$@" ;;`, and afterwards this plan's own `cmd_config`/`config)` lines) is one that phase 4a's plan does not touch. 4a anchors on the `teeup configure`/`teeup commands --check`/`teeup version` usage lines, on `cmd_commands() {` and on the `configure)`, `reset)`, `update)` and `commands)` dispatch arms. The two sets are disjoint, so 4a and 4b apply in either order.
2. **`cmd_dev` already exists.** Phase 4a Task 4 creates `cmd_dev` with a single `add-migration` arm and its `dev) cmd_dev "$@" ;;` dispatch arm; this plan owns the `dev` verb group and appends its two subcommands as new case arms in that one function. Task 8 Step 4 and Task 9 Step 4 are plain `edit-old`/`edit-new` pairs against 4a's function — they add no second definition and no second dispatch arm. Nothing else in this plan depends on 4a.

Three items phase 4a explicitly hands to 4b are taken here: the `gpg.ssh.allowedSignersFile` check (Task 4, the `ssh` doctor), the "shims directory is last on the live PATH" check (Task 2, the `teeup-runtime` doctor), and `teeup doctor` as the place the migration leftovers of spec section 10 will eventually be reported (the runner is built here; the leftover checks themselves are phase 5a's, per the brief). Routing `capabilities/mise/configure` through `write_config_region` is left, because `write_config_region` is a phase 4a primitive this plan's base does not have.

---

## Global Constraints

Every task's requirements implicitly include this section.

- **bash 3.2 compatible.** No `mapfile`, `readarray`, `declare -A`, `${var,,}`, `readlink -f`, `**`, `&>>`. Use `10#$n` for any arithmetic on a string that may have a leading zero. No same-line `local` back-reference (`local a=1 b=$a` leaves `b` empty). bash 3.2 mis-parses a quoted pattern containing `/` inside `${var//pat/repl}`: use `replace_literal` (`lib/files.sh`). Run `shopt -u patsub_replacement 2>/dev/null || true` before any `${var//}` replacement whose replacement text can contain `&`.
- **BSD tools only.** No GNU-only flags, no `\t` or `\n` in `sed` replacements, no `grep -P`. Pass awk values through `ENVIRON` rather than `-v` whenever they can contain a backslash (menu ids and field names cannot, and the tasks say so where `-v` is used).
- **Capability scripts** (`install`, `configure`, `doctor`, `remove`, …) start `#!/usr/bin/env bash`, are run by `cap_run` as `bash -eu` with `lib/all.sh` sourced and `answers_load` done, and must not use `local`. Mind `set -e` on a trailing `[[ ]] && cmd`. Mocked commands are called by bare name. Every mutation goes through `run_cmd`/`run_privileged` or a `DRY_RUN`-guarded primitive; `DRY_RUN=true` must change nothing. In `bin/teeup` and `lib/*.sh`, which also run under `set -eu`, use `if … then … fi` rather than a bare `[[ ]] && cmd` statement.
- **Paths.** `user_config_dir` for `~/.config`; `TEEUP_CONFIG_DIR` and `TEEUP_STATE_DIR` are honoured everywhere. Paths containing spaces and shell metacharacters must work, and every new suite includes at least one such path.
- **Machine file precedence.** `answers` then `machines/<hostname>.conf`; the machine file wins. Every consumer of an answer respects it, and `teeup config` surfaces it rather than writing over it.
- **Capability metadata contract:** `summary group tier requires provides packages casks apps interactive`. `provides` never names a command macOS ships. A `core` or `daily` capability must appear in its tier list or `teeup commands --check` fails; append to the list in the same commit that adds the capability.
- **Tests** use the `tests/helper.sh` harness: a temp `$HOME`, `MOCK_BIN` first on the narrowed PATH `$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin`, `mock_command`, `mock_command_script`, `mock_macos_base`, `hide_host_commands`, `TEEUP_TEST_MISSING`, `TEEUP_PKG_PREFIX`, `TEEUP_APPS_DIR`. The narrowed PATH hides Homebrew, so any host tool a test needs must be resolved before `setup_test_env` or mocked. CI runs macos-14, macos-15-intel and ubuntu-latest. A test that can only pass on a developer's machine is a defect.
- **Prompts and menus in tests.** `lib/ui.sh` uses gum whenever `TEEUP_NO_GUM` is empty and `gum` is on PATH, and the harness's narrowed PATH still exposes a host `/usr/bin/gum`. **Every test that drives a prompt or a menu must `export TEEUP_NO_GUM=1`**, exactly as `tests/bootstrap.sh` and `tests/capabilities/secrets.sh` do. No test may depend on `gum` or `fzf` being installed; the fzf branch is driven with a mocked `fzf` and an explicit `TEEUP_MENU_PICKER=fzf`.
- **Suite counts.** `tests/run.sh` ends with `All N suites passed.` Never hard-code N: write "the suite count printed before this task, plus K", so this plan stays right whichever of 3a, 3b, 4a and 4b lands first.
- **Nothing has run on a real Mac.** Each task carries a **Real-Mac risk** note naming what only hardware proves.
- **Verify, do not guess** every external CLI flag, config key, package name and file location against the installed tool's `--help` or current upstream documentation.
- **Every task ends** with: `./tests/run.sh` green, `./bin/teeup commands --check` silent and exit 0, `shellcheck --severity=warning` clean on every new or edited shell script and test, `git diff --check` clean, and ONE commit with a plain imperative subject and NO trailers (no `Co-Authored-By`, no `Claude-Session`, no "Generated with").

---

## Contracts

### The doctor contract

A capability may ship an executable `doctor` script beside its `install` and `configure`. It runs exactly as they do (`bash -eu`, `lib/all.sh` loaded, answers sourced, `TEEUP_CAP` and `TEEUP_CAP_DIR` exported) and reports through three functions from `lib/doctor.sh`:

- `doctor_ok <message>` — a check that passed.
- `doctor_warn <message>` — something worth saying that is not a failure (a manual step, a service that is simply not running).
- `doctor_fail <message> <fix-command>` — a failure. It prints the message and records `<capability>`, `<message>` and `<fix-command>` in the report the runner reads, then returns 0 so the script keeps checking.

A doctor script never decides the exit status: the runner does, from the report. A script that exits non-zero on its own is itself recorded as a failure. Scripts must not mutate anything, so `DRY_RUN` needs no special handling in them.

Before running a capability's own doctor, the runner performs `doctor_metadata_check`, derived entirely from the metadata: every `packages` entry is installed, every `casks` entry is installed (skipped with a note on MacPorts), every `apps` entry is in `/Applications`, and every `provides` command resolves to a real binary rather than only to a shim. That is the generic half the spec's CLI-surface note asks for, so most capabilities need no doctor script at all.

`teeup doctor` with no argument checks every installed, non-skipped capability. `teeup doctor <cap>` checks that one whether or not it is installed. Both exit 0 when nothing failed and 1 otherwise, and both end with a summary that names each failure and the command that fixes it.

### The menu file format

`share/teeup/menu.json` is one JSON object. Its keys are dotted ids, its values are objects, and every field value is a one-line string. Anything else is refused: arrays, numbers, booleans, nesting past that and comments all fail the parse, and inside a string the only escapes understood are `\"`, `\\` and `\/`. The parser is `lib/menu.awk`, about a hundred lines, and it exists so that reading the menu needs no jq — macOS ships none, and the test harness's narrowed PATH hides Homebrew's.

Fields:

| Field | Meaning |
|---|---|
| `label` | required; what the row shows |
| `icon` | optional; printed before the label, separated by one space |
| `action` | a shell command line; a row with one is a leaf, a row without one is a submenu |
| `when` | a shell condition; the row is hidden when it exits non-zero |
| `title` | header shown when this row's submenu is open; defaults to `label` |

Hierarchy comes from the ids alone: `install.editors.zed` is a child of `install.editors`, which is a child of `install`. Every id's parent must itself be declared, and no two siblings may share a label; `teeup dev check` enforces both.

`when` and `action` run through `bash -c` with `$TEEUP_PATH/bin` prepended to PATH, so `teeup has <cap>` — the exit-code predicate that has been in `bin/teeup` since phase 1 — is the natural condition, and `teeup install <cap>` the natural action. To hide a shipped row, give it `"when": "false"`.

`~/.config/teeup/menu.json` is read after the shipped file and merged by id: an id in both files takes the user's entry **whole** (fields are replaced, not merged) and keeps the shipped position; an id only in the user file is appended. That is the extension and override mechanism spec section 12 step 5 asks for.

### The picker

`menu_pick <prompt> <option...>` prints the chosen option and returns 0, or prints nothing and returns 1 when the user cancels. It chooses its front end with `menu_picker`:

| `TEEUP_MENU_PICKER` | Behaviour |
|---|---|
| unset or `auto` | `gum choose` when `_ui_gum` says gum is usable; else `fzf` when `TEEUP_NO_GUM` is empty and `fzf` is on PATH; else the plain numbered list |
| `gum` / `fzf` / `plain` | that one, unconditionally |
| anything else | `die` |

`TEEUP_NO_GUM` turns off **both** full-screen pickers, not just gum: gum and fzf each paint on `/dev/tty`, and the one switch tests use to get deterministic, pipe-driven prompts has to cover both. A test that wants the fzf branch sets `TEEUP_MENU_PICKER=fzf` and mocks `fzf`.

### `teeup config`

Over the answers file only. `get` prints the effective value — the answers file, then `machines/<hostname>.conf` on top, which is what `answers_load` already produces. `set` writes the answers file through `answers_set` and **warns when the machine file pins that key to something else**, because the write would then have no effect. `edit` opens `$VISUAL`/`$EDITOR` on the answers file, checks the result parses, and restores the backup when it does not.

---

## File structure

| File | Responsibility | Task |
|---|---|---|
| `lib/doctor.sh` | the three reporting functions, the generic metadata check, the runner and the summary | 1 |
| `lib/menu.awk` | the menu-file parser: one tab-separated `id`/`field`/`value` line per field | 5 |
| `lib/menu.sh` | parse, merge shipped with user, query the tree, evaluate `when`, pick a row | 5 |
| `lib/dev.sh` | `new-capability` scaffolding and the `dev check` lint | 8, 9 |
| `lib/all.sh` | sources the three new libraries | 1, 5, 8 |
| `share/teeup/menu.json` | the shipped menu | 6 |
| `share/teeup/skeleton/{capability,install,configure,test.sh}` | what `teeup dev new-capability` copies | 8 |
| `bin/teeup` | `cmd_doctor`, `cmd_menu`, `cmd_config`, two `cmd_dev` arms, usage and dispatch | 1, 6, 7, 8, 9 |
| `capabilities/aerospace/doctor` | ported onto the reporting functions | 1 |
| `capabilities/{package-manager,teeup-runtime,dev-dirs,zsh}/doctor` | the runtime and home spine | 2 |
| `capabilities/{git,ssh,github}/doctor` | identity | 3 |
| `capabilities/{mise,starship,theme}/doctor` | generated artifacts and tool config | 4 |
| `tests/lib/doctor.sh` | the library, the generic check and the summary | 1 |
| `tests/lib/menu.sh` | the parser, the merge, the tree queries and the picker | 5 |
| `tests/lib/dev.sh` | scaffolding and the lint | 8, 9 |
| `tests/cli.sh` | the four verbs end to end | 1, 6, 7, 8, 9 |
| `tests/capabilities/*.sh` | one doctor test per capability that gains a doctor script | 1, 2, 3, 4 |
| `.github/workflows/ci.yml` | shellcheck the skeleton scripts | 8 |
| `README.md`, `CONTRIBUTING.md` | the four verbs, the menu format, the doctor contract | 10 |

`tests/run.sh` needs no edit: it discovers `tests/lib/*.sh` and `tests/capabilities/*.sh` by glob. `tests/helper.sh` and `tests/bootstrap.sh` are not edited by this plan at all, which keeps it clear of phase 4d's edits to `tests/bootstrap.sh` and of its new `tests/lib/themes.sh`.

---

## Tasks

1. `lib/doctor.sh`, the `teeup doctor` verb and the generic metadata check
2. Doctor scripts for the runtime spine: `package-manager`, `teeup-runtime`, `dev-dirs`, `zsh`
3. Doctor scripts for identity: `git`, `ssh`, `github`
4. Doctor scripts for generated state: `mise`, `starship`, `theme`
5. `lib/menu.awk` and `lib/menu.sh`: parse, merge, query, pick
6. `share/teeup/menu.json` and the `teeup menu` verb
7. `teeup config get|set|edit`
8. `teeup dev new-capability <name>`
9. `teeup dev check`
10. README and contributor documentation

---
### Task 1: `lib/doctor.sh`, the `teeup doctor` verb and the generic metadata check

**Files:**
- Create: `lib/doctor.sh`
- Create: `tests/lib/doctor.sh`
- Modify: `lib/all.sh`
- Modify: `bin/teeup`
- Modify: `capabilities/aerospace/doctor`
- Modify: `tests/cli.sh`
- Modify: `tests/capabilities/aerospace.sh`

**Interfaces:**
- Consumes: `ok warn err die log have run_cmd` (`lib/core.sh`); `state_done check` (`lib/state.sh`); `cap_dir cap_exists cap_list cap_meta_get cap_skipped cap_run` (`lib/capability.sh`); `package_candidates pkg_installed casks_supported cask_installed pkg_backend_label` (`lib/pkg.sh`); `cap_apps app_installed` (`lib/lazy.sh`, phase 3b Task 1).
- Produces:
  - `doctor_ok <message>` — prints a passing check. Always 0.
  - `doctor_warn <message>` — prints a note that is not a failure. Always 0.
  - `doctor_fail <message> <fix-command>` — prints the message, records it against `$TEEUP_CAP`, counts it in this process. Always 0.
  - `doctor_verdict` — 0 when this process recorded no failure, 1 otherwise. The last line of every doctor script.
  - `doctor_record <capability> <message> <fix-command>` — appends one tab-separated record to `$TEEUP_DOCTOR_REPORT`; a no-op when that variable is empty. Always 0.
  - `doctor_metadata_check <capability>` — the generic check derived from `packages`, `casks`, `apps` and `provides`. Always 0.
  - `doctor_targets` — prints the installed, non-skipped capability names, one per line, in `cap_list` order. Always 0.
  - `doctor_run_one <capability>` — the metadata check plus the capability's own `doctor`. Always 0.
  - `doctor_summary <report-file>` — prints the verdict; 0 when the report is empty, 1 otherwise.
  - `TEEUP_DOCTOR_REPORT` — the report path, exported by `cmd_doctor` and inherited by every doctor script.
  - `cmd_doctor [<capability>]` in `bin/teeup`, reached as `teeup doctor`.

**Real-Mac risk:** `pkg_installed` shells out to `brew list --formula` once per declared package, so on a real Mac `teeup doctor` with no argument is a few seconds of Homebrew calls that the mocked suite finishes instantly; only a real machine shows whether that is tolerable or wants a `brew list` cache. Whether `brew list --formula <name>` and `brew list --cask <name>` answer correctly for every token the capabilities declare (taps, versioned formulae) is also only provable against a real Homebrew.

- [ ] **Step 1: Write the failing test**

Create `tests/lib/doctor.sh`:

```bash file=tests/lib/doctor.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# A capability tree of fixtures, so the metadata check is tested against
# metadata this file controls rather than against whatever teeup ships.
make_cap() {
  local name="$1" packages="${2:-}" casks="${3:-}" apps="${4:-}" provides="${5:-}"
  local dir="$TEEUP_CAPS_DIR/$name"
  mkdir -p "$dir"
  printf 'summary="Fixture %s"\ngroup=system\ntier=lazy\nrequires=""\nprovides="%s"\npackages="%s"\ncasks="%s"\napps="%s"\ninteractive=false\n' \
    "$name" "$provides" "$packages" "$casks" "$apps" > "$dir/capability"
  printf '#!/usr/bin/env bash\n:\n' > "$dir/install"
  printf '#!/usr/bin/env bash\n:\n' > "$dir/configure"
  chmod +x "$dir/install" "$dir/configure"
}

setup() {
  setup_test_env
  mock_macos_base
  # A config dir whose name carries a space and three characters that are
  # special to sed, awk and the shell, so every path this library builds is
  # exercised against one.
  export TEEUP_CONFIG_DIR="$TEST_HOME/con fig \$x & 'q'/teeup"
  export TEEUP_STATE_DIR="$TEST_HOME/sta te \$x & 'q'/teeup"
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  mkdir -p "$TEEUP_CAPS_DIR" "$TEEUP_APPS_DIR"
  source "$TEEUP_PATH/lib/all.sh"
  REPORT="$TEST_HOME/report"
  : > "$REPORT"
  export TEEUP_DOCTOR_REPORT="$REPORT"
}

test_fail_prints_and_records_against_the_current_capability() {
  setup
  local out
  out="$(TEEUP_CAP=widget doctor_fail "the widget is bent" "teeup configure widget" 2>&1)"
  assert_contains "$out" "the widget is bent" || return 1
  assert_equals "widget	the widget is bent	teeup configure widget" "$(cat "$REPORT")" || return 1
  cleanup_test_env
}

test_fail_flattens_tabs_and_newlines_so_one_failure_is_one_record() {
  setup
  TEEUP_CAP=widget doctor_fail "$(printf 'two\tparts\nand a line')" "$(printf 'teeup\tconfigure widget')" >/dev/null 2>&1
  assert_equals "1" "$(wc -l < "$REPORT" | tr -d ' ')" "one failure must be one line" || return 1
  assert_contains "$(cat "$REPORT")" "two parts and a line" || return 1
  cleanup_test_env
}

test_record_without_a_report_is_a_no_op() {
  setup
  export TEEUP_DOCTOR_REPORT=""
  doctor_record widget "nothing collects this" "teeup help" || return 1
  assert_equals "" "$(cat "$REPORT")" || return 1
  cleanup_test_env
}

test_verdict_is_zero_until_something_fails() {
  setup
  doctor_verdict || { echo "a fresh process has no failures"; return 1; }
  TEEUP_CAP=widget doctor_fail "bent" "teeup configure widget" >/dev/null 2>&1
  doctor_verdict && { echo "verdict must fail after doctor_fail"; return 1; }
  cleanup_test_env
}

test_metadata_check_reports_a_missing_package_with_its_fix() {
  setup
  make_cap widget "ripgrep"
  hide_host_commands brew
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "package ripgrep is not installed" || return 1
  assert_contains "$(cat "$REPORT")" "teeup install widget" || return 1
  cleanup_test_env
}

test_metadata_check_passes_when_the_package_manager_lists_it() {
  setup
  make_cap widget "ripgrep"
  mock_command_script brew <<'EOF2'
case "$1 ${2:-} ${3:-}" in
  "list --formula ripgrep") exit 0 ;;
  *) exit 1 ;;
esac
EOF2
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "package ripgrep is installed" || return 1
  assert_equals "" "$(cat "$REPORT")" || return 1
  cleanup_test_env
}

test_metadata_check_reports_a_missing_app() {
  setup
  make_cap widget "" "" "Widget Studio"
  mock_command brew 1 ""
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "Widget Studio.app is not installed" || return 1
  assert_contains "$(cat "$REPORT")" "teeup install widget" || return 1
  mkdir -p "$TEEUP_APPS_DIR/Widget Studio.app"
  : > "$REPORT"
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "Widget Studio.app is installed" || return 1
  assert_equals "" "$(cat "$REPORT")" || return 1
  cleanup_test_env
}

test_metadata_check_skips_casks_on_macports() {
  setup
  make_cap widget "" "widget-app"
  export TEEUP_PACKAGE_MANAGER=macports
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "casks are not available with MacPorts" || return 1
  assert_equals "" "$(cat "$REPORT")" "a MacPorts machine must not be told to install a cask" || return 1
  cleanup_test_env
}

test_metadata_check_rejects_a_command_that_is_only_a_shim() {
  setup
  make_cap widget "" "" "" "frob"
  mock_command brew 1 ""
  mkdir -p "$(shims_dir)"
  printf '#!/usr/bin/env bash\n:\n' > "$(shims_dir)/frob"
  chmod +x "$(shims_dir)/frob"
  PATH="$PATH:$(shims_dir)"
  export PATH
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "frob is not on PATH" || return 1
  assert_contains "$(cat "$REPORT")" "teeup install widget" || return 1
  cleanup_test_env
}

test_targets_are_the_installed_capabilities_in_order() {
  setup
  make_cap alpha
  make_cap beta
  make_cap gamma
  state_done mark cap-gamma
  state_done mark cap-alpha
  assert_equals "alpha
gamma" "$(doctor_targets)" || return 1
  assert_equals "gamma" "$(TEEUP_SKIP=alpha doctor_targets)" || return 1
  cleanup_test_env
}

test_summary_is_quiet_and_zero_when_the_report_is_empty() {
  setup
  local out rc=0
  out="$(doctor_summary "$REPORT" 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "everything checked is healthy" || return 1
  cleanup_test_env
}

test_summary_names_every_failure_and_its_fix() {
  setup
  printf 'git\tno signing key\tteeup configure git\n' >> "$REPORT"
  printf 'zsh\tnot the login shell\tchsh -s /bin/zsh\n' >> "$REPORT"
  local out rc=0
  out="$(doctor_summary "$REPORT" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "found 2 problem" || return 1
  assert_contains "$out" "git: no signing key" || return 1
  assert_contains "$out" "fix: teeup configure git" || return 1
  assert_contains "$out" "fix: chsh -s /bin/zsh" || return 1
  cleanup_test_env
}

test_run_one_records_a_doctor_that_exits_without_saying_why() {
  setup
  make_cap widget
  printf '#!/usr/bin/env bash\nexit 3\n' > "$TEEUP_CAPS_DIR/widget/doctor"
  mock_command brew 1 ""
  doctor_run_one widget >/dev/null 2>&1
  assert_contains "$(cat "$REPORT")" "exited non-zero without saying why" || return 1
  cleanup_test_env
}

test_run_one_does_not_double_count_a_doctor_that_explained_itself() {
  setup
  make_cap widget
  printf '#!/usr/bin/env bash\ndoctor_fail "the widget is bent" "teeup configure widget"\ndoctor_verdict\n' > "$TEEUP_CAPS_DIR/widget/doctor"
  mock_command brew 1 ""
  doctor_run_one widget >/dev/null 2>&1
  assert_equals "1" "$(wc -l < "$REPORT" | tr -d ' ')" || return 1
  assert_contains "$(cat "$REPORT")" "the widget is bent" || return 1
  cleanup_test_env
}

echo "lib/doctor.sh"
run_test "fail prints and records against the current capability" test_fail_prints_and_records_against_the_current_capability
run_test "fail flattens tabs and newlines" test_fail_flattens_tabs_and_newlines_so_one_failure_is_one_record
run_test "record without a report is a no-op" test_record_without_a_report_is_a_no_op
run_test "verdict is zero until something fails" test_verdict_is_zero_until_something_fails
run_test "metadata check reports a missing package" test_metadata_check_reports_a_missing_package_with_its_fix
run_test "metadata check passes when listed" test_metadata_check_passes_when_the_package_manager_lists_it
run_test "metadata check reports a missing app" test_metadata_check_reports_a_missing_app
run_test "metadata check skips casks on macports" test_metadata_check_skips_casks_on_macports
run_test "metadata check rejects a shim-only command" test_metadata_check_rejects_a_command_that_is_only_a_shim
run_test "targets are the installed capabilities" test_targets_are_the_installed_capabilities_in_order
run_test "summary is quiet on an empty report" test_summary_is_quiet_and_zero_when_the_report_is_empty
run_test "summary names every failure and its fix" test_summary_names_every_failure_and_its_fix
run_test "run one records a silent non-zero doctor" test_run_one_records_a_doctor_that_exits_without_saying_why
run_test "run one does not double count" test_run_one_does_not_double_count_a_doctor_that_explained_itself
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/lib/doctor.sh`
Expected: every test fails, because `lib/all.sh` defines none of `doctor_fail`, `doctor_record`, `doctor_verdict`, `doctor_metadata_check`, `doctor_targets`, `doctor_run_one` or `doctor_summary`. The suite ends with `Summary: 0/14 passed`.

- [ ] **Step 3: Write `lib/doctor.sh`**

```bash file=lib/doctor.sh
#!/usr/bin/env bash
# doctor.sh - the health check. Two halves: a generic check every capability
# gets for free from its own metadata, and the optional `doctor` script a
# capability ships for the invariants metadata cannot express. Both report
# into one file, so the summary can name every failure and the single command
# that fixes it (spec section 4: "doctor - optional; exit 0 healthy, prints
# findings", and the Verification gate "teeup doctor must exit 0 afterward").
# Requires core.sh, state.sh, capability.sh, pkg.sh, lazy.sh.

# The runner exports this. Empty means nobody is collecting, which is what a
# doctor script run straight through `cap_run` gets: it still prints, it just
# records nothing.
TEEUP_DOCTOR_REPORT="${TEEUP_DOCTOR_REPORT:-}"
export TEEUP_DOCTOR_REPORT

# Failures recorded by *this* process. A doctor script runs as its own
# `bash -eu`, so this counts that script's own findings and nothing else,
# which is exactly what doctor_verdict needs.
TEEUP_DOCTOR_FAILURES=0

doctor_ok() { ok "$*"; }
doctor_warn() { warn "$*"; }

# doctor_record <capability> <message> <fix-command>
# One tab-separated record per failure. A tab or a newline inside either
# field would split the record, so both are flattened to spaces rather than
# rejected: a check must never itself fail because a path it is reporting on
# has an odd character in it.
doctor_record() {
  local cap="$1" message="$2" fix="$3"
  if [[ -z "$TEEUP_DOCTOR_REPORT" ]]; then
    return 0
  fi
  printf '%s\t%s\t%s\n' \
    "$(printf '%s' "$cap" | tr '\t\n' '  ')" \
    "$(printf '%s' "$message" | tr '\t\n' '  ')" \
    "$(printf '%s' "$fix" | tr '\t\n' '  ')" >> "$TEEUP_DOCTOR_REPORT"
  return 0
}

# _doctor_report_failure <capability> <message> <fix-command>
# Print and record, for a caller that knows which capability it is speaking
# for. The runner uses it directly; a doctor script goes through doctor_fail.
_doctor_report_failure() {
  err "$2"
  doctor_record "$1" "$2" "$3"
  TEEUP_DOCTOR_FAILURES=$((TEEUP_DOCTOR_FAILURES + 1))
  return 0
}

# doctor_fail <message> <fix-command>
# What a capability's doctor script calls. It returns 0 on purpose: the
# script runs under `bash -eu` and must keep checking everything else, and
# the exit status is decided once, at the end, by doctor_verdict.
doctor_fail() {
  _doctor_report_failure "${TEEUP_CAP:-teeup}" "$1" "$2"
}

# The last line of every doctor script. Exit 0 healthy, as the spec requires,
# so `bash capabilities/<cap>/doctor` is still meaningful on its own.
doctor_verdict() { [[ "$TEEUP_DOCTOR_FAILURES" -eq 0 ]]; }

_doctor_report_lines() {
  if [[ -n "$TEEUP_DOCTOR_REPORT" && -f "$TEEUP_DOCTOR_REPORT" ]]; then
    wc -l < "$TEEUP_DOCTOR_REPORT" | tr -d ' '
  else
    printf '0\n'
  fi
}

# doctor_metadata_check <capability>
# Everything the metadata already declares can be checked without a script,
# which is why most capabilities need no doctor of their own: packages and
# casks are installed, apps are in /Applications, and every command in
# provides= resolves to a real binary. `have` returns 1 for a command that
# resolves only inside the shims directory (phase 3b), so a lazy capability
# marked installed whose shim never got replaced is a finding rather than a
# pass. Always returns 0; the report carries the verdict.
doctor_metadata_check() {
  local cap="$1" item candidate found app
  for item in $(cap_meta_get "$cap" packages); do
    found=false
    for candidate in $(package_candidates "$item"); do
      if pkg_installed "$candidate"; then
        found=true
        break
      fi
    done
    if [[ "$found" == "true" ]]; then
      doctor_ok "package $item is installed."
    else
      _doctor_report_failure "$cap" "package $item is not installed." "teeup install $cap"
    fi
  done
  for item in $(cap_meta_get "$cap" casks); do
    if ! casks_supported; then
      doctor_warn "casks are not available with $(pkg_backend_label); install $item by hand."
      continue
    fi
    if cask_installed "$item"; then
      doctor_ok "cask $item is installed."
    else
      _doctor_report_failure "$cap" "cask $item is not installed." "teeup install $cap"
    fi
  done
  # App names can contain spaces, so they arrive one per line, never as words.
  while IFS= read -r app; do
    if [[ -z "$app" ]]; then
      continue
    fi
    if app_installed "$app"; then
      doctor_ok "$app.app is installed."
    else
      _doctor_report_failure "$cap" "$app.app is not installed." "teeup install $cap"
    fi
  done <<EOF_APPS
$(cap_apps "$cap")
EOF_APPS
  for item in $(cap_meta_get "$cap" provides); do
    if have "$item"; then
      doctor_ok "$item is on PATH."
    else
      _doctor_report_failure "$cap" "$item is not on PATH (a lazy shim does not count)." "teeup install $cap"
    fi
  done
  return 0
}

# doctor_targets -> what `teeup doctor` with no argument checks: the
# capabilities this machine has installed and does not skip, in cap_list
# order. A capability that was never installed has nothing to be wrong with.
doctor_targets() {
  local name
  for name in $(cap_list); do
    if state_done check "cap-$name" && ! cap_skipped "$name"; then
      printf '%s\n' "$name"
    fi
  done
  return 0
}

# doctor_run_one <capability>
# Always returns 0: one capability that cannot be checked must not stop the
# rest, and the report, not this function, carries the verdict. A doctor
# script that exits non-zero having already said why is not counted twice.
doctor_run_one() {
  local cap="$1" script before
  log "== $cap: $(cap_meta_get "$cap" summary) =="
  if cap_skipped "$cap"; then
    doctor_warn "$cap is skipped on this machine (TEEUP_SKIP); checking it anyway."
  fi
  doctor_metadata_check "$cap"
  script="$(cap_dir "$cap")/doctor"
  if [[ -f "$script" ]]; then
    before="$(_doctor_report_lines)"
    if ! cap_run "$cap" doctor; then
      if [[ "$(_doctor_report_lines)" -eq "$before" ]]; then
        _doctor_report_failure "$cap" "its doctor script exited non-zero without saying why." "teeup configure $cap"
      fi
    fi
  fi
  return 0
}

# doctor_summary <report-file>
# 0 when the report is empty, which is the spec's "teeup doctor must exit 0"
# gate. Otherwise one block per failure: what is wrong, and the one command
# that fixes it.
doctor_summary() {
  local report="$1" count cap message fix
  count=0
  if [[ -f "$report" ]]; then
    count="$(wc -l < "$report" | tr -d ' ')"
  fi
  echo ""
  if [[ "${count:-0}" -eq 0 ]]; then
    ok "teeup doctor: everything checked is healthy."
    return 0
  fi
  err "teeup doctor found $count problem(s):"
  while IFS=$'\t' read -r cap message fix || [[ -n "$cap" ]]; do
    if [[ -z "$cap" ]]; then
      continue
    fi
    printf '  %s: %s\n' "$cap" "$message" >&2
    printf '      fix: %s\n' "$fix" >&2
  done < "$report"
  return 1
}
```

- [ ] **Step 4: Source the new library**

```bash edit-old=lib/all.sh
for _teeup_lib in files state answers pkg ui capability macos theme font lazy mise hooks migrations; do
```
```bash edit-new=lib/all.sh
for _teeup_lib in files state answers pkg ui capability macos theme font lazy mise hooks migrations doctor; do
```

The anchor carries phase 4a's `hooks migrations`, which is on that line by the time this plan runs. If a checkout's list differs (an earlier phase landing in another order), make the same change: append ` doctor` to the end of whatever list is there, leaving the rest untouched. The libraries define functions and run nothing at source time, so their order among themselves does not matter.

- [ ] **Step 5: Run the library suite**

Run: `bash tests/lib/doctor.sh`
Expected: `Summary: 14/14 passed`.

- [ ] **Step 6: Write the failing CLI test**

Append these four tests to `tests/cli.sh`, immediately above the `echo "bin/teeup"` line:

```bash edit-old=tests/cli.sh
echo "bin/teeup"
```
```bash edit-new=tests/cli.sh
test_doctor_is_quiet_and_zero_when_nothing_is_installed_is_wrong() {
  setup
  "$TEEUP" install alpha >/dev/null
  local out rc=0
  out="$("$TEEUP" doctor 2>&1)" || rc=$?
  assert_success "$rc" "a healthy machine must exit 0" || return 1
  assert_contains "$out" "everything checked is healthy" || return 1
  assert_not_contains "$out" "== beta:" "an uninstalled capability is not checked" || return 1
  cleanup_test_env
}

test_doctor_names_the_failure_and_the_command_that_fixes_it() {
  setup
  "$TEEUP" install alpha >/dev/null
  printf '#!/usr/bin/env bash\ndoctor_fail "alpha has no widget" "teeup configure alpha"\ndoctor_verdict\n' > "$TEEUP_CAPS_DIR/alpha/doctor"
  local out rc=0
  out="$("$TEEUP" doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "alpha has no widget" || return 1
  assert_contains "$out" "fix: teeup configure alpha" || return 1
  cleanup_test_env
}

test_doctor_checks_one_capability_even_when_it_is_not_installed() {
  setup
  printf '#!/usr/bin/env bash\ndoctor_ok "beta looks fine"\ndoctor_verdict\n' > "$TEEUP_CAPS_DIR/beta/doctor"
  local out rc=0
  out="$("$TEEUP" doctor beta 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "beta looks fine" || return 1
  cleanup_test_env
}

test_doctor_rejects_an_unknown_capability() {
  setup
  local out rc=0
  out="$("$TEEUP" doctor nope 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Unknown capability: nope" || return 1
  cleanup_test_env
}

echo "bin/teeup"
```

And their `run_test` lines, immediately above `print_summary`:

```bash edit-old=tests/cli.sh
print_summary
```
```bash edit-new=tests/cli.sh
run_test "doctor is quiet and zero when healthy" test_doctor_is_quiet_and_zero_when_nothing_is_installed_is_wrong
run_test "doctor names the failure and its fix" test_doctor_names_the_failure_and_the_command_that_fixes_it
run_test "doctor checks an uninstalled capability" test_doctor_checks_one_capability_even_when_it_is_not_installed
run_test "doctor rejects an unknown capability" test_doctor_rejects_an_unknown_capability
print_summary
```

- [ ] **Step 7: Run it to see it fail**

Run: `bash tests/cli.sh`
Expected: the four new tests fail with `Unknown verb: doctor`; the suite ends with `Summary: 28/32 passed`.

- [ ] **Step 8: Add the verb to `bin/teeup`**

The usage line, above the `teeup has` line:

```bash edit-old=bin/teeup
  teeup has <capability>         exit 0 when installed (for scripts and menus)
```
```bash edit-new=bin/teeup
  teeup doctor [<capability>]    check what is installed, and say how to fix what is not
  teeup has <capability>         exit 0 when installed (for scripts and menus)
```

The function, above `cmd_has`:

```bash edit-old=bin/teeup
cmd_has() {
```
```bash edit-new=bin/teeup
# teeup doctor [<capability>]
# Exit 0 when healthy: the spec's release gate is "a real bootstrap on a
# clean macOS VM, then teeup doctor must exit 0". With no argument it checks
# what this machine has installed; with one it checks that capability whether
# or not it is installed, because "why is this not working" gets asked about
# things that did not install properly in the first place.
cmd_doctor() {
  local target="${1:-}" report targets name rc=0
  report="$(mktemp)"
  TEEUP_DOCTOR_REPORT="$report"
  export TEEUP_DOCTOR_REPORT
  if [[ -n "$target" ]]; then
    if ! cap_exists "$target"; then
      rm -f "$report"
      die "Unknown capability: $target"
    fi
    doctor_run_one "$target"
  else
    targets="$(doctor_targets)"
    if [[ -z "$targets" ]]; then
      warn "No capability is marked installed here. Run ./bootstrap, or name one: teeup doctor <capability>"
    fi
    for name in $targets; do
      doctor_run_one "$name"
    done
  fi
  doctor_summary "$report" || rc=$?
  rm -f "$report"
  return $rc
}

cmd_has() {
```

The dispatch arm, above `has)`:

```bash edit-old=bin/teeup
  has) cmd_has "$@" ;;
```
```bash edit-new=bin/teeup
  doctor) cmd_doctor "$@" ;;
  has) cmd_has "$@" ;;
```

- [ ] **Step 9: Run the CLI suite**

Run: `bash tests/cli.sh`
Expected: `Summary: 32/32 passed`.

- [ ] **Step 10: Port the AeroSpace doctor onto the reporting functions**

This is the one doctor script that already exists. Its findings keep their wording, so the three tests that assert on them stay green; what changes is that each failure now carries the command that fixes it, and the exit status comes from `doctor_verdict` instead of a hand-rolled counter.

```bash file=capabilities/aerospace/doctor
#!/usr/bin/env bash
# Accessibility grants live in the TCC database, which no unprivileged process
# may read. So doctor checks everything else and prints the one manual step.
# TEEUP_APPS_DIR is a test hook: without it this script reads the real
# /Applications and passes or fails depending on the developer's own machine.
APPS_DIR="${TEEUP_APPS_DIR:-/Applications}"

if [[ -d "$APPS_DIR/AeroSpace.app" ]]; then
  doctor_ok "AeroSpace is installed."
else
  doctor_fail "AeroSpace is not in /Applications." "teeup install aerospace"
fi

# AeroSpace reads either file, and reports both at once as ambiguous.
HOME_AERO="$HOME/.aerospace.toml"
XDG_AERO="$(user_config_dir)/aerospace/aerospace.toml"
if [[ -f "$HOME_AERO" && -f "$XDG_AERO" ]]; then
  doctor_fail "Two AeroSpace configs, $HOME_AERO and $XDG_AERO; AeroSpace reports that as ambiguous." "mv $HOME_AERO $HOME_AERO.disabled"
elif [[ -f "$HOME_AERO" ]]; then
  doctor_ok "AeroSpace config present: $HOME_AERO"
elif [[ -f "$XDG_AERO" ]]; then
  doctor_ok "AeroSpace config present: $XDG_AERO"
else
  doctor_fail "No aerospace.toml." "teeup configure aerospace"
fi

if pgrep -x AeroSpace >/dev/null 2>&1; then
  doctor_ok "AeroSpace is running."
else
  doctor_warn "AeroSpace is not running. Start it with: open -a AeroSpace"
fi

doctor_warn "If windows still do not move, turn AeroSpace on under System Settings > Privacy & Security > Accessibility."
doctor_verdict
```

- [ ] **Step 11: Assert the AeroSpace doctor now carries its fixes**

Add one test to `tests/capabilities/aerospace.sh`, above its `echo "capabilities/aerospace"` line:

```bash edit-old=tests/capabilities/aerospace.sh
echo "capabilities/aerospace"
```
```bash edit-new=tests/capabilities/aerospace.sh
test_doctor_records_the_fix_for_each_finding() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command pgrep 1 ""
  local report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  DRY_RUN=false cap_run aerospace doctor >/dev/null 2>&1 || true
  assert_contains "$(cat "$report")" "teeup install aerospace" || return 1
  assert_contains "$(cat "$report")" "teeup configure aerospace" || return 1
  assert_equals "2" "$(wc -l < "$report" | tr -d ' ')" "the running check is a warning, not a failure" || return 1
  cleanup_test_env
}

echo "capabilities/aerospace"
```

```bash edit-old=tests/capabilities/aerospace.sh
run_test "doctor reports the missing app and config" test_doctor_reports_the_missing_app_and_config
```
```bash edit-new=tests/capabilities/aerospace.sh
run_test "doctor reports the missing app and config" test_doctor_reports_the_missing_app_and_config
run_test "doctor records the fix for each finding" test_doctor_records_the_fix_for_each_finding
```

- [ ] **Step 12: Run the three suites**

Run: `bash tests/lib/doctor.sh && bash tests/cli.sh && bash tests/capabilities/aerospace.sh`
Expected: `Summary: 14/14 passed`, `Summary: 32/32 passed`, `Summary: 11/11 passed`.

- [ ] **Step 13: Run every check**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning bin/teeup lib/doctor.sh capabilities/aerospace/doctor tests/lib/doctor.sh tests/cli.sh tests/capabilities/aerospace.sh && git diff --check`
Expected: `All N suites passed.` where N is the count printed before this task plus 1 (`tests/lib/doctor.sh`); `commands --check` silent and exit 0; shellcheck silent; `git diff --check` silent.

- [ ] **Step 14: Commit**

```bash
git add lib/doctor.sh lib/all.sh bin/teeup capabilities/aerospace/doctor tests/lib/doctor.sh tests/cli.sh tests/capabilities/aerospace.sh
git commit -m "Add teeup doctor and the capability health-check contract"
```

---
### Task 2: Doctor scripts for the runtime spine

The four capabilities whose breakage makes everything else look broken: the package manager nothing installs without, the runtime that tells shells where the checkout is, the two project roots git keys identity off, and the shell layer that puts it all on PATH. None of them declares `packages`, `casks` or `apps` that the generic metadata check could cover, so each needs a script.

**Files:**
- Create: `capabilities/package-manager/doctor`, `capabilities/teeup-runtime/doctor`, `capabilities/dev-dirs/doctor`, `capabilities/zsh/doctor`
- Modify: `tests/capabilities/package-manager.sh`, `tests/capabilities/teeup-runtime.sh`, `tests/capabilities/dev-dirs.sh`, `tests/capabilities/zsh.sh`

**Interfaces:**
- Consumes: `doctor_ok doctor_warn doctor_fail doctor_verdict` (Task 1); `pkg_backend_installed pkg_backend_label pkg_prefix` (`lib/pkg.sh`); `answers_get machine_get machine_file` (`lib/answers.sh`); `user_config_dir` (`lib/core.sh`); `shims_dir` (`lib/lazy.sh`, phase 3b Task 1).
- Produces: four executable `doctor` scripts. They add no function and no variable; the only contract they extend is the report the Task 1 runner reads.

**Real-Mac risk:** the login-shell probe is `dscl . -read /Users/<user> UserShell`, which only a real directory service answers; the mocked suite proves the parsing, not that macOS returns `UserShell: /bin/zsh` in that exact shape. Whether `$HOME/.local/bin` and the shims directory really end up on a login shell's PATH in the order the shell layer intends is likewise only provable in a real terminal after a real bootstrap.

- [ ] **Step 1: Write the failing tests for `package-manager`**

```bash edit-old=tests/capabilities/package-manager.sh
echo "capabilities/package-manager"
```
```bash edit-new=tests/capabilities/package-manager.sh
test_doctor_passes_on_a_healthy_machine() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mkdir -p "$TEEUP_PKG_PREFIX/bin"
  export PATH="$TEEUP_PKG_PREFIX/bin:$PATH"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEEUP_PKG_PREFIX/bin/brew"
  chmod +x "$TEEUP_PKG_PREFIX/bin/brew"
  DRY_RUN=false "$TEEUP" configure package-manager >/dev/null
  local rc=0 out
  out="$(DRY_RUN=false cap_run package-manager doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "Homebrew is installed" || return 1
  assert_contains "$out" "recorded in the answers file: homebrew" || return 1
  cleanup_test_env
}

test_doctor_reports_a_backend_that_is_not_on_path() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  hide_host_commands brew
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run package-manager doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Homebrew is not installed" || return 1
  assert_contains "$out" "is not on PATH" || return 1
  assert_contains "$(cat "$report")" "./bootstrap" || return 1
  cleanup_test_env
}

test_doctor_says_when_the_machine_file_pins_another_backend() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR"
  printf 'TEEUP_PACKAGE_MANAGER="macports"\n' > "$TEEUP_MACHINES_DIR/testmac.conf"
  answers_set TEEUP_PACKAGE_MANAGER homebrew
  local out
  out="$(DRY_RUN=false cap_run package-manager doctor 2>&1)" || true
  assert_contains "$out" "pins TEEUP_PACKAGE_MANAGER=macports" || return 1
  cleanup_test_env
}

echo "capabilities/package-manager"
```

```bash edit-old=tests/capabilities/package-manager.sh
run_test "configure keeps existing answer" test_configure_keeps_existing_answer
```
```bash edit-new=tests/capabilities/package-manager.sh
run_test "configure keeps existing answer" test_configure_keeps_existing_answer
run_test "doctor passes on a healthy machine" test_doctor_passes_on_a_healthy_machine
run_test "doctor reports a backend not on PATH" test_doctor_reports_a_backend_that_is_not_on_path
run_test "doctor says when the machine file pins another backend" test_doctor_says_when_the_machine_file_pins_another_backend
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/capabilities/package-manager.sh`
Expected: the three new tests fail with `package-manager has no doctor script`; the suite ends with `Summary: 4/7 passed`.

- [ ] **Step 3: Write `capabilities/package-manager/doctor`**

```bash file=capabilities/package-manager/doctor
#!/usr/bin/env bash
# The backend itself, not the packages: the generic metadata check covers
# what each capability declares, and this capability declares nothing. What
# it owns is whether the package manager exists, is reachable, and is the one
# everything else has been assuming.
if pkg_backend_installed; then
  doctor_ok "$(pkg_backend_label) is installed under $(pkg_prefix)."
else
  doctor_fail "$(pkg_backend_label) is not installed." "./bootstrap"
fi

# A backend that is installed but whose bin directory is missing from PATH is
# the quieter half of the same failure: every command installed through it is
# invisible, and each one looks like its own capability's problem.
case ":$PATH:" in
  *":$(pkg_prefix)/bin:"*)
    doctor_ok "$(pkg_prefix)/bin is on PATH."
    ;;
  *)
    doctor_fail "$(pkg_prefix)/bin is not on PATH, so nothing installed through $(pkg_backend_label) can be found." "teeup configure zsh"
    ;;
esac

# configure records the resolved backend so that a macOS upgrade past the
# MacPorts cut-off cannot silently move the machine to Homebrew. The answers
# file is read on its own here, not through answers_get: answers_load has
# already layered the machine file on top, and the question this check asks
# is whether `teeup configure package-manager` ever wrote the answer down.
answers_recorded="$( (
  unset TEEUP_PACKAGE_MANAGER
  answers_f="$(answers_file)"
  # shellcheck source=/dev/null
  if [ -f "$answers_f" ]; then . "$answers_f"; fi
  printf '%s\n' "${TEEUP_PACKAGE_MANAGER:-}"
) )"
if [[ -n "$answers_recorded" ]]; then
  doctor_ok "The package manager is recorded in the answers file: $answers_recorded"
else
  doctor_fail "No TEEUP_PACKAGE_MANAGER in the answers file; the backend is detected afresh on every run." "teeup configure package-manager"
fi

# The machine file wins over the answers file by design, so this is not a
# failure. It is the thing to know before wondering why an answer, or a
# `teeup config set`, had no effect.
if pinned="$(machine_get TEEUP_PACKAGE_MANAGER)"; then
  doctor_warn "$(machine_file) pins TEEUP_PACKAGE_MANAGER=${pinned:-detect}, which wins over the answers file (currently ${answers_recorded:-unset})."
fi

doctor_verdict
```

Run: `chmod +x capabilities/package-manager/doctor`

- [ ] **Step 4: Run the package-manager suite**

Run: `bash tests/capabilities/package-manager.sh`
Expected: `Summary: 7/7 passed`.

- [ ] **Step 5: Write the failing tests for `teeup-runtime`**

```bash edit-old=tests/capabilities/teeup-runtime.sh
echo "capabilities/teeup-runtime"
```
```bash edit-new=tests/capabilities/teeup-runtime.sh
# A PATH shaped the way the shell layer shapes it: the package prefix and
# ~/.local/bin in front, the lazy shims directory last.
healthy_path() {
  export PATH="$TEEUP_PKG_PREFIX/bin:$TEST_HOME/.local/bin:$PATH:$TEST_HOME/.local/state/teeup/shims"
}

test_doctor_passes_after_configure() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  healthy_path
  local rc=0 out
  out="$(DRY_RUN=false cap_run teeup-runtime doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "points at this checkout" || return 1
  assert_contains "$out" "The lazy shims directory is last on PATH." || return 1
  cleanup_test_env
}

test_doctor_reports_a_missing_env_file_link_and_state() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run teeup-runtime doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "shells and LaunchAgents cannot find the checkout" || return 1
  assert_contains "$out" "so the teeup command is not on PATH" || return 1
  assert_contains "$out" "Missing under" || return 1
  assert_contains "$(cat "$report")" "teeup configure teeup-runtime" || return 1
  cleanup_test_env
}

test_doctor_fails_when_the_shims_directory_is_off_path() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  export PATH="$TEEUP_PKG_PREFIX/bin:$TEST_HOME/.local/bin:$PATH"
  local rc=0 out
  out="$(DRY_RUN=false cap_run teeup-runtime doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "is not on PATH, so no lazy shim can fire" || return 1
  cleanup_test_env
}

test_doctor_warns_when_the_shims_directory_is_not_last() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  export PATH="$TEEUP_PKG_PREFIX/bin:$TEST_HOME/.local/bin:$TEST_HOME/.local/state/teeup/shims:$PATH"
  local rc=0 out
  out="$(DRY_RUN=false cap_run teeup-runtime doctor 2>&1)" || rc=$?
  assert_success "$rc" "being out of order is a warning, not a failure" || return 1
  assert_contains "$out" "on PATH but not last" || return 1
  cleanup_test_env
}

echo "capabilities/teeup-runtime"
```

```bash edit-old=tests/capabilities/teeup-runtime.sh
run_test "configure dry run writes no shims" test_configure_dry_run_writes_no_shims
```
```bash edit-new=tests/capabilities/teeup-runtime.sh
run_test "configure dry run writes no shims" test_configure_dry_run_writes_no_shims
run_test "doctor passes after configure" test_doctor_passes_after_configure
run_test "doctor reports a missing env file, link and state" test_doctor_reports_a_missing_env_file_link_and_state
run_test "doctor fails when the shims dir is off PATH" test_doctor_fails_when_the_shims_directory_is_off_path
run_test "doctor warns when the shims dir is not last" test_doctor_warns_when_the_shims_directory_is_not_last
```

- [ ] **Step 6: Run it to see it fail**

Run: `bash tests/capabilities/teeup-runtime.sh`
Expected: the four new tests fail with `teeup-runtime has no doctor script`; the suite ends with `Summary: 9/13 passed`.

- [ ] **Step 7: Write `capabilities/teeup-runtime/doctor`**

```bash file=capabilities/teeup-runtime/doctor
#!/usr/bin/env bash
# What configure put in place, checked from the outside: the env file shells
# and LaunchAgents read, the command link users type, the state tree, and the
# two PATH facts everything lazy depends on.
env_file="$TEEUP_CONFIG_DIR/env"
if [[ -f "$env_file" ]]; then
  # Sourced in a subshell rather than parsed: configure writes the three
  # values %q-escaped, so only a shell can read them back correctly.
  # shellcheck source=/dev/null
  recorded_path="$( (set +u; source "$env_file"; printf '%s\n' "${TEEUP_PATH:-}") )"
  if [[ "$recorded_path" == "$TEEUP_PATH" ]]; then
    doctor_ok "$env_file points at this checkout."
  else
    doctor_fail "$env_file says TEEUP_PATH=${recorded_path:-nothing}, but this checkout is $TEEUP_PATH." "teeup configure teeup-runtime"
  fi
else
  doctor_fail "No $env_file, so shells and LaunchAgents cannot find the checkout." "teeup configure teeup-runtime"
fi

link="$HOME/.local/bin/teeup"
link_target="$(readlink "$link" 2>/dev/null || true)"
if [[ "$link_target" == "$TEEUP_PATH/bin/teeup" ]]; then
  doctor_ok "$link points at this checkout."
elif [[ -e "$link" || -L "$link" ]]; then
  doctor_fail "$link is not teeup's symlink; it points at ${link_target:-a regular file}." "teeup configure teeup-runtime"
else
  doctor_fail "No $link, so the teeup command is not on PATH." "teeup configure teeup-runtime"
fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*)
    doctor_ok "$HOME/.local/bin is on PATH."
    ;;
  *)
    doctor_fail "$HOME/.local/bin is not on PATH, so neither teeup nor its mise wrappers can be run by name." "teeup configure zsh"
    ;;
esac

missing=""
for d in "done" toggles migrations shims logs current stock; do
  if [[ ! -d "$TEEUP_STATE_DIR/$d" ]]; then
    missing="$missing $d"
  fi
done
if [[ -z "$missing" ]]; then
  doctor_ok "Every state directory is present under $TEEUP_STATE_DIR."
else
  doctor_fail "Missing under $TEEUP_STATE_DIR:$missing" "teeup configure teeup-runtime"
fi

# A lazy shim fires only when the calling shell cannot find the real command,
# and that is only true while the shims directory is the LAST thing on PATH.
# The shell layer appends it last; anything that moves it earlier turns a shim
# into a shadow over a real binary.
shims="$(shims_dir)"
case ":$PATH:" in
  *":$shims:"*)
    case "$PATH" in
      "$shims"|*":$shims")
        doctor_ok "The lazy shims directory is last on PATH."
        ;;
      *)
        doctor_warn "The lazy shims directory is on PATH but not last, so a shim can shadow a real command. Open a new login shell, or check what prepends to PATH after ~/.zshenv."
        ;;
    esac
    ;;
  *)
    doctor_fail "$shims is not on PATH, so no lazy shim can fire." "teeup configure zsh"
    ;;
esac

# install puts both in place. Neither is fatal any more (prompts fall back to
# plain reads and the menu parses its own file), so they are notes.
for cmd in gum jq; do
  if have "$cmd"; then
    doctor_ok "$cmd is installed."
  else
    doctor_warn "$cmd is not installed. Run: teeup install teeup-runtime"
  fi
done

doctor_verdict
```

Run: `chmod +x capabilities/teeup-runtime/doctor`

- [ ] **Step 8: Run the teeup-runtime suite**

Run: `bash tests/capabilities/teeup-runtime.sh`
Expected: `Summary: 13/13 passed`.

- [ ] **Step 9: Write the failing tests for `dev-dirs`**

```bash edit-old=tests/capabilities/dev-dirs.sh
echo "capabilities/dev-dirs"
```
```bash edit-new=tests/capabilities/dev-dirs.sh
test_doctor_passes_once_the_root_exists() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure dev-dirs >/dev/null
  local rc=0 out
  out="$(DRY_RUN=false cap_run dev-dirs doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "$TEST_HOME/Work is present" || return 1
  cleanup_test_env
}

test_doctor_reports_a_missing_root_with_its_fix() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run dev-dirs doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$TEST_HOME/Work is missing" || return 1
  assert_contains "$(cat "$report")" "teeup configure dev-dirs" || return 1
  cleanup_test_env
}

echo "capabilities/dev-dirs"
```

```bash edit-old=tests/capabilities/dev-dirs.sh
run_test "existing dirs reported not recreated" test_existing_dirs_are_reported_not_recreated
```
```bash edit-new=tests/capabilities/dev-dirs.sh
run_test "existing dirs reported not recreated" test_existing_dirs_are_reported_not_recreated
run_test "doctor passes once the root exists" test_doctor_passes_once_the_root_exists
run_test "doctor reports a missing root with its fix" test_doctor_reports_a_missing_root_with_its_fix
```

- [ ] **Step 10: Write `capabilities/dev-dirs/doctor`**

```bash file=capabilities/dev-dirs/doctor
#!/usr/bin/env bash
# One directory (2026-09-17 decision: git identity lives in generated
# settings now, not a directory rule, so there is no second root to check).
if [[ -d "$HOME/Work" ]]; then
  doctor_ok "$HOME/Work is present."
else
  doctor_fail "$HOME/Work is missing." "teeup configure dev-dirs"
fi

doctor_verdict
```

Run: `chmod +x capabilities/dev-dirs/doctor`

Run: `bash tests/capabilities/dev-dirs.sh`
Expected: `Summary: 4/4 passed`.

- [ ] **Step 11: Write the failing tests for `zsh`**

```bash edit-old=tests/capabilities/zsh.sh
echo "capabilities/zsh"
```
```bash edit-new=tests/capabilities/zsh.sh
test_doctor_passes_after_configure() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/zsh"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  local rc=0 out
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "Login shell is /bin/zsh." || return 1
  assert_contains "$out" ".zshrc loads teeup's shell layer" || return 1
  cleanup_test_env
}

test_doctor_reports_a_login_shell_that_is_not_zsh() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/bash"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "not zsh" || return 1
  assert_contains "$(cat "$report")" "chsh -s /bin/zsh" || return 1
  cleanup_test_env
}

test_doctor_reports_a_home_file_that_lost_the_teeup_layer() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/zsh"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  printf '# somebody replaced this\n' > "$TEST_HOME/.zshrc"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "never loads" || return 1
  assert_contains "$(cat "$report")" "teeup reset zsh" || return 1
  cleanup_test_env
}

echo "capabilities/zsh"
```

```bash edit-old=tests/capabilities/zsh.sh
run_test "rc leaves git revision syntax alone" test_rc_leaves_git_revision_syntax_alone
```
```bash edit-new=tests/capabilities/zsh.sh
run_test "rc leaves git revision syntax alone" test_rc_leaves_git_revision_syntax_alone
run_test "doctor passes after configure" test_doctor_passes_after_configure
run_test "doctor reports a login shell that is not zsh" test_doctor_reports_a_login_shell_that_is_not_zsh
run_test "doctor reports a home file that lost the layer" test_doctor_reports_a_home_file_that_lost_the_teeup_layer
```

- [ ] **Step 12: Write `capabilities/zsh/doctor`**

```bash file=capabilities/zsh/doctor
#!/usr/bin/env bash
# The shell layer is load-bearing for everything else teeup puts on PATH, and
# it fails silently: a ~/.zshrc that no longer sources the teeup layer looks
# completely normal until you notice nothing teeup installed is reachable.
zsh_home_dir="${ZDOTDIR:-$HOME}"

# The same probe capabilities/zsh/install uses to decide whether to chsh.
login_shell="$(dscl . -read "/Users/${USER:-$(id -un)}" UserShell 2>/dev/null | awk '{print $2}')"
case "$login_shell" in
  */zsh)
    doctor_ok "Login shell is $login_shell."
    ;;
  *)
    doctor_fail "Login shell is ${login_shell:-unknown}, not zsh, so none of teeup's shell layer runs." "chsh -s /bin/zsh"
    ;;
esac

# Each shipped home file sources one file out of the default layer, and that
# path is the one part configure never rewrites, so it is the marker that
# survives a config dir with spaces or metacharacters in it.
for f in .zshenv .zprofile .zshrc; do
  if [[ ! -f "$zsh_home_dir/$f" ]]; then
    doctor_fail "No $zsh_home_dir/$f." "teeup configure zsh"
  elif grep -qF 'capabilities/zsh/default/' "$zsh_home_dir/$f"; then
    doctor_ok "$zsh_home_dir/$f loads teeup's shell layer."
  else
    doctor_fail "$zsh_home_dir/$f does not source teeup's default layer, so teeup's shell configuration never loads." "teeup reset zsh"
  fi
done

# Where the user's own lines are meant to go. Without it ~/.zshrc sources
# nothing at the end, which is harmless, but the documented place to put a
# machine-specific line has quietly stopped existing.
local_zsh="$(user_config_dir)/zsh/local.zsh"
if [[ -f "$local_zsh" ]]; then
  doctor_ok "$local_zsh is present for your own lines."
else
  doctor_fail "No $local_zsh, which is where your own shell lines belong." "teeup configure zsh"
fi

doctor_verdict
```

Run: `chmod +x capabilities/zsh/doctor`

- [ ] **Step 13: Run the four suites**

Run: `bash tests/capabilities/package-manager.sh && bash tests/capabilities/teeup-runtime.sh && bash tests/capabilities/dev-dirs.sh && bash tests/capabilities/zsh.sh`
Expected: `Summary: 7/7 passed`, `Summary: 13/13 passed`, `Summary: 4/4 passed`, `Summary: 26/26 passed`.

- [ ] **Step 14: Run every check**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning capabilities/package-manager/doctor capabilities/teeup-runtime/doctor capabilities/dev-dirs/doctor capabilities/zsh/doctor tests/capabilities/package-manager.sh tests/capabilities/teeup-runtime.sh tests/capabilities/dev-dirs.sh tests/capabilities/zsh.sh && git diff --check`
Expected: `All N suites passed.` with N unchanged from the previous task (no new suite file); `commands --check` silent and exit 0; shellcheck silent; `git diff --check` silent.

- [ ] **Step 15: Commit**

```bash
git add capabilities/package-manager/doctor capabilities/teeup-runtime/doctor capabilities/dev-dirs/doctor capabilities/zsh/doctor tests/capabilities/package-manager.sh tests/capabilities/teeup-runtime.sh tests/capabilities/dev-dirs.sh tests/capabilities/zsh.sh
git commit -m "Add doctor checks for the package manager, runtime, project roots and shell layer"
```

---
### Task 3: Doctor scripts for identity

The three capabilities that decide what name is on a commit and which key pushes it. Their failures are the quiet kind: a commit signed with a key GitHub has never seen, or a push going out under a key `~/.ssh/config` names but teeup never generated, both look fine locally and are noticed weeks later.

This task takes the `gpg.ssh.allowedSignersFile` finding that phase 2a's review deferred and phase 4a handed on: the shipped git config turns on `commit.gpgsign` with `gpg.format = ssh`, and git cannot verify a single one of those signatures without an allowed-signers file.

**Files:**
- Create: `capabilities/git/doctor`, `capabilities/ssh/doctor`, `capabilities/github/doctor`
- Modify: `tests/capabilities/git.sh`, `tests/capabilities/ssh.sh`, `tests/capabilities/github.sh`

**Interfaces:**
- Consumes: `doctor_ok doctor_warn doctor_fail doctor_verdict` (Task 1); `identity_list identity_email identity_key ssh_host_alias answers_has_work` (`lib/answers.sh`); `user_config_dir have` (`lib/core.sh`).
- Produces: three executable `doctor` scripts, and a `gh_key_listed <key-body>` helper local to `capabilities/github/doctor`.

**Real-Mac risk:** the GitHub checks talk to a real `gh` session over the network; the mocked suite proves the parsing of `gh auth status --active -h github.com` and the tab-separated `gh ssh-key list`, not that gh 2.100.0 on a real Mac prints those shapes. The key permission checks use `stat -c` with a `stat -f` fallback, and only BSD `stat` on a real Mac proves the fallback is the branch that runs.

- [ ] **Step 1: Write the failing tests for `git`**

```bash edit-old=tests/capabilities/git.sh
echo "capabilities/git"
```
```bash edit-new=tests/capabilities/git.sh
# A configured git tree with its one key pair on disk, which is the state in
# which commit signing is supposed to be on. Git has one identity, full stop,
# so there is no work key to seed here -- that only ever exists when
# machines/<hostname>.conf configures one, and git never reads it.
configure_git_with_keys() {
  seed_answers
  mkdir -p "$TEST_HOME/.ssh"
  printf 'PRIVATE\n' > "$TEST_HOME/.ssh/id_ed25519_personal"
  printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAKEKEYpersonal personal\n' > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
}

test_doctor_passes_on_a_configured_tree() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  printf '%s\n' "ada@example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAKEKEYpersonal" \
    > "$TEST_HOME/.config/git/allowed_signers"
  printf '[gpg "ssh"]\n\tallowedSignersFile = "%s"\n' "$TEST_HOME/.config/git/allowed_signers" \
    > "$TEST_HOME/.config/git/local"
  local rc=0 out
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "Identity: ada@example.com" || return 1
  assert_contains "$out" "Commit signing is on" || return 1
  cleanup_test_env
}

test_doctor_reports_an_unconfigured_tree() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "git has never been configured here" || return 1
  assert_contains "$(cat "$report")" "teeup configure git" || return 1
  cleanup_test_env
}

test_doctor_reports_signing_left_off_although_the_keys_exist() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  seed_answers
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  # The keys arrive after git was configured, which is exactly the order a
  # first bootstrap runs in: git, then ssh.
  mkdir -p "$TEST_HOME/.ssh"
  printf 'PRIVATE\n' > "$TEST_HOME/.ssh/id_ed25519_personal"
  printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAKEKEY personal\n' > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "every key it needs is on disk but commit signing is off" || return 1
  assert_contains "$(cat "$report")" "teeup configure git" || return 1
  cleanup_test_env
}

test_doctor_reports_a_missing_allowed_signers_file() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "gpg.ssh.allowedSignersFile is not set" || return 1
  assert_contains "$(cat "$report")" "allowedSignersFile" || return 1
  cleanup_test_env
}

test_doctor_warns_about_a_leftover_gitconfig() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  configure_git_with_keys
  printf '[user]\n\temail = someone@else\n' > "$TEST_HOME/.gitconfig"
  local out
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || true
  assert_contains "$out" "$TEST_HOME/.gitconfig exists and its keys win" || return 1
  cleanup_test_env
}

echo "capabilities/git"
```

```bash edit-old=tests/capabilities/git.sh
run_test "configure quotes special characters in the name" test_configure_quotes_special_characters_in_the_name
```
```bash edit-new=tests/capabilities/git.sh
run_test "configure quotes special characters in the name" test_configure_quotes_special_characters_in_the_name
run_test "doctor passes on a configured tree" test_doctor_passes_on_a_configured_tree
run_test "doctor reports an unconfigured tree" test_doctor_reports_an_unconfigured_tree
run_test "doctor reports signing left off" test_doctor_reports_signing_left_off_although_the_keys_exist
run_test "doctor reports a missing allowed-signers file" test_doctor_reports_a_missing_allowed_signers_file
run_test "doctor warns about a leftover ~/.gitconfig" test_doctor_warns_about_a_leftover_gitconfig
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/capabilities/git.sh`
Expected: the five new tests fail with `git has no doctor script`; the suite ends with `Summary: 20/25 passed`.

- [ ] **Step 3: Write `capabilities/git/doctor`**

```bash file=capabilities/git/doctor
#!/usr/bin/env bash
# Read the config files rather than asking `git config`: the files are what
# `teeup configure git` owns, and reading them says which of the three layers
# (shipped, generated, yours) a value came from, which is the thing that goes
# wrong here.
git_dir="$(user_config_dir)/git"

if [[ ! -f "$git_dir/config" ]]; then
  doctor_fail "git has never been configured here: there is no $git_dir/config." "teeup configure git"
  doctor_verdict
  exit
fi
doctor_ok "$git_dir/config is in place."

# One identity, full stop (2026-09-17 decision): git carries whatever
# $git_dir/identity says regardless of where a repository sits, so there is
# only ever this one file to check, never a per-root pair.
identity_file="$git_dir/identity"
if [[ ! -f "$identity_file" ]]; then
  doctor_fail "No $identity_file, so the git identity resolves to nothing." "teeup configure git"
elif grep -q '^[[:space:]]*email[[:space:]]*=[[:space:]]*"..*"' "$identity_file"; then
  doctor_ok "Identity: $(sed -n 's/^[[:space:]]*email[[:space:]]*=[[:space:]]*"\(.*\)"$/\1/p' "$identity_file" | head -1)"
else
  doctor_fail "$identity_file has no email, so commits would be unattributed." "teeup configure git"
fi

generated="$git_dir/teeup-generated"
if [[ ! -f "$generated" ]]; then
  doctor_fail "No $generated, so the editor, pager and signing settings the shipped config expects are missing." "teeup configure git"
  doctor_verdict
  exit
fi

# The generated file records what was installed when configure last ran. A
# delta that has since been installed means it is stale, and `git diff` is
# quietly plainer than it should be.
if have delta; then
  if grep -q '^[[:space:]]*pager = delta$' "$generated"; then
    doctor_ok "delta is git's pager."
  else
    doctor_fail "delta is installed but $generated still names another pager." "teeup configure git"
  fi
fi

# Signing turns itself on at the next configure once the personal key has
# both halves -- git signs with that key alone, whatever repository it is in,
# so a work key (when one even exists) never enters into this. On a first
# bootstrap git runs before ssh, so this is the ordinary state of a machine
# that has not been re-configured since.
personal_key="$(identity_key personal)"
if [[ -s "$personal_key" && -s "$personal_key.pub" ]]; then
  keys_present=true
else
  keys_present=false
fi
if grep -q '^[[:space:]]*gpgsign = true$' "$generated"; then
  doctor_ok "Commit signing is on."
  signing_on=true
elif [[ "$keys_present" == "true" ]]; then
  doctor_fail "git has every key it needs is on disk but commit signing is off in $generated." "teeup configure git"
  signing_on=false
else
  doctor_warn "Commit signing is off because the personal key does not exist yet. Run: teeup configure ssh"
  signing_on=false
fi

# Signing with an SSH key is only half of it. Verification reads
# gpg.ssh.allowedSignersFile, and with none set `git log --show-signature`
# reports every commit teeup just signed as having no known signer. Nothing in
# teeup writes that file yet, so the fix is a command, not a verb.
if [[ "$signing_on" == "true" ]]; then
  signers_set=false
  for f in "$git_dir/config" "$generated" "$git_dir/local"; do
    if [[ -f "$f" ]] && grep -qi 'allowedSignersFile' "$f"; then
      signers_set=true
    fi
  done
  if [[ "$signers_set" == "true" ]]; then
    doctor_ok "gpg.ssh.allowedSignersFile is set, so signatures can be verified."
  else
    signers="$git_dir/allowed_signers"
    personal_pub="$(identity_key personal).pub"
    doctor_fail "Commit signing is on with gpg.format = ssh, but gpg.ssh.allowedSignersFile is not set, so git cannot verify any signature it makes. Add one line per identity." \
      "printf '%s %s\n' \"\$(git config user.email)\" \"\$(cat $personal_pub)\" >> $signers && git config --global gpg.ssh.allowedSignersFile $signers"
  fi
fi

# Two ways for the whole tree above to be ignored. teeup never edits either,
# so both are notes with an instruction rather than failures with a fix.
if [[ -f "$HOME/.gitconfig" ]]; then
  doctor_warn "$HOME/.gitconfig exists and its keys win over $git_dir/config. Move what you want to keep into $git_dir/local, then delete it."
fi
if [[ -n "${GIT_CONFIG_GLOBAL:-}" ]]; then
  doctor_warn "GIT_CONFIG_GLOBAL=$GIT_CONFIG_GLOBAL overrides $git_dir/config outright; nothing above is read."
fi

doctor_verdict
```

Run: `chmod +x capabilities/git/doctor`

- [ ] **Step 4: Run the git suite**

Run: `bash tests/capabilities/git.sh`
Expected: `Summary: 25/25 passed`.

- [ ] **Step 5: Write the failing tests for `ssh`**

```bash edit-old=tests/capabilities/ssh.sh
echo "capabilities/ssh"
```
```bash edit-new=tests/capabilities/ssh.sh
test_doctor_passes_after_configure() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  seed_answers
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  local rc=0 out
  out="$(DRY_RUN=false cap_run ssh doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "personal key pair is present" || return 1
  assert_contains "$out" "Host github.com" || return 1
  cleanup_test_env
}

test_doctor_reports_a_missing_key_pair() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  seed_answers
  # The directory exists and is correctly locked down; what is missing is the
  # keys, which is the state a half-finished `teeup configure ssh` leaves.
  mkdir -p "$TEST_HOME/.ssh"
  chmod 700 "$TEST_HOME/.ssh"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run ssh doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "has no key pair" || return 1
  assert_contains "$(cat "$report")" "teeup configure ssh" || return 1
  cleanup_test_env
}

test_doctor_reports_a_world_readable_private_key() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  seed_answers
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  chmod 644 "$TEST_HOME/.ssh/id_ed25519_personal"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run ssh doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "is mode 644" || return 1
  assert_contains "$(cat "$report")" "chmod 600 $TEST_HOME/.ssh/id_ed25519_personal" || return 1
  cleanup_test_env
}

echo "capabilities/ssh"
```

```bash edit-old=tests/capabilities/ssh.sh
run_test "configure twice changes nothing" test_configure_twice_changes_nothing
```
```bash edit-new=tests/capabilities/ssh.sh
run_test "configure twice changes nothing" test_configure_twice_changes_nothing
run_test "doctor passes after configure" test_doctor_passes_after_configure
run_test "doctor reports a missing key pair" test_doctor_reports_a_missing_key_pair
run_test "doctor reports a world-readable private key" test_doctor_reports_a_world_readable_private_key
```

- [ ] **Step 6: Write `capabilities/ssh/doctor`**

```bash file=capabilities/ssh/doctor
#!/usr/bin/env bash
# Keys, their permissions, and the host aliases that decide which key a push
# uses. ssh refuses a private key other people can read, and it refuses it at
# the moment you need it, so the mode is checked here rather than assumed.
ssh_dir="$HOME/.ssh"

# The same probe capabilities/ssh/configure's chmod_once uses: GNU stat first
# because its -f means something else entirely, BSD stat second.
mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || printf 'unknown\n'; }

if [[ ! -d "$ssh_dir" ]]; then
  doctor_fail "No $ssh_dir, so no identity exists on this machine." "teeup configure ssh"
  doctor_verdict
  exit
fi
if [[ "$(mode_of "$ssh_dir")" == "700" ]]; then
  doctor_ok "$ssh_dir is mode 700."
else
  doctor_fail "$ssh_dir is mode $(mode_of "$ssh_dir"), not 700." "chmod 700 $ssh_dir"
fi

for identity in $(identity_list); do
  key="$(identity_key "$identity")"
  if [[ ! -s "$key" || ! -s "$key.pub" ]]; then
    doctor_fail "The $identity identity has no key pair at $key." "teeup configure ssh"
    continue
  fi
  doctor_ok "The $identity key pair is present at $key."
  if [[ "$(mode_of "$key")" != "600" ]]; then
    doctor_fail "$key is mode $(mode_of "$key"); ssh refuses a private key other accounts can read." "chmod 600 $key"
  fi
done

# Only the aliases identity_list actually names: github.com-work is rendered
# only on a machine whose machines/<hostname>.conf configures a work
# identity, so checking for it unconditionally would fail every personal-only
# machine, which is most of them.
if [[ ! -f "$ssh_dir/config" ]]; then
  doctor_fail "No $ssh_dir/config, so no identity's key is ever offered to github.com." "teeup configure ssh"
else
  for identity in $(identity_list); do
    host_alias="Host $(ssh_host_alias "$identity")"
    if grep -q "^$host_alias\$" "$ssh_dir/config"; then
      doctor_ok "$ssh_dir/config declares $host_alias."
    else
      doctor_fail "$ssh_dir/config has no '$host_alias' block." "teeup reset ssh"
    fi
  done
fi

# The agent is per-session state, not configuration: a Mac that has just been
# rebooted has an empty agent and nothing is wrong.
if have ssh-add; then
  if ssh-add -l >/dev/null 2>&1; then
    doctor_ok "The ssh agent is holding at least one key."
  else
    doctor_warn "The ssh agent is holding no key yet; it fills up on first use. Run: ssh-add --apple-use-keychain $(identity_key personal)"
  fi
fi

doctor_verdict
```

Run: `chmod +x capabilities/ssh/doctor`

Run: `bash tests/capabilities/ssh.sh`
Expected: `Summary: 22/22 passed`.

- [ ] **Step 7: Write the failing tests for `github`**

```bash edit-old=tests/capabilities/github.sh
echo "capabilities/github"
```
```bash edit-new=tests/capabilities/github.sh
# github.sh seeds keys but never answers; identity_list needs the latter.
seed_github_answers() {
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_NAME="Ada Lovelace"\nTEEUP_EMAIL="ada@example.com"\nTEEUP_WORK_EMAIL=""\n' \
    > "$TEST_HOME/.config/teeup/answers"
}

test_doctor_passes_when_signed_in_with_the_keys_uploaded() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  seed_github_answers
  seed_keys
  printf 'admin:public_key,admin:ssh_signing_key,repo\n' > "$TEST_HOME/gh-session"
  printf 'laptop\tssh-ed25519 AAAAPERSONALKEY\t2026\t1\tauthentication\n' > "$TEST_HOME/gh-keys"
  printf 'signing\tssh-ed25519 AAAAPERSONALKEY\t2026\t2\tsigning\n' >> "$TEST_HOME/gh-keys"
  local rc=0 out
  out="$(DRY_RUN=false cap_run github doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "Signed in to github.com" || return 1
  assert_contains "$out" "personal public key is on GitHub" || return 1
  cleanup_test_env
}

test_doctor_reports_being_signed_out() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  seed_github_answers
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run github doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Not signed in to github.com" || return 1
  assert_contains "$(cat "$report")" "teeup configure github" || return 1
  cleanup_test_env
}

test_doctor_reports_missing_scopes_and_an_unuploaded_key() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  seed_github_answers
  seed_keys
  printf 'repo\n' > "$TEST_HOME/gh-session"
  : > "$TEST_HOME/gh-keys"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run github doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "admin:public_key" || return 1
  assert_contains "$out" "is not on GitHub" || return 1
  assert_contains "$(cat "$report")" "gh auth refresh" || return 1
  cleanup_test_env
}

echo "capabilities/github"
```

```bash edit-old=tests/capabilities/github.sh
run_test "configure twice uploads nothing new" test_configure_twice_uploads_nothing_new
```
```bash edit-new=tests/capabilities/github.sh
run_test "configure twice uploads nothing new" test_configure_twice_uploads_nothing_new
run_test "doctor passes when signed in with keys uploaded" test_doctor_passes_when_signed_in_with_the_keys_uploaded
run_test "doctor reports being signed out" test_doctor_reports_being_signed_out
run_test "doctor reports missing scopes and an unuploaded key" test_doctor_reports_missing_scopes_and_an_unuploaded_key
```

- [ ] **Step 8: Write `capabilities/github/doctor`**

```bash file=capabilities/github/doctor
#!/usr/bin/env bash
# Pinned for the same reason configure pins it: a GH_HOST left over in the
# environment would send every call below at some other host and report on it.
export GH_HOST=github.com

if ! have gh; then
  doctor_fail "gh is not installed, so nothing can talk to GitHub." "teeup install github"
  doctor_verdict
  exit
fi

# --active narrows the report to the one account gh will actually use for this
# host. Without it an unrelated stale account decides the exit status, and its
# scopes are the ones that get read.
if ! status_out="$(gh auth status --active -h github.com 2>&1)"; then
  doctor_fail "Not signed in to github.com." "teeup configure github"
  doctor_verdict
  exit
fi
doctor_ok "Signed in to github.com."

# The two scopes the key uploads need. A machine that authenticated gh before
# teeup existed is usually missing both.
for scope in admin:public_key admin:ssh_signing_key; do
  case "$status_out" in
    *"$scope"*) doctor_ok "gh has the $scope scope." ;;
    *) doctor_fail "gh's token is missing the $scope scope, so teeup cannot upload your keys." "gh auth refresh -h github.com -s admin:public_key,admin:ssh_signing_key" ;;
  esac
done

# Captured, so gh takes its non-TTY path and prints tab-separated columns
# (gh 2.100.0: TITLE, KEY, ADDED, ID, TYPE). The title is what the user types,
# so a key is only ever matched on a whole field whose second word is exactly
# our key body; a body that merely contains ours is somebody else's key.
listed="$(gh ssh-key list 2>/dev/null || true)"
gh_key_listed() {
  printf '%s\n' "$listed" | awk -F'\t' -v body="$1" '
    { for (f = 2; f <= NF; f++) { split($f, w, " "); if (w[2] == body) { found = 1 } } }
    END { exit(found ? 0 : 1) }
  '
}

for identity in $(identity_list); do
  pub="$(identity_key "$identity").pub"
  if [[ ! -s "$pub" ]]; then
    doctor_warn "The $identity identity has no public key yet, so there is nothing to upload. Run: teeup configure ssh"
    continue
  fi
  body="$(awk '{print $2; exit}' "$pub")"
  if gh_key_listed "$body"; then
    doctor_ok "The $identity public key is on GitHub."
  else
    doctor_fail "The $identity public key is not on GitHub, so pushes with it are refused." "teeup configure github"
  fi
done

doctor_verdict
```

Run: `chmod +x capabilities/github/doctor`

- [ ] **Step 9: Run the three suites**

Run: `bash tests/capabilities/git.sh && bash tests/capabilities/ssh.sh && bash tests/capabilities/github.sh`
Expected: `Summary: 25/25 passed`, `Summary: 22/22 passed`, `Summary: 23/23 passed`.

- [ ] **Step 10: Run every check**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning capabilities/git/doctor capabilities/ssh/doctor capabilities/github/doctor tests/capabilities/git.sh tests/capabilities/ssh.sh tests/capabilities/github.sh && git diff --check`
Expected: `All N suites passed.` with N unchanged from the previous task; `commands --check` silent and exit 0; shellcheck silent; `git diff --check` silent.

- [ ] **Step 11: Commit**

```bash
git add capabilities/git/doctor capabilities/ssh/doctor capabilities/github/doctor tests/capabilities/git.sh tests/capabilities/ssh.sh tests/capabilities/github.sh
git commit -m "Add doctor checks for git identity, ssh keys and the GitHub session"
```

---
### Task 4: Doctor scripts for generated state

Three capabilities whose output is generated rather than copied, so "it was configured once" says nothing about whether it is still right. A theme template added by a later phase has no rendered file until someone re-runs `teeup theme set`; a `starship.toml` whose palette markers were edited away silently stops following the theme; a mise whose shims left PATH makes every globally installed tool vanish.

**Files:**
- Create: `capabilities/mise/doctor`, `capabilities/starship/doctor`, `capabilities/theme/doctor`
- Modify: `tests/capabilities/mise.sh`, `tests/capabilities/starship.sh`, `tests/capabilities/theme.sh`

**Interfaces:**
- Consumes: `doctor_ok doctor_warn doctor_fail doctor_verdict` (Task 1); `mise_global_state <tool>` and `dev_env_installed` (`lib/mise.sh`, phase 3b Tasks 2 and 4); `theme_current theme_templates` (`lib/theme.sh`); `user_config_dir have` (`lib/core.sh`).
- Produces: three executable `doctor` scripts. No new function or variable.

**Real-Mac risk:** the mise checks call `mise -C / ls --global`, whose output shape was verified against mise 2026.9.4 but which only a real installation confirms; the starship check reads a file the user owns, so only a real machine with a hand-edited `starship.toml` proves the marker scan says something useful rather than merely refusing.

- [ ] **Step 1: Write the failing tests for `mise`**

```bash edit-old=tests/capabilities/mise.sh
echo "capabilities/mise"
```
```bash edit-new=tests/capabilities/mise.sh
# The mise suite's own mock is driven by two files: $HOME/mise-tools is what
# the global config asks for, $HOME/mise-installed is what is on disk. Keeping
# them apart is the whole point of mise_global_state, so the doctor tests use
# the same mock rather than a second one that could drift from it.
seed_mise_shims() {
  export XDG_DATA_HOME="$TEST_HOME/.local/share"
  mkdir -p "$XDG_DATA_HOME/mise/shims"
  export PATH="$PATH:$XDG_DATA_HOME/mise/shims"
}

test_doctor_passes_on_a_configured_machine() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure mise >/dev/null 2>&1
  seed_mise_shims
  local rc=0 out
  out="$(DRY_RUN=false cap_run mise doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "pre-commit is installed through mise" || return 1
  assert_contains "$out" "mise shims directory is on PATH" || return 1
  cleanup_test_env
}

test_doctor_reports_a_missing_mise_and_config() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  hide_host_commands mise
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run mise doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "mise is not on PATH" || return 1
  assert_contains "$(cat "$report")" "teeup install mise" || return 1
  cleanup_test_env
}

test_doctor_reports_pre_commit_requested_but_not_installed() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure mise >/dev/null 2>&1
  seed_mise_shims
  # The global config still asks for pre-commit; the binary is gone, which is
  # what an interrupted install or a wiped MISE_DATA_DIR leaves behind.
  : > "$TEST_HOME/mise-installed"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run mise doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "pre-commit is asked for but not installed" || return 1
  assert_contains "$(cat "$report")" "teeup configure mise" || return 1
  cleanup_test_env
}

echo "capabilities/mise"
```

```bash edit-old=tests/capabilities/mise.sh
print_summary
```
```bash edit-new=tests/capabilities/mise.sh
run_test "doctor passes on a configured machine" test_doctor_passes_on_a_configured_machine
run_test "doctor reports a missing mise and config" test_doctor_reports_a_missing_mise_and_config
run_test "doctor reports pre-commit requested but missing" test_doctor_reports_pre_commit_requested_but_not_installed
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/capabilities/mise.sh`
Expected: the three new tests fail with `mise has no doctor script`; the suite ends with `Summary: 10/13 passed`.

- [ ] **Step 3: Write `capabilities/mise/doctor`**

```bash file=capabilities/mise/doctor
#!/usr/bin/env bash
# mise is reached two ways, and both have to work: the command itself, and the
# shims directory the shell layer appends so a tool installed through mise is
# on PATH in shells that never ran `mise activate`.
if ! have mise; then
  doctor_fail "mise is not on PATH, so no runtime or tool it manages can be reached." "teeup install mise"
  doctor_verdict
  exit
fi
doctor_ok "mise is on PATH."

mise_config="${MISE_CONFIG_DIR:-$(user_config_dir)/mise}/config.toml"
if [[ -f "$mise_config" ]]; then
  doctor_ok "The global mise config is at $mise_config."
else
  doctor_fail "No $mise_config, so mise has no global tool list." "teeup configure mise"
fi

# The path the shell layer appends, spelled the way mise itself resolves it:
# MISE_DATA_DIR, else XDG_DATA_HOME, else ~/.local/share.
mise_shims="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/shims"
case ":$PATH:" in
  *":$mise_shims:"*)
    doctor_ok "The mise shims directory is on PATH."
    ;;
  *)
    doctor_fail "$mise_shims is not on PATH, so tools installed through mise are invisible to shells that did not run mise activate." "teeup configure zsh"
    ;;
esac

# mise_global_state (lib/mise.sh) keeps the two questions apart: the global
# config can ask for a tool that is not on disk, and a row in `ls --global` is
# no proof of a binary.
case "$(mise_global_state pre-commit)" in
  installed)
    doctor_ok "pre-commit is installed through mise."
    ;;
  requested)
    doctor_fail "pre-commit is asked for but not installed, so every repository's hooks fail." "teeup configure mise"
    ;;
  *)
    doctor_fail "pre-commit is not in the global mise config." "teeup configure mise"
    ;;
esac

# Not a health question, but the one thing people ask this capability.
envs="$(dev_env_installed | tr '\n' ' ')"
doctor_ok "Development environments installed: ${envs:-none (teeup install dev-env <python|node|java|ruby|rust|go>)}"

doctor_verdict
```

Run: `chmod +x capabilities/mise/doctor`

Run: `bash tests/capabilities/mise.sh`
Expected: `Summary: 13/13 passed`.

- [ ] **Step 4: Write the failing tests for `starship`**

```bash edit-old=tests/capabilities/starship.sh
echo "capabilities/starship"
```
```bash edit-new=tests/capabilities/starship.sh
test_doctor_passes_after_configure() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command starship 0 "starship 1.23.0"
  DRY_RUN=false "$TEEUP" configure starship >/dev/null 2>&1
  local rc=0 out
  out="$(DRY_RUN=false cap_run starship doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "palette block is intact" || return 1
  cleanup_test_env
}

test_doctor_reports_a_missing_config() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command starship 0 "starship 1.23.0"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run starship doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "starship.toml" || return 1
  assert_contains "$(cat "$report")" "teeup configure starship" || return 1
  cleanup_test_env
}

test_doctor_reports_palette_markers_that_were_edited_away() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command starship 0 "starship 1.23.0"
  DRY_RUN=false "$TEEUP" configure starship >/dev/null 2>&1
  grep -v 'teeup:theme-palette' "$TEST_HOME/.config/starship.toml" > "$TEST_HOME/trimmed"
  mv "$TEST_HOME/trimmed" "$TEST_HOME/.config/starship.toml"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run starship doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "no longer follows the teeup theme" || return 1
  assert_contains "$(cat "$report")" "teeup reset starship" || return 1
  cleanup_test_env
}

echo "capabilities/starship"
```

```bash edit-old=tests/capabilities/starship.sh
print_summary
```
```bash edit-new=tests/capabilities/starship.sh
run_test "doctor passes after configure" test_doctor_passes_after_configure
run_test "doctor reports a missing config" test_doctor_reports_a_missing_config
run_test "doctor reports palette markers edited away" test_doctor_reports_palette_markers_that_were_edited_away
print_summary
```

- [ ] **Step 5: Write `capabilities/starship/doctor`**

```bash file=capabilities/starship/doctor
#!/usr/bin/env bash
# The prompt itself, and the one part of its config teeup keeps writing: the
# marker block `teeup theme set` rewrites. Lose the markers and the prompt
# keeps working while quietly staying on whatever colours it had, which is the
# kind of failure nobody reports because nothing looks broken.
if have starship; then
  doctor_ok "starship is on PATH."
else
  doctor_fail "starship is not on PATH, so the prompt falls back to zsh's default." "teeup install starship"
fi

config="$(user_config_dir)/starship.toml"
if [[ ! -f "$config" ]]; then
  doctor_fail "No $config, so starship runs on its built-in defaults." "teeup configure starship"
  doctor_verdict
  exit
fi
doctor_ok "$config is in place."

start_count="$(grep -cxF '# teeup:theme-palette:start' "$config" || true)"
end_count="$(grep -cxF '# teeup:theme-palette:end' "$config" || true)"
if [[ "$start_count" -eq 1 && "$end_count" -eq 1 ]]; then
  doctor_ok "The starship palette block is intact."
elif [[ "$start_count" -eq 0 && "$end_count" -eq 0 ]]; then
  doctor_fail "$config has no teeup:theme-palette markers, so it no longer follows the teeup theme." "teeup reset starship"
else
  doctor_fail "$config has $start_count start and $end_count teeup:theme-palette end markers; the palette rewrite refuses anything but one of each, so it no longer follows the teeup theme." "teeup reset starship"
fi

# The root selector the theme switch rewrites. Without it the palette tables
# are present and unused.
if grep -q '^palette *=' "$config"; then
  doctor_ok "A root palette selector is present."
else
  doctor_fail "$config has no root 'palette =' line, so the rendered palettes are never selected." "teeup reset starship"
fi

doctor_verdict
```

Run: `chmod +x capabilities/starship/doctor`

- [ ] **Step 6: Write the failing tests for `theme`**

```bash edit-old=tests/capabilities/theme.sh
echo "capabilities/theme"
```
```bash edit-new=tests/capabilities/theme.sh
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
  # every later phase does.
  mkdir -p "$TEEUP_CAPS_DIR/theme/themed"
  printf 'color = "{{ base }}"\n' > "$TEEUP_CAPS_DIR/theme/themed/latecomer.conf.tpl"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run theme doctor 2>&1)" || rc=$?
  rm -f "$TEEUP_CAPS_DIR/theme/themed/latecomer.conf.tpl"
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

echo "capabilities/theme"
```

```bash edit-old=tests/capabilities/theme.sh
print_summary
```
```bash edit-new=tests/capabilities/theme.sh
run_test "doctor passes after a theme switch" test_doctor_passes_after_a_theme_switch
run_test "doctor reports a machine with no theme" test_doctor_reports_a_machine_with_no_theme
run_test "doctor reports a template never rendered" test_doctor_reports_a_template_that_was_never_rendered
run_test "doctor reports an unresolved token" test_doctor_reports_an_unresolved_token_in_a_rendered_file
print_summary
```

- [ ] **Step 7: Write `capabilities/theme/doctor`**

```bash file=capabilities/theme/doctor
#!/usr/bin/env bash
# A theme is only as applied as its last render. Every later phase adds
# templates, and a template added after the last `teeup theme set` has no
# rendered file at all -- the tool it belongs to silently keeps the colours it
# was shipped with, and nothing anywhere says so.
name="$(theme_current)"
if [[ "$name" == "none" ]]; then
  doctor_fail "No theme has been applied on this machine." "teeup theme set catppuccin"
  doctor_verdict
  exit
fi
doctor_ok "Current theme: $name"

current="$TEEUP_STATE_DIR/current/theme"
for mode in dark light; do
  if [[ -d "$current/$mode" ]]; then
    doctor_ok "Rendered $mode files are in $current/$mode."
  else
    doctor_fail "No $current/$mode, so nothing follows the theme in $mode mode." "teeup theme set $name"
  fi
done

# theme_templates lists user templates first, then every capability's; the
# rendered name is the basename with .tpl removed, once per mode.
for tpl in $(theme_templates); do
  base="${tpl##*/}"
  base="${base%.tpl}"
  for mode in dark light; do
    rendered="$current/$mode/$base"
    if [[ ! -f "$rendered" ]]; then
      doctor_fail "$base has never been rendered for $mode mode." "teeup theme set $name"
    elif grep -q '{{' "$rendered"; then
      doctor_fail "$rendered still holds an unresolved {{ token }}." "teeup theme set $name"
    fi
  done
done

# The appearance the shell layer and every theme-apply hook read. Not a
# failure: on a Mac in light mode `defaults read -g AppleInterfaceStyle` exits
# 1, which is the correct answer and not an error.
doctor_ok "macOS appearance right now: $(appearance)"

doctor_verdict
```

Run: `chmod +x capabilities/theme/doctor`

- [ ] **Step 8: Run the three suites**

Run: `bash tests/capabilities/mise.sh && bash tests/capabilities/starship.sh && bash tests/capabilities/theme.sh`
Expected: `Summary: 13/13 passed`, `Summary: 8/8 passed`, `Summary: 23/23 passed`.

- [ ] **Step 9: Run every check**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning capabilities/mise/doctor capabilities/starship/doctor capabilities/theme/doctor tests/capabilities/mise.sh tests/capabilities/starship.sh tests/capabilities/theme.sh && git diff --check`
Expected: `All N suites passed.` with N unchanged from the previous task; `commands --check` silent and exit 0; shellcheck silent; `git diff --check` silent.

- [ ] **Step 10: Commit**

```bash
git add capabilities/mise/doctor capabilities/starship/doctor capabilities/theme/doctor tests/capabilities/mise.sh tests/capabilities/starship.sh tests/capabilities/theme.sh
git commit -m "Add doctor checks for mise, the starship palette and the rendered theme"
```

---
### Task 5: `lib/menu.awk` and `lib/menu.sh`

The menu file is read with awk, not jq. macOS ships no jq, and the test harness narrows PATH to `$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin`, which hides Homebrew's — so a jq-based reader would leave every menu test either skipped on the macOS runners or dependent on the developer's own machine. The grammar the parser accepts is deliberately narrower than JSON (one object of objects of strings), which is exactly the menu format and fits in a hundred lines of awk.

This task builds the library and its tests. Nothing calls it yet; Task 6 adds the file and the verb.

**Files:**
- Create: `lib/menu.awk`, `lib/menu.sh`, `tests/lib/menu.sh`
- Modify: `lib/all.sh`

**Interfaces:**
- Consumes: `err warn die have run_cmd` (`lib/core.sh`); `_ui_gum` (`lib/ui.sh`) — the single source of truth for "is gum usable", so the menu and the wizard can never disagree.
- Produces:
  - `TEEUP_MENU_FILE` — the shipped menu path, default `$TEEUP_PATH/share/teeup/menu.json`; a test hook.
  - `menu_user_file` — prints `$TEEUP_CONFIG_DIR/menu.json`.
  - `menu_parse <file>` — prints `id<TAB>field<TAB>value` per field, in file order; 1 with a message on stderr for a malformed file.
  - `menu_entries` — the shipped file merged with the user file; same format; 1 on a bad file.
  - `menu_cache` — prints the path of a temp file holding `menu_entries`; the caller deletes it. 1 on failure.
  - `menu_ids <cache>` — every declared id, in file order, once each.
  - `menu_children <cache> [parent]` — the direct children of `parent` (`""` for the top level), in file order.
  - `menu_field <cache> <id> <field>` — the value, or nothing.
  - `menu_label <cache> <id>` — `icon label` when an icon is set, else `label`, else the id.
  - `menu_visible <cache> <id>` — 0 when the row has no `when` or its `when` succeeds.
  - `menu_run <action>` — runs the action; prints it instead under `DRY_RUN`.
  - `menu_picker` — `gum`, `fzf` or `plain`; `die`s on an unknown `TEEUP_MENU_PICKER`.
  - `menu_pick <prompt> <option...>` — prints the chosen option; 1 when cancelled.
  - `menu_check <cache>` — prints one problem per line; 0 when clean.

**Real-Mac risk:** the awk parser is exercised here against GNU awk and the one-true-awk; macOS ships the latter, but only a real Mac proves that `/usr/bin/awk` there handles a hundred-line program with functions and a slurped file the same way. `gum choose` and `fzf` are both driven only through mocks, so the actual key handling and the exit status each returns on Escape are unproved.

- [ ] **Step 1: Write the failing test**

```bash file=tests/lib/menu.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  # Spaces and three characters that are special to awk, sed and the shell, so
  # every path this library builds is exercised against one.
  export TEEUP_CONFIG_DIR="$TEST_HOME/con fig \$x & 'q'/teeup"
  mkdir -p "$TEEUP_CONFIG_DIR"
  export TEEUP_MENU_FILE="$TEST_HOME/men u \$x & 'q'/menu.json"
  mkdir -p "$(dirname "$TEEUP_MENU_FILE")"
  # gum and fzf both paint on /dev/tty, so the switch that makes prompts
  # deterministic has to turn off both.
  export TEEUP_NO_GUM=1
  source "$TEEUP_PATH/lib/all.sh"
}

write_shipped() {
  cat > "$TEEUP_MENU_FILE"
}

write_user() {
  cat > "$(menu_user_file)"
}

sample_menu() {
  write_shipped <<'EOF2'
{
  "install": {"icon": "+", "label": "Install", "title": "Install something"},
  "install.colima": {"label": "Docker", "when": "teeup has colima", "action": "teeup install colima"},
  "install.tmux": {"label": "tmux", "action": "teeup install tmux"},
  "theme": {"label": "Theme", "action": "teeup theme list"}
}
EOF2
}

test_parse_prints_one_line_per_field_in_file_order() {
  setup
  sample_menu
  local out
  out="$(menu_parse "$TEEUP_MENU_FILE")"
  assert_equals "install	icon	+" "$(printf '%s\n' "$out" | head -1)" || return 1
  assert_contains "$out" "install.colima	when	teeup has colima" || return 1
  assert_equals "theme	action	teeup theme list" "$(printf '%s\n' "$out" | tail -1)" || return 1
  cleanup_test_env
}

test_parse_accepts_an_empty_object_and_an_entry_with_no_fields() {
  setup
  write_shipped <<'EOF2'
{ "a": {}, "b": {"label": "B", "action": "true"} }
EOF2
  assert_equals "b	label	B
b	action	true" "$(menu_parse "$TEEUP_MENU_FILE")" || return 1
  write_shipped <<'EOF2'
{}
EOF2
  assert_equals "" "$(menu_parse "$TEEUP_MENU_FILE")" || return 1
  cleanup_test_env
}

test_parse_keeps_escaped_quotes_and_backslashes() {
  setup
  write_shipped <<'EOF2'
{"a": {"label": "say \"hi\" & co\\"}}
EOF2
  assert_equals 'a	label	say "hi" & co\' "$(menu_parse "$TEEUP_MENU_FILE")" || return 1
  cleanup_test_env
}

test_parse_refuses_a_file_that_is_not_one_object_of_objects_of_strings() {
  setup
  local rc out
  write_shipped <<'EOF2'
not json
EOF2
  rc=0; out="$(menu_parse "$TEEUP_MENU_FILE" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "must be one JSON object" || return 1
  write_shipped <<'EOF2'
{"a": {"label": 3}}
EOF2
  rc=0; out="$(menu_parse "$TEEUP_MENU_FILE" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "a.label must be a string" || return 1
  write_shipped <<'EOF2'
{"a": {"label": "one
two"}}
EOF2
  rc=0; out="$(menu_parse "$TEEUP_MENU_FILE" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "one line of text" || return 1
  cleanup_test_env
}

test_entries_are_the_shipped_file_when_there_is_no_user_file() {
  setup
  sample_menu
  assert_equals "$(menu_parse "$TEEUP_MENU_FILE")" "$(menu_entries)" || return 1
  cleanup_test_env
}

test_a_user_entry_replaces_the_shipped_one_whole_and_keeps_its_place() {
  setup
  sample_menu
  write_user <<'EOF2'
{"install.colima": {"label": "Containers"}}
EOF2
  local out
  out="$(menu_entries)"
  assert_contains "$out" "install.colima	label	Containers" || return 1
  assert_not_contains "$out" "install.colima	when" "the user entry replaces the whole row" || return 1
  local cache
  cache="$(menu_cache)"
  assert_equals "install.colima
install.tmux" "$(menu_children "$cache" install)" "the overridden row keeps its position" || return 1
  rm -f "$cache"
  cleanup_test_env
}

test_a_user_only_entry_is_appended() {
  setup
  sample_menu
  write_user <<'EOF2'
{"mine": {"label": "Mine", "action": "echo hello"}}
EOF2
  local cache
  cache="$(menu_cache)"
  assert_equals "install
theme
mine" "$(menu_children "$cache" "")" || return 1
  rm -f "$cache"
  cleanup_test_env
}

test_children_and_fields_and_labels() {
  setup
  sample_menu
  local cache
  cache="$(menu_cache)"
  assert_equals "install
theme" "$(menu_children "$cache" "")" || return 1
  assert_equals "install.colima
install.tmux" "$(menu_children "$cache" install)" || return 1
  assert_equals "" "$(menu_children "$cache" install.tmux)" || return 1
  assert_equals "Install something" "$(menu_field "$cache" install title)" || return 1
  assert_equals "" "$(menu_field "$cache" install nosuch)" || return 1
  assert_equals "+ Install" "$(menu_label "$cache" install)" || return 1
  assert_equals "tmux" "$(menu_label "$cache" install.tmux)" || return 1
  rm -f "$cache"
  cleanup_test_env
}

test_visible_runs_the_when_predicate_through_teeup_has() {
  setup
  sample_menu
  local cache
  cache="$(menu_cache)"
  menu_visible "$cache" install || { echo "a row with no when is always shown"; return 1; }
  menu_visible "$cache" install.colima && { echo "colima is not installed, so the row hides"; return 1; }
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR/colima"
  printf 'summary="c"\ngroup=containers\ntier=lazy\n' > "$TEEUP_CAPS_DIR/colima/capability"
  state_done mark cap-colima
  menu_visible "$cache" install.colima || { echo "an installed colima shows the row"; return 1; }
  rm -f "$cache"
  cleanup_test_env
}

test_picker_resolves_and_rejects_junk() {
  setup
  assert_equals "plain" "$(menu_picker)" "TEEUP_NO_GUM turns off gum and fzf alike" || return 1
  assert_equals "fzf" "$(TEEUP_MENU_PICKER=fzf menu_picker)" || return 1
  assert_equals "gum" "$(TEEUP_MENU_PICKER=gum menu_picker)" || return 1
  local rc=0 out
  out="$(TEEUP_MENU_PICKER=banana menu_picker 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "must be auto, gum, fzf or plain" || return 1
  mock_command fzf 0 ""
  assert_equals "fzf" "$(TEEUP_NO_GUM="" TEEUP_TEST_MISSING=gum menu_picker)" "no gum but an fzf means fzf" || return 1
  cleanup_test_env
}

test_pick_plain_takes_a_number_a_label_or_a_cancel() {
  setup
  assert_equals "Beta" "$(echo 2 | menu_pick "Pick" Alpha Beta 2>/dev/null)" || return 1
  assert_equals "Alpha" "$(echo Alpha | menu_pick "Pick" Alpha Beta 2>/dev/null)" || return 1
  local rc=0
  echo "" | menu_pick "Pick" Alpha Beta >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "an empty line goes back" || return 1
  rc=0
  echo q | menu_pick "Pick" Alpha Beta >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "q goes back" || return 1
  rc=0
  menu_pick "Pick" Alpha Beta </dev/null >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "end of input goes back rather than looping" || return 1
  rc=0
  echo 9 | menu_pick "Pick" Alpha Beta >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "a number out of range is not a choice" || return 1
  cleanup_test_env
}

test_pick_drives_fzf_when_asked_to() {
  setup
  mock_command_script fzf <<'EOF2'
cat > "$HOME/fzf-input"
echo "Beta"
EOF2
  assert_equals "Beta" "$(TEEUP_MENU_PICKER=fzf menu_pick "Pick" Alpha Beta)" || return 1
  assert_equals "Alpha
Beta" "$(cat "$TEST_HOME/fzf-input")" || return 1
  mock_command fzf 130 ""
  local rc=0
  TEEUP_MENU_PICKER=fzf menu_pick "Pick" Alpha Beta >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "escaping out of fzf cancels" || return 1
  cleanup_test_env
}

test_check_flags_the_four_ways_a_menu_file_goes_wrong() {
  setup
  write_shipped <<'EOF2'
{
  "a": {"label": "A", "action": "true"},
  "a.b": {"label": "B", "action": "true"},
  "orphan.child": {"label": "Child", "action": "true"},
  "c": {"label": "C"},
  "d": {"action": "true"},
  "e": {"label": "E"},
  "e.one": {"label": "Same", "action": "true"},
  "e.two": {"label": "Same", "action": "true"}
}
EOF2
  local cache out rc=0
  cache="$(menu_cache)"
  out="$(menu_check "$cache")" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "a has both an action and child rows" || return 1
  assert_contains "$out" "orphan.child has no parent row orphan" || return 1
  assert_contains "$out" "c has neither an action nor child rows" || return 1
  assert_contains "$out" "d has no label" || return 1
  assert_contains "$out" "two rows under e share the label" || return 1
  rm -f "$cache"
  cleanup_test_env
}

test_check_passes_a_well_formed_menu() {
  setup
  sample_menu
  local cache rc=0 out
  cache="$(menu_cache)"
  out="$(menu_check "$cache")" || rc=$?
  assert_success "$rc" "$out" || return 1
  assert_equals "" "$out" || return 1
  rm -f "$cache"
  cleanup_test_env
}

test_entries_refuses_a_broken_user_file_rather_than_half_a_menu() {
  setup
  sample_menu
  write_user <<'EOF2'
{"mine": {"label": }}
EOF2
  local rc=0 out
  out="$(menu_entries 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$(menu_user_file)" || return 1
  assert_not_contains "$out" "install	icon" "a broken user file must not yield half a menu" || return 1
  cleanup_test_env
}

echo "lib/menu.sh"
run_test "parse prints one line per field in file order" test_parse_prints_one_line_per_field_in_file_order
run_test "parse accepts an empty object" test_parse_accepts_an_empty_object_and_an_entry_with_no_fields
run_test "parse keeps escaped quotes and backslashes" test_parse_keeps_escaped_quotes_and_backslashes
run_test "parse refuses a malformed file" test_parse_refuses_a_file_that_is_not_one_object_of_objects_of_strings
run_test "entries are the shipped file with no user file" test_entries_are_the_shipped_file_when_there_is_no_user_file
run_test "a user entry replaces the shipped one whole" test_a_user_entry_replaces_the_shipped_one_whole_and_keeps_its_place
run_test "a user-only entry is appended" test_a_user_only_entry_is_appended
run_test "children, fields and labels" test_children_and_fields_and_labels
run_test "visible runs the when predicate" test_visible_runs_the_when_predicate_through_teeup_has
run_test "picker resolves and rejects junk" test_picker_resolves_and_rejects_junk
run_test "pick plain takes a number, a label or a cancel" test_pick_plain_takes_a_number_a_label_or_a_cancel
run_test "pick drives fzf when asked to" test_pick_drives_fzf_when_asked_to
run_test "check flags a broken menu" test_check_flags_the_four_ways_a_menu_file_goes_wrong
run_test "check passes a well-formed menu" test_check_passes_a_well_formed_menu
run_test "entries refuses a broken user file" test_entries_refuses_a_broken_user_file_rather_than_half_a_menu
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/lib/menu.sh`
Expected: every test fails, because `lib/all.sh` defines none of `menu_parse`, `menu_entries`, `menu_cache`, `menu_children`, `menu_field`, `menu_label`, `menu_visible`, `menu_picker`, `menu_pick` or `menu_check`. The suite ends with `Summary: 0/15 passed`.

- [ ] **Step 3: Write the parser**

```awk file=lib/menu.awk
# menu.awk - read teeup's menu definition and print one tab-separated
# id/field/value line per field, in file order.
#
# The grammar accepted here is deliberately narrower than JSON: the file is
# one object whose keys are dotted menu ids and whose values are objects whose
# values are one-line strings. The menu format is nothing more than that, and
# a parser that accepts only it fits in a hundred lines of awk instead of
# adding a dependency on jq, which macOS does not ship and the test harness's
# narrowed PATH hides.
#
# Errors go to stderr through `cat 1>&2` rather than "/dev/stderr", which not
# every awk implementation opens, and exit 1.

function fail(msg) {
  print "menu: " msg " (" FILENAME ", byte " i ")" | "cat 1>&2"
  close("cat 1>&2")
  exit 1
}

function skipws(   c) {
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == " " || c == "\t" || c == "\n" || c == "\r") { i++ } else { return }
  }
}

function at() { return substr(s, i, 1) }

function readstring(   out, c, e) {
  if (at() != "\"") fail("expected a double-quoted string")
  i++
  out = ""
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\"") { i++; return out }
    # A tab or a newline inside a value would split the output line this
    # parser exists to produce, so both are refused rather than smuggled
    # through. The escapes \n and \t are refused for the same reason.
    if (c == "\n" || c == "\t" || c == "\r") fail("a value is one line of text; use no raw newlines or tabs")
    if (c == "\\") {
      i++
      e = substr(s, i, 1)
      if (e == "\"" || e == "\\" || e == "/") { out = out e }
      else fail("unsupported escape \\" e "; only \\\" \\\\ and \\/ are understood")
      i++
      continue
    }
    out = out c
    i++
  }
  fail("unterminated string")
}

# The whole file is accumulated and then scanned, because the grammar is not
# line-oriented and awk's record splitting would fight it.
{ s = s $0 "\n" }

END {
  n = length(s)
  i = 1
  skipws()
  if (at() != "{") fail("the file must be one JSON object")
  i++
  skipws()
  if (at() == "}") { i++ } else {
    for (;;) {
      skipws(); id = readstring(); skipws()
      if (at() != ":") fail("expected ':' after the id " id)
      i++
      skipws()
      if (at() != "{") fail("the entry " id " must be an object")
      i++
      skipws()
      if (at() == "}") { i++ } else {
        for (;;) {
          skipws(); key = readstring(); skipws()
          if (at() != ":") fail("expected ':' after " id "." key)
          i++
          skipws()
          if (at() != "\"") fail("the field " id "." key " must be a string")
          val = readstring()
          printf "%s\t%s\t%s\n", id, key, val
          skipws()
          if (at() == ",") { i++; continue }
          if (at() == "}") { i++; break }
          fail("expected ',' or '}' inside " id)
        }
      }
      skipws()
      if (at() == ",") { i++; skipws(); if (at() == "}") { i++; break }; continue }
      if (at() == "}") { i++; break }
      fail("expected ',' or '}' after " id)
    }
  }
  skipws()
  if (i <= n) fail("trailing content after the object")
}
```

- [ ] **Step 4: Write `lib/menu.sh`**

```bash file=lib/menu.sh
#!/usr/bin/env bash
# menu.sh - the declarative menu (spec section 2: Omarchy's menu, and section
# 4: share/teeup/menu.json). Ids are dotted, so the tree is in the ids and
# there is no nesting to parse; a row is hidden when its `when` command fails,
# which is Omarchy's "predicates as exit codes"; the user's own menu.json
# overrides a shipped row by id and appends new ones.
# Requires core.sh and ui.sh.

TEEUP_MENU_FILE="${TEEUP_MENU_FILE:-$TEEUP_PATH/share/teeup/menu.json}"
export TEEUP_MENU_FILE

menu_user_file() { printf '%s/menu.json\n' "$TEEUP_CONFIG_DIR"; }

# menu_parse <file> -> "id<TAB>field<TAB>value" per field, in file order
menu_parse() { awk -f "$TEEUP_PATH/lib/menu.awk" "$1"; }

# _menu_merge <shipped-triples> <user-triples>
# An id in both files takes the user's entry whole -- fields are replaced, not
# merged -- and keeps the shipped position; an id only in the user file is
# appended. FILENAME rather than FNR==NR tells the two apart, so an empty
# shipped file cannot make the user file look like the first one.
_menu_merge() {
  awk -F'\t' -v first="$1" '
    FILENAME == first {
      if (!($1 in a)) { a[$1] = ""; aorder[++na] = $1 }
      a[$1] = a[$1] $0 "\n"
      next
    }
    {
      if (!($1 in b)) { b[$1] = ""; border[++nb] = $1 }
      b[$1] = b[$1] $0 "\n"
    }
    END {
      for (k = 1; k <= na; k++) { id = aorder[k]; if (id in b) printf "%s", b[id]; else printf "%s", a[id] }
      for (k = 1; k <= nb; k++) { id = border[k]; if (!(id in a)) printf "%s", b[id] }
    }
  ' "$1" "$2"
}

# menu_entries -> the merged stream. A malformed file on either side is a
# failure with nothing on stdout: half a menu is worse than none, because the
# missing half looks like a row that simply does not exist here.
menu_entries() {
  local shipped user tmp_a tmp_b rc=0
  shipped="$TEEUP_MENU_FILE"
  if [[ ! -f "$shipped" ]]; then
    err "No menu definition at $shipped"
    return 1
  fi
  user="$(menu_user_file)"
  tmp_a="$(mktemp)"
  if ! menu_parse "$shipped" > "$tmp_a"; then
    rm -f "$tmp_a"
    err "Could not read $shipped"
    return 1
  fi
  if [[ ! -f "$user" ]]; then
    cat "$tmp_a"
    rm -f "$tmp_a"
    return 0
  fi
  tmp_b="$(mktemp)"
  if ! menu_parse "$user" > "$tmp_b"; then
    rm -f "$tmp_a" "$tmp_b"
    err "Could not read $user"
    return 1
  fi
  _menu_merge "$tmp_a" "$tmp_b" || rc=$?
  rm -f "$tmp_a" "$tmp_b"
  return $rc
}

# menu_cache -> the path of a temp file holding menu_entries. Every query
# below reads that file, so the two menu files are parsed once per run rather
# than once per lookup. The caller deletes it.
menu_cache() {
  local tmp
  tmp="$(mktemp)"
  if ! menu_entries > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  printf '%s\n' "$tmp"
}

# ids and field names are dotted words and bare words, so neither can carry a
# backslash for awk's -v to interpret.
menu_ids() { awk -F'\t' '!($1 in seen) { seen[$1] = 1; print $1 }' "$1"; }

menu_field() { awk -F'\t' -v id="$2" -v key="$3" '$1 == id && $2 == key { print $3; exit }' "$1"; }

# menu_children <cache> [parent]
# The direct children of <parent> ("" for the top level): an id with exactly
# one more dotted segment, in file order, each once.
menu_children() {
  awk -F'\t' -v parent="$2" '
    {
      id = $1
      if (parent == "") {
        if (index(id, ".") != 0) next
      } else {
        prefix = parent "."
        if (substr(id, 1, length(prefix)) != prefix) next
        rest = substr(id, length(prefix) + 1)
        if (rest == "" || index(rest, ".") != 0) next
      }
      if (!(id in seen)) { seen[id] = 1; print id }
    }
  ' "$1"
}

menu_label() {
  local icon label
  icon="$(menu_field "$1" "$2" icon)"
  label="$(menu_field "$1" "$2" label)"
  if [[ -z "$label" ]]; then label="$2"; fi
  if [[ -n "$icon" ]]; then
    printf '%s %s\n' "$icon" "$label"
  else
    printf '%s\n' "$label"
  fi
}

# menu_visible <cache> <id>
# A row with no `when` is always shown. A `when` is a shell condition run with
# the checkout's bin directory first on PATH, so `teeup has <capability>` --
# the exit-code predicate bin/teeup has carried since phase 1 -- works even
# before ~/.local/bin/teeup exists.
menu_visible() {
  local when
  when="$(menu_field "$1" "$2" when)"
  if [[ -z "$when" ]]; then
    return 0
  fi
  PATH="$TEEUP_PATH/bin:$PATH" bash -c "$when" >/dev/null 2>&1
}

# menu_run <action>
menu_run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would run: $1"
    return 0
  fi
  PATH="$TEEUP_PATH/bin:$PATH" bash -c "$1"
}

# menu_picker -> gum | fzf | plain
# TEEUP_NO_GUM turns off BOTH full-screen pickers, not only gum: each paints
# on /dev/tty, and the one switch tests use to get deterministic, pipe-driven
# prompts has to cover both. A test that wants the fzf branch says so with
# TEEUP_MENU_PICKER=fzf and mocks fzf.
menu_picker() {
  case "${TEEUP_MENU_PICKER:-auto}" in
    gum|fzf|plain)
      printf '%s\n' "$TEEUP_MENU_PICKER"
      return 0
      ;;
    auto) ;;
    *) die "TEEUP_MENU_PICKER must be auto, gum, fzf or plain (got '$TEEUP_MENU_PICKER')" ;;
  esac
  # _ui_gum is lib/ui.sh's own rule for "is gum usable", so the menu and the
  # wizard can never disagree about it.
  if _ui_gum; then
    printf 'gum\n'
  elif [[ -z "${TEEUP_NO_GUM:-}" ]] && have fzf; then
    printf 'fzf\n'
  else
    printf 'plain\n'
  fi
}

# menu_pick <prompt> <option...> -> the chosen option, or 1 when cancelled.
# Cancelling is a first-class answer here, unlike ui_choose's "empty means the
# first option": a menu needs a way back out, and the plain branch has to tell
# end-of-input from an empty line or it would loop for ever under a test.
menu_pick() {
  local prompt="$1"
  shift
  local picker answer i opt
  local n=$#
  picker="$(menu_picker)" || return 1
  case "$picker" in
    gum)
      answer="$(gum choose --header "$prompt" "$@")" || return 1
      ;;
    fzf)
      answer="$(printf '%s\n' "$@" | fzf --prompt "$prompt > " --height 40% --reverse)" || return 1
      ;;
    *)
      printf '%s\n' "$prompt" >&2
      i=1
      for opt in "$@"; do
        printf '  %d) %s\n' "$i" "$opt" >&2
        i=$((i + 1))
      done
      printf 'Choice (empty or q to go back): ' >&2
      IFS= read -r answer || return 1
      case "$answer" in
        ""|q|Q) return 1 ;;
      esac
      if [[ "$answer" =~ ^[0-9]+$ ]] && (( 10#$answer >= 1 && 10#$answer <= n )); then
        i=1
        for opt in "$@"; do
          if (( i == 10#$answer )); then
            printf '%s\n' "$opt"
            return 0
          fi
          i=$((i + 1))
        done
      fi
      for opt in "$@"; do
        if [[ "$opt" == "$answer" ]]; then
          printf '%s\n' "$opt"
          return 0
        fi
      done
      warn "Unknown choice '$answer'"
      return 1
      ;;
  esac
  if [[ -z "$answer" ]]; then
    return 1
  fi
  printf '%s\n' "$answer"
}

_menu_check_siblings() {
  local cache="$1" parent="$2" child dup
  dup="$(for child in $(menu_children "$cache" "$parent"); do menu_label "$cache" "$child"; done | sort | uniq -d)"
  if [[ -n "$dup" ]]; then
    printf 'menu: two rows under %s share the label: %s\n' "${parent:-the top level}" "$dup"
  fi
  return 0
}

_menu_check_body() {
  local cache="$1" id parent ids
  ids="$(menu_ids "$cache")"
  _menu_check_siblings "$cache" ""
  for id in $ids; do
    if [[ -z "$(menu_field "$cache" "$id" label)" ]]; then
      printf 'menu: %s has no label\n' "$id"
    fi
    parent="${id%.*}"
    if [[ "$parent" != "$id" ]] && ! printf '%s\n' "$ids" | grep -qxF "$parent"; then
      printf 'menu: %s has no parent row %s\n' "$id" "$parent"
    fi
    if [[ -n "$(menu_field "$cache" "$id" action)" && -n "$(menu_children "$cache" "$id")" ]]; then
      printf 'menu: %s has both an action and child rows\n' "$id"
    fi
    if [[ -z "$(menu_field "$cache" "$id" action)" && -z "$(menu_children "$cache" "$id")" ]]; then
      printf 'menu: %s has neither an action nor child rows\n' "$id"
    fi
    _menu_check_siblings "$cache" "$id"
  done
  return 0
}

# menu_check <cache> -> one problem per line on stdout; 0 when clean.
# Two siblings with the same label are a real defect: the picker hands back a
# label, which is mapped to an id by position, so the second of two identical
# labels can never be chosen.
menu_check() {
  local out
  out="$(_menu_check_body "$1")"
  if [[ -n "$out" ]]; then
    printf '%s\n' "$out"
    return 1
  fi
  return 0
}
```

- [ ] **Step 5: Source the new library**

```bash edit-old=lib/all.sh
for _teeup_lib in files state answers pkg ui capability macos theme font lazy mise hooks migrations doctor; do
```
```bash edit-new=lib/all.sh
for _teeup_lib in files state answers pkg ui capability macos theme font lazy mise hooks migrations doctor menu; do
```

- [ ] **Step 6: Run the library suite**

Run: `bash tests/lib/menu.sh`
Expected: `Summary: 15/15 passed`.

- [ ] **Step 7: Run every check**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning lib/menu.sh lib/all.sh tests/lib/menu.sh && git diff --check`
Expected: `All N suites passed.` where N is the count printed before this task plus 1 (`tests/lib/menu.sh`); `commands --check` silent and exit 0; shellcheck silent (it is not run on `lib/menu.awk`, which is awk, not shell, and is outside CI's `lib/*.sh` glob); `git diff --check` silent.

- [ ] **Step 8: Commit**

```bash
git add lib/menu.awk lib/menu.sh lib/all.sh tests/lib/menu.sh
git commit -m "Add the menu file parser, merge and picker"
```

---
### Task 6: `share/teeup/menu.json` and the `teeup menu` verb

The shipped menu, and the loop that walks it. Rows are hidden by `when` predicates that call `teeup has`, so an installed capability drops off the Install list by itself, and the three phase-4a verbs appear the moment that phase lands without this file needing an edit.

This task also gives `teeup theme set` a no-argument form that opens the picker, so a single menu row can offer every theme, including the ones phase 4d adds.

**Files:**
- Create: `share/teeup/menu.json`
- Modify: `bin/teeup`
- Modify: `tests/cli.sh`

**Interfaces:**
- Consumes: `menu_cache menu_ids menu_children menu_field menu_label menu_visible menu_run menu_pick` (Task 5); `theme_list theme_dir theme_set theme_current` (`lib/theme.sh`); `answers_set machine_get machine_file` (`lib/answers.sh`).
- Produces:
  - `cmd_menu [<route>]` in `bin/teeup`, reached as `teeup menu`.
  - `_menu_parent <id>` — the id with its last dotted segment removed, or nothing at the top level.
  - `_menu_loop <cache> <route>` — the walk itself.
  - `teeup theme set` with no name now opens the picker instead of failing.

**Real-Mac risk:** the loop is only ever driven here through the plain numbered picker; how `gum choose` behaves when its option list is longer than the terminal, and whether Escape out of it really returns non-zero rather than an empty line, are only settled on a real terminal.

- [ ] **Step 1: Write the failing test**

```bash edit-old=tests/cli.sh
echo "bin/teeup"
```
```bash edit-new=tests/cli.sh
# A menu of the fixture capabilities, so these tests never depend on what
# share/teeup/menu.json happens to contain.
write_test_menu() {
  export TEEUP_MENU_FILE="$TEST_HOME/menu.json"
  cat > "$TEEUP_MENU_FILE" <<'EOF2'
{
  "install": {"icon": "+", "label": "Install", "title": "Install something"},
  "install.alpha": {"label": "Alpha", "when": "! teeup has alpha", "action": "teeup install alpha"},
  "install.beta": {"label": "Beta", "action": "teeup install beta"},
  "status": {"label": "Status", "action": "teeup status"}
}
EOF2
}

test_menu_walks_into_a_submenu_and_runs_the_action() {
  setup
  write_test_menu
  local out
  out="$(printf '1\n1\n' | "$TEEUP" menu 2>&1)"
  assert_contains "$out" "1) + Install" || return 1
  assert_contains "$out" "install:alpha" || return 1
  "$TEEUP" has alpha || { echo "the action should really have installed alpha"; return 1; }
  cleanup_test_env
}

test_menu_hides_a_row_whose_when_predicate_fails() {
  setup
  write_test_menu
  "$TEEUP" install alpha >/dev/null
  local out
  out="$(printf '1\n\n' | "$TEEUP" menu 2>&1)"
  assert_contains "$out" "Beta" || return 1
  assert_not_contains "$out" "Alpha" "an installed alpha drops off the list" || return 1
  cleanup_test_env
}

test_menu_takes_a_route_and_offers_a_way_back() {
  setup
  write_test_menu
  local out
  out="$(printf '3\n\n' | "$TEEUP" menu install 2>&1)"
  assert_contains "$out" "Install something" || return 1
  assert_contains "$out" "3) .." || return 1
  assert_contains "$out" "1) + Install" "going back lands at the top level" || return 1
  cleanup_test_env
}

test_menu_rejects_an_unknown_route() {
  setup
  write_test_menu
  local rc=0 out
  out="$("$TEEUP" menu nosuch 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "No menu row with the id 'nosuch'" || return 1
  cleanup_test_env
}

test_menu_dry_run_prints_the_action_instead_of_running_it() {
  setup
  write_test_menu
  local out
  out="$(printf '1\n1\n' | DRY_RUN=true "$TEEUP" menu 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would run: teeup install alpha" || return 1
  "$TEEUP" has alpha && { echo "a dry run must install nothing"; return 1; }
  cleanup_test_env
}

test_theme_set_without_a_name_opens_the_picker() {
  setup
  # Two complete palettes, copied from the one theme the repo ships, so the
  # render really succeeds; theme_list sorts, so the second is choice 2.
  export TEEUP_THEMES_DIR="$TEST_HOME/themes"
  mkdir -p "$TEEUP_THEMES_DIR"
  cp -R "$TEEUP_PATH/themes/catppuccin" "$TEEUP_THEMES_DIR/aaa-first"
  cp -R "$TEEUP_PATH/themes/catppuccin" "$TEEUP_THEMES_DIR/zzz-second"
  local out
  out="$(printf '2\n' | "$TEEUP" theme set 2>&1)"
  assert_contains "$out" "2) zzz-second" || return 1
  assert_equals "zzz-second" "$("$TEEUP" theme current)" || return 1
  local rc=0
  out="$(printf '\n' | "$TEEUP" theme set 2>&1)" || rc=$?
  assert_success "$rc" "backing out of the picker is not an error" || return 1
  assert_contains "$out" "Keeping the current theme" || return 1
  assert_equals "zzz-second" "$("$TEEUP" theme current)" "backing out changes nothing" || return 1
  cleanup_test_env
}

echo "bin/teeup"
```

```bash edit-old=tests/cli.sh
run_test "doctor rejects an unknown capability" test_doctor_rejects_an_unknown_capability
```
```bash edit-new=tests/cli.sh
run_test "doctor rejects an unknown capability" test_doctor_rejects_an_unknown_capability
run_test "menu walks into a submenu and runs the action" test_menu_walks_into_a_submenu_and_runs_the_action
run_test "menu hides a row whose when fails" test_menu_hides_a_row_whose_when_predicate_fails
run_test "menu takes a route and offers a way back" test_menu_takes_a_route_and_offers_a_way_back
run_test "menu rejects an unknown route" test_menu_rejects_an_unknown_route
run_test "menu dry run prints the action" test_menu_dry_run_prints_the_action_instead_of_running_it
run_test "theme set without a name opens the picker" test_theme_set_without_a_name_opens_the_picker
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/cli.sh`
Expected: the six new tests fail, five with `Unknown verb: menu` and one with `Usage: teeup theme set <name>`; the suite ends with `Summary: 32/38 passed`.

- [ ] **Step 3: Add the verb to `bin/teeup`**

The usage line, above the doctor line Task 1 added:

```bash edit-old=bin/teeup
  teeup doctor [<capability>]    check what is installed, and say how to fix what is not
```
```bash edit-new=bin/teeup
  teeup menu [<id>]              every teeup action as a keyboard-driven list
  teeup doctor [<capability>]    check what is installed, and say how to fix what is not
```

The functions, above `cmd_doctor`:

```bash edit-old=bin/teeup
# teeup doctor [<capability>]
```
```bash edit-new=bin/teeup
# _menu_parent <id> -> the id with its last dotted segment removed, or
# nothing at the top level.
_menu_parent() {
  local id="$1" parent
  parent="${id%.*}"
  if [[ "$parent" != "$id" ]]; then
    printf '%s\n' "$parent"
  fi
}

# _menu_loop <cache> <route>
# Iterative, not recursive: bash 3.2 has no tail calls and a menu is a walk,
# not a stack. Arrays are indexed by hand throughout, and "${labels[@]}" is
# only ever expanded after the count has been checked, because bash 3.2 under
# `set -u` treats the expansion of an EMPTY array as an unbound variable.
_menu_loop() {
  local cache="$1" current="$2" id chosen action title i
  local rows labels
  if [[ -n "$current" ]] && ! menu_ids "$cache" | grep -qxF "$current"; then
    err "No menu row with the id '$current'."
    return 1
  fi
  while :; do
    rows=()
    labels=()
    for id in $(menu_children "$cache" "$current"); do
      if menu_visible "$cache" "$id"; then
        rows[${#rows[@]}]="$id"
        labels[${#labels[@]}]="$(menu_label "$cache" "$id")"
      fi
    done
    if [[ ${#rows[@]} -eq 0 ]]; then
      if [[ -z "$current" ]]; then
        err "Every row in the menu is hidden by its own 'when' condition."
        return 1
      fi
      warn "Nothing left to show under $current."
      current="$(_menu_parent "$current")"
      continue
    fi
    if [[ -n "$current" ]]; then
      rows[${#rows[@]}]=".."
      labels[${#labels[@]}]=".."
    fi
    title="$(menu_field "$cache" "$current" title)"
    if [[ -z "$title" ]]; then
      if [[ -n "$current" ]]; then
        title="$(menu_label "$cache" "$current")"
      else
        title="teeup"
      fi
    fi
    # Cancelling is how you leave: Escape in gum or fzf, an empty line or q in
    # the plain list. Leaving a menu is not a failure.
    chosen="$(menu_pick "$title" "${labels[@]}")" || return 0
    id=""
    i=0
    while [[ $i -lt ${#labels[@]} ]]; do
      if [[ "${labels[$i]}" == "$chosen" ]]; then
        id="${rows[$i]}"
        break
      fi
      i=$((i + 1))
    done
    if [[ -z "$id" ]]; then
      warn "Unknown choice: $chosen"
      continue
    fi
    if [[ "$id" == ".." ]]; then
      current="$(_menu_parent "$current")"
      continue
    fi
    action="$(menu_field "$cache" "$id" action)"
    if [[ -n "$action" ]]; then
      menu_run "$action"
      return $?
    fi
    current="$id"
  done
}

# teeup menu [<id>]
# The whole of teeup as a list (spec section 2: Omarchy's menu, translated to
# a TUI). An optional id opens straight at that row, the way `omarchy menu
# summon style.theme` does.
cmd_menu() {
  local route="${1:-}" cache rc=0
  cache="$(menu_cache)" || exit 1
  _menu_loop "$cache" "$route" || rc=$?
  rm -f "$cache"
  return $rc
}

# teeup doctor [<capability>]
```

The dispatch arm, above `doctor)`:

```bash edit-old=bin/teeup
  doctor) cmd_doctor "$@" ;;
```
```bash edit-new=bin/teeup
  menu) cmd_menu "$@" ;;
  doctor) cmd_doctor "$@" ;;
```

- [ ] **Step 4: Let `teeup theme set` open the picker**

A menu row cannot list themes that a later phase has not added yet, so the row runs `teeup theme set` and the CLI does the asking. A name typed on the command line is still strict.

```bash edit-old=bin/teeup
    set)
      [[ -n "${1:-}" ]] || die "Usage: teeup theme set <name>"
```
```bash edit-new=bin/teeup
    set)
      # With no name, ask. This is what the menu's Theme row runs, so the list
      # always covers whatever themes/ holds today. Backing out of the picker
      # leaves the current theme alone and is not an error.
      if [[ -z "${1:-}" ]]; then
        local names name
        names=()
        while IFS= read -r name; do
          names[${#names[@]}]="$name"
        done < <(theme_list)
        # bash 3.2 under `set -u` treats the expansion of an EMPTY array as an
        # unbound variable, so the count is checked before "${names[@]}".
        if [[ ${#names[@]} -eq 0 ]]; then
          die "No themes found. Look in $TEEUP_PATH/themes and $TEEUP_CONFIG_DIR/themes."
        fi
        set -- "$(menu_pick "Theme" "${names[@]}")" || true
        if [[ -z "${1:-}" ]]; then
          log "Keeping the current theme: $(theme_current)"
          return 0
        fi
      fi
```

- [ ] **Step 5: Run the CLI suite**

Run: `bash tests/cli.sh`
Expected: `Summary: 38/38 passed`.

- [ ] **Step 6: Write the shipped menu**

Ids are dotted, so the tree is in the keys. Every Install row carries `"when": "! teeup has <capability>"`, so the list shrinks as the machine fills up — Omarchy's predicate rule, using the `teeup has` verb that has been there since phase 1. The three phase-4a verbs are guarded by a `when` that asks `teeup help` whether the verb exists, so they appear on their own once that phase lands and nothing here needs editing.

```json file=share/teeup/menu.json
{
  "install": {"icon": "󰉉", "label": "Install", "title": "Install a capability"},
  "launch": {"icon": "󰀻", "label": "Launch", "title": "Open an app"},
  "style": {"icon": "󰸌", "label": "Style", "title": "Theme and font"},
  "check": {"icon": "󰓙", "label": "Check", "title": "What is installed, and what is wrong"},
  "setup": {"icon": "", "label": "Setup", "title": "Answers, secrets and machine state"},
  "update": {"icon": "", "label": "Update", "when": "teeup help | grep -q '^  teeup update'", "action": "teeup update"},

  "install.editors": {"label": "Editors"},
  "install.editors.emacs": {"label": "Emacs", "when": "! teeup has emacs", "action": "teeup install emacs"},
  "install.editors.zed": {"label": "Zed", "when": "! teeup has zed", "action": "teeup install zed"},
  "install.editors.neovim": {"label": "Neovim", "when": "! teeup has neovim", "action": "teeup install neovim"},
  "install.editors.vscode": {"label": "Visual Studio Code", "when": "! teeup has vscode", "action": "teeup install vscode"},
  "install.editors.cursor": {"label": "Cursor", "when": "! teeup has cursor", "action": "teeup install cursor"},

  "install.apps": {"label": "Apps"},
  "install.apps.firefox": {"label": "Firefox Developer Edition", "when": "! teeup has firefox-developer-edition", "action": "teeup install firefox-developer-edition"},
  "install.apps.chrome": {"label": "Google Chrome", "when": "! teeup has chrome", "action": "teeup install chrome"},
  "install.apps.obsidian": {"label": "Obsidian", "when": "! teeup has obsidian", "action": "teeup install obsidian"},

  "install.ai": {"label": "AI"},
  "install.ai.clis": {"label": "AI command-line tools", "when": "! teeup has ai", "action": "teeup install ai"},
  "install.ai.ollama": {"label": "Ollama", "when": "! teeup has ollama", "action": "teeup install ollama"},
  "install.ai.herdr": {"label": "Herdr", "when": "! teeup has herdr", "action": "teeup install herdr"},

  "install.shell": {"label": "Shell and containers"},
  "install.shell.tmux": {"label": "tmux", "when": "! teeup has tmux", "action": "teeup install tmux"},
  "install.shell.colima": {"label": "Docker through Colima", "when": "! teeup has colima", "action": "teeup install colima"},

  "install.dev-env": {"label": "Language runtimes", "title": "Install a runtime through mise"},
  "install.dev-env.python": {"label": "Python", "action": "teeup install dev-env python"},
  "install.dev-env.node": {"label": "Node", "action": "teeup install dev-env node"},
  "install.dev-env.java": {"label": "Java", "action": "teeup install dev-env java"},
  "install.dev-env.ruby": {"label": "Ruby", "action": "teeup install dev-env ruby"},
  "install.dev-env.rust": {"label": "Rust", "action": "teeup install dev-env rust"},
  "install.dev-env.go": {"label": "Go", "action": "teeup install dev-env go"},

  "launch.wezterm": {"label": "WezTerm", "action": "teeup launch WezTerm"},
  "launch.emacs": {"label": "Emacs", "when": "teeup has emacs", "action": "teeup launch Emacs"},
  "launch.zed": {"label": "Zed", "when": "teeup has zed", "action": "teeup launch Zed"},
  "launch.vscode": {"label": "Visual Studio Code", "when": "teeup has vscode", "action": "teeup launch Visual Studio Code"},
  "launch.cursor": {"label": "Cursor", "when": "teeup has cursor", "action": "teeup launch Cursor"},
  "launch.firefox": {"label": "Firefox Developer Edition", "when": "teeup has firefox-developer-edition", "action": "teeup launch Firefox Developer Edition"},
  "launch.chrome": {"label": "Google Chrome", "when": "teeup has chrome", "action": "teeup launch Google Chrome"},
  "launch.obsidian": {"label": "Obsidian", "when": "teeup has obsidian", "action": "teeup launch Obsidian"},
  "launch.ollama": {"label": "Ollama", "when": "teeup has ollama", "action": "teeup launch Ollama"},
  "launch.aerospace": {"label": "AeroSpace", "action": "teeup launch AeroSpace"},

  "style.theme": {"label": "Theme", "action": "teeup theme set"},
  "style.current": {"label": "Current theme", "action": "teeup theme current"},
  "style.fonts": {"label": "Fonts teeup knows", "action": "teeup install font list"},

  "check.doctor": {"label": "Doctor", "action": "teeup doctor"},
  "check.status": {"label": "Status", "action": "teeup status"},
  "check.list": {"label": "Every capability", "action": "teeup list"},
  "check.lint": {"label": "Lint the capability metadata", "action": "teeup commands --check && echo 'Metadata is clean.'"},

  "setup.config": {"label": "Edit the answers", "action": "teeup config edit"},
  "setup.answers": {"label": "Show the answers", "action": "teeup config get"},
  "setup.reset": {"label": "Reset a capability's config", "when": "teeup help | grep -q '^  teeup reset'", "action": "teeup reset $(teeup list | awk '{print $1}' | head -1)"}
}
```

- [ ] **Step 7: Check the shipped menu against its own lint**

Run: `bash -c 'source lib/all.sh; c="$(menu_cache)"; menu_check "$c"; rc=$?; rm -f "$c"; exit $rc'`
Expected: no output, exit 0. Every id has a label, every dotted id has a declared parent, every row is either a leaf with an action or a submenu with children, and no two siblings share a label.

- [ ] **Step 8: Run every check**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning bin/teeup tests/cli.sh && git diff --check`
Expected: `All N suites passed.` with N unchanged from the previous task; `commands --check` silent and exit 0; shellcheck silent; `git diff --check` silent.

- [ ] **Step 9: Commit**

```bash
git add share/teeup/menu.json bin/teeup tests/cli.sh
git commit -m "Add teeup menu and the shipped menu definition"
```

---
### Task 7: `teeup config get|set|edit`

The answers file is the profile (spec section 7), and until now the only ways to change it were the bootstrap wizard and a text editor. The point of this verb is not convenience: it is that precedence is visible. `machines/<hostname>.conf` is sourced after the answers file and wins, so a `teeup config set` of a pinned key writes a line that changes nothing — and says so at the moment of the write, rather than leaving the user to work it out later.

**Files:**
- Modify: `bin/teeup`
- Modify: `tests/cli.sh`

**Interfaces:**
- Consumes: `answers_file answers_exist answers_get answers_set machine_file machine_get` (`lib/answers.sh`); `run_cmd ok warn die log` (`lib/core.sh`).
- Produces:
  - `cmd_config get [<KEY>] | set <KEY> <value> | edit` in `bin/teeup`, reached as `teeup config`.
  - `_config_keys` — every `TEEUP_*` key named by either file, sorted, once each.

**Real-Mac risk:** `edit` hands the file to `$VISUAL`/`$EDITOR` through `bash -c`, so an editor that needs a controlling terminal (`emacsclient -t`, `vi`) is only proved in a real terminal; the mocked suite proves the rollback, the mode and the argument passing.

- [ ] **Step 1: Write the failing test**

```bash edit-old=tests/cli.sh
echo "bin/teeup"
```
```bash edit-new=tests/cli.sh
seed_config_answers() {
  mkdir -p "$TEST_HOME/.config/teeup"
  {
    printf 'TEEUP_EMAIL="ada@example.com"\n'
    printf 'TEEUP_NAME="Ada Lovelace"\n'
    printf 'TEEUP_THEME="catppuccin"\n'
  } > "$TEST_HOME/.config/teeup/answers"
}

pin_machine() {
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR"
  printf '%s\n' "$1" > "$TEEUP_MACHINES_DIR/testmac.conf"
}

test_config_get_lists_every_key_and_marks_the_pinned_ones() {
  setup
  seed_config_answers
  pin_machine 'TEEUP_THEME="nord"'
  local out
  out="$("$TEEUP" config get)"
  assert_contains "$out" "TEEUP_NAME" || return 1
  assert_contains "$out" "Ada Lovelace" || return 1
  assert_contains "$out" "[pinned by testmac.conf]" || return 1
  cleanup_test_env
}

test_config_get_prints_the_effective_value() {
  setup
  seed_config_answers
  assert_equals "catppuccin" "$("$TEEUP" config get TEEUP_THEME)" || return 1
  pin_machine 'TEEUP_THEME="nord"'
  assert_equals "nord" "$("$TEEUP" config get TEEUP_THEME)" "the machine file wins" || return 1
  local rc=0 out
  out="$("$TEEUP" config get TEEUP_NOPE 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "No answer named TEEUP_NOPE" || return 1
  cleanup_test_env
}

test_config_set_writes_the_answers_file() {
  setup
  seed_config_answers
  "$TEEUP" config set TEEUP_NAME Grace Hopper >/dev/null
  assert_equals "Grace Hopper" "$("$TEEUP" config get TEEUP_NAME)" || return 1
  assert_contains "$(cat "$TEST_HOME/.config/teeup/answers")" 'TEEUP_NAME="Grace Hopper"' || return 1
  cleanup_test_env
}

test_config_set_says_when_the_machine_file_makes_the_write_pointless() {
  setup
  seed_config_answers
  pin_machine 'TEEUP_THEME="nord"'
  local out
  out="$("$TEEUP" config set TEEUP_THEME catppuccin 2>&1)"
  assert_contains "$out" "pins TEEUP_THEME=nord" || return 1
  assert_contains "$out" "will have no effect" || return 1
  assert_contains "$(cat "$TEST_HOME/.config/teeup/answers")" 'TEEUP_THEME="catppuccin"' "the answers file is still written" || return 1
  assert_equals "nord" "$("$TEEUP" config get TEEUP_THEME)" "and the pin still wins" || return 1
  cleanup_test_env
}

test_config_set_rejects_a_key_that_is_not_an_answer() {
  setup
  seed_config_answers
  local rc=0 out
  out="$("$TEEUP" config set PATH /tmp 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "must look like TEEUP_NAME" || return 1
  cleanup_test_env
}

test_config_edit_runs_the_editor_and_keeps_a_good_edit() {
  setup
  seed_config_answers
  mock_command_script fakeed <<'EOF2'
printf 'TEEUP_EMAIL="grace@example.com"\n' >> "$1"
EOF2
  VISUAL=fakeed "$TEEUP" config edit >/dev/null
  assert_equals "grace@example.com" "$("$TEEUP" config get TEEUP_EMAIL)" || return 1
  local mode
  mode="$(stat -c '%a' "$TEST_HOME/.config/teeup/answers" 2>/dev/null || stat -f '%Lp' "$TEST_HOME/.config/teeup/answers")"
  assert_equals "600" "$mode" || return 1
  cleanup_test_env
}

test_config_edit_rolls_back_an_edit_that_will_not_parse() {
  setup
  seed_config_answers
  mock_command_script fakeed <<'EOF2'
printf 'TEEUP_NAME="unterminated\n' >> "$1"
EOF2
  local rc=0 out
  # VISUAL is emptied, not merely unset: it is a real variable in a real
  # developer's environment and would otherwise win over EDITOR here.
  out="$(VISUAL="" EDITOR=fakeed "$TEEUP" config edit 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "rolled back" || return 1
  assert_equals "Ada Lovelace" "$("$TEEUP" config get TEEUP_NAME)" || return 1
  cleanup_test_env
}

test_config_edit_passes_flags_in_the_editor_variable() {
  setup
  seed_config_answers
  mock_command_script fakeed <<'EOF2'
printf '%s\n' "$*" > "$HOME/editor-args"
EOF2
  VISUAL="fakeed --wait" "$TEEUP" config edit >/dev/null
  assert_equals "--wait $TEST_HOME/.config/teeup/answers" "$(cat "$TEST_HOME/editor-args")" || return 1
  cleanup_test_env
}

echo "bin/teeup"
```

```bash edit-old=tests/cli.sh
run_test "theme set without a name opens the picker" test_theme_set_without_a_name_opens_the_picker
```
```bash edit-new=tests/cli.sh
run_test "theme set without a name opens the picker" test_theme_set_without_a_name_opens_the_picker
run_test "config get lists every key and marks pins" test_config_get_lists_every_key_and_marks_the_pinned_ones
run_test "config get prints the effective value" test_config_get_prints_the_effective_value
run_test "config set writes the answers file" test_config_set_writes_the_answers_file
run_test "config set says when a pin makes it pointless" test_config_set_says_when_the_machine_file_makes_the_write_pointless
run_test "config set rejects a non-answer key" test_config_set_rejects_a_key_that_is_not_an_answer
run_test "config edit keeps a good edit" test_config_edit_runs_the_editor_and_keeps_a_good_edit
run_test "config edit rolls back a broken edit" test_config_edit_rolls_back_an_edit_that_will_not_parse
run_test "config edit passes flags in EDITOR" test_config_edit_passes_flags_in_the_editor_variable
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/cli.sh`
Expected: the eight new tests fail with `Unknown verb: config`; the suite ends with `Summary: 38/46 passed`.

- [ ] **Step 3: Add the verb to `bin/teeup`**

The usage line, after the doctor line:

```bash edit-old=bin/teeup
  teeup doctor [<capability>]    check what is installed, and say how to fix what is not
```
```bash edit-new=bin/teeup
  teeup doctor [<capability>]    check what is installed, and say how to fix what is not
  teeup config get|set|edit      read or change the answers file
```

The functions, above `cmd_menu`:

```bash edit-old=bin/teeup
# _menu_parent <id> -> the id with its last dotted segment removed, or
```
```bash edit-new=bin/teeup
# _config_keys -> every TEEUP_* key either file names, sorted, once each.
# The machine file is included, so a key that exists only as a pin is still
# listed rather than being invisible until something breaks.
_config_keys() {
  {
    if [[ -f "$(answers_file)" ]]; then
      sed -n 's/^\(TEEUP_[A-Z0-9_]*\)=.*/\1/p' "$(answers_file)"
    fi
    if [[ -f "$(machine_file)" ]]; then
      sed -n 's/^\(TEEUP_[A-Z0-9_]*\)=.*/\1/p' "$(machine_file)"
    fi
  } | sort -u
}

# teeup config get [<KEY>] | set <KEY> <value> | edit
# Over the answers file only (spec section 7). answers_load has already
# layered machines/<hostname>.conf on top, so `get` prints what the rest of
# teeup will actually see. `set` writes the answers file and never the machine
# file -- and says so when the machine file is about to make the write
# pointless, because that is the one thing about this precedence that is
# impossible to notice on your own.
cmd_config() {
  local op="${1:-}" key value f pinned editor backup parse_error
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$op" in
    get)
      key="${1:-}"
      if [[ -n "$key" ]]; then
        if [[ -z "${!key+x}" ]]; then
          die "No answer named $key. List what there is with: teeup config get"
        fi
        printf '%s\n' "${!key}"
        return 0
      fi
      f="$(answers_file)"
      if answers_exist; then
        echo "Answers: $f"
      else
        echo "Answers: $f (the wizard has not run here; ./bootstrap writes it)"
      fi
      if [[ -f "$(machine_file)" ]]; then
        echo "Machine: $(machine_file)  (sourced last, so it wins)"
      fi
      for key in $(_config_keys); do
        if machine_get "$key" >/dev/null; then
          printf '  %-26s %s   [pinned by %s]\n' "$key" "${!key:-}" "$(basename "$(machine_file)")"
        else
          printf '  %-26s %s\n' "$key" "${!key:-}"
        fi
      done
      ;;
    set)
      if [[ $# -lt 2 ]]; then
        die "Usage: teeup config set <KEY> <value>"
      fi
      key="$1"
      shift
      # Joined, so `teeup config set TEEUP_NAME Ada Lovelace` needs no quotes.
      value="$*"
      if pinned="$(machine_get "$key")"; then
        if [[ "$pinned" != "$value" ]]; then
          warn "$(machine_file) pins $key=${pinned:-<empty>}, which is sourced after the answers file, so this write will have no effect until that line changes."
        fi
      fi
      # answers_set validates the key shape and refuses a newline in the value.
      answers_set "$key" "$value"
      ok "Set $key in $(answers_file)"
      ;;
    edit)
      f="$(answers_file)"
      editor="${VISUAL:-${EDITOR:-vi}}"
      if [[ ! -f "$f" ]]; then
        mkdir -p "$(dirname "$f")"
        : > "$f"
        chmod 600 "$f"
      fi
      backup="$(mktemp)"
      cp "$f" "$backup"
      # Run through `bash -c` with the path as $1, so an EDITOR that carries
      # flags ("code -w", "emacsclient -t") works and a path with spaces or
      # metacharacters in it is still one argument.
      if ! run_cmd bash -c "$editor \"\$1\"" bash "$f"; then
        rm -f "$backup"
        die "$editor did not finish; $f is unchanged."
      fi
      if [[ "$DRY_RUN" == "true" ]]; then
        rm -f "$backup"
        return 0
      fi
      # teeup sources this file at the start of every command, so a syntax
      # error in it breaks every verb including the one that would fix it.
      if bash -n "$f" 2>/dev/null; then
        chmod 600 "$f"
        rm -f "$backup"
        ok "Saved $f"
      else
        # Keep the broken text just long enough to quote bash's complaint
        # about it; the file itself goes back to what it was first.
        cp "$f" "$backup.broken"
        cp "$backup" "$f"
        parse_error="$(bash -n "$backup.broken" 2>&1 || true)"
        rm -f "$backup" "$backup.broken"
        die "The edited $f would not parse as shell, so your edit was rolled back. Every line has to read KEY=\"value\". (bash said: ${parse_error:-nothing})"
      fi
      ;;
    *) die "Usage: teeup config get [<KEY>] | set <KEY> <value> | edit" ;;
  esac
}

# _menu_parent <id> -> the id with its last dotted segment removed, or
```

The dispatch arm, after `doctor)`:

```bash edit-old=bin/teeup
  doctor) cmd_doctor "$@" ;;
```
```bash edit-new=bin/teeup
  doctor) cmd_doctor "$@" ;;
  config) cmd_config "$@" ;;
```

- [ ] **Step 4: Run the CLI suite**

Run: `bash tests/cli.sh`
Expected: `Summary: 46/46 passed`.

- [ ] **Step 5: Run every check**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning bin/teeup tests/cli.sh && git diff --check`
Expected: `All N suites passed.` with N unchanged from the previous task; `commands --check` silent and exit 0; shellcheck silent; `git diff --check` silent.

- [ ] **Step 6: Commit**

```bash
git add bin/teeup tests/cli.sh
git commit -m "Add teeup config get, set and edit over the answers file"
```

---
### Task 8: `teeup dev new-capability <name>`

Spec section 12 step 1: "`teeup dev new-capability <name>` scaffolds `capabilities/<name>/{capability,install,configure}` with templates and a test file." The scaffold is shipped as real files under `share/teeup/skeleton/`, with `@NAME@` as the only token, so they are greppable and shellcheck lints them like any other script.

The scaffold uses `tier=lazy` deliberately: a `core` or `daily` capability that is not in its tier list makes `teeup commands --check` fail, so a scaffold with either tier would leave the checkout broken the moment it was created. The printed next steps say what to change for the other tiers.

**This task extends `cmd_dev`, which phase 4a Task 4 creates.** Step 4 adds one case arm and one usage line to that function; it does not define a second one. Nothing else in this plan depends on phase 4a.

**Files:**
- Create: `lib/dev.sh`, `share/teeup/skeleton/capability`, `share/teeup/skeleton/install`, `share/teeup/skeleton/configure`, `share/teeup/skeleton/test.sh`, `tests/lib/dev.sh`
- Modify: `lib/all.sh`, `bin/teeup`, `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `err ok log die run_cmd` (`lib/core.sh`); `write_managed_file replace_literal` (`lib/files.sh`); `cap_dir cap_exists` (`lib/capability.sh`).
- Produces:
  - `TEEUP_SKELETON_DIR` — default `$TEEUP_PATH/share/teeup/skeleton`; a test hook.
  - `TEEUP_TESTS_DIR` — default `$TEEUP_PATH/tests`; a test hook, so a test can scaffold somewhere harmless.
  - `dev_new_capability <name>` — scaffolds the four files; 1 with a message for a bad or taken name.
  - `_dev_render <src> <dest> <name>` — copies one skeleton file with `@NAME@` replaced.
  - `cmd_dev new-capability <name>` in `bin/teeup`.

**Real-Mac risk:** none beyond the rest — this writes files into the checkout and runs no external tool. What only a real use proves is whether the scaffolded `install` and `configure` are the right starting point for the next capability somebody actually writes.

- [ ] **Step 1: Write the failing test**

```bash file=tests/lib/dev.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  # A caps directory with a space and three characters that are special to
  # sed, awk and the shell, so the scaffold is exercised against one.
  export TEEUP_CAPS_DIR="$TEST_HOME/ca ps \$x & 'q'"
  export TEEUP_TESTS_DIR="$TEST_HOME/te sts \$x & 'q'"
  mkdir -p "$TEEUP_CAPS_DIR" "$TEEUP_TESTS_DIR/capabilities"
  export TEEUP_NO_GUM=1
  source "$TEEUP_PATH/lib/all.sh"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_new_capability_writes_the_four_files() {
  setup
  dev_new_capability widget >/dev/null
  assert_file_exists "$TEEUP_CAPS_DIR/widget/capability" || return 1
  assert_file_exists "$TEEUP_CAPS_DIR/widget/install" || return 1
  assert_file_exists "$TEEUP_CAPS_DIR/widget/configure" || return 1
  assert_file_exists "$TEEUP_TESTS_DIR/capabilities/widget.sh" || return 1
  [[ -x "$TEEUP_CAPS_DIR/widget/install" ]] || { echo "install must be executable"; return 1; }
  [[ -x "$TEEUP_CAPS_DIR/widget/configure" ]] || { echo "configure must be executable"; return 1; }
  cleanup_test_env
}

test_new_capability_replaces_every_token() {
  setup
  dev_new_capability widget >/dev/null
  local body
  body="$(cat "$TEEUP_CAPS_DIR"/widget/capability "$TEEUP_CAPS_DIR"/widget/install "$TEEUP_CAPS_DIR"/widget/configure "$TEEUP_TESTS_DIR"/capabilities/widget.sh)"
  assert_not_contains "$body" "@NAME@" "no token may survive the scaffold" || return 1
  assert_contains "$body" 'packages="widget"' || return 1
  assert_contains "$body" 'tier=lazy' "a scaffold must not break teeup commands --check" || return 1
  cleanup_test_env
}

test_the_scaffolded_files_are_valid_shell() {
  setup
  dev_new_capability widget >/dev/null
  local f
  for f in "$TEEUP_CAPS_DIR/widget/capability" "$TEEUP_CAPS_DIR/widget/install" \
           "$TEEUP_CAPS_DIR/widget/configure" "$TEEUP_TESTS_DIR/capabilities/widget.sh"; do
    bash -n "$f" || { echo "$f does not parse"; return 1; }
  done
  cleanup_test_env
}

test_the_scaffolded_metadata_passes_the_lint() {
  setup
  dev_new_capability widget >/dev/null
  # The scaffold's requires= names package-manager, which every capability
  # needs; a stub stands in for it inside this throwaway caps directory.
  mkdir -p "$TEEUP_CAPS_DIR/package-manager"
  printf 'summary="Stub"\ngroup=system\ntier=lazy\nrequires=""\nprovides=""\ninteractive=false\n' \
    > "$TEEUP_CAPS_DIR/package-manager/capability"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/package-manager/install"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/package-manager/configure"
  chmod +x "$TEEUP_CAPS_DIR/package-manager/install" "$TEEUP_CAPS_DIR/package-manager/configure"
  # cap_check also wants the tier lists to exist and to name nothing unknown.
  : > "$TEEUP_CAPS_DIR/core.list"
  : > "$TEEUP_CAPS_DIR/daily.list"
  cap_check || { echo "a fresh scaffold must lint clean"; return 1; }
  cleanup_test_env
}

test_new_capability_refuses_a_bad_or_taken_name() {
  setup
  local rc=0 out
  out="$(dev_new_capability "Widget" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "lower-case letters, digits and dashes" || return 1
  rc=0
  out="$(dev_new_capability "" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Usage: teeup dev new-capability" || return 1
  dev_new_capability widget >/dev/null
  rc=0
  out="$(dev_new_capability widget 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "already exists" || return 1
  cleanup_test_env
}

test_new_capability_writes_nothing_in_a_dry_run() {
  setup
  DRY_RUN=true dev_new_capability widget >/dev/null
  [[ ! -e "$TEEUP_CAPS_DIR/widget" ]] || { echo "a dry run must create nothing"; return 1; }
  [[ ! -e "$TEEUP_TESTS_DIR/capabilities/widget.sh" ]] || { echo "a dry run must create no test"; return 1; }
  cleanup_test_env
}

test_the_scaffolded_capability_passes_its_own_generated_suite() {
  setup
  # Scaffolded into the real checkout on purpose: a generated suite finds
  # tests/helper.sh by walking up from where it sits, so it only runs where it
  # is meant to live. Everything is removed before the assertions, so a failed
  # assertion cannot leave files behind.
  unset TEEUP_CAPS_DIR TEEUP_TESTS_DIR
  local name=teeup-scaffold-probe
  local out="" rc=0 lint_rc=0
  "$TEEUP" dev new-capability "$name" >/dev/null 2>&1 || rc=$?
  if [[ $rc -eq 0 ]]; then
    "$TEEUP" commands --check >/dev/null 2>&1 || lint_rc=$?
    out="$(bash "$TEEUP_PATH/tests/capabilities/$name.sh" 2>&1)" || rc=$?
  fi
  rm -rf "$TEEUP_PATH/capabilities/$name" "$TEEUP_PATH/tests/capabilities/$name.sh"
  assert_success "$rc" "the generated suite must pass: $out" || return 1
  assert_success "$lint_rc" "a scaffold must keep teeup commands --check green" || return 1
  assert_contains "$out" "Summary: 2/2 passed" || return 1
  cleanup_test_env
}

echo "lib/dev.sh"
run_test "new-capability writes the four files" test_new_capability_writes_the_four_files
run_test "new-capability replaces every token" test_new_capability_replaces_every_token
run_test "the scaffolded files are valid shell" test_the_scaffolded_files_are_valid_shell
run_test "the scaffolded metadata passes the lint" test_the_scaffolded_metadata_passes_the_lint
run_test "new-capability refuses a bad or taken name" test_new_capability_refuses_a_bad_or_taken_name
run_test "new-capability writes nothing in a dry run" test_new_capability_writes_nothing_in_a_dry_run
run_test "the scaffold passes its own generated suite" test_the_scaffolded_capability_passes_its_own_generated_suite
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/lib/dev.sh`
Expected: every test fails, because `lib/all.sh` defines no `dev_new_capability` and `bin/teeup` has no `dev` verb. The suite ends with `Summary: 0/7 passed`.

- [ ] **Step 3: Write the skeleton and the library**

```bash file=share/teeup/skeleton/capability
summary="@NAME@, described in one line"
group=system
tier=lazy
requires="package-manager"
provides=""
packages="@NAME@"
casks=""
apps=""
interactive=false
```

```bash file=share/teeup/skeleton/install
#!/usr/bin/env bash
# Packages only. Anything that writes a config file, a macOS default or a
# LaunchAgent belongs in `configure`, which runs as its own process so a
# config change never means re-reading an install.
#
# pkg_install <package> [command]: the second argument is the command the
# package provides, and the install is skipped when it is already on PATH.
# For a GUI app use `cask_install <cask>` and set casks= and apps= in the
# metadata instead.
pkg_install @NAME@ @NAME@
```

```bash file=share/teeup/skeleton/configure
#!/usr/bin/env bash
# Configuration only, and idempotent: a second run must report that there was
# nothing to do rather than do it again. Every mutation goes through run_cmd
# or a DRY_RUN-guarded primitive, so `DRY_RUN=true` changes nothing.
#
# The usual shapes, in the order they are usually needed:
#
#   copy_config_once "$TEEUP_CAP_DIR/config/@NAME@/config.toml" \
#     "$(user_config_dir)/@NAME@/config.toml"
#   defaults_write com.example.@NAME@ SomeKey -bool true
#   launchagent_install com.example.@NAME@ <<PLIST
#   ...
#   PLIST
#
log "Nothing to configure yet for @NAME@."
```

```bash file=share/teeup/skeleton/test.sh
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
}

test_install_asks_the_package_manager() {
  setup
  export TEEUP_TEST_MISSING="@NAME@"
  local out
  out="$(DRY_RUN=true cap_run @NAME@ install 2>&1)"
  assert_contains "$out" "Would execute: brew install @NAME@" || return 1
  cleanup_test_env
}

test_configure_writes_nothing_in_a_dry_run() {
  setup
  local before after
  before="$(find "$TEST_HOME" -type f | sort)"
  DRY_RUN=true cap_run @NAME@ configure >/dev/null 2>&1
  after="$(find "$TEST_HOME" -type f | sort)"
  assert_equals "$before" "$after" "a dry run must write nothing" || return 1
  cleanup_test_env
}

echo "capabilities/@NAME@"
run_test "install asks the package manager" test_install_asks_the_package_manager
run_test "configure writes nothing in a dry run" test_configure_writes_nothing_in_a_dry_run
print_summary
```

```bash file=lib/dev.sh
#!/usr/bin/env bash
# dev.sh - the verbs for people changing teeup itself (spec section 12).
# Requires core.sh, files.sh, capability.sh.

TEEUP_SKELETON_DIR="${TEEUP_SKELETON_DIR:-$TEEUP_PATH/share/teeup/skeleton}"
TEEUP_TESTS_DIR="${TEEUP_TESTS_DIR:-$TEEUP_PATH/tests}"
export TEEUP_SKELETON_DIR TEEUP_TESTS_DIR

# _dev_render <src> <dest> <name>
# One skeleton file, with @NAME@ replaced. replace_literal (lib/files.sh)
# rather than sed or ${var//pat/repl}: a capability name is tame, but this is
# the helper that is correct for every name, and write_managed_file carries
# the DRY_RUN guard so a dry run creates nothing.
_dev_render() {
  local src="$1" dest="$2" name="$3" line
  {
    while IFS= read -r line || [[ -n "$line" ]]; do
      replace_literal "$line" '@NAME@' "$name"
    done < "$src"
  } | write_managed_file "$dest" "scaffold for $name"
}

# dev_new_capability <name>
# The tier is lazy on purpose: a core or daily capability that is not listed
# in its tier file makes `teeup commands --check` fail, so either of those
# tiers would leave the checkout broken the moment the scaffold was written.
dev_new_capability() {
  local name="${1:-}" dir f
  if [[ -z "$name" ]]; then
    err "Usage: teeup dev new-capability <name>"
    return 1
  fi
  if ! [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    err "A capability name uses lower-case letters, digits and dashes and starts with a letter or digit (got '$name')."
    return 1
  fi
  if cap_exists "$name"; then
    err "$(cap_dir "$name") already exists."
    return 1
  fi
  dir="$(cap_dir "$name")"
  for f in capability install configure; do
    _dev_render "$TEEUP_SKELETON_DIR/$f" "$dir/$f" "$name"
  done
  _dev_render "$TEEUP_SKELETON_DIR/test.sh" "$TEEUP_TESTS_DIR/capabilities/$name.sh" "$name"
  run_cmd chmod +x "$dir/install" "$dir/configure"
  ok "Scaffolded $dir and $TEEUP_TESTS_DIR/capabilities/$name.sh"
  log "Next (spec section 12):"
  log "  1. Fill in summary, group and the packages or casks in $dir/capability."
  log "  2. For a core or daily capability, change tier= and append $name to"
  log "     $TEEUP_CAPS_DIR/<tier>.list in the same commit, or commands --check fails."
  log "  3. Write install and configure; keep every mutation inside run_cmd."
  log "  4. Add a row to share/teeup/menu.json if it should be in teeup menu."
  log "  5. Add themed/<tool>.tpl inside the capability if the tool has colours."
  log "  6. Run: teeup dev check $name"
  return 0
}
```

- [ ] **Step 4: Add `new-capability` to the `dev` verb group in `bin/teeup`**

Phase 4a Task 4 created `cmd_dev` with a single `add-migration` arm and the `dev) cmd_dev "$@" ;;` dispatch arm that routes to it. This step adds one case arm and one usage line to what is already there; it creates neither a second function nor a second dispatch arm.

The usage line, after phase 4a's `dev` line:

```bash edit-old=bin/teeup
  teeup dev add-migration        start migrations/<epoch>.sh for machines already set up
```
```bash edit-new=bin/teeup
  teeup dev add-migration        start migrations/<epoch>.sh for machines already set up
  teeup dev new-capability <name>  scaffold capabilities/<name> and its test
```

The case arm. Phase 4a wrote the shift as a bare `[[ $# -gt 0 ]] && shift`, which this plan's Global Constraints forbid in `bin/teeup`; it does not abort there because it is not the function's last statement, but while this edit is inside the function, make it the `if` form:

```bash edit-old=bin/teeup
cmd_dev() {
  local op="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$op" in
    add-migration) migration_new ;;
    *) die "Usage: teeup dev add-migration" ;;
  esac
}
```
```bash edit-new=bin/teeup
cmd_dev() {
  local op="${1:-}"
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$op" in
    add-migration) migration_new ;;
    new-capability) dev_new_capability "$@" ;;
    *) die "Usage: teeup dev add-migration | new-capability <name>" ;;
  esac
}
```

`tests/cli.sh` (phase 4a) asserts the failure message contains `Usage: teeup dev add-migration`, which this string still begins with. The `Usage: teeup dev new-capability` that `tests/lib/dev.sh` asserts comes from `dev_new_capability` itself, not from here.

- [ ] **Step 5: Source the new library**

```bash edit-old=lib/all.sh
for _teeup_lib in files state answers pkg ui capability macos theme font lazy mise hooks migrations doctor menu; do
```
```bash edit-new=lib/all.sh
for _teeup_lib in files state answers pkg ui capability macos theme font lazy mise hooks migrations doctor menu dev; do
```

- [ ] **Step 6: Lint the skeleton in CI**

The skeleton files are shipped shell and have to stay clean, but they live under `share/`, which CI's `find capabilities ...` expression does not reach.

```bash edit-old=.github/workflows/ci.yml
            tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh \
```
```bash edit-new=.github/workflows/ci.yml
            share/teeup/skeleton/install share/teeup/skeleton/configure \
            share/teeup/skeleton/test.sh \
            tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh \
```

- [ ] **Step 7: Run the library suite**

Run: `bash tests/lib/dev.sh`
Expected: `Summary: 7/7 passed`.

Then confirm the probe left nothing behind:

Run: `git status --short`
Expected: only the files this task creates and modifies; no `capabilities/teeup-scaffold-probe` and no `tests/capabilities/teeup-scaffold-probe.sh`.

- [ ] **Step 8: Run every check**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning bin/teeup lib/dev.sh share/teeup/skeleton/install share/teeup/skeleton/configure share/teeup/skeleton/test.sh tests/lib/dev.sh && git diff --check`
Expected: `All N suites passed.` where N is the count printed before this task plus 1 (`tests/lib/dev.sh`); `commands --check` silent and exit 0; shellcheck silent; `git diff --check` silent.

- [ ] **Step 9: Commit**

```bash
git add lib/dev.sh lib/all.sh bin/teeup share/teeup/skeleton tests/lib/dev.sh .github/workflows/ci.yml
git commit -m "Add teeup dev new-capability and the shipped capability skeleton"
```

---
### Task 9: `teeup dev check`

Spec section 12 step 7: "Run `teeup dev check` (metadata lint, executable bits, shellcheck, dry-run install and configure under the mock harness)." All four already exist as separate commands; the point of the verb is that one command runs the same set CI runs, so a contributor finds out before pushing rather than after. The menu lint from Task 5 joins them, because `share/teeup/menu.json` is the one shipped file with no other check on it.

With a capability name it runs only that capability's suite, which takes a second; with no name it runs the whole suite, which takes minutes.

**Files:**
- Modify: `lib/dev.sh`
- Modify: `bin/teeup`
- Modify: `tests/lib/dev.sh`

**Interfaces:**
- Consumes: `cap_check` (`lib/capability.sh`); `menu_cache menu_check` (Task 5); `TEEUP_SKELETON_DIR TEEUP_TESTS_DIR` (Task 8); `have ok warn err log` (`lib/core.sh`).
- Produces:
  - `dev_shell_files` — every shell file CI lints, one absolute path per line.
  - `dev_check [<capability>]` — 0 when every check passed, 1 otherwise.
  - `cmd_dev check [<capability>]` in `bin/teeup`.

**Real-Mac risk:** `dev_shell_files` mirrors the argument list in `.github/workflows/ci.yml` by hand, so the two can drift; only a real CI run proves they still agree after somebody adds a file type. The check calls that out rather than pretending otherwise.

- [ ] **Step 1: Write the failing test**

```bash edit-old=tests/lib/dev.sh
echo "lib/dev.sh"
```
```bash edit-new=tests/lib/dev.sh
# A checkout-shaped fixture: a caps directory with one valid capability, a
# tests directory with a stub run.sh, and a menu file. Nothing here touches
# the real suite, which takes minutes.
seed_check_fixture() {
  mkdir -p "$TEEUP_CAPS_DIR/widget" "$TEEUP_TESTS_DIR/capabilities" "$TEEUP_TESTS_DIR/lib"
  printf 'summary="Widget"\ngroup=system\ntier=lazy\nrequires=""\nprovides=""\ninteractive=false\n' \
    > "$TEEUP_CAPS_DIR/widget/capability"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/widget/install"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/widget/configure"
  chmod +x "$TEEUP_CAPS_DIR/widget/install" "$TEEUP_CAPS_DIR/widget/configure"
  : > "$TEEUP_CAPS_DIR/core.list"
  : > "$TEEUP_CAPS_DIR/daily.list"
  printf '#!/usr/bin/env bash\necho "All 1 suites passed."\n' > "$TEEUP_TESTS_DIR/run.sh"
  printf '#!/usr/bin/env bash\necho "Summary: 1/1 passed"\n' > "$TEEUP_TESTS_DIR/capabilities/widget.sh"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_TESTS_DIR/helper.sh"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_TESTS_DIR/cli.sh"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_TESTS_DIR/bootstrap.sh"
  chmod +x "$TEEUP_TESTS_DIR/run.sh"
  export TEEUP_MENU_FILE="$TEST_HOME/menu.json"
  printf '{"a": {"label": "A", "action": "true"}}\n' > "$TEEUP_MENU_FILE"
  # The real shellcheck would lint the whole checkout on every one of these
  # tests; what is being tested is how dev_check reacts to its exit status.
  mock_command shellcheck 0 ""
}

test_dev_check_passes_a_clean_checkout() {
  setup
  seed_check_fixture
  local rc=0 out
  out="$(dev_check 2>&1)" || rc=$?
  assert_success "$rc" "$out" || return 1
  assert_contains "$out" "Metadata is clean." || return 1
  assert_contains "$out" "is well formed" || return 1
  assert_contains "$out" "shellcheck is clean." || return 1
  assert_contains "$out" "everything passed" || return 1
  cleanup_test_env
}

test_dev_check_reports_a_metadata_problem() {
  setup
  seed_check_fixture
  chmod -x "$TEEUP_CAPS_DIR/widget/install"
  local rc=0 out
  out="$(dev_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "widget: install is not executable" || return 1
  assert_contains "$out" "check(s) failed" || return 1
  cleanup_test_env
}

test_dev_check_reports_a_malformed_menu() {
  setup
  seed_check_fixture
  printf '{"a": {"label": "A"}}\n' > "$TEEUP_MENU_FILE"
  local rc=0 out
  out="$(dev_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "a has neither an action nor child rows" || return 1
  cleanup_test_env
}

test_dev_check_reports_a_failing_shellcheck() {
  setup
  seed_check_fixture
  mock_command shellcheck 1 "SC9999"
  local rc=0 out
  out="$(dev_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "SC9999" || return 1
  cleanup_test_env
}

test_dev_check_notes_a_missing_shellcheck_rather_than_failing() {
  setup
  seed_check_fixture
  hide_host_commands shellcheck
  local rc=0 out
  out="$(dev_check 2>&1)" || rc=$?
  assert_success "$rc" "a missing linter is not a broken checkout" || return 1
  assert_contains "$out" "shellcheck is not installed" || return 1
  cleanup_test_env
}

test_dev_check_with_a_name_runs_only_that_suite() {
  setup
  seed_check_fixture
  printf '#!/usr/bin/env bash\necho "the whole suite ran"\n' > "$TEEUP_TESTS_DIR/run.sh"
  chmod +x "$TEEUP_TESTS_DIR/run.sh"
  local rc=0 out
  out="$(dev_check widget 2>&1)" || rc=$?
  assert_success "$rc" "$out" || return 1
  assert_contains "$out" "Summary: 1/1 passed" || return 1
  assert_not_contains "$out" "the whole suite ran" || return 1
  cleanup_test_env
}

test_dev_check_insists_every_capability_has_a_suite() {
  setup
  seed_check_fixture
  rm -f "$TEEUP_TESTS_DIR/capabilities/widget.sh"
  local rc=0 out
  out="$(dev_check widget 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Every capability needs a dry-run test" || return 1
  cleanup_test_env
}

test_dev_check_fails_when_the_suite_fails() {
  setup
  seed_check_fixture
  printf '#!/usr/bin/env bash\necho "1 of 1 suites failed."\nexit 1\n' > "$TEEUP_TESTS_DIR/run.sh"
  chmod +x "$TEEUP_TESTS_DIR/run.sh"
  local rc=0 out
  out="$(dev_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "1 of 1 suites failed." || return 1
  cleanup_test_env
}

echo "lib/dev.sh"
```

```bash edit-old=tests/lib/dev.sh
run_test "the scaffold passes its own generated suite" test_the_scaffolded_capability_passes_its_own_generated_suite
```
```bash edit-new=tests/lib/dev.sh
run_test "the scaffold passes its own generated suite" test_the_scaffolded_capability_passes_its_own_generated_suite
run_test "dev check passes a clean checkout" test_dev_check_passes_a_clean_checkout
run_test "dev check reports a metadata problem" test_dev_check_reports_a_metadata_problem
run_test "dev check reports a malformed menu" test_dev_check_reports_a_malformed_menu
run_test "dev check reports a failing shellcheck" test_dev_check_reports_a_failing_shellcheck
run_test "dev check notes a missing shellcheck" test_dev_check_notes_a_missing_shellcheck_rather_than_failing
run_test "dev check with a name runs only that suite" test_dev_check_with_a_name_runs_only_that_suite
run_test "dev check insists on a suite per capability" test_dev_check_insists_every_capability_has_a_suite
run_test "dev check fails when the suite fails" test_dev_check_fails_when_the_suite_fails
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/lib/dev.sh`
Expected: the eight new tests fail with `dev_check: command not found`; the suite ends with `Summary: 7/15 passed`.

- [ ] **Step 3: Add `dev_check` to `lib/dev.sh`**

```bash edit-old=lib/dev.sh
# dev_new_capability <name>
```
```bash edit-new=lib/dev.sh
# dev_shell_files -> every shell file CI lints, one absolute path per line.
# This mirrors the argument list in .github/workflows/ci.yml by hand, so the
# two can drift; dev_check says so rather than implying it is authoritative.
dev_shell_files() {
  local f
  printf '%s\n' "$TEEUP_PATH/bootstrap" "$TEEUP_PATH/bin/teeup"
  for f in "$TEEUP_PATH"/lib/*.sh; do
    if [[ -f "$f" ]]; then printf '%s\n' "$f"; fi
  done
  find "$TEEUP_CAPS_DIR" -type f \( -name install -o -name configure \
    -o -name remove -o -name doctor -o -name theme-apply \
    -o -name font-apply \) 2>/dev/null
  for f in "$TEEUP_SKELETON_DIR/install" "$TEEUP_SKELETON_DIR/configure" "$TEEUP_SKELETON_DIR/test.sh"; do
    if [[ -f "$f" ]]; then printf '%s\n' "$f"; fi
  done
  for f in "$TEEUP_TESTS_DIR"/helper.sh "$TEEUP_TESTS_DIR"/run.sh "$TEEUP_TESTS_DIR"/cli.sh \
           "$TEEUP_TESTS_DIR"/bootstrap.sh "$TEEUP_TESTS_DIR"/lib/*.sh "$TEEUP_TESTS_DIR"/capabilities/*.sh; do
    if [[ -f "$f" ]]; then printf '%s\n' "$f"; fi
  done
  return 0
}

# dev_check [<capability>]
# The four things CI runs, plus the menu lint, in one command (spec section 12
# step 7). With a capability name it runs only that capability's suite, which
# takes a second; with no name it runs the whole suite, which takes minutes.
dev_check() {
  local target="${1:-}" problems=0 cache suite f
  local files
  log "== capability metadata =="
  if cap_check; then
    ok "Metadata is clean."
  else
    problems=$((problems + 1))
  fi

  log "== menu definition =="
  if cache="$(menu_cache)"; then
    if menu_check "$cache"; then
      ok "$TEEUP_MENU_FILE is well formed."
    else
      problems=$((problems + 1))
    fi
    rm -f "$cache"
  else
    problems=$((problems + 1))
  fi

  log "== shellcheck =="
  if have shellcheck; then
    files=()
    while IFS= read -r f; do
      files[${#files[@]}]="$f"
    done < <(dev_shell_files)
    # bash 3.2 under `set -u` treats the expansion of an EMPTY array as an
    # unbound variable, so the count decides before "${files[@]}" is used.
    if [[ ${#files[@]} -eq 0 ]]; then
      warn "No shell files found under $TEEUP_PATH."
    elif shellcheck --severity=warning "${files[@]}"; then
      ok "shellcheck is clean."
    else
      problems=$((problems + 1))
    fi
  else
    warn "shellcheck is not installed, so it was skipped here; CI still runs it. Install it with: brew install shellcheck"
  fi

  log "== tests =="
  if [[ -n "$target" ]]; then
    suite="$TEEUP_TESTS_DIR/capabilities/$target.sh"
    if [[ ! -f "$suite" ]]; then
      err "No $suite. Every capability needs a dry-run test under the mock harness; teeup dev new-capability writes one."
      problems=$((problems + 1))
    elif bash "$suite"; then
      ok "$target's suite passed."
    else
      problems=$((problems + 1))
    fi
  elif bash "$TEEUP_TESTS_DIR/run.sh"; then
    ok "The whole suite passed."
  else
    problems=$((problems + 1))
  fi

  if [[ $problems -eq 0 ]]; then
    ok "teeup dev check: everything passed."
    return 0
  fi
  err "teeup dev check: $problems check(s) failed."
  return 1
}

# dev_new_capability <name>
```

- [ ] **Step 4: Add the subcommand**

The usage line, after the `new-capability` line:

```bash edit-old=bin/teeup
  teeup dev new-capability <name>  scaffold capabilities/<name> and its test
```
```bash edit-new=bin/teeup
  teeup dev new-capability <name>  scaffold capabilities/<name> and its test
  teeup dev check [<capability>]   metadata, menu, shellcheck and the tests
```

The case arm:

```bash edit-old=bin/teeup
    new-capability) dev_new_capability "$@" ;;
    *) die "Usage: teeup dev add-migration | new-capability <name>" ;;
```
```bash edit-new=bin/teeup
    new-capability) dev_new_capability "$@" ;;
    check) dev_check "$@" ;;
    *) die "Usage: teeup dev add-migration | new-capability <name> | check [<capability>]" ;;
```

`tests/cli.sh` (phase 4a) asserts only that the message contains `Usage: teeup dev add-migration`, which this string still begins with.

- [ ] **Step 5: Run the library suite**

Run: `bash tests/lib/dev.sh`
Expected: `Summary: 15/15 passed`.

- [ ] **Step 6: Run `teeup dev check` against the real checkout**

This is the command contributors will run, so run it once here for real.

Run: `./bin/teeup dev check`
Expected: `Metadata is clean.`, the menu is well formed, shellcheck is clean, `All N suites passed.`, and `teeup dev check: everything passed.` It takes a few minutes, because it runs the whole suite.

- [ ] **Step 7: Run every check**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning bin/teeup lib/dev.sh tests/lib/dev.sh && git diff --check`
Expected: `All N suites passed.` with N unchanged from the previous task; `commands --check` silent and exit 0; shellcheck silent; `git diff --check` silent.

- [ ] **Step 8: Commit**

```bash
git add lib/dev.sh bin/teeup tests/lib/dev.sh
git commit -m "Add teeup dev check for metadata, menu, shellcheck and tests"
```

---
### Task 10: README and contributor documentation

Four new verbs, a new file format and a new capability script deserve to be written down where the people who need them will look: the README for users, CONTRIBUTING for whoever adds the next capability.

**Files:**
- Modify: `README.md`
- Modify: `CONTRIBUTING.md`

**Interfaces:**
- Consumes: everything Tasks 1 through 9 produced.
- Produces: nothing executable.

**Real-Mac risk:** none.

- [ ] **Step 1: Add the four verbs to the README's command list**

```markdown edit-old=README.md
teeup install dev-env go  # a language runtime through mise
```
```markdown edit-new=README.md
teeup install dev-env go  # a language runtime through mise
teeup menu                # every teeup action as a keyboard-driven list
teeup doctor              # what is broken, and the command that fixes each thing
teeup config get          # the answers, and which of them a machine file pins
```

- [ ] **Step 2: Add the README section**

Insert it immediately before the `### Editors` heading:

````markdown edit-old=README.md
### Editors
````
````markdown edit-new=README.md
### Finding your way around

`teeup menu` puts every action behind one list. It uses `gum` when gum is
installed, `fzf` when it is not, and a plain numbered list when neither is
there, so it works over ssh and inside a script. `teeup menu install` opens
straight at the Install submenu; an empty line, `q` or Escape goes back a
level, and again at the top level to leave.

The menu is `share/teeup/menu.json`: one JSON object whose keys are dotted
ids, so `install.editors.zed` is a row under `install.editors`. Each row is an
object of one-line strings:

| Field | Meaning |
|---|---|
| `label` | required; what the row shows |
| `icon` | optional; printed before the label |
| `action` | a shell command line; a row with one is a leaf, a row without one is a submenu |
| `when` | a shell condition; the row is hidden when it exits non-zero |
| `title` | header shown when the submenu is open; defaults to `label` |

`when` is why the Install list shrinks as the machine fills up: each row asks
`! teeup has <capability>`, and `teeup has` exits 0 only for something already
installed. Conditions and actions run with the checkout's `bin/` first on
`PATH`.

To add or change rows, write `~/.config/teeup/menu.json` in the same format.
An id that is also in the shipped file replaces that row **whole** and keeps
its position; an id that is not is appended. To hide a shipped row, give it
`"when": "false"`.

`teeup doctor` checks every capability this machine has installed and exits 0
when nothing is wrong. Each capability is checked twice: once from its own
metadata (are the packages, casks and apps it declares actually installed, and
does every command in `provides` resolve to a real binary rather than only to
a lazy shim), and once by its own `doctor` script where one exists — the
AeroSpace config that is ambiguous because it is in two places, the ssh key
that is mode 644, the `gpg.ssh.allowedSignersFile` that is not set although
commit signing is on, the theme template that has never been rendered. The
summary at the end names each failure and the single command that fixes it.
`teeup doctor <capability>` checks one, installed or not.

`teeup config` manages the answers file:

```bash
teeup config get                       # every answer, and which ones are pinned
teeup config get TEEUP_THEME           # the value the rest of teeup will see
teeup config set TEEUP_NAME Ada Lovelace
teeup config edit                      # $VISUAL or $EDITOR on the file itself
```

Precedence is capability defaults, then `~/.config/teeup/answers`, then
`machines/<hostname>.conf`, and the machine file wins because it encodes hard
constraints. `teeup config set` never writes the machine file; when the
machine file pins the key you are setting, it says so, because a write that
has no effect is otherwise impossible to notice. `teeup config edit` checks
that the file still parses as shell and rolls your edit back if it does not —
teeup sources it at the start of every command, so a broken line would break
the verb that would fix it.

### Editors
````

- [ ] **Step 3: Add the contributor items**

Append after the last numbered item in `CONTRIBUTING.md`. Phase 4a ended the list at item 23 (the hooks item anchored below), so these four are 24 to 27.

```markdown edit-old=CONTRIBUTING.md
    `theme-set` (`TEEUP_HOOK_EVENTS` in `lib/hooks.sh`); adding one means a
    new `.sample` under `capabilities/teeup-runtime/default/hooks/` and a
    `hook_run <event> [args]` call where it fires.
```
```markdown edit-new=CONTRIBUTING.md
    `theme-set` (`TEEUP_HOOK_EVENTS` in `lib/hooks.sh`); adding one means a
    new `.sample` under `capabilities/teeup-runtime/default/hooks/` and a
    `hook_run <event> [args]` call where it fires.
24. Start a capability with `teeup dev new-capability <name>`, which writes
    `capabilities/<name>/{capability,install,configure}` and
    `tests/capabilities/<name>.sh` from `share/teeup/skeleton/`. The scaffold
    is `tier=lazy` on purpose: a `core` or `daily` capability that is not in
    its tier list makes `teeup commands --check` fail, so change the tier and
    append to the list in the same commit. Finish with
    `teeup dev check <name>`, which runs the metadata lint, the menu lint,
    shellcheck and that capability's suite — the same four things CI runs.
    `teeup dev check` with no name runs the whole suite, which takes minutes.
25. A capability may ship an executable `doctor` beside its `install` and
    `configure`. It runs exactly like them (`bash -eu`, `lib/all.sh` loaded,
    answers sourced, `TEEUP_CAP` and `TEEUP_CAP_DIR` exported) and reports
    through `doctor_ok <message>`, `doctor_warn <message>` and
    `doctor_fail <message> <fix-command>`; its last line is `doctor_verdict`.
    `doctor_fail` returns 0 so the script keeps checking, and the fix it
    records is what the summary prints, so make it one command somebody can
    paste. A doctor script mutates nothing, so it needs no `DRY_RUN` guard.
    Do not write one for anything the metadata already says: `teeup doctor`
    checks `packages`, `casks`, `apps` and `provides` for every capability by
    itself. Write one for the invariants metadata cannot express — a config
    in two places at once, a key with the wrong mode, a generated file that is
    stale.
26. Adding a row to `share/teeup/menu.json` is step 5 of adding a tool. Ids
    are dotted and the tree is in them, so `install.editors.zed` needs
    `install.editors` and `install` to exist as rows too. Every row needs a
    `label`; a row is a leaf when it has an `action` and a submenu when it has
    children, never both and never neither; and no two rows under the same
    parent may share a label, because the picker hands back a label and it is
    mapped to an id by position. `teeup dev check` enforces all of that. Use
    `"when": "! teeup has <name>"` on an Install row so it disappears once the
    thing is installed. The file is read by `lib/menu.awk`, not jq: macOS
    ships no jq and the test harness's narrowed `PATH` hides Homebrew's, so
    values are one-line strings and the only escapes are `\"`, `\\` and `\/`.
27. Anything that draws a full-screen picker — `gum choose`, `fzf` — is behind
    `menu_pick`, and `TEEUP_NO_GUM` turns off both, because both paint on
    `/dev/tty`. **Every test that drives a prompt or a menu must
    `export TEEUP_NO_GUM=1`**: the harness narrows `PATH` but `/usr/bin/gum`
    can still be there, and a test that forgets will hang on a real terminal
    widget. A test that wants the fzf branch specifically sets
    `TEEUP_MENU_PICKER=fzf` and mocks `fzf`; no test may need either program
    installed.
```

- [ ] **Step 4: Run every check**

Run: `./tests/run.sh && ./bin/teeup commands --check && git diff --check`
Expected: `All N suites passed.` with N unchanged from the previous task; `commands --check` silent and exit 0; `git diff --check` silent (no trailing whitespace in the new prose).

- [ ] **Step 5: Commit**

```bash
git add README.md CONTRIBUTING.md
git commit -m "Document the doctor, menu, config and dev verbs"
```

---
## Verification

Run these after the last task, from the checkout root.

1. **The suite.** `./tests/run.sh` → `All N suites passed.`, where N is the count printed before this plan plus 3 (`tests/lib/doctor.sh`, `tests/lib/menu.sh`, `tests/lib/dev.sh`). Per-suite counts at the end of this plan: `tests/lib/doctor.sh` 14, `tests/lib/menu.sh` 15, `tests/lib/dev.sh` 15, `tests/cli.sh` 46, `tests/capabilities/aerospace.sh` 11, `package-manager.sh` 7, `teeup-runtime.sh` 13, `dev-dirs.sh` 4, `zsh.sh` 26, `git.sh` 25, `ssh.sh` 22, `github.sh` 23, `mise.sh` 13, `starship.sh` 8, `theme.sh` 23.
2. **Metadata.** `./bin/teeup commands --check` → silent, exit 0.
3. **Shellcheck**, the same argument list CI uses, now including the skeleton:
   ```
   shellcheck --severity=warning bootstrap bin/teeup lib/*.sh \
     $(find capabilities -type f \( -name install -o -name configure \
       -o -name remove -o -name doctor -o -name theme-apply \
       -o -name font-apply \)) \
     share/teeup/skeleton/install share/teeup/skeleton/configure \
     share/teeup/skeleton/test.sh \
     tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh \
     tests/lib/*.sh tests/capabilities/*.sh
   ```
   → silent. `lib/menu.awk` is awk, not shell, and is outside that list on purpose.
4. **The menu lints itself.** `./bin/teeup dev check` → metadata clean, `share/teeup/menu.json` well formed, shellcheck clean, the whole suite green, `teeup dev check: everything passed.`
5. **The verbs answer.** `./bin/teeup doctor` exits 0 on a machine with nothing installed (it says so and checks nothing); `./bin/teeup menu` draws the top level through the plain picker under `TEEUP_NO_GUM=1`; `./bin/teeup config get` prints the answers file path.
6. **bash 3.2.** With a bash 3.2.0 first on `PATH`, `bash ./tests/run.sh` gives the same `All N suites passed.` and the five commands above behave identically. Three things in this plan are bash-3.2 hazards and are written for it: `"${array[@]}"` is never expanded without first checking `${#array[@]}` (bash 3.2 under `set -u` calls the expansion of an empty array an unbound variable); `${!key+x}` indirect expansion is used for "is this answer set at all"; and no `${var//pat/repl}` appears anywhere in the new code — `replace_literal` does the one substitution the scaffold needs.
7. **Nothing left behind.** `git status --short` after the `tests/lib/dev.sh` suite shows no `capabilities/teeup-scaffold-probe` and no `tests/capabilities/teeup-scaffold-probe.sh`; that suite scaffolds into the real checkout and removes it before its assertions.
8. **`git diff --check`** → silent.

## Self-review

### Spec coverage

| Spec | Where |
|---|---|
| §4 `doctor` — optional, exit 0 healthy, prints findings | Task 1's contract and runner; scripts in Tasks 1–4 |
| §4 `share/teeup/menu.json` — declarative menu, dotted ids | Tasks 5 and 6 |
| §4a metadata contract | `doctor_metadata_check` reads `packages`, `casks`, `apps` and `provides` (Task 1) |
| §4b home layout | the `teeup-runtime`, `zsh`, `theme` and `mise` doctors check the env file, the command link, the state tree, the three home files and `current/theme/{dark,light}` |
| §7 answers, `teeup config get\|set\|edit`, precedence | Task 7 |
| §7 reset | phase 4a's; this plan's doctors point at `teeup reset <cap>` as the fix for an edited shipped file |
| §12.1 `teeup dev new-capability <name>` with templates and a test file | Task 8 |
| §12.5 a row in `share/teeup/menu.json` | Task 6, and `menu_check` enforces the shape (Task 5) |
| §12.7 `teeup dev check` — metadata lint, executable bits, shellcheck, dry-run tests | Task 9 (`cap_check` covers the executable bits) |
| CLI surface: `teeup doctor [<cap>]`, `teeup menu`, `teeup config get\|set\|edit`, `teeup dev new-capability\|check` | Tasks 1, 6, 7, 8, 9 |
| §1–2 predicates as exit codes; menu with dotted ids and `when` | `menu_visible` runs `when` through `bash -c` with `$TEEUP_PATH/bin` first on PATH, so `teeup has` is the predicate |
| Migration-path gate "phase 4: `teeup doctor` clean on a bootstrapped Mac" | only a real Mac settles it; named as the Real-Mac risk on Task 1 |

**One gap, and it is not this plan's.** The spec's CLI-surface block writes `teeup list [--tier|--group|--json]`; `bin/teeup` implements `--tier` only, and neither phase 3, 4a nor this plan claims `--group` or `--json`. It is discoverability work, but the controller's scope for 4b names doctor, menu, config and dev, so this plan does not take it. Whoever writes 5b's documentation pass should either implement the two flags or amend the spec.

**One addition to §4b's home layout.** That section lists `env`, `answers`, `hooks/`, `themes/` and `themed/` under `~/.config/teeup/`; this plan adds `menu.json` there, as the user-extension half of §12 step 5 and the counterpart of Omarchy's `config/omarchy/extensions/omarchy-menu.jsonc`. It is documented in the README section Task 10 adds.

### Deferred items taken here

| Item | From | Task |
|---|---|---|
| `gpg.ssh.allowedSignersFile` is unset, so commit signatures cannot be verified locally | phase 2a final review #5 ("spec-acknowledged, phase 4 with `teeup doctor`") | 3 — the `git` doctor reports it with a one-line fix, and only when signing is actually on |
| A `doctor` check that the shims directory is last on the live `PATH` | phase 3b deferred | 2 — the `teeup-runtime` doctor fails when it is off PATH and warns when it is on but not last |
| Spec §10's "`teeup doctor` flags leftovers" | spec §10 | partly — the runner, the report and the summary are here; the four leftover checks themselves (a `[user]` block in `~/.gitconfig.local`, p10k remnants, an Oh My Zsh directory, a chezmoi source dir pointing at the Linux repo) belong to phase 5a with the rest of `teeup migrate legacy`, and drop in as one more doctor script |

### Deferred items deliberately left

| Item | Reason |
|---|---|
| Routing `capabilities/mise/configure`'s `mise settings set` through `write_config_region` (phase 2a #6, handed on by 4a) | **already resolved upstream.** Phase 3b Task 2 rewrote that configure so the setting ships inside the copied `config.toml` and no `mise settings set` runs at all; `tests/capabilities/mise.sh` asserts it. Nothing is left to route. |
| `typeset -U fpath path` in the zsh layer (phase 2a #4) | The zsh layer is not touched here. Taking it would be an unrelated edit inside a task nobody would review it in, and it is a duplicate-entry tidiness issue, not a failure a doctor could report. |
| `alt` bindings in AeroSpace take the Meta key; `keyboard` replaces all `hidutil` mappings; a WezTerm started from the Dock with a non-default config dir; `;` or `?` in a checkout path breaks Lua's search path (pr11) | Four bugs inside three capabilities' own scripts, each with its own test surface. A `doctor` can report a symptom but not fix any of them, and inventing a check for each would be worse documentation than the existing deferral. |
| `mock_command` splices `$output` unescaped; `_teeup_log_line` runs `mkdir -p` per line; the `__` collision in `_stock_record_path`; the duplicated `mkdir -p` in `state.sh` (phase 1 #5, #6, #8, #9) | Test-only or cosmetic, and none of them is in code this plan touches. |
| `teeup list --tier` with no value (phase 1 #18) | Already fixed on `main`; `tests/cli.sh` asserts the usage error. |
| The wizard asks a question the machine file pins (2a re-review) | `bootstrap`'s wizard, which this plan does not touch. Phase 4d rewrites the theme question and is the cheap place for the `machine_get` guard. `teeup config get` at least now shows which answers are pinned, which is the reporting half. |
| Doctor scripts for `cli-tools`, `fonts`, `wezterm`, `keyboard`, `macos-defaults`, `secrets`, `xcode-clt` and the phase 3 capabilities | Not an oversight. `doctor_metadata_check` already covers every one of them from their own metadata: `cli-tools` is thirteen packages, `fonts` and `wezterm` are casks and apps, the phase 3 lazy capabilities are `provides` commands. A script is only worth writing where an invariant cannot be read off the metadata, and CONTRIBUTING item 25 says so, so the next contributor does not add nine empty ones. `macos-defaults` gets none on purpose: `defaults_write` records the *prior* value, not teeup's, so there is nothing a check could compare against without re-deriving what `configure` would write. |
| `teeup menu` rows for `update`, `reset` and `remove` as unconditional entries | Those verbs are phase 4a's. The shipped menu carries them behind `"when": "teeup help \| grep -q '^  teeup update'"`, so they appear by themselves once 4a lands and `share/teeup/menu.json` needs no second edit. The transcription below ran without 4a, and the rows correctly stayed hidden. |
| Launch-or-focus inside a themed floating terminal (phase 3b deferred, spec §6.3) | A presentation decision about a terminal window, not discoverability; `teeup launch` already covers the behaviour. |

### Placeholder scan

No `TBD`, `TODO`, `FIXME`, "implement later", "similar to Task N" or bare `...` stands in for content anywhere. Every new file appears as a complete `file=` block; every change to an existing file is an `edit-old`/`edit-new` pair whose `edit-old` text was checked to occur exactly once in the file at that point. No step is conditional: Task 8 Step 4 and Task 9 Step 4 edit the `cmd_dev` phase 4a has already created, which execution order guarantees is there.

### Name and type consistency

- `doctor_ok`, `doctor_warn`, `doctor_fail`, `doctor_verdict`, `doctor_record`, `doctor_metadata_check`, `doctor_targets`, `doctor_run_one`, `doctor_summary` are spelled the same in `lib/doctor.sh`, in all ten doctor scripts, in `tests/lib/doctor.sh`, and in CONTRIBUTING item 25.
- `doctor_fail <message> <fix-command>` takes its arguments in that order everywhere; the report is `capability<TAB>message<TAB>fix`, and `doctor_summary` prints `capability: message` then `      fix: <fix>`. Messages therefore carry no capability prefix of their own, which is why `doctor_metadata_check` says `package ripgrep is not installed` and not `widget: package ripgrep is not installed`.
- `menu_parse`, `menu_entries`, `menu_cache`, `menu_ids`, `menu_children`, `menu_field`, `menu_label`, `menu_visible`, `menu_run`, `menu_picker`, `menu_pick`, `menu_check` are spelled the same in `lib/menu.sh`, `bin/teeup`, `lib/dev.sh` and `tests/lib/menu.sh`. Every query takes the cache path as its first argument; `menu_pick` and `menu_run` do not.
- `dev_new_capability`, `dev_check`, `dev_shell_files`, `TEEUP_SKELETON_DIR`, `TEEUP_TESTS_DIR` agree across `lib/dev.sh`, `bin/teeup` and `tests/lib/dev.sh`.
- The environment names are `TEEUP_DOCTOR_REPORT`, `TEEUP_DOCTOR_FAILURES`, `TEEUP_MENU_FILE`, `TEEUP_MENU_PICKER`, `TEEUP_SKELETON_DIR`, `TEEUP_TESTS_DIR`. None collides with a name phase 3a, 3b or 4a introduces (`TEEUP_CONFIGURING`, `TEEUP_HOOK_EVENTS`, `TEEUP_HOOK_EVENT`, `TEEUP_MIGRATION`, `TEEUP_MIGRATIONS_DIR`, `TEEUP_REFRESH`, `TEEUP_RESET`, `TEEUP_DEFAULTS_CHANGED`, `TEEUP_SHIM_MARKER`, `TEEUP_MISE_WRAPPER_MARKER`, `TEEUP_DEV_ENVS`, `TEEUP_TEST_TTY`).
- `lib/all.sh`'s library list grows `doctor` (Task 1), `menu` (Task 5) and `dev` (Task 8), each anchored on the line the previous task left — the first on phase 4a's `… lazy mise hooks migrations` — so the three edits chain and none of them fights phase 4a's `hooks` and `migrations`.

### External facts, and where each was checked (2026-09-16)

- **The menu model.** `/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc` (Omarchy v4, installed on this machine) — object keys are dotted ids, hierarchy is in the ids, `when` is "shell condition; hide row when it fails", `action` makes a row a leaf, `title` defaults to `label`. The user-override file is `/usr/share/omarchy/config/omarchy/extensions/omarchy-menu.jsonc`. teeup's format is the same idea with JSON instead of JSONC and no `provider`, `aliases` or `checked`.
- **awk portability.** `lib/menu.awk` was run against GNU awk 5.4.1 and against the one-true-awk (version 20260426, the same lineage macOS ships) with identical output on the well-formed and the five malformed inputs. Errors go through `print ... | "cat 1>&2"` rather than `"/dev/stderr"`, which is not universally supported.
- **bash 3.2.0 behaviour**, checked against the built 3.2.0 binary: `a=(); echo ${#a[@]}` prints 0 and is fine, `a[${#a[@]}]="x"` appends, but `printf '%s\n' "${a[@]}"` on an empty array under `set -u` is `a[@]: unbound variable`. `${!k+yes}` and `${!k}` both work.
- **`gh`**: `gh auth status --active -h <host>` prints a `Token scopes:` line for the active account only, and `gh ssh-key list` in a non-TTY prints TITLE, KEY, ADDED, ID, TYPE tab-separated — both as already documented and mocked in `tests/capabilities/github.sh` for gh 2.100.0, which the `github` doctor reuses rather than re-deriving.
- **`mise`**: `mise -C / ls --global [--installed] <tool>` and `mise -C / where <tool>` — the `github` and `mise` doctors go through `mise_global_state` (phase 3b `lib/mise.sh`), which already carries the verified 2026.9.4 semantics, so this plan adds no new mise fact of its own.
- **`ssh-keygen`/`ssh`**: a private key that other accounts can read is refused by ssh, which is why mode 600 is a failure rather than a note; the mode probe is the `stat -c` / `stat -f` pair already used by `capabilities/ssh/configure`'s `chmod_once`.
- **`defaults read -g AppleInterfaceStyle`** exits 1 in light mode — already encoded in `lib/macos.sh`'s `appearance`, which the `theme` doctor calls rather than re-implementing.
- **No new package, cask, formula or mise registry name is introduced by this plan.** Every capability it touches was already shipped by phase 1, 2a, 2b, 3a or 3b.

### Verified by transcription

**Base:** a clone of the phase 3a + 3b scratch tree (`plan3-ab-fix/tree`, HEAD = 3b Task 11, `All 46 suites passed.`). Phase 4a's plan text was final when this was written but its own transcription was still running, so **4a's tasks were not applied**; the "Depends on" section states exactly what this plan assumes about 4a and why the two apply in either order.

Every task was applied to that clone in order and, after each, `./tests/run.sh`, `./bin/teeup commands --check`, `shellcheck --severity=warning` on the new and edited files, and `git diff --check` were run. All ten are green:

| Task | Suites after | Notes |
|---|---|---|
| 1 | All 47 | +`tests/lib/doctor.sh` (14/14); `tests/cli.sh` 32/32; `aerospace.sh` 11/11 |
| 2 | All 47 | `package-manager.sh` 7/7, `teeup-runtime.sh` 13/13, `dev-dirs.sh` 4/4, `zsh.sh` 26/26 |
| 3 | All 47 | `git.sh` 25/25, `ssh.sh` 22/22, `github.sh` 23/23 |
| 4 | All 47 | `mise.sh` 13/13, `starship.sh` 8/8, `theme.sh` 23/23 |
| 5 | All 48 | +`tests/lib/menu.sh` (15/15); also re-run with the one-true-awk first on PATH, 15/15 |
| 6 | All 48 | `tests/cli.sh` 38/38; `menu_check` on the shipped `share/teeup/menu.json` exits 0 with no output |
| 7 | All 48 | `tests/cli.sh` 46/46 |
| 8 | All 49 | +`tests/lib/dev.sh` (7/7); `git status` clean of the scaffold probe |
| 9 | All 49 | `tests/lib/dev.sh` 15/15; `./bin/teeup dev check` on the real checkout: everything passed |
| 10 | All 49 | docs only |

**Under bash 3.2.0** (`bash-3.2/bash` first on `PATH`, so `tests/run.sh`, every suite and every `#!/usr/bin/env bash` script ran under it): `All 49 suites passed.`, 641 PASS, 0 FAIL. `./bin/teeup commands --check` exit 0 and silent; the shipped menu lints clean; `teeup menu` drew its top level through the plain picker, with the `update` and `setup.reset` rows correctly hidden because phase 4a's verbs are not in that tree; `teeup doctor` on a machine with nothing installed said so and exited 0; `teeup config get` printed the answers path.

**What the transcription did not prove**, beyond the per-task Real-Mac notes: the doctor scripts were exercised against mocks, so no finding in them has been produced by a real broken Mac; `gum choose` and `fzf` were never run, only mocked; and `teeup dev check` was run on Linux, where the `find`-based file list and shellcheck behave the same but `brew` does not exist.
