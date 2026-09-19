#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

# jq is resolved before setup_test_env narrows PATH (Homebrew's copy is
# hidden from the macOS runners there), then linked into the mock bin so the
# library finds it by name. A machine without jq skips this suite with a note
# instead of failing it (ruling C11): jq is already a teeup-runtime/cli-tools
# package, so the product dependency is unchanged, and every hosted CI runner
# image ships it anyway.
JQ_BIN="$(command -v jq || true)"
if [[ -z "$JQ_BIN" ]]; then
  echo "lib/json"
  echo "jq is not installed: skipping this suite (install jq to run it)"
  exit 0
fi

setup() {
  setup_test_env
  ln -s "$JQ_BIN" "$MOCK_BIN/jq"
  source "$TEEUP_PATH/lib/all.sh"
  export DRY_RUN=false
  # A directory with a space and shell metacharacters on purpose.
  FILE="$TEST_HOME/Some App & \$more/settings.json"
}

# body_of <file>: the file without its comment header, for jq.
body_of() { sed '/^[[:space:]]*\/\//d' "$1"; }

test_set_key_creates_the_file() {
  setup || return 1
  json_set_key "$FILE" theme '"One Dark"' >/dev/null
  assert_file_exists "$FILE" || return 1
  assert_equals "One Dark" "$(jq -r .theme "$FILE")" || return 1
  cleanup_test_env
}

test_a_dotted_key_is_one_flat_key() {
  setup || return 1
  mkdir -p "$(dirname "$FILE")"
  printf '{"editor.fontSize": 14, "workbench.colorTheme": "Abyss"}\n' > "$FILE"
  json_set_key "$FILE" workbench.colorTheme '"Catppuccin Mocha"' >/dev/null
  assert_equals "14" "$(jq -r '.["editor.fontSize"]' "$FILE")" || return 1
  assert_equals "Catppuccin Mocha" "$(jq -r '.["workbench.colorTheme"]' "$FILE")" || return 1
  assert_equals "null" "$(jq -r '.workbench' "$FILE")" "no nested object was created" || return 1
  cleanup_test_env
}

test_set_key_accepts_objects_and_booleans() {
  setup || return 1
  json_set_key "$FILE" theme '{"mode":"system","light":"One Light","dark":"One Dark"}' >/dev/null
  json_set_key "$FILE" window.autoDetectColorScheme true >/dev/null
  json_set_key "$FILE" telemetry false >/dev/null
  assert_equals "system" "$(jq -r .theme.mode "$FILE")" || return 1
  assert_equals "true" "$(jq -r '.["window.autoDetectColorScheme"]' "$FILE")" || return 1
  assert_equals "false" "$(jq -r .telemetry "$FILE")" || return 1
  cleanup_test_env
}

# Zed's own first settings.json, verbatim from assets/settings/initial_user_settings.json:
# a comment header and trailing commas.
test_zeds_initial_file_is_edited_and_keeps_its_header() {
  setup || return 1
  mkdir -p "$(dirname "$FILE")"
  cat > "$FILE" <<'EOF2'
// Zed settings
//
// For information on how to configure Zed, see the Zed
// documentation: https://zed.dev/docs/configuring-zed
//
// To see all of Zed's default settings without changing your
// custom settings, run `zed: open default settings` from the
// command palette (cmd-shift-p / ctrl-shift-p)
{
  "ui_font_size": 16,
  "buffer_font_size": 15,
  "theme": {
    "mode": "system",
    "light": "One Light",
    "dark": "One Dark",
  },
}
EOF2
  local out
  out="$(json_set_key "$FILE" buffer_font_family '"Hack Nerd Font"' 2>&1)"
  assert_equals "// Zed settings" "$(head -1 "$FILE")" || return 1
  assert_contains "$(cat "$FILE")" "https://zed.dev/docs/configuring-zed" || return 1
  assert_equals "15" "$(body_of "$FILE" | jq -r .buffer_font_size)" || return 1
  assert_equals "One Dark" "$(body_of "$FILE" | jq -r .theme.dark)" || return 1
  assert_equals "Hack Nerd Font" "$(body_of "$FILE" | jq -r .buffer_font_family)" || return 1
  assert_not_contains "$out" "do not survive" "a header-only comment needs no backup" || return 1
  cleanup_test_env
}

