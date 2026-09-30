# Contributing to teeup.sh

teeup is a macOS environment distribution: a git checkout, a `bootstrap`
script, a `bin/teeup` CLI, a library under `lib/`, and one directory per tool
under `capabilities/`. `README.md` describes it from a user's side; the
manual at https://teeup.systemhalted.in (built from `docs/manual`) is the
long-form walkthrough of every tool teeup configures; this file is the rest.

## Getting started

```bash
git clone https://github.com/<you>/teeup.sh
cd teeup.sh
git checkout -b my-change
./tests/run.sh            # everything, in a worker pool; about a minute
./bin/teeup commands --check
```

The tests need [shellenv](https://github.com/systemhalted/shellenv) on
`PATH`. `tests/run.sh` and every suite re-run themselves inside a throwaway
shellenv home, so no test, and no mistake in one, can write into your real
home: `HOME`, `TMPDIR` and every `XDG_*` directory point into
`.shellenv/teeup/` (gitignored), which is deleted after the run. A file
written there instead of a test's `$TEST_HOME` fails the run and is named.
The first run builds bash 5.2 from source into `$SHELLENV_HOME` (about a
minute; it needs `cc`, `make` and `tar`). GitHub Actions skips the sandbox,
since its runners are thrown away after every job.

You do not need a Mac to work on most of teeup: the suite mocks every
external command and runs on Linux, which is what CI's `ubuntu-latest` job
proves. You do need a Mac to know whether a capability actually works, which
is why every change that touches one should say what it has and has not been
run against.

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
| `machines/<hostname>.conf` | committed per-machine overrides; a fork's fallback when `$TEEUP_CONFIG_DIR/machines` has none | whoever owns that machine |
| `tests/` | `helper.sh`, `run.sh`, `lib/`, `capabilities/`, `cli.sh`, `bootstrap.sh`, `docs.sh` | teeup |
| `docs/legacy-parity.md` | where each part of the previous installer went | teeup |
| `docs/manual/` | the mdBook manual published to teeup.systemhalted.in | teeup |
| `docs/superpowers/` | specs, implementation plans and reviews: the design record | read-only |

Inside a capability, three directories carry three different owners. `config/`
is copied into `~/.config` once and belongs to the user after that. `home/` is
copied into `$HOME` under its literal dotfile name (`home/.zshrc` becomes
`~/.zshrc`), same rule. `default/` stays teeup's and is read at runtime through
`$TEEUP_PATH`, so a `git pull` improves it without touching a user edit. Thin
user files source thick default files.

## Adding a capability

1. Create `capabilities/<name>/` with `capability`, `install` and `configure`,
   or let `./bin/teeup dev new-capability <name>` do it (item 29).
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
   `java`, `git`, `perl`).
6. Add the name to `capabilities/core.list` or `daily.list` if it is not lazy.
7. Add `tests/capabilities/<name>.sh` using the mock harness; run
   `./bin/teeup commands --check && ./tests/run.sh` before committing.
8. Shipped files live in one of three directories, by owner:
   `config/` is copied once into `~/.config` and belongs to the user after
   that; `home/` is copied once into `$HOME` under its literal dotfile name
   (`home/.zshrc` becomes `~/.zshrc`); `default/` stays teeup's and is read at
   runtime through `$TEEUP_PATH`, so upgrades improve it without touching
   anything the user edited. Thin user files source thick default files.
9. Files under `default/` and `home/` are zsh or Lua, not bash: shellcheck
   does not run on them, so keep them simple and guard every optional tool.
10. Per-machine overrides go in `<config>/teeup/machines/<hostname>.conf`,
    which is the user's own file and survives a `git pull`; the checkout's
    `machines/<hostname>.conf` is the fallback, for anyone keeping a fork.
    Either is sourced last, so it wins over the answers file. It is also the
    only place a work identity is configured (`TEEUP_WORK_EMAIL`, plus
    `TEEUP_WORK_GH_HOST` for a GitHub Enterprise host or
    `TEEUP_WORK_GH_ACCOUNT` for a second account on github.com): git has one
    identity everywhere, and the wizard never asks about work. See
    `machines/example.conf.sample`.
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
14. A machine that cannot have the capability at all — not "this step
    failed", but "this tool does not run here" — is a third outcome install
    and configure must be able to report, distinct from both success and
    failure. Call `not_applicable "<message>"` (`lib/capability.sh`) instead
    of a plain `warn` + `exit 0`: it prints `<message>` in place of
    instructions that could never have worked, and tells `cap_run` to treat
    the run as neither done nor failed. Concretely: `teeup install`/bootstrap
    mark nothing done, `teeup has <name>` still reports not-installed, and
    `teeup status` lists the capability as "not applicable on this machine"
    rather than "installed" or leaving it out entirely. A capability whose
    job is only partly blocked (it did something real, just not everything —
    `fonts` on MacPorts records the font family every tool follows even
    though the actual font file needs installing by hand) is not this case;
    keep that a normal, honest success with a `warn` about the gap. Reserve
    `not_applicable` for when nothing about the capability could apply.
    Never call it to swallow a real error — a genuine failure must still
    `warn`/`die` or exit non-zero, or bootstrap's core-tier gate would wave
    it through unnoticed.
