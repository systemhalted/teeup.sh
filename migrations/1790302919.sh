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
# (after the upgrade has gone through) tries again. No binary at all is a
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
  for i in 0 1 2; do
    if [[ "${a[$i]:-0}" -gt "${b[$i]:-0}" ]]; then return 0; fi
    if [[ "${a[$i]:-0}" -lt "${b[$i]:-0}" ]]; then return 1; fi
  done
  return 0
}
if cap_exists aerospace; then
  if have aerospace && state_done check cap-aerospace && ! cap_skipped aerospace &&
    ! state_na check cap-aerospace; then
    # "aerospace CLI client version: 0.20.0-Beta 1a2b3c4" -> 0.20.0
    aerospace_v="$(aerospace --version 2>/dev/null |
      sed -n 's/^aerospace CLI client version: \([0-9][0-9]*\.[0-9][0-9]*\(\.[0-9][0-9]*\)*\).*/\1/p' | head -1 || true)"
    if [[ -z "$aerospace_v" ]]; then
      err "Could not read AeroSpace's version from 'aerospace --version', so its new config (which needs $AEROSPACE_MIN_VERSION or later) was not installed. Check that AeroSpace runs, then run: teeup update"
      exit 1
    fi
    if ! aerospace_version_ok "$aerospace_v" "$AEROSPACE_MIN_VERSION"; then
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
