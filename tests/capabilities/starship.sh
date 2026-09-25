#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  # `capabilities/starship/doctor` asks `have starship`. Without this the
  # answer comes from whatever the developer happens to have in /usr/bin:
  # four doctor tests here were green on a machine with starship installed
  # and red on all three CI runners, which have none. Hide the host copy so
  # only a mock a test installs itself can answer.
  hide_host_commands starship
  # `--version` answers for real: an exit-0, silent brew reads as "cannot
  # answer" (lib/doctor.sh's doctor_backend_can_answer), which used to switch
  # off every package check below in silence (NI2).
  mock_command_script brew <<'EOF2'
case "$1" in --version) echo "Homebrew 4.3.9" ;; esac
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  TEEUP="$TEEUP_PATH/bin/teeup"
}

test_install_gets_starship() {
  setup
  export TEEUP_TEST_MISSING="starship"
  local out
  out="$(DRY_RUN=true "$TEEUP" install starship 2>&1)"
  assert_contains "$out" "Would execute: brew install starship" || return 1
  cleanup_test_env
}

test_configure_copies_the_config_once() {
  setup
  DRY_RUN=false "$TEEUP" configure starship >/dev/null
  assert_file_exists "$TEST_HOME/.config/starship.toml" || return 1
  local out
  out="$(DRY_RUN=false "$TEEUP" configure starship)"
  assert_contains "$out" "Already installed: $TEST_HOME/.config/starship.toml" || return 1
  cleanup_test_env
}

test_shipped_config_carries_the_theme_markers() {
  setup
  DRY_RUN=false "$TEEUP" configure starship >/dev/null
  local body
  body="$(cat "$TEST_HOME/.config/starship.toml")"
  assert_contains "$body" "# teeup:theme-palette:start" || return 1
  assert_contains "$body" "# teeup:theme-palette:end" || return 1
  assert_contains "$body" "[palettes.teeup-dark]" || return 1
  assert_contains "$body" "[palettes.teeup-light]" || return 1
  cleanup_test_env
}

test_palette_is_selected_at_the_root() {
  setup
  DRY_RUN=false "$TEEUP" configure starship >/dev/null
  local file="$TEST_HOME/.config/starship.toml" p t
  # A bare key after a [table] header belongs to that table, so `palette` is
  # only the root-level selector while it precedes every table header. A
  # substring assertion cannot see the difference; line order can.
  p="$(grep -n '^palette = ' "$file" | head -1 | cut -d: -f1)"
  t="$(grep -n '^\[' "$file" | head -1 | cut -d: -f1)"
  [[ -n "$p" && -n "$t" ]] || { echo "palette line or table header missing"; return 1; }
  [[ "$p" -lt "$t" ]] ||
    { echo "palette (line $p) must come before the first table (line $t)"; return 1; }
  # And, where a TOML parser is available, prove it for real.
  if command -v python3 >/dev/null 2>&1 &&
     python3 -c 'import tomllib' >/dev/null 2>&1; then
    local parsed
    parsed="$(python3 -c 'import tomllib,sys
d = tomllib.load(open(sys.argv[1], "rb"))
print(d.get("palette"), sorted(d.get("palettes", {})))' "$file")"
    assert_equals "teeup-dark ['teeup-dark', 'teeup-light']" "$parsed" || return 1
  fi
  cleanup_test_env
}

test_configure_dry_run_writes_nothing() {
  setup
  DRY_RUN=true "$TEEUP" configure starship >/dev/null
  [[ ! -e "$TEST_HOME/.config/starship.toml" ]] || { echo "written in dry run"; return 1; }
  cleanup_test_env
}

test_reset_restores_the_file_and_the_current_palette() {
  setup
  # appearance reads the interface style; exit 1 is light mode. starship
  # requires zsh, whose configure calls chsh, so that is mocked too.
  mock_command defaults 1 ""
  mock_command chsh 0 ""
  export TEEUP_NO_GUM=1
  DRY_RUN=false "$TEEUP" install starship >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" install theme >/dev/null
  local file="$TEST_HOME/.config/starship.toml" out
  assert_contains "$(cat "$file")" 'palette = "teeup-light"' || return 1
  # The shipped file has a [directory] table of its own, so the line the user
  # adds has to be one the shipped version does not carry.
  printf '\n[custom.mine]\ncommand = "echo mine"\n' >> "$file"
  out="$(DRY_RUN=false "$TEEUP" reset starship 2>&1)"
  assert_not_contains "$(cat "$file")" "custom.mine" || return 1
  assert_contains "$out" 'command = "echo mine"' "the diff shows the removed table" || return 1
  assert_contains "$(cat "$file")" 'palette = "teeup-light"' "the theme hook put the current palette back" || return 1
  assert_contains "$(cat "$file")" 'accent = "#' || return 1
  out="$(DRY_RUN=false "$TEEUP" configure starship)"
  assert_contains "$out" "Already installed: $file" "the reset and re-themed file reads as unedited" || return 1
  cleanup_test_env
}

