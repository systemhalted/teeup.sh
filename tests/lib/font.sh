#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helper.sh"

setup() {
  setup_test_env
  mock_macos_base
  mock_command_script brew <<'EOF2'
case "$1" in list) exit 1 ;; *) exit 0 ;; esac
EOF2
  source "$TEEUP_PATH/lib/all.sh"
  DRY_RUN=false
}

test_names_normalise_to_the_same_row() {
  setup
  assert_equals "font-caskaydia-mono-nerd-font" "$(font_cask 'Cascadia Mono')" || return 1
  assert_equals "font-caskaydia-mono-nerd-font" "$(font_cask 'cascadia-mono')" || return 1
  assert_equals "font-caskaydia-mono-nerd-font" "$(font_cask 'CaskaydiaMono Nerd Font')" || return 1
  assert_equals "CaskaydiaMono Nerd Font" "$(font_family 'Cascadia Mono')" || return 1
  cleanup_test_env
}

test_every_shipped_family_resolves() {
  setup
  assert_equals "JetBrainsMono Nerd Font" "$(font_family 'JetBrains Mono')" || return 1
  assert_equals "FiraCode Nerd Font" "$(font_family 'Fira Code')" || return 1
  assert_equals "Hack Nerd Font" "$(font_family 'hack')" || return 1
  assert_equals "MesloLGS Nerd Font" "$(font_family 'Meslo')" || return 1
  assert_equals "font-jetbrains-mono-nerd-font" "$(font_cask 'JetBrainsMono')" || return 1
  assert_equals "font-fira-code-nerd-font" "$(font_cask 'FiraCode')" || return 1
  assert_equals "font-hack-nerd-font" "$(font_cask 'Hack')" || return 1
  assert_equals "font-meslo-lg-nerd-font" "$(font_cask 'MesloLGS')" || return 1
  cleanup_test_env
}

test_unknown_font_fails_with_a_hint() {
  setup
  local rc=0 out
  out="$(font_cask 'Comic Sans' 2>&1)" || rc=$?
  assert_failure "$rc" || return 1
  assert_contains "$out" "Unknown font: Comic Sans" || return 1
  assert_contains "$out" "teeup install font list" || return 1
  cleanup_test_env
}

test_current_defaults_to_jetbrains() {
  setup
  assert_equals "JetBrainsMono Nerd Font" "$(font_current)" || return 1
  cleanup_test_env
}

test_set_installs_the_cask_and_records_the_family() {
  setup
  local out
  out="$(font_set 'Cascadia Mono')"
  assert_contains "$(cat "$MOCK_LOG")" "brew install --cask font-caskaydia-mono-nerd-font" || return 1
  assert_equals "CaskaydiaMono Nerd Font" "$(cat "$TEST_HOME/.local/state/teeup/current/font")" || return 1
  assert_equals "CaskaydiaMono Nerd Font" "$(font_current)" || return 1
  assert_contains "$out" "Font set to CaskaydiaMono Nerd Font" || return 1
  cleanup_test_env
}

test_set_runs_font_apply_hooks() {
  setup
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  mkdir -p "$TEEUP_CAPS_DIR/demo"
  cat > "$TEEUP_CAPS_DIR/demo/capability" <<'EOF2'
summary="Fixture demo"
group=system
tier=lazy
requires=""
provides=""
interactive=false
EOF2
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/demo/install"
  printf '#!/usr/bin/env bash\n:\n' > "$TEEUP_CAPS_DIR/demo/configure"
  cat > "$TEEUP_CAPS_DIR/demo/font-apply" <<'EOF2'
#!/usr/bin/env bash
echo "font-applied:$TEEUP_FONT_FAMILY"
EOF2
  chmod +x "$TEEUP_CAPS_DIR/demo/install" "$TEEUP_CAPS_DIR/demo/configure" "$TEEUP_CAPS_DIR/demo/font-apply"
  local out
  out="$(font_set Hack)"
  assert_contains "$out" "font-applied:Hack Nerd Font" || return 1
  cleanup_test_env
}

test_set_runs_every_hook_after_an_interactive_one() {
  setup
  export TEEUP_CAPS_DIR="$TEST_HOME/caps"
  local name interactive body
  for name in aaa bbb; do
    if [[ "$name" == "aaa" ]]; then
      interactive=true
      body='read -r line || true; echo "aaa read:[$line]"'
    else
      interactive=false
      body='echo "bbb applied"'
    fi
    mkdir -p "$TEEUP_CAPS_DIR/$name"
    printf 'summary="Fixture"\ngroup=system\ntier=lazy\nrequires=""\nprovides=""\ninteractive=%s\n' "$interactive" > "$TEEUP_CAPS_DIR/$name/capability"
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$TEEUP_CAPS_DIR/$name/font-apply"
    chmod +x "$TEEUP_CAPS_DIR/$name/font-apply"
  done
  local out
  out="$(font_set Hack 2>&1 </dev/null)"
  assert_contains "$out" "aaa read:[]" || return 1
  assert_contains "$out" "bbb applied" || return 1
  cleanup_test_env
}

test_set_dry_run_writes_nothing() {
  setup
  # shellcheck disable=SC2034  # last assignment in the file; read by run_cmd
  DRY_RUN=true
  local out
  out="$(font_set 'Fira Code')"
  assert_contains "$out" "[DRY-RUN] Would execute: brew install --cask font-fira-code-nerd-font" || return 1
  assert_contains "$out" "[DRY-RUN] Would write $TEST_HOME/.local/state/teeup/current/font" || return 1
  [[ ! -e "$TEST_HOME/.local/state/teeup/current/font" ]] || { echo "state written in dry run"; return 1; }
  cleanup_test_env
}

test_table_lists_every_family() {
  setup
  local out
  out="$(font_table)"
  assert_contains "$out" "JetBrainsMono" || return 1
  assert_contains "$out" "CaskaydiaMono" || return 1
  assert_contains "$out" "font-meslo-lg-nerd-font" || return 1
  cleanup_test_env
}

echo "lib/font.sh"
run_test "names normalise to the same row" test_names_normalise_to_the_same_row
run_test "every shipped family resolves" test_every_shipped_family_resolves
run_test "unknown font fails with a hint" test_unknown_font_fails_with_a_hint
run_test "current defaults to JetBrainsMono" test_current_defaults_to_jetbrains
run_test "set installs the cask and records the family" test_set_installs_the_cask_and_records_the_family
run_test "set runs font-apply hooks" test_set_runs_font_apply_hooks
run_test "set runs every hook after an interactive one" test_set_runs_every_hook_after_an_interactive_one
run_test "set dry run writes nothing" test_set_dry_run_writes_nothing
run_test "table lists every family" test_table_lists_every_family
print_summary
