#!/usr/bin/env bash
# teeup-wizard.sh — An Interactive, user-friendly wizard interface for teeup.sh
#
# Usage:
#   ./teeup_wizard.sh

set -euo pipefail

#################################
# ===== Colors & Styling ====== #
#################################
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
RESET='\033[0m'

#################################
# ===== Helper Functions ====== #
#################################

print_header() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                                                              ║"
  echo "║            ⛳️  teeup.sh Wizard  ⛳️                           ║"
  echo "║                                                              ║"
  echo "║        Get your new machine ready for the first drive!       ║"
  echo "║                                                              ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo -e "${RESET}"
  echo ""
}

print_section() {
  echo ""
  echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BLUE}${BOLD}  $1${RESET}"
  echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
}

print_option() {
  local num="$1"
  local name="${2:-}"
  local desc="${3:-}"
  local selected="${4:-false}"

  if [[ "$selected" == "true" ]]; then
    echo -e "  ${GREEN}[✓]${RESET} ${BOLD}$num. $name${RESET}"
  else
    echo -e "  ${DIM}[ ]${RESET} ${BOLD}$num. $name${RESET}"
  fi
  echo -e "      ${DIM}$desc${RESET}"
}

print_info() {
  echo -e "${CYAN}ℹ️  $1${RESET}"
}

print_success() {
  echo -e "${GREEN}✅ $1${RESET}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${RESET}"
}

print_error() {
  echo -e "${RED}❌ $1${RESET}"
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-y}"
  local response

  if [[ "$default" == "y" ]]; then
    echo -ne "${WHITE}${prompt} ${DIM}[Y/n]${RESET} "
  else
    echo -ne "${WHITE}${prompt} ${DIM}[y/N]${RESET} "
  fi

  read -r response
  response="${response:-$default}"
  # Convert to lowercase (compatible with Bash 3.2)
  response=$(echo "$response" | tr '[:upper:]' '[:lower:]')

  case "$response" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

# Final confirmation prompt, worded for the selected mode (dry-run vs real).
confirm_start() {
  if [[ "$WIZARD_DRY_RUN" == "true" ]]; then
    prompt_yes_no "Run the dry-run preview now?"
  else
    prompt_yes_no "Start installation?"
  fi
}

prompt_choice() {
  local prompt="$1"
  local default="$2"
  shift 2
  local options=("$@")
  local num_options=${#options[@]}

  echo -e "${WHITE}${prompt}${RESET}"
  echo ""

  local i=1
  while [[ $i -le $num_options ]]; do
    local opt="${options[$((i-1))]}"
    if [[ $i -eq $default ]]; then
      echo -e "  ${GREEN}$i)${RESET} $opt ${DIM}(default)${RESET}"
    else
      echo -e "  ${WHITE}$i)${RESET} $opt"
    fi
    i=$((i + 1))
  done

  echo ""
  echo -ne "${WHITE}Enter choice [1-${num_options}]: ${RESET}"
  read -r choice
  choice="${choice:-$default}"

  echo "$choice"
}

prompt_input() {
  local prompt="$1"
  local default="$2"
  local response

  echo -ne "${WHITE}${prompt} ${DIM}[$default]${RESET}: "
  read -r response
  echo "${response:-$default}"
}

wait_for_key() {
  echo ""
  echo -ne "${DIM}Press Enter to continue...${RESET}"
  read -r
}

strip_quotes() {
  local value="$1"
  value="${value%\"}"
  value="${value#\"}"
  echo "$value"
}

detect_wizard_platform() {
  WIZARD_OS="$(uname -s)"
  WIZARD_PLATFORM_FAMILY="unknown"
  WIZARD_PLATFORM_LABEL="$WIZARD_OS"
  WIZARD_DISTRO_ID=""
  WIZARD_DISTRO_VERSION=""

  case "$WIZARD_OS" in
    Darwin)
      WIZARD_PLATFORM_FAMILY="macos"
      WIZARD_PLATFORM_LABEL="macOS"
      ;;
    Linux)
      WIZARD_PLATFORM_FAMILY="linux"
      if [[ -r /etc/os-release ]]; then
        while IFS='=' read -r key value; do
          value="$(strip_quotes "$value")"
          case "$key" in
            ID) WIZARD_DISTRO_ID="$value" ;;
            VERSION_ID) WIZARD_DISTRO_VERSION="$value" ;;
          esac
        done < /etc/os-release
      fi
      if [[ -n "$WIZARD_DISTRO_ID" ]]; then
        WIZARD_PLATFORM_LABEL="Linux ${WIZARD_DISTRO_ID}${WIZARD_DISTRO_VERSION:+ ${WIZARD_DISTRO_VERSION}}"
      else
        WIZARD_PLATFORM_LABEL="Linux"
      fi
      case "$(basename "${SHELL:-bash}")" in
        *zsh) WIZARD_TARGET_SHELL="zsh" ;;
        *) WIZARD_TARGET_SHELL="bash" ;;
      esac
      ;;
  esac
}

wizard_is_macos() {
  [[ "$WIZARD_PLATFORM_FAMILY" == "macos" ]]
}

wizard_is_linux() {
  [[ "$WIZARD_PLATFORM_FAMILY" == "linux" ]]
}

wizard_supports_apps() {
  wizard_is_macos
}

set_full_default_modules() {
  if wizard_supports_apps; then
    SELECTED_MODULES=("homebrew" "zsh" "cli" "python" "java" "ruby" "rust" "emacs" "docker" "apps")
  else
    SELECTED_MODULES=("homebrew" "zsh" "cli" "python" "java" "ruby" "rust" "emacs" "docker")
  fi
}

# The lean base: package manager + login shell + core CLI utilities.
set_base_default_modules() {
  SELECTED_MODULES=("homebrew" "zsh" "cli")
}

# Toggle item in SELECTED_MODULES array (Bash 3.2 compatible)
# This function adds/removes a module from the selection:
# - If module exists in array: removes it (deselect)
# - If module doesn't exist: adds it (select)
# Uses ${arr[@]+"${arr[@]}"} pattern to safely handle empty arrays with set -u
toggle_selected_module() {
  local item="$1"
  local found=false
  local new_arr=()

  # Iterate through array, copying all items except the one we're toggling
  # The special expansion ${arr[@]+"${arr[@]}"} prevents "unbound variable" errors
  # when the array is empty (Bash 3.2 requires this pattern)
  for i in ${SELECTED_MODULES[@]+"${SELECTED_MODULES[@]}"}; do
    if [[ "$i" == "$item" ]]; then
      found=true  # Item exists, don't add to new array (remove it)
    else
      new_arr+=("$i")  # Keep this item
    fi
  done

  # If item wasn't found in array, add it now (toggle on)
  if [[ "$found" == "false" ]]; then
    new_arr+=("$item")
  fi

  # Replace old array with new array
  SELECTED_MODULES=("${new_arr[@]}")
}

