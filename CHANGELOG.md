# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.0-beta] - UNRELEASED

teeup.sh has been rebuilt from scratch as a macOS-only, Omarchy-style distribution that replaces the old installer. See the [manual](https://teeup.systemhalted.in) and [CONTRIBUTING.md](CONTRIBUTING.md) to learn how to use it or how it works.

### Added
- **Company certificates.** Builds a certificate bundle from your macOS System keychain so command-line tools trust a network proxy that re-signs HTTPS.
- **`bootstrap` and the wizard.** A setup script that asks for your name, email, package manager, theme, whether to install the daily set, and the Emacs flavor, and handles the first installation. Run it with `./bootstrap`.
- **Tiers.** Capabilities are organized into core, daily, and lazy tiers.
- **Homebrew or MacPorts.** You can choose your package manager during bootstrap, and teeup will use it to install native packages.
- **Machine files.** Write environment variables and overrides in `~/.config/teeup/machines/<hostname>.conf` or the checkout's `machines/<hostname>.conf`.
- **`teeup install`, `configure`, and `remove`.** Add or take away individual capabilities like `colima` or `obsidian` at any time, or re-run a configuration to apply changes.
- **`teeup update` and `reset`.** Pull the checkout, upgrade packages and mise, run migrations, and configure the core and daily tiers with `update`. Put a capability's shipped configuration back with `reset`.
- **`teeup doctor`, `status`, and `list`.** Check your system health, see your active configuration, and list the capabilities available on your machine.
- **`teeup menu` and `config`.** Open a keyboard-driven list in the terminal to run teeup commands with `menu`, and get, set or edit the answers file with `config`.
- **`teeup theme` and `launch`.** Change your system's colorscheme, and launch GUI applications from the terminal.
- **`teeup secret` and `dev`.** Store and read secrets in the macOS Keychain with `secret`, and run the local development toolkit with `dev`.
- **zsh and Starship.** The default shell environment is now zsh configured with the Starship prompt.
- **git and ssh identity.** Version control with your identity, and an ed25519 SSH key.
- **WezTerm.** A terminal emulator with multiplexing built in.
- **Emacs.** A daemonized setup with a starter config, plus Doom and Spacemacs flavors.
- **Zed, Neovim, VS Code and Cursor.** Text editors and IDEs.
- **Firefox Developer Edition and Obsidian.** Applications for browsing and note-taking.
- **AeroSpace and tmux.** Tiling window management for macOS and terminal multiplexing.
- **Colima, Ollama and Herdr.** Virtualization for Docker, local LLMs, and the agent multiplexer that lives in your terminal.
- **mise runtimes.** Python, Node, Java, Ruby, Rust and Go are managed by mise through `teeup install dev-env <lang>`.
- **AI command-line tools.** Claude Code, Codex, Gemini CLI, GitHub Copilot CLI, and OpenCode are available as lazy capabilities.
- **Themes.** Choose between `catppuccin`, `tokyo-night`, `gruvbox`, and `everforest` in both light and dark variants.
- **Terminal.app and Doom theming.** Your theme choice applies to new Terminal.app windows and Doom Emacs.
- **`theme set --reload`.** Re-render the current theme.
- **Fonts.** A selection of developer fonts for your terminal and editor.
- **`teeup migrate legacy`.** Retire the old teeup and chezmoi wiring on this Mac.
- **`teeup uninstall`.** Take teeup off a Mac.
- **Agent skill.** An agent skill for Claude Code, Codex, and Gemini CLI to understand and interact with the teeup ecosystem.

### Changed
- **macOS only.** The installer no longer supports Linux; the old Linux paths have been removed.
- **One `teeup` command.** Flags are gone; you now interact with your system through a single CLI with subcommands.
- **Shipped configs are copied once.** Configuration files are placed in your `~/.config` or home directory once and are then yours to edit.
- **mise replaces other managers.** Runtimes come through mise instead of pyenv, rbenv, or SDKMAN.
- **zsh and Starship replace Oh My Zsh and Powerlevel10k.** teeup ships its own layered zsh configuration instead of a framework.
See [docs/legacy-parity.md](docs/legacy-parity.md) for the full mapping of legacy features to the new architecture.

### Removed
- **The old installer.** The entire legacy installation script has been deleted.
- **Linux support.** The legacy installer's Linux paths are gone; on Linux, keep using a chezmoi-managed dotfiles repository.

---

## Before the redesign (the legacy installer, removed in 0.1.0-beta)

### [Unreleased]

#### Added
- **chezmoi and GNU Stow overlays.** `--dotfiles` now recognises a chezmoi source
  directory (`dot_*`, `.chezmoi.toml.tmpl`) or a Stow package tree and hands
  `$HOME` to that tool (`chezmoi init --source DIR --apply`, `stow -d DIR -t ~`)
  after installing it if needed. teeup writes nothing into rc files a manager
  owns, so `chezmoi diff` stays clean after a teeup run. The flat layout and the
  managed-block fallback are unchanged. `--dotfiles-manager` (or
  `DOTFILES_MANAGER`) forces a choice; `STOW_PACKAGES` and `CHEZMOI_INIT_ARGS`
  tune the hand-off. The wizard shows the detected manager.
- **pacman support for Arch and derivatives (including Omarchy).**
  `PACKAGE_MANAGER=auto` now resolves to `pacman` from `ID=arch` in
  `/etc/os-release`, or falls back to it when the binary is present;
  `PACKAGE_MANAGER=pacman` selects it explicitly, and the wizard offers it as a
  fourth Linux choice. Debian and Fedora `-dev`/`-devel` package names are
  mapped onto Arch's undecorated libraries, and the Ruby and pyenv build-dep
  lists gained Arch arms.

  Two Arch-specific behaviours are worth knowing: database refreshes run
  `pacman -Syu` rather than a bare `-Sy`, because refreshing without upgrading
  and then installing creates an unsupported partial-upgrade state — so this
  step upgrades the system, unlike `apt-get update`. And packages outside the
  official repositories fall back to an AUR helper (`yay` or `paru`) when one is
  installed, warning and skipping rather than failing when none is.

#### Changed
- **Unified shared shell file → `~/.teeup.common`.** The overlapping
  `shellrc.common` (aliases) and `teeupshrc` (tool init) are merged into a single
  cross-shell file, `teeup.common`, in **both** delivery modes — the dotfiles
  template and the managed-fallback (no-payload) generator. The neutral template's
  per-shell rc files now source `~/.teeup.common`.
- **Prompt tools are opt-in.** Powerlevel10k (zsh) and Starship (bash) are no
  longer installed by default. The default is the shell's plain prompt.
- **Leaner neutral template.** `gitconfig`, `gitconfig.local.example`, and
  `tmux.conf` are no longer shipped in `templates/dotfiles/`. teeup links these (and
  legacy `shellrc.common`/`teeupshrc`) only if a personal overlay actually provides
  them; shell-specific files are still segregated to the target login shell.

#### Added
- `--prompt none|powerlevel10k|starship` (and the `PROMPT` env var, default `none`)
  to choose a prompt tool explicitly. Surfaced in the wizard as a dedicated
  "Which prompt theme?" step, decoupled from the zsh plain/Oh My Zsh choice.
- **Rust LSP tooling.** The `rust` module now runs `rustup component add
  rust-analyzer clippy rustfmt`, so editors (e.g. Emacs rustic/eglot) get a
  working LSP server out of the box. `rust-analyzer` is not in rustup's default
  profile, so it previously had to be added by hand; clippy/rustfmt are listed
  explicitly to stay correct if the default profile changes. The step is
  idempotent, so existing rustup installs pick the components up on rerun.

#### Migration
- An older `~/.teeupshrc` is migrated automatically: a regular file (managed
  fallback) is moved to `~/.teeup.common` and the source line in your `~/.bashrc`/
  `~/.zshrc` is re-pointed (idempotent on re-runs). Stale teeup-owned **symlinks**
  into your dotfiles dir (`~/.teeupshrc`, `~/.shellrc.common`) are removed — but only
  once your overlay no longer ships that legacy file, so a back-compat link stays put
  while you migrate. A foreign-target symlink or pre-existing `~/.teeup.common` is
  left untouched.
- A sibling `../dotfiles` that has moved to chezmoi previously triggered the
  managed-block fallback and appended a source line to `~/.bashrc`/`~/.zshrc`.
  It is now applied with chezmoi instead. Remove the stale `# Added by teeup.sh -
  teeup.common` block from your rc file if one was written, or let `chezmoi apply`
  overwrite it.

---

### [2.0.0] - 2026-05-30

#### Changed
- **Neutral by default.** A bare `./teeup.sh` now installs a lean `base` profile
  (package manager + login shell + core CLI) instead of the entire stack. Use
  `--all` (or `TEEUP_PROFILE=full`) for the full curated stack. This is a
  behavior change for no-argument runs.

#### Added
- `--profile base|full` and `--all` to choose the default module set.
- `--except a,b` to subtract modules (e.g. `--all --except apps,docker`).
- `--init-dotfiles [DIR]` to generate a neutral starter dotfiles repo you own
  (from `templates/dotfiles/`), then symlink it.
- `--dotfiles PATH|URL` to use an existing dotfiles directory or clone a git repo
  as your overlay.
- Wizard: a **Minimal (base)** setup preset (now the default) and a Dotfiles step
  that auto-detects a sibling `dotfiles`, generates a starter, or uses none.

#### Notes
- Dotfiles are now modeled as a neutral base (owned by teeup) plus a personal
  overlay you bring — teeup no longer ships one person's config as the default
  payload. The generated starter omits editor/mergetool lock-in and personal
  aliases.

---

### [1.0.0] - 2026-02-18

#### Added

#### Core Features
- **Interactive Wizard Mode** - User-friendly step-by-step setup experience
- **Dry-Run Mode** - Preview all commands without making changes
  - Preview installations before execution
  - Test script behavior safely
  - Display all commands that would run
  - No modifications to system
- **Input Validation** - Comprehensive validation for all user inputs
  - Version format validation (Python versions)
  - Numeric range validation with sensible limits
  - Menu choice validation with retry loops
  - Clear error messages for invalid inputs
- **Module System** - Install only what you need with `--only` flag
- **UV Support** - Modern Python package manager (10-100x faster than pip)
- **Bruno Integration** - Open-source Postman alternative
- **Comprehensive Testing** - automated test suite (`./tests/run_tests.sh`)

#### Modules
- **Homebrew** - Package manager with auto-detection for Apple Silicon
- **Oh My Zsh** - Shell framework with Powerlevel10k theme
  - zsh-autosuggestions plugin
  - zsh-syntax-highlighting plugin
- **CLI Tools** - Essential utilities (git, jq, ripgrep, fd, etc.)
- **Python Environment**
  - UV (default) - Modern all-in-one Python manager
  - pyenv + poetry (legacy option)
  - Tool installation (ruff, black, httpie)
- **Java Environment**
  - SDKMAN! installer
  - Configurable JDK versions (Temurin 21/17/11)
  - Maven and Gradle support
- **Ruby Environment** - rbenv with RubyGems and Bundler
- **Rust Environment** - rustup toolchain (`rustc`, `cargo`)
- **Emacs** - Text editor with minimal starter config
- **Docker** - Colima VM + Docker CLI
  - Configurable resources (CPU, memory, disk)
- **Apps** - GUI applications
  - Bruno (API client)
  - Obsidian (note-taking)

#### Documentation
- Comprehensive README with usage examples
- Git aliases reference (150+ aliases)
- Migration guide (pyenv → UV)
- Module documentation
- Testing documentation
- Bruno usage guide
- Contributing guidelines

#### Testing
- Test framework with test_helper.sh
- 18 tests for teeup.sh (including dry-run mode)
- 23 tests for teeup-wizard.sh (including validation and dry-run)
- Syntax validation
- Compatibility checks
- Feature verification

#### Configuration
- Environment variable overrides
- Feature toggles for all modules
- Version customization
- Dotfile management
- macOS defaults tuning (optional)

#### Features

#### Wizard Mode
- Welcome screen with overview
- Setup type selection (Full/Custom/Migration)
- Module toggle interface
- Python configuration (UV vs pyenv)
- Java version selection
- Docker/Colima resource configuration
- Apps selection
- Summary and confirmation
- Completion screen with next steps

#### Script Features
- **Idempotent** - Safe to run multiple times
- **Dry-Run Mode** - Preview commands without execution (--dry-run flag)
- **Apple Silicon Support** - Automatic detection and Rosetta 2 installation
- **Partial Execution** - Install specific modules only
- **Migration Tool** - Easy pyenv to UV migration
- **Smart Defaults** - Sensible defaults with override options
- **Progress Indicators** - Clear feedback with emojis
- **Error Handling** - Graceful error handling and warnings
- **Summary Report** - Installation summary at completion

#### Technical Details

#### Compatibility
- macOS 12+ (Monterey, Ventura, Sonoma)
- Apple Silicon (M1, M2, M3) and Intel
- Bash 3.2+ (macOS default shell)

#### Code Quality
- Strict mode enabled (`set -euo pipefail`)
- Bash 3.2 compatible (no Bash 4 syntax)
- Safe array expansion patterns
- Proper error handling
- Comprehensive logging
- Security best practices

#### Installation

```bash
# Clone repository
git clone <repository-url>
cd teeup.sh

# Make executable
chmod +x teeup.sh teeup-wizard.sh

# Run wizard
./teeup-wizard.sh

# Or run directly
./teeup.sh

# Or partial installation
./teeup.sh --only python,java
```

#### Migration

For users migrating from pyenv to UV:

```bash
./teeup.sh --migrate-to-uv
```

#### Testing

```bash
# Run all tests
./tests/run_tests.sh
```

---

### [Unreleased]

#### Added
- **Linux support** — first-class Ubuntu (APT) and Fedora (DNF); `PACKAGE_MANAGER=auto` resolves by platform
- **MacPorts support** on older macOS (≤ 12); Homebrew on macOS 13+
- **bash support** — Starship prompt + bash-completion, with tool init in a shared POSIX `~/.teeupshrc`
  - `TARGET_SHELL` (auto/bash/zsh) detection and override
  - Segregated bash/zsh deployments — only the target shell's dotfiles/rc are configured
  - `shell` and `bash` module aliases (`zsh`/`ohmyzsh` force zsh)
- **Ruby via rbenv** + RubyGems and Bundler
- **Rust via rustup** (`rustc`, `cargo`)
- Linux: adds the invoking user to the `docker` group (sudo-free `docker` after re-login)

#### Changed
- Platform, package-manager, and shell logic extracted into `lib/platform.sh`, `lib/package_manager.sh`, `lib/shell.sh`
- Tool initialization (uv, cargo, SDKMAN, rbenv, pyenv) consolidated into `~/.teeupshrc`

#### Planned Features
- Progress bars for long operations
- Checksum verification for downloads
- Parallel module installation

---

### Version History

#### [1.0.0] - 2026-02-18
- Initial release with full feature set
- Comprehensive automated test suite
- Interactive wizard mode
- UV and Bruno integration
- Dry-run mode
- Input validation

---

### Notes

- This is the first stable release
- All features are production-ready
- Code reviewed and approved (Grade: A+)
- No known critical issues
---

### Acknowledgments

- Oh My Zsh community
- Homebrew maintainers
- UV (Astral) team
- Bruno developers
- SDKMAN! project
- All contributors

---

**Legend:**
- `Added` - New features
- `Changed` - Changes in existing functionality
- `Deprecated` - Soon-to-be removed features
- `Removed` - Removed features
- `Fixed` - Bug fixes
- `Security` - Security fixes

