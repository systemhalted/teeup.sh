# Doctor and troubleshooting

Run `teeup doctor` to check the system state. For every problem, it names the command to fix it.

```sh
teeup doctor           # every installed capability
teeup doctor git       # one capability
```

## What doctor checks

For each installed capability, doctor prints a heading, `== git: ... ==`, and checks:

- that the packages, casks and apps its metadata names are installed;
- whatever the capability's own doctor script checks. Eleven capabilities have one, including `ssh` (key pairs, file modes, the `Host` blocks), `git`, `github`, `zsh`, `mise`, `starship` and `aerospace`.

A capability skipped with `TEEUP_SKIP` is excluded from a full run. Name it to check it. At the end, doctor lists every problem with its fix:

```text
❌ teeup doctor found 1 problem(s):
  ssh: The personal identity has no key pair at /Users/you/.ssh/id_ed25519_personal.
      fix: teeup configure ssh
```

<!-- SCREENSHOT: `teeup doctor` on a healthy Mac, ending with "teeup doctor: everything checked is healthy." -->

The exit status has three values:

| Exit | Meaning |
|---|---|
| 0 | Everything checked is healthy. |
| 1 | Doctor found problems. |
| 2 | Doctor could not check something, such as a GitHub host it could not reach or a package manager that did not answer. The Mac may or may not be healthy there. |

Advisory notes, such as the AeroSpace Accessibility reminder, are printed as warnings and do not change the exit status.

## The logs

teeup keeps its logs in `~/.local/state/teeup/logs/`.

| Log | Written by |
|---|---|
| `bootstrap.log` | `./bootstrap`: each step's start and end, and its output |
| `lazy.log` | Installs started by a lazy shim, and the AI tools' first downloads |

Steps that need your terminal, such as the SSH passphrase and the GitHub sign-in, are not captured; the log says so in their place. Other commands print to the terminal only.

## Common problems

### `teeup: command not found` right after bootstrap

The shell running `./bootstrap` started before teeup added `~/.local/bin` to your `PATH`. Open a new terminal or run `~/.local/bin/teeup`.

### File icons in `ls` show as boxes

`ls` is eza with icons, and the icons need a Nerd Font in the terminal. WezTerm has one. In Terminal.app, set it yourself: Settings, Profiles, Text, Font, then "JetBrainsMono Nerd Font". Some icons appear without it, through macOS's font fallback, but most folder and file icons do not.

### WezTerm does not open in a virtual machine

In a macOS VM, WezTerm can fail with "failed to create NSOpenGLPixelFormat". Put this in `~/.config/wezterm/local.lua`:

```lua
return {
  config = {
    front_end = "WebGpu",
  },
}
```

### Emacs still runs the old configuration

The Emacs daemon retains its initial configuration. After changing the flavor or your init files, restart it:

```sh
launchctl kickstart -k gui/$(id -u)/sh.teeup.emacs
```

### `brew uninstall emacs` removed Emacs.app

teeup warns when Homebrew's terminal-only `emacs` formula is installed. It stops the `emacs-app` cask from linking `emacs` and `emacsclient`. teeup suggests `brew uninstall emacs` for the formula. When no `emacs` formula is installed, Homebrew applies it to the `emacs-app` cask instead and removes Emacs.app. Check first:

```sh
brew list --formula emacs    # only uninstall if this lists it
```

If Emacs.app is gone, put it back with `teeup install emacs`.

### AeroSpace does not move any windows

It needs Accessibility access, once per Mac: System Settings, Privacy & Security, Accessibility, then turn AeroSpace on.

### Stray characters such as `[?2026` appear in a prompt

They are part of a reply from your terminal, not something you typed. teeup's prompts are drawn by gum, which asks the terminal a question when a prompt opens; when the reply arrives late, gum reads part of it as typing. Delete the characters before you type your answer. If an answer was already saved with them, change it with `teeup config set`, for example `teeup config set TEEUP_EMAIL you@example.com`.

To avoid gum altogether, run with plain prompts:

```sh
TEEUP_NO_GUM=1 ./bootstrap
```

### Ctrl-C at a prompt

Ctrl-C stops the run, at a prompt too. Answers you already gave are saved, and `./bootstrap` starts again where you left off.

### `teeup update` will not pull

The teeup checkout has uncommitted changes. Commit, stash or discard them in `~/.local/share/teeup`, then run it again.

### A script fails with exit status 127 and "is provided by capability"

A lazy shim was called with no terminal to ask on, so it did not install anything. Run the `teeup install` command it printed, once, in a terminal.

### Commits are not signed

Signing turns on once your SSH key exists. Run `teeup configure git`.

## Still stuck

Run `teeup doctor` and `teeup status`, and look at the end of `~/.local/state/teeup/logs/bootstrap.log`. Every teeup command that changes something also has a preview: put `DRY_RUN=true` in front of it to see the commands it would run.
