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

test_manual_names_every_capability_remove_refuses() {
  local name missing="" bullet
  # The bullet that makes the claim, not the whole file: a capability named
  # elsewhere in the manual must not satisfy this.
  bullet="$(awk '/^- \*\*`teeup remove/,/^- \*\*`?[A-Z]/' "$REPO/docs/manual/src/the-teeup-command.md")"
  [[ -n "$bullet" ]] || { echo "could not find the teeup remove bullet in the-teeup-command.md"; return 1; }
  for name in $(nothing_to_remove); do
    case "$bullet" in
      *"\`$name\`"*) ;;
      *) missing="${missing:+$missing }$name" ;;
    esac
  done
  if [[ -n "$missing" ]]; then
    echo "manual's teeup remove bullet does not name: $missing"
    echo "(these ship no remove script and no packages or casks, so teeup remove refuses them)"
    return 1
  fi
  return 0
}

test_manual_remove_count_matches_the_tree() {
  local n bullet
  n="$(nothing_to_remove | wc -l | tr -d ' ')"
  bullet="$(awk '/^- \*\*`teeup remove/,/^- \*\*`?[A-Z]/' "$REPO/docs/manual/src/the-teeup-command.md")"
  case "$n" in
    7) printf '%s' "$bullet" | grep -q 'Seven capabilities' || { echo "the manual says a different number than the seven in the tree"; return 1; } ;;
    *) echo "the set changed size (now $n): update the manual bullet and this test's spelling"; return 1 ;;
  esac
  return 0
}

# The manual also counts the capabilities that ship a remove script. That
# number moves whenever one gains or loses the file, and nothing else notices.
test_manual_remove_script_count_matches_the_tree() {
  local n bullet word
  n="$(find "$REPO/capabilities" -mindepth 2 -maxdepth 2 -name remove | wc -l | tr -d ' ')"
  bullet="$(awk '/^- \*\*`teeup remove/,/^- \*\*`?[A-Z]/' "$REPO/docs/manual/src/the-teeup-command.md")"
  case "$n" in
    5) word=five ;;
    6) word=six ;;
    7) word=seven ;;
    8) word=eight ;;
    9) word=nine ;;
    10) word=ten ;;
    11) word=eleven ;;
    12) word=twelve ;;
    13) word=thirteen ;;
    *) echo "no spelling for $n remove scripts: update this test and the manual"; return 1 ;;
  esac
  printf '%s' "$bullet" | grep -q "$word capabilities ship one today" || {
    echo "the manual does not say $word capabilities ship a remove script, but $n do"
    return 1
  }
  return 0
}

# Every `teeup <verb>` the README shows, in a code block or a backtick span,
# has to be a verb bin/teeup accepts: the README is the first page anybody
# reads, and a command it shows that the CLI rejects loses their trust.
test_readme_only_shows_verbs_that_exist() {
  local verbs word bad=""
  verbs=" $(teeup_verbs | tr '\n' ' ') "
  for word in $( { grep -oE '`(DRY_RUN=[^ ]+ )?teeup [a-z][a-z-]*' "$REPO/README.md"
                   awk '/^```/ { f = !f; next } f' "$REPO/README.md" | grep -oE '^(DRY_RUN=[^ ]+ )?teeup [a-z][a-z-]*'
                 } | sed -E 's/.*teeup //' | sort -u); do
    case "$verbs" in
      *" $word "*) ;;
      *) bad="$bad $word" ;;
    esac
  done
  if [[ -n "$bad" ]]; then
    echo "README shows commands bin/teeup does not accept:$bad"
    return 1
  fi
  return 0
}

# The manual's menu-field table (R5.2's `label icon action when title`) has
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

_manual_menu_fields() {
  awk '/^\| Field \| Meaning \|$/,/^$/' "$REPO/docs/manual/src/hooks-and-extending.md" \
    | grep -oE '^\| `[a-z]+`' | sed -e 's/^| `//' -e 's/`$//' | sort
}

test_manual_menu_field_table_matches_menu_awk() {
  local awk_fields manual_fields
  awk_fields="$(_menu_awk_fields)"
  manual_fields="$(_manual_menu_fields)"
  [[ -n "$manual_fields" ]] || { echo "could not find the menu field table in hooks-and-extending.md"; return 1; }
  if [[ "$awk_fields" != "$manual_fields" ]]; then
    echo "manual's menu field table ($(printf '%s' "$manual_fields" | tr '\n' ' ')) does not match lib/menu.awk's valid_field() list ($(printf '%s' "$awk_fields" | tr '\n' ' '))"
    return 1
  fi
  return 0
}

