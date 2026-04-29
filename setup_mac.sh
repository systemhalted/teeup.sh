#!/usr/bin/env bash
# setup_mac.sh — Mac developer bootstrap
# Installs Homebrew, pyenv, SDKMAN!, Emacs, Colima (+ docker CLIs), Bruno, Obsidian, and common CLI tools.
# Safe to rerun. Tested for Apple Silicon
#
# Usage:
#   ./setup_mac.sh                    # Run full setup
#   ./setup_mac.sh --only python      # Run only Python setup
#   ./setup_mac.sh --only java,docker # Run only Java and Docker setup
#   ./setup_mac.sh --migrate-to-uv    # Migrate from pyenv to UV
#   ./setup_mac.sh --help             # Show usage

set -euo pipefail

#############################
# ===== User Toggles ===== #
#############################

# Versions
PYTHON_VERSION="${PYTHON_VERSION:-3.12.5}"          # Override by: PYTHON_VERSION=3.13.x ./setup_mac.sh
JDK_DIST="${JDK_DIST:-temurin}"                     # SDKMAN candidate vendor (temurin, oracle, liberica, etc.)
JDK_VERSION="${JDK_VERSION:-21.0.4-tem}"            # SDKMAN version identifier (e.g., "21.0.4-tem" for Temurin 21)

# Feature toggles
USE_UV="${USE_UV:-true}"                            # Use uv instead of pyenv/poetry/pipx (recommended)
INSTALL_PY_TOOLS="${INSTALL_PY_TOOLS:-true}"        # Install Python tools (via uv tool or pipx)
INSTALL_DOTFILES="${INSTALL_DOTFILES:-true}"        # Add aliases and init lines to ~/.zshrc
TUNE_DEFAULTS="${TUNE_DEFAULTS:-false}"             # Apply some macOS defaults
CREATE_MIN_EMACS_INIT="${CREATE_MIN_EMACS_INIT:-true}"
CREATE_OBSIDIAN_VAULT="${CREATE_OBSIDIAN_VAULT:-false}"  # Create starter vault folder
DRY_RUN="${DRY_RUN:-false}"                         # Preview commands without executing them