15. An editor whose settings are JSON (Zed, VS Code) never gets a shipped
    `settings.json`: its hooks set only the keys teeup owns, with
    `json_set_key <file> <key> <json-value>` or
    `json_merge_key <file> <key> <json-object>` from `lib/files.sh`. The key is
    one literal top-level key (VS Code's `workbench.colorTheme` stays flat),
    the value is a JSON literal (`json_quote` makes one from text), comments
    and trailing commas are read, the write goes through
    `write_managed_file` (so `DRY_RUN` previews it), and a symlink or a file
    jq cannot edit is left alone with a warning.
16. A `theme-apply` or `font-apply` belonging to a capability that may not be
    installed -- every editor, and anything outside the core tier -- starts
    with `if ! state_done check "cap-$TEEUP_CAP"; then exit 0; fi`: `teeup
    theme set` runs every capability's hooks, including on machines where that
    app was never installed through teeup. (A core capability that is always
    present, `wezterm` and `theme`, gates on its own config file existing
    instead.) A hook whose own `configure` runs it --
    one that writes the app's settings file, so there is work to do during the
    install itself, before the done marker exists -- widens the gate to
    `if ! state_done check "cap-$TEEUP_CAP" && [[ "${TEEUP_CONFIGURING:-}" != "$TEEUP_CAP" ]]; then exit 0; fi`
    and that `configure` runs `export TEEUP_CONFIGURING="$TEEUP_CAP"` before
    `cap_run_optional "$TEEUP_CAP" theme-apply` (Zed and VS Code do this). A
    hook that only tells an already-running app to reload (Emacs, Neovim)
    keeps the narrow gate: during a fresh install there is no running app to
    tell, and the next start reads the theme anyway. Theme names an
    editor needs live in the palette next to the colours (`emacs_theme`,
    `zed_theme`, `zed_extension`, `neovim_colorscheme`, `vscode_theme`,
    `vscode_extension`; an extension of `none` installs nothing), so every
    theme, a user theme included, must define each of them in both modes or
    `teeup theme set` refuses to render.
17. A `tier=lazy` capability is reached on first use, never at bootstrap.
    `provides` lists the commands it makes available: `teeup configure
    teeup-runtime` (`shims_generate` in `lib/lazy.sh`) writes one shim per
    command into `~/.local/state/teeup/shims`, last on `PATH`, and each shim
    runs `teeup lazy-run <cap> <command>`. There is no list of lazy
    capabilities to update; adding the directory registers it. Every token
    must be a plain command name (letters, digits and `_.+-`, starting with a
    letter or digit), and two lazy capabilities must not provide the same
    command; `teeup commands --check` fails on either condition. `have`
    (`lib/core.sh`) never counts a shim as an installed command, so
    `pkg_install <pkg> <command>` still installs the package represented by
    the shim.
18. `apps` names the application bundles `teeup launch` opens, separated by
    `;` because names contain spaces (`apps="Visual Studio Code"`). Use the
    `app` artifact name from the cask, without `.app`. The first entry is what
    `launch` opens with `open -a`; when that bundle is missing from
    `/Applications` and `~/Applications`, the capability is installed first.
    Tests point `TEEUP_APPS_DIR` at an empty directory.
19. mise-managed tools go through `lib/mise.sh`. `mise_ensure_global <tool>
    [version]` adds a tool to the global config without rewriting a version
    the user pinned; `mise_wrapper_write <owner> <display-name> <command>
    <tool> [runtime...]` writes an install-on-first-call wrapper into
    `~/.local/bin`, and `mise_wrapper_remove <owner> <command>` removes only a
    wrapper teeup wrote. Every mise call except the wrapper's `mise x` runs
    with `-C /`, so a project's `mise.toml` in the current directory cannot
    shadow the global file. Check registry names with `mise registry`. Give
    each AI leaf its own `tier=lazy` capability with one `provides=` token
    (`ai-claude`, `ai-codex`, `ai-gemini`, `ai-copilot`, `ai-opencode`);
    reserve `ai` for the explicit aggregate that installs all five. A
    wrapper's first install must print progress, append to
    `$TEEUP_STATE_DIR/logs/lazy.log`, and remain retryable after interruption.
    Language runtimes use `teeup install dev-env <lang>` (`dev_env_install`),
    never a capability or a shim.
20. Two test hooks join `TEEUP_TEST_MISSING`: `TEEUP_TEST_TTY=yes|no`
    overrides the terminal check in `teeup lazy-run`, so a piped `y` can
    answer its question, and `hide_host_commands <name...>`
    (`tests/helper.sh`) adds every copy of a command on the host's `PATH` to
    `TEEUP_TEST_MISSING` by absolute path. A test can then prove an install on
    a runner that has `docker` in `/usr/bin` while still finding the copy made
    by the mocked install. `tests/capabilities/colima.sh` is the reference
    round trip.
21. `configure` is re-run by `teeup update` on every machine, so it must be
    quiet and cheap when nothing has changed: report "Already ..." instead of
    rewriting, and never restart an application or print a multi-line manual
    step unconditionally. `defaults_write` leaves a key that already holds
    the value alone and records the domains it did write, so a `configure`
    restarts an app with
    `if defaults_changed com.apple.dock; then run_cmd killall Dock || true; fi`.
    A one-time notice uses `state_done ensure <name>`, which succeeds only the
    first time.
22. `teeup reset <cap>` and a migration's `migration_refresh <cap>` both
    re-run your `configure` with `TEEUP_RESET` or `TEEUP_REFRESH` set to the
    capability's name, which turns each `copy_config_once` in it into
    `refresh_config` or `refresh_if_pristine`. Install every user-facing file
    through `copy_config_once` (rendering into a temporary file first when the
    content depends on the machine, and passing the shipped file as
    `copy_config_once`'s third `display_src` argument so the messages name it
    rather than the temp file — see `capabilities/zsh/configure`) and both
    verbs work for free; a `cp` of your own is invisible to them. A capability
    with no `config/` or `home/` directory is not resettable, and says so.
23. `teeup remove <cap>` uninstalls the `casks` and `packages` your metadata
    names and clears the done marker. Add a `remove` script only for machine
    state teeup created that a package manager cannot undo: a LaunchAgent
    (`launchagent_remove <label>`), recorded `defaults` (`defaults_restore`),
    a `hidutil` mapping. It runs before the uninstall, while the tool is
    still there, and never deletes the user's configuration files.
24. A file teeup owns but the user may edit carries a stock record
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
25. Nothing in `teeup migrate legacy` deletes a path it was given. Every
    removal names a KEY, and `migrate_target` is the closed list of five that
    maps keys to paths -- so no caller anywhere can point a deletion at
    `~/Work/environment/dotfiles`. Adding a key means adding it there, and
    adding a refusal test with it.
26. `chezmoi` is only ever run through `chezmoi_ro`, which accepts `managed`,
    `source-path` and `--version` and dies on anything else. `chezmoi purge`
    removes the source directory, so it must stay unreachable; a test in
    `tests/lib/migrate.sh` greps `bin/`, `lib/` and `capabilities/` for a
    second call site and fails the build if one appears.
27. A test in this area may never name a path outside `$TEST_HOME`. The
    stand-in for the sibling chezmoi checkout is created under `$TEST_HOME`
    with the same shape, so nothing can reach the real one even if a gate
    were broken. A test that only passes on a developer's machine is a defect.
28. Use `disable_matching_lines` rather than editing a shell file by hand. It
    backs the file up first (and refuses to touch it when that backup could
    not be written), refuses a file it cannot write, leaves a symlink alone,
    and neutralises a matching line with `: #` rather than `#` -- an `if`
    whose whole body is commented out is a syntax error, and a line that
    opens a block is reported rather than broken.
29. Start a capability with `teeup dev new-capability <name>`, which writes
    `capabilities/<name>/{capability,install,configure}` and
    `tests/capabilities/<name>.sh` from `share/teeup/skeleton/`. The scaffold
    is `tier=lazy` on purpose: a `core` or `daily` capability that is not in
    its tier list makes `teeup commands --check` fail, so change the tier and
    append to the list in the same commit. Finish with
    `teeup dev check <name>`, which runs the metadata lint, the menu lint,
    shellcheck and that capability's suite -- the same four things CI runs.
    `teeup dev check` with no name runs the whole suite, taking about as long
    as `./tests/run.sh` above.
    Its exit status is 0 when everything passed, 1 when a check ran and found
    a problem, and 2 when a check could not run at all -- shellcheck not
    installed, say, which prints "could not check: shellcheck" and never
    "everything passed", because a check that could not run is not a pass.
    It refuses to run under `DRY_RUN=true`, exiting 1: it runs the real test
    suites, and a dry run of those would not prove anything.
30. A capability may ship an executable `doctor` beside its `install` and
    `configure`. It runs exactly like them (`bash -eu`, `lib/all.sh` loaded,
    answers sourced, `TEEUP_CAP` and `TEEUP_CAP_DIR` exported) and reports
    through `doctor_ok <message>`, `doctor_warn <message>`, `doctor_fail
    <message> <fix>` and `doctor_unknown <message> <fix>`; its last line is
    `doctor_verdict`, which returns 0 when every check reached a verdict and
    none found a problem, 1 when at least one `doctor_fail` fired, and 2 when
    nothing is confirmed broken but at least one `doctor_unknown` fired
    because a check could not run to a verdict at all. `doctor_fail` and
    `doctor_unknown` both return 0 so the script keeps checking, and the fix
    each records is what the summary prints, so make it one command somebody
    can paste. A doctor script mutates nothing, so it needs no `DRY_RUN`
    guard. Do not write one for anything the metadata already says: `teeup
    doctor` checks `packages`, `casks`, `apps` and `provides` for every
    capability by itself. Write one for the invariants metadata cannot
    express -- a config in two places at once, a key with the wrong mode, a
    generated file that is stale.
31. Adding a row to `share/teeup/menu.json` is step 5 of adding a tool. Ids
    are dotted and the tree is in them, so `install.editors.zed` needs
    `install.editors` and `install` to exist as rows too. Every row needs a
    `label`; a row is a leaf when it has an `action` and a submenu when it has
    children, never both and never neither; and no two rows under the same
    parent may share a label, because the picker hands back a label and it is
    mapped to an id by position. `teeup dev check` enforces all of that. Use
    `"when": "! teeup has <name>"` on an Install row so it disappears once the
    thing is installed. The file is read by `lib/menu.awk`, not jq: macOS
    before 15 ships no jq and the harness's narrowed `PATH` hides Homebrew's
    too, so values are one-line strings and the only escapes are `\"`, `\\`
    and `\/`.
32. Anything that draws a full-screen picker -- `gum choose`, `fzf` -- is
    behind `menu_pick`, and `TEEUP_NO_GUM` turns off both, because both paint
    on `/dev/tty`. **Every test that drives a prompt or a menu must
    `export TEEUP_NO_GUM=1`**: the harness narrows `PATH` but `/usr/bin/gum`
    can still be there, and a test that forgets will hang on a real terminal
    widget. A test that wants the fzf branch specifically sets
    `TEEUP_MENU_PICKER=fzf` and mocks `fzf`; no test may need either program
    installed.
33. `teeup uninstall` finds what to remove from teeup's own records, not
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
    undo. Every deletion goes through `uninstall_rm`. A new top-level entry
    under `$TEEUP_STATE_DIR` (a writer such as `lib/state.sh`, `lib/theme.sh`
    or `lib/macos.sh` gaining its own directory there) must be added to
    `_UNINSTALL_STATE_ENTRIES` in `lib/uninstall.sh`, or the state directory
    is never recognised as fully teeup's and never goes.

Phase 4c's twenty capabilities under `install.*` (browsers, communication
apps, container tooling and the rest) are deferred to 0.2.0, and `teeup menu`
has no rows for them yet. Do not add a menu row that points at a
capability which does not exist — `teeup dev check` refuses it, and it would
be the wrong order regardless: the capability comes first, the row after.

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
- **Logging** is `log`, `ok`, `warn`, `err` and `die` from `lib/core.sh` for
  anything reporting progress or an outcome. A bare `echo` still shows up for
  a value a caller reads back (`echo keep`), a line written into a file, and
  the few places that print plain text rather than a single log line —
  `teeup uninstall`'s summary header and `migrate`'s chezmoi lists among
  them.
