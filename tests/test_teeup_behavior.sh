#!/usr/bin/env bash
# test_teeup_behavior.sh — Behavioral tests for teeup.sh
#
# Usage: ./tests/test_teeup_behavior.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/test_helper.sh"

echo "========================================"
echo "Testing teeup.sh behavior"
echo "========================================"

test_isolated_test_env() {
  setup_test_env
  trap cleanup_test_env RETURN

  assert_dir_exists "$HOME" "Should set HOME to a temp directory"
  assert_file_exists "$ZSHRC" "Should create isolated zshrc"
  assert_file_exists "$ZPROFILE" "Should create isolated zprofile"
  assert_dir_exists "$MOCK_BIN" "Should create mock command directory"
}

test_macos_command_mocks() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_macos_base_commands

  assert_equals "Darwin" "$(uname -s)" "Should mock macOS uname"
  assert_equals "14.6.1" "$(sw_vers -productVersion)" "Should mock macOS version"
}

test_dryrun_legacy_python_does_not_write_config() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_macos_base_commands
  mock_package_manager_commands
  mock_python_commands

  local output
  output=$(DRY_RUN=true USE_UV=false PACKAGE_MANAGER=homebrew INSTALL_DOTFILES=true "$PROJECT_DIR/teeup.sh" --only python 2>&1)

  assert_contains "$output" "[DRY-RUN] Would execute: pipx ensurepath" "Should preview pipx ensurepath"
  assert_contains "$output" "[DRY-RUN] Would execute: pipx install poetry" "Should preview pipx installs"
  assert_equals "" "$(cat "$ZSHRC")" "Dry-run should not write zshrc"
  assert_equals "" "$(cat "$ZPROFILE")" "Dry-run should not write zprofile"
}

test_uv_python_only_skips_package_manager() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_macos_base_commands
  mock_python_commands

  local output
  output=$(DRY_RUN=true USE_UV=true "$PROJECT_DIR/teeup.sh" --only python 2>&1)

  assert_contains "$output" "Skipping package manager setup (RUN_HOMEBREW=false)" "UV-only Python should not require package manager"
}

test_legacy_python_only_enables_package_manager() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_macos_base_commands
  mock_package_manager_commands
  mock_python_commands

  local output
  output=$(DRY_RUN=true USE_UV=false PACKAGE_MANAGER=homebrew "$PROJECT_DIR/teeup.sh" --only python 2>&1)

  assert_contains "$output" "Preparing Homebrew" "Legacy Python should prepare package manager"
}

test_package_backed_modules_enable_package_manager() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_macos_base_commands
  mock_package_manager_commands

  local output
  output=$(DRY_RUN=true PACKAGE_MANAGER=homebrew "$PROJECT_DIR/teeup.sh" --only cli 2>&1)

  assert_contains "$output" "Preparing Homebrew" "CLI module should prepare package manager"
  assert_contains "$output" "[DRY-RUN] Would execute: brew update" "Should preview package-manager update"
}

test_macports_dryrun_warns_when_port_missing() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_macos_base_commands

  local output
  output=$(DRY_RUN=true PACKAGE_MANAGER=macports MACPORTS_PREFIX="$TEST_HOME/no-macports" "$PROJECT_DIR/teeup.sh" --only cli 2>&1)

  assert_contains "$output" "MacPorts is selected but the 'port' command is not available" "Should explain missing MacPorts"
  assert_contains "$output" "Continuing dry-run without MacPorts installed" "Should continue dry-run"
}

test_macports_apps_skip_casks_without_fallback() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_macos_base_commands

  local output
  output=$(DRY_RUN=true PACKAGE_MANAGER=macports MACPORTS_PREFIX="$TEST_HOME/no-macports" "$PROJECT_DIR/teeup.sh" --only apps 2>&1)

  assert_contains "$output" "Skipping GUI app casks in MacPorts mode" "Should skip casks without fallback"
  assert_contains "$output" "bruno (cask; MacPorts mode)" "Should record Bruno as skipped"
  assert_contains "$output" "obsidian (cask; MacPorts mode)" "Should record Obsidian as skipped"
}

test_linux_apt_path() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands

  local output
  output=$(DRY_RUN=true PACKAGE_MANAGER=apt "$PROJECT_DIR/teeup.sh" --only cli 2>&1)

  assert_contains "$output" "Detected Linux" "Should detect Linux platform"
  assert_contains "$output" "Preparing APT" "Should prepare apt on Linux"
  assert_contains "$output" "[DRY-RUN] Would execute: sudo apt-get update" "Should preview apt update"
}

test_linux_apps_skip_by_default() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands

  local output
  output=$(DRY_RUN=true PACKAGE_MANAGER=apt "$PROJECT_DIR/teeup.sh" --only apps 2>&1)

  assert_contains "$output" "Skipping module 'apps'" "Should skip unsupported apps module on Linux"
  assert_contains "$output" "apps (unsupported:" "Should summarize unsupported apps module"
}

