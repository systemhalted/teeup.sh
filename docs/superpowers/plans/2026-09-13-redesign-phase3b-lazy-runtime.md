# teeup Redesign, Phase 3b: Lazy Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make everything outside the core and daily tiers arrive on first use: shims for lazy commands, `teeup lazy-run`, `teeup launch` for GUI apps, `teeup install dev-env <lang>` through mise, mise-backed wrappers for the AI CLIs, and the first lazy capabilities (`colima` as the shim round-trip proof, plus `ai`, `herdr`, `tmux`, `ollama` and `cursor`).

**Architecture:** Two new libraries. `lib/lazy.sh` turns every `tier=lazy` capability's `provides=` into a shim under `$TEEUP_STATE_DIR/shims` (written by `teeup-runtime configure`, appended last on `PATH` by the zsh layer phase 2a already ships) and holds the PATH walk, the terminal check and the app lookup behind `bin/teeup`'s new `lazy-run` and `launch` verbs. `lib/mise.sh` holds the one correct way to ask mise "is this tool requested globally, and is it installed" (lifted out of `capabilities/mise/configure`), the install-on-first-call wrapper writer, and `dev_env_install`. Nothing in the runtime knows a capability by name, so the lazy capabilities plan 3a adds (`neovim`, `vscode`, `chrome`) get their shims and launchers with no change here.

**Tech Stack:** bash 3.2 (macOS stock), BSD `sed`/`awk`/`grep`, shellcheck, Homebrew formulae and casks with MacPorts degradation, mise 2026.9 (`use -g`, `ls --global --installed`, `where`, `x`, `-C`), the phase 1 mock-binary test harness.

**Spec:** `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md`. This plan implements section 6 (lazy installation mechanism), the `~/.local/state/teeup/shims/` and `~/.local/bin/` rows of section 4b, the `provides=` rules of section 4a, the `teeup launch` and `teeup install dev-env` entries of the CLI surface, the AI CLIs, Languages, Containers and Herdr rows of the interview table, the "Herdr is gated on a phase 3 check" sentence of section 6, and the phase 3 gate ("shim round-trip test") of the migration table.

**Sibling plan and the seam:** plan 3a (`docs/superpowers/plans/2026-09-13-redesign-phase3a-daily-tier.md`) is written and executed in parallel. It owns the daily capabilities `emacs zed firefox-developer-edition obsidian` and the lazy capabilities `neovim` (`provides="nvim"`), `vscode` (`provides="code"`, `apps="Visual Studio Code"`) and `chrome` (`apps="Google Chrome"`, no `provides`), their theme and font hooks (which do nothing unless teeup installed that editor), the JSON settings helpers `json_set_key`, `json_merge_key` and `json_quote` (in `lib/files.sh`, so 3a leaves `lib/all.sh` to this plan), the `TEEUP_EMACS_FLAVOR` answer and the spec amendment recording the user's 2026-09-13 decision. 3a's Task 4 completes `capabilities/daily.list` (`emacs zed firefox-developer-edition obsidian`) and adds `chrome` with no `provides`; its Task 5 adds `neovim` (`provides="nvim"`) and its Task 6 `vscode` (`provides="code"`). Its Neovim and VS Code hooks test `have nvim` and `have code`, which Task 1's shim-aware `have` keeps false when only a shim exists. This plan owns every new `bin/teeup` verb, the shims directory and its generation, `lib/lazy.sh`, `lib/mise.sh`, and the capabilities named above. Neither plan depends on the other's tasks: shim generation, `teeup list`'s lazy column and `launch` are driven by metadata alone, so 3a's lazy capabilities work the moment both plans are on `main`, whichever lands first. This plan edits neither `capabilities/core.list` nor `capabilities/daily.list` (nothing here is core or daily) and does not edit the spec. The one exception is CONTRIBUTING numbering: this plan is written to execute after 3a (the recommended order — see Verification), and Task 11 Step 3's `edit-old`/`edit-new` pair for CONTRIBUTING's "Adding a capability (new runtime)" list anchors on 3a's last item on that assumption, appending as items 16 to 19; the alternative anchor and numbering for a 3b-first execution is given alongside it, for reference, and is not applied by that step.

---

## Global Constraints

- bash 3.2 compatible everywhere: no `mapfile`, `declare -A`, `${var,,}`/`${var^^}`, `readarray`, `readlink -f`; no same-line `local` back-references (`local a=1 b=$a`); `10#$n` for arithmetic on user-typed numbers. bash 3.2 mis-parses a quoted pattern containing `/` inside `${var//pat/repl}`: use `replace_literal` (`lib/files.sh`). Run `shopt -u patsub_replacement 2>/dev/null || true` before a `${var//}` replacement whose replacement text contains `&`. Nothing in this plan uses `${var//}`.
- BSD tools only: no GNU-only flags for `sed`, `grep`, `date`, `mktemp`, `sort`, `readlink`, `stat`, `env`; `sed -i.bak` (both seds accept it) followed by `rm` of the backup; no `\t` or `\n` inside a `sed` replacement; awk gets values through `ENVIRON`, never `-v`, when they may contain backslashes.
- Capability scripts start with `#!/usr/bin/env bash`, run as `bash -eu` with `lib/all.sh` loaded and `answers_load` done, use no `local`, and call mocked commands by bare name. `set -e` fires on a failing command anywhere in a script, so a command that may fail harmlessly carries `|| warn ...` or sits in an `if`; never end a script with `[[ ]] && cmd`. Every mutation goes through `run_cmd`/`run_privileged` or a primitive with its own `DRY_RUN` guard (`write_managed_file`, `copy_config_once`, `append_once`, `_state_touch`; this plan adds `shim_write`, `shims_generate` and `mise_wrapper_write`, all built on `write_managed_file` and `run_cmd`). `DRY_RUN=true` changes nothing.
- Paths: `user_config_dir` for `~/.config`; `TEEUP_CONFIG_DIR` and `TEEUP_STATE_DIR` honoured; `DOCKER_CONFIG` and `MISE_CONFIG_DIR` honoured where docker's and mise's own files are touched. Paths with spaces and shell metacharacters must work: Task 1 tests a checkout path with a space, a quote and a dollar sign, Task 5 a `DOCKER_CONFIG` with a space, Task 6 a `$HOME` with spaces.
- Machine file precedence (`answers`, then `machines/<hostname>.conf`) for every consumer of an answer: `bin/teeup` runs `answers_load` before any verb, so `TEEUP_SKIP` and `TEEUP_PACKAGE_MANAGER` from the machine file reach `lazy-run`, `launch`, `dev-env` and `shims_generate`.
- `capability` metadata contract: `summary group tier requires provides packages casks apps interactive`. `provides` never names a command macOS ships (`python3 ruby java git perl`; `cap_check` already enforces it). A core or daily capability must be in its tier list or `teeup commands --check` fails; every capability in this plan is `tier=lazy`, so no list changes. `apps` is `;`-separated (Task 1 fixes that convention, because application names contain spaces).
- Tests: `tests/helper.sh` (temp `HOME`, `MOCK_BIN` first on the narrowed `PATH` `$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin`, `mock_command`, `mock_command_script`, `mock_macos_base`, `TEEUP_TEST_MISSING`, `TEEUP_PKG_PREFIX`, `TEEUP_APPS_DIR`). The narrowed `PATH` hides Homebrew but not `/usr/bin`: an `ubuntu-latest` runner has `docker` there, and a developer's machine may have `tmux`, `herdr`, `ollama` or `cursor` on it. Hide what a fresh Mac lacks with `TEEUP_TEST_MISSING` (by name) or `hide_host_commands` (by path, Task 1) before asserting an install. CI runs `macos-14`, `macos-15-intel` and `ubuntu-latest`; a test that passes on only one of them, or only on a developer's machine, is a defect.
- Every task ends with `./tests/run.sh` green, `./bin/teeup commands --check` silent with exit 0, `shellcheck --severity=warning` clean on every new or edited script and test, `git diff --check` clean, and **one** commit with a plain imperative subject and no trailer of any kind (no `Co-Authored-By`, no `Claude-Session`, no "Generated with").
- Suite counts: `tests/run.sh` ends with `All N suites passed.` Never hard-code N. Each task states "the suite count printed before this task, plus K", so the plan stays right whether 3a or 3b lands first.
- Nothing in this phase has run on a real Mac. Each task carries a **Real-Mac risk** note naming what only hardware proves.
- Verify, do not guess: every package, cask, port, mise registry name, CLI flag and file location below was checked against upstream on 2026-09-13; the sources are listed in the Self-review. A name that does not appear there is not to be introduced during execution without the same check.
- Plain prose in every comment, log line and doc: none of "No X, no Y" chains, "That's the whole ...", "Don't X it. Y it.", "Sit with that", "You already know", "is the entire", "The punchline", "Worth naming", "X is real, and ...".

---

## Contracts this plan publishes

1. **The shim.** `$TEEUP_STATE_DIR/shims/<command>` is a four-line executable:
   ```sh
   #!/bin/bash
   # teeup lazy shim; regenerated by: teeup configure teeup-runtime
   teeup_path=<%q-escaped $TEEUP_PATH at generation time>
   exec "${TEEUP_PATH:-$teeup_path}/bin/teeup" lazy-run <capability> <command> "$@"
   ```
   Line 2 is exactly `TEEUP_SHIM_MARKER`; `shims_generate` deletes only files carrying it. There is one shim per token in `provides=` of every `tier=lazy` capability that is not in `TEEUP_SKIP`, and `teeup configure teeup-runtime` regenerates the whole directory. The shape follows spec section 6 with one addition: the checkout path baked in as a fallback for a caller whose environment lacks `TEEUP_PATH`.
