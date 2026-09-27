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
  # getconf DARWIN_USER_TEMP_DIR is what real macOS derives every session's
  # TMPDIR from (I3). The mock passes this test's own TMPDIR through
  # unchanged unless a test overrides the mock itself, so a real macOS CI
  # runner's actual getconf output can never leak into a test's assertions,
  # and every existing TMPDIR-based assertion keeps working unmodified.
  mock_command_script getconf <<'EOF2'
case "$1" in
  DARWIN_USER_TEMP_DIR) [ -n "${TMPDIR:-}" ] && { printf '%s\n' "$TMPDIR"; exit 0; }; exit 1 ;;
  *) exit 1 ;;
esac
EOF2
  TEEUP="$TEEUP_PATH/bin/teeup"
  EMACS_DIR="$TEST_HOME/.config/emacs"
  DOOM_DIR="$TEST_HOME/.config/doom"
  PLIST="$TEST_HOME/Library/LaunchAgents/sh.teeup.emacs.plist"
}

# A Doom checkout and a private module already in place, so configure skips
# the clone and `doom install` and goes straight to the part a test wants:
# neither runs a real git clone nor a real `doom install --no-env` (there is
# no real doom binary behind the stub), which would otherwise warn.
stub_doom_checkout() {
  mkdir -p "$EMACS_DIR/bin" "$DOOM_DIR"
  printf '#!/bin/sh\n' > "$EMACS_DIR/bin/doom"
  chmod +x "$EMACS_DIR/bin/doom"
  printf ';; mine\n' > "$DOOM_DIR/init.el"
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

# I4: MacPorts installs the emacs-app port's bundle under its own
# applications_dir (read from macports.conf, same mechanism as
# capabilities/wezterm), not /Applications or ~/Applications, so it must be
# searched too -- and only on MacPorts, so a Homebrew machine never even
# stats a path that could not exist there.
test_configure_finds_the_bundle_under_macports_apps_dir() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 1 ""
  local apps_dir="$TEST_HOME/MacPortsApps"
  mkdir -p "$TEEUP_PKG_PREFIX/etc/macports"
  printf 'applications_dir\t%s\n' "$apps_dir" > "$TEEUP_PKG_PREFIX/etc/macports/macports.conf"
  mkdir -p "$apps_dir/Emacs.app/Contents/MacOS"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$apps_dir/Emacs.app/Contents/MacOS/Emacs"
  chmod +x "$apps_dir/Emacs.app/Contents/MacOS/Emacs"
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  local plist_body
  plist_body="$(cat "$PLIST")"
  assert_contains "$plist_body" "<string>$apps_dir/Emacs.app/Contents/MacOS/Emacs</string>" || return 1
  assert_not_contains "$plist_body" "<string>$MOCK_BIN/emacs</string>" "the terminal-only PATH emacs must not win" || return 1
  cleanup_test_env
}

# I4's other half: the "opens a window" claim is only made for a GUI build.
# With no Emacs.app bundle anywhere, emacs_bin falls back to the PATH
# `emacs` (a terminal-only build in this setup), so that half must be
# qualified rather than promised unconditionally.
test_configure_qualifies_the_window_claim_for_a_terminal_only_build() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "emacsclient -t opens a terminal frame. $MOCK_BIN/emacs is a terminal-only build, so emacsclient -c cannot open a window" || return 1
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

# I1: the "runs as a daemon" claim is only true once launchd actually loaded
# the agent.
test_configure_claims_the_daemon_only_when_it_loaded() {
  setup
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "Emacs runs as a daemon at login" || return 1
  cleanup_test_env
}

# I1's failure half: launchd refuses both the first bootstrap and the retry
# (real launchd's "Bootstrap failed: 5"). The daemon claim must not follow,
# and the rest of the script (the git-editor section further down) must
# still run rather than aborting under `bash -eu` (the set -e audit I1 asks
# for).
test_configure_does_not_claim_the_daemon_when_launchd_refuses() {
  setup
  mock_command_script launchctl <<'EOF2'
case "$1" in
  bootstrap) exit 5 ;;
  print) exit 1 ;;
  *) exit 0 ;;
