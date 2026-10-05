# Terminal

The terminal of teeup is [WezTerm](https://wezfurlong.org/wezterm/).
Every bootstrapped Mac has this core tier terminal.
WezTerm follows the teeup [theme](themes.md) and [font](fonts.md).
Open WezTerm from the Dock or Spotlight.
You can also run `teeup launch WezTerm`.
If you are in AeroSpace, press `alt-enter` to open WezTerm.

<!-- SCREENSHOT: A WezTerm window with two panes side by side (leader then 3) and the tab bar showing the workspace name and clock on the right. -->

## How the configuration fits together

| File | Owner | What it holds |
|---|---|---|
| `~/.config/wezterm/wezterm.lua` | You | This file loads the layer of teeup. Add settings below the `local config = ...` line. |
| `~/.config/wezterm/local.lua` | You | This file contains machine-specific settings. The file returns a table. All text is a comment at first. |
| `capabilities/wezterm/default/teeup/wezterm.lua` | teeup | This file is the configuration in the checkout. The `teeup update` command changes this file. |

teeup copies the two files in `~/.config/wezterm` one time.
The `local.lua` file understands four entries:

| Entry | Example | Effect |
|---|---|---|
| `font_size` | `font_size = 13.0` | This entry sets the font size. The `teeup install font` command configures the font family. |
| `workspaces` | `{ key = "e", name = "work", cwd = "/Users/you/Work" }` | This entry configures a workspace. Press the leader key and then the `key` to open this workspace. |
| `hyperlink_rules` | A `regex` and `format` pair | This entry configures extra Cmd+Click link patterns. |
| `config` | `config = { check_for_updates = false }` | This entry contains raw WezTerm settings. This configuration overrides the defaults of teeup. |

If you edit one of these two files, press Cmd+Shift+R to reload the configuration.

## Keys

The leader key is Ctrl+Space.
Press this key.
Release the key.
Press the next key within one second.

| Keys | Action |
|---|---|
| Cmd+Shift+P | Open the command palette |
| Cmd+Shift+R | Reload the configuration |
| Cmd+K | Clear the scrollback and the screen |
| Leader 3 / Leader 2 | Split side by side / split top and bottom |
| Leader o, or Leader and an arrow | Move to the next pane, or to the pane in that direction |
| Leader 1 | Zoom or unzoom the current pane |
| Leader 0 | Close the current pane |
| Leader c / Leader k | Open a new tab / close the current tab |
| Leader f / Leader b | Go to the next tab / go to the previous tab |
| Leader w | Name a new workspace and open it |
| Leader s | Select a workspace from a fuzzy list |
| Leader d | Return to the default workspace |
| Leader r | Start resize mode. The arrows resize the pane. Escape or Return stops resize mode. |
| Leader v | Start copy mode |
| Leader q | Start quick select |

The split and pane keys follow Emacs.
Key 2 and key 3 split the pane.
Key 0 closes the pane.
Key 1 zooms the pane.
Key o moves to the next pane.

## The prompt (Starship)

The shell prompt uses Starship.
The prompt shows the directory, git branch, git status, command duration, and a prompt character.

Starship requires a Nerd Font for its symbols.
Read [Fonts](fonts.md) to configure a Nerd Font.

The configuration file is `~/.config/starship.toml`.
teeup copies the configuration file there one time.
The `teeup theme set` command changes the colours of the prompt.

Read the [Prompt](prompt.md) page for more details.

## WezTerm in a virtual machine

In a macOS virtual machine, WezTerm can fail to open a window.
The error message is "failed to create NSOpenGLPixelFormat".
teeup configures WezTerm to use the WebGpu renderer inside a macOS virtual machine.
You can change this setting in `~/.config/wezterm/local.lua`:

```lua
return {
  config = {
    front_end = "OpenGL",
  },
}
```

Raw WezTerm settings go inside `config`.
WezTerm does not read a `front_end` key at the top level of the table.

## Terminal.app

You will use Terminal.app at least one time to run `./bootstrap`.
The shell layer of teeup also operates in Terminal.app.
But teeup does not configure the font of Terminal.app.

The `ls` command uses a Nerd Font to draw file icons.
Until you configure the font of the profile, Terminal.app shows most folder and file icons as boxes.
You must configure this font manually.
Click Settings, Profiles, Text, Font, and select "JetBrainsMono Nerd Font".
Read [Fonts](fonts.md).

MacPorts has no cask.
For this reason, on MacPorts, teeup installs WezTerm from the `wezterm` port.
The application is in the applications folder of MacPorts, not in `/Applications`.
teeup shows the `open -a` command that starts WezTerm.

## Other terminals

teeup also has three other terminal applications as lazy capabilities.
teeup installs these terminals.
But teeup does not apply themes to these terminals.
teeup does not manage the fonts of these terminals.
teeup installs a terminal when you use that terminal for the first time.

| Terminal | How to get it | Capability |
|---|---|---|
| Ghostty | `teeup launch ghostty`, or `teeup install ghostty` | `ghostty` |
| Alacritty | Type `alacritty`, `teeup launch alacritty`, or `teeup install alacritty` | `alacritty` |
| iTerm2 | `teeup launch iterm2`, or `teeup install iterm2` | `iterm2` |
