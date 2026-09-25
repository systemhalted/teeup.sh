# Review follow-ups

Findings from PR reviews that were not fixed on the PR that raised them.
Critical and high (Codex P0/P1) are fixed on the PR itself. Medium and low
(P2/P3) go into a follow-up PR opened right after it. Nitpicks are listed
here and done once the current phase of work is finished.

## Medium / low

| Raised on | Finding | Status |
| --- | --- | --- |
| PR #32 (Codex P2) | `git doctor` accepted an empty or unreadable `gpg.ssh.allowedSignersFile` as able to verify signatures | Fixed on `fix/doctor-followups` |
| PR #32 gpgsign fix (local Codex P2) | `commit.gpgsign` re-read file by file lost git's include order: a line after the last include was overridden by `local` | Fixed on `fix/doctor-followups` |
| PR #32 gpgsign fix (local Codex P2) | Only four spellings of true were accepted; a bare key or `2` read as off, and an invalid value passed silently | Fixed on `fix/doctor-followups` |
| PR #32 gpgsign fix (local Codex P2) | An unreadable `local` with teeup-generated saying true was reported as signing on | Fixed on `fix/doctor-followups` |
| Follow-up (local Codex P2) | The allowed-signers repair appended the default key, not the configured `user.signingkey` | Fixed on `fix/doctor-followups` |
| Follow-up (local Codex P2) | The allowed-signers repair commands left the path unquoted | Fixed on `fix/doctor-followups` |
| PR #33 (Codex P2) | A syntax error anywhere in the include graph was reported as a bad `commit.gpgsign` value | Fixed on `fix/doctor-followups-2` |
| PR #33 (Codex P2) | A `false` in a file that `local` includes was blamed on teeup-generated | Fixed on `fix/doctor-followups-2` |
| PR #33 (Codex P2) | The allowed-signers repair used the signing key from identity/generated/local, missing a top-level override | Fixed on `fix/doctor-followups-2` |
| PR #31 gate (Opus P2) | The AeroSpace migration gate read a missing CLI as no AeroSpace, though the app can be installed without it | Fixed on `fix/aerospace-gate-followups` |
| PR #31 gate (Opus P2) | The gate blocked `teeup update` where the refresh would write nothing (edited config, `~/.aerospace.toml`) | Fixed on `fix/aerospace-gate-followups` |
| PR #31 gate (Opus P3) | A leading zero in a version was compared as octal | Fixed on `fix/aerospace-gate-followups` |

## Nitpicks

- ~~`capabilities/git/doctor`: the unreachable "could not check user.signingkey" and "could not check gpg.format" branches.~~ Removed on `fix/doctor-followups-2`, with `_git_doctor_last_value`.
- `capabilities/git/doctor`: `gpg.ssh.allowedSignersFile` is still found by a per-file grep, which is not include-order or section aware; ask git (`--path --get`) like the other signing settings, and drop the now-dead `signers_unreadable` branch.
- `teeup update --dry-run` stops at the AeroSpace migration on a machine with an old AeroSpace, the same as a real run. Honest, but the preview could say what it would wait for instead of failing.
- `capabilities/git/doctor`: the pre-existing allowed-signers note (setting not configured) still interpolates unquoted paths into its instructions.
