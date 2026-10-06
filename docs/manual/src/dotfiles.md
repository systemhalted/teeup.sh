# Dotfiles

teeup splits the tool configuration into user files and system files, and updates modify only the system files.

| Kind | Where | Owner |
|---|---|---|
| Copied once | `~/.config/<tool>/...`, and `~/.zshrc`, `~/.zshenv`, `~/.zprofile` | You, after teeup copies them |
| Local override | A `local.*` file next to the copied files | You, always |
| Generated | A small number of files that teeup rewrites, marked "Your edits here are overwritten" | teeup |
| Layer | `capabilities/<name>/default/` in the checkout | teeup, and `teeup update` upgrades them |

Most copied files load the teeup layer from the checkout and then your local file, so your settings override the teeup settings.

## The files teeup copies

| Capability | Files |
|---|---|
| `zsh` | `~/.zshenv`, `~/.zprofile`, `~/.zshrc`, `~/.config/zsh/local.zsh` |
| `git` | `~/.config/git/config` |
| `ssh` | `~/.ssh/config`, only if you do not have one |
| `starship` | `~/.config/starship.toml` |
| `wezterm` | `~/.config/wezterm/wezterm.lua`, `~/.config/wezterm/local.lua` |
| `emacs` | `~/.config/emacs/init.el`, `~/.config/emacs/local.el`, for the starter flavor |
| `neovim` | `~/.config/nvim/init.lua`, `stylua.toml`, and the files in the `lua/` directory |
| `cli-tools` | `~/.config/bat/config` |
| `mise` | `~/.config/mise/config.toml` |
| `tmux` | `~/.config/tmux/tmux.conf`, if you do not have a `~/.tmux.conf` |
| `aerospace` | `~/.config/aerospace/aerospace.toml`, if you do not have a `~/.aerospace.toml` |

## The copy-once rule

When teeup installs one of these files, it records a checksum of the file in `~/.local/state/teeup/stock/`. Every later `configure` compares the file against that record:

| The file is | teeup does | and says |
|---|---|---|
| Missing | Copies it and records the checksum | "Installed ..." |
| Not changed after teeup wrote it | Nothing | "Already installed: ..." |
| A file that you changed | Nothing | "Keeping your edited ... (run teeup reset to restore the shipped file)" |
| Not from teeup, for example a file from a different dotfiles tool | Renames the file, installs the teeup file, and prints the lines that are different | "Installed ... (your previous file is at ...)" |

When teeup renames a file, it adds `.teeup_backup_<timestamp>` to the name and keeps the file in the same directory. teeup does not delete the file. teeup treats a symlink as a file that is not from teeup, and does not write through it to its target.

If a teeup update includes a new default, a migration replaces unchanged files but not your edited files.

## Local files

Write your settings in the `local.*` files. teeup installs them with all lines as comments, and `teeup reset` does not overwrite them.

| File | Loaded by |
|---|---|
| `~/.config/zsh/local.zsh` | `~/.zshrc`, last |
| `~/.config/wezterm/local.lua` | `~/.config/wezterm/wezterm.lua` |
| `~/.config/emacs/local.el` | `~/.config/emacs/init.el`, last |
| `~/.config/git/local` | `~/.config/git/config`, last. teeup does not create this file, so you must create it. |

## teeup reset

```sh
teeup reset starship
DRY_RUN=true teeup reset zsh
```

`teeup reset <capability>` restores the copied files of a capability to the version that teeup ships. For each file, the command does these steps:

1. It makes a backup file named `<name>.teeup_backup_<timestamp>` in the same directory.
2. It writes the shipped version, adapted to this Mac if the capability adapts the file (the zsh home files, the git config).
3. It prints the changes.
4. If the previous file was the shipped version, it deletes the backup file.

Then the command applies the current theme and font again, so a reset `starship.toml` file has your palette. It keeps the `local.*` files. It does not change a file that is a symlink or is not writable, and it does not overwrite a file if the backup fails.

You can reset only a capability that has copied files. For other capabilities, teeup prints that the capability "ships no config files to reset".
