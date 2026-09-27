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
SKILL="$REPO/share/agents/skills/teeup/SKILL.md"

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

test_readme_documents_ai_leaves_progress_and_lazy_log() {
  local readme
  readme="$(cat "$REPO/README.md")"
  local leaf
  for leaf in ai-claude ai-codex ai-gemini ai-copilot ai-opencode; do
    assert_contains "$readme" "\`$leaf\`" "README must name $leaf" || return 1
  done
  assert_contains "$readme" 'Installing Claude Code through mise (first run, can take a minute)...' || return 1
  assert_contains "$readme" '$TEEUP_STATE_DIR/logs/lazy.log' || return 1
  assert_contains "$readme" '`teeup install ai` installs all five' || return 1
}

test_menu_offers_each_ai_leaf_and_the_bundle() {
  local menu
  menu="$(cat "$REPO/share/teeup/menu.json")"
  local target
  for target in ai-claude ai-codex ai-gemini ai-copilot ai-opencode ai; do
    # The trailing quote makes this an exact action value: without it, "ai"
    # is a substring of "ai-claude" and the bundle row could be deleted
    # without failing this test.
    assert_contains "$menu" "teeup install $target\"" "menu must offer $target" || return 1
  done
}

# The manual (docs/manual, an mdBook) is the longest document teeup ships,
# so it gets the same guard as the README: every `teeup <verb>` it shows as
# code must be a verb bin/teeup accepts. Code is an inline `...` span or a
# line of a fenced block; prose ("teeup installs") is not checked.
# _manual_code_verbs <src dir> -> "file: verb" for every code-formatted
# teeup command, one per line.
_manual_code_verbs() {
  local dir="$1" f
  for f in "$dir"/*.md; do
    [[ -f "$f" ]] || continue
    awk -v file="${f##*/}" '
      function verb(text,   w) {
        sub(/^[[:space:]]+/, "", text)
        sub(/^DRY_RUN=[^ ]* +/, "", text)
        if (text !~ /^teeup +[^ ]/) return
        sub(/^teeup +/, "", text)
        w = text
        sub(/[^a-z_-].*$/, "", w)
        if (w != "") print file ": " w
      }
      /^```/ { fence = !fence; next }
      fence { verb($0); next }
      {
        line = $0
        while (match(line, /`[^`]+`/)) {
          verb(substr(line, RSTART + 1, RLENGTH - 2))
          line = substr(line, RSTART + RLENGTH)
        }
      }
    ' "$f"
  done
}

# _manual_bad_verbs <src dir> -> the "file: verb" lines whose verb bin/teeup
# does not accept.
_manual_bad_verbs() {
  local verbs line
  verbs=" $(teeup_verbs | tr '\n' ' ') "
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$verbs" in
      *" ${line##*: } "*) ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < <(_manual_code_verbs "$1")
}

# _manual_summary_problems <src dir> -> one line per SUMMARY.md link to a
# missing file, and per .md page SUMMARY.md does not link. mdBook quietly
# creates an empty page for a missing link, and never builds a page nobody
# links, so either mistake publishes without a warning.
_manual_summary_problems() {
  local dir="$1" link f name
  [[ -f "$dir/SUMMARY.md" ]] || { echo "no SUMMARY.md in $dir"; return 0; }
  while IFS= read -r link; do
    [[ -n "$link" ]] || continue
    [[ -f "$dir/$link" ]] || echo "SUMMARY.md links to a missing file: $link"
  done < <(grep -oE '\]\([^)]+\.md\)' "$dir/SUMMARY.md" | sed -e 's/^](//' -e 's/)$//')
  for f in "$dir"/*.md; do
    [[ -f "$f" ]] || continue
    name="${f##*/}"
    [[ "$name" == "SUMMARY.md" ]] && continue
    grep -qF "]($name)" "$dir/SUMMARY.md" || echo "SUMMARY.md does not list: $name"
  done
  return 0
}

