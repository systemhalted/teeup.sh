#!/usr/bin/env bash
# migrations.sh - one-off changes for machines that already run teeup.
# A migration is $TEEUP_MIGRATIONS_DIR/<unix-epoch>.sh (migrations/ in the
# checkout). `teeup update` runs the pending ones oldest first, each exactly
# once per machine, and records each under $TEEUP_STATE_DIR/migrations/<name>
# (lib/state.sh). A fresh ./bootstrap marks every shipped migration applied
# without running it: its capabilities already install the current state
# (spec sections 5 and 9, Omarchy's omarchy-migrate).
# Requires core.sh, state.sh, answers.sh and capability.sh.

TEEUP_MIGRATIONS_DIR="${TEEUP_MIGRATIONS_DIR:-$TEEUP_PATH/migrations}"
export TEEUP_MIGRATIONS_DIR

# migrations_list -> every migration's file name, oldest first
# Only names that start with a digit and end in .sh count, so a README or a
# helper file in the directory is never run. sort -n orders by the leading
# number, which stays right if an epoch ever gains an eleventh digit.
migrations_list() {
  local f name
  for f in "$TEEUP_MIGRATIONS_DIR"/[0-9]*.sh; do
    name="${f##*/}"
    # A directory (or anything else that is not a regular file) named like a
    # migration is announced too: a silent skip is how a migration nobody runs
    # goes unnoticed, which is the same reason the name check below speaks up.
    if [[ ! -f "$f" ]]; then
      [[ -e "$f" ]] && warn "Not a file, so it is skipped: $f"
      continue
    fi
    # <epoch>.sh exactly, which is the only name migration_new writes. The
    # glob alone would also accept "1700000000 copy.sh", and a name carrying a
    # space breaks every caller that reads this list a line at a time -- and
    # would have word-split into bogus tokens before those callers were
    # fixed. Anything that looks like a migration but is not named like one is
    # announced rather than silently skipped: a migration nobody runs is the
    # kind of thing that is only noticed much later.
    if ! [[ "$name" =~ ^[0-9]+\.sh$ ]]; then
      warn "Not a migration name, so it is skipped: $f (a migration is <unix-epoch>.sh)"
      continue
    fi
    printf '%s\n' "$name"
  done | sort -n
}

# migrations_pending -> the names not yet applied on this machine, oldest first
migrations_pending() {
  local m
  while IFS= read -r m; do
    [[ -n "$m" ]] || continue
    if ! state_migration_done "$m"; then printf '%s\n' "$m"; fi
  done < <(migrations_list)
  return 0
}

# migrations_mark_all
# What ./bootstrap does once, on a machine it has never finished on.
migrations_mark_all() {
  local m
  while IFS= read -r m; do
    [[ -n "$m" ]] || continue
    state_migration_mark "$m"
  done < <(migrations_list)
  return 0
}

# migration_run <name>
# Runs one migration the way cap_run runs a capability script: a fresh
# `bash -eu` with lib/all.sh loaded and the answers sourced, stdin on
# /dev/null, bracketed by run_logged. TEEUP_MIGRATION holds its name. The
# marker is written only after a zero exit. DRY_RUN reaches the script like
# any capability's, so a migration previews through run_cmd too.
migration_run() {
  local name="$1" file
  file="$TEEUP_MIGRATIONS_DIR/$name"
  if [[ ! -f "$file" ]]; then
    err "No migration named $name in $TEEUP_MIGRATIONS_DIR"
    return 1
  fi
  TEEUP_MIGRATION="$name"
  export TEEUP_MIGRATION
  run_logged "migration $name" false \
    bash -eu -c 'source "$TEEUP_PATH/lib/all.sh"; answers_load; source "$1"' bash "$file" || return 1
  state_migration_mark "$name"
}

