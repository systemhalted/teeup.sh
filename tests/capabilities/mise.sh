#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  # A mise that knows nothing yet, keeping "requested" and "installed" apart
  # the way the real one does. `mise-tools` is the global mise.toml's tool
  # list (written by `mise use -g`, read back by `mise ls --global`, which
  # like the real command lists a requested tool whether or not it is
  # installed and marks the absent ones "(missing)"); `mise-installed` is what
  # is on disk (`mise use -g` and `mise install` add to it, `--installed` and
  # `mise where` consult it); `mise-local-tools` is what a project directory's
  # own config contributes, which `mise which` sees and `--global` must not.
  mock_command_script mise <<'EOF2'
# `-C /` pins the config stack to the global file; without it the mock, like
# the real mise, lets a project config in the cwd shadow a global request.
pinned=0
[ "$1" = "-C" ] && { pinned=1; shift 2; }
shadowed() { [ "$pinned" = "0" ] && grep -qx "$1" "$HOME/mise-local-tools" 2>/dev/null; }
case "$*" in
  "ls --global --installed"*)
    tool="${4:-}"
    [ -f "$HOME/mise-tools" ] || exit 0
    while read -r name; do
      [ -z "$tool" ] || [ "$name" = "$tool" ] || continue
      shadowed "$name" && continue
      if grep -qx "$name" "$HOME/mise-installed" 2>/dev/null; then
        printf '%s latest ~/.config/mise/config.toml latest\n' "$name"
      fi
    done < "$HOME/mise-tools"
    ;;
  "ls --global"*|"ls -g"*)
    [ -f "$HOME/mise-tools" ] || exit 0
    while read -r name; do
      shadowed "$name" && continue
      if grep -qx "$name" "$HOME/mise-installed" 2>/dev/null; then
        printf '%s latest ~/.config/mise/config.toml latest\n' "$name"
      else
        printf '%s latest (missing) ~/.config/mise/config.toml latest\n' "$name"
      fi
    done < "$HOME/mise-tools"
    ;;
  "ls"*)
    cat "$HOME/mise-tools" "$HOME/mise-local-tools" 2>/dev/null || true
    ;;
  "which "*)
    cat "$HOME/mise-tools" "$HOME/mise-local-tools" 2>/dev/null | grep -q "^$2\$" || exit 1
    ;;
  "where "*)
    grep -qx "$2" "$HOME/mise-installed" 2>/dev/null || exit 1
    ;;
  "use "*)
    shift 2
    printf '%s\n' "$1" >> "$HOME/mise-tools"
    printf '%s\n' "$1" >> "$HOME/mise-installed"
    ;;
  "install "*)
    printf '%s\n' "$2" >> "$HOME/mise-installed"
    ;;
  *) : ;;
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
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / use -g pre-commit" || return 1
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
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / use -g pre-commit" || return 1
  cleanup_test_env
}

test_configure_reinstalls_a_requested_but_missing_pre_commit() {
  setup
  # The global config still asks for pre-commit (an interrupted install, a
  # manual uninstall, a wiped MISE_DATA_DIR) but nothing is on disk. `mise ls
  # --global` lists it all the same, so reading that as "installed" left the
  # binary missing on every re-run.
  printf 'pre-commit\n' > "$TEST_HOME/mise-tools"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure mise 2>&1)"
  assert_not_contains "$out" "Already installed through mise: pre-commit" || return 1
  assert_contains "$out" "requested by the global mise config but not installed" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install pre-commit" || return 1
  # Not `mise use -g`: the request (and its pinned version) is already there.
  assert_not_contains "$(cat "$MOCK_LOG")" "mise -C / use -g" || return 1
  : > "$MOCK_LOG"
  out="$(DRY_RUN=false "$TEEUP" configure mise 2>&1)"
  assert_contains "$out" "Already installed through mise: pre-commit" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "mise -C / install" || return 1
  cleanup_test_env
}

test_configure_is_not_fooled_by_a_project_config_shadowing_the_global_one() {
  setup
  # pre-commit is requested globally and installed, and the directory teeup
  # is run from has its own mise.toml asking for pre-commit too. The real
  # `mise ls --global` then hides the global row (the project's request
  # shadows it), and a cwd-sensitive check concluded "not requested" and ran
  # `mise use -g`, rewriting the user's pinned global version on every run.
  printf 'pre-commit\n' > "$TEST_HOME/mise-tools"
  printf 'pre-commit\n' > "$TEST_HOME/mise-installed"
  printf 'pre-commit\n' > "$TEST_HOME/mise-local-tools"
  local out
  out="$(cd "$TEST_HOME" && DRY_RUN=false "$TEEUP" configure mise 2>&1)"
  assert_contains "$out" "Already installed through mise: pre-commit" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "mise -C / install" || return 1
  # And every mise call was pinned away from the cwd.
  assert_equals "0" "$(grep -c '^mise [^-]' "$MOCK_LOG" || true)" || return 1
  cleanup_test_env
}

