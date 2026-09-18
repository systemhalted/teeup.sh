# Phase 5b: the finish — the agent skill, the last docs pass, the parity checklist, and deleting `legacy/`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the mental model of the finished runtime as an agent skill the three AI CLIs on this machine actually load, make `README.md`, `CONTRIBUTING.md` and `docs/` true against everything phases 1 to 5a shipped, record a module-by-module parity checklist against the old installer, and then delete `legacy/` and every reference to it with the suite still green.

**Architecture:** Four kinds of change, in a deliberate order. First a file nobody has written yet (`share/agents/skills/teeup/SKILL.md`) plus one library function (`agent_skill_link`) that symlinks it into the directories Claude Code, Codex and Gemini CLI scan, wired into `capabilities/teeup-runtime`'s `configure` and `doctor` so it happens at bootstrap and is checked afterwards. Then the last handoff phase 4c left open: twenty `share/teeup/menu.json` rows. Then the documentation, rewritten rather than patched, because both files are still half old-installer manual. Then `docs/legacy-parity.md`, the spec's phase 5 gate. Only then `git rm -r legacy/`, as the last task, so a reviewer can reject the deletion while keeping everything above it. A new suite, `tests/docs.sh`, is what keeps all of it from rotting: it reads `teeup help`, `capabilities/*/capability` and the tier lists at run time and fails when a document disagrees with them.

**Tech Stack:** bash 3.2 (macOS stock), BSD `awk`/`sed`/`grep`, the phase 1 mock-binary test harness, phase 4b's doctor contract and `lib/menu.awk`, GitHub Actions (`macos-14`, `macos-15-intel`, `ubuntu-latest`), and the `SKILL.md` format Claude Code, Codex CLI and Gemini CLI all read.

**Spec:** `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md` — section 4 (`share/agents/skills/teeup/`, the directory structure and the capability metadata contract), section 12 ("Adding a tool later"), the "CLI surface" block, Omarchy idea 12 ("Dense 'why' comments; ship mental model as an agent skill with read-only boundaries"), and the phase 5 row of "Migration path for the repo", whose gate is the parity checklist.

---

## Depends on

Phases 1, 2a and 2b are merged; for them `main` is the ground truth. Phases 3a, 3b, 4a, 4b, 4c, 4d and 5a are planned but not merged, so their plan text is the contract. Execution order is 3a, 3b, 4a, 4b, 4c, 4d, 5a, 5b; this is the last plan.

| Interface | Kind | Defined by |
|---|---|---|
| `log ok warn err die have run_cmd run_privileged run_logged user_config_dir is_macos` | functions, `lib/core.sh` | main |
| `DRY_RUN TEEUP_PATH TEEUP_CONFIG_DIR TEEUP_STATE_DIR TEEUP_CAP TEEUP_CAP_DIR` | variables | main |
| `backup_target backup_copy copy_config_once write_managed_file append_once file_sha replace_literal` | functions, `lib/files.sh` | main, phase 4a |
| `state_done check\|mark\|ensure` | function, `lib/state.sh` | main |
| `cap_dir cap_exists cap_list cap_meta_get cap_check` | functions, `lib/capability.sh` | main |
| `setup_test_env cleanup_test_env mock_command mock_command_script mock_macos_base run_test print_summary` and the `assert_*` family | test harness, `tests/helper.sh` | main |
| `tests/run.sh` suite loop (`lib/*.sh`, `capabilities/*.sh`, `cli.sh`, `bootstrap.sh`), worker pool, `All N suites passed.` | test runner | main (`c08dd63`) |
| `capabilities/teeup-runtime/configure` writes `~/.config/teeup/env`, `~/.local/bin/teeup`, the state tree, the hook `.sample` files, then calls `shims_generate` | capability script | main, phases 3b and 4a |
| `capabilities/emacs zed firefox-developer-edition obsidian neovim vscode chrome`; `TEEUP_EMACS_FLAVOR`; `json_set_key`/`json_merge_key` in `lib/files.sh` | capabilities and functions | phase 3a |
| `teeup launch`, `teeup lazy-run`, `teeup install dev-env <lang>`, `lib/lazy.sh` (`shims_dir`, `shims_generate`, `cask_app_install`, `cask_app_report`), `lib/mise.sh`, capabilities `ai colima herdr tmux ollama cursor` | verbs, libraries, capabilities | phase 3b |
| `teeup update`, `teeup reset`, `teeup remove`, `teeup dev add-migration`, `lib/hooks.sh` (`hook_run`, `TEEUP_HOOK_EVENTS`), `lib/migrations.sh`, `migrations/README.md` | verbs and libraries | phase 4a |
| `teeup doctor`, `teeup menu`, `teeup config`, `teeup dev new-capability`, `teeup dev check`; `lib/doctor.sh` (`doctor_ok`, `doctor_warn`, `doctor_fail <msg> <fix>`, `doctor_verdict`); `lib/menu.sh` + `lib/menu.awk`; `share/teeup/menu.json`; `share/teeup/skeleton/`; `capabilities/teeup-runtime/doctor` | verbs, libraries, files | phase 4b |
| Capabilities `k8s lazydocker docker-dbs brave arc zen slack zoom signal whatsapp telegram discord teams 1password raycast bruno notion typora karabiner xcode`; `tests/capabilities/{browsers,communication,productivity}.sh`; `TEEUP_DBS`, `TEEUP_KARABINER_HYPER` | capabilities and answers | phase 4c |
| Themes `catppuccin everforest gruvbox tokyo-night`, each with `dark.toml` and `light.toml`; `tests/lib/themes.sh` | themes | phase 4d |
| `teeup migrate legacy`; `lib/migrate.sh`; `disable_matching_lines` in `lib/files.sh`; the `setup.migrate` menu row; the leftover checks inside `capabilities/zsh/doctor` and `capabilities/git/doctor` | verb, library, rows, checks | phase 5a |
| `lib/all.sh` sources `… lazy mise hooks migrations doctor menu dev migrate` | library list | phases 3b, 4a, 4b, 5a |

### What was assumed about phase 5a, and why

Phase 5a's plan (`docs/superpowers/plans/2026-09-13-redesign-phase5a-legacy-migration.md`) existed in draft while this plan was written: its header, "Depends on", "What 5a owns", Global Constraints, Contracts, File structure and task list were final, and Tasks 1 to 4 were written in full. Tasks 5 to 9 were not yet on disk. Everything this plan needs from 5a comes from the sections that were final, and is listed here so a reviewer can check it against 5a as merged:

