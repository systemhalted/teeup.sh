# Final review: teeup redesign, Phase 0 and 1

Branch `feat/omarchy-redesign`, base `4dd2920`, head `f9f9e16`, 23 commits.
Reviewed against `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md`
(sections 4, 5, 7, 10) and `docs/superpowers/plans/2026-09-11-redesign-phase1-runtime.md`.

Verification run during the review (each once):

- `./tests/run.sh` — 13 suites, all green.
- `shellcheck --severity=warning` over `bootstrap bin/teeup lib/*.sh capabilities/*/{install,configure} tests/**` — clean.
- `./bin/teeup commands --check` — clean.
- Targeted `DRY_RUN=true` and one non-dry `teeup configure` under a throwaway `$HOME` to settle four concrete doubts (results quoted inline below).

---

## Strengths

- **The architecture in the spec survived contact with the implementation.** The
  capability contract is exactly what section 4a describes: a sourced `capability`
  metadata file, separate `install` and `configure` run as `bash -eu` with `lib/`
  preloaded and the answers file sourced, `TEEUP_CAP`/`TEEUP_CAP_DIR` exported,
  `requires=` resolved into a run order, `provides=` linted against the
  macOS-ships-it list. Nothing was quietly reinterpreted.
- **The dry-run seam is genuinely faithful for everything it covers.** Every
  machine mutation in `bootstrap`, `bin/teeup`, the four capabilities and the
  `files.sh`/`state.sh` primitives is either a `run_cmd`/`run_privileged` call or
  a primitive with its own `DRY_RUN` guard, and the tests assert absence of the
  artifact, not just presence of the message (`tests/bootstrap.sh:204`,
  `tests/capabilities/teeup-runtime.sh:132`, `tests/lib/files.sh:177`). The one
  place where the seam leaks is C1 below, and it leaks in the other direction.
- **Bash 3.2 and BSD discipline is consistent.** No `mapfile`, `declare -A`,
  `${var,,}`, `readlink -f`, `&>`, GNU-only `sed -i`, or `grep -P` anywhere in the
  new tree (grepped). `readlink` is followed by hand in `bin/teeup:9-13`,
  `shasum` falls back to `sha256sum`, `sed -i.bak` appears only in tests where
  both BSD and GNU accept it, `${arr[@]}` on a possibly-empty array is guarded by
  a count check. `_stock_record_path` was converted from `sed` to parameter
  expansion per the Task 4 ruling.
- **`cap_meta_get` sources metadata in a subshell with `set +eu`**, so a malformed
  or partially-filled `capability` file cannot leak assignments into the caller or
  trip `set -u`. That is the right call for a file third parties will write.
- **The `run_logged` stdin rule matches the spec and is actually tested**
  (`tests/lib/core.sh:56`) rather than asserted by reading the source — the test
  pipes text in and checks it does *not* arrive when `interactive=false`.
- **The integration seams the brief flagged all line up.** `pkg_backend` resolves
  in the caller's shell via `_pkg_backend_resolve` and dies for real on an invalid
  answer (`tests/lib/pkg.sh:37` proves the caller fails with the right message);
  `answers_set` exports before its dry-run early return, which is what makes
  `TEEUP_DAILY=no` reach the tier logic in-process (`tests/bootstrap.sh:262`);
  `TEEUP_TEST_MISSING` is honoured by `have` only, is documented as test-only, and
  is inert unless set; `cap_run` exports `TEEUP_CAP`/`TEEUP_CAP_DIR` before
  `run_logged` so the child `bash` sees them on 3.2.
- **Tests check behaviour.** `tests/cli.sh:28` proves ordering by line number of
  real output, `tests/capabilities/teeup-runtime.sh:110` reads back the env file
  content and the symlink target, `tests/lib/answers.sh:52` round-trips a value
  containing a single quote, a double quote and spaces through a bash-sourced
  file. The grep-over-source style the spec called out as debt did not come back.
