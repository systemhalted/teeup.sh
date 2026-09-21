#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false
}

# defaults read exits 1 for every key: a fresh Mac that has never set them.
mock_defaults_absent() {
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) exit 1 ;;
  *) exit 0 ;;
esac
EOF2
}

# A stateful defaults database. Each "<domain>.<key>" file holds the type
# defaults(1) reports on its first line and the value after it. `read` prints
# what the real command prints for a scalar (a boolean as 1 or 0), `read-type`
# prints "Type is <type>", and `write` accepts only what defaults(1) documents
# (-bool TRUE/FALSE/YES/NO in any case, a whole number for -int), failing like
# the real command otherwise. DEFAULTS_FAIL_WRITE names one key whose write
# fails, to simulate a restore that cannot complete.
mock_defaults_db() {
  export DDB="$TEST_HOME/defaults-db"
  mkdir -p "$DDB"
  mock_command_script defaults <<'EOF2'
op="$1"; shift
f="$DDB/$1.$2"
case "$op" in
  read)
    [ -f "$f" ] || exit 1
    t="$(head -1 "$f")"; v="$(tail -n +2 "$f")"
    if [ "$t" = boolean ]; then
      case "$v" in [Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|1) echo 1 ;; *) echo 0 ;; esac
    else
      printf '%s\n' "$v"
    fi
    ;;
  read-type) [ -f "$f" ] || exit 1; echo "Type is $(head -1 "$f")" ;;
  write)
    [ "$2" = "${DEFAULTS_FAIL_WRITE:-}" ] && exit 1
    case "$3" in
      -bool) t=boolean
        case "$4" in [Tt][Rr][Uu][Ee]|[Ff][Aa][Ll][Ss][Ee]|[Yy][Ee][Ss]|[Nn][Oo]) ;; *) echo "Rep argument is not a boolean" >&2; exit 1 ;; esac ;;
      -int) t=integer
        case "$4" in ''|*[!0-9-]*) echo "Rep argument is not an integer" >&2; exit 1 ;; esac ;;
      -float) t=float ;;
      -string) t=string ;;
      *) exit 1 ;;
    esac
    printf '%s\n%s\n' "$t" "$4" > "$f"
    ;;
  delete) [ -f "$f" ] || exit 1; rm -f "$f" ;;
esac
EOF2
}

# seed_default <domain> <key> <type> <value>
seed_default() { printf '%s\n%s\n' "$3" "$4" > "$DDB/$1.$2"; }

test_defaults_write_records_absent_and_writes() {
  setup
  mock_defaults_absent
  defaults_write com.apple.finder ShowPathbar -bool true >/dev/null
  local record
  record="$TEST_HOME/.local/state/teeup/defaults/com.apple.finder.ShowPathbar"
  assert_file_exists "$record" || return 1
  assert_equals "absent" "$(cat "$record")" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "defaults write com.apple.finder ShowPathbar -bool true" || return 1
  cleanup_test_env
}

test_defaults_write_records_the_prior_value_and_its_own_type() {
  setup
  mock_defaults_db
  local r="$TEST_HOME/.local/state/teeup/defaults"
  # The type recorded is the prior value's, not the one teeup is about to write.
  seed_default com.apple.dock autohide boolean 0
  seed_default NSGlobalDomain KeyRepeat integer 6
  seed_default NSGlobalDomain InitialKeyRepeat float 25.5
  seed_default com.apple.finder AppleShowAllFiles string YES
  seed_default com.apple.finder FXPreferredViewStyle array '('
  defaults_write com.apple.dock autohide -bool true >/dev/null
  defaults_write NSGlobalDomain KeyRepeat -int 2 >/dev/null
  defaults_write NSGlobalDomain InitialKeyRepeat -int 15 >/dev/null
  defaults_write com.apple.finder AppleShowAllFiles -bool true >/dev/null
  defaults_write com.apple.finder FXPreferredViewStyle -string Nlsv >/dev/null
  assert_equals "-bool:false" "$(cat "$r/com.apple.dock.autohide")" || return 1
  assert_equals "-int:6" "$(cat "$r/NSGlobalDomain.KeyRepeat")" || return 1
  assert_equals "-float:25.5" "$(cat "$r/NSGlobalDomain.InitialKeyRepeat")" || return 1
  assert_equals "-string:YES" "$(cat "$r/com.apple.finder.AppleShowAllFiles")" || return 1
  assert_equals "array:(" "$(cat "$r/com.apple.finder.FXPreferredViewStyle")" || return 1
  cleanup_test_env
}

