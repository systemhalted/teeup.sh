#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# A real Emacs for the Elisp checks, resolved before setup_test_env narrows
# PATH (and before mock_macos_base replaces uname). The Elisp is
# platform-independent, so one runner is the gate: CI installs emacs-nox on
# the Linux runner, where a missing emacs fails these checks. Anywhere else
# (the macOS runners, a laptop without Emacs) they print a note and pass.
EMACS_REAL="$(command -v emacs || true)"
# python3's plistlib parses the rendered LaunchAgent the way launchd would
# read its XML. Every CI runner image has python3; resolved here for the same
# PATH reason as emacs.
PYTHON3="$(command -v python3 || true)"
EMACS_REQUIRED=false
if [[ "${CI:-}" == "true" && "$(uname -s)" == "Linux" ]]; then EMACS_REQUIRED=true; fi

# no_real_emacs: true (after a note or a failure message) when the Elisp
# checks cannot run; its exit status is what the caller returns.
no_real_emacs() {
  if [[ -n "$EMACS_REAL" ]]; then return 1; fi
  if [[ "$EMACS_REQUIRED" == "true" ]]; then
    echo "emacs is not installed on the Linux CI runner; the workflow's emacs-nox step should have installed it"
    NO_EMACS_RC=1
  else
    echo "note: no emacs on this machine; skipping the Elisp check (CI's Linux runner runs it)."
    NO_EMACS_RC=0
  fi
  return 0
}

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  mock_command_script launchctl <<'EOF2'
case "$1" in print) [ -f "$HOME/agent-loaded" ] ;; *) exit 0 ;; esac
EOF2
  mock_command git 0 ""
  # The emacs on the fake Mac: what `command -v emacs` resolves in the plist.
  mock_command emacs 0 ""
  # `emacsclient -e t` answers only when a daemon marker exists.
  mock_command_script emacsclient <<'EOF2'
[ -f "$HOME/daemon-up" ] || exit 1
exit 0
EOF2
  mock_command_script defaults <<'EOF2'
case "$1" in
  read) exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  TEEUP="$TEEUP_PATH/bin/teeup"
  EMACS_DIR="$TEST_HOME/.config/emacs"
  PLIST="$TEST_HOME/Library/LaunchAgents/sh.teeup.emacs.plist"
}

set_flavor() {
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_EMACS_FLAVOR="%s"\n' "$1" > "$TEST_HOME/.config/teeup/answers"
}

test_install_dry_run_gets_the_cask() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install emacs)"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask emacs-app" || return 1
  cleanup_test_env
}

test_install_falls_back_to_the_port_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  export TEEUP_TEST_MISSING="emacs"
  mock_command port 1 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install emacs 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: sudo port install emacs" || return 1
  assert_not_contains "$out" "brew install --cask" || return 1
  cleanup_test_env
}

test_install_warns_when_the_formula_is_already_installed() {
  setup
  # Homebrew reports the emacs formula installed; cask_installed (a
  # different `brew list` call) must stay false so cask_install still runs.
  mock_command_script brew <<'EOF2'
case "$1 $2 $3" in
  "list --formula emacs") exit 0 ;;
  list*) exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  local out
  out="$(DRY_RUN=true "$TEEUP" install emacs 2>&1)"
  assert_contains "$out" "Homebrew's emacs formula is installed" || return 1
  assert_contains "$out" "brew uninstall emacs" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask emacs-app" || return 1
  cleanup_test_env
}

test_configure_prefers_the_app_bundle_over_a_path_emacs() {
  setup
  # Simulates I2 on hardware: the emacs-app cask is installed (its bundle
  # exists) but Homebrew's emacs formula still owns the PATH `emacs`
  # (`mock_command emacs` in setup stands in for it). configure must use the
  # bundle's own binary for the daemon, not the formula's.
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  mkdir -p "$TEEUP_APPS_DIR/Emacs.app/Contents/MacOS"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEEUP_APPS_DIR/Emacs.app/Contents/MacOS/Emacs"
  chmod +x "$TEEUP_APPS_DIR/Emacs.app/Contents/MacOS/Emacs"
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  local plist_body
  plist_body="$(cat "$PLIST")"
  assert_contains "$plist_body" "<string>$TEEUP_APPS_DIR/Emacs.app/Contents/MacOS/Emacs</string>" || return 1
  assert_not_contains "$plist_body" "<string>$MOCK_BIN/emacs</string>" "the formula's PATH emacs must not win" || return 1
  cleanup_test_env
}

