# teeup redesign: Omarchy-inspired macOS environment distribution

Date: 2026-09-11
Status: approved design, pre-implementation
Amended: 2026-09-17, one identity (user decision; see the Git, SSH/signing, Dev dirs and Work vs personal rows of the interview table, section 4b, section 8 and section 10)

## Context

`teeup.sh` is a 2300-line monolithic installer plus a 1700-line wizard that re-invokes it. It has no config file, fuses install and configure inside each module, duplicates its model in the wizard, and has been superseded for dotfile delivery by a chezmoi repo. The user wants teeup to become a personal macOS environment distribution in the spirit of Omarchy: modular capabilities, lazy installation, configuration separate from installation, opinionated defaults with an answers file and machine overrides, idempotent, discoverable, native to macOS. Scope is macOS only; the chezmoi repo continues to serve Linux.

The architecture below is the recommended design. Sections 1 to 12 answer the twelve questions in the request.

## Research findings

### Current teeup.sh (branch feat/dotfiles-manager-delegation)

- `teeup.sh` 2293 lines: functions 1-1225, then a linear top-level phase script 1227-2293 with no `main()`. Module bodies (homebrew, shell, cli, python, java, ruby, rust, emacs, docker, apps, dotfiles, macOS defaults) are inlined `if RUN_X` blocks that fuse install + configure + PATH wiring + summary bookkeeping.
- `teeup-wizard.sh` 1705 lines: TUI that collects answers into `WIZARD_*` vars and execs `teeup.sh --only …` with ~20 exported env vars. Nothing is persisted; re-running means re-answering. Duplicates platform detection, module list, PM choices, defaults from the installer.
- `lib/platform.sh`, `lib/package_manager.sh` (best abstraction: `pkg_install`/`pkg_installed`/candidate lists per backend), `lib/shell.sh`, `lib/dotfiles.sh` (only genuinely pure lib). Libs depend on `log/warn/run_cmd/remember_*` defined in teeup.sh; sourced mid-file.
- No config file at all. Config = env vars with defaults + CLI flags. "Profile" = module preset (base|full) only.
- Idempotency primitives worth keeping: `run_cmd` (dry-run seam), `append_once`, `write_managed_file`, `install_dotfile_link`+`backup_target`, `disable_matching_lines`, `pkg_install`, `run_privileged`, `prepend_path_once`, `detect_target_shell`/`target_rc_file`, wizard validators.
- Multi-platform: macOS (brew/macports) + Linux (apt/dnf/pacman). Casks/apps macOS-only.
- Tests: homegrown framework, `tests/test_teeup_behavior.sh` (~53 real behavioral tests under DRY_RUN with mocked binaries) is the keeper; `test_teeup.sh`/`test_teeup_wizard.sh` are mostly grep-over-source assertions that pin source text. CI: macos-14, macos-15-intel, ubuntu-latest; shellcheck on the two big scripts only.
- Constraints from existing plan: Bash 3.2 compatible (macOS stock bash), shellcheck warning severity, all mutations via `run_cmd`/`run_privileged`.
- Deferred spec: Phase 2 `RUNTIME_MANAGER=native|mise` (docs/superpowers/specs/2026-09-10-dotfile-manager-and-mise-design.md).
- Debt highlights: `~/.config/mac-setup/zsh.zsh` stale name; hardcoded personal stale-path patterns at 2231; ordering bug (dotfiles_payload_available consulted before TARGET_SHELL detected); unknown flag exits 0; `--migrate-to-uv` exits mid-parse; `sdk_cmd` spawns login shells; dry-run preview strings drift from real commands; 8x copy-pasted "handled by dotfiles / else append_once" triad.

### Sibling dotfiles repo (~/Work/environment/dotfiles)

- chezmoi source dir. README: "Never run teeup.sh against this repo again." teeup is treated as superseded predecessor for dotfile delivery.
- Configures: bash (Linux), zsh + Powerlevel10k (macOS), shared `~/.config/shell/{envs,aliases,functions,init}`, starship (Linux only), WezTerm (Lua, ~300 lines, Catppuccin auto light/dark, Emacs-style leader bindings), tmux (8 lines), mise (`conf.d/dotfiles.toml.tmpl`), git (`dot_gitconfig.tmpl`, identity from chezmoi prompts, no signing, Emacs as editor, gh credential helper), systemd user units (Linux).
- chezmoi data prompts: `omarchy`, `work`, `name`, `email`. Work conditional: only `ruby = "3.4"` when not work. Omarchy → ignore everything.
- run_once packages script per OS (darwin: `brew bundle` Brewfile); run_onchange mise install.
- Brewfile minimal: git curl wget htop tree gnupg mise powerlevel10k zsh-autosuggestions zsh-syntax-highlighting emacs; casks wezterm, font-jetbrains-mono-nerd-font. Runtimes and CLI tools (gh, awscli, node, jq, ripgrep, fd) come from mise.
- Editor is Emacs (daemon + emacsclient); no Neovim config anywhere. No hammerspoon/karabiner/aerospace/yabai/skhd. No `defaults write` script. No cross-tool theming.
- Lazy-install precedent: `javav 21` runs `mise install java@corretto-21` on first use.

