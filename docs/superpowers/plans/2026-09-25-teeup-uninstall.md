# teeup uninstall Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give teeup a verb that takes it off a Mac -- `teeup uninstall [--packages] [--identity] [--yes]` -- that removes the zsh layer's lines before any tool those lines hook, reuses `teeup remove`'s machinery for every capability, keeps what the user owns unless told otherwise, previews under `DRY_RUN=true` without changing or claiming anything, prints a summary in four columns (removed, kept, refused, failed), exits non-zero on any refusal or failure, and does nothing on a second run.

**Architecture:** One new library, `lib/uninstall.sh`, behind one new verb, plus a small refactor that lets the verb share `teeup remove`'s code. `cap_remove <name> <true|false>` moves out of `cmd_remove` into `lib/capability.sh`, with a second argument that decides whether packages come off and is passed to `remove` scripts as `TEEUP_REMOVE_PACKAGES`. `cmd_uninstall` runs six steps in a fixed order -- the zsh home files, the capabilities (dependents first), teeup's LaunchAgents, the config files by the stock-checksum rule, the identity (only with `--identity`), and last teeup's own command, config and state (only after a clean run). Every step writes into one ledger, and every deletion goes through `uninstall_rm`, which reuses `lib/migrate.sh`'s gates (inside the physical `$HOME`, not inside a git checkout, not the chezmoi source, and a symlink is removed as a link rather than followed). What to remove comes from teeup's own records -- done markers, stock records, the `sh.teeup.` LaunchAgent prefix -- never from a list of paths in the new library.

**Tech Stack:** bash 3.2 (macOS stock), BSD `awk`/`sed`/`find`, zsh 5.9 (`zsh -f -n` as a parse check), `launchctl`, `security`, `dscl`, `ssh-add`, Homebrew and MacPorts, the phase 1 mock-binary test harness, phase 4a's `copy_config_once` stock records, phase 5a's `migrate_resolve`/`migrate_path_is_safe`/`disable_matching_lines`.

**Spec:** `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md`, the section "Amendment 2026-09-25: `teeup uninstall`" under the CLI surface, which this plan implements in full (it is committed with this plan). Also section 9's stock-checksum rule and section 10's rule that nothing may leave the user without a `~/.zshrc`.

**Runs:** after phase 4b (menu, `teeup config`, `teeup dev new-capability`/`check`) and before phase 5b. Phase 4b is not merged on `main` today. Every anchor below was measured on `main` at `31a4644`; three things 4b also changes are called out where they occur -- the `lib/all.sh` source list (the same one-word edit either way), the number of the new `CONTRIBUTING.md` item, and the suite counts -- and every other anchor is text 4b leaves as it is (checked against `feat/phase4b-menu-config-dev` at `997ae74`; see Self-review).

---

## How this plan was checked

Every code block below was run before it was written down. The whole change was built on a scratch copy of `main` at `31a4644` and put through CI's full shellcheck command, `./bin/teeup commands --check`, `git diff --check` and `./tests/run.sh` (52 suites, all passing) on Linux with bash 5.3, gawk and zsh 5.9. The plan text itself was then generated from that copy and replayed: starting from the live tree, every `edit-old` block below was checked to occur exactly once at the point it is applied, every `file=` block was checked not to exist yet, and the tree the replay produced was compared byte for byte with the tested copy.

What that did not prove: bash 3.2, BSD `awk`/`sed`/`find`, and anything only a Mac has (`launchctl`, `security`, `dscl`, `ssh-add --apple-use-keychain`, `/private/var/folders`). Those are CI's macOS runners and each task's **Real-Mac risk** note. Five things the prototype caught are now rules in Global Constraints, because the obvious version of each is wrong: a local variable named after a metadata key, a `*` glob over stock records, a bare `zsh -n`, a bare `[[ ]] &&` that ends a function, and a refusal returned as a plain statement's status, which `set -e` turned into the end of the run before its summary -- found by a CLI test written while reviewing this plan, after every library test had passed.

---

## Global Constraints

Every task's requirements implicitly include this section.

