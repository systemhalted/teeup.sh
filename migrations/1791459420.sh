#!/usr/bin/env bash
# The user tools move from the package manager to mise, at the versions in
# share/teeup/tools.lock (#112). From this release on, teeup update installs
# and links them on every run, but the update that brings this release still
# runs the previous release's code, which knows nothing of mise_tools. This
# migration does the first move with the new code: every installed
# capability's tools installed and linked into ~/.local/bin, then
# ~/.config/mise/conf.d/teeup.toml.
#
# The Homebrew or MacPorts copies stay installed. teeup update stops
# upgrading them, and teeup doctor prints the command that removes each one.
# A tool that does not install now (offline, a proxy) does not stop the
# update: the next teeup update tries again, and teeup doctor names it.
if ! cap_exists mise; then
  exit 0
fi
if ! mise_tools_sync; then
  warn "Some tools did not move to mise (the lines above say which). The next teeup update tries again; teeup doctor names each one."
fi
log "The Homebrew or MacPorts copies of these tools stay installed. teeup doctor prints the command that removes each one."
