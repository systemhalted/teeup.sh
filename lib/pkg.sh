#!/usr/bin/env bash
# pkg.sh - Homebrew and MacPorts backends behind one candidate-list install
# primitive. Ported from the previous installer's package_manager.sh, macOS
# only; docs/legacy-parity.md says where the rest of it went.
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

# pkg_backend_cmd -> brew | port
# The one command name every backend probe (doctor's "can it answer" gate,
# package-manager/doctor's own prefix checks) means when it says "the
# backend": resolved once here so the two never name a different command for
# the same TEEUP_PKG_BACKEND.
pkg_backend_cmd() {
  _pkg_backend_resolve
  case "$TEEUP_PKG_BACKEND" in
    homebrew) echo brew ;;
    macports) echo port ;;
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
      # HOMEBREW_PREFIX is what brew itself obeys (brew shellenv exports it),
      # so a Homebrew installed anywhere other than the two standard prefixes
      # is found here rather than guessed at from the architecture. Every
      # caller that looks for a file Homebrew installed needs this, not just
      # the one that first noticed.
      if [[ -n "${HOMEBREW_PREFIX:-}" ]]; then
        printf '%s\n' "$HOMEBREW_PREFIX"
      elif [[ "$(arch)" == "arm64" ]]; then echo "/opt/homebrew"; else echo "/usr/local"; fi
      ;;
  esac
}

# macports_apps_dir -> where MacPorts installs .app bundles.
# An aqua port's Portfile (wezterm, emacs-app, ...) moves its built .app into
# applications_dir at destroot time and never touches /Applications, so
# Launchpad and a plain /Applications search never see it there. `port dir
# <name>` prints the *Portfile's* own directory in the ports tree, and
# `port -q variants` lists build variants; neither exposes applications_dir.
# macports-base ships that key active (uncommented) in macports.conf by
# default, so it is read from there rather than assumed; when the file or key
# is missing, the fallback is macports-base's own compiled-in default for the
# same key: /Applications/MacPorts.
macports_apps_dir() {
  local conf dir=""
  conf="$(pkg_prefix)/etc/macports/macports.conf"
  if [[ -r "$conf" ]]; then
    dir="$(awk '$1 == "applications_dir" { print $2; exit }' "$conf")"
  fi
  printf '%s\n' "${dir:-/Applications/MacPorts}"
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
        run_cmd bash -c 'script="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || exit 1; NONINTERACTIVE=1 /bin/bash -c "$script"' || { err "Homebrew installation failed."; return 1; }
        if [[ "$DRY_RUN" != "true" ]] && ! pkg_backend_installed; then
          err "Homebrew installer finished but brew is not at $(pkg_prefix)/bin/brew."
          return 1
        fi
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
    macports:gh) echo "gh" ;;
    # MacPorts' own `docker-compose` port is the retired Python 1.x tool; the
    # docker CLI plugin -- what Compose v2 actually is -- is the
    # docker-compose-plugin port. capabilities/colima/install installs that
    # one there, so it has to be what `pkg_installed` looks for too, or a
    # correctly installed Colima reads as broken. The plugin lives in docker's
    # cli-plugins directory rather than on PATH, so no command fallback can
    # stand in for asking the port system.
    macports:docker-compose) echo "docker-compose-plugin" ;;
    # `tldr` itself is not a MacPorts port; tealdeer is the only candidate,
    # because its binary is named `tldr`, matching the `tldr:tldr`
    # package:command pair cli-tools installs it under. tlrc, the
    # tldr-pages project's own official client, is a real tldr client too
    # and worth installing by hand, but it can't go in this chain: its
    # binary is `tlrc`, not `tldr`, so pkg_install would report success
    # while the `tldr` command still did not exist. If tealdeer fails to
    # install, pkg_install's own warning is the honest outcome.
    macports:tldr) echo "tealdeer" ;;
    *) echo "$pkg" ;;
  esac
}

pkg_installed() {
  local pkg="$1"
  _pkg_backend_resolve
  case "$TEEUP_PKG_BACKEND" in
    homebrew)
      have brew && log "Asking Homebrew whether $pkg is installed..." && \
        brew list --formula "$pkg" >/dev/null 2>&1
      ;;
    macports)
      have port && log "Asking MacPorts whether $pkg is installed..." && \
        port installed "$pkg" 2>/dev/null | grep -q '(active)'
      ;;
  esac
}

_pkg_install_candidate() {
  _pkg_backend_resolve
  case "$TEEUP_PKG_BACKEND" in
    homebrew) run_cmd brew install "$1" ;;
    macports) run_privileged port install "$1" ;;
  esac
}