2. **`teeup lazy-run <capability> <command> [args...]`.** The package manager's bin directories are added to `PATH`, then a real `<command>` anywhere on `PATH` other than the shims directory is exec'd at once. Otherwise: `TEEUP_SKIP` refuses (exit 127); no terminal on stdin and stderr prints `<command> is not installed. It is provided by capability <cap>; run: teeup install <cap>` (exit 127); on a terminal, `ui_confirm "<command> is provided by capability <cap>. Install now?"` (default yes), then the `teeup install <cap>` path (requires first, install then configure, done marker), then exec of the real binary with the original arguments. A declined prompt exits 127; an install that still leaves no binary exits 127 with `<cap> is installed but <command> is still not on PATH`. `TEEUP_TEST_TTY=yes|no` overrides the terminal check in tests.
3. **`have` never counts a shim.** `lib/core.sh`'s `have` returns 1 when `command -v` resolves into `$TEEUP_STATE_DIR/shims/`, so `pkg_install <pkg> <command>` installs the package a shim stands in for. `TEEUP_TEST_MISSING` accepts absolute paths as well as names.
4. **`apps=` is `;`-separated.** `cap_apps <capability>` prints one name per line; `teeup launch` opens the first with `open -a`. `launch_resolve` accepts a capability name only on an exact, case-sensitive match against the directory names `cap_list` lists (never `[[ -f capabilities/$name/capability ]]`, which macOS's default case-insensitive disks make true for any case variant); any app name matches case-insensitively, with an optional `.app` suffix.
5. **`teeup launch <app|capability>`.** Installed (a bundle under `${TEEUP_APPS_DIR:-/Applications}` or `~/Applications`) means `open -a` only; missing means the `teeup install <cap>` path first, then `open -a`; a bundle still missing after the install (MacPorts, where casks are skipped with a note) is a clear error, not an `open` failure.
6. **`lib/mise.sh`.** `mise_global_state <tool>` prints `installed`, `requested` or `absent`; `mise_ensure_global <tool> [version]` installs without rewriting a pinned request; `mise_wrapper_write <command> <tool> [runtime...]` writes `~/.local/bin/<command>` with `TEEUP_MISE_WRAPPER_MARKER` on line 2 and never replaces a file that lacks it; `dev_env_install <lang>` and `dev_env_installed`. Every mise call is `mise -C / ...` except the `mise x` line inside a wrapper.
7. **`teeup install dev-env <python|node|java|ruby|rust|go>`** marks `done/dev-env-<lang>`; `teeup status` lists the dev-envs and the shims in place; `teeup list` shows how each lazy capability is reached (`[on first: <provides>]`, `[launch: <app>]`, both joined by `; `, or `[teeup install <name>]`).

---

## Decisions made here

1. **Shims are generated from metadata, never from a list.** `shims_generate` walks `cap_list` and keys on `tier=lazy`; adding a capability directory is the registration. That is how 3a's `nvim` and `code` shims appear without this plan naming them, and why the round-trip test uses the shipped `colima` capability while the library tests use fixtures.
2. **The zsh layer already appends the shims; Task 3 hardens it.** Phase 2a's `capabilities/zsh/default/env` ends with `path_append "$TEEUP_STATE_DIR/shims"` after every package-manager prepend and after mise's own shims, and `tests/capabilities/zsh.sh` proves it is the last entry from a clean `PATH` (`test_default_env_appends_the_shims_last`). `path_append` leaves an entry where an inherited `PATH` already had it, so Task 3 removes the entry before appending it (the layer is sourced by both `~/.zshenv` and `~/.zprofile`) and tests the result under a MacPorts machine file with the shims inherited at the front. The same task keeps the layer's `EDITOR` probe from taking a `nvim` shim for Neovim: once 3a's `neovim` capability provides `nvim`, `command -v nvim` answers with the shim on every machine without Neovim.
3. **`have` learns about shims rather than `pkg_install`.** A shim is a real executable on `PATH`, so any "is it installed" probe would be fooled by it. Fixing `have` fixes every caller at once; `lazy_real_command` walks `PATH` itself for the same reason.
4. **`lazy-run` adds the package manager's bin directories before it looks.** A shim fires whenever the calling environment's `PATH` lacks the command, which is also the case for a tool that is installed under `/opt/homebrew/bin` and called from a stripped environment. With the prefix added, such a call runs the tool instead of offering to install it again. A capability marked installed whose command has really gone gets the install question again: every install is idempotent and puts it back.
5. **The wrapper's `mise x` runs unpinned.** `-C /` changes directory before running the command (verified: `mise -C / x uv -- pwd` prints `/`), which would run `claude` in `/`. `where` and `use -g` keep `-C /`; `x` must not.
6. **Wrappers never replace a command teeup did not write.** Claude Code's native installer manages `~/.local/bin/claude` as a symlink into `~/.local/share/claude/versions/`, the same path the `ai` wrapper wants. `mise_wrapper_write` writes only when the file is absent or carries `TEEUP_MISE_WRAPPER_MARKER`, and warns otherwise.
7. **gemini's wrapper brings Node, and names the canonical tool.** mise's registry file for Gemini CLI is `registry/gemini-cli.toml` (`aliases = ["gemini"]`, backend `npm:@google/gemini-cli`), so the wrapper for the `gemini` command installs the tool `gemini-cli` rather than leaning on the alias. mise's npm backend installs the package with its embedded package manager "without needing node", and its documentation adds that it "does not add or install `node` automatically" while "an installed package may still require `node` at runtime". Gemini CLI is a Node program, so its wrapper installs `node` first and loads both into `mise x`. The other four registry entries are `aqua:` release binaries and need nothing.
8. **Wrappers export `MISE_MINIMUM_RELEASE_AGE=0`, and check before they install.** Omarchy's current `omarchy-mise-install` (branch `quattro`) exports the setting for the whole wrapper so the version `mise x` resolves agrees with the one just installed; this plan does the same. Unlike Omarchy's wrapper, which runs `mise use -g` on every call, teeup's runs it only when `mise -C / where <tool>` fails, so a version the user pinned globally is left alone once installed.
9. **Rust goes through mise's rust backend.** Spec section 6 says "Rust uses rustup"; mise's rust backend is rustup: "It installs rustup if it is not already installed, then installs the requested toolchain" into `~/.rustup` and `~/.cargo`. One `mise use -g rust@latest` behaves the same on a Homebrew and a MacPorts machine, and `mise upgrade` covers it with the other runtimes.
10. **`dev-env` never rewrites a pinned runtime.** `mise_ensure_global` is the requested/installed logic phase 2a wrote for pre-commit, moved into a library and reused, so `teeup install dev-env node` on a machine with `node = "22"` pinned globally only reports it.
11. **`javav` is not ported again.** Phase 2a put it in `capabilities/zsh/default/functions` (Corretto by default, `javav 21`). `dev-env java` installs `java@latest` the way Omarchy's `omarchy-install-dev-env java` does and points at `javav` for per-shell switching.
12. **Compose is linked on Homebrew and found on its own on MacPorts.** Homebrew's `docker-compose` formula is the Compose plugin, symlinked under `$(brew --prefix)/lib/docker/cli-plugins`, a directory the docker CLI does not search (its caveat asks for a `cliPluginsExtraDirs` entry in `~/.docker/config.json`). docker searches `cliPluginsExtraDirs`, then `$DOCKER_CONFIG/cli-plugins` (default `~/.docker/cli-plugins`), then fixed system directories, so `configure` links the plugin into the user directory and needs no `config.json` edit (3a owns JSON editing). On MacPorts the `docker-compose` port is the retired Python 1.29.2, so the capability installs the `docker-compose-plugin` port instead: it puts the plugin in `/opt/local/libexec/docker/cli-plugins`, and MacPorts' `docker` port rewrites the CLI's `/usr/lib` system plugin paths to `/opt/local/lib`, which makes `/usr/libexec/docker/cli-plugins` read `/opt/local/libexec/docker/cli-plugins`. No link is needed there.
13. **`colima configure` starts the VM once.** The first `docker ps` that went through the shim expects a daemon. `colima status` returns an error while stopped, so the start is idempotent and dry-run visible.
14. **Herdr stays.** Verified: the `herdrdev/herdr` v0.9.0 release ships `herdr-macos-aarch64` and `herdr-macos-x86_64`; Homebrew has formula `herdr` 0.9.0 (bottles for `arm64_sonoma`, `arm64_sequoia`, `arm64_tahoe`); MacPorts has port `herdr` 0.8.2; the mise registry lists `herdr` (`aqua:herdrdev/herdr`). `pkg_install herdr herdr` covers both backends, so the capability is one small task.
15. **Ollama is the `ollama-app` cask, with the formula as fallback.** Homebrew's cask token is `ollama-app` (there is no cask named `ollama`); it installs `Ollama.app` and links the bundled CLI to `$HOMEBREW_PREFIX/bin/ollama`, so one cask serves `teeup launch ollama` and the `ollama` shim. The cask declares `depends_on macos: >= 14`; where it fails, `install` falls back to the `ollama` formula. MacPorts gets port `ollama`. No models are pulled.
16. **Cursor provides `cursor`.** The `cursor` cask installs `Cursor.app` and links `Cursor.app/Contents/Resources/app/bin/code` to `$HOMEBREW_PREFIX/bin/cursor`, so the command gets a shim exactly as 3a's `vscode` does for `code`. Spec section 6's shim list is a list of examples of the rule ("commands macOS lacks"), and `cursor` follows the rule.
17. **tmux is included, with a small verified config.** The formula and port are both `tmux` 3.7c; tmux reads `~/.config/tmux/tmux.conf` since 3.1. tmux loads every configuration file on its search path that exists, in order (`/etc/tmux.conf`, `~/.tmux.conf`, `$XDG_CONFIG_HOME/tmux/tmux.conf`, `~/.config/tmux/tmux.conf`), not just the first, so a copy dropped next to an existing `~/.tmux.conf` would load after it and override it; `configure` installs nothing when `~/.tmux.conf` exists. The config ports the dotfiles' C-a prefix, drops its theme-pack line (a themed template is phase 4 work) and leaves `default-terminal` to tmux's build-time default, which picks `tmux-256color` when the build's ncurses has it.
18. **CONTRIBUTING items are appended, never numbered against a fixed baseline.** Plan 3a appends two items (JSON settings through `lib/files.sh`, and the editor hook guard); Task 11 appends four after whatever the last numbered item is when it runs.

---

## File structure

| Path | Responsibility |
|---|---|
| `lib/lazy.sh` | `shims_dir`, `TEEUP_SHIM_MARKER`, `lazy_provider`, `lazy_real_command`, `lazy_is_tty`, `shim_write`, `shims_generate`, `cap_apps`, `app_installed`, `launch_resolve`. |
| `lib/mise.sh` | `mise_global_state`, `mise_ensure_global`, `TEEUP_MISE_WRAPPER_MARKER`, `mise_wrapper_write`, `TEEUP_DEV_ENVS`, `dev_env_install`, `dev_env_installed`. |
| `lib/core.sh` | `have` ignores shims and honours path entries in `TEEUP_TEST_MISSING`. |
| `lib/capability.sh` | `cap_check` validates `provides` tokens, rejects duplicate providers and `apps` paths. |
| `lib/all.sh` | sources `lazy` and `mise` after `font`. |
| `capabilities/mise/configure` | uses `mise_ensure_global pre-commit`. |
| `capabilities/teeup-runtime/configure` | calls `shims_generate`. |
| `capabilities/zsh/default/env` | moves the shims directory last on every pass; the `EDITOR` probe ignores a shim. |
| `bin/teeup` | `lazy-run`, `launch`, `install dev-env`, the lazy column in `list`, shims and dev-envs in `status`, usage lines. |
| `capabilities/colima/` | Colima, the Docker CLI, the Compose plugin link, the first start; `provides="docker colima"`. |
| `capabilities/ai/` | wrappers for `claude codex gemini copilot opencode`. |
| `capabilities/herdr/`, `capabilities/tmux/` (+ `config/tmux/tmux.conf`), `capabilities/ollama/`, `capabilities/cursor/` | one small lazy capability each. |
| `tests/helper.sh` | `hide_host_commands`. |
| `tests/lib/{lazy,mise}.sh`, `tests/capabilities/{colima,ai,herdr,tmux,ollama,cursor}.sh` | one new suite per library and capability. |
| `tests/lib/{core,capability}.sh`, `tests/cli.sh`, `tests/capabilities/{teeup-runtime,zsh}.sh` | extended. |
| `README.md`, `CONTRIBUTING.md` | the lazy-capabilities section and four contributor items. |

**Reading this plan mechanically.** Every fenced block whose info string carries `file=<path>` is the complete content of that file after the step. Every edit to an existing file is a pair of blocks, `edit-old=<path>` (text that exists on `main` or was produced by an earlier step of this plan, quoted exactly and occurring exactly once in the file) followed by `edit-new=<path>` (what replaces it). Blocks without either marker are commands or illustrations and change nothing. Blocks that contain triple backticks are fenced with four.

---

### Task 1: `lib/lazy.sh`, shim-aware `have`, and the metadata lint

**Files:**
- Create: `lib/lazy.sh`, `tests/lib/lazy.sh`
- Modify: `lib/all.sh`, `lib/core.sh` (`have`), `lib/capability.sh` (`cap_check`), `tests/helper.sh`, `tests/lib/core.sh`, `tests/lib/capability.sh`

**Interfaces:**
- Consumes: `log`, `ok`, `warn`, `err`, `run_cmd`, `have`, `TEEUP_STATE_DIR`, `TEEUP_PATH` (`lib/core.sh`); `write_managed_file` (`lib/files.sh`); `cap_list`, `cap_meta_get`, `cap_skipped` (`lib/capability.sh`). `launch_resolve` matches a capability name against `cap_list`'s output directly rather than through `cap_exists`, so the match stays case-sensitive on a case-insensitive disk.
- Produces (all in `lib/lazy.sh`):
  - `shims_dir` prints `$TEEUP_STATE_DIR/shims`.
  - `TEEUP_SHIM_MARKER`, the exact second line of every shim.
  - `lazy_provider <command>` prints the lazy capability providing it, exit 1 when none.
  - `lazy_real_command <command>` prints the first executable on `PATH` outside the shims directory, exit 1 when none; honours `TEEUP_TEST_MISSING` by name and by absolute path.
  - `lazy_is_tty` exit 0 when stdin and stderr are terminals, overridable with `TEEUP_TEST_TTY=yes|no`.
  - `shim_write <capability> <command>` writes one executable shim through `write_managed_file` (idempotent, `DRY_RUN` safe).
  - `shims_generate` writes every shim for every `tier=lazy` capability not in `TEEUP_SKIP` and removes stale ones; always returns 0.
  - `cap_apps <capability>` prints the `;`-separated `apps=` entries one per line, trimmed.
  - `app_installed <app>` exit 0 when `<app>.app` is under `${TEEUP_APPS_DIR:-/Applications}` or `~/Applications`.
  - `launch_resolve <app|capability>` prints the capability to launch, exit 1 with an `err` line when nothing matches. A capability name matches only exactly (case-sensitively, against `cap_list`); it falls through to the case-insensitive app-name match otherwise, so a case variant of a real capability name (`Cursor` against `cursor`) resolves through `apps=` instead, and never carries the wrong case downstream into `cap_skipped`.
  - `have` (`lib/core.sh`) returns 1 for a command that resolves into the shims directory, and for an absolute path listed in `TEEUP_TEST_MISSING`.
  - `hide_host_commands <name...>` (`tests/helper.sh`) adds every copy of each name found through `PATH` to `TEEUP_TEST_MISSING` by absolute path.
  - `cap_check` (`lib/capability.sh`) additionally reports: `<cap>: provides token '<t>' is not a plain command name`, `<cap>: apps must be application names, not paths`, `<cap>: provides <cmd>, which <other> already provides`.
- Tasks 3 to 10 consume all of these.

**Real-Mac risk:** `lazy_is_tty` tests `[[ -t 0 && -t 2 ]]`; under gum, `ui_confirm` draws on `/dev/tty` itself. A shim invoked from an app that gives it a pty but no readable stdin (some IDE terminals) would be judged interactive and then read an empty answer, which `ui_confirm` treats as the default yes. Only hardware shows whether any launcher the user actually uses behaves that way.

- [ ] **Step 1: Write the failing test `tests/lib/lazy.sh`**

```bash file=tests/lib/lazy.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# A fixture tree: two lazy capabilities with commands, one lazy app, one core
# capability that must never get a shim.
make_cap() {
  local name="$1" tier="$2" provides="${3:-}" apps="${4:-}"
  local dir="$TEEUP_CAPS_DIR/$name"
  mkdir -p "$dir"
  cat > "$dir/capability" <<EOF2
summary="Fixture $name"
group=system
tier=$tier
requires=""
provides="$provides"
apps="$apps"
interactive=false
EOF2
  printf '#!/usr/bin/env bash\necho "install:%s"\n' "$name" > "$dir/install"
  printf '#!/usr/bin/env bash\necho "configure:%s"\n' "$name" > "$dir/configure"
  chmod +x "$dir/install" "$dir/configure"
}

setup() {
  setup_test_env
  mock_command hostname 0 "testmac"
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR"
  source "$TEEUP_PATH/lib/all.sh"
  export DRY_RUN=false
  make_cap alpha core "" ""
  make_cap boxes lazy "boxctl boxd" ""
  make_cap sketch lazy "sketch" "Sketch Pad"
  make_cap paint lazy "" "Paint Shop; Paint Viewer"
  make_cap cursor lazy "" "Cursor"
  printf 'alpha\n' > "$TEEUP_CAPS_DIR/core.list"
  : > "$TEEUP_CAPS_DIR/daily.list"
  SHIMS="$TEST_HOME/.local/state/teeup/shims"
}

test_provider_finds_the_lazy_capability() {
  setup
  assert_equals "boxes" "$(lazy_provider boxd)" || return 1
  assert_equals "sketch" "$(lazy_provider sketch)" || return 1
  lazy_provider nothing && { echo "unknown command must not resolve"; return 1; }
  cleanup_test_env
}

test_generate_writes_one_executable_shim_per_command() {
  setup
  shims_generate >/dev/null
  local c
  for c in boxctl boxd sketch; do
    assert_file_exists "$SHIMS/$c" || return 1
    [[ -x "$SHIMS/$c" ]] || { echo "$c must be executable"; return 1; }
  done
  [[ ! -e "$SHIMS/alpha" ]] || { echo "core capabilities get no shim"; return 1; }
  assert_equals "#!/bin/bash" "$(sed -n 1p "$SHIMS/boxd")" || return 1
  assert_equals "$TEEUP_SHIM_MARKER" "$(sed -n 2p "$SHIMS/boxd")" || return 1
  assert_contains "$(cat "$SHIMS/boxd")" 'lazy-run boxes boxd "$@"' || return 1
  cleanup_test_env
}

test_shim_execs_teeup_with_the_original_arguments() {
  setup
  shims_generate >/dev/null
  # A fake bin/teeup under a throwaway checkout, so the shim's baked path and
  # its argument order can be checked without going through the real CLI.
  local fake="$TEST_HOME/checkout"
  mkdir -p "$fake/bin"
  printf '#!/usr/bin/env bash\nprintf "[%%s]" "$@"; echo\n' > "$fake/bin/teeup"
  chmod +x "$fake/bin/teeup"
  local out
  out="$(TEEUP_PATH="$fake" "$SHIMS/boxd" --flag "two words")"
  assert_equals "[lazy-run][boxes][boxd][--flag][two words]" "$out" || return 1
  cleanup_test_env
}

test_shim_falls_back_to_the_baked_checkout_path() {
  setup
  # A checkout path with a space, a quote and a dollar sign: the shim must
  # reach the right bin/teeup even when TEEUP_PATH is absent from the
  # environment (an IDE's process runner, a cron job).
  local weird="$TEST_HOME/we ird\$\"dir"
  mkdir -p "$weird/bin"
  printf '#!/usr/bin/env bash\necho "reached:$1"\n' > "$weird/bin/teeup"
  chmod +x "$weird/bin/teeup"
  TEEUP_PATH="$weird" shim_write boxes boxd >/dev/null
  local out
  out="$(env -u TEEUP_PATH "$SHIMS/boxd")"
  assert_equals "reached:lazy-run" "$out" || return 1
  cleanup_test_env
}

test_generate_is_idempotent_and_removes_stale_shims() {
  setup
  shims_generate >/dev/null
  # A shim whose capability no longer provides it, and a file that is not a
  # teeup shim at all.
  cp "$SHIMS/boxd" "$SHIMS/oldcmd"
  printf '#!/bin/bash\necho mine\n' > "$SHIMS/mine"
  local out
  out="$(shims_generate 2>&1)"
  assert_contains "$out" "Already current: $SHIMS/boxd" || return 1
  assert_contains "$out" "Removed stale shim: oldcmd" || return 1
  [[ ! -e "$SHIMS/oldcmd" ]] || { echo "stale shim must be removed"; return 1; }
  assert_contains "$out" "Not a teeup shim, leaving it alone: $SHIMS/mine" || return 1
  assert_file_exists "$SHIMS/mine" || return 1
  cleanup_test_env
}

test_generate_skips_a_capability_in_teeup_skip() {
  setup
  export TEEUP_SKIP="boxes"
  local out
  out="$(shims_generate 2>&1)"
  assert_contains "$out" "No shims for boxes (TEEUP_SKIP)" || return 1
  [[ ! -e "$SHIMS/boxd" ]] || { echo "skipped capability must get no shim"; return 1; }
  assert_file_exists "$SHIMS/sketch" || return 1
  unset TEEUP_SKIP
  cleanup_test_env
}

test_generate_dry_run_writes_nothing() {
  setup
  local out
  out="$(DRY_RUN=true shims_generate)"
  assert_contains "$out" "Would write $SHIMS/boxd" || return 1
  [[ ! -e "$SHIMS" ]] || { echo "dry run must not create the shims dir"; return 1; }
  cleanup_test_env
}

test_real_command_ignores_the_shims_dir() {
  setup
  shims_generate >/dev/null
  export PATH="$MOCK_BIN:/usr/bin:/bin:$SHIMS"
  lazy_real_command boxd && { echo "a shim alone is not a real command"; return 1; }
  mock_command boxd 0 ""
  assert_equals "$MOCK_BIN/boxd" "$(lazy_real_command boxd)" || return 1
  # An empty PATH entry (a leading or doubled colon) means the current
  # directory; it is skipped rather than searched.
  export PATH=":$MOCK_BIN::/usr/bin:$SHIMS/"
  assert_equals "$MOCK_BIN/boxd" "$(lazy_real_command boxd)" || return 1
  export TEEUP_TEST_MISSING="boxd"
  lazy_real_command boxd && { echo "TEEUP_TEST_MISSING must hide it"; return 1; }
  # By absolute path, only that binary is hidden.
  local other
  other="$(mktemp -d)"
  cp "$MOCK_BIN/boxd" "$other/boxd"
  export TEEUP_TEST_MISSING="$MOCK_BIN/boxd"
  export PATH="$MOCK_BIN:$other:/usr/bin:$SHIMS"
  assert_equals "$other/boxd" "$(lazy_real_command boxd)" || return 1
  unset TEEUP_TEST_MISSING
  rm -rf "$other"
  cleanup_test_env
}

test_have_ignores_a_shim() {
  setup
  shims_generate >/dev/null
  # The shim has to exist for this to prove anything: without it `have` is
  # false for want of any boxd at all.
  assert_file_exists "$SHIMS/boxd" || return 1
  export PATH="$MOCK_BIN:/usr/bin:/bin:$SHIMS"
  have boxd && { echo "have must not count a shim as installed"; return 1; }
  mock_command boxd 0 ""
  have boxd || { echo "a real boxd ahead of the shim counts"; return 1; }
  cleanup_test_env
}

test_is_tty_honours_the_test_hook() {
  setup
  TEEUP_TEST_TTY=yes lazy_is_tty || { echo "yes must be a tty"; return 1; }
  TEEUP_TEST_TTY=no lazy_is_tty && { echo "no must not be a tty"; return 1; }
  # Under run_test stdin is not a terminal, so the real check says no.
  lazy_is_tty </dev/null && { echo "/dev/null is not a tty"; return 1; }
  cleanup_test_env
}

test_cap_apps_splits_on_semicolons() {
  setup
  assert_equals "Sketch Pad" "$(cap_apps sketch)" || return 1
  assert_equals "Paint Shop|Paint Viewer" "$(cap_apps paint | tr '\n' '|' | sed 's/|$//')" || return 1
  assert_equals "" "$(cap_apps boxes)" || return 1
  cleanup_test_env
}

test_launch_resolve_by_capability_and_by_app_name() {
  setup
  assert_equals "sketch" "$(launch_resolve sketch)" || return 1
  assert_equals "sketch" "$(launch_resolve "sketch pad")" || return 1
  assert_equals "sketch" "$(launch_resolve "Sketch Pad.app")" || return 1
  assert_equals "paint" "$(launch_resolve "paint viewer")" || return 1
  local rc=0 out
  out="$(launch_resolve boxes 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "boxes has no apps= entry" || return 1
  rc=0
  out="$(launch_resolve "Nothing Here" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "No capability provides an app named 'Nothing Here'" || return 1
  cleanup_test_env
}

test_launch_resolve_matches_capability_names_case_sensitively() {
  setup
  # cap_exists uses [[ -f capabilities/$name/capability ]], which macOS's
  # default case-insensitive disks satisfy for any case variant of a real
  # directory name ("Cursor" opens the same file as "cursor"). Simulate that
  # here by overriding cap_exists the way it would answer on such a disk, in
  # a subshell so the override does not leak into later tests. launch_resolve
  # must not consult cap_exists for this decision at all: a capability name
  # only matches on an exact line in cap_list, so "Cursor" still falls
  # through to the case-insensitive apps= match and resolves to "cursor"
  # with the real, lowercase name attached.
  local resolved
  resolved="$(cap_exists() { [[ "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" == "cursor" ]]; }; launch_resolve Cursor)"
  assert_equals "cursor" "$resolved" || return 1
  # If launch_resolve had returned "Cursor" (the original casing) instead,
  # this literal comparison in cap_skipped would miss a lowercase TEEUP_SKIP
  # entry and the skip would be silently bypassed.
  export TEEUP_SKIP="cursor"
  cap_skipped "$resolved" || { echo "TEEUP_SKIP=cursor must catch the name launch_resolve returns for a case-variant argument"; return 1; }
  unset TEEUP_SKIP
  cleanup_test_env
}

test_app_installed_checks_both_application_folders() {
  setup
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  app_installed "Sketch Pad" && { echo "nothing installed yet"; return 1; }
  mkdir -p "$TEEUP_APPS_DIR/Sketch Pad.app"
  app_installed "Sketch Pad" || { echo "found under TEEUP_APPS_DIR"; return 1; }
  mkdir -p "$HOME/Applications/Paint Shop.app"
  app_installed "Paint Shop" || { echo "found under ~/Applications"; return 1; }
  cleanup_test_env
}

echo "lib/lazy.sh"
run_test "provider finds the lazy capability" test_provider_finds_the_lazy_capability
run_test "generate writes one executable shim per command" test_generate_writes_one_executable_shim_per_command
run_test "shim execs teeup with the original arguments" test_shim_execs_teeup_with_the_original_arguments
run_test "shim falls back to the baked checkout path" test_shim_falls_back_to_the_baked_checkout_path
run_test "generate is idempotent and removes stale shims" test_generate_is_idempotent_and_removes_stale_shims
run_test "generate skips a capability in TEEUP_SKIP" test_generate_skips_a_capability_in_teeup_skip
run_test "generate dry run writes nothing" test_generate_dry_run_writes_nothing
run_test "real command ignores the shims dir" test_real_command_ignores_the_shims_dir
run_test "have ignores a shim" test_have_ignores_a_shim
run_test "is_tty honours the test hook" test_is_tty_honours_the_test_hook
run_test "cap_apps splits on semicolons" test_cap_apps_splits_on_semicolons
run_test "launch_resolve by capability and by app name" test_launch_resolve_by_capability_and_by_app_name
run_test "launch_resolve matches capability names case-sensitively" test_launch_resolve_matches_capability_names_case_sensitively
run_test "app_installed checks both application folders" test_app_installed_checks_both_application_folders
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/lib/lazy.sh`
Expected: every test fails with `command not found` for the function it calls (`lazy_provider`, `shims_generate`, `lazy_is_tty`, ...); the suite ends with `Summary: 0/14 passed`.

- [ ] **Step 3: Write `lib/lazy.sh`**

```bash file=lib/lazy.sh
#!/usr/bin/env bash
# lazy.sh - the lazy-install seam (spec section 6): shims for commands that
# nothing on the machine provides yet, and the app lookup behind `teeup launch`.
# A shim is a four-line script in $TEEUP_STATE_DIR/shims that hands the call
# to `teeup lazy-run <capability> <command>`. The zsh layer appends that
# directory last on PATH, so a shim fires only when no real binary exists.
# Requires core.sh, files.sh, state.sh and capability.sh.

shims_dir() { printf '%s/shims\n' "$TEEUP_STATE_DIR"; }

# The second line of every shim teeup writes. shims_generate deletes only
# files that carry it, so a stray file dropped into the directory by hand is
# reported rather than removed.
TEEUP_SHIM_MARKER="# teeup lazy shim; regenerated by: teeup configure teeup-runtime"

# lazy_provider <command> -> the tier=lazy capability whose provides= names
# <command>; exit 1 (printing nothing) when there is none. cap_check refuses
# two lazy capabilities providing the same command, so the first hit is the
# only hit.
lazy_provider() {
  local command="$1" name p
  for name in $(cap_list); do
    [[ "$(cap_meta_get "$name" tier)" == "lazy" ]] || continue
    for p in $(cap_meta_get "$name" provides); do
      if [[ "$p" == "$command" ]]; then
        printf '%s\n' "$name"
        return 0
      fi
    done
  done
  return 1
}

# lazy_real_command <command> -> the first executable named <command> on
# PATH outside the shims directory; exit 1 when there is none. PATH is walked
# by hand rather than through `command -v` because the shim itself is on PATH
# and would answer. Honours TEEUP_TEST_MISSING like `have` does, by name and
# by absolute path.
lazy_real_command() {
  local command="$1" shims dir rest candidate
  case " ${TEEUP_TEST_MISSING:-} " in
    *" $command "*) return 1 ;;
  esac
  shims="$(shims_dir)"
  rest="$PATH:"
  while [[ -n "$rest" ]]; do
    dir="${rest%%:*}"
    rest="${rest#*:}"
    [[ -n "$dir" ]] || continue
    [[ "${dir%/}" == "${shims%/}" ]] && continue
    candidate="${dir%/}/$command"
    case " ${TEEUP_TEST_MISSING:-} " in
      *" $candidate "*) continue ;;
    esac
    if [[ -f "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# lazy_is_tty -> can lazy-run ask a question? Both stdin and stderr must be a
# terminal: a shim run from a script or an editor has neither, and blocking
# on a prompt nobody sees is the failure mode spec section 6 rules out.
# TEEUP_TEST_TTY=yes|no is a test-only hook (the harness has no terminal),
# the same shape as TEEUP_TEST_MISSING in core.sh.
lazy_is_tty() {
  case "${TEEUP_TEST_TTY:-}" in
    yes) return 0 ;;
    no) return 1 ;;
  esac
  [[ -t 0 && -t 2 ]]
}

# shim_write <capability> <command>
# Writes one shim, executable, only when its content changed. TEEUP_PATH is
# baked in as a fallback: a shim reached through PATH normally has TEEUP_PATH
# from ~/.config/teeup/env, but a stripped environment (an IDE's process
# runner, a cron job) must still find the checkout. The path is %q-escaped
# and lands on its own assignment line, so a space, quote or dollar in the
# checkout path cannot break the exec line, which only ever expands
# variables.
shim_write() {
  local cap="$1" command="$2" file teeup_path_q
  file="$(shims_dir)/$command"
  teeup_path_q="$(printf '%q' "$TEEUP_PATH")"
  write_managed_file "$file" "shim for $command, capability $cap" <<SHIM
#!/bin/bash
$TEEUP_SHIM_MARKER
teeup_path=$teeup_path_q
exec "\${TEEUP_PATH:-\$teeup_path}/bin/teeup" lazy-run $cap $command "\$@"
SHIM
  [[ "$DRY_RUN" == "true" ]] || chmod 755 "$file"
}

# shims_generate
# One shim per command in provides= of every tier=lazy capability, stale
# shims removed. Idempotent; under DRY_RUN it prints what it would write and
# remove. A capability skipped by TEEUP_SKIP gets no shims: on that machine
# the command really is "not found", which is the honest answer. Nothing here
# is hard-coded: a lazy capability added by any later plan gets its shims on
# the next `teeup configure teeup-runtime`.
shims_generate() {
  local dir wanted=" " name p f base
  dir="$(shims_dir)"
  [[ -d "$dir" ]] || run_cmd mkdir -p "$dir"
  for name in $(cap_list); do
    [[ "$(cap_meta_get "$name" tier)" == "lazy" ]] || continue
    if cap_skipped "$name"; then
      log "No shims for $name (TEEUP_SKIP)"
      continue
    fi
    for p in $(cap_meta_get "$name" provides); do
      shim_write "$name" "$p"
      wanted="$wanted$p "
    done
  done
  for f in "$dir"/*; do
    [[ -e "$f" ]] || continue
    base="${f##*/}"
    case "$wanted" in *" $base "*) continue ;; esac
    if [[ -f "$f" ]] && sed -n 2p "$f" | grep -qxF "$TEEUP_SHIM_MARKER"; then
      run_cmd rm -f "$f"
      [[ "$DRY_RUN" == "true" ]] || ok "Removed stale shim: $base"
    else
      warn "Not a teeup shim, leaving it alone: $f"
    fi
  done
  return 0
}

# --- teeup launch -------------------------------------------------------------

# cap_apps <capability> -> one application name per line from apps=. The
# separator is ";" rather than a space because app names contain spaces
# ("Visual Studio Code", "Google Chrome"); a single name needs no separator.
cap_apps() {
  local rest app
  rest="$(cap_meta_get "$1" apps);"
  while [[ -n "$rest" ]]; do
    app="${rest%%;*}"
    rest="${rest#*;}"
    app="${app#"${app%%[![:space:]]*}"}"
    app="${app%"${app##*[![:space:]]}"}"
    [[ -n "$app" ]] && printf '%s\n' "$app"
  done
  return 0
}

# app_installed <app name> -> is <app>.app present where casks put it?
# TEEUP_APPS_DIR is the test hook aerospace already uses for /Applications;
# ~/Applications is where a cask lands when HOMEBREW_CASK_OPTS points it there.
app_installed() {
  [[ -d "${TEEUP_APPS_DIR:-/Applications}/$1.app" || -d "$HOME/Applications/$1.app" ]]
}

# launch_resolve <app|capability> -> the capability to launch; exit 1 with a
# message when nothing matches. A capability name wins, but only on an exact,
# case-sensitive match against the directory names cap_list lists: macOS's
# default case-insensitive disks make `[[ -f capabilities/$name/capability ]]`
# true for any case variant of a real directory name (`Cursor` resolves the
# same file as `cursor`), which would let a mis-cased name through with its
# original casing still attached, letting `TEEUP_SKIP` miss it downstream.
# Comparing against the listed names keeps the match case-sensitive on every
# disk. Otherwise every capability's app names are compared
# case-insensitively, with an optional ".app" suffix on the argument ignored.
launch_resolve() {
  local wanted="${1%.app}" key name app
  if cap_list | grep -qxF -- "$wanted"; then
    if [[ -z "$(cap_meta_get "$wanted" apps)" ]]; then
      err "$wanted has no apps= entry, so there is nothing to launch."
      return 1
    fi
    printf '%s\n' "$wanted"
    return 0
  fi
  key="$(printf '%s' "$wanted" | tr '[:upper:]' '[:lower:]')"
  for name in $(cap_list); do
    while IFS= read -r app; do
      if [[ "$(printf '%s' "$app" | tr '[:upper:]' '[:lower:]')" == "$key" ]]; then
        printf '%s\n' "$name"
        return 0
      fi
    done < <(cap_apps "$name")
  done
  err "No capability provides an app named '$1' (try: teeup list)."
  return 1
}
```

- [ ] **Step 4: Source it from `lib/all.sh`**

```bash edit-old=lib/all.sh
for _teeup_lib in files state answers pkg ui capability macos theme font; do
```

```bash edit-new=lib/all.sh
for _teeup_lib in files state answers pkg ui capability macos theme font lazy; do
```

`lazy` goes after `capability` (it calls `cap_list`, `cap_meta_get`, `cap_skipped`) and after `files` (`write_managed_file`).

- [ ] **Step 5: Teach `have` about shims in `lib/core.sh`**

Replace the whole `have` function and the comment above it:

```bash edit-old=lib/core.sh
# have <command>
# TEEUP_TEST_MISSING is a test-only hook: a space-separated list of commands
# the harness pretends are absent, so a test can simulate a fresh Mac on a
# host that already has them.
have() {
  case " ${TEEUP_TEST_MISSING:-} " in
    *" $1 "*) return 1 ;;
  esac
  command -v "$1" >/dev/null 2>&1
}
```

```bash edit-new=lib/core.sh
# have <command>
# TEEUP_TEST_MISSING is a test-only hook: a space-separated list of commands
# the harness pretends are absent, so a test can simulate a fresh Mac on a
# host that already has them. An entry is a bare name (hidden wherever it is
# found) or an absolute path (only that binary is hidden, so a copy the test
# installs somewhere else is still found; see hide_host_commands in
# tests/helper.sh).
have() {
  local found
  case " ${TEEUP_TEST_MISSING:-} " in
    *" $1 "*) return 1 ;;
  esac
  found="$(command -v "$1" 2>/dev/null)" || return 1
  case " ${TEEUP_TEST_MISSING:-} " in
    *" $found "*) return 1 ;;
  esac
  # A teeup lazy shim (lib/lazy.sh) stands in for a command nothing real
  # provides, and the shell puts the shims directory last on PATH, so when
  # `command -v` answers with a shim there is no real binary anywhere ahead of
  # it. Counting that as "installed" would make pkg_install skip the very
  # package the shim exists to install.
  case "$found" in
    "$TEEUP_STATE_DIR/shims/"*) return 1 ;;
  esac
  return 0
}
```

- [ ] **Step 6: Extend `cap_check` in `lib/capability.sh`** (three edits)

The `local` line of `cap_check` gains `seen`:

```bash edit-old=lib/capability.sh
  local problems=0 name dir tier provides p verb tpl base other d
```

```bash edit-new=lib/capability.sh
  local problems=0 name dir tier provides p verb tpl base other d seen
```

The `provides` loop validates each token, and `apps` is checked right after it:

```bash edit-old=lib/capability.sh
    provides="$(cap_meta_get "$name" provides)"
    for p in $provides; do
      case " $TEEUP_SHIM_FORBIDDEN " in
        *" $p "*) echo "$name: provides must not list $p (macOS ships it, a shim can never fire)"; problems=$((problems + 1)) ;;
      esac
    done
```

```bash edit-new=lib/capability.sh
    provides="$(cap_meta_get "$name" provides)"
    for p in $provides; do
      case " $TEEUP_SHIM_FORBIDDEN " in
        *" $p "*) echo "$name: provides must not list $p (macOS ships it, a shim can never fire)"; problems=$((problems + 1)) ;;
      esac
      # A provides token becomes a file name under the shims directory and a
      # bare word on the shim's exec line, so it has to be a plain command
      # name: letters, digits and _.+- only, starting with a letter or digit.
      if ! [[ "$p" =~ ^[A-Za-z0-9][A-Za-z0-9_.+-]*$ ]]; then
        echo "$name: provides token '$p' is not a plain command name"; problems=$((problems + 1))
      fi
    done
    # apps= is ";"-separated (names contain spaces); an entry becomes
    # "<name>.app" under /Applications and an argument to `open -a`.
    case "$(cap_meta_get "$name" apps)" in
      */*) echo "$name: apps must be application names, not paths"; problems=$((problems + 1)) ;;
    esac
```

The duplicate-provider scan goes between the tier-list loop and the final status line:

```bash edit-old=lib/capability.sh
  for tier in core daily; do
    for name in $(cap_tier_list "$tier"); do
      cap_exists "$name" || { echo "$tier.list: unknown capability $name"; problems=$((problems + 1)); }
    done
  done
  [[ $problems -eq 0 ]]
}
```

```bash edit-new=lib/capability.sh
  for tier in core daily; do
    for name in $(cap_tier_list "$tier"); do
      cap_exists "$name" || { echo "$tier.list: unknown capability $name"; problems=$((problems + 1)); }
    done
  done
  # One shim per command: two lazy capabilities providing the same command
  # would leave whichever sorts first owning the shim, silently.
  seen=" "
  for name in $(cap_list); do
    [[ "$(cap_meta_get "$name" tier)" == "lazy" ]] || continue
    for p in $(cap_meta_get "$name" provides); do
      case "$seen" in
        *" $p="*)
          other="${seen#*" $p="}"
          other="${other%% *}"
          echo "$name: provides $p, which $other already provides"; problems=$((problems + 1))
          ;;
        *) seen="$seen$p=$name " ;;
      esac
    done
  done
  [[ $problems -eq 0 ]]
}
```

- [ ] **Step 7: Add `hide_host_commands` to `tests/helper.sh`**

Insert it just above the `mock_macos_base` comment:

```bash edit-old=tests/helper.sh
# A modern Apple Silicon Mac with CLT present and Homebrew missing.
```

```bash edit-new=tests/helper.sh
# hide_host_commands <name...>
# Pretend the host does not have these commands *as it has them now*: every
# copy reachable through a PATH directory is added to TEEUP_TEST_MISSING by
# its absolute path (all of them, not just the first: on a merged-/usr Linux
# /bin/docker and /usr/bin/docker are the same file under two PATH entries),
# so a copy the test installs later (into MOCK_BIN or a bin directory of its
# own) is still found. Hiding by name (TEEUP_TEST_MISSING="gum jq") is the
# right tool when the test never installs the command. Call after
# setup_test_env, which narrows PATH, and before mocking any of the names.
hide_host_commands() {
  local name rest dir
  for name in "$@"; do
    rest="$PATH:"
    while [[ -n "$rest" ]]; do
      dir="${rest%%:*}"
      rest="${rest#*:}"
      [[ -n "$dir" && -f "$dir/$name" && -x "$dir/$name" ]] || continue
      TEEUP_TEST_MISSING="${TEEUP_TEST_MISSING:+$TEEUP_TEST_MISSING }${dir%/}/$name"
    done
  done
  export TEEUP_TEST_MISSING
}

# A modern Apple Silicon Mac with CLT present and Homebrew missing.
```

- [ ] **Step 8: Extend `tests/lib/core.sh` and `tests/lib/capability.sh`**

In `tests/lib/core.sh`, add one test above the `echo` line and register it:

```bash edit-old=tests/lib/core.sh
echo "lib/core.sh"
```

```bash edit-new=tests/lib/core.sh
test_have_hides_a_binary_by_absolute_path() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  local other
  other="$(mktemp -d)"
  mock_command frob 0 ""
  # Hiding by path: the MOCK_BIN copy is invisible, a copy elsewhere is not.
  export TEEUP_TEST_MISSING="$MOCK_BIN/frob"
  have frob && { echo "the listed path must be hidden"; return 1; }
  cp "$MOCK_BIN/frob" "$other/frob"
  PATH="$other:$PATH" have frob || { echo "a copy at another path is found"; return 1; }
  unset TEEUP_TEST_MISSING
  rm -rf "$other"
  cleanup_test_env
}

echo "lib/core.sh"
```

```bash edit-old=tests/lib/core.sh
run_test "have honours TEEUP_TEST_MISSING hook" test_have_honours_test_missing_hook
```

```bash edit-new=tests/lib/core.sh
run_test "have honours TEEUP_TEST_MISSING hook" test_have_honours_test_missing_hook
run_test "have hides a binary by absolute path" test_have_hides_a_binary_by_absolute_path
```

In `tests/lib/capability.sh`, add two tests above `test_cap_order_fails_on_unknown_requires` and register them before it:

```bash edit-old=tests/lib/capability.sh
test_cap_order_fails_on_unknown_requires() {
```

```bash edit-new=tests/lib/capability.sh
test_check_rejects_a_bad_provides_token_and_a_duplicate() {
  setup
  # A token with a slash would write the shim somewhere else; a leading dash
  # reads as an option on the shim's exec line.
  make_cap lazytwo lazy "" "gam tools/x"
  sed -i.bak 's/^tier=daily/tier=lazy/' "$TEEUP_CAPS_DIR/gamma/capability" && rm "$TEEUP_CAPS_DIR/gamma/capability.bak"
  : > "$TEEUP_CAPS_DIR/daily.list"
  local rc=0 out
  out="$(cap_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "lazytwo: provides token 'tools/x' is not a plain command name" || return 1
  assert_contains "$out" "lazytwo: provides gam, which gamma already provides" || return 1
  cleanup_test_env
}

test_check_rejects_an_apps_path() {
  setup
  printf 'apps="/Applications/Thing.app"\n' >> "$TEEUP_CAPS_DIR/lazyone/capability"
  local rc=0 out
  out="$(cap_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "lazyone: apps must be application names, not paths" || return 1
  cleanup_test_env
}

test_cap_order_fails_on_unknown_requires() {
```

```bash edit-old=tests/lib/capability.sh
run_test "cap_order fails on unknown requires" test_cap_order_fails_on_unknown_requires
```

```bash edit-new=tests/lib/capability.sh
run_test "check rejects a bad provides token and a duplicate" test_check_rejects_a_bad_provides_token_and_a_duplicate
run_test "check rejects an apps path" test_check_rejects_an_apps_path
run_test "cap_order fails on unknown requires" test_cap_order_fails_on_unknown_requires
```

- [ ] **Step 9: Run the three suites**

Run: `bash tests/lib/lazy.sh && bash tests/lib/core.sh && bash tests/lib/capability.sh`
Expected: `Summary: 14/14 passed`, `Summary: 11/11 passed`, `Summary: 17/17 passed`.

- [ ] **Step 10: Full checks and commit**

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning lib/*.sh tests/helper.sh tests/lib/lazy.sh tests/lib/core.sh tests/lib/capability.sh
git diff --check
git add lib/lazy.sh lib/all.sh lib/core.sh lib/capability.sh tests/helper.sh tests/lib/lazy.sh tests/lib/core.sh tests/lib/capability.sh
git commit -m "Add the lazy-install library and shim-aware have"
```

Expected: `commands --check` prints nothing; `tests/run.sh` ends with `All N suites passed.` where N is the suite count printed before this task, plus 1; shellcheck prints nothing.

---

### Task 2: `lib/mise.sh` and the mise capability on top of it

**Files:**
- Create: `lib/mise.sh`, `tests/lib/mise.sh`
- Modify: `lib/all.sh`, `capabilities/mise/configure`
- Test: `tests/lib/mise.sh`, `tests/capabilities/mise.sh` (unchanged, must stay green: its ten tests are the specification of `mise_global_state`)

**Interfaces:**
- Consumes: `log`, `warn`, `err`, `ok`, `run_cmd`, `have`, `user_config_dir` (`lib/core.sh`); `write_managed_file` (`lib/files.sh`); `state_done` (`lib/state.sh`).
- Produces (all in `lib/mise.sh`):
  - `mise_global_state <tool>` prints `installed`, `requested` or `absent`.
  - `mise_ensure_global <tool> [version]`: `installed` logs `Already installed through mise: <tool>`; `requested` logs `<tool> is requested by the global mise config but not installed; installing it.` and runs `mise -C / install <tool>`; `absent` runs `mise -C / use -g <tool>[@<version>]`. Warns `Could not install <tool> through mise.` and returns 1 on failure.
  - `TEEUP_MISE_WRAPPER_MARKER`, the exact second line of every wrapper.
  - `mise_wrapper_write <command> <tool> [runtime...]` writes `~/.local/bin/<command>` (executable; `write_managed_file`, so idempotent and `DRY_RUN` safe). The wrapper exports `MISE_MINIMUM_RELEASE_AGE=0`, runs `mise -C / where <t> || mise -C / use -g --quiet <t>` for each runtime and then the tool, and ends `exec mise x <runtimes> <tool> -- <command> "$@"`. A file at that path without the marker is kept with the warning `Keeping <file>: it was not written by teeup. ...` (return 0); a name that is not a plain command or tool name is refused with an `err` (return 1).
  - `TEEUP_DEV_ENVS="python node java ruby rust go"`; `dev_env_install <lang>` (returns 1 with a usage line for anything else, or `mise is not installed; run: teeup install mise`); `dev_env_installed` prints the marked languages one per line.
- Task 4 consumes `dev_env_install`/`dev_env_installed`; Task 6 consumes `mise_wrapper_write`.

**Real-Mac risk:** the wrapper was run for real on Linux with mise 2026.9.4 (first call of an uninstalled `shfmt` installed it and ran it; a second call only ran it; `mise -C / x uv -- pwd` printed `/`, which is why `x` stays unpinned). What stays unproven is macOS itself: the aqua backend downloading `claude`, `codex`, `copilot` and `opencode` release assets for `darwin-arm64` and `darwin-amd64`, and `gemini` actually starting under the Node that `mise x node gemini` puts on `PATH`. Inside a project whose `mise.toml` pins a version of the same tool that is not installed, `mise x` auto-installs it (`not_found_auto_install`, default `true` in `mise settings ls --all`); that path has not been exercised.

- [ ] **Step 1: Write the failing test `tests/lib/mise.sh`**

```bash file=tests/lib/mise.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# A mise that keeps "requested" (the global config's tool list, in
# mise-tools) and "installed" (what is on disk, in mise-installed) apart, the
# way the real one does. `use -g` records both, stripping any @version; a
# tool listed in mise-local-tools stands for a project config in the cwd,
# which only an unpinned (no `-C /`) call can see.
mock_mise() {
  mock_command_script mise <<'EOF2'
pinned=0
[ "$1" = "-C" ] && { pinned=1; shift 2; }
shadowed() { [ "$pinned" = "0" ] && grep -qx "$1" "$HOME/mise-local-tools" 2>/dev/null; }
case "$*" in
  "ls --global --installed"*)
    tool="${4:-}"
    [ -f "$HOME/mise-tools" ] || exit 0
    while read -r name; do
      [ -z "$tool" ] || [ "$name" = "$tool" ] || continue
      shadowed "$name" && continue
      grep -qx "$name" "$HOME/mise-installed" 2>/dev/null && printf '%s latest ~/.config/mise/config.toml latest\n' "$name"
    done < "$HOME/mise-tools"
    ;;
  "ls --global"*)
    [ -f "$HOME/mise-tools" ] || exit 0
    while read -r name; do
      shadowed "$name" && continue
      if grep -qx "$name" "$HOME/mise-installed" 2>/dev/null; then
        printf '%s latest ~/.config/mise/config.toml latest\n' "$name"
      else
        printf '%s latest (missing) ~/.config/mise/config.toml latest\n' "$name"
      fi
    done < "$HOME/mise-tools"
    ;;
  "where "*)
    grep -qx "$2" "$HOME/mise-installed" 2>/dev/null || exit 1
    ;;
  "use "*)
    shift
    while [ $# -gt 0 ]; do
      case "$1" in -g|--global|--quiet|-q) shift ;; *) break ;; esac
    done
    name="${1%%@*}"
    printf '%s\n' "$name" >> "$HOME/mise-tools"
    printf '%s\n' "$name" >> "$HOME/mise-installed"
    ;;
  "install "*)
    printf '%s\n' "$2" >> "$HOME/mise-installed"
    ;;
  "x "*)
    shift
    tools=""
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do tools="$tools${tools:+,}$1"; shift; done
    shift
    echo "mise-x:$tools:$*"
    ;;
  *) : ;;
esac
exit 0
EOF2
}

setup() {
  setup_test_env
  mock_macos_base
  mock_mise
  source "$TEEUP_PATH/lib/all.sh"
  export DRY_RUN=false
}

test_global_state_distinguishes_the_three_cases() {
  setup
  assert_equals "absent" "$(mise_global_state uv)" || return 1
  printf 'uv\n' > "$TEST_HOME/mise-tools"
  assert_equals "requested" "$(mise_global_state uv)" || return 1
  printf 'uv\n' > "$TEST_HOME/mise-installed"
  assert_equals "installed" "$(mise_global_state uv)" || return 1
  cleanup_test_env
}

test_global_state_is_not_fooled_by_a_project_config() {
  setup
  printf 'uv\n' > "$TEST_HOME/mise-tools"
  printf 'uv\n' > "$TEST_HOME/mise-installed"
  printf 'uv\n' > "$TEST_HOME/mise-local-tools"
  # From inside the project directory the real `mise ls --global` hides the
  # global row; `-C /` is what keeps the answer about the global file.
  assert_equals "installed" "$(cd "$TEST_HOME" && mise_global_state uv)" || return 1
  assert_equals "0" "$(grep -c '^mise [^-]' "$MOCK_LOG" || true)" "every mise call is pinned with -C /" || return 1
  cleanup_test_env
}

test_global_state_falls_back_to_the_config_file() {
  setup
  # A mise too old for --global exits non-zero on it.
  mock_command_script mise <<'EOF2'
[ "$1" = "-C" ] && shift 2
case "$*" in
  "ls --global"*) exit 1 ;;
  "where "*) grep -qx "$2" "$HOME/mise-installed" 2>/dev/null || exit 1 ;;
  *) : ;;
esac
exit 0
EOF2
  mkdir -p "$TEST_HOME/.config/mise"
  assert_equals "absent" "$(mise_global_state uv)" || return 1
  printf '[tools]\nuv = "latest"\n' > "$TEST_HOME/.config/mise/config.toml"
  assert_equals "requested" "$(mise_global_state uv)" || return 1
  printf 'uv\n' > "$TEST_HOME/mise-installed"
  assert_equals "installed" "$(mise_global_state uv)" || return 1
  cleanup_test_env
}

test_ensure_global_installs_reinstalls_or_skips() {
  setup
  local out
  out="$(mise_ensure_global uv latest)"
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / use -g uv@latest" || return 1
  : > "$MOCK_LOG"
  out="$(mise_ensure_global uv latest)"
  assert_contains "$out" "Already installed through mise: uv" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  # Requested but gone from disk: `mise install` honours the pin, `use -g`
  # would rewrite it.
  rm -f "$TEST_HOME/mise-installed"
  : > "$MOCK_LOG"
  out="$(mise_ensure_global uv latest)"
  assert_contains "$out" "uv is requested by the global mise config but not installed" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install uv" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  cleanup_test_env
}

test_ensure_global_dry_run_only_prints() {
  setup
  local out
  out="$(DRY_RUN=true mise_ensure_global go latest)"
  assert_contains "$out" "[DRY-RUN] Would execute: mise -C / use -g go@latest" || return 1
  [[ ! -e "$TEST_HOME/mise-tools" ]] || { echo "dry run must not call mise use"; return 1; }
  cleanup_test_env
}

test_ensure_global_warns_and_fails_when_mise_cannot_install() {
  setup
  mock_command mise 1 ""
  local rc=0 out
  out="$(mise_ensure_global uv latest 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Could not install uv through mise." || return 1
  cleanup_test_env
}

test_wrapper_installs_on_first_call_and_execs_after() {
  setup
  mise_wrapper_write claude claude >/dev/null
  local w="$TEST_HOME/.local/bin/claude" out
  [[ -x "$w" ]] || { echo "wrapper must be executable"; return 1; }
  assert_equals "$TEEUP_MISE_WRAPPER_MARKER" "$(sed -n 2p "$w")" || return 1
  out="$("$w" --version)"
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / use -g --quiet claude" || return 1
  assert_equals "mise-x:claude:claude --version" "$out" || return 1
  : > "$MOCK_LOG"
  out="$("$w" chat "hello there")"
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  assert_equals "mise-x:claude:claude chat hello there" "$out" || return 1
  # `mise x` is the one unpinned call: the command must run in the caller's
  # directory, not in /.
  assert_contains "$(cat "$MOCK_LOG")" "mise x claude -- claude chat hello there" || return 1
  cleanup_test_env
}

test_wrapper_exports_release_age_zero() {
  setup
  mock_command_script mise <<'EOF2'
echo "AGE=${MISE_MINIMUM_RELEASE_AGE:-unset}" >> "$MOCK_LOG"
[ "$1" = "-C" ] && shift 2
case "$*" in
  "where "*) exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  mise_wrapper_write codex codex >/dev/null
  "$TEST_HOME/.local/bin/codex" >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "AGE=0" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "AGE=unset" || return 1
  cleanup_test_env
}

test_wrapper_installs_a_runtime_first_and_loads_it() {
  setup
  mise_wrapper_write gemini gemini node >/dev/null
  local out
  out="$("$TEST_HOME/.local/bin/gemini" chat)"
  assert_equals "mise-x:node,gemini:gemini chat" "$out" || return 1
  # node is installed before gemini, both through the pinned `use -g`.
  assert_equals "node|gemini" "$(grep 'use -g' "$MOCK_LOG" | sed 's/.* //' | tr '\n' '|' | sed 's/|$//')" || return 1
  cleanup_test_env
}

test_wrapper_leaves_a_foreign_command_alone() {
  setup
  mkdir -p "$TEST_HOME/.local/bin" "$TEST_HOME/.local/share/claude/versions"
  # Claude Code's native installer: ~/.local/bin/claude is its symlink.
  printf '#!/bin/sh\necho native\n' > "$TEST_HOME/.local/share/claude/versions/2.1.0"
  ln -s "$TEST_HOME/.local/share/claude/versions/2.1.0" "$TEST_HOME/.local/bin/claude"
  printf '#!/bin/sh\necho mine\n' > "$TEST_HOME/.local/bin/codex"
  local out
  out="$(mise_wrapper_write claude claude 2>&1)"
  assert_contains "$out" "Keeping $TEST_HOME/.local/bin/claude: it was not written by teeup" || return 1
  [[ -L "$TEST_HOME/.local/bin/claude" ]] || { echo "the native symlink must survive"; return 1; }
  out="$(mise_wrapper_write codex codex 2>&1)"
  assert_contains "$out" "Keeping $TEST_HOME/.local/bin/codex" || return 1
  assert_contains "$(cat "$TEST_HOME/.local/bin/codex")" "echo mine" || return 1
  # A wrapper teeup wrote is teeup's to rewrite.
  mise_wrapper_write gemini gemini >/dev/null
  out="$(mise_wrapper_write gemini gemini node)"
  assert_contains "$out" "Wrote $TEST_HOME/.local/bin/gemini" || return 1
  assert_contains "$(cat "$TEST_HOME/.local/bin/gemini")" "exec mise x node gemini -- gemini" || return 1
  cleanup_test_env
}

test_wrapper_rejects_a_name_that_is_not_plain() {
  setup
  local rc=0 out
  out="$(mise_wrapper_write ../evil claude 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "'../evil' is not a plain command or tool name" || return 1
  rc=0
  out="$(mise_wrapper_write ok 'x;y' 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  [[ ! -e "$TEST_HOME/.local/bin/ok" ]] || { echo "nothing may be written"; return 1; }
  cleanup_test_env
}

test_wrapper_write_is_idempotent_and_dry_run_safe() {
  setup
  mise_wrapper_write gemini gemini >/dev/null
  local out
  out="$(mise_wrapper_write gemini gemini)"
  assert_contains "$out" "Already current: $TEST_HOME/.local/bin/gemini" || return 1
  out="$(DRY_RUN=true mise_wrapper_write opencode opencode)"
  assert_contains "$out" "Would write $TEST_HOME/.local/bin/opencode" || return 1
  [[ ! -e "$TEST_HOME/.local/bin/opencode" ]] || { echo "dry run wrote a wrapper"; return 1; }
  cleanup_test_env
}

test_dev_env_python_brings_uv() {
  setup
  local out
  out="$(dev_env_install python)"
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / use -g python@latest" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / use -g uv@latest" || return 1
  assert_contains "$out" "python is ready" || return 1
  state_done check dev-env-python || { echo "dev-env-python must be marked"; return 1; }
  assert_equals "python" "$(dev_env_installed)" || return 1
  cleanup_test_env
}

test_dev_env_each_language_uses_mise() {
  setup
  local l
  for l in node java ruby rust go; do
    dev_env_install "$l" >/dev/null
    assert_contains "$(cat "$MOCK_LOG")" "mise -C / use -g $l@latest" || return 1
  done
  assert_equals "node java ruby rust go" "$(dev_env_installed | tr '\n' ' ' | sed 's/ $//')" || return 1
  cleanup_test_env
}

test_dev_env_rejects_an_unknown_language_and_needs_mise() {
  setup
  local rc=0 out
  out="$(dev_env_install perl 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Usage: teeup install dev-env <python|node|java|ruby|rust|go>" || return 1
  rc=0
  out="$(TEEUP_TEST_MISSING=mise dev_env_install go 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "mise is not installed; run: teeup install mise" || return 1
  cleanup_test_env
}

test_dev_env_leaves_a_pinned_runtime_alone() {
  setup
  # node = "22" already in the global config and installed: nothing to do,
  # and above all no `use -g node@latest` that would rewrite the pin.
  printf 'node\n' > "$TEST_HOME/mise-tools"
  printf 'node\n' > "$TEST_HOME/mise-installed"
  local out
  out="$(dev_env_install node)"
  assert_contains "$out" "Already installed through mise: node" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  cleanup_test_env
}

echo "lib/mise.sh"
run_test "global state distinguishes the three cases" test_global_state_distinguishes_the_three_cases
run_test "global state is not fooled by a project config" test_global_state_is_not_fooled_by_a_project_config
run_test "global state falls back to the config file" test_global_state_falls_back_to_the_config_file
run_test "ensure_global installs, reinstalls or skips" test_ensure_global_installs_reinstalls_or_skips
run_test "ensure_global dry run only prints" test_ensure_global_dry_run_only_prints
run_test "ensure_global warns and fails when mise cannot install" test_ensure_global_warns_and_fails_when_mise_cannot_install
run_test "wrapper installs on first call and execs after" test_wrapper_installs_on_first_call_and_execs_after
run_test "wrapper exports release age zero" test_wrapper_exports_release_age_zero
run_test "wrapper installs a runtime first and loads it" test_wrapper_installs_a_runtime_first_and_loads_it
run_test "wrapper leaves a foreign command alone" test_wrapper_leaves_a_foreign_command_alone
run_test "wrapper rejects a name that is not plain" test_wrapper_rejects_a_name_that_is_not_plain
run_test "wrapper write is idempotent and dry-run safe" test_wrapper_write_is_idempotent_and_dry_run_safe
run_test "dev-env python brings uv" test_dev_env_python_brings_uv
run_test "dev-env each language uses mise" test_dev_env_each_language_uses_mise
run_test "dev-env rejects an unknown language and needs mise" test_dev_env_rejects_an_unknown_language_and_needs_mise
run_test "dev-env leaves a pinned runtime alone" test_dev_env_leaves_a_pinned_runtime_alone
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/lib/mise.sh`
Expected: every test fails with `command not found` for the function it calls; `Summary: 0/16 passed`.

- [ ] **Step 3: Write `lib/mise.sh`**

```bash file=lib/mise.sh
#!/usr/bin/env bash
# mise.sh - mise-managed tools: the global-state check every mise consumer
# needs, the on-first-call wrappers for AI CLIs, and `teeup install dev-env`.
# Requires core.sh, files.sh, state.sh and pkg.sh.
#
# Every mise call here runs with `-C /` ("Change directory before running
# command") except the `mise x` line inside a wrapper, which must run in the
# caller's directory. mise resolves its configuration stack from the current
# directory, so run from inside a project whose own mise.toml also asks for
# the tool, `mise ls --global` hides the global row entirely (verified on
# 2026.9.4: the project's request shadows the global one), `mise install`
# resolves the project's version and `mise where` reports the project's
# install. From `/` no project config is in reach and the global config
# (MISE_CONFIG_DIR or ~/.config/mise, unaffected by -C) is the whole stack.

# mise_global_state <tool> -> installed | requested | absent
# Two questions, because mise answers them separately. `mise ls --global`
# ("Only show tool versions currently specified in the global mise.toml")
# says whether the global config *requests* the tool, but it lists requested
# versions whether or not they are installed, so a row there is no proof of a
# binary: an interrupted install, a manual uninstall or a wiped MISE_DATA_DIR
# all leave the request behind with the tool gone. `--installed` ("Hides
# tools defined in mise.toml but not installed") answers the second question;
# with both flags and the tool name, a row comes back only when the tool is
# requested globally and on disk. A mise that rejects --installed gets
# `mise where <tool>` instead, which fails when the requested version is not
# installed. A mise too old for --global exits non-zero on it; there, the
# global config file (the same file `mise use -g` writes) answers the first
# question and `mise where` the second.
mise_global_state() {
  local tool="$1" config_file rows
  config_file="${MISE_CONFIG_DIR:-$(user_config_dir)/mise}/config.toml"
  if rows="$(mise -C / ls --global 2>/dev/null)"; then
    if printf '%s\n' "$rows" | awk '{print $1}' | grep -qx "$tool"; then
      if rows="$(mise -C / ls --global --installed "$tool" 2>/dev/null)"; then
        if printf '%s\n' "$rows" | awk '{print $1}' | grep -qx "$tool"; then
          echo installed
          return 0
        fi
      elif mise -C / where "$tool" >/dev/null 2>&1; then
        echo installed
        return 0
      fi
      echo requested
      return 0
    fi
  elif [[ -f "$config_file" ]]; then
    if grep -qE "^[[:space:]]*(\"$tool\"|$tool)[[:space:]]*=" "$config_file"; then
      if mise -C / where "$tool" >/dev/null 2>&1; then echo installed; else echo requested; fi
      return 0
    fi
  fi
  echo absent
}

# mise_ensure_global <tool> [version]
#   requested and installed  -> nothing to do
#   requested but missing    -> `mise install` (honours the pinned version;
#                               `mise use -g` would rewrite the request)
#   not requested            -> `mise use -g` (writes the request and installs)
# Warns and returns 1 when mise cannot install it, so a caller under `set -e`
# decides whether that is fatal.
mise_ensure_global() {
  local tool="$1" version="${2:-}"
  case "$(mise_global_state "$tool")" in
    installed)
      log "Already installed through mise: $tool"
      ;;
    requested)
      log "$tool is requested by the global mise config but not installed; installing it."
      run_cmd mise -C / install "$tool" || { warn "Could not install $tool through mise."; return 1; }
      ;;
    *)
      run_cmd mise -C / use -g "$tool${version:+@$version}" || { warn "Could not install $tool through mise."; return 1; }
      ;;
  esac
}

# The second line of every wrapper teeup writes. mise_wrapper_write replaces
# only files that carry it, so a `claude` some other installer put in
# ~/.local/bin (Claude Code's native installer manages ~/.local/bin/claude as
# a symlink) is left alone with a warning instead of being overwritten.
TEEUP_MISE_WRAPPER_MARKER="# teeup mise wrapper; regenerated by: teeup configure ai"

# mise_wrapper_write <command> <tool> [runtime...]
# Omarchy's omarchy-mise-install pattern: ~/.local/bin/<command> installs
# <tool> through mise on its first call and execs it through `mise x` after
# that, so `mise upgrade` keeps it current and nothing is downloaded at
# configure time. `mise where` exits non-zero until a tool is installed, so a
# later call costs one `mise where` per tool and never rewrites a version the
# user pinned in the global config. A runtime is a tool the command needs at
# run time that mise will not bring along (the npm backend installs a package
# without Node, but the package still runs on Node); it is installed first and
# loaded into the same `mise x`. MISE_MINIMUM_RELEASE_AGE=0 lifts mise's
# release cooldown for these self-updating tools and is exported, as Omarchy
# does, so the version `mise x` resolves agrees with the one just installed.
# Every call is `mise -C /` except `mise x`, which must run the command in the
# caller's directory (verified: `mise -C / x uv -- pwd` prints `/`).
mise_wrapper_write() {
  local command="$1" tool="$2" file t tools
  shift 2
  tools="$* $tool"
  tools="${tools# }"
  for t in "$command" $tools; do
    if ! [[ "$t" =~ ^[A-Za-z0-9][A-Za-z0-9_.+-]*$ ]]; then
      err "mise_wrapper_write: '$t' is not a plain command or tool name"
      return 1
    fi
  done
  file="$HOME/.local/bin/$command"
  if [[ -e "$file" || -L "$file" ]] && ! sed -n 2p "$file" 2>/dev/null | grep -qxF "$TEEUP_MISE_WRAPPER_MARKER"; then
    warn "Keeping $file: it was not written by teeup. Remove it and run teeup configure ai to use the mise wrapper."
    return 0
  fi
  [[ -d "$HOME/.local/bin" ]] || run_cmd mkdir -p "$HOME/.local/bin"
  write_managed_file "$file" "mise wrapper for $command" <<WRAPPER
#!/bin/bash
$TEEUP_MISE_WRAPPER_MARKER
# Installs $tools through mise on the first call, then runs $command.
export MISE_MINIMUM_RELEASE_AGE=0
for teeup_tool in $tools; do
  mise -C / where "\$teeup_tool" >/dev/null 2>&1 || mise -C / use -g --quiet "\$teeup_tool" || exit 1
done
exec mise x $tools -- $command "\$@"
WRAPPER
  [[ "$DRY_RUN" == "true" ]] || chmod 755 "$file"
}

# --- teeup install dev-env ---------------------------------------------------

TEEUP_DEV_ENVS="python node java ruby rust go"

# dev_env_install <python|node|java|ruby|rust|go>
# Runtimes get no shims (spec section 4a: macOS ships python3, ruby and java,
# so a PATH-last shim could never fire) and arrive only through this command.
# Everything is `mise use --global`; Python brings uv along; Rust goes
# through mise's rust backend, which drives rustup (installing it into
# ~/.rustup and ~/.cargo when no rustup is on PATH), so the same call works
# on a Homebrew and on a MacPorts machine.
dev_env_install() {
  local lang="${1:-}" l known=false
  for l in $TEEUP_DEV_ENVS; do
    if [[ "$l" == "$lang" ]]; then known=true; fi
  done
  if [[ "$known" != "true" ]]; then
    err "Usage: teeup install dev-env <python|node|java|ruby|rust|go>"
    return 1
  fi
  if ! have mise; then
    err "mise is not installed; run: teeup install mise"
    return 1
  fi
  case "$lang" in
    python)
      mise_ensure_global python latest || return 1
      mise_ensure_global uv latest || return 1
      ;;
    node) mise_ensure_global node latest || return 1 ;;
    java)
      mise_ensure_global java latest || return 1
      log "Switch Java per shell with: javav 21 (Corretto 21), javav zulu-17, javav (show)"
      ;;
    ruby) mise_ensure_global ruby latest || return 1 ;;
    rust) mise_ensure_global rust latest || return 1 ;;
    go) mise_ensure_global go latest || return 1 ;;
  esac
  state_done mark "dev-env-$lang"
  ok "$lang is ready: the next prompt in this shell has it (mise activate); other shells after a new terminal."
}

# dev_env_installed -> the dev-envs this machine has marked, one per line.
dev_env_installed() {
  local l
  for l in $TEEUP_DEV_ENVS; do
    state_done check "dev-env-$l" && printf '%s\n' "$l"
  done
  return 0
}
```

- [ ] **Step 4: Source it from `lib/all.sh`**

```bash edit-old=lib/all.sh
for _teeup_lib in files state answers pkg ui capability macos theme font lazy; do
```

```bash edit-new=lib/all.sh
for _teeup_lib in files state answers pkg ui capability macos theme font lazy mise; do
```

- [ ] **Step 5: Rewrite `capabilities/mise/configure` on top of the library**

The requested/installed logic and its long comment move into `mise_global_state`; the capability keeps the copy-once config and the one call. `|| true` keeps the phase 2a behaviour (a failed pre-commit install warns and the core tier continues).

```bash file=capabilities/mise/configure
#!/usr/bin/env bash
# MISE_CONFIG_DIR wins when set: mise itself reads its config from there, not
# from $(user_config_dir)/mise, so teeup's file has to land in the same place
# mise will actually look.
copy_config_once "$TEEUP_CAP_DIR/config/mise/config.toml" "${MISE_CONFIG_DIR:-$(user_config_dir)/mise}/config.toml"

if ! have mise; then
  warn "mise is not installed; skipping pre-commit."
  exit 0
fi

# pre-commit lives here, not in the git capability: it is a mise-managed tool,
# and git runs before mise in the core list. mise_ensure_global (lib/mise.sh)
# carries the requested/installed distinction and the `-C /` rule; a failure
# there warns, and this capability continues, because a missing pre-commit
# must not take the rest of the core tier down.
mise_ensure_global pre-commit || true
```

- [ ] **Step 6: Run both mise suites**

Run: `bash tests/lib/mise.sh && bash tests/capabilities/mise.sh`
Expected: `Summary: 16/16 passed` and `Summary: 10/10 passed`. The capability suite's mock is unchanged; every one of its strings (`Already installed through mise: pre-commit`, `requested by the global mise config but not installed`, `mise -C / use -g pre-commit`, `mise -C / install pre-commit`) still comes out of the library.

- [ ] **Step 7: Full checks and commit**

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning lib/mise.sh lib/all.sh capabilities/mise/configure tests/lib/mise.sh
git diff --check
git add lib/mise.sh lib/all.sh capabilities/mise/configure tests/lib/mise.sh
git commit -m "Add the mise library and use it for pre-commit"
```

Expected: `All N suites passed.` where N is the suite count printed before this task, plus 1.

---

### Task 3: Shim generation in `teeup-runtime` and `teeup lazy-run`

**Files:**
- Modify: `capabilities/teeup-runtime/configure`, `bin/teeup`, `capabilities/zsh/default/env`, `tests/capabilities/teeup-runtime.sh`, `tests/cli.sh`, `tests/capabilities/zsh.sh`

**Interfaces:**
- Consumes: `shims_generate`, `lazy_real_command`, `lazy_is_tty` (Task 1); `ui_confirm` (`lib/ui.sh`); `pkg_backend_path` (`lib/pkg.sh`); `state_done` (`lib/state.sh`); `cap_exists`, `cap_meta_get`, `cap_skipped` (`lib/capability.sh`); `cmd_install` (`bin/teeup`).
- Produces: `teeup configure teeup-runtime` writes and prunes `$TEEUP_STATE_DIR/shims`; `teeup lazy-run <capability> <command> [args...]` with the exit codes of contract 2; the `teeup lazy-run` usage line; a zsh default layer that moves the shims directory to the end of `PATH` on every pass (under either package-manager ordering) and whose `EDITOR` probe does not take a `nvim` shim for Neovim. Task 5's round trip is built on all of these.

**Real-Mac risk:** zsh remembers where it found a command. After a shim's install, the same shell still reaches `docker` through the shim (zsh hashed that path) until `rehash` or a new shell; each such call costs one `teeup lazy-run` that immediately execs the real binary, which is correct but slower, and only a real terminal session shows how noticeable that is. Apps launched from the Dock or Finder do not see `$TEEUP_STATE_DIR/shims` at all (no login shell), which matches spec section 6: shims serve the interactive shell. Under gum, `ui_confirm` draws on `/dev/tty`; a shim run from a program that gives it a terminal on stdin and stderr but no one to answer would wait on that prompt. The zsh tests source the layer under `zsh -f` with a fake prefix root; macOS's `/etc/zprofile` (`path_helper`) and a real `brew shellenv` between the two passes are not reproduced, and only a login shell on hardware shows the final order.

- [ ] **Step 1: Write the failing runtime tests**

Add to `tests/capabilities/teeup-runtime.sh`, above its `echo` line, and register the three tests:

```bash edit-old=tests/capabilities/teeup-runtime.sh
echo "capabilities/teeup-runtime"
```

```bash edit-new=tests/capabilities/teeup-runtime.sh
# A capability tree of our own: the real teeup-runtime plus one lazy fixture,
# so the shim assertions do not depend on which lazy capabilities the repo
# ships at any given moment.
setup_with_lazy_fixture() {
  setup
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR/boxes"
  cp -R "$TEEUP_PATH/capabilities/teeup-runtime" "$TEEUP_CAPS_DIR/teeup-runtime"
  printf 'summary="Fixture boxes"\ngroup=containers\ntier=lazy\nrequires=""\nprovides="boxctl boxd"\ninteractive=false\n' > "$TEEUP_CAPS_DIR/boxes/capability"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/boxes/install"
  cp "$TEEUP_CAPS_DIR/boxes/install" "$TEEUP_CAPS_DIR/boxes/configure"
  chmod +x "$TEEUP_CAPS_DIR/boxes/install" "$TEEUP_CAPS_DIR/boxes/configure"
  printf 'teeup-runtime\n' > "$TEEUP_CAPS_DIR/core.list"
  : > "$TEEUP_CAPS_DIR/daily.list"
  SHIMS="$TEST_HOME/.local/state/teeup/shims"
}

test_configure_writes_the_lazy_shims() {
  setup_with_lazy_fixture
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  assert_file_exists "$SHIMS/boxctl" || return 1
  assert_file_exists "$SHIMS/boxd" || return 1
  [[ -x "$SHIMS/boxd" ]] || { echo "shim must be executable"; return 1; }
  assert_contains "$(cat "$SHIMS/boxd")" 'lazy-run boxes boxd "$@"' || return 1
  [[ ! -e "$SHIMS/teeup-runtime" ]] || { echo "a core capability gets no shim"; return 1; }
  cleanup_test_env
}

test_configure_removes_a_shim_its_capability_dropped() {
  setup_with_lazy_fixture
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  sed -i.bak 's/^provides=.*/provides="boxd"/' "$TEEUP_CAPS_DIR/boxes/capability" && rm "$TEEUP_CAPS_DIR/boxes/capability.bak"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure teeup-runtime 2>&1)"
  assert_contains "$out" "Removed stale shim: boxctl" || return 1
  assert_contains "$out" "Already current: $SHIMS/boxd" || return 1
  [[ ! -e "$SHIMS/boxctl" ]] || { echo "dropped command must lose its shim"; return 1; }
  cleanup_test_env
}

