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
  local dry="$1" marker label waited
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
    # Stop waiting once Apple's installer is gone (cancelled, or it never
    # opened), after a minute for it to appear, or after an hour; the check
    # below then says how to try again.
    waited=0
    until xcode-select -p >/dev/null 2>&1; do
      if [ "$waited" -ge 3600 ]; then break; fi
      if [ "$waited" -ge 60 ] && ! pgrep -f "Install Command Line Developer Tools" >/dev/null 2>&1; then break; fi
      say "Waiting for the Command Line Tools installer to finish..."
      sleep 30
      waited=$((waited + 30))
    done
  fi
  xcode-select -p >/dev/null 2>&1 ||
    die "The Command Line Tools are still missing. Run: xcode-select --install, then run this installer again."
  say "Xcode Command Line Tools installed."
}

# clone_teeup <repo> <dest> <dry-run:true|false>
# Clones <repo>, then checks out the newest release: the nearest v<digit>
# tag behind origin/main, the same rule lib/channel.sh uses for
# `teeup update`. An older tag further back loses to a nearer one, even
# when its version number is higher.
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

# is_teeup_checkout <dir> -> true when <dir> is a git checkout that has
# teeup's bootstrap and bin/teeup. Any other repository there is not ours to
# run: its ./bootstrap could be anything.
is_teeup_checkout() {
  [ -e "$1/.git" ] && [ -f "$1/bootstrap" ] && [ -f "$1/bin/teeup" ]
}

