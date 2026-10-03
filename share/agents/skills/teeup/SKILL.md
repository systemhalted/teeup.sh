---
name: teeup
description: >
  REQUIRED when working inside a teeup checkout or on a Mac teeup set up.
  Use before editing anything under capabilities/, lib/, themes/, share/ or
  migrations/, before adding a capability or a theme, and when asked how a
  Mac's shell, editors, terminal, fonts, colours, casks or macOS defaults are
  configured. Triggers: teeup, capability, bootstrap, tier, core.list,
  daily.list, lazy shim, teeup install/configure/update/reset/remove/doctor/
  menu/theme/launch/lazy-run/config/secret/migrate/uninstall, answers file,
  machines/<hostname>.conf, ~/.config/teeup, ~/.local/state/teeup, themed
  templates, theme-apply, font-apply. macOS only; not for Linux desktop
  configuration.
---

# teeup

teeup turns a Mac into a working machine and keeps it that way. It is a git
checkout plus one command. Every piece of state it keeps is a file whose
presence or content you can read; very little runs in the background (only
LaunchAgents like `sh.teeup.emacs` and `sh.teeup.keyboard`, whose plists are written and bootstrapped by
`configure`, and booted out and deleted by `remove` and `uninstall`), and nothing
is cached anywhere you cannot open in an editor.

macOS only. If you keep a separate dotfiles repository for Linux, teeup never
touches it.

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

1. **Anything under `~/.local/state/teeup/`.** It holds `done/` and other
   generated records (shims, the current theme and font, logs). Every file
   there is generated. To change it, run the command that generates it:
   `teeup configure teeup-runtime` for the state tree and shims,
   `teeup theme set <name>` for the current theme, `teeup install font <name>`
   for the current font. Deleting a marker under `done/` to "re-run"
   something is the wrong fix; `teeup configure <cap>` is idempotent and is
   the right one.
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
6. **A sibling dotfiles repository for Linux, if you keep one.** It is
   read-only reference that keeps serving Linux. `teeup migrate legacy` never
   runs `chezmoi purge` and is written so that no argument can make it name
   that directory. Keep it that way. Never touch `~/.ssh` keys either: teeup
   can generate missing keys (see `capabilities/ssh/configure`), but never
   deletes or moves one on remove or uninstall; an agent must never delete,
   move or regenerate a user's keys.

## What a capability is

A capability is one directory under `capabilities/` holding a metadata file
and a few scripts. `teeup <verb> <cap>` runs `capabilities/<cap>/<verb>`;
`update` and `remove` fall back to generic implementations derived from the
metadata.

```sh
# capabilities/<name>/capability  -- sourced KEY=value, no logic
summary="One line, shown by teeup list"
group=editors           # editors|shell|git|languages|containers|apps|ai|macos|system
tier=daily              # core | daily | lazy
requires="package-manager git"   # capabilities that run first
provides="nvim"         # commands that get a lazy shim when tier=lazy
packages="neovim"       # pkg_install candidates; drive the generic update and remove
package_commands="neovim:nvim"  # accept this command already on PATH instead (omit to always install)
casks=""                # cask candidates, skipped with a note on MacPorts
apps=""                 # .app bundle names for teeup launch, separated by ;
interactive=false       # true keeps stdin on the TTY (gh auth login, ssh-keygen)
```

Scripts beside it, every one optional except the first two:

| Script | What it may do |
|---|---|
| `install` | install packages only (`pkg_install`, `cask_install`) |
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
`teeup install <cap>`. A core or daily capability that is not in its list
makes `teeup commands --check` fail.

## Adding a capability

1. `./bin/teeup dev new-capability <name>` scaffolds the directory and
   `tests/capabilities/<name>.sh` from `share/teeup/skeleton/`. The scaffold
   is `tier=lazy` on purpose.
