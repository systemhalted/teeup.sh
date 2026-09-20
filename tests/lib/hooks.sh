#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  # A config directory with a space, a dollar sign, a quote and an ampersand:
  # hook paths reach run_logged, bash and the log line as data, never as code.
  export XDG_CONFIG_HOME="$TEST_HOME/con fig \$HOME 'q' & co"
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false
  HOOKS="$XDG_CONFIG_HOME/teeup/hooks"
}

# make_hook <event> <file name> <body>
make_hook() {
  mkdir -p "$HOOKS/$1.d"
  printf '#!/usr/bin/env bash\n%s\n' "$3" > "$HOOKS/$1.d/$2"
}

test_run_executes_every_hook_in_name_order_with_its_arguments() {
  setup
  make_hook theme-set 20-second.sh 'echo "second:$1:$TEEUP_HOOK_EVENT"'
  make_hook theme-set 10-first.sh 'echo "first:$1:$#"'
  local out first second
  out="$(hook_run theme-set "tokyo night" 2>&1)"
  assert_contains "$out" "first:tokyo night:1" || return 1
  assert_contains "$out" "second:tokyo night:theme-set" || return 1
  first="$(printf '%s\n' "$out" | grep -n 'first:' | cut -d: -f1)"
  second="$(printf '%s\n' "$out" | grep -n 'second:' | cut -d: -f1)"
  [[ "$first" -lt "$second" ]] || { echo "10-first.sh must run before 20-second.sh"; return 1; }
  cleanup_test_env
}

test_run_skips_samples_and_runs_a_hook_without_the_executable_bit() {
  setup
  make_hook post-update example.sample 'echo "sample ran"'
  make_hook post-update plain.sh 'echo "plain ran"'
  chmod 644 "$HOOKS/post-update.d/plain.sh"
  local out
  out="$(hook_run post-update 2>&1)"
  assert_not_contains "$out" "sample ran" || return 1
  assert_contains "$out" "plain ran" "hooks run with bash, so no chmod is needed" || return 1
  cleanup_test_env
}

# The hook FILE name, not just the directory: a name with spaces, a dollar
# sign, a quote and an ampersand must run as one file, never be re-split or
# evaluated.
test_a_hook_filename_with_metacharacters_runs() {
  setup
  make_hook theme-set "my hook \$X 'q' & co.sh" 'echo "ran:$1"'
  local out
  out="$(hook_run theme-set tokyo 2>&1)"
  assert_contains "$out" "ran:tokyo" || return 1
  assert_not_contains "$out" "No such file" || return 1
  cleanup_test_env
}

test_a_failing_hook_warns_and_the_rest_still_run() {
  setup
  make_hook post-bootstrap 10-broken.sh 'echo "broken ran"; exit 3'
  make_hook post-bootstrap 20-fine.sh 'echo "fine ran"'
  local out rc=0
  out="$(hook_run post-bootstrap 2>&1)" || rc=$?
  assert_success "$rc" "a hook never fails its caller" || return 1
  assert_contains "$out" "broken ran" || return 1
  assert_contains "$out" "Hook $HOOKS/post-bootstrap.d/10-broken.sh failed (exit code 3); continuing." || return 1
  assert_contains "$out" "fine ran" || return 1
  cleanup_test_env
}

test_a_hook_cannot_read_the_terminal() {
  setup
  make_hook post-update ask.sh 'read -r answer || answer="<none>"; echo "answer:$answer"'
  local out
  out="$(printf 'yes\n' | hook_run post-update 2>&1)"
  assert_contains "$out" "answer:<none>" "stdin is /dev/null" || return 1
  cleanup_test_env
}

test_no_hook_directory_and_unknown_events_are_quiet() {
  setup
  local out rc=0
  out="$(hook_run theme-set catppuccin 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_equals "" "$out" || return 1
  out="$(hook_run pre-lunch 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "unknown event 'pre-lunch'" || return 1
  cleanup_test_env
}

test_dry_run_names_the_hooks_and_runs_none() {
  setup
  make_hook theme-set 10-touch.sh 'touch "$HOME/touched"'
  # shellcheck disable=SC2034  # last assignment in the file; read by hook_run
  DRY_RUN=true
  local out
  out="$(hook_run theme-set catppuccin)"
  assert_contains "$out" "[DRY-RUN] Would run hook: $HOOKS/theme-set.d/10-touch.sh catppuccin" || return 1
  [[ ! -e "$TEST_HOME/touched" ]] || { echo "a hook ran in dry run"; return 1; }
  cleanup_test_env
}

test_theme_set_runs_the_theme_set_hooks_with_the_name() {
  setup
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR"
  make_hook theme-set 10-name.sh 'echo "theme-set hook:$1"'
  mock_command defaults 1 ""
  local out
  out="$(theme_set catppuccin 2>&1)"
  assert_contains "$out" "theme-set hook:catppuccin" || return 1
  cleanup_test_env
}

echo "lib/hooks.sh"
run_test "run executes every hook in name order with its arguments" test_run_executes_every_hook_in_name_order_with_its_arguments
run_test "run skips samples and runs a hook without the executable bit" test_run_skips_samples_and_runs_a_hook_without_the_executable_bit
run_test "a hook filename with metacharacters runs" test_a_hook_filename_with_metacharacters_runs
run_test "a failing hook warns and the rest still run" test_a_failing_hook_warns_and_the_rest_still_run
run_test "a hook cannot read the terminal" test_a_hook_cannot_read_the_terminal
run_test "no hook directory and unknown events are quiet" test_no_hook_directory_and_unknown_events_are_quiet
run_test "dry run names the hooks and runs none" test_dry_run_names_the_hooks_and_runs_none
run_test "theme set runs the theme-set hooks with the name" test_theme_set_runs_the_theme_set_hooks_with_the_name
print_summary
