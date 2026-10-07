#!/usr/bin/env bash
# channel.sh - which commit `teeup update` moves the checkout to.
# Sourced by lib/all.sh.
#
# Two channels, saved as TEEUP_UPDATE_CHANNEL in the answers file:
#   release (the default) - the newest release tag on origin/main;
#   main                  - the tip of origin/main, for the newest code.
# The checkout never moves backwards: a machine already ahead of the newest
# release (every machine that tracked main before releases existed) stays
# where it is until a newer release passes it.
#
# Every function that touches git takes the checkout as its first argument,
# so tests/lib/channel.sh can run it against a real fixture repository.

# channel_get -> release or main. An unset answer is release; any other
# value warns and is treated as release, the safer of the two.
channel_get() {
  local channel
  channel="$(answers_get TEEUP_UPDATE_CHANNEL release)"
  case "$channel" in
    release|main) printf '%s\n' "$channel" ;;
    *)
      warn "TEEUP_UPDATE_CHANNEL=$channel is not release or main; following releases. Fix it with: teeup update --release"
      printf 'release\n'
      ;;
  esac
}

# channel_newest_release <dir> -> the newest release tag on origin/main.
# Releases are tagged on main, so the nearest v<digit> tag behind
# origin/main is the newest one. An older tag that sits further back
# (such as a v2.0.0 left from before the version numbers restarted) loses
# to a nearer one.
# Prints nothing and returns non-zero when there is no such tag.
channel_newest_release() {
  git -C "$1" describe --tags --abbrev=0 --match 'v[0-9]*' origin/main 2>/dev/null
}

# _channel_git_failed <what> <output>: the warning for a failed fetch or
# pull. A certificate error gets its own hint, because behind a proxy that
# re-signs HTTPS it is the usual cause and has a known fix.
_channel_git_failed() {
  local what="$1" out="$2"
  if [[ "$out" == *"certificate"* ]]; then
    warn "$what failed: git does not trust the certificate it was shown, which usually means a network proxy is re-signing HTTPS. Continuing with the checkout as it is."
    warn "teeup builds a certificate bundle from the Keychain when the Mac has company root certificates. Run: teeup doctor ca-bundle"
  else
    warn "$what failed; continuing with the checkout as it is."
  fi
}

# _channel_run <what> <command...>: run_cmd, with the command's output shown
# and a failure reported through _channel_git_failed. Returns its status.
_channel_run() {
  local what="$1" out rc=0
  shift
  out="$(run_cmd "$@" 2>&1)" || rc=$?
  if [[ -n "$out" ]]; then printf '%s\n' "$out"; fi
  if [[ $rc -ne 0 ]]; then
    _channel_git_failed "$what" "$out"
  fi
  return $rc
}

# channel_sync <dir> <release|main> -> 0 moved or already right, 1 could not
# move (warned; the checkout is left as it is), 2 must not continue (an
# unknown channel, which only a caller bug can pass).
channel_sync() {
  local dir="$1" channel="$2" tag old head branch
  case "$channel" in
    release|main) ;;
    *) err "channel_sync: unknown channel '$channel'"; return 2 ;;
  esac
  # --prune-tags drops a local tag that origin no longer has, so a release
  # withdrawn by deleting its tag stops being chosen.
  _channel_run "git fetch" git -C "$dir" fetch --tags --force --prune --prune-tags origin || return 1

  if [[ "$channel" == "main" ]]; then
    branch="$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    if [[ "$branch" != "main" ]]; then
      # Every release is on main, so moving to origin/main is forward from
      # any release. A local main with commits of its own is the exception:
      # `checkout -B` would throw them away.
      if git -C "$dir" show-ref --verify --quiet refs/heads/main &&
         ! git -C "$dir" merge-base --is-ancestor refs/heads/main origin/main; then
        warn "The local branch main in $dir has commits that origin/main does not have, so teeup leaves the checkout where it is."
        return 1
      fi
      _channel_run "git checkout main" git -C "$dir" checkout --quiet -B main origin/main || return 1
    fi
    _channel_run "git pull --ff-only" git -C "$dir" pull --ff-only origin main || return 1
    return 0
  fi

  tag="$(channel_newest_release "$dir")" || tag=""
  if [[ -z "$tag" ]]; then
    warn "No release tag found on origin/main, so the checkout stays where it is."
    return 1
  fi
  head="$(git -C "$dir" rev-parse HEAD)"
  if [[ "$head" == "$(git -C "$dir" rev-parse "$tag^{commit}")" ]]; then
    log "teeup is on the newest release, $tag."
  elif git -C "$dir" merge-base --is-ancestor HEAD "$tag"; then
    old="$(cat "$dir/version" 2>/dev/null || echo "an unknown version")"
    _channel_run "git checkout $tag" git -C "$dir" checkout --quiet --detach "$tag" || return 1
    ok_unless_dry "Updated teeup from $old to $tag."
  elif git -C "$dir" merge-base --is-ancestor "$tag" HEAD; then
    log "teeup is ahead of the newest release ($tag); it stays where it is until a newer release exists."
  else
    warn "The checkout in $dir has commits that the newest release ($tag) does not have, so teeup leaves it where it is."
    return 1
  fi
  return 0
}