1. **The verb is exactly `teeup migrate legacy`** (5a's File structure and its Task 6, `bin/teeup` → `cmd_migrate`), and it is the only verb 5a adds. Task 5 of this plan puts one row for it in the README command table and Task 6 reproduces it in CONTRIBUTING; Task 4's parity checklist cites it for the legacy `--reconcile-existing-config` row.
2. **`teeup migrate legacy` removes `~/.teeup.common`, `~/.teeupshrc`, the `shellrc.common` link, `~/.config/mac-setup` and dangling legacy symlinks; disables SDKMAN, rbenv and pyenv init lines; and asks before deleting only `~/.config/chezmoi`, never running `chezmoi purge` and never touching `~/Work/environment/dotfiles`** (5a Contracts, "What `teeup migrate legacy` may delete"). That is what the README's "Coming from an older setup" section says.
3. **5a adds four doctor checks** — a `[user]` block in `~/.gitconfig.local` (`capabilities/git/doctor`), Powerlevel10k remnants, `~/.oh-my-zsh`, and a chezmoi source directory still configured (`capabilities/zsh/doctor`) — **and no new doctor script** (5a Contracts, "The doctor leftovers"). This plan adds no doctor check to `zsh` or `git`, so there is no collision; the one doctor edit here is in `capabilities/teeup-runtime/doctor`, which 5a does not touch.
4. **5a adds one menu row, `setup.migrate`** (5a File structure). Task 3 of this plan adds rows under `install.*` and `launch.*` only, and the test it writes asserts the rows it adds rather than the whole file, so the two edits compose whichever lands first.
5. **5a Task 9 edits `README.md` and `CONTRIBUTING.md`.** Tasks 5 and 6 here replace both files whole rather than patching them, so nothing anchors on 5a's wording. The content 5a would have added is written out here from the contract above. **If 5a as merged documents anything this plan's README or CONTRIBUTING does not, fold it in during Task 5 or 6 rather than dropping it** — the `tests/docs.sh` check in Task 1 will catch a missing verb by itself, but not a missing paragraph.
6. **5a does not delete anything under `legacy/`** and ports `disable_matching_lines` out of `legacy/teeup.sh:479` into `lib/files.sh` before this plan's Task 7 deletes the file (5a "What 5a owns, and what it does not"). Task 7 Step 1 checks for the port and, separately, for every one of 5a's other five tasks (the safety gates in Task 2, the three migration operations in Tasks 3 to 5, and the verb wired to call them in Task 6) before it deletes anything, precisely so this assumption cannot go unverified — in whole or in part — on the tree Task 7 actually runs against.

If 5a is *not* merged when this plan runs, Tasks 1 to 6 still work, but Task 5's README table and Task 4's parity row for `--reconcile-existing-config` must drop `teeup migrate legacy`, and `tests/docs.sh` will tell you so: it compares the table against `teeup help`, in both directions. **Task 7 must not run.** Deleting `legacy/` is what the phase 5 gate exists to guard, and 5a is what ports `disable_matching_lines` out of `legacy/teeup.sh` (5a Task 1) and gives `teeup migrate legacy` a real, wired-up implementation: `lib/migrate.sh`'s closed key list and safety gates (`migrate_rm`, `migrate_target`, `migrate_path_is_safe` — 5a Task 2) are necessary but not sufficient on their own, because they land before the three operations they guard (`migrate_legacy_paths`, `migrate_disable_runtime_inits`, `migrate_chezmoi` — 5a Tasks 3 to 5) and before `cmd_migrate` calls them from a working `migrate)` dispatch arm (5a Task 6). Running Task 7 before all six of those land would delete the only copy of code the redesign still needs. Dropping the README and parity references does not change that — a document that stops mentioning `teeup migrate legacy` is not the same thing as the verb having a working implementation. Task 7 Step 1 checks for every one of the six pieces, not only the earliest, so a transcription cannot run ahead of 5a by mistake — including the mistake of stopping partway through 5a itself.

---

## Global Constraints

Every task's requirements implicitly include this section.

- **bash 3.2 compatible.** No `mapfile`, `readarray`, `declare -A`, `${var,,}`, `${var^^}`, `readlink -f`, `**`, `&>>`, `wait -n`, `local -n`. Use `10#$n` for arithmetic on a string that may carry a leading zero. No same-line `local` back-reference (`local a=1 b=$a` leaves `b` empty). bash 3.2 mis-parses a quoted pattern containing `/` inside `${var//pat/repl}`: use `replace_literal` (`lib/files.sh`). Run `shopt -u patsub_replacement 2>/dev/null || true` before any `${var//}` whose replacement text can contain `&`.
- **BSD tools only.** No GNU-only flags, no `grep -P`, no `sed -i` without a backup suffix, no `\t` or `\n` in a `sed` replacement, no `readlink -f`. Pass an awk value through `ENVIRON` rather than `-v` whenever it can contain a backslash.
- **Capability scripts** (`install`, `configure`, `doctor`, `theme-apply`, `font-apply`) start `#!/usr/bin/env bash`, are run by `cap_run` as `bash -eu` with `lib/all.sh` sourced and `answers_load` done, and must not use `local`. Mind `set -e` on a trailing `[[ ]] && cmd`. Mocked commands are called by bare name. Every mutation goes through `run_cmd`/`run_privileged` or a `DRY_RUN`-guarded primitive; `DRY_RUN=true` must change nothing. In `bin/teeup` and `lib/*.sh`, which also run under `set -eu`, use `if … then … fi` rather than a bare `[[ ]] && cmd` statement.
- **Paths.** `user_config_dir` for `~/.config`; `TEEUP_CONFIG_DIR` and `TEEUP_STATE_DIR` are honoured everywhere. Paths containing spaces and shell metacharacters must work, and every new suite includes at least one such path.
- **Machine file precedence.** `answers` then `machines/<hostname>.conf`; the machine file wins, for every consumer of an answer.
- **Capability metadata contract:** `summary group tier requires provides packages casks apps interactive`. `provides` never names a command macOS ships (`python3`, `ruby`, `java`, `git`, `perl`). A `core` or `daily` capability must appear in its tier list or `teeup commands --check` fails, and the list entry lands in the same commit as the capability.
- **Tests never touch the real machine.** Every test runs under `tests/helper.sh`: a temp `$HOME`, `MOCK_BIN` first on the narrowed PATH `$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin`, `mock_command`, `mock_command_script`, `mock_macos_base`, `hide_host_commands`, `TEEUP_TEST_MISSING`, `TEEUP_PKG_PREFIX`, `TEEUP_APPS_DIR`. The narrowed PATH hides Homebrew: any host tool a test needs (`lua`, `jq`, `python3`) must be resolved before `setup_test_env` or mocked. CI runs `macos-14`, `macos-15-intel` and `ubuntu-latest`. A test that can only pass on a developer's machine is a defect.
- **Prompts in tests.** `lib/ui.sh` uses gum whenever `TEEUP_NO_GUM` is empty and `gum` is on PATH, and the harness's narrowed PATH still exposes a host `/usr/bin/gum`. **Every test that drives a prompt or a picker must `export TEEUP_NO_GUM=1`.** No test in this plan drives one, and each new suite exports it anyway so that a later test added to the file inherits the guard.
- **`docs/superpowers/` is never deleted or rewritten.** The specs, plans and reviews under it are the record of how the design was decided; Task 7 deletes `legacy/` and moves one stray review *into* `docs/superpowers/reviews/`, and touches nothing else there.
- **Suite counts.** `tests/run.sh` ends with `All N suites passed.` Never hard-code N: write "the suite count printed before this task, plus K".
- **Nothing has run on a real Mac.** Each task carries a **Real-Mac risk** note naming what only hardware, or a real agent CLI, proves.
- **Verify, do not guess** every external path, CLI flag and file format against current upstream documentation or the installed tool. The three agent CLIs' skill directories were checked for this plan; the citations are in the Self-review.
- **Plain prose.** None of these patterns anywhere in the plan or in the documents it writes: "No X, no Y" chains, "Did not X, did not Y" chains, "That's the whole …", "Don't VERB it … VERB it", "Sit with that", "You already know", "is the entire …", "The entire … is", "X is real, and …", "The punchline", "Worth naming".
- **Every task ends** with: `./tests/run.sh` green, `./bin/teeup commands --check` silent and exit 0, `shellcheck --severity=warning` clean on every new or edited shell script and test, `git diff --check` clean, and ONE commit with a plain imperative subject and NO trailers (no `Co-Authored-By`, no `Claude-Session`, no "Generated with").

---

## Decisions made here

1. **The skill lives in the checkout and is reached by symlink, not by copy.** `share/agents/skills/teeup/SKILL.md` is the one copy (spec section 4 names that path). `agent_skill_link` writes `ln -sfn "$TEEUP_PATH/share/agents/skills/teeup" <dir>/teeup` into each agent's skill directory. A copy would go stale the moment `git pull` changed the skill and nothing would say so; a symlink means `teeup update` ships a new skill for free. Claude Code documents that a skill entry "can be a symlink to a directory elsewhere" and that it reads `SKILL.md` from the target; Codex documents that it "supports symlinked skill folders and follows the symlink target when scanning these locations". Gemini CLI's documentation does not mention symlinks either way, which is a Real-Tool risk named in Task 2 — a symlinked directory is an ordinary directory to any code that lists it, and the doctor check reports the link either way.
2. **Four directories, three of them conditional.** `~/.agents/skills/teeup` is written unconditionally: it is the tool-neutral path, it is where Codex CLI documents user skills, and Gemini CLI reads it as an alias for `~/.gemini/skills` that "takes precedence" within the user tier. `~/.claude/skills/teeup`, `~/.codex/skills/teeup` and `~/.gemini/skills/teeup` are written only when `~/.claude`, `~/.codex` or `~/.gemini` already exists, because creating a tool's home directory on a machine that does not have the tool is a write teeup has no business making. Claude Code has no `~/.agents/skills` support — its documentation says so in as many words — which is why the conditional list is not an optimisation but the only way Claude Code sees the skill at all. Installing an agent CLI later is covered: `teeup-runtime` is a core capability, so `teeup update` re-runs its `configure` and the link appears; `teeup doctor` reports the gap in the meantime.
3. **The skill is one file.** Omarchy's own skill splits into `SKILL.md` plus six topic files, and its `diagnose-crash` skill is one file plus `reporting.md`. teeup's mental model fits in one file of roughly two hundred lines, and a second file would immediately duplicate CONTRIBUTING. The skill therefore points at CONTRIBUTING and the README for depth and keeps only what an agent needs before it touches anything: the three owners, the read-only boundaries, the capability contract, the seven steps of adding one, and how to run the tests.
4. **`tests/docs.sh` is a new top-level suite, not a `tests/lib/` file.** It tests documents, not a library, and `tests/run.sh` starts `cli.sh` and `bootstrap.sh` first because they are the slowest; a docs suite is fast and belongs at the end of the list. It needs one line in `tests/run.sh`'s glob and one word in the CI shellcheck list, both added in Task 1.
5. **The documentation checks read the runtime, never a second copy of it.** `tests/docs.sh` extracts the verbs from `./bin/teeup help` and the capability names from `capabilities/*/capability`, and compares the README and the parity checklist against those. A test that hard-coded the verb list would have to be edited by the same person who forgot to edit the README, which is the failure it exists to prevent.
6. **README and CONTRIBUTING are replaced whole, not patched.** Both still carry the old installer's manual: the README's last 638 lines (from `## ✨ Features` on) are `--only python`, `ZSH_MODE=ohmyzsh` and a Bruno tutorial, and CONTRIBUTING's first 425 are "Add Toggle Variable", "Update `list_modules()`" and "Add Case in `parse_only_modules()`". Phases 1 to 5a appended new sections above and below that material rather than removing it, so both documents now describe two products. A patch would leave the seams; a rewrite is also the only way to fix the numbering collision phases 4a, 4b, 4c and 5a created in CONTRIBUTING's capability list, where two separate runs of items restart at 20.
7. **The parity checklist is a document, not a test fixture — and it has a test.** `docs/legacy-parity.md` records the thirteen modules `legacy/teeup.sh --list-modules` printed, verbatim, plus the flags and environment variables that were features in their own right, each mapped to the capability that replaced it or to a drop with a reason. `tests/docs.sh` asserts that every capability name the checklist claims exists in `capabilities/`, so a row cannot point at something that was renamed away. The module list itself is frozen text: the command that produced it stops existing in Task 7, which is exactly why the output is transcribed into the document first.
8. **The twenty menu rows phase 4c handed to 4b are added here.** 4c's plan says the rows "are a handoff, recorded in Depends on"; 4b was written in parallel and could not take them. The README says `teeup menu` is "every teeup action as a keyboard-driven list", and Task 5 writes that sentence, so the rows have to exist before it is true. They are one task of data with a test, and a reviewer can reject them without touching anything else.
9. **`legacy/` goes in the last task, in one commit, with its CI steps.** The workflow runs three legacy steps (two shellcheck, one test run) before the new-runtime steps; they are deleted in the same commit as the tree, because a workflow that shellchecks a deleted directory fails on the next push. The check that nothing still points at the deleted tree reads `git ls-files`, not the working tree: a repository root can hold untracked scratch notes (`review.md` is one on the machine this plan was written on) that mention `legacy/`, and failing somebody's suite over their own file, or deleting it for them, would both be wrong.
10. **`CHANGELOG.md` keeps its history and gains an entry.** A changelog that is edited to pretend the old installer never shipped is worse than no changelog. Task 4 adds the redesign to `[Unreleased]` and leaves every existing entry alone; `tests/docs.sh`'s "nothing points at `legacy/`" check exempts `CHANGELOG.md`, `docs/superpowers/` and `docs/legacy-parity.md`, which are the three places where a reference to a deleted tree is a historical fact rather than a broken link, alongside `tests/docs.sh`, which holds the search string itself.

---

## File structure

| File | Responsibility | Task |
|---|---|---|
| `share/agents/skills/teeup/SKILL.md` | The mental model an agent needs before touching the tree: owners, read-only boundaries, the capability contract, adding one, the tests; the parity pointer | 1, 4 |
| `tests/docs.sh` | New suite: the skill's frontmatter and its claims, the README command table against `teeup help`, the parity checklist against `capabilities/`, and "nothing points at `legacy/`" | 1, 4, 5, 7 |
| `tests/run.sh` | One more entry in the suite glob | 1 |
| `lib/dev.sh` | One more entry in `dev_shell_files`, so `teeup dev check` lints the new suite | 1 |
| `.github/workflows/ci.yml` | `tests/docs.sh` in the shellcheck list (Task 1); the three legacy steps deleted (Task 7) | 1, 7 |
| `lib/files.sh` | `agent_skill_link <source-dir> <name>` | 2 |
| `capabilities/teeup-runtime/configure` | Calls `agent_skill_link` | 2 |
| `capabilities/teeup-runtime/doctor` | Reports a missing or stale skill link | 2 |
| `tests/lib/files.sh` | `agent_skill_link`: the unconditional directory, the conditional ones, a foreign file, `DRY_RUN` | 2 |
| `tests/capabilities/teeup-runtime.sh` | The link after `configure`, the doctor's verdict | 2 |
| `share/teeup/menu.json` | The twenty phase-4c rows, under `install.containers`, `install.browsers`, `install.communication`, `install.productivity`, `install.system` and `launch.*` | 3 |
| `tests/lib/menu.sh` | The new rows parse, are leaves with actions, and have `when` predicates that hide them once installed | 3 |
| `README.md` | Rewritten: what teeup is, install, the command table, the tiers, the sections phases 3 and 4 wrote, migration, agents, trust model, the tree | 5 |
| `CHANGELOG.md` | One `[Unreleased]` entry for the redesign | 5 |
| `CONTRIBUTING.md` | Rewritten: getting started, the layout, one renumbered "adding a capability" list, code style, tests, the skill, docs | 6 |
| `docs/legacy-parity.md` | Every legacy module, flag and environment variable mapped to a capability or a reasoned drop — the spec's phase 5 gate | 4 |
| `legacy/` | Deleted; `lib/pkg.sh`'s one comment reworded | 7 |

---

## Tasks

1. The agent skill, and the suite that keeps every document true
2. Linking the skill where Claude Code, Codex and Gemini CLI look for it
3. The twenty menu rows phase 4c handed over
4. `docs/legacy-parity.md`: the phase 5 gate
5. `README.md`, rewritten against the runtime that exists
6. `CONTRIBUTING.md`, rewritten and renumbered
7. Deleting `legacy/`

---

### Task 1: The agent skill, and the suite that keeps every document true

**Files:**
- Create: `share/agents/skills/teeup/SKILL.md`
- Create: `tests/docs.sh`
- Modify: `tests/run.sh` (the suite glob)
- Modify: `lib/dev.sh` (`dev_shell_files`, so `teeup dev check` lints the new suite)
- Modify: `.github/workflows/ci.yml` (the new-runtime shellcheck list)

**Interfaces:**
- Consumes: `./bin/teeup help` (every phase's verbs), `capabilities/*/capability` and `capabilities/{core,daily}.list` (main), `tests/helper.sh`'s `run_test`, `print_summary`, `assert_equals`, `assert_contains`, `assert_file_exists` (main).
- Produces: `share/agents/skills/teeup/SKILL.md`, the file Task 2 links and Tasks 4, 5 and 6 point at. `tests/docs.sh`, the suite Tasks 4, 5 and 7 extend; it is a plain `bash tests/docs.sh` file with the same shape as every other suite. It reads the checkout — `README.md`, the skill, `capabilities/*` — rather than a temp `$HOME` for the files it asserts on, but it still calls `setup_test_env` once, for the whole file, because `help_verbs()` runs `./bin/teeup help`, and `bin/teeup` sources the real answers file and machine config before dispatching on any verb: see Step 2. The README region markers `<!-- teeup-commands -->` and `<!-- /teeup-commands -->`, which Task 5 must put in `README.md`.

**Why the suite comes first.** Tasks 4, 5 and 6 rewrite three documents by hand. Without a check that reads the runtime, the only thing standing between "the README lists every verb" and "the README lists the verbs somebody remembered" is care, and the rest of this plan is four thousand words of prose written in one sitting. The suite is written here, with the four checks that can pass today (the skill's own claims), and grows more in Tasks 4, 5 and 7.

- [ ] **Step 1: Write the skill**

The skill is the one document written for a reader with no history: an agent opening the checkout for the first time. It says what the tree is, which half of it the user owns, what must never be edited, what a capability is, how to add one, and how to run the tests. Everything else it defers to `README.md` and `CONTRIBUTING.md` rather than repeating, because a second copy of a rule is a rule that will disagree with itself.

````markdown file=share/agents/skills/teeup/SKILL.md
---
name: teeup
description: >
  REQUIRED when working inside a teeup checkout or on a Mac teeup set up.
  Use before editing anything under capabilities/, lib/, themes/, share/ or
  migrations/, before adding a capability or a theme, and when asked how a
  Mac's shell, editors, terminal, fonts, colours, casks or macOS defaults are
  configured. Triggers: teeup, capability, bootstrap, tier, core.list,
  daily.list, lazy shim, teeup install/configure/update/reset/remove/doctor/
  menu/theme/launch/lazy-run/config/secret/migrate, answers file,
  machines/<hostname>.conf, ~/.config/teeup, ~/.local/state/teeup, themed
  templates, theme-apply, font-apply. macOS only; for Linux desktop
  configuration use the omarchy skill instead.
---

# teeup

teeup turns a Mac into a working machine and keeps it that way. It is a git
checkout plus one command. Every piece of state it keeps is a file whose
presence or content you can read; nothing runs in the background and nothing is
cached anywhere you cannot open in an editor.

macOS only. The Linux half of this user's setup lives in a separate chezmoi
repository and teeup never touches it.

## The one thing to understand first

Three trees, three owners. Every question about "where does this file go" is
answered by deciding who owns it.

| Tree | Owner | Rule |
|---|---|---|
| the checkout (`$TEEUP_PATH`, normally `~/.local/share/teeup`) | teeup | Version controlled. Edit it in a branch, with a test. |
| `~/.config/<tool>/` and the dotfiles in `$HOME` | the user | teeup copies a file here **once** and never writes it again. |
| `~/.local/state/teeup/` | generated | Written by teeup, read by teeup, never edited by hand or by you. |

Inside a capability the same split appears as three directories:

- `capabilities/<cap>/config/` is copied into `~/.config/` the first time and
  belongs to the user after that (`copy_config_once` refuses to overwrite).
- `capabilities/<cap>/home/` is copied into `$HOME` under its literal dotfile
  name: `home/.zshrc` becomes `~/.zshrc`. Same once-only rule.
- `capabilities/<cap>/default/` stays teeup's and is read at runtime through
  `$TEEUP_PATH`. The thin file in the user's home sources the thick file here,
  which is how a `git pull` improves defaults without touching a user edit.

## Never edit these

1. **Anything under `~/.local/state/teeup/`.** It holds `done/`, `toggles/`,
   `migrations/`, `shims/`, `stock/`, `logs/` and `current/` (the rendered
   theme, the current theme name, the current font). Every file there is
   generated. To change it, run the command that generates it:
   `teeup configure teeup-runtime` for the shims and the state tree,
   `teeup theme set <name>` for `current/theme/`, `teeup install font <name>`
   for `current/font`. Deleting a marker under `done/` to "re-run" something is
   the wrong fix; `teeup configure <cap>` is idempotent and is the right one.
2. **`~/.config/teeup/answers`.** It is the user's, written by the bootstrap
   wizard and edited with `teeup config set KEY value` or `teeup config edit`,
   which validates the file and rolls back a syntax error.
3. **`machines/<hostname>.conf` for a host that is not this one.** Those files
   are committed, and each one encodes a constraint on somebody's laptop.
4. **`docs/superpowers/`.** Specs, implementation plans and reviews. They are
   the record of how the design was decided, not documentation to refresh. A
   plan being executed belongs to whoever is executing it; if a plan is wrong,
   say so, do not silently rewrite it.
5. **`.superpowers/`.** Another agent's working directory: ledgers, briefs and
   review packages. It is gitignored and it is not yours.
6. **The sibling repository `~/Work/environment/dotfiles`.** It is read-only
   reference that keeps serving Linux. `teeup migrate legacy` is written so that
   no argument can make it name that directory, and it never runs
   `chezmoi purge`. Keep it that way.

## What a capability is

A capability is one directory under `capabilities/` holding a metadata file and
a few scripts. `teeup <verb> <cap>` runs `capabilities/<cap>/<verb>`; `update`
and `remove` fall back to generic implementations derived from the metadata.

```sh
# capabilities/<name>/capability  -- sourced KEY=value, no logic
summary="One line, shown by teeup list"
group=editors           # editors|shell|git|languages|containers|apps|ai|macos|system|browsers|communication|productivity
tier=daily              # core | daily | lazy
requires="package-manager git"   # capabilities that run first
provides="nvim"         # commands that get a lazy shim when tier=lazy
packages="neovim"       # pkg_install candidates; drive the generic update and remove
casks=""                # cask candidates, skipped with a note on MacPorts
apps=""                 # .app bundle names for teeup launch, separated by ;
interactive=false       # true keeps stdin on the TTY (gh auth login, ssh-keygen)
```

Scripts beside it, every one optional except the first two:

| Script | What it may do |
|---|---|
| `install` | install packages only (`pkg_install`, `cask_install`, `cask_app_install`) |
| `configure` | write configuration only (`copy_config_once`, `write_managed_file`, `append_once`, `defaults_write`, `launchagent_install`) |
| `doctor` | check and report; mutate nothing. `doctor_ok`/`doctor_warn`/`doctor_fail <msg> <fix>`, ending in `doctor_verdict` |
| `remove` | undo machine state a package manager cannot: a LaunchAgent, recorded `defaults`, a `hidutil` mapping |
| `theme-apply` | tell the app to pick up the new colours |
| `font-apply` | tell the app to pick up the new font |
| `update` | only when `packages=` is not enough |

Every one of them runs as `bash -eu` with `lib/all.sh` sourced, the answers
file loaded, and `TEEUP_PATH`, `TEEUP_CAP` and `TEEUP_CAP_DIR` exported. They
do not use `local` (they are not functions). They mutate the machine only
through `run_cmd`, `run_privileged` or a file primitive that carries its own
dry-run guard, so `DRY_RUN=true teeup install <cap>` changes nothing.

Three tiers: `core` runs at bootstrap and is listed in
`capabilities/core.list`; `daily` runs at bootstrap when the user said yes and
is listed in `capabilities/daily.list`; `lazy` is everything else and arrives
on first use, through a shim for each command in `provides=` or through
`teeup install <cap>`. A core or daily capability that is not in its list makes
`teeup commands --check` fail.

## Adding a capability

1. `./bin/teeup dev new-capability <name>` scaffolds the directory and
   `tests/capabilities/<name>.sh` from `share/teeup/skeleton/`. The scaffold is
   `tier=lazy` on purpose.
2. Fill in the metadata. Check every package, cask and mise registry name
   against upstream — `https://formulae.brew.sh/api/cask/<token>.json` for a
   cask, `mise registry` for a mise tool. Do not guess a name.
3. Write `install` (packages) and `configure` (configuration). Keep them
   idempotent and quiet on a second run: `teeup update` re-runs every core
   `configure` on every machine.
4. If the tier is `core` or `daily`, append the name to the tier list in the
   same commit.
5. Add a row to `share/teeup/menu.json` for anything a person would look for in
   a list. Ids are dotted, so `install.editors.zed` needs `install.editors` and
   `install` to exist as rows too.
6. If the tool has colours, add `capabilities/<name>/themed/<file>.tpl` and a
   `theme-apply`.
7. `./bin/teeup dev check <name>` — metadata lint, menu lint, shellcheck and
   that capability's suite, which is what CI runs.

`CONTRIBUTING.md` has the long form of each of these, with the rules that are
easy to get wrong (what `provides=` may not name, why `apps=` is `;`
separated, when to write a `doctor` script, how a `theme-apply` guards itself
against running on a machine where the app was never installed). Read it before
the first capability you add.

## Running the tests

```sh
./tests/run.sh                    # every suite, in a worker pool
TEEUP_TEST_JOBS=1 ./tests/run.sh  # serially, when a failure is confusing
bash tests/capabilities/zed.sh    # one suite
./bin/teeup commands --check      # metadata lint; silent means clean
./bin/teeup dev check <name>      # lint + shellcheck + that capability's suite
shellcheck --severity=warning bin/teeup lib/*.sh
```

Every suite builds a throwaway `$HOME` and a mock `bin` directory that is first
on a narrowed `PATH` (`$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin`), so no test
touches the real machine and no test may depend on Homebrew. Two rules catch
most new tests out: a test that drives a prompt or a picker must
`export TEEUP_NO_GUM=1`, because the narrowed `PATH` still exposes a host
`/usr/bin/gum` that would paint on the terminal instead of reading stdin; and a
host tool a test needs (`lua`, `jq`, `python3`) has to be resolved before
`setup_test_env` narrows the path, or mocked.

The runtime is bash 3.2, because that is what macOS ships as `/bin/bash`. No
`mapfile`, no `declare -A`, no `${var,,}`, no `readlink -f`, no `wait -n`, and
no same-line `local` back-reference. BSD `sed` and `awk`, no GNU-only flags.

## The verbs

```text
teeup install <cap> | dev-env <lang> | font <name>    teeup configure <cap>
teeup update [<cap>]                                  teeup remove <cap>
teeup reset <cap>                                     teeup doctor [<cap>]
teeup status                                          teeup list [--tier <t>]
teeup menu [<id>]                                     teeup launch <app|cap>
teeup theme set|list|current                          teeup config get|set|edit
teeup has <cap>        (exit code only)               teeup migrate legacy
teeup secret get|set|rm <name>                        teeup lazy-run <cap> <cmd>
teeup dev new-capability|add-migration|check          teeup commands --check
```

`teeup help` is the authority; this list is a summary of it.

## Where to read more

- `README.md` — what teeup installs, and every verb with its behaviour.
- `CONTRIBUTING.md` — the long form of the capability rules, the code style and
  the test conventions.
- `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md` — why
  the tree is shaped this way. Read it, do not edit it.
````

- [ ] **Step 2: Write the failing suite**

`tests/docs.sh` reads the checkout rather than a temp `$HOME` for the files it
asserts on — `README.md`, the skill, `docs/legacy-parity.md`, `capabilities/*`
— so `REPO` below stays `$TEEUP_PATH`, the real checkout, throughout. But
`help_verbs()` shells out to `./bin/teeup help`, and `bin/teeup` sources
`answers_load` before dispatching on any verb, `help` included: left alone,
that call would source this developer's real `~/.config/teeup/answers` and a
real `machines/<hostname>.conf`, which is exactly what the Global Constraint
"Tests never touch the real machine" rules out. So the suite still calls
`setup_test_env`, once for the whole file rather than once per test — nothing
here writes anything a later test could see, so one shared throwaway `$HOME`
is enough — and additionally points `TEEUP_MACHINES_DIR` at an empty
directory beside it, the way `tests/lib/answers.sh` and `tests/bootstrap.sh`
already do, because `TEEUP_MACHINES_DIR` defaults to `$TEEUP_PATH/machines`
rather than anywhere under `$HOME` and `setup_test_env` alone does not move
it. `setup_test_env` never touches `TEEUP_PATH`, so `REPO` still reads the
real tree. It still exports `TEEUP_NO_GUM=1` so that a later test added here
inherits the guard.

```bash file=tests/docs.sh
#!/usr/bin/env bash
# docs.sh - the documents, checked against the runtime they describe.
# This suite reads the checkout rather than a temp $HOME: everything it
# asserts is a claim a file in the repository makes about bin/teeup,
# capabilities/ or share/. Every other suite mocks the machine; this one
# would have nothing left to test if it did.
set -euo pipefail
# tests/docs.sh sits at the top of tests/, next to helper.sh, the way cli.sh
# and bootstrap.sh do -- not one level down like tests/lib and
# tests/capabilities.
source "$(dirname "$0")/helper.sh"

# help_verbs() below runs ./bin/teeup help, and bin/teeup sources
# answers_load before dispatching on any verb -- so, left alone, this suite
# would source the real ~/.config/teeup/answers and a real
# machines/<hostname>.conf. setup_test_env moves HOME, TEEUP_CONFIG_DIR and
# TEEUP_STATE_DIR under a throwaway directory; TEEUP_MACHINES_DIR is pointed
# at an empty one beside it, the way tests/lib/answers.sh and
# tests/bootstrap.sh do, since it defaults from $TEEUP_PATH rather than
# $HOME and setup_test_env does not move it. Called once for the whole file,
# not once per test: nothing here writes anything a later test could see.
# TEEUP_PATH itself is untouched by setup_test_env, so REPO below still reads
# the real checkout.
setup_test_env
export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
mkdir -p "$TEEUP_MACHINES_DIR"
trap cleanup_test_env EXIT

export TEEUP_NO_GUM=1
REPO="$TEEUP_PATH"
SKILL="$REPO/share/agents/skills/teeup/SKILL.md"

# help_verbs: one verb per line, from the usage block bin/teeup prints.
# Every usage line starts with exactly two spaces and "teeup ".
help_verbs() {
  "$REPO/bin/teeup" help 2>/dev/null |
    grep -E '^  teeup [a-z][a-z-]*' |
    awk '{print $2}' |
    sort -u
}

test_the_skill_has_frontmatter_a_name_and_a_description() {
  assert_file_exists "$SKILL" "the agent skill ships in the checkout" || return 1
  local first
  first="$(head -1 "$SKILL")"
  assert_equals "---" "$first" "frontmatter opens on line 1 or the whole file is content" || return 1
  local front
  front="$(awk 'NR>1 && /^---$/{exit} NR>1{print}' "$SKILL")"
  assert_contains "$front" "name: teeup" "the skill names itself" || return 1
  assert_contains "$front" "description:" "the skill says when to load it" || return 1
}

test_the_skill_names_only_paths_that_exist() {
  # Backticked paths that start with one of the checkout's top-level
  # directories. A path containing < is a placeholder (capabilities/<name>/)
  # and is skipped; so is anything ending in / that names a directory.
  local missing="" p
  for p in $(grep -oE '`(bin|lib|capabilities|share|themes|migrations|tests|docs|machines)/[A-Za-z0-9._/-]+`' "$SKILL" |
             tr -d '`' | sort -u); do
    if [[ ! -e "$REPO/$p" ]]; then
      missing="$missing $p"
    fi
  done
  assert_equals "" "$missing" "every path the skill names exists in the checkout" || return 1
}

# skill_verbs: every verb the skill names, from the two places it names one --
# a backticked `teeup <verb>` span, and the summary block under "## The verbs".
# Bare prose is not scanned, because "a teeup checkout" would otherwise read as
# a verb called "checkout".
skill_verbs() {
  {
    grep -oE '`teeup [a-z][a-z-]*' "$SKILL" | sed 's/^`teeup //'
    awk '/^## The verbs$/{f=1;next} /^## /{f=0} f' "$SKILL" |
      grep -oE 'teeup [a-z][a-z-]*' | sed 's/^teeup //'
  } | sort -u
}

test_the_skill_names_only_verbs_teeup_has() {
  local verbs unknown="" v
  verbs="$(help_verbs)"
  local named
  named="$(skill_verbs)"
  assert_contains "$named" "install" "the verb summary was found at all" || return 1
  for v in $named; do
    if ! grep -qxF -- "$v" <<<"$verbs"; then
      unknown="$unknown $v"
    fi
  done
  assert_equals "" "$unknown" "every verb the skill names is a verb teeup has" || return 1
}

test_the_skill_marks_the_generated_and_borrowed_trees_read_only() {
  local body
  body="$(cat "$SKILL")"
  # No leading ~ in the needle: shellcheck's SC2088 fires on a quoted word that
  # starts with one, and the path is what matters, not the tilde.
  assert_contains "$body" '.local/state/teeup/' "the generated tree is named as read-only" || return 1
  assert_contains "$body" 'docs/superpowers/' "the decision record is named as read-only" || return 1
  assert_contains "$body" '.superpowers/' "another agent's workspace is named as read-only" || return 1
  assert_contains "$body" 'Never edit these' "the read-only rules have a heading of their own" || return 1
}

echo "docs.sh"
run_test "the skill has frontmatter, a name and a description" test_the_skill_has_frontmatter_a_name_and_a_description
run_test "the skill names only paths that exist" test_the_skill_names_only_paths_that_exist
run_test "the skill names only verbs teeup has" test_the_skill_names_only_verbs_teeup_has
run_test "the skill marks the generated and borrowed trees read-only" test_the_skill_marks_the_generated_and_borrowed_trees_read_only
print_summary
```

- [ ] **Step 3: Run it to see it fail before `tests/run.sh` knows about it**

Run: `bash tests/docs.sh`
Expected: `docs.sh` then four `PASS` lines and `Summary: 4/4 passed` — the skill was written in Step 1, so the suite passes standing alone. The failure this step proves is the wiring: run `./tests/run.sh` and the total is unchanged, because `run.sh` globs `tests/lib/*.sh` and `tests/capabilities/*.sh` and names only `cli.sh` and `bootstrap.sh` by hand.

Run: `./tests/run.sh 2>&1 | tail -1`
Expected: the same suite count as before this task — the new suite is not in it.

- [ ] **Step 4: Add the suite to the runner**

```bash edit-old=tests/run.sh
for suite in "$TESTS_DIR"/lib/*.sh "$TESTS_DIR"/capabilities/*.sh "$TESTS_DIR"/cli.sh "$TESTS_DIR"/bootstrap.sh; do
```

```bash edit-new=tests/run.sh
for suite in "$TESTS_DIR"/lib/*.sh "$TESTS_DIR"/capabilities/*.sh "$TESTS_DIR"/cli.sh "$TESTS_DIR"/bootstrap.sh "$TESTS_DIR"/docs.sh; do
```

- [ ] **Step 5: Add it to the two shellcheck lists**

`teeup dev check` builds its own list of shell files and does not glob the top
of `tests/`, so the new suite needs naming there as well as in the workflow.

```bash edit-old=lib/dev.sh
  for f in "$TEEUP_TESTS_DIR"/helper.sh "$TEEUP_TESTS_DIR"/run.sh "$TEEUP_TESTS_DIR"/cli.sh \
           "$TEEUP_TESTS_DIR"/bootstrap.sh "$TEEUP_TESTS_DIR"/lib/*.sh "$TEEUP_TESTS_DIR"/capabilities/*.sh; do
```

```bash edit-new=lib/dev.sh
  for f in "$TEEUP_TESTS_DIR"/helper.sh "$TEEUP_TESTS_DIR"/run.sh "$TEEUP_TESTS_DIR"/cli.sh \
           "$TEEUP_TESTS_DIR"/bootstrap.sh "$TEEUP_TESTS_DIR"/docs.sh \
           "$TEEUP_TESTS_DIR"/lib/*.sh "$TEEUP_TESTS_DIR"/capabilities/*.sh; do
```

```yaml edit-old=.github/workflows/ci.yml
            tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh \
```

```yaml edit-new=.github/workflows/ci.yml
            tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh \
            tests/docs.sh \
```

- [ ] **Step 6: Run everything**

Run: `chmod +x tests/docs.sh && ./tests/run.sh 2>&1 | tail -1`
Expected: `All N suites passed.` where N is the suite count printed before this task, plus 1.

Run: `./bin/teeup commands --check`
Expected: no output, exit 0.

Run: `shellcheck --severity=warning tests/docs.sh tests/run.sh lib/dev.sh`
Expected: no output.

Run: `git diff --check`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add share/agents/skills/teeup/SKILL.md tests/docs.sh tests/run.sh lib/dev.sh .github/workflows/ci.yml
git commit -m "Ship the teeup mental model as an agent skill"
```

**Real-Mac risk:** none in the suite, which reads files. The skill itself is only proven by a real agent CLI loading it, which Task 2 sets up and which nothing in CI can check: whether Claude Code, Codex or Gemini CLI picks the skill up depends on that tool's version on the machine, and the `description` is what decides whether it loads at the right moment. The wording of the `description` is a judgement call that only shows its quality in use.

---

### Task 2: Linking the skill where Claude Code, Codex and Gemini CLI look for it

**Files:**
- Modify: `lib/files.sh` (append `agent_skill_link`)
- Modify: `capabilities/teeup-runtime/configure` (one call, after `shims_generate`)
- Modify: `capabilities/teeup-runtime/doctor` (one check, before `doctor_verdict`)
- Modify: `tests/lib/files.sh` (eight tests)
- Modify: `tests/capabilities/teeup-runtime.sh` (two tests)

**Interfaces:**
- Consumes: `log ok warn run_cmd` (`lib/core.sh`, main), `doctor_ok doctor_warn doctor_fail` (`lib/doctor.sh`, phase 4b), `share/agents/skills/teeup/` (Task 1).
- Produces: `agent_skill_link <source-dir> <name>` in `lib/files.sh`. It creates `$HOME/.agents/skills/<name>` unconditionally and `$HOME/.claude/skills/<name>`, `$HOME/.codex/skills/<name>` and `$HOME/.gemini/skills/<name>` when `$HOME/.claude`, `$HOME/.codex` or `$HOME/.gemini` exists. Each is a symlink to `<source-dir>`. It returns 1 only when `<source-dir>` is not a directory; a single link it refuses to replace is a warning, not a failure — and that includes a symlink already there: it is kept, as somebody else's choice, unless it resolves (physically, on both sides — no `readlink -f` on macOS, so `cd -P` and `pwd -P` on every step, never a bare `cd`, because a bare `cd` cancels a `component/..` pair textually without checking whether `component` is itself a symlink) to `<source-dir>` itself, which is the only thing that makes it teeup's to replace. Task 6's CONTRIBUTING entry and Task 5's README section both describe this behaviour and must stay in step with it.

**Where the four directories come from.** Checked against each tool's current documentation while writing this plan:

| Tool | Directory it scans | Citation |
|---|---|---|
| Claude Code | `~/.claude/skills/<name>/SKILL.md` for personal skills; `.claude/skills/` in a project. **`~/.agents/skills` is explicitly not supported.** A `<name>` entry may be a symlink; Claude Code reads `SKILL.md` from the target. | Claude Code docs, "Extend Claude with skills" |
| Codex CLI | `$HOME/.agents/skills` for user skills and `.agents/skills` walking up from the working directory; "Codex supports symlinked skill folders and follows the symlink target". `~/.codex/skills` is where installed skills land on this machine and is kept for that reason. | OpenAI Codex skills documentation; `~/.codex/skills` on this machine already holds symlinked skills |
| Gemini CLI | `~/.gemini/skills/` **or** `~/.agents/skills/` for user skills, `.gemini/skills/` or `.agents/skills/` for a workspace; within a tier the `.agents/skills/` alias takes precedence. | `google-gemini/gemini-cli`, `docs/cli/skills.md` |

`~/.agents/skills` alone therefore covers Codex and Gemini but not Claude Code, and `~/.claude/skills` alone covers nothing else. Writing all four, three of them only where the tool already lives, is what makes one skill file visible to all three without teeup inventing a home directory for a program that is not installed.

- [ ] **Step 1: Write the failing tests for the helper**

```bash edit-old=tests/lib/files.sh
print_summary
```

```bash edit-new=tests/lib/files.sh
test_agent_skill_link_always_writes_the_tool_neutral_directory() {
  setup
  mkdir -p "$SKILLSRC"
  printf -- '---\nname: probe\n---\n' > "$SKILLSRC/SKILL.md"
  agent_skill_link "$SKILLSRC" probe >/dev/null
  assert_equals "$SKILLSRC" "$(readlink "$TEST_HOME/.agents/skills/probe")" "the neutral path is always linked" || return 1
  assert_file_exists "$TEST_HOME/.agents/skills/probe/SKILL.md" "the link resolves to the skill" || return 1
  # No ~/.claude, ~/.codex or ~/.gemini here, so teeup invents none of them.
  local invented=""
  local d
  for d in .claude .codex .gemini; do
    if [[ -e "$TEST_HOME/$d" ]]; then invented="$invented $d"; fi
  done
  assert_equals "" "$invented" "a tool's home directory is never created by teeup" || return 1
  cleanup_test_env
}

test_agent_skill_link_writes_a_tool_directory_that_already_exists() {
  setup
  mkdir -p "$SKILLSRC" "$TEST_HOME/.claude" "$TEST_HOME/.gemini/skills"
  printf -- '---\nname: probe\n---\n' > "$SKILLSRC/SKILL.md"
  agent_skill_link "$SKILLSRC" probe >/dev/null
  assert_equals "$SKILLSRC" "$(readlink "$TEST_HOME/.claude/skills/probe")" "a bare ~/.claude is enough" || return 1
  assert_equals "$SKILLSRC" "$(readlink "$TEST_HOME/.gemini/skills/probe")" "an existing skills dir is used" || return 1
  assert_equals "" "$(readlink "$TEST_HOME/.codex/skills/probe" 2>/dev/null || true)" "no ~/.codex, no link" || return 1
  # Running it twice is quiet and changes nothing.
  local out
  out="$(agent_skill_link "$SKILLSRC" probe 2>&1)"
  assert_contains "$out" "Already linked" "a correct link is reported, not rewritten" || return 1
  assert_equals "$SKILLSRC" "$(readlink "$TEST_HOME/.claude/skills/probe")" || return 1
  cleanup_test_env
}

test_agent_skill_link_keeps_a_file_it_did_not_write() {
  setup
  mkdir -p "$SKILLSRC" "$TEST_HOME/.agents/skills/probe"
  printf -- '---\nname: probe\n---\n' > "$SKILLSRC/SKILL.md"
  printf 'mine\n' > "$TEST_HOME/.agents/skills/probe/SKILL.md"
  local out rc=0
  out="$(agent_skill_link "$SKILLSRC" probe 2>&1)" || rc=$?
  assert_success "$rc" "a refusal is a warning, not a failure" || return 1
  assert_contains "$out" "not a symlink" "the refusal says why" || return 1
  assert_equals "mine" "$(cat "$TEST_HOME/.agents/skills/probe/SKILL.md")" "somebody else's skill is left alone" || return 1
  cleanup_test_env
}

test_agent_skill_link_keeps_a_foreign_symlink() {
  setup
  mkdir -p "$SKILLSRC" "$TEST_HOME/.agents/skills"
  printf -- '---\nname: probe\n---\n' > "$SKILLSRC/SKILL.md"
  # A symlink pointing somewhere the user chose, not into any checkout's
  # share/agents/skills/ -- their own skill, or a dotfiles manager's link.
  ln -s "$TEST_HOME/elsewhere" "$TEST_HOME/.agents/skills/probe"
  local out rc=0
  out="$(agent_skill_link "$SKILLSRC" probe 2>&1)" || rc=$?
  assert_success "$rc" "a foreign symlink is a warning, not a failure" || return 1
  assert_contains "$out" "$TEST_HOME/.agents/skills/probe" "the warning names the link" || return 1
  assert_contains "$out" "$TEST_HOME/elsewhere" "the warning names what it already points at" || return 1
  assert_equals "$TEST_HOME/elsewhere" "$(readlink "$TEST_HOME/.agents/skills/probe")" "somebody else's symlink is left alone" || return 1
  cleanup_test_env
}

test_agent_skill_link_keeps_a_link_into_a_different_checkout_with_the_same_layout() {
  setup
  mkdir -p "$SKILLSRC" "$TEST_HOME/.agents/skills"
  printf -- '---\nname: probe\n---\n' > "$SKILLSRC/SKILL.md"
  # A second, real checkout -- a fork, or the user's own skills repository --
  # laid out the same way, so its path ends in share/agents/skills/probe too.
  # Ownership is decided by where the link resolves, not by how the path
  # looks, so this one has to be kept even though the shape matches.
  local other="$TEST_HOME/a different checkout/share/agents/skills/probe"
  mkdir -p "$other"
  ln -s "$other" "$TEST_HOME/.agents/skills/probe"
  local out rc=0
  out="$(agent_skill_link "$SKILLSRC" probe 2>&1)" || rc=$?
  assert_success "$rc" "a same-shape foreign symlink is a warning, not a failure" || return 1
  assert_contains "$out" "$TEST_HOME/.agents/skills/probe" "the warning names the link" || return 1
  assert_contains "$out" "$other" "the warning names what it already points at" || return 1
  assert_equals "$other" "$(readlink "$TEST_HOME/.agents/skills/probe")" "a different checkout's link is kept even though the path ends the same way" || return 1
  cleanup_test_env
}

test_agent_skill_link_refreshes_a_link_into_the_real_checkout() {
  setup
  mkdir -p "$SKILLSRC" "$TEST_HOME/.agents/skills"
  printf -- '---\nname: probe\n---\n' > "$SKILLSRC/SKILL.md"
  # A link that does not spell $SKILLSRC exactly, so the exact-string fast
  # path above is not what is under test, but resolves -- physically,
  # through an alias symlink -- to this checkout's own skill directory. This
  # is teeup's by resolution, not by shape, and gets refreshed.
  local alias="$TEST_HOME/alias-to-the-checkout"
  ln -s "$SKILLSRC" "$alias"
  ln -s "$alias" "$TEST_HOME/.agents/skills/probe"
  local out
  out="$(agent_skill_link "$SKILLSRC" probe 2>&1)"
  assert_contains "$out" "Linked" "a link that resolves to this checkout is refreshed" || return 1
  assert_equals "$SKILLSRC" "$(readlink "$TEST_HOME/.agents/skills/probe")" "the refreshed link points at the checkout directly" || return 1
  cleanup_test_env
}

test_agent_skill_link_resolves_symlinks_physically_not_logically() {
  setup
  mkdir -p "$SKILLSRC" "$TEST_HOME/.agents/skills" "$TEST_HOME/user-owns-this"
  printf -- '---\nname: probe\n---\n' > "$SKILLSRC/SKILL.md"
  # A path that answers "this checkout" only if `..` is cancelled textually
  # (bash's default, logical cd) rather than by physically walking the
  # symlink and asking its real parent for .. : "alias" sits beside
  # $SKILLSRC and points at a directory the user owns, and the crafted
  # target routes through it and back out. `cd` without -P treats
  # "alias/.." as a no-op regardless of what alias points to and lands back
  # on $SKILLSRC; `cd -P` actually enters alias, so ".." leaves the user's
  # own tree instead, and "probe" is not there.
  ln -s "$TEST_HOME/user-owns-this" "$(dirname "$SKILLSRC")/alias"
  local crafted
  crafted="$(dirname "$SKILLSRC")/alias/../probe"
  ln -s "$crafted" "$TEST_HOME/.agents/skills/probe"
  local out rc=0
  out="$(agent_skill_link "$SKILLSRC" probe 2>&1)" || rc=$?
  assert_success "$rc" "an unresolvable crafted link is a warning, not a failure" || return 1
  assert_contains "$out" "$TEST_HOME/.agents/skills/probe" "the warning names the link" || return 1
  assert_equals "$crafted" "$(readlink "$TEST_HOME/.agents/skills/probe")" "a link whose physical and logical resolutions differ is left alone" || return 1
  cleanup_test_env
}

test_agent_skill_link_dry_run_and_missing_source() {
  setup
  mkdir -p "$SKILLSRC"
  printf -- '---\nname: probe\n---\n' > "$SKILLSRC/SKILL.md"
  local out rc=0
  out="$(DRY_RUN=true agent_skill_link "$SKILLSRC" probe 2>&1)"
  assert_contains "$out" "Would execute: ln -sfn" "a dry run says what it would link" || return 1
  assert_equals "" "$(readlink "$TEST_HOME/.agents/skills/probe" 2>/dev/null || true)" "a dry run links nothing" || return 1
  out="$(agent_skill_link "$TEST_HOME/no such skill dir" probe 2>&1)" || rc=$?
  assert_failure "$rc" "a missing source directory is an error" || return 1
  assert_contains "$out" "No skill directory" || return 1
  cleanup_test_env
}

run_test "agent_skill_link always writes the neutral directory" test_agent_skill_link_always_writes_the_tool_neutral_directory
run_test "agent_skill_link writes a tool directory that exists" test_agent_skill_link_writes_a_tool_directory_that_already_exists
run_test "agent_skill_link keeps a file it did not write" test_agent_skill_link_keeps_a_file_it_did_not_write
run_test "agent_skill_link keeps a foreign symlink" test_agent_skill_link_keeps_a_foreign_symlink
run_test "agent_skill_link keeps a link into a different checkout with the same layout" test_agent_skill_link_keeps_a_link_into_a_different_checkout_with_the_same_layout
run_test "agent_skill_link refreshes a link into the real checkout" test_agent_skill_link_refreshes_a_link_into_the_real_checkout
run_test "agent_skill_link resolves symlinks physically, not logically" test_agent_skill_link_resolves_symlinks_physically_not_logically
run_test "agent_skill_link dry run, and a missing source" test_agent_skill_link_dry_run_and_missing_source
print_summary
```

The eight tests need one more variable in the suite's `setup`, on a path with a space and a dollar sign so that the helper is proven to quote everything it passes to `ln`:

```bash edit-old=tests/lib/files.sh
  SRC="$TEST_HOME/src.conf"
  DEST="$TEST_HOME/.config/tool/tool.conf"
  printf 'shipped=1\n' > "$SRC"
}
```

```bash edit-new=tests/lib/files.sh
  SRC="$TEST_HOME/src.conf"
  DEST="$TEST_HOME/.config/tool/tool.conf"
  # A checkout path with a space and a dollar sign: agent_skill_link passes it
  # to ln and to readlink, and both have to see it as one argument.
  SKILLSRC="$TEST_HOME/che ckout \$HOME/share/agents/skills/probe"
  printf 'shipped=1\n' > "$SRC"
}
```

- [ ] **Step 2: Run them to watch them fail**

Run: `bash tests/lib/files.sh 2>&1 | tail -17`
Expected: the eight new tests `FAIL` with `agent_skill_link: command not found`, and the summary line reports eight failures.

- [ ] **Step 3: Write the helper**

Append to `lib/files.sh`, after the last function in the file:

```bash edit-old=lib/files.sh
replace_literal() {
```

```bash edit-new=lib/files.sh
# agent_skill_link <source-dir> <name>
# Make one skill directory in the checkout visible to the agent CLIs on this
# machine, by symlink rather than by copy: a copy would go stale the next time
# `git pull` changed the skill and nothing would say so.
#
# $HOME/.agents/skills is the tool-neutral path, and it is always written:
# Codex CLI documents it as where user skills live, and Gemini CLI reads it as
# an alias for ~/.gemini/skills that wins inside the user tier. Claude Code
# does not read it at all, which is why the three tool-specific directories
# exist here too -- but each of those is only written when that tool already
# has a home directory, because creating ~/.gemini on a Mac with no Gemini CLI
# is a write teeup has no business making. Installing an agent later is
# covered: teeup-runtime is a core capability, so `teeup update` re-runs this.
#
# A path that is not a symlink is left alone with a warning: it is somebody
# else's skill, or their own file, and neither is teeup's to replace. Neither
# is a symlink that is not teeup's -- and ownership is decided by where a
# symlink resolves, not by how its path looks: a fork, or a user's own skills
# repository laid out the same way, can end in share/agents/skills/<name>
# without being this checkout. A symlink already at $target is kept, with a
# warning naming both paths, unless it resolves -- physically, both sides --
# to this checkout's own skill directory, in which case it is teeup's to
# refresh.
agent_skill_link() {
  local src="$1" name="$2"
  local dir parent target current resolved_src resolved_current
  if [[ ! -d "$src" ]]; then
    warn "No skill directory at $src"
    return 1
  fi
  resolved_src="$(cd -P "$src" 2>/dev/null && pwd -P)"
  for dir in "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.gemini/skills"; do
    parent="$(dirname "$dir")"
    if [[ "$dir" != "$HOME/.agents/skills" && ! -d "$parent" ]]; then
      continue
    fi
    target="$dir/$name"
    current="$(readlink "$target" 2>/dev/null || true)"
    if [[ "$current" == "$src" ]]; then
      log "Already linked: $target"
      continue
    fi
    if [[ -e "$target" && ! -L "$target" ]]; then
      warn "Keeping $target, which is not a symlink teeup wrote"
      continue
    fi
    if [[ -L "$target" ]]; then
      # No readlink -f on macOS: cd into the link's own directory first, so a
      # relative target resolves the way the shell would resolve it, then
      # into what it points at, then ask for the physical (symlink-free)
      # path on both sides. A target that does not exist, or a chain that
      # does not lead back here, fails this and is foreign. -P on every cd
      # here, not just on the final pwd: bash's default (logical) cd cancels
      # a "component/.." pair textually, without checking whether
      # "component" is a symlink to somewhere else entirely, so a target
      # such as "alias/../probe" can read back as this checkout without -P
      # while actually resolving somewhere else.
      resolved_current="$(cd -P "$(dirname "$target")" 2>/dev/null && cd -P "$current" 2>/dev/null && pwd -P)" || resolved_current=""
      if [[ -z "$resolved_current" || "$resolved_current" != "$resolved_src" ]]; then
        warn "Keeping $target, a symlink to $current rather than $src"
        continue
      fi
    fi
    if [[ ! -d "$dir" ]]; then
      run_cmd mkdir -p "$dir"
    fi
    run_cmd ln -sfn "$src" "$target"
    ok "Linked $target"
  done
  return 0
}

replace_literal() {
```

- [ ] **Step 4: Run them to watch them pass**

Run: `bash tests/lib/files.sh 2>&1 | tail -13`
Expected: the eight new tests `PASS`, and `Summary: N/N passed` with no failures.

Run: `shellcheck --severity=warning lib/files.sh tests/lib/files.sh`
Expected: no output.

- [ ] **Step 5: Write the failing capability tests**

```bash edit-old=tests/capabilities/teeup-runtime.sh
print_summary
```

```bash edit-new=tests/capabilities/teeup-runtime.sh
test_configure_links_the_agent_skill() {
  setup
  mkdir -p "$TEST_HOME/.claude"
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local src="$TEEUP_PATH/share/agents/skills/teeup"
  assert_equals "$src" "$(readlink "$TEST_HOME/.agents/skills/teeup")" "the neutral path is linked" || return 1
  assert_equals "$src" "$(readlink "$TEST_HOME/.claude/skills/teeup")" "an existing ~/.claude gets the link" || return 1
  assert_file_exists "$TEST_HOME/.agents/skills/teeup/SKILL.md" "the link resolves to the shipped skill" || return 1
  assert_equals "" "$(readlink "$TEST_HOME/.codex/skills/teeup" 2>/dev/null || true)" "no ~/.codex, no link" || return 1
  cleanup_test_env
}

test_doctor_reports_the_agent_skill_link() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  local out
  out="$("$TEEUP" doctor teeup-runtime 2>&1)"
  assert_contains "$out" "points at the shipped agent skill" "a linked skill is reported as healthy" || return 1
  rm -f "$TEST_HOME/.agents/skills/teeup"
  local rc=0
  out="$("$TEEUP" doctor teeup-runtime 2>&1)" || rc=$?
  assert_failure "$rc" "a missing skill link fails the doctor" || return 1
  assert_contains "$out" "agent skill is not linked" || return 1
  assert_contains "$out" "teeup configure teeup-runtime" "the fix is one command" || return 1
  cleanup_test_env
}

run_test "configure links the agent skill" test_configure_links_the_agent_skill
run_test "doctor reports the agent skill link" test_doctor_reports_the_agent_skill_link
print_summary
```

- [ ] **Step 6: Run them to watch them fail**

Run: `bash tests/capabilities/teeup-runtime.sh 2>&1 | tail -10`
Expected: both new tests `FAIL` — `configure` never calls the helper, so `readlink` prints nothing and the doctor says nothing about a skill.

- [ ] **Step 7: Wire it into `configure`**

```bash edit-old=capabilities/teeup-runtime/configure
shims_generate
```

```bash edit-new=capabilities/teeup-runtime/configure
shims_generate

# The mental model as an agent skill (spec section 4, Omarchy idea 12). The
# skill stays in the checkout and is reached by symlink, so a `git pull` ships
# a new one without a copy drifting out of date. ~/.agents/skills is the
# tool-neutral path Codex CLI and Gemini CLI read; ~/.claude/skills,
# ~/.codex/skills and ~/.gemini/skills are written only where that tool
# already has a home, and `teeup update` re-runs this capability, so an agent
# CLI installed later still gets the link.
agent_skill_link "$TEEUP_PATH/share/agents/skills/teeup" teeup
```

- [ ] **Step 8: Wire it into `doctor`**

```bash edit-old=capabilities/teeup-runtime/doctor
doctor_verdict
```

```bash edit-new=capabilities/teeup-runtime/doctor
# The agent skill. The neutral path is teeup's to keep correct; the three
# tool-specific ones are only checked where that tool has a home, and a gap
# there is a warning because the user may have removed the link on purpose.
skill_src="$TEEUP_PATH/share/agents/skills/teeup"
skill_link="$HOME/.agents/skills/teeup"
if [[ "$(readlink "$skill_link" 2>/dev/null || true)" == "$skill_src" ]]; then
  doctor_ok "$skill_link points at the shipped agent skill."
else
  doctor_fail "The teeup agent skill is not linked into $skill_link, so an agent CLI cannot load it." "teeup configure teeup-runtime"
fi
for agent_home in .claude .codex .gemini; do
  if [[ -d "$HOME/$agent_home" ]] &&
     [[ "$(readlink "$HOME/$agent_home/skills/teeup" 2>/dev/null || true)" != "$skill_src" ]]; then
    doctor_warn "$HOME/$agent_home is here but $HOME/$agent_home/skills/teeup does not point at the skill. Run: teeup configure teeup-runtime"
  fi
done

doctor_verdict
```

- [ ] **Step 9: Run everything**

Run: `bash tests/capabilities/teeup-runtime.sh 2>&1 | tail -8`
Expected: both new tests `PASS`, no failures.

Run: `./tests/run.sh 2>&1 | tail -1`
Expected: `All N suites passed.` with N unchanged from Task 1 — this task adds tests to existing suites rather than a suite.

Run: `./bin/teeup commands --check`
Expected: no output, exit 0.

Run: `shellcheck --severity=warning lib/files.sh capabilities/teeup-runtime/configure capabilities/teeup-runtime/doctor tests/lib/files.sh tests/capabilities/teeup-runtime.sh`
Expected: no output.

Run: `git diff --check`
Expected: no output.

- [ ] **Step 10: Commit**

```bash
git add lib/files.sh capabilities/teeup-runtime/configure capabilities/teeup-runtime/doctor tests/lib/files.sh tests/capabilities/teeup-runtime.sh
git commit -m "Link the teeup agent skill into the agent CLIs' skill directories"
```

**Real-Mac risk:** three things, none of which a test can reach. Whether Claude Code, Codex CLI and Gemini CLI as installed on this Mac actually load a skill through a symlink — Claude Code and Codex both document that they follow one, Gemini CLI's documentation says nothing either way, and a symlinked directory is an ordinary directory to anything that lists it, so the risk is a version of Gemini CLI that resolves paths differently. Whether the `description` in the frontmatter makes the skill load at the right moment, which only shows up in use. And whether a user who keeps their skills in a git repository of their own finds four teeup symlinks appearing there unwelcome; the `doctor` warning rather than a failure for the three tool directories is the hedge.

---

### Task 3: The twenty menu rows phase 4c handed over

**Files:**
- Modify: `share/teeup/menu.json`
- Modify: `tests/lib/menu.sh` (one test against the shipped file)

**Interfaces:**
- Consumes: `menu_cache`, `menu_ids`, `menu_children`, `menu_field`, `menu_check` (`lib/menu.sh`, phase 4b); the capability names phase 4c added.
- Produces: the ids `install.browsers.*`, `install.communication.*`, `install.productivity.*`, `install.system.*`, three more `install.shell.*` rows and eleven more `launch.*` rows. Task 4's README sentence "every teeup action as a keyboard-driven list" depends on them.

Phase 4c's plan says of these rows: "Adding a `menu.json` row per capability added here is 4b's file to edit … the twenty rows are a handoff, recorded in Depends on". 4b was written at the same time and could not take them, so they land here, in the phase whose job is to make the documentation true.

Two rows that phase 4b wrote move while this happens. `install.apps` held Firefox Developer Edition, Chrome and Obsidian, which was the only sensible grouping when those were the only three; with brave, arc, zen and five productivity apps arriving they belong in the same submenus as their neighbours, and `group=` in each capability's metadata already says which. `install.apps` therefore becomes `install.browsers` and `install.productivity`. No test asserts a shipped id (`tests/lib/menu.sh` builds its own fixture), and `menu_check` catches a dangling parent, so the move is safe to make in one edit.

- [ ] **Step 1: Write the failing test**

```bash edit-old=tests/lib/menu.sh
print_summary
```

```bash edit-new=tests/lib/menu.sh
# The shipped file, not a fixture: every lazy capability a person would go
# looking for has to be reachable from `teeup menu`, and the only way to know
# is to ask the file. A capability with no row is the defect this catches.
test_the_shipped_menu_reaches_every_installable_capability() {
  setup
  # The shipped file, not the suite's fixture. setup() points TEEUP_MENU_FILE
  # at a temp path and lib/menu.sh only defaults it at source time, so it is
  # set here rather than unset.
  export TEEUP_MENU_FILE="$TEEUP_PATH/share/teeup/menu.json"
  local cache missing="" cap
  cache="$(menu_cache)"
  menu_check "$cache" || return 1
  for cap in k8s lazydocker docker-dbs brave arc zen slack zoom signal whatsapp \
             telegram discord teams 1password raycast bruno notion typora \
             karabiner xcode; do
    if ! grep -q "teeup install $cap\$" "$cache"; then
      missing="$missing $cap"
    fi
  done
  assert_equals "" "$missing" "every phase 4c capability has an install row" || return 1
  cleanup_test_env
}

test_the_shipped_menu_hides_an_install_row_once_it_is_installed() {
  setup
  # The shipped file, not the suite's fixture. setup() points TEEUP_MENU_FILE
  # at a temp path and lib/menu.sh only defaults it at source time, so it is
  # set here rather than unset.
  export TEEUP_MENU_FILE="$TEEUP_PATH/share/teeup/menu.json"
  local cache id
  cache="$(menu_cache)"
  # Every Install leaf asks `! teeup has <cap>`, so the list shrinks as the
  # machine fills up. A row with an action and no `when` under install. is the
  # mistake this catches.
  for id in $(menu_ids "$cache" | grep '^install\.'); do
    if [[ -n "$(menu_field "$cache" "$id" action)" ]]; then
      case "$(menu_field "$cache" "$id" action)" in
        "teeup install dev-env "*) continue ;;
      esac
      if [[ -z "$(menu_field "$cache" "$id" when)" ]]; then
        echo "install row without a when: $id"
        return 1
      fi
    fi
  done
  cleanup_test_env
}

run_test "the shipped menu reaches every installable capability" test_the_shipped_menu_reaches_every_installable_capability
run_test "the shipped menu hides an install row once installed" test_the_shipped_menu_hides_an_install_row_once_it_is_installed
print_summary
```

- [ ] **Step 2: Run it to watch it fail**

Run: `bash tests/lib/menu.sh 2>&1 | tail -8`
Expected: `the shipped menu reaches every installable capability` FAILs, naming all twenty capabilities as missing. The second test passes already, because every shipped Install leaf phase 4b wrote does have a `when`.

- [ ] **Step 3: Replace the Apps block with the three grouped submenus**

```json edit-old=share/teeup/menu.json
  "install.apps": {"label": "Apps"},
  "install.apps.firefox": {"label": "Firefox Developer Edition", "when": "! teeup has firefox-developer-edition", "action": "teeup install firefox-developer-edition"},
  "install.apps.chrome": {"label": "Google Chrome", "when": "! teeup has chrome", "action": "teeup install chrome"},
  "install.apps.obsidian": {"label": "Obsidian", "when": "! teeup has obsidian", "action": "teeup install obsidian"},
```

```json edit-new=share/teeup/menu.json
  "install.browsers": {"label": "Browsers"},
  "install.browsers.firefox": {"label": "Firefox Developer Edition", "when": "! teeup has firefox-developer-edition", "action": "teeup install firefox-developer-edition"},
  "install.browsers.chrome": {"label": "Google Chrome", "when": "! teeup has chrome", "action": "teeup install chrome"},
  "install.browsers.brave": {"label": "Brave", "when": "! teeup has brave", "action": "teeup install brave"},
  "install.browsers.arc": {"label": "Arc", "when": "! teeup has arc", "action": "teeup install arc"},
  "install.browsers.zen": {"label": "Zen", "when": "! teeup has zen", "action": "teeup install zen"},

  "install.communication": {"label": "Communication"},
  "install.communication.slack": {"label": "Slack", "when": "! teeup has slack", "action": "teeup install slack"},
  "install.communication.zoom": {"label": "Zoom", "when": "! teeup has zoom", "action": "teeup install zoom"},
  "install.communication.teams": {"label": "Microsoft Teams", "when": "! teeup has teams", "action": "teeup install teams"},
  "install.communication.signal": {"label": "Signal", "when": "! teeup has signal", "action": "teeup install signal"},
  "install.communication.whatsapp": {"label": "WhatsApp", "when": "! teeup has whatsapp", "action": "teeup install whatsapp"},
  "install.communication.telegram": {"label": "Telegram", "when": "! teeup has telegram", "action": "teeup install telegram"},
  "install.communication.discord": {"label": "Discord", "when": "! teeup has discord", "action": "teeup install discord"},

  "install.productivity": {"label": "Productivity"},
  "install.productivity.obsidian": {"label": "Obsidian", "when": "! teeup has obsidian", "action": "teeup install obsidian"},
  "install.productivity.onepassword": {"label": "1Password", "when": "! teeup has 1password", "action": "teeup install 1password"},
  "install.productivity.raycast": {"label": "Raycast", "when": "! teeup has raycast", "action": "teeup install raycast"},
  "install.productivity.bruno": {"label": "Bruno", "when": "! teeup has bruno", "action": "teeup install bruno"},
  "install.productivity.notion": {"label": "Notion", "when": "! teeup has notion", "action": "teeup install notion"},
  "install.productivity.typora": {"label": "Typora", "when": "! teeup has typora", "action": "teeup install typora"},
```

- [ ] **Step 4: Add the containers and macOS rows**

```json edit-old=share/teeup/menu.json
  "install.shell": {"label": "Shell and containers"},
  "install.shell.tmux": {"label": "tmux", "when": "! teeup has tmux", "action": "teeup install tmux"},
  "install.shell.colima": {"label": "Docker through Colima", "when": "! teeup has colima", "action": "teeup install colima"},
```

```json edit-new=share/teeup/menu.json
  "install.shell": {"label": "Shell and containers"},
  "install.shell.tmux": {"label": "tmux", "when": "! teeup has tmux", "action": "teeup install tmux"},
  "install.shell.colima": {"label": "Docker through Colima", "when": "! teeup has colima", "action": "teeup install colima"},
  "install.shell.k8s": {"label": "Kubernetes tools", "when": "! teeup has k8s", "action": "teeup install k8s"},
  "install.shell.lazydocker": {"label": "lazydocker", "when": "! teeup has lazydocker", "action": "teeup install lazydocker"},
  "install.shell.dbs": {"label": "Databases on Colima", "when": "! teeup has docker-dbs", "action": "teeup install docker-dbs"},

  "install.system": {"label": "macOS extras"},
  "install.system.karabiner": {"label": "Karabiner-Elements", "when": "! teeup has karabiner", "action": "teeup install karabiner"},
  "install.system.xcode": {"label": "Xcode from the App Store", "when": "! teeup has xcode", "action": "teeup install xcode"},
```

- [ ] **Step 5: Add the launch rows for the apps those capabilities install**

```json edit-old=share/teeup/menu.json
  "launch.aerospace": {"label": "AeroSpace", "action": "teeup launch AeroSpace"},
```

```json edit-new=share/teeup/menu.json
  "launch.aerospace": {"label": "AeroSpace", "action": "teeup launch AeroSpace"},
  "launch.brave": {"label": "Brave", "when": "teeup has brave", "action": "teeup launch Brave Browser"},
  "launch.arc": {"label": "Arc", "when": "teeup has arc", "action": "teeup launch Arc"},
  "launch.zen": {"label": "Zen", "when": "teeup has zen", "action": "teeup launch Zen"},
  "launch.slack": {"label": "Slack", "when": "teeup has slack", "action": "teeup launch Slack"},
  "launch.zoom": {"label": "Zoom", "when": "teeup has zoom", "action": "teeup launch zoom.us"},
  "launch.teams": {"label": "Microsoft Teams", "when": "teeup has teams", "action": "teeup launch Microsoft Teams"},
  "launch.signal": {"label": "Signal", "when": "teeup has signal", "action": "teeup launch Signal"},
  "launch.onepassword": {"label": "1Password", "when": "teeup has 1password", "action": "teeup launch 1Password"},
  "launch.raycast": {"label": "Raycast", "when": "teeup has raycast", "action": "teeup launch Raycast"},
  "launch.bruno": {"label": "Bruno", "when": "teeup has bruno", "action": "teeup launch Bruno"},
  "launch.notion": {"label": "Notion", "when": "teeup has notion", "action": "teeup launch Notion"},
  "launch.typora": {"label": "Typora", "when": "teeup has typora", "action": "teeup launch Typora"},
  "launch.xcode": {"label": "Xcode", "when": "teeup has xcode", "action": "teeup launch Xcode"},
  "launch.karabiner": {"label": "Karabiner-Elements", "when": "teeup has karabiner", "action": "teeup launch Karabiner-Elements"},
```

Every app name in a `launch` action is the first `apps=` entry of that capability's metadata, which is the bundle name `open -a` takes: `zoom.us` rather than `Zoom`, `Brave Browser` rather than `Brave`, `Karabiner-Elements` rather than `Karabiner`. Phase 4c checked each against `https://formulae.brew.sh/api/cask/<token>.json`; if a name here disagrees with `capabilities/<cap>/capability`, the metadata is right and this file is wrong.

- [ ] **Step 6: Run the tests**

Run: `bash tests/lib/menu.sh 2>&1 | tail -6`
Expected: both new tests `PASS`; no failures.

Run: `./bin/teeup dev check 2>&1 | grep -A2 'menu definition'`
Expected: the menu lint reports no problem.

Run: `./tests/run.sh 2>&1 | tail -1`
Expected: `All N suites passed.` with N unchanged from Task 2.

Run: `./bin/teeup commands --check && git diff --check`
Expected: no output from either.

- [ ] **Step 7: Commit**

```bash
git add share/teeup/menu.json tests/lib/menu.sh
git commit -m "Give every lazy capability a menu row"
```

**Real-Mac risk:** the `launch` rows are the only part hardware can disprove — `teeup launch zoom.us` opens the right bundle only if `zoom.us.app` is what the cask installs. Phase 4c verified every one of those names against the cask API and this task copies them rather than re-deriving them, so a mismatch means phase 4c's metadata is wrong and both need the same fix.

---

### Task 4: `docs/legacy-parity.md`, the phase 5 gate

**Files:**
- Create: `docs/legacy-parity.md`
- Modify: `share/agents/skills/teeup/SKILL.md` (one pointer, now that the file exists)
- Modify: `tests/docs.sh` (the parity checks)

**Interfaces:**
- Consumes: `legacy/teeup.sh --list-modules` and `legacy/teeup.sh --help`, both read once here and transcribed; `capabilities/` for the names the checklist maps to.
- Produces: `docs/legacy-parity.md`, with a machine-readable region between `<!-- parity-map -->` and `<!-- /parity-map -->` whose second column holds only backticked capability names or the plain word `dropped` — nothing else, and `tests/docs.sh`'s check enforces the "nothing else": it is not satisfied by finding a backticked name somewhere in the cell, an unquoted word left over (a typo that lost its backticks) fails it too. The README's "Coming from an older setup" section and CONTRIBUTING's layout table already point at this file; the skill gains its pointer here. **The deletion task must not run before this one:** the checklist is the spec's gate for phase 5, and it is written from a tree that still has `legacy/` in it.

**Get the list from the program, not from memory.** Before writing the document, run the command the spec's gate names and keep the output:

Run: `./legacy/teeup.sh --list-modules`
Expected:

```text
Available modules:
  homebrew  - Package manager setup (compatibility module name; resolves by OS)
  shell     - Configure your login shell (zsh: Powerlevel10k + plugins; bash: bash-completion + Starship)
  zsh       - Force zsh setup (Powerlevel10k + plugins)
  ohmyzsh   - Legacy alias for zsh with ZSH_MODE=ohmyzsh
  bash      - Force bash setup (bash-completion + Starship)
  cli       - Core CLI utilities (git, jq, ripgrep, etc.)
  python    - Python environment (UV or pyenv/poetry)
  java      - SDKMAN! + Java + Maven/Gradle
  ruby      - Ruby via rbenv + RubyGems + Bundler
  rust      - Rust toolchain via rustup
  emacs     - Emacs editor + minimal config
  docker    - Docker runtime + CLI (Colima on macOS, distro packages on Linux)
  apps      - GUI apps (Bruno, Obsidian; macOS-only currently)
```

Run: `./legacy/teeup.sh --help`
Expected: the option and environment-variable lists the document's second and third tables transcribe. If either command prints something this plan does not, the document is what changes — the program is the authority while it still exists.

- [ ] **Step 1: Write the checklist**

````markdown file=docs/legacy-parity.md
# Legacy parity checklist

The previous installer was one 2,292-line `teeup.sh` plus a 1,704-line
`teeup-wizard.sh`, a `lib/` and a `templates/` tree and four test scripts —
6,968 lines in all — driven by thirteen module toggles. This document records
what each of those modules did and where it went, and it is the gate the
redesign's phase 5 had to pass before `legacy/` could be deleted. It is
written in the past tense on purpose: the programs it describes are no longer
in the repository, and this is the only record of them that remains.

The module list is the verbatim output of `./legacy/teeup.sh --list-modules`,
taken from the tree at the commit before the deletion.

## Modules

<!-- parity-map -->

| Legacy module | Replaced by | What changed |
|---|---|---|
| `homebrew` | `package-manager` | Same job, same two backends. Homebrew by default, MacPorts on macOS 12 and older or when `machines/<hostname>.conf` sets `TEEUP_PACKAGE_MANAGER=macports`. The Linux backends (`apt`, `dnf`, `pacman`) are gone: teeup is macOS only now, and the chezmoi repository keeps serving Linux. |
| `shell` | `zsh` `starship` | The login shell is zsh, always. The old module could configure bash instead (`TARGET_SHELL`, `--only bash`) and installed Powerlevel10k or Starship only when `--prompt` asked; the new pair always installs Starship and a layered zsh configuration whose thin `~/.zshrc`, `~/.zprofile` and `~/.zshenv` source teeup's `default/` layer. `~/.teeup.common`, the shared init file both shells sourced, is gone; `teeup migrate legacy` removes it. |
| `zsh` | `zsh` `starship` | The forced-zsh alias of `shell`. There is nothing left to force. |
| `ohmyzsh` | dropped | Oh My Zsh is not installed by teeup any more (design interview: "Plain zsh, Omarchy-style layered default … No Oh My Zsh"). Its git aliases live in `capabilities/git/config/git/config` instead, its completions come from zsh's own `compinit` plus the tools' shipped completions, and `zsh-autosuggestions` and `zsh-syntax-highlighting` are sourced directly by the zsh layer. `teeup doctor` reports an `~/.oh-my-zsh` directory left over from before. |
| `bash` | dropped | macOS ships bash 3.2 and has defaulted to zsh since Catalina. teeup's runtime is still written in bash 3.2 so that `bootstrap` runs on a bare Mac, but it no longer offers to configure bash as your login shell. |
| `cli` | `cli-tools` `git` `github` `tmux` | The old list was `git wget curl jq htop tree tmux ripgrep fd gnupg`. `cli-tools` now installs `ripgrep fd fzf bat eza zoxide jq yq btop tree wget curl gnupg tldr dust`: `htop` became `btop`, and `fzf`, `bat`, `eza`, `zoxide`, `yq`, `tldr` and `dust` are new. `git` moved to its own capability, whose `packages=` is `git git-delta git-lfs lazygit`; `gh` moved to `github`; `pre-commit` comes from `mise`. `tmux` is a lazy capability, because WezTerm's panes cover the multiplexing this setup actually used. |
| `python` | `mise` | pyenv, pyenv-virtualenv, pipx and poetry are gone, and so is the `USE_UV=false` branch that installed them. Python comes from `teeup install dev-env python`, which pins a version through mise and installs `uv` with it. `PYTHON_VERSION` has no successor: mise's global config holds the version, and `mise use --global python@3.13` changes it. |
| `java` | `mise` | SDKMAN is gone, including the login-shell spawning the old module needed to source it. Java comes from `teeup install dev-env java`, and the `javav` shell function switches the version for one shell. Maven and Gradle are mise tools rather than SDKMAN candidates. `JDK_VERSION` has no successor, for the same reason as `PYTHON_VERSION`. |
| `ruby` | `mise` | rbenv is gone. Ruby comes from `teeup install dev-env ruby`, which pins `ruby@latest` in mise's global config and leaves gem management to Ruby: RubyGems and Bundler ship with the interpreter mise installs, and teeup runs neither `gem update --system` nor `gem install bundler` on your behalf. `RUBY_VERSION` and `BUNDLER_VERSION` have no successor. |
| `rust` | `mise` | `teeup install dev-env rust` goes through mise's rust backend, which uses rustup underneath, so the toolchain management is the same and the bootstrap no longer pipes `https://sh.rustup.rs` into a shell. |
| `emacs` | `emacs` | Now a daily-tier capability with a `sh.teeup.emacs` LaunchAgent running the daemon, four configurations behind `TEEUP_EMACS_FLAVOR` (`starter`, `doom`, `spacemacs`, `none`), a themed template and a `theme-apply` hook that reloads a running daemon. The old module installed the `emacs-app` cask and copied a fixed `init.el`. |
| `docker` | `colima` `docker-dbs` `lazydocker` | Colima and the Docker CLI are a lazy capability reached by a `docker` shim: the first `docker ps` on a new Mac offers to install it. `docker-dbs` starts local database containers on it, and `lazydocker` is the TUI. The Linux half of the old module (distro packages, docker group membership) is gone with the rest of the Linux support. |
| `apps` | `bruno` `obsidian` | The two casks the old module installed are now capabilities of their own: `obsidian` is in the daily tier and `bruno` is lazy, alongside every other GUI capability phases 3 and 4 added (browsers, communication, productivity, Karabiner, Xcode). `teeup list --tier lazy` is the current list. `INSTALL_BRUNO` and `INSTALL_OBSIDIAN` have no successor: install what you want, when you want it. |

<!-- /parity-map -->

## Command-line options

| Legacy option | Where it went |
|---|---|
| `--help` | `teeup help`, generated from the verb list rather than a here-doc. |
| `--dry-run` | `DRY_RUN=true` in front of any command, and `./bootstrap --dry-run`. Every mutation goes through one seam (`run_cmd` or a guarded file primitive), so the preview is the real code path rather than a second set of strings. |
| `--profile base\|full`, `--all` | The three tiers. Core is the base, `--skip-daily` is the way to get core alone, and everything past that is lazy rather than a profile. |
| `--prompt none\|powerlevel10k\|starship` | Dropped. Starship is the prompt; Powerlevel10k is not installed, and `teeup doctor` reports remnants of one. |
| `--only MODULES` | `teeup install <capability>`, one at a time, and `teeup list` to see what there is. |
| `--except MODULES` | `TEEUP_SKIP="<capability> …"` in `machines/<hostname>.conf`, which also removes that capability's lazy shims. |
| `--init-dotfiles [DIR]`, `--dotfiles PATH\|URL`, `--dotfiles-manager M` | Dropped, and replaced by the shipped-config model: `capabilities/<cap>/config/` is copied into `~/.config` once and is yours afterwards, `home/` the same for dotfiles in `$HOME`, and `default/` stays teeup's. There is no overlay repository to point at, no chezmoi or Stow hand-off, and no auto-adoption of a sibling `../dotfiles`. A machine that still has a chezmoi-managed home is handled by `teeup migrate legacy`. |
| `--migrate-to-uv` | Dropped. There is no pyenv installation to migrate from, because teeup never creates one; `teeup migrate legacy` neutralises a pyenv init line left in a shell file by the old installer. |
| `--strict-platform` | Dropped. There is one platform. |
| `--reconcile-existing-config`, `--no-reconcile-existing-config` | `teeup migrate legacy`, which does the same work (disabling Antigen, SDKMAN, rbenv and pyenv init lines) as an explicit verb rather than a flag that could fire as a side effect of an install. |
| `--list-modules` | `teeup list`, which reads the capability metadata instead of a hand-maintained function, and takes `--tier core\|daily\|lazy`. |

## Environment variables

| Legacy variable | Where it went |
|---|---|
| `TEEUP_PROFILE` | The tiers, and `TEEUP_DAILY` in the answers file for whether the daily tier runs at bootstrap. |
| `PYTHON_VERSION`, `JDK_VERSION`, `RUBY_VERSION`, `BUNDLER_VERSION` | Dropped; mise's global config holds every runtime version. |
| `USE_UV` | Dropped; `uv` always comes with `teeup install dev-env python`. |
| `RUBYGEMS_UPDATE` | Dropped. The Ruby mise installs brings its own RubyGems, and `gem update --system` is the user's call. |
| `ZSH_MODE` | Dropped with Oh My Zsh. |
| `PROMPT` | Dropped; the prompt is Starship. |
| `TARGET_SHELL` | Dropped; the login shell is zsh. |
| `PACKAGE_MANAGER` | `TEEUP_PACKAGE_MANAGER`, asked once by the bootstrap wizard and pinnable in `machines/<hostname>.conf`. |
| `STRICT_PLATFORM` | Dropped with `--strict-platform`. |
| `INSTALL_DOTFILES`, `DOTFILES_DIR`, `DOTFILES_MANAGER` | Dropped with the dotfiles overlay. |
| `ALLOW_HOMEBREW_CASK_FALLBACK`, `CLEANUP_HOMEBREW_OVERLAPS` | Dropped. A MacPorts machine skips casks with a note and says what to install by hand; teeup does not uninstall another package manager's packages. |
| `UPGRADE_HOMEBREW` | `teeup update`, which upgrades formulae and casks as one of its steps. |
| `RECONCILE_EXISTING_CONFIG` | `teeup migrate legacy`. |
| `TUNE_DEFAULTS` | The `macos-defaults` capability, which is in the core tier and on by default, records the previous value of every key it writes, and puts them all back on `teeup remove macos-defaults`. |
| `DRY_RUN` | Unchanged, and now covering every mutation rather than the ones somebody remembered to wrap. |

## The wizard

`teeup-wizard.sh` was 1,400 lines of screens that set the environment variables
above and then ran `teeup.sh`. It is replaced by two things: the six questions
`bootstrap` asks once, whose answers live in `~/.config/teeup/answers` and are
editable with `teeup config`, and `teeup menu`, which is generated from
`share/teeup/menu.json` and covers installing, launching, theming and checking.
`lib/ui.sh` holds the prompts both of them use, with gum where it is installed
and a plain read where it is not, so there is no second implementation of a
question anywhere in the tree.

## What has no successor, deliberately

- **Linux.** apt, dnf and pacman backends, the docker group, distro package
  name tables. Omarchy covers Arch and the chezmoi repository covers
  Ubuntu and Fedora; teeup is macOS only.
- **Oh My Zsh, SDKMAN, rbenv, pyenv, pipx and poetry.** Each was a second
  version manager layered under the shell. mise replaces all of them, and
  `teeup migrate legacy` disables the init lines they left behind.
- **Powerlevel10k.** Starship is the prompt, and `teeup doctor` reports a
  leftover `~/.p10k.zsh`.
- **The dotfiles overlay** (`--dotfiles`, `--init-dotfiles`, chezmoi and Stow
  hand-off, `../dotfiles` auto-adoption). Capabilities ship their own config
  now.
- **`~/.teeup.common`, `~/.teeupshrc` and `~/.config/mac-setup`.** All three
  were teeup's own invented locations. `teeup migrate legacy` removes them.
- **Module toggles as environment variables.** The old runtime was configured
  entirely by exported variables; the new one has an answers file, a machine
  file, and verbs.
````

- [ ] **Step 2: Point the skill at it**

```markdown edit-old=share/agents/skills/teeup/SKILL.md
- `CONTRIBUTING.md` — the long form of the capability rules, the code style and
  the test conventions.
- `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md` — why
```

```markdown edit-new=share/agents/skills/teeup/SKILL.md
- `CONTRIBUTING.md` — the long form of the capability rules, the code style and
  the test conventions.
- `docs/legacy-parity.md` — what the previous installer did and where each part
  of it went. Read it before "teeup used to …" turns into a guess.
- `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md` — why
```

- [ ] **Step 3: Add the parity checks**

```bash edit-old=tests/docs.sh
echo "docs.sh"
```

```bash edit-new=tests/docs.sh
PARITY="$REPO/docs/legacy-parity.md"

# parity_rows: the table rows between the markers, each one
# "| `<module>` | <capability cell> | <prose> |".
parity_rows() {
  sed -n '/<!-- parity-map -->/,/<!-- \/parity-map -->/p' "$PARITY" | grep '^| `'
}

test_the_parity_checklist_has_a_row_for_every_legacy_module() {
  assert_file_exists "$PARITY" "the parity checklist is in docs/" || return 1
  # The verbatim module list from `legacy/teeup.sh --list-modules`, frozen here
  # because the command that produced it is deleted in the next task.
  local missing="" m rows
  # The rows are captured once. `something | grep -q` would be a race under
  # `set -o pipefail`: grep exits on the first match, the upstream command gets
  # SIGPIPE, and the pipeline reports a failure that depends on the pipe buffer.
  rows="$(parity_rows)"
  for m in homebrew shell zsh ohmyzsh bash cli python java ruby rust emacs docker apps; do
    if ! grep -qF "| \`$m\` |" <<<"$rows"; then
      missing="$missing $m"
    fi
  done
  assert_equals "" "$missing" "every legacy module has a row" || return 1
  assert_equals "13" "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" "thirteen rows, one per module" || return 1
}

test_the_parity_checklist_names_only_capabilities_that_exist() {
  local bad="" row cell trimmed leftover name
  while IFS= read -r row; do
    # The second cell: everything between the first and second "|" after the
    # module name. It has to be exactly the word dropped, or one or more
    # backticked capability names and nothing else -- an unquoted word left
    # over once every `name` span is stripped out is a typo that lost its
    # backticks, and grep -oE alone would silently skip right over it.
    cell="$(printf '%s' "$row" | awk -F'|' '{print $3}')"
    trimmed="$(printf '%s' "$cell" | tr -d ' ')"
    if [[ -z "$trimmed" ]]; then
      bad="$bad empty-cell"
      continue
    fi
    if [[ "$trimmed" == "dropped" ]]; then
      continue
    fi
    leftover="$trimmed"
    for name in $(printf '%s' "$trimmed" | grep -oE '`[a-z0-9][a-z0-9.-]*`' | tr -d '`'); do
      if [[ ! -d "$REPO/capabilities/$name" ]]; then
        bad="$bad $name"
      fi
      leftover="${leftover//\`$name\`/}"
    done
    if [[ -n "$leftover" ]]; then
      bad="$bad unquoted:$leftover"
    fi
  done <<PARITY_ROWS
$(parity_rows)
PARITY_ROWS
  assert_equals "" "$bad" "every replacement cell is dropped, or backticked capability names that all exist" || return 1
}

echo "docs.sh"
```

```bash edit-old=tests/docs.sh
run_test "the skill marks the generated and borrowed trees read-only" test_the_skill_marks_the_generated_and_borrowed_trees_read_only
print_summary
```

```bash edit-new=tests/docs.sh
run_test "the skill marks the generated and borrowed trees read-only" test_the_skill_marks_the_generated_and_borrowed_trees_read_only
run_test "the parity checklist has a row for every legacy module" test_the_parity_checklist_has_a_row_for_every_legacy_module
run_test "the parity checklist names only capabilities that exist" test_the_parity_checklist_names_only_capabilities_that_exist
print_summary
```

- [ ] **Step 4: Run the docs suite**

Run: `bash tests/docs.sh`
Expected: six tests, `Summary: 6/6 passed`. A failure in
`names only capabilities that exist` prints the name it could not find under
`capabilities/`, which means either the checklist is wrong or a capability was
renamed after it was written.

- [ ] **Step 5: Run everything**

Run: `./tests/run.sh 2>&1 | tail -1`
Expected: `All N suites passed.`, N unchanged from Task 3 — this task adds
tests to an existing suite rather than a suite.

Run: `./bin/teeup commands --check && shellcheck --severity=warning tests/docs.sh && git diff --check`
Expected: no output from any of the three.

- [ ] **Step 6: Commit**

```bash
git add docs/legacy-parity.md share/agents/skills/teeup/SKILL.md tests/docs.sh
git commit -m "Record the legacy parity checklist"
```

**Real-Mac risk:** none. The risk this task carries is a wrong claim rather than
a broken command: a row that says something moved to a capability that does not
actually do that job would let the next task delete code nothing replaced. The
test proves the capability exists, not that it does the same work, so read each
row against the capability's `install` and `configure` before signing it off —
that reading is the gate, and it is the last chance to take it.

---

### Task 5: `README.md`, rewritten against the runtime that exists

**Files:**
- Modify: `README.md` (replaced whole)
- Modify: `CHANGELOG.md` (one `[Unreleased]` entry)
- Modify: `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md` (the `teeup list` line of the CLI-surface block)
- Modify: `tests/docs.sh` (the README checks)

**Interfaces:**
- Consumes: `./bin/teeup help` (every verb), `capabilities/{core,daily}.list`, `share/agents/skills/teeup/SKILL.md` (Task 1), the `agent_skill_link` behaviour (Task 2), the menu rows (Task 3), `docs/legacy-parity.md` (Task 4).
- Produces: the region between `<!-- teeup-commands -->` and `<!-- /teeup-commands -->` in `README.md`, which `tests/docs.sh` reads as the canonical command table.

The README is replaced rather than patched. Phases 1 to 5a each appended a section to a document whose last 638 lines, from `## ✨ Features` to the end, are still the old installer's manual: `--only python`, `ZSH_MODE=ohmyzsh`, `--migrate-to-uv`, a Bruno tutorial, an Oh My Zsh alias table and a "Trust Model" listing SDKMAN and Oh My Zsh endpoints teeup no longer touches. Patching that leaves the seams; replacing it is also the only way to get the order right, because a reader currently meets `teeup doctor` a third of the way down and `./legacy/teeup.sh --all` half way.

**Before you write it, read what is there.** This plan reproduces the sections phases 3a, 3b, 4a, 4b, 4c and 4d wrote, because they are good and because a rewrite that drops them would be a regression. If the file on disk when you start says something these sections do not — a paragraph phase 5a's Task 9 added about `teeup migrate legacy`, a bullet a review added — fold it in rather than dropping it. `git show HEAD:README.md` is how to check.

- [ ] **Step 1: Write the README**

````markdown file=README.md
<p align="center">
  <img src="assets/teeup_logo.png" alt="teeup.sh logo" width="520">
</p>

<h1 align="center">
  <img src="assets/teeup_emoji.png" alt="" width="32" height="32">
  teeup.sh
</h1>

<p align="center">
  Get your new machine ready for the first drive.
</p>

teeup turns a fresh Mac into a working machine, and keeps it that way. It is a
git checkout plus one command. macOS only: the Linux half of this setup lives
in a separate chezmoi repository and teeup never touches it.

Three ideas carry the whole design:

- **Three trees, three owners.** The checkout is teeup's, `~/.config` and your
  dotfiles are yours, and `~/.local/state/teeup` is generated. teeup copies a
  config file into your home exactly once and never writes it again; the thin
  file it leaves there sources a thick default that stays in the checkout, so
  `git pull` improves the defaults without touching anything you edited.
- **Capabilities, in three tiers.** Every tool is a directory under
  `capabilities/` with a metadata file and two scripts. Core capabilities run
  at bootstrap, daily ones run at bootstrap if you want them, and everything
  else is lazy: nothing is downloaded until the first time you reach for it.
- **State is a file you can read.** Whether something is installed is the
  presence of a file under `~/.local/state/teeup/done/`; what your theme is, is
  the content of one line. Nothing runs in the background to keep that true.

## Install

```bash
git clone https://github.com/systemhalted/teeup.sh ~/.local/share/teeup
cd ~/.local/share/teeup
./bootstrap --dry-run     # print every command instead of running it
./bootstrap               # run it
```

`bootstrap` is the only entry point on a fresh Mac. It needs nothing beyond
macOS, it is safe to rerun, and it takes three flags: `--dry-run`,
`--reconfigure` (ask the setup questions again) and `--skip-daily` (core tier
only this run). It installs the Xcode Command Line Tools and Rosetta 2 where
needed, then Homebrew — or MacPorts on macOS 12 and older, or when
`machines/<hostname>.conf` says so — then the teeup runtime, then asks you:

| Question | Answer key |
|---|---|
| Your full name | `TEEUP_NAME` |
| Email, your one git identity | `TEEUP_EMAIL` |
| Theme | `TEEUP_THEME` |
| Install the daily set too? | `TEEUP_DAILY` |
| Emacs flavor, when the daily set is on | `TEEUP_EMACS_FLAVOR` |

The answers land in `~/.config/teeup/answers` and are yours to change with
`teeup config set` or `./bootstrap --reconfigure`. A question whose answer is
pinned by `machines/<hostname>.conf` is not asked, because the answer would
never be read. Work is never asked here at all: a work identity is a
per-machine setting, not a question, and it belongs in
`machines/<hostname>.conf` (see "Per-machine overrides" below).

After a new login shell, `teeup` is on your `PATH` through `~/.local/bin`.
Until then it is `~/.local/bin/teeup`.

## The commands

<!-- teeup-commands -->

| Command | What it does |
|---|---|
| `teeup install <capability>` | install and configure it, and whatever it requires |
| `teeup install dev-env <lang>` | `python`, `node`, `java`, `ruby`, `rust` or `go`, through mise |
| `teeup install font <name>` | install a Nerd Font and point every tool at it; `font list` names them |
| `teeup configure <capability>` | re-run only its configuration |
| `teeup update [<capability>]` | pull, migrate, upgrade packages, re-configure, re-theme |
| `teeup reset <capability>` | put its config files back to the shipped version, keeping backups |
| `teeup remove <capability>` | undo what a capability installed |
| `teeup list [--tier core\|daily\|lazy]` | every capability, its tier and its summary |
| `teeup status` | package manager, answers, installed capabilities, shims, dev-envs |
| `teeup doctor [<capability>]` | check what is installed and print the command that fixes what is not |
| `teeup menu [<id>]` | every teeup action as a keyboard-driven list |
| `teeup theme set\|list\|current` | apply, list or print the cross-tool theme |
| `teeup launch <app\|capability>` | open a GUI app, installing its cask first if it is missing |
| `teeup lazy-run <cap> <cmd> [args]` | what a lazy shim runs: install on first use, then exec |
| `teeup config get\|set\|edit` | read or change the answers file |
| `teeup has <capability>` | exit 0 when it is installed; for scripts and menu conditions |
| `teeup secret get\|set\|rm <name>` | read, store or delete a macOS Keychain secret |
| `teeup migrate legacy` | move this Mac off the old `teeup.sh` or chezmoi setup |
| `teeup dev new-capability <name>` | scaffold `capabilities/<name>` and its test |
| `teeup dev add-migration` | start `migrations/<epoch>.sh` for machines already set up |
| `teeup dev check [<capability>]` | metadata, menu, shellcheck and the tests |
| `teeup commands --check` | lint the capability metadata |
| `teeup version` | the contents of `version` |
| `teeup help` | this list |

<!-- /teeup-commands -->

`DRY_RUN=true` in front of any of them prints what would happen and changes
nothing.

## What bootstrap installs

**Core**, in this order: `xcode-clt`, `package-manager`, `teeup-runtime`,
`dev-dirs` (`~/Work`), `zsh`, `starship`, `cli-tools`,
`secrets`, `git`, `ssh`, `github`, `mise`, `wezterm`, `fonts`, `aerospace`,
`keyboard`, `macos-defaults`, `theme`.

**Daily**, when you say yes: `emacs`, `zed`, `firefox-developer-edition`,
`obsidian`.

**Lazy**, which is everything else: shims are in place and nothing is
downloaded. `teeup list --tier lazy` is the list, and it is always the source
of truth — this README is not.

### Finding your way around

`teeup menu` puts every action behind one list. It uses `gum` when gum is
installed, `fzf` when it is not, and a plain numbered list when neither is
there, so it works over ssh and inside a script. `teeup menu install` opens
straight at the Install submenu; an empty line, `q` or Escape goes back a
level, and again at the top level to leave.

The menu is `share/teeup/menu.json`: one JSON object whose keys are dotted
ids, so `install.browsers.brave` is a row under `install.browsers`. Each row is
an object of one-line strings:

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
commit signing is on, the theme template that has never been rendered, the
agent skill that is not linked. The summary at the end names each failure and
the single command that fixes it. `teeup doctor <capability>` checks one,
installed or not.

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
installed: each has a themed template that names the theme for the palette and
a hook that tells a running editor to pick it up.

### Themes

Every theme is a dark and a light palette; apps follow the macOS appearance
between the two. `teeup theme list` shows what is available and
`teeup theme set <name>` switches every app at once. Each palette also names
the theme each tool should load:

| Theme | Palettes | bat | Emacs | Zed | Neovim | VS Code |
|---|---|---|---|---|---|---|
| `catppuccin` | Mocha, Latte | `OneHalfDark`, `OneHalfLight` | `modus-vivendi`, `modus-operandi` | Catppuccin Mocha, Latte (extension `catppuccin`) | `catppuccin-mocha`, `catppuccin-latte` | Catppuccin Mocha, Latte (`Catppuccin.catppuccin-vsc`) |
| `everforest` | dark, light (medium contrast) | `base16` | `modus-vivendi`, `modus-operandi-tinted` | Everforest Dark Medium (regular), Everforest Light Medium (regular) (extension `everforest`) | `everforest` | Everforest Dark, Everforest Light (`sainnhe.everforest`) |
| `gruvbox` | dark, light (medium contrast) | `gruvbox-dark`, `gruvbox-light` | `modus-vivendi`, `modus-operandi-tinted` | Gruvbox Dark, Gruvbox Light (built in) | `gruvbox` | Gruvbox Dark Medium, Gruvbox Light Medium (`jdinhlife.gruvbox`) |
| `tokyo-night` | night, day | `base16` | `modus-vivendi-tinted`, `modus-operandi` | Tokyo Night, Tokyo Night Light (extension `tokyo-night`) | `tokyonight-night`, `tokyonight-day` | Tokyo Night, Tokyo Night Light (`enkia.tokyo-night`) |

- **bat** gets `base16` when it ships no theme for the palette: `base16`
  draws with the terminal's sixteen colours, which WezTerm takes from the
  same palette.
- **Emacs** gets a theme built into Emacs, because the starter configuration
  installs no packages; Doom and Spacemacs keep the theme their own
  configuration picks. The tinted Modus themes need Emacs 30.1 or later; an
  older Emacs falls back to its default colours and says why in
  `*Messages*`.
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

### Fonts

`teeup install font <name>` installs a Nerd Font and points WezTerm, Zed, VS
Code and Neovim at it in one go; the family name lands in
`~/.local/state/teeup/current/font` and each tool's `font-apply` hook tells it
to reload. `teeup install font list` prints the names teeup knows, which are
JetBrainsMono (the bootstrap default), Cascadia Mono, Fira Code, Hack and
Meslo. Names are matched loosely, so `fira-code`, `FiraCode` and
`FiraCode Nerd Font` all reach the same cask.

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
  run `teeup install ai` still works. Its `configure` writes
  `~/.local/bin/{claude,codex,gemini,copilot,opencode}`: small wrappers that
  install the tool through mise on their first call (`gemini` brings Node with
  it) and run it through `mise x` after that, so `mise upgrade` keeps them
  current. A command already at one of those paths that teeup did not write,
  such as the `claude` launcher from Claude Code's own installer, is kept.
- **Shipped lazy capabilities:** `colima` (Colima, the Docker CLI and the
  Compose plugin; `docker` and `colima` shims), `ai`, `herdr`, `tmux` (with a
  `~/.config/tmux/tmux.conf` that is yours after the first copy, skipped when
  you already have a `~/.tmux.conf`), `ollama` (app and CLI, no models) and
  `cursor` (app and `cursor` command), and:
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

### Keeping a Mac up to date

```bash
teeup update                   # the whole machine
DRY_RUN=true teeup update      # ... as a preview that changes nothing
teeup update wezterm           # one capability: its packages, then its configure
teeup reset starship           # the shipped starship.toml back, your copy backed up
teeup remove cursor            # undo what a capability installed
```

`teeup update` does the list in order: `git pull --ff-only` in the checkout,
any pending migrations, `brew update && brew upgrade && brew upgrade --cask`
(or `port selfupdate && port upgrade outdated`), `mise upgrade`, `configure`
again for every installed core capability, the theme re-rendered, and your
`post-update` hooks. A checkout with uncommitted changes stops it before
anything else runs, and so does a migration that fails; every other problem is
a warning, and the command exits non-zero when there was one. Offline, the
pull and the package manager warn and the rest still runs, which makes
`teeup update` the repair path for a bootstrap that stopped half way.

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

### Coming from an older setup

`teeup migrate legacy` moves a Mac that already ran the old `teeup.sh`, or
that is still handed its dotfiles by the chezmoi repository, onto plain teeup.
It removes `~/.teeup.common`, `~/.teeupshrc`, the `shellrc.common` link,
`~/.config/mac-setup` and the dangling symlinks those left behind; it
neutralises SDKMAN, rbenv and pyenv init lines in your shell files, rewriting
each as a comment after taking a backup; and where it finds a chezmoi-managed
home it prints what `chezmoi managed` lists, backs those files up, and asks —
defaulting to no — before deleting only `~/.config/chezmoi`, the file that
points chezmoi at its source.

It never runs `chezmoi purge`, and it never touches
`~/Work/environment/dotfiles`, which keeps serving Linux. Those are not
promises made by a check inside the code; they are the shape of the code.
Everything it can delete is named by a key out of a fixed list rather than by
a path a caller passes, the resolved path has to be strictly inside `$HOME`
and clear of whatever `chezmoi source-path` reports, and the only place in
teeup that runs `chezmoi` accepts three read-only subcommands and refuses
everything else.

`teeup doctor` reports the leftovers it does not remove for you: a `[user]`
block in `~/.gitconfig.local`, Powerlevel10k remnants, an `~/.oh-my-zsh`
directory, and a chezmoi source directory still configured.

`docs/legacy-parity.md` is the module-by-module map of where each part of the
old installer went.

### Agents

teeup ships its own mental model as an agent skill:
`share/agents/skills/teeup/SKILL.md`. It tells an agent which trees belong to
teeup, which belong to you, which are generated and must never be hand-edited,
what a capability is, how to add one, and how to run the tests.

`teeup configure teeup-runtime` symlinks it into the directories the agent
CLIs scan, so one file serves all of them:

| Directory | Written |
|---|---|
| `~/.agents/skills/teeup` | always; Codex CLI reads it, and Gemini CLI reads it as an alias that wins over `~/.gemini/skills` |
| `~/.claude/skills/teeup` | when `~/.claude` exists; Claude Code reads only its own directory |
| `~/.codex/skills/teeup` | when `~/.codex` exists |
| `~/.gemini/skills/teeup` | when `~/.gemini` exists |

teeup never creates a tool's home directory, so installing an agent CLI later
means the link is missing until the next `teeup update` — which re-runs
`configure` for every core capability — or an explicit
`teeup configure teeup-runtime`. `teeup doctor` says so in the meantime. A
path that is already there and is not a symlink teeup wrote is left alone with
a warning. For any other agent, link it by hand:

```bash
ln -sfn ~/.local/share/teeup/share/agents/skills/teeup ~/.someagent/skills/teeup
```

### Per-machine overrides

`machines/<hostname>.conf` is a committed file, sourced after your answers and
winning over them: it is where `TEEUP_PACKAGE_MANAGER=macports`,
`TEEUP_SKIP="aerospace"` or a pinned `TEEUP_THEME` belongs. It is the only
override layer — there are no named profiles. It is also the only place a
work identity exists: git itself has one identity everywhere, whatever
repository it sits in; a *second* SSH key and GitHub upload, for a machine
that needs one, exist only when this file sets `TEEUP_WORK_EMAIL` (see
`machines/example.conf.sample`).

### Where everything lives

```text
the checkout (~/.local/share/teeup)
  bootstrap                the only entry point on a fresh Mac
  bin/teeup                the CLI
  lib/*.sh                 sourced by bin/teeup and every capability script
  capabilities/            core.list, daily.list, and one directory per tool
    <name>/capability      metadata, sourced KEY=value
    <name>/install         packages only
    <name>/configure       configuration only
    <name>/doctor          optional; checks, mutates nothing
    <name>/remove          optional; machine state a package manager cannot undo
    <name>/config/         copied into ~/.config once, yours after that
    <name>/home/           copied into $HOME once, yours after that
    <name>/default/        stays teeup's, read at runtime
    <name>/themed/*.tpl    this tool's theme templates
  themes/<name>/{dark,light}.toml
  share/teeup/menu.json    the declarative menu
  share/agents/skills/teeup/SKILL.md
  migrations/<epoch>.sh
  machines/<hostname>.conf
  tests/                   helper.sh, run.sh, lib/, capabilities/, cli.sh, bootstrap.sh, docs.sh
  docs/                    legacy-parity.md, and the design record under superpowers/

your home
  ~/.config/teeup/         env, answers, hooks/<event>.d/, themes/, themed/, menu.json
  ~/.config/<tool>/        copied from a capability's config/, yours
  ~/.zshrc ~/.zprofile ~/.zshenv    thin, sourcing teeup's zsh layer
  ~/.local/bin/            teeup, and the mise-backed wrappers
  ~/Work                   created by dev-dirs

generated, never edit by hand
  ~/.local/state/teeup/done/ toggles/ migrations/ shims/ stock/ logs/
  ~/.local/state/teeup/current/theme/{dark,light}/  theme.name  font
```

## Trust model

teeup installs software from the internet, so it is worth being precise about
what runs unverified. One vendor script is piped into a shell: Homebrew's
`https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh`, run only
when `brew` is missing and only on a machine that is not using MacPorts.
Everything else arrives through a package manager that checks what it
downloads — Homebrew formulae and casks, MacPorts ports, `mas` for the App
Store, and mise for runtimes and CLI tools. The Emacs Doom and Spacemacs
flavors are `git clone`s of their upstream repositories, and Rust goes through
mise's rust backend, which uses rustup.

teeup never writes a secret into the repository. `teeup secret set` puts it in
the macOS Keychain and the shell helper reads it back with `security`; GitHub
authentication is `gh auth login`'s to hold.

Every mutation goes through one seam, so `DRY_RUN=true` in front of any
command prints what it would do and changes nothing. Read the preview before a
first run on a machine that already has a setup you care about.

## Tests

```bash
./tests/run.sh                    # every suite, in a worker pool
TEEUP_TEST_JOBS=1 ./tests/run.sh  # serially, when a failure is confusing
bash tests/capabilities/zed.sh    # one suite
./bin/teeup commands --check      # metadata lint; silent means clean
./bin/teeup dev check <name>      # lint, menu lint, shellcheck and that suite
```

Every suite builds a throwaway `$HOME` and a mock `bin` directory first on a
narrowed `PATH`, so no test touches the real machine and none depends on
Homebrew. CI runs the suite, shellcheck and the metadata lint on `macos-14`,
`macos-15-intel` and `ubuntu-latest`.

`CONTRIBUTING.md` has the rest: the capability rules, the code style, and what
a new test has to do.
````

- [ ] **Step 2: Add the changelog entry and record the `teeup list` divergence in the spec**

Nothing already in `CHANGELOG.md` is removed or reworded; the new entry goes at
the top of the existing `### Added` list under `[Unreleased]`. The `edit-old`
below therefore carries the first line of that list as its anchor.

```markdown edit-old=CHANGELOG.md
### Added
- **chezmoi and GNU Stow overlays.** `--dotfiles` now recognises a chezmoi source
```

```markdown edit-new=CHANGELOG.md
### Added
- **teeup rebuilt as a macOS environment distribution.** `bootstrap` and
  `bin/teeup` replace `teeup.sh` and `teeup-wizard.sh`: every tool is now a
  capability under `capabilities/`, in one of three tiers, with its own
  metadata, install, configure, doctor and theme hooks. The verbs are
  `install`, `configure`, `update`, `reset`, `remove`, `list`, `status`,
  `doctor`, `menu`, `theme`, `launch`, `lazy-run`, `config`, `has`, `secret`,
  `migrate`, `dev` and `commands`; `teeup help` is the full list. Lazy
  capabilities arrive on first use through shims, themes cover every tool at
  once in light and dark, migrations and hooks carry a machine forward, and
  `teeup migrate legacy` moves one off the old installer.
  `docs/legacy-parity.md` maps every module of the old installer to what
  replaced it. The previous installer is removed from `legacy/`.
- **An agent skill.** `share/agents/skills/teeup/SKILL.md` ships the mental
  model of the tree, and `teeup configure teeup-runtime` links it into the
  directories Claude Code, Codex CLI and Gemini CLI scan.
- **chezmoi and GNU Stow overlays.** `--dotfiles` now recognises a chezmoi source
```

Then the one place where the shipped CLI is narrower than the spec. The
spec's CLI-surface block writes `teeup list [--tier|--group|--json]`;
`cmd_list` in `bin/teeup` has implemented `--tier` alone since phase 1, and
neither phase 3, 4a, 4b nor this plan claims `--group` or `--json`. Adding two
flags and their tests in a documentation phase would be a behaviour change
made by the wrong task, so the divergence is accepted and written down where
the requirement lives, next to the `teeup dev` line that phase 3a's amendment
left untouched. `README.md` (Step 1) and `teeup help` already say `--tier`
only, so after this edit the three agree.

```markdown edit-old=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md
teeup status                                        teeup list [--tier|--group|--json]
```

```markdown edit-new=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md
teeup status                                        teeup list [--tier]
```

Below the block, record why:

```markdown edit-old=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md
`bin/teeup` resolves `<verb> <cap>` to `capabilities/<cap>/<verb>`, falling back to generic implementations for `update` and `remove` from metadata. Help and completion derive from metadata files.
```

```markdown edit-new=docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md
`bin/teeup` resolves `<verb> <cap>` to `capabilities/<cap>/<verb>`, falling back to generic implementations for `update` and `remove` from metadata. Help and completion derive from metadata files.

*Amended 2026-09-13 phase 5b: `teeup list` shipped with `--tier` only. `--group` and `--json` were in the original block and were implemented by no phase; `teeup list` already prints the tier beside every capability and `teeup menu` covers grouping, so the two flags are dropped from the surface rather than left as an unmet requirement. Add them as a new capability of `cmd_list`, with tests, if they are ever wanted.*
```

- [ ] **Step 3: Add the README checks to the docs suite**

```bash edit-old=tests/docs.sh
echo "docs.sh"
```

```bash edit-new=tests/docs.sh
# readme_verbs: the verbs the README's command table names, taken from the
# region markers rather than from the whole file, so prose that happens to
# contain the word "teeup" is not mistaken for a command.
readme_verbs() {
  sed -n '/<!-- teeup-commands -->/,/<!-- \/teeup-commands -->/p' "$REPO/README.md" |
    grep -oE '`teeup [a-z][a-z-]*' |
    sed 's/^`teeup //' |
    sort -u
}

test_the_readme_documents_every_verb_teeup_has() {
  local undocumented="" v
  local documented
  documented="$(readme_verbs)"
  assert_contains "$documented" "install" "the command table was found at all" || return 1
  for v in $(help_verbs); do
    if ! grep -qxF -- "$v" <<<"$documented"; then
      undocumented="$undocumented $v"
    fi
  done
  assert_equals "" "$undocumented" "every verb teeup help prints has a README row" || return 1
}

test_the_readme_documents_no_verb_teeup_lacks() {
  local invented="" v
  local real
  real="$(help_verbs)"
  for v in $(readme_verbs); do
    if ! grep -qxF -- "$v" <<<"$real"; then
      invented="$invented $v"
    fi
  done
  assert_equals "" "$invented" "every README row names a verb teeup has" || return 1
}

test_the_readme_names_the_tiers_the_lists_hold() {
  local body missing="" cap
  body="$(cat "$REPO/README.md")"
  for cap in $(grep -v '^#' "$REPO/capabilities/core.list" | grep -v '^$'); do
    case "$body" in *"\`$cap\`"*) ;; *) missing="$missing $cap" ;; esac
  done
  for cap in $(grep -v '^#' "$REPO/capabilities/daily.list" | grep -v '^$'); do
    case "$body" in *"\`$cap\`"*) ;; *) missing="$missing $cap" ;; esac
  done
  assert_equals "" "$missing" "every core and daily capability is named in the README" || return 1
}

test_the_readme_names_every_shipped_theme() {
  local body missing="" theme
  body="$(cat "$REPO/README.md")"
  for theme in "$REPO"/themes/*/; do
    theme="$(basename "$theme")"
    case "$body" in *"\`$theme\`"*) ;; *) missing="$missing $theme" ;; esac
  done
  assert_equals "" "$missing" "every theme in themes/ has a row in the README table" || return 1
}

