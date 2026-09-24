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

# Returns non-zero when the record cannot be written (a state directory that
# is not writable, say). The caller's own write has usually succeeded by then,
# so this warns rather than failing the write: what is lost is teeup's memory
# of what it shipped, which makes the file read as edited from then on -- the
# safe direction (teeup leaves it alone), but the user should hear why. The
# raw shell error is swallowed so the warning is the only thing they see.
stock_record() {
  local dest="$1" sha="$2" record
  record="$(_stock_record_path "$dest")"
  mkdir -p "$(dirname "$record")" 2>/dev/null || true
  # 2>/dev/null comes BEFORE the output redirect: the shell applies
  # redirections left to right, so a `> "$record"` that fails to open would
  # otherwise print its raw "Permission denied" before stderr was silenced.
  if ! printf '%s\n' "$sha" 2>/dev/null > "$record"; then
    warn "Could not record the shipped checksum at $record; teeup will treat $dest as edited and leave it alone from now on."
    return 1
  fi
}

stock_sha() {
  local record
  record="$(_stock_record_path "$1")"
  [[ -f "$record" ]] && cat "$record"
}

# config_is_pristine <dest>
# True when <dest> is a regular file with a stock record and still hashes to
# it: every byte is what teeup last wrote there (a copy, a reset, a refresh or
# a managed-region rewrite) and nobody has edited it since. This is the test
# behind the stock-checksum rule (spec section 9). A symlink is never
# pristine: no stock record can belong to one.
config_is_pristine() {
  local dest="$1" recorded
  [[ -f "$dest" && ! -L "$dest" ]] || return 1
  recorded="$(stock_sha "$dest" || true)"
  [[ -n "$recorded" && "$recorded" == "$(file_sha "$dest")" ]]
}

# write_config_region <dest> <label>   (the whole new file on stdin)
# Rewrites a user-owned config file whose teeup-managed region changed (the
# starship palette block). The write goes through write_managed_file. When the
# file was pristine before the write, the new content becomes its stock
# record, so teeup's own rewrite never makes the file read as edited: the next
# configure still says "Already installed" and a later migration may still
# refresh it. A file the user has edited keeps its old record and keeps
# reading as edited. A symlink is refused (warns, returns 1, writes nothing):
# the rename inside write_managed_file would replace a dotfile manager's link
# with a copy it no longer tracks.
write_config_region() {
  local dest="$1" label="$2" pristine=false tmp rc=0
  if [[ -L "$dest" ]]; then
    warn "$dest is a symlink; teeup does not write through it, so its $label was not updated."
    cat >/dev/null
    return 1
  fi
  if config_is_pristine "$dest"; then pristine=true; fi
  if [[ "$DRY_RUN" == "true" ]]; then
    write_managed_file "$dest" "$label"
    return 0
  fi
  tmp="$(mktemp)"
  cat > "$tmp"
  write_managed_file "$dest" "$label" < "$tmp" || rc=$?
  rm -f "$tmp"
  # stock_record warns for itself; a failed record does not unwrite the file,
  # so the caller is told the write succeeded.
  if [[ "$rc" -eq 0 && "$pristine" == "true" ]]; then
    stock_record "$dest" "$(file_sha "$dest")" || true
  fi
  return "$rc"
}

