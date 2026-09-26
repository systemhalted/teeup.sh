# FAQ

## Does teeup run on Linux?

No. teeup is for macOS, and `./bootstrap` stops on any other system. On Arch Linux, [Omarchy](https://omarchy.org), which inspired teeup, does the same job.

## Apple Silicon or Intel?

Both. On Apple Silicon teeup also installs Rosetta 2, so Intel-only apps run.

## Homebrew or MacPorts?

Homebrew on macOS 13 and newer, MacPorts on macOS 12 and older, and the first question of the first run lets you choose. MacPorts has no casks, so on a MacPorts Mac the GUI apps that only exist as casks, such as Zed, VS Code, Cursor and the browsers, are marked "not applicable" and teeup names their download pages. See [Getting started](getting-started.md).

## Why does it ask for my password?

At the start of `./bootstrap`, for `sudo`: the package manager and some system settings need it. Changing your login shell to zsh asks once more.

## Where does teeup keep things?

| Path | What |
|---|---|
| `~/.local/share/teeup` | The checkout: teeup's code, its layers and its themes |
| `~/.local/bin/teeup` | A link to the `teeup` command in the checkout |
| `~/.config/teeup/` | Your answers, machine file, hooks and menu additions |
| `~/.local/state/teeup/` | What teeup has done: markers, shims, the rendered theme, checksums of copied files, and logs |

## Will teeup overwrite my dotfiles?

Not the ones you have edited. A file of yours that teeup wants to replace is moved aside as `<name>.teeup_backup_<timestamp>` first, and teeup prints the lines that differ. After that, every copied file is yours. See [Dotfiles](dotfiles.md).

## I used chezmoi, or the old teeup. What now?

`teeup migrate legacy` retires that wiring on this Mac. Run it with `DRY_RUN=true` first to read what it would do. The README's [migration section](https://github.com/systemhalted/teeup.sh#migrating-a-mac-that-already-had-teeup-or-chezmoi) says what it moves aside and what it never touches.

## Can I skip part of it?

Say no to the daily set in the wizard, or run `./bootstrap --skip-daily`. To keep any capability off one Mac for good, list it in `TEEUP_SKIP` in your machine file (see [Answers and machines](answers-and-machines.md)).

## How do I add a tool teeup doesn't know?

Install it the usual way, with `brew install`. `teeup update` upgrades everything Homebrew manages, not only what teeup installed. To make it part of teeup, write a capability: see [Hooks and extending](hooks-and-extending.md).

## How do I undo one capability?

`teeup remove <capability>`. It runs the capability's own removal steps, uninstalls its packages and casks, and keeps your config files. It refuses while another installed capability needs it, and it refuses a capability it has no way to undo, rather than claim it did. A removed core or daily capability comes back on the next `./bootstrap` unless you skip it.

## Does teeup ever delete an SSH key?

Never. teeup has no command or flag that deletes one. See [Identity](identity.md).

## Can I use bash instead of zsh?

teeup's shell layer is written for zsh, and the zsh capability makes `/bin/zsh` your login shell. You can run bash scripts as always, but teeup's aliases, `PATH` and tool setup live in zsh.

## Does teeup send anything anywhere?

teeup itself collects nothing and has no account. It talks to the network to fetch packages, to pull its own checkout on `teeup update`, and to sign you in to GitHub and upload your public SSH key, which you approve in the browser.

## Which version does this manual describe?

teeup 0.1.0-beta. `teeup version` prints the version you have.