is_in_array() {
  local item="$1"
  shift

  # Handle empty array case (Bash 3.2 compatible)
  if [[ $# -eq 0 ]]; then
    return 1
  fi

  local arr=("$@")

  for i in "${arr[@]}"; do
    [[ "$i" == "$item" ]] && return 0
  done
  return 1
}

# Check if a module is selected (Bash 3.2 compatible - handles empty array)
is_module_selected() {
  local item="$1"
  # Use ${arr[@]+"${arr[@]}"} pattern to safely expand empty arrays
  is_in_array "$item" ${SELECTED_MODULES[@]+"${SELECTED_MODULES[@]}"}
}

# Check if any modules are selected (Bash 3.2 compatible)
has_selected_modules() {
  local count="${#SELECTED_MODULES[@]}"
  [[ "$count" -gt 0 ]]
}

# Validate numeric input (positive integer)
# Arguments:
#   $1 - value: The input value to validate
#   $2 - var_name: Name of the variable (for error messages)
#   $3 - min: Minimum allowed value (default: 1)
#   $4 - max: Maximum allowed value (default: 999)
# Returns:
#   0 if valid or empty (will use default)
#   1 if invalid (prints warning message)
# Example:
#   validate_positive_integer "4" "CPUs" 1 32
validate_positive_integer() {
  local value="$1"
  local var_name="$2"
  local min="${3:-1}"
  local max="${4:-999}"

  # Check if empty (will use default)
  if [[ -z "$value" ]]; then
    return 0
  fi

  # Check if numeric using regex pattern
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    print_warning "Invalid input '$value' for $var_name. Must be a positive integer."
    return 1
  fi

  # Check if within allowed range
  if [[ "$value" -lt "$min" || "$value" -gt "$max" ]]; then
    print_warning "Invalid value '$value' for $var_name. Must be between $min and $max."
    return 1
  fi

  return 0
}

# Validate version format (x.y.z or x.y)
# Arguments:
#   $1 - version: The version string to validate
#   $2 - var_name: Name of the variable (for error messages)
# Returns:
#   0 if valid format or empty (will use default)
#   1 if invalid format (prints warning message)
# Example:
#   validate_version_format "3.12.5" "Python version"  # Valid
#   validate_version_format "3.12" "Python version"    # Valid
#   validate_version_format "3" "Python version"       # Invalid
validate_version_format() {
  local version="$1"
  local var_name="$2"

  # Check if empty (will use default)
  if [[ -z "$version" ]]; then
    return 0
  fi

  # Check version format using regex: major.minor or major.minor.patch
  # Pattern: one or more digits, dot, one or more digits, optional (dot and digits)
  if ! [[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    print_warning "Invalid version format '$version' for $var_name. Expected format: x.y or x.y.z (e.g., 3.12.5)"
    return 1
  fi

  return 0
}

# Validate choice input (numeric within range)
# Arguments:
#   $1 - choice: The user's menu selection
#   $2 - min: Minimum valid choice number
#   $3 - max: Maximum valid choice number
#   $4 - default: Default value to use if invalid or empty
# Returns:
#   Echoes the validated choice (or default if invalid)
#   Returns 0 if valid or empty, 1 if invalid (with warning)
# Example:
#   choice=$(validate_choice "$input" 1 3 1)  # Validates 1-3, defaults to 1
validate_choice() {
  local choice="$1"
  local min="$2"
  local max="$3"
  local default="$4"

  # If empty, use default (no error)
  if [[ -z "$choice" ]]; then
    echo "$default"
    return 0
  fi

  # Check if numeric
  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    print_warning "Invalid input '$choice'. Please enter a number between $min and $max."
    echo "$default"
    return 1
  fi

  # Check if within valid range
  if [[ "$choice" -lt "$min" || "$choice" -gt "$max" ]]; then
    print_warning "Invalid choice '$choice'. Please enter a number between $min and $max."
    echo "$default"
    return 1
  fi

  # Valid choice
  echo "$choice"
  return 0
}

#################################
# ===== Wizard State ========== #
#################################

# Selected modules
SELECTED_MODULES=()

# Configuration
WIZARD_PYTHON_VERSION="3.12.5"
WIZARD_USE_UV="true"
WIZARD_ZSH_MODE="plain"
WIZARD_PROMPT="none"
WIZARD_TARGET_SHELL="zsh"
WIZARD_PACKAGE_MANAGER="auto"
WIZARD_JDK_VERSION="21.0.4-tem"
WIZARD_RUBY_VERSION="3.4.9"
WIZARD_RUBYGEMS_UPDATE="true"
WIZARD_BUNDLER_VERSION=""
WIZARD_INSTALL_DOTFILES="true"
# Dotfiles delivery: "existing" (bring your own overlay), "generate" (scaffold a
# neutral starter you own), or "none" (minimal managed blocks).
WIZARD_DOTFILES_MODE="generate"
WIZARD_DOTFILES_SOURCE=""
WIZARD_INIT_DOTFILES_DIR=""
WIZARD_RECONCILE_EXISTING_CONFIG="true"
WIZARD_CLEANUP_HOMEBREW_OVERLAPS="false"
WIZARD_ALLOW_HOMEBREW_CASK_FALLBACK="false"
WIZARD_TUNE_DEFAULTS="false"
WIZARD_DRY_RUN="false"
WIZARD_COLIMA_CPUS="4"
WIZARD_COLIMA_MEMORY="8"
WIZARD_COLIMA_DISK="60"

# App selection
WIZARD_INSTALL_BRUNO="true"
WIZARD_INSTALL_OBSIDIAN="true"

#################################
# ===== Wizard Screens ======== #
#################################

show_welcome() {
  print_header

  if wizard_is_macos; then
    echo -e "${WHITE}Welcome to the macOS Setup Wizard!${RESET}"
  elif wizard_is_linux; then
    echo -e "${WHITE}Welcome to the Linux Setup Wizard!${RESET}"
  else
    echo -e "${WHITE}Welcome to the Setup Wizard!${RESET}"
  fi
  echo ""
  echo "This wizard will help you configure and install your development"
  echo "environment on ${WIZARD_PLATFORM_LABEL} step by step."
  echo "You can choose which components to install and customize settings along the way."
  echo ""
  echo -e "${DIM}What this wizard can set up for you:${RESET}"
  echo ""
  if wizard_is_macos; then
    echo "  📦 Package Manager   - Homebrew on newer macOS, MacPorts on older macOS"
  elif wizard_is_linux; then
    echo "  📦 Package Manager   - APT on Debian/Ubuntu, DNF on Fedora/RHEL-family"
  else
    echo "  📦 Package Manager   - Auto-detected from your operating system"
  fi
  if wizard_is_linux; then
    echo "  🐚 Shell             - bash or zsh (optional prompt: Powerlevel10k / Starship)"
  else
    echo "  🐚 Zsh               - Minimal zsh or Oh My Zsh (optional Powerlevel10k prompt)"
  fi
  echo "  🛠️  CLI Tools         - Essential command-line utilities"
  echo "  🐍 Python            - Python environment (UV or pyenv)"
  echo "  ☕ Java              - SDKMAN! with JDK, Maven, Gradle"
  echo "  💎 Ruby              - rbenv with RubyGems and Bundler"
  echo "  🦀 Rust               - Rust toolchain via rustup"
  echo "  📝 Emacs             - Text editor with starter config"
  if wizard_is_macos; then
    echo "  🐳 Docker            - Colima + Docker CLI"
    echo "  📱 Apps              - Bruno, Obsidian"
  elif wizard_is_linux; then
    echo "  🐳 Docker            - Docker engine + CLI"
    echo "  📱 Apps              - macOS-only (skipped on Linux)"
  else
    echo "  🐳 Docker            - Docker runtime + CLI"
  fi
  echo ""

  if ! prompt_yes_no "Ready to begin?"; then
    echo ""
    print_info "Setup cancelled. Run this wizard again when you're ready!"
    exit 0
  fi
}

show_setup_type() {
  print_header
  print_section "Step 1: Choose Setup Type"

  echo "How would you like to proceed?"
  echo ""
  echo -e "  ${BOLD}1)${RESET} 🌱 ${GREEN}Minimal Setup (Recommended)${RESET} - Package manager + shell + CLI utilities"
  echo -e "  ${BOLD}2)${RESET} 🚀 ${CYAN}Full Setup${RESET} - The whole stack (runtimes, Emacs, Docker, apps)"
  echo -e "  ${BOLD}3)${RESET} 🎯 ${CYAN}Custom Setup${RESET} - Choose which modules to install"
  echo -e "  ${BOLD}4)${RESET} 🔄 ${YELLOW}Migration${RESET} - Migrate from pyenv to UV"
  echo ""
  echo -ne "${WHITE}Enter your choice [1-4] (default: 1): ${RESET}"

  local choice
  read -r choice
  choice=$(validate_choice "$choice" 1 4 1)

  case "$choice" in
    1)
      SETUP_TYPE="minimal"
      set_base_default_modules
      ;;
    2)
      SETUP_TYPE="full"
      set_full_default_modules
      ;;
    3)
      SETUP_TYPE="custom"
      ;;
    4)
      SETUP_TYPE="migrate"
      ;;
    *)
      SETUP_TYPE="minimal"
      set_base_default_modules
      ;;
  esac
}

