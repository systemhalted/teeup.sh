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
  assert_contains "$output" "Would update $TEEUP_COMMON with: Added by teeup.sh - rbenv init" "rbenv init should go to teeup.common"
  assert_contains "$output" "Would update $BASHRC with: Added by teeup.sh - teeup.common" "bashrc should source teeup.common"
  if [[ "$output" == *"Would update $ZSHRC with: Added by teeup.sh - rbenv init"* ]]; then
    echo "FAIL: rbenv init should not be written to zshrc"
    return 1
  fi
}

test_ruby_installs_build_deps() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands
  mock_runtime_commands

  local output
  output=$(DRY_RUN=true TARGET_SHELL=bash PACKAGE_MANAGER=apt \
    DOTFILES_DIR="$TEST_HOME/no-dotfiles" "$PROJECT_DIR/teeup.sh" --only ruby 2>&1)

  assert_contains "$output" "Ensuring Ruby build dependencies for apt" "Ruby module should install build deps before compiling"
  assert_contains "$output" "libyaml-dev" "Should install libyaml-dev (psych needs libyaml)"
  assert_contains "$output" "libffi-dev" "Should install libffi-dev (fiddle needs libffi)"
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
  assert_contains "$output" "Would update $TEEUP_COMMON with: Added by teeup.sh - rbenv init" "rbenv init should go to teeup.common"
  assert_contains "$output" "Would update $ZSHRC with: Added by teeup.sh - teeup.common" "zshrc should source teeup.common"
}

test_rbenv_init_is_cross_shell_in_teeupshrc() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands
  mock_runtime_commands

  DRY_RUN=false TARGET_SHELL=bash PACKAGE_MANAGER=apt RUBYGEMS_UPDATE=false \
    DOTFILES_DIR="$TEST_HOME/no-dotfiles" "$PROJECT_DIR/teeup.sh" --only ruby >/dev/null 2>&1

  assert_file_exists "$TEEUP_COMMON" "Should create teeup.common"
  assert_file_contains_active "$TEEUP_COMMON" "rbenv init - bash" "teeup.common should init rbenv for bash"
  assert_contains "$(cat "$TEEUP_COMMON")" "ZSH_VERSION" "teeup.common should switch on ZSH_VERSION"
  assert_contains "$(cat "$BASHRC")" ".teeup.common" "bashrc should source teeup.common"
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
    bash) assert_contains "$output" "Would update $BASHRC with: Added by teeup.sh - teeup.common" "Detected bash should source teeup.common from bashrc" ;;
    zsh)  assert_contains "$output" "Would update $ZSHRC with: Added by teeup.sh - teeup.common" "Detected zsh should source teeup.common from zshrc" ;;
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
  output=$(DRY_RUN=true PACKAGE_MANAGER=apt PROMPT=starship \
    DOTFILES_DIR="$TEST_HOME/no-dotfiles" "$PROJECT_DIR/teeup.sh" --only bash 2>&1)

  assert_contains "$output" "Configuring bash shell" "Bash module should configure bash"
  assert_contains "$output" "https://starship.rs/install.sh" "Should install Starship when --prompt starship"
  assert_contains "$output" "apt-get install -y bash-completion" "Should install bash-completion"
  assert_contains "$output" "Would update $TEEUP_COMMON with: Added by teeup.sh - starship" "Should write starship init to teeup.common"
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
  for f in zshrc zprofile bashrc .bash_profile profile teeup.common starship.toml; do
    echo "# stub" > "$df/$f"
  done

  local output
  output=$(DRY_RUN=true TARGET_SHELL=bash PACKAGE_MANAGER=apt PROMPT=starship \
    DOTFILES_DIR="$df" "$PROJECT_DIR/teeup.sh" --only bash 2>&1)

  assert_contains "$output" "ln -s $df/bashrc $HOME/.bashrc" "Should link bash dotfiles"
  assert_contains "$output" "ln -s $df/teeup.common $HOME/.teeup.common" "Should link shared teeup.common"
  assert_contains "$output" "ln -s $df/starship.toml $HOME/.config/starship.toml" "Should link starship.toml when --prompt starship"
  if [[ "$output" == *"$df/zshrc $HOME/.zshrc"* ]]; then
    echo "FAIL: bash deployment should not link zsh dotfiles (segregation)"
    return 1
  fi
}

