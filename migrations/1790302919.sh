#!/usr/bin/env bash
# Deliver the new AeroSpace defaults to machines that already installed the
# capability, and retire the local.toml that used to carry machine overrides.
#
# aerospace.toml is copy-once, like wezterm's and starship's: configure
# installs it and never touches it again. That means a machine which installed
# aerospace before this change keeps its old file forever -- "Already
# installed" is the correct answer to copy_config_once, and nothing else in a
# normal `teeup update` ever revisits it. migration_refresh is how a changed
# shipped config actually reaches those machines: it replaces the copies
# nobody edited and leaves an edited one alone, which is the whole point of
# the stock-checksum rule.
#
# What changed in the shipped file: the tuned defaults (zero gaps,
# focus-follows-mouse off, persistent workspaces, config-version 2) and the
# commented-out [workspace-to-monitor-force-assignment] example that local.toml
# used to hold.
#
# The cap_exists guard matters: several `teeup update` tests run migrations
# against a fixture capability tree with no aerospace, where migration_refresh
# would error.
#
# The new file says config-version = 2, which AeroSpace reads from
# 0.20.0-Beta on; 0.19.x rejects the key and loads nothing. `teeup update`
# runs migrations after the upgrades, but a failed cask upgrade is only a
# warning there, and a stopped AeroSpace skips the reload-config check -- so
# the version the binary reports is the one fact this migration can trust.
# Too old, or unreadable, and it stops unapplied, so the next `teeup update`
# (after the upgrade has gone through) tries again. No CLI and no app is a
# machine with nothing to break: migration_refresh decides from the markers.
# The gate asks only where migration_refresh would write -- installed, not
# skipped, not not-applicable -- so a capability the owner opted out of with
# TEEUP_SKIP can never block `teeup update`.
AEROSPACE_MIN_VERSION="0.20.0"
aerospace_version_ok() {
  local have_v="$1" need_v="$2" a b i
  local IFS=.
  # shellcheck disable=SC2206 # splitting on dots is the point
  a=($have_v)
  # shellcheck disable=SC2206
  b=($need_v)
  # 10#: a leading zero is otherwise octal, and 09 is an arithmetic error
  # that made both tests false and fell through to "new enough".
  for i in 0 1 2; do
    if (( 10#${a[$i]:-0} > 10#${b[$i]:-0} )); then return 0; fi
    if (( 10#${a[$i]:-0} < 10#${b[$i]:-0} )); then return 1; fi
  done
  return 0
}

# aerospace_installed_version -> the version, "" when it cannot be read, or
# "none" when there is no AeroSpace here to read a config at all.
# The CLI first. Failing that, the app itself: the cask links the CLI
# separately, so a stripped PATH or a hand-installed app has no `aerospace`
# to ask, and it is the app that reads the config anyway.
aerospace_installed_version() {
  local app="" dir raw=""
  # The places app_installed (lib/lazy.sh) looks, in its order.
  for dir in "${TEEUP_APPS_DIR:-/Applications}" "$HOME/Applications"; do
    [[ -d "$dir/AeroSpace.app" ]] && { app="$dir/AeroSpace.app"; break; }
  done
  if [[ -z "$app" && "$(pkg_backend)" == "macports" && -d "$(macports_apps_dir)/AeroSpace.app" ]]; then
    app="$(macports_apps_dir)/AeroSpace.app"
  fi
  if have aerospace; then
    # "aerospace CLI client version: 0.20.0-Beta 1a2b3c4"
    raw="$(aerospace --version 2>/dev/null | sed -n 's/^aerospace CLI client version: //p' | head -1 || true)"
  elif [[ -n "$app" ]]; then
    raw="$(defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
  else
    echo none
    return 0
  fi
  # 0.20.0-Beta -> 0.20.0
  printf '%s\n' "$raw" | sed -n 's/^\([0-9][0-9]*\.[0-9][0-9]*\(\.[0-9][0-9]*\)*\).*/\1/p' | head -1 || true
}

# aerospace_refresh_would_write -> 0 when migration_refresh would put the new
# file in place. Mirrors capabilities/aerospace/configure and
# refresh_if_pristine: a ~/.aerospace.toml means configure installs nothing;
# a missing destination is installed; a pristine one that differs from the
# shipped file is replaced; an edited one is left alone. Where nothing would
# be written, an old AeroSpace has nothing to choke on, and blocking every
# later migration and `teeup update` over it would be all cost.
aerospace_refresh_would_write() {
  local dest src
  dest="$(user_config_dir)/aerospace/aerospace.toml"
  src="$TEEUP_PATH/capabilities/aerospace/config/aerospace/aerospace.toml"
  [[ -e "$HOME/.aerospace.toml" ]] && return 1
  [[ -e "$dest" || -L "$dest" ]] || return 0
  config_is_pristine "$dest" && ! cmp -s "$src" "$dest"
}

if cap_exists aerospace; then
  if state_done check cap-aerospace && ! cap_skipped aerospace &&
    ! state_na check cap-aerospace && aerospace_refresh_would_write; then
    aerospace_v="$(aerospace_installed_version)"
    if [[ -z "$aerospace_v" ]]; then
      err "Could not read the installed AeroSpace's version, so its new config (which needs $AEROSPACE_MIN_VERSION or later) was not installed. Check that AeroSpace runs, then run: teeup update"
      exit 1
    fi
    if [[ "$aerospace_v" != "none" ]] && ! aerospace_version_ok "$aerospace_v" "$AEROSPACE_MIN_VERSION"; then
      err "AeroSpace $aerospace_v is installed, but its new config needs $AEROSPACE_MIN_VERSION or later, so the config was left as it is. Upgrade AeroSpace (brew upgrade --cask aerospace), then run: teeup update"
      exit 1
    fi
  fi
  migration_refresh aerospace
fi

# local.toml is no longer read by anything. It is the user's file, so it is
# not deleted -- only named, once, so nobody keeps editing a file that stopped
# having any effect. An untouched copy is still teeup's shipped stub and worth
# nothing to keep, but telling them apart needs the stock record, and saying
# one honest sentence is better than a wrong deletion.
AEROSPACE_LOCAL_TOML="$(user_config_dir)/aerospace/local.toml"
if [[ -e "$AEROSPACE_LOCAL_TOML" ]]; then
  log "$AEROSPACE_LOCAL_TOML is no longer read: AeroSpace takes one config file, so machine-specific settings now go straight into $(user_config_dir)/aerospace/aerospace.toml. Move anything you set there across, then delete it."
fi
