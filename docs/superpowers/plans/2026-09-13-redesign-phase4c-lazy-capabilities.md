# teeup Redesign, Phase 4c: The Remaining Lazy Capabilities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the rest of the spec's lazy tier: Kubernetes tools and lazydocker on top of Colima, a `docker-dbs` picker that starts localhost database containers, the browsers, communication and productivity casks, Karabiner-Elements with an optional hyper key, and Xcode through `mas`.

**Architecture:** Every capability here is `tier=lazy`, so nothing it installs is downloaded at bootstrap and nothing in `bin/teeup` changes: phase 3b's shims, `teeup lazy-run`, `teeup launch` and phase 4a's `teeup remove` all read the capability's metadata and need no code for a new name. Four shapes cover the twenty capabilities. Command-line tools that mise packages (`kubectl`, `helm`, `k9s`) install through `mise_ensure_global` and are reached by their `provides=` shims. `lazydocker` is a package-manager formula with a command of its own, so it is one `pkg_install` line and a `provides=` shim. GUI casks (sixteen of them) are one `cask_app_install` line and one `cask_app_report` line each, over two helpers this plan adds to `lib/lazy.sh` next to `app_installed`, and are reached by `teeup launch`. The two that are neither — `docker-dbs`, an interactive picker over `docker run`, and `xcode`, an App Store download through `mas` — carry their own scripts.

**Tech Stack:** bash 3.2 (macOS stock), BSD `sed`/`awk`/`grep`, shellcheck, Homebrew casks and formulae with MacPorts degradation, mise 2026.9 (`use -g`, `unuse --global`, `where`), Docker Official Images on Colima, `mas` 7, Karabiner-Elements 16, the phase 1 mock-binary test harness.

**Spec:** `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md`. This plan implements the Containers, Databases, Browsers, Comms, Productivity, Keyboard (Karabiner half) and Package managers (`mas`) rows of the interview table, the `kubectl helm k9s lazydocker` entries of section 6's shim list, and section 6's sentence "Lazy covers languages, containers, Kubernetes, `docker-dbs`, AI CLIs, Ollama, Cursor, Herdr, tmux, Karabiner, Xcode, browsers beyond Chrome, communication and productivity apps (1Password, Raycast, Bruno, Notion, Typora)", minus the parts phases 3a and 3b already ship.

**Subphase seams:** 4a owns `update`/`reset`/`remove` and the migration and hook libraries; 4b owns `doctor`, `menu`, `config` and the `dev` verbs, including `share/teeup/menu.json` and every doctor script; 4c adds **no** `bin/teeup` verb, edits no doctor infrastructure and edits no menu file; 4d adds themes only. Execution order is 4a, 4b, 4c, 4d.

---

## Global Constraints

- bash 3.2 compatible everywhere: no `mapfile`, `declare -A`, `${var,,}`/`${var^^}`, `readarray`, `readlink -f`; no same-line `local` back-references (`local a=1 b=$a`); `10#$n` for arithmetic on user-typed numbers. bash 3.2 mis-parses a quoted pattern containing `/` inside `${var//pat/repl}`: use `replace_literal` (`lib/files.sh`). Run `shopt -u patsub_replacement 2>/dev/null || true` before a `${var//}` replacement whose replacement text contains `&`. Nothing in this plan uses `${var//}`. An empty array under `set -u` is an error in bash 3.2, so every array expansion here is written `${arr[@]+"${arr[@]}"}`.
- BSD tools only: no GNU-only flags for `sed`, `grep`, `date`, `mktemp`, `sort`, `readlink`, `stat`, `env`; no `\t` or `\n` inside a `sed` replacement; awk gets values through `ENVIRON`, never `-v`, when they may contain backslashes.
- Capability scripts start with `#!/usr/bin/env bash`, run as `bash -eu` with `lib/all.sh` loaded and `answers_load` done, use no `local`, and call mocked commands by bare name (`brew`, `port`, `mise`, `docker`, `mas`, `open`). `set -e` fires on a failing command anywhere in a script, so a command that may fail harmlessly carries `|| warn ...` or sits in an `if`; never end a script with `[[ ]] && cmd`. Every mutation goes through `run_cmd`/`run_privileged` or a primitive with its own `DRY_RUN` guard (`copy_config_once`, `write_managed_file`, `_state_touch`). `DRY_RUN=true` changes nothing.
- Paths: `user_config_dir` for `~/.config`; `TEEUP_CONFIG_DIR` and `TEEUP_STATE_DIR` honoured; `TEEUP_APPS_DIR` instead of a literal `/Applications` in every script and test. Paths with spaces and shell metacharacters must work: Task 3 runs the picker under a `$HOME` containing a space and a dollar sign, Task 7 copies Karabiner's config under an `XDG_CONFIG_HOME` with a space.
- Machine file precedence (`answers`, then `machines/<hostname>.conf`) for every consumer of an answer: `bin/teeup` runs `answers_load` before any verb, so `TEEUP_SKIP`, `TEEUP_PACKAGE_MANAGER`, `TEEUP_DBS` (Task 3) and `TEEUP_KARABINER_HYPER` (Task 7) all reach the capability from either file.
- `capability` metadata contract: `summary group tier requires provides packages casks apps interactive`. `provides` never names a command macOS ships (`python3 ruby java git perl`); `apps` is `;`-separated because application names contain spaces; a core or daily capability must be in its tier list. Every capability in this plan is `tier=lazy`, so no tier list changes and `capabilities/core.list` and `capabilities/daily.list` are not edited.
- Tests: `tests/helper.sh` (temp `HOME`, `MOCK_BIN` first on the narrowed `PATH` `$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin`, `mock_command`, `mock_command_script`, `mock_macos_base`, `hide_host_commands`, `TEEUP_TEST_MISSING`, `TEEUP_PKG_PREFIX`, `TEEUP_APPS_DIR`, `TEEUP_TEST_TTY`). No test may depend on the host having any app or tool this plan installs: `TEEUP_APPS_DIR` points at a temp directory, and `hide_host_commands` hides a `docker`, `kubectl` or `helm` the runner happens to have in `/usr/bin` before any mock of that name exists. **`lib/ui.sh` uses `gum` whenever `TEEUP_NO_GUM` is empty and `gum` is on `PATH`, and the harness `PATH` still exposes `/usr/bin/gum` on a machine that has it: every test that drives a prompt or a picker exports `TEEUP_NO_GUM=1`.** CI runs `macos-14`, `macos-15-intel` and `ubuntu-latest`; a test that passes on only one of them, or only on a developer's machine, is a defect.
- Every task ends with `./tests/run.sh` green, `./bin/teeup commands --check` silent with exit 0, `shellcheck --severity=warning` clean on every new or edited script and test, `git diff --check` clean, and **one** commit with a plain imperative subject and no trailer of any kind (no `Co-Authored-By`, no `Claude-Session`, no "Generated with").
- Suite counts: `tests/run.sh` ends with `All N suites passed.` Never hard-code N. Each task states "the suite count printed before this task, plus K", so the plan stays right whatever else landed first.
- Nothing in this phase has run on a real Mac. Each task carries a **Real-Mac risk** note naming what only hardware proves.
- Verify, do not guess: every cask token, formula name, port name, mise registry name, container image, application bundle name and CLI flag below was checked against upstream on 2026-09-16; the sources are listed in the Self-review. A name that does not appear there is not to be introduced during execution without the same check.
- Plain prose in every comment, log line and doc: none of "No X, no Y" chains, "That's the whole ...", "Don't X it. Y it.", "Sit with that", "You already know", "is the entire", "The punchline", "Worth naming", "X is real, and ...".

---

## Depends on

Phases 3a, 3b and 4a are planned and land before this one. Their plan text is the contract for everything they add; `main` is the contract for everything older. The pre-flight scan should confirm each of these exists before Task 1 starts.

| What this plan consumes | Shape | Defined by |
|---|---|---|
| `lib/lazy.sh` with `shims_dir`, `TEEUP_SHIM_MARKER`, `shims_generate`, `lazy_provider`, `lazy_real_command`, `lazy_is_tty`, `cap_apps`, `app_installed`, `launch_resolve` | shell library, sourced by `lib/all.sh` between `font` and `mise` | plan 3b, Task 1 |
| `teeup lazy-run <cap> <command>` and the shim written for every `provides=` token of a `tier=lazy` capability | `bin/teeup` verb plus `$TEEUP_STATE_DIR/shims/<command>` | plan 3b, Tasks 1 and 3 |
| `teeup launch <app\|capability>` reading `apps=` | `bin/teeup` verb | plan 3b, Task 4 |
| `mise_ensure_global <tool> [version]` (`installed`/`requested`/`absent` logic, `mise -C /` everywhere) | function in `lib/mise.sh` | plan 3b, Task 2 |
| `capabilities/colima` (`provides="docker colima"`, `requires="package-manager"`, installs the Docker CLI and starts the VM in `configure`) | capability directory; Tasks 2 and 3 name it in `requires=` | plan 3b, Task 5 |
| `capabilities/ai` and `capabilities/chrome` | the two shapes this plan copies: a mise-backed lazy capability and a GUI-cask lazy capability | plans 3b Task 6 and 3a Task 4 |
| `hide_host_commands <name...>` and `TEEUP_TEST_TTY=yes\|no` | `tests/helper.sh` and `lib/lazy.sh` | plan 3b, Task 1 |
| README's "Shipped lazy capabilities" bullet and the "Adding a capability (new runtime)" list in CONTRIBUTING | the two anchors Task 9 extends | plan 3b, Task 11 |
| `pkg_uninstall <pkg>` and `cask_uninstall <cask>` | functions in `lib/pkg.sh` | plan 4a, Task 2 |
| `teeup remove <cap>`: runs `capabilities/<cap>/remove` when present, then `cask_uninstall` for every `casks=` entry and `pkg_uninstall` for every `packages=` entry, then clears `done/cap-<cap>` | `bin/teeup` verb | plan 4a, Task 2 |
| `teeup update` re-runs `configure` only for `core.list` | why a `configure` in this plan may prompt: none of these is core, so none is re-run unattended | plan 4a, Task 1 |
| CONTRIBUTING items up to 23 | Task 9 appends after the last numbered item, whatever its number is by then | plan 4a, Task 9 |

