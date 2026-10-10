# User tools through mise Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pin every command-line tool teeup installs for the user to the version its release names. The tools that teeup itself needs stay with Homebrew or MacPorts. The tools the user uses come from mise at the exact versions in `share/teeup/tools.lock`, linked into `~/.local/bin` so a call costs nothing extra. Package-manager formulae, which cannot be pinned, upgrade only when `teeup update` moves the checkout.

**Architecture:** A new lock file is the one list of versions, and a new `mise_tools="<tool>:<command> ..."` metadata field says which capability owns which tool. `lib/mise.sh` gains a lock reader, a writer for `~/.config/mise/conf.d/teeup.toml` (so `mise prune` keeps the pins), `mise_tool_install`/`mise_tool_remove` (install with `mise -C / install <tool>@<version>`, find the binary with `mise -C / which --tool`, symlink it into `~/.local/bin`, keep a foreign file there), and three drivers: `mise_tools_apply` (install scripts), `mise_tools_repair` (configure scripts) and `mise_tools_sync` (`teeup update` and the migration). `cap_check`, `cap_remove`, `doctor_metadata_check` and `teeup uninstall` learn the field. `cmd_update` records HEAD before and after `_update_checkout` and runs `pkg_upgrade_all` only when it moved, then re-installs and re-links from the lock in a fresh bash that reads the new release's code. `core.list` moves `mise` before every capability that uses it. A migration moves existing Macs and leaves their package-manager copies, which doctor names with the command that removes them.

**Tech Stack:** bash 3.2 (macOS `/bin/bash`), BSD `sed`/`awk`/`grep`, mise (`-C /` on every call), Homebrew/MacPorts through `lib/pkg.sh`, file-existence state under `$TEEUP_STATE_DIR`, the mock harness in `tests/helper.sh` run inside shellenv.