test_linux_apps_strict_platform_fails() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands

  local output exit_code
  set +e
  output=$(DRY_RUN=true PACKAGE_MANAGER=apt "$PROJECT_DIR/teeup.sh" --strict-platform --only apps 2>&1)
  exit_code=$?
  set -e

  assert_failure "$exit_code" "Strict platform mode should fail on unsupported module"
  assert_contains "$output" "is not supported on Linux" "Should explain strict-platform failure"
}

test_linux_docker_avoids_colima() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands
  mock_command systemctl 0 ""

  local output
  output=$(DRY_RUN=true PACKAGE_MANAGER=apt "$PROJECT_DIR/teeup.sh" --only docker 2>&1)

  assert_contains "$output" "Docker engine and CLI should now be available" "Should use Linux Docker flow"
  if [[ "$output" == *"colima start"* ]]; then
    echo "FAIL: Linux Docker flow should not attempt colima"
    return 1
  fi
}

test_bash_target_routes_init_to_teeupshrc() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands
  mock_runtime_commands

  local output
  output=$(DRY_RUN=true TARGET_SHELL=bash PACKAGE_MANAGER=apt \
    DOTFILES_DIR="$TEST_HOME/no-dotfiles" "$PROJECT_DIR/teeup.sh" --only ruby 2>&1)

  assert_contains "$output" "Target login shell: bash" "Should report bash as target shell"
  assert_contains "$output" "Would update $TEEUPSHRC with: Added by teeup.sh - rbenv init" "rbenv init should go to teeupshrc"
  assert_contains "$output" "Would update $BASHRC with: Added by teeup.sh - teeupshrc" "bashrc should source teeupshrc"
  if [[ "$output" == *"Would update $ZSHRC with: Added by teeup.sh - rbenv init"* ]]; then
    echo "FAIL: rbenv init should not be written to zshrc"
    return 1
  fi
}

test_zsh_target_sources_teeupshrc_from_zshrc() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands
  mock_runtime_commands

  local output
  output=$(DRY_RUN=true TARGET_SHELL=zsh PACKAGE_MANAGER=apt \
    DOTFILES_DIR="$TEST_HOME/no-dotfiles" "$PROJECT_DIR/teeup.sh" --only ruby 2>&1)

  assert_contains "$output" "Target login shell: zsh" "Should honor TARGET_SHELL=zsh"
  assert_contains "$output" "Would update $TEEUPSHRC with: Added by teeup.sh - rbenv init" "rbenv init should go to teeupshrc"
  assert_contains "$output" "Would update $ZSHRC with: Added by teeup.sh - teeupshrc" "zshrc should source teeupshrc"
}

test_rbenv_init_is_cross_shell_in_teeupshrc() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands
  mock_runtime_commands

  DRY_RUN=false TARGET_SHELL=bash PACKAGE_MANAGER=apt RUBYGEMS_UPDATE=false \
    DOTFILES_DIR="$TEST_HOME/no-dotfiles" "$PROJECT_DIR/teeup.sh" --only ruby >/dev/null 2>&1

  assert_file_exists "$TEEUPSHRC" "Should create teeupshrc"
  assert_file_contains_active "$TEEUPSHRC" "rbenv init - bash" "teeupshrc should init rbenv for bash"
  assert_contains "$(cat "$TEEUPSHRC")" "ZSH_VERSION" "teeupshrc should switch on ZSH_VERSION"
  assert_contains "$(cat "$BASHRC")" ".teeupshrc" "bashrc should source teeupshrc"
  if grep -q "rbenv init" "$ZSHRC"; then
    echo "FAIL: rbenv init should not be written to zshrc"
    return 1
  fi
}

test_target_shell_autodetect_routes_consistently() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands
  mock_runtime_commands

  local output detected
  output=$(DRY_RUN=true PACKAGE_MANAGER=apt \
    DOTFILES_DIR="$TEST_HOME/no-dotfiles" "$PROJECT_DIR/teeup.sh" --only ruby 2>&1)
  detected=$(printf '%s\n' "$output" | sed -n 's/.*Target login shell: //p' | tr -d '[:space:]')

  case "$detected" in
    bash) assert_contains "$output" "Would update $BASHRC with: Added by teeup.sh - teeupshrc" "Detected bash should source teeupshrc from bashrc" ;;
    zsh)  assert_contains "$output" "Would update $ZSHRC with: Added by teeup.sh - teeupshrc" "Detected zsh should source teeupshrc from zshrc" ;;
    *) echo "FAIL: unexpected detected shell '$detected'"; return 1 ;;
  esac
}

test_linux_docker_adds_user_to_group() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands
  mock_command systemctl 0 ""
  mock_command usermod 0 ""

  local output
  output=$(DRY_RUN=true PACKAGE_MANAGER=apt "$PROJECT_DIR/teeup.sh" --only docker 2>&1)

  assert_contains "$output" "usermod -aG docker" "Should add the user to the docker group"
  assert_contains "$output" "Log out and back in" "Should explain re-login is required"
}