# Module toggles (all enabled by default, use --only to run specific modules)
RUN_HOMEBREW="${RUN_HOMEBREW:-true}"
RUN_OHMYZSH="${RUN_OHMYZSH:-true}"
RUN_CLI="${RUN_CLI:-true}"
RUN_PYTHON="${RUN_PYTHON:-true}"
RUN_JAVA="${RUN_JAVA:-true}"
RUN_EMACS="${RUN_EMACS:-true}"
RUN_DOCKER="${RUN_DOCKER:-true}"
RUN_APPS="${RUN_APPS:-true}"

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
log()  { emoj "🔹"; echo "$*"; }
ok()   { emoj "✅"; echo "$*"; }
warn() { emoj "⚠️"; echo "$*" >&2; }
err()  { emoj "❌"; echo "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

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

show_help() {
  cat <<EOF
Mac Setup Script - Bootstrap your macOS development environment

Usage:
  ./setup_mac.sh [OPTIONS]

Options:
  --help                Show this help message
  --dry-run             Preview commands without executing them
  --only MODULES        Run only specified modules (comma-separated)
                        Available: homebrew,ohmyzsh,cli,python,java,emacs,docker,apps
  --migrate-to-uv       Migrate from pyenv/poetry/pipx to UV
  --list-modules        List available modules

Environment Variables:
  PYTHON_VERSION        Python version to install (default: 3.12.5)
  JDK_VERSION           Java version for SDKMAN (default: 21.0.4-tem)
  USE_UV                Use UV instead of pyenv (default: true)
  INSTALL_DOTFILES      Update ~/.zshrc (default: true)
  TUNE_DEFAULTS         Apply macOS defaults (default: false)
  DRY_RUN               Preview mode, no actual changes (default: false)

Examples:
  # Full setup
  ./setup_mac.sh

  # Preview what would be installed (dry-run)
  ./setup_mac.sh --dry-run

  # Only install Python environment
  ./setup_mac.sh --only python

  # Preview Python installation
  ./setup_mac.sh --dry-run --only python

  # Migrate from pyenv to UV
  ./setup_mac.sh --migrate-to-uv

  # Use pyenv instead of UV
  USE_UV=false ./setup_mac.sh --only python
EOF
  exit 0
}

list_modules() {
  cat <<EOF
Available modules:
  homebrew  - Homebrew package manager
  ohmyzsh   - Oh My Zsh + Powerlevel10k + plugins
  cli       - Core CLI utilities (git, jq, ripgrep, etc.)
  python    - Python environment (UV or pyenv/poetry)
  java      - SDKMAN! + Java + Maven/Gradle
  emacs     - Emacs editor + minimal config
  docker    - Colima + Docker CLI
  apps      - GUI apps (Bruno, Obsidian)
EOF
  exit 0
}

parse_only_modules() {
  local modules="$1"
  # Disable all modules first
  RUN_HOMEBREW=false
  RUN_OHMYZSH=false
  RUN_CLI=false
  RUN_PYTHON=false
  RUN_JAVA=false
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
      ohmyzsh)  RUN_OHMYZSH=true ;;
      cli)      RUN_CLI=true ;;
      python)   RUN_PYTHON=true ;;
      java)     RUN_JAVA=true ;;
      emacs)    RUN_EMACS=true ;;
      docker)   RUN_DOCKER=true ;;
      apps)     RUN_APPS=true ;;
      *) warn "Unknown module: $mod" ;;
    esac
  done

  # Homebrew is always needed as a dependency
  if [[ "$RUN_CLI" == "true" || "$RUN_PYTHON" == "true" || "$RUN_EMACS" == "true" || "$RUN_DOCKER" == "true" || "$RUN_APPS" == "true" ]]; then
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
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    ok "UV installed"
  else
    ok "UV already installed"
  fi

  # Install Python version via UV
  log "Installing Python $PYTHON_VERSION via UV..."
  uv python install "$PYTHON_VERSION"
  ok "Python $PYTHON_VERSION installed via UV"

  # Migrate pipx tools to uv tool
  if have pipx; then
    log "Migrating pipx tools to UV..."
    local tools
    tools=$(pipx list 2>/dev/null | grep "package " | awk '{print $2}' || true)
    for tool in $tools; do
      log "Installing $tool via uv tool..."
      uv tool install "$tool" 2>/dev/null || warn "Failed to install $tool"
    done
    ok "Tools migrated to UV"
  fi

  # Update .zshrc
  ZSHRC="${HOME}/.zshrc"
  if [[ -f "$ZSHRC" ]]; then
    log "Updating .zshrc..."

    # Comment out pyenv init lines
    if grep -q "pyenv init" "$ZSHRC"; then
      sed -i '' 's/^eval "\$(pyenv init/# DISABLED by UV migration: eval "$(pyenv init/' "$ZSHRC" 2>/dev/null || true
      sed -i '' 's/^eval "\$(pyenv virtualenv-init/# DISABLED by UV migration: eval "$(pyenv virtualenv-init/' "$ZSHRC" 2>/dev/null || true
      ok "Commented out pyenv init in .zshrc"
    fi

    # Add uv path if not present
    if ! grep -q "uv (Python package manager)" "$ZSHRC"; then
      cat >> "$ZSHRC" <<'EOF'

# Added by setup_mac.sh — uv path
# uv (Python package manager)
export PATH="$HOME/.local/bin:$PATH"
EOF
      ok "Added UV to PATH in .zshrc"
    fi
  fi

  echo ""
  ok "Migration complete!"
  echo ""
  echo "📝 Next steps:"
  echo "   1. Run: exec zsh (to reload shell)"
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

append_once() {
  # append_once <file> <unique_marker> <block...>
  local file="$1"; shift
  local marker="$1"; shift
  local tmp
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if ! grep -q "$marker" "$file"; then
    tmp="$(mktemp)"
    {
      echo ""
      echo "# ${marker}"
      cat
    } > "$tmp"
    cat "$tmp" >> "$file"
    rm -f "$tmp"
    ok "Updated $(basename "$file") with: $marker"
  else
    log "Already present in $(basename "$file"): $marker"
  fi
}

