#!/usr/bin/env bash
# sandbox.sh - sourced first by tests/run.sh and tests/helper.sh.
#
# teeup_enter_sandbox <script> [args...]
# Re-runs <script> inside a throwaway shellenv home
# (https://github.com/systemhalted/shellenv), so no test can write into the
# real machine: shellenv points HOME, TMPDIR and every XDG_* directory at a
# sandbox that is deleted when the run ends. setup_test_env still gives each
# test its own home; this is the second wall, for the test or the
# hand-written experiment that forgets it. On 2026-09-28 a run that changed
# only HOME still replaced the real ~/.config/git/config through an exported
# XDG_CONFIG_HOME.
#
# Returns without doing anything when already inside shellenv (a suite that
# tests/run.sh started, or tests/bash32.sh) and on GitHub Actions, whose
# runners are thrown away after every job.
teeup_enter_sandbox() {
  [[ -n "${SHELLENV_ACTIVE:-}" ]] && return 0
  [[ "${GITHUB_ACTIONS:-}" == "true" ]] && return 0
  local root script
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  if [[ ! -f "$1" ]]; then
    echo "Run tests from a script (bash tests/<suite>.sh), not by sourcing tests/helper.sh in an interactive shell." >&2
    exit 2
  fi
  script="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
  shift
  if ! command -v shellenv >/dev/null 2>&1; then
    echo "teeup's tests run inside a shellenv sandbox so they cannot touch this machine, and shellenv is not on PATH. Install it: https://github.com/systemhalted/shellenv" >&2
    exit 2
  fi
  cd "$root" || exit 2
  # The first run builds bash 5.2 from source into $SHELLENV_HOME (about a
  # minute); later runs find it installed.
  shellenv install --require-checksum bash@5.2 >/dev/null || exit 2
  [[ -f .shellenv/teeup/metadata.json ]] ||
    shellenv create --name teeup --shell bash@5.2 >/dev/null || exit 2
  # TMPDIR goes back to /tmp because cleanup_test_env deletes only temp
  # directories there. --ephemeral gives every run its own home, so two runs
  # at once do not share one.
  exec shellenv exec teeup --strict-shell --ephemeral -- \
    env TMPDIR=/tmp bash "$root/tests/sandbox-run.sh" "$script" "$@"
}
