#!/usr/bin/env bash
# teeup.sh — Get your new machine ready for the first drive.
# Installs a package manager, zsh integration, UV, SDKMAN!, Emacs, Colima (+ docker CLIs), Bruno, Obsidian, and common CLI tools.
# Safe to rerun.
#
# Usage:
#   ./teeup.sh                    # Run full setup
#   ./teeup.sh --only python      # Run only Python setup
#   ./teeup.sh --only java,docker # Run only Java and Docker setup
#   ./teeup.sh --migrate-to-uv    # Migrate from pyenv to UV
#   ./teeup.sh --help             # Show usage

set -euo pipefail

SETUP_START_EPOCH="$(date +%s)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if DEFAULT_DOTFILES_DIR="$(cd "$SCRIPT_DIR/../dotfiles" 2>/dev/null && pwd)"; then
  :
else
  DEFAULT_DOTFILES_DIR=""
fi

#############################
# ===== User Toggles ===== #
#############################

# Versions
PYTHON_VERSION="${PYTHON_VERSION:-3.12.5}"          # Override by: PYTHON_VERSION=3.13.x ./teeup.sh
JDK_VERSION="${JDK_VERSION:-21.0.4-tem}"            # SDKMAN version identifier (e.g., "21.0.4-tem" for Temurin 21)
RUBY_VERSION="${RUBY_VERSION:-3.4.9}"               # Override by: RUBY_VERSION=4.0.3 ./teeup.sh
BUNDLER_VERSION="${BUNDLER_VERSION:-}"              # Optional Bundler version; empty installs latest

# Feature toggles
USE_UV="${USE_UV:-true}"                            # Use uv instead of pyenv/poetry/pipx (recommended)
INSTALL_PY_TOOLS="${INSTALL_PY_TOOLS:-true}"        # Install Python tools (via uv tool or pipx)
RUBYGEMS_UPDATE="${RUBYGEMS_UPDATE:-true}"          # Update RubyGems after installing Ruby
INSTALL_DOTFILES="${INSTALL_DOTFILES:-true}"        # Install/symlink dotfiles from DOTFILES_DIR
RECONCILE_EXISTING_CONFIG="${RECONCILE_EXISTING_CONFIG:-false}"  # Disable old Antigen/pyenv/stale shell config
ZSH_MODE="${ZSH_MODE:-plain}"                       # plain or ohmyzsh
DOTFILES_DIR="${DOTFILES_DIR:-$DEFAULT_DOTFILES_DIR}"
PACKAGE_MANAGER="${PACKAGE_MANAGER:-auto}"          # auto, homebrew, macports, apt, or dnf
STRICT_PLATFORM="${STRICT_PLATFORM:-false}"         # fail instead of skip when module/platform mismatch
ALLOW_HOMEBREW_CASK_FALLBACK="${ALLOW_HOMEBREW_CASK_FALLBACK:-false}"  # Use existing Homebrew for casks in MacPorts mode
CLEANUP_HOMEBREW_OVERLAPS="${CLEANUP_HOMEBREW_OVERLAPS:-false}"        # Remove verified Homebrew overlaps after MacPorts install
UPGRADE_HOMEBREW="${UPGRADE_HOMEBREW:-false}"       # Upgrade all Homebrew packages (default: false)
TUNE_DEFAULTS="${TUNE_DEFAULTS:-false}"             # Apply some macOS defaults
CREATE_MIN_EMACS_INIT="${CREATE_MIN_EMACS_INIT:-true}"
CREATE_OBSIDIAN_VAULT="${CREATE_OBSIDIAN_VAULT:-false}"  # Create starter vault folder
DRY_RUN="${DRY_RUN:-false}"                         # Preview commands without executing them

# Module toggles (all enabled by default, use --only to run specific modules)
# RUN_HOMEBREW is kept as the public module name for compatibility. It now means
# "prepare the selected package manager" and may resolve to Homebrew or MacPorts.
RUN_HOMEBREW="${RUN_HOMEBREW:-true}"
RUN_ZSH="${RUN_ZSH:-true}"
RUN_CLI="${RUN_CLI:-true}"
RUN_PYTHON="${RUN_PYTHON:-true}"
RUN_JAVA="${RUN_JAVA:-true}"
RUN_RUBY="${RUN_RUBY:-true}"
RUN_EMACS="${RUN_EMACS:-true}"
RUN_DOCKER="${RUN_DOCKER:-true}"
RUN_APPS="${RUN_APPS:-true}"
RUN_RUST="${RUN_RUST:-true}"

# Colima defaults (edit as desired)
COLIMA_PROFILE="${COLIMA_PROFILE:-default}"
COLIMA_CPUS="${COLIMA_CPUS:-4}"
COLIMA_MEMORY="${COLIMA_MEMORY:-8}"     # in GiB
COLIMA_DISK="${COLIMA_DISK:-60}"        # in GiB
COLIMA_RUNTIME="${COLIMA_RUNTIME:-docker}"  # docker or containerd

#################################
# ===== Helpers / Logging ===== #
#################################

emoj() { printf "%b " "$1"; }
log()  { printf "%b %s\n" "🔹" "$*"; }
ok()   { printf "%b %s\n" "✅" "$*"; }
warn() { printf "%b %s\n" "⚠️" "$*" >&2; }
err()  { printf "%b %s\n" "❌" "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

format_duration() {
  local total="$1"
  local hours minutes seconds
  hours=$((total / 3600))
  minutes=$(((total % 3600) / 60))
  seconds=$((total % 60))

  if [[ "$hours" -gt 0 ]]; then
    printf "%dh %dm %ds" "$hours" "$minutes" "$seconds"
  elif [[ "$minutes" -gt 0 ]]; then
    printf "%dm %ds" "$minutes" "$seconds"
  else
    printf "%ds" "$seconds"
  fi
}

ZSHRC="${ZSHRC:-$HOME/.zshrc}"
ZPROFILE="${ZPROFILE:-$HOME/.zprofile}"
ZSH_INTEGRATION="${ZSH_INTEGRATION:-$HOME/.config/mac-setup/zsh.zsh}"
BASHRC="${BASHRC:-$HOME/.bashrc}"
BASH_PROFILE="${BASH_PROFILE:-$HOME/.bash_profile}"
PROFILE="${PROFILE:-$HOME/.profile}"
TEEUPSHRC="${TEEUPSHRC:-$HOME/.teeupshrc}"

# Execute command or preview in dry-run mode
# Usage: run_cmd command [args...]
# In dry-run mode: prints command without executing
# In normal mode: executes command
run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    emoj "🔍"
    echo "[DRY-RUN] Would execute: $*"
    return 0
  else
    "$@"
  fi
}

# True if the ruby-build that `rbenv install` will use knows about a Ruby
# version. Checks via rbenv (which prefers a plugin ruby-build over a system
# one) and falls back to a standalone ruby-build.
ruby_build_knows() {
  rbenv install --list-all 2>/dev/null | grep -qx "$1" \
    || ruby-build --definitions 2>/dev/null | grep -qx "$1"
}

# Make sure ruby-build can resolve a given Ruby version, refreshing it if not.
# Distro/Homebrew ruby-build packages are frequently too old for recent
# releases; refresh via Homebrew or the rbenv git plugin (which takes
# precedence over a system ruby-build). Returns non-zero (non-fatal) when the
# version still can't be resolved, so callers can skip rather than abort.
ensure_ruby_build_definition() {
  local version="$1"
  local plugin="${RBENV_ROOT:-$HOME/.rbenv}/plugins/ruby-build"

  if [[ "$DRY_RUN" == "true" ]]; then
    emoj "🔍"
    echo "[DRY-RUN] Would refresh ruby-build (git plugin/Homebrew) if it can't resolve Ruby $version"
    return 0
  fi

  ruby_build_knows "$version" && return 0

  log "ruby-build doesn't list Ruby $version; refreshing ruby-build definitions..."
  if is_macos && have brew && brew list ruby-build >/dev/null 2>&1; then
    brew upgrade ruby-build || brew install ruby-build || true
  elif [[ -d "$plugin/.git" ]]; then
    git -C "$plugin" pull --ff-only || true
  else
    [[ -e "$plugin" ]] && mv "$plugin" "$plugin.bak.$$" 2>/dev/null || true
    git clone --depth 1 https://github.com/rbenv/ruby-build.git "$plugin" || true
  fi
  have rbenv && rbenv rehash >/dev/null 2>&1 || true

  if ruby_build_knows "$version"; then
    ok "ruby-build refreshed; Ruby $version is now resolvable."
    return 0
  fi
  warn "ruby-build still cannot resolve Ruby $version after refresh."
  return 1
}