- **Commit hygiene is good.** 23 plain imperative subjects, no `Co-Authored-By`
  or "Generated with" trailers, spec and plan committed with substantive bodies.
  One exception, M12.
- **Legacy freeze is clean.** `git log --follow` works through the moves (19
  renames, no content edits beyond one shellcheck directive), CI still runs the
  legacy suite, and README/CONTRIBUTING invocations were rewritten to
  `./legacy/...` consistently.

---

## Issues

### Critical

**C1 — The bootstrap wizard never runs on a real fresh Mac.**
`bootstrap:128` / `capabilities/package-manager/configure:5` / `lib/answers.sh:17`

*What.* Step 2 (`bootstrap:121`) runs `package-manager configure`, which writes
`TEEUP_PACKAGE_MANAGER="homebrew"` into `~/.config/teeup/answers`. Step 4
(`bootstrap:128`) then asks `answers_exist`, which is `[[ -s "$(answers_file)" ]]` —
true, because step 2 just created the file. So on a genuinely fresh machine
bootstrap prints *"Using existing answers from …/answers (pass --reconfigure to
change them)"* and skips the wizard entirely. The user is never asked for name,
personal email, work email, theme or the daily set.

Verified directly (temp `$HOME`, mocked `brew`/`sw_vers`/`hostname`, `DRY_RUN=false`):

```
✅ Recorded package manager: homebrew
--- answers file after step 3 of bootstrap ---
TEEUP_PACKAGE_MANAGER="homebrew"
answers_exist=TRUE -> bootstrap SKIPS the wizard
```

*Why it matters.* This is spec section 5 step 4 not happening at all, and it is
the single step the whole configuration model (section 7) depends on. Downstream,
phase 2's `git` and `ssh` capabilities key identity off `TEEUP_NAME`/`TEEUP_EMAIL`,
which will be empty. The workaround (`--reconfigure`) is undiscoverable because
bootstrap reports the state as normal. This is also a dry-run fidelity failure in
the direction that matters: every bootstrap test runs `--dry-run`, where
`answers_set` returns before writing the file, so the suite is structurally
incapable of seeing it. `tests/bootstrap.sh:213` ("existing answers skip wizard")
passes by pre-seeding the file, which is the same code path — it does not
distinguish "the user's answers" from "the file package-manager just created".

*Fix.* Decide whether the wizard is needed *before* any capability can write the
file. Simplest: after preflight, `WIZARD_NEEDED=false; answers_exist || WIZARD_NEEDED=true`,
and gate step 4 on `[[ "$WIZARD_NEEDED" == "true" || "$RECONFIGURE" == "true" ]]`.
Alternatively make "the wizard has run" its own fact — `state_done check answers`
marked at the end of `wizard()`, or test for a wizard-only key such as
`TEEUP_NAME`. Whichever you pick, add a bootstrap test that runs with
`DRY_RUN=false` under the mocked `$HOME` and asserts the wizard prompt appears on
a fresh machine; without one, the next refactor puts it back.

### Important

**I1 — A failed Homebrew install is reported as success.**
`lib/pkg.sh:94-106`

*What.* The install branch is `run_cmd bash -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL …install.sh)"'`.
When `curl` fails, the command substitution yields an empty string, `/bin/bash -c ""`
exits 0, and the outer `run_cmd` succeeds. Control falls to
`run_cmd brew update || warn …`, whose `warn` returns 0, so `pkg_backend_prepare`
returns 0 and `package-manager install` logs `Completed`.

Verified with a `curl` stub that exits 22:

```
🔹 Installing Homebrew...
lib/core.sh: line 35: brew: command not found
⚠️ brew update returned non-zero.
prepare rc=0
```

*Why it matters.* Bootstrap proceeds to `teeup-runtime`, which fails with
`Unable to install 'gum' with Homebrew` — two steps and a misleading message away
from the actual cause. On a first real run over flaky hotel wifi this costs a
debugging session.

