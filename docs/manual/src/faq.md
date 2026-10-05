# FAQ

## Linux support

teeup is for macOS. The `./bootstrap` command stops on any other system. On Arch Linux, [Omarchy](https://omarchy.org) does the same job. Omarchy inspired teeup.

## Supported architectures

teeup supports Apple Silicon and Intel. If you use Apple Silicon, teeup installs Rosetta 2. Intel-only applications run on Rosetta 2.

## Package managers

Homebrew is the default package manager on macOS 13 and newer versions. MacPorts is the default package manager on macOS 12 and older versions. The first question of the first run lets you select the package manager. MacPorts has no casks.

If you use MacPorts, teeup marks the GUI applications that only exist as casks as "not applicable". These GUI applications include Zed, VS Code, Cursor, and the browsers. teeup lists the download pages for these applications. See [Getting started](getting-started.md).

## Password prompts

The `./bootstrap` command asks for your password for `sudo`. The package manager and the system settings require your password. If you change your login shell to zsh, the system asks for your password again.

## Storage locations

| Path | What |
|---|---|
| `~/.local/share/teeup` | The checkout: the teeup code, the layers, and the themes |
| `~/.local/bin/teeup` | A link to the `teeup` command in the checkout |
| `~/.config/teeup/` | Your answers, the machine file, the hooks, and the menu additions |
| `~/.local/state/teeup/` | A record of what teeup did: the markers, the shims, the rendered theme, the checksums of the copied files, and the logs |

## Dotfiles

teeup does not overwrite the dotfiles that you edit. If teeup must replace your file, teeup renames your file to `<name>.teeup_backup_<timestamp>`. teeup prints the lines that differ. After this step, you own every copied file. See [Dotfiles](dotfiles.md).

## Migrating from older tools

The `teeup migrate legacy` command removes the configuration from chezmoi or the old teeup on this Mac. Run the command with `DRY_RUN=true` first to preview the changes. The [Migrating](migrating.md) page lists the items that teeup moves and the items that teeup keeps.

## Skipping capabilities

Answer no to the daily set in the wizard, or run `./bootstrap --skip-daily`. If you never want a capability on a Mac, list the capability in `TEEUP_SKIP` in the machine file. See [Answers and machines](answers-and-machines.md).

## Adding new tools

Install the new tool with the `brew install` command. The `teeup update` command upgrades all the packages that Homebrew manages. The command upgrades the packages that teeup installs and the packages that teeup does not install. If you want to add the tool to teeup, write a capability. See [Hooks and extending](hooks-and-extending.md).

## Removing capabilities

Run `teeup remove <capability>`. This command runs the removal steps of the capability. The command uninstalls the packages and the casks, but keeps your configuration files. The command stops if another installed capability requires this capability. The command stops if teeup cannot undo the capability. If you do not skip the capability, the next `./bootstrap` run installs a removed core capability or daily capability again.

## Uninstalling teeup

Run `teeup uninstall`. Before you run this command, preview the changes with `DRY_RUN=true`. The command keeps your packages, the edited files, the SSH keys, and the checkout. If you want to remove these items, you must specify this choice. See [Uninstall](uninstall.md).

## SSH keys

teeup does not delete the SSH keys. See [Identity](identity.md).

## Using bash

The teeup shell layer uses zsh. The zsh capability makes `/bin/zsh` your login shell. You can run the bash scripts normally. But the aliases, the `PATH` variable, and the tool configuration of teeup are in zsh.

## Telemetry and network usage

teeup does not collect data. teeup does not require an account. teeup connects to the network to download the packages and to update the teeup checkout during `teeup update`. teeup also connects to the network to sign you in to GitHub and to upload your public SSH key. You approve the GitHub sign in and the key upload in the browser.

## Manual version

This manual applies to teeup 0.2.0-beta. The `teeup version` command prints your installed version.
