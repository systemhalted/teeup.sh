# Uninstall

`teeup uninstall` removes teeup from this Mac. Run the command in a terminal as your user. Do not run the command as the root user.

```sh
teeup uninstall
```

`teeup uninstall` asks three questions in this sequence. The default answer for each question is no. Press the Enter key to keep the items.

1. **Remove teeup from this Mac?** If you answer no, teeup stops.
2. **Also uninstall the packages and apps teeup installed?** teeup lists the packages and apps. If you answer no, teeup keeps them. If you answer yes, teeup removes them. This includes packages you installed before teeup. To keep a package, answer no.
3. **Also move aside your git identity files and remove teeup's git and ssh config?** If you answer no, teeup keeps your config. teeup never modifies SSH keys.

If you want to see what teeup does without changes, preview the command first. The preview asks no questions:

```sh
DRY_RUN=true teeup uninstall
```

Before the package question, teeup lists the installed packages and apps that it recorded. If teeup has no state directory or capability records, teeup cannot identify the software that it installed. teeup removes nothing. It shows the package-manager commands that you can run manually.

<!-- SCREENSHOT: The end of `DRY_RUN=true teeup uninstall`, showing the "teeup uninstall summary" with its "Would remove" and "Kept" sections and the "Run it for real with:" line. -->

## What teeup does in sequence

| Step | What comes off |
|---|---|
| 1. Shell files | teeup removes its lines in `~/.zshrc`, `~/.zshenv` and `~/.zprofile` first. This prevents new shells from calling a removed tool. An unedited `~/.zshrc` becomes your short file. teeup deletes unedited `~/.zshenv` and `~/.zprofile` files. If you edited a file, teeup disables only the teeup lines. teeup puts a copy of the original file next to it. |
| 2. Capabilities | teeup removes every installed capability. It removes dependent capabilities first. It uses the same removal process as `teeup remove`. If you answered yes, teeup removes packages and apps. |
| 3. LaunchAgents | teeup removes loaded teeup LaunchAgents. Examples include the Emacs daemon and the Caps Lock mapping. |
| 4. Agent skills | teeup removes the teeup symlinks in `~/.agents/skills`, `~/.claude/skills`, `~/.codex/skills`, and `~/.gemini/skills`. |
| 5. Config files | teeup removes every file that it copied and you did not edit. If teeup replaced your file during install and the `.teeup_backup_*` copy remains, teeup offers to restore that copy. |
| 6. Identity | If you answered yes to the third question, teeup removes the generated git identity file. teeup moves `~/.config/git/local` because teeup did not write it. If teeup installed `~/.ssh/config` and `~/.config/git/config` and you did not edit them, teeup removes them. |
| 7. teeup itself | If no previous step failed or was refused, teeup removes `~/.local/bin/teeup`. It removes the files that teeup wrote in `~/.config/teeup` and `~/.local/state/teeup`. If you have a machine file, hook, or theme, teeup keeps `~/.config/teeup` and names the file. |

## What teeup keeps

| Kept | Why, and how to remove it yourself |
|---|---|
| Your SSH keys | teeup always keeps SSH keys. teeup never deletes an SSH key. If you answered yes to the third question, the summary shows the commands to remove the passphrases from the Keychain. The commands also move the keys. The public keys stay on GitHub. Delete them at github.com/settings/keys. |
| Packages and apps | If you answered no, teeup keeps packages and apps. The summary shows the `brew uninstall` or `port uninstall` command for each package. |
| Homebrew or MacPorts | teeup always keeps Homebrew or MacPorts. The summary gives the name of the package manager uninstaller. |
| The Xcode Command Line Tools | teeup always keeps the Xcode Command Line Tools. They belong to macOS. |
| Config files you edited | teeup always keeps the config files that you edited. The summary lists them. |
| Your secrets | teeup always keeps your secrets. The summary lists them with the `security delete-generic-password` command for each secret. |
| `~/Work` | teeup always keeps `~/Work`. Your projects are in this directory. |
| The checkout | teeup always keeps the checkout. The last lines show `rm -rf ~/.local/share/teeup`. Run this command when you do not want the checkout. |

teeup also leaves the items that the tools made for themselves. These items include the runtimes that mise installed, and a Doom or Spacemacs checkout. The items also include the theme and font keys in the Zed and VS Code settings.

teeup refuses to remove items outside your home directory. teeup refuses to remove items inside a git checkout. teeup refuses to write through a symlink. teeup does not uninstall the zsh that your login shell runs. To switch to `/bin/zsh`, run `chsh -s /bin/zsh` first.

## Keeping Homebrew and mise on PATH

The teeup shell layer added Homebrew, MacPorts, mise, and `~/.local/bin` to your `PATH`. When teeup removes its lines, a new shell cannot find these tools. The summary shows the command to add the line for each tool that stays. On Apple Silicon with Homebrew, the commands are:

```sh
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
echo 'eval "$(/opt/homebrew/bin/mise activate zsh)"' >> ~/.zshrc
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

If your file already contains a line, teeup skips it. If the uninstall removes mise, teeup skips the two `~/.zshrc` lines. Intel Homebrew in `/usr/local` is on the macOS default `PATH` already. teeup does not show a Homebrew line for Intel Homebrew.

## After removing packages

If `~/.config/git/config` remains but the uninstall removed delta, git-lfs, or the GitHub CLI, the file still names them. The summary lists each setting with the `git config` command to remove it.

## When something is refused

The summary lists removed, kept, refused, and failed items. If a failure or refusal occurs, teeup keeps its command, config, and state. teeup exits with a non-zero code.

teeup shows the command to run again after you fix the problem. The command includes your answers as flags. You can paste the command directly. A second run on a clean Mac changes nothing.

## Afterwards

Open a new terminal. You can also run `exec /bin/zsh -l`. The shell that ran the uninstall loaded the teeup hooks when it started. The shell calls the hooks until you replace the shell.

## In scripts

The `--yes` flag confirms the teeup removal without questions. Use the `--yes` flag with care. Each other flag answers one optional question in advance. Scripts require the `--yes` flag because the command refuses to run without a terminal.

| Flag | Answers |
|---|---|
| `--packages` | Yes to the packages and apps question. |
| `--identity` | Yes to the git identity and config question. |
| `--yes` | Yes to the teeup removal, and no to every optional question without a flag. |

For example, `teeup uninstall --yes --packages` removes teeup and its packages. It keeps your git identity.