**Spec:** `docs/superpowers/specs/2026-10-08-mise-user-tools-design.md` (issue #112).

---

## How this plan was checked

Read from the checkout on branch `docs/mise-user-tools-spec` (base `aa220d5`, Release 0.3.0-beta, plus the spec commit `9d9798f`): the spec, `AGENTS.md`, `CONTRIBUTING.md`, `lib/mise.sh`, `lib/pkg.sh`, `lib/capability.sh`, `lib/doctor.sh`, `lib/lazy.sh`, `lib/channel.sh`, `lib/uninstall.sh`, `lib/migrations.sh`, `lib/files.sh` (`write_managed_file`), `lib/core.sh`, `lib/state.sh`, `lib/all.sh`, `bin/teeup` (`cmd_install`, `cmd_remove`, `_update_checkout`, `cmd_update`, `cmd_lazy_run`), `bootstrap`, `migrations/README.md` and the two newest migrations, `capabilities/core.list`, every file of `capabilities/{cli-tools,git,starship,neovim,tmux,herdr,ollama,mise}`, `capabilities/zsh/default/{env,init}`, `tests/helper.sh`, `tests/lib/{mise,pkg,doctor,capability,lazy,migrations,uninstall}.sh`, `tests/capabilities/{cli-tools,git,starship,neovim,tmux,herdr,ollama,mise,colima}.sh`, `tests/cli.sh` (update and remove sections), `tests/bootstrap.sh`, `tests/docs.sh`, the manual pages `runtimes.md`, `updates.md`, `doctor-and-troubleshooting.md`, `the-teeup-command.md`, `share/agents/skills/teeup/SKILL.md`, `.github/workflows/ci.yml`.

Facts this plan relies on, each verified in the tree:

- `cap_meta_get` sources the metadata file in a subshell that still sees the caller's locals, so a local named after a metadata key answers for a capability that does not set it (`tests/lib/uninstall.sh`, comment above `make_cap`). No code below names a local `mise_tools`, `packages`, `requires` or any other metadata key.
- `teeup update` runs the **old** checkout's `bin/teeup` in-process after `_update_checkout` moves the tree, but every `cap_run` and `migration_run` starts a fresh `bash` that sources the new `lib/`. The first update to the release with this change therefore runs the old `cmd_update` (no tool sync); only the migration and the core and daily configures run new code.
- `tests/cli.sh`'s `mock_update_world` answers `git rev-parse HEAD` with a constant, so a HEAD comparison needs a stateful mock (Task 9 changes it).
- `tests/bootstrap.sh`'s idempotency test fails on any file under `$TEST_HOME` written by a second bootstrap, so the mise mock must not rewrite a binary it already made.
- `mise registry` on this machine (mise 2026.9.12) lists `aqua:` first for every tool in the spec's mise group except `neovim`, whose first backend is `vfox:mise-plugins/vfox-neovim`. The lock therefore names `aqua:neovim/neovim` for it (Decision 1).
- Lock versions below are `mise -C / ls-remote <tool> | tail -1` on 2026-10-09, read-only. Every lookup succeeded.

---

## Global Constraints

Every task's requirements include this section.

- **`-C /` on every mise call.** Every `mise` invocation in `lib/` and capability scripts is `mise -C / ...`. The only exception is the existing `mise x` line inside an AI wrapper. A printed fix for the user (`mise uninstall <tool>@<version>`) names an exact version, so it needs no `-C /`.
- **bash 3.2.** No `mapfile`, `readarray`, `declare -A`, `${var,,}`, `${var^^}`, `readlink -f`, `**`, `&>>`, `wait -n`, `local -n`. A same-line `local` back-reference (`local a=1 b=$a`) leaves `b` empty. No quoted pattern containing `/` inside `${var//pat/repl}`. Arrays expand as `${array[@]+"${array[@]}"}`.
- **BSD tools.** No GNU-only flags, no `grep -P`, no `\t` or `\n` in a `sed` replacement. Pass an awk value through `ENVIRON` when it can contain a backslash (tool names cannot, so `-v` is used below).
- **Strict mode style.** In any file that runs under `set -e`, write `if … then … fi` rather than a bare `[[ … ]] && cmd` as a statement.
- **Never run teeup against a real home.** Do not run `bin/teeup`, `./bootstrap`, `teeup dev add-migration`, a capability script or a migration directly, not even with `HOME=/tmp/...` in front: `XDG_CONFIG_HOME` and `XDG_STATE_HOME` leak into the real home. Do not set `TEEUP_ALLOW_NON_MACOS`. Create the migration file by hand (Task 10). Lint the shipped metadata through the test added in Task 2, not `./bin/teeup commands --check`.
- **Tests run inside shellenv, in their own process group.** Run a suite as `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/<suite>.sh` and the whole tree as `perl -e 'setpgrp 0,0; exec @ARGV' ./tests/run.sh`. shellenv must be on `PATH`; if it is missing, stop and say so. Never set `SHELLENV_ACTIVE` or `GITHUB_ACTIONS`. Run the bash 3.2 pass with `perl -e 'setpgrp 0,0; exec @ARGV' ./tests/bash32.sh <suite>` for every suite a task touches.
- **Tests never reach the host's mise.** A suite that installs or configures a capability with `mise_tools`, or anything that requires `mise`, calls `mock_mise_tools` in its `setup`. Tests read pinned versions with `lock_version <tool>`; only fixture locks under `$TEST_HOME` contain literal versions.
- **Test hygiene.** One function per behaviour, each registered with `run_test` before the single `print_summary`; no `set -x` and no scratch files left behind. Every new test that drives a prompt exports `TEEUP_NO_GUM=1`. Report each touched suite's `Summary:` line as printed.
- **Never touch `~/.ssh` or git settings outside the repository.** No `git config --global`. If a commit fails because of the user's git setup, stop and report it.
- **Commits.** One commit per task, plain imperative subject, no trailer of any kind: no `Co-Authored-By`, no `Claude-Session`, no generated-by line.
- **Docs.** Pages under `docs/manual/src/` follow ASD-STE100 as `tests/docs.sh` enforces it: at most 25 words per sentence and 6 sentences per paragraph (a code span is one word; tables, headings and fences are skipped), no word from `PLAIN_LANGUAGE_BLOCKLIST` (`just`, `simply`, `easily`, `powerful`, `in order to`, ...), and every `teeup <verb>` shown must be a real verb. `CHANGELOG.md` only gains lines under `[Unreleased]`.
- **Plain prose.** Comments, messages and docs avoid the cliché patterns listed in the owner's global instructions ("No X, no Y" chains, "That's the whole ...", "X is real, and ...", "Worth naming", and the rest).
- **Every task ends with:** the touched suites green under bash 5 and bash 3.2, the full `./tests/run.sh` green, the CI shellcheck command from `.github/workflows/ci.yml` (`shellcheck --severity=warning bootstrap bin/teeup install.sh lib/*.sh $(find capabilities -type f \( -name install -o -name configure -o -name remove -o -name doctor -o -name theme-apply -o -name font-apply \)) capabilities/teeup-runtime/default/hooks/*.sample $(find migrations -type f -name '*.sh') share/teeup/skeleton/install share/teeup/skeleton/configure share/teeup/skeleton/test.sh tests/helper.sh tests/run.sh tests/sandbox.sh tests/sandbox-run.sh tests/cli.sh tests/bootstrap.sh tests/install.sh tests/docs.sh tests/lib/*.sh tests/capabilities/*.sh`) silent, and `git diff --check` clean.

---

## Review Focus

The five input classes the spec implies and a happy-path test suite would miss, most likely first. Each line names the test that covers it and the task that owns that test.

1. **A tool whose command or mise name is not the tool's plain name.** `tealdeer` provides `tldr`, `neovim` provides `nvim` and is installed as `aqua:neovim/neovim`, `ripgrep` provides `rg`. The conf.d key, the `install`/`which`/`uninstall` argument and the link name are three different strings. Tests: `test_tool_install_follows_a_command_and_a_backend_that_differ_from_the_tool` (Task 4), `test_conf_lists_the_tools_of_installed_capabilities_only` (Task 3, backend key), `test_mise_tools_check_notes_an_old_macports_copy` (Task 7, `tealdeer` vs `tldr` package names).
2. **Something already at, or missing behind, `~/.local/bin/<cmd>`.** A user's own file or symlink there must be kept; a teeup link left dangling after `mise uninstall` or `mise prune` must be reported and repaired by the printed fix. Tests: `test_tool_install_keeps_a_file_or_link_teeup_did_not_write`, `test_tool_install_repairs_a_link_left_dangling_by_mise_uninstall`, `test_tool_remove_deletes_only_a_teeup_link` (Task 4); `test_mise_tools_check_fails_a_dangling_link_and_its_fix_repairs_it`, `test_mise_tools_check_leaves_a_foreign_file_alone` (Task 7); the three tmux version tests that now place a foreign `tmux` (Task 8).
3. **mise is not there.** Not installed yet (core order on a first bootstrap, or a preview), installed by the package manager but not yet on `PATH`, or skipped with `TEEUP_SKIP=mise`. Tests: `test_tool_install_without_mise_fails_but_a_dry_run_previews`, `test_apply_finds_a_mise_the_package_manager_just_installed`, `test_apply_refuses_when_mise_is_skipped` (Task 4); `test_shipped_core_list_installs_mise_before_its_users` (Task 5); `test_mise_tools_check_cannot_verify_without_mise`, `test_mise_tools_check_only_warns_when_mise_is_skipped` (Task 7); `test_install_is_not_applicable_when_mise_is_skipped` (Task 8, tmux); `test_mise_tools_migration_without_mise_lets_the_update_continue` (Task 10).
4. **The update path.** A lock version that changes under an installed lazy capability (whose configure `teeup update` never runs), an update that stays on the same release, a dry run, a failed download, and the first update that still runs the previous release's `cmd_update`. Tests: `test_tool_install_relinks_when_the_lock_moves` (Task 4); `test_update_relinks_a_lazy_tool_whose_lock_version_changed`, `test_update_reports_a_pinned_tool_that_would_not_install`, `test_update_leaves_formulae_alone_when_the_checkout_stays`, `test_update_dry_run_upgrades_no_formulae` (Task 9); `test_mise_tools_migration_links_the_tools_and_keeps_the_homebrew_copies` (Task 10, the old-`cmd_update` gap).
5. **A MacPorts Mac.** The same mise tools, no `port install` for a moved tool, and the old-copy notice with `sudo port uninstall` and the MacPorts package name. Tests: `test_install_on_macports_gets_the_same_mise_tools` (Task 8, cli-tools), `test_install_on_macports_still_uses_mise` (Task 8, neovim and herdr), `test_mise_tools_check_notes_an_old_macports_copy` (Task 7).

---

## Decisions made here

1. **The lock line may carry a third field, the mise backend.** `neovim`'s registry entry lists `vfox:` first, and the spec requires an `aqua:` source. `neovim 0.12.6 aqua:neovim/neovim` makes every mise call and the conf.d key use `aqua:neovim/neovim`. `tools_lock_spec <tool>` returns that field, or the tool name when there is none.
2. **Every capability with `mise_tools` requires `mise`, and `cap_check` enforces it.** The spec adds `requires=mise` only to capabilities left with nothing but mise tools. `cli-tools`, `git` and `ollama` need it as much: `cap_order` must install mise before them for `teeup install git` on a bare Mac, and `uninstall_caps` (the reverse of `cap_order`) must remove them before mise.
3. **`cap_check` also refuses one tool in two capabilities.** The spec names commands only. Two owners of one tool would mean `teeup remove` of one uninstalls the other's binary.
4. **`mise_tool_remove` takes a third argument, `<true|false>` for "with packages", and `cap_remove` rewrites the conf.d file once per capability.** The spec has `mise_tool_remove <tool> <command>` rewrite the file itself; with several tools per capability that is several rewrites, each with the capability half-removed.
5. **`mise_tools_apply` installs before it writes conf.d.** A pin written for a version that then fails to download makes `mise activate` warn about a missing tool in every shell. The spec's migration order (conf.d first) is the same pair of calls in the other order.
6. **`teeup update` runs the sync in a fresh bash.** The running `bin/teeup` sourced `lib/` before `_update_checkout` moved the tree, so the new lock must be read by the new code.
7. **`~/.local/bin` goes first on `PATH` inside `bin/teeup` and `bootstrap` (`local_bin_on_path`).** On a fresh Mac the bootstrap shell has no `~/.local/bin`, so `git/configure` would not see the `delta` it had just linked and would choose `less` as the pager.
8. **A capability that is only mise tools answers `not_applicable` when mise is skipped** (starship, neovim, tmux, herdr). cli-tools and git warn and continue, because their package-manager half still applies. ollama warns and keeps its cask.
9. **ollama loses its formula fallback.** When the cask cannot install (macOS 13, MacPorts), the `ollama` command still comes from mise and the message tells the user to start the server with `ollama serve`.
10. **The `tldr` to `tealdeer` MacPorts mapping leaves `package_candidates`.** No capability lists `tldr` as a package any more. Doctor's old-copy notice keeps that knowledge in `mise_tool_old_packages`.
11. **Task order differs from the suggested decomposition.** Remove/uninstall (Task 6) and doctor (Task 7) land before the metadata switch (Task 8), so no commit exists where a moved tool cannot be removed or is not checked. The lock/metadata agreement test moves from Task 1 to Task 8, because "the lock names nothing else" cannot pass before the metadata names the tools. The core.list reorder is Task 5, after the mise mock exists (Task 4), because `requires=mise` makes `teeup install starship` reach the mise capability in suites that until then never mocked mise.
12. **`mise_tools_sync` skips the tools of a TEEUP_SKIP'd capability, and `mise_tools_conf_write` keeps that capability's existing pin rather than pinning a version that was never installed.**

---

## File structure

| Path | Responsibility |
|---|---|
| `share/teeup/tools.lock` | The pinned version of every user tool (new). |
| `lib/mise.sh` | Lock reader, conf.d writer, install/link/remove, apply/repair/sync drivers, `local_bin_on_path`, old-copy helpers. |
| `lib/capability.sh` | `mise_tools` lint in `cap_check`; mise tools in `cap_remove`. |
| `lib/doctor.sh` | `_doctor_mise_tools_check` inside `doctor_metadata_check`. |
| `lib/uninstall.sh` | Summary lines for links, pinned installs and the conf.d file. |
| `lib/pkg.sh` | Drop the `macports:tldr` candidate. |
| `bin/teeup` | `local_bin_on_path`; HEAD-gated `pkg_upgrade_all`; `_update_mise_tools`; remove message. |
| `bootstrap` | `local_bin_on_path` after `pkg_backend_path`. |
| `capabilities/core.list` | `mise` after `teeup-runtime`. |
| `capabilities/{cli-tools,git,starship,neovim,tmux,herdr,ollama}/` | Metadata split and `mise_tools_apply`/`mise_tools_repair` calls. |
| `capabilities/{git,mise}/configure` | Order comments. |
| `migrations/1791459420.sh` | The move on existing Macs (new). |
| `tests/helper.sh` | `lock_version`, `mock_mise_tools`. |
| `tests/lib/{mise,capability,doctor,uninstall,migrations,pkg}.sh`, `tests/cli.sh`, `tests/bootstrap.sh`, `tests/docs.sh`, `tests/capabilities/*.sh` | Tests. |
| `docs/manual/src/{runtimes,updates,doctor-and-troubleshooting,the-teeup-command}.md`, `CONTRIBUTING.md`, `share/agents/skills/teeup/SKILL.md`, `CHANGELOG.md` | Docs. |

---

### Task 1: The lock file and its reader

**Files:**
- Create: `share/teeup/tools.lock`
- Modify: `lib/mise.sh` (append a new section after `mise_upgrade`, end of file, line 351)
- Modify: `tests/helper.sh` (after `missing_tool_status`, line 148)
- Test: `tests/lib/mise.sh` (new tests before `print_summary`, line 792)

**Interfaces:**
- Consumes: nothing new.
- Produces: `TEEUP_TOOLS_LOCK` (default `$TEEUP_PATH/share/teeup/tools.lock`, not exported); `tools_lock_version <tool>` → prints the version, exit 1 when the lock is unreadable or has no line for `<tool>`; `tools_lock_spec <tool>` → prints the third field or `<tool>`, exit 1 the same way; test helper `lock_version <tool>`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/helper.sh` after `missing_tool_status`:

```bash
# lock_version <tool> -> the version share/teeup/tools.lock pins. Tests use
# it so that a release which moves a pin does not have to edit them.
lock_version() {
  awk -v t="$1" '$1 !~ /^#/ && $1 == t { print $2; exit }' "$TEEUP_PATH/share/teeup/tools.lock"
}
```

Add to `tests/lib/mise.sh` after `setup()`:

```bash
# A lock of the test's own, so these tests neither depend on nor move with
# the versions a release pins.
tools_lock_fixture() {
  TEEUP_TOOLS_LOCK="$TEST_HOME/tools.lock"
  cat > "$TEEUP_TOOLS_LOCK" <<'EOF2'
# a comment, and a blank line below

ripgrep 15.2.0
neovim 0.12.6 aqua:neovim/neovim
tealdeer 1.9.0
EOF2
}

test_lock_reader_returns_the_pinned_version_and_spec() {
  setup
  tools_lock_fixture
  assert_equals "15.2.0" "$(tools_lock_version ripgrep)" || return 1
  assert_equals "ripgrep" "$(tools_lock_spec ripgrep)" "no backend field means the registry name" || return 1
  assert_equals "0.12.6" "$(tools_lock_version neovim)" || return 1
  assert_equals "aqua:neovim/neovim" "$(tools_lock_spec neovim)" || return 1
  cleanup_test_env
}

test_lock_reader_fails_for_a_tool_the_lock_does_not_name() {
  setup
  tools_lock_fixture
  local rc=0
  tools_lock_version nosuch >/dev/null || rc=$?
  assert_equals "1" "$rc" || return 1
  rc=0
  tools_lock_version "#" >/dev/null || rc=$?
  assert_equals "1" "$rc" "a comment line is not a tool" || return 1
  rc=0
  TEEUP_TOOLS_LOCK="$TEST_HOME/missing.lock" tools_lock_version ripgrep >/dev/null || rc=$?
  assert_equals "1" "$rc" "no lock file, no version" || return 1
  cleanup_test_env
}

test_shipped_lock_is_well_formed() {
  setup
  local lock="$TEEUP_PATH/share/teeup/tools.lock" bad dups
  assert_file_exists "$lock" || return 1
  bad="$(awk '!/^#/ && NF && (NF < 2 || NF > 3 || $1 !~ /^[A-Za-z0-9][A-Za-z0-9_.+-]*$/ || $2 !~ /^[0-9][0-9A-Za-z.+-]*$/ || (NF == 3 && $3 !~ /:/))' "$lock")"
  assert_equals "" "$bad" "every line is <tool> <version> [<backend>:<name>]" || return 1
  dups="$(awk '!/^#/ && NF { print $1 }' "$lock" | sort | uniq -d)"
  assert_equals "" "$dups" "one line per tool" || return 1
  assert_equals "$(awk '$1 == "ripgrep" { print $2 }' "$lock")" "$(lock_version ripgrep)" "the test helper reads the same file" || return 1
  cleanup_test_env
}
```

Register them before `print_summary`:

```bash
run_test "lock reader returns the pinned version and spec" test_lock_reader_returns_the_pinned_version_and_spec
run_test "lock reader fails for a tool the lock does not name" test_lock_reader_fails_for_a_tool_the_lock_does_not_name
run_test "shipped lock is well formed" test_shipped_lock_is_well_formed
```

- [ ] **Step 2: Run them and see them fail**

Run: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/lib/mise.sh`
Expected: FAIL on all three (`tools_lock_version: command not found`, then `File not found: .../share/teeup/tools.lock`).

- [ ] **Step 3: Create the lock**

`share/teeup/tools.lock`:

```text
# share/teeup/tools.lock - the version of every user tool teeup installs
# through mise (issue #112). One line per tool: <mise tool> <version>, and a
# third field naming the backend when the registry's first choice is not an
# aqua: source. A release changes this file in its release PR, and
# `teeup update` installs and links what it names. tests/lib/mise.sh checks
# that every tool in a capability's mise_tools has exactly one line here and
# that nothing else does.
bat 0.26.1
delta 0.20.1
dust 1.2.6
eza 0.23.5
fd 10.5.0
fzf 0.74.4
git-lfs 3.8.0
herdr 0.9.3
lazygit 0.66.0
neovim 0.12.6 aqua:neovim/neovim
ollama 0.40.2
ripgrep 15.2.0
starship 1.26.0
tealdeer 1.9.0
tmux 3.7c
yq 4.54.1
zoxide 0.10.0
```

- [ ] **Step 4: Add the reader to `lib/mise.sh`**

Append at the end of the file:

```bash

# --- user tools pinned by the release (#112) ---------------------------------
# The tools the user uses come from mise at the exact versions in
# share/teeup/tools.lock; what teeup itself needs stays with the package
# manager. A test points TEEUP_TOOLS_LOCK at a fixture.

TEEUP_TOOLS_LOCK="${TEEUP_TOOLS_LOCK:-$TEEUP_PATH/share/teeup/tools.lock}"

# tools_lock_version <tool> -> the version the lock pins; 1 when the lock is
# unreadable or names no such tool. Comment lines never match.
tools_lock_version() {
  local tool="$1" version
  [[ -r "$TEEUP_TOOLS_LOCK" ]] || return 1
  version="$(awk -v t="$tool" '$1 !~ /^#/ && $1 == t { print $2; exit }' "$TEEUP_TOOLS_LOCK")"
  if [[ -z "$version" ]]; then
    return 1
  fi
  printf '%s\n' "$version"
}

# tools_lock_spec <tool> -> what mise is given for <tool>: the lock's third
# field when it names a backend (neovim's registry entry lists vfox first,
# and the release wants the aqua build), else the tool name itself.
tools_lock_spec() {
  local tool="$1" spec
  [[ -r "$TEEUP_TOOLS_LOCK" ]] || return 1
  spec="$(awk -v t="$tool" '$1 !~ /^#/ && $1 == t { print ($3 != "" ? $3 : $1); exit }' "$TEEUP_TOOLS_LOCK")"
  if [[ -z "$spec" ]]; then
    return 1
  fi
  printf '%s\n' "$spec"
}
```

- [ ] **Step 5: Run and see them pass**

Run: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/lib/mise.sh` and `perl -e 'setpgrp 0,0; exec @ARGV' ./tests/bash32.sh tests/lib/mise.sh`
Expected: PASS; `Summary:` counts three more passes than before.

- [ ] **Step 6: Commit**

```bash
git add share/teeup/tools.lock lib/mise.sh tests/helper.sh tests/lib/mise.sh
git commit -m "Add the tools lock and its reader"
```

---

### Task 2: Lint the `mise_tools` field

**Files:**
- Modify: `lib/capability.sh:170-278` (`cap_check`)
- Test: `tests/lib/capability.sh` (helpers after `setup`, tests and registrations before `print_summary`, line 455)

**Interfaces:**
- Consumes: `tools_lock_version` (Task 1), `TEEUP_TOOLS_LOCK`.
- Produces: `cap_check` problems, one per line, exactly:
  - `<cap>: mise_tools entry '<p>' is not <tool>:<command>`
  - `<cap>: mise_tools names <tool>, which has no line in <lock path>`
  - `<cap>: has mise_tools but does not require mise`
  - `<cap>: mise_tools command <cmd> is also in <other>`
  - `<cap>: mise_tools tool <tool> is also in <other>`

- [ ] **Step 1: Write the failing tests**

Add after `setup()` in `tests/lib/capability.sh`:

```bash
# tools_fixture: a lock of the test's own and a mise capability for the
# requires check to find.
tools_fixture() {
  TEEUP_TOOLS_LOCK="$TEST_HOME/tools.lock"
  printf 'ripgrep 15.2.0\nfd 10.5.0\n' > "$TEEUP_TOOLS_LOCK"
  make_cap mise lazy "" ""
}

# make_tool_cap <name> <mise_tools> [requires, default mise]
make_tool_cap() {
  make_cap "$1" lazy "${3-mise}" ""
  printf 'mise_tools="%s"\n' "$2" >> "$TEEUP_CAPS_DIR/$1/capability"
}
```

Add the tests:

```bash
test_check_accepts_well_formed_mise_tools() {
  setup
  tools_fixture
  make_tool_cap search "ripgrep:rg fd:fd"
  local out rc=0
  out="$(cap_check 2>&1)" || rc=$?
  assert_success "$rc" "a well-formed mise_tools must pass: $out" || return 1
  cleanup_test_env
}

test_check_rejects_a_bad_mise_tools_pair() {
  setup
  tools_fixture
  make_tool_cap search "ripgrep rg: :fd ripgrep:r/g"
  local out rc=0
  out="$(cap_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "search: mise_tools entry 'ripgrep' is not <tool>:<command>" || return 1
  assert_contains "$out" "search: mise_tools entry 'rg:' is not <tool>:<command>" || return 1
  assert_contains "$out" "search: mise_tools entry ':fd' is not <tool>:<command>" || return 1
  assert_contains "$out" "search: mise_tools entry 'ripgrep:r/g' is not <tool>:<command>" || return 1
  cleanup_test_env
}

test_check_rejects_a_mise_tool_without_a_lock_line() {
  setup
  tools_fixture
  make_tool_cap search "ripgrep:rg bat:bat"
  local out rc=0
  out="$(cap_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "search: mise_tools names bat, which has no line in $TEEUP_TOOLS_LOCK" || return 1
  assert_not_contains "$out" "names ripgrep" || return 1
  cleanup_test_env
}

test_check_rejects_a_mise_command_or_tool_in_two_capabilities() {
  setup
  tools_fixture
  make_tool_cap finder "fd:rg"
  make_tool_cap other "ripgrep:rga"
  make_tool_cap search "ripgrep:rg"
  local out rc=0
  out="$(cap_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "search: mise_tools command rg is also in finder" || return 1
  assert_contains "$out" "search: mise_tools tool ripgrep is also in other" || return 1
  cleanup_test_env
}

test_check_requires_mise_for_mise_tools() {
  setup
  tools_fixture
  make_tool_cap search "ripgrep:rg" ""
  local out rc=0
  out="$(cap_check 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "search: has mise_tools but does not require mise" || return 1
  cleanup_test_env
}

# What `./bin/teeup commands --check` runs in CI, against the shipped tree
# and the shipped lock, without running bin/teeup.
test_check_passes_on_the_shipped_tree() {
  setup
  TEEUP_CAPS_DIR="$TEEUP_PATH/capabilities"
  TEEUP_TOOLS_LOCK="$TEEUP_PATH/share/teeup/tools.lock"
  local out rc=0
  out="$(cap_check 2>&1)" || rc=$?
  assert_success "$rc" "the shipped capabilities must lint clean: $out" || return 1
  cleanup_test_env
}
```

Register before `print_summary`:

```bash
run_test "check accepts well-formed mise_tools" test_check_accepts_well_formed_mise_tools
run_test "check rejects a bad mise_tools pair" test_check_rejects_a_bad_mise_tools_pair
run_test "check rejects a mise tool without a lock line" test_check_rejects_a_mise_tool_without_a_lock_line
run_test "check rejects a mise command or tool in two capabilities" test_check_rejects_a_mise_command_or_tool_in_two_capabilities
run_test "check requires mise for mise_tools" test_check_requires_mise_for_mise_tools
run_test "check passes on the shipped tree" test_check_passes_on_the_shipped_tree
```

- [ ] **Step 2: Run and see them fail**

Run: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/lib/capability.sh`
Expected: FAIL on the four rejection tests (cap_check exits 0); the two acceptance tests already pass.

- [ ] **Step 3: Implement**

In `cap_check`, change the locals line:

```bash
  local problems=0 name dir tier provides p verb tpl base other d seen
```

to:

```bash
  local problems=0 name dir tier provides p verb tpl base other d seen pairs tool cmd seen_tools
```

Insert after the `package_commands` loop (after its closing `done`, before the `# apps= is ";"-separated` comment):

```bash
    # mise_tools= (#112): <tool>:<command> pairs installed through mise at
    # the version share/teeup/tools.lock pins and linked as
    # ~/.local/bin/<command>. Both halves become file names and mise
    # arguments, so both must be plain names. A tool with no lock line would
    # install nothing, and a capability that does not require mise could run
    # before mise is installed, or outlive it in `teeup uninstall`.
    pairs="$(cap_meta_get "$name" mise_tools)"
    for p in $pairs; do
      if ! [[ "$p" =~ ^[A-Za-z0-9][A-Za-z0-9_.+-]*:[A-Za-z0-9][A-Za-z0-9_.+-]*$ ]]; then
        echo "$name: mise_tools entry '$p' is not <tool>:<command>"; problems=$((problems + 1))
        continue
      fi
      if ! tools_lock_version "${p%%:*}" >/dev/null; then
        echo "$name: mise_tools names ${p%%:*}, which has no line in $TEEUP_TOOLS_LOCK"; problems=$((problems + 1))
      fi
    done
    if [[ -n "$pairs" ]]; then
      case " $(cap_meta_get "$name" requires) " in
        *" mise "*) ;;
        *) echo "$name: has mise_tools but does not require mise"; problems=$((problems + 1)) ;;
      esac
    fi
```

Insert after the lazy-provides uniqueness loop (after its outer `done`, before `[[ $problems -eq 0 ]]`):

```bash
  # One owner per mise command and per mise tool: two capabilities linking
  # the same ~/.local/bin/<command> would overwrite each other, and removing
  # one would uninstall the other's tool.
  seen=" "
  seen_tools=" "
  for name in $(cap_list); do
    for p in $(cap_meta_get "$name" mise_tools); do
      case "$p" in *?:?*) ;; *) continue ;; esac
      tool="${p%%:*}"
      cmd="${p#*:}"
      case "$seen" in
        *" $cmd="*)
          other="${seen#*" $cmd="}"
          other="${other%% *}"
          echo "$name: mise_tools command $cmd is also in $other"; problems=$((problems + 1))
          ;;
        *) seen="$seen$cmd=$name " ;;
      esac
      case "$seen_tools" in
        *" $tool="*)
          other="${seen_tools#*" $tool="}"
          other="${other%% *}"
          echo "$name: mise_tools tool $tool is also in $other"; problems=$((problems + 1))
          ;;
        *) seen_tools="$seen_tools$tool=$name " ;;
      esac
    done
  done
```

- [ ] **Step 4: Run and see them pass**

Run: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/lib/capability.sh` and `perl -e 'setpgrp 0,0; exec @ARGV' ./tests/bash32.sh tests/lib/capability.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/capability.sh tests/lib/capability.sh
git commit -m "Lint the mise_tools capability field"
```

---

### Task 3: Write the pinned tools to `conf.d/teeup.toml`

**Files:**
- Modify: `lib/mise.sh` (append after the Task 1 section)
- Test: `tests/lib/mise.sh`

**Interfaces:**
- Consumes: `tools_lock_version`, `tools_lock_spec` (Task 1); `cap_list`, `cap_meta_get`, `state_done`, `write_managed_file`, `run_cmd`, `user_config_dir`.
- Produces: `TEEUP_MISE_CONF_MARKER`; `mise_tools_conf_file` → prints `${MISE_CONFIG_DIR:-$(user_config_dir)/mise}/conf.d/teeup.toml`; `mise_tools_conf_write [--with <cap>] [--without <cap>]` → 0 written, current or removed; 1 refused (foreign file, bad argument, or a write that failed).

- [ ] **Step 1: Write the failing tests**

Add after `tools_lock_fixture` in `tests/lib/mise.sh`:

```bash
# make_tool_cap <name> <mise_tools>: a fixture capability whose scripts run
# what a real one with mise tools runs.
make_tool_cap() {
  local name="$1" pairs="$2" dir="$TEST_HOME/caps/$1"
  mkdir -p "$dir"
  printf 'summary="Fixture %s"\ngroup=system\ntier=lazy\nrequires="mise"\nprovides=""\nmise_tools="%s"\ninteractive=false\n' "$name" "$pairs" > "$dir/capability"
  printf '#!/usr/bin/env bash\nmise_tools_apply "$TEEUP_CAP"\n' > "$dir/install"
  printf '#!/usr/bin/env bash\nmise_tools_repair "$TEEUP_CAP"\n' > "$dir/configure"
  chmod +x "$dir/install" "$dir/configure"
}

# tools_fixture: the fixture lock and two capabilities, search (two tools
# whose commands differ from their names) and editor (a backend spec).
tools_fixture() {
  tools_lock_fixture
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  make_tool_cap search "ripgrep:rg tealdeer:tldr"
  make_tool_cap editor "neovim:nvim"
  CONF="$TEST_HOME/.config/mise/conf.d/teeup.toml"
}
```

Tests:

```bash
test_conf_lists_the_tools_of_installed_capabilities_only() {
  setup
  tools_fixture
  state_done mark cap-search
  mise_tools_conf_write >/dev/null || { echo "the write failed"; return 1; }
  assert_file_exists "$CONF" || return 1
  assert_equals "$TEEUP_MISE_CONF_MARKER" "$(head -1 "$CONF")" "the marker is line 1" || return 1
  assert_contains "$(cat "$CONF")" "[tools]" || return 1
  assert_contains "$(cat "$CONF")" '"ripgrep" = "15.2.0"' || return 1
  assert_contains "$(cat "$CONF")" '"tealdeer" = "1.9.0"' "the key is the tool, not its command" || return 1
  assert_not_contains "$(cat "$CONF")" "neovim" "editor is not installed here" || return 1
  local out
  out="$(mise_tools_conf_write 2>&1)"
  assert_contains "$out" "Already current: $CONF" "a second write is quiet" || return 1
  cleanup_test_env
}

test_conf_counts_a_capability_being_installed_and_drops_one_being_removed() {
  setup
  tools_fixture
  state_done mark cap-search
  mise_tools_conf_write --with editor >/dev/null || return 1
  assert_contains "$(cat "$CONF")" '"aqua:neovim/neovim" = "0.12.6"' "the backend spec is the key" || return 1
  mise_tools_conf_write --without search >/dev/null || return 1
  [[ ! -e "$CONF" ]] || { echo "nothing is pinned any more, so teeup's file goes"; return 1; }
  local rc=0
  mise_tools_conf_write --with >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "a flag without its value is refused, not looped on" || return 1
  cleanup_test_env
}

test_conf_leaves_a_file_teeup_did_not_write() {
  setup
  tools_fixture
  state_done mark cap-search
  mkdir -p "${CONF%/*}"
  printf '[tools]\nripgrep = "14.0.0"\n' > "$CONF"
  local out rc=0
  out="$(mise_tools_conf_write 2>&1)" || rc=$?
  assert_equals "1" "$rc" || return 1
  assert_contains "$out" "Keeping $CONF: it was not written by teeup" || return 1
  assert_equals "$(printf '[tools]\nripgrep = "14.0.0"')" "$(cat "$CONF")" "the user's file is untouched" || return 1
  cleanup_test_env
}

test_conf_follows_mise_config_dir_and_dry_run_writes_nothing() {
  setup
  tools_fixture
  state_done mark cap-search
  export MISE_CONFIG_DIR="$TEST_HOME/mise c\$fg 'q'"
  local out
  out="$(DRY_RUN=true mise_tools_conf_write 2>&1)"
  assert_contains "$out" "Would write $MISE_CONFIG_DIR/conf.d/teeup.toml" || return 1
  [[ ! -e "$MISE_CONFIG_DIR/conf.d/teeup.toml" ]] || { echo "dry run wrote the file"; return 1; }
  mise_tools_conf_write >/dev/null || return 1
  assert_file_exists "$MISE_CONFIG_DIR/conf.d/teeup.toml" || return 1
  [[ ! -e "$CONF" ]] || { echo "MISE_CONFIG_DIR moves conf.d too"; return 1; }
  unset MISE_CONFIG_DIR
  cleanup_test_env
}
```

Register:

```bash
run_test "conf lists the tools of installed capabilities only" test_conf_lists_the_tools_of_installed_capabilities_only
run_test "conf counts a capability being installed and drops one being removed" test_conf_counts_a_capability_being_installed_and_drops_one_being_removed
run_test "conf leaves a file teeup did not write" test_conf_leaves_a_file_teeup_did_not_write
run_test "conf follows MISE_CONFIG_DIR and dry run writes nothing" test_conf_follows_mise_config_dir_and_dry_run_writes_nothing
```

- [ ] **Step 2: Run and see them fail**

Run: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/lib/mise.sh`
Expected: FAIL on the four new tests (`mise_tools_conf_write: command not found`).

- [ ] **Step 3: Implement**

Append to `lib/mise.sh`:

```bash

# The first line of conf.d/teeup.toml: the record that teeup wrote it.
TEEUP_MISE_CONF_MARKER="# teeup mise tools; regenerated by: teeup configure <capability> and teeup update"

# mise_tools_conf_file -> where teeup pins its tools for mise. mise reads
# every conf.d/*.toml in its config directory as part of the global config,
# and MISE_CONFIG_DIR moves that directory as it moves config.toml.
mise_tools_conf_file() {
  printf '%s/conf.d/teeup.toml\n' "${MISE_CONFIG_DIR:-$(user_config_dir)/mise}"
}

# mise_tools_conf_write [--with <capability>] [--without <capability>]
# Writes conf.d/teeup.toml from the lock: one [tools] entry for each mise
# tool of each capability marked installed (TEEUP_SKIP or not: a capability
# skipped after its install still has its links, and an unpinned version is
# one `mise prune` removes). --with counts a capability whose install or
# configure is running before its done marker exists; --without leaves out
# one being removed. The user's config.toml is never edited. With nothing to
# pin, teeup's file is deleted. A file without the marker is not teeup's and
# is left alone.
# 0 written, already current or removed; 1 refused.
mise_tools_conf_write() {
  local with="" without="" file name pair tool version spec body=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --with|--without)
        if [[ $# -lt 2 || -z "$2" ]]; then
          err "mise_tools_conf_write: $1 needs a capability name"
          return 1
        fi
        if [[ "$1" == "--with" ]]; then with="$2"; else without="$2"; fi
        shift 2
        ;;
      *) err "mise_tools_conf_write: unknown argument '$1'"; return 1 ;;
    esac
  done
  file="$(mise_tools_conf_file)"
  if [[ -e "$file" || -L "$file" ]] && ! head -1 "$file" 2>/dev/null | grep -qxF "$TEEUP_MISE_CONF_MARKER"; then
    warn "Keeping $file: it was not written by teeup, so the versions teeup pins are in no mise config and mise prune can remove them. Move it aside, then run: teeup update"
    return 1
  fi
  for name in $(cap_list); do
    if [[ "$name" == "$without" ]]; then continue; fi
    if [[ "$name" != "$with" ]] && ! state_done check "cap-$name"; then continue; fi
    for pair in $(cap_meta_get "$name" mise_tools); do
      tool="${pair%%:*}"
      if ! version="$(tools_lock_version "$tool")"; then
        warn "$name names $tool in mise_tools, but $TEEUP_TOOLS_LOCK has no line for it, so $file leaves it out."
        continue
      fi
      spec="$(tools_lock_spec "$tool")"
      body="$body\"$spec\" = \"$version\""$'\n'
    done
  done
  if [[ -z "$body" ]]; then
    if [[ -e "$file" ]]; then
      if ! run_cmd rm -f "$file"; then
        warn "Could not remove $file. Remove it by hand."
        return 1
      fi
      ok_unless_dry "Removed $file: no capability here uses a tool from mise any more."
    fi
    return 0
  fi
  printf '%s\n%s\n[tools]\n%s' "$TEEUP_MISE_CONF_MARKER" \
    "# The versions come from share/teeup/tools.lock in the teeup checkout." "$body" |
    write_managed_file "$file" "the tool versions teeup pins for mise"
}
```

- [ ] **Step 4: Run and see them pass**

Run: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/lib/mise.sh` and `perl -e 'setpgrp 0,0; exec @ARGV' ./tests/bash32.sh tests/lib/mise.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/mise.sh tests/lib/mise.sh
git commit -m "Write the pinned mise tools to conf.d/teeup.toml"
```

---

### Task 4: Install, link and remove pinned tools

**Files:**
- Modify: `lib/mise.sh` (append after the Task 3 section)
- Modify: `bin/teeup:20` (after `answers_load`)
- Modify: `bootstrap:272` (after `pkg_backend_path`)
- Modify: `tests/helper.sh` (after `lock_version`)
- Test: `tests/lib/mise.sh`, `tests/cli.sh` (before `print_summary`, line 3350)

**Interfaces:**
- Consumes: Tasks 1 and 3; `have`, `run_cmd`, `ok_unless_dry`, `warn`, `log`, `cap_skipped`, `cap_list`, `cap_meta_get`, `state_done`, `pkg_backend_path`, `write_managed_file`.
- Produces:
  - `TEEUP_MISE_TOOL_MARKER="# teeup mise tool; regenerated by: teeup configure"`; `TEEUP_MISE_EXEC_SCRIPT_TOOLS=""` (space-separated tools that get an exec script instead of a symlink; empty until the Mac verification names one).
  - `mise_installs_dir` → `${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/installs`.
  - `local_bin_on_path` → puts `$HOME/.local/bin` first on `PATH` for this process (once).
  - `mise_tool_link_owned <path>` → 0 when `<path>` is a symlink into `mise_installs_dir` or a script whose line 2 is the marker.
  - `mise_tool_link_is <path> <bin>` → 0 when `<path>` already runs `<bin>`.
  - `mise_tool_install <tool> <command>` → 0 linked, already linked, kept a foreign file, or previewed; 1 the command is missing and a warning said why.
  - `mise_tool_remove <tool> <command> [true|false]` → 0 removed or nothing to do; 1 a link or install that should have gone is still there.
  - `mise_tools_apply <capability>` → 0 every tool linked and conf.d written; 1 otherwise. Used by `install` scripts.
  - `mise_tools_repair <capability>` → always 0, warns on a failure; nothing when mise is skipped. Used by `configure` scripts.
  - `mise_tools_sync` → 0 every installed, unskipped capability's tools linked at the lock's versions; 1 otherwise. Used by `teeup update` and the migration.
  - Test helper `mock_mise_tools` (env `MOCK_MISE_FAIL_INSTALL=<tool>`, `MOCK_MISE_FAIL_UNINSTALL=<tool>`).

- [ ] **Step 1: Add the mise mock to `tests/helper.sh`**

After `lock_version`:

```bash
# mock_mise_tools
# A mise that installs pinned tools the way lib/mise.sh asks it to.
# `install <tool>@<version>` creates <installs>/<dir>/<version>/bin, where
# <dir> is the tool with ':' and '/' turned into '-' (as mise names a
# backend's directory); `where` answers from that directory; `which --tool
# <tool>@<version> <command>` makes an executable for <command> there once
# and prints its path; `uninstall` deletes the version. The executable
# answers --version, -V and version with "<command> <version>" and otherwise
# prints "<command> ran: <args>". MOCK_MISE_FAIL_INSTALL=<tool> or
# MOCK_MISE_FAIL_UNINSTALL=<tool> makes that one call fail. Every other call
# succeeds and prints nothing, which is a fresh global config's answer to
# `ls --global`.
mock_mise_tools() {
  mock_command_script mise <<'EOF2'
[ "$1" = "-C" ] && shift 2
root="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/installs"
spec_dir() {
  printf '%s/%s/%s\n' "$root" "$(printf '%s' "${1%@*}" | tr ':/' '--')" "${1##*@}"
}
case "$1" in
  install)
    if [ "${MOCK_MISE_FAIL_INSTALL:-}" = "${2%@*}" ]; then
      echo "mise ERROR failed to install $2" >&2
      exit 1
    fi
    mkdir -p "$(spec_dir "$2")/bin"
    ;;
  where)
    d="$(spec_dir "$2")"
    [ -d "$d" ] || { echo "mise ERROR $2 is not installed" >&2; exit 1; }
    printf '%s\n' "$d"
    ;;
  which)
    d="$(spec_dir "$3")"
    [ -d "$d/bin" ] || exit 1
    if [ ! -x "$d/bin/$4" ]; then
      printf '#!/bin/sh\ncase "$1" in --version|-V|version) echo "%s %s"; exit 0 ;; esac\necho "%s ran: $*"\n' "$4" "${3##*@}" "$4" > "$d/bin/$4"
      chmod +x "$d/bin/$4"
    fi
    printf '%s\n' "$d/bin/$4"
    ;;
  uninstall)
    [ "${MOCK_MISE_FAIL_UNINSTALL:-}" = "${2%@*}" ] && exit 1
    rm -rf "$(spec_dir "$2")"
    ;;
