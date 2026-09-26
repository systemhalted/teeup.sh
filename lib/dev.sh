#!/usr/bin/env bash
# dev.sh - the verbs for people changing teeup itself (spec section 12).
# Requires core.sh, files.sh, capability.sh, menu.sh, lazy.sh.

TEEUP_SKELETON_DIR="${TEEUP_SKELETON_DIR:-$TEEUP_PATH/share/teeup/skeleton}"
TEEUP_TESTS_DIR="${TEEUP_TESTS_DIR:-$TEEUP_PATH/tests}"
export TEEUP_SKELETON_DIR TEEUP_TESTS_DIR

# teeup_verbs -> every verb bin/teeup's dispatcher accepts, one per line,
# sorted. Moved here from tests/docs.sh (which now sources this file for it)
# so the README check and `teeup dev check`'s menu lint (R9.5) read the
# dispatcher the same way and cannot silently disagree about what counts as
# a real verb.
teeup_verbs() {
  awk '/^case "\$verb" in/,/^esac/' "$TEEUP_PATH/bin/teeup" \
    | grep -oE '^  [a-z|_-]+\)' | tr -d ' )' | tr '|' '\n' | sort -u
}

# _dev_render <src> <dest> <name>
# One skeleton file, with @NAME@ replaced. replace_literal (lib/files.sh)
# rather than sed or ${var//pat/repl}: a capability name is tame, but this is
# the helper that is correct for every name, and write_managed_file carries
# the DRY_RUN guard so a dry run creates nothing.
_dev_render() {
  local src="$1" dest="$2" name="$3" line
  {
    while IFS= read -r line || [[ -n "$line" ]]; do
      replace_literal "$line" '@NAME@' "$name"
    done < "$src"
  } | write_managed_file "$dest" "scaffold for $name"
}

