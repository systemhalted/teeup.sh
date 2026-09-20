#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# A fixture tree: two lazy capabilities with commands, one lazy app, one core
# capability that must never get a shim.
make_cap() {
  local name="$1" tier="$2" provides="${3:-}" apps="${4:-}"
  local dir="$TEEUP_CAPS_DIR/$name"
  mkdir -p "$dir"
  cat > "$dir/capability" <<EOF2
summary="Fixture $name"
group=system
tier=$tier
requires=""
provides="$provides"
apps="$apps"
interactive=false
EOF2
  printf '#!/usr/bin/env bash\necho "install:%s"\n' "$name" > "$dir/install"
  printf '#!/usr/bin/env bash\necho "configure:%s"\n' "$name" > "$dir/configure"
  chmod +x "$dir/install" "$dir/configure"
}

setup() {
  setup_test_env
  mock_command hostname 0 "testmac"
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR"
  source "$TEEUP_PATH/lib/all.sh"
  export DRY_RUN=false
  make_cap alpha core "" ""
  make_cap boxes lazy "boxctl boxd" ""
  make_cap sketch lazy "sketch" "Sketch Pad"
  make_cap paint lazy "" "Paint Shop; Paint Viewer"
  make_cap cursor lazy "" "Cursor"
  printf 'alpha\n' > "$TEEUP_CAPS_DIR/core.list"
  : > "$TEEUP_CAPS_DIR/daily.list"
  SHIMS="$TEST_HOME/.local/state/teeup/shims"
}

test_provider_finds_the_lazy_capability() {
  setup
  assert_equals "boxes" "$(lazy_provider boxd)" || return 1
  assert_equals "sketch" "$(lazy_provider sketch)" || return 1
  lazy_provider nothing && { echo "unknown command must not resolve"; return 1; }
  cleanup_test_env
}

test_generate_writes_one_executable_shim_per_command() {
  setup
  shims_generate >/dev/null
  local c
  for c in boxctl boxd sketch; do
    assert_file_exists "$SHIMS/$c" || return 1
    [[ -x "$SHIMS/$c" ]] || { echo "$c must be executable"; return 1; }
  done
  [[ ! -e "$SHIMS/alpha" ]] || { echo "core capabilities get no shim"; return 1; }
  assert_equals "#!/bin/bash" "$(sed -n 1p "$SHIMS/boxd")" || return 1
  assert_equals "$TEEUP_SHIM_MARKER" "$(sed -n 2p "$SHIMS/boxd")" || return 1
  assert_contains "$(cat "$SHIMS/boxd")" 'lazy-run boxes boxd "$@"' || return 1
  cleanup_test_env
}

test_shim_execs_teeup_with_the_original_arguments() {
  setup
  shims_generate >/dev/null
  # A fake bin/teeup under a throwaway checkout, so the shim's baked path and
  # its argument order can be checked without going through the real CLI.
  local fake="$TEST_HOME/checkout"
  mkdir -p "$fake/bin"
  printf '#!/usr/bin/env bash\nprintf "[%%s]" "$@"; echo\n' > "$fake/bin/teeup"
  chmod +x "$fake/bin/teeup"
  local out
  out="$(TEEUP_PATH="$fake" "$SHIMS/boxd" --flag "two words")"
  assert_equals "[lazy-run][boxes][boxd][--flag][two words]" "$out" || return 1
  cleanup_test_env
}

test_shim_falls_back_to_the_baked_checkout_path() {
  setup
  # A checkout path with a space, a quote and a dollar sign: the shim must
  # reach the right bin/teeup even when TEEUP_PATH is absent from the
  # environment (an IDE's process runner, a cron job).
  local weird="$TEST_HOME/we ird\$\"dir"
  mkdir -p "$weird/bin"
  printf '#!/usr/bin/env bash\necho "reached:$1"\n' > "$weird/bin/teeup"
  chmod +x "$weird/bin/teeup"
  TEEUP_PATH="$weird" shim_write boxes boxd >/dev/null
  local out
  out="$(env -u TEEUP_PATH "$SHIMS/boxd")"
  assert_equals "reached:lazy-run" "$out" || return 1
  cleanup_test_env
}

test_generate_is_idempotent_and_removes_stale_shims() {
  setup
  shims_generate >/dev/null
  # A shim whose capability no longer provides it, and a file that is not a
  # teeup shim at all.
  cp "$SHIMS/boxd" "$SHIMS/oldcmd"
  printf '#!/bin/bash\necho mine\n' > "$SHIMS/mine"
  local out
  out="$(shims_generate 2>&1)"
  assert_contains "$out" "Already current: $SHIMS/boxd" || return 1
  assert_contains "$out" "Removed stale shim: oldcmd" || return 1
  [[ ! -e "$SHIMS/oldcmd" ]] || { echo "stale shim must be removed"; return 1; }
  assert_contains "$out" "Not a teeup shim, leaving it alone: $SHIMS/mine" || return 1
  assert_file_exists "$SHIMS/mine" || return 1
  cleanup_test_env
}