echo "docs.sh"
```

```bash edit-old=tests/docs.sh
run_test "the parity checklist names only capabilities that exist" test_the_parity_checklist_names_only_capabilities_that_exist
print_summary
```

```bash edit-new=tests/docs.sh
run_test "the parity checklist names only capabilities that exist" test_the_parity_checklist_names_only_capabilities_that_exist
run_test "the README documents every verb teeup has" test_the_readme_documents_every_verb_teeup_has
run_test "the README documents no verb teeup lacks" test_the_readme_documents_no_verb_teeup_lacks
run_test "the README names every core and daily capability" test_the_readme_names_the_tiers_the_lists_hold
run_test "the README names every shipped theme" test_the_readme_names_every_shipped_theme
print_summary
```

- [ ] **Step 4: Run the docs suite**

Run: `bash tests/docs.sh`
Expected: ten tests, `Summary: 10/10 passed`. If `the README documents every verb teeup has` fails, the missing verb is named in the message and belongs in the table; if `no verb teeup lacks` fails, the table has a row for something that was never built.

- [ ] **Step 5: Run everything**

Run: `./tests/run.sh 2>&1 | tail -1`
Expected: `All N suites passed.`, N unchanged from Task 4.

Run: `./bin/teeup commands --check && shellcheck --severity=warning tests/docs.sh && git diff --check`
Expected: no output from any of the three.

- [ ] **Step 6: Commit**

```bash
git add README.md CHANGELOG.md tests/docs.sh
git commit -m "Rewrite the README against the runtime that exists"
```

**Real-Mac risk:** none in the tests. The README makes claims only a Mac can settle — that `teeup install font "Fira Code"` really changes WezTerm's font, that the Emacs LaunchAgent really starts a daemon — but each of those is a claim the capability's own plan already carries as its risk, and this task copies rather than re-derives them.

---

### Task 6: `CONTRIBUTING.md`, rewritten and renumbered

**Files:**
- Modify: `CONTRIBUTING.md` (replaced whole)

**Interfaces:**
- Consumes: nothing at run time. Every rule in it is a rule some `lib/` function or `bin/teeup` verb enforces; the citations are in the text.
- Produces: one numbered list of capability rules, 1 to 30, which the agent skill points at ("`CONTRIBUTING.md` has the long form of each of these") and which Task 4's parity checklist does not duplicate. Items 27 to 30 are phase 5a's four `teeup migrate legacy` rules, carried over verbatim: they are the written form of the guard that keeps the sibling chezmoi repository intact, so a rewrite that dropped them would be the one regression this task must not make.

Two things are wrong with the file on disk. The first 425 lines, everything before `## Adding a capability (new runtime)`, tell a contributor to add a toggle variable to `teeup.sh`, update `list_modules()` and add a case to `parse_only_modules()` — none of which exist. The second is subtler and is why this is a task rather than a paragraph in Task 4: phases 3a, 3b, 4a, 4b, 4c and 5a each appended items to the "Adding a capability" list, so by the time this task runs the list is 34 items long and says the same thing about `TEEUP_NO_GUM` twice — once in phase 4b's picker item and once in phase 4c's test item. Deduplicating and renumbering cannot be done without reading every item, which is also the way to find out which of them are now stale.