# Optional, non-shell-specific configs link only when the overlay ships them.
test_optional_dotfiles_link_if_present() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands

  # Overlay WITH optional configs → they get linked.
  local df="$TEST_HOME/dotfiles"
  mkdir -p "$df"
  local f
  for f in bashrc teeup.common gitconfig tmux.conf; do
    echo "# stub" > "$df/$f"
  done
  local with_output
  with_output=$(DRY_RUN=true TARGET_SHELL=bash PACKAGE_MANAGER=apt \
    DOTFILES_DIR="$df" "$PROJECT_DIR/teeup.sh" --only bash 2>&1)
  assert_contains "$with_output" "ln -s $df/gitconfig $HOME/.gitconfig" "Should link gitconfig when present"
  assert_contains "$with_output" "ln -s $df/tmux.conf $HOME/.tmux.conf" "Should link tmux.conf when present"

  # Overlay WITHOUT them but WITH the full bash core → no optional link, no warning.
  local df2="$TEST_HOME/dotfiles-min"
  mkdir -p "$df2"
  for f in bashrc .bash_profile profile teeup.common; do
    echo "# stub" > "$df2/$f"
  done
  local min_output
  min_output=$(DRY_RUN=true TARGET_SHELL=bash PACKAGE_MANAGER=apt \
    DOTFILES_DIR="$df2" "$PROJECT_DIR/teeup.sh" --only bash 2>&1)
  if [[ "$min_output" == *"$HOME/.gitconfig"* || "$min_output" == *"$HOME/.tmux.conf"* ]]; then
    echo "FAIL: should not link gitconfig/tmux.conf when overlay omits them"
    return 1
  fi
  if [[ "$min_output" == *"Dotfile source missing"* ]]; then
    echo "FAIL: link-if-present should not emit a missing-source warning"
    return 1
  fi
}

# A back-compat link (~/.teeupshrc) for an overlay still shipping teeupshrc must SURVIVE
# the orphan cleanup — the cleanup only fires once the overlay has dropped the legacy file.
test_legacy_link_survives_when_overlay_ships_it() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands

  local df="$TEST_HOME/dotfiles"
  mkdir -p "$df"
  local f
  for f in bashrc .bash_profile profile shellrc.common teeupshrc; do
    echo "# stub" > "$df/$f"
  done

  DRY_RUN=false TARGET_SHELL=bash PACKAGE_MANAGER=apt \
    DOTFILES_DIR="$df" "$PROJECT_DIR/teeup.sh" --only cli >/dev/null 2>&1

  if [[ ! -L "$HOME/.teeupshrc" ]]; then
    echo "FAIL: ~/.teeupshrc back-compat link should survive when overlay ships teeupshrc"; return 1
  fi
  assert_equals "$df/teeupshrc" "$(readlink "$HOME/.teeupshrc")" "teeupshrc link should point into the overlay"
  if [[ ! -L "$HOME/.shellrc.common" ]]; then
    echo "FAIL: ~/.shellrc.common back-compat link should survive when overlay ships it"; return 1
  fi
}

# Once the overlay drops a legacy file, a stale teeup-owned ~/.<name> symlink is removed.
test_stale_legacy_symlink_removed_after_migration() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands

  local df="$TEST_HOME/dotfiles"
  mkdir -p "$df"
  local f
  for f in bashrc .bash_profile profile teeup.common; do
    echo "# stub" > "$df/$f"
  done
  # Leftover from an older run: a teeup-owned ~/.shellrc.common symlink into the overlay,
  # which no longer ships shellrc.common.
  ln -s "$df/shellrc.common" "$HOME/.shellrc.common"

  DRY_RUN=false TARGET_SHELL=bash PACKAGE_MANAGER=apt \
    DOTFILES_DIR="$df" "$PROJECT_DIR/teeup.sh" --only cli >/dev/null 2>&1

  if [[ -L "$HOME/.shellrc.common" || -e "$HOME/.shellrc.common" ]]; then
    echo "FAIL: stale ~/.shellrc.common symlink should be removed once overlay drops it"; return 1
  fi
  assert_equals "$df/teeup.common" "$(readlink "$HOME/.teeup.common")" "teeup.common link should be created"
}

test_zsh_shell_module_still_installs_plugins() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands

  local output
  output=$(DRY_RUN=true PACKAGE_MANAGER=apt PROMPT=powerlevel10k \
    DOTFILES_DIR="$TEST_HOME/no-dotfiles" "$PROJECT_DIR/teeup.sh" --only zsh 2>&1)

  assert_contains "$output" "Configuring zsh mode" "Zsh module should configure zsh"
  assert_contains "$output" "powerlevel10k.git" "Should install Powerlevel10k when --prompt powerlevel10k"
  assert_contains "$output" "zsh-autosuggestions" "Should install zsh plugins"
  if [[ "$output" == *"starship.rs"* ]]; then
    echo "FAIL: zsh shell module should not install Starship"
    return 1
  fi
}

