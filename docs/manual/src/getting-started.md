# Getting started

## What you need

| Requirement | Detail |
|---|---|
| macOS | teeup does not set a minimum version. `./bootstrap` refuses to run on other systems. |
| Apple Silicon or Intel | Both architectures work. If you use Apple Silicon, teeup also installs Rosetta 2 for Intel-only applications. |
| Your own account | Run `./bootstrap` as your own user, not as root. At the start, the script asks for your password for `sudo`. |
| A package manager | teeup installs Homebrew on macOS 13 and newer. MacPorts is the default on macOS 12 and older, and you must install it first from [macports.org](https://www.macports.org/install.php). |
| A network connection | You need a network connection for Homebrew, for the packages, and to sign in to GitHub. |

Some applications need a minimum macOS version: AeroSpace and Google Chrome need macOS 13, and Cursor needs macOS 12. On an older Mac, teeup marks these applications as not applicable and continues.

## The first run

Run the installer in Terminal. Use `curl` or `wget`:

```sh
curl -fsSL https://teeup.systemhalted.in/install.sh | bash
wget -qO- https://teeup.systemhalted.in/install.sh | bash
```

The installer does three things:

1. If the Xcode Command Line Tools are missing, it installs them with `softwareupdate`. It asks for your password for `sudo`. If `softwareupdate` does not find the tools, Apple's installer opens, and the script waits until you complete it.
2. It clones teeup into `~/.local/share/teeup` and checks out the newest release.
3. It runs `./bootstrap` in the checkout.

The installer stops if the Mac does not run macOS, or if you run it as root. If `~/.local/share/teeup` is a teeup checkout already, the installer runs its `./bootstrap` again. If the directory exists but is not a git checkout, the installer stops and changes nothing.

To give options to `./bootstrap`, put them after `bash -s --`:

```sh
curl -fsSL https://teeup.systemhalted.in/install.sh | bash -s -- --skip-daily
```

With `--dry-run`, the installer shows the Command Line Tools step and the clone, but does not do them. Then it stops, because the dry run of `./bootstrap` needs the checkout.

To read the installer before it runs, download it first:

```sh
curl -fsSLo install.sh https://teeup.systemhalted.in/install.sh
less install.sh
bash install.sh
```

You can also clone teeup by hand and run the bootstrap script:

```sh
git clone https://github.com/systemhalted/teeup.sh ~/.local/share/teeup
cd ~/.local/share/teeup
./bootstrap --dry-run    # optional: print every command without running it
./bootstrap
```

If macOS offers to install the Command Line Tools when you run `git`, accept the prompt. Then run the `git clone` command again. teeup also needs these tools, and installs them if they are missing.

`./bootstrap` accepts three options:

| Option | What it does |
|---|---|
| `--dry-run` | Print every command, but do not run it. |
| `--reconfigure` | Ask the setup questions again, even if the answers exist. |
| `--skip-daily` | Install only the core tier on this run. |

## The questions

After teeup installs the Command Line Tools, the first prompt asks which package manager to use, and teeup offers the one that it finds first. teeup then installs its runtime and asks the remaining questions:

| Question | Default | Saved as |
|---|---|---|
| Package manager | Homebrew on macOS 13 and newer. MacPorts on macOS 12 and older. | `TEEUP_PACKAGE_MANAGER` |
| Your full name | The name of your macOS account. | `TEEUP_NAME` |
| Personal email (your git identity) | None. | `TEEUP_EMAIL` |
| Theme | The first theme in the list. | `TEEUP_THEME` |
| Install the daily set too (Emacs)? | Yes. | `TEEUP_DAILY` |
| Emacs flavor: `starter`, `doom`, `spacemacs` or `none` | `starter` | `TEEUP_EMACS_FLAVOR` |
| Default editor | `emacsclient -c` with the daily set and an Emacs flavor. `nvim` if not. | `TEEUP_EDITOR` |
| Terminal editor | `emacsclient -t` with the daily set and an Emacs flavor. `nvim` if not. | `TEEUP_TERMINAL_EDITOR` |

teeup asks the Emacs question only if you answer yes to the daily set. If you enter an empty name or an invalid email, teeup asks the question again, up to three attempts in total. If your machine file pins a package manager, theme, Emacs flavor, or editor, teeup does not ask that question and shows the pinned value. See [Answers and machines](answers-and-machines.md).

teeup saves the answers to `~/.config/teeup/answers`, and a second `./bootstrap` run uses them again without the questions. To change the answers, run `./bootstrap --reconfigure` or use `teeup config`.

<!-- SCREENSHOT: The bootstrap wizard in Terminal.app with gum, showing the "Install the daily set too (Emacs)?" confirmation. -->

## What it installs

teeup installs the core tier first, in this order:

1. The Xcode Command Line Tools
2. The package manager
3. The teeup runtime
4. `~/Work`
5. zsh
6. Starship
7. The command-line tools
8. Keychain secrets
9. git
10. SSH
11. The GitHub CLI
12. mise
13. WezTerm
14. The Nerd Font
15. AeroSpace
16. The Caps Lock mapping
17. macOS preferences
18. The theme

After the core tier, if you answered yes, teeup installs the daily tier: Emacs. [Tiers](tiers.md) explains the difference.

A few steps stop and wait for your input:

- The step to change your login shell to `/bin/zsh` asks for your password.
- `ssh-keygen` asks for a passphrase for the new key, and macOS saves the passphrase in your Keychain.
- The GitHub CLI opens your browser for you to sign in, and then uploads the key.

If a core step fails, teeup stops the run and shows the name of the failed step. If a daily step fails, teeup prints a warning and the run continues. To install a failed daily step later, run `teeup install <name>`. teeup writes a log of the full run to `~/.local/state/teeup/logs/bootstrap.log`.

<!-- SCREENSHOT: The end of a real ./bootstrap run, showing "Bootstrap finished in ..." and the "Open a new terminal" hint. -->

## After the first run

The last lines of output tell you the next steps:

```text
Open a new terminal (the zsh capability puts ~/.local/bin on PATH) and try: teeup status
```

The shell where you ran `./bootstrap` started before teeup existed, so it cannot find `teeup` yet. Open a new terminal. To use the old terminal, run the command by its full path: `~/.local/bin/teeup status`.

You can run `./bootstrap` again later without risk, because each step checks the current state before it acts. A second run repairs unfinished steps.