test_configure_dry_run_writes_no_shims() {
  setup_with_lazy_fixture
  local out
  out="$(DRY_RUN=true "$TEEUP" configure teeup-runtime)"
  assert_contains "$out" "Would write $SHIMS/boxd" || return 1
  [[ ! -e "$SHIMS/boxd" ]] || { echo "shim written in dry run"; return 1; }
  cleanup_test_env
}

echo "capabilities/teeup-runtime"
```

```bash edit-old=tests/capabilities/teeup-runtime.sh
run_test "configure backs up a regular file at the link" test_configure_backs_up_a_regular_file_at_the_link
```

```bash edit-new=tests/capabilities/teeup-runtime.sh
run_test "configure backs up a regular file at the link" test_configure_backs_up_a_regular_file_at_the_link
run_test "configure writes the lazy shims" test_configure_writes_the_lazy_shims
run_test "configure removes a shim its capability dropped" test_configure_removes_a_shim_its_capability_dropped
run_test "configure dry run writes no shims" test_configure_dry_run_writes_no_shims
```

- [ ] **Step 2: Write the failing CLI tests in `tests/cli.sh`**

The fixture builder gains `provides` and `apps` parameters (the phase 1 version wrote `provides=""` and no `apps`):

```bash edit-old=tests/cli.sh
make_cap() {
  local name="$1" tier="$2" requires="${3:-}"
  local dir="$TEEUP_CAPS_DIR/$name"
  mkdir -p "$dir"
  printf 'summary="Fixture %s"\ngroup=system\ntier=%s\nrequires="%s"\nprovides=""\ninteractive=false\n' "$name" "$tier" "$requires" > "$dir/capability"
```

```bash edit-new=tests/cli.sh
make_cap() {
  local name="$1" tier="$2" requires="${3:-}" provides="${4:-}" apps="${5:-}"
  local dir="$TEEUP_CAPS_DIR/$name"
  mkdir -p "$dir"
  printf 'summary="Fixture %s"\ngroup=system\ntier=%s\nrequires="%s"\nprovides="%s"\napps="%s"\ninteractive=false\n' "$name" "$tier" "$requires" "$provides" "$apps" > "$dir/capability"
```

`setup` gets a lazy command capability (`lazyone` provides `frob`), a lazy app capability (`sketch`, used by Task 4), and the two environment settings both verbs need; `make_frob_installable` follows it:

```bash edit-old=tests/cli.sh
  make_cap lazyone lazy
  printf 'alpha\nbeta\n' > "$TEEUP_CAPS_DIR/core.list"
  : > "$TEEUP_CAPS_DIR/daily.list"
  TEEUP="$TEEUP_PATH/bin/teeup"
}
```

```bash edit-new=tests/cli.sh
  make_cap lazyone lazy "" "frob" ""
  make_cap sketch lazy "" "" "Sketch Pad"
  printf 'alpha\nbeta\n' > "$TEEUP_CAPS_DIR/core.list"
  : > "$TEEUP_CAPS_DIR/daily.list"
  TEEUP="$TEEUP_PATH/bin/teeup"
  # lazy-run and launch ask through ui_confirm and probe /Applications; keep
  # both away from gum and from the real folder.
  export TEEUP_NO_GUM=1
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
}