# --prompt none (the default) installs no prompt tool on either shell.
test_prompt_none_installs_no_prompt_tool() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands

  local zsh_output bash_output
  zsh_output=$(DRY_RUN=true PACKAGE_MANAGER=apt \
    DOTFILES_DIR="$TEST_HOME/no-dotfiles" "$PROJECT_DIR/teeup.sh" --only zsh 2>&1)
  bash_output=$(DRY_RUN=true PACKAGE_MANAGER=apt \
    DOTFILES_DIR="$TEST_HOME/no-dotfiles" "$PROJECT_DIR/teeup.sh" --only bash 2>&1)

  if [[ "$zsh_output" == *"powerlevel10k.git"* ]]; then
    echo "FAIL: default prompt (none) should not install Powerlevel10k"; return 1
  fi
  if [[ "$bash_output" == *"starship.rs"* ]]; then
    echo "FAIL: default prompt (none) should not install Starship"; return 1
  fi
  # zsh plugins are independent of the prompt and should still install.
  assert_contains "$zsh_output" "zsh-autosuggestions" "zsh plugins install regardless of prompt"
}

# --prompt starship installs Starship only (never Powerlevel10k).
test_prompt_starship_only() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands

  local output
  output=$(DRY_RUN=true PACKAGE_MANAGER=apt PROMPT=starship \
    DOTFILES_DIR="$TEST_HOME/no-dotfiles" "$PROJECT_DIR/teeup.sh" --only bash 2>&1)

  assert_contains "$output" "https://starship.rs/install.sh" "--prompt starship should install Starship"
  if [[ "$output" == *"powerlevel10k"* ]]; then
    echo "FAIL: --prompt starship should not install Powerlevel10k"; return 1
  fi
}

# An older Mode-2 ~/.teeupshrc (a real file) is migrated to ~/.teeup.common, the rc is
# re-pointed, and a re-run stays idempotent (no duplicate source line).
test_mode2_teeupshrc_migration() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands
  mock_runtime_commands

  # Seed an old Mode-2 install: a real ~/.teeupshrc + the old managed source block.
  printf '# old tool init\nexport OLD_MARKER=1\n' > "$TEST_HOME/.teeupshrc"
  {
    echo ""
    echo "# Added by teeup.sh - teeupshrc"
    echo '# Cross-shell tool integration written by teeup.sh.'
    echo 'if [ -r "$HOME/.teeupshrc" ]; then'
    echo '  . "$HOME/.teeupshrc"'
    echo 'fi'
  } >> "$BASHRC"

  DRY_RUN=false TARGET_SHELL=bash PACKAGE_MANAGER=apt RUBYGEMS_UPDATE=false \
    DOTFILES_DIR="$TEST_HOME/no-dotfiles" "$PROJECT_DIR/teeup.sh" --only ruby >/dev/null 2>&1

  assert_file_exists "$TEEUP_COMMON" "Should migrate content to ~/.teeup.common"
  assert_contains "$(cat "$TEEUP_COMMON")" "OLD_MARKER" "Migrated file should keep the old content"
  if [[ -e "$TEST_HOME/.teeupshrc" ]]; then
    echo "FAIL: old ~/.teeupshrc should be gone after migration"; return 1
  fi
  assert_contains "$(cat "$BASHRC")" ".teeup.common" "bashrc should source the new path"
  if grep -q '\.teeupshrc' "$BASHRC"; then
    echo "FAIL: bashrc should no longer reference .teeupshrc"; return 1
  fi
  # Idempotency: exactly one teeup.common source block (no duplicate).
  local count
  count=$(grep -c 'Added by teeup.sh - teeup.common' "$BASHRC")
  if [[ "$count" -ne 1 ]]; then
    echo "FAIL: expected exactly one teeup.common source block, got $count"; return 1
  fi
}

test_default_profile_is_base() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands

  local output
  output=$(DRY_RUN=true PACKAGE_MANAGER=apt \
    DOTFILES_DIR="$TEST_HOME/no-dotfiles" "$PROJECT_DIR/teeup.sh" 2>&1)

  # base = package manager + shell + cli; everything else is skipped.
  assert_contains "$output" "Installing core CLI utilities" "Base profile should install CLI"
  assert_contains "$output" "Skipping Python setup (RUN_PYTHON=false)" "Base profile should skip Python"
  assert_contains "$output" "Skipping Java setup (RUN_JAVA=false)" "Base profile should skip Java"
  assert_contains "$output" "Skipping Ruby setup (RUN_RUBY=false)" "Base profile should skip Ruby"
  assert_contains "$output" "Skipping Rust setup (RUN_RUST=false)" "Base profile should skip Rust"
  assert_contains "$output" "Skipping Emacs setup (RUN_EMACS=false)" "Base profile should skip Emacs"
  assert_contains "$output" "Skipping Docker setup (RUN_DOCKER=false)" "Base profile should skip Docker"
}

