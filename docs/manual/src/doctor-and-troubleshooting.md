# Doctor and troubleshooting

Run `teeup doctor` to check the system state.
It names the command to fix every problem.

```sh
teeup doctor           # every installed capability
teeup doctor git       # one capability
```

## What doctor checks

The doctor command prints a heading `== git: ... ==` for each capability that you install.
The doctor command checks that the packages, casks, and apps from the metadata exist.
The doctor command checks the items from the doctor script of the capability.
Eleven capabilities have a doctor script.
These include `ssh` (key pairs, file modes, the `Host` blocks), `git`, `github`, `zsh`, `mise`, `starship`, and `aerospace`.

If you skip a capability with `TEEUP_SKIP`, the doctor command excludes it from a full run.
Name the capability to check it.
At the end, the doctor command lists every problem with its fix:

```text
❌ teeup doctor found 1 problem(s):
  ssh: The personal identity has no key pair at /Users/you/.ssh/id_ed25519_personal.
      fix: teeup configure ssh
```

<!-- SCREENSHOT: `teeup doctor` on a healthy Mac, ending with "teeup doctor: everything checked is healthy." -->

The exit status has three values:

| Exit | Meaning |
|---|---|
| 0 | Everything that the doctor command checks is healthy. |
| 1 | The doctor command found problems. |
| 2 | The doctor command could not check an item. For example, the doctor command could not reach a GitHub host or a package manager did not answer. The Mac can be healthy or not healthy there. |

The doctor command prints advisory notes as warnings.
For example, the doctor command prints the AeroSpace Accessibility reminder.
These warnings do not change the exit status.

## The logs

The teeup command keeps the logs in `~/.local/state/teeup/logs/`.

| Log | Written by |
|---|---|
| `bootstrap.log` | `./bootstrap` writes the start, the end, and the output of each step. |
| `lazy.log` | A lazy shim writes the installs. AI tools write the first downloads. |

The log does not capture the steps that need your terminal.
For example, it does not capture the SSH passphrase and the GitHub sign-in.
The log writes a message in their place.
Other commands print to the terminal only.

## Common problems

### `teeup: command not found` right after bootstrap

The shell that ran `./bootstrap` started before the teeup command added `~/.local/bin` to your `PATH`.
Open a new terminal.
Or, run `~/.local/bin/teeup`.

### File icons in `ls` show as boxes

The `ls` command is `eza` with icons that need a Nerd Font in the terminal.
The WezTerm app has a Nerd Font.
In Terminal.app, select Settings, Profiles, Text, Font, and "JetBrainsMono Nerd Font".
Some icons show without a Nerd Font because macOS uses a font fallback.
But, most folder and file icons do not show.

### WezTerm does not open in a virtual machine

The WezTerm app can fail with "failed to create NSOpenGLPixelFormat" in a macOS VM.
Add this code to `~/.config/wezterm/local.lua`:

```lua
return {
  config = {
    front_end = "WebGpu",
  },
}
```

### Emacs still runs the old configuration

The Emacs daemon keeps its initial configuration.
When you change the flavor or your init files, restart it:

```sh
launchctl kickstart -k gui/$(id -u)/sh.teeup.emacs
```

### `brew uninstall emacs` removed Emacs.app

When you install the terminal-only `emacs` formula from Homebrew, the teeup command warns you.
This formula stops the `emacs-app` cask.
The `emacs-app` cask cannot link `emacs` and `emacsclient`.
The teeup command suggests `brew uninstall emacs` for the formula.
If you do not install the `emacs` formula, Homebrew applies the command to the `emacs-app` cask and removes Emacs.app.
Check the packages first:

```sh
brew list --formula emacs    # only uninstall if this lists it
```

If Homebrew removes Emacs.app, run `teeup install emacs`.

### AeroSpace does not move any windows

The AeroSpace app needs Accessibility access one time for each Mac.
Open System Settings.
Select Privacy & Security, and then Accessibility.
Enable the AeroSpace app.

### Stray characters such as `[?2026` appear in a prompt

Stray characters are part of a reply from your terminal, and you did not type them.
When a prompt opens, the `gum` command draws the prompts for teeup and asks the terminal a question.
If the reply arrives late, the `gum` command reads part of the reply as text that you type.
Delete the characters before you type your answer.
If teeup saved an answer with the characters, change it with `teeup config set`.
For example, run `teeup config set TEEUP_EMAIL you@example.com`.

Do not use the `gum` command.
Run `./bootstrap` with plain prompts:

```sh
TEEUP_NO_GUM=1 ./bootstrap
```

### Ctrl-C at a prompt

The Ctrl-C key stops the run, even at a prompt.
The teeup command saves the answers that you gave.
`./bootstrap` starts again from the last step.

### `teeup update` will not pull

The teeup checkout has uncommitted changes.
Commit, stash, or discard the changes in `~/.local/share/teeup`.
Run `teeup update` again.

### A script fails with exit status 127 and "is provided by capability"

A command called a lazy shim without a terminal.
The lazy shim could not ask questions.
The lazy shim did not install anything.
Run the printed `teeup install` command one time in a terminal.

### Commits are not signed

When your SSH key exists, the teeup command enables commit signing.
Run `teeup configure git`.

## Still stuck

Run `teeup doctor` and `teeup status`.
Look at the end of `~/.local/state/teeup/logs/bootstrap.log`.
Every teeup command that changes an item has a preview.
Put `DRY_RUN=true` in front of the command to see the commands that it runs.
