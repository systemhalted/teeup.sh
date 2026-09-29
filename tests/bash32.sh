#!/usr/bin/env bash
# tests/bash32.sh [suite...] - the whole suite, or the named suites, under
# macOS's /bin/bash, bash 3.2.57, built by shellenv
# (https://github.com/systemhalted/shellenv).
# A first run builds it from source (about a minute) into $SHELLENV_HOME.
#
# shellenv exec also moves HOME into ./.shellenv/bash32/home. The tests make
# their own homes, so anything that lands there is a test that would have
# written into your real home; the run names it. TMPDIR stays /tmp, because
# cleanup_test_env only deletes temp directories there.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v shellenv >/dev/null 2>&1; then
  echo "tests/bash32.sh needs shellenv: https://github.com/systemhalted/shellenv" >&2
  exit 2
fi

shellenv install --require-checksum bash@3.2.57 >/dev/null
[[ -f .shellenv/bash32/metadata.json ]] ||
  shellenv create --name bash32 --shell bash@3.2.57 >/dev/null

sandbox=.shellenv/bash32/home
rm -rf "$sandbox"
mkdir -p "$sandbox"

rc=0
# TEEUP_TEST_BASH32 turns on the byte-for-byte %q checks in the emacs, neovim
# and wezterm suites; inside the env, `bash` is the pinned 3.2.57.
# With no arguments, the whole suite through tests/run.sh; otherwise each
# named suite in turn (run.sh itself takes no suite list).
shellenv exec bash32 --strict-shell -- env TMPDIR=/tmp bash -c '
  export TEEUP_TEST_BASH32="$(command -v bash)"
  [[ $# -gt 0 ]] || exec bash ./tests/run.sh
  rc=0
  for suite in "$@"; do bash "$suite" || rc=1; done
  exit $rc' bash "$@" || rc=$?

# Files and links only: shellenv itself creates the empty XDG directories.
strays="$(cd "$sandbox" && find . -path ./tmp -prune -o \( -type f -o -type l \) -print 2>/dev/null | sed 's|^\./||')"
if [[ -n "$strays" ]]; then
  echo ""
  echo "A test wrote into HOME itself instead of \$TEST_HOME (outside a sandbox this is your real home):"
  printf '  %s\n' $strays
  [[ $rc -ne 0 ]] || rc=1
fi
exit $rc
