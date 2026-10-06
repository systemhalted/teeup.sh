# Uninstall

`teeup uninstall` removes teeup from this Mac. Run it in a terminal as your user, not as the root user.

```sh
teeup uninstall
```

It asks three questions in this order. The default answer to each question is no, so if you press Enter, teeup keeps the items.

1. **Remove teeup from this Mac?** If you answer no, teeup stops and changes nothing.
2. **Also uninstall the packages and apps teeup installed?** teeup first lists the packages and apps that its capabilities use. If you answer no, it keeps all of them.

   The list is not a record of what teeup itself installed. If you installed one of them with `brew install` before teeup, the list includes it, and a yes answer removes it. To keep it, answer no and remove the others with the commands that the summary shows.
3. **Also move aside your git identity files and remove teeup's git and ssh config?** If you answer no, teeup keeps your git identity and `~/.ssh/config`. teeup never touches SSH keys, for any answer.

To see what teeup will do without changes, preview the command first (the preview asks no questions):

```sh
DRY_RUN=true teeup uninstall
```

Before the package question, teeup lists the installed packages and apps that it recorded. If teeup has no state directory or capability records, it cannot identify which matching software it installed. It then removes nothing, and shows the package-manager commands that you can run manually.

<!-- SCREENSHOT: The end of `DRY_RUN=true teeup uninstall`, showing the "teeup uninstall summary" with its "Would remove" and "Kept" sections and the "Run it for real with:" line. -->

## What it does, in order

| Step | What comes off |
|---|---|
| 1. Shell files | teeup removes its lines in `~/.zshrc`, `~/.zshenv` and `~/.zprofile` first, so no new shell calls a tool that a later step removes. It replaces an unedited `~/.zshrc` with a short one of your own, and deletes an unedited `~/.zshenv` and `~/.zprofile`. In an edited file, teeup disables only its own lines and puts a copy of the original next to the file. |
| 2. Capabilities | teeup removes every installed capability, dependent capabilities first, with the same removal process as `teeup remove`. It removes packages and apps only if you answered yes to them. |
| 3. LaunchAgents | teeup removes each of its LaunchAgents that is still loaded, for example the Emacs daemon and the Caps Lock mapping. |
| 4. Agent skills | teeup removes the "teeup" symlinks that it put in `~/.agents/skills`, `~/.claude/skills`, `~/.codex/skills`, and `~/.gemini/skills`. |
| 5. Config files | teeup removes every file that it copied and you did not edit. If teeup replaced your file during install and the `.teeup_backup_*` copy remains, teeup offers to restore that copy. |
| 6. Identity | teeup does this step only if you answered yes to the third question. It removes the git identity file that it generated, and moves `~/.config/git/local` aside because it never wrote that file. It removes `~/.ssh/config` and `~/.config/git/config` only if teeup put them there and you never edited them. |
| 7. teeup itself | Last, and only if no step above was refused or failed, teeup removes `~/.local/bin/teeup` and the files that it wrote in `~/.config/teeup` and `~/.local/state/teeup`. If you have a machine file, hook, or theme of your own, teeup keeps `~/.config/teeup` and names it. |

## What it keeps

| Kept | Why, and how to remove it yourself |
|---|---|
| Your SSH keys | Always. teeup never deletes an SSH key. If you answered yes to the third question, the summary shows commands that remove the passphrase of each key from the Keychain and move the key aside. The public keys stay on GitHub, so delete them at github.com/settings/keys. |
| Packages and apps | Unless you answered yes to them. The summary shows the `brew uninstall` or `port uninstall` command for them. |
| Homebrew or MacPorts | Always. The summary gives the name of the uninstaller that the package manager supplies. |
| The Xcode Command Line Tools | Always, because they belong to macOS. |
| Config files you edited | Always. The summary lists them. |
| Your secrets | Always. The summary lists them with the `security delete-generic-password` command for each secret. |
| `~/Work` | Always, because your projects are in this directory. |
| The checkout | Always. The last lines show `rm -rf ~/.local/share/teeup`, which you can run when you no longer want the checkout. |

teeup also leaves the items that the tools made for themselves. These include the runtimes that mise installed, a Doom or Spacemacs checkout, and the theme and font keys in the Zed and VS Code settings.

teeup refuses to change anything outside your home directory or inside a git checkout, and refuses to write through a symlink. It does not uninstall the zsh that your login shell runs, so to change back to `/bin/zsh`, run `chsh -s /bin/zsh` first.

## Keeping Homebrew and mise on PATH

The teeup shell layer added Homebrew or MacPorts, mise, and `~/.local/bin` to your `PATH`, so after teeup removes its lines, a new shell cannot find them. The summary shows the command to add the line for each tool that stays. On Apple Silicon with Homebrew, the commands are:

```sh
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
echo 'eval "$(/opt/homebrew/bin/mise activate zsh)"' >> ~/.zshrc
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

teeup skips a line that your file already contains, and skips the two `~/.zshrc` lines if the uninstall removes mise. Intel Homebrew in `/usr/local` is on the macOS default `PATH` already, so teeup does not show a Homebrew line for it.

## After removing packages

If `~/.config/git/config` remains but the uninstall removed delta, git-lfs, or the GitHub CLI, the file still names them. The summary lists each setting with the `git config` command to remove it.

## When something is refused

The summary lists the items that teeup removed, kept and refused, and the items that failed. After a refusal or a failure, teeup keeps its own command, config, and state, and exits with a non-zero code. It shows the command to run again after you fix the cause. The command includes your answers as flags, so you can paste it without changes. A second run on a clean Mac changes nothing.

## Afterwards

Open a new terminal, or run `exec /bin/zsh -l`. The shell that ran the uninstall loaded the teeup hooks when it started, and calls them until you replace it.

## In scripts

The `--yes` flag confirms the teeup removal without questions, so use it with care. Each other flag answers one optional question in advance. Scripts require `--yes` because the command refuses to run without a terminal.

| Flag | Answers |
|---|---|
| `--packages` | Yes to the packages and apps question. |
| `--identity` | Yes to the git identity and config question. |
| `--yes` | Yes to the teeup removal, and no to every optional question that no other flag answers. |

For example, `teeup uninstall --yes --packages` removes teeup and its packages, and keeps your git identity.
