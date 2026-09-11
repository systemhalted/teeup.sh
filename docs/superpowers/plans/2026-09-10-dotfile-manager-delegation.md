# Dotfile-manager delegation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `--dotfiles` hand a chezmoi or GNU Stow repo to that tool, installing it first if needed, instead of running teeup's own symlink linker or managed-block fallback against it.

**Architecture:** Layout detection lives in a new sourced library, `lib/dotfiles.sh`, shared by `teeup.sh` and `teeup-wizard.sh`. `teeup.sh` resolves `RESOLVED_DOTFILES_MANAGER` once, right after the dotfiles source is known; `dotfiles_payload_available` treats chezmoi and stow as a payload so every existing "handled by dotfiles" branch fires, and the dotfiles step delegates to the manager before any teeup write. Phase 2 (a mise runtime backend) is deferred; see the spec.

**Tech Stack:** Bash 3.2 compatible shell (no `mapfile`, `declare -A`, or `${var,,}`), shellcheck at warning severity, the repo's own test harness (`tests/test_helper.sh`, `run_test`, mock commands).

**Spec:** `docs/superpowers/specs/2026-09-10-dotfile-manager-and-mise-design.md`

## Global Constraints

- Bash 3.2 syntax only; `tests/test_teeup.sh` fails on Bash 4 lowercase expansion.
- `shellcheck --severity=warning teeup.sh teeup-wizard.sh` and `shellcheck --severity=warning -x tests/*.sh` must pass (CI runs both).
- Every command that changes the system goes through `run_cmd` or `run_privileged` so `--dry-run` previews it.
- Package installs go through `pkg_install <pkg> <command>` (`lib/package_manager.sh:366`); it skips when the command is on PATH.
- New rc-file writes use `append_once` and are gated on `dotfiles_payload_available` exactly like the existing modules.
- Commit messages: plain imperative subject, no `Co-Authored-By` or generated-with trailer.
- Run `./tests/run_tests.sh` before every commit.

---

## Tasks

### Task 1: `lib/dotfiles.sh` with layout detection and stow package selection

**Files:**
- Create: `lib/dotfiles.sh`
- Modify: `teeup.sh:509-514` (source the new lib after `lib/shell.sh`)
- Modify: `teeup-wizard.sh` (source the lib before the Wizard State block, see step 6)
- Test: `tests/test_teeup_behavior.sh`

**Interfaces:**
- Produces: `detect_dotfiles_manager DIR` → prints `chezmoi|stow|native|none`, exit 0.
- Produces: `stow_packages DIR` → prints space-separated package names, or nothing for a flat mirror. Reads `STOW_PACKAGES` and `TARGET_SHELL`.

- [ ] **Step 1: Write the failing tests**

Add after `test_init_dotfiles_generates_neutral_starter` in `tests/test_teeup_behavior.sh`:

```bash
# lib/dotfiles.sh is pure shell; source it directly and probe fixtures.
test_detect_dotfiles_manager_layouts() {
  setup_test_env
  trap cleanup_test_env RETURN
  # shellcheck source=../lib/dotfiles.sh
  source "$PROJECT_DIR/lib/dotfiles.sh"

  local d="$TEST_HOME/chez"; mkdir -p "$d"; touch "$d/.chezmoi.toml.tmpl" "$d/dot_bashrc"
  assert_equals "chezmoi" "$(detect_dotfiles_manager "$d")" "chezmoi template marks chezmoi"

  d="$TEST_HOME/chez2"; mkdir -p "$d"; touch "$d/dot_zshrc"
  assert_equals "chezmoi" "$(detect_dotfiles_manager "$d")" "dot_* entry alone marks chezmoi"

  d="$TEST_HOME/stow"; mkdir -p "$d/bash" "$d/zsh"; touch "$d/bash/.bashrc" "$d/zsh/.zshrc"
  assert_equals "stow" "$(detect_dotfiles_manager "$d")" "package dirs with dotted files mark stow"

  d="$TEST_HOME/stow2"; mkdir -p "$d"; touch "$d/.stow-local-ignore"
  assert_equals "stow" "$(detect_dotfiles_manager "$d")" ".stow-local-ignore marks stow"

  d="$TEST_HOME/native"; mkdir -p "$d"; touch "$d/bashrc" "$d/.bash_profile" "$d/teeup.common"
  assert_equals "native" "$(detect_dotfiles_manager "$d")" "flat zshrc/bashrc marks native"

  d="$TEST_HOME/empty"; mkdir -p "$d/.git"; touch "$d/.git/.dotted" "$d/README.md"
  assert_equals "none" "$(detect_dotfiles_manager "$d")" "no markers gives none; .git is ignored"

  assert_equals "none" "$(detect_dotfiles_manager "$TEST_HOME/missing")" "missing dir gives none"
}

test_stow_packages_filters_shells() {
  setup_test_env
  trap cleanup_test_env RETURN
  # shellcheck source=../lib/dotfiles.sh
  source "$PROJECT_DIR/lib/dotfiles.sh"

  local d="$TEST_HOME/stow"
  mkdir -p "$d/bash" "$d/zsh" "$d/common" "$d/docs"
  touch "$d/bash/.bashrc" "$d/zsh/.zshrc" "$d/common/.gitconfig" "$d/docs/README.md"

  assert_equals "bash common" "$(TARGET_SHELL=bash stow_packages "$d")" "bash target drops zsh, keeps common, skips docs"
  assert_equals "common zsh" "$(TARGET_SHELL=zsh stow_packages "$d")" "zsh target drops bash"
  assert_equals "only this" "$(STOW_PACKAGES='only this' stow_packages "$d")" "STOW_PACKAGES overrides"

  local flat="$TEST_HOME/flat"; mkdir -p "$flat"; touch "$flat/.bashrc"
  assert_equals "" "$(TARGET_SHELL=bash stow_packages "$flat")" "no package dirs gives empty (flat mirror)"
}
```

