# Uninstall

`teeup uninstall` removes teeup from this Mac. Run it in a terminal, as your user, not root:

```sh
teeup uninstall
```

It asks three questions, in this order. Each one defaults to no, so pressing Enter keeps things.

1. **Remove teeup from this Mac?** No stops here and changes nothing.
2. **Also uninstall the packages and apps teeup installed?** teeup first lists the packages and apps its capabilities use. No keeps them all. The list is not a record of what teeup itself installed: if you installed one of them with `brew install` before teeup, it is listed too, and yes removes it. To keep it, answer no and remove the others with the commands the summary prints.
3. **Also move aside your git identity files and remove teeup's git and ssh config?** No keeps your git identity and `~/.ssh/config`. SSH keys are never touched, whatever you answer.

To see what it would do without changing anything, preview it first. The preview asks nothing:

```sh
DRY_RUN=true teeup uninstall
```

Before the package question, teeup lists the installed packages and apps it recorded. If teeup has no state directory or capability records, it cannot tell which matching software it installed. It removes nothing and prints the package-manager commands you can run by hand.

<!-- SCREENSHOT: The end of `DRY_RUN=true teeup uninstall`, showing the "teeup uninstall summary" with its "Would remove" and "Kept" sections and the "Run it for real with:" line. -->

## What it does, in order

| Step | What comes off |
|---|---|
| 1. Shell files | teeup's lines in `~/.zshrc`, `~/.zshenv` and `~/.zprofile`, first, so no new shell calls a tool that is about to go. An unedited `~/.zshrc` becomes a short one of your own; unedited `~/.zshenv` and `~/.zprofile` go. In an edited file only teeup's lines are disabled, with a copy of the original beside it. |
| 2. Capabilities | Every installed capability, dependents first, through the same removal `teeup remove` uses. Packages and apps only if you said yes to them. |
| 3. LaunchAgents | Any of teeup's LaunchAgents still loaded, such as the Emacs daemon and the Caps Lock mapping. |
| 4. Agent skills | The "teeup" symlinks placed in `~/.agents/skills`, `~/.claude/skills`, `~/.codex/skills`, and `~/.gemini/skills`. |
| 5. Config files | Every file teeup copied and you never edited. Where teeup replaced a file of yours at install time and the `.teeup_backup_*` copy is still there, it offers to put that copy back. |
| 6. Identity | Only if you said yes to the third question: the git identity file teeup generated, `~/.config/git/local` (moved aside, since teeup never wrote it), and `~/.ssh/config` and `~/.config/git/config` if teeup put them there and you never edited them. |
| 7. teeup itself | Last, and only if nothing above was refused or failed: `~/.local/bin/teeup`, and the files teeup wrote in `~/.config/teeup` and `~/.local/state/teeup`. A machine file, hook or theme of your own keeps `~/.config/teeup` in place, and teeup names it. |

## What it keeps

| Kept | Why, and how to remove it yourself |
|---|---|
| Your SSH keys | Always. teeup never deletes an SSH key. If you said yes to the third question, the summary prints the commands that drop each key's passphrase from the Keychain and move the key aside. The public keys stay on GitHub; delete them at github.com/settings/keys. |
| Packages and apps | Unless you said yes to them. The summary prints the `brew uninstall` or `port uninstall` command for them. |
| Homebrew or MacPorts | Always. The summary names the package manager's own uninstaller. |
| The Xcode Command Line Tools | Always. They belong to macOS. |
| Config files you edited | Always. The summary lists them. |
| Your secrets | Always. The summary lists them with the `security delete-generic-password` command for each. |
| `~/Work` | Always. Your projects live there. |
| The checkout | Always. The last lines print `rm -rf ~/.local/share/teeup` for you to run when you no longer want it. |

It also leaves what the tools made for themselves: the runtimes mise installed, a Doom or Spacemacs checkout, and the theme and font keys in Zed's and VS Code's settings.

It refuses anything outside your home directory, anything inside a git checkout, and any symlink it would have to write through. It will not uninstall the zsh your login shell runs; switch back to `/bin/zsh` with `chsh -s /bin/zsh` first.

## Keeping Homebrew and mise on PATH

teeup's shell layer was what put Homebrew or MacPorts, mise and `~/.local/bin` on your `PATH`. Once its lines are gone, a new shell cannot find them. The summary prints the command that adds the line for each one that stays. On Apple Silicon with Homebrew, the lines amount to:

```sh
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
echo 'eval "$(/opt/homebrew/bin/mise activate zsh)"' >> ~/.zshrc
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

It skips a line your own file already has, and the two `~/.zshrc` lines when the uninstall removed mise. Intel Homebrew in `/usr/local` is on macOS's default `PATH` already, so it gets no Homebrew line.

## After removing packages

If your `~/.config/git/config` stays but the uninstall removed delta, git-lfs or the GitHub CLI, the file still names them. The summary lists each such setting with the `git config` command that removes it.

## When something is refused

The summary lists what was removed, kept, refused and failed. After a refusal or failure, teeup keeps its own command, config and state, exits non-zero, and prints the command to rerun once you fix the cause. It carries your answers as flags, so you can paste it as it is. A second run on a clean Mac changes nothing.

## Afterwards

Open a new terminal, or run `exec /bin/zsh -l`. The shell you ran the uninstall from loaded teeup's hooks when it started and keeps calling them until it is replaced.

## In scripts

`--yes` confirms removing teeup without asking, so use it with care. Each other flag answers one optional question in advance. Scripts need `--yes`, because without a terminal the command refuses to run.

| Flag | Answers |
|---|---|
| `--packages` | Yes to the packages and apps question. |
| `--identity` | Yes to the git identity and config question. |
| `--yes` | Yes to removing teeup, and no to every optional question not answered by another flag. |

`teeup uninstall --yes --packages`, for example, removes teeup and its packages and keeps your git identity.
