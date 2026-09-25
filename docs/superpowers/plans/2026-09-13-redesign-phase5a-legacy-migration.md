# Phase 5a: legacy migration — `teeup migrate legacy`, the leftover checks, and the last of the chezmoi content

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a Mac that already ran the old `teeup.sh`, or that is still handed its dotfiles by the chezmoi repo, become a plain teeup machine with one command — `teeup migrate legacy` — without ever deleting the chezmoi source directory that keeps serving Linux.

**Architecture:** One new library, `lib/migrate.sh`, behind one new verb. Everything it deletes is named by a **key**, not by a path: `migrate_target` is a `case` statement mapping a fixed set of keys to absolute paths, and `migrate_rm` accepts only a key, so there is no argument any caller can pass that names `~/Work/environment/dotfiles`. Two further gates run on the resolved path anyway (strictly inside `$HOME`, and clear of whatever `chezmoi source-path` reports), and every chezmoi call in teeup goes through `chezmoi_ro`, which refuses any subcommand that is not read-only — `purge` among them. The leftovers spec section 10 asks `teeup doctor` to flag are added to the `zsh` and `git` doctor scripts phase 4b creates, since that is how checks register — **which makes Task 7 conditional on PR #32 merging**; see Revision 2.

**Tech Stack:** bash 3.2 (macOS stock), BSD `awk`/`sed`/`date`, chezmoi's read-only subcommands, the phase 1 mock-binary test harness, phase 4a's `backup_copy`/`refresh_if_pristine`/migration runner, phase 4b's doctor contract and `share/teeup/menu.json`.

**Spec:** `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md` — section 10 ("Migrating existing machines") in full, plus section 4 (the capability directory and its `doctor` script), section 7 (the configuration model), section 9 (migrations and the stock-checksum rule) and section 12.

---

## Revision 2 — 2026-09-24

A preflight ran this plan against the tree it will actually execute on and found
5 Blocking and 11 Important defects (`.superpowers/sdd/2026-09-13-redesign-phase5a-legacy-migration/preflight.md`,
rulings in `rulings-by-task.md` beside it). This revision folds every ruling into the
plan text so there is one document to follow. **Where a task's body still disagrees
with a rule below, the rule wins.**

What changed, and why:

1. **The ground truth moved.** Phases 3a, 3b and 4a are merged; `main` is their
   contract now, not their plan text. Phase 4b's doctor half is open as **PR #32**
   and is not merged. The dependency table below is corrected.
2. **Task 7 is gated on 4b landing** (A1/T7.1). The doctor framework, both `doctor`
   scripts and both test anchors do not exist on `main`. Until #32 merges, skip Task 7,
   skip Task 6 Step 4 and the `dev check` half of Step 5, and name no `teeup doctor`
   in the closing message, README or CONTRIBUTING.
3. **A destructive command may not claim what it did not do** (A2). Every success line
   in `lib/migrate.sh` uses `ok_unless_dry`, never `ok`, and every `run_cmd` /
   `backup_target` / `backup_copy` / `disable_matching_lines` call has its status checked
   before anything is claimed.
