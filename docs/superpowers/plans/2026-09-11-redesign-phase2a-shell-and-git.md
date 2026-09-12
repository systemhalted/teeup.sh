# teeup Redesign, Phase 2a: Shell and Git Group Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the phase 1 follow-ups in the shared libraries, then build the shell and git half of the core tier: `secrets`, `zsh`, `starship`, `cli-tools`, `git`, `ssh`, `github` and `mise`. After this plan a fresh Mac gets a working login shell with teeup's layered zsh configuration, a prompt, the modern CLI set, both git identities with SSH signing, keys uploaded to GitHub, and mise ready for the lazy runtimes of phase 3.

**Architecture:** Every capability is a directory under `capabilities/` with a sourced `capability` metadata file and `install`/`configure` scripts run by `cap_run` as `bash -eu` with `lib/all.sh` preloaded and the answers file sourced. Configuration follows the three-owner model: `capabilities/<cap>/config/` is copied once into `~/.config` and belongs to the user, `capabilities/<cap>/home/` is copied once into `$HOME` under its literal dotfile name, and `capabilities/<cap>/default/` stays teeup-owned and is sourced at runtime through `$TEEUP_PATH`. The thin `~/.zshrc`, `~/.zprofile` and `~/.zshenv` source the default layer; user additions go below them or in `~/.config/zsh/local.zsh`.

**Tech Stack:** bash 3.2 (macOS stock) for everything teeup runs, zsh 5.9 (macOS stock) for the shipped shell layer, TOML for starship and mise, gitconfig INI for git, shellcheck, Homebrew or MacPorts, the phase 1 mock harness.

**Spec:** `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md`. This plan covers spec sections 5 (core list entries `zsh starship cli-tools secrets git ssh github mise`), 7 (secrets, shipped configs, defaults, git extras) and 8 (identity as a directory rule: `includeIf` plus one SSH key per identity).

**Sibling plan:** `docs/superpowers/plans/2026-09-11-redesign-phase2b-desktop.md` (writer B) builds the desktop half: `lib/macos.sh`, `lib/theme.sh`, `theme`, `fonts`, `wezterm`, `aerospace`, `keyboard`, `macos-defaults`. **2b depends on 2a** for the Task 1 library fixes and for the `zsh` capability, which exports `TEEUP_APPEARANCE` and sources the generated theme environment (contract fixed in Task 3 below). **2a depends on nothing in 2b** and can land first. The files both plans modify are `capabilities/core.list` (2a appends its eight names, 2b appends its six after them), `tests/bootstrap.sh` (both add mocks to its `setup`, in disjoint lines) and `README.md`/`CONTRIBUTING.md` in the final task of each.

**Why `tests/bootstrap.sh` appears in eight of these ten tasks:** `bootstrap --dry-run` runs `run_tier core`, and `tests/bootstrap.sh` runs `bootstrap --dry-run`. So the moment a capability's name lands in `capabilities/core.list`, that capability's `install` and `configure` execute inside the bootstrap suite, under *that* suite's mocks — not its own. A core failure is fatal there (`bootstrap:84`), so any macOS-only command a new capability reads outside `run_cmd` turns the suite red on Linux. Every task below that touches `core.list` extends `tests/bootstrap.sh`'s `setup()` in the same task, and its run step names the bootstrap suite explicitly.

## Global Constraints

