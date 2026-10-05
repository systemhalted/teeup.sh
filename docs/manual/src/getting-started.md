# Getting started

## What you need

| Requirement | Detail |
|---|---|
| macOS | teeup does not set a minimum version. `./bootstrap` does not run on other systems. |
| Apple Silicon or Intel | Both architectures work. If you use Apple Silicon, teeup also installs Rosetta 2 for Intel-only applications. |
| Your own account | Run `./bootstrap` as your own user. Do not run it as root. The script asks for your password at the start for `sudo`. |
| A package manager | teeup installs Homebrew on macOS 13 and newer. MacPorts is the default package manager on macOS 12 and older. If you use macOS 12 or older, install MacPorts from [macports.org](https://www.macports.org/install.php) first. |
| A network connection | You need a network connection for Homebrew, the packages, and to sign in to GitHub. |

Some applications need a minimum macOS version. AeroSpace and Google Chrome need macOS 13. Cursor needs macOS 12. If your Mac is older, teeup marks these applications as not applicable. Then, teeup continues.

## The first run

Clone teeup into `~/.local/share/teeup`. Run the bootstrap script:

```sh
git clone https://github.com/systemhalted/teeup.sh ~/.local/share/teeup
cd ~/.local/share/teeup
./bootstrap --dry-run    # optional: print every command without running it
./bootstrap
```

If macOS offers to install the Command Line Tools when you run `git`, accept the prompt. Then, run the `git clone` command again. teeup also needs these tools. If the tools are missing, teeup installs them.

`./bootstrap` accepts three options:

| Option | What it does |
|---|---|
| `--dry-run` | Print every command. Do not run the commands. |
| `--reconfigure` | Ask the setup questions again. The script asks even if the answers exist. |
| `--skip-daily` | Install only the core tier. |

## The questions

The first prompt asks which package manager to use. The prompt occurs after the installation of the Command Line Tools. teeup offers the package manager that it finds first. Then, teeup installs the teeup runtime. After the installation, teeup asks the remaining questions:

| Question | Default | Saved as |
|---|---|---|
| Package manager | Homebrew on macOS 13 and newer. MacPorts on macOS 12 and older. | `TEEUP_PACKAGE_MANAGER` |
| Your full name | The name of your macOS account. | `TEEUP_NAME` |
| Personal email (your git identity) | None. | `TEEUP_EMAIL` |
| Theme | The first theme in the list. | `TEEUP_THEME` |
| Install the daily set too (Emacs)? | Yes. | `TEEUP_DAILY` |
| Emacs flavor: `starter`, `doom`, `spacemacs` or `none` | `starter` | `TEEUP_EMACS_FLAVOR` |

If you answer yes to the daily set, the Emacs question shows. If you enter an empty name or an invalid email, teeup asks the question again. You have three attempts. If you pin a package manager, theme, or Emacs flavor in your machine file, teeup does not ask the question. See [Answers and machines](answers-and-machines.md). teeup reports the pinned status and continues.

teeup saves the answers to `~/.config/teeup/answers`. A second `./bootstrap` run uses the answers again. The script does not ask the questions. If you want to change the answers, run `./bootstrap --reconfigure` or use `teeup config`.

<!-- SCREENSHOT: The bootstrap wizard in Terminal.app with gum, showing the "Install the daily set too (Emacs)?" confirmation. -->

## What it installs

teeup installs the core tier first. It installs the Xcode Command Line Tools, the package manager, the teeup runtime, `~/Work`, zsh, and Starship. Then, it installs the command-line tools, Keychain secrets, git, SSH, the GitHub CLI, mise, and WezTerm. Next, it installs the Nerd Font, AeroSpace, the Caps Lock mapping, macOS preferences, and the theme. If you answer yes, teeup installs the daily tier: Emacs. The [Tiers](tiers.md) document explains the differences.

A few steps stop and wait for your input:

- The step to change your login shell to `/bin/zsh` asks for your password.
- `ssh-keygen` asks for a passphrase for the new key. macOS saves the key in your Keychain.
- The GitHub CLI opens your browser. You sign in, and the CLI uploads the key.

If a core step fails, teeup stops the run. teeup shows the name of the failed step. If a daily step fails, teeup prints a warning. Then, the run continues. If you want to install a failed daily step later, run `teeup install <name>`. teeup writes all logs to `~/.local/state/teeup/logs/bootstrap.log`.

<!-- SCREENSHOT: The end of a real ./bootstrap run, showing "Bootstrap finished in ..." and the "Open a new terminal" hint. -->

## After the first run

The last lines of output tell you the next steps:

```text
Open a new terminal (the zsh capability puts ~/.local/bin on PATH) and try: teeup status
```

The shell where you ran `./bootstrap` started before teeup existed. This shell cannot find the `teeup` command yet. Open a new terminal. If you want to use the old terminal, run the command by its full path: `~/.local/bin/teeup status`.

It is safe to run `./bootstrap` again later. Each step performs a check before it runs. A second run completes unfinished steps.
