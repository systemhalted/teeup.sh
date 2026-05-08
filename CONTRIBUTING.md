# Contributing to teeup.sh

Thank you for your interest in contributing! This document provides guidelines for contributing to the teeup.sh project.

---

## 📋 Table of Contents

- [Getting Started](#getting-started)
- [Adding a New Module](#adding-a-new-module)
- [Code Style Guidelines](#code-style-guidelines)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)

---

## 🚀 Getting Started

1. **Fork the repository**
2. **Clone your fork:**
   ```bash
   git clone https://github.com/yourusername/teeup.sh.git
   cd setup
   ```
3. **Create a feature branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```

---

## 🆕 Adding a New Module

To add a new module to the setup scripts, follow these steps:

### 1. Add Toggle Variable

In `teeup.sh`, add a toggle variable in the "User Toggles" section:

```bash
# Module toggles (all enabled by default, use --only to run specific modules)
RUN_HOMEBREW="${RUN_HOMEBREW:-true}"
RUN_ZSH="${RUN_ZSH:-true}"
RUN_CLI="${RUN_CLI:-true}"
RUN_PYTHON="${RUN_PYTHON:-true}"
RUN_JAVA="${RUN_JAVA:-true}"
RUN_EMACS="${RUN_EMACS:-true}"
RUN_DOCKER="${RUN_DOCKER:-true}"
RUN_APPS="${RUN_APPS:-true}"
RUN_NEWMODULE="${RUN_NEWMODULE:-true}"  # Add your new module
```

### 2. Update `list_modules()` Function

Add your module to the list:

```bash
list_modules() {
  cat <<EOF
Available modules:
  homebrew  - Package manager setup (Homebrew or MacPorts; compatibility module name)
  zsh       - Zsh integration + Powerlevel10k + plugins
  ohmyzsh   - Legacy alias for zsh with ZSH_MODE=ohmyzsh
  cli       - Core CLI utilities (git, jq, ripgrep, etc.)
  python    - Python environment (UV or pyenv/poetry)
  java      - SDKMAN! + Java + Maven/Gradle
  emacs     - Emacs editor + minimal config
  docker    - Colima + Docker CLI
  apps      - GUI apps (Bruno, Obsidian)
  newmodule - Your new module description
EOF
  exit 0
}
```

### 3. Add Case in `parse_only_modules()`

Handle the module name in the parser:

```bash
parse_only_modules() {
  # ... existing code ...
  for mod in "${MODS[@]}"; do
    mod_lower=$(echo "$mod" | tr '[:upper:]' '[:lower:]')
    case "$mod_lower" in
      homebrew) RUN_HOMEBREW=true ;;
      # ... existing cases ...
      newmodule) RUN_NEWMODULE=true ;;
      *) warn "Unknown module: $mod" ;;
    esac
  done
}
```

### 4. Implement Installation Logic

Add the installation section:

```bash
###################################
# ===== New Module Setup ======== #
###################################
if [[ "$RUN_NEWMODULE" == "true" ]]; then
  log "Setting up New Module..."
  
  # Your installation logic here
  pkg_install newmodule newmodule
  
  # Configuration steps
  # ...
  
else
  log "Skipping New Module setup (RUN_NEWMODULE=false)"
fi
```

### 5. Add to Wizard

In `teeup-wizard.sh`, add configuration screen:

```bash
show_newmodule_config() {
  if ! is_module_selected "newmodule"; then
    return
  fi

  print_header
  print_section "Step 3x: New Module Configuration"

  echo "Configure your new module:"
  echo ""
  
  # Your configuration prompts
  
  wait_for_key
}
```

Add to module selection:

```bash
show_module_selection() {
  # ... existing code ...
  
  selected="false"
  is_module_selected "newmodule" && selected="true"
  print_option "9" "newmodule" "Your new module description" "$selected"
  echo ""
}
```

### 6. Add Tests

In `tests/test_teeup.sh`, add tests:

```bash
test_newmodule_support() {
  local content
  content=$(cat "$PROJECT_DIR/teeup.sh")
  assert_contains "$content" "RUN_NEWMODULE" "Should define RUN_NEWMODULE"
  assert_contains "$content" "newmodule" "Should support newmodule"
}
```

Add to test execution:

```bash
run_test "New Module support" test_newmodule_support
```

### 7. Update Documentation

Update `README.md`:

- Add to Available Modules table
- Add to Installed Tools table
- Add configuration section if needed

---

## 🎨 Code Style Guidelines

### Bash Compatibility

- **Target:** Bash 3.2 (macOS default)
- **Strict mode:** Always use `set -euo pipefail`
- **No Bash 4 syntax:** Avoid `${var,,}`, use `tr '[:upper:]' '[:lower:]'` instead

### Array Handling

Use safe array expansion for Bash 3.2 compatibility:

```bash
# Good (safe for empty arrays)
for item in ${array[@]+"${array[@]}"}; do
  echo "$item"
