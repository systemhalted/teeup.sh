# Notes for coding agents

Read CONTRIBUTING.md first. These rules exist because an agent broke them.

## Never run teeup against a real home

Do not run `bin/teeup`, `./bootstrap`, a capability script
(`capabilities/*/install`, `configure`, `remove` ...) or a migration directly,
not even with `HOME=/tmp/...` in front. Many machines export
`XDG_CONFIG_HOME` and `XDG_STATE_HOME`, and teeup writes to them, so changing
`HOME` alone still writes into the real home. On 2026-09-28 an agent ran
`HOME=/tmp/test_home ./bin/teeup configure ssh` on the owner's Linux machine,
and it replaced their real `~/.config/git/config`, which broke every commit.

`bin/teeup` now refuses to change anything off macOS unless
`TEEUP_ALLOW_NON_MACOS=1` is set. Do not set that flag yourself.

## Every test run is sandboxed by shellenv

`tests/run.sh` and every suite (`bash tests/<suite>.sh`) re-run themselves
inside a throwaway [shellenv](https://github.com/systemhalted/shellenv) home
before any test starts: `HOME`, `TMPDIR` and every `XDG_*` directory point
into `.shellenv/teeup/`, and that home is deleted when the run ends. A run
that writes into that home instead of a test's `$TEST_HOME` fails and names
the files. On GitHub Actions the runner is thrown away anyway, so the
sandbox is skipped there.

- shellenv must be on `PATH`; the first run builds bash 5.2 from source
  (about a minute). If it is missing, stop and say so. Do not work around it.
- Never set `SHELLENV_ACTIVE` or `GITHUB_ACTIONS` yourself to skip the
  sandbox.
- `tests/bash32.sh` runs the same suites under macOS's bash 3.2.57, also
  inside shellenv.

To try a change, write a test. For a quick experiment, put a throwaway
script under `tests/` (and delete it afterwards). Sourcing `tests/helper.sh`
re-runs the script inside the sandbox first:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"   # re-runs this script inside shellenv
setup_test_env          # HOME and every XDG directory inside a temp dir
mock_macos_base         # uname, sw_vers, sudo ... mocked
# ... run "$TEEUP_PATH/bin/teeup" ... here ...
cleanup_test_env
```

## Other rules

- Never delete, move or un-Keychain anything under `~/.ssh`.
- Do not change git settings outside the repository you are working in: no
  `git config --global`, and no edits to `~/.config/git`. If a commit fails
  because of the user's git setup, stop and report it.
- Run the suites you changed and report their `Summary:` lines as printed.
  Register every new test with `run_test` before the single `print_summary`,
  and leave no `set -x` or scratch files behind.
- Run shell tests in their own process group, since a zsh test can signal
  its whole group: `perl -e 'setpgrp 0,0; exec @ARGV' bash tests/<suite>.sh`.
