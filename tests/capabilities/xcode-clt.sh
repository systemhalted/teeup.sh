#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  export DRY_RUN=true
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_present_clt_and_rosetta_are_noops() {
  setup
  mock_command pkgutil 0 "package-id: com.apple.pkg.RosettaUpdateAuto"
  local out
  out="$("$TEEUP" configure xcode-clt; "$TEEUP" install xcode-clt)"
  assert_contains "$out" "Xcode Command Line Tools present." || return 1
  assert_contains "$out" "Rosetta 2 already installed." || return 1
  assert_not_contains "$out" "softwareupdate" || return 1
  cleanup_test_env
}

test_missing_clt_uses_softwareupdate_label() {
  setup
  mock_command xcode-select 2 ""
  mock_command softwareupdate 0 "* Label: Command Line Tools for Xcode-16.2"
  local out
  out="$("$TEEUP" install xcode-clt)"
  assert_contains "$out" "Would execute: touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress" || return 1
  assert_contains "$out" "Would execute: softwareupdate -i Command Line Tools for Xcode-16.2" || return 1
  cleanup_test_env
}

test_missing_clt_falls_back_to_gui() {
  setup
  mock_command xcode-select 2 ""
  mock_command softwareupdate 0 "No new software available."
  local out
  out="$("$TEEUP" install xcode-clt 2>&1)"
  assert_contains "$out" "Would execute: xcode-select --install" || return 1
  cleanup_test_env
}

test_rosetta_installed_on_arm_when_missing() {
  setup
  mock_command pkgutil 1 ""
  local out
  out="$("$TEEUP" install xcode-clt)"
  assert_contains "$out" "Would execute: /usr/sbin/softwareupdate --install-rosetta --agree-to-license" || return 1
  cleanup_test_env
}

test_rosetta_skipped_on_intel() {
  setup
  mock_command_script uname <<'EOF2'
case "$1" in -m) echo x86_64 ;; *) echo Darwin ;; esac
EOF2
  mock_command pkgutil 1 ""
  assert_not_contains "$("$TEEUP" install xcode-clt)" "install-rosetta" || return 1
  cleanup_test_env
}

echo "capabilities/xcode-clt"
run_test "present CLT and Rosetta are no-ops" test_present_clt_and_rosetta_are_noops
run_test "missing CLT uses softwareupdate label" test_missing_clt_uses_softwareupdate_label
run_test "missing CLT falls back to GUI" test_missing_clt_falls_back_to_gui
run_test "Rosetta installed on arm when missing" test_rosetta_installed_on_arm_when_missing
run_test "Rosetta skipped on Intel" test_rosetta_skipped_on_intel
print_summary