show_module_selection() {
  # Temporarily disable 'set -u' (unbound variable check) for this function
  # This is needed because we use array expansion patterns that can trigger
  # false positives with empty arrays in Bash 3.2 environments.
  # We restore the setting at the end of the function
  local restore_nounset="false"
  case "$-" in
    *u*) restore_nounset="true"; set +u ;;
  esac

  while true; do
    print_header
    print_section "Step 2: Select Modules to Install"

    echo "Toggle modules on/off by entering their number."
    echo "Enter 'done' when finished, or 'all' to select all."
    echo ""

    local selected="false"
    is_module_selected "homebrew" && selected="true"
    if wizard_is_macos; then
      print_option "1" "package-manager" "Homebrew or MacPorts setup (module name: homebrew)" "$selected"
    elif wizard_is_linux; then
      print_option "1" "package-manager" "APT or DNF setup (module name: homebrew)" "$selected"
    else
      print_option "1" "package-manager" "Auto package manager setup (module name: homebrew)" "$selected"
    fi
    echo ""

    selected="false"
    is_module_selected "zsh" && selected="true"
    if wizard_is_linux; then
      print_option "2" "shell" "Configure login shell: bash or zsh (optional prompt tool)" "$selected"
    else
      print_option "2" "zsh" "Minimal zsh or Oh My Zsh (optional Powerlevel10k prompt)" "$selected"
    fi
    echo ""

    selected="false"
    is_module_selected "cli" && selected="true"
    print_option "3" "cli" "Core CLI utilities (git, jq, ripgrep, etc.)" "$selected"
    echo ""

    selected="false"
    is_module_selected "python" && selected="true"
    print_option "4" "python" "Python environment (UV or pyenv)" "$selected"
    echo ""

    selected="false"
    is_module_selected "java" && selected="true"
    print_option "5" "java" "SDKMAN! + Java + Maven/Gradle" "$selected"
    echo ""

    selected="false"
    is_module_selected "ruby" && selected="true"
    print_option "6" "ruby" "rbenv with RubyGems and Bundler" "$selected"
    echo ""

    selected="false"
    is_module_selected "emacs" && selected="true"
    print_option "7" "emacs" "Emacs editor + minimal config" "$selected"
    echo ""

    selected="false"
    is_module_selected "docker" && selected="true"
    if wizard_is_macos; then
      print_option "8" "docker" "Colima + Docker CLI" "$selected"
    else
      print_option "8" "docker" "Docker engine + CLI" "$selected"
    fi
    echo ""

    selected="false"
    is_module_selected "apps" && selected="true"
    if wizard_supports_apps; then
      print_option "9" "apps" "GUI apps (Bruno, Obsidian)" "$selected"
    else
      print_option "9" "apps" "GUI apps (macOS only)" "$selected"
    fi
    echo ""

    selected="false"
    is_module_selected "rust" && selected="true"
    print_option "10" "rust" "Rust toolchain via rustup" "$selected"
    echo ""

    echo ""
    echo -ne "${WHITE}Enter number to toggle, 'all', or 'done': ${RESET}"
    read -r input
    # Convert to lowercase (compatible with Bash 3.2)
    input=$(echo "$input" | tr '[:upper:]' '[:lower:]')

    # Handle numeric input safely before any arithmetic
    case "$input" in
      1) toggle_selected_module "homebrew"; continue ;;
      2) toggle_selected_module "zsh"; continue ;;
      3) toggle_selected_module "cli"; continue ;;
      4) toggle_selected_module "python"; continue ;;
      5) toggle_selected_module "java"; continue ;;
      6) toggle_selected_module "ruby"; continue ;;
      7) toggle_selected_module "emacs"; continue ;;
      8) toggle_selected_module "docker"; continue ;;
      9)
        if wizard_supports_apps; then
          toggle_selected_module "apps"
        else
          print_warning "Apps module is currently macOS-only and will be skipped on Linux."
          sleep 1
        fi
        continue
        ;;
      10) toggle_selected_module "rust"; continue ;;
      ''|*[!0-9]*)
        ;; # non-numeric; fall through to keyword handling
      *)
        print_warning "Invalid input. Enter a number 1-10, 'all', or 'done'."
        sleep 1
        continue
        ;;
    esac

    case "$input" in
      done|d)
        if ! has_selected_modules; then
          print_warning "Please select at least one module."
          sleep 1
          continue
        fi
        break
        ;;
      all|a)
        set_full_default_modules
        ;;
      none|n|clear|c)
        SELECTED_MODULES=()
        ;;
      *)
        print_warning "Invalid input. Enter a number 1-10, 'all', or 'done'."
        sleep 1
        ;;
    esac
  done

  # Restore 'set -u' if it was previously enabled
  # This ensures strict error checking is maintained for the rest of the script
  if [[ "$restore_nounset" == "true" ]]; then
    set -u
  fi

  # Ensure package manager setup is included if other modules need it.
  local needs_package_manager=("zsh" "cli" "ruby" "emacs" "docker" "apps")
  for mod in "${needs_package_manager[@]}"; do
    if is_module_selected "$mod"; then
      if ! is_module_selected "homebrew"; then
        SELECTED_MODULES=("homebrew" ${SELECTED_MODULES[@]+"${SELECTED_MODULES[@]}"})
        print_info "Added package-manager setup as it's required by other selected modules."
        sleep 1
      fi
      break
    fi
  done
}