# lazyone's install puts a real `frob` on PATH (in MOCK_BIN, ahead of the
# shims), the way a package install would; the binary echoes its arguments so
# the exec at the end of lazy-run can be checked.
make_frob_installable() {
  cat > "$TEEUP_CAPS_DIR/lazyone/install" <<EOF2
#!/usr/bin/env bash
echo "install:lazyone"
printf '#!/usr/bin/env bash\necho "frob ran: \$*"\n' > "$MOCK_BIN/frob"
chmod +x "$MOCK_BIN/frob"
EOF2
}
```

The fixture tree now holds four capabilities, so the status count changes:

```bash edit-old=tests/cli.sh
  assert_contains "$out" "Installed: 1 of 3" || return 1
```

```bash edit-new=tests/cli.sh
  assert_contains "$out" "Installed: 1 of 4" || return 1
```

The help test checks the new usage line:

```bash edit-old=tests/cli.sh
  assert_contains "$("$TEEUP" help)" "teeup install font list" || return 1
```

```bash edit-new=tests/cli.sh
  assert_contains "$("$TEEUP" help)" "teeup install font list" || return 1
  assert_contains "$("$TEEUP" help)" "teeup lazy-run <cap> <cmd> [args]" || return 1
```

The nine `lazy-run` tests go above the `echo` line:

```bash edit-old=tests/cli.sh
echo "bin/teeup"
```

```bash edit-new=tests/cli.sh
test_lazy_run_execs_a_real_binary_when_one_exists() {
  setup
  mock_command frob 0 "the real frob"
  local out
  out="$("$TEEUP" lazy-run lazyone frob --one "two words")"
  assert_equals "the real frob" "$out" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "frob --one two words" || return 1
  assert_not_contains "$out" "install:lazyone" || return 1
  cleanup_test_env
}

test_lazy_run_without_a_tty_hints_and_exits_127() {
  setup
  local rc=0 out
  out="$(TEEUP_TEST_TTY=no "$TEEUP" lazy-run lazyone frob 2>&1)" || rc=$?
  assert_equals "127" "$rc" || return 1
  assert_contains "$out" "frob is not installed. It is provided by capability lazyone; run: teeup install lazyone" || return 1
  assert_not_contains "$out" "install:lazyone" || return 1
  cleanup_test_env
}

test_lazy_run_on_a_tty_installs_configures_and_execs() {
  setup
  make_frob_installable
  local out
  out="$(printf 'y\n' | TEEUP_TEST_TTY=yes "$TEEUP" lazy-run lazyone frob --flag "two words" 2>&1)"
  assert_contains "$out" "frob is provided by capability lazyone. Install now?" || return 1
  assert_contains "$out" "install:lazyone" || return 1
  assert_contains "$out" "configure:lazyone" || return 1
  assert_contains "$out" "frob ran: --flag two words" || return 1
  "$TEEUP" has lazyone || { echo "lazyone must be marked installed"; return 1; }
  cleanup_test_env
}

test_lazy_run_declined_exits_127_without_installing() {
  setup
  make_frob_installable
  local rc=0 out
  out="$(printf 'n\n' | TEEUP_TEST_TTY=yes "$TEEUP" lazy-run lazyone frob 2>&1)" || rc=$?
  assert_equals "127" "$rc" || return 1
  assert_contains "$out" "Not installed. When you want it: teeup install lazyone" || return 1
  assert_not_contains "$out" "install:lazyone" || return 1
  cleanup_test_env
}

test_lazy_run_respects_teeup_skip() {
  setup
  local rc=0 out
  out="$(printf 'y\n' | TEEUP_SKIP=lazyone TEEUP_TEST_TTY=yes "$TEEUP" lazy-run lazyone frob 2>&1)" || rc=$?
  assert_equals "127" "$rc" || return 1
  assert_contains "$out" "frob is provided by capability lazyone, which is skipped on this machine (TEEUP_SKIP)." || return 1
  assert_not_contains "$out" "install:lazyone" || return 1
  cleanup_test_env
}

test_lazy_run_reinstalls_a_capability_whose_command_went_missing() {
  setup
  "$TEEUP" install lazyone >/dev/null
  # Marked installed, but frob is gone: the question comes back, and an
  # install that still produces no frob ends in a clear 127.
  local rc=0 out
  out="$(printf 'y\n' | TEEUP_TEST_TTY=yes "$TEEUP" lazy-run lazyone frob 2>&1)" || rc=$?
  assert_equals "127" "$rc" || return 1
  assert_contains "$out" "frob is provided by capability lazyone. Install now?" || return 1
  assert_contains "$out" "install:lazyone" || return 1
  assert_contains "$out" "lazyone is installed but frob is still not on PATH" || return 1
  # With an install that does put frob back, the command runs.
  make_frob_installable
  out="$(printf 'y\n' | TEEUP_TEST_TTY=yes "$TEEUP" lazy-run lazyone frob again 2>&1)"
  assert_contains "$out" "frob ran: again" || return 1
  cleanup_test_env
}

test_lazy_run_finds_a_command_under_the_package_prefix() {
  setup
  # Installed by the package manager, but the calling PATH lacks its bin
  # directory: lazy-run adds it and execs without asking.
  mkdir -p "$TEEUP_PKG_PREFIX/bin"
  printf '#!/usr/bin/env bash\necho "prefix frob: $*"\n' > "$TEEUP_PKG_PREFIX/bin/frob"
  chmod +x "$TEEUP_PKG_PREFIX/bin/frob"
  local out
  out="$(TEEUP_TEST_TTY=no "$TEEUP" lazy-run lazyone frob x 2>&1)"
  assert_equals "prefix frob: x" "$out" || return 1
  cleanup_test_env
}

test_lazy_run_dry_run_previews_and_runs_nothing() {
  setup
  make_frob_installable
  local out
  out="$(printf 'y\n' | DRY_RUN=true TEEUP_TEST_TTY=yes "$TEEUP" lazy-run lazyone frob 2>&1)"
  assert_contains "$out" "Would record state: done/cap-lazyone" || return 1
  assert_contains "$out" "Dry run: frob was not installed, so it was not run." || return 1
  assert_not_contains "$out" "frob ran" || return 1
  cleanup_test_env
}

test_lazy_run_rejects_a_command_the_capability_does_not_provide() {
  setup
  local rc=0 out
  out="$("$TEEUP" lazy-run lazyone nope 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "lazyone does not provide nope" || return 1
  out="$("$TEEUP" lazy-run 2>&1)" || rc=$?
  assert_contains "$out" "Usage: teeup lazy-run <capability> <command> [args...]" || return 1
  cleanup_test_env
}

echo "bin/teeup"
```

```bash edit-old=tests/cli.sh
run_test "list --tier without a value errors" test_list_tier_without_a_value_errors
```

```bash edit-new=tests/cli.sh
run_test "list --tier without a value errors" test_list_tier_without_a_value_errors
run_test "lazy-run execs a real binary when one exists" test_lazy_run_execs_a_real_binary_when_one_exists
run_test "lazy-run without a tty hints and exits 127" test_lazy_run_without_a_tty_hints_and_exits_127
run_test "lazy-run on a tty installs, configures and execs" test_lazy_run_on_a_tty_installs_configures_and_execs
run_test "lazy-run declined exits 127 without installing" test_lazy_run_declined_exits_127_without_installing
run_test "lazy-run respects TEEUP_SKIP" test_lazy_run_respects_teeup_skip
run_test "lazy-run reinstalls a capability whose command went missing" test_lazy_run_reinstalls_a_capability_whose_command_went_missing
run_test "lazy-run finds a command under the package prefix" test_lazy_run_finds_a_command_under_the_package_prefix
run_test "lazy-run dry run previews and runs nothing" test_lazy_run_dry_run_previews_and_runs_nothing
run_test "lazy-run rejects a command the capability does not provide" test_lazy_run_rejects_a_command_the_capability_does_not_provide
```

- [ ] **Step 3: Write the failing zsh layer tests in `tests/capabilities/zsh.sh`**

Phase 2a already appends the shims last (`test_default_env_appends_the_shims_last`), but only from a clean `PATH`, and only once. Two cases are left: an inherited `PATH` that already holds the shims ahead of other entries (a nested shell whose parent's `local.zsh` appended a directory, then the layer sourced again, as `~/.zshenv` and `~/.zprofile` both do), under the machine file's MacPorts ordering; and the `EDITOR` probe, which a `nvim` shim (plan 3a's `neovim` capability provides `nvim`) would otherwise answer on a machine with no Neovim. Add both above the `echo` line and register them:

```bash edit-old=tests/capabilities/zsh.sh
echo "capabilities/zsh"
```

```bash edit-new=tests/capabilities/zsh.sh
test_default_env_moves_the_shims_last_under_a_macports_machine_file() {
  setup
  require_zsh || return 1
  local root="$TEST_HOME/prefixroot" shims="$TEST_HOME/.local/state/teeup/shims"
  mkdir -p "$root/opt/local/bin" "$root/opt/local/sbin" "$root/opt/homebrew/bin" "$root/opt/homebrew/sbin"
  : > "$root/opt/homebrew/bin/brew"
  chmod +x "$root/opt/homebrew/bin/brew"
  mkdir -p "$TEST_HOME/.local/bin" "$shims" "$TEST_HOME/machines"
  # machine_file() looks up $TEEUP_PATH/machines/<hostname -s>.conf, and
  # mock_macos_base answers "testmac"; TEEUP_PATH is pointed at TEST_HOME
  # inside the zsh process only, as in the machine-file test above.
  printf 'TEEUP_PACKAGE_MANAGER="macports"\n' > "$TEST_HOME/machines/testmac.conf"
  local out n macports_pos brew_pos
  out="$(PATH="$shims:$PATH:$TEST_HOME/appended" TEEUP_TEST_PREFIX_ROOT="$root" zsh -f -c "export TEEUP_PATH='$TEST_HOME'; . '$TEEUP_PATH/capabilities/zsh/default/env'; . '$TEEUP_PATH/capabilities/zsh/default/env'; printf '%s\n' \"\$PATH\"")"
  [[ "$out" == *":$shims" ]] || { echo "teeup shims must be the last PATH entry, got: $out"; return 1; }
  n="$(printf '%s' "$out" | tr ':' '\n' | grep -cxF "$shims" || true)"
  assert_equals "1" "$n" "the shims directory appears once" || return 1
  macports_pos="$(printf '%s' "$out" | tr ':' '\n' | grep -nxF "$root/opt/local/bin" | head -1 | cut -d: -f1)"
  brew_pos="$(printf '%s' "$out" | tr ':' '\n' | grep -nxF "$root/opt/homebrew/bin" | head -1 | cut -d: -f1)"
  [[ -n "$macports_pos" && -n "$brew_pos" && "$macports_pos" -lt "$brew_pos" ]] ||
    { echo "expected MacPorts before Homebrew (machine file must win), got: $out"; return 1; }
  cleanup_test_env
}

test_default_env_editor_ignores_a_lazy_shim() {
  setup
  require_zsh || return 1
  local shims="$TEST_HOME/.local/state/teeup/shims" zsh_bin out
  zsh_bin="$(command -v zsh)"
  mkdir -p "$shims"
  printf '#!/bin/bash\nexit 127\n' > "$shims/nvim"
  chmod +x "$shims/nvim"
  # Only MOCK_BIN and the shims are searched, so an nvim, emacsclient or vim
  # on the host cannot answer the probe.
  out="$(PATH="$MOCK_BIN:$shims" "$zsh_bin" -f -c "unset EDITOR VISUAL; . '$TEEUP_PATH/capabilities/zsh/default/env'; print -r -- \$EDITOR" 2>/dev/null)"
  assert_equals "vim" "$out" "a lazy shim is not an installed nvim" || return 1
  mock_command nvim 0 ""
  out="$(PATH="$MOCK_BIN:$shims" "$zsh_bin" -f -c "unset EDITOR VISUAL; . '$TEEUP_PATH/capabilities/zsh/default/env'; print -r -- \$EDITOR" 2>/dev/null)"
  assert_equals "nvim" "$out" "a real nvim ahead of the shims counts" || return 1
  cleanup_test_env
}

echo "capabilities/zsh"
```

```bash edit-old=tests/capabilities/zsh.sh
run_test "default env lets the machine file override the answers file" test_default_env_lets_the_machine_file_override_the_answers_file
```

```bash edit-new=tests/capabilities/zsh.sh
run_test "default env lets the machine file override the answers file" test_default_env_lets_the_machine_file_override_the_answers_file
run_test "default env moves the shims last under a macports machine file" test_default_env_moves_the_shims_last_under_a_macports_machine_file
run_test "default env editor ignores a lazy shim" test_default_env_editor_ignores_a_lazy_shim
```

- [ ] **Step 4: Run the three suites to see them fail**

Run: `bash tests/capabilities/teeup-runtime.sh; bash tests/cli.sh; bash tests/capabilities/zsh.sh`
Expected: the three new runtime tests fail (`File not found: .../shims/boxctl`); the nine `lazy-run` tests and `help lists verbs` fail (`Unknown verb: lazy-run`, exit 2 where 127 was expected); the two new zsh tests fail (the shims stay first, and `EDITOR` comes out as `nvim` from the shim). `Summary: 6/9 passed`, `Summary: 12/22 passed` and `Summary: 21/23 passed`.

- [ ] **Step 5: Call `shims_generate` from `capabilities/teeup-runtime/configure`**

The whole file, with the new block at the end:

```bash file=capabilities/teeup-runtime/configure
#!/usr/bin/env bash
# State lives under ~/.local/state/teeup as plain files; the env file tells
# shells and LaunchAgents where the checkout is; ~/.local/bin/teeup is the
# command users type.
for d in "done" toggles migrations shims logs current stock; do
  [[ -d "$TEEUP_STATE_DIR/$d" ]] || run_cmd mkdir -p "$TEEUP_STATE_DIR/$d"
done
[[ -d "$TEEUP_CONFIG_DIR/hooks" ]] || run_cmd mkdir -p "$TEEUP_CONFIG_DIR/hooks"

# TEEUP_CONFIG_DIR and TEEUP_STATE_DIR are written here too, not just
# TEEUP_PATH: the shell layer's home files (capabilities/zsh/configure) bake
# this file's own path in as an absolute string at configure time, so nothing
# a login shell reads before ~/.zshenv (XDG_CONFIG_HOME included) can ever
# make the CLI and the shell disagree about where the rest of teeup's files
# live.
# Each value is %q-escaped before it lands inside the double-quoted-looking
# assignment below: a raw $, `, " or \ in one of these paths would otherwise
# break out of the export line and corrupt the rest of the file. bash 3.2's
# %q emits backslash escapes or a $'...' literal; zsh 5.9 parses both forms
# identically for these characters, so the same env file works for both
# shells that source it.
teeup_path_q="$(printf '%q' "$TEEUP_PATH")"
teeup_config_dir_q="$(printf '%q' "$TEEUP_CONFIG_DIR")"
teeup_state_dir_q="$(printf '%q' "$TEEUP_STATE_DIR")"
write_managed_file "$TEEUP_CONFIG_DIR/env" "teeup env" <<TEEUP_ENV
export TEEUP_PATH=$teeup_path_q
export TEEUP_CONFIG_DIR=$teeup_config_dir_q
export TEEUP_STATE_DIR=$teeup_state_dir_q
TEEUP_ENV

link="$HOME/.local/bin/teeup"
[[ -d "$HOME/.local/bin" ]] || run_cmd mkdir -p "$HOME/.local/bin"
if [[ "$(readlink "$link" 2>/dev/null)" == "$TEEUP_PATH/bin/teeup" ]]; then
  log "Already linked: $link"
else
  # A real file here is somebody's script, not our symlink; every other
  # user-facing write goes through backup_target, so this one does too.
  if [[ -e "$link" && ! -L "$link" ]]; then
    warn "Replacing a regular file at $link"
    backup_target "$link" >/dev/null
  fi
  run_cmd ln -sfn "$TEEUP_PATH/bin/teeup" "$link"
  ok "Linked $link"
fi

# Lazy shims (spec section 6): one per command in provides= of every
# tier=lazy capability, stale ones removed. The zsh layer appends the shims
# directory last on PATH, so a shim only fires for a command nothing real
# provides. Re-run `teeup configure teeup-runtime` after adding a lazy
# capability; `teeup update` will do that for the whole core tier.
shims_generate
```

- [ ] **Step 6: Add `teeup lazy-run` to `bin/teeup`** (three edits)

The usage line, just above `teeup has`:

```bash edit-old=bin/teeup
  teeup has <capability>         exit 0 when installed (for scripts and menus)
```

```bash edit-new=bin/teeup
  teeup lazy-run <cap> <cmd> [args]  what a lazy shim runs: install <cap> on first use, then exec <cmd>
  teeup has <capability>         exit 0 when installed (for scripts and menus)
```

The verb, placed just above `cmd_has`:

```bash edit-old=bin/teeup
cmd_has() {
```

```bash edit-new=bin/teeup
# What every lazy shim runs (lib/lazy.sh writes them). A real binary anywhere
# on PATH other than the shims directory wins outright; the package manager's
# bin directories are added first, because a shim fires whenever the calling
# shell's PATH lacks the command, and a stripped environment (an editor's
# process runner, a script run with `env -i`) can lack /opt/homebrew/bin
# while the tool is already installed there. Otherwise the capability is
# installed, on a terminal and after a yes, and the real binary is exec'd
# with the original arguments. A capability already marked installed whose
# command has gone missing (uninstalled by hand) gets the same question: its
# install is idempotent and puts the command back. Exit 127 is "command not
# found" for every path that ends without running the command, so a script
# that hit the shim fails the way it would have without teeup, with a hint.
cmd_lazy_run() {
  local cap="${1:-}" command="${2:-}" real p found=false
  if [[ -z "$cap" || -z "$command" ]]; then
    die "Usage: teeup lazy-run <capability> <command> [args...]"
  fi
  shift 2
  cap_exists "$cap" || die "Unknown capability: $cap"
  for p in $(cap_meta_get "$cap" provides); do
    if [[ "$p" == "$command" ]]; then found=true; fi
  done
  [[ "$found" == "true" ]] || die "$cap does not provide $command"
  pkg_backend_path
  if real="$(lazy_real_command "$command")"; then
    exec "$real" "$@"
  fi
  if cap_skipped "$cap"; then
    err "$command is provided by capability $cap, which is skipped on this machine (TEEUP_SKIP)."
    exit 127
  fi
  if ! lazy_is_tty; then
    err "$command is not installed. It is provided by capability $cap; run: teeup install $cap"
    exit 127
  fi
  if ! ui_confirm "$command is provided by capability $cap. Install now?" yes; then
    err "Not installed. When you want it: teeup install $cap"
    exit 127
  fi
  cmd_install "$cap"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "Dry run: $command was not installed, so it was not run."
    exit 0
  fi
  if real="$(lazy_real_command "$command")"; then
    exec "$real" "$@"
  fi
  err "$cap is installed but $command is still not on PATH. Open a new terminal and try again."
  exit 127
}

cmd_has() {
```

The dispatch arm, just above `has)`:

```bash edit-old=bin/teeup
  has) cmd_has "$@" ;;
```

```bash edit-new=bin/teeup
  lazy-run) cmd_lazy_run "$@" ;;
  has) cmd_has "$@" ;;
```

- [ ] **Step 7: Keep the shims last and out of the `EDITOR` probe in `capabilities/zsh/default/env`** (two edits)

```bash edit-old=capabilities/zsh/default/env
path_append "$TEEUP_STATE_DIR/shims"
export PATH
```

```bash edit-new=capabilities/zsh/default/env
# Moved rather than only appended: path_append leaves an entry where an
# inherited PATH already had it, and a nested shell can inherit the shims
# ahead of a directory its parent's local.zsh appended.
path_remove "$TEEUP_STATE_DIR/shims"
path_append "$TEEUP_STATE_DIR/shims"
export PATH
```

```bash edit-old=capabilities/zsh/default/env
if [ -z "${EDITOR:-}" ]; then
  if command -v emacsclient >/dev/null 2>&1; then
    # An empty ALTERNATE_EDITOR makes emacsclient start the daemon itself.
    ALTERNATE_EDITOR=""
    export ALTERNATE_EDITOR
    EDITOR="emacsclient -t"
  elif command -v nvim >/dev/null 2>&1; then
    EDITOR="nvim"
  else
    EDITOR="vim"
  fi
  export EDITOR
fi
```

```bash edit-new=capabilities/zsh/default/env
# A lazy shim answers `command -v` for a command nothing installed provides
# (the neovim capability's provides="nvim"), so a hit inside the shims
# directory is not an editor. The shims are last on PATH, so a real nvim
# anywhere would have been found first.
_teeup_nvim="$(command -v nvim 2>/dev/null)"
case "$_teeup_nvim" in
  "$TEEUP_STATE_DIR/shims/"*) _teeup_nvim="" ;;
esac
if [ -z "${EDITOR:-}" ]; then
  if command -v emacsclient >/dev/null 2>&1; then
    # An empty ALTERNATE_EDITOR makes emacsclient start the daemon itself.
    ALTERNATE_EDITOR=""
    export ALTERNATE_EDITOR
    EDITOR="emacsclient -t"
  elif [ -n "$_teeup_nvim" ]; then
    EDITOR="nvim"
  else
    EDITOR="vim"
  fi
  export EDITOR
fi
unset _teeup_nvim
```

`emacsclient` needs no such guard: plan 3a's `emacs` is a daily capability with no `provides`, so no shim ever carries that name.

- [ ] **Step 8: Run the three suites**

Run: `bash tests/capabilities/teeup-runtime.sh && bash tests/cli.sh && bash tests/capabilities/zsh.sh`
Expected: `Summary: 9/9 passed`, `Summary: 22/22 passed` and `Summary: 23/23 passed`.

- [ ] **Step 9: Full checks and commit**

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning bin/teeup capabilities/teeup-runtime/configure tests/cli.sh tests/capabilities/teeup-runtime.sh tests/capabilities/zsh.sh
git diff --check
git add bin/teeup capabilities/teeup-runtime/configure capabilities/zsh/default/env tests/cli.sh tests/capabilities/teeup-runtime.sh tests/capabilities/zsh.sh
git commit -m "Generate lazy shims and add teeup lazy-run"
```

Expected: `All N suites passed.` where N is the suite count printed before this task (unchanged: no new suite file). `tests/bootstrap.sh` stays green: its dry run now also prints `Would write .../shims/<cmd>` lines for every lazy capability in the repo, and none of its assertions count lines of that shape.

---

