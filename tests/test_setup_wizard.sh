#!/usr/bin/env bash
# test_setup_wizard.sh — Tests for setup_wizard.sh
#
# Usage: ./tests/test_setup_wizard.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source test helper
source "$SCRIPT_DIR/test_helper.sh"

echo "========================================"
echo "Testing setup_wizard.sh"
echo "========================================"

###########################################
# Test: Script syntax is valid
###########################################
test_syntax_valid() {
  bash -n "$PROJECT_DIR/setup_wizard.sh" 2>&1
}

###########################################
# Test: Script is executable
###########################################
test_is_executable() {
  [[ -x "$PROJECT_DIR/setup_wizard.sh" ]] || return 1
}

###########################################
# Test: Has shebang
###########################################
test_has_shebang() {
  local first_line
  first_line=$(head -1 "$PROJECT_DIR/setup_wizard.sh")
  assert_contains "$first_line" "#!/usr/bin/env bash" "Should have bash shebang"
}

###########################################
# Test: Uses strict mode
###########################################
test_strict_mode() {
  local content
  content=$(cat "$PROJECT_DIR/setup_wizard.sh")
  assert_contains "$content" "set -euo pipefail" "Should use strict mode"
}

###########################################
# Test: Color codes are defined
###########################################
test_color_codes_defined() {
  local content
  content=$(cat "$PROJECT_DIR/setup_wizard.sh")
  assert_contains "$content" "BOLD=" "Should define BOLD"
  assert_contains "$content" "GREEN=" "Should define GREEN"
  assert_contains "$content" "RED=" "Should define RED"
  assert_contains "$content" "RESET=" "Should define RESET"
}

###########################################
# Test: All wizard screens are defined
###########################################
test_wizard_screens_defined() {
  local content
  content=$(cat "$PROJECT_DIR/setup_wizard.sh")
  assert_contains "$content" "show_welcome()" "Should have show_welcome"
  assert_contains "$content" "show_setup_type()" "Should have show_setup_type"
  assert_contains "$content" "show_module_selection()" "Should have show_module_selection"
  assert_contains "$content" "show_python_config()" "Should have show_python_config"
  assert_contains "$content" "show_java_config()" "Should have show_java_config"
  assert_contains "$content" "show_docker_config()" "Should have show_docker_config"
  assert_contains "$content" "show_apps_config()" "Should have show_apps_config"
  assert_contains "$content" "show_summary()" "Should have show_summary"
}

###########################################
# Test: Helper functions are defined
###########################################
test_helper_functions_defined() {
  local content
  content=$(cat "$PROJECT_DIR/setup_wizard.sh")
  assert_contains "$content" "print_header()" "Should have print_header"
  assert_contains "$content" "print_section()" "Should have print_section"
  assert_contains "$content" "prompt_yes_no()" "Should have prompt_yes_no"
  assert_contains "$content" "toggle_selected_module()" "Should have toggle_selected_module"
  assert_contains "$content" "is_module_selected()" "Should have is_module_selected"
}

###########################################
# Test: State variables are initialized
###########################################
test_state_variables() {
  local content
  content=$(cat "$PROJECT_DIR/setup_wizard.sh")
  assert_contains "$content" "SELECTED_MODULES=()" "Should init SELECTED_MODULES"
  assert_contains "$content" "WIZARD_PYTHON_VERSION=" "Should init WIZARD_PYTHON_VERSION"
  assert_contains "$content" "WIZARD_USE_UV=" "Should init WIZARD_USE_UV"
  assert_contains "$content" "WIZARD_JDK_VERSION=" "Should init WIZARD_JDK_VERSION"
}

###########################################
# Test: Module list is complete
###########################################
test_module_list_complete() {
  local content
  content=$(cat "$PROJECT_DIR/setup_wizard.sh")
  assert_contains "$content" '"homebrew"' "Should list homebrew"
  assert_contains "$content" '"python"' "Should list python"
  assert_contains "$content" '"java"' "Should list java"
  assert_contains "$content" '"docker"' "Should list docker"
  assert_contains "$content" '"apps"' "Should list apps"
}

###########################################
# Test: Setup type options
###########################################
test_setup_type_options() {
  local content
  content=$(cat "$PROJECT_DIR/setup_wizard.sh")
  assert_contains "$content" "Full Setup" "Should have Full Setup option"
  assert_contains "$content" "Custom Setup" "Should have Custom Setup option"
  assert_contains "$content" "Migration" "Should have Migration option"
}

###########################################
# Test: No Bash 4 lowercase syntax
###########################################
test_no_bash4_lowercase() {
  local count
  count=$(grep -E '\$\{[a-zA-Z_]+,,\}' "$PROJECT_DIR/setup_wizard.sh" | wc -l | tr -d ' ')
  assert_equals "0" "$count" "Should not use Bash 4 lowercase syntax"
}

###########################################
# Test: Uses tr for lowercase
###########################################
test_uses_tr_lowercase() {
  local content
  content=$(cat "$PROJECT_DIR/setup_wizard.sh")
  assert_contains "$content" "tr '[:upper:]' '[:lower:]'" "Should use tr for lowercase"
}

