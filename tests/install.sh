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
  tgit -C "$WORK" add version bootstrap bin/teeup
  tgit -C "$WORK" commit -q -m "$1"
}

# make_fixture: a bare origin whose main carries v2.0.0 (old and unrelated),
# v0.1.0, v0.2.0 and one untagged commit after it. Its bootstrap writes the
# checked-out version, its arguments and where it ran to $HOME/bootstrap.out,
# and exits with $FAKE_BOOTSTRAP_RC (0 when unset).
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
exit "${FAKE_BOOTSTRAP_RC:-0}"
EOF2
  chmod +x "$WORK/bootstrap"
  mkdir -p "$WORK/bin"
  printf '#!/usr/bin/env bash\n' > "$WORK/bin/teeup"
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

# A different repository at the install path is refused, and its own
# ./bootstrap never runs.
test_an_unrelated_git_checkout_is_refused() {
  setup
  mkdir -p "$DEST"
  tgit init -q "$DEST"
  printf '#!/usr/bin/env bash\ntouch "$HOME/unrelated-ran"\n' > "$DEST/bootstrap"
  chmod +x "$DEST/bootstrap"
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$DEST is a git checkout, but not of teeup" || return 1
  [[ ! -e "$HOME/unrelated-ran" ]] || { echo "the unrelated bootstrap ran"; return 1; }
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

test_an_unwritable_data_home_stops_before_the_clone() {
  setup
  # $HOME/.local/share does not exist yet, but $HOME/.local does and is
  # locked, so the ancestor walk stops there. A non-dry run's write test is
  # the real mktemp probe, not -w, so a real EACCES there reads as "refuses
  # new folders", not "is not writable".
  local locked="$HOME/.local"
  mkdir -p "$locked"
  chmod 555 "$locked"
  export TEEUP_INSTALL_REPO="$TEST_HOME/no-such-origin.git"
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  chmod u+w "$locked"
  assert_failure "$rc" || return 1
  assert_contains "$out" "$locked refuses new folders" || return 1
  assert_contains "$out" "ls -lde -- $locked to see its permissions and ACLs" || return 1
  [[ ! -e "$DEST" ]] || { echo "cloned into a locked data home"; return 1; }
  cleanup_test_env
}

# -w alone cannot tell a real ACL refusal from a plain unwritable directory,
# so check_data_home_writable also does a real mkdir-and-remove; a sandbox
# cannot set up a real ACL, so mktemp is mocked to fail it.
test_an_acl_denied_data_home_stops_before_the_clone() {
  setup
  # $HOME/.local exists and passes -O/-w, so the probe is what fails here,
  # not an earlier check.
  mkdir -p "$HOME/.local"
  mock_command_script mktemp <<'EOF2'
echo "mktemp: mkdtemp failed: Operation not permitted" >&2
exit 1
EOF2
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$HOME/.local refuses new folders" || return 1
  assert_contains "$out" "Operation not permitted" || return 1
  assert_contains "$out" "ls -lde -- $HOME/.local to see its permissions and ACLs" || return 1
  [[ ! -e "$DEST" ]] || { echo "cloned despite the ACL refusal"; return 1; }
  cleanup_test_env
}

# Round 4, item 1: a directory probe passing does not prove a plain file
# can be created too.
test_a_file_probe_failure_stops_before_the_clone() {
  setup
  mkdir -p "$HOME/.local"
  mock_command_script mktemp <<'EOF2'
if [ "$1" = "-d" ]; then
  exec /usr/bin/mktemp "$@"
fi
echo "mktemp: cannot create file: Operation not permitted" >&2
exit 1
EOF2
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$HOME/.local refuses new files (mktemp: cannot create file: Operation not permitted)" || return 1
  assert_contains "$out" "ls -lde -- $HOME/.local to see its permissions and ACLs" || return 1
  [[ -z "$(ls -A "$HOME/.local" 2>/dev/null)" ]] || { echo "a probe was left behind"; return 1; }
  [[ ! -e "$DEST" ]] || { echo "cloned despite the file-probe refusal"; return 1; }
  cleanup_test_env
}

# A dangling symlink at $HOME/.local/share -e is false for one too, so
# without a dedicated check the ancestor walk would read it as "does not
# exist" and walk straight past it to $HOME/.local, instead of reporting
# the broken link itself.
test_a_dangling_data_home_symlink_stops_before_the_clone() {
  setup
  mkdir -p "$HOME/.local"
  ln -s "$HOME/gone" "$HOME/.local/share"
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$HOME/.local/share is a symlink that cannot be resolved (its target $HOME/gone is missing, or the links form a loop). Fix or remove the link." || return 1
  [[ ! -e "$DEST" ]] || { echo "cloned despite the dangling symlink"; return 1; }
  cleanup_test_env
}

# $HOME/.local exists as a plain file, so mkdir -p could never create
# $HOME/.local/share under it; that must be reported outright, before any
# write test.
test_a_file_blocking_the_data_home_ancestor_stops_before_the_clone() {
  setup
  : > "$HOME/.local"
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$HOME/.local is a file, not a folder, so teeup cannot create $HOME/.local/share. Move it aside, then try again." || return 1
  [[ ! -e "$DEST" ]] || { echo "cloned despite the blocking file"; return 1; }
  cleanup_test_env
}

# Round 3, item 2: every path inside a "Run: ..." command is shell-quoted
# with printf %q, so a $HOME with a space or a metacharacter in it (a real
# possibility: macOS usernames can contain spaces) can be pasted straight
# into a terminal. A space, a $ and a quote in HOME, same as the piped
# install test above.
test_a_tricky_home_quotes_the_fix_command() {
  setup
  export HOME="$TEST_HOME/it's a \$home"
  mkdir -p "$HOME/.local"
  chmod 555 "$HOME/.local"
  DEST="$HOME/.local/share/teeup"
  local expected
  printf -v expected '%q' "$HOME/.local"
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  chmod u+w "$HOME/.local"
  assert_failure "$rc" || return 1
  assert_contains "$out" "ls -lde -- $expected" || return 1
  [[ ! -e "$DEST" ]] || { echo "cloned despite the locked ancestor"; return 1; }
  cleanup_test_env
}

test_dry_run_does_not_probe_the_data_home() {
  setup
  mock_command mktemp 1 "boom"
  local out rc=0
  out="$(run_installer --dry-run 2>&1)" || rc=$?
  assert_equals "0" "$rc" "$out" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "mktemp" "a dry run must not probe with mktemp" || return 1
  cleanup_test_env
}

# #1: there is no ownership test-hook in a standalone POSIX script (the
# sandbox has no way to really hand $HOME/.local to another user), so the
# "owned by someone else" chown wording is proven non-recursive and
# group-aware in tests/lib/core.sh instead (the same message text, kept
# aligned by test_data_home_check_matches_the_bootstrap_wording below);
# this only has to carry the test for #2.

# #2: a probe teeup creates must never be left behind silently -- a
# cleanup that itself fails is reported, not swallowed as success.
test_a_probe_cleanup_failure_stops_before_the_clone() {
  setup
  mkdir -p "$HOME/.local"
  mock_command_script rmdir <<'EOF2'
echo "rmdir: cannot remove: Operation not permitted" >&2
exit 1
EOF2
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$HOME/.local: teeup created" || return 1
  assert_contains "$out" "but could not remove it. Remove it by hand: rm -rf -- " || return 1
  [[ ! -e "$DEST" ]] || { echo "cloned despite the cleanup failure"; return 1; }
  cleanup_test_env
}

# #7: a directory can be writable but not searchable (mode 0200) --
# nothing can be created inside it either way, so a dry run must require
# -x too, not just -w.
test_dry_run_requires_both_w_and_x() {
  setup
  mkdir -p "$HOME/.local"
  chmod 200 "$HOME/.local"
  local out rc=0
  out="$(run_installer --dry-run 2>&1)" || rc=$?
  chmod u+rwx "$HOME/.local"
  assert_failure "$rc" || return 1
  assert_contains "$out" "$HOME/.local is not writable" || return 1
  assert_contains "$out" "chmod u+wx -- $HOME/.local" || return 1
  cleanup_test_env
}

# #12: before any other work, a dangling or looping $dest must be treated
# as an existing collision, same as a real non-checkout directory would
# be -- otherwise -e "$dest" and -e "$dest/.git" are both false for it,
# and the installer would start installing the Command Line Tools before
# git clone finally fails on it.
test_a_dangling_dest_symlink_is_an_existing_collision() {
  setup
  mkdir -p "$(dirname "$DEST")"
  ln -s "$TEST_HOME/nowhere" "$DEST"
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$DEST is a symlink, and not to a teeup checkout" || return 1
  [[ ! -e "$HOME/bootstrap.out" ]] || { echo "bootstrap ran despite the dangling symlink"; return 1; }
  cleanup_test_env
}

test_a_dangling_dest_symlink_is_caught_in_a_dry_run_too() {
  setup
  mkdir -p "$(dirname "$DEST")"
  ln -s "$TEST_HOME/nowhere" "$DEST"
  local out rc=0
  out="$(run_installer --dry-run 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$DEST is a symlink, and not to a teeup checkout" || return 1
  cleanup_test_env
}

# A symlink at $dest that resolves to a real directory, but not a teeup
# checkout, is also the new symlink collision -- #12 names this case
# explicitly, so it is reported uniformly with the dangling and looping
# cases, not left to the older "exists and is not a git checkout" message
# (which is for a real, non-symlink directory at $dest).
test_a_dest_symlink_to_a_non_checkout_directory_is_also_a_collision() {
  setup
  mkdir -p "$(dirname "$DEST")" "$TEST_HOME/elsewhere"
  : > "$TEST_HOME/elsewhere/notes.txt"
  ln -s "$TEST_HOME/elsewhere" "$DEST"
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$DEST is a symlink, and not to a teeup checkout" || return 1
  cleanup_test_env
}

# (test_an_existing_directory_that_is_not_a_checkout_is_refused, above,
# already proves a real, non-symlink directory at $dest keeps that older
# message -- the new check is specific to $dest being a symlink.)

# tests/bootstrap.sh and tests/lib/core.sh exercise writable_dirs_check
# (lib/core.sh) directly; this only checks the two copies describe the same
# problem and the same fix in the same words, since install.sh cannot
# source lib/core.sh and keeps its own small copy.
test_data_home_check_matches_the_bootstrap_wording() {
  local cap="$TEEUP_PATH/lib/core.sh" s
  for s in "is not writable" "does not allow new folders" "refuses new folders" \
           "refuses new files" "does not let you create" "its permissions and ACLs" \
           "ls -lde --" "chmod u+wx --" "sudo chown --" "\$(id -gn)" \
           "is a symlink that cannot be resolved" "Fix or remove the link" \
           "could not remove it"; do
    grep -qF "$s" "$cap" || { echo "lib/core.sh no longer says: $s"; return 1; }
    grep -qF "$s" "$INSTALLER" || { echo "install.sh no longer says: $s"; return 1; }
  done
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
  mock_command pgrep 0 "123"
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

# A cancelled dialog: Apple's installer is gone and the tools never arrive,
# so the wait ends and the installer stops with the rerun instructions.
test_a_cancelled_clt_dialog_stops_the_wait() {
  setup
  mock_missing_clt
  mock_command softwareupdate 0 "No new software available."
  mock_command pgrep 1 ""
  mock_command sleep 0 ""
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "The Command Line Tools are still missing" || return 1
  [[ ! -e "$DEST" ]] || { echo "cloned without the tools"; return 1; }
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

# mock_proxy_network: git clone fails with the error a re-signing proxy
# causes unless GIT_SSL_CAINFO names a bundle. The bundle git was given is
# copied to $HOME/used-bundle.pem, so a test can read it after the installer
# deletes it. Every other git call goes to the real git.
mock_proxy_network() {
  local real_git
  real_git="$(command -v git)"
  mock_command_script git <<EOF2
if [ "\$1" = "clone" ]; then
  if [ -z "\${GIT_SSL_CAINFO:-}" ]; then
    echo "fatal: unable to access 'https://github.com/systemhalted/teeup.sh/': SSL certificate problem: self signed certificate in certificate chain" >&2
    exit 128
  fi
  cp "\$GIT_SSL_CAINFO" "\$HOME/used-bundle.pem"
fi
exec "$real_git" "\$@"
EOF2
}

# mock_company_keychain <trusted:yes|no|broken>: security and plutil as on
# a Mac whose System keychain holds the company root (hash AAAA...) and a
# second certificate nobody trusts (hash BBBB...). With "no", there are no
# admin trust settings at all, and security says so as macOS does. With
# "broken", the trust settings list the root but their export fails.
mock_company_keychain() {
  local trusted="$1" a b
  a="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  b="BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
  mock_command_script security <<EOF2
case "\$1" in
  dump-trust-settings)
    [ "$trusted" != "no" ] || { echo "SecTrustSettingsCopyCertificates: No Trust Settings were found."; exit 1; }
    printf '%s\n' 'Number of trusted certs = 1' 'Cert 0: Company Root'
    ;;
  trust-settings-export)
    [ "$trusted" = "yes" ] || { echo "SecTrustSettingsCreateExternalRepresentation: error" >&2; exit 1; }
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
      '<plist version="1.0"><dict><key>trustList</key><dict>' \
      '<key>$a</key><dict><key>trustSettings</key><array/></dict>' \
      '</dict></dict></plist>' > "\$3"
    ;;
  find-certificate)
    case "\$*" in
      *SystemRootCertificates*)
        printf '%s\n' '-----BEGIN CERTIFICATE-----' 'APPLE-ROOT' '-----END CERTIFICATE-----' ;;
      *)
        printf '%s\n' 'SHA-1 hash: $a' '-----BEGIN CERTIFICATE-----' 'COMPANY-ROOT' '-----END CERTIFICATE-----' \
          'SHA-1 hash: $b' '-----BEGIN CERTIFICATE-----' 'UNTRUSTED' '-----END CERTIFICATE-----' ;;
    esac
    ;;