# check_data_home_writable <dry:true|false> -> prints the problem (and a
# command to inspect or fix it) when $HOME/.local/share, or its nearest
# existing ancestor, is not safely writable; prints nothing and returns 0
# when it is fine. That is where clone_teeup's `mkdir -p "$(dirname
# "$dest")"` writes, and a bare mkdir error part way through a MacBook's
# ./bootstrap (2026-10-11) is the reason this runs before the clone.
# install.sh runs before the clone, so it cannot source lib/core.sh; this
# is a small, self-contained copy of the same check (writable_dirs_check,
# lib/core.sh) -- kept in the same words on purpose, so tests/install.sh
# can check the two stay aligned.
#
# Order, deliberately (same reasoning as writable_dirs_check, lib/core.sh):
# a symlink that cannot be resolved, at the path itself or at any ancestor
# the walk passes through, is reported outright, never walked past. Then
# the write test decides -- the real mktemp -d probe outside a dry run
# (since -w only asks access(2), and an ACL or a privacy rule can pass
# that while a real mkdir still fails), -w and -x under one (a directory
# that is writable but not searchable cannot have anything created inside
# it either). Every probe this makes is removed before returning, and a
# cleanup that itself fails is reported rather than ignored. Ownership is
# consulted only once the write test fails, and only to choose the fix: a
# folder someone else owns but that still took the probe is left alone --
# ownership must never fail a folder by itself. A plain (non-recursive)
# `chown` naming the user's own group is offered only when
# $HOME/.local/share itself is the one that exists and is owned by someone
# else, never for an ancestor above it, and never a recursive one.
check_data_home_writable() {
  local dry="$1" path dir owner probe reason="" linktarget dir_q path_q probe_q
  path="$HOME/.local/share"
  dir="$path"
  while [ ! -e "$dir" ]; do
    if [ -L "$dir" ]; then
      linktarget="$(readlink "$dir")"
      printf '%s is a symlink that cannot be resolved (its target %s is missing, or the links form a loop). Fix or remove the link.\n' "$dir" "$linktarget"
      return 1
    fi
    dir="$(dirname "$dir")"
  done
  if [ "$dir" = "$path" ]; then
    if [ ! -d "$dir" ]; then
      echo "$dir exists and is not a directory. Move it aside, then try again."
      return 1
    fi
  else
    if [ ! -d "$dir" ]; then
      printf '%s is a file, not a folder, so teeup cannot create %s. Move it aside, then try again.\n' "$dir" "$path"
      return 1
    fi
  fi

  printf -v dir_q '%q' "$dir"
  printf -v path_q '%q' "$path"

  if [ "$dry" != "true" ]; then
    if probe="$(mktemp -d "$dir/.teeup-write-probe.XXXXXX" 2>&1)"; then
      if ! rmdir "$probe" 2>/dev/null; then
        printf -v probe_q '%q' "$probe"
        printf '%s: teeup created %s but could not remove it. Remove it by hand: rm -rf -- %s\n' "$dir" "$probe" "$probe_q"
        return 1
      fi
      # A directory probe passing does not prove a plain file can be
      # created there too -- some ACLs and sandboxing rules distinguish
      # the two.
      if probe="$(mktemp "$dir/.teeup-write-probe.XXXXXX" 2>&1)"; then
        if ! rm -f "$probe" 2>/dev/null; then
          printf -v probe_q '%q' "$probe"
          printf '%s: teeup created %s but could not remove it. Remove it by hand: rm -rf -- %s\n' "$dir" "$probe" "$probe_q"
          return 1
        fi
      else
        reason="file"
      fi
    else
      reason="probe"
    fi
  else
    [ -w "$dir" ] && [ -x "$dir" ] || reason="perm"
  fi
  [ -n "$reason" ] || return 0

  if [ -O "$dir" ]; then
    if [ "$dir" = "$HOME" ]; then
      if [ "$reason" = "probe" ]; then
        printf 'Your home folder %s does not allow new folders (%s). Run: ls -lde -- %s to see its permissions and ACLs.\n' "$dir" "$probe" "$dir_q"
      elif [ "$reason" = "file" ]; then
        printf 'Your home folder %s does not allow new files (%s). Run: ls -lde -- %s to see its permissions and ACLs.\n' "$dir" "$probe" "$dir_q"
      else
        printf 'Your home folder %s does not allow new folders. Run: ls -lde -- %s, then: chmod u+wx -- %s\n' "$dir" "$dir_q" "$dir_q"
      fi
    else
      if [ "$reason" = "probe" ]; then
        printf '%s refuses new folders (%s). Run: ls -lde -- %s to see its permissions and ACLs.\n' "$dir" "$probe" "$dir_q"
      elif [ "$reason" = "file" ]; then
        printf '%s refuses new files (%s). Run: ls -lde -- %s to see its permissions and ACLs.\n' "$dir" "$probe" "$dir_q"
      else
        printf '%s is not writable. Run: ls -lde -- %s, then: chmod u+wx -- %s\n' "$dir" "$dir_q" "$dir_q"
      fi
    fi
    return 1
  fi

  if [ "$dir" = "$path" ]; then
    owner="$(stat -c '%U' "$dir" 2>/dev/null || stat -f '%Su' "$dir" 2>/dev/null || true)"
    printf '%s is owned by %s, not you. Run: sudo chown -- "$(id -un)":"$(id -gn)" %s\n' "$dir" "${owner:-someone else}" "$dir_q"
    return 1
  fi

  # $dir is an ancestor of $HOME/.local/share, not the path itself, and
  # not mine: never offer a recursive chown of it.
  if [ "$dir" = "$HOME" ]; then
    printf 'Your home folder %s does not let you create %s. Run: ls -lde -- %s to see its permissions and ACLs. Create %s yourself with the right owner (for example: sudo mkdir -p -- %s && sudo chown -- "$(id -un)":"$(id -gn)" %s).\n' \
      "$dir" "$path" "$dir_q" "$path" "$path_q" "$path_q"
  else
    printf '%s does not let you create %s. Run: ls -lde -- %s to see its permissions and ACLs. Create %s yourself with the right owner (for example: sudo mkdir -p -- %s && sudo chown -- "$(id -un)":"$(id -gn)" %s).\n' \
      "$dir" "$path" "$dir_q" "$path" "$path_q" "$path_q"
  fi
  return 1
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
  local dest="$HOME/.local/share/teeup" dry=false arg writable_problem
  for arg in "$@"; do
    if [ "$arg" = "--dry-run" ]; then dry=true; fi
  done

  [ "$(uname -s)" = "Darwin" ] || die "teeup installs on macOS only; this system is $(uname -s)."
  [ "$(id -u)" -ne 0 ] || die "Run the installer as your own user, not as root."

  # Before any other work: -e and -e "$dest/.git" below both follow a
  # symlink to its target, so a dangling one, a loop, or one pointing at
  # a real but non-checkout directory would otherwise slip past every
  # check below (none of them is true for one), and the installer could
  # start installing the Command Line Tools before `git clone` finally
  # fails on it. is_teeup_checkout is false for all three of those, and
  # true for a symlink that does resolve to a real checkout, so this only
  # catches the symlink cases the checks below would miss.
  if [ -L "$dest" ] && ! is_teeup_checkout "$dest"; then
    die "$dest is a symlink, and not to a teeup checkout. Move it aside, then run the installer again."
  fi

  if is_teeup_checkout "$dest"; then
    say "teeup is already installed at $dest. Running its ./bootstrap again, which repairs what is missing."
    run_bootstrap "$dest" "$@"
  fi
  if [ -e "$dest/.git" ]; then
    die "$dest is a git checkout, but not of teeup. Move it aside, then run the installer again."
  fi
  if [ -e "$dest" ]; then
    die "$dest exists and is not a git checkout of teeup. Move it aside, then run the installer again."
  fi

  writable_problem="$(check_data_home_writable "$dry")" || die "$writable_problem"

  install_clt "$dry"
  clone_teeup "$repo" "$dest" "$dry"
  if [ "$dry" = "true" ]; then
    say "bootstrap's dry run needs the checkout, so the preview stops here. To see it, clone teeup by hand and run: ./bootstrap --dry-run"
    return 0
  fi
  run_bootstrap "$dest" "$@"
}

main "$@"