test_defaults_write_never_overwrites_an_existing_record() {
  setup
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) echo 1; exit 0 ;;
  *) exit 0 ;;
esac
EOF2
  mkdir -p "$TEST_HOME/.local/state/teeup/defaults"
  printf 'absent\n' > "$TEST_HOME/.local/state/teeup/defaults/com.apple.dock.autohide"
  defaults_write com.apple.dock autohide -bool true >/dev/null
  assert_equals "absent" "$(cat "$TEST_HOME/.local/state/teeup/defaults/com.apple.dock.autohide")" || return 1
  cleanup_test_env
}

test_defaults_write_leaves_a_value_already_set_alone() {
  setup
  mock_defaults_db
  seed_default com.apple.dock autohide boolean 1
  seed_default NSGlobalDomain KeyRepeat integer 2
  seed_default com.apple.screencapture location string "/Users/ada/My Shots & more"
  local out
  out="$(
    defaults_write com.apple.dock autohide -bool true
    defaults_write NSGlobalDomain KeyRepeat -int 2
    defaults_write com.apple.screencapture location -string "/Users/ada/My Shots & more"
    defaults_changed com.apple.dock && echo "dock changed"
    echo "changed:[$TEEUP_DEFAULTS_CHANGED]"
  )"
  assert_contains "$out" "Already set: com.apple.dock autohide" || return 1
  assert_contains "$out" "Already set: NSGlobalDomain KeyRepeat" || return 1
  assert_contains "$out" "Already set: com.apple.screencapture location" || return 1
  assert_not_contains "$out" "dock changed" || return 1
  assert_contains "$out" "changed:[ ]" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "defaults write" "nothing was written" || return 1
  assert_equals "-bool:true" "$(cat "$TEST_HOME/.local/state/teeup/defaults/com.apple.dock.autohide")" "the prior value is still recorded" || return 1
  cleanup_test_env
}

test_defaults_write_writes_a_different_value_or_type_and_names_the_domain() {
  setup
  mock_defaults_db
  seed_default com.apple.dock autohide boolean 0
  # The same text under another type is a change: teeup writes a real boolean.
  seed_default com.apple.finder AppleShowAllFiles string true
  local out d
  out="$(
    defaults_write com.apple.dock autohide -bool true
    defaults_write com.apple.finder AppleShowAllFiles -bool true
    defaults_write NSGlobalDomain KeyRepeat -int 2
    for d in com.apple.dock com.apple.finder NSGlobalDomain com.apple.screencapture; do
      if defaults_changed "$d"; then echo "changed:$d"; fi
    done
  )"
  assert_contains "$out" "changed:com.apple.dock" || return 1
  assert_contains "$out" "changed:com.apple.finder" || return 1
  assert_contains "$out" "changed:NSGlobalDomain" "an absent key is written" || return 1
  assert_not_contains "$out" "changed:com.apple.screencapture" || return 1
  assert_equals "$(printf 'boolean\ntrue')" "$(cat "$DDB/com.apple.finder.AppleShowAllFiles")" || return 1
  cleanup_test_env
}

test_defaults_write_dry_run_records_nothing() {
  setup
  mock_defaults_absent
  DRY_RUN=true
  local out
  out="$(defaults_write com.apple.finder ShowPathbar -bool true)"
  assert_contains "$out" "[DRY-RUN] Would execute: defaults write com.apple.finder ShowPathbar -bool true" || return 1
  assert_contains "$out" "[DRY-RUN] Would record defaults/com.apple.finder.ShowPathbar" || return 1
  [[ ! -e "$TEST_HOME/.local/state/teeup/defaults/com.apple.finder.ShowPathbar" ]] || { echo "record written in dry run"; return 1; }
  cleanup_test_env
}

test_defaults_restore_deletes_when_absent() {
  setup
  mock_defaults_absent
  mkdir -p "$TEST_HOME/.local/state/teeup/defaults"
  printf 'absent\n' > "$TEST_HOME/.local/state/teeup/defaults/com.apple.finder.ShowPathbar"
  defaults_restore com.apple.finder ShowPathbar >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "defaults delete com.apple.finder ShowPathbar" || return 1
  [[ ! -e "$TEST_HOME/.local/state/teeup/defaults/com.apple.finder.ShowPathbar" ]] || { echo "record kept"; return 1; }
  cleanup_test_env
}