esac
EOF2
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs 2>&1)"
  assert_not_contains "$out" "Emacs runs as a daemon at login" "the daemon claim must not follow a failed load" || return 1
  assert_contains "$out" "Could not load sh.teeup.emacs; run: launchctl bootstrap gui/501 $PLIST" || return 1
  assert_contains "$out" "Emacs is not running as a daemon; run: launchctl bootstrap gui/501 $PLIST" || return 1
  # Proof the script did not abort: the line after the daemon block still ran.
  assert_contains "$out" "A running daemon keeps its old configuration until" || return 1
  assert_file_exists "$EMACS_DIR/init.el" "the starter config is still installed" || return 1
  cleanup_test_env
}

# M5: a brand-new LaunchAgent plist matches every hand-made one in
# ~/Library/LaunchAgents (mode 644), not write_managed_file's mktemp default
# of 600.
test_configure_creates_the_plist_at_mode_644() {
  setup
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  assert_equals "644" "$(stat -c '%a' "$PLIST" 2>/dev/null || stat -f '%Lp' "$PLIST")" || return 1
  cleanup_test_env
}

# M5's other half: a plist the user chmod'ed keeps that mode across a
# rewrite (write_managed_file's own mode-preservation, unaffected by the new
# 644-on-creation behaviour).
test_configure_keeps_a_users_chmod_on_the_plist() {
  setup
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  printf 'stale\n' > "$PLIST"
  chmod 600 "$PLIST"
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  assert_equals "600" "$(stat -c '%a' "$PLIST" 2>/dev/null || stat -f '%Lp' "$PLIST")" || return 1
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

# Doom's stock config.el starts with a file-local-variables cookie
# (`-*- lexical-binding: t; -*-`), which Emacs only honors on the file's
# first line; if the marked block were prepended ahead of it, the cookie
# would silently stop applying (config.el would load dynamically instead of
# lexically) with no error anywhere. The cookie must stay first, and the
# block goes right after it.
test_doom_flavor_adds_the_theme_line_once() {
  setup
  set_flavor doom
  stub_doom_checkout
  printf ';;; config.el -*- lexical-binding: t; -*-\n(setq doom-theme (quote doom-one))\n' > "$DOOM_DIR/config.el"
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  local body
  body="$(cat "$DOOM_DIR/config.el")"
  assert_equals ";;; config.el -*- lexical-binding: t; -*-" "$(head -n1 "$DOOM_DIR/config.el")" \
    "the file-local-variables cookie must stay on line 1" || return 1
  assert_equals ";; teeup: theme (managed by teeup; remove this line to opt out)" "$(sed -n '2p' "$DOOM_DIR/config.el")" \
    "the marked line follows the cookie, still ahead of the user's own setq" || return 1
  assert_contains "$body" "(load! \"$TEST_HOME/.local/state/teeup/current/theme/doom-theme-loader.el\" \"\" t)" \
    "the line loads the mode-independent loader, not a path fixed to today's appearance (I3)" || return 1
  assert_contains "$body" "(setq doom-theme (quote doom-one))" "the user's own line is kept" || return 1
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  assert_equals "1" "$(grep -c "teeup: theme" "$DOOM_DIR/config.el")" "the line is never duplicated" || return 1
  assert_equals ";;; config.el -*- lexical-binding: t; -*-" "$(head -n1 "$DOOM_DIR/config.el")" \
    "the second run must not move the cookie either" || return 1
  cleanup_test_env
}

test_doom_configure_after_the_core_theme_creates_every_loaded_file() {
  setup
  set_flavor doom
  stub_doom_checkout
  printf ';;; config.el\n' > "$DOOM_DIR/config.el"

  # Fresh-bootstrap order: core theme runs before daily Emacs exists, so the
  # rendered mode files exist but Emacs's hook has not written its loader.
  DRY_RUN=false "$TEEUP" configure theme >/dev/null
  local theme_dir="$TEST_HOME/.local/state/teeup/current/theme"
  assert_file_exists "$theme_dir/dark/doom-theme.el" || return 1
  assert_file_exists "$theme_dir/light/doom-theme.el" || return 1
  [[ ! -e "$theme_dir/doom-theme-loader.el" ]] || { echo "the pre-Emacs theme run unexpectedly wrote the loader"; return 1; }

  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  assert_file_exists "$theme_dir/doom-theme-loader.el" "configure must create the loader before config.el names it" || return 1
  assert_contains "$(cat "$DOOM_DIR/config.el")" "$theme_dir/doom-theme-loader.el" || return 1
  cleanup_test_env
}

# I3: a marked line written by a teeup before this fix names one mode's own
# doom-theme.el directly (the mode fixed at the moment configure last ran,
# never re-evaluated afterward). configure must rewrite just that one line to
# the mode-independent loader, in place, without moving the marker, the
# user's own lines, or duplicating the marker.
test_doom_flavor_rewrites_an_old_style_theme_line() {
  setup
  set_flavor doom
  stub_doom_checkout
  printf ';;; config.el -*- lexical-binding: t; -*-\n%s\n%s\n\n(setq doom-theme (quote doom-one))\n' \
    ";; teeup: theme (managed by teeup; remove this line to opt out)" \
    "(load! \"$TEST_HOME/.local/state/teeup/current/theme/dark/doom-theme.el\" \"\" t)" \
    > "$DOOM_DIR/config.el"
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  local body
  body="$(cat "$DOOM_DIR/config.el")"
  assert_equals ";;; config.el -*- lexical-binding: t; -*-" "$(head -n1 "$DOOM_DIR/config.el")" \
    "the file-local-variables cookie must stay on line 1" || return 1
  assert_equals "1" "$(grep -c "teeup: theme" "$DOOM_DIR/config.el")" "the marker is never duplicated" || return 1
  assert_not_contains "$body" "current/theme/dark/doom-theme.el" "the old per-mode path must be gone" || return 1
  assert_contains "$body" "(load! \"$TEST_HOME/.local/state/teeup/current/theme/doom-theme-loader.el\" \"\" t)" || return 1
  assert_contains "$body" "(setq doom-theme (quote doom-one))" "the user's own line is kept" || return 1
  # A second run converges and changes nothing further.
  local before after
  before="$(cat "$DOOM_DIR/config.el")"
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  after="$(cat "$DOOM_DIR/config.el")"
  assert_equals "$before" "$after" "a run against the new-style line is a no-op" || return 1
  cleanup_test_env
}

# A config.el with no file-local-variables cookie on its first line keeps the
# pre-fix behavior: the marked block goes at the very top.
test_doom_flavor_without_a_cookie_adds_the_line_at_the_top() {
  setup
  set_flavor doom
  stub_doom_checkout
  printf ';;; config.el\n(setq doom-theme (quote doom-one))\n' > "$DOOM_DIR/config.el"
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  assert_equals ";; teeup: theme (managed by teeup; remove this line to opt out)" "$(head -n1 "$DOOM_DIR/config.el")" \
    "with no cookie to protect, the line sits at the top as before" || return 1
  assert_contains "$(cat "$DOOM_DIR/config.el")" "(setq doom-theme (quote doom-one))" "the user's own line is kept" || return 1
  cleanup_test_env
}

test_doom_flavor_dry_run_leaves_config_el_untouched() {
  setup
  set_flavor doom
  stub_doom_checkout
  printf ';;; config.el\n' > "$DOOM_DIR/config.el"
  local before out
  before="$(cat "$DOOM_DIR/config.el")"
  out="$(DRY_RUN=true "$TEEUP" configure emacs 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would add to $DOOM_DIR/config.el: ;; teeup: theme" || return 1
  assert_equals "$before" "$(cat "$DOOM_DIR/config.el")" "a dry run writes nothing" || return 1
  cleanup_test_env
}

test_doom_flavor_without_config_el_writes_nothing() {
  setup
  set_flavor doom
  local out rc=0
  out="$(DRY_RUN=true "$TEEUP" configure emacs 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  [[ ! -e "$DOOM_DIR/config.el" ]] || { echo "config.el appeared with no Doom install"; return 1; }
  assert_not_contains "$out" "teeup: theme" "nothing to add a theme line to yet" || return 1
  cleanup_test_env
}

test_starter_flavor_leaves_doom_config_el_untouched() {
  setup
  mkdir -p "$DOOM_DIR"
  printf ';; mine\n' > "$DOOM_DIR/config.el"
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  assert_equals ";; mine" "$(cat "$DOOM_DIR/config.el")" "the starter never touches Doom's config.el" || return 1
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

# I3: TMPDIR legitimately differs between sessions on the same Mac (a
# Terminal.app session has one, an `ssh host teeup configure emacs` session
# usually does not), but getconf DARWIN_USER_TEMP_DIR does not -- it is what
# macOS derives every session's TMPDIR from. This overrides setup()'s
# pass-through getconf mock with one that ignores TMPDIR entirely (the real
# getconf does too), so the plist-unchanged gate must hold across a run with
# TMPDIR set and a run with it unset.
test_the_tmpdir_gate_holds_across_a_different_session() {
  setup
  mock_command_script getconf <<'EOF2'
case "$1" in
  DARWIN_USER_TEMP_DIR) echo "/var/folders/zz/session-independent/T"; exit 0 ;;
  *) exit 1 ;;
esac
EOF2
  export TMPDIR="$TEST_HOME/session1/T"
  mkdir -p "$TMPDIR"
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  local plist_body
  plist_body="$(cat "$PLIST")"
  assert_contains "$plist_body" "<string>/var/folders/zz/session-independent/T</string>" || return 1
  assert_not_contains "$plist_body" "<string>$TMPDIR</string>" "the session's own TMPDIR must not reach the plist" || return 1
  : > "$TEST_HOME/agent-loaded"
  unset TMPDIR
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure emacs)"
  assert_contains "$out" "Emacs daemon agent already loaded" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "launchctl bootout" "the daemon must not restart across a TMPDIR-only difference" || return 1
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