require_command_available() {
  local command_name="$1"
  local context="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    return 0
  fi
  if ! have "$command_name"; then
    err "$context did not make '$command_name' available on PATH."
    err "Open a new terminal or fix PATH, then rerun setup."
    exit 1
  fi
}

require_path_available() {
  local path="$1"
  local context="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    return 0
  fi
  if [[ ! -e "$path" ]]; then
    err "$context did not create expected path: $path"
    exit 1
  fi
}

append_once() {
  # append_once <file> <unique_marker> <block...>
  local file="$1"; shift
  local marker="$1"; shift
  local tmp
  if grep -q "$marker" "$file" 2>/dev/null; then
    log "Already present in $(basename "$file"): $marker"
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    emoj "🔍"
    echo "[DRY-RUN] Would update $file with: $marker"
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  touch "$file"
  tmp="$(mktemp)"
  {
    echo ""
    echo "# ${marker}"
    cat
  } > "$tmp"
  cat "$tmp" >> "$file"
  rm -f "$tmp"
  ok "Updated $(basename "$file") with: $marker"
}

write_managed_file() {
  local file="$1"
  local marker="$2"
  local tmp
  if [[ "$DRY_RUN" == "true" ]]; then
    emoj "🔍"
    echo "[DRY-RUN] Would write $file ($marker)"
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"
  cat > "$tmp"
  if [[ -f "$file" ]] && cmp -s "$tmp" "$file"; then
    rm -f "$tmp"
    log "Already current: $file"
    return 0
  fi
  mv "$tmp" "$file"
  ok "Wrote $file ($marker)"
}

backup_target() {
  local target="$1"
  local backup
  backup="${target}.teeup_backup_$(date +%Y%m%d%H%M%S)"
  if [[ "$DRY_RUN" == "true" ]]; then
    emoj "🔍"
    echo "[DRY-RUN] Would back up $target to $backup"
  else
    mv "$target" "$backup"
    ok "Backed up $target to $backup"
  fi
}

install_dotfile_link() {
  local source="$1"
  local target="$2"
  local current
  if [[ ! -f "$source" ]]; then
    warn "Dotfile source missing, skipping: $source"
    return 0
  fi
  if [[ -L "$target" ]]; then
    current="$(readlink "$target")"
    if [[ "$current" == "$source" ]]; then
      log "Dotfile already linked: $target"
      return 0
    fi
  fi
  if [[ -e "$target" || -L "$target" ]]; then
    backup_target "$target"
  fi
  run_cmd ln -s "$source" "$target"
}

disable_matching_lines() {
  local file="$1"
  local pattern="$2"
  local reason="$3"
  local tmp
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  if [[ -L "$file" ]]; then
    log "Skipping direct reconciliation for symlinked file: $file"
    return 0
  fi
  if ! awk -v pattern="$pattern" '$0 ~ pattern && $0 !~ /^#/ { found=1 } END { exit found ? 0 : 1 }' "$file"; then
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    emoj "🔍"
    echo "[DRY-RUN] Would disable matching lines in $file: $reason"
    return 0
  fi
  cp -p "$file" "${file}.teeup_backup_$(date +%Y%m%d%H%M%S)"
  tmp="$(mktemp)"
  awk -v pattern="$pattern" -v reason="$reason" '
    $0 ~ pattern && $0 !~ /^#/ {
      print "# Disabled by teeup.sh (" reason "): " $0
      next
    }
    { print }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
  ok "Disabled stale config in $file: $reason"
}

dotfiles_payload_available() {
  [[ -n "$DOTFILES_DIR" ]] || return 1
  case "${TARGET_SHELL:-}" in
    zsh)  [[ -f "$DOTFILES_DIR/zshrc" ]] ;;
    bash) [[ -f "$DOTFILES_DIR/bashrc" ]] ;;
    *)    [[ -f "$DOTFILES_DIR/zshrc" || -f "$DOTFILES_DIR/bashrc" ]] ;;
  esac
}

# shellcheck source=lib/platform.sh
source "$SCRIPT_DIR/lib/platform.sh"
# shellcheck source=lib/package_manager.sh
source "$SCRIPT_DIR/lib/package_manager.sh"
# shellcheck source=lib/shell.sh
source "$SCRIPT_DIR/lib/shell.sh"

homebrew_casks_allowed() {
  is_macos || return 1
  [[ "$RESOLVED_PACKAGE_MANAGER" == "homebrew" ]] && return 0
  [[ "$ALLOW_HOMEBREW_CASK_FALLBACK" == "true" ]] && have brew && return 0
  return 1
}