# refresh_if_pristine <src> <dest> [display_src]
# The stock-checksum rule, as migrations use it: a <dest> that is still
# pristine is replaced with the shipped <src> and its record follows; a
# missing <dest> is installed with copy_config_once. A <dest> the user has
# edited (or one teeup holds no record of) is left alone with a log line and
# the function returns 1, so the migration can patch that file minimally
# instead, after backup_copy. <display_src> names the file in the DRY-RUN
# message when it differs from <src> -- see copy_config_once.
# Three outcomes, three statuses, because the caller has to tell them apart:
#   0  refreshed, installed, or already current
#   1  the user edited it, so it was deliberately left alone (not a failure)
#   2  teeup tried and could not write it
# A single non-zero status would make a migration treat a failed write as
# "the user edited this file" and mark itself applied over the top of it.
refresh_if_pristine() {
  local src="$1" dest="$2" display_src="${3:-$1}" refresh_tmp
  if [[ ! -e "$dest" && ! -L "$dest" ]]; then
    copy_config_once "$src" "$dest" "$display_src" || return 2
    return 0
  fi
  if ! config_is_pristine "$dest"; then
    log "Keeping your edited $dest; it was not refreshed."
    return 1
  fi
  if cmp -s "$src" "$dest"; then
    log "Already at the shipped version: $dest"
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would refresh $dest from $display_src"
    return 0
  fi
  # A file the user made read-only is left alone, the way write_managed_file
  # leaves one: the rename below would replace it regardless, because a rename
  # needs the directory's permission and not the file's, so the check has to
  # be explicit or the atomicity below would quietly undo that rule.
  if [[ ! -w "$dest" ]]; then
    warn "$dest is not writable, so it was not refreshed from $display_src."
    return 2
  fi
  # Into a temp file beside the destination, then rename: a `cp` straight over
  # the live file truncates it first, so a disk that fills mid-copy would
  # leave a half-written config where a working one used to be. `mv` within
  # the same directory is atomic, so the file is either the old one or the new
  # one and never something in between. Nothing here holds a backup -- the
  # file is pristine by definition at this point -- which is exactly why the
  # copy must not be able to destroy it.
  refresh_tmp="$(mktemp "$(dirname "$dest")/.teeup_refresh.XXXXXX" 2>/dev/null)" || {
    warn "Could not write in $(dirname "$dest"), so $dest was not refreshed from $display_src."
    return 2
  }
  if ! cp "$src" "$refresh_tmp" 2>/dev/null || ! mv "$refresh_tmp" "$dest" 2>/dev/null; then
    rm -f "$refresh_tmp"
    warn "Could not write $dest, so it was not refreshed from $display_src."
    return 2
  fi
  stock_record "$dest" "$(file_sha "$src")" || true
  ok "Refreshed $dest (you had not edited it)"
}

# _backup_name <path>  -> prints a backup path nothing holds yet
# Both backup_copy and backup_target name a backup <path>.teeup_backup_<ts>,
# to the second. A single `teeup migrate legacy` run can back the same file
# up several times inside one second (legacy wiring, then prompt wiring, then
# chezmoi), and a second call landing on the name the first just used would
# silently overwrite it. When that name is already taken, this appends -1,
# -2, ... until it finds one nothing holds, so every backup from the same run
# survives. Bash-3.2-safe: a counter and plain concatenation, no ${var//}.
_backup_name() {
  local target="$1" base n
  base="${target}.teeup_backup_$(date +%Y%m%d%H%M%S)"
  if [[ ! -e "$base" ]]; then
    printf '%s\n' "$base"
    return 0
  fi
  n=1
  while [[ -e "${base}-${n}" ]]; do
    n=$((n + 1))
  done
  printf '%s\n' "${base}-${n}"
}

