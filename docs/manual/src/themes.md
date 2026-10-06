# Themes

teeup has four themes: `catppuccin`, `everforest`, `gruvbox`, and `tokyo-night`. Every theme has a dark palette and a light palette. When macOS changes the appearance, WezTerm, Zed, VS Code, and Emacs change palettes. Terminal.app, Starship, and bat select the palette that matches the appearance when teeup runs or when a new shell starts. After you change macOS between light and dark, run `teeup theme set --reload` and open a new window.

| Command | What it does |
|---|---|
| `teeup theme set <name>` | Change the theme in all applications. |
| `teeup theme set --reload` | Apply the current theme again. Run this command if you manually change or delete a file. |
| `teeup theme current` | Show the current theme. |
| `teeup theme list` | Show all available themes. |

<!-- SCREENSHOT: The theme picker from \`teeup theme set\` showing the available themes. -->

You can also use the Theme row in the menu (`teeup menu style.theme`) to select a theme from a list.

## What is themed

A theme applies to WezTerm, Terminal.app, Starship, bat, Zed, VS Code, Neovim, and Emacs (the starter and Doom flavors).

teeup disables the default Doom template theme so that the teeup theme applies, but your own `doom-theme` setting overrides it.

When you set a theme, teeup creates a Terminal.app profile named `teeup <Theme> <Mode>` (for example, `teeup Tokyo Night Dark`). The new profile becomes the default and startup profile, so a new Terminal.app window or a restart uses it. teeup does not change your other profiles. If you remove the Terminal.app integration (`teeup remove terminal-app`), teeup restores your old default profile.

## Custom themes

You can write a custom theme, which replaces a teeup theme that has the same name.

Put your custom theme in `~/.config/teeup/themes/<name>/` as `dark.toml` and `light.toml`, in the same format as a teeup theme. To start, copy a teeup theme and change the values.

You must keep all the keys. Each value must be a hex color (`#rrggbb`) or a simple name. A simple name contains only letters, digits, spaces, and the characters `. _ ( ) + -`, and starts with a letter or a digit (for example, `Catppuccin Mocha`). You must also include `mode = "dark"` in `dark.toml` and `mode = "light"` in `light.toml`.