**Phase 4b is written in parallel and this plan does not touch its files.** 4b owns `share/teeup/menu.json` and every doctor script, and its `doctor_metadata_check` is derived from metadata alone: it checks that every `packages` entry is installed, every `casks` entry is installed (skipped on MacPorts), every `apps` entry is in `/Applications`, and every `provides` command resolves to a real binary rather than only to a shim. That is why the metadata in this plan is exact rather than decorative, and it is also why no capability here ships a `doctor` script: the generic half already covers a cask that installs one app, and the two checks that need more than metadata (Karabiner's driver approval, a signed-in App Store) are named in "Deliberately deferred". Adding a `menu.json` row per capability added here is 4b's file to edit; each capability carries a `group=` (`containers`, `browsers`, `communication`, `productivity`, `macos`, `system`) so those rows can be grouped without reading any script.

---

## Contracts this plan publishes

1. **Two GUI-cask helpers in `lib/lazy.sh`** (Task 4), used by every cask capability in Tasks 4 to 7:
   - `cask_app_install <cask> <app name> <download url>` installs the cask on Homebrew and, on MacPorts (which has no casks), warns with the download page and returns 0, so `teeup install <cap>` still exits 0 there.
   - `cask_app_report <app name> [extra line]` prints `<app> is installed; open it with: open -a '<app>'` when the bundle is under `${TEEUP_APPS_DIR:-/Applications}` or `~/Applications`, and `<app>.app is not in <dir>; the install step above says why.` when it is not, then the optional extra line. It always returns 0. The two sentences are word-for-word what `capabilities/chrome/configure` prints on `main`, so the family reads the same.
2. **Twenty new capabilities, all `tier=lazy`.** `k8s` (`provides="kubectl helm k9s"`), `lazydocker` (`provides="lazydocker"`), `docker-dbs` (`interactive=true`, no `provides`), `brave`, `arc`, `zen`, `slack`, `zoom`, `signal`, `whatsapp`, `telegram`, `discord`, `teams`, `1password`, `raycast`, `bruno`, `notion`, `typora`, `karabiner` and `xcode`. Each declares the `casks=` or `packages=` that `teeup remove` undoes and the `apps=` that `teeup launch` and 4b's doctor read.
3. **`TEEUP_DBS`** (Task 3) is an answers/machine-file key holding a space-separated subset of `postgres mysql mariadb redis mongo`. When it is set, `teeup configure docker-dbs` starts exactly those containers without asking; when it is empty, it asks once with `ui_choose` and starts the one chosen. The container names, images, ports and environment are fixed: `postgres18`/`postgres:18`/5432, `mysql8`/`mysql:8.4`/3306, `mariadb11`/`mariadb:11.8`/3306, `redis`/`redis:7`/6379, `mongodb`/`mongo:noble`/27017, every one published to `127.0.0.1` only.
4. **`TEEUP_KARABINER_HYPER`** (Task 7) is an answers/machine-file key with the values `right_command` (the default), `caps_lock` and `none`. It picks which shipped `karabiner.json` is installed, and only when `~/.config/karabiner/karabiner.json` does not exist yet; an existing file is kept and the shipped rule's path is printed instead.
5. **No new `bin/teeup` verb, no new library file, no edit to `bin/teeup`, `bootstrap`, `capabilities/core.list`, `capabilities/daily.list`, `share/teeup/menu.json` or any `doctor` script.** The only shared file this plan changes is `lib/lazy.sh` (two functions appended), plus `tests/lib/lazy.sh`, `README.md` and `CONTRIBUTING.md`.

---

## Decisions made here

1. **`kubectl`, `helm` and `k9s` are one capability, not three.** `cap_check` refuses two lazy capabilities that provide the same command, and nothing here would ever want `helm` without `kubectl`, so `k8s` provides all three and one `teeup install k8s` (or the first `kubectl` through its shim) brings the set. The spec's interview table groups them the same way ("k8s: kubectl, helm, k9s via mise, lazy").
2. **`k8s` installs through mise at install time and needs no `~/.local/bin` wrapper.** The `ai` capability writes wrappers because its five CLIs must install on their *first call*; `k8s` is installed by `teeup install k8s`, which the shim already triggers. Phase 2a's zsh layer appends mise's own shims directory (`${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/shims`) to `PATH` ahead of teeup's shims, so the binary `mise use -g` installs is on `PATH` for `lazy_real_command` to exec and for every later shell. That keeps `TEEUP_MISE_WRAPPER_MARKER`, whose text names the `ai` capability, out of a second capability's files.
3. **`k8s` ships a `remove` script; the cask capabilities do not need one.** `teeup remove` uninstalls `casks=` and `packages=`, and `k8s` has neither, so without a `remove` script `teeup remove k8s` would clear the marker and leave three tools installed. `mise unuse --global <tool>` removes the request from the global config and prunes the installation ("Versions are pruned only when no remaining tracked config or tool stub needs them"), which is the exact inverse of `mise_ensure_global`.
4. **`lazydocker` and `docker-dbs` require `colima`.** Both are useless without a Docker daemon, and `cap_order` installs a requirement first, so `teeup install lazydocker` on a fresh machine brings Colima, the Docker CLI and the started VM before it installs the TUI. Omarchy's `omarchy-launch-docker-tui` wraps lazydocker in `pkexec` because on Arch the Docker socket is root-owned; Colima runs the VM as the user and its socket is the user's, so the macOS capability needs no elevation at all.
5. **`docker-dbs` is a `configure` that can be run again, not a command.** 4c adds no verbs, so the picker lives where the capability model already puts a repeatable action: `teeup configure docker-dbs` (which `teeup install docker-dbs` also runs). Running it again starts another database. `interactive=true` is what lets `cap_run` leave stdin attached for the picker.
6. **The database table follows Omarchy's `omarchy-install-docker-dbs`, minus MSSQL and minus `sudo`.** Same images, tags, container names, published ports and environment variables, because those are a working set that has shipped. `sudo` goes because Colima's docker runs as the user. MSSQL goes because `mcr.microsoft.com/mssql/server:2022-latest` answers with a single-platform `linux/amd64` manifest rather than a manifest list, so there is no arm64 image for an Apple Silicon Mac; the other five images all publish `arm64/v8`.
7. **Containers are started idempotently.** Omarchy's script runs `docker run` every time, which fails on the second run with "name is already in use". This one reads `docker ps -a` first: an existing container that is stopped is started, an existing container that is running is reported, and only a missing one is created. That also makes `teeup configure docker-dbs` safe to re-run, which the capability model requires.
8. **Fifteen GUI casks, three tasks, two helper functions.** Grouping them by what they are for (browsers, communication, productivity) keeps each task's review meaningful and each suite readable, while `cask_app_install`/`cask_app_report` keep fifteen `install` scripts from being fifteen copies of the same six lines. Every capability still declares its own metadata, and every suite still asserts each capability's own cask token and application name by name.
9. **`group=` gets three new values rather than reusing `apps`.** `browsers`, `communication` and `productivity` are what 4b's menu will group by. `chrome`, `firefox-developer-edition` and `obsidian` keep `group=apps` from phase 3a: nothing reads `group=` yet, and re-tagging another phase's capabilities belongs with the menu rows that would use the new values.
10. **Karabiner's hyper key defaults to right command, not Caps Lock.** The core `keyboard` capability maps Caps Lock to Control at the HID layer through `hidutil` and re-applies it at every login, so a Karabiner rule on the same key would be two mappings fighting over one key. `TEEUP_KARABINER_HYPER=caps_lock` is still offered and still ships the classic "Caps Lock is Hyper, tap for Escape" rule, and `configure` warns when it is chosen while `keyboard` is not in `TEEUP_SKIP`.
11. **Karabiner's config is installed only when the user has none.** Karabiner rewrites `~/.config/karabiner/karabiner.json` itself whenever a setting changes in its UI, so the file is the user's, not teeup's. `copy_config_once` would back up and replace a foreign file; `configure` therefore checks for the file first and, when it exists, prints the path of the shipped rule to import by hand. This is the rule `capabilities/tmux/configure` already follows for `~/.tmux.conf`.
12. **The Karabiner permission steps print in full once, then as one line.** The four approvals (background services, Accessibility, Input Monitoring, the driver extension) are what makes the difference between an installed Karabiner and a working one, and they cannot be scripted. `state_done ensure karabiner-permissions` succeeds only the first time, so the full list prints on the first `configure` and a one-line reminder afterwards. That answers the deferred "the AeroSpace manual-step text prints on every run" complaint for this capability without touching AeroSpace.
13. **`xcode` cannot check `mas account`, because mas removed it.** The spec (section 4a) says the capability "checks `mas account`"; mas pull request 1167, "Remove `account`, `region` & `signin`", was merged on 2025-12-28 and mas 7.0.0's command table has neither. There is no supported way to ask mas whether an Apple Account is signed in, so `configure` tells the user to sign in to the App Store first, asks before starting a multi-gigabyte download, and reports mas's own failure when nobody is signed in. `mas list` is still the way to ask whether Xcode has already been installed from the App Store.
14. **`xcode` is `interactive=true` and never switches the developer directory by itself.** `mas install` needs root and prompts for the password itself ("If run without root privileges, mas requests them as necessary"), and the confirmation prompt needs stdin, so the capability declares itself interactive. Pointing the command line tools at Xcode changes what every compiler on the machine uses, including the `xcode-clt` capability's, so `configure` prints `sudo xcode-select --switch ...` and `sudo xcodebuild -license accept` instead of running them, and only when `xcode-select -p` is not already inside an `Xcode.app`.
15. **Arc is kept and flagged, not dropped.** The `arc` cask is live (1.164.0, `Arc.app`, `depends_on macos: >= 13`), so it installs; the browser has been in maintenance since The Browser Company moved to Dia, which is a reason to say so in the capability's `summary` and README line, not a reason to refuse an app the spec asks for. `zen` is live too, and its token is `zen`: `zen-browser` is an old token Homebrew still redirects, and the plan uses the current one.

---

## File structure

| Path | Responsibility |
|---|---|
| `lib/lazy.sh` | gains `cask_app_install` and `cask_app_report` next to `app_installed` (Task 4). |
| `capabilities/k8s/{capability,install,configure,remove}` | kubectl, helm and k9s through mise; `provides="kubectl helm k9s"` (Task 1). |
| `capabilities/lazydocker/{capability,install,configure}` | the Docker TUI on top of Colima; `provides="lazydocker"` (Task 2). |
| `capabilities/docker-dbs/{capability,install,configure}` | the picker that starts localhost database containers (Task 3). |
| `capabilities/{brave,arc,zen}/{capability,install,configure}` | browser casks (Task 4). |
| `capabilities/{slack,zoom,signal,whatsapp,telegram,discord,teams}/{capability,install,configure}` | communication casks (Task 5). |
| `capabilities/{1password,raycast,bruno,notion,typora}/{capability,install,configure}` | productivity casks (Task 6). |
| `capabilities/karabiner/{capability,install,configure}` and `capabilities/karabiner/config/karabiner/karabiner-{right_command,caps_lock}.json` | Karabiner-Elements and the two shipped hyper-key profiles (Task 7). |
| `capabilities/xcode/{capability,install,configure}` | `mas` and the App Store download (Task 8). |
| `tests/capabilities/{k8s,lazydocker,docker-dbs,browsers,communication,productivity,karabiner,xcode}.sh` | one new suite per task; the three cask suites cover their group's capabilities one row at a time. |
| `tests/lib/lazy.sh` | four tests for the two new helpers (Task 4). |
| `README.md`, `CONTRIBUTING.md` | the lazy-capability list and three contributor items (Task 9). |

**Reading this plan mechanically.** Every fenced block whose info string carries `file=<path>` is the complete content of that file after the step. Every edit to an existing file is a pair of blocks, `edit-old=<path>` (text that exists at that point in the execution, quoted exactly and occurring exactly once in the file) followed by `edit-new=<path>` (what replaces it). Blocks without either marker are commands or illustrations and change nothing.

---

### Task 1: `k8s` — kubectl, helm and k9s through mise

**Files:**
- Create: `capabilities/k8s/capability`, `capabilities/k8s/install`, `capabilities/k8s/configure`, `capabilities/k8s/remove`
- Test: `tests/capabilities/k8s.sh`

**Interfaces:**
- Consumes: `have`, `log`, `ok`, `err`, `warn`, `run_cmd` (`lib/core.sh`); `mise_ensure_global <tool> [version]` (`lib/mise.sh`, plan 3b Task 2); `teeup lazy-run` and the shim generator keyed on `provides=` (plan 3b Tasks 1 and 3); `teeup remove`, which runs `capabilities/<cap>/remove` before uninstalling `casks=` and `packages=` (plan 4a Task 2).
- Produces: the capability `k8s` with `tier=lazy`, `requires="mise"`, `provides="kubectl helm k9s"`, no `packages=`, no `casks=`, no `apps=`. Later tasks do not consume it; 4b's `doctor_metadata_check` reads its `provides=` and expects each of the three to resolve to a real binary once it is installed.

**Real-Mac risk:** that `mise use -g kubectl@latest` really puts `kubectl` in `~/.local/share/mise/shims` on macOS and that the aqua backend has a darwin/arm64 build for all three (the registry says it does, and the tests mock mise); that a shell started before the install picks the new binary up only after `mise activate`'s next prompt or a new terminal, which is what `lazy-run`'s final message says.

- [ ] **Step 1: Write the failing test**

```bash file=tests/capabilities/k8s.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# kubectl, helm and k9s arrive through mise, and the binaries mise installs
# land in mise's own shims directory, which the zsh layer puts on PATH ahead
# of teeup's shims. The mise mock below models exactly that: `use -g` records
# the tool and drops an executable into $HOME/.local/share/mise/shims, so the
# round-trip test can prove that a shim call ends in the real command.
# A CI runner or a developer's machine may have kubectl, helm or k9s in
# /usr/bin; hide_host_commands hides those copies by path before any of them
# exists anywhere else, so the mocked install is what provides them.
setup() {
  setup_test_env
  mock_macos_base
  hide_host_commands kubectl helm k9s
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  mock_command_script mise <<'EOF2'
[ "${1:-}" = "-C" ] && shift 2
requested="$HOME/mise-requested"
installed="$HOME/mise-installed"
shims="$HOME/.local/share/mise/shims"
make_tool() {
  mkdir -p "$shims"
  printf '#!/usr/bin/env bash\necho "%s-real $*" >> "$MOCK_LOG"\necho "%s ran: $*"\n' "$1" "$1" > "$shims/$1"
  chmod +x "$shims/$1"
}
case "$1 ${2:-}" in
  "ls --global")
    if [ "${3:-}" = "--installed" ]; then
      grep -qx "$4" "$installed" 2>/dev/null || exit 0
      echo "$4 latest"
      exit 0
    fi
    cat "$requested" 2>/dev/null
    ;;
  "where "*) grep -qx "$2" "$installed" 2>/dev/null || exit 1 ;;
  "install "*)
    printf '%s\n' "$2" >> "$installed"
    make_tool "$2"
    ;;
  "use "*)
    tool="${3%%@*}"
    printf '%s\n' "$tool" >> "$requested"
    printf '%s\n' "$tool" >> "$installed"
    make_tool "$tool"
    ;;
  "unuse "*)
    tool="$3"
    for f in "$requested" "$installed"; do
      [ -f "$f" ] || continue
      grep -vx "$tool" "$f" > "$f.new" 2>/dev/null || true
      mv "$f.new" "$f"
    done
    rm -f "$shims/$tool"
    ;;
esac
exit 0
EOF2
  # lib/ui.sh reaches for gum whenever TEEUP_NO_GUM is empty and gum is on
  # PATH, and /usr/bin is on the harness PATH: the round-trip test drives
  # lazy-run's install question, so gum stays out of it.
  export TEEUP_NO_GUM=1
  TEEUP="$TEEUP_PATH/bin/teeup"
  SHIMS="$TEST_HOME/.local/state/teeup/shims"
  MISE_SHIMS="$TEST_HOME/.local/share/mise/shims"
}

test_install_dry_run_asks_mise_for_the_three_tools() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install k8s 2>&1)"
  assert_contains "$out" "Would execute: mise -C / use -g kubectl@latest" || return 1
  assert_contains "$out" "Would execute: mise -C / use -g helm@latest" || return 1
  assert_contains "$out" "Would execute: mise -C / use -g k9s@latest" || return 1
  assert_contains "$out" "kubectl, helm and k9s are installed through mise." || return 1
  cleanup_test_env
}

test_install_leaves_a_tool_that_is_already_there() {
  setup
  printf 'helm\n' > "$TEST_HOME/mise-requested"
  printf 'helm\n' > "$TEST_HOME/mise-installed"
  local out
  out="$(DRY_RUN=false "$TEEUP" install k8s 2>&1)"
  assert_contains "$out" "Already installed through mise: helm" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g helm" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "use -g kubectl@latest" || return 1
  cleanup_test_env
}

test_install_installs_a_requested_but_missing_tool_without_rewriting_it() {
  setup
  printf 'k9s\n' > "$TEST_HOME/mise-requested"
  local out
  out="$(DRY_RUN=false "$TEEUP" install k8s 2>&1)"
  assert_contains "$out" "k9s is requested by the global mise config but not installed" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install k9s" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g k9s" || return 1
  cleanup_test_env
}

test_install_without_mise_stops_with_the_hint() {
  setup
  export TEEUP_TEST_MISSING="mise"
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" install k8s 2>&1)" || rc=$?
  assert_failure "$rc" "k8s must not claim success without mise" || return 1
  assert_contains "$out" "mise is not installed; run: teeup install mise" || return 1
  unset TEEUP_TEST_MISSING
  cleanup_test_env
}

test_configure_reports_the_kubeconfig() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure k8s 2>&1)"
  assert_contains "$out" "No cluster config yet ($TEST_HOME/.kube/config does not exist)" || return 1
  mkdir -p "$TEST_HOME/.kube"
  printf 'clusters: []\n' > "$TEST_HOME/.kube/config"
  out="$(DRY_RUN=false "$TEEUP" configure k8s 2>&1)"
  assert_contains "$out" "Cluster config in place: $TEST_HOME/.kube/config" || return 1
  out="$(KUBECONFIG="$TEST_HOME/work.yaml" DRY_RUN=false "$TEEUP" configure k8s 2>&1)"
  assert_contains "$out" "KUBECONFIG is set to $TEST_HOME/work.yaml" || return 1
  cleanup_test_env
}

test_shims_exist_after_runtime_configure() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local c
  for c in kubectl helm k9s; do
    assert_file_exists "$SHIMS/$c" || return 1
    [[ -x "$SHIMS/$c" ]] || { echo "$c shim must be executable"; return 1; }
    assert_contains "$(cat "$SHIMS/$c")" "lazy-run k8s $c \"\$@\"" || return 1
  done
  cleanup_test_env
}

test_round_trip_shim_installs_and_execs_kubectl() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  # The shell's lookup: mise's shims ahead of teeup's, as capabilities/zsh's
  # default/env arranges it. Before the install nothing but the teeup shim
  # answers to `kubectl`.
  assert_equals "$SHIMS/kubectl" "$(PATH="$MOCK_BIN:$MISE_SHIMS:$SHIMS" command -v kubectl)" || return 1
  export PATH="$MOCK_BIN:$MISE_SHIMS:/usr/bin:/bin:/usr/sbin:/sbin:$SHIMS"
  local out
  out="$(printf 'y\n' | TEEUP_TEST_TTY=yes DRY_RUN=false "$SHIMS/kubectl" get pods 2>&1)"
  assert_contains "$out" "kubectl is provided by capability k8s. Install now?" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / use -g kubectl@latest" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / use -g helm@latest" || return 1
  assert_contains "$out" "Completed: k8s configure" || return 1
  # The real kubectl ran, with the original arguments.
  assert_contains "$(cat "$MOCK_LOG")" "kubectl-real get pods" || return 1
  assert_contains "$out" "kubectl ran: get pods" || return 1
  "$TEEUP" has k8s || { echo "k8s must be marked installed"; return 1; }
  # A second call finds mise's binary ahead of the shim and installs nothing.
  : > "$MOCK_LOG"
  out="$(TEEUP_TEST_TTY=no "$SHIMS/helm" list 2>&1)"
  assert_equals "helm ran: list" "$out" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  cleanup_test_env
}

test_remove_unuses_the_three_tools() {
  setup
  DRY_RUN=false "$TEEUP" install k8s >/dev/null 2>&1
  : > "$MOCK_LOG"
  local out c
  out="$(DRY_RUN=false "$TEEUP" remove k8s 2>&1)"
  for c in kubectl helm k9s; do
    assert_contains "$(cat "$MOCK_LOG")" "mise -C / unuse --global $c" || return 1
    [[ ! -e "$MISE_SHIMS/$c" ]] || { echo "$c should be gone from mise's shims"; return 1; }
  done
  assert_contains "$out" "Removed k8s." || return 1
  "$TEEUP" has k8s && { echo "k8s must not read as installed after remove"; return 1; }
  cleanup_test_env
}

test_the_tier_is_lazy() {
  setup
  assert_contains "$("$TEEUP" list --tier lazy)" "k8s" || return 1
  if grep -qx "k8s" "$TEEUP_PATH/capabilities/daily.list" "$TEEUP_PATH/capabilities/core.list"; then
    echo "k8s is lazy but sits in a tier list"
    return 1
  fi
  cleanup_test_env
}

echo "capabilities/k8s"
run_test "install dry run asks mise for the three tools" test_install_dry_run_asks_mise_for_the_three_tools
run_test "install leaves a tool that is already there" test_install_leaves_a_tool_that_is_already_there
run_test "install installs a requested but missing tool" test_install_installs_a_requested_but_missing_tool_without_rewriting_it
run_test "install without mise stops with the hint" test_install_without_mise_stops_with_the_hint
run_test "configure reports the kubeconfig" test_configure_reports_the_kubeconfig
run_test "shims exist after runtime configure" test_shims_exist_after_runtime_configure
run_test "round trip: shim installs and execs kubectl" test_round_trip_shim_installs_and_execs_kubectl
run_test "remove unuses the three tools" test_remove_unuses_the_three_tools
run_test "the tier is lazy" test_the_tier_is_lazy
print_summary
```

- [ ] **Step 2: Run it and watch every test fail**

Run: `chmod +x tests/capabilities/k8s.sh && bash tests/capabilities/k8s.sh`
Expected: `Summary: 0/9 passed`, every failure tracing back to `Unknown capability: k8s` (the `tier is lazy` test fails with `Missing: k8s`).

- [ ] **Step 3: Write the metadata**

```ini file=capabilities/k8s/capability
summary="Kubernetes tools: kubectl, helm and k9s through mise"
group=containers
tier=lazy
requires="mise"
provides="kubectl helm k9s"
packages=""
casks=""
apps=""
interactive=false
```

- [ ] **Step 4: Write the install script**

```bash file=capabilities/k8s/install
#!/usr/bin/env bash
# The three tools come from mise rather than from Homebrew or MacPorts (spec
# interview table: "k8s: kubectl, helm, k9s via mise, lazy"), so one `mise
# upgrade` inside `teeup update` keeps all three current and a MacPorts
# machine gets the same versions as a Homebrew one. The mise registry names
# are the command names: kubectl is aqua:kubernetes/kubernetes/kubectl, helm
# is aqua:helm/helm, k9s is aqua:derailed/k9s.
if ! have mise; then
  err "mise is not installed; run: teeup install mise"
  exit 1
fi
k8s_missing=""
for k8s_tool in kubectl helm k9s; do
  mise_ensure_global "$k8s_tool" latest || k8s_missing="$k8s_missing $k8s_tool"
done
if [[ -n "$k8s_missing" ]]; then
  err "mise could not install:$k8s_missing"
  exit 1
fi
ok "kubectl, helm and k9s are installed through mise."
```

- [ ] **Step 5: Write the configure script**

```bash file=capabilities/k8s/configure
#!/usr/bin/env bash
# teeup writes nothing under ~/.kube: a kubeconfig is handed out by whoever
# runs the cluster, and k9s and helm both read whatever kubectl reads.
if [[ -n "${KUBECONFIG:-}" ]]; then
  log "KUBECONFIG is set to $KUBECONFIG, so kubectl reads that instead of $HOME/.kube/config."
elif [[ -f "$HOME/.kube/config" ]]; then
  log "Cluster config in place: $HOME/.kube/config"
else
  log "No cluster config yet ($HOME/.kube/config does not exist); your cluster provider writes it, for example with: aws eks update-kubeconfig"
fi
log "kubectl, helm and k9s run from mise; teeup update upgrades them with mise upgrade."
```

- [ ] **Step 6: Write the remove script**

`teeup remove k8s` has no `packages=` or `casks=` to undo, so the capability undoes its own mise installs. `mise unuse --global <tool>` removes the request from the global config and prunes the installation; a tool that was never requested exits 0 (verified on mise 2026.9.4).

```bash file=capabilities/k8s/remove
#!/usr/bin/env bash
# k8s declares no packages= and no casks=, so `teeup remove` has nothing of
# its own to uninstall here: the three tools belong to mise. `mise unuse
# --global <tool>` drops the request from the global config and prunes the
# installation, which is the inverse of mise_ensure_global. A tool that was
# never requested is not an error there.
if have mise; then
  for k8s_tool in kubectl helm k9s; do
    run_cmd mise -C / unuse --global "$k8s_tool" || warn "Could not remove $k8s_tool from the global mise config."
  done
else
  log "mise is not installed here, so there is nothing to remove."
fi
```

- [ ] **Step 7: Make the three scripts executable and run the suite**

Run: `chmod +x capabilities/k8s/install capabilities/k8s/configure capabilities/k8s/remove && bash tests/capabilities/k8s.sh`
Expected: `Summary: 9/9 passed`.

- [ ] **Step 8: Run the whole suite and the checks**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning capabilities/k8s/install capabilities/k8s/configure capabilities/k8s/remove tests/capabilities/k8s.sh && git diff --check`
Expected: the suite count printed before this task, plus 1; `commands --check` silent with exit 0; shellcheck and `git diff --check` silent.

- [ ] **Step 9: Commit**

```bash
git add capabilities/k8s tests/capabilities/k8s.sh
git commit -m "Add the k8s lazy capability"
```

---

### Task 2: `lazydocker` — the container TUI on top of Colima

**Files:**
- Create: `capabilities/lazydocker/capability`, `capabilities/lazydocker/install`, `capabilities/lazydocker/configure`
- Test: `tests/capabilities/lazydocker.sh`

**Interfaces:**
- Consumes: `pkg_install <pkg> [command]` (`lib/pkg.sh`); `have`, `log` (`lib/core.sh`); `capabilities/colima` as its `requires=` (plan 3b Task 5); `teeup remove`'s metadata path, which uninstalls the `packages=` entry (plan 4a Task 2).
- Produces: the capability `lazydocker` with `tier=lazy`, `requires="colima"`, `provides="lazydocker"`, `packages="lazydocker"`. Nothing later consumes it.

**Real-Mac risk:** that `colima status` exits non-zero while the VM is stopped and zero while it runs (plan 3b's `colima` capability relies on the same behaviour, and both are mocked here); that lazydocker reaches Colima's socket with no `DOCKER_HOST` of its own, which is true when Colima has set the default docker context and is the reason this capability installs nothing else.

- [ ] **Step 1: Write the failing test**

```bash file=tests/capabilities/lazydocker.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# lazydocker requires colima, so `teeup install lazydocker` walks the chain
# xcode-clt, package-manager, colima, lazydocker. The dry run keeps that
# cheap; the configure tests mock colima directly and run only this
# capability. A Linux CI runner has docker in /usr/bin and a developer's
# machine may have lazydocker or colima there, so those are hidden by path
# before anything else mocks them.
setup() {
  setup_test_env
  mock_macos_base
  hide_host_commands colima docker docker-compose lazydocker
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  TEEUP="$TEEUP_PATH/bin/teeup"
  SHIMS="$TEST_HOME/.local/state/teeup/shims"
}

mock_colima() {
  # $1 is "running" or "stopped".
  mock_command_script colima <<EOF2
case "\$1" in
  status) [ "$1" = "running" ] || exit 1 ;;
esac
exit 0
EOF2
}

test_install_dry_run_gets_the_formula_after_colima() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install lazydocker 2>&1)"
  assert_contains "$out" "Would execute: brew install colima" || return 1
  assert_contains "$out" "Would execute: brew install lazydocker" || return 1
  cleanup_test_env
}

test_install_on_macports_gets_the_port() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install lazydocker 2>&1)"
  assert_contains "$out" "Would execute: sudo port install lazydocker" || return 1
  cleanup_test_env
}

test_configure_reports_a_running_colima() {
  setup
  mock_colima running
  local out
  out="$(DRY_RUN=false "$TEEUP" configure lazydocker 2>&1)"
  assert_contains "$out" "Colima is running; open the UI with: lazydocker" || return 1
  cleanup_test_env
}

test_configure_reports_a_stopped_colima() {
  setup
  mock_colima stopped
  local out
  out="$(DRY_RUN=false "$TEEUP" configure lazydocker 2>&1)"
  assert_contains "$out" "Colima is installed but not running; start it with: colima start" || return 1
  cleanup_test_env
}

test_configure_reports_a_missing_colima() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure lazydocker 2>&1)"
  assert_contains "$out" "Colima is not on PATH yet" || return 1
  cleanup_test_env
}

test_configure_runs_nothing_privileged() {
  setup
  mock_colima running
  DRY_RUN=false "$TEEUP" configure lazydocker >/dev/null
  assert_not_contains "$(cat "$MOCK_LOG")" "sudo" || return 1
  cleanup_test_env
}

test_the_shim_points_at_this_capability() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  assert_file_exists "$SHIMS/lazydocker" || return 1
  assert_contains "$(cat "$SHIMS/lazydocker")" 'lazy-run lazydocker lazydocker "$@"' || return 1
  cleanup_test_env
}

test_remove_uninstalls_the_formula_from_metadata() {
  setup
  mock_colima running
  mock_command_script brew <<'EOF2'
case "$1 ${2:-} ${3:-}" in
  "list --formula lazydocker") exit 0 ;;
  "list "*) exit 1 ;;
esac
exit 0
EOF2
  DRY_RUN=false "$TEEUP" install lazydocker >/dev/null 2>&1
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=false "$TEEUP" remove lazydocker 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall lazydocker" || return 1
  assert_contains "$out" "Removed lazydocker." || return 1
  cleanup_test_env
}

test_the_tier_is_lazy() {
  setup
  assert_contains "$("$TEEUP" list --tier lazy)" "lazydocker" || return 1
  if grep -qx "lazydocker" "$TEEUP_PATH/capabilities/daily.list" "$TEEUP_PATH/capabilities/core.list"; then
    echo "lazydocker is lazy but sits in a tier list"
    return 1
  fi
  cleanup_test_env
}

echo "capabilities/lazydocker"
run_test "install dry run gets the formula after colima" test_install_dry_run_gets_the_formula_after_colima
run_test "install on macports gets the port" test_install_on_macports_gets_the_port
run_test "configure reports a running colima" test_configure_reports_a_running_colima
run_test "configure reports a stopped colima" test_configure_reports_a_stopped_colima
run_test "configure reports a missing colima" test_configure_reports_a_missing_colima
run_test "configure runs nothing privileged" test_configure_runs_nothing_privileged
run_test "the shim points at this capability" test_the_shim_points_at_this_capability
run_test "remove uninstalls the formula from metadata" test_remove_uninstalls_the_formula_from_metadata
run_test "the tier is lazy" test_the_tier_is_lazy
print_summary
```

- [ ] **Step 2: Run it and watch it fail**

Run: `chmod +x tests/capabilities/lazydocker.sh && bash tests/capabilities/lazydocker.sh`
Expected: `Summary: 1/9 passed`. The one that passes early is `configure runs nothing privileged`, which asserts that nothing was run; the other eight fail on `Unknown capability: lazydocker`.

- [ ] **Step 3: Write the metadata**

```ini file=capabilities/lazydocker/capability
summary="lazydocker, a terminal UI for the containers Colima runs"
group=containers
tier=lazy
requires="colima"
provides="lazydocker"
packages="lazydocker"
casks=""
apps=""
interactive=false
```

- [ ] **Step 4: Write the install script**

```bash file=capabilities/lazydocker/install
#!/usr/bin/env bash
# Formula and port are both named lazydocker (0.25.2 in each), so the
# package manager is the whole install. requires="colima" brings the Docker
# CLI and a started VM first: a TUI over a daemon that is not there has
# nothing to draw.
pkg_install lazydocker lazydocker
```

- [ ] **Step 5: Write the configure script**

```bash file=capabilities/lazydocker/configure
#!/usr/bin/env bash
# lazydocker talks to the Docker socket, and on macOS that socket is Colima's
# and belongs to the user, so nothing here needs elevation. (Omarchy's
# omarchy-launch-docker-tui wraps lazydocker in pkexec only because the Arch
# daemon's socket is owned by root.)
#
# The user config is lazydocker's own, at
# ~/Library/Application Support/jesseduffield/lazydocker/config.yml, and the
# app writes it; teeup ships no opinion about it.
if ! have colima; then
  log "Colima is not on PATH yet, so there is no daemon to draw; install it with: teeup install colima"
elif colima status >/dev/null 2>&1; then
  log "Colima is running; open the UI with: lazydocker"
else
  log "Colima is installed but not running; start it with: colima start, then run: lazydocker"
fi
```

- [ ] **Step 6: Make the scripts executable and run the suite**

Run: `chmod +x capabilities/lazydocker/install capabilities/lazydocker/configure && bash tests/capabilities/lazydocker.sh`
Expected: `Summary: 9/9 passed`.

- [ ] **Step 7: Run the whole suite and the checks**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning capabilities/lazydocker/install capabilities/lazydocker/configure tests/capabilities/lazydocker.sh && git diff --check`
Expected: the suite count printed before this task, plus 1; everything else silent.

- [ ] **Step 8: Commit**

```bash
git add capabilities/lazydocker tests/capabilities/lazydocker.sh
git commit -m "Add the lazydocker lazy capability"
```

---

### Task 3: `docker-dbs` — the localhost database picker

**Files:**
- Create: `capabilities/docker-dbs/capability`, `capabilities/docker-dbs/install`, `capabilities/docker-dbs/configure`
- Test: `tests/capabilities/docker-dbs.sh`

**Interfaces:**
- Consumes: `have`, `log`, `ok`, `warn`, `err`, `run_cmd` (`lib/core.sh`); `answers_get <KEY> [default]` (`lib/answers.sh`); `ui_choose <prompt> <option...>` (`lib/ui.sh`); `capabilities/colima` as its `requires=` (plan 3b Task 5).
- Produces: the capability `docker-dbs` with `tier=lazy`, `interactive=true`, no `provides=` (so no shim) and no `packages=`/`casks=` (so `teeup remove docker-dbs` clears the marker and leaves the containers alone, which is right: a database holds data). `db_conflict_check <requested>` warns about a port two of the requested databases both publish (MySQL and MariaDB both bind 3306) before either one starts, since only one of them will actually get the port. The answers key `TEEUP_DBS` is documented in Task 9's README section.

**Real-Mac risk:** that Colima forwards a container port published on the guest's `127.0.0.1` to the host's `127.0.0.1` (its README lists "Automatic Port Forwarding" as a feature, and the tests mock `docker` entirely); that the five images pull and start under Colima's default 2 CPU / 2 GiB VM, where MySQL and MongoDB are the heavy two; that `--restart unless-stopped` brings a container back after `colima stop` and `colima start`.

- [ ] **Step 1: Write the failing test**

```bash file=tests/capabilities/docker-dbs.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# The docker mock keeps two lists in $HOME: every container it was asked to
# create, and the ones that are running. That is enough to prove the three
# paths configure has (create, start an existing one, report a running one).
# A Linux CI runner has a real docker in /usr/bin, so it is hidden by path
# before the mock is written.
setup() {
  setup_test_env
  mock_macos_base
  hide_host_commands docker colima docker-compose
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  # A published host port is bound for as long as some container in
  # $up claims it (tracked in $ports as "hostport:name" lines): a second
  # `docker run` publishing an already-bound port fails to bind, exactly like
  # a real docker daemon, and the loser is never added to $all or $up.
  mock_command_script docker <<'EOF2'
all="$HOME/containers-all"
up="$HOME/containers-running"
ports="$HOME/containers-ports"
case "$1 ${2:-}" in
  "ps -a") cat "$all" 2>/dev/null ;;
  "ps --format") cat "$up" 2>/dev/null ;;
  "run "*)
    name="" hostport=""
    while [ $# -gt 0 ]; do
      if [ "$1" = "--name" ]; then name="$2"; fi
      if [ "$1" = "-p" ]; then hostport="${2#*:}"; hostport="${hostport%%:*}"; fi
      shift
    done
    if [ -n "$hostport" ] && grep -q "^$hostport:" "$ports" 2>/dev/null; then
      bound="$(grep "^$hostport:" "$ports" 2>/dev/null | tail -1 | cut -d: -f2)"
      if grep -qx "$bound" "$up" 2>/dev/null; then
        echo "docker: Error response from daemon: Bind for 127.0.0.1:$hostport failed: port is already allocated." >&2
        exit 1
      fi
    fi
    printf '%s\n' "$name" >> "$all"
    printf '%s\n' "$name" >> "$up"
    printf '%s:%s\n' "$hostport" "$name" >> "$ports"
    ;;
  "start "*) printf '%s\n' "$2" >> "$up" ;;
