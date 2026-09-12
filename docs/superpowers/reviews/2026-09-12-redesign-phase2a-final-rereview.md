# Phase 2a final-review fix wave — re-review

Reviewer: senior code reviewer (read-only, scoped). Diff reviewed:
`review-794019c..060e446.diff` (single commit, "Fix the final-review findings for
the shell and git group", 13 files, +194/-24). No suite re-run; one focused check
per named doubt, run directly against zsh 5.9 and gh 2.100.0 present on this host.

## Per-finding verdicts

**1. I1 — `EXTENDED_GLOB` breaks `HEAD^` (Important). ADDRESSED.**
`capabilities/zsh/default/rc:37,42` adds `setopt NO_NOMATCH` right after the
existing `setopt … EXTENDED_GLOB …` line, with a comment on why both options are
kept together. Verified independently with the host's zsh 5.9: `zsh -f` sourcing
of the shipped `rc` prints `HEAD^` unchanged. Also checked the specific interplay
the task flagged — the compinit dump-age qualifier `(#qN.mh-24)` — with a
standalone script: the `N` glob qualifier forces per-pattern nullglob regardless
of `NO_NOMATCH`, confirmed both for a missing file (0 matches, no error) and a
present, recently-touched one (1 match). No interaction problem. The new test
(`tests/capabilities/zsh.sh:126-138`, `test_rc_leaves_git_revision_syntax_alone`)
discards stderr; reproduced that choice directly — stdout is exactly `HEAD^` and
stderr carries only an unrelated `mise WARN … is not trusted` line from `mise
activate` in the same rc chain, not a masked failure. Test and rationale hold up.

**2. I2 — `teeup secret set` echoed the value (Important). ADDRESSED, with one new gap.**
`lib/ui.sh:22-33` adds `ui_secret` (gum `--password` / plain `read -rs` +
stderr-only prompt and trailing newline); `bin/teeup:119` calls it from
`cmd_secret set`. Confirmed `gum input --password` is a real, currently-shipped
flag (`gum input --help` on this host). Ran `printf 's3cret\n' | ui_secret
"Value" 2>err.log` — value comes back on stdout, stderr shows only the prompt,
never the secret.

New breakage found: `IFS= read -rs answer || answer=""` (`lib/ui.sh:29`)
silently discards a value that was piped **without a trailing newline**. Bash's
`read` populates the variable even when it hits EOF before a newline, but still
returns non-zero — and `|| answer=""` then overwrites the already-read value with
an empty string. Verified end-to-end: `printf 's3cret' | ./bin/teeup secret set
x` (no `\n`) fails with "Refusing to store an empty value for 'x'" even though
`s3cret` was on stdin. This is not a `set -e` crash (bash does not propagate
`errexit` into `$(...)` without `shopt -s inherit_errexit`, which is not set
here, so the "read under set -e" framing of the doubt doesn't apply) — it's a
silent-data-loss/false-empty bug. It's not a regression introduced by this diff
(the identical `read -r … || answer=""` pattern already exists, unfixed, in the
pre-existing `ui_input`), but `ui_secret` is new code that reproduces it in
exactly the path I2 was hardening, and no fixture in the suite pipes a value
without a trailing newline (all use `printf '...\n'` or `echo`), so it ships
untested. Fails safe (loud die, no leak, no mis-store) — not a security
regression, but worth a fast-follow (e.g. drop the `|| answer=""` and let the
`local` empty-string default stand, or check `[[ -z "$answer" ]]` instead of the
read's exit code).

**3. I3 — GitHub scope refresh + type-aware dedupe (Important). ADDRESSED, two narrow residual gaps.**
`capabilities/github/configure:7-17` (scope check/refresh) and `:34-62`
(`_github_key_uploaded`, per-type loop) match the fix report. Verified against
the real `gh` 2.100.0 installed here:
- `gh auth status` really prints a `Token scopes: 'a', 'b', …` line in the shape
  the substring check expects.
- `gh ssh-key list` really emits a trailing TYPE column
  (`authentication`/`signing`) as the last tab-separated field — confirmed by
  running it live. The dedupe helper's raw substring match (not field-split) is
  correct for spaces-in-titles (the doubt raised); it does not break there.

Two gaps found, neither a regression (the old code had no such logic at all)
and neither reopens the "permanently stuck" failure I3 targets in the mainline
single-host case:
- **Host scoping**: `gh auth status` is called without `-h github.com`, so on a
  machine also logged into a second host (e.g. a GHE instance) its output
  covers every host; the scope substring check (`configure:13`) scans the whole
  blob, so scopes present only on the *other* host could read as "present" for
  github.com. Not exercised by any fixture (all seed a single host).
- **Type-match specificity**: `_github_key_uploaded` (`configure:36-43`)
  matches `type` as a substring of the whole line rather than the actual last
  field, so a user-chosen key title containing the literal word "signing" or
  "authentication" could produce a false type match. teeup's own generated
  titles ("$host $identity", "... (signing)") don't trigger this, so the
  common path is fine; pre-existing/hand-titled keys are unproven.

**4. Minor 1 — shell rc files ending on a failing status. ADDRESSED, and extended correctly.**
A `true` line, with a one-line comment, was added as the last executable
statement in `capabilities/zsh/home/.zshrc:14-16`, `.zprofile:6-7`, and
`.zshenv:7-8` — covering the two "siblings" the review flagged as the same
shape, per the controller's "and siblings if applicable." Verified by reading
all three files: in each, everything after `true` is comment-only, so sourcing
now always exits 0 when the guarded file is absent. No new test was added for
this (not required by the controller's ruling for this item).

**5. Minor 5 — `teeup-env` variable-name sanitisation. ADDRESSED.**
`capabilities/secrets/default/functions.zsh:11-19`. Verified independently with
a standalone zsh script exercising the exact expression used
(`${(U)name}` → `${var//[^A-Za-z0-9_]/_}` → leading-digit prefix): `my.api-key`
→ `MY_API_KEY`, `1password` → `_1PASSWORD`, `openai_api_key` unchanged
(uppercased), matching the spec exactly. The shipped test
(`tests/capabilities/secrets.sh`, `test_teeup_env_sanitises_the_variable_name`)
exercises the same case through the real `teeup secret set`/`teeup-env` path.

**6. "Nothing else changed" claim. VERIFIED.**
The diff touches exactly the 13 files the fix report lists, nothing more. Both
adjusted test fixtures (`test_configure_skips_a_key_github_already_has`,
`test_configure_skips_the_login_when_already_signed_in` in
`tests/capabilities/github.sh`) only add type-tagged seed data and *add* new
assertions (`assert_not_contains … "auth refresh"`) — no existing assertion was
weakened or removed. The `tests/bootstrap.sh` gh mock was reshaped to the same
session/type-column shape for consistency, confirmed harmless since that suite
never reaches the signed-in branch.

## New breakage summary

- `lib/ui.sh:29` (`ui_secret`): a piped secret value with no trailing newline is
  silently dropped to empty (loud, safe failure — "Refusing to store an empty
  value" — not a leak), untested by the suite. Pre-existing pattern, newly
  relevant to the hardened path. Recommend a fast-follow.
- `capabilities/github/configure`: two narrow, untested parsing gaps (multi-host
  `Token scopes:` blob not scoped to github.com; type match is substring-based
  rather than field-based). Neither is a regression nor reopens the blocking
  scenario the fix targets.
- No other new breakage: `NO_NOMATCH`/`EXTENDED_GLOB`/compinit-qualifier
  interplay is clean; the zsh test's stderr-discard is justified, not
  error-masking; `gum --password` is a real flag; the three `true` additions are
  correctly the last executable statement in each file.

## Round verdict

**Pass, with two fast-follow items** (not blocking): tighten `ui_secret`'s
no-trailing-newline handling, and make the github scope/type checks
host-scoped and field-based rather than substring-based. All five required
findings (I1, I2, I3, Minor 1, Minor 5) are genuinely fixed and independently
verified against real zsh/gh behavior on this host, matching the fix report's
claims; the "nothing else changed / no weakened assertions" claim holds against
the diff.