*Fix.* Verify the postcondition rather than the exit code: after the install
branch, `pkg_backend_path; pkg_backend_installed || return 1` (with a message
naming the installer URL). Optionally fetch the installer to a temp file with
`curl -fsSL -o` first so the download failure is itself visible.

**I2 — The Xcode CLT GUI fallback exits 0, so bootstrap continues without CLT.**
`capabilities/xcode-clt/install:14-18`, `bootstrap:117`

*What.* When `softwareupdate -l` lists no Command Line Tools label, the script
runs `xcode-select --install || true`, warns *"Complete the dialog, then re-run
./bootstrap."*, removes the on-demand marker and ends with status 0. Bootstrap's
`cap_run xcode-clt install || die "Xcode Command Line Tools are required. Complete
the installer and re-run ./bootstrap."` therefore never fires — that `die` string
is unreachable for the exact case it was written for. The run carries on into
Homebrew installation while a GUI installer is still open.

*Why it matters.* Spec section 5 makes CLT step 1 because everything after it
needs a compiler. The code already contains the correct intent in two places; only
the exit status is missing. `tests/capabilities/xcode-clt.sh:179` asserts the
warning text but not the exit status, so the gap is invisible.

*Fix.* `exit 1` at the end of the GUI-fallback branch (the script is sourced under
`bash -eu -c`, so `exit` is right). Also re-check `xcode-select -p` after
`softwareupdate -i "$label"` and fail if it is still absent. Extend the test to
assert a non-zero status and the bootstrap-level `die` message.

**I3 — `bin/teeup` honours an inherited `TEEUP_PATH`.**
`bin/teeup:14`

*What.* The script carefully resolves its own location through symlinks
(lines 8-13) and then throws the result away if `TEEUP_PATH` is already set:
`TEEUP_PATH="${TEEUP_PATH:-$(cd "$(dirname "$_self")/.." && pwd)}"`.

*Why it matters.* `capabilities/teeup-runtime/configure:10` writes
`export TEEUP_PATH=…` into `~/.config/teeup/env`, which the phase-2 shell layer
will source in every session. From then on, running `./bin/teeup` inside a second
clone loads the *installed* checkout's `lib/` and `capabilities/` while the user
believes they are testing their working copy. The Task 10 ruling identified this
and explicitly deferred the fix to "the final-review fix wave", which is this
review.

*Fix.* Drop the `:-` and always derive: `TEEUP_PATH="$(cd "$(dirname "$_self")/.." && pwd)"`.
No test churn — every test already invokes `$TEEUP_PATH/bin/teeup` from the repo
root, so the derived value is identical. (`bootstrap:10` already does the right
thing.)

### Minor

21 findings, in rough order of how likely they are to matter.

1. **M1** `capabilities/teeup-runtime/configure:19` — `ln -sfn` replaces a *regular
   file* at `~/.local/bin/teeup` with no backup. Other user-facing writes go
   through `backup_target`. Guard with `[[ -e "$link" && ! -L "$link" ]] && backup_target "$link"`.
2. **M2** `lib/answers.sh:52` — the key guard `TEEUP_[A-Z0-9_]*)` is a glob, so the
   trailing `*` matches *any* characters: `TEEUP_A.*` passes. The key then goes
   unquoted into `grep -v "^${key}="`, i.e. it is used as a regex. Confirmed:
   `answers_set 'TEEUP_A.*' hi` clears the guard and only fails later at `export`.
   Not reachable from user input today (all callers pass literals). Use
   `[[ "$key" =~ ^TEEUP_[A-Z0-9_]+$ ]]` and `grep -v "^${key}="` with the key
   escaped, or filter with `case`/`while read` instead of `grep`.
3. **M3** `README.md:14-33`, `bootstrap:160` — both tell the user to run
   `teeup status` after bootstrap, but `~/.local/bin` is not on a stock macOS
   `PATH`; the capability that adds it (`zsh`) is phase 2. Until then the summary
   should say `~/.local/bin/teeup status` or mention the PATH line.