test_doctor_passes_after_configure() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command starship 0 "starship 1.23.0"
  DRY_RUN=false "$TEEUP" configure starship >/dev/null 2>&1
  local rc=0 out
  out="$(DRY_RUN=false cap_run starship doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "palette block is intact" || return 1
  cleanup_test_env
}

# NB2: a real bootstrap, then `teeup theme set`, must leave doctor healthy.
# `theme-apply` writes ONE marker block holding BOTH modes (dark render,
# blank line, light render, blank line), so it can switch appearance without
# a re-render; the block was being diffed against only ONE mode's rendered
# file, which can never equal it in either appearance -- a correctly
# themed, freshly bootstrapped machine failed doctor every time, with a fix
# (`teeup theme set catppuccin`) that had just run and changes nothing.
test_doctor_passes_after_configure_then_theme_set() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  # theme-apply hooks only fire for a capability teeup has actually marked
  # installed (cap_hook_eligible), so this needs a real `install`, not just
  # `configure` -- the same shape test_reset_restores_the_file_and_the_current_palette
  # uses above. starship pulls in zsh, whose configure calls chsh.
  mock_command starship 0 "starship 1.23.0"
  mock_command defaults 1 ""
  mock_command chsh 0 ""
  export TEEUP_NO_GUM=1
  DRY_RUN=false "$TEEUP" install starship >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" install theme >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null 2>&1
  local rc=0 out
  out="$(DRY_RUN=false cap_run starship doctor 2>&1)" || rc=$?
  assert_success "$rc" "a real bootstrap then teeup theme set must leave doctor healthy (NB2)" || return 1
  assert_contains "$out" "palette block is intact and matches the current theme" || return 1
  cleanup_test_env
}

# Minor 1: an unreadable rendered palette means the colours genuinely could
# not be compared -- not a confirmed mismatch (they might well be fine), and
# not healthy either. Mutation testing found this branch had no test at all
# (the "cannot be read" wording could be deleted with the suite still
# green); this pins both the wording and the exit status.
test_doctor_reports_unknown_when_a_rendered_palette_is_unreadable() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command starship 0 "starship 1.23.0"
  mock_command defaults 1 ""
  mock_command chsh 0 ""
  export TEEUP_NO_GUM=1
  DRY_RUN=false "$TEEUP" install starship >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" install theme >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null 2>&1
  chmod 0000 "$TEEUP_STATE_DIR/current/theme/dark/starship-palette.toml"
  local rc=0 out
  out="$(DRY_RUN=false cap_run starship doctor 2>&1)" || rc=$?
  chmod 0644 "$TEEUP_STATE_DIR/current/theme/dark/starship-palette.toml"
  assert_unknown "$rc" "an unreadable rendered palette could not be compared; it is not a confirmed mismatch" || return 1
  assert_contains "$out" "colours were not compared" || return 1
  cleanup_test_env
}

# Minor 2: the "no render at all => the block is intact" guard requires
# NEITHER mode to have a rendered palette. Mutation testing found the `&&`
# had no test pinning it against the boundary it exists for: a theme that
# rendered only one mode must still be COMPARED (dark exists here; light
# does not), never waved through as "intact" on the strength of the missing
# mode alone.
test_doctor_still_compares_when_only_one_mode_was_rendered() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command starship 0 "starship 1.23.0"
  mock_command defaults 1 ""
  mock_command chsh 0 ""
  export TEEUP_NO_GUM=1
  DRY_RUN=false "$TEEUP" install starship >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" install theme >/dev/null 2>&1
  DRY_RUN=false "$TEEUP" theme set catppuccin >/dev/null 2>&1
  rm -f "$TEEUP_STATE_DIR/current/theme/light/starship-palette.toml"
  local rc=0 out
  out="$(DRY_RUN=false cap_run starship doctor 2>&1)" || rc=$?
  # theme-apply wrote the config's block from BOTH modes; rebuilding the
  # expected content from only the mode still on disk (dark) cannot equal
  # it, so the real comparison must run and find the mismatch -- never take
  # the "no render at all" shortcut and call it intact on the strength of
  # one missing file alone.
  assert_failure "$rc" "one rendered mode is not the same as no render; the real comparison must run" || return 1
  assert_contains "$out" "does not match what the" || return 1
  assert_not_contains "$out" "palette block is intact" "a missing light render alone must not take the no-render-at-all shortcut" || return 1
  cleanup_test_env
}

