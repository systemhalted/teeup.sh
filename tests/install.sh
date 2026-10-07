#!/usr/bin/env bash
# Tests for install.sh, the one-line installer served at
# https://teeup.systemhalted.in/install.sh. It runs against a real git
# fixture (TEEUP_INSTALL_REPO), with a bootstrap stub that records how it was
# called, so no test ever runs the real bootstrap. The script is run with the
# bash running this suite, so tests/bash32.sh runs it under bash 3.2.
set -euo pipefail
source "$(dirname "$0")/helper.sh"

INSTALLER="$TEEUP_PATH/install.sh"

setup() {
  setup_test_env
  mock_macos_base
  DEST="$HOME/.local/share/teeup"
  make_fixture
}

tgit() {
  git -c user.name="teeup test" -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c tag.gpgsign=false "$@"
}

# fixture_commit <version>: one commit whose version file is <version>.
fixture_commit() {
  printf '%s\n' "$1" > "$WORK/version"
  tgit -C "$WORK" add version bootstrap
  tgit -C "$WORK" commit -q -m "$1"
}

# make_fixture: a bare origin whose main carries v2.0.0 (old and unrelated),
# v0.1.0, v0.2.0 and one untagged commit after it. Its bootstrap writes the
# checked-out version, its arguments and where it ran to $HOME/bootstrap.out.
make_fixture() {
  ORIGIN="$TEST_HOME/origin.git"
  WORK="$TEST_HOME/work"
  tgit init -q --bare "$ORIGIN"
  git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
  tgit init -q "$WORK"
  git -C "$WORK" symbolic-ref HEAD refs/heads/main
  cat > "$WORK/bootstrap" <<'EOF2'
#!/usr/bin/env bash
{
  printf 'version=%s\n' "$(cat version)"
  printf 'pwd=%s\n' "$(pwd)"
  for a in "$@"; do printf 'arg=%s\n' "$a"; done
} > "$HOME/bootstrap.out"
EOF2
  chmod +x "$WORK/bootstrap"
  fixture_commit "2.0.0"
  tgit -C "$WORK" tag v2.0.0
  fixture_commit "0.1.0-beta"
  tgit -C "$WORK" tag -a v0.1.0 -m "v0.1.0"
  fixture_commit "0.2.0-beta"
  tgit -C "$WORK" tag -a v0.2.0 -m "v0.2.0"
  fixture_commit "0.3.0-dev"
  tgit -C "$WORK" remote add origin "$ORIGIN"
  tgit -C "$WORK" push -q origin main --tags
  export TEEUP_INSTALL_REPO="$ORIGIN"
}

# run_installer [args...]: install.sh run the way a file download runs it.
run_installer() {
  "$BASH" "$INSTALLER" "$@"
}

test_fresh_install_checks_out_the_newest_release_and_bootstraps() {
  setup
  local out
  out="$(run_installer --skip-daily "two words" 2>&1)"
  [[ -d "$DEST/.git" ]] || { echo "no checkout at $DEST"; echo "$out"; return 1; }
  assert_equals "$(git -C "$DEST" rev-parse "v0.2.0^{commit}")" "$(git -C "$DEST" rev-parse HEAD)" "HEAD is v0.2.0" || return 1
  assert_file_exists "$HOME/bootstrap.out" "bootstrap ran" || return 1
  local rec
  rec="$(cat "$HOME/bootstrap.out")"
  assert_contains "$rec" "version=0.2.0-beta" || return 1
  assert_contains "$rec" "pwd=$DEST" || return 1
  assert_contains "$rec" "arg=--skip-daily" || return 1
  assert_contains "$rec" "arg=two words" "an argument keeps its spaces" || return 1
  cleanup_test_env
}

