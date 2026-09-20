# teeup Redesign, Phase 4a: Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a machine that already runs teeup the four verbs it needs afterwards — `teeup update [<cap>]`, `teeup reset <cap>`, `teeup remove <cap>` and `teeup dev add-migration` — plus the migration runner, the stock-checksum refresh rule and the user hook points (`post-bootstrap`, `post-update`, `theme-set`) that spec section 9 and section 7's "Hooks" paragraph describe.

**Architecture:** Nothing here adds a new model. `update` walks spec section 9's list, each step idempotent and each failure reported rather than fatal. Migrations are `migrations/<epoch>.sh` files run once per machine through the same `bash -eu` seam `cap_run` uses, with markers under `state/migrations/`. `reset` and a migration's config refresh are the same idea from two directions: both re-run the capability's own `configure` with an environment variable that turns its `copy_config_once` calls into `refresh_config` or `refresh_if_pristine`, so a file the capability renders (zsh's home stubs, git's include paths) is rendered again instead of copied raw. `remove` runs the capability's `remove` script when it has one and then uninstalls what its metadata names. Hooks are Omarchy's: a directory per event, every file run with `bash`, a failure warns and never aborts.

**Tech Stack:** bash 3.2 (macOS stock), BSD `sed`/`awk`/`date`/`stat`, `git`, Homebrew and MacPorts, `mise`, `defaults(1)`, `launchctl`, the phase 1 mock-binary test harness.

**Spec:** `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md`. This plan implements spec section 9 (Updates) in full, the "Reset", "Hooks" and "macOS defaults" paragraphs of section 7, the `update`/`remove`/`reset`/`dev add-migration` rows of the CLI surface, and the "fall back to generic implementations for `update` and `remove` from metadata" sentence below that table. It is the first half of the phase 4 row of "Migration path for the repo".

**Depends on:** phases 1, 2a and 2b (merged; `main` is the ground truth for them) and the two phase 3 plans, which are the contract for the code they add. See "Depends on" below for the exact list.

---

## Global Constraints

