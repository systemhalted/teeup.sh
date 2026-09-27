# The teeup command

Everything teeup does after the first run goes through one command, `teeup`. It is located at `bin/teeup`. `./bootstrap` links it to `~/.local/bin/teeup`. Most verbs take the name of a capability. `teeup list` prints them all.

## Installing and changing things

| Command | What it does |
|---|---|
| `teeup install <capability>` | Install and configure it, and anything it requires. Running it again repairs a capability you broke by hand. |
| `teeup install dev-env <lang>` | Install a language runtime through mise: `python`, `node`, `java`, `ruby`, `rust` or `go`. |
| `teeup install font <name>` | Install a Nerd Font and point every tool at it. `teeup install font list` shows the names teeup knows. |
| `teeup configure <capability>` | Run only its configuration again. |
| `teeup reset <capability>` | Put its config files back to the version teeup ships. Your copy is backed up and the diff printed. |
| `teeup update` | Update the whole machine: pull the checkout, upgrade packages and mise tools, run migrations, configure the core and daily tiers again, render the theme, and run your hooks. |
| `teeup update <capability>` | Upgrade one capability's packages, or run its own update script if it has one, then configure it again. |
| `teeup remove <capability>` | Undo what a capability installed. Your config files stay. See [Removing a capability](#removing-a-capability). |
| `teeup uninstall` | Remove teeup from this Mac. It prompts for confirmation. Add `--packages` to uninstall packages. Add `--identity` to remove your git identity. Add `--yes` to run without prompts. See [Uninstall](uninstall.md). |
| `teeup theme set <name>` | Apply a theme to every themed tool. With no name, it shows a picker. |
| `teeup theme list` | List the themes. |
| `teeup theme current` | Print the current theme. This is also what plain `teeup theme` does. |
| `teeup launch <app or capability>` | Open a GUI app, installing its capability first if the app is missing. App names need no quotes. |

## Removing a capability

- **`teeup remove <capability>`** runs the capability's `remove` script if it
  has one. (twelve capabilities ship one today: `macos-defaults` restores
  preferences; `terminal-app` deletes teeup's profiles and restores the default;
  `emacs` and `keyboard` unload their LaunchAgents; `colima` stops its VM;
  each of the five `ai-*` capabilities deletes its wrapper; the `ai` bundle
  removes all five leaves; `emacs` and `wezterm` uninstall their MacPorts ports.)
  Next, it uninstalls the casks and packages listed in its metadata. Finally, it
  forgets the capability. Your configuration files remain. The command refuses
  to run if another installed capability requires it. It refuses to run if the
  capability lacks a `remove` script, packages, or casks. Seven capabilities
  have nothing to undo: `dev-dirs`, `package-manager`, `secrets`, `ssh`,
  `teeup-runtime`, `theme`, and `xcode-clt`. A `remove` script that reports
  "not applicable on this machine" is displayed.

## Looking at the machine

| Command | What it does |
|---|---|
| `teeup status` | The version, package manager, answers file, installed capabilities, lazy shims and language runtimes. |
| `teeup list` | Every capability with its tier and summary. |
| `teeup list --tier core` | The same, for one tier: `core`, `daily` or `lazy`. |
| `teeup doctor` | Check what is installed and say how to fix what is not. It exits 0 when the machine is healthy, 1 when it found problems, and 2 when it could not check something. |
| `teeup doctor <capability>` | Check one capability. |
| `teeup has <capability>` | Exit 0 when it is installed. Useful in scripts and menus. |
| `teeup version` | Print the teeup version. |

## Settings and secrets

| Command | What it does |
|---|---|
| `teeup config get` | Show the answers file, the machine file if there is one, and every answer, marking the ones the machine file pins. |
| `teeup config get <KEY>` | Print one answer, such as `TEEUP_THEME`. |
| `teeup config set <KEY> <value>` | Change one answer, then name the command that applies it. |
| `teeup config edit` | Open the answers file in `$VISUAL`, or `$EDITOR`, or `vi`. An edit that breaks the file is rolled back. |
| `teeup secret set <name>` | Store a secret in the macOS Keychain. It asks for the value without echoing it. |
| `teeup secret get <name>` | Print a stored secret. |
| `teeup secret rm <name>` | Delete a stored secret. |

## Everything else

| Command | What it does |
|---|---|
| `teeup menu` | Every action as a keyboard-driven list. See [The menu](the-menu.md). |
| `teeup migrate legacy` | Retire the old teeup and chezmoi wiring on this Mac. See [Migrating](migrating.md). |
| `teeup commands` | List the capability names, one per line. |
| `teeup commands --check` | Lint the capability metadata. |
| `teeup dev new-capability <name>` | Start a new capability and its test from a skeleton. |
| `teeup dev add-migration` | Start a migration script for machines that are already set up. |
| `teeup dev check` | Run the metadata, menu, shellcheck and test checks. Add a capability name to check one. |
| `teeup lazy-run <capability> <command>` | What a lazy shim runs. You will rarely type it; [Tiers](tiers.md) explains it. |
| `teeup help` | The short usage text. |

The `dev` commands build teeup.

<!-- SCREENSHOT: Terminal output of `teeup help` in WezTerm, full height so every verb is visible. -->

## Previewing with DRY_RUN

Prefix a command with `DRY_RUN=true`. teeup prints what it would run instead of running it. Nothing is installed, written, or deleted.

```sh
DRY_RUN=true teeup update
DRY_RUN=true teeup remove cursor
DRY_RUN=true teeup migrate legacy
```

Skipped commands appear as follows:

```text
🔍 [DRY-RUN] Would execute: brew update
```

`./bootstrap` uses a flag: `./bootstrap --dry-run`.

Run a dry run before using a command that removes items, such as `teeup remove`, `teeup uninstall`, or `teeup migrate legacy`.