done

# Bad (fails with set -u on empty arrays)
for item in "${array[@]}"; do
  echo "$item"
done
```

### Variable Naming

- **Environment variables:** `UPPERCASE_WITH_UNDERSCORES`
- **Local variables:** `lowercase_with_underscores`
- **Functions:** `snake_case`

### Error Handling

```bash
# Always check command success
if ! command -v tool >/dev/null 2>&1; then
  warn "Tool not found"
  return 1
fi

# Use || for optional commands
pkg_install package package || warn "Failed to install package"
```

### Logging

Use the provided logging functions:

```bash
log "Installing something..."   # Info message
ok "Installation complete"      # Success message
warn "Non-critical warning"     # Warning message
err "Critical error"            # Error message
```

### Idempotency

Always check if something is already installed:

```bash
if pkg_installed package; then
  log "Package already exists, skipping"
elif [[ -f "$CONFIG_FILE" ]]; then
  log "Config already exists, skipping"
else
  # Create config
fi
```

### Package Manager Support

Package-backed modules should use `pkg_install <package> [command]` instead of calling `brew` or `port` directly. This keeps `PACKAGE_MANAGER=auto` working across newer Homebrew machines and older MacPorts machines.

Use explicit Homebrew calls only for Homebrew-only features, such as casks, and guard them with the existing fallback behavior.

---

## 🧪 Testing

### Running Tests

```bash
# Run all tests
./tests/run_tests.sh

# Run specific test file
./tests/test_teeup.sh
./tests/test_teeup-wizard.sh
```

### Writing Tests

Tests use the helper framework in `tests/test_helper.sh`:

```bash
test_my_feature() {
  local content
  content=$(cat "$PROJECT_DIR/teeup.sh")
  assert_contains "$content" "my_feature" "Should contain my_feature"
}

# Add to test execution
run_test "My feature" test_my_feature
```

### Test Assertions

Available assertions:

- `assert_equals expected actual message`
- `assert_contains haystack needle message`
- `assert_file_exists file message`
- `assert_dir_exists dir message`
- `assert_success exit_code message`
- `assert_failure exit_code message`

---

## 📝 Pull Request Process

1. **Update tests** to cover your changes
2. **Run the test suite** and ensure all tests pass:
   ```bash
   ./tests/run_tests.sh
   ```
3. **Update documentation** (README.md, etc.)
4. **Commit with clear message:**
   ```bash
   git commit -m "Add feature: Brief description
   
   - Detail 1
   - Detail 2
   - Detail 3"
   ```
5. **Push to your fork:**
   ```bash
   git push origin feature/your-feature-name
   ```
6. **Create Pull Request** with:
   - Clear title
   - Description of changes
   - Test results
   - Screenshots (if UI changes)

---

## 🐛 Bug Reports

When reporting bugs, include:

1. **macOS version:** `sw_vers`
2. **Architecture:** `uname -m`
3. **Error output:** Full error message
4. **Steps to reproduce**
5. **Expected vs actual behavior**

---

## 💡 Feature Requests

For feature requests:

1. **Describe the feature** clearly
2. **Explain the use case** and benefits
3. **Consider alternatives** you've explored
4. **Offer to implement** if possible

---

## 📜 Code of Conduct

- Be respectful and inclusive
- Provide constructive feedback
- Focus on the code, not the person
- Help others learn and grow

---

## 🙏 Thank You!

Your contributions make this project better for everyone. We appreciate your time and effort!

---

## 📞 Questions?

If you have questions about contributing:

1. Check existing issues and PRs
2. Review the documentation
3. Open a discussion issue
4. Ask in the community

Happy contributing! 🚀
