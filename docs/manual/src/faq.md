# FAQ

## Linux support

teeup is for macOS. `./bootstrap` stops on any other system. On Arch Linux, [Omarchy](https://omarchy.org), which inspired teeup, does the same job.

## Supported architectures

teeup supports Apple Silicon and Intel. On Apple Silicon, teeup installs Rosetta 2. Intel-only apps run.

## Package managers

Homebrew is the default on macOS 13 and newer, MacPorts on macOS 12 and older. The first question of the first run lets you choose. MacPorts has no casks. On a MacPorts Mac, the GUI apps that only exist as casks, such as Zed, VS Code, Cursor and the browsers, are marked "not applicable" and teeup lists their download pages. See [Getting started](getting-started.md).

## Password prompts

`./bootstrap` asks for your password for `sudo`. The package manager and system settings require it. Changing your login shell to zsh asks once more.

## Storage locations

| Path | What |
|---|---|
| `~/.local/share/teeup` | The checkout: teeup's code, its layers and its themes |
| `~/.local/bin/teeup` | A link to the `teeup` command in the checkout |
| `~/.config/teeup/` | Your answers, machine file, hooks and menu additions |
| `~/.local/state/teeup/` | What teeup has done: markers, shims, the rendered theme, checksums of copied files, and logs |

## Dotfiles

teeup does not overwrite dotfiles you have edited. A file of yours that teeup needs to replace is moved aside as `<name>.teeup_backup_<timestamp>` first, and teeup prints the lines that differ. After that, every copied file is yours. See [Dotfiles](dotfiles.md).

## Migrating from older tools

`teeup migrate legacy` retires the wiring from chezmoi or the old teeup on this Mac. Run it with `DRY_RUN=true` first to preview the changes. [Migrating](migrating.md) lists what it moves aside and what it leaves alone.

## Skipping capabilities

Say no to the daily set in the wizard, or run `./bootstrap --skip-daily`. To keep any capability off one Mac for good, list it in `TEEUP_SKIP` in your machine file (see [Answers and machines](answers-and-machines.md)).

## Adding new tools

Install it the usual way, with `brew install`. `teeup update` upgrades everything Homebrew manages, not only what teeup installed. To make it part of teeup, write a capability: see [Hooks and extending](hooks-and-extending.md).

## Removing capabilities

`teeup remove <capability>`. It runs the capability's own removal steps, uninstalls its packages and casks, and keeps your config files. It refuses to run while another installed capability needs it, and it refuses a capability it has no way to undo. A removed core or daily capability comes back on the next `./bootstrap` unless you skip it.

## Uninstalling teeup

`teeup uninstall`, after a preview with `DRY_RUN=true`. It keeps your packages, edited files, SSH keys and the checkout unless you say otherwise. See [Uninstall](uninstall.md).

## SSH keys

teeup does not delete SSH keys. See [Identity](identity.md).

## Using bash

teeup's shell layer is written for zsh, and the zsh capability makes `/bin/zsh` your login shell. You can run bash scripts as always, but teeup's aliases, `PATH` and tool setup live in zsh.

## Telemetry and network usage

teeup collects no data and requires no account. It talks to the network to fetch packages, to pull its own checkout on `teeup update`, and to sign you in to GitHub and upload your public SSH key, which you approve in the browser.

## Manual version

teeup 0.1.0-beta. `teeup version` prints the version you have.
