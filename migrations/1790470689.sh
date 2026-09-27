#!/usr/bin/env bash
# Install terminal-app on a machine that already ran teeup before this
# branch added it.
#
# Final review I4 (the owner's decision): terminal-app is a core capability
# now, but `teeup update`'s core-tier loop (bin/teeup's
# _update_configure_tier) only re-runs `configure` on a capability already
# marked installed; it never installs one core gained since a machine's last
# bootstrap. Without this migration, an existing Mac that pulls this branch
# and runs `teeup update && teeup theme set <name>` keeps a Basic-profile
# Terminal.app forever, because nothing short of a fresh ./bootstrap would
# ever reach terminal-app's install script.
#
# cap_install_verbs (lib/capability.sh) is the same primitive `teeup install`
# itself calls: it runs terminal-app's install and configure scripts and
# marks it installed or not-applicable, so a DRY_RUN teeup update previews
# it exactly as `teeup install terminal-app` would, and TEEUP_SKIP is
# honoured the same way.
#
# A fresh ./bootstrap needs none of this: it installs terminal-app as part
# of core in the same run this migration would otherwise have fired in, and
# migrations_mark_all (lib/migrations.sh) marks every shipped migration,
# this one included, applied without running it -- so it never runs there
# at all.
#
# The cap_exists guard matters: several `teeup update` tests run migrations
# against a fixture capability tree with no terminal-app, where
# cap_install_verbs would error. requires="theme" is terminal-app's own
# metadata (it themes Terminal.app from the rendered palette), and theme is
# itself core, so on any real existing machine it is already installed by
# the time migrations run; the check only guards the same impossible case
# the aerospace migration guards for its own dependency, without erroring
# the whole update over it.
if cap_exists terminal-app; then
  if state_done check cap-terminal-app; then
    log "terminal-app is already installed; nothing to do."
  elif state_na check cap-terminal-app; then
    log "terminal-app was already found not applicable on this machine; nothing to do."
  elif cap_skipped terminal-app; then
    warn "Skipping terminal-app (TEEUP_SKIP)."
  elif ! state_done check cap-theme; then
    log "theme is not installed here yet, so terminal-app was left for a later teeup update."
    exit 1
  else
    cap_install_verbs terminal-app || exit 1
  fi
fi