test_configure_starter_installs_the_config_and_the_daemon_agent() {
  setup
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  assert_file_exists "$EMACS_DIR/init.el" || return 1
  assert_file_exists "$EMACS_DIR/local.el" || return 1
  assert_contains "$(cat "$EMACS_DIR/init.el")" "capabilities/emacs/default/teeup/init.el" || return 1
  assert_file_exists "$PLIST" || return 1
  local plist_body
  plist_body="$(cat "$PLIST")"
  assert_contains "$plist_body" "<string>$MOCK_BIN/emacs</string>" || return 1
  assert_contains "$plist_body" "<string>--fg-daemon</string>" || return 1
  assert_contains "$plist_body" "<key>TEEUP_PATH</key>" || return 1
  assert_contains "$plist_body" "<string>$TEEUP_PATH</string>" || return 1
  assert_contains "$plist_body" "<key>XDG_CONFIG_HOME</key>" || return 1
  assert_contains "$plist_body" "<string>$TEST_HOME/.config</string>" || return 1
  assert_contains "$plist_body" "<key>SuccessfulExit</key>" "only a crash restarts the daemon" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "launchctl bootstrap gui/501 $PLIST" || return 1
  cleanup_test_env
}

test_configure_is_idempotent_and_leaves_a_loaded_daemon_alone() {
  setup
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  # launchd reports the agent loaded from now on.
  : > "$TEST_HOME/agent-loaded"
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs)"
  assert_contains "$out" "Already installed: $EMACS_DIR/init.el" || return 1
  assert_contains "$out" "Emacs daemon agent already loaded" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "launchctl bootout" "a loaded daemon is not restarted" || return 1
  cleanup_test_env
}

test_configure_reloads_when_the_plist_changed() {
  setup
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  : > "$TEST_HOME/agent-loaded"
  printf 'stale\n' > "$PLIST"
  : > "$MOCK_LOG"
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "launchctl bootstrap gui/501 $PLIST" || return 1
  assert_contains "$(cat "$PLIST")" "<string>--fg-daemon</string>" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" configure emacs)"
  assert_contains "$out" "[DRY-RUN] Would install $EMACS_DIR/init.el" || return 1
  assert_contains "$out" "[DRY-RUN] Would write $PLIST" || return 1
  [[ ! -e "$EMACS_DIR" ]] || { echo "config written in dry run"; return 1; }
  [[ ! -e "$PLIST" ]] || { echo "plist written in dry run"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "launchctl" || return 1
  cleanup_test_env
}

test_configure_without_emacs_skips_the_agent() {
  setup
  export TEEUP_TEST_MISSING="emacs"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs)"
  assert_contains "$out" "emacs is not on PATH yet" || return 1
  assert_file_exists "$EMACS_DIR/init.el" "the config is still installed" || return 1
  [[ ! -e "$PLIST" ]] || { echo "plist written without an emacs to run"; return 1; }
  cleanup_test_env
}

test_flavor_doom_clones_and_installs() {
  setup
  set_flavor doom
  local out
  out="$(DRY_RUN=true "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: git clone --depth 1 https://github.com/doomemacs/core $EMACS_DIR" || return 1
  assert_contains "$out" "[DRY-RUN] Would execute: $EMACS_DIR/bin/doom install --no-env" || return 1
  assert_not_contains "$out" "Would install $EMACS_DIR/init.el" "the starter is not installed for doom" || return 1
  cleanup_test_env
}

test_flavor_doom_skips_an_existing_checkout_and_config() {
  setup
  set_flavor doom
  mkdir -p "$EMACS_DIR/bin" "$TEST_HOME/.config/doom"
  printf '#!/bin/sh\n' > "$EMACS_DIR/bin/doom"
  chmod +x "$EMACS_DIR/bin/doom"
  printf ';; mine\n' > "$TEST_HOME/.config/doom/init.el"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "Already a Doom checkout: $EMACS_DIR" || return 1
  assert_contains "$out" "Doom is set up ($TEST_HOME/.config/doom)" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "git clone" || return 1
  cleanup_test_env
}

test_switching_starter_to_doom_backs_up_the_starter() {
  setup
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  set_flavor doom
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "$EMACS_DIR is not a Doom checkout; moving it aside." || return 1
  ls -d "$EMACS_DIR.teeup_backup_"* >/dev/null 2>&1 || { echo "no backup of the starter"; return 1; }
  assert_contains "$(cat "$MOCK_LOG")" "git clone --depth 1 https://github.com/doomemacs/core $EMACS_DIR" || return 1
  cleanup_test_env
}