- **Packages** go through `pkg_install <package> [command]`, never a direct
  `brew` or `port` call, so `TEEUP_PACKAGE_MANAGER=macports` keeps working on
  an old Intel laptop. Casks are Homebrew-only by nature: `cask_install` skips
  them with a note where `casks_supported` is false.
- **Paths with spaces and metacharacters must work.** Quote everything, and
  give at least one test in every new suite a `$TEST_HOME` path containing a
  space, a `$` and a quote.
- **shellcheck at warning severity** is clean on `bootstrap`, `bin/teeup`,
  `lib/*.sh`, every capability script, `share/teeup/skeleton/`'s scripts and
  every test. A disable comment needs a reason on the same line.

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
`print_summary` at the end. `print_summary` compares the `test_*` functions
the file defines against the ones it was asked to run and fails the suite
over any that were left out, so a test nobody passes to `run_test` cannot
silently stop running. `tests/run.sh` finds `tests/lib/*.sh`,
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

A few suites (`tests/capabilities/emacs.sh`, `neovim.sh`, `wezterm.sh`) also
check their output byte-for-byte against a real bash 3.2 binary when one is
available, through `TEEUP_TEST_BASH32`; without it they still run, against
bash's own `%q` output, and note that the bash 3.2 variant was skipped. CI's
macOS runners ship `/bin/bash` 3.2 natively, so this only matters when
developing on Linux.