- bash 3.2 compatible everywhere: no `mapfile`, `declare -A`, `${var,,}`/`${var^^}`, `readarray`, `readlink -f`; no same-line `local` back-references (`local a=1 b=$a`); `10#$n` for arithmetic on a number that came from text. bash 3.2 mis-parses a quoted pattern containing `/` inside `${var//pat/repl}`: use `replace_literal` (`lib/files.sh`). Run `shopt -u patsub_replacement 2>/dev/null || true` before a `${var//}` replacement whose replacement text contains `&`. Nothing in this plan uses `${var//}`.
- BSD tools only: no GNU-only flags for `sed`, `grep`, `awk`, `date`, `mktemp`, `sort`, `readlink`, `stat`; no `\t` or `\n` inside a `sed` replacement; awk gets values through `ENVIRON`, never `-v`, when they may contain backslashes.
- Capability scripts and migrations start with `#!/usr/bin/env bash`, run as `bash -eu` with `lib/all.sh` loaded and `answers_load` done, use no `local`, and call mocked commands by bare name. `set -e` fires on a failing command anywhere in such a script, so a command that may fail harmlessly carries `|| warn ...` or sits in an `if`; never end a script, or write a statement in the middle of one, as a bare `[[ ]] && cmd` (in `bin/teeup`, which also runs under `set -eu`, use `if ... then ... fi`). Every mutation goes through `run_cmd`/`run_privileged` or a primitive with its own `DRY_RUN` guard (`write_managed_file`, `copy_config_once`, `refresh_config`, `backup_target`, `_state_touch`, `_defaults_record`, and this plan's `write_config_region`, `refresh_if_pristine`, `backup_copy`, `hook_run` and `migration_new`). `DRY_RUN=true` changes nothing.
- Paths: `user_config_dir` for `~/.config`; `TEEUP_CONFIG_DIR`, `TEEUP_STATE_DIR` and (new here) `TEEUP_MIGRATIONS_DIR` are honoured. Paths with spaces and metacharacters must work: `tests/lib/hooks.sh` uses a config dir named `con fig $HOME 'q' & co`, `tests/lib/migrations.sh` a migrations dir named `mig rations 'q' $x & co`, `tests/lib/files.sh` a config directory named `it's a & $dir`, and `tests/capabilities/zsh.sh` a config dir named `con fig $x`.
- Machine file precedence (answers, then `machines/<hostname>.conf`) for every consumer of an answer. This plan adds no answer; `TEEUP_SKIP` is honoured by `update`, `reset`, `remove` and every hook loop.
- `capability` metadata contract: `summary group tier requires provides packages casks apps interactive`. `teeup update <cap>` and the generic `teeup remove <cap>` read `packages` and `casks` from it, and `remove` reads `requires` of every other installed capability. No capability is added or moved between tiers here, so `capabilities/core.list` and `capabilities/daily.list` are untouched.
- Tests: `tests/helper.sh` (temp `HOME`, `MOCK_BIN` first on the narrowed `PATH` `$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin`, `mock_command`, `mock_command_script`, `mock_macos_base`, `TEEUP_TEST_MISSING`, `TEEUP_PKG_PREFIX`, `TEEUP_APPS_DIR`, and 3b's `hide_host_commands`). The narrowed `PATH` hides Homebrew but not `/usr/bin`: `git` is on every developer machine and both CI runners, so every test of `teeup update` mocks `git` rather than relying on the checkout's state; the checkout itself is whatever `TEEUP_PATH` is (the repository the tests run from), worktree or plain clone, and `_update_checkout`'s own checks must not care which. `lib/ui.sh` uses `gum` whenever `TEEUP_NO_GUM` is empty and `gum` is on `PATH`, and the narrowed `PATH` still exposes a host `/usr/bin/gum`, so a test that can reach `ui_confirm` or `ui_choose` exports `TEEUP_NO_GUM=1` (as `tests/cli.sh`, `tests/bootstrap.sh`, `tests/capabilities/secrets.sh` and 3b's `ai` and `colima` suites do). CI runs `macos-14`, `macos-15-intel` and `ubuntu-latest`; a test that passes on only one of them, or only on a developer's machine, is a defect.
- Every task ends with `./tests/run.sh` green, `./bin/teeup commands --check` silent with exit 0, `shellcheck --severity=warning` clean on every new or edited script and test, `git diff --check` clean, and **one** commit with a plain imperative subject and no trailer of any kind (no `Co-Authored-By`, no `Claude-Session`, no "Generated with").
- Suite counts: `tests/run.sh` ends with `All N suites passed.` Never hard-code N. Each task states "the suite count printed before this task, plus K". Per-suite counts (`Summary: x/y passed`) are exact.
- Nothing in this phase has run on a real Mac. Each task carries a **Real-Mac risk** note naming what only hardware proves.
- Verify, do not guess: every CLI flag, subcommand and exit-status claim below was checked against the installed tool's `--help` or upstream documentation on 2026-09-16; the sources are in the Self-review. A flag that does not appear there is not to be introduced during execution without the same check.
- Plain prose in every comment, log line and doc: none of "No X, no Y" chains, "That's the whole ...", "Don't X it. Y it.", "Sit with that", "You already know", "is the entire", "The punchline", "Worth naming", "X is real, and ...".

---

## Depends on

Everything below already exists when this plan runs. `main` is the authority for the first group; the phase 3 plan text is the authority for the second, and the executor's pre-flight scan should reconcile against the files themselves.

**From `main` (phases 1, 2a, 2b).**

| Interface | Where |
|---|---|
| `run_cmd`, `run_logged`, `have`, `log`/`ok`/`warn`/`err`/`die`, `user_config_dir`, `is_macos`, `macos_major` | `lib/core.sh` |
| `file_sha`, `stock_record`, `stock_sha`, `write_managed_file`, `backup_target`, `copy_config_once`, `refresh_config`, `replace_literal` | `lib/files.sh` |
| `state_done` (`check`, `mark`, `clear`, `ensure`), `state_migration_done`, `state_migration_mark` | `lib/state.sh` |
| `cap_dir`, `cap_exists`, `cap_list`, `cap_meta_get`, `cap_tier_list`, `cap_order`, `cap_skipped`, `cap_run`, `cap_run_optional`, `cap_check` | `lib/capability.sh` |
| `pkg_backend`, `pkg_backend_label`, `package_candidates`, `pkg_installed`, `pkg_install`, `casks_supported`, `cask_installed`, `cask_install`, `run_privileged`, `_pkg_backend_resolve` | `lib/pkg.sh` |
| `defaults_write`, `defaults_restore`, `_defaults_record_path`, `_defaults_flag`, `_defaults_bool`, `launchagent_remove`, `appearance` | `lib/macos.sh` |
| `theme_set`, `theme_current`, `theme_dir`, `theme_list` | `lib/theme.sh` |
| `font_set`, `font_file`, `font_current` | `lib/font.sh` |
| `answers_get`, `answers_load`, `machine_get` | `lib/answers.sh` |
| `$TEEUP_STATE_DIR/{done,toggles,migrations,shims,logs,current,stock}`, `$TEEUP_CONFIG_DIR/hooks`, the `~/.local/bin/teeup` link | `capabilities/teeup-runtime/configure` |
| the `migrations/*.sh` marking loop this plan replaces | `bootstrap`, section 7 |
| `capabilities/macos-defaults/{configure,remove}`, `capabilities/aerospace/configure`, `capabilities/keyboard/remove`, `capabilities/starship/config/starship.toml`, `capabilities/theme/{configure,theme-apply}`, `capabilities/zsh/{configure,home/*}` | the capabilities this plan edits |
| `mock_defaults_db`, `seed_default`, `mock_defaults_absent` | `tests/lib/macos.sh` and `tests/capabilities/macos-defaults.sh` (each file has its own copy) |

**From plan 3a (`docs/superpowers/plans/2026-09-13-redesign-phase3a-daily-tier.md`).**

| Interface | Task |
|---|---|
| The editor hook gate: a `theme-apply`/`font-apply` acts only when `state_done check "cap-$TEEUP_CAP"` succeeds or `TEEUP_CONFIGURING` equals `$TEEUP_CAP` (contract 4) | Tasks 2, 3, 5, 6 |
| `capabilities/emacs/remove` (`launchagent_remove sh.teeup.emacs`), `casks="emacs-app"` / `packages="emacs"` metadata | Task 2 |
| `json_set_key`, `json_merge_key`, `json_quote` in `lib/files.sh` (this plan calls none of them, but Task 3 below edits the same file) | Task 1 |
| `capabilities/daily.list` holding `emacs zed firefox-developer-edition obsidian` | Tasks 2 to 4 |

**From plan 3b (`docs/superpowers/plans/2026-09-13-redesign-phase3b-lazy-runtime.md`).**

| Interface | Task |
|---|---|
| `lib/all.sh`'s source loop, ending `... capability macos theme font lazy mise` — this plan appends `hooks` then `migrations` | Tasks 1, 2 |
| `have` returns 1 for a command that resolves inside `$TEEUP_STATE_DIR/shims/` | Task 1 |
| `lib/mise.sh`: `mise_global_state`, `mise_ensure_global`, `mise_wrapper_write`, `dev_env_install`, `dev_env_installed`, and the rule that every mise call outside a wrapper is `mise -C / ...` | Task 2 |
| `shims_generate` and `$TEEUP_STATE_DIR/shims`, regenerated by `teeup configure teeup-runtime` | Task 3 |
| `bin/teeup`'s verb table and `usage()` after `lazy-run`, `launch` and `install dev-env` | Tasks 3, 4 |
| `tests/cli.sh`'s `make_cap` fixture helper and `$TEEUP` | Tasks 1, 3, 4 |
| `capabilities/colima`, `ai`, `herdr`, `tmux`, `ollama`, `cursor` with `packages=`/`casks=` metadata the generic `remove` reads | Tasks 5 to 10 |

**Seam with the other phase 4 and 5 plans.** 4a owns `bin/teeup`'s `update`, `reset`, `remove` and `dev` verbs, `lib/hooks.sh` and `lib/migrations.sh`. 4b adds `doctor`, `menu`, `config` and two more `dev` subcommands (appended as new case arms in `cmd_dev`, which Task 4 creates). 4c and 4d add no verb; 4d adds `tests/lib/themes.sh` and edits `tests/bootstrap.sh` around the wizard's theme question and `README.md` around the Editors section, none of which this plan touches. 5a adds `migrate` and reuses `backup_copy` and `refresh_if_pristine` from Task 3.

---

## Contracts this plan publishes

1. **Hook events** (`lib/hooks.sh`). `TEEUP_HOOK_EVENTS` is `post-bootstrap post-update theme-set`. `hook_run <event> [args...]` runs every file in `$TEEUP_CONFIG_DIR/hooks/<event>.d/` that does not end in `.sample`, in file-name order, as `bash <file> [args...]` with stdin on `/dev/null`, `TEEUP_HOOK_EVENT` in the environment and `run_logged` brackets around each. It always returns 0: a hook that fails warns and the rest still run. An unknown event warns and returns 0. In a dry run each hook is named and none runs. `post-bootstrap` gets no arguments, `post-update` gets the capability name after `teeup update <cap>` and nothing after a full update, `theme-set` gets the theme name.
2. **The hook gate for capabilities** (`lib/capability.sh`). `cap_hook_eligible <name>` is true when `state_done check "cap-<name>"` succeeds or `TEEUP_CONFIGURING` equals `<name>`. `cap_run_hooks <verb>` runs `<verb>` through `cap_run_optional` for every eligible capability. `theme_set` and `font_set` call it instead of looping themselves, so a capability teeup never installed is never handed a theme or a font.
3. **The stock-checksum rule** (`lib/files.sh`). `config_is_pristine <dest>` is true when `<dest>` is a regular file with a stock record it still hashes to. `write_config_region <dest> <label>` (content on stdin) rewrites a user-owned file through `write_managed_file` and re-records its stock sha when it was pristine, so teeup's own managed-region rewrite never makes the file read as user-edited; it refuses a symlink with a warning and exit 1. `refresh_if_pristine <src> <dest>` replaces a pristine `<dest>` with `<src>` and follows with the record, installs a missing one through `copy_config_once`, and leaves an edited one alone with a log line and exit 1. `backup_copy <path>` copies rather than moves and prints the backup path on stdout.
4. **Migrations** (`lib/migrations.sh`). `TEEUP_MIGRATIONS_DIR` defaults to `$TEEUP_PATH/migrations`. A migration is `<unix-epoch>.sh` there. `migrations_list` prints them oldest first, `migrations_pending` those with no marker, `migrations_mark_all` marks every one without running it (what `bootstrap` does once), `migration_run <name>` runs one as `bash -eu` with `lib/all.sh` and the answers loaded and marks it only on success, `migrations_run_pending` runs the pending ones and stops at the first failure, `migration_refresh <capability>` re-runs that capability's `configure` with the stock-checksum rule in force, and `migration_new` creates the next file from the checkout's last commit time and prints its path.
5. **`teeup update [<capability>]`.** Without an argument: pull the checkout (refusing a dirty tree), run pending migrations, update and upgrade the package manager, `mise -C / upgrade`, re-run `configure` for every installed core capability, regenerate the theme, then `hook_run post-update`. With a capability: upgrade the packages and casks its metadata names, re-run its `configure`, then `hook_run post-update <capability>`. Exit 0 when every step succeeded, 1 when any of them warned.
6. **`teeup reset <capability>`** re-runs the capability's `configure` with `TEEUP_RESET` naming it, which turns each `copy_config_once` into `refresh_config` (back up, replace, print the diff, drop the backup when nothing changed), then runs the theme and font hooks so the reset file carries the current theme and font.
7. **`teeup remove <capability>`** refuses while another installed capability requires it, runs `capabilities/<name>/remove` when there is one (machine state: LaunchAgents, `defaults`, `hidutil`), then uninstalls the `casks` and `packages` its metadata names, then clears `done/cap-<name>`. Configuration files are left in place and named.
8. **Package-manager verbs** (`lib/pkg.sh`). `pkg_update`, `pkg_upgrade_all`, `pkg_upgrade <pkg>`, `cask_upgrade <cask>`, `pkg_uninstall <pkg>`, `cask_uninstall <cask>`, each with the Homebrew and MacPorts branch and each a no-op with a log line where the backend cannot do it.
9. **`defaults_write` change detection** (`lib/macos.sh`). A key that already holds the value teeup is about to write, as the type teeup writes, is left alone with `Already set: <domain> <key>`. Every key that is written adds its domain to `TEEUP_DEFAULTS_CHANGED`; `defaults_changed <domain>` reads it, so `macos-defaults/configure` restarts Finder or the Dock only when one of their keys changed in that run.

---

## Decisions made here

1. **A dirty checkout stops the whole update; every other failure is a warning.** Spec section 9 says the pull "refuses on a dirty tree, tells the user". Refusing only the pull and carrying on would run migrations and configures from a half-edited working tree, which is the state most likely to produce something the user did not mean. Everything after the pull is idempotent and individually useful, so one failing step must not cancel the other fifteen: each warns, and `teeup update` exits 1 at the end if any of them did. The one exception is a failed migration (decision 3).
2. **A failed `git pull` is a warning, not a stop, and there is no connectivity probe.** `teeup update` on a plane, or behind a proxy that blocks GitHub, still runs pending migrations, re-renders every config and regenerates the theme from the checkout that is already there — which is also the repair path after a half-finished bootstrap. Probing the network first would add a failure mode (a captive portal that answers everything) without changing what the command can do. `brew update`, `brew upgrade` and `mise upgrade` follow the same rule for the same reason.
3. **A failed migration stops the update.** Migrations are written against the state the previous one leaves, so running the next one on top of a failure can do the damage the failed one existed to prevent. The failed migration keeps no marker and runs again on the next `teeup update`; the error names it and says what to do.
4. **MacPorts gets `port selfupdate` and `port upgrade outdated`, and a non-zero exit from either is a warning.** Spec section 9 names both commands. MacPorts does not document the exit status of `port upgrade outdated` when nothing is outdated, and a package manager that reports "nothing to do" as a failure must not fail an update; the same rule already covers a formula that will not build. Casks do not exist on MacPorts, so `cask_upgrade` and `cask_uninstall` log and return 0 there, matching `cask_install`'s existing behaviour.
5. **`teeup update <cap>` upgrades what the metadata names, then configures.** Spec section 9: "only that capability's packages and configure". `pkg_upgrade` and `cask_upgrade` skip anything not installed on this machine with a log line, so `teeup update colima` on a Mac that never installed it says so instead of installing it by surprise; `teeup install` is the verb that installs.
6. **`update` configures only core capabilities that are installed here.** Spec section 9 says "re-run configure for `core.list`". A core capability that this machine has never installed (`TEEUP_SKIP`, or a bootstrap that stopped early) has no configuration to re-run, and `configure` for it would be the first half of an install nobody asked for. It is named with the `teeup install` hint instead. Daily and lazy capabilities are not configured: the spec lists `core.list` only, and a lazy capability's configure can start a VM.
7. **The theme is regenerated once, not twice.** `theme` is in `core.list`, so the configure loop has already re-rendered every template through `theme_set`. Update falls back to `theme_set "$(theme_current)"` only when the loop did not run `theme` (it is skipped, or not installed here), which is the same guard `bootstrap` already uses with `CONFIGURED_THIS_RUN`.
8. **Hooks are the user's scripts, so a dry run names them and runs none.** `DRY_RUN=true` is teeup's promise that nothing changes; nothing says a hook the user wrote honours it.
9. **A hook runs with `bash <file>`, not `"$file"`.** No executable bit to explain, no `chmod` in the documentation, and the same rule for every event. `.sample` files are skipped by suffix, so the installed documentation can sit in the same directory.
10. **Samples are teeup's files and are rewritten; everything else in the directory is the user's and is never touched.** `write_managed_file` gives "Already current" on a re-run and rewrites a sample whose text changed in a new teeup version, which is what makes the documentation follow the code.
11. **Theme and font hooks run only for installed capabilities, through `cap_run_hooks`, and `cap_run_optional` keeps its meaning.** `cap_run_optional` is "run this hook if the capability ships one"; which capabilities get a hook is the caller's policy, so the gate lives in a new function next to it. Without the gate, `teeup theme set` on a core-only Mac probes for a Neovim and an Emacs the user never asked teeup to install (pr11's deferred list, and plan 3a's Decision 5, which this generalises to every capability).
12. **The capability being configured is eligible for its own hooks.** On a first bootstrap `theme configure` runs before `run_capability` marks `cap-theme`, and its own `theme-apply` is what writes the starship palette. `capabilities/theme/configure` exports `TEEUP_CONFIGURING="$TEEUP_CAP"`, the variable plan 3a's editor hooks already read, and `cap_hook_eligible` honours it.
13. **`reset` and a migration's refresh both go through the capability's `configure`.** The alternative, copying `capabilities/<cap>/config/<file>` to `$(user_config_dir)/<file>`, is wrong for every file a capability renders (zsh's three home stubs carry the `%q`-quoted env path, git's config carries the resolved include paths) and for every file whose destination is not under `~/.config` (ssh's `~/.ssh/config`) or is conditional (aerospace skips its copy when `~/.aerospace.toml` exists). Re-running `configure` with one variable set reuses all of that logic, so there is one code path to keep correct instead of one per capability. The cost is that `configure`'s other work runs too; it is idempotent by contract, and `teeup configure <cap>` is a command the user can already run.
14. **`TEEUP_RESET` and `TEEUP_REFRESH` are scoped by name.** `copy_config_once` acts on them only when they equal `TEEUP_CAP`, and `cap_run` restores `TEEUP_CAP` after a nested run, so `ssh configure` re-running `git configure` inside a `teeup reset ssh` does not reset git's files too. Each variable is also cleared for the nested call (a prefix assignment), because `refresh_config` and `refresh_if_pristine` come back to `copy_config_once` for a file that is missing.
15. **`reset` requires an installed capability that ships config files.** Resetting something that was never installed would be an install with a different name, and resetting a capability with no `config/` or `home/` directory would print nothing and look broken; both say what they are instead.
16. **`remove` runs the capability's `remove` script in addition to the metadata uninstall, not instead of it.** Five capabilities ship a `remove` script: the two on `main` (`macos-defaults`, `keyboard`), plan 3a's (`emacs`), and task 7's own two (`colima`, stopping the VM before its formula comes off, and `ai`, deleting the mise wrappers `configure` wrote, since `packages=`/`casks=` are both empty). All five undo machine state rather than a package, so a script that also had to uninstall its own cask would repeat what metadata already says. The script runs first, while the tool is still installed. A capability with neither a `remove` script nor any packages or casks (`xcode-clt`, `package-manager`) has nothing `teeup remove` can undo, and dies rather than claim it did.
17. **`remove` refuses while another installed capability requires it.** `teeup remove package-manager` on a working machine would leave fifteen capabilities pointing at a package manager that is gone. The message names the dependents and the order to remove them in; there is no `--force`, because `teeup remove` on each dependent is the same command.
18. **`remove` leaves configuration and state files in place.** The user's `~/.config/nvim` is theirs, spec section 7 gives no rule for deleting it, and a removal that took the configuration with it could not be undone by re-installing. The `done/cap-<name>` marker and the recorded `defaults` are the exceptions: the marker is teeup's own bookkeeping, and `macos-defaults/remove` restoring what it recorded is the point of that record.
19. **`teeup dev add-migration` names the file from the checkout's last commit time.** Spec section 9, and Omarchy's `omarchy-dev-add-migration`. A migration written on top of the newest commit then sorts after every migration that commit already carries, whatever the author's clock says. A second migration for the same commit takes the next free second; a checkout with no git history falls back to the current time with a warning.
20. **`bootstrap` marks every shipped migration applied on a machine it has never finished on.** This is `main`'s behaviour, moved into `migrations_mark_all`: the capabilities have just installed the state those migrations lead to, so running them would be redundant at best.
21. **`defaults_write` reads before it writes.** Two extra `defaults` calls per key buy a `teeup update` that does not close every Finder window and re-hide the Dock on a machine where nothing changed (pr11's deferred list). A value of the right type that already matches is left alone; a value of a different type is a change, because teeup writing `-bool true` over a hand-set `-string YES` is a real edit.
22. **The AeroSpace Accessibility block prints in full once per machine.** `teeup update` re-runs every core `configure`, and a five-line manual step on every run is how people learn to skip it. `state_done ensure` is the existing once-per-machine primitive; later runs print one line that still says where the setting is.

---

## File structure

| Path | Responsibility |
|---|---|
| `lib/hooks.sh` | New. `TEEUP_HOOK_EVENTS`, `hooks_dir`, `hook_run`. |
| `lib/migrations.sh` | New. The migration list, runner, markers, `migration_refresh` and `migration_new`. |
| `lib/capability.sh` | `cap_hook_eligible`, `cap_run_hooks`, and `cap_run` restoring `TEEUP_CAP` after a nested run. |
| `lib/files.sh` | `config_is_pristine`, `write_config_region`, `refresh_if_pristine`, `backup_copy`, and the `TEEUP_REFRESH`/`TEEUP_RESET` seams at the top of `copy_config_once`. |
| `lib/pkg.sh` | `pkg_update`, `pkg_upgrade_all`, `pkg_upgrade`, `cask_upgrade`, `pkg_uninstall`, `cask_uninstall`. |
| `lib/mise.sh` | `mise_upgrade`. |
| `lib/macos.sh` | `defaults_write` change detection, `_defaults_same`, `defaults_changed`, `TEEUP_DEFAULTS_CHANGED`. |
| `lib/theme.sh`, `lib/font.sh` | the hook loop becomes `cap_run_hooks`; `theme_set` ends with `hook_run theme-set`. |
| `lib/all.sh` | the source loop gains `hooks` and `migrations`. |
| `bin/teeup` | `cmd_update`, `cmd_reset`, `cmd_remove`, `cmd_dev`, their verb table entries and their `usage()` lines. |
| `bootstrap` | `migrations_mark_all`, and `hook_run post-bootstrap` before the summary. |
| `capabilities/teeup-runtime/` | `configure` installs one `.sample` per event; `default/hooks/*.sample` are the three documents. |
| `capabilities/theme/` | `configure` exports `TEEUP_CONFIGURING`; `theme-apply` writes through `write_config_region`. |
| `capabilities/macos-defaults/configure`, `capabilities/aerospace/configure` | restart what changed; print the manual step once. |
| `.github/workflows/ci.yml` | the shellcheck step covers the samples and `migrations/*.sh`. |
| `tests/lib/hooks.sh`, `tests/lib/migrations.sh` | two new suites. |
| `tests/lib/{capability,files,theme,font,macos,pkg,mise}.sh`, `tests/capabilities/{teeup-runtime,theme,starship,zsh,macos-defaults,aerospace}.sh`, `tests/cli.sh`, `tests/bootstrap.sh` | the behaviour each task adds. |
| `README.md`, `CONTRIBUTING.md` | the lifecycle commands, the hooks section, and four contributor items. |

**Reading this plan mechanically.** Every fenced block whose info string carries `file=<path>` is the complete content of that file after the step. Every edit to an existing file is a pair of blocks, `edit-old=<path>` (text that exists at that point, quoted exactly and occurring exactly once in the file) followed by `edit-new=<path>` (what replaces it). Blocks without either marker are commands or illustrations and change nothing. A block whose own content contains triple backticks is fenced with four.

---

### Task 1: Theme and font hooks run only for capabilities teeup installed

`teeup theme set` and `teeup install font <name>` currently run every capability's `theme-apply` and `font-apply`, installed or not, so a core-only Mac gets an `emacsclient` probe and a `code --list-extensions` call for editors it does not have (pr11's deferred list; plan 3a's Decision 5 guards its own four hooks and this generalises the rule). The gate goes next to `cap_run_optional`, which keeps its meaning.

**Files:**
- Modify: `lib/capability.sh` (after `cap_run_optional`), `lib/theme.sh` (`theme_set`'s hook loop), `lib/font.sh` (`font_set`'s hook loop), `capabilities/theme/configure`
- Test: `tests/lib/capability.sh`, `tests/lib/theme.sh`, `tests/lib/font.sh`, `tests/capabilities/wezterm.sh`

**Interfaces:**
- Consumes: `cap_list`, `cap_run_optional`, `cap_skipped` (`lib/capability.sh`); `state_done check` (`lib/state.sh`); `TEEUP_CAP`, exported by `cap_run`; plan 3a's `TEEUP_CONFIGURING` convention.
- Produces: `cap_hook_eligible <name>` (exit 0 when the capability is installed here or is the one being configured) and `cap_run_hooks <verb>` (runs `<verb>` for every eligible capability, always returns 0). Tasks 5 and 6 call `cap_run_hooks`; Task 2's `theme_set` change sits next to it.

**Real-Mac risk:** none new. The risk this removes is real hardware only: on a Mac with somebody else's Neovim in `/usr/local/bin`, the ungated hook sent `<Cmd>lua require("teeup.neovim").apply()<CR>` to whatever Neovim was running.

- [ ] **Step 1: Write the failing tests for the gate**

Append to `tests/lib/capability.sh`, before its `echo "lib/capability.sh"` line:

```bash edit-old=tests/lib/capability.sh
echo "lib/capability.sh"
run_test "list and exists" test_list_and_exists
```

```bash edit-new=tests/lib/capability.sh
test_hook_eligible_needs_the_marker_or_a_running_configure() {
  setup
  cap_hook_eligible alpha && { echo "alpha was never installed"; return 1; }
  state_done mark cap-alpha
  cap_hook_eligible alpha || { echo "an installed capability is eligible"; return 1; }
  TEEUP_CONFIGURING=beta cap_hook_eligible beta || { echo "the capability being configured is eligible"; return 1; }
  TEEUP_CONFIGURING=alpha cap_hook_eligible beta && { echo "only the capability named by TEEUP_CONFIGURING"; return 1; }
  cleanup_test_env
}

test_run_hooks_skips_capabilities_that_were_never_installed() {
  setup
  local name
  for name in alpha beta lazyone; do
    printf '#!/usr/bin/env bash\necho "hook:%s"\n' "$name" > "$TEEUP_CAPS_DIR/$name/font-apply"
    chmod +x "$TEEUP_CAPS_DIR/$name/font-apply"
  done
  state_done mark cap-alpha
  state_done mark cap-lazyone
  local out rc=0
  out="$(TEEUP_SKIP=lazyone cap_run_hooks font-apply 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "hook:alpha" || return 1
  assert_not_contains "$out" "hook:beta" "beta was never installed" || return 1
  assert_not_contains "$out" "hook:lazyone" "a skipped capability stays skipped" || return 1
  cleanup_test_env
}

echo "lib/capability.sh"
run_test "list and exists" test_list_and_exists
```

```bash edit-old=tests/lib/capability.sh
run_test "run_optional warns but succeeds on failure" test_run_optional_warns_but_succeeds_on_failure
print_summary
```

```bash edit-new=tests/lib/capability.sh
run_test "run_optional warns but succeeds on failure" test_run_optional_warns_but_succeeds_on_failure
run_test "hook eligible needs the marker or a running configure" test_hook_eligible_needs_the_marker_or_a_running_configure
run_test "run_hooks skips capabilities that were never installed" test_run_hooks_skips_capabilities_that_were_never_installed
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/lib/capability.sh`
Expected: the two new tests fail with `cap_hook_eligible: command not found` and `cap_run_hooks: command not found`; the suite ends with `Summary: 17/19 passed`.

- [ ] **Step 3: Add the gate to `lib/capability.sh`**

```bash edit-old=lib/capability.sh
cap_run_optional() {
  local name="$1" verb="$2"
  if cap_skipped "$name"; then return 0; fi
  [[ -f "$(cap_dir "$name")/$verb" ]] || return 0
  cap_run "$name" "$verb" || warn "$name $verb failed; continuing."
  return 0
}
```

```bash edit-new=lib/capability.sh
cap_run_optional() {
  local name="$1" verb="$2"
  if cap_skipped "$name"; then return 0; fi
  [[ -f "$(cap_dir "$name")/$verb" ]] || return 0
  cap_run "$name" "$verb" || warn "$name $verb failed; continuing."
  return 0
}

# cap_hook_eligible <name>
# A theme-apply or font-apply hook pushes the current theme or font into a tool
# teeup set up. A capability that was never installed has set nothing up, and
# a tool of the same name on the machine is not teeup's to drive, so its hooks
# wait until `teeup install` (or bootstrap) has marked it installed. The one
# exception is the capability whose own configure is running, before that
# marker exists: its configure exports TEEUP_CONFIGURING with its name, the
# same variable plan 3a's editor hooks check.
cap_hook_eligible() {
  if state_done check "cap-$1"; then return 0; fi
  [[ "${TEEUP_CONFIGURING:-}" == "$1" ]]
}

# cap_run_hooks <verb>
# Runs <verb> for every eligible capability that ships it, through
# cap_run_optional (so a skipped capability is left out and a failing hook
# warns). A for loop over a captured list, not `while read ... < <(cap_list)`:
# an interactive=true capability's hook inherits stdin, and reading it would
# swallow the names of the capabilities still waiting for their hooks.
cap_run_hooks() {
  local verb="$1" cap
  for cap in $(cap_list); do
    if cap_hook_eligible "$cap"; then
      cap_run_optional "$cap" "$verb"
    fi
  done
  return 0
}
```

- [ ] **Step 4: Run the capability suite**

Run: `bash tests/lib/capability.sh`
Expected: `Summary: 19/19 passed`.

- [ ] **Step 5: Point `theme_set` and `font_set` at the gate**

```bash edit-old=lib/theme.sh
theme_set() {
  local name="$1" dir mode tpl base out current next cap failed=0 missing user_bases cap_bases
```

```bash edit-new=lib/theme.sh
theme_set() {
  local name="$1" dir mode tpl base out current next failed=0 missing user_bases cap_bases
```

```bash edit-old=lib/theme.sh
  export TEEUP_THEME_DIR TEEUP_THEME_NAME
  # A for loop over a captured list, not `while read ... < <(cap_list)`: an
  # interactive=true capability's hook inherits stdin, and reading it would
  # swallow the names of the capabilities still waiting for their hooks.
  for cap in $(cap_list); do
    cap_run_optional "$cap" theme-apply
  done
}
```

```bash edit-new=lib/theme.sh
  export TEEUP_THEME_DIR TEEUP_THEME_NAME
  cap_run_hooks theme-apply
}
```

```bash edit-old=lib/font.sh
font_set() {
  local requested="${1:-}" family cask cap
```

```bash edit-new=lib/font.sh
font_set() {
  local requested="${1:-}" family cask
```

```bash edit-old=lib/font.sh
  export TEEUP_FONT_FAMILY
  # A for loop, not `while read < <(cap_list)`: see theme_set's hook loop.
  for cap in $(cap_list); do
    cap_run_optional "$cap" font-apply
  done
  ok "Font set to $family"
```

```bash edit-new=lib/font.sh
  export TEEUP_FONT_FAMILY
  cap_run_hooks font-apply
  ok "Font set to $family"
```

- [ ] **Step 6: Let the theme capability's own hook run during its configure**

On a first bootstrap `theme configure` runs before `run_capability` marks `cap-theme`, and the theme capability's own `theme-apply` is what writes the starship palette.

```bash edit-old=capabilities/theme/configure
# Re-running it is also how `teeup update` picks up new or changed templates,
# which is why theme_set always re-renders instead of skipping.
theme_set "$(answers_get TEEUP_THEME catppuccin)"
```

```bash edit-new=capabilities/theme/configure
# Re-running it is also how `teeup update` picks up new or changed templates,
# which is why theme_set always re-renders instead of skipping.
#
# theme_set runs theme-apply only for installed capabilities, and on a first
# bootstrap this one is marked installed after this script returns. Its own
# theme-apply writes the starship palette, so it is named as the capability
# being configured.
export TEEUP_CONFIGURING="$TEEUP_CAP"
theme_set "$(answers_get TEEUP_THEME catppuccin)"
```

- [ ] **Step 7: Update the suites whose fixtures were never installed**

```bash edit-old=tests/lib/theme.sh
test_set_renders_both_modes_and_runs_hooks() {
  setup
  make_fixture_theme
  make_fixture_caps
  local out state
```

```bash edit-new=tests/lib/theme.sh
test_set_renders_both_modes_and_runs_hooks() {
  setup
  make_fixture_theme
  make_fixture_caps
  state_done mark cap-demo
  local out state
```

```bash edit-old=tests/lib/theme.sh
  make_hook_cap aaa true theme-apply 'read -r line || true; echo "aaa read:[$line]"'
  make_hook_cap bbb false theme-apply 'echo "bbb applied"'
  local out
  out="$(theme_set fixture 2>&1 </dev/null)"
  assert_contains "$out" "aaa read:[]" || return 1
  assert_contains "$out" "bbb applied" || return 1
  cleanup_test_env
}
```

```bash edit-new=tests/lib/theme.sh
  make_hook_cap aaa true theme-apply 'read -r line || true; echo "aaa read:[$line]"'
  make_hook_cap bbb false theme-apply 'echo "bbb applied"'
  state_done mark cap-aaa
  state_done mark cap-bbb
  local out
  out="$(theme_set fixture 2>&1 </dev/null)"
  assert_contains "$out" "aaa read:[]" || return 1
  assert_contains "$out" "bbb applied" || return 1
  cleanup_test_env
}

test_set_runs_hooks_only_for_installed_capabilities() {
  setup
  make_fixture_theme
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  # Three capabilities ship a hook; only the one teeup installed, and the one
  # whose own configure is running, may be told about the new theme.
  make_hook_cap installed false theme-apply 'echo "hook:installed"'
  make_hook_cap never false theme-apply 'echo "hook:never"'
  make_hook_cap configuring false theme-apply 'echo "hook:configuring"'
  state_done mark cap-installed
  local out
  out="$(TEEUP_CONFIGURING=configuring theme_set fixture 2>&1)"
  assert_contains "$out" "hook:installed" || return 1
  assert_contains "$out" "hook:configuring" || return 1
  assert_not_contains "$out" "hook:never" "a capability that was never installed gets no hook" || return 1
  assert_not_contains "$out" "Starting: never theme-apply" "its hook is not even started" || return 1
  cleanup_test_env
}
```

```bash edit-old=tests/lib/theme.sh
run_test "set runs every hook after an interactive one" test_set_runs_every_hook_after_an_interactive_one
```

```bash edit-new=tests/lib/theme.sh
run_test "set runs every hook after an interactive one" test_set_runs_every_hook_after_an_interactive_one
run_test "set runs hooks only for installed capabilities" test_set_runs_hooks_only_for_installed_capabilities
```

```bash edit-old=tests/lib/font.sh
  local out
  out="$(font_set Hack)"
  assert_contains "$out" "font-applied:Hack Nerd Font" || return 1
  cleanup_test_env
}
```

```bash edit-new=tests/lib/font.sh
  local out
  out="$(font_set Hack)"
  assert_not_contains "$out" "font-applied" "a capability that was never installed gets no hook" || return 1
  state_done mark cap-demo
  out="$(font_set Hack)"
  assert_contains "$out" "font-applied:Hack Nerd Font" || return 1
  cleanup_test_env
}
```

```bash edit-old=tests/lib/font.sh
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$TEEUP_CAPS_DIR/$name/font-apply"
    chmod +x "$TEEUP_CAPS_DIR/$name/font-apply"
  done
```

```bash edit-new=tests/lib/font.sh
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$TEEUP_CAPS_DIR/$name/font-apply"
    chmod +x "$TEEUP_CAPS_DIR/$name/font-apply"
    state_done mark "cap-$name"
  done
```

```bash edit-old=tests/capabilities/wezterm.sh
test_theme_apply_reloads_the_config() {
  setup
  DRY_RUN=false "$TEEUP" configure wezterm >/dev/null
```

```bash edit-new=tests/capabilities/wezterm.sh
test_theme_apply_reloads_the_config() {
  setup
  # install, not configure: theme set runs hooks only for installed capabilities.
  DRY_RUN=false "$TEEUP" install wezterm >/dev/null
```

```bash edit-old=tests/capabilities/wezterm.sh
test_font_apply_reloads_the_config() {
  setup
  DRY_RUN=false "$TEEUP" configure wezterm >/dev/null
```

```bash edit-new=tests/capabilities/wezterm.sh
test_font_apply_reloads_the_config() {
  setup
  DRY_RUN=false "$TEEUP" install wezterm >/dev/null
```

- [ ] **Step 8: Run the four suites**

Run: `bash tests/lib/capability.sh && bash tests/lib/theme.sh && bash tests/lib/font.sh && bash tests/capabilities/wezterm.sh`
Expected: `Summary: 19/19 passed`, `Summary: 23/23 passed`, `Summary: 9/9 passed`, `Summary: 11/11 passed`.

- [ ] **Step 9: Full checks and commit**

```bash
./tests/run.sh
./bin/teeup commands --check
shellcheck --severity=warning lib/capability.sh lib/theme.sh lib/font.sh capabilities/theme/configure tests/lib/capability.sh tests/lib/theme.sh tests/lib/font.sh tests/capabilities/wezterm.sh
git diff --check
git add lib/capability.sh lib/theme.sh lib/font.sh capabilities/theme/configure tests/lib/capability.sh tests/lib/theme.sh tests/lib/font.sh tests/capabilities/wezterm.sh
git commit -m "Run theme and font hooks only for installed capabilities"
```

Expected: the suite count printed before this task, plus 0. `commands --check`, shellcheck and `git diff --check` print nothing.

---

### Task 2: `lib/hooks.sh`, the three events and their documented samples

Spec section 7's last bullet: "Hooks. `~/.config/teeup/hooks/<event>.d/` with `.sample` files; events `post-bootstrap`, `post-update`, `theme-set`." This task builds the runner, installs the three samples from `teeup-runtime configure`, and fires the two events that exist today (`post-update` arrives with `teeup update` in Task 6).

**Files:**
- Create: `lib/hooks.sh`, `capabilities/teeup-runtime/default/hooks/post-bootstrap.sample`, `capabilities/teeup-runtime/default/hooks/post-update.sample`, `capabilities/teeup-runtime/default/hooks/theme-set.sample`
- Modify: `lib/all.sh`, `lib/theme.sh` (end of `theme_set`), `bootstrap` (before the summary), `capabilities/teeup-runtime/configure`, `.github/workflows/ci.yml`
- Test: `tests/lib/hooks.sh` (new), `tests/capabilities/teeup-runtime.sh`, `tests/bootstrap.sh`

**Interfaces:**
- Consumes: `run_logged`, `warn`, `DRY_RUN` (`lib/core.sh`); `write_managed_file` (`lib/files.sh`); `run_cmd`; `TEEUP_CONFIG_DIR`; `TEEUP_CAP_DIR`, exported by `cap_run`.
- Produces: `TEEUP_HOOK_EVENTS="post-bootstrap post-update theme-set"`, `hooks_dir` (prints `$TEEUP_CONFIG_DIR/hooks`), `hook_run <event> [args...]` (always returns 0). Task 6 calls `hook_run post-update`; `theme_set` calls `hook_run theme-set "$name"` here.

**Real-Mac risk:** a hook that opens a GUI (`osascript -e 'display notification'`, the example in the samples) needs a logged-in session; under `launchctl` or ssh it fails, which is exactly the case the warning-and-continue rule covers. Whether `run_logged`'s `</dev/null` really keeps a hook that calls `read` from stalling a login-time bootstrap is only provable on a terminal.

- [ ] **Step 1: Write the failing suite**

```bash file=tests/lib/hooks.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  # A config directory with a space, a dollar sign, a quote and an ampersand:
  # hook paths reach run_logged, bash and the log line as data, never as code.
  export XDG_CONFIG_HOME="$TEST_HOME/con fig \$HOME 'q' & co"
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false
  HOOKS="$XDG_CONFIG_HOME/teeup/hooks"
}

# make_hook <event> <file name> <body>
make_hook() {
  mkdir -p "$HOOKS/$1.d"
  printf '#!/usr/bin/env bash\n%s\n' "$3" > "$HOOKS/$1.d/$2"
}

test_run_executes_every_hook_in_name_order_with_its_arguments() {
  setup
  make_hook theme-set 20-second.sh 'echo "second:$1:$TEEUP_HOOK_EVENT"'
  make_hook theme-set 10-first.sh 'echo "first:$1:$#"'
  local out first second
  out="$(hook_run theme-set "tokyo night" 2>&1)"
  assert_contains "$out" "first:tokyo night:1" || return 1
  assert_contains "$out" "second:tokyo night:theme-set" || return 1
  first="$(printf '%s\n' "$out" | grep -n 'first:' | cut -d: -f1)"
  second="$(printf '%s\n' "$out" | grep -n 'second:' | cut -d: -f1)"
  [[ "$first" -lt "$second" ]] || { echo "10-first.sh must run before 20-second.sh"; return 1; }
  cleanup_test_env
}

test_run_skips_samples_and_runs_a_hook_without_the_executable_bit() {
  setup
  make_hook post-update example.sample 'echo "sample ran"'
  make_hook post-update plain.sh 'echo "plain ran"'
  chmod 644 "$HOOKS/post-update.d/plain.sh"
  local out
  out="$(hook_run post-update 2>&1)"
  assert_not_contains "$out" "sample ran" || return 1
  assert_contains "$out" "plain ran" "hooks run with bash, so no chmod is needed" || return 1
  cleanup_test_env
}

test_a_failing_hook_warns_and_the_rest_still_run() {
  setup
  make_hook post-bootstrap 10-broken.sh 'echo "broken ran"; exit 3'
  make_hook post-bootstrap 20-fine.sh 'echo "fine ran"'
  local out rc=0
  out="$(hook_run post-bootstrap 2>&1)" || rc=$?
  assert_success "$rc" "a hook never fails its caller" || return 1
  assert_contains "$out" "broken ran" || return 1
  assert_contains "$out" "Hook $HOOKS/post-bootstrap.d/10-broken.sh failed (exit code 3); continuing." || return 1
  assert_contains "$out" "fine ran" || return 1
  cleanup_test_env
}

test_a_hook_cannot_read_the_terminal() {
  setup
  make_hook post-update ask.sh 'read -r answer || answer="<none>"; echo "answer:$answer"'
  local out
  out="$(printf 'yes\n' | hook_run post-update 2>&1)"
  assert_contains "$out" "answer:<none>" "stdin is /dev/null" || return 1
  cleanup_test_env
}

test_no_hook_directory_and_unknown_events_are_quiet() {
  setup
  local out rc=0
  out="$(hook_run theme-set catppuccin 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_equals "" "$out" || return 1
  out="$(hook_run pre-lunch 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "unknown event 'pre-lunch'" || return 1
  cleanup_test_env
}

test_dry_run_names_the_hooks_and_runs_none() {
  setup
  make_hook theme-set 10-touch.sh 'touch "$HOME/touched"'
  # shellcheck disable=SC2034  # last assignment in the file; read by hook_run
  DRY_RUN=true
  local out
  out="$(hook_run theme-set catppuccin)"
  assert_contains "$out" "[DRY-RUN] Would run hook: $HOOKS/theme-set.d/10-touch.sh catppuccin" || return 1
  [[ ! -e "$TEST_HOME/touched" ]] || { echo "a hook ran in dry run"; return 1; }
  cleanup_test_env
}

test_theme_set_runs_the_theme_set_hooks_with_the_name() {
  setup
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR"
  make_hook theme-set 10-name.sh 'echo "theme-set hook:$1"'
  mock_command defaults 1 ""
  local out
  out="$(theme_set catppuccin 2>&1)"
  assert_contains "$out" "theme-set hook:catppuccin" || return 1
  cleanup_test_env
}

echo "lib/hooks.sh"
run_test "run executes every hook in name order with its arguments" test_run_executes_every_hook_in_name_order_with_its_arguments
run_test "run skips samples and runs a hook without the executable bit" test_run_skips_samples_and_runs_a_hook_without_the_executable_bit
run_test "a failing hook warns and the rest still run" test_a_failing_hook_warns_and_the_rest_still_run
run_test "a hook cannot read the terminal" test_a_hook_cannot_read_the_terminal
run_test "no hook directory and unknown events are quiet" test_no_hook_directory_and_unknown_events_are_quiet
run_test "dry run names the hooks and runs none" test_dry_run_names_the_hooks_and_runs_none
run_test "theme set runs the theme-set hooks with the name" test_theme_set_runs_the_theme_set_hooks_with_the_name
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/lib/hooks.sh`
Expected: every test fails with `hook_run: command not found`; the suite ends with `Summary: 0/7 passed`.

- [ ] **Step 3: Write the library**

```bash file=lib/hooks.sh
#!/usr/bin/env bash
# hooks.sh - the user's own scripts, run when teeup finishes something.
# $TEEUP_CONFIG_DIR/hooks/<event>.d/ holds any number of scripts. Each one runs
# with bash, in file name order, with the event's arguments; a *.sample file is
# documentation and never runs. A hook that fails warns and never aborts what
# fired it (spec section 7; Omarchy's omarchy-hook does the same).
#
#   post-bootstrap   after ./bootstrap, before its summary        (no arguments)
#   post-update      at the end of teeup update                  ($1: the capability, or nothing)
#   theme-set        after a theme is rendered and applied        ($1: the theme name)
#
# Requires core.sh.

TEEUP_HOOK_EVENTS="post-bootstrap post-update theme-set"
export TEEUP_HOOK_EVENTS

hooks_dir() { printf '%s/hooks\n' "$TEEUP_CONFIG_DIR"; }

# hook_run <event> [args...]
# Always returns 0. stdin is /dev/null (run_logged with interactive=false), so
# a hook that prompts cannot stall an update. In a dry run the hooks are named
# and not run: they are the user's scripts, and nothing says they honour
# DRY_RUN.
hook_run() {
  local event="$1" dir f rc
  shift
  case " $TEEUP_HOOK_EVENTS " in
    *" $event "*) ;;
    *)
      warn "hook_run: unknown event '$event' (expected one of: $TEEUP_HOOK_EVENTS)"
      return 0
      ;;
  esac
  dir="$(hooks_dir)/$event.d"
  [[ -d "$dir" ]] || return 0
  for f in "$dir"/*; do
    [[ -f "$f" ]] || continue
    case "$f" in *.sample) continue ;; esac
    if [[ "$DRY_RUN" == "true" ]]; then
      printf "%b %s\n" "🔍" "[DRY-RUN] Would run hook: $f $*"
      continue
    fi
    rc=0
    run_logged "hook $event ${f##*/}" false env TEEUP_HOOK_EVENT="$event" bash "$f" "$@" || rc=$?
    if [[ $rc -ne 0 ]]; then
      warn "Hook $f failed (exit code $rc); continuing."
    fi
  done
  return 0
}
```

- [ ] **Step 4: Load it and fire the theme-set event**

```bash edit-old=lib/all.sh
for _teeup_lib in files state answers pkg ui capability macos theme font lazy mise; do
```

```bash edit-new=lib/all.sh
for _teeup_lib in files state answers pkg ui capability macos theme font lazy mise hooks; do
```

```bash edit-old=lib/theme.sh
# theme_set <name>
# Render both modes into a staging directory, swap it into place, record the
# name, then let every capability pick the new files up. Rendering into a
```

```bash edit-new=lib/theme.sh
# theme_set <name>
# Render both modes into a staging directory, swap it into place, record the
# name, then let every installed capability pick the new files up and run the
# user's theme-set hooks (lib/hooks.sh). Rendering into a
```

```bash edit-old=lib/theme.sh
  export TEEUP_THEME_DIR TEEUP_THEME_NAME
  cap_run_hooks theme-apply
}
```

```bash edit-new=lib/theme.sh
  export TEEUP_THEME_DIR TEEUP_THEME_NAME
  cap_run_hooks theme-apply
  hook_run theme-set "$name"
}
```

- [ ] **Step 5: Run the new suite**

Run: `bash tests/lib/hooks.sh`
Expected: `Summary: 7/7 passed`.

- [ ] **Step 6: Write the three samples**

```bash file=capabilities/teeup-runtime/default/hooks/post-bootstrap.sample
#!/usr/bin/env bash
# post-bootstrap hook sample, installed by teeup and rewritten when teeup's
# copy changes. It never runs: teeup skips every *.sample file.
#
# To add a hook, put a script of your own next to this file, for example
# post-bootstrap.d/10-dock.sh. Every file in this directory that does not end
# in .sample runs with bash, in name order, after ./bootstrap has installed
# and configured everything and before it prints its summary. It gets no
# arguments; TEEUP_PATH, TEEUP_CONFIG_DIR, TEEUP_STATE_DIR and
# TEEUP_HOOK_EVENT=post-bootstrap are in its environment. Its stdin is
# /dev/null, and a hook that fails prints a warning and bootstrap carries on.
#
# Example: a notification when a long bootstrap is done.
# osascript -e 'display notification "Bootstrap finished" with title "teeup"'
```

```bash file=capabilities/teeup-runtime/default/hooks/post-update.sample
#!/usr/bin/env bash
# post-update hook sample, installed by teeup and rewritten when teeup's copy
# changes. It never runs: teeup skips every *.sample file.
#
# To add a hook, put a script of your own next to this file, for example
# post-update.d/10-brew-cleanup.sh. Every file in this directory that does not
# end in .sample runs with bash, in name order, at the end of `teeup update`.
# After a full `teeup update` it gets no arguments; after `teeup update <cap>`
# it gets the capability name as $1. TEEUP_PATH, TEEUP_CONFIG_DIR,
# TEEUP_STATE_DIR and TEEUP_HOOK_EVENT=post-update are in its environment. Its
# stdin is /dev/null, and a hook that fails prints a warning and the update
# still finishes.
#
# Example: clear Homebrew's download cache after a full update.
# if [ -z "${1:-}" ] && command -v brew >/dev/null 2>&1; then brew cleanup; fi
```

```bash file=capabilities/teeup-runtime/default/hooks/theme-set.sample
#!/usr/bin/env bash
# theme-set hook sample, installed by teeup and rewritten when teeup's copy
# changes. It never runs: teeup skips every *.sample file.
#
# To add a hook, put a script of your own next to this file, for example
# theme-set.d/10-notify.sh. Every file in this directory that does not end in
# .sample runs with bash, in name order, after `teeup theme set` (and every
# configure of the theme capability) has rendered the theme and every
# installed capability has picked it up. $1 is the theme name. The rendered
# files are under $TEEUP_STATE_DIR/current/theme/dark and .../light;
# TEEUP_PATH, TEEUP_CONFIG_DIR and TEEUP_HOOK_EVENT=theme-set are in the
# environment too. Its stdin is /dev/null, and a hook that fails prints a
# warning and the theme stays applied.
#
# Example: say which theme is now active.
# osascript -e "display notification \"Theme: $1\" with title \"teeup\""
```

- [ ] **Step 7: Install the samples from `teeup-runtime configure` and fire `post-bootstrap`**

```bash edit-old=capabilities/teeup-runtime/configure
[[ -d "$TEEUP_CONFIG_DIR/hooks" ]] || run_cmd mkdir -p "$TEEUP_CONFIG_DIR/hooks"
```

```bash edit-new=capabilities/teeup-runtime/configure
[[ -d "$TEEUP_CONFIG_DIR/hooks" ]] || run_cmd mkdir -p "$TEEUP_CONFIG_DIR/hooks"

# One directory per hook event, each with a sample that documents the event's
# arguments. The sample is teeup's (rewritten when it changes, never run); the
# user's hooks are the other files in the directory, which teeup never touches.
for event in $TEEUP_HOOK_EVENTS; do
  hook_event_dir="$TEEUP_CONFIG_DIR/hooks/$event.d"
  [[ -d "$hook_event_dir" ]] || run_cmd mkdir -p "$hook_event_dir"
  write_managed_file "$hook_event_dir/example.sample" "$event hook sample" < "$TEEUP_CAP_DIR/default/hooks/$event.sample"
done
```

```bash edit-old=bootstrap
# --- 8. summary ---------------------------------------------------------------
echo ""
ok "Bootstrap finished in $(format_duration $(( $(date +%s) - started )))."
```

```bash edit-new=bootstrap
# --- 8. hooks and summary -----------------------------------------------------
hook_run post-bootstrap
echo ""
ok "Bootstrap finished in $(format_duration $(( $(date +%s) - started )))."
```

- [ ] **Step 8: Cover the samples and the bootstrap wiring**

```bash edit-old=tests/capabilities/teeup-runtime.sh
  [[ ! -e "$TEST_HOME/.local/bin/teeup" ]] || { echo "link made in dry run"; return 1; }
  cleanup_test_env
}
```

```bash edit-new=tests/capabilities/teeup-runtime.sh
  [[ ! -e "$TEST_HOME/.local/bin/teeup" ]] || { echo "link made in dry run"; return 1; }
  [[ ! -e "$TEST_HOME/.config/teeup/hooks" ]] || { echo "hook directories made in dry run"; return 1; }
  cleanup_test_env
}

test_configure_installs_a_sample_for_every_hook_event() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local event hooks="$TEST_HOME/.config/teeup/hooks"
  for event in post-bootstrap post-update theme-set; do
    assert_file_exists "$hooks/$event.d/example.sample" || return 1
    assert_equals "$(cat "$TEEUP_PATH/capabilities/teeup-runtime/default/hooks/$event.sample")" "$(cat "$hooks/$event.d/example.sample")" || return 1
  done
  # The user's own hooks sit beside the samples and survive every configure.
  printf '#!/usr/bin/env bash\necho mine\n' > "$hooks/theme-set.d/10-mine.sh"
  printf 'stale\n' > "$hooks/theme-set.d/example.sample"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure teeup-runtime)"
  assert_equals "$(printf '#!/usr/bin/env bash\necho mine')" "$(cat "$hooks/theme-set.d/10-mine.sh")" || return 1
  assert_contains "$out" "Wrote $hooks/theme-set.d/example.sample" "a changed sample is rewritten" || return 1
  assert_contains "$out" "Already current: $hooks/post-update.d/example.sample" || return 1
  cleanup_test_env
}
```

```bash edit-old=tests/capabilities/teeup-runtime.sh
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
```

```bash edit-new=tests/capabilities/teeup-runtime.sh
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "configure installs a sample for every hook event" test_configure_installs_a_sample_for_every_hook_event
```

```bash edit-old=tests/bootstrap.sh
test_dry_run_touches_nothing() {
  setup
  "$BOOT" --dry-run <<<"$WIZARD_INPUT" >/dev/null
```

```bash edit-new=tests/bootstrap.sh
test_post_bootstrap_hooks_run_before_the_summary() {
  setup
  mkdir -p "$TEST_HOME/.config/teeup/hooks/post-bootstrap.d"
  printf '#!/usr/bin/env bash\ntouch "$HOME/hook-ran"\n' > "$TEST_HOME/.config/teeup/hooks/post-bootstrap.d/10-mark.sh"
  local out h s
  out="$("$BOOT" --dry-run <<<"$WIZARD_INPUT")"
  assert_contains "$out" "[DRY-RUN] Would run hook: $TEST_HOME/.config/teeup/hooks/post-bootstrap.d/10-mark.sh" || return 1
  h="$(printf '%s\n' "$out" | grep -n 'Would run hook' | head -1 | cut -d: -f1)"
  s="$(printf '%s\n' "$out" | grep -n 'Bootstrap finished' | head -1 | cut -d: -f1)"
  [[ "$h" -lt "$s" ]] || { echo "the hook must come before the summary"; return 1; }
  [[ ! -e "$TEST_HOME/hook-ran" ]] || { echo "a hook ran in dry run"; return 1; }
  cleanup_test_env
}

test_dry_run_touches_nothing() {
  setup
  "$BOOT" --dry-run <<<"$WIZARD_INPUT" >/dev/null
```

```bash edit-old=tests/bootstrap.sh
run_test "dry run touches nothing" test_dry_run_touches_nothing
```

```bash edit-new=tests/bootstrap.sh
run_test "post-bootstrap hooks run before the summary" test_post_bootstrap_hooks_run_before_the_summary
run_test "dry run touches nothing" test_dry_run_touches_nothing
```

- [ ] **Step 9: Cover the samples in CI's shellcheck step**

```yaml edit-old=.github/workflows/ci.yml
              -o -name font-apply \)) \
            tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh \
```

```yaml edit-new=.github/workflows/ci.yml
              -o -name font-apply \)) \
            capabilities/teeup-runtime/default/hooks/*.sample \
            tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh \
```

- [ ] **Step 10: Run the three suites**

Run: `bash tests/lib/hooks.sh && bash tests/capabilities/teeup-runtime.sh && bash tests/bootstrap.sh`
Expected: `Summary: 7/7 passed`, `Summary: 10/10 passed`, `Summary: 25/25 passed`.

- [ ] **Step 11: Full checks and commit**

```bash
./tests/run.sh
./bin/teeup commands --check
shellcheck --severity=warning lib/hooks.sh lib/all.sh lib/theme.sh bootstrap capabilities/teeup-runtime/configure capabilities/teeup-runtime/default/hooks/*.sample tests/lib/hooks.sh tests/capabilities/teeup-runtime.sh tests/bootstrap.sh
git diff --check
git add lib/hooks.sh lib/all.sh lib/theme.sh bootstrap capabilities/teeup-runtime/configure capabilities/teeup-runtime/default/hooks .github/workflows/ci.yml tests/lib/hooks.sh tests/capabilities/teeup-runtime.sh tests/bootstrap.sh
git commit -m "Add user hooks for post-bootstrap, post-update and theme-set"
```

Expected: the suite count printed before this task, plus 1 (`tests/lib/hooks.sh`). `commands --check`, shellcheck and `git diff --check` print nothing.

---

### Task 3: The stock-checksum rule, and a `starship.toml` that stays pristine

Spec section 9: "Migrations follow Omarchy's stock-checksum rule: refresh a user file only if its SHA matches the shipped version at the time it was copied (recorded in state at copy time), otherwise patch minimally and back up." `stock_record` and `stock_sha` already exist; this task adds the three functions that use them, and fixes the defect that makes the rule useless for the one file teeup rewrites in place: `capabilities/theme/theme-apply` replaces the palette block in `~/.config/starship.toml`, after which its content no longer matches its stock record, so `copy_config_once` says `Keeping your edited ...` on a file the user never touched (pr11's deferred list). The same change refuses to write through a symlinked `starship.toml`, which is the other starship item on that list.

**Files:**
- Modify: `lib/files.sh` (after `stock_sha`, and `backup_target`'s body), `capabilities/theme/theme-apply` (its last write)
- Test: `tests/lib/files.sh`, `tests/capabilities/theme.sh`

**Interfaces:**
- Consumes: `file_sha`, `stock_record`, `stock_sha`, `write_managed_file`, `copy_config_once`, `backup_target` (`lib/files.sh`).
- Produces: `config_is_pristine <dest>`, `write_config_region <dest> <label>` (content on stdin), `refresh_if_pristine <src> <dest>`, `_backup_name <path>` (a backup name nothing holds yet, `-1`/`-2`/... on a collision), `backup_copy <path>`. `backup_target` is rewritten to call `_backup_name` too, so the two never collide on the same name inside one run. Task 4's `migration_refresh` calls `refresh_if_pristine`; plan 5a's legacy migration calls `backup_copy`.

**Real-Mac risk:** `shasum` is what `file_sha` prefers and macOS ships it; the Linux runs use `sha256sum`. Both are already exercised by `copy_config_once`. Whether a dotfile manager on the user's Mac really leaves `~/.config/starship.toml` as a symlink (chezmoi does not; GNU stow does) decides whether the symlink branch ever fires.

- [ ] **Step 1: Write the failing tests**

```bash edit-old=tests/lib/files.sh
echo "lib/files.sh"
run_test "append_once is idempotent" test_append_once_is_idempotent
```

```bash edit-new=tests/lib/files.sh
test_config_is_pristine_follows_the_stock_record() {
  setup
  config_is_pristine "$DEST" && { echo "a missing file is not pristine"; return 1; }
  copy_config_once "$SRC" "$DEST" >/dev/null
  config_is_pristine "$DEST" || { echo "a fresh copy is pristine"; return 1; }
  printf 'shipped=1\nmine=2\n' > "$DEST"
  config_is_pristine "$DEST" && { echo "an edited file is not pristine"; return 1; }
  printf 'unrecorded\n' > "$TEST_HOME/other"
  config_is_pristine "$TEST_HOME/other" && { echo "a file with no record is not pristine"; return 1; }
  ln -s "$SRC" "$TEST_HOME/link"
  stock_record "$TEST_HOME/link" "$(file_sha "$SRC")"
  config_is_pristine "$TEST_HOME/link" && { echo "a symlink is never pristine"; return 1; }
  cleanup_test_env
}

test_write_config_region_keeps_a_pristine_file_pristine() {
  setup
  # A directory with a space, an ampersand, a quote and a dollar sign: the
  # stock record path is derived from it.
  DEST="$TEST_HOME/.config/it's a & \$dir/tool.conf"
  copy_config_once "$SRC" "$DEST" >/dev/null
  printf 'shipped=1\n# managed region rewritten\n' | write_config_region "$DEST" "palette" >/dev/null
  assert_equals "$(printf 'shipped=1\n# managed region rewritten')" "$(cat "$DEST")" || return 1
  config_is_pristine "$DEST" || { echo "teeup's own rewrite must not read as a user edit"; return 1; }
  assert_contains "$(copy_config_once "$SRC" "$DEST")" "Already installed: $DEST" || return 1
  cleanup_test_env
}

test_write_config_region_leaves_an_edited_file_edited() {
  setup
  copy_config_once "$SRC" "$DEST" >/dev/null
  printf 'shipped=1\nmine=2\n' > "$DEST"
  local before
  before="$(stock_sha "$DEST")"
  printf 'shipped=1\nmine=2\n# region\n' | write_config_region "$DEST" "palette" >/dev/null
  assert_equals "$(printf 'shipped=1\nmine=2\n# region')" "$(cat "$DEST")" || return 1
  assert_equals "$before" "$(stock_sha "$DEST")" "the record of an edited file is kept" || return 1
  assert_contains "$(copy_config_once "$SRC" "$DEST")" "Keeping your edited $DEST" || return 1
  cleanup_test_env
}

test_write_config_region_refuses_a_symlink_and_dry_run() {
  setup
  mkdir -p "$TEST_HOME/store"
  printf 'managed elsewhere\n' > "$TEST_HOME/store/tool.conf"
  mkdir -p "$(dirname "$DEST")"
  ln -s "$TEST_HOME/store/tool.conf" "$DEST"
  local rc=0 out
  out="$(printf 'new\n' | write_config_region "$DEST" "palette" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$DEST is a symlink" || return 1
  [[ -L "$DEST" ]] || { echo "the link was replaced"; return 1; }
  assert_equals "managed elsewhere" "$(cat "$TEST_HOME/store/tool.conf")" || return 1
  rm -f "$DEST"
  copy_config_once "$SRC" "$DEST" >/dev/null
  out="$(printf 'new\n' | DRY_RUN=true write_config_region "$DEST" "palette")"
  assert_contains "$out" "[DRY-RUN] Would write $DEST (palette)" || return 1
  assert_equals "shipped=1" "$(cat "$DEST")" || return 1
  assert_equals "$(file_sha "$SRC")" "$(stock_sha "$DEST")" || return 1
  cleanup_test_env
}

test_refresh_if_pristine_replaces_only_an_unedited_file() {
  setup
  copy_config_once "$SRC" "$DEST" >/dev/null
  printf 'shipped=2\n' > "$TEST_HOME/src2"
  local out rc=0
  out="$(refresh_if_pristine "$TEST_HOME/src2" "$DEST")"
  assert_contains "$out" "Refreshed $DEST" || return 1
  assert_equals "shipped=2" "$(cat "$DEST")" || return 1
  config_is_pristine "$DEST" || { echo "the record follows the refresh"; return 1; }
  printf 'shipped=2\nmine=3\n' > "$DEST"
  printf 'shipped=3\n' > "$TEST_HOME/src3"
  out="$(refresh_if_pristine "$TEST_HOME/src3" "$DEST")" || rc=$?
  assert_failure "$rc" "an edited file is reported, so the migration can patch it" || return 1
  assert_contains "$out" "Keeping your edited $DEST" || return 1
  assert_equals "$(printf 'shipped=2\nmine=3')" "$(cat "$DEST")" || return 1
  rm -f "$DEST"
  refresh_if_pristine "$TEST_HOME/src3" "$DEST" >/dev/null
  assert_equals "shipped=3" "$(cat "$DEST")" "a missing file is installed" || return 1
  cleanup_test_env
}

test_refresh_if_pristine_dry_run_changes_nothing() {
  setup
  copy_config_once "$SRC" "$DEST" >/dev/null
  printf 'shipped=2\n' > "$TEST_HOME/src2"
  local out
  out="$(DRY_RUN=true refresh_if_pristine "$TEST_HOME/src2" "$DEST")"
  assert_contains "$out" "[DRY-RUN] Would refresh $DEST from $TEST_HOME/src2" || return 1
  assert_equals "shipped=1" "$(cat "$DEST")" || return 1
  cleanup_test_env
}

test_backup_copy_keeps_the_original_in_place() {
  setup
  printf 'mine\n' > "$TEST_HOME/file"
  local backup
  backup="$(backup_copy "$TEST_HOME/file" 2>/dev/null)"
  [[ "$backup" == "$TEST_HOME/file.teeup_backup_"* ]] || { echo "bad backup name: $backup"; return 1; }
  assert_equals "mine" "$(cat "$backup")" || return 1
  assert_equals "mine" "$(cat "$TEST_HOME/file")" || return 1
  cleanup_test_env
}

test_two_backups_of_the_same_file_within_one_second_both_survive() {
  setup
  printf 'first\n' > "$TEST_HOME/file"
  local first second
  first="$(backup_copy "$TEST_HOME/file" 2>/dev/null)"
  printf 'second\n' > "$TEST_HOME/file"
  second="$(backup_copy "$TEST_HOME/file" 2>/dev/null)"
  [[ "$first" != "$second" ]] || { echo "the second call reused the first's name: $first"; return 1; }
  assert_equals "first" "$(cat "$first")" "the first backup must not be overwritten by the second" || return 1
  assert_equals "second" "$(cat "$second")" || return 1
  cleanup_test_env
}

echo "lib/files.sh"
run_test "append_once is idempotent" test_append_once_is_idempotent
```

```bash edit-old=tests/lib/files.sh
run_test "replace_literal is literal and repeats" test_replace_literal_is_literal_and_repeats
print_summary
```

```bash edit-new=tests/lib/files.sh
run_test "config_is_pristine follows the stock record" test_config_is_pristine_follows_the_stock_record
run_test "write_config_region keeps a pristine file pristine" test_write_config_region_keeps_a_pristine_file_pristine
run_test "write_config_region leaves an edited file edited" test_write_config_region_leaves_an_edited_file_edited
run_test "write_config_region refuses a symlink, and dry run" test_write_config_region_refuses_a_symlink_and_dry_run
run_test "refresh_if_pristine replaces only an unedited file" test_refresh_if_pristine_replaces_only_an_unedited_file
run_test "refresh_if_pristine dry run changes nothing" test_refresh_if_pristine_dry_run_changes_nothing
run_test "backup_copy keeps the original in place" test_backup_copy_keeps_the_original_in_place
run_test "two backups of the same file within one second both survive" test_two_backups_of_the_same_file_within_one_second_both_survive
run_test "replace_literal is literal and repeats" test_replace_literal_is_literal_and_repeats
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/lib/files.sh`
Expected: the eight new tests fail with `config_is_pristine: command not found`, `write_config_region: command not found`, `refresh_if_pristine: command not found` and `backup_copy: command not found`; the suite ends with `Summary: 12/20 passed`.

- [ ] **Step 3: Add the four functions to `lib/files.sh`**

```bash edit-old=lib/files.sh
stock_sha() {
  local record
  record="$(_stock_record_path "$1")"
  [[ -f "$record" ]] && cat "$record"
}
```

```bash edit-new=lib/files.sh
stock_sha() {
  local record
  record="$(_stock_record_path "$1")"
  [[ -f "$record" ]] && cat "$record"
}

# config_is_pristine <dest>
# True when <dest> is a regular file with a stock record and still hashes to
# it: every byte is what teeup last wrote there (a copy, a reset, a refresh or
# a managed-region rewrite) and nobody has edited it since. This is the test
# behind the stock-checksum rule (spec section 9). A symlink is never
# pristine: no stock record can belong to one.
config_is_pristine() {
  local dest="$1" recorded
  [[ -f "$dest" && ! -L "$dest" ]] || return 1
  recorded="$(stock_sha "$dest" || true)"
  [[ -n "$recorded" && "$recorded" == "$(file_sha "$dest")" ]]
}

# write_config_region <dest> <label>   (the whole new file on stdin)
# Rewrites a user-owned config file whose teeup-managed region changed (the
# starship palette block). The write goes through write_managed_file. When the
# file was pristine before the write, the new content becomes its stock
# record, so teeup's own rewrite never makes the file read as edited: the next
# configure still says "Already installed" and a later migration may still
# refresh it. A file the user has edited keeps its old record and keeps
# reading as edited. A symlink is refused (warns, returns 1, writes nothing):
# the rename inside write_managed_file would replace a dotfile manager's link
# with a copy it no longer tracks.
write_config_region() {
  local dest="$1" label="$2" pristine=false tmp
  if [[ -L "$dest" ]]; then
    warn "$dest is a symlink; teeup does not write through it, so its $label was not updated."
    cat >/dev/null
    return 1
  fi
  if config_is_pristine "$dest"; then pristine=true; fi
  if [[ "$DRY_RUN" == "true" ]]; then
    write_managed_file "$dest" "$label"
    return 0
  fi
  tmp="$(mktemp)"
  cat > "$tmp"
  write_managed_file "$dest" "$label" < "$tmp"
  rm -f "$tmp"
  if [[ "$pristine" == "true" ]]; then
    stock_record "$dest" "$(file_sha "$dest")"
  fi
}

# refresh_if_pristine <src> <dest>
# The stock-checksum rule, as migrations use it: a <dest> that is still
# pristine is replaced with the shipped <src> and its record follows; a
# missing <dest> is installed with copy_config_once. A <dest> the user has
# edited (or one teeup holds no record of) is left alone with a log line and
# the function returns 1, so the migration can patch that file minimally
# instead, after backup_copy.
refresh_if_pristine() {
  local src="$1" dest="$2"
  if [[ ! -e "$dest" && ! -L "$dest" ]]; then
    copy_config_once "$src" "$dest"
    return $?
  fi
  if ! config_is_pristine "$dest"; then
    log "Keeping your edited $dest; it was not refreshed."
    return 1
  fi
  if cmp -s "$src" "$dest"; then
    log "Already at the shipped version: $dest"
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would refresh $dest from $src"
    return 0
  fi
  cp "$src" "$dest"
  stock_record "$dest" "$(file_sha "$src")"
  ok "Refreshed $dest (you had not edited it)"
}

# _backup_name <path>  -> prints a backup path nothing holds yet
# Both backup_copy and backup_target name a backup <path>.teeup_backup_<ts>,
# to the second. A single `teeup migrate legacy` run can back the same file
# up several times inside one second (legacy wiring, then prompt wiring, then
# chezmoi), and a second call landing on the name the first just used would
# silently overwrite it. When that name is already taken, this appends -1,
# -2, ... until it finds one nothing holds, so every backup from the same run
# survives. Bash-3.2-safe: a counter and plain concatenation, no ${var//}.
_backup_name() {
  local target="$1" base n
  base="${target}.teeup_backup_$(date +%Y%m%d%H%M%S)"
  if [[ ! -e "$base" ]]; then
    printf '%s\n' "$base"
    return 0
  fi
  n=1
  while [[ -e "${base}-${n}" ]]; do
    n=$((n + 1))
  done
  printf '%s\n' "${base}-${n}"
}

# backup_copy <path>  -> prints the backup path on stdout
# Like backup_target, but copies: the file stays in place for a migration to
# patch, and the copy keeps what it held before.
backup_copy() {
  local target="$1" backup
  backup="$(_backup_name "$target")"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would copy $target to $backup" >&2
  else
    cp -p "$target" "$backup"
    ok "Copied $target to $backup" >&2
  fi
  printf '%s\n' "$backup"
}
```

`backup_target` (already in `lib/files.sh`, unchanged by phase 1-3) collides on the exact same name; it gets the same fix, through the same helper:

```bash edit-old=lib/files.sh
backup_target() {
  local target="$1" backup
  backup="${target}.teeup_backup_$(date +%Y%m%d%H%M%S)"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would back up $target to $backup" >&2
```

```bash edit-new=lib/files.sh
backup_target() {
  local target="$1" backup
  backup="$(_backup_name "$target")"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would back up $target to $backup" >&2
```

- [ ] **Step 4: Run the files suite**

Run: `bash tests/lib/files.sh`
Expected: `Summary: 20/20 passed`.

- [ ] **Step 5: Write the failing tests for `starship.toml`**

```bash edit-old=tests/capabilities/theme.sh
test_theme_apply_refuses_malformed_markers() {
```

```bash edit-new=tests/capabilities/theme.sh
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
```

```bash edit-old=tests/capabilities/theme.sh
run_test "theme-apply refuses malformed markers" test_theme_apply_refuses_malformed_markers
```

```bash edit-new=tests/capabilities/theme.sh
run_test "theme-apply refuses malformed markers" test_theme_apply_refuses_malformed_markers
run_test "a palette rewrite leaves starship.toml unedited" test_a_palette_rewrite_leaves_starship_toml_unedited
run_test "theme-apply leaves a symlinked starship.toml alone" test_theme_apply_leaves_a_symlinked_starship_toml_alone
```

- [ ] **Step 6: Run it to see it fail**

Run: `bash tests/capabilities/theme.sh`
Expected: `a palette rewrite leaves starship.toml unedited` fails on `Already installed: ...` (the rewritten file reads as edited) and `theme-apply leaves a symlinked starship.toml alone` fails because the link was replaced by a regular file; the suite ends with `Summary: 19/21 passed`.

- [ ] **Step 7: Write the palette through `write_config_region`**

```bash edit-old=capabilities/theme/theme-apply
write_managed_file "$STARSHIP" "starship palette ($active)" < "$rewritten"
rm -f "$block" "$rewritten"
```

```bash edit-new=capabilities/theme/theme-apply
# write_config_region, not write_managed_file: starship.toml is the user's file
# with a stock record, and a palette rewrite of a file the user never edited
# must leave it reading as unedited (lib/files.sh). It also refuses a
# symlinked starship.toml rather than replacing the link with a copy.
write_config_region "$STARSHIP" "starship palette ($active)" < "$rewritten" || true
rm -f "$block" "$rewritten"
```

- [ ] **Step 8: Run the theme suite**

Run: `bash tests/capabilities/theme.sh`
Expected: `Summary: 21/21 passed`.

- [ ] **Step 9: Full checks and commit**

```bash
./tests/run.sh
./bin/teeup commands --check
shellcheck --severity=warning lib/files.sh capabilities/theme/theme-apply tests/lib/files.sh tests/capabilities/theme.sh
git diff --check
git add lib/files.sh capabilities/theme/theme-apply tests/lib/files.sh tests/capabilities/theme.sh
git commit -m "Keep a pristine starship.toml pristine across theme rewrites"
```

Expected: the suite count printed before this task, plus 0. `commands --check`, shellcheck and `git diff --check` print nothing.

---

### Task 4: The migration runner, `migration_refresh` and `teeup dev add-migration`

Spec section 9: "run pending `migrations/<epoch>.sh` (marker per applied file under `state/migrations`)" and "`teeup dev add-migration` names the file from the last commit timestamp". `bootstrap` already marks every shipped migration on a fresh machine and `lib/state.sh` already has the markers; this task adds the directory, the runner, the refresh helper that makes the stock-checksum rule reach a rendered config, and the scaffold command.

**Files:**
- Create: `lib/migrations.sh`, `migrations/README.md`
- Modify: `lib/all.sh`, `lib/capability.sh` (`cap_run`), `lib/files.sh` (`copy_config_once`), `bootstrap`, `bin/teeup` (`usage`, `cmd_dev`, the verb table), `.github/workflows/ci.yml`
- Test: `tests/lib/migrations.sh` (new), `tests/lib/capability.sh`, `tests/cli.sh`, `tests/bootstrap.sh`

**Interfaces:**
- Consumes: `state_migration_done`, `state_migration_mark` (`lib/state.sh`); `run_logged`, `run_cmd`, `DRY_RUN` (`lib/core.sh`); `cap_exists`, `cap_skipped`, `cap_run`, `state_done check` (`lib/capability.sh`, `lib/state.sh`); `copy_config_once`, `refresh_if_pristine` (Task 3).
- Produces: `TEEUP_MIGRATIONS_DIR`, `migrations_list`, `migrations_pending`, `migrations_mark_all`, `migration_run <name>`, `migrations_run_pending`, `migration_refresh <capability>`, `migration_new`, and the `TEEUP_REFRESH` seam in `copy_config_once`. Task 5 adds the matching `TEEUP_RESET` seam; Task 6 calls `migrations_run_pending`; 4b appends its `dev` subcommands to `cmd_dev`.

**Real-Mac risk:** `git -C "$TEEUP_PATH" log -1 --format=%ct` needs a checkout with history; a user who downloaded a tarball gets the clock fallback, which only a real download proves. Nothing here runs a migration on hardware, because no migration exists yet.

- [ ] **Step 1: Write the failing suite**

```bash file=tests/lib/migrations.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  # A migrations directory with a space, a quote, a dollar sign and an
  # ampersand in its path: file names reach bash, run_logged and the markers.
  export TEEUP_MIGRATIONS_DIR="$TEST_HOME/mig rations 'q' \$x & co"
  mkdir -p "$TEEUP_MIGRATIONS_DIR"
  source "$TEEUP_PATH/lib/all.sh"
  # shellcheck disable=SC2034  # read by the library functions under test
  DRY_RUN=false
  MARKS="$TEST_HOME/.local/state/teeup/migrations"
}

# make_migration <name> <body>
make_migration() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$TEEUP_MIGRATIONS_DIR/$1"
}

test_list_is_oldest_first_and_ignores_other_files() {
  setup
  make_migration 1790000000.sh ':'
  make_migration 999999999.sh ':'
  make_migration 1780000000.sh ':'
  make_migration helper.sh ':'
  printf 'notes\n' > "$TEEUP_MIGRATIONS_DIR/README.md"
  assert_equals "999999999.sh 1780000000.sh 1790000000.sh" "$(migrations_list | tr '\n' ' ' | sed 's/ $//')" || return 1
  cleanup_test_env
}

test_pending_leaves_out_applied_migrations() {
  setup
  make_migration 1780000000.sh ':'
  make_migration 1790000000.sh ':'
  state_migration_mark 1780000000.sh
  assert_equals "1790000000.sh" "$(migrations_pending)" || return 1
  migrations_mark_all
  assert_equals "" "$(migrations_pending)" || return 1
  assert_file_exists "$MARKS/1790000000.sh" || return 1
  cleanup_test_env
}

test_run_pending_runs_each_once_in_order_with_the_library() {
  setup
  make_migration 1790000000.sh 'echo "second $TEEUP_MIGRATION" >> "$HOME/ran"'
  make_migration 1780000000.sh 'log "from lib"; echo "first $TEEUP_MIGRATION name=${TEEUP_NAME:-}" >> "$HOME/ran"'
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_NAME="Ada"\n' > "$TEST_HOME/.config/teeup/answers"
  local out
  out="$(migrations_run_pending 2>&1)"
  assert_equals "$(printf 'first 1780000000.sh name=Ada\nsecond 1790000000.sh')" "$(cat "$TEST_HOME/ran")" || return 1
  assert_contains "$out" "from lib" || return 1
  assert_contains "$out" "Completed: migration 1780000000.sh" || return 1
  assert_contains "$out" "Applied 2 migration(s)." || return 1
  assert_file_exists "$MARKS/1780000000.sh" || return 1
  assert_file_exists "$MARKS/1790000000.sh" || return 1
  out="$(migrations_run_pending 2>&1)"
  assert_contains "$out" "No pending migrations." || return 1
  assert_equals "2" "$(wc -l < "$TEST_HOME/ran" | tr -d ' ')" "nothing runs twice" || return 1
  cleanup_test_env
}

test_a_failed_migration_stops_the_run_and_stays_pending() {
  setup
  make_migration 1770000000.sh 'echo "one" >> "$HOME/ran"'
  make_migration 1780000000.sh 'false; echo "unreachable" >> "$HOME/ran"'
  make_migration 1790000000.sh 'echo "three" >> "$HOME/ran"'
  local out rc=0
  out="$(migrations_run_pending 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_equals "one" "$(cat "$TEST_HOME/ran")" "bash -eu stops the failing script, and nothing after it runs" || return 1
  assert_contains "$out" "Migration 1780000000.sh failed, so the migrations after it did not run" || return 1
  assert_equals "$(printf '1780000000.sh\n1790000000.sh')" "$(migrations_pending)" || return 1
  cleanup_test_env
}

test_dry_run_previews_and_marks_nothing() {
  setup
  make_migration 1780000000.sh 'run_cmd touch "$HOME/made"'
  local out
  out="$(DRY_RUN=true migrations_run_pending 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: touch $TEST_HOME/made" || return 1
  assert_contains "$out" "[DRY-RUN] Would record state: migrations/1780000000.sh" || return 1
  [[ ! -e "$TEST_HOME/made" ]] || { echo "a migration mutated in dry run"; return 1; }
  [[ ! -e "$MARKS/1780000000.sh" ]] || { echo "marker written in dry run"; return 1; }
  cleanup_test_env
}

# A capability whose configure renders its file (the way zsh renders its home
# stubs), so a refresh must go through configure rather than copy the raw file.
make_rendering_cap() {
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR/tool/config"
  printf 'summary="Fixture tool"\ngroup=system\ntier=lazy\nrequires=""\nprovides=""\ninteractive=false\n' > "$TEEUP_CAPS_DIR/tool/capability"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/tool/install"
  cat > "$TEEUP_CAPS_DIR/tool/configure" <<'EOF2'
#!/usr/bin/env bash
rendered="$(mktemp)"
sed "s|@HOME@|$HOME|" "$TEEUP_CAP_DIR/config/tool.conf" > "$rendered"
copy_config_once "$rendered" "$HOME/.config/tool.conf"
rm -f "$rendered"
copy_config_once "$TEEUP_CAP_DIR/config/other.conf" "$HOME/.config/other.conf"
EOF2
  chmod +x "$TEEUP_CAPS_DIR/tool/install" "$TEEUP_CAPS_DIR/tool/configure"
  printf 'home=@HOME@\nversion=1\n' > "$TEEUP_CAPS_DIR/tool/config/tool.conf"
  printf 'other=1\n' > "$TEEUP_CAPS_DIR/tool/config/other.conf"
}

test_refresh_replaces_pristine_rendered_files_and_keeps_edited_ones() {
  setup
  make_rendering_cap
  cap_run tool configure >/dev/null
  state_done mark cap-tool
  printf 'other=1\nmine=1\n' > "$TEST_HOME/.config/other.conf"
  # The shipped files change in the next teeup version.
  printf 'home=@HOME@\nversion=2\n' > "$TEEUP_CAPS_DIR/tool/config/tool.conf"
  printf 'other=2\n' > "$TEEUP_CAPS_DIR/tool/config/other.conf"
  local out
  out="$(migration_refresh tool 2>&1)"
  assert_equals "$(printf 'home=%s\nversion=2' "$TEST_HOME")" "$(cat "$TEST_HOME/.config/tool.conf")" "refreshed, and rendered by configure" || return 1
  assert_contains "$out" "Refreshed $TEST_HOME/.config/tool.conf" || return 1
  assert_equals "$(printf 'other=1\nmine=1')" "$(cat "$TEST_HOME/.config/other.conf")" || return 1
  assert_contains "$out" "Keeping your edited $TEST_HOME/.config/other.conf" || return 1
  # Outside a refresh, copy_config_once is back to copying once: a newer
  # shipped file does not reach even a pristine copy.
  printf 'home=@HOME@\nversion=3\n' > "$TEEUP_CAPS_DIR/tool/config/tool.conf"
  out="$(cap_run tool configure 2>&1)"
  assert_contains "$out" "Already installed: $TEST_HOME/.config/tool.conf" || return 1
  assert_contains "$(cat "$TEST_HOME/.config/tool.conf")" "version=2" || return 1
  cleanup_test_env
}

test_refresh_skips_a_capability_that_is_not_installed() {
  setup
  make_rendering_cap
  local out
  out="$(migration_refresh tool 2>&1)"
  assert_contains "$out" "tool is not installed here; nothing to refresh." || return 1
  [[ ! -e "$TEST_HOME/.config/tool.conf" ]] || { echo "configure ran for a capability that is not installed"; return 1; }
  cleanup_test_env
}

test_new_is_named_from_the_last_commit() {
  setup
  mock_command git 0 "1788000000"
  local file
  file="$(migration_new 2>/dev/null)"
  assert_equals "$TEEUP_MIGRATIONS_DIR/1788000000.sh" "$file" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "git -C $TEEUP_PATH log -1 --format=%ct" || return 1
  assert_contains "$(head -2 "$file")" "Migration 1788000000." || return 1
  bash -n "$file" || { echo "the scaffold must be valid bash"; return 1; }
  file="$(migration_new 2>/dev/null)"
  assert_equals "$TEEUP_MIGRATIONS_DIR/1788000001.sh" "$file" "a second migration on the same commit takes the next second" || return 1
  cleanup_test_env
}

test_new_without_git_history_uses_the_clock_and_dry_run_writes_nothing() {
  setup
  mock_command git 128 ""
  local file out before after stamp
  before="$(date +%s)"
  file="$(migration_new 2>"$TEST_HOME/err")"
  after="$(date +%s)"
  assert_contains "$(cat "$TEST_HOME/err")" "No git history" || return 1
  stamp="${file##*/}"
  stamp="${stamp%.sh}"
  [[ "$stamp" -ge "$before" && "$stamp" -le "$after" ]] || { echo "unexpected name $file"; return 1; }
  rm -f "$file"
  mock_command git 0 "1788000000"
  out="$(DRY_RUN=true migration_new 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would create $TEEUP_MIGRATIONS_DIR/1788000000.sh" || return 1
  [[ ! -e "$TEEUP_MIGRATIONS_DIR/1788000000.sh" ]] || { echo "created in dry run"; return 1; }
  cleanup_test_env
}

echo "lib/migrations.sh"
run_test "list is oldest first and ignores other files" test_list_is_oldest_first_and_ignores_other_files
run_test "pending leaves out applied migrations" test_pending_leaves_out_applied_migrations
run_test "run_pending runs each once, in order, with the library" test_run_pending_runs_each_once_in_order_with_the_library
run_test "a failed migration stops the run and stays pending" test_a_failed_migration_stops_the_run_and_stays_pending
run_test "dry run previews and marks nothing" test_dry_run_previews_and_marks_nothing
run_test "refresh replaces pristine rendered files and keeps edited ones" test_refresh_replaces_pristine_rendered_files_and_keeps_edited_ones
run_test "refresh skips a capability that is not installed" test_refresh_skips_a_capability_that_is_not_installed
run_test "new is named from the last commit" test_new_is_named_from_the_last_commit
run_test "new without git history uses the clock, and dry run writes nothing" test_new_without_git_history_uses_the_clock_and_dry_run_writes_nothing
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/lib/migrations.sh`
Expected: every test fails with `command not found` for the function it calls (`migrations_list`, `migrations_pending`, `migrations_run_pending`, `migration_refresh`, `migration_new`); the suite ends with `Summary: 0/9 passed`.

- [ ] **Step 3: Write the library**

```bash file=lib/migrations.sh
#!/usr/bin/env bash
# migrations.sh - one-off changes for machines that already run teeup.
# A migration is $TEEUP_MIGRATIONS_DIR/<unix-epoch>.sh (migrations/ in the
# checkout). `teeup update` runs the pending ones oldest first, each exactly
# once per machine, and records each under $TEEUP_STATE_DIR/migrations/<name>
# (lib/state.sh). A fresh ./bootstrap marks every shipped migration applied
# without running it: its capabilities already install the current state
# (spec sections 5 and 9, Omarchy's omarchy-migrate).
# Requires core.sh, state.sh, answers.sh and capability.sh.

TEEUP_MIGRATIONS_DIR="${TEEUP_MIGRATIONS_DIR:-$TEEUP_PATH/migrations}"
export TEEUP_MIGRATIONS_DIR

# migrations_list -> every migration's file name, oldest first
# Only names that start with a digit and end in .sh count, so a README or a
# helper file in the directory is never run. sort -n orders by the leading
# number, which stays right if an epoch ever gains an eleventh digit.
migrations_list() {
  local f
  for f in "$TEEUP_MIGRATIONS_DIR"/[0-9]*.sh; do
    [[ -f "$f" ]] || continue
    printf '%s\n' "${f##*/}"
  done | sort -n
}

# migrations_pending -> the names not yet applied on this machine, oldest first
migrations_pending() {
  local m
  for m in $(migrations_list); do
    if ! state_migration_done "$m"; then printf '%s\n' "$m"; fi
  done
  return 0
}

# migrations_mark_all
# What ./bootstrap does once, on a machine it has never finished on.
migrations_mark_all() {
  local m
  for m in $(migrations_list); do
    state_migration_mark "$m"
  done
  return 0
}

# migration_run <name>
# Runs one migration the way cap_run runs a capability script: a fresh
# `bash -eu` with lib/all.sh loaded and the answers sourced, stdin on
# /dev/null, bracketed by run_logged. TEEUP_MIGRATION holds its name. The
# marker is written only after a zero exit. DRY_RUN reaches the script like
# any capability's, so a migration previews through run_cmd too.
migration_run() {
  local name="$1" file
  file="$TEEUP_MIGRATIONS_DIR/$name"
  if [[ ! -f "$file" ]]; then
    err "No migration named $name in $TEEUP_MIGRATIONS_DIR"
    return 1
  fi
  TEEUP_MIGRATION="$name"
  export TEEUP_MIGRATION
  run_logged "migration $name" false \
    bash -eu -c 'source "$TEEUP_PATH/lib/all.sh"; answers_load; source "$1"' bash "$file" || return 1
  state_migration_mark "$name"
}

# migrations_run_pending
# Stops at the first migration that fails and returns 1: a later migration is
# written against the state an earlier one leaves, so running it on top of a
# failure could do damage the failed one was meant to prevent. The failed
# migration stays unmarked and runs again on the next `teeup update`.
migrations_run_pending() {
  local m ran=0
  for m in $(migrations_pending); do
    log "Running migration $m"
    if ! migration_run "$m"; then
      err "Migration $m failed, so the migrations after it did not run. Fix the cause, then run: teeup update"
      return 1
    fi
    ran=$((ran + 1))
  done
  if [[ $ran -eq 0 ]]; then
    log "No pending migrations."
  else
    ok "Applied $ran migration(s)."
  fi
}

# migration_refresh <capability>
# For a migration that ships a changed config: re-runs <capability>'s
# configure with TEEUP_REFRESH naming it, which turns each of its
# copy_config_once calls into refresh_if_pristine (lib/files.sh). A file the
# user never edited is replaced with the new shipped version, rendered by the
# same configure code that installed it; an edited file is left alone for the
# migration to patch. A capability that is not installed here, or is skipped,
# has nothing to refresh.
migration_refresh() {
  local cap="$1" rc=0
  if ! cap_exists "$cap"; then
    err "migration_refresh: unknown capability $cap"
    return 1
  fi
  if cap_skipped "$cap" || ! state_done check "cap-$cap"; then
    log "$cap is not installed here; nothing to refresh."
    return 0
  fi
  export TEEUP_REFRESH="$cap"
  cap_run "$cap" configure || rc=$?
  unset TEEUP_REFRESH
  return $rc
}

# migration_new -> creates a migration file and prints its path
# Named from the checkout's last commit time, as spec section 9 and Omarchy's
# omarchy-dev-add-migration do: a migration written on top of the latest
# commit sorts after every migration that commit already carries, whatever
# this machine's clock says. A second migration for the same commit takes the
# next free second. A checkout without git history uses the current time.
migration_new() {
  local stamp file
  stamp="$(git -C "$TEEUP_PATH" log -1 --format=%ct 2>/dev/null || true)"
  if ! [[ "$stamp" =~ ^[0-9]+$ ]]; then
    warn "No git history at $TEEUP_PATH; naming the migration from the current time."
    stamp="$(date +%s)"
  fi
  while [[ -e "$TEEUP_MIGRATIONS_DIR/$stamp.sh" ]]; do
    stamp=$((10#$stamp + 1))
  done
  file="$TEEUP_MIGRATIONS_DIR/$stamp.sh"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would create $file" >&2
    printf '%s\n' "$file"
    return 0
  fi
  mkdir -p "$TEEUP_MIGRATIONS_DIR"
  cat > "$file" <<MIGRATION
#!/usr/bin/env bash
# Migration $stamp. Replace this line with what the migration changes and why.
#
# teeup update runs this once per machine, as bash -eu with lib/all.sh loaded
# and the answers sourced; a fresh ./bootstrap marks it applied without
# running it. Exit non-zero to stop the update: it runs again next time.
# Mutate only through run_cmd or a DRY_RUN-guarded primitive.
#
# A shipped config changed? \`migration_refresh <capability>\` refreshes the
# copies nobody edited (the stock-checksum rule); patch an edited one after
# \`backup_copy <file>\`.
MIGRATION
  ok "Created $file" >&2
  printf '%s\n' "$file"
}
```

- [ ] **Step 4: Ship the directory**

```markdown file=migrations/README.md
# migrations

One-off changes for machines that already run teeup. Each file is
`<unix-epoch>.sh`, created with `teeup dev add-migration`, and
`teeup update` runs the pending ones oldest first, once per machine.

A migration runs as `bash -eu` with `lib/all.sh` loaded and the answers
sourced, so `run_cmd`, `log`, `warn`, `answers_get` and the capability
helpers are available. Every mutation goes through `run_cmd` or a
primitive with its own dry-run guard, because `teeup update --dry-run`
must change nothing.

A shipped config file changed? Call `migration_refresh <capability>`: it
re-runs that capability's `configure` with the stock-checksum rule in
force, so a copy nobody edited is replaced (rendered by the same code
that installed it) and an edited one is left alone. Patch an edited file
minimally, after `backup_copy <file>`.

A fresh `./bootstrap` marks every migration here applied without running
it: the capabilities have just installed the state they lead to.
```

- [ ] **Step 5: Load the library, scope `TEEUP_REFRESH`, and replace bootstrap's loop**

```bash edit-old=lib/all.sh
for _teeup_lib in files state answers pkg ui capability macos theme font lazy mise hooks; do
```

```bash edit-new=lib/all.sh
for _teeup_lib in files state answers pkg ui capability macos theme font lazy mise hooks migrations; do
```

`cap_run` must put `TEEUP_CAP` back after a nested run, or `ssh configure` re-running `git configure` would leave `TEEUP_CAP=git` and a later `copy_config_once` in `ssh`'s own script would compare the wrong name:

```bash edit-old=lib/capability.sh
cap_run() {
  local name="$1" verb="$2" dir script interactive
```

```bash edit-new=lib/capability.sh
cap_run() {
  local name="$1" verb="$2" dir script interactive rc=0 outer_cap="${TEEUP_CAP:-}" outer_dir="${TEEUP_CAP_DIR:-}"
```

```bash edit-old=lib/capability.sh
  run_logged "$name $verb" "$interactive" \
    bash -eu -c 'source "$TEEUP_PATH/lib/all.sh"; answers_load; source "$1"' bash "$script"
}
```

```bash edit-new=lib/capability.sh
  run_logged "$name $verb" "$interactive" \
    bash -eu -c 'source "$TEEUP_PATH/lib/all.sh"; answers_load; source "$1"' bash "$script" || rc=$?
  # A capability script that runs another one (ssh re-runs git's configure)
  # is still itself afterwards: copy_config_once reads TEEUP_CAP to scope a
  # migration's TEEUP_REFRESH to the capability it names.
  TEEUP_CAP="$outer_cap"
  TEEUP_CAP_DIR="$outer_dir"
  return $rc
}
```

```bash edit-old=lib/files.sh
copy_config_once() {
  local src="$1" dest="$2" recorded current backup
```

```bash edit-new=lib/files.sh
copy_config_once() {
  local src="$1" dest="$2" recorded current backup
  # A migration refreshing this capability's files (migration_refresh sets
  # TEEUP_REFRESH to its name) gets the stock-checksum rule instead: a file
  # still pristine is replaced, an edited one is kept. The name must match
  # TEEUP_CAP, so a configure that re-runs another capability's (ssh re-runs
  # git's) leaves that capability's files to the normal rule. The prefix
  # assignment clears the variable for the nested call, which may come back
  # here for a missing file.
  if [[ -n "${TEEUP_REFRESH:-}" && "$TEEUP_REFRESH" == "${TEEUP_CAP:-}" ]]; then
    TEEUP_REFRESH="" refresh_if_pristine "$src" "$dest" || true
    return 0
  fi
```

```bash edit-old=bootstrap
if ! state_done check bootstrap; then
  # A fresh install starts with every shipped migration already applied.
  for m in "$TEEUP_PATH"/migrations/*.sh; do
    [[ -f "$m" ]] || continue
    state_migration_mark "$(basename "$m")"
  done
fi
```

```bash edit-new=bootstrap
if ! state_done check bootstrap; then
  # A fresh install starts with every shipped migration already applied: the
  # capabilities above put the machine in the state those migrations lead to.
  migrations_mark_all
fi
```

- [ ] **Step 6: Add the `dev` verb**

```bash edit-old=bin/teeup
  teeup commands --check         lint capability metadata
  teeup version
```

```bash edit-new=bin/teeup
  teeup commands --check         lint capability metadata
  teeup dev add-migration        start migrations/<epoch>.sh for machines already set up
  teeup version
```

```bash edit-old=bin/teeup
cmd_commands() {
  case "${1:-}" in
    --check) cap_check ;;
    *) cap_list ;;
  esac
}
```

```bash edit-new=bin/teeup
# Developer verbs, for people changing teeup itself. Each subcommand is one
# case arm; the scaffold writes into the checkout (TEEUP_MIGRATIONS_DIR).
cmd_dev() {
  local op="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$op" in
    add-migration) migration_new ;;
    *) die "Usage: teeup dev add-migration" ;;
  esac
}

cmd_commands() {
  case "${1:-}" in
    --check) cap_check ;;
    *) cap_list ;;
  esac
}
```

```bash edit-old=bin/teeup
  commands) cmd_commands "$@" ;;
  version) cat "$TEEUP_PATH/version" 2>/dev/null || echo dev ;;
```

```bash edit-new=bin/teeup
  commands) cmd_commands "$@" ;;
  dev) cmd_dev "$@" ;;
  version) cat "$TEEUP_PATH/version" 2>/dev/null || echo dev ;;
```

- [ ] **Step 7: Cover the nested-run fix, the CLI and bootstrap**

```bash edit-old=tests/lib/capability.sh
echo "lib/capability.sh"
run_test "list and exists" test_list_and_exists
```

```bash edit-new=tests/lib/capability.sh
test_run_restores_the_outer_capability_after_a_nested_run() {
  setup
  printf '#!/usr/bin/env bash\ncap_run alpha install\necho "after nested: $TEEUP_CAP $TEEUP_CAP_DIR"\n' > "$TEEUP_CAPS_DIR/beta/configure"
  local out
  out="$(cap_run beta configure 2>&1)"
  assert_contains "$out" "install:alpha cap=alpha" || return 1
  assert_contains "$out" "after nested: beta $TEEUP_CAPS_DIR/beta" || return 1
  cleanup_test_env
}

echo "lib/capability.sh"
run_test "list and exists" test_list_and_exists
```

```bash edit-old=tests/lib/capability.sh
run_test "hook eligible needs the marker or a running configure" test_hook_eligible_needs_the_marker_or_a_running_configure
```

```bash edit-new=tests/lib/capability.sh
run_test "hook eligible needs the marker or a running configure" test_hook_eligible_needs_the_marker_or_a_running_configure
run_test "run restores the outer capability after a nested run" test_run_restores_the_outer_capability_after_a_nested_run
```

```bash edit-old=tests/cli.sh
echo "bin/teeup"
run_test "install runs requires in order and marks done" test_install_runs_requires_in_order_and_marks_done
```

```bash edit-new=tests/cli.sh
test_dev_add_migration_creates_a_named_scaffold() {
  setup
  export TEEUP_MIGRATIONS_DIR="$TEST_HOME/migrations"
  mock_command git 0 "1788000000"
  local out rc=0
  out="$("$TEEUP" dev add-migration 2>/dev/null)"
  assert_equals "$TEEUP_MIGRATIONS_DIR/1788000000.sh" "$out" || return 1
  assert_file_exists "$TEEUP_MIGRATIONS_DIR/1788000000.sh" || return 1
  out="$("$TEEUP" dev frobnicate 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Usage: teeup dev add-migration" || return 1
  assert_contains "$("$TEEUP" help)" "teeup dev add-migration" || return 1
  cleanup_test_env
}

echo "bin/teeup"
run_test "install runs requires in order and marks done" test_install_runs_requires_in_order_and_marks_done
```

```bash edit-old=tests/cli.sh
run_test "install dev-env goes through mise" test_install_dev_env_goes_through_mise
print_summary
```

```bash edit-new=tests/cli.sh
run_test "install dev-env goes through mise" test_install_dev_env_goes_through_mise
run_test "dev add-migration creates a named scaffold" test_dev_add_migration_creates_a_named_scaffold
print_summary
```

```bash edit-old=tests/bootstrap.sh
test_dry_run_touches_nothing() {
  setup
  "$BOOT" --dry-run <<<"$WIZARD_INPUT" >/dev/null
```

```bash edit-new=tests/bootstrap.sh
test_a_fresh_bootstrap_marks_every_migration_without_running_it() {
  setup
  export TEEUP_MIGRATIONS_DIR="$TEST_HOME/migrations"
  mkdir -p "$TEEUP_MIGRATIONS_DIR"
  printf '#!/usr/bin/env bash\ntouch "$HOME/migration-ran"\n' > "$TEEUP_MIGRATIONS_DIR/1780000000.sh"
  cp "$TEEUP_MIGRATIONS_DIR/1780000000.sh" "$TEEUP_MIGRATIONS_DIR/1790000000.sh"
  local out
  out="$("$BOOT" --dry-run <<<"$WIZARD_INPUT")"
  assert_contains "$out" "Would record state: migrations/1780000000.sh" || return 1
  assert_contains "$out" "Would record state: migrations/1790000000.sh" || return 1
  assert_not_contains "$out" "Starting: migration" "bootstrap runs no migration" || return 1
  [[ ! -e "$TEST_HOME/migration-ran" ]] || { echo "a migration ran during bootstrap"; return 1; }
  cleanup_test_env
}

test_dry_run_touches_nothing() {
  setup
  "$BOOT" --dry-run <<<"$WIZARD_INPUT" >/dev/null
```

```bash edit-old=tests/bootstrap.sh
run_test "post-bootstrap hooks run before the summary" test_post_bootstrap_hooks_run_before_the_summary
```

```bash edit-new=tests/bootstrap.sh
run_test "post-bootstrap hooks run before the summary" test_post_bootstrap_hooks_run_before_the_summary
run_test "a fresh bootstrap marks every migration without running it" test_a_fresh_bootstrap_marks_every_migration_without_running_it
```

- [ ] **Step 8: Cover `migrations/*.sh` in CI's shellcheck step**

```yaml edit-old=.github/workflows/ci.yml
            capabilities/teeup-runtime/default/hooks/*.sample \
            tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh \
```

```yaml edit-new=.github/workflows/ci.yml
            capabilities/teeup-runtime/default/hooks/*.sample \
            $(find migrations -type f -name '*.sh' 2>/dev/null) \
            tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh \
```

- [ ] **Step 9: Run the four suites**

Run: `bash tests/lib/migrations.sh && bash tests/lib/capability.sh && bash tests/cli.sh && bash tests/bootstrap.sh`
Expected: `Summary: 9/9 passed`, `Summary: 20/20 passed`, `Summary: 29/29 passed`, `Summary: 26/26 passed`.

- [ ] **Step 10: Full checks and commit**

```bash
./tests/run.sh
./bin/teeup commands --check
shellcheck --severity=warning lib/migrations.sh lib/all.sh lib/capability.sh lib/files.sh bootstrap bin/teeup tests/lib/migrations.sh tests/lib/capability.sh tests/cli.sh tests/bootstrap.sh
git diff --check
git add lib/migrations.sh lib/all.sh lib/capability.sh lib/files.sh bootstrap bin/teeup migrations .github/workflows/ci.yml tests/lib/migrations.sh tests/lib/capability.sh tests/cli.sh tests/bootstrap.sh
git commit -m "Add the migration runner and teeup dev add-migration"
```

Expected: the suite count printed before this task, plus 1 (`tests/lib/migrations.sh`). `commands --check`, shellcheck and `git diff --check` print nothing.

---

### Task 5: `teeup reset <capability>`

Spec section 7: "`teeup reset <cap>` backs up the user copy, replaces it with the shipped file, prints the diff, and deletes the backup if nothing changed." `refresh_config` in `lib/files.sh` is already exactly that for one file. What is missing is the mapping from a capability to its files, and it cannot be "copy `capabilities/<cap>/config/<file>` to `~/.config/<file>`": `zsh/configure` renders the `%q`-quoted env path into its three home stubs, `git/configure` renders the resolved include paths, `ssh` writes to `~/.ssh`, and `aerospace` installs nothing next to an existing `~/.aerospace.toml`. Re-running the capability's own `configure` with `TEEUP_RESET` naming it reuses all of that.

**Files:**
- Modify: `lib/files.sh` (`copy_config_once`), `bin/teeup` (`usage`, `cmd_reset`, the verb table)
- Test: `tests/cli.sh`, `tests/capabilities/zsh.sh`, `tests/capabilities/starship.sh`

**Interfaces:**
- Consumes: `refresh_config` (`lib/files.sh`); `cap_exists`, `cap_dir`, `cap_skipped`, `cap_run` (`lib/capability.sh`); `state_done check`; `cap_run_hooks` (Task 1); `theme_current` (`lib/theme.sh`), `font_file`, `font_current` (`lib/font.sh`); the `TEEUP_CAP` restore from Task 4.
- Produces: `teeup reset <capability>` and the `TEEUP_RESET` seam in `copy_config_once`. Nothing later in this plan consumes them; 4b's `doctor` and 5a's `migrate` mention the verb in their messages.

**Real-Mac risk:** `teeup reset ssh` re-runs an `interactive=true` configure, which on hardware can prompt for a key passphrase; `teeup reset emacs` re-runs the LaunchAgent install, which bootstraps the daemon. Both are what `teeup configure <cap>` already does, but only a Mac shows how it feels.

- [ ] **Step 1: Write the failing CLI tests**

```bash edit-old=tests/cli.sh
test_dev_add_migration_creates_a_named_scaffold() {
```

```bash edit-new=tests/cli.sh
# A capability with two shipped files under config/, the second rendered by
# configure, installed the way `teeup install` leaves it.
make_config_cap() {
  make_cap tool lazy
  mkdir -p "$TEEUP_CAPS_DIR/tool/config"
  printf 'shipped=1\n' > "$TEEUP_CAPS_DIR/tool/config/plain.conf"
  printf 'home=@HOME@\n' > "$TEEUP_CAPS_DIR/tool/config/rendered.conf"
  cat > "$TEEUP_CAPS_DIR/tool/configure" <<'EOF2'
#!/usr/bin/env bash
copy_config_once "$TEEUP_CAP_DIR/config/plain.conf" "$(user_config_dir)/tool/plain.conf"
rendered="$(mktemp)"
sed "s|@HOME@|$HOME|" "$TEEUP_CAP_DIR/config/rendered.conf" > "$rendered"
copy_config_once "$rendered" "$(user_config_dir)/tool/rendered.conf"
rm -f "$rendered"
echo "configure:tool"
EOF2
  "$TEEUP" install tool >/dev/null
  TOOL="$TEST_HOME/.config/tool"
}

test_reset_replaces_edited_files_through_configure() {
  setup
  make_config_cap
  printf 'shipped=1\nmine=1\n' > "$TOOL/plain.conf"
  local out backups
  out="$("$TEEUP" reset tool 2>&1)"
  assert_equals "shipped=1" "$(cat "$TOOL/plain.conf")" || return 1
  assert_equals "home=$TEST_HOME" "$(cat "$TOOL/rendered.conf")" "the rendered file stays rendered" || return 1
  assert_contains "$out" "Reset $TOOL/plain.conf (backup at $TOOL/plain.conf.teeup_backup_" || return 1
  assert_contains "$out" "> mine=1" "the diff shows what the backup holds" || return 1
  assert_contains "$out" "Already at the shipped version: $TOOL/rendered.conf" || return 1
  assert_contains "$out" "Reset tool." || return 1
  backups="$(find "$TOOL" -name '*.teeup_backup_*' | wc -l | tr -d ' ')"
  assert_equals "1" "$backups" "a backup only where something changed" || return 1
  assert_contains "$("$TEEUP" configure tool)" "Already installed: $TOOL/plain.conf" "the reset file is pristine again" || return 1
  cleanup_test_env
}

test_reset_dry_run_changes_nothing() {
  setup
  make_config_cap
  printf 'mine\n' > "$TOOL/plain.conf"
  local out
  out="$(DRY_RUN=true "$TEEUP" reset tool 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would reset $TOOL/plain.conf" || return 1
  assert_equals "mine" "$(cat "$TOOL/plain.conf")" || return 1
  [[ -z "$(find "$TOOL" -name '*.teeup_backup_*')" ]] || { echo "backup made in dry run"; return 1; }
  cleanup_test_env
}

test_reset_refuses_what_it_cannot_reset() {
  setup
  make_config_cap
  local out rc=0
  out="$("$TEEUP" reset nope 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Unknown capability: nope" || return 1
  rc=0
  out="$("$TEEUP" reset alpha 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "alpha ships no config files to reset." || return 1
  rc=0
  out="$(TEEUP_SKIP=tool "$TEEUP" reset tool 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "tool is skipped on this machine (TEEUP_SKIP)" || return 1
  rm -f "$TEST_HOME/.local/state/teeup/done/cap-tool"
  rc=0
  out="$("$TEEUP" reset tool 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "tool is not installed. Install it with: teeup install tool" || return 1
  assert_contains "$("$TEEUP" help)" "teeup reset <capability>" || return 1
  cleanup_test_env
}

test_dev_add_migration_creates_a_named_scaffold() {
```

```bash edit-old=tests/cli.sh
run_test "dev add-migration creates a named scaffold" test_dev_add_migration_creates_a_named_scaffold
```

```bash edit-new=tests/cli.sh
run_test "reset replaces edited files through configure" test_reset_replaces_edited_files_through_configure
run_test "reset dry run changes nothing" test_reset_dry_run_changes_nothing
run_test "reset refuses what it cannot reset" test_reset_refuses_what_it_cannot_reset
run_test "dev add-migration creates a named scaffold" test_dev_add_migration_creates_a_named_scaffold
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/cli.sh`
Expected: the three new tests fail with `Unknown verb: reset`; the suite ends with `Summary: 29/32 passed`.

- [ ] **Step 3: Add the reset seam to `copy_config_once`**

```bash edit-old=lib/files.sh
  if [[ -n "${TEEUP_REFRESH:-}" && "$TEEUP_REFRESH" == "${TEEUP_CAP:-}" ]]; then
    TEEUP_REFRESH="" refresh_if_pristine "$src" "$dest" || true
    return 0
  fi
```

```bash edit-new=lib/files.sh
  if [[ -n "${TEEUP_REFRESH:-}" && "$TEEUP_REFRESH" == "${TEEUP_CAP:-}" ]]; then
    TEEUP_REFRESH="" refresh_if_pristine "$src" "$dest" || true
    return 0
  fi
  # `teeup reset <capability>` sets TEEUP_RESET to its name the same way: each
  # file goes back to the shipped version through refresh_config (backup,
  # replace, diff, the backup dropped when nothing changed). Because this
  # happens inside the capability's own configure, a file configure renders
  # is reset to the rendered version, never to the raw template.
  if [[ -n "${TEEUP_RESET:-}" && "$TEEUP_RESET" == "${TEEUP_CAP:-}" ]]; then
    TEEUP_RESET="" refresh_config "$src" "$dest"
    return $?
  fi
```

```bash edit-old=lib/capability.sh
  # A capability script that runs another one (ssh re-runs git's configure)
  # is still itself afterwards: copy_config_once reads TEEUP_CAP to scope a
  # migration's TEEUP_REFRESH to the capability it names.
```

```bash edit-new=lib/capability.sh
  # A capability script that runs another one (ssh re-runs git's configure)
  # is still itself afterwards: copy_config_once reads TEEUP_CAP to scope
  # TEEUP_REFRESH and TEEUP_RESET to the capability they name.
```

- [ ] **Step 4: Add the verb**

```bash edit-old=bin/teeup
  teeup configure <capability>   re-run only its configuration
```

```bash edit-new=bin/teeup
  teeup configure <capability>   re-run only its configuration
  teeup reset <capability>       put its config files back to the shipped version (backups kept)
```

```bash edit-old=bin/teeup
cmd_theme() {
  local op="${1:-current}" pinned
```

```bash edit-new=bin/teeup
# Every file a capability installs with copy_config_once goes back to what
# teeup ships. The capability's own configure does the work, with TEEUP_RESET
# naming it (lib/files.sh), so a file configure renders for this machine (zsh's
# home files, git's config) is rendered again rather than copied raw. Each
# replaced file is backed up and its diff printed; a backup of a file that was
# already the shipped version is dropped. A reset file carries the shipped
# colours, so the theme hooks run again afterwards, and the font hooks too.
cmd_reset() {
  local target="${1:-}" dir rc=0
  [[ -n "$target" ]] || die "Usage: teeup reset <capability>"
  cap_exists "$target" || die "Unknown capability: $target"
  if cap_skipped "$target"; then
    die "$target is skipped on this machine (TEEUP_SKIP)"
  fi
  dir="$(cap_dir "$target")"
  if [[ ! -d "$dir/config" && ! -d "$dir/home" ]]; then
    die "$target ships no config files to reset."
  fi
  state_done check "cap-$target" || die "$target is not installed. Install it with: teeup install $target"
  export TEEUP_RESET="$target"
  cap_run "$target" configure || rc=$?
  unset TEEUP_RESET
  if [[ $rc -ne 0 ]]; then
    die "Resetting $target failed; the backups made so far are next to their files."
  fi
  if [[ "$(theme_current)" != "none" ]]; then
    TEEUP_THEME_DIR="$TEEUP_STATE_DIR/current/theme"
    TEEUP_THEME_NAME="$(theme_current)"
    export TEEUP_THEME_DIR TEEUP_THEME_NAME
    cap_run_hooks theme-apply
  fi
  if [[ -s "$(font_file)" ]]; then
    TEEUP_FONT_FAMILY="$(font_current)"
    export TEEUP_FONT_FAMILY
    cap_run_hooks font-apply
  fi
  ok "Reset $target."
}

cmd_theme() {
  local op="${1:-current}" pinned
```

```bash edit-old=bin/teeup
  configure) cmd_configure "$@" ;;
```

```bash edit-new=bin/teeup
  configure) cmd_configure "$@" ;;
  reset) cmd_reset "$@" ;;
```

- [ ] **Step 5: Run the CLI suite**

Run: `bash tests/cli.sh`
Expected: `Summary: 32/32 passed`.

- [ ] **Step 6: Prove it on the two capabilities that need it most**

`zsh` renders its three home files; a raw copy would put the unexpanded `${XDG_CONFIG_HOME:-$HOME/.config}/teeup/env` token back into `~/.zshrc`.

```bash edit-old=tests/capabilities/zsh.sh
test_configure_installs_under_zdotdir() {
```

```bash edit-new=tests/capabilities/zsh.sh
test_reset_renders_the_home_files_again() {
  setup
  # A config dir with a space and a dollar sign: the rendered env path is
  # %q-quoted, so a raw copy of home/.zshrc would differ from the reset file.
  export XDG_CONFIG_HOME="$TEST_HOME/con fig \$x"
  # The narrowed PATH still exposes a host gum, and a capability's configure
  # may ask a question; keep every prompt on the plain read path.
  export TEEUP_NO_GUM=1
  DRY_RUN=false "$TEEUP" install zsh >/dev/null
  cp "$TEST_HOME/.zshrc" "$TEST_HOME/zshrc.installed"
  printf 'alias gs="git status"\n' >> "$TEST_HOME/.zshrc"
  local out
  out="$(DRY_RUN=false "$TEEUP" reset zsh 2>&1)"
  cmp -s "$TEST_HOME/zshrc.installed" "$TEST_HOME/.zshrc" ||
    { echo "reset must restore what configure rendered:"; diff "$TEST_HOME/zshrc.installed" "$TEST_HOME/.zshrc"; return 1; }
  assert_not_contains "$(cat "$TEST_HOME/.zshrc")" '${XDG_CONFIG_HOME:-$HOME/.config}/teeup/env' "not the raw template" || return 1
  assert_contains "$out" "Reset $TEST_HOME/.zshrc (backup at" || return 1
  assert_contains "$out" 'alias gs="git status"' "the diff shows the line the backup keeps" || return 1
  assert_contains "$out" "Already at the shipped version: $TEST_HOME/.zshenv" || return 1
  cleanup_test_env
}

test_configure_installs_under_zdotdir() {
```

```bash edit-old=tests/capabilities/zsh.sh
run_test "configure installs under ZDOTDIR" test_configure_installs_under_zdotdir
```

```bash edit-new=tests/capabilities/zsh.sh
run_test "reset renders the home files again" test_reset_renders_the_home_files_again
run_test "configure installs under ZDOTDIR" test_configure_installs_under_zdotdir
```

`starship.toml` is the file whose managed region teeup rewrites, so a reset has to put the current palette back and leave the file reading as unedited:

```bash edit-old=tests/capabilities/starship.sh
echo "capabilities/starship"
run_test "install gets starship" test_install_gets_starship
```

```bash edit-new=tests/capabilities/starship.sh
test_reset_restores_the_file_and_the_current_palette() {
  setup
  # appearance reads the interface style; exit 1 is light mode. starship
  # requires zsh, whose configure calls chsh, so that is mocked too.
  mock_command defaults 1 ""
  mock_command chsh 0 ""
  export TEEUP_NO_GUM=1
  DRY_RUN=false "$TEEUP" install starship >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" install theme >/dev/null
  local file="$TEST_HOME/.config/starship.toml" out
  assert_contains "$(cat "$file")" 'palette = "teeup-light"' || return 1
  # The shipped file has a [directory] table of its own, so the line the user
  # adds has to be one the shipped version does not carry.
  printf '\n[custom.mine]\ncommand = "echo mine"\n' >> "$file"
  out="$(DRY_RUN=false "$TEEUP" reset starship 2>&1)"
  assert_not_contains "$(cat "$file")" "custom.mine" || return 1
  assert_contains "$out" 'command = "echo mine"' "the diff shows the removed table" || return 1
  assert_contains "$(cat "$file")" 'palette = "teeup-light"' "the theme hook put the current palette back" || return 1
  assert_contains "$(cat "$file")" 'accent = "#' || return 1
  out="$(DRY_RUN=false "$TEEUP" configure starship)"
  assert_contains "$out" "Already installed: $file" "the reset and re-themed file reads as unedited" || return 1
  cleanup_test_env
}

echo "capabilities/starship"
run_test "install gets starship" test_install_gets_starship
```

```bash edit-old=tests/capabilities/starship.sh
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
print_summary
```

```bash edit-new=tests/capabilities/starship.sh
run_test "reset restores the file and the current palette" test_reset_restores_the_file_and_the_current_palette
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
print_summary
```

- [ ] **Step 7: Run the three suites**

Run: `bash tests/cli.sh && bash tests/capabilities/zsh.sh && bash tests/capabilities/starship.sh`
Expected: `Summary: 32/32 passed`, `Summary: 24/24 passed`, `Summary: 6/6 passed`.

- [ ] **Step 8: Full checks and commit**

```bash
./tests/run.sh
./bin/teeup commands --check
shellcheck --severity=warning lib/files.sh lib/capability.sh bin/teeup tests/cli.sh tests/capabilities/zsh.sh tests/capabilities/starship.sh
git diff --check
git add lib/files.sh lib/capability.sh bin/teeup tests/cli.sh tests/capabilities/zsh.sh tests/capabilities/starship.sh
git commit -m "Add teeup reset to restore a capability's shipped config"
```

Expected: the suite count printed before this task, plus 0. `commands --check`, shellcheck and `git diff --check` print nothing.

---

### Task 6: `teeup update [<capability>]`

Spec section 9, step by step: `git -C $TEEUP_PATH pull --ff-only` refusing a dirty tree, the pending migrations, the package manager, `mise upgrade`, `configure` for `core.list`, the theme, the `post-update` hook. Plus the one-capability form: "only that capability's packages and configure".

Section 4's capability contract lists `update` as an optional script beside `install`, `configure`, `doctor` and `remove` ("default is pkg upgrade of the packages declared in metadata"), so `teeup update <cap>` looks for `capabilities/<cap>/update` first and falls back to the metadata upgrade when there is none — the same shape Task 7 gives `teeup remove`. No capability ships one yet; the branch is what makes shipping one possible, and what the agent skill phase 5b writes already documents.

**Files:**
- Modify: `lib/pkg.sh` (after `cask_install`), `lib/mise.sh` (after `dev_env_installed`), `bin/teeup` (`usage`, `_update_checkout`, `cmd_update`, the verb table)
- Test: `tests/lib/pkg.sh`, `tests/lib/mise.sh`, `tests/cli.sh`

**Interfaces:**
- Consumes: `_pkg_backend_resolve`, `package_candidates`, `pkg_installed`, `casks_supported`, `cask_installed`, `run_privileged`, `pkg_backend_label` (`lib/pkg.sh`); `have`, `run_cmd`, `warn`, `log`, `ok`, `err`, `die`; `migrations_run_pending` (Task 4); `hook_run` (Task 2); `cap_tier_list`, `cap_exists`, `cap_skipped`, `cap_run`, `cap_dir`, `cap_meta_get`, `state_done check`; `theme_current`, `theme_set`.
- Produces: `pkg_update`, `pkg_upgrade_all`, `pkg_upgrade <pkg>`, `cask_upgrade <cask>` in `lib/pkg.sh`; `mise_upgrade` in `lib/mise.sh`; `teeup update [<capability>]` in `bin/teeup`. Task 7 adds `pkg_uninstall` and `cask_uninstall` next to them.

**Real-Mac risk:** most of this task. `brew update`/`brew upgrade`/`brew upgrade --cask` on a real Homebrew (how long, what it prints, a cask that needs `sudo` for its uninstall script), `port selfupdate`/`port upgrade outdated` and their exit status on a MacPorts machine, `mise -C / upgrade` pruning a version an open shell is using, `git pull --ff-only` against a branch that has diverged, and the total wall-clock time of re-running seventeen `configure` scripts.

- [ ] **Step 1: Write the failing package-manager tests**

```bash edit-old=tests/lib/pkg.sh
echo "lib/pkg.sh"
```

```bash edit-new=tests/lib/pkg.sh
test_update_and_upgrade_all_on_both_backends() {
  setup
  mock_command brew 0 ""
  mock_command port 0 ""
  mock_command sudo 0 ""
  export TEEUP_PACKAGE_MANAGER=homebrew
  unset TEEUP_PKG_BACKEND
  pkg_update
  pkg_upgrade_all
  assert_contains "$(cat "$MOCK_LOG")" "brew update" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew upgrade" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew upgrade --cask" || return 1
  : > "$MOCK_LOG"
  export TEEUP_PACKAGE_MANAGER=macports
  unset TEEUP_PKG_BACKEND
  pkg_update
  pkg_upgrade_all
  assert_contains "$(cat "$MOCK_LOG")" "sudo port selfupdate" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "sudo port upgrade outdated" || return 1
  cleanup_test_env
}

test_upgrade_one_package_or_cask_only_when_it_is_installed() {
  setup
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1 $2" in
  "list --formula") [ "$3" = "ripgrep" ] && exit 0 || exit 1 ;;
  "list --cask") [ "$3" = "wezterm" ] && exit 0 || exit 1 ;;
esac
exit 0
EOF2
  export TEEUP_PACKAGE_MANAGER=homebrew
  unset TEEUP_PKG_BACKEND
  local out
  out="$(pkg_upgrade ripgrep; pkg_upgrade nowhere; cask_upgrade wezterm; cask_upgrade absent)"
  assert_contains "$(cat "$MOCK_LOG")" "brew upgrade ripgrep" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew upgrade nowhere" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew upgrade --cask wezterm" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew upgrade --cask absent" || return 1
  assert_contains "$out" "Not installed here, so nothing to upgrade: nowhere" || return 1
  assert_contains "$out" "Not installed here, so nothing to upgrade: absent (cask)" || return 1
  cleanup_test_env
}

test_cask_upgrade_is_a_note_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  unset TEEUP_PKG_BACKEND
  local out rc=0
  out="$(cask_upgrade wezterm)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "Casks are not available with MacPorts" || return 1
  cleanup_test_env
}

test_upgrade_failures_are_reported() {
  setup
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1 $2" in
  "list --formula") exit 0 ;;
esac
exit 1
EOF2
  export TEEUP_PACKAGE_MANAGER=homebrew
  unset TEEUP_PKG_BACKEND
  local rc=0 out
  out="$(pkg_upgrade ripgrep 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Could not upgrade ripgrep." || return 1
  rc=0
  out="$(pkg_upgrade_all 2>&1)" || rc=$?
  assert_failure "$rc" "a failed upgrade is reported to the caller" || return 1
  cleanup_test_env
}

test_update_and_upgrade_dry_run_change_nothing() {
  setup
  mock_command brew 0 ""
  export TEEUP_PACKAGE_MANAGER=homebrew
  unset TEEUP_PKG_BACKEND
  local out
  out="$(DRY_RUN=true pkg_update; DRY_RUN=true pkg_upgrade_all)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew update" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: brew upgrade --cask" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew update" || return 1
  cleanup_test_env
}

echo "lib/pkg.sh"
```

```bash edit-old=tests/lib/pkg.sh
print_summary
```

```bash edit-new=tests/lib/pkg.sh
run_test "update and upgrade_all on both backends" test_update_and_upgrade_all_on_both_backends
run_test "upgrade one package or cask only when it is installed" test_upgrade_one_package_or_cask_only_when_it_is_installed
run_test "cask_upgrade is a note on MacPorts" test_cask_upgrade_is_a_note_on_macports
run_test "upgrade failures are reported" test_upgrade_failures_are_reported
run_test "update and upgrade dry run change nothing" test_update_and_upgrade_dry_run_change_nothing
print_summary
```

```bash edit-old=tests/lib/mise.sh
echo "lib/mise.sh"
```

```bash edit-new=tests/lib/mise.sh
test_upgrade_covers_the_global_config_and_tolerates_no_mise() {
  setup
  mock_command mise 0 ""
  mise_upgrade
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / upgrade" || return 1
  local out
  out="$(DRY_RUN=true mise_upgrade)"
  assert_contains "$out" "[DRY-RUN] Would execute: mise -C / upgrade" || return 1
  out="$(TEEUP_TEST_MISSING="mise" mise_upgrade)"
  assert_contains "$out" "mise is not installed here; skipping the mise upgrade." || return 1
  cleanup_test_env
}

echo "lib/mise.sh"
```

```bash edit-old=tests/lib/mise.sh
run_test "dev-env leaves a pinned runtime alone" test_dev_env_leaves_a_pinned_runtime_alone
print_summary
```

```bash edit-new=tests/lib/mise.sh
run_test "dev-env leaves a pinned runtime alone" test_dev_env_leaves_a_pinned_runtime_alone
run_test "upgrade covers the global config and tolerates no mise" test_upgrade_covers_the_global_config_and_tolerates_no_mise
print_summary
```

- [ ] **Step 2: Run the two suites to see them fail**

Run: `bash tests/lib/pkg.sh; bash tests/lib/mise.sh`
Expected: the five new `lib/pkg.sh` tests fail with `pkg_update: command not found`, `pkg_upgrade_all: command not found`, `pkg_upgrade: command not found` and `cask_upgrade: command not found` (`Summary: 15/20 passed`), and the new `lib/mise.sh` test with `mise_upgrade: command not found` (`Summary: 16/17 passed`).

- [ ] **Step 3: Add the package-manager verbs**

```bash edit-old=lib/pkg.sh
cask_install() {
  _pkg_backend_resolve
  local cask="$1"
  if ! casks_supported; then
    warn "Casks are not available with MacPorts; install $cask by hand."
    return 0
  fi
  if cask_installed "$cask"; then
    log "Already installed: $cask (cask)"
    return 0
  fi
  run_cmd brew install --cask "$cask" && ok "Installed $cask (cask)"
}
```

```bash edit-new=lib/pkg.sh
cask_install() {
  _pkg_backend_resolve
  local cask="$1"
  if ! casks_supported; then
    warn "Casks are not available with MacPorts; install $cask by hand."
    return 0
  fi
  if cask_installed "$cask"; then
    log "Already installed: $cask (cask)"
    return 0
  fi
  run_cmd brew install --cask "$cask" && ok "Installed $cask (cask)"
}

# pkg_update -> refresh the package manager's own index (spec section 9).
pkg_update() {
  _pkg_backend_resolve
  case "$TEEUP_PKG_BACKEND" in
    homebrew) run_cmd brew update ;;
    macports) run_privileged port selfupdate ;;
  esac
}

# pkg_upgrade_all -> upgrade everything the package manager installed.
# Homebrew keeps formulae and casks apart, so both lines are needed; MacPorts
# has no casks, so `port upgrade outdated` covers it. A non-zero exit is
# reported to the caller, which turns it into a warning: `teeup update` must
# not stop because one formula will not build, and MacPorts does not document
# the status `port upgrade outdated` returns with nothing to upgrade.
pkg_upgrade_all() {
  _pkg_backend_resolve
  local rc=0
  case "$TEEUP_PKG_BACKEND" in
    homebrew)
      run_cmd brew upgrade || rc=1
      run_cmd brew upgrade --cask || rc=1
      ;;
    macports)
      run_privileged port upgrade outdated || rc=1
      ;;
  esac
  return $rc
}

# pkg_upgrade <pkg>
# One formula or port, the candidate list the same way pkg_install reads it.
# A package this machine does not have is a log line, not an install: the
# verb that installs is `teeup install`.
pkg_upgrade() {
  _pkg_backend_resolve
  local pkg="$1" candidate
  for candidate in $(package_candidates "$pkg"); do
    if pkg_installed "$candidate"; then
      case "$TEEUP_PKG_BACKEND" in
        homebrew) run_cmd brew upgrade "$candidate" || { warn "Could not upgrade $candidate."; return 1; } ;;
        macports) run_privileged port upgrade "$candidate" || { warn "Could not upgrade $candidate."; return 1; } ;;
      esac
      return 0
    fi
  done
  log "Not installed here, so nothing to upgrade: $pkg"
  return 0
}

# cask_upgrade <cask>
cask_upgrade() {
  local cask="$1"
  if ! casks_supported; then
    log "Casks are not available with MacPorts; nothing to upgrade for $cask."
    return 0
  fi
  if ! cask_installed "$cask"; then
    log "Not installed here, so nothing to upgrade: $cask (cask)"
    return 0
  fi
  run_cmd brew upgrade --cask "$cask" || { warn "Could not upgrade the $cask cask."; return 1; }
}
```

```bash edit-old=lib/mise.sh
# dev_env_installed -> the dev-envs this machine has marked, one per line.
dev_env_installed() {
  local l
  for l in $TEEUP_DEV_ENVS; do
    state_done check "dev-env-$l" && printf '%s\n' "$l"
  done
  return 0
}
```

```bash edit-new=lib/mise.sh
# dev_env_installed -> the dev-envs this machine has marked, one per line.
dev_env_installed() {
  local l
  for l in $TEEUP_DEV_ENVS; do
    state_done check "dev-env-$l" && printf '%s\n' "$l"
  done
  return 0
}

# mise_upgrade
# `teeup update`'s mise step (spec section 9): upgrade every tool the global
# config holds, which is the AI CLIs' tools, the dev-env runtimes and anything
# else installed with `mise use -g`. `-C /` keeps it to that config, the rule
# every mise call outside a wrapper follows. A machine without mise is not an
# error: mise is a core capability, but `teeup update` also runs on a machine
# where it is in TEEUP_SKIP.
mise_upgrade() {
  if ! have mise; then
    log "mise is not installed here; skipping the mise upgrade."
    return 0
  fi
  run_cmd mise -C / upgrade || { warn "mise upgrade returned non-zero."; return 1; }
}
```

- [ ] **Step 4: Run the two suites**

Run: `bash tests/lib/pkg.sh && bash tests/lib/mise.sh`
Expected: `Summary: 20/20 passed`, `Summary: 17/17 passed`.

- [ ] **Step 5: Write the failing tests for the verb**

```bash edit-old=tests/cli.sh
# A capability with two shipped files under config/, the second rendered by
```

```bash edit-new=tests/cli.sh
# Everything `teeup update` reaches out to, mocked: the checkout is clean, the
# package manager and mise do nothing, and the fixture core.list is alpha+beta.
mock_update_world() {
  mock_command_script git <<'EOF2'
echo "git $*" >> "$MOCK_LOG"
case "$*" in
  *status*) exit 0 ;;
esac
exit 0
EOF2
  mock_command brew 0 ""
  mock_command mise 0 ""
}

test_update_walks_every_step_in_order() {
  setup
  mock_update_world
  "$TEEUP" install alpha >/dev/null
  "$TEEUP" install beta >/dev/null
  mkdir -p "$TEST_HOME/.config/teeup/hooks/post-update.d"
  printf '#!/usr/bin/env bash\necho "post-update hook:[$*]"\n' > "$TEST_HOME/.config/teeup/hooks/post-update.d/10-mark.sh"
  export TEEUP_MIGRATIONS_DIR="$TEST_HOME/migrations"
  mkdir -p "$TEEUP_MIGRATIONS_DIR"
  printf '#!/usr/bin/env bash\necho "migration ran"\n' > "$TEEUP_MIGRATIONS_DIR/1780000000.sh"
  local out
  out="$("$TEEUP" update 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "git -C $TEEUP_PATH pull --ff-only" || return 1
  assert_contains "$out" "migration ran" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew update" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew upgrade --cask" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / upgrade" || return 1
  assert_contains "$out" "configure:alpha" || return 1
  assert_contains "$out" "configure:beta" || return 1
  assert_not_contains "$out" "install:alpha" "update never installs" || return 1
  assert_contains "$out" "post-update hook:[]" || return 1
  assert_contains "$out" "teeup is up to date." || return 1
  assert_file_exists "$TEST_HOME/.local/state/teeup/migrations/1780000000.sh" || return 1
  cleanup_test_env
}

test_update_skips_core_capabilities_it_never_installed() {
  setup
  mock_update_world
  "$TEEUP" install alpha >/dev/null
  local out
  out="$(TEEUP_SKIP=alpha "$TEEUP" update 2>&1)"
  assert_contains "$out" "Skipping alpha (TEEUP_SKIP)" || return 1
  assert_contains "$out" "beta has never been installed here; run: teeup install beta" || return 1
  assert_not_contains "$out" "configure:beta" || return 1
  cleanup_test_env
}

test_update_refuses_a_dirty_checkout() {
  setup
  mock_command_script git <<'EOF2'
echo "git $*" >> "$MOCK_LOG"
case "$*" in
  *status*) echo " M lib/core.sh" ;;
esac
exit 0
EOF2
  mock_command brew 0 ""
  mock_command mise 0 ""
  local rc=0 out
  out="$("$TEEUP" update 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$TEEUP_PATH has uncommitted changes" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "git -C $TEEUP_PATH pull" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew update" "nothing after the checkout runs" || return 1
  cleanup_test_env
}

test_update_carries_on_when_the_pull_fails() {
  setup
  mock_command_script git <<'EOF2'
echo "git $*" >> "$MOCK_LOG"
case "$*" in
  *status*) exit 0 ;;
  *pull*) echo "fatal: unable to access github.com" >&2; exit 128 ;;
esac
exit 0
EOF2
  mock_command brew 0 ""
  mock_command mise 0 ""
  "$TEEUP" install alpha >/dev/null
  local rc=0 out
  out="$("$TEEUP" update 2>&1)" || rc=$?
  assert_failure "$rc" "an update with a failed step exits non-zero" || return 1
  assert_contains "$out" "git pull --ff-only failed" || return 1
  assert_contains "$out" "configure:alpha" "the rest of the update still ran" || return 1
  assert_contains "$out" "teeup update finished, with the problems above." || return 1
  cleanup_test_env
}

test_update_one_capability_upgrades_its_packages_and_configures() {
  setup
  mock_update_world
  printf 'summary="Fixture alpha"\ngroup=system\ntier=core\nrequires=""\nprovides=""\npackages="ripgrep"\ncasks="wezterm"\ninteractive=false\n' > "$TEEUP_CAPS_DIR/alpha/capability"
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1 $2" in
  "list --formula"|"list --cask") exit 0 ;;
esac
exit 0
EOF2
  "$TEEUP" install alpha >/dev/null
  : > "$MOCK_LOG"
  local out
  out="$("$TEEUP" update alpha 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "brew upgrade --cask wezterm" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew upgrade ripgrep" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew update" "one capability does not update the whole machine" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "git -C" || return 1
  assert_contains "$out" "configure:alpha" || return 1
  assert_contains "$out" "Updated alpha." || return 1
  cleanup_test_env
}

test_update_one_capability_refuses_what_it_cannot_update() {
  setup
  mock_update_world
  local rc=0 out
  out="$("$TEEUP" update nope 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Unknown capability: nope" || return 1
  rc=0
  out="$("$TEEUP" update alpha 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "alpha is not installed. Install it with: teeup install alpha" || return 1
  "$TEEUP" install alpha >/dev/null
  rc=0
  out="$(TEEUP_SKIP=alpha "$TEEUP" update alpha 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "alpha is skipped on this machine (TEEUP_SKIP)" || return 1
  assert_contains "$("$TEEUP" help)" "teeup update [<capability>]" || return 1
  cleanup_test_env
}

# Spec section 4's optional `update` script, and the metadata fallback for a
# capability that ships none (the test above this one). The script owns the
# upgrade: a capability that manages its own tool (a runtime installed from a
# tarball, an editor that updates itself) must not also have its metadata
# packages upgraded underneath it.
test_update_runs_a_capabilitys_own_update_script() {
  setup
  mock_update_world
  printf 'summary="Fixture alpha"\ngroup=system\ntier=core\nrequires=""\nprovides=""\npackages="ripgrep"\ncasks="wezterm"\ninteractive=false\n' > "$TEEUP_CAPS_DIR/alpha/capability"
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1 $2" in
  "list --formula"|"list --cask") exit 0 ;;
esac
exit 0
EOF2
  printf '#!/usr/bin/env bash\necho "update:alpha"\nrun_cmd touch "$HOME/updated"\n' > "$TEEUP_CAPS_DIR/alpha/update"
  chmod +x "$TEEUP_CAPS_DIR/alpha/update"
  "$TEEUP" install alpha >/dev/null
  : > "$MOCK_LOG"
  local out
  out="$("$TEEUP" update alpha 2>&1)"
  assert_contains "$out" "update:alpha" || return 1
  assert_file_exists "$TEST_HOME/updated" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew upgrade" "the script replaces the metadata upgrade" || return 1
  assert_contains "$out" "configure:alpha" "configure still runs after the script" || return 1
  assert_contains "$out" "Updated alpha." || return 1
  # The same capability without the script takes the metadata path again.
  rm -f "$TEEUP_CAPS_DIR/alpha/update"
  : > "$MOCK_LOG"
  out="$("$TEEUP" update alpha 2>&1)"
  assert_not_contains "$out" "update:alpha" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew upgrade ripgrep" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew upgrade --cask wezterm" || return 1
  cleanup_test_env
}

test_an_update_script_is_dry_run_and_its_failure_is_reported() {
  setup
  mock_update_world
  "$TEEUP" install alpha >/dev/null
  printf '#!/usr/bin/env bash\nrun_cmd touch "$HOME/updated"\n' > "$TEEUP_CAPS_DIR/alpha/update"
  chmod +x "$TEEUP_CAPS_DIR/alpha/update"
  local out rc=0
  out="$(DRY_RUN=true "$TEEUP" update alpha 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: touch $TEST_HOME/updated" || return 1
  [[ ! -e "$TEST_HOME/updated" ]] || { echo "the update script mutated in dry run"; return 1; }
  printf '#!/usr/bin/env bash\necho "the tool refused to update" >&2\nexit 1\n' > "$TEEUP_CAPS_DIR/alpha/update"
  out="$("$TEEUP" update alpha 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "alpha's update script failed." || return 1
  assert_contains "$out" "teeup update alpha finished, with the problems above." || return 1
  cleanup_test_env
}

test_update_dry_run_changes_nothing() {
  setup
  mock_update_world
  "$TEEUP" install alpha >/dev/null
  export TEEUP_MIGRATIONS_DIR="$TEST_HOME/migrations"
  mkdir -p "$TEEUP_MIGRATIONS_DIR"
  printf '#!/usr/bin/env bash\nrun_cmd touch "$HOME/made"\n' > "$TEEUP_MIGRATIONS_DIR/1780000000.sh"
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=true "$TEEUP" update 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: git -C $TEEUP_PATH pull --ff-only" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: touch $TEST_HOME/made" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: brew update" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: mise -C / upgrade" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "pull --ff-only" "nothing was pulled" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew update" "nothing was upgraded" || return 1
  [[ ! -e "$TEST_HOME/made" ]] || { echo "a migration mutated in dry run"; return 1; }
  [[ ! -e "$TEST_HOME/.local/state/teeup/migrations/1780000000.sh" ]] || { echo "marker written in dry run"; return 1; }
  cleanup_test_env
}

# A capability with two shipped files under config/, the second rendered by
```

```bash edit-old=tests/cli.sh
run_test "reset replaces edited files through configure" test_reset_replaces_edited_files_through_configure
```

```bash edit-new=tests/cli.sh
run_test "update walks every step in order" test_update_walks_every_step_in_order
run_test "update skips core capabilities it never installed" test_update_skips_core_capabilities_it_never_installed
run_test "update refuses a dirty checkout" test_update_refuses_a_dirty_checkout
run_test "update carries on when the pull fails" test_update_carries_on_when_the_pull_fails
run_test "update one capability upgrades its packages and configures" test_update_one_capability_upgrades_its_packages_and_configures
run_test "update one capability refuses what it cannot update" test_update_one_capability_refuses_what_it_cannot_update
run_test "update runs a capability's own update script" test_update_runs_a_capabilitys_own_update_script
run_test "an update script is dry run and its failure is reported" test_an_update_script_is_dry_run_and_its_failure_is_reported
run_test "update dry run changes nothing" test_update_dry_run_changes_nothing
run_test "reset replaces edited files through configure" test_reset_replaces_edited_files_through_configure
```

- [ ] **Step 6: Run it to see it fail**

Run: `bash tests/cli.sh`
Expected: the nine new tests fail with `Unknown verb: update`; the suite ends with `Summary: 32/41 passed`.

- [ ] **Step 7: Add the verb**

```bash edit-old=bin/teeup
  teeup reset <capability>       put its config files back to the shipped version (backups kept)
```

```bash edit-new=bin/teeup
  teeup reset <capability>       put its config files back to the shipped version (backups kept)
  teeup update [<capability>]    pull, migrate, upgrade packages, re-configure, re-theme
  teeup remove <capability>      undo what a capability installed
```

The `remove` line is written here so `usage()` reads as one list; Task 7 adds the verb itself. Add the two functions above `cmd_theme`, after `cmd_reset`:

```bash edit-old=bin/teeup
cmd_theme() {
  local op="${1:-current}" pinned
```

```bash edit-new=bin/teeup
# _update_checkout -> 0 updated, 1 could not update, 2 must not update.
# Spec section 9's first line. A checkout with local changes is the one case
# that stops the whole update: running migrations and seventeen configures
# from a half-edited tree is how a debugging session becomes a broken Mac.
# Every other failure (offline, no upstream, a diverged branch) is a warning,
# because everything after this step works from the checkout already here.
_update_checkout() {
  # -e, not -d: a linked worktree's .git is a file (it points at the real
  # repository's .git/worktrees/<name>), not a directory. TEEUP_PATH is
  # whatever checkout is running teeup, worktree or plain clone either way,
  # and the tests below run this against that same checkout, so treating a
  # worktree as "not a git checkout" would both be wrong on a real machine
  # and make the tests depend on which kind of checkout happens to be on
  # disk.
  if [[ ! -e "$TEEUP_PATH/.git" ]]; then
    log "$TEEUP_PATH is not a git checkout; nothing to pull."
    return 0
  fi
  if ! have git; then
    warn "git is not installed, so $TEEUP_PATH was not updated."
    return 1
  fi
  if [[ -n "$(git -C "$TEEUP_PATH" status --porcelain 2>/dev/null)" ]]; then
    err "$TEEUP_PATH has uncommitted changes, so teeup update will not pull."
    err "Commit, stash or discard them, then run: teeup update"
    return 2
  fi
  if ! run_cmd git -C "$TEEUP_PATH" pull --ff-only; then
    warn "git pull --ff-only failed; continuing with the checkout as it is."
    return 1
  fi
  return 0
}

# teeup update [<capability>]
# Spec section 9. Every step is idempotent, so this is also the repair path
# for a bootstrap that stopped half way. Failures are collected rather than
# fatal and the exit status reports them, so one formula that will not build
# cannot cancel the theme or the configures.
cmd_update() {
  local target="${1:-}" failed=0 name pkg cask rc=0 theme_done=false current_theme
  if [[ -n "$target" ]]; then
    cap_exists "$target" || die "Unknown capability: $target"
    if cap_skipped "$target"; then
      die "$target is skipped on this machine (TEEUP_SKIP)"
    fi
    state_done check "cap-$target" || die "$target is not installed. Install it with: teeup install $target"
    # Spec section 4: `update` is an optional member of the capability
    # contract and the metadata upgrade is its default. A capability that
    # ships one owns its upgrade completely, so the packages its metadata
    # names are left alone; `configure` runs either way, because the point of
    # both paths is a capability that works after a new version lands.
    if [[ -f "$(cap_dir "$target")/update" ]]; then
      cap_run "$target" update || { warn "$target's update script failed."; failed=1; }
    else
      for cask in $(cap_meta_get "$target" casks); do
        cask_upgrade "$cask" || failed=1
      done
      for pkg in $(cap_meta_get "$target" packages); do
        pkg_upgrade "$pkg" || failed=1
      done
    fi
    if ! cap_run "$target" configure; then
      warn "$target configure failed."
      failed=1
    fi
    hook_run post-update "$target"
    if [[ $failed -ne 0 ]]; then
      err "teeup update $target finished, with the problems above."
      exit 1
    fi
    ok "Updated $target."
    return 0
  fi

  _update_checkout || rc=$?
  if [[ $rc -eq 2 ]]; then exit 1; fi
  if [[ $rc -ne 0 ]]; then failed=1; fi

  # A later migration is written against the state an earlier one leaves, so
  # a failure stops here rather than configuring on top of it.
  migrations_run_pending || exit 1

  pkg_update || { warn "$(pkg_backend_label) could not refresh its index."; failed=1; }
  pkg_upgrade_all || { warn "$(pkg_backend_label) could not upgrade everything."; failed=1; }
  mise_upgrade || failed=1

  # core.list only (spec section 9). A capability this machine never installed
  # has no configuration to re-run, and a lazy capability's configure can
  # start a VM.
  for name in $(cap_tier_list core); do
    if ! cap_exists "$name"; then
      warn "$name is listed in core.list but not implemented yet; skipping."
      continue
    fi
    if cap_skipped "$name"; then
      log "Skipping $name (TEEUP_SKIP)"
      continue
    fi
    if ! state_done check "cap-$name"; then
      log "$name has never been installed here; run: teeup install $name"
      continue
    fi
    if cap_run "$name" configure; then
      if [[ "$name" == "theme" ]]; then theme_done=true; fi
    else
      warn "$name configure failed; continuing."
      failed=1
    fi
  done

  # The theme capability's configure already renders every template, so this
  # only covers a run where it did not happen (skipped, or not installed).
  if [[ "$theme_done" != "true" ]]; then
    current_theme="$(theme_current)"
    if [[ "$current_theme" == "none" ]]; then
      log "No theme recorded yet; pick one with: teeup theme set <name>"
    elif ! theme_set "$current_theme"; then
      warn "Could not regenerate the $current_theme theme."
      failed=1
    fi
  fi

  hook_run post-update
  if [[ $failed -ne 0 ]]; then
    err "teeup update finished, with the problems above."
    exit 1
  fi
  ok "teeup is up to date."
}

cmd_theme() {
  local op="${1:-current}" pinned
```

```bash edit-old=bin/teeup
  reset) cmd_reset "$@" ;;
```

```bash edit-new=bin/teeup
  reset) cmd_reset "$@" ;;
  update) cmd_update "$@" ;;
```

- [ ] **Step 8: Run the CLI suite**

Run: `bash tests/cli.sh`
Expected: `Summary: 41/41 passed`.

- [ ] **Step 9: Full checks and commit**

```bash
./tests/run.sh
./bin/teeup commands --check
shellcheck --severity=warning lib/pkg.sh lib/mise.sh bin/teeup tests/lib/pkg.sh tests/lib/mise.sh tests/cli.sh
git diff --check
git add lib/pkg.sh lib/mise.sh bin/teeup tests/lib/pkg.sh tests/lib/mise.sh tests/cli.sh
git commit -m "Add teeup update for the machine and for one capability"
```

Expected: the suite count printed before this task, plus 0. `commands --check`, shellcheck and `git diff --check` print nothing.

---

### Task 7: `teeup remove <capability>`

The spec's CLI surface lists `teeup remove <cap>`, and the sentence below the table says `bin/teeup` falls back "to generic implementations for `update` and `remove` from metadata". Three capabilities already ship a `remove` script (`macos-defaults`, `keyboard`, and plan 3a's `emacs`); all three undo machine state and none touches a package, so the script and the metadata are two halves of one removal.

**Files:**
- Modify: `lib/pkg.sh` (after `cask_upgrade`), `bin/teeup` (`cmd_remove`, the verb table)
- Test: `tests/lib/pkg.sh`, `tests/cli.sh`

**Interfaces:**
- Consumes: `_pkg_backend_resolve`, `package_candidates`, `pkg_installed`, `casks_supported`, `cask_installed`, `run_privileged`, `pkg_backend_label`; `cap_exists`, `cap_dir`, `cap_list`, `cap_meta_get`, `cap_run`; `state_done check`, `state_done clear`.
- Produces: `pkg_uninstall <pkg>`, `cask_uninstall <cask>`, `teeup remove <capability>`. `teeup remove` clears the capability's done marker only once every cask and package it named actually uninstalled; a failed uninstall leaves the marker set and exits non-zero, so a retry still sees the capability as installed and the leftover software is not orphaned. Plan 5a's `teeup migrate legacy` points at this verb in its messages.

**Real-Mac risk:** `brew uninstall --cask` runs the cask's own `uninstall` stanza, which for some apps asks for an administrator password or quits a running application; `port uninstall` refuses a port other ports depend on. Neither is visible under mocks.

- [ ] **Step 1: Write the failing uninstall tests**

```bash edit-old=tests/lib/pkg.sh
run_test "update and upgrade_all on both backends" test_update_and_upgrade_all_on_both_backends
```

```bash edit-new=tests/lib/pkg.sh
run_test "uninstall removes only what is installed" test_uninstall_removes_only_what_is_installed
run_test "update and upgrade_all on both backends" test_update_and_upgrade_all_on_both_backends
```

```bash edit-old=tests/lib/pkg.sh
test_update_and_upgrade_all_on_both_backends() {
```

```bash edit-new=tests/lib/pkg.sh
test_uninstall_removes_only_what_is_installed() {
  setup
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1 $2" in
  "list --formula") [ "$3" = "ripgrep" ] && exit 0 || exit 1 ;;
  "list --cask") [ "$3" = "wezterm" ] && exit 0 || exit 1 ;;
esac
exit 0
EOF2
  mock_command port 0 ""
  mock_command sudo 0 ""
  export TEEUP_PACKAGE_MANAGER=homebrew
  unset TEEUP_PKG_BACKEND
  local out
  out="$(pkg_uninstall ripgrep; pkg_uninstall nowhere; cask_uninstall wezterm; cask_uninstall absent)"
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall ripgrep" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew uninstall nowhere" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall --cask wezterm" || return 1
  assert_contains "$out" "Not installed here, so nothing to uninstall: nowhere" || return 1
  assert_contains "$out" "Not installed here, so nothing to uninstall: absent (cask)" || return 1
  : > "$MOCK_LOG"
  out="$(DRY_RUN=true cask_uninstall wezterm; DRY_RUN=true pkg_uninstall ripgrep)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew uninstall --cask wezterm" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: brew uninstall ripgrep" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew uninstall" "a dry run uninstalls nothing" || return 1
  export TEEUP_PACKAGE_MANAGER=macports
  unset TEEUP_PKG_BACKEND
  out="$(cask_uninstall wezterm)"
  assert_contains "$out" "Casks are not available with MacPorts" || return 1
  cleanup_test_env
}

test_update_and_upgrade_all_on_both_backends() {
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/lib/pkg.sh`
Expected: the new test fails with `pkg_uninstall: command not found`; the suite ends with `Summary: 20/21 passed`.

- [ ] **Step 3: Add the two uninstall verbs**

```bash edit-old=lib/pkg.sh
# cask_upgrade <cask>
cask_upgrade() {
  local cask="$1"
  if ! casks_supported; then
    log "Casks are not available with MacPorts; nothing to upgrade for $cask."
    return 0
  fi
  if ! cask_installed "$cask"; then
    log "Not installed here, so nothing to upgrade: $cask (cask)"
    return 0
  fi
  run_cmd brew upgrade --cask "$cask" || { warn "Could not upgrade the $cask cask."; return 1; }
}
```

```bash edit-new=lib/pkg.sh
# cask_upgrade <cask>
cask_upgrade() {
  local cask="$1"
  if ! casks_supported; then
    log "Casks are not available with MacPorts; nothing to upgrade for $cask."
    return 0
  fi
  if ! cask_installed "$cask"; then
    log "Not installed here, so nothing to upgrade: $cask (cask)"
    return 0
  fi
  run_cmd brew upgrade --cask "$cask" || { warn "Could not upgrade the $cask cask."; return 1; }
}

# pkg_uninstall <pkg>
# The inverse of pkg_install, for `teeup remove`. Only the candidate this
# machine actually has is uninstalled; a package that is not here is a log
# line, so removing a capability twice is not an error.
pkg_uninstall() {
  _pkg_backend_resolve
  local pkg="$1" candidate
  for candidate in $(package_candidates "$pkg"); do
    if pkg_installed "$candidate"; then
      case "$TEEUP_PKG_BACKEND" in
        homebrew) run_cmd brew uninstall "$candidate" || { warn "Could not uninstall $candidate."; return 1; } ;;
        macports) run_privileged port uninstall "$candidate" || { warn "Could not uninstall $candidate."; return 1; } ;;
      esac
      ok "Uninstalled $candidate ($(pkg_backend_label))"
      return 0
    fi
  done
  log "Not installed here, so nothing to uninstall: $pkg"
  return 0
}

# cask_uninstall <cask>
cask_uninstall() {
  local cask="$1"
  if ! casks_supported; then
    log "Casks are not available with MacPorts; remove $cask by hand if it is on this machine."
    return 0
  fi
  if ! cask_installed "$cask"; then
    log "Not installed here, so nothing to uninstall: $cask (cask)"
    return 0
  fi
  run_cmd brew uninstall --cask "$cask" || { warn "Could not uninstall the $cask cask."; return 1; }
  ok "Uninstalled $cask (cask)"
}
```

- [ ] **Step 4: Run the pkg suite**

Run: `bash tests/lib/pkg.sh`
Expected: `Summary: 21/21 passed`.

- [ ] **Step 5: Write the failing tests for the verb**

```bash edit-old=tests/cli.sh
# Everything `teeup update` reaches out to, mocked: the checkout is clean, the
```

```bash edit-new=tests/cli.sh
# A lazy capability with packages, a cask and a remove script of its own, the
# shape `teeup remove` has to handle: the script undoes machine state, the
# metadata names what to uninstall.
make_removable_cap() {
  make_cap tool lazy
  printf 'summary="Fixture tool"\ngroup=system\ntier=lazy\nrequires=""\nprovides=""\npackages="ripgrep"\ncasks="wezterm"\ninteractive=false\n' > "$TEEUP_CAPS_DIR/tool/capability"
  printf '#!/usr/bin/env bash\necho "remove:tool"\n' > "$TEEUP_CAPS_DIR/tool/remove"
  chmod +x "$TEEUP_CAPS_DIR/tool/remove"
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1 $2" in
  "list --formula"|"list --cask") exit 0 ;;
esac
exit 0
EOF2
  "$TEEUP" install tool >/dev/null
  : > "$MOCK_LOG"
}

test_remove_runs_the_script_then_uninstalls_from_metadata() {
  setup
  make_removable_cap
  local out r u
  out="$("$TEEUP" remove tool 2>&1)"
  assert_contains "$out" "remove:tool" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall --cask wezterm" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall ripgrep" || return 1
  r="$(printf '%s\n' "$out" | grep -n 'remove:tool' | head -1 | cut -d: -f1)"
  u="$(printf '%s\n' "$out" | grep -n 'Uninstalled wezterm' | head -1 | cut -d: -f1)"
  [[ "$r" -lt "$u" ]] || { echo "the remove script runs while the tool is still installed"; return 1; }
  assert_contains "$out" "Removed tool." || return 1
  "$TEEUP" has tool && { echo "the done marker must be gone"; return 1; }
  cleanup_test_env
}

test_remove_without_a_script_uses_metadata_alone() {
  setup
  make_removable_cap
  rm -f "$TEEUP_CAPS_DIR/tool/remove"
  local out
  out="$("$TEEUP" remove tool 2>&1)"
  assert_not_contains "$out" "has no remove script" "a capability without one is the normal case" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall ripgrep" || return 1
  assert_contains "$out" "Removed tool." || return 1
  cleanup_test_env
}

test_remove_refuses_what_something_else_requires() {
  setup
  mock_command brew 0 ""
  "$TEEUP" install beta >/dev/null
  local rc=0 out
  out="$("$TEEUP" remove alpha 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "alpha is required by: beta" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew uninstall" || return 1
  "$TEEUP" has alpha || { echo "nothing was removed"; return 1; }
  rc=0
  out="$("$TEEUP" remove nope 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Unknown capability: nope" || return 1
  rc=0
  out="$("$TEEUP" remove lazyone 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "lazyone is not installed here." || return 1
  assert_contains "$("$TEEUP" help)" "teeup remove <capability>" || return 1
  cleanup_test_env
}

test_remove_keeps_config_files_and_previews_a_dry_run() {
  setup
  make_removable_cap
  mkdir -p "$TEEUP_CAPS_DIR/tool/config"
  printf 'shipped=1\n' > "$TEEUP_CAPS_DIR/tool/config/tool.conf"
  local out
  out="$(DRY_RUN=true "$TEEUP" remove tool 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew uninstall --cask wezterm" || return 1
  assert_contains "$out" "[DRY-RUN] Would clear state: done/cap-tool" || return 1
  assert_contains "$out" "Your configuration files for tool were left in place." || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew uninstall" "nothing was uninstalled" || return 1
  "$TEEUP" has tool || { echo "the marker must survive a dry run"; return 1; }
  cleanup_test_env
}

test_remove_keeps_the_marker_when_an_uninstall_fails() {
  setup
  make_removable_cap
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1 $2" in
  "uninstall --cask") exit 1 ;;
  "list --formula"|"list --cask") exit 0 ;;
esac
exit 0
EOF2
  local rc=0 out
  out="$("$TEEUP" remove tool 2>&1)" || rc=$?
  assert_failure "$rc" "a failed uninstall must reach the exit status" || return 1
  assert_contains "$out" "Could not uninstall the wezterm cask." || return 1
  assert_contains "$out" "Leaving tool marked installed" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall ripgrep" "the package uninstall still runs" || return 1
  "$TEEUP" has tool || { echo "the marker must survive a failed uninstall, so a retry can find the leftover cask"; return 1; }
  cleanup_test_env
}

# Everything `teeup update` reaches out to, mocked: the checkout is clean, the
```

```bash edit-old=tests/cli.sh
run_test "update walks every step in order" test_update_walks_every_step_in_order
```

```bash edit-new=tests/cli.sh
run_test "remove runs the script then uninstalls from metadata" test_remove_runs_the_script_then_uninstalls_from_metadata
run_test "remove without a script uses metadata alone" test_remove_without_a_script_uses_metadata_alone
run_test "remove refuses what something else requires" test_remove_refuses_what_something_else_requires
run_test "remove keeps config files and previews a dry run" test_remove_keeps_config_files_and_previews_a_dry_run
run_test "remove keeps the marker when an uninstall fails" test_remove_keeps_the_marker_when_an_uninstall_fails
run_test "update walks every step in order" test_update_walks_every_step_in_order
```

- [ ] **Step 6: Run it to see it fail**

Run: `bash tests/cli.sh`
Expected: the five new tests fail with `Unknown verb: remove`; the suite ends with `Summary: 41/46 passed`.

- [ ] **Step 7: Add the verb**

```bash edit-old=bin/teeup
# _update_checkout -> 0 updated, 1 could not update, 2 must not update.
```

```bash edit-new=bin/teeup
# teeup remove <capability>
# The inverse of `teeup install`, read from metadata. A capability that ships
# a remove script owns the machine state it set up (a LaunchAgent, recorded
# `defaults`, a hidutil mapping); that script runs first, while its tool is
# still installed, and then the casks and packages its metadata names are
# uninstalled. Configuration files stay where they are: they are the user's,
# and re-installing the capability could not bring them back. A lazy
# capability keeps its shim, so typing its command offers to install it again.
cmd_remove() {
  local target="${1:-}" dependents="" name cask pkg failed=0 tier
  [[ -n "$target" ]] || die "Usage: teeup remove <capability>"
  cap_exists "$target" || die "Unknown capability: $target"
  state_done check "cap-$target" || die "$target is not installed here."
  for name in $(cap_list); do
    if [[ "$name" == "$target" ]]; then continue; fi
    if ! state_done check "cap-$name"; then continue; fi
    case " $(cap_meta_get "$name" requires) " in
      *" $target "*) dependents="$dependents $name" ;;
    esac
  done
  if [[ -n "$dependents" ]]; then
    die "$target is required by:$dependents. Remove those first, then $target."
  fi
  if [[ -f "$(cap_dir "$target")/remove" ]]; then
    cap_run "$target" remove || die "$target's remove script failed; nothing was uninstalled."
  fi
  for cask in $(cap_meta_get "$target" casks); do
    cask_uninstall "$cask" || failed=1
  done
  for pkg in $(cap_meta_get "$target" packages); do
    pkg_uninstall "$pkg" || failed=1
  done
  # Only clear the done marker once every cask and package is actually gone.
  # Clearing it after a failed uninstall would make a retry see the
  # capability as not installed, and the leftover software could then never
  # be removed: cmd_install would skip it ("Already installed") and
  # cmd_remove itself would refuse with "not installed here".
  if [[ $failed -eq 0 ]]; then
    state_done clear "cap-$target"
  else
    warn "Leaving $target marked installed since something above failed; fix it and run teeup remove $target again."
  fi
  if [[ -d "$(cap_dir "$target")/config" || -d "$(cap_dir "$target")/home" ]]; then
    log "Your configuration files for $target were left in place."
  fi
  tier="$(cap_meta_get "$target" tier)"
  if [[ "$tier" != "lazy" ]]; then
    log "$target is in the $tier tier, so the next ./bootstrap installs it again unless machines/<hostname>.conf sets TEEUP_SKIP."
  fi
  if [[ $failed -ne 0 ]]; then
    err "teeup remove $target finished, with the problems above."
    exit 1
  fi
  ok "Removed $target."
}

# _update_checkout -> 0 updated, 1 could not update, 2 must not update.
```

```bash edit-old=bin/teeup
  update) cmd_update "$@" ;;
```

```bash edit-new=bin/teeup
  update) cmd_update "$@" ;;
  remove) cmd_remove "$@" ;;
```

- [ ] **Step 8: Run the CLI suite**

Run: `bash tests/cli.sh`
Expected: `Summary: 46/46 passed`.

- [ ] **Step 9: Full checks and commit**

```bash
./tests/run.sh
./bin/teeup commands --check
shellcheck --severity=warning lib/pkg.sh bin/teeup tests/lib/pkg.sh tests/cli.sh
git diff --check
git add lib/pkg.sh bin/teeup tests/lib/pkg.sh tests/cli.sh
git commit -m "Add teeup remove from capability metadata"
```

Expected: the suite count printed before this task, plus 0. `commands --check`, shellcheck and `git diff --check` print nothing.

---

### Task 8: Quieter re-runs — `defaults_write` change detection and the AeroSpace notice

`teeup update` re-runs every core `configure`, which makes two habits from phase 2b expensive. `macos-defaults/configure` ends with `killall Finder` and `killall Dock` unconditionally, so every update closes every Finder window and re-hides the Dock even when nothing changed; `aerospace/configure` prints a five-line manual step every time, which is how people learn to skip it. Both are on pr11's deferred list.

These two are the last core configures that mutate on a re-run, so the task ends with the spec's Verification gate: "Idempotency: run `./bootstrap` twice under the harness and assert the second run performs no mutations." Nothing asserts it today — `tests/bootstrap.sh`'s `dry run touches nothing` is the different claim that a *dry* run writes nothing — and after this task the property is true, so Step 9 writes the test that holds it true.

**Files:**
- Modify: `lib/macos.sh` (`defaults_write`, plus `_defaults_same` and `defaults_changed`), `capabilities/macos-defaults/configure`, `capabilities/aerospace/configure`
- Test: `tests/lib/macos.sh`, `tests/capabilities/macos-defaults.sh`, `tests/capabilities/aerospace.sh`, `tests/bootstrap.sh`

**Interfaces:**
- Consumes: `_defaults_record_path`, `_defaults_record`, `_defaults_flag`, `_defaults_bool` (`lib/macos.sh`); `run_cmd`; `state_done ensure` (`lib/state.sh`).
- Produces: `TEEUP_DEFAULTS_CHANGED` (the domains written in this process, space-delimited), `_defaults_same <flag> <value> <read-type> <prior>` and `defaults_changed <domain>`. 4b's `doctor` for `macos-defaults` reads neither; nothing else in this plan consumes them. In `tests/bootstrap.sh`: `mock_a_real_machine` and `home_state`, which only the new test uses.

**Real-Mac risk:** all of the comparison. `defaults read` prints a float as `0.5` or `0.5000`, a string with no quotes, and a boolean as `1`/`0`; `defaults read-type` prints `Type is boolean`. The mock follows what `defaults(1)` documents, and only a Mac shows whether a real `com.apple.screencapture location` round-trips byte for byte (a trailing slash, a `~` expansion). A false "changed" costs one `killall`; a false "already set" would leave a preference unwritten, which `teeup doctor` in 4b is the place to catch.

- [ ] **Step 1: Write the failing library tests**

```bash edit-old=tests/lib/macos.sh
test_defaults_write_dry_run_records_nothing() {
```

```bash edit-new=tests/lib/macos.sh
test_defaults_write_leaves_a_value_already_set_alone() {
  setup
  mock_defaults_db
  seed_default com.apple.dock autohide boolean 1
  seed_default NSGlobalDomain KeyRepeat integer 2
  seed_default com.apple.screencapture location string "/Users/ada/My Shots & more"
  local out
  out="$(
    defaults_write com.apple.dock autohide -bool true
    defaults_write NSGlobalDomain KeyRepeat -int 2
    defaults_write com.apple.screencapture location -string "/Users/ada/My Shots & more"
    defaults_changed com.apple.dock && echo "dock changed"
    echo "changed:[$TEEUP_DEFAULTS_CHANGED]"
  )"
  assert_contains "$out" "Already set: com.apple.dock autohide" || return 1
  assert_contains "$out" "Already set: NSGlobalDomain KeyRepeat" || return 1
  assert_contains "$out" "Already set: com.apple.screencapture location" || return 1
  assert_not_contains "$out" "dock changed" || return 1
  assert_contains "$out" "changed:[ ]" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "defaults write" "nothing was written" || return 1
  assert_equals "-bool:true" "$(cat "$TEST_HOME/.local/state/teeup/defaults/com.apple.dock.autohide")" "the prior value is still recorded" || return 1
  cleanup_test_env
}

test_defaults_write_writes_a_different_value_or_type_and_names_the_domain() {
  setup
  mock_defaults_db
  seed_default com.apple.dock autohide boolean 0
  # The same text under another type is a change: teeup writes a real boolean.
  seed_default com.apple.finder AppleShowAllFiles string true
  local out d
  out="$(
    defaults_write com.apple.dock autohide -bool true
    defaults_write com.apple.finder AppleShowAllFiles -bool true
    defaults_write NSGlobalDomain KeyRepeat -int 2
    for d in com.apple.dock com.apple.finder NSGlobalDomain com.apple.screencapture; do
      if defaults_changed "$d"; then echo "changed:$d"; fi
    done
  )"
  assert_contains "$out" "changed:com.apple.dock" || return 1
  assert_contains "$out" "changed:com.apple.finder" || return 1
  assert_contains "$out" "changed:NSGlobalDomain" "an absent key is written" || return 1
  assert_not_contains "$out" "changed:com.apple.screencapture" || return 1
  assert_equals "$(printf 'boolean\ntrue')" "$(cat "$DDB/com.apple.finder.AppleShowAllFiles")" || return 1
  cleanup_test_env
}

test_defaults_write_dry_run_records_nothing() {
```

```bash edit-old=tests/lib/macos.sh
run_test "defaults_write dry run records nothing" test_defaults_write_dry_run_records_nothing
```

```bash edit-new=tests/lib/macos.sh
run_test "defaults_write leaves a value already set alone" test_defaults_write_leaves_a_value_already_set_alone
run_test "defaults_write writes a different value or type and names the domain" test_defaults_write_writes_a_different_value_or_type_and_names_the_domain
run_test "defaults_write dry run records nothing" test_defaults_write_dry_run_records_nothing
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/lib/macos.sh`
Expected: both new tests fail — the first because `defaults write` is logged and `Already set:` never appears, the second with `defaults_changed: command not found`; the suite ends with `Summary: 16/18 passed`.

- [ ] **Step 3: Compare before writing**

```bash edit-old=lib/macos.sh
# defaults_write <domain> <key> <type> <value>
# Records what was there before the first time teeup touches a key, so
```

```bash edit-new=lib/macos.sh
# The domains defaults_write has written a key of in this process, each
# surrounded by spaces (bash 3.2 has no associative arrays).
TEEUP_DEFAULTS_CHANGED=" "

# defaults_write <domain> <key> <type> <value>
# Records what was there before the first time teeup touches a key, so
```

```bash edit-old=lib/macos.sh
# defaults_restore can say what it is leaving alone. Only the first line of a
# prior value is kept.
# real-Mac check: `defaults read-type <domain> <key>` prints "Type is boolean"
# (integer, float, string, array, dictionary, data, date), and `write -bool`
# accepts true/false.
defaults_write() {
  local domain="$1" key="$2" type="$3" value="$4" record prior ptype flag
  record="$(_defaults_record_path "$domain" "$key")"
  if [[ ! -f "$record" ]]; then
    if defaults read "$domain" "$key" >/dev/null 2>&1; then
      prior="$(defaults read "$domain" "$key" 2>/dev/null | head -1)"
      ptype="$(defaults read-type "$domain" "$key" 2>/dev/null | sed -n 's/^Type is //p' | head -1)"
      if flag="$(_defaults_flag "$ptype")"; then
        if [[ "$flag" == "-bool" ]]; then prior="$(_defaults_bool "$prior")"; fi
        _defaults_record "$record" "$flag:$prior"
      else
        _defaults_record "$record" "${ptype:-unknown}:$prior"
      fi
    else
      _defaults_record "$record" "absent"
    fi
  fi
  run_cmd defaults write "$domain" "$key" "$type" "$value"
}
```

```bash edit-new=lib/macos.sh
# defaults_restore can say what it is leaving alone. Only the first line of a
# prior value is kept.
#
# A key that already holds <value> as <type> is left alone ("Already set"), so
# a second configure writes nothing. Each key that is written adds its domain
# to TEEUP_DEFAULTS_CHANGED, which defaults_changed reads: a caller restarts
# Finder or the Dock only when one of their keys changed in this run.
# real-Mac check: `defaults read-type <domain> <key>` prints "Type is boolean"
# (integer, float, string, array, dictionary, data, date), and `write -bool`
# accepts true/false.
defaults_write() {
  local domain="$1" key="$2" type="$3" value="$4" record prior="" ptype="" flag present=false recorded
  record="$(_defaults_record_path "$domain" "$key")"
  if prior="$(defaults read "$domain" "$key" 2>/dev/null)"; then
    present=true
    prior="$(printf '%s\n' "$prior" | head -1)"
    ptype="$(defaults read-type "$domain" "$key" 2>/dev/null | sed -n 's/^Type is //p' | head -1)"
  fi
  if [[ ! -f "$record" ]]; then
    if [[ "$present" == "true" ]]; then
      if flag="$(_defaults_flag "$ptype")"; then
        recorded="$prior"
        if [[ "$flag" == "-bool" ]]; then recorded="$(_defaults_bool "$prior")"; fi
        _defaults_record "$record" "$flag:$recorded"
      else
        _defaults_record "$record" "${ptype:-unknown}:$prior"
      fi
    else
      _defaults_record "$record" "absent"
    fi
  fi
  if [[ "$present" == "true" ]] && _defaults_same "$type" "$value" "$ptype" "$prior"; then
    log "Already set: $domain $key"
    return 0
  fi
  run_cmd defaults write "$domain" "$key" "$type" "$value" || return $?
  case "$TEEUP_DEFAULTS_CHANGED" in
    *" $domain "*) ;;
    *) TEEUP_DEFAULTS_CHANGED="$TEEUP_DEFAULTS_CHANGED$domain " ;;
  esac
}

# _defaults_same <flag> <value> <read-type name> <value as defaults read printed it>
# True only when the stored type is the one <flag> writes and the values
# agree; a hand-set `-string YES` where teeup writes `-bool true` is a change.
# Booleans compare through _defaults_bool (read prints 1, teeup writes true).
_defaults_same() {
  local flag="$1" value="$2" ptype="$3" prior="$4"
  case "$flag" in
    -bool) [[ "$ptype" == "boolean" && "$(_defaults_bool "$prior")" == "$(_defaults_bool "$value")" ]] ;;
    -int) [[ "$ptype" == "integer" && "$prior" == "$value" ]] ;;
    -float) [[ "$ptype" == "float" && "$prior" == "$value" ]] ;;
    -string) [[ "$ptype" == "string" && "$prior" == "$value" ]] ;;
    *) return 1 ;;
  esac
}

# defaults_changed <domain> -> exit 0 when defaults_write wrote a key of
# <domain> in this process.
defaults_changed() {
  case "$TEEUP_DEFAULTS_CHANGED" in
    *" $1 "*) return 0 ;;
  esac
  return 1
}
```

- [ ] **Step 4: Run the macos suite**

Run: `bash tests/lib/macos.sh`
Expected: `Summary: 18/18 passed`.

- [ ] **Step 5: Write the failing capability tests**

```bash edit-old=tests/capabilities/macos-defaults.sh
test_configure_dry_run_writes_nothing() {
```

```bash edit-new=tests/capabilities/macos-defaults.sh
test_a_second_configure_writes_nothing_and_restarts_nothing() {
  setup
  mock_defaults_db
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "killall Finder" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "killall Dock" || return 1
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure macos-defaults)"
  assert_not_contains "$(cat "$MOCK_LOG")" "defaults write" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "killall" "Finder and the Dock keep running when nothing changed" || return 1
  assert_contains "$out" "Already set: com.apple.dock autohide" || return 1
  assert_contains "$out" "macOS preferences already set; nothing to restart." || return 1
  cleanup_test_env
}

test_a_dock_change_restarts_only_the_dock() {
  setup
  mock_defaults_db
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  seed_default com.apple.dock autohide boolean 0
  : > "$MOCK_LOG"
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "defaults write com.apple.dock autohide -bool true" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "killall Dock" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "killall Finder" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
```

```bash edit-old=tests/capabilities/macos-defaults.sh
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
```

```bash edit-new=tests/capabilities/macos-defaults.sh
run_test "a second configure writes nothing and restarts nothing" test_a_second_configure_writes_nothing_and_restarts_nothing
run_test "a Dock change restarts only the Dock" test_a_dock_change_restarts_only_the_dock
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
```

```bash edit-old=tests/capabilities/aerospace.sh
test_configure_keeps_an_existing_home_config() {
```

```bash edit-new=tests/capabilities/aerospace.sh
test_the_manual_step_is_printed_in_full_once() {
  setup
  DRY_RUN=false "$TEEUP" configure aerospace >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure aerospace)"
  assert_not_contains "$out" "One manual step, once per machine" || return 1
  assert_contains "$out" "If AeroSpace cannot move windows, turn it on under System Settings > Privacy & Security > Accessibility." || return 1
  cleanup_test_env
}

test_configure_keeps_an_existing_home_config() {
```

```bash edit-old=tests/capabilities/aerospace.sh
run_test "configure keeps an existing ~/.aerospace.toml" test_configure_keeps_an_existing_home_config
```

```bash edit-new=tests/capabilities/aerospace.sh
run_test "the manual step is printed in full once" test_the_manual_step_is_printed_in_full_once
run_test "configure keeps an existing ~/.aerospace.toml" test_configure_keeps_an_existing_home_config
```

- [ ] **Step 6: Run the two suites to see them fail**

Run: `bash tests/capabilities/macos-defaults.sh; bash tests/capabilities/aerospace.sh`
Expected: `a second configure writes nothing and restarts nothing` fails on the `killall` that still runs, `a Dock change restarts only the Dock` on the `killall Finder` that also runs, and `the manual step is printed in full once` on the block printing twice. The suites end with `Summary: 9/11 passed` and `Summary: 10/11 passed`.

- [ ] **Step 7: Restart what changed, and print the step once**

```bash edit-old=capabilities/macos-defaults/configure
# Finder and Dock read most of these only at start. killall fails when a
# process is not running, which must not abort the script.
run_cmd killall Finder || true
run_cmd killall Dock || true
ok "macOS preferences applied. KeyRepeat and InitialKeyRepeat take effect after the next login."
```

```bash edit-new=capabilities/macos-defaults/configure
# Finder and the Dock read most of these only at start, so each is restarted,
# and only when defaults_write changed one of its keys in this run: teeup
# update re-runs this configure, and a run that changes nothing must not
# close every Finder window. AppleShowAllExtensions lives in the global domain
# but is Finder's. killall fails when a process is not running, which must not
# abort the script.
if defaults_changed com.apple.finder || defaults_changed NSGlobalDomain; then
  run_cmd killall Finder || true
fi
if defaults_changed com.apple.dock; then
  run_cmd killall Dock || true
fi
if [[ "$TEEUP_DEFAULTS_CHANGED" == " " ]]; then
  ok "macOS preferences already set; nothing to restart."
else
  ok "macOS preferences applied. KeyRepeat and InitialKeyRepeat take effect after the next login."
fi
```

```bash edit-old=capabilities/aerospace/configure
# No script can grant Accessibility: macOS requires a human in System Settings,
# and doctor re-checks the part of this that is checkable.
cat <<'STEP'
One manual step, once per machine:
  System Settings > Privacy & Security > Accessibility > turn AeroSpace on
Until you do, AeroSpace cannot move a single window. Then start it with:
  open -a AeroSpace
STEP
```

```bash edit-new=capabilities/aerospace/configure
# No script can grant Accessibility: macOS requires a human in System Settings,
# and doctor re-checks the part of this that is checkable. The step is printed
# in full the first time only (state_done ensure succeeds once per machine):
# teeup update re-runs every core configure, and the block on every update
# would train people to skip it. Later runs print one line.
if state_done ensure aerospace-accessibility-notice; then
  cat <<'STEP'
One manual step, once per machine:
  System Settings > Privacy & Security > Accessibility > turn AeroSpace on
Until you do, AeroSpace cannot move a single window. Then start it with:
  open -a AeroSpace
STEP
else
  log "If AeroSpace cannot move windows, turn it on under System Settings > Privacy & Security > Accessibility."
fi
```

- [ ] **Step 8: Run the three suites**

Run: `bash tests/lib/macos.sh && bash tests/capabilities/macos-defaults.sh && bash tests/capabilities/aerospace.sh`
Expected: `Summary: 18/18 passed`, `Summary: 11/11 passed`, `Summary: 11/11 passed`.

- [ ] **Step 9: The spec's idempotency gate — `./bootstrap` twice**

The dry-run walk this suite is built on cannot answer the gate: it never writes, so a second dry run trivially writes nothing. The test below runs the real thing twice with `DRY_RUN=false`, which needs a fuller mock machine (a package manager that remembers what it installed, an `ssh-keygen` that really makes the pair, a `defaults` that keeps what was written, and the macOS-only commands the capabilities call). Everything still lands inside `$TEST_HOME`; `curl` is mocked to fail so nothing can reach the network.

It asserts three things about the second run: every file under `$HOME` has the same contents afterwards (and none appeared or disappeared), nothing outside `~/.local/state/teeup` was even rewritten, and the output is the "Already ..." vocabulary rather than the words the first run prints. The state directory is excluded from the *rewrite* check on purpose, not from the contents check: a second bootstrap re-stamps its own zero-byte `done/` markers and re-renders the theme to byte-identical files. `~/.config/wezterm/wezterm.lua` is the one file outside it that is touched deliberately (`theme-apply` touches it so a running WezTerm reloads), and its contents are compared like every other file's.

```bash edit-old=tests/bootstrap.sh
test_dry_run_touches_nothing() {
```

```bash edit-new=tests/bootstrap.sh
# The spec's Verification gate asks for two real (DRY_RUN=false) bootstraps,
# which needs more of the machine than the dry-run walk above: a package
# manager that remembers what it installed, keys that really appear, a
# defaults database that keeps what was written, and the macOS-only commands
# the capabilities call. Everything still lands inside $TEST_HOME.
mock_a_real_machine() {
  # brew is hidden in setup so the dry-run walk sees a fresh Mac. Here it has
  # to be visible: `have brew` gates pkg_installed and cask_installed, and
  # with it missing every check is false and the second bootstrap reinstalls
  # the lot.
  export TEEUP_TEST_MISSING="gum jq starship rg fd fzf bat eza zoxide yq btop tldr dust gpg delta git-lfs lazygit emacs emacsclient"
  export BREWDB="$TEST_HOME/brewdb"
  mkdir -p "$BREWDB"
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "list --formula") [ -f "$BREWDB/f-$3" ] ;;
  "list --cask") [ -f "$BREWDB/c-${3##*/}" ] ;;
  "install --cask") shift 2; for c in "$@"; do touch "$BREWDB/c-${c##*/}"; done ;;
  "install "*) shift; for p in "$@"; do touch "$BREWDB/f-$p"; done ;;
  *) : ;;
esac
EOF2
  # pkg_backend_prepare looks for brew at the prefix, not on PATH; with it
  # there the Homebrew installer (a curl | bash) never runs. curl fails for
  # the same reason: nothing in a test may reach the network.
  mkdir -p "$TEEUP_PKG_PREFIX/bin"
  cp "$MOCK_BIN/brew" "$TEEUP_PKG_PREFIX/bin/brew"
  mock_command curl 1 ""
  mock_command launchctl 0 ""
  mock_command hidutil 0 ""
  mock_command killall 0 ""
  mock_command open 0 ""
  mock_command osascript 0 ""
  mock_command mas 0 ""
  # ssh-keygen writes the pair it is asked for, so the second run finds it.
  mock_command_script ssh-keygen <<'EOF2'
prev=""
for a in "$@"; do
  [ "$prev" = "-f" ] && { printf 'key\n' > "$a"; printf 'ssh-ed25519 AAAA test\n' > "$a.pub"; }
  prev="$a"
done
exit 0
EOF2
  # A gh that is already signed in with the scopes the github capability wants.
  printf 'admin:public_key\n' > "$TEST_HOME/gh-session"
  # A stateful defaults(1): what configure writes, the next read returns, so
  # the second run finds every preference already set. Same shape as the one
  # in tests/lib/macos.sh, without the write validation that suite needs.
  export DDB="$TEST_HOME/defaults-db"
  mkdir -p "$DDB"
  mock_command_script defaults <<'EOF2'
op="$1"; shift
f="$DDB/$1.$2"
case "$op" in
  read)
    [ -f "$f" ] || exit 1
    t="$(head -1 "$f")"; v="$(tail -n +2 "$f")"
    if [ "$t" = boolean ]; then
      case "$v" in [Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|1) echo 1 ;; *) echo 0 ;; esac
    else
      printf '%s\n' "$v"
    fi
    ;;
  read-type) [ -f "$f" ] || exit 1; echo "Type is $(head -1 "$f")" ;;
  write)
    case "$3" in
      -bool) t=boolean ;;
      -int) t=integer ;;
      -float) t=float ;;
      -string) t=string ;;
      *) exit 1 ;;
    esac
    printf '%s\n%s\n' "$t" "$4" > "$f"
    ;;
  delete) rm -f "$f" ;;
esac
EOF2
}

# home_state -> every file under $HOME with a checksum of its contents, one
# per line, sorted. The harness's own scratch (the mock log, the marker, the
# bootstrap log) is left out; everything else, including symlink targets, is
# in. Two identical listings mean the second run changed nothing at all.
home_state() {
  ( cd "$TEST_HOME" && find . \( -type f -o -type l \) \
      ! -name 'mock.log' ! -name '.idempotency-marker' \
      ! -path './.local/state/teeup/logs/*' -print0 \
    | LC_ALL=C sort -z \
    | while IFS= read -r -d '' f; do
        if [[ -L "$f" ]]; then printf '%s link:%s\n' "$f" "$(readlink "$f")"
        else printf '%s %s\n' "$f" "$(cksum < "$f")"
        fi
      done )
}

test_a_second_bootstrap_changes_nothing() {
  setup
  mock_a_real_machine
  export DRY_RUN=false
  "$BOOT" <<<"$WIZARD_INPUT" >/dev/null 2>&1 || { echo "the first bootstrap failed"; return 1; }
  local marker="$TEST_HOME/.idempotency-marker"
  : > "$marker"
  local before after out
  before="$(home_state)"
  out="$("$BOOT" </dev/null 2>&1)" || { echo "the second bootstrap failed"; return 1; }
  after="$(home_state)"
  assert_equals "$before" "$after" "the second bootstrap changed a file under \$HOME" || return 1
  # Nothing outside teeup's own state directory may even be rewritten.
  # wezterm.lua is the one exception and it is deliberate: theme-apply touches
  # it so a running WezTerm reloads (its contents are in the comparison above).
  local written
  written="$(find "$TEST_HOME" -newer "$marker" \( -type f -o -type l \) \
    ! -name 'mock.log' ! -name '.idempotency-marker' \
    ! -path "$TEST_HOME/.local/state/teeup/*" \
    ! -path "$TEST_HOME/.config/wezterm/wezterm.lua" 2>/dev/null)"
  assert_equals "" "$written" "the second bootstrap wrote outside the state directory" || return 1
  # And it says so: every step reports what is already there.
  assert_contains "$out" "Homebrew already installed." || return 1
  assert_contains "$out" "Already installed: gum" || return 1
  assert_contains "$out" "Already current: $TEST_HOME/.config/teeup/env" || return 1
  assert_contains "$out" "Already installed: $TEST_HOME/.zshrc" || return 1
  assert_contains "$out" "Already present: $TEST_HOME/Work" || return 1
  assert_contains "$out" "Already signed in to GitHub." || return 1
  assert_contains "$out" "macOS preferences already set; nothing to restart." || return 1
  assert_not_contains "$out" "Installed ripgrep (Homebrew)" "nothing was installed again" || return 1
  assert_not_contains "$out" "Installed wezterm (cask)" "no cask was installed again" || return 1
  assert_not_contains "$out" "Generating the" "the keys were left alone" || return 1
  assert_not_contains "$out" "One manual step" "the AeroSpace block is printed once" || return 1
  cleanup_test_env
}
test_dry_run_touches_nothing() {
```

```bash edit-old=tests/bootstrap.sh
run_test "dry run touches nothing" test_dry_run_touches_nothing
```

```bash edit-new=tests/bootstrap.sh
run_test "a second bootstrap changes nothing" test_a_second_bootstrap_changes_nothing
run_test "dry run touches nothing" test_dry_run_touches_nothing
```

- [ ] **Step 10: Run the bootstrap suite**

Run: `bash tests/bootstrap.sh`
Expected: `Summary: 27/27 passed`. The new test is the slowest in the repository (two real bootstraps, roughly half a minute together); it is one test in the suite the worker pool already schedules first.

Run it against the tree as it was before Step 3 and Step 7 to see what it holds: `macOS preferences already set; nothing to restart.` is missing, `One manual step` is printed again, and the second run rewrites `~/Library/LaunchAgents` and the defaults records.

- [ ] **Step 11: Full checks and commit**

```bash
./tests/run.sh
./bin/teeup commands --check
shellcheck --severity=warning lib/macos.sh capabilities/macos-defaults/configure capabilities/aerospace/configure tests/lib/macos.sh tests/capabilities/macos-defaults.sh tests/capabilities/aerospace.sh tests/bootstrap.sh
git diff --check
git add lib/macos.sh capabilities/macos-defaults/configure capabilities/aerospace/configure tests/lib/macos.sh tests/capabilities/macos-defaults.sh tests/capabilities/aerospace.sh tests/bootstrap.sh
git commit -m "Restart Finder and the Dock only when a preference changed"
```

Expected: the suite count printed before this task, plus 0. `commands --check`, shellcheck and `git diff --check` print nothing.

---

### Task 9: README and contributor documentation

Four verbs, three hook events and a migrations directory exist now and nothing says so. This task adds one README section and four items to CONTRIBUTING's "Adding a capability (new runtime)" list.

**Files:**
- Modify: `README.md`, `CONTRIBUTING.md`

**Interfaces:**
- Consumes: everything Tasks 1 to 8 produced.
- Produces: documentation only.

**Real-Mac risk:** none. The commands the section shows are the ones the suite covers under mocks; whether a real `teeup update` takes two minutes or twenty is the risk Task 6 carries.

- [ ] **Step 1: Add the README section**

The anchor is the last line of plan 3b's "Lazy capabilities" section. Plan 4d's "Themes" section goes after plan 3a's "Editors" section, higher up, so the two do not collide.

````markdown edit-old=README.md
  `teeup status` lists the shims in place and the dev-envs installed.
````

````markdown edit-new=README.md
  `teeup status` lists the shims in place and the dev-envs installed.

### Keeping a Mac up to date

```bash
teeup update                  # the whole machine
DRY_RUN=true teeup update      # ... as a preview that changes nothing
teeup update wezterm          # one capability: its packages, then its configure
teeup reset starship          # the shipped starship.toml back, your copy backed up
teeup remove cursor           # undo what a capability installed
```

`teeup update` does spec section 9's list in order: `git pull --ff-only` in
the checkout, any pending migrations, `brew update && brew upgrade && brew
upgrade --cask` (or `port selfupdate && port upgrade outdated`), `mise
upgrade`, `configure` again for every installed core capability, the theme
re-rendered, and your `post-update` hooks. A checkout with uncommitted
changes stops it before anything else runs, and so does a migration that
fails; every other problem is a warning, and the command exits non-zero when
there was one. Offline, the pull and the package manager warn and the rest
still runs, which makes `teeup update` the repair path for a bootstrap that
stopped half way.

- **Migrations** are `migrations/<epoch>.sh` in the checkout, each run once
  per machine (`teeup dev add-migration` starts one, named from the last
  commit). A fresh `./bootstrap` marks them all applied without running them.
  A migration that ships a changed config calls `migration_refresh <cap>`,
  which replaces the copies nobody edited and leaves an edited one alone.
- **`teeup reset <cap>`** re-runs the capability's own `configure` with every
  `copy_config_once` turned into "back up, replace, show the diff", so a file
  teeup renders for this machine (the zsh home files, `~/.config/git/config`)
  comes back rendered rather than as a raw template. A backup whose content
  matched the shipped file is deleted again, and the theme and font hooks run
  afterwards, so a reset `starship.toml` carries the current palette.
- **`teeup remove <cap>`** runs the capability's own `remove` script when it
  has one (`macos-defaults` puts every preference back the way it found it,
  `emacs` unloads its daemon), then uninstalls the casks and packages its
  metadata names, then forgets it. Your configuration files stay where they
  are. It refuses while another installed capability requires it.
- **Hooks** are your own scripts under
  `~/.config/teeup/hooks/<event>.d/`, run with `bash` in file-name order.
  The events are `post-bootstrap`, `post-update` (with the capability name
  after `teeup update <cap>`) and `theme-set` (with the theme name). Each
  directory holds an `example.sample` that documents it; `.sample` files
  never run. A hook that fails prints a warning and nothing is aborted.
````

- [ ] **Step 2: Append four items to CONTRIBUTING's "Adding a capability (new runtime)" list**

Append after the last numbered item of that list, continuing its numbering, and renumber nothing. Running after plans 3a and 3b, that last item is 19 (the `TEEUP_TEST_TTY` and `hide_host_commands` item, whose last line is the one quoted below), so these are 20 to 23.

```markdown edit-old=CONTRIBUTING.md
    found. `tests/capabilities/colima.sh` is the reference round trip.
```

```markdown edit-new=CONTRIBUTING.md
    found. `tests/capabilities/colima.sh` is the reference round trip.
20. `configure` is re-run by `teeup update` on every machine, so it must be
    quiet and cheap when nothing has changed: report "Already ..." instead of
    rewriting, and never restart an application or print a multi-line manual
    step unconditionally. `defaults_write` now leaves a key that already
    holds the value alone and records the domains it did write, so a
    `configure` restarts an app with
    `if defaults_changed com.apple.dock; then run_cmd killall Dock || true; fi`.
    A one-time notice uses `state_done ensure <name>`, which succeeds only the
    first time.
21. `teeup reset <cap>` and a migration's `migration_refresh <cap>` both
    re-run your `configure` with `TEEUP_RESET` or `TEEUP_REFRESH` set to the
    capability's name, which turns each `copy_config_once` in it into
    `refresh_config` or `refresh_if_pristine`. Install every user-facing file
    through `copy_config_once` (rendering into a temporary file first when the
    content depends on the machine) and both verbs work for free; a `cp` of
    your own is invisible to them. A capability with no `config/` or `home/`
    directory is not resettable, and says so.
22. `teeup remove <cap>` uninstalls the `casks` and `packages` your metadata
    names and clears the done marker. Add a `remove` script only for machine
    state teeup created that a package manager cannot undo: a LaunchAgent
    (`launchagent_remove <label>`), recorded `defaults` (`defaults_restore`),
    a `hidutil` mapping. It runs before the uninstall, while the tool is
    still there, and never deletes the user's configuration files.
23. A file teeup owns but the user may edit carries a stock record
    (`stock_record`, written by `copy_config_once`). `config_is_pristine
    <file>` asks whether it still matches; `write_config_region <file>
    <label>` rewrites a managed region and keeps a pristine file reading as
    pristine (and refuses a symlink); `refresh_if_pristine <src> <dest>` is
    the stock-checksum rule a migration uses; `backup_copy <file>` takes a
    copy and leaves the original in place for a minimal patch. Hook events
    for the user's own scripts are `post-bootstrap`, `post-update` and
    `theme-set` (`TEEUP_HOOK_EVENTS` in `lib/hooks.sh`); adding one means a
    new `.sample` under `capabilities/teeup-runtime/default/hooks/` and a
    `hook_run <event> [args]` call where it fires.
```

- [ ] **Step 3: Check the names the docs use against the code**

Run:

```bash
for name in cmd_update cmd_reset cmd_remove cmd_dev hook_run TEEUP_HOOK_EVENTS migration_refresh migration_new config_is_pristine write_config_region refresh_if_pristine backup_copy defaults_changed pkg_upgrade cask_upgrade pkg_uninstall cask_uninstall mise_upgrade cap_run_hooks; do
  grep -rqF -- "$name" bin lib || echo "missing in code: $name"
done
./bin/teeup help
```

Expected: no `missing in code:` line, and `teeup help` lists `update`, `reset`, `remove` and `dev add-migration`.

- [ ] **Step 4: Full checks and commit**

```bash
./tests/run.sh
./bin/teeup commands --check
git diff --check
git add README.md CONTRIBUTING.md
git commit -m "Document the lifecycle commands and hooks"
```

Expected: the suite count printed before this task, plus 0. `commands --check` and `git diff --check` print nothing.

---

## Verification

Run on a machine with the suite green, after every task is committed.

1. **The suite, the lint and shellcheck.**

```bash
./tests/run.sh
./bin/teeup commands --check
shellcheck --severity=warning bootstrap bin/teeup lib/*.sh \
  $(find capabilities -type f \( -name install -o -name configure \
    -o -name remove -o -name doctor -o -name theme-apply -o -name font-apply \)) \
  capabilities/teeup-runtime/default/hooks/*.sample \
  $(find migrations -type f -name '*.sh' 2>/dev/null) \
  tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh \
  tests/lib/*.sh tests/capabilities/*.sh
```

Expected: `All N suites passed.` with N two higher than before this plan, and nothing from the other two.

2. **A dry-run update changes nothing.** In a throwaway `HOME`:

```bash
# One export per line: `export HOME=x XDG_CONFIG_HOME="$HOME/.config"` expands
# every word before it assigns any of them, so the second would still name
# your real home and these steps would write into it.
export HOME="$(mktemp -d)"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
DRY_RUN=true ./bin/teeup update 2>&1 | head -20
find "$HOME" -type f | head
```

Expected: `[DRY-RUN] Would execute: git -C ... pull --ff-only` and a preview of each later step; `find` prints nothing, because a dry run creates no state.

3. **The hook samples are installed and never run.**

```bash
DRY_RUN=false ./bin/teeup configure teeup-runtime
ls "$XDG_CONFIG_HOME"/teeup/hooks/*/
printf '#!/usr/bin/env bash\necho "hook saw $TEEUP_HOOK_EVENT $1"\n' > "$XDG_CONFIG_HOME/teeup/hooks/theme-set.d/10-say.sh"
DRY_RUN=false ./bin/teeup theme set catppuccin | tail -3
```

Expected: `post-bootstrap.d/example.sample`, `post-update.d/example.sample` and `theme-set.d/example.sample`; the theme switch ends with `hook saw theme-set catppuccin`.

4. **A migration runs once.**

```bash
export TEEUP_MIGRATIONS_DIR="$HOME/migrations"
mkdir -p "$TEEUP_MIGRATIONS_DIR"
printf '#!/usr/bin/env bash\nlog "migration ran"\n' > "$TEEUP_MIGRATIONS_DIR/1780000000.sh"
bash -c 'source lib/all.sh; answers_load; migrations_run_pending'
bash -c 'source lib/all.sh; answers_load; migrations_run_pending'
```

Expected: `migration ran` and `Applied 1 migration(s).` the first time, `No pending migrations.` the second.

5. **Reset renders rather than copies.**

```bash
DRY_RUN=false ./bin/teeup configure zsh >/dev/null
# configure, not install: install runs chsh. reset needs the done marker, so
# write it by hand rather than changing this machine's login shell.
mkdir -p "$XDG_STATE_HOME/teeup/done" && : > "$XDG_STATE_HOME/teeup/done/cap-zsh"
grep -c 'XDG_CONFIG_HOME:-$HOME/.config}/teeup/env' "$HOME/.zshrc"
printf 'alias x=y\n' >> "$HOME/.zshrc"
DRY_RUN=false ./bin/teeup reset zsh | grep -E 'Reset|Already at'
grep -c 'alias x=y' "$HOME/.zshrc"
```

Expected: the first `grep -c` prints `0` (the token was rendered to an absolute path at configure time), the reset names `$HOME/.zshrc` and reports the two other home files as already at the shipped version, and the last `grep -c` prints `0`.

6. **`teeup help` lists the four new verbs.**

```bash
./bin/teeup help | grep -E 'update|reset|remove|dev add-migration'
```

Expected: four lines.

7. **bash 3.2.** With a bash 3.2.0 build first on `PATH`, `./tests/run.sh` prints the same `All N suites passed.`

---

## Self-review

### Spec coverage

| Spec text | Task |
|---|---|
| S9 `git -C $TEEUP_PATH pull --ff-only` "(refuses on a dirty tree, tells the user)" | 6 (`_update_checkout`) |
| S9 "run pending `migrations/<epoch>.sh` (marker per applied file under `state/migrations`)" | 4, called from 6 |
| S9 "`brew update && brew upgrade && brew upgrade --cask`, or `port selfupdate && port upgrade outdated`" | 6 (`pkg_update`, `pkg_upgrade_all`) |
| S9 "`mise upgrade` (AI CLIs, runtimes, CLI tools from mise)" | 6 (`mise_upgrade`, `mise -C / upgrade`) |
| S9 "re-run configure for `core.list` (idempotent; picks up new shims and templates)" | 6 |
| S9 "`theme set $(theme current)` (regenerate templates)" | 6, with Decision 7's single-render guard |
| S9 "hook post-update" | 2 (the runner), 6 (the call) |
| S9 "`teeup update <cap>` — only that capability's packages and configure" | 6 |
| S9 "Migrations follow Omarchy's stock-checksum rule ... otherwise patch minimally and back up" | 3 (`refresh_if_pristine`, `backup_copy`), 4 (`migration_refresh`) |
| S9 "`teeup dev add-migration` names the file from the last commit timestamp" | 4 (`migration_new`) |
| S7 "Reset. `teeup reset <cap>` backs up the user copy, replaces it with the shipped file, prints the diff, and deletes the backup if nothing changed" | 5 |
| S7 "Hooks. `~/.config/teeup/hooks/<event>.d/` with `.sample` files; events `post-bootstrap`, `post-update`, `theme-set`" | 2 |
| S7 "macOS defaults are applied by `configure` through `defaults_write`" (and the re-run cost of that) | 8 |
| CLI surface `teeup remove <cap>`; "falling back to generic implementations for `update` and `remove` from metadata" | 6, 7 |
| S4 capability contract: `update # optional; default is pkg upgrade of the packages declared in metadata` | 6 (`cmd_update` runs `capabilities/<cap>/update` when there is one) |
| Verification: "Idempotency: run `./bootstrap` twice under the harness and assert the second run performs no mutations" | 8 (Step 9) |
| S5 step 7 / S11: a fresh bootstrap marks every migration | 4 (`migrations_mark_all`) |

Not in this plan, by the controller's split: `doctor`, `menu`, `config` and the other `dev` subcommands (4b); the remaining lazy capabilities (4c); more themes (4d); `teeup migrate legacy` and the legacy doctor checks (5a); the agent skill and the parity checklist (5b).

### Deferred items taken here

From `docs/superpowers/reviews/2026-09-11-redesign-phase1-final-review.md`, `...-phase2a-final-review.md`, `...-phase2a-final-rereview.md`, `.superpowers/plan3/pr11-deferred.md` and the phase 3 plans' "Deliberately deferred" sections:

| Item | Where it came from | Task |
|---|---|---|
| Finder and Dock restart on every `configure macos-defaults` | pr11 | 8 |
| The AeroSpace manual-step text prints on every run | pr11 | 8 |
| Hooks run for capabilities that were never installed | pr11 | 1 |
| `starship.toml` reads as user-edited after a theme switch | pr11 | 3 |
| A symlinked `starship.toml` is replaced by a file | pr11 | 3 (`write_config_region` refuses a symlink) |
| `mise settings set` rewrites the copied file so the stock sha reads as user-edited (phase 2a #6) | 2a triage | 3 partially: `config_is_pristine` and `write_config_region` are the primitive that fixes this class, and the starship case is converted here. `capabilities/mise/configure` keeps its own `mise settings set` calls, which 4b's `doctor` work is the right place to route through `write_config_region`. |
| `teeup remove` and `teeup reset` for the editors (3a) | 3a deferred | 5, 7 — both verbs are generic, so plan 3a's `emacs/remove` and every capability's `config/` are covered without editor-specific code |
| `teeup update` running `mise upgrade` (3b) | 3b deferred | 6 |

### Deferred items deliberately left

| Item | Reason |
|---|---|
| `alt` bindings in AeroSpace take the Meta key zsh and Emacs use (pr11) | A keybinding design decision, not lifecycle. It belongs with whoever next edits `aerospace.toml`. |
| `keyboard` replaces all `hidutil` mappings, not only its own (pr11) | A correctness bug in one capability's `configure`/`remove`, with its own test surface; `teeup remove keyboard` here only runs the script that already exists. |
| A WezTerm started from the Dock with a non-default config dir (pr11) | WezTerm's launch environment, not a lifecycle verb. |
| `;` or `?` in a checkout path breaks Lua's search path (pr11) | Path-quoting in `capabilities/wezterm` and 3a's `neovim` Lua layer. |
| `gpg.ssh.allowedSignersFile` unset (2a #5) | Spec-acknowledged as phase 4 `doctor` work, which is 4b. |
| `typeset -U fpath path` in the zsh layer (2a #4) | The zsh layer is not touched here; taking it would be an unrelated edit in a task nobody would review it in. |
| The wizard asks a question the machine file pins (2a re-review) | `bootstrap`'s wizard. 4d rewrites the theme question's option list and is the cheap place to add the `machine_get` guard. |
| `mock_command` splices `$output` unescaped; `_teeup_log_line` runs `mkdir -p` per line; `__` collision in `_stock_record_path`; `teeup list --tier` with no value (phase 1 items 5, 6, 8, 18) | Test-only or cosmetic, and none of them is in code this plan touches. `_stock_record_path` is read by Task 3, but changing the record path would orphan every record on an existing machine, which is a migration in its own right. |
| Appearance changes do not re-run the hooks (3a) | An appearance-watching LaunchAgent is a new background service; it needs its own capability and doctor check, and `hook_run theme-set` gives a user one line of shell to do it with in the meantime. |
| A themed tmux configuration and a `tmux` `theme-apply` (3b) | A themed template belongs with 4d's theme work, which is where every other template lives. |
| mise's `upgrade.auto_prune` (3b) | `mise_upgrade` calls plain `mise upgrade`; turning a user's mise setting off is a decision about their tool, not teeup's. Named as a Real-Mac risk in Task 6. |
| A `doctor` check that the shims directory is last on `PATH` (3b) | 4b owns `doctor`. |

### Placeholder scan

Searched for `TBD`, `TODO`, `FIXME`, `implement later`, `similar to Task`, `appropriate error handling`, `add validation`, `handle edge cases` and a bare `...` standing in for content: no hits. Every new file appears in full in a `file=` block (`lib/hooks.sh`, `lib/migrations.sh`, `tests/lib/hooks.sh`, `tests/lib/migrations.sh`, `migrations/README.md`, the three `.sample` files); every change to an existing file is an `edit-old`/`edit-new` pair. The `...` characters that remain are prose inside error messages (`Remove those first, then $target.`) or an ellipsis in a quoted spec line.

### Name and type consistency

- `lib/hooks.sh` (Task 2): `TEEUP_HOOK_EVENTS`, `hooks_dir`, `hook_run`. `bootstrap` calls `hook_run post-bootstrap`; `theme_set` calls `hook_run theme-set "$name"`; `cmd_update` calls `hook_run post-update` with and without an argument; `capabilities/teeup-runtime/configure` loops over `$TEEUP_HOOK_EVENTS`. The singular `hook_run` is used everywhere; there is no `hooks_run`.
- `lib/capability.sh` (Task 1): `cap_hook_eligible`, `cap_run_hooks`. Callers: `theme_set`, `font_set`, `cmd_reset`. `cap_run_optional` keeps its signature and its three tests.
- `lib/files.sh` (Task 3): `config_is_pristine`, `write_config_region`, `refresh_if_pristine`, `backup_copy`. Callers: `capabilities/theme/theme-apply` (`write_config_region`), `copy_config_once` (`refresh_if_pristine`, `refresh_config`), Task 4's `migration_refresh` (indirectly). The existing `backup_target` (which moves) and the new `backup_copy` (which copies) are distinct and both are used.
- `lib/migrations.sh` (Task 4): `TEEUP_MIGRATIONS_DIR`, `migrations_list`, `migrations_pending`, `migrations_mark_all`, `migration_run`, `migrations_run_pending`, `migration_refresh`, `migration_new`. Plural for the set, singular for one; `bootstrap` calls `migrations_mark_all`, `cmd_update` calls `migrations_run_pending`, `cmd_dev` calls `migration_new`.
- `lib/pkg.sh` (Tasks 6, 7): `pkg_update`, `pkg_upgrade_all`, `pkg_upgrade`, `cask_upgrade`, `pkg_uninstall`, `cask_uninstall`, matching the existing `pkg_install`/`cask_install` pair's naming and their `<pkg>`/`<cask>` argument shapes.
- `lib/mise.sh` (Task 6): `mise_upgrade`, next to 3b's `mise_ensure_global`, `mise_wrapper_write`, `dev_env_install`, `dev_env_installed`, and following its `mise -C /` rule.
- `lib/macos.sh` (Task 8): `TEEUP_DEFAULTS_CHANGED`, `_defaults_same`, `defaults_changed`, next to `defaults_write` and `defaults_restore`.
- Environment variables: `TEEUP_HOOK_EVENT` (set for a hook), `TEEUP_MIGRATION` (set for a migration), `TEEUP_REFRESH` and `TEEUP_RESET` (scoped against `TEEUP_CAP`), `TEEUP_CONFIGURING` (plan 3a's, honoured by `cap_hook_eligible`), `TEEUP_MIGRATIONS_DIR`, `TEEUP_DEFAULTS_CHANGED`. None of them shares a name with anything in phases 1 to 3.
- User-visible strings asserted in one task and produced in another agree: `Already set: <domain> <key>` (Task 8 `defaults_write`, Task 8 tests), `Keeping your edited <file>; it was not refreshed.` (Task 3, Task 4 test), `Refreshed <file> (you had not edited it)` (Task 3, Task 4 test), `Not installed here, so nothing to upgrade: <name>` and `... to uninstall: <name>` (Tasks 6 and 7), `<cap> is not installed. Install it with: teeup install <cap>` (Tasks 5 and 6), `Reset <cap>.` / `Removed <cap>.` / `Updated <cap>.` / `teeup is up to date.` (Tasks 5, 7, 6).

### External facts and their sources (checked 2026-09-16)

| Fact the plan relies on | Source |
|---|---|
| `mise upgrade` with no arguments upgrades every current tool; `-C, --cd <DIR>` changes directory before running | `mise upgrade --help` and `mise --help` on the installed mise 2026.9.4 |
| `git -C <dir> status --porcelain` prints nothing for a clean tree; `git pull --ff-only` refuses a non-fast-forward; `git log -1 --format=%ct` prints the commit's Unix timestamp | `git(1)`, `git-status(1)`, `git-pull(1)`, `git-log(1)` (`%ct` = "committer date, UNIX timestamp") |
| Homebrew: `brew update`, `brew upgrade` (formulae), `brew upgrade --cask` (casks), `brew uninstall <formula>`, `brew uninstall --cask <token>` | `brew help update`/`upgrade`/`uninstall` and docs.brew.sh's manpage: "`upgrade` ... if `--cask` is passed, only casks" |
| MacPorts: `sudo port selfupdate`, `sudo port upgrade outdated`, `sudo port uninstall <port>`; the guide documents no exit status for an empty upgrade list | The MacPorts Guide, sections 2.5 (Upgrading) and 3.2 (`port` commands) |
| `defaults read <domain> <key>` exits 1 for a key that is absent and prints a boolean as `1`/`0`; `defaults read-type` prints `Type is <type>`; `defaults write -bool` accepts `TRUE`/`FALSE`/`YES`/`NO` | `defaults(1)` on macOS, and the mock in `tests/lib/macos.sh` written from it in phase 2b |
| Omarchy's shape for the three pieces this plan copies: a hook directory per event whose failures never abort, migrations named from a timestamp and marked once applied, and `refresh-config`'s backup-replace-diff | `basecamp/omarchy`: `bin/omarchy-hook`, `bin/omarchy-migrate`, `bin/omarchy-dev-add-migration`, `bin/omarchy-refresh-config` |

### Mechanical verification of this text

Every code block in this plan was applied to a scratch clone and run; nothing below is a claim about code that was never executed.

- **The base.** A clone of `main` at `0adfb22` with plan 3a's seven tasks and then plan 3b's eleven applied by the same harness, one commit per task, each checked the way those plans specify. The base printed `All 46 suites passed.`, `./bin/teeup commands --check` was silent, and `git diff --check` was clean, matching both plans' own Verification sections. The whole run below was then repeated on the controller's own prepared base tree (byte-identical apart from `tests/capabilities/ai.sh`, which it carries one revision newer), with `TEEUP_NO_GUM` unset in the environment, and every number came out the same.
- **Transcription.** A script read this document, applied each task's `file=` blocks and `edit-old`/`edit-new` pairs in order (failing on any `edit-old` that did not occur exactly once), ran the `chmod` lines, ran every step's `Run:` command at the point it appears and compared its `Summary:` lines with that step's `Expected:` text, then ran `./tests/run.sh`, `./bin/teeup commands --check`, `shellcheck --severity=warning` on the task's new and edited scripts, `git diff --check`, and committed with the task's `git add` line. Every `edit-old` matched exactly once; after every commit the working tree was clean.
- **Results.** The base printed `All 46 suites passed.`; after Tasks 1 to 9 it printed `46`, `47`, `47`, `48`, `48`, `48`, `48`, `48` and `48`, matching each task's "plus K" (Tasks 2 and 4 add `tests/lib/hooks.sh` and `tests/lib/migrations.sh`; the other seven add none). `commands --check` printed nothing and exited 0 after every task, each task's own shellcheck line was silent, and `git diff --check` was clean after every task.
- **Failing first.** Every "see it fail" step printed exactly the `Summary:` its `Expected:` line names: `17/19`, `0/7`, `12/19`, `19/21`, `0/9`, `29/32`, `15/20`, `16/17`, `32/41`, `20/21`, `41/45`, `16/18`, `9/11`, `10/11`. Every "passes" step printed the full count: `19/19`, `23/23`, `9/9`, `11/11`, `7/7`, `10/10`, `25/25`, `19/19`, `21/21`, `9/9`, `20/20`, `29/29`, `26/26`, `32/32`, `24/24`, `6/6`, `20/20`, `17/17`, `41/41`, `21/21`, `45/45`, `18/18`, `11/11`, `11/11`, `27/27`.
- **Whole-tree checks on the final state.** The CI shellcheck command (every `install`, `configure`, `remove`, `doctor`, `theme-apply`, `font-apply`, the libraries, the three `.sample` files, `migrations/*.sh` and every test) is clean. Task 9's name check prints no `missing in code:` line and `./bin/teeup help` lists the four new verbs.
- **The Verification block above, run as written.** The dry-run update previewed the pull, the package manager and `mise -C / upgrade`, named every core capability that is not installed, and `find` showed it had written nothing. `teeup configure teeup-runtime` installed the three `example.sample` files and `teeup theme set catppuccin` ended in `hook saw theme-set catppuccin`. A migration ran once and then reported `No pending migrations.` `teeup configure zsh` left no `${XDG_CONFIG_HOME:-...}` token in `~/.zshrc`, and `teeup reset zsh` reset that file, reported the other three as already at the shipped version, and dropped the user's added line.
- **bash 3.2.0.** The final tree's full suite, on both runs, with a bash 3.2.0 build first on `PATH` (so `tests/run.sh`, every suite and every library ran under 3.2), printed `All 48 suites passed.` That run also had `TEEUP_NO_GUM` unset, on a host that has `/usr/bin/gum`, so it doubles as the check that nothing this plan adds is fooled by a real `gum`.
- **Host independence.** The runs were on Linux with mocked `brew`, `port`, `mise`, `git`, `defaults`, `killall`, `chsh` and `open`. `lib/ui.sh` prefers `gum` whenever `TEEUP_NO_GUM` is empty and `gum` is on `PATH`, and this host has `/usr/bin/gum`, which the harness's narrowed `PATH` does not hide; `tests/cli.sh` already exports `TEEUP_NO_GUM=1` in its `setup`, and Task 5's two capability tests export it as well.

What this does not prove: anything on macOS. No `brew update`, `brew upgrade --cask`, `port selfupdate`, `port upgrade outdated`, `brew uninstall --cask`, `mise upgrade`, `defaults read-type`, `killall Finder` or `git pull --ff-only` in this plan has run against the real tool; the `defaults` comparison in Task 8 and the package-manager verbs in Tasks 6 and 7 are the two places where a mock that is kinder than the real command would hide a defect.
