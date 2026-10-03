#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false
  unset TEEUP_PKG_BACKEND TEEUP_PACKAGE_MANAGER
}

test_backend_defaults_to_homebrew_on_modern_macos() {
  setup
  unset TEEUP_PKG_PREFIX
  assert_equals "homebrew" "$(pkg_backend)" || return 1
  assert_equals "/opt/homebrew" "$(pkg_prefix)" || return 1
  cleanup_test_env
}

test_backend_is_macports_on_macos_12() {
  setup
  unset TEEUP_PKG_PREFIX
  mock_command sw_vers 0 "12.7.1"
  assert_equals "macports" "$(pkg_backend)" || return 1
  assert_equals "/opt/local" "$(pkg_prefix)" || return 1
  cleanup_test_env
}

test_backend_honours_answer() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  assert_equals "macports" "$(pkg_backend)" || return 1
  cleanup_test_env
}

test_invalid_backend_answer_dies() {
  setup
  export TEEUP_PACKAGE_MANAGER=apt
  local rc=0 out
  out="$( (pkg_install ripgrep) 2>&1 )" || rc=$?
  assert_failure "$rc" "invalid backend must fail the caller" || return 1
  assert_contains "$out" "Unknown TEEUP_PACKAGE_MANAGER 'apt'" || return 1
  cleanup_test_env
}

test_intel_homebrew_prefix() {
  setup
  unset TEEUP_PKG_PREFIX
  mock_command_script uname <<'EOF2'
case "$1" in -m) echo x86_64 ;; *) echo Darwin ;; esac
EOF2
  assert_equals "/usr/local" "$(pkg_prefix)" || return 1
  cleanup_test_env
}

test_macports_apps_dir_falls_back_to_the_compiled_in_default() {
  setup
  assert_equals "/Applications/MacPorts" "$(macports_apps_dir)" || return 1
  cleanup_test_env
}

test_macports_apps_dir_reads_macports_conf() {
  setup
  mkdir -p "$TEEUP_PKG_PREFIX/etc/macports"
  printf 'applications_dir\t%s\n' "$TEST_HOME/CustomApps" > "$TEEUP_PKG_PREFIX/etc/macports/macports.conf"
  assert_equals "$TEST_HOME/CustomApps" "$(macports_apps_dir)" || return 1
  cleanup_test_env
}

test_pkg_install_skips_when_command_on_path() {
  setup
  mock_command jq 0 ""
  mock_command brew 0 ""
  local out
  out="$(pkg_install jq jq)"
  assert_contains "$out" "Already available on PATH: jq" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew install" || return 1
  cleanup_test_env
}

test_command_runs_uses_the_supported_version_invocation() {
  setup
  local command_name expected
  for command_name in rg fd fzf bat eza zoxide jq yq btop tree wget curl gpg tldr dust delta lazygit mise starship nvim docker ollama herdr zsh; do
    mock_command_script "$command_name" <<'EOF2'
[[ "${1:-}" == "--version" ]]
EOF2
    command_runs "$command_name" || { echo "$command_name did not accept --version"; return 1; }
  done
  for expected in "colima:version" "docker-compose:version" "git-lfs:version" "tmux:-V"; do
    command_name="${expected%%:*}"
    expected="${expected#*:}"
    mock_command_script "$command_name" <<EOF2
[[ "\${1:-}" == "$expected" ]]
EOF2
    command_runs "$command_name" || { echo "$command_name did not receive $expected"; return 1; }
  done
  cleanup_test_env
}

test_command_runs_stops_its_watchdog_when_probe_finishes() {
  setup
  mock_command jq 0 ""
  mock_command_script sleep <<'EOF2'
printf '%s\n' "$$" > "$TEST_HOME/watchdog-sleep-pid"
exec /bin/sleep 1
EOF2
  command_runs jq || return 1
  local sleep_pid
  sleep_pid="$(cat "$TEST_HOME/watchdog-sleep-pid")"
  if kill -0 "$sleep_pid" 2>/dev/null; then
    echo "command_runs left watchdog sleep PID $sleep_pid running"
    return 1
  fi
  cleanup_test_env
}