- **bash 3.2 compatible.** No `mapfile`, `readarray`, `declare -A`, `${var,,}`, `readlink -f`, `**`, `&>>`, `wait -n`. No same-line `local` back-reference (`local a=1 b=$a`). bash 3.2 mis-parses a quoted pattern containing `/` inside `${var//pat/repl}`: use `replace_literal` (`lib/files.sh`), as `uninstall_stock_paths` does. Before merging Task 3, run `tests/lib/files.sh` and `tests/lib/uninstall.sh` under a real bash 3.2 (rebuild bash-3.2.57 from ftp.gnu.org with `CFLAGS="-O0 -std=gnu89 -fcommon -Wno-implicit-function-declaration -Wno-implicit-int -Wno-int-conversion"` if none is at hand): `ere_quote` walks a string with `${text:i:1}`, and the shell-file rendering depends on `printf %q`.
- **BSD tools only.** No GNU-only flags, no `\t` or `\n` in `sed` replacements, no `grep -P`. An awk value that can hold a backslash reaches awk through `ENVIRON`, never `-v`.
- **`set -eu` everywhere.** `bin/teeup` and every `lib/*.sh` function run under it, and capability scripts run as `bash -eu`. Never write a bare `[[ ]] && cmd` as a statement: when the test is false the statement returns 1, and as the last statement of a function (or of a `while` body) it becomes the function's status. `_uninstall_section` did exactly that in the prototype and only survived because every caller happened to sit on the left of a `||`. Use `if ... then ... fi`.
- **A refusal is a ledger line, never an exit status left for `set -e`.** `uninstall_rm` notes its own outcome and returns 1 on a refusal or failure, and so does `uninstall_offer_restore` when it put nothing back. Every call is in an `if` or ends `|| true`, and every step function returns 0. A bare `uninstall_rm "$TEEUP_STATE_DIR"` as the last line of the teardown ended `teeup uninstall` with no summary at all when the state directory was refused. The library tests cannot see this -- `run_test` calls every test function with `set +e` -- so the verb's own tests in `tests/cli.sh` drive a refusal through the first step and through the last one.
- **No local named after a metadata key.** `cap_meta_get` sources the `capability` file in a subshell, and that subshell sees the caller's locals: a capability that does not set `packages=` reads the caller's `$packages` instead. The first version of `cap_remove` had `local packages="$2"` and every fixture reported the package `true`. The reserved names are `summary group tier requires provides packages casks apps interactive package_commands`.
- **Every mutation goes through `run_cmd`/`run_privileged` or a `DRY_RUN`-guarded primitive** (`write_managed_file`, `backup_target`, `backup_copy`, `disable_matching_lines`, `_state_touch`, `launchagent_remove`). In `lib/uninstall.sh` the only deletion is `uninstall_rm`; `_uninstall_prune_dirs` uses `rmdir`, which removes nothing but an empty directory, and returns at once under `DRY_RUN`. `DRY_RUN=true teeup uninstall` changes nothing, asks nothing and claims nothing: every success line is `ok_unless_dry` after a checked mutation, and the summary's first column is titled "Would remove".
- **zsh is always run with `-f`.** Without it, `zsh -n <file>` sources `~/.zshenv` first -- teeup's own shell layer, in the middle of its removal, and in a test the harness's mocked `hostname` appends to `$MOCK_LOG`, which made the first dry-run test flaky.
- **Stock records are dotfiles.** `_stock_record_path` names a record after the path relative to `$HOME`, so nearly every name starts with a dot (`.config__git__config`, `.zshrc`). A `*` glob misses them; `uninstall_stock_paths` globs `* .[!.]* ..?*`.
- **Paths.** `user_config_dir` for `~/.config`; `TEEUP_CONFIG_DIR`, `TEEUP_STATE_DIR`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME` and `ZDOTDIR` are honoured everywhere. Paths with spaces and shell metacharacters must work: the new suites use a config directory named `con fig $x`, a ZDOTDIR named `z dot`, a directory named `it's a $dir` and a state directory named `st ate $x`.
- **Physical paths in assertions** (phase 5a's R2). `uninstall_rm` acts on the resolved path, and on macOS `$TEST_HOME` under `/var/folders` resolves to `/private/var/folders`. An assertion on a path teeup printed compares against `HOME_P="$(cd "$TEST_HOME" && pwd -P)"`.
- **Every printed fix is a command that works, and a test runs it.** Paths in a printed command go through `uninstall_q` (`printf %q`), and the tests run the command with `run_fix`, which uses zsh when the machine has it (every CI runner does; it is what the user will paste into) and bash otherwise.
- **Tests never touch the real machine or the checkout.** Every suite runs under `tests/helper.sh`. `TEEUP_MACHINES_DIR` defaults to the checkout's `machines/`, so every uninstall test sets it to `$TEST_HOME/machines`. `chezmoi` is hidden with `hide_host_commands chezmoi`, so `migrate_path_is_safe` answers the same on every runner. The real zsh capability's `configure` may be run from the checkout (it only reads the checkout; everything it writes lands under `$TEST_HOME`). `tests/run.sh` fails the run when any test leaves a file behind in the checkout or changes a mode there.
- **Prompts in tests.** `lib/ui.sh` uses gum whenever `TEEUP_NO_GUM` is empty and `gum` is on `PATH`, and the narrowed `PATH` can still expose `/usr/bin/gum`: every test that can reach a prompt exports `TEEUP_NO_GUM=1`. `TEEUP_TEST_TTY=yes|no` decides whether there is a terminal (`lazy_is_tty`).
- **Capability metadata contract** is unchanged: `summary group tier requires provides packages casks apps interactive` (plus `package_commands`). No capability is added or moved between tiers, and no capability gains a `remove` script -- `tests/docs.sh` pins the README's count of them ("six capabilities ship one today") and the seven `teeup remove` refuses.
- **Suite counts** (phase 5a's R3). `tests/run.sh` ends with `All N suites passed.` Never paste a number from this plan into an expectation for an existing suite: print the count before the task and expect that count plus K. Phase 4b adds suites and tests to `tests/cli.sh`, so the counts on `main` today are not the ones the executor will see. Only a new suite's own `Summary: x/y passed` is given exactly.
- **Nothing here has run on a real Mac.** Each task carries a **Real-Mac risk** note naming what only hardware proves.
- **Verify, do not guess** every external command, flag and URL a note prints (Self-review lists them) against the installed tool's `--help`, its `man` page on a Mac, or upstream documentation, before the task that prints it merges.
- **Plain prose** in every comment, log line, note and doc: none of "No X, no Y" chains, "Did not X, did not Y" chains, "That's the whole ...", "Don't X it. Y it.", "Sit with that", "You already know", "is the entire", "The entire ... is", "X is real, and ...", "The punchline", "Worth naming".
- **Every task ends with** `./tests/run.sh` green, CI's full shellcheck command (Task 1 prints it) silent, `./bin/teeup commands --check` silent with exit 0, `git diff --check` clean, and **one** commit with a plain imperative subject and no trailer of any kind (no `Co-Authored-By`, no `Claude-Session`, no "Generated with").

---

## Review Focus

The five inputs the spec implies but a first reading of it would not test, most likely to bite first. Each has a test in the task named.

1. **The shell that sources a hook for a tool already gone.** A Mac emptied with a loop of `teeup remove` on 2026-09-25 printed `_mise_hook:1: no such file or directory: /opt/homebrew/bin/mise` and the same for starship on every prompt, because `~/.zshrc` still loaded the layer when mise and starship came off. The zsh home files are the first mutation; the running shell cannot be unhooked, so the run ends by saying to open a new terminal. Task 6's `test_uninstall_takes_the_shell_layer_off_before_what_it_hooks` has each fixture `remove` script record, at the moment it runs, whether the layer is still loaded -- and fails when the order in `cmd_uninstall` is swapped (checked while writing this plan).
2. **A home file teeup must not write.** A `~/.zshrc` that is a symlink into a dotfiles repo, or a `ZDOTDIR` inside a git checkout: refused with what to do, nothing written through the link or into the repo, exit non-zero. Task 3's symlink and `ZDOTDIR` tests.
3. **`--packages` on a Mac whose login shell is Homebrew's zsh.** Uninstalling the `zsh` formula would leave Terminal nothing to start. zsh's packages are refused with `chsh -s /bin/zsh` and the rerun command, and zsh stays marked installed so that rerun can finish. Task 4's login-shell test.
4. **Something fails or is refused half way.** A `remove` script that fails must not be followed by its requirements coming off; any refusal or failure must still reach the summary (not end the run under `set -e`), make the run exit non-zero, and leave teeup's state and command in place so the printed rerun works -- and the rerun, once the cause is fixed, must finish the job. Task 4's failed-dependent test; Task 6's fails-loudly test and its two tests that drive a refusal through the first and the last step of the real verb.
5. **Overridden or awkward teeup directories.** A `TEEUP_CONFIG_DIR` with a space and a `$` renders the env line as `%q` escapes, which the stripping pattern must still match literally (Task 3, through `ere_quote`); a `TEEUP_STATE_DIR` outside `$HOME` is refused and the printed `rm -rf` really removes it (Task 6's teardown test).

---

## Depends on

`main` at `31a4644` is the ground truth for everything in this table except the last row.

| Interface | Where |
|---|---|
| `log ok warn err die ok_unless_dry have run_cmd user_config_dir macos_major` | `lib/core.sh` |
| `file_sha stock_sha config_is_pristine write_managed_file backup_target copy_config_once replace_literal block_opener_ere disable_matching_lines` | `lib/files.sh` |
| `_stock_record_path` naming: path relative to `$HOME`, `/` turned into `__` | `lib/files.sh:20` |
| `state_done check|mark|clear`, `state_na check|clear` | `lib/state.sh` |
| `answers_load answers_get machine_file identity_key` and `TEEUP_MACHINES_DIR` | `lib/answers.sh` |
| `pkg_backend pkg_backend_label pkg_prefix package_candidates pkg_installed pkg_uninstall casks_supported cask_installed cask_uninstall` | `lib/pkg.sh` |
| `ui_confirm <prompt> no` | `lib/ui.sh` |
| `cap_list cap_dir cap_exists cap_meta_get cap_order cap_run` and `TEEUP_CAP_NA` | `lib/capability.sh` |
| `launchagent_remove <label>` (plist at `~/Library/LaunchAgents/<label>.plist`) | `lib/macos.sh` |
| `lazy_is_tty` (honours `TEEUP_TEST_TTY`) | `lib/lazy.sh` |
| `TEEUP_HOOK_EVENTS` (`post-bootstrap post-update theme-set`) | `lib/hooks.sh` |
| `migrate_resolve migrate_in_git_checkout migrate_path_is_safe` | `lib/migrate.sh` |
| `cmd_remove` and its eight tests in `tests/cli.sh` | `bin/teeup` |
| `capabilities/{emacs,wezterm,colima,keyboard,macos-defaults,ai}/remove`; `sh.teeup.emacs` and `sh.teeup.keyboard` agents | the capabilities |
| the zsh home files and the `%q`-rendered env line | `capabilities/zsh/configure`, `capabilities/zsh/home/` |
| `~/.config/git/{config,identity,teeup-generated}` and the `# Generated by teeup` first line | `capabilities/git/configure` |
| `~/.local/bin/teeup`, `$TEEUP_CONFIG_DIR/{env,hooks/<event>.d/example.sample,machines}` | `capabilities/teeup-runtime/configure` |
| `setup_test_env mock_command mock_command_script mock_macos_base hide_host_commands` and the assertions | `tests/helper.sh` |
| The `lib/all.sh` source list, and `CONTRIBUTING.md` items 29 to 32 | **phase 4b**, `feat/phase4b-menu-config-dev` at `997ae74`; not merged |

---

## Contracts this plan publishes

1. **`cap_remove <name> <true|false>`** (`lib/capability.sh`). Runs `capabilities/<name>/remove` when there is one, with `TEEUP_REMOVE_PACKAGES` exported as the second argument; then, only when it is `true`, `cask_uninstall` each of `casks=` and `pkg_uninstall` each of `packages=`; then clears the done and not-applicable markers. Returns 0 removed, 1 a cask or package would not uninstall (marker kept), 2 nothing to undo (no script, no packages or casks; nothing run, marker kept), 3 the remove script failed (nothing uninstalled, marker kept). Leaves `TEEUP_CAP_NA` as the script answered. The caller has already checked that the capability is installed and that nothing installed requires it. `cmd_remove` calls it with `true` and keeps every message it printed before.
2. **`TEEUP_REMOVE_PACKAGES`**, read by `remove` scripts: `false` means keep software installed. `emacs` and `wezterm` then leave their MacPorts port; `colima` leaves its VM running and its Compose link in place. Unset means `true`, so `teeup remove` behaves as it does today.
3. **`ere_quote <text>`** (`lib/files.sh`) prints an ERE matching exactly `<text>`: each of `\ ^ $ . [ ( ) * + ? { } |` gets a backslash.
4. **The ledger** (`lib/uninstall.sh`). `uninstall_note <removed|kept|refused|failed> <text>`; `uninstall_clean` is 0 when nothing was refused or failed; `uninstall_summary` prints the four columns and returns `uninstall_clean`'s status. Kept is a policy outcome and never makes the run fail.
5. **`uninstall_rm <path> [label]`**: the only deletion. Nothing there is 0 with no note. Otherwise the path must pass `migrate_resolve` and `migrate_path_is_safe`, or it is refused with the `rm` that removes it by hand; a directory gets `rm -rf`, anything else (a symlink included, which is never followed) `rm -f`; the result is checked on disk. Notes its own outcome; 0 removed or absent, 1 refused or failed.
6. **`uninstall_offer_restore <path>`**: when `<path>.teeup_backup_*` exists, asks (terminal only, default no) to move the newest back over `<path>`; otherwise notes it as kept with the `mv` that puts it back. 0 only when it put one back.
7. **Step functions**, called by `cmd_uninstall` in this order: `uninstall_shell`, `uninstall_capabilities`, `uninstall_launchagents`, `uninstall_configs`, `uninstall_identity` (only with `--identity`), `uninstall_teardown`. Each reads `DRY_RUN`, `_UNINSTALL_ASK`, `_UNINSTALL_PACKAGES` and `_UNINSTALL_IDENTITY`, writes only to the ledger and through the primitives above, and always returns 0.
8. **`teeup uninstall [--packages] [--identity] [--yes]`.** Exit 0 when nothing was refused or failed (a decline at the first question is also 0, with "Nothing was changed."); 1 otherwise, and on a usage error, on root, and on a real run with no terminal and no `--yes`. The last line of a real run is always "Open a new terminal (or run: exec /bin/zsh -l)...".

---

## Decisions made here

1. **The zsh home files come first, before any capability.** Required by the real run of 2026-09-25 (Review Focus 1). The capability loop cannot do it in dependency order: `starship` requires `zsh`, so reverse order would remove starship first.
2. **A pristine `~/.zshrc` is replaced, never removed; pristine `.zshenv` and `.zprofile` are removed.** Phase 5a's rule is that nothing leaves the user without a `~/.zshrc`. The replacement is two comment lines and, when the user edited `~/.config/zsh/local.zsh` (so it stays), the line that sources it -- their own settings keep loading. An edited home file keeps every line of the user's and has teeup's lines neutralised by `disable_matching_lines` (backup beside it), because a user's file is the one place where deleting a line inside an `if` can break the shell; zsh then checks the result parses (`zsh -f -n`), and a file that parsed before and does not after is put back from the backup and reported as failed.
3. **"teeup's lines" are three literal markers:** the env line as `zsh/configure` renders it (the `%q` path of `$TEEUP_CONFIG_DIR/env`), the same line unrendered, and `TEEUP_PATH`. `ere_quote` makes the first two literal. A user line naming `TEEUP_PATH` is dead after the uninstall anyway, since nothing sets it. The `local.zsh` include is not one of them: it is how the user's own file loads.
4. **After the shell step changed something, the package manager's PATH line is named.** teeup's layer is what put `/opt/homebrew/bin` (or `/opt/local/bin`) on PATH, and Homebrew and the kept packages stay. The note prints the line each package manager documents, with the `echo ... >> ~/.zprofile` that adds it; nothing is written for the user. Intel Homebrew (`/usr/local`) needs nothing.
5. **Packages are asked about, default no.** On a terminal, one question after the first confirmation. With `--yes`, with no terminal, or in a dry run, packages stay unless `--packages` was given. What stays is named, once, with the `brew uninstall ...` / `sudo port uninstall ...` / `brew uninstall --cask ...` that removes exactly the names installed here (each checked with `pkg_installed`/`cask_installed`, so the printed command never names something missing). `gum` and `jq`, which `teeup-runtime` installs without naming them in metadata, are outside this: the spec's rule is "the packages the metadata names".
6. **A real run with no terminal needs `--yes`.** *For the user to confirm.* The decision given was "with no terminal (or `--yes`) keep packages unless `--packages`"; it did not say whether a run with no terminal may proceed at all. A destructive verb that runs unasked when piped is the riskier reading, so it refuses and names both `DRY_RUN=true teeup uninstall` and `teeup uninstall --yes`. Dropping the refusal is a two-line change in `cmd_uninstall`.
7. **The seven capabilities `teeup remove` refuses** (spec amendment's table): `xcode-clt` kept (git, compilers and the package manager need it; the note names `sudo rm -rf /Library/Developer/CommandLineTools`); `package-manager` kept (never; the note names Homebrew's own uninstaller or MacPorts' documented procedure); `dev-dirs` keeps `~/Work` even when empty (the projects are there, and teeup cannot tell a directory it made from one the user made); `secrets` keeps every Keychain item and names each one with the `security delete-generic-password` that deletes it (the user's data, not teeup's configuration); `ssh` keeps keys and `~/.ssh/config` unless `--identity`; `teeup-runtime` and `theme` are teeup's own state and go in the teardown. None of the seven counts as a refusal, so none of them stops the teardown.
8. **`--identity` removes only what teeup's convention names.** The keys at `~/.ssh/id_ed25519_personal` and `_work` (and their `.pub`), after `ssh-add -d` with the Keychain flag `ssh/configure` stored them with; `~/.ssh/config` only when pristine; `~/.config/git/identity` (generated) and `~/.config/git/config` (when pristine). A key the user's own `~/.ssh/config` named at another path is theirs and stays. On a terminal it asks first (default no), naming the key files, since a private key that exists nowhere else cannot come back. Keys uploaded to GitHub are named with https://github.com/settings/keys; teeup does not call the GitHub API during an uninstall.
9. **`~/.config/git/local` is moved aside with `--identity`, not deleted.** *For the user to confirm.* The decision listed it with the identity, so it leaves git's view with `--identity`. But teeup never writes it -- it is the user's own overrides file -- so it goes to `local.teeup_backup_<ts>` through `backup_target` rather than being deleted.
10. **Without `--identity`, `~/.config/git/config` stays even when pristine, and `teeup-generated` goes either way.** git reads the kept identity through `config`, so removing it would remove the identity from git's view without touching the file. `teeup-generated` is teeup's (it says so on its first line and is rewritten on every configure), and it points `core.editor` at `emacsclient -t`, which fails once the Emacs agent is gone. Without it the shipped `commit.gpgsign = true` is back in charge; when the key is missing the note prints `git config --file <config> commit.gpgsign false`, and a test runs it.
11. **The teardown runs only after a clean run.** `~/.local/bin/teeup`, `$TEEUP_CONFIG_DIR` and `$TEEUP_STATE_DIR` hold what a rerun needs: the stock records that tell pristine from edited, the done markers, the recorded `defaults`. After any refusal or failure they stay and the summary says why; every rerun command printed uses the checkout's `bin/teeup` by absolute path, so it works whether or not the link is still there.
12. **`$TEEUP_CONFIG_DIR` loses only teeup's files when the user has their own there.** teeup's are `env`, `answers` and each `hooks/<event>.d/example.sample`. A personal machine file, a hook, a theme or a template override stays, the directory with it, and the note names them with the `rm -rf` that finishes the job. With nothing of the user's in it, the directory goes whole.
13. **`TEEUP_SKIP` is ignored.** A capability the machine file skips now may have been installed before; it is teeup's either way.
14. **A capability still required by one that failed is refused**, and it stays marked installed for the rerun. Kept-by-policy and teardown capabilities count as handled, so `ssh` kept without `--identity` does not block `git`.
15. **What tools made for themselves is named, not removed.** Runtimes under mise's data directory, a Doom or Spacemacs checkout, and the theme and font keys teeup set inside Zed's and VS Code's own `settings.json` were never tracked by teeup. One kept line names them when any of `mise`, `emacs`, `zed` or `vscode` was installed.
16. **No menu row.** Phase 4b's menu is for things done often; this verb is done once and deletes things.
17. **LaunchAgents are swept by prefix after the capability loop.** `emacs/remove` and `keyboard/remove` take their own agents; the sweep catches an `sh.teeup.*` plist left by a capability that is no longer marked installed. A symlinked plist is refused.

---

## File structure

| Path | Responsibility | Task |
|---|---|---|
| `lib/capability.sh` | `cap_remove` | 1 |
| `bin/teeup` | `cmd_remove` calls `cap_remove`; `cmd_uninstall`, its usage lines and dispatch | 1, 6 |
| `capabilities/{emacs,wezterm,colima}/remove` | honour `TEEUP_REMOVE_PACKAGES=false` | 1 |
| `lib/uninstall.sh` | new: ledger, `uninstall_rm`, restore offers, then one section per step | 2 to 6 |
| `lib/all.sh` | sources `uninstall` | 2 |
| `lib/files.sh` | `ere_quote` | 3 |
| `tests/lib/capability.sh`, `tests/capabilities/{emacs,wezterm,colima}.sh` | `cap_remove` and the three scripts | 1 |
| `tests/lib/uninstall.sh` | new: every step, every refusal, every printed fix | 2 to 6 |
| `tests/lib/files.sh` | `ere_quote` | 3 |
| `tests/cli.sh` | the verb end to end, the order proof, dry run, rerun, prompts | 6 |
| `README.md`, `CONTRIBUTING.md` | the verb, and the contributor rule | 7 |

`tests/run.sh` needs no edit (it globs `tests/lib/*.sh`), and neither does CI (its shellcheck step globs `lib/*.sh` and `tests/lib/*.sh`).

**Reading this plan mechanically.** Every fenced block whose info string carries `file=<path>` is the complete content of a file that does not exist yet. Every edit to an existing file is a pair of blocks, `edit-old=<path>` (text that exists at that point, occurring exactly once) followed by `edit-new=<path>` (what replaces it); pairs within a step are applied in the order given. Blocks without either marker are commands and change nothing. A block whose content contains three backticks is fenced with four.

---

## Tasks

1. `cap_remove`: `teeup remove`'s removal, shareable, with packages optional
2. `lib/uninstall.sh`: the ledger, `uninstall_rm`, restore offers and the capability order
3. The shell layer comes off first
4. The capabilities, dependents first, and teeup's LaunchAgents
5. Config files by the stock-checksum rule, and `--identity`
6. The teardown and `teeup uninstall`
7. README and CONTRIBUTING

---

### Task 1: `cap_remove` -- `teeup remove`'s removal, shareable, with packages optional

`teeup uninstall` must run every capability's removal the way `teeup remove` does, but keep packages unless asked. The removal lives inside `cmd_remove` today, fused with messages and `die`s that end the process. It moves into `lib/capability.sh` as `cap_remove`, which returns a status instead of exiting, and `cmd_remove` becomes a caller that prints exactly what it printed before (its eight tests in `tests/cli.sh` are the proof and are not edited). Three `remove` scripts do package work of their own, so they learn to skip it.

**Files:**
- Modify: `lib/capability.sh` (append after `cap_run_hooks`), `bin/teeup` (`cmd_remove`), `capabilities/emacs/remove`, `capabilities/wezterm/remove`, `capabilities/colima/remove`
- Test: `tests/lib/capability.sh`, `tests/capabilities/emacs.sh`, `tests/capabilities/wezterm.sh`, `tests/capabilities/colima.sh`

**Interfaces:**
- Consumes: `cap_meta_get`, `cap_dir`, `cap_run` and `TEEUP_CAP_NA` (`lib/capability.sh`); `cask_uninstall`, `pkg_uninstall` (`lib/pkg.sh`); `state_done clear`, `state_na clear` (`lib/state.sh`).
- Produces: `cap_remove <name> <true|false>` returning 0/1/2/3 (Contract 1) and the `TEEUP_REMOVE_PACKAGES` variable (Contract 2). Task 4 calls `cap_remove` with `false` by default.

**Real-Mac risk:** the MacPorts branches of `emacs/remove` and `wezterm/remove` have never run against a real `port`. With `TEEUP_REMOVE_PACKAGES=false`, `colima/remove` leaves a running Colima VM and the `~/.docker/cli-plugins/docker-compose` link alone; whether a kept Colima keeps working after teeup's state is gone is only provable on a Mac (nothing in teeup's state is read by Colima, so it should).

- [ ] **Step 1: Write the failing tests**

`cap_remove` in `tests/lib/capability.sh`, before its `echo "lib/capability.sh"` line, and registered at the end:

```bash edit-old=tests/lib/capability.sh
echo "lib/capability.sh"
```
```bash edit-new=tests/lib/capability.sh
# A capability with a remove script that reports what it was told, and a
# package and a cask for cap_remove's own loop. brew answers "installed" to
# every list query and logs every call.
make_removable() {
  cat >> "$TEEUP_CAPS_DIR/alpha/capability" <<'EOF2'
packages="ripgrep"
casks="wezterm"
EOF2
  printf '#!/usr/bin/env bash\necho "remove:alpha packages=${TEEUP_REMOVE_PACKAGES:-unset}"\n' > "$TEEUP_CAPS_DIR/alpha/remove"
  chmod +x "$TEEUP_CAPS_DIR/alpha/remove"
  mock_command brew 0 ""
  state_done mark cap-alpha
}

test_cap_remove_with_packages_runs_the_script_then_uninstalls() {
  setup
  make_removable
  local out rc=0
  out="$(cap_remove alpha true 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "remove:alpha packages=true" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall --cask wezterm" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall ripgrep" || return 1
  state_done check cap-alpha && { echo "the marker must be cleared"; return 1; }
  [[ -z "${TEEUP_REMOVE_PACKAGES:-}" ]] || { echo "the variable must not outlive the script"; return 1; }
  cleanup_test_env
}

# `teeup uninstall` keeps packages unless asked: the remove script still runs
# (it owns machine state such as a LaunchAgent), nothing is uninstalled, and
# the capability is forgotten all the same.
test_cap_remove_without_packages_keeps_them_and_tells_the_script() {
  setup
  make_removable
  local out rc=0
  out="$(cap_remove alpha false 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "remove:alpha packages=false" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "uninstall" "packages were kept" || return 1
  state_done check cap-alpha && { echo "the marker must be cleared"; return 1; }
  cleanup_test_env
}

# The metadata keys are read by cap_meta_get in a subshell that can see the
# caller's locals, so a local named after a key would answer for a
# capability that does not set it. beta sets no packages= at all.
test_cap_remove_reads_packages_from_the_metadata_only() {
  setup
  mock_command brew 0 ""
  state_done mark cap-beta
  local rc=0
  cap_remove beta true >/dev/null 2>&1 || rc=$?
  assert_equals "2" "$rc" "beta has nothing to undo" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "uninstall" || return 1
  state_done check cap-beta || { echo "nothing was removed, so the marker stays"; return 1; }
  cleanup_test_env
}

test_cap_remove_reports_a_failed_script_and_a_failed_uninstall() {
  setup
  make_removable
  printf '#!/usr/bin/env bash\nexit 1\n' > "$TEEUP_CAPS_DIR/alpha/remove"
  local rc=0
  cap_remove alpha true >/dev/null 2>&1 || rc=$?
  assert_equals "3" "$rc" "a failed remove script" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "uninstall" "nothing is uninstalled after the script failed" || return 1
  state_done check cap-alpha || { echo "the marker stays"; return 1; }
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/alpha/remove"
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "uninstall --cask") exit 1 ;;
esac
exit 0
EOF2
  rc=0
  cap_remove alpha true >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "a failed uninstall" || return 1
  state_done check cap-alpha || { echo "the marker stays so a retry finds the cask"; return 1; }
  cleanup_test_env
}

echo "lib/capability.sh"
```

```bash edit-old=tests/lib/capability.sh
print_summary
```
```bash edit-new=tests/lib/capability.sh
run_test "cap_remove with packages runs the script then uninstalls" test_cap_remove_with_packages_runs_the_script_then_uninstalls
run_test "cap_remove without packages keeps them and tells the script" test_cap_remove_without_packages_keeps_them_and_tells_the_script
run_test "cap_remove reads packages from the metadata only" test_cap_remove_reads_packages_from_the_metadata_only
run_test "cap_remove reports a failed script and a failed uninstall" test_cap_remove_reports_a_failed_script_and_a_failed_uninstall
print_summary
```

The three scripts, each in its own suite. The MacPorts port is installed and active in the mock, so the only thing that can keep it is `TEEUP_REMOVE_PACKAGES`; each test also proves `teeup remove` (the variable unset) still uninstalls it.

```bash edit-old=tests/capabilities/emacs.sh
echo "capabilities/emacs"
```
```bash edit-new=tests/capabilities/emacs.sh
# `teeup uninstall` without --packages: the agent still goes, the port the
# MacPorts install put here stays.
test_remove_keeps_the_port_when_packages_are_kept() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command_script port <<'EOF2'
case "$1" in
  installed) echo "  $2 @1.0_0 (active)" ;;
esac
exit 0
EOF2
  source "$TEEUP_PATH/lib/all.sh"
  local out
  out="$(DRY_RUN=false TEEUP_REMOVE_PACKAGES=false cap_run emacs remove 2>&1)"
  assert_contains "$out" "Keeping the Emacs application; packages stay installed." || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "port uninstall" || return 1
  out="$(DRY_RUN=false cap_run emacs remove 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "sudo port uninstall emacs" "teeup remove still takes the port off" || return 1
  cleanup_test_env
}

echo "capabilities/emacs"
```

```bash edit-old=tests/capabilities/emacs.sh
run_test "configure points git at emacsclient" test_configure_points_git_at_emacsclient
```
```bash edit-new=tests/capabilities/emacs.sh
run_test "remove keeps the port when packages are kept" test_remove_keeps_the_port_when_packages_are_kept
run_test "configure points git at emacsclient" test_configure_points_git_at_emacsclient
```

```bash edit-old=tests/capabilities/wezterm.sh
echo "capabilities/wezterm"
```
```bash edit-new=tests/capabilities/wezterm.sh
# `teeup uninstall` without --packages keeps the port; `teeup remove` (no
# variable set) still uninstalls it.
test_remove_keeps_the_port_when_packages_are_kept() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command_script port <<'EOF2'
case "$1" in
  installed) echo "  $2 @1.0_0 (active)" ;;
esac
exit 0
EOF2
  source "$TEEUP_PATH/lib/all.sh"
  local out
  out="$(DRY_RUN=false TEEUP_REMOVE_PACKAGES=false cap_run wezterm remove 2>&1)"
  assert_contains "$out" "Keeping WezTerm; packages stay installed." || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "port uninstall" || return 1
  out="$(DRY_RUN=false cap_run wezterm remove 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "sudo port uninstall wezterm" "teeup remove still takes the port off" || return 1
  cleanup_test_env
}

echo "capabilities/wezterm"
```

```bash edit-old=tests/capabilities/wezterm.sh
print_summary
```
```bash edit-new=tests/capabilities/wezterm.sh
run_test "remove keeps the port when packages are kept" test_remove_keeps_the_port_when_packages_are_kept
print_summary
```

```bash edit-old=tests/capabilities/colima.sh
echo "capabilities/colima"
```
```bash edit-new=tests/capabilities/colima.sh
# With packages kept there is no formula coming off, so the VM keeps running
# and the Compose link the kept docker needs stays.
test_remove_leaves_the_vm_and_link_when_packages_are_kept() {
  setup
  mock_colima_stopped
  local plugin="$TEEUP_PKG_PREFIX/lib/docker/cli-plugins/docker-compose"
  mkdir -p "$(dirname "$plugin")"
  printf '#!/bin/sh\n' > "$plugin"
  chmod +x "$plugin"
  DRY_RUN=false "$TEEUP" configure colima >/dev/null
  local link="$TEST_HOME/.docker/cli-plugins/docker-compose"
  : > "$MOCK_LOG"
  source "$TEEUP_PATH/lib/all.sh"
  local out
  out="$(DRY_RUN=false TEEUP_REMOVE_PACKAGES=false cap_run colima remove 2>&1)"
  assert_contains "$out" "Keeping colima, docker and Compose installed" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "colima stop" || return 1
  [[ -L "$link" ]] || { echo "the compose link must stay"; return 1; }
  cleanup_test_env
}

echo "capabilities/colima"
```

```bash edit-old=tests/capabilities/colima.sh
print_summary
```
```bash edit-new=tests/capabilities/colima.sh
run_test "remove leaves the vm and link when packages are kept" test_remove_leaves_the_vm_and_link_when_packages_are_kept
print_summary
```

- [ ] **Step 2: Run them to see them fail**

Run: `bash tests/lib/capability.sh; bash tests/capabilities/emacs.sh; bash tests/capabilities/wezterm.sh; bash tests/capabilities/colima.sh`
Expected: the four `cap_remove` tests fail with `cap_remove: command not found`; the emacs and wezterm tests fail on `port uninstall` in the log; the colima test fails because the Compose link was removed.

- [ ] **Step 3: Add `cap_remove` to `lib/capability.sh`**

```bash edit-old=lib/capability.sh
  done
  return 0
}
```
```bash edit-new=lib/capability.sh
  done
  return 0
}

# cap_remove <name> <true|false>
# The removal half of `teeup remove`, shared with `teeup uninstall`. Runs the
# capability's remove script when it ships one, then -- only when the second
# argument is true -- uninstalls the casks and packages its metadata names,
# then forgets the capability. The caller has already checked that it is
# installed and that nothing installed still requires it.
#
# The second argument is also exported to the remove script as
# TEEUP_REMOVE_PACKAGES, because three scripts do package work of their own:
# emacs and wezterm uninstall the MacPorts port their install used in place
# of a cask, and colima stops its VM only because the formula is about to
# come off. With false, all three leave the software alone. A script that
# never reads the variable is unaffected, and `teeup remove` always passes
# true, so its behaviour is unchanged.
#
# Returns:
#   0  removed, and the done marker cleared
#   1  a cask or package would not uninstall; the marker is kept so a retry
#      can find what is left
#   2  nothing to undo: no remove script, and no packages or casks named.
#      Nothing was run and the marker is kept
#   3  the remove script failed; nothing was uninstalled and the marker is kept
# Leaves TEEUP_CAP_NA set to what the remove script answered ("false" when
# there was no script), for a caller that reports it.
cap_remove() {
  local target="$1" with_packages="$2" cask pkg failed=0 pkgs casks_meta has_remove=false
  pkgs="$(cap_meta_get "$target" packages)"
  casks_meta="$(cap_meta_get "$target" casks)"
  [[ -f "$(cap_dir "$target")/remove" ]] && has_remove=true
  TEEUP_CAP_NA=false
  if [[ "$has_remove" != "true" && -z "$pkgs" && -z "$casks_meta" ]]; then
    return 2
  fi
  if [[ "$has_remove" == "true" ]]; then
    export TEEUP_REMOVE_PACKAGES="$with_packages"
    if ! cap_run "$target" remove; then
      unset TEEUP_REMOVE_PACKAGES
      return 3
    fi
    unset TEEUP_REMOVE_PACKAGES
  fi
  if [[ "$with_packages" == "true" ]]; then
    for cask in $casks_meta; do
      cask_uninstall "$cask" || failed=1
    done
    for pkg in $pkgs; do
      pkg_uninstall "$pkg" || failed=1
    done
  fi
  if [[ $failed -ne 0 ]]; then
    return 1
  fi
  # `|| true`: state_done and state_na warn for themselves when a marker
  # will not clear, and the software is already off by here.
  state_done clear "cap-$target" || true
  state_na clear "cap-$target" || true
  return 0
}
```

- [ ] **Step 4: Make `cmd_remove` a caller of `cap_remove`**

The preflight (unknown, not applicable, not installed, required by something) stays in `cmd_remove`; the removal and its statuses move out. Every message is word for word what it was.

```bash edit-old=bin/teeup
# teeup remove <capability>
# The inverse of `teeup install`, read from metadata. A capability that ships
# a remove script owns the machine state it set up (a LaunchAgent, recorded
# `defaults`, a hidutil mapping, a mise wrapper); that script runs first,
# while its tool is still installed, and then the casks and packages its
# metadata names are uninstalled. Configuration files stay where they are:
# they are the user's, and re-installing the capability could not bring them
# back. A lazy capability keeps its shim, so typing its command offers to
# install it again. A capability with neither a remove script nor any
# packages or casks (xcode-clt, package-manager before a wrapper capability
# like ai grows one) has nothing teeup can undo, so it dies rather than
# claim a removal that never happened.
cmd_remove() {
  local target="${1:-}" dependents="" name cask pkg failed=0 tier
  local has_remove=false pkgs casks_meta
  [[ -n "$target" ]] || die "Usage: teeup remove <capability>"
  cap_exists "$target" || die "Unknown capability: $target"
  if state_na check "cap-$target"; then
    die "$target is not applicable on this machine."
  fi
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
  pkgs="$(cap_meta_get "$target" packages)"
  casks_meta="$(cap_meta_get "$target" casks)"
  [[ -f "$(cap_dir "$target")/remove" ]] && has_remove=true
  if [[ "$has_remove" != "true" && -z "$pkgs" && -z "$casks_meta" ]]; then
    die "$target ships no remove script and installs no packages or casks that teeup tracks, so teeup remove cannot undo it; $target is still marked installed."
  fi
  if [[ "$has_remove" == "true" ]]; then
    cap_run "$target" remove || die "$target's remove script failed; nothing was uninstalled."
    # cap_run turns the not-applicable exit into a success for every verb, so
    # a remove script that answered "this machine cannot have it" gets here
    # having undone nothing. Saying "Removed $target." after that would be a
    # claim about work that did not happen; the packages below are still
    # taken off, since metadata is the other half of a removal.
    if [[ "$TEEUP_CAP_NA" == "true" ]]; then
      warn "$target's remove script reported it is not applicable on this machine, so it undid nothing of its own."
    fi
  fi
  for cask in $casks_meta; do
    cask_uninstall "$cask" || failed=1
  done
  for pkg in $pkgs; do
    pkg_uninstall "$pkg" || failed=1
  done
  # Only clear the done marker once every cask and package is actually gone.
  # Clearing it after a failed uninstall would make a retry see the
  # capability as not installed, and the leftover software could then never
  # be removed: cmd_install would skip it ("Already installed") and
  # cmd_remove itself would refuse with "not installed here".
  if [[ $failed -eq 0 ]]; then
    # `|| true`: state_done warns for itself when the marker will not clear,
    # and the packages are already off by here -- aborting would leave the
    # user with no teeup message at all.
    state_done clear "cap-$target" || true
    # Defensive, and unreachable today: cmd_remove refuses a capability that
    # is marked not-applicable before it gets here, and a `remove` script that
    # answers not_applicable only trips cap_run's own temp sentinel -- the
    # state_na marker is written by cap_install_verbs, which removal does not
    # call. It stays so that a future path that can set the marker cannot
    # leave `teeup status` calling a removed capability "not applicable on
    # this machine" (R-7.3). Do not write a test for it: there is nothing it
    # could assert that would not be vacuous.
    state_na clear "cap-$target" || true
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
  ok_unless_dry "Removed $target."
}

```
```bash edit-new=bin/teeup
# teeup remove <capability>
# The inverse of `teeup install`, read from metadata. A capability that ships
# a remove script owns the machine state it set up (a LaunchAgent, recorded
# `defaults`, a hidutil mapping, a mise wrapper); that script runs first,
# while its tool is still installed, and then the casks and packages its
# metadata names are uninstalled. Configuration files stay where they are:
# they are the user's, and re-installing the capability could not bring them
# back. A lazy capability keeps its shim, so typing its command offers to
# install it again. A capability with neither a remove script nor any
# packages or casks (xcode-clt, package-manager before a wrapper capability
# like ai grows one) has nothing teeup can undo, so it dies rather than
# claim a removal that never happened. The removal itself is cap_remove
# (lib/capability.sh), which `teeup uninstall` shares.
cmd_remove() {
  local target="${1:-}" dependents="" name tier rc=0
  [[ -n "$target" ]] || die "Usage: teeup remove <capability>"
  cap_exists "$target" || die "Unknown capability: $target"
  if state_na check "cap-$target"; then
    die "$target is not applicable on this machine."
  fi
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
  cap_remove "$target" true || rc=$?
  case "$rc" in
    2) die "$target ships no remove script and installs no packages or casks that teeup tracks, so teeup remove cannot undo it; $target is still marked installed." ;;
    3) die "$target's remove script failed; nothing was uninstalled." ;;
  esac
  # cap_run turns the not-applicable exit into a success for every verb, so
  # a remove script that answered "this machine cannot have it" gets here
  # having undone nothing. Saying "Removed $target." after that would be a
  # claim about work that did not happen; the packages were still taken off,
  # since metadata is the other half of a removal.
  if [[ "$TEEUP_CAP_NA" == "true" ]]; then
    warn "$target's remove script reported it is not applicable on this machine, so it undid nothing of its own."
  fi
  # cap_remove clears the done marker only once every cask and package is
  # actually gone. Clearing it after a failed uninstall would make a retry
  # see the capability as not installed, and the leftover software could
  # then never be removed: cmd_install would skip it ("Already installed")
  # and cmd_remove itself would refuse with "not installed here".
  if [[ $rc -ne 0 ]]; then
    warn "Leaving $target marked installed since something above failed; fix it and run teeup remove $target again."
  fi
  if [[ -d "$(cap_dir "$target")/config" || -d "$(cap_dir "$target")/home" ]]; then
    log "Your configuration files for $target were left in place."
  fi
  tier="$(cap_meta_get "$target" tier)"
  if [[ "$tier" != "lazy" ]]; then
    log "$target is in the $tier tier, so the next ./bootstrap installs it again unless machines/<hostname>.conf sets TEEUP_SKIP."
  fi
  if [[ $rc -ne 0 ]]; then
    err "teeup remove $target finished, with the problems above."
    exit 1
  fi
  ok_unless_dry "Removed $target."
}

```

- [ ] **Step 5: Teach the three scripts `TEEUP_REMOVE_PACKAGES`**

```bash edit-old=capabilities/emacs/remove
# capability gone. Undo what install actually did on this backend.
if ! casks_supported; then
```
```bash edit-new=capabilities/emacs/remove
# capability gone. Undo what install actually did on this backend, unless
# the caller is keeping packages (`teeup uninstall` without --packages sets
# TEEUP_REMOVE_PACKAGES=false; lib/capability.sh's cap_remove).
if [[ "${TEEUP_REMOVE_PACKAGES:-true}" != "true" ]]; then
  log "Keeping the Emacs application; packages stay installed."
elif ! casks_supported; then
```

```bash edit-old=capabilities/wezterm/remove
# nothing to add.
if ! casks_supported; then
```
```bash edit-new=capabilities/wezterm/remove
# nothing to add. `teeup uninstall` without --packages keeps packages, and
# says so through TEEUP_REMOVE_PACKAGES=false (lib/capability.sh's
# cap_remove); the port is a package like any other then.
if [[ "${TEEUP_REMOVE_PACKAGES:-true}" != "true" ]]; then
  log "Keeping WezTerm; packages stay installed."
elif ! casks_supported; then
```

```bash edit-old=capabilities/colima/remove
if have colima; then
```
```bash edit-new=capabilities/colima/remove
#
# `teeup uninstall` without --packages keeps colima, docker and Compose
# installed (TEEUP_REMOVE_PACKAGES=false, from lib/capability.sh's
# cap_remove). Then there is no formula coming off to protect the VM from,
# and the Compose link is what makes the docker the user keeps work, so both
# stay exactly as they are.
if [[ "${TEEUP_REMOVE_PACKAGES:-true}" != "true" ]]; then
  log "Keeping colima, docker and Compose installed, so the VM and the docker compose link stay as they are."
  exit 0
fi
if have colima; then
```

- [ ] **Step 6: Run the suites for this task**

Run: `bash tests/lib/capability.sh && bash tests/capabilities/emacs.sh && bash tests/capabilities/wezterm.sh && bash tests/capabilities/colima.sh && bash tests/cli.sh`
Expected: `tests/lib/capability.sh` prints its count before this task plus 4, each capability suite its count plus 1, and `tests/cli.sh` its count unchanged -- the eight `remove` tests there pass untouched, which is the proof that `cmd_remove` says what it said before.

- [ ] **Step 7: Run the whole suite and every check CI runs**

Run: `./tests/run.sh`
Expected: `All N suites passed.`, where N is the count printed before this task (no new suite).

Run CI's own shellcheck command, exactly as `.github/workflows/ci.yml` spells it (not a hand-picked file list: a helper sourced by a test is only checked this way):

```bash
shellcheck --severity=warning bootstrap bin/teeup lib/*.sh \
  $(find capabilities -type f \( -name install -o -name configure \
    -o -name remove -o -name doctor -o -name theme-apply \
    -o -name font-apply \)) \
  capabilities/teeup-runtime/default/hooks/*.sample \
  $(find migrations -type f -name '*.sh' 2>/dev/null) \
  tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh tests/docs.sh \
  tests/lib/*.sh tests/capabilities/*.sh
```

Then: `./bin/teeup commands --check && git diff --check`
Expected: shellcheck, `commands --check` and `git diff --check` all silent, exit 0.

- [ ] **Step 8: Commit**

```bash
git add lib/capability.sh bin/teeup capabilities/emacs/remove capabilities/wezterm/remove capabilities/colima/remove tests/lib/capability.sh tests/capabilities/emacs.sh tests/capabilities/wezterm.sh tests/capabilities/colima.sh
git commit -m "Share teeup remove's removal as cap_remove, with packages optional"
```

No trailer of any kind.

---

### Task 2: `lib/uninstall.sh` -- the ledger, `uninstall_rm`, restore offers and the capability order

The foundation every later step writes through. Nothing here deletes anything a caller did not name, and nothing claims a removal that was not checked on disk.

**Files:**
- Create: `lib/uninstall.sh`, `tests/lib/uninstall.sh`
- Modify: `lib/all.sh`

**Interfaces:**
- Consumes: `migrate_resolve`, `migrate_path_is_safe` (`lib/migrate.sh`); `ui_confirm`; `run_cmd`, `ok_unless_dry`; `cap_list`, `cap_order`, `state_done check`.
- Produces: `uninstall_report_reset`, `uninstall_note`, `uninstall_clean`, `uninstall_summary` (Contract 4); `uninstall_ask <question>` (0 for yes, and always 1 unless `_UNINSTALL_ASK=true`); `uninstall_q <path>`; `uninstall_rm` (Contract 5); `uninstall_newest_backup <path>`; `uninstall_offer_restore` (Contract 6); `uninstall_caps` (installed capabilities, dependents first, one per line). The test file's `setup`, `make_cap` and `run_fix` are what Tasks 3 to 6 add their tests beside.

**Real-Mac risk:** `$TEST_HOME` under `/var/folders` resolves to `/private/var/folders`, which is what `migrate_path_is_safe` compares; the dry-run test compares against `HOME_P` for that reason, and only the macOS runners exercise the difference. `rm -rf` of a directory holding a file with the `uchg` flag fails on macOS and is reported as failed with the command -- untested, since the flag is macOS-only.

- [ ] **Step 1: Write the failing test file**

```bash file=tests/lib/uninstall.sh
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# Every test runs in the harness's throwaway HOME with a fixture capability
# tree, a machines directory of its own (TEEUP_MACHINES_DIR otherwise
# defaults to the checkout's machines/, which no test may write or read), and
# chezmoi hidden, so migrate_path_is_safe's chezmoi gate answers the same on
# every runner. HOME_P is $TEST_HOME's physical form: uninstall_rm resolves
# paths, and on macOS /var/folders is /private/var/folders.
setup() {
  setup_test_env
  mock_macos_base
  hide_host_commands chezmoi
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_CAPS_DIR" "$TEEUP_MACHINES_DIR"
  export TEEUP_NO_GUM=1
  source "$TEEUP_PATH/lib/all.sh"
  # shellcheck disable=SC2034
  DRY_RUN=false
  uninstall_report_reset
  _UNINSTALL_ASK=false
  _UNINSTALL_PACKAGES=false
  _UNINSTALL_IDENTITY=false
  _UNINSTALL_GONE=" "
  HOME_P="$(cd "$TEST_HOME" && pwd -P)"
}

# make_cap <name> <tier> [requires] [packages] [casks]
make_cap() {
  local name="$1" tier="$2" requires="${3:-}" pkgs="${4:-}" casks="${5:-}"
  local dir="$TEEUP_CAPS_DIR/$name"
  mkdir -p "$dir"
  printf 'summary="Fixture %s"\ngroup=system\ntier=%s\nrequires="%s"\nprovides=""\npackages="%s"\ncasks="%s"\ninteractive=false\n' \
    "$name" "$tier" "$requires" "$pkgs" "$casks" > "$dir/capability"
  printf '#!/usr/bin/env bash\necho "install:%s"\n' "$name" > "$dir/install"
  printf '#!/usr/bin/env bash\necho "configure:%s"\n' "$name" > "$dir/configure"
  chmod +x "$dir/install" "$dir/configure"
}

# run_fix <command>: what the user would do with a printed fix, in their
# shell: zsh when the machine has it (every CI runner does), else bash.
run_fix() {
  if have zsh; then zsh -c "$1"; else bash -c "$1"; fi
}

test_rm_removes_a_file_a_directory_and_a_link_without_following_it() {
  setup
  mkdir -p "$TEST_HOME/d/sub" "$TEST_HOME/keep"
  printf 'x\n' > "$TEST_HOME/f"
  printf 'x\n' > "$TEST_HOME/d/sub/g"
  printf 'precious\n' > "$TEST_HOME/keep/target"
  ln -s "$TEST_HOME/keep/target" "$TEST_HOME/link"
  uninstall_rm "$TEST_HOME/f" "a file" >/dev/null || return 1
  uninstall_rm "$TEST_HOME/d" "a directory" >/dev/null || return 1
  uninstall_rm "$TEST_HOME/link" "a link" >/dev/null || return 1
  [[ ! -e "$TEST_HOME/f" && ! -e "$TEST_HOME/d" && ! -L "$TEST_HOME/link" ]] || { echo "all three must be gone"; return 1; }
  assert_file_exists "$TEST_HOME/keep/target" "a link is removed, never what it points to" || return 1
  assert_contains "$_UNINSTALL_REMOVED" "a directory" || return 1
  uninstall_rm "$TEST_HOME/nothing-here" "absent" || { echo "nothing there is not a problem"; return 1; }
  uninstall_clean || { echo "nothing was refused"; return 1; }
  cleanup_test_env
}

# A path outside $HOME and one inside a git checkout are refused, and the
# command the note prints really does remove them.
test_rm_refuses_outside_home_and_in_a_git_checkout_with_a_fix_that_works() {
  setup
  local outside="$TEST_HOME/outside dir \$x" repo="$TEST_HOME/home/repo" fix
  mkdir -p "$outside" "$repo/.git" "$TEST_HOME/home"
  printf 'x\n' > "$repo/tracked"
  export HOME="$TEST_HOME/home"
  uninstall_rm "$outside" "outside" >/dev/null 2>&1 && { echo "outside HOME must be refused"; return 1; }
  uninstall_rm "$repo/tracked" "in a repo" >/dev/null 2>&1 && { echo "a git checkout must be refused"; return 1; }
  [[ -d "$outside" && -f "$repo/tracked" ]] || { echo "nothing may be deleted"; return 1; }
  assert_contains "$_UNINSTALL_REFUSED" "outside" || return 1
  while IFS= read -r fix; do
    [[ -n "$fix" ]] || continue
    run_fix "${fix##*: }" || { echo "the printed fix failed: $fix"; return 1; }
  done <<EOF2
$_UNINSTALL_REFUSED
EOF2
  [[ ! -e "$outside" && ! -e "$repo/tracked" ]] || { echo "the printed fixes must remove both"; return 1; }
  cleanup_test_env
}

test_rm_dry_run_deletes_nothing_and_claims_nothing() {
  setup
  printf 'x\n' > "$TEST_HOME/f"
  local out
  out="$(DRY_RUN=true uninstall_rm "$TEST_HOME/f" "a file" 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: rm -f $HOME_P/f" || return 1
  assert_not_contains "$out" "Removed" || return 1
  assert_file_exists "$TEST_HOME/f" || return 1
  DRY_RUN=true uninstall_rm "$TEST_HOME/f" "a file" >/dev/null
  out="$(DRY_RUN=true uninstall_summary)"
  assert_contains "$out" "Would remove (dry run; nothing was changed):" || return 1
  cleanup_test_env
}

test_summary_lists_each_column_and_fails_on_a_problem() {
  setup
  local out rc=0
  out="$(uninstall_summary)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "Nothing of teeup's was left to remove." || return 1
  uninstall_note removed "gone thing"
  uninstall_note kept "kept thing"
  out="$(uninstall_summary)" || rc=$?
  assert_success "$rc" "kept is not a problem" || return 1
  assert_contains "$out" "  - kept thing" || return 1
  uninstall_note refused "refused thing"
  rc=0
  out="$(uninstall_summary)" || rc=$?
  assert_failure "$rc" "a refusal makes the run fail" || return 1
  assert_contains "$out" "  - refused thing" || return 1
  cleanup_test_env
}

test_caps_lists_installed_capabilities_dependents_first() {
  setup
  make_cap base core
  make_cap mid core base
  make_cap top lazy mid
  make_cap never lazy
  state_done mark cap-base
  state_done mark cap-mid
  state_done mark cap-top
  assert_equals "top mid base" "$(uninstall_caps | tr '\n' ' ' | sed 's/ $//')" || return 1
  cleanup_test_env
}

test_offer_restore_asks_and_puts_the_earlier_copy_back() {
  setup
  printf 'teeup\n' > "$TEST_HOME/conf"
  printf 'mine\n' > "$TEST_HOME/conf.teeup_backup_20260101000000"
  _UNINSTALL_ASK=true
  uninstall_offer_restore "$TEST_HOME/conf" >/dev/null 2>&1 <<< "y" || { echo "a yes restores"; return 1; }
  assert_equals "mine" "$(cat "$TEST_HOME/conf")" || return 1
  [[ ! -e "$TEST_HOME/conf.teeup_backup_20260101000000" ]] || { echo "the backup was moved, not copied"; return 1; }
  cleanup_test_env
}

# Without a terminal nothing is asked; the note carries the mv that puts the
# backup back, and that command works.
test_offer_restore_without_a_terminal_notes_a_command_that_works() {
  setup
  local dir="$TEST_HOME/it's a \$dir" fix
  mkdir -p "$dir"
  printf 'teeup\n' > "$dir/conf"
  printf 'mine\n' > "$dir/conf.teeup_backup_20260101000000"
  uninstall_offer_restore "$dir/conf" >/dev/null 2>&1 && { echo "nothing was restored"; return 1; }
  assert_equals "teeup" "$(cat "$dir/conf")" || return 1
  fix="${_UNINSTALL_KEPT##*: }"
  rm -f "$dir/conf"
  run_fix "$fix" || { echo "the printed mv failed: $fix"; return 1; }
  assert_equals "mine" "$(cat "$dir/conf")" || return 1
  cleanup_test_env
}

echo "lib/uninstall.sh"
run_test "rm removes a file, a directory and a link without following it" test_rm_removes_a_file_a_directory_and_a_link_without_following_it
run_test "rm refuses outside HOME and in a git checkout, with a fix that works" test_rm_refuses_outside_home_and_in_a_git_checkout_with_a_fix_that_works
run_test "rm dry run deletes nothing and claims nothing" test_rm_dry_run_deletes_nothing_and_claims_nothing
run_test "summary lists each column and fails on a problem" test_summary_lists_each_column_and_fails_on_a_problem
run_test "caps lists installed capabilities dependents first" test_caps_lists_installed_capabilities_dependents_first
run_test "offer_restore asks and puts the earlier copy back" test_offer_restore_asks_and_puts_the_earlier_copy_back
run_test "offer_restore without a terminal notes a command that works" test_offer_restore_without_a_terminal_notes_a_command_that_works
print_summary
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/lib/uninstall.sh`
Expected: every test fails with `uninstall_rm: command not found` or the like -- `lib/uninstall.sh` does not exist and nothing sources it.

- [ ] **Step 3: Write `lib/uninstall.sh`**

```bash file=lib/uninstall.sh
#!/usr/bin/env bash
# uninstall.sh - `teeup uninstall`: take teeup off this Mac.
#
# The run is a fixed sequence of steps (bin/teeup's cmd_uninstall calls them
# in order) and every step reports into one ledger with four columns:
# removed, kept, refused and failed. "Kept" is a policy outcome -- the
# user's edited files, their identity, the package manager, the packages
# unless asked -- and is not a problem. "Refused" is teeup declining to touch
# something it would otherwise have removed (a symlink into a dotfiles repo,
# a path inside a git checkout or outside $HOME), and "failed" is a removal
# that did not happen. Either of the last two makes the verb exit non-zero
# and keeps teeup's own state, config and command in place, so the printed
# rerun command can finish the job once the cause is fixed.
#
# Every deletion goes through uninstall_rm, which reuses lib/migrate.sh's
# safety gates: never outside $HOME, never inside a git checkout, never the
# chezmoi source directory, and a symlink is removed as a link, never
# followed. Every success line is ok_unless_dry after a checked mutation, and
# a line in the "removed" column is only written after the removal was
# verified (or, in a dry run, under a "Would remove" heading).
#
# Requires core.sh, files.sh, state.sh, answers.sh, pkg.sh, ui.sh,
# capability.sh, macos.sh, lazy.sh, hooks.sh and migrate.sh.

# --- the ledger ---------------------------------------------------------------

uninstall_report_reset() {
  _UNINSTALL_REMOVED=""
  _UNINSTALL_KEPT=""
  _UNINSTALL_REFUSED=""
  _UNINSTALL_FAILED=""
}
uninstall_report_reset

# uninstall_note <removed|kept|refused|failed> <text>
uninstall_note() {
  local line="$2"$'\n'
  case "$1" in
    removed) _UNINSTALL_REMOVED="$_UNINSTALL_REMOVED$line" ;;
    kept) _UNINSTALL_KEPT="$_UNINSTALL_KEPT$line" ;;
    refused) _UNINSTALL_REFUSED="$_UNINSTALL_REFUSED$line" ;;
    failed) _UNINSTALL_FAILED="$_UNINSTALL_FAILED$line" ;;
    *) die "uninstall_note: unknown column '$1'" ;;
  esac
}

# uninstall_clean -> 0 when nothing so far was refused or failed.
uninstall_clean() {
  [[ -z "$_UNINSTALL_REFUSED" && -z "$_UNINSTALL_FAILED" ]]
}

_uninstall_section() {
  local title="$1" body="$2" line
  [[ -n "$body" ]] || return 0
  printf '%s\n' "$title"
  while IFS= read -r line; do
    if [[ -n "$line" ]]; then printf '  - %s\n' "$line"; fi
  done <<EOF
$body
EOF
  return 0
}

# uninstall_summary -> prints the ledger; 0 when clean, 1 otherwise.
uninstall_summary() {
  local removed_title="Removed:"
  if [[ "$DRY_RUN" == "true" ]]; then removed_title="Would remove (dry run; nothing was changed):"; fi
  echo ""
  echo "teeup uninstall summary"
  if [[ -z "$_UNINSTALL_REMOVED$_UNINSTALL_KEPT$_UNINSTALL_REFUSED$_UNINSTALL_FAILED" ]]; then
    echo "  Nothing of teeup's was left to remove."
  fi
  _uninstall_section "$removed_title" "$_UNINSTALL_REMOVED"
  _uninstall_section "Kept:" "$_UNINSTALL_KEPT"
  _uninstall_section "Refused (teeup would not touch these; each line says what to do):" "$_UNINSTALL_REFUSED"
  _uninstall_section "Failed:" "$_UNINSTALL_FAILED"
  uninstall_clean
}

# --- asking -------------------------------------------------------------------

# _UNINSTALL_ASK is "true" only on a real run with a terminal and no --yes;
# cmd_uninstall sets it. Everything else takes the default, which is always
# the answer that removes less.
_UNINSTALL_ASK="${_UNINSTALL_ASK:-false}"

# uninstall_ask <question> -> 0 for yes. Defaults to no.
uninstall_ask() {
  [[ "$_UNINSTALL_ASK" == "true" ]] || return 1
  ui_confirm "$1" no
}

# uninstall_q <path> -> <path> quoted for a command line the user can paste
# into bash or zsh (both read bash's %q forms).
uninstall_q() { printf '%q' "$1"; }

# --- deleting -----------------------------------------------------------------

# uninstall_rm <path> [label]
# The one deletion in `teeup uninstall`. A path that is not there is nothing
# to do. Anything else is resolved (lib/migrate.sh's migrate_resolve, which
# leaves the last component alone so a symlink is removed as a link and never
# followed) and must pass migrate_path_is_safe -- strictly inside the
# physical $HOME, not inside any git checkout, not the chezmoi source -- or
# it is refused with the command that removes it by hand. A directory gets
# rm -rf, anything else rm -f, and the result is checked on disk before it
# is called removed. Notes its own outcome in the ledger.
# 0 removed or nothing there; 1 refused or failed. A caller that does not
# branch on the status writes `|| true`: the outcome is already in the
# ledger, and bin/teeup runs under `set -e`, where a bare call that returned 1
# would end the whole uninstall before its summary.
uninstall_rm() {
  local path="$1" label="${2:-$1}" resolved flag="-f"
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    return 0
  fi
  if [[ -d "$path" && ! -L "$path" ]]; then flag="-rf"; fi
  if ! resolved="$(migrate_resolve "$path")" || ! migrate_path_is_safe "$resolved"; then
    uninstall_note refused "$label: $path is outside your home directory, inside a git checkout or inside the chezmoi source, so teeup did not delete it. Remove it yourself if you mean to: rm $flag $(uninstall_q "$path")"
    return 1
  fi
  if ! run_cmd rm "$flag" "$resolved" 2>/dev/null; then
    uninstall_note failed "$label: could not delete $path. Remove it with: rm $flag $(uninstall_q "$path")"
    return 1
  fi
  if [[ "$DRY_RUN" != "true" ]] && [[ -e "$resolved" || -L "$resolved" ]]; then
    uninstall_note failed "$label: $path is still there after rm. Remove it with: rm $flag $(uninstall_q "$path")"
    return 1
  fi
  ok_unless_dry "Removed $path"
  uninstall_note removed "$label"
  return 0
}

# uninstall_newest_backup <path> -> the newest <path>.teeup_backup_* beside
# it, or nothing. backup names carry a sortable timestamp (lib/files.sh's
# _backup_name), and a glob expands sorted, so the last match is the newest.
uninstall_newest_backup() {
  local f newest=""
  for f in "$1".teeup_backup_*; do
    [[ -e "$f" || -L "$f" ]] || continue
    newest="$f"
  done
  [[ -n "$newest" ]] || return 1
  printf '%s\n' "$newest"
}

# uninstall_offer_restore <path> -> 0 when an earlier copy was put back.
# A pristine teeup file that is about to go may have replaced one of the
# user's own at install time; copy_config_once kept that as
# <path>.teeup_backup_<ts>. On a terminal the user is asked (default no);
# otherwise, and after a no, the command that puts it back is noted instead.
# The mv is checked, and a failed one leaves the teeup file for the caller.
uninstall_offer_restore() {
  local path="$1" backup
  backup="$(uninstall_newest_backup "$path")" || return 1
  if uninstall_ask "Put back your earlier $path from $backup?"; then
    if run_cmd mv "$backup" "$path" 2>/dev/null && [[ -e "$path" || -L "$path" ]]; then
      ok_unless_dry "Put back $path from $backup"
      uninstall_note removed "teeup's $path (your earlier copy is back in its place)"
      return 0
    fi
    uninstall_note failed "$path: could not put $backup back. Do it with: mv $(uninstall_q "$backup") $(uninstall_q "$path")"
    return 1
  fi
  uninstall_note kept "$backup, your copy from before teeup. Put it back with: mv $(uninstall_q "$backup") $(uninstall_q "$path")"
  return 1
}

# --- what is installed --------------------------------------------------------

# uninstall_caps -> every installed capability, dependents before what they
# require (the reverse of cap_order), one per line. TEEUP_SKIP is ignored on
# purpose: a capability the machine file now skips may still have been
# installed before, and it is teeup's all the same.
uninstall_caps() {
  local name installed="" ordered reversed=""
  for name in $(cap_list); do
    if state_done check "cap-$name"; then installed="$installed $name"; fi
  done
  [[ -n "$installed" ]] || return 0
  # shellcheck disable=SC2086  # a word list of capability names
  ordered="$(cap_order $installed)" || return 1
  for name in $ordered; do
    case " $installed " in
      *" $name "*) reversed="$name $reversed" ;;
    esac
  done
  for name in $reversed; do
    printf '%s\n' "$name"
  done
}
```

- [ ] **Step 4: Source it**

Append ` uninstall` to the end of the list in `lib/all.sh`. The libraries define functions and run nothing that depends on another at source time (`lib/uninstall.sh` only calls its own `uninstall_report_reset`), so the position only has to be after `migrate`. On `main` at `31a4644` the line reads as below; after phase 4b it ends `... doctor migrate menu dev; do`, and the change is the same: ` uninstall` goes after `dev`.

```bash edit-old=lib/all.sh
for _teeup_lib in files state answers pkg ui capability macos theme font lazy mise hooks migrations doctor migrate; do
```
```bash edit-new=lib/all.sh
for _teeup_lib in files state answers pkg ui capability macos theme font lazy mise hooks migrations doctor migrate uninstall; do
```

- [ ] **Step 5: Run the new suite**

Run: `bash tests/lib/uninstall.sh`
Expected: `Summary: 7/7 passed`.

- [ ] **Step 6: Run the whole suite and every check CI runs**

Run: `./tests/run.sh`
Expected: `All N suites passed.`, where N is the count printed before this task plus 1 (`tests/lib/uninstall.sh` is new).

Run CI's own shellcheck command, exactly as `.github/workflows/ci.yml` spells it (not a hand-picked file list: a helper sourced by a test is only checked this way):

```bash
shellcheck --severity=warning bootstrap bin/teeup lib/*.sh \
  $(find capabilities -type f \( -name install -o -name configure \
    -o -name remove -o -name doctor -o -name theme-apply \
    -o -name font-apply \)) \
  capabilities/teeup-runtime/default/hooks/*.sample \
  $(find migrations -type f -name '*.sh' 2>/dev/null) \
  tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh tests/docs.sh \
  tests/lib/*.sh tests/capabilities/*.sh
```

Then: `./bin/teeup commands --check && git diff --check`
Expected: shellcheck, `commands --check` and `git diff --check` all silent, exit 0.

- [ ] **Step 7: Commit**

```bash
git add lib/uninstall.sh lib/all.sh tests/lib/uninstall.sh
git commit -m "Add the uninstall ledger and its one checked deletion"
```

No trailer of any kind.

---

### Task 3: The shell layer comes off first

`uninstall_shell` is the first mutation of every uninstall (Decision 1). It handles `${ZDOTDIR:-$HOME}/.zshenv`, `.zprofile` and `.zshrc`, in the order zsh reads them, by Decisions 2 and 3, and when it changed anything it adds the package manager's PATH line to the summary (Decision 4). `ere_quote` goes into `lib/files.sh` next to `disable_matching_lines`, whose pattern is an ERE.

**Files:**
- Modify: `lib/files.sh` (append `ere_quote`), `lib/uninstall.sh` (append the shell section)
- Test: `tests/lib/files.sh`, `tests/lib/uninstall.sh`

**Interfaces:**
- Consumes: `disable_matching_lines`, `block_opener_ere`, `config_is_pristine`, `write_managed_file` (`lib/files.sh`); `migrate_resolve`, `migrate_in_git_checkout`; `pkg_backend`, `pkg_prefix`, `pkg_backend_label`; Task 2's `uninstall_rm`, `uninstall_offer_restore`, `uninstall_newest_backup`, `uninstall_note`, `uninstall_q`.
- Produces: `ere_quote <text>` (Contract 3); `uninstall_shell_pattern`; `uninstall_shell_live <file>` (0 when a live teeup line remains); `uninstall_shell`; `uninstall_path_hint`. Task 6's `cmd_uninstall` calls `uninstall_shell` first.

**Real-Mac risk:** BSD awk on macOS reads the backslash escapes `ere_quote` produces from a dynamic regex passed through `ENVIRON`; POSIX defines them and gawk honours them, but only the macOS runners prove BSD awk does (phase 5a named the same risk for `\.`). Run the two suites under a real bash 3.2 before merging (Global Constraints). Apple's zsh 5.9 at `/bin/zsh` is what `zsh -f -n` runs on a Mac; the Linux runner installs Debian's.

- [ ] **Step 1: Write the failing tests**

`ere_quote` in `tests/lib/files.sh`:

```bash edit-old=tests/lib/files.sh
echo "lib/files.sh"
```
```bash edit-new=tests/lib/files.sh
# ere_quote: the quoted text matches itself, through awk's ENVIRON the way
# disable_matching_lines passes a pattern, and a near miss does not match --
# every ERE metacharacter, a %q-escaped space and a dollar included.
test_ere_quote_matches_only_the_literal_text() {
  setup
  local text q
  for text in '/Users/a b/.config/teeup/env' '${XDG_CONFIG_HOME:-$HOME/.config}/teeup/env' \
    '/x/con\ fig\ \$x/env' 'a.b*c+d?e(f)g[h]i{j}k|l^m\n'; do
    q="$(ere_quote "$text")"
    printf '%s\n' "pre $text post" | TEEUP_T="$q" awk '$0 ~ ENVIRON["TEEUP_T"] { found = 1 } END { exit found ? 0 : 1 }' ||
      { echo "does not match itself: $text (as $q)"; return 1; }
    printf '%s\n' "pre ${text%?}Z post" | TEEUP_T="$q" awk '$0 ~ ENVIRON["TEEUP_T"] { found = 1 } END { exit found ? 0 : 1 }' &&
      { echo "matches a near miss: $text (as $q)"; return 1; }
  done
  printf 'axb\n' | TEEUP_T="$(ere_quote 'a.b')" awk '$0 ~ ENVIRON["TEEUP_T"] { found = 1 } END { exit found ? 0 : 1 }' &&
    { echo "a quoted dot matched any character"; return 1; }
  cleanup_test_env
}

echo "lib/files.sh"
```

```bash edit-old=tests/lib/files.sh
print_summary
```
```bash edit-new=tests/lib/files.sh
run_test "ere_quote matches only the literal text" test_ere_quote_matches_only_the_literal_text
print_summary
```

The shell step in `tests/lib/uninstall.sh`. `zsh_home` runs the checkout's real `zsh` capability `configure` (it reads the checkout and writes only under `$TEST_HOME`), so the files are exactly what a Mac has, rendered env line and stock records included:

```bash edit-old=tests/lib/uninstall.sh
echo "lib/uninstall.sh"
```
```bash edit-new=tests/lib/uninstall.sh
# zsh_home: the three home files exactly as `teeup configure zsh` leaves them,
# rendered and stock-recorded, from the real capability in the checkout.
# The checkout is only read; everything written lands under $TEST_HOME.
zsh_home() {
  TEEUP_CAPS_DIR="$TEEUP_PATH/capabilities" cap_run zsh configure >/dev/null 2>&1
  ZH="${ZDOTDIR:-$HOME}"
}

test_shell_strips_teeups_lines_from_an_edited_zshrc_and_keeps_the_users() {
  setup
  export TEEUP_CONFIG_DIR="$TEST_HOME/con fig \$x"
  zsh_home
  printf 'export MINE=1\n' >> "$ZH/.zshrc"
  uninstall_shell >/dev/null 2>&1
  assert_contains "$(cat "$ZH/.zshrc")" "export MINE=1" || return 1
  assert_contains "$(cat "$ZH/.zshrc")" ": # Disabled by teeup (teeup uninstall):" || return 1
  uninstall_shell_live "$ZH/.zshrc" && { echo "a live teeup line is left"; return 1; }
  if have zsh; then zsh -f -n "$ZH/.zshrc" || { echo "zsh cannot parse the result"; return 1; }; fi
  [[ -n "$(uninstall_newest_backup "$ZH/.zshrc")" ]] || { echo "a copy of the file as it was must be beside it"; return 1; }
  uninstall_clean || { echo "nothing was refused: $_UNINSTALL_REFUSED$_UNINSTALL_FAILED"; return 1; }
  cleanup_test_env
}

# Pristine: .zshenv and .zprofile go; .zshrc is replaced, never removed, and
# the replacement sources an edited local.zsh so the user's own lines load.
test_shell_replaces_a_pristine_zshrc_and_removes_the_other_two() {
  setup
  zsh_home
  printf 'export LOCAL=1\n' >> "$(user_config_dir)/zsh/local.zsh"
  uninstall_shell >/dev/null 2>&1
  [[ ! -e "$ZH/.zshenv" && ! -e "$ZH/.zprofile" ]] || { echo "pristine .zshenv and .zprofile go"; return 1; }
  assert_file_exists "$ZH/.zshrc" "a .zshrc must always be left" || return 1
  uninstall_shell_live "$ZH/.zshrc" && { echo "the new .zshrc has a teeup line"; return 1; }
  assert_contains "$(cat "$ZH/.zshrc")" "zsh/local.zsh" || return 1
  if have zsh; then
    assert_equals "1" "$(zsh -f -c ". $(printf '%q' "$ZH/.zshrc"); echo \$LOCAL")" "the new .zshrc loads local.zsh" || return 1
  fi
  cleanup_test_env
}

test_shell_refuses_a_symlinked_zshrc_and_writes_nothing() {
  setup
  zsh_home
  mkdir -p "$TEST_HOME/dotfiles/.git"
  cp "$ZH/.zshrc" "$TEST_HOME/dotfiles/zshrc"
  rm -f "$ZH/.zshrc"
  ln -s "$TEST_HOME/dotfiles/zshrc" "$ZH/.zshrc"
  local before
  before="$(cat "$TEST_HOME/dotfiles/zshrc")"
  uninstall_shell >/dev/null 2>&1
  [[ -L "$ZH/.zshrc" ]] || { echo "the link must stay a link"; return 1; }
  assert_equals "$before" "$(cat "$TEST_HOME/dotfiles/zshrc")" "nothing is written through the link" || return 1
  assert_contains "$_UNINSTALL_REFUSED" "$ZH/.zshrc is a symlink" || return 1
  cleanup_test_env
}

test_shell_honours_zdotdir_and_refuses_one_inside_a_git_checkout() {
  setup
  export ZDOTDIR="$TEST_HOME/.config/zsh"
  zsh_home
  printf 'export MINE=1\n' >> "$ZDOTDIR/.zshrc"
  uninstall_shell >/dev/null 2>&1
  uninstall_shell_live "$ZDOTDIR/.zshrc" && { echo "ZDOTDIR's .zshrc was not handled"; return 1; }
  cleanup_test_env
  setup
  export ZDOTDIR="$TEST_HOME/dots/zsh"
  mkdir -p "$TEST_HOME/dots/.git"
  zsh_home
  printf 'export MINE=1\n' >> "$ZDOTDIR/.zshrc"
  uninstall_shell >/dev/null 2>&1
  uninstall_shell_live "$ZDOTDIR/.zshrc" || { echo "a file in a git checkout must not be edited"; return 1; }
  assert_contains "$_UNINSTALL_REFUSED" "is inside a git checkout" || return 1
  cleanup_test_env
}

test_shell_dry_run_changes_nothing() {
  setup
  zsh_home
  printf 'export MINE=1\n' >> "$ZH/.zshrc"
  local before after out
  before="$(ls -l "$ZH/.zshenv" "$ZH/.zprofile" "$ZH/.zshrc"; ls -A "$ZH"; cat "$ZH/.zshrc")"
  out="$(DRY_RUN=true uninstall_shell 2>&1)"
  after="$(ls -l "$ZH/.zshenv" "$ZH/.zprofile" "$ZH/.zshrc"; ls -A "$ZH"; cat "$ZH/.zshrc")"
  assert_equals "$before" "$after" || return 1
  assert_contains "$out" "[DRY-RUN]" || return 1
  cleanup_test_env
}

# The package manager stays, but the shell layer that put it on PATH goes.
# The printed command must put it back, into the .zprofile zsh reads.
test_path_hint_prints_a_command_that_works() {
  setup
  export ZDOTDIR="$TEST_HOME/z dot"
  mkdir -p "$ZDOTDIR" "$TEEUP_PKG_PREFIX/bin"
  printf '#!/bin/sh\n' > "$TEEUP_PKG_PREFIX/bin/brew"
  chmod +x "$TEEUP_PKG_PREFIX/bin/brew"
  export TEEUP_PACKAGE_MANAGER=homebrew
  uninstall_path_hint
  run_fix "${_UNINSTALL_KEPT##*run: }" || { echo "the printed command failed"; return 1; }
  assert_contains "$(cat "$ZDOTDIR/.zprofile")" "eval \"\$($TEEUP_PKG_PREFIX/bin/brew shellenv)\"" || return 1
  uninstall_report_reset
  uninstall_path_hint
  assert_equals "" "$_UNINSTALL_KEPT" "no hint once the line is there" || return 1
  cleanup_test_env
}

echo "lib/uninstall.sh"
```

```bash edit-old=tests/lib/uninstall.sh
print_summary
```
```bash edit-new=tests/lib/uninstall.sh
run_test "shell strips teeup's lines from an edited zshrc and keeps the user's" test_shell_strips_teeups_lines_from_an_edited_zshrc_and_keeps_the_users
run_test "shell replaces a pristine zshrc and removes the other two" test_shell_replaces_a_pristine_zshrc_and_removes_the_other_two
run_test "shell refuses a symlinked zshrc and writes nothing" test_shell_refuses_a_symlinked_zshrc_and_writes_nothing
run_test "shell honours ZDOTDIR and refuses one inside a git checkout" test_shell_honours_zdotdir_and_refuses_one_inside_a_git_checkout
run_test "shell dry run changes nothing" test_shell_dry_run_changes_nothing
run_test "path hint prints a command that works" test_path_hint_prints_a_command_that_works
print_summary
```

- [ ] **Step 2: Run them to see them fail**

Run: `bash tests/lib/files.sh; bash tests/lib/uninstall.sh`
Expected: `ere_quote: command not found`, and the six new uninstall tests fail on `uninstall_shell: command not found`.

- [ ] **Step 3: Add `ere_quote` to `lib/files.sh`**

```bash edit-old=lib/files.sh
  ok "Disabled $reason lines in $file"
}
```
```bash edit-new=lib/files.sh
  ok "Disabled $reason lines in $file"
}

# ere_quote <text> -> <text> as an extended regular expression that matches
# exactly that text. Each ERE metacharacter ( \ ^ $ . [ ( ) * + ? { } | ) gets
# a backslash; everything else, spaces and slashes and non-ASCII bytes
# included, stands for itself. POSIX defines a backslash before any of those
# characters as that literal character, which BSD awk, gawk and grep -E all
# honour. For disable_matching_lines, whose pattern is an ERE, when the thing
# to match is a path that may hold any of them -- a %q-quoted
# TEEUP_CONFIG_DIR carries backslashes and dollars.
ere_quote() {
  local text="$1" out="" c i
  for ((i = 0; i < ${#text}; i++)); do
    c="${text:i:1}"
    case "$c" in
      '\' | '^' | '$' | '.' | '[' | '(' | ')' | '*' | '+' | '?' | '{' | '}' | '|') out="$out\\$c" ;;
      *) out="$out$c" ;;
    esac
  done
  printf '%s\n' "$out"
}
```

- [ ] **Step 4: Append the shell section to `lib/uninstall.sh`**

```bash edit-old=lib/uninstall.sh
  done
}
```
```bash edit-new=lib/uninstall.sh
  done
}

# --- the shell layer ----------------------------------------------------------

# uninstall_shell_pattern -> the ERE for a line of teeup's in a zsh home file.
# Three things mark one: the env file line as capabilities/zsh/configure
# renders it (the %q-quoted path of $TEEUP_CONFIG_DIR/env), the same line
# unrendered (a file installed before rendering existed), and TEEUP_PATH,
# which every line that sources the default layer names. A user line that
# names TEEUP_PATH is dead after the uninstall anyway: nothing sets it.
uninstall_shell_pattern() {
  printf '%s|%s|TEEUP_PATH\n' \
    "$(ere_quote "$(printf '%q' "$TEEUP_CONFIG_DIR/env")")" \
    "$(ere_quote '${XDG_CONFIG_HOME:-$HOME/.config}/teeup/env')"
}

# uninstall_shell_live <file> -> 0 when <file> still has a live teeup line:
# one matching uninstall_shell_pattern that is not a comment, not already
# neutralised (": # Disabled by teeup ..."), and not a block opener, which
# disable_matching_lines leaves in place on purpose and which does nothing
# once its body is disabled and TEEUP_PATH is unset.
uninstall_shell_live() {
  TEEUP_UNS_PATTERN="$(uninstall_shell_pattern)" TEEUP_UNS_OPENER="$(block_opener_ere)" awk '
    $0 ~ ENVIRON["TEEUP_UNS_PATTERN"] && $0 !~ /^[ \t]*[:#]/ && $0 !~ ENVIRON["TEEUP_UNS_OPENER"] { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$1" 2>/dev/null
}

# _uninstall_zshrc_stub -> the ~/.zshrc left in place of a pristine teeup
# copy. A shell must always find one: removing it outright is how the old
# migration nearly left a Mac with no working shell setup at all. It sources
# local.zsh only when that file stays (the user edited it), rendered the
# way capabilities/zsh/configure renders it.
_uninstall_zshrc_stub() {
  local local_zsh
  local_zsh="$(user_config_dir)/zsh/local.zsh"
  echo "# ~/.zshrc - left by teeup uninstall on $(date '+%Y-%m-%d'). teeup's shell"
  echo "# setup is gone; this file is yours, and is here so zsh always has one."
  if [[ -e "$local_zsh" ]] && ! config_is_pristine "$local_zsh"; then
    echo "[ -r $(printf '%q' "$local_zsh") ] && . $(printf '%q' "$local_zsh")"
  fi
}

# _uninstall_shell_file <path>
_uninstall_shell_file() {
  local file="$1" name resolved target backup parsed_before=false
  name="${file##*/}"
  [[ -e "$file" || -L "$file" ]] || return 0
  if [[ -L "$file" ]]; then
    target="$(readlink "$file" 2>/dev/null || true)"
    if [[ -f "$file" ]] && uninstall_shell_live "$file"; then
      uninstall_note refused "$file is a symlink (to $target), so teeup did not write through it. Delete the lines that mention TEEUP_PATH or teeup/env from the file it points to."
    fi
    return 0
  fi
  uninstall_shell_live "$file" || return 0
  resolved="$(migrate_resolve "$file")" || resolved="$file"
  if migrate_in_git_checkout "$resolved"; then
    uninstall_note refused "$file is inside a git checkout, so teeup did not edit it. Delete the lines that mention TEEUP_PATH or teeup/env yourself."
    return 0
  fi
  if config_is_pristine "$file"; then
    # teeup's own copy, never edited: it goes, and an earlier copy of the
    # user's comes back if they want it.
    if uninstall_offer_restore "$file"; then return 0; fi
    if [[ "$name" != ".zshrc" ]]; then
      uninstall_rm "$file" "teeup's $file" || true
      return 0
    fi
    if _uninstall_zshrc_stub | write_managed_file "$file" "a zshrc of your own"; then
      uninstall_note removed "teeup's $file (a short one of your own is in its place)"
    else
      uninstall_note failed "$file: could not replace teeup's copy; it still sources teeup's shell layer. Edit it by hand."
    fi
    return 0
  fi
  # Edited by the user: their lines stay, teeup's are neutralised in place
  # with a backup beside the file (disable_matching_lines). zsh itself is
  # asked whether the file still parses, when it did before. -f, because
  # without it zsh sources ~/.zshenv first -- teeup's shell layer, running
  # in the middle of its own removal.
  if have zsh && zsh -f -n "$file" 2>/dev/null; then parsed_before=true; fi
  disable_matching_lines "$file" "$(uninstall_shell_pattern)" "teeup uninstall"
  if [[ "$DRY_RUN" == "true" ]]; then
    uninstall_note removed "teeup's lines in $file (your own lines stay)"
    return 0
  fi
  backup="$(uninstall_newest_backup "$file" || true)"
  if uninstall_shell_live "$file"; then
    uninstall_note failed "$file: teeup's lines are still live (see the warnings above). Delete the lines that mention TEEUP_PATH or teeup/env by hand."
    return 0
  fi
  if [[ "$parsed_before" == "true" ]] && ! zsh -f -n "$file" 2>/dev/null; then
    if [[ -n "$backup" ]] && cat "$backup" > "$file"; then
      uninstall_note failed "$file: zsh could not parse it with teeup's lines disabled, so it was put back as it was. Delete the lines that mention TEEUP_PATH or teeup/env by hand."
    else
      uninstall_note failed "$file: zsh cannot parse it with teeup's lines disabled. Your copy from before is ${backup:-missing}."
    fi
    return 0
  fi
  uninstall_note removed "teeup's lines in $file (your own lines stay; the file as it was is at $backup)"
}

# uninstall_shell
# The first mutation of every uninstall, before any tool the layer hooks
# (mise, starship, zoxide, fzf) is removed: a new shell must never start by
# sourcing a hook for a binary that is already gone. A shell that is running
# already registered those hooks at startup and cannot be unhooked from here,
# which is why cmd_uninstall ends by telling the user to open a new one.
# The files are the ones zsh reads (${ZDOTDIR:-$HOME}), in the order it
# reads them. When any of them changed, uninstall_path_hint says how to keep
# the package manager on PATH without teeup.
uninstall_shell() {
  local dir f before="$_UNINSTALL_REMOVED"
  dir="${ZDOTDIR:-$HOME}"
  for f in .zshenv .zprofile .zshrc; do
    _uninstall_shell_file "$dir/$f"
  done
  if [[ "$_UNINSTALL_REMOVED" != "$before" ]]; then
    uninstall_path_hint
  fi
}

# uninstall_path_hint
# teeup's shell layer is what put the package manager on PATH (default/env
# and `brew shellenv` in default/profile). With the layer gone, a new shell
# on Apple Silicon or MacPorts no longer finds brew, port or anything they
# installed, although both stay. The line each package manager documents
# for this is noted, with the command that adds it, unless the user's own
# .zprofile already has one. /usr/local/bin (Intel Homebrew) is on macOS's
# default PATH already.
uninstall_path_hint() {
  local prefix zprofile line
  zprofile="${ZDOTDIR:-$HOME}/.zprofile"
  prefix="$(pkg_prefix)"
  case "$(pkg_backend)" in
    homebrew)
      [[ "$prefix" != "/usr/local" && -x "$prefix/bin/brew" ]] || return 0
      if grep -qs 'brew shellenv' "$zprofile"; then return 0; fi
      line="eval \"\$($prefix/bin/brew shellenv)\""
      ;;
    macports)
      [[ -x "$prefix/bin/port" ]] || return 0
      if grep -qsF "$prefix/bin" "$zprofile"; then return 0; fi
      line="export PATH=\"$prefix/bin:$prefix/sbin:\$PATH\""
      ;;
  esac
  uninstall_note kept "$(pkg_backend_label) at $prefix. teeup's shell layer put it on PATH; to keep it there in new shells run: echo $(uninstall_q "$line") >> $(uninstall_q "$zprofile")"
}
```

- [ ] **Step 5: Run the suites**

Run: `bash tests/lib/files.sh && bash tests/lib/uninstall.sh`
Expected: `tests/lib/files.sh` its count before this task plus 1; `tests/lib/uninstall.sh` `Summary: 13/13 passed`.

- [ ] **Step 6: Run the whole suite and every check CI runs**

Run: `./tests/run.sh`
Expected: `All N suites passed.`, where N is the count printed before this task (no new suite).

Run CI's own shellcheck command, exactly as `.github/workflows/ci.yml` spells it (not a hand-picked file list: a helper sourced by a test is only checked this way):

```bash
shellcheck --severity=warning bootstrap bin/teeup lib/*.sh \
  $(find capabilities -type f \( -name install -o -name configure \
    -o -name remove -o -name doctor -o -name theme-apply \
    -o -name font-apply \)) \
  capabilities/teeup-runtime/default/hooks/*.sample \
  $(find migrations -type f -name '*.sh' 2>/dev/null) \
  tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh tests/docs.sh \
  tests/lib/*.sh tests/capabilities/*.sh
```

Then: `./bin/teeup commands --check && git diff --check`
Expected: shellcheck, `commands --check` and `git diff --check` all silent, exit 0.

- [ ] **Step 7: Commit**

```bash
git add lib/files.sh lib/uninstall.sh tests/lib/files.sh tests/lib/uninstall.sh
git commit -m "Take teeup's lines out of the zsh home files first"
```

No trailer of any kind.

---

### Task 4: The capabilities, dependents first, and teeup's LaunchAgents

Every installed capability, in the reverse of `cap_order`, through `cap_remove` with packages only when asked (Decision 5). The seven `teeup remove` refuses get the answers in Decision 7; a capability still needed by one that failed is refused (Decision 14); zsh's packages are refused while the login shell runs Homebrew's zsh (Review Focus 3). The LaunchAgent sweep follows (Decision 17).

**Files:**
- Modify: `lib/uninstall.sh` (append the capabilities section)
- Test: `tests/lib/uninstall.sh`

**Interfaces:**
- Consumes: Task 1's `cap_remove` and `TEEUP_CAP_NA`; Task 2's `uninstall_caps`, `uninstall_note`, `uninstall_q`; `cap_list`, `cap_meta_get`, `cap_dir`; `package_candidates`, `pkg_installed`, `casks_supported`, `cask_installed`, `pkg_backend`, `pkg_prefix`; `launchagent_remove`; `have`.
- Produces: the globals `_UNINSTALL_PACKAGES`, `_UNINSTALL_IDENTITY` (set by Task 6's `cmd_uninstall`, read by Task 5) and `_UNINSTALL_GONE`; `uninstall_login_shell`, `uninstall_blockers <name>`, `uninstall_policy <name>` (`keep`, `identity`, `state` or `remove`), `uninstall_secret_names`, `uninstall_capabilities`, `uninstall_launchagents`.

**Real-Mac risk:** the format of `security dump-keychain` (an account name with a non-ASCII character is printed as `0x...` hex, not a quoted string; a name containing `"` has not been tried). `dscl . -read /Users/<user> UserShell` prints `UserShell: /bin/zsh` on every macOS release checked in documentation, but not on a real 11 or 12. `brew uninstall a b c` stops at a formula another installed formula depends on, so the printed "Remove them later" command can refuse part of its list; that is Homebrew saying why, which is honest, but a Mac will show whether the list should leave dependencies out. `launchctl bootout` of an agent whose plist is already gone.

- [ ] **Step 1: Write the failing tests**

```bash edit-old=tests/lib/uninstall.sh
echo "lib/uninstall.sh"
```
```bash edit-new=tests/lib/uninstall.sh
# make_remove_script <name> [exit status]
make_remove_script() {
  printf '#!/usr/bin/env bash\necho "remove:%s" >> "$MOCK_LOG"\nexit %s\n' "$1" "${2:-0}" > "$TEEUP_CAPS_DIR/$1/remove"
  chmod +x "$TEEUP_CAPS_DIR/$1/remove"
}

# A brew that says every formula and cask is installed and logs each call.
mock_brew_all_installed() {
  mock_command brew 0 ""
}

test_capabilities_keep_packages_by_default_and_name_how_to_remove_them() {
  setup
  mock_brew_all_installed
  make_cap tool lazy "" "ripgrep" "wezterm"
  make_remove_script tool
  state_done mark cap-tool
  uninstall_capabilities >/dev/null 2>&1
  assert_contains "$(cat "$MOCK_LOG")" "remove:tool" "the remove script still runs" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew uninstall" "packages are kept by default" || return 1
  assert_contains "$_UNINSTALL_KEPT" "Remove them later with: brew uninstall ripgrep" || return 1
  assert_contains "$_UNINSTALL_KEPT" "Remove them later with: brew uninstall --cask wezterm" || return 1
  state_done check cap-tool && { echo "tool is forgotten"; return 1; }
  uninstall_clean || return 1
  cleanup_test_env
}

test_capabilities_name_what_the_tools_made_for_themselves() {
  setup
  make_cap mise core
  make_cap other lazy
  state_done mark cap-other
  uninstall_capabilities >/dev/null 2>&1
  assert_not_contains "$_UNINSTALL_KEPT" "made for themselves" "nothing to say without those tools" || return 1
  state_done mark cap-mise
  uninstall_capabilities >/dev/null 2>&1
  assert_contains "$_UNINSTALL_KEPT" "runtimes mise installed ($HOME/.local/share/mise)" || return 1
  cleanup_test_env
}

test_capabilities_uninstall_packages_when_asked() {
  setup
  mock_brew_all_installed
  make_cap tool lazy "" "ripgrep" "wezterm"
  state_done mark cap-tool
  _UNINSTALL_PACKAGES=true
  uninstall_capabilities >/dev/null 2>&1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall ripgrep" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall --cask wezterm" || return 1
  assert_contains "$_UNINSTALL_REMOVED" "tool's packages: ripgrep wezterm" || return 1
  cleanup_test_env
}

# The seven `teeup remove` refuses. Each is decided, none is run, and none
# counts as a problem.
test_capabilities_decide_each_of_the_seven_remove_refuses() {
  setup
  mock_brew_all_installed
  mock_command security 0 ""
  local name
  for name in xcode-clt package-manager teeup-runtime dev-dirs secrets ssh theme; do
    make_cap "$name" core
    state_done mark "cap-$name"
  done
  uninstall_capabilities >/dev/null 2>&1
  uninstall_clean || { echo "a policy decision is not a problem: $_UNINSTALL_REFUSED$_UNINSTALL_FAILED"; return 1; }
  assert_contains "$_UNINSTALL_KEPT" "Xcode Command Line Tools" || return 1
  assert_contains "$_UNINSTALL_KEPT" "teeup never uninstalls the package manager" || return 1
  assert_contains "$_UNINSTALL_KEPT" "$HOME/Work" || return 1
  assert_contains "$_UNINSTALL_KEPT" "Your SSH keys and ~/.ssh/config" || return 1
  for name in xcode-clt package-manager teeup-runtime dev-dirs secrets ssh theme; do
    case "$_UNINSTALL_GONE" in *" $name "*) ;; *) echo "$name was not handled"; return 1 ;; esac
  done
  assert_not_contains "$(cat "$MOCK_LOG")" "uninstall" || return 1
  cleanup_test_env
}

# A capability whose dependent failed stays, and is refused rather than
# pulled out from under it.
test_capabilities_refuse_what_a_failed_dependent_still_needs() {
  setup
  mock_brew_all_installed
  make_cap base core
  make_remove_script base
  make_cap top lazy base
  make_remove_script top 1
  state_done mark cap-base
  state_done mark cap-top
  uninstall_capabilities >/dev/null 2>&1
  assert_contains "$_UNINSTALL_FAILED" "top: its remove script failed" || return 1
  assert_contains "$_UNINSTALL_REFUSED" "base: still required by top" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "remove:base" "base's remove must not run" || return 1
  state_done check cap-base || { echo "base stays marked for the rerun"; return 1; }
  state_done check cap-top || { echo "top stays marked for the rerun"; return 1; }
  cleanup_test_env
}

# --packages must not take away the zsh the login shell runs.
test_capabilities_keep_the_zsh_the_login_shell_runs() {
  setup
  mock_brew_all_installed
  mock_command dscl 0 "UserShell: $TEEUP_PKG_PREFIX/bin/zsh"
  make_cap zsh core "" "zsh zsh-completions"
  state_done mark cap-zsh
  _UNINSTALL_PACKAGES=true
  uninstall_capabilities >/dev/null 2>&1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew uninstall" || return 1
  assert_contains "$_UNINSTALL_REFUSED" "chsh -s /bin/zsh" || return 1
  state_done check cap-zsh || { echo "zsh stays marked so the rerun can finish"; return 1; }
  cleanup_test_env
}

test_launchagents_are_unloaded_removed_and_checked() {
  setup
  mock_command launchctl 0 ""
  local dir="$TEST_HOME/Library/LaunchAgents"
  mkdir -p "$dir"
  printf '<plist/>\n' > "$dir/sh.teeup.keyboard.plist"
  printf '<plist/>\n' > "$dir/com.other.agent.plist"
  uninstall_launchagents >/dev/null 2>&1
  [[ ! -e "$dir/sh.teeup.keyboard.plist" ]] || { echo "teeup's agent must go"; return 1; }
  assert_file_exists "$dir/com.other.agent.plist" "someone else's agent stays" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "launchctl bootout gui/501 $dir/sh.teeup.keyboard.plist" || return 1
  assert_contains "$_UNINSTALL_REMOVED" "LaunchAgent sh.teeup.keyboard" || return 1
  cleanup_test_env
}

test_secrets_are_named_with_commands_that_delete_them() {
  setup
  mock_command_script security <<'EOF2'
cat <<'DUMP'
keychain: "/Users/x/Library/Keychains/login.keychain-db"
class: "genp"
attributes:
    "acct"<blob>="gh token"
    "svce"<blob>="teeup"
keychain: "/Users/x/Library/Keychains/login.keychain-db"
class: "genp"
attributes:
    "acct"<blob>="someone"
    "svce"<blob>="other-app"
DUMP
EOF2
  make_cap secrets core
  state_done mark cap-secrets
  uninstall_capabilities >/dev/null 2>&1
  assert_contains "$_UNINSTALL_KEPT" "(gh token)" || return 1
  assert_contains "$_UNINSTALL_KEPT" "security delete-generic-password -s teeup -a gh\\ token" || return 1
  assert_not_contains "$_UNINSTALL_KEPT" "someone" || return 1
  cleanup_test_env
}

echo "lib/uninstall.sh"
```

```bash edit-old=tests/lib/uninstall.sh
print_summary
```
```bash edit-new=tests/lib/uninstall.sh
run_test "capabilities keep packages by default and name how to remove them" test_capabilities_keep_packages_by_default_and_name_how_to_remove_them
run_test "capabilities name what the tools made for themselves" test_capabilities_name_what_the_tools_made_for_themselves
run_test "capabilities uninstall packages when asked" test_capabilities_uninstall_packages_when_asked
run_test "capabilities decide each of the seven remove refuses" test_capabilities_decide_each_of_the_seven_remove_refuses
run_test "capabilities refuse what a failed dependent still needs" test_capabilities_refuse_what_a_failed_dependent_still_needs
run_test "capabilities keep the zsh the login shell runs" test_capabilities_keep_the_zsh_the_login_shell_runs
run_test "launchagents are unloaded, removed and checked" test_launchagents_are_unloaded_removed_and_checked
run_test "secrets are named with commands that delete them" test_secrets_are_named_with_commands_that_delete_them
print_summary
```

- [ ] **Step 2: Run them to see them fail**

Run: `bash tests/lib/uninstall.sh`
Expected: the eight new tests fail on `uninstall_capabilities: command not found` or `uninstall_launchagents: command not found`; the thirteen from Tasks 2 and 3 pass.

- [ ] **Step 3: Append the capabilities section to `lib/uninstall.sh`**

```bash edit-old=lib/uninstall.sh
  uninstall_note kept "$(pkg_backend_label) at $prefix. teeup's shell layer put it on PATH; to keep it there in new shells run: echo $(uninstall_q "$line") >> $(uninstall_q "$zprofile")"
}
```
```bash edit-new=lib/uninstall.sh
  uninstall_note kept "$(pkg_backend_label) at $prefix. teeup's shell layer put it on PATH; to keep it there in new shells run: echo $(uninstall_q "$line") >> $(uninstall_q "$zprofile")"
}

# --- capabilities ---------------------------------------------------------------

# Set by cmd_uninstall: "true" to uninstall the packages and casks each
# capability's metadata names, "true" to remove the identity as well.
_UNINSTALL_PACKAGES="${_UNINSTALL_PACKAGES:-false}"
_UNINSTALL_IDENTITY="${_UNINSTALL_IDENTITY:-false}"
# Capabilities handled this run (removed, or kept by policy), space-padded.
_UNINSTALL_GONE=" "
# Installed package and cask names left on the machine, for the one "kept"
# line that says how to remove them later.
_UNINSTALL_KEPT_PKGS=""
_UNINSTALL_KEPT_CASKS=""

# uninstall_login_shell -> the login shell macOS has on record for this user.
uninstall_login_shell() {
  dscl . -read "/Users/${USER:-$(id -un)}" UserShell 2>/dev/null | awk '{print $2}'
}

# uninstall_blockers <name> -> the installed capabilities that still require
# <name> and were not handled this run, space separated (empty when none).
uninstall_blockers() {
  local target="$1" name out=""
  for name in $(cap_list); do
    if [[ "$name" == "$target" ]]; then continue; fi
    case "$_UNINSTALL_GONE" in *" $name "*) continue ;; esac
    state_done check "cap-$name" || continue
    case " $(cap_meta_get "$name" requires) " in
      *" $target "*) out="$out $name" ;;
    esac
  done
  printf '%s\n' "${out# }"
}

# _uninstall_keep_packages <name>
# Adds whichever of <name>'s packages and casks are installed here to the
# kept lists, under the name the package manager knows them by.
_uninstall_keep_packages() {
  local name="$1" pkg candidate cask
  for pkg in $(cap_meta_get "$name" packages); do
    for candidate in $(package_candidates "$pkg"); do
      if pkg_installed "$candidate" >/dev/null 2>&1; then
        case " $_UNINSTALL_KEPT_PKGS " in
          *" $candidate "*) ;;
          *) _UNINSTALL_KEPT_PKGS="${_UNINSTALL_KEPT_PKGS:+$_UNINSTALL_KEPT_PKGS }$candidate" ;;
        esac
        break
      fi
    done
  done
  casks_supported || return 0
  for cask in $(cap_meta_get "$name" casks); do
    if cask_installed "$cask" >/dev/null 2>&1; then
      _UNINSTALL_KEPT_CASKS="${_UNINSTALL_KEPT_CASKS:+$_UNINSTALL_KEPT_CASKS }$cask"
    fi
  done
}

# uninstall_policy <name> -> what uninstall does with a capability that
# `teeup remove` refuses (it ships no remove script and names no packages),
# or "remove" for every other one. Spec amendment 2026-09-25 gives the reason
# for each; the short form is in the kept line each one writes.
uninstall_policy() {
  case "$1" in
    xcode-clt|package-manager|dev-dirs|secrets) echo keep ;;
    ssh) echo identity ;;
    teeup-runtime|theme) echo state ;;
    *) echo remove ;;
  esac
}

# _uninstall_keep_note <name>
_uninstall_keep_note() {
  case "$1" in
    xcode-clt)
      uninstall_note kept "Xcode Command Line Tools: git, compilers and the package manager need them. They are macOS's to manage; remove them by hand with: sudo rm -rf /Library/Developer/CommandLineTools"
      ;;
    package-manager)
      case "$(pkg_backend)" in
        homebrew) uninstall_note kept "Homebrew: teeup never uninstalls the package manager. Homebrew's own uninstaller is: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)\"" ;;
        macports) uninstall_note kept "MacPorts: teeup never uninstalls the package manager. MacPorts documents its removal at https://guide.macports.org/#installing.macports.uninstalling" ;;
      esac
      ;;
    dev-dirs)
      uninstall_note kept "$HOME/Work: your projects live there."
      ;;
    secrets)
      _uninstall_secrets_note
      ;;
  esac
}

# uninstall_secret_names -> the account name of every login-Keychain item
# stored under the service "teeup" (what `teeup secret set` writes), one per
# line. `security dump-keychain` without -d prints attributes only, never a
# secret, and asks for nothing.
uninstall_secret_names() {
  have security || return 0
  security dump-keychain 2>/dev/null | awk '
    /^keychain: / { if (svce == "teeup" && acct != "") print acct; svce = ""; acct = "" }
    /"svce"<blob>="/ { v = $0; sub(/^.*"svce"<blob>="/, "", v); sub(/"$/, "", v); svce = v }
    /"acct"<blob>="/ { v = $0; sub(/^.*"acct"<blob>="/, "", v); sub(/"$/, "", v); acct = v }
    END { if (svce == "teeup" && acct != "") print acct }
  '
}

# _uninstall_secrets_note -> one kept line naming each teeup secret and the
# command that deletes it. Secrets are the user's data, not teeup's
# configuration, so uninstall never deletes them itself.
_uninstall_secrets_note() {
  local secret names="" cmds=""
  while IFS= read -r secret; do
    [[ -n "$secret" ]] || continue
    names="${names:+$names, }$secret"
    cmds="${cmds:+$cmds; }security delete-generic-password -s teeup -a $(uninstall_q "$secret")"
  done <<EOF
$(uninstall_secret_names)
EOF
  [[ -n "$names" ]] || return 0
  uninstall_note kept "Secrets in your login Keychain ($names). Delete them with: $cmds"
}

# _uninstall_remove_one <name>
_uninstall_remove_one() {
  local name="$1" rc=0 with="$_UNINSTALL_PACKAGES" names login
  names="$(cap_meta_get "$name" packages) $(cap_meta_get "$name" casks)"
  names="$(printf '%s' "$names" | awk '{$1=$1; print}')"
  # The login shell must survive. zsh's packages include zsh itself; when
  # the login shell is the package manager's zsh, uninstalling it would
  # leave Terminal nothing to start. The capability stays marked installed,
  # so the rerun this note names can finish it.
  if [[ "$name" == "zsh" && "$with" == "true" ]]; then
    login="$(uninstall_login_shell)"
    case "$login" in
      "$(pkg_prefix)"/*)
        uninstall_note refused "zsh's packages ($names): your login shell is $login, which they provide. Switch to macOS's own zsh first with: chsh -s /bin/zsh, then run: $(uninstall_q "$TEEUP_PATH/bin/teeup") uninstall --packages"
        return 0
        ;;
    esac
  fi
  cap_remove "$name" "$with" || rc=$?
  case "$rc" in
    0)
      _UNINSTALL_GONE="$_UNINSTALL_GONE$name "
      if [[ -f "$(cap_dir "$name")/remove" && "$TEEUP_CAP_NA" != "true" ]]; then
        uninstall_note removed "$name: what its remove script set up"
      fi
      if [[ -n "$names" ]]; then
        if [[ "$with" == "true" ]]; then
          uninstall_note removed "$name's packages: $names"
        else
          _uninstall_keep_packages "$name"
        fi
      fi
      ;;
    2)
      # Nothing teeup tracks for it beyond its own record, which goes with
      # the state directory.
      _UNINSTALL_GONE="$_UNINSTALL_GONE$name "
      ;;
    3)
      uninstall_note failed "$name: its remove script failed (the output above says why), so nothing of it was uninstalled. Fix that, then run: $(uninstall_q "$TEEUP_PATH/bin/teeup") uninstall"
      ;;
    *)
      uninstall_note failed "$name: a package or cask would not uninstall (the output above says which). Fix that, then run: $(uninstall_q "$TEEUP_PATH/bin/teeup") uninstall --packages"
      ;;
  esac
}

# uninstall_capabilities
# Every installed capability, dependents first. A capability another one
# still needs (because that one failed or was refused) is refused in turn:
# pulling the package manager out from under a half-removed capability is
# how a retry becomes impossible.
uninstall_capabilities() {
  local name blockers had
  had=" $(uninstall_caps | tr '\n' ' ')"
  for name in $had; do
    blockers="$(uninstall_blockers "$name")"
    if [[ -n "$blockers" ]]; then
      uninstall_note refused "$name: still required by $blockers, which could not be removed. It goes on the rerun, once those do."
      continue
    fi
    case "$(uninstall_policy "$name")" in
      keep)
        _uninstall_keep_note "$name"
        _UNINSTALL_GONE="$_UNINSTALL_GONE$name "
        ;;
      identity)
        if [[ "$_UNINSTALL_IDENTITY" != "true" ]]; then
          uninstall_note kept "Your SSH keys and ~/.ssh/config: they are your identity. teeup uninstall --identity removes the keys teeup generated."
        fi
        _UNINSTALL_GONE="$_UNINSTALL_GONE$name "
        ;;
      state)
        _UNINSTALL_GONE="$_UNINSTALL_GONE$name "
        ;;
      remove)
        _uninstall_remove_one "$name"
        ;;
    esac
  done
  if [[ -n "$_UNINSTALL_KEPT_PKGS" ]]; then
    case "$(pkg_backend)" in
      homebrew) uninstall_note kept "Packages: $_UNINSTALL_KEPT_PKGS. Remove them later with: brew uninstall $_UNINSTALL_KEPT_PKGS" ;;
      macports) uninstall_note kept "Packages: $_UNINSTALL_KEPT_PKGS. Remove them later with: sudo port uninstall $_UNINSTALL_KEPT_PKGS" ;;
    esac
  fi
  if [[ -n "$_UNINSTALL_KEPT_CASKS" ]]; then
    uninstall_note kept "Apps: $_UNINSTALL_KEPT_CASKS. Remove them later with: brew uninstall --cask $_UNINSTALL_KEPT_CASKS"
  fi
  # What a tool made for itself was never teeup's to track, so it is named
  # rather than silently left behind.
  case "$had" in
    *" mise "*|*" emacs "*|*" zed "*|*" vscode "*)
      uninstall_note kept "What the tools made for themselves: runtimes mise installed (${MISE_DATA_DIR:-$HOME/.local/share/mise}), a Doom or Spacemacs checkout, and the theme and font keys teeup set inside Zed's and VS Code's own settings."
      ;;
  esac
  return 0
}

# uninstall_launchagents
# Every sh.teeup.* agent still in ~/Library/LaunchAgents: the capability
# loop's remove scripts took their own (emacs, keyboard), so anything here
# belongs to a capability no longer marked installed. Unloaded and deleted
# through launchagent_remove, then checked on disk.
uninstall_launchagents() {
  local plist label
  for plist in "$HOME/Library/LaunchAgents"/sh.teeup.*.plist; do
    [[ -e "$plist" || -L "$plist" ]] || continue
    label="${plist##*/}"
    label="${label%.plist}"
    if [[ -L "$plist" ]]; then
      uninstall_note refused "LaunchAgent $label: $plist is a symlink, so teeup left it. Unload and delete it with: launchctl bootout gui/$(id -u) $(uninstall_q "$plist"); rm $(uninstall_q "$plist")"
      continue
    fi
    launchagent_remove "$label" || true
    if [[ "$DRY_RUN" != "true" && -e "$plist" ]]; then
      uninstall_note failed "LaunchAgent $label: $plist is still there. Unload and delete it with: launchctl bootout gui/$(id -u) $(uninstall_q "$plist"); rm $(uninstall_q "$plist")"
      continue
    fi
    uninstall_note removed "LaunchAgent $label"
  done
}
```

- [ ] **Step 4: Run the suite**

Run: `bash tests/lib/uninstall.sh`
Expected: `Summary: 21/21 passed`.

- [ ] **Step 5: Run the whole suite and every check CI runs**

Run: `./tests/run.sh`
Expected: `All N suites passed.`, where N is the count printed before this task (no new suite).

Run CI's own shellcheck command, exactly as `.github/workflows/ci.yml` spells it (not a hand-picked file list: a helper sourced by a test is only checked this way):

```bash
shellcheck --severity=warning bootstrap bin/teeup lib/*.sh \
  $(find capabilities -type f \( -name install -o -name configure \
    -o -name remove -o -name doctor -o -name theme-apply \
    -o -name font-apply \)) \
  capabilities/teeup-runtime/default/hooks/*.sample \
  $(find migrations -type f -name '*.sh' 2>/dev/null) \
  tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh tests/docs.sh \
  tests/lib/*.sh tests/capabilities/*.sh
```

Then: `./bin/teeup commands --check && git diff --check`
Expected: shellcheck, `commands --check` and `git diff --check` all silent, exit 0.

- [ ] **Step 6: Commit**

```bash
git add lib/uninstall.sh tests/lib/uninstall.sh
git commit -m "Remove every capability dependents first, keeping packages unless asked"
```

No trailer of any kind.

---

### Task 5: Config files by the stock-checksum rule, and `--identity`

Every file teeup copied is found from its stock record, whichever capability copied it and wherever it went; pristine goes (after offering back what it replaced), edited stays. The identity files wait for `--identity` (Decisions 8 to 10).

**Files:**
- Modify: `lib/uninstall.sh` (append the configuration section)
- Test: `tests/lib/uninstall.sh`

**Interfaces:**
- Consumes: `config_is_pristine`, `replace_literal`, `backup_target`, `identity_key`, `macos_major`, `user_config_dir`; Task 2's `uninstall_rm`, `uninstall_offer_restore`; Task 4's `_UNINSTALL_IDENTITY`.
- Produces: `uninstall_stock_paths` (every stock-recorded path, one per line), `uninstall_configs`, `uninstall_identity`.

**Real-Mac risk:** `ssh-add -d --apple-use-keychain <key>` is Apple's documented way to drop a key and its stored passphrase (`man ssh-add` on macOS 12 and later; `-K` before), and has not been run here. On a Mac with a non-default `XDG_CONFIG_HOME` outside `$HOME`, every config file there is refused by `uninstall_rm`'s gate and named with its `rm` -- correct, and untested against a real volume. A stock record for a path containing `__` decodes wrongly (phase 1's deferred item 8); the wrong path either does not exist or is not pristine, so nothing is removed, which is the safe direction.

- [ ] **Step 1: Write the failing tests**

```bash edit-old=tests/lib/uninstall.sh
echo "lib/uninstall.sh"
```
```bash edit-new=tests/lib/uninstall.sh
# install_teeup_file <shipped content> <dest>: the file as copy_config_once
# leaves it, stock record included.
install_teeup_file() {
  local src
  src="$(mktemp "$TEST_HOME/src.XXXXXX")"
  printf '%s\n' "$1" > "$src"
  copy_config_once "$src" "$2" >/dev/null
  rm -f "$src"
}

test_configs_remove_pristine_files_keep_edited_ones_and_prune_empty_dirs() {
  setup
  local cfg
  cfg="$(user_config_dir)"
  install_teeup_file "shipped" "$cfg/tool/tool.conf"
  install_teeup_file "shipped" "$cfg/other/other.conf"
  install_teeup_file "shipped" "$cfg/weird dir \$x/w.conf"
  printf 'mine\n' >> "$cfg/other/other.conf"
  uninstall_configs >/dev/null 2>&1
  [[ ! -e "$cfg/tool" ]] || { echo "a pristine file goes, and its emptied directory with it"; return 1; }
  [[ ! -e "$cfg/weird dir \$x" ]] || { echo "an awkward path is decoded and removed too"; return 1; }
  assert_file_exists "$cfg/other/other.conf" "an edited file stays" || return 1
  assert_contains "$_UNINSTALL_KEPT" "Config files you edited: $cfg/other/other.conf" || return 1
  assert_dir_exists "$cfg" "the config directory itself is never pruned" || return 1
  cleanup_test_env
}

# Without --identity, ~/.ssh/config and ~/.config/git/config stay even when
# pristine: git reads the identity through them.
test_configs_keep_the_identity_files_without_identity() {
  setup
  local gdir
  gdir="$(user_config_dir)/git"
  install_teeup_file "Host github.com" "$HOME/.ssh/config"
  install_teeup_file "[include]" "$gdir/config"
  printf '# Generated by teeup (teeup configure git). Your edits here are overwritten.\n[core]\n' > "$gdir/teeup-generated"
  printf '# Generated by teeup (teeup configure git). Your edits here are overwritten.\n[user]\n' > "$gdir/identity"
  uninstall_configs >/dev/null 2>&1
  assert_file_exists "$HOME/.ssh/config" || return 1
  assert_file_exists "$gdir/config" || return 1
  assert_file_exists "$gdir/identity" || return 1
  [[ ! -e "$gdir/teeup-generated" ]] || { echo "teeup's generated settings go either way"; return 1; }
  cleanup_test_env
}

test_configs_leave_a_generated_file_teeup_did_not_write() {
  setup
  local gdir
  gdir="$(user_config_dir)/git"
  mkdir -p "$gdir"
  printf '[core]\n\teditor = nano\n' > "$gdir/teeup-generated"
  uninstall_configs >/dev/null 2>&1
  assert_file_exists "$gdir/teeup-generated" || return 1
  assert_contains "$_UNINSTALL_KEPT" "teeup did not write it" || return 1
  cleanup_test_env
}

# teeup-generated kept signing off while no key existed. With it gone, the
# kept config's gpgsign = true would fail every commit, so the printed fix
# must turn it off -- and it does.
test_configs_gpgsign_fix_works() {
  setup
  hide_host_commands ssh
  local gdir fix
  gdir="$(user_config_dir)/git"
  install_teeup_file "$(printf '[commit]\n\tgpgsign = true')" "$gdir/config"
  uninstall_configs >/dev/null 2>&1
  fix="$(printf '%s\n' "$_UNINSTALL_KEPT" | sed -n 's/^Commit signing.*Turn signing off with: //p')"
  [[ -n "$fix" ]] || { echo "no signing fix was printed"; return 1; }
  run_fix "$fix" || { echo "the fix failed: $fix"; return 1; }
  assert_equals "false" "$(git config --file "$gdir/config" commit.gpgsign)" || return 1
  cleanup_test_env
}

test_identity_removes_only_teeups_keys_and_moves_local_aside() {
  setup
  mock_command ssh-add 0 ""
  local gdir
  gdir="$(user_config_dir)/git"
  mkdir -p "$HOME/.ssh" "$gdir"
  printf 'k\n' > "$HOME/.ssh/id_ed25519_personal"
  printf 'k\n' > "$HOME/.ssh/id_ed25519_personal.pub"
  printf 'k\n' > "$HOME/.ssh/id_ed25519"
  printf '# Generated by teeup (teeup configure git). Your edits here are overwritten.\n' > "$gdir/identity"
  printf '[user]\n\temail = me@example.com\n' > "$gdir/local"
  uninstall_identity >/dev/null 2>&1
  [[ ! -e "$HOME/.ssh/id_ed25519_personal" && ! -e "$HOME/.ssh/id_ed25519_personal.pub" ]] || { echo "teeup's key pair goes"; return 1; }
  assert_file_exists "$HOME/.ssh/id_ed25519" "a key teeup did not name stays" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "ssh-add -d --apple-use-keychain $HOME/.ssh/id_ed25519_personal" || return 1
  [[ ! -e "$gdir/identity" ]] || { echo "the generated identity goes"; return 1; }
  [[ ! -e "$gdir/local" ]] || { echo "local is moved aside"; return 1; }
  [[ -n "$(uninstall_newest_backup "$gdir/local")" ]] || { echo "local's content must survive in a backup"; return 1; }
  cleanup_test_env
}

echo "lib/uninstall.sh"
```

```bash edit-old=tests/lib/uninstall.sh
print_summary
```
```bash edit-new=tests/lib/uninstall.sh
run_test "configs remove pristine files, keep edited ones and prune empty dirs" test_configs_remove_pristine_files_keep_edited_ones_and_prune_empty_dirs
run_test "configs keep the identity files without --identity" test_configs_keep_the_identity_files_without_identity
run_test "configs leave a generated file teeup did not write" test_configs_leave_a_generated_file_teeup_did_not_write
run_test "configs gpgsign fix works" test_configs_gpgsign_fix_works
run_test "identity removes only teeup's keys and moves local aside" test_identity_removes_only_teeups_keys_and_moves_local_aside
print_summary
```

- [ ] **Step 2: Run them to see them fail**

Run: `bash tests/lib/uninstall.sh`
Expected: the five new tests fail on `uninstall_configs: command not found` or `uninstall_identity: command not found`.

- [ ] **Step 3: Append the configuration section to `lib/uninstall.sh`**

```bash edit-old=lib/uninstall.sh
    uninstall_note removed "LaunchAgent $label"
  done
}
```
```bash edit-new=lib/uninstall.sh
    uninstall_note removed "LaunchAgent $label"
  done
}

# --- configuration files --------------------------------------------------------

# uninstall_stock_paths -> every file teeup holds a stock record for, one per
# line: the reverse of lib/files.sh's _stock_record_path, which names a record
# after the path relative to $HOME with "/" turned into "__" (an absolute
# path, outside $HOME, keeps its leading "/" and so starts with "__"). This is
# every file copy_config_once, refresh_config or refresh_if_pristine ever
# installed, whichever capability did it and wherever it went. Nearly every
# record name starts with a dot (.config__..., .zshrc), which a plain * does
# not match, hence the two extra globs.
uninstall_stock_paths() {
  local record rel
  for record in "$TEEUP_STATE_DIR/stock"/* "$TEEUP_STATE_DIR/stock"/.[!.]* "$TEEUP_STATE_DIR/stock"/..?*; do
    [[ -f "$record" ]] || continue
    rel="${record##*/}"
    case "$rel" in
      __*) replace_literal "$rel" "__" "/" ;;
      *) printf '%s/%s\n' "$HOME" "$(replace_literal "$rel" "__" "/")" ;;
    esac
  done
}

# _uninstall_prune_dirs <removed file>
# Directories the removal left empty go too, walking up, but never $HOME
# itself or the XDG config directory. rmdir removes only an empty directory,
# so anything of the user's stops the walk.
_uninstall_prune_dirs() {
  local dir config
  if [[ "$DRY_RUN" == "true" ]]; then return 0; fi
  dir="$(dirname "$1")"
  config="$(user_config_dir)"
  while [[ "$dir" == "$HOME"/* && "$dir" != "$config" ]]; do
    rmdir "$dir" 2>/dev/null || break
    dir="$(dirname "$dir")"
  done
}

# _uninstall_generated <file> <label>
# A file teeup generates in full (git's identity and teeup-generated) says so
# on its first line and is overwritten on every configure, so it is teeup's
# whatever it holds. Without that line it is not a file teeup wrote.
_uninstall_generated() {
  local file="$1" label="$2"
  [[ -e "$file" || -L "$file" ]] || return 0
  if [[ ! -L "$file" ]] && head -n 1 "$file" 2>/dev/null | grep -q '^# Generated by teeup'; then
    uninstall_rm "$file" "$label" || true
  else
    uninstall_note kept "$file: teeup did not write it."
  fi
}

# uninstall_configs
# The stock-checksum rule (spec section 9) decides every file teeup copied:
# pristine, it is teeup's and goes (after offering back whatever it replaced);
# edited, it is the user's and stays. The zsh home files were already handled
# by uninstall_shell. ~/.ssh/config and ~/.config/git/config carry the
# identity and wait for --identity.
uninstall_configs() {
  local path zdot gdir key edited=""
  zdot="${ZDOTDIR:-$HOME}"
  gdir="$(user_config_dir)/git"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    case "$path" in
      "$zdot/.zshenv"|"$zdot/.zprofile"|"$zdot/.zshrc") continue ;;
    esac
    if [[ "$_UNINSTALL_IDENTITY" != "true" ]]; then
      case "$path" in
        "$HOME/.ssh/config"|"$gdir/config") continue ;;
      esac
    fi
    [[ -e "$path" || -L "$path" ]] || continue
    if config_is_pristine "$path"; then
      if uninstall_offer_restore "$path"; then continue; fi
      if uninstall_rm "$path" "teeup's $path"; then _uninstall_prune_dirs "$path"; fi
    else
      edited="${edited:+$edited, }$path"
    fi
  done <<STOCK
$(uninstall_stock_paths)
STOCK
  if [[ -n "$edited" ]]; then
    uninstall_note kept "Config files you edited: $edited"
  fi
  _uninstall_generated "$gdir/teeup-generated" "teeup's generated git settings ($gdir/teeup-generated)"
  if [[ "$_UNINSTALL_IDENTITY" != "true" && -f "$gdir/config" ]]; then
    uninstall_note kept "$gdir/config and $gdir/identity: git reads your name and email through them. teeup uninstall --identity removes them."
    # teeup-generated turned signing off until a key existed; with it gone
    # the shipped config's gpgsign = true is back in charge, and signing
    # with no key fails every commit.
    key="$(identity_key personal)"
    if grep -qE '^[[:space:]]*gpgsign[[:space:]]*=[[:space:]]*true' "$gdir/config" && [[ ! -f "$key" || ! -f "$key.pub" ]]; then
      uninstall_note kept "Commit signing is on in $gdir/config but $key is missing, so git commit would fail. Turn signing off with: git config --file $(uninstall_q "$gdir/config") commit.gpgsign false"
    fi
  fi
}

# uninstall_identity
# Only with --identity. The keys at teeup's own naming convention
# (~/.ssh/id_ed25519_<identity>) and nothing else: a key the user's own
# ~/.ssh/config named was theirs before teeup and stays. Each key's
# passphrase is dropped from the login Keychain first, with the same flag
# capabilities/ssh/configure stored it with. ~/.ssh/config went with the
# other configs if it was pristine. git's identity file is generated and
# goes; ~/.config/git/local is the user's own and is moved aside, never
# deleted.
uninstall_identity() {
  local id key flag="--apple-use-keychain" major gdir backup
  major="$(macos_major)"
  if [[ "$major" =~ ^[0-9]+$ && "$major" -lt 12 ]]; then flag="-K"; fi
  for id in personal work; do
    key="$HOME/.ssh/id_ed25519_$id"
    [[ -e "$key" || -L "$key" || -e "$key.pub" || -L "$key.pub" ]] || continue
    if [[ -f "$key" ]] && have ssh-add; then
      run_cmd ssh-add -d "$flag" "$key" 2>/dev/null || log "The ssh agent did not hold $key; nothing to forget."
    fi
    uninstall_rm "$key" "SSH key $key" || true
    uninstall_rm "$key.pub" "SSH key $key.pub" || true
  done
  gdir="$(user_config_dir)/git"
  _uninstall_generated "$gdir/identity" "your git identity ($gdir/identity)"
  if [[ -e "$gdir/local" && ! -L "$gdir/local" ]]; then
    if backup="$(backup_target "$gdir/local")"; then
      uninstall_note removed "$gdir/local (moved to $backup, since teeup never wrote it)"
    else
      uninstall_note failed "$gdir/local: could not move it aside. Move it yourself with: mv $(uninstall_q "$gdir/local") $(uninstall_q "$gdir/local.old")"
    fi
  fi
  uninstall_note kept "Public keys teeup uploaded to GitHub: they stay on your account. Delete them at https://github.com/settings/keys"
}
```

- [ ] **Step 4: Run the suite**

Run: `bash tests/lib/uninstall.sh`
Expected: `Summary: 26/26 passed`.

- [ ] **Step 5: Run the whole suite and every check CI runs**

Run: `./tests/run.sh`
Expected: `All N suites passed.`, where N is the count printed before this task (no new suite).

Run CI's own shellcheck command, exactly as `.github/workflows/ci.yml` spells it (not a hand-picked file list: a helper sourced by a test is only checked this way):

```bash
shellcheck --severity=warning bootstrap bin/teeup lib/*.sh \
  $(find capabilities -type f \( -name install -o -name configure \
    -o -name remove -o -name doctor -o -name theme-apply \
    -o -name font-apply \)) \
  capabilities/teeup-runtime/default/hooks/*.sample \
  $(find migrations -type f -name '*.sh' 2>/dev/null) \
  tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh tests/docs.sh \
  tests/lib/*.sh tests/capabilities/*.sh
```

Then: `./bin/teeup commands --check && git diff --check`
Expected: shellcheck, `commands --check` and `git diff --check` all silent, exit 0.

- [ ] **Step 6: Commit**

```bash
git add lib/uninstall.sh tests/lib/uninstall.sh
git commit -m "Remove pristine config files and, when asked, the identity"
```

No trailer of any kind.

---

### Task 6: The teardown and `teeup uninstall`

The last step and the verb. The teardown removes teeup's command, config and state only after a clean run (Decisions 11 and 12). `cmd_uninstall` parses the flags, refuses root, asks its questions, runs the six steps in Contract 7's order, prints the summary, and ends a real run with the checkout's `rm -rf` and the new-terminal line.

**Files:**
- Modify: `lib/uninstall.sh` (append the teardown section), `bin/teeup` (`cmd_uninstall`, `usage()`, dispatch)
- Test: `tests/lib/uninstall.sh`, `tests/cli.sh`

**Interfaces:**
- Consumes: every step function from Tasks 2 to 5; `lazy_is_tty`, `ui_confirm`, `TEEUP_HOOK_EVENTS`.
- Produces: `uninstall_teardown`; `cmd_uninstall` and the verb (Contract 8).

**Real-Mac risk:** `teeup uninstall` is usually started through `~/.local/bin/teeup`, which the teardown deletes while the command is still running. bash holds `bin/teeup` open in the checkout (the symlink only led to it), so this is expected to be harmless, and it is exactly what the CLI tests do on Linux -- but only a Mac proves Apple's bash 3.2 does not reopen the script by its invoked path. The parent zsh keeps its `precmd` hooks until it is replaced; the closing line says so, and nothing else can.

- [ ] **Step 1: Write the failing tests**

The teardown in `tests/lib/uninstall.sh`:

```bash edit-old=tests/lib/uninstall.sh
echo "lib/uninstall.sh"
```
```bash edit-new=tests/lib/uninstall.sh
# teeup's own files as teeup-runtime/configure leaves them, the user's own
# machine file among them.
teeup_runtime_home() {
  mkdir -p "$TEEUP_CONFIG_DIR/hooks/post-update.d" "$TEEUP_STATE_DIR/done" "$HOME/.local/bin"
  printf 'export TEEUP_PATH=x\n' > "$TEEUP_CONFIG_DIR/env"
  printf 'TEEUP_NAME="Ada"\n' > "$TEEUP_CONFIG_DIR/answers"
  printf '# sample\n' > "$TEEUP_CONFIG_DIR/hooks/post-update.d/example.sample"
  ln -s "$TEEUP_PATH/bin/teeup" "$HOME/.local/bin/teeup"
}

test_teardown_removes_teeups_command_config_and_state() {
  setup
  teeup_runtime_home
  uninstall_teardown >/dev/null 2>&1
  [[ ! -e "$TEEUP_CONFIG_DIR" ]] || { echo "the config dir goes when nothing of the user's is in it"; return 1; }
  [[ ! -e "$TEEUP_STATE_DIR" ]] || { echo "the state dir goes"; return 1; }
  [[ ! -L "$HOME/.local/bin/teeup" ]] || { echo "the command goes"; return 1; }
  assert_file_exists "$TEEUP_PATH/bin/teeup" "the checkout stays" || return 1
  cleanup_test_env
}

test_teardown_keeps_the_users_own_files_in_the_config_dir() {
  setup
  teeup_runtime_home
  mkdir -p "$TEEUP_CONFIG_DIR/machines" "$TEEUP_CONFIG_DIR/hooks/post-update.d"
  printf 'TEEUP_SKIP="aerospace"\n' > "$TEEUP_CONFIG_DIR/machines/testmac.conf"
  printf 'echo mine\n' > "$TEEUP_CONFIG_DIR/hooks/post-update.d/mine"
  uninstall_teardown >/dev/null 2>&1
  assert_file_exists "$TEEUP_CONFIG_DIR/machines/testmac.conf" || return 1
  assert_file_exists "$TEEUP_CONFIG_DIR/hooks/post-update.d/mine" || return 1
  [[ ! -e "$TEEUP_CONFIG_DIR/env" && ! -e "$TEEUP_CONFIG_DIR/answers" ]] || { echo "teeup's own files go"; return 1; }
  [[ ! -e "$TEEUP_CONFIG_DIR/hooks/post-update.d/example.sample" ]] || { echo "the sample goes"; return 1; }
  assert_contains "$_UNINSTALL_KEPT" "machines/testmac.conf" || return 1
  cleanup_test_env
}

# After any refusal or failure the rerun needs teeup's state, config and
# command, so none of them is touched.
test_teardown_waits_for_a_clean_run() {
  setup
  teeup_runtime_home
  uninstall_note failed "something"
  uninstall_teardown >/dev/null 2>&1
  assert_dir_exists "$TEEUP_STATE_DIR" || return 1
  assert_file_exists "$TEEUP_CONFIG_DIR/env" || return 1
  [[ -L "$HOME/.local/bin/teeup" ]] || { echo "the command stays for the rerun"; return 1; }
  cleanup_test_env
}

test_teardown_leaves_a_command_that_is_not_teeups() {
  setup
  mkdir -p "$HOME/.local/bin"
  ln -s /somewhere/else "$HOME/.local/bin/teeup"
  uninstall_teardown >/dev/null 2>&1
  [[ -L "$HOME/.local/bin/teeup" ]] || { echo "a link to somewhere else is not teeup's"; return 1; }
  assert_contains "$_UNINSTALL_KEPT" "not at this checkout" || return 1
  cleanup_test_env
}

# A state directory outside $HOME is refused, and the printed rm removes it.
test_teardown_refuses_a_state_dir_outside_home_with_a_fix_that_works() {
  setup
  export HOME="$TEST_HOME/home"
  export TEEUP_STATE_DIR="$TEST_HOME/elsewhere/st ate \$x"
  export TEEUP_CONFIG_DIR="$HOME/.config/teeup"
  mkdir -p "$HOME" "$TEEUP_STATE_DIR/done"
  uninstall_teardown >/dev/null 2>&1
  assert_dir_exists "$TEEUP_STATE_DIR" || return 1
  assert_contains "$_UNINSTALL_REFUSED" "teeup's state" || return 1
  run_fix "${_UNINSTALL_REFUSED##*mean to: }" || { echo "the printed rm failed"; return 1; }
  [[ ! -e "$TEEUP_STATE_DIR" ]] || { echo "the printed rm must remove it"; return 1; }
  cleanup_test_env
}

echo "lib/uninstall.sh"
```

```bash edit-old=tests/lib/uninstall.sh
print_summary
```
```bash edit-new=tests/lib/uninstall.sh
run_test "teardown removes teeup's command, config and state" test_teardown_removes_teeups_command_config_and_state
run_test "teardown keeps the user's own files in the config dir" test_teardown_keeps_the_users_own_files_in_the_config_dir
run_test "teardown waits for a clean run" test_teardown_waits_for_a_clean_run
run_test "teardown leaves a command that is not teeup's" test_teardown_leaves_a_command_that_is_not_teeups
run_test "teardown refuses a state dir outside HOME, with a fix that works" test_teardown_refuses_a_state_dir_outside_home_with_a_fix_that_works
print_summary
```

The verb in `tests/cli.sh`, before its final `print_summary` (phase 4b adds tests to this file; `print_summary` stays its last line, so the anchor holds). `uninstall_fixture` builds the Mac the 2026-09-25 run happened on, in miniature: the real zsh home files, and fixture `mise` and `starship` capabilities whose `remove` scripts record whether the shell layer is still loaded at the moment they run. The two `reports a refused ... and still finishes` tests are the only place a refusal meets `set -e`; see Global Constraints.

```bash edit-old=tests/cli.sh
print_summary
```
```bash edit-new=tests/cli.sh
# A machine teeup set up, in miniature: the real zsh home files (rendered by
# the checkout's own zsh capability, which only reads the checkout), and two
# fixture capabilities named after tools the shell layer hooks. Each one's
# remove script records whether ~/.zshrc still sources teeup's layer at the
# moment the tool comes off.
uninstall_fixture() {
  hide_host_commands chezmoi
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR"
  TEEUP_CAPS_DIR="$TEEUP_PATH/capabilities" "$TEEUP" configure zsh >/dev/null 2>&1
  local name
  for name in mise starship; do
    make_cap "$name" core
    cat > "$TEEUP_CAPS_DIR/$name/remove" <<EOF2
#!/usr/bin/env bash
if grep -qs 'TEEUP_PATH' "\$HOME/.zshrc" || [[ -e "\$HOME/.zshenv" ]]; then
  echo "remove:$name shell-layer=live" >> "\$MOCK_LOG"
else
  echo "remove:$name shell-layer=gone" >> "\$MOCK_LOG"
fi
echo "remove:$name"
EOF2
    chmod +x "$TEEUP_CAPS_DIR/$name/remove"
  done
  printf 'alpha\nbeta\nmise\nstarship\n' > "$TEEUP_CAPS_DIR/core.list"
  mock_command brew 0 ""
  mock_command launchctl 0 ""
  "$TEEUP" install mise >/dev/null
  "$TEEUP" install starship >/dev/null
  : > "$MOCK_LOG"
}

# home_snapshot: every path under the test HOME with its checksum, except
# the mock log, which the mocks themselves append to.
home_snapshot() {
  find "$TEST_HOME" ! -name mock.log -print | LC_ALL=C sort
  find "$TEST_HOME" -type f ! -name mock.log -exec cksum {} + | LC_ALL=C sort
}

# The order a real Mac proved matters (2026-09-25): mise and starship were
# removed while ~/.zshrc still loaded their hooks, and every prompt of every
# shell after that failed. The layer comes off first.
test_uninstall_takes_the_shell_layer_off_before_what_it_hooks() {
  setup
  uninstall_fixture
  local out rc=0
  out="$(TEEUP_TEST_TTY=no "$TEEUP" uninstall --yes 2>&1)" || rc=$?
  assert_success "$rc" "$out" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "remove:mise shell-layer=gone" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "remove:starship shell-layer=gone" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "shell-layer=live" || return 1
  assert_file_exists "$HOME/.zshrc" "a .zshrc is always left" || return 1
  assert_contains "$(printf '%s\n' "$out" | tail -1)" "Open a new terminal (or run: exec /bin/zsh -l)" || return 1
  assert_contains "$out" "rm -rf $(printf '%q' "$TEEUP_PATH")" "the checkout stays, with how to delete it" || return 1
  [[ ! -e "$TEST_HOME/.local/state/teeup" && ! -e "$TEST_HOME/.config/teeup" ]] || { echo "teeup's state and config go after a clean run"; return 1; }
  cleanup_test_env
}

test_uninstall_refuses_to_run_unasked() {
  setup
  local out rc=0
  out="$(TEEUP_TEST_TTY=no "$TEEUP" uninstall 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "teeup uninstall --yes" || return 1
  rc=0
  out="$(TEEUP_TEST_TTY=no "$TEEUP" uninstall --frobnicate 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Usage: teeup uninstall [--packages] [--identity] [--yes]" || return 1
  mock_command id 0 "0"
  rc=0
  out="$(TEEUP_TEST_TTY=no "$TEEUP" uninstall --yes 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "not as root" || return 1
  assert_contains "$("$TEEUP" help)" "teeup uninstall [--packages] [--identity] [--yes]" || return 1
  cleanup_test_env
}

test_uninstall_on_a_terminal_asks_first_and_no_changes_nothing() {
  setup
  uninstall_fixture
  local before out
  before="$(home_snapshot)"
  out="$(printf 'n\n' | TEEUP_TEST_TTY=yes "$TEEUP" uninstall 2>&1)"
  assert_contains "$out" "Take teeup off this Mac?" || return 1
  assert_contains "$out" "Nothing was changed." || return 1
  assert_equals "$before" "$(home_snapshot)" || return 1
  cleanup_test_env
}

test_uninstall_asks_about_packages_and_keeps_them_by_default() {
  setup
  uninstall_fixture
  printf 'packages="ripgrep"\n' >> "$TEEUP_CAPS_DIR/mise/capability"
  local out
  out="$(printf 'y\n\n' | TEEUP_TEST_TTY=yes "$TEEUP" uninstall 2>&1)"
  assert_contains "$out" "Also uninstall the packages and apps teeup installed" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew uninstall" "an empty answer keeps the packages" || return 1
  assert_contains "$out" "brew uninstall ripgrep" "and says how to remove them later" || return 1
  cleanup_test_env
  setup
  uninstall_fixture
  printf 'packages="ripgrep"\n' >> "$TEEUP_CAPS_DIR/mise/capability"
  out="$(printf 'y\ny\n' | TEEUP_TEST_TTY=yes "$TEEUP" uninstall 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall ripgrep" "a yes uninstalls them" || return 1
  cleanup_test_env
}

test_uninstall_dry_run_changes_nothing() {
  setup
  uninstall_fixture
  local before out rc=0
  before="$(home_snapshot)"
  out="$(DRY_RUN=true TEEUP_TEST_TTY=yes "$TEEUP" uninstall --packages 2>&1 </dev/null)" || rc=$?
  assert_success "$rc" || return 1
  assert_equals "$before" "$(home_snapshot)" "a dry run changes nothing" || return 1
  assert_not_contains "$out" "Take teeup off this Mac?" "a dry run asks nothing" || return 1
  assert_contains "$out" "Would remove (dry run; nothing was changed):" || return 1
  assert_not_contains "$out" "✅" "a dry run claims nothing" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "uninstall" || return 1
  cleanup_test_env
}

test_uninstall_twice_does_nothing_the_second_time() {
  setup
  uninstall_fixture
  TEEUP_TEST_TTY=no "$TEEUP" uninstall --yes >/dev/null 2>&1
  : > "$MOCK_LOG"
  local before out rc=0
  before="$(home_snapshot)"
  out="$(TEEUP_TEST_TTY=no "$TEEUP" uninstall --yes 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "Nothing of teeup's was left to remove." || return 1
  assert_equals "$before" "$(home_snapshot)" || return 1
  cleanup_test_env
}

# A failure keeps the run's exit status, and keeps teeup's state and command
# so the rerun the output names can finish.
test_uninstall_fails_loudly_and_keeps_what_a_rerun_needs() {
  setup
  uninstall_fixture
  printf '#!/usr/bin/env bash\nexit 1\n' > "$TEEUP_CAPS_DIR/mise/remove"
  local out rc=0
  out="$(TEEUP_TEST_TTY=no "$TEEUP" uninstall --yes 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "mise: its remove script failed" || return 1
  assert_contains "$out" "then run: $(printf '%q' "$TEEUP_PATH/bin/teeup") uninstall" || return 1
  assert_dir_exists "$TEST_HOME/.local/state/teeup" || return 1
  "$TEEUP" has mise || { echo "mise stays marked for the rerun"; return 1; }
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/mise/remove"
  rc=0
  TEEUP_TEST_TTY=no "$TEEUP" uninstall --yes >/dev/null 2>&1 || rc=$?
  assert_success "$rc" "the rerun finishes" || return 1
  [[ ! -e "$TEST_HOME/.local/state/teeup" ]] || { echo "the rerun tears down"; return 1; }
  cleanup_test_env
}

# A refusal anywhere must reach the summary and the exit status, never end
# the run early: bin/teeup runs under `set -e`, and a step that returned a
# refusal's status as a plain statement would stop the verb before it said
# anything. One refusal in the first step, one in the last.
test_uninstall_reports_a_refused_home_file_and_still_finishes() {
  setup
  uninstall_fixture
  mkdir -p "$TEST_HOME/dotfiles/.git"
  mv "$HOME/.zshrc" "$TEST_HOME/dotfiles/zshrc"
  ln -s "$TEST_HOME/dotfiles/zshrc" "$HOME/.zshrc"
  local out rc=0
  out="$(TEEUP_TEST_TTY=no "$TEEUP" uninstall --yes 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "teeup uninstall summary" || return 1
  assert_contains "$out" "$HOME/.zshrc is a symlink" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "remove:mise" "the rest of the run still happened" || return 1
  assert_contains "$(printf '%s\n' "$out" | tail -1)" "Open a new terminal" || return 1
  cleanup_test_env
}

test_uninstall_reports_a_refused_state_dir_and_still_finishes() {
  setup
  export HOME="$TEST_HOME/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export TEEUP_STATE_DIR="$TEST_HOME/elsewhere/state"
  mkdir -p "$HOME"
  uninstall_fixture
  local out rc=0
  out="$(TEEUP_TEST_TTY=no "$TEEUP" uninstall --yes 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "teeup uninstall summary" || return 1
  assert_contains "$out" "teeup's state" || return 1
  assert_dir_exists "$TEEUP_STATE_DIR" || return 1
  assert_contains "$(printf '%s\n' "$out" | tail -1)" "Open a new terminal" || return 1
  cleanup_test_env
}

run_test "uninstall takes the shell layer off before what it hooks" test_uninstall_takes_the_shell_layer_off_before_what_it_hooks
run_test "uninstall refuses to run unasked" test_uninstall_refuses_to_run_unasked
run_test "uninstall on a terminal asks first, and no changes nothing" test_uninstall_on_a_terminal_asks_first_and_no_changes_nothing
run_test "uninstall asks about packages and keeps them by default" test_uninstall_asks_about_packages_and_keeps_them_by_default
run_test "uninstall dry run changes nothing" test_uninstall_dry_run_changes_nothing
run_test "uninstall twice does nothing the second time" test_uninstall_twice_does_nothing_the_second_time
run_test "uninstall fails loudly and keeps what a rerun needs" test_uninstall_fails_loudly_and_keeps_what_a_rerun_needs
run_test "uninstall reports a refused home file and still finishes" test_uninstall_reports_a_refused_home_file_and_still_finishes
run_test "uninstall reports a refused state dir and still finishes" test_uninstall_reports_a_refused_state_dir_and_still_finishes
print_summary
```

- [ ] **Step 2: Run them to see them fail**

Run: `bash tests/lib/uninstall.sh; bash tests/cli.sh`
Expected: the five teardown tests fail on `uninstall_teardown: command not found`; the nine CLI tests fail with `Unknown verb: uninstall`.

- [ ] **Step 3: Append the teardown section to `lib/uninstall.sh`**

```bash edit-old=lib/uninstall.sh
  uninstall_note kept "Public keys teeup uploaded to GitHub: they stay on your account. Delete them at https://github.com/settings/keys"
}
```
```bash edit-new=lib/uninstall.sh
  uninstall_note kept "Public keys teeup uploaded to GitHub: they stay on your account. Delete them at https://github.com/settings/keys"
}

# --- teeup itself -----------------------------------------------------------------

# _uninstall_config_dir
# $TEEUP_CONFIG_DIR holds teeup's env file, the answers and the hook samples,
# and may hold the user's own: a personal machine file, hooks, themes,
# template overrides. teeup's go; the directory goes only when nothing of
# the user's is left in it.
_uninstall_config_dir() {
  local dir="$TEEUP_CONFIG_DIR" teeup_files event f mine="" left=""
  [[ -e "$dir" || -L "$dir" ]] || return 0
  if [[ -L "$dir" ]]; then
    uninstall_note refused "$dir is a symlink, so teeup did not touch it or what it points to. Remove it yourself if you mean to: rm $(uninstall_q "$dir")"
    return 0
  fi
  teeup_files="$dir/env"$'\n'"$dir/answers"
  for event in $TEEUP_HOOK_EVENTS; do
    teeup_files="$teeup_files"$'\n'"$dir/hooks/$event.d/example.sample"
  done
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    case $'\n'"$teeup_files"$'\n' in
      *$'\n'"$f"$'\n'*) mine="${mine:+$mine$'\n'}$f" ;;
      *) left="${left:+$left, }${f#"$dir"/}" ;;
    esac
  done <<FILES
$(find "$dir" \( -type f -o -type l \) -print 2>/dev/null)
FILES
  if [[ -z "$left" ]]; then
    uninstall_rm "$dir" "teeup's config ($dir)" || true
    return 0
  fi
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if uninstall_rm "$f" "teeup's $f"; then _uninstall_prune_dirs "$f"; fi
  done <<MINE
$mine
MINE
  uninstall_note kept "Your own files in $dir: $left. Delete them with: rm -rf $(uninstall_q "$dir")"
}

# uninstall_teardown
# Last, and only after a clean run: the teeup command, $TEEUP_CONFIG_DIR and
# $TEEUP_STATE_DIR. They are what a rerun needs -- the stock records that
# tell a pristine file from an edited one, the install markers, the recorded
# `defaults` values -- so after any refusal or failure they stay.
uninstall_teardown() {
  local link="$HOME/.local/bin/teeup" target
  if ! uninstall_clean; then
    uninstall_note kept "teeup's own state ($TEEUP_STATE_DIR), config ($TEEUP_CONFIG_DIR) and command: something above was refused or failed, and the rerun needs them."
    return 0
  fi
  if [[ -L "$link" ]]; then
    target="$(readlink "$link" 2>/dev/null || true)"
    if [[ "$target" == "$TEEUP_PATH/bin/teeup" ]]; then
      uninstall_rm "$link" "the teeup command ($link)" || true
    else
      uninstall_note kept "$link: it points at $target, not at this checkout."
    fi
  elif [[ -e "$link" ]]; then
    uninstall_note kept "$link: it is a file, not teeup's link."
  fi
  _uninstall_config_dir
  uninstall_rm "$TEEUP_STATE_DIR" "teeup's state ($TEEUP_STATE_DIR: install records, shims, the generated theme, logs)" || true
}
```

- [ ] **Step 4: Add the verb to `bin/teeup`**

`cmd_uninstall` goes right after `cmd_remove`, its usage lines right after `remove`'s, and its dispatch arm right after `remove)`. Phase 4b adds verbs to `usage()` and the dispatch table but not beside `remove`, so these anchors are the same before and after it.

```bash edit-old=bin/teeup
  teeup list [--tier core|daily|lazy]
```
```bash edit-new=bin/teeup
  teeup uninstall [--packages] [--identity] [--yes]
                                 take teeup off this Mac (asks first; keeps your
                                  edits, identity and packages unless told)
  teeup list [--tier core|daily|lazy]
```

```bash edit-old=bin/teeup
}

# _update_checkout -> 0 updated, 1 could not update, 2 must not update.
```
```bash edit-new=bin/teeup
}

# teeup uninstall [--packages] [--identity] [--yes]
# Takes teeup off this Mac (spec amendment of 2026-09-25, lib/uninstall.sh).
# The order is load-bearing:
#   1. the zsh home files, before any tool the shell layer hooks is removed,
#      so no new shell ever starts by calling a binary that is gone;
#   2. every installed capability, dependents first, through the same
#      cap_remove `teeup remove` uses -- packages only when asked;
#   3. any LaunchAgent of teeup's still loaded;
#   4. the config files, by the stock-checksum rule;
#   5. with --identity, the keys and git identity;
#   6. teeup's own command, config and state, only after a clean run.
# It asks at most four questions and only on a terminal, each defaulting to
# the answer that removes less. Without a terminal it needs --yes, which
# also takes every default. A dry run asks nothing and changes nothing.
cmd_uninstall() {
  local arg yes=false tty=false rc=0 teeup_q
  _UNINSTALL_PACKAGES=""
  _UNINSTALL_IDENTITY=false
  for arg in "$@"; do
    case "$arg" in
      --packages) _UNINSTALL_PACKAGES=true ;;
      --identity) _UNINSTALL_IDENTITY=true ;;
      --yes) yes=true ;;
      *) die "Usage: teeup uninstall [--packages] [--identity] [--yes]" ;;
    esac
  done
  if [[ "$(id -u)" == "0" ]]; then
    die "Run teeup uninstall as yourself, not as root: it takes teeup out of your own home directory."
  fi
  if lazy_is_tty; then tty=true; fi
  _UNINSTALL_ASK=false
  if [[ "$DRY_RUN" != "true" ]]; then
    if [[ "$tty" == "true" && "$yes" != "true" ]]; then
      _UNINSTALL_ASK=true
      if ! ui_confirm "Take teeup off this Mac? Your edited files, identity, package manager and the checkout stay." no; then
        log "Nothing was changed."
        return 0
      fi
    elif [[ "$yes" != "true" ]]; then
      die "teeup uninstall asks before it removes anything, and there is no terminal to ask on. Preview it with: DRY_RUN=true teeup uninstall, then run: teeup uninstall --yes"
    fi
  fi
  if [[ -z "$_UNINSTALL_PACKAGES" ]]; then
    _UNINSTALL_PACKAGES=false
    if uninstall_ask "Also uninstall the packages and apps teeup installed (ripgrep, WezTerm, Emacs and the rest)? Homebrew or MacPorts itself stays either way."; then
      _UNINSTALL_PACKAGES=true
    fi
  fi
  if [[ "$_UNINSTALL_IDENTITY" == "true" && "$_UNINSTALL_ASK" == "true" ]]; then
    if ! ui_confirm "Delete the SSH keys teeup generated (~/.ssh/id_ed25519_personal and _work) and your git identity? A private key you have not copied elsewhere is gone for good." no; then
      _UNINSTALL_IDENTITY=false
    fi
  fi
  uninstall_report_reset
  _UNINSTALL_GONE=" "
  uninstall_shell
  uninstall_capabilities
  uninstall_launchagents
  uninstall_configs
  if [[ "$_UNINSTALL_IDENTITY" == "true" ]]; then
    uninstall_identity
  fi
  uninstall_teardown
  uninstall_summary || rc=1
  teeup_q="$(uninstall_q "$TEEUP_PATH/bin/teeup")"
  echo ""
  if [[ $rc -ne 0 ]]; then
    err "Something above was refused or failed. Fix it, then run: $teeup_q uninstall"
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log "That was a preview. Run it for real with: $teeup_q uninstall"
    return $rc
  fi
  log "The teeup checkout is still at $TEEUP_PATH. Delete it when you no longer want it: rm -rf $(uninstall_q "$TEEUP_PATH")"
  log "Open a new terminal (or run: exec /bin/zsh -l). This shell loaded teeup's hooks when it started and keeps calling them until it is replaced."
  return $rc
}

# _update_checkout -> 0 updated, 1 could not update, 2 must not update.
```

```bash edit-old=bin/teeup
  theme) cmd_theme "$@" ;;
```
```bash edit-new=bin/teeup
  uninstall) cmd_uninstall "$@" ;;
  theme) cmd_theme "$@" ;;
```

- [ ] **Step 5: Prove the order test can fail**

The order is the reason this verb exists (Review Focus 1), so prove the test would catch a regression: move the `uninstall_shell` line in `cmd_uninstall` below `uninstall_capabilities`, run `bash tests/cli.sh`, and see `uninstall takes the shell layer off before what it hooks` fail on `remove:mise shell-layer=live`. Put the line back.

- [ ] **Step 6: Run the suites**

Run: `bash tests/lib/uninstall.sh && bash tests/cli.sh && bash tests/docs.sh`
Expected: `tests/lib/uninstall.sh` `Summary: 31/31 passed`; `tests/cli.sh` its count before this task plus 9; `tests/docs.sh` unchanged (it reads the dispatch table, and `uninstall` is in it now).

- [ ] **Step 7: Run the whole suite and every check CI runs**

Run: `./tests/run.sh`
Expected: `All N suites passed.`, where N is the count printed before this task (no new suite).

Run CI's own shellcheck command, exactly as `.github/workflows/ci.yml` spells it (not a hand-picked file list: a helper sourced by a test is only checked this way):

```bash
shellcheck --severity=warning bootstrap bin/teeup lib/*.sh \
  $(find capabilities -type f \( -name install -o -name configure \
    -o -name remove -o -name doctor -o -name theme-apply \
    -o -name font-apply \)) \
  capabilities/teeup-runtime/default/hooks/*.sample \
  $(find migrations -type f -name '*.sh' 2>/dev/null) \
  tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh tests/docs.sh \
  tests/lib/*.sh tests/capabilities/*.sh
```

Then: `./bin/teeup commands --check && git diff --check`
Expected: shellcheck, `commands --check` and `git diff --check` all silent, exit 0.

- [ ] **Step 8: Commit**

```bash
git add lib/uninstall.sh bin/teeup tests/lib/uninstall.sh tests/cli.sh
git commit -m "Add teeup uninstall"
```

No trailer of any kind.

---

### Task 7: README and CONTRIBUTING

**Files:**
- Modify: `README.md` (a section after "Migrating a Mac that already had teeup or chezmoi"), `CONTRIBUTING.md` (one numbered item at the end)

**Interfaces:**
- Consumes: the verb as Task 6 left it.
- Produces: nothing code reads, except `tests/docs.sh`, which checks that every `teeup <verb>` in a README code block is a verb `bin/teeup` accepts. The new section is its own `###` heading rather than a bullet under `teeup remove`, because `tests/docs.sh` reads the `teeup remove` bullet up to the next bullet that starts with a capital, and a bullet here would be read as part of it.

**Real-Mac risk:** none.

- [ ] **Step 1: The README section**

```markdown edit-old=README.md

This repository contains `teeup.sh`, a cross-platform developer setup script. It configures your workspace and installs essential tooling so you can get straight to work.
```
````markdown edit-new=README.md

### Taking teeup off a Mac

```bash
DRY_RUN=true teeup uninstall        # a preview: no questions, and nothing is changed
teeup uninstall                     # asks first; keeps packages unless you say yes
teeup uninstall --packages          # also uninstall what the capabilities installed
teeup uninstall --identity          # also the SSH keys teeup generated and the git identity
teeup uninstall --yes               # no questions (needed without a terminal); takes every default
```

`teeup uninstall` works in a fixed order. First it takes teeup's lines out of
your zsh home files, before anything they load is removed: a `~/.zshrc`
teeup installed and you never edited is replaced by a short one of your own
(never deleted, so zsh always has one), `~/.zshenv` and `~/.zprofile` go, and
in a file you edited only teeup's lines are disabled, with a copy of the file
as it was beside it. Then every installed capability comes off, dependents
first, through the same removal `teeup remove` uses; teeup's LaunchAgents are
unloaded; every config file teeup copied and you never edited is removed, and
every one you edited stays; and last, `~/.local/bin/teeup`,
`~/.config/teeup` and `~/.local/state/teeup` go (wherever `XDG_CONFIG_HOME`,
`XDG_STATE_HOME`, `TEEUP_CONFIG_DIR` and `TEEUP_STATE_DIR` put them).

What it keeps unless you say otherwise: the packages and apps (it asks,
defaulting to no), your SSH keys, `~/.ssh/config` and git identity (only
`--identity` touches them), and your own files inside `~/.config/teeup` -- a
machine file, hooks, themes. What it never removes: Homebrew or MacPorts, the
Xcode Command Line Tools, `~/Work`, the secrets in your Keychain, and the
checkout itself. The summary names each one with the command that removes it
by hand, and when a file teeup replaced at install time is still beside it as
a `.teeup_backup_*` copy, it offers to put that back.

It refuses anything outside your home directory, anything inside a git
checkout, and any symlink it would have to write through, and it will not
uninstall the zsh your login shell runs. A refusal or a failure makes it exit
non-zero and keeps teeup's own state and command in place, so running it
again after you fix the cause finishes the job; a second run on a clean Mac
changes nothing. The shell you ran it from still has teeup's hooks loaded, so
open a new terminal afterwards.

This repository contains `teeup.sh`, a cross-platform developer setup script. It configures your workspace and installs essential tooling so you can get straight to work.
````

- [ ] **Step 2: The contributor rule**

Append one item to the end of the numbered list. On `main` at `31a4644` the list ends at 28 and the item is 29, as below; after phase 4b it ends at 32, and the item is numbered 33 with the same text.

```markdown edit-old=CONTRIBUTING.md
    opens a block is reported rather than broken.
```
```markdown edit-new=CONTRIBUTING.md
    opens a block is reported rather than broken.
29. `teeup uninstall` finds what to remove from teeup's own records, not
    from a list in `lib/uninstall.sh`: installed capabilities from the done
    markers, config files from the stock records, LaunchAgents by the
    `sh.teeup.` label prefix. A new capability is covered by following the
    rules above -- a `remove` script for machine state, `packages`/`casks`
    in metadata, `copy_config_once` for shipped files, `launchagent_install`
    for agents. A `remove` script that uninstalls software itself (a
    MacPorts port in place of a cask) must skip it when
    `TEEUP_REMOVE_PACKAGES` is `false`, which is how `teeup uninstall` keeps
    packages. A capability with no `remove` script and no packages needs a
    line in `uninstall_policy`, or uninstall treats it as having nothing to
    undo. Every deletion goes through `uninstall_rm`.
```

- [ ] **Step 3: Run the docs suite**

Run: `bash tests/docs.sh`
Expected: its count unchanged, all passing (`README only shows verbs that exist` now meets `teeup uninstall` and accepts it).

- [ ] **Step 4: Run the whole suite and every check CI runs**

Run: `./tests/run.sh`
Expected: `All N suites passed.`, where N is the count printed before this task (no new suite).

Run CI's own shellcheck command, exactly as `.github/workflows/ci.yml` spells it (not a hand-picked file list: a helper sourced by a test is only checked this way):

```bash
shellcheck --severity=warning bootstrap bin/teeup lib/*.sh \
  $(find capabilities -type f \( -name install -o -name configure \
    -o -name remove -o -name doctor -o -name theme-apply \
    -o -name font-apply \)) \
  capabilities/teeup-runtime/default/hooks/*.sample \
  $(find migrations -type f -name '*.sh' 2>/dev/null) \
  tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh tests/docs.sh \
  tests/lib/*.sh tests/capabilities/*.sh
```

Then: `./bin/teeup commands --check && git diff --check`
Expected: shellcheck, `commands --check` and `git diff --check` all silent, exit 0.

- [ ] **Step 5: Commit**

```bash
git add README.md CONTRIBUTING.md
git commit -m "Document teeup uninstall"
```

No trailer of any kind.

---

## Before the first real run

`teeup uninstall` has not run on a Mac. The first time it does, on a machine whose loss would matter:

1. `DRY_RUN=true teeup uninstall --packages --identity`, and read every line of the summary. Every "Remove it yourself" and "Remove them later" command in it should be one you would run.
2. `ls ~/.ssh ~/.config/git`, and copy anything irreplaceable somewhere else. `--identity` deletes private keys.
3. The real run, from a terminal, answering the questions. Say no to packages the first time.
4. Open a new terminal before anything else (the old one keeps teeup's hooks), and confirm it starts without an error and that `brew` is found -- or add the line the summary printed.
5. Run `teeup uninstall` again through the checkout's `bin/teeup`: it should say "Nothing of teeup's was left to remove." and exit 0.

---

## Self-review

### Spec coverage

| Spec amendment text | Task |
|---|---|
| order step 1: the zsh home files before any tool the layer hooks; pristine `.zshrc` replaced, never deleted; pristine `.zshenv`/`.zprofile` removed; edited files neutralised with a backup; symlink or git checkout refused | 3 (`uninstall_shell`), 6 (called first; the order test) |
| "the run ends by telling the user to open a new terminal (or `exec /bin/zsh -l`)" | 6 |
| order step 2: every installed capability, dependents first, through `teeup remove`'s removal; a capability still required by one that failed is refused | 1 (`cap_remove`), 4 |
| order step 3: teeup's LaunchAgents | 4 (`uninstall_launchagents`) |
| order step 4: config files by the stock-checksum rule, backups offered back | 2 (`uninstall_offer_restore`), 5 |
| order step 5: `--identity`, and `~/.config/git/config` kept without it | 5 |
| order step 6: command, config and state last, only after a clean run; the user's own files in the config dir stay | 6 |
| packages asked (default no), `--packages`, kept with `--yes` or no terminal, named with the command that removes them | 4 (`_uninstall_keep_packages`), 6 (the question) |
| `DRY_RUN=true` asks nothing and changes nothing | 2, 3, 6 (dry-run tests) |
| four-column summary, non-zero on refused or failed, a second run changes nothing | 2 (`uninstall_summary`), 6 (rerun tests) |
| never: Homebrew/MacPorts, edited configs, the checkout (with its `rm -rf` printed) | 4, 5, 6 |
| `--packages` never uninstalls the login shell's zsh | 4 |
| the table of the seven | 4 (`uninstall_policy`, `_uninstall_keep_note`, `_uninstall_secrets_note`), 6 (teardown for `teeup-runtime` and `theme`) |
| honour XDG / `TEEUP_CONFIG_DIR` / `TEEUP_STATE_DIR` | 3 (rendered env path), 5, 6 (teardown outside `$HOME`) |

### Placeholder scan

No "TBD", "TODO", "implement later", "similar to Task N", or step without its code. The one number the executor derives is each existing suite's count, by rule R3. Every note that ends in a command prints a command a test runs, except the three that point outside teeup (Homebrew's uninstaller, MacPorts' documented procedure, the GitHub keys page), which are in the external facts below.

### Name and type consistency

`cap_remove` (Task 1) is called only by `cmd_remove` (Task 1) and `_uninstall_remove_one` (Task 4), both with `true|false` and both reading the 0/1/2/3 statuses of Contract 1. `_UNINSTALL_ASK`, `_UNINSTALL_PACKAGES`, `_UNINSTALL_IDENTITY` and `_UNINSTALL_GONE` are defined in `lib/uninstall.sh` (Tasks 2 and 4), set by `cmd_uninstall` (Task 6) and by each test's `setup`. `uninstall_rm`, `uninstall_note`, `uninstall_q`, `uninstall_offer_restore` and `uninstall_newest_backup` keep the names and argument order Task 2 gives them in every later task. `run_fix` is defined in Task 2's test file and used by Tasks 2, 3, 5 and 6.

### External facts to verify before the task that prints them merges

| Fact | Printed or used by | Source to check |
|---|---|---|
| Homebrew's uninstaller: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"` | Task 4 | Homebrew FAQ, "How do I uninstall Homebrew?" |
| MacPorts' removal procedure at https://guide.macports.org/#installing.macports.uninstalling | Task 4 | the MacPorts Guide, section 2.5 |
| `security dump-keychain` prints attributes, never a secret, without `-d`; `security delete-generic-password -s <service> -a <account>` | Task 4 | `man security` on a Mac |
| `dscl . -read /Users/<user> UserShell` prints `UserShell: <path>` | Task 4 | `man dscl` on a Mac |
| `chsh -s /bin/zsh` needs no privilege for a shell in `/etc/shells` | Task 4 | `man chsh`; `capabilities/zsh/install` already relies on it |
| `ssh-add -d --apple-use-keychain <key>` removes the key and its Keychain passphrase; `-K` before macOS 12 | Task 5 | `man ssh-add` on macOS 12+ and 11 |
| `git config --file <path> commit.gpgsign false` | Task 5 | `git config --help`; run by `test_configs_gpgsign_fix_works` |
| `zsh -f -n <file>` parses without sourcing any startup file | Task 3 | `man zshoptions` (`NO_RCS`, `NO_EXEC`); checked against zsh 5.9 while writing this plan |
| `launchctl bootout gui/<uid> <plist>` | Task 4 | already relied on by `launchagent_remove` |

### Mechanical verification of this text

Generated from the tested prototype and replayed against the live tree as described in "How this plan was checked": 17 files, every `edit-old` found exactly once when applied, every `file=` new, and the result identical to the prototype that passed 52 suites, CI's shellcheck command, `commands --check` and `git diff --check`. A second, independent replay parsed the fenced blocks back out of this document and applied them to a fresh export of `main`; the result was again identical.

Against phase 4b: `feat/phase4b-menu-config-dev` at `997ae74` branches from `main` at `31a4644`, and replaying this plan onto it applied every `edit-old` except the two called out (the `lib/all.sh` line and the `CONTRIBUTING.md` item number), which were then made by hand as Task 2 Step 4 and Task 7 Step 2 describe. On that tree `tests/lib/uninstall.sh`, `tests/lib/capability.sh`, `tests/lib/files.sh`, the emacs, wezterm and colima suites, `tests/cli.sh` (131 tests with 4b's) and `tests/docs.sh` all passed.

### Found outside this plan's scope

- `disable_matching_lines` (`lib/files.sh`) never prints the last block-opening line it leaves in place: it reads `$tmp.openers` with `while IFS= read -r`, and awk writes that file without a trailing newline, so the last line is dropped. A run of `teeup uninstall` over an edited `~/.zshrc` shows the header "Left the block-opening lines ... alone" with nothing under it. The fix is `|| [[ -n "$_dml_line" ]]` on the `read`, with a test; it belongs with phase 5b or a follow-up to 5a, not here.
