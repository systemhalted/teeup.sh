# Legacy parity checklist

The previous installer was one 2,292-line `teeup.sh` plus a 1,704-line
`teeup-wizard.sh`, a `lib/` and a `templates/` tree and four test scripts —
6,968 lines in all — driven by thirteen module toggles. This document records
what each of those modules did and where it went, and it is the gate the
redesign's phase 5 had to pass before `legacy/` could be deleted. It is
written in the past tense on purpose: the programs it describes are no longer
in the repository, and this is the only record of them that remains.

The module list is the verbatim output of `./legacy/teeup.sh --list-modules`,
taken from the tree at commit `808d049`, the commit before the deletion.

Two of the thirteen modules' replacements are still partly in progress: the
`docker` and `apps` rows below name only the capabilities that exist on this
tree today. The remaining ones they used to cover (`docker-dbs`, `lazydocker`,
`bruno`) are phase 4c work, moved to the 0.2.0 milestone, and are called out
in prose rather than backticked as if they already shipped.

## Modules

<!-- parity-map -->

| Legacy module | Replaced by | What changed |
|---|---|---|
| `homebrew` | `package-manager` | Same job, same two backends. Homebrew by default, MacPorts on macOS 12 and older or when `machines/<hostname>.conf` sets `TEEUP_PACKAGE_MANAGER=macports`. The Linux backends (`apt`, `dnf`, `pacman`) are gone: teeup is macOS only now, and the chezmoi repository keeps serving Linux. |
| `shell` | `zsh` `starship` | The login shell is zsh, always. The old module could configure bash instead (`TARGET_SHELL`, `--only bash`) and installed Powerlevel10k or Starship only when `--prompt` asked; the new pair always installs Starship and a layered zsh configuration whose thin `~/.zshrc`, `~/.zprofile` and `~/.zshenv` source teeup's `default/` layer. `~/.teeup.common`, the shared init file both shells sourced, is gone; `teeup migrate legacy` removes it. |
| `zsh` | `zsh` `starship` | The forced-zsh alias of `shell`. There is nothing left to force. |
| `ohmyzsh` | dropped | Oh My Zsh is not installed by teeup any more (design interview: "Plain zsh, Omarchy-style layered default … No Oh My Zsh"). Its git aliases live in `capabilities/git/config/git/config` instead, its completions come from zsh's own `compinit` plus the tools' shipped completions, and `zsh-autosuggestions` and `zsh-syntax-highlighting` are sourced directly by the zsh layer. `teeup doctor` reports an `~/.oh-my-zsh` directory left over from before. |
| `bash` | dropped | macOS ships bash 3.2 and has defaulted to zsh since Catalina. teeup's runtime is still written in bash 3.2 so that `bootstrap` runs on a bare Mac, but it no longer offers to configure bash as your login shell. |
| `cli` | `cli-tools` `git` `github` `tmux` | The old list was `git wget curl jq htop tree tmux ripgrep fd gnupg`. `cli-tools` now installs `ripgrep fd fzf bat eza zoxide jq yq btop tree wget curl gnupg tldr dust`: `htop` became `btop`, and `fzf`, `bat`, `eza`, `zoxide`, `yq`, `tldr` and `dust` are new. `git` moved to its own capability, whose `packages=` is `git git-delta git-lfs lazygit`; `gh` moved to `github`; `pre-commit` comes from `mise`. `tmux` is a lazy capability, because WezTerm's panes cover the multiplexing this setup actually used. |
| `python` | `mise` | pyenv, pyenv-virtualenv, pipx and poetry are gone, and so is the `USE_UV=false` branch that installed them. Python comes from `teeup install dev-env python`, which pins a version through mise and installs `uv` with it. `PYTHON_VERSION` has no successor: mise's global config holds the version, and `mise use --global python@3.13` changes it. |
| `java` | `mise` | SDKMAN is gone, including the login-shell spawning the old module needed to source it. Java comes from `teeup install dev-env java`, and the `javav` shell function switches the version for one shell. Maven and Gradle are mise tools rather than SDKMAN candidates. `JDK_VERSION` has no successor, for the same reason as `PYTHON_VERSION`. |
| `ruby` | `mise` | rbenv is gone. Ruby comes from `teeup install dev-env ruby`, which pins `ruby@latest` in mise's global config and leaves gem management to Ruby: RubyGems and Bundler ship with the interpreter mise installs, and teeup runs neither `gem update --system` nor `gem install bundler` on your behalf. `RUBY_VERSION` and `BUNDLER_VERSION` have no successor. |
| `rust` | `mise` | `teeup install dev-env rust` goes through mise's rust backend, which uses rustup underneath, so the toolchain management is the same and the bootstrap no longer pipes `https://sh.rustup.rs` into a shell. |
| `emacs` | `emacs` | Now a daily-tier capability with a `sh.teeup.emacs` LaunchAgent running the daemon, four configurations behind `TEEUP_EMACS_FLAVOR` (`starter`, `doom`, `spacemacs`, `none`), a themed template and a `theme-apply` hook that reloads a running daemon. The old module installed the `emacs-app` cask and copied a fixed `init.el`. |
| `docker` | `colima` | Colima and the Docker CLI are a lazy capability reached by a `docker` shim: the first `docker ps` on a new Mac offers to install it. The Linux half of the old module (distro packages, docker group membership) is gone with the rest of the Linux support. `docker-dbs` (local database containers) and `lazydocker` (the TUI) were part of the same redesign phase as this checklist but did not land in 0.1.0; they are phase 4c work, moved to 0.2.0, and are not capabilities on this tree yet. |
| `apps` | `obsidian` | Obsidian is a daily-tier capability of its own, alongside the other GUI capabilities teeup ships today (Zed, Firefox Developer Edition, Chrome, VS Code, Cursor, AeroSpace). The wider set of browsers, communication and productivity apps, Karabiner and Xcode is phase 4c work moved to 0.2.0. `teeup list --tier lazy` is the current lazy list. `Bruno`, the other cask this module installed, is phase 4c work moved to 0.2.0 and has no capability yet. `INSTALL_BRUNO` and `INSTALL_OBSIDIAN` have no successor either way: install what you want, when you want it. |