test_manual_documents_ai_leaves_progress_and_lazy_log() {
  local manual
  manual="$(cat "$REPO/docs/manual/src/ai-tools.md")"
  local leaf
  for leaf in ai-claude ai-codex ai-gemini ai-copilot ai-opencode; do
    assert_contains "$manual" "\`$leaf\`" "manual must name $leaf" || return 1
  done
  assert_contains "$manual" 'Installing Claude Code through mise (first run, can take a minute)...' || return 1
  assert_contains "$manual" '`~/.local/state/teeup/logs/lazy.log`' || return 1
  assert_contains "$manual" '`teeup install ai` installs all five' || return 1
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


PLAIN_LANGUAGE_BLOCKLIST="seamless|effortless|powerful|beautiful|elegant|delightful|blazing|magic|simply|just|easily|basically|essentially|out of the box|batteries included|under the hood|in order to"

_manual_plain_language_violations() {
  local dir="$1" f
  for f in "$dir"/*.md; do
    [[ -f "$f" ]] || continue
    awk -v file="${f##*/}" -v blocklist="$PLAIN_LANGUAGE_BLOCKLIST" '
      BEGIN {
        split(tolower(blocklist), words, "|")
      }
      /^```/ { fence = !fence; next }
      fence { next }
      {
        prose = $0
        gsub(/`[^`]+`/, "", prose)
        lower_prose = tolower(prose)
        bad = 0
        for (i in words) {
          regex = "(^|[^a-z])" words[i] "($|[^a-z])"
          if (lower_prose ~ regex) {
            bad = 1
            break
          }
        }
        if (bad) print file ":" NR ": " $0
      }
    ' "$f"
  done
}

test_manual_is_written_in_plain_language() {
  local found
  found="$(_manual_plain_language_violations "$REPO/docs/manual/src")"
  if [[ -n "$found" ]]; then
    echo "Plain language violations found in the manual:"
    printf '%s
' "$found"
    return 1
  fi
  return 0
}

test_manual_plain_language_check_catches_violations() {
  local dir found
  dir="$(mktemp -d)"
  printf '%s
' \
    'This is basically a test.' \
    'It is `powerful` but not really.' \
    '```' \
    'just an effortless script' \
    '```' \
    'Batteries included!' > "$dir/page.md"
  found="$(_manual_plain_language_violations "$dir")"
  rm -rf "$dir"
  assert_contains "$found" "page.md:1:" || return 1
  assert_not_contains "$found" "page.md:2:" || return 1
  assert_not_contains "$found" "page.md:4:" || return 1
  assert_contains "$found" "page.md:6:" || return 1
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

PARITY="$REPO/docs/legacy-parity.md"

# parity_rows: the table rows between the markers, each one
# "| `<module>` | <capability cell> | <prose> |".
parity_rows() {
  sed -n '/<!-- parity-map -->/,/<!-- \/parity-map -->/p' "$PARITY" | grep '^| `'
}

test_the_parity_checklist_has_a_row_for_every_legacy_module() {
  assert_file_exists "$PARITY" "the parity checklist is in docs/" || return 1
  # The verbatim module list from `legacy/teeup.sh --list-modules`, frozen here
  # because the command that produced it is deleted in a later task.
  local missing="" m rows
  # The rows are captured once. `something | grep -q` would be a race under
  # `set -o pipefail`: grep exits on the first match, the upstream command gets
  # SIGPIPE, and the pipeline reports a failure that depends on the pipe buffer.
  rows="$(parity_rows)"
  for m in homebrew shell zsh ohmyzsh bash cli python java ruby rust emacs docker apps; do
    if ! grep -qF "| \`$m\` |" <<<"$rows"; then
      missing="$missing $m"
    fi
  done
  assert_equals "" "$missing" "every legacy module has a row" || return 1
  assert_equals "13" "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" "thirteen rows, one per module" || return 1
}

test_the_parity_checklist_names_only_capabilities_that_exist() {
  local bad="" row cell trimmed leftover name
  while IFS= read -r row; do
    # The second cell: everything between the first and second "|" after the
    # module name. It has to be exactly the word dropped, or one or more
    # backticked capability names and nothing else -- an unquoted word left
    # over once every `name` span is stripped out is a typo that lost its
    # backticks, and grep -oE alone would silently skip right over it.
    cell="$(printf '%s' "$row" | awk -F'|' '{print $3}')"
    trimmed="$(printf '%s' "$cell" | tr -d ' ')"
    if [[ -z "$trimmed" ]]; then
      bad="$bad empty-cell"
      continue
    fi
    if [[ "$trimmed" == "dropped" ]]; then
      continue
    fi
    leftover="$trimmed"
    for name in $(printf '%s' "$trimmed" | grep -oE '`[a-z0-9][a-z0-9.-]*`' | tr -d '`'); do
      if [[ ! -d "$REPO/capabilities/$name" ]]; then
        bad="$bad $name"
      fi
      leftover="${leftover//\`$name\`/}"
    done
    if [[ -n "$leftover" ]]; then
      bad="$bad unquoted:$leftover"
    fi
  done <<PARITY_ROWS
$(parity_rows)
PARITY_ROWS
  assert_equals "" "$bad" "every replacement cell is dropped, or backticked capability names that all exist" || return 1
}

# Four files may still say "legacy/". In three of them it is a historical
# fact rather than a path somebody could follow -- the changelog, the parity
# checklist, and the design record under docs/superpowers -- and the fourth
# is this file, which cannot search for the string without containing it.
# Anywhere else it is a broken reference to a tree that no longer exists.
test_nothing_tracked_points_at_the_deleted_legacy_tree() {
  if [[ -d "$REPO/legacy" ]]; then
    echo "legacy/ is still in the checkout"
    return 1
  fi
  local hits=""
  # -e, not -d: in a linked git worktree ".git" is a file pointing at the main
  # repository, so -d would skip the check there and the suite would pass
  # without ever looking.
  if command -v git >/dev/null 2>&1 && [[ -e "$REPO/.git" ]]; then
    # Tracked files only: an untracked scratch note in somebody's working
    # tree is theirs, and failing their suite over it would be wrong.
    hits="$(cd "$REPO" && git ls-files -z | xargs -0 grep -lF 'legacy/' 2>/dev/null |
      grep -v '^CHANGELOG\.md$' |
      grep -v '^docs/superpowers/' |
      grep -v '^docs/legacy-parity\.md$' |
      grep -v '^tests/docs\.sh$' || true)"
  else
    # A tarball rather than a checkout: fall back to the filesystem.
    hits="$(cd "$REPO" && grep -rlF 'legacy/' \
      --exclude-dir=.git --exclude-dir=superpowers \
      --exclude=CHANGELOG.md --exclude=legacy-parity.md --exclude=docs.sh \
      . 2>/dev/null || true)"
  fi
  assert_equals "" "$hits" "no tracked file points at legacy/" || return 1
}