test_defaults_restore_replays_the_recorded_type() {
  setup
  mock_defaults_db
  local r="$TEST_HOME/.local/state/teeup/defaults"
  mkdir -p "$r"
  printf -- '-bool:false\n' > "$r/com.apple.dock.autohide"
  # A record written before booleans were stored as true/false.
  printf -- '-bool:1\n' > "$r/NSGlobalDomain.AppleShowAllExtensions"
  printf -- '-float:25.5\n' > "$r/NSGlobalDomain.InitialKeyRepeat"
  printf -- '-string:/Users/ada/My Shots: 2026\n' > "$r/com.apple.screencapture.location"
  defaults_restore com.apple.dock autohide >/dev/null
  defaults_restore NSGlobalDomain AppleShowAllExtensions >/dev/null
  defaults_restore NSGlobalDomain InitialKeyRepeat >/dev/null
  defaults_restore com.apple.screencapture location >/dev/null
  local log_body
  log_body="$(cat "$MOCK_LOG")"
  assert_contains "$log_body" "defaults write com.apple.dock autohide -bool false" || return 1
  assert_contains "$log_body" "defaults write NSGlobalDomain AppleShowAllExtensions -bool true" || return 1
  assert_contains "$log_body" "defaults write NSGlobalDomain InitialKeyRepeat -float 25.5" || return 1
  assert_equals $'string\n/Users/ada/My Shots: 2026' "$(cat "$DDB/com.apple.screencapture.location")" || return 1
  assert_equals "0" "$(find "$r" -type f | wc -l | tr -d ' ')" "every replayed record is consumed" || return 1
  cleanup_test_env
}

test_defaults_restore_leaves_an_unreplayable_type_alone() {
  setup
  mock_defaults_db
  local r="$TEST_HOME/.local/state/teeup/defaults" rc=0 out
  mkdir -p "$r"
  printf 'dictionary:{\n' > "$r/com.apple.finder.FXPreferredViewStyle"
  out="$(defaults_restore com.apple.finder FXPreferredViewStyle 2>&1)" || rc=$?
  # A type teeup cannot write back leaves the preference where it is, so the
  # removal is incomplete and the caller has to be able to see that.
  assert_failure "$rc" "an unrestorable key is reported, not passed off as restored" || return 1
  assert_contains "$out" "com.apple.finder FXPreferredViewStyle held a dictionary" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "defaults write" || return 1
  assert_equals "dictionary:{" "$(cat "$r/com.apple.finder.FXPreferredViewStyle")" "the record is kept" || return 1
  cleanup_test_env
}

test_defaults_restore_warns_and_keeps_the_record_when_a_write_fails() {
  setup
  mock_defaults_db
  local r="$TEST_HOME/.local/state/teeup/defaults" rc=0 out
  mkdir -p "$r"
  printf -- '-int:6\n' > "$r/NSGlobalDomain.KeyRepeat"
  export DEFAULTS_FAIL_WRITE=KeyRepeat
  out="$(defaults_restore NSGlobalDomain KeyRepeat 2>&1)" || rc=$?
  unset DEFAULTS_FAIL_WRITE
  assert_failure "$rc" "a failed restore is reported to the caller" || return 1
  assert_contains "$out" "Could not restore NSGlobalDomain KeyRepeat" || return 1
  assert_file_exists "$r/NSGlobalDomain.KeyRepeat" "the record stays for another try" || return 1
  cleanup_test_env
}

test_defaults_restore_without_a_record_is_a_noop() {
  setup
  mock_defaults_absent
  local out
  out="$(defaults_restore com.apple.dock autohide)"
  assert_contains "$out" "No recorded value for com.apple.dock autohide" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "defaults delete" || return 1
  cleanup_test_env
}

test_launchagent_remove_unloads_and_deletes_the_plist() {
  setup
  # bootout exits non-zero when the agent is not loaded; that must not matter.
  mock_command launchctl 3 ""
  local plist rc=0
  plist="$TEST_HOME/Library/LaunchAgents/sh.teeup.test.plist"
  mkdir -p "$(dirname "$plist")"
  printf '<plist/>\n' > "$plist"
  launchagent_remove sh.teeup.test >/dev/null || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "launchctl bootout gui/501 $plist" || return 1
  [[ ! -e "$plist" ]] || { echo "plist survived"; return 1; }
  cleanup_test_env
}

test_launchagent_remove_without_a_plist_is_a_noop() {
  setup
  mock_command launchctl 0 ""
  local out
  out="$(launchagent_remove sh.teeup.test)"
  assert_contains "$out" "nothing to unload" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "launchctl" || return 1
  cleanup_test_env
}