esac
exit 0
EOF2
  # ui_choose calls gum whenever TEEUP_NO_GUM is empty and gum is on PATH,
  # and /usr/bin is on the harness PATH: the picker tests need the plain
  # numbered fallback, which reads the answer from stdin.
  export TEEUP_NO_GUM=1
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_configure_starts_the_database_the_answer_names() {
  setup
  export TEEUP_DBS="postgres"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure docker-dbs 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "docker run -d --restart unless-stopped -p 127.0.0.1:5432:5432 --name postgres18 -e POSTGRES_HOST_AUTH_METHOD=trust postgres:18" || return 1
  assert_contains "$out" "Started postgres18 from postgres:18 on 127.0.0.1:5432" || return 1
  assert_contains "$out" "psql postgres://postgres@127.0.0.1:5432/postgres" || return 1
  unset TEEUP_DBS
  cleanup_test_env
}

test_a_database_without_environment_gets_no_e_flags() {
  setup
  export TEEUP_DBS="redis"
  DRY_RUN=false "$TEEUP" configure docker-dbs >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "--name redis redis:7" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "--name redis -e" || return 1
  unset TEEUP_DBS
  cleanup_test_env
}

test_every_image_and_port_matches_the_table() {
  setup
  export TEEUP_DBS="postgres mysql mariadb redis mongo"
  local out log
  out="$(DRY_RUN=false "$TEEUP" configure docker-dbs 2>&1)"
  log="$(cat "$MOCK_LOG")"
  assert_contains "$log" "-p 127.0.0.1:3306:3306 --name mysql8 -e MYSQL_ROOT_PASSWORD= -e MYSQL_ALLOW_EMPTY_PASSWORD=true mysql:8.4" || return 1
  assert_contains "$log" "-p 127.0.0.1:3306:3306 --name mariadb11 -e MARIADB_ROOT_PASSWORD= -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=true mariadb:11.8" || return 1
  assert_contains "$log" "-p 127.0.0.1:6379:6379 --name redis redis:7" || return 1
  assert_contains "$log" "-p 127.0.0.1:27017:27017 --name mongodb -e MONGO_INITDB_ROOT_USERNAME=admin -e MONGO_INITDB_ROOT_PASSWORD=admin123 mongo:noble" || return 1
  # Both MySQL and MariaDB publish 3306, so the second one cannot have it.
  # The warning is checked before either one starts: the mock models the real
  # docker daemon's refusal, so mariadb11's docker run is attempted (logged
  # above) but fails to bind, and only mysql8 ends up running.
  assert_contains "$out" "mysql and mariadb both publish 3306" || return 1
  assert_contains "$(cat "$TEST_HOME/containers-running")" "mysql8" || return 1
  assert_not_contains "$(cat "$TEST_HOME/containers-running")" "mariadb11" "the port loser must not be reported as started" || return 1
  assert_not_contains "$log" "0.0.0.0:" || return 1
  unset TEEUP_DBS
  cleanup_test_env
}

test_an_existing_stopped_container_is_started_not_created() {
  setup
  printf 'postgres18\n' > "$TEST_HOME/containers-all"
  export TEEUP_DBS="postgres"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure docker-dbs 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "docker start postgres18" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "docker run" || return 1
  assert_contains "$out" "Started the existing postgres18 on 127.0.0.1:5432" || return 1
  unset TEEUP_DBS
  cleanup_test_env
}

test_a_running_container_is_left_alone() {
  setup
  printf 'postgres18\n' > "$TEST_HOME/containers-all"
  printf 'postgres18\n' > "$TEST_HOME/containers-running"
  export TEEUP_DBS="postgres"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure docker-dbs 2>&1)"
  assert_contains "$out" "Already running: postgres18 on 127.0.0.1:5432" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "docker run" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "docker start" || return 1
  unset TEEUP_DBS
  cleanup_test_env
}

test_the_picker_asks_and_starts_the_choice() {
  setup
  local out
  out="$(printf '2\n' | DRY_RUN=false "$TEEUP" configure docker-dbs 2>&1)"
  assert_contains "$out" "Which database should run on localhost?" || return 1
  assert_contains "$out" "2) mysql" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "--name mysql8" || return 1
  cleanup_test_env
}

test_the_picker_takes_none_for_an_answer() {
  setup
  local out
  out="$(printf '6\n' | DRY_RUN=false "$TEEUP" configure docker-dbs 2>&1)"
  assert_contains "$out" "Nothing started. Run teeup configure docker-dbs again when you want one." || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "docker run" || return 1
  cleanup_test_env
}

test_dry_run_starts_nothing() {
  setup
  export TEEUP_DBS="mongo"
  local out
  out="$(DRY_RUN=true "$TEEUP" configure docker-dbs 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: docker run -d --restart unless-stopped -p 127.0.0.1:27017:27017 --name mongodb" || return 1
  [[ ! -e "$TEST_HOME/containers-all" ]] || { echo "dry run created a container"; return 1; }
  unset TEEUP_DBS
  cleanup_test_env
}

test_configure_without_docker_stops_with_the_hint() {
  setup
  export TEEUP_DBS="redis"
  export TEEUP_TEST_MISSING="docker"
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" configure docker-dbs 2>&1)" || rc=$?
  assert_failure "$rc" "configure must fail without docker" || return 1
  assert_contains "$out" "docker is not on PATH; install Colima first with: teeup install colima" || return 1
  unset TEEUP_DBS TEEUP_TEST_MISSING
  cleanup_test_env
}

test_a_home_with_a_space_and_a_dollar_still_reads_the_answer() {
  setup
  export HOME="$TEST_HOME/od d \$x"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_STATE_HOME="$HOME/.local/state"
  mkdir -p "$XDG_CONFIG_HOME/teeup"
  printf 'TEEUP_DBS="redis"\n' > "$XDG_CONFIG_HOME/teeup/answers"
  DRY_RUN=false "$TEEUP" configure docker-dbs >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "--name redis redis:7" || return 1
  cleanup_test_env
}

test_it_is_lazy_interactive_and_shimless() {
  setup
  assert_contains "$("$TEEUP" list --tier lazy)" "docker-dbs" || return 1
  assert_equals "true" "$(cd "$TEEUP_PATH" && bash -c 'source lib/all.sh; cap_meta_get docker-dbs interactive')" || return 1
  assert_equals "" "$(cd "$TEEUP_PATH" && bash -c 'source lib/all.sh; cap_meta_get docker-dbs provides')" || return 1
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  [[ ! -e "$TEST_HOME/.local/state/teeup/shims/docker-dbs" ]] || { echo "docker-dbs must not get a shim"; return 1; }
  cleanup_test_env
}

echo "capabilities/docker-dbs"
run_test "configure starts the database the answer names" test_configure_starts_the_database_the_answer_names
run_test "a database without environment gets no -e flags" test_a_database_without_environment_gets_no_e_flags
run_test "every image and port matches the table" test_every_image_and_port_matches_the_table
run_test "an existing stopped container is started, not created" test_an_existing_stopped_container_is_started_not_created
run_test "a running container is left alone" test_a_running_container_is_left_alone
run_test "the picker asks and starts the choice" test_the_picker_asks_and_starts_the_choice
run_test "the picker takes none for an answer" test_the_picker_takes_none_for_an_answer
run_test "dry run starts nothing" test_dry_run_starts_nothing
run_test "configure without docker stops with the hint" test_configure_without_docker_stops_with_the_hint
run_test "a home with a space and a dollar still reads the answer" test_a_home_with_a_space_and_a_dollar_still_reads_the_answer
run_test "it is lazy, interactive and shimless" test_it_is_lazy_interactive_and_shimless
print_summary
```

- [ ] **Step 2: Run it and watch every test fail**

Run: `chmod +x tests/capabilities/docker-dbs.sh && bash tests/capabilities/docker-dbs.sh`
Expected: `Summary: 0/11 passed`, every failure tracing back to `Unknown capability: docker-dbs`.

- [ ] **Step 3: Write the metadata**

`interactive=true` is what keeps `cap_run` from redirecting stdin from `/dev/null`, which the picker needs.

```ini file=capabilities/docker-dbs/capability
summary="Local database containers on Colima: PostgreSQL, MySQL, MariaDB, Redis, MongoDB"
group=containers
tier=lazy
requires="colima"
provides=""
packages=""
casks=""
apps=""
interactive=true
```

- [ ] **Step 4: Write the install script**

```bash file=capabilities/docker-dbs/install
#!/usr/bin/env bash
# There is nothing to download at install time: the images are pulled by the
# first `docker run`, and requires="colima" has already installed the Docker
# CLI and started the VM. Picking a database is configure's job, so this
# capability can be asked for again whenever another one is wanted.
if have docker; then
  log "Pick a database with: teeup configure docker-dbs"
else
  warn "docker is not on PATH yet; install Colima first with: teeup install colima"
fi
```

- [ ] **Step 5: Write the configure script**

The table is Omarchy's `omarchy-install-docker-dbs`, checked image by image against Docker Hub (every one of the five publishes an `arm64/v8` manifest, and every environment variable below is documented on its image's page).

```bash file=capabilities/docker-dbs/configure
#!/usr/bin/env bash
# Omarchy's omarchy-install-docker-dbs, ported to Colima: the same images,
# tags, container names, published ports and environment variables, without
# its `sudo` (Colima runs the daemon as you, so the socket is yours) and
# without its MSSQL row (Microsoft publishes a single linux/amd64 manifest
# for mssql/server, so there is no image for an Apple Silicon Mac).
#
# Every container publishes to 127.0.0.1 only, so a database that trusts
# local connections is not reachable from the network. Colima forwards a
# published port to the host by itself ("Automatic Port Forwarding").
#
# TEEUP_DBS in the answers file or machines/<hostname>.conf skips the
# question: TEEUP_DBS="postgres redis" starts those two and asks nothing.
# Without it the picker asks once, and running this configure again is how
# another database is added.

db_container=""
db_image=""
db_port=""
db_hint=""
db_env=()

# db_spec <name> -> fills db_container, db_image, db_port, db_hint, db_env.
db_spec() {
  db_env=()
  case "$1" in
    postgres)
      db_container="postgres18"; db_image="postgres:18"; db_port="5432"
      db_env=(-e POSTGRES_HOST_AUTH_METHOD=trust)
      db_hint="psql postgres://postgres@127.0.0.1:5432/postgres"
      ;;
    mysql)
      db_container="mysql8"; db_image="mysql:8.4"; db_port="3306"
      db_env=(-e MYSQL_ROOT_PASSWORD= -e MYSQL_ALLOW_EMPTY_PASSWORD=true)
      db_hint="mysql -h 127.0.0.1 -P 3306 -u root"
      ;;
    mariadb)
      db_container="mariadb11"; db_image="mariadb:11.8"; db_port="3306"
      db_env=(-e MARIADB_ROOT_PASSWORD= -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=true)
      db_hint="mysql -h 127.0.0.1 -P 3306 -u root"
      ;;
    redis)
      db_container="redis"; db_image="redis:7"; db_port="6379"
      db_hint="redis-cli -h 127.0.0.1 -p 6379"
      ;;
    mongo)
      db_container="mongodb"; db_image="mongo:noble"; db_port="27017"
      db_env=(-e MONGO_INITDB_ROOT_USERNAME=admin -e MONGO_INITDB_ROOT_PASSWORD=admin123)
      db_hint="mongosh mongodb://admin:admin123@127.0.0.1:27017/"
      ;;
    *) return 1 ;;
  esac
  return 0
}

# db_start <name>
# Idempotent, unlike the Omarchy original: a container that is already there
# is started rather than created again, which is what makes this configure
# safe to run as often as a database is wanted. The array expansion is
# written ${db_env[@]+"${db_env[@]}"} because bash 3.2 treats "${db_env[@]}"
# on an empty array as an unbound variable under set -u, and redis takes no
# environment.
db_start() {
  db_spec "$1" || { warn "Unknown database '$1'; known names are postgres mysql mariadb redis mongo."; return 1; }
  db_all=" $(docker ps -a --format '{{.Names}}' 2>/dev/null | tr '\n' ' ') "
  db_up=" $(docker ps --format '{{.Names}}' 2>/dev/null | tr '\n' ' ') "
  case "$db_up" in
    *" $db_container "*)
      ok "Already running: $db_container on 127.0.0.1:$db_port"
      log "Connect with: $db_hint"
      return 0
      ;;
  esac
  case "$db_all" in
    *" $db_container "*)
      run_cmd docker start "$db_container" || { warn "Could not start the existing container $db_container."; return 1; }
      ok "Started the existing $db_container on 127.0.0.1:$db_port"
      log "Connect with: $db_hint"
      return 0
      ;;
  esac
  run_cmd docker run -d --restart unless-stopped -p "127.0.0.1:$db_port:$db_port" --name "$db_container" ${db_env[@]+"${db_env[@]}"} "$db_image" \
    || { warn "Could not start $db_container from $db_image."; return 1; }
  ok "Started $db_container from $db_image on 127.0.0.1:$db_port"
  log "Connect with: $db_hint"
  return 0
}