**Before you write it, read what is there.** `git show HEAD:CONTRIBUTING.md` and keep every rule. The list below is that file's content, deduplicated and renumbered, plus two items for the agent skill and the documentation. If the file on disk has a rule this task's text does not, it was added after this plan was written: keep it, at the end of the list.

- [ ] **Step 1: Write it**

````markdown file=CONTRIBUTING.md
# Contributing to teeup.sh

teeup is a macOS environment distribution: a git checkout, a `bootstrap`
script, a `bin/teeup` CLI, a library under `lib/`, and one directory per tool
under `capabilities/`. `README.md` describes it from a user's side; this file
is the rest.

## Getting started

```bash
git clone https://github.com/<you>/teeup.sh
cd teeup.sh
git checkout -b my-change
./tests/run.sh            # everything, in a worker pool; about a minute
./bin/teeup commands --check
```

You do not need a Mac to work on most of teeup: the suite mocks every external
command and runs on Linux, which is what CI's `ubuntu-latest` job proves. You
do need a Mac to know whether a capability actually works, which is why every
change that touches one should say what it has and has not been run against.

## The layout

| Path | What it is | Who owns it |
|---|---|---|
| `bootstrap` | the only entry point on a fresh Mac | teeup |
| `bin/teeup` | verb dispatch; `teeup <verb> <cap>` runs `capabilities/<cap>/<verb>` | teeup |
| `lib/*.sh` | sourced by `bin/teeup` and by every capability script through `lib/all.sh` | teeup |
| `capabilities/<name>/` | one tool: metadata, scripts, shipped files, theme templates | teeup |
| `capabilities/{core,daily}.list` | the ordered tier manifests | teeup |
| `themes/<name>/{dark,light}.toml` | semantic palettes | teeup |
| `share/teeup/menu.json` | the declarative menu | teeup |
| `share/teeup/skeleton/` | what `teeup dev new-capability` copies | teeup |
| `share/agents/skills/teeup/` | the agent skill | teeup |
| `migrations/<epoch>.sh` | one-shot fixes for machines already set up | teeup |
| `machines/<hostname>.conf` | committed per-machine overrides | whoever owns that machine |
| `tests/` | `helper.sh`, `run.sh`, `lib/`, `capabilities/`, `cli.sh`, `bootstrap.sh`, `docs.sh` | teeup |
| `docs/legacy-parity.md` | where each part of the previous installer went | teeup |
| `docs/superpowers/` | specs, implementation plans and reviews: the design record | read-only |