test_command_runs_kills_a_probe_tree_that_ignores_term() {
  setup
  mock_command_script jq <<'EOF2'
trap '' TERM
sleep 4 &
child_pid=$!
printf '%s\n' "$child_pid" > "$TEST_HOME/probe-child-pid"
wait "$child_pid"
EOF2
  local elapsed child_pid
  SECONDS=0
  TEEUP_COMMAND_RUN_TIMEOUT=0.1 TEEUP_COMMAND_KILL_GRACE=0.1 command_runs jq && {
    echo "a probe killed after its deadline must not succeed"
    return 1
  }
  elapsed=$SECONDS
  child_pid="$(cat "$TEST_HOME/probe-child-pid")"
  if (( elapsed >= 3 )); then
    echo "command_runs took ${elapsed}s to stop a probe that ignored TERM"
    return 1
  fi
  if kill -0 "$child_pid" 2>/dev/null; then
    echo "command_runs left probe child PID $child_pid running"
    ps -o pid=,ppid=,pgid=,stat=,command= -p "$child_pid" 2>/dev/null || true
    return 1
  fi
  cleanup_test_env
}

test_pkg_install_installs_when_the_command_on_path_does_not_run() {
  setup
  mock_command jq 1 "mise ERROR No version is set for shim: jq"
  mock_command_script brew <<'EOF2'
case "$1" in
  list) exit 1 ;;
  install) exit 0 ;;
esac
EOF2
  local out
  out="$(pkg_install jq jq 2>&1)"
  assert_contains "$out" "jq resolves to $MOCK_BIN/jq but does not run" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew install jq" || return 1
  cleanup_test_env
}

test_pkg_install_names_the_declared_mise_tool_for_an_aliased_shim() {
  setup
  export MISE_DATA_DIR="$TEST_HOME/mise data"
  local shim="$MISE_DATA_DIR/shims/nvim"
  mkdir -p "${shim%/*}"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$shim"
  chmod +x "$shim"
  PATH="${shim%/*}:$PATH"
  mock_command_script brew <<'EOF2'
case "$1 ${2:-} ${3:-}" in
  "list --formula neovim") exit 0 ;;
  *) exit 1 ;;
esac
EOF2
  local out
  out="$(pkg_install neovim nvim 2>&1)"
  assert_contains "$out" "mise unuse -g neovim && mise uninstall neovim --all && mise reshim" || return 1
  assert_not_contains "$out" "mise unuse -g nvim" "the executable name is not the mise tool name" || return 1
  cleanup_test_env
}

test_pkg_install_installs_when_the_command_on_path_hangs() {
  setup
  mock_command_script jq <<'EOF2'
while :; do sleep 1; done
EOF2
  mock_command_script brew <<'EOF2'
case "$1" in
  list) exit 1 ;;
  install) exit 0 ;;
esac
EOF2
  local out
  out="$(TEEUP_COMMAND_RUN_TIMEOUT=0.1 pkg_install jq jq 2>&1)"
  assert_contains "$out" "jq resolves to $MOCK_BIN/jq but does not run" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew install jq" || return 1
  cleanup_test_env
}

test_pkg_install_calls_brew_when_missing() {
  setup
  mock_command_script brew <<'EOF2'
case "$1" in
  list) exit 1 ;;
  install) exit 0 ;;
esac
EOF2
  DRY_RUN=true
  local out
  out="$(pkg_install ripgrep)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install ripgrep" || return 1
  # F1: a dry run must never claim the package was installed.
  assert_not_contains "$out" "Installed ripgrep" "dry run must not claim an install that did not happen" || return 1
  cleanup_test_env
}