SUMMARY_INSTALLED=()
SUMMARY_SKIPPED=()

remember_installed() { SUMMARY_INSTALLED+=("$1"); }
remember_skipped()   { SUMMARY_SKIPPED+=("$1"); }

########################################
# ===== Detect architecture/OS ======  #
########################################
ARCH="$(uname -m)"
OS="$(uname -s)"
if [[ "$OS" != "Darwin" ]]; then
  err "This script is intended for macOS."
  exit 1
fi
ok "Detected macOS on $ARCH"

########################################
# ===== Xcode CLT & Rosetta (ARM) ==== #
########################################
if ! xcode-select -p >/dev/null 2>&1; then
  log "Installing Xcode Command Line Tools…"
  xcode-select --install || true
  warn "If a dialog appeared, complete it and re-run the script if needed."
else
  ok "Xcode Command Line Tools present."
fi

if [[ "$ARCH" == "arm64" ]]; then
  if ! pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
    log "Installing Rosetta 2 (Apple Silicon)…"
    /usr/sbin/softwareupdate --install-rosetta --agree-to-license || warn "Rosetta install may require approval."
  else
    ok "Rosetta 2 already installed."
  fi
fi

#############################
# ===== Homebrew setup ==== #
#############################
if [[ "$RUN_HOMEBREW" == "true" ]]; then
  BREW_PREFIX="/usr/local"
  if [[ "$ARCH" == "arm64" ]]; then
    BREW_PREFIX="/opt/homebrew"
  fi

  if ! have brew; then
    log "Installing Homebrew…"
    if [[ "$DRY_RUN" == "true" ]]; then
      run_cmd bash -c "curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | NONINTERACTIVE=1 bash"
    else
      NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    ok "Homebrew installed."
  else
    ok "Homebrew already installed."
  fi

  # Ensure Brew in PATH for current shell
  if [[ ":$PATH:" != *":$BREW_PREFIX/bin:"* ]]; then
    export PATH="$BREW_PREFIX/bin:$PATH"
  fi

  # Ensure Brew in future shells
  ZPROFILE="${HOME}/.zprofile"
  append_once "$ZPROFILE" "Added by setup_mac.sh — Homebrew path" <<EOF
# Homebrew (added by setup_mac.sh)
if [ -d "$BREW_PREFIX/bin" ]; then
  export PATH="$BREW_PREFIX/bin:\$PATH"
fi
EOF

  log "Updating Homebrew…"
  run_cmd brew update || warn "brew update returned non-zero."
  run_cmd brew upgrade || warn "brew upgrade returned non-zero."
else
  log "Skipping Homebrew setup (RUN_HOMEBREW=false)"
  # Still need BREW_PREFIX for other modules
  BREW_PREFIX="/usr/local"
  if [[ "$ARCH" == "arm64" ]]; then
    BREW_PREFIX="/opt/homebrew"
  fi
fi