Register at the end of the file, after the last existing `run_test` line:

```bash
run_test "detect_dotfiles_manager recognises layouts" test_detect_dotfiles_manager_layouts
run_test "stow_packages filters by target shell" test_stow_packages_filters_shells
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./tests/test_teeup_behavior.sh 2>&1 | grep -A3 'detect_dotfiles_manager\|stow_packages'`
Expected: both FAIL, output mentions `lib/dotfiles.sh: No such file`.

- [ ] **Step 3: Create `lib/dotfiles.sh`**

```bash
#!/usr/bin/env bash
# dotfiles.sh — recognise which tool a dotfiles directory is built for.
#
# teeup does not replace chezmoi or GNU Stow: it provisions the machine and hands
# $HOME to whichever manager the user's repo expects. These helpers are pure
# shell (no logging, no side effects) so the wizard can source them too.

# Print the manager a dotfiles directory is laid out for:
#   chezmoi  .chezmoiroot / .chezmoi.*.tmpl / .chezmoiignore / any top-level dot_* entry
#   stow     .stow-local-ignore / .stowrc / a top-level non-dot dir holding a dotted entry
#   native   teeup's flat layout: zshrc or bashrc at the top level
#   none     nothing recognised (also for a missing directory)
detect_dotfiles_manager() {
  local dir="$1" entry sub
  [[ -d "$dir" ]] || { echo "none"; return 0; }

  for entry in .chezmoiroot .chezmoi.toml.tmpl .chezmoi.yaml.tmpl .chezmoi.json.tmpl .chezmoiignore; do
    if [[ -e "$dir/$entry" ]]; then echo "chezmoi"; return 0; fi
  done
  for entry in "$dir"/dot_*; do
    if [[ -e "$entry" ]]; then echo "chezmoi"; return 0; fi
  done

  for entry in .stow-local-ignore .stowrc; do
    if [[ -e "$dir/$entry" ]]; then echo "stow"; return 0; fi
  done
  for sub in "$dir"/*/; do
    [[ -d "$sub" ]] || continue
    for entry in "$sub".??*; do
      if [[ -e "$entry" ]]; then echo "stow"; return 0; fi
    done
  done

  if [[ -f "$dir/zshrc" || -f "$dir/bashrc" ]]; then echo "native"; return 0; fi
  echo "none"
}

# Print the stow packages to apply from DIR, space-separated and sorted.
# STOW_PACKAGES overrides. Otherwise every top-level non-dot directory that
# contains a dotted entry is a package; when both bash and zsh packages exist
# only the TARGET_SHELL one survives. Empty output means "no packages": the
# directory is a flat mirror of $HOME and the caller stows it as one package.
stow_packages() {
  local dir="$1" sub name entry pkgs="" other_shell
  if [[ -n "${STOW_PACKAGES:-}" ]]; then
    echo "$STOW_PACKAGES"
    return 0
  fi
  case "${TARGET_SHELL:-bash}" in
    zsh) other_shell="bash" ;;
    *)   other_shell="zsh" ;;
  esac
  for sub in "$dir"/*/; do
    [[ -d "$sub" ]] || continue
    name="$(basename "$sub")"
    [[ "$name" == "$other_shell" ]] && continue
    for entry in "$sub".??*; do
      if [[ -e "$entry" ]]; then
        pkgs="${pkgs:+$pkgs }$name"
        break
      fi
    done
  done
  echo "$pkgs"
}
```

The `for sub in "$dir"/*/` glob is sorted by the shell, so output order is alphabetical without calling `sort`.

- [ ] **Step 4: Source the lib from `teeup.sh`**

After the `source "$SCRIPT_DIR/lib/shell.sh"` line (`teeup.sh:514`):

```bash
# shellcheck source=lib/dotfiles.sh
source "$SCRIPT_DIR/lib/dotfiles.sh"
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `./tests/test_teeup_behavior.sh 2>&1 | grep 'detect_dotfiles_manager\|stow_packages'`
Expected: both PASS.

- [ ] **Step 6: Source the lib from the wizard**

In `teeup-wizard.sh`, immediately before the `# ===== Wizard State =====` banner (around line 392), add:

```bash
# Shared layout detection (also used by teeup.sh).
WIZARD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=lib/dotfiles.sh
source "$WIZARD_LIB_DIR/dotfiles.sh"
```

- [ ] **Step 7: Shellcheck and full suite**

Run: `shellcheck --severity=warning teeup.sh teeup-wizard.sh lib/dotfiles.sh && shellcheck --severity=warning -x tests/*.sh && ./tests/run_tests.sh`
Expected: shellcheck silent; suite summary shows all passed.