show_package_manager_config() {
  if ! is_module_selected "homebrew"; then
    return
  fi

  print_header
  print_section "Step 3a: Package Manager"

  if wizard_is_macos; then
    echo "Choose which macOS package manager setup should use:"
    echo ""
    echo -e "  ${BOLD}1)${RESET} ${GREEN}Auto (Recommended)${RESET} - Homebrew on macOS 13+, MacPorts on macOS 12 and older"
    echo -e "  ${BOLD}2)${RESET} ${CYAN}Homebrew${RESET} - Use Homebrew explicitly"
    echo -e "  ${BOLD}3)${RESET} ${CYAN}MacPorts${RESET} - Use MacPorts explicitly"
  elif wizard_is_linux; then
    echo "Choose which Linux package manager setup should use:"
    echo ""
    echo -e "  ${BOLD}1)${RESET} ${GREEN}Auto (Recommended)${RESET} - APT on Debian/Ubuntu, DNF on Fedora/RHEL-family"
    echo -e "  ${BOLD}2)${RESET} ${CYAN}APT${RESET} - Use apt explicitly"
    echo -e "  ${BOLD}3)${RESET} ${CYAN}DNF${RESET} - Use dnf explicitly"
  else
    echo "Choose package manager mode:"
    echo ""
    echo -e "  ${BOLD}1)${RESET} ${GREEN}Auto (Recommended)${RESET}"
    echo -e "  ${BOLD}2)${RESET} ${CYAN}Homebrew${RESET}"
    echo -e "  ${BOLD}3)${RESET} ${CYAN}APT${RESET}"
  fi
  echo ""
  echo -ne "${WHITE}Enter your choice [1-3] (default: 1): ${RESET}"

  local choice
  read -r choice
  choice=$(validate_choice "$choice" 1 3 1)

  if wizard_is_macos; then
    case "$choice" in
      1) WIZARD_PACKAGE_MANAGER="auto" ;;
      2) WIZARD_PACKAGE_MANAGER="homebrew" ;;
      3) WIZARD_PACKAGE_MANAGER="macports" ;;
      *) WIZARD_PACKAGE_MANAGER="auto" ;;
    esac
  elif wizard_is_linux; then
    case "$choice" in
      1) WIZARD_PACKAGE_MANAGER="auto" ;;
      2) WIZARD_PACKAGE_MANAGER="apt" ;;
      3) WIZARD_PACKAGE_MANAGER="dnf" ;;
      *) WIZARD_PACKAGE_MANAGER="auto" ;;
    esac
  else
    case "$choice" in
      1) WIZARD_PACKAGE_MANAGER="auto" ;;
      2) WIZARD_PACKAGE_MANAGER="homebrew" ;;
      3) WIZARD_PACKAGE_MANAGER="apt" ;;
      *) WIZARD_PACKAGE_MANAGER="auto" ;;
    esac
  fi

  echo ""
  print_success "Package manager mode: $WIZARD_PACKAGE_MANAGER"
  if [[ "$WIZARD_PACKAGE_MANAGER" == "macports" ]]; then
    print_info "Install MacPorts from https://www.macports.org/install.php before running non-dry setup."
  fi

  wait_for_key
}

# Ask which prompt tool to install, scoped to the target shell (Powerlevel10k for zsh,
# Starship for bash). Both are opt-in; the default is the shell's plain prompt.
choose_wizard_prompt() {
  local tool_label tool_value
  if [[ "$WIZARD_TARGET_SHELL" == "zsh" ]]; then
    tool_label="Powerlevel10k"; tool_value="powerlevel10k"
  else
    tool_label="Starship"; tool_value="starship"
  fi

  echo "Which prompt would you like?"
  echo ""
  echo -e "  ${BOLD}1)${RESET} ${GREEN}Plain shell prompt (Recommended)${RESET} - No extra prompt tool"
  echo -e "  ${BOLD}2)${RESET} ${CYAN}${tool_label}${RESET} - Install ${tool_label} for ${WIZARD_TARGET_SHELL}"
  echo ""
  echo -ne "${WHITE}Enter your choice [1-2] (default: 1): ${RESET}"

  local p_choice
  read -r p_choice
  p_choice=$(validate_choice "$p_choice" 1 2 1)

  case "$p_choice" in
    2) WIZARD_PROMPT="$tool_value" ;;
    *) WIZARD_PROMPT="none" ;;
  esac

  echo ""
  if [[ "$WIZARD_PROMPT" == "none" ]]; then
    print_success "Using the plain ${WIZARD_TARGET_SHELL} prompt"
  else
    print_success "Will install ${tool_label}"
  fi
}

show_zsh_config() {
  if ! is_module_selected "zsh"; then
    return
  fi

  print_header
  print_section "Step 3a: Shell Configuration"

  if wizard_is_linux; then
    echo "Which login shell do you use on this machine?"
    echo ""
    echo -e "  ${BOLD}1)${RESET} ${GREEN}bash${RESET} - Default on most Linux distros"
    echo -e "  ${BOLD}2)${RESET} ${CYAN}zsh${RESET} - Configure zsh as your shell"
    echo ""
    local default_shell_choice=1
    [[ "$WIZARD_TARGET_SHELL" == "zsh" ]] && default_shell_choice=2
    echo -ne "${WHITE}Enter your choice [1-2] (default: ${default_shell_choice}): ${RESET}"

    local shell_choice
    read -r shell_choice
    shell_choice=$(validate_choice "$shell_choice" 1 2 "$default_shell_choice")

    case "$shell_choice" in
      1) WIZARD_TARGET_SHELL="bash" ;;
      2) WIZARD_TARGET_SHELL="zsh" ;;
      *) WIZARD_TARGET_SHELL="bash" ;;
    esac

    if [[ "$WIZARD_TARGET_SHELL" == "bash" ]]; then
      WIZARD_ZSH_MODE="plain"
      echo ""
      print_success "Using bash; tool initialization is written to ~/.teeup.common."
      echo ""
      choose_wizard_prompt
      wait_for_key
      return
    fi
    echo ""
  else
    WIZARD_TARGET_SHELL="zsh"
  fi

  echo "Choose your zsh setup:"
  echo ""
  echo -e "  ${BOLD}1)${RESET} ${GREEN}Plain zsh (Recommended)${RESET} - Minimal plugins, direct sourcing"
  echo -e "  ${BOLD}2)${RESET} ${CYAN}Oh My Zsh${RESET} - Oh My Zsh plugin framework"
  echo ""
  echo -ne "${WHITE}Enter your choice [1-2] (default: 1): ${RESET}"

  local choice
  read -r choice
  choice=$(validate_choice "$choice" 1 2 1)

  case "$choice" in
    1) WIZARD_ZSH_MODE="plain" ;;
    2) WIZARD_ZSH_MODE="ohmyzsh" ;;
    *) WIZARD_ZSH_MODE="plain" ;;
  esac

  echo ""
  if [[ "$WIZARD_ZSH_MODE" == "plain" ]]; then
    print_success "Using plain zsh"
  else
    print_success "Using Oh My Zsh"
  fi

  echo ""
  choose_wizard_prompt

  wait_for_key
}

show_python_config() {
  if ! is_module_selected "python"; then
    return
  fi

  print_header
  print_section "Step 3b: Python Configuration"

  echo "Choose your Python package manager:"
  echo ""
  echo -e "  ${BOLD}1)${RESET} ${GREEN}UV (Recommended)${RESET} - Modern, fast, all-in-one Python manager"
  echo -e "  ${BOLD}2)${RESET} ${CYAN}pyenv + poetry${RESET} - Traditional approach (legacy)"
  echo ""
  echo -ne "${WHITE}Enter your choice [1-2] (default: 1): ${RESET}"

  local choice
  read -r choice
  choice=$(validate_choice "$choice" 1 2 1)

  case "$choice" in
    1) WIZARD_USE_UV="true" ;;
    2) WIZARD_USE_UV="false" ;;
    *) WIZARD_USE_UV="true" ;;
  esac

  echo ""

  # Python version input with validation loop
  # Keeps asking until user provides valid version format or empty (default)
  local version
  local valid=false
  while [[ "$valid" == "false" ]]; do
    echo -ne "${WHITE}Python version to install ${DIM}[$WIZARD_PYTHON_VERSION]${RESET}: "
    read -r version

    # Validate format (x.y or x.y.z)
    if validate_version_format "$version" "Python version"; then
      WIZARD_PYTHON_VERSION="${version:-$WIZARD_PYTHON_VERSION}"
      valid=true
    elif [[ -z "$version" ]]; then
      # Empty input, use default
      valid=true
    else
      echo ""  # Add spacing after error message
    fi
  done

  echo ""
  if [[ "$WIZARD_USE_UV" == "true" ]]; then
    print_success "Using UV with Python $WIZARD_PYTHON_VERSION"
  else
    print_success "Using pyenv with Python $WIZARD_PYTHON_VERSION"
  fi

  wait_for_key
}