Inside a capability, three directories carry three different owners. `config/`
is copied into `~/.config` once and belongs to the user after that. `home/` is
copied into `$HOME` under its literal dotfile name (`home/.zshrc` becomes
`~/.zshrc`), same rule. `default/` stays teeup's and is read at runtime through
`$TEEUP_PATH`, so a `git pull` improves it without touching a user edit. Thin
user files source thick default files; that is the whole upgrade story.

## Adding a capability

1. Create `capabilities/<name>/` with `capability`, `install` and `configure`,
   or let `./bin/teeup dev new-capability <name>` do it (item 20).
2. `capability` is a sourced `KEY=value` file with no logic: `summary`,
   `group`, `tier` (`core|daily|lazy`), `requires`, `provides`, `packages`,
   `casks`, `apps`, `interactive`.
3. `install` only installs packages (`pkg_install`, `cask_install`).
   `configure` only writes configuration (`copy_config_once`,
   `write_managed_file`, `append_once`, `run_cmd`). Both are idempotent and
   run as `bash -eu` with `lib/all.sh` loaded and the answers file sourced.
   Judge success by the postcondition, not by the exit code of the last
   command: end an install with the check that the thing is actually there.
4. Never call `sudo`; use `run_privileged`. Mutate the machine only through
   `run_cmd`, or through the file primitives (`copy_config_once`,
   `write_managed_file`, `append_once`), which carry their own dry-run guard —
   do not wrap those in `run_cmd`.