test_launchagent_remove_dry_run_changes_nothing() {
  setup
  mock_command launchctl 0 ""
  local plist out
  plist="$TEST_HOME/Library/LaunchAgents/sh.teeup.test.plist"
  mkdir -p "$(dirname "$plist")"
  printf '<plist/>\n' > "$plist"
  out="$(DRY_RUN=true launchagent_remove sh.teeup.test)"
  assert_contains "$out" "[DRY-RUN] Would execute: launchctl bootout gui/501 $plist" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: rm -f $plist" || return 1
  assert_file_exists "$plist" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "launchctl" || return 1
  cleanup_test_env
}

test_launchagent_install_writes_and_reloads() {
  setup
  mock_command launchctl 0 ""
  launchagent_install sh.teeup.test >/dev/null <<'EOF2'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>Label</key><string>sh.teeup.test</string></dict></plist>
EOF2
  local plist
  plist="$TEST_HOME/Library/LaunchAgents/sh.teeup.test.plist"
  assert_file_exists "$plist" || return 1
  assert_contains "$(cat "$plist")" "sh.teeup.test" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "launchctl bootout gui/501 $plist" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "launchctl bootstrap gui/501 $plist" || return 1
  cleanup_test_env
}

test_launchagent_install_is_idempotent_on_the_file() {
  setup
  mock_command launchctl 0 ""
  local plist body out
  plist="$TEST_HOME/Library/LaunchAgents/sh.teeup.test.plist"
  body='<plist version="1.0"><dict/></plist>'
  printf '%s\n' "$body" | launchagent_install sh.teeup.test >/dev/null
  out="$(printf '%s\n' "$body" | launchagent_install sh.teeup.test)"
  assert_contains "$out" "Already current: $plist" || return 1
  cleanup_test_env
}

test_launchagent_install_dry_run_writes_nothing() {
  setup
  mock_command launchctl 0 ""
  # shellcheck disable=SC2034  # last assignment in the file; read by run_cmd
  DRY_RUN=true
  local out
  out="$(printf '<plist/>\n' | launchagent_install sh.teeup.test)"
  assert_contains "$out" "[DRY-RUN] Would write $TEST_HOME/Library/LaunchAgents/sh.teeup.test.plist" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: launchctl bootstrap gui/501" || return 1
  [[ ! -e "$TEST_HOME/Library/LaunchAgents/sh.teeup.test.plist" ]] || { echo "plist written in dry run"; return 1; }
  cleanup_test_env
}

test_appearance_reads_the_interface_style() {
  setup
  mock_command_script defaults <<'EOF2'
case "$2" in
  -g) echo Dark; exit 0 ;;
esac
exit 1
EOF2
  assert_equals "dark" "$(appearance)" || return 1
  mock_defaults_absent
  assert_equals "light" "$(appearance)" || return 1
  cleanup_test_env
}

echo "lib/macos.sh"
run_test "defaults_write records absent and writes" test_defaults_write_records_absent_and_writes
run_test "defaults_write records the prior value and its own type" test_defaults_write_records_the_prior_value_and_its_own_type
run_test "defaults_write never overwrites a record" test_defaults_write_never_overwrites_an_existing_record
run_test "defaults_write leaves a value already set alone" test_defaults_write_leaves_a_value_already_set_alone
run_test "defaults_write writes a different value or type and names the domain" test_defaults_write_writes_a_different_value_or_type_and_names_the_domain
run_test "defaults_write dry run records nothing" test_defaults_write_dry_run_records_nothing
run_test "defaults_restore deletes when absent" test_defaults_restore_deletes_when_absent
run_test "defaults_restore replays the recorded type" test_defaults_restore_replays_the_recorded_type
run_test "defaults_restore leaves an unreplayable type alone" test_defaults_restore_leaves_an_unreplayable_type_alone
run_test "defaults_restore warns and keeps the record when a write fails" test_defaults_restore_warns_and_keeps_the_record_when_a_write_fails
run_test "defaults_restore without a record is a no-op" test_defaults_restore_without_a_record_is_a_noop
run_test "launchagent_remove unloads and deletes the plist" test_launchagent_remove_unloads_and_deletes_the_plist
run_test "launchagent_remove without a plist is a no-op" test_launchagent_remove_without_a_plist_is_a_noop
run_test "launchagent_remove dry run changes nothing" test_launchagent_remove_dry_run_changes_nothing
run_test "launchagent_install writes and reloads" test_launchagent_install_writes_and_reloads
run_test "launchagent_install is idempotent" test_launchagent_install_is_idempotent_on_the_file
run_test "launchagent_install dry run writes nothing" test_launchagent_install_dry_run_writes_nothing
run_test "appearance reads the interface style" test_appearance_reads_the_interface_style
print_summary