<!-- /parity-map -->

## Command-line options

| Legacy option | Where it went |
|---|---|
| `--help` | `teeup help` (also `-h` and `--help`), which lists every verb. |
| `--dry-run` | `DRY_RUN=true` in front of any command, and `./bootstrap --dry-run`. Every mutation goes through one seam (`run_cmd` or a guarded file primitive), so the preview is the real code path rather than a second set of strings. |
| `--profile base\|full`, `--all` | The three tiers. Core is the base, `--skip-daily` is the way to get core alone, and everything past that is lazy rather than a profile. |
| `--prompt none\|powerlevel10k\|starship` | Dropped. Starship is the prompt; Powerlevel10k is not installed, and `teeup doctor` reports remnants of one. |
| `--only MODULES` | `teeup install <capability>`, one at a time, and `teeup list` to see what there is. |
| `--except MODULES` | `TEEUP_SKIP="<capability> …"` in `machines/<hostname>.conf`, which also removes that capability's lazy shims. |
| `--init-dotfiles [DIR]`, `--dotfiles PATH\|URL`, `--dotfiles-manager M` | Dropped, and replaced by the shipped-config model: `capabilities/<cap>/config/` is copied into `~/.config` once and is yours afterwards, `home/` the same for dotfiles in `$HOME`, and `default/` stays teeup's. There is no overlay repository to point at, no chezmoi or Stow hand-off, and no auto-adoption of a sibling `../dotfiles`. A machine that still has a chezmoi-managed home is handled by `teeup migrate legacy`. |
| `--migrate-to-uv` | Dropped. There is no pyenv installation to migrate from, because teeup never creates one; `teeup migrate legacy` neutralises a pyenv init line left in a shell file by the old installer. |
| `--strict-platform` | Dropped. There is one platform. |
| `--reconcile-existing-config`, `--no-reconcile-existing-config` | `teeup migrate legacy`, which does the same work (disabling Antigen, SDKMAN, rbenv and pyenv init lines) as an explicit verb rather than a flag that could fire as a side effect of an install. |
| `--list-modules` | `teeup list`, which reads the capability metadata instead of a hand-maintained function, and takes `--tier core\|daily\|lazy`. |

## Environment variables