###################################
# ===== Oh My Zsh + Plugins ===== #
###################################
if [[ "$RUN_OHMYZSH" == "true" ]]; then
  OMZ_DIR="${HOME}/.oh-my-zsh"
  if [[ ! -d "$OMZ_DIR" ]]; then
    log "Installing Oh My Zsh…"
    if [[ "$DRY_RUN" == "true" ]]; then
      run_cmd sh -c "curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | RUNZSH=no KEEP_ZSHRC=yes sh"
    else
      RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    fi
    remember_installed "oh-my-zsh"
  else
    remember_skipped "oh-my-zsh"
    log "Oh My Zsh already installed."
  fi

  # Install zsh-autosuggestions plugin
  ZSH_AUTOSUGGESTIONS_DIR="${ZSH_CUSTOM:-$OMZ_DIR/custom}/plugins/zsh-autosuggestions"
  if [[ ! -d "$ZSH_AUTOSUGGESTIONS_DIR" ]]; then
    log "Installing zsh-autosuggestions plugin…"
    run_cmd git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_AUTOSUGGESTIONS_DIR"
    remember_installed "zsh-autosuggestions"
  else
    remember_skipped "zsh-autosuggestions"
  fi

  # Install zsh-syntax-highlighting plugin
  ZSH_SYNTAX_HIGHLIGHTING_DIR="${ZSH_CUSTOM:-$OMZ_DIR/custom}/plugins/zsh-syntax-highlighting"
  if [[ ! -d "$ZSH_SYNTAX_HIGHLIGHTING_DIR" ]]; then
    log "Installing zsh-syntax-highlighting plugin…"
    run_cmd git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_SYNTAX_HIGHLIGHTING_DIR"
    remember_installed "zsh-syntax-highlighting"
  else
    remember_skipped "zsh-syntax-highlighting"
  fi

  # Install Powerlevel10k theme
  P10K_DIR="${ZSH_CUSTOM:-$OMZ_DIR/custom}/themes/powerlevel10k"
  if [[ ! -d "$P10K_DIR" ]]; then
    log "Installing Powerlevel10k theme…"
    run_cmd git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
    remember_installed "powerlevel10k"
  else
    remember_skipped "powerlevel10k"
  fi

  # Configure Oh My Zsh in .zshrc
  if [[ "$INSTALL_DOTFILES" == "true" ]]; then
    # Set ZSH_THEME if not already set to powerlevel10k
    if ! grep -q 'ZSH_THEME="powerlevel10k/powerlevel10k"' "$ZSHRC" 2>/dev/null; then
      # Replace existing ZSH_THEME or add it
      if grep -q '^ZSH_THEME=' "$ZSHRC" 2>/dev/null; then
        sed -i '' 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC"
        ok "Updated ZSH_THEME to powerlevel10k"
      else
        append_once "$ZSHRC" "Added by setup_mac.sh — Oh My Zsh theme" <<'EOF'
ZSH_THEME="powerlevel10k/powerlevel10k"
EOF
      fi
    fi

    # Set plugins if not already configured
    if ! grep -q 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' "$ZSHRC" 2>/dev/null; then
      if grep -q '^plugins=' "$ZSHRC" 2>/dev/null; then
        sed -i '' 's|^plugins=.*|plugins=(git zsh-autosuggestions zsh-syntax-highlighting)|' "$ZSHRC"
        ok "Updated plugins list"
      else
        append_once "$ZSHRC" "Added by setup_mac.sh — Oh My Zsh plugins" <<'EOF'
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
EOF
      fi
    fi

    # Ensure Oh My Zsh is sourced
    append_once "$ZSHRC" "Added by setup_mac.sh — Oh My Zsh source" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
source $ZSH/oh-my-zsh.sh
EOF
  fi
else
  log "Skipping Oh My Zsh setup (RUN_OHMYZSH=false)"
fi



###################################
# ===== Core CLI utilities ====== #
###################################
if [[ "$RUN_CLI" == "true" ]]; then
  CLI_FORMULAE=(
    git wget curl jq htop tree tmux ripgrep fd gnupg
  )

  log "Installing core CLI utilities…"
  for f in "${CLI_FORMULAE[@]}"; do
    if brew list --formula "$f" >/dev/null 2>&1; then
      remember_skipped "$f (brew)"
      log "Already installed: $f"
    else
      run_cmd brew install "$f"
      remember_installed "$f (brew)"
    fi
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
  else
    remember_skipped "uv"
    ok "UV already installed."
  fi

  # Ensure uv is in PATH for future shells
  if [[ "$INSTALL_DOTFILES" == "true" ]]; then
    append_once "$ZSHRC" "Added by setup_mac.sh — uv path" <<'EOF'
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
    run_cmd uv python pin "$PYTHON_VERSION"
  else
    uv python pin "$PYTHON_VERSION" 2>/dev/null || true
  fi

  # Install Python dev tools via uv tool
  if [[ "$INSTALL_PY_TOOLS" == "true" ]]; then
    UV_TOOLS=(ruff black httpie)
    for t in "${UV_TOOLS[@]}"; do
      if uv tool list 2>/dev/null | grep -q "^$t "; then
        remember_skipped "uv:$t"
        log "uv tool already installed: $t"
      else
        uv tool install "$t" || warn "Failed to install uv tool: $t"
        remember_installed "uv:$t"
      fi
    done
  fi