# `curl ... | bash -s -- <args>`: the script arrives on stdin.
test_piped_install_passes_its_arguments_to_bootstrap() {
  setup
  # A space, a $ and a quote in HOME (CONTRIBUTING: every new suite).
  export HOME="$TEST_HOME/it's a \$home"
  mkdir -p "$HOME"
  DEST="$HOME/.local/share/teeup"
  "$BASH" -s -- --reconfigure < "$INSTALLER" >/dev/null 2>&1
  [[ -d "$DEST/.git" ]] || { echo "no checkout at $DEST"; return 1; }
  assert_contains "$(cat "$HOME/bootstrap.out")" "arg=--reconfigure" || return 1
  assert_contains "$(cat "$HOME/bootstrap.out")" "pwd=$DEST" || return 1
  cleanup_test_env
}

# Everything is inside main(), called on the last line, so a download that
# stops part way defines functions and runs nothing.
test_a_partly_downloaded_script_does_nothing() {
  setup
  local lines
  lines="$(wc -l < "$INSTALLER" | tr -d ' ')"
  head -n "$((lines - 1))" "$INSTALLER" | "$BASH" -s >/dev/null 2>&1 || true
  [[ ! -e "$DEST" ]] || { echo "a truncated script cloned"; return 1; }
  [[ ! -e "$HOME/bootstrap.out" ]] || { echo "a truncated script ran bootstrap"; return 1; }
  assert_equals 'main "$@"' "$(tail -n 1 "$INSTALLER")" "the last line calls main" || return 1
  cleanup_test_env
}

test_an_existing_checkout_is_not_cloned_again() {
  setup
  mkdir -p "$(dirname "$DEST")"
  tgit clone -q "$ORIGIN" "$DEST"
  git -C "$DEST" checkout -q --detach v0.1.0
  export TEEUP_INSTALL_REPO="$TEST_HOME/no-such-origin.git"
  local out rc=0
  out="$(run_installer --skip-daily 2>&1)" || rc=$?
  assert_equals "0" "$rc" "$out" || return 1
  assert_contains "$out" "teeup is already installed at $DEST" || return 1
  assert_contains "$(cat "$HOME/bootstrap.out")" "version=0.1.0-beta" "the checkout was left where it was" || return 1
  assert_contains "$(cat "$HOME/bootstrap.out")" "arg=--skip-daily" || return 1
  cleanup_test_env
}

test_an_existing_directory_that_is_not_a_checkout_is_refused() {
  setup
  mkdir -p "$DEST"
  : > "$DEST/notes.txt"
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$DEST exists and is not a git checkout" || return 1
  assert_file_exists "$DEST/notes.txt" "the directory is left alone" || return 1
  [[ ! -e "$HOME/bootstrap.out" ]] || { echo "bootstrap ran"; return 1; }
  cleanup_test_env
}

test_root_is_refused() {
  setup
  mock_command id 0 "0"
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "not as root" || return 1
  [[ ! -e "$DEST" ]] || { echo "cloned as root"; return 1; }
  cleanup_test_env
}

test_a_mac_is_required() {
  setup
  mock_command uname 0 "Linux"
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "teeup installs on macOS only" || return 1
  [[ ! -e "$DEST" ]] || { echo "cloned off macOS"; return 1; }
  cleanup_test_env
}

# xcode-select -p fails until softwareupdate has run.
mock_missing_clt() {
  mock_command_script xcode-select <<'EOF2'
if [ "$1" = "-p" ] && [ -e "$HOME/clt-installed" ]; then echo /Library/Developer/CommandLineTools; exit 0; fi
exit 2
EOF2
  mock_command touch 0 ""
  mock_command rm 0 ""
}

# cleanup_clt_test: cleanup_test_env deletes with rm, which mock_missing_clt
# replaced; take the stand-ins away first, with the real rm.
cleanup_clt_test() {
  /bin/rm -f "$MOCK_BIN/rm" "$MOCK_BIN/touch"
  cleanup_test_env
}

test_missing_clt_installs_through_softwareupdate() {
  setup
  mock_missing_clt
  mock_command_script softwareupdate <<'EOF2'
case "$1" in
  -l) printf '%s\n' "* Label: Command Line Tools for Xcode-16.2" ;;
  -i) : > "$HOME/clt-installed" ;;
