# Themes

teeup comes with four themes: `catppuccin`, `everforest`, `gruvbox`, and `tokyo-night`. Every theme has a dark and a light palette. WezTerm, Zed, VS Code and Emacs switch between them on their own when macOS changes appearance. Terminal.app, Starship and bat pick the palette that matches the appearance when teeup last ran, or when a new shell starts, so after switching macOS between light and dark, run `teeup theme set --reload` and open a new window.

| Command | What it does |
|---|---|
| `teeup theme set <name>` | Switch every app to the theme. |
| `teeup theme set --reload` | Re-render the current theme. Useful if a file was deleted or changed by hand. |
| `teeup theme current` | Show the current theme. |
| `teeup theme list` | Show all available themes. |

<!-- SCREENSHOT: The theme picker from \`teeup theme set\` showing the available themes. -->

You can also use the menu's Theme row (`teeup menu style.theme`) to pick one from a list.

## What is themed

A theme reaches WezTerm, Terminal.app, Starship, bat, Zed, VS Code, Neovim, and Emacs (both the starter and Doom flavors).

Setting a theme generates a profile in Terminal.app named `teeup <Theme> <Mode>` (for example, `teeup Tokyo Night Dark`). The new profile becomes the default and startup profile, so a new Terminal window or a restart picks it up. teeup never touches your own profiles. If you decide to remove the Terminal.app integration (`teeup remove terminal-app`), your old default profile is restored.

## Custom themes

You can write your own theme. A custom theme wins over a shipped theme of the same name.

Put it in `~/.config/teeup/themes/<name>/` as `dark.toml` and `light.toml`. A custom theme looks exactly like a shipped theme, so the easiest way to start is to copy one of the shipped themes and change the values.

Every key must stay. Each value must be a hex colour (`#rrggbb`) or a plain name: letters, digits, spaces, and the characters `. _ ( ) + -`, starting with a letter or digit (such as `Catppuccin Mocha`). You also must include `mode = "dark"` in `dark.toml` and `mode = "light"` in `light.toml`.