# backup_copy <path>  -> prints the backup path on stdout
# Like backup_target, but copies: the file stays in place for a migration to
# patch, and the copy keeps what it held before.
backup_copy() {
  local target="$1" backup
  backup="$(_backup_name "$target")"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would copy $target to $backup" >&2
  else
    # The `cp` is checked, and "Copied" is only said when it worked. Every
    # caller goes on to rewrite <target> in place, so a claimed backup that
    # never happened is the worst thing this function can produce -- and
    # `set -e` cannot catch it, because backup_copy is always called inside
    # `$(...)`, where a non-zero status is the assignment's, not the shell's.
    # backup_target carries the same guard for the same reason.
    if ! cp -p "$target" "$backup" 2>/dev/null; then
      warn "Could not copy $target to $backup; leaving it alone." >&2
      return 1
    fi
    ok "Copied $target to $backup" >&2
  fi
  printf '%s\n' "$backup"
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
  local file="$1" label="$2" dir tmp mode=""
  dir="$(dirname "$file")"
  # shellcheck disable=SC2034  # read by callers (capabilities/git/configure)
  WRITE_MANAGED_FILE_CHANGED=true
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would write $file ($label)"
    cat >/dev/null
    return 0
  fi
  [[ -d "$dir" ]] || mkdir -p "$dir" 2>/dev/null || true
  tmp="$(mktemp)"
  cat > "$tmp"
  if [[ -f "$file" ]] && cmp -s "$tmp" "$file"; then
    rm -f "$tmp"
    # shellcheck disable=SC2034  # read by callers (capabilities/git/configure)
    WRITE_MANAGED_FILE_CHANGED=false
    log "Already current: $file"
    return 0
  fi
  # A file that exists but is not writable (mode 0444, say) signals intent
  # the way the symlink above does (M11): `mv` onto the path would still
  # succeed (only the directory's permissions govern a rename) and silently
  # rewrite it, so this is checked explicitly rather than left to `mv`.
  # A symlink is left alone outright: `mv` onto the path would replace the
  # link with a regular file, silently detaching a config someone keeps in a
  # dotfiles repo (chezmoi, stow, a bare git checkout) and leaving teeup's
  # copy where their managed file used to be. The caller is told, and decides.
  if [[ -L "$file" ]]; then
    rm -f "$tmp"
    # shellcheck disable=SC2034  # read by callers (capabilities/git/configure)
    WRITE_MANAGED_FILE_CHANGED=false
    warn "$file is a symlink; teeup does not write through it. Point it elsewhere, or set it by hand: $label"
    return 1
  fi
  if [[ -e "$file" && ! -w "$file" ]]; then
    rm -f "$tmp"
    # shellcheck disable=SC2034  # read by callers (capabilities/git/configure)
    WRITE_MANAGED_FILE_CHANGED=false
    warn "$file is not writable; teeup leaves it alone. Set it by hand: $label"
    return 1
  fi
  # A read-only directory with no file yet to catch by the check above (a
  # read-only ~/.local/bin the mise wrapper or a shim would land in, say)
  # would otherwise reach `mv` below and fail with a raw, teeup-less error
  # (M1): mkdir -p above cannot have created it either in that case.
  if [[ ! -d "$dir" || ! -w "$dir" ]]; then
    rm -f "$tmp"
    # shellcheck disable=SC2034  # read by callers (capabilities/git/configure)
    WRITE_MANAGED_FILE_CHANGED=false
    warn "$dir is not writable; teeup leaves $file alone. Set it by hand: $label"
    return 1
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
  backup="$(_backup_name "$target")"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would back up $target to $backup" >&2
  else
    # The `mv` is checked, and "Backed up" is only said when it worked. A
    # read-only parent directory fails the rename, and every caller here goes
    # on to overwrite <target> in place: the claim of a backup, followed by
    # the destruction of the file it claimed to have saved, is the worst
    # outcome this file can produce. `set -e` does not catch it either --
    # backup_target is always called inside `$(...)`, where a non-zero status
    # is the assignment's, not the shell's.
    if ! mv "$target" "$backup" 2>/dev/null; then
      warn "Could not back up $target to $backup; leaving it alone." >&2
      return 1
    fi
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
  # A migration refreshing this capability's files (migration_refresh sets
  # TEEUP_REFRESH to its name) gets the stock-checksum rule instead: a file
  # still pristine is replaced, an edited one is kept. The name must match
  # TEEUP_CAP, so a configure that re-runs another capability's (ssh re-runs
  # git's) leaves that capability's files to the normal rule. The prefix
  # assignment clears the variable for the nested call, which may come back
  # here for a missing file.
  if [[ -n "${TEEUP_REFRESH:-}" && "$TEEUP_REFRESH" == "${TEEUP_CAP:-}" ]]; then
    local refresh_rc=0
    TEEUP_REFRESH="" refresh_if_pristine "$src" "$dest" "$display_src" || refresh_rc=$?
    # 1 is the user's edit being respected, which is a normal outcome of a
    # migration refresh. 2 is teeup failing to write, which the migration has
    # to hear about: swallowing it marks the migration applied while the old
    # file is still in place.
    [[ "$refresh_rc" -eq 2 ]] && return 1
    return 0
  fi
  # `teeup reset <capability>` sets TEEUP_RESET to its name the same way: each
  # file goes back to the shipped version through refresh_config (backup,
  # replace, diff, the backup dropped when nothing changed). Because this
  # happens inside the capability's own configure, a file configure renders
  # is reset to the rendered version, never to the raw template.
  if [[ -n "${TEEUP_RESET:-}" && "$TEEUP_RESET" == "${TEEUP_CAP:-}" ]]; then
    # A local.* file is the one teeup promises never to touch again: it holds
    # the machine's own settings (aerospace's monitor assignment, wezterm's
    # passthrough, the zsh and emacs local files). Reset exists to put teeup's
    # own files back, and someone reaching for it because the managed config
    # is broken is not asking to lose the overrides they wrote by hand.
    case "${dest##*/}" in
      local.*)
        log "Keeping your $dest; teeup reset leaves the local override file alone."
        return 0
        ;;
    esac
    TEEUP_RESET="" refresh_config "$src" "$dest" "$display_src"
    return $?
  fi
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
    stock_record "$dest" "$(file_sha "$src")" || true
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
  # No backup, no overwrite: the user's file is what is being protected.
  if ! backup="$(backup_target "$dest")"; then
    warn "$dest was left as it is, so $display_src was not installed."
    return 1
  fi
  if ! cp "$src" "$dest"; then
    warn "Could not write $dest; your previous file is at $backup."
    return 1
  fi
  stock_record "$dest" "$(file_sha "$src")" || true
  ok "Installed $dest (your previous file is at $backup)"
  # A backed-up dangling symlink has nothing to diff; diff says so on stderr
  # and the `|| true` keeps that from failing the capability.
  echo "Lines from your previous file that are not in the teeup version:"
  diff "$backup" "$dest" || true
}