echo "docs"
run_test "README only shows verbs that exist" test_readme_only_shows_verbs_that_exist
run_test "manual names every capability remove refuses" test_manual_names_every_capability_remove_refuses
run_test "manual's remove count matches the tree" test_manual_remove_count_matches_the_tree
run_test "manual's remove-script count matches the tree" test_manual_remove_script_count_matches_the_tree
run_test "manual's menu field table matches menu.awk" test_manual_menu_field_table_matches_menu_awk
run_test "manual documents AI leaves, progress and lazy log" test_manual_documents_ai_leaves_progress_and_lazy_log
run_test "menu offers each AI leaf and the bundle" test_menu_offers_each_ai_leaf_and_the_bundle
run_test "manual only shows verbs that exist" test_manual_only_shows_verbs_that_exist
run_test "manual verb check catches an unknown verb" test_manual_verb_check_catches_an_unknown_verb
run_test "manual SUMMARY.md matches the pages" test_manual_summary_matches_the_pages
run_test "manual SUMMARY.md check catches both mistakes" test_manual_summary_check_catches_both_mistakes
run_test "manual has no Org code markers" test_manual_has_no_org_code_markers
run_test "manual Org marker check catches leftovers" test_manual_org_marker_check_catches_leftovers
run_test "manual is written in plain language" test_manual_is_written_in_plain_language
run_test "manual plain language check catches violations" test_manual_plain_language_check_catches_violations
run_test "the skill has frontmatter, a name and a description" test_the_skill_has_frontmatter_a_name_and_a_description
run_test "the skill names only paths that exist" test_the_skill_names_only_paths_that_exist
run_test "the skill names only verbs teeup has" test_the_skill_names_only_verbs_teeup_has
run_test "the skill marks the generated and borrowed trees read-only" test_the_skill_marks_the_generated_and_borrowed_trees_read_only
run_test "the parity checklist has a row for every legacy module" test_the_parity_checklist_has_a_row_for_every_legacy_module
run_test "the parity checklist names only capabilities that exist" test_the_parity_checklist_names_only_capabilities_that_exist
run_test "nothing tracked points at the deleted legacy tree" test_nothing_tracked_points_at_the_deleted_legacy_tree

