#!/usr/bin/env bash
# install.sh - install teeup on a Mac in one line:
#
#   curl -fsSL https://teeup.systemhalted.in/install.sh | bash
#   wget -qO- https://teeup.systemhalted.in/install.sh | bash
#
# Options after `bash -s --` go to ./bootstrap (`... | bash -s -- --dry-run`).
#
# 1. Installs the Xcode Command Line Tools when they are missing, because on
#    a fresh Mac /usr/bin/git is only a stub that opens Apple's dialog.
# 2. Clones teeup into ~/.local/share/teeup at its newest release.
# 3. Runs ./bootstrap there.
#
# A Mac that already has the checkout gets its ./bootstrap run again, which
# is teeup's repair path. bash 3.2, nothing beyond a fresh macOS.
#
# Everything is inside main, called on the last line, so a download that
# stops part way runs nothing.
set -eu

say()  { printf "%b %s\n" "🔹" "$*"; }
warn() { printf "%b %s\n" "⚠️" "$*" >&2; }
die()  { printf "%b %s\n" "❌" "$*" >&2; exit 1; }

# have_tty -> true when /dev/tty can be opened. Under `curl | bash` stdin is
# the script itself, so a prompt (sudo's, then bootstrap's) must read from
# the terminal instead. A CI job or an ssh session without one has no tty.
have_tty() {
  (exec < /dev/tty) 2>/dev/null
}

# install_clt <dry-run:true|false>
# The same unattended path as capabilities/xcode-clt/install: the on-demand
# marker makes softwareupdate list the CLT package. When it lists none,
# Apple's dialog opens and this waits for it rather than exiting, so the
# one-liner does not have to be run twice. tests/install.sh checks that the
# marker and the label pattern stay the same in both files.
install_clt() {
  local dry="$1" marker label
  if xcode-select -p >/dev/null 2>&1; then
    say "Xcode Command Line Tools present."
    return 0
  fi
  if [ "$dry" = "true" ]; then
    say "[DRY-RUN] Would install the Xcode Command Line Tools with softwareupdate, or open Apple's installer when it lists none."
    return 0
  fi
  say "Installing the Xcode Command Line Tools. This takes a few minutes, and sudo asks for your password."
  if have_tty; then
    # shellcheck disable=SC2024 # the redirect is meant for sudo's prompt, not a file sudo reads
    sudo -v < /dev/tty || die "sudo is required to install the Command Line Tools."
  else
    sudo -v || die "sudo is required to install the Command Line Tools."
  fi
  marker="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
  touch "$marker"
  label="$(softwareupdate -l 2>/dev/null | grep -o 'Command Line Tools for Xcode-[0-9.]*' | tail -1 || true)"
  if [ -n "$label" ]; then
    if ! sudo softwareupdate -i "$label"; then
      rm -f "$marker"
      die "softwareupdate could not install $label. Run: xcode-select --install, then run this installer again."
    fi
    rm -f "$marker"
  else
    rm -f "$marker"
    warn "softwareupdate lists no Command Line Tools package, so Apple's installer opens. Complete its dialog; this script waits for it."
    xcode-select --install >/dev/null 2>&1 || true
    until xcode-select -p >/dev/null 2>&1; do
      say "Waiting for the Command Line Tools installer to finish..."
      sleep 30
    done
  fi
  xcode-select -p >/dev/null 2>&1 ||
    die "The Command Line Tools are still missing. Run: xcode-select --install, then run this installer again."
  say "Xcode Command Line Tools installed."
}

# clone_teeup <repo> <dest> <dry-run:true|false>
# Clones <repo>, then checks out the newest release: the nearest v<digit>
# tag behind origin/main, the same rule lib/channel.sh uses for
# `teeup update`. An older tag further back (v2.0.0) loses to a nearer one.
clone_teeup() {
  local repo="$1" dest="$2" dry="$3" tag
  if [ "$dry" = "true" ]; then
    say "[DRY-RUN] Would execute: git clone $repo $dest"
    say "[DRY-RUN] Would check out the newest release tag on main."
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  if ! git clone --quiet "$repo" "$dest"; then
    warn "On a network that re-signs HTTPS, git does not trust the company certificate until teeup builds its bundle."
    die "git clone of $repo failed. Run the installer on another network, or clone by hand: https://teeup.systemhalted.in/getting-started.html"
  fi
  tag="$(git -C "$dest" describe --tags --abbrev=0 --match 'v[0-9]*' origin/main 2>/dev/null || true)"
  if [ -z "$tag" ]; then
    warn "No release tag found on main, so teeup stays on main."
    return 0
  fi
  git -C "$dest" checkout --quiet --detach "$tag"
  say "Cloned teeup $tag into $dest."
}

# run_bootstrap <dest> [args...]: replace this script with the checkout's
# ./bootstrap, its prompts reading from the terminal.
run_bootstrap() {
  local dest="$1"
  shift
  cd "$dest"
  if have_tty; then
    exec ./bootstrap "$@" < /dev/tty
  fi
  exec ./bootstrap "$@"
}

main() {
  local repo="${TEEUP_INSTALL_REPO:-https://github.com/systemhalted/teeup.sh}"
  local dest="$HOME/.local/share/teeup" dry=false arg
  for arg in "$@"; do
    if [ "$arg" = "--dry-run" ]; then dry=true; fi
  done

  [ "$(uname -s)" = "Darwin" ] || die "teeup installs on macOS only; this system is $(uname -s)."
  [ "$(id -u)" -ne 0 ] || die "Run the installer as your own user, not as root."

  if [ -e "$dest/.git" ]; then
    say "teeup is already installed at $dest. Running its ./bootstrap again, which repairs what is missing."
    run_bootstrap "$dest" "$@"
  fi
  if [ -e "$dest" ]; then
    die "$dest exists and is not a git checkout of teeup. Move it aside, then run the installer again."
  fi

  install_clt "$dry"
  clone_teeup "$repo" "$dest" "$dry"
  if [ "$dry" = "true" ]; then
    say "bootstrap's dry run needs the checkout, so the preview stops here. To see it, clone teeup by hand and run: ./bootstrap --dry-run"
    return 0
  fi
  run_bootstrap "$dest" "$@"
}

main "$@"