test_configure_falls_back_to_mise_where_when_installed_is_unsupported() {
  setup
  # A mise with --global but not --installed rejects the flag; concluding
  # "not installed" from that would install on every run.
  mock_command_script mise <<'EOF2'
[ "$1" = "-C" ] && shift 2
case "$*" in
  "ls --global --installed"*) echo "error: unexpected argument '--installed' found" >&2; exit 2 ;;
  "ls --global"*) [ -f "$HOME/mise-tools" ] && awk '{print $1 " latest ~/.config/mise/config.toml"}' "$HOME/mise-tools" ;;
  "where "*) grep -qx "$2" "$HOME/mise-installed" 2>/dev/null || exit 1 ;;
  "use "*) shift 2; printf '%s\n' "$1" >> "$HOME/mise-tools"; printf '%s\n' "$1" >> "$HOME/mise-installed" ;;
  "install "*) printf '%s\n' "$2" >> "$HOME/mise-installed" ;;
  *) : ;;
esac
exit 0
EOF2
  printf 'pre-commit\n' > "$TEST_HOME/mise-tools"
  printf 'pre-commit\n' > "$TEST_HOME/mise-installed"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure mise 2>&1)"
  assert_contains "$out" "Already installed through mise: pre-commit" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "mise -C / install" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "use -g" || return 1
  rm -f "$TEST_HOME/mise-installed"
  : > "$MOCK_LOG"
  out="$(DRY_RUN=false "$TEEUP" configure mise 2>&1)"
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install pre-commit" || return 1
  cleanup_test_env
}

test_configure_falls_back_to_the_global_config_file() {
  setup
  # A mise too old for `mise ls --global` exits non-zero on the flag; the
  # global config file teeup wrote is then the only place to look for the
  # request, and `mise where` (which fails when nothing is installed) for
  # the binary.
  mock_command_script mise <<'EOF2'
[ "$1" = "-C" ] && shift 2
case "$*" in
  "ls --global"*) exit 1 ;;
  "where "*) grep -qx "$2" "$HOME/mise-installed" 2>/dev/null || exit 1 ;;
  "use "*) shift 2; printf '%s\n' "$1" >> "$HOME/mise-installed" ;;
  "install "*) printf '%s\n' "$2" >> "$HOME/mise-installed" ;;
  *) : ;;
esac
exit 0
EOF2
  DRY_RUN=false "$TEEUP" configure mise >/dev/null 2>&1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / use -g pre-commit" || return 1
  # Requested in the file but gone from disk: the fallback must not take the
  # config line as proof of a binary either.
  printf 'pre-commit = "latest"\n' >> "$TEST_HOME/.config/mise/config.toml"
  rm -f "$TEST_HOME/mise-installed"
  : > "$MOCK_LOG"
  local out
  out="$(DRY_RUN=false "$TEEUP" configure mise 2>&1)"
  assert_not_contains "$out" "Already installed through mise: pre-commit" || return 1
  assert_contains "$(cat "$MOCK_LOG")" "mise -C / install pre-commit" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "mise -C / use -g" || return 1
  : > "$MOCK_LOG"
  out="$(DRY_RUN=false "$TEEUP" configure mise 2>&1)"
  assert_contains "$out" "Already installed through mise: pre-commit" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "mise -C / use -g" || return 1
  assert_not_contains "$(cat "$MOCK_LOG")" "mise -C / install" || return 1
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

# The mise suite's own mock is driven by two files: $HOME/mise-tools is what
# the global config asks for, $HOME/mise-installed is what is on disk. Keeping
# them apart is the whole point of mise_global_state, so the doctor tests use
# the same mock rather than a second one that could drift from it.
seed_mise_shims() {
  export XDG_DATA_HOME="$TEST_HOME/.local/share"
  mkdir -p "$XDG_DATA_HOME/mise/shims"
  export PATH="$PATH:$XDG_DATA_HOME/mise/shims"
}

test_doctor_passes_on_a_configured_machine() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure mise >/dev/null 2>&1
  seed_mise_shims
  local rc=0 out
  out="$(DRY_RUN=false cap_run mise doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "pre-commit is installed through mise" || return 1
  assert_contains "$out" "mise shims directory is on PATH" || return 1
  cleanup_test_env
}

