# Dotfiles

teeup splits the tool configuration into user files and system files. Updates modify the system files.

| Kind | Where | Owner |
|---|---|---|
| Copied once | `~/.config/<tool>/...`, and `~/.zshrc`, `~/.zshenv`, `~/.zprofile` | You, after teeup copies them |
| Local override | A `local.*` file next to the copied files | You, always |
| Generated | teeup rewrites these files. The files contain the mark "Your edits here are overwritten". | teeup |
| Layer | `capabilities/<name>/default/` in the checkout | teeup. `teeup update` upgrades these files. |

Most copied files load the teeup layer from the checkout. Then the copied files load your local file. Your settings override the settings from teeup.

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

When teeup installs a file, teeup records a checksum of the file in `~/.local/state/teeup/stock/`. Every time that you run `configure`, teeup compares the file against that record:

| The file is | teeup does | and says |
|---|---|---|
| Missing | Copies the file and records the checksum | "Installed ..." |
| Without changes after teeup wrote the file | Nothing | "Already installed: ..." |
| A file that you changed | Nothing | "Keeping your edited ... (run teeup reset to restore the shipped file)" |
| From a different tool | Changes the file name, installs a new file, and prints the different lines | "Installed ... (your previous file is at ...)" |

When teeup changes a file name, teeup adds `.teeup_backup_<timestamp>` to the file name. The file stays in the same directory. teeup does not delete the file. teeup identifies a symlink as a file from a different tool. teeup does not modify the target of a symlink.

If a teeup update includes a new default, a migration replaces unchanged files. The migration does not replace your edited files.

## Local files

Write your settings in the `local.*` files. teeup installs these files with all lines as comments. When you run `teeup reset`, teeup does not overwrite these files.

| File | Loaded by |
|---|---|
| `~/.config/zsh/local.zsh` | `~/.zshrc`, last |
| `~/.config/wezterm/local.lua` | `~/.config/wezterm/wezterm.lua` |
| `~/.config/emacs/local.el` | `~/.config/emacs/init.el`, last |
| `~/.config/git/local` | `~/.config/git/config`, last. teeup does not create this file. You must create this file. |

## teeup reset

```sh
teeup reset starship
DRY_RUN=true teeup reset zsh
```

Run `teeup reset <capability>` to restore the copied files of the capability to the default version from teeup. For each file, the command does these operations:

1. The command makes a backup file named `<name>.teeup_backup_<timestamp>` in the same directory.
2. The command writes the default version. The command configures the file for this Mac (the zsh home files, the git config).
3. The command prints the changes.
4. If the previous file was the default version, the command deletes the backup file.

Then the command applies the current theme and the current font again. A reset `starship.toml` file contains your palette. The command keeps the `local.*` files. If a file is a symlink or is not writable, the command refuses the file. If the backup operation fails, the command does not overwrite the file.

If a capability has copied files, you can reset the capability. If a capability does not have copied files, teeup prints that the capability "ships no config files to reset".