5. `provides` must not list a command macOS already ships (`python3`, `ruby`,
   `java`, `git`, `perl`). A shim appended last on `PATH` could never fire.
6. Add the name to `capabilities/core.list` or `daily.list` if it is not lazy,
   in the same commit: a core or daily capability that is not in its tier list
   makes `teeup commands --check` fail.
7. Add `tests/capabilities/<name>.sh` using the mock harness; run
   `./bin/teeup commands --check && ./tests/run.sh` before committing.
8. Shipped files live in one of three directories, by owner: `config/` is
   copied once into `~/.config` and belongs to the user after that; `home/` is
   copied once into `$HOME` under its literal dotfile name; `default/` stays
   teeup's and is read at runtime through `$TEEUP_PATH`.
9. Files under `default/` and `home/` are zsh or Lua, not bash: shellcheck
   does not run on them, so keep them simple and guard every optional tool.
10. Per-machine overrides go in `machines/<hostname>.conf`, which is committed
    and sourced last, so it wins over the answers file.
11. If the tool has colours, add `capabilities/<name>/themed/<file>.tpl`.
    `teeup theme set` renders every template once per mode with `{{ key }}`,
    `{{ key_strip }}` (no leading `#`) and `{{ key_rgb }}` (`r,g,b`) replaced
    from `themes/<theme>/{dark,light}.toml`, and stages the results in
    `~/.local/state/teeup/current/theme/<mode>/<file>`. A user template of the
    same basename in `~/.config/teeup/themed/` wins. Basenames share one
    namespace, so no two capabilities may ship the same one
    (`teeup commands --check` fails on a duplicate).
12. If the tool needs to be told about a new theme or font, add an executable
    `capabilities/<name>/theme-apply` or `capabilities/<name>/font-apply`. Both
    run exactly like `install` and `configure` (`bash -eu`, `lib/all.sh`
    loaded, answers sourced, `TEEUP_CAP` and `TEEUP_CAP_DIR` exported).
    `theme-apply` additionally gets `TEEUP_THEME_DIR`
    (`~/.local/state/teeup/current/theme`) and `TEEUP_THEME_NAME`;
    `font-apply` gets `TEEUP_FONT_FAMILY`. Both are optional, and a failure
    warns without aborting the switch, so keep them to "tell the app to
    reload" rather than real work.
13. Native macOS settings go through `lib/macos.sh`: `defaults_write` (which
    records the prior value so `remove` can call `defaults_restore`),
    `launchagent_install <label>` with the plist on stdin, and
    `launchagent_remove <label>` in `remove`. Never call `defaults write` or
    `launchctl` directly.
14. An editor whose settings are JSON (Zed, VS Code) never gets a shipped
    `settings.json`: its hooks set only the keys teeup owns, with
    `json_set_key <file> <dotted.key> <json-value>` or
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
19. A capability whose whole content is one GUI cask needs no code of its
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
20. Start a capability with `./bin/teeup dev new-capability <name>`, which
    writes `capabilities/<name>/{capability,install,configure}` and
    `tests/capabilities/<name>.sh` from `share/teeup/skeleton/`. The scaffold
    is `tier=lazy` on purpose: a `core` or `daily` capability that is not in
    its tier list makes `teeup commands --check` fail, so change the tier and
    append to the list in the same commit. Finish with
    `./bin/teeup dev check <name>`, which runs the metadata lint, the menu
    lint, shellcheck and that capability's suite — the same four things CI
    runs. `teeup dev check` with no name runs the whole suite, which takes
    minutes.
21. A capability may ship an executable `doctor` beside its `install` and
    `configure`. It runs exactly like them and reports through
    `doctor_ok <message>`, `doctor_warn <message>` and
    `doctor_fail <message> <fix-command>`; its last line is `doctor_verdict`.
    `doctor_fail` returns 0 so the script keeps checking, and the fix it
    records is what the summary prints, so make it one command somebody can
    paste. A doctor script mutates nothing, so it needs no `DRY_RUN` guard.
    Do not write one for anything the metadata already says: `teeup doctor`
    checks `packages`, `casks`, `apps` and `provides` for every capability by
    itself. Write one for the invariants metadata cannot express — a config
    in two places at once, a key with the wrong mode, a generated file that is
    stale, a symlink that is not there.
22. Adding a row to `share/teeup/menu.json` is part of adding a tool. Ids are
    dotted and the tree is in them, so `install.browsers.brave` needs
    `install.browsers` and `install` to exist as rows too. Every row needs a
    `label`; a row is a leaf when it has an `action` and a submenu when it has
    children, never both and never neither; and no two rows under the same
    parent may share a label, because the picker hands back a label and it is
    mapped to an id by position. `teeup dev check` enforces all of that. Use
    `"when": "! teeup has <name>"` on an Install row so it disappears once the
    thing is installed. The file is read by `lib/menu.awk`, not jq: macOS
    ships no jq and the test harness's narrowed `PATH` hides Homebrew's, so
    values are one-line strings and the only escapes are `\"`, `\\` and `\/`.
23. `configure` is re-run by `teeup update` on every machine, so it must be
    quiet and cheap when nothing has changed: report "Already ..." instead of
    rewriting, and never restart an application or print a multi-line manual
    step unconditionally. `defaults_write` leaves a key that already holds the
    value alone and records the domains it did write, so a `configure`
    restarts an app with
    `if defaults_changed com.apple.dock; then run_cmd killall Dock || true; fi`.
    A one-time notice uses `state_done ensure <name>`, which succeeds only the
    first time.
24. `teeup reset <cap>` and a migration's `migration_refresh <cap>` both
    re-run your `configure` with `TEEUP_RESET` or `TEEUP_REFRESH` set to the
    capability's name, which turns each `copy_config_once` in it into
    `refresh_config` or `refresh_if_pristine`. Install every user-facing file
    through `copy_config_once` (rendering into a temporary file first when the
    content depends on the machine) and both verbs work for free; a `cp` of
    your own is invisible to them. A capability with no `config/` or `home/`
    directory is not resettable, and says so. `teeup remove <cap>` uninstalls
    the `casks` and `packages` your metadata names and clears the done marker;
    add a `remove` script only for machine state a package manager cannot
    undo — a LaunchAgent (`launchagent_remove <label>`), recorded `defaults`
    (`defaults_restore`), a `hidutil` mapping. It runs before the uninstall,
    while the tool is still there, and never deletes the user's configuration.
25. A file teeup owns but the user may edit carries a stock record
    (`stock_record`, written by `copy_config_once`). `config_is_pristine
    <file>` asks whether it still matches; `write_config_region <file>
    <label>` rewrites a managed region and keeps a pristine file reading as
    pristine (and refuses a symlink); `refresh_if_pristine <src> <dest>` is
    the stock-checksum rule a migration uses; `backup_copy <file>` takes a
    copy and leaves the original in place for a minimal patch. Hook events for
    the user's own scripts are `post-bootstrap`, `post-update` and `theme-set`
    (`TEEUP_HOOK_EVENTS` in `lib/hooks.sh`); adding one means a new `.sample`
    under `capabilities/teeup-runtime/default/hooks/` and a
    `hook_run <event> [args]` call where it fires.
26. A capability that asks a question sets `interactive=true` (otherwise
    `cap_run` redirects stdin from `/dev/null` and the prompt hangs on
    nothing), reads an answers key first so it can run unattended
    (`TEEUP_DBS`, `TEEUP_KARABINER_HYPER`), and stays idempotent, because
    `configure` is how the question is asked again: `docker-dbs` starts a
    container that exists instead of creating a second one.
27. Nothing in `teeup migrate legacy` deletes a path it was given. Every
    deletion goes through `migrate_rm <key>`, and the keys are the five-entry
    `case` in `migrate_target` — adding something to delete means adding a
    key there and a test for it, never passing a path. The resolved path is
    checked again by `migrate_path_is_safe` (inside `$HOME`, and clear of the
    chezmoi source directory and everything above and below it), because an
    `XDG_CONFIG_HOME` override or a symlinked `~/.config` can still make a
    key land somewhere it must not.
28. `chezmoi` is only ever run through `chezmoi_ro`, which accepts `managed`,
    `source-path` and `--version` and `die`s on anything else. `chezmoi purge`
    removes chezmoi's source directory, which is the sibling repo that still
    serves Linux, so it must stay unreachable — including from a capability's
    `doctor` script, which sources the same libraries.
29. A test in this area may never name a path outside `$TEST_HOME`. The
    stand-in for the sibling checkout is a `Work/environment/dotfiles`
    directory the test creates inside the throwaway `$HOME`, and `chezmoi` and
    `git` are mocked. A destructive code path needs a test for the refusal,
    not only for the success.