### Task 4: `teeup launch`, `teeup install dev-env`, and lazy-aware `list` and `status`

**Files:**
- Modify: `bin/teeup`, `tests/cli.sh`

**Interfaces:**
- Consumes: `launch_resolve`, `cap_apps`, `app_installed`, `shims_dir` (Task 1); `dev_env_install`, `dev_env_installed` (Task 2); `cmd_install` (`bin/teeup`); `run_cmd`, `state_done`.
- Produces: `teeup launch <app|capability>`; `teeup install dev-env <lang>`; `cap_list_via <capability>` (the bracketed column `teeup list` prints for lazy rows: `[on first: <provides>]`, `[launch: <app>]`, `[on first: <provides>; launch: <app>]` when a capability has both, or `[teeup install <name>]`); `teeup status` prints `<name> installed (<tier>)` per installed capability, then `Lazy shims: <names>` (or `none (run: teeup configure teeup-runtime)`) and `Dev envs: <langs>` (or `none (teeup install dev-env <python|node|java|ruby|rust|go>)`); usage lines for `install dev-env` and `launch`. Tasks 5, 9 and 10 exercise `launch` and the shims line against real capabilities.

**Real-Mac risk:** `open -a <name>` resolves the app by its bundle's display name through Launch Services, not by the path `app_installed` checked, so a cask whose `app` artifact is named differently from what Launch Services registers (rare, but a renamed `.app` does it) would pass the installed check and then fail in `open` with `Unable to find application named`. Only hardware, per app, proves the two agree; every `apps=` value in this plan and in 3a is the `app` artifact name from the cask's Homebrew JSON (`Ollama.app`, `Cursor.app`, `Visual Studio Code.app`, `Google Chrome.app`, `Firefox Developer Edition.app`). An app moved somewhere other than `/Applications` or `~/Applications` is reported missing: `cask_install` logs `Already installed: <cask> (cask)` and `launch` stops with its "still not in" error rather than opening it.

- [ ] **Step 1: Write the failing tests in `tests/cli.sh`**

The list test learns the lazy column:

```bash edit-old=tests/cli.sh
  out="$("$TEEUP" list --tier lazy)"
  assert_contains "$out" "lazyone" || return 1
  assert_not_contains "$out" "alpha" || return 1
  cleanup_test_env
}
```

```bash edit-new=tests/cli.sh
  # A cask that also links a command, and a lazy capability with neither.
  make_cap zapper lazy "" "zap" "Zap App"
  make_cap plain lazy
  out="$("$TEEUP" list --tier lazy)"
  assert_contains "$out" "lazyone" || return 1
  assert_not_contains "$out" "alpha" || return 1
  # Lazy rows say how they are reached; core rows have no such column.
  assert_contains "$out" "[on first: frob]" || return 1
  assert_contains "$out" "[launch: Sketch Pad]" || return 1
  assert_contains "$out" "[on first: zap; launch: Zap App]" || return 1
  assert_contains "$out" "[teeup install plain]" || return 1
  out="$("$TEEUP" list --tier core)"
  assert_not_contains "$out" "[" || return 1
  cleanup_test_env
}
```

The status test learns the tier suffix and the two new lines:

```bash edit-old=tests/cli.sh
  assert_contains "$out" "Package manager: homebrew" || return 1
  assert_contains "$out" "Installed: 1 of 4" || return 1
  assert_contains "$out" "Answers: missing" || return 1
  cleanup_test_env
}
```

```bash edit-new=tests/cli.sh
  assert_contains "$out" "Package manager: homebrew" || return 1
  assert_contains "$out" "alpha              installed (core)" || return 1
  assert_contains "$out" "Installed: 1 of 4" || return 1
  assert_contains "$out" "Answers: missing" || return 1
  assert_contains "$out" "Lazy shims: none (run: teeup configure teeup-runtime)" || return 1
  assert_contains "$out" "Dev envs: none" || return 1
  # With shims in place and a dev-env marked, both lines list them.
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false shims_generate >/dev/null
  DRY_RUN=false state_done mark dev-env-go
  out="$("$TEEUP" status)"
  assert_contains "$out" "Lazy shims: frob" || return 1
  assert_contains "$out" "Dev envs: go" || return 1
  cleanup_test_env
}
```

The help test checks the two new usage lines:

```bash edit-old=tests/cli.sh
  assert_contains "$("$TEEUP" help)" "teeup lazy-run <cap> <cmd> [args]" || return 1
```

```bash edit-new=tests/cli.sh
  assert_contains "$("$TEEUP" help)" "teeup install dev-env <lang>" || return 1
  assert_contains "$("$TEEUP" help)" "teeup launch <app|capability>" || return 1
  assert_contains "$("$TEEUP" help)" "teeup lazy-run <cap> <cmd> [args]" || return 1
```

Six more tests above the `echo` line, and their registrations:

```bash edit-old=tests/cli.sh
echo "bin/teeup"
```

```bash edit-new=tests/cli.sh
test_launch_opens_an_installed_app_without_installing() {
  setup
  mock_command open 0 ""
  mkdir -p "$TEEUP_APPS_DIR/Sketch Pad.app"
  local out
  out="$("$TEEUP" launch "sketch pad")"
  assert_contains "$out" "Opening Sketch Pad" || return 1
  assert_not_contains "$out" "install:sketch" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "open -a Sketch Pad" || return 1
  # Unquoted, the way people type `teeup launch Google Chrome`.
  out="$("$TEEUP" launch Sketch Pad 2>&1)" || { echo "an unquoted app name must resolve: $out"; return 1; }
  assert_contains "$out" "Opening Sketch Pad" || return 1
  cleanup_test_env
}

test_launch_installs_the_capability_then_opens() {
  setup
  mock_command open 0 ""
  # The fixture's install "installs" the app by creating its bundle.
  printf '#!/usr/bin/env bash\necho "install:sketch"\nmkdir -p "$TEEUP_APPS_DIR/Sketch Pad.app"\n' > "$TEEUP_CAPS_DIR/sketch/install"
  local out
  out="$("$TEEUP" launch sketch)"
  assert_contains "$out" "Sketch Pad is not installed; installing sketch first." || return 1
  assert_contains "$out" "install:sketch" || return 1
  assert_contains "$out" "configure:sketch" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "open -a Sketch Pad" || return 1
  "$TEEUP" has sketch || { echo "sketch must be marked installed"; return 1; }
  cleanup_test_env
}

test_launch_fails_clearly_when_the_app_never_appears() {
  setup
  mock_command open 0 ""
  # What a MacPorts machine sees: cask_install warned and returned 0, so the
  # capability "succeeded" and the bundle is still missing.
  local rc=0 out
  out="$("$TEEUP" launch sketch 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Sketch Pad is still not in $TEEUP_APPS_DIR after installing sketch" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "open -a" || return 1
  cleanup_test_env
}

test_launch_dry_run_previews_the_open() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" launch sketch)"
  assert_contains "$out" "[DRY-RUN] Would execute: open -a Sketch Pad" || return 1
  cleanup_test_env
}

test_launch_unknown_app_and_skipped_capability() {
  setup
  local rc=0 out
  out="$("$TEEUP" launch "Nothing Here" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "No capability provides an app named 'Nothing Here'" || return 1
  rc=0
  out="$(TEEUP_SKIP=sketch "$TEEUP" launch sketch 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "sketch is skipped on this machine (TEEUP_SKIP); install Sketch Pad by hand." || return 1
  cleanup_test_env
}

test_install_dev_env_goes_through_mise() {
  setup
  mock_command_script mise <<'EOF2'
[ "$1" = "-C" ] && shift 2
case "$*" in
  "ls --global"*) : ;;
  "where "*) exit 1 ;;
  *) : ;;
esac
exit 0
EOF2
  local out
  out="$("$TEEUP" install dev-env go)"
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / use -g go@latest" || return 1
  assert_contains "$out" "go is ready" || return 1
  local rc=0
  out="$("$TEEUP" install dev-env cobol 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Usage: teeup install dev-env <python|node|java|ruby|rust|go>" || return 1
  cleanup_test_env
}

echo "bin/teeup"
```

```bash edit-old=tests/cli.sh
run_test "lazy-run rejects a command the capability does not provide" test_lazy_run_rejects_a_command_the_capability_does_not_provide
```

```bash edit-new=tests/cli.sh
run_test "lazy-run rejects a command the capability does not provide" test_lazy_run_rejects_a_command_the_capability_does_not_provide
run_test "launch opens an installed app without installing" test_launch_opens_an_installed_app_without_installing
run_test "launch installs the capability then opens" test_launch_installs_the_capability_then_opens
run_test "launch fails clearly when the app never appears" test_launch_fails_clearly_when_the_app_never_appears
run_test "launch dry run previews the open" test_launch_dry_run_previews_the_open
run_test "launch unknown app and skipped capability" test_launch_unknown_app_and_skipped_capability
run_test "install dev-env goes through mise" test_install_dev_env_goes_through_mise
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/cli.sh`
Expected: `list shows tier and summary`, `status reports backend and installed`, `help lists verbs`, the five `launch` tests and `install dev-env goes through mise` fail (`Unknown verb: launch`, `Unknown capability: dev-env`); `Summary: 19/28 passed`.

- [ ] **Step 3: Edit `bin/teeup`** (six edits)

Usage, the `dev-env` line after `install <capability>`:

```bash edit-old=bin/teeup
  teeup install <capability>     install and configure it (and what it requires)
  teeup install font <name>      install a Nerd Font and point every tool at it
```

```bash edit-new=bin/teeup
  teeup install <capability>     install and configure it (and what it requires)
  teeup install dev-env <lang>   python|node|java|ruby|rust|go through mise
  teeup install font <name>      install a Nerd Font and point every tool at it
```

Usage, the `launch` line above `lazy-run`:

```bash edit-old=bin/teeup
  teeup lazy-run <cap> <cmd> [args]  what a lazy shim runs: install <cap> on first use, then exec <cmd>
```

```bash edit-new=bin/teeup
  teeup launch <app|capability>  open a GUI app, installing its cask first if needed
  teeup lazy-run <cap> <cmd> [args]  what a lazy shim runs: install <cap> on first use, then exec <cmd>
```

`cmd_install` gets the `dev-env` switch right after the `font` one:

```bash edit-old=bin/teeup
    font_set "$*"
    return $?
  fi
  [[ -n "$target" ]] || die "Usage: teeup install <capability>"
```

```bash edit-new=bin/teeup
    font_set "$*"
    return $?
  fi
  # `dev-env` is not a capability either: runtimes come through mise and get
  # no shims (spec section 6), so they have their own switch.
  if [[ "$target" == "dev-env" ]]; then
    shift
    dev_env_install "${1:-}"
    return $?
  fi
  [[ -n "$target" ]] || die "Usage: teeup install <capability>"
```

`cmd_list` prints the lazy column through a new `cap_list_via`; replace the function's loop and add the helper after it:

```bash edit-old=bin/teeup
  for name in $(cap_list); do
    tier="$(cap_meta_get "$name" tier)"
    [[ -z "$tier_filter" || "$tier" == "$tier_filter" ]] || continue
    printf '%-18s %-6s %s\n' "$name" "$tier" "$(cap_meta_get "$name" summary)"
  done
}
```

```bash edit-new=bin/teeup
  for name in $(cap_list); do
    tier="$(cap_meta_get "$name" tier)"
    [[ -z "$tier_filter" || "$tier" == "$tier_filter" ]] || continue
    printf '%-18s %-6s %s%s\n' "$name" "$tier" "$(cap_meta_get "$name" summary)" "$(cap_list_via "$name")"
  done
}

# The lazy column: how a lazy capability is reached, since nothing installs
# it at bootstrap. Commands come from provides= (they have shims), an app
# from apps= (it has `teeup launch`); a capability can have both (a cask that
# links a command, like vscode's `code`), and one with neither is reached by
# `teeup install` alone.
cap_list_via() {
  local name="$1" tier provides app via=""
  tier="$(cap_meta_get "$name" tier)"
  [[ "$tier" == "lazy" ]] || return 0
  provides="$(cap_meta_get "$name" provides)"
  app="$(cap_apps "$name" | head -1)"
  [[ -z "$provides" ]] || via="on first: $provides"
  [[ -z "$app" ]] || via="${via:+$via; }launch: $app"
  printf '  [%s]' "${via:-teeup install $name}"
}
```

`cmd_launch`, placed just above `cmd_has` (after Task 3's `cmd_lazy_run`):

```bash edit-old=bin/teeup
cmd_has() {
```

```bash edit-new=bin/teeup
# `open -a` launches the app, or brings it to the front when it is already
# running, so one call covers Omarchy's launch-or-focus. A missing app means
# its capability's cask is not installed yet: install it, then open. The
# arguments are joined, so `teeup launch Google Chrome` needs no quotes. A
# GUI-only capability (apps= and no provides=, like 3a's chrome) is reached
# only this way and through `teeup install`.
cmd_launch() {
  local target="$*" cap app
  [[ -n "$target" ]] || die "Usage: teeup launch <app|capability>"
  cap="$(launch_resolve "$target")" || exit 1
  app="$(cap_apps "$cap" | head -1)"
  if app_installed "$app"; then
    log "Opening $app"
  else
    if cap_skipped "$cap"; then
      die "$cap is skipped on this machine (TEEUP_SKIP); install $app by hand."
    fi
    log "$app is not installed; installing $cap first."
    cmd_install "$cap"
    if [[ "$DRY_RUN" != "true" ]] && ! app_installed "$app"; then
      die "$app is still not in ${TEEUP_APPS_DIR:-/Applications} after installing $cap. On a MacPorts machine install it by hand, then run: teeup launch $target"
    fi
  fi
  run_cmd open -a "$app"
}

cmd_has() {
```

`cmd_status`, replaced whole:

```bash edit-old=bin/teeup
cmd_status() {
  local total=0 installed=0 name
  echo "teeup $(cat "$TEEUP_PATH/version" 2>/dev/null || echo dev) at $TEEUP_PATH"
  echo "Package manager: $(pkg_backend)"
  if answers_exist; then echo "Answers: $(answers_file)"; else echo "Answers: missing (run ./bootstrap)"; fi
  for name in $(cap_list); do
    total=$((total + 1))
    if state_done check "cap-$name"; then
      installed=$((installed + 1))
      printf '  %-18s installed\n' "$name"
    fi
  done
  echo "Installed: $installed of $total capabilities"
}
```

```bash edit-new=bin/teeup
cmd_status() {
  local total=0 installed=0 name tier shims="" f envs
  echo "teeup $(cat "$TEEUP_PATH/version" 2>/dev/null || echo dev) at $TEEUP_PATH"
  echo "Package manager: $(pkg_backend)"
  if answers_exist; then echo "Answers: $(answers_file)"; else echo "Answers: missing (run ./bootstrap)"; fi
  for name in $(cap_list); do
    total=$((total + 1))
    tier="$(cap_meta_get "$name" tier)"
    if state_done check "cap-$name"; then
      installed=$((installed + 1))
      printf '  %-18s installed (%s)\n' "$name" "$tier"
    fi
  done
  echo "Installed: $installed of $total capabilities"
  # What the lazy machinery has in place: the shims the shell will fall back
  # to, and the runtimes `teeup install dev-env` has set up.
  for f in "$(shims_dir)"/*; do
    [[ -x "$f" ]] || continue
    shims="$shims ${f##*/}"
  done
  echo "Lazy shims:${shims:- none (run: teeup configure teeup-runtime)}"
  envs="$(dev_env_installed | tr '\n' ' ')"
  echo "Dev envs: ${envs:-none (teeup install dev-env <python|node|java|ruby|rust|go>)}"
}
```

The dispatch arm, above `lazy-run)`:

```bash edit-old=bin/teeup
  lazy-run) cmd_lazy_run "$@" ;;
```

```bash edit-new=bin/teeup
  launch) cmd_launch "$@" ;;
  lazy-run) cmd_lazy_run "$@" ;;
```

- [ ] **Step 4: Run the suite**

Run: `bash tests/cli.sh`
Expected: `Summary: 28/28 passed`.

- [ ] **Step 5: Full checks and commit**

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning bin/teeup tests/cli.sh
git diff --check
git add bin/teeup tests/cli.sh
git commit -m "Add teeup launch, install dev-env and the lazy status lines"
```

Expected: `All N suites passed.` where N is the suite count printed before this task (unchanged).

---

### Task 5: `colima` capability and the shim round trip (the phase 3 gate)

**Files:**
- Create: `capabilities/colima/{capability,install,configure}`, `tests/capabilities/colima.sh`

**Interfaces:**
- Consumes: `pkg_install`, `pkg_backend`, `pkg_prefix` (`lib/pkg.sh`); `have`, `run_cmd`, `log`, `ok`, `warn` (`lib/core.sh`); `shims_generate` through `teeup configure teeup-runtime` (Task 3); `teeup lazy-run` (Task 3); `hide_host_commands` (Task 1).
- Produces: the `docker` and `colima` shims on every machine that runs `teeup configure teeup-runtime`; `${DOCKER_CONFIG:-~/.docker}/cli-plugins/docker-compose` on Homebrew machines; the `docker-compose-plugin` port on MacPorts machines; a running Colima after `teeup install colima`. The two round-trip tests are the spec's phase 3 gate: a terminal answer of `y` goes shim, `lazy-run`, install, configure, exec of the real `docker` with the original arguments; without a terminal the shim exits 127 with the hint and installs nothing.

**External facts (verified 2026-09-13):** Homebrew formulae `colima` 0.10.3 (depends on `lima`), `docker` 29.8.0 (the CLI, no runtime dependencies) and `docker-compose` 5.5.1, whose formula runs `(lib/"docker/cli-plugins").install_symlink bin/"docker-compose"` and whose caveat says "Compose is a Docker plugin. For Docker to find the plugin, add "cliPluginsExtraDirs" to ~/.docker/config.json"; there is no cask named `docker` (the Desktop app is `docker-desktop`). MacPorts ports `colima` 0.10.3, `docker` 29.8.0, `docker-compose` 1.29.2 (`python/docker-compose`, the Python v1 tool) and `docker-compose-plugin` 2.36.2 (`devel/docker-compose-plugin`: `go.setup github.com/docker/compose 2.36.2`, `depends_run port:docker`, installs `${prefix}/libexec/docker/cli-plugins/docker-compose`); the `docker` Portfile runs `reinplace s+/usr/lib+${prefix}/lib+g` on `cli-plugins/manager/manager_unix.go`. docker/cli v29.8.0 `cli-plugins/manager/manager.go` `getPluginDirs`: `cfg.CLIPluginsExtraDirs`, then `filepath.Join(config.Dir(), "cli-plugins")` (`$DOCKER_CONFIG`, default `~/.docker`), then `defaultSystemPluginDirs` = `/usr/local/lib/docker/cli-plugins`, `/usr/local/libexec/docker/cli-plugins`, `/usr/lib/docker/cli-plugins`, `/usr/libexec/docker/cli-plugins` (`manager_unix.go`; its doc comment lists the config directory first, the code puts the extra dirs first). Colima: `colima status` returns the error "`<profile>` is not running" from `getStatus` when the VM is stopped (`app/app.go`), which cobra turns into a non-zero exit; the FAQ says "Colima makes itself the default Docker context on startup"; the README says "Docker client is required for Docker runtime. Installable with `brew install docker`."

**Real-Mac risk:** the exit code of `colima status` was read from source, not observed. The first `colima start` downloads a VM image and takes minutes, and the shim's `docker ps` waits for it inside `run_logged` with no progress beyond colima's own output. Homebrew publishes `docker` and `docker-compose` bottles only for Apple Silicon macOS (`arm64_sonoma`, `arm64_sequoia`, `arm64_tahoe`, `arm64_golden_gate`), so an Intel Mac on Homebrew builds both from source with Go. On an old Intel Mac with MacPorts, `port install colima` pulls in lima and its VM driver, which nothing here can exercise; that `docker compose` finds the `docker-compose-plugin` port's binary through the patched system path was read from the two Portfiles, not observed, and the port trails Homebrew's Compose by several releases.

- [ ] **Step 1: Write the metadata**

```sh file=capabilities/colima/capability
summary="Colima container runtime with the Docker CLI and Compose"
group=containers
tier=lazy
requires="package-manager"
provides="docker colima"
packages="colima docker docker-compose"
casks=""
apps=""
interactive=false
```

- [ ] **Step 2: Write the failing test `tests/capabilities/colima.sh`**

```bash file=tests/capabilities/colima.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# The phase 3 gate: a shim round trip. `docker` is not on a fresh Mac, so on
# the harness PATH (MOCK_BIN, /usr/bin, /bin, /usr/sbin, /sbin) the shim is
# the only `docker` until the mocked brew "installs" a real one into
# REAL_BIN, a directory ahead of the shims on PATH the way /opt/homebrew/bin
# is. A Linux CI runner (and a developer's machine) can have docker in
# /usr/bin; hide_host_commands hides those copies by path, before any mock of
# the same name exists, so the mocked install is what provides them.
setup() {
  setup_test_env
  mock_macos_base
  hide_host_commands colima docker docker-compose
  REAL_BIN="$TEST_HOME/realbin"
  mkdir -p "$REAL_BIN"
  export REAL_BIN
  # brew install <formula> drops an executable of that name into REAL_BIN:
  # docker and docker-compose log their arguments and echo them; colima
  # keeps a stopped/running state behind `status` and `start`.
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "list "*) exit 1 ;;
  "install colima")
    printf '#!/usr/bin/env bash\necho "colima-real $*" >> "$MOCK_LOG"\ncase "$1" in\n  status) [ -f "$HOME/colima-running" ] || exit 1 ;;\n  start) touch "$HOME/colima-running" ;;\nesac\nexit 0\n' > "$REAL_BIN/colima"
    chmod +x "$REAL_BIN/colima"
    ;;
  "install "*)
    printf '#!/usr/bin/env bash\necho "%s-real $*" >> "$MOCK_LOG"\necho "%s ran: $*"\n' "$2" "$2" > "$REAL_BIN/$2"
    chmod +x "$REAL_BIN/$2"
    ;;
esac
exit 0
EOF2
  export TEEUP_NO_GUM=1
  TEEUP="$TEEUP_PATH/bin/teeup"
  SHIMS="$TEST_HOME/.local/state/teeup/shims"
}

# A colima already on PATH, stopped until `colima start` has been called.
mock_colima_stopped() {
  mock_command_script colima <<'EOF2'
case "$1" in
  status) [ -f "$HOME/colima-running" ] || exit 1 ;;
  start) touch "$HOME/colima-running" ;;
esac
exit 0
EOF2
}

test_install_dry_run_gets_colima_docker_and_compose() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install colima 2>&1)"
  assert_contains "$out" "Would execute: brew install colima" || return 1
  assert_contains "$out" "Would execute: brew install docker" || return 1
  assert_contains "$out" "Would execute: brew install docker-compose" || return 1
  # Nothing was really installed, so configure has no colima to start.
  assert_contains "$out" "colima is not installed; start it later with: colima start" || return 1
  cleanup_test_env
}

test_install_on_macports_gets_the_compose_plugin_port() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install colima 2>&1)"
  assert_contains "$out" "Would execute: sudo port install colima" || return 1
  assert_contains "$out" "Would execute: sudo port install docker" || return 1
  # The docker-compose port is the retired Python 1.x tool; the plugin port
  # is Compose v2.
  assert_contains "$out" "Would execute: sudo port install docker-compose-plugin" || return 1
  if printf '%s\n' "$out" | grep -q 'port install docker-compose$'; then
    echo "the Python docker-compose port must not be installed"; return 1
  fi
  cleanup_test_env
}

test_configure_links_the_compose_plugin_once() {
  setup
  mock_colima_stopped
  local plugin="$TEEUP_PKG_PREFIX/lib/docker/cli-plugins/docker-compose"
  mkdir -p "$(dirname "$plugin")"
  printf '#!/bin/sh\n' > "$plugin"
  chmod +x "$plugin"
  DRY_RUN=false "$TEEUP" configure colima >/dev/null
  assert_equals "$plugin" "$(readlink "$TEST_HOME/.docker/cli-plugins/docker-compose")" || return 1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure colima)"
  assert_contains "$out" "Already linked: $TEST_HOME/.docker/cli-plugins/docker-compose" || return 1
  cleanup_test_env
}

test_configure_starts_colima_only_when_stopped() {
  setup
  mock_colima_stopped
  DRY_RUN=false "$TEEUP" configure colima >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "colima start" || return 1
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure colima)"
  assert_contains "$out" "Colima is running." || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "colima start" || return 1
  cleanup_test_env
}

test_configure_honours_docker_config() {
  setup
  mock_colima_stopped
  local plugin="$TEEUP_PKG_PREFIX/lib/docker/cli-plugins/docker-compose"
  mkdir -p "$(dirname "$plugin")"
  printf '#!/bin/sh\n' > "$plugin"
  export DOCKER_CONFIG="$TEST_HOME/docker config"
  DRY_RUN=false "$TEEUP" configure colima >/dev/null
  assert_equals "$plugin" "$(readlink "$DOCKER_CONFIG/cli-plugins/docker-compose")" || return 1
  [[ ! -e "$TEST_HOME/.docker" ]] || { echo "DOCKER_CONFIG must replace ~/.docker"; return 1; }
  unset DOCKER_CONFIG
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  mock_colima_stopped
  local plugin="$TEEUP_PKG_PREFIX/lib/docker/cli-plugins/docker-compose"
  mkdir -p "$(dirname "$plugin")"
  printf '#!/bin/sh\n' > "$plugin"
  chmod +x "$plugin"
  local out
  out="$(DRY_RUN=true "$TEEUP" configure colima)"
  assert_contains "$out" "Would execute: colima start" || return 1
  [[ ! -e "$TEST_HOME/.docker" ]] || { echo "dry run wrote under ~/.docker"; return 1; }
  [[ ! -e "$TEST_HOME/colima-running" ]] || { echo "dry run started colima"; return 1; }
  cleanup_test_env
}

test_shims_exist_after_runtime_configure() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  assert_file_exists "$SHIMS/docker" || return 1
  assert_file_exists "$SHIMS/colima" || return 1
  [[ -x "$SHIMS/docker" ]] || { echo "docker shim must be executable"; return 1; }
  assert_contains "$(cat "$SHIMS/docker")" 'lazy-run colima docker "$@"' || return 1
  cleanup_test_env
}

test_round_trip_shim_installs_configures_and_execs_docker() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  # The shell's lookup, with real bin directories first and teeup's shims
  # last: before the install nothing but the shim answers to `docker`.
  # (/usr/bin is left out of this one lookup because a Linux runner has
  # docker there; `command -v` is a builtin and needs no PATH of its own.)
  assert_equals "$SHIMS/docker" "$(PATH="$MOCK_BIN:$REAL_BIN:$SHIMS" command -v docker)" || return 1
  # The PATH every command below runs with. The shim is named outright for
  # the same /usr/bin reason; hide_host_commands keeps teeup itself from
  # counting a host docker as installed.
  export PATH="$MOCK_BIN:$REAL_BIN:/usr/bin:/bin:/usr/sbin:/sbin:$SHIMS"
  local out
  out="$(printf 'y\n' | TEEUP_TEST_TTY=yes DRY_RUN=false "$SHIMS/docker" ps --all 2>&1)"
  assert_contains "$out" "docker is provided by capability colima. Install now?" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew install colima" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew install docker" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew install docker-compose" || return 1
  # configure ran after install and started the VM it had just installed.
  assert_contains "$(cat "$MOCK_LOG")" "colima-real start" || return 1
  assert_contains "$out" "Completed: colima configure" || return 1
  # The real docker ran, with the original arguments.
  assert_contains "$(cat "$MOCK_LOG")" "docker-real ps --all" || return 1
  assert_contains "$out" "docker ran: ps --all" || return 1
  "$TEEUP" has colima || { echo "colima must be marked installed"; return 1; }
  # After the install the same lookup finds the real docker ahead of the shim.
  assert_equals "$REAL_BIN/docker" "$(PATH="$MOCK_BIN:$REAL_BIN:$SHIMS" command -v docker)" || return 1
  # Second call through the shim: a real binary exists ahead of it now, so
  # lazy-run execs that at once, with nothing installed and nothing asked.
  : > "$MOCK_LOG"
  out="$(TEEUP_TEST_TTY=no "$SHIMS/docker" images 2>&1)"
  assert_equals "docker ran: images" "$out" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew" || return 1
  cleanup_test_env
}

