# Phase 2a final review — shell and git group

Reviewer: senior code reviewer (read-only). Base `4f01454`, head `794019c`, 16 commits.
Requirements read: spec sections 4, 5, 7, 8; plan header, Global Constraints, Decisions,
File structure, Verification, Self-review; the deferred/ruling ledger.

Checks actually run here (each once):

| Check | Result |
|---|---|
| `./tests/run.sh` | **All 21 suites passed** (zsh 5.9 present, so the four real-zsh tests ran) |
| `./bin/teeup commands --check` | clean, exit 0 |
| `shellcheck --severity=warning` over the plan's file list | clean, exit 0 |
| `zsh -f` sourcing of the shipped layer under a temp `HOME` | `zsh -n` clean on all 11 shipped fragments; `TEEUP_APPEARANCE` exported; teeup shims last on `PATH`; re-sourcing leaves `PATH` byte-identical |
| `DRY_RUN=true ./bootstrap` under a temp `HOME` with the suite's mocks | reaches the summary, exit 0, **zero files written** under `$HOME` beyond the seeded answers file |

---

## Strengths

- **Dry-run fidelity is real, not asserted.** The end-to-end dry run walked all twelve core
  capabilities and wrote nothing; every mutating line carried the `🔍 [DRY-RUN]` prefix, and the
  three reads that legitimately escape `DRY_RUN` (`security find-generic-password`,
  `gh auth status`/`ssh-key list`, `mise which`) are mocked in `tests/bootstrap.sh:18-47` for
  hermeticity rather than convenience.
- **Idempotency is tested behaviourally, not by message.** `tests/capabilities/ssh.sh:117`,
  `github.sh:249` and `secrets.sh:247` each stamp a marker and then assert `find -newer` finds
  nothing — a much stronger contract than "prints Already". `chmod_once`
  (`capabilities/ssh/configure:13-19`) exists precisely so the second run is silent, and it probes
  GNU `stat` before BSD `stat` for the documented reason.
- **The 2b contracts are all in place and provable.** `capabilities/starship/config/starship.toml:18`
  has root-level `palette =` above every table header, with the markers at 20/40 and a
  `tomllib` test (`tests/capabilities/starship.sh:45`) that proves the key is root-level rather
  than swallowed by a table; `TEEUP_APPEARANCE` and
  `$TEEUP_STATE_DIR/current/theme/$TEEUP_APPEARANCE/env.sh` are exported/sourced in
  `capabilities/zsh/default/rc:17-29`; `capabilities/core.list` ends exactly
  `... secrets git ssh github mise`.
- **Cross-task integration is genuinely single-sourced.** `identity_list`/`identity_email`/
  `identity_key` (`lib/answers.sh:82-102`) are the only place the identity→email→key mapping
  lives; `git`, `ssh` and `github` all key off them, and the deliberate asymmetry (`git` iterates
  `personal work` literally, the other two iterate `identity_list`) is commented at both ends.
- **The two loud-failure traps the plan worried about are closed in code.** `core.pager = delta`
  and `commit.gpgsign = true` ship as defaults but are switched back off by the later-included
  `teeup-generated` when delta or the key is missing (`capabilities/git/configure:43-77`), and
  `tests/capabilities/git.sh:110` pins the include *order* by line number, which is the property
  that actually matters.
- **PATH assembly is correct and idempotent.** Verified empirically: `.local/bin` first, package
  prefixes next, mise shims then teeup shims appended last, and a second source of the layer
  leaves `PATH` unchanged (`path_prepend` re-prepends, `path_append` skips).
- **Secret handling was hardened past the plan.** The `set +x` window plus the anchored name
  pattern (`bin/teeup:100-123`) are covered by a real `bash -x` leak test
  (`tests/capabilities/secrets.sh:296`), and the dry-run line is redacted by hand rather than
  going through `run_cmd`.
