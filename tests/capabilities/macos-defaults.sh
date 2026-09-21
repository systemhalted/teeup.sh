#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command killall 0 ""
  mock_defaults_absent
  TEEUP="$TEEUP_PATH/bin/teeup"
  RECORDS="$TEST_HOME/.local/state/teeup/defaults"
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

mock_defaults_absent() {
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) exit 1 ;;
  *) exit 0 ;;
esac
EOF2
}

test_configure_writes_every_preference() {
  setup
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  local log_body
  log_body="$(cat "$MOCK_LOG")"
  assert_contains "$log_body" "defaults write NSGlobalDomain AppleShowAllExtensions -bool true" || return 1
  assert_contains "$log_body" "defaults write com.apple.finder FXPreferredViewStyle -string Nlsv" || return 1
  assert_contains "$log_body" "defaults write NSGlobalDomain KeyRepeat -int 2" || return 1
  assert_contains "$log_body" "defaults write NSGlobalDomain InitialKeyRepeat -int 15" || return 1
  assert_contains "$log_body" "defaults write com.apple.dock autohide -bool true" || return 1
  assert_contains "$log_body" "defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true" || return 1
  assert_contains "$log_body" "defaults write com.apple.screencapture location -string $TEST_HOME/Screenshots" || return 1
  assert_contains "$log_body" "killall Finder" || return 1
  assert_contains "$log_body" "killall Dock" || return 1
  cleanup_test_env
}

test_configure_records_every_key_and_creates_the_screenshots_dir() {
  setup
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  assert_dir_exists "$TEST_HOME/Screenshots" || return 1
  assert_equals "absent" "$(cat "$RECORDS/NSGlobalDomain.AppleShowAllExtensions")" || return 1
  assert_equals "absent" "$(cat "$RECORDS/com.apple.dock.autohide")" || return 1
  assert_equals "16" "$(find "$RECORDS" -type f | wc -l | tr -d ' ')" "one record per preference" || return 1
  cleanup_test_env
}

test_configure_records_a_prior_value() {
  setup
  mock_defaults_db
  seed_default com.apple.dock autohide boolean 1
  seed_default NSGlobalDomain KeyRepeat integer 6
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  assert_equals "-bool:true" "$(cat "$RECORDS/com.apple.dock.autohide")" || return 1
  assert_equals "-int:6" "$(cat "$RECORDS/NSGlobalDomain.KeyRepeat")" || return 1
  cleanup_test_env
}

db_snapshot() {
  local f
  for f in "$DDB"/*; do
    [[ -f "$f" ]] || continue
    printf '%s=%s|' "${f##*/}" "$(tr '\n' ' ' < "$f")"
  done
}

test_remove_puts_every_prior_value_back_with_its_type() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_defaults_db
  seed_default NSGlobalDomain AppleShowAllExtensions boolean false
  seed_default NSGlobalDomain KeyRepeat integer 6
  seed_default NSGlobalDomain InitialKeyRepeat float 25.5
  seed_default com.apple.screencapture location string "/Users/ada/My Shots: 2026"
  seed_default com.apple.finder FXPreferredViewStyle string icnv
  seed_default com.apple.finder AppleShowAllFiles string YES
  local before rc=0
  before="$(db_snapshot)"
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  DRY_RUN=false cap_run macos-defaults remove >/dev/null 2>&1 || rc=$?
  assert_success "$rc" || return 1
  assert_equals "$before" "$(db_snapshot)" "the defaults database is back to what it was" || return 1
  assert_equals "0" "$(find "$RECORDS" -type f | wc -l | tr -d ' ')" "every record is consumed" || return 1
  cleanup_test_env
}

test_remove_continues_past_a_failed_restore() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_defaults_db
  seed_default NSGlobalDomain AppleShowAllExtensions boolean false
  seed_default com.apple.dock autohide boolean false
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  local rc=0 out
  out="$(DEFAULTS_FAIL_WRITE=AppleShowAllExtensions DRY_RUN=false cap_run macos-defaults remove 2>&1)" || rc=$?
  # Two properties at once: every later key is still restored (one bad key
  # must not stop the other fifteen), and the removal as a whole reports
  # failure, so cmd_remove keeps the capability marked installed and the user
  # can run it again instead of being told it is gone.
  assert_failure "$rc" "a removal that left preferences behind is not a success" || return 1
  assert_contains "$out" "Could not restore NSGlobalDomain AppleShowAllExtensions" || return 1
  assert_contains "$out" "stays marked installed" || return 1
  assert_equals $'boolean\nfalse' "$(cat "$DDB/com.apple.dock.autohide")" "later keys are still restored" || return 1
  assert_equals "1" "$(find "$RECORDS" -type f | wc -l | tr -d ' ')" "only the failed record remains" || return 1
  cleanup_test_env
}

