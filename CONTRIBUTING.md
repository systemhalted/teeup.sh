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

The `run_test` line is not optional bookkeeping: a `test_*` function nobody
passes to `run_test` never runs, and the suite still reports green, which is
worse than a failing test because nothing says so. `print_summary` compares the
`test_*` functions the file defines against the ones it was asked to run and
fails the suite over any that were left out.

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
10. Per-machine overrides go in `<config>/teeup/machines/<hostname>.conf`,
    which is the user's own file and survives a `git pull`; the checkout's
    `machines/<hostname>.conf` is the fallback, for anyone keeping a fork.
    Either is sourced last, so it wins over the answers file. It is also the
    only
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
14. A machine that cannot have the capability at all — not "this step
    failed", but "this tool does not run here" — is a third outcome install
    and configure must be able to report, distinct from both success and
    failure. Call `not_applicable "<message>"` (`lib/capability.sh`) instead
    of a plain `warn` + `exit 0`: it prints `<message>` in place of
    instructions that could never have worked, and tells `cap_run` to treat
    the run as neither done nor failed. Concretely: `teeup install`/bootstrap
    mark nothing done, `teeup has <name>` still reports not-installed, and
    `teeup status` lists the capability as "not applicable on this machine"
    rather than "installed" or leaving it out entirely. A capability whose
    job is only partly blocked (it did something real, just not everything —
    `fonts` on MacPorts records the font family every tool follows even
    though the actual font file needs installing by hand) is not this case;
    keep that a normal, honest success with a `warn` about the gap. Reserve
    `not_applicable` for when nothing about the capability could apply.
    Never call it to swallow a real error — a genuine failure must still
    `warn`/`die` or exit non-zero, or bootstrap's core-tier gate would wave
    it through unnoticed.
