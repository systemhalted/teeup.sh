# Doctor and troubleshooting

Run `teeup doctor` to check the system state.
For every problem, it names the command that fixes it.

```sh
teeup doctor           # every installed capability
teeup doctor git       # one capability
```

## What doctor checks

For each installed capability, doctor prints a heading `== git: ... ==` and checks that the packages, casks, and apps that its metadata names are installed.
It also checks each tool from mise.
The link in `~/.local/bin` must point to the teeup link in `~/.local/state/teeup/tools`, at the version of the teeup release, and the tool must run.
It also runs the checks in the doctor script of the capability, if it has one.
Eleven capabilities have a doctor script, including `ssh` (key pairs, file modes, the `Host` blocks), `git`, `github`, `zsh`, `mise`, `starship`, and `aerospace`.

If you skip a capability with `TEEUP_SKIP`, doctor excludes it from a full run, but you can name the capability to check it.
At the end, doctor lists every problem with its fix:

```text
❌ teeup doctor found 1 problem(s):
  ssh: The personal identity has no key pair at /Users/you/.ssh/id_ed25519_personal.
      fix: teeup configure ssh
```

<!-- SCREENSHOT: `teeup doctor` on a healthy Mac, ending with "teeup doctor: everything checked is healthy." -->

The exit status has three values:

| Exit | Meaning |
|---|---|
| 0 | Everything that doctor checks is healthy. |
| 1 | Doctor found problems. |
| 2 | Doctor could not check an item, for example because it could not reach a GitHub host or a package manager did not answer. The Mac can be healthy or not healthy there. |

Doctor prints advisory notes, such as the AeroSpace Accessibility reminder, as warnings that do not change the exit status.

## The logs

teeup keeps its logs in `~/.local/state/teeup/logs/`.

| Log | Written by |
|---|---|
| `bootstrap.log` | `./bootstrap` writes the start, the end, and the output of each step. |
| `lazy.log` | The installs that a lazy shim starts, and the first downloads of the AI tools. |

The log does not capture the steps that need your terminal, such as the SSH passphrase and the GitHub sign-in.
In their place, the log has a message.
Other commands print to the terminal only.

## Common problems

### `teeup: command not found` right after bootstrap

The shell that ran `./bootstrap` started before teeup added `~/.local/bin` to your `PATH`.
Open a new terminal, or run `~/.local/bin/teeup`.

### File icons in `ls` show as boxes

The `ls` command is `eza` with icons that need a Nerd Font in the terminal, and WezTerm has one.
In Terminal.app, select Settings, Profiles, Text, Font, and "JetBrainsMono Nerd Font".
Without a Nerd Font, the macOS font fallback draws some icons, but not most folder and file icons.

### WezTerm does not open in a virtual machine

WezTerm can fail with "failed to create NSOpenGLPixelFormat" in a macOS VM.
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

If the terminal-only `emacs` formula from Homebrew is installed, teeup shows a warning, because this formula stops the `emacs-app` cask from linking `emacs` and `emacsclient`.
teeup suggests `brew uninstall emacs` to remove the formula.
If the `emacs` formula is not installed, Homebrew applies that command to the `emacs-app` cask instead and removes Emacs.app.
Check first:

```sh
brew list --formula emacs    # only uninstall if this lists it
```

If Emacs.app is gone, run `teeup install emacs` to install it again.

### AeroSpace does not move any windows

AeroSpace needs Accessibility access one time for each Mac.
Open System Settings.
Select Privacy & Security, and then Accessibility.
Enable AeroSpace.

### Stray characters such as `[?2026` appear in a prompt

The characters are part of a reply from your terminal, not text that you typed.
The teeup prompts come from `gum`, which asks the terminal a question when a prompt opens.
If the reply arrives late, `gum` reads part of it as text that you type.
Delete the characters before you type your answer.
If teeup saved an answer with the characters, change it with `teeup config set`, for example `teeup config set TEEUP_EMAIL you@example.com`.

If you do not want to use `gum`, run `./bootstrap` with plain prompts:

```sh
TEEUP_NO_GUM=1 ./bootstrap
```

### Ctrl-C at a prompt

Ctrl-C stops the run, also at a prompt, but teeup keeps the answers that you gave.
Run `./bootstrap` again to continue from the point where it stopped.

### `teeup update` does not move the checkout

`teeup update` moves the checkout in `~/.local/share/teeup` only forward. The message tells you why it did not move:

| Message | What to do |
|---|---|
| "has uncommitted changes" | Commit, stash, or discard the changes in the checkout. Then run `teeup update` again. |
| "teeup is ahead of the newest release" | Nothing. This is correct for a checkout that followed `main`. The checkout moves when a newer release exists. |
| "has commits that the newest release ... does not have" | The checkout has your own commits. Move them to a branch, or run `teeup update --main` if you want to follow `main`. |
| "The checkout ... has commits that origin/main does not have" | You made commits on top of a release. Put them on a branch, then run `teeup update --main` again. |
| "The local branch main ... has commits that origin/main does not have" | Move your commits from `main` to a different branch. Then run `teeup update --main` again. |
| "git fetch failed" with a certificate message | The network re-signs HTTPS. Run `teeup doctor ca-bundle`, or run `teeup update` on a different network. |

### The installer stops

The one-line installer stops with a message in these cases:

| Message | What to do |
|---|---|
| "is not a git checkout of teeup" | Move the directory `~/.local/share/teeup` aside. Then run the installer again. |
| "softwareupdate could not install" or "The Command Line Tools are still missing" | Run `xcode-select --install`, complete the dialog, and then run the installer again. |
| "git clone ... failed" | The network can re-sign HTTPS, which git does not trust before teeup builds its certificate bundle. Run the installer on a different network. |
| "Run the installer as your own user" | Do not use `sudo` for the installer. The installer asks for your password when it needs it. |

If the installer shows "Waiting for the Command Line Tools installer to finish", complete Apple's dialog. The installer continues when the tools are installed.

### A script fails with exit status 127 and "is provided by capability"

A command called a lazy shim without a terminal, so the shim could not ask you and did not install anything.
Run the printed `teeup install` command one time in a terminal.

### Doctor says that Homebrew still has an old copy of a tool

In teeup 0.3.0-beta and older, Homebrew or MacPorts installed tools such as ripgrep, Starship, and Neovim. Now mise installs them at the versions of the teeup release. The old copies stay installed, and `teeup update` does not upgrade them.

Doctor shows a warning for each old copy, with the command that removes it, for example `brew uninstall ripgrep`. The warning does not change the exit status. teeup does not remove the old copies itself.

### A tool link in `~/.local/bin` is missing or broken

teeup links each tool in two steps. `~/.local/bin/rg` points to `~/.local/state/teeup/tools/rg`, and that link points to the version that mise installed. `mise uninstall` and `mise prune` can remove that version, and doctor then reports the link as broken. If you delete `~/.local/state/teeup`, doctor reports the second link as missing. Run the fix that doctor shows, for example `teeup configure cli-tools`. This command installs the pinned version again and repairs the links.

### Commits are not signed

teeup enables commit signing only when your SSH key exists.
Run `teeup configure git`.

## Still stuck

Run `teeup doctor` and `teeup status`.
Look at the end of `~/.local/state/teeup/logs/bootstrap.log`.
Every teeup command that changes an item has a preview.
Put `DRY_RUN=true` in front of the command to see the commands that it would run.