# NI5: theme_current does a plain `cat`, which would otherwise die under
# `bash -eu` on an unreadable theme.name before starship's own findings are
# recorded -- the exact I19 defect, fixed in theme/doctor but not here.
test_doctor_reports_an_unreadable_theme_name_instead_of_dying() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command starship 0 "starship 1.23.0"
  DRY_RUN=false "$TEEUP" configure starship >/dev/null 2>&1
  theme_set catppuccin >/dev/null 2>&1
  chmod 0000 "$TEEUP_STATE_DIR/current/theme.name"
  local rc=0 out
  out="$(DRY_RUN=false cap_run starship doctor 2>&1)" || rc=$?
  chmod 0644 "$TEEUP_STATE_DIR/current/theme.name"
  assert_failure "$rc" || return 1
  assert_contains "$out" "theme.name cannot be read" || return 1
  assert_not_contains "$out" "Permission denied" "raw cat stderr must not leak" || return 1
  cleanup_test_env
}

# NI5: a bogus theme.name must not be offered as a fix that cannot succeed
# ("teeup theme set not-a-real-theme"), the same guard theme/doctor already
# has.
test_doctor_reports_a_theme_name_that_does_not_exist() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command starship 0 "starship 1.23.0"
  DRY_RUN=false "$TEEUP" configure starship >/dev/null 2>&1
  theme_set catppuccin >/dev/null 2>&1
  printf 'not-a-real-theme\n' > "$TEEUP_STATE_DIR/current/theme.name"
  local rc=0 out
  out="$(DRY_RUN=false cap_run starship doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "not-a-real-theme" || return 1
  assert_contains "$out" "teeup has no theme by that name" || return 1
  assert_not_contains "$out" "teeup theme set not-a-real-theme" "the fix offered must be able to succeed" || return 1
  cleanup_test_env
}

test_doctor_reports_a_missing_config() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command starship 0 "starship 1.23.0"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run starship doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "starship.toml" || return 1
  assert_contains "$(cat "$report")" "teeup configure starship" || return 1
  cleanup_test_env
}

test_doctor_reports_palette_markers_that_were_edited_away() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  mock_command starship 0 "starship 1.23.0"
  DRY_RUN=false "$TEEUP" configure starship >/dev/null 2>&1
  grep -v 'teeup:theme-palette' "$TEST_HOME/.config/starship.toml" > "$TEST_HOME/trimmed"
  mv "$TEST_HOME/trimmed" "$TEST_HOME/.config/starship.toml"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run starship doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "no longer follows the teeup theme" || return 1
  assert_contains "$(cat "$report")" "teeup reset starship" || return 1
  cleanup_test_env
}

# Intact markers are not intact colours. A hand-edited or stale palette block
# keeps the prompt on colours the current theme does not name, while every
# structural check passes.
test_doctor_reports_a_palette_block_that_does_not_match_the_theme() {
  setup
  mock_command starship 0 "starship 1.23.0"
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure starship >/dev/null 2>&1
  theme_set catppuccin >/dev/null 2>&1
  local config
  config="$(user_config_dir)/starship.toml"
  # Keep the markers, change what is between them.
  awk '/^# teeup:theme-palette:start$/ { print; print "red = \"#000000\""; skip = 1; next }
       /^# teeup:theme-palette:end$/ { skip = 0 }
       !skip { print }' "$config" > "$config.new" && mv "$config.new" "$config"
  local rc=0 out
  out="$(DRY_RUN=false cap_run starship doctor 2>&1)" || rc=$?
  assert_failure "$rc" "colours that do not match the theme are a problem" || return 1
  assert_contains "$out" "does not match what the" || return 1
  cleanup_test_env
}

# Unreadable is not missing, and `teeup reset starship` would replace the file
# over what is only a permissions problem.
test_doctor_separates_an_unreadable_config_from_a_missing_one() {
  setup
  mock_command starship 0 "starship 1.23.0"
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure starship >/dev/null 2>&1
  local config
  config="$(user_config_dir)/starship.toml"
  chmod 0000 "$config"
  local rc=0 out report="$TEST_HOME/report"
  : > "$report"
  export TEEUP_DOCTOR_REPORT="$report"
  out="$(DRY_RUN=false cap_run starship doctor 2>&1)" || rc=$?
  chmod 0644 "$config"
  assert_failure "$rc" || return 1
  assert_contains "$out" "cannot be read" || return 1
  assert_not_contains "$out" "runs on its built-in defaults" || return 1
  assert_not_contains "$(cat "$report")" "teeup reset starship" "a permissions problem is not fixed by replacing the file" || return 1
  cleanup_test_env
}

# The root selector had no coverage at all: deleting the whole branch left the
# suite green.
test_doctor_reports_a_missing_root_palette_selector() {
  setup
  mock_command starship 0 "starship 1.23.0"
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure starship >/dev/null 2>&1
  local config
  config="$(user_config_dir)/starship.toml"
  grep -v '^palette *=' "$config" > "$config.new" && mv "$config.new" "$config"
  local rc=0 out
  out="$(DRY_RUN=false cap_run starship doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "no root 'palette =' line" || return 1
  cleanup_test_env
}

