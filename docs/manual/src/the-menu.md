# The menu

`teeup menu` opens a list of teeup actions, grouped into sections. Pick a section, pick an action, and the menu runs the matching `teeup` command.

```sh
teeup menu
```

<!-- SCREENSHOT: `teeup menu` at the top level in WezTerm with gum, showing Install, Launch, Style, Check, Setup and Update. -->

## The sections

| Section | What is in it |
|---|---|
| Install | Five submenus: Editors, Apps, AI, Shell and containers, and Language runtimes. |
| Launch | The GUI apps teeup installed: WezTerm, Emacs, Zed, Firefox Developer Edition, Obsidian and the rest. |
| Style | Pick a theme, show the current theme, and list the fonts teeup knows. |
| Check | Doctor, status, every capability, and a lint of the capability metadata. |
| Setup | Show or edit the answers, and preview or run the retirement of the old teeup and chezmoi wiring. |
| Update | Runs `teeup update`. |

The lists change with the machine. An Install row disappears once that capability is installed, and a Launch row appears only once its capability is installed. Each row asks `teeup has` to decide.

Choosing an action runs it and closes the menu. Run `teeup menu` again for the next one.

## Moving around

teeup draws the menu with the best picker it finds. It uses [gum](https://github.com/charmbracelet/gum), which teeup's runtime installs, then fzf, then a plain numbered list. The numbered list works anywhere, including over ssh and inside a script.

| Picker | Choose | Go back one level |
|---|---|---|
| gum | Arrow keys, then Return | Escape |
| fzf | Type to filter, then Return | Escape |
| Numbered list | Type the number, or the label exactly, then Return | An empty line, or `q` |

Every submenu also ends with a `..` row, which goes back one level. Going back from the top level leaves the menu. In the numbered list, a number that is out of range asks again instead of leaving.

<!-- SCREENSHOT: The Install submenu in gum, showing Editors, Apps, AI, Shell and containers, Language runtimes and the ".." row. -->

<!-- SCREENSHOT: The same Install submenu drawn by the numbered-list fallback (run: TEEUP_MENU_PICKER=plain teeup menu install), showing the "Choice (empty or q to go back):" prompt. -->

To force one picker, set `TEEUP_MENU_PICKER` to `gum`, `fzf` or `plain`. The default is `auto`.

```sh
TEEUP_MENU_PICKER=plain teeup menu
```

## Opening directly

Every row has a dotted id, such as `install`, `install.editors` or `style.theme`. Give one to `teeup menu` to open a submenu directly, or to run an action without the menu:

| Command | What happens |
|---|---|
| `teeup menu install` | Opens at the Install section. |
| `teeup menu install.editors` | Opens at the list of editors. |
| `teeup menu style.theme` | Runs `teeup theme set`, which shows the theme picker. |
| `teeup menu check.doctor` | Runs `teeup doctor`. |

## Previewing and changing the menu

With `DRY_RUN=true`, the menu still lets you walk it, but an action prints `[DRY-RUN] Would run: <command>` instead of running.

The menu is defined in `share/teeup/menu.json` in the checkout. To add rows, change one, or hide one, write `~/.config/teeup/menu.json` in the same format; a row there with the same id replaces the shipped row. [Hooks and extending](hooks-and-extending.md) covers the format.
