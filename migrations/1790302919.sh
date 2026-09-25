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
if cap_exists aerospace; then
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