test_pkg_install_real_run_wording_is_unchanged() {
  setup
  mock_command_script brew <<'EOF2'
case "$1" in
  list) exit 1 ;;
  install) exit 0 ;;
esac
EOF2
  DRY_RUN=false
  local out
  out="$(pkg_install ripgrep)"
  assert_contains "$out" "✅ Installed ripgrep (Homebrew)" "the real-run wording must stay exactly what it is today" || return 1
  cleanup_test_env
}

test_pkg_install_uses_sudo_port_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  DRY_RUN=true
  local out
  out="$(pkg_install ripgrep)"
  assert_contains "$out" "[DRY-RUN] Would execute: sudo port install ripgrep" || return 1
  cleanup_test_env
}

test_candidates_map_bash_completion_on_homebrew() {
  setup
  assert_equals "bash-completion@2 bash-completion" "$(package_candidates bash-completion)" || return 1
  cleanup_test_env
}

# `tldr` itself is not a MacPorts port; tealdeer is the only candidate,
# because its binary is named `tldr`, which is what cli-tools's tldr:tldr
# package:command pair checks for on PATH. tlrc is deliberately not a
# fallback here: see test_pkg_install_does_not_claim_success_on_a_failed_
# tealdeer below for why.
test_candidates_map_tldr_to_tealdeer_only_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  assert_equals "tealdeer" "$(package_candidates tldr)" || return 1
  cleanup_test_env
}

# `github-cli` is not a real MacPorts port (only `gh` is); the mapping must
# not offer it as a fallback.
test_candidates_map_gh_to_just_gh_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  assert_equals "gh" "$(package_candidates gh)" || return 1
  cleanup_test_env
}

# tlrc's binary is `tlrc`, not `tldr`, so it can never satisfy the
# `tldr:tldr` package:command pair cli-tools installs it under: adding it as
# a fallback would let a failed tealdeer install still report success while
# leaving the user without a `tldr` command, and the next run would find
# tlrc already installed and stay silent about the gap forever. A failed
# tealdeer must surface pkg_install's honest "unable to install" warning
# instead.
test_pkg_install_does_not_claim_success_on_a_failed_tealdeer() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  export TEEUP_TEST_MISSING=tldr
  mock_command port 0 ""
  mock_command_script sudo <<'EOF2'
case "$1 $2 ${3:-}" in
  "port install tealdeer") exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  DRY_RUN=false
  local rc=0 out
  out="$(pkg_install tldr tldr 2>&1)" || rc=$?
  assert_failure "$rc" "a failed tealdeer must not be reported as a successful install" || return 1
  assert_contains "$out" "Failed to install 'tealdeer' with MacPorts; trying the next candidate." || return 1
  assert_contains "$out" "Unable to install 'tldr' with MacPorts." || return 1
  assert_not_contains "$out" "Installed" "nothing was actually installed" || return 1
  cleanup_test_env
}

test_pkg_installed_announces_the_backend_it_asks() {
  setup
  mock_command brew 0 ""
  local out
  out="$(pkg_installed ripgrep)"
  assert_contains "$out" "Asking Homebrew whether ripgrep is installed" || return 1
  cleanup_test_env
}

test_pkg_installed_announces_macports_too() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(pkg_installed ripgrep)"
  assert_contains "$out" "Asking MacPorts whether ripgrep is installed" || return 1
  cleanup_test_env
}

test_pkg_install_have_short_circuit_does_not_announce() {
  setup
  mock_command jq 0 ""
  mock_command brew 0 ""
  local out
  out="$(pkg_install jq jq)"
  assert_contains "$out" "Already available on PATH: jq" || return 1
  assert_not_contains "$out" "Asking" "nothing blocks on the have short-circuit, so there is nothing to announce" || return 1
  cleanup_test_env
}