show_java_config() {
  if ! is_module_selected "java"; then
    return
  fi

  print_header
  print_section "Step 3c: Java Configuration"

  echo "Java will be installed via SDKMAN!"
  echo ""
  echo "Choose your Java version:"
  echo ""
  echo -e "  ${BOLD}1)${RESET} ${GREEN}Java 21 LTS (Temurin)${RESET} - Recommended"
  echo -e "  ${BOLD}2)${RESET} ${CYAN}Java 17 LTS (Temurin)${RESET}"
  echo -e "  ${BOLD}3)${RESET} ${CYAN}Java 11 LTS (Temurin)${RESET}"
  echo -e "  ${BOLD}4)${RESET} ${YELLOW}Custom version${RESET}"
  echo ""
  echo -ne "${WHITE}Enter your choice [1-4] (default: 1): ${RESET}"

  local choice
  read -r choice
  choice=$(validate_choice "$choice" 1 4 1)

  case "$choice" in
    1) WIZARD_JDK_VERSION="21.0.4-tem" ;;
    2) WIZARD_JDK_VERSION="17.0.12-tem" ;;
    3) WIZARD_JDK_VERSION="11.0.24-tem" ;;
    4)
      echo ""
      echo -ne "${WHITE}Enter SDKMAN JDK identifier (e.g., 21.0.4-tem) ${DIM}[$WIZARD_JDK_VERSION]${RESET}: "
      local version
      read -r version
      WIZARD_JDK_VERSION="${version:-$WIZARD_JDK_VERSION}"
      ;;
    *) WIZARD_JDK_VERSION="21.0.4-tem" ;;
  esac

  echo ""
  print_success "Will install Java $WIZARD_JDK_VERSION"

  wait_for_key
}

show_ruby_config() {
  if ! is_module_selected "ruby"; then
    return
  fi

  print_header
  print_section "Step 3d: Ruby Configuration"

  echo "Ruby will be installed via rbenv."
  echo ""

  local version
  local valid=false
  while [[ "$valid" == "false" ]]; do
    echo -ne "${WHITE}Ruby version to install ${DIM}[$WIZARD_RUBY_VERSION]${RESET}: "
    read -r version

    if validate_version_format "$version" "Ruby version"; then
      WIZARD_RUBY_VERSION="${version:-$WIZARD_RUBY_VERSION}"
      valid=true
    elif [[ -z "$version" ]]; then
      valid=true
    else
      echo ""
    fi
  done

  echo ""
  if prompt_yes_no "Update RubyGems after installing Ruby?" "y"; then
    WIZARD_RUBYGEMS_UPDATE="true"
  else
    WIZARD_RUBYGEMS_UPDATE="false"
  fi

  echo ""
  echo -ne "${WHITE}Bundler version ${DIM}[latest]${RESET}: "
  local bundler_version
  read -r bundler_version
  WIZARD_BUNDLER_VERSION="$bundler_version"

  echo ""
  if [[ -n "$WIZARD_BUNDLER_VERSION" ]]; then
    print_success "Using Ruby $WIZARD_RUBY_VERSION with Bundler $WIZARD_BUNDLER_VERSION"
  else
    print_success "Using Ruby $WIZARD_RUBY_VERSION with latest Bundler"
  fi

  wait_for_key
}

show_docker_config() {
  if ! is_module_selected "docker"; then
    return
  fi

  print_header
  if wizard_is_macos; then
    print_section "Step 3e: Docker (Colima) Configuration"
    echo "Colima is a lightweight Docker runtime for macOS."
    echo "Configure the VM resources:"
    echo ""
  else
    print_section "Step 3e: Docker Configuration"
    echo "On Linux, setup installs Docker engine + CLI via your package manager."
    print_info "No Colima VM resource settings are required on Linux."
    wait_for_key
    return
  fi

  # CPU validation with retry loop
  # Accepts 1-32 CPUs (typical range for Docker VM)
  local cpus
  local valid=false
  while [[ "$valid" == "false" ]]; do
    echo -ne "${WHITE}Number of CPUs ${DIM}[$WIZARD_COLIMA_CPUS]${RESET}: "
    read -r cpus

    if validate_positive_integer "$cpus" "CPUs" 1 32; then
      WIZARD_COLIMA_CPUS="${cpus:-$WIZARD_COLIMA_CPUS}"
      valid=true
    elif [[ -z "$cpus" ]]; then
      # Empty input, use default
      valid=true
    else
      echo ""  # Add spacing after error message
    fi
  done

  # Memory validation with retry loop
  # Accepts 2-128 GB (minimum 2GB for Docker, max 128GB reasonable limit)
  local memory
  valid=false
  while [[ "$valid" == "false" ]]; do
    echo -ne "${WHITE}Memory in GiB ${DIM}[$WIZARD_COLIMA_MEMORY]${RESET}: "
    read -r memory

    if validate_positive_integer "$memory" "Memory" 2 128; then
      WIZARD_COLIMA_MEMORY="${memory:-$WIZARD_COLIMA_MEMORY}"
      valid=true
    elif [[ -z "$memory" ]]; then
      # Empty input, use default
      valid=true
    else
      echo ""  # Add spacing after error message
    fi
  done

  # Disk validation with retry loop
  # Accepts 10-500 GB (minimum 10GB for Docker, max 500GB reasonable limit)
  local disk
  valid=false
  while [[ "$valid" == "false" ]]; do
    echo -ne "${WHITE}Disk size in GiB ${DIM}[$WIZARD_COLIMA_DISK]${RESET}: "
    read -r disk

    if validate_positive_integer "$disk" "Disk" 10 500; then
      WIZARD_COLIMA_DISK="${disk:-$WIZARD_COLIMA_DISK}"
      valid=true
    elif [[ -z "$disk" ]]; then
      # Empty input, use default
      valid=true
    else
      echo ""
    fi
  done

  echo ""
  print_success "Colima will use: ${WIZARD_COLIMA_CPUS} CPUs, ${WIZARD_COLIMA_MEMORY}GB RAM, ${WIZARD_COLIMA_DISK}GB disk"

  wait_for_key
}

