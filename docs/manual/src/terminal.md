# Terminal

The teeup terminal is [WezTerm](https://wezfurlong.org/wezterm/).
It is in the core tier, so every bootstrapped Mac has it, and it follows the teeup [theme](themes.md) and [font](fonts.md).
Open it from the Dock or Spotlight, or run `teeup launch WezTerm`.
In AeroSpace, press `alt-enter` to open it.

<!-- SCREENSHOT: A WezTerm window with two panes side by side (leader then 3) and the tab bar showing the workspace name and clock on the right. -->

## How the configuration fits together

| File | Owner | What it holds |
|---|---|---|
| `~/.config/wezterm/wezterm.lua` | You | Loads the teeup layer. Add settings below its `local config = ...` line. |
| `~/.config/wezterm/local.lua` | You | Machine-specific settings, which the file returns as a table. All of it is a comment at first. |
| `capabilities/wezterm/default/teeup/wezterm.lua` | teeup | The configuration in the checkout. `teeup update` changes it. |

teeup copies the two files in `~/.config/wezterm` one time.
`local.lua` understands four entries:

| Entry | Example | Effect |
|---|---|---|
| `font_size` | `font_size = 13.0` | Sets the font size. `teeup install font` configures the font family. |
| `workspaces` | `{ key = "e", name = "work", cwd = "/Users/you/Work" }` | Configures a workspace that opens when you press the leader key and then the value of `key`, for example `e`. |
| `hyperlink_rules` | A `regex` and `format` pair | Configures extra Cmd+Click link patterns. |
| `config` | `config = { check_for_updates = false }` | Raw WezTerm settings, which override the teeup defaults. |

If you edit one of these two files, press Cmd+Shift+R to reload the configuration.

## Keys

The leader key is Ctrl+Space.
Press it and release it, then press the next key within one second.

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
| Leader r | Start resize mode, where the arrows resize the pane. Escape or Return stops it. |
| Leader v | Start copy mode |
| Leader q | Start quick select |

The split and pane keys follow Emacs: 2 and 3 split, 0 closes, 1 zooms, and o moves to the next pane.

## The prompt (Starship)

The shell prompt uses Starship, and shows the directory, git branch, git status, command duration, and a prompt character.

Starship requires a Nerd Font for its symbols.
Read [Fonts](fonts.md) to configure one.

teeup copies the configuration file to `~/.config/starship.toml` one time.
`teeup theme set` changes the colours of the prompt.

Read the [Prompt](prompt.md) page for more details.

## WezTerm in a virtual machine

In a macOS virtual machine, WezTerm can fail to open a window with the error "failed to create NSOpenGLPixelFormat".
For this reason, teeup configures WezTerm to use the WebGpu renderer inside a macOS virtual machine.
You can change this setting in `~/.config/wezterm/local.lua`:

```lua
return {
  config = {
    front_end = "OpenGL",
  },
}
```

Raw WezTerm settings go inside `config`, because WezTerm does not read a `front_end` key at the top level of the table.

## Terminal.app

You will use Terminal.app at least one time, to run `./bootstrap`.
The teeup shell layer also works in Terminal.app, but teeup does not configure its font.

`ls` uses a Nerd Font to draw file icons, so Terminal.app shows most icons as boxes until you configure the font of the profile.
To configure it, click Settings, Profiles, Text, Font, and select "JetBrainsMono Nerd Font".
Read [Fonts](fonts.md).

MacPorts has no cask, so on MacPorts teeup installs WezTerm from the `wezterm` port.
The application is then in the MacPorts applications folder, not in `/Applications`, and teeup shows the `open -a` command that starts it.

## Other terminals

teeup also has three other terminal applications as lazy capabilities.
teeup installs them, but it does not apply themes to them or manage their fonts.
Each one installs the first time you use it.

| Terminal | How to get it | Capability |
|---|---|---|
| Ghostty | `teeup launch ghostty`, or `teeup install ghostty` | `ghostty` |
| Alacritty | Type `alacritty`, `teeup launch alacritty`, or `teeup install alacritty` | `alacritty` |
| iTerm2 | `teeup launch iterm2`, or `teeup install iterm2` | `iterm2` |
