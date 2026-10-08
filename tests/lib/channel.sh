#!/usr/bin/env bash
# Tests for lib/channel.sh: which commit `teeup update` moves the checkout
# to. These use real git, not a mock: the release rule is a question about
# the commit graph (which tag is nearest, which commit is an ancestor of
# which), and a mock would only repeat what the code under test assumes.
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_command hostname 0 "testmac"
  source "$TEEUP_PATH/lib/all.sh"
  # shellcheck disable=SC2034
  DRY_RUN=false
  unset TEEUP_UPDATE_CHANNEL
}

# git with a throwaway identity, so a fixture commit or tag never needs the
# user's own git configuration (there is none inside $TEST_HOME anyway).
tgit() {
  git -c user.name="teeup test" -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c tag.gpgsign=false "$@"
}

# fixture_commit <message>: one commit in $WORK whose version file is
# <message>, so a test can tell commits apart by `cat version`.
fixture_commit() {
  printf '%s\n' "$1" > "$WORK/version"
  tgit -C "$WORK" add version
  tgit -C "$WORK" commit -q -m "$1"
}

# make_fixture [<clone dir>]: a bare origin whose main carries v2.0.0 (an
# old, unrelated tag), then v0.1.0, then v0.2.0, then one untagged commit;
# and a clone of it at $CLONE, on branch main.
make_fixture() {
  ORIGIN="$TEST_HOME/origin.git"
  WORK="$TEST_HOME/work"
  CLONE="${1:-$TEST_HOME/teeup}"
  tgit init -q --bare "$ORIGIN"
  git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
  tgit init -q "$WORK"
  git -C "$WORK" symbolic-ref HEAD refs/heads/main
  fixture_commit "2.0.0"
  tgit -C "$WORK" tag v2.0.0
  fixture_commit "0.1.0-beta"
  tgit -C "$WORK" tag -a v0.1.0 -m "v0.1.0"
  fixture_commit "0.2.0-beta"
  tgit -C "$WORK" tag -a v0.2.0 -m "v0.2.0"
  fixture_commit "0.3.0-dev"
  tgit -C "$WORK" remote add origin "$ORIGIN"
  tgit -C "$WORK" push -q origin main --tags
  mkdir -p "$(dirname "$CLONE")"
  tgit clone -q "$ORIGIN" "$CLONE"
}

# head_is <dir> <rev>: true when HEAD in <dir> is the commit <rev> names.
head_is() {
  [[ "$(git -C "$1" rev-parse HEAD)" == "$(git -C "$1" rev-parse "$2^{commit}")" ]]
}

test_channel_get_defaults_to_release() {
  setup
  assert_equals "release" "$(channel_get)" || return 1
  export TEEUP_UPDATE_CHANNEL=main
  assert_equals "main" "$(channel_get)" || return 1
  cleanup_test_env
}

test_channel_get_treats_an_unknown_value_as_release() {
  setup
  local out
  export TEEUP_UPDATE_CHANNEL=nightly
  out="$(channel_get 2>"$TEST_HOME/err")"
  assert_equals "release" "$out" || return 1
  assert_contains "$(cat "$TEST_HOME/err")" "TEEUP_UPDATE_CHANNEL=nightly" || return 1
  cleanup_test_env
}

test_newest_release_skips_an_old_unrelated_tag() {
  setup
  make_fixture
  assert_equals "v0.2.0" "$(channel_newest_release "$CLONE")" "v2.0.0 is further from main than v0.2.0" || return 1
  cleanup_test_env
}

test_release_moves_an_older_release_forward() {
  setup
  # A space, a $ and a quote in the path (CONTRIBUTING: every new suite).
  make_fixture "$TEST_HOME/it's a \$dir/teeup"
  git -C "$CLONE" checkout -q --detach v0.1.0
  local out rc=0
  out="$(channel_sync "$CLONE" release 2>&1)" || rc=$?
  assert_equals "0" "$rc" "$out" || return 1
  head_is "$CLONE" v0.2.0 || { echo "HEAD is not v0.2.0"; return 1; }
  assert_contains "$out" "Updated teeup from 0.1.0-beta to v0.2.0." || return 1
  cleanup_test_env
}

test_release_already_on_the_newest_release_changes_nothing() {
  setup
  make_fixture
  git -C "$CLONE" checkout -q --detach v0.2.0
  local out
  out="$(channel_sync "$CLONE" release 2>&1)"
  head_is "$CLONE" v0.2.0 || { echo "HEAD moved"; return 1; }
  assert_contains "$out" "teeup is on the newest release, v0.2.0." || return 1
  cleanup_test_env
}

