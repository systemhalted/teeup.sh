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
| `fix/doctor-followups-2` (Opus P2) | git's first stderr line can be a warning printed before the fatal one, so a bad boolean was reported as an unreadable directory. Take the first `fatal:` line | Fixed on `fix/doctor-followups-3` |
| `fix/doctor-followups-2` (Opus P3) | The unreadable-path parse cuts at the first `'`, truncating a path with a quote in it | Fixed on `fix/doctor-followups-3` |
| `fix/doctor-followups-2` (Opus P3) | `chmod u+r <file>` is the wrong fix when a parent directory is unsearchable | Fixed on `fix/doctor-followups-3` |
| `fix/doctor-followups-2` (Opus P3) | "remove the commit.gpgsign line there" names `local` when the line is in a file `local` includes | Fixed on `fix/doctor-followups-3` |
| `fix/doctor-followups-2` (Opus P3) | A `~nosuchuser/` signing key makes `--path` exit 128 and reads as unset; a `key::` literal or GPG key ID fails the `-s` check although git accepts both (the latter predates this branch) | Fixed on `fix/doctor-followups-3` |
| `fix/doctor-followups-3` (local Codex P2) | Any `gpg.format` other than `ssh` is accepted as healthy, including a typo git rejects on every commit; validate against `openpgp`, `x509`, `ssh` | Fixed on `fix/doctor-followups-3` |
| `fix/doctor-followups-3` (local Codex P2) | A `key::` literal is reported healthy without checking it parses or that ssh-agent holds its private key | Fixed on `fix/doctor-followups-3` |
| `fix/doctor-followups-3` (local Codex P3) | With two nested unsearchable directories, the repair fixes only the outer one (the inner is not a `-d` behind it) | Fixed on `fix/doctor-followups-3` |
| PR #34 (Codex P2) | The AeroSpace refresh still ran (and validated against a running old AeroSpace) where nothing would be written | Fixed on `fix/aerospace-gate-followups-2` |
| PR #31 gate (Opus P2) | The AeroSpace migration gate read a missing CLI as no AeroSpace, though the app can be installed without it | Fixed on `fix/aerospace-gate-followups` |
| PR #31 gate (Opus P2) | The gate blocked `teeup update` where the refresh would write nothing (edited config, `~/.aerospace.toml`) | Fixed on `fix/aerospace-gate-followups` |
| PR #31 gate (Opus P3) | A leading zero in a version was compared as octal | Fixed on `fix/aerospace-gate-followups` |

Doctor follow-ups stop here (decision 2026-09-25): P2/P3 findings on `capabilities/git/doctor` from any further review round are logged below and done after phase 5a, not in another follow-up PR.

## Nitpicks

- ~~`capabilities/git/doctor`: the unreachable "could not check user.signingkey" and "could not check gpg.format" branches.~~ Removed on `fix/doctor-followups-2`, with `_git_doctor_last_value`.
- ~~`capabilities/git/doctor`: `gpg.ssh.allowedSignersFile` found by a per-file grep.~~ Asked of git on `fix/doctor-followups-3`.
- `teeup update --dry-run` stops at the AeroSpace migration on a machine with an old AeroSpace, the same as a real run. Honest, but the preview could say what it would wait for instead of failing.
- ~~`capabilities/git/doctor`: the allowed-signers note interpolated unquoted paths.~~ Quoted on `fix/doctor-followups-3`.
- ~~`capabilities/git/doctor` header comment said doctor reads the files.~~ Rewritten on `fix/doctor-followups-3`.
- `capabilities/theme/doctor`: the stale-render check uses `-nt`, which under bash 3.2 compares whole seconds, so a template edited in the same second as its render is not flagged. `stat -f %m` and `-c %Y` are whole seconds too; `find <tpl> -newer <render>` compares sub-second times, if it ever matters.