###########################################
# Test: Safe array expansion
###########################################
test_safe_array_expansion() {
  local content
  content=$(cat "$PROJECT_DIR/setup_wizard.sh")
  assert_contains "$content" '${SELECTED_MODULES[@]}' "Should have array expansion"
}

###########################################
# Test: Exports env vars to setup_mac.sh
###########################################
test_exports_env_vars() {
  local content
  content=$(cat "$PROJECT_DIR/setup_wizard.sh")
  assert_contains "$content" 'export PYTHON_VERSION=' "Should export PYTHON_VERSION"
  assert_contains "$content" 'export USE_UV=' "Should export USE_UV"
  assert_contains "$content" 'export JDK_VERSION=' "Should export JDK_VERSION"
  assert_contains "$content" 'export INSTALL_BRUNO=' "Should export INSTALL_BRUNO"
}

###########################################
# Test: Calls setup_mac.sh
###########################################
test_calls_setup_mac() {
  local content
  content=$(cat "$PROJECT_DIR/setup_wizard.sh")
  assert_contains "$content" "setup_mac.sh" "Should reference setup_mac.sh"
  assert_contains "$content" "--only" "Should use --only flag"
}

###########################################
# Test: Has main function
###########################################
test_main_function() {
  local content
  content=$(cat "$PROJECT_DIR/setup_wizard.sh")
  assert_contains "$content" "main()" "Should have main function"
  assert_contains "$content" 'main "$@"' "Should call main"
}

###########################################
# Test: Checks for setup_mac.sh
###########################################
test_checks_setup_mac_exists() {
  local content
  content=$(cat "$PROJECT_DIR/setup_wizard.sh")
  assert_contains "$content" "setup_mac.sh not found" "Should check for setup_mac.sh"
}

###########################################
# Test: Has Bruno in apps config
###########################################
test_bruno_in_apps() {
  local content
  content=$(cat "$PROJECT_DIR/setup_wizard.sh")
  assert_contains "$content" "Bruno" "Should mention Bruno"
  assert_contains "$content" "WIZARD_INSTALL_BRUNO" "Should have Bruno toggle"
}

###########################################
# Test: Shellcheck validation (optional)
###########################################
test_shellcheck() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    echo "shellcheck not installed, skipping"
    return 0
  fi

  shellcheck -x "$PROJECT_DIR/setup_wizard.sh" 2>&1
}

###########################################
# Test: Validation functions defined
###########################################
test_validation_functions_defined() {
  local content
  content=$(cat "$PROJECT_DIR/setup_wizard.sh")
  assert_contains "$content" "validate_positive_integer()" "Should have validate_positive_integer"
  assert_contains "$content" "validate_version_format()" "Should have validate_version_format"
  assert_contains "$content" "validate_choice()" "Should have validate_choice"
}

###########################################
# Test: Validation used in configs
###########################################
test_validation_used() {
  local content
  content=$(cat "$PROJECT_DIR/setup_wizard.sh")
  assert_contains "$content" "validate_choice" "Should use validate_choice"
  assert_contains "$content" "validate_positive_integer" "Should use validate_positive_integer"
  assert_contains "$content" "validate_version_format" "Should use validate_version_format"
}

###########################################
# Test: Dry-run mode support
###########################################
test_dryrun_support() {
  local content
  content=$(cat "$PROJECT_DIR/setup_wizard.sh")
  assert_contains "$content" "WIZARD_DRY_RUN" "Should support WIZARD_DRY_RUN"
  assert_contains "$content" "Preview mode only" "Should have dry-run prompt"
}

###########################################
# Test: Exports dry-run to setup_mac
###########################################
test_exports_dryrun() {
  local content
  content=$(cat "$PROJECT_DIR/setup_wizard.sh")
  assert_contains "$content" 'export DRY_RUN=' "Should export DRY_RUN"
  assert_contains "$content" '--dry-run' "Should pass --dry-run flag"
}

###########################################
# Run all tests
###########################################
echo ""
echo "Running tests..."
echo ""

run_test "Script syntax valid" test_syntax_valid
run_test "Script is executable" test_is_executable
run_test "Has shebang" test_has_shebang
run_test "Uses strict mode" test_strict_mode
run_test "Color codes defined" test_color_codes_defined
run_test "Wizard screens defined" test_wizard_screens_defined
run_test "Helper functions defined" test_helper_functions_defined
run_test "State variables initialized" test_state_variables
run_test "Module list complete" test_module_list_complete
run_test "Setup type options" test_setup_type_options
run_test "No Bash 4 lowercase" test_no_bash4_lowercase
run_test "Uses tr for lowercase" test_uses_tr_lowercase
run_test "Safe array expansion" test_safe_array_expansion
run_test "Exports env vars" test_exports_env_vars
run_test "Calls setup_mac.sh" test_calls_setup_mac
run_test "Main function exists" test_main_function
run_test "Checks setup_mac.sh exists" test_checks_setup_mac_exists
run_test "Bruno in apps config" test_bruno_in_apps
run_test "Shellcheck validation" test_shellcheck
run_test "Validation functions defined" test_validation_functions_defined
run_test "Validation used in configs" test_validation_used
run_test "Dry-run mode support" test_dryrun_support
run_test "Exports dry-run to setup_mac" test_exports_dryrun

print_summary