# refresh_config <src> <dest> [display_src]
# Backup, replace with the shipped file, print the diff, drop the backup if
# nothing changed. Omarchy's refresh-config. <display_src> names the file in
# the DRY-RUN message when it differs from <src> -- a capability that renders
# before copying (zsh, git, ssh) passes a temp file as <src>, which the
# message would otherwise name instead of the shipped file the user asked
# `teeup reset` to restore -- see copy_config_once. A symlinked or
# non-writable <dest> is refused outright (warns, returns 1, touches
# nothing): the same protection write_managed_file gives every other managed
# write, checked here too because this function writes through `cp` instead.
refresh_config() {
  local src="$1" dest="$2" display_src="${3:-$1}" backup
  # The symlink test comes first because `-e` follows the link: a DANGLING
  # symlink answers "does not exist", and the install path below would then
  # replace the link itself with a regular file -- the very thing the guard
  # exists to prevent (I1).
  if [[ -L "$dest" ]]; then
    warn "$dest is a symlink; teeup does not write through it, so it was not reset. Point it elsewhere, or reset it by hand: $display_src"
    return 1
  fi
  if [[ ! -e "$dest" ]]; then
    copy_config_once "$src" "$dest" "$display_src"
    return $?
  fi
  # A directory where a config file belongs: every test below passes for one,
  # and the user's whole directory would be renamed out of the way and called
  # a backup (I2). Whatever put it there, teeup did not, and moving it is not
  # this function's call to make.
  if [[ -d "$dest" ]]; then
    warn "$dest is a directory, not a config file; teeup left it alone. Move it aside yourself, then reset $display_src."
    return 1
  fi
  if [[ ! -w "$dest" ]]; then
    warn "$dest is not writable; teeup leaves it alone, so it was not reset. Set it by hand: $display_src"
    return 1
  fi
  # The directory, not just the file: a rename needs the directory's
  # permission, so a writable file in a read-only directory cannot be backed
  # up -- and overwriting it in place without a backup is exactly what must
  # not happen here.
  if [[ ! -w "$(dirname "$dest")" ]]; then
    warn "$(dirname "$dest") is not writable, so $dest cannot be backed up and was not reset. Reset it by hand: $display_src"
    return 1
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would reset $dest to $display_src"
    return 0
  fi
  if ! backup="$(backup_target "$dest")"; then
    warn "$dest was not reset, so your version is still there."
    return 1
  fi
  if ! cp "$src" "$dest"; then
    warn "Could not write $dest; your version is at $backup."
    return 1
  fi
  stock_record "$dest" "$(file_sha "$src")" || true
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

# --- TOML local-override merge -------------------------------------------------
# toml_merge_local <base> <local>   (merged file on stdout)
# Merges a machine's local.toml onto teeup's shipped base TOML and prints the
# result. Used where a config format has no include mechanism of its own
# (AeroSpace, so far), so a per-machine override file has to be folded into
# the shipped one at configure time rather than just sitting alongside it.
# Three rules, applied only to what <local> actually sets -- everything else
# in it (comments, its own commented-out examples) is inert:
#   - a [table] in <local> replaces <base>'s table of the same name entirely
#     (redefining [gaps] gives you your gaps, not a mix of the two);
#   - a bare top-level `key = value` in <local> replaces just that key;
#   - anything <local> sets that <base> does not mention is appended (a
#     top-level key ahead of <base>'s first [table], a whole new [table] at
#     the end).
# AWK, not a shell loop: portable to the BSD awk bash-3.2 boxes ship, and a
# TOML table is naturally the line-oriented block one pass can gather.
# FNR == NR is true only while reading the first file (<base>); once the
# second file (<local>) starts, FNR resets but NR keeps counting, so it goes
# false for the rest of the run -- the standard awk idiom for "two files, two
# different passes" without needing gawk's FILENAME/ARGIND.
toml_merge_local() {
  awk '
    # TOML allows whitespace around a table header and around a key, and a
    # file edited on another machine can arrive with CRLF line endings. A
    # header this does not recognise is swallowed into the previous table,
    # which produces a duplicate table declaration no TOML parser accepts --
    # and a local.toml override that silently never takes effect.
    function trim(line,   s) {
      s = line
      sub(/\r$/, "", s)
      sub(/^[ \t]+/, "", s)
      sub(/[ \t]+$/, "", s)
      return s
    }
    # [table] and [[array-of-table]] both start a section. An unrecognised
    # header is swallowed into the previous section, which produces a
    # duplicate declaration no parser accepts -- and for [[...]] it would also
    # promote the keys of that entry to the root and collapse repeated entries
    # into one. An array-of-table name keeps its brackets, so "[[x]]" and
    # "[x]" can never collide, and every [[x]] entry accumulates under that
    # one name so repeats survive in order. A table header right after a
    # "[[x]]" entry whose own dotted name starts with "x." is a subtable of
    # that entry, not a section of its own -- TOML attaches it to whichever
    # array entry was opened most recently ("[[on-window-detected]]" then
    # "[on-window-detected.if]"), so grouping by header name alone moves
    # every "[[on-window-detected]]" ahead of every "[on-window-detected.if]"
    # and ends up declaring the subtable of the last entry twice. Each
    # subtable header instead stays folded into the entry bucket it followed,
    # in source order.
    # A header may carry a trailing comment ("[gaps] # laptop"). The comment is
    # stripped for detection and for the name only -- never for a key line,
    # where a "#" inside a quoted value is part of the value, not a comment.
    function header_text(line,   s) {
      s = trim(line)
      if (substr(s, 1, 1) != "[") return s
      sub(/\][ \t]*#.*$/, "]", s)
      return trim(s)
    }
    function is_header(line,   s) {
      s = header_text(line)
      return s ~ /^\[\[[^]]+\]\]$/ || s ~ /^\[[^]]+\]$/
    }
    # canon_path(path) -- a dotted TOML path with the whitespace trimmed off
    # every segment. "[ gaps ]" and "gaps . inner" name the same paths as
    # "gaps" and "gaps.inner"; comparing the raw header or key text instead
    # of this canonical form misses that, and both survive into the merged
    # file as two declarations of the same path.
    function canon_path(path,    n, i, parts, out) {
      n = split(path, parts, ".")
      out = ""
      for (i = 1; i <= n; i++) {
        gsub(/^[ \t]+/, "", parts[i])
        gsub(/[ \t]+$/, "", parts[i])
        out = (i == 1) ? parts[i] : out "." parts[i]
      }
      return out
    }
    # is_ancestor(anc, path) -- true when anc and path name the same TOML
    # path, or anc names a table that path lives inside. A dotted root key
    # ("gaps.inner.horizontal = 12") and a table header ("[gaps]") can both
    # claim the "gaps" path; this is the test for whether two declarations,
    # one from each shape, collide.
    function is_ancestor(anc, path) {
      return (anc == path) || (index(path, anc ".") == 1)
    }
    function header_name(line,   s) {
      s = header_text(line)
      if (s ~ /^\[\[[^]]+\]\]$/) {
        s = substr(s, 3, length(s) - 4)
        return "[[" canon_path(s) "]]"
      }
      sub(/^\[/, "", s)
      sub(/\]$/, "", s)
      return canon_path(s)
    }
    function is_kv(line) { return trim(line) ~ /^[A-Za-z0-9_.-]+[ \t]*=/ }
    function kv_key(line,   i, s) {
      s = trim(line)
      i = index(s, "=")
      s = substr(s, 1, i - 1)
      gsub(/[ \t]+$/, "", s)
      return canon_path(s)
    }
    FNR == NR {
      # Pass 1: the shipped base. bsec == "" is the root, before any [table].
      if (is_header($0)) {
        bname = header_name($0)
        if (bname ~ /^\[\[/) {
          barrname = substr(bname, 3, length(bname) - 4)
          bsec = bname
        } else if (barrname != "" && is_ancestor(barrname, bname)) {
          # A subtable of the array entry still open: bsec is left as the
          # entry bucket it belongs to, so this header lands there too.
        } else {
          barrname = ""
          bsec = bname
        }
        if (!(bsec in bseen)) { bseen[bsec] = 1; border[++bcount] = bsec }
        bblock[bsec] = (bsec in bblock) ? bblock[bsec] "\n" $0 : $0
      } else if (bsec == "") {
        rootn++
        rootline[rootn] = $0
        if (is_kv($0)) rootkey[kv_key($0)] = rootn
      } else {
        bblock[bsec] = bblock[bsec] "\n" $0
      }
      next
    }
    {
      # Pass 2: the machine local.toml.
      if (is_header($0)) {
        lrootopen = ""
        lname = header_name($0)
        if (lname ~ /^\[\[/) {
          larrname = substr(lname, 3, length(lname) - 4)
          lsec = lname
        } else if (larrname != "" && is_ancestor(larrname, lname)) {
          # Same grouping as pass 1, above.
        } else {
          larrname = ""
          lsec = lname
        }
        if (!(lsec in lseen)) { lseen[lsec] = 1; lorder[++lcount] = lsec }
        lblock[lsec] = (lsec in lblock) ? lblock[lsec] "\n" $0 : $0
      } else if (lsec == "") {
        if (is_kv($0)) {
          k = kv_key($0)
          if (!(k in lrootseen)) { lrootseen[k] = 1; lrootorder[++lrootn] = k }
          lrootval[k] = $0
          lrootopen = k
        } else if (lrootopen != "" && trim($0) != "") {
          # A value written across several lines (`after-startup-command = [`
          # and the entries under it). Keeping only the first line would emit
          # an unterminated value that AeroSpace cannot load.
          lrootval[lrootopen] = lrootval[lrootopen] "\n" $0
        }
      } else {
        lblock[lsec] = lblock[lsec] "\n" $0
      }
      next
    }
    # local_table_claims(path) -- true when local.toml declares a [table]
    # (never an [[array]]: an array entry names one item, not a path other
    # declarations can live under) whose canonical name is path itself or an
    # ancestor of it. Drops a base root key a local table header now also
    # names -- the shipped base has "focus-follows-mouse.enabled = false" at
    # its root, and a local "[focus-follows-mouse]" claims that same path,
    # so keeping both declares it twice.
    function local_table_claims(path,    i, name) {
      for (i = 1; i <= lcount; i++) {
        name = lorder[i]
        if (name ~ /^\[\[/) continue
        if (is_ancestor(name, path)) return 1
      }
      return 0
    }
    # local_rootkey_claims(path) -- the inverse of local_table_claims: true
    # when local.toml sets a bare root key whose canonical path is path
    # itself or a descendant of it. Drops a whole base [table] a local root
    # key now reaches into -- a local "gaps.inner.horizontal = 12" at the
    # root claims the same path as the base "[gaps]" table does.
    function local_rootkey_claims(path,    i) {
      for (i = 1; i <= lrootn; i++) {
        if (is_ancestor(path, lrootorder[i])) return 1
      }
      return 0
    }
    END {
      # Root: base lines, with any locally-overridden key swapped in place,
      # and a base key a local [table] now names left out entirely.
      for (i = 1; i <= rootn; i++) {
        line = rootline[i]
        if (is_kv(line)) {
          k = kv_key(line)
          if (k in lrootval) { print lrootval[k]; continue }
          if (local_table_claims(k)) continue
        }
        print line
      }
      # Root keys local.toml sets that the base never mentioned: appended, in
      # local order, still ahead of the first [table] printed below.
      for (i = 1; i <= lrootn; i++) {
        k = lrootorder[i]
        if (!(k in rootkey)) print lrootval[k]
      }
      # Every base table, local.tomls own version of it when it set one, or
      # left out entirely when a local root key already claims that path.
      for (i = 1; i <= bcount; i++) {
        name = border[i]
        if (name in lblock) print lblock[name]
        else if (name !~ /^\[\[/ && local_rootkey_claims(name)) continue
        else print bblock[name]
      }
      # Tables only local.toml defines: appended, in local order.
      for (i = 1; i <= lcount; i++) {
        name = lorder[i]
        if (!(name in bseen)) print lblock[name]
      }
    }
  ' "$1" "$2"
}

# aerospace_config_ok <dest> <candidate>
# The merge above is hand-written awk, not a TOML parser, and three rounds of
# review have already found eight ways it can get a real local.toml wrong --
# this is the backstop for the ones still to be found. AeroSpace can check a
# config itself (`aerospace reload-config --dry-run`, verified against its
# own command reference), but its CLI has no way to point that check at an
# arbitrary file: reload-config always re-reads whatever is at <dest>, the
# resolved config location. So this stages <candidate> there just long
# enough to ask, then puts <dest> back exactly as it was -- present or
# absent, byte for byte -- using the same mktemp-then-mv swap the rest of
# this file uses, so <dest> is never observably anything but its old content
# or the candidate. --dry-run only checks; AeroSpace's reference is explicit
# that it never applies what it finds, so the brief window where <dest> holds
# an unvalidated candidate cannot make AeroSpace act on it.
# Returns 0 when AeroSpace accepts <candidate>, or when there is no
# `aerospace` binary to ask (a fresh Mac before the cask lands, a MacPorts
# machine, the Linux test harness) -- validation is skipped then, not
# claimed. Returns 1, with AeroSpace's own error on stdout and <dest>
# restored, when AeroSpace rejects it.
aerospace_config_ok() {
  local dest="$1" candidate="$2" dir stage saved="" had_dest=false out rc=0
  have aerospace || return 0
  dir="$(dirname "$dest")"
  if [[ -e "$dest" || -L "$dest" ]]; then
    had_dest=true
    saved="$(mktemp "$dir/.teeup_validate_old.XXXXXX" 2>/dev/null)" || {
      warn "Could not stage a validation copy of $dest; skipping AeroSpace's own config check."
      return 0
    }
    if ! cp -p "$dest" "$saved" 2>/dev/null; then
      warn "Could not stage a validation copy of $dest; skipping AeroSpace's own config check."
      rm -f "$saved"
      return 0
    fi
  fi
  stage="$(mktemp "$dir/.teeup_validate_new.XXXXXX" 2>/dev/null)" || {
    warn "Could not stage $dest for AeroSpace's own config check; skipping it."
    rm -f "$saved"
    return 0
  }
  if ! cp "$candidate" "$stage" 2>/dev/null || ! mv "$stage" "$dest" 2>/dev/null; then
    rm -f "$stage"
    warn "Could not stage $dest for AeroSpace's own config check; skipping it."
    rm -f "$saved"
    return 0
  fi
  out="$(aerospace reload-config --dry-run --no-gui 2>&1)" || rc=$?
  if [[ "$had_dest" == "true" ]]; then
    # mv within the same directory should never actually fail here -- saved
    # and dest are two files this function just made in the same place --
    # but under bash -eu a bare "mv || cp" whose cp also failed would be a
    # simple command that exits the whole script, leaving the unvalidated
    # candidate in place at dest. The if/elif keeps that possibility, however
    # remote, from ever doing that.
    if mv "$saved" "$dest" 2>/dev/null; then
      rm -f "$saved"
    elif cp -p "$saved" "$dest" 2>/dev/null; then
      rm -f "$saved"
    else
      warn "Could not restore $dest after checking it with AeroSpace; your original is saved at $saved."
    fi
  else
    rm -f "$dest"
  fi
  if [[ $rc -ne 0 ]]; then
    printf '%s\n' "$out"
    return 1
  fi
  return 0
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
#
# Two byte-level things this does not round-trip, both benign for a Zed/VS
# Code settings file (M7, M10): a raw NUL byte is silently dropped (bash's
# own command substitution already drops it with "ignored null byte in
# input" before awk ever sees it, and a file with one is not valid JSON
# anyway), and a UTF-8 BOM at the start of the file is silently stripped
# (jq 1.7+ already skips a leading BOM when reading, so the rewrite below
# simply never puts one back).
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
# Every current caller already checks `have jq` first (M1), but this guard
# keeps a caller that forgot it from getting bash's raw
# "jq: command not found" and an empty value instead of a warning.
json_quote() {
  if ! have jq; then
    warn "jq is not installed; cannot quote a JSON value. Run: teeup install cli-tools"
    return 1
  fi
  jq -n --arg v "$1" '$v'
}

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
  if printf '%s\n' "$body" | JSONC_DETECT=1 awk "$_JSONC_AWK"; then
    if [[ "$DRY_RUN" != "true" ]]; then
      backup="${file}.teeup_backup_$(date +%Y%m%d%H%M%S)"
      cp "$file" "$backup"
      warn "Comments inside $file do not survive the edit; your previous file is at $backup"
    else
      # M2: a dry run previews the write below but must still say the
      # comments are about to go, not just that a write would happen.
      warn "Comments inside $file do not survive the edit; would back up your previous file first"
    fi
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
