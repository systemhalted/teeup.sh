#!/usr/bin/env bash
# package_manager.sh — package-manager resolution and install helpers

default_brew_prefix() {
  if [[ "$ARCH" == "arm64" ]]; then
    echo "/opt/homebrew"
  else
    echo "/usr/local"
  fi
}

run_privileged() {
  if [[ "$DRY_RUN" == "true" ]]; then
    if have sudo && [[ "$(id -u)" -ne 0 ]]; then
      run_cmd sudo "$@"
    else
      run_cmd "$@"
    fi
    return 0
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    run_cmd "$@"
    return $?
  fi

  if have sudo; then
    run_cmd sudo "$@"
    return $?
  fi

  warn "sudo is unavailable; cannot run privileged command: $*"
  return 1
}

normalize_package_manager() {
  local mode_lower
  mode_lower=$(echo "$PACKAGE_MANAGER" | tr '[:upper:]' '[:lower:]')
  case "$mode_lower" in
    auto|homebrew|macports|apt|dnf) PACKAGE_MANAGER="$mode_lower" ;;
    *)
      warn "Unknown PACKAGE_MANAGER '$PACKAGE_MANAGER'; defaulting to auto"
      PACKAGE_MANAGER="auto"
      ;;
  esac
}

resolve_package_manager() {
  normalize_package_manager

  if [[ "$PACKAGE_MANAGER" != "auto" ]]; then
    RESOLVED_PACKAGE_MANAGER="$PACKAGE_MANAGER"
    return 0
  fi

  if is_macos; then
    local major
    major="$(sw_vers -productVersion | awk -F. '{print $1}')"
    if [[ "$major" =~ ^[0-9]+$ && "$major" -le 12 ]]; then
      RESOLVED_PACKAGE_MANAGER="macports"
    else
      RESOLVED_PACKAGE_MANAGER="homebrew"
    fi
    return 0
  fi

  if is_linux; then
    if linux_distro_matches ubuntu || linux_distro_matches debian; then
      RESOLVED_PACKAGE_MANAGER="apt"
      return 0
    fi
    if linux_distro_matches fedora || linux_distro_matches rhel || linux_distro_matches centos; then
      RESOLVED_PACKAGE_MANAGER="dnf"
      return 0
    fi

    # Best-effort default for unknown distros.
    if have apt-get; then
      RESOLVED_PACKAGE_MANAGER="apt"
      return 0
    fi
    if have dnf; then
      RESOLVED_PACKAGE_MANAGER="dnf"
      return 0
    fi
  fi

  err "Could not resolve package manager automatically for ${PLATFORM_LABEL:-this platform}."
  err "Set PACKAGE_MANAGER explicitly (supported: homebrew, macports, apt, dnf)."
  exit 1
}

validate_package_manager_for_platform() {
  case "$RESOLVED_PACKAGE_MANAGER" in
    homebrew|macports)
      if ! is_macos; then
        err "PACKAGE_MANAGER=$RESOLVED_PACKAGE_MANAGER is only supported on macOS."
        exit 1
      fi
      ;;
    apt|dnf)
      if ! is_linux; then
        err "PACKAGE_MANAGER=$RESOLVED_PACKAGE_MANAGER is only supported on Linux."
        exit 1
      fi
      ;;
  esac
}

package_manager_label() {
  case "$RESOLVED_PACKAGE_MANAGER" in
    homebrew) echo "Homebrew" ;;
    macports) echo "MacPorts" ;;
    apt) echo "APT" ;;
    dnf) echo "DNF" ;;
    *) echo "$RESOLVED_PACKAGE_MANAGER" ;;
  esac
}

package_manager_tag() {
  case "$RESOLVED_PACKAGE_MANAGER" in
    homebrew) echo "brew" ;;
    macports) echo "port" ;;
    apt) echo "apt" ;;
    dnf) echo "dnf" ;;
    *) echo "$RESOLVED_PACKAGE_MANAGER" ;;
  esac
}

prepend_path_once() {
  local path_entry="$1"
  [[ -d "$path_entry" ]] || return 0
  PATH=":$PATH:"
  PATH="${PATH//:$path_entry:/:}"
  PATH="${PATH#:}"
  PATH="${PATH%:}"
  export PATH="$path_entry${PATH:+:$PATH}"
}

prepend_prefix_path() {
  local prefix="$1"
  prepend_path_once "$prefix/sbin"
  prepend_path_once "$prefix/bin"
}

apply_package_manager_path() {
  if ! is_macos; then
    return 0
  fi

  case "$RESOLVED_PACKAGE_MANAGER" in
    macports)
      prepend_prefix_path "$BREW_PREFIX"
      prepend_prefix_path "$MACPORTS_PREFIX"
      ;;
    *)
      prepend_prefix_path "$MACPORTS_PREFIX"
      prepend_prefix_path "$BREW_PREFIX"
      ;;
  esac
}

print_macports_install_instructions() {
  err "MacPorts is selected but the 'port' command is not available."
  echo "Install the official MacPorts pkg for this macOS version, then rerun setup:"
  echo "  https://www.macports.org/install.php"
  echo "Expected prefix after install: $MACPORTS_PREFIX"
}

require_package_manager() {
  case "$RESOLVED_PACKAGE_MANAGER" in
    homebrew)
      if ! have brew && [[ "$DRY_RUN" != "true" ]]; then
        err "Homebrew is required but the 'brew' command is not available."
        exit 1
      fi
      ;;
    macports)
      if ! have port; then
        if [[ "$DRY_RUN" == "true" ]]; then
          if [[ "${MACPORTS_MISSING_WARNED:-false}" != "true" ]]; then
            print_macports_install_instructions
            warn "Continuing dry-run without MacPorts installed."
            MACPORTS_MISSING_WARNED=true
          fi
          return 0
        fi
        print_macports_install_instructions
        exit 1
      fi
      ;;
    apt)
      if ! have apt-get && [[ "$DRY_RUN" != "true" ]]; then
        err "APT is selected but apt-get is not available."
        exit 1
      fi
      ;;
    dnf)
      if ! have dnf && [[ "$DRY_RUN" != "true" ]]; then
        err "DNF is selected but dnf is not available."
        exit 1
      fi
      ;;
  esac
}

