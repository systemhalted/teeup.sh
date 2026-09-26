#!/usr/bin/env bash
# Documentation that names a set of capabilities goes stale the moment one of
# them gains a remove script or a package, and nothing else notices: the
# README is not executable and no capability test reads it. These tests keep
# the few doc claims that enumerate the tree honest by deriving the same set
# from the capabilities themselves.
set -euo pipefail
source "$(dirname "$0")/helper.sh"
# teeup_verbs lives in lib/dev.sh now, so this check and `teeup dev check`'s
# menu lint (R9.5) cannot silently disagree about what a real verb is.
source "$TEEUP_PATH/lib/dev.sh"

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

# The README also counts the capabilities that ship a remove script. That
# number moves whenever one gains or loses the file, and nothing else notices.
test_readme_remove_script_count_matches_the_tree() {
  local n bullet word
  n="$(find "$REPO/capabilities" -mindepth 2 -maxdepth 2 -name remove | wc -l | tr -d ' ')"
  bullet="$(awk '/^- \*\*`teeup remove/,/^- \*\*`?[A-Z]/' "$REPO/README.md")"
  case "$n" in
    5) word=five ;;
    6) word=six ;;
    7) word=seven ;;
    8) word=eight ;;
    9) word=nine ;;
    10) word=ten ;;
    11) word=eleven ;;
    *) echo "no spelling for $n remove scripts: update this test and the README"; return 1 ;;
  esac
  printf '%s' "$bullet" | grep -q "$word capabilities ship one today" || {
    echo "the README does not say $word capabilities ship a remove script, but $n do"
    return 1
  }
  return 0
}

# Every `teeup <verb>` the README shows in a command block has to be a verb
# bin/teeup actually accepts. The README is the page somebody reads before
# trusting a command that deletes things, and documenting a verb the CLI
# rejects with "Unknown verb" is the fastest way to lose that trust. Prose
# ("teeup ships", "teeup replaced") is not checked -- only fenced code blocks,
# where a line really is something to type.
#
# This exists because the migration section was written against `teeup doctor`
# while the doctor branch had not merged, and nothing would have caught it.
# teeup_verbs itself now lives in lib/dev.sh (sourced above).
test_readme_only_shows_verbs_that_exist() {
  local in_block=false line word verbs bad=""
  verbs=" $(teeup_verbs | tr '\n' ' ') "
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      '```'*) if [[ "$in_block" == "true" ]]; then in_block=false; else in_block=true; fi; continue ;;
    esac
    [[ "$in_block" == "true" ]] || continue
    # A command line starting with teeup, or one behind a DRY_RUN= prefix.
    case "$line" in
      teeup\ *|DRY_RUN=*\ teeup\ *) ;;
      *) continue ;;
    esac
    word="$(printf '%s\n' "$line" | sed -e 's/^DRY_RUN=[^ ]* //' -e 's/^teeup  *//' -e 's/[ #].*$//')"
    [[ -n "$word" ]] || continue
    case "$verbs" in
      *" $word "*) ;;
      *) bad="$bad $word" ;;
    esac
  done < "$TEEUP_PATH/README.md"
  if [[ -n "$bad" ]]; then
    echo "README shows commands bin/teeup does not accept:$bad"
    return 1
  fi
  return 0
}

# The README's menu-field table (R5.2's `label icon action when title`) has
# to name exactly the fields lib/menu.awk's valid_field() accepts. Derived
# from the parser rather than hard-coded here, so a field added to one and
# not the other fails this test instead of drifting silently (R10.4).
_menu_awk_fields() {
  local line inner
  line="$(grep -F 'function valid_field' "$REPO/lib/menu.awk")"
  [[ -n "$line" ]] || { echo "could not find valid_field() in lib/menu.awk" >&2; return 1; }
  inner="${line#*/^(}"
  inner="${inner%%)\$/*}"
  printf '%s\n' "$inner" | tr '|' '\n' | sort
}

_readme_menu_fields() {
  awk '/^\| Field \| Meaning \|$/,/^$/' "$REPO/README.md" \
    | grep -oE '^\| `[a-z]+`' | sed -e 's/^| `//' -e 's/`$//' | sort
}

test_readme_menu_field_table_matches_menu_awk() {
  local awk_fields readme_fields
  awk_fields="$(_menu_awk_fields)"
  readme_fields="$(_readme_menu_fields)"
  [[ -n "$readme_fields" ]] || { echo "could not find the menu field table in README.md"; return 1; }
  if [[ "$awk_fields" != "$readme_fields" ]]; then
    echo "README's menu field table ($(printf '%s' "$readme_fields" | tr '\n' ' ')) does not match lib/menu.awk's valid_field() list ($(printf '%s' "$awk_fields" | tr '\n' ' '))"
    return 1
  fi
  return 0
}

echo "docs"
run_test "README only shows verbs that exist" test_readme_only_shows_verbs_that_exist
run_test "README names every capability remove refuses" test_readme_names_every_capability_remove_refuses
run_test "README's remove count matches the tree" test_readme_remove_count_matches_the_tree
run_test "README's remove-script count matches the tree" test_readme_remove_script_count_matches_the_tree
run_test "README's menu field table matches menu.awk" test_readme_menu_field_table_matches_menu_awk
print_summary