# The manual's first pages were converted from Org, where =code= is inline
# code, and a conversion bug left the markers behind: `c=, =cls` for two
# spans, a bare =word= for one that was never converted. Fenced blocks are
# skipped (a shell line may say KEY=value); inline code spans are checked for
# the "closing marker, gap, opening marker" shape, and the prose around them
# for a whole =word= marker.
# _manual_org_markers <src dir> -> "file:line: text" for every suspect line.
_manual_org_markers() {
  local dir="$1" f
  for f in "$dir"/*.md; do
    [[ -f "$f" ]] || continue
    awk -v file="${f##*/}" '
      /^```/ { fence = !fence; next }
      fence { next }
      {
        line = $0; bad = 0; rest = line
        while (match(rest, /`[^`]+`/)) {
          span = substr(rest, RSTART + 1, RLENGTH - 2)
          if (span ~ /[^ =]=[,.;:]? .* =[^ =]/ || span ~ /[^ =]=(, | and | or )=[^ =]/) bad = 1
          rest = substr(rest, RSTART + RLENGTH)
        }
        prose = line
        gsub(/`[^`]+`/, "", prose)
        if (prose ~ /(^|[ (|"[{])=[^= ]([^=]*[^= ])?=($|[ .,;:)|!?"}]|\])/) bad = 1
        if (bad) print file ":" NR ": " line
      }
    ' "$f"
  done
}

test_manual_has_no_org_code_markers() {
  local found
  found="$(_manual_org_markers "$REPO/docs/manual/src")"
  if [[ -n "$found" ]]; then
    echo "Org =code= markers left in the manual (use Markdown backticks):"
    printf '%s\n' "$found"
    return 1
  fi
  return 0
}

test_manual_org_marker_check_catches_leftovers() {
  local dir found
  dir="$(mktemp -d)"
  # shellcheck disable=SC2016  # the backticks are Markdown, not a substitution
  printf '%s\n' \
    '| `c=, =cls` | clear |' \
    'teeup runs mise from `/= for this, so a =mise.toml` here.' \
    'Run =teeup status= to see it.' \
    'Is it =teeup status=? Run "=teeup status=!" [=teeup doctor=] {=teeup list=}' \
    'Set `DRY_RUN=true` and `--icons=auto`, or `config = { a = 1 }`.' \
    '```sh' 'DRY_RUN=true teeup update' 'x =y= z' '```' > "$dir/page.md"
  found="$(_manual_org_markers "$dir")"
  rm -rf "$dir"
  assert_contains "$found" "page.md:1:" || return 1
  assert_contains "$found" "page.md:2:" || return 1
  assert_contains "$found" "page.md:3:" || return 1
  assert_contains "$found" "page.md:4:" || return 1
  assert_not_contains "$found" "page.md:5:" || return 1
  assert_not_contains "$found" "page.md:7:" || return 1
  assert_not_contains "$found" "page.md:8:" || return 1
}

test_manual_only_shows_verbs_that_exist() {
  local bad
  bad="$(_manual_bad_verbs "$REPO/docs/manual/src")"
  if [[ -n "$bad" ]]; then
    echo "The manual shows teeup commands bin/teeup does not accept:"
    printf '%s\n' "$bad"
    return 1
  fi
  [[ -n "$(_manual_code_verbs "$REPO/docs/manual/src")" ]] || { echo "found no teeup commands in the manual at all; the scan is broken"; return 1; }
  return 0
}

test_manual_verb_check_catches_an_unknown_verb() {
  local dir bad
  dir="$(mktemp -d)"
  # shellcheck disable=SC2016  # the backticks are Markdown, not a substitution
  printf '%s\n' 'Run `teeup instal git`, then:' '```sh' 'DRY_RUN=true teeup frobnicate' 'teeup status' '```' 'Prose: teeup installs things.' > "$dir/page.md"
  bad="$(_manual_bad_verbs "$dir")"
  rm -rf "$dir"
  assert_contains "$bad" "page.md: instal" || return 1
  assert_contains "$bad" "page.md: frobnicate" || return 1
  assert_not_contains "$bad" "status" || return 1
  assert_not_contains "$bad" "installs" || return 1
}

test_manual_summary_matches_the_pages() {
  local problems
  problems="$(_manual_summary_problems "$REPO/docs/manual/src")"
  if [[ -n "$problems" ]]; then
    printf '%s\n' "$problems"
    return 1
  fi
  return 0
}

test_manual_summary_check_catches_both_mistakes() {
  local dir problems
  dir="$(mktemp -d)"
  printf '%s\n' '# Part 1: The Basics' '' '- [Here](here.md)' '- [Gone](gone.md)' > "$dir/SUMMARY.md"
  : > "$dir/here.md"
  : > "$dir/stray.md"
  problems="$(_manual_summary_problems "$dir")"
  rm -rf "$dir"
  assert_contains "$problems" "missing file: gone.md" || return 1
  assert_contains "$problems" "does not list: stray.md" || return 1
  assert_not_contains "$problems" "here.md" || return 1
}

# The agent skill (share/agents/skills/teeup/SKILL.md) is the mental model an
# agent CLI loads before it touches the checkout. These four checks read it
# the same way the manual and README checks above read their documents:
# derive a claim from the runtime and compare, rather than trusting prose.

test_the_skill_has_frontmatter_a_name_and_a_description() {
  assert_file_exists "$SKILL" "the agent skill ships in the checkout" || return 1
  local first
  first="$(head -1 "$SKILL")"
  assert_equals "---" "$first" "frontmatter opens on line 1 or the whole file is content" || return 1
  local front
  front="$(awk 'NR>1 && /^---$/{exit} NR>1{print}' "$SKILL")"
  assert_contains "$front" "name: teeup" "the skill names itself" || return 1
  assert_contains "$front" "description:" "the skill says when to load it" || return 1
}

test_the_skill_names_only_paths_that_exist() {
  # Backticked paths that start with one of the checkout's top-level
  # directories. A path containing < is a placeholder (capabilities/<name>/)
  # and never matches the character class below, so it is skipped along with
  # anything else the class does not spell out.
  local missing="" p
  for p in $(grep -oE '`(bin|lib|capabilities|share|themes|migrations|tests|docs|machines)/[A-Za-z0-9._/-]+`' "$SKILL" |
             tr -d '`' | sort -u); do
    if [[ ! -e "$REPO/$p" ]]; then
      missing="$missing $p"
    fi
  done
  assert_equals "" "$missing" "every path the skill names exists in the checkout" || return 1
}