esac
exit 0
EOF2
}
```

- [ ] **Step 2: Write the failing tests**

Add to `tests/lib/mise.sh`:

```bash
test_tool_install_installs_the_pinned_version_then_links_the_which_result() {
  setup
  tools_fixture
  mock_mise_tools
  local link="$TEST_HOME/.local/bin/rg" bin="$TEST_HOME/.local/share/mise/installs/ripgrep/15.2.0/bin/rg" out
  out="$(mise_tool_install ripgrep rg 2>&1)" || { echo "install failed: $out"; return 1; }
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install ripgrep@15.2.0" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / which --tool ripgrep@15.2.0 rg" || return 1
  [[ -L "$link" ]] || { echo "rg must be a symlink"; return 1; }
  assert_equals "$bin" "$(readlink "$link")" || return 1
  assert_equals "rg 15.2.0" "$("$link" --version)" "the link runs the binary itself" || return 1
  assert_contains "$out" "Linked rg to ripgrep 15.2.0 (mise)" || return 1
  : > "$MOCK_LOG"
  out="$(mise_tool_install ripgrep rg 2>&1)"
  assert_contains "$out" "Already linked: rg (ripgrep 15.2.0)" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "install ripgrep" "an installed version is not installed again" || return 1
  cleanup_test_env
}

test_tool_install_follows_a_command_and_a_backend_that_differ_from_the_tool() {
  setup
  tools_fixture
  mock_mise_tools
  mise_tool_install tealdeer tldr >/dev/null 2>&1 || return 1
  mise_tool_install neovim nvim >/dev/null 2>&1 || return 1
  assert_equals "$TEST_HOME/.local/share/mise/installs/tealdeer/1.9.0/bin/tldr" "$(readlink "$TEST_HOME/.local/bin/tldr")" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install aqua:neovim/neovim@0.12.6" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / which --tool aqua:neovim/neovim@0.12.6 nvim" || return 1
  [[ -L "$TEST_HOME/.local/bin/nvim" ]] || { echo "nvim is the link, not neovim"; return 1; }
  [[ ! -e "$TEST_HOME/.local/bin/neovim" && ! -e "$TEST_HOME/.local/bin/tealdeer" ]] || { echo "the tool name is not a command"; return 1; }
  cleanup_test_env
}

test_tool_install_keeps_a_file_or_link_teeup_did_not_write() {
  setup
  tools_fixture
  mock_mise_tools
  mkdir -p "$TEST_HOME/.local/bin"
  printf '#!/bin/sh\necho mine\n' > "$TEST_HOME/.local/bin/rg"
  ln -s /bin/sh "$TEST_HOME/.local/bin/tldr"
  local out rc=0
  out="$(mise_tool_install ripgrep rg 2>&1)" || rc=$?
  assert_success "$rc" "a kept file is the user's choice, not a failure" || return 1
  assert_contains "$out" "Keeping $TEST_HOME/.local/bin/rg: it was not written by teeup" || return 1
  assert_equals "$(printf '#!/bin/sh\necho mine')" "$(cat "$TEST_HOME/.local/bin/rg")" || return 1
  out="$(mise_tool_install tealdeer tldr 2>&1)" || true
  assert_contains "$out" "Keeping $TEST_HOME/.local/bin/tldr" || return 1
  assert_equals "/bin/sh" "$(readlink "$TEST_HOME/.local/bin/tldr")" "a foreign symlink is kept too" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "install" "nothing is installed for a command that stays foreign" || return 1
  cleanup_test_env
}

test_tool_install_repairs_a_link_left_dangling_by_mise_uninstall() {
  setup
  tools_fixture
  mock_mise_tools
  mise_tool_install ripgrep rg >/dev/null 2>&1 || return 1
  rm -rf "$TEST_HOME/.local/share/mise/installs/ripgrep/15.2.0"
  [[ -L "$TEST_HOME/.local/bin/rg" && ! -e "$TEST_HOME/.local/bin/rg" ]] || { echo "fixture: the link must dangle"; return 1; }
  : > "$MOCK_LOG"
  mise_tool_install ripgrep rg >/dev/null 2>&1 || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install ripgrep@15.2.0" || return 1
  [[ -e "$TEST_HOME/.local/bin/rg" ]] || { echo "the link must resolve again"; return 1; }
  cleanup_test_env
}

test_tool_install_relinks_when_the_lock_moves() {
  setup
  tools_fixture
  mock_mise_tools
  mise_tool_install ripgrep rg >/dev/null 2>&1 || return 1
  sed 's/^ripgrep 15.2.0$/ripgrep 15.3.0/' "$TEEUP_TOOLS_LOCK" > "$TEST_HOME/lock.new"
  mv "$TEST_HOME/lock.new" "$TEEUP_TOOLS_LOCK"
  mise_tool_install ripgrep rg >/dev/null 2>&1 || return 1
  assert_equals "$TEST_HOME/.local/share/mise/installs/ripgrep/15.3.0/bin/rg" "$(readlink "$TEST_HOME/.local/bin/rg")" || return 1
  assert_dir_exists "$TEST_HOME/.local/share/mise/installs/ripgrep/15.2.0" "the old version stays for mise prune" || return 1
  cleanup_test_env
}

test_tool_install_without_mise_fails_but_a_dry_run_previews() {
  setup
  tools_fixture
  export TEEUP_TEST_MISSING=mise
  local out rc=0
  out="$(mise_tool_install ripgrep rg 2>&1)" || rc=$?
  assert_equals "1" "$rc" || return 1
  assert_contains "$out" "mise is not on PATH, so ripgrep 15.2.0 was not installed and rg is missing. Run: teeup install mise" || return 1
  rc=0
  out="$(DRY_RUN=true mise_tool_install ripgrep rg 2>&1)" || rc=$?
  assert_success "$rc" "a first bootstrap previews cli-tools before mise exists" || return 1
  assert_contains "$out" "Would execute: mise -C / install ripgrep@15.2.0" || return 1
  assert_contains "$out" "Would link $TEST_HOME/.local/bin/rg to ripgrep 15.2.0 (mise)" || return 1
  [[ ! -e "$TEST_HOME/.local/bin/rg" ]] || { echo "nothing is linked"; return 1; }
  unset TEEUP_TEST_MISSING
  cleanup_test_env
}

test_tool_install_dry_run_installs_and_links_nothing() {
  setup
  tools_fixture
  mock_mise_tools
  local out
  out="$(DRY_RUN=true mise_tool_install ripgrep rg 2>&1)"
  assert_contains "$out" "Would execute: mise -C / install ripgrep@15.2.0" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "mise -C / install" "the install only previews" || return 1
  [[ ! -e "$TEST_HOME/.local/share/mise/installs" && ! -e "$TEST_HOME/.local/bin/rg" ]] || { echo "dry run changed the disk"; return 1; }
  cleanup_test_env
}

test_tool_install_reports_a_failed_install() {
  setup
  tools_fixture
  mock_mise_tools
  local out rc=0
  out="$(MOCK_MISE_FAIL_INSTALL=ripgrep mise_tool_install ripgrep rg 2>&1)" || rc=$?
  assert_equals "1" "$rc" || return 1
  assert_contains "$out" "mise could not install ripgrep 15.2.0, so rg is missing." || return 1
  [[ ! -e "$TEST_HOME/.local/bin/rg" && ! -L "$TEST_HOME/.local/bin/rg" ]] || { echo "no link to a version that is not there"; return 1; }
  cleanup_test_env
}

# A path with a space, a dollar sign and a quote in it, through both the
# symlink and the exec script (the fallback for a tool that cannot run from
# a link).
test_tool_install_writes_a_script_for_a_tool_that_needs_one_under_an_odd_home() {
  setup
  tools_fixture
  mock_mise_tools
  export HOME="$TEST_HOME/h o\$m'e"
  mkdir -p "$HOME"
  TEEUP_MISE_EXEC_SCRIPT_TOOLS="neovim"
  mise_tool_install ripgrep rg >/dev/null 2>&1 || return 1
  assert_equals "rg ran: a b" "$("$HOME/.local/bin/rg" a b)" || return 1
  mise_tool_install neovim nvim >/dev/null 2>&1 || return 1
  local script="$HOME/.local/bin/nvim"
  [[ -f "$script" && ! -L "$script" ]] || { echo "nvim must be a script, not a link"; return 1; }
  assert_equals "$TEEUP_MISE_TOOL_MARKER" "$(sed -n 2p "$script")" || return 1
  assert_equals "nvim ran: x y z" "$("$script" x y z)" || return 1
  mise_tool_link_owned "$script" || { echo "teeup owns its script"; return 1; }
  assert_contains "$(mise_tool_install neovim nvim 2>&1)" "Already linked: nvim" || return 1
  TEEUP_MISE_EXEC_SCRIPT_TOOLS=""
  cleanup_test_env
}

test_tool_remove_deletes_only_a_teeup_link() {
  setup
  tools_fixture
  mock_mise_tools
  mise_tool_install ripgrep rg >/dev/null 2>&1 || return 1
  printf '#!/bin/sh\necho mine\n' > "$TEST_HOME/.local/bin/tldr"
  local out
  out="$(mise_tool_remove ripgrep rg false 2>&1)" || { echo "remove failed: $out"; return 1; }
  [[ ! -e "$TEST_HOME/.local/bin/rg" && ! -L "$TEST_HOME/.local/bin/rg" ]] || { echo "the link must go"; return 1; }
  assert_dir_exists "$TEST_HOME/.local/share/mise/installs/ripgrep/15.2.0" "without packages the install stays" || return 1
  out="$(mise_tool_remove tealdeer tldr false 2>&1)" || return 1
  assert_contains "$out" "Keeping $TEST_HOME/.local/bin/tldr: it was not written by teeup." || return 1
  assert_file_exists "$TEST_HOME/.local/bin/tldr" || return 1
  cleanup_test_env
}

test_tool_remove_with_packages_uninstalls_the_pinned_version() {
  setup
  tools_fixture
  mock_mise_tools
  mise_tool_install ripgrep rg >/dev/null 2>&1 || return 1
  local out rc=0
  out="$(DRY_RUN=true mise_tool_remove ripgrep rg true 2>&1)" || rc=$?
  assert_contains "$out" "Would execute: mise -C / uninstall ripgrep@15.2.0" || return 1
  [[ -L "$TEST_HOME/.local/bin/rg" ]] || { echo "dry run removed the link"; return 1; }
  mise_tool_remove ripgrep rg true >/dev/null 2>&1 || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / uninstall ripgrep@15.2.0" || return 1
  [[ ! -e "$TEST_HOME/.local/share/mise/installs/ripgrep/15.2.0" ]] || { echo "the pinned version must go"; return 1; }
  rc=0
  mise_tool_install ripgrep rg >/dev/null 2>&1
  out="$(MOCK_MISE_FAIL_UNINSTALL=ripgrep mise_tool_remove ripgrep rg true 2>&1)" || rc=$?
  assert_equals "1" "$rc" || return 1
  assert_contains "$out" "Run: mise uninstall ripgrep@15.2.0" || return 1
  cleanup_test_env
}

test_apply_installs_every_pair_and_writes_the_conf() {
  setup
  tools_fixture
  mock_mise_tools
  mise_tools_apply search >/dev/null 2>&1 || { echo "apply failed"; return 1; }
  [[ -L "$TEST_HOME/.local/bin/rg" && -L "$TEST_HOME/.local/bin/tldr" ]] || { echo "both commands are linked"; return 1; }
  assert_contains "$(cat "$CONF")" '"tealdeer" = "1.9.0"' "the capability being installed is pinned" || return 1
  assert_not_contains "$(cat "$CONF")" "neovim" || return 1
  cleanup_test_env
}

test_apply_finds_a_mise_the_package_manager_just_installed() {
  setup
  tools_fixture
  mock_mise_tools
  mkdir -p "$TEEUP_PKG_PREFIX/bin"
  mv "$MOCK_BIN/mise" "$TEEUP_PKG_PREFIX/bin/mise"
  hide_host_commands mise
  mise_tools_apply search >/dev/null 2>&1 || { echo "a mise under the package prefix must be found"; return 1; }
  [[ -L "$TEST_HOME/.local/bin/rg" ]] || return 1
  cleanup_test_env
}

test_apply_refuses_when_mise_is_skipped() {
  setup
  tools_fixture
  mock_mise_tools
  local out rc=0
  out="$(TEEUP_SKIP=mise mise_tools_apply search 2>&1)" || rc=$?
  assert_equals "1" "$rc" || return 1
  assert_contains "$out" "mise is skipped on this machine (TEEUP_SKIP), so teeup does not install rg tldr for search." || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "install" || return 1
  out="$(TEEUP_SKIP=mise mise_tools_repair search 2>&1)" || { echo "repair never fails"; return 1; }
  assert_equals "" "$out" "configure says nothing more once install said it" || return 1
  cleanup_test_env
}

test_repair_warns_but_succeeds() {
  setup
  tools_fixture
  mock_mise_tools
  local out rc=0
  out="$(MOCK_MISE_FAIL_INSTALL=tealdeer mise_tools_repair search 2>&1)" || rc=$?
  assert_success "$rc" "configure carries on" || return 1
  assert_contains "$out" "Some of search's tools from mise are missing or not linked" || return 1
  assert_contains "$out" "run: teeup configure search" || return 1
  [[ -L "$TEST_HOME/.local/bin/rg" ]] || { echo "the other tool is still linked"; return 1; }
  cleanup_test_env
}

test_sync_links_every_installed_unskipped_capability() {
  setup
  tools_fixture
  mock_mise_tools
  state_done mark cap-search
  state_done mark cap-editor
  mise_tools_sync >/dev/null 2>&1 || { echo "sync failed"; return 1; }
  [[ -L "$TEST_HOME/.local/bin/rg" && -L "$TEST_HOME/.local/bin/tldr" && -L "$TEST_HOME/.local/bin/nvim" ]] || return 1
  rm -f "$TEST_HOME/.local/bin/nvim"
  TEEUP_SKIP=editor mise_tools_sync >/dev/null 2>&1 || return 1
  [[ ! -e "$TEST_HOME/.local/bin/nvim" ]] || { echo "a skipped capability is left as it is"; return 1; }
  assert_contains "$(cat "$CONF")" "aqua:neovim/neovim" "its pin stays, so mise prune keeps its install" || return 1
  local out rc=0
  out="$(TEEUP_TEST_MISSING=mise mise_tools_sync 2>&1)" || rc=$?
  assert_equals "1" "$rc" || return 1
  assert_equals "1" "$(printf '%s\n' "$out" | grep -c 'mise is not on PATH')" "one warning, not one per tool" || return 1
  cleanup_test_env
}

test_every_mise_call_runs_from_root() {
  setup
  tools_fixture
  mock_mise_tools
  state_done mark cap-search
  mise_tools_apply search >/dev/null 2>&1
  mise_tools_sync >/dev/null 2>&1
  mise_tool_remove ripgrep rg true >/dev/null 2>&1
  local stray
  stray="$(grep '^mise ' "$MOCK_LOG" | grep -v '^mise -C / ' || true)"
  assert_equals "" "$stray" "a project mise.toml in the current directory must not redirect a call" || return 1
  cleanup_test_env
}

test_local_bin_on_path_puts_it_first_once() {
  setup
  PATH="/usr/bin:/bin"
  local_bin_on_path
  assert_equals "$HOME/.local/bin:/usr/bin:/bin" "$PATH" || return 1
  local_bin_on_path
  assert_equals "$HOME/.local/bin:/usr/bin:/bin" "$PATH" "a second call adds nothing" || return 1
  cleanup_test_env
}
```

Register them before `print_summary`:

```bash
run_test "tool install installs the pinned version then links the which result" test_tool_install_installs_the_pinned_version_then_links_the_which_result
run_test "tool install follows a command and a backend that differ from the tool" test_tool_install_follows_a_command_and_a_backend_that_differ_from_the_tool
run_test "tool install keeps a file or link teeup did not write" test_tool_install_keeps_a_file_or_link_teeup_did_not_write
run_test "tool install repairs a link left dangling by mise uninstall" test_tool_install_repairs_a_link_left_dangling_by_mise_uninstall
run_test "tool install relinks when the lock moves" test_tool_install_relinks_when_the_lock_moves
run_test "tool install without mise fails but a dry run previews" test_tool_install_without_mise_fails_but_a_dry_run_previews
run_test "tool install dry run installs and links nothing" test_tool_install_dry_run_installs_and_links_nothing
run_test "tool install reports a failed install" test_tool_install_reports_a_failed_install
run_test "tool install writes a script for a tool that needs one, under an odd home" test_tool_install_writes_a_script_for_a_tool_that_needs_one_under_an_odd_home
run_test "tool remove deletes only a teeup link" test_tool_remove_deletes_only_a_teeup_link
run_test "tool remove with packages uninstalls the pinned version" test_tool_remove_with_packages_uninstalls_the_pinned_version
run_test "apply installs every pair and writes the conf" test_apply_installs_every_pair_and_writes_the_conf
run_test "apply finds a mise the package manager just installed" test_apply_finds_a_mise_the_package_manager_just_installed
run_test "apply refuses when mise is skipped" test_apply_refuses_when_mise_is_skipped
run_test "repair warns but succeeds" test_repair_warns_but_succeeds
run_test "sync links every installed, unskipped capability" test_sync_links_every_installed_unskipped_capability
run_test "every mise call runs from /" test_every_mise_call_runs_from_root
run_test "local_bin_on_path puts it first once" test_local_bin_on_path_puts_it_first_once
```

Add to `tests/cli.sh` (before `print_summary`) and register it:

```bash
# A capability script must see the links mise_tool_install writes, before
# the shell layer exists: a first bootstrap's Terminal has no ~/.local/bin.
test_capability_scripts_see_local_bin_first() {
  setup
  cat > "$TEEUP_CAPS_DIR/alpha/configure" <<'EOF2'
#!/usr/bin/env bash
echo "first:${PATH%%:*}"
EOF2
  local out
  out="$("$TEEUP" configure alpha)"
  assert_contains "$out" "first:$TEST_HOME/.local/bin" || return 1
  cleanup_test_env
}
```

```bash
run_test "capability scripts see ~/.local/bin first" test_capability_scripts_see_local_bin_first
```

- [ ] **Step 3: Run and see them fail**

Run: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/lib/mise.sh` and `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/cli.sh`
Expected: FAIL on every new test (`mise_tool_install: command not found`, and `first:$MOCK_BIN` in cli.sh).

- [ ] **Step 4: Implement in `lib/mise.sh`**

Append:

