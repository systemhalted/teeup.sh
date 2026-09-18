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
   cd teeup.sh
   ```
3. **Create a feature branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```

---

## 🆕 Adding a New Module

To add a new module to the setup scripts, follow these steps:

### 1. Add Toggle Variable

In `teeup.sh`, add a toggle variable in the "User Toggles" section. Toggles are
left **empty** here and resolved from the selected profile after argument parsing
(see `apply_profile_defaults`), so the profile and `--only`/`--except` can drive
them while an explicit `RUN_*` env var still wins:

```bash
# Module toggles (resolved from TEEUP_PROFILE in apply_profile_defaults).
RUN_HOMEBREW="${RUN_HOMEBREW:-}"
RUN_ZSH="${RUN_ZSH:-}"
RUN_CLI="${RUN_CLI:-}"
# ... existing modules ...
RUN_NEWMODULE="${RUN_NEWMODULE:-}"  # Add your new module
```

Then decide whether your module belongs in the lean `base` profile (package
manager + shell + cli) or only in `full`, and wire its default in
`apply_profile_defaults()`:

```bash
apply_profile_defaults() {
  # ...
  RUN_CLI="${RUN_CLI:-true}"                # in base
  RUN_NEWMODULE="${RUN_NEWMODULE:-$extra}"  # full-only (extra=true only when profile=full)
}
```

Also add a case to `parse_except_modules()` so `--except newmodule` works.

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
./legacy/tests/run_tests.sh

# Run specific test file
./legacy/tests/test_teeup.sh
./legacy/tests/test_teeup-wizard.sh
```

### Testing with shellenv

[shellenv](https://github.com/systemhalted/shellenv) gives teeup a per-project shell sandbox: runs execute under a *pinned* bash version, and every `$HOME`/`TMPDIR`/`XDG_*` write teeup makes lands in `./.shellenv/<env>/home/` instead of your real home — so you can exercise the dotfile-writing paths for real without touching your own dotfiles. (`./.shellenv/` is gitignored.)

One-time setup (needs `cc`/`make`/`tar`; the bash build takes ~a minute):

```bash
shellenv init
shellenv install bash@5.2                     # build the pinned runtime from source
shellenv create --shell bash@5.2 --profile strict   # from the teeup.sh directory
```

Then, from the teeup.sh directory:

```bash
# Test suite under the pinned bash
shellenv exec -- ./legacy/tests/run_tests.sh

# Dry-run everything; sandboxed even without --dry-run
shellenv exec -- ./legacy/teeup.sh --dry-run --all

# Real dotfile writes, contained: lands in .shellenv/default/home/, not ~
shellenv exec -- ./legacy/teeup.sh --init-dotfiles

# Throwaway HOME per run (idempotency checks)
shellenv exec --ephemeral -- ./legacy/teeup.sh --init-dotfiles

# Real package installs with full namespace isolation (network required)
shellenv exec --container ubuntu:24.04 -- ./legacy/teeup.sh --only cli
```

Notes:
- `shellenv exec --strict-shell -- …` fails instead of falling back when the pinned bash isn't installed.
- Host-mode sandboxing contains `$HOME`-class writes only; package installs and other system mutations need `--container`.
- If you run a bare `shellenv` binary from outside its release directory, set `SHELLENV_PROFILES` to its bundled `profiles/` directory so `--profile` resolution works.

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
   ./legacy/tests/run_tests.sh
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

---

## Adding a capability (new runtime)

1. Create `capabilities/<name>/` with `capability`, `install`, `configure`.
2. `capability` is a sourced `KEY=value` file: `summary`, `group`, `tier`
   (`core|daily|lazy`), `requires`, `provides`, `packages`, `casks`, `apps`,
   `interactive`.
3. `install` only installs packages (`pkg_install`, `cask_install`).
   `configure` only writes configuration (`copy_config_once`,
   `write_managed_file`, `append_once`, `run_cmd`). Both are idempotent and
   run as `bash -eu` with `lib/all.sh` loaded and the answers file sourced.
   Judge success by the postcondition, not by the exit code of the last
   command: end an install with the check that the thing is actually there.
4. Never call `sudo`; use `run_privileged`. Mutate the machine only through
   `run_cmd`, or through the file primitives (`copy_config_once`,
   `write_managed_file`, `append_once`), which carry their own dry-run guard —
   do not wrap those in `run_cmd`.
5. `provides` must not list a command macOS already ships (`python3`, `ruby`,
   `java`, `git`, `perl`).
6. Add the name to `capabilities/core.list` or `daily.list` if it is not lazy.
7. Add `tests/capabilities/<name>.sh` using the mock harness; run
   `./bin/teeup commands --check && ./tests/run.sh` before committing.
8. Shipped files live in one of three directories, by owner:
   `config/` is copied once into `~/.config` and belongs to the user after
   that; `home/` is copied once into `$HOME` under its literal dotfile name
   (`home/.zshrc` becomes `~/.zshrc`); `default/` stays teeup's and is read at
   runtime through `$TEEUP_PATH`, so upgrades improve it without touching
   anything the user edited. Thin user files source thick default files.
9. Files under `default/` and `home/` are zsh or Lua, not bash: shellcheck
   does not run on them, so keep them simple and guard every optional tool.
10. Per-machine overrides go in `machines/<hostname>.conf`, which is committed
    and sourced last, so it wins over the answers file. It is also the only
    place a work identity is configured (`TEEUP_WORK_EMAIL`, plus
    `TEEUP_WORK_GH_HOST` for a GitHub Enterprise host or
    `TEEUP_WORK_GH_ACCOUNT` for a second account on github.com): git has one
    identity everywhere, and the wizard never asks about work. See
    `machines/example.conf.sample`.
11. If the tool has colours, add `capabilities/<name>/themed/<file>.tpl`.
    `teeup theme set` renders every template once per mode with `{{ key }}`,
    `{{ key_strip }}` (no leading `#`) and `{{ key_rgb }}` (`r,g,b`) replaced
    from `themes/<theme>/{dark,light}.toml`, and stages the results in
    `~/.local/state/teeup/current/theme/<mode>/<file>`. A user template of the
    same basename in `~/.config/teeup/themed/` wins. Basenames share one
    namespace, so no two capabilities may ship the same one
    (`teeup commands --check` fails on a duplicate).
12. If the tool needs to be told about a new theme or font, add an executable
    `capabilities/<name>/theme-apply` or `capabilities/<name>/font-apply`. Both
    run exactly like `install` and `configure` (`bash -eu`, `lib/all.sh`
    loaded, answers sourced, `TEEUP_CAP` and `TEEUP_CAP_DIR` exported).
    `theme-apply` additionally gets `TEEUP_THEME_DIR`
    (`~/.local/state/teeup/current/theme`) and `TEEUP_THEME_NAME`;
    `font-apply` gets `TEEUP_FONT_FAMILY`. Both are optional, and a failure
    warns without aborting the switch, so keep them to "tell the app to
    reload" rather than real work.
13. Native macOS settings go through `lib/macos.sh`: `defaults_write` (which
    records the prior value so `remove` can call `defaults_restore`),
    `launchagent_install <label>` with the plist on stdin, and
    `launchagent_remove <label>` in `remove`. Never call `defaults write` or
    `launchctl` directly.
