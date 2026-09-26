# Review follow-ups

Findings from PR reviews that were not fixed on the PR that raised them.
Critical and high (Codex P0/P1) are fixed on the PR itself. Medium and low
(P2/P3) go into a follow-up PR opened right after it. Nitpicks are listed
here and done once the current phase of work is finished.

## Medium / low

| Raised on | Finding | Status |
| --- | --- | --- |
| AI wrappers (task reviews) | `mise where` runs twice per tool on every wrapper launch; iterate the missing list in the install loop | Open |
| AI wrappers (task reviews) | `mise_wrapper_remove` builds its path from raw `$2` before validating; untested remove branches and owner interpolation | Open |
| AI wrappers (task reviews) | The generated wrapper lost the comment explaining its mise global-config fallback | Open |
| AI wrappers (task reviews) | Bundle members are hardcoded in three places; read them from `cap_meta_get ai requires` | Open |
| AI wrappers (task reviews) | `teeup remove ai-claude` is refused while `ai` is installed; the README remove bullet does not say so | Open |
| AI wrappers (task reviews) | The skip notice and install failure reason do not reach the log file; the explicit `TEEUP_LOG_FILE` branch is untested | Open |
| AI wrappers (task reviews) | "All AI command-line tools" stays in the menu after installing all five leaves individually | Open |
| PR #43 uninstall plan (Codex P2) | The printed rerun command after a refusal drops the active flags (`--yes --packages --identity`); carry them through | Open (fold in when executing the plan) |
| PR #43 uninstall plan (Codex P2) | On MacPorts the kept-package ledger omits the emacs/wezterm ports that their remove scripts map casks to | Open (fold in when executing the plan) |
| Migrate reinstall fix (local Codex P2) | A `DRY_RUN=true teeup migrate legacy` does not preview the new reinstall step (owners are collected only for real moves); track owners separately and preview each configure | Open |
| PR #41 (Codex P2) | dev check lints the personal menu against shipped parent ids only; build and validate the merged cache so cross-file duplicate labels and action/children conflicts are caught | Open |
| PR #41 (Codex P2) | `lib/menu.awk` drops an empty row object (`"ghost": {}`), so an invalid menu passes `menu_check`; emit an id record or reject it | Open |
| PR #40 (Codex P2) | README "Terminals and file icons" says teeup installs the Nerd Font; on MacPorts `cask_install` skips the font cask and configure only records the family, so qualify the claim for MacPorts | Open |
| Phase 4b 5-10 final review (m5) | `config set TEEUP_THEME` stores an unvalidated name before redirecting; the printed `teeup theme set $value` is unquoted | Open |
| Phase 4b 5-10 final review (m6) | "Run: ./bootstrap" only works from the checkout; use `$TEEUP_PATH/bootstrap` | Open |
| Phase 4b 5-10 final review (m7) | A forced `TEEUP_MENU_PICKER=fzf|gum` with the tool missing, or a picker crash, reads as a cancel; the theme-set picker infers cancel from an empty `$1` | Open |
| Phase 4b 5-10 final review (m8) | dev check's menu-row lint accepts an empty verb (double space), `teeup reset`/`has` with no argument, and a second `&& teeup <x>` in one row | Open |
| Phase 4b 5-10 final review (m9) | `lib/menu.awk`: a trailing comma is accepted at the top level but refused in a row; a BOM is refused as "must be one JSON object" | Open |
| Phase 4b 5-10 final review (m10) | A submenu whose rows are all hidden (Launch on a fresh machine) is still listed, then says "Nothing left to show" | Open |
| Phase 4b 5-10 final review (m11) | `_dev_check_env_clean` unsets `TEEUP_TEST_JOBS`, the low-RAM knob; exempt it | Open |
| Phase 4b 5-10 final review (m12) | `dev new-capability` accepts `font` and `dev-env`, which `teeup install` treats as sub-switches | Open |
| Phase 4b 5-10 final review (m13) | README: the menu picker note omits `TEEUP_NO_GUM` turning off both pickers and the `TEEUP_MENU_PICKER` override; `config edit` "parses as shell" omits the shape check | Open |
| Real Mac, 2026-09-25 | `teeup doctor` prints every "Asking Homebrew whether X is installed" line; quiet them unless a check fails or verbose | Open |
| Real Mac, 2026-09-25 | eza icons show as `?` in Terminal.app (teeup never sets its font; U+F0000+ icons do not fall back). Documented in #40; code options: no `--icons` under `TERM_PROGRAM=Apple_Terminal`, or have `fonts` set Terminal.app's profile font | Open |
| `fix/phase5a-followups` (Opus P2) | The symlink-target resolution for `~/.gitconfig.local` falls back to `/<name>` when its directory cannot be entered; join the raw `readlink` to `$HOME` instead | Open (after phase 5a) |
| `fix/phase5a-followups` (Opus P3) | The symlink target is resolved one level only; a chain names an intermediate link; loop `readlink` | Open (after phase 5a) |
| `fix/phase5a-followups` (Opus P3) | The `-z` output temp file has no trap, so an interrupt leaves it behind | Open (after phase 5a) |
| Phase 5a task 7 (Opus P2) | `git doctor` matches `~/.gitconfig.local` by literal origin text; a relative include or a C-quoted non-ASCII home reads as "nothing includes it". Use `--show-origin -z` and compare resolved paths | Fixed on `fix/phase5a-followups` |
| Phase 5a task 7 (Opus P2) | `git config -f ~/.gitconfig.local` exiting 128 (a parse error) reads as "no leftover [user] block" | Fixed on `fix/phase5a-followups` |
| Phase 5a task 7 (Opus P2) | A failing `chezmoi source-path` reads as "configured here but has no source directory"; report could-not-check | Fixed on `fix/phase5a-followups` |
| Phase 5a task 7 (Opus P3) | `--remove-section user` leaves `[user "x"]` subsections, and writes through a symlinked `~/.gitconfig.local`; an unreadable included file should fail, not be unknown; the rc>1 "fix" only diagnoses; a git doctor comment sits away from the checks it describes | Fixed on `fix/phase5a-followups` |
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
- `tests/run.sh`: nothing stops a test writing into the checkout (two package-manager tests wrote `machines/testmac.conf` there, racing every suite that loads it). Snapshot `machines/` before the run and fail when it changed.
- Phase 4b 5-10 (task reviews): `_menu_check_body` reads a label twice; `cmd_config get` repeats the machine-file lookup a third time (share `machine_file`); the `cmd_menu` trap rationale comment is written twice; `lib/dev.sh` render-failure cleanup is duplicated for the test file; the new-capability probe copies with `cp -Rp` rather than `git ls-files`; a dry-run chmod preview names files a dry run never created; `install.dev-env.*` menu rows have no `when` guard; `dev check` refuses DRY_RUN with exit 1 rather than 2; `config edit`'s quoted-value pattern was verified on glibc only.
- AI wrappers: no test of two captured `run_logged` calls in one shell; nested interactive note printed into a captured stream; new leaf suites are mode 644 while others are 755; a spaced-HOME wrapper test was dropped; the registry mapping comment (aqua backends) was lost; CONTRIBUTING's "-C /" claim is not tree-wide.
- `teeup config edit` prefers `$VISUAL` over `$EDITOR` (git's order), and the zsh layer exports `VISUAL="emacsclient -t"`, so `EDITOR=nano teeup config edit` still opens Emacs (real Mac, 2026-09-26). Print which editor it opens and which variable chose it; mention `VISUAL=` in the usage text.
- Emacs daemon (real Mac VM, 2026-09-26): `teeup configure emacs` says "already loaded" after a flavor change and leaves the old daemon running; it should kickstart the agent itself when it moved a config aside or cloned a new flavor. The plist has no StandardOutPath/StandardErrorPath, so a hung daemon leaves nothing to read.
- WezTerm in a macOS VM fails with "failed to create NSOpenGLPixelFormat"; `front_end = "WebGpu"` in local.lua fixes it. Document it, or detect a VM (`sysctl -n kern.hv_vmm_present`) and default to WebGpu there.
