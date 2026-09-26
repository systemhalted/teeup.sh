#!/usr/bin/env bash
# menu.sh - the declarative menu (spec section 2: Omarchy's menu, and section
# 4: share/teeup/menu.json). Ids are dotted, so the tree is in the ids and
# there is no nesting to parse; a row is hidden when its `when` command fails,
# which is Omarchy's "predicates as exit codes"; the user's own menu.json
# overrides a shipped row by id and appends new ones.
# Requires core.sh and ui.sh.

TEEUP_MENU_FILE="${TEEUP_MENU_FILE:-$TEEUP_PATH/share/teeup/menu.json}"
export TEEUP_MENU_FILE

menu_user_file() { printf '%s/menu.json\n' "$TEEUP_CONFIG_DIR"; }

# menu_parse <file> -> "id<TAB>field<TAB>value" per field, in file order
menu_parse() { awk -f "$TEEUP_PATH/lib/menu.awk" "$1"; }

# _menu_merge <shipped-triples> <user-triples>
# An id in both files takes the user's entry whole -- fields are replaced, not
# merged -- and keeps the shipped position; an id only in the user file is
# appended. FILENAME rather than FNR==NR tells the two apart, so an empty
# shipped file cannot make the user file look like the first one.
_menu_merge() {
  # first="$1" awk, not -v first="$1": the path comes from mktemp, which
  # honours $TMPDIR, and awk's -v processes backslash escapes in its value.
  # A TMPDIR containing a backslash would then make this never equal awk's
  # own FILENAME, silently dropping every user override (I4). ENVIRON does
  # not process escapes.
  first="$1" awk -F'\t' '
    FILENAME == ENVIRON["first"] {
      if (!($1 in a)) { a[$1] = ""; aorder[++na] = $1 }
      a[$1] = a[$1] $0 "\n"
      next
    }
    {
      if (!($1 in b)) { b[$1] = ""; border[++nb] = $1 }
      b[$1] = b[$1] $0 "\n"
    }
    END {
      for (k = 1; k <= na; k++) { id = aorder[k]; if (id in b) printf "%s", b[id]; else printf "%s", a[id] }
      for (k = 1; k <= nb; k++) { id = border[k]; if (!(id in a)) printf "%s", b[id] }
    }
  ' "$1" "$2"
}

# menu_entries -> the merged stream. A malformed file on either side is a
# failure with nothing on stdout: half a menu is worse than none, because the
# missing half looks like a row that simply does not exist here.
menu_entries() {
  local shipped user tmp_a tmp_b rc=0
  shipped="$TEEUP_MENU_FILE"
  if [[ ! -f "$shipped" ]]; then
    err "No menu definition at $shipped"
    return 1
  fi
  user="$(menu_user_file)"
  tmp_a="$(mktemp)"
  if ! menu_parse "$shipped" > "$tmp_a"; then
    rm -f "$tmp_a"
    err "Could not read $shipped"
    return 1
  fi
  if [[ ! -f "$user" ]]; then
    cat "$tmp_a"
    rm -f "$tmp_a"
    return 0
  fi
  tmp_b="$(mktemp)"
  if ! menu_parse "$user" > "$tmp_b"; then
    rm -f "$tmp_a" "$tmp_b"
    err "Could not read $user"
    return 1
  fi
  _menu_merge "$tmp_a" "$tmp_b" || rc=$?
  rm -f "$tmp_a" "$tmp_b"
  return $rc
}

# menu_cache -> the path of a temp file holding menu_entries. Every query
# below reads that file, so the two menu files are parsed once per run rather
# than once per lookup. The caller deletes it.
menu_cache() {
  local tmp
  tmp="$(mktemp)"
  if ! menu_entries > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  printf '%s\n' "$tmp"
}

# ids and field names are dotted words and bare words, so neither can carry a
# backslash for awk's -v to interpret.
menu_ids() { awk -F'\t' '!($1 in seen) { seen[$1] = 1; print $1 }' "$1"; }