- **bash 3.2 / BSD discipline holds** throughout the new code: no `declare -A`, no `mapfile`, no
  `${var^^}`, `sort -o "$tmp" "$tmp"` instead of a GNU-only redirect, `stat` probed both ways,
  `hostname -s` with a fallback, and the one `[ … -le … ]` on possibly non-numeric input is
  guarded with `2>/dev/null`.
- **Docs match the code.** The three-owner model (`config/`, `home/`, `default/`), the
  "don't wrap the file primitives in `run_cmd`" rule and the `machines/<hostname>.conf`
  precedence claim are all true of `lib/answers.sh:26-35` and `lib/files.sh`.

---

## Issues

### Critical

None.

### Important (I would block a merge on these three)

**I1. `setopt EXTENDED_GLOB` breaks git revision syntax in every interactive shell.**
`capabilities/zsh/default/rc:37`

What: the global `setopt AUTO_CD EXTENDED_GLOB INTERACTIVE_COMMENTS NO_BEEP` turns `^` into a
glob operator, so ordinary git commands die before git ever sees them. Verified on this host with
zsh 5.9:

```
$ zsh -f -c 'setopt EXTENDED_GLOB; print HEAD^'
zsh:1: no matches found: HEAD^
```

`git show HEAD^`, `git log HEAD^`, `git reset HEAD^`, `git diff HEAD^!` all fail the same way.

Why it blocks: this is the shell layer of a distribution whose headline feature in this very plan
is the git setup, and `HEAD^` is the most-typed git argument there is. Nothing in the suite covers
it, so it would ship unnoticed and then be blamed on the machine. It is also user-visible from the
first prompt, unlike anything else on this list.

Fix: either drop `EXTENDED_GLOB` from that line, or add `NO_NOMATCH` so unmatched patterns pass
through unchanged. Verified working:

```
$ zsh -f -c 'setopt EXTENDED_GLOB NO_NOMATCH; print HEAD^ HEAD~1 "a*z"'
HEAD^ HEAD~1 a*z
```

`setopt … EXTENDED_GLOB NO_NOMATCH …` is the one-token change; add a test in
`tests/capabilities/zsh.sh` asserting `zsh -f -c '. rc; print HEAD^'` prints `HEAD^`.

---

**I2. `teeup secret set` echoes the secret to the terminal.**
`bin/teeup:119` with `lib/ui.sh:12` and `lib/ui.sh:17`

What: the value is read with `ui_input`, which uses `gum input` (no `--password`) or a plain
`IFS= read -r answer` — terminal echo on. The typed secret is displayed, stays in the scrollback,
and lands in any `script`/tmux capture of the session. It is then passed as `-w "$value"` in the
`security` argv, visible to any other process of the same user for the life of the call.

Why it blocks: the capability's stated contract (plan Task 2, `bin/teeup:93-96`) is that the value
never reaches the repo, the answers file or a log — and the terminal buffer is a log. The code goes
to real trouble to redact the dry-run line and to suppress `set -x`, which makes the unredacted
echo an inconsistency rather than an accepted trade-off. Fix is small and local.

Fix: add a password mode to `ui_input` (`ui_input --password <prompt>` → `gum input --password`, or
`read -rs answer; printf '\n' >&2` in the fallback) and use it from `cmd_secret`; the piped-stdin
path the tests rely on is unaffected by `-s`. Optionally drop the argv exposure too:
`security add-generic-password -U -s teeup -a "$name" -w` with no value prompts on the tty, but
that breaks the pipe-driven tests — the `read -rs` change alone is enough to close the echo.

---

**I3. The GitHub key-upload path cannot recover a partial upload, and never ensures the scopes.**
`capabilities/github/configure:7-15` and `22-39`