# db_conflict_check <requested>
# Warns about a port two requested databases both publish (MySQL and MariaDB
# both bind 3306) before anything starts. A check keyed off which containers
# actually came up cannot catch this: docker refuses the second bind, so the
# loser never starts and a warning keyed off db_started can never fire for
# the exact case it exists to cover. No `local`, like the rest of this
# script: capability scripts run once, top to bottom. Bash-3.2-safe: no
# associative arrays, just a space-separated "port:name:container" list and
# a plain loop.
db_conflict_check() {
  requested="$1"; seen=""
  for name in $requested; do
    if [[ "$name" == "none" ]]; then continue; fi
    db_spec "$name" || continue
    port="$db_port"; container="$db_container"
    prior_name=""; prior_container=""
    for entry in $seen; do
      case "$entry" in
        "$port:"*)
          prior_name="${entry#*:}"; prior_name="${prior_name%%:*}"
          prior_container="${entry##*:}"
          ;;
      esac
    done
    if [[ -n "$prior_name" ]]; then
      warn "$prior_name and $name both publish $port; only one of them can bind it. $prior_name will start; start $name once you free the port with: docker stop $prior_container"
    fi
    seen="$seen $port:$name:$container"
  done
}

if ! have docker; then
  err "docker is not on PATH; install Colima first with: teeup install colima"
  exit 1
fi

db_selection="$(answers_get TEEUP_DBS)"
if [[ -z "$db_selection" ]]; then
  db_selection="$(ui_choose "Which database should run on localhost?" postgres mysql mariadb redis mongo none)"
fi

db_conflict_check "$db_selection"

db_started=""
for db_name in $db_selection; do
  if [[ "$db_name" == "none" ]]; then
    log "Nothing started. Run teeup configure docker-dbs again when you want one."
    continue
  fi
  if db_start "$db_name"; then
    db_started="$db_started $db_name"
  fi
done

if [[ -n "$db_started" ]]; then
  log "These containers accept local connections without a password, which is what makes them useful for development; they listen on 127.0.0.1 only."
  log "Stop one with: docker stop <name>. Remove one with: docker rm -f <name>."
fi
```

- [ ] **Step 6: Make the scripts executable and run the suite**

Run: `chmod +x capabilities/docker-dbs/install capabilities/docker-dbs/configure && bash tests/capabilities/docker-dbs.sh`
Expected: `Summary: 11/11 passed`.

- [ ] **Step 7: Run the whole suite and the checks**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning capabilities/docker-dbs/install capabilities/docker-dbs/configure tests/capabilities/docker-dbs.sh && git diff --check`
Expected: the suite count printed before this task, plus 1; everything else silent.

- [ ] **Step 8: Commit**

```bash
git add capabilities/docker-dbs tests/capabilities/docker-dbs.sh
git commit -m "Add the docker-dbs lazy capability"
```

---

### Task 4: the GUI-cask helpers, and the browsers `brave`, `arc` and `zen`

**Files:**
- Modify: `lib/lazy.sh` (two functions appended), `tests/lib/lazy.sh` (three tests appended)
- Create: `capabilities/brave/{capability,install,configure}`, `capabilities/arc/{capability,install,configure}`, `capabilities/zen/{capability,install,configure}`
- Test: `tests/capabilities/browsers.sh`

**Interfaces:**
- Consumes: `casks_supported`, `cask_install <cask>` (`lib/pkg.sh`); `app_installed <app>` (`lib/lazy.sh`, plan 3b Task 1); `log`, `warn` (`lib/core.sh`); `teeup launch` (plan 3b Task 4) and `teeup remove` (plan 4a Task 2), both metadata-driven.
- Produces, in `lib/lazy.sh` and used by Tasks 5, 6 and 7:
  - `cask_app_install <cask> <app name> <download url>` — `cask_install` on Homebrew, a warning naming the download page on MacPorts, and the return code of `cask_install` in the first case.
  - `cask_app_report <app name> [extra line]` — one line saying whether `<app>.app` is in place, then the optional extra line; always returns 0.
  - the capabilities `brave` (cask `brave-browser`, app `Brave Browser`), `arc` (cask `arc`, app `Arc`) and `zen` (cask `zen`, app `Zen`), all `group=browsers`, `tier=lazy`, `requires="package-manager"`, no `provides=`.

**Real-Mac risk:** that each cask's pkg or app artifact lands as `<app>.app` in `/Applications` rather than somewhere else (the tokens, the bundle names and the `depends_on macos` floors come from Homebrew's cask API, and `TEEUP_APPS_DIR` stands in for `/Applications` in every test); that Arc and Zen still install on the machine's macOS version (Arc and Brave both declare macOS 13 or newer).

- [ ] **Step 1: Write the failing capability test**

```bash file=tests/capabilities/browsers.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# The three browser capabilities have one shape, so the table below is the
# whole difference between them: capability name, cask token, application
# bundle name. Every assertion still names each capability's own values, so a
# wrong token fails on the row that owns it.
browser_rows() {
  cat <<'EOF2'
brave brave-browser Brave Browser
arc arc Arc
zen zen Zen
EOF2
}

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  mock_command open 0 ""
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  mkdir -p "$TEEUP_APPS_DIR"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_each_install_gets_its_own_cask() {
  setup
  local cap cask app out
  while read -r cap cask app; do
    out="$(DRY_RUN=true "$TEEUP" install "$cap" 2>&1)"
    assert_contains "$out" "Would execute: brew install --cask $cask" || return 1
    assert_not_contains "$out" "MacPorts" || return 1
  done < <(browser_rows)
  cleanup_test_env
}

test_each_install_points_at_a_download_page_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local cap cask app out rc
  while read -r cap cask app; do
    rc=0
    out="$(DRY_RUN=true "$TEEUP" install "$cap" 2>&1)" || rc=$?
    assert_success "$rc" "$cap must not fail on a MacPorts machine" || return 1
    assert_contains "$out" "$app is a cask and MacPorts has none; download it from https://" || return 1
    assert_not_contains "$out" "brew install --cask" || return 1
    assert_not_contains "$out" "port install $cask" || return 1
  done < <(browser_rows)
  cleanup_test_env
}

test_each_configure_reports_its_app() {
  setup
  local cap cask app out
  while read -r cap cask app; do
    out="$(DRY_RUN=false "$TEEUP" configure "$cap" 2>&1)"
    assert_contains "$out" "$app.app is not in $TEEUP_APPS_DIR" || return 1
    mkdir -p "$TEEUP_APPS_DIR/$app.app"
    out="$(DRY_RUN=false "$TEEUP" configure "$cap" 2>&1)"
    assert_contains "$out" "$app is installed; open it with: open -a '$app'" || return 1
  done < <(browser_rows)
  cleanup_test_env
}

test_each_configure_writes_nothing() {
  setup
  local cap cask app
  while read -r cap cask app; do
    DRY_RUN=false "$TEEUP" configure "$cap" >/dev/null
  done < <(browser_rows)
  # answers_load's hostname lookup is the harness's, not a capability's.
  assert_equals "" "$(grep -v '^hostname' "$MOCK_LOG" || true)" "a configure ran a command" || return 1
  [[ ! -e "$TEST_HOME/.config/teeup/answers" ]] || { echo "a configure wrote an answer"; return 1; }
  cleanup_test_env
}

test_each_is_lazy_launchable_and_shimless() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local cap cask app
  while read -r cap cask app; do
    assert_contains "$("$TEEUP" list --tier lazy)" "$cap" || return 1
    assert_equals "$app" "$(cd "$TEEUP_PATH" && bash -c "source lib/all.sh; cap_meta_get $cap apps")" || return 1
    assert_equals "" "$(cd "$TEEUP_PATH" && bash -c "source lib/all.sh; cap_meta_get $cap provides")" || return 1
    [[ ! -e "$TEST_HOME/.local/state/teeup/shims/$cap" ]] || { echo "$cap must not get a shim"; return 1; }
    if grep -qx "$cap" "$TEEUP_PATH/capabilities/daily.list" "$TEEUP_PATH/capabilities/core.list"; then
      echo "$cap is lazy but sits in a tier list"
      return 1
    fi
  done < <(browser_rows)
  cleanup_test_env
}

test_arc_says_it_is_in_maintenance() {
  setup
  mkdir -p "$TEEUP_APPS_DIR/Arc.app"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure arc 2>&1)"
  assert_contains "$out" "Arc is in maintenance: security fixes, no new features." || return 1
  assert_contains "$("$TEEUP" list --tier lazy)" "security fixes only since Dia replaced it" || return 1
  cleanup_test_env
}

test_launch_opens_an_installed_browser_by_app_name() {
  setup
  mkdir -p "$TEEUP_APPS_DIR/Brave Browser.app"
  local out
  out="$(DRY_RUN=false "$TEEUP" launch "Brave Browser" 2>&1)"
  assert_contains "$out" "Opening Brave Browser" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "open -a Brave Browser" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew install --cask" || return 1
  cleanup_test_env
}

test_launch_installs_a_missing_browser_first() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" launch zen 2>&1)"
  assert_contains "$out" "Zen is not installed; installing zen first." || return 1
  assert_contains "$out" "Would execute: brew install --cask zen" || return 1
  cleanup_test_env
}

test_remove_uninstalls_the_cask_from_metadata() {
  setup
  mock_command_script brew <<'EOF2'
case "$1 ${2:-} ${3:-}" in
  "list --cask zen") exit 0 ;;
  "list "*) exit 1 ;;
esac
exit 0
EOF2
  DRY_RUN=false "$TEEUP" install zen >/dev/null 2>&1
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=false "$TEEUP" remove zen 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall --cask zen" || return 1
  assert_contains "$out" "Removed zen." || return 1
  cleanup_test_env
}

echo "capabilities/browsers"
run_test "each install gets its own cask" test_each_install_gets_its_own_cask
run_test "each install points at a download page on macports" test_each_install_points_at_a_download_page_on_macports
run_test "each configure reports its app" test_each_configure_reports_its_app
run_test "each configure writes nothing" test_each_configure_writes_nothing
run_test "each is lazy, launchable and shimless" test_each_is_lazy_launchable_and_shimless
run_test "arc says it is in maintenance" test_arc_says_it_is_in_maintenance
run_test "launch opens an installed browser by app name" test_launch_opens_an_installed_browser_by_app_name
run_test "launch installs a missing browser first" test_launch_installs_a_missing_browser_first
run_test "remove uninstalls the cask from metadata" test_remove_uninstalls_the_cask_from_metadata
print_summary
```

- [ ] **Step 2: Add the three library tests**

Both edits are in `tests/lib/lazy.sh`. First the test functions, ahead of the suite header:

```bash edit-old=tests/lib/lazy.sh
echo "lib/lazy.sh"
```

```bash edit-new=tests/lib/lazy.sh
test_cask_app_install_uses_the_cask_on_homebrew() {
  setup
  export TEEUP_PACKAGE_MANAGER=homebrew
  DRY_RUN=true
  local out
  out="$(cask_app_install demo-cask "Demo App" https://example.test/demo 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask demo-cask" || return 1
  assert_not_contains "$out" "MacPorts" || return 1
  cleanup_test_env
}

test_cask_app_install_names_the_download_page_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  DRY_RUN=true
  local out rc=0
  out="$(cask_app_install demo-cask "Demo App" https://example.test/demo 2>&1)" || rc=$?
  assert_success "$rc" "a missing cask must not fail the install" || return 1
  assert_contains "$out" "Demo App is a cask and MacPorts has none; download it from https://example.test/demo" || return 1
  assert_not_contains "$out" "brew install" || return 1
  cleanup_test_env
}

test_cask_app_report_names_both_states() {
  setup
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  local out
  out="$(cask_app_report "Demo App" 2>&1)"
  assert_contains "$out" "Demo App.app is not in $TEEUP_APPS_DIR; the install step above says why." || return 1
  mkdir -p "$TEEUP_APPS_DIR/Demo App.app"
  out="$(cask_app_report "Demo App" "One more thing." 2>&1)"
  assert_contains "$out" "Demo App is installed; open it with: open -a 'Demo App'" || return 1
  assert_contains "$out" "One more thing." || return 1
  cleanup_test_env
}

echo "lib/lazy.sh"
```

Then the three `run_test` lines, after the last one:

```bash edit-old=tests/lib/lazy.sh
run_test "app_installed checks both application folders" test_app_installed_checks_both_application_folders
```

```bash edit-new=tests/lib/lazy.sh
run_test "app_installed checks both application folders" test_app_installed_checks_both_application_folders
run_test "cask_app_install uses the cask on homebrew" test_cask_app_install_uses_the_cask_on_homebrew
run_test "cask_app_install names the download page on macports" test_cask_app_install_names_the_download_page_on_macports
run_test "cask_app_report names both states" test_cask_app_report_names_both_states
```

- [ ] **Step 3: Run both suites and watch them fail**

Run: `chmod +x tests/capabilities/browsers.sh && bash tests/capabilities/browsers.sh; bash tests/lib/lazy.sh`
Expected: `Summary: 1/9 passed` for `capabilities/browsers` (the one that passes early is `each configure writes nothing`, which asserts that nothing was run) and `Summary: 14/17 passed` for `lib/lazy.sh`, the three new ones failing on `cask_app_install: command not found`.

- [ ] **Step 4: Append the two helpers to `lib/lazy.sh`**

They go at the end of the file, after `launch_resolve`.

```bash edit-old=lib/lazy.sh
  err "No capability provides an app named '$1' (try: teeup list)."
  return 1
}
```

```bash edit-new=lib/lazy.sh
  err "No capability provides an app named '$1' (try: teeup list)."
  return 1
}

# --- GUI cask capabilities ----------------------------------------------------

# cask_app_install <cask> <app name> <download url>
# The install half of a lazy capability whose whole content is one GUI app.
# MacPorts has no casks, so there the app is a named download page rather than
# a failure: `teeup install <cap>` still exits 0, which is what keeps an old
# Intel Mac on MacPorts usable.
cask_app_install() {
  if casks_supported; then
    cask_install "$1"
  else
    warn "$2 is a cask and MacPorts has none; download it from $3"
  fi
}

# cask_app_report <app name> [extra line]
# The configure half. These apps keep their settings in their own containers
# or behind an account, so teeup ships none; what configure can still say is
# whether the bundle arrived and how to open it. The wording is the one
# capabilities/chrome/configure already uses, so the family reads the same.
cask_app_report() {
  if app_installed "$1"; then
    log "$1 is installed; open it with: open -a '$1'"
  else
    log "$1.app is not in ${TEEUP_APPS_DIR:-/Applications}; the install step above says why."
  fi
  if [[ -n "${2:-}" ]]; then
    log "$2"
  fi
  return 0
}
```

- [ ] **Step 5: Write Brave**

```ini file=capabilities/brave/capability
summary="Brave, a Chromium browser with the ad blocker built in"
group=browsers
tier=lazy
requires="package-manager"
provides=""
packages=""
casks="brave-browser"
apps="Brave Browser"
interactive=false
```

```bash file=capabilities/brave/install
#!/usr/bin/env bash
# The cask token is brave-browser and it installs Brave Browser.app, which is
# also the name `teeup launch` opens. It needs macOS 13 or newer and updates
# itself. MacPorts has no casks and no port of it.
cask_app_install brave-browser "Brave Browser" https://brave.com/download/
```

```bash file=capabilities/brave/configure
#!/usr/bin/env bash
# Brave syncs its settings through its own Sync Chain, so teeup ships none.
cask_app_report "Brave Browser"
```

- [ ] **Step 6: Write Arc**

```ini file=capabilities/arc/capability
summary="Arc, a Chromium browser that gets security fixes only since Dia replaced it"
group=browsers
tier=lazy
requires="package-manager"
provides=""
packages=""
casks="arc"
apps="Arc"
interactive=false
```

```bash file=capabilities/arc/install
#!/usr/bin/env bash
# The cask token is arc and it installs Arc.app; it needs macOS 13 or newer.
# The Browser Company moved its development to Dia, so Arc is in maintenance:
# it still installs, still runs Chrome extensions and still takes Chromium
# security updates, and it gains no features. MacPorts has no casks.
cask_app_install arc Arc https://arc.net/
```

```bash file=capabilities/arc/configure
#!/usr/bin/env bash
# Arc keeps its spaces and settings behind its own account, so teeup ships
# nothing for it.
cask_app_report Arc "Arc is in maintenance: security fixes, no new features. Brave, Chrome and Zen are the other lazy browsers."
```

- [ ] **Step 7: Write Zen**

```ini file=capabilities/zen/capability
summary="Zen, a Firefox-based browser with a minimal window"
group=browsers
tier=lazy
requires="package-manager"
provides=""
packages=""
casks="zen"
apps="Zen"
interactive=false
```

```bash file=capabilities/zen/install
#!/usr/bin/env bash
# The cask token is zen and it installs Zen.app. It was renamed from
# zen-browser, which Homebrew still lists as an old token; the current one is
# what this installs. MacPorts has no casks.
cask_app_install zen Zen https://zen-browser.app/
```

```bash file=capabilities/zen/configure
#!/usr/bin/env bash
# Zen is Firefox underneath and keeps its settings per profile, so there is
# no file teeup can own without choosing a profile.
cask_app_report Zen
```

- [ ] **Step 8: Make the six scripts executable and run both suites**

Run: `chmod +x capabilities/brave/install capabilities/brave/configure capabilities/arc/install capabilities/arc/configure capabilities/zen/install capabilities/zen/configure && bash tests/capabilities/browsers.sh && bash tests/lib/lazy.sh`
Expected: `Summary: 9/9 passed` and `Summary: 17/17 passed`.

- [ ] **Step 9: Run the whole suite and the checks**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning lib/lazy.sh capabilities/brave/install capabilities/brave/configure capabilities/arc/install capabilities/arc/configure capabilities/zen/install capabilities/zen/configure tests/capabilities/browsers.sh tests/lib/lazy.sh && git diff --check`
Expected: the suite count printed before this task, plus 1; everything else silent.

- [ ] **Step 10: Commit**

```bash
git add lib/lazy.sh tests/lib/lazy.sh capabilities/brave capabilities/arc capabilities/zen tests/capabilities/browsers.sh
git commit -m "Add the browser capabilities and the GUI cask helpers"
```

---

### Task 5: the communication apps

Seven capabilities, one shape, one suite. Every one is a Homebrew cask with a
single application bundle, so `install` is one `cask_app_install` line and
`configure` is one `cask_app_report` line; what differs is the cask token, the
bundle name and the sentence about where that app keeps its settings.

**Files:**
- Create: `capabilities/slack/`, `capabilities/zoom/`, `capabilities/signal/`, `capabilities/whatsapp/`, `capabilities/telegram/`, `capabilities/discord/`, `capabilities/teams/`, each with `capability`, `install` and `configure`
- Test: `tests/capabilities/communication.sh`

**Interfaces:**
- Consumes: `cask_app_install`, `cask_app_report` (`lib/lazy.sh`, Task 4).
- Produces: the capabilities `slack` (cask `slack`, app `Slack`), `zoom` (cask `zoom`, app `zoom.us`), `signal` (cask `signal`, app `Signal`), `whatsapp` (cask `whatsapp`, app `WhatsApp`), `telegram` (cask `telegram`, app `Telegram`), `discord` (cask `discord`, app `Discord`) and `teams` (cask `microsoft-teams`, app `Microsoft Teams`), all `group=communication`, `tier=lazy`, `requires="package-manager"`, no `provides=`.

**Real-Mac risk:** that the two pkg-based casks (`zoom`, `microsoft-teams`) really leave `zoom.us.app` and `Microsoft Teams.app` in `/Applications` — Homebrew's uninstall stanzas delete exactly those two paths, which is where the names come from, but only an install proves it; that `microsoft-teams` needs macOS 14 or newer and `signal` and `whatsapp` macOS 12 or newer, so an old Intel Mac may refuse them even on Homebrew.

- [ ] **Step 1: Write the failing test**

```bash file=tests/capabilities/communication.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# Seven capabilities of one shape. The table is capability name, cask token
# and application bundle name; two of the bundles are not what the capability
# is called (zoom installs zoom.us.app, teams installs Microsoft Teams.app),
# which is exactly what these rows pin down.
comms_rows() {
  cat <<'EOF2'
slack slack Slack
zoom zoom zoom.us
signal signal Signal
whatsapp whatsapp WhatsApp
telegram telegram Telegram
discord discord Discord
teams microsoft-teams Microsoft Teams
EOF2
}

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  mock_command open 0 ""
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  mkdir -p "$TEEUP_APPS_DIR"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_each_install_gets_its_own_cask() {
  setup
  local cap cask app out
  while read -r cap cask app; do
    out="$(DRY_RUN=true "$TEEUP" install "$cap" 2>&1)"
    assert_contains "$out" "Would execute: brew install --cask $cask" || return 1
  done < <(comms_rows)
  cleanup_test_env
}

