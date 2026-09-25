#!/usr/bin/env bash
# dev.sh - the verbs for people changing teeup itself (spec section 12).
# Requires core.sh, files.sh, capability.sh.

TEEUP_SKELETON_DIR="${TEEUP_SKELETON_DIR:-$TEEUP_PATH/share/teeup/skeleton}"
TEEUP_TESTS_DIR="${TEEUP_TESTS_DIR:-$TEEUP_PATH/tests}"
export TEEUP_SKELETON_DIR TEEUP_TESTS_DIR

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
  if cap_exists "$name"; then
    err "$(cap_dir "$name") already exists."
    return 1
  fi
  dir="$(cap_dir "$name")"
  test_file="$TEEUP_TESTS_DIR/capabilities/$name.sh"
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