else
  #################################
  # ===== pyenv + Python setup == #
  #################################
  log "Using pyenv/poetry for Python management (legacy)"

  if ! brew list --formula pyenv >/dev/null 2>&1; then
    run_cmd brew install pyenv
    remember_installed "pyenv"
  else
    remember_skipped "pyenv"
  fi

  if ! brew list --formula pyenv-virtualenv >/dev/null 2>&1; then
    run_cmd brew install pyenv-virtualenv
    remember_installed "pyenv-virtualenv"
  else
    remember_skipped "pyenv-virtualenv"
  fi

  ZSHRC="${HOME}/.zshrc"
  if [[ "$INSTALL_DOTFILES" == "true" ]]; then
    append_once "$ZSHRC" "Added by setup_mac.sh — pyenv init" <<'EOF'
# pyenv init
if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init -)"
  eval "$(pyenv virtualenv-init -)"
fi
EOF
  fi

  # Ensure shims for current session
  if have pyenv; then
    eval "$(pyenv init -)"
    eval "$(pyenv virtualenv-init -)"
  fi

  log "Ensuring Python $PYTHON_VERSION via pyenv…"
  if pyenv versions --bare | grep -qx "$PYTHON_VERSION"; then
    remember_skipped "python@$PYTHON_VERSION (pyenv)"
    log "Python $PYTHON_VERSION already installed with pyenv."
  else
    # Build deps help (esp. for older Pythons)
    run_cmd brew install openssl readline sqlite xz tcl-tk zlib bzip2 || true
    if [[ "$DRY_RUN" == "true" ]]; then
      run_cmd pyenv install "$PYTHON_VERSION"
    else
      CFLAGS="-I$BREW_PREFIX/opt/zlib/include -I$BREW_PREFIX/opt/bzip2/include" \
      LDFLAGS="-L$BREW_PREFIX/opt/zlib/lib -L$BREW_PREFIX/opt/bzip2/lib" \
      PYTHON_CONFIGURE_OPTS="--enable-framework" \
      pyenv install "$PYTHON_VERSION"
    fi
    remember_installed "python@$PYTHON_VERSION (pyenv)"
  fi

  if [[ "$DRY_RUN" != "true" ]]; then
    pyenv global "$PYTHON_VERSION" || warn "Could not set global Python to $PYTHON_VERSION."
  else
    run_cmd pyenv global "$PYTHON_VERSION"
  fi

  # pipx + Python dev tools
  if ! brew list --formula pipx >/dev/null 2>&1; then
    run_cmd brew install pipx
    remember_installed "pipx"
  else
    remember_skipped "pipx"
  fi
  pipx ensurepath || true

  if [[ "$INSTALL_PY_TOOLS" == "true" ]]; then
    PY_TOOLS=(poetry black ruff httpie)
    for t in "${PY_TOOLS[@]}"; do
      if pipx list | grep -E "package $t " >/dev/null 2>&1; then
        remember_skipped "pipx:$t"
        log "pipx tool already installed: $t"
      else
        pipx install "$t" || warn "Failed to install pipx tool: $t"
        remember_installed "pipx:$t"
      fi
    done
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
      run_cmd bash -c "curl -s https://get.sdkman.io | bash"
    else
      curl -s "https://get.sdkman.io" | bash
    fi
    remember_installed "SDKMAN!"
  else
    remember_skipped "SDKMAN!"
  fi

  # Source SDKMAN for current session
  if [[ -s "${SDKMAN_DIR}/bin/sdkman-init.sh" ]]; then
    log "Sourcing sdkman-init.sh"
    # shellcheck disable=SC1091
    source "${SDKMAN_DIR}/bin/sdkman-init.sh" || warn "SDKMAN init failed, may need to restart shell"
  else
    warn "SDKMAN init script not found. Reopen your terminal and rerun if needed."
  fi

  # Java via SDKMAN
  echo "Installing Java candidate"
  JAVA_CANDIDATE="${JDK_VERSION}"
  if sdk list java | grep -q "$JAVA_CANDIDATE"; then
    if ! sdk current java | grep -q "$JAVA_CANDIDATE"; then
      log "Installing Java $JAVA_CANDIDATE via SDKMAN!…"
      run_cmd sdk install java "$JAVA_CANDIDATE" || true
      run_cmd sdk default java "$JAVA_CANDIDATE" || true
      remember_installed "java@$JAVA_CANDIDATE (SDKMAN)"
    else
      remember_skipped "java@$JAVA_CANDIDATE (SDKMAN)"
      log "Java $JAVA_CANDIDATE already current."
    fi
  else
    warn "Requested Java candidate $JAVA_CANDIDATE not listed by SDKMAN. Skipping."
  fi

  # Maven/Gradle via SDKMAN (optional but useful)
  for tool in maven gradle; do
    if sdk list "$tool" >/dev/null 2>&1; then
      if ! sdk current "$tool" >/dev/null 2>&1; then
        log "Installing $tool via SDKMAN!…"
        run_cmd sdk install "$tool" || warn "Failed to install $tool"
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