test_backend_announcement_reads_the_same_under_dry_run() {
  setup
  mock_command brew 0 ""
  local dry_out real_out
  DRY_RUN=true
  dry_out="$(pkg_installed ripgrep)"
  DRY_RUN=false
  real_out="$(pkg_installed ripgrep)"
  assert_contains "$dry_out" "Asking Homebrew whether ripgrep is installed" || return 1
  assert_equals "$real_out" "$dry_out" "the announcement is a plain log line, not routed through ok_unless_dry" || return 1
  cleanup_test_env
}

test_cask_installed_announces_the_backend_it_asks() {
  setup
  mock_command brew 0 ""
  local out
  out="$(cask_installed wezterm)"
  assert_contains "$out" "Asking Homebrew whether wezterm is installed (cask)" || return 1
  cleanup_test_env
}

test_cask_install_skipped_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  local out
  out="$(cask_install wezterm 2>&1)"
  assert_contains "$out" "Casks are not available with MacPorts" || return 1
  cleanup_test_env
}

test_cask_install_dry_run() {
  setup
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; esac
EOF2
  DRY_RUN=true
  local out
  out="$(cask_install wezterm)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask wezterm" || return 1
  # F1: a dry run must never claim the cask was installed.
  assert_not_contains "$out" "Installed wezterm" "dry run must not claim an install that did not happen" || return 1
  cleanup_test_env
}

test_backend_prepare_installs_homebrew_when_missing() {
  setup
  DRY_RUN=true
  local out
  out="$(pkg_backend_prepare)"
  assert_contains "$out" "Homebrew/install/HEAD/install.sh" || return 1
  cleanup_test_env
}

test_backend_prepare_fails_when_installer_fails() {
  setup
  export TEEUP_TEST_MISSING=brew
  mock_command curl 1 ""
  DRY_RUN=false
  local rc=0 out
  out="$(pkg_backend_prepare 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Homebrew installation failed" || return 1
  cleanup_test_env
}

test_run_privileged_prefixes_sudo() {
  setup
  # shellcheck disable=SC2034
  DRY_RUN=true
  assert_contains "$(run_privileged port selfupdate)" "sudo port selfupdate" || return 1
  cleanup_test_env
}

test_cask_install_dies_on_invalid_backend() {
  setup
  export TEEUP_PACKAGE_MANAGER=apt
  local rc=0 out
  out="$( (cask_install wezterm) 2>&1 )" || rc=$?
  assert_failure "$rc" "invalid backend must fail the caller" || return 1
  assert_contains "$out" "Unknown TEEUP_PACKAGE_MANAGER 'apt'" || return 1
  cleanup_test_env
}

test_uninstall_removes_only_what_is_installed() {
  setup
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1 $2" in
  "list --formula") [ "$3" = "ripgrep" ] && exit 0 || exit 1 ;;
  "list --cask") [ "$3" = "wezterm" ] && exit 0 || exit 1 ;;
esac
exit 0
EOF2
  mock_command port 0 ""
  mock_command sudo 0 ""
  export TEEUP_PACKAGE_MANAGER=homebrew
  unset TEEUP_PKG_BACKEND
  local out
  out="$(pkg_uninstall ripgrep; pkg_uninstall nowhere; cask_uninstall wezterm; cask_uninstall absent)"
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall ripgrep" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew uninstall nowhere" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew uninstall --cask wezterm" || return 1
  assert_contains "$out" "Not installed here, so nothing to uninstall: nowhere" || return 1
  assert_contains "$out" "Not installed here, so nothing to uninstall: absent (cask)" || return 1
  : > "$MOCK_LOG"
  out="$(DRY_RUN=true cask_uninstall wezterm; DRY_RUN=true pkg_uninstall ripgrep)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew uninstall --cask wezterm" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: brew uninstall ripgrep" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew uninstall" "a dry run uninstalls nothing" || return 1
  export TEEUP_PACKAGE_MANAGER=macports
  unset TEEUP_PKG_BACKEND
  out="$(cask_uninstall wezterm)"
  assert_contains "$out" "Casks are not available with MacPorts" || return 1
  cleanup_test_env
}