```bash

# The second line of a script teeup writes in place of a link (below).
TEEUP_MISE_TOOL_MARKER="# teeup mise tool; regenerated by: teeup configure"

# Tools whose command must be a script that execs the binary rather than a
# symlink: a tool that finds its own files next to the path it was started
# as would look for them in ~/.local/bin. Empty until the spec's Mac
# verification names one; adding the tool here is the whole change. bash
# startup for the script costs about 1 ms.
TEEUP_MISE_EXEC_SCRIPT_TOOLS="${TEEUP_MISE_EXEC_SCRIPT_TOOLS:-}"

# mise_installs_dir -> where mise keeps installed versions, resolved the way
# mise resolves its data root.
mise_installs_dir() {
  printf '%s/installs\n' "${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}"
}

# local_bin_on_path: puts ~/.local/bin first on PATH for this process, as
# capabilities/zsh/default/env does for every shell. bin/teeup and bootstrap
# call it so a capability script sees the links mise_tool_install writes
# even from a Terminal the shell layer has not set up yet.
local_bin_on_path() {
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH"; export PATH ;;
  esac
}

# _mise_plain_names <caller> <name...>: every name is a plain tool or
# command name, or an error names the caller and the name.
_mise_plain_names() {
  local caller="$1" t
  shift
  for t in "$@"; do
    if ! [[ "$t" =~ ^[A-Za-z0-9][A-Za-z0-9_.+-]*$ ]]; then
      err "$caller: '$t' is not a plain tool or command name"
      return 1
    fi
  done
}

# _mise_tool_wants_script <tool> -> 0 when <tool> is in
# TEEUP_MISE_EXEC_SCRIPT_TOOLS.
_mise_tool_wants_script() {
  case " $TEEUP_MISE_EXEC_SCRIPT_TOOLS " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# _mise_tool_script <bin> -> the exec script for <bin>, single-quoted for sh.
_mise_tool_script() {
  local quoted
  quoted="$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
  printf '#!/bin/sh\n%s\nexec '\''%s'\'' "$@"\n' "$TEEUP_MISE_TOOL_MARKER" "$quoted"
}

# mise_tool_link_owned <path> -> 0 when teeup wrote <path>: a symlink into
# mise's installs directory (dangling or not), or a script carrying the
# marker on its second line. Anything else at the path is the user's.
mise_tool_link_owned() {
  local path="$1" installs target
  installs="$(mise_installs_dir)/"
  if [[ -L "$path" ]]; then
    target="$(readlink "$path")"
    case "$target" in
      "$installs"*) return 0 ;;
    esac
    return 1
  fi
  if [[ -f "$path" ]] && sed -n 2p "$path" 2>/dev/null | grep -qxF "$TEEUP_MISE_TOOL_MARKER"; then
    return 0
  fi
  return 1
}

# mise_tool_link_is <path> <bin> -> 0 when <path> already runs <bin>.
mise_tool_link_is() {
  local path="$1" bin="$2"
  if [[ -L "$path" ]]; then
    if [[ "$(readlink "$path")" == "$bin" ]]; then return 0; fi
    return 1
  fi
  if [[ -f "$path" && "$(cat "$path")" == "$(_mise_tool_script "$bin")" ]]; then
    return 0
  fi
  return 1
}

# mise_tool_install <tool> <command>
# Installs <tool> at the version share/teeup/tools.lock pins (only when that
# version is not installed yet), asks mise where its <command> is, and points
# ~/.local/bin/<command> at it. A call then runs the binary directly, with no
# mise process in between. A file at the link path that teeup did not create
# is kept, with a warning, as mise_wrapper_write does. The previous version
# stays installed; `mise prune` removes it once nothing pins it.
# TEEUP_CAP names the capability in the repair hints when it is set.
# 0 linked, already linked, kept, or previewed; 1 <command> is missing.
mise_tool_install() {
  local tool="$1" command="$2" version spec link bin owner
  _mise_plain_names mise_tool_install "$tool" "$command" || return 1
  if ! version="$(tools_lock_version "$tool")"; then
    err "mise_tool_install: $tool has no line in $TEEUP_TOOLS_LOCK"
    return 1
  fi
  spec="$(tools_lock_spec "$tool")"
  link="$HOME/.local/bin/$command"
  owner="${TEEUP_CAP:-<capability>}"
  if [[ -e "$link" || -L "$link" ]] && ! mise_tool_link_owned "$link"; then
    warn "Keeping $link: it was not written by teeup, so $command is not the pinned $tool $version. Remove it, then run: teeup configure $owner"
    return 0
  fi
  if ! have mise; then
    if [[ "$DRY_RUN" == "true" ]]; then
      run_cmd mise -C / install "$spec@$version"
      printf "%b %s\n" "🔍" "[DRY-RUN] Would link $link to $tool $version (mise)"
      return 0
    fi
    warn "mise is not on PATH, so $tool $version was not installed and $command is missing. Run: teeup install mise, then: teeup configure $owner"
    return 1
  fi
  if ! mise -C / where "$spec@$version" >/dev/null 2>&1; then
    if ! run_cmd mise -C / install "$spec@$version"; then
      warn "mise could not install $tool $version, so $command is missing. Fix the cause above, then run: teeup configure $owner"
      return 1
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
      printf "%b %s\n" "🔍" "[DRY-RUN] Would link $link to $tool $version (mise)"
      return 0
    fi
  fi
  if ! bin="$(mise -C / which --tool "$spec@$version" "$command" 2>/dev/null)" || [[ -z "$bin" || ! -x "$bin" ]]; then
    warn "mise installed $tool $version, but it has no $command, so $link was not written."
    return 1
  fi
  if mise_tool_link_is "$link" "$bin"; then
    log "Already linked: $command ($tool $version)"
    return 0
  fi
  if [[ ! -d "$HOME/.local/bin" ]]; then
    run_cmd mkdir -p "$HOME/.local/bin" || return 1
  fi
  if _mise_tool_wants_script "$tool"; then
    # write_managed_file refuses to write through a symlink.
    if [[ -L "$link" ]]; then
      run_cmd rm -f "$link" || return 1
    fi
    _mise_tool_script "$bin" | write_managed_file "$link" "$command, which runs $tool $version" || return 1
    if [[ "$DRY_RUN" != "true" ]]; then
      chmod 755 "$link"
    fi
  elif ! run_cmd ln -sfn "$bin" "$link"; then
    warn "Could not link $link to $bin. Fix the permissions of $HOME/.local/bin, then run: teeup configure $owner"
    return 1
  fi
  ok_unless_dry "Linked $command to $tool $version (mise)"
}

# mise_tool_remove <tool> <command> [true|false]
# Removes ~/.local/bin/<command> when teeup wrote it; a foreign file stays,
# with a warning. With true (`teeup remove`, `teeup uninstall --packages`)
# it also uninstalls the pinned version. The conf.d file is the caller's to
# rewrite (cap_remove does it once per capability).
# 0 removed or nothing to do; 1 something that should be gone is still there.
mise_tool_remove() {
  local tool="$1" command="$2" with_packages="${3:-false}" link version spec
  _mise_plain_names mise_tool_remove "$tool" "$command" || return 1
  link="$HOME/.local/bin/$command"
  if [[ -e "$link" || -L "$link" ]]; then
    if mise_tool_link_owned "$link"; then
      if ! run_cmd rm -f "$link"; then
        warn "Could not remove $link. Fix its permissions and try again."
        return 1
      fi
      if [[ "$DRY_RUN" != "true" && ( -e "$link" || -L "$link" ) ]]; then
        warn "$link is still there. Remove it and try again."
        return 1
      fi
      ok_unless_dry "Removed the link: $command"
    else
      warn "Keeping $link: it was not written by teeup."
    fi
  fi
  if [[ "$with_packages" != "true" ]]; then
    return 0
  fi
  if ! version="$(tools_lock_version "$tool")"; then
    log "$TEEUP_TOOLS_LOCK has no line for $tool, so no pinned version of it is uninstalled."
    return 0
  fi
  spec="$(tools_lock_spec "$tool")"
  if ! have mise; then
    if [[ "$DRY_RUN" == "true" ]]; then
      run_cmd mise -C / uninstall "$spec@$version"
      return 0
    fi
    warn "mise is not on PATH, so $tool $version stays installed. Once mise is back, run: mise uninstall $spec@$version"
    return 1
  fi
  if ! mise -C / where "$spec@$version" >/dev/null 2>&1; then
    log "Not installed through mise, so nothing to uninstall: $tool $version"
    return 0
  fi
  if ! run_cmd mise -C / uninstall "$spec@$version"; then
    warn "Could not uninstall $tool $version through mise. Run: mise uninstall $spec@$version"
    return 1
  fi
  ok_unless_dry "Uninstalled $tool $version (mise)"
}

# mise_tools_apply <capability>
# What a capability's install runs for its mise_tools pairs: install and
# link each one, then rewrite conf.d with this capability counted as
# installed. Installing first means a version that fails to download is
# never pinned, so `mise activate` does not warn about it in every shell. A
# mise the package manager installed earlier in this run is found even
# before the shell layer puts its prefix on PATH.
# 0 every tool linked; 1 otherwise (the warnings say which).
mise_tools_apply() {
  local cap="$1" pair cmds="" rc=0
  for pair in $(cap_meta_get "$cap" mise_tools); do
    cmds="${cmds:+$cmds }${pair#*:}"
  done
  if [[ -z "$cmds" ]]; then
    return 0
  fi
  if cap_skipped mise; then
    warn "mise is skipped on this machine (TEEUP_SKIP), so teeup does not install $cmds for $cap. Install them another way, or take mise out of TEEUP_SKIP."
    return 1
  fi
  pkg_backend_path
  for pair in $(cap_meta_get "$cap" mise_tools); do
    if ! TEEUP_CAP="$cap" mise_tool_install "${pair%%:*}" "${pair#*:}"; then
      rc=1
    fi
  done
  if ! mise_tools_conf_write --with "$cap"; then
    rc=1
  fi
  return $rc
}

# mise_tools_repair <capability>
# What a capability's configure runs: `teeup configure <cap>` is the repair
# path for a missing pinned version or a broken link. A failure is a warning,
# so the rest of configure still runs. Silent when mise is skipped: install
# already said so.
mise_tools_repair() {
  local cap="$1"
  if cap_skipped mise; then
    return 0
  fi
  if ! mise_tools_apply "$cap"; then
    warn "Some of $cap's tools from mise are missing or not linked (the lines above say why). Fix that, then run: teeup configure $cap"
  fi
  return 0
}

# mise_tools_sync
# `teeup update`'s pinned-tools step and the migration's whole job: every
# installed, unskipped capability's tools installed and linked at the
# versions the lock names now, lazy capabilities included (update never runs
# their configure). A tool whose pin changed gets the new version; the old
# one stays for `mise prune`. conf.d is rewritten last.
# 0 everything linked or nothing to do; 1 otherwise.
mise_tools_sync() {
  local name pair rc=0 any=false
  if cap_skipped mise; then
    log "mise is skipped on this machine (TEEUP_SKIP), so the tools teeup pins are left as they are."
    return 0
  fi
  for name in $(cap_list); do
    if state_done check "cap-$name" && ! cap_skipped "$name" && [[ -n "$(cap_meta_get "$name" mise_tools)" ]]; then
      any=true
    fi
  done
  if [[ "$any" != "true" ]]; then
    mise_tools_conf_write
    return $?
  fi
  pkg_backend_path
  if [[ "$DRY_RUN" != "true" ]] && ! have mise; then
    warn "mise is not on PATH, so the tools teeup pins were not checked. Run: teeup install mise, then: teeup update"
    return 1
  fi
  for name in $(cap_list); do
    if ! state_done check "cap-$name"; then continue; fi
    if cap_skipped "$name"; then
      log "Skipping $name's tools from mise (TEEUP_SKIP)"
      continue
    fi
    for pair in $(cap_meta_get "$name" mise_tools); do
      if ! TEEUP_CAP="$name" mise_tool_install "${pair%%:*}" "${pair#*:}"; then
        rc=1
      fi
    done
  done
  if ! mise_tools_conf_write; then
    rc=1
  fi
  return $rc
}
```

- [ ] **Step 5: Put `~/.local/bin` first in `bin/teeup` and `bootstrap`**

In `bin/teeup`, replace:

```bash
source "$TEEUP_PATH/lib/all.sh"
answers_load
```

with:

```bash
source "$TEEUP_PATH/lib/all.sh"
answers_load
# The links mise_tool_install writes must win over an older package-manager
# copy here too, as they do in every shell the zsh layer starts.
local_bin_on_path
```

In `bootstrap`, replace:

```bash
run_capability package-manager || { rc=$?; ui_rc_or_exit $rc || true; die "Core capability package-manager failed. Fix the cause and re-run ./bootstrap."; }
pkg_backend_path
```

with:

```bash
run_capability package-manager || { rc=$?; ui_rc_or_exit $rc || true; die "Core capability package-manager failed. Fix the cause and re-run ./bootstrap."; }
pkg_backend_path
# ~/.local/bin before the package manager's directories, as in every teeup
# shell: git/configure must see the delta that cli-tools linked there.
local_bin_on_path
```

- [ ] **Step 6: Run and see them pass**

Run: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/lib/mise.sh`, `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/cli.sh`, `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/bootstrap.sh`, then the bash 3.2 pass for all three and the full `./tests/run.sh`.
Expected: PASS. If an existing test fails because `~/.local/bin` is now on `PATH` inside `bin/teeup`, that test assumed a command there stayed invisible to teeup; read it before changing anything, and change the test only when the new behaviour matches the shell layer's own `PATH` order.

- [ ] **Step 7: Commit**

```bash
git add lib/mise.sh bin/teeup bootstrap tests/helper.sh tests/lib/mise.sh tests/cli.sh
git commit -m "Install and link pinned tools through mise"
```

---

### Task 5: Install mise before the capabilities that use it

**Files:**
- Modify: `capabilities/core.list`
- Modify: `capabilities/{cli-tools,git,starship,neovim,tmux,herdr,ollama}/capability` (`requires=` line, line 4)
- Modify: `capabilities/git/configure:337`, `capabilities/mise/configure:12-16`
- Modify: `setup()` of `tests/capabilities/{cli-tools,git,starship,neovim,tmux,herdr,ollama,ssh,github,zed,vscode,emacs}.sh`; `tests/bootstrap.sh:75-85` (its mise mock)
- Test: `tests/lib/capability.sh`

**Interfaces:**
- Consumes: `mock_mise_tools` (Task 4), `cap_tier_list`, `cap_meta_get`.
- Produces: the new core order; `requires` containing `mise` for all seven capabilities.

- [ ] **Step 1: Write the failing test**

Add to `tests/lib/capability.sh` and register it:

```bash
# A first bootstrap installs core.list top to bottom, so mise must come before
# every capability that installs a tool through it, and every entry's
# requires must already be above it.
test_shipped_core_list_installs_mise_before_its_users() {
  setup
  TEEUP_CAPS_DIR="$TEEUP_PATH/capabilities"
  local seen=" " name r pos=0 mise_pos=""
  for name in $(cap_tier_list core); do
    pos=$((pos + 1))
    for r in $(cap_meta_get "$name" requires); do
      case "$seen" in
        *" $r "*) ;;
        *) echo "$name requires $r, which core.list puts later"; return 1 ;;
      esac
    done
    if [[ "$name" == "mise" ]]; then mise_pos="$pos"; fi
    case " zsh starship cli-tools git " in
      *" $name "*)
        [[ -n "$mise_pos" ]] || { echo "$name comes before mise in core.list"; return 1; }
        ;;
    esac
    seen="$seen$name "
  done
  for name in cli-tools git starship neovim tmux herdr ollama; do
    case " $(cap_meta_get "$name" requires) " in
      *" mise "*) ;;
      *) echo "$name does not require mise"; return 1 ;;
    esac
  done
  cleanup_test_env
}
```

```bash
run_test "shipped core.list installs mise before its users" test_shipped_core_list_installs_mise_before_its_users
```

- [ ] **Step 2: Run and see it fail**

Run: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/lib/capability.sh`
Expected: FAIL with `zsh comes before mise in core.list`.

- [ ] **Step 3: Reorder and require**

`capabilities/core.list` becomes:

```text
# Core tier: what every terminal session needs. Ordered; each entry's
# requires= must already be satisfied by the entries above it. mise comes
# right after teeup-runtime: it needs only the package manager, and zsh,
# starship, cli-tools and git install their user tools through it (#112).
xcode-clt
ca-bundle
package-manager
teeup-runtime
mise
dev-dirs
zsh
starship
cli-tools
secrets
git
ssh
github
wezterm
fonts
aerospace
keyboard
macos-defaults
theme
terminal-app
```

Change the `requires=` line of each capability:

| File | New line |
|---|---|
| `capabilities/cli-tools/capability` | `requires="package-manager mise"` |
| `capabilities/git/capability` | `requires="dev-dirs cli-tools mise"` |
| `capabilities/starship/capability` | `requires="zsh mise"` |
| `capabilities/neovim/capability` | `requires="package-manager git cli-tools mise"` |
| `capabilities/tmux/capability` | `requires="package-manager mise"` |
| `capabilities/herdr/capability` | `requires="package-manager mise"` |
| `capabilities/ollama/capability` | `requires="package-manager mise"` |

In `capabilities/git/configure`, replace the last line:

```bash
log "pre-commit is installed by the mise capability, later in the core list."
```

with:

```bash
log "pre-commit is installed by the mise capability, which runs before git in the core list."
```

In `capabilities/mise/configure`, replace:

```bash
# pre-commit lives here, not in the git capability: it is a mise-managed tool,
# and git runs before mise in the core list. mise_ensure_global (lib/mise.sh)
```

with:

```bash
# pre-commit lives here, not in the git capability: it is a mise-managed tool
# the global config requests, unlike git's pinned tools. mise_ensure_global (lib/mise.sh)
```

- [ ] **Step 4: Keep the host's mise out of the suites that now reach the mise capability**

`requires=mise` makes a real `teeup install starship` (and cli-tools, git, ollama, and everything that requires them) run the mise capability, whose configure calls `mise -C / use -g pre-commit`. Add this line as the last line of `setup()` in each of `tests/capabilities/cli-tools.sh`, `git.sh`, `starship.sh`, `neovim.sh`, `tmux.sh`, `herdr.sh`, `ollama.sh`, `ssh.sh`, `github.sh`, `zed.sh`, `vscode.sh`, `emacs.sh`:

```bash
  # Nothing in this suite may reach the host's mise (Task 5, #112).
  mock_mise_tools
```

In `tests/bootstrap.sh`, replace the block:

```bash
  # mise capability: `mise ls --global` is a read, so DRY_RUN does not cover
  # it. Succeeding with no output is the fresh-machine answer: the global
  # mise.toml asks for no tools yet.
  mock_command_script mise <<'EOF2'
[ "$1" = "-C" ] && shift 2
case "$1 ${2:-}" in
  "ls --global") : ;;
  *) : ;;
esac
exit 0
EOF2
```

with:

```bash
  # mise capability: `mise ls --global` is a read, so DRY_RUN does not cover
  # it, and mock_mise_tools answers it with nothing, the fresh-machine
  # answer. The same mock installs and links the pinned user tools.
  mock_mise_tools
```

Then list any suite that installs or configures one of these capabilities without the mock:

```bash
grep -L 'mock_mise_tools' $(grep -lE '(install|configure) (cli-tools|git|starship|neovim|tmux|herdr|ollama|ssh|github|zed|vscode|emacs)|"\$BOOT"' tests/*.sh tests/capabilities/*.sh tests/lib/*.sh)
```

Expected: only `tests/lib/*.sh` files whose tests use fixture capability trees (`TEEUP_CAPS_DIR="$TEST_HOME/caps"`). Add `mock_mise_tools` to any other file it prints.

- [ ] **Step 5: Run and see it pass**

Run: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/lib/capability.sh`, each suite edited in Step 4, `tests/bootstrap.sh`, their bash 3.2 pass, then the full `./tests/run.sh`.
Expected: PASS. If a test in `ssh.sh`, `github.sh`, `zed.sh`, `vscode.sh` or `emacs.sh` fails because it expects no `mise` on `PATH`, remove `mock_mise_tools` from that suite's `setup` and call it at the top of each test in that suite that installs or configures cli-tools, git or the capability itself with `DRY_RUN=false`.

- [ ] **Step 6: Commit**

```bash
git add capabilities tests
git commit -m "Install mise before the capabilities that use it"
```

---

### Task 6: Remove mise tools with their capability

**Files:**
- Modify: `lib/capability.sh:322-381` (`cap_remove` and its comment)
- Modify: `bin/teeup` (`cmd_remove`'s `2)` message, about line 220)
- Modify: `lib/uninstall.sh:725-834` (`_uninstall_remove_one`, `uninstall_capabilities`; new `_uninstall_mise_specs` above `_uninstall_remove_one`)
- Test: `tests/lib/capability.sh`, `tests/lib/uninstall.sh`, `tests/cli.sh:809-821`

**Interfaces:**
- Consumes: `mise_tool_remove`, `mise_tools_conf_write`, `mise_tools_conf_file`, `tools_lock_version`, `tools_lock_spec` (Tasks 1-4).
- Produces: `cap_remove` returns 2 only with no remove script, packages, casks **or mise tools**; `_uninstall_mise_specs <cap>` → `<spec>@<version> ...` installed through mise; `TEEUP_COLLECTED_MISE`; the uninstall ledger lines `<cap>'s links in <dir>: <cmds>`, `<cap>'s mise tools: <specs>`, kept `mise tools: <specs>. Remove them later with: mise uninstall <specs>`, removed `the pinned tool list teeup wrote for mise (<file>)`.

- [ ] **Step 1: Write the failing tests**

`tests/lib/capability.sh` (reuses `tools_fixture` and `make_tool_cap` from Task 2):

```bash
test_cap_remove_takes_the_links_and_with_packages_the_pinned_installs() {
  setup
  tools_fixture
  mock_mise_tools
  make_tool_cap search "ripgrep:rg"
  state_done mark cap-search
  mise_tools_apply search >/dev/null 2>&1
  local link="$TEST_HOME/.local/bin/rg" conf="$TEST_HOME/.config/mise/conf.d/teeup.toml" rc=0
  [[ -L "$link" && -f "$conf" ]] || { echo "fixture: rg is linked and pinned"; return 1; }
  cap_remove search false >/dev/null 2>&1 || rc=$?
  assert_success "$rc" "a capability with only mise tools has something to undo" || return 1
  [[ ! -e "$link" && ! -L "$link" ]] || { echo "the link goes"; return 1; }
  [[ ! -e "$conf" ]] || { echo "nothing is pinned any more, so the conf.d file goes"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "uninstall" "without packages the install stays" || return 1
  state_done check cap-search && { echo "the marker is cleared"; return 1; }
  state_done mark cap-search
  mise_tools_apply search >/dev/null 2>&1
  cap_remove search true >/dev/null 2>&1 || { echo "remove with packages failed"; return 1; }
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / uninstall ripgrep@15.2.0" || return 1
  cleanup_test_env
}

test_cap_remove_keeps_the_marker_when_a_mise_uninstall_fails() {
  setup
  tools_fixture
  mock_mise_tools
  make_tool_cap search "ripgrep:rg"
  state_done mark cap-search
  mise_tools_apply search >/dev/null 2>&1
  local rc=0
  MOCK_MISE_FAIL_UNINSTALL=ripgrep cap_remove search true >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" || return 1
  state_done check cap-search || { echo "a retry must still find it"; return 1; }
  cleanup_test_env
}
```

`tests/lib/uninstall.sh` (after `make_cap`, add a helper; then the tests):

```bash
# tool_cap_fixture: mise and a capability with one pinned tool, both marked
# installed, the tool linked.
tool_cap_fixture() {
  mock_mise_tools
  TEEUP_TOOLS_LOCK="$TEST_HOME/tools.lock"
  printf 'ripgrep 15.2.0\n' > "$TEEUP_TOOLS_LOCK"
  make_cap mise core
  make_cap search lazy "mise"
  printf 'mise_tools="ripgrep:rg"\n' >> "$TEEUP_CAPS_DIR/search/capability"
  state_done mark cap-mise
  state_done mark cap-search
  mise_tools_apply search >/dev/null 2>&1
}

test_capabilities_unlink_mise_tools_and_name_the_mise_uninstall_to_run() {
  setup
  tool_cap_fixture
  local conf="$TEST_HOME/.config/mise/conf.d/teeup.toml" fix
  uninstall_capabilities >/dev/null 2>&1
  [[ ! -e "$TEST_HOME/.local/bin/rg" && ! -L "$TEST_HOME/.local/bin/rg" ]] || { echo "the link goes"; return 1; }
  [[ ! -e "$conf" ]] || { echo "the conf.d file goes"; return 1; }
  assert_contains "$_UNINSTALL_REMOVED" "search's links in $TEST_HOME/.local/bin: rg" || return 1
  assert_contains "$_UNINSTALL_REMOVED" "the pinned tool list teeup wrote for mise ($conf)" || return 1
  assert_contains "$_UNINSTALL_KEPT" "mise tools: ripgrep@15.2.0. Remove them later with: mise uninstall ripgrep@15.2.0" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "mise -C / uninstall" "kept unless asked" || return 1
  uninstall_clean || return 1
  while IFS= read -r fix; do
    case "$fix" in *"mise uninstall"*) run_fix "${fix##*: }" || { echo "the printed fix failed: $fix"; return 1; } ;; esac
  done <<EOF2
$_UNINSTALL_KEPT
EOF2
  [[ ! -e "$TEST_HOME/.local/share/mise/installs/ripgrep/15.2.0" ]] || { echo "the printed fix removes the install"; return 1; }
  cleanup_test_env
}

test_capabilities_uninstall_mise_tools_when_asked() {
  setup
  tool_cap_fixture
  _UNINSTALL_PACKAGES=true
  uninstall_capabilities >/dev/null 2>&1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / uninstall ripgrep@15.2.0" || return 1
  assert_contains "$_UNINSTALL_REMOVED" "search's mise tools: ripgrep@15.2.0" || return 1
  assert_not_contains "$_UNINSTALL_KEPT" "mise uninstall" || return 1
  cleanup_test_env
}
```

Register in their files:

```bash
run_test "cap_remove takes the links and, with packages, the pinned installs" test_cap_remove_takes_the_links_and_with_packages_the_pinned_installs
run_test "cap_remove keeps the marker when a mise uninstall fails" test_cap_remove_keeps_the_marker_when_a_mise_uninstall_fails
```

```bash
run_test "capabilities unlink mise tools and name the mise uninstall to run" test_capabilities_unlink_mise_tools_and_name_the_mise_uninstall_to_run
run_test "capabilities uninstall mise tools when asked" test_capabilities_uninstall_mise_tools_when_asked
```

In `tests/cli.sh` `test_remove_dies_when_nothing_can_be_undone`, change the expected text:

```bash
  assert_contains "$out" "widget ships no remove script and installs no packages, casks or mise tools that teeup tracks" || return 1
```

- [ ] **Step 2: Run and see them fail**

Run: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/lib/capability.sh`, `tests/lib/uninstall.sh`, `tests/cli.sh` (each through `perl -e 'setpgrp 0,0; exec @ARGV' bash`).
Expected: FAIL (cap_remove returns 2 for `search`; the cli message differs).

- [ ] **Step 3: Implement `cap_remove`**

Replace the comment line:

```bash
#   2  nothing to undo: no remove script, and no packages or casks named.
```

with:

```bash
#   2  nothing to undo: no remove script, and no packages, casks or mise
#      tools named.
```

Replace the head of `cap_remove`:

```bash
cap_remove() {
  local target="$1" with_packages="$2" cask pkg failed=0 pkgs casks_meta has_remove=false
  pkgs="$(cap_meta_get "$target" packages)"
  casks_meta="$(cap_meta_get "$target" casks)"
  [[ -f "$(cap_dir "$target")/remove" ]] && has_remove=true
  TEEUP_CAP_NA=false
  if [[ "$has_remove" != "true" && -z "$pkgs" && -z "$casks_meta" ]]; then
    return 2
  fi
```

