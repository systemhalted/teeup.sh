#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/helper.sh"

BOOT="$TEEUP_PATH/bootstrap"

# Answers piped to the plain-read prompts, one per prompt. The package manager
# is asked first and on its own, before step 2 installs one; the rest is the
# wizard in step 4:
# package manager choice, name, email, theme choice, daily confirm, Emacs
# flavor. Work is never asked (it is per-machine, not a question; see
# machines/*.conf). "1" is the detected backend (Homebrew on the mocked
# modern Mac), "2" the other one; for the theme choice, "1" is the first
# theme themes/ ships, i.e. catppuccin. The flavor question is asked only
# after a "y" to the daily set, and the plain-read fallback takes an empty
# answer (end of input here) as the first option, starter, so inputs that
# stop after the daily confirm still work.
WIZARD_INPUT=$'1\nAda Lovelace\nada@example.com\n1\ny\n'

setup() {
  setup_test_env
  mock_macos_base
  mock_command softwareupdate 0 ""
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  # /usr/bin/security is macOS-only; 44 is its "no such item" exit code.
  mock_command security 44 ""
  # zsh capability: the login-shell probe, the change itself, and the
  # appearance read the shell layer performs (never reached from bootstrap,
  # mocked so a stray call cannot touch the host).
  mock_command dscl 0 "UserShell: /bin/zsh"
  mock_command chsh 0 ""
  mock_command defaults 1 ""
  # aerospace/configure probes /Applications outside run_cmd; point it at an
  # empty tree so the walk is the same on a developer's Mac and on CI.
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  # ssh capability: never let a real keygen or agent call escape a test run.
  mock_command ssh-keygen 0 ""
  mock_command ssh-add 0 ""
  # github capability: signed out, with an empty key list. These two calls are
  # reads, so they are not covered by DRY_RUN and would otherwise hit the real
  # gh session and the GitHub API. Shaped like the github suite's mock (a
  # "Token scopes:" line on a successful auth status, and the real five-column
  # non-TTY `ssh-key list` format TITLE/KEY/ADDED/ID/TYPE) even though this
  # fresh-machine walk never reaches the signed-in branch, so the two mocks do
  # not drift apart.
  mock_command_script gh <<'EOF2'
host=""
prev=""
for a in "$@"; do
  [ "$prev" = "-h" ] && host="$a"
  prev="$a"
done
case "$1 ${2:-}" in
  "auth status")
    session_file="$HOME/gh-session"
    [ -z "$host" ] || [ "$host" = "github.com" ] || session_file="$HOME/gh-session-$host"
    [ -f "$session_file" ] || exit 1
    echo "${host:-github.com}"
    echo "  Token scopes: $(cat "$session_file")"
    ;;
  "ssh-key list") cat "$HOME/gh-keys" 2>/dev/null || true ;;
  *) : ;;
esac
exit 0
EOF2
  # mise capability: `mise ls --global` is a read, so DRY_RUN does not cover
  # it. Succeeding with no output is the fresh-machine answer: the global
  # mise.toml asks for no tools yet.
  mock_command_script mise <<'EOF2'
[ "$1" = "-C" ] && shift 2
case "$1 ${2:-}" in
  "ls --global") : ;;
  *) : ;;
esac
exit 0
EOF2
  # emacs and emacsclient are in the list below because a fresh Mac has
  # neither and a Linux developer machine may have both in /usr/bin: with them
  # hidden, emacs configure skips the daemon agent and never reaches launchctl.
  export TEEUP_TEST_MISSING="brew gum jq starship rg fd fzf bat eza zoxide yq btop tldr dust gpg delta git-lfs lazygit emacs emacsclient"
  export TEEUP_NO_GUM=1
  export DRY_RUN=true
}

test_refuses_non_macos() {
  setup
  mock_command uname 0 "Linux"
  local rc=0 out
  out="$("$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")" || rc=$?
  assert_equals "1" "$rc" || return 1
  assert_contains "$out" "teeup targets macOS only" || return 1
  cleanup_test_env
}

test_refuses_root() {
  setup
  mock_command id 0 "0"
  local rc=0 out
  out="$("$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")" || rc=$?
  assert_equals "1" "$rc" || return 1
  assert_contains "$out" "not root" || return 1
  cleanup_test_env
}

test_unknown_flag_exits_2() {
  setup
  local rc=0
  "$BOOT" --frobnicate >/dev/null 2>&1 || rc=$?
  assert_equals "2" "$rc" || return 1
  cleanup_test_env
}