test_round_trip_without_a_tty_exits_127_with_the_hint() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  export PATH="$MOCK_BIN:$REAL_BIN:/usr/bin:/bin:/usr/sbin:/sbin:$SHIMS"
  local rc=0 out
  out="$(TEEUP_TEST_TTY=no "$SHIMS/docker" ps 2>&1)" || rc=$?
  assert_equals "127" "$rc" || return 1
  assert_contains "$out" "docker is not installed. It is provided by capability colima; run: teeup install colima" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew install" || return 1
  cleanup_test_env
}

echo "capabilities/colima"
run_test "install dry run gets colima, docker and compose" test_install_dry_run_gets_colima_docker_and_compose
run_test "install on macports gets the compose plugin port" test_install_on_macports_gets_the_compose_plugin_port
run_test "configure links the compose plugin once" test_configure_links_the_compose_plugin_once
run_test "configure starts colima only when stopped" test_configure_starts_colima_only_when_stopped
run_test "configure honours DOCKER_CONFIG" test_configure_honours_docker_config
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "shims exist after runtime configure" test_shims_exist_after_runtime_configure
run_test "round trip: shim installs, configures and execs docker" test_round_trip_shim_installs_configures_and_execs_docker
run_test "round trip: without a tty exits 127 with the hint" test_round_trip_without_a_tty_exits_127_with_the_hint
print_summary
```

- [ ] **Step 3: Run it to see it fail**

Run: `bash tests/capabilities/colima.sh`
Expected: the install, configure and round-trip tests fail (`colima has no install script`, `colima has no configure script`); `shims exist after runtime configure` and `round trip: without a tty exits 127 with the hint` already pass, because the metadata alone drives shim generation and the no-terminal path of `lazy-run` never reaches the capability's scripts; `Summary: 2/9 passed`.

- [ ] **Step 4: Write `capabilities/colima/install`**

```bash file=capabilities/colima/install
#!/usr/bin/env bash
# Colima runs the Linux VM; the docker formula/port is the CLI only (no
# Docker Desktop). Compose v2 is a docker CLI plugin: Homebrew's
# docker-compose formula ships it under lib/docker/cli-plugins (configure
# links it where docker looks), while MacPorts' docker-compose port is the
# retired Python 1.x tool and the plugin is the docker-compose-plugin port.
pkg_install colima colima
pkg_install docker docker
if [[ "$(pkg_backend)" == "homebrew" ]]; then
  pkg_install docker-compose docker-compose
else
  pkg_install docker-compose-plugin
fi
```

- [ ] **Step 5: Write `capabilities/colima/configure`**

```bash file=capabilities/colima/configure
#!/usr/bin/env bash
# docker looks for CLI plugins in the cli-plugins directory of its config
# directory ($DOCKER_CONFIG, default ~/.docker) before its fixed system
# directories (docker/cli, cli-plugins/manager). Homebrew's docker-compose
# formula puts the Compose plugin in $(brew --prefix)/lib/docker/cli-plugins,
# which is not one of them, so link it into the user directory: `docker
# compose` then works with no ~/.docker/config.json edit. MacPorts needs
# nothing here: its docker port rewrites the system plugin paths to
# /opt/local, where the docker-compose-plugin port installs.
if [[ "$(pkg_backend)" == "homebrew" ]]; then
  plugin="$(pkg_prefix)/lib/docker/cli-plugins/docker-compose"
  plugins_dir="${DOCKER_CONFIG:-$HOME/.docker}/cli-plugins"
  link="$plugins_dir/docker-compose"
  if [[ ! -e "$plugin" ]]; then
    log "No Compose plugin at $plugin; docker compose stays unavailable until docker-compose is installed."
  elif [[ "$(readlink "$link" 2>/dev/null)" == "$plugin" ]]; then
    log "Already linked: $link"
  else
    [[ -d "$plugins_dir" ]] || run_cmd mkdir -p "$plugins_dir"
    run_cmd ln -sfn "$plugin" "$link"
    ok "Linked the docker compose plugin at $link"
  fi
fi

# Start the VM once, so the `docker ps` that went through the shim has a
# daemon to talk to. `colima status` returns an error ("colima is not
# running", exit 1) while it is stopped, so starting is idempotent. Colima
# makes itself the default docker context on start; `colima start --edit`
# changes CPU, memory and disk later.
if ! have colima; then
  warn "colima is not installed; start it later with: colima start"
  exit 0
fi
if colima status >/dev/null 2>&1; then
  log "Colima is running."
else
  run_cmd colima start || warn "Colima did not start; run: colima start"
fi
```

- [ ] **Step 6: Make both executable and run the suite**

Run: `chmod +x capabilities/colima/install capabilities/colima/configure && bash tests/capabilities/colima.sh`
Expected: `Summary: 9/9 passed`. The round trip's output contains, in order, `docker is provided by capability colima. Install now?`, `Starting: colima install`, `Completed: colima configure`, then `docker ran: ps --all`.

- [ ] **Step 7: Full checks and commit**

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning capabilities/colima/install capabilities/colima/configure tests/capabilities/colima.sh
git diff --check
git add capabilities/colima tests/capabilities/colima.sh
git commit -m "Add the colima capability with the shim round-trip test"
```

Expected: `All N suites passed.` where N is the suite count printed before this task, plus 1. `./bin/teeup list --tier lazy` now shows `colima ... [on first: docker colima]`.

---

### Task 6: `ai` capability (mise wrappers for the AI CLIs)

**Files:**
- Create: `capabilities/ai/{capability,install,configure}`, `tests/capabilities/ai.sh`

**Interfaces:**
- Consumes: `mise_wrapper_write <command> <tool> [runtime...]` and `TEEUP_MISE_WRAPPER_MARKER` (Task 2); `have`, `log`, `warn`.
- Produces: `~/.local/bin/{claude,codex,gemini,copilot,opencode}`, where `gemini` also loads `node`; an existing non-teeup file at any of those paths is kept. `provides="claude codex gemini copilot opencode"` also puts a shim for each of the five in `$TEEUP_STATE_DIR/shims` (Task 1's `shims_generate`, run from `teeup-runtime configure`): on a freshly bootstrapped Mac, typing `claude` before anyone has run `teeup install ai` or `teeup configure ai` still reaches it, through the shim, `lazy-run ai claude`, the capability's install and configure, and the wrapper it writes. None of the five names is in `TEEUP_SHIM_FORBIDDEN` or in another capability's `provides=`.

**External facts (verified 2026-09-13):** `mise registry` on 2026.9.4: `claude` -> `aqua:anthropics/claude-code http:claude`, `codex` -> `aqua:openai/codex npm:@openai/codex`, `gemini` and `gemini-cli` -> `npm:@google/gemini-cli`, `copilot` -> `aqua:github/copilot-cli github:github/copilot-cli npm:@github/copilot`, `opencode` -> `aqua:anomalyco/opencode`, `node` -> `core:node`. Upstream `jdx/mise` `main` has the same backends in `registry/claude.toml` (alias `claude-code`), `registry/codex.toml`, `registry/gemini-cli.toml` (alias `gemini`), `registry/copilot.toml` (alias `copilot-cli`) and `registry/opencode.toml`. `MISE_MINIMUM_RELEASE_AGE=0 mise settings get minimum_release_age` prints `0`, so the environment form is recognised. mise's npm backend docs (`docs/dev-tools/backends/npm.md` at v2026.9.4): packages install with mise's embedded package manager "without needing node", but "an installed package may still require `node` at runtime" and "the npm backend does not add or install `node` automatically" (reworded on `main` to "The installed CLI may still need Node.js ... does not add it to your project automatically"). Omarchy (`basecamp/omarchy`, default branch `quattro`): `install/user/mise.sh` runs `omarchy-mise-install` for `codex`, `claude`, `copilot` and `opencode` among others (Gemini is no longer in that list), and `bin/omarchy-mise-install` writes a wrapper that exports `MISE_MINIMUM_RELEASE_AGE=0`, runs `mise use -g --quiet` and ends `exec mise x ... -- ... "$@"`; the same `mise.sh` sets `mise settings set upgrade.auto_prune false`. Claude Code's setup docs: "the native installer manages the launcher at `~/.local/bin/claude` as a symlink into `~/.local/share/claude/versions/`".

**Real-Mac risk:** the aqua backend downloads GitHub release assets; behind a proxy that blocks GitHub the first `claude` call fails inside mise, and the wrapper's `|| exit 1` surfaces mise's own message. `mise upgrade` moving a `latest` tool forward while a session of it is running has not been observed: mise 2026.9.4's `upgrade.auto_prune` (default `true`) schedules the old version for removal after `upgrade.prune_after`, a grace period for running processes, while Omarchy turns pruning off altogether; teeup leaves the user's mise settings alone. On a Mac that already has Claude Code from its native installer, `teeup configure ai` keeps that `claude` and says so; only a real machine shows whether users then expect the mise one.

- [ ] **Step 1: Write the metadata**

```sh file=capabilities/ai/capability
summary="AI coding CLIs: claude, codex, gemini, copilot, opencode through mise"
group=ai
tier=lazy
requires="mise"
provides="claude codex gemini copilot opencode"
packages=""
casks=""
apps=""
interactive=false
```

`provides=` is what puts a shim for each of the five commands in `$TEEUP_STATE_DIR/shims` (Task 1). Without it nothing runs `ai`'s configure until a user already knows to type `teeup install ai`; on a freshly bootstrapped Mac `claude` would be "command not found". None of the five is in `TEEUP_SHIM_FORBIDDEN` (`python3 ruby java git perl`) or provided by another capability in this plan or 3a's.

- [ ] **Step 2: Write the failing test `tests/capabilities/ai.sh`**

```bash file=tests/capabilities/ai.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  # A mise that knows nothing is installed until `use -g` says so, and whose
  # `x` echoes the tools it would load and the command it would run.
  mock_command_script mise <<'EOF2'
[ "$1" = "-C" ] && shift 2
case "$*" in
  "ls --global"*) : ;;
  "where "*) grep -qx "$2" "$HOME/mise-installed" 2>/dev/null || exit 1 ;;
  "use "*)
    shift
    while [ $# -gt 0 ]; do case "$1" in -g|--quiet) shift ;; *) break ;; esac; done
    printf '%s\n' "${1%%@*}" >> "$HOME/mise-installed"
    ;;
  "x "*)
    shift
    tools=""
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do tools="$tools${tools:+,}$1"; shift; done
    shift
    echo "mise-x:$tools:$*"
    ;;
  *) : ;;
esac
exit 0
EOF2
  # The last test drives the shim's install prompt through ui_confirm; keep
  # it away from gum (a host gum on the narrowed PATH would otherwise answer
  # for real and never print the line this test asserts on).
  export TEEUP_NO_GUM=1
  TEEUP="$TEEUP_PATH/bin/teeup"
  BIN="$TEST_HOME/.local/bin"
  SHIMS="$TEST_HOME/.local/state/teeup/shims"
}

test_install_downloads_nothing() {
  setup
  local out c
  out="$(DRY_RUN=true "$TEEUP" install ai 2>&1)"
  assert_contains "$out" "AI CLIs install on first call through mise; nothing to download now." || return 1
  # The requires= chain runs the mise capability (which asks mise about
  # pre-commit); none of the five CLIs is touched.
  for c in claude codex gemini copilot opencode; do
    assert_not_contains "$(cat "$MOCK_LOG")" "$c" || return 1
  done
  cleanup_test_env
}

test_configure_writes_the_five_wrappers() {
  setup
  DRY_RUN=false "$TEEUP" configure ai >/dev/null
  local c
  for c in claude codex copilot opencode; do
    assert_file_exists "$BIN/$c" || return 1
    [[ -x "$BIN/$c" ]] || { echo "$c wrapper must be executable"; return 1; }
    assert_contains "$(cat "$BIN/$c")" "for teeup_tool in $c; do" || return 1
    assert_contains "$(cat "$BIN/$c")" "exec mise x $c -- $c \"\$@\"" || return 1
  done
  # gemini is an npm package and runs on Node, so its wrapper brings node;
  # the mise tool is the registry's canonical gemini-cli.
  assert_contains "$(cat "$BIN/gemini")" "for teeup_tool in node gemini-cli; do" || return 1
  assert_contains "$(cat "$BIN/gemini")" "exec mise x node gemini-cli -- gemini \"\$@\"" || return 1
  cleanup_test_env
}

test_wrapper_installs_on_first_call_then_execs() {
  setup
  DRY_RUN=false "$TEEUP" configure ai >/dev/null
  local out
  out="$("$BIN/claude" --version)"
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / use -g --quiet claude" || return 1
  assert_equals "mise-x:claude:claude --version" "$out" || return 1
  : > "$MOCK_LOG"
  out="$("$BIN/claude" -p "say hi")"
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  assert_equals "mise-x:claude:claude -p say hi" "$out" || return 1
  cleanup_test_env
}

test_configure_keeps_a_native_claude() {
  setup
  mkdir -p "$BIN" "$TEST_HOME/.local/share/claude/versions"
  printf '#!/bin/sh\necho native\n' > "$TEST_HOME/.local/share/claude/versions/2.1.0"
  chmod +x "$TEST_HOME/.local/share/claude/versions/2.1.0"
  ln -s "$TEST_HOME/.local/share/claude/versions/2.1.0" "$BIN/claude"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ai 2>&1)"
  assert_contains "$out" "Keeping $BIN/claude: it was not written by teeup" || return 1
  assert_equals "native" "$("$BIN/claude")" || return 1
  assert_file_exists "$BIN/codex" || return 1
  cleanup_test_env
}

test_configure_is_idempotent_and_dry_run_safe() {
  setup
  DRY_RUN=false "$TEEUP" configure ai >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ai)"
  assert_contains "$out" "Already current: $BIN/opencode" || return 1
  cleanup_test_env
  setup
  out="$(DRY_RUN=true "$TEEUP" configure ai)"
  assert_contains "$out" "Would write $BIN/claude" || return 1
  [[ ! -e "$BIN/claude" ]] || { echo "dry run wrote a wrapper"; return 1; }
  cleanup_test_env
}

test_wrappers_survive_a_home_with_spaces() {
  setup
  export HOME="$TEST_HOME/home with spaces"
  mkdir -p "$HOME"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_STATE_HOME="$HOME/.local/state"
  DRY_RUN=false "$TEEUP" configure ai >/dev/null
  local out
  out="$("$HOME/.local/bin/gemini" chat)"
  assert_equals "mise-x:node,gemini-cli:gemini chat" "$out" || return 1
  cleanup_test_env
}

# The freshly-bootstrapped-Mac path: nobody has run `teeup install ai` or
# `teeup configure ai` yet, and `claude` still works, through the shim
# provides= now puts in place.
test_the_claude_shim_installs_ai_then_execs_through_mise() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  assert_file_exists "$SHIMS/claude" || return 1
  assert_contains "$(cat "$SHIMS/claude")" 'lazy-run ai claude "$@"' || return 1
  export PATH="$MOCK_BIN:/usr/bin:/bin:$BIN:$SHIMS"
  # A gum binary on PATH (MOCK_BIN, ahead of the shims, the way a real
  # /opt/homebrew/bin/gum would be) must not be touched: TEEUP_NO_GUM=1
  # (set in setup) short-circuits _ui_gum before it ever checks `have gum`,
  # so the plain read fallback below is what answers the prompt even on a
  # machine that has gum installed.
  mock_command_script gum <<'EOF2'
echo "gum must not run when TEEUP_NO_GUM=1" >&2
exit 1
EOF2
  local out
  out="$(printf 'y\n' | TEEUP_TEST_TTY=yes DRY_RUN=false "$SHIMS/claude" --version 2>&1)"
  assert_contains "$out" "claude is provided by capability ai. Install now?" || return 1
  assert_contains "$out" "mise-x:claude:claude --version" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "gum " "gum ran even though TEEUP_NO_GUM=1" || return 1
  assert_file_exists "$BIN/claude" || return 1
  "$TEEUP" has ai || { echo "ai must be marked installed"; return 1; }
  cleanup_test_env
}

echo "capabilities/ai"
run_test "install downloads nothing" test_install_downloads_nothing
run_test "configure writes the five wrappers" test_configure_writes_the_five_wrappers
run_test "wrapper installs on first call then execs" test_wrapper_installs_on_first_call_then_execs
run_test "configure keeps a native claude" test_configure_keeps_a_native_claude
run_test "configure is idempotent and dry-run safe" test_configure_is_idempotent_and_dry_run_safe
run_test "wrappers survive a home with spaces" test_wrappers_survive_a_home_with_spaces
run_test "the claude shim installs ai then execs through mise" test_the_claude_shim_installs_ai_then_execs_through_mise
print_summary
```

- [ ] **Step 3: Run it to see it fail**

Run: `bash tests/capabilities/ai.sh`
Expected: every test fails (`ai has no install script`, `ai has no configure script`); `Summary: 0/7 passed`.

- [ ] **Step 4: Write `capabilities/ai/install`**

```bash file=capabilities/ai/install
#!/usr/bin/env bash
# Nothing to download here. Each CLI installs itself through mise the first
# time its wrapper is called (configure writes the wrappers), so a machine
# that never runs `claude` never fetches it. mise itself is the requires=.
if have mise; then
  log "AI CLIs install on first call through mise; nothing to download now."
else
  warn "mise is not installed; the wrappers will fail until it is (teeup install mise)."
fi
```

- [ ] **Step 5: Write `capabilities/ai/configure`**

```bash file=capabilities/ai/configure
#!/usr/bin/env bash
# One wrapper per CLI in ~/.local/bin, which the zsh layer puts first on
# PATH (Omarchy's omarchy-mise-install pattern, lib/mise.sh): the first call
# installs the tool through mise, every later call execs it through `mise x`,
# and `mise upgrade` keeps it current. Arguments are the command, the mise
# registry name, then any runtime the tool needs. Registry names checked with
# `mise registry` on 2026.9.4: claude -> aqua:anthropics/claude-code,
# codex -> aqua:openai/codex, gemini-cli (alias gemini) ->
# npm:@google/gemini-cli, copilot -> aqua:github/copilot-cli,
# opencode -> aqua:anomalyco/opencode.
# gemini-cli is the one npm package: mise's npm backend installs it without
# Node but does not add Node, and the CLI runs on Node, so its wrapper brings
# node.
mise_wrapper_write claude claude
mise_wrapper_write codex codex
mise_wrapper_write gemini gemini-cli node
mise_wrapper_write copilot copilot
mise_wrapper_write opencode opencode
log "The first call of claude, codex, gemini, copilot or opencode installs it through mise."
```

- [ ] **Step 6: Make both executable and run the suite**

Run: `chmod +x capabilities/ai/install capabilities/ai/configure && bash tests/capabilities/ai.sh`
Expected: `Summary: 7/7 passed`.

- [ ] **Step 7: Full checks and commit**

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning capabilities/ai/install capabilities/ai/configure tests/capabilities/ai.sh
git diff --check
git add capabilities/ai tests/capabilities/ai.sh
git commit -m "Add the ai capability with mise-backed wrappers"
```

Expected: `All N suites passed.` where N is the suite count printed before this task, plus 1.

---

### Task 7: `herdr` capability

**Files:**
- Create: `capabilities/herdr/{capability,install,configure}`, `tests/capabilities/herdr.sh`

**Interfaces:**
- Consumes: `pkg_install`, `log`.
- Produces: the `herdr` shim; `teeup install herdr`.

**External facts (verified 2026-09-13):** `gh api repos/herdrdev/herdr/releases/latest` -> `v0.9.0` with assets `herdr-linux-aarch64`, `herdr-linux-x86_64`, `herdr-macos-aarch64`, `herdr-macos-x86_64`, `herdr-windows-x86_64.zip`; Homebrew formula `herdr` 0.9.0 ("Agent multiplexer that lives in your terminal") with `arm64_sonoma`, `arm64_sequoia` and `arm64_tahoe` bottles and build dependencies `rust` and `zig@0.15`; MacPorts port `herdr` 0.8.2; the README says "`brew install herdr` · `mise use -g herdr`" and "`ctrl+b q` detaches, `herdr` reattaches"; herdr.dev/docs/configuration gives "macOS: ~/.config/herdr/config.toml" and says herdr works without a config file; `mise registry` lists `herdr` -> `aqua:herdrdev/herdr github:herdrdev/herdr`. The spec's phase 3 check ("verify Herdr macOS availability") therefore keeps the capability.

**Real-Mac risk:** the Homebrew formula has no Intel macOS bottle, so on an Intel Mac `brew install herdr` compiles it with Rust and Zig, which Homebrew installs as build dependencies and which takes minutes; `pkg_install` shows that as one long quiet step. The MacPorts port trails the release by one minor version.

- [ ] **Step 1: Write the metadata**

```sh file=capabilities/herdr/capability
summary="Herdr, the agent multiplexer that lives in your terminal"
group=ai
tier=lazy
requires="package-manager"
provides="herdr"
packages="herdr"
casks=""
apps=""
interactive=false
```

- [ ] **Step 2: Write the failing test `tests/capabilities/herdr.sh`**

```bash file=tests/capabilities/herdr.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  # The host may ship herdr; the install tests only preview.
  export TEEUP_TEST_MISSING="herdr"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_gets_the_formula() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install herdr)"
  assert_contains "$out" "Would execute: brew install herdr" || return 1
  cleanup_test_env
}

test_install_uses_the_port_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install herdr)"
  assert_contains "$out" "Would execute: sudo port install herdr" || return 1
  cleanup_test_env
}

test_shim_is_generated_for_herdr() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  assert_file_exists "$TEST_HOME/.local/state/teeup/shims/herdr" || return 1
  cleanup_test_env
}

echo "capabilities/herdr"
run_test "install gets the formula" test_install_gets_the_formula
run_test "install uses the port on macports" test_install_uses_the_port_on_macports
run_test "shim is generated for herdr" test_shim_is_generated_for_herdr
print_summary
```

- [ ] **Step 3: Run it to see it fail**

Run: `bash tests/capabilities/herdr.sh`
Expected: `herdr has no install script`; `Summary: 1/3 passed` (the shim test passes from the metadata alone).

- [ ] **Step 4: Write `capabilities/herdr/install` and `configure`**

```bash file=capabilities/herdr/install
#!/usr/bin/env bash
# Herdr ships macOS builds (herdr-macos-aarch64 and herdr-macos-x86_64 on
# every GitHub release), a Homebrew formula and a MacPorts port, both named
# herdr, so the package manager is the whole install.
pkg_install herdr herdr
```

```bash file=capabilities/herdr/configure
#!/usr/bin/env bash
# Herdr runs without a config file; ~/.config/herdr/config.toml is where one
# goes when you want to change it. teeup ships no opinion about it yet.
log "Start herdr in a project directory; ctrl+b q detaches and herdr reattaches."
```

- [ ] **Step 5: Make both executable and run the suite**

Run: `chmod +x capabilities/herdr/install capabilities/herdr/configure && bash tests/capabilities/herdr.sh`
Expected: `Summary: 3/3 passed`.

- [ ] **Step 6: Full checks and commit**

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning capabilities/herdr/install capabilities/herdr/configure tests/capabilities/herdr.sh
git diff --check
git add capabilities/herdr tests/capabilities/herdr.sh
git commit -m "Add the herdr capability"
```

Expected: `All N suites passed.` where N is the suite count printed before this task, plus 1.

---

### Task 8: `tmux` capability

**Files:**
- Create: `capabilities/tmux/{capability,install,configure}`, `capabilities/tmux/config/tmux/tmux.conf`, `tests/capabilities/tmux.sh`

**Interfaces:**
- Consumes: `pkg_install`, `copy_config_once`, `user_config_dir`, `log`.
- Produces: the `tmux` shim; `~/.config/tmux/tmux.conf`, user-owned after the copy.

**External facts (verified 2026-09-13):** Homebrew formula `tmux` 3.7c; MacPorts port `tmux` 3.7c. tmux's CHANGES: "Add ~/.config/tmux/tmux.conf to the default search path for configuration files" (3.0a to 3.1), "Try $XDG_CONFIG_HOME/tmux/tmux.conf as well as ~/.config/tmux/tmux.conf" (3.1c to 3.2), "a new terminal-features option" (3.2), and "When building, pick default-terminal from the first of tmux-256color, tmux, screen-256color, screen that is available on the build system" (3.2a to 3.3). The search path is `TMUX_CONF` in `Makefile.am`, `"$(sysconfdir)/tmux.conf:~/.tmux.conf:$$XDG_CONFIG_HOME/tmux/tmux.conf:~/.config/tmux/tmux.conf"`, and `start_cfg` in `cfg.c` (tag 3.7c) runs `load_cfg` for every entry (`for (i = 0; i < cfg_nfiles; i++)`), quietly skipping missing files; `expand_paths` in `tmux.c` drops duplicates, so `XDG_CONFIG_HOME=~/.config` loads the file once. `tmux.1`'s summary ("looks for a user configuration file at ~/.tmux.conf or $XDG_CONFIG_HOME/tmux/tmux.conf") reads as either-or, and the code is what decides. The shipped `tmux.conf` was loaded with `tmux -f` on tmux 3.7c (Linux): no parse messages, `prefix` `C-a`, `base-index` `1`, `default-terminal` `tmux-256color`, and the `|` and `r` bindings as written. Every option in the shipped config (`prefix`, `mouse`, `history-limit`, `base-index`, `pane-base-index`, `renumber-windows`, `terminal-features`, `send-prefix`, `split-window -h/-v -c`, `source-file`, `display-message`, the `pane_current_path` format) appears in the current `tmux.1`. The dotfiles repo's `dot_tmux.conf` holds the C-a prefix and an optional tmux-themepack source; the prefix is ported, the theme-pack line is not.