| Legacy variable | Where it went |
|---|---|
| `TEEUP_PROFILE` | The tiers, and `TEEUP_DAILY` in the answers file for whether the daily tier runs at bootstrap. |
| `PYTHON_VERSION`, `JDK_VERSION`, `RUBY_VERSION`, `BUNDLER_VERSION` | Dropped; mise's global config holds every runtime version. |
| `USE_UV` | Dropped; `uv` always comes with `teeup install dev-env python`. |
| `RUBYGEMS_UPDATE` | Dropped. The Ruby mise installs brings its own RubyGems, and `gem update --system` is the user's call. |
| `ZSH_MODE` | Dropped with Oh My Zsh. |
| `PROMPT` | Dropped; the prompt is Starship. |
| `TARGET_SHELL` | Dropped; the login shell is zsh. |
| `PACKAGE_MANAGER` | `TEEUP_PACKAGE_MANAGER`, asked once by the bootstrap wizard and pinnable in `machines/<hostname>.conf`. |
| `STRICT_PLATFORM` | Dropped with `--strict-platform`. |
| `INSTALL_DOTFILES`, `DOTFILES_DIR`, `DOTFILES_MANAGER` | Dropped with the dotfiles overlay. |
| `ALLOW_HOMEBREW_CASK_FALLBACK`, `CLEANUP_HOMEBREW_OVERLAPS` | Dropped. A MacPorts machine skips casks with a note and says what to install by hand; teeup does not uninstall another package manager's packages. |
| `UPGRADE_HOMEBREW` | `teeup update`, which upgrades formulae and casks as one of its steps. |
| `RECONCILE_EXISTING_CONFIG` | `teeup migrate legacy`. |
| `TUNE_DEFAULTS` | The `macos-defaults` capability, which is in the core tier and on by default, records the previous value of every key it writes, and puts them all back on `teeup remove macos-defaults`. |
| `DRY_RUN` | Unchanged, and now covering every mutation rather than the ones somebody remembered to wrap. |

## The wizard

`teeup-wizard.sh` was 1,400 lines of screens that set the environment variables
above and then ran `teeup.sh`. It is replaced by two things: the questions
`bootstrap` asks once, whose answers live in `~/.config/teeup/answers` and are
editable with `teeup config`, and `teeup menu`, which is generated from
`share/teeup/menu.json` and covers installing, launching, theming and checking.
`lib/ui.sh` holds the prompts both of them use, with gum where it is installed
and a plain read where it is not, so there is no second implementation of a
question anywhere in the tree.

## What has no successor, deliberately

- **Linux.** apt, dnf and pacman backends, the docker group, distro package
  name tables. Omarchy covers Arch and the chezmoi repository covers
  Ubuntu and Fedora; teeup is macOS only.
- **Oh My Zsh, SDKMAN, rbenv, pyenv, pipx and poetry.** Each was a second
  version manager layered under the shell. mise replaces all of them, and
  `teeup migrate legacy` disables the init lines they left behind.
- **Powerlevel10k.** Starship is the prompt, and `teeup doctor` reports a
  leftover `~/.p10k.zsh`.
- **The dotfiles overlay** (`--dotfiles`, `--init-dotfiles`, chezmoi and Stow
  hand-off, `../dotfiles` auto-adoption). Capabilities ship their own config
  now.
- **`~/.teeup.common`, `~/.teeupshrc` and `~/.config/mac-setup`.** All three
  were teeup's own invented locations. `teeup migrate legacy` removes them.
- **Module toggles as environment variables.** The old runtime was configured
  entirely by exported variables; the new one has an answers file, a machine
  file, and verbs.

## What is still in progress, not dropped

- **`docker-dbs` and `lazydocker`.** The redesign's phase 4c adds local
  database containers and a Docker TUI on top of `colima`. That phase was
  moved to the 0.2.0 milestone, so these two are not capabilities on this
  tree; `docker`'s row above names only what exists today.
- **`bruno`.** Also phase 4c, also moved to 0.2.0. `apps`'s row above names
  only `obsidian`, the GUI app phase 4c's peers do not affect.
- **Themes beyond `catppuccin`.** teeup's theme system (the `theme`
  capability) ships one palette today. `everforest`, `gruvbox` and
  `tokyo-night` are part of PR #54, not yet merged; when it lands, this
  document does not need an update, because the legacy installer never had a
  theme module to map from.