### Running the suite under macOS's bash

teeup targets `/bin/bash` 3.2.57, and bash 5 accepts things bash 3.2 does
not. On Linux, run the whole suite under 3.2.57 with
[shellenv](https://github.com/systemhalted/shellenv):

```bash
./tests/bash32.sh                  # all suites
./tests/bash32.sh tests/cli.sh     # one suite
```

The first run builds bash 3.2.57 from source into `$SHELLENV_HOME` (about a
minute; it needs `cc`, `make` and `tar`). The script also sets
`TEEUP_TEST_BASH32`, so the byte-for-byte checks above run. shellenv moves
`HOME` into `./.shellenv/bash32/home` (gitignored) for the run; a file that
lands there is a test writing to HOME instead of `$TEST_HOME`, and the run
fails and names it.

## The agent skill

`share/agents/skills/teeup/SKILL.md` is the mental model an AI agent reads
before it touches the tree: the three owners, the read-only trees, the
capability contract, the seven steps of adding one, and how to run the tests.
`teeup configure teeup-runtime` symlinks it into `~/.agents/skills/teeup`
always, and into `~/.claude/skills/teeup`, `~/.codex/skills/teeup` and
`~/.gemini/skills/teeup` where that tool already has a home directory.

Keep it short and keep it true. `tests/docs.sh` checks that every path it
names exists in the checkout and that every verb it names is one `bin/teeup`
actually accepts, but nothing can check that a rule in it still matches the
code, so a change to the capability contract means a look at the skill in the
same commit. When a rule needs more than three sentences it belongs in this
file, and the skill points here instead of repeating it.

## Documentation

`tests/docs.sh` keeps the claims that enumerate the tree honest by deriving
the same set from the capabilities, the menu and `bin/teeup` itself, rather
than trusting prose. It checks, among other things: that every `teeup <verb>`
shown as code in the README or the manual is a verb `bin/teeup` accepts; that
the README's count of capabilities `teeup remove` refuses (no `remove` script,
with neither packages nor casks) matches the tree; that the README's menu field table
matches `lib/menu.awk`; that the README names every AI leaf and the lazy log
path; that the manual's `SUMMARY.md` links every page and no page is orphaned;
that the agent skill's frontmatter, paths and verbs are all real; and that
`docs/legacy-parity.md` has a row for every legacy module and names only
capabilities that exist.

- A new verb needs `bin/teeup help` to print it, and any README or manual
  page that demonstrates it kept in sync — `tests/docs.sh` catches a `teeup
  <verb>` shown as code in either document that `bin/teeup` no longer
  accepts. It does not check the other direction: a real verb that neither
  document demonstrates passes silently.
- A new core or daily capability needs its name in the README's tier list.
- User-facing walkthroughs (themes, fonts, migration, identity, uninstall)
  belong in the manual (`docs/manual/src/`, published to
  https://teeup.systemhalted.in), not copied into the README or here: add or
  extend a page there and link it, rather than duplicating the prose.
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