test_all_profile_enables_runtimes() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands

  local output
  output=$(DRY_RUN=true PACKAGE_MANAGER=apt \
    DOTFILES_DIR="$TEST_HOME/no-dotfiles" "$PROJECT_DIR/teeup.sh" --all 2>&1)

  if [[ "$output" == *"Skipping Java setup (RUN_JAVA=false)"* ]]; then
    echo "FAIL: --all should not skip Java"; return 1
  fi
  if [[ "$output" == *"Skipping Ruby setup (RUN_RUBY=false)"* ]]; then
    echo "FAIL: --all should not skip Ruby"; return 1
  fi
}

test_except_skips_listed_modules() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands

  local output
  output=$(DRY_RUN=true PACKAGE_MANAGER=apt \
    DOTFILES_DIR="$TEST_HOME/no-dotfiles" "$PROJECT_DIR/teeup.sh" --all --except ruby,emacs 2>&1)

  assert_contains "$output" "Skipping Ruby setup (RUN_RUBY=false)" "--except ruby should skip Ruby"
  assert_contains "$output" "Skipping Emacs setup (RUN_EMACS=false)" "--except emacs should skip Emacs"
  if [[ "$output" == *"Skipping Java setup (RUN_JAVA=false)"* ]]; then
    echo "FAIL: --except ruby,emacs should not skip Java"; return 1
  fi
}

test_run_env_var_overrides_base_profile() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands

  local output
  output=$(DRY_RUN=true RUN_RUBY=true PACKAGE_MANAGER=apt \
    DOTFILES_DIR="$TEST_HOME/no-dotfiles" "$PROJECT_DIR/teeup.sh" 2>&1)

  if [[ "$output" == *"Skipping Ruby setup (RUN_RUBY=false)"* ]]; then
    echo "FAIL: RUN_RUBY=true should override base profile"; return 1
  fi
}

test_init_dotfiles_generates_neutral_starter() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands

  local dest="$TEST_HOME/dotfiles"
  local output
  output=$(DRY_RUN=true PACKAGE_MANAGER=apt "$PROJECT_DIR/teeup.sh" \
    --only cli --init-dotfiles "$dest" 2>&1)

  assert_contains "$output" "Generating a neutral starter dotfiles repo at $dest" \
    "--init-dotfiles should scaffold a starter repo"
}

echo ""
echo "Running tests..."
echo ""

run_test "Default profile is base" test_default_profile_is_base
run_test "--all enables runtimes" test_all_profile_enables_runtimes
run_test "--except skips listed modules" test_except_skips_listed_modules
run_test "RUN_* env overrides base profile" test_run_env_var_overrides_base_profile
run_test "--init-dotfiles generates neutral starter" test_init_dotfiles_generates_neutral_starter
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
run_test "Bash target routes init to teeup.common" test_bash_target_routes_init_to_teeupshrc
run_test "Ruby installs build dependencies" test_ruby_installs_build_deps
run_test "Zsh target sources teeup.common from zshrc" test_zsh_target_sources_teeupshrc_from_zshrc
run_test "rbenv init is cross-shell in teeup.common" test_rbenv_init_is_cross_shell_in_teeupshrc
run_test "Target shell autodetect routes consistently" test_target_shell_autodetect_routes_consistently
run_test "Linux Docker adds user to docker group" test_linux_docker_adds_user_to_group
run_test "Bash shell module uses Starship not zsh" test_bash_shell_module_uses_starship_not_zsh
run_test "Bash deploy links only bash dotfiles" test_bash_deploy_links_only_bash_dotfiles
run_test "Optional dotfiles link only if present" test_optional_dotfiles_link_if_present
run_test "Legacy link survives when overlay ships it" test_legacy_link_survives_when_overlay_ships_it
run_test "Stale legacy symlink removed after migration" test_stale_legacy_symlink_removed_after_migration
run_test "Zsh shell module still installs plugins" test_zsh_shell_module_still_installs_plugins
run_test "Prompt none installs no prompt tool" test_prompt_none_installs_no_prompt_tool
run_test "Prompt starship installs Starship only" test_prompt_starship_only
run_test "Mode-2 teeupshrc migrates to teeup.common" test_mode2_teeupshrc_migration

print_summary
