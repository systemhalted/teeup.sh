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

To try a change, write a test, or use the test harness in a throwaway script:

```bash
source tests/helper.sh
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