What: two coupled gaps.
1. When `gh auth status` already succeeds (line 7) the login is skipped entirely, so a machine whose
   `gh` was authenticated earlier — the common case for anyone who already uses `gh`, including this
   repo's author — never obtains `admin:public_key` / `admin:ssh_signing_key`. Both
   `gh ssh-key add` calls then fail and only a `warn` is printed.
2. The "already uploaded" check (line 32) compares the key *body* against the whole
   `gh ssh-key list` output, with no notion of key type. So once the authentication key is on the
   account, the signing upload is skipped forever, even though it never happened. Re-running
   `teeup configure github` — the remedy the plan's Verification step 11 tells the user to reach
   for — prints `Already uploaded` and exits.

Why it blocks: the end state is silent and permanent. Commits are signed locally (the generated
include flips `commit.gpgsign` on as soon as the key exists) but GitHub shows them **Unverified**,
and no teeup command will ever fix it. `tests/capabilities/github.sh:209` enshrines the
body-only comparison, so the suite actively protects the bug.

Fix: (a) when already signed in, check the scopes and refresh rather than assume —
`gh auth status` prints a `Token scopes:` line; if either scope is absent, run
`run_cmd gh auth refresh -h github.com -s admin:public_key,admin:ssh_signing_key` (the capability
is already `interactive=true`). (b) Dedupe per type: `gh ssh-key list` emits a TYPE column, so
build the "already there" test from `body` **and** type (`authentication`, `signing`) instead of
from `body` alone, and extend the github suite's mock to record the `--type` it was given.

### Minor

1. **`~/.zshrc` ends on a failing test, so the first prompt shows an error.**
   `capabilities/zsh/home/.zshrc:11-12`. `[ -r …local.zsh ] && . …` is the last statement in the
   file; when `local.zsh` is absent (user deleted it, or `XDG_CONFIG_HOME` differs from where
   `configure` wrote it) sourcing `.zshrc` returns 1. Measured here: `status_no_local=1`. Starship's
   `character` module reads `$status`, so the very first prompt renders red for no reason.
   Fix: wrap in `if … fi`, or append `|| true`, or end the file with `:`.

2. **The shipped gitconfig hardcodes `~/.config/git/…` while `configure` writes to
   `$(user_config_dir)/git/…`.** `capabilities/git/config/git/config:10,56,109,111,116` versus
   `capabilities/git/configure:4`. With a non-default `XDG_CONFIG_HOME` git reads the config from
   the XDG path (git honours the variable) but its includes point at `~/.config/git`, which teeup
   never wrote — every identity and every generated setting silently disappears. Same shape in
   `capabilities/zsh/home/.zshenv:4` (`$HOME/.config/teeup/env` vs `TEEUP_CONFIG_DIR`), though
   `.zshrc:11` gets it right. Fix: generate the five include paths in `configure`
   (`write_managed_file` already writes two other files), or document that teeup assumes the
   default XDG location for git and assert it in `configure`.

3. **`git lfs install --skip-repo` mutates the file `copy_config_once` just installed, so the
   stock record goes stale on the first real run.** `capabilities/git/configure:92-93`. With no
   `~/.gitconfig`, git's `--global` target is `$XDG_CONFIG_HOME/git/config` — the file teeup copied
   one line earlier — so git-lfs appends its `[filter "lfs"]` block there. From the second
   `teeup configure git` onwards the user sees `Keeping your edited …/.config/git/config` instead of
   `Already installed`, and teeup can no longer tell a real user edit from git-lfs's block (this
   also disarms a future `teeup reset git`). `tests/capabilities/git.sh:146` asserts
   `Already installed` and passes only because the mocked `git` writes nothing — the test proves
   less than it claims. Fix: re-`stock_record` the dest after the lfs call, or put the filter block
   in `teeup-generated` and drop the call. (Same class as the deferred `mise settings set` note.)