esac
EOF2
  mock_command_script plutil <<'EOF2'
cp "$5" "$4"
EOF2
}

# no_temporary_bundle -> fails when the installer left a teeup-ca file in TMPDIR.
no_temporary_bundle() {
  local f
  for f in "${TMPDIR:-/tmp}"/teeup-ca*; do
    [[ -e "$f" ]] && { echo "the temporary bundle was left behind: $f"; return 1; }
  done
  return 0
}

test_a_proxy_network_clones_with_the_company_certificates() {
  setup
  mock_proxy_network
  mock_company_keychain yes
  local out rc=0 bundle
  out="$(run_installer 2>&1)" || rc=$?
  assert_equals "0" "$rc" "$out" || return 1
  assert_contains "$out" "SSL certificate problem" "git's own error is shown" || return 1
  assert_contains "$out" "This network re-signs HTTPS. Cloning again with the certificates an administrator trusts in the System keychain." || return 1
  bundle="$(cat "$HOME/used-bundle.pem")"
  assert_contains "$bundle" "APPLE-ROOT" "the public roots" || return 1
  assert_contains "$bundle" "COMPANY-ROOT" "the trusted company root" || return 1
  assert_not_contains "$bundle" "UNTRUSTED" "a certificate without admin trust is left out" || return 1
  assert_contains "$(cat "$HOME/bootstrap.out")" "version=0.2.0-beta" || return 1
  no_temporary_bundle || return 1
  cleanup_test_env
}