test_bash_shell_module_uses_starship_not_zsh() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands

  local output
  output=$(DRY_RUN=true PACKAGE_MANAGER=apt \
    DOTFILES_DIR="$TEST_HOME/no-dotfiles" "$PROJECT_DIR/teeup.sh" --only bash 2>&1)

  assert_contains "$output" "Configuring bash shell" "Bash module should configure bash"
  assert_contains "$output" "https://starship.rs/install.sh" "Should install Starship"
  assert_contains "$output" "apt-get install -y bash-completion" "Should install bash-completion"
  assert_contains "$output" "Would update $TEEUPSHRC with: Added by teeup.sh - starship" "Should write starship init to teeupshrc"
  if [[ "$output" == *"powerlevel10k"* ]]; then
    echo "FAIL: bash shell module should not install Powerlevel10k"
    return 1
  fi
  if [[ "$output" == *"zsh-autosuggestions"* ]]; then
    echo "FAIL: bash shell module should not install zsh plugins"
    return 1
  fi
  if [[ "$output" == *"Would update $ZSHRC"* ]]; then
    echo "FAIL: bash deployment should not touch ~/.zshrc (segregation)"
    return 1
  fi
}

test_bash_deploy_links_only_bash_dotfiles() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands

  local df="$TEST_HOME/dotfiles"
  mkdir -p "$df"
  local f
  for f in zshrc zprofile bashrc .bash_profile profile shellrc.common teeupshrc gitconfig tmux.conf; do
    echo "# stub" > "$df/$f"
  done

  local output
  output=$(DRY_RUN=true TARGET_SHELL=bash PACKAGE_MANAGER=apt \
    DOTFILES_DIR="$df" "$PROJECT_DIR/teeup.sh" --only bash 2>&1)

  assert_contains "$output" "ln -s $df/bashrc $HOME/.bashrc" "Should link bash dotfiles"
  assert_contains "$output" "ln -s $df/teeupshrc $HOME/.teeupshrc" "Should link shared teeupshrc"
  if [[ "$output" == *"$df/zshrc $HOME/.zshrc"* ]]; then
    echo "FAIL: bash deployment should not link zsh dotfiles (segregation)"
    return 1
  fi
}

test_zsh_shell_module_still_installs_plugins() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands

  local output
  output=$(DRY_RUN=true PACKAGE_MANAGER=apt \
    DOTFILES_DIR="$TEST_HOME/no-dotfiles" "$PROJECT_DIR/teeup.sh" --only zsh 2>&1)

  assert_contains "$output" "Configuring zsh mode" "Zsh module should configure zsh"
  assert_contains "$output" "powerlevel10k.git" "Should install Powerlevel10k"
  assert_contains "$output" "zsh-autosuggestions" "Should install zsh plugins"
  if [[ "$output" == *"starship.rs"* ]]; then
    echo "FAIL: zsh shell module should not install Starship"
    return 1
  fi
}

echo ""
echo "Running tests..."
echo ""

run_test "Isolated test environment" test_isolated_test_env
run_test "macOS command mocks" test_macos_command_mocks
run_test "Dry-run legacy Python config isolation" test_dryrun_legacy_python_does_not_write_config
run_test "UV Python skips package manager" test_uv_python_only_skips_package_manager
run_test "Legacy Python enables package manager" test_legacy_python_only_enables_package_manager
run_test "Package-backed modules enable package manager" test_package_backed_modules_enable_package_manager
run_test "MacPorts dry-run missing port" test_macports_dryrun_warns_when_port_missing
run_test "MacPorts apps skip casks" test_macports_apps_skip_casks_without_fallback
run_test "Linux apt path" test_linux_apt_path
run_test "Linux apps skip by default" test_linux_apps_skip_by_default
run_test "Linux apps strict-platform fails" test_linux_apps_strict_platform_fails
run_test "Linux Docker avoids Colima" test_linux_docker_avoids_colima
run_test "Bash target routes init to teeupshrc" test_bash_target_routes_init_to_teeupshrc
run_test "Zsh target sources teeupshrc from zshrc" test_zsh_target_sources_teeupshrc_from_zshrc
run_test "rbenv init is cross-shell in teeupshrc" test_rbenv_init_is_cross_shell_in_teeupshrc
run_test "Target shell autodetect routes consistently" test_target_shell_autodetect_routes_consistently
run_test "Linux Docker adds user to docker group" test_linux_docker_adds_user_to_group
run_test "Bash shell module uses Starship not zsh" test_bash_shell_module_uses_starship_not_zsh
run_test "Bash deploy links only bash dotfiles" test_bash_deploy_links_only_bash_dotfiles
run_test "Zsh shell module still installs plugins" test_zsh_shell_module_still_installs_plugins

print_summary
