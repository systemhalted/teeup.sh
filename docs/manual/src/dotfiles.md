# Dotfiles

teeup splits tool configuration into user files and system files. Updates modify the system files.

| Kind | Where | Owner |
|---|---|---|
| Copied once | `~/.config/<tool>/...`, and `~/.zshrc`, `~/.zshenv`, `~/.zprofile` | You, from the moment they land |
| Local override | A `local.*` file next to them | You, always |
| Generated | A few files teeup rewrites, marked "Your edits here are overwritten" | teeup |
| Layer | `capabilities/<name>/default/` in the checkout | teeup, upgraded by `teeup update` |

Most copied files load the teeup layer from the checkout, then your local file. Your settings override teeup's.

## The files teeup copies

| Capability | Files |
|---|---|
| `zsh` | `~/.zshenv`, `~/.zprofile`, `~/.zshrc`, `~/.config/zsh/local.zsh` |
| `git` | `~/.config/git/config` |
| `ssh` | `~/.ssh/config`, only when you have none |
| `starship` | `~/.config/starship.toml` |
| `wezterm` | `~/.config/wezterm/wezterm.lua`, `~/.config/wezterm/local.lua` |
| `emacs` | `~/.config/emacs/init.el`, `~/.config/emacs/local.el`, for the starter flavor |
| `neovim` | `~/.config/nvim/init.lua`, `stylua.toml`, and the files under `lua/` |
| `cli-tools` | `~/.config/bat/config` |
| `mise` | `~/.config/mise/config.toml` |
| `tmux` | `~/.config/tmux/tmux.conf`, unless you have a `~/.tmux.conf` |
| `aerospace` | `~/.config/aerospace/aerospace.toml`, unless you have a `~/.aerospace.toml` |

## The copy-once rule

When teeup installs one of these files it records a checksum of what it wrote, under `~/.local/state/teeup/stock/`. Every later `configure` compares the file against that record:

| The file is | teeup does | and says |
|---|---|---|
| Missing | Copies it and records the checksum | "Installed ..." |
| Unchanged since teeup wrote it | Nothing | "Already installed: ..." |
| Edited by you | Nothing | "Keeping your edited ... (run teeup reset to restore the shipped file)" |
| Someone else's, such as a file from another dotfiles tool | Moves it aside, installs its own, and prints the lines that differ | "Installed ... (your previous file is at ...)" |

A file teeup moves aside keeps its name with `.teeup_backup_<timestamp>` added, in the same directory. teeup never deletes it. A symlink counts as someone else's file: teeup does not write through it.

When a teeup update includes a new default, a migration replaces unchanged files. Your edited files remain.

## Local files

Write your settings in the `local.*` files. teeup ships them commented out and does not overwrite them during `teeup reset`.

| File | Loaded by |
|---|---|
| `~/.config/zsh/local.zsh` | `~/.zshrc`, last |
| `~/.config/wezterm/local.lua` | `~/.config/wezterm/wezterm.lua` |
| `~/.config/emacs/local.el` | `~/.config/emacs/init.el`, last |
| `~/.config/git/local` | `~/.config/git/config`, last. teeup does not create it; make it yourself. |

## teeup reset

```sh
teeup reset starship
DRY_RUN=true teeup reset zsh
```

`teeup reset <capability>` puts that capability's copied files back to the version teeup ships. For each file it:

1. makes a backup next to it, `<name>.teeup_backup_<timestamp>`;
2. writes the shipped version, rendered for this Mac where the capability renders it (the zsh home files, the git config);
3. prints what changed;
4. deletes the backup again if the file was already the shipped version.

Then it applies the current theme and font again, so a reset `starship.toml` has your palette. It keeps the `local.*` files. It refuses a file that is a symlink or not writable, and it never overwrites a file whose backup failed.

Only a capability with copied files can be reset. For others, teeup says the capability "ships no config files to reset".
