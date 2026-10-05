# The teeup command

All teeup actions after the first run use one command, `teeup`.
This command is in `bin/teeup`.
The `./bootstrap` script links the command to `~/.local/bin/teeup`.
Most verbs need the name of a capability.
Run `teeup list` to see all capabilities.

## Install and change items

| Command | What it does |
|---|---|
| `teeup install <capability>` | Install and configure a capability and all required items. Run this command again to repair a capability that you broke manually. |
| `teeup install dev-env <lang>` | Install a language runtime with mise: `python`, `node`, `java`, `ruby`, `rust`, or `go`. |
| `teeup install font <name>` | Install a Nerd Font and configure every tool to use it. Run `teeup install font list` to see the known font names. |
| `teeup configure <capability>` | Configure the capability again. |
| `teeup reset <capability>` | Restore the configuration files to the teeup version. teeup makes a backup of your files and prints the differences. |
| `teeup update` | Update the machine. Pull the checkout, upgrade the packages, upgrade the mise tools, and run the migrations. Configure the core and daily tiers again, render the theme, and run your hooks. |
| `teeup update <capability>` | Upgrade the packages for one capability. If the capability has an update script, run it. Configure the capability again. |
| `teeup remove <capability>` | Undo the capability installation. Your configuration files remain. See [Removing a capability](#removing-a-capability). |
| `teeup uninstall` | Remove teeup from the Mac. teeup prompts for confirmation. Add `--packages` to uninstall the packages. Add `--identity` to remove your git identity. Add `--yes` to run without prompts. See [Uninstall](uninstall.md). |
| `teeup theme set <name>` | Apply a theme to all themed tools. If you do not give a name, teeup shows a picker. |
| `teeup theme list` | List the themes. |
| `teeup theme current` | Print the current theme. The `teeup theme` command does the same thing. |
| `teeup launch <app or capability>` | Start a GUI app. If the app is missing, teeup installs the capability first. App names do not need quotes. |

## Removing a capability

- **`teeup remove <capability>`** runs the capability `remove` script if it has one.
Next, the command uninstalls the casks and packages from the metadata.
Finally, teeup forgets the capability.
Your configuration files remain.

thirteen capabilities ship one today:
- The `macos-defaults` script restores preferences.
- The `terminal-app` script deletes the teeup profiles and restores the default profile.
- The `emacs` and `keyboard` scripts unload their LaunchAgents.
- The `colima` script stops the VM.
- Each of the five `ai-*` capabilities deletes its wrapper.
- The `ai` bundle removes all five leaves.
- The `ca-bundle` script deletes the PEM bundle.
- The `emacs` and `wezterm` scripts uninstall their MacPorts ports.

If another installed capability requires the target capability, the command does not run.
If the target capability does not have a `remove` script, packages, or casks, the command does not run.

Seven capabilities have nothing to undo: `dev-dirs`, `package-manager`, `secrets`, `ssh`, `teeup-runtime`, `theme`, and `xcode-clt`.
For these capabilities, `teeup remove secrets` and similar commands show a message.
teeup leaves the capability marked as installed.
If a `remove` script reports "not applicable on this machine", teeup shows this status.
teeup does not report a clean removal.

## Look at the machine

| Command | What it does |
|---|---|
| `teeup status` | Show the version, the package manager, the answers file, the installed capabilities, the lazy shims, and the language runtimes. |
| `teeup list` | Show every capability with its tier and summary. |
| `teeup list --tier core` | Show capabilities for one tier: `core`, `daily`, or `lazy`. |
| `teeup doctor` | Check the installed items and show how to fix the missing items. The command exits 0 when the machine is healthy. It exits 1 when it finds problems. It exits 2 when it cannot check an item. |
| `teeup doctor <capability>` | Check one capability. |
| `teeup has <capability>` | Exit 0 when the capability is installed. Use this command in scripts and menus. |
| `teeup version` | Print the teeup version. |

## Settings and secrets

| Command | What it does |
|---|---|
| `teeup config get` | Show the answers file, the machine file, and every answer. teeup marks the answers that the machine file pins. |
| `teeup config get <KEY>` | Print one answer, for example `TEEUP_THEME`. |
| `teeup config set <KEY> <value>` | Change one answer. teeup shows the name of the command that applies the answer. |
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
| `teeup dev check` | Run the metadata, the menu, the shellcheck, and the test checks. Add a capability name to check only that capability. |
| `teeup lazy-run <capability> <command>` | Run a lazy shim. You will rarely type this command. See [Tiers](tiers.md) for an explanation. |
| `teeup help` | Show the short usage text. |

The `dev` commands build teeup.

<!-- SCREENSHOT: Terminal output of `teeup help` in WezTerm, full height so every verb is visible. -->

## Preview with DRY_RUN

Put `DRY_RUN=true` before a command.
teeup prints the commands but does not run them.
teeup does not install, write, or delete anything.

```sh
DRY_RUN=true teeup update
DRY_RUN=true teeup remove cursor
DRY_RUN=true teeup migrate legacy
```

Skipped commands show this format:

```text
🔍 [DRY-RUN] Would execute: brew update
```

The `./bootstrap` script uses a flag: `./bootstrap --dry-run`.

When you use a command that removes items, run a dry run first.
These commands include `teeup remove`, `teeup uninstall`, and `teeup migrate legacy`.