test_a_proxy_network_without_a_trusted_root_says_how_to_trust_it() {
  setup
  mock_proxy_network
  mock_company_keychain no
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "no company certificate is trusted in the System keychain" || return 1
  assert_contains "$out" "sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Downloads/company-root.cer" || return 1
  [[ ! -e "$DEST" ]] || { echo "a failed install left a checkout"; return 1; }
  [[ ! -e "$HOME/bootstrap.out" ]] || { echo "bootstrap ran"; return 1; }
  no_temporary_bundle || return 1
  cleanup_test_env
}

test_a_failed_trust_export_names_the_step_not_the_certificate() {
  setup
  mock_proxy_network
  mock_company_keychain broken
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Could not export the administrator certificate trust settings." || return 1
  assert_contains "$out" "the installer could not make a certificate bundle" || return 1
  assert_not_contains "$out" "add-trusted-cert" "the certificate is trusted already" || return 1
  [[ ! -e "$DEST" ]] || { echo "a failed install left a checkout"; return 1; }
  no_temporary_bundle || return 1
  cleanup_test_env
}

test_a_clone_failure_without_a_certificate_error_stops() {
  setup
  export TEEUP_INSTALL_REPO="$TEST_HOME/no-such-repo.git"
  mock_company_keychain yes
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "git clone of $TEST_HOME/no-such-repo.git failed." || return 1
  assert_not_contains "$out" "re-signs HTTPS" "no certificate retry" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "security" "the keychain is not read" || return 1
  cleanup_test_env
}