test_generate_skips_a_capability_in_teeup_skip() {
  setup
  export TEEUP_SKIP="boxes"
  local out
  out="$(shims_generate 2>&1)"
  assert_contains "$out" "No shims for boxes (TEEUP_SKIP)" || return 1
  [[ ! -e "$SHIMS/boxd" ]] || { echo "skipped capability must get no shim"; return 1; }
  assert_file_exists "$SHIMS/sketch" || return 1
  unset TEEUP_SKIP
  cleanup_test_env
}

test_generate_dry_run_writes_nothing() {
  setup
  local out
  out="$(DRY_RUN=true shims_generate)"
  assert_contains "$out" "Would write $SHIMS/boxd" || return 1
  [[ ! -e "$SHIMS" ]] || { echo "dry run must not create the shims dir"; return 1; }
  cleanup_test_env
}

test_real_command_ignores_the_shims_dir() {
  setup
  shims_generate >/dev/null
  export PATH="$MOCK_BIN:/usr/bin:/bin:$SHIMS"
  lazy_real_command boxd && { echo "a shim alone is not a real command"; return 1; }
  mock_command boxd 0 ""
  assert_equals "$MOCK_BIN/boxd" "$(lazy_real_command boxd)" || return 1
  # An empty PATH entry (a leading or doubled colon) means the current
  # directory; it is skipped rather than searched.
  export PATH=":$MOCK_BIN::/usr/bin:$SHIMS/"
  assert_equals "$MOCK_BIN/boxd" "$(lazy_real_command boxd)" || return 1
  export TEEUP_TEST_MISSING="boxd"
  lazy_real_command boxd && { echo "TEEUP_TEST_MISSING must hide it"; return 1; }
  # By absolute path, only that binary is hidden.
  local other
  other="$(mktemp -d)"
  cp "$MOCK_BIN/boxd" "$other/boxd"
  export TEEUP_TEST_MISSING="$MOCK_BIN/boxd"
  export PATH="$MOCK_BIN:$other:/usr/bin:$SHIMS"
  assert_equals "$other/boxd" "$(lazy_real_command boxd)" || return 1
  unset TEEUP_TEST_MISSING
  rm -rf "$other"
  cleanup_test_env
}

test_have_ignores_a_shim() {
  setup
  shims_generate >/dev/null
  # The shim has to exist for this to prove anything: without it `have` is
  # false for want of any boxd at all.
  assert_file_exists "$SHIMS/boxd" || return 1
  export PATH="$MOCK_BIN:/usr/bin:/bin:$SHIMS"
  have boxd && { echo "have must not count a shim as installed"; return 1; }
  mock_command boxd 0 ""
  have boxd || { echo "a real boxd ahead of the shim counts"; return 1; }
  cleanup_test_env
}

test_is_tty_honours_the_test_hook() {
  setup
  TEEUP_TEST_TTY=yes lazy_is_tty || { echo "yes must be a tty"; return 1; }
  TEEUP_TEST_TTY=no lazy_is_tty && { echo "no must not be a tty"; return 1; }
  # Under run_test stdin is not a terminal, so the real check says no.
  lazy_is_tty </dev/null && { echo "/dev/null is not a tty"; return 1; }
  cleanup_test_env
}

test_cap_apps_splits_on_semicolons() {
  setup
  assert_equals "Sketch Pad" "$(cap_apps sketch)" || return 1
  assert_equals "Paint Shop|Paint Viewer" "$(cap_apps paint | tr '\n' '|' | sed 's/|$//')" || return 1
  assert_equals "" "$(cap_apps boxes)" || return 1
  cleanup_test_env
}

test_launch_resolve_by_capability_and_by_app_name() {
  setup
  assert_equals "sketch" "$(launch_resolve sketch)" || return 1
  assert_equals "sketch" "$(launch_resolve "sketch pad")" || return 1
  assert_equals "sketch" "$(launch_resolve "Sketch Pad.app")" || return 1
  assert_equals "paint" "$(launch_resolve "paint viewer")" || return 1
  local rc=0 out
  out="$(launch_resolve boxes 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "boxes has no apps= entry" || return 1
  rc=0
  out="$(launch_resolve "Nothing Here" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "No capability provides an app named 'Nothing Here'" || return 1
  cleanup_test_env
}

test_launch_resolve_matches_capability_names_case_sensitively() {
  setup
  # cap_exists uses [[ -f capabilities/$name/capability ]], which macOS's
  # default case-insensitive disks satisfy for any case variant of a real
  # directory name ("Cursor" opens the same file as "cursor"). Simulate that
  # here by overriding cap_exists the way it would answer on such a disk, in
  # a subshell so the override does not leak into later tests. launch_resolve
  # must not consult cap_exists for this decision at all: a capability name
  # only matches on an exact line in cap_list, so "Cursor" still falls
  # through to the case-insensitive apps= match and resolves to "cursor"
  # with the real, lowercase name attached.
  local resolved
  resolved="$(cap_exists() { [[ "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" == "cursor" ]]; }; launch_resolve Cursor)"
  assert_equals "cursor" "$resolved" || return 1
  # If launch_resolve had returned "Cursor" (the original casing) instead,
  # this literal comparison in cap_skipped would miss a lowercase TEEUP_SKIP
  # entry and the skip would be silently bypassed.
  export TEEUP_SKIP="cursor"
  cap_skipped "$resolved" || { echo "TEEUP_SKIP=cursor must catch the name launch_resolve returns for a case-variant argument"; return 1; }
  unset TEEUP_SKIP
  cleanup_test_env
}