# skill_verbs: every verb the skill names, from the two places it names one --
# a backticked `teeup <verb>` span, and the summary block under "## The verbs".
# Bare prose is not scanned, because "a teeup checkout" would otherwise read as
# a verb called "checkout". Compared against teeup_verbs (lib/dev.sh), the
# dispatcher's own list, rather than shelling out to `./bin/teeup help`: that
# would source the real answers file and machine config (see the file header),
# and teeup_verbs already reads the same source `teeup dev check`'s menu lint
# does, so the two checks cannot silently disagree about what a real verb is.
skill_verbs() {
  {
    grep -oE '`teeup [a-z][a-z-]*' "$SKILL" | sed 's/^`teeup //'
    awk '/^## The verbs$/{f=1;next} /^## /{f=0} f' "$SKILL" |
      grep -oE 'teeup [a-z][a-z-]*' | sed 's/^teeup //'
  } | sort -u
}

test_the_skill_names_only_verbs_teeup_has() {
  local verbs named unknown="" v
  verbs=" $(teeup_verbs | tr '\n' ' ') "
  named="$(skill_verbs)"
  assert_contains "$named" "install" "the verb summary was found at all" || return 1
  for v in $named; do
    case "$verbs" in
      *" $v "*) ;;
      *) unknown="$unknown $v" ;;
    esac
  done
  assert_equals "" "$unknown" "every verb the skill names is a verb teeup has" || return 1
}

test_the_skill_marks_the_generated_and_borrowed_trees_read_only() {
  local body
  body="$(cat "$SKILL")"
  # No leading ~ in the needle: shellcheck's SC2088 fires on a quoted word that
  # starts with one, and the path is what matters, not the tilde.
  assert_contains "$body" '.local/state/teeup/' "the generated tree is named as read-only" || return 1
  assert_contains "$body" 'docs/superpowers/' "the decision record is named as read-only" || return 1
  assert_contains "$body" '.superpowers/' "another agent's workspace is named as read-only" || return 1
  assert_contains "$body" 'Never edit these' "the read-only rules have a heading of their own" || return 1
}

echo "docs"
run_test "README only shows verbs that exist" test_readme_only_shows_verbs_that_exist
run_test "README names every capability remove refuses" test_readme_names_every_capability_remove_refuses
run_test "README's remove count matches the tree" test_readme_remove_count_matches_the_tree
run_test "README's remove-script count matches the tree" test_readme_remove_script_count_matches_the_tree
run_test "README's menu field table matches menu.awk" test_readme_menu_field_table_matches_menu_awk
run_test "README documents AI leaves, progress and lazy log" test_readme_documents_ai_leaves_progress_and_lazy_log
run_test "menu offers each AI leaf and the bundle" test_menu_offers_each_ai_leaf_and_the_bundle
run_test "manual only shows verbs that exist" test_manual_only_shows_verbs_that_exist
run_test "manual verb check catches an unknown verb" test_manual_verb_check_catches_an_unknown_verb
run_test "manual SUMMARY.md matches the pages" test_manual_summary_matches_the_pages
run_test "manual SUMMARY.md check catches both mistakes" test_manual_summary_check_catches_both_mistakes
run_test "manual has no Org code markers" test_manual_has_no_org_code_markers
run_test "manual Org marker check catches leftovers" test_manual_org_marker_check_catches_leftovers
run_test "the skill has frontmatter, a name and a description" test_the_skill_has_frontmatter_a_name_and_a_description
run_test "the skill names only paths that exist" test_the_skill_names_only_paths_that_exist
run_test "the skill names only verbs teeup has" test_the_skill_names_only_verbs_teeup_has
run_test "the skill marks the generated and borrowed trees read-only" test_the_skill_marks_the_generated_and_borrowed_trees_read_only
print_summary