show_apps_config() {
  if ! is_module_selected "apps"; then
    return
  fi

  if ! wizard_supports_apps; then
    print_warning "Apps module is currently macOS-only. Skipping apps configuration."
    local filtered=()
    local mod
    for mod in ${SELECTED_MODULES[@]+"${SELECTED_MODULES[@]}"}; do
      [[ "$mod" == "apps" ]] && continue
      filtered+=("$mod")
    done
    SELECTED_MODULES=("${filtered[@]}")
    return
  fi

  print_header
  print_section "Step 3f: Apps Configuration"

  echo "Choose which apps to install:"
  echo ""

  if prompt_yes_no "Install Bruno (API client, Postman alternative)?" "y"; then
    WIZARD_INSTALL_BRUNO="true"
  else
    WIZARD_INSTALL_BRUNO="false"
  fi

  echo ""

  if prompt_yes_no "Install Obsidian (note-taking app)?" "y"; then
    WIZARD_INSTALL_OBSIDIAN="true"
  else
    WIZARD_INSTALL_OBSIDIAN="false"
  fi

  echo ""

  local apps_list=""
  [[ "$WIZARD_INSTALL_BRUNO" == "true" ]] && apps_list="Bruno"
  [[ "$WIZARD_INSTALL_OBSIDIAN" == "true" ]] && {
    [[ -n "$apps_list" ]] && apps_list+=", "
    apps_list+="Obsidian"
  }

  if [[ -n "$apps_list" ]]; then
    print_success "Will install: $apps_list"
  else
    print_warning "No apps selected"
  fi

  wait_for_key
}

show_additional_options() {
  print_header
  print_section "Step 4: Additional Options"

  echo "Configure additional settings:"
  echo ""

  # Dotfiles: a neutral base owned by teeup + a personal overlay you bring.
  local wizard_dir sibling_dotfiles df_choice df_default df_src df_dir
  wizard_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  sibling_dotfiles="$(cd "$wizard_dir/../dotfiles" 2>/dev/null && pwd)" || sibling_dotfiles=""

  echo "Dotfiles (shell aliases, git config, tmux, prompt):"
  echo ""
  if [[ -n "$sibling_dotfiles" ]]; then
    echo -e "  ${BOLD}1)${RESET} Use existing dotfiles  ${DIM}(detected: $sibling_dotfiles)${RESET}"
  else
    echo -e "  ${BOLD}1)${RESET} Use existing dotfiles  ${DIM}(enter a path or git URL)${RESET}"
  fi
  echo -e "  ${BOLD}2)${RESET} Generate a neutral starter dotfiles repo you own"
  echo -e "  ${BOLD}3)${RESET} None ${DIM}(teeup writes minimal managed shell blocks)${RESET}"
  echo ""
  df_default=2
  [[ -n "$sibling_dotfiles" ]] && df_default=1
  echo -ne "${WHITE}Enter your choice [1-3] (default: $df_default): ${RESET}"
  read -r df_choice
  df_choice=$(validate_choice "$df_choice" 1 3 "$df_default")

  WIZARD_DOTFILES_SOURCE=""
  WIZARD_INIT_DOTFILES_DIR=""
  case "$df_choice" in
    1)
      WIZARD_DOTFILES_MODE="existing"
      WIZARD_INSTALL_DOTFILES="true"
      if [[ -n "$sibling_dotfiles" ]]; then
        echo -ne "${WHITE}Path or git URL [${sibling_dotfiles}]: ${RESET}"
        read -r df_src
        WIZARD_DOTFILES_SOURCE="${df_src:-$sibling_dotfiles}"
      else
        echo -ne "${WHITE}Path or git URL: ${RESET}"
        read -r df_src
        WIZARD_DOTFILES_SOURCE="$df_src"
        if [[ -z "$WIZARD_DOTFILES_SOURCE" ]]; then
          print_warning "No source given; generating a neutral starter instead."
          WIZARD_DOTFILES_MODE="generate"
          WIZARD_INIT_DOTFILES_DIR="$HOME/dotfiles"
        fi
      fi
      ;;
    2)
      WIZARD_DOTFILES_MODE="generate"
      WIZARD_INSTALL_DOTFILES="true"
      echo -ne "${WHITE}Target directory [${HOME}/dotfiles]: ${RESET}"
      read -r df_dir
      WIZARD_INIT_DOTFILES_DIR="${df_dir:-$HOME/dotfiles}"
      ;;
    3|*)
      WIZARD_DOTFILES_MODE="none"
      WIZARD_INSTALL_DOTFILES="false"
      ;;
  esac

  echo ""

  if prompt_yes_no "Reconcile existing Antigen/pyenv/stale shell config?" "y"; then
    WIZARD_RECONCILE_EXISTING_CONFIG="true"
  else
    WIZARD_RECONCILE_EXISTING_CONFIG="false"
  fi

  echo ""

  if wizard_is_macos; then
    if prompt_yes_no "Remove verified Homebrew package overlaps after MacPorts replacements are active?" "n"; then
      WIZARD_CLEANUP_HOMEBREW_OVERLAPS="true"
    else
      WIZARD_CLEANUP_HOMEBREW_OVERLAPS="false"
    fi

    echo ""

    if is_module_selected "apps" && [[ "$WIZARD_PACKAGE_MANAGER" != "homebrew" ]]; then
      if prompt_yes_no "Use existing Homebrew for GUI app casks when MacPorts is selected?" "n"; then
        WIZARD_ALLOW_HOMEBREW_CASK_FALLBACK="true"
      else
        WIZARD_ALLOW_HOMEBREW_CASK_FALLBACK="false"
      fi
      echo ""
    fi

    if prompt_yes_no "Apply macOS defaults (fast key repeat, show extensions, etc.)?" "n"; then
      WIZARD_TUNE_DEFAULTS="true"
    else
      WIZARD_TUNE_DEFAULTS="false"
    fi
  else
    WIZARD_CLEANUP_HOMEBREW_OVERLAPS="false"
    WIZARD_ALLOW_HOMEBREW_CASK_FALLBACK="false"
    WIZARD_TUNE_DEFAULTS="false"
    print_info "Skipping macOS-only options on ${WIZARD_PLATFORM_LABEL}."
  fi

  echo ""

  if prompt_yes_no "Preview mode only (dry-run - no actual changes)?" "n"; then
    WIZARD_DRY_RUN="true"
  else
    WIZARD_DRY_RUN="false"
  fi

  wait_for_key
}

