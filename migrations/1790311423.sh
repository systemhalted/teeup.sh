#!/usr/bin/env bash
# Deliver the last of the chezmoi repo's shell and git content to machines
# that installed those capabilities before it was ported.
#
# The shell layer needs no refresh: ~/.zshrc and friends are thin stubs that
# source capabilities/zsh/default/*, which this checkout just updated, so the
# new PATH entries and Emacs variables are live on the next shell. The git
# config is different -- capabilities/git/config/git/config is copy-once, so a
# machine that already has ~/.config/git/config keeps its old one and would
# never see the two new aliases. migration_refresh replaces the copies nobody
# edited and leaves an edited one alone.
#
# The cap_exists guard matters: several `teeup update` tests in tests/cli.sh
# do not override TEEUP_MIGRATIONS_DIR and run this against a fixture
# capability tree with no git, where migration_refresh errors.
if cap_exists git; then
  migration_refresh git
fi