# Every existing user tracks main today. Moving them back to the release
# would be a downgrade, which teeup never does.
test_release_never_moves_main_backwards() {
  setup
  make_fixture
  local before out
  before="$(git -C "$CLONE" rev-parse HEAD)"
  out="$(channel_sync "$CLONE" release 2>&1)"
  assert_equals "$before" "$(git -C "$CLONE" rev-parse HEAD)" "HEAD moved" || return 1
  assert_equals "main" "$(git -C "$CLONE" symbolic-ref --short HEAD)" "still on branch main" || return 1
  assert_contains "$out" "teeup is ahead of the newest release (v0.2.0); it stays where it is until a newer release exists." || return 1
  cleanup_test_env
}

test_release_never_picks_the_unrelated_v2_tag() {
  setup
  make_fixture
  git -C "$CLONE" checkout -q --detach v0.1.0
  channel_sync "$CLONE" release >/dev/null 2>&1
  if head_is "$CLONE" v2.0.0; then echo "moved to v2.0.0"; return 1; fi
  head_is "$CLONE" v0.2.0 || { echo "HEAD is not v0.2.0"; return 1; }
  cleanup_test_env
}

# The fetch is what brings a release made after the clone; without it the
# rule would only ever see the tags the checkout already had.
test_release_fetches_a_release_made_after_the_clone() {
  setup
  make_fixture
  git -C "$CLONE" checkout -q --detach v0.2.0
  fixture_commit "0.3.0-beta"
  tgit -C "$WORK" tag -a v0.3.0 -m "v0.3.0"
  tgit -C "$WORK" push -q origin main --tags
  channel_sync "$CLONE" release >/dev/null 2>&1
  head_is "$CLONE" v0.3.0 || { echo "HEAD is not v0.3.0"; return 1; }
  cleanup_test_env
}

# A release withdrawn by deleting its tag on origin must stop being chosen,
# although the clone fetched the tag before it was deleted.
test_a_withdrawn_release_tag_is_not_chosen() {
  setup
  make_fixture
  git -C "$CLONE" checkout -q --detach v0.1.0
  tgit -C "$WORK" push -q origin :refs/tags/v0.2.0
  channel_sync "$CLONE" release >/dev/null 2>&1
  head_is "$CLONE" v0.1.0 || { echo "HEAD moved to the withdrawn v0.2.0"; return 1; }
  if git -C "$CLONE" rev-parse -q --verify refs/tags/v0.2.0 >/dev/null; then
    echo "the local v0.2.0 tag was kept"; return 1
  fi
  cleanup_test_env
}

# A commit made on top of a detached release is not on origin/main, so
# switching to main would leave it behind: --main refuses instead.
test_main_keeps_a_detached_commit_of_its_own() {
  setup
  make_fixture
  git -C "$CLONE" checkout -q --detach v0.2.0
  printf 'local\n' > "$CLONE/local.txt"
  tgit -C "$CLONE" add local.txt
  tgit -C "$CLONE" commit -q -m "local change"
  local before rc=0
  before="$(git -C "$CLONE" rev-parse HEAD)"
  channel_sync "$CLONE" main >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "channel_sync should refuse" || return 1
  assert_equals "$before" "$(git -C "$CLONE" rev-parse HEAD)" "HEAD moved off the local commit" || return 1
  cleanup_test_env
}

test_main_from_a_detached_tag_ends_on_branch_main() {
  setup
  make_fixture
  git -C "$CLONE" checkout -q --detach v0.1.0
  fixture_commit "0.3.0-dev2"
  tgit -C "$WORK" push -q origin main
  local out rc=0
  out="$(channel_sync "$CLONE" main 2>&1)" || rc=$?
  assert_equals "0" "$rc" "$out" || return 1
  assert_equals "main" "$(git -C "$CLONE" symbolic-ref --short HEAD)" "on branch main" || return 1
  assert_equals "$(git -C "$WORK" rev-parse HEAD)" "$(git -C "$CLONE" rev-parse HEAD)" "at the newest commit" || return 1
  cleanup_test_env
}

test_main_on_branch_main_pulls() {
  setup
  make_fixture
  fixture_commit "0.3.0-dev2"
  tgit -C "$WORK" push -q origin main
  channel_sync "$CLONE" main >/dev/null 2>&1
  assert_equals "$(git -C "$WORK" rev-parse HEAD)" "$(git -C "$CLONE" rev-parse HEAD)" "at the newest commit" || return 1
  cleanup_test_env
}