4. **M4** `capabilities/xcode-clt/install:11` — `… | tail -1` takes the *last
   listed* CLT label, not the newest. Usually the same thing; `sort -V | tail -1`
   (or a comment explaining the assumption) is safer.
5. **M5** `bin/teeup:62-71` — `teeup list --tier` with no value silently lists
   everything (confirmed by running it). Either error out or document it.
6. **M6** `bin/teeup:55-60` — `cmd_configure` ignores `TEEUP_SKIP` although
   `cmd_install` refuses (`bin/teeup:41`). Machines that skip a capability for a
   hard reason can still be configured for it.
7. **M7** `lib/capability.sh:60` — `_cap_visit` recurses into
   `$(cap_meta_get "$c" requires)`; when a required capability does not exist,
   `die` kills only the substitution subshell, so ordering continues with an empty
   requires list after printing to stderr. `cap_check` catches this at lint time,
   but `teeup install` would proceed. Guard with `cap_exists` before recursing.
8. **M8** `lib/files.sh:143` — `refresh_config` swallows `backup_target`'s
   "Backed up …" line with `2>/dev/null` while `copy_config_once:122` shows it.
   Inconsistent, and the user loses the backup path on the noisier of the two
   operations. (Deferred item.)
9. **M9** `lib/files.sh:16-21` — flattening `/` to `__` collides for a dest whose
   own name contains `__`. No shipped config hits it. (Deferred item.)
10. **M10** `tests/helper.sh:49-54` — `mock_command` splices `$output` into the
    generated script unquoted; mock output containing a quote or a backtick breaks
    the mock. Worth a comment at minimum. (Deferred item.)
11. **M11** `lib/core.sh:42` — `_teeup_log_line` runs `mkdir -p` per log line.
    (Deferred item; plan-mandated text.)
12. **M12** commit `4a492db "Add ui.sh"` adds only `tests/lib/ui.sh`. The subject
    names a file the commit does not contain, and the suite was red at that commit,
    against the plan's "`./tests/run.sh` must be green before every commit".
13. **M13** `legacy/teeup.sh:635-641` — stale `# shellcheck source=lib/*.sh`
    directives after the move (`legacy/teeup-wizard.sh:394` was fixed). Masked at
    `--severity=warning`. (Deferred item.)
14. **M14** No `machines/` directory ships, although `lib/answers.sh:6` points at
    it and `.gitignore` now has `machines/*.draft`. A `machines/.gitkeep` plus one
    README line would make the only override layer discoverable.
15. **M15** `bootstrap:121` — `package-manager` declares `interactive=true`, so at
    step 2 its child inherits bootstrap's stdin. Harmless now (no unit reads
    stdin), but a future interactive unit at that position would consume the
    wizard's piped answers when bootstrap's stdin is not a TTY.
16. **M16** Spec section 5 step 8's `post-bootstrap` hook is absent. The plan's
    self-review defers hooks to a later plan, so this is sanctioned — recorded so
    it is not lost when the hooks plan is written.
17. **M17** Spec Verification asks for "run `./bootstrap` twice and assert the
    second run performs no mutations". No such test exists, and every bootstrap
    test runs `--dry-run` — which is precisely what hid C1. One non-dry-run
    bootstrap test under the mocked `$HOME` would have caught it and would cover
    this line too.
18. **M18** `tests/run.sh:167-170` forces `LANG=en_US.UTF-8` when the environment
    is `C.UTF-8`; that locale is not generated on `ubuntu-latest` by default, so
    the substitution can produce a locale warning rather than fix one.
19. **M19** `lib/state.sh:168,193` — `mkdir -p` duplicated between `_state_touch`
    and the `ensure` branch. (Deferred item.)
20. **M20** `lib/ui.sh:79` — `gum input` passes the default as both `--value` and
    `--placeholder`. (Deferred item; cosmetic.)
21. **M21** Plan File-structure row for `tests/helper.sh` promises `setup_teeup_env`;
    the harness provides `setup_test_env`, which is what Task 2's own interface
    list specifies. The plan text is the stale side — no code change needed.