test_each_install_points_at_a_download_page_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local cap cask app out rc
  while read -r cap cask app; do
    rc=0
    out="$(DRY_RUN=true "$TEEUP" install "$cap" 2>&1)" || rc=$?
    assert_success "$rc" "$cap must not fail on a MacPorts machine" || return 1
    assert_contains "$out" "$app is a cask and MacPorts has none; download it from https://" || return 1
    assert_not_contains "$out" "brew install --cask" || return 1
  done < <(comms_rows)
  cleanup_test_env
}

test_each_configure_reports_its_app() {
  setup
  local cap cask app out
  while read -r cap cask app; do
    out="$(DRY_RUN=false "$TEEUP" configure "$cap" 2>&1)"
    assert_contains "$out" "$app.app is not in $TEEUP_APPS_DIR" || return 1
    mkdir -p "$TEEUP_APPS_DIR/$app.app"
    out="$(DRY_RUN=false "$TEEUP" configure "$cap" 2>&1)"
    assert_contains "$out" "$app is installed; open it with: open -a '$app'" || return 1
  done < <(comms_rows)
  cleanup_test_env
}

test_each_configure_writes_nothing() {
  setup
  local cap cask app
  while read -r cap cask app; do
    DRY_RUN=false "$TEEUP" configure "$cap" >/dev/null
  done < <(comms_rows)
  assert_equals "" "$(grep -v '^hostname' "$MOCK_LOG" || true)" "a configure ran a command" || return 1
  cleanup_test_env
}

test_each_is_lazy_launchable_and_shimless() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local cap cask app
  while read -r cap cask app; do
    assert_contains "$("$TEEUP" list --tier lazy)" "$cap" || return 1
    assert_equals "$app" "$(cd "$TEEUP_PATH" && bash -c "source lib/all.sh; cap_meta_get $cap apps")" || return 1
    assert_equals "$cask" "$(cd "$TEEUP_PATH" && bash -c "source lib/all.sh; cap_meta_get $cap casks")" || return 1
    assert_equals "" "$(cd "$TEEUP_PATH" && bash -c "source lib/all.sh; cap_meta_get $cap provides")" || return 1
    [[ ! -e "$TEST_HOME/.local/state/teeup/shims/$cap" ]] || { echo "$cap must not get a shim"; return 1; }
    if grep -qx "$cap" "$TEEUP_PATH/capabilities/daily.list" "$TEEUP_PATH/capabilities/core.list"; then
      echo "$cap is lazy but sits in a tier list"
      return 1
    fi
  done < <(comms_rows)
  cleanup_test_env
}

test_zoom_launches_by_capability_name_and_by_bundle_name() {
  setup
  mkdir -p "$TEEUP_APPS_DIR/zoom.us.app"
  local out
  out="$(DRY_RUN=false "$TEEUP" launch zoom 2>&1)"
  assert_contains "$out" "Opening zoom.us" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "open -a zoom.us" || return 1
  : > "$MOCK_LOG"
  out="$(DRY_RUN=false "$TEEUP" launch zoom.us 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "open -a zoom.us" || return 1
  cleanup_test_env
}

test_teams_launches_by_its_two_word_bundle_name() {
  setup
  mkdir -p "$TEEUP_APPS_DIR/Microsoft Teams.app"
  local out
  out="$(DRY_RUN=false "$TEEUP" launch "Microsoft Teams" 2>&1)"
  assert_contains "$out" "Opening Microsoft Teams" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "open -a Microsoft Teams" || return 1
  cleanup_test_env
}

test_remove_uninstalls_the_cask_from_metadata() {
  setup
  mock_command_script brew <<'EOF2'
case "$1 ${2:-} ${3:-}" in
  "list --cask slack") exit 0 ;;
  "list "*) exit 1 ;;
esac
exit 0
EOF2
  DRY_RUN=false "$TEEUP" install slack >/dev/null 2>&1
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=false "$TEEUP" remove slack 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall --cask slack" || return 1
  assert_contains "$out" "Removed slack." || return 1
  cleanup_test_env
}

echo "capabilities/communication"
run_test "each install gets its own cask" test_each_install_gets_its_own_cask
run_test "each install points at a download page on macports" test_each_install_points_at_a_download_page_on_macports
run_test "each configure reports its app" test_each_configure_reports_its_app
run_test "each configure writes nothing" test_each_configure_writes_nothing
run_test "each is lazy, launchable and shimless" test_each_is_lazy_launchable_and_shimless
run_test "zoom launches by capability name and by bundle name" test_zoom_launches_by_capability_name_and_by_bundle_name
run_test "teams launches by its two-word bundle name" test_teams_launches_by_its_two_word_bundle_name
run_test "remove uninstalls the cask from metadata" test_remove_uninstalls_the_cask_from_metadata
print_summary
```

- [ ] **Step 2: Run it and watch it fail**

Run: `chmod +x tests/capabilities/communication.sh && bash tests/capabilities/communication.sh`
Expected: `Summary: 1/8 passed`; the one that passes early is `each configure writes nothing`, which asserts that nothing was run.

- [ ] **Step 3: Write Slack**

```ini file=capabilities/slack/capability
summary="Slack, the team chat client"
group=communication
tier=lazy
requires="package-manager"
provides=""
packages=""
casks="slack"
apps="Slack"
interactive=false
```

```bash file=capabilities/slack/install
#!/usr/bin/env bash
# The cask token is slack and it installs Slack.app. It updates itself once
# it is running. MacPorts has no casks.
cask_app_install slack "Slack" https://slack.com/downloads/mac
```

```bash file=capabilities/slack/configure
#!/usr/bin/env bash
# Slack keeps its workspaces and settings behind your account, so teeup
# ships nothing for it.
cask_app_report "Slack"
```

- [ ] **Step 4: Write Zoom**

```ini file=capabilities/zoom/capability
summary="Zoom, the video meeting client"
group=communication
tier=lazy
requires="package-manager"
provides=""
packages=""
casks="zoom"
apps="zoom.us"
interactive=false
```

```bash file=capabilities/zoom/install
#!/usr/bin/env bash
# The cask token is zoom and it is a pkg installer, not an app bundle drop:
# the package puts zoom.us.app in /Applications, which is the name apps= and
# `teeup launch` use. MacPorts has no casks.
cask_app_install zoom "zoom.us" https://zoom.us/download
```

```bash file=capabilities/zoom/configure
#!/usr/bin/env bash
# Zoom signs in against your account and updates itself, so teeup ships no
# settings for it.
cask_app_report "zoom.us" "The bundle is named zoom.us, so the launcher is: teeup launch zoom.us (or teeup launch zoom)."
```

- [ ] **Step 5: Write Signal**

```ini file=capabilities/signal/capability
summary="Signal, the private messenger"
group=communication
tier=lazy
requires="package-manager"
provides=""
packages=""
casks="signal"
apps="Signal"
interactive=false
```

```bash file=capabilities/signal/install
#!/usr/bin/env bash
# The cask token is signal and it installs Signal.app; it needs macOS 12 or
# newer. MacPorts has no casks.
cask_app_install signal "Signal" https://signal.org/download/
```

```bash file=capabilities/signal/configure
#!/usr/bin/env bash
# Signal links to your phone and keeps its database in its own container, so
# there is nothing for teeup to ship.
cask_app_report "Signal" "Link it from the phone app: Settings, then Linked Devices."
```

- [ ] **Step 6: Write WhatsApp**

```ini file=capabilities/whatsapp/capability
summary="WhatsApp, the desktop client"
group=communication
tier=lazy
requires="package-manager"
provides=""
packages=""
casks="whatsapp"
apps="WhatsApp"
interactive=false
```

```bash file=capabilities/whatsapp/install
#!/usr/bin/env bash
# The cask token is whatsapp and it installs WhatsApp.app; it needs macOS 12
# or newer. MacPorts has no casks.
cask_app_install whatsapp "WhatsApp" https://www.whatsapp.com/download
```

```bash file=capabilities/whatsapp/configure
#!/usr/bin/env bash
# WhatsApp links to your phone and keeps everything in its own container.
cask_app_report "WhatsApp"
```

- [ ] **Step 7: Write Telegram**

```ini file=capabilities/telegram/capability
summary="Telegram for macOS"
group=communication
tier=lazy
requires="package-manager"
provides=""
packages=""
casks="telegram"
apps="Telegram"
interactive=false
```

```bash file=capabilities/telegram/install
#!/usr/bin/env bash
# The cask token is telegram (Homebrew names the cask "Telegram for macOS")
# and it installs Telegram.app. MacPorts has no casks.
cask_app_install telegram "Telegram" https://macos.telegram.org/
```

```bash file=capabilities/telegram/configure
#!/usr/bin/env bash
# Telegram signs in with your phone number and syncs from the server, so
# teeup ships no settings for it.
cask_app_report "Telegram"
```

- [ ] **Step 8: Write Discord**

```ini file=capabilities/discord/capability
summary="Discord, the voice and text chat client"
group=communication
tier=lazy
requires="package-manager"
provides=""
packages=""
casks="discord"
apps="Discord"
interactive=false
```

```bash file=capabilities/discord/install
#!/usr/bin/env bash
# The cask token is discord and it installs Discord.app. It updates itself.
# MacPorts has no casks.
cask_app_install discord "Discord" https://discord.com/download
```

```bash file=capabilities/discord/configure
#!/usr/bin/env bash
# Discord keeps its settings behind your account.
cask_app_report "Discord"
```

- [ ] **Step 9: Write Microsoft Teams**

```ini file=capabilities/teams/capability
summary="Microsoft Teams, the work chat and meeting client"
group=communication
tier=lazy
requires="package-manager"
provides=""
packages=""
casks="microsoft-teams"
apps="Microsoft Teams"
interactive=false
```

```bash file=capabilities/teams/install
#!/usr/bin/env bash
# The cask token is microsoft-teams and it is a pkg installer that puts
# Microsoft Teams.app in /Applications; it needs macOS 14 or newer. The cask
# deselects the bundled Microsoft AutoUpdate component, so Teams updates
# through its own path rather than installing a second updater. MacPorts has
# no casks.
cask_app_install microsoft-teams "Microsoft Teams" https://www.microsoft.com/microsoft-teams/download-app
```

```bash file=capabilities/teams/configure
#!/usr/bin/env bash
# Teams signs in against your work account and stores everything there.
cask_app_report "Microsoft Teams"
```

- [ ] **Step 10: Make the fourteen scripts executable and run the suite**

Run: `chmod +x capabilities/slack/install capabilities/slack/configure capabilities/zoom/install capabilities/zoom/configure capabilities/signal/install capabilities/signal/configure capabilities/whatsapp/install capabilities/whatsapp/configure capabilities/telegram/install capabilities/telegram/configure capabilities/discord/install capabilities/discord/configure capabilities/teams/install capabilities/teams/configure && bash tests/capabilities/communication.sh`
Expected: `Summary: 8/8 passed`.

- [ ] **Step 11: Run the whole suite and the checks**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning capabilities/slack/install capabilities/slack/configure capabilities/zoom/install capabilities/zoom/configure capabilities/signal/install capabilities/signal/configure capabilities/whatsapp/install capabilities/whatsapp/configure capabilities/telegram/install capabilities/telegram/configure capabilities/discord/install capabilities/discord/configure capabilities/teams/install capabilities/teams/configure tests/capabilities/communication.sh && git diff --check`
Expected: the suite count printed before this task, plus 1; everything else silent.

- [ ] **Step 12: Commit**

```bash
git add capabilities/slack capabilities/zoom capabilities/signal capabilities/whatsapp capabilities/telegram capabilities/discord capabilities/teams tests/capabilities/communication.sh
git commit -m "Add the communication app capabilities"
```

---

### Task 6: the productivity apps

Five more capabilities of the Task 4 shape. `1password` is the one whose
directory name starts with a digit; the suite proves that `teeup list`,
`teeup launch` and `teeup has` all take it.

**Files:**
- Create: `capabilities/1password/`, `capabilities/raycast/`, `capabilities/bruno/`, `capabilities/notion/`, `capabilities/typora/`, each with `capability`, `install` and `configure`
- Test: `tests/capabilities/productivity.sh`

**Interfaces:**
- Consumes: `cask_app_install`, `cask_app_report` (`lib/lazy.sh`, Task 4).
- Produces: the capabilities `1password` (cask `1password`, app `1Password`), `raycast` (cask `raycast`, app `Raycast`), `bruno` (cask `bruno`, app `Bruno`), `notion` (cask `notion`, app `Notion`) and `typora` (cask `typora`, app `Typora`), all `group=productivity`, `tier=lazy`, `requires="package-manager"`, no `provides=`.

**Real-Mac risk:** that `1password` and `notion` install at all on an old Intel Mac (both declare macOS 12 or newer); that Typora's trial dialog does not block a scripted install; that nothing here needs an approval step the way Karabiner does.

- [ ] **Step 1: Write the failing test**

```bash file=tests/capabilities/productivity.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# Five capabilities of one shape: capability name, cask token, application
# bundle name.
productivity_rows() {
  cat <<'EOF2'
1password 1password 1Password
raycast raycast Raycast
bruno bruno Bruno
notion notion Notion
typora typora Typora
EOF2
}

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  mock_command open 0 ""
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  mkdir -p "$TEEUP_APPS_DIR"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_each_install_gets_its_own_cask() {
  setup
  local cap cask app out
  while read -r cap cask app; do
    out="$(DRY_RUN=true "$TEEUP" install "$cap" 2>&1)"
    assert_contains "$out" "Would execute: brew install --cask $cask" || return 1
  done < <(productivity_rows)
  cleanup_test_env
}

test_each_install_points_at_a_download_page_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local cap cask app out rc
  while read -r cap cask app; do
    rc=0
    out="$(DRY_RUN=true "$TEEUP" install "$cap" 2>&1)" || rc=$?
    assert_success "$rc" "$cap must not fail on a MacPorts machine" || return 1
    assert_contains "$out" "$app is a cask and MacPorts has none; download it from https://" || return 1
    assert_not_contains "$out" "brew install --cask" || return 1
  done < <(productivity_rows)
  cleanup_test_env
}

test_each_configure_reports_its_app() {
  setup
  local cap cask app out
  while read -r cap cask app; do
    out="$(DRY_RUN=false "$TEEUP" configure "$cap" 2>&1)"
    assert_contains "$out" "$app.app is not in $TEEUP_APPS_DIR" || return 1
    mkdir -p "$TEEUP_APPS_DIR/$app.app"
    out="$(DRY_RUN=false "$TEEUP" configure "$cap" 2>&1)"
    assert_contains "$out" "$app is installed; open it with: open -a '$app'" || return 1
  done < <(productivity_rows)
  cleanup_test_env
}

test_each_configure_writes_nothing() {
  setup
  local cap cask app
  while read -r cap cask app; do
    DRY_RUN=false "$TEEUP" configure "$cap" >/dev/null
  done < <(productivity_rows)
  assert_equals "" "$(grep -v '^hostname' "$MOCK_LOG" || true)" "a configure ran a command" || return 1
  cleanup_test_env
}

test_each_is_lazy_launchable_and_shimless() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local cap cask app
  while read -r cap cask app; do
    assert_contains "$("$TEEUP" list --tier lazy)" "$cap" || return 1
    assert_equals "$app" "$(cd "$TEEUP_PATH" && bash -c "source lib/all.sh; cap_meta_get $cap apps")" || return 1
    assert_equals "$cask" "$(cd "$TEEUP_PATH" && bash -c "source lib/all.sh; cap_meta_get $cap casks")" || return 1
    assert_equals "" "$(cd "$TEEUP_PATH" && bash -c "source lib/all.sh; cap_meta_get $cap provides")" || return 1
    [[ ! -e "$TEST_HOME/.local/state/teeup/shims/$cap" ]] || { echo "$cap must not get a shim"; return 1; }
    if grep -qx "$cap" "$TEEUP_PATH/capabilities/daily.list" "$TEEUP_PATH/capabilities/core.list"; then
      echo "$cap is lazy but sits in a tier list"
      return 1
    fi
  done < <(productivity_rows)
  cleanup_test_env
}

test_a_capability_whose_name_starts_with_a_digit_still_works() {
  setup
  mkdir -p "$TEEUP_APPS_DIR/1Password.app"
  local out
  out="$(DRY_RUN=false "$TEEUP" launch 1password 2>&1)"
  assert_contains "$out" "Opening 1Password" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "open -a 1Password" || return 1
  "$TEEUP" has 1password && { echo "1password is not installed here"; return 1; }
  cleanup_test_env
}

test_the_hotkey_and_ssh_agent_notes_are_printed() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure raycast 2>&1)"
  assert_contains "$out" "Show Spotlight search" || return 1
  out="$(DRY_RUN=false "$TEEUP" configure 1password 2>&1)"
  assert_contains "$out" "teeup keeps its own secrets in the macOS Keychain either way." || return 1
  cleanup_test_env
}

test_remove_uninstalls_the_cask_from_metadata() {
  setup
  mock_command_script brew <<'EOF2'
case "$1 ${2:-} ${3:-}" in
  "list --cask typora") exit 0 ;;
  "list "*) exit 1 ;;
esac
exit 0
EOF2
  DRY_RUN=false "$TEEUP" install typora >/dev/null 2>&1
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=false "$TEEUP" remove typora 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall --cask typora" || return 1
  assert_contains "$out" "Removed typora." || return 1
  cleanup_test_env
}

echo "capabilities/productivity"
run_test "each install gets its own cask" test_each_install_gets_its_own_cask
run_test "each install points at a download page on macports" test_each_install_points_at_a_download_page_on_macports
run_test "each configure reports its app" test_each_configure_reports_its_app
run_test "each configure writes nothing" test_each_configure_writes_nothing
run_test "each is lazy, launchable and shimless" test_each_is_lazy_launchable_and_shimless
run_test "a capability whose name starts with a digit still works" test_a_capability_whose_name_starts_with_a_digit_still_works
run_test "the hotkey and ssh agent notes are printed" test_the_hotkey_and_ssh_agent_notes_are_printed
run_test "remove uninstalls the cask from metadata" test_remove_uninstalls_the_cask_from_metadata
print_summary
```

- [ ] **Step 2: Run it and watch it fail**

Run: `chmod +x tests/capabilities/productivity.sh && bash tests/capabilities/productivity.sh`
Expected: `Summary: 1/8 passed`; the one that passes early is `each configure writes nothing`.

- [ ] **Step 3: Write 1Password**

```ini file=capabilities/1password/capability
summary="1Password, the password manager app"
group=productivity
tier=lazy
requires="package-manager"
provides=""
packages=""
casks="1password"
apps="1Password"
interactive=false
```

```bash file=capabilities/1password/install
#!/usr/bin/env bash
# The cask token is 1password and it installs 1Password.app; it needs macOS
# 12 or newer. The separate 1password-cli cask (the `op` command) is not
# installed here: teeup keeps its own secrets in the macOS Keychain through
# the secrets capability. MacPorts has no casks.
cask_app_install 1password "1Password" https://1password.com/downloads/mac/
```

```bash file=capabilities/1password/configure
#!/usr/bin/env bash
# 1Password keeps its vaults behind your account, so teeup ships nothing for
# it.
cask_app_report "1Password" "Turn on Settings, Developer, Use the SSH agent if you want 1Password to hold your SSH keys; teeup keeps its own secrets in the macOS Keychain either way."
```

- [ ] **Step 4: Write Raycast**

```ini file=capabilities/raycast/capability
summary="Raycast, the launcher that replaces Spotlight"
group=productivity
tier=lazy
requires="package-manager"
provides=""
packages=""
casks="raycast"
apps="Raycast"
interactive=false
```

