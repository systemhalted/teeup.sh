#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# The phase 3 gate: a shim round trip. `docker` is not on a fresh Mac, so on
# the harness PATH (MOCK_BIN, /usr/bin, /bin, /usr/sbin, /sbin) the shim is
# the only `docker` until the mocked brew "installs" a real one into
# REAL_BIN, a directory ahead of the shims on PATH the way /opt/homebrew/bin
# is. A Linux CI runner (and a developer's machine) can have docker in
# /usr/bin; hide_host_commands hides those copies by path, before any mock of
# the same name exists, so the mocked install is what provides them.
setup() {
  setup_test_env
  mock_macos_base
  hide_host_commands colima docker docker-compose
  REAL_BIN="$TEST_HOME/realbin"
  mkdir -p "$REAL_BIN"
  export REAL_BIN
  # brew install <formula> drops an executable of that name into REAL_BIN:
  # docker and docker-compose log their arguments and echo them; colima
  # keeps a stopped/running state behind `status` and `start`.
  mock_command_script brew <<'EOF2'
case "$1 ${2:-}" in
  "list "*) exit 1 ;;
  "install colima")
    printf '#!/usr/bin/env bash\necho "colima-real $*" >> "$MOCK_LOG"\ncase "$1" in\n  status) [ -f "$HOME/colima-running" ] || exit 1 ;;\n  start) touch "$HOME/colima-running" ;;\nesac\nexit 0\n' > "$REAL_BIN/colima"
    chmod +x "$REAL_BIN/colima"
    ;;
  "install "*)
    printf '#!/usr/bin/env bash\necho "%s-real $*" >> "$MOCK_LOG"\necho "%s ran: $*"\n' "$2" "$2" > "$REAL_BIN/$2"
    chmod +x "$REAL_BIN/$2"
    ;;
esac
exit 0
EOF2
  export TEEUP_NO_GUM=1
  TEEUP="$TEEUP_PATH/bin/teeup"
  SHIMS="$TEST_HOME/.local/state/teeup/shims"
}

# A colima already on PATH, stopped until `colima start` has been called.
mock_colima_stopped() {
  mock_command_script colima <<'EOF2'
case "$1" in
  status) [ -f "$HOME/colima-running" ] || exit 1 ;;
  start) touch "$HOME/colima-running" ;;
esac
exit 0
EOF2
}

test_install_dry_run_gets_colima_docker_and_compose() {
  setup
  local out
  out="$(DRY_RUN=true "$TEEUP" install colima 2>&1)"
  assert_contains "$out" "Would execute: brew install colima" || return 1
  assert_contains "$out" "Would execute: brew install docker" || return 1
  assert_contains "$out" "Would execute: brew install docker-compose" || return 1
  # Nothing was really installed, so configure has no colima to start.
  assert_contains "$out" "colima is not installed; start it later with: colima start" || return 1
  cleanup_test_env
}

test_install_on_macports_gets_the_compose_plugin_port() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  mock_command port 0 ""
  local out
  out="$(DRY_RUN=true "$TEEUP" install colima 2>&1)"
  assert_contains "$out" "Would execute: sudo port install colima" || return 1
  assert_contains "$out" "Would execute: sudo port install docker" || return 1
  # The docker-compose port is the retired Python 1.x tool; the plugin port
  # is Compose v2.
  assert_contains "$out" "Would execute: sudo port install docker-compose-plugin" || return 1
  if printf '%s\n' "$out" | grep -q 'port install docker-compose$'; then
    echo "the Python docker-compose port must not be installed"; return 1
  fi
  cleanup_test_env
}

test_configure_links_the_compose_plugin_once() {
  setup
  mock_colima_stopped
  local plugin="$TEEUP_PKG_PREFIX/lib/docker/cli-plugins/docker-compose"
  mkdir -p "$(dirname "$plugin")"
  printf '#!/bin/sh\n' > "$plugin"
  chmod +x "$plugin"
  DRY_RUN=false "$TEEUP" configure colima >/dev/null
  assert_equals "$plugin" "$(readlink "$TEST_HOME/.docker/cli-plugins/docker-compose")" || return 1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure colima)"
  assert_contains "$out" "Already linked: $TEST_HOME/.docker/cli-plugins/docker-compose" || return 1
  cleanup_test_env
}

test_configure_starts_colima_only_when_stopped() {
  setup
  mock_colima_stopped
  DRY_RUN=false "$TEEUP" configure colima >/dev/null
  assert_contains "$(cat "$MOCK_LOG")" "colima start" || return 1
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure colima)"
  assert_contains "$out" "Colima is running." || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "colima start" || return 1
  cleanup_test_env
}

test_configure_honours_docker_config() {
  setup
  mock_colima_stopped
  local plugin="$TEEUP_PKG_PREFIX/lib/docker/cli-plugins/docker-compose"
  mkdir -p "$(dirname "$plugin")"
  printf '#!/bin/sh\n' > "$plugin"
  export DOCKER_CONFIG="$TEST_HOME/docker config"
  DRY_RUN=false "$TEEUP" configure colima >/dev/null
  assert_equals "$plugin" "$(readlink "$DOCKER_CONFIG/cli-plugins/docker-compose")" || return 1
  [[ ! -e "$TEST_HOME/.docker" ]] || { echo "DOCKER_CONFIG must replace ~/.docker"; return 1; }
  unset DOCKER_CONFIG
  cleanup_test_env
}