test_flavor_spacemacs_clones_into_emacs_d() {
  setup
  set_flavor spacemacs
  local out
  out="$(DRY_RUN=true "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: git clone https://github.com/syl20bnr/spacemacs $TEST_HOME/.emacs.d" || return 1
  cleanup_test_env
}

test_flavor_none_touches_no_config() {
  setup
  set_flavor none
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "TEEUP_EMACS_FLAVOR=none: leaving your Emacs configuration alone." || return 1
  [[ ! -e "$EMACS_DIR" ]] || { echo "config written for flavor none"; return 1; }
  assert_file_exists "$PLIST" "the daemon agent is flavor-independent" || return 1
  cleanup_test_env
}

test_the_machine_file_wins_over_the_answer() {
  setup
  set_flavor doom
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEEUP_MACHINES_DIR"
  printf 'TEEUP_EMACS_FLAVOR="none"\n' > "$TEEUP_MACHINES_DIR/testmac.conf"
  local out
  out="$(DRY_RUN=true "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "TEEUP_EMACS_FLAVOR=none: leaving your Emacs configuration alone." || return 1
  assert_not_contains "$out" "git clone" "the answers file's doom lost to the machine file" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_unknown_flavor_warns_and_uses_the_starter() {
  setup
  set_flavor vanilla
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "Unknown TEEUP_EMACS_FLAVOR 'vanilla'" || return 1
  assert_file_exists "$EMACS_DIR/init.el" || return 1
  cleanup_test_env
}

test_a_legacy_emacs_d_is_reported_not_moved() {
  setup
  mkdir -p "$TEST_HOME/.emacs.d"
  printf ';; old\n' > "$TEST_HOME/.emacs.d/init.el"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "$TEST_HOME/.emacs.d exists and Emacs reads it instead of $EMACS_DIR/init.el" || return 1
  assert_equals ";; old" "$(cat "$TEST_HOME/.emacs.d/init.el")" || return 1
  cleanup_test_env
}

test_plist_escapes_metacharacters_in_paths() {
  setup
  # A state dir and a TMPDIR with a space and an ampersand: the plist must
  # stay valid XML.
  export TEEUP_STATE_DIR="$TEST_HOME/st ate&more"
  export TMPDIR="$TEST_HOME/t mp&<T>"
  mkdir -p "$TMPDIR"
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  local plist_body
  plist_body="$(cat "$PLIST")"
  assert_contains "$plist_body" "<string>$TEST_HOME/st ate&amp;more</string>" || return 1
  assert_contains "$plist_body" "<key>TMPDIR</key>" || return 1
  assert_contains "$plist_body" "<string>$TEST_HOME/t mp&amp;&lt;T&gt;</string>" || return 1
  assert_not_contains "$plist_body" "ate&more" "a bare ampersand would be malformed XML" || return 1
  if [[ -z "$PYTHON3" ]]; then
    echo "python3 is not installed: this test parses the plist with plistlib"
    return 1
  fi
  local parsed
  parsed="$("$PYTHON3" -c 'import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
print(d["EnvironmentVariables"]["TEEUP_STATE_DIR"] + "|" + d["EnvironmentVariables"]["TMPDIR"])' "$PLIST" 2>&1)"
  assert_equals "$TEST_HOME/st ate&more|$TEST_HOME/t mp&<T>" "$parsed" "the plist parses and the values round-trip" || return 1
  unset TEEUP_STATE_DIR TMPDIR
  cleanup_test_env
}

test_the_daemon_probe_never_starts_a_daemon() {
  setup
  mkdir -p "$TEST_HOME/.local/state/teeup/done"
  : > "$TEST_HOME/.local/state/teeup/done/cap-emacs"
  local out
  out="$(ALTERNATE_EDITOR="" DRY_RUN=true "$TEEUP" theme set catppuccin 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "emacsclient -a false -e t" || return 1
  assert_not_contains "$(grep '^emacsclient' "$MOCK_LOG")" "emacsclient -e" "every call overrides ALTERNATE_EDITOR" || return 1
  assert_contains "$out" "No Emacs daemon is running" || return 1
  cleanup_test_env
}

test_theme_renders_the_emacs_palette() {
  setup
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  local dark light
  dark="$TEST_HOME/.local/state/teeup/current/theme/dark/emacs.el"
  light="$TEST_HOME/.local/state/teeup/current/theme/light/emacs.el"
  assert_file_exists "$dark" || return 1
  assert_contains "$(cat "$dark")" '(setq teeup-theme-name (intern "modus-vivendi"))' || return 1
  assert_contains "$(cat "$light")" '(setq teeup-theme-name (intern "modus-operandi"))' || return 1
  assert_contains "$(cat "$dark")" '(accent . "#89b4fa")' || return 1
  assert_not_contains "$(cat "$dark")" "{{" "every token was substituted" || return 1
  cleanup_test_env
}

test_hooks_wait_until_teeup_installed_emacs() {
  setup
  : > "$TEST_HOME/daemon-up"
  local out
  out="$(DRY_RUN=true "$TEEUP" theme set catppuccin 2>&1)"
  assert_not_contains "$out" "emacsclient -e" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "emacsclient" "not even the daemon probe runs" || return 1
  cleanup_test_env
}

test_theme_apply_reloads_a_running_daemon() {
  setup
  mkdir -p "$TEST_HOME/.local/state/teeup/done"
  : > "$TEST_HOME/.local/state/teeup/done/cap-emacs"
  : > "$TEST_HOME/daemon-up"
  local out
  out="$(DRY_RUN=true "$TEEUP" theme set catppuccin 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: emacsclient -a false -e (when (fboundp 'teeup-apply) (teeup-apply))" || return 1
  rm -f "$TEST_HOME/daemon-up"
  out="$(DRY_RUN=true "$TEEUP" install font Hack 2>&1)"
  assert_contains "$out" "No Emacs daemon is running; the font is read at the next start." || return 1
  cleanup_test_env
}

test_remove_unloads_the_agent_through_lib_macos() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  DRY_RUN=false cap_run emacs remove >/dev/null
  [[ ! -e "$PLIST" ]] || { echo "plist survived remove"; return 1; }
  assert_contains "$(cat "$MOCK_LOG")" "launchctl bootout gui/501 $PLIST" || return 1
  assert_file_exists "$EMACS_DIR/init.el" "remove keeps the configuration" || return 1
  cleanup_test_env
}

