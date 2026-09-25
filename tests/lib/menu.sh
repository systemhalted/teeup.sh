#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  # Spaces and three characters that are special to awk, sed and the shell, so
  # every path this library builds is exercised against one.
  export TEEUP_CONFIG_DIR="$TEST_HOME/con fig \$x & 'q'/teeup"
  mkdir -p "$TEEUP_CONFIG_DIR"
  export TEEUP_MENU_FILE="$TEST_HOME/men u \$x & 'q'/menu.json"
  mkdir -p "$(dirname "$TEEUP_MENU_FILE")"
  # gum and fzf both paint on /dev/tty, so the switch that makes prompts
  # deterministic has to turn off both.
  export TEEUP_NO_GUM=1
  source "$TEEUP_PATH/lib/all.sh"
}

write_shipped() {
  cat > "$TEEUP_MENU_FILE"
}

write_user() {
  cat > "$(menu_user_file)"
}

sample_menu() {
  write_shipped <<'EOF2'
{
  "install": {"icon": "+", "label": "Install", "title": "Install something"},
  "install.colima": {"label": "Docker", "when": "teeup has colima", "action": "teeup install colima"},
  "install.tmux": {"label": "tmux", "action": "teeup install tmux"},
  "theme": {"label": "Theme", "action": "teeup theme list"}
}
EOF2
}

test_parse_prints_one_line_per_field_in_file_order() {
  setup
  sample_menu
  local out
  out="$(menu_parse "$TEEUP_MENU_FILE")"
  assert_equals "install	icon	+" "$(printf '%s\n' "$out" | head -1)" || return 1
  assert_contains "$out" "install.colima	when	teeup has colima" || return 1
  assert_equals "theme	action	teeup theme list" "$(printf '%s\n' "$out" | tail -1)" || return 1
  cleanup_test_env
}

test_parse_accepts_an_empty_object_and_an_entry_with_no_fields() {
  setup
  write_shipped <<'EOF2'
{ "a": {}, "b": {"label": "B", "action": "true"} }
EOF2
  assert_equals "b	label	B
b	action	true" "$(menu_parse "$TEEUP_MENU_FILE")" || return 1
  write_shipped <<'EOF2'
{}
EOF2
  assert_equals "" "$(menu_parse "$TEEUP_MENU_FILE")" || return 1
  cleanup_test_env
}

test_parse_keeps_escaped_quotes_and_backslashes() {
  setup
  write_shipped <<'EOF2'
{"a": {"label": "say \"hi\" & co\\"}}
EOF2
  assert_equals 'a	label	say "hi" & co\' "$(menu_parse "$TEEUP_MENU_FILE")" || return 1
  cleanup_test_env
}

