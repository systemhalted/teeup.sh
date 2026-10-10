# Answers and machines

teeup reads its settings from two files: the answers file that the wizard writes, and an optional machine file for one Mac. teeup reads the machine file second, so it overrides the answers file.

| File | Written by | Holds |
|---|---|---|
| `~/.config/teeup/answers` | The wizard, `teeup config` and `teeup update --main` or `--release` | Your name and email, the theme, the daily set, the Emacs flavor, the editors, the package manager, the update channel |
| `~/.config/teeup/machines/<hostname>.conf` | You | Settings pinned for this Mac, and the only file where you configure a work identity |

`<hostname>` is the short name that `hostname -s` prints.

## The answers

The answers file is a list of `KEY="value"` lines that only you can read.

| Key | Meaning | Applied by |
|---|---|---|
| `TEEUP_NAME`, `TEEUP_EMAIL` | Your git identity | `teeup configure git` |
| `TEEUP_THEME` | The theme | `teeup theme set <name>` |
| `TEEUP_DAILY` | `yes` or `no`: installs the daily set | `./bootstrap` |
| `TEEUP_EMACS_FLAVOR` | `starter`, `doom`, `spacemacs` or `none` | `teeup configure emacs` and `teeup update` |
| `TEEUP_EDITOR` | The editor for a local session, for example `emacsclient -c` or `zed --wait`. See [Editors](shell-tools.md#editors). | A new terminal |
| `TEEUP_TERMINAL_EDITOR` | The editor over SSH, and when `TEEUP_EDITOR` has no value, for example `emacsclient -t` or `nvim` | A new terminal |
| `TEEUP_PACKAGE_MANAGER` | `homebrew` or `macports` | `./bootstrap` the first time |
| `TEEUP_UPDATE_CHANNEL` | `release` or `main`: what `teeup update` follows. No value means `release`. See [Release or main](updates.md#release-or-main). | `teeup update` |

## teeup config

| Command | What it does |
|---|---|
| `teeup config get` | Shows the file paths and every answer, with `[pinned by <host>.conf]` next to each answer that the machine file overrides. |
| `teeup config get TEEUP_THEME` | Shows the value that teeup reads, with the pin included. |
| `teeup config set TEEUP_NAME Ada Lovelace` | Changes one answer. The rest of the line is the value, so you do not need quotes. |
| `teeup config edit` | Opens the answers file in your editor. |

teeup does not apply an answer when you write it. After `teeup config set` or `teeup config edit`, teeup prints the command that applies the change:

```text
teeup config set TEEUP_EMACS_FLAVOR doom
✅ Set TEEUP_EMACS_FLAVOR in /Users/you/.config/teeup/answers
🔹 Run: teeup configure emacs -- that is what reads TEEUP_EMACS_FLAVOR (teeup update now covers it too).
```

`teeup config edit` opens `$VISUAL`, then `$EDITOR`, then `vi`. The teeup shell sets `EDITOR` and `VISUAL` from your editor answers (see [Editors](shell-tools.md#editors)). When you close the editor, teeup checks that every line has the `KEY="value"` format. If a line does not, teeup restores the previous file and prints the broken line. Because teeup reads the answers file at the start of every command, a broken line breaks `teeup config edit`.

`teeup config set` does not accept two keys:

- `TEEUP_PACKAGE_MANAGER`, after teeup installs a package manager, because teeup does not support a change of package manager after that.
- `TEEUP_WORK_EMAIL` and the other `TEEUP_WORK_*` keys, because teeup reads them only from the machine file (see [Identity](identity.md)).

## The machine file

If one Mac needs different settings from your other Macs, create the machine file from the sample in the checkout:

```sh
mkdir -p ~/.config/teeup/machines
cp ~/.local/share/teeup/machines/example.conf.sample ~/.config/teeup/machines/$(hostname -s).conf
```

Every setting in the machine file is optional:

| Key | Example | Effect |
|---|---|---|
| `TEEUP_SKIP` | `TEEUP_SKIP="aerospace"` | The capabilities that this Mac never installs, separated by spaces. |
| `TEEUP_PACKAGE_MANAGER` | `TEEUP_PACKAGE_MANAGER="macports"` | Pins the package manager. |
| `TEEUP_THEME` | `TEEUP_THEME="catppuccin"` | Pins the theme. |
| `TEEUP_EMACS_FLAVOR` | `TEEUP_EMACS_FLAVOR="doom"` | Pins the Emacs flavor. |
| `TEEUP_EDITOR`, `TEEUP_TERMINAL_EDITOR` | `TEEUP_EDITOR="zed --wait"` | Pins the editors. |
| `TEEUP_WORK_EMAIL` and related keys | see [Identity](identity.md) | A second, work SSH key. |
| `TEEUP_PERSONAL_SSH_HOST` and `TEEUP_PERSONAL_GH_ACCOUNT` | see [Identity](identity.md) | The SSH host alias and GitHub login for the personal identity. |

A pinned key overrides the answers file. The wizard does not ask about a pinned theme, flavor, editor, or package manager. If you set a different value with `teeup config set`, it warns you that the pin overrides it. To change a pinned value, edit the machine file.

teeup checks the machine file. An invalid shell file or a malformed `TEEUP_WORK_EMAIL` stops every teeup command with an error.

## Your file or the checkout's

teeup searches for the machine file in two locations and uses the first file it finds:

1. `~/.config/teeup/machines/<hostname>.conf` is your personal file, and `teeup update` does not change it.
2. `machines/<hostname>.conf` in the teeup checkout is for users who keep a fork of teeup.

teeup does not merge the two files. If both exist, it tells you which one it uses.
