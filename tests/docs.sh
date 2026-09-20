#!/usr/bin/env bash
# Documentation that names a set of capabilities goes stale the moment one of
# them gains a remove script or a package, and nothing else notices: the
# README is not executable and no capability test reads it. These tests keep
# the few doc claims that enumerate the tree honest by deriving the same set
# from the capabilities themselves.
set -euo pipefail
source "$(dirname "$0")/helper.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"

# Every capability with no remove script and no packages or casks: the set
# `teeup remove` refuses outright, because there is nothing for it to undo.
nothing_to_remove() {
  local dir name packages casks
  for dir in "$REPO"/capabilities/*/; do
    name="${dir%/}"
    name="${name##*/}"
    [[ -f "$dir/capability" ]] || continue
    [[ -f "$dir/remove" ]] && continue
    packages="$(sed -n 's/^packages="\(.*\)"$/\1/p' "$dir/capability")"
    casks="$(sed -n 's/^casks="\(.*\)"$/\1/p' "$dir/capability")"
    [[ -n "$packages" || -n "$casks" ]] && continue
    printf '%s\n' "$name"
  done
}

test_readme_names_every_capability_remove_refuses() {
  local name missing="" bullet
  # The bullet that makes the claim, not the whole file: a capability named
  # elsewhere in the README must not satisfy this.
  bullet="$(awk '/^- \*\*`teeup remove/,/^- \*\*`?[A-Z]/' "$REPO/README.md")"
  [[ -n "$bullet" ]] || { echo "could not find the teeup remove bullet in README.md"; return 1; }
  for name in $(nothing_to_remove); do
    case "$bullet" in
      *"\`$name\`"*) ;;
      *) missing="${missing:+$missing }$name" ;;
    esac
  done
  if [[ -n "$missing" ]]; then
    echo "README's teeup remove bullet does not name: $missing"
    echo "(these ship no remove script and no packages or casks, so teeup remove refuses them)"
    return 1
  fi
  return 0
}

test_readme_remove_count_matches_the_tree() {
  local n bullet
  n="$(nothing_to_remove | wc -l | tr -d ' ')"
  bullet="$(awk '/^- \*\*`teeup remove/,/^- \*\*`?[A-Z]/' "$REPO/README.md")"
  case "$n" in
    7) printf '%s' "$bullet" | grep -q 'Seven capabilities' || { echo "the README says a different number than the seven in the tree"; return 1; } ;;
    *) echo "the set changed size (now $n): update the README bullet and this test's spelling"; return 1 ;;
  esac
  return 0
}

echo "docs"
run_test "README names every capability remove refuses" test_readme_names_every_capability_remove_refuses
run_test "README's remove count matches the tree" test_readme_remove_count_matches_the_tree
print_summary