**Real-Mac risk:** the config leaves `default-terminal` to the build. Homebrew's tmux links its own `ncurses` (a formula dependency), so it should pick `tmux-256color`; a program inside tmux that reads the system terminfo instead of Homebrew's may not find that entry. Only a real terminal session shows whether anything the user runs complains. That both `~/.tmux.conf` and `~/.config/tmux/tmux.conf` load, the XDG file last, was read from the 3.7c source and observed with tmux 3.7c on Linux (a `history-limit` set in each came out as the XDG file's value), not on macOS. The reload key names `~/.config/tmux/tmux.conf`, so with a non-default `XDG_CONFIG_HOME` it reports a missing file until edited.

- [ ] **Step 1: Write the metadata and the config**

```sh file=capabilities/tmux/capability
summary="tmux terminal multiplexer"
group=shell
tier=lazy
requires="package-manager"
provides="tmux"
packages="tmux"
casks=""
apps=""
interactive=false
```

```text file=capabilities/tmux/config/tmux/tmux.conf
# ~/.config/tmux/tmux.conf - installed once by teeup; this copy is yours.
# tmux 3.1 and newer read this path. tmux also reads ~/.tmux.conf, before this
# file, when one exists; teeup does not install this copy next to one.

# C-a as the prefix, ported from the previous dotfiles.
unbind C-b
set-option -g prefix C-a
bind-key C-a send-prefix

set -g mouse on
set -g history-limit 50000
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
# WezTerm reports TERM=xterm-256color and draws 24-bit colour.
set -as terminal-features ",xterm-256color:RGB"

# Splits that keep the current directory, and a reload key.
bind '|' split-window -h -c "#{pane_current_path}"
bind '-' split-window -v -c "#{pane_current_path}"
bind r source-file ~/.config/tmux/tmux.conf \; display-message "tmux.conf reloaded"
```

- [ ] **Step 2: Write the failing test `tests/capabilities/tmux.sh`**

```bash file=tests/capabilities/tmux.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  # The host may ship tmux; the install tests only preview.
  export TEEUP_TEST_MISSING="tmux"
  TEEUP="$TEEUP_PATH/bin/teeup"
  CONF="$TEST_HOME/.config/tmux/tmux.conf"
}

test_install_gets_tmux() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install tmux)"
  assert_contains "$out" "Would execute: brew install tmux" || return 1
  cleanup_test_env
}

test_configure_installs_the_config_once() {
  setup
  DRY_RUN=false "$TEEUP" configure tmux >/dev/null
  assert_file_exists "$CONF" || return 1
  assert_contains "$(cat "$CONF")" "set-option -g prefix C-a" || return 1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure tmux)"
  assert_contains "$out" "Already installed: $CONF" || return 1
  cleanup_test_env
}

test_configure_leaves_an_existing_home_config_alone() {
  setup
  printf 'set -g mouse on\n' > "$TEST_HOME/.tmux.conf"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure tmux)"
  assert_contains "$out" "Keeping your $TEST_HOME/.tmux.conf" || return 1
  # tmux loads both files, the XDG one last, so a second copy would
  # override the user's own settings.
  [[ ! -e "$CONF" ]] || { echo "no second config next to ~/.tmux.conf"; return 1; }
  assert_equals "set -g mouse on" "$(cat "$TEST_HOME/.tmux.conf")" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" configure tmux)"
  assert_contains "$out" "Would install $CONF" || return 1
  [[ ! -e "$CONF" ]] || { echo "written in dry run"; return 1; }
  cleanup_test_env
}

test_shim_is_generated_for_tmux() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  assert_file_exists "$TEST_HOME/.local/state/teeup/shims/tmux" || return 1
  cleanup_test_env
}

echo "capabilities/tmux"
run_test "install gets tmux" test_install_gets_tmux
run_test "configure installs the config once" test_configure_installs_the_config_once
run_test "configure leaves an existing home config alone" test_configure_leaves_an_existing_home_config_alone
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "shim is generated for tmux" test_shim_is_generated_for_tmux
print_summary
```

- [ ] **Step 3: Run it to see it fail**

Run: `bash tests/capabilities/tmux.sh`
Expected: `tmux has no install script` / `tmux has no configure script`; `Summary: 1/5 passed` (the shim test passes from the metadata alone).

- [ ] **Step 4: Write `capabilities/tmux/install` and `configure`**

```bash file=capabilities/tmux/install
#!/usr/bin/env bash
pkg_install tmux tmux
```

```bash file=capabilities/tmux/configure
#!/usr/bin/env bash
# tmux 3.1 and newer read ~/.config/tmux/tmux.conf (or
# $XDG_CONFIG_HOME/tmux/tmux.conf) on their own, so the config lives with the
# rest of ~/.config. tmux loads every config file it finds, ~/.tmux.conf
# first, so a copy next to an existing ~/.tmux.conf would silently override
# it; in that case nothing is installed.
if [[ -e "$HOME/.tmux.conf" || -L "$HOME/.tmux.conf" ]]; then
  log "Keeping your $HOME/.tmux.conf; not adding $(user_config_dir)/tmux/tmux.conf, which tmux would load after it."
else
  copy_config_once "$TEEUP_CAP_DIR/config/tmux/tmux.conf" "$(user_config_dir)/tmux/tmux.conf"
fi
```

- [ ] **Step 5: Make both executable and run the suite**

Run: `chmod +x capabilities/tmux/install capabilities/tmux/configure && bash tests/capabilities/tmux.sh`
Expected: `Summary: 5/5 passed`.

- [ ] **Step 6: Full checks and commit**

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning capabilities/tmux/install capabilities/tmux/configure tests/capabilities/tmux.sh
git diff --check
git add capabilities/tmux tests/capabilities/tmux.sh
git commit -m "Add the tmux capability"
```

Expected: `All N suites passed.` where N is the suite count printed before this task, plus 1.

---

### Task 9: `ollama` capability

**Files:**
- Create: `capabilities/ollama/{capability,install,configure}`, `tests/capabilities/ollama.sh`

**Interfaces:**
- Consumes: `casks_supported`, `cask_install`, `pkg_install`, `log`, `warn`.
- Produces: the `ollama` shim; `teeup launch ollama`; the formula fallback when the cask cannot install.

**External facts (verified 2026-09-13 at formulae.brew.sh and ports.macports.org):** cask `ollama-app` 0.34.0, name `Ollama`, artifacts `app: Ollama.app` and `binary: $APPDIR/Ollama.app/Contents/Resources/ollama -> $HOMEBREW_PREFIX/bin/ollama`, `depends_on macos: >= 14`, conflicts with cask `ollama-binary`; there is no cask named `ollama` (`/api/cask/ollama.json` is 404). Formula `ollama` 0.33.3 ("Create, run, and share large language models (LLMs)") is the CLI and server without the app. MacPorts port `ollama` 0.33.3. The interview asked for "cask + CLI, no models", which the app cask gives in one install.

**Real-Mac risk:** the cask's `binary` link lands in `$HOMEBREW_PREFIX/bin`, ahead of the shims on `PATH`, so the shim goes dormant after install; that link has not been observed. On macOS 13 the fallback relies on `brew install --cask` exiting non-zero for an unmet `depends_on macos`, which is Homebrew's documented behaviour but was not run. The app starts its own server on first launch; the formula fallback does not, and `ollama serve` is then the user's step.

- [ ] **Step 1: Write the metadata**

```sh file=capabilities/ollama/capability
summary="Ollama local LLM runtime (no models downloaded)"
group=ai
tier=lazy
requires="package-manager"
provides="ollama"
packages="ollama"
casks="ollama-app"
apps="Ollama"
interactive=false
```

- [ ] **Step 2: Write the failing test `tests/capabilities/ollama.sh`**

```bash file=tests/capabilities/ollama.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  mock_command open 0 ""
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  export TEEUP_TEST_MISSING="ollama"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_gets_the_cask() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install ollama)"
  assert_contains "$out" "Would execute: brew install --cask ollama-app" || return 1
  assert_not_contains "$out" "brew install ollama" || return 1
  assert_contains "$out" "ollama pull llama3.2" || return 1
  cleanup_test_env
}

test_install_falls_back_to_the_formula_when_the_cask_fails() {
  setup
  # What macOS 13 sees: the cask refuses, the formula installs.
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "list "*) exit 1 ;;
  "install --cask") exit 1 ;;
esac
exit 0
EOF2
  local out
  out="$(DRY_RUN=false "$TEEUP" install ollama 2>&1)"
  assert_contains "$out" "The ollama-app cask did not install (it needs macOS 14 or newer)" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew install ollama" || return 1
  "$TEEUP" has ollama || { echo "ollama must be marked installed"; return 1; }
  cleanup_test_env
}

test_install_uses_the_port_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install ollama)"
  assert_contains "$out" "Would execute: sudo port install ollama" || return 1
  assert_not_contains "$out" "--cask" || return 1
  cleanup_test_env
}

test_launch_opens_the_app_and_the_shim_exists() {
  setup
  mkdir -p "$TEEUP_APPS_DIR/Ollama.app"
  DRY_RUN=false "$TEEUP" launch ollama >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "open -a Ollama" || return 1
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  assert_file_exists "$TEST_HOME/.local/state/teeup/shims/ollama" || return 1
  cleanup_test_env
}

echo "capabilities/ollama"
run_test "install gets the cask" test_install_gets_the_cask
run_test "install falls back to the formula when the cask fails" test_install_falls_back_to_the_formula_when_the_cask_fails
run_test "install uses the port on macports" test_install_uses_the_port_on_macports
run_test "launch opens the app and the shim exists" test_launch_opens_the_app_and_the_shim_exists
print_summary
```

- [ ] **Step 3: Run it to see it fail**

Run: `bash tests/capabilities/ollama.sh`
Expected: the install tests fail (`ollama has no install script`); `launch opens the app and the shim exists` already passes, because the bundle exists and the metadata drives `launch` and the shim; `Summary: 1/4 passed`.

- [ ] **Step 4: Write `capabilities/ollama/install` and `configure`**

```bash file=capabilities/ollama/install
#!/usr/bin/env bash
# The Homebrew cask ollama-app installs Ollama.app and links the CLI bundled
# inside it to $(brew --prefix)/bin/ollama, so one cask serves both
# `teeup launch ollama` and the `ollama` shim. The cask needs macOS 14 or
# newer; where it cannot install, the ollama formula (CLI and server, no app)
# is the fallback. MacPorts has only that CLI, as the port ollama.
if casks_supported; then
  if ! cask_install ollama-app; then
    warn "The ollama-app cask did not install (it needs macOS 14 or newer); installing the ollama formula instead."
    pkg_install ollama ollama
  fi
else
  pkg_install ollama ollama
fi
```

```bash file=capabilities/ollama/configure
#!/usr/bin/env bash
# No models are pulled: they are gigabytes each and the choice is yours.
log "Pull a model when you need one, for example: ollama pull llama3.2"
```

- [ ] **Step 5: Make both executable and run the suite**

Run: `chmod +x capabilities/ollama/install capabilities/ollama/configure && bash tests/capabilities/ollama.sh`
Expected: `Summary: 4/4 passed`.

- [ ] **Step 6: Full checks and commit**

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning capabilities/ollama/install capabilities/ollama/configure tests/capabilities/ollama.sh
git diff --check
git add capabilities/ollama tests/capabilities/ollama.sh
git commit -m "Add the ollama capability"
```

Expected: `All N suites passed.` where N is the suite count printed before this task, plus 1.

---

### Task 10: `cursor` capability

**Files:**
- Create: `capabilities/cursor/{capability,install,configure}`, `tests/capabilities/cursor.sh`

**Interfaces:**
- Consumes: `casks_supported`, `cask_install`, `log`, `warn`; `teeup launch` and the lazy `list` column (Task 4).
- Produces: `teeup launch cursor` (and `teeup launch Cursor`); the `cursor` shim; the cask-with-command pattern 3a's `vscode` also follows.

**External facts (verified 2026-09-13 at formulae.brew.sh):** cask `cursor` 3.20.17, name `Cursor`, artifacts `app: Cursor.app` and `binary: $APPDIR/Cursor.app/Contents/Resources/app/bin/code` with `target: cursor`, linked to `$HOMEBREW_PREFIX/bin/cursor`; `depends_on macos: >= 12`. MacPorts has no Cursor port.

**Real-Mac risk:** beyond `open -a` (Task 4), the `cursor` shim assumes the cask's `binary` link lands in `$HOMEBREW_PREFIX/bin`; on MacPorts there is no cask, so `cursor` through the shim installs nothing and ends with `cursor is installed but cursor is still not on PATH`, which only a MacPorts machine will show.

- [ ] **Step 1: Write the metadata**

```sh file=capabilities/cursor/capability
summary="Cursor, the AI code editor"
group=editors
tier=lazy
requires="package-manager"
provides="cursor"
packages=""
casks="cursor"
apps="Cursor"
interactive=false
```

- [ ] **Step 2: Write the failing test `tests/capabilities/cursor.sh`**

```bash file=tests/capabilities/cursor.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  mock_command open 0 ""
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  export TEEUP_TEST_MISSING="cursor"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_gets_the_cask() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install cursor)"
  assert_contains "$out" "Would execute: brew install --cask cursor" || return 1
  cleanup_test_env
}

test_install_degrades_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install cursor 2>&1)"
  assert_contains "$out" "Cursor is a cask and MacPorts has none" || return 1
  assert_not_contains "$out" "port install" || return 1
  cleanup_test_env
}

test_launch_installs_then_opens() {
  setup
  # brew install --cask "installs" the bundle.
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "list "*) exit 1 ;;
  "install --cask") mkdir -p "$TEEUP_APPS_DIR/Cursor.app" ;;
esac
exit 0
EOF2
  local out
  out="$(DRY_RUN=false "$TEEUP" launch Cursor)"
  assert_contains "$out" "Cursor is not installed; installing cursor first." || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew install --cask cursor" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "open -a Cursor" || return 1
  "$TEEUP" has cursor || { echo "cursor must be marked installed"; return 1; }
  cleanup_test_env
}

test_the_cursor_command_gets_a_shim() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  assert_contains "$(cat "$TEST_HOME/.local/state/teeup/shims/cursor")" 'lazy-run cursor cursor "$@"' || return 1
  assert_contains "$("$TEEUP" list --tier lazy)" "[on first: cursor; launch: Cursor]" || return 1
  cleanup_test_env
}

echo "capabilities/cursor"
run_test "install gets the cask" test_install_gets_the_cask
run_test "install degrades on macports" test_install_degrades_on_macports
run_test "launch installs then opens" test_launch_installs_then_opens
run_test "the cursor command gets a shim" test_the_cursor_command_gets_a_shim
print_summary
```

- [ ] **Step 3: Run it to see it fail**

Run: `bash tests/capabilities/cursor.sh`
Expected: the three install and launch tests fail (`cursor has no install script`); `the cursor command gets a shim` already passes from the metadata; `Summary: 1/4 passed`.

- [ ] **Step 4: Write `capabilities/cursor/install` and `configure`**

```bash file=capabilities/cursor/install
#!/usr/bin/env bash
# Cask only (token cursor). It installs Cursor.app and links the app's shell
# command to $(brew --prefix)/bin/cursor, which is what the `cursor` shim
# waits for. MacPorts has no casks, so there the app is a manual download.
if casks_supported; then
  cask_install cursor
else
  warn "Cursor is a cask and MacPorts has none; download it from https://cursor.com/downloads"
fi
```

```bash file=capabilities/cursor/configure
#!/usr/bin/env bash
# Cursor keeps its settings in its own application support folder; teeup
# writes nothing there.
log "Open it with: teeup launch cursor (or run cursor in a project directory)"
```

- [ ] **Step 5: Make both executable and run the suite**

Run: `chmod +x capabilities/cursor/install capabilities/cursor/configure && bash tests/capabilities/cursor.sh`
Expected: `Summary: 4/4 passed`.

- [ ] **Step 6: Full checks and commit**

```bash
./bin/teeup commands --check
./tests/run.sh
shellcheck --severity=warning capabilities/cursor/install capabilities/cursor/configure tests/capabilities/cursor.sh
git diff --check
git add capabilities/cursor tests/capabilities/cursor.sh
git commit -m "Add the cursor capability"
```

Expected: `All N suites passed.` where N is the suite count printed before this task, plus 1.

---

### Task 11: README and contributor docs

**Files:**
- Modify: `README.md`, `CONTRIBUTING.md`

**Interfaces:**
- Consumes: every verb, library function and capability of Tasks 1 to 10, by the names they have there: `teeup lazy-run`, `teeup launch`, `teeup install dev-env`, `shims_generate`, `have`, `mise_ensure_global`, `mise_wrapper_write`, `dev_env_install`, `TEEUP_TEST_TTY`, `hide_host_commands`, `TEEUP_APPS_DIR`, and the capabilities `colima ai herdr tmux ollama cursor`.
- Produces: the README's "Lazy capabilities" section and two usage lines; four CONTRIBUTING items appended to "Adding a capability (new runtime)".

**Real-Mac risk:** none of its own; the README describes behaviour whose risks are recorded in Tasks 3 to 10.

- [ ] **Step 1: Add the two usage lines to the README's command block**

````markdown edit-old=README.md
teeup secret set <name>   # store a secret in the macOS Keychain
```
````

````markdown edit-new=README.md
teeup secret set <name>   # store a secret in the macOS Keychain
teeup launch cursor       # open an app, installing its cask on first use
teeup install dev-env go  # a language runtime through mise
```
````

- [ ] **Step 2: Add the "Lazy capabilities" section after the per-machine overrides paragraph**

Plan 3a may have added a daily-tier paragraph and an "Editors" section above this paragraph; the anchor below is untouched by 3a, so the new section lands after it either way.

````markdown edit-old=README.md
Per-machine overrides live in `machines/<hostname>.conf`, a committed file that is sourced after your answers and wins over them: it is where `TEEUP_PACKAGE_MANAGER=macports` or `TEEUP_SKIP="aerospace"` belongs.
````

````markdown edit-new=README.md
Per-machine overrides live in `machines/<hostname>.conf`, a committed file that is sourced after your answers and wins over them: it is where `TEEUP_PACKAGE_MANAGER=macports` or `TEEUP_SKIP="aerospace"` belongs.

### Lazy capabilities

Everything outside the core and daily tiers is `tier=lazy`: nothing is
downloaded at bootstrap, and each capability arrives the first time you reach
for it. `teeup list --tier lazy` shows every one and how it is reached.

```bash
docker ps                         # first call: "docker is provided by capability colima. Install now?"
teeup launch cursor               # opens Cursor, installing its cask first if it is missing
teeup install dev-env python      # Python and uv through mise; also node, java, ruby, rust, go
claude                            # first call installs Claude Code through mise, then runs it
teeup install colima              # the explicit form of any of the above
```

