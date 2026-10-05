# The menu

The `teeup menu` command opens a list of teeup actions. The actions are in sections. Select a section. Select an action. The menu runs the applicable `teeup` command.

```sh
teeup menu
```

<!-- SCREENSHOT: `teeup menu` at the top level in WezTerm with gum, showing Install, Launch, Style, Check, Setup and Update. -->

## The sections

| Section | What is in it |
|---|---|
| Install | This section contains five submenus: Editors, Apps, AI, Shell and containers, and Language runtimes. |
| Launch | This section contains the GUI apps that teeup installed. These apps include WezTerm, Emacs, Zed, Firefox Developer Edition, Obsidian, and the other apps. |
| Style | This section contains commands to select a theme, show the current theme, and list the fonts that teeup knows. |
| Check | This section contains the doctor, status, every capability, and a lint of the capability metadata. |
| Setup | This section contains commands to show or edit the answers. It also contains commands to preview or run the retirement of the old teeup and chezmoi wiring. |
| Update | This section runs `teeup update`. |

The lists change for each machine. An Install row does not show when teeup installs that capability. A Launch row shows only when teeup installs its capability. Each row uses `teeup has` to make a decision.

Select an action to run the action. The menu closes. Run `teeup menu` again to select the next action.

## Moving around

The teeup tool draws the menu with the best picker that it finds. It uses [gum](https://github.com/charmbracelet/gum), which the runtime of teeup installs. If it does not find gum, it uses fzf. If it does not find fzf, it uses a plain numbered list. The numbered list works anywhere. This includes over ssh and inside a script.

| Picker | Choose | Go back one level |
|---|---|---|
| gum | Press the arrow keys, then press Return. | Press Escape. |
| fzf | Type characters to filter, then press Return. | Press Escape. |
| Numbered list | Type the number or the exact label, then press Return. | Type an empty line or `q`. |

Every submenu ends with a `..` row. This row returns the menu one level. If you return from the top level, the menu closes. If you type a number that is out of range, the numbered list asks you to type a number again. The numbered list does not close the menu in this condition.

<!-- SCREENSHOT: The Install submenu in gum, showing Editors, Apps, AI, Shell and containers, Language runtimes and the ".." row. -->

<!-- SCREENSHOT: The same Install submenu drawn by the numbered-list fallback (run: TEEUP_MENU_PICKER=plain teeup menu install), showing the "Choice (empty or q to go back):" prompt. -->

To force one picker, set `TEEUP_MENU_PICKER` to one of these values:
- `gum`
- `fzf`
- `plain`

The default value is `auto`.

```sh
TEEUP_MENU_PICKER=plain teeup menu
```

## Opening directly

Every row has a dotted id. Examples of dotted ids are:
- `install`
- `install.editors`
- `style.theme`

Supply a dotted id to `teeup menu` to directly open a submenu. You can also supply a dotted id to run an action without the menu.

| Command | What happens |
|---|---|
| `teeup menu install` | The menu opens at the Install section. |
| `teeup menu install.editors` | The menu opens at the list of editors. |
| `teeup menu style.theme` | This command runs `teeup theme set`. The `teeup theme set` command shows the theme picker. |
| `teeup menu check.doctor` | This command runs `teeup doctor`. |

## Previewing and changing the menu

If you set `DRY_RUN=true`, you can navigate the menu. An action prints `[DRY-RUN] Would run: <command>` and does not run the command.

The `share/teeup/menu.json` file in the checkout defines the menu. Write `~/.config/teeup/menu.json` in the same format to do these operations:
- Add a row.
- Change a row.
- Hide a row.

A row in this file with the same id replaces the shipped row. The [Hooks and extending](hooks-and-extending.md) file contains information about the format.
