#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
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
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false "$TEEUP" configure starship >/dev/null 2>&1
  local rc=0 out
  out="$(DRY_RUN=false cap_run starship doctor 2>&1)" || rc=$?
  assert_success "$rc" || return 1
  assert_contains "$out" "A root palette selector is present (\"teeup-" || return 1
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
run_test "doctor reports a missing config" test_doctor_reports_a_missing_config
run_test "doctor reports palette markers edited away" test_doctor_reports_palette_markers_that_were_edited_away
run_test "doctor reports a palette block that does not match the theme" test_doctor_reports_a_palette_block_that_does_not_match_the_theme
run_test "doctor separates an unreadable config from a missing one" test_doctor_separates_an_unreadable_config_from_a_missing_one
run_test "doctor reports a missing root palette selector" test_doctor_reports_a_missing_root_palette_selector
run_test "doctor rejects a palette line inside a table" test_doctor_rejects_a_palette_line_inside_a_table
run_test "doctor names the root palette selected" test_doctor_names_the_root_palette_selected
print_summary