test_comments_inside_the_object_are_backed_up() {
  setup || return 1
  mkdir -p "$(dirname "$FILE")"
  cat > "$FILE" <<'EOF2'
{
  // the size I like
  "editor.fontSize": 13, /* inline */
  "url": "https://example.com/a//b",
  "quote": "say \"hi\" // not a comment",
}
EOF2
  local out
  out="$(json_set_key "$FILE" editor.fontFamily '"Hack Nerd Font"' 2>&1)"
  assert_equals "13" "$(jq -r '.["editor.fontSize"]' "$FILE")" || return 1
  assert_equals "https://example.com/a//b" "$(jq -r .url "$FILE")" "// inside a string is kept" || return 1
  assert_equals 'say "hi" // not a comment' "$(jq -r .quote "$FILE")" || return 1
  assert_contains "$out" "Comments inside $FILE do not survive the edit" || return 1
  ls "$FILE".teeup_backup_* >/dev/null 2>&1 || { echo "no backup was made"; return 1; }
  assert_contains "$(cat "$FILE".teeup_backup_*)" "// the size I like" || return 1
  cleanup_test_env
}

# M2: a dry run previews the write but must still warn that the comments are
# about to go, as a "would back up" line -- and must not actually make one.
test_comments_inside_the_object_warn_in_dry_run_too() {
  setup || return 1
  mkdir -p "$(dirname "$FILE")"
  cat > "$FILE" <<'EOF2'
{
  // the size I like
  "editor.fontSize": 13,
}
EOF2
  local out
  out="$(DRY_RUN=true json_set_key "$FILE" editor.fontFamily '"Hack Nerd Font"' 2>&1)"
  assert_contains "$out" "Comments inside $FILE do not survive the edit; would back up your previous file first" || return 1
  assert_contains "$out" "[DRY-RUN] Would write $FILE" || return 1
  ! ls "$FILE".teeup_backup_* >/dev/null 2>&1 || { echo "a backup was made in dry run"; return 1; }
  cleanup_test_env
}

test_set_key_is_idempotent() {
  setup || return 1
  json_set_key "$FILE" theme '"One Dark"' >/dev/null
  local out
  out="$(json_set_key "$FILE" theme '"One Dark"')"
  assert_contains "$out" "Already current: $FILE" || return 1
  cleanup_test_env
}

test_set_key_dry_run_writes_nothing() {
  setup || return 1
  local out
  out="$(DRY_RUN=true json_set_key "$FILE" theme '"One Dark"')"
  assert_contains "$out" "[DRY-RUN] Would write $FILE (theme)" || return 1
  [[ ! -e "$FILE" ]] || { echo "file written in dry run"; return 1; }
  cleanup_test_env
}

test_a_file_that_is_not_an_object_is_left_alone() {
  setup || return 1
  mkdir -p "$(dirname "$FILE")"
  printf '["a", "b"]\n' > "$FILE"
  local rc=0 out
  out="$(json_set_key "$FILE" theme '"One Dark"' 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" 'is not a JSON object jq can edit; set it by hand: "theme": "One Dark"' || return 1
  assert_equals '["a", "b"]' "$(cat "$FILE")" "the file is untouched" || return 1
  printf '{ "a": \n' > "$FILE"
  rc=0
  json_set_key "$FILE" theme '"One Dark"' >/dev/null 2>&1 || rc=$?
  assert_failure "$rc" "a truncated file is refused" || return 1
  assert_equals '{ "a": ' "$(cat "$FILE")" || return 1
  cleanup_test_env
}