# teeup-runtime installs gum and jq without declaring them (declaring would let
# `teeup remove` uninstall teeup's own tools); the upgrade still covers them,
# and uninstall's package list does not gain them.
test_upgrade_all_includes_teeups_own_tools() {
  setup
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1 $2" in
  "list --formula") [[ "$3" == "gum" || "$3" == "jq" ]] && exit 0 || exit 1 ;;
  "list --cask") exit 1 ;;
esac
exit 0
EOF2
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR/teeup-runtime"
  printf 'provides=""\n' > "$TEEUP_CAPS_DIR/teeup-runtime/capability"
  state_done mark cap-teeup-runtime
  export TEEUP_PACKAGE_MANAGER=homebrew
  unset TEEUP_PKG_BACKEND
  pkg_upgrade_all
  assert_contains "$(cat "$MOCK_LOG")" "brew upgrade --formula gum jq" || return 1
  TEEUP_COLLECTED_PKGS=""
  pkg_collect_installed_items teeup-runtime
  assert_equals "" "$TEEUP_COLLECTED_PKGS" "uninstall's collector must not list teeup's own tools" || return 1
  cleanup_test_env
}

test_update_and_upgrade_all_on_both_backends() {
  setup
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1 $2" in
  "list --formula") [[ "$3" == "ripgrep" || "$3" == "fzf" ]] && exit 0 || exit 1 ;;
  "list --cask") [ "$3" = "wezterm" ] && exit 0 || exit 1 ;;
esac
exit 0
EOF2
  mock_command_script port <<'EOF2'
echo "port $*" >> "$MOCK_LOG"
case "$1 $2" in
  "installed ripgrep") echo "  ripgrep @1.0 (active)"; exit 0 ;;
  "installed fzf") echo "  fzf @1.0 (active)"; exit 0 ;;
esac
exit 0
EOF2
  mock_command sudo 0 ""
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR/fakecap"
  printf 'packages="ripgrep fzf"\ncasks="wezterm"\n' > "$TEEUP_CAPS_DIR/fakecap/capability"
  state_done mark cap-fakecap

  export TEEUP_PACKAGE_MANAGER=homebrew
  unset TEEUP_PKG_BACKEND
  pkg_update
  pkg_upgrade_all
  assert_contains "$(cat "$MOCK_LOG")" "brew update" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew upgrade --formula ripgrep fzf" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew upgrade --cask wezterm" || return 1
  : > "$MOCK_LOG"
  export TEEUP_PACKAGE_MANAGER=macports
  unset TEEUP_PKG_BACKEND
  pkg_update
  pkg_upgrade_all
  assert_contains "$(cat "$MOCK_LOG")" "sudo port selfupdate" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "sudo port upgrade ripgrep fzf" || return 1
  cleanup_test_env
}

test_upgrade_one_package_or_cask_only_when_it_is_installed() {
  setup
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1 $2" in
  "list --formula") [ "$3" = "ripgrep" ] && exit 0 || exit 1 ;;
  "list --cask") [ "$3" = "wezterm" ] && exit 0 || exit 1 ;;
esac
exit 0
EOF2
  export TEEUP_PACKAGE_MANAGER=homebrew
  unset TEEUP_PKG_BACKEND
  local out
  out="$(pkg_upgrade ripgrep; pkg_upgrade nowhere; cask_upgrade wezterm; cask_upgrade absent)"
  assert_contains "$(cat "$MOCK_LOG")" "brew upgrade ripgrep" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew upgrade nowhere" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew upgrade --cask wezterm" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew upgrade --cask absent" || return 1
  assert_contains "$out" "Not installed here, so nothing to upgrade: nowhere" || return 1
  assert_contains "$out" "Not installed here, so nothing to upgrade: absent (cask)" || return 1
  cleanup_test_env
}

