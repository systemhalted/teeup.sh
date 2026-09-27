# Terminal

teeup's terminal is [WezTerm](https://wezfurlong.org/wezterm/). It is in the core tier, so every bootstrapped Mac has it, and it follows the teeup [theme](themes.md) and [font](fonts.md). Open it from the Dock or Spotlight, with `teeup launch WezTerm`, or from AeroSpace with `alt-enter`.

<!-- SCREENSHOT: A WezTerm window with two panes side by side (leader then 3) and the tab bar showing the workspace name and clock on the right. -->

## How the configuration fits together

| File | Owner | What it holds |
|---|---|---|
| `~/.config/wezterm/wezterm.lua` | You | A thin file that loads teeup's layer. Add settings below its `local config = ...` line. |
| `~/.config/wezterm/local.lua` | You | Machine-specific settings, returned as a table. Everything in it is commented out at first. |
| `capabilities/wezterm/default/teeup/wezterm.lua` | teeup | The real configuration, in the checkout. `teeup update` improves it. |

teeup copies the two files in `~/.config/wezterm` once and never touches them again. `local.lua` understands four entries:

| Entry | Example | Effect |
|---|---|---|
| `font_size` | `font_size = 13.0` | The font size. The family comes from `teeup install font`. |
| `workspaces` | `{ key = "e", name = "work", cwd = "/Users/you/Work" }` | A workspace one leader key away. |
| `hyperlink_rules` | a `regex` and `format` pair | Extra Cmd+Click link patterns. |
| `config` | `config = { check_for_updates = false }` | Any raw WezTerm setting. It wins over every teeup default. |

After editing either file, press Cmd+Shift+R to reload.

## Keys

The leader key is Ctrl+Space. Press it, let go, then press the next key within a second.

| Keys | Action |
|---|---|
| Cmd+Shift+P | Command palette |
| Cmd+Shift+R | Reload the configuration |
| Cmd+K | Clear the scrollback and the screen |
| Leader 3 / Leader 2 | Split side by side / split top and bottom |
| Leader o, or Leader and an arrow | Move to the next pane, or the pane in that direction |
| Leader 1 | Zoom the current pane, and back |
| Leader 0 | Close the current pane |
| Leader c / Leader k | New tab / close tab |
| Leader f / Leader b | Next tab / previous tab |
| Leader w | Name a new workspace and switch to it |
| Leader s | Pick a workspace from a fuzzy list |
| Leader d | Back to the default workspace |
| Leader r | Resize mode: arrows resize, Escape or Return leaves |
| Leader v | Copy mode |
| Leader q | Quick select |

The split and pane keys follow Emacs: 2 and 3 split, 0 closes, 1 zooms, and o moves on.

## WezTerm in a virtual machine

In a macOS virtual machine, WezTerm can fail to open a window with "failed to create NSOpenGLPixelFormat". Switch it to the WebGPU front end in `~/.config/wezterm/local.lua`:

```lua
return {
  config = {
    front_end = "WebGpu",
  },
}
```

Raw WezTerm settings go inside `config`; a `front_end` key at the top level of the table is not read.

## Terminal.app

You will use Terminal.app at least once, to run `./bootstrap`. teeup's shell layer works there too, but teeup does not set Terminal.app's font. `ls` draws file icons with a Nerd Font, so in Terminal.app most folder and file icons show as boxes until you set the profile's font yourself: Settings, Profiles, Text, Font, then "JetBrainsMono Nerd Font". See [Fonts](fonts.md).

On MacPorts there is no cask, so teeup installs WezTerm from the `wezterm` port. The app then lives in MacPorts' applications folder rather than `/Applications`, and teeup prints the `open -a` line that starts it.
