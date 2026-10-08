# FAQ

## Linux support

teeup is for macOS, and `./bootstrap` stops on any other system. On Arch Linux, [Omarchy](https://omarchy.org), which inspired teeup, does the same job.

## Supported architectures

teeup supports Apple Silicon and Intel. On Apple Silicon, teeup installs Rosetta 2 so that Intel-only applications run.

## Package managers

Homebrew is the default package manager on macOS 13 and newer, and MacPorts on macOS 12 and older. The first question of the first run lets you select the package manager.

MacPorts has no casks. If you use MacPorts, teeup marks the GUI applications that only exist as casks as "not applicable" and lists their download pages. These applications include Zed, VS Code, Cursor, and the browsers. See [Getting started](getting-started.md).

## Password prompts

`./bootstrap` asks for your password for `sudo`, because the package manager and the system settings require it. If you change your login shell to zsh, the system asks for your password again.

## Storage locations

| Path | What |
|---|---|
| `~/.local/share/teeup` | The checkout: the teeup code, its layers, and its themes |
| `~/.local/bin/teeup` | A link to the `teeup` command in the checkout |
| `~/.config/teeup/` | Your answers, the machine file, the hooks, and the menu additions |
| `~/.local/state/teeup/` | A record of what teeup did: the markers, the shims, the rendered theme, the checksums of the copied files, and the logs |

## Dotfiles

teeup does not overwrite the dotfiles that you edit. If teeup must replace one of your files, it first renames your file to `<name>.teeup_backup_<timestamp>` and prints the lines that differ. After that, you own every copied file. See [Dotfiles](dotfiles.md).

## Migrating from older tools

`teeup migrate legacy` retires the wiring from chezmoi or the old teeup on this Mac. Run it with `DRY_RUN=true` first to preview the changes. [Migrating](migrating.md) lists what it moves aside and what it keeps.

## Skipping capabilities

Answer no to the daily set in the wizard, or run `./bootstrap --skip-daily`. If you never want a capability on a Mac, list it in `TEEUP_SKIP` in the machine file (see [Answers and machines](answers-and-machines.md)).

## Adding new tools

Install the new tool with `brew install`. `teeup update` upgrades only the packages that teeup capabilities use, so you upgrade the new tool yourself with `brew upgrade`. To make the tool part of teeup, write a capability (see [Hooks and extending](hooks-and-extending.md)).

## Removing capabilities

Run `teeup remove <capability>`. It runs the removal steps of the capability and uninstalls its packages and casks, but keeps your configuration files. It stops if another installed capability requires this capability, or if teeup cannot undo the capability. The next `./bootstrap` installs a removed core or daily capability again, unless you skip it.

## Uninstalling teeup

Run `teeup uninstall` after you preview the changes with `DRY_RUN=true`. It keeps your packages, the edited files, the SSH keys, and the checkout, unless you tell it to remove them. See [Uninstall](uninstall.md).

## SSH keys

teeup does not delete SSH keys. See [Identity](identity.md).

## Using bash

The teeup shell layer uses zsh, and the zsh capability makes `/bin/zsh` your login shell. You can run bash scripts as usual, but the teeup aliases, `PATH`, and tool configuration are in zsh.

## Telemetry and network usage

teeup does not collect data or require an account. It connects to the network to download packages, and to update its checkout during `teeup update`. It also connects to sign you in to GitHub and to upload your public SSH key, which you approve in the browser.

## The newest code

`teeup update` installs the newest release. To get the code on `main` before it is in a release, run `teeup update --main`. The code on `main` can be unstable. To follow releases again, run `teeup update --release`. See [Release or main](updates.md#release-or-main).

## Reading the installer first

The one-line installer sends the script from `curl` directly to `bash`. To read the script before it runs, download it, read it, and then run it with `bash install.sh`. [Getting started](getting-started.md) shows the commands.

## Manual version

This manual applies to teeup 0.2.1-beta. `teeup version` prints the version that you have.
