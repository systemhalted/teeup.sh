#!/usr/bin/env bash
# pkg.sh - Homebrew and MacPorts backends behind one candidate-list install
# primitive. Ported from legacy/lib/package_manager.sh, macOS only.
# Requires core.sh and answers.sh.

run_privileged() {
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

# Resolves once into TEEUP_PKG_BACKEND in the caller's shell, so `die` on an
# invalid answer really exits and the cache survives across calls.
_pkg_backend_resolve() {
  [[ -n "${TEEUP_PKG_BACKEND:-}" ]] && return 0
  local answer major
  answer="$(answers_get TEEUP_PACKAGE_MANAGER)"
  case "$answer" in
    homebrew|macports) TEEUP_PKG_BACKEND="$answer" ;;
    "")
      major="$(macos_major)"
      if [[ "$major" =~ ^[0-9]+$ && "$major" -le 12 ]]; then
        TEEUP_PKG_BACKEND=macports
      else
        TEEUP_PKG_BACKEND=homebrew
      fi
      ;;
    *) die "Unknown TEEUP_PACKAGE_MANAGER '$answer' (expected homebrew or macports)" ;;
  esac
  export TEEUP_PKG_BACKEND
}

# pkg_backend -> homebrew | macports
# Resolution order: TEEUP_PACKAGE_MANAGER (answers or machine file), then
# macOS 12 or older means MacPorts (Homebrew no longer supports them), else
# Homebrew. Cached in TEEUP_PKG_BACKEND for the process.
pkg_backend() {
  _pkg_backend_resolve
  printf '%s\n' "$TEEUP_PKG_BACKEND"
}

pkg_backend_label() {
  _pkg_backend_resolve
  case "$TEEUP_PKG_BACKEND" in
    homebrew) echo "Homebrew" ;;
    macports) echo "MacPorts" ;;
  esac
}

pkg_prefix() {
  # TEEUP_PKG_PREFIX lets tests point at an empty directory instead of the
  # real /opt/homebrew on the CI runner.
  if [[ -n "${TEEUP_PKG_PREFIX:-}" ]]; then
    printf '%s\n' "$TEEUP_PKG_PREFIX"
    return 0
  fi
  _pkg_backend_resolve
  case "$TEEUP_PKG_BACKEND" in
    macports) echo "/opt/local" ;;
    homebrew)
      if [[ "$(arch)" == "arm64" ]]; then echo "/opt/homebrew"; else echo "/usr/local"; fi
      ;;
  esac
}

# Put the backend's bin dirs first on PATH for this process. The shell
# capability handles the persistent version later.
pkg_backend_path() {
  local prefix
  prefix="$(pkg_prefix)"
  case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *) PATH="$prefix/bin:$prefix/sbin:$PATH"; export PATH ;;
  esac
}

pkg_backend_installed() {
  _pkg_backend_resolve
  case "$TEEUP_PKG_BACKEND" in
    homebrew) have brew || [[ -x "$(pkg_prefix)/bin/brew" ]] ;;
    macports) have port || [[ -x "$(pkg_prefix)/bin/port" ]] ;;
  esac
}

# Install Homebrew if missing, or refresh MacPorts. MacPorts itself is never
# auto-installed: its installer is a signed pkg tied to the macOS version.
pkg_backend_prepare() {
  _pkg_backend_resolve
  case "$TEEUP_PKG_BACKEND" in
    homebrew)
      if pkg_backend_installed; then
        ok "Homebrew already installed."
      else
        log "Installing Homebrew..."
        run_cmd bash -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
      fi
      pkg_backend_path
      run_cmd brew update || warn "brew update returned non-zero."
      ;;
    macports)
      if ! pkg_backend_installed; then
        err "MacPorts is not installed. Download the installer for your macOS version from https://www.macports.org/install.php, run it, then re-run bootstrap."
        return 1
      fi
      pkg_backend_path
      run_privileged port selfupdate || warn "port selfupdate returned non-zero."
      ;;
  esac
}

# package_candidates <pkg> -> space-separated names to try in order
package_candidates() {
  local pkg="$1"
  _pkg_backend_resolve
  case "$TEEUP_PKG_BACKEND:$pkg" in
    homebrew:bash-completion) echo "bash-completion@2 bash-completion" ;;
    macports:gnupg) echo "gnupg2 gnupg" ;;
    macports:gh) echo "gh github-cli" ;;
    *) echo "$pkg" ;;
  esac
}

pkg_installed() {
  local pkg="$1"
  _pkg_backend_resolve
  case "$TEEUP_PKG_BACKEND" in
    homebrew) have brew && brew list --formula "$pkg" >/dev/null 2>&1 ;;
    macports) have port && port installed "$pkg" 2>/dev/null | grep -q '(active)' ;;
  esac
}

_pkg_install_candidate() {
  _pkg_backend_resolve
  case "$TEEUP_PKG_BACKEND" in
    homebrew) run_cmd brew install "$1" ;;
    macports) run_privileged port install "$1" ;;
  esac
}

# pkg_install <pkg> [command]
# Skips when <command> is already on PATH or any candidate is installed.
# Tries each candidate in order; warns and returns 1 when none installs.
pkg_install() {
  local pkg="$1" command_name="${2:-}" candidate
  if [[ -n "$command_name" ]] && have "$command_name"; then
    log "Already available on PATH: $command_name (skipping install for $pkg)"
    return 0
  fi
  for candidate in $(package_candidates "$pkg"); do
    if pkg_installed "$candidate"; then
      log "Already installed: $candidate"
      return 0
    fi
    if _pkg_install_candidate "$candidate"; then
      ok "Installed $candidate ($(pkg_backend_label))"
      return 0
    fi
    warn "Failed to install '$candidate' with $(pkg_backend_label); trying the next candidate."
  done
  warn "Unable to install '$pkg' with $(pkg_backend_label)."
  return 1
}

casks_supported() { _pkg_backend_resolve; [[ "$TEEUP_PKG_BACKEND" == "homebrew" ]]; }

cask_installed() { have brew && brew list --cask "$1" >/dev/null 2>&1; }

# cask_install <cask>
# On MacPorts machines GUI apps are skipped with a note rather than failing,
# so a capability that is mostly CLI still installs its CLI half.
cask_install() {
  local cask="$1"
  if ! casks_supported; then
    warn "Casks are not available with MacPorts; install $cask by hand."
    return 0
  fi
  if cask_installed "$cask"; then
    log "Already installed: $cask (cask)"
    return 0
  fi
  run_cmd brew install --cask "$cask" && ok "Installed $cask (cask)"
}
