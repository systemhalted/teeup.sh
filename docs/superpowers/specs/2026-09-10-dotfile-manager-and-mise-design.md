# Dotfile-manager delegation and a mise runtime backend

Design agreed in conversation on 2026-09-10. Two independent phases; phase 1
fixes an active conflict, phase 2 is a feature.

## Problem

teeup's dotfiles step symlinks a fixed list of flat files (`zshrc`, `bashrc`,
`teeup.common`, …) from `DOTFILES_DIR` into `$HOME`. When the directory does
not contain `zshrc` or `bashrc` it falls back to "managed blocks": it writes
`~/.teeup.common` and appends a source line to the target shell's rc file.

The sibling `../dotfiles` repo is now a chezmoi source directory (`dot_*`
files, `.chezmoi.toml.tmpl`, `.chezmoiignore`, run scripts). teeup still
auto-detects it, finds no `bashrc`, and takes the fallback path, which writes
into `~/.bashrc`, a file chezmoi owns. Confirmed with a dry run on Arch:

```
⚠️ DOTFILES_DIR is not available; falling back to small managed shell blocks.
🔍 [DRY-RUN] Would update /home/…/.teeup.common with: Added by teeup.sh - aliases
🔍 [DRY-RUN] Would update /home/…/.bashrc with: Added by teeup.sh - teeup.common
```

Separately, that repo moves every runtime (Java, Maven, Gradle, Ruby, Python,
uv, Go, Node) under mise. teeup has no mise support, so `--all` on such a
machine installs SDKMAN, rbenv and a second uv beside mise.

## Decision

teeup does not replace chezmoi or GNU Stow. It provisions the machine
(package manager, shell, CLI tools, runtimes) and hands `$HOME` to whichever
dotfile manager the user's repo is built for. Its own linker stays for flat
repos and the generated starter. The managed-block fallback stays for users
with no dotfiles at all.

## Phase 1: manager-aware `--dotfiles`

**Detection** (`detect_dotfiles_manager DIR`, in a new `lib/dotfiles.sh`
sourced by both scripts) returns one of `chezmoi`, `stow`, `native`, `none`:

| Result   | Evidence, checked in this order |
|----------|---------------------------------|
| chezmoi  | `.chezmoiroot`, `.chezmoi.toml.tmpl`, `.chezmoi.yaml.tmpl`, `.chezmoiignore`, or any top-level `dot_*` entry |
| stow     | explicit marker: `.stow-local-ignore` or `.stowrc` |
| native   | `zshrc` or `bashrc` at top level (teeup's flat layout) |
| stow     | package layout: a top-level non-dot directory that contains a dotted entry (e.g. `bash/.bashrc`) |
| none     | anything else |

`DOTFILES_MANAGER=auto|chezmoi|stow|native` (flag `--dotfiles-manager`)
overrides detection. `RESOLVED_DOTFILES_MANAGER` is set in
`prepare_dotfiles_source`. `dotfiles_payload_available` returns true for
`chezmoi` and `stow`, so every module's existing "handled by dotfiles" branch
fires and teeup writes nothing into rc files. For a git URL under `--dry-run`
the clone does not exist yet; detection reports `none` with a warning that the
manager is detected after the clone.

**Installation.** `ensure_dotfiles_manager_installed` runs in the dotfiles
step, after the package manager is resolved:

- stow: `pkg_install stow stow` (present in brew, MacPorts, apt, dnf, pacman).
- chezmoi: `pkg_install chezmoi chezmoi` on homebrew, dnf and pacman. apt and
  MacPorts do not package it, so those use the upstream installer
  `sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"`, listed in
  the README trust-model table. `ensure_curl` runs first.

**Hand-off** (`apply_dotfiles_with_manager`):

- chezmoi: `chezmoi init --source "$DOTFILES_DIR" --apply`. chezmoi's own
  run scripts execute here; teeup does not try to suppress them. Prompts from
  `.chezmoi.toml.tmpl` are answered interactively, or preset with
  `--promptString`/`--promptBool` via `CHEZMOI_INIT_ARGS`.
- stow: `stow -d "$DOTFILES_DIR" -t "$HOME" <packages>`. Packages are the
  top-level non-dot directories containing a dotted entry, sorted; when both
  `bash` and `zsh` exist only the `TARGET_SHELL` one is kept. `STOW_PACKAGES`
  (space-separated) overrides the list. With no package directories (a flat
  mirror of `$HOME`, reachable only via the explicit override) the call is
  `stow -d "$(dirname DIR)" -t "$HOME" "$(basename DIR)"`. Conflicts make stow
  exit non-zero; teeup warns and continues, it does not adopt or back up.
- native: unchanged linker.
- none: unchanged managed-block fallback, unless `DOTFILES_DIR` is set, in
  which case the existing warning names the directory and says no layout was
  recognised.

**Wizard.** The dotfiles step shows the detected manager beside the path
("detected: …/dotfiles, chezmoi"), the review screen adds "chezmoi will be
installed" when the binary is missing. No manual override in the wizard.

## Phase 2: `RUNTIME_MANAGER=mise` (deferred)

Deferred on 2026-09-10. On the author's machines the runtime story already
happens inside `chezmoi apply` (mise installed by the packages script,
`mise install` by the change script, activation in `~/.config/shell/init`), so
teeup's mise section would be a redundant `mise install`. The design below is
kept so it can be picked up if teeup should offer mise-managed runtimes to
users without such a dotfiles repo. The implementation plan covers phase 1
only.

`RUNTIME_MANAGER=native|mise` (flag `--runtime-manager`), default `native`,
which is today's behaviour. Rust stays on rustup in both modes.

In mise mode the python, java and ruby module bodies are skipped with a log
line, and a new section "Runtimes via mise" runs **after** the dotfiles step,
so a mise config delivered by chezmoi or Stow is already in place:

1. `ensure_mise_installed`: `pkg_install mise mise` on homebrew and pacman;
   elsewhere `curl https://mise.run | sh` (installs to `~/.local/bin`,
   listed in the trust table). Then `export PATH="$HOME/.local/bin:$PATH"`
   and `require_command_available mise`.
2. If `~/.config/mise/config.toml` or any `~/.config/mise/conf.d/*.toml`
   exists: `mise install --yes` and no pins. Otherwise, per enabled module:
   - python: `mise use -g python@$PYTHON_VERSION`, `mise use -g uv@latest`,
     and with `INSTALL_PY_TOOLS=true`: `ruff@latest`, `pipx:black@latest`,
     `pipx:httpie@latest`.
   - java: `mise use -g java@$(sdkman_to_mise_java "$JDK_VERSION")`, then
     `maven@latest` and `gradle@latest`. The mapping turns `21.0.4-tem` into
     `temurin-21.0.4`; vendor suffixes tem, amzn, zulu, librca, graalce,
     oracle, open, ms, sem map to temurin, corretto, zulu, liberica,
     graalvm-community, oracle, openjdk, microsoft, semeru. An unknown suffix
     is passed through with a warning.
   - ruby: `mise use -g ruby@$RUBY_VERSION`. `RUBYGEMS_UPDATE` and
     `BUNDLER_VERSION` are ignored in mise mode with a log line.
3. Shell activation follows the existing rule: with a dotfiles payload, log
   "mise activation is handled by dotfiles"; otherwise `append_once` a block
   to `~/.teeup.common` that adds `~/.local/bin` to PATH and runs
   `eval "$(mise activate bash|zsh)"` by `$ZSH_VERSION`.

`MISE_YES=1` is exported for the section so nothing prompts.

**Wizard.** A "Runtime manager" step appears when python, java or ruby is
selected: native (default) or mise. The Java screen keeps SDKMAN identifiers
and says they are converted for mise. `RUNTIME_MANAGER` is exported and shown
on the review screen.

## Out of scope

- Generating chezmoi- or stow-shaped starters from `--init-dotfiles`.
- Removing the SDKMAN/rbenv/pyenv fallback from the dotfiles repo.
- Having the dotfiles repo's chezmoi package script call teeup. That is a
  change to the dotfiles repo.
- `~/.config/mac-setup/zsh.zsh` is still written by the shell module. It is a
  teeup-owned file outside any rc file and harmless when nothing sources it.
