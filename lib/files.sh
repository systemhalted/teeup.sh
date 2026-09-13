#!/usr/bin/env bash
# files.sh - idempotent file primitives and the copy-once config model.
# Requires core.sh.

file_sha() {
  # Read from stdin rather than naming the file on argv: both shasum and
  # sha256sum prefix the digest with a "\" when the filename itself contains
  # a backslash (GNU/Perl escaping), which would otherwise corrupt every
  # comparison against a stock-recorded sha for such a path.
  if have shasum; then
    shasum -a 256 < "$1" | cut -d ' ' -f 1
  else
    sha256sum < "$1" | cut -d ' ' -f 1
  fi
}

# The stock record remembers the sha of the shipped file at the moment it was
# copied into place. It is how copy_config_once tells "still pristine" from
# "the user edited this" without ever diffing against the current shipped file.
_stock_record_path() {
  local dest="$1" rel
  rel="${dest#"$HOME"/}"
  rel="${rel//\//__}"
  printf '%s/stock/%s\n' "$TEEUP_STATE_DIR" "$rel"
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
  # `! -e` on its own is true for a *dangling* symlink, even though the
  # directory entry is very much there, so teeup used to treat one as absent
  # and hand it straight to `cp`: GNU cp refuses to write through a dangling
  # destination symlink (failing the capability) and a link pointing somewhere
  # unexpected gets written through instead, in both cases without the backup
  # that preserves what a dotfile manager put there. A symlink is never a file
  # teeup installed (this function only ever copies a regular file into place),
  # so it is foreign by definition and takes the backup-then-install path
  # below.
  if [[ ! -e "$dest" && ! -L "$dest" ]]; then
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
  if [[ -L "$dest" && ! -e "$dest" ]]; then
    # A dangling symlink has no content to hash, and no stock record can
    # belong to it; leaving both empty sends it to the foreign-file path.
    recorded=""
    current=""
  else
    recorded="$(stock_sha "$dest" || true)"
    current="$(file_sha "$dest")"
  fi
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
  # A backed-up dangling symlink has nothing to diff; diff says so on stderr
  # and the `|| true` keeps that from failing the capability.
  echo "Lines from your previous file that are not in the teeup version:"
  diff "$backup" "$dest" || true
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
  backup="$(backup_target "$dest")"
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

# replace_literal <text> <token> <replacement>
# Literal, whole-text replacement of every occurrence of <token>, printed with
# a trailing newline. Built on ${x%%"$tok"*} and ${x#*"$tok"} rather than
# ${x//pat/repl}: bash 3.2 mis-parses a quoted pattern containing "/" in the
# latter (the first "/" inside the quotes ends the pattern), and bash 5.2
# treats "&" in the replacement as the matched text. Neither applies here, so
# a replacement may contain /, &, |, \ or $ and lands verbatim.
replace_literal() {
  local text="$1" tok="$2" rep="$3" out="" rest
  rest="$text"
  [[ -n "$tok" ]] || { printf '%s\n' "$text"; return 0; }
  while case "$rest" in *"$tok"*) true ;; *) false ;; esac; do
    out="$out${rest%%"$tok"*}$rep"
    rest="${rest#*"$tok"}"
  done
  printf '%s\n' "$out$rest"
}
