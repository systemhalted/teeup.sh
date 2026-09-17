#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false
  unset TEEUP_PKG_BACKEND TEEUP_PACKAGE_MANAGER
}

test_backend_defaults_to_homebrew_on_modern_macos() {
  setup
  unset TEEUP_PKG_PREFIX
  assert_equals "homebrew" "$(pkg_backend)" || return 1
  assert_equals "/opt/homebrew" "$(pkg_prefix)" || return 1
  cleanup_test_env
}

test_backend_is_macports_on_macos_12() {
  setup
  unset TEEUP_PKG_PREFIX
  mock_command sw_vers 0 "12.7.1"
  assert_equals "macports" "$(pkg_backend)" || return 1
  assert_equals "/opt/local" "$(pkg_prefix)" || return 1
  cleanup_test_env
}

test_backend_honours_answer() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  assert_equals "macports" "$(pkg_backend)" || return 1
  cleanup_test_env
}

test_invalid_backend_answer_dies() {
  setup
  export TEEUP_PACKAGE_MANAGER=apt
  local rc=0 out
  out="$( (pkg_install ripgrep) 2>&1 )" || rc=$?
  assert_failure "$rc" "invalid backend must fail the caller" || return 1
  assert_contains "$out" "Unknown TEEUP_PACKAGE_MANAGER 'apt'" || return 1
  cleanup_test_env
}

test_intel_homebrew_prefix() {
  setup
  unset TEEUP_PKG_PREFIX
  mock_command_script uname <<'EOF2'
case "$1" in -m) echo x86_64 ;; *) echo Darwin ;; esac
EOF2
  assert_equals "/usr/local" "$(pkg_prefix)" || return 1
  cleanup_test_env
}

test_pkg_install_skips_when_command_on_path() {
  setup
  mock_command jq 0 ""
  mock_command brew 0 ""
  local out
  out="$(pkg_install jq jq)"
  assert_contains "$out" "Already available on PATH: jq" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew install" || return 1
  cleanup_test_env
}

test_pkg_install_calls_brew_when_missing() {
  setup
  mock_command_script brew <<'EOF2'
case "$1" in
  list) exit 1 ;;
  install) exit 0 ;;
esac
EOF2
  DRY_RUN=true
  local out
  out="$(pkg_install ripgrep)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install ripgrep" || return 1
  # F1: a dry run must never claim the package was installed.
  assert_not_contains "$out" "Installed ripgrep" "dry run must not claim an install that did not happen" || return 1
  cleanup_test_env
}

test_pkg_install_real_run_wording_is_unchanged() {
  setup
  mock_command_script brew <<'EOF2'
case "$1" in
  list) exit 1 ;;
  install) exit 0 ;;
esac
EOF2
  DRY_RUN=false
  local out
  out="$(pkg_install ripgrep)"
  assert_contains "$out" "✅ Installed ripgrep (Homebrew)" "the real-run wording must stay exactly what it is today" || return 1
  cleanup_test_env
}

test_pkg_install_uses_sudo_port_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  DRY_RUN=true
  local out
  out="$(pkg_install ripgrep)"
  assert_contains "$out" "[DRY-RUN] Would execute: sudo port install ripgrep" || return 1
  cleanup_test_env
}

test_candidates_map_bash_completion_on_homebrew() {
  setup
  assert_equals "bash-completion@2 bash-completion" "$(package_candidates bash-completion)" || return 1
  cleanup_test_env
}

test_cask_install_skipped_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  local out
  out="$(cask_install wezterm 2>&1)"
  assert_contains "$out" "Casks are not available with MacPorts" || return 1
  cleanup_test_env
}

test_cask_install_dry_run() {
  setup
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; esac
EOF2
  DRY_RUN=true
  local out
  out="$(cask_install wezterm)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask wezterm" || return 1
  # F1: a dry run must never claim the cask was installed.
  assert_not_contains "$out" "Installed wezterm" "dry run must not claim an install that did not happen" || return 1
  cleanup_test_env
}

test_backend_prepare_installs_homebrew_when_missing() {
  setup
  DRY_RUN=true
  local out
  out="$(pkg_backend_prepare)"
  assert_contains "$out" "Homebrew/install/HEAD/install.sh" || return 1
  cleanup_test_env
}

test_backend_prepare_fails_when_installer_fails() {
  setup
  export TEEUP_TEST_MISSING=brew
  mock_command curl 1 ""
  DRY_RUN=false
  local rc=0 out
  out="$(pkg_backend_prepare 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Homebrew installation failed" || return 1
  cleanup_test_env
}

test_run_privileged_prefixes_sudo() {
  setup
  # shellcheck disable=SC2034
  DRY_RUN=true
  assert_contains "$(run_privileged port selfupdate)" "sudo port selfupdate" || return 1
  cleanup_test_env
}

test_cask_install_dies_on_invalid_backend() {
  setup
  export TEEUP_PACKAGE_MANAGER=apt
  local rc=0 out
  out="$( (cask_install wezterm) 2>&1 )" || rc=$?
  assert_failure "$rc" "invalid backend must fail the caller" || return 1
  assert_contains "$out" "Unknown TEEUP_PACKAGE_MANAGER 'apt'" || return 1
  cleanup_test_env
}

echo "lib/pkg.sh"
run_test "backend defaults to homebrew on modern macOS" test_backend_defaults_to_homebrew_on_modern_macos
run_test "backend is macports on macOS 12" test_backend_is_macports_on_macos_12
run_test "backend honours answer" test_backend_honours_answer
run_test "invalid backend answer dies" test_invalid_backend_answer_dies
run_test "intel homebrew prefix" test_intel_homebrew_prefix
run_test "pkg_install skips when command on PATH" test_pkg_install_skips_when_command_on_path
run_test "pkg_install calls brew when missing" test_pkg_install_calls_brew_when_missing
run_test "pkg_install real-run wording is unchanged" test_pkg_install_real_run_wording_is_unchanged
run_test "pkg_install uses sudo port on macports" test_pkg_install_uses_sudo_port_on_macports
run_test "candidates map bash-completion" test_candidates_map_bash_completion_on_homebrew
run_test "cask_install skipped on macports" test_cask_install_skipped_on_macports
run_test "cask_install dry run" test_cask_install_dry_run
run_test "backend prepare installs homebrew" test_backend_prepare_installs_homebrew_when_missing
run_test "backend prepare fails when installer fails" test_backend_prepare_fails_when_installer_fails
run_test "run_privileged prefixes sudo" test_run_privileged_prefixes_sudo
run_test "cask_install dies on invalid backend" test_cask_install_dies_on_invalid_backend
print_summary