test_a_symlinked_file_is_left_alone() {
  setup || return 1
  mkdir -p "$(dirname "$FILE")" "$TEST_HOME/dotfiles"
  printf '{"theme": "Mine"}\n' > "$TEST_HOME/dotfiles/settings.json"
  ln -s "$TEST_HOME/dotfiles/settings.json" "$FILE"
  local rc=0 out
  out="$(json_set_key "$FILE" theme '"One Dark"' 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "$FILE is a symlink; teeup does not write through it" || return 1
  [[ -L "$FILE" ]] || { echo "the link was replaced"; return 1; }
  assert_equals "Mine" "$(jq -r .theme "$TEST_HOME/dotfiles/settings.json")" || return 1
  cleanup_test_env
}

test_set_key_rejects_a_non_json_value() {
  setup || return 1
  local rc=0 out
  out="$(json_set_key "$FILE" theme 'One Dark' 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "not a JSON value: 'One Dark'" || return 1
  [[ ! -e "$FILE" ]] || { echo "file written for a bad value"; return 1; }
  cleanup_test_env
}

test_set_key_without_jq_warns() {
  setup || return 1
  export TEEUP_TEST_MISSING="jq"
  local rc=0 out
  out="$(json_set_key "$FILE" theme '"One Dark"' 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "jq is not installed" || return 1
  unset TEEUP_TEST_MISSING
  cleanup_test_env
}

test_merge_key_keeps_the_users_entries() {
  setup || return 1
  mkdir -p "$(dirname "$FILE")"
  printf '{"auto_install_extensions": {"html": true, "toml": false}}\n' > "$FILE"
  json_merge_key "$FILE" auto_install_extensions '{"catppuccin": true}' >/dev/null
  assert_equals "true" "$(jq -r .auto_install_extensions.html "$FILE")" || return 1
  assert_equals "false" "$(jq -r .auto_install_extensions.toml "$FILE")" || return 1
  assert_equals "true" "$(jq -r .auto_install_extensions.catppuccin "$FILE")" || return 1
  json_merge_key "$TEST_HOME/new.json" auto_install_extensions '{"catppuccin": true}' >/dev/null
  assert_equals "true" "$(jq -r .auto_install_extensions.catppuccin "$TEST_HOME/new.json")" "a missing object is created" || return 1
  cleanup_test_env
}

test_json_quote_escapes() {
  setup || return 1
  assert_equals '"Ada \"Countess\" \\ Lovelace"' "$(json_quote 'Ada "Countess" \ Lovelace')" || return 1
  cleanup_test_env
}

# M1: json_quote had no `have jq` guard of its own (unlike _json_edit), so a
# caller that forgot to check first got bash's raw "jq: command not found"
# and an empty value instead of a warning.
test_json_quote_without_jq_warns() {
  setup || return 1
  export TEEUP_TEST_MISSING="jq"
  local rc=0 out
  out="$(json_quote 'Ada Lovelace' 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "jq is not installed" || return 1
  unset TEEUP_TEST_MISSING
  cleanup_test_env
}

echo "lib/json"
run_test "set_key creates the file" test_set_key_creates_the_file
run_test "a dotted key is one flat key" test_a_dotted_key_is_one_flat_key
run_test "set_key accepts objects and booleans" test_set_key_accepts_objects_and_booleans
run_test "Zed's initial file is edited and keeps its header" test_zeds_initial_file_is_edited_and_keeps_its_header
run_test "comments inside the object are backed up" test_comments_inside_the_object_are_backed_up
run_test "comments inside the object warn in dry run too" test_comments_inside_the_object_warn_in_dry_run_too
run_test "set_key is idempotent" test_set_key_is_idempotent
run_test "set_key dry run writes nothing" test_set_key_dry_run_writes_nothing
run_test "a file that is not an object is left alone" test_a_file_that_is_not_an_object_is_left_alone
run_test "a symlinked file is left alone" test_a_symlinked_file_is_left_alone
run_test "set_key rejects a non-JSON value" test_set_key_rejects_a_non_json_value
run_test "set_key without jq warns" test_set_key_without_jq_warns
run_test "merge_key keeps the user's entries" test_merge_key_keeps_the_users_entries
run_test "json_quote escapes" test_json_quote_escapes
run_test "json_quote without jq warns" test_json_quote_without_jq_warns
print_summary