# A local main with commits origin/main lacks: `checkout -B` would throw
# them away, so the move is refused.
test_main_keeps_a_local_main_with_its_own_commits() {
  setup
  make_fixture
  tgit -C "$CLONE" commit -q --allow-empty -m "local work"
  local mine rc=0 out
  mine="$(git -C "$CLONE" rev-parse HEAD)"
  git -C "$CLONE" checkout -q --detach v0.1.0
  out="$(channel_sync "$CLONE" main 2>&1)" || rc=$?
  assert_equals "1" "$rc" "$out" || return 1
  assert_equals "$mine" "$(git -C "$CLONE" rev-parse main)" "local main kept" || return 1
  assert_contains "$out" "has commits that origin/main does not have" || return 1
  cleanup_test_env
}

test_dry_run_changes_nothing() {
  setup
  make_fixture
  git -C "$CLONE" checkout -q --detach v0.1.0
  local out
  # shellcheck disable=SC2034
  DRY_RUN=true
  out="$(channel_sync "$CLONE" release 2>&1)"
  head_is "$CLONE" v0.1.0 || { echo "a dry run moved HEAD"; return 1; }
  assert_contains "$out" "[DRY-RUN] Would execute: git -C $CLONE checkout --quiet --detach v0.2.0" || return 1
  out="$(channel_sync "$CLONE" main 2>&1)"
  head_is "$CLONE" v0.1.0 || { echo "a dry run moved HEAD"; return 1; }
  if git -C "$CLONE" symbolic-ref -q HEAD >/dev/null; then echo "a dry run left the detached HEAD"; return 1; fi
  cleanup_test_env
}

test_a_fetch_failure_returns_1() {
  setup
  make_fixture
  git -C "$CLONE" checkout -q --detach v0.1.0
  git -C "$CLONE" remote set-url origin "$TEST_HOME/no-such-origin.git"
  local out rc=0
  out="$(channel_sync "$CLONE" release 2>&1)" || rc=$?
  assert_equals "1" "$rc" "$out" || return 1
  head_is "$CLONE" v0.1.0 || { echo "HEAD moved after a failed fetch"; return 1; }
  assert_contains "$out" "git fetch failed; continuing with the checkout as it is." || return 1
  cleanup_test_env
}

test_a_certificate_failure_names_the_ca_bundle() {
  setup
  make_fixture
  mock_command_script git <<'EOF2'
case "$*" in
  *fetch*) echo "SSL certificate problem: self signed certificate in certificate chain" >&2; exit 128 ;;
esac
exit 0
EOF2
  # The fixture ran the real git, and bash remembers where it found it.
  hash -r
  local out rc=0
  out="$(channel_sync "$CLONE" release 2>&1)" || rc=$?
  assert_equals "1" "$rc" "$out" || return 1
  assert_contains "$out" "network proxy is re-signing HTTPS" || return 1
  assert_contains "$out" "teeup doctor ca-bundle" || return 1
  cleanup_test_env
}

echo "lib/channel.sh"
run_test "a withdrawn release tag is not chosen" test_a_withdrawn_release_tag_is_not_chosen
run_test "channel_get defaults to release" test_channel_get_defaults_to_release
run_test "channel_get treats an unknown value as release" test_channel_get_treats_an_unknown_value_as_release
run_test "newest release skips an old unrelated tag" test_newest_release_skips_an_old_unrelated_tag
run_test "release moves an older release forward" test_release_moves_an_older_release_forward
run_test "release already on the newest release changes nothing" test_release_already_on_the_newest_release_changes_nothing
run_test "release never moves main backwards" test_release_never_moves_main_backwards
run_test "release never picks the unrelated v2.0.0 tag" test_release_never_picks_the_unrelated_v2_tag
run_test "release fetches a release made after the clone" test_release_fetches_a_release_made_after_the_clone
run_test "main keeps a detached commit of its own" test_main_keeps_a_detached_commit_of_its_own
run_test "main from a detached tag ends on branch main" test_main_from_a_detached_tag_ends_on_branch_main
run_test "main on branch main pulls" test_main_on_branch_main_pulls
run_test "main keeps a local main with its own commits" test_main_keeps_a_local_main_with_its_own_commits
run_test "a dry run changes nothing" test_dry_run_changes_nothing
run_test "a fetch failure returns 1" test_a_fetch_failure_returns_1
run_test "a certificate failure names the CA bundle" test_a_certificate_failure_names_the_ca_bundle
print_summary