test_app_installed_checks_both_application_folders() {
  setup
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  app_installed "Sketch Pad" && { echo "nothing installed yet"; return 1; }
  mkdir -p "$TEEUP_APPS_DIR/Sketch Pad.app"
  app_installed "Sketch Pad" || { echo "found under TEEUP_APPS_DIR"; return 1; }
  mkdir -p "$HOME/Applications/Paint Shop.app"
  app_installed "Paint Shop" || { echo "found under ~/Applications"; return 1; }
  cleanup_test_env
}

# B1: a MacPorts aqua port moves its .app into applications_dir, never
# /Applications -- app_installed must consult macports_apps_dir on that
# backend, or an already-installed app reads as missing forever.
test_app_installed_checks_macports_apps_dir_on_macports() {
  setup
  export TEEUP_PACKAGE_MANAGER=macports
  local apps_dir="$TEST_HOME/MacPortsApps"
  mkdir -p "$TEEUP_PKG_PREFIX/etc/macports"
  printf 'applications_dir\t%s\n' "$apps_dir" > "$TEEUP_PKG_PREFIX/etc/macports/macports.conf"
  app_installed "Emacs" && { echo "nothing installed yet"; return 1; }
  mkdir -p "$apps_dir/Emacs.app"
  app_installed "Emacs" || { echo "must be found under macports_apps_dir"; return 1; }
  unset TEEUP_PACKAGE_MANAGER
  cleanup_test_env
}

# B1: the "still not found" message must name every directory actually
# looked in, and only add MacPorts' applications_dir when the backend is
# MacPorts -- naming it on a Homebrew machine would claim a lookup that
# never happens.
test_app_search_dirs_lists_macports_only_on_macports() {
  setup
  export TEEUP_APPS_DIR="$TEST_HOME/Applications"
  assert_equals "$TEEUP_APPS_DIR, $HOME/Applications" "$(app_search_dirs)" || return 1
  export TEEUP_PACKAGE_MANAGER=macports
  assert_equals "$TEEUP_APPS_DIR, $HOME/Applications, /Applications/MacPorts" "$(app_search_dirs)" || return 1
  unset TEEUP_PACKAGE_MANAGER
  cleanup_test_env
}

# M6: matching one specific app out of a capability's apps= list, the same
# case-insensitive, ".app"-optional way launch_resolve matches by app name.
test_app_match_in_cap_finds_the_named_app() {
  setup
  assert_equals "Paint Viewer" "$(app_match_in_cap paint "paint viewer")" || return 1
  assert_equals "Paint Shop" "$(app_match_in_cap paint "Paint Shop.app")" || return 1
  app_match_in_cap paint "nonexistent" && { echo "must fail when nothing matches"; return 1; }
  cleanup_test_env
}

echo "lib/lazy.sh"
run_test "provider finds the lazy capability" test_provider_finds_the_lazy_capability
run_test "generate writes one executable shim per command" test_generate_writes_one_executable_shim_per_command
run_test "shim execs teeup with the original arguments" test_shim_execs_teeup_with_the_original_arguments
run_test "shim falls back to the baked checkout path" test_shim_falls_back_to_the_baked_checkout_path
run_test "generate is idempotent and removes stale shims" test_generate_is_idempotent_and_removes_stale_shims
run_test "generate skips a capability in TEEUP_SKIP" test_generate_skips_a_capability_in_teeup_skip
run_test "generate dry run writes nothing" test_generate_dry_run_writes_nothing
run_test "real command ignores the shims dir" test_real_command_ignores_the_shims_dir
run_test "have ignores a shim" test_have_ignores_a_shim
run_test "is_tty honours the test hook" test_is_tty_honours_the_test_hook
run_test "cap_apps splits on semicolons" test_cap_apps_splits_on_semicolons
run_test "launch_resolve by capability and by app name" test_launch_resolve_by_capability_and_by_app_name
run_test "launch_resolve matches capability names case-sensitively" test_launch_resolve_matches_capability_names_case_sensitively
run_test "app_installed checks both application folders" test_app_installed_checks_both_application_folders
run_test "app_installed checks macports_apps_dir on macports" test_app_installed_checks_macports_apps_dir_on_macports
run_test "app_search_dirs lists macports only on macports" test_app_search_dirs_lists_macports_only_on_macports
run_test "app_match_in_cap finds the named app" test_app_match_in_cap_finds_the_named_app
print_summary