test_cask_upgrade_is_a_note_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  unset TEEUP_PKG_BACKEND
  local out rc=0
  out="$(cask_upgrade wezterm)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "Casks are not available with MacPorts" || return 1
  cleanup_test_env
}

test_upgrade_failures_are_reported() {
  setup
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1 $2" in
  "list --formula") exit 0 ;;
esac
exit 1
EOF2
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR/fakecap"
  printf 'packages="ripgrep"\n' > "$TEEUP_CAPS_DIR/fakecap/capability"
  state_done mark cap-fakecap

  export TEEUP_PACKAGE_MANAGER=homebrew
  unset TEEUP_PKG_BACKEND
  local rc=0 out
  out="$(pkg_upgrade ripgrep 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Could not upgrade ripgrep." || return 1
  rc=0
  out="$(pkg_upgrade_all 2>&1)" || rc=$?
  assert_failure "$rc" "a failed upgrade is reported to the caller" || return 1
  assert_contains "$out" "Could not upgrade formulas: ripgrep" || return 1
  cleanup_test_env
}

test_update_and_upgrade_dry_run_change_nothing() {
  setup
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1 $2" in
  "list --formula") [[ "$3" == "ripgrep" ]] && exit 0 || exit 1 ;;
  "list --cask") [[ "$3" == "wezterm" ]] && exit 0 || exit 1 ;;
esac
exit 0
EOF2
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR/fakecap"
  printf 'packages="ripgrep"\ncasks="wezterm"\n' > "$TEEUP_CAPS_DIR/fakecap/capability"
  state_done mark cap-fakecap

  export TEEUP_PACKAGE_MANAGER=homebrew
  unset TEEUP_PKG_BACKEND
  local out
  out="$(DRY_RUN=true pkg_update; DRY_RUN=true pkg_upgrade_all)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew update" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: brew upgrade --formula ripgrep" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: brew upgrade --cask wezterm" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew update" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew upgrade" || return 1
  cleanup_test_env
}

echo "lib/pkg.sh"
# 2026-09-29, a work Mac: `brew install --cask emacs-app` failed with "It
# seems there is already an App at '/Applications/Emacs.app'". An app that is
# already there, however it got there, is used as it is.
test_cask_install_uses_an_app_installed_another_way() {
  setup
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1" in list) exit 1 ;; esac
EOF2
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  mkdir -p "$TEEUP_APPS_DIR/WezTerm.app"
  local out
  out="$(TEEUP_CAP=wezterm cask_install wezterm 2>&1)"
  assert_not_contains "$(cat "$MOCK_LOG")" "install --cask" "brew was asked to install over the app" || return 1
  assert_contains "$out" "Using the WezTerm.app that is already installed (not by Homebrew)" || return 1
  cleanup_test_env
}

test_cask_install_installs_when_the_app_is_missing() {
  setup
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1" in list) exit 1 ;; esac
EOF2
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  mkdir -p "$TEEUP_APPS_DIR"
  TEEUP_CAP=wezterm cask_install wezterm >/dev/null 2>&1 || true
  assert_contains "$(cat "$MOCK_LOG")" "brew install --cask wezterm" || return 1
  cleanup_test_env
}

# Outside a capability there are no apps to go by, so the cask installs.
test_cask_install_outside_a_capability_still_installs() {
  setup
  mock_command_script brew <<'EOF2'
echo "brew $*" >> "$MOCK_LOG"
case "$1" in list) exit 1 ;; esac
EOF2
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  mkdir -p "$TEEUP_APPS_DIR/WezTerm.app"
  unset TEEUP_CAP
  cask_install wezterm >/dev/null 2>&1 || true
  assert_contains "$(cat "$MOCK_LOG")" "brew install --cask wezterm" || return 1
  cleanup_test_env
}

