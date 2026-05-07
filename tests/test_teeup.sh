#!/usr/bin/env bash
# test_teeup.sh — Tests for teeup.sh
#
# Usage: ./tests/test_teeup.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source test helper
source "$SCRIPT_DIR/test_helper.sh"

echo "========================================"
echo "Testing teeup.sh"
echo "========================================"

###########################################
# Test: Script syntax is valid
###########################################
test_syntax_valid() {
  bash -n "$PROJECT_DIR/teeup.sh" 2>&1
}

###########################################
# Test: Help flag works
###########################################
test_help_flag() {
  local output
  output=$("$PROJECT_DIR/teeup.sh" --help 2>&1 || true)
  assert_contains "$output" "Usage:" "Help should show usage"
}

###########################################
# Test: List modules flag works
###########################################
test_list_modules() {
  local output
  output=$("$PROJECT_DIR/teeup.sh" --list-modules 2>&1 || true)
  assert_contains "$output" "homebrew" "Should list homebrew module"
}

###########################################
# Test: Unknown option shows warning
###########################################
test_unknown_option() {
  local output
  output=$("$PROJECT_DIR/teeup.sh" --invalid-option 2>&1 || true)
  assert_contains "$output" "Unknown option" "Should warn about unknown option"
}

###########################################
# Test: Default environment variables
###########################################
test_default_env_vars() {
  local content
  content=$(cat "$PROJECT_DIR/teeup.sh")
  assert_contains "$content" 'PYTHON_VERSION="${PYTHON_VERSION:-3.12.5}"' "Should have default Python version"
  assert_contains "$content" 'PACKAGE_MANAGER="${PACKAGE_MANAGER:-auto}"' "Should default package manager to auto"
}

###########################################
# Test: No Bash 4 lowercase syntax
###########################################
test_no_bash4_lowercase() {
  local count
  count=$(grep -E '\$\{[a-zA-Z_]+,,\}' "$PROJECT_DIR/teeup.sh" | wc -l | tr -d ' ')
  assert_equals "0" "$count" "Should not use Bash 4 lowercase syntax"
}

###########################################
# Test: Uses tr for lowercase
###########################################
test_uses_tr_lowercase() {
  local content
  content=$(cat "$PROJECT_DIR/teeup.sh")
  assert_contains "$content" "tr '[:upper:]' '[:lower:]'" "Should use tr for lowercase"
}

###########################################
# Test: All modules defined
###########################################
test_all_modules_defined() {
  local content
  content=$(cat "$PROJECT_DIR/teeup.sh")
  assert_contains "$content" "RUN_HOMEBREW" "Should define RUN_HOMEBREW"
  assert_contains "$content" "RUN_ZSH" "Should define RUN_ZSH"
  assert_contains "$content" "RUN_PYTHON" "Should define RUN_PYTHON"
  assert_contains "$content" "RUN_JAVA" "Should define RUN_JAVA"
  assert_contains "$content" "RUN_DOCKER" "Should define RUN_DOCKER"
  assert_contains "$content" "RUN_APPS" "Should define RUN_APPS"
}

###########################################
# Test: Script has shebang
###########################################
test_has_shebang() {
  local first_line
  first_line=$(head -1 "$PROJECT_DIR/teeup.sh")
  assert_contains "$first_line" "#!/usr/bin/env bash" "Should have bash shebang"
}

###########################################
# Test: Uses set -euo pipefail
###########################################
test_strict_mode() {
  local content
  content=$(cat "$PROJECT_DIR/teeup.sh")
  assert_contains "$content" "set -euo pipefail" "Should use strict mode"
}

###########################################
# Test: Has UV support
###########################################
test_uv_support() {
  local content
  content=$(cat "$PROJECT_DIR/teeup.sh")
  assert_contains "$content" "USE_UV" "Should support UV"
  assert_contains "$content" "uv python install" "Should install Python via UV"
}

###########################################
# Test: Has modern zsh support
###########################################
test_zsh_support() {
  local content
  content=$(cat "$PROJECT_DIR/teeup.sh")
  assert_contains "$content" 'ZSH_MODE="${ZSH_MODE:-plain}"' "Should default to plain zsh mode"
  assert_contains "$content" "zsh)      RUN_ZSH=true" "Should support zsh module"
  assert_contains "$content" "ohmyzsh)  RUN_ZSH=true; ZSH_MODE=\"ohmyzsh\"" "Should keep ohmyzsh alias"
  assert_contains "$content" "powerlevel10k" "Should support Powerlevel10k"
}

###########################################
# Test: Has existing config reconciliation
###########################################
test_reconcile_support() {
  local content
  content=$(cat "$PROJECT_DIR/teeup.sh")
  assert_contains "$content" "RECONCILE_EXISTING_CONFIG" "Should support existing config reconciliation"
  assert_contains "$content" "--reconcile-existing-config" "Should expose reconcile flag"
  assert_contains "$content" "disable_matching_lines" "Should disable stale config safely"
}