4. **`n()` is defined without an `nvim` guard.** `capabilities/zsh/default/functions:19-25`. Every
   other optional tool is behind `command -v` (`e`, `et`, `lg`, `zd`), and the plan's self-review
   claims "the zsh layer already guards on `nvim` (`n`)" — it does not. On a fresh Mac before the
   daily tier, `n` gives `command not found: nvim`. Faithful to the plan text, so this is the
   plan's defect carried forward. Fix: wrap in the same `if command -v nvim` block.

5. **`teeup-env` builds an invalid variable name from a legal secret name.**
   `capabilities/secrets/default/functions.zsh:11,13`. `cmd_secret` accepts `.` and `-` in names
   (`bin/teeup:104`), so `teeup-env my.key` runs `export MY.KEY=…` and dies with zsh's
   "not an identifier". This is the "teeup-env export edge case" minor the Task 2 review raised;
   it was not fixed. Fix: `var="${2:-${${(U)name}//[.-]/_}}"`, or reject such names in the function.

6. **A stray trailer on one commit.** `af606f8` ("Add the zsh capability …") carries
   `Claude-Session: https://…`; the other eleven commits carry nothing. The plan's Global
   Constraints and the review brief both say plain imperative subjects with no trailers, and the
   ledger shows the controller already amended this commit once to strip a `Co-Authored-By`. Fix
   now, while the branch is unpushed: `git rebase` that one message. Cheap, and it cannot be done
   after a merge.

7. **README formatting regression.** `README.md:33,35,37` are single unwrapped long lines in a file
   wrapped at ~78 columns elsewhere, and line 33 opens with a bare path (`~/.local/bin joins your
   PATH…`), which reads oddly and renders as the start of a sentence in lower case. Fix: rewrap and
   lead with a word.

8. **`mise settings set upgrade.auto_prune false` runs unconditionally on every configure.**
   `capabilities/mise/configure:11`. Harmless and dry-run-safe, but it is the one line in the
   capability that is not "check, then act", and it is what makes the copied `config.toml` read as
   user-edited (deferred item 6). Fix: `mise settings get upgrade.auto_prune` first.

9. **`packages="zsh …"` names a formula `pkg_install zsh zsh` can never install.**
   `capabilities/zsh/capability:6` and `capabilities/zsh/install:4`. Acknowledged in the plan's
   self-review as a phase-4 concern (it only matters when the generic `update`/`remove` verbs land).
   No change needed now; recorded so phase 4 does not rediscover it.