test_dry_run_walks_core_tier_in_order() {
  setup
  local out
  out="$("$BOOT" --dry-run <<<"$WIZARD_INPUT")"
  local x p r d
  x="$(printf '%s\n' "$out" | grep -n 'Completed: xcode-clt install' | head -1 | cut -d: -f1)"
  p="$(printf '%s\n' "$out" | grep -n 'Completed: package-manager install' | head -1 | cut -d: -f1)"
  r="$(printf '%s\n' "$out" | grep -n 'Completed: teeup-runtime configure' | head -1 | cut -d: -f1)"
  d="$(printf '%s\n' "$out" | grep -n 'Completed: dev-dirs configure' | head -1 | cut -d: -f1)"
  [[ -n "$x" && -n "$p" && -n "$r" && -n "$d" ]] || { echo "a core step did not complete:"; printf '%s\n' "$out"; return 1; }
  [[ "$x" -lt "$p" && "$p" -lt "$r" && "$r" -lt "$d" ]] || { echo "core tier ran out of order"; return 1; }
  assert_contains "$out" "Homebrew/install/HEAD/install.sh" || return 1
  assert_contains "$out" "Would set TEEUP_NAME" || return 1
  assert_contains "$out" "Would set TEEUP_THEME" || return 1
  assert_contains "$out" "Would record state: done/bootstrap" || return 1
  assert_contains "$out" "Bootstrap finished" || return 1
  cleanup_test_env
}

test_the_theme_is_rendered_once() {
  setup
  # theme is the last core capability; step 7 must not render it a second
  # time (every template, every theme-apply hook, starship.toml again).
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")"
  assert_equals "1" "$(printf '%s\n' "$out" | grep -c 'Completed: theme configure')" || return 1
  assert_equals "1" "$(printf '%s\n' "$out" | grep -c 'Would swap')" || return 1
  assert_contains "$out" "Would record state: done/bootstrap" || return 1
  cleanup_test_env
}

test_choosing_macports_runs_the_macports_path() {
  setup
  # MacPorts is never auto-installed, so the choice only reaches its path when
  # `port` is already there; a modern Mac detects Homebrew, so option 2 is
  # MacPorts. Before this question moved ahead of step 2, the answer arrived
  # after Homebrew had already been installed and recorded.
  mock_command port 0 ""
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<$'2\nAda Lovelace\nada@example.com\n1\ny\n')"
  assert_contains "$out" "Would execute: sudo port selfupdate" || return 1
  assert_not_contains "$out" "Homebrew/install/HEAD/install.sh" || return 1
  assert_contains "$out" "Would set TEEUP_PACKAGE_MANAGER" || return 1
  cleanup_test_env
}

test_the_package_manager_is_asked_before_it_is_installed() {
  setup
  local out pm_line install_line
  out="$("$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")"
  # ui_choose's plain fallback prints the prompt on a line of its own, which
  # is what -x matches; the capability's "Package manager already recorded"
  # log lines are not the question.
  pm_line="$(printf '%s\n' "$out" | grep -nx 'Package manager' | head -1 | cut -d: -f1)"
  install_line="$(printf '%s\n' "$out" | grep -n 'Starting: package-manager install' | head -1 | cut -d: -f1)"
  [[ -n "$pm_line" && -n "$install_line" ]] ||
    { echo "expected both the question and the install:"; printf '%s\n' "$out"; return 1; }
  [[ "$pm_line" -lt "$install_line" ]] || { echo "the package manager was asked after it was installed"; return 1; }
  # And it is asked exactly once: the wizard no longer repeats the question.
  assert_equals "1" "$(printf '%s\n' "$out" | grep -cx 'Package manager')" || return 1
  # The choice is recorded before the capability that installs it runs, so the
  # capability agrees with it instead of recording a backend of its own.
  assert_contains "$out" "Package manager already recorded: homebrew" || return 1
  # The wizard's theme question offers only what themes/ ships (catppuccin);
  # ui_choose prints its options on stderr, which this test already captures.
  assert_not_contains "$out" "tokyo-night" "the wizard must not offer an unshipped theme" || return 1
  cleanup_test_env
}

test_git_is_reconfigured_after_ssh_makes_the_keys() {
  setup
  local out ssh_start git_done ssh_done
  out="$("$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")"
  ssh_start="$(printf '%s\n' "$out" | grep -n 'Starting: ssh configure' | head -1 | cut -d: -f1)"
  ssh_done="$(printf '%s\n' "$out" | grep -n 'Completed: ssh configure' | head -1 | cut -d: -f1)"
  git_done="$(printf '%s\n' "$out" | grep -n 'Completed: git configure' | tail -1 | cut -d: -f1)"
  [[ -n "$ssh_start" && -n "$ssh_done" && -n "$git_done" ]] ||
    { echo "a step did not complete:"; printf '%s\n' "$out"; return 1; }
  # git runs before ssh in the core list, so its first pass sees no keys and
  # writes commit.gpgsign = false. The last `git configure` must therefore be
  # the one ssh re-runs for itself, nested inside ssh configure.
  [[ "$git_done" -gt "$ssh_start" && "$git_done" -lt "$ssh_done" ]] ||
    { echo "git was not reconfigured inside ssh configure (ssh $ssh_start..$ssh_done, git $git_done)"; return 1; }
  cleanup_test_env
}