```bash file=capabilities/raycast/install
#!/usr/bin/env bash
# The cask token is raycast and it installs Raycast.app. MacPorts has no
# casks.
cask_app_install raycast "Raycast" https://raycast.com/
```

```bash file=capabilities/raycast/configure
#!/usr/bin/env bash
# Raycast stores its settings and extensions behind its own account, and the
# hotkey swap has to be done in the two apps by hand: nothing here can take
# command-space away from Spotlight for you.
cask_app_report "Raycast" "Set the hotkey in Raycast, then turn off System Settings, Keyboard, Keyboard Shortcuts, Spotlight, Show Spotlight search."
```

- [ ] **Step 5: Write Bruno**

```ini file=capabilities/bruno/capability
summary="Bruno, the offline API client"
group=productivity
tier=lazy
requires="package-manager"
provides=""
packages=""
casks="bruno"
apps="Bruno"
interactive=false
```

```bash file=capabilities/bruno/install
#!/usr/bin/env bash
# The cask token is bruno and it installs Bruno.app. MacPorts has no casks.
cask_app_install bruno "Bruno" https://www.usebruno.com/downloads
```

```bash file=capabilities/bruno/configure
#!/usr/bin/env bash
# Bruno keeps collections as files in a directory you choose, so there is
# nothing for teeup to ship; ~/Work is where teeup puts project directories.
cask_app_report "Bruno"
```

- [ ] **Step 6: Write Notion**

```ini file=capabilities/notion/capability
summary="Notion, the notes and database app"
group=productivity
tier=lazy
requires="package-manager"
provides=""
packages=""
casks="notion"
apps="Notion"
interactive=false
```

```bash file=capabilities/notion/install
#!/usr/bin/env bash
# The cask token is notion and it installs Notion.app; it needs macOS 12 or
# newer. MacPorts has no casks.
cask_app_install notion "Notion" https://www.notion.com/desktop
```

```bash file=capabilities/notion/configure
#!/usr/bin/env bash
# Notion is a client for your workspace, so everything it knows lives
# server-side.
cask_app_report "Notion"
```

- [ ] **Step 7: Write Typora**

```ini file=capabilities/typora/capability
summary="Typora, the Markdown editor"
group=productivity
tier=lazy
requires="package-manager"
provides=""
packages=""
casks="typora"
apps="Typora"
interactive=false
```

```bash file=capabilities/typora/install
#!/usr/bin/env bash
# The cask token is typora and it installs Typora.app. Typora is paid
# software with a trial; the cask installs it either way. MacPorts has no
# casks.
cask_app_install typora "Typora" https://typora.io/
```

```bash file=capabilities/typora/configure
#!/usr/bin/env bash
# Typora keeps its themes in ~/Library/Application Support/abnerworks.Typora
# and teeup ships none, so a theme you add there survives every teeup update.
cask_app_report "Typora"
```

- [ ] **Step 8: Make the ten scripts executable and run the suite**

Run: `chmod +x capabilities/1password/install capabilities/1password/configure capabilities/raycast/install capabilities/raycast/configure capabilities/bruno/install capabilities/bruno/configure capabilities/notion/install capabilities/notion/configure capabilities/typora/install capabilities/typora/configure && bash tests/capabilities/productivity.sh`
Expected: `Summary: 8/8 passed`.

- [ ] **Step 9: Run the whole suite and the checks**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning capabilities/1password/install capabilities/1password/configure capabilities/raycast/install capabilities/raycast/configure capabilities/bruno/install capabilities/bruno/configure capabilities/notion/install capabilities/notion/configure capabilities/typora/install capabilities/typora/configure tests/capabilities/productivity.sh && git diff --check`
Expected: the suite count printed before this task, plus 1; everything else silent.

- [ ] **Step 10: Commit**

```bash
git add capabilities/1password capabilities/raycast capabilities/bruno capabilities/notion capabilities/typora tests/capabilities/productivity.sh
git commit -m "Add the productivity app capabilities"
```

---

### Task 7: `karabiner` — Karabiner-Elements and the optional hyper key

**Files:**
- Create: `capabilities/karabiner/capability`, `capabilities/karabiner/install`, `capabilities/karabiner/configure`, `capabilities/karabiner/config/karabiner/karabiner-right_command.json`, `capabilities/karabiner/config/karabiner/karabiner-caps_lock.json`
- Test: `tests/capabilities/karabiner.sh`

**Interfaces:**
- Consumes: `cask_app_install`, `cask_app_report` (`lib/lazy.sh`, Task 4); `copy_config_once <src> <dest>` (`lib/files.sh`); `state_done ensure <name>`, which succeeds only the first time (`lib/state.sh`); `answers_get <KEY> [default]` (`lib/answers.sh`); `cap_skipped <name>` (`lib/capability.sh`); `user_config_dir` (`lib/core.sh`).
- Produces: the capability `karabiner` (cask `karabiner-elements`, `apps="Karabiner-Elements;Karabiner-EventViewer"`, `group=macos`, `tier=lazy`, no `provides=`) and the answers key `TEEUP_KARABINER_HYPER` (`right_command` by default, or `caps_lock`, or `none`), documented in Task 9's README section.

**Real-Mac risk:** everything that makes Karabiner work, which is the part no test can reach: the four macOS approvals, the DriverKit extension loading, and whether a `hidutil` Caps Lock mapping and a Karabiner `caps_lock` rule really collide on hardware (this plan assumes they do and defaults away from it). Also that the shipped `karabiner.json` is accepted as written: Karabiner rewrites the file with all of its defaults the first time its UI touches a setting, so a profile with only `name`, `selected` and `complex_modifications` has to be enough to start from. A doctor check for the approvals is deferred to a later phase.

- [ ] **Step 1: Write the failing test**

```bash file=tests/capabilities/karabiner.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# jq is resolved before setup_test_env narrows PATH and linked into the mock
# bin, so the two shipped profiles can be parsed rather than grepped. Every
# CI runner image ships jq.
JQ_BIN="$(command -v jq || true)"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  mkdir -p "$TEEUP_APPS_DIR"
  TEEUP="$TEEUP_PATH/bin/teeup"
  KARABINER_JSON="$TEST_HOME/.config/karabiner/karabiner.json"
}

test_install_gets_the_cask() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install karabiner 2>&1)"
  assert_contains "$out" "Would execute: brew install --cask karabiner-elements" || return 1
  cleanup_test_env
}

test_install_points_at_the_download_page_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local rc=0 out
  out="$(DRY_RUN=true "$TEEUP" install karabiner 2>&1)" || rc=$?
  assert_success "$rc" "a missing cask must not fail the install" || return 1
  assert_contains "$out" "Karabiner-Elements is a cask and MacPorts has none; download it from https://karabiner-elements.pqrs.org/" || return 1
  cleanup_test_env
}

test_configure_installs_the_right_command_profile_by_default() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure karabiner 2>&1)"
  assert_file_exists "$KARABINER_JSON" || return 1
  assert_contains "$out" "Hyper key: hold right_command for command+control+option+shift." || return 1
  if [[ -n "$JQ_BIN" ]]; then
    assert_equals "right_command" "$("$JQ_BIN" -r '.profiles[0].complex_modifications.rules[0].manipulators[0].from.key_code' "$KARABINER_JSON")" || return 1
    assert_equals "right_command" "$("$JQ_BIN" -r '.profiles[0].complex_modifications.rules[0].manipulators[0].to_if_alone[0].key_code' "$KARABINER_JSON")" || return 1
    assert_equals "left_shift" "$("$JQ_BIN" -r '.profiles[0].complex_modifications.rules[0].manipulators[0].to[0].key_code' "$KARABINER_JSON")" || return 1
    assert_equals "left_command left_control left_option" "$("$JQ_BIN" -r '.profiles[0].complex_modifications.rules[0].manipulators[0].to[0].modifiers|join(" ")' "$KARABINER_JSON")" || return 1
    assert_equals "true" "$("$JQ_BIN" -r '.profiles[0].selected' "$KARABINER_JSON")" || return 1
  fi
  cleanup_test_env
}

test_the_caps_lock_profile_taps_escape_and_warns_about_hidutil() {
  setup
  export TEEUP_KARABINER_HYPER=caps_lock
  local out
  out="$(DRY_RUN=false "$TEEUP" configure karabiner 2>&1)"
  assert_contains "$out" "The keyboard capability already maps Caps Lock to Control through hidutil" || return 1
  if [[ -n "$JQ_BIN" ]]; then
    assert_equals "caps_lock" "$("$JQ_BIN" -r '.profiles[0].complex_modifications.rules[0].manipulators[0].from.key_code' "$KARABINER_JSON")" || return 1
    assert_equals "escape" "$("$JQ_BIN" -r '.profiles[0].complex_modifications.rules[0].manipulators[0].to_if_alone[0].key_code' "$KARABINER_JSON")" || return 1
  fi
  unset TEEUP_KARABINER_HYPER
  cleanup_test_env
}

test_caps_lock_does_not_warn_when_keyboard_is_skipped() {
  setup
  export TEEUP_KARABINER_HYPER=caps_lock
  export TEEUP_SKIP="keyboard"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure karabiner 2>&1)"
  assert_not_contains "$out" "would fight over one key" || return 1
  assert_file_exists "$KARABINER_JSON" || return 1
  unset TEEUP_KARABINER_HYPER TEEUP_SKIP
  cleanup_test_env
}

test_none_writes_no_profile() {
  setup
  export TEEUP_KARABINER_HYPER=none
  local out
  out="$(DRY_RUN=false "$TEEUP" configure karabiner 2>&1)"
  assert_contains "$out" "No hyper-key profile (TEEUP_KARABINER_HYPER=none)" || return 1
  [[ ! -e "$KARABINER_JSON" ]] || { echo "none must write nothing"; return 1; }
  unset TEEUP_KARABINER_HYPER
  cleanup_test_env
}

test_an_unknown_answer_writes_nothing_and_warns() {
  setup
  export TEEUP_KARABINER_HYPER=hyper
  local out
  out="$(DRY_RUN=false "$TEEUP" configure karabiner 2>&1)"
  assert_contains "$out" "Unknown TEEUP_KARABINER_HYPER 'hyper'; expected right_command, caps_lock or none." || return 1
  [[ ! -e "$KARABINER_JSON" ]] || { echo "an unknown answer must write nothing"; return 1; }
  unset TEEUP_KARABINER_HYPER
  cleanup_test_env
}

test_an_existing_config_is_kept() {
  setup
  mkdir -p "$(dirname "$KARABINER_JSON")"
  printf '{"profiles":[{"name":"mine","selected":true}]}\n' > "$KARABINER_JSON"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure karabiner 2>&1)"
  assert_contains "$out" "Keeping your $KARABINER_JSON" || return 1
  assert_contains "$(cat "$KARABINER_JSON")" '"name":"mine"' || return 1
  cleanup_test_env
}

test_the_permission_steps_print_once() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure karabiner 2>&1)"
  assert_contains "$out" "Allow the driver extension for the virtual keyboard and mouse" || return 1
  out="$(DRY_RUN=false "$TEEUP" configure karabiner 2>&1)"
  assert_not_contains "$out" "Allow the driver extension for the virtual keyboard and mouse" || return 1
  assert_contains "$out" "The macOS approvals Karabiner needs were listed the first time this ran" || return 1
  cleanup_test_env
}

test_dry_run_writes_nothing() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" configure karabiner 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would install $KARABINER_JSON" || return 1
  [[ ! -e "$KARABINER_JSON" ]] || { echo "dry run wrote the profile"; return 1; }
  [[ ! -e "$TEST_HOME/.local/state/teeup/done/karabiner-permissions" ]] || { echo "dry run recorded state"; return 1; }
  cleanup_test_env
}

test_a_config_home_with_a_space_still_works() {
  setup
  export XDG_CONFIG_HOME="$TEST_HOME/My Config"
  DRY_RUN=false "$TEEUP" configure karabiner >/dev/null
  assert_file_exists "$TEST_HOME/My Config/karabiner/karabiner.json" || return 1
  cleanup_test_env
}

test_it_is_lazy_launchable_and_shimless() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  assert_contains "$("$TEEUP" list --tier lazy)" "karabiner" || return 1
  assert_equals "Karabiner-Elements
Karabiner-EventViewer" "$(cd "$TEEUP_PATH" && bash -c 'source lib/all.sh; cap_apps karabiner')" || return 1
  assert_equals "" "$(cd "$TEEUP_PATH" && bash -c 'source lib/all.sh; cap_meta_get karabiner provides')" || return 1
  [[ ! -e "$TEST_HOME/.local/state/teeup/shims/karabiner" ]] || { echo "karabiner must not get a shim"; return 1; }
  cleanup_test_env
}

echo "capabilities/karabiner"
run_test "install gets the cask" test_install_gets_the_cask
run_test "install points at the download page on macports" test_install_points_at_the_download_page_on_macports
run_test "configure installs the right_command profile by default" test_configure_installs_the_right_command_profile_by_default
run_test "the caps_lock profile taps escape and warns about hidutil" test_the_caps_lock_profile_taps_escape_and_warns_about_hidutil
run_test "caps_lock does not warn when keyboard is skipped" test_caps_lock_does_not_warn_when_keyboard_is_skipped
run_test "none writes no profile" test_none_writes_no_profile
run_test "an unknown answer writes nothing and warns" test_an_unknown_answer_writes_nothing_and_warns
run_test "an existing config is kept" test_an_existing_config_is_kept
run_test "the permission steps print once" test_the_permission_steps_print_once
run_test "dry run writes nothing" test_dry_run_writes_nothing
run_test "a config home with a space still works" test_a_config_home_with_a_space_still_works
run_test "it is lazy, launchable and shimless" test_it_is_lazy_launchable_and_shimless
print_summary
```

- [ ] **Step 2: Run it and watch every test fail**

Run: `chmod +x tests/capabilities/karabiner.sh && bash tests/capabilities/karabiner.sh`
Expected: `Summary: 0/12 passed`, every failure tracing back to `Unknown capability: karabiner`.

- [ ] **Step 3: Write the metadata**

`apps=` is `;`-separated, and the package installs both bundles; `teeup launch karabiner` opens the first.

```ini file=capabilities/karabiner/capability
summary="Karabiner-Elements, with an optional hyper key"
group=macos
tier=lazy
requires="package-manager"
provides=""
packages=""
casks="karabiner-elements"
apps="Karabiner-Elements;Karabiner-EventViewer"
interactive=false
```

- [ ] **Step 4: Write the install script**

```bash file=capabilities/karabiner/install
#!/usr/bin/env bash
# The cask token is karabiner-elements. It is a pkg installer, and the
# package puts Karabiner-Elements.app and Karabiner-EventViewer.app in
# /Applications (Karabiner's own uninstall_core.sh removes exactly those two)
# and links karabiner_cli into the Homebrew prefix. Nothing is shimmed: the
# CLI is not a command anyone types, and the app is what this capability is
# for. MacPorts has no casks.
cask_app_install karabiner-elements "Karabiner-Elements" https://karabiner-elements.pqrs.org/
```

- [ ] **Step 5: Write the two shipped profiles**

Both follow Karabiner's documented root structure (`profiles[].complex_modifications.rules[].manipulators[]`) and the documented keys of a `basic` manipulator (`type`, `from`, `to`, `to_if_alone`). Hyper is the usual four modifiers: the key sends `left_shift` with `left_command`, `left_control` and `left_option` held, and tapping it alone sends what the key would have sent (`escape` for Caps Lock, by long convention).

```json file=capabilities/karabiner/config/karabiner/karabiner-right_command.json
{
  "profiles": [
    {
      "name": "teeup",
      "selected": true,
      "complex_modifications": {
        "rules": [
          {
            "description": "Hyper: hold right command for command+control+option+shift, tap it for right command",
            "manipulators": [
              {
                "type": "basic",
                "from": {
                  "key_code": "right_command",
                  "modifiers": { "optional": ["any"] }
                },
                "to": [
                  {
                    "key_code": "left_shift",
                    "modifiers": ["left_command", "left_control", "left_option"]
                  }
                ],
                "to_if_alone": [{ "key_code": "right_command" }]
              }
            ]
          }
        ]
      }
    }
  ]
}
```

```json file=capabilities/karabiner/config/karabiner/karabiner-caps_lock.json
{
  "profiles": [
    {
      "name": "teeup",
      "selected": true,
      "complex_modifications": {
        "rules": [
          {
            "description": "Hyper: hold caps lock for command+control+option+shift, tap it for escape",
            "manipulators": [
              {
                "type": "basic",
                "from": {
                  "key_code": "caps_lock",
                  "modifiers": { "optional": ["any"] }
                },
                "to": [
                  {
                    "key_code": "left_shift",
                    "modifiers": ["left_command", "left_control", "left_option"]
                  }
                ],
                "to_if_alone": [{ "key_code": "escape" }]
              }
            ]
          }
        ]
      }
    }
  ]
}
```

- [ ] **Step 6: Write the configure script**

```bash file=capabilities/karabiner/configure
#!/usr/bin/env bash
# Karabiner needs approvals from macOS that nothing can script, and it owns
# ~/.config/karabiner/karabiner.json: the app rewrites that file whenever a
# setting changes in its UI. So this configure installs a profile only when
# there is no file at all (the rule capabilities/tmux/configure follows for
# ~/.tmux.conf), and prints the approval steps once.
cask_app_report "Karabiner-Elements"

# state_done ensure succeeds only the first time, so the four steps are a
# list on the first configure and one line on every later one.
if state_done ensure karabiner-permissions; then
  log "macOS holds Karabiner back until you approve it. Open Karabiner-Elements once and follow its prompts:"
  log "  1. Allow its privileged and non-privileged background services to run"
  log "  2. Grant Accessibility permission"
  log "  3. Grant Input Monitoring permission (granting Accessibility usually covers this one)"
  log "  4. Allow the driver extension for the virtual keyboard and mouse"
  log "It then asks which virtual keyboard layout to use; pick the one your keyboard prints."
  log "If the driver approval never appears: https://karabiner-elements.pqrs.org/docs/help/troubleshooting/"
else
  log "The macOS approvals Karabiner needs were listed the first time this ran: https://karabiner-elements.pqrs.org/docs/getting-started/installation/"
fi

karabiner_hyper="$(answers_get TEEUP_KARABINER_HYPER right_command)"
karabiner_json="$(user_config_dir)/karabiner/karabiner.json"
case "$karabiner_hyper" in
  none)
    log "No hyper-key profile (TEEUP_KARABINER_HYPER=none). The two teeup ships are in $TEEUP_CAP_DIR/config/karabiner/."
    ;;
  right_command|caps_lock)
    # The core keyboard capability maps Caps Lock to Control through hidutil
    # and re-applies it at every login, so a Karabiner rule on the same key
    # is two mappings over one key.
    if [[ "$karabiner_hyper" == "caps_lock" ]] && ! cap_skipped keyboard; then
      warn "The keyboard capability already maps Caps Lock to Control through hidutil at every login, so the two would fight over one key. Put keyboard in TEEUP_SKIP in machines/<hostname>.conf, or set TEEUP_KARABINER_HYPER=right_command."
    fi
    if [[ -e "$karabiner_json" || -L "$karabiner_json" ]]; then
      log "Keeping your $karabiner_json; the shipped rule is at $TEEUP_CAP_DIR/config/karabiner/karabiner-$karabiner_hyper.json if you want to copy it in."
    else
      copy_config_once "$TEEUP_CAP_DIR/config/karabiner/karabiner-$karabiner_hyper.json" "$karabiner_json"
      log "Hyper key: hold $karabiner_hyper for command+control+option+shift."
    fi
    ;;
  *)
    warn "Unknown TEEUP_KARABINER_HYPER '$karabiner_hyper'; expected right_command, caps_lock or none. Nothing was written."
    ;;
esac
```

- [ ] **Step 7: Make the scripts executable and run the suite**

Run: `chmod +x capabilities/karabiner/install capabilities/karabiner/configure && bash tests/capabilities/karabiner.sh`
Expected: `Summary: 12/12 passed`.

- [ ] **Step 8: Run the whole suite and the checks**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning capabilities/karabiner/install capabilities/karabiner/configure tests/capabilities/karabiner.sh && git diff --check`
Expected: the suite count printed before this task, plus 1; everything else silent.