### Omarchy (v4 at /usr/share/omarchy) — portable ideas

1. Flat `bin/omarchy-*` scripts + metadata-driven dispatcher (`# omarchy:summary=`, `args=`, `group=`, `hidden=`), routes derived from filenames, `commands --json/--markdown/--check`.
2. `config/` (yours, copied to ~/.config) vs `default/` (ours, sourced/required) vs `~/.local/state/omarchy/` (generated). Thin user files require thick package defaults; Lua `package.path` three-tier (state → user → default).
3. Phased install with explicit `all.sh` manifests + `run_logged` wrapper; one file per concern; idempotent guard-first units; empty unit file kept to record a decision.
4. Exit-code-only predicates (`cmd-missing`, `pkg-present`, `hw-*`) enabling declarative menu `when:`/`checked:`.
5. Declarative dotted-ID JSONC menu as discoverability layer; user extensions by ID override.
6. Timestamped migrations with per-user marker files; checksum-against-stock pattern (pristine → refresh; modified → surgical patch + backup); fresh installs mark all migrations done.
7. Lazy install: `launch-or-focus` three-state (running → focus; installed → launch; else install-then-launch), `install-and-launch`, mise shim wrappers (`omarchy-mise-install`) that install on first invocation.
8. Semantic `colors.toml` + `{{ token }}` `.tpl` templates staged atomically; user templates override.
9. Hooks (`~/.config/omarchy/hooks/<event>.d/` with `.sample` docs), failures warn not abort.
10. `refresh-config` = backup, replace with default, print diff.
11. State as file existence (`done/`, `toggles/`); `done ensure` uses noclobber for once-only.
12. Dense "why" comments; ship mental model as an agent skill with read-only boundaries.

Not portable: pacman/AUR, systemd, Hyprland/Wayland/Quickshell, plymouth/limine/btrfs snapper, /etc/skel, hardware quirks tree, freedesktop .desktop, PAM/polkit.

## Interview answers (2026-09-11)