test_post_bootstrap_hooks_run_before_the_summary() {
  setup
  mkdir -p "$TEST_HOME/.config/teeup/hooks/post-bootstrap.d"
  printf '#!/usr/bin/env bash\ntouch "$HOME/hook-ran"\n' > "$TEST_HOME/.config/teeup/hooks/post-bootstrap.d/10-mark.sh"
  local out h s
  out="$("$BOOT" --dry-run <<<"$WIZARD_INPUT")"
  assert_contains "$out" "[DRY-RUN] Would run hook: $TEST_HOME/.config/teeup/hooks/post-bootstrap.d/10-mark.sh" || return 1
  h="$(printf '%s\n' "$out" | grep -n 'Would run hook' | head -1 | cut -d: -f1)"
  s="$(printf '%s\n' "$out" | grep -n 'Bootstrap finished' | head -1 | cut -d: -f1)"
  [[ "$h" -lt "$s" ]] || { echo "the hook must come before the summary"; return 1; }
  [[ ! -e "$TEST_HOME/hook-ran" ]] || { echo "a hook ran in dry run"; return 1; }
  cleanup_test_env
}

test_a_fresh_bootstrap_marks_every_migration_without_running_it() {
  setup
  export TEEUP_MIGRATIONS_DIR="$TEST_HOME/migrations"
  mkdir -p "$TEEUP_MIGRATIONS_DIR"
  printf '#!/usr/bin/env bash\ntouch "$HOME/migration-ran"\n' > "$TEEUP_MIGRATIONS_DIR/1780000000.sh"
  cp "$TEEUP_MIGRATIONS_DIR/1780000000.sh" "$TEEUP_MIGRATIONS_DIR/1790000000.sh"
  local out
  out="$("$BOOT" --dry-run <<<"$WIZARD_INPUT")"
  assert_contains "$out" "Would record state: migrations/1780000000.sh" || return 1
  assert_contains "$out" "Would record state: migrations/1790000000.sh" || return 1
  assert_not_contains "$out" "Starting: migration" "bootstrap runs no migration" || return 1
  [[ ! -e "$TEST_HOME/migration-ran" ]] || { echo "a migration ran during bootstrap"; return 1; }
  cleanup_test_env
}

# The spec's Verification gate asks for two real (DRY_RUN=false) bootstraps,
# which needs more of the machine than the dry-run walk above: a package
# manager that remembers what it installed, keys that really appear, a
# defaults database that keeps what was written, and the macOS-only commands
# the capabilities call. Everything still lands inside $TEST_HOME.
mock_a_real_machine() {
  # brew is hidden in setup so the dry-run walk sees a fresh Mac. Here it has
  # to be visible: `have brew` gates pkg_installed and cask_installed, and
  # with it missing every check is false and the second bootstrap reinstalls
  # the lot.
  export TEEUP_TEST_MISSING="gum jq starship rg fd fzf bat eza zoxide yq btop tldr dust gpg delta git-lfs lazygit emacs emacsclient"
  export BREWDB="$TEST_HOME/brewdb"
  mkdir -p "$BREWDB"
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "list --formula") [ -f "$BREWDB/f-$3" ] ;;
  "list --cask") [ -f "$BREWDB/c-${3##*/}" ] ;;
  "install --cask") shift 2; for c in "$@"; do touch "$BREWDB/c-${c##*/}"; done ;;
  "install "*) shift; for p in "$@"; do touch "$BREWDB/f-$p"; done ;;
  *) : ;;
esac
EOF2
  # pkg_backend_prepare looks for brew at the prefix, not on PATH; with it
  # there the Homebrew installer (a curl | bash) never runs. curl fails for
  # the same reason: nothing in a test may reach the network.
  mkdir -p "$TEEUP_PKG_PREFIX/bin"
  cp "$MOCK_BIN/brew" "$TEEUP_PKG_PREFIX/bin/brew"
  mock_command curl 1 ""
  mock_command launchctl 0 ""
  mock_command hidutil 0 ""
  mock_command killall 0 ""
  mock_command open 0 ""
  mock_command osascript 0 ""
  mock_command mas 0 ""
  # ssh-keygen writes the pair it is asked for, so the second run finds it.
  mock_command_script ssh-keygen <<'EOF2'
prev=""
for a in "$@"; do
  [ "$prev" = "-f" ] && { printf 'key\n' > "$a"; printf 'ssh-ed25519 AAAA test\n' > "$a.pub"; }
  prev="$a"
done
exit 0
EOF2
  # A gh that is already signed in with the scopes the github capability wants.
  printf 'admin:public_key\n' > "$TEST_HOME/gh-session"
  # A stateful defaults(1): what configure writes, the next read returns, so
  # the second run finds every preference already set. Same shape as the one
  # in tests/lib/macos.sh, without the write validation that suite needs.
  export DDB="$TEST_HOME/defaults-db"
  mkdir -p "$DDB"
  mock_command_script defaults <<'EOF2'
op="$1"; shift
f="$DDB/$1.$2"
case "$op" in
  read)
    [ -f "$f" ] || exit 1
    t="$(head -1 "$f")"; v="$(tail -n +2 "$f")"
    if [ "$t" = boolean ]; then
      case "$v" in [Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|1) echo 1 ;; *) echo 0 ;; esac
    else
      printf '%s\n' "$v"
    fi
    ;;
  read-type) [ -f "$f" ] || exit 1; echo "Type is $(head -1 "$f")" ;;
  write)
    case "$3" in
      -bool) t=boolean ;;
      -int) t=integer ;;
      -float) t=float ;;
      -string) t=string ;;
      *) exit 1 ;;
    esac
    printf '%s\n%s\n' "$t" "$4" > "$f"
    ;;
  delete) rm -f "$f" ;;