2. Fill in the metadata. Check every package and cask name against upstream
   (`https://formulae.brew.sh/api/cask/<token>.json` for a cask) or against
   `mise registry` for a mise tool. Do not guess a name.
3. Write `install` (packages) and `configure` (configuration). Keep them
   idempotent and quiet on a second run: `teeup update` re-runs every core
   `configure` on every machine.
4. If the tier is `core` or `daily`, append the name to the tier list in the
   same commit.
5. Add a row to `share/teeup/menu.json` for anything a person would look for
   in a list. Ids are dotted, so `install.editors.zed` needs `install.editors`
   and `install` to exist as rows too.
6. If the tool has colours, add `capabilities/<name>/themed/<file>.tpl` and a
   `theme-apply`.
7. `./bin/teeup dev check <name>` -- metadata lint, menu lint, shellcheck and
   that capability's suite, which is what CI runs.

`CONTRIBUTING.md` has the long form of each of these, with the rules that are
easy to get wrong (what `provides=` may not name, why `apps=` is `;`
separated, when to write a `doctor` script, how a `theme-apply` guards itself
against running on a machine where the app was never installed). Read it
before the first capability you add.

## Running the tests

```sh
./tests/run.sh                    # every suite, in a worker pool
TEEUP_TEST_JOBS=1 ./tests/run.sh  # serially, when a failure is confusing
bash tests/capabilities/zed.sh    # one suite
./bin/teeup commands --check      # metadata lint; silent means clean
./bin/teeup dev check <name>      # lint + shellcheck + that capability's suite
shellcheck --severity=warning bin/teeup lib/*.sh
```

Every run re-runs itself inside a throwaway shellenv home, so a test cannot
write into the real one; shellenv must be on `PATH`. Never run `bin/teeup`,
`./bootstrap` or a capability script outside the tests (see `AGENTS.md`).

Every suite builds a throwaway `$HOME` and a mock `bin` directory that is
first on a narrowed `PATH` (`$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin`), so no
test touches the real machine and no test may depend on Homebrew. Two rules
catch most new tests out: a test that drives a prompt or a picker must
`export TEEUP_NO_GUM=1`, because the narrowed `PATH` still exposes a host
`/usr/bin/gum` that would paint on the terminal instead of reading stdin; and
a host tool a test needs (`lua`, `jq`, `python3`) has to be resolved before
`setup_test_env` narrows the path, or mocked.

The runtime is bash 3.2, because that is what macOS ships as `/bin/bash`. No
`mapfile`, no `declare -A`, no `${var,,}`, no `readlink -f`, no `wait -n`, and
no same-line `local` back-reference. BSD `sed` and `awk`, no GNU-only flags.

## The verbs

```text
teeup install <cap> | dev-env <lang> | font <name>    teeup configure <cap>
teeup update [<cap>]                                  teeup remove <cap>
teeup reset <cap>                                      teeup doctor [<cap>]
teeup status                                           teeup list [--tier <t>]
teeup menu [<id>]                                      teeup launch <app|cap>
teeup theme set|list|current                           teeup config get|set|edit
teeup has <cap>        (exit code only)                teeup migrate legacy
teeup secret get|set|rm <name>                         teeup lazy-run <cap> <cmd>
teeup dev new-capability|add-migration|check           teeup commands --check
teeup uninstall [--packages] [--identity] [--yes]
```

`teeup help` is the authority; this list is a summary of it.

## Where to read more

- `README.md` -- what teeup installs, and every verb with its behaviour.
- `CONTRIBUTING.md` -- the long form of the capability rules, the code style
  and the test conventions.
- `docs/legacy-parity.md` -- what the previous installer did and where each
  part of it went. Read it before "teeup used to ..." turns into a guess.
- The manual at https://teeup.systemhalted.in (built from `docs/manual`) --
  the long-form walkthrough of every tool teeup configures, tier by tier.
- `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md` --
  why the tree is shaped this way. Read it, do not edit it.