show_summary() {
  print_header
  print_section "Step 5: Review Configuration"

  if [[ "$WIZARD_DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}🔍 Dry-run: nothing below will be installed — this is a preview.${RESET}"
    echo ""
    echo -e "${BOLD}Modules that would be installed:${RESET}"
  else
    echo -e "${BOLD}Modules to install:${RESET}"
  fi
  echo ""
  for mod in ${SELECTED_MODULES[@]+"${SELECTED_MODULES[@]}"}; do
    if [[ "$mod" == "zsh" ]]; then
      echo -e "  ${GREEN}✓${RESET} shell (${WIZARD_TARGET_SHELL})"
    else
      echo -e "  ${GREEN}✓${RESET} $mod"
    fi
  done

  echo ""
  echo -e "${BOLD}Configuration:${RESET}"
  echo ""

  if is_module_selected "homebrew"; then
    echo -e "  Package manager: ${CYAN}$WIZARD_PACKAGE_MANAGER${RESET}"
  fi

  if is_module_selected "zsh"; then
    local prompt_label
    case "$WIZARD_PROMPT" in
      powerlevel10k) prompt_label="Powerlevel10k" ;;
      starship)      prompt_label="Starship" ;;
      *)             prompt_label="plain prompt" ;;
    esac
    if [[ "$WIZARD_TARGET_SHELL" == "bash" ]]; then
      echo -e "  Shell: ${CYAN}bash${RESET} with ${CYAN}bash-completion${RESET} + ${CYAN}${prompt_label}${RESET}"
    elif [[ "$WIZARD_ZSH_MODE" == "plain" ]]; then
      echo -e "  Shell: ${CYAN}Plain zsh${RESET} with ${CYAN}${prompt_label}${RESET}"
    else
      echo -e "  Shell: ${CYAN}Oh My Zsh${RESET} with ${CYAN}${prompt_label}${RESET}"
    fi
  fi

  if is_module_selected "python"; then
    if [[ "$WIZARD_USE_UV" == "true" ]]; then
      echo -e "  Python: ${CYAN}UV${RESET} with version ${CYAN}$WIZARD_PYTHON_VERSION${RESET}"
    else
      echo -e "  Python: ${CYAN}pyenv${RESET} with version ${CYAN}$WIZARD_PYTHON_VERSION${RESET}"
    fi
  fi

  if is_module_selected "java"; then
    echo -e "  Java: ${CYAN}$WIZARD_JDK_VERSION${RESET}"
  fi

  if is_module_selected "ruby"; then
    if [[ -n "$WIZARD_BUNDLER_VERSION" ]]; then
      echo -e "  Ruby: ${CYAN}$WIZARD_RUBY_VERSION${RESET}, Bundler ${CYAN}$WIZARD_BUNDLER_VERSION${RESET}"
    else
      echo -e "  Ruby: ${CYAN}$WIZARD_RUBY_VERSION${RESET}, latest Bundler"
    fi
    echo -e "  Update RubyGems: ${CYAN}$WIZARD_RUBYGEMS_UPDATE${RESET}"
  fi

  if is_module_selected "docker"; then
    if wizard_is_macos; then
      echo -e "  Colima: ${CYAN}${WIZARD_COLIMA_CPUS} CPUs, ${WIZARD_COLIMA_MEMORY}GB RAM, ${WIZARD_COLIMA_DISK}GB disk${RESET}"
    else
      echo -e "  Docker: ${CYAN}engine + CLI via package manager${RESET}"
    fi
  fi

  case "${WIZARD_DOTFILES_MODE:-}" in
    existing) echo -e "  Dotfiles: ${CYAN}use existing (${WIZARD_DOTFILES_SOURCE:-auto-detected})${RESET}" ;;
    generate) echo -e "  Dotfiles: ${CYAN}generate starter at ${WIZARD_INIT_DOTFILES_DIR:-$HOME/dotfiles}${RESET}" ;;
    none|*)   echo -e "  Dotfiles: ${CYAN}none (minimal managed blocks)${RESET}" ;;
  esac
  echo -e "  Reconcile existing config: ${CYAN}$WIZARD_RECONCILE_EXISTING_CONFIG${RESET}"
  if wizard_is_macos; then
    echo -e "  Cleanup Homebrew overlaps: ${CYAN}$WIZARD_CLEANUP_HOMEBREW_OVERLAPS${RESET}"
    echo -e "  Homebrew cask fallback: ${CYAN}$WIZARD_ALLOW_HOMEBREW_CASK_FALLBACK${RESET}"
    echo -e "  Tune macOS defaults: ${CYAN}$WIZARD_TUNE_DEFAULTS${RESET}"
  fi

  if [[ "$WIZARD_DRY_RUN" == "true" ]]; then
    echo ""
    echo -e "  ${YELLOW}${BOLD}🔍 DRY-RUN MODE: Preview only, no changes will be made${RESET}"
  fi

  echo ""
}

run_setup() {
  print_header
  print_section "Running Setup"

  # Build the command. The shell preference travels via TARGET_SHELL, so emit the
  # generic 'shell' module (not 'zsh', which would force TARGET_SHELL=zsh on the CLI).
  local modules_str
  local out_mods=()
  local m
  for m in ${SELECTED_MODULES[@]+"${SELECTED_MODULES[@]}"}; do
    if [[ "$m" == "zsh" ]]; then
      out_mods+=("shell")
    else
      out_mods+=("$m")
    fi
  done
  modules_str=$(IFS=,; echo "${out_mods[*]}")

  local cmd="./teeup.sh"
  [[ "$WIZARD_DRY_RUN" == "true" ]] && cmd+=" --dry-run"
  [[ "$WIZARD_RECONCILE_EXISTING_CONFIG" == "true" ]] && cmd+=" --reconcile-existing-config"
  cmd+=" --prompt $WIZARD_PROMPT"
  cmd+=" --only $modules_str"
  case "${WIZARD_DOTFILES_MODE:-}" in
    existing) [[ -n "$WIZARD_DOTFILES_SOURCE" ]] && cmd+=" --dotfiles $WIZARD_DOTFILES_SOURCE" ;;
    generate) cmd+=" --init-dotfiles ${WIZARD_INIT_DOTFILES_DIR:-$HOME/dotfiles}" ;;
  esac

  # Export environment variables
  export PYTHON_VERSION="$WIZARD_PYTHON_VERSION"
  export USE_UV="$WIZARD_USE_UV"
  export ZSH_MODE="$WIZARD_ZSH_MODE"
  export PROMPT="$WIZARD_PROMPT"
  export TARGET_SHELL="$WIZARD_TARGET_SHELL"
  export PACKAGE_MANAGER="$WIZARD_PACKAGE_MANAGER"
  export JDK_VERSION="$WIZARD_JDK_VERSION"
  export RUBY_VERSION="$WIZARD_RUBY_VERSION"
  export RUBYGEMS_UPDATE="$WIZARD_RUBYGEMS_UPDATE"
  export BUNDLER_VERSION="$WIZARD_BUNDLER_VERSION"
  export INSTALL_DOTFILES="$WIZARD_INSTALL_DOTFILES"
  export RECONCILE_EXISTING_CONFIG="$WIZARD_RECONCILE_EXISTING_CONFIG"
  export CLEANUP_HOMEBREW_OVERLAPS="$WIZARD_CLEANUP_HOMEBREW_OVERLAPS"
  export ALLOW_HOMEBREW_CASK_FALLBACK="$WIZARD_ALLOW_HOMEBREW_CASK_FALLBACK"
  export TUNE_DEFAULTS="$WIZARD_TUNE_DEFAULTS"
  export DRY_RUN="$WIZARD_DRY_RUN"
  export COLIMA_CPUS="$WIZARD_COLIMA_CPUS"
  export COLIMA_MEMORY="$WIZARD_COLIMA_MEMORY"
  export COLIMA_DISK="$WIZARD_COLIMA_DISK"
  export INSTALL_BRUNO="$WIZARD_INSTALL_BRUNO"
  export INSTALL_OBSIDIAN="$WIZARD_INSTALL_OBSIDIAN"

  echo -e "${DIM}Running: $cmd${RESET}"
  echo -e "${DIM}With environment:${RESET}"
  echo -e "${DIM}  PYTHON_VERSION=$PYTHON_VERSION${RESET}"
  echo -e "${DIM}  USE_UV=$USE_UV${RESET}"
  echo -e "${DIM}  ZSH_MODE=$ZSH_MODE${RESET}"
  echo -e "${DIM}  PROMPT=$PROMPT${RESET}"
  echo -e "${DIM}  TARGET_SHELL=$TARGET_SHELL${RESET}"
  echo -e "${DIM}  PACKAGE_MANAGER=$PACKAGE_MANAGER${RESET}"
  echo -e "${DIM}  JDK_VERSION=$JDK_VERSION${RESET}"
  echo -e "${DIM}  RUBY_VERSION=$RUBY_VERSION${RESET}"
  echo -e "${DIM}  RUBYGEMS_UPDATE=$RUBYGEMS_UPDATE${RESET}"
  echo -e "${DIM}  BUNDLER_VERSION=$BUNDLER_VERSION${RESET}"
  echo -e "${DIM}  INSTALL_DOTFILES=$INSTALL_DOTFILES${RESET}"
  echo -e "${DIM}  RECONCILE_EXISTING_CONFIG=$RECONCILE_EXISTING_CONFIG${RESET}"
  echo -e "${DIM}  CLEANUP_HOMEBREW_OVERLAPS=$CLEANUP_HOMEBREW_OVERLAPS${RESET}"
  echo -e "${DIM}  ALLOW_HOMEBREW_CASK_FALLBACK=$ALLOW_HOMEBREW_CASK_FALLBACK${RESET}"
  echo -e "${DIM}  TUNE_DEFAULTS=$TUNE_DEFAULTS${RESET}"
  echo -e "${DIM}  DRY_RUN=$DRY_RUN${RESET}"
  echo -e "${DIM}  COLIMA_CPUS=$COLIMA_CPUS${RESET}"
  echo -e "${DIM}  COLIMA_MEMORY=$COLIMA_MEMORY${RESET}"
  echo -e "${DIM}  COLIMA_DISK=$COLIMA_DISK${RESET}"
  echo -e "${DIM}  INSTALL_BRUNO=$INSTALL_BRUNO${RESET}"
  echo -e "${DIM}  INSTALL_OBSIDIAN=$INSTALL_OBSIDIAN${RESET}"
  echo ""

  # Get the script directory
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Run the setup script
  if [[ -f "$SCRIPT_DIR/teeup.sh" ]]; then
    local setup_args=()
    [[ "$WIZARD_DRY_RUN" == "true" ]] && setup_args+=("--dry-run")
    if [[ "$WIZARD_RECONCILE_EXISTING_CONFIG" == "true" ]]; then
      setup_args+=("--reconcile-existing-config")
    else
      setup_args+=("--no-reconcile-existing-config")
    fi
    setup_args+=("--prompt" "$WIZARD_PROMPT")
    setup_args+=("--only" "$modules_str")
    case "${WIZARD_DOTFILES_MODE:-}" in
      existing) [[ -n "$WIZARD_DOTFILES_SOURCE" ]] && setup_args+=("--dotfiles" "$WIZARD_DOTFILES_SOURCE") ;;
      generate) setup_args+=("--init-dotfiles" "${WIZARD_INIT_DOTFILES_DIR:-$HOME/dotfiles}") ;;
    esac
    "$SCRIPT_DIR/teeup.sh" "${setup_args[@]}"
  else
    print_error "teeup.sh not found in $SCRIPT_DIR"
    exit 1
  fi
}