test_configure_is_idempotent() {
  setup
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  local out
  out="$(DRY_RUN=false "$TEEUP" configure macos-defaults)"
  assert_contains "$out" "Already present: $TEST_HOME/Screenshots" || return 1
  assert_equals "absent" "$(cat "$RECORDS/com.apple.dock.autohide")" "the record is never refreshed" || return 1
  cleanup_test_env
}

test_a_second_configure_writes_nothing_and_restarts_nothing() {
  setup
  mock_defaults_db
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "killall Finder" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "killall Dock" || return 1
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure macos-defaults)"
  assert_not_contains "$(cat "$MOCK_LOG")" "defaults write" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "killall" "Finder and the Dock keep running when nothing changed" || return 1
  assert_contains "$out" "Already set: com.apple.dock autohide" || return 1
  assert_contains "$out" "macOS preferences already set; nothing to restart." || return 1
  cleanup_test_env
}

test_a_dock_change_restarts_only_the_dock() {
  setup
  mock_defaults_db
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  seed_default com.apple.dock autohide boolean 0
  : > "$MOCK_LOG"
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "defaults write com.apple.dock autohide -bool true" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "killall Dock" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "killall Finder" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" configure macos-defaults)"
  assert_contains "$out" "[DRY-RUN] Would execute: defaults write com.apple.dock autohide -bool true" || return 1
  assert_contains "$out" "[DRY-RUN] Would record defaults/com.apple.dock.autohide as absent" || return 1
  [[ ! -d "$RECORDS" ]] || { echo "records written in dry run"; return 1; }
  [[ ! -d "$TEST_HOME/Screenshots" ]] || { echo "Screenshots created in dry run"; return 1; }
  # F1: a dry run must never claim the preferences were applied.
  assert_not_contains "$out" "macOS preferences applied" || return 1
  cleanup_test_env
}

test_remove_restores_every_key() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  : > "$MOCK_LOG"
  DRY_RUN=false cap_run macos-defaults remove >/dev/null
  local log_body
  log_body="$(cat "$MOCK_LOG")"
  assert_contains "$log_body" "defaults delete com.apple.dock autohide" || return 1
  assert_contains "$log_body" "defaults delete com.apple.screencapture location" || return 1
  assert_equals "0" "$(find "$RECORDS" -type f | wc -l | tr -d ' ')" "every record is consumed" || return 1
  cleanup_test_env
}

test_remove_rewrites_a_recorded_value() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mkdir -p "$RECORDS"
  printf -- '-bool:true\n' > "$RECORDS/com.apple.dock.autohide"
  DRY_RUN=false cap_run macos-defaults remove >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "defaults write com.apple.dock autohide -bool true" || return 1
  cleanup_test_env
}

test_remove_dry_run_does_not_claim_the_preferences_were_restored() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure macos-defaults >/dev/null
  local out
  out="$(DRY_RUN=true cap_run macos-defaults remove 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: killall Finder" || return 1
  assert_not_contains "$out" "macOS preferences restored" || return 1
  cleanup_test_env
}

echo "capabilities/macos-defaults"
run_test "configure writes every preference" test_configure_writes_every_preference
run_test "configure records every key and creates ~/Screenshots" test_configure_records_every_key_and_creates_the_screenshots_dir
run_test "configure records a prior value" test_configure_records_a_prior_value
run_test "configure is idempotent" test_configure_is_idempotent
run_test "a second configure writes nothing and restarts nothing" test_a_second_configure_writes_nothing_and_restarts_nothing
run_test "a Dock change restarts only the Dock" test_a_dock_change_restarts_only_the_dock
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "remove restores every key" test_remove_restores_every_key
run_test "remove rewrites a recorded value" test_remove_rewrites_a_recorded_value
run_test "remove dry run does not claim the preferences were restored" test_remove_dry_run_does_not_claim_the_preferences_were_restored
run_test "remove puts every prior value back with its type" test_remove_puts_every_prior_value_back_with_its_type
run_test "remove continues past a failed restore" test_remove_continues_past_a_failed_restore
print_summary