cleanup_homebrew_overlaps() {
  if [[ "$RESOLVED_PACKAGE_MANAGER" != "macports" || "$CLEANUP_HOMEBREW_OVERLAPS" != "true" ]]; then
    return 0
  fi
  if ! have brew; then
    log "Homebrew is not installed; no Homebrew overlaps to clean up."
    return 0
  fi

  log "Cleaning verified Homebrew overlaps now managed by MacPorts."
  local overlap formula command_name command_path
  local overlaps=(
    zsh:zsh
    git:git
    wget:wget
    curl:curl
    jq:jq
    htop:htop
    tree:tree
    tmux:tmux
    ripgrep:rg
    fd:fd
    gnupg:gpg
    docker:docker
    docker-compose:docker-compose
    colima:colima
    emacs:emacs
  )

  for overlap in "${overlaps[@]}"; do
    formula="${overlap%%:*}"
    command_name="${overlap#*:}"
    if ! brew list --formula "$formula" >/dev/null 2>&1; then
      continue
    fi
    command_path="$(command -v "$command_name" 2>/dev/null || true)"
    case "$command_path" in
      "$MACPORTS_PREFIX"/bin/*|"$MACPORTS_PREFIX"/sbin/*)
        log "Removing Homebrew $formula; $command_name resolves to $command_path"
        run_cmd brew uninstall "$formula"
        remember_installed "removed Homebrew $formula"
        ;;
      *)
        warn "Keeping Homebrew $formula; $command_name does not resolve to MacPorts ($command_path)"
        remember_skipped "Homebrew $formula cleanup"
        ;;
    esac
  done
}

normalize_zsh_mode() {
  local mode_lower
  mode_lower=$(echo "$ZSH_MODE" | tr '[:upper:]' '[:lower:]')
  case "$mode_lower" in
    plain|ohmyzsh) ZSH_MODE="$mode_lower" ;;
    *)
      warn "Unknown ZSH_MODE '$ZSH_MODE'; defaulting to plain"
      ZSH_MODE="plain"
      ;;
  esac
}

sdk_cmd() {
  local shell_cmd="zsh"
  if ! have zsh; then
    shell_cmd="bash"
  fi

  "$shell_cmd" -lc '
    if ! source "$HOME/.sdkman/bin/sdkman-init.sh" >/dev/null 2>&1; then
      echo "sdk_cmd: failed to source $HOME/.sdkman/bin/sdkman-init.sh" >&2
      exit 1
    fi
    sdk "$@"
  ' "$shell_cmd" "$@"
}

sdk_candidate_listed() {
  local candidate="$1"
  local candidates
  candidates="$(sdk_cmd list java 2>/dev/null)" || return 1
  [[ "$candidates" == *"$candidate"* ]]
}

sdk_candidate_installed() {
  local candidate="$1"
  sdk_cmd home java "$candidate" >/dev/null 2>&1
}

sdk_candidate_current() {
  local candidate="$1"
  local current
  current="$(sdk_cmd current java 2>/dev/null)" || return 1
  [[ "$current" == *"$candidate"* ]]
}

show_help() {
    cat <<EOF

⛳️ teeup.sh - Get your new machine ready for the first drive. ⛳️

Usage:
  ./teeup.sh [OPTIONS]

Options:
  --help                Show this help message
  --dry-run             Preview commands without executing them
  --only MODULES        Run only specified modules (comma-separated)
                        Available: homebrew,shell,zsh,ohmyzsh,bash,cli,python,java,ruby,rust,emacs,docker,apps
                        homebrew aliases package-manager setup; shell configures the
                        login shell (zsh→Powerlevel10k, bash→Starship), zsh/bash force one.
  --migrate-to-uv       Migrate from pyenv/poetry/pipx to UV
  --strict-platform     Fail if a selected module is unsupported on this OS
  --reconcile-existing-config
                        Disable old Antigen, pyenv, and stale shell config safely
  --no-reconcile-existing-config
                        Skip existing shell config reconciliation
  --list-modules        List available modules

Environment Variables:
  PYTHON_VERSION        Python version to install (default: 3.12.5)
  JDK_VERSION           Java version for SDKMAN (default: 21.0.4-tem)
  RUBY_VERSION          Ruby version to install with rbenv (default: 3.4.9)
  BUNDLER_VERSION       Optional Bundler version to install (default: latest)
  USE_UV                Use UV instead of pyenv (default: true)
  RUBYGEMS_UPDATE       Update RubyGems after Ruby install (default: true)
  ZSH_MODE              zsh integration mode: plain or ohmyzsh (default: plain)
  TARGET_SHELL          Login shell to configure: auto, bash, or zsh (default: auto)
  PACKAGE_MANAGER       auto, homebrew, macports, apt, or dnf (default: auto)
  STRICT_PLATFORM       Fail on unsupported module/platform combos (default: false)
  INSTALL_DOTFILES      Install/symlink dotfiles from DOTFILES_DIR (default: true)
  DOTFILES_DIR          Dotfiles payload path (default: ../dotfiles when present)
  ALLOW_HOMEBREW_CASK_FALLBACK
                        Use existing Homebrew for GUI casks in MacPorts mode (default: false)
  CLEANUP_HOMEBREW_OVERLAPS
                        Remove verified Homebrew overlaps after MacPorts install (default: false)
  UPGRADE_HOMEBREW      Upgrade all Homebrew packages (default: false)
  RECONCILE_EXISTING_CONFIG
                        Disable old Antigen/pyenv/stale shell config (default: false)
  TUNE_DEFAULTS         Apply macOS defaults (default: false)
  DRY_RUN               Preview mode, no actual changes (default: false)

Examples:
  # Full setup
  ./teeup.sh

  # Preview what would be installed (dry-run)
  ./teeup.sh --dry-run

  # Only install Python environment
  ./teeup.sh --only python

  # Install minimal zsh setup with Powerlevel10k (default)
  ./teeup.sh --only zsh

  # Install Oh My Zsh mode instead
  ZSH_MODE=ohmyzsh ./teeup.sh --only zsh

  # Preview Python installation
  ./teeup.sh --dry-run --only python

  # Migrate from pyenv to UV
  ./teeup.sh --migrate-to-uv

  # Use pyenv instead of UV
  USE_UV=false ./teeup.sh --only python

  # Install only Ruby
  ./teeup.sh --only ruby
EOF
  exit 0
}

list_modules() {
  cat <<EOF
Available modules:
  homebrew  - Package manager setup (compatibility module name; resolves by OS)
  shell     - Configure your login shell (zsh: Powerlevel10k + plugins; bash: bash-completion + Starship)
  zsh       - Force zsh setup (Powerlevel10k + plugins)
  ohmyzsh   - Legacy alias for zsh with ZSH_MODE=ohmyzsh
  bash      - Force bash setup (bash-completion + Starship)
  cli       - Core CLI utilities (git, jq, ripgrep, etc.)
  python    - Python environment (UV or pyenv/poetry)
  java      - SDKMAN! + Java + Maven/Gradle
  ruby      - Ruby via rbenv + RubyGems + Bundler
  rust      - Rust toolchain via rustup
  emacs     - Emacs editor + minimal config
  docker    - Docker runtime + CLI (Colima on macOS, distro packages on Linux)
  apps      - GUI apps (Bruno, Obsidian; macOS-only currently)
EOF
  exit 0
}

parse_only_modules() {
  local modules="$1"
  # Disable all modules first
  RUN_HOMEBREW=false
  RUN_ZSH=false
  RUN_CLI=false
  RUN_PYTHON=false
  RUN_JAVA=false
  RUN_RUBY=false
  RUN_RUST=false
  RUN_EMACS=false
  RUN_DOCKER=false
  RUN_APPS=false

  # Enable only specified modules
  IFS=',' read -ra MODS <<< "$modules"
  for mod in "${MODS[@]}"; do
    # Convert to lowercase (Bash 3.2 compatible)
    mod_lower=$(echo "$mod" | tr '[:upper:]' '[:lower:]')
    case "$mod_lower" in  # lowercase
      homebrew) RUN_HOMEBREW=true ;;
      shell)    RUN_ZSH=true ;;
      zsh)      RUN_ZSH=true; TARGET_SHELL="zsh" ;;
      ohmyzsh)  RUN_ZSH=true; ZSH_MODE="ohmyzsh"; TARGET_SHELL="zsh" ;;
      bash)     RUN_ZSH=true; TARGET_SHELL="bash" ;;
      cli)      RUN_CLI=true ;;
      python)   RUN_PYTHON=true ;;
      java)     RUN_JAVA=true ;;
      ruby)     RUN_RUBY=true ;;
      rust)     RUN_RUST=true ;;
      emacs)    RUN_EMACS=true ;;
      docker)   RUN_DOCKER=true ;;
      apps)     RUN_APPS=true ;;
      *) warn "Unknown module: $mod" ;;
    esac
  done

  # Package manager setup is needed by package-backed modules. Python only needs
  # it when explicitly using the legacy pyenv path instead of uv.
  if [[ "$RUN_ZSH" == "true" || "$RUN_CLI" == "true" || "$RUN_RUBY" == "true" || "$RUN_EMACS" == "true" || "$RUN_DOCKER" == "true" || "$RUN_APPS" == "true" ]]; then
    RUN_HOMEBREW=true
  elif [[ "$RUN_PYTHON" == "true" && "$USE_UV" != "true" ]]; then
    RUN_HOMEBREW=true
  fi
}

migrate_pyenv_to_uv() {
  log "Starting migration from pyenv to UV..."
  echo ""

  # Check if pyenv is installed
  if ! have pyenv && [[ ! -d "$HOME/.pyenv" ]]; then
    warn "pyenv not found. Nothing to migrate."
    exit 0
  fi

  # List current pyenv versions
  echo "📋 Current pyenv Python versions:"
  if have pyenv; then
    pyenv versions 2>/dev/null || echo "  (none)"
  fi
  echo ""

  # List pipx tools
  echo "📋 Current pipx tools:"
  if have pipx; then
    pipx list 2>/dev/null | grep "package " || echo "  (none)"
  fi
  echo ""

  # Install UV if not present
  if ! have uv; then
    log "Installing UV..."
    if [[ "$DRY_RUN" == "true" ]]; then
      run_cmd sh -c "curl -LsSf https://astral.sh/uv/install.sh | sh"
    else
      curl -LsSf https://astral.sh/uv/install.sh | sh
    fi
    export PATH="$HOME/.local/bin:$PATH"
    require_command_available uv "UV install"
    ok "UV installed"
  else
    ok "UV already installed"
  fi

  # Install Python version via UV
  log "Installing Python $PYTHON_VERSION via UV..."
  run_cmd uv python install "$PYTHON_VERSION"
  ok "Python $PYTHON_VERSION installed via UV"

  # Migrate pipx tools to uv tool
  if have pipx; then
    log "Migrating pipx tools to UV..."
    while IFS= read -r tool; do
      [[ -z "$tool" ]] && continue
      log "Installing $tool via uv tool..."
      if [[ "$DRY_RUN" == "true" ]]; then
        run_cmd uv tool install "$tool"
      else
        uv tool install "$tool" 2>/dev/null || warn "Failed to install $tool"
      fi
    done < <(pipx list 2>/dev/null | awk '/^[[:space:]]*package / {print $2}')
    ok "Tools migrated to UV"
  fi

  # Update .zshrc
  if [[ -f "$ZSHRC" ]]; then
    log "Updating .zshrc..."

    # Comment out pyenv init lines
    if grep -q "pyenv init" "$ZSHRC"; then
      disable_matching_lines "$ZSHRC" 'pyenv (init|virtualenv-init)|PYENV_ROOT|\.pyenv' "uv migration"
      ok "Commented out pyenv init in .zshrc"
    fi

    # Add uv path if not present
    if ! dotfiles_payload_available; then
      append_once "$TEEUPSHRC" "Added by teeup.sh - uv path" <<'EOF'
# uv (Python package manager)
export PATH="$HOME/.local/bin:$PATH"
EOF
    else
      log "uv PATH is handled by dotfiles."
    fi
  fi

  echo ""
  ok "Migration complete!"
  echo ""
  echo "📝 Next steps:"
  echo "   1. Open a new terminal (or re-exec your shell) to reload"
  echo "   2. Verify: uv --version && uv python list --only-installed"
  echo "   3. Optional cleanup (after verifying everything works):"
  echo "      - Remove pyenv: rm -rf ~/.pyenv"
  echo "      - Remove pipx: pipx uninstall-all && brew uninstall pipx"
  echo "      - Remove pyenv brew packages: brew uninstall pyenv pyenv-virtualenv"
  echo "      - Clean up .zshrc: Remove commented pyenv lines"
  echo ""
  warn "Keep pyenv installed until you've verified UV works for all your projects!"

  exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      show_help
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --only)
      if [[ -z "${2:-}" ]]; then
        err "--only requires a comma-separated list of modules"
        exit 1
      fi
      parse_only_modules "$2"
      shift 2
      ;;
    --migrate-to-uv)
      migrate_pyenv_to_uv
      ;;
    --strict-platform)
      STRICT_PLATFORM=true
      shift
      ;;
    --reconcile-existing-config)
      RECONCILE_EXISTING_CONFIG=true
      shift
      ;;
    --no-reconcile-existing-config)
      RECONCILE_EXISTING_CONFIG=false
      shift
      ;;
    --list-modules)
      list_modules
      ;;
    *)
      warn "Unknown option: $1"
      show_help
      ;;
  esac
done

# Show dry-run banner if enabled
if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                    🔍 DRY-RUN MODE 🔍                        ║"
  echo "║                                                              ║"
  echo "║  No changes will be made to your system.                    ║"
  echo "║  Commands will be displayed for preview only.               ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
fi

normalize_zsh_mode
normalize_strict_platform

ZSHRC="${ZSHRC:-$HOME/.zshrc}"

SUMMARY_INSTALLED=()
SUMMARY_SKIPPED=()

remember_installed() { SUMMARY_INSTALLED+=("$1"); }
remember_skipped()   { SUMMARY_SKIPPED+=("$1"); }

########################################
# ===== Detect architecture/OS ======  #
########################################
detect_platform
ok "Detected ${PLATFORM_LABEL} on ${ARCH}"

MACPORTS_PREFIX="${MACPORTS_PREFIX:-/opt/local}"
BREW_PREFIX="${BREW_PREFIX:-$(default_brew_prefix)}"
resolve_package_manager
validate_package_manager_for_platform
apply_package_manager_path
ok "Package manager mode: PACKAGE_MANAGER=$PACKAGE_MANAGER -> $(package_manager_label) on ${PLATFORM_LABEL}"

detect_target_shell
ok "Target login shell: $TARGET_SHELL"

########################################
# ===== Xcode CLT & Rosetta (ARM) ==== #
########################################
if is_macos; then
  if ! xcode-select -p >/dev/null 2>&1; then
    log "Installing Xcode Command Line Tools…"
    run_cmd xcode-select --install || true
    warn "If a dialog appeared, complete it and re-run the script if needed."
  else
    ok "Xcode Command Line Tools present."
  fi

  if [[ "$ARCH" == "arm64" ]]; then
    if ! pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
      log "Installing Rosetta 2 (Apple Silicon)…"
      run_cmd /usr/sbin/softwareupdate --install-rosetta --agree-to-license || warn "Rosetta install may require approval."
    else
      ok "Rosetta 2 already installed."
    fi
  fi
fi

#################################
# ===== Package manager setup ==#
#################################
if [[ "$RUN_HOMEBREW" == "true" ]]; then
  log "Preparing $(package_manager_label)…"
  prepare_package_manager

  case "$RESOLVED_PACKAGE_MANAGER" in
    homebrew)
      apply_package_manager_path
      require_command_available brew "Homebrew install"
      if [[ "$INSTALL_DOTFILES" == "true" ]] && dotfiles_payload_available; then
        log "Homebrew path is handled by dotfiles zprofile."
      else
        append_once "$ZPROFILE" "Added by teeup.sh - Homebrew path" <<EOF
# Homebrew (added by teeup.sh)
if [ -d "$BREW_PREFIX/bin" ]; then
  export PATH="$BREW_PREFIX/bin:\$PATH"
fi
EOF
      fi
      ;;
    macports)
      apply_package_manager_path
      if [[ "$INSTALL_DOTFILES" == "true" ]] && dotfiles_payload_available; then
        log "MacPorts path is handled by dotfiles zprofile."
      else
        append_once "$ZPROFILE" "Added by teeup.sh - MacPorts path" <<EOF
# MacPorts (added by teeup.sh)
if [ -d "$MACPORTS_PREFIX/bin" ]; then
  export PATH="$MACPORTS_PREFIX/bin:$MACPORTS_PREFIX/sbin:\$PATH"
fi
EOF
      fi
      ;;
  esac
else
  log "Skipping package manager setup (RUN_HOMEBREW=false)"
fi

###################################
# ===== Shell + Prompt/Plugins == #
###################################
if [[ "$RUN_ZSH" == "true" ]]; then
  if [[ "$TARGET_SHELL" == "zsh" ]]; then
  log "Configuring zsh mode: $ZSH_MODE"

  if [[ "$ZSH_MODE" == "plain" ]]; then
    if [[ "$RESOLVED_PACKAGE_MANAGER" == "macports" ]] || is_linux; then
      ZSH_PACKAGES=(zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting)
    else
      ZSH_PACKAGES=(zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting powerlevel10k)
    fi
    for f in "${ZSH_PACKAGES[@]}"; do
      pkg_install "$f"
    done
    if [[ "$RESOLVED_PACKAGE_MANAGER" == "macports" ]] || is_linux; then
      P10K_DIR="${HOME}/.local/share/powerlevel10k"
      if [[ ! -d "$P10K_DIR" ]]; then
        log "Installing Powerlevel10k theme from upstream git…"
        run_cmd mkdir -p "$(dirname "$P10K_DIR")"
        run_cmd git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
        remember_installed "powerlevel10k (git)"
      else
        remember_skipped "powerlevel10k (git)"
        log "Powerlevel10k already installed at $P10K_DIR"
      fi
    fi

    write_managed_file "$ZSH_INTEGRATION" "plain zsh integration" <<'EOF'
# Generated by teeup.sh. Personal shell config belongs in ~/.zshrc.
if [ -d /opt/local/share/zsh/site-functions ]; then
  FPATH="/opt/local/share/zsh/site-functions:$FPATH"
fi
if [ -d /opt/local/share/zsh-completions ]; then
  FPATH="/opt/local/share/zsh-completions:$FPATH"
fi
if [ -d /usr/share/zsh/site-functions ]; then
  FPATH="/usr/share/zsh/site-functions:$FPATH"
fi
if [ -d /usr/share/zsh/vendor-completions ]; then
  FPATH="/usr/share/zsh/vendor-completions:$FPATH"
fi

BREW_PREFIX=""
if command -v brew >/dev/null 2>&1; then
  BREW_PREFIX="$(brew --prefix)"

  if [ -d "$BREW_PREFIX/share/zsh/site-functions" ]; then
    FPATH="$BREW_PREFIX/share/zsh/site-functions:$FPATH"
  fi
  if [ -d "$BREW_PREFIX/share/zsh-completions" ]; then
    FPATH="$BREW_PREFIX/share/zsh-completions:$FPATH"
  fi
fi

autoload -Uz compinit
compinit -i

for theme_file in \
  /opt/local/share/powerlevel10k/powerlevel10k.zsh-theme \
  "$HOME/.local/share/powerlevel10k/powerlevel10k.zsh-theme" \
  "$BREW_PREFIX/share/powerlevel10k/powerlevel10k.zsh-theme"; do
  if [ -r "$theme_file" ]; then
    source "$theme_file"
    break
  fi
done

for plugin_file in \
  /opt/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh \
  "$BREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"; do
  if [ -r "$plugin_file" ]; then
    source "$plugin_file"
    break
  fi
done

for plugin_file in \
  /opt/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  "$BREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"; do
  if [ -r "$plugin_file" ]; then
    source "$plugin_file"
    break
  fi
done

[ -r "$HOME/.p10k.zsh" ] && source "$HOME/.p10k.zsh"
EOF
  else
    OMZ_DIR="${HOME}/.oh-my-zsh"
    if [[ ! -d "$OMZ_DIR" ]]; then
      log "Installing Oh My Zsh…"
      if [[ "$DRY_RUN" == "true" ]]; then
        run_cmd sh -c "curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | RUNZSH=no KEEP_ZSHRC=yes sh"
      else
        RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
      fi
      require_path_available "$OMZ_DIR/oh-my-zsh.sh" "Oh My Zsh install"
      remember_installed "oh-my-zsh"
    else
      require_path_available "$OMZ_DIR/oh-my-zsh.sh" "Oh My Zsh"
      remember_skipped "oh-my-zsh"
      log "Oh My Zsh already installed."
    fi

    ZSH_AUTOSUGGESTIONS_DIR="${ZSH_CUSTOM:-$OMZ_DIR/custom}/plugins/zsh-autosuggestions"
    if [[ ! -d "$ZSH_AUTOSUGGESTIONS_DIR" ]]; then
      log "Installing zsh-autosuggestions plugin…"
      run_cmd git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_AUTOSUGGESTIONS_DIR"
      remember_installed "zsh-autosuggestions"
    else
      remember_skipped "zsh-autosuggestions"
    fi

    ZSH_SYNTAX_HIGHLIGHTING_DIR="${ZSH_CUSTOM:-$OMZ_DIR/custom}/plugins/zsh-syntax-highlighting"
    if [[ ! -d "$ZSH_SYNTAX_HIGHLIGHTING_DIR" ]]; then
      log "Installing zsh-syntax-highlighting plugin…"
      run_cmd git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_SYNTAX_HIGHLIGHTING_DIR"
      remember_installed "zsh-syntax-highlighting"
    else
      remember_skipped "zsh-syntax-highlighting"
    fi

    P10K_DIR="${ZSH_CUSTOM:-$OMZ_DIR/custom}/themes/powerlevel10k"
    if [[ ! -d "$P10K_DIR" ]]; then
      log "Installing Powerlevel10k theme…"
      run_cmd git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
      remember_installed "powerlevel10k"
    else
      remember_skipped "powerlevel10k"
    fi

    write_managed_file "$ZSH_INTEGRATION" "Oh My Zsh integration" <<'EOF'
# Generated by teeup.sh. Personal shell config belongs in ~/.zshrc.
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git docker command-not-found zsh-autosuggestions zsh-syntax-highlighting)

if [ -r "$ZSH/oh-my-zsh.sh" ]; then
  source "$ZSH/oh-my-zsh.sh"
fi

[ -r "$HOME/.p10k.zsh" ] && source "$HOME/.p10k.zsh"
EOF
  fi
  else
    log "Configuring bash shell (bash-completion + Starship)"
    pkg_install bash-completion

    if ! have starship; then
      log "Installing Starship prompt…"
      if [[ "$DRY_RUN" == "true" ]]; then
        run_cmd sh -c "curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir \"$HOME/.local/bin\""
      else
        curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$HOME/.local/bin"
      fi
      export PATH="$HOME/.local/bin:$PATH"
      remember_installed "starship"
    else
      remember_skipped "starship"
      ok "Starship already installed."
    fi

    if [[ "$INSTALL_DOTFILES" == "true" ]] && dotfiles_payload_available; then
      log "bash shell integration is handled by dotfiles."
    elif [[ "$INSTALL_DOTFILES" == "true" ]]; then
      append_once "$TEEUPSHRC" "Added by teeup.sh - bash-completion" <<'EOF'
# bash-completion (bash only)
if [ -n "${BASH_VERSION:-}" ]; then
  if [ -r /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -r /etc/bash_completion ]; then
    . /etc/bash_completion
  elif [ -n "${HOMEBREW_PREFIX:-}" ] && [ -r "$HOMEBREW_PREFIX/etc/profile.d/bash_completion.sh" ]; then
    . "$HOMEBREW_PREFIX/etc/profile.d/bash_completion.sh"
  fi
fi
EOF
      append_once "$TEEUPSHRC" "Added by teeup.sh - starship" <<'EOF'
# Starship prompt (bash only; zsh uses Powerlevel10k)
if [ -n "${BASH_VERSION:-}" ] && command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi
EOF
    fi
  fi
else
  log "Skipping shell setup (RUN_ZSH=false)"
fi



###################################
# ===== Core CLI utilities ====== #
###################################
if [[ "$RUN_CLI" == "true" ]]; then
  if [[ "$RESOLVED_PACKAGE_MANAGER" == "macports" ]]; then
    CLI_PACKAGES=(git wget curl jq htop tree tmux ripgrep fd gnupg2)
  else
    CLI_PACKAGES=(git wget curl jq htop tree tmux ripgrep fd gnupg)
  fi

  log "Installing core CLI utilities…"
  for f in "${CLI_PACKAGES[@]}"; do
    cmd_name="$(package_command "$f")"
    pkg_install "$f" "$cmd_name"
  done
else
  log "Skipping CLI utilities setup (RUN_CLI=false)"
fi

###################################
# ===== Python Environment ====== #
###################################
if [[ "$RUN_PYTHON" == "true" ]]; then

if [[ "$USE_UV" == "true" ]]; then
  #################################
  # ===== UV (Modern Python) ==== #
  #################################
  log "Using UV for Python management (recommended)"

  if ! have uv; then
    log "Installing UV…"
    if [[ "$DRY_RUN" == "true" ]]; then
      run_cmd sh -c "curl -LsSf https://astral.sh/uv/install.sh | sh"
    else
      curl -LsSf https://astral.sh/uv/install.sh | sh
    fi
    remember_installed "uv"
    # Add uv to current PATH
    export PATH="$HOME/.local/bin:$PATH"
    require_command_available uv "UV install"
  else
    remember_skipped "uv"
    ok "UV already installed."
  fi

  # Ensure uv is in PATH for future shells
  if [[ "$INSTALL_DOTFILES" == "true" ]] && dotfiles_payload_available; then
    log "uv PATH is handled by dotfiles."
  elif [[ "$INSTALL_DOTFILES" == "true" ]]; then
    append_once "$TEEUPSHRC" "Added by teeup.sh - uv path" <<'EOF'
# uv (Python package manager)
export PATH="$HOME/.local/bin:$PATH"
EOF
  fi

  # Install Python version via uv
  log "Ensuring Python $PYTHON_VERSION via uv…"
  if uv python list --only-installed 2>/dev/null | grep -q "$PYTHON_VERSION"; then
    remember_skipped "python@$PYTHON_VERSION (uv)"
    log "Python $PYTHON_VERSION already installed with uv."
  else
    run_cmd uv python install "$PYTHON_VERSION"
    remember_installed "python@$PYTHON_VERSION (uv)"
  fi

  # Pin Python version globally
  if [[ "$DRY_RUN" == "true" ]]; then
    run_cmd sh -c "cd \"\$HOME\" && uv python pin \"$PYTHON_VERSION\""
  else
    if ! (cd "$HOME" && uv python pin "$PYTHON_VERSION"); then
      warn "uv python pin $PYTHON_VERSION failed; you may need to run it manually"
    fi
  fi

  # Install Python dev tools via uv tool
  if [[ "$INSTALL_PY_TOOLS" == "true" ]]; then
    UV_TOOLS=(ruff black httpie)
    for t in "${UV_TOOLS[@]}"; do
      if uv tool list 2>/dev/null | grep -q "^$t "; then
        remember_skipped "uv:$t"
        log "uv tool already installed: $t"
      else
        run_cmd uv tool install "$t" || warn "Failed to install uv tool: $t"
        remember_installed "uv:$t"
      fi
    done
  fi

else
  #################################
  # ===== pyenv + Python setup == #
  #################################
  log "Using pyenv/poetry for Python management (legacy)"

  pkg_install pyenv pyenv
  pkg_install pyenv-virtualenv

  if [[ "$INSTALL_DOTFILES" == "true" ]] && dotfiles_payload_available; then
    log "pyenv init is handled conditionally by dotfiles."
  elif [[ "$INSTALL_DOTFILES" == "true" ]]; then
    append_once "$TEEUPSHRC" "Added by teeup.sh - pyenv init" <<'EOF'
# pyenv init
if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init -)"
  eval "$(pyenv virtualenv-init -)"
fi
EOF
  fi

  if [[ "$DRY_RUN" != "true" ]] && ! have pyenv; then
    if [[ "$STRICT_PLATFORM" == "true" ]]; then
      err "Legacy Python mode requested, but pyenv is unavailable after package installation."
      exit 1
    fi
    warn "pyenv is unavailable; skipping legacy Python setup."
    remember_skipped "python@$PYTHON_VERSION (pyenv unavailable)"
  else
    # Ensure shims for current session.
    if have pyenv; then
      eval "$(pyenv init -)"
      eval "$(pyenv virtualenv-init -)"
    fi

    log "Ensuring Python $PYTHON_VERSION via pyenv…"
    if [[ "$DRY_RUN" != "true" ]] && pyenv versions --bare | grep -qx "$PYTHON_VERSION"; then
      remember_skipped "python@$PYTHON_VERSION (pyenv)"
      log "Python $PYTHON_VERSION already installed with pyenv."
    else
      # Build deps help (esp. for older Pythons)
      if [[ "$RESOLVED_PACKAGE_MANAGER" == "homebrew" ]]; then
        run_cmd brew install openssl readline sqlite xz tcl-tk zlib bzip2 \
          || warn "Failed to install Python build deps via Homebrew; pyenv install may fail"
      elif [[ "$RESOLVED_PACKAGE_MANAGER" == "apt" ]]; then
        PYENV_BUILD_DEPS=(build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev xz-utils tk-dev libffi-dev liblzma-dev)
        for dep in "${PYENV_BUILD_DEPS[@]}"; do
          pkg_install "$dep"
        done
      elif [[ "$RESOLVED_PACKAGE_MANAGER" == "dnf" ]]; then
        PYENV_BUILD_DEPS=(gcc make openssl-devel bzip2 bzip2-devel readline-devel sqlite sqlite-devel xz xz-devel tk-devel libffi-devel zlib-devel)
        for dep in "${PYENV_BUILD_DEPS[@]}"; do
          pkg_install "$dep"
        done
      fi
      if [[ "$DRY_RUN" == "true" ]]; then
        run_cmd pyenv install "$PYTHON_VERSION"
      else
        if [[ "$RESOLVED_PACKAGE_MANAGER" == "homebrew" ]]; then
          CFLAGS="-I$BREW_PREFIX/opt/zlib/include -I$BREW_PREFIX/opt/bzip2/include" \
          LDFLAGS="-L$BREW_PREFIX/opt/zlib/lib -L$BREW_PREFIX/opt/bzip2/lib" \
          PYTHON_CONFIGURE_OPTS="--enable-framework" \
          pyenv install "$PYTHON_VERSION"
        else
          pyenv install "$PYTHON_VERSION"
        fi
      fi
      remember_installed "python@$PYTHON_VERSION (pyenv)"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
      run_cmd pyenv global "$PYTHON_VERSION"
    else
      pyenv global "$PYTHON_VERSION" || warn "Could not set global Python to $PYTHON_VERSION."
    fi
  fi

  # pipx + Python dev tools
  pkg_install pipx pipx
  if have pipx || [[ "$DRY_RUN" == "true" ]]; then
    run_cmd pipx ensurepath || warn "pipx ensurepath failed; pipx tools may not be on PATH"
  else
    warn "pipx is unavailable; skipping pipx tool setup."
    remember_skipped "pipx (unavailable)"
  fi

  if [[ "$INSTALL_PY_TOOLS" == "true" ]] && (have pipx || [[ "$DRY_RUN" == "true" ]]); then
    PY_TOOLS=(poetry black ruff httpie)
    for t in "${PY_TOOLS[@]}"; do
      if pipx list | grep -E "package $t " >/dev/null 2>&1; then
        remember_skipped "pipx:$t"
        log "pipx tool already installed: $t"
      else
        run_cmd pipx install "$t" || warn "Failed to install pipx tool: $t"
        remember_installed "pipx:$t"
      fi
    done
  elif [[ "$INSTALL_PY_TOOLS" == "true" ]]; then
    remember_skipped "pipx tools (pipx unavailable)"
  fi
fi

else
  log "Skipping Python setup (RUN_PYTHON=false)"
fi

###################################
# ===== SDKMAN! + Java setup ==== #
###################################
if [[ "$RUN_JAVA" == "true" ]]; then
  SDKMAN_DIR="${HOME}/.sdkman"
  if [[ ! -d "$SDKMAN_DIR" ]]; then
    log "Installing SDKMAN!…"
    if [[ "$DRY_RUN" == "true" ]]; then
      run_cmd bash -c "curl -fsSL https://get.sdkman.io | bash"
    else
      curl -fsSL "https://get.sdkman.io" | bash
    fi
    remember_installed "SDKMAN!"
  else
    remember_skipped "SDKMAN!"
  fi

  if [[ -s "${SDKMAN_DIR}/bin/sdkman-init.sh" ]]; then
    log "Using SDKMAN through zsh."
  elif [[ "$DRY_RUN" == "true" ]]; then
    warn "SDKMAN init script is not present; dry-run will preview SDKMAN commands."
  else
    err "SDKMAN init script not found at ${SDKMAN_DIR}/bin/sdkman-init.sh."
    err "Reopen your terminal or rerun SDKMAN install, then rerun setup."
    exit 1
  fi

  # Java via SDKMAN
  echo "Installing Java candidate"
  JAVA_CANDIDATE="${JDK_VERSION}"
  JAVA_INSTALLED_THIS_RUN=false
  if [[ "$DRY_RUN" == "true" ]]; then
    run_cmd sdk install java "$JAVA_CANDIDATE"
    run_cmd sdk default java "$JAVA_CANDIDATE"
    remember_installed "java@$JAVA_CANDIDATE (SDKMAN)"
  elif ! sdk_candidate_listed "$JAVA_CANDIDATE"; then
    warn "Requested Java candidate $JAVA_CANDIDATE not listed by SDKMAN. Skipping."
  else
    if ! sdk_candidate_installed "$JAVA_CANDIDATE"; then
      log "Installing Java $JAVA_CANDIDATE via SDKMAN!…"
      if sdk_cmd install java "$JAVA_CANDIDATE"; then
        JAVA_INSTALLED_THIS_RUN=true
      else
        warn "Failed to install Java $JAVA_CANDIDATE"
      fi
    fi

    if sdk_candidate_installed "$JAVA_CANDIDATE"; then
      if sdk_candidate_current "$JAVA_CANDIDATE"; then
        if [[ "$JAVA_INSTALLED_THIS_RUN" == "true" ]]; then
          remember_installed "java@$JAVA_CANDIDATE (SDKMAN)"
        else
          remember_skipped "java@$JAVA_CANDIDATE (SDKMAN)"
        fi
        log "Java $JAVA_CANDIDATE already current."
      else
        log "Setting Java $JAVA_CANDIDATE as SDKMAN default…"
        sdk_cmd default java "$JAVA_CANDIDATE" || warn "Failed to set Java $JAVA_CANDIDATE as default"
        remember_installed "java@$JAVA_CANDIDATE (SDKMAN)"
      fi
    else
      warn "Java $JAVA_CANDIDATE is not installed; default was not changed."
    fi
  fi

  # Maven/Gradle via SDKMAN (optional but useful)
  for tool in maven gradle; do
    if [[ "$DRY_RUN" == "true" ]]; then
      run_cmd sdk install "$tool"
      remember_installed "$tool (SDKMAN)"
    elif sdk_cmd list "$tool" >/dev/null 2>&1; then
      if ! sdk_cmd current "$tool" >/dev/null 2>&1; then
        log "Installing $tool via SDKMAN!…"
        sdk_cmd install "$tool" || warn "Failed to install $tool"
        remember_installed "$tool (SDKMAN)"
      else
        remember_skipped "$tool (SDKMAN)"
        log "$tool already installed via SDKMAN."
      fi
    fi
  done
else
  log "Skipping Java setup (RUN_JAVA=false)"
fi

###################################
# ===== Ruby via rbenv ========== #
###################################
if [[ "$RUN_RUBY" == "true" ]]; then
  log "Installing Ruby via rbenv..."

  pkg_install rbenv rbenv
  pkg_install ruby-build ruby-build

  if [[ "$DRY_RUN" != "true" ]] && ! have rbenv; then
    if [[ "$STRICT_PLATFORM" == "true" ]]; then
      err "Ruby module requested, but rbenv is unavailable after package installation."
      exit 1
    fi
    warn "rbenv is unavailable; skipping Ruby setup."
    remember_skipped "ruby@$RUBY_VERSION (rbenv unavailable)"
  else
    RBENV_ROOT="${RBENV_ROOT:-$HOME/.rbenv}"
    prepend_path_once "$RBENV_ROOT/bin"
    if have rbenv; then
      if [[ "$DRY_RUN" == "true" ]]; then
        run_cmd sh -c "eval \"\$(rbenv init - bash)\""
      else
        RBENV_INIT_SCRIPT="$(rbenv init - bash)" || RBENV_INIT_SCRIPT=""
        if [[ -n "$RBENV_INIT_SCRIPT" ]]; then
          eval "$RBENV_INIT_SCRIPT"
        else
          warn "Could not initialize rbenv for the current shell."
        fi
      fi
    fi

    if [[ "$INSTALL_DOTFILES" == "true" ]] && dotfiles_payload_available; then
      log "rbenv init is handled conditionally by dotfiles."
    elif [[ "$INSTALL_DOTFILES" == "true" ]]; then
      append_once "$TEEUPSHRC" "Added by teeup.sh - rbenv init" <<'EOF'
# rbenv init
if command -v rbenv >/dev/null 2>&1; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(rbenv init - zsh)"
  else
    eval "$(rbenv init - bash)"
  fi
fi
EOF
    fi

    log "Ensuring Ruby $RUBY_VERSION via rbenv..."
    ruby_ready=false
    if [[ "$DRY_RUN" == "true" ]]; then
      ensure_ruby_build_definition "$RUBY_VERSION"
      run_cmd rbenv install -s "$RUBY_VERSION"
      remember_installed "ruby@$RUBY_VERSION (rbenv)"
      ruby_ready=true
    elif rbenv versions --bare | grep -qx "$RUBY_VERSION"; then
      remember_skipped "ruby@$RUBY_VERSION (rbenv)"
      log "Ruby $RUBY_VERSION already installed with rbenv."
      ruby_ready=true
    elif ensure_ruby_build_definition "$RUBY_VERSION" && run_cmd rbenv install "$RUBY_VERSION"; then
      remember_installed "ruby@$RUBY_VERSION (rbenv)"
      ruby_ready=true
    else
      if [[ "$STRICT_PLATFORM" == "true" ]]; then
        err "Failed to install Ruby $RUBY_VERSION via rbenv."
        exit 1
      fi
      warn "Skipping Ruby $RUBY_VERSION (rbenv install failed); continuing setup."
      remember_skipped "ruby@$RUBY_VERSION (install failed)"
    fi

    # Only configure gems/bundler against a Ruby that actually installed.
    if [[ "$ruby_ready" == "true" ]]; then
      run_cmd rbenv global "$RUBY_VERSION"

      if [[ "$RUBYGEMS_UPDATE" == "true" ]]; then
        run_cmd gem update --system
        remember_installed "rubygems update"
      else
        remember_skipped "rubygems update"
        log "Skipping RubyGems update (RUBYGEMS_UPDATE=false)."
      fi

      if [[ -n "$BUNDLER_VERSION" ]]; then
        run_cmd gem install bundler -v "$BUNDLER_VERSION"
        remember_installed "bundler@$BUNDLER_VERSION"
      else
        run_cmd gem install bundler
        remember_installed "bundler"
      fi

      run_cmd rbenv rehash
    fi
  fi
else
  log "Skipping Ruby setup (RUN_RUBY=false)"
fi

###################################
# ===== Rust via rustup ========= #
###################################

if [[ "$RUN_RUST" == "true" ]]; then
  if ! have rustup; then
    log "Installing Rust via rustup…"
    rustup_init="$(mktemp -t teeup-rustup-init.XXXXXX)"
    if [[ "$DRY_RUN" == "true" ]]; then
      run_cmd curl -fsSL https://sh.rustup.rs -o "$rustup_init"
      run_cmd sh "$rustup_init" -y --no-modify-path
      run_cmd rm -f "$rustup_init"
    else
      if ! curl -fsSL https://sh.rustup.rs -o "$rustup_init"; then
        rm -f "$rustup_init"
        err "Failed to download rustup installer"
        exit 1
      fi
      sh "$rustup_init" -y --no-modify-path
      rm -f "$rustup_init"
    fi
    unset rustup_init
    remember_installed "rustup"
    # Add cargo to current PATH
    export PATH="$HOME/.cargo/bin:$PATH"
    require_command_available rustup "Rust install"
  else
    remember_skipped "rustup"
    ok "rustup already installed."
  fi

  # Ensure cargo in PATH for future shells
  if [[ "$INSTALL_DOTFILES" == "true" ]] && dotfiles_payload_available; then
    log "Cargo PATH is handled by dotfiles."
  elif [[ "$INSTALL_DOTFILES" == "true" ]]; then
    append_once "$TEEUPSHRC" "Added by teeup.sh - Cargo path" <<'EOF'
# Rust (cargo)
if [ -f "$HOME/.cargo/env" ]; then
  . "$HOME/.cargo/env"
fi
EOF
  fi
else
  log "Skipping Rust setup (RUN_RUST=false)"
fi


############################
# ===== Emacs install ==== #
############################
if [[ "$RUN_EMACS" == "true" ]]; then
  # Choose CLI formula to keep script simple/portable. Switch to --cask emacs if you prefer GUI.
  echo "Checking if Emacs is installed"
  pkg_install emacs emacs

  if [[ "$CREATE_MIN_EMACS_INIT" == "true" ]]; then
    EMACS_DIR="${HOME}/.emacs.d"
    run_cmd mkdir -p "$EMACS_DIR"
    INIT_FILE="$EMACS_DIR/init.el"
    if [[ ! -f "$INIT_FILE" ]]; then
      if [[ "$DRY_RUN" == "true" ]]; then
        emoj "🔍"
        echo "[DRY-RUN] Would write $INIT_FILE"
      else
        cat > "$INIT_FILE" <<'EOF'
;; Minimal init.el (added by teeup.sh)
(setq inhibit-startup-message t)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(column-number-mode 1)
(global-display-line-numbers-mode 1)

;; Package bootstrap
(require 'package)
(setq package-archives '(("melpa" . "https://melpa.org/packages/")
                         ("gnu"   . "https://elpa.gnu.org/packages/")))
(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))

(dolist (pkg '(use-package))
  (unless (package-installed-p pkg)
    (package-install pkg)))

(eval-when-compile (require 'use-package))
(setq use-package-always-ensure t)

(use-package magit)
(use-package vertico
  :init (vertico-mode))
(use-package orderless
  :init (setq completion-styles '(orderless basic)
              completion-category-defaults nil))
EOF
        ok "Created minimal Emacs init at $INIT_FILE"
      fi
    else
      log "Emacs init already exists at $INIT_FILE — not overwriting."
    fi
  fi
else
  log "Skipping Emacs setup (RUN_EMACS=false)"
fi

#####################################
# ===== Colima + Docker CLIs ====== #
#####################################
if [[ "$RUN_DOCKER" == "true" ]]; then
  if is_macos; then
    # Install Docker CLI and Colima runtime (no Docker Desktop dependency).
    if [[ "$RESOLVED_PACKAGE_MANAGER" == "macports" ]]; then
      DOCKER_PACKAGES=(docker docker-compose-plugin colima)
    else
      DOCKER_PACKAGES=(docker docker-compose colima)
    fi
    for f in "${DOCKER_PACKAGES[@]}"; do
      pkg_install "$f" "$(package_command "$f")"
    done

    # Start Colima if not running; create or update profile.
    if colima status --profile "$COLIMA_PROFILE" >/dev/null 2>&1; then
      if ! colima status --profile "$COLIMA_PROFILE" | grep -q "Running"; then
        log "Starting Colima profile '$COLIMA_PROFILE'…"
        run_cmd colima start --profile "$COLIMA_PROFILE" --cpu "$COLIMA_CPUS" --memory "$COLIMA_MEMORY" --disk "$COLIMA_DISK" --runtime "$COLIMA_RUNTIME" || warn "Colima start failed."
      else
        log "Colima '$COLIMA_PROFILE' already running."
      fi
    else
      log "Creating & starting Colima profile '$COLIMA_PROFILE'…"
      run_cmd colima start --profile "$COLIMA_PROFILE" --cpu "$COLIMA_CPUS" --memory "$COLIMA_MEMORY" --disk "$COLIMA_DISK" --runtime "$COLIMA_RUNTIME" || warn "Colima start failed."
    fi
    ok "Docker CLI should now target Colima. Try: docker ps"
  else
    # Linux path: open-source Docker engine + compose packages.
    DOCKER_PACKAGES=(docker docker-compose)
    for f in "${DOCKER_PACKAGES[@]}"; do
      pkg_install "$f" "$(package_command "$f")"
    done

    if have systemctl; then
      if [[ "$DRY_RUN" == "true" ]]; then
        run_privileged systemctl enable --now docker
      else
        run_privileged systemctl enable --now docker || warn "Could not enable/start docker service. Start it manually if needed."
      fi
    fi

    # Let the invoking user run docker without sudo.
    DOCKER_TARGET_USER="${SUDO_USER:-$(id -un)}"
    if [[ "$DOCKER_TARGET_USER" == "root" ]]; then
      log "Running as root; skipping docker group membership."
    elif ! have usermod; then
      warn "usermod is unavailable; add '$DOCKER_TARGET_USER' to the 'docker' group manually."
      remember_skipped "docker group ($DOCKER_TARGET_USER)"
    elif [[ "$DRY_RUN" != "true" ]] && id -nG "$DOCKER_TARGET_USER" 2>/dev/null | grep -qw docker; then
      log "User '$DOCKER_TARGET_USER' is already in the docker group."
      remember_skipped "docker group ($DOCKER_TARGET_USER)"
    elif run_privileged usermod -aG docker "$DOCKER_TARGET_USER"; then
      remember_installed "docker group ($DOCKER_TARGET_USER)"
      warn "Added '$DOCKER_TARGET_USER' to the 'docker' group. Log out and back in (or run 'newgrp docker') before running docker without sudo."
    else
      warn "Could not add '$DOCKER_TARGET_USER' to the docker group; you may need to run docker with sudo."
    fi
    ok "Docker engine and CLI should now be available. Try: docker ps"
  fi
else
  log "Skipping Docker setup (RUN_DOCKER=false)"
fi

##########################################
# ===== Bruno & Obsidian (casks) ======= #
##########################################
if [[ "$RUN_APPS" == "true" ]]; then
  if ! platform_supports_module "apps"; then
    handle_unsupported_module "apps" "$PLATFORM_SUPPORT_REASON"
    RUN_APPS=false
  fi
fi

if [[ "$RUN_APPS" == "true" ]]; then
  # Check which apps to install (defaults to true if not set)
  INSTALL_BRUNO="${INSTALL_BRUNO:-true}"
  INSTALL_OBSIDIAN="${INSTALL_OBSIDIAN:-true}"

  # Build casks array based on selection
  CASKS=()
  [[ "$INSTALL_BRUNO" == "true" ]] && CASKS+=("bruno")
  [[ "$INSTALL_OBSIDIAN" == "true" ]] && CASKS+=("obsidian")

  if [[ ${#CASKS[@]} -eq 0 ]]; then
    log "No apps selected for installation."
  elif ! homebrew_casks_allowed; then
    warn "Skipping GUI app casks in $(package_manager_label) mode."
    warn "Install Bruno/Obsidian manually, or set ALLOW_HOMEBREW_CASK_FALLBACK=true with Homebrew already installed."
    for c in "${CASKS[@]}"; do
      remember_skipped "$c (cask; $(package_manager_label) mode)"
    done
  else
    for c in "${CASKS[@]}"; do
      if brew list --cask "$c" >/dev/null 2>&1; then
        remember_skipped "$c (cask)"
        log "Already installed cask: $c"
      else
        run_cmd brew install --cask "$c"
        remember_installed "$c (cask)"
      fi
    done
  fi

  if [[ "$INSTALL_OBSIDIAN" == "true" && "$CREATE_OBSIDIAN_VAULT" == "true" ]]; then
    VAULT_DIR="${HOME}/Documents/ObsidianVault"
    if [[ ! -d "$VAULT_DIR" ]]; then
      run_cmd mkdir -p "$VAULT_DIR"
      if [[ "$DRY_RUN" != "true" ]]; then
        ok "Created starter Obsidian vault at: $VAULT_DIR"
      fi
    else
      log "Obsidian vault already exists at: $VAULT_DIR"
    fi
  fi
else
  log "Skipping Apps setup (RUN_APPS=false)"
fi

#################################
# ===== Shell dotfiles add =====#
#################################
if [[ "$INSTALL_DOTFILES" == "true" ]]; then
  if dotfiles_payload_available; then
    log "Installing dotfiles from $DOTFILES_DIR for $TARGET_SHELL"
    # Shared, shell-agnostic dotfiles.
    install_dotfile_link "$DOTFILES_DIR/shellrc.common" "$HOME/.shellrc.common"
    install_dotfile_link "$DOTFILES_DIR/teeupshrc" "$HOME/.teeupshrc"
    install_dotfile_link "$DOTFILES_DIR/gitconfig" "$HOME/.gitconfig"
    install_dotfile_link "$DOTFILES_DIR/tmux.conf" "$HOME/.tmux.conf"
    # Shell-specific dotfiles for the target login shell only (segregated).
    if [[ "$TARGET_SHELL" == "zsh" ]]; then
      install_dotfile_link "$DOTFILES_DIR/zshrc" "$HOME/.zshrc"
      install_dotfile_link "$DOTFILES_DIR/zprofile" "$HOME/.zprofile"
    else
      install_dotfile_link "$DOTFILES_DIR/bashrc" "$HOME/.bashrc"
      install_dotfile_link "$DOTFILES_DIR/.bash_profile" "$HOME/.bash_profile"
      install_dotfile_link "$DOTFILES_DIR/profile" "$HOME/.profile"
      if [[ -f "$DOTFILES_DIR/starship.toml" ]]; then
        run_cmd mkdir -p "$HOME/.config"
        install_dotfile_link "$DOTFILES_DIR/starship.toml" "$HOME/.config/starship.toml"
      fi
    fi
  else
    warn "DOTFILES_DIR is not available; falling back to small managed shell blocks."
    append_once "$TEEUPSHRC" "Added by teeup.sh - aliases" <<'EOF'
# Handy aliases
alias ll='ls -lah'
alias cls='clear'
alias grv='git remote -v'
alias colima-start='colima start'
alias colima-stop='colima stop'
EOF
    append_once "$TEEUPSHRC" "Added by teeup.sh - SDKMAN init" <<'EOF'
# SDKMAN!
if [ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]; then
  . "$HOME/.sdkman/bin/sdkman-init.sh"
fi
EOF
    ensure_teeupshrc_sourced
  fi
fi

if [[ "$RUN_ZSH" == "true" && "$TARGET_SHELL" == "zsh" ]]; then
  if [[ "$INSTALL_DOTFILES" == "true" ]] && dotfiles_payload_available; then
    log "zsh integration is sourced by dotfiles zshrc."
  else
    append_once "$ZSHRC" "Added by teeup.sh - zsh integration" <<'EOF'
if [ -r "$HOME/.config/mac-setup/zsh.zsh" ]; then
  source "$HOME/.config/mac-setup/zsh.zsh"
fi
EOF
  fi
fi

if [[ "$RECONCILE_EXISTING_CONFIG" == "true" ]]; then
  log "Reconciling existing shell config."
  if [[ "$USE_UV" == "true" ]] && { have pyenv || [[ -d "$HOME/.pyenv" ]]; }; then
    log "pyenv detected and UV selected; disabling pyenv shell init."
    if have uv && have pipx; then
      log "Migrating pipx tools to uv tool where possible."
      while IFS= read -r tool; do
        [[ -z "$tool" ]] && continue
        if [[ "$DRY_RUN" == "true" ]]; then
          run_cmd uv tool install "$tool"
        else
          uv tool install "$tool" 2>/dev/null || warn "Failed to install uv tool: $tool"
        fi
      done < <(pipx list 2>/dev/null | awk '/^[[:space:]]*package / {print $2}')
    fi
  fi
  for shell_file in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    disable_matching_lines "$shell_file" 'antigen|antigenrc|antigen\.zsh' "Antigen removed"
    if [[ "$USE_UV" == "true" ]]; then
      disable_matching_lines "$shell_file" 'pyenv (init|virtualenv-init)|PYENV_ROOT|\.pyenv' "uv migration"
    fi
    disable_matching_lines "$shell_file" 'M2_HOME|apache-maven-3\.6\.0|openssl@1\.1|Python/3\.7|powerline|smlnj|/usr/local/smlnj' "stale hardcoded tool path"
  done
  echo ""
  warn "Optional cleanup after verifying a new shell works:"
  echo "   rm -rf ~/.antigen"
  if [[ "$RESOLVED_PACKAGE_MANAGER" == "homebrew" ]]; then
    echo "   brew uninstall pyenv pyenv-virtualenv pipx"
  fi
  echo "   rm -rf ~/.pyenv"
fi

cleanup_homebrew_overlaps

#################################
# ===== macOS Defaults (opt) ===#
#################################
if [[ "$TUNE_DEFAULTS" == "true" ]]; then
  if ! platform_supports_module "macos-defaults"; then
    handle_unsupported_module "macos-defaults" "$PLATFORM_SUPPORT_REASON"
  else
    log "Applying optional macOS defaults…"
    # Show all filename extensions in Finder
    run_cmd defaults write NSGlobalDomain AppleShowAllExtensions -bool true
    # Expand save/print panels by default
    run_cmd defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
    run_cmd defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
    # Fast key repeat
    run_cmd defaults write NSGlobalDomain KeyRepeat -int 2
    run_cmd defaults write NSGlobalDomain InitialKeyRepeat -int 15
    if [[ "$DRY_RUN" == "true" ]]; then
      log "Defaults preview complete."
    else
      ok "Defaults applied (a logout/login may be required for some)."
    fi
  fi
fi

#########################
# ===== Final log ===== #
#########################
echo ""
emoj "🧾"; echo "Install summary:"
for item in ${SUMMARY_INSTALLED[@]+"${SUMMARY_INSTALLED[@]}"}; do
  emoj "  ➕"; echo " $item"
done
for item in ${SUMMARY_SKIPPED[@]+"${SUMMARY_SKIPPED[@]}"}; do
  emoj "  ↩️"; echo " $item"
done
SETUP_END_EPOCH="$(date +%s)"
SETUP_ELAPSED_SECONDS=$((SETUP_END_EPOCH - SETUP_START_EPOCH))

echo ""
ok "All done! Open a new terminal (or 'exec ${TARGET_SHELL:-zsh}') to load updated PATH/initializations."
if is_macos; then
  warn "Colima may require full-disk/network permissions on first use. If docker commands fail, restart your shell and try: 'colima start'."
fi
printf "%b Install duration: %s\n" "⏱️" "$(format_duration "$SETUP_ELAPSED_SECONDS")"