test_configure_points_git_at_emacsclient() {
  setup
  # git ran in the core tier before emacs existed and chose vim.
  mkdir -p "$TEST_HOME/.config/git"
  printf '[core]\n\teditor = vim\n' > "$TEST_HOME/.config/git/teeup-generated"
  mock_command delta 0 ""
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "Re-running the git configuration so git opens emacsclient." || return 1
  assert_contains "$(cat "$TEST_HOME/.config/git/teeup-generated")" "editor = emacsclient -t" || return 1
  out="$(DRY_RUN=false "$TEEUP" configure emacs 2>&1)"
  assert_not_contains "$out" "Re-running the git configuration" "an up-to-date git is left alone" || return 1
  printf '[core]\n\teditor = vim\n' > "$TEST_HOME/.config/git/teeup-generated"
  out="$(TEEUP_SKIP="git" DRY_RUN=false "$TEEUP" configure emacs 2>&1)"
  assert_not_contains "$out" "Re-running the git configuration" "a skipped git is left alone" || return 1
  cleanup_test_env
}

# The starter is loaded by a real Emacs in batch mode with HOME pointing at
# the test home, TEEUP_PATH at this checkout and the theme rendered: it must
# resolve the layer, apply the light Modus theme (the defaults mock exits 1)
# and read the font teeup recorded.
test_starter_loads_in_a_real_emacs() {
  setup
  local NO_EMACS_RC=0
  if no_real_emacs; then
    cleanup_test_env
    return "$NO_EMACS_RC"
  fi
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  mkdir -p "$TEST_HOME/.local/state/teeup/current"
  printf 'Hack Nerd Font\n' > "$TEST_HOME/.local/state/teeup/current/font"
  local out rc=0
  out="$(cd "$TEST_HOME" && env -u TEEUP_APPEARANCE TEEUP_PATH="$TEEUP_PATH" "$EMACS_REAL" -Q --batch \
    -l "$EMACS_DIR/init.el" \
    --eval '(princ (format "THEME=%s MODE=%s FONT=%s ACCENT=%s\n" teeup-theme-name teeup-theme-mode teeup-font-family (cdr (assq (quote accent) teeup-theme-colors))))' 2>&1)" || rc=$?
  assert_success "$rc" "emacs --batch exited non-zero: $out" || return 1
  assert_contains "$out" "THEME=modus-operandi MODE=light FONT=Hack Nerd Font ACCENT=#1e66f5" || return 1
  cleanup_test_env
}