package_command() {
  local pkg="$1"
  case "$pkg" in
    gnupg|gnupg2) echo "gpg" ;;
    ripgrep) echo "rg" ;;
    fd)
      case "$RESOLVED_PACKAGE_MANAGER" in
        apt) echo "fdfind" ;;
        *) echo "fd" ;;
      esac
      ;;
    docker-compose|docker-compose-plugin)
      # On Linux the Compose plugin provides the `docker compose` subcommand
      # rather than a standalone `docker-compose` binary, so don't assert one.
      case "$RESOLVED_PACKAGE_MANAGER" in
        apt|dnf) echo "" ;;
        *) echo "docker-compose" ;;
      esac
      ;;
    *) echo "$pkg" ;;
  esac
}

package_candidates() {
  local pkg="$1"

  case "$RESOLVED_PACKAGE_MANAGER:$pkg" in
    apt:fd) echo "fd-find fd" ;;
    dnf:fd) echo "fd-find fd" ;;
    apt:gnupg2) echo "gnupg2 gnupg" ;;
    dnf:gnupg) echo "gnupg2 gnupg" ;;
    apt:docker) echo "docker.io docker-ce" ;;
    dnf:docker) echo "moby-engine docker-ce docker" ;;
    apt:docker-compose|apt:docker-compose-plugin) echo "docker-compose-v2 docker-compose-plugin docker-compose" ;;
    dnf:docker-compose|dnf:docker-compose-plugin) echo "docker-compose-plugin docker-compose" ;;
    apt:zsh-completions) echo "zsh zsh-completions" ;;
    dnf:zsh-completions) echo "zsh zsh-completions" ;;
    homebrew:bash-completion) echo "bash-completion@2 bash-completion" ;;
    *) echo "$pkg" ;;
  esac
}

pkg_installed() {
  local pkg="$1"
  case "$RESOLVED_PACKAGE_MANAGER" in
    homebrew)
      have brew && brew list --formula "$pkg" >/dev/null 2>&1
      ;;
    macports)
      have port && port installed "$pkg" 2>/dev/null | grep -q '(active)'
      ;;
    apt)
      dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"
      ;;
    dnf)
      rpm -q "$pkg" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

pkg_install_candidate() {
  local pkg="$1"
  case "$RESOLVED_PACKAGE_MANAGER" in
    homebrew) run_cmd brew install "$pkg" ;;
    macports) run_privileged port install "$pkg" ;;
    apt) run_privileged apt-get install -y "$pkg" ;;
    dnf) run_privileged dnf install -y "$pkg" ;;
    *) return 1 ;;
  esac
}

pkg_install() {
  local canonical_pkg="$1"
  local command_name="${2:-}"
  local tag
  local installed=false
  local candidate

  tag="$(package_manager_tag)"
  require_package_manager

  if [[ -n "$command_name" ]] && have "$command_name"; then
    remember_skipped "$canonical_pkg (PATH)"
    log "Already available on PATH: $command_name (skipping install for $canonical_pkg)"
    return 0
  fi

  for candidate in $(package_candidates "$canonical_pkg"); do
    if pkg_installed "$candidate"; then
      remember_skipped "$candidate ($tag)"
      log "Already installed: $candidate"
      return 0
    fi

    if pkg_install_candidate "$candidate"; then
      if [[ -n "$command_name" ]]; then
        if have "$command_name" || [[ "$DRY_RUN" == "true" ]]; then
          installed=true
          remember_installed "$candidate ($tag)"
          break
        fi
      else
        installed=true
        remember_installed "$candidate ($tag)"
        break
      fi
    fi

    warn "Failed to install '$candidate' using $(package_manager_label); trying fallback if available."
  done

  if [[ "$installed" != "true" ]]; then
    if [[ "$STRICT_PLATFORM" == "true" ]]; then
      err "Could not install '$canonical_pkg' using $(package_manager_label)."
      exit 1
    fi
    warn "Unable to install '$canonical_pkg'; continuing."
    remember_skipped "$canonical_pkg (unavailable via $tag)"
    return 0
  fi

  if [[ -n "$command_name" ]] && [[ "$DRY_RUN" != "true" ]] && ! have "$command_name"; then
    if [[ "$STRICT_PLATFORM" == "true" ]]; then
      err "$canonical_pkg install did not make '$command_name' available on PATH."
      exit 1
    fi
    warn "$canonical_pkg install did not make '$command_name' available on PATH."
  fi

  return 0
}

prepare_package_manager() {
  require_package_manager
  case "$RESOLVED_PACKAGE_MANAGER" in
    homebrew)
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
      apply_package_manager_path
      run_cmd brew update || warn "brew update returned non-zero."
      if [[ "$UPGRADE_HOMEBREW" == "true" ]]; then
        run_cmd brew upgrade || warn "brew upgrade returned non-zero."
      else
        log "Skipping full Homebrew upgrade (UPGRADE_HOMEBREW=false)."
      fi
      ;;
    macports)
      apply_package_manager_path
      run_privileged port selfupdate || warn "port selfupdate returned non-zero."
      ;;
    apt)
      run_privileged apt-get update || warn "apt-get update returned non-zero."
      ;;
    dnf)
      run_privileged dnf makecache || warn "dnf makecache returned non-zero."
      ;;
  esac
}