# I17: `grep -q '^palette *='` matched anywhere in the file, including
# inside a [palettes.X] table -- a root selector with no root selector at
# all reads as healthy while the prompt selects nothing.
test_doctor_rejects_a_palette_line_inside_a_table() {
  setup
  mock_command starship 0 "starship 1.23.0"
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure starship >/dev/null 2>&1
  local config
  config="$(user_config_dir)/starship.toml"
  grep -v '^palette *=' "$config" > "$config.new" && mv "$config.new" "$config"
  printf '\n[palettes.other]\npalette = "nonsense"\n' >> "$config"
  local rc=0 out
  out="$(DRY_RUN=false cap_run starship doctor 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "no root 'palette =' line" || return 1
  cleanup_test_env
}

# The passing case should also name which palette was picked, so a stale
# answer is visible instead of a bare checkmark.
test_doctor_names_the_root_palette_selected() {
  setup
  mock_command starship 0 "starship 1.23.0"
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure starship >/dev/null 2>&1
  local rc=0 out
  out="$(DRY_RUN=false cap_run starship doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "A root palette selector is present (\"teeup-" || return 1
  cleanup_test_env
}


# The defect this suite shipped once: four doctor tests never mocked starship,
# so `have starship` in capabilities/starship/doctor was answered by whatever
# was in the developer's /usr/bin. They passed on a machine with starship
# installed and failed on all three CI runners, which have none. setup hides
# the host copy; this asserts the EFFECT of that, which is the only thing that
# holds on both kinds of machine.
#
# Asserting the evidence instead -- that TEEUP_TEST_MISSING names starship --
# is what the first version of this test did, and it failed on CI for the very
# reason the hiding exists: hide_host_commands records only copies it actually
# finds, so on a runner with no starship it recorded nothing and the assertion
# had nothing to see.
test_no_doctor_test_depends_on_a_host_starship() {
  setup
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure starship >/dev/null 2>&1
  # No mock: the doctor must say starship is absent. On a machine that has one
  # in /usr/bin that is only true because setup hid it.
  local out rc=0
  out="$(DRY_RUN=false cap_run starship doctor 2>&1)" || rc=$?
  assert_contains "$out" "starship is not on PATH" "the host's starship must not be visible to this suite" || return 1
  # And with its own mock, the same doctor passes.
  mock_command starship 0 "starship 1.23.0"
  rc=0
  out="$(DRY_RUN=false cap_run starship doctor 2>&1)" || rc=$?
  assert_success "$rc" "the doctor must pass on the mock this test installed" || return 1
  assert_contains "$out" "starship is on PATH." || return 1
  cleanup_test_env
}

echo "capabilities/starship"
run_test "install gets starship" test_install_gets_starship
run_test "configure copies the config once" test_configure_copies_the_config_once
run_test "shipped config carries the theme markers" test_shipped_config_carries_the_theme_markers
run_test "palette is selected at the root" test_palette_is_selected_at_the_root
run_test "reset restores the file and the current palette" test_reset_restores_the_file_and_the_current_palette
run_test "configure dry run writes nothing" test_configure_dry_run_writes_nothing
run_test "doctor passes after configure" test_doctor_passes_after_configure
run_test "doctor passes after configure then theme set" test_doctor_passes_after_configure_then_theme_set
run_test "doctor reports unknown when a rendered palette is unreadable" test_doctor_reports_unknown_when_a_rendered_palette_is_unreadable
run_test "doctor still compares when only one mode was rendered" test_doctor_still_compares_when_only_one_mode_was_rendered
run_test "doctor reports an unreadable theme name instead of dying" test_doctor_reports_an_unreadable_theme_name_instead_of_dying
run_test "doctor reports a theme name that does not exist" test_doctor_reports_a_theme_name_that_does_not_exist
run_test "doctor reports a missing config" test_doctor_reports_a_missing_config
run_test "doctor reports palette markers edited away" test_doctor_reports_palette_markers_that_were_edited_away
run_test "doctor reports a palette block that does not match the theme" test_doctor_reports_a_palette_block_that_does_not_match_the_theme
run_test "doctor separates an unreadable config from a missing one" test_doctor_separates_an_unreadable_config_from_a_missing_one
run_test "doctor reports a missing root palette selector" test_doctor_reports_a_missing_root_palette_selector
run_test "doctor rejects a palette line inside a table" test_doctor_rejects_a_palette_line_inside_a_table
run_test "doctor names the root palette selected" test_doctor_names_the_root_palette_selected
run_test "no doctor test depends on a host starship" test_no_doctor_test_depends_on_a_host_starship
print_summary