30. Use `disable_matching_lines` rather than editing a shell file by hand. It
    rewrites a matching line as `: # Disabled by teeup (<reason>): <line>` —
    the `:` matters, because an `if … ; then` whose whole body is commented
    out is a syntax error — leaves a line that *opens* a block alone and
    reports it, backs the file up through `backup_copy`, and is idempotent.
    Pass its pattern and reason through `ENVIRON`, never `awk -v`: awk expands
    escape sequences in a `-v` assignment, so `\.pyenv` would arrive as
    `.pyenv` and match `mypyenv` too.

## Code style

- **bash 3.2**, because that is what macOS ships as `/bin/bash`. No `mapfile`,
  `readarray`, `declare -A`, `${var,,}`, `${var^^}`, `readlink -f`, `**`,
  `&>>`, `wait -n` or `local -n`. Use `10#$n` for arithmetic on a string that
  may have a leading zero. A same-line `local` back-reference (`local a=1
  b=$a`) leaves `b` empty. bash 3.2 mis-parses a quoted pattern containing `/`
  inside `${var//pat/repl}`: use `replace_literal` (`lib/files.sh`). Run
  `shopt -u patsub_replacement 2>/dev/null || true` before any `${var//}`
  whose replacement can contain `&`.
- **BSD tools.** No GNU-only flags, no `grep -P`, no `\t` or `\n` in a `sed`
  replacement. Pass an awk value through `ENVIRON` rather than `-v` when it can
  contain a backslash: awk expands escapes in a `-v` assignment.
- **Strict mode.** `set -euo pipefail` at the top of `bin/teeup`, `bootstrap`
  and every test. Capability scripts are run as `bash -eu` by `cap_run` and
  need no line of their own. In any file that runs under `set -e`, write
  `if … then … fi` rather than a bare `[[ … ]] && cmd` statement: as the last
  statement of a function it makes the function's exit status the test's.
- **Arrays** expand as `${array[@]+"${array[@]}"}`, which is safe when the
  array is empty and `set -u` is on. bash 3.2 has indexed arrays only.
- **Names.** Environment variables `UPPER_WITH_UNDERSCORES`, locals and
  functions `lower_with_underscores`. Every teeup-owned variable starts
  `TEEUP_`.
- **Logging** is `log`, `ok`, `warn`, `err` and `die` from `lib/core.sh`.
  Nothing prints a bare `echo` to describe what it is doing.
- **Packages** go through `pkg_install <package> [command]`, never a direct
  `brew` or `port` call, so `TEEUP_PACKAGE_MANAGER=macports` keeps working on
  an old Intel laptop. Casks are Homebrew-only by nature: `cask_install` and
  `cask_app_install` skip them with a note where `casks_supported` is false.
- **Paths with spaces and metacharacters must work.** Quote everything, and
  give at least one test in every new suite a `$TEST_HOME` path containing a
  space, a `$` and a quote.
- **shellcheck at warning severity** is clean on `bootstrap`, `bin/teeup`,
  `lib/*.sh`, every capability script and every test. A disable comment needs
  a reason on the same line.

## Tests

```bash
./tests/run.sh                     # everything, in a worker pool
TEEUP_TEST_JOBS=1 ./tests/run.sh   # serially, when a failure is confusing
bash tests/lib/theme.sh            # one suite
./bin/teeup dev check <name>       # lint, menu lint, shellcheck, that suite
```

`tests/helper.sh` gives every suite a throwaway `$HOME`, a `MOCK_BIN`
directory first on a narrowed `PATH` (`$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin`),
`mock_command`, `mock_command_script`, `mock_macos_base`,
`hide_host_commands`, and the `assert_*` family. A suite is a plain bash
script: `setup`, one function per behaviour, a `run_test` line for each, and
`print_summary` at the end. `tests/run.sh` finds `tests/lib/*.sh`,
`tests/capabilities/*.sh`, `tests/cli.sh`, `tests/bootstrap.sh` and
`tests/docs.sh`; anything else needs a line in its glob.

Four rules catch most new tests out.

- **A test that drives a prompt or a picker must `export TEEUP_NO_GUM=1`.**
  `lib/ui.sh` uses gum whenever `TEEUP_NO_GUM` is empty and gum is on `PATH`,
  and the narrowed `PATH` still exposes a host `/usr/bin/gum`, which paints on
  `/dev/tty` instead of reading the piped answer. A test that wants the fzf
  branch sets `TEEUP_MENU_PICKER=fzf` and mocks `fzf`; no test may need either
  program installed.
- **The narrowed `PATH` hides Homebrew.** A host tool a test needs (`lua`,
  `jq`, `python3`, `nvim`) has to be resolved to an absolute path before
  `setup_test_env` runs, or mocked. A test that only passes on a developer's
  machine is a defect.
- **Nothing outside `$TEST_HOME`.** No test writes to the real `$HOME`, and a
  test that needs a real command hidden uses `TEEUP_TEST_MISSING` or
  `hide_host_commands <name...>`, which adds every copy on the host's `PATH`
  by absolute path.
- **`TEEUP_TEST_TTY=yes|no`** overrides the terminal check in
  `teeup lazy-run`, so a piped `y` can answer its question.
  `tests/capabilities/colima.sh` is the reference round trip.

## The agent skill

`share/agents/skills/teeup/SKILL.md` is the mental model an AI agent reads
before it touches the tree: the three owners, the read-only trees, the
capability contract, the seven steps of adding one, and how to run the tests.
`teeup configure teeup-runtime` symlinks it into `~/.agents/skills/teeup`
always, and into `~/.claude/skills/teeup`, `~/.codex/skills/teeup` and
`~/.gemini/skills/teeup` where that tool already has a home directory.

Keep it short and keep it true. `tests/docs.sh` checks that every path it names
exists and every verb it names is one `teeup help` prints, but nothing can
check that a rule in it still matches the code, so a change to the capability
contract means a look at the skill in the same commit. When a rule needs more
than three sentences it belongs in this file, and the skill points here.

## Documentation

`tests/docs.sh` is the check: it reads `./bin/teeup help`,
`capabilities/{core,daily}.list`, `themes/` and `capabilities/*/capability` and
compares the documents against them. It fails when the README's command table
and `teeup help` disagree in either direction, when a core or daily capability
is not named in the README, when a theme has no row, when the skill names a
path that does not exist, and when the parity checklist names a capability
that does not.

- A new verb needs a row in the README's command table, between the
  `<!-- teeup-commands -->` markers.
- A new core or daily capability needs its name in the README's tier list.
- A new theme needs a row in the README's theme table.
- `CHANGELOG.md` is history: add to `[Unreleased]`, never reword what is
  already there.
- `docs/superpowers/` is the design record. Read it; do not edit it.

## Pull requests

1. One commit per self-contained change, with a plain imperative subject and
   no trailers.
2. `./tests/run.sh`, `./bin/teeup commands --check`, `shellcheck
   --severity=warning` on everything you touched, and `git diff --check`, all
   green before you push.
3. Say what you ran it against. "Suite green on Linux, not run on a Mac" is
   useful; silence is not.
4. Update the documentation in the same commit as the behaviour.

## Bug reports

Include `sw_vers`, `uname -m`, `teeup version`, the output of
`teeup doctor`, and the command you ran with its full output. A `DRY_RUN=true`
run of the same command is usually the fastest thing to paste.

## Feature requests

Say what you want to be able to do and what you do today instead. If it is a
tool, say whether it should be core, daily or lazy, and why.

## Code of conduct

Be decent. Assume the person on the other side is doing their best with the
information they had.
````

- [ ] **Step 2: Check the numbering is one run**

Run: `grep -nE '^[0-9]+\. ' CONTRIBUTING.md | awk -F. '{print $1}' | awk '{print $2}' | tr '\n' ' '`
Expected: `1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26` for the capability list, then `1 2 3 4` for the pull request list — two runs, each starting at 1 and increasing by one, with no repeats.

- [ ] **Step 3: Check nothing points at the old installer any more**

Run: `grep -n 'teeup\.sh --\|list_modules\|parse_only_modules\|ZSH_MODE\|--only ' CONTRIBUTING.md`
Expected: no output.

- [ ] **Step 4: Run everything**

Run: `./tests/run.sh 2>&1 | tail -1`
Expected: `All N suites passed.`, N unchanged from Task 5.

Run: `./bin/teeup commands --check && git diff --check`
Expected: no output from either.

- [ ] **Step 5: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "Rewrite CONTRIBUTING for the capability runtime"
```

**Real-Mac risk:** none; this task changes one Markdown file. The risk it carries is the ordinary documentation one: a rule stated here that the code does not enforce reads as a promise. Every item above names the function or the verb that enforces it, so a reader can check.

---

### Task 7: Deleting `legacy/`

**Files:**
- Delete: `legacy/` (`teeup.sh`, `teeup-wizard.sh`, `lib/`, `templates/`, `tests/`)
- Modify: `.github/workflows/ci.yml` (three steps removed, two renamed)
- Modify: `lib/pkg.sh`, `lib/files.sh`, `lib/migrate.sh` (four comments reworded; the last three name paths phase 5a ported from)
- Modify: `tests/docs.sh` (the last check)

**Interfaces:**
- Consumes: `docs/legacy-parity.md` (Task 4), which is the only remaining record of what is being deleted. Also, as a precondition rather than a file this task edits: the whole of phase 5a, not only its safety machinery — `disable_matching_lines` (`lib/files.sh`, 5a Task 1); `lib/migrate.sh`'s `migrate_rm`, `migrate_target` and `migrate_path_is_safe` (5a Task 2); `lib/migrate.sh`'s `migrate_legacy_paths`, `migrate_disable_runtime_inits` and `migrate_chezmoi` (5a Tasks 3 to 5); and `bin/teeup`'s `cmd_migrate`, dispatched from a working `migrate)` arm and calling all three of the above (5a Task 6). All of it must exist before this task may run — see Step 1.
- Produces: a repository with one runtime in it. Nothing consumes this task.

**This is the last task on purpose.** A reviewer who is not convinced by the
parity checklist should be able to reject this commit and keep the six before
it, which is why the deletion is one commit that touches nothing else. Run
Task 4 first, read its checklist against the capabilities, and only then do
this. **5a must be merged and verified before this task runs, not only Task 4.**
The parity checklist is the spec's phase 5 gate, but it is a document; the
thing standing between `legacy/` and deletion is whether 5a actually ported
what the checklist claims it ported. Step 1 checks that rather than trusting
it.

**What has to go in the same commit.** The workflow runs three legacy steps
before the new-runtime steps; a workflow that shellchecks a deleted directory
fails on the next push, so the tree and the CI steps go together. Everything
else that mentions `legacy/` has already been dealt with: `README.md` and
`CONTRIBUTING.md` were rewritten in Tasks 5 and 6, `lib/pkg.sh`'s single
mention is a comment saying where the file was ported from and is reworded in
Step 6 so the note survives without a path that no longer resolves, `capabilities/wezterm/config/wezterm/wezterm.lua` uses `legacy` as a
Lua variable name for the old `~/.wezterm_local.lua` hook and has nothing to do
with the directory, and `CHANGELOG.md` and `docs/superpowers/` are history.
`.gitignore` has no `legacy` entry to remove — check, do not assume.

One file that looks like a loose end is not one. `review.md` in the repository
root names `./legacy/tests/run_tests.sh`, but `git ls-files review.md` prints
nothing: it is an untracked scratch file on one developer's machine, not part
of the repository. That is why the check below reads `git ls-files` rather than
the working tree — an untracked note somebody left lying about must not fail
the suite, and must not be deleted by teeup either.

- [ ] **Step 1: Prove the parity task landed, and that 5a landed underneath it**

Run: `git log --oneline -6 | grep -c 'parity'`
Expected: `1`. If it is `0`, stop: Task 4 has not been committed, and this
commit would delete the only copy of what the checklist describes.

Run: `ls docs/legacy-parity.md`
Expected: the path, with no error.

A parity document is not proof that 5a shipped the code it describes, and
neither is 5a's safety machinery by itself: `lib/migrate.sh`'s closed key
list and its read-only chezmoi wrapper (5a Task 2) land before the three
things they guard (5a Tasks 3 to 5) and before the verb that calls them (5a
Task 6), so a tree that stops partway through 5a can pass a check that only
looks for the early pieces. Check the whole of it, one 5a task at a time,
before touching `legacy/`:

Run: `n=$(grep -c '^disable_matching_lines()' lib/files.sh 2>/dev/null || true); printf '%s\n' "${n:-0}"`
Expected: `1`. This is 5a Task 1. If it is `0`, stop: 5a has not ported
`disable_matching_lines` out of `legacy/teeup.sh` yet, and this commit would
delete the only copy of a function `teeup migrate legacy` needs. Dropping the
README and parity references to `teeup migrate legacy` (the fallback in "What
was assumed about phase 5a") does not change this — it only means the
*documents* stopped claiming the verb exists, not that deleting `legacy/` is
safe.

Run: `n=$(grep -c '^migrate_rm()\|^migrate_target()\|^migrate_path_is_safe()' lib/migrate.sh 2>/dev/null || true); printf '%s\n' "${n:-0}"`
Expected: `3`. This is 5a Task 2 — the closed key list, the safety gates and
the read-only chezmoi wrapper. It is necessary but not sufficient: these three
functions exist before 5a has written a single line that actually migrates
anything, so a `3` here proves only that `legacy/` cannot yet be deleted for
the wrong reason (no safety gate at all), not that it can be deleted for the
right one. If `lib/migrate.sh` does not exist, or defines fewer than three of
these, stop.

Run: `n=$(grep -c '^migrate_legacy_paths()\|^migrate_disable_runtime_inits()\|^migrate_chezmoi()' lib/migrate.sh 2>/dev/null || true); printf '%s\n' "${n:-0}"`
Expected: `3`. This is 5a Tasks 3, 4 and 5 — the three operations
`cmd_migrate` calls, one per task: `migrate_legacy_paths` (Task 3, the legacy
files, directories, symlinks and rc lines), `migrate_disable_runtime_inits`
(Task 4, SDKMAN, rbenv and pyenv) and `migrate_chezmoi` (Task 5, the only one
that touches the sibling checkout's config, and only by asking). If this is
less than `3`, stop: 5a's safety gates have landed (the check above passed)
but the migration itself has not, in full or in part — a partially applied
5a exactly like this one is what let `legacy/` get deleted while
`teeup migrate legacy` was still unable to do its one job.

Run: `n=$(grep -c '^cmd_migrate()' bin/teeup 2>/dev/null || true); printf '%s\n' "${n:-0}"`
Expected: `1`. This is 5a Task 6, first half: the verb exists as a function.

Run: `n=$(grep -c '^  migrate) cmd_migrate' bin/teeup 2>/dev/null || true); printf '%s\n' "${n:-0}"`
Expected: `1`. Still 5a Task 6: the dispatcher reaches it.

Run: `n=$(grep -c '[[:space:]]migrate[[:space:];]' lib/all.sh 2>/dev/null || true); printf '%s\n' "${n:-0}"`
Expected: `1`. `cmd_migrate` calls functions that live in `lib/migrate.sh`;
they exist only once `lib/all.sh`'s source loop actually names `migrate`
alongside `menu` and `dev`. A `0` here means every check above this one can
still read `3`, `1` and `1` while `teeup migrate legacy` dies with
`migrate_legacy_paths: command not found` the moment it runs.

The four checks above are cheap and worth keeping as a first gate, but none of
them is proof: `grep` over a function's text counts a name whether it is
called, echoed, or only sitting in a comment — `migrate_legacy_paths ||
rc=1` and `# migrate_legacy_paths || rc=1` match the same pattern. A
`cmd_migrate` whose three calls were commented out would still print `3` on
the check this replaced. The only check that cannot be fooled that way is
running the verb and reading what it actually did:

Run:
```sh
( source tests/helper.sh
  setup_test_env
  export TEEUP_NO_GUM=1
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR"
  export DRY_RUN=true
  out="$("$TEEUP_PATH/bin/teeup" migrate legacy 2>&1)"
  rc=$?
  cleanup_test_env
  n=$(printf '%s\n' "$out" | grep -c \
    'Removing what older teeup versions left in your home directory\|Disabling the runtime managers mise replaces\|nothing to take over' \
    || true)
  n="${n:-0}"
  [[ $rc -eq 0 ]] || n=0
  printf '%s\n' "$n" )
```
Expected: `3`. This is 5a Tasks 3 to 6 together, proven by behaviour rather
than by text: the same throwaway-`$HOME`, temp-config/state/machines,
`TEEUP_NO_GUM=1` isolation `tests/helper.sh` gives every suite, `DRY_RUN=true`
so nothing is written even though `$TEST_HOME` is already disposable, and a
count of how many of the three migration operations actually previewed their
work — `migrate_legacy_paths`'s "Removing what older teeup versions left in
your home directory", `migrate_disable_runtime_inits`'s "Disabling the
runtime managers mise replaces (SDKMAN, rbenv, pyenv)", and
`migrate_chezmoi`'s own log line, which reads "No chezmoi on this machine;
nothing to take over." on a machine without chezmoi and "chezmoi is
installed but reports no source directory here; nothing to take over." on
one where this fake `$HOME` has no chezmoi source configured — both share
"nothing to take over", which is the substring matched so the check reads the
same on either kind of machine. Counting the three lines is not enough by
itself: each of `migrate_legacy_paths`, `migrate_disable_runtime_inits` and
`migrate_chezmoi` prints its own line unconditionally near the top of the
function, before anything in it can fail, so all three lines can appear even
when one of them goes on to fail later and `cmd_migrate` returns non-zero.
`rc` is `teeup migrate legacy`'s own exit status, `cmd_migrate`'s `$rc`
propagated: `[[ $rc -eq 0 ]] || n=0` forces the count to `0` whenever the
command itself did not exit clean, so a migration that printed all three
previews and then failed reads the same as one that never ran. **This is the
check that decides, not the four above it.** If it is anything other than
`3` — nothing ran (`teeup migrate legacy` still reaches
`Unknown verb: migrate`, indistinguishable from a tree where 5a never started
or from this plan's own two-line verification stand-in, see Self-review,
"Mechanical transcription", "The 5a stand-in"), some of it ran (a
`cmd_migrate` that calls only some of the three, or comments one out), or all
of it ran but one operation failed — stop. A transcription must not run
Task 7 against any tree that fails one of the checks above.

- [ ] **Step 2: Write the failing check**

```bash edit-old=tests/docs.sh
run_test "the README names every shipped theme" test_the_readme_names_every_shipped_theme
print_summary
```

```bash edit-new=tests/docs.sh
run_test "the README names every shipped theme" test_the_readme_names_every_shipped_theme
run_test "nothing tracked points at the deleted legacy tree" test_nothing_tracked_points_at_the_deleted_legacy_tree
print_summary
```

```bash edit-old=tests/docs.sh
PARITY="$REPO/docs/legacy-parity.md"
```

```bash edit-new=tests/docs.sh
PARITY="$REPO/docs/legacy-parity.md"

# Four files may still say "legacy/". In three of them it is a historical fact
# rather than a path somebody could follow -- the changelog, the parity
# checklist, and the design record under docs/superpowers -- and the fourth is
# this file, which cannot search for a string without containing it. Anywhere
# else it is a broken reference to a tree that no longer exists.
test_nothing_tracked_points_at_the_deleted_legacy_tree() {
  if [[ -d "$REPO/legacy" ]]; then
    echo "legacy/ is still in the checkout"
    return 1
  fi
  local hits=""
  if command -v git >/dev/null 2>&1 && [[ -d "$REPO/.git" ]]; then
    # Tracked files only: an untracked scratch note in somebody's working tree
    # is theirs, and failing their suite over it would be wrong.
    hits="$(cd "$REPO" && git ls-files -z | xargs -0 grep -lF 'legacy/' 2>/dev/null |
      grep -v '^CHANGELOG\.md$' |
      grep -v '^docs/superpowers/' |
      grep -v '^docs/legacy-parity\.md$' |
      grep -v '^tests/docs\.sh$' || true)"
  else
    # A tarball rather than a checkout: fall back to the filesystem.
    hits="$(cd "$REPO" && grep -rlF 'legacy/' \
      --exclude-dir=.git --exclude-dir=superpowers \
      --exclude=CHANGELOG.md --exclude=legacy-parity.md --exclude=docs.sh \
      . 2>/dev/null || true)"
  fi
  assert_equals "" "$hits" "no tracked file points at legacy/" || return 1
}
```

- [ ] **Step 3: Run it to watch it fail**

Run: `bash tests/docs.sh 2>&1 | tail -6`
Expected: `nothing tracked points at the deleted legacy tree` FAILs with
`legacy/ is still in the checkout`.

- [ ] **Step 4: Delete the tree**

```bash
git rm -r --quiet legacy
```

Run: `ls legacy 2>&1`
Expected: `ls: legacy: No such file or directory`.

- [ ] **Step 5: Remove the three legacy CI steps**

```yaml edit-old=.github/workflows/ci.yml
      - name: Shellcheck legacy scripts
        run: shellcheck --severity=warning legacy/teeup.sh legacy/teeup-wizard.sh

      - name: Shellcheck legacy tests
        run: shellcheck --severity=warning -x legacy/tests/*.sh

      - name: Run legacy tests
        env:
          CI: "true"
        run: ./legacy/tests/run_tests.sh

      - name: Shellcheck new runtime
```

```yaml edit-new=.github/workflows/ci.yml
      - name: Shellcheck the runtime
```

The two remaining step names say "new runtime" and "new runtime tests", which
stopped being useful the moment there was only one:

```yaml edit-old=.github/workflows/ci.yml
      - name: Run new runtime tests
```

```yaml edit-new=.github/workflows/ci.yml
      - name: Run the tests
```

- [ ] **Step 6: Reword the comments that name a path inside it**

Four comments in `lib/` say where something came from by naming a file under
`legacy/`. Each note is worth keeping; the path in it is about to stop
resolving, and the parity checklist is the better pointer. `lib/pkg.sh` is the
oldest of them; the other three arrived with phase 5a, which ported
`disable_matching_lines` and the migration's rc patterns out of the old
installer.

```bash edit-old=lib/pkg.sh
# primitive. Ported from legacy/lib/package_manager.sh, macOS only.
```

```bash edit-new=lib/pkg.sh
# primitive. Ported from the previous installer's package_manager.sh, macOS
# only; docs/legacy-parity.md says where the rest of it went.
```

```bash edit-old=lib/files.sh
# Ported from legacy/teeup.sh with two more fixes. The pattern and the reason
```

```bash edit-new=lib/files.sh
# Ported from the old installer with two more fixes. The pattern and the reason
```

```bash edit-old=lib/migrate.sh
# teeup's zsh layer and starship replace. legacy/teeup.sh disabled the antigen
```

```bash edit-new=lib/migrate.sh
# teeup's zsh layer and starship replace. The old installer disabled the antigen
```

```bash edit-old=lib/migrate.sh
# legacy/teeup.sh used, plus the dot-directory each manager puts on PATH.
```

