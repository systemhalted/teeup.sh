#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  # A mise that knows nothing yet. `mise-tools` is the global mise.toml's tool
  # list, written by `mise use -g` and read back by `mise ls --global`;
  # `mise-local-tools` is what a project directory's own config contributes,
  # which `mise which` sees and `mise ls --global` must not.
  mock_command_script mise <<'EOF2'
case "$1 ${2:-}" in
  "ls --global"|"ls -g")
    [ -f "$HOME/mise-tools" ] && awk '{print $1 " latest ~/.config/mise/config.toml"}' "$HOME/mise-tools"
    ;;
  "ls "*|"ls")
    cat "$HOME/mise-tools" "$HOME/mise-local-tools" 2>/dev/null || true
    ;;
  *)
    case "$1" in
      which)
        cat "$HOME/mise-tools" "$HOME/mise-local-tools" 2>/dev/null | grep -q "^$2\$" || exit 1
        ;;
      use) shift 2; printf '%s\n' "$1" >> "$HOME/mise-tools" ;;
      *) : ;;
    esac
    ;;
esac
exit 0
EOF2
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_gets_mise() {
  setup
  export TEEUP_TEST_MISSING="mise"
  local out
  out="$(DRY_RUN=true "$TEEUP" install mise 2>&1)"
  assert_contains "$out" "Would execute: brew install mise" || return 1
  cleanup_test_env
}

test_configure_writes_the_config_and_the_setting() {
  setup
  DRY_RUN=false "$TEEUP" configure mise >/dev/null 2>&1
  assert_file_exists "$TEST_HOME/.config/mise/config.toml" || return 1
  local body
  body="$(cat "$TEST_HOME/.config/mise/config.toml")"
  assert_contains "$body" "idiomatic_version_file_enable_tools = []" || return 1
  assert_contains "$body" "experimental = false" || return 1
  # auto_prune ships inside the copied file itself now, so configure never
  # mutates the file copy_config_once just installed (that used to make
  # every run after the first look user-edited from teeup's point of view).
  assert_not_contains "$(cat "$MOCK_LOG")" "settings set" || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import sys
try:
    import tomllib
except ImportError:
    sys.exit(0)
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
if data["settings"]["upgrade"]["auto_prune"] is not False:
    sys.exit(1)
' "$TEST_HOME/.config/mise/config.toml" || { echo "settings.upgrade.auto_prune is not false"; return 1; }
  fi
  cleanup_test_env
}

test_configure_installs_pre_commit_once() {
  setup
  DRY_RUN=false "$TEEUP" configure mise >/dev/null 2>&1
  assert_contains "$(cat "$MOCK_LOG")" "mise use -g pre-commit" || return 1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure mise 2>&1)"
  assert_contains "$out" "Already installed through mise: pre-commit" || return 1
  cleanup_test_env
}

test_configure_ignores_a_project_local_pre_commit() {
  setup
  # A directory whose own mise config asks for pre-commit. `mise which
  # pre-commit` succeeds there, which used to make teeup skip the global
  # install and leave pre-commit missing everywhere else on the machine.
  printf 'pre-commit\n' > "$TEST_HOME/mise-local-tools"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure mise 2>&1)"
  assert_not_contains "$out" "Already installed through mise: pre-commit" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise use -g pre-commit" || return 1
  cleanup_test_env
}

test_configure_falls_back_to_the_global_config_file() {
  setup
  # A mise too old for `mise ls --global` exits non-zero on the flag; the
  # global config file teeup wrote is then the only place to look.
  mock_command_script mise <<'EOF2'
case "$1 ${2:-}" in
  "ls --global") exit 1 ;;
  *) : ;;
esac
exit 0
EOF2
  DRY_RUN=false "$TEEUP" configure mise >/dev/null 2>&1
  assert_contains "$(cat "$MOCK_LOG")" "mise use -g pre-commit" || return 1
  printf 'pre-commit = "latest"\n' >> "$TEST_HOME/.config/mise/config.toml"
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure mise 2>&1)"
  assert_contains "$out" "Already installed through mise: pre-commit" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "mise use -g" || return 1
  cleanup_test_env
}

test_configure_ships_an_empty_tools_table() {
  setup
  DRY_RUN=false "$TEEUP" configure mise >/dev/null 2>&1
  # The [tools] table is the last line of the shipped file: no runtime is
  # installed at bootstrap, they arrive through `teeup install dev-env`.
  assert_equals "[tools]" "$(tail -1 "$TEST_HOME/.config/mise/config.toml")" || return 1
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  DRY_RUN=true "$TEEUP" configure mise >/dev/null 2>&1
  [[ ! -e "$TEST_HOME/.config/mise/config.toml" ]] || { echo "written in dry run"; return 1; }
  cleanup_test_env
}

echo "capabilities/mise"
run_test "install gets mise" test_install_gets_mise
run_test "configure writes the config and the setting" test_configure_writes_the_config_and_the_setting
run_test "configure installs pre-commit once" test_configure_installs_pre_commit_once
run_test "configure ignores a project-local pre-commit" test_configure_ignores_a_project_local_pre_commit
run_test "configure falls back to the global config file" test_configure_falls_back_to_the_global_config_file
run_test "configure ships an empty tools table" test_configure_ships_an_empty_tools_table
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
print_summary
