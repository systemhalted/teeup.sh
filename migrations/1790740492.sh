#!/usr/bin/env bash
# Older github installs could be marked done after accepting any gh already
# on PATH, including a mise shim. The capability now owns the package-manager
# gh, so repair only machines that completed that capability and still lack
# its formula or port. pkg_install supplies the backend mapping, idempotency
# and dry-run behavior; no mise state is read or changed here.

if cap_exists github && state_done check cap-github; then
  pkg_install gh || exit 1
fi