| Topic | Decision |
|---|---|
| Platform | macOS only. Linux dropped from teeup (Omarchy covers Arch; chezmoi repo keeps serving Ubuntu/Fedora). |
| Dotfiles | teeup ships default configs Omarchy-style (`config/` yours, `default/` teeup's). chezmoi repo retired for macOS, kept for Linux. Shared content copied into teeup. |
| Package managers | Homebrew on modern Macs; **MacPorts must keep working on old Intel laptops**; `mas` for App Store (Xcode etc.); mise for CLIs/runtimes. |
| Window manager | AeroSpace (TOML). |
| Terminal | WezTerm (Lua; port existing ~300-line config). WezTerm panes/workspaces for multiplexing; tmux not essential. |
| Herdr | Lazy optional; agent workspace manager; verify macOS support. |
| Shell | Plain zsh, Omarchy-style layered default (`default/zsh/*` sourced by thin `~/.zshrc`); Starship; autosuggestions/syntax-highlighting/completions sourced directly; mise, zoxide, fzf, eza, bat wired in. No Oh My Zsh. |
| Prompt | Starship (TOML). |
| Editors | Emacs (flavor=starter default; doom/spacemacs/none switchable), Neovim (LazyVim), Zed, VS Code. |
| Git | Ask name/email once; git carries that one identity, full stop -- no `includeIf`, no per-root switching. A repository that needs a different address gets `git config user.email ...` by hand. Aliases + modern defaults like Omarchy. *Decision of 2026-09-17; this row first asked for an optional work email and an `includeIf` per root.* |
| Git extras | gh CLI + `gh auth login` + credential helper; lazygit; delta; git-lfs; pre-commit. |
| SSH/signing | ed25519 keys, macOS Keychain via ssh-agent, upload via gh, SSH commit signing (`gpg.format=ssh`). Two keys are two separate identities: personal exists everywhere, work only on a machine whose `machines/<hostname>.conf` configures one. An existing `~/.ssh/config` is authority -- a `Host` block already naming a key wins over generating a new one. SSH config host aliases pick the key. |
| AI CLIs | Claude Code, Codex, Gemini, Copilot, OpenCode: mise-backed lazy shims in `~/.local/bin` (Omarchy `mise-install` pattern). Ollama optional lazy (cask + CLI, no models). Cursor optional lazy cask. Ship a teeup agent skill. |
| Languages | Python, Node/TS, Java/JVM (Kotlin/Scala), Ruby, Rust, Go. mise for everything; uv installed with Python; rustup for Rust. All lazy (`teeup install dev-env <lang>` / first-use). |
| Containers | Colima + docker CLI, lazy on first `docker`. k8s: kubectl, helm, k9s via mise, lazy. |
| Databases | Omarchy `docker-dbs` pattern: lazy picker starting localhost containers on Colima. |
| CLI core | Omarchy modern set: ripgrep fd fzf bat eza zoxide jq yq btop tree wget curl gnupg tldr dust lazygit gh; Omarchy aliases (ls→eza, cd→zoxide). |
| Fonts | JetBrainsMono Nerd Font at bootstrap; `teeup install font <name>` lazy, also switches terminal/editor font. |
| Browsers | Chrome, Firefox, Brave/Arc/Zen: all lazy casks. |
| Comms | Slack, Zoom, Signal/WhatsApp/Telegram, Discord/Teams: all lazy. |
| Productivity | Obsidian, 1Password, Raycast, Bruno/Notion/Typora: all lazy. |
| macOS prefs | Opinionated dev set on by default, one unit each, revertable. |
| Keyboard | Native `hidutil` Caps Lock→Control at bootstrap (LaunchAgent); Karabiner optional lazy with hyper-key config. |
| Secrets | macOS Keychain + `gh auth`; shell helper reads Keychain via `security`. Nothing in repo. |
| Dev dirs | Bootstrap creates `~/Work`. Fixed, not a question; `~/Personal` is no longer created. *Decision of 2026-09-17; this row first created two roots, one per identity.* |
| Work vs personal | Nothing about directories any more: git has one identity regardless of where a repository sits, and a work identity is a per-machine SSH key and GitHub upload, configured in `machines/<hostname>.conf`, never a question the wizard asks. *Decision of 2026-09-17; this row first said only git identity + SSH key differ by root.* |
| Essential set | Core (Xcode CLT, PM, shell, git/gh/ssh, WezTerm, font, CLI set, mise, AeroSpace, macOS defaults, hidutil) **plus daily set** (Emacs, Neovim, Zed, VS Code, Chrome, Obsidian) at bootstrap. Everything else lazy. |
| Profiles | No named profiles. Answers file + per-hostname overrides. |
| Themes | Yes: cross-tool theme system, a few themes, light/dark following macOS appearance. |
| Discoverability | CLI + `teeup menu` TUI (gum/fzf) from the same declarative data as `teeup list`/help. |
| Runtime language | Bash 3.2-compatible, shellcheck-clean. |
| Migration | New tree built in same repo; old `teeup.sh`/wizard frozen under `legacy/` until parity, then removed. |

## Architecture

### 1. What Omarchy taught (concepts)

- **Three config trees with three owners.** `config/` is copied to the user's home once and is theirs; `default/` stays package-owned and is sourced or required at runtime; `~/.local/state/` holds generated artifacts. Thin user files pull in thick defaults, so upgrades improve defaults without touching user edits.
- **One file per concern, explicit ordering.** Install units are single-purpose scripts listed in an `all.sh` manifest, wrapped by a `run_logged` helper. An empty unit is kept when it records a decision.
- **Self-describing commands.** A flat directory of scripts with `# omarchy:` metadata comments drives help, completion, JSON listing and a CI lint.
- **Predicates as exit codes.** `cmd-missing`, `pkg-present` and friends make declarative menu conditions possible.
- **Lazy install as a launcher.** `launch-or-focus` is three-state (running, installed, missing); missing means install then launch inside a themed floating terminal. CLI tools are mise-backed shims that install on first call.
- **Migrations with markers and a stock checksum.** Timestamped scripts, one marker file per applied migration, fresh installs mark everything done, and a migration refreshes a config only if it still matches the shipped checksum, otherwise it patches surgically and backs up.
- **Refresh is backup, replace, diff.** Never a silent overwrite.
- **Semantic palette plus templates.** `colors.toml` names roles, `{{ token }}` templates produce every per-app theme file, staged then swapped atomically, user templates override.
- **Hooks with `.sample` docs.** Event directories where failures warn and never abort.
- **State as file existence.** `done/`, `toggles/`, `migrations/`.
- **Ship the mental model.** A skill directory teaches AI agents the layout and what is read-only.

### 2. Concepts adopted

All of the above, with these macOS translations:

| Omarchy | teeup |
|---|---|
| `/usr/share/omarchy` | the git clone, canonical `~/.local/share/teeup`, path recorded in `~/.config/teeup/env` |
| `/etc/skel` copy | `teeup configure <cap>` copies `capabilities/<cap>/config/` into `~/.config` when absent |
| `pacman -S --needed` | `pkg_install` candidate lists over Homebrew, MacPorts, `mas` (kept from `lib/package_manager.sh`) |
| floating terminal presentation | plain terminal presentation for CLI, `open -a` after cask install for apps |
| mise shim wrappers | identical, in `~/.local/bin` |
| systemd user units | LaunchAgents written by a `lib/launchd.sh` helper |
| Hyprland Lua chain | WezTerm and Neovim Lua chains using the same three-tier `package.path` |
| `omarchy-menu` GUI | `teeup menu` TUI (gum, fzf fallback) from `share/teeup/menu.json` |
| theme `mode` | every theme ships `dark.toml` and `light.toml`; apps follow macOS appearance |

### 3. Concepts not carried over

pacman and AUR, systemd units and timers, Hyprland and the Quickshell bar, plymouth and limine, btrfs snapshots, `/etc/skel` and `useradd`, the hardware quirks tree, freedesktop `.desktop` files, PAM and polkit, web apps as desktop entries, channel switching via mirrorlists. Also dropped from teeup itself: Linux backends (apt, dnf, pacman), Oh My Zsh, SDKMAN, rbenv, pyenv, pipx, the sibling `../dotfiles` auto-adoption, and `~/.config/mac-setup`.

### 4. Directory structure

```text
teeup/
  bootstrap                    # only entry point on a fresh Mac; bash 3.2
  version
  bin/
    teeup                      # CLI dispatcher: teeup <verb> [capability] [args]
  lib/                         # sourced by bin/teeup and every capability script
    core.sh                    # log/ok/warn/err, have, die, run_cmd (dry-run seam), run_logged (stdin from /dev/null unless interactive), TEEUP_* paths
    pkg.sh                     # backends: homebrew, macports, mas; pkg_install/pkg_installed/cask_install
    files.sh                   # append_once, write_managed_file, backup_target, copy_config_once, refresh_config
    state.sh                   # done check|mark|ensure, toggle, migration markers under ~/.local/state/teeup
    answers.sh                 # load/get/set ~/.config/teeup/answers and machine overrides
    capability.sh              # read capability metadata, resolve requires=, tier lists, provides= index
    macos.sh                   # defaults_write (records prior value), launchagent_install, appearance
    ui.sh                      # gum wrappers (confirm/choose/input) with plain read fallbacks
    theme.sh                   # palette parse, template render, stage+swap
  capabilities/
    core.list                  # ordered tier manifests (explicit, no globbing)
    daily.list
    <name>/
      capability               # metadata, KEY=value, sourced (see 4a)
      install                  # idempotent; packages only
      configure                # idempotent; configs, defaults, launchagents, shims
      doctor                   # optional; exit 0 healthy, prints findings
      remove                   # optional
      update                   # optional; default is pkg upgrade of the packages declared in metadata
      config/                  # shipped user files (copied once, user-owned) mirrored on ~/.config or ~
      default/                 # teeup-owned files referenced at runtime via $TEEUP_PATH
      home/                    # shipped files that live directly in $HOME (e.g. home/.zshrc)
      themed/*.tpl             # this tool's theme templates, rendered by lib/theme.sh
  themes/
    <name>/dark.toml, light.toml, backgrounds/, neovim.lua, ...
  share/
    teeup/menu.json            # declarative menu, dotted ids
    agents/skills/teeup/       # SKILL.md for Claude/Codex/Gemini: layout, read-only rules
  migrations/
    <unix-epoch>.sh
  machines/
    <hostname>.conf            # committed per-machine overrides (the only override layer)
  tests/
    helper.sh                  # mock harness ported from tests/test_helper.sh
    lib/*.sh, capabilities/*.sh, cli.sh
  docs/
  legacy/                      # frozen: teeup.sh, teeup-wizard.sh, lib/, templates/, tests/ (deleted at parity)
```

Note on the approved preview: the capability tree is named `capabilities/` rather than `install/` because each directory also holds `configure`, `doctor`, `remove` and the shipped configs.

#### 4a. Capability metadata contract

```sh
# capabilities/neovim/capability
summary="Neovim with LazyVim"
group=editors                  # editors|shell|git|languages|containers|apps|ai|macos|system
tier=daily                     # core | daily | lazy
provides="nvim"                # commands that get lazy shims when tier=lazy (space separated)
requires="package-manager git" # capabilities run before this one
packages="neovim"              # pkg_install candidates; used by default update/remove
casks=""                       # cask candidates (skipped with a note on MacPorts machines)
apps=""                        # .app names for teeup launch
interactive=false              # true: run_logged keeps stdin on the TTY (gh auth login, ssh-keygen, sudo)
```

Every script in a capability directory is run as `bash -eu` with `lib/` preloaded, `TEEUP_PATH`, `TEEUP_CAP`, `TEEUP_CAP_DIR` exported, and the answers file loaded. Install and configure are separate processes so a config change never requires understanding an install. `config/` maps onto `~/.config/`, `home/` maps onto `$HOME` with literal dotfile names.

Rules for `provides=`: never list a command macOS already ships (`python3`, `ruby`, `java`, `git`, `perl`); a shim appended last on PATH can never fire for those. Languages are reached only through `teeup install dev-env <lang>` and mise activation.

#### 4b. Home layout after bootstrap

```text
~/.config/teeup/
  env                  # export TEEUP_PATH=...; sourced by shell layer and LaunchAgents
  answers              # KEY="value", written by bootstrap wizard, editable with teeup config set
  hooks/<event>.d/     # post-update, theme-set, post-bootstrap; ships *.sample files
  themes/<name>/       # user themes overlaying themes/<name>
  themed/*.tpl         # user templates overriding capability themed/ templates
~/.config/<tool>/      # copied from capabilities/<cap>/config, user-owned
~/.zshrc, ~/.zprofile, ~/.zshenv   # thin, source $TEEUP_PATH/capabilities/zsh/default/*
~/.local/state/teeup/
  done/ toggles/ migrations/       # file-existence state
  current/theme/{dark,light}/      # generated per-app theme files, atomically swapped
  current/theme.name
  current/font                     # family name set by teeup install font; read by wezterm/zed/vscode/neovim
  defaults/<domain>.<key>          # prior value ("absent" or "<type>:<value>") recorded by defaults_write
  shims/                           # lazy-install shims, appended last on PATH
  logs/bootstrap.log, update.log
~/.local/bin/          # mise-backed wrappers for AI CLIs and other mise tools
~/Work                 # created by dev-dirs capability (2026-09-17: ~/Personal dropped, one identity)
```

### 5. Bootstrap process

`bootstrap` is bash 3.2, has no dependencies beyond a fresh macOS, and is safe to rerun.

```text
./bootstrap [--dry-run] [--reconfigure] [--skip-daily]
  0  preflight: macOS only, not root, arch and version detected, sudo -v + keepalive
  1  Xcode Command Line Tools: unattended first (touch the .installondemand.in-progress
     marker, softwareupdate --list, install the CLT label), GUI xcode-select --install as
     fallback; Rosetta 2 on Apple Silicon (reuse legacy code for both)
  2  package manager: Homebrew by default; MacPorts when macOS major is 12 or older
     or when machines/<hostname>.conf sets TEEUP_PACKAGE_MANAGER=macports; confirmed in wizard
  3  minimal self-install, only what the CLI needs to exist: write ~/.config/teeup/env,
     link ~/.local/bin/teeup, install gum (state dirs and shims belong to teeup-runtime)
  4  wizard (skipped when answers exist unless --reconfigure): name, personal email,
     work email (optional), package manager confirm, theme, include daily set (default yes)
     -> writes ~/.config/teeup/answers
  5  for cap in capabilities/core.list:  run_logged install; run_logged configure
  6  for cap in capabilities/daily.list: same (unless --skip-daily or answers say no)
  7  theme set <answers.theme>; mark all migrations applied; done mark bootstrap
  8  hook post-bootstrap; summary; "open a new terminal or run exec zsh"
```

`run_logged` redirects stdin from `/dev/null` like Omarchy unless the capability sets `interactive=true`; `github` (gh auth login with scopes `admin:public_key,admin:ssh_signing_key`), `ssh` (key passphrase) and `package-manager` (sudo) are interactive.

Core list (ordered): `xcode-clt package-manager teeup-runtime dev-dirs zsh starship cli-tools secrets git ssh github mise wezterm fonts aerospace keyboard macos-defaults theme`.
Daily list: `emacs neovim zed vscode chrome obsidian`.
Everything else is `tier=lazy`, including `xcode` (`mas install 497799835` after checking `mas account`; the user signs into the App Store by hand since `mas signin` no longer works).

Capabilities that need a permission no script can grant (AeroSpace needs Accessibility, Karabiner needs driver approval) print the System Settings step from `configure` and check it from `doctor`.

Each step is idempotent, so rerunning `./bootstrap` is the "repair" path and is what `teeup update` calls after migrations.

### 6. Lazy installation mechanism

Three entry points, one implementation.

1. **Shims.** `teeup-runtime configure` reads `provides=` from every `tier=lazy` capability and writes a shim per command into `~/.local/state/teeup/shims/`, which the shell layer appends last on `PATH`. A shim is:
   ```sh
   #!/bin/bash
   exec "$TEEUP_PATH/bin/teeup" lazy-run <capability> <command> "$@"
   ```
   `teeup lazy-run` checks whether a real binary exists elsewhere on PATH; if so it execs it (the shim is unreachable anyway because it is last). Otherwise, on a TTY it asks "docker is provided by capability docker. Install now?", runs install then configure, then execs the real command with the original arguments. Without a TTY it prints the `teeup install` hint and exits 127, so scripts fail loudly rather than block.
2. **Explicit.** `teeup install <cap>` and the `teeup menu` Install section run the same install+configure pair.
3. **Launchers.** `teeup launch <app>` for GUI casks: `open -a` if installed (it focuses a running app already), else install the cask and open. Menu rows use `when` predicates (`teeup has <cap>`) to hide installed items.

AI CLIs (Claude Code, Codex, Gemini, Copilot CLI, OpenCode) use mise wrappers instead of shims, exactly like Omarchy's `mise-install`: `~/.local/bin/claude` runs `mise use -g claude` on first call and `exec mise x claude -- claude "$@"` after, so `teeup update` upgrades them with `mise upgrade`. The `ai` capability writes the wrappers at configure time; nothing is downloaded until first call.

Language runtimes are `teeup install dev-env <python|node|java|ruby|rust|go>`; Python also installs uv, Rust uses rustup, the rest are `mise use --global`. Runtimes get no shims (see the `provides=` rule). Shims exist only for commands macOS lacks: `docker`, `colima`, `kubectl`, `helm`, `k9s`, `tmux`, `herdr`, `ollama`, `lazydocker`.

Bootstrap versus lazy: bootstrap installs what every terminal session needs (core) plus the daily set, which defaults to yes. Lazy covers languages, containers, Kubernetes, `docker-dbs`, AI CLIs, Ollama, Cursor, Herdr, tmux, Karabiner, Xcode, browsers beyond Chrome, communication and productivity apps (1Password, Raycast, Bruno, Notion, Typora).

Herdr is gated on a phase 3 check that it ships macOS builds; if it does not, the capability is dropped.

### 7. Configuration model

- **Answers** (`~/.config/teeup/answers`) are the profile: identity, package manager, theme, daily set, opt-outs. Sourceable `KEY="value"` so bash 3.2 reads it with no parser. `teeup config get|set|edit` manages it. Precedence: capability defaults, then `answers`, then the committed `machines/<hostname>.conf` (machine wins because it encodes hard constraints such as the package manager or `TEEUP_SKIP`).
- **Secrets.** The `secrets` core capability ships `teeup secret get|set|rm <name>` over `security find-generic-password` / `add-generic-password` (service `teeup`), and a zsh function `teeup-env <name>` that exports a secret as an environment variable for one shell. GitHub tokens stay in `gh auth`. Nothing secret enters the repo or the answers file.
- **Shipped user configs** live in `capabilities/<cap>/config/` and are copied once by `configure` (Omarchy `/etc/skel`). Formats are native to each tool: Lua for WezTerm and Neovim, TOML for Starship, AeroSpace, mise, Herdr, JSON for Zed, VS Code, Karabiner, gitconfig INI, zsh.
- **Defaults** live in `capabilities/<cap>/default/` and are referenced at runtime. Lua tools use a three-tier `package.path` (state, user config, teeup default) so `require("teeup.wezterm")` resolves to teeup's file and user overrides load after it. zsh uses `source "$TEEUP_PATH/capabilities/zsh/default/rc"` from a twelve-line `~/.zshrc` with the user's additions below. Tools without include support (Starship, AeroSpace) get the whole file copied and a managed block for theme colors.
- **Reset.** `teeup reset <cap>` backs up the user copy, replaces it with the shipped file, prints the diff, and deletes the backup if nothing changed.
- **macOS defaults** are applied by `configure` through `defaults_write <domain> <key> <type> <value>`, which first records the prior state under `state/defaults/<domain>.<key>` as `absent` (when `defaults read` exits 1) or `<type>:<value>`; `remove` replays that record with `defaults delete` or a typed `defaults write`.
- **Fonts.** `teeup install font <name>` installs the Nerd Font cask and writes the family name to `state/current/font`; WezTerm and Neovim read it through the default Lua layer, Zed and VS Code get `font_family` written by jq. Same flow as themes.
- **Git extras.** The `git` capability declares `packages="git git-delta git-lfs lazygit"`, installs `pre-commit` via mise in `configure`, and the shipped gitconfig sets delta as `core.pager` and runs `git lfs install`.
- **Themes.** `themes/<name>/{dark,light}.toml` hold the semantic palette. `teeup theme set <name>` renders every `capabilities/*/themed/*.tpl` (user overrides from `~/.config/teeup/themed/` first) for both modes into a staging dir, swaps it into `current/theme/`, then notifies apps (WezTerm reloads, Zed and VS Code get `theme` written by jq, tmux sources, bat via `BAT_THEME`). Apps that follow macOS appearance read both variants; shell-level tools pick the variant from `TEEUP_APPEARANCE`, exported at shell start from `defaults read -g AppleInterfaceStyle` (exit 1 means light).
- **Hooks.** `~/.config/teeup/hooks/<event>.d/` with `.sample` files; events `post-bootstrap`, `post-update`, `theme-set`.

### 8. Profiles

No named profiles. "Sensible defaults + my profile + machine overrides" maps to capability defaults + `answers` + `machines/<hostname>.conf`. *Amended 2026-09-17 (user decision; this section first made identity a directory rule -- see the Git, SSH/signing, Dev dirs and Work vs personal rows of the interview table): git carries one identity, full stop, so there is no `includeIf` and no per-root switching left to make a profile out of. The only thing "work" still means is a second SSH key and a second GitHub upload, and that is per-machine, not a question: `ssh` generates the work key (`id_ed25519_work`) and writes `Host github.com-work` style aliases only when `machines/<hostname>.conf` sets `TEEUP_WORK_EMAIL`; without it there is one key, one identity, no work anything.* Machines that must skip a capability (no AeroSpace on a locked-down Mac) set `TEEUP_SKIP="aerospace"` in `machines/<hostname>.conf`.

### 9. Updates

```text
teeup update            # everything
  git -C $TEEUP_PATH pull --ff-only        (refuses on a dirty tree, tells the user)
  run pending migrations/<epoch>.sh        (marker per applied file under state/migrations)
  package manager: brew update && brew upgrade && brew upgrade --cask, or port selfupdate && port upgrade outdated
  mise upgrade                             (AI CLIs, runtimes, CLI tools from mise)
  re-run configure for core.list           (idempotent; picks up new shims and templates)
  theme set $(theme current)               (regenerate templates)
  hook post-update
teeup update <cap>      # only that capability's packages and configure
```

Migrations follow Omarchy's stock-checksum rule: refresh a user file only if its SHA matches the shipped version at the time it was copied (recorded in state at copy time), otherwise patch minimally and back up. `teeup dev add-migration` names the file from the last commit timestamp.

### 10. Migrating existing machines

`bootstrap` on a Mac that already has a teeup or chezmoi setup:

- Every user-facing file teeup writes goes through `copy_config_once`, which never overwrites; when a foreign file exists it is backed up as `<file>.teeup_backup_<ts>` (existing `backup_target` behavior), the thin teeup file is installed, and a diff of the backup is printed so personal lines can be moved into the user section.
- `teeup migrate legacy` handles known predecessors: removes `~/.teeup.common`, `~/.config/mac-setup`, dangling legacy symlinks; disables SDKMAN, rbenv, pyenv init lines (reusing `disable_matching_lines`); detects a chezmoi-managed home, prints the list from `chezmoi managed`, backs those files up with `backup_target`, and asks before deleting only `~/.config/chezmoi` (the config that points chezmoi at its source). It never runs `chezmoi purge`, which would delete the source directory, and never touches `~/Work/environment/dotfiles`, which keeps serving Linux.
- `teeup doctor` flags leftovers: a `[user]` block in `~/.gitconfig.local`, p10k remnants, Oh My Zsh directory, a chezmoi source dir still pointing at the Linux repo.
- Content from the chezmoi repo worth porting into capability configs: `~/.config/shell/{envs,aliases,functions}`, `wezterm.lua` (minus the work Jira hyperlink rule, which moves to `~/.wezterm_local.lua`), gitconfig aliases, the `javav` function.
- **An existing `~/.ssh/config` is authority (2026-09-17 decision; this section otherwise assumed `copy_config_once`'s general backup-and-replace rule would apply here too).** A machine already has a real `Host` block naming a real `IdentityFile` far more often than it has a stray `~/.config/git/config`, so ssh does not treat it like every other shipped file: when it exists, teeup neither backs it up nor replaces it, and the key it already names is used for the matching identity instead of a fresh `id_ed25519_<identity>`. The two-root git identity this section's own migration notes used to have to reconcile is gone from what teeup writes, but not from machines that already ran the old model: `copy_config_once` still finds their `~/.config/git/config` matching the sha recorded at install time, so the `includeIf` blocks and the `identity-personal`/`identity-work` files it installed survive every upgrade. `git configure` therefore repairs that shape in place -- it drops the blocks teeup itself shipped, backs up the stale identity files, and refreshes the stock record -- and warns, naming the lines, when a config carries old-model lines teeup did not ship.

### 11. Fresh Mac

```text
Fresh Mac
   │
   ▼
git clone <repo> ~/.local/share/teeup && cd ~/.local/share/teeup && ./bootstrap
   │
   ├── preflight, Xcode CLT, Rosetta
   ├── Homebrew (or MacPorts on old Intel)
   ├── teeup runtime: env file, ~/.local/bin/teeup, state dirs, gum
   ├── wizard → ~/.config/teeup/answers
   │
   ▼
core tier (ordered, install then configure each)
   ├── dev-dirs        ~/Work (2026-09-17: one root, one identity)
   ├── zsh + starship  thin ~/.zshrc → teeup default layer
   ├── cli-tools       rg fd fzf bat eza zoxide jq yq btop tldr dust
   ├── git / ssh / github   one git identity, ed25519 per identity (work only when machines/*.conf configures one), gh auth login per host, SSH signing
   ├── mise            runtime + tool manager
   ├── wezterm, fonts  JetBrainsMono Nerd Font
   ├── aerospace, keyboard (hidutil), macos-defaults
   └── theme           default theme rendered for dark and light
   │
   ▼
daily tier (if chosen): emacs neovim zed vscode chrome obsidian
   │
   ▼
lazy capabilities: shims in place, nothing downloaded
   │
   ├── `docker ps`        → shim → install colima+docker → continue
   ├── `claude`           → mise wrapper → mise use -g claude → continue
   ├── `teeup install dev-env rust`
   ├── `teeup launch slack`
   └── `teeup menu` → Install → Communication → Slack
```

### 12. Adding a tool later

1. `teeup dev new-capability <name>` scaffolds `capabilities/<name>/{capability,install,configure}` with templates and a test file.
2. Fill in metadata: `summary`, `group`, `tier`, `provides`, `requires`, `packages` or `casks`.
3. `install` calls `pkg_install`/`cask_install`; `configure` copies `config/`, writes defaults, registers a LaunchAgent if needed.
4. If `tier` is core or daily, append to the tier list at the right position.
5. Add a row to `share/teeup/menu.json` (only needed for GUI-launchable or grouped items; `teeup list` is generated from metadata).
6. Add `themed/<tool>.tpl` inside the capability if the tool has colors.
7. Run `teeup dev check` (metadata lint, executable bits, shellcheck, dry-run install and configure under the mock harness).

### CLI surface

```text
teeup install <cap>|dev-env <lang>|font <name>     teeup configure <cap>
teeup update [<cap>]                                teeup remove <cap>
teeup reset <cap>                                   teeup doctor [<cap>]
teeup status                                        teeup list [--tier|--group|--json]
teeup menu                                          teeup launch <app>
teeup theme set|list|current                        teeup config get|set|edit
teeup has <cap>   (exit code only)                  teeup migrate legacy
teeup secret get|set|rm <name>                      teeup dev new-capability|add-migration|check
teeup commands [--check]
```

`bin/teeup` resolves `<verb> <cap>` to `capabilities/<cap>/<verb>`, falling back to generic implementations for `update` and `remove` from metadata. Help and completion derive from metadata files.

### Reused from the current repo

- `lib/package_manager.sh` candidate-list model and backends (Homebrew, MacPorts), `run_privileged`, `prepend_path_once`.
- `run_cmd`, `append_once`, `write_managed_file`, `backup_target`, `install_dotfile_link`, `disable_matching_lines`, `format_duration`, `have`.
- `lib/shell.sh` target shell and rc-file detection.
- `tests/test_helper.sh` mock harness and the behavioral tests as the template for capability tests.
- Wizard validators (`validate_positive_integer`, `validate_version_format`, `validate_choice`).
- Xcode CLT, Rosetta, Colima, and `defaults write` code paths as the starting point for those capabilities.

### Debt removed by construction

No `main()`-less script, no wizard duplication (the wizard is `lib/ui.sh` plus `lib/answers.sh`), no env-var-only configuration, no dry-run preview strings maintained separately (every mutation is a `run_cmd`), no hardcoded personal stale paths, no `~/.config/mac-setup`, no login-shell spawning for SDKMAN, no grep-over-source tests.

### Migration path for the repo

| Phase | Deliverable | Gate |
|---|---|---|
| 0 | `git mv` current scripts, lib, templates, tests to `legacy/`; CI runs legacy tests from there; README banner | legacy tests green |
| 1 | `bootstrap`, `bin/teeup`, `lib/*` ported from legacy, capability contract, `tests/helper.sh`, CI on macos-14 and macos-15 plus shellcheck | `teeup commands --check`, lib tests |
| 2 | core tier capabilities + `theme` with one theme | `./bootstrap --dry-run` passes under mocks; real run on a Mac |
| 3 | daily tier, lazy shims, mise wrappers, `dev-env`, `launch`; verify Herdr macOS availability | shim round-trip test |
| 4 | menu, doctor, update + migrations, reset, hooks, remaining lazy capabilities, remaining themes | `teeup doctor` clean on a bootstrapped Mac |
| 5 | `teeup migrate legacy`, agent skill, docs; delete `legacy/` | parity checklist against legacy `--list-modules` |

### Verification

- Unit: `tests/lib/*.sh` under the mock harness for pkg, files, state, answers, capability resolution, theme rendering.
- Capability: each capability gets a dry-run test asserting the commands it would run and the files it would write under a temp `$HOME`.
- CLI: `teeup commands --check` lints metadata; shellcheck at warning severity on `bootstrap`, `bin/teeup`, `lib/*.sh`, every capability script.
- End to end: `./bootstrap --dry-run` on CI macOS runners; a real bootstrap on a clean macOS VM or a fresh user account before each release; `teeup doctor` must exit 0 afterward.
- Idempotency: run `./bootstrap` twice under the harness and assert the second run performs no mutations.