---

## Triage of the deferred list

`.superpowers/sdd/2026-09-11-redesign-phase1-runtime/final-review-deferred.md`,
in file order. Entries that record an already-applied ruling are marked *applied*.

| # | Item | Verdict |
|---|---|---|
| 1 | Work in place rather than a worktree (process ruling) | applied — correct call, the branch was cut for this work |
| 2 | T9: `export TEEUP_CAP TEEUP_CAP_DIR` inside `cap_run` | applied — `lib/capability.sh:84`, verified by `tests/lib/capability.sh:220` |
| 3 | Task 1 git-state repair | applied — renames detected, PR #7 branch untouched at 4dd2920 |
| 4 | Task 1: stale `shellcheck source=` in `legacy/teeup.sh` | **defer** — masked at warning severity, and `legacy/` is deleted at phase 5 (M13) |
| 5 | Task 2: `mock_command` splices `$output` unescaped | **defer** — test-only; add the caveat as a comment when convenient (M10) |
| 6 | Task 3: `_teeup_log_line` runs `mkdir -p` per line | **defer** — a few hundred syscalls per bootstrap, no correctness impact (M11) |
| 7 | Task 4: `sed` → parameter expansion in `_stock_record_path` | applied — `lib/files.sh:18-19`, correct and faster |
| 8 | Task 4: `__` collision / unreachable `backup_target` dry-run / silenced backup message | **defer** the first two; **defer** the third but fix it with the next `files.sh` touch (M8, M9) |
| 9 | Task 5: `mkdir -p` duplicated in `state.sh` | **defer** — pure tidiness (M19) |
| 10 | Task 6: key pattern also accepts bare `TEEUP_` | **disagree** — the defect is wider than recorded: the glob's trailing `*` accepts *any* suffix and the key is then used as a `grep` regex (M2). Still not a merge blocker, but fix it in the same pass as C1 |
| 11 | Task 7: cask notice stays on stderr | applied — agreed, it is a warning |
| 12 | Task 7: `_pkg_backend_resolve` split | applied — the convention holds for all current callers |
| 13 | Task 7: `pkg_install` resolves the backend inside `$(package_candidates)` | **defer** — `tests/lib/pkg.sh:37` shows the `die` message still reaches the user and the caller still fails; adding `_pkg_backend_resolve` as line 1 of `pkg_install`/`cask_install` is a clean follow-up |
| 14 | Task 8: keep `4a492db` as-is | **disagree, mildly** — the subject names a file the commit does not add and the suite was red there. Not worth rewriting history on its own; reword or squash it if you rebase before merge (M12) |
| 15 | Task 8: `10#$answer` and `local opt` | applied — `lib/ui.sh:134-137`, covered by the leading-zero test |
| 16 | Task 8: gum default as both `--value` and `--placeholder` | **defer** — cosmetic (M20) |
| 17 | Task 9: unguarded `cap_meta_get` substitutions in `cap_check`; `TEEUP_CAP` persists after `cap_run` | **defer** both — unreachable today, and the persistence was an accepted trade |
| 18 | Task 10: `teeup list --tier` with no value lists everything | **defer** — confirmed by running it; harmless (M5) |
| 19 | Task 10: `bin/teeup` should derive `TEEUP_PATH` from its own location | **fix-before-merge** — this review is the fix wave the ruling deferred it to; one line, zero test churn (I3) |
| 20 | Task 10: `answers_load` before verb dispatch is by design | **defer** — agreed; the answers file is the user's own sourceable file |
| 21 | Task 11: `TEEUP_TEST_MISSING` hook in `have()` | **defer** — agreed; documented, inert unless set, and it is what makes the fresh-Mac tests honest |
| 22 | Task 12: bootstrap test exports `TEEUP_TEST_MISSING="brew gum jq"` | applied — without it the installer-URL assertion would be vacuous |
| 23 | Task 12: `answers_set` exports before the dry-run return; keepalive polls `kill -0` | applied — both correct; the export is load-bearing for `TEEUP_DAILY` |
| 24 | Task 12: `pkg_backend` in two subshells / `id` mock returns one value for every flag / core caps run twice | **defer** all three. Note the second is the reason `id -F` is untested, and the third is what makes C1 possible — the double run is safe by idempotency, but the *ordering* of the answers write against the wizard check is not (C1) |