- [ ] **Step 9: Commit**

```bash
git add capabilities/karabiner tests/capabilities/karabiner.sh
git commit -m "Add the karabiner lazy capability"
```

---

### Task 8: `xcode` — Xcode from the App Store through `mas`

**Files:**
- Create: `capabilities/xcode/capability`, `capabilities/xcode/install`, `capabilities/xcode/configure`
- Test: `tests/capabilities/xcode.sh`

**Interfaces:**
- Consumes: `pkg_install <pkg> [command]` (`lib/pkg.sh`); `app_installed <app>` (`lib/lazy.sh`, plan 3b Task 1); `ui_confirm <prompt> [yes|no]` (`lib/ui.sh`); `have`, `log`, `ok`, `warn`, `run_cmd` (`lib/core.sh`).
- Produces: the capability `xcode` (`packages="mas"`, `apps="Xcode"`, `group=system`, `tier=lazy`, `interactive=true`, no `provides=`). It is a different capability from the core `xcode-clt`, which installs the Command Line Tools and stays untouched here.

**Real-Mac risk:** all of it. Whether `mas install 497799835` succeeds depends on an Apple Account being signed in to the App Store, on the machine's macOS being new enough for the Xcode the store offers, and on the password prompt mas raises for root; none of that can be exercised under the harness, which mocks `mas` outright. The `xcode-select --switch` line is printed rather than run for the same reason: it changes the toolchain for every compiler on the machine.

- [ ] **Step 1: Write the failing test**

Every test that would reach `ui_confirm` either pipes its answer or arranges for the question not to be asked. `lib/ui.sh` reaches for `gum` unless `TEEUP_NO_GUM` is set, and the harness `PATH` still has `/usr/bin`, so `TEEUP_NO_GUM=1` is exported in `setup`.

```bash file=tests/capabilities/xcode.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# The mas mock keeps the list of App Store apps in $HOME and, on install,
# creates the bundle under TEEUP_APPS_DIR the way the real one would create
# it under /Applications.
setup() {
  setup_test_env
  mock_macos_base
  hide_host_commands mas
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  mock_command_script mas <<'EOF2'
case "$1" in
  list) cat "$HOME/mas-list" 2>/dev/null ;;
  install)
    printf '%s Xcode (27.0)\n' "$2" >> "$HOME/mas-list"
    mkdir -p "$TEEUP_APPS_DIR/Xcode.app"
    ;;
esac
exit 0
EOF2
  # configure asks with ui_confirm, which reaches for gum whenever
  # TEEUP_NO_GUM is empty and gum is on PATH; /usr/bin is on the harness PATH.
  export TEEUP_NO_GUM=1
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  mkdir -p "$TEEUP_APPS_DIR"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_gets_mas_from_the_package_manager() {
  setup
  # TEEUP_TEST_MISSING hides the mocked mas from `have`, so pkg_install does
  # the install rather than reporting mas as already on PATH, and the
  # configure that `teeup install` runs next warns instead of asking a
  # question no test should have to answer.
  export TEEUP_TEST_MISSING="mas"
  local out
  out="$(DRY_RUN=true "$TEEUP" install xcode 2>&1)"
  assert_contains "$out" "Would execute: brew install mas" || return 1
  assert_not_contains "$out" "Download and install Xcode now" || return 1
  unset TEEUP_TEST_MISSING
  cleanup_test_env
}

test_install_gets_the_mas_port_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  export TEEUP_TEST_MISSING="mas"
  mock_command port 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install xcode 2>&1)"
  assert_contains "$out" "Would execute: sudo port install mas" || return 1
  unset TEEUP_TEST_MISSING
  cleanup_test_env
}

test_configure_asks_and_installs_on_yes() {
  setup
  local out
  out="$(printf 'y\n' | DRY_RUN=false "$TEEUP" configure xcode 2>&1)"
  assert_contains "$out" "signed in to the App Store" || return 1
  assert_contains "$out" "Download and install Xcode now (mas install 497799835)?" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mas install 497799835" || return 1
  cleanup_test_env
}

test_configure_takes_no_for_an_answer() {
  setup
  local out
  out="$(printf 'n\n' | DRY_RUN=false "$TEEUP" configure xcode 2>&1)"
  assert_contains "$out" "Not now. When you want it: teeup configure xcode" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "mas install" || return 1
  cleanup_test_env
}

test_configure_reports_a_mas_failure_with_the_sign_in_hint() {
  setup
  mock_command_script mas <<'EOF2'
case "$1" in
  list) exit 0 ;;
  install) echo "Not signed in" >&2; exit 1 ;;
esac
exit 0
EOF2
  local out
  out="$(printf 'y\n' | DRY_RUN=false "$TEEUP" configure xcode 2>&1)"
  assert_contains "$out" "mas could not install Xcode. Sign in to the App Store, then run: teeup configure xcode" || return 1
  cleanup_test_env
}

test_configure_asks_nothing_when_xcode_is_there() {
  setup
  mkdir -p "$TEEUP_APPS_DIR/Xcode.app"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure xcode 2>&1)"
  assert_contains "$out" "Xcode is installed." || return 1
  assert_not_contains "$out" "Download and install Xcode now" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "mas install" || return 1
  cleanup_test_env
}

test_configure_says_so_when_the_store_has_it_but_the_disk_does_not() {
  setup
  printf '497799835 Xcode (27.0)\n' > "$TEST_HOME/mas-list"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure xcode 2>&1)"
  assert_contains "$out" "The App Store already counts Xcode as installed for this account" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "mas install" || return 1
  cleanup_test_env
}

test_configure_without_mas_warns_instead_of_failing() {
  setup
  export TEEUP_TEST_MISSING="mas"
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" configure xcode 2>&1)" || rc=$?
  assert_success "$rc" "a missing mas must not fail the configure" || return 1
  assert_contains "$out" "mas is not on PATH, so Xcode cannot be fetched here" || return 1
  unset TEEUP_TEST_MISSING
  cleanup_test_env
}

test_the_developer_directory_is_printed_not_switched() {
  setup
  local out
  out="$(printf 'y\n' | DRY_RUN=false "$TEEUP" configure xcode 2>&1)"
  assert_contains "$out" "sudo xcode-select --switch $TEEUP_APPS_DIR/Xcode.app/Contents/Developer" || return 1
  assert_contains "$out" "sudo xcodebuild -license accept" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "xcode-select --switch" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "xcodebuild" || return 1
  cleanup_test_env
}

test_nothing_is_printed_when_the_tools_already_point_at_xcode() {
  setup
  mkdir -p "$TEEUP_APPS_DIR/Xcode.app"
  mock_command xcode-select 0 "$TEEUP_APPS_DIR/Xcode.app/Contents/Developer"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure xcode 2>&1)"
  assert_contains "$out" "The command line tools already point at $TEEUP_APPS_DIR/Xcode.app/Contents/Developer." || return 1
  assert_not_contains "$out" "sudo xcode-select --switch" || return 1
  cleanup_test_env
}

test_dry_run_downloads_nothing() {
  setup
  local out
  out="$(printf 'y\n' | DRY_RUN=true "$TEEUP" configure xcode 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: mas install 497799835" || return 1
  [[ ! -e "$TEEUP_APPS_DIR/Xcode.app" ]] || { echo "dry run installed Xcode"; return 1; }
  cleanup_test_env
}

test_it_is_lazy_interactive_and_shimless() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  assert_contains "$("$TEEUP" list --tier lazy)" "xcode " || return 1
  assert_equals "true" "$(cd "$TEEUP_PATH" && bash -c 'source lib/all.sh; cap_meta_get xcode interactive')" || return 1
  assert_equals "Xcode" "$(cd "$TEEUP_PATH" && bash -c 'source lib/all.sh; cap_meta_get xcode apps')" || return 1
  assert_equals "" "$(cd "$TEEUP_PATH" && bash -c 'source lib/all.sh; cap_meta_get xcode provides')" || return 1
  [[ ! -e "$TEST_HOME/.local/state/teeup/shims/xcode" ]] || { echo "xcode must not get a shim"; return 1; }
  cleanup_test_env
}

echo "capabilities/xcode"
run_test "install gets mas from the package manager" test_install_gets_mas_from_the_package_manager
run_test "install gets the mas port on macports" test_install_gets_the_mas_port_on_macports
run_test "configure asks and installs on yes" test_configure_asks_and_installs_on_yes
run_test "configure takes no for an answer" test_configure_takes_no_for_an_answer
run_test "configure reports a mas failure with the sign-in hint" test_configure_reports_a_mas_failure_with_the_sign_in_hint
run_test "configure asks nothing when Xcode is there" test_configure_asks_nothing_when_xcode_is_there
run_test "configure says so when the store has it but the disk does not" test_configure_says_so_when_the_store_has_it_but_the_disk_does_not
run_test "configure without mas warns instead of failing" test_configure_without_mas_warns_instead_of_failing
run_test "the developer directory is printed, not switched" test_the_developer_directory_is_printed_not_switched
run_test "nothing is printed when the tools already point at Xcode" test_nothing_is_printed_when_the_tools_already_point_at_xcode
run_test "dry run downloads nothing" test_dry_run_downloads_nothing
run_test "it is lazy, interactive and shimless" test_it_is_lazy_interactive_and_shimless
print_summary
```

- [ ] **Step 2: Run it and watch every test fail**

Run: `chmod +x tests/capabilities/xcode.sh && bash tests/capabilities/xcode.sh`
Expected: `Summary: 0/12 passed`, every failure tracing back to `Unknown capability: xcode`.

- [ ] **Step 3: Write the metadata**

`interactive=true` keeps stdin attached for the download question and for the password prompt mas raises by itself.

```ini file=capabilities/xcode/capability
summary="Xcode from the App Store, through mas"
group=system
tier=lazy
requires="package-manager"
provides=""
packages="mas"
casks=""
apps="Xcode"
interactive=true
```

- [ ] **Step 4: Write the install script**

```bash file=capabilities/xcode/install
#!/usr/bin/env bash
# mas is the App Store command line interface; the Homebrew formula and the
# MacPorts port are both named mas (7.0.0 in each), so one line covers both
# backends. The Xcode download itself is configure's job: it needs a signed-in
# App Store and a question first.
pkg_install mas mas
```

- [ ] **Step 5: Write the configure script**

The spec says this capability "checks `mas account`". It cannot: mas removed `account`, `region` and `signin` in pull request 1167 (merged 2025-12-28), and mas 7.0.0's command table has none of them. What replaces the check is a sentence saying who has to sign in, a question before a multi-gigabyte download, and mas's own error when nobody is signed in.

```bash file=capabilities/xcode/configure
#!/usr/bin/env bash
# Xcode is App Store software: no cask can install it, and mas needs an Apple
# Account already signed in to the App Store. mas 7 removed the `account`,
# `region` and `signin` commands (pull request 1167, merged 2025-12-28), so
# nothing can ask whether anybody is signed in; the honest flow is to say so,
# ask before a multi-gigabyte download, and repeat what mas answers.
# 497799835 is Xcode's App Store id.
xcode_id=497799835

if app_installed Xcode; then
  ok "Xcode is installed."
elif ! have mas; then
  warn "mas is not on PATH, so Xcode cannot be fetched here; install it with: teeup install xcode"
elif mas list 2>/dev/null | awk '{print $1}' | grep -qx "$xcode_id"; then
  log "The App Store already counts Xcode as installed for this account, but the app is not in ${TEEUP_APPS_DIR:-/Applications}; reinstall it from the App Store."
else
  log "Xcode is a multi-gigabyte App Store download, and mas can fetch it only once your Apple Account is signed in to the App Store (Apple menu, App Store, Sign In). The App Store gives you the newest Xcode this macOS supports."
  log "Installing App Store software needs root, and mas asks for your macOS password by itself."
  if ui_confirm "Download and install Xcode now (mas install $xcode_id)?" yes; then
    run_cmd mas install "$xcode_id" || warn "mas could not install Xcode. Sign in to the App Store, then run: teeup configure xcode"
  else
    log "Not now. When you want it: teeup configure xcode"
  fi
fi

# Switching the developer directory changes what every compiler on the
# machine uses, including the command line tools the xcode-clt capability
# installed, so this prints the commands rather than running them.
if app_installed Xcode; then
  xcode_developer_dir="$(xcode-select -p 2>/dev/null || true)"
  case "$xcode_developer_dir" in
    */Xcode.app/*)
      ok "The command line tools already point at $xcode_developer_dir."
      ;;
    *)
      log "Point the command line tools at Xcode when you want its SDKs, then accept the licence:"
      log "  sudo xcode-select --switch ${TEEUP_APPS_DIR:-/Applications}/Xcode.app/Contents/Developer"
      log "  sudo xcodebuild -license accept"
      ;;
  esac
fi
```

- [ ] **Step 6: Make the scripts executable and run the suite**

Run: `chmod +x capabilities/xcode/install capabilities/xcode/configure && bash tests/capabilities/xcode.sh`
Expected: `Summary: 12/12 passed`.

- [ ] **Step 7: Run the whole suite and the checks**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning capabilities/xcode/install capabilities/xcode/configure tests/capabilities/xcode.sh && git diff --check`
Expected: the suite count printed before this task, plus 1; everything else silent.

- [ ] **Step 8: Commit**

```bash
git add capabilities/xcode tests/capabilities/xcode.sh
git commit -m "Add the xcode lazy capability"
```

---

### Task 9: the README and CONTRIBUTING entries

**Files:**
- Modify: `README.md` (the "Lazy capabilities" section), `CONTRIBUTING.md` (three items appended to the "Adding a capability (new runtime)" list)

**Interfaces:**
- Consumes: the README bullet plan 3b Task 11 wrote, and whatever number CONTRIBUTING's last item carries when this runs.
- Produces: no code. The two answers keys this phase adds, `TEEUP_DBS` and `TEEUP_KARABINER_HYPER`, are documented here and nowhere else.

**Real-Mac risk:** none; this task ships prose.

- [ ] **Step 1: Extend the README's lazy-capability list**

The anchor is the "Shipped lazy capabilities" bullet and it ends the section, just before the `### Keeping a Mac up to date` heading.

```markdown edit-old=README.md
- **Shipped lazy capabilities:** `colima` (Colima, the Docker CLI and the
  Compose plugin; `docker` and `colima` shims), `ai` (`claude codex gemini
  copilot opencode` shims), `herdr`, `tmux` (with a `~/.config/tmux/tmux.conf`
  that is yours after the first copy, skipped when you already have a
  `~/.tmux.conf`), `ollama` (app and CLI, no models) and `cursor` (app and
  `cursor` command).
  `teeup status` lists the shims in place and the dev-envs installed.
```

```markdown edit-new=README.md
- **Shipped lazy capabilities:** `colima` (Colima, the Docker CLI and the
  Compose plugin; `docker` and `colima` shims), `ai` (`claude codex gemini
  copilot opencode` shims), `herdr`, `tmux` (with a `~/.config/tmux/tmux.conf`
  that is yours after the first copy, skipped when you already have a
  `~/.tmux.conf`), `ollama` (app and CLI, no models) and `cursor` (app and
  `cursor` command), and:
  - **Containers and Kubernetes:** `k8s` (`kubectl`, `helm` and `k9s` through
    mise, with a shim each), `lazydocker` (the container TUI, over Colima's
    socket) and `docker-dbs` (below).
  - **Browsers:** `chrome`, `brave`, `arc` and `zen`. Firefox Developer
    Edition is in the daily tier rather than here.
  - **Communication:** `slack`, `zoom`, `signal`, `whatsapp`, `telegram`,
    `discord` and `teams`.
  - **Productivity:** `1password`, `raycast`, `bruno`, `notion` and `typora`.
    Obsidian is in the daily tier.
  - **The rest:** `karabiner` (below) and `xcode`, which installs `mas` and
    asks before pulling Xcode from the App Store; sign in to the App Store
    first, because mas 7 can no longer do it for you.

  `teeup status` lists the shims in place and the dev-envs installed.
- **Databases on demand.** `teeup configure docker-dbs` asks which database
  should run and starts it as a container on Colima, published to
  `127.0.0.1` only: PostgreSQL 18, MySQL 8.4, MariaDB 11.8, Redis 7 or
  MongoDB. Run it again to add another; a container that already exists is
  started rather than created a second time. `TEEUP_DBS="postgres redis"` in
  the answers file or `machines/<hostname>.conf` skips the question. The
  containers take local connections without a password, which is what makes
  them useful for development and why they listen on the loopback address
  only.
- **A hyper key, if you want one.** `teeup install karabiner` installs
  Karabiner-Elements and lists the four approvals macOS asks for (background
  services, Accessibility, Input Monitoring, the driver extension). If you
  have no `~/.config/karabiner/karabiner.json` of your own, it also installs
  a profile that turns one key into Hyper (command, control, option and
  shift at once): right command by default, Caps Lock with
  `TEEUP_KARABINER_HYPER=caps_lock`, or nothing with `none`. The core
  `keyboard` capability already maps Caps Lock to Control through `hidutil`
  at every login, so those two share a key only when `keyboard` is in
  `TEEUP_SKIP`.
```

- [ ] **Step 2: Append three items to CONTRIBUTING**

Append after the **last numbered item** of the "Adding a capability (new runtime)" list, continuing its numbering. The `edit-old` below is item 27, the last one phase 4b appended, so these three are 28 to 30.

```markdown edit-old=CONTRIBUTING.md
    `TEEUP_MENU_PICKER=fzf` and mocks `fzf`; no test may need either program
    installed.
```

```markdown edit-new=CONTRIBUTING.md
    `TEEUP_MENU_PICKER=fzf` and mocks `fzf`; no test may need either program
    installed.
28. A capability whose whole content is one GUI cask needs no code of its
    own: `install` is `cask_app_install <cask> "<App Name>" <download url>`
    and `configure` is `cask_app_report "<App Name>" ["one more line"]`, both
    in `lib/lazy.sh`. Put the cask token in `casks=` and the bundle name in
    `apps=` so `teeup launch`, `teeup remove` and `teeup doctor` all work
    from metadata, and check both against
    `https://formulae.brew.sh/api/cask/<token>.json` before you write them:
    the bundle is often not what the app is called (`zoom` installs
    `zoom.us.app`), and a cask that installs a `pkg` declares no app artifact
    at all, so its uninstall stanza is where the path shows up. Add a row to
    `tests/capabilities/browsers.sh`, `communication.sh` or
    `productivity.sh` rather than a new suite.
29. A capability that asks a question sets `interactive=true` (otherwise
    `cap_run` redirects stdin from `/dev/null` and the prompt hangs on
    nothing), reads an answers key first so it can run unattended
    (`TEEUP_DBS`, `TEEUP_KARABINER_HYPER`), and stays idempotent, because
    `configure` is how the question is asked again: `docker-dbs` starts a
    container that exists instead of creating a second one.
30. A test that drives a prompt or a picker must `export TEEUP_NO_GUM=1`.
    `lib/ui.sh` uses `gum` whenever `TEEUP_NO_GUM` is empty and `gum` is on
    `PATH`, and the harness `PATH` keeps `/usr/bin`, so on a machine with
    gum installed there the test would drive a full-screen prompt instead of
    the plain fallback that reads stdin.
