#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/helper.sh"

BOOT="$TEEUP_PATH/bootstrap"

# Answers piped to the plain-read prompts, one per prompt. The package manager
# is asked first and on its own, before step 2 installs one; the rest is the
# wizard in step 4:
# package manager choice, name, email, work email, personal dir, work dir,
# theme choice, daily confirm.
# "1" is the detected backend (Homebrew on the mocked modern Mac), "2" the
# other one; for the theme choice, "1" is the first theme themes/ ships, i.e.
# catppuccin. The two empty lines after the work email accept the default
# personal and work project roots (F3).
WIZARD_INPUT=$'1\nAda Lovelace\nada@example.com\n\n\n\n1\ny\n'

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
  export TEEUP_TEST_MISSING="brew gum jq starship rg fd fzf bat eza zoxide yq btop tldr dust gpg delta git-lfs lazygit"
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
  out="$("$BOOT" --dry-run 2>&1 <<<$'2\nAda Lovelace\nada@example.com\n\n\n\n1\ny\n')"
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
  out="$("$BOOT" --dry-run --reconfigure 2>&1 <<<$'Ada Lovelace\nada@example.com\n\n\n\n1\ny\n')"
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
  out="$("$BOOT" --dry-run 2>&1 <<<$'Ada Lovelace\nada@example.com\n\n\n\n1\ny\n')"
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
  out="$("$BOOT" --dry-run 2>&1 <<<$'1\nAda Lovelace\nada@example.com\n\n\n\ny\n')"
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

test_empty_personal_email_reprompts_and_second_answer_is_recorded() {
  setup
  # F2: the wizard used to accept an empty personal email outright. Now it
  # must re-prompt, and the second (valid) answer is what git configure
  # actually uses -- the "git identity: ..." line is not gated by DRY_RUN
  # (files.sh swallows the rendered content, but this message is not one of
  # them), so it is the observable proof the retried answer was recorded.
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<$'1\nAda Lovelace\n\nada@example.com\n\n\n\n1\ny\n')"
  assert_contains "$out" "email address is required" || return 1
  assert_contains "$out" "git identity: ada@example.com for both ~/Personal and ~/Work" || return 1
  assert_contains "$out" "Bootstrap finished" || return 1
  cleanup_test_env
}

test_a_path_shaped_work_email_reprompts() {
  setup
  # The dry run's actual failure: a path typed into the work-email field was
  # accepted outright and would have become both the git identity address and
  # the -C comment of the work SSH key.
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<$'1\nAda Lovelace\nada@example.com\n~/Workspaces/Work\nada@corp.example\n\n\n1\ny\n')"
  assert_contains "$out" "does not look like an email address" || return 1
  assert_contains "$out" "git identities: personal (ada@example.com), work (ada@corp.example)" || return 1
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
  assert_equals "1" "$(printf '%s\n' "$out" | grep -c 'Personal email (git identity')" || return 1
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

test_personal_email_prompt_names_the_answered_personal_root() {
  setup
  # F3: the email prompts must name the answered root instead of the literal
  # "~/Personal" / "~/Work". On a first run there is no prior answer, so the
  # prompt falls back to identity_dir's own default -- the absolute path,
  # which under this test's mocked $HOME is $TEST_HOME/Personal.
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<"$WIZARD_INPUT")"
  assert_contains "$out" "Personal email (git identity under $TEST_HOME/Personal)" || return 1
  assert_contains "$out" "Work email (git identity under $TEST_HOME/Work" || return 1
  cleanup_test_env
}

test_custom_project_roots_reach_dev_dirs_and_git() {
  setup
  # The wizard's own two new questions (F3): a custom personal and work root
  # must be created by dev-dirs and named in the git identity message.
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<$'1\nAda Lovelace\nada@example.com\n\nMyPersonal\nWorkspaces/Work\n1\ny\n')"
  assert_contains "$out" "Would execute: mkdir -p $TEST_HOME/MyPersonal" || return 1
  assert_contains "$out" "Would execute: mkdir -p $TEST_HOME/Workspaces/Work" || return 1
  assert_contains "$out" "git identity: ada@example.com for both ~/MyPersonal and ~/Workspaces/Work" || return 1
  assert_contains "$out" "Bootstrap finished" || return 1
  cleanup_test_env
}

test_wizard_rejects_equal_project_roots() {
  setup
  # A path shaped answer that resolves to the same directory as the personal
  # root must re-prompt rather than leave both identities pointed at the same
  # place. "Personal" (bare) and "~/Personal" both resolve to the same
  # absolute path, so this also proves the equality check compares resolved,
  # not raw, values.
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<$'1\nAda Lovelace\nada@example.com\n\nPersonal\n~/Personal\nWork\n1\ny\n')"
  assert_contains "$out" "already the other project root" || return 1
  assert_contains "$out" "Bootstrap finished" || return 1
  cleanup_test_env
}

test_wizard_warns_but_accepts_a_root_outside_home() {
  setup
  local out
  out="$("$BOOT" --dry-run 2>&1 <<<$'1\nAda Lovelace\nada@example.com\n\n/opt/personal\nWork\n1\ny\n')"
  assert_contains "$out" "outside \$HOME" || return 1
  assert_contains "$out" "Would execute: mkdir -p /opt/personal" || return 1
  assert_contains "$out" "Bootstrap finished" || return 1
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
  wizard_no_daily=$'1\nAda Lovelace\nada@example.com\n\n\n\n1\nn\n'
  out="$("$BOOT" --dry-run <<<"$wizard_no_daily")"
  assert_contains "$out" "Skipping the daily tier (TEEUP_DAILY=no)" || return 1
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
run_test "empty personal email re-prompts and the second answer is recorded" test_empty_personal_email_reprompts_and_second_answer_is_recorded
run_test "a path-shaped work email re-prompts" test_a_path_shaped_work_email_reprompts
run_test "valid wizard answers pass validation on the first try" test_valid_wizard_answers_pass_validation_on_the_first_try
run_test "the retry limit dies with a clear message" test_the_retry_limit_dies_with_a_clear_message
run_test "personal email prompt names the answered personal root" test_personal_email_prompt_names_the_answered_personal_root
run_test "custom project roots reach dev-dirs and git" test_custom_project_roots_reach_dev_dirs_and_git
run_test "wizard rejects equal project roots" test_wizard_rejects_equal_project_roots
run_test "wizard warns but accepts a root outside HOME" test_wizard_warns_but_accepts_a_root_outside_home
run_test "dry run summary is a preview, not a status suggestion" test_dry_run_summary_is_a_preview_not_a_status_suggestion
run_test "dry run answers take effect" test_dry_run_answers_take_effect
print_summary