# dev_new_capability <name>
# The tier is lazy on purpose: a core or daily capability that is not listed
# in its tier file makes `teeup commands --check` fail, so either of those
# tiers would leave the checkout broken the moment the scaffold was written.
#
# Metadata and the generated test are written 644 and install/configure 755,
# matching what every other capability ships (a fresh render otherwise picks
# up mktemp's 600, which reads as an accidental permissions diff the moment
# the scaffold is committed). If any render fails partway through, whatever
# was already written is removed rather than left as a half a capability.
dev_new_capability() {
  local name="${1:-}" dir f test_file
  if [[ -z "$name" ]]; then
    err "Usage: teeup dev new-capability <name>"
    return 1
  fi
  if ! [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    err "A capability name uses lower-case letters, digits and dashes and starts with a letter or digit (got '$name')."
    return 1
  fi
  # Any existing path, not just a complete capability: cap_exists needs a
  # capability file, so a half-made directory (an interrupted scaffold, or
  # one started by hand) would pass it and have its files overwritten.
  if [[ -e "$(cap_dir "$name")" || -L "$(cap_dir "$name")" ]]; then
    err "$(cap_dir "$name") already exists."
    return 1
  fi
  dir="$(cap_dir "$name")"
  test_file="$TEEUP_TESTS_DIR/capabilities/$name.sh"
  # M3: refuse a hand-written test the same way an existing capability
  # directory is refused, before anything is written -- silently overwriting
  # someone's own test with the skeleton is the one thing the capability-dir
  # check above already exists to prevent, just for the other file.
  if [[ -f "$test_file" ]]; then
    err "$test_file already exists."
    return 1
  fi
  for f in capability install configure; do
    if ! _dev_render "$TEEUP_SKELETON_DIR/$f" "$dir/$f" "$name"; then
      run_cmd rm -rf "$dir"
      err "Could not write $dir/$f; removed the partial scaffold."
      return 1
    fi
  done
  if ! _dev_render "$TEEUP_SKELETON_DIR/test.sh" "$test_file" "$name"; then
    run_cmd rm -rf "$dir"
    run_cmd rm -f "$test_file"
    err "Could not write $test_file; removed the partial scaffold."
    return 1
  fi
  run_cmd chmod 644 "$dir/capability" "$test_file"
  run_cmd chmod 755 "$dir/install" "$dir/configure"
  ok_unless_dry "Scaffolded $dir and $test_file"
  if [[ "$DRY_RUN" != "true" ]]; then
    log "Next (spec section 12):"
    log "  1. Fill in summary, group and the packages or casks in $dir/capability."
    log "  2. For a core or daily capability, change tier= and append $name to"
    log "     $TEEUP_CAPS_DIR/<tier>.list in the same commit, or commands --check fails."
    log "  3. Write install and configure; keep every mutation inside run_cmd."
    log "  4. Add a row to share/teeup/menu.json if it should be in teeup menu."
    log "  5. Add themed/<tool>.tpl inside the capability if the tool has colours."
    log "  6. This scaffold dirties the checkout; commit it, or teeup update will"
    log "     refuse to pull until you do."
    log "  7. Run: teeup dev check $name"
  fi
  return 0
}

# dev_shell_files -> every shell file CI lints, one absolute path per line.
# This mirrors the argument list in .github/workflows/ci.yml's "Shellcheck
# new runtime" step by hand, so the two can drift; tests/lib/dev.sh derives
# ci.yml's own list independently and asserts it matches this one (R9.2),
# and `teeup dev check` says so rather than pretending this file is the
# single source of truth CI itself reads from.
dev_shell_files() {
  local f
  printf '%s\n' "$TEEUP_PATH/bootstrap" "$TEEUP_PATH/bin/teeup"
  for f in "$TEEUP_PATH"/lib/*.sh; do
    if [[ -f "$f" ]]; then printf '%s\n' "$f"; fi
  done
  find "$TEEUP_CAPS_DIR" -type f \( -name install -o -name configure \
    -o -name remove -o -name doctor -o -name theme-apply \
    -o -name font-apply \) 2>/dev/null
  for f in "$TEEUP_PATH"/capabilities/teeup-runtime/default/hooks/*.sample; do
    if [[ -f "$f" ]]; then printf '%s\n' "$f"; fi
  done
  find "$TEEUP_PATH/migrations" -type f -name '*.sh' 2>/dev/null
  for f in "$TEEUP_SKELETON_DIR/install" "$TEEUP_SKELETON_DIR/configure" "$TEEUP_SKELETON_DIR/test.sh"; do
    if [[ -f "$f" ]]; then printf '%s\n' "$f"; fi
  done
  for f in "$TEEUP_TESTS_DIR"/helper.sh "$TEEUP_TESTS_DIR"/run.sh "$TEEUP_TESTS_DIR"/cli.sh \
           "$TEEUP_TESTS_DIR"/bootstrap.sh "$TEEUP_TESTS_DIR"/docs.sh \
           "$TEEUP_TESTS_DIR"/lib/*.sh "$TEEUP_TESTS_DIR"/capabilities/*.sh; do
    if [[ -f "$f" ]]; then printf '%s\n' "$f"; fi
  done
  return 0
}

# _dev_check_menu_command <id> <field> <command> <" verb1 verb2 ... ">
# The first `teeup <word>` of a menu action/when has to be a real dispatch
# arm (R9.5), and for a handful of verbs the next word has to name something
# real too: a capability for install/has/reset/remove (except the two
# install sub-switches that are not capabilities), an app or capability
# launch_resolve can find for launch. Prints one problem line and returns 1
# per bad row; a row that never mentions teeup (or names a verb this
# function does not specialise) is not this function's business and passes.
_dev_check_menu_command() {
  local id="$1" field="$2" s="$3" verbs="$4" rest verb arg cap
  case "$s" in
    *teeup\ *) ;;
    *) return 0 ;;
  esac
  rest="${s#*teeup }"
  verb="${rest%% *}"
  case "$verbs" in
    *" $verb "*) ;;
    *)
      printf 'menu: %s %s calls an unknown verb: teeup %s\n' "$id" "$field" "$verb"
      return 1
      ;;
  esac
  arg="${rest#"$verb"}"
  arg="${arg# }"
  arg="${arg%%&&*}"
  arg="${arg%%;*}"
  arg="${arg%%|*}"
  while [[ "$arg" == *" " ]]; do arg="${arg% }"; done
  case "$verb" in
    install)
      case "$arg" in
        dev-env*|font*) return 0 ;;
      esac
      cap="${arg%% *}"
      if [[ -n "$cap" ]] && ! cap_exists "$cap"; then
        printf 'menu: %s %s names an unknown capability: %s\n' "$id" "$field" "$cap"
        return 1
      fi
      ;;
    has|reset|remove)
      cap="${arg%% *}"
      if [[ -n "$cap" ]] && ! cap_exists "$cap"; then
        printf 'menu: %s %s names an unknown capability: %s\n' "$id" "$field" "$cap"
        return 1
      fi
      ;;
    launch)
      if [[ -n "$arg" ]] && ! launch_resolve "$arg" >/dev/null 2>&1; then
        printf 'menu: %s %s names an app or capability launch cannot resolve: %s\n' "$id" "$field" "$arg"
        return 1
      fi
      ;;
  esac
  return 0
}

# _dev_check_menu_rows <cache> -> one problem per line on stdout; 0 clean.
_dev_check_menu_rows() {
  local cache="$1" id action when verbs bad=0
  verbs=" $(teeup_verbs | tr '\n' ' ') "
  for id in $(menu_ids "$cache"); do
    action="$(menu_field "$cache" "$id" action)"
    when="$(menu_field "$cache" "$id" when)"
    if [[ -n "$action" ]]; then
      _dev_check_menu_command "$id" action "$action" "$verbs" || bad=1
    fi
    if [[ -n "$when" ]]; then
      _dev_check_menu_command "$id" when "$when" "$verbs" || bad=1
    fi
  done
  [[ $bad -eq 0 ]]
}

# _dev_check_menu_file <file> <label> [<extra-parent-ids-file>] -> prints
# problems (if any); 0 clean. menu_check's structural lint and the R9.5
# row-content lint both run on whatever file is passed -- shipped or the
# user's -- so a mistake in either is visible. It is the caller's job to
# decide whether a bad result here changes dev_check's own exit status
# (R9.3: a broken shipped menu fails the repo check, a broken personal one
# is only reported).
#
# <extra-parent-ids-file>, when given, is parsed too and its ids count as
# known parents for the "no parent row" check (M4): the personal menu.json
# is linted on its own, so without this a row the README itself tells users
# to append under a shipped submenu (install.editors.helix under
# install.editors) reads as an orphan just because that submenu lives only
# in the shipped file. A row whose parent is missing from BOTH files is
# still reported.
_dev_check_menu_file() {
  local file="$1" label="$2" extra_file="${3:-}" cache extra_cache extra_ids="" out1 out2 rc=0
  cache="$(mktemp)"
  if ! menu_parse "$file" > "$cache"; then
    rm -f "$cache"
    err "Could not read $label."
    return 1
  fi
  if [[ -n "$extra_file" && -f "$extra_file" ]]; then
    extra_cache="$(mktemp)"
    if menu_parse "$extra_file" > "$extra_cache"; then
      extra_ids="$(menu_ids "$extra_cache")"
    fi
    rm -f "$extra_cache"
  fi
  out1="$(menu_check "$cache" "$extra_ids")" || rc=1
  out2="$(_dev_check_menu_rows "$cache")" || rc=1
  rm -f "$cache"
  if [[ -n "$out1" ]]; then printf '%s\n' "$out1"; fi
  if [[ -n "$out2" ]]; then printf '%s\n' "$out2"; fi
  if [[ $rc -ne 0 ]]; then
    return 1
  fi
  ok "$label is well formed."
  return 0
}

# _dev_check_env_clean <script> [args...]
# Runs a test script in a subshell with DRY_RUN and every exported TEEUP_*
# variable unset first (R9.4), so a contributor's own DRY_RUN=true, or a
# TEEUP_MENU_FILE/TEEUP_CAPS_DIR/TEEUP_PKG_BACKEND left over from something
# else, cannot leak into the suite CI runs clean. compgen -e (not an
# associative array) so this works on bash 3.2.
_dev_check_env_clean() {
  (
    local v
    for v in $(compgen -e); do
      case "$v" in
        TEEUP_*) unset "$v" ;;
      esac
    done
    unset DRY_RUN
    bash "$@"
  )
}

# dev_check [<capability>]
# The four things CI runs, plus the menu lint, in one command (spec section
# 12 step 7; this also completes 5a's deferred dev-check step, R9.5). With a
# capability name it runs only that capability's suite, which takes a
# second; with no name it runs the whole suite, which takes minutes.
#
# Exit status mirrors doctor_verdict's tri-state (R9.1): 0 only when every
# check ran AND none found a problem; 1 when a check ran and found a real
# problem; 2 when nothing is confirmed broken but something could not be
# checked at all (shellcheck missing today). A check that could not run is
# not a pass, so 2 never prints "everything passed".
dev_check() {
  local target="${1:-}" problems=0 unknowns="" f files suite run_sh capname
  local user_menu

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    err "teeup dev check does not run under DRY_RUN=true: it runs the real test suites, which need a real DRY_RUN=false. Unset it and run again."
    return 1
  fi

  if [[ -n "$target" ]] && ! cap_exists "$target"; then
    err "$target is not a known capability (try: teeup list)."
    return 1
  fi

  log "== capability metadata =="
  if cap_check; then
    ok "Metadata is clean."
  else
    problems=$((problems + 1))
  fi

  log "== menu definition =="
  if ! _dev_check_menu_file "$TEEUP_MENU_FILE" "$TEEUP_MENU_FILE"; then
    problems=$((problems + 1))
  fi
  user_menu="$(menu_user_file)"
  if [[ -f "$user_menu" ]]; then
    log "-- $user_menu (yours; does not affect this result) --"
    _dev_check_menu_file "$user_menu" "$user_menu" "$TEEUP_MENU_FILE" || true
  fi

  log "== shellcheck =="
  if have shellcheck; then
    files=()
    while IFS= read -r f; do
      files[${#files[@]}]="$f"
    done < <(dev_shell_files)
    # bash 3.2 under `set -u` treats the expansion of an EMPTY array as an
    # unbound variable, so the count decides before "${files[@]}" is used.
    if [[ ${#files[@]} -eq 0 ]]; then
      warn "No shell files found under $TEEUP_PATH."
    elif shellcheck --severity=warning "${files[@]}"; then
      ok "shellcheck is clean."
    else
      problems=$((problems + 1))
    fi
  else
    unknowns="${unknowns:+$unknowns, }shellcheck"
    warn "shellcheck is not installed, so it was skipped here; CI still runs it. Install it with: brew install shellcheck"
  fi

  log "== tests =="
  if [[ -z "$target" ]]; then
    # R9.6: every real capability needs a dry-run test of its own, whether or
    # not this run happens to be exercising it right now.
    for capname in $(cap_list); do
      if [[ ! -f "$TEEUP_TESTS_DIR/capabilities/$capname.sh" ]]; then
        err "No $TEEUP_TESTS_DIR/capabilities/$capname.sh. Every capability needs a dry-run test under the mock harness; teeup dev new-capability writes one."
        problems=$((problems + 1))
      fi
    done
  fi
  if [[ -n "$target" ]]; then
    suite="$TEEUP_TESTS_DIR/capabilities/$target.sh"
    if [[ ! -f "$suite" ]]; then
      err "No $suite. Every capability needs a dry-run test under the mock harness; teeup dev new-capability writes one."
      problems=$((problems + 1))
    elif _dev_check_env_clean "$suite"; then
      ok "$target's suite passed."
    else
      problems=$((problems + 1))
    fi
  else
    run_sh="$TEEUP_TESTS_DIR/run.sh"
    if _dev_check_env_clean "$run_sh"; then
      ok "The whole suite passed."
    else
      problems=$((problems + 1))
    fi
  fi

  if [[ $problems -gt 0 ]]; then
    err "teeup dev check: $problems check(s) failed."
    return 1
  fi
  if [[ -n "$unknowns" ]]; then
    err "teeup dev check: could not check: $unknowns."
    return 2
  fi
  ok "teeup dev check: everything passed."
  return 0
}