with:

```bash
cap_remove() {
  local target="$1" with_packages="$2" cask pkg failed=0 pkgs casks_meta has_remove=false tool_pairs pair
  pkgs="$(cap_meta_get "$target" packages)"
  casks_meta="$(cap_meta_get "$target" casks)"
  tool_pairs="$(cap_meta_get "$target" mise_tools)"
  [[ -f "$(cap_dir "$target")/remove" ]] && has_remove=true
  TEEUP_CAP_NA=false
  if [[ "$has_remove" != "true" && -z "$pkgs" && -z "$casks_meta" && -z "$tool_pairs" ]]; then
    return 2
  fi
```

Replace:

```bash
  if [[ "$with_packages" == "true" ]]; then
    for cask in $casks_meta; do
```

with:

```bash
  # A mise tool's link always goes; its pinned install only with packages.
  # conf.d is rewritten without this capability either way, so `mise prune`
  # may take what nothing pins any more.
  for pair in $tool_pairs; do
    mise_tool_remove "${pair%%:*}" "${pair#*:}" "$with_packages" || failed=1
  done
  if [[ -n "$tool_pairs" ]]; then
    mise_tools_conf_write --without "$target" || failed=1
  fi
  if [[ "$with_packages" == "true" ]]; then
    for cask in $casks_meta; do
```

In `bin/teeup` `cmd_remove`, replace:

```bash
    2) die "$target ships no remove script and installs no packages or casks that teeup tracks, so teeup remove cannot undo it; $target is still marked installed." ;;
```

with:

```bash
    2) die "$target ships no remove script and installs no packages, casks or mise tools that teeup tracks, so teeup remove cannot undo it; $target is still marked installed." ;;
```

- [ ] **Step 4: Implement the uninstall summary**

In `lib/uninstall.sh`, add above `_uninstall_remove_one`:

```bash
# _uninstall_mise_specs <name> -> "<spec>@<version> ..." for each of
# <name>'s mise tools that mise has installed, for a summary line and a
# `mise uninstall` that works as printed. Without mise every pinned spec is
# listed, since nothing can say otherwise.
_uninstall_mise_specs() {
  local name="$1" pair tool version spec out=""
  for pair in $(cap_meta_get "$name" mise_tools); do
    tool="${pair%%:*}"
    version="$(tools_lock_version "$tool")" || continue
    spec="$(tools_lock_spec "$tool")"
    if have mise && ! mise -C / where "$spec@$version" >/dev/null 2>&1; then
      continue
    fi
    out="${out:+$out }$spec@$version"
  done
  printf '%s\n' "$out"
}
```

In `_uninstall_remove_one`, replace:

```bash
  local name="$1" rc=0 with="$_UNINSTALL_PACKAGES" names login
  names="$(cap_meta_get "$name" packages) $(cap_meta_get "$name" casks)"
  names="$(printf '%s' "$names" | awk '{$1=$1; print}')"
```

with:

```bash
  local name="$1" rc=0 with="$_UNINSTALL_PACKAGES" names login tool_specs tool_cmds pair link_dir="$HOME/.local/bin"
  names="$(cap_meta_get "$name" packages) $(cap_meta_get "$name" casks)"
  names="$(printf '%s' "$names" | awk '{$1=$1; print}')"
  # Asked before cap_remove: with packages, mise no longer has them after.
  tool_specs="$(_uninstall_mise_specs "$name")"
```

and replace:

```bash
      if [[ -n "$names" ]]; then
        if [[ "$with" == "true" ]]; then
          uninstall_note removed "$name's packages: $names"
        else
          pkg_collect_installed_items "$name"
        fi
      fi
      ;;
```

with:

```bash
      if [[ -n "$names" ]]; then
        if [[ "$with" == "true" ]]; then
          uninstall_note removed "$name's packages: $names"
        else
          pkg_collect_installed_items "$name"
        fi
      fi
      # Only links that are gone: a file teeup did not write was kept.
      tool_cmds=""
      for pair in $(cap_meta_get "$name" mise_tools); do
        if [[ "$DRY_RUN" == "true" || ! ( -e "$link_dir/${pair#*:}" || -L "$link_dir/${pair#*:}" ) ]]; then
          tool_cmds="${tool_cmds:+$tool_cmds }${pair#*:}"
        fi
      done
      if [[ -n "$tool_cmds" ]]; then
        uninstall_note removed "$name's links in $link_dir: $tool_cmds"
      fi
      if [[ -n "$tool_specs" ]]; then
        if [[ "$with" == "true" ]]; then
          uninstall_note removed "$name's mise tools: $tool_specs"
        else
          TEEUP_COLLECTED_MISE="${TEEUP_COLLECTED_MISE:+$TEEUP_COLLECTED_MISE }$tool_specs"
        fi
      fi
      ;;
```

In `uninstall_capabilities`, replace:

```bash
  local name blockers had
  # Reset here, not just at source time: the ledger globals below must not
  # accumulate if the caller (a test, most likely) runs this twice in one
  # process.
  _UNINSTALL_GONE=" "
  TEEUP_COLLECTED_PKGS=""
  TEEUP_COLLECTED_CASKS=""
```

with:

```bash
  local name blockers had conf conf_had=false
  # Reset here, not just at source time: the ledger globals below must not
  # accumulate if the caller (a test, most likely) runs this twice in one
  # process.
  _UNINSTALL_GONE=" "
  TEEUP_COLLECTED_PKGS=""
  TEEUP_COLLECTED_CASKS=""
  TEEUP_COLLECTED_MISE=""
  conf="$(mise_tools_conf_file)"
  if [[ -f "$conf" ]]; then conf_had=true; fi
```

and replace:

```bash
  if [[ -n "$TEEUP_COLLECTED_CASKS" ]]; then
    uninstall_note kept "Apps: $TEEUP_COLLECTED_CASKS. Remove them later with: brew uninstall --cask $TEEUP_COLLECTED_CASKS"
  fi
```

with:

```bash
  if [[ -n "$TEEUP_COLLECTED_CASKS" ]]; then
    uninstall_note kept "Apps: $TEEUP_COLLECTED_CASKS. Remove them later with: brew uninstall --cask $TEEUP_COLLECTED_CASKS"
  fi
  if [[ -n "$TEEUP_COLLECTED_MISE" ]]; then
    uninstall_note kept "mise tools: $TEEUP_COLLECTED_MISE. Remove them later with: mise uninstall $TEEUP_COLLECTED_MISE"
  fi
  # cap_remove rewrote conf.d after each capability; the last one with mise
  # tools deleted it.
  if [[ "$conf_had" == "true" ]] && { [[ "$DRY_RUN" == "true" ]] || [[ ! -e "$conf" ]]; }; then
    uninstall_note removed "the pinned tool list teeup wrote for mise ($conf)"
  fi
```

- [ ] **Step 5: Run and see them pass**

Run the three suites, their bash 3.2 pass, and the full `./tests/run.sh`.
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/capability.sh lib/uninstall.sh bin/teeup tests/lib/capability.sh tests/lib/uninstall.sh tests/cli.sh
git commit -m "Remove mise tools with their capability"
```

---

### Task 7: Check mise tools in `teeup doctor`

**Files:**
- Modify: `lib/mise.sh` (append `mise_tool_old_packages`, `mise_tool_old_package_uninstall`)
- Modify: `lib/doctor.sh:8` (requires comment), `lib/doctor.sh:214-337` (call from `doctor_metadata_check`; new `_doctor_mise_tools_check` just above it)
- Test: `tests/lib/doctor.sh` (helpers after `setup`, tests before `echo "lib/doctor.sh"` at line 756, registrations before `print_summary`)

**Interfaces:**
- Consumes: Tasks 1 and 4 (`mise_tool_link_owned`, `mise_tool_link_is`), `doctor_ok`, `doctor_warn`, `_doctor_report_failure`, `_doctor_report_unknown`, `doctor_backend_can_answer`, `pkg_installed`, `pkg_backend`, `pkg_backend_label`, `command_runs`.
- Produces: `mise_tool_old_packages <tool>` → package names to look for (Homebrew `delta`→`git-delta`, `tealdeer`→`tldr tealdeer`; MacPorts `delta`→`git-delta`; otherwise the tool name); `mise_tool_old_package_uninstall <pkg>` → `brew uninstall <pkg>` or `sudo port uninstall <pkg>`; `_doctor_mise_tools_check <cap>`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/lib/doctor.sh` after `setup()`:

```bash
# doctor_tools_fixture: widget with two mise tools, a lock of its own, a mise
# that installs into $TEST_HOME, and ~/.local/bin first on PATH the way
# bin/teeup puts it.
doctor_tools_fixture() {
  TEEUP_TOOLS_LOCK="$TEST_HOME/tools.lock"
  printf 'ripgrep 15.2.0\ntealdeer 1.9.0\n' > "$TEEUP_TOOLS_LOCK"
  make_cap widget
  printf 'requires="mise"\nmise_tools="ripgrep:rg tealdeer:tldr"\n' >> "$TEEUP_CAPS_DIR/widget/capability"
  hide_host_commands rg tldr
  mock_mise_tools
  export PATH="$HOME/.local/bin:$PATH"
}

# mock_brew_formulas <formula...>: a Homebrew that has exactly these.
mock_brew_formulas() {
  printf '%s\n' "$@" > "$TEST_HOME/brew-formulas"
  mock_command_script brew <<'EOF2'
case "$1" in
  --version) echo "Homebrew 4.3.9" ;;
  list) grep -qx "${3:-}" "$HOME/brew-formulas" ;;
esac
EOF2
}

# mock_port_ports <port...>: a MacPorts machine that has exactly these.
mock_port_ports() {
  printf '%s\n' "$@" > "$TEST_HOME/ports"
  mock_command_script port <<'EOF2'
case "$1" in
  version) echo "Version: 2.9.3" ;;
  installed) grep -qx "${2:-}" "$HOME/ports" && echo "  ${2} @1.0_0 (active)" ;;
esac
EOF2
  export TEEUP_PACKAGE_MANAGER=macports
  unset TEEUP_PKG_BACKEND
}
```

Tests:

```bash
test_mise_tools_check_passes_a_linked_pinned_tool() {
  setup
  doctor_tools_fixture
  mock_brew_formulas
  mise_tools_apply widget >/dev/null 2>&1
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "rg is ripgrep 15.2.0 through mise." || return 1
  assert_contains "$out" "tldr is tealdeer 1.9.0 through mise." || return 1
  assert_equals "" "$(cat "$REPORT")" || return 1
  cleanup_test_env
}

test_mise_tools_check_fails_a_missing_link() {
  setup
  doctor_tools_fixture
  mock_brew_formulas
  doctor_metadata_check widget >/dev/null 2>&1
  assert_contains "$(cat "$REPORT")" "$HOME/.local/bin/rg is missing, so rg is not the ripgrep 15.2.0 that teeup pins." || return 1
  assert_contains "$(cat "$REPORT")" "teeup configure widget" || return 1
  cleanup_test_env
}

test_mise_tools_check_fails_a_dangling_link_and_its_fix_repairs_it() {
  setup
  doctor_tools_fixture
  mock_brew_formulas
  mise_tools_apply widget >/dev/null 2>&1
  rm -rf "$HOME/.local/share/mise/installs/ripgrep/15.2.0"
  doctor_metadata_check widget >/dev/null 2>&1
  assert_contains "$(cat "$REPORT")" "which is gone (mise uninstall and mise prune remove it)" || return 1
  assert_contains "$(cat "$REPORT")" "teeup configure widget" || return 1
  # What `teeup configure widget` runs for a capability with mise tools.
  mise_tools_repair widget >/dev/null 2>&1
  : > "$REPORT"
  doctor_metadata_check widget >/dev/null 2>&1
  assert_equals "" "$(cat "$REPORT")" "the printed fix clears the finding" || return 1
  cleanup_test_env
}

test_mise_tools_check_fails_a_link_to_another_version() {
  setup
  doctor_tools_fixture
  mock_brew_formulas
  mise_tools_apply widget >/dev/null 2>&1
  printf 'ripgrep 15.3.0\ntealdeer 1.9.0\n' > "$TEEUP_TOOLS_LOCK"
  doctor_metadata_check widget >/dev/null 2>&1
  assert_contains "$(cat "$REPORT")" "ripgrep 15.3.0 is not installed through mise" || return 1
  cleanup_test_env
}

test_mise_tools_check_notes_an_old_homebrew_copy() {
  setup
  doctor_tools_fixture
  mock_brew_formulas ripgrep tldr
  mise_tools_apply widget >/dev/null 2>&1
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "Remove it with: brew uninstall ripgrep" || return 1
  assert_contains "$out" "Remove it with: brew uninstall tldr" "teeup installed tealdeer as tldr" || return 1
  assert_equals "" "$(cat "$REPORT")" "a notice does not change the exit status" || return 1
  cleanup_test_env
}

test_mise_tools_check_notes_an_old_macports_copy() {
  setup
  doctor_tools_fixture
  mock_port_ports ripgrep tealdeer
  mise_tools_apply widget >/dev/null 2>&1
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "Remove it with: sudo port uninstall ripgrep" || return 1
  assert_contains "$out" "Remove it with: sudo port uninstall tealdeer" || return 1
  assert_equals "" "$(cat "$REPORT")" || return 1
  unset TEEUP_PACKAGE_MANAGER TEEUP_PKG_BACKEND
  cleanup_test_env
}

test_mise_tools_check_leaves_a_foreign_file_alone() {
  setup
  doctor_tools_fixture
  mock_brew_formulas
  mise_tools_apply widget >/dev/null 2>&1
  rm -f "$HOME/.local/bin/rg"
  printf '#!/bin/sh\necho mine\n' > "$HOME/.local/bin/rg"
  chmod +x "$HOME/.local/bin/rg"
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "$HOME/.local/bin/rg was not written by teeup" || return 1
  assert_equals "" "$(cat "$REPORT")" || return 1
  cleanup_test_env
}

test_mise_tools_check_cannot_verify_without_mise() {
  setup
  doctor_tools_fixture
  mock_brew_formulas
  mise_tools_apply widget >/dev/null 2>&1
  export TEEUP_TEST_MISSING="${TEEUP_TEST_MISSING:-} mise"
  doctor_metadata_check widget >/dev/null 2>&1
  assert_contains "$(cat "$REPORT")" "mise is not on PATH, so teeup could not check that $HOME/.local/bin/rg is ripgrep 15.2.0." || return 1
  assert_contains "$(cat "$REPORT")" "unknown" "it could not check; it did not find a problem" || return 1
  assert_not_contains "$(cat "$REPORT")" "	fail" || return 1
  cleanup_test_env
}

test_mise_tools_check_only_warns_when_mise_is_skipped() {
  setup
  doctor_tools_fixture
  mock_brew_formulas
  local out
  out="$(TEEUP_SKIP=mise doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "mise is skipped on this machine (TEEUP_SKIP), so teeup did not install ripgrep" || return 1
  assert_equals "" "$(cat "$REPORT")" || return 1
  cleanup_test_env
}

test_mise_tools_check_warns_when_another_copy_comes_first() {
  setup
  doctor_tools_fixture
  mock_brew_formulas
  mise_tools_apply widget >/dev/null 2>&1
  mock_command rg 0 "rg 13.0.0"
  export PATH="$MOCK_BIN:$PATH"
  local out
  out="$(doctor_metadata_check widget 2>&1)"
  assert_contains "$out" "rg resolves to $MOCK_BIN/rg on this PATH, not to teeup's $HOME/.local/bin/rg" || return 1
  assert_equals "" "$(cat "$REPORT")" || return 1
  cleanup_test_env
}
```

In the `assert_not_contains ... "	fail"` line above, the character between the quotes is a literal tab (the record separator), so the check means "no record of kind fail".

Register:

```bash
run_test "mise_tools check passes a linked, pinned tool" test_mise_tools_check_passes_a_linked_pinned_tool
run_test "mise_tools check fails a missing link" test_mise_tools_check_fails_a_missing_link
run_test "mise_tools check fails a dangling link, and its fix repairs it" test_mise_tools_check_fails_a_dangling_link_and_its_fix_repairs_it
run_test "mise_tools check fails a link to another version" test_mise_tools_check_fails_a_link_to_another_version
run_test "mise_tools check notes an old Homebrew copy" test_mise_tools_check_notes_an_old_homebrew_copy
run_test "mise_tools check notes an old MacPorts copy" test_mise_tools_check_notes_an_old_macports_copy
run_test "mise_tools check leaves a foreign file alone" test_mise_tools_check_leaves_a_foreign_file_alone
run_test "mise_tools check cannot verify without mise" test_mise_tools_check_cannot_verify_without_mise
run_test "mise_tools check only warns when mise is skipped" test_mise_tools_check_only_warns_when_mise_is_skipped
run_test "mise_tools check warns when another copy comes first" test_mise_tools_check_warns_when_another_copy_comes_first
```

- [ ] **Step 2: Run and see them fail**

Run: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/lib/doctor.sh`
Expected: FAIL on every new test except the two that expect an empty report (`only warns when mise is skipped` fails on its message).

- [ ] **Step 3: Implement**

Append to `lib/mise.sh`:

```bash

# mise_tool_old_packages <tool> -> the package names this backend knew
# <tool> by when teeup 0.3.0-beta and older installed it there, for doctor's
# old-copy notice. Homebrew's tldr formula and MacPorts' tealdeer port both
# gave the `tldr` command; git-delta gave `delta` on both.
mise_tool_old_packages() {
  case "$(pkg_backend):$1" in
    homebrew:delta|macports:delta) echo "git-delta" ;;
    homebrew:tealdeer) echo "tldr tealdeer" ;;
    *) echo "$1" ;;
  esac
}

# mise_tool_old_package_uninstall <pkg> -> the command that removes <pkg>.
mise_tool_old_package_uninstall() {
  case "$(pkg_backend)" in
    homebrew) printf 'brew uninstall %s\n' "$1" ;;
    macports) printf 'sudo port uninstall %s\n' "$1" ;;
  esac
}
```

In `lib/doctor.sh`, change line 8 from:

```bash
# Requires core.sh, state.sh, capability.sh, pkg.sh, lazy.sh.
```

to:

```bash
# Requires core.sh, state.sh, capability.sh, pkg.sh, lazy.sh, mise.sh.
```

Add above `doctor_metadata_check()`:

```bash
# _doctor_mise_tools_check <capability>
# The mise_tools half of the metadata check (#112). Each command's link in
# ~/.local/bin exists, runs the version share/teeup/tools.lock pins, comes
# first on PATH and runs. A dangling link (after `mise uninstall` or
# `mise prune`) and a missing one are failures whose fix is
# `teeup configure <cap>`. A copy of the tool the package manager still has
# from before is a notice with the command that removes it; teeup does not
# remove it itself.
_doctor_mise_tools_check() {
  local cap="$1" pair tool command_name link version spec bin found candidate
  for pair in $(cap_meta_get "$cap" mise_tools); do
    tool="${pair%%:*}"
    command_name="${pair#*:}"
    link="$HOME/.local/bin/$command_name"
    version="$(tools_lock_version "$tool" || true)"
    spec="$(tools_lock_spec "$tool" || true)"
    if cap_skipped mise; then
      doctor_warn "mise is skipped on this machine (TEEUP_SKIP), so teeup did not install $tool; $command_name is whatever else is on PATH."
    elif [[ ! -e "$link" && ! -L "$link" ]]; then
      _doctor_report_failure "$cap" "$link is missing, so $command_name is not the $tool $version that teeup pins." "teeup configure $cap"
    elif ! mise_tool_link_owned "$link"; then
      doctor_warn "$link was not written by teeup, so teeup leaves it alone, and $command_name may not be $tool $version."
    elif [[ -L "$link" && ! -e "$link" ]]; then
      _doctor_report_failure "$cap" "$link points at $(readlink "$link"), which is gone (mise uninstall and mise prune remove it), so $command_name does not run." "teeup configure $cap"
    elif ! have mise; then
      _doctor_report_unknown "$cap" "mise is not on PATH, so teeup could not check that $link is $tool $version." "teeup install mise"
    elif ! bin="$(mise -C / which --tool "$spec@$version" "$command_name" 2>/dev/null)" || [[ -z "$bin" ]]; then
      _doctor_report_failure "$cap" "$tool $version is not installed through mise, so $link runs another version." "teeup configure $cap"
    elif ! mise_tool_link_is "$link" "$bin"; then
      _doctor_report_failure "$cap" "$link does not run $tool $version, the version teeup pins." "teeup configure $cap"
    else
      found="$(command -v "$command_name" 2>/dev/null || true)"
      if [[ "$found" != "$link" ]]; then
        doctor_warn "$command_name resolves to ${found:-nothing} on this PATH, not to teeup's $link ($tool $version). New terminals put $HOME/.local/bin first; check that this shell does too."
      elif command_runs "$command_name"; then
        doctor_ok "$command_name is $tool $version through mise."
      else
        _doctor_report_failure "$cap" "$link is $tool $version, but $command_name does not run." "teeup configure $cap"
      fi
    fi
    if doctor_backend_can_answer; then
      for candidate in $(mise_tool_old_packages "$tool"); do
        if pkg_installed "$candidate" >/dev/null 2>&1; then
          doctor_warn "$(pkg_backend_label) still has $candidate, an older copy of the $tool that teeup now installs through mise. teeup no longer upgrades it. Remove it with: $(mise_tool_old_package_uninstall "$candidate")"
        fi
      done
    fi
  done
  return 0
}
```

In `doctor_metadata_check`, after the closing `fi` of the packages `if ! doctor_backend_can_answer; then ... else ... fi` block (the line before `for item in $(cap_meta_get "$cap" casks); do`), insert:

```bash
  _doctor_mise_tools_check "$cap"
```

- [ ] **Step 4: Run and see them pass**

Run: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/lib/doctor.sh` and its bash 3.2 pass, then the full `./tests/run.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/mise.sh lib/doctor.sh tests/lib/doctor.sh
git commit -m "Check mise tools in teeup doctor"
```

---

### Task 8: Move the user tools from the package manager to mise

**Files:**
- Modify: `capabilities/{cli-tools,git,starship,neovim,tmux,herdr,ollama}/{capability,install,configure}`
- Modify: `lib/pkg.sh:178-186` (drop `macports:tldr`)
- Modify: `tests/docs.sh:17-30` (`nothing_to_remove`)
- Test: `tests/lib/mise.sh` (lock/metadata agreement); `tests/capabilities/cli-tools.sh` (rewritten); `tests/capabilities/{git,starship,neovim,tmux,herdr,ollama}.sh`; `tests/lib/doctor.sh:717-753`; `tests/lib/pkg.sh` (two tldr tests removed); `tests/bootstrap.sh:402`

**Interfaces:**
- Consumes: `mise_tools_apply`, `mise_tools_repair` (Task 4); `not_applicable`; `cask_install`; `pkg_install`.
- Produces: the metadata table from the spec, with `requires` from Task 5:

| Capability | `packages` | `package_commands` | `casks` | `mise_tools` |
|---|---|---|---|---|
| cli-tools | `jq btop tree wget curl gnupg` | `jq:jq btop:btop tree:tree wget:wget curl:curl gnupg:gpg` | | `ripgrep:rg fd:fd fzf:fzf bat:bat eza:eza zoxide:zoxide yq:yq tealdeer:tldr dust:dust` |
| git | `git` | | | `delta:delta git-lfs:git-lfs lazygit:lazygit` |
| starship | | | | `starship:starship` |
| neovim | | | | `neovim:nvim` |
| tmux | | | | `tmux:tmux` |
| herdr | | | | `herdr:herdr` |
| ollama | | | `ollama-app` | `ollama:ollama` |

- [ ] **Step 1: Write the failing tests**

Add to `tests/lib/mise.sh` and register it:

```bash
# The lock and the metadata agree: every tool a capability names has exactly
# one lock line, and the lock names no tool that no capability uses.
test_lock_and_metadata_agree() {
  setup
  local lock="$TEEUP_PATH/share/teeup/tools.lock" name pair tool count named=" " t
  for name in $(cap_list); do
    for pair in $(cap_meta_get "$name" mise_tools); do
      tool="${pair%%:*}"
      count="$(awk -v t="$tool" '$1 !~ /^#/ && $1 == t' "$lock" | wc -l | tr -d ' ')"
      assert_equals "1" "$count" "$name's $tool needs exactly one lock line" || return 1
      named="$named$tool "
    done
  done
  [[ "$named" != " " ]] || { echo "no capability names a mise tool"; return 1; }
  for t in $(awk '!/^#/ && NF { print $1 }' "$lock"); do
    case "$named" in
      *" $t "*) ;;
      *) echo "the lock names $t, which no capability's mise_tools uses"; return 1 ;;
    esac
  done
  cleanup_test_env
}
```

```bash
run_test "lock and metadata agree" test_lock_and_metadata_agree
```

Replace `tests/capabilities/cli-tools.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# cli-tools has two halves (#112). The package manager installs what teeup
# needs (jq), what mise has no package for (tree, wget, curl, gnupg) and
# btop, which has no macOS build upstream. mise installs the rest at the
# versions in share/teeup/tools.lock.
PM_COMMANDS="jq btop tree wget curl gpg"
MISE_COMMANDS="rg fd fzf bat eza zoxide yq tldr dust"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  # A fresh Mac has none of these. The mise half is hidden by path, so the
  # links an install writes into ~/.local/bin still count.
  export TEEUP_TEST_MISSING="jq btop gpg"
  # shellcheck disable=SC2086  # a word list of command names
  hide_host_commands $MISE_COMMANDS
  TEEUP="$TEEUP_PATH/bin/teeup"
  # Nothing in this suite may reach the host's mise (Task 5, #112).
  mock_mise_tools
}

mock_answering_brew() {
  mock_command_script brew <<'EOF2'
case "$1" in --version) echo "Homebrew 4.3.9" ;; esac
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
}

test_doctor_accepts_a_healthy_machine() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_answering_brew
  export TEEUP_TEST_MISSING=""
  local cmd rc=0 out
  for cmd in $PM_COMMANDS; do
    mock_command "$cmd" 0 ""
  done
  DRY_RUN=false "$TEEUP" configure cli-tools >/dev/null 2>&1
  state_done mark cap-cli-tools
  out="$(DRY_RUN=false "$TEEUP" doctor cli-tools 2>&1)" || rc=$?
  assert_success "$rc" "every package command is on PATH and every mise tool is linked: $out" || return 1
  assert_not_contains "$out" "is not installed" || return 1
  assert_contains "$out" "rg is ripgrep $(lock_version ripgrep) through mise." || return 1
  assert_contains "$out" "tldr is tealdeer $(lock_version tealdeer) through mise." || return 1
  cleanup_test_env
}

test_doctor_still_reports_a_package_that_is_missing_everywhere() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_answering_brew
  local cmd rc=0 out
  for cmd in btop tree wget curl gpg; do
    mock_command "$cmd" 0 ""
  done
  export TEEUP_TEST_MISSING="jq"
  DRY_RUN=false "$TEEUP" configure cli-tools >/dev/null 2>&1
  state_done mark cap-cli-tools
  out="$(DRY_RUN=false "$TEEUP" doctor cli-tools 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "package jq is not installed" || return 1
  cleanup_test_env
}

# The printed fix for a missing link is `teeup configure cli-tools`, and
# running it clears the finding.
test_doctor_reports_a_missing_link_and_its_fix_works() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_answering_brew
  export TEEUP_TEST_MISSING=""
  local cmd rc=0 out
  for cmd in $PM_COMMANDS; do
    mock_command "$cmd" 0 ""
  done
  state_done mark cap-cli-tools
  out="$(DRY_RUN=false "$TEEUP" doctor cli-tools 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$TEST_HOME/.local/bin/rg is missing" || return 1
  assert_contains "$out" "fix: teeup configure cli-tools" || return 1
  DRY_RUN=false "$TEEUP" configure cli-tools >/dev/null 2>&1
  rc=0
  out="$(DRY_RUN=false "$TEEUP" doctor cli-tools 2>&1)" || rc=$?
  assert_success "$rc" "the printed fix repaired it: $out" || return 1
  cleanup_test_env
}

test_doctor_reports_one_broken_package_command_end_to_end() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_answering_brew
  export TEEUP_TEST_MISSING=""
  local cmd rc=0 out
  for cmd in btop tree wget curl gpg; do
    mock_command "$cmd" 0 ""
  done
  mock_command jq 1 "broken jq"
  DRY_RUN=false "$TEEUP" configure cli-tools >/dev/null 2>&1
  state_done mark cap-cli-tools
  out="$(DRY_RUN=false "$TEEUP" doctor cli-tools 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "jq resolves to $MOCK_BIN/jq but does not run" || return 1
  assert_contains "$out" "fix: teeup install cli-tools" || return 1
  assert_contains "$out" "gpg is on PATH, so gnupg is provided" || return 1
  cleanup_test_env
}

test_install_reads_its_pairs_from_the_metadata() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  local declared pkg tools pair
  declared="$(cap_meta_get cli-tools package_commands)"
  for pkg in $(cap_meta_get cli-tools packages); do
    case " $declared " in
      *" $pkg:"*) ;;
      *) echo "package $pkg has no command mapping, so doctor cannot ask what install asked"; return 1 ;;
    esac
  done
  assert_contains "$declared" "gnupg:gpg" || return 1
  tools="$(cap_meta_get cli-tools mise_tools)"
  assert_contains "$tools" "ripgrep:rg" || return 1
  assert_contains "$tools" "tealdeer:tldr" || return 1
  for pair in $tools; do
    case " $(cap_meta_get cli-tools packages) " in
      *" ${pair%%:*} "*) echo "${pair%%:*} is in both packages and mise_tools"; return 1 ;;
    esac
  done
  cleanup_test_env
}

test_install_uses_the_package_manager_for_its_half_and_mise_for_the_rest() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install cli-tools 2>&1)"
  assert_contains "$out" "Would execute: brew install jq" || return 1
  assert_contains "$out" "Would execute: brew install gnupg" || return 1
  assert_not_contains "$out" "brew install ripgrep" || return 1
  assert_not_contains "$out" "brew install tldr" || return 1
  assert_contains "$out" "Would execute: mise -C / install ripgrep@$(lock_version ripgrep)" || return 1
  assert_contains "$out" "Would execute: mise -C / install tealdeer@$(lock_version tealdeer)" || return 1
  assert_contains "$out" "Would link $TEST_HOME/.local/bin/tldr to tealdeer $(lock_version tealdeer) (mise)" || return 1
  cleanup_test_env
}

test_install_skips_tools_already_on_path() {
  setup
  export TEEUP_TEST_MISSING="btop gpg"
  mock_command jq 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install cli-tools 2>&1)"
  assert_contains "$out" "Already available on PATH: jq" || return 1
  assert_not_contains "$out" "brew install jq" || return 1
  cleanup_test_env
}

test_install_links_every_mise_tool() {
  setup
  DRY_RUN=false "$TEEUP" install cli-tools >/dev/null 2>&1 || { echo "install failed"; return 1; }
  local cmd
  for cmd in $MISE_COMMANDS; do
    [[ -L "$TEST_HOME/.local/bin/$cmd" ]] || { echo "$cmd is not linked"; return 1; }
  done
  assert_contains "$(cat "$TEST_HOME/.config/mise/conf.d/teeup.toml")" "\"ripgrep\" = \"$(lock_version ripgrep)\"" || return 1
  cleanup_test_env
}

test_install_warns_but_survives_a_missing_port_or_tool() {
  setup
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "list"*) exit 1 ;;
  "install btop") exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  local rc=0 out
  out="$(MOCK_MISE_FAIL_INSTALL=dust DRY_RUN=false "$TEEUP" install cli-tools 2>&1)" || rc=$?
  assert_success "$rc" "one missing tool must not fail the capability" || return 1
  assert_contains "$out" "Could not install: btop" || return 1
  assert_contains "$out" "mise could not install dust $(lock_version dust)" || return 1
  assert_contains "$out" "Some of the tools that come from mise are missing" || return 1
  [[ -L "$TEST_HOME/.local/bin/rg" ]] || { echo "the other tools are still linked"; return 1; }
  cleanup_test_env
}

test_install_on_macports_gets_the_same_mise_tools() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install cli-tools 2>&1)"
  assert_contains "$out" "Would execute: sudo port install jq" || return 1
  assert_contains "$out" "Would execute: mise -C / install ripgrep@$(lock_version ripgrep)" || return 1
  assert_contains "$out" "Would execute: mise -C / install tealdeer@$(lock_version tealdeer)" || return 1
  assert_not_contains "$out" "port install ripgrep" || return 1
  assert_not_contains "$out" "port install tealdeer" || return 1
  cleanup_test_env
}

test_configure_writes_the_bat_config() {
  setup
  DRY_RUN=false "$TEEUP" configure cli-tools >/dev/null 2>&1
  assert_file_exists "$TEST_HOME/.config/bat/config" || return 1
  local body
  body="$(cat "$TEST_HOME/.config/bat/config")"
  assert_contains "$body" "--style=numbers,changes,header" || return 1
  assert_not_contains "$body" "--theme" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  DRY_RUN=false "$TEEUP" configure cli-tools >/dev/null 2>&1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure cli-tools 2>&1)"
  assert_contains "$out" "Already installed: $TEST_HOME/.config/bat/config" || return 1
  assert_contains "$out" "Already linked: rg (ripgrep $(lock_version ripgrep))" || return 1
  assert_contains "$out" "Already current: $TEST_HOME/.config/mise/conf.d/teeup.toml" || return 1
  cleanup_test_env
}

echo "capabilities/cli-tools"
run_test "doctor accepts a healthy machine" test_doctor_accepts_a_healthy_machine
run_test "doctor still reports a package that is missing everywhere" test_doctor_still_reports_a_package_that_is_missing_everywhere
run_test "doctor reports a missing link, and its fix works" test_doctor_reports_a_missing_link_and_its_fix_works
run_test "doctor reports one broken package command end to end" test_doctor_reports_one_broken_package_command_end_to_end
run_test "install reads its pairs from the metadata" test_install_reads_its_pairs_from_the_metadata
run_test "install uses the package manager for its half and mise for the rest" test_install_uses_the_package_manager_for_its_half_and_mise_for_the_rest
run_test "install skips tools already on PATH" test_install_skips_tools_already_on_path
run_test "install links every mise tool" test_install_links_every_mise_tool
run_test "install warns but survives a missing port or tool" test_install_warns_but_survives_a_missing_port_or_tool
run_test "install on MacPorts gets the same mise tools" test_install_on_macports_gets_the_same_mise_tools
run_test "configure writes the bat config" test_configure_writes_the_bat_config
run_test "configure is idempotent" test_configure_is_idempotent
print_summary
```

`tests/capabilities/git.sh`, body of `test_install_gets_git_delta_lfs_and_lazygit` after `local out` / the dry-run line becomes:

```bash
  out="$(DRY_RUN=true "$TEEUP" install git 2>&1)"
  assert_contains "$out" "Would execute: brew install git" || return 1
  assert_not_contains "$out" "brew install git-delta" || return 1
  assert_not_contains "$out" "brew install git-lfs" || return 1
  assert_not_contains "$out" "brew install lazygit" || return 1
  assert_contains "$out" "Would execute: mise -C / install delta@$(lock_version delta)" || return 1
  assert_contains "$out" "Would execute: mise -C / install git-lfs@$(lock_version git-lfs)" || return 1
  assert_contains "$out" "Would execute: mise -C / install lazygit@$(lock_version lazygit)" || return 1
  cleanup_test_env
```

`tests/capabilities/starship.sh`, `test_install_gets_starship`:

```bash
test_install_gets_starship() {
  setup
  export TEEUP_TEST_MISSING="starship"
  local out
  out="$(DRY_RUN=true "$TEEUP" install starship 2>&1)"
  assert_contains "$out" "Would execute: mise -C / install starship@$(lock_version starship)" || return 1
  assert_not_contains "$out" "brew install starship" || return 1
  cleanup_test_env
}
```

`tests/capabilities/neovim.sh`: replace `test_install_dry_run_gets_the_formula` and `test_install_uses_the_port_on_macports` with:

```bash
test_install_dry_run_gets_the_pinned_neovim() {
  setup
  export TEEUP_TEST_MISSING="nvim"
  local out
  out="$(DRY_RUN=true "$TEEUP" install neovim 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: mise -C / install aqua:neovim/neovim@$(lock_version neovim)" || return 1
  assert_not_contains "$out" "brew install neovim" || return 1
  cleanup_test_env
}

test_install_on_macports_still_uses_mise() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  export TEEUP_TEST_MISSING="nvim"
  mock_command port 1 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install neovim 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: mise -C / install aqua:neovim/neovim@$(lock_version neovim)" || return 1
  assert_not_contains "$out" "port install neovim" || return 1
  cleanup_test_env
}
```

and their registrations:

```bash
run_test "install dry run gets the pinned Neovim" test_install_dry_run_gets_the_pinned_neovim
run_test "install on MacPorts still uses mise" test_install_on_macports_still_uses_mise
```

`tests/capabilities/tmux.sh`: replace `test_install_gets_tmux`:

```bash
test_install_gets_tmux() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install tmux 2>&1)"
  assert_contains "$out" "Would execute: mise -C / install tmux@$(lock_version tmux)" || return 1
  assert_not_contains "$out" "brew install tmux" || return 1
  cleanup_test_env
}
```

In each of `test_configure_warns_when_the_installed_tmux_predates_xdg_support`, `test_configure_is_silent_about_the_version_when_tmux_is_current` and `test_configure_never_guesses_at_an_unparsable_version`, replace the `mock_command_script tmux <<'EOF2' ... EOF2` block with a foreign `tmux` in `~/.local/bin` (which mise_tool_install keeps). For the 2.8 test:

```bash
  mkdir -p "$TEST_HOME/.local/bin"
  printf '#!/usr/bin/env bash\n[ "$1" = "-V" ] && echo "tmux 2.8"\n' > "$TEST_HOME/.local/bin/tmux"
  chmod +x "$TEST_HOME/.local/bin/tmux"
```

and the same with `tmux 3.3a` and `tmux next-3.4` in the other two. Then add:

```bash
test_install_is_not_applicable_when_mise_is_skipped() {
  setup
  local out
  out="$(TEEUP_SKIP=mise DRY_RUN=false "$TEEUP" install tmux 2>&1)" || true
  assert_contains "$out" "tmux comes from mise, which is skipped on this machine (TEEUP_SKIP)." || return 1
  "$TEEUP" has tmux && { echo "tmux must not be marked installed"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "brew install tmux" || return 1
  cleanup_test_env
}

# The lazy round trip through mise: the shim asks, the install links
# ~/.local/bin/tmux, the link runs, and the next call needs no teeup at all.
test_shim_round_trip_installs_tmux_through_mise_and_runs_it() {
  setup
  export TEEUP_NO_GUM=1
  local shims="$TEST_HOME/.local/state/teeup/shims" out
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null 2>&1
  assert_file_exists "$shims/tmux" || return 1
  export PATH="$MOCK_BIN:$TEST_HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$shims"
  export TEEUP_TEST_MISSING=""
  hide_host_commands tmux
  out="$(printf 'y\n' | TEEUP_TEST_TTY=yes DRY_RUN=false "$shims/tmux" new -s work 2>&1)"
  assert_contains "$out" "tmux is provided by capability tmux. Install now?" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install tmux@$(lock_version tmux)" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew install tmux" || return 1
  assert_contains "$out" "tmux ran: new -s work" || return 1
  [[ -L "$TEST_HOME/.local/bin/tmux" ]] || { echo "the link must be in ~/.local/bin"; return 1; }
  "$TEEUP" has tmux || { echo "tmux must be marked installed"; return 1; }
  assert_equals "$TEST_HOME/.local/bin/tmux" "$(command -v tmux)" "the link comes before the shim" || return 1
  cleanup_test_env
}
```

```bash
run_test "install is not applicable when mise is skipped" test_install_is_not_applicable_when_mise_is_skipped
run_test "shim round trip installs tmux through mise and runs it" test_shim_round_trip_installs_tmux_through_mise_and_runs_it
```

`tests/capabilities/herdr.sh`: replace both install tests with:

```bash
test_install_gets_the_pinned_herdr() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install herdr 2>&1)"
  assert_contains "$out" "Would execute: mise -C / install herdr@$(lock_version herdr)" || return 1
  assert_not_contains "$out" "brew install herdr" || return 1
  cleanup_test_env
}

test_install_on_macports_still_uses_mise() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install herdr 2>&1)"
  assert_contains "$out" "Would execute: mise -C / install herdr@$(lock_version herdr)" || return 1
  assert_not_contains "$out" "port install herdr" || return 1
  cleanup_test_env
}
```

```bash
run_test "install gets the pinned herdr" test_install_gets_the_pinned_herdr
run_test "install on MacPorts still uses mise" test_install_on_macports_still_uses_mise
```

`tests/capabilities/ollama.sh`: replace the four install tests with:

```bash
test_install_gets_the_cask_and_the_pinned_command() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install ollama 2>&1)"
  assert_contains "$out" "Would execute: brew install --cask ollama-app" || return 1
  assert_contains "$out" "Would execute: mise -C / install ollama@$(lock_version ollama)" || return 1
  assert_not_contains "$out" "brew install ollama" || return 1
  assert_not_contains "$out" "ollama pull llama3.2" || return 1
  cleanup_test_env
}

test_install_keeps_the_mise_command_when_the_cask_fails_on_an_old_mac() {
  setup
  mock_command sw_vers 0 "13.6"
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "list "*) exit 1 ;;
  "install --cask") exit 1 ;;
esac
exit 0
EOF2
  local out
  out="$(DRY_RUN=false "$TEEUP" install ollama 2>&1)"
  assert_contains "$out" "The ollama-app cask did not install (it needs macOS 14 or newer; this Mac is on macOS 13)." || return 1
  assert_contains "$out" "start the server with: ollama serve" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install ollama@$(lock_version ollama)" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew install ollama" "the formula fallback is gone" || return 1
  "$TEEUP" has ollama || { echo "ollama must be marked installed"; return 1; }
  cleanup_test_env
}

test_install_does_not_blame_macos_when_this_mac_is_current() {
  setup
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "list "*) exit 1 ;;
  "install --cask") exit 1 ;;
esac
exit 0
EOF2
  local out
  out="$(DRY_RUN=false "$TEEUP" install ollama 2>&1)"
  assert_contains "$out" "The ollama-app cask did not install. The ollama command still comes from mise" || return 1
  assert_not_contains "$out" "macOS 14 or newer" || return 1
  "$TEEUP" has ollama || { echo "ollama must be marked installed"; return 1; }
  cleanup_test_env
}

test_install_on_macports_uses_mise_and_no_port() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install ollama 2>&1)"
  assert_contains "$out" "Would execute: mise -C / install ollama@$(lock_version ollama)" || return 1
  assert_not_contains "$out" "port install ollama" || return 1
  assert_not_contains "$out" "--cask" || return 1
  cleanup_test_env
}
```

```bash
run_test "install gets the cask and the pinned command" test_install_gets_the_cask_and_the_pinned_command
run_test "install keeps the mise command when the cask fails on an old Mac" test_install_keeps_the_mise_command_when_the_cask_fails_on_an_old_mac
run_test "install does not blame macOS when this Mac is current" test_install_does_not_blame_macos_when_this_mac_is_current
run_test "install on MacPorts uses mise and no port" test_install_on_macports_uses_mise_and_no_port
```

`tests/lib/doctor.sh`: in `test_run_one_checks_packages_for_a_real_capability_with_no_doctor_script`, replace the three `ripgrep` assertions with:

```bash
  assert_contains "$out" "package jq is not installed" || return 1
  assert_contains "$(cat "$REPORT")" "package jq is not installed" || return 1
  assert_contains "$(cat "$REPORT")" "teeup install cli-tools" || return 1
  assert_contains "$(cat "$REPORT")" "$HOME/.local/bin/rg is missing" "the mise half is checked too" || return 1
```

and replace the body of `test_run_one_accepts_a_real_capability_whose_commands_are_on_path` with:

```bash
  setup
  TEEUP_CAPS_DIR="$TEEUP_PATH/capabilities"
  mock_command_script brew <<'EOF2'
case "$1" in --version) echo "Homebrew 4.0.0" ;; *) exit 1 ;; esac
EOF2
  hide_host_commands rg fd fzf bat eza zoxide yq tldr dust
  mock_mise_tools
  local cmd
  for cmd in jq btop tree wget curl gpg; do
    mock_command "$cmd" 0 ""
  done
  mise_tools_apply cli-tools >/dev/null 2>&1
  export PATH="$HOME/.local/bin:$PATH"
  local out
  out="$(doctor_run_one cli-tools 2>&1)"
  assert_not_contains "$out" "is not installed" "every package command is on PATH and every mise tool is linked" || return 1
  assert_equals "" "$(cat "$REPORT")" "nothing here is a finding the user must act on" || return 1
  cleanup_test_env
```

`tests/lib/pkg.sh`: delete `test_candidates_map_tldr_to_tealdeer_only_on_macports` and `test_pkg_install_does_not_claim_success_on_a_failed_tealdeer` (and the comment blocks above them, lines 252-298), and their two `run_test` lines (669 and 671).

`tests/bootstrap.sh` `test_a_second_bootstrap_changes_nothing`: replace

```bash
  assert_not_contains "$out" "Installed ripgrep (Homebrew)" "nothing was installed again" || return 1
```

with:

```bash
  assert_not_contains "$out" "Installed jq (Homebrew)" "nothing was installed again" || return 1
  assert_contains "$out" "Already linked: rg (ripgrep $(lock_version ripgrep))" "the pinned tools are already in place" || return 1
```

`tests/docs.sh` `nothing_to_remove`: replace

```bash
  local dir name packages casks
```

with:

```bash
  local dir name packages casks tools
```

and

```bash
    casks="$(sed -n 's/^casks="\(.*\)"$/\1/p' "$dir/capability")"
    [[ -n "$packages" || -n "$casks" ]] && continue
```

with:

```bash
    casks="$(sed -n 's/^casks="\(.*\)"$/\1/p' "$dir/capability")"
    tools="$(sed -n 's/^mise_tools="\(.*\)"$/\1/p' "$dir/capability")"
    [[ -n "$packages" || -n "$casks" || -n "$tools" ]] && continue
```

and its comment `# Every capability with no remove script and no packages or casks:` to `# Every capability with no remove script and no packages, casks or mise tools:`.

- [ ] **Step 2: Run and see them fail**

Run each edited suite through `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/...`.
Expected: FAIL (`no capability names a mise tool`; brew installs where mise is expected; `tests/docs.sh` stays green at this step).

- [ ] **Step 3: Switch the metadata**

`capabilities/cli-tools/capability`:

```bash
summary="The modern CLI set: ripgrep, fd, fzf, bat, eza, zoxide and friends"
group=shell
tier=core
requires="package-manager mise"
provides=""
packages="jq btop tree wget curl gnupg"
package_commands="jq:jq btop:btop tree:tree wget:wget curl:curl gnupg:gpg"
mise_tools="ripgrep:rg fd:fd fzf:fzf bat:bat eza:eza zoxide:zoxide yq:yq tealdeer:tldr dust:dust"
casks=""
apps=""
interactive=false
```

`capabilities/git/capability`:

```bash
summary="git with your identity, SSH commit signing, delta and lazygit"
group=git
tier=core
requires="dev-dirs cli-tools mise"
provides=""
packages="git"
package_commands=""
mise_tools="delta:delta git-lfs:git-lfs lazygit:lazygit"
casks=""
apps=""
interactive=false
```

`capabilities/starship/capability`:

```bash
summary="Starship prompt"
group=shell
tier=core
requires="zsh mise"
provides=""
packages=""
package_commands=""
mise_tools="starship:starship"
casks=""
apps=""
interactive=false
```

`capabilities/neovim/capability`:

```bash
summary="Neovim with LazyVim, following the teeup theme"
group=editors
tier=lazy
requires="package-manager git cli-tools mise"
provides="nvim"
packages=""
package_commands=""
mise_tools="neovim:nvim"
casks=""
apps=""
interactive=false
```

`capabilities/tmux/capability`:

```bash
summary="tmux terminal multiplexer"
group=shell
tier=lazy
requires="package-manager mise"
provides="tmux"
packages=""
package_commands=""
mise_tools="tmux:tmux"
casks=""
apps=""
interactive=false
```

`capabilities/herdr/capability`:

```bash
summary="Herdr, the agent multiplexer that lives in your terminal"
group=ai
tier=lazy
requires="package-manager mise"
provides="herdr"
packages=""
package_commands=""
mise_tools="herdr:herdr"
casks=""
apps=""
interactive=false
```

`capabilities/ollama/capability`:

```bash
summary="Ollama local LLM runtime (no models downloaded)"
group=ai
tier=lazy
requires="package-manager mise"
provides="ollama"
packages=""
package_commands=""
mise_tools="ollama:ollama"
casks="ollama-app"
apps="Ollama"
interactive=false
```

- [ ] **Step 4: Switch the scripts**

`capabilities/cli-tools/install`:

```bash
#!/usr/bin/env bash
# Two sources (#112). The package manager installs what teeup itself needs
# (jq), what mise has no package for (tree, wget, curl, gnupg) and btop,
# which has no macOS build upstream, as package:command pairs, because the
# package name and the binary differ and pkg_install skips whatever is
# already on PATH. Every other tool comes from mise at the version in
# share/teeup/tools.lock, linked into ~/.local/bin (mise_tools).
#
# Both lists live in the capability metadata, not here: they are the facts
# `teeup doctor` needs, and it has to ask what install asked.
#
# lazygit and delta belong to the git capability and gh to github: every
# package and every mise tool has exactly one owner.
failed=""
for pair in $(cap_meta_get "$TEEUP_CAP" package_commands); do
  pkg="${pair%%:*}"
  cmd="${pair##*:}"
  pkg_install "$pkg" "$cmd" || failed="$failed $pkg"
done

# One missing port or tool must not abort the core tier; the shell layer
# guards on each tool and `teeup doctor` reports the gap.
if [[ -n "$failed" ]]; then
  warn "Could not install:$failed. Install them by hand, or re-run: teeup install cli-tools"
fi
if ! mise_tools_apply "$TEEUP_CAP"; then
  warn "Some of the tools that come from mise are missing (the lines above say which). Fix the cause, then run: teeup configure cli-tools"
fi
```

`capabilities/cli-tools/configure`, append:

```bash

# `teeup configure cli-tools` is the repair path for the mise half: it
# installs a missing pinned version again and repairs its link.
mise_tools_repair "$TEEUP_CAP"
```

`capabilities/git/install`:

```bash
#!/usr/bin/env bash
# No command guard on git itself: macOS ships one with the Command Line Tools,
# so `pkg_install git git` would be a permanent no-op and the machine would
# keep a git that trails upstream by about a year. git is teeup's own tool
# (its checkout and updates), so it stays with the package manager.
pkg_install git || die "git is required and could not be installed."

# delta, git-lfs and lazygit come from mise at the versions in
# share/teeup/tools.lock (#112). delta is the pager the generated config
# names, so a missing one is loud; configure falls back to less without it.
if ! mise_tools_apply "$TEEUP_CAP"; then
  warn "delta, git-lfs or lazygit is missing (the lines above say which). git uses less as its pager until delta is there. Fix the cause, then run: teeup configure git"
fi
```

`capabilities/git/configure`: insert after the `git_dir="$(user_config_dir)/git"` line:

```bash

# delta, git-lfs and lazygit first: the pager choice below asks whether
# delta is there, and `teeup configure git` is their repair path.
mise_tools_repair "$TEEUP_CAP"
```

`capabilities/starship/install`:

```bash
#!/usr/bin/env bash
# The prompt itself, from mise at the version in share/teeup/tools.lock and
# linked into ~/.local/bin. capabilities/zsh/default/init runs
# `starship init zsh` whenever the binary is on PATH, so there is no wiring
# step.
if cap_skipped mise; then
  not_applicable "Starship comes from mise, which is skipped on this machine (TEEUP_SKIP)."
fi
mise_tools_apply "$TEEUP_CAP"
```

`capabilities/starship/configure`: insert before the `copy_config_once` line:

```bash
mise_tools_repair "$TEEUP_CAP"
```

`capabilities/neovim/install`:

```bash
#!/usr/bin/env bash
# Neovim comes from mise at the version in share/teeup/tools.lock, through
# the aqua build the lock names, and ~/.local/bin/nvim links to it. LazyVim
# wants git (partial clones), ripgrep, fd and fzf, which the git and
# cli-tools capabilities this one requires already provide; lazy.nvim and
# the plugins are cloned by Neovim itself on the first start.
if cap_skipped mise; then
  not_applicable "Neovim comes from mise, which is skipped on this machine (TEEUP_SKIP)."
fi
mise_tools_apply "$TEEUP_CAP" || die "Neovim could not be installed."
```

`capabilities/neovim/configure`: insert after the `NVIM_DIR="$(user_config_dir)/nvim"` line:

```bash
mise_tools_repair "$TEEUP_CAP"
```

and replace the comment lines:

```bash
# LazyVim stops with an error on a Neovim older than 0.11.2, and pkg_install
# keeps whatever nvim is already on PATH, so an old one is reported here. The
```

with:

```bash
# LazyVim stops with an error on a Neovim older than 0.11.2. The pinned one
# is newer, but an nvim the user put in ~/.local/bin is kept in its place,
# and another can come first on PATH, so an old one is reported here. The
```

`capabilities/tmux/install`:

```bash
#!/usr/bin/env bash
# tmux comes from mise (aqua:tmux/tmux-builds) at the version in
# share/teeup/tools.lock, linked into ~/.local/bin.
if cap_skipped mise; then
  not_applicable "tmux comes from mise, which is skipped on this machine (TEEUP_SKIP)."
fi
mise_tools_apply "$TEEUP_CAP"
```

`capabilities/tmux/configure`: replace the comment lines

```bash
# "master"). pkg_install skips installing when any tmux is already on PATH
# (M8), so a pre-existing 2.x tmux would otherwise get a config it can never
# read while teeup claims success; only a confirmed-old answer says so, so an
# unverifiable one is never turned into a claim either way.
```

with:

```bash
# "master"). The pinned tmux is newer than 3.1, but a tmux the user put in
# ~/.local/bin is kept in its place (M8), so a pre-existing 2.x tmux would
# otherwise get a config it can never read while teeup claims success; only
# a confirmed-old answer says so, so an unverifiable one is never turned into
# a claim either way.
```

and insert before the `if [[ -e "$HOME/.tmux.conf" || -L "$HOME/.tmux.conf" ]]; then` line:

```bash
mise_tools_repair "$TEEUP_CAP"

```

`capabilities/herdr/install`:

```bash
#!/usr/bin/env bash
# Herdr comes from mise (aqua:herdrdev/herdr, the macOS builds on every
# GitHub release) at the version in share/teeup/tools.lock, linked into
# ~/.local/bin: the same tool on a Homebrew and on a MacPorts Mac.
if cap_skipped mise; then
  not_applicable "Herdr comes from mise, which is skipped on this machine (TEEUP_SKIP)."
fi
mise_tools_apply "$TEEUP_CAP"
```

`capabilities/herdr/configure`: insert before the `log` line:

```bash
mise_tools_repair "$TEEUP_CAP"
```

`capabilities/ollama/install`:

```bash
#!/usr/bin/env bash
# Two halves from two sources (#112). The ollama command comes from mise at
# the version in share/teeup/tools.lock, linked into ~/.local/bin ahead of
# the package manager's directories (and ahead of the CLI the cask links
# there). Ollama.app, the menu-bar app that runs the server, comes from the
# ollama-app cask, which needs macOS 14 or newer and exists only on
# Homebrew. Without the app, `ollama serve` runs the server.
if casks_supported; then
  if ! cask_install ollama-app; then
    # Only blame the macOS floor when this Mac is actually below it (I6): the
    # cask can as well fail from a network problem, a tap issue or a
    # quarantine prompt.
    ollama_macos_major="$(macos_major)"
    if [[ "${ollama_macos_major:-99}" -lt 14 ]] 2>/dev/null; then
      warn "The ollama-app cask did not install (it needs macOS 14 or newer; this Mac is on macOS $ollama_macos_major). The ollama command still comes from mise; start the server with: ollama serve"
    else
      warn "The ollama-app cask did not install. The ollama command still comes from mise; start the server with: ollama serve"
    fi
    unset ollama_macos_major
  fi
else
  log "MacPorts has no Ollama.app; the ollama command comes from mise. Start the server with: ollama serve"
fi
if ! mise_tools_apply "$TEEUP_CAP"; then
  if cap_skipped mise; then
    warn "The ollama command comes from mise, which is skipped on this machine (TEEUP_SKIP); only the app was installed."
  else
    die "The ollama command could not be installed through mise (the lines above say why)."
  fi
fi
```

`capabilities/ollama/configure`: insert after the two comment lines:

```bash
mise_tools_repair "$TEEUP_CAP"
```

- [ ] **Step 5: Drop the `macports:tldr` candidate**

In `lib/pkg.sh` `package_candidates`, delete these lines:

```bash
    # `tldr` itself is not a MacPorts port; tealdeer is the only candidate,
    # because its binary is named `tldr`, matching the `tldr:tldr`
    # package:command pair cli-tools installs it under. tlrc, the
    # tldr-pages project's own official client, is a real tldr client too
    # and worth installing by hand, but it can't go in this chain: its
    # binary is `tlrc`, not `tldr`, so pkg_install would report success
    # while the `tldr` command still did not exist. If tealdeer fails to
    # install, pkg_install's own warning is the honest outcome.
    macports:tldr) echo "tealdeer" ;;
```

- [ ] **Step 6: Run and see them pass**

Run every suite edited in Step 1 plus `tests/docs.sh`, each through `perl -e 'setpgrp 0,0; exec @ARGV' bash ...`, then the bash 3.2 pass for each and the full `./tests/run.sh`. Run the guard from Task 5 Step 4 again; it must print only fixture-tree `tests/lib/*.sh` files.
Expected: PASS. `tests/lib/capability.sh`'s `test_check_passes_on_the_shipped_tree` now lints the new metadata against the shipped lock.

- [ ] **Step 7: Commit**

```bash
git add capabilities lib/pkg.sh tests
git commit -m "Move the user tools from the package manager to mise"
```

---

### Task 9: `teeup update` upgrades formulae only when the checkout moved, and re-links from the lock

**Files:**
- Modify: `bin/teeup:350-391` (new `_update_head` and `_update_mise_tools` after `_update_checkout`), `bin/teeup:467-...` (`cmd_update`)
- Test: `tests/cli.sh:868-883` (`mock_update_world`), `tests/cli.sh:1241-1277` (`test_update_upgrades_only_what_teeup_installed`), new tests before `print_summary`

**Interfaces:**
- Consumes: `mise_tools_sync` (Task 4) in a fresh bash; `pkg_upgrade_all`, `run_logged`, `have`.
- Produces: `_update_head` → HEAD's commit id, or nothing when `$TEEUP_PATH` is not a git checkout or git is missing; `_update_mise_tools` → `run_logged "mise tools"` around `mise_tools_sync`, its exit status. Messages: `teeup is still on the same commit, so the packages it installed keep their versions. A new release upgrades them.` and `A dry run does not move the checkout, so it upgrades no packages. A real run upgrades them when it moves teeup to a new commit.`

- [ ] **Step 1: Write the failing tests**

Replace `mock_update_world` in `tests/cli.sh` with:

```bash
# Everything `teeup update` reaches out to, mocked: the checkout is clean and
# one release (v9.9.9) behind origin/main's newest, with HEAD detached; the
# checkout moves when `git checkout` runs, the way a real one does, so
# `rev-parse HEAD` answers 1111111 before it and 9999999 after; the package
# manager and mise do nothing, and the fixture core.list is alpha+beta.
# lib/channel.sh's own suite runs the release rule against real git.
mock_update_world() {
  mock_command_script git <<'EOF2'
case "$*" in
  *status*) exit 0 ;;
  *"for-each-ref"*) echo refs/teeup/releases/v9.9.9 ;;
  *"rev-list --count"*) echo 5 ;;
  *"checkout --quiet --detach"*) echo 9999999 > "$HOME/mock-git-head" ;;
  *"rev-parse HEAD") cat "$HOME/mock-git-head" 2>/dev/null || echo 1111111 ;;
  *rev-parse*) echo 9999999 ;;
  *symbolic-ref*) exit 1 ;;
esac
exit 0
EOF2
  mock_command brew 0 ""
  mock_command mise 0 ""
  mock_command security 0 "Number of trusted certs = 0"
}
```

In `test_update_upgrades_only_what_teeup_installed`, replace the second

```bash
  : > "$MOCK_LOG"
  local rc=0
```

with:

```bash
  : > "$MOCK_LOG"
  # A second update only upgrades formulae when it moves teeup again.
  rm -f "$TEST_HOME/mock-git-head"
  local rc=0
```

In `test_update_walks_every_step_in_order`, add after the `mise -C / upgrade` assertion:

```bash
  assert_contains "$out" "Completed: mise tools" || return 1
```

Add the new tests:

```bash
test_update_leaves_formulae_alone_when_the_checkout_stays() {
  setup
  mock_update_world
  printf 'packages="ripgrep"\n' >> "$TEEUP_CAPS_DIR/alpha/capability"
  "$TEEUP" install alpha >/dev/null
  echo 9999999 > "$TEST_HOME/mock-git-head"
  : > "$MOCK_LOG"
  local out
  out="$("$TEEUP" update 2>&1)"
  assert_contains "$out" "teeup is on the newest release, v9.9.9." || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew update" "the index still refreshes" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew upgrade" "formulae cannot be pinned, so they move only with teeup" || return 1
  assert_contains "$out" "teeup is still on the same commit, so the packages it installed keep their versions." || return 1
  assert_contains "$out" "configure:alpha" "the rest of the update still runs" || return 1
  cleanup_test_env
}

test_update_dry_run_upgrades_no_formulae() {
  setup
  mock_update_world
  printf 'packages="ripgrep"\n' >> "$TEEUP_CAPS_DIR/alpha/capability"
  "$TEEUP" install alpha >/dev/null
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=true "$TEEUP" update 2>&1)"
  assert_contains "$out" "Would execute: git -C $TEEUP_PATH checkout --quiet --detach refs/teeup/releases/v9.9.9" || return 1
  assert_not_contains "$out" "brew upgrade" || return 1
  assert_contains "$out" "A dry run does not move the checkout, so it upgrades no packages." || return 1
  cleanup_test_env
}

# A release that moves a pin moves the tool, on every capability installed
# here, lazy ones included: update never runs a lazy capability's configure.
test_update_relinks_a_lazy_tool_whose_lock_version_changed() {
  setup
  mock_update_world
  mock_mise_tools
  export TEEUP_TOOLS_LOCK="$TEST_HOME/tools.lock"
  printf 'ripgrep 15.2.0\n' > "$TEEUP_TOOLS_LOCK"
  make_cap search lazy
  printf 'mise_tools="ripgrep:rg"\n' >> "$TEEUP_CAPS_DIR/search/capability"
  printf '#!/usr/bin/env bash\nmise_tools_apply "$TEEUP_CAP"\n' > "$TEEUP_CAPS_DIR/search/install"
  "$TEEUP" install search >/dev/null 2>&1
  local installs="$TEST_HOME/.local/share/mise/installs/ripgrep" link="$TEST_HOME/.local/bin/rg" out
  assert_equals "$installs/15.2.0/bin/rg" "$(readlink "$link")" "fixture: linked at the first version" || return 1
  printf 'ripgrep 15.3.0\n' > "$TEEUP_TOOLS_LOCK"
  out="$("$TEEUP" update 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install ripgrep@15.3.0" || return 1
  assert_equals "$installs/15.3.0/bin/rg" "$(readlink "$link")" || return 1
  assert_dir_exists "$installs/15.2.0" "the old version stays for mise prune" || return 1
  assert_contains "$(cat "$TEST_HOME/.config/mise/conf.d/teeup.toml")" '"ripgrep" = "15.3.0"' || return 1
  assert_not_contains "$out" "configure:search" "update still leaves a lazy capability's configure alone" || return 1
  assert_contains "$out" "teeup is up to date." || return 1
  cleanup_test_env
}

test_update_reports_a_pinned_tool_that_would_not_install() {
  setup
  mock_update_world
  mock_mise_tools
  export TEEUP_TOOLS_LOCK="$TEST_HOME/tools.lock"
  printf 'ripgrep 15.2.0\n' > "$TEEUP_TOOLS_LOCK"
  make_cap search lazy
  printf 'mise_tools="ripgrep:rg"\n' >> "$TEEUP_CAPS_DIR/search/capability"
  printf '#!/usr/bin/env bash\nmise_tools_apply "$TEEUP_CAP"\n' > "$TEEUP_CAPS_DIR/search/install"
  "$TEEUP" install search >/dev/null 2>&1
  printf 'ripgrep 15.3.0\n' > "$TEEUP_TOOLS_LOCK"
  local rc=0 out
  out="$(MOCK_MISE_FAIL_INSTALL=ripgrep "$TEEUP" update 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "mise could not install ripgrep 15.3.0" || return 1
  assert_contains "$out" "teeup update finished, with the problems above." || return 1
  assert_equals "$TEST_HOME/.local/share/mise/installs/ripgrep/15.2.0/bin/rg" "$(readlink "$TEST_HOME/.local/bin/rg")" "the working version stays linked" || return 1
  cleanup_test_env
}
```

Register them before `print_summary`:

```bash
run_test "update leaves formulae alone when the checkout stays" test_update_leaves_formulae_alone_when_the_checkout_stays
run_test "update dry run upgrades no formulae" test_update_dry_run_upgrades_no_formulae
run_test "update relinks a lazy tool whose lock version changed" test_update_relinks_a_lazy_tool_whose_lock_version_changed
run_test "update reports a pinned tool that would not install" test_update_reports_a_pinned_tool_that_would_not_install
```

- [ ] **Step 2: Run and see them fail**

Run: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/cli.sh`
Expected: FAIL on the four new tests and on `test_update_walks_every_step_in_order` (`Completed: mise tools` missing).

- [ ] **Step 3: Implement**

In `bin/teeup`, add after `_update_checkout`'s closing `}`:

```bash

# _update_head -> the commit the checkout is on; nothing when it is not a git
# checkout or git is missing. cmd_update compares it before and after
# _update_checkout.
_update_head() {
  if [[ ! -e "$TEEUP_PATH/.git" ]] || ! have git; then
    return 0
  fi
  git -C "$TEEUP_PATH" rev-parse HEAD 2>/dev/null || true
}

# _update_mise_tools: the pinned tools at the versions the lock names now
# (#112), for every installed capability, lazy ones included. It runs in a
# fresh bash because this process loaded lib/ before _update_checkout moved
# the checkout, and the new release's lock has to be read by the new
# release's code.
_update_mise_tools() {
  run_logged "mise tools" false \
    bash -eu -c 'source "$TEEUP_PATH/lib/all.sh"; answers_load; mise_tools_sync'
}
```

In `cmd_update`, change the locals line:

```bash
  local target="" channel="" failed=0 name pkg cask rc=0 theme_done=false current_theme
```

to:

```bash
  local target="" channel="" failed=0 name pkg cask rc=0 theme_done=false current_theme head_before head_after
```

and replace:

```bash
  _update_checkout || rc=$?
  if [[ $rc -eq 2 ]]; then exit 1; fi
  if [[ $rc -ne 0 ]]; then failed=1; fi

  pkg_update || { warn "$(pkg_backend_label) could not refresh its index."; failed=1; }
  pkg_upgrade_all || { warn "$(pkg_backend_label) could not upgrade everything."; failed=1; }
  mise_upgrade || failed=1
```

with:

```bash
  head_before="$(_update_head)"
  _update_checkout || rc=$?
  if [[ $rc -eq 2 ]]; then exit 1; fi
  if [[ $rc -ne 0 ]]; then failed=1; fi
  head_after="$(_update_head)"

  pkg_update || { warn "$(pkg_backend_label) could not refresh its index."; failed=1; }
  # Package-manager formulae cannot be pinned (#112), so they move only when
  # teeup does: a new release, or new commits on the main channel. An update
  # that stays on the same commit leaves their versions where they are.
  if [[ -n "$head_before" && "$head_before" != "$head_after" ]]; then
    pkg_upgrade_all || { warn "$(pkg_backend_label) could not upgrade everything."; failed=1; }
  elif [[ "$DRY_RUN" == "true" ]]; then
    log "A dry run does not move the checkout, so it upgrades no packages. A real run upgrades them when it moves teeup to a new commit."
  else
    log "teeup is still on the same commit, so the packages it installed keep their versions. A new release upgrades them."
  fi
  # mise upgrade moves what the user added with `mise use -g`; the pinned
  # tools carry exact versions, which it leaves alone.
  mise_upgrade || failed=1
  _update_mise_tools || failed=1
```

- [ ] **Step 4: Run and see them pass**

Run: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/cli.sh`, its bash 3.2 pass, and the full `./tests/run.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/teeup tests/cli.sh
git commit -m "Upgrade formulae only when teeup update moves the checkout"
```

