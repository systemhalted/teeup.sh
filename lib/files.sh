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

# _file_mode <path> -> its octal permission bits (e.g. "644"), or nothing.
# GNU stat is probed first on purpose: GNU's -f means "filesystem status" and
# would print something odd before failing, while BSD stat rejects -c cleanly
# on stderr. Same idiom as capabilities/ssh/configure's own file_mode.
_file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || true
}

# write_managed_file <file> <label>   (content on stdin)
# Sets WRITE_MANAGED_FILE_CHANGED to true when the file was actually written
# (and in a dry run, when it would have been), so a caller with its own
# success line to print can tell a write from a no-op instead of claiming a
# mutation on every run.
write_managed_file() {
  local file="$1" label="$2" tmp mode=""
  # shellcheck disable=SC2034  # read by callers (capabilities/git/configure)
  WRITE_MANAGED_FILE_CHANGED=true
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
    # shellcheck disable=SC2034  # read by callers (capabilities/git/configure)
    WRITE_MANAGED_FILE_CHANGED=false
    log "Already current: $file"
    return 0
  fi
  # A file that already exists keeps its own mode across a rewrite: mktemp's
  # 0600 would otherwise land on it once mv puts the temp file's inode at
  # that path, quietly narrowing a 0644 editor settings file to 0600 and
  # showing up as a permissions diff in whatever dotfiles repo tracks it
  # (Task 1 review). A file that does not exist yet keeps today's behaviour
  # (mktemp's 0600, same as always) -- there is nothing to preserve, and a
  # capability that wants something else (git identity, ssh material) chmods
  # it itself afterward. Never through a symlink: mv replaces the link with a
  # plain file regardless, and the link's target mode is not this file's mode
  # to inherit.
  if [[ -e "$file" && ! -L "$file" ]]; then
    mode="$(_file_mode "$file")"
  fi
  mv "$tmp" "$file"
  [[ -n "$mode" ]] && chmod "$mode" "$file"
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

# copy_config_once <src> <dest> [display_src]
# Installs a shipped file into the user's home exactly once. Never overwrites
# a file the user has edited. A foreign file (one teeup did not install) is
# backed up first and its diff printed so the user can carry lines over.
# <display_src> names the file in the DRY-RUN messages below when it differs
# from <src> -- a capability that renders before copying (zsh, git) passes a
# temp file as <src>, which the messages would otherwise name: useless to the
# user, who cannot tell what is actually being installed. Defaults to <src>,
# so every other caller's wording is unchanged.
copy_config_once() {
  local src="$1" dest="$2" display_src="${3:-$1}" recorded current backup
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
      printf "%b %s\n" "🔍" "[DRY-RUN] Would install $dest from $display_src"
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
    printf "%b %s\n" "🔍" "[DRY-RUN] Would back up foreign $dest and install $display_src"
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

# --- JSON settings files ------------------------------------------------------
# Zed and VS Code keep their settings in a JSON file the user also edits, so
# teeup never ships one: it sets the few keys the theme and the font need and
# leaves the rest alone. jq does the edit (cli-tools and teeup-runtime install
# it); write_managed_file does the write, so DRY_RUN previews it and an
# unchanged file is left alone.
#
# Both editors read JSON with comments and trailing commas ("JSONC"), and
# Zed's own first settings file has both. jq reads neither, so the file is
# converted first by the awk program below, which walks it character by
# character outside strings: `//` and `/* */` comments are dropped and a comma
# followed only by whitespace or comments before `}` or `]` is dropped. The
# comment lines above the opening brace (Zed's header) are put back on the way
# out; a comment inside the object cannot survive jq's rewrite, so a file that
# has one is copied to <file>.teeup_backup_<timestamp> before the first write.
#
# The program runs per line with its state carried across lines, so it never
# indexes into one long string. With ENVIRON["JSONC_DETECT"] set it prints
# nothing and exits 0 when the input holds a comment, 1 when it holds none.
_JSONC_AWK='
function out(s) { if (!detect) printf "%s", s }
BEGIN { detect = (ENVIRON["JSONC_DETECT"] != ""); found = 0 }
{
  line = $0 "\n"
  n = length(line)
  for (i = 1; i <= n; i++) {
    c = substr(line, i, 1)
    if (lc) { if (c == "\n") { lc = 0; if (pc) pw = pw c; else out(c) } ; continue }
    if (bc) { if (c == "*" && substr(line, i + 1, 1) == "/") { bc = 0; i++ } ; continue }
    if (ins) {
      out(c)
      if (esc) esc = 0
      else if (c == "\\") esc = 1
      else if (c == "\"") ins = 0
      continue
    }
    if (c == "/" && substr(line, i + 1, 1) == "/") { lc = 1; found = 1; i++; continue }
    if (c == "/" && substr(line, i + 1, 1) == "*") { bc = 1; found = 1; i++; continue }
    if (c == " " || c == "\t" || c == "\r" || c == "\n") { if (pc) pw = pw c; else out(c); continue }
    if (pc) { if (c != "}" && c != "]") out(","); out(pw); pc = 0; pw = "" }
    if (c == ",") { pc = 1; continue }
    if (c == "\"") ins = 1
    out(c)
  }
}
END {
  if (pc) { out(","); out(pw) }
  if (detect) exit(found ? 0 : 1)
}
'

# json_quote <text> -> <text> as one JSON string literal, escaped by jq.
json_quote() { jq -n --arg v "$1" '$v'; }

# _json_edit <set|merge> <file> <key> <json-value>
_json_edit() {
  local op="$1" file="$2" key="$3" value="$4" header="" body="" stripped result filter backup
  if ! have jq; then
    warn "jq is not installed; cannot set $key in $file. Run: teeup install cli-tools"
    return 1
  fi
  # A settings file that is a symlink belongs to a dotfile manager, and the
  # write below (a rename onto the path) would replace the link with a copy
  # the manager no longer tracks.
  if [[ -L "$file" ]]; then
    warn "$file is a symlink; teeup does not write through it. Set it by hand: \"$key\": $value"
    return 1
  fi
  if ! jq -n --argjson v "$value" 'true' >/dev/null 2>&1; then
    warn "json_${op}_key: not a JSON value: '$value' (a string needs its quotes: '\"text\"')"
    return 1
  fi
  if [[ -f "$file" ]]; then
    # The header is every blank or `//` line before the first other line.
    header="$(awk '!body && /^[[:space:]]*(\/\/.*)?$/ { print; next } { body = 1 }' "$file")"
    body="$(awk '!body && /^[[:space:]]*(\/\/.*)?$/ { next } { body = 1; print }' "$file")"
  fi
  stripped="$(printf '%s\n' "$body" | awk "$_JSONC_AWK")"
  case "$stripped" in
    *[![:space:]]*) ;;
    *) stripped="{}" ;;
  esac
  case "$op" in
    set) filter='if type == "object" then .[$k] = $v else error("not an object") end' ;;
    merge) filter='if type == "object" and ((.[$k] // {}) | type) == "object" then .[$k] = ((.[$k] // {}) + $v) else error("not an object") end' ;;
  esac
  if ! result="$(printf '%s\n' "$stripped" | jq --arg k "$key" --argjson v "$value" "$filter" 2>/dev/null)" || [[ -z "$result" ]]; then
    warn "$file is not a JSON object jq can edit; set it by hand: \"$key\": $value"
    return 1
  fi
  if [[ "$DRY_RUN" != "true" ]] && printf '%s\n' "$body" | JSONC_DETECT=1 awk "$_JSONC_AWK"; then
    backup="${file}.teeup_backup_$(date +%Y%m%d%H%M%S)"
    cp "$file" "$backup"
    warn "Comments inside $file do not survive the edit; your previous file is at $backup"
  fi
  {
    if [[ -n "$header" ]]; then printf '%s\n' "$header"; fi
    printf '%s\n' "$result"
  } | write_managed_file "$file" "$key"
}

# json_set_key <file> <dotted.key> <json-value>
# Sets <dotted.key> in the JSON object in <file> to <json-value>, a JSON
# literal ('"Catppuccin Mocha"', 'true', '{"mode":"system"}'; json_quote makes
# one from text). The key is one literal top-level key, dots included: VS
# Code's "workbench.colorTheme" is a single key, and a nested
# {"workbench": {...}} object is not a setting VS Code reads. A missing or
# empty file starts as {}. Returns 1, the file untouched, when jq is missing,
# the file is a symlink, the value is not JSON, or the file is not a JSON
# object.
json_set_key() { _json_edit set "$1" "$2" "$3"; }

# json_merge_key <file> <key> <json-object>
# Like json_set_key, but the object already at <key> keeps the members
# <json-object> does not name (Zed's auto_install_extensions gains one entry
# and keeps the user's).
json_merge_key() { _json_edit merge "$1" "$2" "$3"; }
