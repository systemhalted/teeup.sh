# Getting started

## What you need

| Requirement | Detail |
|---|---|
| macOS | teeup sets no minimum version. `./bootstrap` refuses to run on any other system. |
| Apple Silicon or Intel | Both work. On Apple Silicon, teeup also installs Rosetta 2 for Intel-only apps. |
| Your own account | Run it as yourself, not as root. It asks for your password at the start, for `sudo`. |
| A package manager | Homebrew on macOS 13 and newer, which teeup installs for you. MacPorts is the default on macOS 12 and older; install it yourself first from [macports.org](https://www.macports.org/install.php). |
| A network connection | For Homebrew, the packages, and signing in to GitHub. |

Some apps set their own floor: AeroSpace and Google Chrome need macOS 13, and Cursor needs macOS 12. On an older Mac teeup marks them "not applicable" and carries on.

## The first run

Clone teeup into `~/.local/share/teeup` and run the bootstrap script:

```sh
git clone https://github.com/systemhalted/teeup.sh ~/.local/share/teeup
cd ~/.local/share/teeup
./bootstrap --dry-run    # optional: print every command without running it
./bootstrap
```

If macOS offers to install the Command Line Tools when you run `git`, accept and run the clone again. teeup needs those tools too, and installs them itself if they are missing.

`./bootstrap` takes three options:

| Option | What it does |
|---|---|
| `--dry-run` | Print every command instead of running it. |
| `--reconfigure` | Ask the setup questions again, even if answers exist. |
| `--skip-daily` | Install only the core tier this time. |

## The questions

The first prompt asks which package manager to use. This happens after installing the Command Line Tools. teeup offers the one it detected first. After that it installs its own runtime, then asks the rest:

| Question | Default | Saved as |
|---|---|---|
| Package manager | Homebrew on macOS 13 and newer, MacPorts before | `TEEUP_PACKAGE_MANAGER` |
| Your full name | The name on your macOS account | `TEEUP_NAME` |
| Personal email (your git identity) | none | `TEEUP_EMAIL` |
| Theme | the first theme listed | `TEEUP_THEME` |
| Install the daily set too (Emacs)? | yes | `TEEUP_DAILY` |
| Emacs flavor: `starter`, `doom`, `spacemacs` or `none` | `starter` | `TEEUP_EMACS_FLAVOR` |

The Emacs question only appears when you said yes to the daily set. An empty name or an invalid email is asked again, three tries in all. A package manager, theme or Emacs flavor pinned in your machine file (see [Answers and machines](answers-and-machines.md)) is not asked at all; teeup says it is pinned and moves on.

The answers go to `~/.config/teeup/answers`. A second `./bootstrap` reuses them without asking. To change them, run `./bootstrap --reconfigure` or use `teeup config`.

<!-- SCREENSHOT: The bootstrap wizard in Terminal.app with gum, showing the "Install the daily set too (Emacs)?" confirmation. -->

## What it installs

The core tier comes first, in this order: the Xcode Command Line Tools, the package manager, teeup's runtime, `~/Work`, zsh, Starship, the command-line tools, Keychain secrets, git, SSH, the GitHub CLI, mise, WezTerm, the Nerd Font, AeroSpace, the Caps Lock mapping, macOS preferences, and the theme. Then, if you said yes, the daily tier: Emacs. [Tiers](tiers.md) explains the difference.

A few steps stop and wait for you:

- changing your login shell to `/bin/zsh` asks for your password;
- `ssh-keygen` asks for a passphrase for the new key, which macOS then keeps in your Keychain;
- the GitHub CLI opens your browser to sign in, then uploads the key.

A core step that fails stops the run with the name of what failed. A daily step that fails prints a warning and the run continues; install it later with `teeup install <name>`. Everything is logged to `~/.local/state/teeup/logs/bootstrap.log`.

<!-- SCREENSHOT: The end of a real ./bootstrap run, showing "Bootstrap finished in ..." and the "Open a new terminal" hint. -->

## After the first run

The last lines tell you what to do next:

```text
Open a new terminal (the zsh capability puts ~/.local/bin on PATH) and try: teeup status
```

The shell you ran `./bootstrap` in started before teeup existed, so it cannot find `teeup` yet. Open a new terminal, or call it by its full path, `~/.local/bin/teeup status`, in the old one.

Running `./bootstrap` again later is safe. Each step checks before it acts; a second run repairs unfinished steps.