# _command_version_probe <resolved-path> <command-name>
# Runs the cheapest upstream-documented version invocation for a command.
# Most of package_commands supports --version; keep the exceptions here so
# every caller asks the command the same valid question.
_command_version_probe() {
  local command_path="$1" command_name="$2"
  case "$command_name" in
    colima|docker-compose|git-lfs) exec "$command_path" version ;;
    tmux) exec "$command_path" -V ;;
    *) exec "$command_path" --version ;;
  esac
}

# command_runs <command>
# True only when <command> resolves to a non-teeup shim and its version probe
# exits zero promptly. The watchdog uses only bash jobs, sleep and kill:
# macOS does not ship timeout(1). stdin is closed and all output is discarded
# so a broken or unexpectedly interactive command cannot stall an install.
command_runs() {
  local command_name="$1" command_path probe_pid timer_pid rc=1 monitor_was_enabled=false
  have "$command_name" || return 1
  command_path="$(command -v "$command_name" 2>/dev/null)" || return 1

  case "$-" in *m*) monitor_was_enabled=true ;; esac
  if [[ "$monitor_was_enabled" == "false" ]]; then
    set -m
  fi
  (
    set +m
    trap '' TERM
    (
      trap - TERM
      _command_version_probe "$command_path" "$command_name"
    ) &
    wait "$!"
  ) </dev/null >/dev/null 2>&1 &
  probe_pid=$!
  if [[ "$monitor_was_enabled" == "false" ]]; then
    set +m
  fi
  (
    timer_sleep_pid=""
    stop_timer() {
      if [[ -n "$timer_sleep_pid" ]]; then
        kill "$timer_sleep_pid" >/dev/null 2>&1 || true
        wait "$timer_sleep_pid" 2>/dev/null || true
      fi
      exit 0
    }
    trap stop_timer TERM HUP INT
    sleep "${TEEUP_COMMAND_RUN_TIMEOUT:-2}" &
    timer_sleep_pid=$!
    if wait "$timer_sleep_pid" 2>/dev/null; then
      kill -TERM -- "-$probe_pid" >/dev/null 2>&1 || true
      sleep "${TEEUP_COMMAND_KILL_GRACE:-1}" &
      timer_sleep_pid=$!
      if wait "$timer_sleep_pid" 2>/dev/null; then
        kill -KILL -- "-$probe_pid" >/dev/null 2>&1 || true
      fi
    fi
  ) </dev/null >/dev/null 2>&1 &
  timer_pid=$!

  if wait "$probe_pid" 2>/dev/null; then
    rc=0
  else
    rc=$?
  fi
  kill "$timer_pid" >/dev/null 2>&1 || true
  wait "$timer_pid" 2>/dev/null || true
  return "$rc"
}

# command_mise_tool <command> [resolved-path] [declared-tool]
# Prints the mise tool name when the command is the shim or an installed copy
# under mise's resolved data root. An install's directory name is the repair
# target; it may differ from the executable (neovim/nvim, for example).
command_mise_tool() {
  local command_name="$1" command_path="${2:-}" declared_tool="${3:-$1}" mise_root prefix relative tool
  if [[ -z "$command_path" ]]; then
    command_path="$(command -v "$command_name" 2>/dev/null)" || return 1
  fi
  mise_root="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}"
  case "$command_path" in
    "$mise_root/shims/$command_name") printf '%s\n' "$declared_tool"; return 0 ;;
    "$mise_root"/installs/*)
      case "$command_path" in
        */"$command_name") ;;
        *) return 1 ;;
      esac
      prefix="$mise_root/installs/"
      relative="${command_path#"$prefix"}"
      tool="${relative%%/*}"
      [[ -n "$tool" ]] || return 1
      printf '%s\n' "$tool"
      return 0
      ;;
  esac
  return 1
}

# mise_repair_command <tool> [mise-binary]
# When the broken command is mise itself, an unqualified `mise` would run the
# broken copy again, so callers pass the package manager's binary.
mise_repair_command() {
  local tool="$1" mise_bin="${2:-mise}"
  printf '%s unuse -g %s && %s uninstall %s --all && %s reshim\n' "$mise_bin" "$tool" "$mise_bin" "$tool" "$mise_bin"
}

# _mise_repair_binary <command> -> the mise to run for a repair of <command>.
_mise_repair_binary() {
  if [[ "$1" == "mise" ]]; then
    printf '%s/bin/mise\n' "$(pkg_prefix)"
  else
    printf 'mise\n'
  fi
}

