#!/usr/bin/env bash
# sandbox-run.sh <script> [args...] - runs inside the shellenv sandbox that
# tests/sandbox.sh opens: runs <script>, then fails the run if anything was
# written into the sandbox HOME itself instead of a test's $TEST_HOME.
# shellenv before 0.3 left XDG_STATE_HOME at the real ~/.local/state
# (shellenv#10). Whatever the version, no XDG directory may point outside
# the sandbox home.
for var in XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME; do
  case "${!var:-}" in
    "$HOME"/*) ;;
    *)
      case "$var" in
        XDG_CONFIG_HOME) export XDG_CONFIG_HOME="$HOME/.config" ;;
        XDG_CACHE_HOME) export XDG_CACHE_HOME="$HOME/.cache" ;;
        XDG_DATA_HOME) export XDG_DATA_HOME="$HOME/.local/share" ;;
        XDG_STATE_HOME) export XDG_STATE_HOME="$HOME/.local/state" ;;
      esac
      ;;
  esac
done

rc=0
bash "$@" || rc=$?
# Files and links only: shellenv itself creates the empty XDG directories.
strays="$(cd "$HOME" && find . -path ./tmp -prune -o \( -type f -o -type l \) -print 2>/dev/null | sed 's|^\./||')"
if [[ -n "$strays" ]]; then
  echo ""
  echo "A test wrote into HOME itself instead of \$TEST_HOME (outside the sandbox this would be your real home):"
  sed 's/^/  /' <<<"$strays"
  [[ $rc -ne 0 ]] || rc=1
fi
exit $rc
