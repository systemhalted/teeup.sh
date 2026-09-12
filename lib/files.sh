#!/usr/bin/env bash
# files.sh - idempotent file primitives and the copy-once config model.
# Requires core.sh.

file_sha() {
  if have shasum; then
    shasum -a 256 "$1" | cut -d ' ' -f 1
  else
    sha256sum "$1" | cut -d ' ' -f 1
  fi
}

# The stock record remembers the sha of the shipped file at the moment it was
# copied into place. It is how copy_config_once tells "still pristine" from
# "the user edited this" without ever diffing against the current shipped file.
_stock_record_path() {
  local dest="$1"
  printf '%s/stock/%s\n' "$TEEUP_STATE_DIR" "$(printf '%s' "$dest" | sed -e "s#^$HOME/##" -e 's#/#__#g')"
}

stock_record() {
  local dest="$1" sha="$2" record
  record="$(_stock_record_path "$dest")"
  mkdir -p "$(dirname "$record")"
  printf '%s\n' "$sha" > "$record"
}

stock_sha() {
  local record
  record="$(_stock_record_path "$1")"
  [[ -f "$record" ]] && cat "$record"
}

# append_once <file> <marker>   (block on stdin)
append_once() {
  local file="$1" marker="$2" tmp
  if grep -qF "# $marker" "$file" 2>/dev/null; then
    log "Already present in $(basename "$file"): $marker"
    cat >/dev/null
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would append to $file: $marker"
    cat >/dev/null
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  touch "$file"
  tmp="$(mktemp)"
  { echo ""; echo "# $marker"; cat; } > "$tmp"
  cat "$tmp" >> "$file"
  rm -f "$tmp"
  ok "Updated $(basename "$file") with: $marker"
}

# write_managed_file <file> <label>   (content on stdin)
write_managed_file() {
  local file="$1" label="$2" tmp
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would write $file ($label)"
    cat >/dev/null
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"
  cat > "$tmp"
  if [[ -f "$file" ]] && cmp -s "$tmp" "$file"; then
    rm -f "$tmp"
    log "Already current: $file"
    return 0
  fi
  mv "$tmp" "$file"
  ok "Wrote $file ($label)"
}

# backup_target <path>  -> prints the backup path on stdout
backup_target() {
  local target="$1" backup
  backup="${target}.teeup_backup_$(date +%Y%m%d%H%M%S)"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would back up $target to $backup" >&2
  else
    mv "$target" "$backup"
    ok "Backed up $target to $backup" >&2
  fi
  printf '%s\n' "$backup"
}

# copy_config_once <src> <dest>
# Installs a shipped file into the user's home exactly once. Never overwrites
# a file the user has edited. A foreign file (one teeup did not install) is
# backed up first and its diff printed so the user can carry lines over.
copy_config_once() {
  local src="$1" dest="$2" recorded current backup
  if [[ ! -e "$dest" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      printf "%b %s\n" "🔍" "[DRY-RUN] Would install $dest from $src"
      return 0
    fi
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    stock_record "$dest" "$(file_sha "$src")"
    ok "Installed $dest"
    return 0
  fi
  recorded="$(stock_sha "$dest" || true)"
  current="$(file_sha "$dest")"
  if [[ -n "$recorded" ]]; then
    if [[ "$recorded" == "$current" ]]; then
      log "Already installed: $dest"
    else
      log "Keeping your edited $dest (run teeup reset to restore the shipped file)"
    fi
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would back up foreign $dest and install $src"
    return 0
  fi
  backup="$(backup_target "$dest")"
  cp "$src" "$dest"
  stock_record "$dest" "$(file_sha "$src")"
  ok "Installed $dest (your previous file is at $backup)"
  echo "Lines from your previous file that are not in the teeup version:"
  diff "$dest" "$backup" || true
}

# refresh_config <src> <dest>
# Backup, replace with the shipped file, print the diff, drop the backup if
# nothing changed. Omarchy's refresh-config.
refresh_config() {
  local src="$1" dest="$2" backup
  if [[ ! -e "$dest" ]]; then
    copy_config_once "$src" "$dest"
    return $?
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would reset $dest to $src"
    return 0
  fi
  backup="$(backup_target "$dest" 2>/dev/null)"
  cp "$src" "$dest"
  stock_record "$dest" "$(file_sha "$src")"
  if cmp -s "$dest" "$backup"; then
    rm -f "$backup"
    log "Already at the shipped version: $dest"
    return 0
  fi
  ok "Reset $dest (backup at $backup)"
  echo "Changes:"
  diff "$dest" "$backup" || true
}
