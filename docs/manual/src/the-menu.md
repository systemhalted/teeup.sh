# The menu

`teeup menu` opens a list of teeup actions in sections. When you select a section and then an action, the menu runs the applicable teeup command.

```sh
teeup menu
```

<!-- SCREENSHOT: `teeup menu` at the top level in WezTerm with gum, showing Install, Launch, Style, Check, Setup and Update. -->

## The sections

| Section | What is in it |
|---|---|
| Install | Five submenus: Editors, Apps, AI, Shell and containers, and Language runtimes. |
| Launch | The GUI apps that teeup installed: WezTerm, Emacs, Zed, Firefox Developer Edition, Obsidian, and the others. |
| Style | Select a theme, show the current theme, and list the fonts that teeup knows. |
| Check | The doctor, status, every capability, and a lint of the capability metadata. |
| Setup | Show or edit the answers, and preview or run the retirement of the old teeup and chezmoi wiring. |
| Update | Runs `teeup update`. |

The lists change for each machine. An Install row does not show after that capability is installed, and a Launch row shows only after its capability is installed. Each row uses `teeup has` to decide.

When you select an action, the menu runs it and closes, so run `teeup menu` again for the next action.

## Moving around

teeup draws the menu with the best picker that it finds. It uses [gum](https://github.com/charmbracelet/gum), which the teeup runtime installs, then fzf, then a plain numbered list. The numbered list works anywhere, also over ssh and inside a script.

| Picker | Choose | Go back one level |
|---|---|---|
| gum | Arrow keys, then Return | Escape |
| fzf | Type to filter, then Return | Escape |
| Numbered list | Type the number or the exact label, then Return | An empty line or `q` |

Every submenu ends with a `..` row, which goes back one level. If you go back from the top level, the menu closes. If you type a number that is out of range, the numbered list asks again and does not close.

<!-- SCREENSHOT: The Install submenu in gum, showing Editors, Apps, AI, Shell and containers, Language runtimes and the ".." row. -->

<!-- SCREENSHOT: The same Install submenu drawn by the numbered-list fallback (run: TEEUP_MENU_PICKER=plain teeup menu install), showing the "Choice (empty or q to go back):" prompt. -->

To force one picker, set `TEEUP_MENU_PICKER` to `gum`, `fzf` or `plain`. The default value is `auto`.

```sh
TEEUP_MENU_PICKER=plain teeup menu
```

## Opening directly

Every row has a dotted id, for example `install`, `install.editors` or `style.theme`. Give a dotted id to `teeup menu` to open a submenu directly, or to run an action without the menu:

| Command | What happens |
|---|---|
| `teeup menu install` | Opens at the Install section. |
| `teeup menu install.editors` | Opens at the list of editors. |
| `teeup menu style.theme` | Runs `teeup theme set`, which shows the theme picker. |
| `teeup menu check.doctor` | Runs `teeup doctor`. |

## Previewing and changing the menu

If you set `DRY_RUN=true`, you can still move through the menu, but an action prints `[DRY-RUN] Would run: <command>` and does not run.

The `share/teeup/menu.json` file in the checkout defines the menu. To add, change, or hide a row, write `~/.config/teeup/menu.json` in the same format. A row in this file with the same id replaces the shipped row. [Hooks and extending](hooks-and-extending.md) gives the format.
