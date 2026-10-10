# The teeup command

All teeup actions after the first run use one command, `teeup`, which is in `bin/teeup`.
The `./bootstrap` script links it to `~/.local/bin/teeup`.
Most verbs need the name of a capability.
Run `teeup list` to see all capabilities.

## Installing and changing things

| Command | What it does |
|---|---|
| `teeup install <capability>` | Install and configure a capability and all the items that it requires. Run it again to repair a capability that you broke manually. |
| `teeup install dev-env <lang>` | Install a language runtime with mise: `python`, `node`, `java`, `ruby`, `rust`, or `go`. |
| `teeup install font <name>` | Install a Nerd Font and configure every tool to use it. Run `teeup install font list` to see the known font names. |
| `teeup configure <capability>` | Configure the capability again. |
| `teeup reset <capability>` | Restore the configuration files to the teeup version. teeup makes a backup of your files and prints the differences. |
| `teeup update` | Update the machine: move the checkout to the newest release, upgrade the packages and the mise tools, and run the migrations. Then configure the core and daily tiers again, render the theme, and run your hooks. |
| `teeup update --main` | Follow `main` instead of releases, now and in later updates. `teeup update --release` follows releases again. See [Updates](updates.md#release-or-main). |
| `teeup update <capability>` | Upgrade the packages for one capability, or run its own update script if it has one. Then configure the capability again. |
| `teeup remove <capability>` | Undo what a capability installed. Your configuration files remain. See [Removing a capability](#removing-a-capability). |
| `teeup uninstall` | Remove teeup from the Mac after you confirm. Add `--packages` to uninstall the packages. Add `--identity` to remove your git identity. Add `--yes` to run without prompts. See [Uninstall](uninstall.md). |
| `teeup theme set <name>` | Apply a theme to all themed tools. If you do not give a name, teeup shows a picker. |
| `teeup theme list` | List the themes. |
| `teeup theme current` | Print the current theme, as `teeup theme` with no verb also does. |
| `teeup launch <app or capability>` | Start a GUI app, and install its capability first if the app is missing. App names do not need quotes. |

## Removing a capability

- **`teeup remove <capability>`** runs the `remove` script of the capability, if it has one, and then uninstalls the casks and packages that its metadata lists.
  It also removes the links of the tools that it installed through mise, and uninstalls their pinned versions.
  Finally, teeup forgets the capability, but your configuration files remain.

  A `remove` script is optional, and thirteen capabilities ship one today:

  - The `macos-defaults` script restores preferences.
  - The `terminal-app` script deletes the teeup profiles and restores the default profile.
  - The `emacs` and `keyboard` scripts unload their LaunchAgents.
  - The `colima` script stops its VM.
  - The script of each of the five `ai-*` capabilities deletes its wrapper.
  - The `ai` bundle script removes all five leaves.
  - The `ca-bundle` script deletes its PEM bundle.
  - The `emacs` and `wezterm` scripts uninstall their MacPorts ports.

  The command refuses to run if another installed capability requires this one. It also refuses if the capability does not have a `remove` script, packages, casks, or tools from mise.
  Seven capabilities have nothing to undo: `dev-dirs`, `package-manager`, `secrets`, `ssh`, `teeup-runtime`, `theme`, and `xcode-clt`.
  For these capabilities, `teeup remove secrets` and similar commands tell you so, and the capability stays marked as installed.
  If a `remove` script reports "not applicable on this machine", teeup reports that status, not a clean removal.

## Looking at the machine

| Command | What it does |
|---|---|
| `teeup status` | Show the version, the package manager, the answers file, the installed capabilities, the lazy shims, and the language runtimes. |
| `teeup list` | Show every capability with its tier and summary. |
| `teeup list --tier core` | Show capabilities for one tier: `core`, `daily`, or `lazy`. |
| `teeup doctor` | Check the installed items and show how to fix the problems. The command exits 0 when the machine is healthy, 1 when it finds problems, and 2 when it cannot check an item. |
| `teeup doctor <capability>` | Check one capability. |
| `teeup has <capability>` | Exit 0 when the capability is installed, for use in scripts and menus. |
| `teeup version` | Print the teeup version. |

## Settings and secrets

| Command | What it does |
|---|---|
| `teeup config get` | Show the answers file, the machine file (if there is one), and every answer, with a mark on the answers that the machine file pins. |
| `teeup config get <KEY>` | Print one answer, for example `TEEUP_THEME`. |
| `teeup config set <KEY> <value>` | Change one answer, and show the command that applies it. |
| `teeup config edit` | Open the answers file in `$VISUAL`, `$EDITOR`, or `vi`. If an edit breaks the file, teeup restores the previous file. |
| `teeup secret set <name>` | Store a secret in the macOS Keychain. teeup asks for the value but does not echo it. |
| `teeup secret get <name>` | Print a stored secret. |
| `teeup secret rm <name>` | Delete a stored secret. |

## Everything else

| Command | What it does |
|---|---|
| `teeup menu` | Show all actions in a keyboard-driven list. See [The menu](the-menu.md). |
| `teeup migrate legacy` | Remove the old teeup and the chezmoi configuration on this Mac. See [Migrating](migrating.md). |
| `teeup commands` | List the capability names, one name per line. |
| `teeup commands --check` | Lint the capability metadata. |
| `teeup dev new-capability <name>` | Start a new capability and its test from a skeleton. |
| `teeup dev add-migration` | Start a migration script for the machines that are already configured. |
| `teeup dev check` | Run the metadata, the menu, the shellcheck, and the test checks. Add a capability name to check only that one. |
| `teeup lazy-run <capability> <command>` | The command that a lazy shim runs. You will rarely type it, and [Tiers](tiers.md) explains it. |
| `teeup help` | Show the short usage text. |

The `dev` commands build teeup.

<!-- SCREENSHOT: Terminal output of `teeup help` in WezTerm, full height so every verb is visible. -->

## Previewing with DRY_RUN

Put `DRY_RUN=true` before a command.
teeup then prints the commands but does not run them, so it does not install, write, or delete anything.

```sh
DRY_RUN=true teeup update
DRY_RUN=true teeup remove cursor
DRY_RUN=true teeup migrate legacy
```

teeup shows skipped commands in this format:

```text
🔍 [DRY-RUN] Would execute: brew update
```

The `./bootstrap` script uses a flag: `./bootstrap --dry-run`.

Before you use a command that removes items, such as `teeup remove`, `teeup uninstall`, or `teeup migrate legacy`, do a dry run.