esac
EOF2
  mock_command_script sudo <<'EOF2'
[ "$1" = "-v" ] && exit 0
exec "$@"
EOF2
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  assert_equals "0" "$rc" "$out" || return 1
  local log
  log="$(cat "$MOCK_LOG")"
  assert_contains "$log" "sudo -v" || return 1
  assert_contains "$log" "touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress" || return 1
  assert_contains "$log" "softwareupdate -i Command Line Tools for Xcode-16.2" || return 1
  assert_contains "$log" "rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress" || return 1
  [[ -d "$DEST/.git" ]] || { echo "no clone after the CLT install"; return 1; }
  cleanup_clt_test
}

# No label: Apple's dialog opens and the installer waits for it instead of
# exiting, so a curl | bash run does not have to be repeated.
test_missing_clt_without_a_label_waits_for_the_dialog() {
  setup
  mock_missing_clt
  mock_command softwareupdate 0 "No new software available."
  mock_command_script sleep <<'EOF2'
: > "$HOME/clt-installed"
EOF2
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  assert_equals "0" "$rc" "$out" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "xcode-select --install" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "sleep 30" || return 1
  assert_contains "$out" "Waiting for the Command Line Tools" || return 1
  [[ -d "$DEST/.git" ]] || { echo "no clone after the dialog"; return 1; }
  cleanup_clt_test
}

test_dry_run_writes_nothing() {
  setup
  mock_missing_clt
  mock_command softwareupdate 0 ""
  local out rc=0
  out="$(run_installer --dry-run 2>&1)" || rc=$?
  assert_equals "0" "$rc" "$out" || return 1
  [[ ! -e "$DEST" ]] || { echo "a dry run cloned"; return 1; }
  [[ ! -e "$HOME/bootstrap.out" ]] || { echo "a dry run ran bootstrap"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "softwareupdate" "nothing was installed" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "sudo" || return 1
  assert_contains "$out" "[DRY-RUN] Would install the Xcode Command Line Tools" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: git clone $ORIGIN $DEST" || return 1
  assert_contains "$out" "bootstrap's dry run needs the checkout" || return 1
  cleanup_clt_test
}

# install.sh repeats capabilities/xcode-clt/install's unattended path,
# because it must run before teeup is on disk. The two copies must agree.
test_clt_marker_and_label_match_the_capability() {
  setup
  local cap="$TEEUP_PATH/capabilities/xcode-clt/install" s
  for s in "/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress" \
           "grep -o 'Command Line Tools for Xcode-[0-9.]*'"; do
    grep -qF "$s" "$cap" || { echo "the capability no longer names: $s"; return 1; }
    grep -qF "$s" "$INSTALLER" || { echo "install.sh no longer names: $s"; return 1; }
  done
  cleanup_test_env
}

echo "install.sh"
run_test "fresh install checks out the newest release and bootstraps" test_fresh_install_checks_out_the_newest_release_and_bootstraps
run_test "piped install passes its arguments to bootstrap" test_piped_install_passes_its_arguments_to_bootstrap
run_test "a partly downloaded script does nothing" test_a_partly_downloaded_script_does_nothing
run_test "an existing checkout is not cloned again" test_an_existing_checkout_is_not_cloned_again
run_test "an existing directory that is not a checkout is refused" test_an_existing_directory_that_is_not_a_checkout_is_refused
run_test "root is refused" test_root_is_refused
run_test "a Mac is required" test_a_mac_is_required
run_test "missing CLT installs through softwareupdate" test_missing_clt_installs_through_softwareupdate
run_test "missing CLT without a label waits for the dialog" test_missing_clt_without_a_label_waits_for_the_dialog
run_test "dry run writes nothing" test_dry_run_writes_nothing
run_test "CLT marker and label match the capability" test_clt_marker_and_label_match_the_capability
print_summary