Net: two items move to fix-before-merge territory — item 19 outright, and item 10
as a one-line hardening to ride along with the C1 fix.

---

## Recommendations

1. **Fix C1 first and add the test that would have caught it.** One bootstrap test
   with `DRY_RUN=false` under the mocked `$HOME` covers C1, M17's idempotency
   requirement, and the non-dry sudo/keepalive path in one go. Right now the
   entire non-dry-run bootstrap path has zero coverage, and that is where all
   three Critical/Important findings live.
2. **Make capability postconditions the success criterion, not exit codes.** I1
   and I2 are the same shape: a unit reports success because the last command it
   ran happened to return 0. `pkg_backend_prepare` should end with
   `pkg_backend_installed || return 1`; `xcode-clt install` should end with
   `xcode-select -p >/dev/null || exit 1`. Consider making this an explicit rule in
   the CONTRIBUTING capability section before phase 2 adds sixteen more units.
3. **Take I3 now.** The ruling routed it here, it is one line, and after phase 2
   ships the shell layer it becomes a confusing multi-checkout bug rather than a
   theoretical one.
4. **Tighten the `answers_set` key guard** (M2) while you are in `answers.sh` for
   C1 — a regex test plus a non-`grep` filter removes both the glob hole and the
   regex interpolation.
5. **Before the first real Mac run**, fix M3 so the closing instruction works:
   either print the absolute path, or have `teeup-runtime configure` append a PATH
   line and say so. It is the first thing the user will type.
6. **Add `machines/.gitkeep` and a CONTRIBUTING line** (M14). The per-machine
   override is the only escape hatch in the configuration model and currently
   nothing in the tree hints that it exists.
7. **Documentation is accurate apart from M3.** The CONTRIBUTING capability
   section matches the implemented contract, including the `provides=` rule and
   the "never call sudo" constraint (verified: `grep -rn sudo capabilities/`
   returns only a comment). One nit: it says "Never mutate outside `run_cmd`"
   immediately after listing `copy_config_once`/`append_once`, which mutate
   directly with their own `DRY_RUN` guards — worth a half-sentence so the next
   capability author does not wrap them in `run_cmd`.

---

## Assessment

**Ready to merge? No — with fixes, yes.**

The structure is right and the craft is good. The library boundaries hold, bash
3.2 and BSD constraints were respected throughout, dry-run is honest everywhere it
is exercised, and the tests assert behaviour rather than restating the source. The
cross-task seams the brief asked about — `pkg_backend` resolution, the
`TEEUP_TEST_MISSING` hook, `answers_set`'s dry-run export, `cap_run`'s env exports,
the `run_logged` stdin rule — are all consistent between producer and consumer,
which is not a given for a runtime built one subagent at a time. Commit history is
clean and the legacy freeze preserved `--follow`.

What blocks the merge is C1: on a real fresh Mac the bootstrap wizard does not
run, because step 2 creates the answers file that step 4 uses to decide whether
the wizard is needed. That is the central step of spec section 5 and the entry
point to the whole configuration model, and the defect is invisible to the suite
because every bootstrap test runs `--dry-run`, which is exactly the condition
under which the write does not happen. I1 and I2 are the same class — units
reporting success on the strength of the last command's exit code — and both fire
on a first real run rather than under mocks. I3 is the deferred Task 10 ruling
coming due.

All four fixes are small and local. Once they land, with one non-dry-run bootstrap
test to hold C1 down, this is a solid Phase 0/1 foundation and phase 2 can build
on it without rework.