# pkg_install <pkg> [command]
# Skips when <command> is already on PATH and its version probe runs, or any
# candidate is installed.
# Tries each candidate in order; warns and returns 1 when none installs.
pkg_install() {
  _pkg_backend_resolve
  local pkg="$1" command_name="${2:-}" candidate command_path mise_tool
  if [[ -n "$command_name" ]] && have "$command_name"; then
    if command_runs "$command_name"; then
      log "Already available on PATH: $command_name (skipping install for $pkg)"
      return 0
    fi
    command_path="$(command -v "$command_name" 2>/dev/null || true)"
    warn "$command_name resolves to $command_path but does not run; installing $pkg."
    if mise_tool="$(command_mise_tool "$command_name" "$command_path" "$pkg")"; then
      warn "$command_name is managed by mise. Repair it with: $(mise_repair_command "$mise_tool" "$(_mise_repair_binary "$command_name")")"
    fi
  fi
  for candidate in $(package_candidates "$pkg"); do
    if pkg_installed "$candidate"; then
      log "Already installed: $candidate"
      return 0
    fi
    if _pkg_install_candidate "$candidate"; then
      ok_unless_dry "Installed $candidate ($(pkg_backend_label))"
      return 0
    fi
    warn "Failed to install '$candidate' with $(pkg_backend_label); trying the next candidate."
  done
  warn "Unable to install '$pkg' with $(pkg_backend_label)."
  return 1
}

casks_supported() { _pkg_backend_resolve; [[ "$TEEUP_PKG_BACKEND" == "homebrew" ]]; }

cask_installed() {
  have brew && log "Asking Homebrew whether $1 is installed (cask)..." && \
    brew list --cask "$1" >/dev/null 2>&1
}

# cask_apps_already_here <capability> <cask> -> 0 when <cask> is one of the
# capability's casks and every app it declares is already in /Applications
# (or ~/Applications) without Homebrew: downloaded by hand or pushed by IT.
# brew refuses to install over such an app ("It seems there is already an
# App at '/Applications/Emacs.app'"), so teeup uses it as it is. teeup update
# upgrades only what Homebrew installed for teeup, so it leaves the app alone.
cask_apps_already_here() {
  local cap="$1" cask="$2" app found=false
  [[ -n "$cap" ]] || return 1
  case " $(cap_meta_get "$cap" casks) " in
    *" $cask "*) ;;
    *) return 1 ;;
  esac
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    app_installed "$app" || return 1
    found=true
  done <<EOF_APPS
$(cap_apps "$cap")
EOF_APPS
  [[ "$found" == "true" ]]
}

# cask_install <cask>
# On MacPorts machines GUI apps are skipped with a note rather than failing,
# so a capability that is mostly CLI still installs its CLI half.
cask_install() {
  _pkg_backend_resolve
  local cask="$1"
  if ! casks_supported; then
    warn "Casks are not available with MacPorts; install $cask by hand."
    return 0
  fi
  if cask_installed "$cask"; then
    log "Already installed: $cask (cask)"
    return 0
  fi
  if cask_apps_already_here "${TEEUP_CAP:-}" "$cask"; then
    local app
    while IFS= read -r app; do
      log "Using the $app.app that is already installed (not by Homebrew) instead of the $cask cask; teeup update leaves it to you."
    done <<EOF_APPS
$(cap_apps "$TEEUP_CAP")
EOF_APPS
    return 0
  fi
  run_cmd brew install --cask "$cask" && ok_unless_dry "Installed $cask (cask)"
}

# pkg_update -> refresh the package manager's own index (spec section 9).
pkg_update() {
  _pkg_backend_resolve
  case "$TEEUP_PKG_BACKEND" in
    homebrew) run_cmd brew update ;;
    macports) run_privileged port selfupdate ;;
  esac
}

# pkg_collect_installed_items <name>
# Adds whichever of <name>'s packages and casks are installed here to
# TEEUP_COLLECTED_PKGS and TEEUP_COLLECTED_CASKS, under the names the package
# manager knows them by.
pkg_collect_installed_items() {
  local name="$1" pkgs pkg candidate cask
  pkgs="$(cap_meta_get "$name" packages) ${TEEUP_COLLECT_EXTRA:-}"
  for pkg in $pkgs; do
    for candidate in $(package_candidates "$pkg"); do
      if pkg_installed "$candidate" >/dev/null 2>&1; then
        case " $TEEUP_COLLECTED_PKGS " in
          *" $candidate "*) ;;
          *) TEEUP_COLLECTED_PKGS="${TEEUP_COLLECTED_PKGS:+$TEEUP_COLLECTED_PKGS }$candidate" ;;
        esac
        break
      fi
    done
  done
  casks_supported || return 0
  for cask in $(cap_meta_get "$name" casks); do
    if cask_installed "$cask" >/dev/null 2>&1; then
      case " $TEEUP_COLLECTED_CASKS " in
        *" $cask "*) ;;
        *) TEEUP_COLLECTED_CASKS="${TEEUP_COLLECTED_CASKS:+$TEEUP_COLLECTED_CASKS }$cask" ;;
      esac
    fi
  done
}

