# Answers and machines

teeup reads its settings from two files: the answers the wizard wrote, and an optional machine file for settings that belong to one Mac. The machine file is read second, so it wins.

| File | Written by | Holds |
|---|---|---|
| `~/.config/teeup/answers` | The wizard and `teeup config` | Your name and email, the theme, the daily set, the Emacs flavor, the package manager |
| `~/.config/teeup/machines/<hostname>.conf` | You | Settings pinned for this Mac, and the only place a work identity is configured |

`<hostname>` is the short name `hostname -s` prints.

## The answers

The answers file is a list of `KEY="value"` lines, readable only by you.

| Key | Meaning | Applied by |
|---|---|---|
| `TEEUP_NAME`, `TEEUP_EMAIL` | Your git identity | `teeup configure git` |
| `TEEUP_THEME` | The theme | `teeup theme set <name>` |
| `TEEUP_DAILY` | `yes` or `no`: install the daily set | `./bootstrap` |
| `TEEUP_EMACS_FLAVOR` | `starter`, `doom`, `spacemacs` or `none` | `teeup configure emacs`, and `teeup update` |
| `TEEUP_PACKAGE_MANAGER` | `homebrew` or `macports` | `./bootstrap`, the first time |

## teeup config

| Command | What it does |
|---|---|
| `teeup config get` | The file paths, then every answer, with `[pinned by <host>.conf]` next to any the machine file overrides |
| `teeup config get TEEUP_THEME` | The value the rest of teeup sees, pin included |
| `teeup config set TEEUP_NAME Ada Lovelace` | Changes one answer. The rest of the line is the value, so it needs no quotes. |
| `teeup config edit` | Opens the answers file in your editor |

Writing an answer does not apply it. After `teeup config set`, and after every answer an edit changed, teeup names the command that does:

```text
teeup config set TEEUP_EMACS_FLAVOR doom
✅ Set TEEUP_EMACS_FLAVOR in /Users/you/.config/teeup/answers
🔹 Run: teeup configure emacs -- that is what reads TEEUP_EMACS_FLAVOR (teeup update now covers it too).
```

`teeup config edit` opens `$VISUAL`, then `$EDITOR`, then `vi`. teeup's shell sets `EDITOR` to `emacsclient -t` when Emacs is installed, and `VISUAL` to the same unless you set it yourself, so the file usually opens in an Emacs frame in your terminal. When you close the editor, teeup checks every line still reads `KEY="value"`. If one does not, it puts your previous file back and says which line was wrong: teeup reads this file at the start of every command, so a broken line would break the command that could fix it.

`teeup config set` refuses two keys:

- `TEEUP_PACKAGE_MANAGER` once a package manager is installed. Switching it underneath an installed Mac is not safe.
- `TEEUP_WORK_EMAIL` and the other `TEEUP_WORK_*` keys. They are read only from the machine file (see [Identity](identity.md)).

## The machine file

Create it when one Mac needs something different from the others. Start from the sample in the checkout:

```sh
mkdir -p ~/.config/teeup/machines
cp ~/.local/share/teeup/machines/example.conf.sample ~/.config/teeup/machines/$(hostname -s).conf
```

Everything in it is optional:

| Key | Example | Effect |
|---|---|---|
| `TEEUP_SKIP` | `TEEUP_SKIP="aerospace"` | Capabilities this Mac never installs. Space-separated. |
| `TEEUP_PACKAGE_MANAGER` | `TEEUP_PACKAGE_MANAGER="macports"` | Pins the package manager. |
| `TEEUP_THEME` | `TEEUP_THEME="catppuccin"` | Pins the theme. |
| `TEEUP_EMACS_FLAVOR` | `TEEUP_EMACS_FLAVOR="doom"` | Pins the Emacs flavor. |
| `TEEUP_WORK_EMAIL` and friends | see [Identity](identity.md) | A second, work SSH key. |

A pinned key wins over the answers file. The wizard does not ask about a pinned theme, flavor or package manager, and `teeup config set` warns that the pin wins when you set a different value. Change the machine file instead.

teeup checks the machine file before trusting it. A file that is not valid shell stops every teeup command with a message naming it, and a `TEEUP_WORK_EMAIL` that is not an email address does the same.

## Your file or the checkout's

teeup looks for the machine file in two places and uses the first it finds:

1. `~/.config/teeup/machines/<hostname>.conf`, your own. `git pull` never touches it.
2. `machines/<hostname>.conf` in the teeup checkout, for anyone who keeps a fork of teeup.

The two are never merged. If both exist, teeup says which one it is using.
