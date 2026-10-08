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

# Release tags are fetched into a namespace of their own, so that pruning
# a withdrawn release never touches a tag the user made in refs/tags.
CHANNEL_RELEASES="refs/teeup/releases"

# channel_fetch <dir>: fetch origin's main and its v<digit> tags. --prune
# applies only to the refspecs given here, so it drops a release whose tag
# was deleted on origin and leaves every other local ref alone.
channel_fetch() {
  _channel_run "git fetch" git -C "$1" fetch --quiet --prune origin \
    "+refs/heads/main:refs/remotes/origin/main" \
    "+refs/tags/v*:$CHANNEL_RELEASES/v*"
}

# _channel_release_refs <dir> -> where the releases are: teeup's namespace
# once channel_fetch has filled it, else the clone's own tags (a checkout
# that has not fetched yet, as in a dry run).
_channel_release_refs() {
  if [[ -n "$(git -C "$1" for-each-ref --count=1 --format='%(refname)' "$CHANNEL_RELEASES/")" ]]; then
    printf '%s\n' "$CHANNEL_RELEASES"
  else
    printf 'refs/tags\n'
  fi
}

# channel_newest_release <dir> -> the newest release on origin/main, as a
# tag name, from what channel_fetch fetched. Releases are tagged on main,
# so the newest is the one with the most commits behind it. An older tag
# further back (such as a v2.0.0 left from before the version numbers
# restarted) loses to a nearer one.
# Prints nothing and returns non-zero when there is no such tag.
channel_newest_release() {
  local dir="$1" ref n best="" best_n=-1 refs
  refs="$(_channel_release_refs "$dir")"
  for ref in $(git -C "$dir" for-each-ref --format='%(refname)' "$refs/"); do
    # A refspec has only *, not [0-9]: keep v<digit> names here.
    case "${ref#"$refs"/}" in v[0-9]*) ;; *) continue ;; esac
    git -C "$dir" merge-base --is-ancestor "$ref" origin/main 2>/dev/null || continue
    n="$(git -C "$dir" rev-list --count "$ref")"
    if [[ "$n" -gt "$best_n" ]]; then
      best="${ref#"$refs"/}"
      best_n="$n"
    fi
  done
  [[ -n "$best" ]] || return 1
  printf '%s\n' "$best"
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
  local dir="$1" channel="$2" tag ref old head branch
  case "$channel" in
    release|main) ;;
    *) err "channel_sync: unknown channel '$channel'"; return 2 ;;
  esac
  channel_fetch "$dir" || return 1

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
      # A checkout detached at a commit of its own (made on top of a
      # release) would be left behind by the switch; keep it instead.
      if ! git -C "$dir" merge-base --is-ancestor HEAD origin/main; then
        warn "The checkout in $dir has commits that origin/main does not have, so teeup leaves it where it is. Put them on a branch first."
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
  ref="$(_channel_release_refs "$dir")/$tag"
  if [[ "$head" == "$(git -C "$dir" rev-parse "$ref^{commit}")" ]]; then
    log "teeup is on the newest release, $tag."
  elif git -C "$dir" merge-base --is-ancestor HEAD "$ref"; then
    old="$(cat "$dir/version" 2>/dev/null || echo "an unknown version")"
    _channel_run "git checkout $tag" git -C "$dir" checkout --quiet --detach "$ref" || return 1
    ok_unless_dry "Updated teeup from $old to $tag."
  elif git -C "$dir" merge-base --is-ancestor "$ref" HEAD; then
    # This includes a machine still on a release whose tag was withdrawn:
    # teeup does not move it back. A newer release moves it forward.
    log "teeup is ahead of the newest release ($tag); it stays where it is until a newer release exists."
  else
    warn "The checkout in $dir has commits that the newest release ($tag) does not have, so teeup leaves it where it is."
    return 1
  fi
  return 0
}
