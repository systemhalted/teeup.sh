# Answers and machines

`teeup` reads the configuration settings from two files. The `teeup` wizard writes the answers file. You write an optional machine file for settings that belong to one Mac. `teeup` reads the machine file second. The machine file overrides the answers file.

| File | Written by | Holds |
|---|---|---|
| `~/.config/teeup/answers` | The wizard and `teeup config` | Your name and email, the theme, the daily set, the Emacs flavor, the package manager |
| `~/.config/teeup/machines/<hostname>.conf` | You | The pinned settings for this Mac and the work identity configuration |

The `<hostname>` is the short name that `hostname -s` prints.

## The answers

The answers file is a list of `KEY="value"` lines. Only you can read the answers file.

| Key | Meaning | Applied by |
|---|---|---|
| `TEEUP_NAME`, `TEEUP_EMAIL` | Your git identity | `teeup configure git` |
| `TEEUP_THEME` | The theme | `teeup theme set <name>` |
| `TEEUP_DAILY` | `yes` or `no`: installs the daily set | `./bootstrap` |
| `TEEUP_EMACS_FLAVOR` | `starter`, `doom`, `spacemacs` or `none` | `teeup configure emacs` and `teeup update` |
| `TEEUP_PACKAGE_MANAGER` | `homebrew` or `macports` | `./bootstrap` the first time |

## teeup config

| Command | What it does |
|---|---|
| `teeup config get` | Shows the file paths and every answer. It shows `[pinned by <host>.conf]` next to an overridden answer. |
| `teeup config get TEEUP_THEME` | Shows the value that `teeup` reads. This includes the pin. |
| `teeup config set TEEUP_NAME Ada Lovelace` | Changes one answer. The command uses the rest of the line as the value. You do not need quotes. |
| `teeup config edit` | Opens the answers file in your editor. |

When you write an answer, `teeup` does not apply it. After you run `teeup config set` or `teeup config edit`, `teeup` prints the command to apply the change:

```text
teeup config set TEEUP_EMACS_FLAVOR doom
✅ Set TEEUP_EMACS_FLAVOR in /Users/you/.config/teeup/answers
🔹 Run: teeup configure emacs -- that is what reads TEEUP_EMACS_FLAVOR (teeup update now covers it too).
```

The `teeup config edit` command opens `$VISUAL`, then `$EDITOR`, then `vi`. If you install Emacs, the `teeup` shell configures `EDITOR` and `VISUAL` to `emacsclient -t`. When you close the editor, `teeup` checks that every line has the `KEY="value"` format. If a line does not have this format, `teeup` restores the previous file and prints the broken line. Because `teeup` reads the answers file at the start of every command, a broken line breaks `teeup config edit`.

The `teeup config set` command does not accept two keys:

- `TEEUP_PACKAGE_MANAGER` after you install a package manager. `teeup` does not support a package manager change after a Mac installation.
- `TEEUP_WORK_EMAIL` and the other `TEEUP_WORK_*` keys. `teeup` reads these keys only from the machine file (see [Identity](identity.md)).

## The machine file

If one Mac needs different settings from the other Macs, create the machine file. Start from the sample file in the checkout:

```sh
mkdir -p ~/.config/teeup/machines
cp ~/.local/share/teeup/machines/example.conf.sample ~/.config/teeup/machines/$(hostname -s).conf
```

Every setting in the machine file is optional:

| Key | Example | Effect |
|---|---|---|
| `TEEUP_SKIP` | `TEEUP_SKIP="aerospace"` | The capabilities that this Mac never installs. Separate the values with spaces. |
| `TEEUP_PACKAGE_MANAGER` | `TEEUP_PACKAGE_MANAGER="macports"` | Pins the package manager. |
| `TEEUP_THEME` | `TEEUP_THEME="catppuccin"` | Pins the theme. |
| `TEEUP_EMACS_FLAVOR` | `TEEUP_EMACS_FLAVOR="doom"` | Pins the Emacs flavor. |
| `TEEUP_WORK_EMAIL` and related keys | see [Identity](identity.md) | A second, work SSH key. |
| `TEEUP_PERSONAL_SSH_HOST` and `TEEUP_PERSONAL_GH_ACCOUNT` | see [Identity](identity.md) | The SSH host alias and GitHub login for the personal identity. |

A pinned key overrides the answers file. The wizard does not ask about a pinned theme, flavor, or package manager. If you set a different value, `teeup config set` warns you that the pin overrides the value. To change the value, change the machine file.

`teeup` checks the machine file. An invalid shell file or a malformed `TEEUP_WORK_EMAIL` stops every `teeup` command. The command also prints an error.

## Your file or the checkout's

`teeup` searches for the machine file in two locations. `teeup` uses the first file it finds:

1. `~/.config/teeup/machines/<hostname>.conf` is your personal file. `git pull` does not change this file.
2. `machines/<hostname>.conf` in the `teeup` checkout is for users who keep a fork of `teeup`.

`teeup` does not merge the two files. If both files exist, `teeup` tells you which file it uses.