4. **`T1.1` is fixed upstream.** `backup_copy` now checks its `cp`, warns and returns 1
   (`lib/files.sh`, merged in #30). The remaining obligation is on the *caller*: check
   its status and abort the rewrite when it returns non-zero.
5. **Two new safety gates** (T2.1): refuse when `have chezmoi` is true but
   `migrate_chezmoi_source` prints nothing, and refuse any resolved path with a `.git`
   entry between it and `$HOME`.
6. **`migrate_chezmoi` asks before the bulk move** (T5.1), splitting the managed list
   into what teeup will reinstall and what it will not.
7. **`ZDOTDIR` is honoured** in the rc-file list (T3.1, T4.1).
8. **Stale anchors and counts are corrected** (A4, T2.2, T8.2, T9.1). Measured on
   `main` at `5186afe`: **49 suites**, `tests/lib/files.sh` **42 tests**,
   `CONTRIBUTING.md`'s numbered list ends at **24**, `lib/all.sh:9` reads
   `for _teeup_lib in files state answers pkg ui capability macos theme font lazy mise hooks migrations; do`,
   and `README.md` has no `teeup config` verb to anchor against.
9. **The `chezmoi_ro` rule becomes enforceable** (A5): a test greps the tree for a
   `chezmoi` invocation outside the wrapper.

### Binding rules, all tasks

**R1 — `ok_unless_dry`, and only after a checked mutation.** `migrate_rm` says
"Removed …" only after a real `rm` returned 0; `migrate_chezmoi` counts a move only on a
real move (`backup_target` returns the prospective path and 0 under `DRY_RUN`). A
`DRY_RUN=true teeup migrate legacy` that reports deletions which never happened is
worthless exactly where the user is told to rely on it.

**R2 — compare against the physical path in tests.** `migrate_rm` and `migrate_backup`
act on the resolved path, and on macOS `$TEST_HOME` (`/var/folders/…`) resolves to
`/private/var/folders/…`. Whenever an assertion compares a string that came out of
teeup's own output, compare against `home="$(cd "$TEST_HOME" && pwd -P)"`, not
`$TEST_HOME`. Getting this wrong goes red on macOS CI while passing locally — a failure
mode this project has already been bitten by.

**R3 — re-derive every count.** Print the count before each task and write "that count
plus K". Never paste a number from this plan into an expectation.

**R4 — no `teeup doctor` until #32 merges.** See item 2 above.

### Gate on running this against the user's work Mac

**`teeup migrate legacy` does not run on the work Mac until A2, T1.1, T2.1 and T5.1 are
done.** Until then the preview lies, the backups are unverified, the sibling-repo gate has
a state-dependent hole, and the bulk move is unprompted. That Mac is chezmoi-managed, which
is the exact configuration every one of those four defects is about.

**First real run, in order:**

1. `DRY_RUN=true teeup migrate legacy`, and read every line.
2. `chezmoi managed --path-style=absolute --include=files,symlinks` by hand; confirm the
   list matches what the preview said.
3. `cp -a ~/Work/environment/dotfiles <scratch>` to a location off the machine's normal
   paths. That repo still serves Linux and is never to be deleted; the copy is in case a
   gate fails in a way nobody predicted.
4. The real run. **Answer `no`** to the `~/.config/chezmoi` question the first time.
5. Open a new terminal before doing anything else, and confirm the shell comes up.

**Sequencing.** Land 5a without Task 7 and without the menu row, or merge PR #32 first.
Do not half-implement a doctor framework inside 5a.

---

## Depends on

Phases 1, 2a, 2b, 3a, 3b and 4a are **merged**; for all of them `main` (at `5186afe`) is
the ground truth, not their plan text. Phase 4b's doctor half is open as **PR #32** and is
**not merged**; 4b's remaining tasks (menu, `teeup config`, dev verbs, docs), 4c and 4d are
neither written nor merged.

Execution order is unchanged on paper — 3a, 3b, 4a, 4b, 4c, 4d, 5a, 5b — but 5a is being
pulled forward because it is on the critical path for the first real run on the user's
work Mac (which is chezmoi-managed). That is allowed for every task **except Task 7**,
which cannot be written against a tree without `lib/doctor.sh`; see Revision 2, item 2.

| Interface | Kind | Defined by |
|---|---|---|
| `log ok warn err die have run_cmd run_logged user_config_dir is_macos` | functions, `lib/core.sh` | main |
| `DRY_RUN TEEUP_CONFIG_DIR TEEUP_STATE_DIR` | variables, `lib/core.sh` | main |
| `backup_target copy_config_once write_managed_file append_once file_sha stock_record stock_sha replace_literal` | functions, `lib/files.sh` | main |
| `state_done check\|mark\|clear <name>` | function, `lib/state.sh` | main |
| `answers_load answers_get answers_set machine_get machine_file` | functions, `lib/answers.sh` | main |
| `cap_dir cap_exists cap_list cap_meta_get cap_skipped cap_run cap_check` | functions, `lib/capability.sh` | main |
| `ui_confirm ui_input _ui_gum` | functions, `lib/ui.sh` | main |
| `setup_test_env cleanup_test_env mock_command mock_command_script mock_macos_base` and the assertions | test harness, `tests/helper.sh` | main |
| `capabilities/zsh/default/{env,aliases,functions}` | the shipped zsh default layer | main (phase 2a) |
| `capabilities/git/config/git/config` | the copy-once gitconfig | main (phase 2a) |
| `hide_host_commands <name...>` | test helper, `tests/helper.sh` | phase 3b, Task 1 |
| `shims_dir` | function, `lib/lazy.sh` | phase 3b, Task 1 |
| `backup_copy <path>` — copies, prints the backup path, **returns 1 without printing `Copied` when the `cp` fails** | function, `lib/files.sh` | main (#30) |
| `refresh_if_pristine <src> <dest>`, `config_is_pristine <dest>` | functions, `lib/files.sh` | phase 4a, Task 3 |
| `migration_refresh <capability>`, `migration_run <name>`, `migrations_list`, `TEEUP_MIGRATIONS_DIR` (`$TEEUP_PATH/migrations`) | functions, `lib/migrations.sh` | phase 4a, Task 4 |
| `state_migration_mark`/`state_migration_done` write and read `$TEEUP_STATE_DIR/migrations/<name>` | functions, `lib/state.sh` | phase 4a, Task 4 |
| `copy_config_once` turns into `refresh_if_pristine` when `TEEUP_REFRESH` names the running capability | changed behaviour, `lib/files.sh` | phase 4a, Task 3 |
| `migrations/` exists and holds only `README.md` plus `<unix-epoch>.sh` files | directory | phase 4a, Task 4 |
| `teeup update`, `teeup reset`, `teeup remove`, `teeup dev add-migration` | verbs, `bin/teeup` | phase 4a, Tasks 4–7 |
| `doctor_ok`, `doctor_warn`, `doctor_fail`, `doctor_unknown`, `doctor_summary` | functions, `lib/doctor.sh` | phase 4b — **PR #32, not merged**. Note `doctor_unknown`/`doctor_summary`, not the `doctor_verdict` this plan was written against. |
| `capabilities/zsh/doctor`, `capabilities/git/doctor` | doctor scripts Task 7 extends | phase 4b — **PR #32, not merged** |
| `share/teeup/menu.json` and its flat dotted-id format | menu file | phase 4b **task 6, not written**. Task 6 Step 4 is skipped. |
| `teeup dev check` (lints metadata, the menu and shellcheck) | verb, `bin/teeup` | phase 4b **task 9, not written**. Use `./bin/teeup commands --check` instead. |
| `lib/all.sh` sources `files state answers pkg ui capability macos theme font lazy mise hooks migrations` (`lib/all.sh:9`, measured) | library list | main |
| `teeup doctor` | verb, `bin/teeup` | phase 4b — **PR #32, not merged**. `teeup menu` and `teeup config` are not written at all; name neither. |

### One seam that used to need reconciling, now fixed upstream

Building this plan's transcription base (4a, then 4b, then 4c, then 4d on top of 3a and 3b) turned up one conflict between the plans it consumes: phase 4a Task 4 creates `cmd_dev` in `bin/teeup`, and phase 4b Task 8 gave a whole second `cmd_dev` for the case where 4a had not landed, which a mechanical apply took, leaving two definitions and breaking `teeup dev new-capability`. **That is fixed in 4b's text** (cross-plan pass of 2026-09-16): Task 8 Step 4 and Task 9 Step 4 are now plain `edit-old`/`edit-new` pairs that add one case arm each to the function 4a created, so nothing here has to be reconciled by hand. Nothing in this plan touches `cmd_dev`; it is named here only so a reader of the old note knows why it is gone.

### What 5a owns, and what it does not

- **5a owns `teeup migrate`.** 5b owns deleting `legacy/` and its CI steps. This plan reads `legacy/teeup.sh` and ports one function out of it; it does not delete anything under `legacy/`.
- **5a adds no capability.** `capabilities/core.list` and `capabilities/daily.list` are untouched.
- **The doctor framework is 4b's.** This plan adds checks the only way 4b's contract allows: as lines inside a capability's own `doctor` script, reporting through `doctor_fail`/`doctor_warn`.
- **`wezterm.lua` is not ported here.** Spec section 10 lists it among the chezmoi content worth porting, but phase 2b already ships the `wezterm` capability with its own themed template and the `~/.wezterm_local.lua` seam. The phase 4/5 brief's 5a bullet lists only "shell envs/aliases/functions, gitconfig aliases, `javav`", which is what Task 8 covers.

---

## Global Constraints

Every task's requirements implicitly include this section.

- **bash 3.2 compatible.** No `mapfile`, `readarray`, `declare -A`, `${var,,}`, `readlink -f`, `**`, `&>>`, `wait -n`. Use `10#$n` for arithmetic on a string that may have a leading zero. No same-line `local` back-reference (`local a=1 b=$a` leaves `b` empty). bash 3.2 mis-parses a quoted pattern containing `/` inside `${var//pat/repl}`: use `replace_literal` (`lib/files.sh`). Run `shopt -u patsub_replacement 2>/dev/null || true` before any `${var//}` whose replacement text can contain `&`.
- **BSD tools only.** No GNU-only flags, no `\t` or `\n` in `sed` replacements, no `grep -P`, no `readlink -f`. Pass an awk value through `ENVIRON` rather than `-v` whenever it can contain a backslash — every pattern in this plan can, which is the defect Task 1 fixes.
- **Capability scripts** (`install`, `configure`, `doctor`, …) start `#!/usr/bin/env bash`, are run by `cap_run` as `bash -eu` with `lib/all.sh` sourced and `answers_load` done, and must not use `local`. Mind `set -e` on a trailing `[[ ]] && cmd`. Mocked commands are called by bare name. Every mutation goes through `run_cmd`/`run_privileged` or a `DRY_RUN`-guarded primitive; `DRY_RUN=true` must change nothing. In `bin/teeup` and `lib/*.sh`, which also run under `set -eu`, use `if … then … fi` rather than a bare `[[ ]] && cmd` statement.
- **Paths.** `user_config_dir` for `~/.config`; `TEEUP_CONFIG_DIR` and `TEEUP_STATE_DIR` are honoured everywhere. Paths containing spaces and shell metacharacters must work, and every new suite includes at least one such path.
- **Machine file precedence.** `answers` then `machines/<hostname>.conf`; the machine file wins.
- **Capability metadata contract:** `summary group tier requires provides packages casks apps interactive`. `provides` never names a command macOS ships. A `core` or `daily` capability must appear in its tier list or `teeup commands --check` fails.
- **Tests never touch the real machine.** Every test runs under `tests/helper.sh`: a temp `$HOME`, `MOCK_BIN` first on the narrowed PATH `$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin`, `mock_command`, `mock_command_script`, `mock_macos_base`, `hide_host_commands`, `TEEUP_TEST_MISSING`, `TEEUP_PKG_PREFIX`, `TEEUP_APPS_DIR`. **No test in this plan may name a path outside `$TEST_HOME`**, and no test may run a real `chezmoi` or a real `git` against `~/Work/environment/dotfiles`: both are mocked, and the stand-in for the sibling repo is a directory the test creates under `$TEST_HOME`. A test that can only pass on a developer's machine is a defect.
- **Prompts in tests.** `lib/ui.sh` uses gum whenever `TEEUP_NO_GUM` is empty and `gum` is on PATH, and the harness's narrowed PATH still exposes a host `/usr/bin/gum`. **Every test that drives a prompt must `export TEEUP_NO_GUM=1`**, exactly as `tests/bootstrap.sh` and `tests/capabilities/secrets.sh` do.
- **Destructive paths need refusal tests.** Every function in `lib/migrate.sh` that can delete something carries at least one test proving it refuses: the chezmoi source directory, a path outside `$HOME`, and a key it was never given.
- **Suite counts (R3).** `tests/run.sh` ends with `All N suites passed.` Never hard-code N:
  print the count before the task and write "that count plus K". Measured on `main` at
  `5186afe`: **49 suites**, and `tests/lib/files.sh` reports **42 tests**. Every count
  written into this plan before Revision 2 is stale; treat one as a defect, not an
  expectation.
- **Physical paths in assertions (R2).** On macOS `$TEST_HOME` under `/var/folders/…`
  resolves to `/private/var/folders/…`, and `migrate_rm`/`migrate_backup` report the
  resolved path. Any assertion comparing a string teeup printed must compare against
  `home="$(cd "$TEST_HOME" && pwd -P)"`.
- **Nothing has run on a real Mac.** Each task carries a **Real-Mac risk** note naming what only hardware proves.
- **Verify, do not guess** every external CLI flag, config key, package name and file location against the installed tool's `--help` or current upstream documentation.
- **Every task ends** with: `./tests/run.sh` green, `./bin/teeup commands --check` silent and exit 0, `shellcheck --severity=warning` clean on every new or edited shell script and test, `git diff --check` clean, and ONE commit with a plain imperative subject and NO trailers (no `Co-Authored-By`, no `Claude-Session`, no "Generated with").

---

## Contracts

### What `teeup migrate legacy` may delete, and how that is enforced

Three independent gates, in this order:

1. **A closed key list.** `migrate_target <key>` is a `case` statement over five keys (`teeup-common`, `teeupshrc`, `shellrc-common`, `mac-setup`, `chezmoi-config`) and prints the absolute path for each. Any other key returns 1 and prints nothing. `migrate_rm` takes a **key**, never a path, and calls `migrate_target` itself. There is therefore no argument, anywhere in teeup, that makes `migrate_rm` name the chezmoi source directory — the protection is the shape of the call, not a check inside it.
2. **The resolved path must be safe.** `migrate_resolve` resolves every symlink *above* the last component (`cd "$(dirname …)" && pwd -P`) and leaves the last component alone, so a dangling or foreign symlink can be removed without being followed. `migrate_path_is_safe` then requires the result to be strictly inside the physical `$HOME` (never `$HOME` itself, never a `..` component) and to be neither the chezmoi source directory, nor anything inside it, nor any directory that contains it. This is the gate that catches `XDG_CONFIG_HOME` pointing somewhere odd, or `~/.config/mac-setup` being a symlink into the sibling repo.
3. **chezmoi is read-only.** `chezmoi_ro <subcommand> [args…]` is the only place in teeup that runs `chezmoi`. It accepts `managed`, `source-path` and `--version`, and `die`s on anything else. `chezmoi purge` "removes chezmoi's configuration, state, and source directory" (chezmoi reference, `purge`), which is exactly the sibling repo, so it cannot be reached.

`migrate_rm` never removes what a symlink points at: a symlink is removed with `rm -f` on the link itself, and only a real directory gets `rm -rf`.

### Reporting

Every success line uses `ok_unless_dry` (`lib/core.sh`), never `ok`, and is printed only
after the mutation it describes returned 0 (R1). A step that could not check something says
so rather than claiming it acted.

Every migration step returns 0 when it did its work or had nothing to do, and 1 when it
**refused** something. `migrate_legacy` collects those, so a refusal never stops the rest of the migration and the verb still exits non-zero to say something was left alone. Nothing in the migration prompts except the one question spec section 10 requires, and that one defaults to **no**.

### `disable_matching_lines <file> <pattern> <reason>`

Ported from `legacy/teeup.sh:479` into `lib/files.sh`, with two defects fixed. It rewrites every matching line of `<file>` as `: # Disabled by teeup (<reason>): <the original line>`. A missing file and a symlink are both no-ops (a symlink belongs to whatever put it there). It copies the file to `<file>.teeup_backup_<ts>` through `backup_copy` before writing, writes through a temp file and `cat`s it back so the inode survives, and is a no-op when nothing matches. `DRY_RUN=true` prints what it would do and changes nothing. Returns 0 always.

`: ` rather than a plain `#` because these lines usually sit inside an `if … ; then` block, and an `if` whose whole body is commented out is a syntax error. A matching line that *opens* a block (ends in `then`, `do` or `in`, or in `{`, `(`, `\`, `&&` or `||`) is left alone and reported instead, since neutralising an opener would orphan its terminator; its body is neutralised, which is what stops the init from running.

The two fixes the port makes: the pattern and the reason reach awk through `ENVIRON`, not `-v` (awk expands escape sequences in a `-v` assignment, so legacy's `'\.pyenv'` reached awk as `.pyenv` and matched `mypyenv` too), and the backup goes through `backup_copy` so it is `DRY_RUN`-aware and logged like every other teeup backup.

### The doctor leftovers

Spec section 10 names four. They register as lines inside the doctor scripts phase 4b wrote:

| Leftover | Script | Verdict |
|---|---|---|
| `[user]` block in `~/.gitconfig.local` | `capabilities/git/doctor` | `doctor_fail` when some git config file teeup knows about includes it, `doctor_warn` when nothing does |
| Powerlevel10k remnants (`~/.p10k.zsh`, `$ZDOTDIR/.p10k.zsh`, a `p10k` line in `.zshrc`) | `capabilities/zsh/doctor` | `doctor_fail`, fixed by `teeup migrate legacy` for the rc line and by deleting the file otherwise |
| `~/.oh-my-zsh` | `capabilities/zsh/doctor` | `doctor_fail` |
| chezmoi source directory still configured | `capabilities/zsh/doctor` | `doctor_fail`, fix `teeup migrate legacy` |

---

## File structure

| File | Responsibility | Task |
|---|---|---|
| `lib/files.sh` | `disable_matching_lines` | 1 |
| `lib/migrate.sh` | keys, resolution, the safety gates, `chezmoi_ro`, and the three migration steps | 2, 3, 4, 5 |
| `lib/all.sh` | sources `migrate.sh` | 2 |
| `bin/teeup` | `cmd_migrate`, usage and dispatch | 6 |
| `share/teeup/menu.json` | the `setup.migrate` row | 6 |
| `capabilities/zsh/doctor` | p10k, Oh My Zsh and the chezmoi source dir | 7 |
| `capabilities/git/doctor` | the `[user]` block in `~/.gitconfig.local` | 7 |
| `capabilities/zsh/default/env` | `~/.cargo/bin`, `GOPATH`, the Emacs package checkout variables | 8 |
| `capabilities/zsh/default/aliases` | `cd..`, the Colima shortcuts | 8 |
| `capabilities/git/config/git/config` | the `lfs` and `llg` aliases and the ediff mergetool | 8 |
| `migrations/<epoch>.sh` | refresh a pristine `~/.config/git/config` onto the new shipped file. **Name it from `./bin/teeup dev add-migration`, never from a number in this plan** (T8.2). | 8 |
| `tests/lib/files.sh` | `disable_matching_lines` | 1 |
| `tests/lib/migrate.sh` | every gate, every step, every refusal | 2, 3, 4, 5 |
| `tests/cli.sh` | `teeup migrate legacy` end to end | 6 |
| `tests/capabilities/zsh.sh`, `tests/capabilities/git.sh` | the leftover checks | 7, 8 |
| `README.md`, `CONTRIBUTING.md` | the verb, the safety rules, the section 10 checklist | 9 |
| `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md` | section 10 marked done | 9 |

`tests/run.sh` needs no edit: it globs `tests/lib/*.sh` and `tests/capabilities/*.sh`.

---

## Tasks

1. `disable_matching_lines` in `lib/files.sh`
2. `lib/migrate.sh`: the closed key list, the safety gates and the read-only chezmoi wrapper
3. `migrate_legacy_paths`: the legacy files, directories, symlinks and rc wiring
4. `migrate_disable_runtime_inits`: SDKMAN, rbenv and pyenv
5. `migrate_chezmoi`: detect, list, back up, and ask only about `~/.config/chezmoi`
6. `teeup migrate legacy`: the verb, the menu row and the end-to-end refusal proofs
7. The doctor leftover checks
8. The remaining chezmoi content, and the migration that refreshes it
9. README, CONTRIBUTING and the spec's section 10

---

### Task 1: `disable_matching_lines` in `lib/files.sh`

> **Rulings folded in (Revision 2).**
> **T1.1 — check the backup before you overwrite.** `backup_copy` now checks its `cp`,
> warns and returns 1 (`lib/files.sh`, merged in #30), so the fix this ruling asked for is
> upstream. The obligation left is on this caller: capture its status, and when it is
> non-zero **warn and return without touching the file**. On a home directory teeup cannot
> write a backup into, the alternative is rewriting the user's `.zshrc` with no copy
> anywhere — the one outcome this phase exists to prevent.
> **T1.2 — refuse a file you cannot write, and claim only the edit you made.** Before
> rewriting, check the target is a regular writable file (the rule `write_managed_file`
> already applies), check that `cat "$tmp" > "$file"` succeeded, and print
> `ok_unless_dry "Disabled …"` only then. Otherwise a read-only rc file gets a success
> message and no change.
> **T1.3 — test `-L` before `-f`**, so a dangling legacy symlink is reported like a live
> one instead of returning silently.

Spec section 10: `teeup migrate legacy` "disables SDKMAN, rbenv, pyenv init lines (reusing `disable_matching_lines`)". The function exists only in `legacy/teeup.sh:479`, which phase 5b deletes, so it is ported first, on its own, with its tests — every later task in this plan calls it.

**Files:**
- Modify: `lib/files.sh` (append after `replace_literal`)
- Modify: `tests/lib/files.sh`

**Interfaces:**
- Consumes: `log ok warn` (`lib/core.sh`), `DRY_RUN` (`lib/core.sh`), `backup_copy` (`lib/files.sh`, phase 4a Task 3).
- Produces: `disable_matching_lines <file> <pattern> <reason>` — neutralises every line of `<file>` that matches the awk ERE `<pattern>`, rewriting it as `: # Disabled by teeup (<reason>): <original line>`. A missing file and a symlink are no-ops. Backs the file up through `backup_copy` before writing. Idempotent, `DRY_RUN`-aware, always returns 0.

**Why `: #` and not `#`.** A shell init line is very often inside an `if`, and an `if …; then` whose whole body is commented out is a **syntax error** — the next `fi` has nothing to close. Prefixing with the no-op builtin `:` keeps the line a command wherever it sits, and carries the original text along as a comment on the same line. The matching line that *opens* a block (`if … ; then`, `… do`, `case … in`, a trailing `{`, `(`, `\`, `&&` or `||`) is left exactly as it is and reported, because neutralising an opener would orphan its terminator; its body is neutralised instead, which is what actually stops the init from running. A bare `[ -s ~/.sdkman/bin/sdkman-init.sh ]` with a dead body does nothing.

**Real-Mac risk:** BSD awk on macOS versus the `onetrueawk`/`gawk` on the Linux CI runner. The features relied on are `ENVIRON[]`, a dynamic regexp built from a string, `print … > var` redirection to a named file, and `[[:space:]]` classes — all POSIX, all present in both, but only a real Mac proves BSD awk treats `\.` in a dynamic regexp as a literal dot. `mktemp` with no template is BSD-compatible and already used by `append_once` and `write_managed_file`.

- [ ] **Step 1: Write the failing tests**

Add these eight tests to `tests/lib/files.sh`, immediately above the `echo "lib/files.sh"` line:

```bash edit-old=tests/lib/files.sh
echo "lib/files.sh"
```
```bash edit-new=tests/lib/files.sh
test_disable_matching_lines_neutralises_only_matching_lines() {
  setup
  local rc="$TEST_HOME/rc"
  printf 'export A=1\neval "$(rbenv init -)"\nexport B=2\n' > "$rc"
  disable_matching_lines "$rc" 'rbenv (init|shell)|RBENV_ROOT' "rbenv replaced by mise" >/dev/null
  assert_equals 'export A=1
: # Disabled by teeup (rbenv replaced by mise): eval "$(rbenv init -)"
export B=2' "$(cat "$rc")" || return 1
  cleanup_test_env
}

test_disable_matching_lines_keeps_the_file_parsable_inside_a_block() {
  setup
  local rc="$TEST_HOME/rc" out
  printf 'if [ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]; then\n  . "$HOME/.sdkman/bin/sdkman-init.sh"\nfi\nexport KEEP=1\n' > "$rc"
  out="$(disable_matching_lines "$rc" 'sdkman' "SDKMAN replaced by mise" 2>&1)"
  assert_contains "$(cat "$rc")" 'if [ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]; then' "the opener is left alone" || return 1
  assert_contains "$(cat "$rc")" ': # Disabled by teeup (SDKMAN replaced by mise):   . "$HOME/.sdkman/bin/sdkman-init.sh"' || return 1
  assert_contains "$(cat "$rc")" "export KEEP=1" || return 1
  assert_contains "$out" "block-opening lines in $rc" || return 1
  bash -n "$rc" || { echo "the rewritten file no longer parses"; return 1; }
  cleanup_test_env
}

test_disable_matching_lines_is_idempotent() {
  setup
  local rc="$TEST_HOME/rc"
  printf 'eval "$(rbenv init -)"\n' > "$rc"
  disable_matching_lines "$rc" 'rbenv (init|shell)' "rbenv replaced by mise" >/dev/null
  disable_matching_lines "$rc" 'rbenv (init|shell)' "rbenv replaced by mise" >/dev/null
  assert_equals ': # Disabled by teeup (rbenv replaced by mise): eval "$(rbenv init -)"' "$(cat "$rc")" || return 1
  assert_equals "1" "$(find "$TEST_HOME" -name 'rc.teeup_backup_*' | wc -l | tr -d ' ')" "the second pass must not back up again" || return 1
  cleanup_test_env
}

test_disable_matching_lines_passes_the_pattern_to_awk_unescaped() {
  setup
  local rc="$TEST_HOME/rc"
  # "mypyenv" is the trap: awk expands escape sequences inside a -v
  # assignment, so the legacy version saw ".pyenv" (any character, then
  # "pyenv") and disabled this alias too.
  printf 'alias mypyenv="echo hi"\nexport PATH="$HOME/.pyenv/bin:$PATH"\n' > "$rc"
  disable_matching_lines "$rc" 'pyenv (init|virtualenv-init)|PYENV_ROOT|\.pyenv' "pyenv replaced by mise" >/dev/null
  assert_contains "$(cat "$rc")" 'alias mypyenv="echo hi"' "a name that merely contains pyenv must survive" || return 1
  assert_not_contains "$(cat "$rc")" 'Disabled by teeup (pyenv replaced by mise): alias mypyenv' || return 1
  assert_contains "$(cat "$rc")" ': # Disabled by teeup (pyenv replaced by mise): export PATH="$HOME/.pyenv/bin:$PATH"' || return 1
  cleanup_test_env
}

test_disable_matching_lines_leaves_a_symlink_alone() {
  setup
  local real="$TEST_HOME/real" link="$TEST_HOME/link" out
  printf 'eval "$(rbenv init -)"\n' > "$real"
  ln -s "$real" "$link"
  out="$(disable_matching_lines "$link" 'rbenv' "rbenv replaced by mise")"
  assert_contains "$out" "Not editing the symlink $link" || return 1
  assert_equals 'eval "$(rbenv init -)"' "$(cat "$real")" || return 1
  cleanup_test_env
}

test_disable_matching_lines_ignores_a_missing_file_and_a_pattern_that_matches_nothing() {
  setup
  local rc="$TEST_HOME/rc"
  disable_matching_lines "$TEST_HOME/nope" 'rbenv' "rbenv replaced by mise" >/dev/null || return 1
  printf 'export A=1\n' > "$rc"
  disable_matching_lines "$rc" 'rbenv' "rbenv replaced by mise" >/dev/null
  assert_equals 'export A=1' "$(cat "$rc")" || return 1
  assert_equals "0" "$(find "$TEST_HOME" -name 'rc.teeup_backup_*' | wc -l | tr -d ' ')" "nothing matched, so nothing is backed up" || return 1
  cleanup_test_env
}

test_disable_matching_lines_dry_run_changes_nothing() {
  setup
  local rc="$TEST_HOME/rc" out
  printf 'eval "$(rbenv init -)"\n' > "$rc"
  out="$(DRY_RUN=true disable_matching_lines "$rc" 'rbenv' "rbenv replaced by mise")"
  assert_contains "$out" "[DRY-RUN] Would disable matching lines in $rc: rbenv replaced by mise" || return 1
  assert_equals 'eval "$(rbenv init -)"' "$(cat "$rc")" || return 1
  assert_equals "0" "$(find "$TEST_HOME" -name 'rc.teeup_backup_*' | wc -l | tr -d ' ')" || return 1
  cleanup_test_env
}

test_disable_matching_lines_handles_a_path_with_spaces_and_metacharacters() {
  setup
  local dir="$TEST_HOME/od d \$x & 'q'" rc
  mkdir -p "$dir"
  rc="$dir/.zshrc"
  printf 'eval "$(rbenv init -)"\n' > "$rc"
  disable_matching_lines "$rc" 'rbenv' "rbenv replaced by mise" >/dev/null
  assert_equals ': # Disabled by teeup (rbenv replaced by mise): eval "$(rbenv init -)"' "$(cat "$rc")" || return 1
  assert_equals "1" "$(find "$dir" -name '.zshrc.teeup_backup_*' | wc -l | tr -d ' ')" || return 1
  cleanup_test_env
}

echo "lib/files.sh"
```

And their `run_test` lines, immediately above `print_summary`:

```bash edit-old=tests/lib/files.sh
run_test "replace_literal is literal and repeats" test_replace_literal_is_literal_and_repeats
print_summary
```
```bash edit-new=tests/lib/files.sh
run_test "replace_literal is literal and repeats" test_replace_literal_is_literal_and_repeats
run_test "disable_matching_lines neutralises only matching lines" test_disable_matching_lines_neutralises_only_matching_lines
run_test "disable_matching_lines keeps a block parsable" test_disable_matching_lines_keeps_the_file_parsable_inside_a_block
run_test "disable_matching_lines is idempotent" test_disable_matching_lines_is_idempotent
run_test "disable_matching_lines passes the pattern unescaped" test_disable_matching_lines_passes_the_pattern_to_awk_unescaped
run_test "disable_matching_lines leaves a symlink alone" test_disable_matching_lines_leaves_a_symlink_alone
run_test "disable_matching_lines ignores a missing file and a non-match" test_disable_matching_lines_ignores_a_missing_file_and_a_pattern_that_matches_nothing
run_test "disable_matching_lines dry run changes nothing" test_disable_matching_lines_dry_run_changes_nothing
run_test "disable_matching_lines handles an awkward path" test_disable_matching_lines_handles_a_path_with_spaces_and_metacharacters
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/lib/files.sh`
Expected: the eight new tests fail with `disable_matching_lines: command not found`. Do not expect `20/28`: `tests/lib/files.sh` reports **42** tests on `main` at `5186afe`, so the red state is that count plus the eight new ones, with eight failing (R3). Print the count first.

- [ ] **Step 3: Append the function to `lib/files.sh`**

```bash edit-old=lib/files.sh
  printf '%s\n' "$out$rest"
}
```
```bash edit-new=lib/files.sh
  printf '%s\n' "$out$rest"
}

# disable_matching_lines <file> <pattern> <reason>
# Neutralise every line of <file> that matches the awk ERE <pattern>, by
# rewriting it as ": # Disabled by teeup (<reason>): <the original line>".
# Spec section 10 asks for exactly this when retiring SDKMAN, rbenv and pyenv:
# the line stays visible, so a user who wanted it can put it back, and
# re-running changes nothing because a line that already starts with ": #" is
# skipped.
#
# The ":" matters. These init lines usually sit inside an "if ...; then"
# block, and an if whose entire body is commented out is a syntax error - the
# "fi" below it has nothing to close. ":" is the shell's no-op builtin, so the
# line stays a command wherever it is while carrying its old text along as a
# comment. For the same reason a matching line that OPENS a block (ends in
# "then", "do" or "in", or in "{", "(", "\", "&&" or "||") is left exactly as
# it is and reported: neutralising an opener would orphan its terminator. Its
# body is neutralised instead, and a bare test with a dead body does nothing.
#
# Ported from legacy/teeup.sh with two more fixes. The pattern and the reason
# reach awk through ENVIRON rather than -v: awk expands escape sequences
# inside a -v assignment, so the legacy call's '\.pyenv' arrived as '.pyenv' -
# any character followed by "pyenv" - and disabled unrelated lines. And the
# backup goes through backup_copy, so it previews under DRY_RUN and is logged
# like every other backup teeup takes.
#
# A missing file is nothing to do. A symlink belongs to whatever put it there
# (a dotfile manager writing through it would see teeup's edit as a local
# change), so it is left alone with a line saying so. The rewrite goes through
# a temp file that is cat'ed back rather than moved over the original, so the
# inode survives for anything watching or hard-linking the file. Always 0.
disable_matching_lines() {
  local file="$1" tmp skipped
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  if [[ -L "$file" ]]; then
    log "Not editing the symlink $file; whatever manages it owns its contents."
    return 0
  fi
  if ! TEEUP_DML_PATTERN="$2" awk '
    BEGIN { p = ENVIRON["TEEUP_DML_PATTERN"] }
    /^[[:space:]]*(#|:[[:space:]]#)/ { next }
    $0 ~ p { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$file"; then
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would disable matching lines in $file: $3"
    return 0
  fi
  backup_copy "$file" >/dev/null
  tmp="$(mktemp)"
  skipped="$(mktemp)"
  TEEUP_DML_PATTERN="$2" TEEUP_DML_REASON="$3" TEEUP_DML_SKIPPED="$skipped" awk '
    BEGIN {
      p = ENVIRON["TEEUP_DML_PATTERN"]
      r = ENVIRON["TEEUP_DML_REASON"]
      s = ENVIRON["TEEUP_DML_SKIPPED"]
    }
    /^[[:space:]]*(#|:[[:space:]]#)/ { print; next }
    $0 !~ p { print; next }
    /([[:space:];]|^)(then|do|in)[[:space:]]*$/ || /[({][[:space:]]*$/ || /(\\|&&|\|\|)[[:space:]]*$/ {
      print NR ": " $0 > s
      print
      next
    }
    { print ": # Disabled by teeup (" r "): " $0 }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
  if [[ -s "$skipped" ]]; then
    warn "Left these block-opening lines in $file alone; their bodies are disabled, but check them by hand:"
    sed 's/^/    /' "$skipped" >&2
  fi
  rm -f "$skipped"
  ok "Disabled $3 lines in $file"
}
```

- [ ] **Step 4: Run the suite for this file**

Run: `bash tests/lib/files.sh`
Expected: `Summary: 28/28 passed`.

- [ ] **Step 5: Run the whole suite and the checks**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning lib/files.sh tests/lib/files.sh && git diff --check`
Expected: the same suite count as the task before this one (no new suite file), `commands --check` silent, shellcheck silent, `git diff --check` silent.

- [ ] **Step 6: Commit**

```bash
git add lib/files.sh tests/lib/files.sh
git commit -m "Port disable_matching_lines out of the legacy script"
```

---

### Task 2: `lib/migrate.sh` — the closed key list, the safety gates and the read-only chezmoi wrapper

> **Rulings folded in (Revision 2).**
> **T2.1 (Blocking) — fail closed, and never delete inside a git checkout.**
> `migrate_path_is_safe` gets two more refusals:
> (a) when `have chezmoi` is true but `migrate_chezmoi_source` prints nothing, refuse the
> path — an undeterminable source directory is not an absent one;
> (b) refuse any resolved path with a `.git` entry in any directory between it and `$HOME`.
> Without both, a user who answers yes to deleting `~/.config/chezmoi` and later re-runs
> the verb on a machine whose `~/.config` is symlinked into `~/Work/environment/dotfiles`
> gets `rm -rf` inside the repo that still serves Linux. The user has declared that
> outcome absolute. Each gate needs its own refusal test.
> **T2.2 — the `lib/all.sh` anchor in this task is stale.** The real line is
> `for _teeup_lib in files state answers pkg ui capability macos theme font lazy mise hooks migrations; do`
> (`lib/all.sh:9`). Append ` migrate` to **that** line and change nothing else. Do not paste
> this plan's older version, which sources `doctor`, `menu` and `dev` libraries that do not
> exist and would break every verb.
> **A5 — make the `chezmoi_ro` rule enforceable.** Alongside the unit test that
> `chezmoi_ro purge` dies, add a test that greps `bin/`, `lib/` and `capabilities/` for a
> `chezmoi` invocation outside `chezmoi_ro` and fails if it finds one. Otherwise the
> guarantee lasts exactly until someone adds a second call site.

Nothing in this task deletes anything a user would notice; it builds the three gates described under Contracts and proves each one refuses. The migration steps that use them are Tasks 3, 4 and 5.

**Files:**
- Create: `lib/migrate.sh`
- Create: `tests/lib/migrate.sh`
- Modify: `lib/all.sh`

**Interfaces:**
- Consumes: `log ok warn err die have run_cmd user_config_dir` and `DRY_RUN` (`lib/core.sh`).
- Produces:
  - `TEEUP_MIGRATE_RC_FILES` — the space-separated rc file names, relative to `$HOME`, that every predecessor wrote into: `.zshenv .zprofile .zshrc .bashrc .bash_profile .profile`.
  - `migrate_target <key>` — prints the absolute path for one of `teeup-common teeupshrc shellrc-common mac-setup chezmoi-config`; prints nothing and returns 1 for anything else.
  - `chezmoi_ro <subcommand> [args…]` — runs `chezmoi` for `managed`, `source-path` and `--version` only; `die`s on anything else.
  - `migrate_chezmoi_source` — prints the physical chezmoi source directory, or nothing when there is no chezmoi or no source.
  - `migrate_resolve <path>` — prints the path with every symlink above the last component resolved and the last component left as it is; returns 1 when the parent directory does not exist.
  - `migrate_path_is_safe <resolved-path>` — 0 when teeup's migration may delete it.
  - `migrate_rm <key>` — the only deletion in the migration. 0 when it removed something or there was nothing there, 1 when it refused.

**Real-Mac risk:** `$TMPDIR` on macOS is under `/var/folders/…`, which is itself a symlink to `/private/var/folders/…`, so `$HOME` inside a test is a path whose physical form differs from its literal one. That is precisely what `migrate_path_is_safe` compares, and the Linux CI runner never exercises the difference; only a Mac (or a macOS runner) proves the physical-form comparison holds there. `pwd -P` and `dirname`/`basename` are POSIX and present on both.

- [ ] **Step 1: Write the failing test**

Create `tests/lib/migrate.sh`:

```bash file=tests/lib/migrate.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# Every test in this file runs inside the harness's throwaway HOME. The
# stand-in for the sibling chezmoi repo (~/Work/environment/dotfiles on the
# real machine, which keeps serving Linux and must never be touched) is
# created under $TEST_HOME with the same shape, so nothing here can reach the
# real one even if a gate were broken.
SIBLING_REL="Work/environment/dotfiles"

setup() {
  setup_test_env
  mock_macos_base
  # A config root whose name carries a space and three characters that are
  # special to sed, awk and the shell.
  export XDG_CONFIG_HOME="$TEST_HOME/con fig \$x & 'q'"
  export TEEUP_CONFIG_DIR="$XDG_CONFIG_HOME/teeup"
  export TEEUP_STATE_DIR="$TEST_HOME/sta te \$x & 'q'/teeup"
  # Prompts must be pipe-driven: the narrowed PATH still exposes a host gum.
  export TEEUP_NO_GUM=1
  source "$TEEUP_PATH/lib/all.sh"
  export DRY_RUN=false
  SIBLING="$TEST_HOME/$SIBLING_REL"
  mkdir -p "$SIBLING/dot_config"
  printf 'sibling\n' > "$SIBLING/dot_zshrc"
}

# A chezmoi that says $SIBLING is its source directory and lists whatever
# $TEEUP_TEST_CHEZMOI_MANAGED holds. Every call lands in $MOCK_LOG, so a test
# can prove which subcommands ran.
mock_chezmoi() {
  export TEEUP_TEST_CHEZMOI_SRC="${1:-$SIBLING}"
  mock_command_script chezmoi <<'EOF2'
case "$1" in
  source-path) printf '%s\n' "$TEEUP_TEST_CHEZMOI_SRC" ;;
  managed) cat "${TEEUP_TEST_CHEZMOI_MANAGED:-/dev/null}" ;;
  --version) echo "chezmoi version v2.66.0" ;;
  *) echo "mock chezmoi: unexpected subcommand $1" >&2; exit 1 ;;
esac
EOF2
}

no_chezmoi() { export TEEUP_TEST_MISSING="chezmoi"; }

test_migrate_target_names_only_the_five_legacy_paths() {
  setup
  assert_equals "$TEST_HOME/.teeup.common" "$(migrate_target teeup-common)" || return 1
  assert_equals "$TEST_HOME/.teeupshrc" "$(migrate_target teeupshrc)" || return 1
  assert_equals "$TEST_HOME/.shellrc.common" "$(migrate_target shellrc-common)" || return 1
  assert_equals "$XDG_CONFIG_HOME/mac-setup" "$(migrate_target mac-setup)" || return 1
  assert_equals "$XDG_CONFIG_HOME/chezmoi" "$(migrate_target chezmoi-config)" || return 1
  local rc=0
  migrate_target "$SIBLING" >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "a path is not a key" || return 1
  rc=0
  migrate_target dotfiles >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "there is no key for the sibling repo" || return 1
  cleanup_test_env
}

test_chezmoi_ro_runs_the_read_only_subcommands() {
  setup
  mock_chezmoi
  assert_equals "$SIBLING" "$(chezmoi_ro source-path)" || return 1
  assert_contains "$(chezmoi_ro --version)" "chezmoi version" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "chezmoi source-path" || return 1
  cleanup_test_env
}

test_chezmoi_ro_refuses_purge_and_every_other_subcommand() {
  setup
  mock_chezmoi
  local sub rc out
  for sub in purge apply init destroy forget remove edit update; do
    rc=0
    out="$( (chezmoi_ro "$sub") 2>&1 )" || rc=$?
    assert_failure "$rc" "chezmoi_ro must refuse $sub" || return 1
    assert_contains "$out" "only runs read-only chezmoi subcommands" || return 1
  done
  assert_not_contains "$(cat "$MOCK_LOG")" "chezmoi purge" "the refusal happens before chezmoi is reached" || return 1
  cleanup_test_env
}

test_migrate_resolve_resolves_the_parent_and_keeps_the_last_component() {
  setup
  local home
  home="$(cd "$TEST_HOME" && pwd -P)"
  mkdir -p "$TEST_HOME/real dir"
  ln -s "$TEST_HOME/real dir" "$TEST_HOME/link dir"
  assert_equals "$home/real dir/thing" "$(migrate_resolve "$TEST_HOME/link dir/thing")" || return 1
  assert_equals "$home/.teeupshrc" "$(migrate_resolve "$TEST_HOME/real dir/../.teeupshrc")" || return 1
  # The last component is never followed, so a dangling link resolves to
  # itself and can be removed without chasing where it pointed.
  ln -s "$TEST_HOME/gone" "$TEST_HOME/dangling"
  assert_equals "$home/dangling" "$(migrate_resolve "$TEST_HOME/dangling")" || return 1
  local rc=0
  migrate_resolve "$TEST_HOME/no such dir/file" >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "a missing parent directory cannot be resolved" || return 1
  cleanup_test_env
}

test_migrate_path_is_safe_refuses_home_itself_and_anything_outside_it() {
  setup
  no_chezmoi
  local home
  home="$(cd "$TEST_HOME" && pwd -P)"
  migrate_path_is_safe "$home/.teeup.common" || { echo "a plain file under HOME must be safe"; return 1; }
  if migrate_path_is_safe "$home"; then echo "HOME itself must be refused"; return 1; fi
  if migrate_path_is_safe "/etc/zshrc"; then echo "a path outside HOME must be refused"; return 1; fi
  if migrate_path_is_safe "/"; then echo "/ must be refused"; return 1; fi
  if migrate_path_is_safe "$home/../elsewhere"; then echo "a .. component must be refused"; return 1; fi
  cleanup_test_env
}

test_migrate_path_is_safe_refuses_the_chezmoi_source_directory() {
  setup
  mock_chezmoi
  local src home
  src="$(cd "$SIBLING" && pwd -P)"
  home="$(cd "$TEST_HOME" && pwd -P)"
  if migrate_path_is_safe "$src"; then echo "the source directory itself must be refused"; return 1; fi
  if migrate_path_is_safe "$src/dot_zshrc"; then echo "a file inside it must be refused"; return 1; fi
  if migrate_path_is_safe "$(dirname "$src")"; then echo "a directory containing it must be refused"; return 1; fi
  migrate_path_is_safe "$home/.teeup.common" || { echo "an unrelated path is still safe"; return 1; }
  cleanup_test_env
}

test_migrate_rm_removes_a_file_a_directory_and_a_dangling_symlink() {
  setup
  no_chezmoi
  printf 'legacy\n' > "$TEST_HOME/.teeup.common"
  mkdir -p "$XDG_CONFIG_HOME/mac-setup"
  printf 'x\n' > "$XDG_CONFIG_HOME/mac-setup/zsh.zsh"
  ln -s "$TEST_HOME/gone" "$TEST_HOME/.teeupshrc"
  migrate_rm teeup-common >/dev/null || return 1
  migrate_rm mac-setup >/dev/null || return 1
  migrate_rm teeupshrc >/dev/null || return 1
  if [[ -e "$TEST_HOME/.teeup.common" ]]; then echo "the file is still there"; return 1; fi
  if [[ -d "$XDG_CONFIG_HOME/mac-setup" ]]; then echo "the directory is still there"; return 1; fi
  if [[ -L "$TEST_HOME/.teeupshrc" ]]; then echo "the dangling link is still there"; return 1; fi
  # A key whose path does not exist is not an error.
  local out
  out="$(migrate_rm shellrc-common)"
  assert_contains "$out" "Nothing at $TEST_HOME/.shellrc.common" || return 1
  cleanup_test_env
}

test_migrate_rm_removes_a_live_symlink_without_touching_its_target() {
  setup
  no_chezmoi
  printf 'still here\n' > "$SIBLING/teeup.common"
  ln -s "$SIBLING/teeup.common" "$TEST_HOME/.teeup.common"
  migrate_rm teeup-common >/dev/null || return 1
  if [[ -L "$TEST_HOME/.teeup.common" ]]; then echo "the link is still there"; return 1; fi
  assert_equals "still here" "$(cat "$SIBLING/teeup.common")" "removing a link must never touch its target" || return 1
  cleanup_test_env
}

test_migrate_rm_refuses_an_unknown_key() {
  setup
  no_chezmoi
  local rc=0 out
  out="$( (migrate_rm dotfiles) 2>&1 )" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "no target named 'dotfiles'" || return 1
  rc=0
  out="$( (migrate_rm "$SIBLING") 2>&1 )" || rc=$?
  assert_failure "$rc" "a path is not a key, so it cannot be removed" || return 1
  assert_dir_exists "$SIBLING" || return 1
  cleanup_test_env
}

test_migrate_rm_refuses_a_key_that_resolves_inside_the_chezmoi_source_directory() {
  setup
  mock_chezmoi
  # The config root moved into the checkout: the key list is still closed, but
  # the path it names now lands inside the repo that serves Linux.
  export XDG_CONFIG_HOME="$SIBLING/dot_config"
  mkdir -p "$XDG_CONFIG_HOME/mac-setup" "$XDG_CONFIG_HOME/chezmoi"
  printf 'x\n' > "$XDG_CONFIG_HOME/mac-setup/zsh.zsh"
  local rc=0 out
  out="$(migrate_rm mac-setup 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Refusing to remove" || return 1
  assert_dir_exists "$XDG_CONFIG_HOME/mac-setup" "the sibling repo must be untouched" || return 1
  rc=0
  out="$(migrate_rm chezmoi-config 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_dir_exists "$XDG_CONFIG_HOME/chezmoi" || return 1
  cleanup_test_env
}

test_migrate_rm_refuses_a_config_root_symlinked_into_the_checkout() {
  setup
  mock_chezmoi
  mkdir -p "$SIBLING/dot_config/chezmoi"
  export XDG_CONFIG_HOME="$TEST_HOME/.config"
  rm -rf "$XDG_CONFIG_HOME"
  ln -s "$SIBLING/dot_config" "$XDG_CONFIG_HOME"
  local rc=0 out
  out="$(migrate_rm chezmoi-config 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Refusing to remove" || return 1
  assert_dir_exists "$SIBLING/dot_config/chezmoi" || return 1
  cleanup_test_env
}

test_migrate_rm_dry_run_changes_nothing() {
  setup
  no_chezmoi
  printf 'legacy\n' > "$TEST_HOME/.teeup.common"
  local out
  out="$(DRY_RUN=true migrate_rm teeup-common)"
  assert_contains "$out" "[DRY-RUN] Would execute: rm -f $TEST_HOME/.teeup.common" || return 1
  assert_file_exists "$TEST_HOME/.teeup.common" || return 1
  cleanup_test_env
}

echo "lib/migrate.sh"
run_test "migrate_target names only the five legacy paths" test_migrate_target_names_only_the_five_legacy_paths
run_test "chezmoi_ro runs the read-only subcommands" test_chezmoi_ro_runs_the_read_only_subcommands
run_test "chezmoi_ro refuses purge and everything else" test_chezmoi_ro_refuses_purge_and_every_other_subcommand
run_test "migrate_resolve resolves the parent only" test_migrate_resolve_resolves_the_parent_and_keeps_the_last_component
run_test "migrate_path_is_safe refuses HOME and outside it" test_migrate_path_is_safe_refuses_home_itself_and_anything_outside_it
run_test "migrate_path_is_safe refuses the chezmoi source dir" test_migrate_path_is_safe_refuses_the_chezmoi_source_directory
run_test "migrate_rm removes file, directory and dangling link" test_migrate_rm_removes_a_file_a_directory_and_a_dangling_symlink
run_test "migrate_rm keeps a live link's target" test_migrate_rm_removes_a_live_symlink_without_touching_its_target
run_test "migrate_rm refuses an unknown key" test_migrate_rm_refuses_an_unknown_key
run_test "migrate_rm refuses a key inside the checkout" test_migrate_rm_refuses_a_key_that_resolves_inside_the_chezmoi_source_directory
run_test "migrate_rm refuses a symlinked config root" test_migrate_rm_refuses_a_config_root_symlinked_into_the_checkout
run_test "migrate_rm dry run changes nothing" test_migrate_rm_dry_run_changes_nothing
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/lib/migrate.sh`
Expected: every test fails, because `lib/all.sh` defines none of `migrate_target`, `chezmoi_ro`, `migrate_resolve`, `migrate_path_is_safe` or `migrate_rm`. The suite ends with `Summary: 0/12 passed`.

- [ ] **Step 3: Write `lib/migrate.sh`**

```bash file=lib/migrate.sh
#!/usr/bin/env bash
# migrate.sh - `teeup migrate legacy`: retire this teeup's predecessors on a
# machine that already had one. Spec section 10.
#
# Two predecessors exist. The old monolithic teeup.sh wrote ~/.teeup.common,
# ~/.config/mac-setup and a handful of ~/.<name> symlinks, and appended blocks
# to the shell rc files that source them. The chezmoi repo at
# ~/Work/environment/dotfiles still owns $HOME on machines that ran it, and it
# still serves Linux, so it is never deleted, never purged, and never even
# written to: this file only ever reads from chezmoi.
#
# Everything this file deletes is named by a KEY, never by a path. migrate_rm
# takes a key and asks migrate_target for the path itself, so the set of
# deletable things is fixed by the case statement below and no caller can
# widen it. Two further gates run on the resolved path anyway, because an
# XDG_CONFIG_HOME override or a symlinked ~/.config can still make a key land
# somewhere it must not.
#
# Requires core.sh, files.sh, state.sh, ui.sh.

# The rc files every predecessor wrote into, relative to $HOME, in the order
# they are visited. Names only: each step joins them to $HOME itself. Exported
# like TEEUP_MIGRATIONS_DIR and the rest of teeup's module variables, so a
# capability script or a migration can read the same list.
TEEUP_MIGRATE_RC_FILES=".zshenv .zprofile .zshrc .bashrc .bash_profile .profile"
export TEEUP_MIGRATE_RC_FILES

# migrate_target <key> -> the absolute path that key names
# The closed list. Anything that is not one of these five keys has no path, so
# migrate_rm can never be pointed at it — the sibling chezmoi checkout
# included. Returns 1 and prints nothing for an unknown key.
migrate_target() {
  case "$1" in
    teeup-common)   printf '%s\n' "$HOME/.teeup.common" ;;
    teeupshrc)      printf '%s\n' "$HOME/.teeupshrc" ;;
    shellrc-common) printf '%s\n' "$HOME/.shellrc.common" ;;
    mac-setup)      printf '%s\n' "$(user_config_dir)/mac-setup" ;;
    chezmoi-config) printf '%s\n' "$(user_config_dir)/chezmoi" ;;
    *) return 1 ;;
  esac
}

# chezmoi_ro <subcommand> [args...]
# The only place in teeup that runs chezmoi, and it runs only read-only
# subcommands. `chezmoi purge` "removes chezmoi's configuration, state, and
# source directory" (chezmoi reference, purge), which is the sibling repo, so
# it is not on the list and cannot be reached from anywhere - including a
# capability's doctor script, which sources this file like everything else.
# An unlisted subcommand is a programming error, not a user mistake, so it
# dies rather than warning.
chezmoi_ro() {
  case "${1:-}" in
    managed|source-path|--version) ;;
    *) die "teeup only runs read-only chezmoi subcommands; '${1:-}' is not one of managed, source-path, --version." ;;
  esac
  chezmoi "$@"
}

# migrate_chezmoi_source -> the physical chezmoi source directory, or nothing
# Nothing when chezmoi is not installed, when it reports no source directory,
# or when the directory it reports does not exist. Physical form (pwd -P), so
# a symlinked path cannot slip past the comparisons in migrate_path_is_safe.
migrate_chezmoi_source() {
  local src
  have chezmoi || return 0
  src="$(chezmoi_ro source-path 2>/dev/null)" || return 0
  [[ -n "$src" ]] || return 0
  src="$(cd "$src" 2>/dev/null && pwd -P)" || return 0
  printf '%s\n' "$src"
}

# migrate_resolve <path> -> the path with its parent resolved
# Every symlink ABOVE the last component is resolved; the last component is
# left exactly as it is, so a dangling or foreign symlink can be removed
# without following it to whatever it points at. Returns 1 when the parent
# directory does not exist (macOS has no readlink -f, hence cd + pwd -P).
migrate_resolve() {
  local path="$1" parent base
  parent="$(dirname "$path")"
  base="$(basename "$path")"
  parent="$(cd "$parent" 2>/dev/null && pwd -P)" || return 1
  [[ -n "$parent" ]] || return 1
  case "$parent" in
    /) printf '/%s\n' "$base" ;;
    *) printf '%s/%s\n' "$parent" "$base" ;;
  esac
}

# migrate_path_is_safe <resolved-path>
# 0 when teeup's migration may delete it. Three refusals:
#   - not strictly inside the physical $HOME (so never /, never $HOME itself,
#     never anything in /etc or another user's home);
#   - a ".." component survived resolution;
#   - it is the chezmoi source directory, something inside it, or a directory
#     that contains it. That last one is what keeps
#     ~/Work/environment/dotfiles - still serving Linux - out of reach even
#     when a key resolves into it through a symlinked ~/.config.
migrate_path_is_safe() {
  local path="$1" home src
  home="$(cd "$HOME" 2>/dev/null && pwd -P)" || return 1
  case "$path" in
    "$home") return 1 ;;
    "$home"/*) ;;
    *) return 1 ;;
  esac
  case "$path" in
    */..|*/../*) return 1 ;;
  esac
  src="$(migrate_chezmoi_source)"
  if [[ -n "$src" ]]; then
    case "$path" in
      "$src"|"$src"/*) return 1 ;;
    esac
    case "$src" in
      "$path"/*) return 1 ;;
    esac
  fi
  return 0
}

# migrate_rm <key>
# The only deletion in the migration. Takes a key, never a path. Order is
# deliberate: the safety gate runs before the existence check, so a key that
# resolves somewhere forbidden is refused out loud whether or not anything is
# there. A symlink is removed with rm -f on the link itself and what it points
# at is never touched; only a real directory gets rm -rf.
# 0 when it removed something or there was nothing to remove, 1 when refused.
migrate_rm() {
  local key="$1" path resolved
  if ! path="$(migrate_target "$key")"; then
    err "teeup migrate has no target named '$key'; nothing was removed."
    return 1
  fi
  if ! resolved="$(migrate_resolve "$path")"; then
    log "Nothing at $path."
    return 0
  fi
  if ! migrate_path_is_safe "$resolved"; then
    warn "Refusing to remove $path: it resolves to $resolved, which teeup's migration must not touch."
    return 1
  fi
  if [[ ! -e "$resolved" && ! -L "$resolved" ]]; then
    log "Nothing at $path."
    return 0
  fi
  if [[ -L "$resolved" ]]; then
    run_cmd rm -f "$resolved"
    ok "Removed the legacy symlink $path"
    return 0
  fi
  if [[ -d "$resolved" ]]; then
    run_cmd rm -rf "$resolved"
    ok "Removed the legacy directory $path"
    return 0
  fi
  run_cmd rm -f "$resolved"
  ok "Removed the legacy file $path"
}
```

- [ ] **Step 4: Source the new library**

`lib/all.sh` sources every library in one loop. Append `migrate` to the end of the list; the libraries define functions and run nothing at source time, so their order among themselves does not matter.

```bash edit-old=lib/all.sh
for _teeup_lib in files state answers pkg ui capability macos theme font lazy mise hooks migrations; do
```
```bash edit-new=lib/all.sh
for _teeup_lib in files state answers pkg ui capability macos theme font lazy mise hooks migrations migrate; do
```

If the list in the checkout differs (an earlier phase landing in another order), make the same change: append ` migrate` to the end of whatever list is there, leaving the rest untouched.

- [ ] **Step 5: Run the new suite**

Run: `bash tests/lib/migrate.sh`
Expected: `Summary: 12/12 passed`.

- [ ] **Step 6: Run the whole suite and the checks**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning lib/migrate.sh lib/all.sh tests/lib/migrate.sh && git diff --check`
Expected: the suite count printed before this task, plus 1 (`tests/lib/migrate.sh` is new); everything else silent.

- [ ] **Step 7: Commit**

```bash
git add lib/migrate.sh lib/all.sh tests/lib/migrate.sh
git commit -m "Add the migration safety gates and the read-only chezmoi wrapper"
```

---

### Task 3: `migrate_legacy_paths` — the legacy files, directories, symlinks and rc wiring

> **Ruling folded in (Revision 2). T3.1 — honour `ZDOTDIR`.** Visit
> `${ZDOTDIR:-$HOME}/<name>` as well as `$HOME/<name>` for the zsh rc files, de-duplicating
> when the two are the same directory; the zsh capability installs its stubs into
> `${ZDOTDIR:-$HOME}` (`capabilities/zsh/configure`). On a `ZDOTDIR` machine the migration
> otherwise reports success while changing nothing.

Spec section 10, first half: "removes `~/.teeup.common`, `~/.config/mac-setup`, dangling legacy symlinks". The rc lines that loaded them go too, because a `source ~/.teeup.common` left behind after the file is gone makes every new shell print an error. The Oh My Zsh, Powerlevel10k and Antigen lines go with them: spec section 10 asks `teeup doctor` to flag p10k and Oh My Zsh remnants, and a finding is worth printing only when the fix it names really fixes it — `teeup migrate legacy` is that fix, so it has to neutralise those lines too. (`legacy/teeup.sh:2227` disabled the Antigen lines for the same reason.)

**Files:**
- Modify: `lib/migrate.sh` (append after `migrate_rm`)
- Modify: `tests/lib/migrate.sh`

**Interfaces:**
- Consumes: `migrate_rm`, `TEEUP_MIGRATE_RC_FILES` (`lib/migrate.sh`, Task 2); `disable_matching_lines` (`lib/files.sh`, Task 1); `log` (`lib/core.sh`).
- Produces:
  - `TEEUP_MIGRATE_LEGACY_RC_PATTERN` — the awk ERE matching every rc line that loads one of the old teeup's files.
  - `TEEUP_MIGRATE_PROMPT_RC_PATTERN` — the awk ERE matching Oh My Zsh, Powerlevel10k and Antigen lines. Task 7's `zsh` doctor looks for the union of the two, so a machine that has run the migration reads as clean.
  - `migrate_legacy_paths` — removes the four legacy entries and neutralises every rc line either pattern matches. 0 when everything it tried succeeded, 1 when at least one removal was refused; a refusal never stops the rest.

**Note for the implementer:** teeup's own `~/.zshrc`, `~/.zshenv` and `~/.zprofile` stubs (phase 2a) contain none of these names, so `disable_matching_lines` finds nothing in them and leaves them byte-identical — which matters, because editing one would change its sha and make `copy_config_once` report it as user-edited from then on. The test below asserts that.

**Real-Mac risk:** on a machine that ran the old teeup for years, `~/.zshrc` may hold hand-edited variants of these blocks that no test here anticipates. What a real Mac proves is whether the block-opener rule from Task 1 covers the shapes actually on that machine; the backup `disable_matching_lines` takes is the safety net either way.

- [ ] **Step 1: Write the failing tests**

Add these four tests to `tests/lib/migrate.sh`, immediately above the `echo "lib/migrate.sh"` line:

```bash edit-old=tests/lib/migrate.sh
echo "lib/migrate.sh"
```
```bash edit-new=tests/lib/migrate.sh
test_migrate_legacy_paths_removes_every_legacy_entry_and_neutralises_the_rc_lines() {
  setup
  no_chezmoi
  printf 'legacy\n' > "$TEST_HOME/.teeup.common"
  mkdir -p "$XDG_CONFIG_HOME/mac-setup"
  printf 'x\n' > "$XDG_CONFIG_HOME/mac-setup/zsh.zsh"
  ln -s "$TEST_HOME/gone" "$TEST_HOME/.teeupshrc"
  ln -s "$TEST_HOME/gone" "$TEST_HOME/.shellrc.common"
  printf '%s\n' \
    'export KEEP=1' \
    'if [ -r "$HOME/.config/mac-setup/zsh.zsh" ]; then' \
    '  source "$HOME/.config/mac-setup/zsh.zsh"' \
    'fi' \
    'source "$HOME/.teeup.common"' \
    'source "$HOME/.p10k.zsh"' > "$TEST_HOME/.zshrc"
  migrate_legacy_paths >/dev/null 2>&1 || return 1
  if [[ -e "$TEST_HOME/.teeup.common" ]]; then echo ".teeup.common survived"; return 1; fi
  if [[ -d "$XDG_CONFIG_HOME/mac-setup" ]]; then echo "mac-setup survived"; return 1; fi
  if [[ -L "$TEST_HOME/.teeupshrc" ]]; then echo ".teeupshrc survived"; return 1; fi
  if [[ -L "$TEST_HOME/.shellrc.common" ]]; then echo ".shellrc.common survived"; return 1; fi
  local body
  body="$(cat "$TEST_HOME/.zshrc")"
  assert_contains "$body" "export KEEP=1" || return 1
  assert_contains "$body" 'if [ -r "$HOME/.config/mac-setup/zsh.zsh" ]; then' "the opener stays so fi still closes something" || return 1
  assert_contains "$body" ': # Disabled by teeup (replaced by teeup'"'"'s zsh layer):   source "$HOME/.config/mac-setup/zsh.zsh"' || return 1
  assert_contains "$body" ': # Disabled by teeup (replaced by teeup'"'"'s zsh layer): source "$HOME/.teeup.common"' || return 1
  assert_contains "$body" ': # Disabled by teeup (replaced by teeup'"'"'s starship prompt): source "$HOME/.p10k.zsh"' || return 1
  bash -n "$TEST_HOME/.zshrc" || { echo "the rewritten .zshrc no longer parses"; return 1; }
  cleanup_test_env
}

test_migrate_legacy_paths_leaves_an_rc_without_legacy_lines_byte_identical() {
  setup
  no_chezmoi
  printf 'source "%s/capabilities/zsh/default/rc"\n' "$TEEUP_PATH" > "$TEST_HOME/.zshrc"
  local before
  before="$(cat "$TEST_HOME/.zshrc")"
  migrate_legacy_paths >/dev/null 2>&1 || return 1
  assert_equals "$before" "$(cat "$TEST_HOME/.zshrc")" "teeup's own stub must not be rewritten" || return 1
  assert_equals "0" "$(find "$TEST_HOME" -maxdepth 1 -name '.zshrc.teeup_backup_*' | wc -l | tr -d ' ')" || return 1
  cleanup_test_env
}

test_migrate_legacy_paths_reports_a_refusal_and_still_does_the_rest() {
  setup
  mock_chezmoi
  printf 'legacy\n' > "$TEST_HOME/.teeup.common"
  # The config root sits inside the checkout that still serves Linux, so
  # mac-setup must be refused while everything else proceeds.
  export XDG_CONFIG_HOME="$SIBLING/dot_config"
  mkdir -p "$XDG_CONFIG_HOME/mac-setup"
  local rc=0 out
  out="$(migrate_legacy_paths 2>&1)" || rc=$?
  assert_failure "$rc" "a refusal must be reported through the exit status" || return 1
  assert_contains "$out" "Refusing to remove" || return 1
  assert_dir_exists "$XDG_CONFIG_HOME/mac-setup" "the sibling repo is untouched" || return 1
  if [[ -e "$TEST_HOME/.teeup.common" ]]; then echo "the refusal stopped the rest of the work"; return 1; fi
  cleanup_test_env
}

test_migrate_legacy_paths_dry_run_changes_nothing() {
  setup
  no_chezmoi
  printf 'legacy\n' > "$TEST_HOME/.teeup.common"
  printf 'source "$HOME/.teeup.common"\n' > "$TEST_HOME/.zshrc"
  local out
  out="$(DRY_RUN=true migrate_legacy_paths 2>&1)" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: rm -f $TEST_HOME/.teeup.common" || return 1
  assert_contains "$out" "[DRY-RUN] Would disable matching lines in $TEST_HOME/.zshrc" || return 1
  assert_file_exists "$TEST_HOME/.teeup.common" || return 1
  assert_equals 'source "$HOME/.teeup.common"' "$(cat "$TEST_HOME/.zshrc")" || return 1
  cleanup_test_env
}

echo "lib/migrate.sh"
```

And their `run_test` lines, immediately above `print_summary`:

```bash edit-old=tests/lib/migrate.sh
run_test "migrate_rm dry run changes nothing" test_migrate_rm_dry_run_changes_nothing
print_summary
```
```bash edit-new=tests/lib/migrate.sh
run_test "migrate_rm dry run changes nothing" test_migrate_rm_dry_run_changes_nothing
run_test "migrate_legacy_paths clears the legacy entries and rc lines" test_migrate_legacy_paths_removes_every_legacy_entry_and_neutralises_the_rc_lines
run_test "migrate_legacy_paths leaves a clean rc untouched" test_migrate_legacy_paths_leaves_an_rc_without_legacy_lines_byte_identical
run_test "migrate_legacy_paths keeps going after a refusal" test_migrate_legacy_paths_reports_a_refusal_and_still_does_the_rest
run_test "migrate_legacy_paths dry run changes nothing" test_migrate_legacy_paths_dry_run_changes_nothing
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/lib/migrate.sh`
Expected: the four new tests fail with `migrate_legacy_paths: command not found`; the suite ends with `Summary: 12/16 passed`.

- [ ] **Step 3: Append the step to `lib/migrate.sh`**

```bash edit-old=lib/migrate.sh
  run_cmd rm -f "$resolved"
  ok "Removed the legacy file $path"
}
```
```bash edit-new=lib/migrate.sh
  run_cmd rm -f "$resolved"
  ok "Removed the legacy file $path"
}

# Every rc line that wired a predecessor into a shell. Two patterns, because
# the reason printed on each neutralised line should say which predecessor it
# came from. teeup's own zsh stubs (phase 2a) contain none of these names, so
# neither pattern touches them and their stock checksums stay valid.
TEEUP_MIGRATE_LEGACY_RC_PATTERN='teeup\.common|teeupshrc|shellrc\.common|mac-setup'
# Oh My Zsh, Powerlevel10k and Antigen: the prompt and plugin frameworks that
# teeup's zsh layer and starship replace. legacy/teeup.sh disabled the antigen
# lines for the same reason. capabilities/zsh/doctor looks for exactly this
# union afterwards, so anything added here belongs there too.
TEEUP_MIGRATE_PROMPT_RC_PATTERN='powerlevel10k|p10k|POWERLEVEL9K_|oh-my-zsh|ohmyzsh|ZSH_THEME|antigen'

# migrate_legacy_paths
# What the old monolithic teeup.sh left behind: ~/.teeup.common (a file it
# generated with append_once), ~/.config/mac-setup (which held the generated
# zsh.zsh), and the ~/.teeupshrc and ~/.shellrc.common symlinks it created
# into whatever dotfiles directory it was pointed at. Removing the files
# without neutralising the lines that source them would make every new shell
# print an error, so both halves happen here.
# 0 when everything it tried succeeded, 1 when a removal was refused. A
# refusal never stops the rest.
migrate_legacy_paths() {
  local key name rc=0
  log "Removing what older teeup versions left in your home directory"
  for key in teeup-common teeupshrc shellrc-common mac-setup; do
    if ! migrate_rm "$key"; then
      rc=1
    fi
  done
  log "Neutralising the shell lines that loaded them"
  for name in $TEEUP_MIGRATE_RC_FILES; do
    disable_matching_lines "$HOME/$name" "$TEEUP_MIGRATE_LEGACY_RC_PATTERN" "replaced by teeup's zsh layer"
    disable_matching_lines "$HOME/$name" "$TEEUP_MIGRATE_PROMPT_RC_PATTERN" "replaced by teeup's starship prompt"
  done
  return $rc
}
```

- [ ] **Step 4: Run the suite for this file**

Run: `bash tests/lib/migrate.sh`
Expected: `Summary: 16/16 passed`.

- [ ] **Step 5: Run the whole suite and the checks**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning lib/migrate.sh tests/lib/migrate.sh && git diff --check`
Expected: the same suite count as the task before this one; everything else silent.

- [ ] **Step 6: Commit**

```bash
git add lib/migrate.sh tests/lib/migrate.sh
git commit -m "Remove the files and shell wiring the old teeup left behind"
```

---

### Task 4: `migrate_disable_runtime_inits` — SDKMAN, rbenv and pyenv

> **Ruling folded in (Revision 2). T4.1 — the same `ZDOTDIR` rule as T3.1**; the rc list is
> shared. Otherwise the SDKMAN/rbenv/pyenv lines that actually run on that machine keep
> running alongside mise, which is the shadowing this step exists to stop.

Spec section 10: "disables SDKMAN, rbenv, pyenv init lines (reusing `disable_matching_lines`)". mise owns every runtime now (phase 3b), and two managers both putting a `java` or a `python` on PATH is the failure this prevents. teeup never deletes `~/.sdkman`, `~/.rbenv` or `~/.pyenv`: those hold installed toolchains a user may still want, and the shell lines are what make them win.

**Files:**
- Modify: `lib/migrate.sh` (append after `migrate_legacy_paths`)
- Modify: `tests/lib/migrate.sh`

**Interfaces:**
- Consumes: `TEEUP_MIGRATE_RC_FILES` (`lib/migrate.sh`, Task 2); `disable_matching_lines` (`lib/files.sh`, Task 1); `log warn` (`lib/core.sh`).
- Produces:
  - `migrate_runtime_pattern <sdkman|rbenv|pyenv>` — prints that manager's awk ERE; returns 1 for any other name.
  - `migrate_disable_runtime_inits` — neutralises all three across every file in `TEEUP_MIGRATE_RC_FILES`, then names the directories it deliberately did not delete. Always 0.

**External facts (verified 2026-09-13):** SDKMAN's installer appends `export SDKMAN_DIR="$HOME/.sdkman"` and `[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"` — both single lines, both covered. `legacy/teeup.sh:2188` wrote the same thing as a three-line `if` block, which Task 1's block-opener rule handles. rbenv's documented line is `eval "$(rbenv init - zsh)"`; pyenv's are `export PYENV_ROOT="$HOME/.pyenv"`, a `[[ -d $PYENV_ROOT/bin ]] && export PATH=…` line, and `eval "$(pyenv init - zsh)"` plus `eval "$(pyenv virtualenv-init -)"`. The patterns below are the ones `legacy/teeup.sh:1064` and `:2229` used, with `\.sdkman` and `\.rbenv` added for the PATH lines.

**Real-Mac risk:** only a machine that actually ran SDKMAN can show whether its rc block still has the shape its installer writes today; a hand-edited one may need the by-hand follow-up the warning names.

- [ ] **Step 1: Write the failing tests**

Add these four tests to `tests/lib/migrate.sh`, immediately above the `echo "lib/migrate.sh"` line:

```bash edit-old=tests/lib/migrate.sh
echo "lib/migrate.sh"
```
```bash edit-new=tests/lib/migrate.sh
test_migrate_disable_runtime_inits_covers_all_three_in_every_rc_file() {
  setup
  no_chezmoi
  printf '%s\n' \
    'export SDKMAN_DIR="$HOME/.sdkman"' \
    '[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"' \
    'eval "$(rbenv init - zsh)"' > "$TEST_HOME/.zshrc"
  printf '%s\n' \
    'export PYENV_ROOT="$HOME/.pyenv"' \
    'eval "$(pyenv init - bash)"' \
    'export KEEP=1' > "$TEST_HOME/.bashrc"
  migrate_disable_runtime_inits >/dev/null 2>&1 || return 1
  local zshrc bashrc
  zshrc="$(cat "$TEST_HOME/.zshrc")"
  bashrc="$(cat "$TEST_HOME/.bashrc")"
  assert_contains "$zshrc" ': # Disabled by teeup (sdkman replaced by mise): export SDKMAN_DIR="$HOME/.sdkman"' || return 1
  assert_contains "$zshrc" ': # Disabled by teeup (sdkman replaced by mise): [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"' || return 1
  assert_contains "$zshrc" ': # Disabled by teeup (rbenv replaced by mise): eval "$(rbenv init - zsh)"' || return 1
  assert_contains "$bashrc" ': # Disabled by teeup (pyenv replaced by mise): export PYENV_ROOT="$HOME/.pyenv"' || return 1
  assert_contains "$bashrc" ': # Disabled by teeup (pyenv replaced by mise): eval "$(pyenv init - bash)"' || return 1
  assert_contains "$bashrc" "export KEEP=1" || return 1
  bash -n "$TEST_HOME/.bashrc" || { echo ".bashrc no longer parses"; return 1; }
  cleanup_test_env
}

test_migrate_disable_runtime_inits_keeps_a_line_that_only_looks_like_pyenv() {
  setup
  no_chezmoi
  printf '%s\n' 'alias mypyenv="echo hi"' 'export SDKMANAGER_HOME=/opt/sdkmanager' > "$TEST_HOME/.zshrc"
  migrate_disable_runtime_inits >/dev/null 2>&1 || return 1
  assert_equals 'alias mypyenv="echo hi"
export SDKMANAGER_HOME=/opt/sdkmanager' "$(cat "$TEST_HOME/.zshrc")" || return 1
  cleanup_test_env
}

# shellcheck disable=SC2088  # the warning prints a literal ~; nothing here
# expands it as a path.
test_migrate_disable_runtime_inits_names_what_it_will_not_delete() {
  setup
  no_chezmoi
  mkdir -p "$TEST_HOME/.sdkman" "$TEST_HOME/.pyenv"
  local out
  out="$(migrate_disable_runtime_inits 2>&1)" || return 1
  assert_contains "$out" "~/.sdkman" || return 1
  assert_contains "$out" "~/.pyenv" || return 1
  assert_not_contains "$out" "~/.rbenv" "a directory that is not there is not named" || return 1
  assert_dir_exists "$TEST_HOME/.sdkman" "teeup never deletes an installed toolchain" || return 1
  cleanup_test_env
}

test_migrate_disable_runtime_inits_dry_run_changes_nothing() {
  setup
  no_chezmoi
  printf 'eval "$(rbenv init - zsh)"\n' > "$TEST_HOME/.zshrc"
  local out
  out="$(DRY_RUN=true migrate_disable_runtime_inits 2>&1)" || return 1
  assert_contains "$out" "[DRY-RUN] Would disable matching lines in $TEST_HOME/.zshrc: rbenv replaced by mise" || return 1
  assert_equals 'eval "$(rbenv init - zsh)"' "$(cat "$TEST_HOME/.zshrc")" || return 1
  cleanup_test_env
}

echo "lib/migrate.sh"
```

And their `run_test` lines, immediately above `print_summary`:

```bash edit-old=tests/lib/migrate.sh
run_test "migrate_legacy_paths dry run changes nothing" test_migrate_legacy_paths_dry_run_changes_nothing
print_summary
```
```bash edit-new=tests/lib/migrate.sh
run_test "migrate_legacy_paths dry run changes nothing" test_migrate_legacy_paths_dry_run_changes_nothing
run_test "runtime inits are disabled in every rc file" test_migrate_disable_runtime_inits_covers_all_three_in_every_rc_file
run_test "a line that only looks like pyenv survives" test_migrate_disable_runtime_inits_keeps_a_line_that_only_looks_like_pyenv
run_test "runtime inits name what is not deleted" test_migrate_disable_runtime_inits_names_what_it_will_not_delete
run_test "runtime inits dry run changes nothing" test_migrate_disable_runtime_inits_dry_run_changes_nothing
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/lib/migrate.sh`
Expected: the four new tests fail with `migrate_disable_runtime_inits: command not found`; the suite ends with `Summary: 16/20 passed`.

- [ ] **Step 3: Append the step to `lib/migrate.sh`**

```bash edit-old=lib/migrate.sh
  for name in $TEEUP_MIGRATE_RC_FILES; do
    disable_matching_lines "$HOME/$name" "$TEEUP_MIGRATE_LEGACY_RC_PATTERN" "replaced by teeup's zsh layer"
    disable_matching_lines "$HOME/$name" "$TEEUP_MIGRATE_PROMPT_RC_PATTERN" "replaced by teeup's starship prompt"
  done
  return $rc
}
```
```bash edit-new=lib/migrate.sh
  for name in $TEEUP_MIGRATE_RC_FILES; do
    disable_matching_lines "$HOME/$name" "$TEEUP_MIGRATE_LEGACY_RC_PATTERN" "replaced by teeup's zsh layer"
    disable_matching_lines "$HOME/$name" "$TEEUP_MIGRATE_PROMPT_RC_PATTERN" "replaced by teeup's starship prompt"
  done
  return $rc
}

# migrate_runtime_pattern <sdkman|rbenv|pyenv> -> that manager's awk ERE
# Deliberately narrow. The bare name would match a comment, an unrelated PATH
# entry or a variable that merely contains it, and a pattern that is too wide
# comments out lines the user still needs. These are the patterns
# legacy/teeup.sh used, plus the dot-directory each manager puts on PATH.
migrate_runtime_pattern() {
  case "$1" in
    sdkman) printf '%s\n' 'sdkman-init\.sh|SDKMAN_DIR|\.sdkman' ;;
    rbenv)  printf '%s\n' 'rbenv (init|shell)|RBENV_ROOT|\.rbenv' ;;
    pyenv)  printf '%s\n' 'pyenv (init|virtualenv-init)|PYENV_ROOT|\.pyenv' ;;
    *) return 1 ;;
  esac
}

# migrate_disable_runtime_inits
# mise owns every runtime from phase 3b on, and two managers each putting a
# java or a python on PATH is the failure this prevents. The toolchains stay:
# ~/.sdkman, ~/.rbenv and ~/.pyenv hold installed versions a user may still
# want, and it is the shell lines, not the directories, that make them win.
# Always 0: nothing here can be refused.
migrate_disable_runtime_inits() {
  local manager name dir leftover=""
  log "Disabling the runtime managers mise replaces (SDKMAN, rbenv, pyenv)"
  for manager in sdkman rbenv pyenv; do
    for name in $TEEUP_MIGRATE_RC_FILES; do
      disable_matching_lines "$HOME/$name" "$(migrate_runtime_pattern "$manager")" "$manager replaced by mise"
    done
  done
  for dir in .sdkman .rbenv .pyenv; do
    if [[ -d "$HOME/$dir" ]]; then
      leftover="$leftover ~/$dir"
    fi
  done
  if [[ -n "$leftover" ]]; then
    warn "Still on disk:$leftover. teeup does not delete an installed toolchain; remove them yourself once a new shell works."
  fi
  return 0
}
```

- [ ] **Step 4: Run the suite for this file**

Run: `bash tests/lib/migrate.sh`
Expected: `Summary: 20/20 passed`.

- [ ] **Step 5: Run the whole suite and the checks**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning lib/migrate.sh tests/lib/migrate.sh && git diff --check`
Expected: the same suite count as the task before this one; everything else silent.

- [ ] **Step 6: Commit**

```bash
git add lib/migrate.sh tests/lib/migrate.sh
git commit -m "Disable the SDKMAN, rbenv and pyenv shell init lines"
```

---

### Task 5: `migrate_chezmoi` — detect, list, back up, and ask only about `~/.config/chezmoi`

> **Rulings folded in (Revision 2).**
> **T5.1 (Blocking) — ask before the bulk move, and split what teeup will restore from what
> it will not.** List the managed entries in two groups — ones teeup ships a config for (it
> will reinstall them) and ones it does not (`~/.tmux.conf`, `~/.local/bin/*.sh`, anything
> else) — then ask one `ui_confirm … no` before moving anything. In a non-interactive run,
> move nothing and print what a real run would do. Without this, the first real run on the
> user's work Mac renames ~20 files they wrote, their own `~/.local/bin` scripts included,
> with no prompt and nothing to put them back but a hand search for `*.teeup_backup_*`.
> **T5.2 (Blocking) — `ok_unless_dry` for "Moved N …", and count only real moves.**
> `backup_target` returns the prospective path and 0 under `DRY_RUN`, so counting its
> return makes the preview claim it moved the user's home aside.
> **T5.3 — tell a refusal apart from a failed backup.** `migrate_backup` returns 1 for
> "refused" and 2 for "`backup_target` failed"; the closing message names which happened.
> Conflating them sends the user looking for a safety refusal while the file that failed to
> move sits there uninvestigated.

Spec section 10: "detects a chezmoi-managed home, prints the list from `chezmoi managed`, backs those files up with `backup_target`, and asks before deleting only `~/.config/chezmoi` (the config that points chezmoi at its source). It never runs `chezmoi purge`, which would delete the source directory, and never touches `~/Work/environment/dotfiles`, which keeps serving Linux."

Moving a managed file aside rather than deleting it is what lets teeup take over: `copy_config_once` installs teeup's own version into the gap it leaves, and the backup is right there to copy personal lines out of.

**Files:**
- Modify: `lib/migrate.sh` (append after `migrate_disable_runtime_inits`)
- Modify: `tests/lib/migrate.sh`

**Interfaces:**
- Consumes: `migrate_resolve`, `migrate_path_is_safe`, `migrate_chezmoi_source`, `chezmoi_ro`, `migrate_target`, `migrate_rm` (`lib/migrate.sh`, Task 2); `backup_target` (`lib/files.sh`); `ui_confirm` (`lib/ui.sh`); `have log ok warn` (`lib/core.sh`).
- Produces:
  - `migrate_backup <absolute-path>` — `backup_target` behind the same two gates as `migrate_rm`. Prints the backup path on success, prints nothing when there was nothing to move, returns 1 when it refused.
  - `migrate_chezmoi` — the whole chezmoi half of the migration. 0 when everything it tried succeeded, 1 when something was refused or the listing failed.

**External facts (verified 2026-09-13 against the chezmoi reference):** `chezmoi managed` "lists all managed entries in the destination directory"; `--path-style` accepts `absolute`, `relative` (the default), `source-absolute`, `source-relative` and `all`; `--include` selects entry types, e.g. `--include=files,symlinks`. `chezmoi source-path` with no target "prints the source directory". `chezmoi purge` "removes chezmoi's configuration, state, and source directory" — which is why `chezmoi_ro` does not list it. chezmoi reads its configuration from `$HOME/.config/chezmoi/chezmoi.$FORMAT`, with `$FORMAT` one of `json`, `jsonc`, `toml` or `yaml`, so the whole `~/.config/chezmoi` directory is the thing to ask about.

**Real-Mac risk:** everything here runs against a mocked `chezmoi`. What only a real machine proves is the shape of `chezmoi managed --path-style=absolute --include=files,symlinks` on the user's actual source state (how many entries, whether any path falls outside `$HOME` through a `destDir` setting), and whether moving `~/.zshrc` aside while a chezmoi-managed `~/.zshenv` still sources it leaves a shell that starts. Note also that `migrate_path_is_safe` runs `chezmoi source-path` once per managed file rather than caching it — deliberate, so a single stale value can never widen what the gate allows, but on a home with hundreds of managed entries it is hundreds of subprocesses. If that is slow enough to notice on hardware, cache it in one variable set before the loop and passed in, not in a module-level global that a later call could read after the config changed.

- [ ] **Step 1: Write the failing tests**

Add these six tests to `tests/lib/migrate.sh`, immediately above the `echo "lib/migrate.sh"` line:

```bash edit-old=tests/lib/migrate.sh
echo "lib/migrate.sh"
```
```bash edit-new=tests/lib/migrate.sh
# Write $1... as the list a mocked `chezmoi managed` prints.
set_managed() {
  export TEEUP_TEST_CHEZMOI_MANAGED="$TEST_HOME/managed.list"
  printf '%s\n' "$@" > "$TEEUP_TEST_CHEZMOI_MANAGED"
}

test_migrate_chezmoi_does_nothing_without_chezmoi() {
  setup
  no_chezmoi
  local out
  out="$(migrate_chezmoi 2>&1)" || return 1
  assert_contains "$out" "No chezmoi on this machine" || return 1
  cleanup_test_env
}

test_migrate_chezmoi_lists_and_backs_up_every_managed_file() {
  setup
  mock_chezmoi
  mkdir -p "$TEST_HOME/od d \$x & 'q'/wezterm"
  printf 'old zshrc\n' > "$TEST_HOME/.zshrc"
  printf 'old wezterm\n' > "$TEST_HOME/od d \$x & 'q'/wezterm/wezterm.lua"
  set_managed "$TEST_HOME/.zshrc" "$TEST_HOME/od d \$x & 'q'/wezterm/wezterm.lua" "$TEST_HOME/.never-existed"
  local out
  out="$(printf 'n\n' | migrate_chezmoi 2>&1)" || return 1
  assert_contains "$out" "chezmoi manages these files" || return 1
  assert_contains "$out" "$TEST_HOME/.zshrc" || return 1
  if [[ -e "$TEST_HOME/.zshrc" ]]; then echo "the managed file was not moved aside"; return 1; fi
  assert_equals "1" "$(find "$TEST_HOME" -maxdepth 1 -name '.zshrc.teeup_backup_*' | wc -l | tr -d ' ')" || return 1
  assert_equals "1" "$(find "$TEST_HOME/od d \$x & 'q'/wezterm" -name 'wezterm.lua.teeup_backup_*' | wc -l | tr -d ' ')" "a managed path with spaces and metacharacters is one entry, not several" || return 1
  assert_contains "$out" "Moved 2 chezmoi-managed file" "a path that does not exist is not counted" || return 1
  cleanup_test_env
}

test_migrate_chezmoi_never_touches_the_source_directory() {
  setup
  mock_chezmoi
  printf 'old zshrc\n' > "$TEST_HOME/.zshrc"
  # chezmoi would never list a path inside its own source directory; the gate
  # is here for the case where it somehow does.
  set_managed "$TEST_HOME/.zshrc" "$SIBLING/dot_zshrc"
  local rc=0 out
  out="$(printf 'n\n' | migrate_chezmoi 2>&1)" || rc=$?
  assert_failure "$rc" "refusing one entry must show in the exit status" || return 1
  assert_contains "$out" "Refusing to back up $SIBLING/dot_zshrc" || return 1
  assert_equals "sibling" "$(cat "$SIBLING/dot_zshrc")" "the checkout that serves Linux is untouched" || return 1
  assert_dir_exists "$SIBLING" || return 1
  local calls
  calls="$(cat "$MOCK_LOG")"
  assert_not_contains "$calls" "chezmoi purge" || return 1
  assert_not_contains "$calls" "chezmoi apply" || return 1
  assert_not_contains "$calls" "chezmoi destroy" || return 1
  assert_contains "$calls" "chezmoi managed" || return 1
  cleanup_test_env
}

test_migrate_chezmoi_keeps_the_config_directory_on_no() {
  setup
  mock_chezmoi
  set_managed
  mkdir -p "$XDG_CONFIG_HOME/chezmoi"
  printf 'sourceDir = "%s"\n' "$SIBLING" > "$XDG_CONFIG_HOME/chezmoi/chezmoi.toml"
  local out
  out="$(printf 'n\n' | migrate_chezmoi 2>&1)" || return 1
  assert_contains "$out" "Delete $XDG_CONFIG_HOME/chezmoi" || return 1
  assert_dir_exists "$XDG_CONFIG_HOME/chezmoi" || return 1
  # Answering nothing at all is the same as no.
  out="$(printf '\n' | migrate_chezmoi 2>&1)" || return 1
  assert_dir_exists "$XDG_CONFIG_HOME/chezmoi" "an empty answer must default to keeping it" || return 1
  cleanup_test_env
}

test_migrate_chezmoi_deletes_only_the_config_directory_on_yes() {
  setup
  mock_chezmoi
  set_managed
  mkdir -p "$XDG_CONFIG_HOME/chezmoi"
  printf 'sourceDir = "%s"\n' "$SIBLING" > "$XDG_CONFIG_HOME/chezmoi/chezmoi.toml"
  printf 'y\n' | migrate_chezmoi >/dev/null 2>&1 || return 1
  if [[ -d "$XDG_CONFIG_HOME/chezmoi" ]]; then echo "the config directory is still there"; return 1; fi
  assert_dir_exists "$SIBLING" "only the config goes; the source directory stays" || return 1
  assert_equals "sibling" "$(cat "$SIBLING/dot_zshrc")" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "chezmoi purge" || return 1
  cleanup_test_env
}

test_migrate_chezmoi_dry_run_changes_nothing() {
  setup
  mock_chezmoi
  printf 'old zshrc\n' > "$TEST_HOME/.zshrc"
  set_managed "$TEST_HOME/.zshrc"
  mkdir -p "$XDG_CONFIG_HOME/chezmoi"
  local out
  out="$(printf 'y\n' | DRY_RUN=true migrate_chezmoi 2>&1)" || return 1
  assert_contains "$out" "[DRY-RUN] Would back up $TEST_HOME/.zshrc" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: rm -rf $XDG_CONFIG_HOME/chezmoi" || return 1
  assert_file_exists "$TEST_HOME/.zshrc" || return 1
  assert_dir_exists "$XDG_CONFIG_HOME/chezmoi" || return 1
  cleanup_test_env
}

echo "lib/migrate.sh"
```

And their `run_test` lines, immediately above `print_summary`:

```bash edit-old=tests/lib/migrate.sh
run_test "runtime inits dry run changes nothing" test_migrate_disable_runtime_inits_dry_run_changes_nothing
print_summary
```
```bash edit-new=tests/lib/migrate.sh
run_test "runtime inits dry run changes nothing" test_migrate_disable_runtime_inits_dry_run_changes_nothing
run_test "migrate_chezmoi does nothing without chezmoi" test_migrate_chezmoi_does_nothing_without_chezmoi
run_test "migrate_chezmoi lists and backs up managed files" test_migrate_chezmoi_lists_and_backs_up_every_managed_file
run_test "migrate_chezmoi never touches the source directory" test_migrate_chezmoi_never_touches_the_source_directory
run_test "migrate_chezmoi keeps the config on no" test_migrate_chezmoi_keeps_the_config_directory_on_no
run_test "migrate_chezmoi deletes only the config on yes" test_migrate_chezmoi_deletes_only_the_config_directory_on_yes
run_test "migrate_chezmoi dry run changes nothing" test_migrate_chezmoi_dry_run_changes_nothing
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/lib/migrate.sh`
Expected: the six new tests fail with `migrate_chezmoi: command not found`; the suite ends with `Summary: 20/26 passed`.

- [ ] **Step 3: Append the step to `lib/migrate.sh`**

```bash edit-old=lib/migrate.sh
  if [[ -n "$leftover" ]]; then
    warn "Still on disk:$leftover. teeup does not delete an installed toolchain; remove them yourself once a new shell works."
  fi
  return 0
}
```
```bash edit-new=lib/migrate.sh
  if [[ -n "$leftover" ]]; then
    warn "Still on disk:$leftover. teeup does not delete an installed toolchain; remove them yourself once a new shell works."
  fi
  return 0
}

# migrate_backup <absolute-path>
# backup_target behind the same two gates migrate_rm uses. Every path reaching
# this comes from `chezmoi managed`, which lists entries in the destination
# directory, so the gates should never fire; they are here because a chezmoi
# config with an unusual destDir would otherwise let the migration rename a
# file outside $HOME. Prints the backup path when it moved something, prints
# nothing when there was nothing there, returns 1 when it refused.
migrate_backup() {
  local path="$1" resolved
  if ! resolved="$(migrate_resolve "$path")"; then
    return 0
  fi
  if ! migrate_path_is_safe "$resolved"; then
    warn "Refusing to back up $path: it resolves to $resolved, which teeup's migration must not touch."
    return 1
  fi
  if [[ ! -e "$resolved" && ! -L "$resolved" ]]; then
    return 0
  fi
  if [[ -d "$resolved" && ! -L "$resolved" ]]; then
    log "Leaving the directory $resolved in place; only files are moved aside."
    return 0
  fi
  backup_target "$resolved"
}

# migrate_chezmoi
# The chezmoi half of spec section 10. Managed files are MOVED ASIDE, not
# deleted: copy_config_once then installs teeup's own version into the gap,
# and the .teeup_backup_<ts> copy is right there to lift personal lines out
# of. The source directory is never deleted, never purged, never written to -
# it is ~/Work/environment/dotfiles on this user's machines and it still
# serves Linux. The one thing this can delete is ~/.config/chezmoi, the config
# that points chezmoi at that source, and only after asking; the default is
# no, so a non-interactive run (teeup update, a hook) keeps it.
# 0 when everything it tried succeeded, 1 when something was refused.
migrate_chezmoi() {
  local src managed line backup count=0 rc=0 chezmoi_config
  if ! have chezmoi; then
    log "No chezmoi on this machine; nothing to take over."
    return 0
  fi
  src="$(migrate_chezmoi_source)"
  if [[ -z "$src" ]]; then
    log "chezmoi is installed but reports no source directory here; nothing to take over."
    return 0
  fi
  log "chezmoi manages this home from $src"
  log "That checkout still serves Linux, so teeup never deletes it, never runs 'chezmoi purge', and never writes to it."
  managed="$(mktemp)"
  if ! chezmoi_ro managed --path-style=absolute --include=files,symlinks > "$managed" 2>/dev/null; then
    warn "Could not list what chezmoi manages, so nothing was moved. Run 'chezmoi managed' yourself to see why."
    rm -f "$managed"
    return 1
  fi
  echo "chezmoi manages these files in your home directory:"
  sed 's/^/  /' "$managed"
  # Line by line, never word by word: a managed path can contain spaces.
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" ]]; then
      continue
    fi
    if backup="$(migrate_backup "$line")"; then
      if [[ -n "$backup" ]]; then
        count=$((count + 1))
      fi
    else
      rc=1
    fi
  done < "$managed"
  rm -f "$managed"
  ok "Moved $count chezmoi-managed file(s) aside. Run 'teeup update' and teeup reinstalls the ones it owns."
  chezmoi_config="$(migrate_target chezmoi-config)"
  if [[ ! -e "$chezmoi_config" ]]; then
    log "No $chezmoi_config, so chezmoi already has nothing pointing it at this home."
    return $rc
  fi
  if ui_confirm "Delete $chezmoi_config, so chezmoi stops pointing at $src? The checkout itself stays." no; then
    if ! migrate_rm chezmoi-config; then
      rc=1
    fi
  else
    log "Keeping $chezmoi_config. Running 'chezmoi apply' again will put its files back over teeup's."
  fi
  return $rc
}
```

- [ ] **Step 4: Run the suite for this file**

Run: `bash tests/lib/migrate.sh`
Expected: `Summary: 26/26 passed`.

- [ ] **Step 5: Run the whole suite and the checks**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning lib/migrate.sh tests/lib/migrate.sh && git diff --check`
Expected: the same suite count as the task before this one; everything else silent.

- [ ] **Step 6: Commit**

```bash
git add lib/migrate.sh tests/lib/migrate.sh
git commit -m "Take a chezmoi-managed home over without touching its source"
```

---

### Task 6: `teeup migrate legacy` — the verb, the menu row and the end-to-end refusal proofs

> **Rulings folded in (Revision 2).**
> **T6.1 (Blocking) — drop the menu row and `dev check` for now.** `share/teeup/menu.json`
> and `teeup dev check` do not exist on `main` (4b tasks 6 and 9 are unwritten), so **skip
> Step 4 and the `dev check` half of Step 5**, and close with a command that exists:
> `teeup update`, then `teeup status`. A migration that ends by naming a verb `bin/teeup`
> rejects with "Unknown verb" undoes the trust the command is for.
> **T6.2 — do not leave the machine without a shell.** Before moving rc files aside, check
> `state_done check cap-zsh`; when zsh has not been configured here, say so and either run
> `teeup install zsh` first or refuse the chezmoi half with instructions. Otherwise a user
> who migrates before installing teeup's zsh layer opens a new terminal with no `.zshrc`,
> `.zshenv` or `.zprofile` at all.

The three steps become one command. The verb takes a target so that a future migration off something else needs no new verb, and today `legacy` is the only one.

**Files:**
- Modify: `bin/teeup` (usage, `cmd_migrate`, dispatch)
- Modify: `share/teeup/menu.json`
- Modify: `tests/cli.sh`

**Interfaces:**
- Consumes: `migrate_legacy_paths` (Task 3), `migrate_disable_runtime_inits` (Task 4), `migrate_chezmoi` (Task 5); `ok err die` (`lib/core.sh`).
- Produces: `cmd_migrate [<target>]` in `bin/teeup`, reached as `teeup migrate legacy`. Exit 0 when nothing was refused, 1 otherwise. A `setup.migrate` row in `share/teeup/menu.json`.

**Real-Mac risk:** the whole command has only ever run against mocks. On a real machine the order matters in a way no test shows: `migrate_legacy_paths` neutralises rc lines that `migrate_chezmoi` may then move aside wholesale, so the surviving `.teeup_backup_<ts>` copies are the record of what the machine used to do. Only a real migration shows whether the shell that comes up afterwards is usable, which is why the last line points the user at a follow-up command — `teeup update` today, `teeup doctor` once #32 has merged (T6.1).

- [ ] **Step 1: Write the failing tests**

Add these five tests to `tests/cli.sh`, immediately above the `echo "bin/teeup"` line:

```bash edit-old=tests/cli.sh
echo "bin/teeup"
```
```bash edit-new=tests/cli.sh
# A chezmoi that manages $TEST_HOME/.zshrc out of a stand-in for the sibling
# repo, created inside the throwaway HOME. Every call lands in $MOCK_LOG.
setup_legacy_home() {
  export TEEUP_NO_GUM=1
  SIBLING="$TEST_HOME/Work/environment/dotfiles"
  mkdir -p "$SIBLING"
  printf 'sibling\n' > "$SIBLING/dot_zshrc"
  export TEEUP_TEST_CHEZMOI_SRC="$SIBLING"
  export TEEUP_TEST_CHEZMOI_MANAGED="$TEST_HOME/managed.list"
  printf '%s\n' "$TEST_HOME/.zshrc" > "$TEEUP_TEST_CHEZMOI_MANAGED"
  mock_command_script chezmoi <<'EOF2'
case "$1" in
  source-path) printf '%s\n' "$TEEUP_TEST_CHEZMOI_SRC" ;;
  managed) cat "$TEEUP_TEST_CHEZMOI_MANAGED" ;;
  --version) echo "chezmoi version v2.66.0" ;;
  *) echo "mock chezmoi: unexpected subcommand $1" >&2; exit 1 ;;
esac
EOF2
  printf 'legacy\n' > "$TEST_HOME/.teeup.common"
  mkdir -p "$TEST_HOME/.config/mac-setup"
  printf '%s\n' 'source "$HOME/.teeup.common"' 'eval "$(rbenv init - zsh)"' 'export KEEP=1' > "$TEST_HOME/.zshrc"
  mkdir -p "$TEST_HOME/.config/chezmoi"
}

test_migrate_legacy_cleans_a_legacy_home() {
  setup
  setup_legacy_home
  local out rc=0
  out="$(printf 'y\n' | "$TEEUP" migrate legacy 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  if [[ -e "$TEST_HOME/.teeup.common" ]]; then echo ".teeup.common survived"; return 1; fi
  if [[ -d "$TEST_HOME/.config/mac-setup" ]]; then echo "mac-setup survived"; return 1; fi
  if [[ -d "$TEST_HOME/.config/chezmoi" ]]; then echo "the chezmoi config survived a yes"; return 1; fi
  if [[ -e "$TEST_HOME/.zshrc" ]]; then echo ".zshrc was not moved aside"; return 1; fi
  # .zshrc is backed up three times in this run - by the legacy-pattern
  # disable, the rbenv disable, and the final chezmoi move - and every backup
  # in this run is named <file>.teeup_backup_<ts> to the second. _backup_name
  # (plan 4a, lib/files.sh) is what keeps the three distinct instead of the
  # later writes silently overwriting the first.
  local backups
  backups="$(find "$TEST_HOME" -maxdepth 1 -name '.zshrc.teeup_backup_*' | wc -l | tr -d ' ')"
  assert_equals "3" "$backups" "every backup of .zshrc this run made must survive" || return 1
  assert_contains "$out" "Migration finished" || return 1
  cleanup_test_env
}

test_migrate_legacy_leaves_the_sibling_checkout_and_writes_no_chezmoi_state() {
  setup
  setup_legacy_home
  printf 'y\n' | "$TEEUP" migrate legacy >/dev/null 2>&1 || return 1
  assert_dir_exists "$SIBLING" "the checkout that still serves Linux must survive" || return 1
  assert_equals "sibling" "$(cat "$SIBLING/dot_zshrc")" || return 1
  local calls
  calls="$(cat "$MOCK_LOG")"
  assert_not_contains "$calls" "chezmoi purge" || return 1
  assert_not_contains "$calls" "chezmoi apply" || return 1
  assert_not_contains "$calls" "chezmoi destroy" || return 1
  assert_not_contains "$calls" "chezmoi forget" || return 1
  assert_contains "$calls" "chezmoi managed" "it still reads the list" || return 1
  cleanup_test_env
}

test_migrate_legacy_refuses_an_unknown_target() {
  setup
  local rc=0 out
  out="$("$TEEUP" migrate dotfiles 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Unknown migration target 'dotfiles'" || return 1
  rc=0
  out="$("$TEEUP" migrate 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Usage: teeup migrate legacy" || return 1
  cleanup_test_env
}

test_migrate_legacy_reports_a_refusal_through_its_exit_status() {
  setup
  setup_legacy_home
  # ~/.config lives inside the checkout, so mac-setup and the chezmoi config
  # both resolve somewhere teeup must not touch.
  rm -rf "$TEST_HOME/.config"
  mkdir -p "$SIBLING/dot_config/mac-setup" "$SIBLING/dot_config/chezmoi"
  ln -s "$SIBLING/dot_config" "$TEST_HOME/.config"
  local rc=0 out
  out="$(printf 'y\n' | "$TEEUP" migrate legacy 2>&1)" || rc=$?
  assert_failure "$rc" "a refusal must reach the exit status" || return 1
  assert_contains "$out" "Refusing to remove" || return 1
  assert_contains "$out" "teeup refused to touch something" || return 1
  assert_dir_exists "$SIBLING/dot_config/mac-setup" || return 1
  assert_dir_exists "$SIBLING/dot_config/chezmoi" || return 1
  cleanup_test_env
}

test_migrate_legacy_dry_run_changes_nothing() {
  setup
  setup_legacy_home
  local out
  out="$(printf 'y\n' | DRY_RUN=true "$TEEUP" migrate legacy 2>&1)" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: rm -f $TEST_HOME/.teeup.common" || return 1
  assert_contains "$out" "[DRY-RUN] Would back up $TEST_HOME/.zshrc" || return 1
  assert_file_exists "$TEST_HOME/.teeup.common" || return 1
  assert_dir_exists "$TEST_HOME/.config/mac-setup" || return 1
  assert_dir_exists "$TEST_HOME/.config/chezmoi" || return 1
  assert_contains "$(cat "$TEST_HOME/.zshrc")" 'eval "$(rbenv init - zsh)"' || return 1
  cleanup_test_env
}

echo "bin/teeup"
```

And their `run_test` lines, immediately above `print_summary`:

```bash edit-old=tests/cli.sh
print_summary
```
```bash edit-new=tests/cli.sh
run_test "migrate legacy cleans a legacy home" test_migrate_legacy_cleans_a_legacy_home
run_test "migrate legacy leaves the sibling checkout" test_migrate_legacy_leaves_the_sibling_checkout_and_writes_no_chezmoi_state
run_test "migrate refuses an unknown target" test_migrate_legacy_refuses_an_unknown_target
run_test "migrate legacy reports a refusal" test_migrate_legacy_reports_a_refusal_through_its_exit_status
run_test "migrate legacy dry run changes nothing" test_migrate_legacy_dry_run_changes_nothing
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/cli.sh`
Expected: the five new tests fail with `Unknown verb: migrate`; the suite ends with five fewer passes than tests.

- [ ] **Step 3: Add the verb to `bin/teeup`**

The usage line, above `teeup version`:

```bash edit-old=bin/teeup
  teeup version
  teeup help
USAGE
```
```bash edit-new=bin/teeup
  teeup migrate legacy           retire the old teeup and chezmoi wiring on this Mac
  teeup version
  teeup help
USAGE
```

The function, immediately above the dispatch block:

```bash edit-old=bin/teeup
verb="${1:-help}"
[[ $# -gt 0 ]] && shift
```
```bash edit-new=bin/teeup
# `teeup migrate <target>` retires one of this teeup's predecessors on a
# machine that already had it (spec section 10). It takes a target rather than
# doing one fixed thing, so a later migration off something else needs no new
# verb; `legacy` is the only one today.
#
# Each step returns 1 when it REFUSED something rather than when it failed:
# the migration always runs to the end, and the exit status says whether
# anything was left alone. Nothing is ever lost - every removal is of a file
# teeup itself generated, and every foreign file is moved to a
# .teeup_backup_<ts> copy beside it.
cmd_migrate() {
  local target="${1:-}" rc=0
  case "$target" in
    legacy) ;;
    "") die "Usage: teeup migrate legacy" ;;
    *) die "Unknown migration target '$target'. The only one is: legacy" ;;
  esac
  migrate_legacy_paths || rc=1
  migrate_disable_runtime_inits || rc=1
  migrate_chezmoi || rc=1
  echo ""
  if [[ $rc -eq 0 ]]; then
    ok "Migration finished. Open a new terminal, then run: teeup update"
  else
    err "Migration finished, but teeup refused to touch something above. Nothing was lost; read the warnings, then run: teeup status"
  fi
  return $rc
}

verb="${1:-help}"
[[ $# -gt 0 ]] && shift
```

The dispatch arm:

```bash edit-old=bin/teeup
  version) cat "$TEEUP_PATH/version" 2>/dev/null || echo dev ;;
```
```bash edit-new=bin/teeup
  migrate) cmd_migrate "$@" ;;
  version) cat "$TEEUP_PATH/version" 2>/dev/null || echo dev ;;
```

- [ ] **Step 4: Add the menu row**

`setup` is already a declared parent, so the row needs no new group. Put it last in that group, because it is the one entry there that changes the machine rather than reading it.

```bash edit-old=share/teeup/menu.json
  "setup.reset": {"label": "Reset a capability's config", "when": "teeup help | grep -q '^  teeup reset'", "action": "teeup reset $(teeup list | awk '{print $1}' | head -1)"}
```
```bash edit-new=share/teeup/menu.json
  "setup.reset": {"label": "Reset a capability's config", "when": "teeup help | grep -q '^  teeup reset'", "action": "teeup reset $(teeup list | awk '{print $1}' | head -1)"},
  "setup.migrate": {"label": "Retire the old teeup and chezmoi wiring", "action": "teeup migrate legacy"}
```

- [ ] **Step 5: Run the CLI suite and the menu lint**

Run: `bash tests/cli.sh && ./bin/teeup dev check`
Expected: the CLI suite ends with every test passing, and `teeup dev check` reports the menu and the metadata clean.

- [ ] **Step 6: Run the whole suite and the checks**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning bin/teeup tests/cli.sh && git diff --check`
Expected: the same suite count as the task before this one; everything else silent.

- [ ] **Step 7: Commit**

```bash
git add bin/teeup share/teeup/menu.json tests/cli.sh
git commit -m "Add the teeup migrate legacy verb"
```

---

### Task 7: The doctor leftover checks

> **BLOCKED until PR #32 merges (Revision 2, A1/T7.1).** `lib/doctor.sh`,
> `capabilities/zsh/doctor` and `capabilities/git/doctor` do not exist on `main`. Do not
> invent a doctor framework inside 5a; 4b would immediately contradict it. **If #32 has not
> merged, skip this task** and record the five checks (Oh My Zsh, p10k files, a live
> predecessor rc line, a chezmoi source still pointing here, git's `[user]` block) as a note
> for whoever lands the rest of 4b.
>
> **When #32 has merged, three corrections apply before writing it:**
> **T7.2 — fix the git wording.** teeup has **one** git identity now ("One identity, full
> stop", `capabilities/git/configure`), so the finding must say the `[user]` block outranks
> *the identity teeup wrote*, not "teeup's per-directory identities". Printing a claim about
> a model teeup deliberately removed is exactly the untrue message that has bitten this
> project on real machines.
> **T7.3 — re-anchor both test insertions.** `tests/capabilities/git.sh` has
> `run_test "configure writes the one identity" …`, not "writes both identities", and
> `tests/capabilities/zsh.sh` has no "doctor reports a home file that lost the layer" line
> at all. Insert above the first `run_test` in each file instead. Note that `print_summary`
> fails a suite for any `test_*` function without a `run_test` line, so a mis-anchored
> insertion is not silent — but it is also not what you meant.
> **T7.4 — #32 renamed the contract.** It ships `doctor_ok`/`doctor_warn`/`doctor_fail`/
> `doctor_unknown` and `doctor_summary`, with exit codes 0 verified / 1 problems / 2 could
> not check. There is no `doctor_verdict`. A check that cannot verify a leftover reports
> `doctor_unknown`, not `doctor_ok`.

Spec section 10: "`teeup doctor` flags leftovers: a `[user]` block in `~/.gitconfig.local`, p10k remnants, Oh My Zsh directory, a chezmoi source dir still pointing at the Linux repo." Phase 4b owns the doctor framework, and its contract is that checks live inside a capability's own `doctor` script and report through `doctor_ok`/`doctor_warn`/`doctor_fail`. Three of the four belong to `zsh` (they are all about what a shell loads before teeup's layer does) and one to `git`.

**Files:**
- Modify: `capabilities/zsh/doctor`
- Modify: `capabilities/git/doctor`
- Modify: `tests/capabilities/zsh.sh`
- Modify: `tests/capabilities/git.sh`

**Interfaces:**
- Consumes: `doctor_ok doctor_warn doctor_fail` (`lib/doctor.sh`, phase 4b Task 1); `chezmoi_ro` (`lib/migrate.sh`, Task 2); `have user_config_dir` (`lib/core.sh`); `$zsh_home_dir` and `$git_dir`, both already set at the top of the two scripts by phase 4b.
- Produces: four new findings, each with a fix command that really fixes it. Nothing else changes.

**Why a neutralised line stops counting.** After `teeup migrate legacy`, a disabled line reads `: # Disabled by teeup (…): <original>` and a block opener whose body is dead is left as it was. Neither runs anything, so the rc check filters out comments, teeup-neutralised lines and bare block openers before it looks for a leftover. Without that filter the doctor would keep failing on a machine that has already been migrated, and the fix command it prints would be a lie.

**Real-Mac risk:** `dscl`, `grep -E` and the `~/.oh-my-zsh` and `~/.p10k.zsh` locations are all mocked or synthesised here. What a real Mac proves is whether the user's machine actually holds p10k under one of the three names checked — Homebrew's `powerlevel10k` formula installs the theme under `$(brew --prefix)/share/powerlevel10k` and leaves only `~/.p10k.zsh` in the home directory, which is the one that matters.

- [ ] **Step 1: Write the failing tests**

Add these three tests to `tests/capabilities/zsh.sh`, immediately above the `echo "capabilities/zsh"` line:

```bash edit-old=tests/capabilities/zsh.sh
echo "capabilities/zsh"
```
```bash edit-new=tests/capabilities/zsh.sh
test_doctor_flags_oh_my_zsh_p10k_files_and_a_live_rc_line() {
  setup
  export TEEUP_TEST_MISSING="chezmoi"
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/zsh"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  mkdir -p "$TEST_HOME/.oh-my-zsh"
  printf '# p10k\n' > "$TEST_HOME/.p10k.zsh"
  printf 'source "$HOME/.p10k.zsh"\n' >> "$TEST_HOME/.zshrc"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$TEST_HOME/.oh-my-zsh is still on disk" || return 1
  assert_contains "$out" "Powerlevel10k files are still here" || return 1
  assert_contains "$out" "still load something teeup replaced" || return 1
  assert_contains "$(cat "$report")" "teeup migrate legacy" || return 1
  cleanup_test_env
}

test_doctor_stops_flagging_leftovers_once_migrate_has_neutralised_them() {
  setup
  export TEEUP_NO_GUM=1
  # No chezmoi here: this test is about the shell leftovers, and a host
  # chezmoi on the runner would drag its own source directory in.
  export TEEUP_TEST_MISSING="chezmoi"
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/zsh"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  printf '%s\n' 'source "$HOME/.teeup.common"' 'source "$HOME/.p10k.zsh"' >> "$TEST_HOME/.zshrc"
  DRY_RUN=false "$TEEUP" migrate legacy >/dev/null 2>&1 || return 1
  local rc=0 out
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_success "$rc" "a migrated home must come up clean" || return 1
  assert_contains "$out" "No Oh My Zsh directory." || return 1
  assert_contains "$out" "No Powerlevel10k files." || return 1
  assert_contains "$out" "No shell file loads a predecessor of teeup." || return 1
  cleanup_test_env
}

test_doctor_flags_a_chezmoi_source_directory_that_still_points_here() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command dscl 0 "UserShell: /bin/zsh"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  local sibling="$TEST_HOME/Work/environment/dotfiles"
  mkdir -p "$sibling" "$TEST_HOME/.config/chezmoi"
  export TEEUP_TEST_CHEZMOI_SRC="$sibling"
  mock_command_script chezmoi <<'EOF2'
case "$1" in
  source-path) printf '%s\n' "$TEEUP_TEST_CHEZMOI_SRC" ;;
  *) echo "mock chezmoi: unexpected subcommand $1" >&2; exit 1 ;;
esac
EOF2
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run zsh doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "chezmoi still points at $sibling" || return 1
  assert_contains "$(cat "$report")" "teeup migrate legacy" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "chezmoi purge" || return 1
  assert_dir_exists "$sibling" "a doctor script never changes anything" || return 1
  cleanup_test_env
}

echo "capabilities/zsh"
```

And their `run_test` lines, immediately above `print_summary`:

```bash edit-old=tests/capabilities/zsh.sh
run_test "doctor reports a home file that lost the layer" test_doctor_reports_a_home_file_that_lost_the_teeup_layer
print_summary
```
```bash edit-new=tests/capabilities/zsh.sh
run_test "doctor reports a home file that lost the layer" test_doctor_reports_a_home_file_that_lost_the_teeup_layer
run_test "doctor flags Oh My Zsh, p10k files and a live rc line" test_doctor_flags_oh_my_zsh_p10k_files_and_a_live_rc_line
run_test "doctor is clean once migrate has run" test_doctor_stops_flagging_leftovers_once_migrate_has_neutralised_them
run_test "doctor flags a chezmoi source directory" test_doctor_flags_a_chezmoi_source_directory_that_still_points_here
print_summary
```

Add these two tests to `tests/capabilities/git.sh`, immediately above its `print_summary` block's `run_test` lines — that is, right before the line `run_test "configure writes both identities" test_configure_writes_both_identities`:

```bash edit-old=tests/capabilities/git.sh
run_test "configure writes both identities" test_configure_writes_both_identities
```
```bash edit-new=tests/capabilities/git.sh
test_doctor_flags_a_user_block_in_gitconfig_local_that_is_still_included() {
  setup
  seed_answers
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  printf '[user]\n\tname = Someone Else\n\temail = old@example.com\n' > "$TEST_HOME/.gitconfig.local"
  printf '[include]\n\tpath = ~/.gitconfig.local\n' > "$TEST_HOME/.gitconfig"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "has a [user] block and is still included" || return 1
  assert_contains "$(cat "$report")" "--remove-section user" || return 1
  cleanup_test_env
}

test_doctor_only_notes_a_gitconfig_local_that_nothing_includes() {
  setup
  seed_answers
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  printf '[user]\n\tname = Someone Else\n' > "$TEST_HOME/.gitconfig.local"
  local out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run git doctor 2>&1)" || true
  assert_contains "$out" "but nothing includes it any more" || return 1
  assert_not_contains "$(cat "$report")" "--remove-section user" "a file nothing reads is a note, not a failure" || return 1
  cleanup_test_env
}

run_test "doctor flags an included [user] block" test_doctor_flags_a_user_block_in_gitconfig_local_that_is_still_included
run_test "doctor only notes an unused gitconfig.local" test_doctor_only_notes_a_gitconfig_local_that_nothing_includes
run_test "configure writes both identities" test_configure_writes_both_identities
```

- [ ] **Step 2: Run them to see them fail**

Run: `bash tests/capabilities/zsh.sh; bash tests/capabilities/git.sh`
Expected: the three zsh tests fail (the doctor says nothing about Oh My Zsh, p10k or chezmoi) and the two git tests fail (nothing mentions `.gitconfig.local`).

- [ ] **Step 3: Add the three checks to `capabilities/zsh/doctor`**

```bash edit-old=capabilities/zsh/doctor
fi

doctor_verdict
```
```bash edit-new=capabilities/zsh/doctor
fi

# Leftovers from what teeup replaced (spec section 10). None of these breaks a
# shell on its own; each quietly outranks or duplicates teeup's layer, and the
# only way to notice is to be told.

# A line counts as a leftover only when it would still run something. A
# comment, a line `teeup migrate legacy` neutralised with ": #", and a bare
# block opener whose body is dead are all inert, so a migrated machine reads
# as clean instead of failing for ever on text it can no longer act on.
rc_still_loads_a_predecessor() {
  grep -vE '^[[:space:]]*(#|:[[:space:]]#)' "$1" |
    grep -vE '([[:space:];]|^)(then|do|in)[[:space:]]*$' |
    grep -qE 'powerlevel10k|p10k|POWERLEVEL9K_|oh-my-zsh|ohmyzsh|ZSH_THEME|antigen|teeup\.common|teeupshrc|shellrc\.common|mac-setup'
}

omz_dir="$HOME/.oh-my-zsh"
if [[ -d "$omz_dir" ]]; then
  doctor_fail "$omz_dir is still on disk. Oh My Zsh redefines prompts, aliases and completions on top of teeup's layer." "rm -rf $omz_dir"
else
  doctor_ok "No Oh My Zsh directory."
fi

# ZDOTDIR defaults to $HOME, so the same file can be named twice; the case
# below keeps the list and the rm it prints free of duplicates.
p10k_files=""
for f in "$HOME/.p10k.zsh" "$zsh_home_dir/.p10k.zsh" "$HOME/.powerlevel10k"; do
  if [[ -e "$f" ]]; then
    case " $p10k_files " in
      *" $f "*) continue ;;
    esac
    p10k_files="$p10k_files $f"
  fi
done
if [[ -n "$p10k_files" ]]; then
  doctor_fail "Powerlevel10k files are still here:$p10k_files. teeup's prompt is starship, and p10k's instant prompt takes over the start of every shell." "rm -rf$p10k_files"
else
  doctor_ok "No Powerlevel10k files."
fi

stale_rc=""
for f in .zshenv .zprofile .zshrc; do
  if [[ -f "$zsh_home_dir/$f" ]] && rc_still_loads_a_predecessor "$zsh_home_dir/$f"; then
    stale_rc="$stale_rc $zsh_home_dir/$f"
  fi
done
if [[ -n "$stale_rc" ]]; then
  doctor_fail "These still load something teeup replaced:$stale_rc" "teeup migrate legacy"
else
  doctor_ok "No shell file loads a predecessor of teeup."
fi

# The source directory itself is never teeup's business: it is
# ~/Work/environment/dotfiles, it still serves Linux, and nothing here touches
# it. The config that points chezmoi at it is the problem, because while it
# exists one `chezmoi apply` puts its files back over teeup's.
if [[ -d "$(user_config_dir)/chezmoi" ]] && have chezmoi; then
  chezmoi_src="$(chezmoi_ro source-path 2>/dev/null || true)"
  if [[ -n "$chezmoi_src" && -d "$chezmoi_src" ]]; then
    doctor_fail "chezmoi still points at $chezmoi_src, so one 'chezmoi apply' would put its files back over the ones teeup owns." "teeup migrate legacy"
  else
    doctor_ok "chezmoi is configured here but has no source directory."
  fi
else
  doctor_ok "chezmoi is not pointing at this home."
fi

doctor_verdict
```

- [ ] **Step 4: Add the check to `capabilities/git/doctor`**

It goes above the early exit for a git that was never configured: a leftover identity is worth saying either way.

```bash edit-old=capabilities/git/doctor
git_dir="$(user_config_dir)/git"

if [[ ! -f "$git_dir/config" ]]; then
```
```bash edit-new=capabilities/git/doctor
git_dir="$(user_config_dir)/git"

# A leftover from the chezmoi era (spec section 10). That gitconfig ended with
# `[include] path = ~/.gitconfig.local`, so a [user] block there outranks the
# per-directory identities teeup sets up - but only while something still
# includes it. Checked before the early exit below, because a stale identity
# matters whether or not teeup has configured git here yet.
gitconfig_local="$HOME/.gitconfig.local"
if [[ -f "$gitconfig_local" ]] && grep -qE '^[[:space:]]*\[user\]' "$gitconfig_local"; then
  gitconfig_local_included=false
  for f in "$HOME/.gitconfig" "$git_dir/config" "$git_dir/local"; do
    if [[ -f "$f" ]] && grep -qF '.gitconfig.local' "$f"; then
      gitconfig_local_included=true
    fi
  done
  if [[ "$gitconfig_local_included" == "true" ]]; then
    doctor_fail "$gitconfig_local has a [user] block and is still included, so its name and email win over teeup's per-directory identities." "git config --file $gitconfig_local --remove-section user"
  else
    doctor_warn "$gitconfig_local has a [user] block, but nothing includes it any more. Move anything you still want into $git_dir/local and delete it."
  fi
else
  doctor_ok "No leftover [user] block in $gitconfig_local."
fi

if [[ ! -f "$git_dir/config" ]]; then
```

- [ ] **Step 5: Run the two suites**

Run: `bash tests/capabilities/zsh.sh && bash tests/capabilities/git.sh`
Expected: both end with every test passing.

- [ ] **Step 6: Run the whole suite and the checks**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning capabilities/zsh/doctor capabilities/git/doctor tests/capabilities/zsh.sh tests/capabilities/git.sh && git diff --check`
Expected: the same suite count as the task before this one; everything else silent.

- [ ] **Step 7: Commit**

```bash
git add capabilities/zsh/doctor capabilities/git/doctor tests/capabilities/zsh.sh tests/capabilities/git.sh
git commit -m "Flag the migration leftovers in teeup doctor"
```

---

### Task 8: The remaining chezmoi content, and the migration that refreshes it

> **Rulings folded in (Revision 2).**
> **T8.1 — re-anchor the test insertions**, for the same reason as T7.3: both quoted
> anchors are lines Task 7 would have created, and Task 7 may not have run.
> **T8.2 — name the migration from `./bin/teeup dev add-migration`**, not from the epoch
> written in this plan, and make the Task-8 test use the same name. A hard-coded epoch
> either fails the test with "No migration named …" or ships a migration whose timestamp
> predates commits already in the tree.
> **T8.3 (keep) — keep the `cap_exists git` guard.** Several `teeup update` tests in
> `tests/cli.sh` do not override `TEEUP_MIGRATIONS_DIR` and run this migration against a
> fixture capability tree with no `git`, where `migration_refresh` errors.

Spec section 10's last bullet: "Content from the chezmoi repo worth porting into capability configs: `~/.config/shell/{envs,aliases,functions}`, `wezterm.lua` …, gitconfig aliases, the `javav` function."

Most of it is already here. `javav`, `zd`, the `ls`/`git`/Emacs/Finder aliases, the PATH helpers, the package-manager prefixes and the `EDITOR`/`VISUAL`/`SUDO_EDITOR` defaults all landed in phase 2a's `capabilities/zsh/default/{env,aliases,functions}`; twenty-four of the twenty-six gitconfig aliases landed in phase 2a's `capabilities/git/config/git/config`; `wezterm.lua` is phase 2b's `wezterm` capability, with its own themed template and the `~/.wezterm_local.lua` seam. **This task closes what is genuinely still missing**, which was found by reading `/home/systemhalted/Work/environment/dotfiles` (read-only) against the checkout:

| From the chezmoi repo | Where it goes | Why |
|---|---|---|
| `path_prepend "$HOME/.cargo/bin"` | `capabilities/zsh/default/env` | mise's rust backend installs rustup into `~/.rustup` and `~/.cargo`; nothing puts `~/.cargo/bin` on PATH, so `cargo install`ed binaries are invisible |
| `GOPATH` and `$GOPATH/bin` | `capabilities/zsh/default/env` | the repo pins `~/Development/GoWorkspace` rather than taking Go's `~/go` default |
| `SDKMAN_EL_DIR`, `TRUSTRAIL_EL_DIR`, `WORDWISE_EL_DIR` | `capabilities/zsh/default/env` | the Emacs configuration reads them to prefer a local checkout of the user's own packages |
| `alias cd..='cd ..'` | `capabilities/zsh/default/aliases` | the one alias from the repo with no equivalent here |
| `colima-start` / `colima-stop` | `capabilities/zsh/default/aliases` | the repo's Colima shortcuts; phase 3b ships the capability but no aliases |
| `lfs` and `llg` git aliases | `capabilities/git/config/git/config` | the two of twenty-six that phase 2a did not carry over |

**Deliberately not ported, with the reason:** `path_prepend "$HOME/.opencode/bin"` — phase 3b's `ai` capability delivers `opencode` as a mise wrapper in `~/.local/bin`, which is already on PATH, so the upstream installer's directory is not used here. The `[merge] tool = ediff` block and the `INSIDE_EMACS` `core.editor` one-liner — neither is an alias, and `teeup configure git` already picks the editor from what is installed and writes it into `~/.config/git/teeup-generated`; wiring a mergetool to an Emacs that a machine may not have belongs with that detection, not in the shipped file. The `showHiddenFiles`/`hideHiddenFiles` spellings — `showhidden`/`hidehidden` already do the same thing.

**Files:**
- Modify: `capabilities/zsh/default/env`
- Modify: `capabilities/zsh/default/aliases`
- Modify: `capabilities/git/config/git/config`
- Create: `migrations/<epoch>.sh`
- Modify: `tests/capabilities/zsh.sh`, `tests/capabilities/git.sh`

**Interfaces:**
- Consumes: `path_prepend`, `path_append` (`capabilities/zsh/default/env`); `migration_refresh` (`lib/migrations.sh`, phase 4a Task 4); `state_done mark`, `stock_record`, `file_sha` (in the test).
- Produces: no new function. `~/.config/git/config` is a copy-once file, so a machine that already has one needs the migration to pick the two aliases up; an edited copy is left alone, which is the stock-checksum rule doing its job.

**The one ordering trap:** `default/env` ends by appending mise's shims and then `$TEEUP_STATE_DIR/shims`, and the teeup shims **must stay the last PATH entry** — `capabilities/teeup-runtime/doctor` checks it and `tests/capabilities/zsh.sh`'s `default env appends the shims last` asserts it. `path_append "$GOPATH/bin"` therefore goes above that block, not below it.

**Migration naming:** `./bin/teeup dev add-migration` names the file from the checkout's last commit time and prints the path. `migrations/<epoch>.sh` below is that name for a checkout whose last commit is 2026-09-16; if `dev add-migration` prints a different epoch, use the name it printed — the body is the same either way, and `migrations/` holds nothing else, so any epoch sorts correctly.

**Real-Mac risk:** `~/Development/GoWorkspace` and the three Emacs package checkouts exist only on the user's own machines; the exports are inert everywhere else, and `path_append` skips a directory that is not there. Whether `cargo` really lands in `~/.cargo/bin` after `teeup install dev-env rust` is a mise-on-macOS fact no test here reaches.

- [ ] **Step 1: Write the failing tests**

Add these two tests to `tests/capabilities/zsh.sh`, immediately above the `echo "capabilities/zsh"` line:

```bash edit-old=tests/capabilities/zsh.sh
echo "capabilities/zsh"
```
```bash edit-new=tests/capabilities/zsh.sh
test_default_env_carries_the_chezmoi_path_and_emacs_variables() {
  setup
  require_zsh || return 1
  mkdir -p "$TEST_HOME/.local/bin" "$TEST_HOME/.cargo/bin" \
    "$TEST_HOME/Development/GoWorkspace/bin" \
    "$TEST_HOME/.local/state/teeup/shims" \
    "$TEST_HOME/Work/products/emacs-packages/sdkman.el" \
    "$TEST_HOME/Work/products/emacs-packages/wordwise.el"
  # The four variables are cleared first: a developer whose own shell exports
  # GOPATH or one of the Emacs package directories would otherwise see the
  # inherited value rather than the one default/env computes.
  local out
  out="$(env -u SDKMAN_EL_DIR -u TRUSTRAIL_EL_DIR -u WORDWISE_EL_DIR GOPATH= zsh -f -c ". '$TEEUP_PATH/capabilities/zsh/default/env'; printf '%s\n%s\n%s\n%s\n' \"\$PATH\" \"\$GOPATH\" \"\${SDKMAN_EL_DIR:-unset}\" \"\${TRUSTRAIL_EL_DIR:-unset}\"")"
  local path_line goenv sdkman trustrail
  path_line="$(printf '%s\n' "$out" | sed -n '1p')"
  goenv="$(printf '%s\n' "$out" | sed -n '2p')"
  sdkman="$(printf '%s\n' "$out" | sed -n '3p')"
  trustrail="$(printf '%s\n' "$out" | sed -n '4p')"
  assert_contains "$path_line" "$TEST_HOME/.cargo/bin" || return 1
  assert_contains "$path_line" "$TEST_HOME/Development/GoWorkspace/bin" || return 1
  assert_equals "$TEST_HOME/Development/GoWorkspace" "$goenv" || return 1
  assert_equals "$TEST_HOME/Work/products/emacs-packages/sdkman.el" "$sdkman" || return 1
  assert_equals "unset" "$trustrail" "a package directory that is not there stays unset" || return 1
  # The one thing the additions must not break.
  [[ "$path_line" == *"$TEST_HOME/.local/state/teeup/shims" ]] ||
    { echo "teeup shims must still be the last PATH entry, got: $path_line"; return 1; }
  cleanup_test_env
}

test_default_aliases_carry_the_last_chezmoi_shortcuts() {
  setup
  require_zsh || return 1
  mock_command colima 0 ""
  local out
  out="$(zsh -f -c ". '$TEEUP_PATH/capabilities/zsh/default/aliases'; alias")"
  assert_contains "$out" "cd..=" || return 1
  assert_contains "$out" "colima-start=" || return 1
  assert_contains "$out" "colima-stop=" || return 1
  cleanup_test_env
}

echo "capabilities/zsh"
```

And their `run_test` lines, immediately above `print_summary`:

```bash edit-old=tests/capabilities/zsh.sh
run_test "doctor flags a chezmoi source directory" test_doctor_flags_a_chezmoi_source_directory_that_still_points_here
print_summary
```
```bash edit-new=tests/capabilities/zsh.sh
run_test "doctor flags a chezmoi source directory" test_doctor_flags_a_chezmoi_source_directory_that_still_points_here
run_test "default env carries the chezmoi PATH and Emacs variables" test_default_env_carries_the_chezmoi_path_and_emacs_variables
run_test "default aliases carry the last chezmoi shortcuts" test_default_aliases_carry_the_last_chezmoi_shortcuts
print_summary
```

Add these two tests to `tests/capabilities/git.sh`, immediately above its first `run_test` line:

```bash edit-old=tests/capabilities/git.sh
run_test "doctor flags an included [user] block" test_doctor_flags_a_user_block_in_gitconfig_local_that_is_still_included
```
```bash edit-new=tests/capabilities/git.sh
test_configure_ships_the_last_two_chezmoi_aliases() {
  setup
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local body
  body="$(cat "$TEST_HOME/.config/git/config")"
  assert_contains "$body" "lfs = log --stat --oneline" || return 1
  assert_contains "$body" "llg = log --color --graph" || return 1
  cleanup_test_env
}

test_the_shipped_migration_refreshes_a_pristine_git_config() {
  setup
  seed_answers ""
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  state_done mark cap-git
  # A machine that installed git before this task: an older shipped file whose
  # stock record matches it, so it reads as pristine.
  printf '[alias]\n\ts = status\n' > "$TEST_HOME/.config/git/config"
  stock_record "$TEST_HOME/.config/git/config" "$(file_sha "$TEST_HOME/.config/git/config")"
  # T8.2: MIGRATION is the name ./bin/teeup dev add-migration produced in Step 4,
  # not a number pasted from the plan. Define it once at the top of the suite.
  DRY_RUN=false migration_run "$MIGRATION" >/dev/null 2>&1 || return 1
  assert_contains "$(cat "$TEST_HOME/.config/git/config")" "llg = log --color --graph" || return 1
  # An edited copy is left alone: that is the stock-checksum rule. The marker
  # lib/state.sh wrote goes first, so the migration is allowed to run again.
  printf '[alias]\n\tmine = status\n' > "$TEST_HOME/.config/git/config"
  rm -f "$TEEUP_STATE_DIR/migrations/$MIGRATION"
  DRY_RUN=false migration_run "$MIGRATION" >/dev/null 2>&1 || true
  assert_equals '[alias]
	mine = status' "$(cat "$TEST_HOME/.config/git/config")" || return 1
  cleanup_test_env
}

run_test "configure ships the last two chezmoi aliases" test_configure_ships_the_last_two_chezmoi_aliases
run_test "the shipped migration refreshes a pristine config" test_the_shipped_migration_refreshes_a_pristine_git_config
run_test "doctor flags an included [user] block" test_doctor_flags_a_user_block_in_gitconfig_local_that_is_still_included
```

- [ ] **Step 2: Run them to see them fail**

Run: `bash tests/capabilities/zsh.sh; bash tests/capabilities/git.sh`
Expected: the two zsh tests fail (no `.cargo/bin`, no `GOPATH`, no `cd..`), `configure ships the last two chezmoi aliases` fails on the missing `lfs`/`llg`, and `the shipped migration refreshes a pristine config` fails with `No migration named <epoch>.sh` — the name `./bin/teeup dev add-migration` will produce in Step 4, which the suite holds in `$MIGRATION` (T8.2).

- [ ] **Step 3: Add the PATH entries to `capabilities/zsh/default/env`**

```bash edit-old=capabilities/zsh/default/env
path_prepend "$HOME/.local/bin"
# mise's own shims let shells without `mise activate` find mise tools. mise
```
```bash edit-new=capabilities/zsh/default/env
# Cargo's own bin directory. mise's rust backend is rustup, which installs
# into ~/.rustup and ~/.cargo, and anything `cargo install` puts in
# ~/.cargo/bin is covered by no shim. Ported from the chezmoi repo's
# ~/.config/shell/envs; prepended before ~/.local/bin so that one still wins.
path_prepend "$HOME/.cargo/bin"
path_prepend "$HOME/.local/bin"

# Go's workspace, ported from the same file: it pins a location rather than
# taking Go's own ~/go default. path_append adds only a directory that exists,
# so a machine without Go gains the variable and nothing else. This has to
# stay ABOVE the two shims lines below - they are appended last on purpose,
# and the teeup shims must remain the final PATH entry (checked by
# capabilities/teeup-runtime/doctor).
export GOPATH="${GOPATH:-$HOME/Development/GoWorkspace}"
path_append "$GOPATH/bin"

# mise's own shims let shells without `mise activate` find mise tools. mise
```

- [ ] **Step 4: Add the Emacs package variables to the same file**

```bash edit-old=capabilities/zsh/default/env
export BAT_THEME="${BAT_THEME:-ansi}"
export LESS="${LESS:--R}"
if command -v bat >/dev/null 2>&1; then
  export MANROFFOPT="-c"
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi
```
```bash edit-new=capabilities/zsh/default/env
export BAT_THEME="${BAT_THEME:-ansi}"
export LESS="${LESS:--R}"
if command -v bat >/dev/null 2>&1; then
  export MANROFFOPT="-c"
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi

# Self-maintained Emacs packages, ported from the chezmoi repo's
# ~/.config/shell/envs: point the Emacs configuration at a local checkout when
# there is one. The checkout root differs per machine, and with none of them
# present every variable stays unset and the Emacs configuration installs the
# packages from GitHub instead.
for _teeup_pkg_dir in "$HOME/Work/products/emacs-packages" \
                      "$HOME/Workspaces/Palak/products/emacs-packages" \
                      "$HOME/Workspaces/Personal/products/emacs-packages"; do
  if [ -d "$_teeup_pkg_dir" ]; then
    [ -d "$_teeup_pkg_dir/sdkman.el" ] && export SDKMAN_EL_DIR="$_teeup_pkg_dir/sdkman.el"
    [ -d "$_teeup_pkg_dir/trustrail.el" ] && export TRUSTRAIL_EL_DIR="$_teeup_pkg_dir/trustrail.el"
    [ -d "$_teeup_pkg_dir/wordwise.el" ] && export WORDWISE_EL_DIR="$_teeup_pkg_dir/wordwise.el"
    break
  fi
done
unset _teeup_pkg_dir
```

- [ ] **Step 5: Add the two aliases**

```bash edit-old=capabilities/zsh/default/aliases
alias pse='ps -ef'
```
```bash edit-new=capabilities/zsh/default/aliases
alias pse='ps -ef'
alias cd..='cd ..'
```

```bash edit-old=capabilities/zsh/default/aliases
# macOS Finder toggles.
```
```bash edit-new=capabilities/zsh/default/aliases
# Colima, when it is there. teeup installs it lazily, so on a machine that has
# never run a container these two reach the shim, which installs it on first
# use. Ported from the chezmoi repo's ~/.config/shell/aliases.
if command -v colima >/dev/null 2>&1; then
  alias colima-start='colima start'
  alias colima-stop='colima stop'
fi

# macOS Finder toggles.
```

- [ ] **Step 6: Add the last two git aliases**

```bash edit-old=capabilities/git/config/git/config
	lfo = log --name-only --oneline
	lg = log --color --graph --pretty=format:'%C(bold white)%h%Creset -%C(bold green)%d%Creset %s %C(bold green)(%cr)%Creset %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative
	ll = log --oneline --graph --decorate
	ls-ignored = ls-files --others --exclude-from=.git/info/exclude
```
```bash edit-new=capabilities/git/config/git/config
	lfo = log --name-only --oneline
	lfs = log --stat --oneline
	lg = log --color --graph --pretty=format:'%C(bold white)%h%Creset -%C(bold green)%d%Creset %s %C(bold green)(%cr)%Creset %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative
	ll = log --oneline --graph --decorate
	llg = log --color --graph --pretty=format:'%C(bold white)%H %d%Creset%n%s%n%+b%C(bold blue)%an <%ae>%Creset %C(bold green)%cr (%ci)' --abbrev-commit
	ls-ignored = ls-files --others --exclude-from=.git/info/exclude
```

- [ ] **Step 7: Ship the migration**

`~/.config/git/config` is installed once and then belongs to the user, so a machine that already ran teeup would never see the two new aliases. That is what the stock-checksum rule and `migration_refresh` are for.

```bash file=migrations/<epoch>.sh
#!/usr/bin/env bash
# Phase 5a: the shipped ~/.config/git/config gained the `lfs` and `llg`
# aliases, the last two the chezmoi repo had that teeup did not (spec section
# 10). git's config is a copy-once file, so a machine that installed git
# before this needs a refresh to see them.
#
# migration_refresh re-runs `teeup configure git` with the stock-checksum rule
# in force: a copy the user never edited is replaced with the new shipped
# version, and an edited one is logged and left exactly as it is. There is
# nothing to patch in that case - two extra aliases are additive, and a user
# who wants them can copy the two lines out of
# capabilities/git/config/git/config.
#
# capabilities/zsh/default/{env,aliases} also changed in the same commit, but
# those are read straight out of the checkout on every shell start, so they
# need no migration.
#
# The cap_exists guard is not paranoia: a migration runs against whatever
# capability tree TEEUP_CAPS_DIR points at, and the `teeup update` tests
# (phase 4a) point it at a fixture tree with three made-up capabilities in it.
# Without the guard, migration_refresh errors on a capability that is not
# there, the migration exits non-zero, and every `teeup update` in those tests
# stops at this migration. A machine that has no git capability also has no
# ~/.config/git/config to refresh.
if cap_exists git; then
  migration_refresh git
else
  log "No git capability in this checkout; nothing to refresh."
fi
```

Make it executable is not required (`migration_run` sources it through `bash -eu -c`), and `migrations_list` only wants the `<epoch>.sh` name.

- [ ] **Step 8: Run the two suites**

Run: `bash tests/capabilities/zsh.sh && bash tests/capabilities/git.sh && bash tests/lib/migrations.sh`
Expected: all three end with every test passing.

- [ ] **Step 9: Run the whole suite and the checks**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning migrations/<epoch>.sh tests/capabilities/zsh.sh tests/capabilities/git.sh && git diff --check`
Expected: the same suite count as the task before this one; everything else silent.

- [ ] **Step 10: Commit**

```bash
git add capabilities/zsh/default/env capabilities/zsh/default/aliases capabilities/git/config/git/config migrations/<epoch>.sh tests/capabilities/zsh.sh tests/capabilities/git.sh
git commit -m "Port the last of the chezmoi shell and git content"
```

---

### Task 9: README and contributor documentation

> **Rulings folded in (Revision 2).**
> **T9.1 — both anchors are stale.** There is no `teeup config get` line in `README.md`
> (no `teeup config` verb exists), so add the `teeup migrate legacy` line under the existing
> command list where it actually is. `CONTRIBUTING.md`'s numbered list ends at **24**, so
> the new items are **25-28**, not 31-34. Renumbering by hand against this plan's old
> numbers would duplicate or skip items in a file other phases keep appending to.
> **T9.2 (Blocking) — the README section must not promise `teeup doctor`**, or the five
> findings it would print, until #32 merges. The README is the one page a user reads before
> trusting a command that deletes things; it may not document a verb the shipped CLI rejects.
> **T9.3 (keep) — leave the `teeup remove` bullet alone.** `tests/docs.sh` pins its
> capability names and counts, and `tests/docs.sh` derives those claims from the tree.

Documentation only. It is a task of its own because a reviewer can reject the wording without rejecting the code, and because `teeup migrate legacy` is the one command in teeup whose entire value is that a user trusts what it will and will not delete — that has to be written down where they will read it.

**Files:**
- Modify: `README.md`
- Modify: `CONTRIBUTING.md`

**Interfaces:** none. No code changes.

**Real-Mac risk:** none.

- [ ] **Step 1: Add the verb to the README's command list**

The `teeup config get` line this step used to anchor on does not exist (T9.1). The real
command list is the fenced block under `## New runtime (preview)` in `README.md`, whose
last line is the `dev-env` one. Anchor there:

```bash edit-old=README.md
teeup install dev-env go  # install a language runtime through mise
```
```bash edit-new=README.md
teeup install dev-env go  # install a language runtime through mise
teeup migrate legacy      # retire the old teeup and chezmoi wiring on this Mac
```

- [ ] **Step 2: Add the section**

It goes after the update/reset/remove/hooks block and before the old README begins.

````bash edit-old=README.md
  never run. A hook that fails prints a warning and nothing is aborted.

This repository contains `teeup.sh`, a cross-platform developer setup script. It configures your workspace and installs essential tooling so you can get straight to work.
````
````bash edit-new=README.md
  never run. A hook that fails prints a warning and nothing is aborted.

### Migrating a Mac that already had teeup or chezmoi

```bash
DRY_RUN=true teeup migrate legacy   # read what it would do first
teeup migrate legacy
teeup status                        # what is installed afterwards
```

(T9.2: `teeup doctor` is named here only once PR #32 has merged. Until then the README
may not point at a verb `bin/teeup` rejects. When #32 lands, the third line becomes
`teeup doctor   # what is left, and how to finish it` and the paragraph on the five
findings can be added with it.)

`teeup migrate legacy` retires the two things this teeup replaced. It removes
`~/.teeup.common`, `~/.config/mac-setup` and the `~/.teeupshrc` and
`~/.shellrc.common` symlinks the old `teeup.sh` created, and it neutralises
the shell lines that loaded them, along with the SDKMAN, rbenv and pyenv init
lines that mise now replaces. A neutralised line is rewritten in place as
`: # Disabled by teeup (<reason>): <the original line>`, so nothing is lost
and the file still parses; every file it edits is copied to
`<file>.teeup_backup_<ts>` first.

If chezmoi is managing your home, it prints `chezmoi managed`, moves each of
those files aside with the same `.teeup_backup_<ts>` suffix so teeup can
install its own, and then asks one question: whether to delete
`~/.config/chezmoi`, the config that points chezmoi at its source. The default
is no.

**What it will not do.** It never deletes, purges or writes to the chezmoi
source directory — on these machines that is `~/Work/environment/dotfiles`,
which still serves Linux. That is enforced rather than promised: everything
the migration can delete is named by a key from a five-entry list in
`lib/migrate.sh`, so no path can be handed to it; the path that key resolves
to is then checked to be inside `$HOME` and clear of whatever
`chezmoi source-path` reports; and every chezmoi call in teeup goes through
`chezmoi_ro`, which runs `managed`, `source-path` and `--version` and dies on
anything else, `purge` included. It also never deletes `~/.sdkman`,
`~/.rbenv` or `~/.pyenv`: those hold toolchains you may still want, and it is
the shell lines, not the directories, that made them win.

The command exits non-zero when it **refused** something rather than when it
failed, and says what it left alone. `teeup doctor` then reports the leftovers
it cannot fix on its own: an `~/.oh-my-zsh` directory, Powerlevel10k files, a
shell file that still loads a predecessor, a chezmoi source directory still
pointing here, and a `[user]` block in `~/.gitconfig.local` that outranks
teeup's per-directory identities.

This repository contains `teeup.sh`, a cross-platform developer setup script. It configures your workspace and installs essential tooling so you can get straight to work.
````

- [ ] **Step 3: Add the contributor items**

Append after the last numbered item in `CONTRIBUTING.md` (item 30, which phase 4c wrote; do not renumber anything above).

```bash edit-old=CONTRIBUTING.md
30. A test that drives a prompt or a picker must `export TEEUP_NO_GUM=1`.
    `lib/ui.sh` uses `gum` whenever `TEEUP_NO_GUM` is empty and `gum` is on
    `PATH`, and the harness `PATH` keeps `/usr/bin`, so on a machine with
    gum installed there the test would drive a full-screen prompt instead of
    the plain fallback that reads stdin.
```
```bash edit-new=CONTRIBUTING.md
30. A test that drives a prompt or a picker must `export TEEUP_NO_GUM=1`.
    `lib/ui.sh` uses `gum` whenever `TEEUP_NO_GUM` is empty and `gum` is on
    `PATH`, and the harness `PATH` keeps `/usr/bin`, so on a machine with
    gum installed there the test would drive a full-screen prompt instead of
    the plain fallback that reads stdin.
25. Nothing in `teeup migrate legacy` deletes a path it was given. Every
    deletion goes through `migrate_rm <key>`, and the keys are the five-entry
    `case` in `migrate_target` — adding something to delete means adding a
    key there and a test for it, never passing a path. The resolved path is
    checked again by `migrate_path_is_safe` (inside `$HOME`, and clear of the
    chezmoi source directory and everything above and below it), because an
    `XDG_CONFIG_HOME` override or a symlinked `~/.config` can still make a
    key land somewhere it must not.
26. `chezmoi` is only ever run through `chezmoi_ro`, which accepts `managed`,
    `source-path` and `--version` and `die`s on anything else. `chezmoi purge`
    removes chezmoi's source directory, which is the sibling repo that still
    serves Linux, so it must stay unreachable — including from a capability's
    `doctor` script, which sources the same libraries.
27. A test in this area may never name a path outside `$TEST_HOME`. The
    stand-in for the sibling checkout is a `Work/environment/dotfiles`
    directory the test creates inside the throwaway `$HOME`, and `chezmoi` and
    `git` are mocked. A destructive code path needs a test for the refusal,
    not only for the success.
28. Use `disable_matching_lines` rather than editing a shell file by hand. It
    rewrites a matching line as `: # Disabled by teeup (<reason>): <line>` —
    the `:` matters, because an `if … ; then` whose whole body is commented
    out is a syntax error — leaves a line that *opens* a block alone and
    reports it, backs the file up through `backup_copy`, and is idempotent.
    Pass its pattern and reason through `ENVIRON`, never `awk -v`: awk expands
    escape sequences in a `-v` assignment, so `\.pyenv` would arrive as
    `.pyenv` and match `mypyenv` too.
```

- [ ] **Step 4: Check the documentation against the code**

Run: `./tests/run.sh && ./bin/teeup commands --check && git diff --check`
Expected: the same suite count as the task before this one; everything else silent. Then read the new README section next to `bin/teeup`'s `usage()` output and confirm every command it names exists:

Run: `./bin/teeup help | grep migrate`
Expected: `  teeup migrate legacy           retire the old teeup and chezmoi wiring on this Mac`

- [ ] **Step 5: Commit**

```bash
git add README.md CONTRIBUTING.md
git commit -m "Document teeup migrate legacy and its safety rules"
```

---

## Verification

Run on the finished branch, in order.

1. **The whole suite, twice.** `./tests/run.sh` and then `TEEUP_TEST_JOBS=1 ./tests/run.sh`. Both end `All N suites passed.`, where N is the count before this plan plus one (`tests/lib/migrate.sh`). The serial run matters here: `tests/capabilities/zsh.sh` and `tests/cli.sh` both scaffold a legacy home and run the migration, and a difference between the two runs would mean one of them is touching shared state.
2. **The metadata, the menu and the linter.** `./bin/teeup commands --check` silent and 0; `./bin/teeup dev check` reports the metadata, the menu, shellcheck and every suite clean — that is what proves the new `setup.migrate` row parses and has a declared parent.
3. **shellcheck.** `shellcheck --severity=warning lib/migrate.sh lib/files.sh lib/all.sh bin/teeup capabilities/zsh/doctor capabilities/git/doctor migrations/*.sh tests/lib/migrate.sh tests/lib/files.sh tests/cli.sh tests/capabilities/zsh.sh tests/capabilities/git.sh` — silent.
4. **bash 3.2.** Run the whole suite with a bash 3.2 driver on PATH. Everything must pass: `lib/migrate.sh` uses `case`, `printf`, `dirname`/`basename` and `cd … && pwd -P` and nothing newer, and `disable_matching_lines` is awk.
5. **The refusal, by hand.** In a throwaway HOME, with a directory standing in for the sibling repo and a `chezmoi` mock that names it:

```bash
teeup migrate legacy            # with ~/.config symlinked into the stand-in
echo "exit: $?"                 # 1
```

Expected: `Refusing to remove …` for `~/.config/mac-setup` and `~/.config/chezmoi`, `Migration finished, but teeup refused to touch something above`, exit 1, and the stand-in directory byte-identical afterwards.

6. **`chezmoi purge` is unreachable.** `grep -rn 'chezmoi' lib/ bin/ capabilities/ --include='*' | grep -v chezmoi_ro | grep -v '^.*#'` returns only the `chezmoi "$@"` line inside `chezmoi_ro` itself and the `have chezmoi` guards. Then, in a shell with `lib/all.sh` sourced, `chezmoi_ro purge` prints `teeup only runs read-only chezmoi subcommands` and exits 1.
7. **The doctor closes the loop — only once PR #32 has merged and Task 7 has run.** On the throwaway HOME above, without the symlink: `teeup migrate legacy` then `teeup doctor zsh` and `teeup doctor git` both exit 0 — that is the spec's "teeup doctor must exit 0 afterward" for section 10's leftovers. Note #32's exit codes: 0 is verified healthy, 1 problems, 2 could not check, so "not 1" is not good enough here. When Task 7 is skipped, this step is skipped with it and the leftovers stay on 4b's list.
8. **`DRY_RUN` is faithful.** `DRY_RUN=true teeup migrate legacy` in a legacy-shaped HOME, then `git status` on nothing and a `find $HOME -newer` that lists no file: the preview must create, delete and rename nothing, including backups.

---

## Self-review

### Spec coverage

Section 10 is the whole of this plan's mandate. Bullet by bullet:

| Spec section 10 | Task |
|---|---|
| "Every user-facing file teeup writes goes through `copy_config_once` … backed up … a diff of the backup is printed" | already true on `main` (`lib/files.sh`); nothing to add |
| `teeup migrate legacy` "removes `~/.teeup.common`, `~/.config/mac-setup`, dangling legacy symlinks" | 2 (`migrate_rm`), 3 (`migrate_legacy_paths`) |
| "disables SDKMAN, rbenv, pyenv init lines (reusing `disable_matching_lines`)" | 1 (the port), 4 (`migrate_disable_runtime_inits`) |
| "detects a chezmoi-managed home, prints the list from `chezmoi managed`" | 5 |
| "backs those files up with `backup_target`" | 5 (`migrate_backup`) |
| "asks before deleting only `~/.config/chezmoi`" | 5, default no |
| "It never runs `chezmoi purge`" | 2 (`chezmoi_ro`), proved by a unit test and by asserting `$MOCK_LOG` in Tasks 5 and 6 |
| "never touches `~/Work/environment/dotfiles`" | 2 (the closed key list and `migrate_path_is_safe`), proved by four refusal tests |
| "`teeup doctor` flags … a `[user]` block in `~/.gitconfig.local`" | 7 (`capabilities/git/doctor`) |
| "… p10k remnants, Oh My Zsh directory" | 7 (`capabilities/zsh/doctor`) |
| "… a chezmoi source dir still pointing at the Linux repo" | 7 (`capabilities/zsh/doctor`) |
| "Content from the chezmoi repo worth porting: `~/.config/shell/{envs,aliases,functions}` … gitconfig aliases, the `javav` function" | 8; `javav`, the aliases and most of the gitconfig were already ported in phase 2a, and Task 8 names what was left and what is deliberately not taken |
| "… `wezterm.lua` (minus the work Jira hyperlink rule, which moves to `~/.wezterm_local.lua`)" | phase 2b's `wezterm` capability, which already ships the template and the `~/.wezterm_local.lua` seam. Not re-done here; the phase 4/5 brief's 5a bullet lists only the shell files, the gitconfig aliases and `javav` |
| The verb itself, in the CLI surface | 6 |

Nothing in section 10 is unclaimed.

### Deferred items from earlier phases

The lists the brief names were read in full: the phase 1 final review's triage table, the phase 2a final review and re-review, `.superpowers/plan3/pr11-deferred.md`, and the "Deliberately deferred" sections of plans 3a, 3b, 4a, 4c and 4d.

**Taken here:** none of them, and that is the honest answer rather than an oversight. Every open entry is a runtime, library, `macos-defaults`, hook, editor, theme or menu item already claimed by 4a (Finder/Dock restart detection, the AeroSpace manual-step text, hooks for never-installed capabilities, the starship stock-sha rule and the symlink refusal, `teeup reset`/`teeup remove`), by 4b (`gpg.ssh.allowedSignersFile`, the shims-last PATH check, routing `capabilities/mise/configure` through `write_config_region`) or by 4c/4d (menu rows, `doctor` scripts for `karabiner` and `xcode`, themes for `k9s` and `lazydocker`).

**Left, with the reason:**

- **"Stale `shellcheck source=` in `legacy/teeup.sh`"** (phase 1 triage item 4, M13). The triage itself says the fix is phase 5 deleting `legacy/`, and the brief gives that deletion to **5b**. This plan reads `legacy/teeup.sh` and deletes nothing there.
- **"The silenced `backup_target` message" / "`__` collision in `_stock_record_path`" / "unreachable `backup_target` dry-run"** (phase 1 triage item 8, M8/M9). The ruling was "fix with the next `files.sh` touch", and phase 4a Task 3 is that touch — it adds `config_is_pristine`, `write_config_region`, `refresh_if_pristine` and `backup_copy` to the same file. Task 1 here appends one function and changes none of the existing ones; folding an unrelated behaviour change into it would make the migration commit harder to review, not easier.
- **"The teeup agent skill"** (phase 3b deferred). The brief gives it to 5b.
- **`~/.antigen`, `~/.oh-my-zsh`, `~/.p10k.zsh`, `~/.sdkman`, `~/.rbenv`, `~/.pyenv` deletion.** `teeup migrate legacy` neutralises the lines that load them and `teeup doctor` names the directories with the exact `rm` that removes each; the migration itself deletes only files teeup generated. Deleting a toolchain or a framework a user may still want is not something a migration should decide, and `legacy/teeup.sh` printed the same list as "optional cleanup after verifying a new shell works".

### Deliberately deferred by this plan

- **A migration that runs `teeup migrate legacy` automatically.** `migrations/<epoch>.sh` runs unattended inside `teeup update`, and this command asks a question and deletes things. It stays a verb the user types.
- **`teeup migrate` targets other than `legacy`.** The verb takes a target so a second one costs a `case` arm, but there is nothing else to migrate off today.
- **Rewriting the block-opening lines.** `disable_matching_lines` leaves `if … ; then` alone and reports it. Neutralising its body is enough to stop the init, and rewriting an opener (to `if false; then`, say) means editing shell the user wrote. The report names the file and the line number.
- **A `doctor` check for `~/.teeup.common` and `~/.config/mac-setup` themselves.** The `zsh` doctor's rc check fails while any shell file still loads them, which is the part that has an effect; a leftover file nothing sources is inert, and `teeup migrate legacy` removes it anyway.
- **The `[merge] tool = ediff` block and the `INSIDE_EMACS` `core.editor` one-liner from the chezmoi gitconfig.** Neither is an alias, and `teeup configure git` already writes the editor into `~/.config/git/teeup-generated` from what is actually installed. Wiring a mergetool belongs with that detection.
- **`path_prepend "$HOME/.opencode/bin"`.** Phase 3b's `ai` capability delivers `opencode` as a mise wrapper in `~/.local/bin`, which is already first on PATH.

### External facts verified

| Fact | How |
|---|---|
| `chezmoi managed` lists managed entries in the destination directory; `--path-style` takes `absolute`/`relative`/`source-absolute`/`source-relative`/`all`; `--include` takes entry types such as `files,symlinks` | chezmoi reference, `managed` (fetched 2026-09-13) |
| `chezmoi source-path` with no target prints the source directory | chezmoi reference, `source-path` |
| `chezmoi purge` "removes chezmoi's configuration, state, and source directory, but leave the target state intact" | chezmoi reference, `purge` — this is the reason `chezmoi_ro` exists |
| chezmoi's configuration lives at `$HOME/.config/chezmoi/chezmoi.$FORMAT`, `$FORMAT` one of `json`, `jsonc`, `toml`, `yaml` | chezmoi reference, configuration file |
| awk expands escape sequences in a `-v` assignment, so `-v p='\.pyenv'` matches `mypyenv`, while `ENVIRON["…"]` does not | run locally: `awk -v p='…\.pyenv'` warns `escape sequence '\.' treated as plain '.'` and matches `alias mypyenv=…`; the `ENVIRON` form matches only the `.pyenv` line |
| `: # comment` keeps an `if … ; then … fi` parsable | `bash -n`, `zsh -n` and the bash 3.2.0 build all accept `if [ -s "$HOME/x" ]; then` / `: # …` / `fi` |
| SDKMAN's installer writes `export SDKMAN_DIR="$HOME/.sdkman"` and a single-line `[[ -s … ]] && source …`; `legacy/teeup.sh:2188` wrote the same as a three-line `if` block | SDKMAN install documentation; `legacy/teeup.sh` read directly |
| The rbenv and pyenv init lines, and the patterns that match them | `legacy/teeup.sh:1064` and `:2229`, which this plan ports with `\.sdkman` and `\.rbenv` added |
| What is still missing from the chezmoi repo | `/home/systemhalted/Work/environment/dotfiles` read (read-only) and diffed by hand against `capabilities/zsh/default/{env,aliases,functions}` and `capabilities/git/config/git/config` in the transcription tree |
| Homebrew's `powerlevel10k` installs the theme under `$(brew --prefix)/share/powerlevel10k` and leaves `~/.p10k.zsh` in the home directory | Powerlevel10k README, Homebrew install section |

### Placeholder scan

Searched the plan for `TBD`, `TODO`, `implement later`, `fill in`, `appropriate error handling`, `handle edge cases`, `similar to Task`, `and so on`, `etc.` inside a code block, and for any test step without a code block. None found. Every test file, library function, doctor block, migration and documentation edit is given in full; every `edit-old` was copied from the transcription tree rather than typed.

### Name and type consistency

`migrate_target`, `chezmoi_ro`, `migrate_chezmoi_source`, `migrate_resolve`, `migrate_path_is_safe`, `migrate_rm`, `migrate_backup`, `migrate_legacy_paths`, `migrate_runtime_pattern`, `migrate_disable_runtime_inits`, `migrate_chezmoi`, `cmd_migrate`, `TEEUP_MIGRATE_RC_FILES`, `TEEUP_MIGRATE_LEGACY_RC_PATTERN`, `TEEUP_MIGRATE_PROMPT_RC_PATTERN` and `disable_matching_lines` are each defined once and spelled the same in every task, in the Contracts section, in the tests, in `CONTRIBUTING.md` and in the README. The five keys (`teeup-common`, `teeupshrc`, `shellrc-common`, `mac-setup`, `chezmoi-config`) appear only in `migrate_target`, in the callers and in the tests. The two rc patterns' union is exactly the alternation `capabilities/zsh/doctor` greps for, which is what makes the doctor go quiet after a migration; both sides say so in a comment.


### Mechanical verification (2026-09-16)

**The base (superseded — see Revision 2).** This whole section records a transcription run made on 2026-09-13 against a *simulated* base, and every count in it is stale: `main` now measures **49 suites** and `tests/lib/files.sh` **42 tests**. Read it as evidence that the plan's code applies cleanly, not as an expectation to check against. The base was `main` (at `c08dd63`, which already carries the parallel test runner, so nothing was cherry-picked) with the phase 3a, 3b, 4a, 4b, 4c and 4d plans applied in that order into `…/scratchpad/plan5a/base`. It reaches **60 suites**, `./tests/run.sh` green and `./bin/teeup commands --check` silent. Two hand reconciliations were needed to get there, both between plans this one consumes, neither in 5a's own text. **Both have since been fixed in the plans themselves** (cross-plan pass of 2026-09-16), so an executor applying 3a to 5b in order meets neither:

1. Phase 4b's three `lib/all.sh` edits anchored on the library list *without* 4a's `hooks migrations`, so each anchor was widened by those two names before applying. 4b's six blocks now carry `hooks migrations`.
2. Phase 4a and 4b each defined `cmd_dev` in `bin/teeup`; applied mechanically that left two definitions, the later one winning and `teeup dev new-capability` breaking. 4b's Task 8 Step 4 now edits 4a's function instead of redefining it, and Task 9 Step 4 anchors on the result.

**This plan.** Every task was applied in order to a clone of that base with a harness that, after each one, runs `./tests/run.sh`, `./bin/teeup commands --check`, `shellcheck --severity=warning` on every file the task touched and `git diff --check`, then commits. All nine tasks are green: **All 61 suites passed** after each (60 plus `tests/lib/migrate.sh`), `commands --check` silent and 0, shellcheck silent, `git diff --check` silent. The red states were observed too: `tests/lib/files.sh` went `20/28` then `28/28` at Task 1, and `tests/lib/migrate.sh` went `0/12`, `12/16`, `16/20`, `20/26` and finally `26/26` across Tasks 2 to 5.

Two defects in this plan's own text were found by that run and fixed:

- `TEEUP_MIGRATE_RC_FILES` is set in Task 2 but not read until Task 3, so shellcheck failed Task 2 with SC2034. It is now `export`ed, like `TEEUP_MIGRATIONS_DIR` and the rest of teeup's module variables.
- `migrations/<epoch>.sh` called `migration_refresh git` unconditionally, which broke two of phase 4a's `teeup update` tests: they point `TEEUP_CAPS_DIR` at a fixture tree with no `git` capability, so the migration exited non-zero and stopped the update. It is now guarded with `if cap_exists git`.

**Final state.** On the finished tree: `./tests/run.sh` **All 61 suites passed**; `TEEUP_TEST_JOBS=1 ./tests/run.sh` **All 61 suites passed**; the whole suite under the bash 3.2.0 build at `…/scratchpad/bash32build/bash-3.2/bash` **All 61 suites passed**; `shellcheck --severity=warning` over `lib/migrate.sh lib/files.sh lib/all.sh bin/teeup capabilities/zsh/doctor capabilities/git/doctor migrations/*.sh` and the five test files, silent; `./bin/teeup commands --check`, silent and 0; `git diff --check`, silent; `./bin/teeup dev check`, `teeup dev check: everything passed`. Applying the plan a second time to a fresh copy of the base produces a tree byte-identical to the transcribed one.

**The refusal, run by hand.** In a throwaway `$HOME` with `~/.config` symlinked into a stand-in for the sibling checkout and a mocked `chezmoi`:

```
✅ Removed the legacy file …/home/.teeup.common
🔹 Nothing at …/home/.teeupshrc.
⚠️ Refusing to remove …/home/.config/mac-setup: it resolves to
   …/home/Work/environment/dotfiles/dot_config/mac-setup, which teeup's
   migration must not touch.
✅ Copied …/home/.zshrc to …/home/.zshrc.teeup_backup_20260916181426
✅ Moved 1 chezmoi-managed file(s) aside.
Delete …/home/.config/chezmoi …? The checkout itself stays. [y/N]:
🔹 Keeping …/home/.config/chezmoi.
❌ Migration finished, but teeup refused to touch something above.
exit: 1
```

The stand-in checkout came out byte-identical, and the whole log of chezmoi calls was `source-path` six times and `managed --path-style=absolute --include=files,symlinks` once. No `purge`, no `apply`, nothing that writes.

**Not verified.** Nothing here has run on macOS: BSD awk's handling of `\.` in a dynamic regexp, `$TMPDIR` under `/var/folders` resolving through `/private` in `migrate_path_is_safe`, a real `chezmoi managed` listing, and every **Real-Mac risk** note in the tasks above.