esac
EOF2
}

# home_state -> every file under $HOME with a checksum of its contents, one
# per line, sorted. The harness's own scratch (the mock log, the marker, the
# bootstrap log) is left out; everything else, including symlink targets, is
# in. Two identical listings mean the second run changed nothing at all.
home_state() {
  ( cd "$TEST_HOME" && find . \( -type f -o -type l \) \
      ! -name 'mock.log' ! -name '.idempotency-marker' \
      ! -path './.local/state/teeup/logs/*' -print0 \
    | LC_ALL=C sort -z \
    | while IFS= read -r -d '' f; do
        if [[ -L "$f" ]]; then printf '%s link:%s\n' "$f" "$(readlink "$f")"
        else printf '%s %s\n' "$f" "$(cksum < "$f")"
        fi
      done )
}

test_a_second_bootstrap_changes_nothing() {
  setup
  mock_a_real_machine
  export DRY_RUN=false
  "$BOOT" <<<"$WIZARD_INPUT" >/dev/null 2>&1 || { echo "the first bootstrap failed"; return 1; }
  local marker="$TEST_HOME/.idempotency-marker"
  : > "$marker"
  local before after out
  before="$(home_state)"
  out="$("$BOOT" </dev/null 2>&1)" || { echo "the second bootstrap failed"; return 1; }
  after="$(home_state)"
  assert_equals "$before" "$after" "the second bootstrap changed a file under \$HOME" || return 1
  # Nothing outside teeup's own state directory may even be rewritten.
  # wezterm.lua is the one exception and it is deliberate: theme-apply touches
  # it so a running WezTerm reloads (its contents are in the comparison above).
  local written
  written="$(find "$TEST_HOME" -newer "$marker" \( -type f -o -type l \) \
    ! -name 'mock.log' ! -name '.idempotency-marker' \
    ! -path "$TEST_HOME/.local/state/teeup/*" \
    ! -path "$TEST_HOME/.config/wezterm/wezterm.lua" 2>/dev/null)"
  assert_equals "" "$written" "the second bootstrap wrote outside the state directory" || return 1
  # And it says so: every step reports what is already there.
  assert_contains "$out" "Homebrew already installed." || return 1
  assert_contains "$out" "Already installed: gum" || return 1
  assert_contains "$out" "Already current: $TEST_HOME/.config/teeup/env" || return 1
  assert_contains "$out" "Already installed: $TEST_HOME/.zshrc" || return 1
  assert_contains "$out" "Already present: $TEST_HOME/Work" || return 1
  assert_contains "$out" "Already signed in to GitHub (" || return 1
  assert_contains "$out" "macOS preferences already set; nothing to restart." || return 1
  assert_not_contains "$out" "Installed ripgrep (Homebrew)" "nothing was installed again" || return 1
  assert_not_contains "$out" "Installed wezterm (cask)" "no cask was installed again" || return 1
  assert_not_contains "$out" "Generating the" "the keys were left alone" || return 1
  assert_not_contains "$out" "One manual step" "the AeroSpace block is printed once" || return 1
  cleanup_test_env
}
test_dry_run_touches_nothing() {
  setup
  "$BOOT" --dry-run <<<"$WIZARD_INPUT" >/dev/null
  [[ ! -e "$TEST_HOME/.config/teeup/answers" ]] || { echo "answers written in dry run"; return 1; }
  [[ ! -e "$TEST_HOME/Work" ]] || { echo "Work created in dry run"; return 1; }
  assert_not_contains "$(cat "$MOCK_LOG")" "sudo" "no sudo in dry run" || return 1
  cleanup_test_env
}

test_existing_answers_skip_wizard() {
  setup
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_NAME="Ada"\nTEEUP_EMAIL="ada@example.com"\nTEEUP_PACKAGE_MANAGER="homebrew"\nTEEUP_THEME="catppuccin"\nTEEUP_DAILY="yes"\n' > "$TEST_HOME/.config/teeup/answers"
  local out
  out="$("$BOOT" --dry-run </dev/null)"
  assert_contains "$out" "Using existing answers" || return 1
  assert_not_contains "$out" "Your full name" || return 1
  cleanup_test_env
}

test_wizard_runs_when_only_backend_recorded() {
  setup
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_PACKAGE_MANAGER="homebrew"\n' > "$TEST_HOME/.config/teeup/answers"
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")"
  assert_contains "$out" "Your full name" || return 1
  cleanup_test_env
}

test_reconfigure_reruns_wizard() {
  setup
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_NAME="Ada"\n' > "$TEST_HOME/.config/teeup/answers"
  local out
  out="$("$BOOT" --dry-run --reconfigure 2>&1 <<<"$WIZARD_INPUT")"
  assert_contains "$out" "Your full name" || return 1
  cleanup_test_env
}

test_reconfigure_does_not_ask_for_a_pinned_package_manager() {
  setup
  # machines/<hostname>.conf pins the backend. Asking anyway would export the
  # answer into bootstrap's own shell while every capability (which reloads
  # the machine file) ignored it, so pkg_backend_path in bootstrap would add
  # the wrong bin dir and lose the gum the capability had just installed.
  # The question is only reachable with --reconfigure, so that is the probe.
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEST_HOME/machines" "$TEST_HOME/.config/teeup"
  printf 'TEEUP_PACKAGE_MANAGER="homebrew"\n' > "$TEST_HOME/machines/testmac.conf"
  printf 'TEEUP_NAME="Ada"\n' > "$TEST_HOME/.config/teeup/answers"
  # The wizard input minus the package-manager line: it must not be asked.
  local out
  out="$("$BOOT" --dry-run --reconfigure 2>&1 <<<$'Ada Lovelace\nada@example.com\n1\ny\n')"
  assert_contains "$out" "Package manager is pinned to homebrew by $TEST_HOME/machines/testmac.conf" || return 1
  assert_equals "0" "$(printf '%s\n' "$out" | grep -cx 'Package manager')" || return 1
  assert_not_contains "$out" "Would set TEEUP_PACKAGE_MANAGER" || return 1
  assert_contains "$out" "Homebrew/install/HEAD/install.sh" || return 1
  assert_contains "$out" "Your full name" || return 1
  assert_contains "$out" "Bootstrap finished" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_an_empty_machine_pin_is_still_a_pin() {
  setup
  # `TEEUP_PACKAGE_MANAGER=""` in the machine file pins the backend to
  # detection. A non-emptiness test read it as "not pinned" and asked, and the
  # answer was then exported here and ignored everywhere else.
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEST_HOME/machines"
  printf 'TEEUP_PACKAGE_MANAGER=""\n' > "$TEST_HOME/machines/testmac.conf"
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<$'Ada Lovelace\nada@example.com\n1\ny\n')"
  assert_contains "$out" "Package manager is pinned to auto-detection by $TEST_HOME/machines/testmac.conf" || return 1
  assert_equals "0" "$(printf '%s\n' "$out" | grep -cx 'Package manager')" || return 1
  # The package-manager capability still records the backend it detected (an
  # answer the machine file keeps overriding to ""); what must not happen is
  # the question, and the prompt-line count above is what proves it.
  assert_contains "$out" "Bootstrap finished" || return 1
  cleanup_test_env
}

test_wizard_does_not_ask_for_a_pinned_theme() {
  setup
  # Whatever the wizard recorded, answers_load would apply the machine file's
  # TEEUP_THEME last, so the question would be answered and then ignored.
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEST_HOME/machines"
  printf 'TEEUP_THEME="catppuccin"\n' > "$TEST_HOME/machines/testmac.conf"
  # The wizard input minus the theme line.
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<$'1\nAda Lovelace\nada@example.com\ny\n')"
  assert_contains "$out" "Theme is pinned to catppuccin by $TEST_HOME/machines/testmac.conf; not asking." || return 1
  assert_equals "0" "$(printf '%s\n' "$out" | grep -cx 'Theme')" "the theme question was asked" || return 1
  assert_not_contains "$out" "Would set TEEUP_THEME" || return 1
  assert_not_contains "$out" "Skipping the daily tier (TEEUP_DAILY=no)" "the daily answer lined up with its question" || return 1
  assert_contains "$out" "Bootstrap finished" || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

test_skip_daily_and_daily_no_skip_the_tier() {
  setup
  local out
  out="$("$BOOT" --dry-run --skip-daily <<<"$WIZARD_INPUT")"
  assert_contains "$out" "Skipping the daily tier" || return 1
  cleanup_test_env
}

test_teeup_skip_skips_a_core_capability() {
  setup
  local out
  out="$(TEEUP_SKIP=dev-dirs "$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")"
  assert_contains "$out" "Skipping dev-dirs (TEEUP_SKIP)" || return 1
  assert_not_contains "$out" "Completed: dev-dirs configure" || return 1
  cleanup_test_env
}

test_core_failure_aborts() {
  setup
  mock_command sw_vers 0 "12.7.1"   # MacPorts path, port missing -> package-manager fails
  local rc=0 out
  out="$("$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")" || rc=$?
  assert_equals "1" "$rc" || return 1
  assert_contains "$out" "Core capability package-manager failed" || return 1
  assert_not_contains "$out" "Completed: dev-dirs configure" || return 1
  cleanup_test_env
}

# AeroSpace's own README floor (macOS 13+) is stricter than package-manager's
# MacPorts-vs-Homebrew line (macOS 12 or older). On a macOS 12 machine that
# still answers Homebrew explicitly (bypassing package-manager's own MacPorts
# auto-pick, so this test is isolated to aerospace's own floor), aerospace
# must say so and skip cleanly rather than aborting the run core failures do.
test_aerospace_not_applicable_completes_bootstrap() {
  setup
  mock_command sw_vers 0 "12.7.6"
  # ask_package_manager's "detected" option is macports on this mocked OS
  # (macos_major <= 12), so "2" (the other option) is the explicit Homebrew
  # choice here, not "1" as on the modern Mac WIZARD_INPUT assumes.
  local rc=0 out
  out="$("$BOOT" --dry-run 2>&1 <<<$'2\nAda Lovelace\nada@example.com\n1\ny\n')" || rc=$?
  assert_success "$rc" "an unsupported capability must not abort bootstrap" || return 1
  assert_contains "$out" "AeroSpace requires macOS 13 or newer; this Mac is on macOS 12, so there is nothing to install." || return 1
  assert_contains "$out" "AeroSpace requires macOS 13 or newer; this Mac is on macOS 12, so there is nothing to configure." || return 1
  assert_contains "$out" "Would record state: na/cap-aerospace" || return 1
  assert_not_contains "$out" "Would record state: done/cap-aerospace" || return 1
  assert_contains "$out" "Bootstrap finished" || return 1
  cleanup_test_env
}

test_empty_personal_email_reprompts_and_second_answer_is_recorded() {
  setup
  # F2: the wizard used to accept an empty personal email outright. Now it
  # must re-prompt, and the second (valid) answer is what flows downstream --
  # proved through ssh configure's own dry-run preview of the ssh-keygen
  # command it would run. That is run_cmd's built-in "Would execute" line
  # (a preview, not a claim of completion), so unlike git configure's
  # identity summary it is correctly still visible under DRY_RUN after the
  # F1 sweep fix.
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<$'1\nAda Lovelace\n\nada@example.com\n1\ny\n')"
  assert_contains "$out" "email address is required" || return 1
  assert_contains "$out" "Would execute: ssh-keygen -t ed25519 -C ada@example.com -f $TEST_HOME/.ssh/id_ed25519_personal" || return 1
  assert_contains "$out" "Bootstrap finished" || return 1
  cleanup_test_env
}

test_valid_wizard_answers_pass_validation_on_the_first_try() {
  setup
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")"
  assert_not_contains "$out" "email address is required" || return 1
  assert_not_contains "$out" "does not look like an email address" || return 1
  # Each prompt must fire exactly once: a spurious re-prompt would consume the
  # next line of input meant for a later question and desync the whole wizard.
  assert_equals "1" "$(printf '%s\n' "$out" | grep -c 'Personal email (your git identity')" || return 1
  assert_contains "$out" "Bootstrap finished" || return 1
  cleanup_test_env
}

test_the_retry_limit_dies_with_a_clear_message() {
  setup
  local rc=0 out
  out="$("$BOOT" --dry-run 2>&1 <<<$'1\nAda Lovelace\n\nnotanemail\nstill@bad\n')" || rc=$?
  assert_equals "1" "$rc" || return 1
  assert_contains "$out" "Too many invalid answers" || return 1
  assert_contains "$out" "Personal email" "the message names the question that failed" || return 1
  assert_not_contains "$out" "Bootstrap finished" || return 1
  cleanup_test_env
}

# Sourcing all of bootstrap would run its top-level flow (argument parsing,
# the xcode-clt/package-manager/wizard steps), so only the wizard validator
# functions are extracted and eval'd -- the same functions wizard_ask
# actually calls, not a reimplementation of them. lib/core.sh supplies warn,
# which every validator's failure path calls.
source_wizard_validators() {
  # all.sh, not core.sh alone: _wizard_valid_email is the wizard's contract
  # over email_valid, which lives in lib/answers.sh.
  source "$TEEUP_PATH/lib/all.sh"
  eval "$(sed -n '/^_wizard_valid_name() {/,/^wizard() {/p' "$BOOT" | sed '$d')"
}

# B2: the old wizard wrote TEEUP_WORK_EMAIL into the answers file. The new one
# neither asks for it nor reads it, so a leftover answer would sit there
# forever with no supported way to remove it. Running the wizard clears it.
# Only the wizard's own functions are extracted and eval'd (see
# source_wizard_validators above for why): sourcing all of bootstrap would run
# its whole install flow.
source_wizard() {
  local f body
  source "$TEEUP_PATH/lib/all.sh"
  # wizard_ask's retry limit, normally set at bootstrap's top level.
  # shellcheck disable=SC2034
  WIZARD_MAX_TRIES=3
  for f in wizard_ask _wizard_valid_name _wizard_valid_email wizard; do
    # The extraction lands in a variable before eval sees it: bash 3.2
    # mis-parses `eval "$(sed -n "/^$f() {/..." ...)"` and hands sed a
    # truncated expression.
    body="$(sed -n "/^$f() {/,/^}/p" "$BOOT")"
    eval "$body"
  done
  export TEEUP_NO_GUM=1
}

test_the_wizard_clears_a_stale_work_email() {
  setup
  source_wizard
  mkdir -p "$TEST_HOME/.config/teeup"
  {
    printf 'TEEUP_EMAIL="ada@example.com"\n'
    printf 'TEEUP_NAME="Ada Lovelace"\n'
    printf 'TEEUP_WORK_EMAIL="ada@corp.example"\n'
  } > "$TEST_HOME/.config/teeup/answers"
  answers_load
  local out
  # name, email, theme choice, daily confirm.
  out="$(DRY_RUN=false wizard 2>&1 <<<$'Ada Lovelace\nada@example.com\n1\ny\n')"
  assert_contains "$out" "Removed the old TEEUP_WORK_EMAIL answer" || return 1
  assert_not_contains "$(cat "$TEST_HOME/.config/teeup/answers")" "TEEUP_WORK_EMAIL" || return 1
  assert_contains "$(cat "$TEST_HOME/.config/teeup/answers")" 'TEEUP_EMAIL="ada@example.com"' || return 1
  cleanup_test_env
}

test_the_wizard_says_nothing_about_work_on_a_clean_answers_file() {
  setup
  source_wizard
  mkdir -p "$TEST_HOME/.config/teeup"
  printf 'TEEUP_EMAIL="ada@example.com"\n' > "$TEST_HOME/.config/teeup/answers"
  answers_load
  local out
  out="$(DRY_RUN=false wizard 2>&1 <<<$'Ada Lovelace\nada@example.com\n1\ny\n')"
  assert_not_contains "$out" "TEEUP_WORK_EMAIL" || return 1
  cleanup_test_env
}

test_wizard_email_validator_rejects_a_trailing_dot() {
  setup
  source_wizard_validators
  local rc=0 out
  out="$(_wizard_valid_email "ada@example.com." 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "ends with a dot" || return 1
  cleanup_test_env
}
test_wizard_email_validator_still_accepts_a_normal_address() {
  setup
  source_wizard_validators
  assert_equals "ada@example.com" "$(_wizard_valid_email "ada@example.com")" || return 1
  cleanup_test_env
}

# Minor review fix: _wizard_valid_name checked a trimmed value for
# emptiness but printed (and so stored) the original, untrimmed candidate.
test_wizard_name_validator_stores_the_trimmed_value() {
  setup
  source_wizard_validators
  assert_equals "Ada Lovelace" "$(_wizard_valid_name "  Ada Lovelace  ")" || return 1
  cleanup_test_env
}
test_dry_run_summary_is_a_preview_not_a_status_suggestion() {
  setup
  # F1: the closing summary used to tell the user to run `teeup status`, which
  # does not exist after a dry run (nothing was installed or linked).
  local out
  out="$("$BOOT" --dry-run <<<"$WIZARD_INPUT")"
  assert_contains "$out" "Bootstrap finished" || return 1
  assert_contains "$out" "This was a dry run: nothing was installed or written." || return 1
  assert_not_contains "$out" "teeup status" || return 1
  cleanup_test_env
}

test_dry_run_answers_take_effect() {
  setup
  local out wizard_no_daily
  wizard_no_daily=$'1\nAda Lovelace\nada@example.com\n1\nn\n'
  out="$("$BOOT" --dry-run <<<"$wizard_no_daily")"
  assert_contains "$out" "Skipping the daily tier (TEEUP_DAILY=no)" || return 1
  cleanup_test_env
}

test_dry_run_walks_the_daily_tier() {
  setup
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")"
  assert_contains "$out" "Completed: emacs install" || return 1
  assert_contains "$out" "Completed: emacs configure" || return 1
  assert_contains "$out" "Would install $TEST_HOME/.config/emacs/init.el" "the default flavor is the starter" || return 1
  cleanup_test_env
}

test_dry_run_walks_the_daily_tier_in_order() {
  setup
  local out e z f o
  out="$("$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")"
  e="$(printf '%s\n' "$out" | grep -n 'Completed: emacs configure' | head -1 | cut -d: -f1)"
  z="$(printf '%s\n' "$out" | grep -n 'Completed: zed configure' | head -1 | cut -d: -f1)"
  f="$(printf '%s\n' "$out" | grep -n 'Completed: firefox-developer-edition configure' | head -1 | cut -d: -f1)"
  o="$(printf '%s\n' "$out" | grep -n 'Completed: obsidian configure' | head -1 | cut -d: -f1)"
  [[ -n "$e" && -n "$z" && -n "$f" && -n "$o" ]] || { echo "a daily capability did not complete:"; printf '%s\n' "$out"; return 1; }
  [[ "$e" -lt "$z" && "$z" -lt "$f" && "$f" -lt "$o" ]] || { echo "the daily tier ran out of order"; return 1; }
  assert_not_contains "$out" "Starting: chrome install" "chrome is lazy" || return 1
  assert_not_contains "$out" "Starting: neovim install" "neovim is lazy" || return 1
  assert_not_contains "$out" "Starting: vscode install" "vscode is lazy" || return 1
  cleanup_test_env
}

test_wizard_records_the_emacs_flavor() {
  setup
  # Option 2 after "y" is doom (the current answer, starter, is offered first).
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<$'1\nAda Lovelace\nada@example.com\n1\ny\n2\n')"
  assert_contains "$out" "Would set TEEUP_EMACS_FLAVOR" || return 1
  assert_contains "$out" "git clone --depth 1 https://github.com/doomemacs/core $TEST_HOME/.config/emacs" "the answer reached emacs configure in the same run" || return 1
  cleanup_test_env
}

test_wizard_does_not_ask_the_flavor_without_the_daily_tier() {
  setup
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<$'1\nAda Lovelace\nada@example.com\n1\nn\n')"
  assert_equals "0" "$(printf '%s\n' "$out" | grep -c 'Emacs flavor')" "the flavor question was asked" || return 1
  assert_not_contains "$out" "Would set TEEUP_EMACS_FLAVOR" || return 1
  cleanup_test_env
}

test_wizard_does_not_ask_for_a_pinned_flavor() {
  setup
  export TEEUP_MACHINES_DIR="$TEST_HOME/machines"
  mkdir -p "$TEST_HOME/machines"
  printf 'TEEUP_EMACS_FLAVOR="none"\n' > "$TEST_HOME/machines/testmac.conf"
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")"
  assert_contains "$out" "Emacs flavor is pinned to none by $TEST_HOME/machines/testmac.conf; not asking." || return 1
  assert_not_contains "$out" "Would set TEEUP_EMACS_FLAVOR" || return 1
  assert_contains "$out" "TEEUP_EMACS_FLAVOR=none: leaving your Emacs configuration alone." || return 1
  unset TEEUP_MACHINES_DIR
  cleanup_test_env
}

echo "bootstrap"
run_test "refuses non-macOS" test_refuses_non_macos
run_test "refuses root" test_refuses_root
run_test "unknown flag exits 2" test_unknown_flag_exits_2
run_test "dry run walks core tier in order" test_dry_run_walks_core_tier_in_order
run_test "the theme is rendered once" test_the_theme_is_rendered_once
run_test "the package manager is asked before it is installed" test_the_package_manager_is_asked_before_it_is_installed
run_test "choosing macports runs the MacPorts path" test_choosing_macports_runs_the_macports_path
run_test "git is reconfigured after ssh makes the keys" test_git_is_reconfigured_after_ssh_makes_the_keys
run_test "post-bootstrap hooks run before the summary" test_post_bootstrap_hooks_run_before_the_summary
run_test "a fresh bootstrap marks every migration without running it" test_a_fresh_bootstrap_marks_every_migration_without_running_it
run_test "a second bootstrap changes nothing" test_a_second_bootstrap_changes_nothing
run_test "dry run touches nothing" test_dry_run_touches_nothing
run_test "existing answers skip wizard" test_existing_answers_skip_wizard
run_test "wizard runs when only backend recorded" test_wizard_runs_when_only_backend_recorded
run_test "--reconfigure reruns wizard" test_reconfigure_reruns_wizard
run_test "--reconfigure does not ask for a pinned package manager" test_reconfigure_does_not_ask_for_a_pinned_package_manager
run_test "an empty machine pin is still a pin" test_an_empty_machine_pin_is_still_a_pin
run_test "the wizard does not ask for a pinned theme" test_wizard_does_not_ask_for_a_pinned_theme
run_test "--skip-daily skips the tier" test_skip_daily_and_daily_no_skip_the_tier
run_test "TEEUP_SKIP skips a core capability" test_teeup_skip_skips_a_core_capability
run_test "core failure aborts" test_core_failure_aborts
run_test "aerospace not-applicable completes bootstrap" test_aerospace_not_applicable_completes_bootstrap
run_test "empty personal email re-prompts and the second answer is recorded" test_empty_personal_email_reprompts_and_second_answer_is_recorded
run_test "valid wizard answers pass validation on the first try" test_valid_wizard_answers_pass_validation_on_the_first_try
run_test "the retry limit dies with a clear message" test_the_retry_limit_dies_with_a_clear_message
run_test "the wizard clears a stale work email" test_the_wizard_clears_a_stale_work_email
run_test "the wizard says nothing about work on a clean answers file" test_the_wizard_says_nothing_about_work_on_a_clean_answers_file
run_test "wizard email validator rejects a trailing dot" test_wizard_email_validator_rejects_a_trailing_dot
run_test "wizard email validator still accepts a normal address" test_wizard_email_validator_still_accepts_a_normal_address
run_test "wizard name validator stores the trimmed value" test_wizard_name_validator_stores_the_trimmed_value
run_test "dry run summary is a preview, not a status suggestion" test_dry_run_summary_is_a_preview_not_a_status_suggestion
run_test "dry run answers take effect" test_dry_run_answers_take_effect
run_test "dry run walks the daily tier" test_dry_run_walks_the_daily_tier
run_test "dry run walks the daily tier in order" test_dry_run_walks_the_daily_tier_in_order
run_test "the wizard records the Emacs flavor" test_wizard_records_the_emacs_flavor
run_test "the wizard does not ask the flavor without the daily tier" test_wizard_does_not_ask_the_flavor_without_the_daily_tier
run_test "the wizard does not ask for a pinned flavor" test_wizard_does_not_ask_for_a_pinned_flavor
print_summary
