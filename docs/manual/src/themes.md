# Themes

teeup has four themes:
* `catppuccin`
* `everforest`
* `gruvbox`
* `tokyo-night`

Every theme has a dark palette and a light palette. When macOS changes the appearance, WezTerm, Zed, VS Code, and Emacs change palettes. When teeup runs or when a new shell starts, Terminal.app, Starship, and bat select the palette that matches the appearance. When you change the appearance of macOS between light and dark, run `teeup theme set --reload`. Then, open a new window.

| Command | What it does |
|---|---|
| `teeup theme set <name>` | Change the theme in all applications. |
| `teeup theme set --reload` | Apply the current theme again. Run this command if you manually change or delete a file. |
| `teeup theme current` | Show the current theme. |
| `teeup theme list` | Show all available themes. |

<!-- SCREENSHOT: The theme picker from \`teeup theme set\` showing the available themes. -->

You can also select a theme from a list with the Theme row in the menu (`teeup menu style.theme`).

## What is themed

A theme applies to these applications:
* WezTerm
* Terminal.app
* Starship
* bat
* Zed
* VS Code
* Neovim
* Emacs (the starter flavor and the Doom flavor)

teeup disables the default template theme of Doom. This lets the teeup theme apply. Your `doom-theme` setting replaces the teeup theme.

When you set a theme, teeup creates a profile in Terminal.app. The name of the profile is `teeup <Theme> <Mode>` (for example, `teeup Tokyo Night Dark`). This new profile becomes the default profile and the startup profile. A new Terminal.app window or a restart uses this new profile. teeup does not change your other profiles. If you remove the Terminal.app integration (`teeup remove terminal-app`), teeup restores your old default profile.

## Custom themes

You can write a custom theme. A custom theme replaces a default theme that has the same name.

Put your custom theme in the `~/.config/teeup/themes/<name>/` directory as `dark.toml` and `light.toml`. The format of a custom theme is the same as the format of a default theme. Copy a default theme. Change the values.

You must keep all the keys. Each value must be a hex color (`#rrggbb`) or a simple name. A simple name contains letters, digits, spaces, and the characters `. _ ( ) + -`. A simple name must start with a letter or a digit (for example, `Catppuccin Mocha`). You must also include `mode = "dark"` in `dark.toml`. You must also include `mode = "light"` in `light.toml`.
