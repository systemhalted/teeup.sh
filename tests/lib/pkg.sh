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
  # shellcheck disable=SC2034
  DRY_RUN=true
  local out
  out="$(pkg_install ripgrep)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install ripgrep" || return 1
  cleanup_test_env
}

test_pkg_install_uses_sudo_port_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  # shellcheck disable=SC2034
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
  out="$(cask_install wezterm)"
  assert_contains "$out" "Casks are not available with MacPorts" || return 1
  cleanup_test_env
}

test_cask_install_dry_run() {
  setup
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; esac
EOF2
  # shellcheck disable=SC2034
  DRY_RUN=true
  local out
  out="$(cask_install wezterm)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask wezterm" || return 1
  cleanup_test_env
}

test_backend_prepare_installs_homebrew_when_missing() {
  setup
  # shellcheck disable=SC2034
  DRY_RUN=true
  local out
  out="$(pkg_backend_prepare)"
  assert_contains "$out" "Homebrew/install/HEAD/install.sh" || return 1
  cleanup_test_env
}

test_run_privileged_prefixes_sudo() {
  setup
  # shellcheck disable=SC2034
  DRY_RUN=true
  assert_contains "$(run_privileged port selfupdate)" "sudo port selfupdate" || return 1
  cleanup_test_env
}

echo "lib/pkg.sh"
run_test "backend defaults to homebrew on modern macOS" test_backend_defaults_to_homebrew_on_modern_macos
run_test "backend is macports on macOS 12" test_backend_is_macports_on_macos_12
run_test "backend honours answer" test_backend_honours_answer
run_test "intel homebrew prefix" test_intel_homebrew_prefix
run_test "pkg_install skips when command on PATH" test_pkg_install_skips_when_command_on_path
run_test "pkg_install calls brew when missing" test_pkg_install_calls_brew_when_missing
run_test "pkg_install uses sudo port on macports" test_pkg_install_uses_sudo_port_on_macports
run_test "candidates map bash-completion" test_candidates_map_bash_completion_on_homebrew
run_test "cask_install skipped on macports" test_cask_install_skipped_on_macports
run_test "cask_install dry run" test_cask_install_dry_run
run_test "backend prepare installs homebrew" test_backend_prepare_installs_homebrew_when_missing
run_test "run_privileged prefixes sudo" test_run_privileged_prefixes_sudo
print_summary