############################
# ===== Emacs install ==== #
############################
if [[ "$RUN_EMACS" == "true" ]]; then
  # Choose CLI formula to keep script simple/portable. Switch to --cask emacs if you prefer GUI.
  echo "Checking if Emacs is installed"
  if brew list --formula emacs >/dev/null 2>&1; then
    remember_skipped "emacs (brew)"
    log "Emacs already installed."
  else
    run_cmd brew install emacs
    remember_installed "emacs (brew)"
  fi

  if [[ "$CREATE_MIN_EMACS_INIT" == "true" ]]; then
    EMACS_DIR="${HOME}/.emacs.d"
    mkdir -p "$EMACS_DIR"
    INIT_FILE="$EMACS_DIR/init.el"
    if [[ ! -f "$INIT_FILE" ]]; then
      cat > "$INIT_FILE" <<'EOF'
;; Minimal init.el (added by setup_mac.sh)
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
  # Install docker CLI and colima (lightweight VM)
  for f in docker docker-compose colima; do
    if brew list --formula "$f" >/dev/null 2>&1; then
      remember_skipped "$f (brew)"
      log "Already installed: $f"
    else
      run_cmd brew install "$f"
      remember_installed "$f (brew)"
    fi
  done

  # Start Colima if not running; create or update profile
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
  log "Skipping Docker setup (RUN_DOCKER=false)"
fi

##########################################
# ===== Bruno & Obsidian (casks) ======= #
##########################################
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
      mkdir -p "$VAULT_DIR"
      ok "Created starter Obsidian vault at: $VAULT_DIR"
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
  append_once "$ZSHRC" "Added by setup_mac.sh — aliases" <<'EOF'
# Handy aliases
alias ll='ls -lah'
alias cls='clear'
alias grv='git remote -v'
alias colima-start='colima start'
alias colima-stop='colima stop'
EOF
  if ! grep -q "alias cls='clear'" "$ZSHRC" 2>/dev/null; then
    append_once "$ZSHRC" "Added by setup_mac.sh — cls alias" <<'EOF'
alias cls='clear'
EOF
  fi
  append_once "$ZSHRC" "Added by setup_mac.sh — SDKMAN init" <<'EOF'
# SDKMAN!
if [ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]; then
  source "$HOME/.sdkman/bin/sdkman-init.sh"
fi
EOF
fi

#################################
# ===== macOS Defaults (opt) ===#
#################################
if [[ "$TUNE_DEFAULTS" == "true" ]]; then
  log "Applying optional macOS defaults…"
  # Show all filename extensions in Finder
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  # Expand save/print panels by default
  defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
  defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
  # Fast key repeat
  defaults write NSGlobalDomain KeyRepeat -int 2
  defaults write NSGlobalDomain InitialKeyRepeat -int 15
  ok "Defaults applied (a logout/login may be required for some)."
fi

#########################
# ===== Final log ===== #
#########################
echo ""
emoj "🧾"; echo "Install summary:"
for item in "${SUMMARY_INSTALLED[@]}"; do
  emoj "  ➕"; echo " $item"
done
for item in "${SUMMARY_SKIPPED[@]}"; do
  emoj "  ↩️"; echo " $item"
done

echo ""
ok "All done! Open a new terminal (or 'exec zsh') to load updated PATH/initializations."
warn "Colima may require full-disk/network permissions on first use. If docker commands fail, restart your shell and try: 'colima start'."

