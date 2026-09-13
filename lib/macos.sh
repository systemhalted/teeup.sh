#!/usr/bin/env bash
# macos.sh - the three native macOS seams teeup needs: the defaults database,
# LaunchAgents, and the light/dark appearance.
# Requires core.sh and files.sh.

_defaults_record_path() { printf '%s/defaults/%s.%s\n' "$TEEUP_STATE_DIR" "$1" "$2"; }

# Writing the record is a mutation of the machine's state dir, so it gets the
# same dry-run guard as state.sh's markers rather than going through run_cmd
# (the content is data, not a command line).
_defaults_record() {
  local record="$1" content="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would record ${record#"$TEEUP_STATE_DIR"/} as $content"
    return 0
  fi
  mkdir -p "$(dirname "$record")"
  printf '%s\n' "$content" > "$record"
}

# defaults_write <domain> <key> <type> <value>
# Records what was there before the first time teeup touches a key, so
# `teeup remove macos-defaults` can put the machine back. The record is never
# refreshed: the value teeup itself wrote is not a prior value.
# Only the first line of a prior value is kept; every key teeup writes is a
# scalar (bool, int or string), never a dict or an array.
defaults_write() {
  local domain="$1" key="$2" type="$3" value="$4" record prior
  record="$(_defaults_record_path "$domain" "$key")"
  if [[ ! -f "$record" ]]; then
    if defaults read "$domain" "$key" >/dev/null 2>&1; then
      prior="$(defaults read "$domain" "$key" 2>/dev/null | head -1)"
      _defaults_record "$record" "$type:$prior"
    else
      _defaults_record "$record" "absent"
    fi
  fi
  run_cmd defaults write "$domain" "$key" "$type" "$value"
}

# defaults_restore <domain> <key>
defaults_restore() {
  local domain="$1" key="$2" record recorded type value
  record="$(_defaults_record_path "$domain" "$key")"
  if [[ ! -f "$record" ]]; then
    log "No recorded value for $domain $key; leaving it alone."
    return 0
  fi
  recorded="$(cat "$record")"
  if [[ "$recorded" == "absent" ]]; then
    run_cmd defaults delete "$domain" "$key" || warn "Could not delete $domain $key."
  else
    type="${recorded%%:*}"
    value="${recorded#*:}"
    run_cmd defaults write "$domain" "$key" "$type" "$value"
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "%b %s\n" "🔍" "[DRY-RUN] Would clear ${record#"$TEEUP_STATE_DIR"/}"
  else
    rm -f "$record"
  fi
}

# launchagent_install <label>   (plist content on stdin)
# Always reloads, even when the plist did not change: bootout is the cheap way
# to make the agent match the file, and it is how a manually unloaded agent
# repairs itself on the next `teeup configure`.
launchagent_install() {
  local label="$1" dir plist uid
  dir="$HOME/Library/LaunchAgents"
  plist="$dir/$label.plist"
  [[ -d "$dir" ]] || run_cmd mkdir -p "$dir"
  write_managed_file "$plist" "LaunchAgent $label"
  uid="$(id -u)"
  # bootout exits non-zero when the agent is not loaded. That is the normal
  # first-install case, so the failure is ignored. Do not redirect run_cmd:
  # its dry-run preview goes to stdout and a redirection would hide it.
  run_cmd launchctl bootout "gui/$uid" "$plist" || true
  # launchd often refuses an immediate bootstrap right after a bootout with
  # "Bootstrap failed: 5" (the old instance has not finished tearing down
  # yet), so a single retry after a short pause is normal, not a bug.
  run_cmd launchctl bootstrap "gui/$uid" "$plist" ||
    { sleep 1; run_cmd launchctl bootstrap "gui/$uid" "$plist"; } ||
    warn "Could not load $label; run: launchctl bootstrap gui/$uid $plist"
}

# appearance -> dark | light
# `defaults read -g AppleInterfaceStyle` prints "Dark" in dark mode and exits 1
# in light mode, which is also what plan 2a's zsh layer uses for
# TEEUP_APPEARANCE. Same exact-match rule in both places, so a script and a
# shell agree.
appearance() {
  local style
  if style="$(defaults read -g AppleInterfaceStyle 2>/dev/null)"; then
    [[ "$style" == "Dark" ]] && { printf 'dark\n'; return 0; }
  fi
  printf 'light\n'
}