```

- [ ] **Step 3: Check the two documents**

Run: `grep -c 'docker-dbs' README.md && grep -c 'TEEUP_KARABINER_HYPER' README.md && grep -c 'cask_app_install' CONTRIBUTING.md && grep -n 'TEEUP_NO_GUM' CONTRIBUTING.md`
Expected: `2`, `1`, `1`, and four numbered lines for `TEEUP_NO_GUM` — two in item 27, which phase 4b wrote about pickers, and two in the item 30 added here (`grep -c` counts lines, not occurrences).

- [ ] **Step 4: Run the whole suite and the checks**

Run: `./tests/run.sh && ./bin/teeup commands --check && git diff --check`
Expected: the same suite count as the task before this one (no new suite); everything else silent.

- [ ] **Step 5: Commit**

```bash
git add README.md CONTRIBUTING.md
git commit -m "Document the phase 4c lazy capabilities"
```

---

## Verification

Run these from the checkout root once Task 9 is committed.

1. **The whole suite.**

```bash
./tests/run.sh
```

Expected: `All N suites passed.`, where N is the count `main` printed before Task 1 plus 8 — one new suite in each of Tasks 1, 2, 3, 4, 5, 6, 7 and 8, and none in Task 9.

2. **Metadata lint and the working tree.**

```bash
./bin/teeup commands --check && git diff --check && git status --porcelain
```

Expected: all three silent, exit 0.

3. **Shellcheck over everything this phase touched.**

```bash
shellcheck --severity=warning lib/lazy.sh \
  capabilities/k8s/install capabilities/k8s/configure capabilities/k8s/remove \
  capabilities/lazydocker/install capabilities/lazydocker/configure \
  capabilities/docker-dbs/install capabilities/docker-dbs/configure \
  capabilities/brave/install capabilities/brave/configure \
  capabilities/arc/install capabilities/arc/configure \
  capabilities/zen/install capabilities/zen/configure \
  capabilities/slack/install capabilities/slack/configure \
  capabilities/zoom/install capabilities/zoom/configure \
  capabilities/signal/install capabilities/signal/configure \
  capabilities/whatsapp/install capabilities/whatsapp/configure \
  capabilities/telegram/install capabilities/telegram/configure \
  capabilities/discord/install capabilities/discord/configure \
  capabilities/teams/install capabilities/teams/configure \
  capabilities/1password/install capabilities/1password/configure \
  capabilities/raycast/install capabilities/raycast/configure \
  capabilities/bruno/install capabilities/bruno/configure \
  capabilities/notion/install capabilities/notion/configure \
  capabilities/typora/install capabilities/typora/configure \
  capabilities/karabiner/install capabilities/karabiner/configure \
  capabilities/xcode/install capabilities/xcode/configure \
  tests/lib/lazy.sh tests/capabilities/k8s.sh tests/capabilities/lazydocker.sh \
  tests/capabilities/docker-dbs.sh tests/capabilities/browsers.sh \
  tests/capabilities/communication.sh tests/capabilities/productivity.sh \
  tests/capabilities/karabiner.sh tests/capabilities/xcode.sh
```

Expected: silent. (CI's own line already globs `capabilities/*/install`, `configure` and `tests/*.sh`, so this is the same set it will check.)

4. **The lazy tier holds every capability this phase adds.**

```bash
./bin/teeup list --tier lazy | awk '{print $1}' | tr '\n' ' '; echo
```

Expected, on a tree with phases 3a, 3b and 4c applied:

```text
1password ai arc brave bruno chrome colima cursor discord docker-dbs herdr k8s karabiner lazydocker neovim notion ollama raycast signal slack teams telegram tmux typora vscode whatsapp xcode zen zoom
```

5. **The shims, in a throwaway home.**

```bash
H="$(mktemp -d)"
HOME="$H" XDG_CONFIG_HOME="$H/.config" XDG_STATE_HOME="$H/.local/state" \
  ./bin/teeup configure teeup-runtime >/dev/null
ls "$H/.local/state/teeup/shims" | tr '\n' ' '; echo
rm -rf "$H"
```

Expected (the four new ones are `helm`, `k9s`, `kubectl` and `lazydocker`; none of the cask capabilities has one):

```text
claude code codex colima copilot cursor docker gemini helm herdr k9s kubectl lazydocker nvim ollama opencode tmux
```

6. **Every install is a faithful preview under `DRY_RUN`.**

```bash
H="$(mktemp -d)"
for c in k8s lazydocker docker-dbs brave arc zen slack zoom signal whatsapp \
         telegram discord teams 1password raycast bruno notion typora \
         karabiner xcode; do
  HOME="$H" XDG_CONFIG_HOME="$H/.config" XDG_STATE_HOME="$H/.local/state" \
    TEEUP_DBS=none TEEUP_KARABINER_HYPER=none TEEUP_NO_GUM=1 DRY_RUN=true \
    ./bin/teeup install "$c" >/dev/null 2>&1 </dev/null
done
find "$H" ! -path "$H" ! -path "$H/.local" ! -path "$H/.local/state" \
     ! -path "$H/.local/state/mise*" | wc -l
rm -rf "$H"
```

Expected: `0`. The one directory a dry run can leave behind is mise's own state (`~/.local/state/mise/tracked-configs`), which mise writes for itself when `mise_global_state` asks it about the global config; nothing teeup writes survives a dry run.

7. **bash 3.2.** Put a bash 3.2 build first on `PATH` and run the suite again, so `tests/run.sh`, `bin/teeup`, and every capability script parse and run the way they will on macOS:

```bash
PATH="/path/to/bash32/bin:$PATH" bash ./tests/run.sh
```

Expected: the same `All N suites passed.`

---

## Self-review

### Spec coverage

| Spec requirement | Where it lands |
|---|---|
| Interview table, Containers: "k8s: kubectl, helm, k9s via mise, lazy" | Task 1 (`k8s`, `mise_ensure_global` for all three) |
| Section 6: "Shims exist only for commands macOS lacks: `docker`, `colima`, `kubectl`, `helm`, `k9s`, `tmux`, `herdr`, `ollama`, `lazydocker`" | Tasks 1 and 2 add the four this phase owns; phase 3b added the other five |
| Interview table, Databases: "Omarchy `docker-dbs` pattern: lazy picker starting localhost containers on Colima" | Task 3 |
| Interview table, Browsers: "Chrome, Firefox, Brave/Arc/Zen: all lazy casks" | Task 4 (`brave`, `arc`, `zen`); `chrome` is phase 3a's lazy cask and Firefox Developer Edition its daily browser |
| Interview table, Comms: "Slack, Zoom, Signal/WhatsApp/Telegram, Discord/Teams: all lazy" | Task 5, all seven |
| Interview table, Productivity: "Obsidian, 1Password, Raycast, Bruno/Notion/Typora: all lazy" | Task 6 for the five; Obsidian is phase 3a's daily capability |
| Interview table, Keyboard: "Karabiner optional lazy with hyper-key config" | Task 7 |
| Interview table, Package managers: "`mas` for App Store (Xcode etc.)"; section 4a: "including `xcode` (`mas install 497799835` after checking `mas account`)" | Task 8, with the `mas account` half rewritten because mas removed the command (Decision 13) |
| Section 6: "Lazy covers languages, containers, Kubernetes, `docker-dbs`, AI CLIs, Ollama, Cursor, Herdr, tmux, Karabiner, Xcode, browsers beyond Chrome, communication and productivity apps" | Tasks 1 to 8 finish the list; every other name on it is phase 3b's |
| Section 12 step 5: "Add a row to `share/teeup/menu.json`" | **Not done here, on purpose.** 4b owns that file and is written in parallel, so the twenty rows are a handoff, recorded in "Depends on" and again below. Nothing else in the capability model needs them: `teeup list`, `teeup install`, `teeup launch` and `teeup remove` are all metadata-driven. |
| Section 4: `capabilities/<cap>/doctor` | No doctor script ships here. 4b's `doctor_metadata_check` already checks `packages`, `casks`, `apps` and `provides` from metadata, which is the whole of what these capabilities could claim; the two checks that need more (Karabiner's approvals, an Apple Account signed in) are listed under "Deliberately deferred". |

### Deferred items from earlier phases

The lists named in the phase 4/5 brief were read in full: the phase 1 final review's triage table, the phase 2a final review and re-review triage, `.superpowers/plan3/pr11-deferred.md`, and the "Deliberately deferred" sections of plans 3a and 3b. **None of their entries belongs to a lazy capability**: they are runtime, library, editor, `macos-defaults` and hook items owned by phases 4a, 4b and 5. One entry has a sibling here rather than a fix: "the AeroSpace manual-step text prints on every run". This plan does not touch AeroSpace (its capability is phase 2b's), but Karabiner has exactly the same problem and Task 7 answers it with `state_done ensure karabiner-permissions`, so the four approvals are a list once and a single line afterwards. If that reads well on hardware, AeroSpace can take the same three lines later.

### Placeholder scan

Searched this document for `TBD`, `TODO`, `FIXME`, `implement later`, `Similar to Task`, `appropriate error handling`, `add validation`, `handle edge cases` and for a bare `...` standing in for code: no hits. Every new file appears in full (four `k8s` files, three each for `lazydocker` and `docker-dbs`, three each for fifteen cask capabilities, two Karabiner profiles, three `xcode` files, and nine test files or test additions). Every change to an existing file is an `edit-old`/`edit-new` pair quoting text that occurs exactly once at that point in the execution, which the transcription check below enforces mechanically.

### Name and type consistency across tasks

- The two helpers are `cask_app_install <cask> <app name> <download url>` and `cask_app_report <app name> [extra line]`, defined once in `lib/lazy.sh` (Task 4) and called by sixteen capabilities (fifteen cask capabilities plus `karabiner`), spelled identically in all of them.
- Capability directory names, `casks=` tokens and `apps=` bundle names agree between each capability file and the row that tests it: `brave`/`brave-browser`/`Brave Browser`, `arc`/`arc`/`Arc`, `zen`/`zen`/`Zen`, `slack`/`slack`/`Slack`, `zoom`/`zoom`/`zoom.us`, `signal`/`signal`/`Signal`, `whatsapp`/`whatsapp`/`WhatsApp`, `telegram`/`telegram`/`Telegram`, `discord`/`discord`/`Discord`, `teams`/`microsoft-teams`/`Microsoft Teams`, `1password`/`1password`/`1Password`, `raycast`/`raycast`/`Raycast`, `bruno`/`bruno`/`Bruno`, `notion`/`notion`/`Notion`, `typora`/`typora`/`Typora`, `karabiner`/`karabiner-elements`/`Karabiner-Elements;Karabiner-EventViewer`, `xcode`/(no cask)/`Xcode`.
- Answers keys: `TEEUP_DBS` is read only by `capabilities/docker-dbs/configure` and set only by tests and the user; `TEEUP_KARABINER_HYPER` only by `capabilities/karabiner/configure`. Both are documented in Task 9's README text and nowhere else.
- Library functions consumed from earlier phases are used with the signatures those plans publish: `mise_ensure_global <tool> [version]`, `pkg_install <pkg> [command]`, `cask_install <cask>`, `casks_supported`, `app_installed <app>`, `copy_config_once <src> <dest>`, `state_done ensure <name>`, `answers_get <KEY> [default]`, `cap_skipped <name>`, `ui_choose <prompt> <option...>`, `ui_confirm <prompt> [yes|no]`.
- User-visible strings asserted in a test and produced in a script agree word for word: `<app> is installed; open it with: open -a '<app>'` and `<app>.app is not in <dir>; the install step above says why.` (Task 4's helper, matching `capabilities/chrome/configure` on `main`), `<app> is a cask and MacPorts has none; download it from <url>` (Task 4's helper, asserted by Tasks 4, 5, 6 and 7), `kubectl is provided by capability k8s. Install now?` (plan 3b's `cmd_lazy_run`, asserted by Task 1), `Hyper key: hold right_command for command+control+option+shift.` (Task 7), `Download and install Xcode now (mas install 497799835)?` (Task 8).
- Per-suite `run_test` counts, taken from the runs recorded below: `capabilities/k8s` 9, `capabilities/lazydocker` 9, `capabilities/docker-dbs` 11, `capabilities/browsers` 9, `capabilities/communication` 8, `capabilities/productivity` 8, `capabilities/karabiner` 12, `capabilities/xcode` 12, and `lib/lazy.sh` 14 before Task 4 and 17 after. Suites rise by one in Tasks 1, 2, 3, 4, 5, 6, 7 and 8 and stay flat in Task 9: eight new suites.
- Every command a test mocks is called by bare name in the shipped scripts (`brew`, `port`, `mise`, `docker`, `colima`, `mas`, `open`, `xcode-select`); no shipped script here names an absolute path to a binary.

### External facts and their sources (checked 2026-09-16)

| Fact the plan relies on | Source |
|---|---|
| Cask tokens, current versions, application bundles and macOS floors: `brave-browser` 1.95.101.0 / `Brave Browser.app` / macOS 13+, `arc` 1.164.0 / `Arc.app` / macOS 13+, `zen` 1.22.1b / `Zen.app` (old token `zen-browser`), `slack` / `Slack.app`, `signal` / `Signal.app` / macOS 12+, `whatsapp` / `WhatsApp.app` / macOS 12+, `telegram` / `Telegram.app`, `discord` / `Discord.app`, `1password` / `1Password.app` / macOS 12+, `raycast` / `Raycast.app`, `bruno` / `Bruno.app`, `notion` / `Notion.app` / macOS 12+, `typora` / `Typora.app` | `https://formulae.brew.sh/api/cask/<token>.json`, one fetch per token |
| The two pkg casks declare no app artifact, and their bundle paths come from their uninstall stanzas: `zoom` deletes `/Applications/zoom.us.app`, `microsoft-teams` (macOS 14+) deletes `/Applications/Microsoft Teams.app` and deselects the bundled `com.microsoft.autoupdate` choice | the `artifacts` arrays of the same two cask JSON documents |
| `karabiner-elements` 16.3.0 is a pkg cask that links `karabiner_cli` into the Homebrew prefix and zaps `~/.config/karabiner`; the package installs `/Applications/Karabiner-Elements.app` and `/Applications/Karabiner-EventViewer.app` | the cask JSON, and `pqrs-org/Karabiner-Elements` `src/scripts/uninstall_core.sh` lines 26-34 (`rm -rf '/Applications/Karabiner-Elements.app'`, `rm -rf '/Applications/Karabiner-EventViewer.app'`) |
| Karabiner's `karabiner.json` root structure (`profiles[]` with `name`, `selected`, `complex_modifications.rules[]`) and the keys of a `basic` manipulator (`type`, `from.key_code`, `from.modifiers.optional`, `to[].key_code`, `to[].modifiers`, `to_if_alone[]`) | karabiner-elements.pqrs.org, `docs/json/root-data-structure/` and `docs/json/complex-modifications-manipulator-definition/` |
| The four approvals macOS asks for, in order, and the keyboard-layout question that follows | karabiner-elements.pqrs.org, `docs/getting-started/installation/` (page last modified 2026-05-02) |
| Formulae: `lazydocker` 0.25.2, `mas` 7.0.0, `helm` 4.3.0 (old name `kubernetes-helm`), `k9s` 0.51.0, `kubernetes-cli` 1.37.0 with `kubectl` as an alias (there is no formula named `kubectl`) | `https://formulae.brew.sh/api/formula/<name>.json` |
| MacPorts has `lazydocker` 0.25.2, `mas` 7.0.0, `kubectl` 1.37.0, `helm` 4.3.0 and `k9s` 0.51.0, all under those names | `https://ports.macports.org/api/v1/ports/?name=<name>` |
| mise registry entries: `kubectl` → `aqua:kubernetes/kubernetes/kubectl`, `helm` → `aqua:helm/helm`, `k9s` → `aqua:derailed/k9s`, `lazydocker` → `aqua:jesseduffield/lazydocker` | `mise registry` on mise 2026.9.4 |
| `mise unuse` "Remove tool requests from configuration and prune unused installations", takes `-g, --global` ("Use the global config file … instead of the local one"), and prunes "only when no remaining tracked config or tool stub needs them"; `mise uninstall` "only removes the installed version; it does not modify mise.toml"; `mise -C / unuse --global <unknown tool>` exits 0 | `mise unuse --help`, `mise uninstall --help`, and a run against a throwaway `MISE_CONFIG_DIR` on 2026.9.4 |
| mas 7.0.0's command table has `install`, `list`, `uninstall`, `signout` and no `account`, `region` or `signin`; `install` "require[s] root privileges" and "If run without root privileges, mas requests them as necessary"; `install` requires "an Apple Account signed in to the App Store" | `mas-cli/mas` `README.md` on `main` (Commands, Root Privileges, App Store Apple Account Requirements) and pull request 1167, "Remove `account`, `region` & `signin`", merged 2025-12-28 |
| Xcode's App Store id is 497799835 | Apple's lookup API: `https://itunes.apple.com/lookup?id=497799835` returns `trackId` 497799835, `trackName` "Xcode", `sellerName` "Apple Inc." |
| The `docker-dbs` table (images, tags, container names, published ports, environment variables) and the picker's shape | Omarchy 4.0.0.alpha, `/usr/share/omarchy/bin/omarchy-install-docker-dbs`; the `pkexec` wrapper this plan drops is `/usr/share/omarchy/bin/omarchy-launch-docker-tui` |
| `postgres:18`, `mysql:8.4`, `mariadb:11.8`, `redis:7` and `mongo:noble` each publish an `arm64/v8` image | `https://hub.docker.com/v2/repositories/library/<name>/tags/<tag>` |
| `POSTGRES_HOST_AUTH_METHOD=trust` ("then `POSTGRES_PASSWORD` is not required"), `MYSQL_ROOT_PASSWORD`, `MYSQL_ALLOW_EMPTY_PASSWORD`, `MARIADB_ROOT_PASSWORD`, `MARIADB_ALLOW_EMPTY_ROOT_PASSWORD`, `MONGO_INITDB_ROOT_USERNAME`, `MONGO_INITDB_ROOT_PASSWORD` are the documented variables of those images | the five images' Docker Hub descriptions |
| `mcr.microsoft.com/mssql/server:2022-latest` answers with a single `application/vnd.docker.distribution.manifest.v2+json` document rather than a manifest list, so there is no arm64 variant | direct fetch of `https://mcr.microsoft.com/v2/mssql/server/manifests/2022-latest` with the manifest-list `Accept` header |
| Colima does "Automatic Port Forwarding" | `abiosoft/colima` `README.md`, feature list |
| lazydocker's user config on macOS is `~/Library/Application Support/jesseduffield/lazydocker/config.yml` | `jesseduffield/lazydocker` `docs/Config.md` |

### What is not verified

- **Arc's maintenance status.** The installable facts are first-party and current (the `arc` cask is live at 1.164.0 and installs `Arc.app`). That Arc is feature-frozen after Atlassian's acquisition of The Browser Company, taking Chromium security updates only, comes from secondary reporting: `arc.net` and `resources.arc.net` are behind a JavaScript and Cloudflare wall that neither `curl` nor a fetch could read on 2026-09-16. The capability installs Arc either way; what rests on the unverified half is one sentence in its `summary` and one `log` line. If that sentence turns out to be wrong, the fix is one word in two files.
- **`brew list --formula kubectl`** resolving the alias to `kubernetes-cli` was not tested, and nothing depends on it: `k8s` installs through mise, and its `packages=` is empty, so `pkg_installed` is never asked about `kubectl`.
- **Every install and launch on hardware.** No cask has been installed, no App Store download attempted, no container started; each task's Real-Mac risk note names what its own tests cannot reach.

### Deliberately deferred

- **`share/teeup/menu.json` rows for these twenty capabilities.** 4b owns the file and is being written in parallel; `group=browsers`, `communication`, `productivity` and `containers` are there so the rows can be grouped without reading a script.
- **A `doctor` script for `karabiner`** (are the background services approved, is the DriverKit extension loaded, does `karabiner_cli --version` answer) and **for `xcode`** (is an Apple Account signed in). Both need machine state that only a Mac has, and 4b owns the doctor runner.
- **A `remove` script for `docker-dbs`.** Removing the capability leaves the containers running on purpose: a database holds data, and `docker rm -f` is not something a capability should do on the user's behalf. The configure's closing lines name the two commands.
- **The 1Password CLI (`op`)**, its `1password-cli` cask, and the SSH-agent wiring that would go with it. teeup's own secrets live in the macOS Keychain through the `secrets` capability, so the CLI is a separate decision rather than part of installing the app.
- **Retagging `chrome`, `firefox-developer-edition` and `obsidian`** from `group=apps` to the new `browsers` and `productivity` groups. Nothing reads `group=` yet; the change belongs with the menu rows that would use it.
- **`k9s` and `lazydocker` configuration.** Both have their own config files and neither is shipped, so a theme for them is a phase 4d question, not a 4c one.
- **A themed template for anything here.** None of these tools reads a palette teeup renders; the themed templates are phase 4d's.


### bash 3.2 run (recorded by the controller, 2026-09-16)

The transcription tree for this plan (`main` + 3a + 3b + 4a + this plan's nine
tasks) was run again with a bash 3.2.0 build first on `PATH`, so `tests/run.sh`,
`bin/teeup` and every capability script parsed and ran the way they will on
macOS: `All 56 suites passed.`