- [ ] **Step 8: Commit**

```bash
git add lib/dotfiles.sh teeup.sh teeup-wizard.sh tests/test_teeup_behavior.sh
git commit -m "Add dotfiles layout detection for chezmoi, stow and the flat layout"
```

---

### Task 2: `DOTFILES_MANAGER` resolution and payload gating

**Files:**
- Modify: `teeup.sh:40-45` (toggle block), `teeup.sh:85-90` (source controls), `teeup.sh:431-438` (`dotfiles_payload_available`), `teeup.sh:483-508` (`prepare_dotfiles_source`), help text `teeup.sh:657-684`, arg parsing near `teeup.sh:1020` (`--dotfiles`)
- Test: `tests/test_teeup_behavior.sh`, `tests/test_teeup.sh`

**Interfaces:**
- Consumes: `detect_dotfiles_manager` from Task 1.
- Produces: global `DOTFILES_MANAGER` (`auto|chezmoi|stow|native`, default `auto`), global `RESOLVED_DOTFILES_MANAGER` (`chezmoi|stow|native|none`), flag `--dotfiles-manager NAME`. `dotfiles_payload_available` returns 0 for `chezmoi` and `stow`.

- [ ] **Step 1: Write the failing tests**

Behaviour test (append to `tests/test_teeup_behavior.sh` after Task 1's tests):

```bash
# A chezmoi-shaped overlay counts as a payload: runtime modules must not write rc blocks
# and the managed-block fallback must not fire.
test_chezmoi_layout_counts_as_payload() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands
  mock_runtime_commands

  local df="$TEST_HOME/dotfiles"
  mkdir -p "$df"
  touch "$df/.chezmoi.toml.tmpl" "$df/dot_bashrc"

  local output
  output=$(DRY_RUN=true TARGET_SHELL=bash PACKAGE_MANAGER=pacman \
    DOTFILES_DIR="$df" "$PROJECT_DIR/teeup.sh" --only rust 2>&1)

  assert_contains "$output" "Cargo PATH is handled by dotfiles." "rust module must defer to the manager"
  assert_contains "$output" "Dotfiles manager: chezmoi" "should report the resolved manager"
  if [[ "$output" == *"falling back to small managed shell blocks"* ]]; then
    echo "FAIL: managed-block fallback must not fire for a chezmoi layout"; return 1
  fi
  if [[ "$output" == *"Would update $HOME/.bashrc"* ]]; then
    echo "FAIL: must not write into a chezmoi-managed rc file"; return 1
  fi
}

test_dotfiles_manager_override_and_validation() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands

  local df="$TEST_HOME/dotfiles"
  mkdir -p "$df"; touch "$df/.bashrc"

  local output
  output=$(DRY_RUN=true TARGET_SHELL=bash PACKAGE_MANAGER=pacman \
    DOTFILES_DIR="$df" "$PROJECT_DIR/teeup.sh" --only cli --dotfiles-manager stow 2>&1)
  assert_contains "$output" "Dotfiles manager: stow" "--dotfiles-manager should force stow"

  set +e
  output=$(DRY_RUN=true PACKAGE_MANAGER=pacman "$PROJECT_DIR/teeup.sh" --only cli --dotfiles-manager yadm 2>&1)
  local rc=$?
  set -e
  assert_failure "$rc" "unknown manager must fail"
  assert_contains "$output" "DOTFILES_MANAGER" "error should name the variable"
}
```

Register:

```bash
run_test "chezmoi layout counts as a dotfiles payload" test_chezmoi_layout_counts_as_payload
run_test "--dotfiles-manager override and validation" test_dotfiles_manager_override_and_validation
```

Static test: in `tests/test_teeup.sh`, inside `test_profile_and_selection_flags` (line 294) add:

```bash
  assert_contains "$content" "--dotfiles-manager)" "Should support --dotfiles-manager flag"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./tests/test_teeup_behavior.sh 2>&1 | grep -A6 'chezmoi layout counts\|dotfiles-manager override'`
Expected: both FAIL. The first because the fallback fires and "Dotfiles manager:" is missing, the second because `--dotfiles-manager` is an unknown option.

- [ ] **Step 3: Add the toggle and its normaliser**

In the toggle block after `DOTFILES_DIR=...` (`teeup.sh:44`):

```bash
DOTFILES_MANAGER="${DOTFILES_MANAGER:-auto}"    # auto, chezmoi, stow, or native (teeup's own linker)
```

Next to the source controls (`teeup.sh:88-90`):

```bash
# Set by prepare_dotfiles_source from DOTFILES_MANAGER and the overlay's layout:
# chezmoi | stow | native | none. "none" means no recognised payload (managed blocks).
RESOLVED_DOTFILES_MANAGER="none"
```

Add this function right after `dotfiles_payload_available` (`teeup.sh:438`):

```bash
normalize_dotfiles_manager() {
  local value_lower
  value_lower=$(echo "${DOTFILES_MANAGER:-auto}" | tr '[:upper:]' '[:lower:]')
  case "$value_lower" in
    auto|chezmoi|stow|native) DOTFILES_MANAGER="$value_lower" ;;
    *)
      err "Unknown DOTFILES_MANAGER '${DOTFILES_MANAGER}'. Use auto, chezmoi, stow, or native."
      exit 1
      ;;
  esac
}
```

- [ ] **Step 4: Rewrite `dotfiles_payload_available`**

Replace the function at `teeup.sh:431-438` with:

```bash
# True when the overlay can deliver rc files itself, so teeup must not write any.
# chezmoi/stow own $HOME once applied; the native layout needs the target shell's
# rc file to be present in the overlay.
dotfiles_payload_available() {
  [[ -n "$DOTFILES_DIR" ]] || return 1
  case "$RESOLVED_DOTFILES_MANAGER" in
    chezmoi|stow) return 0 ;;
    none) return 1 ;;
  esac
  case "${TARGET_SHELL:-}" in
    zsh)  [[ -f "$DOTFILES_DIR/zshrc" ]] ;;
    bash) [[ -f "$DOTFILES_DIR/bashrc" ]] ;;
    *)    [[ -f "$DOTFILES_DIR/zshrc" || -f "$DOTFILES_DIR/bashrc" ]] ;;
  esac
}
```

- [ ] **Step 5: Resolve the manager in `prepare_dotfiles_source`**

Append to the end of `prepare_dotfiles_source` (after the `fi` that closes the `DOTFILES_SOURCE` branch, `teeup.sh:~507`), still inside the function:

```bash
  resolve_dotfiles_manager
}

# Pick the manager for DOTFILES_DIR. An explicit DOTFILES_MANAGER wins; otherwise the
# layout decides. A git URL under --dry-run has no clone yet, so detection cannot run.
resolve_dotfiles_manager() {
  normalize_dotfiles_manager
  RESOLVED_DOTFILES_MANAGER="none"
  [[ -n "$DOTFILES_DIR" ]] || return 0

  if [[ "$DOTFILES_MANAGER" != "auto" ]]; then
    RESOLVED_DOTFILES_MANAGER="$DOTFILES_MANAGER"
  elif [[ ! -d "$DOTFILES_DIR" ]]; then
    # A missing directory is either a --dry-run git URL (clone previewed, not made)
    # or a stale path; the dotfiles step already warns about the latter.
    if [[ -n "$DOTFILES_SOURCE" ]] && looks_like_git_url "$DOTFILES_SOURCE"; then
      warn "Dotfiles clone is previewed only; the manager is detected after a real clone."
    fi
    return 0
  else
    RESOLVED_DOTFILES_MANAGER="$(detect_dotfiles_manager "$DOTFILES_DIR")"
  fi

  case "$RESOLVED_DOTFILES_MANAGER" in
    none) warn "No recognised dotfiles layout in $DOTFILES_DIR (expected chezmoi, stow, or zshrc/bashrc); managed blocks will be used." ;;
    *)    ok "Dotfiles manager: $RESOLVED_DOTFILES_MANAGER ($DOTFILES_DIR)" ;;
  esac
}
```

Existing tests pass `DOTFILES_DIR="$TEST_HOME/no-dotfiles"` (a path that does not exist) to force the managed-block path. That still works: the directory is missing, no URL was given, so the function returns with `none` and no new output.

Delete the original closing `}` of `prepare_dotfiles_source` that the first line above replaces.

- [ ] **Step 6: Parse the flag and document it**

In the argument loop, after the `--dotfiles)` case (`teeup.sh:~1020-1028`):

```bash
    --dotfiles-manager)
      if [[ -z "${2:-}" ]]; then
        err "--dotfiles-manager requires one of: auto, chezmoi, stow, native"
        exit 1
      fi
      DOTFILES_MANAGER="$2"
      shift 2
      ;;
```

Help text, after the `--dotfiles PATH|URL` lines (`teeup.sh:~659-660`):

```
  --dotfiles-manager M  Which tool deploys the overlay: auto (detect from layout,
                        default), chezmoi, stow, or native (teeup's own symlinks).
```

And in the Environment Variables list after `DOTFILES_DIR`:

```
  DOTFILES_MANAGER      auto, chezmoi, stow, or native (default: auto)
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `./tests/test_teeup_behavior.sh 2>&1 | grep 'chezmoi layout counts\|dotfiles-manager override'` and `./tests/test_teeup.sh 2>&1 | grep 'Profile and selection'`
Expected: all PASS.

- [ ] **Step 8: Full suite, shellcheck, commit**

Run: `shellcheck --severity=warning teeup.sh && ./tests/run_tests.sh`

```bash
git add teeup.sh tests/test_teeup_behavior.sh tests/test_teeup.sh
git commit -m "Resolve the dotfiles manager from the overlay layout"
```

---

### Task 3: Install the manager and hand off in the dotfiles step

**Files:**
- Modify: `teeup.sh` helpers after `install_dotfile_link` (`teeup.sh:~343`), and the "Shell dotfiles add" section (`teeup.sh:2002-2057`)
- Modify: `tests/test_helper.sh` (mock for chezmoi/stow), `tests/test_teeup_behavior.sh`

**Interfaces:**
- Consumes: `RESOLVED_DOTFILES_MANAGER`, `stow_packages`, `pkg_install`, `prepare_package_manager`, `ensure_curl`, `run_cmd`, `remember_installed`.
- Produces: `ensure_dotfiles_manager_installed`, `apply_dotfiles_with_manager`. Env `CHEZMOI_INIT_ARGS` (extra words appended to `chezmoi init`), `STOW_PACKAGES`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_helper.sh` after `mock_runtime_commands`:

```bash
mock_dotfiles_manager_commands() {
  mock_command_script chezmoi <<'EOF'
echo "chezmoi $*" >> "$MOCK_LOG"
exit 0
EOF
  mock_command_script stow <<'EOF'
echo "stow $*" >> "$MOCK_LOG"
exit 0
EOF
}
```

Append to `tests/test_teeup_behavior.sh`:

```bash
test_chezmoi_layout_installs_and_applies() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands
  # chezmoi deliberately NOT mocked: the install path must be exercised.

  local df="$TEST_HOME/dotfiles"
  mkdir -p "$df"; touch "$df/.chezmoi.toml.tmpl" "$df/dot_bashrc"

  local output
  output=$(DRY_RUN=true TARGET_SHELL=bash PACKAGE_MANAGER=pacman \
    DOTFILES_DIR="$df" "$PROJECT_DIR/teeup.sh" --only cli 2>&1)

  assert_contains "$output" "[DRY-RUN] Would execute: sudo pacman -S --needed --noconfirm chezmoi" "should install chezmoi via pacman"
  assert_contains "$output" "[DRY-RUN] Would execute: chezmoi init --source $df --apply" "should hand off to chezmoi"
  if [[ "$output" == *"ln -s "* ]]; then
    echo "FAIL: teeup must not symlink when chezmoi owns the overlay"; return 1
  fi
  if [[ "$output" == *"Would update $HOME/.teeup.common"* ]]; then
    echo "FAIL: no managed blocks when chezmoi owns the overlay"; return 1
  fi
}

test_chezmoi_on_apt_uses_upstream_installer() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands
  mock_command curl 0 ""

  local df="$TEST_HOME/dotfiles"
  mkdir -p "$df"; touch "$df/dot_bashrc"

  local output
  output=$(DRY_RUN=true TARGET_SHELL=bash PACKAGE_MANAGER=apt \
    DOTFILES_DIR="$df" "$PROJECT_DIR/teeup.sh" --only cli 2>&1)

  assert_contains "$output" "get.chezmoi.io" "apt has no chezmoi package; use the upstream installer"
  if [[ "$output" == *"apt-get install -y chezmoi"* ]]; then
    echo "FAIL: must not try apt-get install chezmoi"; return 1
  fi
}

test_chezmoi_present_skips_install() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands
  mock_dotfiles_manager_commands

  local df="$TEST_HOME/dotfiles"
  mkdir -p "$df"; touch "$df/dot_zshrc"

  local output
  output=$(DRY_RUN=true TARGET_SHELL=zsh PACKAGE_MANAGER=pacman \
    DOTFILES_DIR="$df" "$PROJECT_DIR/teeup.sh" --only cli 2>&1)

  assert_contains "$output" "chezmoi init --source $df --apply" "should still apply"
  if [[ "$output" == *"--noconfirm chezmoi"* || "$output" == *"get.chezmoi.io"* ]]; then
    echo "FAIL: chezmoi already on PATH must not be installed again"; return 1
  fi
}

test_stow_layout_applies_target_shell_packages() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands

  local df="$TEST_HOME/dotfiles"
  mkdir -p "$df/bash" "$df/zsh" "$df/common"
  touch "$df/bash/.bashrc" "$df/zsh/.zshrc" "$df/common/.gitconfig"

  local output
  output=$(DRY_RUN=true TARGET_SHELL=bash PACKAGE_MANAGER=pacman \
    DOTFILES_DIR="$df" "$PROJECT_DIR/teeup.sh" --only cli 2>&1)

  assert_contains "$output" "[DRY-RUN] Would execute: sudo pacman -S --needed --noconfirm stow" "should install stow"
  assert_contains "$output" "[DRY-RUN] Would execute: stow -d $df -t $HOME bash common" "should stow bash + common, not zsh"
}

test_stow_override_on_flat_mirror() {
  setup_test_env
  trap cleanup_test_env RETURN
  mock_linux_base_commands
  mock_linux_package_manager_commands
  mock_dotfiles_manager_commands

  local df="$TEST_HOME/home-mirror"
  mkdir -p "$df/.config"; touch "$df/.bashrc" "$df/.config/starship.toml"

  local output
  output=$(DRY_RUN=true TARGET_SHELL=bash PACKAGE_MANAGER=pacman \
    DOTFILES_DIR="$df" "$PROJECT_DIR/teeup.sh" --only cli --dotfiles-manager stow 2>&1)

  assert_contains "$output" "[DRY-RUN] Would execute: stow -d $TEST_HOME -t $HOME home-mirror" "flat mirror is stowed as one package from its parent"
}
```

Register:

```bash
run_test "chezmoi layout installs chezmoi and applies" test_chezmoi_layout_installs_and_applies
run_test "chezmoi on apt uses upstream installer" test_chezmoi_on_apt_uses_upstream_installer
run_test "chezmoi on PATH is not reinstalled" test_chezmoi_present_skips_install
run_test "stow layout applies target-shell packages" test_stow_layout_applies_target_shell_packages
run_test "--dotfiles-manager stow on a flat mirror" test_stow_override_on_flat_mirror
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./tests/test_teeup_behavior.sh 2>&1 | grep -A4 'chezmoi layout installs\|chezmoi on apt\|chezmoi on PATH\|stow layout\|flat mirror'`
Expected: all five FAIL. None of the install or hand-off lines appear yet.

- [ ] **Step 3: Add the helpers**

Insert after `install_dotfile_link` (`teeup.sh:~343`):

```bash
# Make sure the resolved dotfiles manager binary exists. Stow is packaged everywhere
# teeup runs. chezmoi is packaged by Homebrew, dnf and pacman; apt and MacPorts are
# not, so those use the upstream installer (listed in the README trust table).
# Mirrors ensure_curl: a run without the package-manager module still needs the
# index refreshed before pkg_install.
ensure_dotfiles_manager_installed() {
  case "$RESOLVED_DOTFILES_MANAGER" in
    stow)
      have stow && { remember_skipped "stow"; return 0; }
      [[ "$RUN_HOMEBREW" == "true" ]] || prepare_package_manager
      pkg_install stow stow
      require_command_available stow "stow install"
      ;;
    chezmoi)
      have chezmoi && { remember_skipped "chezmoi"; return 0; }
      case "$RESOLVED_PACKAGE_MANAGER" in
        apt|macports)
          log "Installing chezmoi with the upstream installer (no $RESOLVED_PACKAGE_MANAGER package)…"
          ensure_curl
          run_cmd mkdir -p "$HOME/.local/bin"
          if [[ "$DRY_RUN" == "true" ]]; then
            run_cmd sh -c "curl -fsLS get.chezmoi.io | sh -s -- -b $HOME/.local/bin"
          else
            sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
          fi
          export PATH="$HOME/.local/bin:$PATH"
          ;;
        *)
          [[ "$RUN_HOMEBREW" == "true" ]] || prepare_package_manager
          pkg_install chezmoi chezmoi
          ;;
      esac
      remember_installed "chezmoi"
      require_command_available chezmoi "chezmoi install"
      ;;
  esac
}

# Hand $HOME to the manager. Nothing here backs up or adopts: chezmoi diffs and
# overwrites by design, stow refuses on conflicts and we surface that.
apply_dotfiles_with_manager() {
  case "$RESOLVED_DOTFILES_MANAGER" in
    chezmoi)
      log "Applying dotfiles with chezmoi from $DOTFILES_DIR"
      # shellcheck disable=SC2086  # CHEZMOI_INIT_ARGS is intentionally word-split
      run_cmd chezmoi init --source "$DOTFILES_DIR" --apply ${CHEZMOI_INIT_ARGS:-} \
        || warn "chezmoi apply returned non-zero; run 'chezmoi diff' to inspect."
      remember_installed "dotfiles (chezmoi)"
      ;;
    stow)
      local pkgs
      pkgs="$(stow_packages "$DOTFILES_DIR")"
      if [[ -n "$pkgs" ]]; then
        log "Stowing packages from $DOTFILES_DIR: $pkgs"
        # shellcheck disable=SC2086  # package list is intentionally word-split
        run_cmd stow -d "$DOTFILES_DIR" -t "$HOME" $pkgs \
          || warn "stow reported conflicts; move the existing files aside and rerun."
      else
        log "Stowing $DOTFILES_DIR as a single package (flat mirror of \$HOME)"
        run_cmd stow -d "$(dirname "$DOTFILES_DIR")" -t "$HOME" "$(basename "$DOTFILES_DIR")" \
          || warn "stow reported conflicts; move the existing files aside and rerun."
      fi
      remember_installed "dotfiles (stow)"
      ;;
  esac
}
```

- [ ] **Step 4: Branch the dotfiles section**

Replace the opening of the "Shell dotfiles add" section (`teeup.sh:2004-2006`):

```bash
if [[ "$INSTALL_DOTFILES" == "true" ]]; then
  if dotfiles_payload_available; then
    log "Installing dotfiles from $DOTFILES_DIR for $TARGET_SHELL"
```

with:

```bash
if [[ "$INSTALL_DOTFILES" == "true" ]]; then
  if [[ "$RESOLVED_DOTFILES_MANAGER" == "chezmoi" || "$RESOLVED_DOTFILES_MANAGER" == "stow" ]]; then
    ensure_dotfiles_manager_installed
    apply_dotfiles_with_manager
  elif dotfiles_payload_available; then
    log "Installing dotfiles from $DOTFILES_DIR for $TARGET_SHELL"
```

The rest of the section (native linking, then the `else` managed-block fallback) is unchanged.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `./tests/test_teeup_behavior.sh 2>&1 | grep 'chezmoi layout installs\|chezmoi on apt\|chezmoi on PATH\|stow layout\|flat mirror'`
Expected: all PASS. If the pacman test fails on the `-Syu` line order, check that `prepare_package_manager` is only called when `RUN_HOMEBREW` is not `true`.

- [ ] **Step 6: Manual dry run against the real sibling repo**

Run: `./teeup.sh --dry-run --only cli 2>&1 | grep -i 'dotfiles manager\|chezmoi\|bashrc\|managed'`
Expected: `Dotfiles manager: chezmoi (...)`, a `chezmoi init --source ... --apply` preview, and no `Would update .../.bashrc` line.

- [ ] **Step 7: Full suite, shellcheck, commit**

Run: `shellcheck --severity=warning teeup.sh && shellcheck --severity=warning -x tests/*.sh && ./tests/run_tests.sh`

```bash
git add teeup.sh tests/test_helper.sh tests/test_teeup_behavior.sh
git commit -m "Hand chezmoi and stow overlays to their manager instead of symlinking"
```

---

### Task 4: Wizard shows the detected manager

**Files:**
- Modify: `teeup-wizard.sh:1150-1210` (`show_additional_options`), `teeup-wizard.sh:1336-1340` (summary)
- Test: `tests/test_teeup_wizard.sh:142-149` (`test_dotfiles_step`)

**Interfaces:**
- Consumes: `detect_dotfiles_manager` (sourced in Task 1).
- Produces: `WIZARD_DOTFILES_MANAGER` (`chezmoi|stow|native|none|` empty for URL).

- [ ] **Step 1: Write the failing test**

In `test_dotfiles_step` (`tests/test_teeup_wizard.sh:142`) add:

```bash
  assert_contains "$content" "WIZARD_DOTFILES_MANAGER" "Should track the detected dotfiles manager"
  assert_contains "$content" "detect_dotfiles_manager" "Should detect the manager for the chosen path"
  assert_contains "$content" "will be installed" "Should warn when the manager binary is missing"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/test_teeup_wizard.sh 2>&1 | grep -A4 'Dotfiles base/overlay'`
Expected: FAIL on `WIZARD_DOTFILES_MANAGER`.

- [ ] **Step 3: Add state and detection**

State block (after `WIZARD_INIT_DOTFILES_DIR=""`, `teeup-wizard.sh:~414`):

```bash
# Filled by show_additional_options: chezmoi | stow | native | none, or empty for a
# git URL (detected after teeup.sh clones it).
WIZARD_DOTFILES_MANAGER=""
```

Add two helpers before `show_additional_options`. The first sets the global and must be called directly (not in `$(...)`, which would lose the assignment); the second only formats:

```bash
# Set WIZARD_DOTFILES_MANAGER from a path. A git URL cannot be inspected before
# teeup.sh clones it, so it leaves the variable empty.
wizard_detect_dotfiles_manager() {
  local src="$1"
  WIZARD_DOTFILES_MANAGER=""
  case "$src" in
    *://*|git@*:*) return 0 ;;
  esac
  WIZARD_DOTFILES_MANAGER="$(detect_dotfiles_manager "$src")"
}

# Human label for WIZARD_DOTFILES_MANAGER.
wizard_dotfiles_manager_label() {
  case "$WIZARD_DOTFILES_MANAGER" in
    chezmoi|stow) echo "$WIZARD_DOTFILES_MANAGER" ;;
    native)       echo "teeup symlinks" ;;
    none)         echo "unrecognised layout" ;;
    *)            echo "detected after clone" ;;
  esac
}
```

In `show_additional_options`, change the sibling-detected menu line to include the label:

```bash
  if [[ -n "$sibling_dotfiles" ]]; then
    wizard_detect_dotfiles_manager "$sibling_dotfiles"
    echo -e "  ${BOLD}1)${RESET} Use existing dotfiles  ${DIM}(detected: $sibling_dotfiles, $(wizard_dotfiles_manager_label))${RESET}"
  else
```

After `WIZARD_DOTFILES_SOURCE` is final in case `1)` (both branches), add:

```bash
      if [[ -n "$WIZARD_DOTFILES_SOURCE" ]]; then
        wizard_detect_dotfiles_manager "$WIZARD_DOTFILES_SOURCE"
        print_info "Dotfiles will be deployed by: $(wizard_dotfiles_manager_label)"
        if [[ "$WIZARD_DOTFILES_MANAGER" == "chezmoi" || "$WIZARD_DOTFILES_MANAGER" == "stow" ]] \
           && ! command -v "$WIZARD_DOTFILES_MANAGER" >/dev/null 2>&1; then
          print_info "$WIZARD_DOTFILES_MANAGER is not installed; it will be installed first."
        fi
      fi
```

- [ ] **Step 4: Summary line**

Replace the `existing)` line in `show_summary` (`teeup-wizard.sh:~1337`):

```bash
    existing)
      echo -e "  Dotfiles: ${CYAN}use existing (${WIZARD_DOTFILES_SOURCE:-auto-detected})${RESET}"
      case "$WIZARD_DOTFILES_MANAGER" in
        chezmoi|stow)
          if command -v "$WIZARD_DOTFILES_MANAGER" >/dev/null 2>&1; then
            echo -e "  Dotfiles manager: ${CYAN}$WIZARD_DOTFILES_MANAGER${RESET}"
          else
            echo -e "  Dotfiles manager: ${CYAN}$WIZARD_DOTFILES_MANAGER${RESET} ${YELLOW}(will be installed)${RESET}"
          fi
          ;;
      esac
      ;;
```

- [ ] **Step 5: Run the wizard tests and the full suite**

Run: `./tests/test_teeup_wizard.sh 2>&1 | grep 'Dotfiles base/overlay'` then `shellcheck --severity=warning teeup-wizard.sh && ./tests/run_tests.sh`
Expected: PASS; suite green.

- [ ] **Step 6: Commit**

```bash
git add teeup-wizard.sh tests/test_teeup_wizard.sh
git commit -m "Show the detected dotfiles manager in the wizard"
```

---

### Task 5: Documentation

**Files:**
- Modify: `README.md` (Features bullet on dotfiles, "Dotfiles: a neutral base + your overlay" section, Customization env block, Trust Model table, Test Coverage list)
- Modify: `CHANGELOG.md` `[Unreleased]`

- [ ] **Step 1: README**

In the Features list replace the "Dotfiles your way" bullet with:

```markdown
- ✅ Dotfiles your way: point teeup at a **chezmoi** or **GNU Stow** repo and it installs that tool and hands `$HOME` to it; point it at a flat directory (or `--init-dotfiles` a starter) and teeup symlinks it; with no dotfiles it falls back to minimal managed shell blocks
```

In "Dotfiles: a neutral base + your overlay", after the "Bring your own" bullet add:

```markdown
  teeup looks at the directory's layout to decide who deploys it:

  | Layout | Deployed by | What teeup runs |
  |--------|-------------|-----------------|
  | `dot_*` files, `.chezmoi.toml.tmpl`, `.chezmoiignore` | chezmoi | `chezmoi init --source DIR --apply` |
  | package directories (`bash/.bashrc`, `common/.gitconfig`), `.stowrc` | GNU Stow | `stow -d DIR -t ~ <packages>` (only the package for your login shell when both `bash` and `zsh` exist; `STOW_PACKAGES` overrides) |
  | flat `zshrc`, `bashrc`, `teeup.common` | teeup | the symlinks described below |

  The manager is installed first when missing (chezmoi through the upstream
  installer on apt and MacPorts, which do not package it). teeup writes nothing
  into rc files a manager owns. Force a choice with `--dotfiles-manager
  chezmoi|stow|native`; a flat mirror of `$HOME` needs `--dotfiles-manager stow`.
  Extra `chezmoi init` words (for example `--promptBool work=true`) go in
  `CHEZMOI_INIT_ARGS`.
```

Customization block: add after `INSTALL_DOTFILES=...`:

```sh
DOTFILES_MANAGER="${DOTFILES_MANAGER:-auto}"        # auto, chezmoi, stow, or native
```

Trust Model table: add a row `| chezmoi   | \`https://get.chezmoi.io\` (apt and MacPorts only) |`.

Test Coverage, "teeup.sh behavior tests": add `- Dotfiles manager detection (chezmoi / stow / flat) and hand-off, including the apt installer path`.

- [ ] **Step 2: CHANGELOG**

Under `## [Unreleased]` → `### Added`, before the pacman entry:

```markdown
- **chezmoi and GNU Stow overlays.** `--dotfiles` now recognises a chezmoi source
  directory (`dot_*`, `.chezmoi.toml.tmpl`) or a Stow package tree and hands
  `$HOME` to that tool (`chezmoi init --source DIR --apply`, `stow -d DIR -t ~`)
  after installing it if needed. teeup writes nothing into rc files a manager
  owns, so `chezmoi diff` stays clean after a teeup run. The flat layout and the
  managed-block fallback are unchanged. `--dotfiles-manager` (or
  `DOTFILES_MANAGER`) forces a choice; `STOW_PACKAGES` and `CHEZMOI_INIT_ARGS`
  tune the hand-off. The wizard shows the detected manager.
```

Under `### Migration` add:

```markdown
- A sibling `../dotfiles` that has moved to chezmoi previously triggered the
  managed-block fallback and appended a source line to `~/.bashrc`/`~/.zshrc`.
  It is now applied with chezmoi instead. Remove the stale `# Added by teeup.sh -
  teeup.common` block from your rc file if one was written, or let `chezmoi apply`
  overwrite it.
```

- [ ] **Step 3: Verify and commit**

Run: `./tests/run_tests.sh` (the README test-coverage list is prose; nothing executes it, but the suite must still be green).

```bash
git add README.md CHANGELOG.md
git commit -m "Document chezmoi and stow overlay support"
```

---

## Verification

After all five tasks:

1. `./tests/run_tests.sh` green on Linux and, if available, macOS.
2. `shellcheck --severity=warning teeup.sh teeup-wizard.sh lib/*.sh` and `shellcheck --severity=warning -x tests/*.sh` clean.
3. On this Arch machine with the chezmoi sibling:
   `./teeup.sh --dry-run --only cli` previews `chezmoi init --source … --apply` and never `Would update …/.bashrc`.
4. `./teeup-wizard.sh`, minimal setup, dotfiles option 1: the menu shows "chezmoi" next to the sibling path and the review screen lists the manager.
5. Flat-layout regression: `DOTFILES_DIR=$(mktemp -d)` with `bashrc`, `.bash_profile`, `profile`, `teeup.common` inside still previews `ln -s` lines and nothing about chezmoi or stow.
6. Managed-block regression: `DOTFILES_DIR=/nonexistent ./teeup.sh --dry-run --only bash` still previews the `teeup.common` block and the `.bashrc` source line.