test_doctor_reports_a_missing_mise_and_config() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  hide_host_commands mise
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run mise doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "mise is not on PATH" || return 1
  assert_contains "$(cat "$report")" "teeup install mise" || return 1
  cleanup_test_env
}

test_doctor_reports_pre_commit_requested_but_not_installed() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure mise >/dev/null 2>&1
  seed_mise_shims
  # The global config still asks for pre-commit; the binary is gone, which is
  # what an interrupted install or a wiped MISE_DATA_DIR leaves behind.
  : > "$TEST_HOME/mise-installed"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run mise doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "pre-commit is asked for but not installed" || return 1
  assert_contains "$(cat "$report")" "teeup configure mise" || return 1
  cleanup_test_env
}

# Unreadable is not missing: the file is plainly there, and telling the user
# to run `teeup configure mise` over a permissions problem sends them to do
# something that will not help.
test_doctor_separates_an_unreadable_config_from_a_missing_one() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  local config
  config="$(user_config_dir)/mise/config.toml"
  mkdir -p "$(dirname "$config")"
  printf '[tools]\n' > "$config"
  chmod 0000 "$config"
  local rc=0 out
  out="$(DRY_RUN=false cap_run mise doctor 2>&1)" || rc=$?
  chmod 0644 "$config"
  assert_failure "$rc" || return 1
  assert_contains "$out" "cannot be read, so teeup cannot tell what mise manages" || return 1
  assert_not_contains "$out" "has no global tool list" || return 1
  cleanup_test_env
}

# I15: a mise shims directory named on PATH but gone from disk (the data
# directory wiped or moved) must not read as healthy -- that is precisely the
# state the failure branch's own wording describes.
test_doctor_reports_a_stale_shims_directory_on_path() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure mise >/dev/null 2>&1
  seed_mise_shims
  rm -rf "$XDG_DATA_HOME/mise/shims"
  local rc=0 out
  out="$(DRY_RUN=false cap_run mise doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "does not exist" || return 1
  assert_not_contains "$out" "shims directory is on PATH." || return 1
  cleanup_test_env
}

# I16: a mise that is on PATH but fails on every call (a broken config, a
# corrupt install) must be its own failure, not read through as "pre-commit
# is asked for but not installed" -- the offered fix there, teeup configure
# mise, would only run the same broken mise again.
test_doctor_reports_an_unusable_mise_instead_of_a_missing_tool() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure mise >/dev/null 2>&1
  seed_mise_shims
  mock_command_script mise <<'EOF2'
echo "mise: failed to load config" >&2
exit 1
EOF2
  local rc=0 out
  out="$(DRY_RUN=false cap_run mise doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "did not answer to mise --version" || return 1
  assert_not_contains "$out" "pre-commit is asked for but not installed" || return 1
  cleanup_test_env
}

echo "capabilities/mise"
run_test "install gets mise" test_install_gets_mise
run_test "configure writes the config and the setting" test_configure_writes_the_config_and_the_setting
run_test "configure installs pre-commit once" test_configure_installs_pre_commit_once
run_test "configure ignores a project-local pre-commit" test_configure_ignores_a_project_local_pre_commit
run_test "configure reinstalls a requested but missing pre-commit" test_configure_reinstalls_a_requested_but_missing_pre_commit
run_test "configure is not fooled by a project config shadowing the global one" test_configure_is_not_fooled_by_a_project_config_shadowing_the_global_one
run_test "configure falls back to mise where when --installed is unsupported" test_configure_falls_back_to_mise_where_when_installed_is_unsupported
run_test "configure falls back to the global config file" test_configure_falls_back_to_the_global_config_file
run_test "configure ships an empty tools table" test_configure_ships_an_empty_tools_table
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "doctor passes on a configured machine" test_doctor_passes_on_a_configured_machine
run_test "doctor reports a missing mise and config" test_doctor_reports_a_missing_mise_and_config
run_test "doctor separates an unreadable config from a missing one" test_doctor_separates_an_unreadable_config_from_a_missing_one
run_test "doctor reports pre-commit requested but missing" test_doctor_reports_pre_commit_requested_but_not_installed
run_test "doctor reports a stale shims directory on PATH" test_doctor_reports_a_stale_shims_directory_on_path
run_test "doctor reports an unusable mise instead of a missing tool" test_doctor_reports_an_unusable_mise_instead_of_a_missing_tool
print_summary