test_parse_refuses_a_file_that_is_not_one_object_of_objects_of_strings() {
  setup
  local rc out
  write_shipped <<'EOF2'
not json
EOF2
  rc=0; out="$(menu_parse "$TEEUP_MENU_FILE" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "must be one JSON object" || return 1
  write_shipped <<'EOF2'
{"a": {"label": 3}}
EOF2
  rc=0; out="$(menu_parse "$TEEUP_MENU_FILE" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "a.label must be a string" || return 1
  write_shipped <<'EOF2'
{"a": {"label": "one
two"}}
EOF2
  rc=0; out="$(menu_parse "$TEEUP_MENU_FILE" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "one line of text" || return 1
  cleanup_test_env
}

test_parse_refuses_an_invalid_id() {
  setup
  write_shipped <<'EOF2'
{"Bad Id!": {"label": "x"}}
EOF2
  local rc=0 out
  out="$(menu_parse "$TEEUP_MENU_FILE" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "invalid id" || return 1
  cleanup_test_env
}

test_parse_refuses_an_unknown_field() {
  setup
  write_shipped <<'EOF2'
{"a": {"color": "red"}}
EOF2
  local rc=0 out
  out="$(menu_parse "$TEEUP_MENU_FILE" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "unknown field" || return 1
  cleanup_test_env
}

test_parse_refuses_a_duplicate_id() {
  setup
  write_shipped <<'EOF2'
{"a": {"label": "A"}, "a": {"label": "Again"}}
EOF2
  local rc=0 out
  out="$(menu_parse "$TEEUP_MENU_FILE" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "duplicate id" || return 1
  cleanup_test_env
}

test_parse_refuses_a_duplicate_field() {
  setup
  write_shipped <<'EOF2'
{"a": {"label": "A", "label": "B"}}
EOF2
  local rc=0 out
  out="$(menu_parse "$TEEUP_MENU_FILE" 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "duplicate field" || return 1
  cleanup_test_env
}

test_entries_are_the_shipped_file_when_there_is_no_user_file() {
  setup
  sample_menu
  assert_equals "$(menu_parse "$TEEUP_MENU_FILE")" "$(menu_entries)" || return 1
  cleanup_test_env
}

test_a_user_entry_replaces_the_shipped_one_whole_and_keeps_its_place() {
  setup
  sample_menu
  write_user <<'EOF2'
{"install.colima": {"label": "Containers"}}
EOF2
  local out
  out="$(menu_entries)"
  assert_contains "$out" "install.colima	label	Containers" || return 1
  assert_not_contains "$out" "install.colima	when" "the user entry replaces the whole row" || return 1
  local cache
  cache="$(menu_cache)"
  assert_equals "install.colima
install.tmux" "$(menu_children "$cache" install)" "the overridden row keeps its position" || return 1
  rm -f "$cache"
  cleanup_test_env
}

test_a_user_only_entry_is_appended() {
  setup
  sample_menu
  write_user <<'EOF2'
{"mine": {"label": "Mine", "action": "echo hello"}}
EOF2
  local cache
  cache="$(menu_cache)"
  assert_equals "install
theme
mine" "$(menu_children "$cache" "")" || return 1
  rm -f "$cache"
  cleanup_test_env
}

test_children_and_fields_and_labels() {
  setup
  sample_menu
  local cache
  cache="$(menu_cache)"
  assert_equals "install
theme" "$(menu_children "$cache" "")" || return 1
  assert_equals "install.colima
install.tmux" "$(menu_children "$cache" install)" || return 1
  assert_equals "" "$(menu_children "$cache" install.tmux)" || return 1
  assert_equals "Install something" "$(menu_field "$cache" install title)" || return 1
  assert_equals "" "$(menu_field "$cache" install nosuch)" || return 1
  assert_equals "+ Install" "$(menu_label "$cache" install)" || return 1
  assert_equals "tmux" "$(menu_label "$cache" install.tmux)" || return 1
  rm -f "$cache"
  cleanup_test_env
}

test_visible_runs_the_when_predicate_through_teeup_has() {
  setup
  sample_menu
  local cache
  cache="$(menu_cache)"
  menu_visible "$cache" install || { echo "a row with no when is always shown"; return 1; }
  menu_visible "$cache" install.colima && { echo "colima is not installed, so the row hides"; return 1; }
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR/colima"
  printf 'summary="c"\ngroup=containers\ntier=lazy\n' > "$TEEUP_CAPS_DIR/colima/capability"
  state_done mark cap-colima
  menu_visible "$cache" install.colima || { echo "an installed colima shows the row"; return 1; }
  rm -f "$cache"
  cleanup_test_env
}

test_picker_resolves_and_rejects_junk() {
  setup
  assert_equals "plain" "$(menu_picker)" "TEEUP_NO_GUM turns off gum and fzf alike" || return 1
  assert_equals "fzf" "$(TEEUP_MENU_PICKER=fzf menu_picker)" || return 1
  assert_equals "gum" "$(TEEUP_MENU_PICKER=gum menu_picker)" || return 1
  local rc=0 out
  out="$(TEEUP_MENU_PICKER=banana menu_picker 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "must be auto, gum, fzf or plain" || return 1
  mock_command fzf 0 ""
  assert_equals "fzf" "$(TEEUP_NO_GUM="" TEEUP_TEST_MISSING=gum menu_picker)" "no gum but an fzf means fzf" || return 1
  cleanup_test_env
}

test_menu_validate_picker_env_dies_on_an_unknown_value_and_passes_good_ones() {
  setup
  local rc=0 out
  out="$(TEEUP_MENU_PICKER=banana menu_validate_picker_env 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "must be auto, gum, fzf or plain" || return 1
  rc=0
  TEEUP_MENU_PICKER=fzf menu_validate_picker_env || rc=$?
  assert_success "$rc" || return 1
  rc=0
  menu_validate_picker_env || rc=$?
  assert_success "$rc" "an unset TEEUP_MENU_PICKER (meaning auto) is valid" || return 1
  cleanup_test_env
}

test_pick_plain_takes_a_number_a_label_or_a_cancel() {
  setup
  assert_equals "Beta" "$(echo 2 | menu_pick "Pick" Alpha Beta 2>/dev/null)" || return 1
  assert_equals "Alpha" "$(echo Alpha | menu_pick "Pick" Alpha Beta 2>/dev/null)" || return 1
  local rc=0
  echo "" | menu_pick "Pick" Alpha Beta >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "an empty line goes back" || return 1
  rc=0
  echo q | menu_pick "Pick" Alpha Beta >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "q goes back" || return 1
  rc=0
  menu_pick "Pick" Alpha Beta </dev/null >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "end of input goes back rather than looping" || return 1
  rc=0
  echo 9 | menu_pick "Pick" Alpha Beta >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "a number out of range is not a choice, and end of input after it still cancels" || return 1
  cleanup_test_env
}

test_pick_plain_reprompts_on_a_bad_answer_instead_of_giving_up() {
  setup
  assert_equals "Beta" "$(printf '9\n2\n' | menu_pick "Pick" Alpha Beta 2>/dev/null)" "an out-of-range number re-prompts" || return 1
  assert_equals "Alpha" "$(printf 'nope\nAlpha\n' | menu_pick "Pick" Alpha Beta 2>/dev/null)" "an unrecognised word re-prompts" || return 1
  cleanup_test_env
}

test_pick_drives_fzf_when_asked_to() {
  setup
  mock_command_script fzf <<'EOF2'
cat > "$HOME/fzf-input"
echo "Beta"
EOF2
  assert_equals "Beta" "$(TEEUP_MENU_PICKER=fzf menu_pick "Pick" Alpha Beta)" || return 1
  assert_equals "Alpha
Beta" "$(cat "$TEST_HOME/fzf-input")" || return 1
  mock_command fzf 130 ""
  local rc=0
  TEEUP_MENU_PICKER=fzf menu_pick "Pick" Alpha Beta >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "escaping out of fzf cancels" || return 1
  cleanup_test_env
}

test_check_flags_the_four_ways_a_menu_file_goes_wrong() {
  setup
  write_shipped <<'EOF2'
{
  "a": {"label": "A", "action": "true"},
  "a.b": {"label": "B", "action": "true"},
  "orphan.child": {"label": "Child", "action": "true"},
  "c": {"label": "C"},
  "d": {"action": "true"},
  "e": {"label": "E"},
  "e.one": {"label": "Same", "action": "true"},
  "e.two": {"label": "Same", "action": "true"}
}
EOF2
  local cache out rc=0
  cache="$(menu_cache)"
  out="$(menu_check "$cache")" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "a has both an action and child rows" || return 1
  assert_contains "$out" "orphan.child has no parent row orphan" || return 1
  assert_contains "$out" "c has neither an action nor child rows" || return 1
  assert_contains "$out" "d has no label" || return 1
  assert_contains "$out" "two rows under e share the label" || return 1
  rm -f "$cache"
  cleanup_test_env
}

test_check_flags_a_reserved_dot_dot_label() {
  setup
  write_shipped <<'EOF2'
{"a": {"label": "..", "action": "true"}}
EOF2
  local cache out rc=0
  cache="$(menu_cache)"
  out="$(menu_check "$cache")" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" 'a has the reserved label ".."' || return 1
  rm -f "$cache"
  cleanup_test_env
}

test_check_passes_a_well_formed_menu() {
  setup
  sample_menu
  local cache rc=0 out
  cache="$(menu_cache)"
  out="$(menu_check "$cache")" || rc=$?
  assert_success "$rc" "$out" || return 1
  assert_equals "" "$out" || return 1
  rm -f "$cache"
  cleanup_test_env
}

test_entries_refuses_a_broken_user_file_rather_than_half_a_menu() {
  setup
  sample_menu
  write_user <<'EOF2'
{"mine": {"label": }}
EOF2
  local rc=0 out
  out="$(menu_entries 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$(menu_user_file)" || return 1
  assert_not_contains "$out" "install	icon" "a broken user file must not yield half a menu" || return 1
  cleanup_test_env
}

echo "lib/menu.sh"
run_test "parse prints one line per field in file order" test_parse_prints_one_line_per_field_in_file_order
run_test "parse accepts an empty object" test_parse_accepts_an_empty_object_and_an_entry_with_no_fields
run_test "parse keeps escaped quotes and backslashes" test_parse_keeps_escaped_quotes_and_backslashes
run_test "parse refuses a malformed file" test_parse_refuses_a_file_that_is_not_one_object_of_objects_of_strings
run_test "parse refuses an invalid id" test_parse_refuses_an_invalid_id
run_test "parse refuses an unknown field" test_parse_refuses_an_unknown_field
run_test "parse refuses a duplicate id" test_parse_refuses_a_duplicate_id
run_test "parse refuses a duplicate field" test_parse_refuses_a_duplicate_field
run_test "entries are the shipped file with no user file" test_entries_are_the_shipped_file_when_there_is_no_user_file
run_test "a user entry replaces the shipped one whole" test_a_user_entry_replaces_the_shipped_one_whole_and_keeps_its_place
run_test "a user-only entry is appended" test_a_user_only_entry_is_appended
run_test "children, fields and labels" test_children_and_fields_and_labels
run_test "visible runs the when predicate" test_visible_runs_the_when_predicate_through_teeup_has
run_test "picker resolves and rejects junk" test_picker_resolves_and_rejects_junk
run_test "menu_validate_picker_env dies on junk, before any \$(...)" test_menu_validate_picker_env_dies_on_an_unknown_value_and_passes_good_ones
run_test "pick plain takes a number, a label or a cancel" test_pick_plain_takes_a_number_a_label_or_a_cancel
run_test "pick plain re-prompts on a bad answer" test_pick_plain_reprompts_on_a_bad_answer_instead_of_giving_up
run_test "pick drives fzf when asked to" test_pick_drives_fzf_when_asked_to
run_test "check flags a broken menu" test_check_flags_the_four_ways_a_menu_file_goes_wrong
run_test "check flags a reserved '..' label" test_check_flags_a_reserved_dot_dot_label
run_test "check passes a well-formed menu" test_check_passes_a_well_formed_menu
run_test "entries refuses a broken user file" test_entries_refuses_a_broken_user_file_rather_than_half_a_menu
print_summary