# install.sh repeats the two awk programs of lib/certs.sh, because it runs
# before teeup is on disk. The two copies must agree, up to the line that
# names the input files.
test_certificate_filters_match_lib_certs() {
  setup
  local prog lib inst
  for prog in "awk 'BEGIN { RS = \"<\" }" 'awk -v hashes="$hashes"'; do
    lib="$(awk -v start="$prog" 'index($0, start) { on = 1 } on && /^  '"'"' / { exit } on { print }' "$TEEUP_PATH/lib/certs.sh")"
    inst="$(awk -v start="$prog" 'index($0, start) { on = 1 } on && /^  '"'"' / { exit } on { print }' "$INSTALLER")"
    [[ -n "$lib" ]] || { echo "lib/certs.sh no longer has: $prog"; return 1; }
    assert_equals "$lib" "$inst" "install.sh's copy of: $prog" || return 1
  done
  cleanup_test_env
}

# The installer, not the one-liner, starts the new zsh, so a failed bootstrap
# (or a failed download) never replaces the user's shell. A captured run has
# no terminal on stdout, so it never starts one either.
test_a_failed_bootstrap_keeps_its_status_and_starts_no_shell() {
  setup
  mock_command zsh 0 ""
  local out rc=0
  out="$(FAKE_BOOTSTRAP_RC=3 run_installer 2>&1)" || rc=$?
  assert_equals "3" "$rc" "$out" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "zsh" "no new shell after a failure" || return 1
  cleanup_test_env
}