# The hook itself takes no flavor branch: it calls `teeup-apply` for every
# flavor, and Doom now defines that function too (via the marked config.el
# line and the rendered doom-theme.el), so the same call fires unchanged.
test_theme_apply_reloads_a_running_daemon_for_doom() {
  setup
  set_flavor doom
  mkdir -p "$TEST_HOME/.local/state/teeup/done"
  : > "$TEST_HOME/.local/state/teeup/done/cap-emacs"
  : > "$TEST_HOME/daemon-up"
  local out
  out="$(DRY_RUN=true "$TEEUP" theme set catppuccin 2>&1)"
  assert_contains "$out" "[DRY-RUN] Would execute: emacsclient -a false -e (when (fboundp 'teeup-apply) (teeup-apply))" || return 1
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

# A running Doom's `doom-theme' is only ever set once, when config.el's
# `load!' first loads a rendered doom-theme.el; `teeup-apply', called via
# emacsclient after every `teeup theme set', has to re-read that same path
# from disk before reapplying, or a second `teeup theme set' to a different
# theme would just reload the theme this Emacs already has. This renders
# theme A's doom-theme.el, loads it in a real Emacs, overwrites the same path
# with theme B's rendered file (simulating the `teeup theme set` that ran
# while this Emacs was up), then calls `teeup-apply' and checks `doom-theme'
# picked up B's value. `load-theme' is stubbed: doom-themes is not installed
# here, and a real `load-theme' would error on an unknown theme.
test_doom_theme_apply_picks_up_a_new_theme_without_restarting() {
  setup
  local NO_EMACS_RC=0
  if no_real_emacs; then
    cleanup_test_env
    return "$NO_EMACS_RC"
  fi
  source "$TEEUP_PATH/lib/all.sh"
  local mode="dark" rendered rendered_b palette_a palette_b out
  rendered="$TEST_HOME/.local/state/teeup/current/theme/$mode/doom-theme.el"
  rendered_b="$TEST_HOME/doom-theme-b.el"
  mkdir -p "$(dirname "$rendered")"
  palette_a="$TEST_HOME/palette-a.toml"
  palette_b="$TEST_HOME/palette-b.toml"
  printf 'mode = "dark"\ndoom_theme = "doom-dracula"\n' > "$palette_a"
  printf 'mode = "dark"\ndoom_theme = "doom-nord"\n' > "$palette_b"
  theme_palette_load "$palette_a" "$mode" || { echo "palette A did not load"; return 1; }
  theme_render "$TEEUP_PATH/capabilities/emacs/themed/doom-theme.el.tpl" "$rendered" || { echo "theme A did not render"; return 1; }
  theme_palette_load "$palette_b" "$mode" || { echo "palette B did not load"; return 1; }
  theme_render "$TEEUP_PATH/capabilities/emacs/themed/doom-theme.el.tpl" "$rendered_b" || { echo "theme B did not render"; return 1; }
  out="$(TEEUP_APPEARANCE="$mode" "$EMACS_REAL" -Q --batch \
    --eval "(defun load-theme (&rest _) t)" \
    -l "$rendered" \
    --eval "(copy-file \"$rendered_b\" \"$rendered\" t)" \
    --eval "(teeup-apply)" \
    --eval "(princ (symbol-name doom-theme))" 2>&1)"
  assert_equals "doom-nord" "$out" "teeup-apply re-reads the rendered file, so a running Doom picks up a new theme" || return 1
  cleanup_test_env
}

# The daemon's LaunchAgent plist exports TEEUP_STATE_DIR (capabilities/emacs/
# configure), so `teeup-apply` must resolve the rendered file's directory the
# same way `lib/core.sh` does -- (getenv "TEEUP_STATE_DIR") first -- not a
# path hardcoded to the default ~/.local/state/teeup. This renders theme A
# under a non-default state dir, loads it, overwrites that same path with
# theme B's rendered file, then runs `teeup-apply` with TEEUP_STATE_DIR set to
# that non-default directory and checks `doom-theme` picked up B's value.
test_doom_theme_apply_honors_a_non_default_teeup_state_dir() {
  setup
  local NO_EMACS_RC=0
  if no_real_emacs; then
    cleanup_test_env
    return "$NO_EMACS_RC"
  fi
  source "$TEEUP_PATH/lib/all.sh"
  local mode="dark" state_dir rendered rendered_b palette_a palette_b out
  state_dir="$TEST_HOME/elsewhere/state"
  rendered="$state_dir/current/theme/$mode/doom-theme.el"
  rendered_b="$TEST_HOME/doom-theme-b.el"
  mkdir -p "$(dirname "$rendered")"
  palette_a="$TEST_HOME/palette-a.toml"
  palette_b="$TEST_HOME/palette-b.toml"
  printf 'mode = "dark"\ndoom_theme = "doom-dracula"\n' > "$palette_a"
  printf 'mode = "dark"\ndoom_theme = "doom-nord"\n' > "$palette_b"
  theme_palette_load "$palette_a" "$mode" || { echo "palette A did not load"; return 1; }
  theme_render "$TEEUP_PATH/capabilities/emacs/themed/doom-theme.el.tpl" "$rendered" || { echo "theme A did not render"; return 1; }
  theme_palette_load "$palette_b" "$mode" || { echo "palette B did not load"; return 1; }
  theme_render "$TEEUP_PATH/capabilities/emacs/themed/doom-theme.el.tpl" "$rendered_b" || { echo "theme B did not render"; return 1; }
  out="$(TEEUP_APPEARANCE="$mode" TEEUP_STATE_DIR="$state_dir" "$EMACS_REAL" -Q --batch \
    --eval "(defun load-theme (&rest _) t)" \
    -l "$rendered" \
    --eval "(copy-file \"$rendered_b\" \"$rendered\" t)" \
    --eval "(teeup-apply)" \
    --eval "(princ (symbol-name doom-theme))" 2>&1)"
  assert_equals "doom-nord" "$out" "teeup-apply must resolve TEEUP_STATE_DIR from the environment, not a hardcoded path" || return 1
  cleanup_test_env
}

# doom-themes may not be installed (e.g. the :ui theme module disabled);
# `load-theme` then errors. teeup-apply must degrade like the starter's
# teeup-apply-theme: message the error and leave Emacs usable, not signal out
# of the daemon hook. load-theme is stubbed to error unconditionally.
test_doom_theme_apply_survives_a_load_theme_error() {
  setup
  local NO_EMACS_RC=0
  if no_real_emacs; then
    cleanup_test_env
    return "$NO_EMACS_RC"
  fi
  source "$TEEUP_PATH/lib/all.sh"
  local mode="dark" rendered palette out rc=0
  rendered="$TEST_HOME/.local/state/teeup/current/theme/$mode/doom-theme.el"
  mkdir -p "$(dirname "$rendered")"
  palette="$TEST_HOME/palette.toml"
  printf 'mode = "dark"\ndoom_theme = "doom-dracula"\n' > "$palette"
  theme_palette_load "$palette" "$mode" || { echo "palette did not load"; return 1; }
  theme_render "$TEEUP_PATH/capabilities/emacs/themed/doom-theme.el.tpl" "$rendered" || { echo "theme did not render"; return 1; }
  out="$(TEEUP_APPEARANCE="$mode" "$EMACS_REAL" -Q --batch \
    --eval "(defun load-theme (&rest _) (error \"doom-themes not installed\"))" \
    -l "$rendered" \
    --eval "(teeup-apply)" \
    --eval '(princ "OK")' 2>&1)" || rc=$?
  assert_success "$rc" "teeup-apply must not signal when load-theme errors: $out" || return 1
  assert_contains "$out" "OK" "Emacs stays usable and reaches the eval after teeup-apply" || return 1
  cleanup_test_env
}

test_doom_theme_registers_the_macos_appearance_hook_once() {
  setup
  local NO_EMACS_RC=0
  if no_real_emacs; then
    cleanup_test_env
    return "$NO_EMACS_RC"
  fi
  source "$TEEUP_PATH/lib/all.sh"
  local rendered="$TEST_HOME/doom-theme.el" palette="$TEST_HOME/palette.toml" out rc=0
  printf 'mode = "dark"\ndoom_theme = "doom-dracula"\n' > "$palette"
  theme_palette_load "$palette" dark || { echo "palette did not load"; return 1; }
  theme_render "$TEEUP_PATH/capabilities/emacs/themed/doom-theme.el.tpl" "$rendered" || { echo "theme did not render"; return 1; }

  out="$("$EMACS_REAL" -Q --batch -l "$rendered" \
    --eval '(princ (format "BOUND=%s" (boundp (quote ns-system-appearance-change-functions))))' 2>&1)" || rc=$?
  assert_success "$rc" "the rendered Doom theme must load when the macOS hook variable is absent: $out" || return 1
  assert_equals "BOUND=nil" "$out" "a non-macOS Emacs must not gain the macOS hook variable" || return 1

  out="$("$EMACS_REAL" -Q --batch \
    --eval '(defvar ns-system-appearance-change-functions nil)' \
    -l "$rendered" -l "$rendered" \
    --eval '(defvar teeup-hook-called nil)' \
    --eval '(defun teeup-apply () (setq teeup-hook-called t))' \
    --eval '(run-hook-with-args (quote ns-system-appearance-change-functions) (quote dark))' \
    --eval '(princ (format "COUNT=%d CALLED=%s" (length ns-system-appearance-change-functions) teeup-hook-called))' 2>&1)" || rc=$?
  assert_success "$rc" "the registered appearance hook must run: $out" || return 1
  assert_equals "COUNT=1 CALLED=t" "$out" "the callback is registered once and calls teeup-apply" || return 1
  cleanup_test_env
}

# I3: the loader capabilities/emacs/theme-apply renders must pick a mode at
# Emacs load time, not carry one baked in by whoever last ran `teeup theme
# set`. This runs a real `teeup theme set` (the same path a real machine
# takes, so the rendered loader is the genuine one, not a hand-built fixture),
# then loads that one file in a real Emacs twice, once per TEEUP_APPEARANCE,
# and checks `doom-theme` picked up catppuccin's own value for each mode.
test_doom_theme_loader_picks_the_current_appearance_at_load_time() {
  setup
  local NO_EMACS_RC=0
  if no_real_emacs; then
    cleanup_test_env
    return "$NO_EMACS_RC"
  fi
  set_flavor doom
  mkdir -p "$TEST_HOME/.local/state/teeup/done"
  : > "$TEST_HOME/.local/state/teeup/done/cap-emacs"
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null
  local loader="$TEST_HOME/.local/state/teeup/current/theme/doom-theme-loader.el"
  assert_file_exists "$loader" "the theme-apply hook must render the loader for a Doom flavor" || return 1
  local out
  out="$(TEEUP_APPEARANCE=light "$EMACS_REAL" -Q --batch -l "$loader" --eval "(princ (symbol-name doom-theme))" 2>&1)"
  assert_equals "doom-acario-light" "$out" "the loader must pick catppuccin's light doom theme when TEEUP_APPEARANCE=light" || return 1
  out="$(TEEUP_APPEARANCE=dark "$EMACS_REAL" -Q --batch -l "$loader" --eval "(princ (symbol-name doom-theme))" 2>&1)"
  assert_equals "doom-dracula" "$out" "the loader must pick catppuccin's dark doom theme otherwise" || return 1
  cleanup_test_env
}

# M8: `teeup--find-quote` (the `string-search` call `teeup--unquote` makes
# for '...' quoting) must degrade to `string-match` on an Emacs without
# `string-search` (28 and earlier) rather than erroring out of init. Run
# against whatever real Emacs this suite already has (see EMACS_REQUIRED
# above): `fmakunbound` simulates the missing function regardless of which
# Emacs is actually installed.
test_unquote_degrades_without_string_search() {
  setup
  local NO_EMACS_RC=0
  if no_real_emacs; then
    cleanup_test_env
    return "$NO_EMACS_RC"
  fi
  DRY_RUN=false "$TEEUP" configure emacs >/dev/null
  # The word is built from char codes (39 is a single quote) rather than
  # written as a literal Lisp string here, so the shell's own single-quoting
  # of --eval never has to contain a ' itself. The word is "'ab'c'": two
  # '...'-quoted runs, "ab" and (after the bare c) an empty one at the end.
  local out rc=0
  out="$(cd "$TEST_HOME" && env -u TEEUP_APPEARANCE TEEUP_PATH="$TEEUP_PATH" "$EMACS_REAL" -Q --batch \
    -l "$EMACS_DIR/init.el" \
    --eval '(progn (fmakunbound (quote string-search))
                   (let ((q (char-to-string 39)))
                     (princ (format "UNQUOTED=%s\n" (teeup--unquote (concat q "ab" q "c" q))))))' 2>&1)" || rc=$?
  assert_success "$rc" "emacs --batch exited non-zero: $out" || return 1
  assert_contains "$out" "UNQUOTED=abc" "the '...' branch must still find the closing quote via string-match" || return 1
  cleanup_test_env
}

# `teeup uninstall` without --packages: the agent still goes, the port the
# MacPorts install put here stays.
test_remove_keeps_the_port_when_packages_are_kept() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command_script port <<'EOF2'
case "$1" in
  installed) echo "  $2 @1.0_0 (active)" ;;