10. **`--dry-run` is not read-free on a real Mac.** `capabilities/secrets/configure:15`,
    `capabilities/github/configure:7,22`, `capabilities/mise/configure:16` all read live state
    during a dry run (Keychain probe, `gh auth status`, `gh ssh-key list` → a GitHub API call with
    the developer's own session, `mise which`). Correct by the plan's rules (reads are not
    mutations) and mocked in tests, but the README/CONTRIBUTING promise of "nothing happens" is
    worth one sentence of nuance.

11. **FPATH grows on every re-source.** `capabilities/zsh/default/rc:41-46` (the deferred minor).
    `typeset -U fpath path` before the loop fixes it in one line and would also make the PATH
    helpers' de-duplication belt-and-braces.

---

## Triage of the deferred list

| # | Deferred item | Triage |
|---|---|---|
| 1 | Pre-flight narration nits (anchor typo, `core.list` comment wording, "fifteen commands") | **disagree** with recording them as findings at all — all three are prose about the plan, and the code matches the intent; nothing to fix. |
| 2 | Task 1: no dedicated tests for `cmd_install`'s `cap_order` capture, the bootstrap summary line, `machines/.gitkeep`; `cask_install` resolve-first unproven | **defer** — the `cap_order` failure path is covered by `tests/lib/capability.sh:128` and the resolve-first change by `tests/lib/pkg.sh:150`; the summary line and `.gitkeep` are not behaviour. |
| 3 | Task 2: both review findings fixed (set +x guard, anchored name) | **agreed, closed** — verified by `tests/capabilities/secrets.sh:280,296`; see Minor 5 for the one leftover edge (`(U)name`). |
| 4 | Task 3: FPATH loop has no membership check, so re-sourcing duplicates entries | **defer**, but take the one-line `typeset -U fpath path` if the branch is touched again for I1 (same file, same block). |
| 5 | Task 6: `gpg.ssh.allowedSignersFile` unset, so local verification does not work | **defer** — spec-acknowledged, phase 4 with `teeup doctor`. Note it interacts with I3: unverifiable locally *and* unverified on GitHub is a worse combination than either alone. |
| 6 | Task 9: no tomllib validity test for the mise config; `mise settings set` rewrites the copied file so the stock sha reads as user-edited | **defer** the missing test (the suite already asserts the two settings and the trailing `[tools]`); **fix-before-merge** the stale-stock-sha half only if you take Minor 3, since git has the identical bug and one fix pattern covers both. |

---

## Real-Mac risks (top three)

1. **`git show HEAD^` fails in the new shell (I1).** This is the first thing that will happen on a
   real Mac, in the first hour, and it will look like a broken machine rather than a shell option.
   Highest-probability, highest-annoyance item on the branch.
2. **`gh` is already authenticated on the target Mac, so neither key uploads (I3).** The target
   machine is a working developer box migrating off chezmoi; `gh auth status` will succeed with
   scopes from an older login, both `gh ssh-key add` calls will fail with a scope error, and the
   second `teeup configure github` will say `Already uploaded` and do nothing. Signing is on
   locally, GitHub says Unverified, and the repair is a manual `gh auth refresh`.
3. **Signing keys, passphrases and the leftover `~/.gitconfig`.** Once `ssh` has made the keys, the
   next `teeup configure git` sets `commit.gpgsign = true`; `git` signs through
   `ssh-keygen -Y sign`, which uses the agent but has no Keychain integration of its own, so after a
   reboot — before any `ssh` connection triggers `UseKeychain` — commits can prompt for the key
   passphrase, and with `allowedSignersFile` unset nothing verifies locally. On the same migrating
   machine, `~/.gitconfig` exists and *wins* over everything teeup writes; `configure` warns twice
   (`capabilities/git/configure:83-88`) but the user must act, or the new identity/pager/signing
   settings appear to be ignored. Worth walking through by hand on the first real run:
   `ssh-add --apple-load-keychain; git -C ~/Personal/any commit --allow-empty -m t`.

---

## Assessment

**Ready to merge? With fixes.**

The branch is faithful to the spec and the plan: the eight capabilities exist with the metadata
contract the spec fixes in 4a, the core list is in the spec's order, the three-owner config model is
implemented rather than described, identity-as-a-directory-rule is real on both the git and ssh
sides, and every plan deviation I checked is in the Decisions table with a reason I agree with
(pre-commit under `mise`, lazygit under `git`, both identity files always written,
`IdentitiesOnly` per host, literal plugin prefixes, `/bin/zsh` as the login shell). Twenty-one
suites, shellcheck, the metadata lint and an end-to-end dry run are green here, the dry run wrote
nothing, and the four contracts plan 2b depends on are present and independently proved by tests —
2b is not blocked by anything on this list.

What holds the merge is three small, local defects, none of which needs a redesign: the
`EXTENDED_GLOB` option (one token, plus a test), the echoed secret (one flag through `ui_input`),
and the GitHub upload path that cannot self-heal (a scope check plus a per-type dedupe, with the
mock extended to see `--type`). All three are in code the suite already covers, so each comes with
an obvious place to put the regression test. I would also take Minor 6 (the stray trailer) in the
same pass, because it can only be fixed while the branch is unpushed, and Minor 1 (the first prompt
rendering as an error) because it is one character and it is the first thing a user sees.

Everything else on the Minor list, and everything on the deferred list, can land afterwards without
risk to phase 2b or to the fresh-Mac path.