_manual_ste_violations() {
  local dir="$1" f
  for f in "$dir"/*.md; do
    [[ -f "$f" ]] || continue
    [[ "${f##*/}" == "SUMMARY.md" ]] && continue
    awk -v file="${f##*/}" '
      BEGIN {
        in_fence = 0; in_html = 0;
        p_lines = 0; p_text = ""; p_start = 0;
      }
      function check_p() {
        if (p_lines == 0) return;

        text = p_text;

        while (match(text, /`[^`]*`/)) {
          text = substr(text, 1, RSTART - 1) substr(text, RSTART + RLENGTH);
        }

        while (match(text, /\[[^]]*\]\([^)]*\)/)) {
          m_start = RSTART; m_len = RLENGTH;
          m_str = substr(text, m_start, m_len);
          split_idx = index(m_str, "](");
          link_text = substr(m_str, 2, split_idx - 2);
          text = substr(text, 1, m_start - 1) link_text substr(text, m_start + m_len);
        }

        gsub(/e\.g\./, "e_g_", text);
        gsub(/i\.e\./, "i_e_", text);

        n = split(text, sentences, /[.?!][*_")]*( +|$)/);
        s_count = 0;
        for (i = 1; i <= n; i++) {
          s = sentences[i];
          sub(/^[ \t]+/, "", s);
          sub(/[ \t]+$/, "", s);
          if (s != "") {
            s_count++;

            w_count = split(s, words, /[ \t]+/);
            if (w_count > 25) {
              print file ":" p_start ": sentence has " w_count " words (max 25)";
            }
          }
        }

        if (s_count > 6) {
          print file ":" p_start ": paragraph has " s_count " sentences (max 6)";
        }

        p_lines = 0;
        p_text = "";
      }

      /^```/ {
        check_p();
        in_fence = !in_fence;
        next;
      }
      in_fence { next; }

      /<!--/ {
        check_p();
        if (! /-->/) {
          in_html = 1;
        }
        next;
      }
      in_html {
        if (/-->/) in_html = 0;
        next;
      }
      /-->/ {
        check_p();
        in_html = 0;
        next;
      }

      /^\|/ {
        check_p();
        next;
      }

      /^#/ {
        check_p();
        next;
      }

      /^[ \t]*$/ {
        check_p();
        next;
      }

      /^[ \t]*[-*+]/ || /^[ \t]*[0-9]+\./ {
        check_p();
        p_lines = 1;
        p_start = NR;
        p_text = $0;
        next;
      }

      {
        if (p_lines == 0) {
          p_lines = 1;
          p_start = NR;
          p_text = $0;
        } else {
          p_lines++;
          p_text = p_text " " $0;
        }
      }

      END {
        check_p();
      }
    ' "$f"
  done
}

test_manual_keeps_ste_sentence_limits() {
  local found
  found="$(_manual_ste_violations "$REPO/docs/manual/src")"
  if [[ -n "$found" ]]; then
    echo "ASD-STE100 sentence/paragraph limits violated:"
    printf '%s\n' "$found"
    return 1
  fi
  return 0
}

test_manual_ste_check_catches_violations() {
  local dir found
  dir="$(mktemp -d)"

  cat << 'DOC' > "$dir/page.md"
One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twenty-one twenty-two twenty-three twenty-four twenty-five twenty-six.

One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twenty-one twenty-two twenty-three twenty-four twenty-five.

```
One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twenty-one twenty-two twenty-three twenty-four twenty-five twenty-six twenty-seven.
```

| `col` | One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twenty-one twenty-two twenty-three twenty-four twenty-five twenty-six. |

One. Two. Three. Four. Five. Six. Seven.

**One?** Two. Three. Four. Five. Six. Seven.
DOC

  found="$(_manual_ste_violations "$dir")"
  rm -rf "$dir"

  assert_contains "$found" "page.md:1: sentence has 26 words" || return 1
  assert_not_contains "$found" "page.md:3:" || return 1
  assert_not_contains "$found" "page.md:5:" || return 1
  assert_not_contains "$found" "page.md:9:" || return 1
  assert_contains "$found" "page.md:11: paragraph has 7 sentences" || return 1
  assert_contains "$found" "page.md:13: paragraph has 7 sentences" || return 1
}

run_test "manual keeps STE sentence limits" test_manual_keeps_ste_sentence_limits
run_test "manual STE check catches violations" test_manual_ste_check_catches_violations
print_summary