menu_field() { awk -F'\t' -v id="$2" -v key="$3" '$1 == id && $2 == key { print $3; exit }' "$1"; }

# menu_children <cache> [parent]
# The direct children of <parent> ("" for the top level): an id with exactly
# one more dotted segment, in file order, each once.
menu_children() {
  awk -F'\t' -v parent="$2" '
    {
      id = $1
      if (parent == "") {
        if (index(id, ".") != 0) next
      } else {
        prefix = parent "."
        if (substr(id, 1, length(prefix)) != prefix) next
        rest = substr(id, length(prefix) + 1)
        if (rest == "" || index(rest, ".") != 0) next
      }
      if (!(id in seen)) { seen[id] = 1; print id }
    }
  ' "$1"
}

menu_label() {
  local icon label
  icon="$(menu_field "$1" "$2" icon)"
  label="$(menu_field "$1" "$2" label)"
  if [[ -z "$label" ]]; then label="$2"; fi
  if [[ -n "$icon" ]]; then
    printf '%s %s\n' "$icon" "$label"
  else
    printf '%s\n' "$label"
  fi
}

# menu_visible <cache> <id>
# A row with no `when` is always shown. A `when` is a shell condition run with
# the checkout's bin directory first on PATH, so `teeup has <capability>` --
# the exit-code predicate bin/teeup has carried since phase 1 -- works even
# before ~/.local/bin/teeup exists.
menu_visible() {
  local when
  when="$(menu_field "$1" "$2" when)"
  if [[ -z "$when" ]]; then
    return 0
  fi
  PATH="$TEEUP_PATH/bin:$PATH" bash -c "$when" >/dev/null 2>&1
}

# menu_run <action>
menu_run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would run: $1"
    return 0
  fi
  PATH="$TEEUP_PATH/bin:$PATH" bash -c "$1"
}

# menu_validate_picker_env -> dies when TEEUP_MENU_PICKER is set to anything
# other than auto, gum, fzf or plain; a no-op otherwise.
#
# This is meant to be called bare, never through $(...): a caller that instead
# writes `x="$(menu_picker)"` and forgets the `|| ...` on that assignment gets
# a die() whose exit 1 lands on the subshell only, and the assignment itself
# still succeeds -- measured as `TEEUP_MENU_PICKER=banana teeup menu` printing
# the die message and then exiting 0. Checking the environment variable here,
# in the caller's own shell, before any $(...) is opened at all, means a bad
# value is fatal to the right process no matter how the caller later happens
# to invoke menu_picker or menu_pick.
menu_validate_picker_env() {
  case "${TEEUP_MENU_PICKER:-auto}" in
    auto|gum|fzf|plain) return 0 ;;
    *) die "TEEUP_MENU_PICKER must be auto, gum, fzf or plain (got '$TEEUP_MENU_PICKER')" ;;
  esac
}

# menu_picker -> gum | fzf | plain
# TEEUP_NO_GUM turns off BOTH full-screen pickers, not only gum: each paints
# on /dev/tty, and the one switch tests use to get deterministic, pipe-driven
# prompts has to cover both. A test that wants the fzf branch says so with
# TEEUP_MENU_PICKER=fzf and mocks fzf.
menu_picker() {
  menu_validate_picker_env
  case "${TEEUP_MENU_PICKER:-auto}" in
    gum|fzf|plain)
      printf '%s\n' "$TEEUP_MENU_PICKER"
      return 0
      ;;
  esac
  # _ui_gum is lib/ui.sh's own rule for "is gum usable", so the menu and the
  # wizard can never disagree about it.
  if _ui_gum; then
    printf 'gum\n'
  elif [[ -z "${TEEUP_NO_GUM:-}" ]] && have fzf; then
    printf 'fzf\n'
  else
    printf 'plain\n'
  fi
}