# migrations_run_pending
# Stops at the first migration that fails and returns 1: a later migration is
# written against the state an earlier one leaves, so running it on top of a
# failure could do damage the failed one was meant to prevent. The failed
# migration stays unmarked and runs again on the next `teeup update`.
migrations_run_pending() {
  # `while read` over a process substitution, not `for m in $(...)`: the loop
  # body assigns `ran`, so it has to run in this shell, and a name is one
  # whole line whatever it contains.
  local m ran=0
  while IFS= read -r m; do
    [[ -n "$m" ]] || continue
    log "Running migration $m"
    if ! migration_run "$m"; then
      err "Migration $m failed, so the migrations after it did not run. Fix the cause, then run: teeup update"
      return 1
    fi
    ran=$((ran + 1))
  done < <(migrations_pending)
  if [[ $ran -eq 0 ]]; then
    log "No pending migrations."
  else
    ok_unless_dry "Applied $ran migration(s)."
  fi
}

# migration_refresh <capability>
# For a migration that ships a changed config: re-runs <capability>'s
# configure with TEEUP_REFRESH naming it, which turns each of its
# copy_config_once calls into refresh_if_pristine (lib/files.sh). A file the
# user never edited is replaced with the new shipped version, rendered by the
# same configure code that installed it; an edited file is left alone for the
# migration to patch. A capability that is not applicable on this machine, is
# not installed here, or is skipped, has nothing to refresh.
migration_refresh() {
  local cap="$1" rc=0
  if ! cap_exists "$cap"; then
    err "migration_refresh: unknown capability $cap"
    return 1
  fi
  if state_na check "cap-$cap"; then
    log "$cap is not applicable on this machine; nothing to refresh."
    return 0
  fi
  if cap_skipped "$cap" || ! state_done check "cap-$cap"; then
    log "$cap is not installed here; nothing to refresh."
    return 0
  fi
  export TEEUP_REFRESH="$cap"
  cap_run "$cap" configure || rc=$?
  unset TEEUP_REFRESH
  return $rc
}

# migration_new -> creates a migration file and prints its path
# Named from the checkout's last commit time, as spec section 9 and Omarchy's
# omarchy-dev-add-migration do: a migration written on top of the latest
# commit sorts after every migration that commit already carries, whatever
# this machine's clock says. A second migration for the same commit takes the
# next free second. A checkout without git history uses the current time.
migration_new() {
  local stamp file
  stamp="$(git -C "$TEEUP_PATH" log -1 --format=%ct 2>/dev/null || true)"
  if ! [[ "$stamp" =~ ^[0-9]+$ ]]; then
    warn "No git history at $TEEUP_PATH; naming the migration from the current time."
    stamp="$(date +%s)"
  fi
  while [[ -e "$TEEUP_MIGRATIONS_DIR/$stamp.sh" ]]; do
    stamp=$((10#$stamp + 1))
  done
  file="$TEEUP_MIGRATIONS_DIR/$stamp.sh"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would create $file" >&2
    printf '%s\n' "$file"
    return 0
  fi
  # A migrations directory that will not take the file would otherwise leak a
  # raw "cannot create" from the redirection below, which is also processed
  # before any 2>/dev/null could silence it.
  if ! mkdir -p "$TEEUP_MIGRATIONS_DIR" 2>/dev/null || [[ ! -w "$TEEUP_MIGRATIONS_DIR" ]]; then
    err "Cannot write $TEEUP_MIGRATIONS_DIR, so no migration was created."
    return 1
  fi
  cat > "$file" <<MIGRATION
#!/usr/bin/env bash
# Migration $stamp. Replace this line with what the migration changes and why.
#
# teeup update runs this once per machine, as bash -eu with lib/all.sh loaded
# and the answers sourced; a fresh ./bootstrap marks it applied without
# running it. Exit non-zero to stop the update: it runs again next time.
# Mutate only through run_cmd or a DRY_RUN-guarded primitive.
#
# A shipped config changed? \`migration_refresh <capability>\` refreshes the
# copies nobody edited (the stock-checksum rule); patch an edited one after
# \`backup_copy <file>\`.
MIGRATION
  ok "Created $file" >&2
  printf '%s\n' "$file"
}