15. An editor whose settings are JSON (Zed, VS Code) never gets a shipped
    `settings.json`: its hooks set only the keys teeup owns, with
    `json_set_key <file> <key> <json-value>` or
    `json_merge_key <file> <key> <json-object>` from `lib/files.sh`. The key is
    one literal top-level key (VS Code's `workbench.colorTheme` stays flat),
    the value is a JSON literal (`json_quote` makes one from text), comments
    and trailing commas are read, the write goes through
    `write_managed_file` (so `DRY_RUN` previews it), and a symlink or a file
    jq cannot edit is left alone with a warning.
16. A `theme-apply` or `font-apply` belonging to a capability that may not be
    installed -- every editor, and anything outside the core tier -- starts
    with `if ! state_done check "cap-$TEEUP_CAP"; then exit 0; fi`: `teeup
    theme set` runs every capability's hooks, including on machines where that
    app was never installed through teeup. (A core capability that is always
    present, `wezterm` and `theme`, gates on its own config file existing
    instead.) A hook whose own `configure` runs it --
    one that writes the app's settings file, so there is work to do during the
    install itself, before the done marker exists -- widens the gate to
    `if ! state_done check "cap-$TEEUP_CAP" && [[ "${TEEUP_CONFIGURING:-}" != "$TEEUP_CAP" ]]; then exit 0; fi`
    and that `configure` runs `export TEEUP_CONFIGURING="$TEEUP_CAP"` before
    `cap_run_optional "$TEEUP_CAP" theme-apply` (Zed and VS Code do this). A
    hook that only tells an already-running app to reload (Emacs, Neovim)
    keeps the narrow gate: during a fresh install there is no running app to
    tell, and the next start reads the theme anyway. Theme names an
    editor needs live in the palette next to the colours (`emacs_theme`,
    `zed_theme`, `zed_extension`, `neovim_colorscheme`, `vscode_theme`,
    `vscode_extension`; an extension of `none` installs nothing), so every
    theme, a user theme included, must define each of them in both modes or
    `teeup theme set` refuses to render.
17. A `tier=lazy` capability is reached on first use, never at bootstrap.
    `provides` lists the commands it makes available: `teeup configure
    teeup-runtime` (`shims_generate` in `lib/lazy.sh`) writes one shim per
    command into `~/.local/state/teeup/shims`, last on `PATH`, and each shim
    runs `teeup lazy-run <cap> <command>`. There is no list of lazy
    capabilities to update; adding the directory registers it. Every token
    must be a plain command name (letters, digits and `_.+-`, starting with a
    letter or digit), and two lazy capabilities must not provide the same
    command; `teeup commands --check` fails on either condition. `have`
    (`lib/core.sh`) never counts a shim as an installed command, so
    `pkg_install <pkg> <command>` still installs the package represented by
    the shim.
18. `apps` names the application bundles `teeup launch` opens, separated by
    `;` because names contain spaces (`apps="Visual Studio Code"`). Use the
    `app` artifact name from the cask, without `.app`. The first entry is what
    `launch` opens with `open -a`; when that bundle is missing from
    `/Applications` and `~/Applications`, the capability is installed first.
    Tests point `TEEUP_APPS_DIR` at an empty directory.
19. mise-managed tools go through `lib/mise.sh`. `mise_ensure_global <tool>
    [version]` adds a tool to the global config without rewriting a version
    the user pinned; `mise_wrapper_write <command> <tool> [runtime...]` writes
    an install-on-first-call wrapper into `~/.local/bin` (the `ai`
    capability) and never replaces a file there that it did not write. Every
    mise call except the wrapper's `mise x` runs with `-C /`, so a project's
    `mise.toml` in the current directory cannot shadow the global file. Check
    registry names with `mise registry`. Language runtimes use `teeup install
    dev-env <lang>` (`dev_env_install`), never a capability or a shim.
20. Two test hooks join `TEEUP_TEST_MISSING`: `TEEUP_TEST_TTY=yes|no`
    overrides the terminal check in `teeup lazy-run`, so a piped `y` can
    answer its question, and `hide_host_commands <name...>`
    (`tests/helper.sh`) adds every copy of a command on the host's `PATH` to
    `TEEUP_TEST_MISSING` by absolute path. A test can then prove an install on
    a runner that has `docker` in `/usr/bin` while still finding the copy made
    by the mocked install. `tests/capabilities/colima.sh` is the reference
    round trip.
21. `configure` is re-run by `teeup update` on every machine, so it must be
    quiet and cheap when nothing has changed: report "Already ..." instead of
    rewriting, and never restart an application or print a multi-line manual
    step unconditionally. `defaults_write` now leaves a key that already
    holds the value alone and records the domains it did write, so a
    `configure` restarts an app with
    `if defaults_changed com.apple.dock; then run_cmd killall Dock || true; fi`.
    A one-time notice uses `state_done ensure <name>`, which succeeds only the
    first time.
22. `teeup reset <cap>` and a migration's `migration_refresh <cap>` both
    re-run your `configure` with `TEEUP_RESET` or `TEEUP_REFRESH` set to the
    capability's name, which turns each `copy_config_once` in it into
    `refresh_config` or `refresh_if_pristine`. Install every user-facing file
    through `copy_config_once` (rendering into a temporary file first when the
    content depends on the machine, and passing the shipped file as
    `copy_config_once`'s third `display_src` argument so the messages name it
    rather than the temp file — see `capabilities/zsh/configure`) and both
    verbs work for free; a `cp` of your own is invisible to them. A capability
    with no `config/` or `home/` directory is not resettable, and says so.
23. `teeup remove <cap>` uninstalls the `casks` and `packages` your metadata
    names and clears the done marker. Add a `remove` script only for machine
    state teeup created that a package manager cannot undo: a LaunchAgent
    (`launchagent_remove <label>`), recorded `defaults` (`defaults_restore`),
    a `hidutil` mapping. It runs before the uninstall, while the tool is
    still there, and never deletes the user's configuration files.
24. A file teeup owns but the user may edit carries a stock record
    (`stock_record`, written by `copy_config_once`). `config_is_pristine
    <file>` asks whether it still matches; `write_config_region <file>
    <label>` rewrites a managed region and keeps a pristine file reading as
    pristine (and refuses a symlink); `refresh_if_pristine <src> <dest>` is
    the stock-checksum rule a migration uses; `backup_copy <file>` takes a
    copy and leaves the original in place for a minimal patch. Hook events
    for the user's own scripts are `post-bootstrap`, `post-update` and
    `theme-set` (`TEEUP_HOOK_EVENTS` in `lib/hooks.sh`); adding one means a
    new `.sample` under `capabilities/teeup-runtime/default/hooks/` and a
    `hook_run <event> [args]` call where it fires.