test_a_captured_run_starts_no_shell() {
  setup
  mock_command zsh 0 ""
  local out rc=0
  out="$(run_installer 2>&1)" || rc=$?
  assert_equals "0" "$rc" "$out" || return 1
  assert_file_exists "$HOME/bootstrap.out" "bootstrap ran" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "zsh" "stdout is not a terminal" || return 1
  cleanup_test_env
}

echo "install.sh"
run_test "fresh install checks out the newest release and bootstraps" test_fresh_install_checks_out_the_newest_release_and_bootstraps
run_test "piped install passes its arguments to bootstrap" test_piped_install_passes_its_arguments_to_bootstrap
run_test "a partly downloaded script does nothing" test_a_partly_downloaded_script_does_nothing
run_test "an existing checkout is not cloned again" test_an_existing_checkout_is_not_cloned_again
run_test "an existing directory that is not a checkout is refused" test_an_existing_directory_that_is_not_a_checkout_is_refused
run_test "an unrelated git checkout is refused" test_an_unrelated_git_checkout_is_refused
run_test "root is refused" test_root_is_refused
run_test "an unwritable data home stops before the clone" test_an_unwritable_data_home_stops_before_the_clone
run_test "an ACL-denied data home stops before the clone" test_an_acl_denied_data_home_stops_before_the_clone
run_test "a file probe failure stops before the clone" test_a_file_probe_failure_stops_before_the_clone
run_test "a dangling data home symlink stops before the clone" test_a_dangling_data_home_symlink_stops_before_the_clone
run_test "a file blocking the data home ancestor stops before the clone" test_a_file_blocking_the_data_home_ancestor_stops_before_the_clone
run_test "a tricky home quotes the fix command" test_a_tricky_home_quotes_the_fix_command
run_test "dry run does not probe the data home" test_dry_run_does_not_probe_the_data_home
run_test "a probe cleanup failure stops before the clone" test_a_probe_cleanup_failure_stops_before_the_clone
run_test "dry run requires both w and x" test_dry_run_requires_both_w_and_x
run_test "a dangling dest symlink is an existing collision" test_a_dangling_dest_symlink_is_an_existing_collision
run_test "a dangling dest symlink is caught in a dry run too" test_a_dangling_dest_symlink_is_caught_in_a_dry_run_too
run_test "a dest symlink to a non-checkout directory is also a collision" test_a_dest_symlink_to_a_non_checkout_directory_is_also_a_collision
run_test "data home check matches the bootstrap wording" test_data_home_check_matches_the_bootstrap_wording
run_test "a Mac is required" test_a_mac_is_required
run_test "missing CLT installs through softwareupdate" test_missing_clt_installs_through_softwareupdate
run_test "missing CLT without a label waits for the dialog" test_missing_clt_without_a_label_waits_for_the_dialog
run_test "a cancelled CLT dialog stops the wait" test_a_cancelled_clt_dialog_stops_the_wait
run_test "dry run writes nothing" test_dry_run_writes_nothing
run_test "CLT marker and label match the capability" test_clt_marker_and_label_match_the_capability
run_test "a proxy network clones with the company certificates" test_a_proxy_network_clones_with_the_company_certificates
run_test "a proxy network without a trusted root says how to trust it" test_a_proxy_network_without_a_trusted_root_says_how_to_trust_it
run_test "a failed trust export names the step, not the certificate" test_a_failed_trust_export_names_the_step_not_the_certificate
run_test "a clone failure without a certificate error stops" test_a_clone_failure_without_a_certificate_error_stops
run_test "a failed bootstrap keeps its status and starts no shell" test_a_failed_bootstrap_keeps_its_status_and_starts_no_shell
run_test "a captured run starts no shell" test_a_captured_run_starts_no_shell
run_test "certificate filters match lib/certs.sh" test_certificate_filters_match_lib_certs
print_summary