# ~/.config/teeup/env holds %q-escaped values; the thin init.el must decode a
# path with a space, a quote, a dollar sign and non-ASCII bytes the way bash
# would, in both the backslash form and the $'...' form. bash 5 writes the
# first; bash 3.2 (macOS's /bin/bash) switches to the second for non-ASCII
# bytes. The macOS runners have no Emacs, so the $'...' form is also written
# by hand here, byte for byte what bash 3.2 prints for this path, and the
# check does not depend on which bash the runner has. /bin/bash and
# TEEUP_TEST_BASH32 (a developer's bash 3.2 build) are tried as well.
test_env_file_paths_survive_special_bytes() {
  setup
  local NO_EMACS_RC=0
  if no_real_emacs; then
    cleanup_test_env
    return "$NO_EMACS_RC"
  fi
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  local weird checkout
  weird="José's \$Café Dir"
  checkout="$TEST_HOME/$weird Checkout/teeup"
  mkdir -p "$TEST_HOME/.config/teeup"
  local bash_bin out quoted
  for bash_bin in literal bash /bin/bash "${TEEUP_TEST_BASH32:-}"; do
    if [[ "$bash_bin" == "literal" ]]; then
      # What bash 3.2's %q prints for this path: $'...' with the quote
      # backslash-escaped and each UTF-8 byte of é as an octal escape.
      quoted="\$'$TEST_HOME/Jos\\303\\251\\'s \$Caf\\303\\251 Dir Checkout/teeup'"
    else
      [[ -n "$bash_bin" && -x "$(command -v "$bash_bin")" ]] || continue
      quoted="$("$bash_bin" -c 'printf "%q" "$1"' _ "$checkout")"
    fi
    printf 'export TEEUP_PATH=%s\n' "$quoted" > "$TEST_HOME/.config/teeup/env"
    out="$(cd "$TEST_HOME" && env -u TEEUP_PATH "$EMACS_REAL" -Q --batch -l "$EMACS_DIR/init.el" \
      --eval '(princ (format "PATH=%s\n" teeup-path))' 2>/dev/null)"
    assert_contains "$out" "PATH=$checkout" "$bash_bin: TEEUP_PATH should decode byte-for-byte (got: $out)" || return 1
  done
  cleanup_test_env
}

echo "capabilities/emacs"
run_test "install dry run gets the cask" test_install_dry_run_gets_the_cask
run_test "install falls back to the port on macports" test_install_falls_back_to_the_port_on_macports
run_test "install warns when the formula is already installed" test_install_warns_when_the_formula_is_already_installed
run_test "configure prefers the app bundle over a PATH emacs" test_configure_prefers_the_app_bundle_over_a_path_emacs
run_test "configure starter installs the config and the daemon agent" test_configure_starter_installs_the_config_and_the_daemon_agent
run_test "configure is idempotent and leaves a loaded daemon alone" test_configure_is_idempotent_and_leaves_a_loaded_daemon_alone
run_test "configure reloads when the plist changed" test_configure_reloads_when_the_plist_changed
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "configure without emacs skips the agent" test_configure_without_emacs_skips_the_agent
run_test "flavor doom clones and installs" test_flavor_doom_clones_and_installs
run_test "flavor doom skips an existing checkout and config" test_flavor_doom_skips_an_existing_checkout_and_config
run_test "switching starter to doom backs up the starter" test_switching_starter_to_doom_backs_up_the_starter
run_test "flavor spacemacs clones into ~/.emacs.d" test_flavor_spacemacs_clones_into_emacs_d
run_test "flavor none touches no config" test_flavor_none_touches_no_config
run_test "the machine file wins over the answer" test_the_machine_file_wins_over_the_answer
run_test "unknown flavor warns and uses the starter" test_unknown_flavor_warns_and_uses_the_starter
run_test "a legacy ~/.emacs.d is reported, not moved" test_a_legacy_emacs_d_is_reported_not_moved
run_test "plist escapes metacharacters in paths" test_plist_escapes_metacharacters_in_paths
run_test "the daemon probe never starts a daemon" test_the_daemon_probe_never_starts_a_daemon
run_test "theme renders the emacs palette" test_theme_renders_the_emacs_palette
run_test "hooks wait until teeup installed emacs" test_hooks_wait_until_teeup_installed_emacs
run_test "theme-apply reloads a running daemon" test_theme_apply_reloads_a_running_daemon
run_test "remove unloads the agent through lib/macos" test_remove_unloads_the_agent_through_lib_macos
run_test "configure points git at emacsclient" test_configure_points_git_at_emacsclient
run_test "starter loads in a real emacs" test_starter_loads_in_a_real_emacs
run_test "env file paths survive special bytes" test_env_file_paths_survive_special_bytes
print_summary