- **Shims.** `teeup configure teeup-runtime` writes one shim per command in a
  lazy capability's `provides=` into `~/.local/state/teeup/shims`, which the
  shell layer appends last on `PATH`. A shim runs `teeup lazy-run`, which
  execs the real command when one exists anywhere else on `PATH` (or under
  the package manager's prefix). Otherwise, on a terminal, it asks, installs
  and configures the capability, and runs the command with your original
  arguments. Without a terminal (a script, an editor) it prints the
  `teeup install` hint and exits 127, so nothing waits on a question nobody
  sees. `TEEUP_SKIP` in the machine file removes a capability's shims and
  makes `lazy-run` refuse.
- **Launchers.** `teeup launch <app|capability>` runs `open -a`, which also
  brings a running app to the front. When the app is not in `/Applications`
  or `~/Applications` its capability is installed first. On a MacPorts
  machine casks are skipped with a note, and `launch` tells you to install
  the app by hand.
- **Runtimes.** `teeup install dev-env <python|node|java|ruby|rust|go>` runs
  `mise use --global` from `/`, so a project's `mise.toml` cannot redirect
  it, and leaves a version you pinned alone. Python brings `uv`; Rust goes
  through mise's rust backend, which uses rustup. Runtimes get no shims,
  because macOS ships `python3`, `ruby` and `java` and a last-on-`PATH` shim
  could never fire for them. `javav 21` switches Java for one shell.
- **AI CLIs.** `ai` (`provides="claude codex gemini copilot opencode"`) gets a
  shim for each of the five names, so typing any of them before anyone has
  run `teeup install ai` or `teeup configure ai` still works. Its `configure`
  writes `~/.local/bin/{claude,codex,gemini,copilot,opencode}`: small
  wrappers that install the tool through mise on their first call (`gemini`
  brings Node with it) and run it through `mise x` after that, so `mise
  upgrade` keeps them current. A command already at one of those paths that
  teeup did not write, such as the `claude` launcher from Claude Code's own
  installer, is kept.
- **Shipped lazy capabilities:** `colima` (Colima, the Docker CLI and the
  Compose plugin; `docker` and `colima` shims), `ai` (`claude codex gemini
  copilot opencode` shims), `herdr`, `tmux` (with a `~/.config/tmux/tmux.conf`
  that is yours after the first copy, skipped when you already have a
  `~/.tmux.conf`), `ollama` (app and CLI, no models) and `cursor` (app and
  `cursor` command).
  `teeup status` lists the shims in place and the dev-envs installed.
````

- [ ] **Step 3: Append four items to CONTRIBUTING's "Adding a capability (new runtime)" list**

Append them after the last numbered item of that list, continuing its numbering, and renumber nothing that is already there. This plan is written to run after 3a (the recommended order: see "Sibling plan and the seam" above and Verification), so by the time this step runs, 3a's two items are already there (14, JSON settings through `json_set_key`/`json_merge_key` in `lib/files.sh`; 15, the `theme-apply`/`font-apply` guard, whose last line is ``    `teeup theme set` refuses to render.``): these four items continue as 16 to 19, and the block below anchors on that last line, not on item 13.

If this task instead runs before plan 3a (3b executed first), CONTRIBUTING's last item is still 13 (the `lib/macos.sh` rule) and 3a's items do not exist yet: anchor on `` `launchagent_remove <label>` in `remove`. Never call `defaults write` or `launchctl` directly. `` instead, and number these items 14 to 17 with the same text, unindented under that point instead. That pairing is shown after the block below for reference; it is not applied by this step.

````markdown edit-old=CONTRIBUTING.md
    theme, a user theme included, must define each of them in both modes or
    `teeup theme set` refuses to render.
````

````markdown edit-new=CONTRIBUTING.md
    theme, a user theme included, must define each of them in both modes or
    `teeup theme set` refuses to render.
16. A `tier=lazy` capability is reached on first use, never at bootstrap.
    `provides` lists the commands it makes available: `teeup configure
    teeup-runtime` (`shims_generate` in `lib/lazy.sh`) writes one shim per
    command into `~/.local/state/teeup/shims`, last on `PATH`, and each shim
    runs `teeup lazy-run <cap> <command>`. There is no list of lazy
    capabilities to update; adding the directory registers it. Every token
    must be a plain command name (letters, digits and `_.+-`, starting with a
    letter or digit), and no two lazy capabilities may provide the same
    command; `teeup commands --check` fails on either. `have` (`lib/core.sh`)
    never counts a shim as an installed command, so
    `pkg_install <pkg> <command>` still installs the package the shim stands
    in for.
17. `apps` names the application bundles `teeup launch` opens, separated by
    `;` because names contain spaces (`apps="Visual Studio Code"`). Use the
    `app` artifact name from the cask, without `.app`. The first entry is what
    `launch` opens with `open -a`; when that bundle is missing from
    `/Applications` and `~/Applications` the capability is installed first.
    Tests point `TEEUP_APPS_DIR` at an empty directory.
18. mise-managed tools go through `lib/mise.sh`. `mise_ensure_global <tool>
    [version]` adds a tool to the global config without rewriting a version
    the user pinned; `mise_wrapper_write <command> <tool> [runtime...]` writes
    an install-on-first-call wrapper into `~/.local/bin` (the `ai`
    capability) and never replaces a file there that it did not write; and
    every mise call except the wrapper's `mise x` runs with `-C /`, so a
    project's `mise.toml` in the current directory cannot shadow the global
    file. Check registry names with `mise registry`. Language runtimes are
    `teeup install dev-env <lang>` (`dev_env_install`), never a capability
    and never a shim.
19. Two more test hooks join `TEEUP_TEST_MISSING`: `TEEUP_TEST_TTY=yes|no`
    overrides the terminal check in `teeup lazy-run`, so a piped `y` can
    answer its question, and `hide_host_commands <name...>` (tests/helper.sh)
    adds every copy of a command on the host's `PATH` to `TEEUP_TEST_MISSING`
    by absolute path. A test can then prove an install on a runner that has
    `docker` in `/usr/bin` while the copy the mocked install creates is still
    found. `tests/capabilities/colima.sh` is the reference round trip.
````

For reference only, the 3b-first pairing (not applied here; use it instead of the block above only when this task runs before plan 3a is on `main`):

```markdown
edit-old:
    `launchagent_remove <label>` in `remove`. Never call `defaults write` or
    `launchctl` directly.

edit-new:
    `launchagent_remove <label>` in `remove`. Never call `defaults write` or
    `launchctl` directly.
14. A `tier=lazy` capability is reached on first use, never at bootstrap.
    [... same text as item 16 above ...]
15. `apps` names the application bundles `teeup launch` opens ...
    [... same text as item 17 above ...]
16. mise-managed tools go through `lib/mise.sh` ...
    [... same text as item 18 above ...]
17. Two more test hooks join `TEEUP_TEST_MISSING` ...
    [... same text as item 19 above ...]
```

- [ ] **Step 4: Check the names the docs use against the code**

Run:

```bash
for name in lazy-run launch dev-env shims_generate mise_ensure_global mise_wrapper_write dev_env_install TEEUP_TEST_TTY hide_host_commands TEEUP_APPS_DIR; do
  grep -rqF -- "$name" bin lib tests || echo "missing in code: $name"
done
./bin/teeup list --tier lazy
```

Expected: no `missing in code:` line. The list prints, among any lazy capabilities plan 3a has added, these six rows (the column widths come from `%-18s %-6s`):

```text
ai                 lazy   AI coding CLIs: claude, codex, gemini, copilot, opencode through mise  [on first: claude codex gemini copilot opencode]
colima             lazy   Colima container runtime with the Docker CLI and Compose  [on first: docker colima]
cursor             lazy   Cursor, the AI code editor  [on first: cursor; launch: Cursor]
herdr              lazy   Herdr, the agent multiplexer that lives in your terminal  [on first: herdr]
ollama             lazy   Ollama local LLM runtime (no models downloaded)  [on first: ollama; launch: Ollama]
tmux               lazy   tmux terminal multiplexer  [on first: tmux]
```

- [ ] **Step 5: Full checks and commit**

```bash
./bin/teeup commands --check
./tests/run.sh
git diff --check
git add README.md CONTRIBUTING.md
git commit -m "Document lazy capabilities, launch and dev-env"
```

Expected: `commands --check` prints nothing; `All N suites passed.` where N is the suite count printed before this task (unchanged). No script changed, so there is nothing new for shellcheck.

---

## Verification

This plan is written for the recommended order, 3a then 3b: every task through Task 10 transcribes and passes on `main` alone, in either order, but Task 11 Step 3's CONTRIBUTING edit (see C1 in that step) anchors on 3a's last item and is not standalone-verifiable in isolation from 3a. Verifying this plan alone against `main` (without 3a) means substituting that step's reference 3b-first pairing for the applied one; everything else below is unaffected by which plan landed first.

Run from the repository root after Task 11, on a machine with `shellcheck`, `zsh` and `lua` installed (`sudo apt-get install -y shellcheck zsh lua5.4`, or `brew install shellcheck lua`; macOS ships zsh):

```bash
./bin/teeup commands --check          # capability metadata lint; prints nothing
./tests/run.sh                        # All N suites passed. (the count before this plan, plus 8)
shellcheck --severity=warning bootstrap bin/teeup lib/*.sh \
  $(find capabilities -type f \( -name install -o -name configure \
    -o -name remove -o -name doctor -o -name theme-apply -o -name font-apply \)) \
  tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh \
  tests/lib/*.sh tests/capabilities/*.sh
./bin/teeup list --tier lazy          # every lazy row ends in a [on first: ...], [launch: ...] or [teeup install ...] column
```

The shellcheck line is the CI step, unchanged: every new script and test file sits under a path it already globs, so `.github/workflows/ci.yml` needs no edit.

Then, under a throwaway `$HOME` and in a subshell, prove the shim round trip outside the harness. Nothing is installed: without a terminal the shim only hints, and `TEEUP_TEST_MISSING=docker` makes a host that has `docker` behave like one that does not.

```bash
(
  tmp="$(mktemp -d)"
  export HOME="$tmp" XDG_CONFIG_HOME="$tmp/.config" XDG_STATE_HOME="$tmp/.local/state"
  ./bin/teeup configure teeup-runtime >/dev/null
  ls "$tmp/.local/state/teeup/shims"
  TEEUP_TEST_MISSING=docker "$tmp/.local/state/teeup/shims/docker" ps </dev/null; echo "exit $?"
  "$tmp/.local/state/teeup/shims/docker" --version </dev/null; echo "exit $?"
  ./bin/teeup status | tail -2
  rm -rf "$tmp"
)
```

Expected: the shims `claude codex colima copilot cursor docker gemini herdr ollama opencode tmux` (plus `code` and `nvim` once plan 3a is on `main`); `docker is not installed. It is provided by capability colima; run: teeup install colima` and `exit 127`; then, on a host that has a `docker`, that docker's version line and `exit 0` (the shim execs a real binary whenever one exists), or the same hint and `exit 127` on a host without one; and `Lazy shims: claude codex colima copilot cursor docker gemini herdr ollama opencode tmux` (plus `code` and `nvim` once plan 3a is on `main`) followed by `Dev envs: none (teeup install dev-env <python|node|java|ruby|rust|go>)`. This exact block was run on the transcribed final state on Linux, with a host `docker` 29.7.2.

**What the first real run on a Mac should show.** Nothing in this plan has executed on macOS. In order:

1. `./bootstrap` (or `teeup configure teeup-runtime`) leaves `~/.local/state/teeup/shims/{colima,cursor,docker,herdr,ollama,tmux}`, and in a **new** login shell `print -rl -- $path | tail -1` is that directory, also after `exec zsh -l` inside the first shell.
2. `docker ps` in that shell asks `docker is provided by capability colima. Install now? [Y/n]` (or a gum confirm), installs `colima`, `docker` and `docker-compose`, links `~/.docker/cli-plugins/docker-compose`, runs `colima start` (minutes, the first time), then prints the empty container table. `docker compose version` works. A second `docker ps` in a new shell does not go through `teeup` at all (`command -v docker` is `/opt/homebrew/bin/docker`).
3. `echo | docker ps` in a shell on a machine where colima is not installed yet exits 127 with the hint and asks nothing.
4. `teeup launch cursor` installs the cask and opens Cursor; running it again only brings the window forward. `teeup launch Google Chrome` does the same once plan 3a's `chrome` capability is on `main`.
5. `teeup install dev-env python` leaves `python` and `uv` in `~/.config/mise/config.toml`, and `python --version` in the next prompt is mise's Python, not `/usr/bin/python3`. `teeup install dev-env rust` installs `~/.rustup` and `~/.cargo`, and `cargo --version` works after a new terminal.
6. `teeup configure ai`, then `claude --version`: the first call installs Claude Code through mise and prints its version; `gemini --version` installs Node and Gemini CLI first. On a Mac that already had Claude Code's native installer, `configure ai` printed `Keeping ~/.local/bin/claude` instead.
7. `tmux` through its shim installs tmux and starts a session with the `C-a` prefix; `herdr` and `ollama` do the same for their capabilities, and `ollama --version` resolves to the cask's link under `/opt/homebrew/bin`.
8. On a MacPorts machine (`TEEUP_PACKAGE_MANAGER=macports` in `machines/<host>.conf`): `docker ps` installs the `colima`, `docker` and `docker-compose-plugin` ports, and `docker compose version` finds the plugin without any link; `teeup launch cursor` stops with its "still not in /Applications" message.

---

## Self-review

### Spec coverage

| Spec requirement | Section | Task |
|---|---|---|
| `teeup-runtime configure` reads `provides=` of every `tier=lazy` capability and writes one shim per command into `~/.local/state/teeup/shims/` | 6.1, 4b | 1 (`shims_generate`), 3 |
| The shape of a shim (`#!/bin/bash`, `exec "$TEEUP_PATH/bin/teeup" lazy-run <capability> <command> "$@"`) | 6.1 | 1 (plus the baked fallback path of contract 1) |
| The shell layer appends the shims last on `PATH` | 6.1, 4b | phase 2a; 3 (moved last on every pass, tested under the MacPorts machine-file ordering) |
| `lazy-run` execs a real binary elsewhere on `PATH` | 6.1 | 3 |
| On a TTY: ask, install then configure, exec with the original arguments | 6.1 | 3, 5 (round trip) |
| Without a TTY: print the `teeup install` hint and exit 127 | 6.1 | 3, 5 |
| `provides=` never lists a command macOS ships; runtimes get no shims | 4a, 6 | existing `TEEUP_SHIM_FORBIDDEN`; 1 adds token and duplicate checks |
| `apps=` holds `.app` names for `teeup launch` | 4a | 1 (`cap_apps`, `;`-separated), 4 |
| `teeup launch <app>`: `open -a` when installed (focuses a running app), else install the cask and open | 6.3, CLI surface | 4, 9, 10 |
| AI CLIs through mise wrappers in `~/.local/bin`: `mise use -g` on first call, `exec mise x <tool> -- <cmd> "$@"` after; nothing downloaded at configure time | 6, 4b, interview: AI CLIs | 2 (`mise_wrapper_write`), 6 |
| `teeup install dev-env <python\|node\|java\|ruby\|rust\|go>`; Python also installs uv; Rust uses rustup; the rest `mise use --global` | 6, CLI surface, interview: Languages | 2 (`dev_env_install`), 4 |
| Shims for commands macOS lacks: `docker`, `colima`, `tmux`, `herdr`, `ollama` | 6 | 5, 7, 8, 9 |
| Colima + docker CLI, lazy on first `docker` | interview: Containers | 5 |
| Ollama optional lazy (cask + CLI, no models) | interview: AI CLIs | 9 |
| Cursor optional lazy cask | interview: AI CLIs | 10 |
| tmux lazy, not essential | interview: Terminal; 6 | 8 |
| Herdr is gated on a phase 3 check that it ships macOS builds | 6, migration table | 7 (Decision 14 records the check) |
| Phase 3 gate: shim round-trip test | migration table | 5 (`test_round_trip_shim_installs_configures_and_execs_docker`) |
| `teeup list` generated from metadata | 12 | 4 (lazy column) |
| Machine file precedence for `TEEUP_SKIP` and the package manager | 7 | 1 (`shims_generate`), 3 (`lazy-run`), 4 (`launch`), all through `answers_load` in `bin/teeup` |
| Daily tier, editors, Firefox Developer Edition, `neovim`/`vscode`/`chrome` as lazy | USER DECISION 2026-09-13 | plan 3a; this plan's shims, `launch` and `list` column serve them from metadata with no change |

Spec items this phase does not cover are listed under "Deliberately deferred" below.

### Corrections folded in after the first draft

| Finding | Change |
|---|---|
| MacPorts does package Compose v2, as `docker-compose-plugin` 2.36.2; the draft skipped Compose there | Task 5 installs that port on MacPorts, its test asserts it, Decision 12 and the external facts explain why no link is needed (the `docker` port's patched plugin path) |
| docker's plugin search order was stated with the config directory ahead of `cliPluginsExtraDirs` | Corrected from `manager.go` in Decision 12 and Task 5; the design is unaffected |
| tmux loads `~/.tmux.conf` and `~/.config/tmux/tmux.conf` both, the XDG file last; the draft said `~/.tmux.conf` wins and copied the config anyway | Task 8 installs nothing next to an existing `~/.tmux.conf`; the test, the config header, Decision 17 and the README follow |
| Gemini CLI's registry file is `gemini-cli` with `gemini` as an alias | The wrapper installs `gemini-cli` (command still `gemini`); Task 6 tests and Decision 7 follow |
| Omarchy's current `install/user/mise.sh` no longer wraps Gemini and turns `upgrade.auto_prune` off | Decision 8 and Task 6's facts cite branch `quattro` as it is; auto-prune is a Real-Mac risk and a deferred item |
| A `nvim` shim would answer the zsh layer's `command -v nvim` and set `EDITOR=nvim` on a machine without Neovim | Task 3 Step 7 ignores a hit inside the shims directory, with a test |
| `path_append` leaves the shims wherever an inherited `PATH` had them | Task 3 moves the entry last on every pass, tested under a MacPorts machine file with the shims inherited first |
| `teeup launch Google Chrome` (unquoted) resolved only `Google` | `cmd_launch` joins its arguments; Task 4's test covers it |
| Task 2's test file drew SC2034 for `DRY_RUN` | `setup` exports it and the dry-run calls use a `DRY_RUN=true` prefix, in `tests/lib/mise.sh` and `tests/lib/lazy.sh` |
| Two tests passed before their implementation for the wrong reason; seven expected counts were off | See "What the transcription check proved" |
| The sibling plan's file name and the JSON helpers' location | Plan 3a is `2026-09-13-redesign-phase3a-daily-tier.md`; its helpers are `json_set_key`, `json_merge_key` and `json_quote` in `lib/files.sh`; Task 11 numbers the CONTRIBUTING items after 3a's two when they are present |

### Placeholder scan

Searched the plan for `TBD`, `TODO`, `FIXME`, `implement later`, `similar to Task`, `appropriate error handling`, and for a bare `...` standing in for code: no hits in any step. The `...` characters that remain are prose (`lazy_provider`, `shims_generate`, `lazy_is_tty`, ... in Task 1's expected failure list), shell output shapes (`File not found: .../shims/boxctl`), or the `mise x ... -- ...` description of Omarchy's wrapper. Every new file appears in full (`lib/lazy.sh`, `lib/mise.sh`, `capabilities/mise/configure`, `capabilities/teeup-runtime/configure`, the six capabilities' `capability`/`install`/`configure`, `tmux.conf`, and the eight new test files). Every change to an existing file is an `edit-old`/`edit-new` pair that quotes text occurring exactly once at that point, which the transcription check below enforces mechanically.

### Name and type consistency across tasks

- `lib/lazy.sh` (Task 1): `shims_dir`, `TEEUP_SHIM_MARKER`, `lazy_provider`, `lazy_real_command`, `lazy_is_tty`, `shim_write`, `shims_generate`, `cap_apps`, `app_installed`, `launch_resolve`. Task 3 calls `shims_generate`, `lazy_real_command`, `lazy_is_tty`; Task 4 calls `launch_resolve`, `cap_apps`, `app_installed`, `shims_dir`; Task 4's status test calls `shims_generate` directly. No other spelling of any of them appears (grepped).
- `lib/mise.sh` (Task 2): `mise_global_state` (prints `installed`/`requested`/`absent`), `mise_ensure_global <tool> [version]`, `TEEUP_MISE_WRAPPER_MARKER`, `mise_wrapper_write <command> <tool> [runtime...]`, `TEEUP_DEV_ENVS`, `dev_env_install`, `dev_env_installed`. `capabilities/mise/configure` calls `mise_ensure_global pre-commit`; `bin/teeup` calls `dev_env_install` and `dev_env_installed`; `capabilities/ai/configure` calls `mise_wrapper_write` five times with the argument order `<command> <tool> [runtime]`, including `gemini gemini-cli node`.
- `lib/all.sh`'s source list ends `... capability macos theme font lazy mise`: `lazy` after `files` and `capability`, `mise` after `state` and `pkg`.
- The marker strings are asserted by the tests through the variables, never retyped: `TEEUP_SHIM_MARKER` in `tests/lib/lazy.sh`, `TEEUP_MISE_WRAPPER_MARKER` in `tests/lib/mise.sh`.
- Test hooks: `TEEUP_TEST_TTY` is read only by `lazy_is_tty` and set only by tests; `hide_host_commands` is defined in `tests/helper.sh` (Task 1) and used by `tests/capabilities/colima.sh` (Task 5); `TEEUP_TEST_MISSING` absolute-path entries are honoured by both `have` and `lazy_real_command`; `TEEUP_APPS_DIR` is read by `app_installed` and `cmd_launch`'s error line.
- User-visible strings asserted in one task and produced in another agree: `docker is provided by capability colima. Install now?` (Task 3 `cmd_lazy_run`, Task 5 test), `<cmd> is not installed. It is provided by capability <cap>; run: teeup install <cap>` (Task 3, Tasks 3 and 5 tests), `Keeping <file>: it was not written by teeup` (Task 2, Tasks 2 and 6 tests), `[on first: cursor; launch: Cursor]` (Task 4 `cap_list_via`, Task 10 test), `Would install <file>` (`copy_config_once` on `main`, Task 8 test).
- Per-suite `run_test` counts, taken from the transcription runs: `lib/lazy.sh` 14, `lib/mise.sh` 16, `lib/core.sh` 11, `lib/capability.sh` 17, `capabilities/teeup-runtime` 9, `bin/teeup` (`tests/cli.sh`) 22 after Task 3 and 28 after Task 4, `capabilities/zsh` 23, `capabilities/colima` 9, `capabilities/ai` 7, `capabilities/herdr` 3, `capabilities/tmux` 5, `capabilities/ollama` 4, `capabilities/cursor` 4. Suites rise by one in Tasks 1, 2, 5, 6, 7, 8, 9 and 10 and stay flat in Tasks 3, 4 and 11: eight new suites, from 30 on `main` today to 38.
- Every command a test mocks is called by bare name in shipped code (`brew`, `port`, `mise`, `open`, `colima`, `hostname`); the only absolute path a shim contains is the `#!/bin/bash` interpreter line.

### External facts and their sources (checked 2026-09-13)

| Fact the plan relies on | Source |
|---|---|
| mise registry: `claude` -> `aqua:anthropics/claude-code http:claude`; `codex` -> `aqua:openai/codex npm:@openai/codex`; `gemini-cli` (alias `gemini`) -> `npm:@google/gemini-cli`; `copilot` -> `aqua:github/copilot-cli github:github/copilot-cli npm:@github/copilot`; `opencode` -> `aqua:anomalyco/opencode`; `herdr` -> `aqua:herdrdev/herdr github:herdrdev/herdr`; `node`, `python`, `java`, `ruby`, `go`, `rust` are `core:`; `uv` -> `aqua:astral-sh/uv` | `mise registry <name>` on mise 2026.9.4; `jdx/mise` `main` `registry/{claude,codex,gemini-cli,copilot,opencode,herdr}.toml` |
| `mise -C/--cd` "Change directory before running command"; `mise -C / x uv -- pwd` prints `/`; `ls --global`/`--installed`, `use --global --quiet`, `where` ("The tool must be installed") | `mise --help`, `mise ls --help`, `mise use --help`, `mise where --help` and a run on 2026.9.4 |
| `MISE_MINIMUM_RELEASE_AGE=0` is honoured; `not_found_auto_install` defaults to `true`; `upgrade.auto_prune` defaults to `true` with a `prune_after` grace period | `mise settings get`/`settings ls --all` on 2026.9.4; `settings.toml` at `v2026.9.4` |
| npm backend installs without Node but does not add Node at runtime | `docs/dev-tools/backends/npm.md` at `v2026.9.4` (reworded on `main`) |
| mise's rust backend installs rustup when missing and uses `~/.rustup`/`~/.cargo`; it can reuse a package manager's rustup proxies | `docs/lang/rust.md` at `v2026.9.4` |
| Omarchy wraps `codex`, `claude`, `copilot`, `opencode` with `omarchy-mise-install`, which exports `MISE_MINIMUM_RELEASE_AGE=0`, runs `mise use -g --quiet` each call and execs `mise x`; `omarchy-install-dev-env` uses `mise use --global` for python and java, the uv and rustup install scripts for uv and rust | `basecamp/omarchy` branch `quattro`: `bin/omarchy-mise-install`, `install/user/mise.sh`, `bin/omarchy-install-dev-env` |
| Claude Code's native installer manages `~/.local/bin/claude` as a symlink into `~/.local/share/claude/versions/` | code.claude.com/docs/en/setup |
| Homebrew formulae: `colima` 0.10.3 (dep `lima`; bottles include Intel `sonoma`), `docker` 29.8.0 and `docker-compose` 5.5.1 (Apple Silicon and Linux bottles only), `tmux` 3.7c, `ollama` 0.33.3, `herdr` 0.9.0 (bottles `arm64_sonoma`, `arm64_sequoia`, `arm64_tahoe`; build deps `rust`, `zig@0.15`), `rustup` 1.29.1, `uv` 0.12.13 | formulae.brew.sh `/api/formula/<name>.json` |
| `docker-compose` formula symlinks the plugin into `lib/docker/cli-plugins` and its caveat asks for `cliPluginsExtraDirs` | `Homebrew/homebrew-core` `Formula/d/docker-compose.rb` |
| Casks: `ollama-app` 0.34.0 (`Ollama.app`, binary linked to `$HOMEBREW_PREFIX/bin/ollama`, `macos >= 14`, conflicts with `ollama-binary`); `cursor` 3.20.17 (`Cursor.app`, `bin/code` linked as `$HOMEBREW_PREFIX/bin/cursor`, `macos >= 12`); `google-chrome` (`Google Chrome.app`) and `visual-studio-code` (`Visual Studio Code.app`, `bin/code`) for 3a's `apps=`; no casks named `ollama`, `docker` or `herdr` | formulae.brew.sh `/api/cask/<token>.json` (404 for the missing ones) |
| MacPorts ports: `colima` 0.10.3, `docker` 29.8.0, `docker-compose` 1.29.2 (`python/docker-compose`), `docker-compose-plugin` 2.36.2, `tmux` 3.7c, `ollama` 0.33.3, `herdr` 0.8.2, `rustup` 1.29.0, `uv` 0.12.11; no Cursor port | ports.macports.org `/api/v1/ports/<name>/` and its name search |
| `docker-compose-plugin` installs to `${prefix}/libexec/docker/cli-plugins`; the `docker` port rewrites `/usr/lib` to `${prefix}/lib` in `manager_unix.go` | `macports/macports-ports` `devel/docker-compose-plugin/Portfile`, `devel/docker/Portfile` |
| docker CLI plugin search order: `cliPluginsExtraDirs`, `$DOCKER_CONFIG/cli-plugins`, then `/usr/local/lib`, `/usr/local/libexec`, `/usr/lib`, `/usr/libexec` `docker/cli-plugins` | `docker/cli` v29.8.0 `cli-plugins/manager/manager.go` and `manager_unix.go` |
| `colima status` returns "`<profile>` is not running" from `getStatus` (cobra `RunE`, so non-zero); latest release v0.10.3 | `abiosoft/colima` `app/app.go`, `cmd/status.go`; `gh api repos/abiosoft/colima/releases/latest` |
| Herdr v0.9.0 ships `herdr-macos-aarch64` and `herdr-macos-x86_64`; README: `brew install herdr` · `mise use -g herdr`, "`ctrl+b q` detaches, `herdr` reattaches"; config at `~/.config/herdr/config.toml` on macOS | `gh api repos/herdrdev/herdr/releases/latest`; `herdrdev/herdr` README; herdr.dev/docs/configuration |
| tmux loads every existing file in `/etc/tmux.conf:~/.tmux.conf:$XDG_CONFIG_HOME/tmux/tmux.conf:~/.config/tmux/tmux.conf`, in order; `~/.config/tmux/tmux.conf` since 3.1; `default-terminal` picked at build time since 3.3 | `tmux/tmux` tag 3.7c `Makefile.am`, `cfg.c`, `tmux.c`; `CHANGES`; observed with tmux 3.7c on Linux |

### What the transcription check proved

A harness (`apply2.py` and `verify2.sh` in the author's scratchpad) cloned `main` at `0adfb22` fresh, then for each task in order: applied every `file=` block and every `edit-old`/`edit-new` pair of that task exactly as written (failing on any `edit-old` that did not occur exactly once), ran the `chmod` lines, ran every step's `Run:` command at the point it appears and compared its `Summary:` lines with the step's `Expected:` text, then ran `./tests/run.sh`, `./bin/teeup commands --check`, `shellcheck --severity=warning` on the task's new and edited scripts (and each touched test file on its own), `git diff --check`, and committed. Each task's literal shellcheck line and the CI shellcheck step were then run against the final tree.

Results on the final text of this plan:

- `main` printed `All 30 suites passed.`; after Tasks 1 to 11, `31`, `32`, `32`, `32`, `33`, `34`, `35`, `36`, `37`, `38` and `38`, each matching the task's "plus K".
- Every "see it fail" step printed the `Summary:` its `Expected:` line names (`0/14`, `0/16`, `6/9` `12/22` `21/23`, `19/28`, `2/9`, `0/7`, `1/3`, `1/5`, `1/4`, `1/4`), and every "passes" step the full count (`14/14` `11/11` `17/17`, `16/16` `10/10`, `9/9` `22/22` `23/23`, `28/28`, `9/9`, `7/7`, `3/3`, `5/5`, `4/4`, `4/4`). Seven counts in the earlier draft disagreed with these runs and were corrected; two tests that passed before their implementation for the wrong reason (`have ignores a shim` with no shim present, `tmux configure dry run writes nothing` with no configure script) now assert what they depend on and fail first.
- `./bin/teeup commands --check` printed nothing and exited 0 after every task. Each task's own `shellcheck --severity=warning` line, run as written, was silent, and so was the CI step's full shellcheck line on the final tree; every new test file is also clean on its own. (`tests/lib/core.sh` on `main` already warns SC2034 when checked alone; that is phase 1's, and every command in this plan and in CI checks it together with `lib/*.sh`, where it is clean.)
- `git diff --check` was clean after every task, and each commit contained only paths named on that task's `git add` line.
- Task 11 Step 4's name check printed no `missing in code:` line, and `./bin/teeup list --tier lazy` printed exactly the six rows shown there.
- The final tree's full suite passed under bash 3.2.0 twice: once with a directory holding a `bash` symlink to the 3.2.0 build first on `PATH` (`All 38 suites passed.`, which covers the runner, every suite and the libraries they source), and once inside a user and mount namespace with the 3.2.0 binary bind-mounted over `/usr/bin/bash` (`All 38 suites passed.`), so that `bin/teeup`, every capability script started through `#!/usr/bin/env bash` under the harness's narrowed `PATH`, the generated `#!/bin/bash` shims and the mise wrappers also ran on 3.2.0.
- The Verification block above ran on the final tree as written.

What it does not prove: anything on macOS (the harness runs on Linux with mocked `brew`, `port`, `mise`, `open` and `colima`); that the real `brew`, `port` and `mise` behave like their mocks; how zsh orders `PATH` after `/etc/zprofile`'s `path_helper`; the terminal detection under a real pty and gum; Task 11's documentation reading well.

### Real-Mac risks, collected

- **Shims under a real login shell** (Tasks 1, 3): the shims directory's final position after `path_helper`, `brew shellenv` and `mise activate`; zsh's command hash reaching a shim after the real binary is installed; programs that give a shim a pty on stdin and stderr but nobody to answer the prompt.
- **`open -a` and Launch Services** (Task 4): an app whose registered name differs from its bundle file name passes `app_installed` and then fails in `open`.
- **Colima** (Task 5): the non-zero exit of `colima status` was read from source; the first `colima start` downloads a VM image for minutes inside the shim's install; `docker` and `docker-compose` build from source on Intel Homebrew; the MacPorts plugin path through the patched `docker` port was read from two Portfiles.
- **mise wrappers** (Tasks 2, 6): aqua downloads for `darwin-arm64`/`darwin-amd64`, Gemini CLI starting under mise's Node, `mise x` auto-installing a project-pinned version, `mise upgrade` pruning an old version while a session is open.
- **Herdr** (Task 7): no Intel bottle, so Rust and Zig build dependencies on an Intel Mac; the MacPorts port trails the release.
- **tmux** (Task 8): `tmux-256color` terminfo reached by programs that read the system terminfo; the reload key's hard-coded `~/.config` path under a non-default `XDG_CONFIG_HOME`.
- **Ollama** (Task 9): the cask's CLI link, and the formula fallback relying on `brew install --cask` failing on macOS 13.
- **Cursor** (Task 10): the cask's `cursor` link; on MacPorts the shim can only end in its "still not on PATH" message.

### Deliberately deferred

- **`kubectl`, `helm`, `k9s`, `lazydocker` shims and the `docker-dbs` picker** (spec section 6, interview: Containers and Databases). Each is another lazy capability on the pattern Task 5 fixes; they belong with the containers work in phase 4 and need no runtime change.
- **`teeup update` running `mise upgrade`** for the AI CLIs and runtimes (spec section 6). The `update` verb is phase 4; until then `mise upgrade` is a manual command.
- **`teeup menu` rows with `when` predicates** and **launch-or-focus installing inside a themed floating terminal** (spec sections 1 and 6.3). There is no menu yet; `teeup launch` covers the CLI half.
- **The teeup agent skill** (interview: AI CLIs). It documents the finished runtime and fits phase 5's documentation pass.
- **Shims for mise-managed CLI tools other than the AI CLIs.** The `mise_wrapper_write` helper is general; which tools get wrappers is a later decision.
- **A themed tmux configuration** and a tmux `theme-apply` hook (spec section 7). The shipped `tmux.conf` has no colours; themed templates are phase 4.
- **Herdr configuration.** Herdr runs without a config file; a shipped `~/.config/herdr/config.toml` waits for a reason to exist.
- **mise's `upgrade.auto_prune`.** Omarchy turns it off so `mise upgrade` never removes a version a running agent is using; teeup leaves the user's mise settings alone for now and relies on mise's default grace period.
- **A `teeup doctor` check that the shims directory is last on the live `PATH`.** The `doctor` verb is phase 4.

### Review fixes (2026-09-14)

Applied against `.superpowers/plan3/phase3-plans-review.md`'s five Blocking/Important findings (reviewed against `main` at `0adfb22`, combined tree in both orders); the three that touch this plan's own text are folded into the task bodies above rather than left as a diff, so they read as if always written this way:

- **B1 (Blocking).** `launch_resolve` (Task 1, `lib/lazy.sh`) took a case-insensitive `[[ -f capabilities/$name/capability ]]` hit for any case variant of a real capability name, which is certain on the case-insensitive disk every default Mac (and both GitHub macOS CI runners) uses: `teeup launch Cursor` resolved to a nonexistent `Cursor` capability instead of falling through to the `apps=` match. Fixed by matching a capability name only on an exact, case-sensitive hit against `cap_list`'s output (`cap_list | grep -qxF -- "$wanted"`), never through `cap_exists`; a case variant now falls through to the case-insensitive app-name match. `test_launch_resolve_matches_capability_names_case_sensitively` (Task 4) covers it on Linux by faking `cap_exists` to accept any case, so the guard is exercised without needing a case-insensitive filesystem.
- **I1 (Important).** Nothing put the AI CLI wrappers in place on a freshly bootstrapped Mac: `ai` (Task 6) was `tier=lazy` with no `provides=`, so its `configure` never ran until a user already knew to type `teeup install ai`, and `claude` was "command not found". Fixed with `provides="claude codex gemini copilot opencode"` on the `ai` capability, which gets it a shim from every other lazy capability's `provides=` (Task 1's `shims_generate`); typing `claude` before `ai` is ever installed now reaches it through the shim, `lazy-run ai claude`, and the wrapper the capability writes. `test_the_claude_shim_installs_ai_then_execs_through_mise` (Task 6) is the round-trip test; the Task 11 `teeup list --tier lazy` row, the Verification shim list and the README's AI CLIs bullet all name the five commands.
- **C1 (Important, combination with plan 3a).** Task 11 Step 3's CONTRIBUTING `edit-old`/`edit-new` pair originally anchored on item 13 and hard-coded items 14-17, the same anchor and numbers plan 3a's own CONTRIBUTING step used; applied in either order the second plan's items landed between item 13 and the first plan's, so the list read out of order. Fixed by anchoring this plan's pair on 3a's item 15 (the `theme-apply`/`font-apply` guard's last line) and numbering these four items 16 to 19, matching the recommended 3a-then-3b execution order; the 3b-first anchor and numbering (14-17, unindented under item 13) is kept alongside it, labelled for reference only and not applied by the step.
- 3a's own two Important findings from the same review, **I2** (the `emacs` formula shadowing the `emacs-app` cask's link step) and **I3** (the Neovim `rosepine` key that could never match `rose-pine*`), touch none of this plan's files; they are recorded in plan 3a's own "Review fixes (2026-09-14)" section.
- **Gum-dependent test (found by this session's controller, not in the review above).** Task 6's `tests/capabilities/ai.sh` drives the shim's install prompt (`test_the_claude_shim_installs_ai_then_execs_through_mise`, a piped `y` under `TEEUP_TEST_TTY=yes`) without disabling gum. `lib/ui.sh` uses gum whenever `TEEUP_NO_GUM` is empty and `have gum` succeeds, and the test harness's narrowed PATH (`$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin`) still exposes a host `gum` (a real `/usr/bin/gum` on a machine that has one installed, exactly the authoring brief's forbidden host dependency): real gum then draws the prompt on `/dev/tty` instead of reading the piped answer, the expected `claude is provided by capability ai. Install now?` line never prints, and the test fails on any machine with gum installed while still passing on CI runners that lack it. Fixed by exporting `TEEUP_NO_GUM=1` in `tests/capabilities/ai.sh`'s `setup()`, the same practice Task 3's `tests/cli.sh` `setup` (`lazy-run` and `launch` ask through `ui_confirm`) and `tests/capabilities/secrets.sh` already use. The round-trip test also now seeds a fake `gum` in `$MOCK_BIN` that fails loudly if run and asserts (via `$MOCK_LOG`) that it never is, proving the disable holds even on a machine that has gum on `PATH`, without the suite itself depending on gum being present. Every other prompt-driving test in this plan (`tests/cli.sh`'s lazy-run/launch tests in Task 3, `tests/capabilities/colima.sh`'s round trip in Task 5) already exported `TEEUP_NO_GUM=1` before this session; Tasks 4, 7, 8, 9 and 10 never call `ui_confirm`/`ui_choose`, so they needed no change. Plans 3a and 4d were checked for the same defect: 3a's wizard tests (`tests/bootstrap.sh`) already export `TEEUP_NO_GUM=1` in `setup()`, covering the theme, daily-confirm and Emacs-flavor questions; 4d's only prompt-driving test (`test_the_wizard_offers_every_shipped_theme`, also in `tests/bootstrap.sh`) inherits the same `setup()`; neither plan needed a fix.

**Combined verification, re-run after the gum fix.** A tree with plan 3a's 7 tasks and this plan's Tasks 1-5 already applied (recommended order, 3a then 3b) had its `Task 6` commit reset off (it predated the gum fix) and Tasks 6 to 11 re-applied and re-verified by the same transcription harness described above: every task's `./tests/run.sh`, `./bin/teeup commands --check`, `shellcheck --severity=warning` on touched scripts and tests, and `git diff --check` were green, ending at `All 46 suites passed.`, matching the review's combined total. The final tree's full suite was then run a third way beyond the two ways described earlier in this Self-review: inside a user and mount namespace with the bash 3.2.0 build bind-mounted over `/usr/bin/bash` and the same build's directory also first on `PATH` — `All 46 suites passed.`, 545 PASS, 0 FAIL, confirming the fixed `tests/capabilities/ai.sh` (and every other suite) also passes under bash 3.2.0.