###########################################
# Test: Has package manager support
###########################################
test_package_manager_support() {
  local content
  content=$(cat "$PROJECT_DIR/teeup.sh")
  assert_contains "$content" "resolve_package_manager" "Should resolve package manager"
  assert_contains "$content" "macports" "Should support MacPorts"
  assert_contains "$content" "sudo port install" "Should install packages with MacPorts"
  assert_contains "$content" "CLEANUP_HOMEBREW_OVERLAPS" "Should support Homebrew overlap cleanup"
}

###########################################
# Test: Does not install Antigen
###########################################
test_no_antigen_install() {
  local content
  content=$(cat "$PROJECT_DIR/teeup.sh")
  if grep -q "curl .*antigen\\|antigen init\\|source .*antigen.zsh" "$PROJECT_DIR/teeup.sh"; then
    return 1
  fi
  assert_contains "$content" "Antigen removed" "Should reconcile old Antigen config"
}

###########################################
# Test: Has pyenv support
###########################################
test_pyenv_support() {
  local content
  content=$(cat "$PROJECT_DIR/teeup.sh")
  assert_contains "$content" "pyenv install" "Should support pyenv"
}

###########################################
# Test: Has SDKMAN support
###########################################
test_sdkman_support() {
  local content
  content=$(cat "$PROJECT_DIR/teeup.sh")
  assert_contains "$content" "SDKMAN" "Should support SDKMAN"
  assert_contains "$content" "sdk install java" "Should install Java via SDKMAN"
}

###########################################
# Test: Has Colima support
###########################################
test_colima_support() {
  local content
  content=$(cat "$PROJECT_DIR/teeup.sh")
  assert_contains "$content" "colima" "Should support Colima"
  assert_contains "$content" "COLIMA_CPUS" "Should have Colima CPU config"
}

###########################################
# Test: Has Bruno support
###########################################
test_bruno_support() {
  local content
  content=$(cat "$PROJECT_DIR/teeup.sh")
  assert_contains "$content" "bruno" "Should support Bruno"
  assert_contains "$content" "INSTALL_BRUNO" "Should have Bruno toggle"
}

###########################################
# Test: Includes cls alias
###########################################
test_cls_alias() {
  local content
  content=$(cat "$PROJECT_DIR/teeup.sh")
  assert_contains "$content" "alias cls='clear'" "Should add cls alias for clear"
}

###########################################
# Test: Shellcheck validation (optional)
###########################################
test_shellcheck() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    echo "shellcheck not installed, skipping"
    return 0
  fi

  shellcheck -x "$PROJECT_DIR/teeup.sh" 2>&1
}

###########################################
# Test: Dry-run mode support
###########################################
test_dryrun_support() {
  local content
  content=$(cat "$PROJECT_DIR/teeup.sh")
  assert_contains "$content" "DRY_RUN" "Should support DRY_RUN"
  assert_contains "$content" "run_cmd" "Should have run_cmd function"
  assert_contains "$content" "--dry-run" "Should have --dry-run flag"
}

###########################################
# Test: run_cmd function defined
###########################################
test_run_cmd_function() {
  local content
  content=$(cat "$PROJECT_DIR/teeup.sh")
  assert_contains "$content" "run_cmd()" "Should define run_cmd function"
  assert_contains "$content" "[DRY-RUN]" "Should have dry-run output message"
}

###########################################
# Run all tests
###########################################
echo ""
echo "Running tests..."
echo ""

run_test "Script syntax valid" test_syntax_valid
run_test "Help flag works" test_help_flag
run_test "List modules flag" test_list_modules
run_test "Unknown option handling" test_unknown_option
run_test "Default env vars" test_default_env_vars
run_test "No Bash 4 lowercase" test_no_bash4_lowercase
run_test "Uses tr for lowercase" test_uses_tr_lowercase
run_test "All modules defined" test_all_modules_defined
run_test "Has shebang" test_has_shebang
run_test "Uses strict mode" test_strict_mode
run_test "UV support" test_uv_support
run_test "Modern zsh support" test_zsh_support
run_test "Existing config reconciliation" test_reconcile_support
run_test "Package manager support" test_package_manager_support
run_test "No Antigen install" test_no_antigen_install
run_test "pyenv support" test_pyenv_support
run_test "SDKMAN support" test_sdkman_support
run_test "Colima support" test_colima_support
run_test "Bruno support" test_bruno_support
run_test "cls alias" test_cls_alias
run_test "Shellcheck validation" test_shellcheck
run_test "Dry-run mode support" test_dryrun_support
run_test "run_cmd function defined" test_run_cmd_function

print_summary