# I5: HOMEBREW_PREFIX, not just the arch guess pkg_prefix makes, is where
# Homebrew itself resolves formula paths -- a custom prefix must be honoured,
# or a real Compose plugin there reads as absent.
test_configure_honours_homebrew_prefix() {
  setup
  mock_colima_stopped
  # TEEUP_PKG_PREFIX (set by setup_test_env) outranks HOMEBREW_PREFIX in
  # pkg_prefix, so drop it: this test is about what a user's own Homebrew
  # prefix does.
  unset TEEUP_PKG_PREFIX
  export HOMEBREW_PREFIX="$TEST_HOME/custombrew"
  local plugin="$HOMEBREW_PREFIX/lib/docker/cli-plugins/docker-compose"
  mkdir -p "$(dirname "$plugin")"
  printf '#!/bin/sh\n' > "$plugin"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure colima)"
  assert_not_contains "$out" "No Compose plugin" || return 1
  assert_equals "$plugin" "$(readlink "$TEST_HOME/.docker/cli-plugins/docker-compose")" || return 1
  unset HOMEBREW_PREFIX
  export TEEUP_PKG_PREFIX="$TEST_HOME/pkgprefix"
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  mock_colima_stopped
  local plugin="$TEEUP_PKG_PREFIX/lib/docker/cli-plugins/docker-compose"
  mkdir -p "$(dirname "$plugin")"
  printf '#!/bin/sh\n' > "$plugin"
  chmod +x "$plugin"
  local out
  out="$(DRY_RUN=true "$TEEUP" configure colima)"
  assert_contains "$out" "Would execute: colima start" || return 1
  assert_not_contains "$out" "Linked the docker compose plugin" || return 1
  [[ ! -e "$TEST_HOME/.docker" ]] || { echo "dry run wrote under ~/.docker"; return 1; }
  [[ ! -e "$TEST_HOME/colima-running" ]] || { echo "dry run started colima"; return 1; }
  cleanup_test_env
}

test_shims_exist_after_runtime_configure() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  assert_file_exists "$SHIMS/docker" || return 1
  assert_file_exists "$SHIMS/colima" || return 1
  [[ -x "$SHIMS/docker" ]] || { echo "docker shim must be executable"; return 1; }
  assert_contains "$(cat "$SHIMS/docker")" 'lazy-run colima docker "$@"' || return 1
  cleanup_test_env
}

test_round_trip_shim_installs_configures_and_execs_docker() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  # The shell's lookup, with real bin directories first and teeup's shims
  # last: before the install nothing but the shim answers to `docker`.
  # (/usr/bin is left out of this one lookup because a Linux runner has
  # docker there; `command -v` is a builtin and needs no PATH of its own.)
  assert_equals "$SHIMS/docker" "$(PATH="$MOCK_BIN:$REAL_BIN:$SHIMS" command -v docker)" || return 1
  # The PATH every command below runs with. The shim is named outright for
  # the same /usr/bin reason; hide_host_commands keeps teeup itself from
  # counting a host docker as installed.
  export PATH="$MOCK_BIN:$REAL_BIN:/usr/bin:/bin:/usr/sbin:/sbin:$SHIMS"
  local out
  out="$(printf 'y\n' | TEEUP_TEST_TTY=yes DRY_RUN=false "$SHIMS/docker" ps --all 2>&1)"
  assert_contains "$out" "docker is provided by capability colima. Install now?" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew install colima" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew install docker" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "brew install docker-compose" || return 1
  # configure ran after install and started the VM it had just installed.
  assert_contains "$(cat "$MOCK_LOG")" "colima-real start" || return 1
  assert_contains "$out" "Completed: colima configure" || return 1
  # The real docker ran, with the original arguments.
  assert_contains "$(cat "$MOCK_LOG")" "docker-real ps --all" || return 1
  assert_contains "$out" "docker ran: ps --all" || return 1
  "$TEEUP" has colima || { echo "colima must be marked installed"; return 1; }
  # After the install the same lookup finds the real docker ahead of the shim.
  assert_equals "$REAL_BIN/docker" "$(PATH="$MOCK_BIN:$REAL_BIN:$SHIMS" command -v docker)" || return 1
  # Second call through the shim: a real binary exists ahead of it now, so
  # lazy-run execs that at once, with nothing installed and nothing asked.
  : > "$MOCK_LOG"
  out="$(TEEUP_TEST_TTY=no "$SHIMS/docker" images 2>&1)"
  assert_equals "docker ran: images" "$out" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew" || return 1
  cleanup_test_env
}

test_round_trip_without_a_tty_exits_127_with_the_hint() {
  setup
  DRY_RUN=false "$TEEUP" configure teeup-runtime >/dev/null
  export PATH="$MOCK_BIN:$REAL_BIN:/usr/bin:/bin:/usr/sbin:/sbin:$SHIMS"
  local rc=0 out
  out="$(TEEUP_TEST_TTY=no "$SHIMS/docker" ps 2>&1)" || rc=$?
  assert_equals "127" "$rc" || return 1
  assert_contains "$out" "docker is not installed. It is provided by capability colima; run: teeup install colima" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "brew install" || return 1
  cleanup_test_env
}

echo "capabilities/colima"
run_test "install dry run gets colima, docker and compose" test_install_dry_run_gets_colima_docker_and_compose
run_test "install on macports gets the compose plugin port" test_install_on_macports_gets_the_compose_plugin_port
run_test "configure links the compose plugin once" test_configure_links_the_compose_plugin_once
run_test "configure starts colima only when stopped" test_configure_starts_colima_only_when_stopped
run_test "configure honours DOCKER_CONFIG" test_configure_honours_docker_config
run_test "configure honours HOMEBREW_PREFIX" test_configure_honours_homebrew_prefix
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "shims exist after runtime configure" test_shims_exist_after_runtime_configure
run_test "round trip: shim installs, configures and execs docker" test_round_trip_shim_installs_configures_and_execs_docker
run_test "round trip: without a tty exits 127 with the hint" test_round_trip_without_a_tty_exits_127_with_the_hint
print_summary