- Bash 3.2 compatible everywhere: no `mapfile`, no `declare -A`, no `${var,,}`, no `${var^^}`, no `readarray`, no `readlink -f`. Never reference a variable assigned earlier on the same `local` line. Use `10#$n` for arithmetic on user-typed numbers. Empty arrays expand as `${arr[@]+"${arr[@]}"}`.
- macOS BSD tools: no GNU-only flags for `sed`, `date`, `mktemp`, `diff`, `cmp`, `sort`, `grep`, `readlink`, `stat`. Tests run on Linux too; the product runs on macOS.
- Every mutation of the machine goes through `run_cmd` or `run_privileged`, so `DRY_RUN=true` changes nothing and prints `🔍 [DRY-RUN] Would execute: ...`. The one deliberate exception is `teeup secret set` (Task 2), which prints a redacted line itself so a secret never reaches the dry-run output or the bootstrap log.
- Capability scripts never call `sudo`; they use `run_privileged`. They are sourced, not executed, so they use no `local`, and they still start with `#!/usr/bin/env bash` so shellcheck parses them as bash.
- `capability` metadata is a sourced `KEY=value` file: `summary group tier requires provides packages casks apps interactive`. Not executable, no shebang. `provides` must not name a command macOS ships (`python3 ruby java git perl`).
- Shipped zsh fragments (`capabilities/*/default/*`, `capabilities/*/home/.*`) are zsh, not bash: shellcheck never runs on them, and CI's shellcheck globs (`capabilities/*/install capabilities/*/configure`) do not reach them. Keep them POSIX-shaped where the syntax allows it so a stray `sh` sourcing them still works.
- `shellcheck --severity=warning` clean on `bootstrap`, `bin/teeup`, `lib/*.sh`, every `capabilities/*/install|configure`, and `tests/**/*.sh`.
- `./tests/run.sh`, `./legacy/tests/run_tests.sh` and `./bin/teeup commands --check` must all be green before every commit.
- Commit subjects are plain imperative sentences. No `Co-Authored-By` or "Generated with" trailers (user's global CLAUDE.md).
- Nothing in this plan has been run on a real Mac yet. Each task's notes name what only a real run can prove.

## Decisions made in this plan

The brief left four choices open. They are settled here, together with four deviations from the brief's literal wording, and carried through every task.

| Decision | Choice | Why |
|---|---|---|
| Order of `git` and `mise` in `core.list` | Keep the spec's order: `... secrets git ssh github mise ...`. `mise` is **not** moved before `git`. | The spec's core list is the binding order and `git` genuinely does not need mise; only `pre-commit` does. Reordering the spec to satisfy one tool would be the tail wagging the dog. |
| Owner of `pre-commit` | The `mise` capability's `configure` (Task 9) installs it with `mise use -g pre-commit`. `git`'s configure only carries a comment saying so. | `pre-commit` is a mise-managed tool, so the capability that owns mise owns its tools; this keeps `git` runnable before mise exists and avoids a "deferred, re-run me later" branch that nothing would ever re-run. |
| Owner of `lazygit` | The `git` capability (`packages="git git-delta git-lfs lazygit"`). It is **removed** from `cli-tools`. | `packages=` drives the generic `update` and `remove` verbs, so a package listed under two capabilities has two owners and an ambiguous removal. lazygit is a git UI; it belongs with git. |
| `teeup secret` as a verb or a script | A first-class `secret` verb in `bin/teeup` (`cmd_secret`), with the `secrets` capability shipping only the doctor-ish `configure` check and the `teeup-env` zsh function. | The spec's CLI surface lists `teeup secret get|set|rm <name>` alongside the other verbs, and `bin/teeup` is already linked into `~/.local/bin`; a second script would need its own PATH entry and its own argument parsing for no gain. |
| Existing `~/.gitconfig` | Never touched. teeup writes `~/.config/git/config` (XDG) and `configure` warns once when `~/.gitconfig` exists, naming it and saying its keys win. | git reads both files with `~/.gitconfig` last, so a leftover file silently overrides teeup's settings; backing it up would break every tool that wrote to it through `git config --global`. A warning is honest and reversible. |
| Login shell | `/bin/zsh`, not the package manager's zsh. | `/bin/zsh` is Apple-signed, already listed in `/etc/shells`, and needs no privileged edit; a Homebrew zsh would need `/etc/shells` patched with sudo for `chsh` to accept it. |
| Both git identity files always written (brief: "work identity only when `TEEUP_WORK_EMAIL` is set") | Task 6 writes `identity-personal` and `identity-work` unconditionally; with no work email the work file carries the personal one. | An unused gitconfig include costs nothing, while a missing one leaves every repository under `~/Work` with no identity at all and `user.useConfigOnly = true` refusing to commit. `ssh` and `github` keep the brief's literal behaviour, because a spare key means a spare passphrase and a spare upload. |
| `IdentitiesOnly yes` per host, not in `Host *` (brief: listed with `AddKeysToAgent`/`UseKeychain`) | Task 7 sets it inside the two `github.com` blocks only. | In `Host *` it restricts *every* host to explicitly named keys, which breaks agent-forwarded and corporate hosts that rely on the agent's whole key set. |
| zsh plugin paths hardcoded (brief: "`$(pkg_prefix)`-relative") | Task 3 lists `/opt/local`, `/opt/homebrew`, `/usr/local` and `~/.local/share` explicitly. | `pkg_prefix` is a bash function in `lib/pkg.sh`; the zsh layer cannot call it without sourcing the whole library into every interactive shell. The four literal prefixes are exactly what `pkg_prefix` can return, plus a manual checkout. |
| Signing and the pager are switched on by a generated include, not by the shipped config | Task 6 ships `commit.gpgsign` / `core.pager = delta` defaults but lets `~/.config/git/teeup-generated` (included *after* them) turn both off when the key or the binary is missing. | Both settings are machine-wide and fail loudly: mandatory signing with no key makes every `git commit` fail, and `pager = delta` with no delta makes every `git log` fail. `ssh` runs after `git`, so on a first bootstrap the key genuinely does not exist yet. |

---

## File structure

| Path | Responsibility |
|---|---|
| `lib/core.sh` | Gains `user_config_dir` (Task 1). |
| `lib/answers.sh` | Hardened `answers_set` key guard; gains `answers_has_work`, `identity_list`, `identity_email`, `identity_key` (Task 1). |
| `lib/pkg.sh` | `pkg_install`/`cask_install` resolve the backend before anything else (Task 1). |
| `lib/capability.sh` | `_cap_visit` fails on an unknown `requires` (Task 1). |
| `lib/files.sh` | `refresh_config` stops swallowing the backup message (Task 1). |
| `bin/teeup` | `configure` honours `TEEUP_SKIP`; `list --tier` validates its value; new `secret` verb (Tasks 1, 2). |
| `capabilities/secrets/` | Keychain-backed secrets: `configure` check plus `default/functions.zsh` (`teeup-env`). |
| `capabilities/zsh/` | `home/.zshrc`, `home/.zprofile`, `home/.zshenv`, `config/zsh/local.zsh`, `default/{env,profile,rc,aliases,functions,init}`, login-shell switch. |
| `capabilities/starship/` | `config/starship.toml` with the `# teeup:theme-palette:` managed block 2b regenerates. |
| `capabilities/cli-tools/` | The modern CLI set plus `config/bat/config`. |
| `capabilities/git/` | `config/git/config`, generated identity files, delta, lfs, lazygit. |
| `capabilities/ssh/` | ed25519 key per identity, `config/ssh/config`, Keychain agent. |
| `capabilities/github/` | `gh auth login` and SSH key upload (authentication and signing). |
| `capabilities/mise/` | `config/mise/config.toml`, `upgrade.auto_prune false`, `pre-commit`. |
| `capabilities/core.list` | Grows to `... dev-dirs zsh starship cli-tools secrets git ssh github mise`. |
| `machines/.gitkeep` | Makes the only override layer discoverable (Task 1). |
| `tests/capabilities/{secrets,zsh,starship,cli-tools,git,ssh,github,mise}.sh` | One behavioural suite per capability. |
| `tests/bootstrap.sh` | Extended by Tasks 2 to 9: each adds the mocks its new core capability needs, because `bootstrap --dry-run` runs the whole core tier. |
| `.github/workflows/ci.yml` | Task 10 adds a zsh install step for the Linux runner; the shellcheck and test globs already cover everything else. |

---

### Task 1: Phase 1 follow-ups in the shared libraries

The phase 1 final review (`docs/superpowers/reviews/2026-09-11-redesign-phase1-final-review.md`) left 21 Minor findings after its four blocking fixes landed. These are the ones that touch `lib/`, `bin/teeup`, `bootstrap` or the runtime capability and that phase 2 code would otherwise inherit. The rest (M4, M9-M13, M15-M21) stay deferred and are listed in the self-review.

This task also adds the two shared helpers later tasks need: `user_config_dir` (used by `starship`, `cli-tools`, `git`, `mise`) and the identity helpers (used by `git`, `ssh`, `github`). Nothing macOS-specific is added here — `lib/macos.sh` and `launchagent_install` belong to plan 2b.

**Files:**
- Modify: `lib/answers.sh`, `lib/core.sh`, `lib/pkg.sh`, `lib/capability.sh`, `lib/files.sh`, `bin/teeup`, `bootstrap`, `capabilities/teeup-runtime/configure`
- Create: `machines/.gitkeep`
- Test: `tests/lib/answers.sh`, `tests/lib/core.sh`, `tests/lib/pkg.sh`, `tests/lib/capability.sh`, `tests/lib/files.sh`, `tests/cli.sh`, `tests/capabilities/teeup-runtime.sh` (all extended, none created)

**Interfaces:**
- Consumes: `answers_get`, `answers_file`, `die`, `run_cmd`, `backup_target`, `cap_exists`, `cap_meta_get`, `_pkg_backend_resolve`.
- Produces: `user_config_dir` (prints `${XDG_CONFIG_HOME:-$HOME/.config}`); `answers_has_work` (exit 0 when `TEEUP_WORK_EMAIL` is non-empty); `identity_list` (prints `personal`, and `work` when a work email exists); `identity_email <personal|work>`; `identity_key <personal|work>` (prints `$HOME/.ssh/id_ed25519_<identity>`, no `.pub`). Tasks 4, 5, 6, 7, 8 and 9 consume these.

- [ ] **Step 1: Harden the `answers_set` key guard (M2)**

In `lib/answers.sh`, replace the `case` guard and the `grep -v` filter inside `answers_set`. The glob `TEEUP_[A-Z0-9_]*)` accepts any suffix (`TEEUP_A.*` passes) and the key was then interpolated into a `grep` regex. Replace the body from the `case` through the `mv` with:

```bash
  if ! [[ "$key" =~ ^TEEUP_[A-Z0-9_]+$ ]]; then
    die "answers_set: key must look like TEEUP_NAME, got '$key'"
  fi
  export "$key=$value"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would set $key in $f"
    return 0
  fi
  mkdir -p "$(dirname "$f")"
  touch "$f"
  escaped="$(printf '%s' "$value" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\$/g' -e 's/`/\\`/g')"
  tmp="$(mktemp)"
  # Drop the old line for KEY with the shell rather than grep, so the key is
  # never interpreted as a regular expression.
  while IFS= read -r line; do
    case "$line" in "$key="*) continue ;; esac
    printf '%s\n' "$line"
  done < "$f" > "$tmp"
  printf '%s="%s"\n' "$key" "$escaped" >> "$tmp"
  sort -o "$tmp" "$tmp"
  mv "$tmp" "$f"
  chmod 600 "$f"
```

and widen the `local` line to carry the loop variable:

```bash
  local key="$1" value="$2" f tmp escaped line
```

`sort -o FILE FILE` is safe on both GNU and BSD sort (it reads the input fully before writing). The option must come **before** the operand: macOS `sort` uses BSD `getopt`, which stops at the first non-option argument, so `sort "$tmp" -o "$tmp"` would treat `-o` as a second input file and never write anything. `f="$(answers_file)"` stays where it is, above the guard.

- [ ] **Step 2: Add the identity helpers to `lib/answers.sh`**

Append to `lib/answers.sh`:

```bash
# Identity helpers. git, ssh and github all key off the same two identities,
# so the mapping from identity name to email and key path lives here once.
# Work exists only when the wizard was given a work email; otherwise both
# directory roots use the personal identity.
answers_has_work() { [[ -n "$(answers_get TEEUP_WORK_EMAIL)" ]]; }

identity_list() {
  printf 'personal\n'
  answers_has_work && printf 'work\n'
  return 0
}

identity_email() {
  case "$1" in
    personal) answers_get TEEUP_EMAIL ;;
    work)
      if answers_has_work; then answers_get TEEUP_WORK_EMAIL; else answers_get TEEUP_EMAIL; fi
      ;;
    *) die "identity_email: unknown identity '$1' (expected personal or work)" ;;
  esac
}

identity_key() {
  case "$1" in
    personal|work) printf '%s/.ssh/id_ed25519_%s\n' "$HOME" "$1" ;;
    *) die "identity_key: unknown identity '$1' (expected personal or work)" ;;
  esac
}
```

- [ ] **Step 3: Add `user_config_dir` to `lib/core.sh`**

`TEEUP_CONFIG_DIR` is teeup's own `~/.config/teeup`; capabilities need the parent to place another tool's config. Insert after the `is_macos`/`arch`/`macos_major` line group:

```bash
# The directory capabilities/<cap>/config/ maps onto. TEEUP_CONFIG_DIR is
# teeup's own subdirectory of this one.
user_config_dir() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}"; }
```

- [ ] **Step 4: Resolve the package backend before anything else (deferred item 13)**

In `lib/pkg.sh`, make `_pkg_backend_resolve` the first statement of both entry points so an invalid `TEEUP_PACKAGE_MANAGER` kills the caller instead of a `$( )` subshell. In `pkg_install`:

```bash
pkg_install() {
  _pkg_backend_resolve
  local pkg="$1" command_name="${2:-}" candidate
```

and in `cask_install`:

```bash
cask_install() {
  _pkg_backend_resolve
  local cask="$1"
```

- [ ] **Step 5: Fail on an unknown `requires` (M7)**

In `lib/capability.sh`, guard `_cap_visit` before it recurses:

```bash
_cap_visit() {
  local c="$1" r
  case "$_TEEUP_CAP_VISITED" in *" $c "*) return 0 ;; esac
  cap_exists "$c" || die "Unknown capability: $c"
  _TEEUP_CAP_VISITED="$_TEEUP_CAP_VISITED$c "
  for r in $(cap_meta_get "$c" requires); do _cap_visit "$r"; done
  printf '%s\n' "$c"
}
```

`die` inside `cap_order` still only kills the command substitution, so the caller must check the status. In `bin/teeup`, `cmd_install` captures the order first:

```bash
cmd_install() {
  local target="${1:-}" order c
  [[ -n "$target" ]] || die "Usage: teeup install <capability>"
  cap_exists "$target" || die "Unknown capability: $target"
  if cap_skipped "$target"; then
    die "$target is skipped on this machine (TEEUP_SKIP)"
  fi
  order="$(cap_order "$target")" || die "Cannot resolve what $target requires."
  for c in $order; do
    if cap_skipped "$c"; then
      warn "Skipping $c (TEEUP_SKIP)"
      continue
    fi
    cap_run "$c" install
    cap_run "$c" configure
    state_done mark "cap-$c"
  done
}
```

- [ ] **Step 6: `configure` honours `TEEUP_SKIP` (M6) and `list --tier` validates its value (M5)**

In `bin/teeup`, replace `cmd_configure` and the head of `cmd_list`. The `if` form matters: `cap_skipped "$t" && die ...` would return non-zero as the last command of the function under `set -e` and exit the whole dispatcher on the happy path.

```bash
cmd_configure() {
  local target="${1:-}"
  [[ -n "$target" ]] || die "Usage: teeup configure <capability>"
  cap_exists "$target" || die "Unknown capability: $target"
  if cap_skipped "$target"; then
    die "$target is skipped on this machine (TEEUP_SKIP)"
  fi
  cap_run "$target" configure
}

cmd_list() {
  local tier_filter="" name tier
  case "${1:-}" in
    "") ;;
    --tier)
      tier_filter="${2:-}"
      [[ -n "$tier_filter" ]] || die "Usage: teeup list [--tier core|daily|lazy]"
      case "$tier_filter" in
        core|daily|lazy) ;;
        *) die "Unknown tier '$tier_filter' (expected core, daily or lazy)" ;;
      esac
      ;;
    *) die "Usage: teeup list [--tier core|daily|lazy]" ;;
  esac
  for name in $(cap_list); do
    tier="$(cap_meta_get "$name" tier)"
    [[ -z "$tier_filter" || "$tier" == "$tier_filter" ]] || continue
    printf '%-18s %-6s %s\n' "$name" "$tier" "$(cap_meta_get "$name" summary)"
  done
}
```

- [ ] **Step 7: Never clobber a regular file at `~/.local/bin/teeup` (M1)**

In `capabilities/teeup-runtime/configure`, replace the link block:

```bash
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
```

- [ ] **Step 8: Show the backup path on refresh (M8)**

In `lib/files.sh`, `refresh_config` line 143, drop the redirection so the user sees where the backup went:

```bash
  backup="$(backup_target "$dest")"
```

`backup_target` already prints its message to stderr and the path to stdout, so the capture stays clean.

- [ ] **Step 9: Tell the user a working command at the end of bootstrap (M3)**

`~/.local/bin` is not on a stock macOS `PATH`; the `zsh` capability (Task 3) puts it there, but only for shells started afterwards. Replace the last line of `bootstrap`:

```bash
echo "Open a new terminal (the zsh capability puts ~/.local/bin on PATH) and try: teeup status"
echo "In this shell, use the full path: $HOME/.local/bin/teeup status"
```

- [ ] **Step 10: Ship the machines directory (M14)**

```bash
mkdir -p machines
printf '' > machines/.gitkeep
```

The README and CONTRIBUTING lines that explain it are folded into Task 10.

- [ ] **Step 11: Extend the library tests**

Append to `tests/lib/answers.sh`, before the `echo "lib/answers"` line:

```bash
test_set_rejects_a_key_with_regex_characters() {
  setup
  local rc=0 out
  out="$( (answers_set 'TEEUP_A.*' hi) 2>&1 )" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "key must look like TEEUP_NAME" || return 1
  cleanup_test_env
}

test_set_rejects_a_bare_prefix() {
  setup
  local rc=0
  ( answers_set 'TEEUP_' hi ) >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" || return 1
  cleanup_test_env
}

test_set_replaces_only_the_exact_key() {
  setup
  answers_set TEEUP_EMAIL "old@example.com"
  answers_set TEEUP_WORK_EMAIL "work@example.com"
  answers_set TEEUP_EMAIL "new@example.com"
  answers_load
  assert_equals "new@example.com" "$(answers_get TEEUP_EMAIL)" || return 1
  assert_equals "work@example.com" "$(answers_get TEEUP_WORK_EMAIL)" || return 1
  cleanup_test_env
}

test_identity_helpers_without_work_email() {
  setup
  answers_set TEEUP_EMAIL "ada@example.com"
  answers_set TEEUP_WORK_EMAIL ""
  answers_load
  assert_equals "personal" "$(identity_list)" || return 1
  assert_equals "ada@example.com" "$(identity_email personal)" || return 1
  assert_equals "ada@example.com" "$(identity_email work)" || return 1
  assert_equals "$HOME/.ssh/id_ed25519_personal" "$(identity_key personal)" || return 1
  cleanup_test_env
}

test_identity_helpers_with_work_email() {
  setup
  answers_set TEEUP_EMAIL "ada@example.com"
  answers_set TEEUP_WORK_EMAIL "ada@corp.example"
  answers_load
  assert_equals "personal
work" "$(identity_list)" || return 1
  assert_equals "ada@corp.example" "$(identity_email work)" || return 1
  assert_equals "$HOME/.ssh/id_ed25519_work" "$(identity_key work)" || return 1
  cleanup_test_env
}
```

and the matching `run_test` lines before `print_summary`:

```bash
run_test "set rejects a key with regex characters" test_set_rejects_a_key_with_regex_characters
run_test "set rejects a bare prefix" test_set_rejects_a_bare_prefix
run_test "set replaces only the exact key" test_set_replaces_only_the_exact_key
run_test "identity helpers without work email" test_identity_helpers_without_work_email
run_test "identity helpers with work email" test_identity_helpers_with_work_email
```

Append to `tests/lib/core.sh` (before its `echo "lib/core.sh"` line). That file has no shared `setup` helper: each test calls `setup_test_env` and sources the library itself, so this one does the same.

```bash
test_user_config_dir_follows_xdg() {
  setup_test_env
  source "$TEEUP_PATH/lib/core.sh"
  assert_equals "$TEST_HOME/.config" "$(user_config_dir)" || return 1
  # In a subshell, so XDG_CONFIG_HOME stays set for the rest of the file.
  assert_equals "$HOME/.config" "$(unset XDG_CONFIG_HOME; user_config_dir)" || return 1
  cleanup_test_env
}
```

```bash
run_test "user_config_dir follows XDG" test_user_config_dir_follows_xdg
```

Append to `tests/lib/pkg.sh`:

```bash
test_cask_install_dies_on_invalid_backend() {
  setup
  export TEEUP_PACKAGE_MANAGER=apt
  local rc=0 out
  out="$( (cask_install wezterm) 2>&1 )" || rc=$?
  assert_failure "$rc" "invalid backend must fail the caller" || return 1
  assert_contains "$out" "Unknown TEEUP_PACKAGE_MANAGER 'apt'" || return 1
  cleanup_test_env
}
```

```bash
run_test "cask_install dies on invalid backend" test_cask_install_dies_on_invalid_backend
```

Append to `tests/lib/capability.sh`:

```bash
test_cap_order_fails_on_unknown_requires() {
  setup
  make_cap orphan core "ghost"
  local rc=0 out
  out="$( (cap_order orphan) 2>&1 )" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Unknown capability: ghost" || return 1
  cleanup_test_env
}
```

```bash
run_test "cap_order fails on unknown requires" test_cap_order_fails_on_unknown_requires
```

`tests/lib/capability.sh:6` defines `make_cap <name> <tier> [requires] [provides]`, whose last two arguments are optional; reuse it as-is rather than adding a second fixture builder. This suite has 10 `run_test` lines today and 11 after this step — plan 2b also extends this file, so it should count from 11, not 10.

Append to `tests/lib/files.sh`:

```bash
test_refresh_prints_the_backup_path() {
  setup
  printf 'shipped\n' > "$TEST_HOME/src"
  printf 'mine\n' > "$TEST_HOME/dest"
  local out
  out="$(refresh_config "$TEST_HOME/src" "$TEST_HOME/dest" 2>&1)"
  assert_contains "$out" "Backed up $TEST_HOME/dest to" || return 1
  cleanup_test_env
}
```

```bash
run_test "refresh prints the backup path" test_refresh_prints_the_backup_path
```

Append to `tests/cli.sh`:

```bash
test_configure_refuses_skipped_capability() {
  setup
  local rc=0 out
  out="$(TEEUP_SKIP=alpha "$TEEUP" configure alpha 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "alpha is skipped on this machine (TEEUP_SKIP)" || return 1
  cleanup_test_env
}

test_list_tier_without_a_value_errors() {
  setup
  local rc=0 out
  out="$("$TEEUP" list --tier 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Usage: teeup list [--tier core|daily|lazy]" || return 1
  out="$("$TEEUP" list --tier nope 2>&1)" || rc=$?
  assert_contains "$out" "Unknown tier 'nope'" || return 1
  cleanup_test_env
}
```

```bash
run_test "configure refuses skipped capability" test_configure_refuses_skipped_capability
run_test "list --tier without a value errors" test_list_tier_without_a_value_errors
```

Append to `tests/capabilities/teeup-runtime.sh`:

```bash
test_configure_backs_up_a_regular_file_at_the_link() {
  setup
  mkdir -p "$TEST_HOME/.local/bin"
  printf 'mine\n' > "$TEST_HOME/.local/bin/teeup"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure teeup-runtime 2>&1)"
  assert_contains "$out" "Replacing a regular file" || return 1
  assert_equals "$TEEUP_PATH/bin/teeup" "$(readlink "$TEST_HOME/.local/bin/teeup")" || return 1
  # A glob loop, not `ls | grep`: shellcheck rejects the latter (SC2010).
  local backup="" f
  for f in "$TEST_HOME"/.local/bin/teeup.teeup_backup_*; do
    [[ -e "$f" ]] && backup="$f"
  done
  [[ -n "$backup" ]] || { echo "no backup kept"; return 1; }
  cleanup_test_env
}
```

```bash
run_test "configure backs up a regular file at the link" test_configure_backs_up_a_regular_file_at_the_link
```

- [ ] **Step 12: Run everything**

Run: `./tests/run.sh && ./bin/teeup commands --check && shellcheck --severity=warning bootstrap bin/teeup lib/*.sh capabilities/*/install capabilities/*/configure tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh tests/lib/*.sh tests/capabilities/*.sh`
Expected: `All 13 suites passed.`, then no output from `commands --check` and none from shellcheck.

- [ ] **Step 13: Commit**

```bash
git add lib bin/teeup bootstrap capabilities/teeup-runtime/configure machines tests
git commit -m "Close the phase 1 minor findings and add the identity helpers"
```

**Real-Mac risk:** none of these paths are macOS-specific. The `chmod 600` in `answers_set` and the `sort -o` rewrite are the only file operations changed, and both are BSD-safe.

---

### Task 2: `secrets` capability and the `teeup secret` verb

Spec section 7: secrets live in the macOS login Keychain under service `teeup`, never in the repo or the answers file. `teeup secret get|set|rm <name>` is the interface; the `teeup-env` zsh function exports one secret into the current shell.

**Files:**
- Create: `capabilities/secrets/capability`, `capabilities/secrets/install`, `capabilities/secrets/configure`, `capabilities/secrets/default/functions.zsh`
- Modify: `bin/teeup`, `capabilities/core.list`, `tests/bootstrap.sh`
- Test: `tests/capabilities/secrets.sh`

**Interfaces:**
- Consumes: `have`, `die`, `ok`, `log`, `warn`, `run_cmd`, `ui_input` (from `lib/ui.sh`), `state_done`.
- Produces: `teeup secret get <name>` (prints the secret on stdout, exit 1 when absent), `teeup secret set <name>` (reads the value from `ui_input`, i.e. stdin in tests), `teeup secret rm <name>`; and `capabilities/secrets/default/functions.zsh` defining `teeup-env`, which Task 3's `default/rc` sources by name.

- [ ] **Step 1: Write the failing test**

`tests/capabilities/secrets.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  export TEEUP_NO_GUM=1
  TEEUP="$TEEUP_PATH/bin/teeup"
}

# A Keychain that remembers one item, so get/set/rm can be checked end to end.
mock_security_store() {
  mock_command_script security <<'EOF2'
store="$HOME/keychain"
case "$1" in
  find-generic-password)
    [ -f "$store" ] || exit 44
    cat "$store"
    ;;
  add-generic-password)
    shift
    while [ $# -gt 0 ]; do
      if [ "$1" = "-w" ]; then shift; printf '%s\n' "$1" > "$store"; fi
      shift
    done
    ;;
  delete-generic-password)
    [ -f "$store" ] || exit 44
    rm -f "$store"
    ;;
esac
EOF2
}

test_set_then_get_round_trips() {
  setup
  mock_security_store
  printf 's3cret\n' | "$TEEUP" secret set openai_api_key >/dev/null
  assert_equals "s3cret" "$("$TEEUP" secret get openai_api_key)" || return 1
  # Asserting a plaintext value in a log looks wrong next to this capability's
  # whole point. It is deliberate: MOCK_LOG is the harness's record of how the
  # mock was called, inside a temp $HOME, with a fake value. It is what proves
  # the real `security` would receive the right arguments. Do not "fix" it by
  # dropping -w from the mock.
  assert_contains "$(cat "$MOCK_LOG")" "add-generic-password -U -s teeup -a openai_api_key -w s3cret" || return 1
  cleanup_test_env
}

test_get_missing_secret_fails_with_a_hint() {
  setup
  mock_command security 44 ""
  local rc=0 out
  out="$("$TEEUP" secret get nope 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "teeup secret set nope" || return 1
  cleanup_test_env
}

test_rm_deletes_the_item() {
  setup
  mock_security_store
  printf 's3cret\n' | "$TEEUP" secret set gh_token >/dev/null
  "$TEEUP" secret rm gh_token >/dev/null
  local rc=0
  "$TEEUP" secret get gh_token >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" || return 1
  cleanup_test_env
}

test_set_never_prints_the_value_in_dry_run() {
  setup
  mock_security_store
  local out
  out="$(printf 's3cret\n' | DRY_RUN=true "$TEEUP" secret set gh_token 2>&1)"
  assert_contains "$out" "Would execute: security add-generic-password -U -s teeup -a gh_token -w <value>" || return 1
  assert_not_contains "$out" "s3cret" || return 1
  [[ ! -e "$TEST_HOME/keychain" ]] || { echo "dry run wrote to the keychain"; return 1; }
  cleanup_test_env
}

test_set_refuses_an_empty_value() {
  setup
  mock_security_store
  local rc=0 out
  out="$(printf '\n' | "$TEEUP" secret set empty 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Refusing to store an empty value" || return 1
  cleanup_test_env
}

test_usage_without_a_name() {
  setup
  local rc=0 out
  out="$("$TEEUP" secret get 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Usage: teeup secret get|set|rm <name>" || return 1
  cleanup_test_env
}

test_configure_reports_the_keychain_is_usable() {
  setup
  mock_security_store
  local out
  out="$(DRY_RUN=false "$TEEUP" configure secrets)"
  assert_contains "$out" "Keychain service 'teeup' is ready" || return 1
  cleanup_test_env
}

test_configure_twice_is_a_no_op() {
  setup
  mock_security_store
  DRY_RUN=false "$TEEUP" configure secrets >/dev/null
  local marker="$TEST_HOME/.idempotency-marker"
  : > "$marker"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure secrets)"
  assert_contains "$out" "Keychain service 'teeup' is ready" || return 1
  # Nothing under $HOME may change on the second run. mock.log and the marker
  # itself are the harness's own bookkeeping.
  local changed
  changed="$(find "$TEST_HOME" -newer "$marker" -type f \
    ! -name 'mock.log' ! -name '.idempotency-marker' 2>/dev/null)"
  assert_equals "" "$changed" "second configure must write nothing" || return 1
  cleanup_test_env
}

test_teeup_env_function_is_shipped_and_parses() {
  setup
  local f="$TEEUP_PATH/capabilities/secrets/default/functions.zsh"
  assert_file_exists "$f" || return 1
  assert_contains "$(cat "$f")" "teeup-env()" || return 1
  # A grep alone would pass on a syntactically broken function. zsh is
  # installed on every runner this suite targets (CI installs it on Linux).
  if ! command -v zsh >/dev/null 2>&1; then
    echo "zsh is required to syntax-check the shipped function"
    return 1
  fi
  zsh -n "$f" || { echo "functions.zsh does not parse"; return 1; }
  cleanup_test_env
}

echo "capabilities/secrets"
run_test "set then get round trips" test_set_then_get_round_trips
run_test "get missing secret fails with a hint" test_get_missing_secret_fails_with_a_hint
run_test "rm deletes the item" test_rm_deletes_the_item
run_test "set never prints the value in dry run" test_set_never_prints_the_value_in_dry_run
run_test "set refuses an empty value" test_set_refuses_an_empty_value
run_test "usage without a name" test_usage_without_a_name
run_test "configure reports the keychain is usable" test_configure_reports_the_keychain_is_usable
run_test "configure twice is a no-op" test_configure_twice_is_a_no_op
run_test "teeup-env function is shipped and parses" test_teeup_env_function_is_shipped_and_parses
print_summary
```

Run: `bash tests/capabilities/secrets.sh`
Expected: every test fails with `Unknown verb: secret` or `Unknown capability: secrets`.

- [ ] **Step 2: Add the `secret` verb to `bin/teeup`**

Insert `cmd_secret` after `cmd_has`:

```bash
# Secrets live in the login Keychain under the service name "teeup"; nothing
# secret ever reaches the repo, the answers file or a log. `set` is the one
# mutation in teeup that does not go through run_cmd: run_cmd echoes its whole
# argument list in dry run, and the value must not appear there.
cmd_secret() {
  local op="${1:-}" name="${2:-}" value
  case "$op" in
    get|set|rm) ;;
    *) die "Usage: teeup secret get|set|rm <name>" ;;
  esac
  [[ -n "$name" ]] || die "Usage: teeup secret get|set|rm <name>"
  have security || die "teeup secret needs macOS's security command."
  case "$op" in
    get)
      security find-generic-password -s teeup -a "$name" -w 2>/dev/null ||
        die "No secret named '$name'. Store one with: teeup secret set $name"
      ;;
    set)
      value="$(ui_input "Value for $name")"
      [[ -n "$value" ]] || die "Refusing to store an empty value for '$name'."
      if [[ "$DRY_RUN" == "true" ]]; then
        printf "%b %s\n" "🔍" "[DRY-RUN] Would execute: security add-generic-password -U -s teeup -a $name -w <value>"
        return 0
      fi
      security add-generic-password -U -s teeup -a "$name" -w "$value" >/dev/null ||
        die "Could not store '$name' in the Keychain."
      ok "Stored $name in the Keychain (service: teeup)"
      ;;
    rm)
      # No >/dev/null here: that would swallow run_cmd's own dry-run line.
      if ! run_cmd security delete-generic-password -s teeup -a "$name"; then
        die "No secret named '$name'."
      fi
      ok "Removed $name from the Keychain"
      ;;
  esac
}
```

Add the dispatch line next to `has`:

```bash
  secret) cmd_secret "$@" ;;
```

and the help line in `usage()`, after the `has` line:

```text
  teeup secret get|set|rm <name>  read, store or delete a Keychain secret
```

- [ ] **Step 3: Write `capabilities/secrets/`**

`capability`:

```sh
summary="Secrets in the macOS Keychain (teeup secret, teeup-env)"
group=system
tier=core
requires="teeup-runtime"
provides=""
packages=""
casks=""
apps=""
interactive=false
```

`install`:

```bash
#!/usr/bin/env bash
# Nothing to install: /usr/bin/security is part of macOS. The file exists so
# `teeup install secrets` is a recorded no-op rather than an error.
:
```

`configure`:

```bash
#!/usr/bin/env bash
# Confirm the Keychain is reachable and tell the user the two entry points.
# A read of a name that cannot exist is enough: exit 44 means "no such item",
# which is the healthy answer here.
#
# A missing `security` warns and returns 0 rather than failing, exactly like
# github and mise do for a missing prerequisite. This capability installs
# nothing and its whole job is to print two hints; aborting here would take
# git, ssh, github and mise down with it, since run_tier treats a core failure
# as fatal. On a real Mac /usr/bin/security always exists.
if ! have security; then
  warn "security is missing (not a macOS machine?); skipping the Keychain check."
  exit 0
fi
security find-generic-password -s teeup -a teeup-selftest -w >/dev/null 2>&1 || true
ok "Keychain service 'teeup' is ready."
log "Store a secret:    teeup secret set <name>"
log "Use one in a shell: teeup-env <name>   (exports it for this shell only)"
```

`default/functions.zsh`:

```zsh
# teeup-env <secret-name> [VARIABLE]
# Exports one Keychain secret into the current shell and nowhere else. With no
# VARIABLE the secret name is upper-cased, so `teeup-env openai_api_key` sets
# OPENAI_API_KEY. Sourced by capabilities/zsh/default/rc.
teeup-env() {
  local name="$1" var value
  if [[ -z "$name" ]]; then
    print -u2 "usage: teeup-env <secret-name> [VARIABLE]"
    return 2
  fi
  var="${2:-${(U)name}}"
  value="$(teeup secret get "$name")" || return 1
  export "$var=$value"
  print "exported $var from the teeup Keychain"
}
```

- [ ] **Step 4: Add `secrets` to the core list**

`capabilities/core.list` becomes (the comment line changes too):

```text
# Core tier: what every terminal session needs. Ordered; each entry's
# requires= must already be satisfied by the entries above it.
# Later phases append: wezterm fonts aerospace keyboard macos-defaults theme
xcode-clt
package-manager
teeup-runtime
dev-dirs
secrets
```

Every later task **inserts** its capability at the position the spec's core list gives (`xcode-clt package-manager teeup-runtime dev-dirs zsh starship cli-tools secrets git ssh github mise wezterm fonts aerospace keyboard macos-defaults theme`) rather than appending, so the file is in spec order after every commit and `cap_check` stays green task by task. `secrets` is the first of this plan's entries to land and is simply the last line today; Tasks 3, 4 and 5 insert `zsh`, `starship` and `cli-tools` **above** it.

- [ ] **Step 5: Teach the bootstrap suite about `secrets`**

`tests/bootstrap.sh` runs `bootstrap --dry-run`, which from this commit on runs `secrets configure` too. Add one line to its `setup()`, after the `brew` mock:

```bash
  # /usr/bin/security is macOS-only; 44 is its "no such item" exit code.
  mock_command security 44 ""
```

Every task from here to Task 9 adds one such block for the capability it puts in the manifest. Without them the bootstrap suite runs the new capability against the unmocked host.

- [ ] **Step 6: Run everything**

```bash
chmod +x capabilities/secrets/install capabilities/secrets/configure
./tests/run.sh
./bin/teeup commands --check
shellcheck --severity=warning bin/teeup capabilities/secrets/install capabilities/secrets/configure tests/capabilities/secrets.sh tests/bootstrap.sh
```

Expected: `All 14 suites passed.`, **including `bootstrap.sh`, whose twelve tests must still pass** now that the core tier has a ninth entry; no output from `commands --check`, no output from shellcheck.

- [ ] **Step 7: Commit**

```bash
git add bin/teeup capabilities/secrets capabilities/core.list tests/capabilities/secrets.sh tests/bootstrap.sh
git commit -m "Add the secrets capability and the teeup secret verb"
```

**Real-Mac risk:** the first `teeup secret set` triggers a Keychain unlock prompt, and macOS may ask to allow `security` access to the item on the first `get` from a different binary path. Neither can be exercised under mocks.

---

### Task 3: `zsh` capability

The shell layer every later capability leans on. Spec section 7: a thin `~/.zshrc` sources a thick teeup-owned default layer, user additions go below. The content is ported from the chezmoi repo's `~/.config/shell/{envs,aliases,functions,init}` and `~/.config/zsh/rc`, and from Omarchy's `default/bash/*`, with Powerlevel10k, SDKMAN, rbenv and pyenv dropped (Starship replaces the first, mise the rest) and the machine-specific Emacs-package-checkout loop moved to the user file.

**Contracts this task fixes for plan 2b** (2b's `theme` capability depends on both):

1. `TEEUP_APPEARANCE` is exported by `capabilities/zsh/default/rc` as exactly `dark` or `light`, derived from `defaults read -g AppleInterfaceStyle` (exit 1 means light), guarded so a child shell inherits it instead of forking `defaults` again.
2. Immediately afterwards, `default/rc` sources `$TEEUP_STATE_DIR/current/theme/$TEEUP_APPEARANCE/env.sh` when that file is readable, where `TEEUP_STATE_DIR` is `${XDG_STATE_HOME:-$HOME/.local/state}/teeup` — the same formula `lib/core.sh` uses. It is sourced after `BAT_THEME` gets its default, so the generated file wins.

**Files:**
- Create: `capabilities/zsh/capability`, `capabilities/zsh/install`, `capabilities/zsh/configure`
- Create: `capabilities/zsh/home/.zshenv`, `capabilities/zsh/home/.zprofile`, `capabilities/zsh/home/.zshrc`
- Create: `capabilities/zsh/config/zsh/local.zsh`
- Create: `capabilities/zsh/default/env`, `capabilities/zsh/default/profile`, `capabilities/zsh/default/rc`, `capabilities/zsh/default/aliases`, `capabilities/zsh/default/functions`, `capabilities/zsh/default/init`
- Modify: `capabilities/core.list`, `tests/bootstrap.sh`
- Test: `tests/capabilities/zsh.sh`

**Interfaces:**
- Consumes: `pkg_install`, `copy_config_once`, `user_config_dir` (Task 1), `run_cmd`, `have`, `log`, `ok`, `warn`; `capabilities/secrets/default/functions.zsh` (Task 2), sourced by name from `default/rc`.
- Produces: `~/.zshenv`, `~/.zprofile`, `~/.zshrc`, `~/.config/zsh/local.zsh`; the exported `TEEUP_APPEARANCE`, `TEEUP_STATE_DIR`, `BAT_THEME`, `EDITOR`; `path_prepend`/`path_append`/`path_remove` as shell functions; `$HOME/.local/state/teeup/shims` appended last on `PATH` (phase 3's lazy shims depend on that position); the `zd`, `n` and `javav` functions.

- [ ] **Step 1: Write the failing test**

`tests/capabilities/zsh.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  mock_command dscl 0 "UserShell: /bin/bash"
  mock_command chsh 0 ""
  mock_command defaults 1 ""
  TEEUP="$TEEUP_PATH/bin/teeup"
}

# The two contracts plan 2b builds on (TEEUP_APPEARANCE and the generated theme
# environment) are only proved by actually running zsh, so a missing zsh is a
# failure, not a skip: run_test hides the output of a passing test, so a "skip"
# notice would be invisible and 2b would inherit an unverified contract.
# CI installs zsh on the Linux runner; macOS always has /bin/zsh.
require_zsh() {
  command -v zsh >/dev/null 2>&1 && return 0
  echo "zsh is not installed; this suite needs it (brew install zsh / sudo apt-get install -y zsh)"
  return 1
}

test_install_gets_the_plugins_and_switches_the_login_shell() {
  setup
  export TEEUP_TEST_MISSING="zsh"
  local out
  out="$(DRY_RUN=true "$TEEUP" install zsh 2>&1)"
  assert_contains "$out" "Would execute: brew install zsh-autosuggestions" || return 1
  assert_contains "$out" "Would execute: brew install zsh-syntax-highlighting" || return 1
  assert_contains "$out" "Would execute: brew install zsh-completions" || return 1
  assert_contains "$out" "Would execute: chsh -s /bin/zsh" || return 1
  cleanup_test_env
}

test_install_leaves_an_existing_zsh_login_shell_alone() {
  setup
  mock_command dscl 0 "UserShell: /bin/zsh"
  local out
  out="$(DRY_RUN=true "$TEEUP" install zsh 2>&1)"
  assert_contains "$out" "Login shell is already /bin/zsh." || return 1
  assert_not_contains "$out" "chsh" || return 1
  cleanup_test_env
}

test_configure_installs_the_thin_home_files() {
  setup
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null
  assert_file_exists "$TEST_HOME/.zshrc" || return 1
  assert_file_exists "$TEST_HOME/.zprofile" || return 1
  assert_file_exists "$TEST_HOME/.zshenv" || return 1
  assert_file_exists "$TEST_HOME/.config/zsh/local.zsh" || return 1
  assert_contains "$(cat "$TEST_HOME/.zshrc")" 'capabilities/zsh/default/rc' || return 1
  assert_contains "$(cat "$TEST_HOME/.zshenv")" '.config/teeup/env' || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure zsh)"
  assert_contains "$out" "Already installed: $TEST_HOME/.zshrc" || return 1
  cleanup_test_env
}

test_configure_backs_up_a_foreign_zshrc() {
  setup
  printf 'export PATH=/mine:$PATH\n' > "$TEST_HOME/.zshrc"
  DRY_RUN=false "$TEEUP" configure zsh >/dev/null 2>&1
  # A glob loop, not `ls | grep` (shellcheck SC2010). The backup of a dotfile
  # is itself a dotfile, so the pattern carries the leading dot.
  local backup="" f
  for f in "$TEST_HOME"/.zshrc.teeup_backup_*; do
    [[ -e "$f" ]] && backup="$f"
  done
  [[ -n "$backup" ]] || { echo "foreign file not backed up"; return 1; }
  assert_contains "$(cat "$TEST_HOME/.zshrc")" 'capabilities/zsh/default/rc' || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  DRY_RUN=true "$TEEUP" configure zsh >/dev/null
  [[ ! -e "$TEST_HOME/.zshrc" ]] || { echo ".zshrc written in dry run"; return 1; }
  cleanup_test_env
}

test_default_env_appends_the_shims_last() {
  setup
  require_zsh || return 1
  mkdir -p "$TEST_HOME/.local/bin" "$TEST_HOME/.local/state/teeup/shims"
  local out
  out="$(zsh -f -c ". '$TEEUP_PATH/capabilities/zsh/default/env'; printf '%s\n' \"\$PATH\"")"
  assert_contains "$out" "$TEST_HOME/.local/bin" || return 1
  [[ "$out" == *"$TEST_HOME/.local/state/teeup/shims" ]] ||
    { echo "teeup shims must be the last PATH entry, got: $out"; return 1; }
  cleanup_test_env
}

test_rc_exports_appearance_and_sources_the_theme_env() {
  setup
  require_zsh || return 1
  mock_command defaults 0 "Dark"
  mkdir -p "$TEST_HOME/.local/state/teeup/current/theme/dark"
  printf 'export BAT_THEME=teeup-generated\n' \
    > "$TEST_HOME/.local/state/teeup/current/theme/dark/env.sh"
  local out
  out="$(zsh -f -c "export TEEUP_PATH='$TEEUP_PATH'; . '$TEEUP_PATH/capabilities/zsh/default/rc'; print \"\$TEEUP_APPEARANCE \$BAT_THEME\"" 2>&1)"
  assert_contains "$out" "dark teeup-generated" || return 1
  cleanup_test_env
}

test_rc_reports_light_when_defaults_exits_nonzero() {
  setup
  require_zsh || return 1
  local out
  out="$(zsh -f -c "export TEEUP_PATH='$TEEUP_PATH'; . '$TEEUP_PATH/capabilities/zsh/default/rc'; print \"\$TEEUP_APPEARANCE\"" 2>&1)"
  assert_contains "$out" "light" || return 1
  cleanup_test_env
}

echo "capabilities/zsh"
run_test "install gets the plugins and switches the login shell" test_install_gets_the_plugins_and_switches_the_login_shell
run_test "install leaves an existing zsh login shell alone" test_install_leaves_an_existing_zsh_login_shell_alone
run_test "configure installs the thin home files" test_configure_installs_the_thin_home_files
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure backs up a foreign zshrc" test_configure_backs_up_a_foreign_zshrc
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "default env appends the shims last" test_default_env_appends_the_shims_last
run_test "rc exports appearance and sources the theme env" test_rc_exports_appearance_and_sources_the_theme_env
run_test "rc reports light when defaults exits non-zero" test_rc_reports_light_when_defaults_exits_nonzero
print_summary
```

Run: `bash tests/capabilities/zsh.sh`
Expected: every test fails with `Unknown capability: zsh`.

- [ ] **Step 2: Write the metadata and the two scripts**

`capabilities/zsh/capability`:

```sh
summary="zsh login shell with teeup's layered configuration"
group=shell
tier=core
requires="teeup-runtime"
provides=""
packages="zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting"
casks=""
apps=""
interactive=true
```

`interactive=true` because `chsh` asks for the account password on a TTY. `requires` stays at `teeup-runtime`: `default/rc` sources the `secrets` capability's function file out of the checkout, which exists whether or not that capability has been installed.

`capabilities/zsh/install`:

```bash
#!/usr/bin/env bash
# macOS ships zsh 5.9, so the first install is a no-op on any Mac; it is here
# for MacPorts machines that want a newer one.
pkg_install zsh zsh || warn "Continuing with the zsh macOS ships."

# Plain scripts sourced by default/rc, not a framework. Each one is optional:
# the shell layer skips whatever is missing.
for plugin in zsh-completions zsh-autosuggestions zsh-syntax-highlighting; do
  pkg_install "$plugin" || warn "Could not install $plugin; the shell layer will skip it."
done

# Login shell. /bin/zsh is Apple-signed and already listed in /etc/shells, so
# chsh takes it without a privileged edit; a package-manager zsh would need
# /etc/shells patched first.
login_shell="$(dscl . -read "/Users/${USER:-$(id -un)}" UserShell 2>/dev/null | awk '{print $2}')"
if [[ "$login_shell" == "/bin/zsh" ]]; then
  ok "Login shell is already /bin/zsh."
else
  log "Changing the login shell to /bin/zsh (macOS asks for your password)..."
  run_cmd chsh -s /bin/zsh || warn "chsh failed; run it by hand: chsh -s /bin/zsh"
fi
```

`capabilities/zsh/configure`:

```bash
#!/usr/bin/env bash
# The three home files are thin: they source teeup's default layer and leave
# room underneath for your own lines. copy_config_once never overwrites a file
# you edited and backs up a foreign one with a diff.
for f in .zshenv .zprofile .zshrc; do
  copy_config_once "$TEEUP_CAP_DIR/home/$f" "$HOME/$f"
done

# The documented home for machine-specific and personal lines, shipped as a
# comment-only stub so ~/.zshrc can source it unconditionally.
copy_config_once "$TEEUP_CAP_DIR/config/zsh/local.zsh" "$(user_config_dir)/zsh/local.zsh"

log "Open a new terminal, or run: exec zsh"
```

- [ ] **Step 3: Write the three thin home files**

`capabilities/zsh/home/.zshenv`:

```zsh
# ~/.zshenv - installed once by teeup; this copy is yours to edit.
# Read by every zsh, including the non-interactive one behind `ssh mac cmd`,
# which reads neither ~/.zprofile nor ~/.zshrc. Environment only.
[ -r "$HOME/.config/teeup/env" ] && . "$HOME/.config/teeup/env"
[ -n "${TEEUP_PATH:-}" ] && [ -r "$TEEUP_PATH/capabilities/zsh/default/env" ] &&
  . "$TEEUP_PATH/capabilities/zsh/default/env"

# Your own exports below this line.
```

`capabilities/zsh/home/.zprofile`:

```zsh
# ~/.zprofile - installed once by teeup; this copy is yours to edit.
# Login shells only, after macOS's /etc/zprofile has run path_helper.
[ -r "$HOME/.config/teeup/env" ] && . "$HOME/.config/teeup/env"
[ -n "${TEEUP_PATH:-}" ] && [ -r "$TEEUP_PATH/capabilities/zsh/default/profile" ] &&
  . "$TEEUP_PATH/capabilities/zsh/default/profile"

# Your own login-shell lines below this line.
```

`capabilities/zsh/home/.zshrc`:

```zsh
# ~/.zshrc - installed once by teeup; this copy is yours to edit.
# Interactive shells. The thick layer lives in the teeup checkout, so teeup
# upgrades improve it without touching this file.
[ -r "$HOME/.config/teeup/env" ] && . "$HOME/.config/teeup/env"
[ -n "${TEEUP_PATH:-}" ] && [ -r "$TEEUP_PATH/capabilities/zsh/default/rc" ] &&
  . "$TEEUP_PATH/capabilities/zsh/default/rc"

# Machine-specific and personal lines belong in ~/.config/zsh/local.zsh, which
# is sourced last so it wins over everything above. The XDG expansion matches
# what `configure` used to place the file (lib/core.sh's user_config_dir).
[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/local.zsh" ] &&
  . "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/local.zsh"
```

- [ ] **Step 4: Write `capabilities/zsh/default/env`**

```zsh
# capabilities/zsh/default/env - environment for every zsh, interactive or not.
# teeup owns this file; it is replaced on every teeup update. Your exports go
# in ~/.config/zsh/local.zsh or below the source line in ~/.zshenv.
# POSIX-shaped on purpose: a plain sh that sources it still works.

# --- PATH helpers ------------------------------------------------------------
# Remove every occurrence of $1 from PATH. POSIX parameter expansion only.
path_remove() {
  _pr=":$PATH:"
  while :; do
    case "$_pr" in
      *":$1:"*) _pr="${_pr%%":$1:"*}:${_pr#*":$1:"}" ;;
      *) break ;;
    esac
  done
  _pr="${_pr#:}"
  PATH="${_pr%:}"
  unset _pr
}

# Put $1 first even when it is already further back. This file is sourced more
# than once per login (~/.zshenv, then ~/.zprofile after macOS's path_helper
# and `brew shellenv` have prepended their own directories), and every pass has
# to restore user-path precedence.
path_prepend() {
  [ -d "$1" ] || return 0
  path_remove "$1"
  PATH="$1${PATH:+:$PATH}"
}

# Append only when missing; appended entries are meant to stay last.
path_append() {
  [ -d "$1" ] || return 0
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$PATH:$1" ;;
  esac
}

# --- teeup paths -------------------------------------------------------------
# TEEUP_PATH comes from ~/.config/teeup/env, sourced just before this file.
# TEEUP_STATE_DIR uses the same formula as lib/core.sh so the shell and the CLI
# never disagree about where generated files live.
TEEUP_STATE_DIR="${TEEUP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/teeup}"
export TEEUP_STATE_DIR

# --- package manager prefixes ------------------------------------------------
# MacPorts wins on macOS 12 and older (Darwin 21), where Homebrew dropped
# support; Homebrew wins otherwise. Doing it here means shells that never run
# `brew shellenv` (ssh commands, cron, GUI launchers) still find the binaries.
_teeup_darwin="$(uname -r 2>/dev/null)"
_teeup_darwin="${_teeup_darwin%%.*}"
_teeup_brew=""
if [ -x /opt/homebrew/bin/brew ]; then
  _teeup_brew=/opt/homebrew
elif [ -x /usr/local/bin/brew ]; then
  _teeup_brew=/usr/local
fi
if [ "${_teeup_darwin:-99}" -le 21 ] 2>/dev/null; then
  if [ -n "$_teeup_brew" ]; then
    path_prepend "$_teeup_brew/sbin"
    path_prepend "$_teeup_brew/bin"
  fi
  path_prepend /opt/local/sbin
  path_prepend /opt/local/bin
else
  path_prepend /opt/local/sbin
  path_prepend /opt/local/bin
  if [ -n "$_teeup_brew" ]; then
    path_prepend "$_teeup_brew/sbin"
    path_prepend "$_teeup_brew/bin"
  fi
fi
unset _teeup_darwin _teeup_brew

path_prepend "$HOME/.local/bin"
# mise's own shims let shells without `mise activate` find mise tools. teeup's
# lazy-install shims come after them and after everything else: a shim exists
# only to catch a command nothing real provides (spec section 6).
path_append "$HOME/.local/share/mise/shims"
path_append "$TEEUP_STATE_DIR/shims"
export PATH

# --- editor ------------------------------------------------------------------
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
# Defaulted, not forced: a parent process that set VISUAL or SUDO_EDITOR on
# purpose keeps its value, and an inherited EDITOR does not silently become
# all three.
export VISUAL="${VISUAL:-$EDITOR}"
export SUDO_EDITOR="${SUDO_EDITOR:-$EDITOR}"

# --- everything else ---------------------------------------------------------
# BAT_THEME is the shell-level theme hook; `teeup theme set` overrides this
# default through the generated file sourced in default/rc.
export BAT_THEME="${BAT_THEME:-ansi}"
export LESS="${LESS:--R}"
if command -v bat >/dev/null 2>&1; then
  export MANROFFOPT="-c"
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi
```

- [ ] **Step 5: Write `capabilities/zsh/default/profile`**

```zsh
# capabilities/zsh/default/profile - login shells, sourced by ~/.zprofile.
# teeup owns this file.

# macOS has no C.UTF-8 locale; normalise it before child processes warn.
if [ "${LC_ALL:-}" = "C.UTF-8" ] || [ "${LANG:-}" = "C.UTF-8" ]; then
  export LANG="en_US.UTF-8"
  export LC_ALL="en_US.UTF-8"
fi

# brew shellenv exports HOMEBREW_PREFIX, MANPATH and INFOPATH. It skips PATH
# entries that are already present, which the env layer has usually added.
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# macOS's /etc/zprofile ran path_helper before this file and moved the system
# directories to the front. Re-source the environment layer to put the user
# directories back in front; path_prepend is idempotent.
if [ -n "${TEEUP_PATH:-}" ] && [ -r "$TEEUP_PATH/capabilities/zsh/default/env" ]; then
  . "$TEEUP_PATH/capabilities/zsh/default/env"
fi
```

- [ ] **Step 6: Write `capabilities/zsh/default/rc`**

```zsh
# capabilities/zsh/default/rc - interactive zsh, sourced by ~/.zshrc.
# teeup owns this file. Order matters: environment, then appearance, history
# and completion, then plugins (syntax highlighting hooks every widget, so it
# goes last), then teeup's aliases and functions, then tool activation.

: "${TEEUP_PATH:=$HOME/.local/share/teeup}"
_teeup_zsh="$TEEUP_PATH/capabilities/zsh/default"

# Idempotent, so an interactive shell started from a stripped environment
# still gets the full PATH.
[ -r "$_teeup_zsh/env" ] && . "$_teeup_zsh/env"

# --- appearance and the generated theme environment --------------------------
# TEEUP_APPEARANCE is the contract the theme system reads: exactly "dark" or
# "light". `defaults read -g AppleInterfaceStyle` exits 1 in light mode. The
# guard means a child shell inherits the value instead of forking again.
if [ -z "${TEEUP_APPEARANCE:-}" ]; then
  if [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ]; then
    TEEUP_APPEARANCE=dark
  else
    TEEUP_APPEARANCE=light
  fi
  export TEEUP_APPEARANCE
fi
# Written by `teeup theme set` (capabilities/theme); absent until that lands.
# Sourced after BAT_THEME's default so the generated value wins.
if [ -r "$TEEUP_STATE_DIR/current/theme/$TEEUP_APPEARANCE/env.sh" ]; then
  . "$TEEUP_STATE_DIR/current/theme/$TEEUP_APPEARANCE/env.sh"
fi

# --- history -----------------------------------------------------------------
HISTFILE="${HISTFILE:-$HOME/.zsh_history}"
HISTSIZE=50000
SAVEHIST=50000
setopt APPEND_HISTORY INC_APPEND_HISTORY SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS
setopt AUTO_CD EXTENDED_GLOB INTERACTIVE_COMMENTS NO_BEEP

# --- completion --------------------------------------------------------------
# Site functions from whichever package manager is installed.
for _dir in /opt/local/share/zsh/site-functions /opt/local/share/zsh-completions \
            "${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh/site-functions" \
            "${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-completions" \
            /usr/local/share/zsh/site-functions /usr/local/share/zsh-completions; do
  [ -d "$_dir" ] && FPATH="$_dir:$FPATH"
done
unset _dir

autoload -Uz compinit
# The full compinit, with its compaudit security scan, at most once a day;
# the rest of the time trust the dump, which is far faster. The glob has to
# run in an array assignment: zsh does no filename generation inside [[ ]], so
# the tempting `[[ -n …(#qN…) ]]` is always true and the fast path dies.
# (#qN.mh-24) = exists, modified less than 24 hours ago.
_teeup_dump=("${ZDOTDIR:-$HOME}"/.zcompdump(#qN.mh-24))
if (( ${#_teeup_dump} )); then
  compinit -C
else
  compinit -i
fi
unset _teeup_dump
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# --- plugins -----------------------------------------------------------------
# Source the first readable candidate: MacPorts, Homebrew on either prefix, or
# a manual checkout under ~/.local/share.
_teeup_source_first() {
  local f
  for f in "$@"; do
    if [ -r "$f" ]; then
      . "$f"
      return 0
    fi
  done
  return 1
}

_teeup_source_first \
  /opt/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
  "$HOME/.local/share/zsh-autosuggestions/zsh-autosuggestions.zsh"

# Syntax highlighting wraps every widget defined so far, so it goes last.
_teeup_source_first \
  /opt/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  "$HOME/.local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

unset -f _teeup_source_first

# --- teeup's own shell surface ----------------------------------------------
[ -r "$_teeup_zsh/aliases" ] && . "$_teeup_zsh/aliases"
[ -r "$_teeup_zsh/functions" ] && . "$_teeup_zsh/functions"
# teeup-env, shipped by the secrets capability (spec section 7).
[ -r "$TEEUP_PATH/capabilities/secrets/default/functions.zsh" ] &&
  . "$TEEUP_PATH/capabilities/secrets/default/functions.zsh"
[ -r "$_teeup_zsh/init" ] && . "$_teeup_zsh/init"

# --- terminal title ----------------------------------------------------------
# The directory while idle, "directory — command" while a command runs.
autoload -Uz add-zsh-hook
_teeup_title_idle() { print -Pn '\e]2;%~\a' }
_teeup_title_run()  { print -Pn '\e]2;%~ — '"${1%% *}"'\a' }
add-zsh-hook precmd _teeup_title_idle
add-zsh-hook preexec _teeup_title_run

unset _teeup_zsh
```

- [ ] **Step 7: Write `capabilities/zsh/default/aliases`**

```zsh
# capabilities/zsh/default/aliases - teeup owns this file. To change or drop
# one, redefine or `unalias` it in ~/.config/zsh/local.zsh, which loads later.

if command -v eza >/dev/null 2>&1; then
  alias ls='eza -lh --group-directories-first --icons=auto'
  alias lsa='eza -lha --group-directories-first --icons=auto'
  alias ll='eza -lh --group-directories-first --icons=auto'
  alias la='eza -lha --group-directories-first --icons=auto'
  alias lt='eza --tree --level=2 --long --icons --git'
else
  alias ll='ls -lah'
  alias la='ls -lAh'
fi

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias c='clear'
alias cls='clear'
alias pse='ps -ef'

# zoxide's learned directories, with plain cd behaviour for real paths.
# zd is defined in default/functions.
command -v zoxide >/dev/null 2>&1 && alias cd='zd'

# git
alias g='git'
alias gs='git status'
alias ga='git add'
alias gcm='git commit -m'
alias gcam='git commit -a -m'
alias gco='git checkout'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate'
alias gp='git push'
alias gpl='git pull'
alias grv='git remote -v'
command -v lazygit >/dev/null 2>&1 && alias lg='lazygit'

# Emacs daemon. Plain `emacs` stays untouched for isolated instances.
if command -v emacsclient >/dev/null 2>&1; then
  alias e='emacsclient -c'
  alias et='emacsclient -t'
fi

# macOS Finder toggles.
alias showhidden='defaults write com.apple.finder AppleShowAllFiles YES; killall Finder'
alias hidehidden='defaults write com.apple.finder AppleShowAllFiles NO; killall Finder'
```

- [ ] **Step 8: Write `capabilities/zsh/default/functions`**

```zsh
# capabilities/zsh/default/functions - teeup owns this file.

# zd - cd that falls back to zoxide's database. `alias cd=zd` lives in
# default/aliases, so plain paths keep working exactly as before.
if command -v zoxide >/dev/null 2>&1; then
  zd() {
    if [[ $# -eq 0 ]]; then
      builtin cd ~ || return
    elif [[ -d "$1" ]]; then
      builtin cd "$1" || return
    else
      z "$@" || { print -u2 "zd: no directory or match for: $1"; return 1; }
      print -r -- "$PWD"
    fi
  }
fi

# n - nvim, on the current directory when given nothing.
n() {
  if [[ $# -eq 0 ]]; then
    command nvim .
  else
    command nvim "$@"
  fi
}

# javav [version|spec] - switch this shell's Java through mise.
#   javav          show the current Java
#   javav 21       $JAVAV_VENDOR-21 (default vendor: corretto)
#   javav zulu-17  any full mise java spec, passed through unchanged
# Needs `mise activate`, which default/init does: `mise shell` only affects the
# current session.
javav() {
  local spec
  if ! command -v mise >/dev/null 2>&1; then
    print -u2 "javav: mise is not installed"
    return 1
  fi
  if [[ $# -gt 0 ]]; then
    case "$1" in
      *-*) spec="$1" ;;
      *)   spec="${JAVAV_VENDOR:-corretto}-$1" ;;
    esac
    mise install "java@$spec" || return 1
    mise shell "java@$spec" || return 1
    hash -r 2>/dev/null || true
    print "javav: using Java $spec from mise"
  fi
  print "JAVA_HOME=${JAVA_HOME:-unset}"
  command -v java
  java -version
}
```

- [ ] **Step 9: Write `capabilities/zsh/default/init`**

```zsh
# capabilities/zsh/default/init - tool activation, last in the rc chain.
# Every block is guarded: on a machine without the tool the shell pays nothing
# and prints nothing.

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
  # mise rewrites PATH per directory, so command hashing has to be off.
  setopt NO_HASH_CMDS
fi

if command -v starship >/dev/null 2>&1 && [[ "${TERM:-}" != "dumb" ]]; then
  eval "$(starship init zsh)"
fi

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

if command -v fzf >/dev/null 2>&1; then
  # fzf 0.48 and newer ship their integration in the binary; older builds
  # shipped shell files next to the install prefix.
  if fzf --zsh >/dev/null 2>&1; then
    eval "$(fzf --zsh)"
  else
    for _f in /opt/homebrew/opt/fzf/shell /usr/local/opt/fzf/shell /opt/local/share/fzf/shell; do
      [ -r "$_f/completion.zsh" ] && . "$_f/completion.zsh"
      [ -r "$_f/key-bindings.zsh" ] && . "$_f/key-bindings.zsh"
    done
    unset _f
  fi
fi
```

- [ ] **Step 10: Write `capabilities/zsh/config/zsh/local.zsh`**

```zsh
# ~/.config/zsh/local.zsh - yours. teeup installs this stub once and never
# rewrites it. ~/.zshrc sources it last, so everything here wins over teeup's
# layer: aliases, PATH entries, machine-specific exports, work-only settings.
#
# Examples:
#   export JAVAV_VENDOR=zulu
#   alias k='kubectl'
#   path_prepend "$HOME/bin"
#   [ -d "$HOME/Work/products/emacs-packages" ] &&
#     export WORDWISE_EL_DIR="$HOME/Work/products/emacs-packages/wordwise.el"
```

- [ ] **Step 11: Add `zsh` to the core list in its spec position**

`capabilities/core.list`:

```text
# Core tier: what every terminal session needs. Ordered; each entry's
# requires= must already be satisfied by the entries above it.
# Later phases append: wezterm fonts aerospace keyboard macos-defaults theme
xcode-clt
package-manager
teeup-runtime
dev-dirs
zsh
secrets
```

- [ ] **Step 12: Teach the bootstrap suite about `zsh`**

`bootstrap --dry-run` now runs `zsh install` and `zsh configure`. `install` reads `dscl` outside `run_cmd`, and the shell layer is never sourced by bootstrap itself, so three mocks are enough. Add to `tests/bootstrap.sh`'s `setup()`:

```bash
  # zsh capability: the login-shell probe, the change itself, and the
  # appearance read the shell layer performs (never reached from bootstrap,
  # mocked so a stray call cannot touch the host).
  mock_command dscl 0 "UserShell: /bin/zsh"
  mock_command chsh 0 ""
  mock_command defaults 1 ""
```

`dscl` answering `/bin/zsh` keeps the bootstrap run on the "already correct" branch, so no `chsh` line appears in the dry-run walk and the existing ordering assertions are unaffected.

- [ ] **Step 13: Run everything**

```bash
chmod +x capabilities/zsh/install capabilities/zsh/configure
command -v zsh >/dev/null || echo "install zsh first: brew install zsh / sudo apt-get install -y zsh"
./tests/run.sh
./bin/teeup commands --check
shellcheck --severity=warning capabilities/zsh/install capabilities/zsh/configure tests/capabilities/zsh.sh tests/bootstrap.sh
```

Expected: `All 15 suites passed.`, including `bootstrap.sh`. The three `zsh -f` tests **fail loudly** on a machine without zsh (`zsh is not installed; this suite needs it`) rather than skipping — install zsh and re-run; Task 10 adds the CI step that does this on the Linux runner. No output from `commands --check`, none from shellcheck. The files under `capabilities/zsh/default/` and `capabilities/zsh/home/` are zsh and are deliberately not shellchecked; `zsh -n` covers their syntax through the tests that source them.

- [ ] **Step 14: Commit**

```bash
git add capabilities/zsh capabilities/core.list tests/capabilities/zsh.sh tests/bootstrap.sh
git commit -m "Add the zsh capability with teeup's layered shell configuration"
```

**Real-Mac risk:** `chsh` prompts for the account password and cannot be exercised under mocks; a wrong answer leaves the login shell unchanged and the message tells the user to run it by hand. On any Mac since Catalina `/bin/zsh` is already the login shell, so this branch usually does not fire at all. `compinit`'s compaudit can refuse group-writable Homebrew completion directories on a fresh install and print "insecure directories" — `compinit -i` ignores them, which is why the `-i` is there. The `defaults read -g AppleInterfaceStyle` fork adds a few milliseconds to the first interactive shell of each session.

---

### Task 4: `starship` capability

**Files:**
- Create: `capabilities/starship/capability`, `capabilities/starship/install`, `capabilities/starship/configure`, `capabilities/starship/config/starship.toml`
- Modify: `capabilities/core.list`, `tests/bootstrap.sh`
- Test: `tests/capabilities/starship.sh`

**Interfaces:**
- Consumes: `pkg_install`, `copy_config_once`, `user_config_dir`.
- Produces: `~/.config/starship.toml` containing the managed block delimited by the exact lines `# teeup:theme-palette:start` and `# teeup:theme-palette:end`, and the `palette = "teeup-dark"` line directly above the start marker. **Plan 2b's theme system regenerates everything between those two markers** (both `[palettes.teeup-dark]` and `[palettes.teeup-light]` tables) and may rewrite the `palette =` line above them to switch modes. `capabilities/zsh/default/init` already runs `starship init zsh` when the binary is present, so nothing wires the prompt here.

- [ ] **Step 1: Write the failing test**

`tests/capabilities/starship.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_gets_starship() {
  setup
  export TEEUP_TEST_MISSING="starship"
  local out
  out="$(DRY_RUN=true "$TEEUP" install starship 2>&1)"
  assert_contains "$out" "Would execute: brew install starship" || return 1
  cleanup_test_env
}

test_configure_copies_the_config_once() {
  setup
  DRY_RUN=false "$TEEUP" configure starship >/dev/null
  assert_file_exists "$TEST_HOME/.config/starship.toml" || return 1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure starship)"
  assert_contains "$out" "Already installed: $TEST_HOME/.config/starship.toml" || return 1
  cleanup_test_env
}

test_shipped_config_carries_the_theme_markers() {
  setup
  DRY_RUN=false "$TEEUP" configure starship >/dev/null
  local body
  body="$(cat "$TEST_HOME/.config/starship.toml")"
  assert_contains "$body" "# teeup:theme-palette:start" || return 1
  assert_contains "$body" "# teeup:theme-palette:end" || return 1
  assert_contains "$body" "[palettes.teeup-dark]" || return 1
  assert_contains "$body" "[palettes.teeup-light]" || return 1
  cleanup_test_env
}

test_palette_is_selected_at_the_root() {
  setup
  DRY_RUN=false "$TEEUP" configure starship >/dev/null
  local file="$TEST_HOME/.config/starship.toml" p t
  # A bare key after a [table] header belongs to that table, so `palette` is
  # only the root-level selector while it precedes every table header. A
  # substring assertion cannot see the difference; line order can.
  p="$(grep -n '^palette = ' "$file" | head -1 | cut -d: -f1)"
  t="$(grep -n '^\[' "$file" | head -1 | cut -d: -f1)"
  [[ -n "$p" && -n "$t" ]] || { echo "palette line or table header missing"; return 1; }
  [[ "$p" -lt "$t" ]] ||
    { echo "palette (line $p) must come before the first table (line $t)"; return 1; }
  # And, where a TOML parser is available, prove it for real.
  if command -v python3 >/dev/null 2>&1 &&
     python3 -c 'import tomllib' >/dev/null 2>&1; then
    local parsed
    parsed="$(python3 -c 'import tomllib,sys
d = tomllib.load(open(sys.argv[1], "rb"))
print(d.get("palette"), sorted(d.get("palettes", {})))' "$file")"
    assert_equals "teeup-dark ['teeup-dark', 'teeup-light']" "$parsed" || return 1
  fi
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  DRY_RUN=true "$TEEUP" configure starship >/dev/null
  [[ ! -e "$TEST_HOME/.config/starship.toml" ]] || { echo "written in dry run"; return 1; }
  cleanup_test_env
}

echo "capabilities/starship"
run_test "install gets starship" test_install_gets_starship
run_test "configure copies the config once" test_configure_copies_the_config_once
run_test "shipped config carries the theme markers" test_shipped_config_carries_the_theme_markers
run_test "palette is selected at the root" test_palette_is_selected_at_the_root
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
print_summary
```

- [ ] **Step 2: Write `capabilities/starship/`**

`capability`:

```sh
summary="Starship prompt"
group=shell
tier=core
requires="zsh"
provides=""
packages="starship"
casks=""
apps=""
interactive=false
```

`install`:

```bash
#!/usr/bin/env bash
# The prompt itself. capabilities/zsh/default/init runs `starship init zsh`
# whenever the binary is on PATH, so there is no wiring step.
pkg_install starship starship
```

`configure`:

```bash
#!/usr/bin/env bash
# Copied once and then yours. The palette block between the teeup:theme-palette
# markers is the exception: `teeup theme set` rewrites it in place.
copy_config_once "$TEEUP_CAP_DIR/config/starship.toml" "$(user_config_dir)/starship.toml"
```

- [ ] **Step 3: Write `capabilities/starship/config/starship.toml`**

Ported from the chezmoi repo's `dot_config/starship.toml` (blank line, character symbols, truncation, `cmd_duration`) with Omarchy's compact git status module, plus the palette contract. The colours below are Catppuccin Frappe (dark) and Latte (light); the theme system overwrites them.

```toml
# starship.toml - installed once by teeup; this copy is yours to edit.
# Reference: https://starship.rs/config/
#
# LAYOUT RULE, do not reorder: in TOML a bare key after a [table] header
# belongs to that table. `palette` and the other root keys must therefore come
# before the FIRST table header in the file, and the first tables are the two
# palettes. Putting `palette` further down (say after [cmd_duration]) silently
# makes it `cmd_duration.palette`, which Starship ignores, and no palette is
# ever selected.
#
# Everything between the teeup:theme-palette markers is regenerated by
# `teeup theme set`, which also rewrites the `palette = ` line above them to
# switch modes. Edit outside the markers only.

add_newline = true
command_timeout = 200
format = "$directory$git_branch$git_status$cmd_duration$character"
palette = "teeup-dark"

# teeup:theme-palette:start
[palettes.teeup-dark]
black = "#51576d"
red = "#e78284"
green = "#a6d189"
yellow = "#e5c890"
blue = "#8caaee"
magenta = "#ca9ee6"
cyan = "#81c8be"
white = "#b5bfe2"

[palettes.teeup-light]
black = "#5c5f77"
red = "#d20f39"
green = "#40a02b"
yellow = "#df8e1d"
blue = "#1e66f5"
magenta = "#8839ef"
cyan = "#179299"
white = "#4c4f69"
# teeup:theme-palette:end

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"

[directory]
truncation_length = 4
truncate_to_repo = true
truncation_symbol = "…/"
style = "bold blue"

[git_branch]
format = "[$branch]($style) "
style = "italic magenta"

[git_status]
format = "[$all_status$ahead_behind]($style)"
style = "yellow"
ahead = "⇡${count} "
behind = "⇣${count} "
diverged = "⇕⇡${ahead_count}⇣${behind_count} "
conflicted = "= "
untracked = "? "
modified = "! "
staged = "+ "
renamed = "» "
deleted = "✘ "
stashed = "$ "
up_to_date = ""

[cmd_duration]
min_time = 2000
format = "took [$duration](bold yellow) "
```

- [ ] **Step 4: Add `starship` to the core list**

Insert `starship` directly after `zsh` in `capabilities/core.list`, giving `xcode-clt package-manager teeup-runtime dev-dirs zsh starship secrets`.

- [ ] **Step 5: Teach the bootstrap suite about `starship`**

`starship configure` only copies a file and `install` only calls `pkg_install`, so no new mock is needed — but the run must not depend on whether the developer's machine happens to have starship. Add `starship` to the existing `TEEUP_TEST_MISSING` line in `tests/bootstrap.sh`'s `setup()`:

```bash
  export TEEUP_TEST_MISSING="brew gum jq starship"
```

- [ ] **Step 6: Run everything**

```bash
chmod +x capabilities/starship/install capabilities/starship/configure
./tests/run.sh
./bin/teeup commands --check
shellcheck --severity=warning capabilities/starship/install capabilities/starship/configure tests/capabilities/starship.sh tests/bootstrap.sh
```

Expected: `All 16 suites passed.`, including `bootstrap.sh`; no output from the other two. `test_palette_is_selected_at_the_root` runs the TOML parser half only when `python3` has `tomllib` (3.11+); the line-order half always runs.

- [ ] **Step 7: Commit**

```bash
git add capabilities/starship capabilities/core.list tests/capabilities/starship.sh tests/bootstrap.sh
git commit -m "Add the starship capability with a themable palette block"
```

**Real-Mac risk:** the prompt glyphs need a Nerd Font, which plan 2b's `fonts` capability installs; until then the arrows render as boxes in a stock terminal. Starship reads `~/.config/starship.toml` by default, so no `STARSHIP_CONFIG` export is needed.

---

### Task 5: `cli-tools` capability

The modern CLI set from the spec's "CLI core" row, minus `lazygit` (owned by `git`, Task 6) and `gh` (owned by `github`, Task 8).

**Files:**
- Create: `capabilities/cli-tools/capability`, `capabilities/cli-tools/install`, `capabilities/cli-tools/configure`, `capabilities/cli-tools/config/bat/config`
- Modify: `capabilities/core.list`, `tests/bootstrap.sh`
- Test: `tests/capabilities/cli-tools.sh`

**Interfaces:**
- Consumes: `pkg_install <pkg> <command>`, `copy_config_once`, `user_config_dir`, `warn`.
- Produces: `~/.config/bat/config`. The tools it installs are what `capabilities/zsh/default/{aliases,init}` guard on (`eza`, `zoxide`, `fzf`, `bat`, `btop`).

- [ ] **Step 1: Write the failing test**

`tests/capabilities/cli-tools.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  # A fresh Mac has none of these.
  export TEEUP_TEST_MISSING="rg fd fzf bat eza zoxide jq yq btop tldr dust gpg"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_uses_package_and_command_pairs() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install cli-tools 2>&1)"
  assert_contains "$out" "Would execute: brew install ripgrep" || return 1
  assert_contains "$out" "Would execute: brew install fd" || return 1
  assert_contains "$out" "Would execute: brew install gnupg" || return 1
  assert_contains "$out" "Would execute: brew install dust" || return 1
  cleanup_test_env
}

test_install_skips_tools_already_on_path() {
  setup
  export TEEUP_TEST_MISSING="rg fd fzf bat eza zoxide yq btop tldr dust gpg"
  mock_command jq 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install cli-tools 2>&1)"
  assert_contains "$out" "Already available on PATH: jq" || return 1
  assert_not_contains "$out" "brew install jq" || return 1
  cleanup_test_env
}

test_install_warns_but_survives_a_missing_port() {
  setup
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "list"*) exit 1 ;;
  "install dust") exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  local rc=0 out
  out="$(DRY_RUN=false "$TEEUP" install cli-tools 2>&1)" || rc=$?
  assert_success "$rc" "one missing tool must not fail the capability" || return 1
  assert_contains "$out" "Could not install: dust" || return 1
  cleanup_test_env
}

test_configure_writes_the_bat_config() {
  setup
  DRY_RUN=false "$TEEUP" configure cli-tools >/dev/null
  assert_file_exists "$TEST_HOME/.config/bat/config" || return 1
  local body
  body="$(cat "$TEST_HOME/.config/bat/config")"
  assert_contains "$body" "--style=numbers,changes,header" || return 1
  assert_not_contains "$body" "--theme" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  DRY_RUN=false "$TEEUP" configure cli-tools >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure cli-tools)"
  assert_contains "$out" "Already installed: $TEST_HOME/.config/bat/config" || return 1
  cleanup_test_env
}

echo "capabilities/cli-tools"
run_test "install uses package and command pairs" test_install_uses_package_and_command_pairs
run_test "install skips tools already on PATH" test_install_skips_tools_already_on_path
run_test "install warns but survives a missing port" test_install_warns_but_survives_a_missing_port
run_test "configure writes the bat config" test_configure_writes_the_bat_config
run_test "configure is idempotent" test_configure_is_idempotent
print_summary
```

- [ ] **Step 2: Write `capabilities/cli-tools/`**

`capability`:

```sh
summary="The modern CLI set: ripgrep, fd, fzf, bat, eza, zoxide and friends"
group=shell
tier=core
requires="package-manager"
provides=""
packages="ripgrep fd fzf bat eza zoxide jq yq btop tree wget curl gnupg tldr dust"
casks=""
apps=""
interactive=false
```

`install`:

```bash
#!/usr/bin/env bash
# package:command pairs, because the package name and the binary differ for
# half of them and pkg_install skips whatever is already on PATH.
# lazygit belongs to the git capability and gh to github: packages= drives the
# generic update and remove verbs, so every package has exactly one owner.
failed=""
for pair in ripgrep:rg fd:fd fzf:fzf bat:bat eza:eza zoxide:zoxide jq:jq \
            yq:yq btop:btop tree:tree wget:wget curl:curl gnupg:gpg \
            tldr:tldr dust:dust; do
  pkg="${pair%%:*}"
  cmd="${pair##*:}"
  pkg_install "$pkg" "$cmd" || failed="$failed $pkg"
done

# One missing port on a MacPorts machine must not abort the core tier; the
# shell layer guards on each tool and `teeup doctor` will report the gap.
if [[ -n "$failed" ]]; then
  warn "Could not install:$failed. Install them by hand, or re-run: teeup install cli-tools"
fi
```

`configure`:

```bash
#!/usr/bin/env bash
# bat is the only one of these with a config file worth shipping. The theme is
# deliberately absent from it: bat reads $BAT_THEME, which capabilities/zsh
# exports and `teeup theme set` overrides, and a --theme line here would win
# over both.
copy_config_once "$TEEUP_CAP_DIR/config/bat/config" "$(user_config_dir)/bat/config"
```

`config/bat/config`:

```text
# bat configuration - installed once by teeup; this copy is yours to edit.
# The theme comes from the BAT_THEME environment variable, exported by teeup's
# zsh layer and rewritten by `teeup theme set`. Adding --theme here would
# override the theme system, so it is left out on purpose.
--style=numbers,changes,header
--italic-text=always
--paging=auto
```

- [ ] **Step 3: Add `cli-tools` to the core list**

Insert `cli-tools` directly after `starship`, giving `xcode-clt package-manager teeup-runtime dev-dirs zsh starship cli-tools secrets` — which is now exactly the spec's order for the entries that exist.

- [ ] **Step 4: Teach the bootstrap suite about `cli-tools`**

Every command this capability touches goes through `pkg_install` (mocked `brew`) or `copy_config_once`, so the bootstrap run needs no new mock. It does need a deterministic answer to "is this tool already on the host", so extend the `TEEUP_TEST_MISSING` line in `tests/bootstrap.sh`'s `setup()` to hide all of them:

```bash
  export TEEUP_TEST_MISSING="brew gum jq starship rg fd fzf bat eza zoxide yq btop tldr dust gpg"
```

(`tree`, `wget` and `curl` are left alone: whichever way the host answers, the branch taken is a `log` line or a mocked `brew install`.)

- [ ] **Step 5: Run everything**

```bash
chmod +x capabilities/cli-tools/install capabilities/cli-tools/configure
./tests/run.sh
./bin/teeup commands --check
shellcheck --severity=warning capabilities/cli-tools/install capabilities/cli-tools/configure tests/capabilities/cli-tools.sh tests/bootstrap.sh
```

Expected: `All 17 suites passed.`, including `bootstrap.sh`; no output from the other two.

- [ ] **Step 6: Commit**

```bash
git add capabilities/cli-tools capabilities/core.list tests/capabilities/cli-tools.sh tests/bootstrap.sh
git commit -m "Add the cli-tools capability with the modern CLI set"
```

**Real-Mac risk:** `curl` and `tree`-style tools that macOS already ships are skipped by the command check, so Homebrew's newer `curl` is never installed — deliberate, since nothing here needs it. On MacPorts machines `dust` and `tldr` may not exist as ports; the warning path above is the one that fires, and it has a test.

---

### Task 6: `git` capability

Spec sections 7 (git extras) and 8 (identity as a directory rule). `git` owns `lazygit` (see Decisions). `pre-commit` is **not** installed here: it belongs to `mise` (Task 9), which keeps `git` runnable before mise exists and keeps `core.list` in the spec's order.

**Files:**
- Create: `capabilities/git/capability`, `capabilities/git/install`, `capabilities/git/configure`, `capabilities/git/config/git/config`
- Modify: `capabilities/core.list`, `tests/bootstrap.sh`
- Test: `tests/capabilities/git.sh`

**Interfaces:**
- Consumes: `pkg_install`, `copy_config_once`, `write_managed_file`, `user_config_dir`, `identity_email`, `identity_key`, `answers_get`, `answers_has_work`, `have`, `run_cmd`, `warn`, `die`.
- Produces: `~/.config/git/config` (copied once, user-owned), `~/.config/git/teeup-generated` (managed: `core.editor`, `core.pager`, `interactive.diffFilter`, `commit.gpgsign` — included *after* the shipped defaults so it can switch them off), `~/.config/git/identity-personal` and `~/.config/git/identity-work` (managed: name, email, `user.signingkey` pointing at `~/.ssh/id_ed25519_<identity>.pub`, which Task 7 creates). `~/.config/git/local` is referenced by the shipped config and left for the user to create.

- [ ] **Step 1: Write the failing test**

`tests/capabilities/git.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  mock_command git 0 ""
  mock_command git-lfs 0 ""
  export TEEUP_TEST_MISSING="delta lazygit emacsclient"
  TEEUP="$TEEUP_PATH/bin/teeup"
}

seed_answers() {
  mkdir -p "$TEST_HOME/.config/teeup"
  {
    printf 'TEEUP_NAME="Ada Lovelace"\n'
    printf 'TEEUP_EMAIL="ada@example.com"\n'
    printf 'TEEUP_WORK_EMAIL="%s"\n' "${1:-}"
  } > "$TEST_HOME/.config/teeup/answers"
}

test_install_gets_git_delta_lfs_and_lazygit() {
  setup
  # setup mocks git-lfs onto PATH for the configure tests, and pkg_install
  # short-circuits on a command that is already there. Hide it for this test
  # only, or the brew assertion below can never fire.
  export TEEUP_TEST_MISSING="delta lazygit emacsclient git-lfs"
  local out
  out="$(DRY_RUN=true "$TEEUP" install git 2>&1)"
  assert_contains "$out" "Would execute: brew install git" || return 1
  assert_contains "$out" "Would execute: brew install git-delta" || return 1
  assert_contains "$out" "Would execute: brew install git-lfs" || return 1
  assert_contains "$out" "Would execute: brew install lazygit" || return 1
  cleanup_test_env
}

test_configure_writes_both_identities() {
  setup
  seed_answers "ada@corp.example"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local personal work
  personal="$(cat "$TEST_HOME/.config/git/identity-personal")"
  work="$(cat "$TEST_HOME/.config/git/identity-work")"
  assert_contains "$personal" "email = ada@example.com" || return 1
  assert_contains "$personal" "name = Ada Lovelace" || return 1
  assert_contains "$personal" "signingkey = $TEST_HOME/.ssh/id_ed25519_personal.pub" || return 1
  assert_contains "$work" "email = ada@corp.example" || return 1
  assert_contains "$work" "signingkey = $TEST_HOME/.ssh/id_ed25519_work.pub" || return 1
  cleanup_test_env
}

test_work_identity_falls_back_to_the_personal_email() {
  setup
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  assert_contains "$(cat "$TEST_HOME/.config/git/identity-work")" "email = ada@example.com" || return 1
  cleanup_test_env
}

test_configure_without_answers_warns_and_writes_no_identity() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure git 2>&1)"
  assert_contains "$out" "skipping the git identities" || return 1
  [[ ! -e "$TEST_HOME/.config/git/identity-personal" ]] || { echo "identity written without answers"; return 1; }
  cleanup_test_env
}

test_configure_ships_the_config_and_the_editor() {
  setup
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local body
  body="$(cat "$TEST_HOME/.config/git/config")"
  assert_contains "$body" 'includeIf "gitdir:~/Work/"' || return 1
  assert_contains "$body" 'includeIf "gitdir:~/Personal/"' || return 1
  assert_contains "$body" "pager = delta" || return 1
  assert_contains "$body" "format = ssh" || return 1
  assert_contains "$body" "defaultBranch = main" || return 1
  local generated
  generated="$(cat "$TEST_HOME/.config/git/teeup-generated")"
  assert_contains "$generated" "editor = vim" || return 1
  # delta is hidden by TEEUP_TEST_MISSING and no key exists yet, so the
  # generated include has to switch both dangerous defaults back off.
  assert_contains "$generated" "pager = less" || return 1
  assert_contains "$generated" "diffFilter = cat" || return 1
  assert_contains "$generated" "gpgsign = false" || return 1
  cleanup_test_env
}

test_signing_and_delta_are_enabled_once_they_exist() {
  setup
  export TEEUP_TEST_MISSING="lazygit emacsclient"
  mock_command delta 0 ""
  seed_answers ""
  mkdir -p "$TEST_HOME/.ssh"
  printf 'ssh-ed25519 AAAAFAKE ada@example.com\n' > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local generated
  generated="$(cat "$TEST_HOME/.config/git/teeup-generated")"
  assert_contains "$generated" "gpgsign = true" || return 1
  assert_contains "$generated" "pager = delta" || return 1
  cleanup_test_env
}

test_generated_include_is_read_after_the_defaults() {
  setup
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  # git keeps the last value it reads, so the teeup-generated include must sit
  # below the [core] pager default it exists to override.
  local file="$TEST_HOME/.config/git/config" pager_line include_line
  pager_line="$(grep -n 'pager = delta' "$file" | head -1 | cut -d: -f1)"
  include_line="$(grep -n 'path = ~/.config/git/teeup-generated' "$file" | head -1 | cut -d: -f1)"
  [[ -n "$pager_line" && -n "$include_line" && "$include_line" -gt "$pager_line" ]] ||
    { echo "teeup-generated (line $include_line) must be included after pager (line $pager_line)"; return 1; }
  cleanup_test_env
}

test_configure_prefers_emacsclient_when_present() {
  setup
  export TEEUP_TEST_MISSING="delta lazygit"
  mock_command emacsclient 0 ""
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  assert_contains "$(cat "$TEST_HOME/.config/git/teeup-generated")" "editor = emacsclient -t" || return 1
  cleanup_test_env
}

test_configure_runs_git_lfs_install_and_warns_about_gitconfig() {
  setup
  seed_answers ""
  printf '[user]\n\tname = Old\n' > "$TEST_HOME/.gitconfig"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure git 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "git lfs install --skip-repo" || return 1
  assert_contains "$out" "$TEST_HOME/.gitconfig exists and its keys win" || return 1
  assert_file_exists "$TEST_HOME/.gitconfig" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure git >/dev/null 2>&1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure git 2>&1)"
  assert_contains "$out" "Already current: $TEST_HOME/.config/git/identity-personal" || return 1
  assert_contains "$out" "Already installed: $TEST_HOME/.config/git/config" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  seed_answers ""
  DRY_RUN=true "$TEEUP" configure git >/dev/null 2>&1
  [[ ! -e "$TEST_HOME/.config/git/config" ]] || { echo "written in dry run"; return 1; }
  cleanup_test_env
}

echo "capabilities/git"
run_test "install gets git, delta, lfs and lazygit" test_install_gets_git_delta_lfs_and_lazygit
run_test "configure writes both identities" test_configure_writes_both_identities
run_test "work identity falls back to the personal email" test_work_identity_falls_back_to_the_personal_email
run_test "configure without answers warns and writes no identity" test_configure_without_answers_warns_and_writes_no_identity
run_test "configure ships the config and the editor" test_configure_ships_the_config_and_the_editor
run_test "signing and delta are enabled once they exist" test_signing_and_delta_are_enabled_once_they_exist
run_test "generated include is read after the defaults" test_generated_include_is_read_after_the_defaults
run_test "configure prefers emacsclient when present" test_configure_prefers_emacsclient_when_present
run_test "configure runs git lfs install and warns about gitconfig" test_configure_runs_git_lfs_install_and_warns_about_gitconfig
run_test "configure is idempotent" test_configure_is_idempotent
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
print_summary
```

- [ ] **Step 2: Write the metadata and `install`**

`capabilities/git/capability`:

```sh
summary="git with two identities, SSH signing, delta and lazygit"
group=git
tier=core
requires="dev-dirs cli-tools"
provides=""
packages="git git-delta git-lfs lazygit"
casks=""
apps=""
interactive=false
```

`requires="dev-dirs"` matters: the `includeIf` rules key off `~/Work` and `~/Personal`, so those directories exist first. `provides` stays empty — `git` is on the forbidden shim list because macOS ships it.

`capabilities/git/install`:

```bash
#!/usr/bin/env bash
# No command guard on git itself: macOS ships one with the Command Line Tools,
# so `pkg_install git git` would be a permanent no-op and the machine would
# keep a git that trails upstream by about a year.
pkg_install git || die "git is required and could not be installed."

# delta is the pager the shipped config points at, so a missing one is loud.
pkg_install git-delta delta || warn "delta is missing; git will fall back to less until you install it."
pkg_install git-lfs git-lfs || warn "git-lfs is missing; large-file repositories will not clone correctly."
pkg_install lazygit lazygit || warn "lazygit is missing; the lg alias will not work."
```

- [ ] **Step 3: Write `capabilities/git/configure`**

```bash
#!/usr/bin/env bash
# Identity is a directory rule, not a profile (spec section 8): both identities
# exist on every machine and the repository's location picks one.
git_dir="$(user_config_dir)/git"

name="$(answers_get TEEUP_NAME)"
email="$(answers_get TEEUP_EMAIL)"
if [[ -z "$name" || -z "$email" ]]; then
  warn "No name or personal email in the answers file; skipping the git identities."
  warn "Run ./bootstrap --reconfigure, then: teeup configure git"
else
  # Both files are always written, even with no work email (identity_email
  # falls back to the personal one): an unused gitconfig include costs nothing,
  # while a missing one would leave ~/Work with no identity at all. Compare
  # with ssh, where a second identity means a second passphrase and upload.
  for identity in personal work; do
    key="$(identity_key "$identity")"
    write_managed_file "$git_dir/identity-$identity" "git identity ($identity)" <<GIT_IDENTITY
# Generated by teeup (teeup configure git). Your edits here are overwritten.
[user]
	name = $name
	email = $(identity_email "$identity")
	signingkey = $key.pub
GIT_IDENTITY
  done
  if answers_has_work; then
    ok "git identities: personal ($email), work ($(identity_email work))"
  else
    ok "git identity: $email for both ~/Personal and ~/Work (no work email set)"
  fi
fi

# Three settings depend on what is actually installed, so they are generated
# rather than shipped. The shipped config includes this file AFTER its own
# defaults, so what is written here wins over them (and ~/.config/git/local,
# included last, still wins over this).
if have emacsclient; then
  editor="emacsclient -t"
else
  editor="vim"
fi

# A pager that is not installed makes `git log`, `git diff` and `git show` fail
# machine-wide, so delta is only kept when delta exists.
if have delta; then
  pager="delta"
  diff_filter="delta --color-only"
else
  pager="less"
  diff_filter="cat"
  log "delta is not installed; leaving git on its default pager."
fi

# Mandatory SSH signing with no key makes every `git commit` fail, including
# the one that would fix it. ssh runs after git in the core list, so on a first
# bootstrap the key does not exist yet: signing turns itself on at the next
# `teeup configure git` (which `teeup update` runs) once ssh has made it.
if [[ -f "$(identity_key personal).pub" ]]; then
  gpgsign="true"
else
  gpgsign="false"
  log "No $(identity_key personal).pub yet; commit signing stays off."
  log "After the ssh capability has made your keys, run: teeup configure git"
fi

write_managed_file "$git_dir/teeup-generated" "git generated settings" <<GIT_GENERATED
# Generated by teeup (teeup configure git). Your edits here are overwritten.
[core]
	editor = $editor
	pager = $pager
[sequence]
	editor = $editor
[interactive]
	diffFilter = $diff_filter
[commit]
	gpgsign = $gpgsign
GIT_GENERATED

copy_config_once "$TEEUP_CAP_DIR/config/git/config" "$git_dir/config"

# git reads ~/.gitconfig after ~/.config/git/config, so a leftover file wins
# silently. teeup never edits, moves or deletes it; it says so instead.
if [[ -f "$HOME/.gitconfig" ]]; then
  # $HOME rather than a literal ~: a tilde inside a quoted string is not
  # expanded by the shell and shellcheck rejects it (SC2088).
  warn "$HOME/.gitconfig exists and its keys win over $git_dir/config."
  warn "Move what you want to keep into $git_dir/config or $git_dir/local, then delete it."
fi

# git-lfs writes its filter block into the global config; --skip-repo stops it
# from also touching whichever repository happens to be the working directory.
if have git-lfs; then
  run_cmd git lfs install --skip-repo || warn "git lfs install failed; run it by hand."
else
  log "git-lfs is not installed; skipping git lfs install."
fi

log "pre-commit is installed by the mise capability, later in the core list."
```

- [ ] **Step 4: Write `capabilities/git/config/git/config`**

Aliases and colours are ported from the chezmoi repo's `dot_gitconfig.tmpl`; the modern defaults are Omarchy's `config/git/config` with `init.defaultBranch` changed from `master` to `main` per the spec.

```ini
# ~/.config/git/config - installed once by teeup; this copy is yours to edit.
# Generated pieces (editor, pager, signing, the two identities) live in
# separate included files so teeup can regenerate them without touching your
# edits here. Include order is load-bearing: git keeps the LAST value it
# reads, so teeup-generated is included below the defaults it has to be able
# to override, and ~/.config/git/local last of all.

[include]
	# Default identity; the includeIf blocks at the bottom override it per root.
	path = ~/.config/git/identity-personal

[user]
	useConfigOnly = true     # never guess an identity from the hostname

[init]
	defaultBranch = main
[pull]
	rebase = true            # rebase instead of merge on pull
[push]
	autoSetupRemote = true   # no "set upstream" dance on the first push
	followTags = true
[fetch]
	prune = true
[diff]
	algorithm = histogram    # clearer diffs on moved and edited lines
	colorMoved = plain
	mnemonicPrefix = true
	renames = copies
[merge]
	conflictstyle = zdiff3
[commit]
	verbose = true           # the diff in the commit message template
	gpgsign = true           # turned off again by teeup-generated until a key exists
[gpg]
	format = ssh             # sign with the SSH key; no GPG keyring to manage
[tag]
	sort = -version:refname
[branch]
	sort = -committerdate
[column]
	ui = auto
[rerere]
	enabled = true           # record and reuse conflict resolutions
	autoupdate = true
[core]
	pager = delta            # replaced by teeup-generated when delta is missing
[interactive]
	diffFilter = delta --color-only
[delta]
	navigate = true
	line-numbers = true

# Editor, pager, diffFilter and commit.gpgsign, as detected by
# `teeup configure git`. Included here so it overrides the defaults above.
[include]
	path = ~/.config/git/teeup-generated
[credential "https://github.com"]
	helper =
	helper = !gh auth git-credential
[credential "https://gist.github.com"]
	helper =
	helper = !gh auth git-credential

[alias]
	aa = !git add . && git add -u . && git status
	ac = !git add . && git commit
	acm = !git add . && git commit -m
	au = !git add -u . && git status
	branch-name = !git rev-parse --abbrev-ref HEAD
	br = branch
	c = commit
	ca = commit --amend
	cam = commit -am
	cm = commit -m
	co = checkout
	d = diff
	f = fetch
	fo = fetch origin
	fu = fetch upstream
	l = log --oneline
	lf = log --name-only
	lfo = log --name-only --oneline
	lg = log --color --graph --pretty=format:'%C(bold white)%h%Creset -%C(bold green)%d%Creset %s %C(bold green)(%cr)%Creset %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative
	ll = log --oneline --graph --decorate
	ls-ignored = ls-files --others --exclude-from=.git/info/exclude
	r = remote
	ra = remote add
	rv = remote -v
	s = status

[color "branch"]
	current = yellow bold
	local = green bold
	remote = cyan bold
[color "diff"]
	meta = yellow bold
	frag = magenta bold
	old = red bold
	new = green bold
	whitespace = red reverse
[color "status"]
	added = green bold
	changed = yellow bold
	untracked = red bold

# Identity by directory (spec section 8). Both identities live on every
# machine; where the repository sits decides which one applies.
[includeIf "gitdir:~/Personal/"]
	path = ~/.config/git/identity-personal
[includeIf "gitdir:~/Work/"]
	path = ~/.config/git/identity-work

# Untracked machine-local overrides, included last so they win over everything
# above. Create it yourself; teeup never writes it.
[include]
	path = ~/.config/git/local
```

- [ ] **Step 5: Add `git` to the core list**

Insert `git` directly after `secrets`, giving `xcode-clt package-manager teeup-runtime dev-dirs zsh starship cli-tools secrets git`.

- [ ] **Step 6: Teach the bootstrap suite about `git`**

`git configure` reads nothing outside `run_cmd`, but `have git-lfs` and `have delta` must answer the same way on every machine or the dry-run walk differs between the developer's box and CI. Extend the `TEEUP_TEST_MISSING` line in `tests/bootstrap.sh`'s `setup()` once more:

```bash
  export TEEUP_TEST_MISSING="brew gum jq starship rg fd fzf bat eza zoxide yq btop tldr dust gpg delta git-lfs lazygit"
```

`git lfs install` is then never reached, and `delta` being hidden makes the generated include deterministic. No `git` mock is needed: the only `git` call is inside `run_cmd`, and the bootstrap suite runs with `DRY_RUN=true`.

- [ ] **Step 7: Run everything**

```bash
chmod +x capabilities/git/install capabilities/git/configure
./tests/run.sh
./bin/teeup commands --check
shellcheck --severity=warning capabilities/git/install capabilities/git/configure tests/capabilities/git.sh tests/bootstrap.sh
```

Expected: `All 18 suites passed.`, including `bootstrap.sh`; no output from the other two.

- [ ] **Step 8: Commit**

```bash
git add capabilities/git capabilities/core.list tests/capabilities/git.sh tests/bootstrap.sh
git commit -m "Add the git capability with per-directory identities and SSH signing"
```

**Real-Mac risk:** the two machine-wide footguns are handled by the generated include rather than left to the user — `commit.gpgsign` stays `false` until `~/.ssh/id_ed25519_personal.pub` exists (the `ssh` capability, which runs next, makes it; `teeup configure git` or `teeup update` then flips it on), and `core.pager` falls back to `less` when delta is missing. Signature *verification* additionally needs `gpg.ssh.allowedSignersFile`, deliberately deferred (see the self-review). What no mock can prove is the `includeIf` resolution itself: after a real bootstrap, check it with `git -C ~/Work/anything config --get user.email`.

---

### Task 7: `ssh` capability

**Files:**
- Create: `capabilities/ssh/capability`, `capabilities/ssh/install`, `capabilities/ssh/configure`, `capabilities/ssh/config/ssh/config`
- Modify: `capabilities/core.list`, `tests/bootstrap.sh`
- Test: `tests/capabilities/ssh.sh`

**Interfaces:**
- Consumes: `identity_list`, `identity_email`, `identity_key`, `copy_config_once`, `run_cmd`, `log`, `warn`.
- Produces: `~/.ssh/id_ed25519_personal` (and `_work` when a work email exists) plus their `.pub` files, which Task 6's identity files already point at and Task 8 uploads; `~/.ssh/config` with the `github.com` and `github.com-work` host aliases.
- Note the asymmetry with `git`: `ssh` iterates `identity_list`, so no work key is generated without a work email. A spare gitconfig include is free; a spare key means another passphrase and another upload.

- [ ] **Step 1: Write the failing test**

`tests/capabilities/ssh.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command ssh-add 0 ""
  # A keygen that actually leaves the two files behind, so the permission and
  # idempotency steps have something to act on.
  mock_command_script ssh-keygen <<'EOF2'
out=""
while [ $# -gt 0 ]; do
  [ "$1" = "-f" ] && { shift; out="$1"; }
  shift
done
[ -n "$out" ] || exit 1
mkdir -p "$(dirname "$out")"
printf 'PRIVATE\n' > "$out"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAKEKEY comment\n' > "$out.pub"
EOF2
  TEEUP="$TEEUP_PATH/bin/teeup"
}

seed_answers() {
  mkdir -p "$TEST_HOME/.config/teeup"
  {
    printf 'TEEUP_NAME="Ada Lovelace"\n'
    printf 'TEEUP_EMAIL="ada@example.com"\n'
    printf 'TEEUP_WORK_EMAIL="%s"\n' "${1:-}"
  } > "$TEST_HOME/.config/teeup/answers"
}

test_configure_generates_one_key_without_a_work_email() {
  setup
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  assert_file_exists "$TEST_HOME/.ssh/id_ed25519_personal" || return 1
  assert_file_exists "$TEST_HOME/.ssh/id_ed25519_personal.pub" || return 1
  [[ ! -e "$TEST_HOME/.ssh/id_ed25519_work" ]] || { echo "work key without a work email"; return 1; }
  cleanup_test_env
}

test_configure_generates_both_keys_with_a_work_email() {
  setup
  seed_answers "ada@corp.example"
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  assert_file_exists "$TEST_HOME/.ssh/id_ed25519_work" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "ssh-keygen -t ed25519 -C ada@corp.example" || return 1
  cleanup_test_env
}

test_configure_adds_the_keys_to_the_keychain() {
  setup
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  assert_contains "$(cat "$MOCK_LOG")" "ssh-add --apple-use-keychain $TEST_HOME/.ssh/id_ed25519_personal" || return 1
  cleanup_test_env
}

test_configure_installs_the_ssh_config_with_both_hosts() {
  setup
  seed_answers "ada@corp.example"
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  local body
  body="$(cat "$TEST_HOME/.ssh/config")"
  assert_contains "$body" "Host github.com-work" || return 1
  assert_contains "$body" "IdentityFile ~/.ssh/id_ed25519_work" || return 1
  assert_contains "$body" "UseKeychain yes" || return 1
  cleanup_test_env
}

# GNU stat first, BSD stat second. Trying BSD first would be wrong: GNU's
# `stat -f` means "filesystem status", so it prints something and fails, and
# the fallback's output would be appended to that garbage.
file_mode() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then
    stat -c '%a' "$1"
  else
    stat -f '%Lp' "$1"
  fi
}

test_permissions_are_tightened() {
  setup
  seed_answers ""
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  assert_equals "700" "$(file_mode "$TEST_HOME/.ssh")" || return 1
  assert_equals "600" "$(file_mode "$TEST_HOME/.ssh/id_ed25519_personal")" || return 1
  assert_equals "600" "$(file_mode "$TEST_HOME/.ssh/config")" || return 1
  cleanup_test_env
}

test_existing_key_is_not_regenerated() {
  setup
  seed_answers ""
  mkdir -p "$TEST_HOME/.ssh"
  printf 'MINE\n' > "$TEST_HOME/.ssh/id_ed25519_personal"
  printf 'ssh-ed25519 MINE comment\n' > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  assert_contains "$out" "Already present: $TEST_HOME/.ssh/id_ed25519_personal" || return 1
  assert_equals "MINE" "$(cat "$TEST_HOME/.ssh/id_ed25519_personal")" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  seed_answers ""
  local out
  out="$(DRY_RUN=true "$TEEUP" configure ssh 2>&1)"
  assert_contains "$out" "Would execute: ssh-keygen -t ed25519 -C ada@example.com" || return 1
  [[ ! -e "$TEST_HOME/.ssh/id_ed25519_personal" ]] || { echo "key written in dry run"; return 1; }
  cleanup_test_env
}

test_configure_twice_changes_nothing() {
  setup
  seed_answers "ada@corp.example"
  DRY_RUN=false "$TEEUP" configure ssh >/dev/null 2>&1
  local marker="$TEST_HOME/.idempotency-marker"
  : > "$marker"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure ssh 2>&1)"
  assert_contains "$out" "Already present: $TEST_HOME/.ssh/id_ed25519_personal" || return 1
  assert_contains "$out" "Already installed: $TEST_HOME/.ssh/config" || return 1
  assert_not_contains "$out" "Generating the" || return 1
  # chmod_once keeps the second run silent, so nothing under $HOME may change.
  local changed
  changed="$(find "$TEST_HOME" -newer "$marker" -type f \
    ! -name 'mock.log' ! -name '.idempotency-marker' 2>/dev/null)"
  assert_equals "" "$changed" "second configure must write nothing" || return 1
  cleanup_test_env
}

echo "capabilities/ssh"
run_test "configure generates one key without a work email" test_configure_generates_one_key_without_a_work_email
run_test "configure generates both keys with a work email" test_configure_generates_both_keys_with_a_work_email
run_test "configure adds the keys to the keychain" test_configure_adds_the_keys_to_the_keychain
run_test "configure installs the ssh config with both hosts" test_configure_installs_the_ssh_config_with_both_hosts
run_test "permissions are tightened" test_permissions_are_tightened
run_test "existing key is not regenerated" test_existing_key_is_not_regenerated
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "configure twice changes nothing" test_configure_twice_changes_nothing
print_summary
```

- [ ] **Step 2: Write `capabilities/ssh/`**

`capability`:

```sh
summary="ed25519 keys per identity, the Keychain agent and GitHub host aliases"
group=git
tier=core
requires="git"
provides=""
packages=""
casks=""
apps=""
interactive=true
```

`interactive=true`: `ssh-keygen` asks for a passphrase on the TTY. That is the point — macOS's Keychain then remembers it, so it is typed once per key.

`install`:

```bash
#!/usr/bin/env bash
# Nothing to install: ssh, ssh-keygen and ssh-add are part of macOS. The file
# exists so `teeup install ssh` is a recorded no-op rather than an error.
:
```

`configure`:

```bash
#!/usr/bin/env bash
# One ed25519 key per identity. ssh-keygen prompts for a passphrase; that is
# why this capability is interactive. --apple-use-keychain then stores it in
# the login Keychain, so it is typed once and never again.
ssh_dir="$HOME/.ssh"
[[ -d "$ssh_dir" ]] || run_cmd mkdir -p "$ssh_dir"

# chmod_once <mode> <path>: only chmod when the mode is actually wrong, so a
# second configure is the reported no-op the contract asks for and a dry run
# does not print four "Would execute: chmod" lines for nothing. GNU stat is
# probed first on purpose: GNU's -f means "filesystem status" and would print
# something before failing, while BSD stat rejects -c cleanly on stderr.
chmod_once() {
  local mode="$1" path="$2" current
  [[ -e "$path" ]] || return 0
  current="$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path" 2>/dev/null || true)"
  [[ "$current" == "$mode" ]] && return 0
  run_cmd chmod "$mode" "$path"
}

chmod_once 700 "$ssh_dir"

for identity in $(identity_list); do
  key="$(identity_key "$identity")"
  if [[ -f "$key" ]]; then
    log "Already present: $key"
  else
    log "Generating the $identity ed25519 key (you will be asked for a passphrase)..."
    if ! run_cmd ssh-keygen -t ed25519 -C "$(identity_email "$identity")" -f "$key"; then
      warn "ssh-keygen failed for the $identity identity; skipping the rest of it."
      continue
    fi
  fi
  chmod_once 600 "$key"
  chmod_once 644 "$key.pub"
  run_cmd ssh-add --apple-use-keychain "$key" || warn "ssh-add failed for $key."
done

copy_config_once "$TEEUP_CAP_DIR/config/ssh/config" "$ssh_dir/config"
chmod_once 600 "$ssh_dir/config"
```

`chmod_once` returns 0 on a path that does not exist, so the last statement is safe under `bash -eu` — unlike `[[ -f … ]] && run_cmd …`, whose false test would make the whole capability exit non-zero.

`config/ssh/config`:

```text
# ~/.ssh/config - installed once by teeup; this copy is yours to edit.
# ssh keeps the FIRST value it finds for each keyword, so specific hosts come
# first and the catch-all Host * block goes last.

Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_personal
  IdentitiesOnly yes

# Clone work repositories as git@github.com-work:org/repo.git. That picks the
# work key here, and cloning into ~/Work picks the work git identity.
Host github.com-work
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_work
  IdentitiesOnly yes

Host *
  # Add a key to the agent on first use and keep its passphrase in the login
  # Keychain. IdentitiesOnly is deliberately NOT set here: restricting every
  # host to explicitly named keys breaks agent-forwarded and corporate hosts.
  AddKeysToAgent yes
  UseKeychain yes
  ServerAliveInterval 60
  ServerAliveCountMax 3
```

- [ ] **Step 3: Add `ssh` to the core list**

Insert `ssh` directly after `git`.

- [ ] **Step 4: Teach the bootstrap suite about `ssh`**

Every mutation here is inside `run_cmd` and the bootstrap suite is `DRY_RUN=true`, so nothing would actually run. Mock the two commands anyway, so that a future non-dry bootstrap test (the phase 1 review's M17) cannot touch the developer's real `~/.ssh` or agent. Add to `tests/bootstrap.sh`'s `setup()`:

```bash
  # ssh capability: never let a real keygen or agent call escape a test run.
  mock_command ssh-keygen 0 ""
  mock_command ssh-add 0 ""
```

- [ ] **Step 5: Run everything**

```bash
chmod +x capabilities/ssh/install capabilities/ssh/configure
./tests/run.sh
./bin/teeup commands --check
shellcheck --severity=warning capabilities/ssh/install capabilities/ssh/configure tests/capabilities/ssh.sh tests/bootstrap.sh
```

Expected: `All 19 suites passed.`, including `bootstrap.sh`; no output from the other two.

- [ ] **Step 6: Commit**

```bash
git add capabilities/ssh capabilities/core.list tests/capabilities/ssh.sh tests/bootstrap.sh
git commit -m "Add the ssh capability with one ed25519 key per identity"
```

**Real-Mac risk, highest in this plan:** `ssh-keygen` blocks on the passphrase prompt, so `bootstrap` genuinely stops here and waits — `interactive=true` is what keeps stdin on the TTY. `UseKeychain` is macOS-only and unknown to OpenSSH elsewhere, which is fine for a macOS-only product. `ssh-add --apple-use-keychain` fails with "Could not open a connection to your authentication agent" if `ssh-agent` is not running; macOS launchd starts it on demand, but this is exactly the kind of thing only a real run proves. And `~/.ssh/config` is the sharpest `copy_config_once` in this plan: on a machine that already has one, the existing file (corporate `Host` blocks, jump hosts, `ProxyCommand` lines) is moved to `~/.ssh/config.teeup_backup_<ts>` and its diff printed inside a long bootstrap log. Read that diff before the first `ssh` to a work host, and merge what you need back.

---

### Task 8: `github` capability

**Files:**
- Create: `capabilities/github/capability`, `capabilities/github/install`, `capabilities/github/configure`
- Modify: `capabilities/core.list`, `tests/bootstrap.sh`
- Test: `tests/capabilities/github.sh`

**Interfaces:**
- Consumes: `pkg_install`, `identity_list`, `identity_key`, `have`, `run_cmd`, `log`, `ok`, `warn`.
- Produces: an authenticated `gh` (which the git credential helper in Task 6's config depends on), `gh config set git_protocol ssh`, and each identity's public key uploaded twice — once as an authentication key, once as a signing key, matching `commit.gpgsign`/`gpg.format = ssh` from Task 6.

- [ ] **Step 1: Write the failing test**

`tests/capabilities/github.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  # A gh that is signed out until `auth login` runs, and whose key list lives
  # in a file the test can seed.
  mock_command_script gh <<'EOF2'
case "$1 ${2:-}" in
  "auth status") [ -f "$HOME/gh-session" ] || exit 1 ;;
  "auth login") : > "$HOME/gh-session" ;;
  "ssh-key list") cat "$HOME/gh-keys" 2>/dev/null || true ;;
  # An upload lands in the same list a later run reads back, so running
  # configure twice can be tested the way GitHub would actually behave.
  "ssh-key add") cat "$3" >> "$HOME/gh-keys" ;;
  *) : ;;
esac
exit 0
EOF2
  TEEUP="$TEEUP_PATH/bin/teeup"
}

seed_keys() {
  mkdir -p "$TEST_HOME/.ssh"
  printf 'ssh-ed25519 AAAAPERSONALKEY ada@example.com\n' > "$TEST_HOME/.ssh/id_ed25519_personal.pub"
  printf 'PRIVATE\n' > "$TEST_HOME/.ssh/id_ed25519_personal"
}

test_install_gets_gh() {
  setup
  export TEEUP_TEST_MISSING="gh"
  local out
  out="$(DRY_RUN=true "$TEEUP" install github 2>&1)"
  assert_contains "$out" "Would execute: brew install gh" || return 1
  cleanup_test_env
}

test_configure_logs_in_with_the_two_scopes() {
  setup
  seed_keys
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "auth login --web --git-protocol ssh --scopes admin:public_key,admin:ssh_signing_key" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "config set git_protocol ssh" || return 1
  cleanup_test_env
}

test_configure_uploads_authentication_and_signing_keys() {
  setup
  seed_keys
  DRY_RUN=false "$TEEUP" configure github >/dev/null 2>&1
  local calls
  calls="$(cat "$MOCK_LOG")"
  assert_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub --type authentication --title testmac personal" || return 1
  assert_contains "$calls" "ssh-key add $TEST_HOME/.ssh/id_ed25519_personal.pub --type signing --title testmac personal (signing)" || return 1
  cleanup_test_env
}

test_configure_skips_a_key_github_already_has() {
  setup
  seed_keys
  printf 'laptop  ssh-ed25519 AAAAPERSONALKEY  12345  2026-09-11\n' > "$TEST_HOME/gh-keys"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  assert_contains "$out" "Already uploaded" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "ssh-key add" || return 1
  cleanup_test_env
}

test_configure_skips_the_login_when_already_signed_in() {
  setup
  seed_keys
  : > "$TEST_HOME/gh-session"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  assert_contains "$out" "Already signed in to GitHub." || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "auth login" || return 1
  cleanup_test_env
}

test_configure_warns_when_the_key_is_missing() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  assert_contains "$out" "teeup configure ssh" || return 1
  cleanup_test_env
}

test_configure_dry_run_uploads_nothing() {
  setup
  seed_keys
  local out
  out="$(DRY_RUN=true "$TEEUP" configure github 2>&1)"
  assert_contains "$out" "Would execute: gh ssh-key add" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "ssh-key add" || return 1
  cleanup_test_env
}

test_configure_twice_uploads_nothing_new() {
  setup
  seed_keys
  DRY_RUN=false "$TEEUP" configure github >/dev/null 2>&1
  local marker="$TEST_HOME/.idempotency-marker"
  : > "$marker"
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure github 2>&1)"
  assert_contains "$out" "Already signed in to GitHub." || return 1
  assert_contains "$out" "Already uploaded" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "ssh-key add" || return 1
  # gh config set is the only write the second run makes, and it goes to gh's
  # own state, not to a file teeup owns.
  local changed
  changed="$(find "$TEST_HOME" -newer "$marker" -type f \
    ! -name 'mock.log' ! -name '.idempotency-marker' 2>/dev/null)"
  assert_equals "" "$changed" "second configure must write nothing" || return 1
  cleanup_test_env
}

echo "capabilities/github"
run_test "install gets gh" test_install_gets_gh
run_test "configure logs in with the two scopes" test_configure_logs_in_with_the_two_scopes
run_test "configure uploads authentication and signing keys" test_configure_uploads_authentication_and_signing_keys
run_test "configure skips a key GitHub already has" test_configure_skips_a_key_github_already_has
run_test "configure skips the login when already signed in" test_configure_skips_the_login_when_already_signed_in
run_test "configure warns when the key is missing" test_configure_warns_when_the_key_is_missing
run_test "configure dry run uploads nothing" test_configure_dry_run_uploads_nothing
run_test "configure twice uploads nothing new" test_configure_twice_uploads_nothing_new
print_summary
```

- [ ] **Step 2: Write `capabilities/github/`**

`capability`:

```sh
summary="GitHub CLI, browser sign-in and SSH key upload"
group=git
tier=core
requires="ssh"
provides=""
packages="gh"
casks=""
apps=""
interactive=true
```

`interactive=true`: `gh auth login --web` prints a one-time code and waits for the browser.

`install`:

```bash
#!/usr/bin/env bash
# gh is also the git credential helper the shipped gitconfig points at, so it
# is not optional on a machine that clones over HTTPS.
pkg_install gh gh || warn "gh could not be installed; GitHub sign-in and the credential helper will not work."
```

`configure`:

```bash
#!/usr/bin/env bash
if ! have gh; then
  warn "gh is not installed; skipping the GitHub setup. Re-run: teeup install github"
  exit 0
fi

if gh auth status >/dev/null 2>&1; then
  ok "Already signed in to GitHub."
else
  log "Signing in to GitHub. A browser window opens; approve the SSH key scopes."
  if ! run_cmd gh auth login --web --git-protocol ssh --scopes admin:public_key,admin:ssh_signing_key; then
    warn "gh auth login did not complete. Re-run: teeup configure github"
    exit 0
  fi
fi

run_cmd gh config set git_protocol ssh || warn "Could not set gh's git protocol to ssh."

# One upload per identity, twice: an authentication key for pushing and a
# signing key for the SSH commit signatures the git capability turns on.
host="$(hostname -s 2>/dev/null || hostname)"
listed="$(gh ssh-key list 2>/dev/null || true)"
for identity in $(identity_list); do
  pub="$(identity_key "$identity").pub"
  if [[ ! -f "$pub" ]]; then
    warn "No $pub yet. Run: teeup configure ssh"
    continue
  fi
  # The key body is the second field; comparing on it matches whatever title
  # the key was uploaded under.
  body="$(awk '{print $2}' < "$pub")"
  if [[ -n "$body" && "$listed" == *"$body"* ]]; then
    log "Already uploaded: $pub"
    continue
  fi
  run_cmd gh ssh-key add "$pub" --type authentication --title "$host $identity" ||
    warn "Could not upload $pub as an authentication key."
  run_cmd gh ssh-key add "$pub" --type signing --title "$host $identity (signing)" ||
    warn "Could not upload $pub as a signing key."
done
```

- [ ] **Step 3: Add `github` to the core list**

Insert `github` directly after `ssh`.

- [ ] **Step 4: Teach the bootstrap suite about `github` (the one that really matters)**

`gh auth status` and `gh ssh-key list` are reads, so they are deliberately **outside** `run_cmd` and run even under `DRY_RUN=true`. `gh` exists on this developer's machine and on both GitHub runner images, so without a mock `./tests/run.sh` would make an authenticated API call and read the real account's key list during a unit-test run. Add to `tests/bootstrap.sh`'s `setup()`:

```bash
  # github capability: signed out, with an empty key list. These two calls are
  # reads, so they are not covered by DRY_RUN and would otherwise hit the real
  # gh session and the GitHub API.
  mock_command_script gh <<'EOF2'
case "$1 ${2:-}" in
  "auth status") exit 1 ;;
  "ssh-key list") : ;;
  *) : ;;
esac
exit 0
EOF2
```

`auth status` failing puts the bootstrap walk on the `gh auth login` branch, which is a `run_cmd` and therefore only printed.

- [ ] **Step 5: Run everything**

```bash
chmod +x capabilities/github/install capabilities/github/configure
./tests/run.sh
./bin/teeup commands --check
shellcheck --severity=warning capabilities/github/install capabilities/github/configure tests/capabilities/github.sh tests/bootstrap.sh
```

Expected: `All 20 suites passed.`, including `bootstrap.sh`; no output from the other two. Confirm the isolation held: `grep -c 'gh auth' "$MOCK_LOG"` is meaningless after the fact, so instead run `./tests/run.sh` with your network off once — it must still pass.

- [ ] **Step 6: Commit**

```bash
git add capabilities/github capabilities/core.list tests/capabilities/github.sh tests/bootstrap.sh
git commit -m "Add the github capability with browser sign-in and key upload"
```

**Real-Mac risk:** `gh auth login --web` opens a browser and waits for a device code; under `bootstrap` that pause is intentional. `gh ssh-key list` needs the `read:public_key` scope, which the login grants; on a pre-existing `gh` session without it the list comes back empty and the upload is attempted, where GitHub answers "key is already in use" and the warning path fires. `--type signing` needs gh 2.32 or newer.

---

### Task 9: `mise` capability

**Files:**
- Create: `capabilities/mise/capability`, `capabilities/mise/install`, `capabilities/mise/configure`, `capabilities/mise/config/mise/config.toml`
- Modify: `capabilities/core.list`, `tests/bootstrap.sh`
- Test: `tests/capabilities/mise.sh`

**Interfaces:**
- Consumes: `pkg_install`, `copy_config_once`, `user_config_dir`, `have`, `run_cmd`.
- Produces: `~/.config/mise/config.toml`; `pre-commit` installed globally through mise (the decision recorded at the top of this plan); the `upgrade.auto_prune false` setting. `capabilities/zsh/default/init` already runs `mise activate zsh` when the binary is present, so nothing wires the shell here. Phase 3's `dev-env` and the AI-CLI wrappers build on this capability.

- [ ] **Step 1: Write the failing test**

`tests/capabilities/mise.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  # A mise that knows nothing yet: `which` fails until `use` has run.
  mock_command_script mise <<'EOF2'
case "$1" in
  which) [ -f "$HOME/mise-tools" ] && grep -q "$2" "$HOME/mise-tools" || exit 1 ;;
  use) shift 2; printf '%s\n' "$1" >> "$HOME/mise-tools" ;;
  *) : ;;
esac
exit 0
EOF2
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_gets_mise() {
  setup
  export TEEUP_TEST_MISSING="mise"
  local out
  out="$(DRY_RUN=true "$TEEUP" install mise 2>&1)"
  assert_contains "$out" "Would execute: brew install mise" || return 1
  cleanup_test_env
}

test_configure_writes_the_config_and_the_setting() {
  setup
  DRY_RUN=false "$TEEUP" configure mise >/dev/null 2>&1
  assert_file_exists "$TEST_HOME/.config/mise/config.toml" || return 1
  local body
  body="$(cat "$TEST_HOME/.config/mise/config.toml")"
  assert_contains "$body" "idiomatic_version_file_enable_tools = []" || return 1
  assert_contains "$body" "experimental = false" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise settings set upgrade.auto_prune false" || return 1
  cleanup_test_env
}

test_configure_installs_pre_commit_once() {
  setup
  DRY_RUN=false "$TEEUP" configure mise >/dev/null 2>&1
  assert_contains "$(cat "$MOCK_LOG")" "mise use -g pre-commit" || return 1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure mise 2>&1)"
  assert_contains "$out" "Already installed through mise: pre-commit" || return 1
  cleanup_test_env
}

test_configure_ships_an_empty_tools_table() {
  setup
  DRY_RUN=false "$TEEUP" configure mise >/dev/null 2>&1
  # The [tools] table is the last line of the shipped file: no runtime is
  # installed at bootstrap, they arrive through `teeup install dev-env`.
  assert_equals "[tools]" "$(tail -1 "$TEST_HOME/.config/mise/config.toml")" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  DRY_RUN=true "$TEEUP" configure mise >/dev/null 2>&1
  [[ ! -e "$TEST_HOME/.config/mise/config.toml" ]] || { echo "written in dry run"; return 1; }
  cleanup_test_env
}

echo "capabilities/mise"
run_test "install gets mise" test_install_gets_mise
run_test "configure writes the config and the setting" test_configure_writes_the_config_and_the_setting
run_test "configure installs pre-commit once" test_configure_installs_pre_commit_once
run_test "configure ships an empty tools table" test_configure_ships_an_empty_tools_table
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
print_summary
```

- [ ] **Step 2: Write `capabilities/mise/`**

`capability`:

```sh
summary="mise, the runtime and tool manager"
group=languages
tier=core
requires="package-manager"
provides=""
packages="mise"
casks=""
apps=""
interactive=false
```

`provides` stays empty: mise manages `python3`, `ruby` and `java`, every one of which is on the forbidden shim list because macOS ships it (spec section 4a).

`install`:

```bash
#!/usr/bin/env bash
# capabilities/zsh/default/init runs `mise activate zsh` whenever the binary is
# on PATH, so installing it is the whole wiring step.
pkg_install mise mise
```

`configure`:

```bash
#!/usr/bin/env bash
copy_config_once "$TEEUP_CAP_DIR/config/mise/config.toml" "$(user_config_dir)/mise/config.toml"

if ! have mise; then
  warn "mise is not installed; skipping its settings and pre-commit."
  exit 0
fi

# Omarchy's reason for turning pruning off: it deletes a version some running
# process is still executing from, which breaks daemons on upgrade.
run_cmd mise settings set upgrade.auto_prune false || warn "Could not set upgrade.auto_prune."

# pre-commit lives here, not in the git capability: it is a mise-managed tool,
# and git runs before mise in the core list. `teeup update` upgrades it with
# everything else mise owns.
if mise which pre-commit >/dev/null 2>&1; then
  log "Already installed through mise: pre-commit"
else
  run_cmd mise use -g pre-commit || warn "Could not install pre-commit through mise."
fi
```

`config/mise/config.toml`:

```toml
# ~/.config/mise/config.toml - installed once by teeup; this copy is yours to
# edit. `mise use -g <tool>` appends to the [tools] table below, so the file
# grows as you add tools.
#
# Language runtimes are deliberately absent: they arrive with
# `teeup install dev-env <python|node|java|ruby|rust|go>`, which is lazy on
# purpose (spec section 6).

[settings]
experimental = false
# Leave .python-version, .nvmrc, .ruby-version and friends to the tools that
# own them; mise acts only on what this file and a project's mise.toml say.
idiomatic_version_file_enable_tools = []

[tools]
```

- [ ] **Step 3: Add `mise` to the core list**

Insert `mise` directly after `github`. The file is now exactly the spec's core order for everything that exists:

```text
# Core tier: what every terminal session needs. Ordered; each entry's
# requires= must already be satisfied by the entries above it.
# Plan 2b appends: wezterm fonts aerospace keyboard macos-defaults theme
xcode-clt
package-manager
teeup-runtime
dev-dirs
zsh
starship
cli-tools
secrets
git
ssh
github
mise
```

- [ ] **Step 4: Teach the bootstrap suite about `mise`**

`mise which pre-commit` is a read and therefore outside `run_cmd`, and `mise` exists on machines that already use it. Add to `tests/bootstrap.sh`'s `setup()`:

```bash
  # mise capability: `mise which` is a read, so DRY_RUN does not cover it.
  # Exit 1 = "that tool is not installed", which is the fresh-machine answer.
  mock_command_script mise <<'EOF2'
case "$1" in
  which) exit 1 ;;
  *) : ;;
esac
exit 0
EOF2
```

- [ ] **Step 5: Run everything**

```bash
chmod +x capabilities/mise/install capabilities/mise/configure
./tests/run.sh
./bin/teeup commands --check
shellcheck --severity=warning capabilities/mise/install capabilities/mise/configure tests/capabilities/mise.sh tests/bootstrap.sh
```

Expected: `All 21 suites passed.`, including `bootstrap.sh`; no output from the other two. This is the last task that grows the core tier, so `tests/bootstrap.sh` now mocks `security`, `dscl`, `chsh`, `defaults`, `ssh-keygen`, `ssh-add`, `gh` and `mise` on top of the phase 1 set, and hides fifteen commands through `TEEUP_TEST_MISSING`.

- [ ] **Step 6: Commit**

```bash
git add capabilities/mise capabilities/core.list tests/capabilities/mise.sh tests/bootstrap.sh
git commit -m "Add the mise capability and install pre-commit through it"
```

**Real-Mac risk:** `mise settings set` writes `~/.config/mise/settings.toml` on newer versions and into `config.toml` on older ones; either is fine, but the file teeup copied may end up modified, which `copy_config_once` will later report as "Keeping your edited …". `mise use -g pre-commit` downloads on first run, so a bootstrap without network warns and continues.

---

### Task 10: Manifest check, README and contributor docs

**Files:**
- Modify: `README.md`, `CONTRIBUTING.md`, `.github/workflows/ci.yml`
- Verify (no change expected): `capabilities/core.list`, `bin/teeup` help

**Interfaces:**
- Consumes: everything the previous nine tasks produced.
- Produces: documentation that matches the implemented contract, including the `home/` layer and the `secret` verb, both new in this plan.

- [ ] **Step 1: Confirm the manifest is in spec order**

```bash
cat capabilities/core.list
./bin/teeup list --tier core
```

Expected from `cat`, after the two comment lines: `xcode-clt package-manager teeup-runtime dev-dirs zsh starship cli-tools secrets git ssh github mise`, one per line, and nothing else. `teeup list --tier core` prints the same twelve names with their summaries, but sorted by name: `cap_list` sorts, so that command proves membership only. The `cat` is the sole check of manifest *order*, which is what `bootstrap` walks. If the manifest differs, fix it here rather than in a later task — plan 2b appends `wezterm fonts aerospace keyboard macos-defaults theme` to the end of this file and assumes these twelve lines are already correct.

- [ ] **Step 2: Confirm the `secret` verb is in the help**

```bash
./bin/teeup help | grep secret
```

Expected: `  teeup secret get|set|rm <name>  read, store or delete a Keychain secret` (added in Task 2; this step only checks it is there).

- [ ] **Step 3: Update the README preview block**

In `README.md`, under "## New runtime (preview)", add one line to the existing
fenced `bash` block, after the `teeup install <name>` line:

```bash
teeup secret set <name>   # store a secret in the macOS Keychain
```

Then replace the paragraph that begins "Capabilities implemented so far" with
these three paragraphs (plain markdown prose, no fences):

- `~/.local/bin` joins your `PATH` through the shell layer the `zsh` capability installs, so `teeup` is spelled `~/.local/bin/teeup` until you open a new terminal.
- Capabilities implemented so far: `xcode-clt`, `package-manager`, `teeup-runtime`, `dev-dirs`, `zsh`, `starship`, `cli-tools`, `secrets`, `git`, `ssh`, `github`, `mise`. The rest arrive phase by phase; `teeup list` is always the source of truth.
- Per-machine overrides live in `machines/<hostname>.conf`, a committed file that is sourced after your answers and wins over them: it is where `TEEUP_PACKAGE_MANAGER=macports` or `TEEUP_SKIP="aerospace"` belongs.

Write them as ordinary paragraphs, not as a bullet list; the dashes above are
only there to separate them in this plan.

- [ ] **Step 4: Extend the CONTRIBUTING capability section**

In `CONTRIBUTING.md`, replace items 3 and 4 of "Adding a capability (new runtime)" and append items 8 to 10:

```markdown
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
8. Shipped files live in one of three directories, by owner:
   `config/` is copied once into `~/.config` and belongs to the user after
   that; `home/` is copied once into `$HOME` under its literal dotfile name
   (`home/.zshrc` becomes `~/.zshrc`); `default/` stays teeup's and is read at
   runtime through `$TEEUP_PATH`, so upgrades improve it without touching
   anything the user edited. Thin user files source thick default files.
9. Files under `default/` and `home/` are zsh or Lua, not bash: shellcheck
   does not run on them, so keep them simple and guard every optional tool.
10. Per-machine overrides go in `machines/<hostname>.conf`, which is committed
    and sourced last, so it wins over the answers file.
```

- [ ] **Step 5: Give the Linux runner a zsh**

`.github/workflows/ci.yml:40-42` already globs `capabilities/*/install capabilities/*/configure` and `tests/**/*.sh` for shellcheck and runs `./tests/run.sh`, so every script this plan adds is already covered — no change there. One thing is missing: `tests/capabilities/zsh.sh` and `tests/capabilities/secrets.sh` now *require* zsh instead of skipping without it, and `ubuntu-latest` does not ship one. Add a step directly after "Install shellcheck":

```yaml
      - name: Install zsh (the shell layer's tests need it)
        shell: bash
        run: |
          if [[ "$RUNNER_OS" == "Linux" ]]; then
            sudo apt-get update
            sudo apt-get install -y zsh
          fi
          zsh --version
```

macOS runners already have `/bin/zsh`, so the guard only covers the Linux leg. `zsh --version` outside the guard turns a missing zsh into a failed step with an obvious message rather than a puzzling suite failure later.

- [ ] **Step 6: Run everything one last time**

```bash
./tests/run.sh
./legacy/tests/run_tests.sh
./bin/teeup commands --check
shellcheck --severity=warning bootstrap bin/teeup lib/*.sh capabilities/*/install capabilities/*/configure tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh tests/lib/*.sh tests/capabilities/*.sh
DRY_RUN=true ./bin/teeup install mise | tail -20
```

Expected: `All 21 suites passed.`, `All tests passed!`, no output from `commands --check`, no output from shellcheck, and a dry-run `install mise` that walks `xcode-clt → package-manager → mise` printing only `[DRY-RUN] Would execute: …` lines and leaving the machine untouched.

- [ ] **Step 7: Commit**

```bash
git add README.md CONTRIBUTING.md .github/workflows/ci.yml
git commit -m "Document the shell and git capabilities and the config layers"
```

---

## Verification

Run from the repository root, in this order:

```bash
command -v zsh                       # required: four suites run a real zsh
./tests/run.sh                       # 21 suites, all green, bootstrap.sh included
./legacy/tests/run_tests.sh          # the frozen suite is still green
./bin/teeup commands --check         # capability metadata lints clean
shellcheck --severity=warning bootstrap bin/teeup lib/*.sh \
  capabilities/*/install capabilities/*/configure \
  tests/helper.sh tests/run.sh tests/cli.sh tests/bootstrap.sh \
  tests/lib/*.sh tests/capabilities/*.sh
./bootstrap --dry-run                # end to end under the real environment
```

`./bootstrap --dry-run` on a Mac must reach the summary line without a single
mutation: every line that would change anything is prefixed `🔍 [DRY-RUN]`.

**What the first real run on a Mac should show,** in order:

1. `sudo -v` prompts once, then the keepalive is silent.
2. Xcode CLT and the package manager, as in phase 1.
3. The wizard asks for name, personal email, work email, package manager,
   theme and the daily set, and writes `~/.config/teeup/answers`.
4. `zsh`: three or four `brew install` lines, then **macOS asks for the account
   password** because of `chsh -s /bin/zsh`. Then `Installed /Users/you/.zshrc`
   and its two siblings, or `Keeping your edited …` on a machine that already
   had them.
5. `starship`, `cli-tools`: installs and two copied config files.
6. `secrets`: `Keychain service 'teeup' is ready.`
7. `git`: identities written, `~/.config/git/config` installed, `No …/.ssh/id_ed25519_personal.pub yet; commit signing stays off.`, and — on a
   machine migrating from the chezmoi setup — the warning that `~/.gitconfig`
   exists and wins.
8. `ssh`: **a passphrase prompt per key**, then `ssh-add --apple-use-keychain`.
   Say yes to the Keychain dialog if macOS shows one.
9. `github`: a browser window for `gh auth login`, then two `gh ssh-key add`
   calls per identity (authentication and signing).
10. `mise`: `mise use -g pre-commit` downloads a release.
11. `teeup configure git` once more, by hand: now that `ssh` has made the keys,
    the generated include flips `commit.gpgsign` to `true`. (`teeup update`
    does this for you from the next run on.)
12. The summary, then `exec zsh`. In the new shell: `teeup status` resolves
    without a path, `echo $PATH` ends with `…/.local/state/teeup/shims`,
    `echo $TEEUP_APPEARANCE` prints `dark` or `light`, `git config --get
    user.email` inside `~/Work/anything` prints the work email and inside
    `~/Personal/anything` the personal one, and `ssh -T git@github.com` greets
    you by username.

Anything in that list that does not happen is a bug in this plan's capability,
not in the user's machine; `teeup configure <cap>` re-runs one step in
isolation.

---

## Self-review

**Spec coverage.**

| Spec requirement | Section | Task |
|---|---|---|
| Core list entries `zsh starship cli-tools secrets git ssh github mise`, in that order | 5 | 2-9, manifest checked in 10 |
| Secrets in the Keychain under service `teeup`, `teeup secret get\|set\|rm`, `teeup-env` zsh function, nothing secret in the repo | 7 | 2 |
| Thin `~/.zshrc` sourcing a teeup-owned default layer; plain zsh, no framework; autosuggestions, syntax highlighting, completions sourced directly; mise, zoxide, fzf, eza, bat wired in | Interview, 7 | 3 |
| `~/.local/state/teeup/shims` appended last on PATH for the lazy mechanism | 6 | 3 |
| `TEEUP_APPEARANCE` from `defaults read -g AppleInterfaceStyle`, exit 1 means light | 7 | 3 |
| Starship as the prompt, whole file copied with a managed block for theme colours | 7 | 4 |
| CLI core: ripgrep fd fzf bat eza zoxide jq yq btop tree wget curl gnupg tldr dust; Omarchy aliases (`ls`→eza, `cd`→zoxide) | Interview | 3 (aliases), 5 (packages) |
| Git: ask name/email plus optional work email; `includeIf` for `~/Work` and `~/Personal`; both identities on the work laptop; aliases and modern defaults | Interview, 8 | 6 |
| Git extras: gh CLI and credential helper, lazygit, delta, git-lfs, pre-commit | 7 | 6 (delta, lfs, lazygit), 8 (gh), 9 (pre-commit) |
| SSH: ed25519 per identity, Keychain via ssh-agent, upload via gh, SSH commit signing, host aliases per key | Interview, 8 | 6 (`gpg.format ssh`), 7 (keys, config), 8 (upload) |
| mise as the runtime and tool manager, no runtimes at bootstrap | Interview, 6 | 9 |
| `config/` copied once and user-owned, `default/` teeup-owned and read at runtime, `home/` for `$HOME` dotfiles | 4, 7 | 3, 10 (documented) |
| Migration: every user-facing file goes through `copy_config_once`, foreign files backed up with a diff | 10 | 3, 5, 6, 7 (every shipped file) |
| Content ported from the chezmoi repo: `~/.config/shell/{envs,aliases,functions}`, gitconfig aliases, the `javav` function | 10 | 3, 6 |
| Phase 1 review follow-ups in `lib/` and `bin/teeup` | — | 1 |

**Placeholder scan.** No `TBD`, `TODO`, `FIXME`, `...` standing in for code, or "same as Task N" anywhere in this plan. Every file that the engineer must create appears in full, including all four `config/` files, all six `default/` zsh files, the three `home/` dotfiles and all nine test suites. The three sentences that reference another task (`pre-commit` in Task 6, the palette markers in Task 4, the `teeup-env` source line in Task 3) name the exact file and symbol rather than deferring content.

**Name and type consistency, checked pairwise.**

- `user_config_dir` — produced in Task 1 (`lib/core.sh`), consumed in Tasks 3, 4, 5, 6, 9; always as `"$(user_config_dir)/<tool>/<file>"`, never mixed with a hand-rolled `${XDG_CONFIG_HOME:-…}`.
- `identity_list`, `identity_email <id>`, `identity_key <id>`, `answers_has_work` — produced in Task 1 (`lib/answers.sh`), consumed in Tasks 6, 7, 8. `identity_key` returns the **private** key path everywhere; `.pub` is appended by the caller in all three consumers (`signingkey = $key.pub`, `chmod 644 "$key.pub"`, `pub="$(identity_key …).pub"`).
- `git` iterates `personal work` literally, `ssh` and `github` iterate `identity_list`. The asymmetry is deliberate and is commented in both Task 6 and Task 7.
- `capabilities/secrets/default/functions.zsh` — produced in Task 2, sourced by exact path in Task 3's `default/rc`.
- `TEEUP_APPEARANCE` (`dark`/`light`), `TEEUP_STATE_DIR` (`${XDG_STATE_HOME:-$HOME/.local/state}/teeup`, identical to `lib/core.sh`), and `$TEEUP_STATE_DIR/current/theme/$TEEUP_APPEARANCE/env.sh` — exported and sourced in Task 3, and are the two contracts plan 2b's `theme` capability writes against.
- `# teeup:theme-palette:start` / `# teeup:theme-palette:end` with `palette = "teeup-dark"` on the line above — produced in Task 4, regenerated by plan 2b.
- `BAT_THEME` — defaulted in Task 3's `default/env`, overridden by the generated theme file in `default/rc`, and deliberately not set in Task 5's `bat/config` (asserted by `assert_not_contains "$body" "--theme"`).
- `lazygit` — declared only in Task 6's `packages`, aliased as `lg` in Task 3's aliases behind a `command -v` guard, absent from Task 5.
- `pre-commit` — installed only in Task 9; Task 6 prints a pointer and installs nothing.
- `delta` — package `git-delta`, command `delta` in Task 6's `pkg_install git-delta delta`, matching `core.pager = delta` and `diffFilter = delta --color-only` in the same task's shipped config.
- `gh` — `pkg_install gh gh` in Task 8, matching the `!gh auth git-credential` helper in Task 6's config.
- `capabilities/core.list` — grows by exactly one line per task, always at the spec position, ending as the twelve lines Task 10 verifies.
- Test suite count — 13 (Task 1) → 14, 15, 16, 17, 18, 19, 20, 21; every task's run step states the number it expects.
- Every capability declares `packages` matching what its `install` actually calls, because `packages=` drives the generic `update` and `remove` verbs in a later phase.

**Deliberately deferred to phases 3 to 5.**

- `gpg.ssh.allowedSignersFile` and signature *verification* (creating signatures works without it). Phase 4, with `teeup doctor`. Enabling `commit.gpgsign` itself is **not** deferred: Task 6's generated include turns it on as soon as the key exists.
- `teeup doctor`, `update`, `reset`, `menu`, `config get|set|edit`, `migrate legacy`, `dev` verbs, hooks, migrations. Phases 4 and 5, per the spec's migration table.
- Lazy shims, `lazy-run`, mise wrappers for the AI CLIs, `teeup install dev-env <lang>`, `teeup launch`. Phase 3. This plan only reserves the PATH slot (`default/env`) and installs mise.
- The daily tier (`emacs neovim zed vscode chrome obsidian`) and `tmux`. Phase 3. The zsh layer already guards on `nvim` (`n`) and `emacsclient` (`e`, `et`, `EDITOR`) so those capabilities need no shell change.
- Starship light/dark switching, which needs `teeup theme set` to rewrite the `palette =` line above the managed block. Plan 2b or phase 4; the marker contract and the line's position (above every table header) are fixed here.
- The palette *key set*: 2a ships `black red green yellow blue magenta cyan white`, while 2b's semantic palette is `accent selection muted background … bright_*`. Nothing breaks — this file's module styles use built-in colour names only — but the first `teeup theme set` replaces the whole block, so the shipped keys are a placeholder, not a contract.
- `packages="zsh …"` naming a formula that `pkg_install zsh zsh` can never install on macOS (the command guard always fires). It costs nothing today and matters only when the generic `update`/`remove` verbs land in phase 4; the fix belongs with them.
- Machine-specific content from the old dotfiles that deliberately did not come across: the work Jira hyperlink rule (goes to `~/.wezterm_local.lua`, plan 2b), the Emacs-package checkout loop and `GOPATH` (documented as examples in `~/.config/zsh/local.zsh`), the ediff mergetool block, the p10k instant prompt, SDKMAN/rbenv/pyenv init, and the tmux themepack line.
- Phase 1 review minors not touched here: M4 (`sort -V` for the CLT label), M9 (`__` collision in stock record paths), M10 (`mock_command` quoting), M11 (`mkdir -p` per log line), M12 (commit `4a492db`'s subject), M13 (stale shellcheck directives in `legacy/`), M15 (`package-manager` inheriting bootstrap's stdin), M16 (`post-bootstrap` hook), M17 (a second non-dry bootstrap run asserting no mutations), M18 (`tests/run.sh` locale substitution), M19-M21 (tidiness and one stale plan sentence).

**Per-suite test counts after this plan** (plan 2b should count from these, not from today's file):

| Suite | Before | After |
|---|---|---|
| `tests/lib/answers.sh` | 8 | 13 |
| `tests/lib/capability.sh` | 10 | 11 |
| `tests/lib/core.sh` | 9 | 10 |
| `tests/lib/files.sh` | 9 | 10 |
| `tests/lib/pkg.sh` | 14 | 15 |
| `tests/cli.sh` | 11 | 13 |
| `tests/bootstrap.sh` | 12 | 12 (mocks only) |
| `tests/capabilities/teeup-runtime.sh` | 4 | 5 |
| `tests/capabilities/secrets.sh` | — | 9 |
| `tests/capabilities/zsh.sh` | — | 9 |
| `tests/capabilities/starship.sh` | — | 5 |
| `tests/capabilities/cli-tools.sh` | — | 5 |
| `tests/capabilities/git.sh` | — | 11 |
| `tests/capabilities/ssh.sh` | — | 8 |
| `tests/capabilities/github.sh` | — | 8 |
| `tests/capabilities/mise.sh` | — | 5 |

Suite *files* go from 13 to 21. The "before" numbers are what is on disk today; count `run_test` lines rather than trusting these if a task has already landed.

**Known test-environment caveats.**

- Three `zsh` tests and one `secrets` test run real `zsh`. A machine without zsh makes them **fail**, with the message naming the install command — deliberately, because `run_test` hides the output of a passing test, so a "skipped" notice would be invisible and plan 2b would inherit an unverified `TEEUP_APPEARANCE` contract. Task 10 adds the CI step that installs zsh on `ubuntu-latest`; macOS runners always have `/bin/zsh`.
- `tests/capabilities/starship.sh` parses the shipped TOML with `python3 -c 'import tomllib'` when that is available (3.11+), and always checks the cheaper line-order property that `palette` precedes every table header.
- `tests/capabilities/ssh.sh` defines its own `file_mode` helper because `stat -c` (GNU) and `stat -f '%Lp'` (BSD) are mutually incompatible, and GNU's `-f` succeeds partially instead of failing cleanly.
- `mock_macos_base` mocks `id` to print `501` for every flag, so `${USER:-$(id -un)}` in the `zsh` install resolves to `501` under tests and to the real login name on a Mac. The `dscl` mock is what the assertion actually reads.
- `tests/bootstrap.sh` is extended by eight of the ten tasks, because `bootstrap --dry-run` runs every capability named in `core.list`. The two calls that are reads, and therefore escape `DRY_RUN` — `gh auth status` / `gh ssh-key list` and `mise which` — are mocked there for hermeticity, not for convenience: without them a unit-test run would query the GitHub API with the developer's own session.
- Nothing in this plan has been run on a real Mac. The two steps that cannot be exercised under mocks at all are `chsh` (Task 3) and the `ssh-keygen` passphrase prompt (Task 7); both are marked `interactive=true` and both print what to run by hand when they fail.

**Changes made after the plan review** (`.superpowers/sdd/phase2a-plan-review.md`), so a reader of both documents can reconcile them: B1/I2 the bootstrap-suite mock steps in Tasks 2-9; B2 the per-test `TEEUP_TEST_MISSING` for `git-lfs`; B3 `palette` and the marker block moved above every table header, with a parser-backed test; B4 the two `ls | grep` idioms replaced by glob loops and the two `~/.gitconfig` messages by `$HOME/.gitconfig`; I1 `sort -o "$tmp" "$tmp"`; I3 `require_zsh` fails loudly plus the CI zsh step; I4 configure-twice tests for `secrets`, `ssh` and `github`; I5 `secrets/configure` warns instead of exiting 1; I6 the per-suite table above. Minors 1, 2, 5, 6, 13, 14, 17, 19 and 20 are fixed in place; Minors 10, 11 and 12 are now rows in the Decisions table; Minor 9 is fixed by `chmod_once`; Minors 3 and 4 are fixed by the `zsh -n` and TOML checks. Beyond the review's list, the first two "real-Mac risks" it raised are now closed in code: `commit.gpgsign` and `core.pager` are switched on by the generated include only when the key and the binary exist.