run_migration() {
  print_header
  print_section "Migration: pyenv → UV"

  echo "This will migrate your Python environment from pyenv to UV."
  echo ""
  echo "What will happen:"
  echo "  1. Install UV alongside pyenv (non-destructive)"
  echo "  2. Install your Python version via UV"
  echo "  3. Migrate pipx tools to 'uv tool'"
  echo "  4. Update shell configuration"
  echo ""

  print_warning "This is non-destructive. pyenv will remain installed."
  echo ""

  if ! prompt_yes_no "Proceed with migration?"; then
    print_info "Migration cancelled."
    exit 0
  fi

  echo ""

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if [[ -f "$SCRIPT_DIR/teeup.sh" ]]; then
    "$SCRIPT_DIR/teeup.sh" --migrate-to-uv
  else
    print_error "teeup.sh not found in $SCRIPT_DIR"
    exit 1
  fi
}

show_completion() {
  print_header

  # Dry-run made no changes, so don't tell the user to reload the shell or verify
  # installs that never happened.
  if [[ "$WIZARD_DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║              🔍  Dry-Run Complete  🔍                        ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo ""
    echo "No changes were made to your system — the commands above were a preview."
    echo ""
    echo -e "${BOLD}Next step:${RESET}"
    echo ""
    echo "  Run the wizard again and choose a real run (decline dry-run in"
    echo "  Additional Options), or run teeup.sh directly without --dry-run."
    echo ""
    return
  fi

  echo -e "${GREEN}${BOLD}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                                                              ║"
  echo "║              🎉  Setup Complete!  🎉                         ║"
  echo "║                                                              ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo -e "${RESET}"
  echo ""

  echo -e "${BOLD}Next steps:${RESET}"
  echo ""
  echo -e "  1. Open a new terminal or run: ${CYAN}exec ${WIZARD_TARGET_SHELL}${RESET}"
  echo ""
  echo "  2. Verify your installation:"

  if is_module_selected "python"; then
    if [[ "$WIZARD_USE_UV" == "true" ]]; then
      echo -e "     ${DIM}uv --version${RESET}"
      echo -e "     ${DIM}python --version${RESET}"
    else
      echo -e "     ${DIM}pyenv --version${RESET}"
      echo -e "     ${DIM}python --version${RESET}"
    fi
  fi

  if is_module_selected "java"; then
    echo -e "     ${DIM}sdk version${RESET}"
    echo -e "     ${DIM}java -version${RESET}"
  fi

  if is_module_selected "ruby"; then
    echo -e "     ${DIM}ruby --version${RESET}"
    echo -e "     ${DIM}gem --version${RESET}"
    echo -e "     ${DIM}bundle --version${RESET}"
  fi

  if is_module_selected "docker"; then
    if wizard_is_macos; then
      echo -e "     ${DIM}colima status${RESET}"
    fi
    echo -e "     ${DIM}docker version${RESET}"
  fi

  if is_module_selected "emacs"; then
    echo -e "     ${DIM}emacs --version${RESET}"
  fi

  if is_module_selected "rust"; then
    echo -e "     ${DIM}rustc --version${RESET}"
    echo -e "     ${DIM}cargo --version${RESET}"
  fi

  if is_module_selected "zsh" && [[ "$WIZARD_PROMPT" == "starship" ]]; then
    echo -e "     ${DIM}starship --version${RESET}"
  fi

  echo ""
  echo -e "${GREEN}Enjoy your new development environment! 🚀${RESET}"
  echo ""
}

#################################
# ===== Main Wizard Flow ====== #
#################################

main() {
  # Check if teeup.sh exists
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ ! -f "$SCRIPT_DIR/teeup.sh" ]]; then
    print_error "teeup.sh not found in $SCRIPT_DIR"
    print_info "The wizard requires teeup.sh to be in the same directory."
    exit 1
  fi

  detect_wizard_platform

  # Run wizard
  show_welcome
  show_setup_type

  case "$SETUP_TYPE" in
    minimal)
      show_package_manager_config
      show_zsh_config
      show_additional_options
      show_summary

      if confirm_start; then
        run_setup
        show_completion
      else
        print_info "Installation cancelled."
      fi
      ;;
    full)
      show_package_manager_config
      show_zsh_config
      show_python_config
      show_java_config
      show_ruby_config
      show_docker_config
      show_apps_config
      show_additional_options
      show_summary

      if confirm_start; then
        run_setup
        show_completion
      else
        print_info "Installation cancelled."
      fi
      ;;
    custom)
      show_module_selection
      show_package_manager_config
      show_zsh_config
      show_python_config
      show_java_config
      show_ruby_config
      show_docker_config
      show_apps_config
      show_additional_options
      show_summary

      if confirm_start; then
        run_setup
        show_completion
      else
        print_info "Installation cancelled."
      fi
      ;;
    migrate)
      run_migration
      ;;
  esac
}

# Run main function
main "$@"