---

### Task 10: Migrate existing Macs

**Files:**
- Create: `migrations/1791459420.sh` (the spec commit's epoch plus one; if `ls migrations` shows a name at or above it when you start, use one more than the largest)
- Test: `tests/lib/migrations.sh` (constant and copy helper next to `GITHUB_PACKAGE_MIGRATION`, line 186; tests and registrations before `print_summary`)

**Interfaces:**
- Consumes: `mise_tools_sync` (Task 4), `cap_exists`, `warn`, `log`.
- Produces: a migration that installs and links every installed capability's tools, writes conf.d, never uninstalls a package, and never fails the update.

- [ ] **Step 1: Write the failing tests**

Add to `tests/lib/migrations.sh` after `copy_github_package_migration`:

```bash
MISE_TOOLS_MIGRATION=1791459420.sh

copy_mise_tools_migration() {
  cp "$TEEUP_PATH/migrations/$MISE_TOOLS_MIGRATION" "$TEEUP_MIGRATIONS_DIR/$MISE_TOOLS_MIGRATION"
}

# A Homebrew that has every formula: the copies teeup installed before #112.
mock_brew_with_everything() {
  mock_command_script brew <<'EOF2'
case "$1" in
  --version) echo "Homebrew 4.3.9" ;;
  list) exit 0 ;;
esac
exit 0
EOF2
}

test_mise_tools_migration_links_the_tools_and_keeps_the_homebrew_copies() {
  setup
  copy_mise_tools_migration
  mock_mise_tools
  mock_brew_with_everything
  state_done mark cap-cli-tools
  state_done mark cap-neovim
  local bin="$TEST_HOME/.local/bin" conf="$TEST_HOME/.config/mise/conf.d/teeup.toml"
  migration_run "$MISE_TOOLS_MIGRATION" >/dev/null 2>&1 || { echo "the migration failed"; return 1; }
  [[ -L "$bin/rg" && -L "$bin/tldr" && -L "$bin/nvim" ]] || { echo "core and lazy tools are linked"; return 1; }
  [[ ! -e "$bin/delta" && ! -L "$bin/delta" ]] || { echo "git is not installed here, so its tools are not"; return 1; }
  assert_contains "$(cat "$conf")" "\"ripgrep\" = \"$(lock_version ripgrep)\"" || return 1
  assert_contains "$(cat "$conf")" "\"aqua:neovim/neovim\" = \"$(lock_version neovim)\"" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "uninstall" "the Homebrew copies stay" || return 1
  assert_file_exists "$MARKS/$MISE_TOOLS_MIGRATION" || return 1
  cleanup_test_env
}

test_mise_tools_migration_dry_run_changes_nothing() {
  setup
  copy_mise_tools_migration
  mock_mise_tools
  mock_brew_with_everything
  state_done mark cap-cli-tools
  local out
  out="$(DRY_RUN=true migration_run "$MISE_TOOLS_MIGRATION" 2>&1)"
  assert_contains "$out" "Would execute: mise -C / install ripgrep@$(lock_version ripgrep)" || return 1
  [[ ! -e "$TEST_HOME/.local/bin/rg" && ! -e "$TEST_HOME/.config/mise/conf.d/teeup.toml" ]] || { echo "dry run changed the disk"; return 1; }
  [[ ! -e "$MARKS/$MISE_TOOLS_MIGRATION" ]] || { echo "dry run marked the migration"; return 1; }
  cleanup_test_env
}

# A failed or impossible move must not stop the update: every later
# teeup update runs mise_tools_sync from the new code and tries again.
test_mise_tools_migration_without_mise_lets_the_update_continue() {
  setup
  copy_mise_tools_migration
  mock_brew_with_everything
  export TEEUP_TEST_MISSING=mise
  state_done mark cap-cli-tools
  local out rc=0
  out="$(migration_run "$MISE_TOOLS_MIGRATION" 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "mise is not on PATH" || return 1
  assert_contains "$out" "The next teeup update tries again" || return 1
  assert_file_exists "$MARKS/$MISE_TOOLS_MIGRATION" || return 1
  unset TEEUP_TEST_MISSING
  cleanup_test_env
}
```

Register:

```bash
run_test "mise tools migration links the tools and keeps the Homebrew copies" test_mise_tools_migration_links_the_tools_and_keeps_the_homebrew_copies
run_test "mise tools migration dry run changes nothing" test_mise_tools_migration_dry_run_changes_nothing
run_test "mise tools migration without mise lets the update continue" test_mise_tools_migration_without_mise_lets_the_update_continue
```

- [ ] **Step 2: Run and see them fail**

Run: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/lib/migrations.sh`
Expected: FAIL (`cp: cannot stat '.../migrations/1791459420.sh'`).

- [ ] **Step 3: Create the migration (by hand; do not run `teeup dev add-migration`)**

`migrations/1791459420.sh`:

```bash
#!/usr/bin/env bash
# The user tools move from the package manager to mise, at the versions in
# share/teeup/tools.lock (#112). From this release on, teeup update installs
# and links them on every run, but the update that brings this release still
# runs the previous release's code, which knows nothing of mise_tools. This
# migration does the first move with the new code: every installed
# capability's tools installed and linked into ~/.local/bin, then
# ~/.config/mise/conf.d/teeup.toml.
#
# The Homebrew or MacPorts copies stay installed. teeup update stops
# upgrading them, and teeup doctor prints the command that removes each one.
# A tool that does not install now (offline, a proxy) does not stop the
# update: the next teeup update tries again, and teeup doctor names it.
if ! cap_exists mise; then
  exit 0
fi
if ! mise_tools_sync; then
  warn "Some tools did not move to mise (the lines above say which). The next teeup update tries again; teeup doctor names each one."
fi
log "The Homebrew or MacPorts copies of these tools stay installed. teeup doctor prints the command that removes each one."
```

- [ ] **Step 4: Run and see them pass**

Run: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/lib/migrations.sh`, its bash 3.2 pass, and the full `./tests/run.sh` (the bootstrap suite marks every shipped migration applied, so it covers the new file too).
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add migrations/1791459420.sh tests/lib/migrations.sh
git commit -m "Migrate existing Macs to the pinned mise tools"
```

---

### Task 11: Documentation

**Files:**
- Modify: `docs/manual/src/runtimes.md:20-34` ("Homebrew or mise?")
- Modify: `docs/manual/src/updates.md:12-30` (the step table and the two paragraphs that cite step numbers), new section "Tool versions" before "## When something goes wrong"
- Modify: `docs/manual/src/doctor-and-troubleshooting.md:13` ("What doctor checks"), two new subsections before "### Commits are not signed"
- Modify: `docs/manual/src/the-teeup-command.md:28,42`
- Modify: `CONTRIBUTING.md` steps 2, 6, 24
- Modify: `share/agents/skills/teeup/SKILL.md:92-93`
- Modify: `CHANGELOG.md` (`[Unreleased]`)
- Test: `tests/docs.sh` (no new test; it already checks STE limits, plain language, verbs and paths)

**Interfaces:** none.

- [ ] **Step 1: Run the docs suite as the baseline**

Run: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/docs.sh`
Expected: PASS before any edit.

- [ ] **Step 2: Manual, Runtimes**

Replace the "## Homebrew or mise?" section (from its heading to the line before "## Where the versions live") with:

```markdown
## Homebrew or mise?

teeup uses two sources. The tools that teeup itself needs come from Homebrew or MacPorts. The tools that you use come from mise, at the versions of the teeup release.

| Source | Tools |
|---|---|
| Homebrew or MacPorts | mise, git, the GitHub CLI, gum, jq, zsh and its plugins, curl, wget, tree, GnuPG, btop, Colima and Docker, and every app |
| mise, at the versions of the release | ripgrep, fd, fzf, bat, eza, zoxide, yq, tealdeer (`tldr`), dust, delta, git-lfs, lazygit, Starship, Neovim, tmux, Herdr, and the Ollama command |
| mise, at the versions that you choose | Language runtimes, the AI command-line tools, and every tool that you add with `mise use -g` |

The file `share/teeup/tools.lock` in the teeup checkout records the versions of the second row. A new teeup release can change these versions. teeup installs each tool with mise and puts a link to it in `~/.local/bin`. A command then starts the tool directly, without mise, so it starts as fast as a Homebrew copy.

teeup records the same versions in `~/.config/mise/conf.d/teeup.toml`, so `mise prune` keeps them. teeup never edits your `~/.config/mise/config.toml`. If you set a version for one of these tools in your own file, a shell that runs `mise activate` uses your version.

Language runtimes come from mise because projects need different versions. Each project specifies its versions in `mise.toml`, and `mise activate` changes between them when you change directories. mise downloads each AI tool the first time that you run it.

A Mac with MacPorts gets the same tools from mise as a Mac with Homebrew. MacPorts has no casks, so with MacPorts, WezTerm and Emacs come from ports and teeup tells you to download the other apps yourself.

`teeup update` installs a new pinned version when a release changes it. It upgrades the Homebrew or MacPorts packages only when it moves teeup to a new commit. It also runs `mise upgrade` for the tools in your global mise configuration. See [Updates](updates.md).

Most capabilities accept a copy of their command that you installed a different way, such as your own jq, if its version command runs. A broken command or a stale shim on `PATH` does not replace the package. A file of your own at `~/.local/bin/rg`, or at the path of another pinned tool, stays, and teeup does not link that tool.

The GitHub CLI is an exception: teeup always installs its own `gh`, because git uses `gh` to sign in. `teeup doctor github` warns when a different `gh` comes first on `PATH`. If you add a tool to mise yourself with `mise use -g`, you must control that tool yourself.
```

- [ ] **Step 3: Manual, Updates**

Replace the step table and the two paragraphs after it (from `| Step | What happens |` to the paragraph that starts "Step 5 applies the changed answers.") with:

```markdown
| Step | What happens |
|---|---|
| 1. Checkout | `git fetch` downloads the new releases and commits of teeup. Then teeup moves the checkout forward on its channel: to the newest release, or to the newest commit on `main`. See [Release or main](#release-or-main). |
| 2. Packages | `brew update` runs (with MacPorts, `port selfupdate`). If step 1 moved the checkout to a new commit, `brew upgrade` (with MacPorts, `port upgrade`) upgrades only the packages and casks that teeup installed. If the checkout did not move, their versions stay as they are. teeup does not upgrade other Homebrew packages: use `brew upgrade` for them. A package that a capability uses belongs to teeup, so teeup upgrades it even if you installed it before teeup. A future version will let you choose (issue #79). |
| 3. mise | `mise upgrade` runs for every tool in the global mise configuration, which includes the language runtimes and the AI tools. |
| 4. Pinned tools | For every installed capability, teeup installs the tools that `share/teeup/tools.lock` names, at the versions of the release, and links them into `~/.local/bin`. See [Tool versions](#tool-versions). |
| 5. Migrations | teeup runs every migration script that this Mac did not run yet. |
| 6. Configure | The `configure` script runs again for every installed capability in the core tier, and then in the daily tier. |
| 7. Theme | If step 6 did not render the current theme, teeup renders it again. |
| 8. Hooks | Your `post-update` hooks run (see [Hooks and extending](hooks-and-extending.md)). |

The migrations run after the upgrades, because a migration adjusts a configuration file for a new tool version and must see the newly installed version.

Step 6 applies the changed answers. If you set a new Emacs flavor with `teeup config set`, `teeup update` applies it because Emacs is in the daily tier.
```

In "## What it leaves alone", replace:

```markdown
- **Lazy capabilities.** Their `configure` step does not run again, because it can start a virtual machine (for example, Colima). Step 2 upgrades their packages.
```

with:

```markdown
- **Lazy capabilities.** Their `configure` step does not run again, because it can start a virtual machine (for example, Colima). Steps 2 and 4 upgrade their packages and their pinned tools.
```

In "## When something goes wrong", replace `| A migration fails | At step 4, after the pull, the package upgrades, and `mise upgrade` ran. |` with:

```markdown
| A migration fails | At step 5, after the pull, the package upgrades, `mise upgrade`, and the pinned tools ran. |
```

Insert before "## When something goes wrong":

```markdown
## Tool versions

A teeup release sets the version of each tool that comes from mise. The file `share/teeup/tools.lock` records these versions. The tools change only when `teeup update` moves teeup to a release with a different file. If teeup stays on the same release, `teeup update` installs no new tool versions.

When a release changes a version, step 4 installs the new version and changes the link in `~/.local/bin`. The old version stays installed. Run `mise prune` to remove the versions that nothing uses.

Homebrew cannot keep a formula at a fixed version. Thus teeup upgrades the packages that it installed only when the checkout moves to a new commit. On the release channel, this is a new release. On `main`, this is a new commit.
```

- [ ] **Step 4: Manual, Doctor and troubleshooting**

Replace:

```markdown
For each installed capability, doctor prints a heading `== git: ... ==` and checks that the packages, casks, and apps that its metadata names are installed.
```

with:

```markdown
For each installed capability, doctor prints a heading `== git: ... ==` and checks that the packages, casks, and apps that its metadata names are installed.
It also checks that each tool from mise has its link in `~/.local/bin`, at the version of the teeup release, and that the tool runs.
```

Insert before "### Commits are not signed":

```markdown
### Doctor says that Homebrew still has an old copy of a tool

In teeup 0.3.0-beta and older, Homebrew or MacPorts installed tools such as ripgrep, Starship, and Neovim. Now mise installs them at the versions of the teeup release. The old copies stay installed, and `teeup update` does not upgrade them.

Doctor shows a warning for each old copy, with the command that removes it, for example `brew uninstall ripgrep`. The warning does not change the exit status. teeup does not remove the old copies itself.

### A tool link in `~/.local/bin` is missing or broken

`mise uninstall` and `mise prune` can remove the version that a link in `~/.local/bin` points to. Doctor then reports the link as broken. Run the fix that doctor shows, for example `teeup configure cli-tools`. This command installs the pinned version again and repairs the link.
```

- [ ] **Step 5: Manual, the teeup command**

Replace:

```markdown
- **`teeup remove <capability>`** runs the `remove` script of the capability, if it has one, and then uninstalls the casks and packages that its metadata lists.
```

with:

```markdown
- **`teeup remove <capability>`** runs the `remove` script of the capability, if it has one, and then uninstalls the casks and packages that its metadata lists.
  It also removes the links of the tools that it installed through mise, and uninstalls their pinned versions.
```

and replace:

```markdown
  The command refuses to run if another installed capability requires this one, or if the capability does not have a `remove` script, packages, or casks.
```

with:

```markdown
  The command refuses to run if another installed capability requires this one, or if the capability does not have a `remove` script, packages, casks, or tools from mise.
```

- [ ] **Step 6: CONTRIBUTING, the skill, the CHANGELOG**

`CONTRIBUTING.md` step 2: replace

```markdown
   `group`, `tier` (`core|daily|lazy`), `requires`, `provides`, `packages`,
   `casks`, `apps`, `interactive`.
```

with:

```markdown
   `group`, `tier` (`core|daily|lazy`), `requires`, `provides`, `packages`,
   `package_commands`, `mise_tools`, `casks`, `apps`, `interactive`.
```

Step 6: replace its first five lines

```markdown
6. Homebrew or mise: put a tool in `packages` (Homebrew, or MacPorts) when one
   current version for the whole Mac is right, which is almost everything.
   Use mise only for a tool people need several versions of, as `dev-env`
   does for language runtimes, or one mise fetches on first call, as the
   `ai-*` capabilities do. The manual states the rule for users in
   [Runtimes](docs/manual/src/runtimes.md#homebrew-or-mise).
```

with:

```markdown
6. Homebrew or mise (#112): what teeup itself needs comes from the package
   manager (`packages`): the package manager, mise, git, gh, gum and jq, the
   zsh layer, anything mise has no package for (curl, wget, tree, gnupg),
   anything with no macOS build upstream (btop), colima with its lima
   dependency, and every cask. The tools the user uses come from mise at
   exact versions: list them as `mise_tools="<tool>:<command> ..."`, give
   each tool one line in `share/teeup/tools.lock` (`<tool> <version>`, plus
   the backend as a third field when the registry's first choice is not an
   `aqua:` source), add `mise` to `requires`, and call
   `mise_tools_apply "$TEEUP_CAP"` from `install` and
   `mise_tools_repair "$TEEUP_CAP"` from `configure`. `mise_tool_install`
   links `~/.local/bin/<command>` to the pinned binary, so a call starts no
   mise process. `cap_check` rejects a malformed pair, a tool with no lock
   line, a tool or command two capabilities claim, and a capability with
   mise tools that does not require mise. Language runtimes stay with
   `teeup install dev-env`, and the `ai-*` wrappers stay as they are. The
   manual states the rule for users in
   [Runtimes](docs/manual/src/runtimes.md#homebrew-or-mise).
```

Step 24: replace

```markdown
24. `teeup remove <cap>` uninstalls the `casks` and `packages` your metadata
    names and clears the done marker. Add a `remove` script only for machine
```

with:

```markdown
24. `teeup remove <cap>` uninstalls the `casks` and `packages` your metadata
    names, removes the links of its `mise_tools` and uninstalls their pinned
    versions, and clears the done marker. Add a `remove` script only for machine
```

`share/agents/skills/teeup/SKILL.md`: replace

```text
packages="neovim"       # pkg_install candidates; drive the generic update and remove
package_commands="neovim:nvim"  # accept this command when it is on PATH and its version probe runs (omit to always install)
```

with:

```text
packages=""             # pkg_install candidates; drive the generic update and remove
package_commands=""     # <package>:<command> accepted when on PATH and its version probe runs
mise_tools="neovim:nvim"  # user tools at the versions in share/teeup/tools.lock, linked into ~/.local/bin (CONTRIBUTING step 6)
```

`CHANGELOG.md`, under `## [Unreleased]`:

```markdown
### Changed
- **User tools come from mise, at the versions of the release (#112).** ripgrep, fd, fzf, bat, eza, zoxide, yq, tealdeer, dust, delta, git-lfs, lazygit, Starship, Neovim, tmux, Herdr and the Ollama command install through mise at the versions in `share/teeup/tools.lock`, and `~/.local/bin` links to each binary, so a call starts no mise process. `~/.config/mise/conf.d/teeup.toml` records the same versions, so `mise prune` keeps them. A release changes the lock; `teeup update` installs and links the new versions and leaves the old ones for `mise prune`. What teeup itself needs (mise, git, gh, gum, jq, the zsh layer), tools mise has no package for, btop, Colima and every cask stay with Homebrew or MacPorts.
- **`teeup update` upgrades Homebrew or MacPorts packages only when it moves teeup.** Formulae cannot be pinned, so an update that stays on the same commit leaves their versions where they are.
- **mise installs earlier.** It now comes right after `teeup-runtime` in the core tier, before zsh, Starship, cli-tools and git, which install their tools through it.
- **Ollama without its app.** When the `ollama-app` cask cannot install (macOS 13, MacPorts), the `ollama` command still comes from mise, and teeup says to start the server with `ollama serve`. The formula fallback is gone.

### Added
- **`mise_tools` capability field.** `<tool>:<command>` pairs, linted by `teeup commands --check`, removed by `teeup remove` and `teeup uninstall`, and checked by `teeup doctor`, which also names the old Homebrew or MacPorts copy of each tool with the command that removes it.
- **A migration for existing Macs.** It installs and links the pinned tools and keeps the package-manager copies.
```

- [ ] **Step 7: Run the docs suite and the full tree**

Run: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/docs.sh`, its bash 3.2 pass, and the full `./tests/run.sh`.
Expected: PASS. If the STE check names a sentence or paragraph, split it; do not change the checker.

- [ ] **Step 8: Commit**

```bash
git add docs/manual/src CONTRIBUTING.md share/agents/skills/teeup/SKILL.md CHANGELOG.md
git commit -m "Document the pinned mise tools"
```

---

## Spec coverage

| Spec item | Task |
|---|---|
| The split (package manager vs mise), `ollama-app` stays a cask, jq only in the first group | 8 |
| `share/teeup/tools.lock`, `<mise tool> <version>`, changed in the release PR | 1 |
| Lock/metadata agreement test | 8 |
| `mise_tools` field; tools leave `packages`/`package_commands` | 8 |
| `cap_check`: pairs well formed, each tool has a lock line, no command in two capabilities | 2 |
| Capabilities that now have only `mise_tools` gain `requires=mise` | 5 (all seven, Decision 2) |
| core.list: `mise` after `teeup-runtime`, before zsh, starship, cli-tools, git | 5 |
| `mise_tools_conf_write`, teeup marker, user's config.toml never edited, prune keeps pins | 3 |
| `mise_tool_install` 1-4 (lock, install if needed, `which --tool`, link, foreign file kept) | 4 |
| `mise_tool_remove` (teeup's link only; with packages `mise uninstall`; conf.d rewrite) | 4, 6 (Decision 4) |
| Script instead of a link for a tool that needs it | 4 (`TEEUP_MISE_EXEC_SCRIPT_TOOLS`, empty) |
| Every call keeps `-C /` | 4 (`test_every_mise_call_runs_from_root`) |
| install runs `mise_tool_install` next to `pkg_install` | 8 |
| configure rewrites conf.d and repairs a missing link | 4 (`mise_tools_repair`), 8 |
| update: conf.d refresh, re-install/re-link changed versions, old version left | 4 (`mise_tools_sync`), 9 |
| `mise_upgrade` stays | 9 |
| `pkg_upgrade_all` only when `_update_checkout` moved the checkout | 9 |
| Lazy tools: shims stay, `cmd_lazy_run` reaches `mise_tool_install` through `cmd_install`, link wins after | 8 (tmux round trip) |
| PATH: `~/.local/bin` before Homebrew and MacPorts | unchanged in `zsh/default/env`; 4 adds it to `bin/teeup` and `bootstrap` |
| Doctor: ok, missing link, dangling link, old-copy notice per backend, shadowing checks keep working | 7 |
| Migration for existing Macs, copies stay, `pkg_upgrade_all` no longer names them | 10 (and 8 for the metadata that drops them) |
| `teeup remove` and `teeup uninstall` (links, conf.d, `--packages`, summary with mise commands) | 6 |
| MacPorts: same mise tools; `tldr`→`tealdeer` mapping no longer needed | 8 |
| Docs: Runtimes, Updates, Doctor, CONTRIBUTING step 6 and the field, CHANGELOG | 11 |
| Verification on a Mac | the section below (owner) |
| Out of scope: removing old copies, gh to mise, pinning formulae, MacPorts Compose v1 | not implemented |

---

## Verification on a Mac (owner)

On a Mac, before the release (the owner):

1. For each tool in the mise group:
   - `mise -C / install <tool>@<version>` works through `aqua:`, on Apple
     Silicon and on Intel;
   - the linked command runs;
   - Neovim, tmux and starship work through a link.
2. Order of `conf.d/teeup.toml` and `config.toml` under `mise activate`.
3. A work-network run: mise downloads through the CA bundle teeup exports.
4. On an existing Mac: the migration, the doctor notice, and that `rg`,
   `nvim` and `starship` resolve to `~/.local/bin`.

If step 1 shows a tool that does not run through a link, add its name to `TEEUP_MISE_EXEC_SCRIPT_TOOLS` in `lib/mise.sh`; nothing else changes.