```bash edit-new=lib/migrate.sh
# the old installer used, plus the dot-directory each manager puts on PATH.
```

- [ ] **Step 7: Check nothing else points at it**

Run: `git ls-files -z | xargs -0 grep -lF 'legacy/' | grep -v '^CHANGELOG.md$' | grep -v '^docs/superpowers/' | grep -v '^docs/legacy-parity.md$' | grep -v '^tests/docs.sh$'`
Expected: no output. (`review.md`, if your working tree has one, is untracked
and will not appear. `tests/docs.sh` is excluded because it holds the search
string itself.)

Run: `grep -n legacy .gitignore`
Expected: no output. (There was never an entry; this confirms it rather than
assuming it.)

Run: `grep -rn 'legacy/' lib/ capabilities/ | grep -v 'wezterm.lua'`
Expected: no output. The bare word `legacy` still appears — in `lib/pkg.sh`'s
`docs/legacy-parity.md` pointer, in `lib/files.sh`'s note about "the legacy
call's `\.pyenv`", and throughout `lib/migrate.sh`, whose verb is
`teeup migrate legacy` — but none of those is a path into the deleted tree. `capabilities/wezterm/config/wezterm/wezterm.lua` is excluded above
because its `ok_legacy`/`legacy` are Lua variable names for the
`~/.wezterm_local.lua` hook, with no path in them.

- [ ] **Step 8: Run everything**

Run: `bash tests/docs.sh 2>&1 | tail -4`
Expected: eleven tests, `Summary: 11/11 passed`.

Run: `./tests/run.sh 2>&1 | tail -1`
Expected: `All N suites passed.`, N unchanged from Task 6. The legacy suites
were never part of this runner — `tests/run.sh` globs `tests/lib` and
`tests/capabilities` and `legacy/tests/run_tests.sh` was a separate program
that CI ran on its own — so deleting them changes no count here.

Run: `./bin/teeup commands --check && shellcheck --severity=warning tests/docs.sh && git diff --check`
Expected: no output from any of the three.

Run: `git status --short`
Expected: the deletions under `legacy/` and the two modified files
(`.github/workflows/ci.yml`, `tests/docs.sh`). An untracked `review.md` may
still be listed; leave it where it is.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Delete the legacy installer and its CI steps"
```

**Real-Mac risk:** the one thing no test covers is a person on an old Intel
laptop who was still running `./legacy/teeup.sh --only cli` because the new
runtime had not reached their machine. After this commit that command is gone
from `main` and the answer is `git checkout <the commit before this one> --
legacy` or a tag. Before pushing, confirm the repository has a tag or a release
on a commit that still contains `legacy/`, and if it does not, make one — the
git history keeps the files, but only a name makes them findable.

---

## Verification

Run all of these on the finished tree, in this order.

```bash
./tests/run.sh                                  # every suite, including tests/docs.sh
./bin/teeup commands --check                    # silent, exit 0
./bin/teeup dev check                           # metadata, menu, shellcheck, whole suite
shellcheck --severity=warning bootstrap bin/teeup lib/*.sh \
  $(find capabilities -type f \( -name install -o -name configure -o -name remove \
    -o -name doctor -o -name theme-apply -o -name font-apply \)) \
  tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh tests/docs.sh \
  tests/lib/*.sh tests/capabilities/*.sh
git diff --check
```

Then the things the suite cannot see.

1. **The skill loads.** On a Mac with at least one of the three CLIs installed,
   run `teeup configure teeup-runtime`, then start the agent and ask it to list
   its skills. Claude Code: the skill appears once `~/.claude/skills/teeup`
   resolves. Codex CLI: `~/.agents/skills/teeup` or `~/.codex/skills/teeup`.
   Gemini CLI: `/skills list`, then `/skills reload` if it was started first.
   A skill that is present but never loads at the right moment is a
   `description` problem, not a path problem.
2. **The links are idempotent and harmless.** Run
   `teeup configure teeup-runtime` twice and confirm the second run prints
   `Already linked` for each directory and changes nothing. Put a real
   directory at `~/.agents/skills/teeup` and confirm the third run keeps it and
   warns.
3. **`teeup doctor` is clean on a bootstrapped Mac**, which is phase 4's gate
   and is re-checked here because this phase adds a check to
   `capabilities/teeup-runtime/doctor`.
4. **`teeup menu` walks to every new row.** `teeup menu install` and then each
   of Browsers, Communication, Productivity, macOS extras and Shell and
   containers; every row's action should be `teeup install <cap>` for something
   `teeup list --tier lazy` also names.
5. **The parity checklist reads true.** For each of the thirteen rows, open the
   capability it names and confirm it does the job the row claims. This is the
   spec's phase 5 gate and the last moment it can be taken, because Task 7
   deletes the program the checklist describes.
6. **`legacy/` is findable after the deletion.** `git log -- legacy/teeup.sh`
   should still show its history, and a tag or release should exist on a commit
   that contains it.
7. **CI is green on all three runners** after the workflow edit: `macos-14`,
   `macos-15-intel` and `ubuntu-latest`. The legacy steps are gone, so a
   failure there is a new-runtime failure.
8. **bash 3.2.** Run the whole suite with a bash 3.2 binary first on `PATH`;
   macOS ships 3.2 as `/bin/bash` and the CI runners do not.

## Self-review

### Spec coverage

| Spec requirement | Where |
|---|---|
| Section 4: `share/agents/skills/teeup/` — "SKILL.md for Claude/Codex/Gemini: layout, read-only rules" | Task 1 writes it; Task 2 puts it where all three look. The read-only rules are its own section, naming the generated tree, the answers file, another machine's config, `docs/superpowers/` and `.superpowers/`. |
| Omarchy idea 12: "Dense 'why' comments; ship mental model as an agent skill with read-only boundaries" | Task 1. The skill is one file, as Omarchy's own `diagnose-crash` is, and points at CONTRIBUTING rather than repeating it. |
| Section 12: "Adding a tool later", all seven steps | The skill's "Adding a capability" section is the seven steps; CONTRIBUTING item 1 to 30 (Task 6) is the long form. Step 5 ("add a row to `share/teeup/menu.json`") is also what Task 3 finally does for phase 4c's twenty capabilities. |
| "CLI surface" block | Task 5's README command table, checked against `teeup help` in both directions by `tests/docs.sh`. Every verb in the spec's block exists: `install`/`dev-env`/`font`, `configure`, `update`, `remove`, `reset`, `doctor`, `status`, `list`, `menu`, `launch`, `theme`, `config`, `has`, `migrate`, `secret`, `dev`, `commands`. `lazy-run` is phase 3b's addition to it and is documented too. **One divergence, settled in Task 5 Step 2:** the spec's `teeup list [--tier\|--group\|--json]` shipped with `--tier` only (`cmd_list` in `bin/teeup`), so the README says `--tier` and nothing more. Adding the other two would be a behaviour change made by a documentation phase, so Step 2 amends the spec's CLI-surface block to `teeup list [--tier]` and records underneath why `--group` and `--json` were dropped. Spec, README and `teeup help` then agree. |
| Phase 5 row of "Migration path for the repo": "`teeup migrate legacy`, agent skill, docs; delete `legacy/`", gate "parity checklist against legacy `--list-modules`" | `migrate` is phase 5a. The agent skill is Tasks 1 and 2, the docs are Tasks 5 and 6, the checklist is Task 4 and the deletion is Task 7, in that order so the gate comes first. |
| Section 4's directory tree, including `legacy/ # frozen … (deleted at parity)` | Task 7. |
| "Verification": shellcheck at warning severity on every capability script; `teeup commands --check`; the suite on CI macOS runners | Unchanged, plus `tests/docs.sh` added to `tests/run.sh`'s glob, `dev_shell_files` and the workflow's shellcheck list in Task 1. |

Nothing in the phase 4/5 brief's 5b bullet is left: the skill, the final
README/CONTRIBUTING/docs pass, the parity checklist and the deletion are Tasks
1, 2, 5, 6, 4 and 7.

### Deferred items taken here

The lists named in the phase 4/5 brief were read in full: the phase 1 final
review's triage, the phase 2a final review and re-review triage,
`.superpowers/plan3/pr11-deferred.md`, and the "Deliberately deferred" sections
of plans 3a, 3b, 4a, 4b, 4c and 4d.

| Item | Where it came from | Task |
|---|---|---|
| "The teeup agent skill. It documents the finished runtime and fits phase 5's documentation pass." | plan 3b, Deliberately deferred | 1 and 2 |
| `share/teeup/menu.json` rows for phase 4c's twenty capabilities | plan 4c, "Deferred items" and its Self-review handoff to 4b | 3 |
| CONTRIBUTING's capability list running 1…19, 20, 21, 22, 23, 20, 21, …, 26 with `TEEUP_NO_GUM` stated twice | not on any list: found by reading the file produced by applying 4a, 4b, 4c and 5a together | 6 |

### Deferred items deliberately left

| Item | Reason |
|---|---|
| `alt` bindings in AeroSpace take the Meta key; `keyboard` replaces all `hidutil` mappings; a WezTerm started from the Dock with a non-default config dir; `;` or `?` in a checkout path breaks Lua's search path (pr11) | Four bugs inside three capabilities' own scripts. This phase writes documents and deletes a directory; fixing a capability inside a documentation task is how a reviewer stops reading the diff. |
| `typeset -U fpath path` in the zsh layer (phase 2a #4) | The zsh layer is not touched here, for the same reason. |
| `mock_command` splices `$output` unescaped; `_teeup_log_line` runs `mkdir -p` per line; the `__` collision in `_stock_record_path`; the duplicated `mkdir -p` in `state.sh` (phase 1 items 5, 6, 8, 9) | Test-only or cosmetic, and none of them is in code this plan touches. |
| The wizard asks a question the machine file pins (2a re-review) | Fixed by phase 4d for the theme question and by phase 3a for the Emacs flavor; `bootstrap` is not touched here. |
| Appearance changes do not re-run the theme hooks (3a) | An appearance-watching LaunchAgent is a new background service with its own capability and doctor check. The README says a `theme-set` hook is where a user puts that today. |
| A themed `tmux` configuration and a `tmux` `theme-apply` (3b) | A themed template belongs with the theme work; 4d left it, and adding one here would mean adding a template to a phase that ships none. |
| mise's `upgrade.auto_prune` (3b) | A decision about the user's own mise settings, named as a Real-Mac risk in plan 4a. |
| Launch-or-focus inside a themed floating terminal (3b, spec §6.3) | A presentation decision about a terminal window; `teeup launch` covers the behaviour and the README describes what it does. |
| Doctor checks for Karabiner's four approvals and a signed-in App Store (4c) | Both need a Mac to write against, and neither is documentation. |
| Shims for mise-managed CLI tools other than the AI CLIs (3b) | Still a product decision about which tools deserve a wrapper. |

### Verified against upstream, not guessed

- **Claude Code skill directories.** `code.claude.com/docs/en/skills`: personal
  skills are `~/.claude/skills/<name>/SKILL.md`, project skills
  `.claude/skills/<name>/SKILL.md`, plus nested, enterprise, `--add-dir` and
  plugin locations; a `<skill-name>` entry "can be a symlink to a directory
  elsewhere" and Claude Code reads `SKILL.md` from the target; **`~/.agents/skills`
  and `.agents/skills` are not supported**; frontmatter is optional, `name`
  defaults to the directory name, `description` is recommended, and the opening
  `---` has to be the file's first line or the whole file is content.
- **Codex CLI skill directories.** OpenAI's Codex skills documentation: the scan
  order is repository-local `.agents/skills` walking up to the repo root, then
  `$HOME/.agents/skills`, then `/etc/codex/skills`, then built-ins; "Codex
  supports symlinked skill folders and follows the symlink target when scanning
  these locations"; `SKILL.md` needs `name` and `description`. `~/.codex/skills`
  is where installed skills land in practice — on the machine this plan was
  written on it already holds two symlinked skill directories pointing into
  `/usr/share/omarchy/default/agents/skills`, which is the pattern Task 2
  copies.
- **Gemini CLI skill directories.** `google-gemini/gemini-cli`,
  `docs/cli/skills.md`: four tiers, of which the user tier is
  `~/.gemini/skills/` or `~/.agents/skills/` and the workspace tier is
  `.gemini/skills/` or `.agents/skills/`; "within the same tier … the
  `.agents/skills/` alias takes precedence over the `.gemini/skills/`
  directory"; `/skills list` and `/skills reload` show and refresh what it
  found. Symlink support is not documented either way, which Task 2 records as
  its Real-Mac risk.
- **Omarchy's own installation pattern**, read from
  `/usr/share/omarchy/migrations/1786098807.sh` and `1786539345.sh`:
  `mkdir -p ~/.agents/skills ~/.claude/skills ~/.codex/skills ~/.pi/agent/skills`
  then `ln -sfn "$OMARCHY_PATH/default/agents/skills/<name>" <dir>/<name>` for
  each. Task 2 differs in one way on purpose: it creates only
  `~/.agents/skills` unconditionally and leaves a tool's home directory alone
  when the tool is not installed.
- **The legacy module list, options and environment variables** in Task 4 are
  the verbatim output of `./legacy/teeup.sh --list-modules` and
  `./legacy/teeup.sh --help`, run against the tree, not recalled.
- **The bundle names in Task 3's `launch` rows** are the first `apps=` entry of
  each phase-4c capability's metadata, which that phase checked against
  `https://formulae.brew.sh/api/cask/<token>.json`. This task copies them
  rather than re-deriving them, so a disagreement means the metadata is the
  thing to fix.

### Placeholder scan

Searched for `TBD`, `TODO`, `FIXME`, "implement later", "similar to Task",
"appropriate error handling", "add validation", "handle edge cases" and a bare
`...` standing in for content: no hits. Every new file appears in full in a
`file=` block (`share/agents/skills/teeup/SKILL.md`, `tests/docs.sh`,
`docs/legacy-parity.md`, `README.md`, `CONTRIBUTING.md`); every change to an
existing file is an `edit-old`/`edit-new` pair whose `edit-old` occurs exactly
once at that point. The `...` characters that remain are inside quoted prose or
a `teeup dev new-capability <name>` style placeholder in a command line, where
`<name>` is the argument's name and not a gap in the plan.

Two blocks use four backticks as their fence because their content contains
three-backtick fences of its own: the `SKILL.md` and `README.md` files.

### Name and type consistency

- `agent_skill_link <source-dir> <name>` is spelled the same in `lib/files.sh`
  (Task 2 Step 3), `capabilities/teeup-runtime/configure` (Step 7),
  `tests/lib/files.sh` (Step 1), CONTRIBUTING's agent-skill section (Task 6)
  and the README's Agents section (Task 5). It takes the source directory
  first and the link name second everywhere.
- The four link targets are `$HOME/.agents/skills`, `$HOME/.claude/skills`,
  `$HOME/.codex/skills` and `$HOME/.gemini/skills`, in that order, in the
  helper, the doctor check, the README table and CONTRIBUTING.
- `tests/docs.sh`'s helpers are `help_verbs`, `skill_verbs`, `readme_verbs` and
  `parity_rows`; `SKILL`, `PARITY` and `REPO` are the three paths it holds.
  None of those names exists in another suite.
- The README region markers are `<!-- teeup-commands -->` and
  `<!-- /teeup-commands -->`; the parity markers are `<!-- parity-map -->` and
  `<!-- /parity-map -->`. Each pair appears once in its file and once in the
  test that reads it.
- The menu ids added in Task 3 are `install.browsers.*`,
  `install.communication.*`, `install.productivity.*`, `install.system.*`,
  three more `install.shell.*` and fourteen more `launch.*`. `install.apps` is
  removed, and its three rows move to `install.browsers` and
  `install.productivity`; no other plan refers to `install.apps`, and phase
  5a's row is `setup.migrate`, which does not collide.
- No environment variable is introduced by this plan. The ones it reads
  (`TEEUP_PATH`, `TEEUP_CONFIG_DIR`, `TEEUP_STATE_DIR`, `TEEUP_CAP`,
  `TEEUP_MENU_FILE`, `TEEUP_TESTS_DIR`, `TEEUP_NO_GUM`, `DRY_RUN`) all belong
  to earlier phases.

### Mechanical transcription

**The base.** No scratch tree in the workspace held phases 4a and 4b together,
so one was built: `plan4c/verify` (main + 3a + 3b + 4a + 4c) with phase 4b's
ten tasks and phase 4d's four tasks applied on top by the same
`apply2.py`/`run_tasks.sh` harness the earlier authors used, plus `main`'s
worker-pool `tests/run.sh` (`c08dd63`). Two hand fixes were needed at the time. **Both have since been fixed in phase
4b's own text** (cross-plan pass of 2026-09-16), so the stack now applies
mechanically from 3a to 5b with no hand edits:

1. Phase 4b Task 8 Step 4 used to give two alternatives for `cmd_dev` and tell
   the executor to pick by checking whether phase 4a already created it; a
   mechanical apply took the first, which left two `cmd_dev` definitions and
   two `dev)` dispatch arms, so `teeup dev new-capability` died with
   `Usage: teeup dev add-migration` and `tests/lib/dev.sh` failed. Step 4 is
   now one `edit-old`/`edit-new` pair against phase 4a's function, and Task 9
   Step 4 anchors on its result.
2. Phase 4b's `lib/all.sh` anchors did not include 4a's `hooks migrations`, so
   the `edit-old` strings were rewritten to the merged loader line before
   applying. All six blocks in 4b now carry `hooks migrations`.

With those, the base is **`All 60 suites passed.`**, `teeup commands --check`
silent, exit 0.

**The 5a stand-in.** Phase 5a's plan was in draft while this one was written:
its Contracts, File structure and task list were final, Tasks 1 to 4 were
written, Tasks 5 to 9 were not. Rather than transcribe half a plan, the base
carries a two-line stand-in for the one interface this plan consumes — the
usage line `teeup migrate legacy` and a `migrate)` dispatch arm — so that
`tests/docs.sh`'s "the README documents every verb teeup has" check runs
against the verb set the finished tree will have. **Everything else about 5a in
this plan is unverified by transcription** and is listed in "What was assumed
about phase 5a" above: the leftover doctor checks, the `setup.migrate` menu
row, `lib/migrate.sh`, and 5a's own README and CONTRIBUTING edits. If 5a lands
differently, the README section "Coming from an older setup" (Task 5) and the
parity rows for `--reconcile-existing-config` and `RECONCILE_EXISTING_CONFIG`
(Task 4) are what to re-read.

**The transcription.** Every `file=` block was written and every
`edit-old`/`edit-new` pair applied, in task order, to a copy of that base;
after each task the whole suite, `./bin/teeup commands --check`,
`shellcheck --severity=warning` on every touched script and `git diff --check`
were run. Tasks 1 to 6 went through the harness unchanged; Task 7's `git rm -r
legacy` is not something the harness performs, so it was run by hand and the
suite re-run afterwards.

Five defects were found this way and fixed in the plan text rather than left
for the executor:

1. `tests/docs.sh` was placed at the top of `tests/` and therefore invisible to
   both shellcheck lists: the workflow names its test files one by one, and
   `dev_shell_files` in `lib/dev.sh` globs `tests/lib` and `tests/capabilities`
   but names the top-level suites explicitly. Task 1 Step 5 now edits both.
2. `assert_contains "$body" '~/.local/state/teeup/'` tripped shellcheck's
   SC2088 (a quoted word starting with `~`). The needle lost its tilde.
3. The skill's "Where to read more" pointed at `docs/legacy-parity.md`, which
   Task 4 creates: the "names only paths that exist" check failed at Task 1.
   The pointer moved into Task 4, which is also where the parity task was moved
   to — before the README rather than after it, so that the README's link to it
   resolves at every commit.
4. Four `something | grep -q` pipelines were a race under `set -o pipefail`:
   `grep -q` exits on its first match, the upstream command takes SIGPIPE, and
   whether the pipeline reports failure depends on how much fitted in the pipe
   buffer. The parity check failed intermittently and passed on the next run.
   All four became `grep -q … <<<"$var"`.
5. The "nothing points at `legacy/`" check read the working tree, where an
   untracked `review.md` (a phase-2a branch review, `git ls-files` prints
   nothing for it) mentions `./legacy/tests/run_tests.sh`. It now reads
   `git ls-files`, and the plan no longer moves or deletes that file. The check
   also caught `lib/pkg.sh`'s "Ported from `legacy/lib/package_manager.sh`"
   comment, which Task 7 Step 6 now rewords so the note survives without a path
   that stops resolving — and, once every task was committed rather than only
   applied, it caught **itself**: `tests/docs.sh` cannot search for the string
   `legacy/` without containing it. The exclusion list names it, with a comment
   saying why.
6. `tests/docs.sh` sourced `"$(dirname "$0")/../helper.sh"` with a fallback,
   copied from a suite that lives one directory deeper. Under bash 5 the
   fallback worked; under bash 3.2.0 the whole suite exited 1 before printing a
   line, because a failed `source` of a missing file inside `set -e` ends the
   script. It is now the one-line form `tests/cli.sh` and `tests/bootstrap.sh`
   use, which is correct for a suite at the top of `tests/`. This is the one
   defect in the list that no amount of running under the developer's own bash
   would have found.

**The result.** All seven tasks applied and committed in order on that base.

| After task | Suite | `commands --check` | shellcheck | `git diff --check` |
|---|---|---|---|---|
| 1 | `tests/docs.sh` 4/4; whole suite **All 61 suites passed.** (60 + the new one) | rc=0, silent | clean on `lib/dev.sh tests/docs.sh tests/run.sh` | clean |
| 2 | `tests/lib/files.sh` 27/27, `tests/capabilities/teeup-runtime.sh` 16/16, `tests/docs.sh` 4/4 | rc=0, silent | clean on all five touched files | clean |
| 3 | `tests/lib/menu.sh` 17/17, `tests/lib/dev.sh` 15/15, `tests/docs.sh` 4/4; whole suite **All 61 suites passed.** | rc=0, silent | clean | clean |
| 4 | `tests/docs.sh` 6/6 | rc=0, silent | clean | clean |
| 5 | `tests/docs.sh` 10/10 | rc=0, silent | clean | clean |
| 6 | `tests/docs.sh` 10/10 | rc=0, silent | — (Markdown only) | clean |
| 7 | `tests/docs.sh` 11/11; whole suite **All 61 suites passed.** | rc=0, silent | clean on `lib/pkg.sh tests/docs.sh` | clean |

The finished tree was then run twice more end to end: the whole suite under the
host bash, **All 61 suites passed.**, and the whole suite with a bash 3.2.0
build first on `PATH` and invoking `tests/run.sh`, **All 61 suites passed.**
`legacy/` is gone in that tree, `git log -- legacy/teeup.sh` still shows its
history, and the deletion commit is 6,968 lines removed across
`legacy/` plus fifteen changed lines in `.github/workflows/ci.yml`.

The suite count is 61 rather than 60 because `tests/docs.sh` is the one new
suite; a tree that has phase 5a merged will have whatever count 5a leaves, plus
one. Nothing in this plan hard-codes it.
