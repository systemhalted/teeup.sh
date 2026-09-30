#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/helper.sh"

setup() {
  setup_test_env
}

test_suite_timeouts_kill_the_suite_and_carry_on() {
  setup

  local copy="$TEST_HOME/checkout"
  mkdir -p "$copy/tests/capabilities" "$copy/tests/lib"

  # Copy enough to make run.sh work
  cp -p "$TEEUP_PATH/tests/helper.sh" "$copy/tests/helper.sh"
  cp -p "$TEEUP_PATH/tests/run.sh" "$TEEUP_PATH/tests/sandbox.sh" "$copy/tests/"

  # The runner will test these two files
  printf '#!/usr/bin/env bash\nsleep 10\n' > "$copy/tests/capabilities/sleeps.sh"
  chmod +x "$copy/tests/capabilities/sleeps.sh"

  printf '#!/usr/bin/env bash\necho "Other suite ran"\n' > "$copy/tests/capabilities/other.sh"
  chmod +x "$copy/tests/capabilities/other.sh"

  local rc=0 out=""
  out="$(cd "$copy" && TEEUP_TEST_SUITE_TIMEOUT=2 ./tests/run.sh 2>&1)" || rc=$?

  assert_failure "$rc" || return 1
  assert_contains "$out" "TIMEOUT: tests/capabilities/sleeps.sh after 2s" "timeout must print correctly: $out" || return 1
  assert_contains "$out" "Other suite ran" "other suites must still run: $out" || return 1
  assert_contains "$out" "1 of 2 suites failed." "summary must be correct: $out" || return 1

  cleanup_test_env
}


test_bootstrap_suite_gets_a_longer_timeout() {
  setup

  local copy="$TEST_HOME/checkout"
  mkdir -p "$copy/tests"

  cp -p "$TEEUP_PATH/tests/helper.sh" "$copy/tests/helper.sh"
  cp -p "$TEEUP_PATH/tests/run.sh" "$TEEUP_PATH/tests/sandbox.sh" "$copy/tests/"

  # bootstrap.sh spawns a real subprocess tree per test and is legitimately
  # slower than every other suite by design (tests/run.sh's own worker-pool
  # comment says so); it gets a longer default timeout than the 600s every
  # other suite uses, so a slow CI runner does not kill a suite that is only
  # slow, not hung. A sleep between the two timeouts proves it.
  printf '#!/usr/bin/env bash\nsleep 3\necho "bootstrap suite ran"\n' > "$copy/tests/bootstrap.sh"
  chmod +x "$copy/tests/bootstrap.sh"

  local rc=0 out=""
  out="$(cd "$copy" && TEEUP_TEST_SUITE_TIMEOUT=1 TEEUP_TEST_BOOTSTRAP_TIMEOUT=10 ./tests/run.sh 2>&1)" || rc=$?

  assert_success "$rc" "$out" || return 1
  assert_contains "$out" "bootstrap suite ran" "bootstrap.sh must be allowed to finish: $out" || return 1
  assert_not_contains "$out" "TIMEOUT: tests/bootstrap.sh" "bootstrap.sh must not use the short default: $out" || return 1

  cleanup_test_env
}

test_inherited_real_home_paths_are_scrubbed_before_a_suite_runs() {
  setup

  local copy="$TEST_HOME/checkout"
  local real_home="$TEST_HOME/real-home"
  local suite="$copy/tests/capabilities/inherited-path.sh"
  mkdir -p "$copy/tests/capabilities" "$real_home"
  cp -p "$TEEUP_PATH/tests/helper.sh" "$TEEUP_PATH/tests/sandbox.sh" \
    "$TEEUP_PATH/tests/sandbox-run.sh" "$copy/tests/"

  mock_command_script shellenv <<'EOF'
case "$1" in
  install) exit 0 ;;
  create)
    mkdir -p .shellenv/teeup
    : > .shellenv/teeup/metadata.json
    exit 0
    ;;
  exec)
    shift 2
    while [[ "$1" != "--" ]]; do shift; done
    shift
    export SHELLENV_ACTIVE=1
    export HOME="$TEST_HOME/shellenv-home"
    mkdir -p "$HOME"
    exec "$@"
    ;;
esac
exit 2
EOF

  cat > "$suite" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

if [[ -n "${DOCKER_CONFIG:-}" ]]; then
  mkdir -p "$DOCKER_CONFIG"
  : > "$DOCKER_CONFIG/touched-real-home"
fi
EOF
  chmod +x "$suite"

  local rc=0 out=""
  out="$(env -u SHELLENV_ACTIVE -u GITHUB_ACTIONS HOME="$real_home" \
    DOCKER_CONFIG="$real_home/.docker" bash "$suite" 2>&1)" || rc=$?

  assert_success "$rc" "$out" || return 1
  [[ ! -e "$real_home/.docker/touched-real-home" ]] || {
    echo "an inherited DOCKER_CONFIG wrote outside the shellenv sandbox"
    return 1
  }

  cleanup_test_env
}

test_setup_test_env_clears_inherited_path_overrides() {
  local inherited_root
  inherited_root="$(mktemp -d)"
  export DOCKER_CONFIG="$inherited_root/docker"
  export ZDOTDIR="$inherited_root/zsh"
  export GNUPGHOME="$inherited_root/gnupg"
  export CARGO_HOME="$inherited_root/cargo"
  export MISE_DATA_DIR="$inherited_root/mise"
  export FPATH="$inherited_root/zsh-functions"
  export SSH_AUTH_SOCK="$inherited_root/agent.sock"
  export TEEUP_LOG_FILE="$inherited_root/teeup.log"

  setup

  local var
  for var in DOCKER_CONFIG ZDOTDIR GNUPGHOME CARGO_HOME MISE_DATA_DIR FPATH SSH_AUTH_SOCK TEEUP_LOG_FILE; do
    if [[ -n "${!var+x}" ]]; then
      echo "setup_test_env left inherited $var=${!var}"
      return 1
    fi
  done

  cleanup_test_env
  rmdir "$inherited_root"
}

run_test "a hung test suite times out" test_suite_timeouts_kill_the_suite_and_carry_on
run_test "the bootstrap suite gets a longer timeout" test_bootstrap_suite_gets_a_longer_timeout
run_test "inherited real-home paths are scrubbed before a suite runs" test_inherited_real_home_paths_are_scrubbed_before_a_suite_runs
run_test "setup_test_env clears inherited path overrides" test_setup_test_env_clears_inherited_path_overrides

print_summary