# menu_pick <prompt> <option...> -> the chosen option, or 1 when cancelled.
# Cancelling is a first-class answer here, unlike ui_choose's "empty means the
# first option": a menu needs a way back out. In the plain branch, a genuine
# cancel (an empty line, q, Q or end of input) is the only thing that returns
# 1; an answer that is merely unrecognised or out of range re-prompts instead
# of quitting the whole menu on a typo.
menu_pick() {
  local prompt="$1"
  shift
  local picker answer i opt
  local n=$#
  picker="$(menu_picker)" || return 1
  case "$picker" in
    gum)
      answer="$(gum choose --header "$prompt" "$@")" || return 1
      ;;
    fzf)
      answer="$(printf '%s\n' "$@" | fzf --prompt "$prompt > " --height 40% --reverse)" || return 1
      ;;
    *)
      printf '%s\n' "$prompt" >&2
      i=1
      for opt in "$@"; do
        printf '  %d) %s\n' "$i" "$opt" >&2
        i=$((i + 1))
      done
      while :; do
        printf 'Choice (empty or q to go back): ' >&2
        IFS= read -r answer || return 1
        case "$answer" in
          ""|q|Q) return 1 ;;
        esac
        if [[ "$answer" =~ ^[0-9]+$ ]] && (( 10#$answer >= 1 && 10#$answer <= n )); then
          i=1
          for opt in "$@"; do
            if (( i == 10#$answer )); then
              printf '%s\n' "$opt"
              return 0
            fi
            i=$((i + 1))
          done
        fi
        for opt in "$@"; do
          if [[ "$opt" == "$answer" ]]; then
            printf '%s\n' "$opt"
            return 0
          fi
        done
        warn "Unknown choice '$answer'; pick again"
      done
      ;;
  esac
  if [[ -z "$answer" ]]; then
    return 1
  fi
  printf '%s\n' "$answer"
}

_menu_check_siblings() {
  local cache="$1" parent="$2" child dup
  dup="$(for child in $(menu_children "$cache" "$parent"); do menu_label "$cache" "$child"; done | sort | uniq -d)"
  if [[ -n "$dup" ]]; then
    printf 'menu: two rows under %s share the label: %s\n' "${parent:-the top level}" "$dup"
  fi
  return 0
}

_menu_check_body() {
  local cache="$1" id parent ids
  ids="$(menu_ids "$cache")"
  _menu_check_siblings "$cache" ""
  for id in $ids; do
    if [[ -z "$(menu_field "$cache" "$id" label)" ]]; then
      printf 'menu: %s has no label\n' "$id"
    fi
    if [[ "$(menu_field "$cache" "$id" label)" == ".." ]]; then
      printf 'menu: %s has the reserved label ".."; the menu uses it to mean "go back"\n' "$id"
    fi
    parent="${id%.*}"
    if [[ "$parent" != "$id" ]] && ! printf '%s\n' "$ids" | grep -qxF "$parent"; then
      printf 'menu: %s has no parent row %s\n' "$id" "$parent"
    fi
    if [[ -n "$(menu_field "$cache" "$id" action)" && -n "$(menu_children "$cache" "$id")" ]]; then
      printf 'menu: %s has both an action and child rows\n' "$id"
    fi
    if [[ -z "$(menu_field "$cache" "$id" action)" && -z "$(menu_children "$cache" "$id")" ]]; then
      printf 'menu: %s has neither an action nor child rows\n' "$id"
    fi
    _menu_check_siblings "$cache" "$id"
  done
  return 0
}

# menu_check <cache> -> one problem per line on stdout; 0 when clean.
# Two siblings with the same label are a real defect: the picker hands back a
# label, which is mapped to an id by position, so the second of two identical
# labels can never be chosen.
menu_check() {
  local out
  out="$(_menu_check_body "$1")"
  if [[ -n "$out" ]]; then
    printf '%s\n' "$out"
    return 1
  fi
  return 0
}