run_test "backend defaults to homebrew on modern macOS" test_backend_defaults_to_homebrew_on_modern_macos
run_test "backend is macports on macOS 12" test_backend_is_macports_on_macos_12
run_test "backend honours answer" test_backend_honours_answer
run_test "invalid backend answer dies" test_invalid_backend_answer_dies
run_test "intel homebrew prefix" test_intel_homebrew_prefix
run_test "macports_apps_dir falls back to the compiled-in default" test_macports_apps_dir_falls_back_to_the_compiled_in_default
run_test "macports_apps_dir reads macports.conf" test_macports_apps_dir_reads_macports_conf
run_test "pkg_install skips when command on PATH" test_pkg_install_skips_when_command_on_path
run_test "command_runs uses supported version invocations" test_command_runs_uses_the_supported_version_invocation
run_test "command_runs stops its watchdog when the probe finishes" test_command_runs_stops_its_watchdog_when_probe_finishes
run_test "command_runs kills a probe tree that ignores TERM" test_command_runs_kills_a_probe_tree_that_ignores_term
run_test "pkg_install installs when command on PATH does not run" test_pkg_install_installs_when_the_command_on_path_does_not_run
run_test "pkg_install names the declared mise tool for an aliased shim" test_pkg_install_names_the_declared_mise_tool_for_an_aliased_shim
run_test "pkg_install installs when command on PATH hangs" test_pkg_install_installs_when_the_command_on_path_hangs
run_test "pkg_install calls brew when missing" test_pkg_install_calls_brew_when_missing
run_test "pkg_install real-run wording is unchanged" test_pkg_install_real_run_wording_is_unchanged
run_test "pkg_install uses sudo port on macports" test_pkg_install_uses_sudo_port_on_macports
run_test "candidates map bash-completion" test_candidates_map_bash_completion_on_homebrew
run_test "candidates map tldr to tealdeer only on macports" test_candidates_map_tldr_to_tealdeer_only_on_macports
run_test "candidates map gh to just gh on macports" test_candidates_map_gh_to_just_gh_on_macports
run_test "pkg_install does not claim success on a failed tealdeer" test_pkg_install_does_not_claim_success_on_a_failed_tealdeer
run_test "pkg_installed announces the backend it asks" test_pkg_installed_announces_the_backend_it_asks
run_test "pkg_installed announces macports too" test_pkg_installed_announces_macports_too
run_test "pkg_install have short-circuit does not announce" test_pkg_install_have_short_circuit_does_not_announce
run_test "backend announcement reads the same under dry run" test_backend_announcement_reads_the_same_under_dry_run
run_test "cask_installed announces the backend it asks" test_cask_installed_announces_the_backend_it_asks
run_test "cask_install skipped on macports" test_cask_install_skipped_on_macports
run_test "cask_install dry run" test_cask_install_dry_run
run_test "backend prepare installs homebrew" test_backend_prepare_installs_homebrew_when_missing
run_test "backend prepare fails when installer fails" test_backend_prepare_fails_when_installer_fails
run_test "run_privileged prefixes sudo" test_run_privileged_prefixes_sudo
run_test "cask_install dies on invalid backend" test_cask_install_dies_on_invalid_backend
run_test "uninstall removes only what is installed" test_uninstall_removes_only_what_is_installed
run_test "update and upgrade_all on both backends" test_update_and_upgrade_all_on_both_backends
run_test "upgrade_all includes teeup's own tools" test_upgrade_all_includes_teeups_own_tools
run_test "upgrade one package or cask only when it is installed" test_upgrade_one_package_or_cask_only_when_it_is_installed
run_test "cask_upgrade is a note on MacPorts" test_cask_upgrade_is_a_note_on_macports
run_test "upgrade failures are reported" test_upgrade_failures_are_reported
run_test "update and upgrade dry run change nothing" test_update_and_upgrade_dry_run_change_nothing
run_test "cask install uses an app installed another way" test_cask_install_uses_an_app_installed_another_way
run_test "cask install installs when the app is missing" test_cask_install_installs_when_the_app_is_missing
run_test "cask install outside a capability still installs" test_cask_install_outside_a_capability_still_installs
print_summary