esac
exit 0
EOF2
  source "$TEEUP_PATH/lib/all.sh"
  local out
  out="$(DRY_RUN=false TEEUP_REMOVE_PACKAGES=false cap_run emacs remove 2>&1)"
  assert_contains "$out" "Keeping the Emacs application; packages stay installed." || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "port uninstall" || return 1
  out="$(DRY_RUN=false cap_run emacs remove 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "sudo port uninstall emacs" "teeup remove still takes the port off" || return 1
  cleanup_test_env
}

echo "capabilities/emacs"
run_test "install dry run gets the cask" test_install_dry_run_gets_the_cask
run_test "install falls back to the port on macports" test_install_falls_back_to_the_port_on_macports
run_test "install warns when the formula is already installed" test_install_warns_when_the_formula_is_already_installed
run_test "configure prefers the app bundle over a PATH emacs" test_configure_prefers_the_app_bundle_over_a_path_emacs
run_test "configure finds the bundle under macports_apps_dir" test_configure_finds_the_bundle_under_macports_apps_dir
run_test "configure qualifies the window claim for a terminal-only build" test_configure_qualifies_the_window_claim_for_a_terminal_only_build
run_test "configure starter installs the config and the daemon agent" test_configure_starter_installs_the_config_and_the_daemon_agent
run_test "configure is idempotent and leaves a loaded daemon alone" test_configure_is_idempotent_and_leaves_a_loaded_daemon_alone
run_test "configure reloads when the plist changed" test_configure_reloads_when_the_plist_changed
run_test "configure claims the daemon only when it loaded" test_configure_claims_the_daemon_only_when_it_loaded
run_test "configure does not claim the daemon when launchd refuses" test_configure_does_not_claim_the_daemon_when_launchd_refuses
run_test "configure creates the plist at mode 644" test_configure_creates_the_plist_at_mode_644
run_test "configure keeps a user's chmod on the plist" test_configure_keeps_a_users_chmod_on_the_plist
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
run_test "doom flavor adds the theme line once" test_doom_flavor_adds_the_theme_line_once
run_test "doom configure after the core theme creates every loaded file" test_doom_configure_after_the_core_theme_creates_every_loaded_file
run_test "doom flavor rewrites an old-style theme line to the loader" test_doom_flavor_rewrites_an_old_style_theme_line
run_test "doom flavor without a cookie adds the line at the top" test_doom_flavor_without_a_cookie_adds_the_line_at_the_top
run_test "doom flavor dry run leaves config.el untouched" test_doom_flavor_dry_run_leaves_config_el_untouched
run_test "doom flavor without config.el writes nothing" test_doom_flavor_without_config_el_writes_nothing
run_test "starter flavor leaves Doom's config.el untouched" test_starter_flavor_leaves_doom_config_el_untouched
run_test "plist escapes metacharacters in paths" test_plist_escapes_metacharacters_in_paths
run_test "the TMPDIR gate holds across a different session" test_the_tmpdir_gate_holds_across_a_different_session
run_test "the daemon probe never starts a daemon" test_the_daemon_probe_never_starts_a_daemon
run_test "theme renders the emacs palette" test_theme_renders_the_emacs_palette
run_test "hooks wait until teeup installed emacs" test_hooks_wait_until_teeup_installed_emacs
run_test "theme-apply reloads a running daemon" test_theme_apply_reloads_a_running_daemon
run_test "theme-apply reloads a running daemon for doom" test_theme_apply_reloads_a_running_daemon_for_doom
run_test "remove unloads the agent through lib/macos" test_remove_unloads_the_agent_through_lib_macos
run_test "remove keeps the port when packages are kept" test_remove_keeps_the_port_when_packages_are_kept
run_test "configure points git at emacsclient" test_configure_points_git_at_emacsclient
run_test "starter loads in a real emacs" test_starter_loads_in_a_real_emacs
run_test "env file paths survive special bytes" test_env_file_paths_survive_special_bytes
run_test "doom theme-apply picks up a new theme without restarting" test_doom_theme_apply_picks_up_a_new_theme_without_restarting
run_test "doom theme-apply honors a non-default TEEUP_STATE_DIR" test_doom_theme_apply_honors_a_non_default_teeup_state_dir
run_test "doom theme-apply survives a load-theme error" test_doom_theme_apply_survives_a_load_theme_error
run_test "doom theme registers the macOS appearance hook once" test_doom_theme_registers_the_macos_appearance_hook_once
run_test "doom theme loader picks the current appearance at load time" test_doom_theme_loader_picks_the_current_appearance_at_load_time
run_test "unquote degrades without string-search" test_unquote_degrades_without_string_search
print_summary