# pkg_upgrade_all -> upgrade everything teeup installed.
# A failure warns and names the package manager; update carries on.
pkg_upgrade_all() {
  _pkg_backend_resolve
  local rc=0 name
  TEEUP_COLLECTED_PKGS=""
  TEEUP_COLLECTED_CASKS=""

  # reuse uninstall_caps logic
  # teeup's own tools: teeup-runtime installs gum and jq but does not declare
  # them, because a declared package is one `teeup remove` may uninstall and
  # teeup needs these to run. Only the upgrade adds them.
  for name in $(uninstall_caps); do
    if [[ "$name" == "teeup-runtime" ]]; then
      TEEUP_COLLECT_EXTRA="gum jq" pkg_collect_installed_items "$name"
    else
      pkg_collect_installed_items "$name"
    fi
  done

  case "$TEEUP_PKG_BACKEND" in
    homebrew)
      if [[ -n "$TEEUP_COLLECTED_PKGS" ]]; then
        # shellcheck disable=SC2086
        run_cmd brew upgrade --formula $TEEUP_COLLECTED_PKGS || { warn "Could not upgrade formulas: $TEEUP_COLLECTED_PKGS"; rc=1; }
      fi
      if [[ -n "$TEEUP_COLLECTED_CASKS" ]]; then
        # shellcheck disable=SC2086
        run_cmd brew upgrade --cask $TEEUP_COLLECTED_CASKS || { warn "Could not upgrade casks: $TEEUP_COLLECTED_CASKS"; rc=1; }
      fi
      ok_unless_dry "Other Homebrew packages are left to you (run brew upgrade)."
      ;;
    macports)
      if [[ -n "$TEEUP_COLLECTED_PKGS" ]]; then
        # shellcheck disable=SC2086
        run_privileged port upgrade $TEEUP_COLLECTED_PKGS || { warn "Could not upgrade ports: $TEEUP_COLLECTED_PKGS"; rc=1; }
      fi
      ;;
  esac
  return $rc
}

# pkg_upgrade <pkg>
# One formula or port, the candidate list the same way pkg_install reads it.
# A package this machine does not have is a log line, not an install: the
# verb that installs is `teeup install`.
pkg_upgrade() {
  _pkg_backend_resolve
  local pkg="$1" candidate
  for candidate in $(package_candidates "$pkg"); do
    if pkg_installed "$candidate"; then
      case "$TEEUP_PKG_BACKEND" in
        homebrew) run_cmd brew upgrade "$candidate" || { warn "Could not upgrade $candidate."; return 1; } ;;
        macports) run_privileged port upgrade "$candidate" || { warn "Could not upgrade $candidate."; return 1; } ;;
      esac
      return 0
    fi
  done
  log "Not installed here, so nothing to upgrade: $pkg"
  return 0
}

# cask_upgrade <cask>
cask_upgrade() {
  local cask="$1"
  if ! casks_supported; then
    log "Casks are not available with MacPorts; nothing to upgrade for $cask."
    return 0
  fi
  if ! cask_installed "$cask"; then
    log "Not installed here, so nothing to upgrade: $cask (cask)"
    return 0
  fi
  run_cmd brew upgrade --cask "$cask" || { warn "Could not upgrade the $cask cask."; return 1; }
}

# pkg_uninstall <pkg>
# The inverse of pkg_install, for `teeup remove`. Only the candidate this
# machine actually has is uninstalled; a package that is not here is a log
# line, so removing a capability twice is not an error.
pkg_uninstall() {
  _pkg_backend_resolve
  local pkg="$1" candidate
  for candidate in $(package_candidates "$pkg"); do
    if pkg_installed "$candidate"; then
      case "$TEEUP_PKG_BACKEND" in
        homebrew) run_cmd brew uninstall "$candidate" || { warn "Could not uninstall $candidate."; return 1; } ;;
        macports) run_privileged port uninstall "$candidate" || { warn "Could not uninstall $candidate."; return 1; } ;;
      esac
      ok_unless_dry "Uninstalled $candidate ($(pkg_backend_label))"
      return 0
    fi
  done
  log "Not installed here, so nothing to uninstall: $pkg"
  return 0
}

# cask_uninstall <cask>
cask_uninstall() {
  local cask="$1"
  if ! casks_supported; then
    log "Casks are not available with MacPorts; remove $cask by hand if it is on this machine."
    return 0
  fi
  if ! cask_installed "$cask"; then
    log "Not installed here, so nothing to uninstall: $cask (cask)"
    return 0
  fi
  run_cmd brew uninstall --cask "$cask" || { warn "Could not uninstall the $cask cask."; return 1; }
  ok_unless_dry "Uninstalled $cask (cask)"
}
